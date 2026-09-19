import SpriteKit
import DerbyCore

/// The two flight cameras, side on: the batted ball travelling with real drag, and the landing
/// number. `DerbyMachine.flightCamera` says which framing is up; this scene only draws it, and
/// the change between them is a hard cut (the framing simply differs from one frame to the next).
///
/// The wide framing is a port of the prototype's `drawWide` (prototypes/03-camera-cut-and-
/// slice.html ~L426-455), minus its "wide only" debug drawing of the pitch and the miss.
final class WideScene: CanvasScene {
    private let groundY = 176.0
    /// Wide: the view starts 24 ft behind the plate (DESIGN.md §8).
    private let wideLeftFeet = -24.0
    /// Wide: the field gets the screen. The wall sits this far across, so what is behind it is
    /// the last third and no more, and every park is framed to its own wall.
    private let wideWallAt = 2.0 / 3.0
    /// Wide: unless this ball needs more. Its farthest point stays this far inside the right
    /// edge and its apex this far under the top, by pulling back just enough for this flight.
    private let landingMarginFeet = 20.0
    private let apexMarginPixels = 16.0
    /// Close: this many times the park's wide scale, with the wall this far across the screen.
    private let closeScale = 2.0
    private let closeWallAt = 0.55   // the ball cuts in about a quarter of the way across, clear of the island
    /// Close: the ground drops out of frame rather than let the ball leave the top.
    private let closeHeadroom = 24.0

    /// World feet → canvas pixels for one frame.
    private struct Framing {
        let scale: Double       // px per foot
        let originX: Double     // canvas x of 0 ft
        let ground: Double      // canvas y of 0 ft
        func x(_ feet: Double) -> Double { originX + feet * scale }
        func y(_ feet: Double) -> Double { ground - feet * scale }
    }

    private func framing(_ machine: DerbyMachine, width: Double) -> (Framing, FlightCamera) {
        // The field starts inside the safe area so the batter isn't under the Dynamic Island;
        // sky and grass still run edge to edge.
        let usable = width - safeLeft - safeRight
        let parkScale = usable * wideWallAt / (machine.park.wallDistanceFeet - wideLeftFeet)
        let camera = machine.flightCamera
        switch camera {
        case .wide:
            // A pure function of the park and the flight, so it holds still for the whole
            // flight and the result, and a replay frames it the same way.
            // Framed on where the ball first comes down, not where it rolls to: the roll of a
            // home run is behind the wall and nobody's business.
            var s = parkScale
            if let f = machine.flight {
                s = min(s, usable / (f.distanceFeet + landingMarginFeet - wideLeftFeet))
                s = min(s, (groundY - apexMarginPixels) / max(1, f.apexFeet))
            }
            return (Framing(scale: s, originX: safeLeft - wideLeftFeet * s, ground: groundY), camera)
        case .close:
            // Twice the park's scale, eased off only for a ball that lands so far past the wall
            // that it would come down off the right edge.
            var s = parkScale * closeScale
            if let f = machine.flight, f.distanceFeet > machine.park.wallDistanceFeet {
                let room = width * (1 - closeWallAt) - safeRight
                s = min(s, room / (f.distanceFeet - machine.park.wallDistanceFeet + landingMarginFeet))
            }
            let ballUp = (machine.playbackPoint?.yFeet ?? 0) * s
            let lift = max(0, closeHeadroom - (groundY - ballUp))
            let originX = width * closeWallAt - machine.park.wallDistanceFeet * s
            return (Framing(scale: s, originX: originX, ground: groundY + lift), camera)
        }
    }

    override func render(into canvas: PixelCanvas) {
        guard let controller else { return }
        let machine = controller.machine
        let scheme = Palette.scheme(isNight: machine.park.isNight)
        let H = 224.0
        let fullWidth = Double(canvas.width)
        let (view, camera) = framing(machine, width: fullWidth)
        let ground = view.ground

        // The sky is infinitely far away: it never moves, whatever the camera does.
        canvas.rect(0, 0, fullWidth, H, scheme.sky1)
        canvas.rect(0, 70, fullWidth, 60, scheme.sky2)
        canvas.rect(0, 130, fullWidth, max(0, ground - 130), scheme.sky3)
        canvas.dither(0, 66, fullWidth, 8, scheme.sky1, scheme.sky2)
        canvas.dither(0, 126, fullWidth, 8, scheme.sky2, scheme.sky3)

        // Grass, mown in 16 ft stripes: world space, so they widen with the scale.
        canvas.rect(0, ground, fullWidth, H - ground, Palette.grassA)
        let stripe = max(4, (16 * view.scale).rounded())
        var gx = view.x(0).truncatingRemainder(dividingBy: stripe * 2) - stripe * 2
        while gx < fullWidth { canvas.rect(gx, ground, stripe, H - ground, Palette.grassB); gx += stripe * 2 }

        let wallX = view.x(machine.park.wallDistanceFeet)
        let wallH = machine.park.wallHeightFeet * view.scale
        canvas.rect(wallX, ground - wallH, fullWidth - wallX, wallH, Palette.wall)
        canvas.rect(wallX, ground - wallH, fullWidth - wallX, 1, Palette.chalk)
        canvas.rect(wallX, ground - wallH - 1, 2, wallH + 1, Palette.chalk)
        // On the wall when it is tall enough to carry a 5 px face, above it when it is not.
        let wallLabelY = wallH >= 11 ? ground - wallH + 3 : ground - wallH - 8
        canvas.t3(wallX + 6, wallLabelY, "\(Int(machine.park.wallDistanceFeet))", Palette.score)

        var f = 100.0
        let tick = max(1, (view.scale / 0.75).rounded())
        while view.x(f) < fullWidth { canvas.rect(view.x(f), ground, tick, 4 * tick, Palette.chalk); f += 100 }

        canvas.rect(view.x(-6), ground, 12 * view.scale, 3, Palette.dirt)
        drawBatter(canvas, x: view.x(0), y: ground, scale: view.scale, machine: machine)

        if let flightResult = machine.flight, !flightResult.points.isEmpty {
            let points = flightResult.points
            let i = min(points.count - 1, Int(machine.playbackIndex))

            var k = 0
            while k < i {
                let pt = points[k]
                canvas.px(view.x(pt.xFeet), view.y(pt.yFeet) - 2, Palette.chalk)
                k += camera == .close ? 4 : 8
            }
            let b = points[i]
            let X = view.x(b.xFeet), Y = view.y(b.yFeet) - 3
            switch camera {
            case .wide:
                canvas.rect(X - 1, Y - 1, 4, 4, Palette.chalk)
                canvas.px(X, Y, scheme.sky3)
            case .close:
                // The 6 px ball with its one highlight pixel (DESIGN.md §9), and its shadow.
                canvas.rect(X - 3, ground + 1, 6, 2, Palette.shade)
                canvas.disc(X, Y, 3, Palette.chalk)
                canvas.px(X - 1, Y - 1, scheme.sky3)
            }

            if let launch = machine.launch {
                canvas.t3(8, 8, "\(Int(launch.exitVelocityMPH.rounded())) MPH", Palette.score, scale: 2)
                canvas.t3(8, 20, "\(Int(launch.launchAngleDegrees.rounded())) DEG", Palette.score, scale: 2)
            }
            canvas.t3(8, 34, machine.pitch.type.name, Palette.chalk)

            if machine.beat == .flight {
                let d = Int(min(b.xFeet, flightResult.distanceFeet).rounded())
                canvas.t3(min(fullWidth - 30, X + 6), max(6, Y - 10), "\(d) FT", Palette.chalk)
            }
            if machine.beat == .result {
                let d = Int(flightResult.distanceFeet.rounded())
                let distanceText = "\(d) FT"
                canvas.t5(fullWidth / 2 - Double(distanceText.count) * 6 * 3 / 2 + 3, 52, distanceText, Palette.score, scale: 3)
                if flightResult.homeRun, Int(machine.elapsed * 6) % 2 == 0 {
                    canvas.t5(fullWidth / 2 - 6 * 3, 88, "HR", Palette.cap, scale: 3)
                }
                if flightResult.homeRun, machine.tally.homeRunStreak >= 2 {
                    let streak = "STREAK \(machine.tally.homeRunStreak)"
                    canvas.t3(fullWidth / 2 - Double(streak.count) * 4, 116, streak, Palette.score, scale: 2)
                }
                if flightResult.wallHit {
                    canvas.t3(fullWidth / 2 - 30, 90, "OFF THE WALL", Palette.chalk)
                }
                // Minors only: one word on a ball that stayed in (DerbyMachine.coachingWord).
                if let word = machine.coachingWord {
                    canvas.t3(fullWidth / 2 - Double(word.count) * 4, 102, word, Palette.chalk, scale: 2)
                }
                // Once per career, on the home run that clears Triple-A.
                if machine.isBeingCalledUp, Int(machine.elapsed * 6) % 2 == 1 {
                    // The 5×7 face only has digits and F T H R, so this is the 3×5 at 3×.
                    canvas.t3(fullWidth / 2 - 9 * 4 * 3 / 2, 134, "CALLED UP", Palette.score, scale: 3)
                }
            }
        }

        let parkName = machine.park.displayName
        canvas.t3(fullWidth - 10 - Double(parkName.count) * 4, H - 12, parkName, Palette.chalk)
    }

    /// The batter is the yardstick for the wall, so he is drawn to the field's scale: most real
    /// walls are a man tall or more, and a 42 px batter (57 ft at the wide scale) made every
    /// fence look knee-high. A generous 6.5 ft, and never fewer pixels than still read as a figure.
    private let batterFeet = 6.5
    private let minBatterPixels = 6.0

    private func drawBatter(_ canvas: PixelCanvas, x: Double, y: Double, scale: Double, machine: DerbyMachine) {
        let frame: Int = machine.flight != nil ? (machine.playbackIndex < 12 ? 1 : 2) : 0
        let bx = x.rounded(.down), by = y
        let h = max(minBatterPixels, (batterFeet * scale).rounded())
        let w = max(3, (h / 3).rounded())
        let legs = max(1, (h * 0.33).rounded()), torso = max(1, (h * 0.38).rounded())
        let head = max(2, h - legs - torso), capRows = max(1, (head / 3).rounded())
        let left = bx - (w / 2).rounded(.down), legW = max(1, (w / 3).rounded(.down))
        let shoulders = by - legs - torso

        canvas.rect(left, by - legs, legW, legs, Palette.ink)
        canvas.rect(left + w - legW, by - legs, legW, legs, Palette.ink)
        canvas.rect(left, shoulders, w, torso, Palette.ink)
        canvas.rect(left, shoulders - head, w, head, Palette.skin)
        canvas.rect(left, shoulders - head, w + 1, capRows, Palette.cap)      // the brim faces the field

        let handsX = left + w - 1, handsY = shoulders + (torso * 0.4).rounded()
        let thick = h >= 16 ? 2 : 1
        switch frame {
        case 0: canvas.line(handsX, handsY, bx - h * 0.15, by - h * 1.3, Palette.bat, thickness: thick)   // stance
        case 1: canvas.line(handsX, handsY, handsX + h * 0.7, handsY - 1, Palette.bat, thickness: thick)  // contact
        default: canvas.line(left, handsY, left - h * 0.5, by - h * 1.15, Palette.bat, thickness: thick)  // follow-through
        }
    }
}
