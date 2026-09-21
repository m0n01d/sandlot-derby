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

    /// Where the result hold's two new lines sit, in design units. The hold's existing lines are
    /// the landing number (52), `HR` (88), `OFF THE WALL` (90), a coaching word (102),
    /// `STREAK n` (116) and `CALLED UP` (134); these two take the gap under the number and the
    /// clear band under `CALLED UP`, above the wide camera's ground line at 176.
    /// (App) — pure layout, no gameplay effect.
    private let parkProgressY = 76.0
    private let recordY = 152.0
    private let recordNameY = 164.0
    private let holdTextScale = 2
    /// Everything behind the wall that does not move, drawn once per park, canvas and framing
    /// (DESIGN.md §17, §20). Two framings' worth at a time: the wide and the close set are built
    /// together at the head of a flight, so the cut between them costs nothing but a pointer.
    private let backdrops = FlightBackdropCache()
    /// `Park.scenery` is computed; this keeps the one the frame needs instead of rebuilding it.
    private var cachedScenery: Scenery?
    /// The flight camera's own knobs (§20 step 4).
    private let flightRules = FlightLookRules.standard

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
        let look = Look.of(machine.phase)
        let H = 224.0
        let fullWidth = Double(canvas.width)
        let (frame, camera) = framing(machine, width: fullWidth)
        let ground = frame.ground
        let close = camera == .close

        let scenery = self.scenery(for: machine.park)
        let layers = self.layers(machine, camera: camera, frame: frame, look: look,
                                 scenery: scenery, canvas: canvas)
        // The layers are drawn with the ground at its canonical place; the close camera drops it.
        let backdropDY = Int((ground - BackdropLayout.canonicalGround).rounded())

        layers.sky.blitOpaque(onto: canvas)

        // §17's draw order, from the back: sky → stars / moon → light halos → clouds →
        // fireworks → birds → towers → field and wall face → trail and ball → stands and
        // crowd → text. Everything that moves reads one clock, the machine's own.
        let now = SceneryClock.now(machine)
        // Every park stands towers in every phase (see `AtBatScene`, and §20's open question 1,
        // decided — Dwight, 2026-09-21). `sideTowerFrames` folds `lampsOn` into `lit` for every
        // bank, so by day each one draws dark and none of them can be chasing. `isOut` needs no
        // such fold: `RareEvents.detect` only ever puts a bank out while `lampsOn` is true (Core,
        // unchanged), so `machine.bankIsOut` already answers false for all of them by day.
        let towers = SkyArt.sideTowerFrames(park: machine.park, scenery: scenery,
                                            scale: frame.scale, originX: frame.originX,
                                            ground: ground, time: now,
                                            chasing: machine.crowdIsUp, lampsOn: machine.lampsOn,
                                            isOut: machine.bankIsOut, layout: layout)
        if machine.lampsOn {
            // The moon hangs in this camera too, where §20 puts it: never moving, whatever the
            // ground does. `nightSky` draws it with the stars and the halos — lamps-only, so the
            // gate stays here rather than inside `nightSky` itself.
            SkyArt.nightSky(into: canvas, scenery: scenery, towers: towers,
                            time: now, width: fullWidth, look: look, layout: layout)
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
                    width: fullWidth, look: look)

        drawFireworks(canvas, machine, fullWidth: fullWidth, look: look)

        SkyArt.birds(into: canvas, scenery: scenery, view: .side, time: now,
                     width: fullWidth, look: look,
                     skipping: machine.struckBird)
        if machine.showsMilestones {
            SkyArt.blimp(into: canvas, scenery: scenery, view: .side, time: now,
                         width: fullWidth, look: look, layout: layout)
        }
        // Feathers, where the ball went through something (#5). In the sky, with the thing it
        // happened to, and before the field goes in on top.
        drawBursts(canvas, machine, frame: frame, fullWidth: fullWidth,
                   kinds: [.birdStrike, .blimpHit])

        layers.behind.blit(onto: canvas, dy: backdropDY)

        // The lattices came down with `behind`, under the roof; only the banks are drawn here,
        // because a bank is the part of a tower the chase moves (§20 "Towers"). Their feet are
        // covered when the stands go in, as they always were.
        SkyArt.towerBanks(into: canvas, frames: towers, width: fullWidth, look: look, layout: layout)
        // …and the sparks off a bank that has just gone out, over the bank they came from.
        drawBursts(canvas, machine, frame: frame, fullWidth: fullWidth, kinds: [.lightsOut])

        // The field, under the ball and moving with the ground, so it is drawn per frame: the
        // mow in three depth bands, the low sun's rake across it, and the marks (§20 step 4).
        FlightArt.grass(into: canvas, view: frame, width: fullWidth, look: look, rules: flightRules)
        FlightArt.lowSunWash(into: canvas, view: frame, width: fullWidth, look: look,
                             rules: flightRules)
        FlightArt.fieldMarks(into: canvas, park: machine.park, view: frame, width: fullWidth,
                             close: close, look: look, rules: flightRules)
        FlightArt.batter(into: canvas, view: frame, look: look, rules: flightRules)

        if let flightResult = machine.flight, !flightResult.points.isEmpty {
            let points = flightResult.points
            let i = min(points.count - 1, Int(machine.playbackIndex))
            FlightArt.trail(into: canvas, points: points, index: i, view: frame, close: close,
                            rules: flightRules)
            let b = points[i]
            let X = frame.x(b.xFeet), Y = frame.y(b.yFeet) - flightRules.ballLift
            FlightArt.ball(into: canvas, at: b, view: frame, close: close, look: look,
                           rules: flightRules)

            drawInFrontOfTheBall(canvas, layers: layers, dy: backdropDY, close: close,
                                 machine: machine, frame: frame, scenery: scenery, look: look)

            if let launch = machine.launch {
                canvas.t3(8, 8, "\(Int(launch.exitVelocityMPH.rounded())) MPH", Palette.score,
                          scale: 2, shadow: Palette.ink)
                canvas.t3(8, 20, "\(Int(launch.launchAngleDegrees.rounded())) DEG", Palette.score,
                          scale: 2, shadow: Palette.ink)
            }
            canvas.t3(8, 34, machine.pitch.type.name, Palette.chalk, shadow: Palette.ink)

            if machine.beat == .flight {
                let d = Int(min(b.xFeet, flightResult.distanceFeet).rounded())
                canvas.t3(min(fullWidth - 30, X + 6), max(6, Y - 10), "\(d) FT", Palette.chalk,
                          shadow: Palette.ink)
            }
            if machine.beat == .result {
                let d = Int(flightResult.distanceFeet.rounded())
                let distanceText = "\(d) FT"
                // The same two-frame blink `HR` and `CALLED UP` already step at (§9's motion
                // budget, §17: two frames, no alpha). A record flashes the landing number
                // between `score` and `chalk` on the off beat, so the number is never gone —
                // only its colour changes, and the words come and go against it (#41).
                let blink = Int(machine.elapsed * 6) % 2 == 0
                let record = machine.recordNow
                let numberColour = record == nil ? Palette.score : (blink ? Palette.chalk : Palette.score)
                canvas.t5(fullWidth / 2 - Double(distanceText.count) * 6 * 3 / 2 + 3, 52,
                          distanceText, numberColour, scale: 3, shadow: Palette.ink)
                drawParkProgress(canvas, machine, flight: flightResult, fullWidth: fullWidth)
                if flightResult.homeRun, blink {
                    canvas.t5(fullWidth / 2 - 6 * 3, 88, "HR", look.red[2], scale: 3, shadow: Palette.ink)
                }
                // `streakNow`: the Warm Up's streak while one is live, the career's otherwise.
                if flightResult.homeRun, machine.streakNow >= 2 {
                    let streak = "STREAK \(machine.streakNow)"
                    canvas.t3(fullWidth / 2 - Double(streak.count) * 4, 116, streak, Palette.score,
                              scale: 2, shadow: Palette.ink)
                }
                if flightResult.wallHit {
                    canvas.t3(fullWidth / 2 - 30, 90, "OFF THE WALL", Palette.chalk, shadow: Palette.ink)
                }
                // Minors only: one word on a ball that stayed in (DerbyMachine.coachingWord).
                if let word = machine.coachingWord {
                    canvas.t3(fullWidth / 2 - Double(word.count) * 4, 102, word, Palette.chalk,
                              scale: 2, shadow: Palette.ink)
                }
                // Once per career, on the home run that clears Triple-A.
                if machine.isBeingCalledUp, !blink {
                    // The 5×7 face only has digits and F T H R, so this is the 3×5 at 3×.
                    canvas.t3(fullWidth / 2 - 9 * 4 * 3 / 2, 134, "CALLED UP", Palette.score,
                              scale: 3, shadow: Palette.ink)
                }
                // A career number just fell (#41). Below everything else the hold draws, so it
                // can never collide with `HR`, `STREAK n`, `OFF THE WALL`, a coaching word,
                // `HR 2 OF 3` or `CALLED UP` — and above the ground line at 176.
                if let record, blink {
                    centred(canvas, "NEW RECORD", y: recordY, fullWidth: fullWidth, Palette.score)
                    centred(canvas, record.name, y: recordNameY, fullWidth: fullWidth, Palette.chalk)
                }
            }
        } else {
            drawInFrontOfTheBall(canvas, layers: layers, dy: backdropDY, close: close,
                                 machine: machine, frame: frame, scenery: scenery, look: look)
        }

        // The same word the outfield scoreboard carries: during a Warm Up this is the day's
        // park, not a park anyone is trying to clear, and its number is a date (DESIGN.md §18).
        let parkName = machine.warmUp == nil ? machine.park.displayName : "WARM UP"
        canvas.t3(fullWidth - 10 - Double(parkName.count) * 4, H - 12, parkName, Palette.chalk,
                  shadow: Palette.ink)

        // The instant replay's camera, top right — the same corner and the same picture the
        // at-bat view carries, so it does not move across the cut (#42).
        if controller?.showsReplayIcon == true {
            ReplayIcon.draw(into: canvas, safeRight: safeRight, layout: replayIcon)
        }
    }

    /// Which home run of this park's count that was (#40): `HR 2 OF 3` on the way, and
    /// `PARK CLEARED` on the one that makes it. Home runs only — the count does not move for
    /// anything else — and never during a Warm Up, whose ten clear nothing (DESIGN.md §18).
    ///
    /// The 5×7 face has no `O`, `P`, `C` or `D`, so this is the 3×5 at 2×, exactly as
    /// `CALLED UP` below is the 3×5 at 3× for the same reason.
    private func drawParkProgress(_ canvas: PixelCanvas, _ machine: DerbyMachine,
                                  flight: FlightResult, fullWidth: Double) {
        guard flight.homeRun, machine.warmUp == nil else { return }
        let text = machine.clearsTheParkNow
            ? "PARK CLEARED"
            : "HR \(machine.homeRunsThisPark) OF \(machine.homeRunsToClearPark)"
        centred(canvas, text, y: parkProgressY, fullWidth: fullWidth, Palette.score)
    }

    /// One line of the 3×5 face at `holdTextScale`, centred on the canvas. The last glyph has no
    /// gap after it, so the measured width is one scale short of `count × 4 × scale`.
    private func centred(_ canvas: PixelCanvas, _ text: String, y: Double, fullWidth: Double,
                         _ colour: Palette.RGBA8) {
        let width = Double(text.count * 4 * holdTextScale - holdTextScale)
        canvas.t3((fullWidth / 2 - width / 2).rounded(), y, text, colour, scale: holdTextScale,
                  shadow: Palette.ink)
    }

    /// This park's scenery, kept between frames: `Park.scenery` is a pure function and builds
    /// its cloud stamps fresh every time it is asked.
    private func scenery(for park: Park) -> Scenery {
        if let s = cachedScenery, s.parkNumber == park.number { return s }
        let s = park.scenery
        cachedScenery = s
        return s
    }

    /// The six cached layers for the framing on screen — and, the first time a flight asks for
    /// them, the other framing's six as well.
    ///
    /// §20 asks for both to be painted during the contact freeze rather than at the cut, so that
    /// the wide → close cut is a hard cut and costs nothing. The machine hands this scene its
    /// first frame at the end of that freeze (`.cutToWide` leaves `.contact`), which is as early
    /// as a scene that is not on screen can do any work; the close set is then already standing
    /// when the ball reaches the wall. A flight that never earns the close camera never pays for
    /// it — `SideView.closeCutIndex` says so before a single pixel is drawn.
    private func layers(_ machine: DerbyMachine, camera: FlightCamera, frame: SideView,
                        look: Look, scenery: Scenery, canvas: PixelCanvas) -> FlightLayers {
        let mine = build(machine, camera: camera, frame: frame, look: look,
                         scenery: scenery, canvas: canvas)
        // Only while the wide camera is up, and only once per flight: `closeCutIndex` walks the
        // whole arc, which is not a per-frame question.
        guard camera == .wide, let flight = machine.flight, prebuiltFor != flight.distanceFeet
        else { return mine }
        prebuiltFor = flight.distanceFeet
        guard SideView.closeCutIndex(flight: flight,
                                     wallDistanceFeet: machine.park.wallDistanceFeet) != nil
        else { return mine }
        // The close framing drops the ground for a towering fly, but only the scale and the
        // origin are in the key, and neither of those moves once the flight is known.
        let other = SideView.framing(camera: .close, park: machine.park, flight: flight,
                                     ballFeet: 0, width: Double(canvas.width),
                                     safeLeft: safeLeft, safeRight: safeRight,
                                     rules: sideRules)
        _ = build(machine, camera: .close, frame: other, look: look,
                  scenery: scenery, canvas: canvas)
        return mine
    }

    /// The flight whose close layers are already standing, by its landing number — which is as
    /// good an identity as a flight has and changes on every swing that produces one.
    private var prebuiltFor: Double?

    /// One framing's six layers, painted if the cache has not seen this key before.
    private func build(_ machine: DerbyMachine, camera: FlightCamera, frame: SideView,
                       look: Look, scenery: Scenery, canvas: PixelCanvas) -> FlightLayers {
        let width = Double(canvas.width)
        let close = camera == .close
        // The layers are painted with the ground at its canonical place, whatever this frame's
        // ground is, and copied down by the difference. The close camera dropping the ground to
        // keep a towering fly in frame therefore costs no repaint.
        let view = SideView(scale: frame.scale, originX: frame.originX,
                            ground: BackdropLayout.canonicalGround)
        let key = BackdropKey(parkNumber: machine.park.number, width: canvas.width,
                              camera: close ? .close : .wide, phase: machine.phase,
                              scale: frame.scale, originX: frame.originX)
        return backdrops.layers(for: key, height: canvas.height) { set in
            // The stops, stretched to the canonical ground whichever framing this is: the sky is
            // infinitely far away and the close camera only exposes more of the last of them.
            SkyArt.sky(into: set.sky.canvas, look: look, width: width, flightCamera: true)
            // The low sun at `goldenHour` is a thing in the park, low behind the hills, so it
            // goes in `behind` and rides down with the ground. The moon does not move and stays
            // in the sky (§20 "Layers and speed").
            if let disc = look.sunFlight, look.sunFlightMovesWithGround {
                SkyArt.sunOrMoon(into: set.behind.canvas, look: look, x: disc.x(width: width),
                                 y: BackdropLayout.canonicalGround - disc.y,
                                 radius: disc.radius, halo: disc.halo,
                                 clipY: BackdropLayout.canonicalGround)
            }
            // The lattices belong in this layer, under the roof (§20 step 4), in every phase now
            // (§20 open question 1, decided) — only their geometry is wanted here, so `time`,
            // `chasing` and `lampsOn` are placeholders that `towerLattices` never reads.
            let poles = SkyArt.sideTowerFrames(park: machine.park, scenery: scenery,
                                               scale: frame.scale, originX: frame.originX,
                                               ground: BackdropLayout.canonicalGround,
                                               time: 0, chasing: false, lampsOn: false,
                                               layout: self.layout)
            FlightArt.behind(into: set.behind.canvas, park: machine.park, scenery: scenery,
                             view: view, width: width, close: close, look: look,
                             towers: poles, layout: self.layout, rules: self.flightRules)
            FlightArt.front(into: set.front.canvas, park: machine.park, scenery: scenery,
                            view: view, width: width, close: close, look: look,
                            layout: self.layout, rules: self.flightRules)
            for lift: FlightArt.CrowdLift in [.none, .even, .odd] {
                FlightArt.crowd(into: set.crowd(lift).canvas, park: machine.park,
                                scenery: scenery, view: view, width: width, close: close,
                                look: look, lift: lift, rules: self.flightRules)
            }
        }
    }

    /// The stands and their crowd, the pop where a home run went into them, and the wall's own
    /// number. §17's draw order puts the stands after the trail and the ball — which is what
    /// makes a home run drop into the crowd and be gone — and the text after everything.
    private func drawInFrontOfTheBall(_ canvas: PixelCanvas, layers: FlightLayers, dy: Int,
                                      close: Bool, machine: DerbyMachine, frame: SideView,
                                      scenery: Scenery, look: Look) {
        layers.front.blit(onto: canvas, dy: dy)

        // The crowd and the flags are the parts of the stands that move, so they are not in the
        // cached layer: the crowd bounces while the cheer plays (`DerbyMachine.crowdIsUp`) and
        // the flags flutter whatever the beat, because it is the wind that moves them.
        let now = SceneryClock.now(machine)
        let fullWidth = Double(canvas.width)
        // Three cached crowds, one drawn (§20 "Layers and speed"). `crowdHeadIsUp` of person 0
        // is the machine's own answer to "is this the even step or the odd one" — index 0 is
        // even, so it is true exactly on the steps the even people are up.
        let lift: FlightArt.CrowdLift = !machine.crowdIsUp
            ? .none
            : (SkyLife.crowdHeadIsUp(0, at: now, cheering: true) ? .even : .odd)
        layers.crowd(lift).blit(onto: canvas, dy: dy)
        // The roof's own shadow falls on the people under it, so it goes on after them.
        FlightArt.roofShadow(into: canvas, park: machine.park, scenery: scenery, view: frame,
                             width: fullWidth, close: close, look: look, rules: flightRules)
        BackdropArt.standsFlags(into: canvas, park: machine.park, scenery: scenery,
                                scale: frame.scale, originX: frame.originX, width: fullWidth,
                                ground: frame.ground, frame: SkyLife.flutterFrame(at: now),
                                close: close, look: look, layout: layout)

        // What this park already carries: dents that stay and a pane that has gone (#5). Over
        // the cached board, and with the shards of the shot on screen on top of them.
        BackdropArt.boardDamage(into: canvas, park: machine.park, scenery: scenery,
                                scars: machine.parkScars, scale: frame.scale,
                                originX: frame.originX, ground: frame.ground, look: look,
                                layout: layout)
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
    private func drawFireworks(_ canvas: PixelCanvas, _ machine: DerbyMachine, fullWidth: Double,
                               look: Look) {
        guard let show = machine.fireworks else { return }
        let particles = Fireworks.particles(show: show, at: machine.tally[.secondsPlayed], rules: machine.fireworksRules)
        for particle in particles where particle.visible {
            // §20: a firework colour has to differ from every sky stop between y 20 and y 110.
            // `sky3` was the one role that used to be a sky colour by definition; it becomes the
            // phase's lit stand lip, which is a pale tone in every line and is never a stop.
            let colour: Palette.RGBA8
            switch particle.colour {
            case .score: colour = Palette.score
            case .cap: colour = look.red[2]
            case .chalk: colour = Palette.chalk
            case .skin: colour = look.skin[2]
            case .sky3: colour = look.standLit[1]
            }
            let x = fullWidth * particle.x
            if particle.size >= 2 {
                canvas.rect(x, particle.y, 2, 2, colour)
            } else {
                canvas.px(x, particle.y, colour)
            }
        }
    }

    // MARK: - The replay's trigger (#42)

    /// Where the camera in the corner goes and how big its target is. A knob per #42; the same
    /// one the at-bat view uses, so the camera does not move across the cut.
    private let replayIcon = ReplayIconLayout.standard

    private var dragStart: CGPoint?
    private var dragLast: CGPoint?

    private func designPoint(for touch: UITouch) -> CGPoint {
        let p = touch.location(in: self)
        return CGPoint(x: p.x, y: size.height - p.y)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        dragStart = designPoint(for: touch)
        dragLast = dragStart
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        dragLast = designPoint(for: touch)
    }

    /// A tap on the camera and nothing else. There is nothing to swing at from this camera, so a
    /// touch that misses it does nothing at all — the same as it did before #42, when the only
    /// thing this scene listened for was a long press.
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer { dragStart = nil; dragLast = nil }
        guard controller?.showsReplayIcon == true, let start = dragStart else { return }
        let end = dragLast ?? start
        guard hypot(end.x - start.x, end.y - start.y) < replayIcon.tapSlack else { return }
        guard ReplayIcon.contains(Point(x: start.x, y: start.y), canvasWidth: Double(size.width),
                                  safeRight: safeRight, layout: replayIcon) else { return }
        controller?.showReplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        dragStart = nil
        dragLast = nil
    }
}
