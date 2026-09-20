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
    }

    private struct MissVisual {
        let pressPoint: Point?
        let ball: Point
        let radius: Double
        let early: Bool
        let feetAway: Double
        let trailPoints: [Point]
    }

    private var trail: [SamplePoint]?
    private var dragStart: Point?
    private var closest: ClosestMiss?
    private var contactVisual: ContactVisual?
    private var missVisual: MissVisual?
    private var fadeTrail: (points: [Point], time: CFTimeInterval)?
    private var trackedBeat: Beat = .windup

    private var xOffset: Double { (Double(size.width) - 320) / 2 }

    // MARK: - Drawing

    override func render(into canvas: PixelCanvas) {
        guard let controller else { return }
        let machine = controller.machine

        if machine.beat != trackedBeat {
            handleBeatChange(to: machine.beat, controller: controller)
            trackedBeat = machine.beat
        }
        #if DEBUG
        if Self.autoSlice, machine.beat == .pitch, machine.pitchProgress >= 0.97 { devSlice() }
        #endif

        let scheme = Palette.scheme(isNight: machine.park.isNight)
        let W = 320.0, H = 224.0
        let fullWidth = Double(canvas.width)
        let xOff = xOffset
        func wx(_ x: Double) -> Double { x + xOff }

        // Sky, wall band and grass span the full (possibly wider-than-320) canvas.
        canvas.rect(0, 0, fullWidth, H, scheme.sky1)
        canvas.rect(0, 44, fullWidth, 26, scheme.sky2)
        canvas.rect(0, 70, fullWidth, 26, scheme.sky3)
        canvas.dither(0, 42, fullWidth, 4, scheme.sky1, scheme.sky2)
        canvas.dither(0, 68, fullWidth, 4, scheme.sky2, scheme.sky3)
        canvas.rect(0, 96, fullWidth, 8, Palette.wall)
        canvas.rect(0, 96, fullWidth, 1, Palette.chalk)
        canvas.rect(0, 104, fullWidth, H - 104, Palette.grassA)
        var gy = 104.0
        while gy < H { canvas.rect(0, gy, fullWidth, 6, Palette.grassB); gy += 12 }

        // Everything else is the 320-wide prototype column, centred.
        canvas.rect(wx(128), 80, 64, 16, Palette.wall)
        canvas.rect(wx(128), 80, 64, 1, Palette.chalk)
        canvas.t3(wx(134), 84, "\(Int(machine.park.wallDistanceFeet)) FT", Palette.score)
        canvas.t3(wx(134), 91, machine.park.displayName, Palette.chalk)

        canvas.line(wx(160), 196, wx(40), 104, Palette.chalk)
        canvas.line(wx(160), 196, wx(280), 104, Palette.chalk)
        canvas.rect(wx(148), 116, 24, 5, Palette.dirt)
        canvas.rect(wx(150), 121, 20, 2, Palette.dirtD)
        canvas.rect(wx(120), 184, 80, 14, Palette.dirt)
        canvas.rect(wx(124), 198, 72, 4, Palette.dirtD)
        canvas.rect(wx(152), 190, 16, 4, Palette.chalk)

        drawPitcher(canvas: canvas, wx: wx, beat: machine.beat, elapsed: machine.elapsed)

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

        let batterFrame: Int
        switch machine.beat {
        case .contact: batterFrame = 1
        case .miss where machine.lastCall == .miss: batterFrame = 2
        default: batterFrame = 0
        }
        drawBatter(canvas: canvas, wx: wx, frame: batterFrame)

        switch machine.beat {
        case .pitch:
            let b = machine.ballNow
            canvas.baseball(wx(b.x), b.y, radius: b.radius, highlight: scheme.sky3)
            if b.radius >= 2 { canvas.px(wx(b.x + b.radius), b.y, Palette.ink) }
            canvas.t3(wx(8), H - 12, "\(Int(machine.pitch.speedMPH.rounded())) MPH", Palette.chalk)
        case .contact:
            drawContactVisual(canvas: canvas, wx: wx, elapsed: machine.elapsed, isBarrel: machine.isBarrelNow, zone: z)
        case .miss:
            drawMissVisual(canvas: canvas, wx: wx, elapsed: machine.elapsed)
            let label = callWord(machine.lastCall)
            let labelY = (missVisual?.early ?? false) ? 164.0 : 118.0
            canvas.t3(wx(W / 2 - Double(label.count) * 4), labelY, label, Palette.score, scale: 2)
            canvas.t3(wx(8), H - 12, "\(machine.pitch.type.name) \(Int(machine.pitch.speedMPH.rounded())) MPH", Palette.chalk)
        default:
            break
        }

        // HUD anchors to the true edges of the canvas, not the centred column.
        // The headline: where you are and what it has cost (DESIGN.md §10).
        let pitches = machine.tally.pitches
        canvas.t3(8, 8, "\(machine.park.displayName)  \(pitches) \(pitches == 1 ? "PITCH" : "PITCHES")", Palette.chalk)
        // Not during the contact freeze: the tally already knows how the ball lands, and a
        // streak line appearing or vanishing here would spoil the cut.
        if machine.tally.homeRunStreak >= 2, machine.beat != .contact {
            canvas.t3(8, 16, "HR STREAK \(machine.tally.homeRunStreak)", Palette.score)
        }

        drawLiveTrail(canvas: canvas, wx: wx)
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

    /// Three frames on the windup clock — `elapsed`/`beat`, no state of its own — set, leg
    /// kick/reach back, release (DESIGN.md §3, §9). The third, `.set`, was the one never built
    /// (issue #20): before it, the windup's first 40% and everything past `.pitch` shared the
    /// release silhouette, so the wind-up never had a calm beat to kick off from.
    private func drawPitcher(canvas: PixelCanvas, wx: (Double) -> Double, beat: Beat, elapsed: Double) {
        let windup = beat == .windup ? min(1, elapsed / 0.5) : 1
        let px = 160.0, py = 117.0
        canvas.rect(wx(px - 2), py - 12, 5, 8, Palette.ink)
        canvas.rect(wx(px - 2), py - 16, 5, 4, Palette.skin)
        canvas.rect(wx(px - 3), py - 18, 7, 2, Palette.cap)
        if beat == .windup, windup <= 0.4 {
            // Set: feet together, hands tucked in — the pause before the kick.
            canvas.rect(wx(px - 1), py - 4, 2, 4, Palette.ink)
        } else if beat == .windup, windup < 0.9 {
            // Leg kick / reach back.
            canvas.rect(wx(px - 1), py - 4, 3, 4, Palette.ink)
            canvas.rect(wx(px + 2), py - 8, 2, 4, Palette.ink)
            canvas.line(wx(px + 3), py - 12, wx(px + 6), py - 20, Palette.ink)
        } else {
            // Release: also held through `.pitch` and beyond — the ball has already left the hand.
            canvas.rect(wx(px - 2), py - 4, 2, 4, Palette.ink)
            canvas.rect(wx(px + 1), py - 4, 2, 4, Palette.ink)
            canvas.line(wx(px + 3), py - 10, wx(px + 7), py - 6, Palette.ink)
        }
    }

    private func drawBatter(canvas: PixelCanvas, wx: (Double) -> Double, frame: Int) {
        let bx = 104.0, by = 222.0
        canvas.rect(wx(bx - 8), by - 24, 7, 24, Palette.ink)
        canvas.rect(wx(bx + 3), by - 24, 7, 24, Palette.ink)
        canvas.rect(wx(bx - 9), by - 52, 20, 30, Palette.ink)
        canvas.rect(wx(bx - 6), by - 64, 12, 12, Palette.skin)
        canvas.rect(wx(bx - 8), by - 68, 16, 6, Palette.cap)
        canvas.rect(wx(bx - 8), by - 62, 4, 8, Palette.cap)
        switch frame {
        case 0:
            canvas.rect(wx(bx + 8), by - 48, 6, 8, Palette.ink)
            canvas.rect(wx(bx + 12), by - 52, 4, 4, Palette.skin)
            canvas.line(wx(bx + 14), by - 52, wx(bx + 22), by - 84, Palette.bat, thickness: 3)
        case 1:
            canvas.rect(wx(bx + 8), by - 44, 10, 6, Palette.ink)
            canvas.rect(wx(bx + 16), by - 44, 4, 4, Palette.skin)
            canvas.line(wx(bx + 18), by - 42, wx(bx + 62), by - 58, Palette.bat, thickness: 3)
        default:
            canvas.rect(wx(bx - 14), by - 40, 8, 6, Palette.ink)
            canvas.rect(wx(bx - 16), by - 40, 4, 4, Palette.skin)
            canvas.line(wx(bx - 16), by - 40, wx(bx - 40), by - 56, Palette.bat, thickness: 3)
        }
    }

    private func drawContactVisual(canvas: PixelCanvas, wx: (Double) -> Double, elapsed: Double,
                                    isBarrel: Bool, zone: Rect) {
        guard let c = contactVisual else { return }
        drawTrail(canvas: canvas, wx: wx, points: c.trailPoints, color: Palette.chalk, core: nil, thickness: 1)
        let x0 = c.ball.x - c.dir.x * 16, y0 = c.ball.y - c.dir.y * 16
        let x1 = c.ball.x + c.dir.x * 16, y1 = c.ball.y + c.dir.y * 16
        canvas.line(wx(x0), y0, wx(x1), y1, Palette.chalk, thickness: 3)
        canvas.line(wx(x0), y0, wx(x1), y1, Palette.score, thickness: 1)
        canvas.baseball(wx(c.ball.x), c.ball.y, radius: max(2, c.radius), highlight: Palette.sky3)
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

    private func drawLiveTrail(canvas: PixelCanvas, wx: (Double) -> Double) {
        if let trail, trail.count > 1 {
            drawTrail(canvas: canvas, wx: wx, points: trail.suffix(14).map { $0.point },
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

    private func callWord(_ call: Call?) -> String {
        switch call {
        case .miss: return "MISS"
        case .strike: return "STRIKE"
        case .ball: return "BALL"
        case nil: return ""
        }
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
                                         early: false, feetAway: 0, trailPoints: [])
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
                                        trailPoints: (trail ?? []).suffix(24).map { $0.point })
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

    /// A medium 27° stroke through the ball, wherever it is, run through the real hit test so
    /// an early press is judged like an early finger. Space bar calls this.
    func devSlice() {
        guard let controller, controller.machine.beat == .pitch else { return }
        let machine = controller.machine
        let ball = machine.ballNow.position
        let radians = 27.0 * Double.pi / 180
        let dir = Point(x: cos(radians), y: -sin(radians))
        func along(_ d: Double) -> Point { Point(x: ball.x + dir.x * d, y: ball.y + dir.y * d) }
        let speed = Self.autoBarrel ? machine.sliceRules.fullPowerSpeed : 0.7 * machine.sliceRules.fullPowerSpeed
        let outcome = Contact.test(segment: along(-4), along(4), dragStart: along(-40),
                                   fingerSpeed: speed,
                                   pitch: machine.pitch, progress: machine.pitchProgress,
                                   ballAt: { controller.ballAt($0) }, rules: machine.sliceRules)
        guard case .contact(let crossing) = outcome else { return }
        contactVisual = ContactVisual(ball: crossing.ball.position, radius: crossing.ball.radius, dir: dir,
                                      angle: crossing.swingAngleDegrees, power: crossing.power,
                                      trailPoints: [along(-40), along(4)])
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
        // Touch-down during `.pitch`: if the pitch times out with this still true, `DerbyMachine`
        // resolves it as a swing and a miss, not a take (DESIGN.md §3, issue #20).
        if controller?.machine.beat == .pitch { controller?.setSliceInProgress(true) }
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
            contactVisual = ContactVisual(
                ball: crossing.ball.position,
                radius: crossing.ball.radius,
                dir: Point(x: dx / len, y: dy / len),
                angle: crossing.swingAngleDegrees,
                power: crossing.power,
                trailPoints: trail.suffix(18).map { $0.point }
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

    private func endDrag() {
        // Touch-up or cancel always ends any slice in progress, whatever the beat is now.
        controller?.setSliceInProgress(false)
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
            trailPoints: (trail ?? []).suffix(24).map { $0.point }
        )
        controller.recordMissedSlice()
    }
}
