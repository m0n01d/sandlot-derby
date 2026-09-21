import XCTest
@testable import DerbyCore

/// The night kit, the birds, and the window the crowd and the lights share. Everything here is
/// a pure function of a seed and a clock, so every one of these tests is an equality (DESIGN.md
/// §17 "Everything is a pure function").
final class SkyLifeTests: XCTestCase {
    private let rules = SkyLifeRules.standard
    private let scenery = SceneryRules.standard

    // MARK: - Stars

    /// Every park is seeded the full forty since §20 — the phase says how many of them show, and
    /// `twilight` shows the first `twilightStars` of exactly this list.
    func testEveryParkGetsTheFullStarfield() {
        var nights = 0, days = 0
        for n in 1...200 {
            let park = Park.generate(number: n)
            let s = park.scenery
            if park.nightSeed { nights += 1 } else { days += 1 }
            XCTAssertEqual(s.stars.count, scenery.starCount, "park \(n)")
            for star in s.stars {
                XCTAssertTrue(scenery.starBand.contains(star.y), "park \(n) star at \(star.y)")
                XCTAssertTrue((0...1).contains(star.xFraction))
            }
        }
        XCTAssertGreaterThan(nights, 0)
        XCTAssertGreaterThan(days, 0)
    }

    func testOneStarInEightBlinks() {
        let s = firstNightPark().scenery
        let blinking = s.stars.filter { $0.blinkPeriod != nil }
        XCTAssertEqual(blinking.count, scenery.starCount / scenery.blinkingStarInEvery)
        for star in blinking {
            XCTAssertTrue(scenery.starBlinkPeriod.contains(star.blinkPeriod!))
            XCTAssertTrue((0..<star.blinkPeriod!).contains(star.blinkPhase))
        }
    }

    func testAStarThatDoesNotBlinkIsAlwaysLitAndOneThatDoesGoesOutAndComesBack() {
        let steady = Star(xFraction: 0.5, y: 20, blinkPeriod: nil, blinkPhase: 0)
        for t in stride(from: 0.0, through: 30.0, by: 0.1) {
            XCTAssertTrue(SkyLife.starIsLit(steady, at: t, rules: rules))
        }

        let winker = Star(xFraction: 0.5, y: 20, blinkPeriod: 5, blinkPhase: 0)
        // Out for `starBlinkOffSeconds` at the top of each period, lit for the rest of it.
        XCTAssertFalse(SkyLife.starIsLit(winker, at: 0, rules: rules))
        XCTAssertFalse(SkyLife.starIsLit(winker, at: rules.starBlinkOffSeconds - 0.01, rules: rules))
        XCTAssertTrue(SkyLife.starIsLit(winker, at: rules.starBlinkOffSeconds, rules: rules))
        XCTAssertTrue(SkyLife.starIsLit(winker, at: 4.9, rules: rules))
        XCTAssertFalse(SkyLife.starIsLit(winker, at: 5.0, rules: rules))
        XCTAssertTrue(SkyLife.starIsLit(winker, at: 5.0 + rules.starBlinkOffSeconds, rules: rules))
    }

    func testAStarIsOutForFarLessOfTheTimeThanItIsLit() {
        let winker = Star(xFraction: 0.5, y: 20, blinkPeriod: 4, blinkPhase: 1.3)
        var lit = 0, total = 0
        for t in stride(from: 0.0, through: 60.0, by: 0.05) {
            total += 1
            if SkyLife.starIsLit(winker, at: t, rules: rules) { lit += 1 }
        }
        XCTAssertGreaterThan(Double(lit) / Double(total), 0.85)
    }

    // MARK: - Towers

    /// Every park stands two to four towers since §20; the clock says whether they are lit.
    func testEveryParkGetsTwoToFourTowers() {
        for n in 1...200 {
            let park = Park.generate(number: n)
            let s = park.scenery
            XCTAssertTrue(scenery.towersPerNightPark.contains(s.towers), "park \(n) has \(s.towers)")
            XCTAssertEqual(s.towers, s.lightTowers.count, "the count is the towers themselves")
            for tower in s.lightTowers {
                XCTAssertTrue(scenery.towerDepthFeet.contains(tower.feetBehindWall), "park \(n)")
                XCTAssertTrue(scenery.towerHeightFeet.contains(tower.heightFeet), "park \(n)")
                XCTAssertTrue(scenery.towerBankColumns.contains(tower.bankColumns))
                XCTAssertTrue(scenery.towerBankRows.contains(tower.bankRows))
            }
        }
    }

    func testNoTwoTowersStandInTheSamePlace() {
        for n in 1...200 {
            let depths = Park.generate(number: n).scenery.lightTowers.map(\.feetBehindWall)
            XCTAssertEqual(Set(depths).count, depths.count, "park \(n) stacked two towers")
            XCTAssertEqual(depths, depths.sorted(), "park \(n) towers are not in depth order")
        }
    }

    func testTheBanksAreSteadyUntilTheCheerAndThenChaseBankToBank() {
        for t in stride(from: 0.0, through: 5.0, by: 0.05) {
            for i in 0..<4 {
                XCTAssertTrue(SkyLife.bankIsLit(i, at: t, chasing: false, rules: rules))
            }
        }
        // Chasing: neighbours disagree, and each bank flips from one step to the next.
        let stepSeconds = 1 / rules.chaseStepsPerSecond
        for k in 0..<8 {
            let t = Double(k) * stepSeconds + stepSeconds / 2
            XCTAssertNotEqual(SkyLife.bankIsLit(0, at: t, chasing: true, rules: rules),
                              SkyLife.bankIsLit(1, at: t, chasing: true, rules: rules))
            XCTAssertNotEqual(SkyLife.bankIsLit(0, at: t, chasing: true, rules: rules),
                              SkyLife.bankIsLit(0, at: t + stepSeconds, chasing: true, rules: rules))
        }
    }

    // MARK: - The crowd and the flags

    func testTheCrowdSitsStillUntilTheCheerAndThenBouncesInHalves() {
        for t in stride(from: 0.0, through: 3.0, by: 0.05) {
            for i in 0..<10 {
                XCTAssertFalse(SkyLife.crowdHeadIsUp(i, at: t, cheering: false, rules: rules))
            }
        }
        let stepSeconds = 1 / rules.crowdBounceStepsPerSecond
        for k in 0..<8 {
            let t = Double(k) * stepSeconds + stepSeconds / 2
            let up = (0..<20).filter { SkyLife.crowdHeadIsUp($0, at: t, cheering: true, rules: rules) }
            XCTAssertEqual(up.count, 10, "half the speckle is up on every step")
            XCTAssertNotEqual(SkyLife.crowdHeadIsUp(3, at: t, cheering: true, rules: rules),
                              SkyLife.crowdHeadIsUp(3, at: t + stepSeconds, cheering: true, rules: rules))
        }
    }

    func testAFlagHasExactlyTwoFlutterFramesAndAlternatesBetweenThem() {
        let stepSeconds = 1 / rules.flutterStepsPerSecond
        var seen = Set<Int>()
        for k in 0..<12 {
            let t = Double(k) * stepSeconds + stepSeconds / 2
            let frame = SkyLife.flutterFrame(at: t, rules: rules)
            seen.insert(frame)
            XCTAssertNotEqual(frame, SkyLife.flutterFrame(at: t + stepSeconds, rules: rules))
        }
        XCTAssertEqual(seen, [0, 1])
    }

    // MARK: - Birds

    func testBirdsAreAPureFunctionOfSeedAndTime() {
        for t in stride(from: 0.0, through: 90.0, by: 0.37) {
            XCTAssertEqual(SkyLife.birds(seed: 7, at: t, breeze: 2, rules: rules, scenery: scenery),
                           SkyLife.birds(seed: 7, at: t, breeze: 2, rules: rules, scenery: scenery))
        }
    }

    func testEachViewGetsItsOwnFlocks() {
        // The two views look in different directions, so they never share a flock (§17).
        var differed = false
        for t in stride(from: 0.0, through: 120.0, by: 0.5) {
            let a = SkyLife.birds(seed: 11, at: t, breeze: 1, rules: rules, scenery: scenery)
            let b = SkyLife.birds(seed: 12, at: t, breeze: 1, rules: rules, scenery: scenery)
            if a != b { differed = true; break }
        }
        XCTAssertTrue(differed)
    }

    func testAFlockCrossesEveryTwentyToFortySeconds() {
        // Every start, over an hour of play, from the gap between one flock and the next.
        var starts: [Double] = []
        var wasEmpty = true
        for k in 0...(3600 * 20) {
            let t = Double(k) / 20
            let up = !SkyLife.birds(seed: 3, at: t, breeze: 2, rules: rules, scenery: scenery).isEmpty
            if up && wasEmpty { starts.append(t) }
            wasEmpty = !up
        }
        XCTAssertGreaterThan(starts.count, 100, "an hour should see a hundred-odd flocks")
        for (a, b) in zip(starts, starts.dropFirst()) {
            let gap = b - a
            XCTAssertGreaterThanOrEqual(gap, 20 - 0.1, "flocks \(a) and \(b) were \(gap) apart")
            XCTAssertLessThanOrEqual(gap, 40 + 0.1, "flocks \(a) and \(b) were \(gap) apart")
        }
    }

    func testAFlockIsOneToFiveBirdsFlyingHighAndDownwind() {
        for seed in UInt64(1)...UInt64(6) {
            for breeze in [-3.0, -1.0, 2.0, 3.0] {
                var sizes = Set<Int>()
                for k in 0...(300 * 10) {
                    let birds = SkyLife.birds(seed: seed, at: Double(k) / 10, breeze: breeze,
                                              rules: rules, scenery: scenery)
                    guard !birds.isEmpty else { continue }
                    sizes.insert(birds.count)
                    for bird in birds {
                        // §17: high, y < 60, well above the scoreboard and nowhere near the zone.
                        XCTAssertLessThan(bird.y, 60, "seed \(seed) bird at y \(bird.y)")
                        XCTAssertGreaterThan(bird.y, 0)
                    }
                }
                XCTAssertFalse(sizes.isEmpty, "seed \(seed) breeze \(breeze) never flew a flock")
                for size in sizes { XCTAssertTrue(rules.flockSize.contains(size)) }
            }
        }
    }

    func testAFlockFliesDownwindAndCrossesTheWholeView() {
        for breeze in [-3.0, 3.0] {
            var xs: [Double] = []
            for k in 0...(60 * 10) {
                let birds = SkyLife.birds(seed: 5, at: Double(k) / 10, breeze: breeze,
                                          rules: rules, scenery: scenery)
                if let lead = birds.first { xs.append(lead.x) }
            }
            XCTAssertFalse(xs.isEmpty)
            // Downwind: a positive breeze carries the flock left to right and back again.
            if breeze > 0 {
                XCTAssertLessThan(xs.first!, 0.1)
                XCTAssertGreaterThan(xs.max()!, 0.9)
            } else {
                XCTAssertGreaterThan(xs.first!, 0.9)
                XCTAssertLessThan(xs.min()!, 0.1)
            }
        }
    }

    func testBirdsStepInWholeStepsAndNeverSmoothly() {
        // The motion budget (§9): nothing but the ball is smooth. Inside one step of the clock
        // a bird does not move at all.
        let stepSeconds = 1 / rules.stepsPerSecond
        var held = 0, moved = 0
        for k in 0...(120 * 10) {
            // Both samples inside the same whole step, near each end of it.
            let stepStart = Double(k) * stepSeconds
            let a = SkyLife.birds(seed: 9, at: stepStart + stepSeconds * 0.05, breeze: 2,
                                  rules: rules, scenery: scenery)
            let b = SkyLife.birds(seed: 9, at: stepStart + stepSeconds * 0.95, breeze: 2,
                                  rules: rules, scenery: scenery)
            guard a.count == b.count, !a.isEmpty else { continue }
            // Wings beat at 4 Hz and may turn over inside a 10 Hz step; positions may not move.
            XCTAssertEqual(a.map(\.x), b.map(\.x), "a flock drifted inside one step at \(stepStart)")
            XCTAssertEqual(a.map(\.y), b.map(\.y), "a flock drifted inside one step at \(stepStart)")
            held += 1

            // ...and it does move from one step to the next, or it is not crossing at all.
            let c = SkyLife.birds(seed: 9, at: stepStart + stepSeconds * 1.05, breeze: 2,
                                  rules: rules, scenery: scenery)
            if c.count == a.count, a.map(\.x) != c.map(\.x) { moved += 1 }
        }
        XCTAssertGreaterThan(held, 100)
        XCTAssertGreaterThan(moved, 100, "the birds never moved at all")
    }

    func testAFlockHasTwoFlapFramesAndNeighboursBeatOnOpposite() {
        var sawBoth = false
        for k in 0...(300 * 10) {
            let birds = SkyLife.birds(seed: 4, at: Double(k) / 10, breeze: 2, rules: rules, scenery: scenery)
            guard birds.count >= 2 else { continue }
            XCTAssertNotEqual(birds[0].wingsUp, birds[1].wingsUp, "the flock is marching in step")
            sawBoth = true
        }
        XCTAssertTrue(sawBoth)
    }

    func testACalmParkStillGetsBirds() {
        // A dead calm is the one case where a flock has to pick its own way across.
        var flew = false
        for k in 0...(300 * 10) where !SkyLife.birds(seed: 21, at: Double(k) / 10, breeze: 0,
                                                     rules: rules, scenery: scenery).isEmpty {
            flew = true
            break
        }
        XCTAssertTrue(flew)
    }

    // MARK: - The cheer's window

    func testTheCrowdIsUpFromTheWallToTheCutAndNotBefore() {
        var m = DerbyMachine(seed: 99, park: Park.generate(number: 2))
        XCTAssertFalse(m.crowdIsUp, "nobody is up during the windup")

        // Swing at the first pitch hard enough to clear the wall.
        while m.beat != .pitch { m.tick(1 / 60) }
        XCTAssertFalse(m.crowdIsUp)
        m.slice(bomb(m))
        guard let flight = m.flight, flight.homeRun else {
            return XCTFail("the test needs a home run to watch the crowd")
        }
        XCTAssertFalse(m.crowdIsUp, "still nobody: the ball has not cleared the wall yet")

        var upDuringFlight = false, downBeforeTheWall = false
        while m.beat == .contact || m.beat == .flight {
            let pastTheWall = (m.playbackPoint?.xFeet ?? 0) >= m.park.wallDistanceFeet
            if m.beat == .flight, !pastTheWall, !m.crowdIsUp { downBeforeTheWall = true }
            if m.crowdIsUp { upDuringFlight = true }
            m.tick(1 / 60)
        }
        XCTAssertTrue(downBeforeTheWall, "the crowd was up before the ball reached the wall")
        XCTAssertTrue(upDuringFlight, "the crowd never got up")

        XCTAssertEqual(m.beat, .result)
        XCTAssertTrue(m.crowdIsUp, "the crowd stays up through the result hold")

        // ...and sits down at the cut back to the plate.
        while m.beat == .result { m.tick(1 / 60) }
        XCTAssertFalse(m.crowdIsUp)
    }

    func testTheCrowdIsNotUpForABallThatStaysInThePark() {
        var m = DerbyMachine(seed: 5, park: Park.generate(number: 1))
        while m.beat != .pitch { m.tick(1 / 60) }
        // A weak pop-up: nowhere near the wall.
        m.slice(popUp(m))
        XCTAssertEqual(m.flight?.homeRun, false, "the test needs a ball that stays in")
        while m.beat != .windup && m.beat != .pitch {
            XCTAssertFalse(m.crowdIsUp, "the crowd rose for a ball that stayed in the park")
            m.tick(1 / 60)
        }
    }

    func testTheCrowdIsUpForEveryHomeRunEvenOneThatEarnsNoFireworks() {
        // §17's table: a streak of 1 gets the cheer, the crowd bounce and the lights' chase, and
        // no shells at all. The two must not be the same flag.
        var m = DerbyMachine(seed: 99, park: Park.generate(number: 2))
        while m.beat != .pitch { m.tick(1 / 60) }
        m.slice(bomb(m))
        guard m.flight?.homeRun == true else { return XCTFail("the test needs a home run") }
        while m.beat != .result { m.tick(1 / 60) }
        XCTAssertEqual(m.tally.homeRunStreak, 1)
        XCTAssertNil(m.fireworks, "a streak of one earns no shells")
        XCTAssertTrue(m.crowdIsUp, "but the crowd is up all the same")
    }

    // MARK: - Helpers

    /// 115 mph at 28°: a home run in any park the rules can generate (`StatsTests.bomb`).
    private func bomb(_ m: DerbyMachine) -> SliceCrossing {
        SliceCrossing(quality: 1, progress: 1, swingAngleDegrees: 28, power: 1,
                      ball: m.ballNow, crossingPoint: m.ballNow.position)
    }

    /// A weak one straight up: nowhere near the wall.
    private func popUp(_ m: DerbyMachine) -> SliceCrossing {
        SliceCrossing(quality: 0, progress: 1, swingAngleDegrees: 62, power: 0.15,
                      ball: m.ballNow, crossingPoint: m.ballNow.position)
    }

    /// A park built with the night gear: the towers and the stars belong to every park now, but
    /// the wall tower and the moon still need this draw (§20).
    private func firstNightPark() -> Park {
        for n in 5...200 {
            let park = Park.generate(number: n)
            if park.nightSeed { return park }
        }
        fatalError("no park with the night gear in the first 200")
    }
}
