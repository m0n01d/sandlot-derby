import CoreGraphics
import Foundation

/// Where the contract card's lines sit, in design units measured from the centre of the canvas
/// (DESIGN.md §8, §16). The canvas is at least 320 wide, so the card is centred rather than
/// pinned: on a wide phone the panel sits in the middle and the corner word stays in the corner.
/// Every number here is a knob.
struct ContractCardLayout {
    /// The panel the card is printed on, centred horizontally.
    var panelWidth = 224.0
    var panelTop = 24.0
    var panelHeight = 152.0
    /// The chalk rule drawn just inside the panel.
    var panelInset = 3.0

    /// `THE SHOW`, the only thing on the card as big as the scoreboard's own heading.
    var titleY = 36.0
    var titleScale = 3
    /// The price. Whatever the store charges today, drawn in the 5×7 face because that is the
    /// only one with room for a `$` that cannot be read as a `5` (DESIGN.md §16).
    var priceY = 60.0
    var priceScale = 2
    /// A price the 5×7 face cannot spell arrives as an ISO code (`BRL 14.90`) and is drawn in
    /// the 3×5 face instead, one step larger so it keeps roughly the same weight.
    var priceFallbackScale = 3
    /// `ONE TIME`.
    var termY = 92.0
    var termScale = 2
    /// `NO ADS  NO SUBSCRIPTION`, the fine print that is not fine print.
    var promiseY = 108.0
    var promiseScale = 1

    /// The dotted line. Half-width either side of centre, and the `X` that ends it.
    var signatureY = 140.0
    var signatureHalfWidth = 80.0
    var signatureMarkGap = 8.0
    var signatureMarkScale = 2
    /// How far above and below the line a slice still counts, and how far past its ends.
    var signatureBand = 10.0
    var signatureOverhang = 8.0
    /// The shortest drag that can sign: a tap that happens to land on the line never buys.
    var minimumSliceLength = 12.0

    /// The one word the card says when a purchase did not happen.
    var statusY = 158.0
    var statusScale = 2

    /// `RESTORE`, out of the way in the bottom corner, at label size.
    var restoreY = 210.0
    var restoreScale = 1
    /// Grown to thumb size for the tap test, as the scoreboard tap is.
    var restorePad = 10.0

    public init() {}
    public static let standard = ContractCardLayout()
}

/// The contract card (DESIGN.md §16): the call-up that has to be signed. A scoreboard in the
/// bitmap face — `THE SHOW`, the price, `ONE TIME`, `NO ADS  NO SUBSCRIPTION` — and a dotted
/// line ending in `X`. **Slicing the line signs it**, because a slice is the only input the game
/// has. A tap anywhere off the line declines, and declining costs nothing: Triple-A goes on
/// counting every stat and the streak.
///
/// Not a menu: there is nothing to scroll, nothing to choose and no timer. The game stands still
/// behind it, exactly as it does behind the stats board.
final class ContractScene: Painter {
    override var ticksMachine: Bool { false }

    var layout = ContractCardLayout.standard

    /// The drag in progress, in design space, and whether it has already crossed the line. One
    /// slice signs once however far the finger carries on.
    private var dragStart: CGPoint?
    private var dragLast: CGPoint?
    private var signedThisDrag = false

    /// Called by `GameController` before every presentation: a card offered again from the stats
    /// board starts with nothing to say, not with the last run's `CANCELLED` still on it.
    func reset() {
        dragStart = nil
        dragLast = nil
        signedThisDrag = false
        #if DEBUG
        framesOnCard = 0
        #endif
        controller?.store.clearPhase()
    }

    // MARK: - Drawing

    override func render(into canvas: PixelCanvas) {
        guard let controller else { return }
        let store = controller.store
        let width = Double(canvas.width)
        let centre = (width / 2).rounded()
        let l = layout

        canvas.fill(Palette.ink)
        let panelX = (centre - l.panelWidth / 2).rounded()
        canvas.rect(panelX, l.panelTop, l.panelWidth, l.panelHeight, Palette.wall)
        frame(canvas, panelX + l.panelInset, l.panelTop + l.panelInset,
              l.panelWidth - l.panelInset * 2, l.panelHeight - l.panelInset * 2, Palette.chalk)

        centred(canvas, "THE SHOW", y: l.titleY, scale: l.titleScale, Palette.score, centre)
        if let price = store.priceText {
            if PixelCanvas.hasGlyphs5(for: price) {
                centred5(canvas, price, y: l.priceY, scale: l.priceScale, Palette.chalk, centre)
            } else {
                centred(canvas, price, y: l.priceY, scale: l.priceFallbackScale, Palette.chalk, centre)
            }
        }
        centred(canvas, "ONE TIME", y: l.termY, scale: l.termScale, Palette.chalk, centre)
        centred(canvas, "NO ADS  NO SUBSCRIPTION", y: l.promiseY, scale: l.promiseScale,
                Palette.chalk, centre)

        // The line to sign, and the X that ends it.
        let x0 = centre - l.signatureHalfWidth, x1 = centre + l.signatureHalfWidth
        canvas.dashed(x0, l.signatureY, x1, l.signatureY, Palette.chalk)
        canvas.t3(x1 + l.signatureMarkGap, l.signatureY - Double(l.signatureMarkScale * 5) / 2,
                  "X", Palette.score, scale: l.signatureMarkScale)

        if let word = Self.word(for: store.phase) {
            centred(canvas, word, y: l.statusY, scale: l.statusScale, Palette.chalk, centre)
        }

        canvas.t3(safeLeft + 8, l.restoreY, "RESTORE", Palette.chalk, scale: l.restoreScale)

        #if DEBUG
        autoSliceIfAsked()
        #endif
    }

    #if DEBUG
    /// `-autosign` signs the card once, a second after it comes up, so that a screenshot run can
    /// reach what signing leads to. Deliberately not part of `-autoslice`: a robot that swings at
    /// every pitch must not also buy things. The stroke is synthetic but the hit test is the real
    /// one — if `crossesSignature` is wrong nothing is signed and the card just sits there, which
    /// is the failure worth catching.
    private func autoSliceIfAsked() {
        guard Self.autoSign, !signedThisDrag else { return }
        framesOnCard += 1
        guard framesOnCard > 60 else { return }
        let x = signatureCentre
        let from = CGPoint(x: x - 20, y: layout.signatureY - 20)
        let to = CGPoint(x: x + 20, y: layout.signatureY + 20)
        guard crossesSignature(from: from, to: to) else { return }
        signedThisDrag = true
        controller?.signContract()
    }

    private static let autoSign = ProcessInfo.processInfo.arguments.contains("-autosign")
    private var framesOnCard = 0
    #endif

    /// One plain word, or none. No sale banner, no countdown, no badge — §16 rules all three out.
    /// Three real causes where there used to be one `.failed` (#47): a network drop, a store that
    /// answered with nothing to sell, and a restore that found nothing to restore.
    private static func word(for phase: Store.Phase) -> String? {
        switch phase {
        case .idle: return nil
        case .purchasing: return nil        // the system sheet is over the card already
        case .pending: return "PENDING"
        case .cancelled: return "CANCELLED"
        case .noConnection: return "NO CONNECTION"
        case .notAvailable: return "NOT AVAILABLE"
        case .nothingToRestore: return "NOTHING TO RESTORE"
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

    // MARK: - Input: one slice signs, one tap declines

    override func touchBegan(at point: CGPoint) {
        dragStart = point
        dragLast = dragStart
        signedThisDrag = false
    }

    override func touchMoved(to point: CGPoint) {
        guard let start = dragStart, let last = dragLast else { return }
        let p = point
        dragLast = p
        guard !signedThisDrag, controller?.store.phase != .purchasing else { return }
        guard hypot(p.x - start.x, p.y - start.y) >= layout.minimumSliceLength else { return }
        guard crossesSignature(from: last, to: p) else { return }
        signedThisDrag = true
        controller?.signContract()
    }

    override func touchEnded() {
        defer { dragStart = nil; dragLast = nil }
        guard let start = dragStart, !signedThisDrag else { return }
        let end = dragLast ?? start
        // A tap, not a slice.
        guard hypot(end.x - start.x, end.y - start.y) < layout.minimumSliceLength else { return }
        if isRestoreTap(start) {
            controller?.restoreContract()
            return
        }
        // A tap that landed on the line was aimed at it: it neither signs nor declines, so a
        // missed stroke costs the player nothing and buys them nothing. Anywhere else declines.
        guard !inSignatureBand(start) else { return }
        controller?.declineContract()
    }

    override func touchCancelled() {
        dragStart = nil
        dragLast = nil
    }

    /// The line is horizontal, so a crossing is a straddle in y with the crossing point inside
    /// the line's span. Exact, and it costs nothing.
    private func crossesSignature(from a: CGPoint, to b: CGPoint) -> Bool {
        let y = layout.signatureY
        let da = a.y - y, db = b.y - y
        guard (da < 0 && db >= 0) || (da >= 0 && db < 0) else { return false }
        let t = da / (da - db)
        let x = a.x + (b.x - a.x) * t
        return abs(x - signatureCentre) <= layout.signatureHalfWidth + layout.signatureOverhang
    }

    private func inSignatureBand(_ p: CGPoint) -> Bool {
        abs(p.y - layout.signatureY) <= layout.signatureBand
            && abs(p.x - signatureCentre) <= layout.signatureHalfWidth + layout.signatureOverhang
    }

    private func isRestoreTap(_ p: CGPoint) -> Bool {
        let x = safeLeft + 8
        let width = Double("RESTORE".count * 4 * layout.restoreScale)
        let pad = layout.restorePad
        return p.x >= x - pad && p.x <= x + width + pad
            && p.y >= layout.restoreY - pad && p.y <= layout.restoreY + Double(5 * layout.restoreScale) + pad
    }

    private var signatureCentre: Double { (Double(size.width) / 2).rounded() }
}
