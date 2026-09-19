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
    /// Freeze on the slash before the cut.
    public var contactHold: Double = 0.35
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

public struct Tally: Equatable {
    public var pitches = 0
    public var hits = 0
    public var homeRuns = 0
    public var longestFeet = 0
    /// The score. Total feet, forever, never reset.
    public var totalFeet = 0
    public init() {}
}

/// What the scene needs to do in response to a tick. The machine never touches a node.
public enum Transition: Equatable {
    case pitchThrown
    case cutToWide
    case cutToAtBat
    case flash
    case parkChanged(Park)
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
    public var timings: Timings
    public var sliceRules: SliceRules
    public var pitchingRules: PitchingRules
    private var rng: SplitMix64

    public init(seed: UInt64, park: Park = .first, timings: Timings = .standard,
                sliceRules: SliceRules = .standard, pitchingRules: PitchingRules = .standard) {
        var g = SplitMix64(seed: seed)
        let first = Pitching.generate(using: &g, rules: pitchingRules)
        self.park = park
        self.timings = timings
        self.sliceRules = sliceRules
        self.pitchingRules = pitchingRules
        self.rng = g
        self.pitch = first
    }

    /// Pitch progress, 0 at release and 1 at the plate. Only meaningful during `.pitch`.
    public var pitchProgress: Double { elapsed / pitch.duration }

    /// The ball right now during the pitch, in at-bat design units.
    public var ballNow: BallSample { Pitching.ball(pitch, at: min(1.15, pitchProgress), rules: pitchingRules) }

    public var playbackPoint: FlightPoint? {
        guard let f = flight, !f.points.isEmpty else { return nil }
        let i = min(f.points.count - 1, Int(playbackIndex))
        return f.points[i]
    }

    // MARK: - Inputs

    /// Called by the scene when `Contact.test` returned `.contact` during `.pitch`.
    public mutating func slice(_ crossing: SliceCrossing) {
        guard beat == .pitch else { return }
        let l = Contact.resolve(crossing, pitch: pitch, rules: sliceRules)
        let f = Flight.simulate(exitVelocityMPH: l.exitVelocityMPH, launchAngleDegrees: l.launchAngleDegrees,
                                wallDistanceFeet: park.wallDistanceFeet, wallHeightFeet: park.wallHeightFeet)
        tally.pitches += 1
        tally.hits += 1
        if f.homeRun { tally.homeRuns += 1 }
        let d = Int(f.distanceFeet.rounded())
        tally.totalFeet += d
        if d > tally.longestFeet { tally.longestFeet = d }
        launch = l
        flight = f
        playbackIndex = 0
        lastCall = nil
        enter(.contact)
    }

    /// Called when the finger lifts during `.pitch` without a contact.
    public mutating func sliceMissed() {
        guard beat == .pitch else { return }
        tally.pitches += 1
        lastCall = .miss
        enter(.miss)
    }

    // MARK: - Clock

    @discardableResult
    public mutating func tick(_ dt: Double) -> [Transition] {
        elapsed += dt
        var out: [Transition] = []
        switch beat {
        case .windup:
            if elapsed > timings.windup { enter(.pitch); out.append(.pitchThrown) }
        case .pitch:
            if elapsed > pitch.duration * timings.pitchOverrun + timings.takeGrace {
                tally.pitches += 1
                lastCall = pitch.isStrike ? .strike : .ball
                enter(.miss)
            }
        case .miss:
            if elapsed > timings.missHold { newPitch() }
        case .contact:
            if elapsed > timings.contactHold { enter(.flight); out.append(.flash); out.append(.cutToWide) }
        case .flight:
            guard let f = flight else { enter(.result); break }
            playbackIndex += dt * (1.0 / FlightParams.calibrated.timestep) * timings.flightSpeed
            if playbackIndex >= Double(f.points.count - 1) {
                playbackIndex = Double(max(0, f.points.count - 1))
                enter(.result)
            }
        case .result:
            if elapsed > timings.resultHold {
                if let f = flight, f.homeRun {
                    park = Park.generate(number: park.number + 1)
                    out.append(.parkChanged(park))
                }
                flight = nil
                launch = nil
                newPitch()
                out.append(.cutToAtBat)
            }
        }
        return out
    }

    private mutating func enter(_ b: Beat) {
        beat = b
        elapsed = 0
    }

    private mutating func newPitch() {
        pitch = Pitching.generate(using: &rng, rules: pitchingRules)
        enter(.windup)
    }
}
