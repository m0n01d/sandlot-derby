import Foundation

/// W0's test pattern (docs/watch.md §9): a canvas drawn so that a screenshot of the glass, zoomed
/// in, answers three questions by counting — is one unit exactly `scale` physical pixels, where do
/// the round corners cut, and what does the system clock cover. See `Watch/README.md`.
enum TestPattern {
    /// The quarter-circle rings in each corner, in design units from the corner.
    static let cornerRings = [8, 16, 24, 32]
    /// The clock stripes: one line every `clockStripeGap` units down the top-right
    /// `clockStripeWidth` columns, alternating colours, down to `clockStripeDepth`.
    static let clockStripeGap = 4
    static let clockStripeWidth = 64
    static let clockStripeDepth = 40
    /// The checkerboard of single units in the middle, `checkerSize` on a side.
    static let checkerSize = 16

    /// Draws the pattern. `frame` moves one marker along the bottom row so a frozen frame shows,
    /// and `label` is written under the checkerboard (the blit path and the measured frame rate).
    static func draw(into c: PixelCanvas, canvas: WatchCanvas, frame: Int, label: String) {
        let w = c.width, h = c.height
        c.fill(Palette.ink)

        // The top-right stripes, drawn first so the rulers sit on top of them.
        for y in stride(from: 0, to: clockStripeDepth, by: clockStripeGap) {
            let colour = (y / clockStripeGap).isMultiple(of: 2) ? Palette.sky2 : Palette.grassA
            c.rect(Double(w - clockStripeWidth), Double(y), Double(clockStripeWidth), 1, colour)
        }

        // A one-unit border at the canvas edge.
        c.rect(0, 0, Double(w), 1, Palette.chalk)
        c.rect(0, Double(h - 1), Double(w), 1, Palette.chalk)
        c.rect(0, 0, 1, Double(h), Palette.chalk)
        c.rect(Double(w - 1), 0, 1, Double(h), Palette.chalk)

        // Rulers along the top and left edges: a tick every 2 units, a long yellow one every 10.
        for x in stride(from: 0, to: w, by: 2) {
            let long = x.isMultiple(of: 10)
            c.rect(Double(x), 1, 1, long ? 4 : 2, long ? Palette.score : Palette.chalk)
        }
        for y in stride(from: 0, to: h, by: 2) {
            let long = y.isMultiple(of: 10)
            c.rect(1, Double(y), long ? 4 : 2, 1, long ? Palette.score : Palette.chalk)
        }

        // Rings about each corner at 8, 16, 24 and 32 units: red, yellow, red, yellow.
        let corners = [(0.0, 0.0), (Double(w), 0.0), (0.0, Double(h)), (Double(w), Double(h))]
        for (i, r) in cornerRings.enumerated() {
            let colour = i.isMultiple(of: 2) ? Palette.cap : Palette.score
            for (cx, cy) in corners { ring(c, cx, cy, Double(r), colour) }
        }

        // The checkerboard: every cell one unit. Zoomed in, each should be `scale` pixels square.
        let n = checkerSize
        let x0 = (w - n) / 2, y0 = (h - n) / 2
        for j in 0..<n {
            for i in 0..<n where (i + j).isMultiple(of: 2) {
                c.rect(Double(x0 + i), Double(y0 + j), 1, 1, Palette.chalk)
            }
        }

        // What this is, and how it is being drawn. In `t3` at 2×: `t5` has digits and a handful
        // of capitals, not the whole alphabet (see Watch/README.md).
        let size = "\(canvas.width)X\(canvas.height) X\(canvas.scale)"
        label3(c, size, y: Double(y0 - 14), Palette.chalk)
        label3(c, label, y: Double(y0 + n + 4), Palette.score)

        // The liveness marker: one unit crawling along the row above the bottom border.
        c.rect(Double(1 + frame % max(1, w - 2)), Double(h - 2), 1, 1, Palette.cap)
    }

    /// A line of `t3` at 2×, centred. Characters it lacks draw as spaces.
    static func label3(_ c: PixelCanvas, _ text: String, y: Double, _ colour: Palette.RGBA8) {
        let width = text.count * 8 - 2
        c.t3(Double((c.width - width) / 2), y, text, colour, scale: 2)
    }

    /// One-unit-wide quarter circle about a corner, inside the canvas.
    private static func ring(_ c: PixelCanvas, _ cx: Double, _ cy: Double, _ r: Double,
                             _ colour: Palette.RGBA8) {
        let steps = Int(r * 8)
        for s in 0...steps {
            let a = Double(s) / Double(steps) * 2 * Double.pi
            c.px((cx + r * cos(a)).rounded(.down), (cy + r * sin(a)).rounded(.down), colour)
        }
    }
}
