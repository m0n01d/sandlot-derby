import Foundation

/// The six phases one drawing has (DESIGN.md §20). A phase is a set of palette lines, a light
/// direction and a small number of switches. It never changes the hit test or the physics, and it
/// changes exactly one counted thing: the lights-out shot (§17 step 6) needs the lamps on.
///
/// The raw values are the names, because that is how a phase travels in a `Replay` record and how
/// the DEBUG `-phase` argument names one.
public enum DayPhase: String, Equatable, CaseIterable, Codable {
    /// 40 minutes before sunrise: a low sun on the right, long shadows to the left, ground mist.
    case dawn
    /// 50 minutes after sunrise: the sun in frame, top right.
    case morning
    /// Two hours before solar noon: the sun out of frame, above, and short shadows.
    case midday
    /// 90 minutes before sunset: a low sun on the left, long shadows to the right.
    case goldenHour
    /// Sunset: the sun below the horizon, the lamps on, the first stars.
    case twilight
    /// 40 minutes after sunset: all forty stars, a moon in the parks that have one, dark corners.
    case night

    /// Whether the park's lamps are lit. The one thing a phase changes that is counted: a light
    /// standard can only be put out while it is on (§17 "Rare things", §20 "The phases"). A player
    /// who plays only by day never sees a lights-out shot; that is the cost of the clock rule.
    public var lampsOn: Bool { self == .twilight || self == .night }
}

/// The knobs behind the sun clock — where the sun is reckoned to be, and how long before and
/// after it each phase starts (DESIGN.md §20 "Knobs").
public struct SkyClockRules: Equatable {
    /// The latitude to use when `ZoneCities` has never heard of the device's time zone. Forty
    /// degrees is the middle of the latitudes people play at, and it is the latitude every row of
    /// §20's first four calibration rows is taken at.
    public var assumedLatitudeDegrees: Double = 40
    /// The sun's altitude at sunrise and at sunset, in degrees. Not zero: the standard figure
    /// allows for the sun's own disc and for refraction near the horizon, which together put the
    /// middle of the sun a little below the skyline at the moment it is called risen.
    public var horizonDegrees: Double = -0.83
    /// `dawn` starts this long before sunrise.
    public var dawnLeadMinutes: Double = 40
    /// `morning` starts this long after sunrise.
    public var dawnTailMinutes: Double = 50
    /// `midday` starts this long before solar noon.
    public var middayLeadMinutes: Double = 120
    /// `goldenHour` starts this long before sunset.
    public var goldenLeadMinutes: Double = 90
    /// `night` starts this long after sunset. `twilight` starts at sunset itself, so this is also
    /// how long twilight lasts.
    public var twilightMinutes: Double = 40

    public init() {}
    public static let standard = SkyClockRules()
}

/// Sunrise, solar noon, sunset and the phase, from a date and a place. Pure arithmetic: it never
/// reads the system clock and it never asks where the player is (DESIGN.md §20 "The sun clock").
/// `GameController` reads the clock and the time zone once and hands the answers in.
///
/// The model is the standard low-precision one — a cosine for the sun's declination, the classic
/// equation of time, and one hour-angle solve for the half-day. §20's calibration table is its
/// oracle, the way `docs/physics.md` is the flight's, and the tolerance there is two minutes.
/// It agrees with a real almanac to about a minute in the cities that table names. A player far
/// from the city of their own time zone sees a larger error, and western China is the worst case
/// in the world at about two hours (§20 open question 2).
public enum SunClock {

    /// The day's three sun times, in **minutes after local midnight**, for a place and a date.
    ///
    /// `utcOffsetHours` is the zone's *standard* offset, with `daylightSavingMinutes` carried
    /// separately, because the two do different jobs in the sum: the offset says which meridian
    /// the zone's clock keeps, and the saving simply slides every clock reading along.
    ///
    /// Latitude is north-positive and longitude east-positive. Nothing here is clamped to a day:
    /// above the Arctic circle in midsummer the half-day is the whole twelve hours and sunrise
    /// lands before midnight, which is the honest answer and exactly what the phases then want.
    public static func sunTimes(dayOfYear: Int,
                                utcOffsetHours: Double,
                                daylightSavingMinutes: Double,
                                latitude: Double,
                                longitude: Double,
                                rules: SkyClockRules = .standard)
        -> (sunrise: Double, solarNoon: Double, sunset: Double) {
        let day = Double(dayOfYear)
        let rad = Double.pi / 180

        // Where the sun is over, north or south, on this day of the year. The +10 puts the
        // cosine's trough on the December solstice rather than on New Year's Day.
        let declination = -23.44 * cos(360.0 / 365.0 * (day + 10) * rad)

        // How far round from noon the sun is when it reaches the horizon. The cosine is clamped
        // rather than allowed to fail: past the polar circles it genuinely leaves −1…1, and the
        // two ends are the two right answers — a sun that never sets, and one that never rises.
        let cosHour = (sin(rules.horizonDegrees * rad) - sin(latitude * rad) * sin(declination * rad))
            / (cos(latitude * rad) * cos(declination * rad))
        let hourAngle = acos(min(1, max(-1, cosHour))) / rad
        let halfDay = hourAngle / 15 * 60

        // The equation of time: how far ahead of or behind the clock the real sun runs, from the
        // tilt of the earth and the shape of its orbit. Minutes.
        let b = 360.0 * (day - 81) / 364 * rad
        let equationOfTime = 9.87 * sin(2 * b) - 7.53 * cos(b) - 1.5 * sin(b)

        // Noon on the clock, moved to the zone's meridian, then to the real sun. Four minutes a
        // degree is the earth's own turn.
        let solarNoon = 720 + daylightSavingMinutes
            + 4 * (utcOffsetHours * 15 - longitude) - equationOfTime

        return (solarNoon - halfDay, solarNoon, solarNoon + halfDay)
    }

    /// The six phase starts, in minutes after local midnight, in the order of §20's table.
    ///
    /// A start is never earlier than the one before it: on a short winter day `midday` would open
    /// before `morning` did, and the rule is that it takes `morning`'s start instead. That leaves
    /// `morning` zero minutes long and the six in order whatever the latitude — which is what §20
    /// means by "a phase can have zero length in a short winter day, and the order stays the same".
    public static func phaseStarts(dayOfYear: Int,
                                   utcOffsetHours: Double,
                                   daylightSavingMinutes: Double,
                                   latitude: Double,
                                   longitude: Double,
                                   rules: SkyClockRules = .standard) -> [(DayPhase, Double)] {
        let sun = sunTimes(dayOfYear: dayOfYear, utcOffsetHours: utcOffsetHours,
                           daylightSavingMinutes: daylightSavingMinutes,
                           latitude: latitude, longitude: longitude, rules: rules)
        let raw: [(DayPhase, Double)] = [
            (.dawn, sun.sunrise - rules.dawnLeadMinutes),
            (.morning, sun.sunrise + rules.dawnTailMinutes),
            (.midday, sun.solarNoon - rules.middayLeadMinutes),
            (.goldenHour, sun.sunset - rules.goldenLeadMinutes),
            (.twilight, sun.sunset),
            (.night, sun.sunset + rules.twilightMinutes),
        ]
        var out: [(DayPhase, Double)] = []
        var floor = -Double.greatestFiniteMagnitude
        for (phase, start) in raw {
            floor = max(floor, start)
            out.append((phase, floor))
        }
        return out
    }

    /// The phase at `minutes` after local midnight: the last one whose start is at or before it,
    /// and `night` before `dawn` has started — the small hours belong to the night that the
    /// evening before began (DESIGN.md §20 "The phases").
    public static func phase(dayOfYear: Int,
                             minutes: Double,
                             utcOffsetHours: Double,
                             daylightSavingMinutes: Double,
                             latitude: Double,
                             longitude: Double,
                             rules: SkyClockRules = .standard) -> DayPhase {
        let starts = phaseStarts(dayOfYear: dayOfYear, utcOffsetHours: utcOffsetHours,
                                 daylightSavingMinutes: daylightSavingMinutes,
                                 latitude: latitude, longitude: longitude, rules: rules)
        var out = DayPhase.night
        for (phase, start) in starts where minutes >= start { out = phase }
        return out
    }
}
