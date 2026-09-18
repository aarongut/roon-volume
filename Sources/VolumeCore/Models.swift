import Foundation

public struct Volume: Codable, Equatable {
    public var type: String
    public var value: Double?
    public var is_muted: Bool?
    public var is_fixed: Bool?
    public var controllable: Bool { is_fixed != true }
}
public struct Output: Codable, Equatable {
    public var output_id: String
    public var display_name: String
    public var volume: Volume?
}
public struct Zone: Codable, Equatable {
    public var zone_id: String
    public var display_name: String
    public var state: String
    public var outputs: [Output]
}
public struct Snapshot: Codable {
    public var connected: Bool
    public var core: String?
    public var generation: Int
    public var zones: [Zone]
    public init(connected: Bool = false, core: String? = nil, generation: Int = 0, zones: [Zone] = []) {
        self.connected = connected; self.core = core; self.generation = generation; self.zones = zones
    }
}
public enum Route: Equatable {
    case mac, choose, outputs([String])
}
public enum Routing {
    public static func route(_ snapshot: Snapshot, eligible: Set<String>, preferred: String?, useMac: Bool) -> Route {
        guard snapshot.connected, !useMac else { return .mac }
        let playing = snapshot.zones.filter { $0.state == "playing" }.compactMap { zone -> [String]? in
            let ids = zone.outputs.filter { eligible.contains($0.output_id) && $0.volume?.controllable == true }.map(\.output_id)
            return ids.isEmpty ? nil : ids
        }
        guard !playing.isEmpty else { return .mac }
        if playing.count == 1 { return .outputs(playing[0]) }
        if let preferred, let ids = playing.first(where: { $0.contains(preferred) }) { return .outputs(ids) }
        return .choose
    }
}
