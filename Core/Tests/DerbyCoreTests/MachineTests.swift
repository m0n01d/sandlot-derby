import XCTest
@testable import DerbyCore

final class MachineTests: XCTestCase {
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
        // 2× playback of a ≤12 s flight, plus holds. Stop on the cut back: the machine never idles,
        // so a fixed 12 s run lands in whatever beat the next pitches have reached.
        var t2: [Transition] = []
        var waited = 0.0
        while !t2.contains(.cutToAtBat) && waited < 12 { t2 += m.tick(1.0 / 60); waited += 1.0 / 60 }
        XCTAssertTrue(t2.contains(.cutToAtBat))
        XCTAssertEqual(m.beat, .windup)
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

    func testFlightCameraCutsCloseAtTheWallAndBackOutForTheResult() {
        var m = DerbyMachine(seed: 3)
        run(&m, seconds: 0.6)
        m.slice(perfectCrossing(m))
        XCTAssertEqual(m.flightCamera, .wide)               // contact freeze
        run(&m, seconds: 0.4)
        XCTAssertEqual(m.beat, .flight)
        XCTAssertEqual(m.flightCamera, .wide)               // the ball leaves the bat wide
        var waited = 0.0
        while m.flightCamera == .wide && m.beat == .flight && waited < 12 { m.tick(1.0 / 60); waited += 1.0 / 60 }
        XCTAssertEqual(m.flightCamera, .close)
        let x = m.playbackPoint?.xFeet ?? 0
        let cutAt = m.park.wallDistanceFeet - m.cameraRules.closeLeadFeet
        XCTAssertGreaterThanOrEqual(x, cutAt)
        XCTAssertLessThan(x, cutAt + 15)                    // cut on arrival, not late
        while m.beat == .flight && waited < 24 {
            XCTAssertEqual(m.flightCamera, .close)          // once close, close until it lands
            m.tick(1.0 / 60); waited += 1.0 / 60
        }
        XCTAssertEqual(m.beat, .result)
        XCTAssertEqual(m.flightCamera, .wide)
    }

    func testFlightCameraStaysWideForABallThatNeverNearsTheWall() {
        var m = DerbyMachine(seed: 3, park: Park.generate(number: 4))    // 380 ft: a pop-up is nowhere near
        run(&m, seconds: 0.6)
        m.slice(SliceCrossing(quality: 0, progress: 1, swingAngleDegrees: 60, power: 0.3,
                              ball: m.ballNow, crossingPoint: m.ballNow.position))   // a soft pop-up
        run(&m, seconds: 0.4)
        var waited = 0.0
        while m.beat == .flight && waited < 12 {
            XCTAssertEqual(m.flightCamera, .wide)
            m.tick(1.0 / 60); waited += 1.0 / 60
        }
        XCTAssertLessThan(m.flight?.points.map(\.xFeet).max() ?? 999, m.park.wallDistanceFeet - 60)
    }

    func testDeterministicForSeed() {
        var a = DerbyMachine(seed: 99), b = DerbyMachine(seed: 99)
        run(&a, seconds: 5); run(&b, seconds: 5)
        XCTAssertEqual(a, b)
    }
}
