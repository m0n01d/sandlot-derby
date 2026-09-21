import XCTest
@testable import DerbyCore

/// DESIGN.md §20's calibration table, which is this file's oracle exactly as `docs/physics.md` is
/// `FlightTests`'. The tolerance there is two minutes, and three of the rows carry an almanac
/// column showing the model agrees with the real sky to one.
///
/// Nothing here reads the system clock. A date, a place and a clock reading go in; a phase comes
/// out (§20 "The phase is an input of the machine").
final class SunClockTests: XCTestCase {

    /// One row of §20's table. Every time is minutes after local midnight.
    private struct Row {
        let note: String
        let day: Int
        let latitude: Double
        let longitude: Double
        let utcOffsetHours: Double
        let daylightSavingMinutes: Double
        let sunrise: Int
        let sunset: Int
        /// The six starts, in the order of `DayPhase.allCases`.
        let starts: [Int]
    }

    private static func at(_ h: Int, _ m: Int) -> Int { h * 60 + m }

    private static let table: [Row] = [
        Row(note: "21 March, on the zone meridian", day: 80,
            latitude: 40, longitude: -75, utcOffsetHours: -5, daylightSavingMinutes: 60,
            sunrise: at(7, 5), sunset: at(19, 10),
            starts: [at(6, 25), at(7, 55), at(11, 8), at(17, 40), at(19, 10), at(19, 50)]),
        Row(note: "21 June, on the zone meridian", day: 172,
            latitude: 40, longitude: -75, utcOffsetHours: -5, daylightSavingMinutes: 60,
            sunrise: at(5, 31), sunset: at(20, 32),
            starts: [at(4, 51), at(6, 21), at(11, 2), at(19, 2), at(20, 32), at(21, 12)]),
        Row(note: "21 September, on the zone meridian", day: 264,
            latitude: 40, longitude: -75, utcOffsetHours: -5, daylightSavingMinutes: 60,
            sunrise: at(6, 48), sunset: at(18, 56),
            starts: [at(6, 8), at(7, 38), at(10, 52), at(17, 26), at(18, 56), at(19, 36)]),
        Row(note: "21 December, on the zone meridian", day: 355,
            latitude: 40, longitude: -75, utcOffsetHours: -5, daylightSavingMinutes: 0,
            sunrise: at(7, 19), sunset: at(16, 39),
            starts: [at(6, 39), at(8, 9), at(9, 59), at(15, 9), at(16, 39), at(17, 19)]),
        Row(note: "21 June, south of the equator", day: 172,
            latitude: -40, longitude: 175, utcOffsetHours: 12, daylightSavingMinutes: 0,
            sunrise: at(7, 42), sunset: at(17, 1),
            starts: [at(7, 2), at(8, 32), at(10, 22), at(15, 31), at(17, 1), at(17, 41)]),
        // The short day: `midday` would open at 09:59, before `morning` did, so it takes
        // `morning`'s start and `morning` is left with no minutes of its own (§20).
        Row(note: "21 December, a short day: morning has zero length", day: 355,
            latitude: 65, longitude: 15, utcOffsetHours: 1, daylightSavingMinutes: 0,
            sunrise: at(10, 12), sunset: at(13, 46),
            starts: [at(9, 32), at(11, 2), at(11, 2), at(12, 16), at(13, 46), at(14, 26)]),
        Row(note: "New York, 21 June. Almanac 05:25 and 20:31", day: 172,
            latitude: 40.71, longitude: -74.01, utcOffsetHours: -5, daylightSavingMinutes: 60,
            sunrise: at(5, 25), sunset: at(20, 30),
            starts: [at(4, 45), at(6, 15), at(10, 58), at(19, 0), at(20, 30), at(21, 10)]),
        Row(note: "Boise, 21 June. Almanac 06:03 and 21:30", day: 172,
            latitude: 43.62, longitude: -116.20, utcOffsetHours: -7, daylightSavingMinutes: 60,
            sunrise: at(6, 3), sunset: at(21, 29),
            starts: [at(5, 23), at(6, 53), at(11, 46), at(19, 59), at(21, 29), at(22, 9)]),
        Row(note: "Madrid, 21 June. Almanac 06:45 and 21:48", day: 172,
            latitude: 40.42, longitude: -3.70, utcOffsetHours: 1, daylightSavingMinutes: 60,
            sunrise: at(6, 44), sunset: at(21, 48),
            starts: [at(6, 4), at(7, 34), at(12, 16), at(20, 18), at(21, 48), at(22, 28)]),
    ]

    private func starts(_ row: Row) -> [(DayPhase, Double)] {
        SunClock.phaseStarts(dayOfYear: row.day, utcOffsetHours: row.utcOffsetHours,
                             daylightSavingMinutes: row.daylightSavingMinutes,
                             latitude: row.latitude, longitude: row.longitude)
    }

    private func phase(_ row: Row, at minutes: Double) -> DayPhase {
        SunClock.phase(dayOfYear: row.day, minutes: minutes, utcOffsetHours: row.utcOffsetHours,
                       daylightSavingMinutes: row.daylightSavingMinutes,
                       latitude: row.latitude, longitude: row.longitude)
    }

    // MARK: - The table

    func testSunriseAndSunsetMatchTheTable() {
        for row in Self.table {
            let sun = SunClock.sunTimes(dayOfYear: row.day, utcOffsetHours: row.utcOffsetHours,
                                        daylightSavingMinutes: row.daylightSavingMinutes,
                                        latitude: row.latitude, longitude: row.longitude)
            XCTAssertEqual(sun.sunrise, Double(row.sunrise), accuracy: 2, "sunrise, \(row.note)")
            XCTAssertEqual(sun.sunset, Double(row.sunset), accuracy: 2, "sunset, \(row.note)")
            // The table's two times are rounded to the minute, so their middle is only good to
            // half of one — but noon being the middle of the day at all is worth saying, because
            // the equation of time enters the sum once and a sign slip there would show here.
            XCTAssertEqual(sun.solarNoon, Double(row.sunrise + row.sunset) / 2, accuracy: 1,
                           "solar noon is the middle of the day, \(row.note)")
        }
    }

    func testEveryPhaseStartsWhenTheTableSaysItDoes() {
        for row in Self.table {
            let starts = starts(row)
            XCTAssertEqual(starts.map(\.0), DayPhase.allCases, "the order never changes")
            for (i, entry) in starts.enumerated() {
                XCTAssertEqual(entry.1, Double(row.starts[i]), accuracy: 2,
                               "\(entry.0.rawValue), \(row.note)")
            }
        }
    }

    /// A minute after a start is that phase, and a minute before it is whatever was in force —
    /// which is the phase before it, or `night` in the small hours before dawn. Probed against the
    /// computed starts rather than the table's rounded minutes, so the two-minute tolerance above
    /// cannot move a boundary out from under the probe.
    func testAMinuteEitherSideOfEveryStart() {
        for row in Self.table {
            let starts = starts(row)
            for (i, entry) in starts.enumerated() {
                let (phase, start) = entry
                // A zero-length phase has no minute of its own — row 6's `morning` is §20's own
                // example, and there the next phase has already started.
                if i + 1 == starts.count || starts[i + 1].1 > start + 1 {
                    XCTAssertEqual(self.phase(row, at: start + 1), phase,
                                   "a minute into \(phase.rawValue), \(row.note)")
                }
                let earlier = starts[..<i].last { $0.1 <= start - 1 }?.0 ?? .night
                XCTAssertEqual(self.phase(row, at: start - 1), earlier,
                               "a minute before \(phase.rawValue), \(row.note)")
            }
        }
    }

    /// §20: "Before the start of `dawn`, the phase is `night`." The small hours belong to the
    /// night the evening before began, which is what makes the clock rule readable at 1 a.m.
    func testBeforeDawnIsNight() {
        for row in Self.table {
            for minute in stride(from: 0.0, to: Double(row.starts[0]), by: 17) {
                XCTAssertEqual(phase(row, at: minute), .night, "\(minute) min, \(row.note)")
            }
        }
    }

    func testMorningHasZeroLengthOnAShortWinterDay() {
        let row = Self.table[5]
        var seen: Set<DayPhase> = []
        for minute in 0..<(24 * 60) { seen.insert(phase(row, at: Double(minute))) }
        XCTAssertFalse(seen.contains(.morning), "§20: a phase can have zero length")
        XCTAssertEqual(seen, [.dawn, .midday, .goldenHour, .twilight, .night])
    }

    /// Past the polar circles the hour angle's cosine genuinely leaves −1…1, and §20 says to clamp
    /// it. The two ends are the two right answers: a sun that never sets and one that never rises.
    func testThePolarCirclesClampRatherThanFail() {
        let midsummer = SunClock.sunTimes(dayOfYear: 172, utcOffsetHours: 0,
                                          daylightSavingMinutes: 0, latitude: 78, longitude: 0)
        XCTAssertEqual(midsummer.sunset - midsummer.sunrise, 24 * 60, accuracy: 0.001)
        let midwinter = SunClock.sunTimes(dayOfYear: 355, utcOffsetHours: 0,
                                          daylightSavingMinutes: 0, latitude: 78, longitude: 0)
        XCTAssertEqual(midwinter.sunset - midwinter.sunrise, 0, accuracy: 0.001)
        XCTAssertFalse(midsummer.sunrise.isNaN)
        XCTAssertFalse(midwinter.sunrise.isNaN)
    }

    // MARK: - What a phase means

    func testTheLampsAreOnInTwilightAndInNightAndNowhereElse() {
        XCTAssertEqual(DayPhase.allCases.filter(\.lampsOn), [.twilight, .night])
    }

    func testAPhaseTravelsAsItsName() throws {
        for phase in DayPhase.allCases {
            XCTAssertEqual(DayPhase(rawValue: phase.rawValue), phase)
            let json = try JSONEncoder().encode(phase)
            XCTAssertEqual(try JSONDecoder().decode(DayPhase.self, from: json), phase)
        }
        XCTAssertEqual(DayPhase.goldenHour.rawValue, "goldenHour")
    }

    /// The knobs are knobs: move one and the start it names moves with it, and nothing else does.
    func testTheKnobsMoveTheStartsTheyName() {
        var rules = SkyClockRules.standard
        rules.goldenLeadMinutes = 30
        let row = Self.table[0]
        let moved = SunClock.phaseStarts(dayOfYear: row.day, utcOffsetHours: row.utcOffsetHours,
                                         daylightSavingMinutes: row.daylightSavingMinutes,
                                         latitude: row.latitude, longitude: row.longitude,
                                         rules: rules)
        let standard = starts(row)
        XCTAssertEqual(moved[3].1, standard[3].1 + 60, accuracy: 0.001, "goldenHour moved an hour")
        for i in [0, 1, 2, 4, 5] {
            XCTAssertEqual(moved[i].1, standard[i].1, accuracy: 0.001, "nothing else moved")
        }
    }
}
