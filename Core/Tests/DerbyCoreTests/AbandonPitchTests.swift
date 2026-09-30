import XCTest
@testable import DerbyCore

/// `DerbyMachine.abandonPitch()` (docs/watch.md §2 "Changes to DerbyCore", §5): a lowered wrist
/// is never a called strike. Back to the top of the windup, counting nothing.
final class AbandonPitchTests: XCTestCase {
    @discardableResult
    private func run(_ m: inout DerbyMachine, seconds: Double, dt: Double = 1.0 / 60) -> [Transition] {
        var out: [Transition] = []
        var t = 0.0
        while t < seconds { out += m.tick(dt); t += dt }
        return out
    }

    private func perfectCrossing(_ m: DerbyMachine) -> SliceCrossing {
        SliceCrossing(quality: 1, progress: 1, swingAngleDegrees: 28, power: 1,
                      ball: m.ballNow, crossingPoint: m.ballNow.position)
    }

    /// A career with a streak going, so "leaves every streak where it was" has something to leave.
    private func careerWithAStreak() -> DerbyMachine {
        var t = Tally()
        t.set(.homeRunStreak, 3)
        t.set(.bestHomeRunStreak, 3)
        return DerbyMachine(seed: 1, tally: t)
    }

    func testFromThePitchBackToTheTopOfTheWindupCountingNothing() {
        var m = careerWithAStreak()
        run(&m, seconds: 0.6)
        XCTAssertEqual(m.beat, .pitch)
        let before = m
        m.abandonPitch()
        XCTAssertEqual(m.beat, .windup)
        XCTAssertEqual(m.elapsed, 0)
        XCTAssertEqual(m.tally, before.tally)
        XCTAssertEqual(m.pitch, before.pitch, "the same pitch comes again")
        XCTAssertEqual(m.streakNow, 3)
        XCTAssertEqual(m.lastCall, before.lastCall)
    }

    func testFromTheWindupStartsItAgain() {
        var m = careerWithAStreak()
        run(&m, seconds: 0.3)
        XCTAssertEqual(m.beat, .windup)
        XCTAssertGreaterThan(m.elapsed, 0)
        let before = m
        m.abandonPitch()
        XCTAssertEqual(m.beat, .windup)
        XCTAssertEqual(m.elapsed, 0)
        XCTAssertEqual(m.tally, before.tally)
        XCTAssertEqual(m.pitch, before.pitch)
    }

    /// The one thing that must never happen: a pitch left alone because the wrist went down is
    /// called. Abandon it at the last moment before the call, and the call never comes.
    func testAnAbandonedPitchIsNeverCalled() {
        var m = careerWithAStreak()
        run(&m, seconds: 0.6)
        run(&m, seconds: m.pitch.duration)
        XCTAssertEqual(m.beat, .pitch)
        m.abandonPitch()
        let out = run(&m, seconds: 0.4)
        XCTAssertFalse(out.contains { if case .called = $0 { return true } else { return false } })
        XCTAssertEqual(m.tally.pitches, 0)
        XCTAssertEqual(m.tally[.calledStrikes], 0)
        XCTAssertEqual(m.streakNow, 3)
    }

    func testTheSamePitchIsThrownAgainAndEmitsItsCueAgain() {
        var m = DerbyMachine(seed: 1)
        run(&m, seconds: 0.6)
        let thrown = m.pitch
        m.abandonPitch()
        let out = run(&m, seconds: 0.6)
        XCTAssertEqual(m.beat, .pitch)
        XCTAssertEqual(m.pitch, thrown)
        XCTAssertEqual(out.filter { $0 == .pitchThrown }.count, 1)
    }

    /// A ball already hit plays out, and a call already made stands.
    func testIgnoredOnceTheSwingOrTheCallHasHappened() {
        var hit = DerbyMachine(seed: 3)
        run(&hit, seconds: 0.6)
        hit.slice(perfectCrossing(hit))
        XCTAssertEqual(hit.beat, .contact)
        var copy = hit
        copy.abandonPitch()
        XCTAssertEqual(copy, hit)

        var called = DerbyMachine(seed: 1)
        run(&called, seconds: 0.6)
        run(&called, seconds: called.pitch.duration * 1.15 + 0.1)
        XCTAssertEqual(called.beat, .miss)
        copy = called
        copy.abandonPitch()
        XCTAssertEqual(copy, called)
    }

    /// Inside a Warm Up the thrown pitch was written down as `.taken` (§18). Abandoning it takes
    /// the placeholder off, so the re-thrown pitch is not spent twice.
    func testInsideAWarmUpThePlaceholderComesOff() {
        var t = Tally()
        t.set(.parksCleared, 1)
        var m = DerbyMachine(seed: 7, park: Park.generate(number: 2), tally: t)
        m.beginWarmUp(WarmUp.generate(day: 20260920))
        run(&m, seconds: 0.1)
        XCTAssertNotNil(m.warmUp)
        while m.beat != .pitch { m.tick(1.0 / 60) }
        XCTAssertEqual(m.warmUp?.pitches, [.taken])
        m.abandonPitch()
        XCTAssertEqual(m.warmUp?.pitches, [])
        while m.beat != .pitch { m.tick(1.0 / 60) }
        XCTAssertEqual(m.warmUp?.pitches, [.taken])
    }
}
