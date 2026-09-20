import XCTest
@testable import DerbyCore

final class SceneryTests: XCTestCase {
    private let rules = SceneryRules.standard

    func testSceneryIsDeterministic() {
        for n in [1, 2, 3, 4, 5, 9, 87, 100, 1_000, 123_456] {
            XCTAssertEqual(Park.generate(number: n).scenery, Park.generate(number: n).scenery)
        }
    }

    func testSceneryVariesBetweenParks() {
        let seen = Set((5...200).map { n -> String in
            let s = Park.generate(number: n).scenery
            return "\(s.far.rawValue)/\(s.near.rawValue)"
        })
        // Three far pieces and five near ones: the kit should be well turned over.
        XCTAssertGreaterThan(seen.count, 10)
    }

    /// §17's table, entry by entry. These four are fixed, never seeded.
    func testTheLadderHasItsOwnBackdrops() {
        let singleA = Park.generate(number: 1).scenery
        XCTAssertEqual(singleA.far, .treeline)
        XCTAssertEqual(singleA.near, .house)
        XCTAssertEqual(singleA.stands, .fenceAndTrees)
        XCTAssertFalse(singleA.stands.swallowsTheBall)   // the one park you watch it land in
        XCTAssertEqual(singleA.flags, 0)

        let doubleA = Park.generate(number: 2).scenery
        XCTAssertEqual(doubleA.far, .treeline)
        XCTAssertEqual(doubleA.near, .waterTower)
        XCTAssertEqual(doubleA.stands, .lowBleacher)
        XCTAssertEqual(doubleA.flags, 0)

        let tripleA = Park.generate(number: 3).scenery
        XCTAssertEqual(tripleA.far, .bleachers)
        XCTAssertEqual(tripleA.near, .lightPoles)
        XCTAssertEqual(tripleA.stands, .bleachers)
        XCTAssertEqual(tripleA.flags, rules.bleachersFlags)

        let theShow = Park.generate(number: 4).scenery
        XCTAssertEqual(theShow.far, .upperDeck)
        XCTAssertEqual(theShow.near, .pennants)
        XCTAssertEqual(theShow.stands, .full)
        XCTAssertEqual(theShow.flags, rules.fullStandsFlags)

        // Park 0 is park 1, the same way the wall is.
        XCTAssertEqual(Park.generate(number: 0).scenery, singleA)
    }

    func testSeededParksDrawFromTheKit() {
        for n in 5...400 {
            let s = Park.generate(number: n).scenery
            XCTAssertTrue(Backdrop.farKit.contains(s.far), "park \(n) far \(s.far)")
            XCTAssertTrue(Backdrop.nearKit.contains(s.near), "park \(n) near \(s.near)")
            XCTAssertTrue(s.far.isFar)
            XCTAssertTrue(s.near.isNear)
            XCTAssertEqual(s.stands, .full)             // the majors: full stands from park 5 on
            XCTAssertEqual(s.standsTopFeet, rules.fullStandsTopFeet)
            XCTAssertEqual(s.standsDepthFeet, rules.fullStandsDepthFeet)
        }
    }

    func testBreezeStaysInRange() {
        var nonZero = 0
        for n in 1...400 {
            let b = Park.generate(number: n).scenery.breezePixelsPerSecond
            XCTAssertTrue(rules.breeze.contains(b), "park \(n) breeze \(b)")
            XCTAssertEqual(b, b.rounded(), "breeze is whole pixels per second")
            if b != 0 { nonZero += 1 }
        }
        XCTAssertGreaterThan(nonZero, 200)              // most parks have some weather
    }

    func testCloudsAreInBandAndWellFormed() {
        for n in 1...400 {
            let s = Park.generate(number: n).scenery
            for (clouds, band) in [(s.atBatClouds, rules.atBatCloudBand),
                                   (s.sideClouds, rules.sideCloudBand)] {
                XCTAssertTrue(rules.cloudsPerView.contains(clouds.count), "park \(n): \(clouds.count) clouds")
                for c in clouds {
                    XCTAssertTrue(rules.cloudBlocks.contains(c.blocks.count))
                    XCTAssertTrue(band.contains(c.baselineY), "park \(n) baseline \(c.baselineY)")
                    XCTAssertTrue((0.0..<1.0).contains(c.xFraction))
                    XCTAssertEqual(c.blocks.first?.dx, 0)
                    XCTAssertGreaterThan(c.width, 0)
                    XCTAssertGreaterThan(c.height, 0)
                    for b in c.blocks {
                        XCTAssertTrue(rules.cloudBlockWidth.contains(b.w))
                        XCTAssertTrue((rules.cloudEndRise.lowerBound...rules.cloudMiddleRise.upperBound).contains(b.rise))
                    }
                }
            }
        }
    }

    /// The two views look in different directions, so they never share a sky.
    func testTheTwoViewsHaveTheirOwnClouds() {
        var differ = 0
        for n in 1...200 where Park.generate(number: n).scenery.atBatClouds
            != Park.generate(number: n).scenery.sideClouds { differ += 1 }
        XCTAssertEqual(differ, 200)
    }

    func testNightKitOnlyAppearsAtNight() {
        var nightParks = 0, moons = 0
        for n in 1...600 {
            let park = Park.generate(number: n)
            let s = park.scenery
            if park.isNight {
                nightParks += 1
                XCTAssertTrue(rules.towersPerNightPark.contains(s.towers), "park \(n) towers \(s.towers)")
                if let moon = s.moon {
                    moons += 1
                    XCTAssertTrue(rules.moonBand.contains(moon.y))
                    XCTAssertTrue(rules.moonRadius.contains(moon.radius))
                    XCTAssertTrue([-1, 1].contains(moon.biteDirection))
                }
            } else {
                XCTAssertEqual(s.towers, 0, "park \(n) is a day game")
                XCTAssertNil(s.moon, "park \(n) is a day game")
            }
        }
        XCTAssertGreaterThan(nightParks, 50)
        // About one night park in four (DESIGN.md §17).
        XCTAssertEqual(Double(moons) / Double(nightParks), rules.moonProbability, accuracy: 0.12)
    }
}
