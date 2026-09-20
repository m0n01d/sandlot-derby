import XCTest
@testable import DerbyCore

/// Home-run fireworks: the streak table, the no-doubter and call-up rules, and the particle
/// maths itself. DESIGN.md §17 "### Fireworks".
final class FireworksTests: XCTestCase {
    // MARK: - The streak table, in isolation

    func testStreakTableExactly() {
        let r = FireworksRules.standard
        let expected: [Int: Int] = [
            1: 0, 2: 0,             // nothing yet
            3: 1, 4: 2, 5: 3,       // the first shells
            6: 4, 7: 5, 8: 6, 9: 7, // 6...9
            10: 10,                 // the first finale
            11: 8, 12: 8, 13: 8, 14: 8,   // between finales
            15: 10, 20: 10, 25: 10,       // every 5 after
            16: 8, 24: 8,
        ]
        for (streak, shells) in expected.sorted(by: { $0.key < $1.key }) {
            XCTAssertEqual(r.shellCount(homeRunStreak: streak, isCalledUp: false, isNoDoubter: false),
                            shells, "streak \(streak)")
        }
    }

    func testNoDoubterAddsOneShellOnlyOnceFireworksAreEarned() {
        let r = FireworksRules.standard
        XCTAssertEqual(r.shellCount(homeRunStreak: 1, isCalledUp: false, isNoDoubter: true), 0)
        XCTAssertEqual(r.shellCount(homeRunStreak: 2, isCalledUp: false, isNoDoubter: true), 0)
        XCTAssertEqual(r.shellCount(homeRunStreak: 3, isCalledUp: false, isNoDoubter: true), 2)
        XCTAssertEqual(r.shellCount(homeRunStreak: 6, isCalledUp: false, isNoDoubter: true), 5)
        XCTAssertEqual(r.shellCount(homeRunStreak: 10, isCalledUp: false, isNoDoubter: true), 11)
    }

    func testCallUpIsAFinaleWhateverTheStreak() {
        let r = FireworksRules.standard
        XCTAssertEqual(r.shellCount(homeRunStreak: 1, isCalledUp: true, isNoDoubter: false), 10)
        XCTAssertEqual(r.shellCount(homeRunStreak: 9, isCalledUp: true, isNoDoubter: false), 10)
        XCTAssertEqual(r.shellCount(homeRunStreak: 1, isCalledUp: true, isNoDoubter: true), 11)
    }

    // MARK: - `DerbyMachine` integration

    /// 115 mph at 28°: a home run in any park the rules can generate (see `StatsTests.bomb`).
    private func bomb(_ m: DerbyMachine) -> SliceCrossing {
        SliceCrossing(quality: 1, progress: 1, swingAngleDegrees: 28, power: 1,
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

    /// A park deep in the majors: every home run advances the park number, but the league stays
    /// `.theShow`, so a run of home runs never collides with the call-up (Triple-A only clears
    /// once, and these tests want the streak table in isolation from it).
    private func majorsMachine(seed: UInt64) -> DerbyMachine { DerbyMachine(seed: seed, park: Park.generate(number: 20)) }

    func testFireworksNilDuringWindupPitchAndMiss() {
        var m = majorsMachine(seed: 1)
        XCTAssertNil(m.fireworks)
        toNextPitch(&m)
        XCTAssertNil(m.fireworks)
        m.sliceMissed()
        XCTAssertNil(m.fireworks)
        run(&m, until: .windup)
        XCTAssertNil(m.fireworks)
    }

    /// The streak already reflects the swing that just landed (`countContact` runs at contact,
    /// well before the ball reaches the wall), so the third straight home run's own cue sees a
    /// streak of 3 and shows exactly one shell — not zero, not two.
    func testThirdStraightHomeRunShowsExactlyOneShell() {
        var m = majorsMachine(seed: 3)
        m.statRules.noDoubterMarginFeet = 10_000   // isolate the streak table from the no-doubter bonus
        for _ in 0..<2 {
            toNextPitch(&m)
            m.slice(bomb(m))
            XCTAssertTrue(m.flight?.homeRun ?? false)
            run(&m, until: .windup)
        }
        XCTAssertEqual(m.tally.homeRunStreak, 2)

        toNextPitch(&m)
        m.slice(bomb(m))
        XCTAssertNil(m.fireworks)          // contact, but the ball hasn't reached the wall yet
        run(&m, until: .result)
        XCTAssertEqual(m.tally.homeRunStreak, 3)
        XCTAssertEqual(m.fireworks?.shellCount, 1)

        run(&m, until: .windup)
        XCTAssertNil(m.fireworks)          // the next pitch gets a clean sky
    }

    func testFinaleAtStreakOfTenThroughTheMachine() {
        var m = majorsMachine(seed: 9)
        m.statRules.noDoubterMarginFeet = 10_000   // isolate the streak table from the no-doubter bonus
        for _ in 0..<9 {
            toNextPitch(&m)
            m.slice(bomb(m))
            run(&m, until: .windup)
        }
        XCTAssertEqual(m.tally.homeRunStreak, 9)

        toNextPitch(&m)
        m.slice(bomb(m))
        run(&m, until: .result)
        XCTAssertEqual(m.tally.homeRunStreak, 10)
        XCTAssertEqual(m.fireworks?.shellCount, 10)
    }

    func testNoDoubterAddsAShellThroughTheMachine() {
        var m = majorsMachine(seed: 3)
        for _ in 0..<2 {
            toNextPitch(&m)
            m.slice(bomb(m))
            run(&m, until: .windup)
        }
        toNextPitch(&m)
        m.slice(bomb(m))
        let past = (m.flight?.distanceFeet ?? 0) - m.park.wallDistanceFeet
        XCTAssertGreaterThanOrEqual(past, m.statRules.noDoubterMarginFeet, "bomb() should clear by more than a no-doubter's margin")
        run(&m, until: .result)
        XCTAssertEqual(m.fireworks?.shellCount, 2)   // 1 for the streak of 3, +1 no-doubter
    }

    func testCallUpIsAFinaleEvenOnAFreshStreak() {
        var m = DerbyMachine(seed: 3, park: Park.generate(number: 3))   // Triple-A
        m.statRules.noDoubterMarginFeet = 10_000   // isolate the call-up rule from the no-doubter bonus
        toNextPitch(&m)
        m.slice(bomb(m))
        run(&m, until: .result)
        XCTAssertTrue(m.isBeingCalledUp)
        XCTAssertEqual(m.tally.homeRunStreak, 1)
        XCTAssertEqual(m.fireworks?.shellCount, 10)
    }

    // MARK: - `Fireworks.particles`: pure maths

    func testParticlesAreDeterministic() {
        let show = FireworksShow(shellCount: 5, seed: 12_345, start: 10, isNight: false)
        let a = Fireworks.particles(show: show, at: 10.6)
        let b = Fireworks.particles(show: show, at: 10.6)
        XCTAssertEqual(a, b)
        XCTAssertFalse(a.isEmpty)
    }

    func testRiserIsOneChalkPixelThatClimbs() {
        let show = FireworksShow(shellCount: 1, seed: 7, start: 0, isNight: false)
        let rules = FireworksRules.standard
        let early = Fireworks.particles(show: show, at: 0.02, rules: rules)
        XCTAssertEqual(early.count, 1)
        XCTAssertEqual(early[0].colour, .chalk)
        XCTAssertEqual(early[0].size, 1)
        let late = Fireworks.particles(show: show, at: rules.risePeriod - 0.01, rules: rules)
        // Climbing: closer to the burst height than the start just before the burst.
        XCTAssertLessThan(abs(late[0].y - early[0].y), rules.riserStartY)
    }

    func testBurstParticleCountAndLifetimeBounds() {
        let show = FireworksShow(shellCount: 1, seed: 7, start: 0, isNight: false)
        let rules = FireworksRules.standard

        let beforeLaunch = Fireworks.particles(show: show, at: -0.01, rules: rules)
        XCTAssertTrue(beforeLaunch.isEmpty)

        let midBurst = Fireworks.particles(show: show, at: rules.risePeriod + 0.1, rules: rules)
        XCTAssertTrue(rules.particleCountRange.contains(midBurst.count), "\(midBurst.count) particles")

        let afterItDies = Fireworks.particles(show: show, at: rules.risePeriod + rules.burstLifetime + 1, rules: rules)
        XCTAssertTrue(afterItDies.isEmpty)
    }

    func testShellsStayWithinTheirScreenBand() {
        let rules = FireworksRules.standard
        let show = FireworksShow(shellCount: 10, seed: 99, start: 0, isNight: true)
        // Sample across the whole finale's span: every particle's x is screen-space (drawn as
        // `width * x`) and should sit in (or very near) the right 45%.
        var sampled = 0
        var t = 0.0
        while t < 3 {
            for p in Fireworks.particles(show: show, at: t, rules: rules) {
                sampled += 1
                XCTAssertGreaterThan(p.x, rules.bandXRange.lowerBound - 0.15)
                XCTAssertLessThan(p.x, rules.bandXRange.upperBound + 0.15)
                XCTAssertGreaterThan(p.y, -20)
                XCTAssertLessThan(p.y, 250)
            }
            t += 0.05
        }
        XCTAssertGreaterThan(sampled, 0)
    }

    func testNightOffersSky3ButDayNeverDoes() {
        let rules = FireworksRules.standard
        var sawSky3 = false
        for seed in UInt64(0)..<40 {
            let show = FireworksShow(shellCount: 1, seed: seed, start: 0, isNight: false)
            let particles = Fireworks.particles(show: show, at: rules.risePeriod + 0.1, rules: rules)
            XCTAssertFalse(particles.contains { $0.colour == .sky3 })
        }
        for seed in UInt64(0)..<40 {
            let show = FireworksShow(shellCount: 1, seed: seed, start: 0, isNight: true)
            let particles = Fireworks.particles(show: show, at: rules.risePeriod + 0.1, rules: rules)
            if particles.contains(where: { $0.colour == .sky3 }) { sawSky3 = true }
        }
        XCTAssertTrue(sawSky3, "sky3 should turn up at night across 40 seeds")
    }
}
