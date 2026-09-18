import Foundation
import VolumeCore

final class Helper {
  var onMessage: ((Data) -> Void)?
  var onExit: (() -> Void)?
  private var process: Process?
  private var input: FileHandle?
  private var output: FileHandle?
  private var stderr: FileHandle?
  private var writer: PipeWriter?
  private var buffer = Data()
  private var session = UUID()

  func start() throws {
    stop()
    let resources = Bundle.main.resourceURL!
    let node = resources.appendingPathComponent("node")
    let script = resources.appendingPathComponent("helper/index.cjs")
    guard FileManager.default.isExecutableFile(atPath: node.path) else {
      throw NSError(domain: "Missing bundled runtime", code: 1)
    }
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
      0
    ].appendingPathComponent("RoonVolume")
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    let log = support.appendingPathComponent("helper.log")
    let previous = support.appendingPathComponent("helper.log.1")
    if FileManager.default.fileExists(atPath: log.path) {
      if FileManager.default.fileExists(atPath: previous.path) {
        try FileManager.default.removeItem(at: previous)
      }
      try FileManager.default.moveItem(at: log, to: previous)
    }
    try Data().write(to: log)
    let p = Process()
    let stdin = Pipe()
    let stdout = Pipe()
    p.executableURL = node
    p.arguments = [script.path, support.path]
    p.standardInput = stdin
    p.standardOutput = stdout
    stderr = try FileHandle(forWritingTo: log)
    p.standardError = stderr
    input = stdin.fileHandleForWriting
    output = stdout.fileHandleForReading
    process = p
    let session = UUID()
    self.session = session
    do {
      writer = try PipeWriter(handle: stdin.fileHandleForWriting) { [weak self] in
        guard let self, self.session == session else { return }
        // The termination handler is the sole source of onExit notifications.
        self.writer?.close()
        self.writer = nil
        try? self.input?.close()
        self.input = nil
        if self.process?.isRunning == true { self.process?.terminate() }
      }
      stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
        let data = handle.availableData
        guard !data.isEmpty else {
          handle.readabilityHandler = nil
          return
        }
        DispatchQueue.main.async {
          guard self?.session == session else { return }
          self?.receive(data)
        }
      }
      p.terminationHandler = { [weak self] _ in
        DispatchQueue.main.async {
          guard let self, self.session == session else { return }
          self.cleanup()
          self.session = UUID()
          self.process = nil
          self.onExit?()
        }
      }
      try p.run()
      // Parent does not need the child's ends of either pipe.
      try? stdin.fileHandleForReading.close()
      try? stdout.fileHandleForWriting.close()
    } catch {
      stop()
      throw error
    }
  }

  private func receive(_ data: Data) {
    buffer.append(data)
    while let index = buffer.firstIndex(of: 10) {
      let line = Data(buffer[..<index])
      buffer.removeSubrange(...index)
      onMessage?(line)
    }
    if buffer.count > 2_000_000 { buffer.removeAll() }
  }

  func send(_ message: [String: Any]) {
    guard var data = try? JSONSerialization.data(withJSONObject: message) else { return }
    data.append(10)
    writer?.send(data)
  }

  private func cleanup() {
    writer?.close()
    writer = nil
    output?.readabilityHandler = nil
    try? input?.close()
    try? output?.close()
    try? stderr?.close()
    input = nil
    output = nil
    stderr = nil
    buffer.removeAll()
  }

  func stop() {
    session = UUID()
    cleanup()
    if process?.isRunning == true { process?.terminate() }
    process = nil
  }
}
