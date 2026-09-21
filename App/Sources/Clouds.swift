import Foundation
import DerbyCore

/// The clouds, which are the first thing in this game's sky that moves. Drawn per frame — they
/// are the only part of a backdrop that cannot be cached — and that costs a few dozen columns.
///
/// They drift at the park's seeded breeze, in whole pixels, stepping four times a second at most:
/// the ball and its trail stay the only smooth things on screen (DESIGN.md §9, §17). The clock is
/// `Tally.secondsPlayed`, which the machine already owns, so a replay (#4) redraws the same sky.
/// Never `Date()`.
///
/// §20 changed how a stamp is *drawn* and nothing else: the stamps, where they sit and how they
/// drift are §17's, still seeded off the park. `morning` and `midday` get cumulus that the light
/// shades and no outline; the other four get flat streaks with dithered ends and a lit underside
/// (`golden.clouds`).
enum Clouds {
    struct Rules: Equatable {
        /// Whole pixels, four times a second at most.
        var stepsPerSecond = 4.0
        /// Where the four cloud tones cut, as a fraction of the way down a stamp. A streak is
        /// top / body / lower / underside; the cumulus reads its light instead and keeps only
        /// three of the four (`golden.clouds`).
        var streakTopBelow = -0.35
        var streakUndersideAbove = 0.45
        var streakUndersideNotLeftOf = -0.5
        var streakLowerAbove = 0.05
        /// Past this far out sideways a streak's end dithers away rather than stopping dead.
        var streakDitherBeyond = 0.78
        /// The cumulus: how much of the phase's light direction reaches its sides, how hard it
        /// falls off, and how many rows at the bottom are the shaded underside.
        var cumulusSideLight = 0.6
        var cumulusDownLight = -0.8
        var cumulusShadeBelow = -0.35
        var cumulusUndersideRows = 1
        var cumulusShadeRows = 3
        static let standard = Rules()
    }

    /// The park's breeze, in whole pixels, at this moment. The quantised clock is the whole
    /// point: a cloud jumps a pixel four times a second and is otherwise still.
    static func drift(breeze: Double, seconds: Double, rules: Rules = .standard) -> Double {
        let stepped = (seconds * rules.stepsPerSecond).rounded(.down) / rules.stepsPerSecond
        return (breeze * stepped).rounded()
    }

    /// One view's sky. `clouds` is `Scenery.atBatClouds` or `Scenery.sideClouds` — the two views
    /// look in different directions and never share one (§17).
    static func draw(into c: PixelCanvas, clouds: [Cloud], breeze: Double, seconds: Double,
                     width: Double, look: Look, rules: Rules = .standard) {
        guard width > 0 else { return }
        let d = drift(breeze: breeze, seconds: seconds, rules: rules)

        for cloud in clouds {
            let stampWidth = Double(cloud.width)
            // Wrapped across a span one stamp wider than the view, so a cloud leaves the right
            // edge and walks back in from the left rather than popping.
            let span = width + stampWidth
            var x = (cloud.xFraction * width + d).truncatingRemainder(dividingBy: span)
            if x < 0 { x += span }
            x -= stampWidth
            stamp(cloud, into: c, at: x, look: look, rules: rules)
        }
    }

    /// One stamp, shaded. A §17 stamp is a run of blocks standing on a baseline, so the silhouette
    /// is a low mound; the normal each pixel is shaded by is read straight off that mound —
    /// across from the middle, and down from the top of its own column — which is the same field
    /// of normals the prototype gets from a row of overlapping ellipses.
    private static func stamp(_ cloud: Cloud, into c: PixelCanvas, at x: Double,
                              look: Look, rules: Rules) {
        // The top of each column of the stamp: the highest block standing over it.
        var tops: [Int: Double] = [:]
        for block in cloud.blocks {
            let bx = Int((x + Double(block.dx)).rounded())
            let top = cloud.baselineY - Double(block.rise)
            for i in 0..<max(0, block.w) {
                let col = bx + i
                tops[col] = min(tops[col] ?? top, top)
            }
        }
        guard let lo = tops.keys.min(), let hi = tops.keys.max(), hi > lo else { return }
        let mid = Double(lo + hi) / 2, half = max(1, Double(hi - lo) / 2)
        let t = look.cloud
        let base = cloud.baselineY

        for (col, top) in tops {
            let depth = base - top
            guard depth >= 1 else { continue }
            let nx = (Double(col) + 0.5 - mid) / half
            var row = top
            while row < base {
                let ny = 2 * (row + 0.5 - top) / depth - 1
                let colour: Palette.RGBA8
                if look.cumulus {
                    let l = nx * (look.light.x * rules.cumulusSideLight)
                        + ny * rules.cumulusDownLight
                    if row >= base - Double(rules.cumulusUndersideRows) {
                        colour = t[3]
                    } else if l < rules.cumulusShadeBelow || row >= base - Double(rules.cumulusShadeRows) {
                        colour = t[2]
                    } else {
                        colour = t[0]
                    }
                } else {
                    // A flat streak: dark on top, a lit underside on the side away from the
                    // light, and ends that dither out instead of stopping dead.
                    if abs(nx) > rules.streakDitherBeyond,
                       (col &+ Int(row)) & 1 != 0 { row += 1; continue }
                    if ny < rules.streakTopBelow { colour = t[0] }
                    else if ny > rules.streakUndersideAbove, nx > rules.streakUndersideNotLeftOf {
                        colour = t[3]
                    } else if ny > rules.streakLowerAbove { colour = t[2] }
                    else { colour = t[1] }
                }
                c.px(Double(col), row, colour)
                row += 1
            }
        }
    }
}
