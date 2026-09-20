import Foundation

/// The knobs of the daily ten (DESIGN.md §18).
public struct WarmUpRules: Equatable {
    /// Pitches in a Warm Up. Ten is the whole of it: no outs, no timer, no menu.
    public var pitches = 10
    /// No Warm Up until the career has cleared this many parks. Ten Show-league pitches with no
    /// swing guide are a bad first minute, so the daily habit starts the day after the first
    /// ball goes out.
    public var minParksCleared = 1
    /// Day one of the count, as `YYYYMMDD`. The card's `WARM UP 173` is days since this,
    /// counting this one. **A placeholder**: set it to the ship date when there is one (§18).
    public var epochDay = 2026_04_01
    /// Where the share string points. **A placeholder** until the App Store has a URL for it.
    public var shareLink = "sandlotderby.app"
    public init() {}
    public static let standard = WarmUpRules()
}

/// How one warm-up pitch ended. `.taken` covers a called strike, a taken ball, and a pitch that
/// was still in the air when the app quit — a pitch cannot be peeked at by quitting (§18).
public enum WarmUpOutcome: String, Equatable, Codable {
    case homeRun, offTheWall, inPlay, swingAndMiss, taken

    /// The share string's glyph (DESIGN.md §18). Emoji squares are outside the sixteen colours
    /// and that is the point: the string lives in other people's apps, not in the game.
    public var glyph: String {
        switch self {
        case .homeRun: return "💥"
        case .offTheWall: return "🟨"
        case .inPlay: return "🟩"
        case .swingAndMiss: return "⬜"
        case .taken: return "⬛"
        }
    }
}

/// One spent pitch of a Warm Up: what the card draws and what the save carries.
public struct WarmUpPitch: Equatable, Codable {
    public let outcome: WarmUpOutcome
    /// How far the ball carried, whole feet. 0 for anything that was not hit.
    public let feet: Int

    public init(outcome: WarmUpOutcome, feet: Int = 0) {
        self.outcome = outcome
        self.feet = feet
    }

    /// What a pitch is worth the moment it is thrown, before it has resolved.
    public static let taken = WarmUpPitch(outcome: .taken)
}

/// A Warm Up's ten, finished or interrupted: what the result card, the share string, the
/// stats-board row and the save are all drawn from. Nothing is kept about any other day.
public struct WarmUpResult: Equatable, Codable {
    /// The local calendar day, `YYYYMMDD`.
    public let day: Int
    /// One entry per spent pitch, in the order they were thrown.
    public let pitches: [WarmUpPitch]

    public init(day: Int, pitches: [WarmUpPitch]) {
        self.day = day
        self.pitches = pitches
    }

    public var totalFeet: Int { pitches.reduce(0) { $0 + $1.feet } }
    public var homeRuns: Int { pitches.filter { $0.outcome == .homeRun }.count }
    /// The day's longest, 0 before anything has been hit.
    public var longestFeet: Int { pitches.map(\.feet).max() ?? 0 }

    /// What the card and the share string call this day: days since `epochDay`, counting it.
    public func number(rules: WarmUpRules = .standard) -> Int {
        WarmUp.serial(of: day) - WarmUp.serial(of: rules.epochDay) + 1
    }

    /// The share string (DESIGN.md §18). Text, because it has to paste anywhere:
    ///
    ///     WARM UP 173 · 1,847 FT
    ///     💥⬜🟩💥⬛🟨💥🟩⬜💥
    ///     <link>
    ///
    /// Built here rather than in the app so that it is a pure function of the result, and can
    /// be tested like everything else in Core.
    public func shareText(rules: WarmUpRules = .standard) -> String {
        let row = pitches.map(\.outcome.glyph).joined()
        return """
        WARM UP \(number(rules: rules)) · \(WarmUp.grouped(totalFeet)) FT
        \(row)
        \(rules.shareLink)
        """
    }
}

/// The day's card: one park and ten pitches, the same for everyone, a pure function of the day
/// number exactly as a park is of its number (DESIGN.md §18).
public struct WarmUp: Equatable {
    /// The player's local calendar day, `YYYYMMDD`. **Core never reads a clock**: the app hands
    /// this in at launch and whenever it comes back to the foreground.
    public let day: Int
    /// The day's park. Its wall comes from the ordinary seeded ranges and night is allowed, and
    /// it is a Show-league park, so The Show's rules apply: a daily taste of what is sold (§16).
    public let park: Park
    /// All ten, generated up front, so the sequence cannot depend on what the player does and
    /// the career's own generator is never drawn from.
    public let pitches: [Pitch]
    public let rules: WarmUpRules

    public init(day: Int, park: Park, pitches: [Pitch], rules: WarmUpRules = .standard) {
        self.day = day
        self.park = park
        self.pitches = pitches
        self.rules = rules
    }

    /// The day's card. Same day, same card, on every phone.
    ///
    /// The day number **is** the park number, which is what makes the rest fall out: a
    /// `YYYYMMDD` is far past The Show, so `Park.generate` reaches for the ordinary seeded wall
    /// ranges with night allowed, `League(parkNumber:)` answers The Show, and §17's scenery —
    /// itself a pure function of the park number — is seeded by the day for nothing. The clamp
    /// only stops a nonsense day from landing on a rung of the minors.
    public static func generate(day: Int, rules: WarmUpRules = .standard,
                                pitchingRules: PitchingRules = .standard,
                                ladder: Ladder = .standard) -> WarmUp {
        let park = Park.generate(number: max(League.theShow.rawValue + 1, day), ladder: ladder)
        // Its own stream, seeded by the day: nothing here may shift the park's wall or the
        // career's next pitch by a single draw.
        var g = SplitMix64(seed: UInt64(bitPattern: Int64(day)) &* 0x9E37_79B9_7F4A_7C15
                                 &+ 0x5DEE_CE66_D1CE_4B9F)
        let table = ladder.pitchingRules(pitchingRules, for: park.league)
        var thrown: [Pitch] = []
        thrown.reserveCapacity(rules.pitches)
        for _ in 0..<max(1, rules.pitches) {
            thrown.append(Pitching.generate(using: &g, rules: table))
        }
        return WarmUp(day: day, park: park, pitches: thrown, rules: rules)
    }

    /// A `YYYYMMDD` day as a plain count of days, so "yesterday" is a subtraction and the
    /// days-in-a-row count is arithmetic. Howard Hinnant's `days_from_civil`, integers only:
    /// Core never reads a clock and never builds a `Date`.
    public static func serial(of day: Int) -> Int {
        let month = (day / 100) % 100, dayOfMonth = day % 100
        let year = day / 10000 - (month <= 2 ? 1 : 0)
        let era = (year >= 0 ? year : year - 399) / 400
        let yearOfEra = year - era * 400                                        // 0…399
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + dayOfMonth - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// 1234567 → "1,234,567". Here rather than in the app because the share string is built in
    /// Core; the card reads it back out for the same number in the same shape.
    public static func grouped(_ value: Int) -> String {
        var out = ""
        for (i, ch) in String(value).reversed().enumerated() {
            if i > 0, i % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return String(out.reversed())
    }
}

/// A Warm Up in progress (DESIGN.md §18). While this is non-nil the career's park, next pitch
/// and generator are set aside untouched, and it carries its own home-run streak.
public struct WarmUpRun: Equatable {
    public let card: WarmUp
    /// One entry per **spent** pitch. Appended as `.taken` the moment the pitch is thrown and
    /// overwritten when it resolves, which is what makes a pitch spent at `.pitchThrown`: quit
    /// with one in the air and it comes back as taken.
    public internal(set) var pitches: [WarmUpPitch]
    /// Consecutive home runs inside this Warm Up. The career's streak is neither fed nor ended
    /// by a warm-up swing; `DerbyMachine.streakNow` is whichever of the two is live.
    public internal(set) var homeRunStreak: Int

    init(card: WarmUp, pitches: [WarmUpPitch] = [], homeRunStreak: Int = 0) {
        self.card = card
        self.pitches = pitches
        self.homeRunStreak = homeRunStreak
    }

    /// Pitches thrown so far, 0…`total`.
    public var spent: Int { pitches.count }
    public var total: Int { card.pitches.count }
    /// True once the tenth has been thrown. The card waits for its hold to play out.
    public var isSpent: Bool { spent >= total }
    public var result: WarmUpResult { WarmUpResult(day: card.day, pitches: pitches) }
}
