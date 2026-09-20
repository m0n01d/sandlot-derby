import Foundation

/// How the side view frames a park, in design pixels. These were `WideScene`'s private constants
/// until #5 needed them: a rare event is judged against where the ball is *drawn*, so the framing
/// had to become something Core can work out and a test can check (DESIGN.md §17 "Everything is a
/// pure function"). The scene still owns every other number it draws with.
public struct SideViewRules: Equatable {
    /// The canonical canvas. A phone is wider and simply sees more sky (§8); a replay clip is
    /// drawn at exactly this width, and so is every rare event's hit test, so that what the
    /// player saw and what the clip shows are the same thing on every phone (DESIGN.md §19).
    public var designWidth: Double = 320
    /// The ground, which never moves in the wide framing.
    public var groundY: Double = 176

    /// Wide: the view starts this far behind the plate (DESIGN.md §8).
    public var wideLeftFeet: Double = -24
    /// Wide: the field gets the screen, with the wall this far across, so what is behind it is
    /// the last third and no more and every park is framed to its own wall.
    public var wideWallAt: Double = 2.0 / 3.0
    /// Wide: unless this ball needs more. Its farthest point stays this far inside the right edge
    /// and its apex this far under the top, by pulling back just enough for this flight.
    public var landingMarginFeet: Double = 20
    public var apexMarginPixels: Double = 16

    /// Close: this many times the park's wide scale, with the wall this far across the screen.
    public var closeScale: Double = 2
    public var closeWallAt: Double = 0.55
    /// Close: the ground drops out of frame rather than let the ball leave the top.
    public var closeHeadroom: Double = 24

    public init() {}
    public static let standard = SideViewRules()
}

/// World feet → canvas pixels for one frame of the side view.
public struct SideView: Equatable {
    /// Pixels per foot.
    public let scale: Double
    /// Canvas x of 0 ft.
    public let originX: Double
    /// Canvas y of 0 ft.
    public let ground: Double

    public init(scale: Double, originX: Double, ground: Double) {
        self.scale = scale; self.originX = originX; self.ground = ground
    }

    public func x(_ feet: Double) -> Double { originX + feet * scale }
    public func y(_ feet: Double) -> Double { ground - feet * scale }

    /// The framing for one frame: a pure function of the park, the whole flight, how much of it
    /// has played and the canvas it is being drawn on. Nothing here reads a clock or a scene, so
    /// the live game, a replay clip and a Core test all arrive at the same numbers.
    ///
    /// `ballFeet` is how high the ball is right now, which only the close framing uses: it lets
    /// the ground drop out of frame rather than let a towering fly leave the top.
    public static func framing(camera: FlightCamera, wallDistanceFeet: Double,
                               distanceFeet: Double?, apexFeet: Double?, ballFeet: Double,
                               width: Double, safeLeft: Double = 0, safeRight: Double = 0,
                               rules: SideViewRules = .standard) -> SideView {
        let usable = width - safeLeft - safeRight
        let parkScale = usable * rules.wideWallAt / (wallDistanceFeet - rules.wideLeftFeet)
        switch camera {
        case .wide:
            // Framed on where the ball first comes down, not where it rolls to: the roll of a
            // home run is behind the wall and nobody's business.
            var s = parkScale
            if let distanceFeet, let apexFeet {
                s = min(s, usable / (distanceFeet + rules.landingMarginFeet - rules.wideLeftFeet))
                s = min(s, (rules.groundY - rules.apexMarginPixels) / max(1, apexFeet))
            }
            return SideView(scale: s, originX: safeLeft - rules.wideLeftFeet * s, ground: rules.groundY)
        case .close:
            // Twice the park's scale, eased off only for a ball that lands so far past the wall
            // that it would come down off the right edge.
            var s = parkScale * rules.closeScale
            if let distanceFeet, distanceFeet > wallDistanceFeet {
                let room = width * (1 - rules.closeWallAt) - safeRight
                s = min(s, room / (distanceFeet - wallDistanceFeet + rules.landingMarginFeet))
            }
            let lift = max(0, rules.closeHeadroom - (rules.groundY - ballFeet * s))
            return SideView(scale: s, originX: width * rules.closeWallAt - wallDistanceFeet * s,
                            ground: rules.groundY + lift)
        }
    }

    /// The same, off a park and a flight. The live scene passes its own canvas width; a hit test
    /// passes `rules.designWidth` and no safe area, which is what makes the answer the same on
    /// every phone.
    public static func framing(camera: FlightCamera, park: Park, flight: FlightResult?,
                               ballFeet: Double, width: Double,
                               safeLeft: Double = 0, safeRight: Double = 0,
                               rules: SideViewRules = .standard) -> SideView {
        framing(camera: camera, wallDistanceFeet: park.wallDistanceFeet,
                distanceFeet: flight?.distanceFeet, apexFeet: flight?.apexFeet,
                ballFeet: ballFeet, width: width, safeLeft: safeLeft, safeRight: safeRight,
                rules: rules)
    }

    /// The point of this flight the cut to the close camera falls on, or nil for a ball that
    /// never earns one — the same rule `DerbyMachine.flightCamera` applies to `playbackIndex`,
    /// in a form a hit test can ask about a point it has not reached. Only the flight is ever
    /// close; the result hold always cuts back out.
    ///
    /// Worked out once for a whole flight on purpose. Asking it per point walked the flight
    /// again each time, which made a detection sweep quadratic in a two-thousand-point arc.
    public static func closeCutIndex(flight: FlightResult, wallDistanceFeet: Double,
                                     rules: CameraRules = .standard) -> Int? {
        guard let reach = flight.points.max(by: { $0.xFeet < $1.xFeet })?.xFeet,
              reach >= wallDistanceFeet - rules.closeReachFeet
        else { return nil }
        return flight.points.firstIndex { $0.xFeet >= wallDistanceFeet - rules.closeLeadFeet }
    }

    /// Which framing is up at `index`, given that cut.
    public static func camera(at index: Int, closeCutIndex cut: Int?) -> FlightCamera {
        guard let cut else { return .wide }
        return index >= cut ? .close : .wide
    }
}
