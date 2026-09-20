import Foundation

/// Which career number just fell (DESIGN.md §10, issue #41). The tally has kept the bests all
/// along; this is the one thing that says a moment ago one of them changed hands.
public enum RecordKind: String, Equatable, Codable, CaseIterable {
    case longest, homeRunStreak, exitVelocity, apex, hangTime, fewestPitches

    /// What the result hold calls it, under `NEW RECORD`. Short enough that the longest of them
    /// still fits the 320-wide column in the 3×5 face at 2×.
    public var name: String {
        switch self {
        case .longest: return "LONGEST"
        case .homeRunStreak: return "HR STREAK"
        case .exitVelocity: return "EXIT VELO"
        case .apex: return "APEX"
        case .hangTime: return "HANG TIME"
        case .fewestPitches: return "FEWEST PITCHES"
        }
    }
}

/// The knobs of the celebration (DESIGN.md §10, #41).
public struct RecordRules: Equatable {
    /// No celebration until the career has this many swings behind it. Early on every swing is a
    /// best and a party every swing is not a party; by 25 the numbers mean something.
    public var minSwingsBeforeRecords = 25
    /// At most one record a swing, and this is the order it is chosen in: first match wins.
    /// Distance leads because the landing number is what the hold is already about.
    public var priority: [RecordKind] = [.longest, .homeRunStreak, .exitVelocity,
                                         .apex, .hangTime, .fewestPitches]
    public init() {}
    public static let standard = RecordRules()
}

/// The numbers one swing put up that the tally does not carry on its own.
public struct RecordSwing: Equatable {
    /// The live home-run streak before and after the swing: the Warm Up's while one is running,
    /// the career's otherwise (`DerbyMachine.streakNow`). The career's streak is a `Stat` and
    /// rides in the tally; a Warm Up's is not, so it travels here and both are read the same way.
    public var streakBefore: Int
    public var streakAfter: Int
    /// Whether the park really changes when this hold ends — the home run that made the count,
    /// and not at the ceiling, where the advance is owed and `fewestPitchesToClearPark` is not
    /// written yet (#40, §16).
    public var clearsThePark: Bool

    public init(streakBefore: Int, streakAfter: Int, clearsThePark: Bool) {
        self.streakBefore = streakBefore
        self.streakAfter = streakAfter
        self.clearsThePark = clearsThePark
    }
}

/// Whether a finished Warm Up beat what stood before it (DESIGN.md §18, #41). Two bools rather
/// than the numbers themselves: the card already draws the numbers, and all it is missing is
/// which of them is new.
public struct WarmUpBests: Equatable {
    /// The day's total feet beat the previous best, and there was a previous best to beat.
    public var feet: Bool
    /// The day's home runs beat the previous best, and there was a previous best to beat.
    public var homeRuns: Bool

    public init(feet: Bool, homeRuns: Bool) {
        self.feet = feet
        self.homeRuns = homeRuns
    }

    public var any: Bool { feet || homeRuns }
}

/// The comparison a record is: the tally before a swing against the tally after it. Pure, so the
/// live game, a replay clip and a test all arrive at the same answer for the same swing
/// (DESIGN.md §19).
public enum Records {

    /// The one record this swing set, or nil. Nil for a career too young to have records, nil
    /// when nothing was beaten, and nil for a number that had no previous best — the first of
    /// anything is not a record, it is the first.
    public static func kind(before: Tally, after: Tally, swing: RecordSwing,
                            rules: RecordRules = .standard) -> RecordKind? {
        guard before.count(.swings) >= rules.minSwingsBeforeRecords else { return nil }
        return rules.priority.first { fell($0, before: before, after: after, swing: swing) }
    }

    private static func fell(_ kind: RecordKind, before: Tally, after: Tally,
                             swing: RecordSwing) -> Bool {
        switch kind {
        case .longest: return beaten(.longestFeet, before, after)
        case .exitVelocity: return beaten(.bestExitVelocityMPH, before, after)
        case .apex: return beaten(.highestApexFeet, before, after)
        case .hangTime: return beaten(.longestHangTime, before, after)

        case .homeRunStreak:
            // Once per streak, on the home run that *passes* the old best and not on the ones
            // after it. By then the best is this streak's own, so "a new best" is true of every
            // one of them; what is only true of the first is that the streak it had to beat —
            // `bestHomeRunStreakAtStreakStart`, written as the streak left 0 — has just been
            // cleared. Anything further along is merely extending a record it already holds.
            guard beaten(.bestHomeRunStreak, before, after) else { return false }
            return swing.streakBefore <= before.count(.bestHomeRunStreakAtStreakStart)

        case .fewestPitches:
            // The only minimum, and the only one that is not in the after-tally yet: the park
            // change at the end of this hold is what writes it, from `pitchesThisPark` as this
            // swing left it. Strictly fewer, matching `Tally.lower`.
            guard swing.clearsThePark,
                  let old = before.value(ifRecorded: .fewestPitchesToClearPark) else { return false }
            return after[.pitchesThisPark] < old
        }
    }

    /// A maximum that both stood before this swing and is bigger after it. `value(ifRecorded:)`
    /// is what makes "there was a previous best" a different question from "the previous best
    /// was 0": a stat nobody has written is nil, not zero.
    private static func beaten(_ s: Stat, _ before: Tally, _ after: Tally) -> Bool {
        guard let old = before.value(ifRecorded: s), old > 0 else { return false }
        return after[s] > old
    }
}
