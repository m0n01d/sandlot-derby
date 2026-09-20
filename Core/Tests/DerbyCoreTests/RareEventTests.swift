import XCTest
@testable import DerbyCore

/// The rare things a batted ball can do to a park (#5, DESIGN.md §17 "Rare things").
///
/// Two rules run through all of it. **Nothing here changes how the ball flies** — the flight is
/// integrated once at contact and an event is only something that arc passes through. And
/// **detection is a pure function of what a `Replay` record carries**, so the clip a player
/// shares shows the event they saw and not a different one.
final class RareEventTests: XCTestCase {
    private let scenery = SceneryRules.standard
    private let rules = RareEventRules.standard

    // MARK: - The landmarks are where they say they are

    /// Agent G's rule, applied again: #5's draws come last in `Scenery.generate`'s stream, so no
    /// park's clouds, breeze, moon, towers or stars moved when the board and the wall tower
    /// arrived. A fingerprint of all of it over parks 1…200, taken before they existed.
    func testLandmarksMovedNoParksExistingScenery() {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        func eat(_ v: Double) { h = (h ^ v.bitPattern) &* 0x0000_0100_0000_01B3 }
        for n in 1...200 {
            let s = Park.generate(number: n).scenery
            eat(s.breezePixelsPerSecond)
            eat(Double(s.flags))
            eat(s.standsTopFeet)
            eat(s.standsDepthFeet)
            for c in s.atBatClouds + s.sideClouds {
                eat(c.xFraction); eat(c.baselineY)
                for b in c.blocks { eat(Double(b.dx)); eat(Double(b.rise)); eat(Double(b.w)) }
            }
            if let m = s.moon {
                eat(m.xFraction); eat(m.y); eat(m.radius); eat(Double(m.biteDirection))
            }
            for t in s.lightTowers {
                eat(t.feetBehindWall); eat(t.heightFeet)
                eat(Double(t.bankColumns)); eat(Double(t.bankRows))
            }
            for star in s.stars {
                eat(star.xFraction); eat(star.y); eat(star.blinkPeriod ?? -1); eat(star.blinkPhase)
            }
        }
        // Measured on `origin/main` before any of #5 existed, not taken from this branch:
        // main's Core was exported on its own and asked the same question (2026-09-19).
        XCTAssertEqual(h, 7_243_457_102_344_678_753)
    }

    func testTheBoardIsInAboutOneParkInThreeAndNeverOnTheLadder() {
        for n in 1...League.theShow.rawValue {
            XCTAssertNil(Park.generate(number: n).scenery.board, "the ladder keeps §17's table")
        }
        var boards = 0
        for n in 5...600 where Park.generate(number: n).scenery.board != nil { boards += 1 }
        XCTAssertEqual(Double(boards) / 596, 1 / Double(scenery.boardInEveryPark), accuracy: 0.06)
    }

    /// A board buried in the stands is not a landmark, and one floating over them is not either.
    func testTheBoardStandsOnTheStandsAndInsideTheAirspaceAShotCanReach() {
        var seen = 0
        for n in 5...600 {
            let park = Park.generate(number: n)
            guard let board = park.scenery.board else { continue }
            seen += 1
            let s = park.scenery
            let under = s.standsHeightFeet(at: park.wallDistanceFeet + board.feetBehindWall, park: park)
            // Its foot is rounded to a whole foot, so the clearance is the seeded one ± half.
            XCTAssertGreaterThanOrEqual(board.bottomFeet - under, scenery.boardClearanceFeet.lowerBound - 1,
                                        "park \(n): the board is buried in the stands")
            XCTAssertLessThanOrEqual(board.bottomFeet - under, scenery.boardClearanceFeet.upperBound + 1,
                                     "park \(n): the board is floating")
            XCTAssertEqual(board.bottomFeet, board.bottomFeet.rounded(), "park \(n): whole feet")
            XCTAssertTrue(scenery.boardDepthFeet.contains(board.feetBehindWall), "park \(n)")
            // The pane is inside the panel it is a pane of, and in a top corner of it.
            let pane = board.pane(wallDistanceFeet: park.wallDistanceFeet)
            XCTAssertGreaterThanOrEqual(pane.near, board.nearFeet(wallDistanceFeet: park.wallDistanceFeet))
            XCTAssertLessThanOrEqual(pane.far, board.farFeet(wallDistanceFeet: park.wallDistanceFeet))
            XCTAssertLessThan(pane.top, board.topFeet)
            XCTAssertGreaterThan(pane.bottom, board.bottomFeet)
            XCTAssertTrue([-1, 1].contains(board.paneSide))
        }
        XCTAssertGreaterThan(seen, 100)
    }

    /// The reason the short standard over the wall exists at all: §17 asks for a no-doubter that
    /// reaches a lamp bank, and **not one of the seeded towers can ever be reached**. They stand
    /// 150–190 ft up and the highest a batted ball is at the wall is well under a hundred.
    func testTheSeededTowersAreOutOfReachAndTheWallTowerIsNot() {
        var reachableTall = 0, reachableShort = 0, shortTowers = 0
        for n in 5...400 {
            let park = Park.generate(number: n)
            let s = park.scenery
            guard park.isNight else { continue }
            let best = Flight.simulate(exitVelocityMPH: 112, launchAngleDegrees: 40,
                                       wallDistanceFeet: park.wallDistanceFeet,
                                       wallHeightFeet: park.wallHeightFeet)
            func reaches(_ tower: Tower) -> Bool {
                let bx = park.wallDistanceFeet + tower.feetBehindWall
                return best.points.contains {
                    let dx = $0.xFeet - bx, dy = $0.yFeet - tower.heightFeet
                    return (dx * dx + dy * dy).squareRoot() <= rules.bankReachFeet
                }
            }
            for tower in s.lightTowers where reaches(tower) { reachableTall += 1 }
            if let wallTower = s.wallTower {
                shortTowers += 1
                if reaches(wallTower) { reachableShort += 1 }
            }
        }
        XCTAssertEqual(reachableTall, 0, "a seeded tower was reachable; §17's spec would work after all")
        XCTAssertGreaterThan(shortTowers, 20)
        XCTAssertGreaterThan(reachableShort, 0, "no wall tower could ever be put out")
    }

    func testTheWallTowerIsNightOnlyAndJoinsTheChaseAtTheEnd() {
        for n in 1...300 {
            let park = Park.generate(number: n)
            let s = park.scenery
            guard park.isNight else {
                XCTAssertNil(s.wallTower, "park \(n) is a day game")
                XCTAssertTrue(s.allTowers.isEmpty)
                XCTAssertNil(s.wallTowerIndex)
                continue
            }
            guard let wallTower = s.wallTower else {
                XCTAssertNil(s.wallTowerIndex)
                XCTAssertEqual(s.allTowers, s.lightTowers)
                continue
            }
            XCTAssertTrue(scenery.wallTowerDepthFeet.contains(wallTower.feetBehindWall), "park \(n)")
            XCTAssertTrue(scenery.wallTowerHeightFeet.contains(wallTower.heightFeet), "park \(n)")
            // Appended, never inserted: every seeded tower keeps the index it had, and so its
            // place in the chase.
            XCTAssertEqual(Array(s.allTowers.prefix(s.lightTowers.count)), s.lightTowers, "park \(n)")
            XCTAssertEqual(s.wallTowerIndex, s.lightTowers.count)
            XCTAssertEqual(s.allTowers.last, wallTower)
            // It is far shorter than any of them, which is the whole point of it.
            for tall in s.lightTowers {
                XCTAssertLessThan(wallTower.heightFeet, tall.heightFeet, "park \(n)")
            }
        }
    }

    func testThingsPastParkOneHundredFiveHundredAndAThousand() {
        for n in [1, 5, 50, 99] {
            let s = Park.generate(number: n).scenery
            XCTAssertFalse(s.hasBlimp, "park \(n)")
            XCTAssertFalse(s.hasSearchlights)
            XCTAssertFalse(s.hasComet)
        }
        for n in [100, 250, 499] {
            let s = Park.generate(number: n).scenery
            XCTAssertTrue(s.hasBlimp, "park \(n)")
            XCTAssertFalse(s.hasSearchlights, "park \(n)")
            XCTAssertFalse(s.hasComet, "park \(n)")
        }
        let five = Park.generate(number: 500).scenery
        XCTAssertTrue(five.hasBlimp)
        XCTAssertTrue(five.hasSearchlights)
        XCTAssertFalse(five.hasComet)
        let thousand = Park.generate(number: 1_000).scenery
        XCTAssertTrue(thousand.hasComet)
    }

    // MARK: - The stands' profile, which the board stands on

    /// It moved into Core with #5 so a landmark knows what it is standing on. It must still be
    /// the same number that decides where a home run disappears.
    func testTheStandsProfileClimbsAndThenGoesFlat() {
        let park = Park.generate(number: 9)
        let s = park.scenery
        XCTAssertEqual(s.standsHeightFeet(at: park.wallDistanceFeet - 1, park: park), 0)
        var last = 0.0
        for back in stride(from: 0.0, to: s.standsDepthFeet, by: 5) {
            let h = s.standsHeightFeet(at: park.wallDistanceFeet + back, park: park)
            XCTAssertGreaterThanOrEqual(h, last)
            XCTAssertLessThanOrEqual(h, s.standsTopFeet)
            last = h
        }
        for back in [s.standsDepthFeet, s.standsDepthFeet + 500] {
            XCTAssertEqual(s.standsHeightFeet(at: park.wallDistanceFeet + back, park: park),
                           s.standsTopFeet)
        }
        // Single-A has no stands, so nothing is ever swallowed and nothing stands on anything.
        let sandlot = Park.generate(number: 1)
        XCTAssertEqual(sandlot.scenery.standsHeightFeet(at: 500, park: sandlot), 0)
    }

    // MARK: - Detection

    /// The whole point of the feature: an event is found, not caused. The flight is byte for
    /// byte the flight it would have been in a park with none of this in it.
    func testNothingAboutTheFlightChanges() {
        for n in [6, 8, 12, 63, 77, 84, 101] {
            let park = Park.generate(number: n)
            var bare = DerbyMachine(seed: 4, park: park)
            var full = DerbyMachine(seed: 4, park: park)
            full.rareEventRules = .standard
            bare.rareEventRules.bankReachFeet = 0          // a park where nothing can be hit
            bare.rareEventRules.birdReachPixels = -1000
            bare.rareEventRules.blimpReachPixels = -1000
            while bare.beat != .pitch { bare.tick(1 / 60); full.tick(1 / 60) }
            bare.slice(bomb(bare))
            full.slice(bomb(full))
            XCTAssertEqual(bare.flight, full.flight, "park \(n): the flight itself moved")
            XCTAssertEqual(bare.flight?.distanceFeet, full.flight?.distanceFeet)
            XCTAssertEqual(bare.flight?.homeRun, full.flight?.homeRun)
        }
    }

    /// Detection is a function of exactly the things a `Replay` record holds — the park, the
    /// pitch, the crossing and the tally before the swing — and of nothing else. If this ever
    /// fails, a shared clip shows a different event from the one the player saw (DESIGN.md §19).
    func testDetectionIsAFunctionOfWhatAReplayRecordCarries() {
        for n in [13, 21, 37, 48, 101, 137] {
            let park = Park.generate(number: n)
            var live = DerbyMachine(seed: 17, park: park)
            live.skyClockOffset = 7.5           // a sky mid-crossing, as `-skyclock` would give
            // A career already a few minutes old, the way a real one is at the moment of a swing.
            while live.tally[.secondsPlayed] < 12 { live.tick(1 / 60) }
            while live.beat != .pitch { live.tick(1 / 60) }

            let before = live                    // what `Replay.init(capturing:)` keeps
            let crossing = loft(live)
            live.slice(crossing)

            // The clip's machine: rebuilt from the record and ticked at a fixed 60 Hz, which is
            // not the rate the phone happened to run at.
            var clip = DerbyMachine.atPitch(park: before.park, tally: before.tally, pitch: before.pitch)
            clip.skyClockOffset = before.skyClockOffset
            clip.slice(crossing)

            XCTAssertEqual(live.parkEvents, clip.parkEvents, "park \(n): the clip found other events")
            XCTAssertEqual(live.clockAtContact, clip.clockAtContact, "park \(n)")
        }
    }

    /// Why a sky strike is only ever judged in the close camera with the ball pinned: that is the
    /// one framing whose picture is the same on every canvas. A phone is wider than 320 and the
    /// wide camera's scale grows with it, so the same towering fly is drawn near the top of a
    /// big phone's frame and halfway down a 320-wide clip's — judge a strike there and what the
    /// player saw and what the clip shows would be two different things.
    func testAPinnedCloseFrameIsTheSamePictureOnEveryCanvas() {
        let park = Park.generate(number: 106)
        let f = Flight.simulate(exitVelocityMPH: 112, launchAngleDegrees: 53,
                                wallDistanceFeet: park.wallDistanceFeet,
                                wallHeightFeet: park.wallHeightFeet)
        let cut = SideView.closeCutIndex(flight: f, wallDistanceFeet: park.wallDistanceFeet)
        var comparedPinned = 0, comparedWide = 0, wideDiffered = 0
        for (i, p) in f.points.enumerated() {
            let camera = SideView.camera(at: i, closeCutIndex: cut)
            var places: [(x: Double, y: Double)] = []
            for width in [320.0, 437.0, 524.0] {
                let v = SideView.framing(camera: camera, park: park, flight: f,
                                         ballFeet: p.yFeet, width: width)
                places.append((v.x(p.xFeet) / width, v.y(p.yFeet)))
            }
            let pinned = SideView.framing(camera: camera, park: park, flight: f,
                                          ballFeet: p.yFeet, width: 320).ground
                > SideViewRules.standard.groundY
            if camera == .close, pinned {
                comparedPinned += 1
                for place in places.dropFirst() {
                    // Same fraction across, same absolute row down — the birds' own units.
                    XCTAssertEqual(place.x, places[0].x, accuracy: 0.001)
                    XCTAssertEqual(place.y, places[0].y, accuracy: 0.001)
                }
            } else if camera == .wide, p.yFeet > 100 {
                comparedWide += 1
                if abs(places[2].y - places[0].y) > 2 { wideDiffered += 1 }
            }
        }
        XCTAssertGreaterThan(comparedPinned, 0, "this flight never pinned; the test proves nothing")
        XCTAssertGreaterThan(wideDiffered, 0,
                             "the wide camera drew the same picture on every canvas after all")
        XCTAssertGreaterThan(comparedWide, 0)
    }

    /// The other half of the same guarantee, against what #33 landed while this was being built:
    /// a clip made **during a Warm Up** restores the Warm Up too, and it must still find the same
    /// rare things. The day's park is an ordinary seeded park with its own landmarks (§18), so
    /// there is something to find.
    func testAClipMadeDuringAWarmUpFindsTheSameThings() {
        var live = DerbyMachine(seed: 21, tally: tallyWithAParkCleared())
        live.skyClockOffset = 11
        live.beginWarmUp(WarmUp.generate(day: 20_260_920))
        while live.warmUp == nil { live.tick(1 / 60) }
        while live.beat != .pitch { live.tick(1 / 60) }

        let before = live
        let crossing = bomb(live)
        live.slice(crossing)

        let record = Replay(capturing: before, crossing: crossing,
                            slash: Point(x: 0, y: 0), trail: [])
        var clip = Replay.machine(from: record)
        clip.skyClockOffset = before.skyClockOffset
        // `Replay.machine` already ran the swing; re-run detection against the restored clock.
        XCTAssertEqual(clip.park.number, live.park.number)
        // Only by the debug sky offset, and by the last bit of a double: the clip's tally is the
        // one the record copied, while the live one got there by adding up sixtieths.
        XCTAssertEqual(clip.clockAtContact, live.clockAtContact - before.skyClockOffset,
                       accuracy: 1e-9)
        let same = RareEvents.detect(
            park: clip.park, scenery: clip.park.scenery, flight: clip.flight!,
            birdSeed: SkyView.side.birdSeed(parkNumber: clip.park.number),
            blimpSeed: SkyView.side.blimpSeed(parkNumber: clip.park.number),
            clockAtContact: live.clockAtContact, contactHold: live.contactHoldNow,
            flightSpeed: live.timings.flightSpeed)
        XCTAssertEqual(same, live.parkEvents, "a Warm Up clip found other events")
    }

    func testDetectionIsRepeatable() {
        let park = Park.generate(number: 21)
        let s = park.scenery
        let f = Flight.simulate(exitVelocityMPH: 112, launchAngleDegrees: 53,
                                wallDistanceFeet: park.wallDistanceFeet,
                                wallHeightFeet: park.wallHeightFeet)
        for clock in stride(from: 0.0, through: 40.0, by: 0.25) {
            let a = RareEvents.detect(park: park, scenery: s, flight: f,
                                      birdSeed: SkyView.side.birdSeed(parkNumber: 21),
                                      blimpSeed: SkyView.side.blimpSeed(parkNumber: 21),
                                      clockAtContact: clock, contactHold: 0.4, flightSpeed: 2)
            let b = RareEvents.detect(park: park, scenery: s, flight: f,
                                      birdSeed: SkyView.side.birdSeed(parkNumber: 21),
                                      blimpSeed: SkyView.side.blimpSeed(parkNumber: 21),
                                      clockAtContact: clock, contactHold: 0.4, flightSpeed: 2)
            XCTAssertEqual(a, b)
        }
    }

    func testAnEventNeverHappensTwiceOnOneFlightAndIsAlwaysInPlaybackOrder() {
        for n in [6, 8, 12, 13, 21, 63, 101] {
            let park = Park.generate(number: n)
            for la in [28.0, 53.0] {
                let f = Flight.simulate(exitVelocityMPH: 112, launchAngleDegrees: la,
                                        wallDistanceFeet: park.wallDistanceFeet,
                                        wallHeightFeet: park.wallHeightFeet)
                for clock in stride(from: 0.0, through: 30.0, by: 2.5) {
                    let events = RareEvents.detect(
                        park: park, scenery: park.scenery, flight: f,
                        birdSeed: SkyView.side.birdSeed(parkNumber: n),
                        blimpSeed: SkyView.side.blimpSeed(parkNumber: n),
                        clockAtContact: clock, contactHold: 0.4, flightSpeed: 2)
                    XCTAssertEqual(Set(events.map(\.kind)).count, events.count,
                                   "park \(n): the same thing happened twice")
                    XCTAssertEqual(events.map(\.index), events.map(\.index).sorted())
                    for e in events {
                        XCTAssertTrue((0..<f.points.count).contains(e.index))
                    }
                }
            }
        }
    }

    /// A park with nothing in it has nothing to hit, however hard the ball is struck.
    func testAParkWithNoLandmarksHasNoEvents() {
        let park = Park.generate(number: 1)               // Single-A: no board, no towers, day
        XCTAssertNil(park.scenery.board)
        XCTAssertNil(park.scenery.wallTower)
        var m = DerbyMachine(seed: 2, park: park)
        while m.beat != .pitch { m.tick(1 / 60) }
        m.slice(bomb(m))
        XCTAssertTrue(m.parkEvents.allSatisfy { $0.kind == .birdStrike || $0.kind == .blimpHit })
    }

    /// §17: it takes a no-doubter to put a bank out. A wall-scraper that grazes one does not.
    func testOnlyANoDoubterPutsABankOut() {
        var checked = 0
        for n in 5...400 {
            let park = Park.generate(number: n)
            guard let tower = park.scenery.wallTower else { continue }
            let bx = park.wallDistanceFeet + tower.feetBehindWall
            for la in [28.0, 40.0, 53.0] {
                let f = Flight.simulate(exitVelocityMPH: 112, launchAngleDegrees: la,
                                        wallDistanceFeet: park.wallDistanceFeet,
                                        wallHeightFeet: park.wallHeightFeet)
                let grazed = f.points.contains {
                    let dx = $0.xFeet - bx, dy = $0.yFeet - tower.heightFeet
                    return (dx * dx + dy * dy).squareRoot() <= rules.bankReachFeet
                }
                let events = RareEvents.detect(
                    park: park, scenery: park.scenery, flight: f,
                    birdSeed: 1, blimpSeed: 2, clockAtContact: 0, contactHold: 0.4, flightSpeed: 2)
                let out = events.contains { $0.kind == .lightsOut }
                let noDoubter = f.distanceFeet - park.wallDistanceFeet >= StatRules.standard.noDoubterMarginFeet
                XCTAssertEqual(out, grazed && noDoubter, "park \(n) at \(la)°")
                if grazed { checked += 1 }
            }
        }
        XCTAssertGreaterThan(checked, 0, "no flight ever came near a bank")
    }

    // MARK: - Counting

    func testEachEventIsCountedOnceAndOnlyWhenPlaybackReachesIt() {
        // Park 6 has a board the robot's own swing puts a ball into.
        var m = DerbyMachine(seed: 11, park: Park.generate(number: 6))
        while m.beat != .pitch { m.tick(1 / 60) }
        m.slice(bomb(m))
        guard let event = m.parkEvents.first else { return XCTFail("park 6 should have a board hit") }
        XCTAssertEqual(m.tally.count(event.kind.stat), 0, "counted at contact instead of at the event")
        XCTAssertNil(m.secondsSince(event), "the burst started before the ball got there")

        var countedAt: Double? = nil
        while m.beat == .contact || m.beat == .flight {
            m.tick(1 / 60)
            if m.tally.count(event.kind.stat) == 1, countedAt == nil { countedAt = m.playbackIndex }
        }
        XCTAssertEqual(countedAt.map { $0 >= Double(event.index) }, true)
        XCTAssertEqual(m.tally.count(event.kind.stat), 1, "counted more than once")
        XCTAssertNotNil(m.secondsSince(event))

        // …and not again while the landing number is up.
        while m.beat == .result { m.tick(1 / 60) }
        XCTAssertEqual(m.tally.count(event.kind.stat), 1)
    }

    func testTheBurstIsOverBeforeTheNextPitch() {
        var m = DerbyMachine(seed: 11, park: Park.generate(number: 6))
        while m.beat != .pitch { m.tick(1 / 60) }
        m.slice(bomb(m))
        XCTAssertFalse(m.parkEvents.isEmpty)
        while m.beat != .windup { m.tick(1 / 60) }
        XCTAssertTrue(m.parkEvents.isEmpty, "the next pitch got someone else's feathers")
    }

    func testABankStaysOutUntilTheParkChanges() {
        // Park 63: a wall tower the robot's swing puts out.
        var m = DerbyMachine(seed: 5, park: Park.generate(number: 63))
        guard let bank = m.park.scenery.wallTowerIndex else { return XCTFail("park 63 has no wall tower") }
        XCTAssertFalse(m.bankIsOut(bank))
        while m.beat != .pitch { m.tick(1 / 60) }
        m.slice(bomb(m))
        guard m.parkEvents.contains(where: { $0.kind == .lightsOut }) else {
            return XCTFail("park 63 should give the robot a lights-out shot")
        }
        while m.beat != .result { m.tick(1 / 60) }
        XCTAssertTrue(m.bankIsOut(bank))
        XCTAssertEqual(m.tally.count(.lightsOut), 1)

        // Still out on the next pitch in the same park — and the park has not changed, because
        // this machine has no ceiling and a home run moves it on. Check the scar itself.
        XCTAssertTrue(m.parkScars.darkBanks.contains(bank))
        let parkBefore = m.park.number
        while m.park.number == parkBefore { m.tick(1 / 60) }
        XCTAssertTrue(m.parkScars.isEmpty, "the new park arrived with someone else's dark bank")
    }

    func testAStruckBirdIsNamedSoTheSkyCanLeaveItOut() {
        var m = DerbyMachine(seed: 3, park: Park.generate(number: 21))
        m.skyClockOffset = 0
        while m.beat != .pitch { m.tick(1 / 60) }
        m.slice(loft(m))
        guard let strike = m.parkEvents.first(where: { $0.kind == .birdStrike }) else {
            // Not every seed puts a bird on the path; the survey covers reach, this covers shape.
            return
        }
        XCTAssertNil(m.struckBird, "the bird was gone before the ball got there")
        while m.secondsSince(strike) == nil { m.tick(1 / 60) }
        XCTAssertEqual(m.struckBird?.slot, strike.flockSlot)
        XCTAssertEqual(m.struckBird?.index, strike.target)
        // The named bird is one that really is in the sky at the moment it is struck.
        let flock = SkyLife.birds(seed: SkyView.side.birdSeed(parkNumber: 21),
                                  at: m.clockAtContact, breeze: m.park.scenery.breezePixelsPerSecond)
        XCTAssertTrue(flock.isEmpty || flock.allSatisfy { $0.slot >= 0 })
    }

    func testTheWarmUpsParkKeepsItsLandmarksAndLosesTheMilestones() {
        // A Warm Up's park number is the day (20260920), which clears every milestone threshold
        // there is by accident. Its seeded landmarks are its own; the milestones are a career's.
        let card = WarmUp.generate(day: 20_260_920)
        XCTAssertTrue(card.park.scenery.hasBlimp, "the day's number clears the thresholds")
        var m = DerbyMachine(seed: 8, tally: tallyWithAParkCleared())
        XCTAssertTrue(m.showsMilestones)
        m.beginWarmUp(card)
        while m.warmUp == nil { m.tick(1 / 60) }
        XCTAssertFalse(m.showsMilestones, "the day's ten showed a career's sky")
        XCTAssertEqual(m.park.number, card.park.number)

        // …and a rare thing hit during a Warm Up counts like any other (DESIGN.md §18).
        while m.beat != .pitch { m.tick(1 / 60) }
        m.slice(bomb(m))
        let events = m.parkEvents
        while m.beat == .contact || m.beat == .flight { m.tick(1 / 60) }
        for e in events {
            XCTAssertEqual(m.tally.count(e.kind.stat), 1, "\(e.kind) was not counted in a Warm Up")
        }
    }

    /// **A dent almost never outlives the swing that made it**, and that is not a bug: anything
    /// that reaches the board has cleared the wall, so the park changes at the end of the result
    /// hold and takes its scars with it. The two places it does last are a park that cannot be
    /// cleared — the ceiling, before the contract is signed (§16) — and a Warm Up, where ten
    /// pitches are thrown in one park (§18). This is the ceiling; the next test is the Warm Up.
    func testADentLastsInAParkThatCannotBeCleared() {
        var m = DerbyMachine(seed: 11, park: Park.generate(number: 6), tally: tallyWithAParkCleared())
        m.parkCeiling = 6
        XCTAssertTrue(m.isAtCeiling)
        while m.beat != .pitch { m.tick(1 / 60) }
        m.slice(bomb(m))
        while m.beat != .windup { m.tick(1 / 60) }
        XCTAssertEqual(m.park.number, 6, "the ceiling should have held the park")
        let scars = m.parkScars
        XCTAssertFalse(scars.isEmpty, "park 6 should have taken a dent")

        // A Warm Up borrows the field; the career's park must get its dents back afterwards.
        m.beginWarmUp(WarmUp.generate(day: 20_260_920))
        while m.warmUp == nil { m.tick(1 / 60) }
        XCTAssertTrue(m.parkScars.isEmpty, "the day's park arrived pre-dented")
        while m.warmUp != nil { m.tick(1 / 60) }
        XCTAssertEqual(m.parkScars, scars, "a Warm Up tidied up the career's park")
    }

    /// Inside a Warm Up the park never changes, so this is where the scars really read: a bank
    /// put out on pitch three is still dark on pitch nine (DESIGN.md §18).
    func testAScarLastsTheRestOfAWarmUp() {
        var m = DerbyMachine(seed: 8, tally: tallyWithAParkCleared())
        m.beginWarmUp(WarmUp.generate(day: 20_260_920))
        while m.warmUp == nil { m.tick(1 / 60) }

        var scarred: ParkScars? = nil
        var pitches = 0
        while m.warmUp != nil, pitches < 10 {
            if m.beat == .pitch, m.elapsed > 0.01 {
                pitches += 1
                m.slice(bomb(m))
                while m.beat == .contact || m.beat == .flight { m.tick(1 / 60) }
                if scarred == nil, !m.parkScars.isEmpty { scarred = m.parkScars }
            }
            m.tick(1 / 60)
            // Whatever it picked up, it keeps: the day's park is the same park all ten times.
            if let scarred {
                XCTAssertTrue(scarred.darkBanks.isSubset(of: m.parkScars.darkBanks))
                XCTAssertEqual(scarred.paneIsBroken && !m.parkScars.paneIsBroken, false)
            }
        }
    }

    // MARK: - The counters and the save

    func testTheNewCountersSurviveASaveFromAnotherBuild() throws {
        var m = DerbyMachine(seed: 11, park: Park.generate(number: 6))
        while m.beat != .pitch { m.tick(1 / 60) }
        m.slice(bomb(m))
        while m.beat != .result { m.tick(1 / 60) }
        let data = try JSONEncoder().encode(m.tally)
        XCTAssertEqual(try JSONDecoder().decode(Tally.self, from: data), m.tally)

        // A save written before any of this existed reads every one of them as 0.
        let old = #"{"values":{"pitches":40,"homeRuns":9}}"#.data(using: .utf8)!
        let t = try JSONDecoder().decode(Tally.self, from: old)
        for kind in ParkEventKind.allCases {
            XCTAssertEqual(t.count(kind.stat), 0, "\(kind) should read as 0 in an older save")
        }
        XCTAssertEqual(t.pitches, 40)
    }

    func testEveryKindHasItsOwnCounter() {
        XCTAssertEqual(Set(ParkEventKind.allCases.map { $0.stat.key }).count,
                       ParkEventKind.allCases.count)
    }

    // MARK: - The burst

    func testABurstStartsFullStopsDeadAndBlinksOutInBetween() {
        let r = rules
        for kind in ParkEventKind.allCases {
            XCTAssertFalse(RareEvents.burst(kind, seed: 4, since: 0, rules: r).isEmpty)
            XCTAssertTrue(RareEvents.burst(kind, seed: 4, since: r.burstSeconds, rules: r).isEmpty,
                          "\(kind) was still going after its time")
            XCTAssertTrue(RareEvents.burst(kind, seed: 4, since: -1, rules: r).isEmpty)

            // It is `f(seed, t)` and nothing else.
            for t in stride(from: 0.0, to: r.burstSeconds, by: 0.02) {
                XCTAssertEqual(RareEvents.burst(kind, seed: 9, since: t, rules: r),
                               RareEvents.burst(kind, seed: 9, since: t, rules: r))
            }
            // Whole pixels, and two sizes at most (§17: no alpha — it blinks, shrinks or stops).
            for t in stride(from: 0.0, to: r.burstSeconds, by: 0.02) {
                for speck in RareEvents.burst(kind, seed: 9, since: t, rules: r) {
                    XCTAssertEqual(speck.dx, speck.dx.rounded())
                    XCTAssertEqual(speck.dy, speck.dy.rounded())
                    XCTAssertTrue([1, 2].contains(speck.size))
                }
            }
            // And it goes out blinking rather than fading.
            var blinkedOff = false
            for t in stride(from: r.burstSeconds * r.burstBlinkFrom, to: r.burstSeconds, by: 0.01)
            where RareEvents.burst(kind, seed: 9, since: t, rules: r).contains(where: { !$0.visible }) {
                blinkedOff = true
            }
            XCTAssertTrue(blinkedOff, "\(kind) faded instead of blinking")
        }
    }

    func testTheSparksAreScoreAndTheFeathersAreChalk() {
        XCTAssertEqual(RareEvents.burst(.lightsOut, seed: 1, since: 0).first?.colour, .score)
        XCTAssertEqual(RareEvents.burst(.birdStrike, seed: 1, since: 0).first?.colour, .chalk)
        XCTAssertEqual(RareEvents.burst(.windowBroken, seed: 1, since: 0).first?.colour, .chalk)
    }

    // MARK: - The framing the sky is judged in

    /// `SideView` came out of `WideScene` so a hit test could ask where the ball is drawn. It has
    /// to answer exactly what the scene used to work out for itself.
    func testTheWideFramingPutsTheWallTwoThirdsAcrossAndTheGroundWhereItWas() {
        let park = Park.generate(number: 9)
        let v = SideView.framing(camera: .wide, park: park, flight: nil, ballFeet: 0, width: 320)
        XCTAssertEqual(v.ground, SideViewRules.standard.groundY)
        XCTAssertEqual(v.x(park.wallDistanceFeet), 320 * 2 / 3, accuracy: 0.001)
        XCTAssertEqual(v.x(SideViewRules.standard.wideLeftFeet), 0, accuracy: 0.001)
    }

    func testTheCloseFramingLiftsTheGroundRatherThanLoseTheBall() {
        let park = Park.generate(number: 9)
        let low = SideView.framing(camera: .close, park: park, flight: nil, ballFeet: 0, width: 320)
        let high = SideView.framing(camera: .close, park: park, flight: nil, ballFeet: 200, width: 320)
        XCTAssertEqual(low.ground, SideViewRules.standard.groundY)
        XCTAssertGreaterThan(high.ground, low.ground)
        XCTAssertEqual(high.y(200), SideViewRules.standard.closeHeadroom, accuracy: 0.001)
        // Twice the park's scale, and the wall 55 % across.
        XCTAssertEqual(low.scale, 2 * SideView.framing(camera: .wide, park: park, flight: nil,
                                                       ballFeet: 0, width: 320).scale,
                       accuracy: 0.001)
        XCTAssertEqual(low.x(park.wallDistanceFeet), 320 * 0.55, accuracy: 0.001)
    }

    func testTheCutToTheCloseCameraIsTheOneTheMachineMakes() {
        for n in [1, 6, 21, 63, 101] {
            let park = Park.generate(number: n)
            var m = DerbyMachine(seed: 6, park: park)
            while m.beat != .pitch { m.tick(1 / 60) }
            m.slice(bomb(m))
            guard let f = m.flight else { return XCTFail() }
            let cut = SideView.closeCutIndex(flight: f, wallDistanceFeet: park.wallDistanceFeet)
            while m.beat == .contact { m.tick(1 / 60) }
            while m.beat == .flight {
                XCTAssertEqual(m.flightCamera,
                               SideView.camera(at: Int(m.playbackIndex), closeCutIndex: cut),
                               "park \(n) at \(m.playbackIndex)")
                m.tick(1 / 60)
            }
        }
    }

    // MARK: - Helpers

    /// 115 mph at 28°: the screenshot robot's own swing, near enough (`StatsTests.bomb`).
    private func bomb(_ m: DerbyMachine) -> SliceCrossing {
        SliceCrossing(quality: 1, progress: 1, swingAngleDegrees: 28, power: 1,
                      ball: m.ballNow, crossingPoint: m.ballNow.position)
    }

    /// The `-autoloft` stroke: a towering fly, which is the only thing that reaches the birds.
    private func loft(_ m: DerbyMachine) -> SliceCrossing {
        SliceCrossing(quality: 1, progress: 1, swingAngleDegrees: 53, power: 1,
                      ball: m.ballNow, crossingPoint: m.ballNow.position)
    }

    /// The Warm Up's gate asks for one cleared park before it will take the field (§18).
    private func tallyWithAParkCleared() -> Tally {
        var t = Tally()
        t.add(.parksCleared)
        return t
    }
}

/// Finding parks to point a screenshot at. The app seeds its machine at random on every launch,
/// so the `-autoslice -autobarrel` robot's exact launch varies from run to run: what a screenshot
/// needs is a park where **the whole of the robot's envelope** does the thing, not one where a
/// single idealised launch does. Run with `SURVEY=1 swift test --filter RareEventSurvey`.
final class RareEventSurvey: XCTestCase {

    /// The robot's launches: a 27° stroke (or 53° under `-autoloft`) at full power, over the
    /// timing jitter `Contact.test` allows and every pitch type's exit-velocity bonus.
    private func robotLaunches(lofted: Bool) -> [(ev: Double, la: Double, hold: Double)] {
        // The robot swings at `pitchProgress >= 0.97`, so its timing term is about 0.89 and its
        // centring a little under 1: measured on a real run, it produces 104–111 mph, not the
        // 109–115 a perfect swing would. Sweeping the wrong band picks parks it cannot reach.
        let rules = SliceRules.standard
        let timings = Timings.standard
        var out: [(Double, Double, Double)] = []
        for quality in stride(from: 0.68, through: 1.00, by: 0.02) {
            for type in PitchType.all {
                let blend = rules.qualityWeight * quality + (1 - rules.qualityWeight) * 1.0
                let ev = rules.exitVelocityBase + rules.exitVelocitySpan * blend
                    + type.exitVelocityBonusMPH
                // The hitstop is a pure function of the same quality, and the sky the events are
                // judged against is worked out through it — half a tenth of a second here moves
                // a flock a whole step, which is three to five pixels.
                let hold = timings.contactHoldWeak
                    + (timings.contactHoldBarrel - timings.contactHoldWeak) * quality
                out.append((ev, lofted ? 53 : 27, hold))
            }
        }
        return out
    }

    func testFindParksForScreenshots() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SURVEY"] != nil, "set SURVEY=1")
        var best: [ParkEventKind: [(park: Int, share: Double, clock: Double)]] = [:]

        for n in 5...900 {
            let park = Park.generate(number: n)
            let scenery = park.scenery
            guard scenery.board != nil || scenery.wallTower != nil else { continue }
            var hits: [ParkEventKind: Int] = [:]
            let launches = robotLaunches(lofted: false)
            for l in launches {
                let f = Flight.simulate(exitVelocityMPH: l.ev, launchAngleDegrees: l.la,
                                        wallDistanceFeet: park.wallDistanceFeet,
                                        wallHeightFeet: park.wallHeightFeet)
                for e in RareEvents.detect(park: park, scenery: scenery, flight: f,
                                           birdSeed: 1, blimpSeed: 2, clockAtContact: 0,
                                           contactHold: l.hold, flightSpeed: 2) {
                    hits[e.kind, default: 0] += 1
                }
            }
            for (kind, count) in hits {
                best[kind, default: []].append((n, Double(count) / Double(launches.count), 0))
            }
        }
        for kind in ParkEventKind.allCases {
            let list = (best[kind] ?? []).sorted { $0.share > $1.share }.prefix(10)
                .map { "park \($0.park) (\(Int($0.share * 100))%)" }
            print("ROBUST \(kind.rawValue): \(list.joined(separator: ", "))")
        }
    }

    /// The sky's two need a clock as well as a park, and only the lofted stroke reaches them.
    func testFindSkyParksForScreenshots() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SURVEY"] != nil, "set SURVEY=1")
        var birds: [(Int, Double, Double)] = [], blimps: [(Int, Double, Double)] = []
        // One launch per pitch type at the quality the robot actually swings with: the point is
        // to find a park and a clock where *whichever* pitch turns up does the thing.
        let launches = robotLaunches(lofted: true)
        for n in stride(from: 100, through: 220, by: 1) {
            let park = Park.generate(number: n)
            let scenery = park.scenery
            let flights = launches.map {
                (Flight.simulate(exitVelocityMPH: $0.ev, launchAngleDegrees: $0.la,
                                 wallDistanceFeet: park.wallDistanceFeet,
                                 wallHeightFeet: park.wallHeightFeet), $0.hold)
            }
            for clock in stride(from: 0.0, through: 60.0, by: 0.5) {
                var birdHits = 0, blimpHits = 0
                for (f, hold) in flights {
                    for e in RareEvents.detect(
                        park: park, scenery: scenery, flight: f,
                        birdSeed: SkyView.side.birdSeed(parkNumber: n),
                        blimpSeed: SkyView.side.blimpSeed(parkNumber: n),
                        clockAtContact: clock, contactHold: hold, flightSpeed: 2) {
                        if e.kind == .birdStrike { birdHits += 1 }
                        if e.kind == .blimpHit { blimpHits += 1 }
                    }
                }
                let n0 = Double(flights.count)
                if Double(birdHits) / n0 >= 0.9, birds.count < 10 { birds.append((n, clock, Double(birdHits) / n0)) }
                if Double(blimpHits) / n0 >= 0.9, blimps.count < 10 { blimps.append((n, clock, Double(blimpHits) / n0)) }
            }
        }
        print("ROBUST birdStrike: " + birds.map { "park \($0.0) -skyclock \($0.1)" }.joined(separator: ", "))
        print("ROBUST blimpHit: " + blimps.map { "park \($0.0) -skyclock \($0.1)" }.joined(separator: ", "))

        // The widest unbroken window per park, which is what a screenshot needs: the robot's
        // first swing lands about 1.2 s after launch, and that has to be inside it.
        for n in [106, 109, 110, 111, 114] {
            let park = Park.generate(number: n)
            let flights = launches.map {
                (Flight.simulate(exitVelocityMPH: $0.ev, launchAngleDegrees: $0.la,
                                 wallDistanceFeet: park.wallDistanceFeet,
                                 wallHeightFeet: park.wallHeightFeet), $0.hold)
            }
            var run: [Double] = [], best: [Double] = []
            for clock in stride(from: 0.0, through: 60.0, by: 0.1) {
                let all = flights.allSatisfy { f, hold in
                    RareEvents.detect(park: park, scenery: park.scenery, flight: f,
                                      birdSeed: SkyView.side.birdSeed(parkNumber: n),
                                      blimpSeed: SkyView.side.blimpSeed(parkNumber: n),
                                      clockAtContact: clock, contactHold: hold, flightSpeed: 2)
                        .contains { $0.kind == .birdStrike }
                }
                if all { run.append(clock) } else { if run.count > best.count { best = run }; run = [] }
            }
            if run.count > best.count { best = run }
            print("WINDOW park \(n) birdStrike: \(best.first ?? -1) … \(best.last ?? -1) (\(best.count) steps)")
        }
    }
}
