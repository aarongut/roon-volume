import Darwin
import Foundation

// Owns a duplicated, nonblocking descriptor. Writes never run on the event-tap thread.
public final class PipeWriter {
  private let queue = DispatchQueue(label: "tech.frat.roon-volume.helper-writes")
  private let lock = NSLock()
  private var pending = 0
  private var descriptor: Int32
  private var closed = false
  private let onFailure: () -> Void

  public init(handle: FileHandle, onFailure: @escaping () -> Void) throws {
    descriptor = dup(handle.fileDescriptor)
    guard descriptor >= 0 else { throw POSIXError(.EBADF) }
    let flags = fcntl(descriptor, F_GETFL)
    guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
      Darwin.close(descriptor)
      throw POSIXError(.EIO)
    }
    self.onFailure = onFailure
  }

  public func send(_ data: Data) {
    lock.lock()
    guard !closed, pending < 8 else {
      lock.unlock()
      return
    }
    pending += 1
    lock.unlock()
    queue.async { [self] in
      defer {
        lock.lock()
        pending -= 1
        lock.unlock()
      }
      lock.lock()
      let active = !closed
      lock.unlock()
      guard active else { return }
      var failed = false
      let deadline = ProcessInfo.processInfo.systemUptime + 0.1
      data.withUnsafeBytes { bytes in
        var offset = 0
        while offset < bytes.count {
          let count = Darwin.write(
            descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
          if count > 0 {
            offset += count
            continue
          }
          if count < 0 && errno == EINTR { continue }
          if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
              failed = true
              return
            }
            var fd = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
            _ = poll(&fd, 1, 10)
            continue
          }
          failed = true
          return
        }
      }
      if failed {
        close()
        DispatchQueue.main.async(execute: onFailure)
      }
    }
  }

  public func close() {
    lock.lock()
    guard !closed else {
      lock.unlock()
      return
    }
    closed = true
    lock.unlock()
    queue.async { [self] in
      Darwin.close(descriptor)
      descriptor = -1
    }
  }
}
