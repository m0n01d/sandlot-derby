import Foundation

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
        public init(slash: Point, trail: [Point]) {
            self.slash = ReplayPoint(slash)
            self.trail = trail.map(ReplayPoint.init)
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

    /// Takes the record at the moment of contact. `machine` must be the machine as it stood
    /// **before** `slice(_:)` ran — `GameController.recordSlice` captures it on the line above
    /// the call.
    public init(capturing machine: DerbyMachine, crossing: SliceCrossing,
                slash: Point, trail: [Point]) {
        version = 1
        park = ParkRecord(machine.park)
        pitch = PitchRecord(machine.pitch)
        swing = SwingRecord(crossing)
        tally = machine.tally
        marks = Marks(slash: slash, trail: trail)
    }

    /// A machine standing at the very start of the contact beat, with the swing already counted.
    /// Tick it at a fixed `dt` and it walks the same beats, chooses the same `flightCamera`, puts
    /// on the same fireworks show and stops on the same landing number as the original.
    public static func machine(from replay: Replay) -> DerbyMachine {
        var m = DerbyMachine.atPitch(park: replay.park.park, tally: replay.tally,
                                     pitch: replay.pitch.pitch)
        m.slice(replay.swing.crossing)
        return m
    }

    /// True when this swing is worth a clip at all. Only a home run is offered one (#4).
    public var isHomeRun: Bool {
        Replay.machine(from: self).flight?.homeRun ?? false
    }
}
