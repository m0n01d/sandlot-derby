import XCTest
@testable import DerbyCore

/// The Warm Up, DESIGN.md §18: the day's card itself, and what the machine does with it.
final class WarmUpTests: XCTestCase {
    /// A night Show-league park with a 330 ft wall, so a squared-up ball is a home run.
    private let day = 20260920
    /// The day before, for the in-a-row count.
    private let dayBefore = 20260919

    // MARK: - Helpers

    /// A career standing in park 2 with one park already cleared — the gate's precondition.
    private func career(seed: UInt64 = 7, parksCleared: Int = 1, homeRunStreak: Int = 0) -> DerbyMachine {
        var t = Tally()
        if parksCleared > 0 { t.set(.parksCleared, Double(parksCleared)) }
        if homeRunStreak > 0 {
            t.set(.homeRunStreak, Double(homeRunStreak))
            t.set(.bestHomeRunStreak, Double(homeRunStreak))
        }
        return DerbyMachine(seed: seed, park: Park.generate(number: 2), tally: t)
    }

    private func perfectCrossing(_ m: DerbyMachine) -> SliceCrossing {
        SliceCrossing(quality: 1, progress: 1, swingAngleDegrees: 28, power: 1,
                      ball: m.ballNow, crossingPoint: m.ballNow.position)
    }

    /// Ticks the machine, swinging at every pitch the way `-autoslice` does.
    @discardableResult
    private func play(_ m: inout DerbyMachine, seconds: Double, swinging: Bool = true,
                      dt: Double = 1.0 / 60) -> [Transition] {
        var out: [Transition] = []
        var t = 0.0
        while t < seconds {
            if swinging, m.beat == .pitch, m.pitchProgress >= 0.97 { m.slice(perfectCrossing(m)) }
            out += m.tick(dt)
            t += dt
        }
        return out
    }

    /// Plays until `.warmUpEnded` and stops on that very tick, so the machine is examined at the
    /// instant the career gets the field back.
    @discardableResult
    private func playToTheCard(_ m: inout DerbyMachine, swinging: Bool = true,
                               budget: Double = 180) -> (result: WarmUpResult?, seen: [Transition]) {
        var seen: [Transition] = []
        var t = 0.0
        while t < budget {
            if swinging, m.beat == .pitch, m.pitchProgress >= 0.97 { m.slice(perfectCrossing(m)) }
            let out = m.tick(1.0 / 60)
            seen += out
            t += 1.0 / 60
            for transition in out {
                if case .warmUpEnded(let r) = transition { return (r, seen) }
            }
        }
        return (nil, seen)
    }

    // MARK: - The day's card (a pure function of the day)

    func testSameDaySameCard() {
        let a = WarmUp.generate(day: day)
        let b = WarmUp.generate(day: day)
        XCTAssertEqual(a.park, b.park)
        XCTAssertEqual(a.pitches, b.pitches)
        XCTAssertEqual(a, b)
    }

    func testDifferentDaysDiffer() {
        let a = WarmUp.generate(day: day)
        let b = WarmUp.generate(day: dayBefore)
        XCTAssertNotEqual(a.park, b.park)
        XCTAssertNotEqual(a.pitches, b.pitches)
    }

    func testAlwaysTenPitchesWhateverTheSwings() {
        for d in [20260101, 20260401, dayBefore, day, 20271231] {
            XCTAssertEqual(WarmUp.generate(day: d).pitches.count, WarmUpRules.standard.pitches)
        }
        var rules = WarmUpRules.standard
        rules.pitches = 3
        XCTAssertEqual(WarmUp.generate(day: day, rules: rules).pitches.count, 3)
    }

    func testTheDaysParkIsShowLeague() {
        for d in stride(from: 20260101, through: 20271231, by: 10_000) {
            XCTAssertEqual(WarmUp.generate(day: d).park.league, .theShow)
        }
        // And nothing in the minors' ladder can be reached, whatever nonsense is handed in.
        XCTAssertEqual(WarmUp.generate(day: 1).park.league, .theShow)
    }

    func testTheDaysParkComesFromTheOrdinarySeededRangesAndNightIsAllowed() {
        var nights = 0
        for offset in 0..<60 {
            let park = WarmUp.generate(day: 20260901 + offset % 28).park
            XCTAssertTrue(Park.Rules.standard.wallDistance.contains(park.wallDistanceFeet))
            XCTAssertTrue(Park.Rules.standard.wallHeight.contains(park.wallHeightFeet))
            if park.isNight { nights += 1 }
        }
        XCTAssertGreaterThan(nights, 0, "night has to be allowed in the day's park")
    }

    func testTheDaysPitchesDoNotComeFromTheParksOwnStream() {
        // The park and the pitches are seeded from the same day and must not share a stream:
        // the wall is what `Park.generate(number:)` says for that number, untouched.
        let card = WarmUp.generate(day: day)
        XCTAssertEqual(card.park, Park.generate(number: day))
    }

    // MARK: - Counting the days

    func testSerialCountsDays() {
        XCTAssertEqual(WarmUp.serial(of: day) - WarmUp.serial(of: dayBefore), 1)
        XCTAssertEqual(WarmUp.serial(of: 20260101) - WarmUp.serial(of: 20251231), 1)
        // 2028 is a leap year: 29 February exists and 1 March is the day after.
        XCTAssertEqual(WarmUp.serial(of: 20280301) - WarmUp.serial(of: 20280229), 1)
        XCTAssertEqual(WarmUp.serial(of: 20270301) - WarmUp.serial(of: 20270228), 1)
    }

    func testDayNumberIsCountedFromTheEpoch() {
        let rules = WarmUpRules.standard
        XCTAssertEqual(WarmUpResult(day: rules.epochDay, pitches: []).number(), 1)
        XCTAssertEqual(WarmUpResult(day: day, pitches: []).number(), 173)
    }

    // MARK: - The share string

    func testShareString() {
        let outcomes: [WarmUpOutcome] = [.homeRun, .swingAndMiss, .inPlay, .homeRun, .taken,
                                         .offTheWall, .homeRun, .inPlay, .swingAndMiss, .homeRun]
        let feet = [412, 0, 141, 388, 0, 372, 401, 89, 0, 436]
        let result = WarmUpResult(day: day, pitches: zip(outcomes, feet).map(WarmUpPitch.init))
        let lines = result.shareText().split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(String(lines[0]), "WARM UP 173 · 2,239 FT")
        XCTAssertEqual(String(lines[1]), "💥⬜🟩💥⬛🟨💥🟩⬜💥")
        XCTAssertEqual(String(lines[2]), WarmUpRules.standard.shareLink)
        XCTAssertEqual(result.totalFeet, 2239)
        XCTAssertEqual(result.homeRuns, 4)
        XCTAssertEqual(result.longestFeet, 436)
    }

    func testEveryOutcomeHasItsOwnGlyph() {
        let glyphs = [WarmUpOutcome.homeRun, .offTheWall, .inPlay, .swingAndMiss, .taken].map(\.glyph)
        XCTAssertEqual(Set(glyphs).count, glyphs.count)
    }

    // MARK: - Beginning it

    func testBeginsAtTheNextWindupNeverInTheMiddleOfAPitch() {
        var m = career()
        play(&m, seconds: 0.6, swinging: false)
        XCTAssertEqual(m.beat, .pitch)
        m.beginWarmUp(WarmUp.generate(day: day))
        XCTAssertNil(m.warmUp, "queued, not started")
        // The career pitch in the air resolves in the career's own park first.
        let careerPark = m.park
        play(&m, seconds: 0.4, swinging: false)
        XCTAssertEqual(m.park, careerPark)
        let seen = play(&m, seconds: 3, swinging: false)
        XCTAssertTrue(seen.contains(.warmUpBegan))
        XCTAssertNotNil(m.warmUp)
        XCTAssertEqual(m.park, WarmUp.generate(day: day).park)
        XCTAssertEqual(m.careerPark, careerPark)
    }

    func testNoWarmUpBeforeTheFirstClearedPark() {
        var m = career(parksCleared: 0)
        m.beginWarmUp(WarmUp.generate(day: day))
        let seen = play(&m, seconds: 4, swinging: false)
        XCTAssertNil(m.warmUp)
        XCTAssertFalse(seen.contains(.warmUpBegan))
    }

    func testASecondBeginIsIgnoredWhileOneIsRunning() {
        var m = career()
        m.beginWarmUp(WarmUp.generate(day: day))
        play(&m, seconds: 1, swinging: false)
        XCTAssertNotNil(m.warmUp)
        m.beginWarmUp(WarmUp.generate(day: dayBefore))
        play(&m, seconds: 1, swinging: false)
        XCTAssertEqual(m.warmUp?.card.day, day)
    }

    // MARK: - Running it

    func testTenPitchesThenTheCardAndTheCareerWindup() {
        var m = career()
        m.beginWarmUp(WarmUp.generate(day: day))
        let (result, seen) = playToTheCard(&m)
        let card = try? XCTUnwrap(result)
        XCTAssertNotNil(card)
        XCTAssertEqual(result?.pitches.count, 10)
        XCTAssertTrue(seen.contains(.warmUpBegan))
        XCTAssertNil(m.warmUp)
        XCTAssertEqual(m.beat, .windup)
    }

    func testAPitchIsSpentWhenItIsThrownAndComesBackTaken() {
        var m = career()
        m.beginWarmUp(WarmUp.generate(day: day))
        play(&m, seconds: 0.3, swinging: false)      // inside the windup that starts the Warm Up
        XCTAssertEqual(m.beat, .windup)
        XCTAssertEqual(m.warmUp?.spent, 0)
        // Tick to just past the first `.pitchThrown`.
        var thrown = false
        var t = 0.0
        while !thrown, t < 3 {
            thrown = m.tick(1.0 / 60).contains(.pitchThrown)
            t += 1.0 / 60
        }
        XCTAssertTrue(thrown)
        XCTAssertEqual(m.beat, .pitch)
        XCTAssertEqual(m.warmUp?.spent, 1, "spent at .pitchThrown, with the ball still in the air")
        XCTAssertEqual(m.warmUp?.pitches.last?.outcome, .taken)
        XCTAssertEqual(m.warmUp?.pitches.last?.feet, 0)
    }

    func testASwungPitchOverwritesItsTakenPlaceholder() {
        var m = career()
        m.beginWarmUp(WarmUp.generate(day: day))
        play(&m, seconds: 1.2, swinging: false)
        XCTAssertEqual(m.beat, .pitch)
        m.slice(perfectCrossing(m))
        XCTAssertEqual(m.warmUp?.spent, 1)
        XCTAssertEqual(m.warmUp?.pitches.last?.outcome, .homeRun)     // 330 ft wall
        XCTAssertGreaterThan(m.warmUp?.pitches.last?.feet ?? 0, 330)
    }

    func testAWhiffIsRecordedAsASwingAndAMiss() {
        var m = career()
        m.beginWarmUp(WarmUp.generate(day: day))
        play(&m, seconds: 1.2, swinging: false)
        XCTAssertEqual(m.beat, .pitch)
        m.sliceMissed()
        XCTAssertEqual(m.warmUp?.pitches.last?.outcome, .swingAndMiss)
    }

    func testResumesWhereItWasInterrupted() {
        let card = WarmUp.generate(day: day)
        var m = career()
        let already = Array(repeating: WarmUpPitch(outcome: .taken), count: 6)
        m.beginWarmUp(card, resuming: already)
        play(&m, seconds: 0.3, swinging: false)      // still in the windup, nothing thrown yet
        XCTAssertEqual(m.warmUp?.spent, 6)
        XCTAssertEqual(m.pitch, card.pitches[6], "picks up at pitch seven")
        let (result, _) = playToTheCard(&m)
        XCTAssertEqual(result?.pitches.count, 10)
    }

    func testAFinishedDayCannotBeResumed() {
        let card = WarmUp.generate(day: day)
        var m = career()
        m.beginWarmUp(card, resuming: Array(repeating: WarmUpPitch(outcome: .taken), count: 10))
        play(&m, seconds: 2, swinging: false)
        XCTAssertNil(m.warmUp)
    }

    // MARK: - What it counts toward (DESIGN.md §18)

    func testTheCostIsNotCounted() {
        var m = career()
        m.beginWarmUp(WarmUp.generate(day: day))
        playToTheCard(&m)
        XCTAssertEqual(m.tally.count(.pitches), 0)
        XCTAssertEqual(m.tally.count(.pitchesThisPark), 0)
        XCTAssertNil(m.tally.value(ifRecorded: .pitchesToTheShow))
        XCTAssertNil(m.tally.value(ifRecorded: .fewestPitchesToClearPark))
    }

    func testEverythingElseIsCounted() {
        var m = career()
        m.beginWarmUp(WarmUp.generate(day: day))
        playToTheCard(&m)
        XCTAssertEqual(m.tally.count(.swings), 10)
        XCTAssertEqual(m.tally.count(.hits), 10)
        XCTAssertGreaterThan(m.tally.count(.homeRuns), 0)
        XCTAssertGreaterThan(m.tally.count(.totalFeet), 0)
        XCTAssertGreaterThan(m.tally.count(.longestFeet), 0)
        XCTAssertGreaterThan(m.tally[.secondsPlayed], 0)
        XCTAssertEqual(PitchType.all.reduce(0) { $0 + m.tally.count(.seen($1)) }, 10)
    }

    func testTheCareerHomeRunStreakIsNeitherFedNorEnded() {
        var m = career(homeRunStreak: 3)
        m.beginWarmUp(WarmUp.generate(day: day))
        // A home run, then a whiff: either one would move a career streak.
        play(&m, seconds: 1.2, swinging: false)
        m.slice(perfectCrossing(m))
        XCTAssertEqual(m.tally.homeRunStreak, 3)
        XCTAssertEqual(m.streakNow, 1)
        play(&m, seconds: 12, swinging: false)
        XCTAssertEqual(m.beat, .pitch)
        m.sliceMissed()
        XCTAssertEqual(m.tally.homeRunStreak, 3, "a warm-up whiff cannot end a career streak")
        XCTAssertEqual(m.streakNow, 0)
    }

    func testStreakNowFollowsWhicheverStreakIsLive() {
        var m = career(homeRunStreak: 4)
        XCTAssertEqual(m.streakNow, 4)
        m.beginWarmUp(WarmUp.generate(day: day))
        play(&m, seconds: 1, swinging: false)
        XCTAssertEqual(m.streakNow, 0, "the Warm Up's own streak starts at nothing")
        playToTheCard(&m)
        XCTAssertEqual(m.streakNow, 4, "and the career's is exactly where it was left")
    }

    func testAResumedWarmUpKeepsTheStreakItHadEarned() {
        var m = career()
        let already = [WarmUpPitch(outcome: .inPlay, feet: 120),
                       WarmUpPitch(outcome: .homeRun, feet: 401),
                       WarmUpPitch(outcome: .homeRun, feet: 388)]
        m.beginWarmUp(WarmUp.generate(day: day), resuming: already)
        play(&m, seconds: 1, swinging: false)
        XCTAssertEqual(m.streakNow, 2)
    }

    func testTheWarmUpsOwnStatsAreCounted() {
        var m = career()
        m.beginWarmUp(WarmUp.generate(day: day))
        let (result, _) = playToTheCard(&m)
        XCTAssertEqual(m.tally.count(.warmUps), 1)
        XCTAssertEqual(m.tally.count(.warmUpBestFeet), result?.totalFeet)
        XCTAssertEqual(m.tally.count(.warmUpBestHomeRuns), result?.homeRuns)
        XCTAssertEqual(m.tally.count(.warmUpDaysInARow), 1)
        XCTAssertEqual(m.tally.count(.bestWarmUpDaysInARow), 1)
    }

    func testDaysInARowCountsConsecutiveDaysAndResetsOnAGap() {
        var m = career()
        m.beginWarmUp(WarmUp.generate(day: dayBefore))
        playToTheCard(&m)
        XCTAssertEqual(m.tally.count(.warmUpDaysInARow), 1)

        m.beginWarmUp(WarmUp.generate(day: day))
        playToTheCard(&m)
        XCTAssertEqual(m.tally.count(.warmUpDaysInARow), 2)
        XCTAssertEqual(m.tally.count(.warmUps), 2)

        m.beginWarmUp(WarmUp.generate(day: day + 2))            // a day skipped
        playToTheCard(&m)
        XCTAssertEqual(m.tally.count(.warmUpDaysInARow), 1)
        XCTAssertEqual(m.tally.count(.bestWarmUpDaysInARow), 2)
    }

    // MARK: - What it must not touch

    func testAWarmUpHomeRunDoesNotChangeTheParkOrCallAnyoneUp() {
        var m = career()
        let careerPark = m.park
        m.beginWarmUp(WarmUp.generate(day: day))
        let (_, seen) = playToTheCard(&m)
        XCTAssertGreaterThan(m.tally.count(.homeRuns), 0)
        XCTAssertEqual(m.tally.count(.parksCleared), 1, "no park was cleared by the daily ten")
        XCTAssertEqual(m.park, careerPark)
        XCTAssertFalse(seen.contains(.calledUp))
        XCTAssertFalse(seen.contains { if case .parkChanged = $0 { return true }; return false })
    }

    func testTheCeilingIsIgnoredInsideAWarmUp() {
        var m = career()
        m.parkCeiling = 2                                   // the career is standing at it
        XCTAssertTrue(m.isAtCeiling)
        m.beginWarmUp(WarmUp.generate(day: day))
        play(&m, seconds: 1, swinging: false)
        XCTAssertFalse(m.isAtCeiling, "the day's park is not the one being cleared")
        let (_, seen) = playToTheCard(&m)
        XCTAssertFalse(seen.contains(.calledUp))
        XCTAssertTrue(m.isAtCeiling, "and the career is still standing at its ceiling")
        XCTAssertEqual(m.park.number, 2)
    }

    /// The whole promise of §18 in one assertion: after a Warm Up, the career machine is
    /// indistinguishable from one built fresh with the same seed, park and tally — same next
    /// pitch, same generator state, nothing of the day left standing. The stats are the one
    /// thing that moved, and they are handed to the fresh machine so they cannot hide a
    /// difference anywhere else.
    func testTheCareerMachineIsUnchangedApartFromTheStatsItCounted() {
        var m = career(seed: 7)
        let fresh = DerbyMachine(seed: 7, park: m.park, tally: m.tally)
        XCTAssertEqual(m, fresh, "the control: nothing has happened yet")

        m.beginWarmUp(WarmUp.generate(day: day))
        let (result, _) = playToTheCard(&m)
        XCTAssertNotNil(result)
        XCTAssertEqual(m, DerbyMachine(seed: 7, park: m.careerPark, tally: m.tally))
    }

    func testTheCareerPitchSequenceIsIdenticalWhetherOrNotItWasPlayed() {
        var withOut = career(seed: 11)
        var with = career(seed: 11)
        with.beginWarmUp(WarmUp.generate(day: day))
        playToTheCard(&with)

        func nextPitches(_ m: inout DerbyMachine, count: Int) -> [Pitch] {
            var seen: [Pitch] = [m.pitch]
            var t = 0.0
            while seen.count < count, t < 120 {
                if m.beat == .pitch, m.pitchProgress >= 0.97 { m.slice(perfectCrossing(m)) }
                m.tick(1.0 / 60)
                t += 1.0 / 60
                if m.beat == .windup, m.pitch != seen.last { seen.append(m.pitch) }
            }
            return seen
        }
        XCTAssertEqual(nextPitches(&with, count: 6), nextPitches(&withOut, count: 6))
    }
}
