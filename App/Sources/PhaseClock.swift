import Foundation
import DerbyCore

/// The one place in the game that asks what time it is (DESIGN.md §20 "The phase is an input of
/// the machine"). `GameController` reads it and offers the answer to the machine; a scene never
/// does, which is what keeps a replay drawing the same frames as the live game.
///
/// Nothing about the sun is worked out here — `SunClock` does all of that, in Core, where it can
/// be tested against §20's calibration table. This is the adapter: it turns a `Date`, a
/// `Calendar` and a `TimeZone` into the six numbers that function wants.
enum PhaseClock {

    /// The phase right now, for the device's own calendar and time zone.
    static func phase(now: Date = Date(),
                      calendar: Calendar = .current,
                      zone: TimeZone = .current,
                      rules: SkyClockRules = .standard) -> DayPhase {
        let place = place(for: zone, at: now, rules: rules)
        var calendar = calendar
        calendar.timeZone = zone
        let day = calendar.ordinality(of: .day, in: .year, for: now) ?? 172
        let parts = calendar.dateComponents([.hour, .minute, .second], from: now)
        let minutes = Double(parts.hour ?? 12) * 60 + Double(parts.minute ?? 0)
            + Double(parts.second ?? 0) / 60
        return SunClock.phase(dayOfYear: day, minutes: minutes,
                              utcOffsetHours: place.standardOffsetHours,
                              daylightSavingMinutes: place.daylightSavingMinutes,
                              latitude: place.latitude, longitude: place.longitude,
                              rules: rules)
    }

    /// Where the sun is to be reckoned from, and how this zone's clock is set.
    ///
    /// The game never asks for the player's location and shows no menu to set one (§1, §20), so
    /// the zone's own city is the place. `ZoneCities` is the tz database's table of those cities.
    /// A zone it has never heard of falls back to the assumed latitude and to the zone's own
    /// meridian — fifteen degrees per hour of standard offset — which is the middle of where a
    /// zone's clock says the sun should be, and the honest guess when there is nothing better.
    ///
    /// The saving is pulled out of the offset rather than left in it because `SunClock` uses the
    /// two differently: the standard offset says which meridian the clock keeps, and the saving
    /// simply slides every reading along. Leaving them together would move the whole zone a
    /// degree east for half the year.
    static func place(for zone: TimeZone, at now: Date, rules: SkyClockRules = .standard)
        -> (latitude: Double, longitude: Double,
            standardOffsetHours: Double, daylightSavingMinutes: Double) {
        let daylightSaving = zone.daylightSavingTimeOffset(for: now)
        let standardOffsetHours = (Double(zone.secondsFromGMT(for: now)) - daylightSaving) / 3600
        if let city = ZoneCities.coordinates(for: zone.identifier) {
            return (city.latitude, city.longitude, standardOffsetHours, daylightSaving / 60)
        }
        return (rules.assumedLatitudeDegrees, standardOffsetHours * 15,
                standardOffsetHours, daylightSaving / 60)
    }
}
