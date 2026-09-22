import SpriteKit
import DerbyCore
import Foundation
import UIKit

/// The pitch camera: pitcher, batter, the ball coming at you, and the slice gesture. A port of
/// the prototype's `drawAtBat` + `drawLiveTrail` + `drawContact` + `drawMiss` plus its
/// `beginSlice`/`moveSlice`/`endSlice` input model (prototypes/03-camera-cut-and-slice.html
/// ~L286-420, ~L474-480). This scene owns no game state — `contactVisual`/`missVisual`/`trail`
/// below are draw-only caches of the last slice, exactly like the prototype's own `contact` /
/// `missInfo` / `trail` locals; every beat, timing and outcome decision comes from
/// `controller.machine`.
final class AtBatScene: CanvasScene {
    private struct SamplePoint { let point: Point; let time: CFTimeInterval }

    private struct ClosestMiss {
        let distance: Double
        let ball: BallSample
        let progress: Double
        let fingerPoint: Point
    }

    private struct ContactVisual {
        let ball: Point
        let radius: Double
        let dir: Point
        let angle: Double
        let power: Double
        let trailPoints: [Point]
        /// When each of those points was made, in seconds relative to this contact (zero or
        /// negative). Carried into the `Replay` so a lead-in can draw the stroke growing (#42).
        let trailTimes: [Double]
    }

    private struct MissVisual {
        let pressPoint: Point?
        let ball: Point
        let radius: Double
        let early: Bool
        let feetAway: Double
        let trailPoints: [Point]
        /// The swing angle of the missed stroke — `Contact.test`'s own formula, off the finger's
        /// drag. A called strike/ball has no finger swing to measure and defaults to 20°.
        let angle: Double
    }

    private var trail: [SamplePoint]?
    private var dragStart: Point?
    /// Whether a finger is on the glass right now, whatever beat this is or where it landed.
    /// Read by `GameController.tick(_:)`, once a frame, to mirror `DerbyMachine.sliceInProgress`
    /// (DESIGN.md §3, issue #20) — "a slice is in progress" means a finger is down, not that one
    /// happened to touch down while `.pitch` was already showing.
    ///
    /// Except a finger resting on the camera in the corner, which is not a swing and must not be
    /// answered as one when the pitch times out (#42). The moment it moves far enough to be a
    /// slice it counts as one, like any other finger.
    var fingerDown: Bool { dragStart != nil && !isReplayIconTouch }
    private var closest: ClosestMiss?
    private var contactVisual: ContactVisual?
    private var missVisual: MissVisual?
    private var fadeTrail: (points: [Point], time: CFTimeInterval)?
    private var trackedBeat: Beat = .windup

    private var xOffset: Double { (Double(size.width) - 320) / 2 }

    /// The foul lines, in the 320-wide design column (DESIGN.md §8): from the plate out to
    /// where each meets the base of the wall. The foul poles (#28) stand on top of the wall at
    /// the same two x's, so both read off these and can never drift apart.
    private let foulLineApexX = 160.0
    private let foulLineApexY = 196.0
    private let foulLineLeftX = 40.0
    private let foulLineRightX = 280.0
    private let foulLineWallY = 104.0

    /// The progress lamps on the outfield scoreboard: one per home run this park asks for, lit
    /// as each one lands (#40). To the right of `380 FT`, on its own line and centred on its cap
    /// height — the board's widest line is `SINGLE-A` at 32 px, so from 166 there is room for a
    /// count of five (166…189) inside the 64 px board. Sat over the board's top rule at first
    /// and read as part of the `2` in `280`. (App) — pure layout, no gameplay effect.
    private let progressLampX = 166.0
    private let progressLampY = 85.0
    private let progressLampSize = 3.0
    private let progressLampGap = 2.0

    private let layout = BackdropLayout.standard
    private let atBatLook = AtBatLookRules.standard
    /// The horizon above the wall, drawn once per park and canvas and copied after that
    /// (DESIGN.md §17). Only the clouds are redrawn per frame.
    private let backdrops = BackdropCache()
    private var cachedScenery: Scenery?

    /// The people, built once for each pose and hour and stamped after that, with the shapes of
    /// their cast shadows beside them (§20 "Layers and speed").
    private let people = ShadedSpriteCache()
    private let shadows = ShadowStampCache()

    /// This park's scenery, kept between frames: `Park.scenery` is a pure function and builds
    /// its cloud stamps fresh every time it is asked.
    private func scenery(for park: Park) -> Scenery {
        if let s = cachedScenery, s.parkNumber == park.number { return s }
        let s = park.scenery
        cachedScenery = s
        return s
    }

    // MARK: - Drawing

    override func render(into canvas: PixelCanvas) {
        guard let machine = renderMachine else { return }

        // A replay scene has no controller and no input: its beats are already decided, and its
        // `contactVisual` was restored from the record before the first frame.
        if machine.beat != trackedBeat {
            if let controller { handleBeatChange(to: machine.beat, controller: controller) }
            trackedBeat = machine.beat
        }
        #if DEBUG
        if Self.autoSlice, !isOffScreen, machine.beat == .pitch, machine.pitchProgress >= 0.97 { devSlice() }
        #endif

        let look = Look.of(machine.phase)
        let W = 320.0, H = 224.0
        let fullWidth = Double(canvas.width)
        let xOff = xOffset
        func wx(_ x: Double) -> Double { x + xOff }

        // The sky and the horizon (DESIGN.md §17, §20). Both sit above y = 96; the strike zone
        // starts at y = 136, so nothing new here moves anywhere near it.
        let scenery = self.scenery(for: machine.park)
        let now = SceneryClock.now(machine)

        // Three cached layers: the sky, what is behind the field, and what goes in front of the
        // ball (§20 "Layers and speed"). Redrawn when the park, the canvas or the phase changes
        // and copied the rest of the time.
        let layers = backdrops.layers(
            for: BackdropKey(parkNumber: machine.park.number, width: canvas.width, camera: .atBat,
                             phase: machine.phase),
            height: canvas.height) { sky, behind, front in
            SkyArt.sky(into: sky.canvas, look: look, width: fullWidth, flightCamera: false)
            // The sun goes in the sky layer with the stops: it is not a thing in the park and
            // nothing about the at-bat camera ever moves it. The moon is the park's and is drawn
            // with the stars instead, because a park that has no moon must show none.
            if let disc = look.sunAtBat, !look.sunIsMoon {
                SkyArt.sunOrMoon(into: sky.canvas, look: look, x: disc.x(width: fullWidth),
                                 y: disc.y, radius: disc.radius, halo: disc.halo)
            }
            // `behind`: the hills, the trees, and — in a park with no stand to hide them —
            // §17's own two pieces on the horizon (§20 "Layers and speed").
            AtBatArt.horizon(into: behind.canvas, park: machine.park, scenery: scenery,
                             look: look, width: fullWidth, xOffset: xOff,
                             layout: self.layout, rules: self.atBatLook)

            // `front`: everything from the stands down. It goes in over the ball's sky and under
            // the people, and none of it moves — not even the crowd, which at bat does not bounce.
            let f = front.canvas
            AtBatArt.stands(into: f, park: machine.park, scenery: scenery, look: look,
                            width: fullWidth, xOffset: xOff, layout: self.layout,
                            rules: self.atBatLook)
            // The foul poles stand in front of the wings and behind everything on the field
            // (#28). Off the same two x's the foul lines are drawn from, so they stay married
            // however wide the canvas is.
            BackdropArt.atBatFoulPoles(into: f, league: machine.park.league,
                                       xs: [xOff + self.foulLineLeftX, xOff + self.foulLineRightX],
                                       look: look, layout: self.layout)
            AtBatArt.field(into: f, look: look, width: fullWidth, xOffset: xOff,
                           rules: self.atBatLook)
            AtBatArt.lowSun(into: f, look: look, width: fullWidth, rules: self.atBatLook)
            AtBatArt.nightPool(into: f, look: look, width: fullWidth, rules: self.atBatLook)
            AtBatArt.scoreboardFrame(into: f, look: look, xOffset: xOff, rules: self.atBatLook)
            AtBatArt.dirtAndChalk(into: f, scenery: scenery, look: look, xOffset: xOff,
                                  foulLines: (apex: (x: xOff + self.foulLineApexX,
                                                     y: self.foulLineApexY),
                                              left: xOff + self.foulLineLeftX,
                                              right: xOff + self.foulLineRightX,
                                              wallY: self.foulLineWallY),
                                  rules: self.atBatLook)
            // The mist lies on top of all of it and behind the pitcher — `dawn` only.
            AtBatArt.mist(into: f, look: look, width: fullWidth)
        }
        layers.sky.blitOpaque(onto: canvas)
        // Every park stands towers in every phase (§20 "What the clock replaces"; §20 open
        // question 1, decided — Dwight, 2026-09-21: the towers stand by day too, dark until the
        // lamps come on). The clock only decides whether a bank is *lit* — `atBatTowerFrames`
        // folds `lampsOn` into `lit` for every bank at once, so the lattice and a dark bank still
        // draw below whatever the hour.
        let towers = SkyArt.atBatTowerFrames(scenery: scenery, xOffset: xOff, time: now,
                                             chasing: machine.crowdIsUp,
                                             lampsOn: machine.lampsOn, layout: layout)
        // Stars, the moon and a bank's halo stay lamps-only: nothing new here to draw by day, and
        // `nightSky` only narrows its star count at `twilight` — it does not know to hide them
        // itself, so the gate has to stay here.
        if machine.lampsOn {
            SkyArt.nightSky(into: canvas, scenery: scenery, towers: towers,
                            time: now, width: fullWidth, look: look, layout: layout)
        }
        // Things a long career arrives at, never announced (#5). The at-bat sky is where a
        // player spends most of their time, so the blimp and the comet cross it too — with
        // their own seeds, like the birds, because you are looking the other way down the park.
        // The searchlights are not here: they rise from behind the stands, which is behind you.
        // A Warm Up is played in a park numbered by the day, which would clear every threshold
        // there is by accident, so its ten see none of them (DESIGN.md §18).
        if machine.showsMilestones {
            SkyArt.comet(into: canvas, scenery: scenery, view: .atBat, time: now, width: fullWidth)
        }
        Clouds.draw(into: canvas, clouds: scenery.atBatClouds,
                    breeze: scenery.breezePixelsPerSecond,
                    seconds: now,
                    width: fullWidth, look: look)
        SkyArt.birds(into: canvas, scenery: scenery, view: .atBat, time: now,
                     width: fullWidth, look: look)
        if machine.showsMilestones {
            SkyArt.blimp(into: canvas, scenery: scenery, view: .atBat, time: now,
                         width: fullWidth, look: look, layout: layout)
        }
        layers.behind.blit(onto: canvas)

        // The towers flank the scoreboard, standing on the wall band. The stands go in on top of
        // them next and cover their feet, so what is left is a bank floating over the roof.
        SkyArt.towers(into: canvas, frames: towers, width: fullWidth, look: look, layout: layout)

        // The stands, the wall, the track, the grass, the dirt and the chalk, in one copy.
        layers.front.blit(onto: canvas)

        // Everything else is the 320-wide prototype column, centred.
        canvas.t3(wx(134), 84, "\(Int(machine.park.wallDistanceFeet)) FT", Palette.score)
        // The outfield scoreboard says where you are — or that these ten are not the career
        // (DESIGN.md §18). Same board, same place, one word swapped.
        canvas.t3(wx(134), 91, machine.warmUp == nil ? machine.park.displayName : "WARM UP", Palette.chalk)
        drawProgressLamps(canvas: canvas, wx: wx, machine: machine, look: look)

        // The two little flags on the scoreboard, fluttering in two frames (§17, step 5).
        BackdropArt.scoreboardFlags(into: canvas, scenery: scenery, xOffset: xOff,
                                    frame: SkyLife.flutterFrame(at: now), look: look, layout: layout)

        // The two figures, each with its cast shadow laid on the ground first. The pitcher
        // stands where he always has, on the mound at (160, 117); the batter's back foot — his
        // right, the near one — is at (106, 214), inside his box (Dwight, 2026-09-22).
        let table = PeopleArt.shadowTable(look: look)
        let pitcherPose = self.pitcherPose(beat: machine.beat, elapsed: machine.elapsed)
        drawFigure(canvas: canvas, name: "pitcher", pose: pitcherPose, phase: machine.phase,
                   look: look, x: wx(pitcherX), y: pitcherY, table: table,
                   // The mound is eight pixels across, so his shadow softens far sooner than a
                   // figure standing on the open grass (`golden.at_bat`).
                   shadows: look.shadows.map {
                       Look.Shadow(slope: $0.slope, rise: $0.rise,
                                   softFrom: PeopleRules.standard.pitcherShadowSoftFrom)
                   }) { PeopleArt.pitcher(pose: pitcherPose, look: look) }

        let z = machine.pitchingRules.strikeZone
        var zi = 0.0
        while zi <= z.width {
            canvas.px(wx(z.x + zi), z.y, Palette.chalk)
            canvas.px(wx(z.x + zi), z.y + z.height, Palette.chalk)
            zi += 3
        }
        var zj = 0.0
        while zj <= z.height {
            canvas.px(wx(z.x), z.y + zj, Palette.chalk)
            canvas.px(wx(z.x + z.width), z.y + zj, Palette.chalk)
            zj += 3
        }

        drawMinorLeagueHelp(canvas: canvas, wx: wx, machine: machine)

        // The distance the finger has dragged since it went down, however that drag is going to
        // resolve — the same measure `.pitch` asks for the mid-swing pose (DESIGN.md, batter
        // rig, Dwight 2026-09-22). In a replay's lead-in there is no finger: the recorded stroke
        // grows through `replayStroke` instead, and it has to move the batter the same way, or
        // the clip shows him frozen in his stance while his own stroke crosses the screen (§19).
        let fingerTravel: Double = {
            if let replayStroke, let first = replayStroke.first, let last = replayStroke.last {
                return hypot(last.x - first.x, last.y - first.y)
            }
            guard let dragStart, let last = trail?.last?.point else { return 0 }
            return hypot(last.x - dragStart.x, last.y - dragStart.y)
        }()
        let strokeUnderway = fingerDown || replayStroke != nil
        let batterFrame: BatterFrame
        switch machine.beat {
        case .contact:
            batterFrame = .contact(angleDegrees: contactVisual?.angle ?? 20)
        case .miss where machine.lastCall == .miss:
            batterFrame = .finish(angleDegrees: missVisual?.angle ?? 20)
        case .pitch where strokeUnderway && fingerTravel >= PeopleRules.standard.swingFrameAfterPixels:
            batterFrame = .swing
        default:
            batterFrame = .stance
        }
        let batterPose = batterFrame.pose
        drawFigure(canvas: canvas, name: "batter", pose: batterFrame.cacheID, phase: machine.phase,
                   look: look, x: wx(batterX), y: batterY, table: table,
                   shadows: look.shadows,
                   groundRise: (x0: batterPose.ankleR.x, x1: batterPose.ankleL.x,
                                rise: batterPose.ankleR.y - batterPose.ankleL.y)) {
            PeopleArt.batter(frame: batterFrame, look: look)
        }

        switch machine.beat {
        case .pitch:
            let b = machine.ballNow
            drawBall(canvas: canvas, x: wx(b.x), y: b.y, radius: b.radius, look: look)
            canvas.t3(wx(8), H - 12, "\(Int(machine.pitch.speedMPH.rounded())) MPH", Palette.chalk,
                      shadow: Palette.ink)
        case .contact:
            drawContactVisual(canvas: canvas, wx: wx, elapsed: machine.elapsed,
                              isBarrel: machine.isBarrelNow, zone: z, look: look)
        case .miss:
            drawMissVisual(canvas: canvas, wx: wx, elapsed: machine.elapsed)
            let label = callWord(machine.lastCall)
            let labelY = (missVisual?.early ?? false) ? 164.0 : 118.0
            canvas.t3(wx(W / 2 - Double(label.count) * 4), labelY, label, Palette.score, scale: 2,
                      shadow: Palette.ink)
            canvas.t3(wx(8), H - 12, "\(machine.pitch.type.name) \(Int(machine.pitch.speedMPH.rounded())) MPH",
                      Palette.chalk, shadow: Palette.ink)
        default:
            break
        }

        // HUD anchors to the true edges of the canvas, not the centred column.
        // The headline: where you are and what it has cost (DESIGN.md §10).
        if let run = machine.warmUp {
            // Where the career's cost would be, the day's count instead: the Warm Up has no
            // cost, and the only thing worth knowing is how many are left (DESIGN.md §18).
            canvas.t3(8, 8, "WARM UP · \(run.spent)/\(run.total)", Palette.chalk, shadow: Palette.ink)
        } else {
            let pitches = machine.tally.pitches
            canvas.t3(8, 8, "\(machine.park.displayName)  \(pitches) \(pitches == 1 ? "PITCH" : "PITCHES")",
                      Palette.chalk, shadow: Palette.ink)
        }
        // Not during the contact freeze: the tally already knows how the ball lands, and a
        // streak line appearing or vanishing here would spoil the cut. `streakNow` so the line
        // follows whichever streak is live.
        if machine.streakNow >= 2, machine.beat != .contact {
            canvas.t3(8, 16, "HR STREAK \(machine.streakNow)", Palette.score, shadow: Palette.ink)
        }

        // The instant replay's camera, top right, when there is a swing worth seeing again (#42).
        if controller?.showsReplayIcon == true {
            ReplayIcon.draw(into: canvas, safeRight: safeRight, layout: replayIcon)
        }

        drawLiveTrail(canvas: canvas, wx: wx)
    }

    /// How many home runs this park still wants, as lamps on its own scoreboard (#40): one per
    /// home run the count asks for, lit in `score` as each lands and dark in `ink` until it does.
    /// No number and no word — the board is a board, and three lamps of which two are lit is the
    /// whole sentence.
    ///
    /// Nothing during a Warm Up: those ten are played in the day's park and clear nothing
    /// (DESIGN.md §18), so a row of lamps there would be a promise the day cannot keep.
    private func drawProgressLamps(canvas: PixelCanvas, wx: (Double) -> Double,
                                   machine: DerbyMachine, look: Look) {
        guard machine.warmUp == nil else { return }
        let lit = machine.homeRunsThisPark
        for i in 0..<machine.homeRunsToClearPark {
            let x = wx(progressLampX + Double(i) * (progressLampSize + progressLampGap))
            canvas.rect(x, progressLampY, progressLampSize, progressLampSize,
                        i < lit ? Palette.score : look.board[0])
        }
    }

    /// The help a minor-league `Rung` gives (DESIGN.md §10). No words: a line for *where and
    /// which way*, a closing ring for *when*. Both sit on the pitch's target, which the minors
    /// give away before the throw on purpose.
    private func drawMinorLeagueHelp(canvas: PixelCanvas, wx: (Double) -> Double, machine: DerbyMachine) {
        guard let rung = machine.rung, machine.beat == .windup || machine.beat == .pitch else { return }
        let t = machine.pitch.target

        if rung.swingGuide {
            let a = machine.ladder.guideAngleDegrees * Double.pi / 180
            let dx = cos(a), dy = -sin(a), reach = 34.0
            let tipX = t.x + dx * reach, tipY = t.y + dy * reach
            var d = -reach                                    // 4 px on, 4 px off, 2 px thick
            while d < reach {
                canvas.line(wx(t.x + dx * d), t.y + dy * d, wx(t.x + dx * (d + 4)), t.y + dy * (d + 4),
                            Palette.chalk, thickness: 2)
                d += 8
            }
            for wing in [-0.5, 0.5] {                         // arrowhead: slice up and through
                let b = a + Double.pi + wing
                canvas.line(wx(tipX), tipY, wx(tipX + cos(b) * 9), tipY - sin(b) * 9, Palette.chalk, thickness: 2)
            }
        }

        if rung.timingRing {
            canvas.ring(wx(t.x), t.y, 5, Palette.chalk, gap: 2)
            if machine.beat == .pitch {
                let remaining = max(0, 1 - machine.pitchProgress)
                canvas.ring(wx(t.x), t.y, 5 + remaining * 30, Palette.score)
            }
        }
    }

    /// Where the two of them stand, deliberately named: the hit test and the pitch's own
    /// geometry are measured against these. The pitcher is unchanged since the prototype; the
    /// batter moved into his box (Dwight, 2026-09-22) — `batterX`/`batterY` is now the sole of
    /// his BACK foot (his right, the near one), not a point between his two feet.
    private let pitcherX = 160.0
    private let pitcherY = 117.0
    private let batterX = 106.0
    private let batterY = 214.0

    /// Three frames on the windup clock — `elapsed`/`beat`, no state of its own — set, leg
    /// kick/reach back, release (DESIGN.md §3, §9). The third, `.set`, was the one never built
    /// (issue #20): before it, the windup's first 40% and everything past `.pitch` shared the
    /// release silhouette, so the wind-up never had a calm beat to kick off from.
    private func pitcherPose(beat: Beat, elapsed: Double) -> Int {
        guard beat == .windup else { return 2 }
        let windup = min(1, elapsed / 0.5)
        if windup <= 0.4 { return 0 }          // set: feet together, hands tucked in
        if windup < 0.9 { return 1 }           // the leg kick and the reach back
        return 2                               // release, and held on past it
    }

    /// One figure and the shadow it throws: the stamp and the shadow's shape are built the first
    /// time this pose comes up at this hour and kept after that (§20 "Layers and speed"), so a
    /// frame is two copies and a walk over a few hundred ground pixels.
    private func drawFigure(canvas: PixelCanvas, name: String, pose: Int, phase: DayPhase,
                            look: Look, x: Double, y: Double,
                            table: [UInt32: Palette.RGBA8], shadows: [Look.Shadow],
                            groundRise: (x0: Double, x1: Double, rise: Double)? = nil,
                            build: () -> ShadedSprite) {
        let sprite = people.sprite(name, pose: pose, phase: phase, build: build)
        let stamp = shadows.isEmpty ? nil : self.shadows.stamp(name, pose: pose, phase: phase) {
            PeopleArt.shadowStamp(for: sprite, shadows: shadows, groundRise: groundRise)
        }
        if let stamp {
            PeopleArt.cast(stamp, into: canvas, footX: x, footY: y, table: table)
        }
        sprite.blit(onto: canvas, x: Int(x), y: Int(y))
    }

    /// The ball: `chalk` with its red laces, one highlight pixel where the light catches it and
    /// three on the underside, so it reads as a sphere rather than a dot (§20 "Ball").
    private func drawBall(canvas: PixelCanvas, x: Double, y: Double, radius: Double, look: Look) {
        canvas.baseball(x, y, radius: radius, highlight: look.ballHi)
        guard radius >= 2 else { return }
        let bx = x.rounded(.down), by = y.rounded(.down)
        for (fx, fy) in [(0.67, 0.67), (0.33, 1.0), (1.0, 0.33)] {
            canvas.px(bx + radius * fx, by + radius * fy, look.ballLo)
        }
    }

    private func drawContactVisual(canvas: PixelCanvas, wx: (Double) -> Double, elapsed: Double,
                                    isBarrel: Bool, zone: Rect, look: Look) {
        guard let c = contactVisual else { return }
        drawTrail(canvas: canvas, wx: wx, points: c.trailPoints, color: Palette.chalk, core: nil, thickness: 1)
        let x0 = c.ball.x - c.dir.x * 16, y0 = c.ball.y - c.dir.y * 16
        let x1 = c.ball.x + c.dir.x * 16, y1 = c.ball.y + c.dir.y * 16
        canvas.line(wx(x0), y0, wx(x1), y1, Palette.chalk, thickness: 3)
        canvas.line(wx(x0), y0, wx(x1), y1, Palette.score, thickness: 1)
        canvas.baseball(wx(c.ball.x), c.ball.y, radius: max(2, c.radius), highlight: look.ballHi)
        for a in 0..<8 {
            let ang = Double(a) / 8 * 2 * Double.pi + 0.39
            let l = (a % 2 == 1 ? 4.0 : 8.0) + min(8, elapsed * 40)
            canvas.line(wx(c.ball.x + cos(ang) * 10), c.ball.y + sin(ang) * 10,
                        wx(c.ball.x + cos(ang) * (10 + l)), c.ball.y + sin(ang) * (10 + l),
                        Palette.chalk, thickness: 1)
        }
        let label = "SWING \(Int(c.angle.rounded()))  POWER \(Int((c.power * 100).rounded()))"
        let lx = max(4, min(320 - Double(label.count) * 4 - 4, c.ball.x - Double(label.count) * 2))
        let ly = max(4, min(224 - 24, c.ball.y + 18))
        canvas.rect(wx(lx - 2), ly - 2, Double(label.count) * 4 + 3, 9, Palette.ink)
        canvas.t3(wx(lx), ly, label, Palette.score)

        if isBarrel {
            // BARREL, next to the SWING/POWER readout, in the chunkier 5×7 face (StatRules.isBarrel,
            // DESIGN.md §3, issue #20). Anchored under the readout and pinned below the strike zone,
            // so it never sits over the ball, the slash or the zone. Static, not blinking: the
            // contact freeze is only 0.22–0.50 s (`Timings.contactHoldWeak`…`contactHoldBarrel`),
            // too short for a blink to read inside the §9 motion budget. Decision, Claude's,
            // 2026-09-19, unreviewed.
            let barrelLabel = "BARREL"
            let bw = Double(barrelLabel.count) * 6
            let blx = max(4, min(320 - bw - 4, c.ball.x - bw / 2))
            let bly = min(224 - 11, max(zone.y + zone.height + 6, ly + 12))
            canvas.rect(wx(blx - 2), bly - 2, bw + 3, 11, Palette.ink)
            canvas.t5(wx(blx), bly, barrelLabel, Palette.score)
        }
    }

    private func drawMissVisual(canvas: PixelCanvas, wx: (Double) -> Double, elapsed: Double) {
        guard let m = missVisual else { return }
        let ballR = max(2, m.radius)
        canvas.disc(wx(m.ball.x), m.ball.y, ballR, Palette.chalk)
        canvas.px(wx(m.ball.x + ballR), m.ball.y, Palette.ink)
        let rr = ballR + 3 + (elapsed * 40).truncatingRemainder(dividingBy: 12)
        for a in 0..<24 {
            let ang = Double(a) / 24 * 2 * Double.pi
            canvas.px(wx(m.ball.x + cos(ang) * rr), m.ball.y + sin(ang) * rr, Palette.score)
        }
        guard let press = m.pressPoint else { return }
        let sX = press.x, sY = press.y
        if m.trailPoints.count > 1 {
            drawTrail(canvas: canvas, wx: wx, points: m.trailPoints, color: Palette.chalk, core: Palette.score, thickness: 2)
        }
        let grow = min(8, elapsed * 40)
        for a in 0..<8 {
            let ang = Double(a) / 8 * 2 * Double.pi + 0.39
            let l = (a % 2 == 1 ? 4.0 : 8.0) + grow
            canvas.line(wx(sX + cos(ang) * 13), sY + sin(ang) * 13,
                        wx(sX + cos(ang) * (13 + l)), sY + sin(ang) * (13 + l),
                        Palette.chalk, thickness: 1)
        }
        canvas.line(wx(sX - 3), sY - 3, wx(sX + 3), sY + 3, Palette.cap)
        canvas.line(wx(sX - 3), sY + 3, wx(sX + 3), sY - 3, Palette.cap)
        canvas.dashed(wx(sX), sY, wx(m.ball.x), m.ball.y, Palette.score)

        let dx = sX - m.ball.x, dy = sY - m.ball.y
        let inches = Int(((dx * dx + dy * dy).squareRoot() * 0.36).rounded())
        let label: String
        if m.early {
            label = "EARLY  BALL \(Int(m.feetAway.rounded())) FT OUT"
        } else {
            var words: [String] = []
            if abs(dy) > 3 { words.append(dy < 0 ? "HIGH" : "LOW") }
            if abs(dx) > 3 { words.append(dx < 0 ? "IN" : "OUT") }
            label = (words + ["\(inches)", "IN"]).joined(separator: " ")
        }
        let lx = max(4, min(320 - Double(label.count) * 4 - 4, (sX + m.ball.x) / 2 - Double(label.count) * 2))
        var ly = max(4, min(224 - 24, (sY + m.ball.y) / 2 + 14))
        if ly > 104, ly < 134 { ly = 98 }
        canvas.rect(wx(lx - 2), ly - 2, Double(label.count) * 4 + 3, 9, Palette.ink)
        canvas.t3(wx(lx), ly, label, Palette.score)
    }

    private func drawTrail(canvas: PixelCanvas, wx: (Double) -> Double, points: [Point],
                            color: Palette.RGBA8, core: Palette.RGBA8?, thickness: Int) {
        guard points.count > 1 else { return }
        for i in 1..<points.count {
            canvas.line(wx(points[i - 1].x), points[i - 1].y, wx(points[i].x), points[i].y, color, thickness: thickness)
        }
        if let core {
            let start = max(1, points.count - 6)
            for i in start..<points.count {
                canvas.line(wx(points[i - 1].x), points[i - 1].y, wx(points[i].x), points[i].y, core, thickness: 1)
            }
        }
    }

    /// The stroke behind the ball this frame: the live finger's own samples, or, through a
    /// replay's lead-in, the recorded ones that had been made by now (#42). One source or the
    /// other — the drawing below is the same either way, which is the point.
    private var strokeNow: [Point] {
        if let replayStroke { return replayStroke }
        return (trail ?? []).map { $0.point }
    }

    private func drawLiveTrail(canvas: PixelCanvas, wx: (Double) -> Double) {
        let stroke = strokeNow
        if stroke.count > 1 {
            drawTrail(canvas: canvas, wx: wx, points: Array(stroke.suffix(14)),
                      color: Palette.chalk, core: Palette.score, thickness: 2)
        }
        if let fadeTrail {
            let age = CACurrentMediaTime() - fadeTrail.time
            if age < 0.3 {
                drawTrail(canvas: canvas, wx: wx, points: fadeTrail.points, color: Palette.chalk, core: nil, thickness: 1)
            } else {
                self.fadeTrail = nil
            }
        }
    }

    // MARK: - The replay record (#4, #42)

    /// Where the camera in the corner goes and how big its target is. A knob per #42.
    private let replayIcon = ReplayIconLayout.standard

    /// The recorded stroke to draw instead of the live finger's, through a replay's lead-in.
    /// Nil in the game and from the freeze on.
    private var replayStroke: [Point]?

    /// The three things the contact freeze draws that the machine knows nothing about: the
    /// direction of the slash through the ball, the finger's trail behind it, and when each of
    /// those samples was made. Read by `GameController.recordSlice` the moment a swing lands, to
    /// go into the `Replay`.
    var lastContactMarks: (slash: Point, trail: [Point], times: [Double])? {
        contactVisual.map { ($0.dir, $0.trailPoints, $0.trailTimes) }
    }

    /// Hands an off-screen copy of this scene the stroke as it stood part-way through a replay's
    /// lead-in (#42). `nil` gives the live finger back, which is what the hand-over to the freeze
    /// does.
    func showReplayStroke(_ points: [Point]?) {
        replayStroke = points
    }

    /// Puts a recorded swing's draw-only marks back, so an off-screen copy of this scene redraws
    /// the contact freeze exactly as it was. `ReplayPlayback` calls this at the hand-over; the
    /// ball, its radius, the swing angle and the power all come from the crossing, which is the
    /// same one the live scene was handed.
    func restoreContactVisual(from replay: Replay) {
        let crossing = replay.swing.crossing
        contactVisual = ContactVisual(ball: crossing.ball.position,
                                      radius: crossing.ball.radius,
                                      dir: replay.marks.slash.point,
                                      angle: crossing.swingAngleDegrees,
                                      power: crossing.power,
                                      trailPoints: replay.marks.trail.map(\.point),
                                      trailTimes: replay.marks.trailTimes ?? [])
        trackedBeat = .contact
    }

    private func callWord(_ call: Call?) -> String {
        switch call {
        case .miss: return "MISS"
        case .strike: return "STRIKE"
        case .ball: return "BALL"
        case nil: return ""
        }
    }

    /// The swing angle of a missed stroke: `Contact.test`'s own formula, from `dragStart` to the
    /// finger's last sample, falling back to the last segment when that drag is shorter than
    /// `rules.minAngleLength`. A called strike/ball has no finger to measure and is never asked.
    private func missSwingAngleDegrees(rules: SliceRules) -> Double {
        guard let dragStart, let trail, let last = trail.last?.point else { return 20 }
        var dx = last.x - dragStart.x, dy = last.y - dragStart.y
        if (dx * dx + dy * dy).squareRoot() < rules.minAngleLength, trail.count > 1 {
            let prev = trail[trail.count - 2].point
            dx = last.x - prev.x; dy = last.y - prev.y
        }
        let rawAngle = atan2(-dy, abs(dx)) * 180 / .pi
        return min(rules.maxSwingAngle, max(rules.minSwingAngle, rawAngle))
    }

    // MARK: - Beat transitions

    private func handleBeatChange(to beat: Beat, controller: GameController) {
        switch beat {
        case .windup:
            contactVisual = nil
            missVisual = nil
            fadeTrail = nil
        case .miss:
            // A called strike/ball: `DerbyMachine` reached this beat on its own (the pitch
            // timed out), so no `touchesEnded` ever built a `missVisual` for it. Ring at the
            // plate, no trail (DESIGN.md §7).
            if controller.machine.lastCall != .miss {
                let ball = controller.ballAt(1.0)
                missVisual = MissVisual(pressPoint: nil, ball: ball.position, radius: ball.radius,
                                         early: false, feetAway: 0, trailPoints: [], angle: 20)
            } else if missVisual == nil {
                // A swing-miss `DerbyMachine` resolved on its own: the pitch timed out with a
                // slice still in progress, i.e. the finger held through it (DESIGN.md §3, issue
                // #20). A real `touchesEnded` miss already set `missVisual` synchronously before
                // this runs, so this only fires when the finger is still down — draw the same
                // markers from whatever the drag has recorded so far, same as `endDrag()`.
                let machine = controller.machine
                let c = closest
                let ball: BallSample
                let progress: Double
                let early: Bool
                if let c {
                    ball = c.ball
                    progress = c.progress
                    early = (1 - abs(c.progress - 1) / machine.sliceRules.timingWindow) <= 0
                } else {
                    ball = controller.ballAt(1.0)
                    progress = 1.0
                    early = false
                }
                let feetAway = max(0, (1 - progress) * machine.pitchingRules.moundDistanceFeet)
                missVisual = MissVisual(pressPoint: c?.fingerPoint, ball: ball.position, radius: ball.radius,
                                        early: early, feetAway: feetAway,
                                        trailPoints: (trail ?? []).suffix(24).map { $0.point },
                                        angle: missSwingAngleDegrees(rules: machine.sliceRules))
            }
        default:
            break
        }
    }

    // MARK: - Dev slice (DESIGN.md §5, dev only)

    #if DEBUG
    /// `-autoslice` launch argument: swing at every pitch as it arrives, so the wide camera can
    /// be reached with no finger (simulator screenshots, soak runs).
    private static let autoSlice = ProcessInfo.processInfo.arguments.contains("-autoslice")

    /// `-autobarrel` launch argument (issue #20 screenshots): the dev swing hits at full power
    /// instead of 0.7×, so every contact clears `StatRules.isBarrel` regardless of pitch type or
    /// exact timing jitter — for reliably capturing the `BARREL` call in a burst. Has no effect
    /// without `-autoslice` (or the space-bar dev slice) also firing the swing.
    private static let autoBarrel = ProcessInfo.processInfo.arguments.contains("-autobarrel")

    /// `-autoloft` launch argument (#5 screenshots): the dev swing takes a steep stroke instead
    /// of the usual 27°, so it puts up a towering fly. The birds and the blimp fly at design
    /// y 18–52, which nothing reaches until the close camera pins a ball near the top of the
    /// frame — and the flat 27° robot never gets high enough to be pinned. Like `-autobarrel`
    /// it changes only the stroke, fakes no career state, and does nothing on its own.
    private static let autoLoft = ProcessInfo.processInfo.arguments.contains("-autoloft")
    private static let loftDegrees = 53.0
    /// How many samples the robot's stroke is made of: the same eighteen a real drag's trail
    /// keeps, a display frame apart, so a `-replay` clip's lead-in has a stroke growing in it
    /// rather than one that appears whole (#42).
    private static let devStrokeSamples = 18

    /// A medium 27° stroke through the ball, wherever it is, run through the real hit test so
    /// an early press is judged like an early finger. Space bar calls this.
    func devSlice() {
        guard let controller, controller.machine.beat == .pitch else { return }
        let machine = controller.machine
        let ball = machine.ballNow.position
        let radians = (Self.autoLoft ? Self.loftDegrees : 27.0) * Double.pi / 180
        let dir = Point(x: cos(radians), y: -sin(radians))
        func along(_ d: Double) -> Point { Point(x: ball.x + dir.x * d, y: ball.y + dir.y * d) }
        let speed = Self.autoBarrel ? machine.sliceRules.fullPowerSpeed : 0.7 * machine.sliceRules.fullPowerSpeed
        let outcome = Contact.test(segment: along(-4), along(4), dragStart: along(-40),
                                   fingerSpeed: speed,
                                   pitch: machine.pitch, progress: machine.pitchProgress,
                                   ballAt: { controller.ballAt($0) }, rules: machine.sliceRules)
        guard case .contact(let crossing) = outcome else { return }
        // The robot has no finger, so its stroke is sampled like one: the same eighteen points a
        // real drag keeps (`trail.suffix(18)`), a display frame apart, along the stroke it took.
        // Without the times a `-replay` clip's lead-in would have no stroke growing in it (#42).
        let samples = Self.devStrokeSamples
        var points: [Point] = []
        var times: [Double] = []
        for i in 0..<samples {
            let t = Double(i) / Double(samples - 1)
            points.append(along(-40 + 44 * t))
            times.append(-Double(samples - 1 - i) / 60)
        }
        contactVisual = ContactVisual(ball: crossing.ball.position, radius: crossing.ball.radius, dir: dir,
                                      angle: crossing.swingAngleDegrees, power: crossing.power,
                                      trailPoints: points, trailTimes: times)
        controller.recordSlice(crossing)
    }
    #endif

    // MARK: - Touch input (the slice)

    private func designPoint(for touch: UITouch) -> Point {
        let p = touch.location(in: self)
        return Point(x: Double(p.x) - xOffset, y: Double(size.height - p.y))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let p = designPoint(for: touch)
        dragStart = p
        trail = [SamplePoint(point: p, time: CACurrentMediaTime())]
        closest = nil
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let dragStart, let controller, var trail = self.trail else { return }
        let b = designPoint(for: touch)
        let now = CACurrentMediaTime()
        let a = trail.last?.point ?? b
        trail.append(SamplePoint(point: b, time: now))
        if trail.count > 24 { trail.removeFirst(trail.count - 24) }
        self.trail = trail

        let machine = controller.machine
        guard machine.beat == .pitch else { return }

        // Finger speed over the last ~80 ms.
        var j = trail.count - 1
        while j > 0, now - trail[j].time < 0.08 { j -= 1 }
        let ref = trail[j]
        let elapsedTime = max(0.016, now - ref.time)
        let fingerSpeed = hypot(b.x - ref.point.x, b.y - ref.point.y) / elapsedTime

        let outcome = Contact.test(
            segment: a, b,
            dragStart: dragStart,
            fingerSpeed: fingerSpeed,
            pitch: machine.pitch,
            progress: machine.pitchProgress,
            ballAt: { controller.ballAt($0) },
            rules: machine.sliceRules
        )

        switch outcome {
        case .contact(let crossing):
            var dx = b.x - dragStart.x, dy = b.y - dragStart.y
            if hypot(dx, dy) < machine.sliceRules.minAngleLength { dx = b.x - a.x; dy = b.y - a.y }
            let len = max(0.0001, hypot(dx, dy))
            let kept = trail.suffix(18)
            contactVisual = ContactVisual(
                ball: crossing.ball.position,
                radius: crossing.ball.radius,
                dir: Point(x: dx / len, y: dy / len),
                angle: crossing.swingAngleDegrees,
                power: crossing.power,
                trailPoints: kept.map { $0.point },
                // Relative to this instant, so a lead-in can draw the stroke growing (#42).
                trailTimes: kept.map { $0.time - now }
            )
            controller.recordSlice(crossing)
            self.trail = nil
            self.dragStart = nil
        case .miss(let d, let ball, let p):
            if d < (closest?.distance ?? .infinity) {
                closest = ClosestMiss(distance: d, ball: ball, progress: p, fingerPoint: b)
            }
        case .early(let ball, let p):
            closest = ClosestMiss(distance: 0, ball: ball, progress: p, fingerPoint: b)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endDrag()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endDrag()
    }

    /// A tap that starts here and goes nowhere opens the stats board. The scoreboard
    /// `(128, 80, 64×16)` grown to thumb size; a slice is never this short.
    private func isScoreboardTap() -> Bool {
        guard let start = dragStart, (112...208).contains(start.x), (70...106).contains(start.y) else { return false }
        return (trail ?? []).allSatisfy { hypot($0.point.x - start.x, $0.point.y - start.y) < 6 }
    }

    /// A finger that is on the camera in the corner and has not moved. While that is true it is
    /// not a swing in progress (`fingerDown`), and if it lifts there it opens the replay instead
    /// of being answered as one (#42). `dragStart` is in the centred 320 column and the camera is
    /// pinned to the canvas's own edge, so the offset goes back on before the test.
    private var isReplayIconTouch: Bool {
        guard controller?.showsReplayIcon == true, let start = dragStart else { return false }
        let canvasPoint = Point(x: start.x + xOffset, y: start.y)
        guard ReplayIcon.contains(canvasPoint, canvasWidth: Double(size.width),
                                  safeRight: safeRight, layout: replayIcon) else { return false }
        return (trail ?? []).allSatisfy {
            hypot($0.point.x - start.x, $0.point.y - start.y) < replayIcon.tapSlack
        }
    }

    private func endDrag() {
        if isReplayIconTouch {
            trail = nil; dragStart = nil; closest = nil
            controller?.showReplay()    // not a swing: nothing is counted
            return
        }
        if isScoreboardTap() {
            trail = nil; dragStart = nil; closest = nil
            controller?.showStats()     // not a swing: nothing is counted
            return
        }
        if let trail, trail.count > 1 {
            fadeTrail = (points: trail.suffix(18).map { $0.point }, time: CACurrentMediaTime())
        }
        defer { trail = nil; dragStart = nil; closest = nil }

        guard let controller, controller.machine.beat == .pitch else { return }
        let machine = controller.machine
        let c = closest
        let ball: BallSample
        let progress: Double
        let early: Bool
        if let c {
            ball = c.ball
            progress = c.progress
            early = (1 - abs(c.progress - 1) / machine.sliceRules.timingWindow) <= 0
        } else {
            ball = controller.ballAt(min(1.15, machine.pitchProgress))
            progress = machine.pitchProgress
            early = true
        }
        let feetAway = max(0, (1 - progress) * machine.pitchingRules.moundDistanceFeet)
        missVisual = MissVisual(
            pressPoint: c?.fingerPoint,
            ball: ball.position,
            radius: ball.radius,
            early: early,
            feetAway: feetAway,
            trailPoints: (trail ?? []).suffix(24).map { $0.point },
            angle: missSwingAngleDegrees(rules: machine.sliceRules)
        )
        controller.recordMissedSlice()
    }
}
