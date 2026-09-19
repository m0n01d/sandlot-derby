import Foundation

/// A point in design units (the 320×224 screen), y down.
public struct Point: Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct Rect: Equatable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
}

/// One row of the pitch table. Speeds in mph, breaks in design pixels.
public struct PitchType: Equatable {
    public let name: String
    public let speedRange: ClosedRange<Double>
    /// Late vertical drop, positive is down.
    public let breakY: Double
    /// Sideways drift over the flight, negative is toward the batter.
    public let breakX: Double
    /// Selection weight; the table's weights sum to 1.
    public let weight: Double
    /// Exit velocity bonus for squaring this pitch up (fast pitches carry more energy).
    public let exitVelocityBonusMPH: Double

    public static let fastball = PitchType(name: "FASTBALL", speedRange: 92...99, breakY: 0, breakX: 0, weight: 0.45, exitVelocityBonusMPH: 3)
    public static let changeup = PitchType(name: "CHANGEUP", speedRange: 74...82, breakY: 6, breakX: 0, weight: 0.25, exitVelocityBonusMPH: -3)
    public static let curve    = PitchType(name: "CURVE",    speedRange: 76...84, breakY: 22, breakX: -8, weight: 0.30, exitVelocityBonusMPH: 0)
    public static let all: [PitchType] = [.fastball, .changeup, .curve]
}

public struct Pitch: Equatable {
    public let type: PitchType
    public let speedMPH: Double
    public let isStrike: Bool
    /// Where the ball crosses the plate, in at-bat design units.
    public let target: Point
    /// Seconds from release to the plate. 0.60 s at 90 mph, scaled by speed.
    public var duration: Double { 0.60 * (90.0 / speedMPH) }

    public init(type: PitchType, speedMPH: Double, isStrike: Bool, target: Point) {
        self.type = type; self.speedMPH = speedMPH; self.isStrike = isStrike; self.target = target
    }
}

/// The ball at one instant of the pitch, in at-bat design units.
public struct BallSample: Equatable {
    public let x: Double
    public let y: Double
    /// Drawn radius in design pixels: 1, 2, 3 or 4 as it approaches.
    public let radius: Double
    public var position: Point { Point(x: x, y: y) }
}

public struct PitchingRules: Equatable {
    /// Oversized for thumbs. The real zone would be about 24×32 at this scale.
    public var strikeZone = Rect(x: 150, y: 136, width: 40, height: 50)
    public var releasePoint = Point(x: 166, y: 108)
    /// The pitch table. The minors throw a shorter, slower one (`Ladder`).
    public var types: [PitchType] = PitchType.all
    /// Share of pitches that end inside the zone.
    public var strikeProbability = 0.65
    /// How far outside the zone a ball can miss, in design pixels.
    public var ballMissRange: ClosedRange<Double> = 6...16
    /// Distance from the mound to the plate, used for "ball still N ft out" readouts.
    public var moundDistanceFeet = 60.5
    public init() {}
    public static let standard = PitchingRules()
}

public enum Pitching {
    /// Weights are relative to the table given, so a minor-league table need not sum to 1.
    public static func pickType<G: RandomNumberGenerator>(using g: inout G, from types: [PitchType] = PitchType.all) -> PitchType {
        let total = types.reduce(0) { $0 + $1.weight }
        var r = Double.random(in: 0..<1, using: &g) * total
        for t in types {
            if r < t.weight { return t }
            r -= t.weight
        }
        return types.first ?? PitchType.fastball
    }

    public static func generate<G: RandomNumberGenerator>(using g: inout G, rules: PitchingRules = .standard) -> Pitch {
        let type = pickType(using: &g, from: rules.types)
        let speed = Double.random(in: type.speedRange, using: &g)
        let strike = Double.random(in: 0..<1, using: &g) < rules.strikeProbability
        let z = rules.strikeZone
        let target: Point
        if strike {
            target = Point(x: z.x + 4 + Double.random(in: 0..<(z.width - 8), using: &g),
                           y: z.y + 4 + Double.random(in: 0..<(z.height - 8), using: &g))
        } else {
            let side = Int.random(in: 0..<4, using: &g)
            let m = Double.random(in: rules.ballMissRange, using: &g)
            switch side {
            case 0:  target = Point(x: z.x - m, y: z.y + Double.random(in: 0..<z.height, using: &g))
            case 1:  target = Point(x: z.x + z.width + m, y: z.y + Double.random(in: 0..<z.height, using: &g))
            case 2:  target = Point(x: z.x + Double.random(in: 0..<z.width, using: &g), y: z.y - m)
            default: target = Point(x: z.x + Double.random(in: 0..<z.width, using: &g), y: z.y + z.height + m)
            }
        }
        return Pitch(type: type, speedMPH: speed, isStrike: strike, target: target)
    }

    /// Ball position at `progress` (0 at release, 1 at the plate, up to 1.15 past it).
    public static func ball(_ pitch: Pitch, at progress: Double, rules: PitchingRules = .standard) -> BallSample {
        let p = progress
        let rel = rules.releasePoint
        let ty = pitch.type
        let x = rel.x + (pitch.target.x - rel.x) * p + ty.breakX * sin(p * .pi)
        let y = rel.y + (pitch.target.y - rel.y) * p * p
            - ty.breakY * (1 - p) * p * 1.6
            + ty.breakY * (p * p * p - p * p)
        let r: Double = p < 0.3 ? 1 : p < 0.6 ? 2 : p < 0.85 ? 3 : 4
        return BallSample(x: x, y: y, radius: r)
    }
}
