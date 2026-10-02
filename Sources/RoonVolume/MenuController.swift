import AppKit
import ServiceManagement
import VolumeCore

struct MenuState {
  var snapshot: Snapshot
  var eligible: Set<String>
  var preferred: String?
  var useMac: Bool
  var route: Route
  var captureReady: Bool
  var helperError: String?
}

enum MenuAction {
  case restoreAccess, toggleMac
  case selectTarget(String?)
  case toggleOutput(String)
  case setup, configureTide, toggleLogin, quit
}

private final class ActionBox: NSObject {
  let action: MenuAction
  init(_ action: MenuAction) { self.action = action }
}

final class MenuController: NSObject, NSMenuDelegate {
  let menu = NSMenu()
  var state: (() -> MenuState)?
  var onAction: ((MenuAction) -> Void)?

  override init() {
    super.init()
    menu.delegate = self
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    guard let state = state?() else { return }
    menu.removeAllItems()
    add(
      state.helperError
        ?? (state.snapshot.connected
          ? "Connected to \(state.snapshot.core ?? "Roon")"
          : "Waiting for Roon · enable extension in Settings"),
      to: menu)
    if !state.captureReady {
      add("Keyboard access unavailable · restore access…", to: menu, action: .restoreAccess)
    }
    if let status = state.snapshot.tideStatus { add("Tide16 · \(status)", to: menu) }
    switch state.route {
    case .mac:
      add("Keys control Mac volume", to: menu)
    case .choose:
      add("Multiple rooms playing · choose a target below", to: menu)
    case .outputs(let ids):
      let names = state.snapshot.zones.flatMap(\.outputs).filter { ids.contains($0.outputID) }.map(
        \.displayName)
      add("Keys control \(names.joined(separator: " + "))", to: menu)
    }
    menu.addItem(.separator())
    add("Use Mac volume", to: menu, action: .toggleMac, checked: state.useMac)
    let all = Dictionary(
      state.snapshot.zones.flatMap(\.outputs).map { ($0.outputID, $0) },
      uniquingKeysWith: { a, _ in a }
    ).values.sorted { $0.displayName < $1.displayName }
    let targets = NSMenu()
    add(
      "Ask when multiple rooms play", to: targets, action: .selectTarget(nil),
      checked: state.preferred == nil)
    for output in all where state.eligible.contains(output.outputID) {
      add(
        output.displayName, to: targets, action: .selectTarget(output.outputID),
        checked: state.preferred == output.outputID)
    }
    submenu("When multiple rooms play", child: targets, parent: menu)
    let outputs = NSMenu()
    for output in all {
      let suffix = output.volume?.controllable == true ? "" : " (no volume control)"
      add(
        output.displayName + suffix, to: outputs, action: .toggleOutput(output.outputID),
        checked: state.eligible.contains(output.outputID))
    }
    for id in state.eligible.sorted() where !all.contains(where: { $0.outputID == id }) {
      add("Unavailable output · \(id)", to: outputs, action: .toggleOutput(id), checked: true)
    }
    if outputs.items.isEmpty { add("Outputs appear after connecting to Roon", to: outputs) }
    submenu("Controlled outputs", child: outputs, parent: menu)
    menu.addItem(.separator())
    add("Configure Tide16…", to: menu, action: .configureTide)
    add("Setup instructions…", to: menu, action: .setup)
    add(
      "Launch at login", to: menu, action: .toggleLogin,
      checked: SMAppService.mainApp.status == .enabled)
    add("Quit Roon Volume", to: menu, action: .quit)
  }

  private func submenu(_ title: String, child: NSMenu, parent: NSMenu) {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.submenu = child
    parent.addItem(item)
  }

  private func add(
    _ title: String, to menu: NSMenu, action: MenuAction? = nil, checked: Bool = false
  ) {
    let item = NSMenuItem(
      title: title, action: action == nil ? nil : #selector(select(_:)), keyEquivalent: "")
    item.target = self
    item.state = checked ? .on : .off
    if let action { item.representedObject = ActionBox(action) } else { item.isEnabled = false }
    menu.addItem(item)
  }

  @objc private func select(_ sender: NSMenuItem) {
    guard let box = sender.representedObject as? ActionBox else { return }
    onAction?(box.action)
  }
}
