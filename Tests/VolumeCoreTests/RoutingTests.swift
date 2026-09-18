import Foundation
import Testing

@testable import VolumeCore

struct RoutingTests {
  func snapshot(_ zones: String, connected: Bool = true) throws -> Snapshot {
    let data = Data("{\"connected\":\(connected),\"generation\":1,\"zones\":\(zones)}".utf8)
    return try JSONDecoder().decode(Snapshot.self, from: data)
  }
  let a =
    "{\"zone_id\":\"za\",\"display_name\":\"A\",\"state\":\"playing\",\"outputs\":[{\"output_id\":\"a\",\"display_name\":\"8C\",\"volume\":{\"type\":\"db\",\"value\":-40}}]}"
  let b =
    "{\"zone_id\":\"zb\",\"display_name\":\"B\",\"state\":\"playing\",\"outputs\":[{\"output_id\":\"b\",\"display_name\":\"WiiM\",\"volume\":{\"type\":\"number\",\"value\":20}}]}"
  @Test func testRouting() throws {
    let ids: Set<String> = ["a", "b"]
    expectEqual(
      Routing.route(try snapshot("[]"), eligible: ids, preferred: nil, useMac: false), .mac)
    expectEqual(
      Routing.route(try snapshot("[\(a)]"), eligible: ids, preferred: "b", useMac: false),
      .outputs(["a"]))
    let both = try snapshot("[\(a),\(b)]")
    expectEqual(Routing.route(both, eligible: ids, preferred: nil, useMac: false), .choose)
    expectEqual(Routing.route(both, eligible: ids, preferred: "b", useMac: false), .outputs(["b"]))
    expectEqual(Routing.route(both, eligible: ids, preferred: "missing", useMac: false), .choose)
    expectEqual(Routing.route(both, eligible: ids, preferred: "b", useMac: true), .mac)
    expectEqual(
      Routing.route(
        try snapshot("[\(a)]", connected: false), eligible: ids, preferred: nil, useMac: false),
      .mac)
    expectEqual(
      Routing.route(
        try snapshot("[\(a.replacingOccurrences(of: "playing", with: "paused"))]"), eligible: ids,
        preferred: nil, useMac: false), .mac)
  }
  @Test func testGroupedOutputsExcludeOtherRoomsAndFixedVolume() throws {
    let grouped =
      "[{\"zone_id\":\"g\",\"display_name\":\"Group\",\"state\":\"playing\",\"outputs\":[{\"output_id\":\"a\",\"display_name\":\"8C\",\"volume\":{\"type\":\"db\"}},{\"output_id\":\"b\",\"display_name\":\"WiiM\",\"volume\":{\"type\":\"number\"}},{\"output_id\":\"c\",\"display_name\":\"Other\",\"volume\":{\"type\":\"number\"}}]}]"
    expectEqual(
      Routing.route(try snapshot(grouped), eligible: ["a", "b"], preferred: "a", useMac: false),
      .outputs(["a", "b"]))
    let fixed = a.replacingOccurrences(of: "\"value\":-40", with: "\"value\":-40,\"is_fixed\":true")
    expectEqual(
      Routing.route(try snapshot("[\(fixed)]"), eligible: ["a"], preferred: nil, useMac: false),
      .mac)
  }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T) { #expect(actual == expected) }
