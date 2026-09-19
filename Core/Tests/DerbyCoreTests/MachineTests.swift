import XCTest
@testable import DerbyCore

final class MachineTests: XCTestCase {
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

    func testWindupThenPitch() {
        var m = DerbyMachine(seed: 1)
        XCTAssertEqual(m.beat, .windup)
        let t = run(&m, seconds: 0.6)
        XCTAssertEqual(m.beat, .pitch)
        XCTAssertTrue(t.contains(.pitchThrown))
    }

    func testTakenPitchIsCalledAndComesBack() {
        var m = DerbyMachine(seed: 1)
        run(&m, seconds: 0.6)
        let expected: Call = m.pitch.isStrike ? .strike : .ball
        run(&m, seconds: m.pitch.duration * 1.15 + 0.1)
        XCTAssertEqual(m.beat, .miss)
        XCTAssertEqual(m.lastCall, expected)
        XCTAssertEqual(m.tally.pitches, 1)
        run(&m, seconds: 1.3)
        XCTAssertEqual(m.beat, .windup)
        XCTAssertEqual(m.tally.hits, 0)
    }

    func testMissedSliceNeverCuts() {
        var m = DerbyMachine(seed: 1)
        run(&m, seconds: 0.6)
        m.sliceMissed()
        XCTAssertEqual(m.beat, .miss)
        XCTAssertEqual(m.lastCall, .miss)
        let t = run(&m, seconds: 1.3)
        XCTAssertFalse(t.contains(.cutToWide))
        XCTAssertEqual(m.beat, .windup)
    }

    func testContactCutsFlightResultAndBack() {
        var m = DerbyMachine(seed: 3)
        run(&m, seconds: 0.6)
        m.slice(perfectCrossing(m))
        XCTAssertEqual(m.beat, .contact)
        XCTAssertNotNil(m.flight)
        XCTAssertEqual(m.tally.hits, 1)
        XCTAssertEqual(m.tally.pitches, 1)
        XCTAssertGreaterThan(m.tally.totalFeet, 380)
        let t1 = run(&m, seconds: 0.4)
        XCTAssertEqual(m.beat, .flight)
        XCTAssertTrue(t1.contains(.cutToWide))
        XCTAssertTrue(t1.contains(.flash))
        let t2 = run(&m, seconds: 12)       // 2× playback of a ≤12 s flight, plus holds
        XCTAssertEqual(m.beat, .windup)
        XCTAssertTrue(t2.contains(.cutToAtBat))
        XCTAssertNil(m.flight)
    }

    func testHomeRunAdvancesThePark() {
        var m = DerbyMachine(seed: 3)
        run(&m, seconds: 0.6)
        m.slice(perfectCrossing(m))          // 115 mph at 28° at park 1 is a home run
        XCTAssertTrue(m.flight?.homeRun ?? false)
        let t = run(&m, seconds: 12)
        XCTAssertEqual(m.park.number, 2)
        XCTAssertEqual(m.park, Park.generate(number: 2))
        XCTAssertTrue(t.contains(.parkChanged(m.park)))
        XCTAssertEqual(m.tally.homeRuns, 1)
    }

    func testSliceOutsideThePitchBeatIsIgnored() {
        var m = DerbyMachine(seed: 5)
        m.slice(perfectCrossing(m))          // still in windup
        XCTAssertEqual(m.beat, .windup)
        XCTAssertEqual(m.tally.pitches, 0)
        m.sliceMissed()
        XCTAssertEqual(m.beat, .windup)
    }

    func testPlaybackPointAdvances() {
        var m = DerbyMachine(seed: 3)
        run(&m, seconds: 0.6)
        m.slice(perfectCrossing(m))
        run(&m, seconds: 0.4)
        let a = m.playbackPoint?.xFeet ?? -1
        run(&m, seconds: 0.5)
        let b = m.playbackPoint?.xFeet ?? -1
        XCTAssertGreaterThan(b, a)
    }

    func testDeterministicForSeed() {
        var a = DerbyMachine(seed: 99), b = DerbyMachine(seed: 99)
        run(&a, seconds: 5); run(&b, seconds: 5)
        XCTAssertEqual(a, b)
    }
}
