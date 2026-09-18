import Foundation

public struct Volume: Codable, Equatable {
  public var type: String
  public var value: Double?
  public var isMuted: Bool?
  public var isFixed: Bool?
  public var controllable: Bool { isFixed != true }

  private enum CodingKeys: String, CodingKey {
    case type, value
    case isMuted = "is_muted"
    case isFixed = "is_fixed"
  }
}
public struct Output: Codable, Equatable {
  public var outputID: String
  public var displayName: String
  public var volume: Volume?

  private enum CodingKeys: String, CodingKey {
    case outputID = "output_id"
    case displayName = "display_name"
    case volume
  }
}
public struct Zone: Codable, Equatable {
  public var zoneID: String
  public var displayName: String
  public var state: String
  public var outputs: [Output]

  private enum CodingKeys: String, CodingKey {
    case zoneID = "zone_id"
    case displayName = "display_name"
    case state, outputs
  }
}
public struct Snapshot: Codable {
  public var connected: Bool
  public var core: String?
  public var generation: Int
  public var zones: [Zone]
  public init(connected: Bool = false, core: String? = nil, generation: Int = 0, zones: [Zone] = [])
  {
    self.connected = connected
    self.core = core
    self.generation = generation
    self.zones = zones
  }
}
public enum Route: Equatable {
  case mac, choose
  case outputs([String])
}
public enum Routing {
  public static func route(
    _ snapshot: Snapshot, eligible: Set<String>, preferred: String?, useMac: Bool
  ) -> Route {
    guard snapshot.connected, !useMac else { return .mac }
    let playing = snapshot.zones.filter { $0.state == "playing" }.compactMap { zone -> [String]? in
      let ids = zone.outputs.filter {
        eligible.contains($0.outputID) && $0.volume?.controllable == true
      }.map(\.outputID)
      return ids.isEmpty ? nil : ids
    }
    guard !playing.isEmpty else { return .mac }
    if playing.count == 1 { return .outputs(playing[0]) }
    if let preferred, let ids = playing.first(where: { $0.contains(preferred) }) {
      return .outputs(ids)
    }
    return .choose
  }
}
