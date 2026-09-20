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
    let warmUpCardScene: WarmUpCardScene
    let replayScene: ReplayScene
    /// The one purchase (DESIGN.md §16). Read by the card and the stats board for the price.
    let store = Store()
    private weak var view: SKView?

    /// The card is offered automatically exactly once per career; after that it is a row on the
    /// stats board and nothing else. Persisted, so declining survives a relaunch.
    private(set) var contractOffered: Bool
    /// This save was already in The Show on the first launch of the paywalled build, so it is
    /// entitled for good. Only a beta tester can be in that state (§16).
    private let grandfathered: Bool

    /// The only day the game remembers (DESIGN.md §18): the Warm Up in progress or the one last
    /// finished, which is the row the stats board carries until tomorrow's replaces it.
    private(set) var lastWarmUp: SavedWarmUp?
    /// The finished card, for the result scene and the stats-board row. Nil until a day is done.
    var finishedWarmUp: WarmUpResult? {
        guard let saved = lastWarmUp, saved.done else { return nil }
        return WarmUpResult(day: saved.day, pitches: saved.pitches)
    }
    private var foregroundObserver: (any NSObjectProtocol)?

    init(seed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)) {
        let save = SaveStore.load()
        #if DEBUG
        // `-contract`: start where the card is earned, so it can be reached in one home run.
        // `-park n`: drop into one park for a screenshot. `-warmup <day>`: Double-A, the park a
        // career that has just cleared Single-A is standing in, which is the Warm Up's gate.
        let startPark: Park?
        if Self.startInTripleA {
            startPark = Park.generate(number: League.theShow.rawValue - 1)
        } else if let n = Self.debugParkNumber {
            startPark = Park.generate(number: n)
        } else if Self.debugWarmUpDay != nil {
            startPark = Park.generate(number: 2)
        } else {
            startPark = nil
        }
        #else
        let startPark: Park? = nil
        #endif
        var startingTally = save?.tally ?? Tally()
        #if DEBUG
        if let n = Self.debugStartingStreak {
            startingTally = Self.tally(["homeRunStreak": n, "bestHomeRunStreak": n])
        }
        // `-warmup <day>` fakes the one thing the Warm Up's gate asks for: a career that has
        // cleared Single-A. Without it the forced day would be refused, as it should be.
        if Self.debugWarmUpDay != nil { startingTally = Self.tally(["parksCleared": 1]) }
        #endif
        machine = DerbyMachine(seed: seed,
                               park: startPark ?? save.map { Park.generate(number: $0.parkNumber) } ?? .first,
                               tally: startingTally)
        // The sky's clock belongs to the machine (#5): a rare event is judged against the sky in
        // Core and drawn from it in the scenes, so `-skyclock` has to wind one clock and not two.
        machine.skyClockOffset = SceneryClock.offset
        #if DEBUG
        contractOffered = Self.startDeclined || (save?.contractOffered ?? false)
        #else
        contractOffered = save?.contractOffered ?? false
        #endif
        // Grandfathering (§16): asked once of each save, on the first launch that can ask it.
        // A blob written before the paywall has no answer in it, so the park number is the answer.
        grandfathered = save?.grandfathered ?? ((save?.parkNumber ?? 0) >= League.theShow.rawValue)
        lastWarmUp = save?.warmUp
        #if DEBUG
        if Self.showWarmUpCardForScreenshots { lastWarmUp = Self.sampleWarmUp }
        #endif
        atBatScene = AtBatScene()
        wideScene = WideScene()
        statsScene = StatsScene()
        contractScene = ContractScene()
        warmUpCardScene = WarmUpCardScene()
        replayScene = ReplayScene()
        atBatScene.controller = self
        wideScene.controller = self
        statsScene.controller = self
        contractScene.controller = self
        warmUpCardScene.controller = self
        replayScene.controller = self
        applyCeiling()
        persist()                                   // the grandfathering answer, written down
        store.onEntitlementChange = { [weak self] in self?.entitlementChanged() }
        Task { await store.start() }
        startTodaysWarmUpIfNeeded()
        // The other half of "at launch, and whenever the app comes back to the foreground"
        // (§18). A `scenePhase` change would have to be plumbed through two SwiftUI views to
        // reach the controller; the notification is already addressed to it.
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.startTodaysWarmUpIfNeeded() }
        }
    }

    deinit {
        if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
    }

    /// Written at every beat change, so at worst a second or so of `secondsPlayed` is lost. The
    /// park recorded is the **career's**: a Warm Up borrows the field, and the day's park number
    /// has no business being restored as the park the player is standing in (§18).
    private func persist() {
        SaveStore.save(SaveState(parkNumber: machine.careerPark.number, tally: machine.tally,
                                 contractOffered: contractOffered, grandfathered: grandfathered,
                                 warmUp: lastWarmUp))
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
        machine.parkCeiling = isEntitled ? nil : max(Self.minorsCeiling, machine.careerPark.number)
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

    // MARK: - The Warm Up (DESIGN.md §18)

    /// Today, as `YYYYMMDD` in the **local** calendar and time zone ("whatever wordle does").
    /// The one clock in the whole feature: Core is handed the number and never reads a clock.
    private static var todayDayNumber: Int {
        let d = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return (d.year ?? 2026) * 10000 + (d.month ?? 1) * 100 + (d.day ?? 1)
    }

    /// The day to play, or nil for a run that must not have one. A run with no save has no
    /// yesterday to differ from, so `-autoslice` and `-nosave` never start a Warm Up and every
    /// screenshot run stays what it was; `-warmup <day>` is the one way to force it.
    private static var warmUpDay: Int? {
        #if DEBUG
        if let forced = debugWarmUpDay { return forced }
        #endif
        return SaveStore.isEnabled ? todayDayNumber : nil
    }

    /// Called at launch and every time the app comes back to the foreground. If today is not
    /// the saved day the day's ten are queued for the next windup; if it is the saved day and
    /// they were interrupted, they pick up where they stopped.
    func startTodaysWarmUpIfNeeded() {
        guard let day = Self.warmUpDay, machine.warmUp == nil else { return }
        let card = WarmUp.generate(day: day)
        if let saved = lastWarmUp, saved.day == day {
            guard !saved.done else { return }                 // already played today
            machine.beginWarmUp(card, resuming: saved.pitches)
        } else {
            machine.beginWarmUp(card)
        }
    }

    /// Mirrors the run into the save at every beat change, so a Warm Up interrupted at pitch six
    /// resumes at pitch seven and a pitch still in the air comes back as taken.
    private func recordWarmUpProgress() {
        guard let run = machine.warmUp else { return }
        lastWarmUp = SavedWarmUp(day: run.card.day, pitches: run.pitches, done: false)
    }

    /// The tenth has played out: the day is written down as finished and the card comes up by
    /// hard cut, the machine standing still behind it.
    private func finishWarmUp(_ result: WarmUpResult) {
        lastWarmUp = SavedWarmUp(day: result.day, pitches: result.pitches, done: true)
        persist()
        #if DEBUG
        // `-showstats` alongside a Warm Up goes to the board rather than the card: a robot has
        // no finger to leave the card with, and the board is where the day's row and its
        // counted stats can be seen together.
        if Self.showStatsForScreenshots {
            Self.showStatsForScreenshots = false
            showStats()
            return
        }
        #endif
        showWarmUpCard()
    }

    func showWarmUpCard() {
        guard let view, view.scene !== warmUpCardScene, finishedWarmUp != nil else { return }
        view.presentScene(warmUpCardScene)
    }

    /// Any slice or tap leaves, by hard cut to the career windup the machine is already in.
    func leaveWarmUpCard() {
        guard let view, view.scene === warmUpCardScene else { return }
        view.presentScene(atBatScene)
    }

    /// `SHARE`: the system sheet with §18's text. The string itself is built in Core, so what
    /// is shared is a pure function of the result and is tested there.
    func shareWarmUp() {
        guard let result = finishedWarmUp, let view,
              let root = view.window?.rootViewController else { return }
        let sheet = UIActivityViewController(activityItems: [result.shareText()], applicationActivities: nil)
        // iPad has no sheet without an anchor, and this app runs on one.
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY,
                                                                 width: 1, height: 1)
        root.present(sheet, animated: true)
    }

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
        #if DEBUG
        if Self.showWarmUpCardForScreenshots {
            view.presentScene(warmUpCardScene)
            return
        }
        #endif
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
        for scene in [atBatScene, wideScene, statsScene, contractScene, warmUpCardScene,
                      replayScene] as [CanvasScene] {
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
        if machine.beat != beatBefore {
            recordWarmUpProgress()
            persist()
        }
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
        // `.warmUpEnded` arrives alongside the `.cutToAtBat` that would draw over the card, so
        // the card waits until every transition has been handled — the same dance as the contract.
        var finishedCard: WarmUpResult? = nil
        for transition in transitions {
            switch transition {
            case .cutToWide:
                if flash { wideScene.flashNextFrame = true }
                view?.presentScene(wideScene)
            case .cutToAtBat:
                if flash { atBatScene.flashNextFrame = true }
                view?.presentScene(atBatScene)
            case .pitchThrown:
                streakAtThePitch = machine.streakNow
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
            case .warmUpEnded(let result):
                finishedCard = result
            case .warmUpBegan, .parkChanged, .flash:
                break
            }
        }
        // The streak is already 0 in the tally from the moment of contact; the sad notes wait for
        // the landing number, so they cannot spoil the flight.
        if machine.beat == .result, beatBefore != .result {
            if machine.flight?.homeRun != true {
                mournStreak(after: 0.35)
            } else if machine.streakNow == 2, machine.hasOrgan {
                sound.chargePrompt()         // two straight: one more starts the fireworks (§17)
            }
        }
        if let finishedCard { finishWarmUp(finishedCard) }
        if offerTheContract { offerContract() }
        #if DEBUG
        // `-replayscreen`: once a robot swing has earned the camera and the hold is over, open
        // the replay screen, so the whole of #42 can be screenshotted with nothing touching the
        // glass. The same shape as `-showstats` above, and after it for the same reason.
        if Self.openReplayForScreenshots, offeredReplay != nil, machine.beat == .windup {
            Self.openReplayForScreenshots = false
            showReplay()
        }
        #endif
    }

    // MARK: - The instant replay (#4, #42, DESIGN.md §19)

    /// How far before the slash a replay starts, what earns one, and how long the loop rests on
    /// the landing number. Every one a knob (`ReplayRules`, in Core).
    var replayRules = ReplayRules.standard

    /// The last swing worth seeing again, or nil. Set at every contact — the record if the ball
    /// left the park or came off the wall, nil if it did nothing worth showing anyone — so the
    /// camera in the corner arrives the moment there is something behind it and is gone the
    /// moment the next ball is hit (#42). A record is a few hundred bytes and never persisted.
    private(set) var offeredReplay: Replay?

    /// True while a clip is being written. The replay screen puts `SAVING` up for it, and the
    /// camera in the corner stands down.
    private(set) var isExportingReplay = false

    /// Whether the camera belongs in the corner this frame: through the offered swing's result
    /// hold, the next windup, the next pitch and a miss's hold. Never over a ball in the air —
    /// there is a new swing to watch — and never while the replay itself is up.
    var showsReplayIcon: Bool {
        guard offeredReplay != nil, !isExportingReplay, view?.scene !== replayScene else { return false }
        switch machine.beat {
        case .result, .windup, .pitch, .miss: return true
        case .contact, .flight: return false
        }
    }

    /// The camera was tapped. Hard cut to the replay, the machine standing still behind it, the
    /// way the stats board and the two cards stop it. Nothing is rendered or encoded to watch
    /// one: `ReplayPlayback` ticks a private rebuilt machine and draws it through the same two
    /// scenes, which costs what a frame of the game costs.
    func showReplay() {
        guard let view, let replay = offeredReplay, view.scene !== replayScene else { return }
        replayScene.begin(replay, rules: replayRules)
        view.presentScene(replayScene)
        #if DEBUG
        writeDebugReplayIfAsked(replay)
        #endif
    }

    /// Any tap on the replay that is not the corner word. A hard cut back to the camera the game
    /// was paused on — the landing number if one is still up, the plate otherwise — and the
    /// machine picks its own clock up where it left it, exactly as it does leaving the board.
    func leaveReplay() {
        guard let view, view.scene === replayScene, !isExportingReplay else { return }
        let paused: CanvasScene = (machine.beat == .flight || machine.beat == .result)
            ? wideScene : atBatScene
        view.presentScene(paused)
    }

    /// `SHARE`. The only place in the game a clip is ever written, and only when it is asked for:
    /// the game is paused behind the replay screen, so nothing is competing for the frame.
    func exportAndShareReplay() {
        guard let replay = replayScene.replay, !isExportingReplay else { return }
        isExportingReplay = true
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sandlot-derby-park-\(replay.park.number).mp4")
        Task { @MainActor [weak self] in
            defer { self?.isExportingReplay = false }
            guard let self else { return }
            // Long enough for `SAVING` to be drawn and presented before the main thread gets
            // busy. Without it the word would go up only after the export it is announcing.
            try? await Task.sleep(for: .milliseconds(50))
            do {
                let clip = try await ReplayRenderer.write(replay, to: url, replayRules: replayRules)
                ReplayShare.present(clip.url, from: view, anchor: replayScene.wordAnchorInView)
            } catch {
                // A clip that could not be made says nothing: there are no toasts in this game.
                print("replay clip failed: \(error)")
            }
        }
    }

    #if DEBUG
    /// `-replay <path>`: with `-autoslice`, open the replay screen on the first swing that earns
    /// the camera and write its clip out, logging where it went and what it cost, so a clip can
    /// be made in a simulator with nothing touching the glass. A path beginning with `/` is used
    /// as given; anything else is a filename in the app's Documents directory, which is where
    /// `simctl get_app_container … data` points. Implies `-nosave`.
    ///
    /// It goes through the replay screen and the very same `ReplayRenderer.write` the `SHARE`
    /// word does, with the game paused behind it — so what it measures is what a player would
    /// actually wait for. Before #42 it wrote the clip during live play, which is the one thing
    /// this issue exists to stop happening.
    private static let debugReplayPath: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-replay"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()
    private var debugReplayDone = false

    /// `-replayscreen`: with `-autoslice`, open the replay screen once, at the windup after the
    /// first swing that earns the camera, and leave it there (the robot's slice only fires from
    /// the at-bat scene's own frame, so nothing swings behind it). For screenshots of #42.
    /// `-replay` implies it, because that is where a clip is written from now.
    private static var openReplayForScreenshots =
        ProcessInfo.processInfo.arguments.contains("-replayscreen") || debugReplayPath != nil

    private func writeDebugReplayIfAsked(_ replay: Replay) {
        guard !debugReplayDone, let path = Self.debugReplayPath else { return }
        debugReplayDone = true
        let url = path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : URL.documentsDirectory.appendingPathComponent(path)
        isExportingReplay = true
        Task { @MainActor [weak self] in
            defer { self?.isExportingReplay = false }
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(50))
            do {
                let clip = try await ReplayRenderer.write(replay, to: url, replayRules: replayRules)
                print("REPLAY CLIP WRITTEN \(clip.url.path)")
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
                     slash: marks?.slash ?? Point(x: 1, y: 0), trail: marks?.trail ?? [],
                     trailTimes: marks?.times)
            : nil
        machine.slice(crossing)
        if wasPitch {
            // Worth seeing again, or not — asked of the live machine's own flight, so nothing is
            // rebuilt to answer it (#42). Either way the previous offer is over: the next ball
            // has been hit.
            offeredReplay = replayRules.offers(homeRun: machine.flight?.homeRun ?? false,
                                               offTheWall: machine.flight?.wallHit ?? false)
                ? record : nil
            sound.crack(strength: contactStrength)
            haptics.contact(strength: contactStrength)
            // No clip is written here any more: `-replay` goes in through the replay screen,
            // the way `SHARE` does, because nothing renders during play (#42).
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

    /// A `Tally` with only the given stats set, via the same JSON shape `SaveStore` and old
    /// saves already round-trip through — `Tally.set` is Core-internal, so this is the one door
    /// the app has into a specific starting number.
    private static func tally(_ values: [String: Int]) -> Tally {
        let body = values.keys.sorted().map { "\"\($0)\":\(values[$0]!)" }.joined(separator: ",")
        let json = "{\"values\":{\(body)}}".data(using: .utf8)!
        return (try? JSONDecoder().decode(Tally.self, from: json)) ?? Tally()
    }

    /// `-warmup <day>`: force the Warm Up for that `YYYYMMDD`, whatever today is, so the daily
    /// ten can be screenshotted on a chosen park. Implies `-nosave` (`SaveStore`) — a forced day
    /// has no business overwriting, or being overwritten by, a real career — and fakes the one
    /// cleared park the gate asks for. `-warmupcard` implies it for today.
    private static let debugWarmUpDay: Int? = {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-warmup"), i + 1 < args.count, let day = Int(args[i + 1]) {
            return day
        }
        return args.contains("-warmupcard") ? todayDayNumber : nil
    }()

    /// `-warmupcard`: jump straight to the result card with a made-up ten, so the card and the
    /// share row can be looked at without playing forty seconds of Warm Up first. It fakes the
    /// result the way `-streak` fakes a streak — the glyph row is §18's own example.
    static let showWarmUpCardForScreenshots = ProcessInfo.processInfo.arguments.contains("-warmupcard")

    private static var sampleWarmUp: SavedWarmUp {
        let outcomes: [WarmUpOutcome] = [.homeRun, .swingAndMiss, .inPlay, .homeRun, .taken,
                                         .offTheWall, .homeRun, .inPlay, .swingAndMiss, .homeRun]
        let feet = [412, 0, 141, 388, 0, 372, 401, 89, 0, 436]
        return SavedWarmUp(day: debugWarmUpDay ?? todayDayNumber,
                           pitches: zip(outcomes, feet).map(WarmUpPitch.init), done: true)
    }
    #endif

    /// The ball's position at a given pitch progress, for `Contact.test`'s `ballAt` closure
    /// and for building miss/call markers.
    func ballAt(_ progress: Double) -> BallSample {
        Pitching.ball(machine.pitch, at: progress, rules: machine.pitchingRules)
    }
}
