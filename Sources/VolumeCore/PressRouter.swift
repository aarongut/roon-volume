public enum VolumeAction: String, CaseIterable, Hashable {
  case up, down, mute
}

public struct PressDecision: Equatable {
  public var consumed: Bool
  public var command: [String]?
  public var chooseTarget: Bool

  public init(consumed: Bool, command: [String]? = nil, chooseTarget: Bool = false) {
    self.consumed = consumed
    self.command = command
    self.chooseTarget = chooseTarget
  }
}

public struct PressRouter {
  private struct Press {
    var route: Route
    var generation: Int
    var invalidated = false
  }
  private var presses: [VolumeAction: Press] = [:]
  private var lastCommand: Double?
  public init() {}

  // Preserve ownership of key-up even when the helper restarts with a reused generation.
  public mutating func invalidate() {
    for action in Array(presses.keys) { presses[action]?.invalidated = true }
  }

  public mutating func handle(
    _ action: VolumeAction, down: Bool, repeating: Bool,
    route: Route, generation: Int, connected: Bool,
    useMac: Bool, now: Double
  ) -> PressDecision {
    if !down {
      guard let press = presses.removeValue(forKey: action) else {
        return PressDecision(consumed: false)
      }
      return PressDecision(consumed: press.route != .mac)
    }
    // A repeat without its initial key-down must not acquire a new target.
    if repeating && presses[action] == nil { return PressDecision(consumed: false) }
    if !repeating { presses[action] = Press(route: route, generation: generation) }
    guard let press = presses[action] else { return PressDecision(consumed: false) }
    switch press.route {
    case .mac:
      return PressDecision(consumed: false)
    case .choose:
      return PressDecision(consumed: true, chooseTarget: !repeating)
    case .outputs(let ids):
      guard !press.invalidated, connected, !useMac, press.generation == generation else {
        return PressDecision(consumed: true)
      }
      if repeating {
        guard action != .mute, lastCommand.map({ now - $0 >= 0.12 }) ?? true else {
          return PressDecision(consumed: true)
        }
      }
      lastCommand = now
      return PressDecision(consumed: true, command: ids)
    }
  }
}

public struct RestartBackoff {
  private var failures = 0
  public init() {}
  public mutating func nextDelay() -> Double {
    let delay = min(60, 3 * Double(1 << min(failures, 5)))
    failures += 1
    return delay
  }
  public mutating func reset() { failures = 0 }
}
