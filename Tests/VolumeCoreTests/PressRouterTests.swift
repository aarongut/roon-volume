import Testing

@testable import VolumeCore

struct PressRouterTests {
  @Test func ownedPressSurvivesDisconnectAndReusedGeneration() {
    var router = PressRouter()
    let first = router.handle(
      .up, down: true, repeating: false, route: .outputs(["a"]), generation: 1, connected: true,
      useMac: false, now: 1)
    #expect(first.command == ["a"])
    router.invalidate()
    let repeatKey = router.handle(
      .up, down: true, repeating: true, route: .outputs(["b"]), generation: 1, connected: true,
      useMac: false, now: 2)
    #expect(repeatKey.consumed && repeatKey.command == nil)
    let release = router.handle(
      .up, down: false, repeating: false, route: .mac, generation: 1, connected: false,
      useMac: false, now: 3)
    #expect(release.consumed)
    let next = router.handle(
      .up, down: true, repeating: false, route: .mac, generation: 1, connected: false,
      useMac: false, now: 4)
    #expect(!next.consumed)
  }

  @Test func repeatsPinTargetAndGeneration() {
    var router = PressRouter()
    _ = router.handle(
      .down, down: true, repeating: false, route: .outputs(["a"]), generation: 1, connected: true,
      useMac: false, now: 1)
    #expect(
      router.handle(
        .down, down: true, repeating: true, route: .outputs(["b"]), generation: 1, connected: true,
        useMac: false, now: 2
      ).command == ["a"])
    #expect(
      router.handle(
        .down, down: true, repeating: true, route: .outputs(["b"]), generation: 2, connected: true,
        useMac: false, now: 3
      ).command == nil)
    #expect(
      router.handle(
        .down, down: false, repeating: false, route: .mac, generation: 2, connected: true,
        useMac: false, now: 4
      ).consumed)
  }

  @Test func throttlesRepeatsButAllowsNewPressesAndIgnoresMuteRepeats() {
    var router = PressRouter()
    _ = router.handle(
      .up, down: true, repeating: false, route: .outputs(["a"]), generation: 1, connected: true,
      useMac: false, now: 1)
    #expect(
      router.handle(
        .up, down: true, repeating: true, route: .outputs(["a"]), generation: 1, connected: true,
        useMac: false, now: 1.05
      ).command == nil)
    #expect(
      router.handle(
        .up, down: true, repeating: true, route: .outputs(["a"]), generation: 1, connected: true,
        useMac: false, now: 1.13
      ).command == ["a"])
    #expect(
      router.handle(
        .mute, down: true, repeating: false, route: .outputs(["a"]), generation: 1, connected: true,
        useMac: false, now: 1.14
      ).command == ["a"])
    #expect(
      router.handle(
        .mute, down: true, repeating: true, route: .outputs(["a"]), generation: 1, connected: true,
        useMac: false, now: 2
      ).command == nil)
  }

  @Test func macPressNeverAcquiresRoonAndOrphanEventsPassThrough() {
    var router = PressRouter()
    #expect(
      !router.handle(
        .up, down: true, repeating: true, route: .outputs(["a"]), generation: 1, connected: true,
        useMac: false, now: 1
      ).consumed)
    #expect(
      !router.handle(
        .up, down: false, repeating: false, route: .outputs(["a"]), generation: 1, connected: true,
        useMac: false, now: 1
      ).consumed)
    _ = router.handle(
      .up, down: true, repeating: false, route: .mac, generation: 1, connected: false,
      useMac: false, now: 1)
    #expect(
      !router.handle(
        .up, down: true, repeating: true, route: .outputs(["a"]), generation: 2, connected: true,
        useMac: false, now: 2
      ).consumed)
    #expect(
      !router.handle(
        .up, down: false, repeating: false, route: .outputs(["a"]), generation: 2, connected: true,
        useMac: false, now: 3
      ).consumed)
  }

  @Test func choicePressAndMacOverrideKeepKeyUpOwnership() {
    var router = PressRouter()
    let first = router.handle(
      .up, down: true, repeating: false, route: .choose, generation: 1, connected: true,
      useMac: false, now: 1)
    #expect(first.chooseTarget && first.consumed)
    #expect(
      !router.handle(
        .up, down: true, repeating: true, route: .outputs(["a"]), generation: 1, connected: true,
        useMac: false, now: 2
      ).chooseTarget)
    #expect(
      router.handle(
        .up, down: false, repeating: false, route: .outputs(["a"]), generation: 1, connected: true,
        useMac: false, now: 3
      ).consumed)
    _ = router.handle(
      .down, down: true, repeating: false, route: .outputs(["a"]), generation: 1, connected: true,
      useMac: false, now: 4)
    let overridden = router.handle(
      .down, down: true, repeating: true, route: .mac, generation: 1, connected: true, useMac: true,
      now: 5)
    #expect(overridden.consumed && overridden.command == nil)
    #expect(
      router.handle(
        .down, down: false, repeating: false, route: .mac, generation: 1, connected: true,
        useMac: true, now: 6
      ).consumed)
  }

  @Test func restartBackoffCapsAndResets() {
    var backoff = RestartBackoff()
    #expect((0..<7).map { _ in backoff.nextDelay() } == [3, 6, 12, 24, 48, 60, 60])
    backoff.reset()
    #expect(backoff.nextDelay() == 3)
  }
}
