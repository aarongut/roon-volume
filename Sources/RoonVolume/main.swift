import AppKit
import ApplicationServices
import ServiceManagement
import VolumeCore

final class Overlay {
    private var panel: NSPanel?
    private var hide: DispatchWorkItem?
    func show(_ text: String) {
        hide?.cancel()
        if panel == nil {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .floating; p.isOpaque = false; p.backgroundColor = .clear
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; p.ignoresMouseEvents = true
            let effect = NSVisualEffectView(frame: p.contentView!.bounds)
            effect.material = .hudWindow; effect.state = .active; effect.wantsLayer = true; effect.layer?.cornerRadius = 10
            effect.autoresizingMask = [.width, .height]
            p.contentView = effect; panel = p
        }
        guard let panel else { return }
        panel.contentView?.subviews.forEach { $0.removeFromSuperview() }
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 16, weight: .medium); label.alignment = .center
        let maxWidth = min(600, (NSScreen.main?.visibleFrame.width ?? 640) - 40)
        let measured = label.sizeThatFits(NSSize(width: maxWidth - 24, height: .greatestFiniteMagnitude))
        let size = NSSize(width: ceil(measured.width) + 24, height: ceil(measured.height) + 12)
        panel.setContentSize(size)
        label.frame = NSRect(x: 12, y: 6, width: size.width - 24, height: size.height - 12)
        panel.contentView?.addSubview(label)
        if let screen = NSScreen.main { panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.minY + 100)) }
        panel.orderFrontRegardless()
        let work = DispatchWorkItem { panel.orderOut(nil) }; hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let helper = Helper(), keys = MediaKeys(), overlay = Overlay()
    private var item: NSStatusItem!
    private var snapshot = Snapshot()
    private let defaults = UserDefaults.standard
    private var eligible: Set<String> { Set(defaults.stringArray(forKey: "outputs") ?? []) }
    private var preferred: String? { defaults.string(forKey: "preferred") }
    private var useMac: Bool { defaults.bool(forKey: "useMac") }
    private var route: Route { Routing.route(snapshot, eligible: eligible, preferred: preferred, useMac: useMac) }
    private var presses: [String: Route] = [:]
    private var pressGenerations: [String: Int] = [:]
    private var lastCommand: TimeInterval = 0
    private var overlayIDs: [String] = []
    private var permissionTimer: Timer?
    private var captureReady = false
    private var quitting = false
    private var helperError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        migratePreferences()
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "Roon Volume")
        helper.onMessage = { [weak self] in self?.message($0) }
        helper.onExit = { [weak self] in
            guard let self, !self.quitting else { return }
            self.snapshot = Snapshot(); self.overlayIDs = []; self.helperError = "Roon helper disconnected"; self.refreshMenu()
            self.pressGenerations = self.pressGenerations.mapValues { _ in -1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.startHelper() }
        }
        keys.handler = { [weak self] action, down, repeating in self?.key(action, down: down, repeating: repeating) ?? false }
        startHelper(); checkPermission(); refreshMenu()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.checkPermission() }
        if !defaults.bool(forKey: "welcomed") {
            defaults.set(true, forKey: "welcomed")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.setup() }
        } else if !AXIsProcessTrusted() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.restoreKeyboardAccess() }
        }
    }
    private func migratePreferences() {
        guard !defaults.bool(forKey: "migratedFromAaronIdentifier") else { return }
        let legacy = defaults.persistentDomain(forName: "com.aaron.roon-volume") ?? [:]
        let current = defaults.persistentDomain(forName: "tech.frat.roon-volume") ?? [:]
        for key in ["outputs", "preferred", "useMac", "welcomed"] where current[key] == nil {
            if let value = legacy[key] { defaults.set(value, forKey: key) }
        }
        defaults.set(true, forKey: "migratedFromAaronIdentifier")
    }
    private func startHelper() {
        guard !quitting else { return }
        helper.stop()
        do { try helper.start(); helperError = nil; configure() }
        catch { helperError = "Unable to start Roon helper: \(error.localizedDescription)"; refreshMenu() }
    }
    private func configure() { helper.send(["type": "configure", "output_ids": Array(eligible)]) }
    private func message(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = object["type"] as? String else { return }
        if type == "snapshot", let fresh = try? JSONDecoder().decode(Snapshot.self, from: data) {
            if fresh.generation != snapshot.generation { overlayIDs = [] }
            snapshot = fresh; helperError = nil; refreshMenu()
            if !overlayIDs.isEmpty { showVolumes(overlayIDs) }
        } else if type == "result", let generation = object["generation"] as? Int, generation == snapshot.generation {
            if let error = object["error"] as? String, error != "busy" { overlay.show(error); overlayIDs = [] }
        } else if type == "error", let error = object["error"] as? String { helperError = error; refreshMenu() }
    }
    private func checkPermission() {
        if AXIsProcessTrusted() {
            if !captureReady { captureReady = keys.start(); refreshMenu() }
        } else if captureReady { keys.stop(); captureReady = false; presses.removeAll(); refreshMenu() }
        writeStatus()
    }
    private func writeStatus() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RoonVolume")
        let status: [String: Any] = ["accessibilityTrusted": AXIsProcessTrusted(), "keyboardCaptureActive": captureReady,
                                   "roonConnected": snapshot.connected, "appPath": Bundle.main.bundlePath]
        if let data = try? JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: support.appendingPathComponent("status.json"), options: .atomic)
        }
    }
    private func key(_ action: String, down: Bool, repeating: Bool) -> Bool {
        if !down { pressGenerations.removeValue(forKey: action); let prior = presses.removeValue(forKey: action); return prior != nil && prior != .mac }
        let selected: Route
        if let prior = presses[action], repeating { selected = prior }
        else { selected = route; presses[action] = selected; pressGenerations[action] = snapshot.generation }
        switch selected {
        case .mac: return false
        case .choose: overlay.show("Choose a Roon zone from the menu"); return true
        case .outputs(let ids):
            guard snapshot.connected, !useMac, pressGenerations[action] == snapshot.generation else { return true }
            if action == "mute" && repeating { return true }
            let now = ProcessInfo.processInfo.systemUptime
            guard !repeating || now - lastCommand >= 0.12 else { return true }
            lastCommand = now; overlayIDs = ids
            helper.send(["type": "command", "id": UUID().uuidString, "generation": snapshot.generation, "output_ids": ids, "action": action])
            showVolumes(ids)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in if let self, ProcessInfo.processInfo.systemUptime - self.lastCommand >= 1.5 { self.overlayIDs = [] } }
            return true
        }
    }
    private func showVolumes(_ ids: [String]) {
        let outputs = snapshot.zones.flatMap(\.outputs).filter { ids.contains($0.output_id) }
        let text = outputs.map { output -> String in
            let value: String
            if output.volume?.is_muted == true { value = "Muted" }
            else if let number = output.volume?.value { value = String(format: "%g", number) + (output.volume?.type == "db" ? " dB" : "") }
            else { value = "Volume" }
            return "\(output.display_name): \(value)"
        }.joined(separator: "\n")
        if !text.isEmpty { overlay.show(text) }
    }
    private func add(_ title: String, to menu: NSMenu, action: Selector? = nil, represented: String? = nil, checked: Bool = false) {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self; entry.representedObject = represented; entry.state = checked ? .on : .off
        if action == nil { entry.isEnabled = false }; menu.addItem(entry)
    }
    private func refreshMenu() {
        guard item != nil else { return }
        let menu = NSMenu()
        add(helperError ?? (snapshot.connected ? "Connected to \(snapshot.core ?? "Roon")" : "Waiting for Roon · enable extension in Settings"), to: menu)
        if !captureReady { add("Keyboard access unavailable · restore access…", to: menu, action: #selector(restoreKeyboardAccess)) }
        switch route {
        case .mac: add("Keys control Mac volume", to: menu)
        case .choose: add("Both rooms playing · choose a target below", to: menu)
        case .outputs(let ids):
            let names = snapshot.zones.flatMap(\.outputs).filter { ids.contains($0.output_id) }.map(\.display_name)
            add("Keys control \(names.joined(separator: " + "))", to: menu)
        }
        menu.addItem(.separator())
        add("Use Mac volume", to: menu, action: #selector(toggleMac), checked: useMac)
        let all = Dictionary(snapshot.zones.flatMap(\.outputs).map { ($0.output_id, $0) }, uniquingKeysWith: { a, _ in a }).values.sorted { $0.display_name < $1.display_name }
        let targets = NSMenu()
        add("Ask when both rooms play", to: targets, action: #selector(selectTarget), checked: preferred == nil)
        for o in all where eligible.contains(o.output_id) { add(o.display_name, to: targets, action: #selector(selectTarget), represented: o.output_id, checked: preferred == o.output_id) }
        let targetItem = NSMenuItem(title: "When both rooms play", action: nil, keyEquivalent: ""); targetItem.submenu = targets; menu.addItem(targetItem)
        let outputs = NSMenu()
        for o in all {
            add(o.display_name + (o.volume?.controllable == true ? "" : " (no volume control)"), to: outputs, action: #selector(toggleOutput), represented: o.output_id, checked: eligible.contains(o.output_id))
        }
        for id in eligible where !all.contains(where: { $0.output_id == id }) { add("Unavailable output · \(id)", to: outputs, action: #selector(toggleOutput), represented: id, checked: true) }
        if outputs.items.isEmpty { add("Outputs appear after connecting to Roon", to: outputs) }
        let outputItem = NSMenuItem(title: "Controlled outputs (select your 8C and WiiM)", action: nil, keyEquivalent: ""); outputItem.submenu = outputs; menu.addItem(outputItem)
        menu.addItem(.separator())
        add("Setup instructions…", to: menu, action: #selector(setup))
        add("Launch at login", to: menu, action: #selector(toggleLogin), checked: SMAppService.mainApp.status == .enabled)
        add("Quit Roon Volume", to: menu, action: #selector(quit))
        item.menu = menu
    }
    @objc private func toggleMac() { defaults.set(!useMac, forKey: "useMac"); refreshMenu() }
    @objc private func toggleOutput(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        var ids = eligible
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        defaults.set(Array(ids), forKey: "outputs"); configure(); refreshMenu()
    }
    @objc private func selectTarget(_ sender: NSMenuItem) { defaults.set(sender.representedObject as? String, forKey: "preferred"); defaults.set(false, forKey: "useMac"); refreshMenu() }
    @objc private func permission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc private func restoreKeyboardAccess() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Restore volume-key access"
        alert.informativeText = "macOS is not allowing Roon Volume to capture your volume keys. Locally built updates can invalidate the previous permission.\n\nIn System Settings → Privacy & Security → Accessibility, turn Roon Volume off and back on. If that does not restore access, remove its entry and add this app again:\n\n\(Bundle.main.bundlePath)\n\nRoon Volume checks for restored access automatically. Your Roon pairing and selected outputs are saved."
        alert.addButton(withTitle: "Open Accessibility Settings"); alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn { permission() }
    }
    @objc private func setup() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Set up Roon Volume"
        alert.informativeText = "1. Allow Roon Volume in System Settings → Privacy & Security → Accessibility.\n\n2. In Roon Settings → Extensions, enable Roon Volume. Allow local network access if macOS asks.\n\n3. From this app’s speaker menu, select your Dutch & Dutch 8C and WiiM under Controlled outputs.\n\nVolume and mute keys follow playback. When both rooms play separately, choose a target in the menu."
        alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Enable keyboard access")
        if alert.runModal() == .alertSecondButtonReturn { permission() }
    }
    @objc private func toggleLogin() {
        do { if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() } }
        catch { overlay.show("Login setting: \(error.localizedDescription)") }
        refreshMenu()
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { quitting = true; permissionTimer?.invalidate(); keys.stop(); helper.stop() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
