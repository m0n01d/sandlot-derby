import CoreGraphics
import DerbyCore

/// One camera or card of the game: it draws a whole frame into a `PixelCanvas` and answers a
/// finger, and that is all it does (#35). No SpriteKit anywhere in it — the texture, the frame
/// clock and the touches it is fed all belong to a `DerbyHost`, so the same painter can be put
/// on the glass by `SpriteKitHost`, drawn off screen by `ReplayPlayback`, or one day handed to a
/// host that is neither (`docs/watch.md` W1, `docs/ports.md` P0).
///
/// Painters own no game state: every `render(into:)` reads `renderMachine` and nothing else.
@MainActor
class Painter {
    weak var controller: GameController?

    /// Set by `GameController` right before `DerbyHost.present(_:)` on a `.flash` transition;
    /// consumed by this painter's very next frame instead of its normal draw — the one white
    /// frame of the hard cut (DESIGN.md §3).
    var flashNextFrame = false

    /// The canvas this painter draws, in design pixels: (max(320, round(224 × aspect)), 224) on
    /// the glass, the design frame in a clip. Set by the host, or by `ReplayPlayback` off screen.
    var size = CGSize.zero

    /// The view's horizontal safe-area insets in design pixels, set by `GameController` on
    /// layout. Backgrounds ignore them; anything that must be seen stays inside.
    var safeLeft = 0.0
    var safeRight = 0.0

    /// Set by `ReplayPlayback` (#4, #42) on an off-screen copy of a painter, so the very same
    /// drawing code redraws a recorded moment from a rebuilt machine instead of the live one.
    /// Nil in the game, where the controller's machine is the only one there is.
    var replayMachine: DerbyMachine?

    /// The machine this frame is drawn from. Every `render(into:)` reads this and nothing else.
    var renderMachine: DerbyMachine? { replayMachine ?? controller?.machine }

    /// True for a painter the replay renderer made: no host, no frame clock, no input, and it
    /// draws into the renderer's canvas.
    var isOffScreen = false

    /// False for a painter the game stands still behind (the stats board).
    var ticksMachine: Bool { true }

    /// One whole frame: the white one of a hard cut if one is owed, the painter's own drawing
    /// otherwise. The host calls this after it has ticked the machine and before it blits.
    final func drawFrame(into canvas: PixelCanvas) {
        if flashNextFrame {
            canvas.fill(Palette.chalk)
            flashNextFrame = false
        } else {
            // No `CLIP` word any more: nothing is drawn or encoded while the game is being
            // played, so there is nothing for it to announce (#42). The one word a clip puts on
            // the screen now is `SAVING`, on the replay screen, which owns it.
            render(into: canvas)
        }
    }

    /// Subclasses draw one whole frame here, reading only from `renderMachine`.
    func render(into canvas: PixelCanvas) {}

    // MARK: - Host callbacks

    /// This painter has just been put on the glass by a hard cut.
    func didAppear() {}

    /// `size` has just changed.
    func sizeDidChange() {}

    /// A painter that keeps a clock of its own (the replay screen) advances it here, once per
    /// real frame while it is up, before the machine is ticked and the frame is drawn. `dt` is
    /// real seconds since the last frame, unclamped, and zero on the first frame after a cut.
    func advance(_ dt: Double) {}

    // MARK: - Input, in design pixels, y down

    /// A finger touched down. Only the first finger of a touch is ever reported.
    func touchBegan(at point: CGPoint) {}
    /// The finger moved.
    func touchMoved(to point: CGPoint) {}
    /// The finger lifted.
    func touchEnded() {}
    /// The system took the touch away.
    func touchCancelled() {}
}
