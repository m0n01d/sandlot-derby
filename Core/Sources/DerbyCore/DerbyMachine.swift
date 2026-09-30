import Foundation

/// The five beats of a pitch, plus miss. One camera-changing edge: contact → flight.
public enum Beat: Equatable {
    case windup, pitch, contact, flight, result, miss
}

public enum Call: Equatable {
    case strike, ball, miss
}

/// Beat durations in seconds. DESIGN.md §3.
public struct Timings: Equatable {
    public var windup: Double = 0.5
    /// Freeze on the slash before the cut, weakest contact (`SliceCrossing.quality` 0). Starting
    /// value, Claude's, 2026-09-19 (issue #20).
    public var contactHoldWeak: Double = 0.22
    /// Freeze on the slash before the cut, best contact (`SliceCrossing.quality` 1). Starting
    /// value, Claude's, 2026-09-19 (issue #20).
    public var contactHoldBarrel: Double = 0.50
    /// Freeze on the miss markers.
    public var missHold: Double = 1.2
    /// Hold on the landing number.
    public var resultHold: Double = 1.3
    /// The pitch is "taken" this far past the plate (as a multiple of duration) plus grace.
    public var pitchOverrun: Double = 1.15
    public var takeGrace: Double = 0.05
    /// Flight playback speed multiplier. 1 is real time; every classic derby ran faster.
    public var flightSpeed: Double = 2
    /// The longest the windup will wait for the organist before pitching anyway — past it the
    /// pitch cuts the organ off exactly as it always has. The funeral march (~3.7 s) is the one
    /// cue longer than this (#46, DESIGN.md §11). Dwight, 2026-09-20: "maybe the pitcher waits
    /// for the music to stop. usually irl they do."
    public var maxMusicHold: Double = 2.5
    public init() {}
    public static let standard = Timings()
}

/// The name of one career number. A string, not an enum, so a save written by an older build
/// still loads after new stats are added: a missing key reads as 0.
public struct Stat: Hashable {
    public let key: String
    public init(_ key: String) { self.key = key }

    // The cost and the progress (DESIGN.md §10).
    public static let pitches = Stat("pitches")
    public static let parksCleared = Stat("parksCleared")
    public static let pitchesThisPark = Stat("pitchesThisPark")
    /// Home runs hit **in this park**, not in a row: what `ProgressRules.homeRunsToClear` is
    /// counted against (#40). Reset by the park change, and never fed by a Warm Up (§18). A save
    /// written before this existed reads 0, which is where a park starts anyway.
    public static let homeRunsThisPark = Stat("homeRunsThisPark")
    /// Absent until the first park is cleared.
    public static let fewestPitchesToClearPark = Stat("fewestPitchesToClearPark")
    public static let secondsPlayed = Stat("secondsPlayed")
    /// Career pitches at the moment of the call-up. Absent in the minors.
    public static let pitchesToTheShow = Stat("pitchesToTheShow")

    // Plate discipline.
    public static let swings = Stat("swings")
    public static let whiffs = Stat("whiffs")
    public static let calledStrikes = Stat("calledStrikes")
    public static let ballsTaken = Stat("ballsTaken")
    /// Swings at pitches outside the zone, hit or not.
    public static let chases = Stat("chases")

    // Contact.
    public static let hits = Stat("hits")
    public static let barrels = Stat("barrels")
    public static let groundBalls = Stat("groundBalls")
    public static let lineDrives = Stat("lineDrives")
    public static let flyBalls = Stat("flyBalls")
    public static let popUps = Stat("popUps")
    public static let wallHits = Stat("wallHits")
    public static let exitVelocitySum = Stat("exitVelocitySum")
    public static let launchAngleSum = Stat("launchAngleSum")
    public static let bestExitVelocityMPH = Stat("bestExitVelocityMPH")
    public static let highestApexFeet = Stat("highestApexFeet")
    public static let longestHangTime = Stat("longestHangTime")

    // Distance.
    public static let totalFeet = Stat("totalFeet")
    public static let longestFeet = Stat("longestFeet")

    // Home runs.
    public static let homeRuns = Stat("homeRuns")
    public static let noDoubters = Stat("noDoubters")
    public static let wallScrapers = Stat("wallScrapers")
    public static let moonshots = Stat("moonshots")
    public static let lasers = Stat("lasers")

    // The rare things (#5, DESIGN.md §17 "Rare things"). Never announced and never explained:
    // they are counted here and shown on the stats board, and nowhere else.
    public static let birdsHit = Stat("birdsHit")
    public static let blimpsHit = Stat("blimpsHit")
    public static let scoreboardDents = Stat("scoreboardDents")
    public static let windowsBroken = Stat("windowsBroken")
    public static let lightsOut = Stat("lightsOut")

    // Streaks.
    public static let homeRunStreak = Stat("homeRunStreak")
    public static let bestHomeRunStreak = Stat("bestHomeRunStreak")
    /// The career best the live home-run streak had to beat when it began. Bookkeeping, not a
    /// number anyone is shown — the same kind of key `warmUpLastDay` is. It is what lets a streak
    /// record fire once, on the home run that *passes* the old best, and not on every one after
    /// it: by then the best is this streak's own and beating it is only extending it (#41).
    public static let bestHomeRunStreakAtStreakStart = Stat("bestHomeRunStreakAtStreakStart")
    public static let hitStreak = Stat("hitStreak")
    public static let bestHitStreak = Stat("bestHitStreak")

    // The Warm Up (DESIGN.md §18). The daily ten count toward everything above except the cost.
    /// Days played through to the tenth pitch.
    public static let warmUps = Stat("warmUps")
    public static let warmUpBestFeet = Stat("warmUpBestFeet")
    public static let warmUpBestHomeRuns = Stat("warmUpBestHomeRuns")
    /// Counted, never dangled: it is on the stats board and nowhere else.
    public static let warmUpDaysInARow = Stat("warmUpDaysInARow")
    public static let bestWarmUpDaysInARow = Stat("bestWarmUpDaysInARow")
    /// The last Warm Up's day as a day count (`WarmUp.serial`), so "in a row" is a subtraction.
    /// Bookkeeping, not a number anyone is shown.
    public static let warmUpLastDay = Stat("warmUpLastDay")

    // Per pitch type, keyed by `PitchType.name`.
    public static func seen(_ t: PitchType) -> Stat { Stat("seen." + t.name) }
    public static func hits(_ t: PitchType) -> Stat { Stat("hits." + t.name) }
    public static func homeRuns(_ t: PitchType) -> Stat { Stat("homeRuns." + t.name) }
}

/// Every career number, forever, never reset. Counted, never punished.
public struct Tally: Equatable, Codable {
    private var values: [String: Double] = [:]
    public init() {}

    public subscript(_ s: Stat) -> Double { values[s.key] ?? 0 }
    public func count(_ s: Stat) -> Int { Int(self[s].rounded()) }
    /// Nil until the stat has been written once. For minimums, where 0 is not "none".
    public func value(ifRecorded s: Stat) -> Double? { values[s.key] }

    mutating func add(_ s: Stat, _ amount: Double = 1) { values[s.key, default: 0] += amount }
    mutating func set(_ s: Stat, _ v: Double) { values[s.key] = v }
    mutating func raise(_ s: Stat, to v: Double) { if v > self[s] { values[s.key] = v } }
    mutating func lower(_ s: Stat, to v: Double) { if let old = values[s.key], old <= v { return }; values[s.key] = v }
    /// Extends `streak` by one and carries `best` with it.
    mutating func extend(_ streak: Stat, best: Stat) { add(streak); raise(best, to: self[streak]) }

    public var pitches: Int { count(.pitches) }
    public var hits: Int { count(.hits) }
    public var homeRuns: Int { count(.homeRuns) }
    public var longestFeet: Int { count(.longestFeet) }
    public var totalFeet: Int { count(.totalFeet) }
    public var homeRunStreak: Int { count(.homeRunStreak) }
    public var bestHomeRunStreak: Int { count(.bestHomeRunStreak) }
    /// Mean exit velocity over every ball put in play, 0 before the first hit.
    public var averageExitVelocityMPH: Double { hits > 0 ? self[.exitVelocitySum] / Double(hits) : 0 }
    public var averageLaunchAngleDegrees: Double { hits > 0 ? self[.launchAngleSum] / Double(hits) : 0 }
}

/// How a batted ball is sorted into the counted kinds. None of this changes the flight.
public struct StatRules: Equatable {
    /// Statcast's barrel: at least this hard…
    public var barrelMinExitVelocity: Double = 98
    /// …and inside this launch window at the minimum velocity. The window opens by
    /// `barrelWidening` degrees a side per mph above it, to at most `barrelMaxWindow`.
    /// An approximation of the published table, not the table.
    public var barrelWindow: ClosedRange<Double> = 26...30
    public var barrelWidening: Double = 1.1
    public var barrelMaxWindow: ClosedRange<Double> = 8...50
    /// Statcast's batted-ball classes by launch angle: ground < line < fly < pop-up.
    public var lineDriveFrom: Double = 10
    public var flyBallFrom: Double = 25
    public var popUpFrom: Double = 50
    /// A home run landing this far past the wall never had a doubt.
    public var noDoubterMarginFeet: Double = 50
    /// A home run landing within this of the wall scraped over.
    public var wallScraperMarginFeet: Double = 12
    /// Apex, in feet, that makes any batted ball a moonshot.
    public var moonshotApexFeet: Double = 150
    /// A home run launched at or below this is a laser.
    public var laserMaxAngle: Double = 20
    /// Taking a pitch outside the zone keeps the home run streak alive. Everything else that
    /// is not a home run (called strike, whiff, any other contact) ends it.
    public var takenBallKeepsStreak = true
    public init() {}
    public static let standard = StatRules()

    public func isBarrel(exitVelocityMPH ev: Double, launchAngleDegrees la: Double) -> Bool {
        guard ev >= barrelMinExitVelocity else { return false }
        let open = (ev - barrelMinExitVelocity) * barrelWidening
        let lo = max(barrelMaxWindow.lowerBound, barrelWindow.lowerBound - open)
        let hi = min(barrelMaxWindow.upperBound, barrelWindow.upperBound + open)
        return la >= lo && la <= hi
    }
}

/// Which of the two flight framings is up. With the at-bat view that makes three cameras, and
/// every change between them is a hard cut (DESIGN.md §3).
public enum FlightCamera: Equatable {
    /// The whole field, batter to beyond the wall. The ball leaves the bat here, and the result
    /// comes back here so the landing number sits over the whole arc.
    case wide
    /// Tight on the wall, so a 6 ft fence reads as a fence and "did it clear?" is a picture.
    case close
}

/// What a park asks for before it is cleared (DESIGN.md §10, issue #40).
public struct ProgressRules: Equatable {
    /// Home runs **in this park** that clear it — a count, not a streak: in a row is what the
    /// home-run streak is for, and in The Show three in a row would be brutal. One number for
    /// every park, the minors included; per-league values are a later tweak. Dwight, 2026-09-20:
    /// "lets start with 3."
    public var homeRunsToClear = 3
    public init() {}
    public static let standard = ProgressRules()
}

public struct CameraRules: Equatable {
    /// A ball earns the close camera only if it ever gets within this many feet of the wall.
    /// Everything else is watched from the wide camera start to finish.
    public var closeReachFeet: Double = 60
    /// The cut to the close camera comes when the ball is this far short of the wall.
    public var closeLeadFeet: Double = 100
    public init() {}
    public static let standard = CameraRules()
}

/// What the scene needs to do in response to a tick. The machine never touches a node.
public enum Transition: Equatable {
    case pitchThrown
    case cutToWide
    case cutToAtBat
    case flash
    case parkChanged(Park)
    /// Triple-A cleared: the next pitch is in The Show. Once per career.
    case calledUp
    /// A career number just fell, at the moment the number that set it goes up on screen: the
    /// start of the result hold (#41). At most one a swing, and never without a previous best.
    case newRecord(RecordKind)
    // Moments worth a sound or a haptic. They fire as playback reaches them, once each, so the
    // crowd reacts when the ball clears the wall and not when the bat meets it.
    /// A pitch was taken: the umpire's call.
    case called(Call)
    /// The ball crossed the wall above it.
    case clearedWall
    /// The ball met the wall below the top.
    case hitWall
    /// First touch of the ground.
    case landed
    /// Two called strikes taken in a row (there is no third in this game, so no called-out
    /// version). Fires once, on the second; a longer streak doesn't repeat it. #17.
    case calledStrikesInARow
    /// The day's Warm Up has taken the field (DESIGN.md §18). The career's park and next pitch
    /// are set aside until `.warmUpEnded`; the beats in between are the usual five and a miss.
    case warmUpBegan
    /// The tenth pitch has resolved and its hold has played out: the result card, and behind it
    /// the career windup the machine is already standing in. The `WarmUpBests` is what the day
    /// beat, worked out as its books closed — by the time the card is drawn the bests have been
    /// raised to it and there is nothing left to compare against (#41). It travels here rather
    /// than on the machine because nothing of a Warm Up may be left standing behind it (§18).
    case warmUpEnded(WarmUpResult, WarmUpBests)
}

/// Pure game state. Scenes call `tick`, `slice`, `sliceMissed`, and draw from the properties.
public struct DerbyMachine: Equatable {
    public private(set) var beat: Beat = .windup
    /// Seconds spent in the current beat.
    public private(set) var elapsed: Double = 0
    public private(set) var park: Park
    public private(set) var pitch: Pitch
    public private(set) var flight: FlightResult? = nil
    public private(set) var launch: Launch? = nil
    /// Fractional index into `flight.points` during playback.
    public private(set) var playbackIndex: Double = 0
    public private(set) var tally = Tally()
    public private(set) var lastCall: Call? = nil
    /// Called strikes taken back to back, reset by any swing or a taken ball. #17: two in a row
    /// is *Three Blind Mice*'s cue (there is no third strike here).
    public private(set) var calledStrikesInARow = 0
    /// Set the instant the ball clears the wall (the `.clearedWall` cue) if the streak has
    /// earned a show at all; nil for every other beat, and nil again the moment `.result` ends
    /// (DESIGN.md §17 "When"). `Fireworks.particles(show:at:)` turns this into drawn points.
    public private(set) var fireworks: FireworksShow? = nil
    /// Every rare thing this flight does, found once at contact and in playback order (#5).
    /// Empty for every beat that is not a flight or its result, and empty again at the cut back
    /// to the plate — the same window `fireworks` lives in.
    public private(set) var parkEvents: [ParkEvent] = []
    /// The record this swing set, for exactly as long as the number that set it is on screen:
    /// set as the result hold begins and nil at every other beat, the same window `fireworks`
    /// and `parkEvents` live in (#41). The scenes read it; nothing in Core does.
    public private(set) var recordNow: RecordKind? = nil
    /// What this park still carries: a dark bank, a dent, a broken pane. It survives the cut to
    /// the plate and dies with the park, which is what #5 means by "until the park changes".
    public private(set) var parkScars = ParkScars()
    /// `Tally[.secondsPlayed]` as the swing was made. The sky the rare events were judged against
    /// is worked out from this and nothing else, so a clip re-rendered at a fixed 60 Hz finds
    /// the same birds a phone did (DESIGN.md §19).
    public private(set) var clockAtContact: Double = 0
    /// What the sky's clock is wound forward by. Zero in every shipped build: only the DEBUG
    /// `-skyclock` argument moves it, so a screenshot can reach a flock of birds without waiting
    /// forty seconds. It lives here rather than in the app because the sky a rare event is judged
    /// against and the sky that is drawn have to be the same sky (#5).
    public var skyClockOffset: Double = 0
    /// The one clock everything in the sky reads (DESIGN.md §17 "One clock").
    public var skyClock: Double { tally[.secondsPlayed] + skyClockOffset }
    /// What the app's reading of the real time of day says the phase should be (DESIGN.md §20).
    /// `GameController` sets it at launch, when the app becomes active and on each beat change;
    /// a Core test simply assigns one. Nothing reads it but the line below.
    public var phaseOffered: DayPhase
    /// The phase this drawing is in. Taken from `phaseOffered` at every windup and held there
    /// until the next one, so the sky cannot change during a pitch, a flight or a result hold —
    /// and the change, when it comes, is a hard palette swap between two frames like every other
    /// cut in this game. It lives on the machine rather than in a scene because it changes one
    /// counted thing (the lights-out shot, §17 step 6), which means a replay has to reproduce it.
    public private(set) var phase: DayPhase
    /// Whether this park's lamps are lit right now — the one thing the phase changes that is
    /// counted. Everything that used to ask `park.isNight` asks this instead.
    public var lampsOn: Bool { phase.lampsOn }
    public var timings: Timings
    /// The knobs as they stand in The Show and beyond. The minors lay a `Rung` over them.
    public var majorsSliceRules: SliceRules
    public var majorsPitchingRules: PitchingRules
    public var statRules: StatRules
    public var fireworksRules: FireworksRules
    public var rareEventRules: RareEventRules = .standard
    /// What this park asks for before it is cleared (#40). Settable like `cameraRules`, so a
    /// test — or a later per-league tweak — can move the count without touching the machine.
    public var progressRules: ProgressRules = .standard
    public var recordRules: RecordRules = .standard
    public var ladder: Ladder
    /// Whether a finger is on the glass right now, mirrored in every frame by the app (whatever
    /// the beat is or where the finger landed — a slice is "in progress" whenever a finger is
    /// down, DESIGN.md §3). If the pitch times out while this is true, `tick` resolves it as a
    /// miss, not a take. Also reset to false at the start of every new pitch, so a caller driving
    /// `DerbyMachine` directly (as the Core tests do) doesn't have to clear it back down itself.
    public var sliceInProgress = false
    /// The day's ten while they are being played, nil in the career (DESIGN.md §18).
    public private(set) var warmUp: WarmUpRun? = nil
    /// Queued by `beginWarmUp`, taken up at the next windup — never in the middle of a pitch,
    /// exactly the way an owed advance is paid (§16).
    private var queuedWarmUp: WarmUpRun? = nil
    /// The career's park and next pitch, held while a Warm Up borrows the field and handed back
    /// untouched afterwards. `rng` is not drawn from once in between.
    private var parkSetAside: Park? = nil
    private var pitchSetAside: Pitch? = nil
    /// The career park's dents and dark banks, held while a Warm Up borrows the field. A day's
    /// ten are played somewhere else entirely; they must not tidy up the park being cleared.
    private var scarsSetAside: ParkScars? = nil
    private var rng: SplitMix64
    private var wallCueIndex: Int? = nil
    private var landCueIndex: Int? = nil
    /// Where the cut to the close camera falls, found once with the other two rather than by
    /// walking the flight again on every frame that asks which camera is up.
    private var closeCutIndex: Int? = nil
    /// The quality of the swing that made contact, 0…1, carried from `slice(_:)` into
    /// `contactHoldNow`.
    private var contactQuality: Double = 0
    /// Seconds left on the organ cue the app just started, set by `holdForMusic` and counted
    /// down every tick regardless of beat (#46). Only `.windup` ever holds for it; it decays
    /// quietly through every other beat, so a cue that outlasted its hold cannot ambush a later
    /// windup. Never saved, never part of a replay record: it starts at 0 on every machine.
    private var musicRemaining: Double = 0
    /// How long the current windup has been holding for the music. Reset whenever a beat is
    /// (re)entered, so the cap in `Timings.maxMusicHold` is measured from the start of *this*
    /// windup, not carried over from an earlier one.
    private var musicHoldElapsed: Double = 0
    /// The tally as it stood the instant before the swing on screen, and the streak with it: the
    /// two halves of the comparison a record is (#41). Nil before the first swing of a machine.
    private var tallyBeforeSwing: Tally? = nil
    private var streakBeforeSwing: Int = 0

    /// The rules in force in this park. Scenes read these, never the majors' ones.
    public var sliceRules: SliceRules { ladder.sliceRules(majorsSliceRules, for: park.league) }
    public var pitchingRules: PitchingRules { ladder.pitchingRules(majorsPitchingRules, for: park.league) }
    /// The help this park gives, nil from The Show on.
    public var rung: Rung? { ladder.rung(for: park.league) }
    /// Whether this park has a ballpark organ (#17). The Show always does; a rung follows its
    /// own `organ` flag — a sandlot has no organist. Claude's call, unreviewed (DESIGN.md §11).
    public var hasOrgan: Bool { rung?.organ ?? true }

    /// `park` and `tally` are what a save restores; everything else starts fresh. `phase` is what
    /// the clock says as the machine is made — the app's reading, or a test's choice; the default
    /// is the one phase that needs no sky kit at all (§20).
    public init(seed: UInt64, park: Park = .first, tally: Tally = Tally(), timings: Timings = .standard,
                sliceRules: SliceRules = .standard, pitchingRules: PitchingRules = .standard,
                statRules: StatRules = .standard, fireworksRules: FireworksRules = .standard,
                ladder: Ladder = .standard, phase: DayPhase = .midday) {
        var g = SplitMix64(seed: seed)
        let first = Pitching.generate(using: &g, rules: ladder.pitchingRules(pitchingRules, for: park.league))
        self.park = park
        self.tally = tally
        self.phase = phase
        self.phaseOffered = phase
        self.statRules = statRules
        self.fireworksRules = fireworksRules
        self.ladder = ladder
        self.timings = timings
        self.majorsSliceRules = sliceRules
        self.majorsPitchingRules = pitchingRules
        self.rng = g
        self.pitch = first
    }

    /// One word for a ball that stayed in the park, minors only, result hold only. Aim first,
    /// then power: a grounder hit harder is still a grounder.
    public var coachingWord: String? {
        guard beat == .result, rung?.coaching == true, let f = flight, !f.homeRun, let l = launch else { return nil }
        if l.launchAngleDegrees < ladder.coachLowAngle { return "SWING UP" }
        if l.launchAngleDegrees > ladder.coachHighAngle { return "LEVEL OUT" }
        if l.exitVelocityMPH < ladder.coachWeakExitVelocity { return "FASTER" }
        return nil
    }

    // MARK: - Clearing a park (#40)

    /// Home runs hit in this park so far. A count, not a streak: a miss or a ball in play between
    /// two of them costs nothing here, only the home-run streak.
    public var homeRunsThisPark: Int { tally.count(.homeRunsThisPark) }

    /// How many this park asks for. Never below one, whatever the knob says: a park that could
    /// not be cleared at all is not a park.
    public var homeRunsToClearPark: Int { max(1, progressRules.homeRunsToClear) }

    /// True through the result hold of the home run that **made this park's count** — the one
    /// that advances at the end of the hold, announces the call-up and is owed at the ceiling.
    /// False on the ones before it, and false for a Warm Up, which clears nothing (§18).
    public var clearsTheParkNow: Bool {
        beat == .result && warmUp == nil && (flight?.homeRun ?? false)
            && homeRunsThisPark >= homeRunsToClearPark
    }

    /// True through the result hold of the home run that clears Triple-A: the clearing one, now
    /// that a park takes a count (#40). At the ceiling the count stays met, so — exactly as
    /// before — every later Triple-A home run announces it again (§16's open question 3).
    public var isBeingCalledUp: Bool {
        clearsTheParkNow && park.league == .tripleA
    }

    /// The hitstop to hold for right now: `contactHoldWeak` at quality 0, `contactHoldBarrel`
    /// at quality 1, linear between. Meaningful only once `slice(_:)` has set `contactQuality`;
    /// before the first contact it reads as the weak hold.
    public var contactHoldNow: Double {
        timings.contactHoldWeak + (timings.contactHoldBarrel - timings.contactHoldWeak) * contactQuality
    }

    /// True while the contact freeze is showing a barrelled ball (`StatRules.isBarrel`), so the
    /// scene can draw the call. False outside `.contact` and whenever there is no launch.
    public var isBarrelNow: Bool {
        guard beat == .contact, let l = launch else { return false }
        return statRules.isBarrel(exitVelocityMPH: l.exitVelocityMPH, launchAngleDegrees: l.launchAngleDegrees)
    }

    /// Pitch progress, 0 at release and 1 at the plate. Only meaningful during `.pitch`.
    public var pitchProgress: Double { elapsed / pitch.duration }

    /// The ball right now during the pitch, in at-bat design units.
    public var ballNow: BallSample { Pitching.ball(pitch, at: min(1.15, pitchProgress), rules: pitchingRules) }

    public var cameraRules = CameraRules.standard

    /// The last park the player may stand in, nil for none (DESIGN.md §16). A home run in the
    /// ceiling park counts in every way but one: the park does not change. It emits `.calledUp`
    /// so the scene can offer the contract, and the advance is owed. Core knows nothing about
    /// money: the app sets this from the entitlement, and back to nil when the contract is
    /// signed, which pays the advance at the next windup.
    public var parkCeiling: Int? = nil
    /// A home run at the ceiling earned an advance that has not happened. Not saved: after a
    /// relaunch it takes one more home run, which is a call-up worth having anyway.
    private var advanceOwed = false

    /// True when a home run here cannot move the player on. Never during a Warm Up: those ten
    /// are played in the day's park, not the one being cleared, so the ceiling does not apply
    /// to them (DESIGN.md §18) — and the day's park number would clear any ceiling anyway.
    public var isAtCeiling: Bool { warmUp == nil && (parkCeiling.map { park.number >= $0 } ?? false) }

    /// The park the **career** is standing in: `park` itself, unless a Warm Up has borrowed the
    /// field. What the save records and what the ceiling is measured against.
    public var careerPark: Park { parkSetAside ?? park }

    /// The home-run streak that is live right now: the Warm Up's while one is running, the
    /// career's otherwise. The fireworks (§17) and the streak cues (§11) read this, so they
    /// follow whichever is live without having to know there are two.
    public var streakNow: Int { warmUp?.homeRunStreak ?? tally.homeRunStreak }

    /// The flight framing right now: a pure function of the flight and how much of it has played,
    /// so a replay cuts exactly where the live game did. Only `.flight` is ever close; the
    /// result hold always cuts back out.
    public var flightCamera: FlightCamera {
        guard beat == .flight, flight != nil, let cut = closeCutIndex else { return .wide }
        return playbackIndex >= Double(cut) ? .close : .wide
    }

    /// True while the crowd is on its feet: from the instant the ball clears the wall to the cut
    /// back to the plate. It opens on the `.clearedWall` cue — the cheer's own — and closes when
    /// `.result` ends, which is the same window `fireworks` lives in and the same one DESIGN.md
    /// §17 means by "for as long as the cheer plays". The stands' bounce and the night lights'
    /// chase both read it, so neither is a timer in a scene.
    ///
    /// Not `fireworks != nil`: a streak under three earns no shells at all, and the crowd is up
    /// for every home run there is (§17's table — streak 1 is "the cheer, the crowd bounce, the
    /// lights chase at night").
    public var crowdIsUp: Bool {
        guard let f = flight, f.homeRun else { return false }
        switch beat {
        case .result: return true
        case .flight: return wallCueIndex.map { playbackIndex >= Double($0) } ?? false
        default: return false
        }
    }

    /// How long ago a rare thing happened, or nil while playback has not reached it (#5). Off the
    /// machine's own clocks and never a timer in a scene, exactly like the pop where a home run
    /// goes into the crowd: playback stops dead at the last point of the flight, so once the
    /// landing number is up the result hold's clock carries the burst the rest of the way out.
    public func secondsSince(_ event: ParkEvent) -> Double? {
        guard beat == .flight || beat == .result,
              playbackIndex >= Double(event.index) else { return nil }
        let played = (playbackIndex - Double(event.index))
            * FlightParams.calibrated.timestep / timings.flightSpeed
        return beat == .result ? played + elapsed : played
    }

    /// The bird this flight has already gone through, if it has: the sky leaves it out for the
    /// rest of its crossing, which is the only way a bird can be gone when nothing anywhere keeps
    /// a bird (DESIGN.md §17 "Everything is a pure function").
    public var struckBird: (slot: Int, index: Int)? {
        for event in parkEvents where event.kind == .birdStrike {
            guard secondsSince(event) != nil else { return nil }
            return (event.flockSlot, event.target)
        }
        return nil
    }

    /// Whether the sky shows what a long career has arrived at — the blimp past park 100, the
    /// searchlights past 500, the comet past 1,000 (#5). A Warm Up's park number is the *day*
    /// (20260920), which would clear every threshold there is by accident, and the day's ten are
    /// not a career park: they are played somewhere else and cleared nothing (DESIGN.md §18).
    /// The seeded landmarks a day's park draws are its own and are shown; these are not.
    public var showsMilestones: Bool { warmUp == nil }

    /// Whether a bank is dark: put out earlier in this park, or put out by the shot on screen.
    public func bankIsOut(_ index: Int) -> Bool {
        if parkScars.darkBanks.contains(index) { return true }
        return parkEvents.contains {
            $0.kind == .lightsOut && $0.target == index && secondsSince($0) != nil
        }
    }

    public var playbackPoint: FlightPoint? {
        guard let f = flight, !f.points.isEmpty else { return nil }
        let i = min(f.points.count - 1, Int(playbackIndex))
        return f.points[i]
    }

    // MARK: - Inputs

    /// Queue the day's Warm Up for the next windup (DESIGN.md §18). Ignored while one is
    /// already running or queued, and ignored for a career that has not cleared
    /// `WarmUpRules.minParksCleared` parks: ten Show-league pitches with no swing guide are a
    /// bad first minute, so it starts the first day after they have hit one out.
    ///
    /// `resuming` is what was already spent earlier the same day — a Warm Up interrupted at
    /// pitch six picks up at pitch seven, with the streak those home runs had earned.
    public mutating func beginWarmUp(_ card: WarmUp, resuming: [WarmUpPitch] = []) {
        guard warmUp == nil, queuedWarmUp == nil else { return }
        guard tally.count(.parksCleared) >= card.rules.minParksCleared else { return }
        guard resuming.count < card.pitches.count else { return }
        let streak = resuming.reversed().prefix { $0.outcome == .homeRun }.count
        queuedWarmUp = WarmUpRun(card: card, pitches: resuming, homeRunStreak: streak)
    }

    /// The app tells the machine how long an organ cue it just started will take to finish
    /// sounding, so the next windup can wait for it (#46, DESIGN.md §11). Never shortened, only
    /// extended — two cues that overlap (the app never means for two to, but a cap makes it
    /// harmless either way) leave the longer of the two standing. Called from any beat; the
    /// windup that is holding, or the next one to begin, is whichever reads it.
    public mutating func holdForMusic(_ seconds: Double) {
        musicRemaining = max(musicRemaining, seconds)
    }

    /// True while the windup is holding the pitcher set for the organ (#46) — for anyone who
    /// wants to know without reaching into the beat, `musicRemaining` (private) and the cap
    /// itself. False the instant the cue finishes or `Timings.maxMusicHold` is reached.
    public var isHoldingForMusic: Bool {
        beat == .windup && musicRemaining > 0 && musicHoldElapsed < timings.maxMusicHold
    }

    /// Called by the scene when `Contact.test` returned `.contact` during `.pitch`.
    public mutating func slice(_ crossing: SliceCrossing) {
        guard beat == .pitch else { return }
        calledStrikesInARow = 0
        // Every number as it stood before this swing, kept so a record is a comparison of before
        // and after rather than a count kept alongside the numbers themselves (#41). A replay
        // rebuilds it for nothing: `atPitch` starts from the record's own before-tally and this
        // line runs again, so a clip finds the same record the live swing did (DESIGN.md §19).
        tallyBeforeSwing = tally
        streakBeforeSwing = streakNow
        let l = Contact.resolve(crossing, pitch: pitch, rules: sliceRules)
        let f = Flight.simulate(exitVelocityMPH: l.exitVelocityMPH, launchAngleDegrees: l.launchAngleDegrees,
                                wallDistanceFeet: park.wallDistanceFeet, wallHeightFeet: park.wallHeightFeet)
        countPitch()
        countContact(l, f)
        launch = l
        flight = f
        // Where in the playback the wall and the ground are met, found once. A wall hit is reset
        // to just inside the wall, so look a fraction short of it.
        wallCueIndex = (f.homeRun || f.wallHit)
            ? f.points.firstIndex(where: { $0.xFeet >= park.wallDistanceFeet - 0.2 }) : nil
        landCueIndex = f.hangTime.flatMap { hang in f.points.firstIndex(where: { $0.time >= hang }) }
        closeCutIndex = SideView.closeCutIndex(flight: f, wallDistanceFeet: park.wallDistanceFeet,
                                               rules: cameraRules)
        playbackIndex = 0
        lastCall = nil
        contactQuality = min(1, max(0, crossing.quality))
        // Every rare thing this arc passes through, found now and counted as playback reaches
        // each one. It has to come after `contactQuality`, which is what `contactHoldNow` — and
        // so the sky the events are judged against — is worked out from (#5).
        clockAtContact = skyClock
        parkEvents = RareEvents.detect(
            park: park, scenery: park.scenery, flight: f,
            birdSeed: SkyView.side.birdSeed(parkNumber: park.number),
            blimpSeed: SkyView.side.blimpSeed(parkNumber: park.number),
            clockAtContact: clockAtContact, contactHold: contactHoldNow,
            flightSpeed: timings.flightSpeed, lampsOn: lampsOn,
            statRules: statRules, rules: rareEventRules)
        recordWarmUpPitch(WarmUpPitch(outcome: f.homeRun ? .homeRun : f.wallHit ? .offTheWall : .inPlay,
                                      feet: Int(f.distanceFeet.rounded())))
        enter(.contact)
    }

    /// Called when the finger lifts during `.pitch` without a contact.
    public mutating func sliceMissed() {
        guard beat == .pitch else { return }
        calledStrikesInARow = 0
        countPitch()
        tally.add(.swings)
        tally.add(.whiffs)
        if !pitch.isStrike { tally.add(.chases) }
        endStreaks()
        lastCall = .miss
        recordWarmUpPitch(WarmUpPitch(outcome: .swingAndMiss))
        enter(.miss)
    }

    /// The player looked away: back to the top of the windup with the same pitch, as though it
    /// had never been thrown (docs/watch.md §5). A lowered wrist must never cost a called strike.
    /// Only from `.windup` or `.pitch`; a ball already hit plays out, and a call already made
    /// stands. Counts nothing, emits nothing, and leaves every streak where it was.
    ///
    /// Inside a Warm Up the pitch in the air has already been written down as `.taken` (§18); that
    /// placeholder comes off again, since the same pitch is about to be thrown a second time.
    public mutating func abandonPitch() {
        guard beat == .windup || beat == .pitch else { return }
        if beat == .pitch, warmUp?.pitches.isEmpty == false { warmUp?.pitches.removeLast() }
        sliceInProgress = false
        enter(.windup)
    }

    // MARK: - Counting

    /// A warm-up swing counts toward everything except **the cost** (DESIGN.md §18): the ten are
    /// thrown in the day's park, not the one being cleared, and a warm-up that made
    /// `PARK n · PITCHES` worse would punish showing up. `pitchesToTheShow` and
    /// `fewestPitchesToClearPark` are read off these two, so they are spared with them.
    private mutating func countPitch() {
        if warmUp == nil {
            tally.add(.pitches)
            tally.add(.pitchesThisPark)
        }
        tally.add(.seen(pitch.type))
    }

    /// The hit streak is an ordinary counted stat and a warm-up ends it like anything else. The
    /// home-run streak is the one carve-out: during a Warm Up only the Warm Up's own streak is
    /// ended, and the career's is left exactly where the last career pitch left it.
    private mutating func endStreaks() {
        tally.set(.hitStreak, 0)
        if warmUp == nil { tally.set(.homeRunStreak, 0) } else { warmUp?.homeRunStreak = 0 }
    }

    /// Overwrites the `.taken` that `.pitchThrown` put down for this pitch. Nothing outside a
    /// Warm Up, and nothing to the streak — `countContact` and `endStreaks` own that.
    private mutating func recordWarmUpPitch(_ p: WarmUpPitch) {
        guard var run = warmUp, !run.pitches.isEmpty else { return }
        run.pitches[run.pitches.count - 1] = p
        warmUp = run
    }

    private mutating func countContact(_ l: Launch, _ f: FlightResult) {
        let r = statRules
        tally.add(.swings)
        if !pitch.isStrike { tally.add(.chases) }
        tally.add(.hits)
        tally.add(.hits(pitch.type))
        tally.extend(.hitStreak, best: .bestHitStreak)

        tally.add(.exitVelocitySum, l.exitVelocityMPH)
        tally.add(.launchAngleSum, l.launchAngleDegrees)
        tally.raise(.bestExitVelocityMPH, to: l.exitVelocityMPH)
        tally.raise(.highestApexFeet, to: f.apexFeet)
        if let hang = f.hangTime { tally.raise(.longestHangTime, to: hang) }
        if r.isBarrel(exitVelocityMPH: l.exitVelocityMPH, launchAngleDegrees: l.launchAngleDegrees) {
            tally.add(.barrels)
        }
        if f.apexFeet >= r.moonshotApexFeet { tally.add(.moonshots) }
        switch l.launchAngleDegrees {
        case ..<r.lineDriveFrom: tally.add(.groundBalls)
        case ..<r.flyBallFrom: tally.add(.lineDrives)
        case ..<r.popUpFrom: tally.add(.flyBalls)
        default: tally.add(.popUps)
        }

        let d = f.distanceFeet.rounded()
        tally.add(.totalFeet, d)
        tally.raise(.longestFeet, to: d)
        if f.wallHit { tally.add(.wallHits) }

        if f.homeRun {
            tally.add(.homeRuns)
            tally.add(.homeRuns(pitch.type))
            // What this streak had to beat when it began (#41). Written as the streak leaves 0,
            // so a save from a build that never had the key is right from its first streak
            // rather than from never. `streakNow` is whichever streak is live, and neither has
            // moved yet.
            if streakNow == 0 { tally.set(.bestHomeRunStreakAtStreakStart, tally[.bestHomeRunStreak]) }
            if var run = warmUp {
                // The Warm Up's own streak. The career's best still carries it: the ten are
                // Show-league pitches, so a streak made in them is a streak (§18, Claude's
                // reading of "counts toward everything but the cost", unreviewed).
                run.homeRunStreak += 1
                warmUp = run
                tally.raise(.bestHomeRunStreak, to: Double(run.homeRunStreak))
            } else {
                tally.extend(.homeRunStreak, best: .bestHomeRunStreak)
                // The park's own count (#40). Career only: the day's ten are thrown in the day's
                // park, not the one being cleared, so nothing in a Warm Up clears it (§18).
                tally.add(.homeRunsThisPark)
            }
            let past = f.distanceFeet - park.wallDistanceFeet
            if past >= r.noDoubterMarginFeet { tally.add(.noDoubters) }
            if past < r.wallScraperMarginFeet { tally.add(.wallScrapers) }
            if l.launchAngleDegrees <= r.laserMaxAngle { tally.add(.lasers) }
        } else if warmUp == nil {
            tally.set(.homeRunStreak, 0)
        } else {
            warmUp?.homeRunStreak = 0
        }
    }

    /// The day's books, closed when the tenth pitch's hold ends. The in-a-row count needs
    /// yesterday's day, which is the one bookkeeping key the tally carries for this.
    @discardableResult
    private mutating func countWarmUp(_ r: WarmUpResult) -> WarmUpBests {
        tally.add(.warmUps)
        // What the day beat, worked out *before* the raises below: afterwards the bests are this
        // day's own and there is nothing left to compare it against (#41). It rides out on
        // `.warmUpEnded`, because nothing of a day may be left standing on the machine (§18).
        let beaten = WarmUpBests(
            feet: tally.value(ifRecorded: .warmUpBestFeet).map { Double(r.totalFeet) > $0 } ?? false,
            homeRuns: tally.value(ifRecorded: .warmUpBestHomeRuns).map { Double(r.homeRuns) > $0 } ?? false)
        tally.raise(.warmUpBestFeet, to: Double(r.totalFeet))
        tally.raise(.warmUpBestHomeRuns, to: Double(r.homeRuns))
        let today = Double(WarmUp.serial(of: r.day))
        if let last = tally.value(ifRecorded: .warmUpLastDay), today == last + 1 {
            tally.add(.warmUpDaysInARow)
        } else {
            tally.set(.warmUpDaysInARow, 1)
        }
        tally.raise(.bestWarmUpDaysInARow, to: tally[.warmUpDaysInARow])
        tally.set(.warmUpLastDay, today)
        return beaten
    }

    /// Fires once, right when the ball clears the wall: the streak (already extended by
    /// `countContact`, which ran at contact, well before this cue) says how many shells, the
    /// call-up forces a finale, and a no-doubter can add one more. DESIGN.md §17 "How big
    /// follows the streak" and "Seed".
    private mutating func startFireworksIfEarned(_ f: FlightResult) {
        // The finale belongs to the call-up, and since #40 the call-up is the home run that makes
        // Triple-A's count: the two before it get the ordinary show their streak has earned.
        // `countContact` ran at contact, so the count is already up to date here.
        let isCalledUp = park.league == .tripleA && homeRunsThisPark >= homeRunsToClearPark
        let isNoDoubter = f.distanceFeet - park.wallDistanceFeet >= statRules.noDoubterMarginFeet
        // `streakNow`, not the career's: during a Warm Up the live streak is the Warm Up's, and
        // the show has to follow it without knowing there are two (DESIGN.md §18).
        let shells = fireworksRules.shellCount(homeRunStreak: streakNow, isCalledUp: isCalledUp, isNoDoubter: isNoDoubter)
        guard shells > 0 else { return }
        // A Warm Up does not move `pitches`, so its own count goes in to keep the day's ten
        // shows from all being the same one. Nil outside a Warm Up: the career seed is what it was.
        let seed = UInt64(park.number) &* 0x2545_F491_4F6C_DD1D &+ UInt64(tally.pitches + (warmUp?.spent ?? 0))
        fireworks = FireworksShow(shellCount: shells, seed: seed, start: tally[.secondsPlayed], lampsOn: lampsOn)
    }

    // MARK: - Clock

    @discardableResult
    public mutating func tick(_ dt: Double) -> [Transition] {
        // Counted down in every beat, not just `.windup` (#46): a cue that started during
        // `.result` or `.miss` has already spent part of itself by the time the next windup
        // reads it, and one still running when the cap cuts a windup short decays away quietly
        // through the beats that follow rather than ambushing a later one.
        tally.add(.secondsPlayed, dt)
        musicRemaining = max(0, musicRemaining - dt)
        // Whether *this* tick is held for the organ. Computed once, ahead of the switch, so the
        // windup clock (`elapsed`) and the hold clock (`musicHoldElapsed`) can never both move on
        // the same tick — the whole point is that one of them stands still while the other does.
        let holdingForMusic = beat == .windup && musicRemaining > 0 && musicHoldElapsed < timings.maxMusicHold
        if holdingForMusic { musicHoldElapsed += dt } else { elapsed += dt }
        var out: [Transition] = []
        switch beat {
        case .windup:
            if advanceOwed && !isAtCeiling {
                // The ceiling lifted with a call-up owed: pay it between pitches, and start the
                // windup again under the new park's rules. `.calledUp` already played. This runs
                // whether or not the windup above is mid-hold — an owed advance is never made to
                // wait on the organist (#46).
                advanceOwed = false
                advancePark(&out, announcing: false)
                newPitch()
            } else if queuedWarmUp != nil {
                // Same rule: the day's ten take the field at the next windup, hold or no hold.
                beginQueuedWarmUp(&out)
            } else if holdingForMusic {
                // The organist is still playing: `elapsed` stayed at whatever it was (0, for an
                // ordinary fresh windup), so `AtBatScene.drawPitcher` keeps drawing the set pose
                // with no scene change (#46, DESIGN.md §11).
            } else if elapsed > timings.windup {
                enter(.pitch)
                // A pitch is spent the moment it is thrown, as a `.taken` that the swing then
                // overwrites: quit with one in the air and it comes back taken (DESIGN.md §18).
                if warmUp != nil { warmUp?.pitches.append(.taken) }
                out.append(.pitchThrown)
            }
        case .pitch:
            if elapsed > pitch.duration * timings.pitchOverrun + timings.takeGrace {
                if sliceInProgress {
                    // A slice was in progress when the pitch timed out: it resolves as a swing
                    // and a miss, with markers, exactly like `sliceMissed()` — never a call
                    // (DESIGN.md §3).
                    sliceMissed()
                } else {
                    countPitch()
                    if pitch.isStrike {
                        tally.add(.calledStrikes)
                        endStreaks()
                        calledStrikesInARow += 1
                        if calledStrikesInARow == 2 { out.append(.calledStrikesInARow) }
                    } else {
                        tally.add(.ballsTaken)
                        if !statRules.takenBallKeepsStreak { endStreaks() }
                        calledStrikesInARow = 0
                    }
                    let call: Call = pitch.isStrike ? .strike : .ball
                    lastCall = call
                    out.append(.called(call))
                    enter(.miss)
                }
            }
        case .miss:
            if elapsed > timings.missHold {
                if warmUp?.isSpent == true { endWarmUp(&out) } else { newPitch() }
            }
        case .contact:
            if elapsed > contactHoldNow { enter(.flight); out.append(.flash); out.append(.cutToWide) }
        case .flight:
            guard let f = flight else { enter(.result); beginResultHold(&out); break }
            let before = Int(playbackIndex)
            playbackIndex += dt * (1.0 / FlightParams.calibrated.timestep) * timings.flightSpeed
            let after = min(f.points.count - 1, Int(playbackIndex))
            if let i = wallCueIndex, before < i, i <= after {
                out.append(f.homeRun ? .clearedWall : .hitWall)
                if f.homeRun { startFireworksIfEarned(f) }
            }
            if let i = landCueIndex, before < i, i <= after { out.append(.landed) }
            // The rare things count as playback reaches them, once each, exactly the way the
            // wall and the ground do — so a bird is counted when the ball goes through it and
            // not when the bat met it (#5).
            for event in parkEvents where before < event.index && event.index <= after {
                tally.add(event.kind.stat)
                parkScars.record(event)
            }
            if playbackIndex >= Double(f.points.count - 1) {
                playbackIndex = Double(max(0, f.points.count - 1))
                enter(.result)
                beginResultHold(&out)
            }
        case .result:
            if elapsed > timings.resultHold {
                // The home run that made this park's count, and only that one (#40). A warm-up
                // home run changes nothing about where the career stands: no park change, no
                // `.calledUp`, and the ceiling is not consulted (DESIGN.md §18) — `clearsTheParkNow`
                // carries all three.
                if clearsTheParkNow {
                    if isAtCeiling {
                        advanceOwed = true
                        out.append(.calledUp)
                    } else {
                        advanceOwed = false
                        advancePark(&out, announcing: true)
                    }
                }
                recordNow = nil        // the number it was set against is coming off the screen
                flight = nil
                launch = nil
                fireworks = nil        // the next pitch gets a clean sky (DESIGN.md §17 "When")
                parkEvents = []        // …and no feathers still falling in it (#5)
                if warmUp?.isSpent == true { endWarmUp(&out) } else { newPitch() }
                out.append(.cutToAtBat)
            }
        }
        return out
    }

    /// The landing number is going up, and with it whatever record it just set (#41). Once per
    /// result hold, and only for a swing — a taken pitch goes to `.miss` and never comes here.
    ///
    /// **The one departure from the issue**, which puts the fewest-pitches celebration "at the
    /// park change": the park change is the *end* of this hold and the cut back to the plate, so
    /// there is no frame left to draw it in. The number is settled here anyway — `pitchesThisPark`
    /// stops moving the moment the home run is hit — so it is celebrated in the same hold that
    /// says `PARK CLEARED`, which is where a player is already looking. Claude's, unreviewed.
    private mutating func beginResultHold(_ out: inout [Transition]) {
        recordNow = nil
        guard let before = tallyBeforeSwing else { return }
        // `clearsThePark` is whether the park really changes when this hold ends: at the ceiling
        // it does not, so `fewestPitchesToClearPark` is not written and nothing has fallen yet.
        let swing = RecordSwing(streakBefore: streakBeforeSwing, streakAfter: streakNow,
                                clearsThePark: clearsTheParkNow && !isAtCeiling)
        guard let kind = Records.kind(before: before, after: tally, swing: swing,
                                      rules: recordRules) else { return }
        recordNow = kind
        out.append(.newRecord(kind))
    }

    /// A cleared park: the books close on it and the next one is generated. `announcing` is
    /// false when the call-up was already announced by the home run that earned it (§16).
    private mutating func advancePark(_ out: inout [Transition], announcing: Bool) {
        tally.add(.parksCleared)
        tally.lower(.fewestPitchesToClearPark, to: tally[.pitchesThisPark])
        tally.set(.pitchesThisPark, 0)
        tally.set(.homeRunsThisPark, 0)    // the next park asks for its own three (#40)
        parkScars = ParkScars()        // a new park, with its lights on and its glass in (#5)
        let wasMinors = park.league.isMinors
        park = Park.generate(number: park.number + 1, ladder: ladder)
        out.append(.parkChanged(park))
        if wasMinors && !park.league.isMinors {
            tally.set(.pitchesToTheShow, tally[.pitches])
            if announcing { out.append(.calledUp) }
        }
    }

    // MARK: - The Warm Up (DESIGN.md §18)

    /// The day's ten take the field at a windup, never in the middle of a pitch. The career's
    /// park and next pitch are set aside and the windup starts again under the day's park.
    private mutating func beginQueuedWarmUp(_ out: inout [Transition]) {
        guard let run = queuedWarmUp else { return }
        queuedWarmUp = nil
        parkSetAside = park
        pitchSetAside = pitch
        scarsSetAside = parkScars
        parkScars = ParkScars()
        warmUp = run
        park = run.card.park
        pitch = run.card.pitches[min(run.spent, run.total - 1)]
        sliceInProgress = false
        out.append(.warmUpBegan)
        enter(.windup)
    }

    /// The tenth has resolved and its hold has played out. The career gets the field back
    /// exactly as it left it — its park, its next pitch, its generator never drawn from — and
    /// nothing of the Warm Up is left standing behind it, so what the career can see of a day's
    /// ten is the stats they counted and nothing else.
    private mutating func endWarmUp(_ out: inout [Transition]) {
        guard let run = warmUp else { return }
        let beaten = countWarmUp(run.result)
        warmUp = nil
        park = parkSetAside ?? park
        pitch = pitchSetAside ?? pitch
        parkScars = scarsSetAside ?? ParkScars()
        parkSetAside = nil
        pitchSetAside = nil
        scarsSetAside = nil
        flight = nil
        launch = nil
        fireworks = nil
        parkEvents = []
        recordNow = nil
        clockAtContact = 0
        playbackIndex = 0
        wallCueIndex = nil
        landCueIndex = nil
        closeCutIndex = nil
        contactQuality = 0
        tallyBeforeSwing = nil
        streakBeforeSwing = 0
        lastCall = nil
        calledStrikesInARow = 0
        sliceInProgress = false
        enter(.windup)
        out.append(.warmUpEnded(run.result, beaten))
    }

    /// The one door into a beat, and so the one place the phase is taken up: every path that
    /// reaches a windup — a new pitch, a Warm Up taking the field, a Warm Up handing it back —
    /// comes through here (DESIGN.md §20 "The phase is an input of the machine").
    private mutating func enter(_ b: Beat) {
        beat = b
        elapsed = 0
        musicHoldElapsed = 0
        if b == .windup { phase = phaseOffered }
    }

    /// Inside a Warm Up the next pitch is the next one off the day's card; the career's
    /// generator is not touched until the career has the field back.
    private mutating func newPitch() {
        if let run = warmUp {
            pitch = run.card.pitches[min(run.spent, run.total - 1)]
        } else {
            pitch = Pitching.generate(using: &rng, rules: pitchingRules)
        }
        sliceInProgress = false
        enter(.windup)
    }

    // MARK: - Replay (#4)

    /// A machine standing at the moment before a recorded slice: this park, these career numbers,
    /// this pitch already on its way. `Replay.machine(from:)` is the only caller — `beat`, `pitch`
    /// and `warmUp` are `private(set)`, so a recorded swing cannot be replayed without a door, and
    /// this is a smaller one than making them settable. Nothing here is random: the generator is
    /// seeded 0 because a replay never reaches the next pitch.
    ///
    /// `warmUp`, when given, is restored exactly as it stood the instant before the slice — the
    /// same `.taken` placeholder for this pitch that `.pitchThrown` would have appended — so
    /// `slice(_:)` overwrites it once, `streakNow` and the fireworks seed read the Warm Up rather
    /// than falling back to the career, and the on-screen labels agree with the corner (#33,
    /// DESIGN.md §18/§19). `parkSetAside`/`pitchSetAside` are deliberately left nil: a replay never
    /// ticks far enough to hand the field back, and if it ever did, leaving them nil rather than
    /// guessing at the career's park is the honest failure.
    /// `elapsed` is how far into the pitch beat to stand: zero for the moment before a recorded
    /// slice, and the lead-in's start for a replay that begins a few frames earlier (#42).
    ///
    /// `phase` is the recorded one, and it is set **before** `slice(_:)` is ever called on this
    /// machine — a windup is what normally takes a phase up, and a replay never stands in one.
    /// Without it a clip would light its fireworks for the wrong sky and could lose a lights-out
    /// shot the player watched (DESIGN.md §19, §20).
    public static func atPitch(park: Park, tally: Tally, pitch: Pitch, warmUp: WarmUpRun? = nil,
                               elapsed: Double = 0, phase: DayPhase = .midday,
                               timings: Timings = .standard, sliceRules: SliceRules = .standard,
                               pitchingRules: PitchingRules = .standard, statRules: StatRules = .standard,
                               fireworksRules: FireworksRules = .standard, ladder: Ladder = .standard) -> DerbyMachine {
        var m = DerbyMachine(seed: 0, park: park, tally: tally, timings: timings,
                             sliceRules: sliceRules, pitchingRules: pitchingRules,
                             statRules: statRules, fireworksRules: fireworksRules, ladder: ladder,
                             phase: phase)
        m.pitch = pitch
        m.beat = .pitch
        m.elapsed = max(0, elapsed)
        m.warmUp = warmUp
        return m
    }
}
