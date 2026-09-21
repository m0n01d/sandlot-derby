import XCTest
@testable import DerbyCore

/// The table `scripts/make-zone-cities.py` generates from the tz database. A tenth of a degree is
/// all the sun clock needs — it is about seven miles, which is under half a minute of sunrise.
final class ZoneCitiesTests: XCTestCase {

    private func assertCity(_ identifier: String, _ latitude: Double, _ longitude: Double,
                            file: StaticString = #filePath, line: UInt = #line) {
        guard let c = ZoneCities.coordinates(for: identifier) else {
            return XCTFail("\(identifier) is not in the table", file: file, line: line)
        }
        XCTAssertEqual(c.latitude, latitude, accuracy: 0.1, identifier, file: file, line: line)
        XCTAssertEqual(c.longitude, longitude, accuracy: 0.1, identifier, file: file, line: line)
    }

    /// The three cities DESIGN.md §20's calibration table names, at the coordinates it uses.
    func testTheCitiesTheCalibrationTableNames() {
        assertCity("America/New_York", 40.71, -74.01)
        assertCity("America/Boise", 43.62, -116.20)
        assertCity("Europe/Madrid", 40.42, -3.70)
    }

    /// North and east are positive, which is the one thing a sign error would quietly break: a
    /// southern-hemisphere park would get the northern hemisphere's seasons.
    func testNorthAndEastArePositive() {
        assertCity("Australia/Sydney", -33.87, 151.21)
        assertCity("Asia/Tokyo", 35.65, 139.75)
    }

    /// The legacy identifiers iOS can still report, which `zone.tab` does not carry. Each stands
    /// at its modern zone's city.
    func testTheLegacyAliasesLandOnTheirModernCity() {
        XCTAssertNotNil(ZoneCities.coordinates(for: "Asia/Calcutta"))
        for (old, new) in [("Asia/Calcutta", "Asia/Kolkata"),
                           ("Asia/Saigon", "Asia/Ho_Chi_Minh"),
                           ("Asia/Katmandu", "Asia/Kathmandu"),
                           ("Asia/Rangoon", "Asia/Yangon"),
                           ("America/Buenos_Aires", "America/Argentina/Buenos_Aires"),
                           ("US/Eastern", "America/New_York"),
                           ("US/Central", "America/Chicago"),
                           ("US/Mountain", "America/Denver"),
                           ("US/Pacific", "America/Los_Angeles")] {
            guard let a = ZoneCities.coordinates(for: old), let b = ZoneCities.coordinates(for: new) else {
                XCTFail("\(old) or \(new) is missing")
                continue
            }
            XCTAssertEqual(a.latitude, b.latitude, accuracy: 0.0001, old)
            XCTAssertEqual(a.longitude, b.longitude, accuracy: 0.0001, old)
        }
    }

    /// A zone the table has never heard of is nil, not a guess. The caller falls back to
    /// `SkyClockRules.assumedLatitudeDegrees` and the zone's own meridian (§20).
    func testAZoneTheTableDoesNotCarryIsNil() {
        XCTAssertNil(ZoneCities.coordinates(for: "Mars/Olympus_Mons"))
        XCTAssertNil(ZoneCities.coordinates(for: ""))
        XCTAssertNil(ZoneCities.coordinates(for: "america/new_york"), "identifiers are case-sensitive")
    }

    /// Every entry is a real place on the globe, which catches an ISO 6709 parse that dropped a
    /// digit or read a longitude as a latitude.
    func testEveryCityIsOnTheGlobe() {
        XCTAssertGreaterThan(ZoneCities.table.count, 400)
        for (name, c) in ZoneCities.table {
            XCTAssertTrue((-90...90).contains(c.latitude), "\(name) latitude \(c.latitude)")
            XCTAssertTrue((-180...180).contains(c.longitude), "\(name) longitude \(c.longitude)")
        }
    }

    /// The identifier the device actually reports is looked up by this table at launch, so at
    /// least the zone this machine is in had better be in it.
    func testThisMachinesOwnZoneIsInTheTable() throws {
        let id = TimeZone.current.identifier
        XCTAssertNotNil(ZoneCities.coordinates(for: id), "this machine reports \(id)")
    }
}
