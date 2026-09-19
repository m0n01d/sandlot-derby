import SpriteKit
import DerbyCore

/// The flight camera: side view, the batted ball travelling with real drag, and the landing
/// number. A port of the prototype's `drawWide` (prototypes/03-camera-cut-and-slice.html
/// ~L426-455), minus the parts of that function that only existed for the "wide only" debug
/// camera (pitch/miss drawing), which this build never shows here — the at-bat camera owns
/// those beats.
final class WideScene: CanvasScene {
    /// View starts 24 ft behind the plate; `s` is px-per-foot, uniform, derived from the
    /// canvas width so wider phones see more field (DESIGN.md §8).
    private let viewLeftFeet = -24.0
    private let groundY = 176.0

    override func render(into canvas: PixelCanvas) {
        guard let controller else { return }
        let machine = controller.machine
        let scheme = Palette.scheme(isNight: machine.park.isNight)
        let H = 224.0
        let fullWidth = Double(canvas.width)
        // The field starts inside the safe area so the batter isn't under the Dynamic Island;
        // sky and grass still run edge to edge.
        let s = min((fullWidth - safeLeft - safeRight) / 584, 170.0 / 230.0)
        func sx(_ feet: Double) -> Double { safeLeft + (feet - viewLeftFeet) * s }
        func sy(_ feet: Double) -> Double { groundY - feet * s }

        canvas.rect(0, 0, fullWidth, H, scheme.sky1)
        canvas.rect(0, 70, fullWidth, 60, scheme.sky2)
        canvas.rect(0, 130, fullWidth, groundY - 130, scheme.sky3)
        canvas.dither(0, 66, fullWidth, 8, scheme.sky1, scheme.sky2)
        canvas.dither(0, 126, fullWidth, 8, scheme.sky2, scheme.sky3)

        canvas.rect(0, groundY, fullWidth, H - groundY, Palette.grassA)
        var gx = 0.0
        while gx < fullWidth { canvas.rect(gx, groundY, 12, H - groundY, Palette.grassB); gx += 24 }

        let wallX = sx(machine.park.wallDistanceFeet)
        let wallH = machine.park.wallHeightFeet * s
        canvas.rect(wallX, groundY - wallH, fullWidth - wallX, wallH, Palette.wall)
        canvas.rect(wallX, groundY - wallH, fullWidth - wallX, 1, Palette.chalk)
        canvas.rect(wallX, groundY - wallH - 1, 2, wallH + 1, Palette.chalk)
        canvas.t3(wallX + 6, groundY - wallH + 3, "\(Int(machine.park.wallDistanceFeet))", Palette.score)

        var f = 100.0
        while sx(f) < fullWidth { canvas.rect(sx(f), groundY, 1, 4, Palette.chalk); f += 100 }

        canvas.rect(sx(-8), groundY, 16 * s * 2, 5, Palette.dirt)

        let bx = sx(0), by = groundY
        let frame: Int = machine.flight != nil ? (machine.playbackIndex < 12 ? 1 : 2) : 0
        canvas.rect(bx - 5, by - 14, 4, 14, Palette.ink)
        canvas.rect(bx + 1, by - 14, 4, 14, Palette.ink)
        canvas.rect(bx - 5, by - 30, 10, 16, Palette.ink)
        canvas.rect(bx - 3, by - 40, 7, 10, Palette.skin)
        canvas.rect(bx - 4, by - 42, 8, 3, Palette.cap)
        canvas.rect(bx - 4, by - 38, 10, 2, Palette.cap)
        switch frame {
        case 0: canvas.line(bx + 3, by - 26, bx - 4, by - 50, Palette.bat, thickness: 2)
        case 1: canvas.line(bx + 4, by - 26, bx + 24, by - 24, Palette.bat, thickness: 2)
        default: canvas.line(bx - 8, by - 30, bx - 22, by - 46, Palette.bat, thickness: 2)
        }

        if let flightResult = machine.flight, !flightResult.points.isEmpty {
            let points = flightResult.points
            let i = min(points.count - 1, Int(machine.playbackIndex))

            var k = 0
            while k < i {
                let pt = points[k]
                canvas.px(sx(pt.xFeet), sy(pt.yFeet) - 2, Palette.chalk)
                k += 8
            }
            let b = points[i]
            let X = sx(b.xFeet), Y = sy(b.yFeet) - 3
            canvas.rect(X - 1, Y - 1, 4, 4, Palette.chalk)
            canvas.px(X, Y, scheme.sky3)

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
                if flightResult.wallHit {
                    canvas.t3(fullWidth / 2 - 30, 90, "OFF THE WALL", Palette.chalk)
                }
            }
        }

        canvas.t3(fullWidth - 42, H - 12, "PARK \(machine.park.number)", Palette.chalk)
    }
}
