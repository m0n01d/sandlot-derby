import DerbyCore
import SpriteKit

/// One recorded swing, played: the lead-in, the contact freeze, the one white frame, the flight
/// across both cameras, the landing number (#42, DESIGN.md §19).
///
/// Both the replay screen (`ReplayScene`, in real time, on the glass) and the exported clip
/// (`ReplayRenderer`, at a fixed 1/60, off screen) drive this, so what the player watches and
/// what is written to the file are the same picture by construction rather than by two pieces of
/// code agreeing. It draws through off-screen copies of `AtBatScene` and `WideScene` — the very
/// same `render(into:)` the player saw, never a second copy of it.
///
/// **The hand-over.** The lead-in ticks a machine built by `Replay.leadInMachine(from:)` and then
/// throws it away: the freeze and everything after it are drawn from `Replay.machine(from:)`,
/// exactly as they were before the lead-in existed. So nothing the lead-in accumulates can drift
/// into the clip, and #33's frame-for-frame tests still hold word for word
/// (`ReplayLeadInTests.testTheLeadInCannotDriftIntoTheClip`).
@MainActor
final class ReplayPlayback {

    let replay: Replay
    private let rules: ReplayRules

    private let atBat = AtBatScene()
    private let wide = WideScene()

    private var machine: DerbyMachine
    private var current: CanvasScene
    /// How much pitch is left before the slash. Zero once the hand-over has happened.
    private var leadInRemaining: Double
    /// The next frame is the white one of the hard cut (DESIGN.md §3).
    private var pendingFlash = false
    /// True once the result hold is over. The machine is not ticked past that point, so the last
    /// frame drawn stands — which is what the screen's short hold on the landing number rests on.
    private(set) var isFinished = false

    init(_ replay: Replay, rules: ReplayRules = .standard) {
        self.replay = replay
        self.rules = rules
        for scene in [atBat, wide] as [CanvasScene] {
            scene.isOffScreen = true
            scene.scaleMode = .aspectFit
        }
        leadInRemaining = replay.leadInSeconds(rules: rules)
        machine = leadInRemaining > 0
            ? Replay.leadInMachine(from: replay, rules: rules)
            : Replay.machine(from: replay)
        current = atBat
        if leadInRemaining > 0 {
            atBat.showReplayStroke(replay.stroke(secondsBeforeContact: leadInRemaining))
        } else {
            atBat.restoreContactVisual(from: replay)
        }
    }

    /// The frame both inner scenes draw into. A clip is always the design frame
    /// (`ReplayClipRules`); the screen is whatever the phone is, because a replay watched on the
    /// glass is the game again and the game is that wide.
    func resize(width: Int, height: Int, safeLeft: Double, safeRight: Double) {
        for scene in [atBat, wide] as [CanvasScene] {
            scene.size = CGSize(width: width, height: height)
            scene.safeLeft = safeLeft
            scene.safeRight = safeRight
        }
    }

    /// Back to the first frame of the lead-in. The record is the only state there is, so this is
    /// a rebuild and not a rewind — a loop cannot drift away from the first time round.
    func restart() {
        leadInRemaining = replay.leadInSeconds(rules: rules)
        machine = leadInRemaining > 0
            ? Replay.leadInMachine(from: replay, rules: rules)
            : Replay.machine(from: replay)
        current = atBat
        pendingFlash = false
        isFinished = false
        if leadInRemaining > 0 {
            atBat.showReplayStroke(replay.stroke(secondsBeforeContact: leadInRemaining))
        } else {
            atBat.restoreContactVisual(from: replay)
        }
    }

    /// One frame of clock. Tick first, then draw — the order `CanvasScene.update(_:)` uses, so a
    /// replay lands on the same frames the player saw.
    func advance(_ dt: Double) {
        guard !isFinished else { return }

        if leadInRemaining > 0 {
            let step = min(dt, leadInRemaining)
            machine.tick(step)
            leadInRemaining -= step
            if leadInRemaining <= 1e-9 {
                leadInRemaining = 0
                handOverToTheFreeze()
                // Whatever was left of this frame after the pitch ran out belongs to the freeze.
                let carry = dt - step
                if carry > 1e-9 { apply(machine.tick(carry)) }
            } else {
                atBat.showReplayStroke(replay.stroke(secondsBeforeContact: leadInRemaining))
            }
            return
        }

        // Ticked on a copy: the tick that ends the result hold must not be the one that is drawn.
        var next = machine
        let transitions = next.tick(dt)
        guard !transitions.contains(.cutToAtBat) else {
            isFinished = true                 // the landing number stands; the clip stops here
            return
        }
        machine = next
        apply(transitions)
    }

    /// Draws this frame. Returns true when it was the one white frame of the hard cut, so a
    /// caller that writes over the picture (the screen's corner word) can leave it alone — the
    /// flash has to stay a whole white frame on the glass as well as in the file (DESIGN.md §3).
    @discardableResult
    func render(into canvas: PixelCanvas) -> Bool {
        if pendingFlash {
            canvas.fill(Palette.chalk)
            pendingFlash = false
            return true
        }
        current.replayMachine = machine
        current.render(into: canvas)
        return false
    }

    /// Which camera this frame is, for anything that has to know (the screen's own corner word
    /// sits above both, so nothing does yet — kept because a crop for vertical video will).
    var isWideCamera: Bool { current === wide }

    // MARK: - Private

    private func handOverToTheFreeze() {
        machine = Replay.machine(from: replay)
        atBat.showReplayStroke(nil)
        atBat.restoreContactVisual(from: replay)
        current = atBat
    }

    private func apply(_ transitions: [Transition]) {
        for transition in transitions {
            switch transition {
            case .flash: pendingFlash = true
            case .cutToWide: current = wide
            default: break
            }
        }
    }
}
