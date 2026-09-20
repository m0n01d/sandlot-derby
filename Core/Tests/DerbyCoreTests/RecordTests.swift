import XCTest
@testable import DerbyCore

/// A celebration when a record falls (issue #41). `Records.kind` is a pure comparison of the
/// tally before a swing against the tally after it, so most of this is arithmetic; the rest is
/// the machine putting it on screen at the right moment and a replay finding the same one.
final class RecordTests: XCTestCase {

    private func tally(_ pairs: [(Stat, Double)]) -> Tally {
        var t = Tally()
        for (s, v) in pairs { t.set(s, v) }
        return t
    }

    /// A swing that is not a home run and not a park change: the plain case.
    private let plainSwing = RecordSwing(streakBefore: 0, streakAfter: 0, clearsThePark: false)

    /// Enough swings behind it that the gate is never what is being tested.
    private let seasoned: (Stat, Double) = (.swings, 40)

    // MARK: - The gate

    func testTheKnobsAreTheOnesTheIssueNamed() {
        XCTAssertEqual(RecordRules.standard.minSwingsBeforeRecords, 25)
        XCTAssertEqual(RecordRules.standard.priority,
                       [.longest, .homeRunStreak, .exitVelocity, .apex, .hangTime, .fewestPitches])
    }

    func testNoRecordUntilTheCareerHasTwentyFiveSwingsBehindIt() {
        for swings in [0.0, 1, 24] {
            XCTAssertNil(Records.kind(before: tally([(.swings, swings), (.longestFeet, 300)]),
                                      after: tally([(.swings, swings + 1), (.longestFeet, 400)]),
                                      swing: plainSwing),
                         "\(swings) swings behind it is too few")
        }
        XCTAssertEqual(Records.kind(before: tally([(.swings, 25), (.longestFeet, 300)]),
                                    after: tally([(.swings, 26), (.longestFeet, 400)]),
                                    swing: plainSwing),
                       .longest)
    }

    /// The first of anything is not a record, it is the first. A stat nobody has written is nil,
    /// which is a different thing from a stat that is 0.
    func testNoRecordWithoutAPreviousBest() {
        XCTAssertNil(Records.kind(before: tally([seasoned]),
                                  after: tally([seasoned, (.longestFeet, 400)]),
                                  swing: plainSwing))
        XCTAssertNil(Records.kind(before: tally([seasoned, (.longestFeet, 0)]),
                                  after: tally([seasoned, (.longestFeet, 400)]),
                                  swing: plainSwing))
        XCTAssertEqual(Records.kind(before: tally([seasoned, (.longestFeet, 399)]),
                                    after: tally([seasoned, (.longestFeet, 400)]),
                                    swing: plainSwing),
                       .longest)
    }

    func testEqualIsNotBeaten() {
        XCTAssertNil(Records.kind(before: tally([seasoned, (.longestFeet, 400)]),
                                  after: tally([seasoned, (.longestFeet, 400)]),
                                  swing: plainSwing))
    }

    // MARK: - One a swing, by priority

    func testAtMostOnePerSwingAndTheOrderIsThePriority() {
        // A swing that beat every maximum there is answers with the first of them.
        let bests: [(Stat, Double)] = [(.longestFeet, 300), (.bestExitVelocityMPH, 100),
                                       (.highestApexFeet, 90), (.longestHangTime, 4),
                                       (.bestHomeRunStreak, 2), (.bestHomeRunStreakAtStreakStart, 2)]
        let after: [(Stat, Double)] = [(.longestFeet, 400), (.bestExitVelocityMPH, 115),
                                       (.highestApexFeet, 150), (.longestHangTime, 6),
                                       (.bestHomeRunStreak, 3)]
        let swing = RecordSwing(streakBefore: 2, streakAfter: 3, clearsThePark: false)
        XCTAssertEqual(Records.kind(before: tally([seasoned] + bests),
                                    after: tally([seasoned] + after), swing: swing), .longest)

        // Take the leader away and the next one answers, all the way down.
        var remaining = bests
        for expected in [RecordKind.homeRunStreak, .exitVelocity, .apex, .hangTime] {
            remaining = blocking(expected, in: remaining)
            XCTAssertEqual(Records.kind(before: tally([seasoned] + remaining),
                                        after: tally([seasoned] + after), swing: swing),
                           expected)
        }
    }

    /// Puts every best *above* `kind` in the priority order out of reach, so `kind` is the first
    /// one left that this swing can beat.
    private func blocking(_ kind: RecordKind, in bests: [(Stat, Double)]) -> [(Stat, Double)] {
        let unreachable: [RecordKind: Stat] = [.homeRunStreak: .longestFeet,
                                               .exitVelocity: .bestHomeRunStreak,
                                               .apex: .bestExitVelocityMPH,
                                               .hangTime: .highestApexFeet]
        guard let stat = unreachable[kind] else { return bests }
        return bests.map { $0.0 == stat ? ($0.0, 100_000) : $0 }
    }

    // MARK: - The streak fires on the one that passes the old best

    func testAStreakRecordFiresOnceOnTheHomeRunThatPassesTheOldBestAndNotAfter() {
        // The old best is 2. The streak runs 1, 2, 3, 4, 5: only the third passes it.
        let oldBest = 2.0
        for streakBefore in 0...4 {
            let streakAfter = streakBefore + 1
            let bestBefore = max(oldBest, Double(streakBefore))
            let bestAfter = max(bestBefore, Double(streakAfter))
            let kind = Records.kind(
                before: tally([seasoned, (.bestHomeRunStreak, bestBefore),
                               (.bestHomeRunStreakAtStreakStart, oldBest)]),
                after: tally([seasoned, (.bestHomeRunStreak, bestAfter)]),
                swing: RecordSwing(streakBefore: streakBefore, streakAfter: streakAfter,
                                   clearsThePark: false))
            if streakAfter == Int(oldBest) + 1 {
                XCTAssertEqual(kind, .homeRunStreak, "the streak reaching \(streakAfter) passes a best of 2")
            } else {
                XCTAssertNil(kind, "a streak of \(streakAfter) is only extending a best it already holds")
            }
        }
    }

    /// The machine writes `bestHomeRunStreakAtStreakStart` as the streak leaves 0, so a save from
    /// a build that never had the key is right from its very first streak rather than from never.
    func testTheStreakToBeatIsWrittenAsTheStreakLeavesZero() {
        var m = DerbyMachine(seed: 3)
        m.progressRules.homeRunsToClear = 99          // stay in one park; this is about the streak
        XCTAssertNil(m.tally.value(ifRecorded: .bestHomeRunStreakAtStreakStart))
        homer(&m)
        XCTAssertEqual(m.tally.count(.bestHomeRunStreakAtStreakStart), 0)
        homer(&m)
        XCTAssertEqual(m.tally.count(.bestHomeRunStreakAtStreakStart), 0, "still the same streak")

        toNextPitch(&m)
        m.sliceMissed()                               // the streak dies at 2, the best is 2
        run(&m, until: .windup)
        homer(&m)
        XCTAssertEqual(m.tally.count(.bestHomeRunStreakAtStreakStart), 2, "the new streak has 2 to beat")
    }

    // MARK: - Fewest pitches, the one minimum

    func testFewestPitchesOnlyCountsWhenTheParkActuallyChanges() {
        let before = tally([seasoned, (.fewestPitchesToClearPark, 10)])
        let after = tally([seasoned, (.pitchesThisPark, 4)])
        XCTAssertEqual(Records.kind(before: before, after: after,
                                    swing: RecordSwing(streakBefore: 0, streakAfter: 0,
                                                       clearsThePark: true)),
                       .fewestPitches)
        XCTAssertNil(Records.kind(before: before, after: after, swing: plainSwing),
                     "a home run that did not make the count clears nothing and beats nothing")
        // Equal is not beaten: `Tally.lower` writes only on strictly fewer.
        XCTAssertNil(Records.kind(before: tally([seasoned, (.fewestPitchesToClearPark, 4)]),
                                  after: after,
                                  swing: RecordSwing(streakBefore: 0, streakAfter: 0,
                                                     clearsThePark: true)))
    }

    // MARK: - The machine puts it on screen

    func testTheRecordGoesUpWithTheLandingNumberAndComesOffWithIt() {
        var m = machine(with: tally([seasoned, (.longestFeet, 100)]))
        toNextPitch(&m)
        m.slice(bomb(m))
        XCTAssertNil(m.recordNow, "not during the contact freeze")
        while m.beat == .contact { m.tick(1.0 / 60) }
        XCTAssertNil(m.recordNow, "and not during the flight")

        let arriving = tickInto(&m, .result)
        XCTAssertEqual(arriving.filter { if case .newRecord = $0 { return true } else { return false } },
                       [.newRecord(.longest)], "once, on the tick the landing number goes up")
        XCTAssertEqual(m.recordNow, .longest)

        // And it is not emitted again for the rest of the hold.
        let rest = run(&m, until: .windup)
        XCTAssertFalse(rest.contains { if case .newRecord = $0 { return true } else { return false } })
        XCTAssertNil(m.recordNow, "nil the moment the number comes off")
    }

    func testAnOrdinarySwingSetsNoRecord() {
        var m = machine(with: tally([seasoned, (.longestFeet, 100_000), (.bestExitVelocityMPH, 999),
                                     (.highestApexFeet, 99_999), (.longestHangTime, 999),
                                     (.bestHomeRunStreak, 99)]))
        toNextPitch(&m)
        m.slice(bomb(m))
        let arriving = tickInto(&m, .result)
        XCTAssertFalse(arriving.contains { if case .newRecord = $0 { return true } else { return false } })
        XCTAssertNil(m.recordNow)
    }

    /// The fewest-pitches celebration rides in the clearing home run's hold — the one that also
    /// says `PARK CLEARED` — rather than at the park change, which is the *end* of that hold and
    /// the cut back to the plate, with no frame left to draw anything in.
    func testFewestPitchesIsCelebratedInTheClearingHold() {
        var m = machine(with: tally([seasoned, (.fewestPitchesToClearPark, 10),
                                     (.longestFeet, 100_000), (.bestExitVelocityMPH, 999),
                                     (.highestApexFeet, 99_999), (.longestHangTime, 999),
                                     (.bestHomeRunStreak, 99)]))
        homer(&m)
        homer(&m)
        toNextPitch(&m)
        m.slice(bomb(m))
        let arriving = tickInto(&m, .result)
        XCTAssertEqual(m.recordNow, .fewestPitches)
        XCTAssertTrue(arriving.contains(.newRecord(.fewestPitches)))
        XCTAssertTrue(m.clearsTheParkNow)
        run(&m, until: .windup)
        XCTAssertEqual(m.tally.count(.fewestPitchesToClearPark), 3)
    }

    // MARK: - A clip finds the same record (DESIGN.md §19)

    func testTheRecordIsReproducibleFromAReplayRecord() {
        var live = machine(with: tally([seasoned, (.longestFeet, 100)]))
        toNextPitch(&live)
        let crossing = bomb(live)
        let record = Replay(capturing: live, crossing: crossing,
                            slash: Point(x: 3, y: -4), trail: [Point(x: 1, y: 2)])
        live.slice(crossing)
        tickInto(&live, .result)
        XCTAssertEqual(live.recordNow, .longest, "the fixture swing must set one")

        var rebuilt = Replay.machine(from: record)
        let arriving = tickInto(&rebuilt, .result)
        XCTAssertEqual(rebuilt.recordNow, live.recordNow)
        XCTAssertTrue(arriving.contains(.newRecord(.longest)))

        // …and a swing that set none still sets none.
        var quiet = machine(with: tally([seasoned, (.longestFeet, 100_000), (.bestExitVelocityMPH, 999),
                                         (.highestApexFeet, 99_999), (.longestHangTime, 999),
                                         (.bestHomeRunStreak, 99)]))
        toNextPitch(&quiet)
        let quietCrossing = bomb(quiet)
        let quietRecord = Replay(capturing: quiet, crossing: quietCrossing,
                                 slash: Point(x: 3, y: -4), trail: [])
        var quietRebuilt = Replay.machine(from: quietRecord)
        tickInto(&quietRebuilt, .result)
        XCTAssertNil(quietRebuilt.recordNow)
    }

    // MARK: - The Warm Up card's `NEW BEST` (DESIGN.md §18)

    func testAWarmUpSaysWhatItBeatAndOnlyWhenThereWasSomethingToBeat() {
        // The first day ever: there is no previous best, so nothing is beaten.
        var first = warmUpCareer()
        let firstBests = playTheDay(&first)
        XCTAssertEqual(firstBests, WarmUpBests(feet: false, homeRuns: false))
        XCTAssertFalse(firstBests?.any ?? true)
        let feetOfTheDay = first.tally[.warmUpBestFeet]
        XCTAssertGreaterThan(feetOfTheDay, 0)

        // A day that beats a smaller one says so.
        var better = warmUpCareer(previousBestFeet: feetOfTheDay - 1, previousBestHomeRuns: 0)
        let betterBests = playTheDay(&better)
        XCTAssertEqual(betterBests?.feet, true)
        XCTAssertEqual(betterBests?.homeRuns, true)

        // A day that cannot beat what stands says nothing.
        var worse = warmUpCareer(previousBestFeet: feetOfTheDay + 1, previousBestHomeRuns: 10)
        let worseBests = playTheDay(&worse)
        XCTAssertEqual(worseBests, WarmUpBests(feet: false, homeRuns: false))
    }

    // MARK: - Helpers

    private func bomb(_ m: DerbyMachine) -> SliceCrossing {
        SliceCrossing(quality: 1, progress: 1, swingAngleDegrees: 28, power: 1,
                      ball: m.ballNow, crossingPoint: m.ballNow.position)
    }

    /// A career standing in an ordinary Show-league park with the given numbers behind it.
    private func machine(with tally: Tally) -> DerbyMachine {
        DerbyMachine(seed: 3, park: Park.generate(number: 30), tally: tally)
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

    /// The transitions of the one tick that *arrives* at `beat` — the frame the number goes up.
    @discardableResult
    private func tickInto(_ m: inout DerbyMachine, _ beat: Beat) -> [Transition] {
        var waited = 0.0
        while waited < 30 {
            let out = m.tick(1.0 / 60)
            waited += 1.0 / 60
            if m.beat == beat { return out }
        }
        XCTFail("never reached \(beat)")
        return []
    }

    private func homer(_ m: inout DerbyMachine) {
        toNextPitch(&m)
        m.slice(bomb(m))
        XCTAssertTrue(m.flight?.homeRun ?? false)
        run(&m, until: .windup)
    }

    private func warmUpCareer(previousBestFeet: Double? = nil,
                              previousBestHomeRuns: Double? = nil) -> DerbyMachine {
        var t = Tally()
        t.set(.parksCleared, 1)                      // the Warm Up's gate
        if let previousBestFeet { t.set(.warmUpBestFeet, previousBestFeet) }
        if let previousBestHomeRuns { t.set(.warmUpBestHomeRuns, previousBestHomeRuns) }
        var m = DerbyMachine(seed: 7, park: Park.generate(number: 2), tally: t)
        m.beginWarmUp(WarmUp.generate(day: 20260920))
        while m.warmUp == nil { m.tick(1.0 / 60) }
        return m
    }

    /// Swings at all ten and returns what `.warmUpEnded` said the day beat.
    private func playTheDay(_ m: inout DerbyMachine) -> WarmUpBests? {
        var waited = 0.0
        while waited < 200 {
            if m.beat == .pitch, m.pitchProgress >= 0.97 { m.slice(bomb(m)) }
            for transition in m.tick(1.0 / 60) {
                if case .warmUpEnded(_, let bests) = transition { return bests }
            }
            waited += 1.0 / 60
        }
        XCTFail("the day never ended")
        return nil
    }
}
