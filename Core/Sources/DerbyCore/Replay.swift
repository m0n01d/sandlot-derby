import Foundation

/// What a batted ball has to be to be worth seeing again (#42).
public enum ReplayWorth: String, Codable, Hashable, CaseIterable {
    case homeRun
    case offTheWall
}

/// The knobs for a replay — what is offered one, how far before the slash it starts, and how long
/// the loop rests on the landing number (#42, DESIGN.md §19). The pixels the clip is written at
/// are `ReplayClipRules`, in the app; these are the rules of the thing itself, so they live here
/// with the record and can be tested.
public struct ReplayRules: Equatable {
    /// How long before contact a replay begins: the last of the pitch arriving and the finger's
    /// stroke being drawn, so the slash lands on something rather than opening cold. Dwight, from
    /// an iPad mini 6: "for clips the replays needs to start a few frames before the bat makes
    /// contact." 0.4 s is 24 frames at 60.
    public var leadInSeconds = 0.4
    /// Which batted balls earn the camera in the corner. A home run always; a ball off the wall
    /// because it is the other one you want to show someone. Nothing that stays in the park.
    public var offeredFor: Set<ReplayWorth> = [.homeRun, .offTheWall]
    /// How long the on-screen replay rests on the landing number before it starts again. Long
    /// enough to read the number, short enough that the loop is a loop and not a slideshow.
    /// Not in the clip: a written clip ends on the cut back to the plate, as it always has.
    public var loopHoldSeconds = 0.8

    public init() {}
    public static let standard = ReplayRules()

    /// Whether this flight is worth the corner camera. Takes the two facts rather than a
    /// `FlightResult`, so the app can ask it from the live machine at the result without
    /// rebuilding anything.
    public func offers(homeRun: Bool, offTheWall: Bool) -> Bool {
        (homeRun && offeredFor.contains(.homeRun)) || (offTheWall && offeredFor.contains(.offTheWall))
    }
}

/// A point in design space, flat and `Codable`. The geometry types carry no conformances of
/// their own, so this file is the one place the record's shape on the wire is fixed.
public struct ReplayPoint: Codable, Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public init(_ p: Point) { self.init(x: p.x, y: p.y) }
    public var point: Point { Point(x: x, y: y) }
}

/// Everything one swing needs to be drawn again, frame for frame (#4, DESIGN.md §19).
///
/// The record keeps the *inputs*, never the derived state: the park, the pitch, the crossing the
/// finger made, and every career number as it stood the instant **before** `slice(_:)` ran.
/// `machine(from:)` replays that one call, so the launch, the flight, the cue indices, the
/// hitstop, the fireworks seed and the landing number are all recomputed by the same code that
/// produced them live. Nothing here can drift out of step with the game, because none of it is a
/// copy of anything the game works out for itself.
///
/// Two fields are not inputs at all: `marks` is the slash and the finger trail, which live in the
/// at-bat scene rather than in the machine (DESIGN.md §3 draws them over the contact freeze) and
/// so have to be carried. Everything else a frame reads — the sky, the clouds, the birds, the
/// fireworks — is already a pure function of the park and the machine's own clock.
public struct Replay: Codable, Equatable {

    /// The park as it stood, not a number to be regenerated: a clip has to survive a later change
    /// to `Park.Rules` or the `Ladder` that would move the wall.
    public struct ParkRecord: Codable, Equatable {
        public var number: Int
        public var wallDistanceFeet: Double
        public var wallHeightFeet: Double
        public var isNight: Bool

        public init(_ p: Park) {
            number = p.number
            wallDistanceFeet = p.wallDistanceFeet
            wallHeightFeet = p.wallHeightFeet
            isNight = p.isNight
        }

        public var park: Park {
            Park(number: number, wallDistanceFeet: wallDistanceFeet,
                 wallHeightFeet: wallHeightFeet, isNight: isNight)
        }
    }

    /// The pitch that was swung at. The type travels as its name: `PitchType` is a fixed table
    /// (`PitchType.all`) and the name is the key `Tally` already counts by, so a clip carries
    /// three fewer numbers. An unknown name falls back to the fastball rather than failing —
    /// a clip is a brag, not a save.
    public struct PitchRecord: Codable, Equatable {
        public var typeName: String
        public var speedMPH: Double
        public var isStrike: Bool
        public var target: ReplayPoint

        public init(_ p: Pitch) {
            typeName = p.type.name
            speedMPH = p.speedMPH
            isStrike = p.isStrike
            target = ReplayPoint(p.target)
        }

        public var pitch: Pitch {
            let type = PitchType.all.first { $0.name == typeName } ?? .fastball
            return Pitch(type: type, speedMPH: speedMPH, isStrike: isStrike, target: target.point)
        }
    }

    /// The crossing the finger made. `Contact.resolve` turns this back into the same `Launch`,
    /// and `Flight.simulate` into the same arc.
    public struct SwingRecord: Codable, Equatable {
        public var quality: Double
        public var progress: Double
        public var swingAngleDegrees: Double
        public var power: Double
        public var ball: ReplayPoint
        public var ballRadius: Double
        public var crossingPoint: ReplayPoint

        public init(_ c: SliceCrossing) {
            quality = c.quality
            progress = c.progress
            swingAngleDegrees = c.swingAngleDegrees
            power = c.power
            ball = ReplayPoint(c.ball.position)
            ballRadius = c.ball.radius
            crossingPoint = ReplayPoint(c.crossingPoint)
        }

        public var crossing: SliceCrossing {
            SliceCrossing(quality: quality, progress: progress,
                          swingAngleDegrees: swingAngleDegrees, power: power,
                          ball: BallSample(x: ball.x, y: ball.y, radius: ballRadius),
                          crossingPoint: crossingPoint.point)
        }
    }

    /// The two draw-only things the machine does not know: the direction of the slash through the
    /// ball, and the finger's trail behind it. Both are in the centred 320-wide column, the space
    /// `AtBatScene` draws in, so a clip rendered at a fixed 320 puts them exactly where the player
    /// saw them whatever the phone's width was.
    public struct Marks: Codable, Equatable {
        public var slash: ReplayPoint
        public var trail: [ReplayPoint]
        /// When each trail sample was taken, in seconds **relative to contact** — so every one is
        /// zero or negative and the last is the one the slash goes through. The lead-in draws the
        /// prefix that had happened by then (#42). Optional, and one per `trail` point when it is
        /// there: a record written before the lead-in existed has no times, and a replay of it
        /// simply has no lead-in, the way it always did.
        public var trailTimes: [Double]?
        public init(slash: Point, trail: [Point], times: [Double]? = nil) {
            self.slash = ReplayPoint(slash)
            self.trail = trail.map(ReplayPoint.init)
            trailTimes = (times?.count == trail.count) ? times : nil
        }
    }

    /// The Warm Up in progress the instant before `slice(_:)` ran, nil for a career swing (#33,
    /// DESIGN.md §18/§19). Optional so records written before this field existed still decode —
    /// `Replay` has always been forward-compatible that way (see `testRecordWithoutWarmUpKeyStillDecodes`).
    ///
    /// The **whole card** travels by value, not the day alone. `WarmUp.generate(day:)` is a pure
    /// function of `WarmUpRules`, `PitchingRules` and `Ladder`, every one of which can move later
    /// the same way `Park.Rules` can move the wall — which is exactly why `ParkRecord` above
    /// already keeps the park's numbers rather than regenerating them from `park.number`.
    /// Regenerating the card from `day` alone would silently swap in a different ten pitches (or
    /// even a different park) the moment any of those tables changed under a shipped clip. `park`
    /// and `pitches` here reuse the same `ParkRecord`/`PitchRecord` wrappers the rest of this file
    /// already carries, so nothing new travels on the wire that has not already been proven.
    public struct WarmUpRecord: Codable, Equatable {
        /// The local calendar day, `YYYYMMDD` — kept for the corner label and the card, even
        /// though the card itself is not regenerated from it.
        public var day: Int
        public var park: ParkRecord
        /// All ten of the day's pitches, in order, so `DerbyMachine.newPitch()` can find the next
        /// one exactly as the live game would, whatever `PitchingRules` looks like by the time the
        /// clip is replayed.
        public var pitches: [PitchRecord]
        /// One entry per pitch spent before and including this one — the last is `.taken`, the
        /// placeholder `slice(_:)` is about to overwrite (DESIGN.md §18: "a pitch is spent at
        /// `.pitchThrown`"). Its count is the pitch index; no separate field carries it.
        public var results: [WarmUpPitch]
        /// Consecutive home runs inside this Warm Up, before this swing.
        public var homeRunStreak: Int

        public init(_ run: WarmUpRun) {
            day = run.card.day
            park = ParkRecord(run.card.park)
            pitches = run.card.pitches.map(PitchRecord.init)
            results = run.pitches
            homeRunStreak = run.homeRunStreak
        }

        /// Rebuilds the `WarmUpRun` `DerbyMachine.atPitch` needs. `rules` is not carried: nothing
        /// downstream of a replayed swing reads `WarmUp.rules` (only `WarmUpResult.number(rules:)`
        /// and `.shareText(rules:)` do, and neither is reachable from a rebuilt machine), so the
        /// default is exactly as good as the original.
        public var run: WarmUpRun {
            let card = WarmUp(day: day, park: park.park, pitches: pitches.map(\.pitch))
            return WarmUpRun(card: card, pitches: results, homeRunStreak: homeRunStreak)
        }
    }

    /// Bumped if the shape ever changes under a clip that has been shared as data rather than as
    /// a file. 1 is the first.
    public var version: Int
    public var park: ParkRecord
    public var pitch: PitchRecord
    public var swing: SwingRecord
    /// Every career number as it stood **before** the swing, so replaying `slice(_:)` counts it
    /// once and arrives at the same streak, the same pitch count and the same `secondsPlayed` the
    /// frames read for the clouds and the fireworks.
    public var tally: Tally
    public var marks: Marks
    /// Nil for a career swing; see `WarmUpRecord` (#33).
    public var warmUp: WarmUpRecord?
    /// The pitch beat's own clock the instant the slash landed — `DerbyMachine.elapsed` while the
    /// beat is `.pitch`, which is what `pitchProgress` is worked out from. Without it there is
    /// nowhere to stand the machine for a lead-in (#42). Optional, so records written before the
    /// lead-in existed decode and simply open on the freeze, the way they always did.
    public var pitchElapsedAtContact: Double?

    /// Takes the record at the moment of contact. `machine` must be the machine as it stood
    /// **before** `slice(_:)` ran — `GameController.recordSlice` captures it on the line above
    /// the call.
    ///
    /// `trailTimes`, when given, is one time per trail point in seconds relative to contact
    /// (zero or negative); `AtBatScene` keeps them alongside the points it already kept.
    public init(capturing machine: DerbyMachine, crossing: SliceCrossing,
                slash: Point, trail: [Point], trailTimes: [Double]? = nil) {
        version = 1
        park = ParkRecord(machine.park)
        pitch = PitchRecord(machine.pitch)
        swing = SwingRecord(crossing)
        tally = machine.tally
        marks = Marks(slash: slash, trail: trail, times: trailTimes)
        warmUp = machine.warmUp.map(WarmUpRecord.init)
        pitchElapsedAtContact = machine.beat == .pitch ? machine.elapsed : nil
    }

    /// A machine standing at the very start of the contact beat, with the swing already counted.
    /// Tick it at a fixed `dt` and it walks the same beats, chooses the same `flightCamera`, puts
    /// on the same fireworks show and stops on the same landing number as the original — and, if
    /// this swing was made during a Warm Up, `warmUp` is restored too, so `streakNow`, the
    /// fireworks seed and the on-screen labels all read the Warm Up rather than falling back to
    /// the career (#33).
    public static func machine(from replay: Replay) -> DerbyMachine {
        var m = DerbyMachine.atPitch(park: replay.park.park, tally: replay.tally,
                                     pitch: replay.pitch.pitch, warmUp: replay.warmUp?.run)
        m.slice(replay.swing.crossing)
        return m
    }

    /// True when this swing is worth a clip at all. Only a home run is offered one (#4).
    public var isHomeRun: Bool {
        Replay.machine(from: self).flight?.homeRun ?? false
    }

    /// Whether the corner camera is offered for this swing (#42). Rebuilds the machine, so the
    /// app asks its own live machine at the result instead — this is for tests and for a record
    /// that arrives from somewhere else.
    public func isWorthSeeingAgain(rules: ReplayRules = .standard) -> Bool {
        guard let f = Replay.machine(from: self).flight else { return false }
        return rules.offers(homeRun: f.homeRun, offTheWall: f.wallHit)
    }

    // MARK: - The lead-in (#42)

    /// How much lead-in this record can actually give: the rule's, but never more pitch than
    /// there was. Zero for a record written before the pitch clock was kept, which replays from
    /// the freeze exactly as it always did.
    public func leadInSeconds(rules: ReplayRules = .standard) -> Double {
        guard let atContact = pitchElapsedAtContact else { return 0 }
        return max(0, min(rules.leadInSeconds, atContact))
    }

    /// A machine standing in `.pitch`, `leadInSeconds` short of the slash: the ball still on its
    /// way, the pitch and the park and the Warm Up all as they were. Tick it at a fixed `dt` and
    /// it walks the last of the pitch the player saw.
    ///
    /// `secondsPlayed` is wound **back** by the lead-in, because the record's tally is the one at
    /// contact and the sky reads that clock (DESIGN.md §17 "One clock") — without the roll-back
    /// the clouds would drift 0.4 s ahead through the lead-in and then jump back at the slash.
    ///
    /// This machine is thrown away at contact: `machine(from:)` above is what draws the freeze
    /// and everything after it, so nothing the lead-in accumulates can drift into the clip. The
    /// lead-in itself is only as exact as the `dt` it is ticked at, which is the honest answer —
    /// the live game ticked it at whatever the display gave.
    public static func leadInMachine(from replay: Replay, rules: ReplayRules = .standard) -> DerbyMachine {
        let lead = replay.leadInSeconds(rules: rules)
        var tally = replay.tally
        tally.set(.secondsPlayed, max(0, tally[.secondsPlayed] - lead))
        return DerbyMachine.atPitch(park: replay.park.park, tally: tally,
                                    pitch: replay.pitch.pitch, warmUp: replay.warmUp?.run,
                                    elapsed: max(0, (replay.pitchElapsedAtContact ?? 0) - lead))
    }

    /// The finger's stroke as it stood `secondsBeforeContact` before the slash: the samples that
    /// had already been made. `AtBatScene` draws these through the very same two lines it draws
    /// the live finger's with.
    public func stroke(secondsBeforeContact: Double) -> [Point] {
        guard let times = marks.trailTimes, times.count == marks.trail.count else { return [] }
        let now = -max(0, secondsBeforeContact)
        var out: [Point] = []
        for (i, t) in times.enumerated() where t <= now { out.append(marks.trail[i].point) }
        return out
    }
}
