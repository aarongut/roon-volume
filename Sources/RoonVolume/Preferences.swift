import Foundation

final class Preferences {
  private enum Key: String {
    case outputs, preferred, useMac, welcomed, migratedFromAaronIdentifier
  }
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    guard !defaults.bool(forKey: Key.migratedFromAaronIdentifier.rawValue) else { return }
    let legacy = defaults.persistentDomain(forName: "com.aaron.roon-volume") ?? [:]
    let current = defaults.persistentDomain(forName: "tech.frat.roon-volume") ?? [:]
    for key in [Key.outputs, .preferred, .useMac, .welcomed] where current[key.rawValue] == nil {
      if let value = legacy[key.rawValue] { defaults.set(value, forKey: key.rawValue) }
    }
    defaults.set(true, forKey: Key.migratedFromAaronIdentifier.rawValue)
  }

  var outputs: Set<String> {
    get { Set(defaults.stringArray(forKey: Key.outputs.rawValue) ?? []) }
    set { defaults.set(Array(newValue), forKey: Key.outputs.rawValue) }
  }
  var preferred: String? {
    get { defaults.string(forKey: Key.preferred.rawValue) }
    set { defaults.set(newValue, forKey: Key.preferred.rawValue) }
  }
  var useMac: Bool {
    get { defaults.bool(forKey: Key.useMac.rawValue) }
    set { defaults.set(newValue, forKey: Key.useMac.rawValue) }
  }
  var welcomed: Bool {
    get { defaults.bool(forKey: Key.welcomed.rawValue) }
    set { defaults.set(newValue, forKey: Key.welcomed.rawValue) }
  }
}
