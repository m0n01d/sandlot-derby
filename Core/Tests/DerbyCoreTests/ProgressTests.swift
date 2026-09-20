import XCTest
@testable import DerbyCore

/// Three home runs clear a park (issue #40). A count in this park, not a count in a row.
final class ProgressTests: XCTestCase {

    /// 115 mph at 28°: a home run in any park the rules can generate.
    private func bomb(_ m: DerbyMachine) -> SliceCrossing {
        SliceCrossing(quality: 1, progress: 1, swingAngleDegrees: 28, power: 1,
                      ball: m.ballNow, crossingPoint: m.ballNow.position)
    }

    /// The weakest contact there is: a slow chop into the ground, a ball in play and nothing more.
    private func chopper(_ m: DerbyMachine) -> SliceCrossing {
        SliceCrossing(quality: 0, progress: 1, swingAngleDegrees: -20, power: 0.3,
                      ball: m.ballNow, crossingPoint: m.ballNow.position)
    }

    private func toNextPitch(_ m: inout DerbyMachine) {
        var waited = 0.0
        while m.beat != .pitch && waited < 30 { m.tick(1.0 / 60); waited += 1.0 / 60 }
        XCTAssertEqual(m.beat, .pitch)
    }

    @discardableResult
    private func run(_ m: inout DerbyMachine, until beat: Beat) -> [Transition] {
        var out: [Transition] = []
        var waited = 0.0
        while m.beat != beat && waited < 30 { out += m.tick(1.0 / 60); waited += 1.0 / 60 }
        XCTAssertEqual(m.beat, beat)
        return out
    }

    /// One home run, played all the way out to the next windup.
    @discardableResult
    private func homer(_ m: inout DerbyMachine) -> [Transition] {
        toNextPitch(&m)
        m.slice(bomb(m))
        XCTAssertTrue(m.flight?.homeRun ?? false)
        return run(&m, until: .windup)
    }

    private func changedPark(_ t: [Transition]) -> Bool {
        t.contains { if case .parkChanged = $0 { return true } else { return false } }
    }

    // MARK: - The count

    func testTheKnobIsThreeAndEveryParkAsksForIt() {
        XCTAssertEqual(ProgressRules.standard.homeRunsToClear, 3)
        for park in [1, 2, 3, 4, 57] {
            let m = DerbyMachine(seed: 1, park: Park.generate(number: park))
            XCTAssertEqual(m.homeRunsToClearPark, 3, "park \(park)")
            XCTAssertEqual(m.homeRunsThisPark, 0)
        }
    }

    func testTwoHomeRunsDoNotClearAParkAndTheThirdDoes() {
        var m = DerbyMachine(seed: 3)
        for hit in 1...2 {
            let t = homer(&m)
            XCTAssertEqual(m.homeRunsThisPark, hit)
            XCTAssertEqual(m.park.number, 1, "home run \(hit) must not move the park")
            XCTAssertFalse(changedPark(t))
            XCTAssertEqual(m.tally.count(.parksCleared), 0)
        }
        let t = homer(&m)
        XCTAssertTrue(changedPark(t))
        XCTAssertEqual(m.park.number, 2)
        XCTAssertEqual(m.tally.count(.parksCleared), 1)
        XCTAssertEqual(m.homeRunsThisPark, 0, "the new park starts its own count")
    }

    /// A count in this park, not a count in a row: only a home run moves it, and nothing moves
    /// it back. (The home-run *streak* is the thing a miss ends, and it does — checked here so
    /// the two cannot be confused.)
    func testMissesAndBallsInPlayBetweenThemDoNotResetTheCount() {
        var m = DerbyMachine(seed: 3)
        homer(&m)
        XCTAssertEqual(m.homeRunsThisPark, 1)

        toNextPitch(&m)
        m.sliceMissed()
        run(&m, until: .windup)
        XCTAssertEqual(m.homeRunsThisPark, 1, "a whiff costs the streak, not the park's count")
        XCTAssertEqual(m.tally.homeRunStreak, 0)

        homer(&m)
        XCTAssertEqual(m.homeRunsThisPark, 2)

        toNextPitch(&m)
        m.slice(chopper(m))
        XCTAssertFalse(m.flight?.homeRun ?? true)
        run(&m, until: .windup)
        XCTAssertEqual(m.homeRunsThisPark, 2, "a ball in play costs the streak, not the count")
        XCTAssertEqual(m.park.number, 1)

        let t = homer(&m)
        XCTAssertTrue(changedPark(t), "the third home run clears it however scattered they were")
        XCTAssertEqual(m.park.number, 2)
        XCTAssertEqual(m.tally.homeRunStreak, 1)      // and the streak is only this one
    }

    func testTheKnobMovesTheCount() {
        for count in [1, 2, 5] {
            var m = DerbyMachine(seed: 3)
            m.progressRules.homeRunsToClear = count
            for hit in 1..<count {
                homer(&m)
                XCTAssertEqual(m.park.number, 1, "count \(count), home run \(hit)")
            }
            homer(&m)
            XCTAssertEqual(m.park.number, 2, "count \(count) should have cleared by now")
        }
    }

    // MARK: - What moves with the clearing home run

    func testTheCallUpFiresOnTheThirdAndNotBefore() {
        var m = DerbyMachine(seed: 3, park: Park.generate(number: 3))   // Triple-A
        for hit in 1...2 {
            toNextPitch(&m)
            m.slice(bomb(m))
            run(&m, until: .result)
            XCTAssertFalse(m.isBeingCalledUp, "home run \(hit) has not cleared Triple-A")
            XCTAssertFalse(m.clearsTheParkNow)
            let t = run(&m, until: .windup)
            XCTAssertFalse(t.contains(.calledUp))
            XCTAssertNil(m.tally.value(ifRecorded: .pitchesToTheShow))
        }
        toNextPitch(&m)
        m.slice(bomb(m))
        run(&m, until: .result)
        XCTAssertTrue(m.isBeingCalledUp)
        XCTAssertTrue(m.clearsTheParkNow)
        let t = run(&m, until: .windup)
        XCTAssertTrue(t.contains(.calledUp))
        XCTAssertEqual(m.park.number, 4)
        XCTAssertEqual(m.tally.count(.pitchesToTheShow), 3)
    }

    /// At the ceiling the advance is owed by the *clearing* home run, and the count then simply
    /// stays met: the park never changes, so nothing resets it (§16, #40).
    func testTheCeilingIsOwedByTheThirdAndTheCountThenStaysMet() {
        var m = DerbyMachine(seed: 3, park: Park.generate(number: 3))
        m.parkCeiling = 3
        for hit in 1...2 {
            let t = homer(&m)
            XCTAssertFalse(t.contains(.calledUp), "home run \(hit) is owed nothing")
        }
        let t = homer(&m)
        XCTAssertTrue(t.contains(.calledUp))
        XCTAssertFalse(changedPark(t))
        XCTAssertEqual(m.park.number, 3)
        XCTAssertEqual(m.homeRunsThisPark, 3)

        // A fourth: the count is still met, so it announces again — §16's open question 3.
        let fourth = homer(&m)
        XCTAssertTrue(fourth.contains(.calledUp))
        XCTAssertEqual(m.homeRunsThisPark, 4)

        // And signing pays the one advance that is owed, at the next windup.
        m.parkCeiling = nil
        XCTAssertEqual(m.tick(1.0 / 60), [.parkChanged(Park.generate(number: 4))])
        XCTAssertEqual(m.homeRunsThisPark, 0)
    }

    func testFewestPitchesToClearCountsEveryPitchOfThePark() {
        var m = DerbyMachine(seed: 3)
        XCTAssertNil(m.tally.value(ifRecorded: .fewestPitchesToClearPark))
        toNextPitch(&m)
        m.sliceMissed()
        run(&m, until: .windup)
        for _ in 0..<3 { homer(&m) }
        XCTAssertEqual(m.tally.count(.fewestPitchesToClearPark), 4)   // the miss and the three
        XCTAssertEqual(m.tally.count(.pitchesThisPark), 0)
    }

    // MARK: - The Warm Up feeds nothing (DESIGN.md §18)

    func testAWarmUpHomeRunNeverCountsTowardThePark() {
        var t = Tally()
        t.set(.parksCleared, 1)                      // the Warm Up's gate
        var m = DerbyMachine(seed: 7, park: Park.generate(number: 2), tally: t)
        m.beginWarmUp(WarmUp.generate(day: 20260920))
        while m.warmUp == nil { m.tick(1.0 / 60) }

        var homeRuns = 0
        var waited = 0.0
        while m.warmUp != nil && waited < 200 {
            if m.beat == .pitch, m.pitchProgress >= 0.97 {
                m.slice(bomb(m))
                if m.flight?.homeRun == true { homeRuns += 1 }
            }
            m.tick(1.0 / 60)
            waited += 1.0 / 60
            XCTAssertEqual(m.homeRunsThisPark, 0, "a day's ten clear nothing")
        }
        XCTAssertGreaterThan(homeRuns, 2, "the ten should contain more home runs than a park asks for")
        XCTAssertEqual(m.homeRunsThisPark, 0)
        XCTAssertEqual(m.park.number, 2, "the career is standing exactly where it was")
        XCTAssertEqual(m.tally.count(.parksCleared), 1)
        XCTAssertEqual(m.tally.count(.homeRuns), homeRuns, "they still count as home runs")
    }

    // MARK: - The save

    func testTheCountSurvivesAJSONRoundTripOfTheTally() throws {
        var m = DerbyMachine(seed: 3)
        homer(&m)
        homer(&m)
        XCTAssertEqual(m.homeRunsThisPark, 2)

        let data = try JSONEncoder().encode(m.tally)
        let restored = try JSONDecoder().decode(Tally.self, from: data)
        XCTAssertEqual(restored.count(.homeRunsThisPark), 2)

        // And a machine carried on from that save clears with one more, not three.
        var carried = DerbyMachine(seed: 3, park: m.park, tally: restored)
        XCTAssertEqual(carried.homeRunsThisPark, 2)
        let t = homer(&carried)
        XCTAssertTrue(changedPark(t))
    }

    /// A save written before #40 has no such key. A keyed tally reads a missing key as 0, which
    /// is exactly where a park starts: the player simply hits three in whatever park they are in.
    func testASaveFromABuildWithoutTheStatStartsAtZero() throws {
        let json = #"{"values":{"pitches":40,"homeRuns":9,"parksCleared":9,"swings":40}}"#
        let old = try JSONDecoder().decode(Tally.self, from: Data(json.utf8))
        XCTAssertNil(old.value(ifRecorded: .homeRunsThisPark))

        var m = DerbyMachine(seed: 3, park: Park.generate(number: 10), tally: old)
        XCTAssertEqual(m.homeRunsThisPark, 0)
        homer(&m)
        homer(&m)
        XCTAssertEqual(m.park.number, 10)
        let t = homer(&m)
        XCTAssertTrue(changedPark(t))
        XCTAssertEqual(m.park.number, 11)
    }
}
