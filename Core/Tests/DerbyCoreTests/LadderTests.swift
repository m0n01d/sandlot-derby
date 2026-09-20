import XCTest
@testable import DerbyCore

final class LadderTests: XCTestCase {
    private func crossing(_ m: DerbyMachine, quality: Double, power: Double, angle: Double) -> SliceCrossing {
        SliceCrossing(quality: quality, progress: 1, swingAngleDegrees: angle, power: power,
                      ball: m.ballNow, crossingPoint: m.ballNow.position)
    }

    private func toNextPitch(_ m: inout DerbyMachine) {
        var waited = 0.0
        while m.beat != .pitch && waited < 30 { m.tick(1.0 / 60); waited += 1.0 / 60 }
        XCTAssertEqual(m.beat, .pitch)
    }

    /// Ticks until `beat`, returning every transition on the way.
    @discardableResult
    private func run(_ m: inout DerbyMachine, until beat: Beat) -> [Transition] {
        var out: [Transition] = []
        var waited = 0.0
        while m.beat != beat && waited < 30 { out += m.tick(1.0 / 60); waited += 1.0 / 60 }
        XCTAssertEqual(m.beat, beat)
        return out
    }

    func testTheLadderIsThreeRungsThenTheShow() {
        let walls = (1...4).map { Park.generate(number: $0) }
        XCTAssertEqual(walls.map(\.wallDistanceFeet), [280, 320, 350, 380])
        XCTAssertEqual(walls.map(\.wallHeightFeet), [6, 8, 10, 10])
        XCTAssertEqual(walls.map(\.displayName), ["SINGLE-A", "DOUBLE-A", "TRIPLE-A", "PARK 4"])
        XCTAssertTrue(walls.allSatisfy { !$0.isNight })
        XCTAssertEqual(Park.generate(number: 4).league, .theShow)
        XCTAssertEqual(Park.generate(number: 900).league, .theShow)
        XCTAssertEqual(Park.generate(number: 900).displayName, "PARK 900")
    }

    func testSingleAThrowsOnlySlowStrikes() {
        var m = DerbyMachine(seed: 21)
        for _ in 0..<60 {
            toNextPitch(&m)
            XCTAssertEqual(m.pitch.type.name, "FASTBALL")
            XCTAssertTrue((68.0...76.0).contains(m.pitch.speedMPH))
            XCTAssertTrue(m.pitch.isStrike)
            m.sliceMissed()
        }
        XCTAssertEqual(m.park.number, 1)
    }

    func testDoubleAAddsTheChangeupAndBallsButNoCurve() {
        var m = DerbyMachine(seed: 22, park: Park.generate(number: 2))
        var names = Set<String>(), balls = 0
        for _ in 0..<200 {
            toNextPitch(&m)
            names.insert(m.pitch.type.name)
            if !m.pitch.isStrike { balls += 1 }
            m.sliceMissed()
        }
        XCTAssertEqual(names, ["FASTBALL", "CHANGEUP"])
        XCTAssertGreaterThan(balls, 10)
        XCTAssertLessThan(balls, 60)
    }

    func testEachRungIsLessForgivingAndTheShowIsTheStandardRules() {
        let margins = (1...4).map { DerbyMachine(seed: 1, park: Park.generate(number: $0)).sliceRules.hitMarginPixels }
        XCTAssertEqual(margins, [14, 12, 10, SliceRules.standard.hitMarginPixels])
        let show = DerbyMachine(seed: 1, park: Park.generate(number: 4))
        XCTAssertEqual(show.sliceRules, .standard)
        XCTAssertEqual(show.pitchingRules, .standard)
        XCTAssertNil(show.rung)
        XCTAssertEqual(DerbyMachine(seed: 1).rung?.swingGuide, true)
        XCTAssertEqual(DerbyMachine(seed: 1, park: Park.generate(number: 2)).rung?.swingGuide, false)
        XCTAssertEqual(DerbyMachine(seed: 1, park: Park.generate(number: 2)).rung?.timingRing, true)
        XCTAssertEqual(DerbyMachine(seed: 1, park: Park.generate(number: 3)).rung?.timingRing, false)
    }

    /// The reason the minors exist: half timing and half speed is a home run in Single-A and
    /// nowhere near one in The Show.
    func testAHalfDecentSwingClearsSingleAButNotTheShow() {
        var a = DerbyMachine(seed: 5)
        toNextPitch(&a)
        a.slice(crossing(a, quality: 0.5, power: 0.5, angle: 28))
        XCTAssertTrue(a.flight?.homeRun ?? false)

        var show = DerbyMachine(seed: 5, park: Park.generate(number: 4))
        toNextPitch(&show)
        show.slice(crossing(show, quality: 0.5, power: 0.5, angle: 28))
        XCTAssertFalse(show.flight?.homeRun ?? true)
    }

    func testClearingTripleAIsACallUpOnceAndCounted() {
        var m = DerbyMachine(seed: 3, park: Park.generate(number: 3))
        toNextPitch(&m)
        m.sliceMissed()
        toNextPitch(&m)
        m.slice(crossing(m, quality: 1, power: 1, angle: 28))
        run(&m, until: .result)
        XCTAssertTrue(m.isBeingCalledUp)
        let t = run(&m, until: .windup)
        XCTAssertTrue(t.contains(.calledUp))
        XCTAssertEqual(m.park.number, 4)
        XCTAssertEqual(m.tally.count(.pitchesToTheShow), 2)
        XCTAssertFalse(m.isBeingCalledUp)

        // The next park up is just a park.
        toNextPitch(&m)
        m.slice(crossing(m, quality: 1, power: 1, angle: 28))
        let later = run(&m, until: .windup)
        XCTAssertFalse(later.contains(.calledUp))
        XCTAssertEqual(m.tally.count(.pitchesToTheShow), 2)
    }

    func testClearingSingleAIsNotACallUp() {
        var m = DerbyMachine(seed: 3)
        toNextPitch(&m)
        m.slice(crossing(m, quality: 1, power: 1, angle: 28))
        run(&m, until: .result)
        XCTAssertFalse(m.isBeingCalledUp)
        let t = run(&m, until: .windup)
        XCTAssertFalse(t.contains(.calledUp))
        XCTAssertEqual(m.park.displayName, "DOUBLE-A")
        XCTAssertNil(m.tally.value(ifRecorded: .pitchesToTheShow))
    }

    func testCoachingNamesTheFixAimBeforePower() {
        func word(park: Int, quality: Double, power: Double, angle: Double) -> String? {
            var m = DerbyMachine(seed: 9, park: Park.generate(number: park))
            toNextPitch(&m)
            m.slice(crossing(m, quality: quality, power: power, angle: angle))
            XCTAssertNil(m.coachingWord)                    // never before the ball has landed
            run(&m, until: .result)
            return m.coachingWord
        }
        XCTAssertEqual(word(park: 1, quality: 0, power: 0.3, angle: -20), "SWING UP")
        XCTAssertEqual(word(park: 1, quality: 0, power: 0.3, angle: 60), "LEVEL OUT")
        XCTAssertEqual(word(park: 1, quality: 0, power: 0.3, angle: 28), "FASTER")
        XCTAssertNil(word(park: 1, quality: 1, power: 1, angle: 28))       // a home run needs no note
        XCTAssertNil(word(park: 4, quality: 0, power: 0.3, angle: -20))    // nobody coaches in The Show
    }

    /// #17: a sandlot has no organist. Every rung above it does, and so does The Show, which has
    /// no rung at all.
    func testOnlySingleALacksAnOrgan() {
        XCTAssertFalse(DerbyMachine(seed: 1, park: Park.generate(number: 1)).hasOrgan)
        XCTAssertTrue(DerbyMachine(seed: 1, park: Park.generate(number: 2)).hasOrgan)
        XCTAssertTrue(DerbyMachine(seed: 1, park: Park.generate(number: 3)).hasOrgan)
        XCTAssertTrue(DerbyMachine(seed: 1, park: Park.generate(number: 4)).hasOrgan)
        XCTAssertNil(DerbyMachine(seed: 1, park: Park.generate(number: 4)).rung)
    }

    /// #17: *Three Blind Mice*'s cue. There is no third strike in this game, so it is two in a
    /// row, not three, and it doesn't repeat if the streak keeps going.
    func testTwoCalledStrikesInARowFiresOnceNotOnTheThird() {
        var m = DerbyMachine(seed: 21)                       // Single-A: every pitch is a strike
        toNextPitch(&m)
        XCTAssertEqual(m.calledStrikesInARow, 0)
        let first = run(&m, until: .windup)                  // taken, not swung at
        XCTAssertFalse(first.contains(.calledStrikesInARow))
        XCTAssertEqual(m.calledStrikesInARow, 1)

        toNextPitch(&m)
        let second = run(&m, until: .windup)
        XCTAssertTrue(second.contains(.calledStrikesInARow))
        XCTAssertEqual(m.calledStrikesInARow, 2)

        toNextPitch(&m)
        let third = run(&m, until: .windup)
        XCTAssertFalse(third.contains(.calledStrikesInARow))  // fired once, not on every strike after
        XCTAssertEqual(m.calledStrikesInARow, 3)

        toNextPitch(&m)
        m.sliceMissed()                                       // any swing breaks the streak
        XCTAssertEqual(m.calledStrikesInARow, 0)
    }
}
