import AppKit
import ApplicationServices

final class Permissions {
  private let keys: MediaKeys
  private var timer: Timer?
  private(set) var trusted = false
  private(set) var captureReady = false
  var onChange: (() -> Void)?

  init(keys: MediaKeys) { self.keys = keys }

  func start() {
    check()
    let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.check() }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  private func check() {
    let oldTrusted = trusted
    let oldCapture = captureReady
    trusted = AXIsProcessTrusted()
    if trusted && !captureReady { captureReady = keys.start() }
    if !trusted && captureReady {
      keys.stop()
      captureReady = false
    }
    if trusted != oldTrusted || captureReady != oldCapture { onChange?() }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    keys.stop()
    captureReady = false
  }

  func openSettings() {
    let options =
      [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
    NSWorkspace.shared.open(
      URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
  }

  func restoreAccess() {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = "Restore volume-key access"
    alert.informativeText =
      "macOS is not allowing Roon Volume to capture your volume keys. Locally built updates can invalidate the previous permission.\n\nIn System Settings → Privacy & Security → Accessibility, turn Roon Volume off and back on. If that does not restore access, remove its entry and add this app again:\n\n\(Bundle.main.bundlePath)\n\nRoon Volume checks for restored access automatically. Your Roon pairing and selected outputs are saved."
    alert.addButton(withTitle: "Open Accessibility Settings")
    alert.addButton(withTitle: "Later")
    if alert.runModal() == .alertFirstButtonReturn { openSettings() }
  }
}
