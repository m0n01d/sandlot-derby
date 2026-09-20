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
    let contractScene: ContractScene
    /// The one purchase (DESIGN.md §16). Read by the card and the stats board for the price.
    let store = Store()
    private weak var view: SKView?

    /// The card is offered automatically exactly once per career; after that it is a row on the
    /// stats board and nothing else. Persisted, so declining survives a relaunch.
    private(set) var contractOffered: Bool
    /// This save was already in The Show on the first launch of the paywalled build, so it is
    /// entitled for good. Only a beta tester can be in that state (§16).
    private let grandfathered: Bool

    init(seed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)) {
        let save = SaveStore.load()
        #if DEBUG
        // `-contract`: start where the card is earned, so it can be reached in one home run.
        // `-park n`: drop into one park for a screenshot.
        let startPark = Self.startInTripleA ? Park.generate(number: League.theShow.rawValue - 1)
            : Self.debugParkNumber.map { Park.generate(number: $0) }
        #else
        let startPark: Park? = nil
        #endif
        var startingTally = save?.tally ?? Tally()
        #if DEBUG
        if let n = Self.debugStartingStreak { startingTally = Self.tally(withHomeRunStreak: n) }
        #endif
        machine = DerbyMachine(seed: seed,
                               park: startPark ?? save.map { Park.generate(number: $0.parkNumber) } ?? .first,
                               tally: startingTally)
        #if DEBUG
        contractOffered = Self.startDeclined || (save?.contractOffered ?? false)
        #else
        contractOffered = save?.contractOffered ?? false
        #endif
        // Grandfathering (§16): asked once of each save, on the first launch that can ask it.
        // A blob written before the paywall has no answer in it, so the park number is the answer.
        grandfathered = save?.grandfathered ?? ((save?.parkNumber ?? 0) >= League.theShow.rawValue)
        atBatScene = AtBatScene()
        wideScene = WideScene()
        statsScene = StatsScene()
        contractScene = ContractScene()
        atBatScene.controller = self
        wideScene.controller = self
        statsScene.controller = self
        contractScene.controller = self
        applyCeiling()
        persist()                                   // the grandfathering answer, written down
        store.onEntitlementChange = { [weak self] in self?.entitlementChanged() }
        Task { await store.start() }
    }

    /// Written at every beat change, so at worst a second or so of `secondsPlayed` is lost.
    private func persist() {
        SaveStore.save(SaveState(parkNumber: machine.park.number, tally: machine.tally,
                                 contractOffered: contractOffered, grandfathered: grandfathered))
    }

    // MARK: - The Show, and what stands between (DESIGN.md §16)

    /// Bought, restored, shared by a family member, or grandfathered in. Core knows none of this;
    /// it only ever sees a ceiling.
    var isEntitled: Bool { store.isEntitled || grandfathered }

    /// The last park of the minors, from the ladder rather than from the number 3.
    private static let minorsCeiling = League.theShow.rawValue - 1

    /// Entitled: no ceiling. Not entitled: the last minors park — or, after a refund, the park
    /// the player is standing in, because nothing is ever taken away. They just stop advancing.
    private func applyCeiling() {
        machine.parkCeiling = isEntitled ? nil : max(Self.minorsCeiling, machine.park.number)
    }

    /// Signed, restored, a pending purchase landing, a purchase made on another device, a refund.
    /// Lifting the ceiling is all it takes: the machine pays the advance it owes at the next
    /// windup, with no second `.calledUp`.
    private func entitlementChanged() {
        applyCeiling()
        persist()
        if isEntitled, view?.scene === contractScene { leaveContract(flash: true) }
    }

    /// Hard cut to the card. The machine stands still behind it (`ContractScene.ticksMachine`).
    func showContract() {
        guard let view, view.scene !== contractScene else { return }
        contractScene.reset()
        view.presentScene(contractScene)
    }

    /// The home run that cleared Triple-A, for a player who has not bought it. Offered once per
    /// career and never again; afterwards the stats board carries the row.
    private func offerContract() {
        guard !contractOffered, !isEntitled else { return }
        contractOffered = true
        persist()
        showContract()
    }

    func signContract() {
        Task { await store.sign() }
    }

    func restoreContract() {
        Task { await store.restore() }
    }

    /// A tap off the line. Never punished and never nagged: back to Triple-A, which goes on
    /// counting every stat and the streak.
    func declineContract() {
        leaveContract(flash: false)
    }

    /// `flash` is the one white frame that a signature earns (§16); a decline is a plain cut.
    private func leaveContract(flash: Bool) {
        guard let view, view.scene === contractScene else { return }
        atBatScene.flashNextFrame = flash
        view.presentScene(atBatScene)
    }

    #if DEBUG
    private static let arguments = ProcessInfo.processInfo.arguments
    /// `-contract` and `-declined` both start where the card is earned.
    private static let startInTripleA = arguments.contains("-contract") || startDeclined
    /// `-declined`: the card has already been offered and turned down, which is the state the
    /// stats board's row exists for. Not entitled, Triple-A, and the card never offers itself.
    private static let startDeclined = arguments.contains("-declined")
    #endif

    // MARK: - The stats board

    /// Hard cut to the board. The machine stops ticking while it is up (`StatsScene.ticksMachine`).
    /// *Take Me Out to the Ball Game* starts a beat later, if this park has an organ (#17).
    func showStats() {
        guard let view, view.scene !== statsScene else { return }
        view.presentScene(statsScene)
        if machine.hasOrgan { sound.startStatsOrgan() }
    }

    /// The board is only ever opened from the at-bat view, so that is where it returns. The
    /// organ, if it was playing, stops dead — same as when the pitch is thrown.
    func hideStats() {
        guard let view, view.scene === statsScene else { return }
        view.presentScene(atBatScene)
        sound.stopOrgan()
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
        for scene in [atBatScene, wideScene, statsScene, contractScene] as [CanvasScene] {
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
        // Mirror the touch state every frame, not just on touch-down: a slice is "in progress"
        // whenever a finger is on the glass, however it got there (DESIGN.md §3, issue #20).
        machine.sliceInProgress = atBatScene.fingerDown
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
        // `.calledUp` arrives in the same list as the `.cutToAtBat` that would draw over the
        // card, so the offer waits until every transition has been handled.
        var offerTheContract = false
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
                lastSwing = nil                 // the record only lives until the next pitch (#4)
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
                // At the ceiling the park did not change: this is the call-up that has to be
                // signed. Anywhere else it is the ordinary one and there is nothing to sell.
                if machine.isAtCeiling { offerTheContract = true }
            case .calledStrikesInARow:
                if machine.hasOrgan { sound.threeBlindMice() }   // there is no third strike here (#17)
            case .parkChanged, .flash:
                break
            }
        }
        // The streak is already 0 in the tally from the moment of contact; the sad notes wait for
        // the landing number, so they cannot spoil the flight.
        if machine.beat == .result, beatBefore != .result {
            if machine.flight?.homeRun != true {
                mournStreak(after: 0.35)
            } else if machine.tally.homeRunStreak == 2, machine.hasOrgan {
                sound.chargePrompt()         // two straight: one more starts the fireworks (§17)
            }
        }
        if offerTheContract { offerContract() }
        if pendingClipURL != nil { presentPendingClipIfCalm() }
    }

    // MARK: - The replay clip (#4, DESIGN.md §19)

    /// The last swing, as a record that can draw itself again. Kept only until the next pitch is
    /// thrown. Taken for every swing, not just the ones that leave the park: it is a few dozen
    /// bytes, and the alternative is deciding before the flight has been simulated.
    private(set) var lastSwing: Replay?

    /// True while a clip is being drawn. `CanvasScene` puts the one word on the screen for it.
    private(set) var isRenderingReplayClip = false

    /// A finished clip with nowhere to go yet, because the player was already swinging again.
    private var pendingClipURL: URL?

    /// What the long press on the landing number is allowed to do right now (`WideScene`).
    var canShareLastHomeRun: Bool {
        !isRenderingReplayClip && pendingClipURL == nil && machine.beat == .result
            && machine.flight?.homeRun == true && lastSwing != nil
    }

    /// The long press matured. Drawing a clip takes longer than the hold it was asked in, so it
    /// runs behind the game and the sheet arrives whenever it arrives — the next pitch is never
    /// held up for it.
    func shareLastHomeRunClip() {
        guard let replay = lastSwing, !isRenderingReplayClip else { return }
        isRenderingReplayClip = true
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sandlot-derby-park-\(replay.park.number).mp4")
        Task { @MainActor [weak self] in
            defer { self?.isRenderingReplayClip = false }
            do {
                try await ReplayRenderer.write(replay, to: url)
                self?.pendingClipURL = url
                self?.presentPendingClipIfCalm()
            } catch {
                // A clip that could not be made says nothing: there are no toasts in this game.
                print("replay clip failed: \(error)")
            }
        }
    }

    /// The sheet never lands over a swing. If the player is back in the box by the time the clip
    /// is drawn, it waits for the next quiet beat — a miss or a landing number — which is never
    /// more than a pitch away.
    private func presentPendingClipIfCalm() {
        guard let url = pendingClipURL else { return }
        switch machine.beat {
        case .miss, .result:
            pendingClipURL = nil
            ReplayShare.present(url, from: view)
        case .windup, .pitch, .contact, .flight:
            break
        }
    }

    #if DEBUG
    /// `-replay <path>`: with `-autoslice`, write the first home run's clip out and log where it
    /// went, so a clip can be made in a simulator with nothing touching the glass. A path
    /// beginning with `/` is used as given; anything else is a filename in the app's Documents
    /// directory, which is where `simctl get_app_container … data` points. Implies `-nosave`.
    private static let debugReplayPath: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-replay"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()
    private var debugReplayDone = false

    private func writeDebugReplayIfAsked() {
        guard !debugReplayDone, let path = Self.debugReplayPath, let replay = lastSwing,
              machine.flight?.homeRun == true else { return }
        debugReplayDone = true
        let url = path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : URL.documentsDirectory.appendingPathComponent(path)
        isRenderingReplayClip = true
        Task { @MainActor [weak self] in
            defer { self?.isRenderingReplayClip = false }
            do {
                let written = try await ReplayRenderer.write(replay, to: url)
                print("REPLAY CLIP WRITTEN \(written.path)")
            } catch {
                print("REPLAY CLIP FAILED \(error)")
            }
        }
    }
    #endif

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

    /// Three notes down, only for a streak worth mourning. A streak of 5+ gets Chopin instead,
    /// where there is an organ to play him (#17) — a sandlot just gets the three notes for
    /// everything 3+, same as before. Claude's call, unreviewed (DESIGN.md §11).
    private func mournStreak(after seconds: Double) {
        guard streakAtThePitch >= 3 else { return }
        let streak = streakAtThePitch
        streakAtThePitch = 0
        if streak >= 5, machine.hasOrgan {
            sound.funeralMarch(after: seconds)
        } else {
            sound.streakOver(after: seconds)
        }
    }

    // MARK: - Slice input entry points, used by AtBatScene.

    /// `DerbyMachine.slice` itself ignores calls made outside `.pitch`.
    func recordSlice(_ crossing: SliceCrossing) {
        let wasPitch = machine.beat == .pitch
        // Taken on the line above the swing, never after: `Replay` replays `slice(_:)` itself, so
        // it needs the machine as it stood before the swing was counted (#4).
        let marks = atBatScene.lastContactMarks
        let record = wasPitch
            ? Replay(capturing: machine, crossing: crossing,
                     slash: marks?.slash ?? Point(x: 1, y: 0), trail: marks?.trail ?? [])
            : nil
        machine.slice(crossing)
        if wasPitch {
            lastSwing = record
            sound.crack(strength: contactStrength)
            haptics.contact(strength: contactStrength)
            #if DEBUG
            writeDebugReplayIfAsked()
            #endif
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
    /// `-park <n>`: start in park n rather than wherever the save left off, so a screenshot can
    /// reach a night park or one rung of the ladder. Implies `-nosave` (`SaveStore`), so it
    /// never reads or writes a real career.
    private static let debugParkNumber: Int? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-park"), i + 1 < args.count else { return nil }
        return Int(args[i + 1])
    }()

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
