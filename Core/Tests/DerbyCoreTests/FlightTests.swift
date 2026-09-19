import XCTest
@testable import DerbyCore

/// The calibration table in docs/physics.md. If these fail, the physics changed; update both.
final class FlightTests: XCTestCase {
    private func fly(_ v: Double, _ deg: Double, params: FlightParams = .calibrated,
                     wall: Double = 380, wallHeight: Double = 10) -> FlightResult {
        Flight.simulate(exitVelocityMPH: v, launchAngleDegrees: deg,
                        wallDistanceFeet: wall, wallHeightFeet: wallHeight, params: params)
    }

    private func assertDistance(_ r: FlightResult, _ expected: Double, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(r.distanceFeet, expected, accuracy: expected * 0.015, file: file, line: line)
    }

    func testStatcastRuleOfThumb_100at28_isA400FootBall() {
        let r = fly(100, 28)
        assertDistance(r, 398)
        XCTAssertTrue(r.homeRun)
        XCTAssertFalse(r.wallHit)
    }

    func testDragIsTheWholeFeel() {
        assertDistance(fly(100, 28, params: .noAir), 560)
        assertDistance(fly(100, 28, params: .dragOnly), 348)
        assertDistance(fly(100, 28), 398)
    }

    func testCalibrationTable() {
        assertDistance(fly(90, 28), 344)
        assertDistance(fly(105, 28), 424)
        assertDistance(fly(110, 28), 450)
        assertDistance(fly(110, 40), 440)
        assertDistance(fly(113, 28), 465)
    }

    func test90at20_isOffTheWall() {
        let r = fly(90, 20)
        XCTAssertTrue(r.wallHit)
        XCTAssertFalse(r.homeRun)
        assertDistance(r, 310)
    }

    func test113at28_clearsTheWallHigh() {
        let r = fly(113, 28)
        XCTAssertTrue(r.homeRun)
        XCTAssertFalse(r.wallHit)
        // Height when crossing 380 ft is about 68 ft; find the first sample past the wall.
        let atWall = r.points.first { $0.xFeet >= 380 }
        XCTAssertNotNil(atWall)
        XCTAssertEqual(atWall?.yFeet ?? 0, 68, accuracy: 6)
    }

    func testBallThatLandsShortAndRollsIntoWall_isWallHitNotHomeRun() {
        // 100 mph at 28° with no lift lands at ~348 ft and rolls to the wall.
        let r = fly(100, 28, params: .dragOnly)
        XCTAssertFalse(r.homeRun)
        XCTAssertTrue(r.wallHit)
        assertDistance(r, 348)
    }

    func testHangTimeIsPlausible() {
        let r = fly(100, 28)
        XCTAssertNotNil(r.hangTime)
        XCTAssertGreaterThan(r.hangTime ?? 0, 4.0)
        XCTAssertLessThan(r.hangTime ?? 0, 6.0)
    }

    func testDeterministic() {
        XCTAssertEqual(fly(104, 31), fly(104, 31))
    }

    func testPointsAreOrderedInTimeAndStartAtContactHeight() {
        let r = fly(100, 28)
        XCTAssertFalse(r.points.isEmpty)
        XCTAssertEqual(r.points[0].yFeet, 3.28, accuracy: 0.6)
        for i in 1..<r.points.count {
            XCTAssertGreaterThan(r.points[i].time, r.points[i - 1].time)
        }
    }
}
