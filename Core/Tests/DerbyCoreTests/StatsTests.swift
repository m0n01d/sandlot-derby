import XCTest
@testable import DerbyCore

final class StatsTests: XCTestCase {
    @discardableResult
    private func run(_ m: inout DerbyMachine, seconds: Double, dt: Double = 1.0 / 60) -> [Transition] {
        var out: [Transition] = []
        var t = 0.0
        while t < seconds { out += m.tick(dt); t += dt }
        return out
    }

    /// 115 mph at 28°: a home run in any park the rules can generate.
    private func bomb(_ m: DerbyMachine) -> SliceCrossing {
        SliceCrossing(quality: 1, progress: 1, swingAngleDegrees: 28, power: 1,
                      ball: m.ballNow, crossingPoint: m.ballNow.position)
    }

    /// The weakest contact there is: a slow chop into the ground.
    private func chopper(_ m: DerbyMachine) -> SliceCrossing {
        SliceCrossing(quality: 0, progress: 1, swingAngleDegrees: -20, power: 0.3,
                      ball: m.ballNow, crossingPoint: m.ballNow.position)
    }

    /// Ticks from wherever the machine is until the next pitch is in the air.
    private func toNextPitch(_ m: inout DerbyMachine) {
        var waited = 0.0
        while m.beat != .pitch && waited < 30 { m.tick(1.0 / 60); waited += 1.0 / 60 }
        XCTAssertEqual(m.beat, .pitch)
    }

    /// A machine that has just homered and is now facing a pitch that is (or is not) a strike.
    private func afterOneHomer(nextPitchIsStrike: Bool) -> DerbyMachine {
        for seed in UInt64(1)...500 {
            var m = DerbyMachine(seed: seed)
            toNextPitch(&m)
            m.slice(bomb(m))
            run(&m, seconds: 0.5)            // into the flight, so the next wait is for a new pitch
            toNextPitch(&m)
            if m.pitch.isStrike == nextPitchIsStrike { return m }
        }
        XCTFail("no seed in 1...500 gave the pitch we wanted")
        return DerbyMachine(seed: 0)
    }

    func testHomeRunStreakCountsAndCarriesItsBest() {
        var m = DerbyMachine(seed: 3)
        for expected in 1...3 {
            toNextPitch(&m)
            m.slice(bomb(m))
            XCTAssertTrue(m.flight?.homeRun ?? false)
            XCTAssertEqual(m.tally.homeRunStreak, expected)
            run(&m, seconds: 0.5)
        }
        toNextPitch(&m)
        m.slice(chopper(m))
        XCTAssertFalse(m.flight?.homeRun ?? true)
        XCTAssertEqual(m.tally.homeRunStreak, 0)
        XCTAssertEqual(m.tally.bestHomeRunStreak, 3)
        XCTAssertEqual(m.tally.count(.hitStreak), 4)     // contact is contact
        XCTAssertEqual(m.tally.count(.groundBalls), 1)
        XCTAssertEqual(m.tally.count(.parksCleared), 3)
    }

    func testTakingABallKeepsTheStreak() {
        var m = afterOneHomer(nextPitchIsStrike: false)
        run(&m, seconds: m.pitch.duration * 1.15 + 0.1)
        XCTAssertEqual(m.lastCall, .ball)
        XCTAssertEqual(m.tally.homeRunStreak, 1)
        XCTAssertEqual(m.tally.count(.ballsTaken), 1)
    }

    func testTakingABallEndsTheStreakWhenTheKnobSaysSo() {
        var m = afterOneHomer(nextPitchIsStrike: false)
        m.statRules.takenBallKeepsStreak = false
        run(&m, seconds: m.pitch.duration * 1.15 + 0.1)
        XCTAssertEqual(m.tally.homeRunStreak, 0)
    }

    func testACalledStrikeEndsTheStreak() {
        var m = afterOneHomer(nextPitchIsStrike: true)
        run(&m, seconds: m.pitch.duration * 1.15 + 0.1)
        XCTAssertEqual(m.lastCall, .strike)
        XCTAssertEqual(m.tally.homeRunStreak, 0)
        XCTAssertEqual(m.tally.bestHomeRunStreak, 1)
        XCTAssertEqual(m.tally.count(.calledStrikes), 1)
    }

    func testAWhiffEndsTheStreakAndAChaseIsCounted() {
        var m = afterOneHomer(nextPitchIsStrike: false)
        m.sliceMissed()
        XCTAssertEqual(m.tally.homeRunStreak, 0)
        XCTAssertEqual(m.tally.count(.whiffs), 1)
        XCTAssertEqual(m.tally.count(.chases), 1)
        XCTAssertEqual(m.tally.count(.swings), 2)
        XCTAssertEqual(m.tally.pitches, 2)
    }

    func testClearingAParkRecordsHowFewPitchesItTook() {
        var m = DerbyMachine(seed: 3)
        XCTAssertNil(m.tally.value(ifRecorded: .fewestPitchesToClearPark))
        toNextPitch(&m)
        m.sliceMissed()
        toNextPitch(&m)
        m.slice(bomb(m))
        XCTAssertEqual(m.tally.count(.pitchesThisPark), 2)
        run(&m, seconds: 0.5)
        toNextPitch(&m)
        XCTAssertEqual(m.park.number, 2)
        XCTAssertEqual(m.tally.count(.fewestPitchesToClearPark), 2)
        XCTAssertEqual(m.tally.count(.pitchesThisPark), 0)
        m.slice(bomb(m))                     // one pitch beats two
        run(&m, seconds: 0.5)
        toNextPitch(&m)
        XCTAssertEqual(m.tally.count(.fewestPitchesToClearPark), 1)
    }

    func testPerPitchTypeLinesAddUp() {
        var m = DerbyMachine(seed: 11)
        for i in 0..<30 {
            toNextPitch(&m)
            if i % 3 == 0 { m.slice(bomb(m)); run(&m, seconds: 0.5) } else { m.sliceMissed() }
        }
        let seen = PitchType.all.reduce(0) { $0 + m.tally.count(.seen($1)) }
        let hits = PitchType.all.reduce(0) { $0 + m.tally.count(.hits($1)) }
        let homers = PitchType.all.reduce(0) { $0 + m.tally.count(.homeRuns($1)) }
        XCTAssertEqual(seen, m.tally.pitches)
        XCTAssertEqual(hits, m.tally.hits)
        XCTAssertEqual(homers, m.tally.homeRuns)
        XCTAssertEqual(m.tally.pitches, 30)
        XCTAssertEqual(m.tally.averageExitVelocityMPH, m.tally[.exitVelocitySum] / 10, accuracy: 1e-9)
    }

    func testBarrelWindowOpensWithVelocity() {
        let r = StatRules.standard
        XCTAssertFalse(r.isBarrel(exitVelocityMPH: 97.9, launchAngleDegrees: 28))
        XCTAssertTrue(r.isBarrel(exitVelocityMPH: 98, launchAngleDegrees: 28))
        XCTAssertFalse(r.isBarrel(exitVelocityMPH: 98, launchAngleDegrees: 24))
        XCTAssertTrue(r.isBarrel(exitVelocityMPH: 105, launchAngleDegrees: 20))
        XCTAssertFalse(r.isBarrel(exitVelocityMPH: 118, launchAngleDegrees: 55))
    }

    func testTallySurvivesJSONAndSavesFromOtherBuilds() throws {
        var m = DerbyMachine(seed: 3)
        toNextPitch(&m)
        m.slice(bomb(m))
        let data = try JSONEncoder().encode(m.tally)
        XCTAssertEqual(try JSONDecoder().decode(Tally.self, from: data), m.tally)

        // A save that lacks stats this build counts, and carries one it has never heard of.
        let other = #"{"values":{"pitches":3,"someFutureStat":9}}"#.data(using: .utf8)!
        let t = try JSONDecoder().decode(Tally.self, from: other)
        XCTAssertEqual(t.pitches, 3)
        XCTAssertEqual(t.homeRuns, 0)
    }

    func testARestoredSaveCarriesOn() {
        var m = DerbyMachine(seed: 3)
        toNextPitch(&m)
        m.slice(bomb(m))
        var restored = DerbyMachine(seed: 77, park: Park.generate(number: 5), tally: m.tally)
        XCTAssertEqual(restored.park.number, 5)
        XCTAssertEqual(restored.tally.homeRunStreak, 1)
        toNextPitch(&restored)
        restored.slice(bomb(restored))
        XCTAssertEqual(restored.tally.homeRunStreak, 2)
        XCTAssertEqual(restored.tally.pitches, 2)
    }
}
