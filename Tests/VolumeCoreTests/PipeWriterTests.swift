import Darwin
import Foundation
import Testing

@testable import VolumeCore

@Suite(.serialized)
struct PipeWriterTests {
  @Test func brokenPipeReportsFailureWithoutKillingProcess() async throws {
    let old = signal(SIGPIPE, SIG_IGN)
    defer { signal(SIGPIPE, old) }
    let pipe = Pipe()
    try pipe.fileHandleForReading.close()
    await withCheckedContinuation { continuation in
      do {
        let writer = try PipeWriter(handle: pipe.fileHandleForWriting) { continuation.resume() }
        writer.send(Data("command\n".utf8))
      } catch {
        Issue.record("Writer creation failed: \(error)")
        continuation.resume()
      }
    }
    try pipe.fileHandleForWriting.close()
  }

  @Test func fullPipeIsAsynchronousAndTimesOut() async throws {
    let pipe = Pipe()
    let started = ProcessInfo.processInfo.systemUptime
    await withCheckedContinuation { continuation in
      do {
        let writer = try PipeWriter(handle: pipe.fileHandleForWriting) { continuation.resume() }
        writer.send(Data(repeating: 1, count: 1_000_000))
        #expect(ProcessInfo.processInfo.systemUptime - started < 0.1)
      } catch {
        Issue.record("Writer creation failed: \(error)")
        continuation.resume()
      }
    }
    #expect(ProcessInfo.processInfo.systemUptime - started < 2)
    try pipe.fileHandleForReading.close()
    try pipe.fileHandleForWriting.close()
  }
}
