import AppKit
import Darwin
import ServiceManagement
import VolumeCore

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let helper = Helper()
  private let keys = MediaKeys()
  private let overlay = Overlay()
  private let preferences = Preferences()
  private let menuController = MenuController()
  private let statusFile = StatusFile()
  private lazy var permissions = Permissions(keys: keys)
  private var item: NSStatusItem!
  private var snapshot = Snapshot()
  private var pressRouter = PressRouter()
  private var backoff = RestartBackoff()
  private var restartWork: DispatchWorkItem?
  private var stableWork: DispatchWorkItem?
  private var overlayIDs: [String] = []
  private var overlayDeadline = 0.0
  private var overlayExpiry: DispatchWorkItem?
  private var quitting = false
  private var helperError: String?

  private var route: Route {
    Routing.route(
      snapshot, eligible: preferences.outputs, preferred: preferences.preferred,
      useMac: preferences.useMac)
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.image = NSImage(
      systemSymbolName: "speaker.wave.2", accessibilityDescription: "Roon Volume")
    menuController.state = { [weak self] in
      guard let self else {
        return MenuState(
          snapshot: Snapshot(), eligible: [], useMac: false, route: .mac, captureReady: false)
      }
      return MenuState(
        snapshot: self.snapshot, eligible: self.preferences.outputs,
        preferred: self.preferences.preferred, useMac: self.preferences.useMac,
        route: self.route, captureReady: self.permissions.captureReady,
        helperError: self.helperError)
    }
    menuController.onAction = { [weak self] in self?.perform($0) }
    // Keep this same menu attached for the lifetime of the status item.
    item.menu = menuController.menu
    helper.onMessage = { [weak self] in self?.message($0) }
    helper.onExit = { [weak self] in self?.helperStopped("Roon helper disconnected") }
    keys.handler = { [weak self] action, down, repeating in
      self?.key(action, down: down, repeating: repeating) ?? false
    }
    permissions.onChange = { [weak self] in
      guard let self else { return }
      if !self.permissions.captureReady { self.pressRouter.invalidate() }
      self.writeStatus()
    }
    startHelper()
    permissions.start()
    writeStatus()
    if !preferences.welcomed {
      preferences.welcomed = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.setup() }
    } else if !permissions.trusted {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        self?.permissions.restoreAccess()
      }
    }
  }

  private func startHelper() {
    guard !quitting else { return }
    restartWork = nil
    do {
      try helper.start()
      helperError = nil
      configure()
      let stable = DispatchWorkItem { [weak self] in self?.backoff.reset() }
      stableWork = stable
      DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: stable)
    } catch {
      helperStopped("Unable to start Roon helper: \(error.localizedDescription)")
    }
  }

  private func helperStopped(_ reason: String) {
    guard !quitting, restartWork == nil else { return }
    stableWork?.cancel()
    stableWork = nil
    snapshot = Snapshot()
    clearOverlayTracking()
    pressRouter.invalidate()
    let delay = backoff.nextDelay()
    helperError = "\(reason) · retry in \(Int(delay))s"
    writeStatus()
    let restart = DispatchWorkItem { [weak self] in self?.startHelper() }
    restartWork = restart
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: restart)
  }

  private func configure() {
    helper.send(["type": "configure", "output_ids": Array(preferences.outputs)])
  }

  private func message(_ data: Data) {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let type = object["type"] as? String
    else { return }
    if type == "snapshot", let fresh = try? JSONDecoder().decode(Snapshot.self, from: data) {
      if fresh.generation != snapshot.generation { clearOverlayTracking() }
      snapshot = fresh
      helperError = nil
      writeStatus()
      // Feedback may update the visible text, but it never extends a key press's lifetime.
      if !overlayIDs.isEmpty, ProcessInfo.processInfo.systemUptime < overlayDeadline {
        showVolumes(overlayIDs, restartTimer: false)
      }
    } else if type == "result", let generation = object["generation"] as? Int,
      generation == snapshot.generation
    {
      if let error = object["error"] as? String, error != "busy" {
        clearOverlayTracking()
        overlay.show(error)
      }
    } else if type == "error", let error = object["error"] as? String {
      helperError = error
    }
  }

  private func writeStatus() {
    statusFile.update(
      trusted: permissions.trusted, captureReady: permissions.captureReady,
      connected: snapshot.connected)
  }

  private func key(_ action: VolumeAction, down: Bool, repeating: Bool) -> Bool {
    let now = ProcessInfo.processInfo.systemUptime
    let decision = pressRouter.handle(
      action, down: down, repeating: repeating, route: route,
      generation: snapshot.generation, connected: snapshot.connected,
      useMac: preferences.useMac, now: now)
    if decision.chooseTarget { overlay.show("Choose a Roon zone from the menu") }
    if let ids = decision.command {
      helper.send([
        "type": "command", "id": UUID().uuidString, "generation": snapshot.generation,
        "output_ids": ids, "action": action.rawValue,
      ])
      overlayIDs = ids
      overlayDeadline = now + 1.5
      showVolumes(ids)
      overlayExpiry?.cancel()
      let expiry = DispatchWorkItem { [weak self] in self?.overlayIDs = [] }
      overlayExpiry = expiry
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: expiry)
    }
    return decision.consumed
  }

  private func clearOverlayTracking() {
    overlayIDs = []
    overlayExpiry?.cancel()
    overlayExpiry = nil
  }

  private func showVolumes(_ ids: [String], restartTimer: Bool = true) {
    let outputs = snapshot.zones.flatMap(\.outputs).filter { ids.contains($0.outputID) }
    let text = outputs.map { output -> String in
      let value: String
      if output.volume?.isMuted == true {
        value = "Muted"
      } else if let number = output.volume?.value {
        value = String(format: "%g", number) + (output.volume?.type == "db" ? " dB" : "")
      } else {
        value = "Volume"
      }
      return "\(output.displayName): \(value)"
    }.joined(separator: "\n")
    if !text.isEmpty {
      let symbolName =
        outputs.allSatisfy { $0.volume?.isMuted == true } ? "speaker.slash" : "speaker.wave.2"
      overlay.show(text, symbolName: symbolName, restartTimer: restartTimer)
    }
  }

  private func perform(_ action: MenuAction) {
    switch action {
    case .restoreAccess:
      permissions.restoreAccess()
    case .toggleMac:
      preferences.useMac.toggle()
    case .selectTarget(let id):
      preferences.preferred = id
      preferences.useMac = false
    case .toggleOutput(let id):
      var ids = preferences.outputs
      if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
      preferences.outputs = ids
      configure()
    case .setup:
      setup()
    case .toggleLogin:
      do {
        if SMAppService.mainApp.status == .enabled {
          try SMAppService.mainApp.unregister()
        } else {
          try SMAppService.mainApp.register()
        }
      } catch { overlay.show("Login setting: \(error.localizedDescription)") }
    case .quit:
      NSApp.terminate(nil)
    }
  }

  private func setup() {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = "Set up Roon Volume"
    alert.informativeText =
      "1. Allow Roon Volume in System Settings → Privacy & Security → Accessibility.\n\n2. In Roon Settings → Extensions, enable Roon Volume. Allow local network access if macOS asks.\n\n3. From this app’s speaker menu, select your Dutch & Dutch 8C and WiiM under Controlled outputs.\n\nVolume and mute keys follow playback. When both rooms play separately, choose a target in the menu."
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Enable keyboard access")
    if alert.runModal() == .alertSecondButtonReturn { permissions.openSettings() }
  }

  func applicationWillTerminate(_ notification: Notification) {
    quitting = true
    restartWork?.cancel()
    stableWork?.cancel()
    overlayExpiry?.cancel()
    permissions.stop()
    helper.stop()
  }
}

// A broken helper pipe must report EPIPE rather than terminate the app.
signal(SIGPIPE, SIG_IGN)
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
