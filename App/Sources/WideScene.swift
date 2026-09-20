import SpriteKit
import DerbyCore
import UIKit

/// The two flight cameras, side on: the batted ball travelling with real drag, and the landing
/// number. `DerbyMachine.flightCamera` says which framing is up; this scene only draws it, and
/// the change between them is a hard cut (the framing simply differs from one frame to the next).
///
/// The wide framing is a port of the prototype's `drawWide` (prototypes/03-camera-cut-and-
/// slice.html ~L426-455), minus its "wide only" debug drawing of the pitch and the miss.
final class WideScene: CanvasScene {
    /// How the two framings are built lives in Core (`SideViewRules`): a rare event is judged
    /// against where the ball is *drawn*, so the framing had to become something Core can work
    /// out and a test can check (#5). The scene still owns every other number it draws with.
    private let sideRules = SideViewRules.standard

    private let layout = BackdropLayout.standard
    /// Everything behind the wall that does not move, drawn once per park, canvas and framing
    /// (DESIGN.md §17). The framing is a pure function of the park and the flight, so this
    /// rebuilds about once a home run, not once a frame.
    private let backdrops = BackdropCache()
    /// `Park.scenery` is computed; this keeps the one the frame needs instead of rebuilding it.
    private var cachedScenery: Scenery?

    /// The framing for this frame, and which camera it is. The field starts inside the safe area
    /// so the batter isn't under the Dynamic Island; sky and grass still run edge to edge.
    private func framing(_ machine: DerbyMachine, width: Double) -> (SideView, FlightCamera) {
        let camera = machine.flightCamera
        return (SideView.framing(camera: camera, park: machine.park, flight: machine.flight,
                                 ballFeet: machine.playbackPoint?.yFeet ?? 0,
                                 width: width, safeLeft: safeLeft, safeRight: safeRight,
                                 rules: sideRules), camera)
    }

    override func render(into canvas: PixelCanvas) {
        guard let machine = renderMachine else { return }
        let scheme = Palette.scheme(isNight: machine.park.isNight)
        let H = 224.0
        let fullWidth = Double(canvas.width)
        let (frame, camera) = framing(machine, width: fullWidth)
        let ground = frame.ground

        let scenery = self.scenery(for: machine.park)
        let (behind, front) = backdrops.layers(
            for: BackdropKey(parkNumber: machine.park.number, width: canvas.width,
                             camera: camera == .close ? .close : .wide,
                             scale: frame.scale, originX: frame.originX),
            height: canvas.height) { b, f in
            BackdropArt.sideBackdrop(behind: b.canvas, front: f.canvas,
                                     park: machine.park, scenery: scenery,
                                     scale: frame.scale, originX: frame.originX,
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

        // §17's draw order, from the back: sky → stars / moon → light halos → clouds →
        // fireworks → birds → towers → field and wall face → trail and ball → stands and
        // crowd → text. Everything that moves reads one clock, the machine's own.
        let now = SceneryClock.now(machine)
        let towers = SkyArt.sideTowerFrames(park: machine.park, scenery: scenery,
                                            scale: frame.scale, originX: frame.originX,
                                            ground: ground, time: now,
                                            chasing: machine.crowdIsUp,
                                            isOut: machine.bankIsOut, layout: layout)
        if machine.park.isNight {
            SkyArt.nightSky(into: canvas, scenery: scenery, towers: towers,
                            time: now, width: fullWidth, layout: layout)
        }

        // What a long career has arrived at, never announced (#5). A Warm Up is played in a park
        // numbered by the *day*, which would clear every threshold there is by accident, so the
        // day's ten see the seeded landmarks and none of these (DESIGN.md §18).
        if machine.showsMilestones {
            SkyArt.comet(into: canvas, scenery: scenery, view: .side, time: now, width: fullWidth)
            SkyArt.searchlights(into: canvas, scenery: scenery, time: now, width: fullWidth,
                                footY: ground - scenery.standsTopFeet * frame.scale, layout: layout)
        }

        Clouds.draw(into: canvas, clouds: scenery.sideClouds,
                    breeze: scenery.breezePixelsPerSecond,
                    seconds: now,
                    width: fullWidth, night: machine.park.isNight)

        drawFireworks(canvas, machine, fullWidth: fullWidth)

        SkyArt.birds(into: canvas, scenery: scenery, view: .side, time: now,
                     width: fullWidth, night: machine.park.isNight,
                     skipping: machine.struckBird)
        if machine.showsMilestones {
            SkyArt.blimp(into: canvas, scenery: scenery, view: .side, time: now,
                         width: fullWidth, night: machine.park.isNight, layout: layout)
        }
        // Feathers, where the ball went through something (#5). In the sky, with the thing it
        // happened to, and before the field goes in on top.
        drawBursts(canvas, machine, frame: frame, fullWidth: fullWidth,
                   kinds: [.birdStrike, .blimpHit])

        behind.blit(onto: canvas, dy: backdropDY)

        // The towers stand behind the stands, so their feet are covered when the stands go in.
        // Lighter than the sky, not `ink`: this pole climbs through `night` and `ink`.
        SkyArt.towers(into: canvas, frames: towers, width: fullWidth,
                      poleColour: Palette.nightSky3, layout: layout)
        // …and the sparks off a bank that has just gone out, over the bank they came from.
        drawBursts(canvas, machine, frame: frame, fullWidth: fullWidth, kinds: [.lightsOut])

        // Grass, mown in 16 ft stripes: world space, so they widen with the scale.
        canvas.rect(0, ground, fullWidth, H - ground, Palette.grassA)
        let stripe = max(4, (16 * frame.scale).rounded())
        var gx = frame.x(0).truncatingRemainder(dividingBy: stripe * 2) - stripe * 2
        while gx < fullWidth { canvas.rect(gx, ground, stripe, H - ground, Palette.grassB); gx += stripe * 2 }

        let wallX = frame.x(machine.park.wallDistanceFeet)
        let wallH = machine.park.wallHeightFeet * frame.scale
        canvas.rect(wallX, ground - wallH, fullWidth - wallX, wallH, Palette.wall)
        canvas.rect(wallX, ground - wallH, fullWidth - wallX, 1, Palette.chalk)
        canvas.rect(wallX, ground - wallH - 1, 2, wallH + 1, Palette.chalk)

        var f = 100.0
        let tick = max(1, (frame.scale / 0.75).rounded())
        while frame.x(f) < fullWidth { canvas.rect(frame.x(f), ground, tick, 4 * tick, Palette.chalk); f += 100 }

        canvas.rect(frame.x(-6), ground, 12 * frame.scale, 3, Palette.dirt)
        drawBatter(canvas, x: frame.x(0), y: ground, scale: frame.scale, machine: machine)

        if let flightResult = machine.flight, !flightResult.points.isEmpty {
            let points = flightResult.points
            let i = min(points.count - 1, Int(machine.playbackIndex))

            var k = 0
            while k < i {
                let pt = points[k]
                canvas.px(frame.x(pt.xFeet), frame.y(pt.yFeet) - 2, Palette.chalk)
                k += camera == .close ? 4 : 8
            }
            let b = points[i]
            let X = frame.x(b.xFeet), Y = frame.y(b.yFeet) - 3
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
                                 machine: machine, frame: frame, scenery: scenery)

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
                                 machine: machine, frame: frame, scenery: scenery)
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
                                      machine: DerbyMachine, frame: SideView, scenery: Scenery) {
        front.blit(onto: canvas, dy: dy)

        // The crowd and the flags are the parts of the stands that move, so they are not in the
        // cached layer: the crowd bounces while the cheer plays (`DerbyMachine.crowdIsUp`) and
        // the flags flutter whatever the beat, because it is the wind that moves them.
        let now = SceneryClock.now(machine)
        let fullWidth = Double(canvas.width)
        BackdropArt.crowd(into: canvas, park: machine.park, scenery: scenery,
                          scale: frame.scale, originX: frame.originX, width: fullWidth,
                          ground: frame.ground, time: now, cheering: machine.crowdIsUp,
                          layout: layout)
        BackdropArt.standsFlags(into: canvas, park: machine.park, scenery: scenery,
                                scale: frame.scale, originX: frame.originX, width: fullWidth,
                                ground: frame.ground, frame: SkyLife.flutterFrame(at: now),
                                layout: layout)

        // What this park already carries: dents that stay and a pane that has gone (#5). Over
        // the cached board, and with the shards of the shot on screen on top of them.
        BackdropArt.boardDamage(into: canvas, park: machine.park, scenery: scenery,
                                scars: machine.parkScars, scale: frame.scale,
                                originX: frame.originX, ground: frame.ground, layout: layout)
        drawBursts(canvas, machine, frame: frame, fullWidth: fullWidth,
                   kinds: [.scoreboardDent, .windowBroken])

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
                let x = frame.x(entry.point.xFeet).rounded()
                let y = frame.y(entry.point.yFeet).rounded()
                canvas.rect(x - r, y, r * 2 + 1, 1, Palette.chalk)
                canvas.rect(x, y - r, 1, r * 2 + 1, Palette.chalk)
                canvas.px(x - r + 1, y - r + 1, Palette.chalk)
                canvas.px(x + r - 1, y - r + 1, Palette.chalk)
                canvas.px(x - r + 1, y + r - 1, Palette.chalk)
                canvas.px(x + r - 1, y + r - 1, Palette.chalk)
            }
        }

        let wallX = frame.x(machine.park.wallDistanceFeet)
        let wallH = machine.park.wallHeightFeet * frame.scale
        // On the wall when it is tall enough to carry a 5 px face, above it when it is not.
        let wallLabelY = wallH >= 11 ? frame.ground - wallH + 3 : frame.ground - wallH - 8
        // On an `ink` plate, which is what `ink` is for (docs/palette.md: "label backgrounds").
        // In the close camera the wall fills so much of the frame that `score` on `wall` was
        // hard to read, and against the crowd above it, worse (review nit, 2026-09-19).
        let label = "\(Int(machine.park.wallDistanceFeet))"
        canvas.rect(wallX + 5, wallLabelY - 1, Double(label.count) * 4 + 1, 7, Palette.ink)
        canvas.t3(wallX + 6, wallLabelY, label, Palette.score)
    }

    /// The bursts of whichever rare things have happened by now (#5). `DerbyMachine` says what
    /// happened and how long ago — off its own clocks, never a timer in a scene — and
    /// `DerbyCore.RareEvents` says where every speck is; this only picks the place out of the
    /// event and hands it over. The sky's events are in screen space and the field's in feet,
    /// because that is where the things they happened to are.
    private func drawBursts(_ canvas: PixelCanvas, _ machine: DerbyMachine,
                            frame: SideView, fullWidth: Double, kinds: Set<ParkEventKind>) {
        for (i, event) in machine.parkEvents.enumerated() where kinds.contains(event.kind) {
            guard let since = machine.secondsSince(event) else { continue }
            let x: Double, y: Double
            switch event.place {
            case let .sky(xFraction, skyY):
                x = (xFraction * fullWidth).rounded()
                y = skyY.rounded()
            case let .field(xFeet, yFeet):
                x = frame.x(xFeet).rounded()
                y = frame.y(yFeet).rounded()
            }
            SkyArt.burst(into: canvas, kind: event.kind,
                         seed: UInt64(machine.park.number) &* 0x9E37_79B9 &+ UInt64(i + 1),
                         since: since, at: x, y: y, rules: machine.rareEventRules)
        }
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

    // MARK: - The replay clip's trigger (#4)

    /// How long a finger stays down on the landing number to ask for a clip. Long enough that no
    /// stray touch fires it, short enough to fit twice inside `Timings.resultHold` (1.30 s).
    /// Claude's, unreviewed (DESIGN.md §19).
    private let longPressSeconds = 0.35
    private var pressStartedAt: TimeInterval?
    private var pressHasFired = false

    /// The whole trigger: no button and no target, because for 1.30 s the landing number is the
    /// only thing on the screen. The press has to mature *during* the hold, so this watches the
    /// clock rather than waiting for the finger to lift — a finger still down when the hold ends
    /// would otherwise never be answered.
    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        guard controller?.canShareLastHomeRun == true else {
            pressStartedAt = nil                // the hold is over: a half-made press is dropped
            return
        }
        guard let started = pressStartedAt, !pressHasFired,
              currentTime - started >= longPressSeconds else { return }
        pressHasFired = true
        controller?.shareLastHomeRunClip()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard controller?.canShareLastHomeRun == true else { return }
        pressStartedAt = CACurrentMediaTime()
        pressHasFired = false
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        pressStartedAt = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        pressStartedAt = nil
    }
}
