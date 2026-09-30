import CoreGraphics
import DerbyCore
import Foundation

/// Where the replay screen's one word sits (#42, DESIGN.md §19). Top right, on an ink plate,
/// which is the corner the camera that opened it was in — the thing you tapped becomes the thing
/// you can do. It is also the only corner free in every frame a replay draws: the at-bat view
/// writes top left and bottom left, the flight view top left and bottom right.
struct ReplayScreenLayout {
    var wordY = 8.0
    var wordScale = 1
    /// In from the canvas's own right edge, past the safe area.
    var inset = 8.0
    /// Grown to thumb size for the tap test, as every other corner word is.
    var pad = 12.0
    /// A touch that wanders further than this was not a tap on the word.
    var tapSlack = 8.0
    static let standard = ReplayScreenLayout()
}

/// The instant replay (#42): the swing again, on the glass, in real time.
///
/// Presented by hard cut with the live machine standing still behind it, exactly the way the
/// stats board and the two cards are. Nothing is rendered or encoded to watch one — the frames
/// cost what a frame of the game costs, because they *are* a frame of the game: `ReplayPlayback`
/// ticks a private rebuilt machine and draws it through the same two scenes the player saw. That
/// is the whole of Dwight's second complaint fixed by construction: "its VEEERRRRYYY slow to
/// export on my ipad mini 6. it makes the game laggy and jittery while its clipping in the
/// background." Nothing clips in the background any more; nothing clips at all until `SHARE`.
///
/// It loops, resting `ReplayRules.loopHoldSeconds` on the landing number. One word, `SHARE`, in
/// the corner; a tap anywhere else is a hard cut back to the game, which resumes where it paused.
final class ReplayScene: Painter {
    /// The game stands still behind this, like the board and the cards.
    override var ticksMachine: Bool { false }

    var layout = ReplayScreenLayout.standard
    private(set) var replay: Replay?
    private var playback: ReplayPlayback?
    private var holdRemaining = 0.0

    /// Starts a record playing from its first frame. Called by `GameController` on the way in.
    func begin(_ replay: Replay, rules: ReplayRules) {
        self.replay = replay
        playback = ReplayPlayback(replay, rules: rules)
        holdRemaining = rules.loopHoldSeconds
        applySize()
    }

    /// Time spent off screen is not replay time: the host's `dt` is zero on the first frame
    /// after the cut in.
    override func didAppear() {
        applySize()
    }

    override func sizeDidChange() {
        applySize()
    }

    private func applySize() {
        playback?.resize(width: max(1, Int(size.width.rounded())),
                         height: max(1, Int(size.height.rounded())),
                         safeLeft: safeLeft, safeRight: safeRight)
    }

    /// The replay's own clock: real seconds, clamped the way `GameController.tick` clamps the
    /// game's, so a stall between frames does not skip half the flight.
    override func advance(_ realDt: Double) {
        let dt = min(realDt, 1.0 / 20.0)
        // The loop stops dead while a clip is being written: the frame the player was looking at
        // when they asked stays up under `SAVING`, and the export gets the whole machine instead
        // of sharing it with a replay nobody is watching.
        if let playback, controller?.isExportingReplay != true {
            if playback.isFinished {
                holdRemaining -= dt
                if holdRemaining <= 0 {
                    playback.restart()
                    holdRemaining = (controller?.replayRules ?? .standard).loopHoldSeconds
                }
            } else {
                playback.advance(dt)
            }
        }
    }

    override func render(into canvas: PixelCanvas) {
        guard let playback else { return }
        // Not on the flash frame: one white frame is one white frame, here as much as in the file.
        guard !playback.render(into: canvas) else { return }
        word(into: canvas)
    }

    /// One plain word, on the ink plate every label in this game is written on. `SAVING` while
    /// the clip is being written, so the wait says what it is rather than nothing.
    private func word(into canvas: PixelCanvas) {
        let text = controller?.isExportingReplay == true ? "SAVING" : "SHARE"
        let width = Double(text.count * 4 * layout.wordScale) - Double(layout.wordScale)
        let x = (Double(canvas.width) - safeRight - layout.inset - width).rounded()
        canvas.rect(x - 2, layout.wordY - 2, width + 3, Double(5 * layout.wordScale) + 4, Palette.ink)
        canvas.t3(x, layout.wordY, text, Palette.chalk, scale: layout.wordScale)
    }

    // MARK: - Input: the word shares, anything else leaves

    private var dragStart: CGPoint?
    private var dragLast: CGPoint?

    override func touchBegan(at point: CGPoint) {
        dragStart = point
        dragLast = dragStart
    }

    override func touchMoved(to point: CGPoint) {
        dragLast = point
    }

    override func touchEnded() {
        defer { dragStart = nil; dragLast = nil }
        guard let start = dragStart, controller?.isExportingReplay != true else { return }
        let end = dragLast ?? start
        if hypot(end.x - start.x, end.y - start.y) < layout.tapSlack, isWordTap(start) {
            controller?.exportAndShareReplay()
            return
        }
        controller?.leaveReplay()
    }

    override func touchCancelled() {
        dragStart = nil
        dragLast = nil
    }

    /// The word's rectangle in design pixels, y down, for the host to turn into the view's own
    /// points, so an iPad's share popover points at the thing that was tapped instead of hanging
    /// off the middle of the screen (`DerbyHost.viewRect(of:in:)`).
    var wordRect: CGRect {
        let text = controller?.isExportingReplay == true ? "SAVING" : "SHARE"
        let width = Double(text.count * 4 * layout.wordScale)
        let x = Double(size.width) - safeRight - layout.inset - width
        return CGRect(x: x, y: layout.wordY, width: width, height: Double(5 * layout.wordScale))
    }

    private func isWordTap(_ p: CGPoint) -> Bool {
        let text = controller?.isExportingReplay == true ? "SAVING" : "SHARE"
        let width = Double(text.count * 4 * layout.wordScale)
        let x = Double(size.width) - safeRight - layout.inset - width
        let pad = layout.pad
        return p.x >= x - pad && p.x <= x + width + pad
            && p.y >= layout.wordY - pad && p.y <= layout.wordY + Double(5 * layout.wordScale) + pad
    }
}
