import Foundation

/// Everything about turning a finger slice into a batted ball. See DESIGN.md §5.
public struct SliceRules: Equatable {
    /// Extra radius around the ball, in design pixels, inside which a slice counts.
    public var hitMarginPixels: Double = 9
    /// The slice is tested against where the ball was over this many seconds back.
    public var lagWindowSeconds: Double = 0.12
    public var lagSamples: Int = 4
    /// Contact quality falls to zero this far (in pitch progress) from arrival at the plate.
    public var timingWindow: Double = 0.28
    /// How much passing off-centre costs, 0…1.
    public var centreWeight: Double = 0.4
    /// Quality multiplier for hitting a pitch outside the zone.
    public var ballPenalty: Double = 0.8
    /// Power floor so a slow deliberate slice still hits.
    public var minPower: Double = 0.3
    /// Finger speed, design pixels per second, that reads as full power.
    public var fullPowerSpeed: Double = 520
    /// Drag length, design pixels, that reads as full power (28 % of a 320 screen).
    public var fullPowerLength: Double = 0.28 * 320
    /// Below this drag length the swing angle comes from the last segment instead.
    public var minAngleLength: Double = 12
    public var minSwingAngle: Double = -20
    public var maxSwingAngle: Double = 80
    /// Degrees of extra loft per unit of earliness (getting under a ball that hasn't arrived).
    public var earlyLoftDegrees: Double = 40
    public var minLaunchAngle: Double = -8
    public var maxLaunchAngle: Double = 70
    /// Exit velocity = base + span·(qualityWeight·q + (1−qualityWeight)·power) + pitch bonus.
    public var exitVelocityBase: Double = 55
    public var exitVelocitySpan: Double = 57
    public var qualityWeight: Double = 0.4
    public init() {}
    public static let standard = SliceRules()
}

/// A slice that crossed the ball.
public struct SliceCrossing: Equatable {
    /// 0…1, timing × centring × strike/ball.
    public let quality: Double
    /// Pitch progress at the ball sample that was crossed.
    public let progress: Double
    /// Direction of the stroke, degrees above horizontal, already clamped.
    public let swingAngleDegrees: Double
    /// 0…1.
    public let power: Double
    public let ball: BallSample
    public let crossingPoint: Point
}

public enum SliceOutcome: Equatable {
    /// Segment did not pass within the margin. Carries the closest approach for miss markers.
    case miss(closestDistance: Double, ball: BallSample, closestProgress: Double)
    /// Passed through the ball, but the ball was still too far from the plate to be hit.
    case early(ball: BallSample, progress: Double)
    case contact(SliceCrossing)
}

public struct Launch: Equatable {
    public let exitVelocityMPH: Double
    public let launchAngleDegrees: Double
}

public enum Contact {
    /// Shortest distance from `p` to segment `a`–`b`.
    public static func distance(from p: Point, toSegment a: Point, _ b: Point) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let l2 = dx * dx + dy * dy
        var t = l2 > 0 ? ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2 : 0
        t = min(1, max(0, t))
        let cx = a.x + dx * t, cy = a.y + dy * t
        return ((p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy)).squareRoot()
    }

    /// Tests one finger segment (the last two pointer samples) against the ball.
    /// - Parameters:
    ///   - a, b: the segment in design units, `b` is the newest sample.
    ///   - dragStart: where the finger went down; the swing angle is measured from here.
    ///   - fingerSpeed: design pixels per second over the last ~80 ms.
    ///   - progress: pitch progress now (`elapsed / pitch.duration`).
    public static func test(
        segment a: Point, _ b: Point,
        dragStart: Point,
        fingerSpeed: Double,
        pitch: Pitch,
        progress: Double,
        ballAt: (Double) -> BallSample,
        rules: SliceRules = .standard
    ) -> SliceOutcome {
        var bestD = Double.infinity
        var bestBall = ballAt(min(1.15, progress))
        var bestP = progress
        let step = rules.lagWindowSeconds / Double(rules.lagSamples) / pitch.duration
        for k in 0...rules.lagSamples {
            let pk = max(0, min(1.15, progress - Double(k) * step))
            let s = ballAt(pk)
            let d = distance(from: s.position, toSegment: a, b)
            if d < bestD { bestD = d; bestBall = s; bestP = pk }
        }
        let reach = bestBall.radius + rules.hitMarginPixels
        if bestD > reach {
            return .miss(closestDistance: bestD, ball: bestBall, closestProgress: bestP)
        }
        let timing = max(0, 1 - abs(bestP - 1) / rules.timingWindow)
        if timing <= 0 {
            return .early(ball: bestBall, progress: bestP)
        }
        let centring = 1 - min(1, bestD / reach) * rules.centreWeight
        var quality = timing * centring
        if !pitch.isStrike { quality *= rules.ballPenalty }

        var dx = b.x - dragStart.x, dy = b.y - dragStart.y
        if (dx * dx + dy * dy).squareRoot() < rules.minAngleLength {
            dx = b.x - a.x; dy = b.y - a.y
        }
        let rawAngle = atan2(-dy, abs(dx)) * 180 / .pi
        let angle = min(rules.maxSwingAngle, max(rules.minSwingAngle, rawAngle))
        let length = (dx * dx + dy * dy).squareRoot()
        let power = max(rules.minPower, min(1, max(fingerSpeed / rules.fullPowerSpeed, length / rules.fullPowerLength)))

        return .contact(SliceCrossing(quality: quality, progress: bestP, swingAngleDegrees: angle,
                                      power: power, ball: bestBall, crossingPoint: b))
    }

    /// Turns a crossing into launch conditions for `Flight.simulate`.
    public static func resolve(_ c: SliceCrossing, pitch: Pitch, rules: SliceRules = .standard) -> Launch {
        let blend = rules.qualityWeight * c.quality + (1 - rules.qualityWeight) * c.power
        let v = rules.exitVelocityBase + rules.exitVelocitySpan * blend + pitch.type.exitVelocityBonusMPH
        var deg = c.swingAngleDegrees + (1 - c.progress) * rules.earlyLoftDegrees
        deg = min(rules.maxLaunchAngle, max(rules.minLaunchAngle, deg))
        return Launch(exitVelocityMPH: v, launchAngleDegrees: deg)
    }
}
