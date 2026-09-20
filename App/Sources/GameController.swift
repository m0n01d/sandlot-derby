import SpriteKit
import DerbyCore

/// Owns the one `DerbyMachine` and both scenes. Ticks the machine once per frame and turns its
/// `Transition`s into `SKView.presentScene(_:)` calls — the hard camera cut. Scenes are pure
/// renderers and gesture sources; all game state lives here, in `machine`.
@MainActor
final class GameController {
    private(set) var machine: DerbyMachine
    let atBatScene: AtBatScene
    let wideScene: WideScene
    let statsScene: StatsScene
    private weak var view: SKView?

    init(seed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)) {
        let save = SaveStore.load()
        var startingTally = save?.tally ?? Tally()
        #if DEBUG
        if let n = Self.debugStartingStreak { startingTally = Self.tally(withHomeRunStreak: n) }
        #endif
        machine = DerbyMachine(seed: seed,
                               park: save.map { Park.generate(number: $0.parkNumber) } ?? .first,
                               tally: startingTally)
        atBatScene = AtBatScene()
        wideScene = WideScene()
        statsScene = StatsScene()
        atBatScene.controller = self
        wideScene.controller = self
        statsScene.controller = self
    }

    /// Written at every beat change, so at worst a second or so of `secondsPlayed` is lost.
    private func persist() {
        SaveStore.save(SaveState(parkNumber: machine.park.number, tally: machine.tally))
    }

    // MARK: - The stats board

    /// Hard cut to the board. The machine stops ticking while it is up (`StatsScene.ticksMachine`).
    func showStats() {
        guard let view, view.scene !== statsScene else { return }
        view.presentScene(statsScene)
    }

    /// The board is only ever opened from the at-bat view, so that is where it returns.
    func hideStats() {
        guard let view, view.scene === statsScene else { return }
        view.presentScene(atBatScene)
    }

    /// Called once, from `GameView.makeUIView`. Presents the initial (at-bat) scene.
    func attach(to view: SKView) {
        self.view = view
        guard view.scene == nil else { return }
        updateLayout(viewSize: view.bounds.size)
        view.presentScene(atBatScene)
    }

    /// Scene size = (max(320, round(224 × aspect)), 224), `.aspectFit`. Called on every layout
    /// pass by `SandlotSKView.layoutSubviews`.
    func updateLayout(viewSize: CGSize, safeArea: UIEdgeInsets = .zero) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        let aspect = viewSize.width / viewSize.height
        let width = max(320, (224 * aspect).rounded())
        let size = CGSize(width: width, height: 224)
        let designPerPoint = 224 / Double(viewSize.height)
        for scene in [atBatScene, wideScene, statsScene] as [CanvasScene] {
            scene.size = size
            scene.scaleMode = .aspectFit
            scene.safeLeft = (Double(safeArea.left) * designPerPoint).rounded()
            scene.safeRight = (Double(safeArea.right) * designPerPoint).rounded()
        }
    }

    /// Advances the pure game clock and turns its transitions into hard camera cuts. Called
    /// from whichever scene is currently presented, inside its own `update(_:)`.
    func tick(_ dt: TimeInterval) {
        let clamped = min(dt, 1.0 / 20.0)
        let beatBefore = machine.beat
        let transitions = machine.tick(clamped)
        if machine.beat != beatBefore { persist() }
        #if DEBUG
        // `-showstats`: cut to the board once a robot career is worth looking at (screenshots).
        if Self.showStatsForScreenshots, machine.beat == .windup, machine.tally.pitches >= 12 {
            Self.showStatsForScreenshots = false
            showStats()
            return
        }
        #endif
        let flash = transitions.contains(.flash)
        for transition in transitions {
            switch transition {
            case .cutToWide:
                if flash { wideScene.flashNextFrame = true }
                view?.presentScene(wideScene)
            case .cutToAtBat:
                if flash { atBatScene.flashNextFrame = true }
                view?.presentScene(atBatScene)
            case .pitchThrown:
                streakAtThePitch = machine.tally.homeRunStreak
                haptics.prepare()
                sound.stopOrgan()            // and then silence: nothing sounds during the pitch
            case .called(let call):
                if call == .strike {
                    sound.calledStrike()
                    mournStreak(after: 0.5)
                } else {
                    sound.calledBall()
                }
            case .clearedWall:
                sound.homeRun(size: homeRunSize)
                haptics.homeRun()
                // A pop per shell, mixed under the cheer. No extra haptic: `.success` just fired.
                if let show = machine.fireworks { sound.fireworks(show, rules: machine.fireworksRules) }
            case .hitWall:
                sound.offTheWall()
                haptics.offTheWall()
            case .landed:
                if machine.flight?.homeRun != true { sound.landed() }     // a home run lands out of earshot
            case .calledUp:
                sound.calledUp()
            case .parkChanged, .flash:
                break
            }
        }
        // The streak is already 0 in the tally from the moment of contact; the sad notes wait for
        // the landing number, so they cannot spoil the flight.
        if machine.beat == .result, beatBefore != .result {
            if machine.flight?.homeRun != true {
                mournStreak(after: 0.35)
            } else if machine.tally.homeRunStreak == 2 {
                sound.chargePrompt()         // two straight: one more starts the fireworks (§17)
            }
        }
    }

    // MARK: - Sound and haptics (DESIGN.md §11)

    private let sound = SoundBoard()
    private let haptics = Haptics()
    private var streakAtThePitch = 0

    /// How well the ball was hit, 0…1, from its exit velocity: what the bat should sound like.
    private var contactStrength: Double {
        guard let launch = machine.launch else { return 0 }
        return (launch.exitVelocityMPH - machine.sliceRules.exitVelocityBase) / machine.sliceRules.exitVelocitySpan
    }

    /// How far past the wall a home run is going to land, 0…1 over 100 ft: how loud the crowd gets.
    private var homeRunSize: Double {
        guard let flight = machine.flight else { return 0 }
        return (flight.distanceFeet - machine.park.wallDistanceFeet) / 100
    }

    /// Three notes down, only for a streak worth mourning.
    private func mournStreak(after seconds: Double) {
        guard streakAtThePitch >= 3 else { return }
        streakAtThePitch = 0
        sound.streakOver(after: seconds)
    }

    // MARK: - Slice input entry points, used by AtBatScene.

    /// `DerbyMachine.slice` itself ignores calls made outside `.pitch`.
    func recordSlice(_ crossing: SliceCrossing) {
        let wasPitch = machine.beat == .pitch
        machine.slice(crossing)
        if wasPitch {
            sound.crack(strength: contactStrength)
            haptics.contact(strength: contactStrength)
        }
        persist()
    }

    /// `DerbyMachine.sliceMissed` itself ignores calls made outside `.pitch`.
    func recordMissedSlice() {
        let wasPitch = machine.beat == .pitch
        machine.sliceMissed()
        if wasPitch {
            sound.whiff()
            mournStreak(after: 0.3)
        }
        persist()
    }

    #if DEBUG
    private static var showStatsForScreenshots = ProcessInfo.processInfo.arguments.contains("-showstats")

    /// `-streak <n>`: start the career with a home-run streak of `n` already going, so a shell
    /// count deep in the table (or a finale) can be screenshotted without hitting n home runs in
    /// a row first. Implies `-nosave` (`SaveStore`): a faked streak has no business overwriting,
    /// or being overwritten by, a real one.
    private static var debugStartingStreak: Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-streak"), i + 1 < args.count else { return nil }
        return Int(args[i + 1])
    }

    /// A `Tally` with only `homeRunStreak` (and its running best) set, via the same JSON shape
    /// `SaveStore` and old saves already round-trip through — `Tally.set` is Core-internal, so
    /// this is the one door the app has into a specific starting number.
    private static func tally(withHomeRunStreak n: Int) -> Tally {
        let json = #"{"values":{"homeRunStreak":\#(n),"bestHomeRunStreak":\#(n)}}"#.data(using: .utf8)!
        return (try? JSONDecoder().decode(Tally.self, from: json)) ?? Tally()
    }
    #endif

    /// The ball's position at a given pitch progress, for `Contact.test`'s `ballAt` closure
    /// and for building miss/call markers.
    func ballAt(_ progress: Double) -> BallSample {
        Pitching.ball(machine.pitch, at: progress, rules: machine.pitchingRules)
    }
}
