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

    private let layout = BackdropLayout.standard
    /// Everything behind the wall that does not move, drawn once per park, canvas and framing
    /// (DESIGN.md §17). The framing is a pure function of the park and the flight, so this
    /// rebuilds about once a home run, not once a frame.
    private let backdrops = BackdropCache()
    /// `Park.scenery` is computed; this keeps the one the frame needs instead of rebuilding it.
    private var cachedScenery: Scenery?

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

        let scenery = self.scenery(for: machine.park)
        let (behind, front) = backdrops.layers(
            for: BackdropKey(parkNumber: machine.park.number, width: canvas.width,
                             camera: camera == .close ? .close : .wide,
                             scale: view.scale, originX: view.originX),
            height: canvas.height) { b, f in
            BackdropArt.sideBackdrop(behind: b.canvas, front: f.canvas,
                                     park: machine.park, scenery: scenery,
                                     scale: view.scale, originX: view.originX,
                                     width: fullWidth, layout: self.layout)
        }
        // The layers are drawn with the ground at its canonical place; the close camera lifts it.
        let backdropDY = Int((ground - BackdropLayout.canonicalGround).rounded())

        // The sky is infinitely far away: it never moves, whatever the camera does.
        canvas.rect(0, 0, fullWidth, H, scheme.sky1)
        canvas.rect(0, 70, fullWidth, 60, scheme.sky2)
        canvas.rect(0, 130, fullWidth, max(0, ground - 130), scheme.sky3)
        canvas.dither(0, 66, fullWidth, 8, scheme.sky1, scheme.sky2)
        canvas.dither(0, 126, fullWidth, 8, scheme.sky2, scheme.sky3)

        Clouds.draw(into: canvas, clouds: scenery.sideClouds,
                    breeze: scenery.breezePixelsPerSecond,
                    seconds: machine.tally[.secondsPlayed],
                    width: fullWidth, night: machine.park.isNight)

        drawFireworks(canvas, machine, fullWidth: fullWidth)

        behind.blit(onto: canvas, dy: backdropDY)

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
                canvas.px(X + 1, Y + 1, Palette.cap)        // all the lace a 4 px ball has room for
            case .close:
                // The 6 px ball with its one highlight pixel (DESIGN.md §9), and its shadow.
                canvas.rect(X - 3, ground + 1, 6, 2, Palette.shade)
                canvas.baseball(X, Y, radius: 3, highlight: scheme.sky3)
            }

            drawInFrontOfTheBall(canvas, front: front, dy: backdropDY,
                                 machine: machine, view: view, scenery: scenery)

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
                // `streakNow`: the Warm Up's streak while one is live, the career's otherwise.
                if flightResult.homeRun, machine.streakNow >= 2 {
                    let streak = "STREAK \(machine.streakNow)"
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
        } else {
            drawInFrontOfTheBall(canvas, front: front, dy: backdropDY,
                                 machine: machine, view: view, scenery: scenery)
        }

        // The same word the outfield scoreboard carries: during a Warm Up this is the day's
        // park, not a park anyone is trying to clear, and its number is a date (DESIGN.md §18).
        let parkName = machine.warmUp == nil ? machine.park.displayName : "WARM UP"
        canvas.t3(fullWidth - 10 - Double(parkName.count) * 4, H - 12, parkName, Palette.chalk)
    }

    /// This park's scenery, kept between frames: `Park.scenery` is a pure function and builds
    /// its cloud stamps fresh every time it is asked.
    private func scenery(for park: Park) -> Scenery {
        if let s = cachedScenery, s.parkNumber == park.number { return s }
        let s = park.scenery
        cachedScenery = s
        return s
    }

    /// The stands and their crowd, the pop where a home run went into them, and the wall's own
    /// number. §17's draw order puts the stands after the trail and the ball — which is what
    /// makes a home run drop into the crowd and be gone — and the text after everything.
    private func drawInFrontOfTheBall(_ canvas: PixelCanvas, front: BackdropLayer, dy: Int,
                                      machine: DerbyMachine, view: Framing, scenery: Scenery) {
        front.blit(onto: canvas, dy: dy)

        if let entry = vanishPoint(machine, scenery: scenery),
           machine.playbackIndex >= Double(entry.index) {
            // Seconds since it went in, off the machine's own clocks. Playback stops dead at
            // the last point of the flight, so once the landing number is up the result hold's
            // own clock carries the pop the rest of the way out — otherwise a ball that landed
            // just after it vanished left its pop on screen for the whole hold.
            let played = (machine.playbackIndex - Double(entry.index))
                * FlightParams.calibrated.timestep / machine.timings.flightSpeed
            let since = machine.beat == .result ? played + machine.elapsed : played
            if since < layout.popSeconds {
                // Two frames, no alpha: a big pop, then a small one, then nothing.
                let r = since < layout.popSeconds / 2 ? layout.popRadius : layout.popRadius - 1
                let x = view.x(entry.point.xFeet).rounded()
                let y = view.y(entry.point.yFeet).rounded()
                canvas.rect(x - r, y, r * 2 + 1, 1, Palette.chalk)
                canvas.rect(x, y - r, 1, r * 2 + 1, Palette.chalk)
                canvas.px(x - r + 1, y - r + 1, Palette.chalk)
                canvas.px(x + r - 1, y - r + 1, Palette.chalk)
                canvas.px(x - r + 1, y + r - 1, Palette.chalk)
                canvas.px(x + r - 1, y + r - 1, Palette.chalk)
            }
        }

        let wallX = view.x(machine.park.wallDistanceFeet)
        let wallH = machine.park.wallHeightFeet * view.scale
        // On the wall when it is tall enough to carry a 5 px face, above it when it is not.
        let wallLabelY = wallH >= 11 ? view.ground - wallH + 3 : view.ground - wallH - 8
        canvas.t3(wallX + 6, wallLabelY, "\(Int(machine.park.wallDistanceFeet))", Palette.score)
    }

    /// The first point of the flight that is inside the stands: where the ball is swallowed.
    /// Nil in Single-A, which has no stands, and for anything that does not clear the wall.
    private func vanishPoint(_ machine: DerbyMachine, scenery: Scenery) -> (index: Int, point: FlightPoint)? {
        guard scenery.stands.swallowsTheBall,
              let flight = machine.flight, flight.homeRun else { return nil }
        let wall = machine.park.wallDistanceFeet
        for i in 0..<flight.points.count {
            let p = flight.points[i]
            guard p.xFeet >= wall else { continue }
            let stands = BackdropArt.standsHeightFeet(at: p.xFeet, park: machine.park,
                                                      scenery: scenery, layout: layout)
            if p.yFeet <= stands { return (i, p) }
        }
        return nil
    }

    /// Home-run fireworks (DESIGN.md §17 "Fireworks"): screen-space, so a burst sits in the same
    /// place whether this frame is wide or close, drawn right after the sky so the field, wall,
    /// ball and every readout land on top of it. `DerbyCore.Fireworks` does all the maths; this
    /// only turns a particle's role into a palette pixel.
    private func drawFireworks(_ canvas: PixelCanvas, _ machine: DerbyMachine, fullWidth: Double) {
        guard let show = machine.fireworks else { return }
        let scheme = Palette.scheme(isNight: show.isNight)
        let particles = Fireworks.particles(show: show, at: machine.tally[.secondsPlayed], rules: machine.fireworksRules)
        for particle in particles where particle.visible {
            let colour: Palette.RGBA8
            switch particle.colour {
            case .score: colour = Palette.score
            case .cap: colour = Palette.cap
            case .chalk: colour = Palette.chalk
            case .skin: colour = Palette.skin
            case .sky3: colour = scheme.sky3
            }
            let x = fullWidth * particle.x
            if particle.size >= 2 {
                canvas.rect(x, particle.y, 2, 2, colour)
            } else {
                canvas.px(x, particle.y, colour)
            }
        }
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
