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

    // Streaks.
    public static let homeRunStreak = Stat("homeRunStreak")
    public static let bestHomeRunStreak = Stat("bestHomeRunStreak")
    public static let hitStreak = Stat("hitStreak")
    public static let bestHitStreak = Stat("bestHitStreak")

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
    public var timings: Timings
    /// The knobs as they stand in The Show and beyond. The minors lay a `Rung` over them.
    public var majorsSliceRules: SliceRules
    public var majorsPitchingRules: PitchingRules
    public var statRules: StatRules
    public var fireworksRules: FireworksRules
    public var ladder: Ladder
    /// Whether a finger is on the glass right now, mirrored in every frame by the app (whatever
    /// the beat is or where the finger landed — a slice is "in progress" whenever a finger is
    /// down, DESIGN.md §3). If the pitch times out while this is true, `tick` resolves it as a
    /// miss, not a take. Also reset to false at the start of every new pitch, so a caller driving
    /// `DerbyMachine` directly (as the Core tests do) doesn't have to clear it back down itself.
    public var sliceInProgress = false
    private var rng: SplitMix64
    private var wallCueIndex: Int? = nil
    private var landCueIndex: Int? = nil
    /// The quality of the swing that made contact, 0…1, carried from `slice(_:)` into
    /// `contactHoldNow`.
    private var contactQuality: Double = 0

    /// The rules in force in this park. Scenes read these, never the majors' ones.
    public var sliceRules: SliceRules { ladder.sliceRules(majorsSliceRules, for: park.league) }
    public var pitchingRules: PitchingRules { ladder.pitchingRules(majorsPitchingRules, for: park.league) }
    /// The help this park gives, nil from The Show on.
    public var rung: Rung? { ladder.rung(for: park.league) }
    /// Whether this park has a ballpark organ (#17). The Show always does; a rung follows its
    /// own `organ` flag — a sandlot has no organist. Claude's call, unreviewed (DESIGN.md §11).
    public var hasOrgan: Bool { rung?.organ ?? true }

    /// `park` and `tally` are what a save restores; everything else starts fresh.
    public init(seed: UInt64, park: Park = .first, tally: Tally = Tally(), timings: Timings = .standard,
                sliceRules: SliceRules = .standard, pitchingRules: PitchingRules = .standard,
                statRules: StatRules = .standard, fireworksRules: FireworksRules = .standard, ladder: Ladder = .standard) {
        var g = SplitMix64(seed: seed)
        let first = Pitching.generate(using: &g, rules: ladder.pitchingRules(pitchingRules, for: park.league))
        self.park = park
        self.tally = tally
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

    /// True through the result hold of the home run that clears Triple-A.
    public var isBeingCalledUp: Bool {
        beat == .result && park.league == .tripleA && (flight?.homeRun ?? false)
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

    /// True when a home run here cannot move the player on.
    public var isAtCeiling: Bool { parkCeiling.map { park.number >= $0 } ?? false }

    /// The flight framing right now: a pure function of the flight and how much of it has played,
    /// so a replay cuts exactly where the live game did. Only `.flight` is ever close; the
    /// result hold always cuts back out.
    public var flightCamera: FlightCamera {
        guard beat == .flight, let f = flight else { return .wide }
        let wall = park.wallDistanceFeet
        guard let reach = f.points.map(\.xFeet).max(), reach >= wall - cameraRules.closeReachFeet,
              let cut = f.points.firstIndex(where: { $0.xFeet >= wall - cameraRules.closeLeadFeet })
        else { return .wide }
        return playbackIndex >= Double(cut) ? .close : .wide
    }

    public var playbackPoint: FlightPoint? {
        guard let f = flight, !f.points.isEmpty else { return nil }
        let i = min(f.points.count - 1, Int(playbackIndex))
        return f.points[i]
    }

    // MARK: - Inputs

    /// Called by the scene when `Contact.test` returned `.contact` during `.pitch`.
    public mutating func slice(_ crossing: SliceCrossing) {
        guard beat == .pitch else { return }
        calledStrikesInARow = 0
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
        playbackIndex = 0
        lastCall = nil
        contactQuality = min(1, max(0, crossing.quality))
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
        enter(.miss)
    }

    // MARK: - Counting

    private mutating func countPitch() {
        tally.add(.pitches)
        tally.add(.pitchesThisPark)
        tally.add(.seen(pitch.type))
    }

    private mutating func endStreaks() {
        tally.set(.homeRunStreak, 0)
        tally.set(.hitStreak, 0)
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
            tally.extend(.homeRunStreak, best: .bestHomeRunStreak)
            let past = f.distanceFeet - park.wallDistanceFeet
            if past >= r.noDoubterMarginFeet { tally.add(.noDoubters) }
            if past < r.wallScraperMarginFeet { tally.add(.wallScrapers) }
            if l.launchAngleDegrees <= r.laserMaxAngle { tally.add(.lasers) }
        } else {
            tally.set(.homeRunStreak, 0)
        }
    }

    /// Fires once, right when the ball clears the wall: the streak (already extended by
    /// `countContact`, which ran at contact, well before this cue) says how many shells, the
    /// call-up forces a finale, and a no-doubter can add one more. DESIGN.md §17 "How big
    /// follows the streak" and "Seed".
    private mutating func startFireworksIfEarned(_ f: FlightResult) {
        let isCalledUp = park.league == .tripleA
        let isNoDoubter = f.distanceFeet - park.wallDistanceFeet >= statRules.noDoubterMarginFeet
        let shells = fireworksRules.shellCount(homeRunStreak: tally.homeRunStreak, isCalledUp: isCalledUp, isNoDoubter: isNoDoubter)
        guard shells > 0 else { return }
        let seed = UInt64(park.number) &* 0x2545_F491_4F6C_DD1D &+ UInt64(tally.pitches)
        fireworks = FireworksShow(shellCount: shells, seed: seed, start: tally[.secondsPlayed], isNight: park.isNight)
    }

    // MARK: - Clock

    @discardableResult
    public mutating func tick(_ dt: Double) -> [Transition] {
        elapsed += dt
        tally.add(.secondsPlayed, dt)
        var out: [Transition] = []
        switch beat {
        case .windup:
            if advanceOwed && !isAtCeiling {
                // The ceiling lifted with a call-up owed: pay it between pitches, and start the
                // windup again under the new park's rules. `.calledUp` already played.
                advanceOwed = false
                advancePark(&out, announcing: false)
                newPitch()
            } else if elapsed > timings.windup { enter(.pitch); out.append(.pitchThrown) }
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
            if elapsed > timings.missHold { newPitch() }
        case .contact:
            if elapsed > contactHoldNow { enter(.flight); out.append(.flash); out.append(.cutToWide) }
        case .flight:
            guard let f = flight else { enter(.result); break }
            let before = Int(playbackIndex)
            playbackIndex += dt * (1.0 / FlightParams.calibrated.timestep) * timings.flightSpeed
            let after = min(f.points.count - 1, Int(playbackIndex))
            if let i = wallCueIndex, before < i, i <= after {
                out.append(f.homeRun ? .clearedWall : .hitWall)
                if f.homeRun { startFireworksIfEarned(f) }
            }
            if let i = landCueIndex, before < i, i <= after { out.append(.landed) }
            if playbackIndex >= Double(f.points.count - 1) {
                playbackIndex = Double(max(0, f.points.count - 1))
                enter(.result)
            }
        case .result:
            if elapsed > timings.resultHold {
                if let f = flight, f.homeRun {
                    if isAtCeiling {
                        advanceOwed = true
                        out.append(.calledUp)
                    } else {
                        advanceOwed = false
                        advancePark(&out, announcing: true)
                    }
                }
                flight = nil
                launch = nil
                fireworks = nil        // the next pitch gets a clean sky (DESIGN.md §17 "When")
                newPitch()
                out.append(.cutToAtBat)
            }
        }
        return out
    }

    /// A cleared park: the books close on it and the next one is generated. `announcing` is
    /// false when the call-up was already announced by the home run that earned it (§16).
    private mutating func advancePark(_ out: inout [Transition], announcing: Bool) {
        tally.add(.parksCleared)
        tally.lower(.fewestPitchesToClearPark, to: tally[.pitchesThisPark])
        tally.set(.pitchesThisPark, 0)
        let wasMinors = park.league.isMinors
        park = Park.generate(number: park.number + 1, ladder: ladder)
        out.append(.parkChanged(park))
        if wasMinors && !park.league.isMinors {
            tally.set(.pitchesToTheShow, tally[.pitches])
            if announcing { out.append(.calledUp) }
        }
    }

    private mutating func enter(_ b: Beat) {
        beat = b
        elapsed = 0
    }

    private mutating func newPitch() {
        pitch = Pitching.generate(using: &rng, rules: pitchingRules)
        sliceInProgress = false
        enter(.windup)
    }

    // MARK: - Replay (#4)

    /// A machine standing at the moment before a recorded slice: this park, these career numbers,
    /// this pitch already on its way. `Replay.machine(from:)` is the only caller — `beat` and
    /// `pitch` are `private(set)`, so a recorded swing cannot be replayed without a door, and this
    /// is a smaller one than making them settable. Nothing here is random: the generator is seeded
    /// 0 because a replay never reaches the next pitch.
    public static func atPitch(park: Park, tally: Tally, pitch: Pitch,
                               timings: Timings = .standard, sliceRules: SliceRules = .standard,
                               pitchingRules: PitchingRules = .standard, statRules: StatRules = .standard,
                               fireworksRules: FireworksRules = .standard, ladder: Ladder = .standard) -> DerbyMachine {
        var m = DerbyMachine(seed: 0, park: park, tally: tally, timings: timings,
                             sliceRules: sliceRules, pitchingRules: pitchingRules,
                             statRules: statRules, fireworksRules: fireworksRules, ladder: ladder)
        m.pitch = pitch
        m.beat = .pitch
        m.elapsed = 0
        return m
    }
}
