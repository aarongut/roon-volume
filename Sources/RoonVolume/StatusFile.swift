import Foundation

final class StatusFile {
  private var lastWritten: Data?
  func update(trusted: Bool, captureReady: Bool, connected: Bool) {
    let status: [String: Any] = [
      "accessibilityTrusted": trusted,
      "keyboardCaptureActive": captureReady,
      "roonConnected": connected,
      "appPath": Bundle.main.bundlePath,
    ]
    guard
      let data = try? JSONSerialization.data(
        withJSONObject: status, options: [.prettyPrinted, .sortedKeys]),
      data != lastWritten
    else { return }
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
      0
    ].appendingPathComponent("RoonVolume")
    do {
      try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
      try data.write(to: support.appendingPathComponent("status.json"), options: .atomic)
      lastWritten = data
    } catch {
      // Leave the cached value unchanged so a future state update can retry.
    }
  }
}
