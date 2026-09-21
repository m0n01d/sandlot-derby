import XCTest
@testable import DerbyCore

final class ParkTests: XCTestCase {
    func testParkOneIsAlwaysTheFriendlyPark() {
        XCTAssertEqual(Park.generate(number: 1), .first)
        XCTAssertEqual(Park.generate(number: 0), .first)
        XCTAssertEqual(Park.first.wallDistanceFeet, 280)     // Single-A; the ladder is LadderTests'
        XCTAssertEqual(Park.first.wallHeightFeet, 6)
    }

    func testParksAreDeterministic() {
        for n in [2, 7, 100, 1_000, 123_456] {
            XCTAssertEqual(Park.generate(number: n), Park.generate(number: n))
        }
        XCTAssertNotEqual(Park.generate(number: 2), Park.generate(number: 3))
    }

    func testParksStayInRange() {
        let rules = Park.Rules.standard
        for n in 5...500 {                                   // 1–4 are the ladder and The Show
            let p = Park.generate(number: n)
            XCTAssertEqual(p.number, n)
            XCTAssertTrue(rules.wallDistance.contains(p.wallDistanceFeet), "park \(n) wall \(p.wallDistanceFeet)")
            XCTAssertTrue(rules.wallHeight.contains(p.wallHeightFeet), "park \(n) height \(p.wallHeightFeet)")
        }
    }

    /// A fingerprint of every park 1…200 exactly as they were generated before `Park.scenery`
    /// existed (captured 2026-09-19). Scenery draws from its own RNG stream precisely so that
    /// adding it cannot quietly move a wall; this is the test that says so.
    ///
    /// The seeded night draw is deliberately **not** in the fingerprint (re-pinned 2026-09-21,
    /// on unchanged code, before the clock arrived — DESIGN.md §20 "What the clock replaces").
    /// §20 renames that field to `nightSeed` and takes the sky away from it, and a hash that
    /// carried it could not tell a rename from a wall that moved. What is left is the wall, the
    /// height and the number, which is exactly what must not move.
    func testParkFieldsAreUnchangedByScenery() {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        for n in 1...200 {
            let p = Park.generate(number: n)
            for v in [Double(p.number), p.wallDistanceFeet, p.wallHeightFeet] {
                h = (h ^ v.bitPattern) &* 0x0000_0100_0000_01B3
            }
        }
        XCTAssertEqual(h, 13_974_837_599_773_724_677)
    }

    /// The seeded draw survives its rename: one park in four is built as a night-game park, which
    /// is what carries a wall tower and a moon. It no longer chooses the sky (§20).
    func testSomeParksAreBuiltAsNightGameParks() {
        let nights = (2...400).filter { Park.generate(number: $0).nightSeed }.count
        XCTAssertGreaterThan(nights, 40)
        XCTAssertLessThan(nights, 160)
    }

    func testPitchingIsDeterministicPerSeed() {
        var g1 = SplitMix64(seed: 42), g2 = SplitMix64(seed: 42)
        for _ in 0..<20 {
            XCTAssertEqual(Pitching.generate(using: &g1), Pitching.generate(using: &g2))
        }
    }

    func testPitchMixAndZone() {
        var g = SplitMix64(seed: 7)
        var counts: [String: Int] = [:]
        var strikes = 0
        let zone = PitchingRules.standard.strikeZone
        for _ in 0..<2000 {
            let p = Pitching.generate(using: &g)
            counts[p.type.name, default: 0] += 1
            if p.isStrike {
                strikes += 1
                XCTAssertTrue(p.target.x >= zone.x && p.target.x <= zone.x + zone.width)
                XCTAssertTrue(p.target.y >= zone.y && p.target.y <= zone.y + zone.height)
            } else {
                let inside = p.target.x >= zone.x && p.target.x <= zone.x + zone.width
                    && p.target.y >= zone.y && p.target.y <= zone.y + zone.height
                XCTAssertFalse(inside)
            }
            XCTAssertTrue(p.type.speedRange.contains(p.speedMPH))
        }
        XCTAssertEqual(Double(strikes) / 2000, 0.65, accuracy: 0.05)
        XCTAssertEqual(Double(counts["FASTBALL"] ?? 0) / 2000, 0.45, accuracy: 0.05)
        XCTAssertEqual(Double(counts["CURVE"] ?? 0) / 2000, 0.30, accuracy: 0.05)
    }

    func testBallPathEndsAtTargetAndGrows() {
        let p = Pitch(type: .curve, speedMPH: 80, isStrike: true, target: Point(x: 170, y: 160))
        let end = Pitching.ball(p, at: 1.0)
        XCTAssertEqual(end.x, 170, accuracy: 1e-9)   // sin(π) = 0
        XCTAssertEqual(end.y, 160, accuracy: 1e-9)   // p³ − p² = 0 at p = 1
        XCTAssertEqual(end.radius, 4)
        XCTAssertEqual(Pitching.ball(p, at: 0.0).radius, 1)
        XCTAssertEqual(Pitching.ball(p, at: 0.0).position, PitchingRules.standard.releasePoint)
        // A curve drops late: it is higher than the straight-line path midway.
        let straight = Pitch(type: .fastball, speedMPH: 80, isStrike: true, target: p.target)
        XCTAssertLessThan(Pitching.ball(p, at: 0.6).y, Pitching.ball(straight, at: 0.6).y)
    }
}
