import XCTest
@testable import DerbyCore

/// The pitcher waits for the organist (#46, DESIGN.md §11, §3): while an organ cue the app just
/// started is still sounding, the windup does not advance — `AtBatScene.drawPitcher` keeps
/// drawing the set pose — and the ordinary 0.5 s windup plays once the cue ends or
/// `Timings.maxMusicHold` is reached, whichever comes first.
final class MusicHoldTests: XCTestCase {
    @discardableResult
    private func run(_ m: inout DerbyMachine, seconds: Double, dt: Double = 1.0 / 60) -> [Transition] {
        var out: [Transition] = []
        var t = 0.0
        while t < seconds { out += m.tick(dt); t += dt }
        return out
    }

    /// Ticks until `transition` appears and returns how much time that took from *this* call,
    /// or nil if `budget` runs out first.
    private func timeUntil(_ transition: Transition, _ m: inout DerbyMachine,
                           dt: Double = 1.0 / 60, budget: Double = 15) -> Double? {
        var t = 0.0
        while t < budget {
            t += dt
            if m.tick(dt).contains(transition) { return t }
        }
        return nil
    }

    private func perfectCrossing(_ m: DerbyMachine) -> SliceCrossing {
        SliceCrossing(quality: 1, progress: 1, swingAngleDegrees: 28, power: 1,
                      ball: m.ballNow, crossingPoint: m.ballNow.position)
    }

    @discardableResult
    private func run(_ m: inout DerbyMachine, until beat: Beat, budget: Double = 30) -> [Transition] {
        var out: [Transition] = []
        var t = 0.0
        while m.beat != beat && t < budget { out += m.tick(1.0 / 60); t += 1.0 / 60 }
        return out
    }

    /// One home run, played all the way out to the next windup. Mirrors `ProgressTests.homer`.
    @discardableResult
    private func homer(_ m: inout DerbyMachine) -> [Transition] {
        run(&m, until: .pitch)
        m.slice(perfectCrossing(m))
        return run(&m, until: .windup)
    }

    // MARK: - The hold itself

    func testHoldDelaysPitchThrownByItsRemainingLengthAndNoMore() {
        var m = DerbyMachine(seed: 1)
        XCTAssertEqual(m.beat, .windup)
        XCTAssertFalse(m.isHoldingForMusic)
        m.holdForMusic(1.0)
        XCTAssertTrue(m.isHoldingForMusic)
        guard let time = timeUntil(.pitchThrown, &m) else { return XCTFail("pitchThrown never fired") }
        XCTAssertEqual(time, 1.0 + m.timings.windup, accuracy: 0.08)
    }

    func testTheCapStopsTheHoldAndThePitchCutsItOffAsBefore() {
        var m = DerbyMachine(seed: 1)
        m.holdForMusic(10)                          // the funeral march is the one cue this long
        guard let time = timeUntil(.pitchThrown, &m) else { return XCTFail("pitchThrown never fired") }
        XCTAssertEqual(time, m.timings.maxMusicHold + m.timings.windup, accuracy: 0.08)
        XCTAssertLessThan(time, 10, "the cap must win, not the full 10 s hold")
    }

    func testHoldDuringMissAppliesToTheWindupThatFollows() {
        var m = DerbyMachine(seed: 1)
        run(&m, seconds: 0.6)                       // into .pitch
        m.sliceMissed()
        XCTAssertEqual(m.beat, .miss)
        m.holdForMusic(1.5)                         // longer than the 1.2 s miss hold
        run(&m, until: .windup)
        XCTAssertEqual(m.beat, .windup)
        XCTAssertTrue(m.isHoldingForMusic, "part of the hold outlived the miss")
        guard let thrownAt = timeUntil(.pitchThrown, &m) else { return XCTFail("pitchThrown never fired") }
        // ~0.3 s of the 1.5 s hold was left when the miss ended, plus the ordinary windup.
        XCTAssertEqual(thrownAt, 0.3 + m.timings.windup, accuracy: 0.08)
    }

    func testHoldDuringResultAppliesToTheWindupThatFollows() {
        var m = DerbyMachine(seed: 3)
        run(&m, until: .pitch)
        m.slice(SliceCrossing(quality: 0, progress: 1, swingAngleDegrees: -20, power: 0.3,
                              ball: m.ballNow, crossingPoint: m.ballNow.position))   // a chopper, not a homer
        run(&m, until: .result)
        m.holdForMusic(2.0)                         // longer than the 1.3 s result hold
        run(&m, until: .windup)
        XCTAssertTrue(m.isHoldingForMusic, "part of the hold outlived the result")
        guard let thrownAt = timeUntil(.pitchThrown, &m) else { return XCTFail("pitchThrown never fired") }
        // ~0.7 s of the 2.0 s hold was left when the result ended, plus the ordinary windup.
        XCTAssertEqual(thrownAt, 0.7 + m.timings.windup, accuracy: 0.1)
    }

    func testTwoOverlappingHoldsTakeTheLonger() {
        func totalDelay(secondHold: Double, budget: Double = 5) -> Double? {
            var m = DerbyMachine(seed: 1)
            m.holdForMusic(0.5)
            var t = 0.0, toldSecond = false
            while t < budget {
                if !toldSecond, t >= 0.1 { m.holdForMusic(secondHold); toldSecond = true }
                t += 1.0 / 60
                if m.tick(1.0 / 60).contains(.pitchThrown) { return t }
            }
            return nil
        }
        let windup = DerbyMachine(seed: 1).timings.windup
        guard let shorter = totalDelay(secondHold: 0.2) else { return XCTFail() }
        XCTAssertEqual(shorter, 0.5 + windup, accuracy: 0.08,
                       "a shorter second call must not cut the first one short")
        guard let longer = totalDelay(secondHold: 2.0) else { return XCTFail() }
        XCTAssertEqual(longer, 0.1 + 2.0 + windup, accuracy: 0.1, "a longer second call wins")
    }

    /// The existing-behaviour case: nothing calls `holdForMusic`, so nothing changes from before
    /// #46 — `.pitchThrown` fires at exactly the ordinary windup.
    func testNoHoldChangesNothing() {
        var m = DerbyMachine(seed: 1)
        XCTAssertFalse(m.isHoldingForMusic)
        guard let time = timeUntil(.pitchThrown, &m) else { return XCTFail("pitchThrown never fired") }
        XCTAssertEqual(time, m.timings.windup, accuracy: 0.05)
        XCTAssertFalse(m.isHoldingForMusic)
    }

    // MARK: - What must never wait on the organist (#40, #18)

    /// The ceiling's owed advance (DESIGN.md §16) still pays at the very next windup, hold or no
    /// hold — mirrors `ProgressTests.testTheCeilingIsOwedByTheThirdAndTheCountThenStaysMet`.
    func testAnOwedAdvanceIsNotDelayedByAMusicHold() {
        var m = DerbyMachine(seed: 3, park: Park.generate(number: 3))
        m.parkCeiling = 3
        homer(&m)
        homer(&m)
        let third = homer(&m)
        XCTAssertTrue(third.contains(.calledUp))
        XCTAssertEqual(m.beat, .windup)
        m.holdForMusic(10)                          // an organ cue is (pretend) still sounding
        XCTAssertTrue(m.isHoldingForMusic)
        m.parkCeiling = nil                         // signed: the advance is owed
        XCTAssertEqual(m.tick(1.0 / 60), [.parkChanged(Park.generate(number: 4))],
                       "the advance pays on the very next tick, hold or no hold")
    }

    /// The day's ten (DESIGN.md §18) still take the field at the very next windup, hold or no
    /// hold — mirrors `WarmUpTests.testBeginsAtTheNextWindupNeverInTheMiddleOfAPitch`.
    func testAQueuedWarmUpIsNotDelayedByAMusicHold() {
        var t = Tally()
        t.set(.parksCleared, 1)                     // the Warm Up's gate
        var m = DerbyMachine(seed: 7, park: Park.generate(number: 2), tally: t)
        XCTAssertEqual(m.beat, .windup)
        m.holdForMusic(10)
        XCTAssertTrue(m.isHoldingForMusic)
        m.beginWarmUp(WarmUp.generate(day: 20260920))
        let seen = m.tick(1.0 / 60)
        XCTAssertTrue(seen.contains(.warmUpBegan), "the day's ten take the field on the very next tick")
        XCTAssertNotNil(m.warmUp)
    }

    // MARK: - A replay never carries a live hold with it (§19)

    /// `Replay` keeps only the inputs `slice(_:)` needs, never derived state, and `machine(from:)`
    /// builds a fresh `DerbyMachine`: a hold in progress on the live machine at the moment of
    /// contact has nowhere to ride along on, and the rebuilt machine's next windup is ordinary.
    func testANonzeroMusicHoldNeverLeaksIntoAReplayOrARebuiltMachine() {
        var live = DerbyMachine(seed: 3)
        run(&live, seconds: 0.6)                    // into .pitch
        live.holdForMusic(100)                       // pretend an organ cue is still sounding live
        let crossing = perfectCrossing(live)
        let record = Replay(capturing: live, crossing: crossing, slash: Point(x: 1, y: 0), trail: [])
        var rebuilt = Replay.machine(from: record)
        run(&rebuilt, until: .windup, budget: 20)
        XCTAssertEqual(rebuilt.beat, .windup)
        XCTAssertFalse(rebuilt.isHoldingForMusic, "nothing of the live machine's hold survived the record")
        guard let thrownAt = timeUntil(.pitchThrown, &rebuilt) else { return XCTFail("pitchThrown never fired") }
        XCTAssertEqual(thrownAt, rebuilt.timings.windup, accuracy: 0.05, "an ordinary windup, not a held one")
    }
}
