import Foundation

/// Where a park sits on the way up. Parks 1–3 are the minors, park 4 is The Show, and every park
/// after that is just another day in the majors. A one-way door: nobody is ever sent down.
public enum League: Int, Equatable, CaseIterable {
    case singleA = 1, doubleA, tripleA, theShow

    public init(parkNumber: Int) {
        self = League(rawValue: max(1, min(parkNumber, League.theShow.rawValue))) ?? .theShow
    }

    public var name: String {
        switch self {
        case .singleA: return "SINGLE-A"
        case .doubleA: return "DOUBLE-A"
        case .tripleA: return "TRIPLE-A"
        case .theShow: return "THE SHOW"
        }
    }

    public var isMinors: Bool { self != .theShow }
}

/// One rung of the minors: a closer fence, a gentler pitcher, a more forgiving bat, and help on
/// screen. Each rung up takes one thing away, which is how the mechanics get uncovered without
/// a tutorial (DESIGN.md §10, §15).
public struct Rung: Equatable {
    public var wallDistanceFeet: Double
    public var wallHeightFeet: Double
    /// The only pitches thrown here. Weights are relative; they need not sum to 1.
    public var pitchTypes: [PitchType]
    public var strikeProbability: Double
    /// Replaces `SliceRules.hitMarginPixels`: how near a slice must pass.
    public var hitMarginPixels: Double
    /// Replaces `SliceRules.timingWindow`: how early a slice still counts.
    public var timingWindow: Double
    /// A dotted line through the pitch's target at the ideal swing angle. Says *where and which way*.
    public var swingGuide: Bool
    /// A ring that closes on the target as the ball arrives. Says *when*.
    public var timingRing: Bool
    /// One word on the result of a ball that stayed in the park: `SWING UP`, `LEVEL OUT`, `FASTER`.
    public var coaching: Bool
    /// Whether this rung has a ballpark organ (#17). A sandlot has no organist; every rung above
    /// it does. `DerbyMachine.hasOrgan` reads this; The Show has no rung and always has one.
    /// Claude's call, unreviewed (DESIGN.md §11).
    public var organ: Bool
}

/// The minors, and the knobs for the help they give.
public struct Ladder: Equatable {
    /// Clears at about 80 mph: half-decent timing with a half-speed slice gets a first home run.
    public var singleA = Rung(
        wallDistanceFeet: 280, wallHeightFeet: 6,
        pitchTypes: [PitchType(name: "FASTBALL", speedRange: 68...76, breakY: 0, breakX: 0, weight: 1, exitVelocityBonusMPH: 3)],
        strikeProbability: 1, hitMarginPixels: 14, timingWindow: 0.40,
        swingGuide: true, timingRing: true, coaching: true, organ: false)
    /// About 88 mph. The changeup arrives, and so do pitches outside the zone.
    public var doubleA = Rung(
        wallDistanceFeet: 320, wallHeightFeet: 8,
        pitchTypes: [PitchType(name: "FASTBALL", speedRange: 80...88, breakY: 0, breakX: 0, weight: 0.65, exitVelocityBonusMPH: 3),
                     PitchType(name: "CHANGEUP", speedRange: 68...76, breakY: 6, breakX: 0, weight: 0.35, exitVelocityBonusMPH: -3)],
        strikeProbability: 0.85, hitMarginPixels: 12, timingWindow: 0.34,
        swingGuide: false, timingRing: true, coaching: true, organ: true)
    /// About 93 mph. The full pitch table, the curve included, and no help but the coaching word.
    public var tripleA = Rung(
        wallDistanceFeet: 350, wallHeightFeet: 10,
        pitchTypes: PitchType.all,
        strikeProbability: 0.75, hitMarginPixels: 10, timingWindow: 0.30,
        swingGuide: false, timingRing: false, coaching: true, organ: true)

    /// The Show is the park every build before the minors called park 1. About 97 mph.
    public var theShowWallDistanceFeet: Double = 380
    public var theShowWallHeightFeet: Double = 10

    /// The angle the swing guide is drawn at: the calibration table's best carry.
    public var guideAngleDegrees: Double = 28
    /// Coaching: a launch below this gets `SWING UP`, above `coachHighAngle` gets `LEVEL OUT`,
    /// and a well-aimed ball under `coachWeakExitVelocity` gets `FASTER`.
    public var coachLowAngle: Double = 12
    public var coachHighAngle: Double = 42
    public var coachWeakExitVelocity: Double = 88

    public init() {}
    public static let standard = Ladder()

    public func rung(for league: League) -> Rung? {
        switch league {
        case .singleA: return singleA
        case .doubleA: return doubleA
        case .tripleA: return tripleA
        case .theShow: return nil
        }
    }

    /// The pitching rules in force in `league`: the majors' rules with the rung laid over them.
    public func pitchingRules(_ majors: PitchingRules, for league: League) -> PitchingRules {
        guard let r = rung(for: league) else { return majors }
        var p = majors
        p.types = r.pitchTypes
        p.strikeProbability = r.strikeProbability
        return p
    }

    public func sliceRules(_ majors: SliceRules, for league: League) -> SliceRules {
        guard let r = rung(for: league) else { return majors }
        var s = majors
        s.hitMarginPixels = r.hitMarginPixels
        s.timingWindow = r.timingWindow
        return s
    }
}
