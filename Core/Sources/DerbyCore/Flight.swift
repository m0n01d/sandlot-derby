import Foundation

/// Physical constants and integration settings for a batted ball.
/// See docs/physics.md. Change a value here and the calibration table there in the same commit.
public struct FlightParams: Equatable {
    /// ½·ρ·A/m for a regulation ball, per metre (ρ 1.2 kg/m³, A 0.00421 m², m 0.145 kg).
    public var k: Double = 0.0174
    public var dragCoefficient: Double = 0.33
    public var liftCoefficient: Double = 0.15
    public var gravity: Double = 9.81
    public var timestep: Double = 1.0 / 240.0
    public var contactHeightMetres: Double = 1.0
    /// Fraction of vertical speed kept on each ground bounce.
    public var groundRestitution: Double = 0.4
    /// Fraction of horizontal speed kept on each ground bounce.
    public var groundFriction: Double = 0.75
    /// Per-step horizontal decay while rolling.
    public var rollDecay: Double = 0.985
    /// Fraction of horizontal speed kept (and reversed) on a wall hit.
    public var wallRestitution: Double = 0.35
    /// Hard cap on simulated seconds.
    public var maxTime: Double = 12

    public init() {}

    /// The shipped model.
    public static let calibrated = FlightParams()

    /// Same ball in a vacuum. Used for the ghost trajectory and for tests.
    public static var noAir: FlightParams {
        var p = FlightParams()
        p.dragCoefficient = 0
        p.liftCoefficient = 0
        return p
    }

    /// Drag with no backspin lift.
    public static var dragOnly: FlightParams {
        var p = FlightParams()
        p.liftCoefficient = 0
        return p
    }
}

/// One sample of the flight, in feet and seconds.
public struct FlightPoint: Equatable {
    public let xFeet: Double
    public let yFeet: Double
    public let time: Double
}

public struct FlightResult: Equatable {
    /// One sample per integration step, from contact until the ball stops.
    public let points: [FlightPoint]
    /// Distance at first ground contact (or where it stopped if it never landed cleanly).
    public let distanceFeet: Double
    /// Hit the wall below its top, either in the air or after landing and rolling.
    public let wallHit: Bool
    /// Cleared the wall in the air.
    public let homeRun: Bool
    public let apexFeet: Double
    /// Seconds from contact to first ground contact, nil if it never landed within maxTime.
    public let hangTime: Double?
}

public enum Flight {
    public static let feetPerMetre = 3.28084
    public static let metresPerSecondPerMPH = 0.44704

    /// Integrates the whole flight once. Deterministic for identical inputs.
    public static func simulate(
        exitVelocityMPH: Double,
        launchAngleDegrees: Double,
        wallDistanceFeet: Double,
        wallHeightFeet: Double,
        params: FlightParams = .calibrated
    ) -> FlightResult {
        let ft = feetPerMetre
        let v = exitVelocityMPH * metresPerSecondPerMPH
        let theta = launchAngleDegrees * .pi / 180
        var x = 0.0
        var y = params.contactHeightMetres
        var vx = v * cos(theta)
        var vy = v * sin(theta)
        var t = 0.0
        var wallHit = false
        var homeRun = false
        var distance: Double? = nil
        var hang: Double? = nil
        var apex = 0.0
        var points: [FlightPoint] = []
        points.reserveCapacity(Int(params.maxTime / params.timestep))

        let k = params.k, cd = params.dragCoefficient, cl = params.liftCoefficient
        let g = params.gravity, dt = params.timestep

        while t < params.maxTime {
            let s = (vx * vx + vy * vy).squareRoot()
            let ax = -k * cd * s * vx - k * cl * s * vy
            let ay = -g - k * cd * s * vy + k * cl * s * vx
            let prevXFeet = x * ft
            vx += ax * dt
            vy += ay * dt
            x += vx * dt
            y += vy * dt
            t += dt
            let xFeet = x * ft
            let yFeet = y * ft
            if yFeet > apex { apex = yFeet }

            // Wall plane crossing, left to right.
            if prevXFeet < wallDistanceFeet && xFeet >= wallDistanceFeet {
                if yFeet < wallHeightFeet {
                    wallHit = true
                    vx = -vx * params.wallRestitution
                    x = (wallDistanceFeet - 0.1) / ft
                } else if distance == nil {
                    homeRun = true
                }
            }

            if y < 0 {
                y = 0
                if distance == nil {
                    distance = max(0, xFeet)
                    hang = t
                }
                vy = -vy * params.groundRestitution
                vx *= params.groundFriction
                if abs(vy) < 0.5 { vy = 0 }
            }
            if y == 0 && vy == 0 {
                vx *= params.rollDecay
                if abs(vx) < 0.3 { break }
            }
            points.append(FlightPoint(xFeet: x * ft, yFeet: y * ft, time: t))
        }

        return FlightResult(
            points: points,
            distanceFeet: distance ?? max(0, x * ft),
            wallHit: wallHit,
            homeRun: homeRun,
            apexFeet: apex,
            hangTime: hang
        )
    }
}
