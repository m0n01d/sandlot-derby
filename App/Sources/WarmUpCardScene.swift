import SpriteKit
import DerbyCore

/// Where the Warm Up card's lines sit, in design units (DESIGN.md §8, §18). Centred rather than
/// pinned, exactly as the contract card is: on a wide phone the panel sits in the middle and the
/// corner word stays in the corner. Every number here is a knob.
struct WarmUpCardLayout {
    /// The panel the card is printed on, centred horizontally.
    var panelWidth = 264.0
    var panelTop = 20.0
    var panelHeight = 168.0
    /// The chalk rule drawn just inside the panel.
    var panelInset = 3.0

    /// `WARM UP 173`, the day's own number, as big as the scoreboard's heading.
    var titleY = 30.0
    var titleScale = 3

    /// The ten cells, one per pitch, in a row.
    var cellsY = 56.0
    var cellWidth = 18.0
    var cellHeight = 16.0
    var cellGap = 3.0

    /// The day's feet, the one number the card is really about, in the 5×7 face.
    var feetY = 84.0
    var feetScale = 3
    /// Home runs, and then the day's longest under it.
    var homeRunsY = 118.0
    var homeRunsScale = 2
    var longestY = 136.0
    var longestScale = 1

    /// `SHARE`, out of the way in the bottom corner, at label size — where `RESTORE` sits on the
    /// contract card, because it is the same kind of word in the same kind of corner.
    var shareY = 210.0
    var shareScale = 1
    /// Grown to thumb size for the tap test, as the scoreboard tap is.
    var sharePad = 10.0

    /// The shortest drag that counts as a slice rather than a tap. Both leave; the distinction
    /// only matters for `SHARE`, which a tap can hit and a slice across the card should not.
    var minimumSliceLength = 12.0

    public init() {}
    public static let standard = WarmUpCardLayout()
}

/// The Warm Up's result card (DESIGN.md §18): the day's number, its ten pitches as ten cells,
/// the feet they came to, and the way out. Shown by hard cut when the tenth pitch's hold has
/// played out, with the machine standing still behind it — the career windup is already there,
/// so **any slice or tap leaves** and lands straight in it.
///
/// Not a menu: nothing to scroll, nothing to choose, no timer. `SHARE` is the one word that does
/// something other than leave, and it opens the system sheet rather than anything of our own.
final class WarmUpCardScene: CanvasScene {
    override var ticksMachine: Bool { false }

    var layout = WarmUpCardLayout.standard

    /// The cell colour for each outcome, borrowed by role from the one palette line: the
    /// scoreboard's yellow for the one that matters, the wall's dirt for a ball that hit it,
    /// grass for a ball that stayed in it, chalk for a swing through it, ink for one left alone.
    private static func colour(for outcome: WarmUpOutcome) -> Palette.RGBA8 {
        switch outcome {
        case .homeRun: return Palette.score
        case .offTheWall: return Palette.dirt
        case .inPlay: return Palette.grassA
        case .swingAndMiss: return Palette.chalk
        case .taken: return Palette.ink
        }
    }

    // MARK: - Drawing

    override func render(into canvas: PixelCanvas) {
        guard let controller, let result = controller.finishedWarmUp else { return }
        let width = Double(canvas.width)
        let centre = (width / 2).rounded()
        let l = layout

        canvas.fill(Palette.ink)
        let panelX = (centre - l.panelWidth / 2).rounded()
        canvas.rect(panelX, l.panelTop, l.panelWidth, l.panelHeight, Palette.wall)
        frame(canvas, panelX + l.panelInset, l.panelTop + l.panelInset,
              l.panelWidth - l.panelInset * 2, l.panelHeight - l.panelInset * 2, Palette.chalk)

        centred(canvas, "WARM UP \(result.number())", y: l.titleY, scale: l.titleScale,
                Palette.score, centre)

        cells(canvas, result: result, centre: centre)

        let feet = "\(WarmUp.grouped(result.totalFeet)) FT"
        centred5(canvas, feet, y: l.feetY, scale: l.feetScale, Palette.chalk, centre)

        let homeRuns = "\(result.homeRuns) \(result.homeRuns == 1 ? "HOME RUN" : "HOME RUNS")"
        centred(canvas, homeRuns, y: l.homeRunsY, scale: l.homeRunsScale, Palette.chalk, centre)
        centred(canvas, "LONGEST \(WarmUp.grouped(result.longestFeet)) FT", y: l.longestY,
                scale: l.longestScale, Palette.chalk, centre)

        canvas.t3(safeLeft + 8, l.shareY, "SHARE", Palette.chalk, scale: l.shareScale)
    }

    /// One cell per pitch, in the order they were thrown. A chalk frame around every one, so a
    /// swing and a miss (chalk) and a pitch left alone (ink) are still two different pictures.
    private func cells(_ canvas: PixelCanvas, result: WarmUpResult, centre: Double) {
        let l = layout
        let count = Double(result.pitches.count)
        guard count > 0 else { return }
        let total = count * l.cellWidth + (count - 1) * l.cellGap
        var x = (centre - total / 2).rounded()
        for p in result.pitches {
            canvas.rect(x, l.cellsY, l.cellWidth, l.cellHeight, Self.colour(for: p.outcome))
            frame(canvas, x, l.cellsY, l.cellWidth, l.cellHeight, Palette.chalk)
            x += l.cellWidth + l.cellGap
        }
    }

    /// Four rects, because a rectangle outline is the only other outline this canvas draws.
    private func frame(_ canvas: PixelCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double,
                       _ colour: Palette.RGBA8) {
        canvas.rect(x, y, w, 1, colour)
        canvas.rect(x, y + h - 1, w, 1, colour)
        canvas.rect(x, y, 1, h, colour)
        canvas.rect(x + w - 1, y, 1, h, colour)
    }

    private func centred(_ canvas: PixelCanvas, _ text: String, y: Double, scale: Int,
                         _ colour: Palette.RGBA8, _ centre: Double) {
        let width = Double(text.count * 4 * scale) - Double(scale)   // no gap after the last glyph
        canvas.t3((centre - width / 2).rounded(), y, text, colour, scale: scale)
    }

    private func centred5(_ canvas: PixelCanvas, _ text: String, y: Double, scale: Int,
                          _ colour: Palette.RGBA8, _ centre: Double) {
        let width = Double(text.count * 6 * scale) - Double(scale)
        canvas.t5((centre - width / 2).rounded(), y, text, colour, scale: scale)
    }

    // MARK: - Input: anything leaves, except the one word in the corner

    private var dragStart: CGPoint?
    private var dragLast: CGPoint?
    private var left = false

    private func designPoint(for touch: UITouch) -> CGPoint {
        let p = touch.location(in: self)
        return CGPoint(x: p.x, y: size.height - p.y)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        dragStart = designPoint(for: touch)
        dragLast = dragStart
        left = false
    }

    /// A slice leaves the moment it is long enough to be one: this card is not something to be
    /// held down on.
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let start = dragStart, !left else { return }
        let p = designPoint(for: touch)
        dragLast = p
        guard hypot(p.x - start.x, p.y - start.y) >= layout.minimumSliceLength else { return }
        left = true
        controller?.leaveWarmUpCard()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer { dragStart = nil; dragLast = nil }
        guard let start = dragStart, !left else { return }
        let end = dragLast ?? start
        if hypot(end.x - start.x, end.y - start.y) < layout.minimumSliceLength, isShareTap(start) {
            controller?.shareWarmUp()
            return
        }
        controller?.leaveWarmUpCard()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        dragStart = nil
        dragLast = nil
    }

    private func isShareTap(_ p: CGPoint) -> Bool {
        let x = safeLeft + 8
        let width = Double("SHARE".count * 4 * layout.shareScale)
        let pad = layout.sharePad
        return p.x >= x - pad && p.x <= x + width + pad
            && p.y >= layout.shareY - pad && p.y <= layout.shareY + Double(5 * layout.shareScale) + pad
    }
}
