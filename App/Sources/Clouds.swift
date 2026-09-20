import Foundation
import DerbyCore

/// The clouds, which are the first thing in this game's sky that moves. Drawn per frame — they
/// are the only part of a backdrop that cannot be cached — and that costs a few dozen rectangles.
///
/// They drift at the park's seeded breeze, in whole pixels, stepping four times a second at most:
/// the ball and its trail stay the only smooth things on screen (DESIGN.md §9, §17). The clock is
/// `Tally.secondsPlayed`, which the machine already owns, so a replay (#4) redraws the same sky.
/// Never `Date()`.
enum Clouds {
    struct Rules: Equatable {
        /// Whole pixels, four times a second at most.
        var stepsPerSecond = 4.0
        /// `chalk` with a `sky3` underside by day; dimmer by night, per §17.
        var dayBody = Palette.chalk
        var dayUnderside = Palette.sky3
        var nightBody = Palette.nightSky3
        var nightUnderside = Palette.ink
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
                     width: Double, night: Bool, rules: Rules = .standard) {
        guard width > 0 else { return }
        let body = night ? rules.nightBody : rules.dayBody
        let underside = night ? rules.nightUnderside : rules.dayUnderside
        let d = drift(breeze: breeze, seconds: seconds, rules: rules)

        for cloud in clouds {
            let stampWidth = Double(cloud.width)
            // Wrapped across a span one stamp wider than the view, so a cloud leaves the right
            // edge and walks back in from the left rather than popping.
            let span = width + stampWidth
            var x = (cloud.xFraction * width + d).truncatingRemainder(dividingBy: span)
            if x < 0 { x += span }
            x -= stampWidth

            for block in cloud.blocks {
                let bx = (x + Double(block.dx)).rounded()
                let rise = Double(block.rise)
                c.rect(bx, cloud.baselineY - rise, Double(block.w), rise, body)
                c.rect(bx, cloud.baselineY - 1, Double(block.w), 1, underside)
            }
        }
    }
}
