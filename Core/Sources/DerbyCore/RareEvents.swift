import Foundation

/// The rare things a batted ball can do to a park (#5, DESIGN.md §17 "Rare things").
///
/// **Nothing here changes how the ball flies.** The flight is integrated once, at contact, and an
/// event is something that arc happens to pass through: it is *detected* from the finished
/// `FlightResult` and the park's seeded scenery, *counted* once as playback reaches it, and
/// *drawn* as a two-frame burst. Rarity comes from geometry and a seed, never from a die rolled
/// at contact — a landmark is in park 87 or it is not, and the ball either reaches it or it does
/// not, the same way for everyone.
public enum ParkEventKind: String, Equatable, CaseIterable, Codable {
    /// A ball through a bird: `chalk` feathers, and the bird is gone for the rest of its crossing.
    case birdStrike
    /// A ball through the blimp that hangs over every park past 100.
    case blimpHit
    /// A ball into the out-of-town board: a dent that stays until the park changes.
    case scoreboardDent
    /// A ball through the board's one lit pane, which is the smaller target inside the larger one.
    case windowBroken
    /// A no-doubter into the light standard over the wall: `score` sparks, and that bank is dark
    /// for the rest of the park.
    case lightsOut

    /// The career number this one adds to.
    public var stat: Stat {
        switch self {
        case .birdStrike: return .birdsHit
        case .blimpHit: return .blimpsHit
        case .scoreboardDent: return .scoreboardDents
        case .windowBroken: return .windowsBroken
        case .lightsOut: return .lightsOut
        }
    }
}

/// Where an event is drawn. The two halves of the park keep their own units: the sky is screen
/// space, because that is where a bird or a blimp is, and everything behind the wall is in feet,
/// because that is where the ball is.
public enum EventPlace: Equatable {
    /// x as a fraction of the view's width, y in design pixels.
    case sky(xFraction: Double, y: Double)
    /// Feet from the plate, feet above the ground.
    case field(xFeet: Double, yFeet: Double)
}

/// One rare thing, found on one flight.
public struct ParkEvent: Equatable {
    public let kind: ParkEventKind
    /// Where in `flight.points` it happens. The machine counts it as playback crosses this, once,
    /// exactly the way the `.clearedWall` cue fires.
    public let index: Int
    public let place: EventPlace
    /// Which one it happened to: a struck bird's place in its flock, or a dark bank's index
    /// among `Scenery.allTowers`. Zero where there is only ever one of the thing.
    public let target: Int
    /// The crossing a struck bird belongs to. There is no bird state anywhere to mark, so the
    /// strike names the bird and the sky leaves it out (DESIGN.md §17 "Everything is a pure
    /// function").
    public let flockSlot: Int

    public init(kind: ParkEventKind, index: Int, place: EventPlace,
                target: Int = 0, flockSlot: Int = 0) {
        self.kind = kind; self.index = index; self.place = place
        self.target = target; self.flockSlot = flockSlot
    }
}

/// One drawn speck of a burst, as an offset from the event's place. Closed form like a firework:
/// every speck's position is `f(seed, t)` and there is no particle state anywhere.
public struct EventParticle: Equatable {
    public let dx: Double
    public let dy: Double
    /// 1 or 2 design pixels square.
    public let size: Int
    public let colour: Role
    /// False while it is between blinks. With no alpha nothing fades: it blinks, shrinks or stops.
    public let visible: Bool

    /// Borrowed by role, one palette line (docs/palette.md). The scene turns these into pixels.
    public enum Role: Equatable { case chalk, score, ink, cap }
}

/// The knobs behind every rare thing: how close counts, and what the burst looks like.
public struct RareEventRules: Equatable {
    /// §17: "a ball passing within 2 px" of a bird bursts it. The ball's own radius is added, so
    /// this is clearance between the two and not between their middles.
    public var birdReachPixels: Double = 2
    /// The blimp's envelope, and how far outside it still counts. A much bigger target than a
    /// bird and a much rarer sky to be in: it is only up about half the time.
    public var blimpWidthPixels: Double = 21
    public var blimpHeightPixels: Double = 7
    public var blimpReachPixels: Double = 1
    /// How big the ball is drawn in the close framing, which is the only one a sky strike is
    /// ever judged in (DESIGN.md §9: a 6 px ball there).
    public var ballRadiusClosePixels: Double = 3
    /// The ball is drawn this far above the point it is at, in both framings.
    public var ballDrawnAbovePixels: Double = 3
    /// Only the sky below this design row is ever asked about a bird: above it there is nothing
    /// but stars, and below it a bird has never flown (`SceneryRules.birdBand` tops out at 52).
    public var skyBottomPixels: Double = 96

    /// How close to the middle of a lamp bank a shot has to pass, in feet. §17 wants this to be
    /// worth a career, so it is deliberately tight: at 18 ft a bank went out on one hard swing
    /// in six in a park that had one (measured, 2026-09-19).
    public var bankReachFeet: Double = 10
    /// §17: it takes a **no-doubter** to put a bank out. A wall-scraper that happens to graze one
    /// is not the shot the spec means.
    public var lightsOutNeedsNoDoubter = true

    /// How long a burst lasts and when its specks start blinking out, in seconds.
    public var burstSeconds: Double = 0.5
    public var burstBlinkFrom: Double = 0.62
    /// Specks step in whole pixels at this rate, like everything else that is not the ball (§9).
    public var burstStepsPerSecond: Double = 10
    /// Feathers drift; sparks are thrown; shards are thrown harder. Pixels a second, and pixels
    /// a second squared downward.
    public var featherCount = 7
    public var featherSpeed: ClosedRange<Double> = 6...16
    public var featherGravity: Double = 26
    public var sparkCount = 14
    public var sparkSpeed: ClosedRange<Double> = 20...52
    public var sparkGravity: Double = 70
    public var shardCount = 10
    public var shardSpeed: ClosedRange<Double> = 14...40
    public var shardGravity: Double = 90

    public init() {}
    public static let standard = RareEventRules()
}

/// Finding the rare things, and drawing them.
public enum RareEvents {

    // MARK: - Detection

    /// Every rare thing this flight does, in the order it does them. A pure function of the park,
    /// its seeded scenery, the finished flight and the clock the machine already owns — which is
    /// exactly the set of things a `Replay` record carries, so a clip shows the player the same
    /// event they saw (DESIGN.md §19).
    ///
    /// `clockAtContact` is `Tally[.secondsPlayed]` as `slice(_:)` was called, and `contactHold`
    /// the freeze that follows it: together with the playback speed they say what the sky looks
    /// like at each point of the flight *without* reading the clock again. That is deliberate.
    /// Reading the live clock would make the answer depend on where the frames happened to fall,
    /// and a clip is ticked at a fixed 60 Hz while a phone is not.
    public static func detect(park: Park, scenery: Scenery, flight: FlightResult,
                              birdSeed: UInt64, blimpSeed: UInt64,
                              clockAtContact: Double, contactHold: Double,
                              flightSpeed: Double,
                              statRules: StatRules = .standard,
                              rules: RareEventRules = .standard,
                              sideViewRules: SideViewRules = .standard,
                              cameraRules: CameraRules = .standard,
                              skyLifeRules: SkyLifeRules = .standard,
                              sceneryRules: SceneryRules = .standard) -> [ParkEvent] {
        let points = flight.points
        guard !points.isEmpty, flightSpeed > 0 else { return [] }
        let wall = park.wallDistanceFeet
        var out: [ParkEvent] = []

        // MARK: Behind the wall, in feet. No camera is involved at all: the ball either goes
        // through the thing or it does not, which is the same answer on every phone.
        if let board = scenery.board {
            // The whole path through the panel, not just the point it went in at. A ball comes
            // down steeply and crosses the board's top edge a foot above the pane, so asking
            // only about the first point inside made the pane unbreakable — every shot that
            // went on to pass clean through it was counted as an ordinary dent.
            var firstInside: (Int, FlightPoint)? = nil
            var throughThePane: (Int, FlightPoint)? = nil
            for (i, p) in points.enumerated() where p.xFeet >= wall {
                guard board.contains(xFeet: p.xFeet, yFeet: p.yFeet, wallDistanceFeet: wall) else {
                    if firstInside != nil { break }      // out the other side; it is done
                    continue
                }
                if firstInside == nil { firstInside = (i, p) }
                if throughThePane == nil,
                   board.paneContains(xFeet: p.xFeet, yFeet: p.yFeet, wallDistanceFeet: wall) {
                    throughThePane = (i, p)
                }
            }
            if let (i, p) = throughThePane ?? firstInside {
                out.append(ParkEvent(kind: throughThePane != nil ? .windowBroken : .scoreboardDent,
                                     index: i, place: .field(xFeet: p.xFeet, yFeet: p.yFeet)))
            }
        }

        if let tower = scenery.wallTower, let bank = scenery.wallTowerIndex,
           !rules.lightsOutNeedsNoDoubter
            || flight.distanceFeet - wall >= statRules.noDoubterMarginFeet {
            let bx = wall + tower.feetBehindWall
            for (i, p) in points.enumerated() where p.xFeet >= wall - rules.bankReachFeet {
                let dx = p.xFeet - bx, dy = p.yFeet - tower.heightFeet
                guard (dx * dx + dy * dy).squareRoot() <= rules.bankReachFeet else { continue }
                out.append(ParkEvent(kind: .lightsOut, index: i,
                                     place: .field(xFeet: bx, yFeet: tower.heightFeet),
                                     target: bank))
                break
            }
        }

        // MARK: The sky. A bird's x is a fraction of the view and its y is an absolute design
        // row, so a wider phone stretches one and not the other: judged on the phone's own
        // canvas, whether a strike counted would depend on which phone it was, and judged on a
        // canonical one it would stop matching what that phone actually drew.
        //
        // There is one framing where the question has the same answer everywhere, and it is the
        // good one: **the close camera with the ball pinned under the headroom.** There the ball
        // sits at exactly `closeHeadroom` whatever the canvas is (that is what the lift is for),
        // and its x is a fixed fraction of the width, because the close scale is itself
        // proportional to the width. So a sky strike is a close-camera moment by construction —
        // the tight shot where a towering fly hangs against the top of the frame — and every
        // phone, and the clip, agree about it. (`safeLeft`/`safeRight` move it by a pixel or
        // two on a notched phone; nothing else does.)
        let width = sideViewRules.designWidth
        var wantBird = true
        var wantBlimp = scenery.hasBlimp
        let step = FlightParams.calibrated.timestep / flightSpeed

        // The sky steps ten times a second and the flight is sampled 240 times, so the same
        // flock answers for about fifty points in a row. Asking once per step rather than once
        // per point is the difference between a swing costing a fraction of a millisecond and
        // costing tens of them; it changes no answer, because the step is what the sky is
        // quantised to in the first place.
        var skyStep = Int.min
        var flock: [Bird] = []
        var balloon: Blimp? = nil
        let cut = SideView.closeCutIndex(flight: flight, wallDistanceFeet: wall, rules: cameraRules)

        for (i, p) in points.enumerated() {
            guard wantBird || wantBlimp else { break }
            let camera = SideView.camera(at: i, closeCutIndex: cut)
            guard camera == .close else { continue }
            let view = SideView.framing(camera: camera, park: park, flight: flight,
                                        ballFeet: p.yFeet, width: width, rules: sideViewRules)
            // Pinned, or this frame is not one every canvas agrees about.
            guard view.ground > sideViewRules.groundY else { continue }
            let bx = view.x(p.xFeet)
            let by = view.y(p.yFeet) - rules.ballDrawnAbovePixels
            guard by <= rules.skyBottomPixels, by >= -8, bx >= -8, bx <= width + 8 else { continue }
            let ball = rules.ballRadiusClosePixels
            let time = clockAtContact + contactHold + Double(i) * step

            let thisStep = Int((time * skyLifeRules.stepsPerSecond).rounded(.down))
            if thisStep != skyStep {
                skyStep = thisStep
                flock = wantBird
                    ? SkyLife.birds(seed: birdSeed, at: time, breeze: scenery.breezePixelsPerSecond,
                                    rules: skyLifeRules, scenery: sceneryRules)
                    : []
                balloon = wantBlimp
                    ? SkyLife.blimp(seed: blimpSeed, at: time, breeze: scenery.breezePixelsPerSecond,
                                    rules: skyLifeRules, scenery: sceneryRules)
                    : nil
            }

            if wantBird {
                let reach = rules.birdReachPixels + ball
                for bird in flock {
                    let dx = bird.x * width - bx, dy = bird.y - by
                    guard (dx * dx + dy * dy).squareRoot() <= reach else { continue }
                    out.append(ParkEvent(kind: .birdStrike, index: i,
                                         place: .sky(xFraction: bird.x, y: bird.y),
                                         target: bird.index, flockSlot: bird.slot))
                    wantBird = false
                    break
                }
            }

            if wantBlimp, let blimp = balloon {
                // A box, not a disc: a blimp is a long thing and clipping its nose counts.
                let halfW = rules.blimpWidthPixels / 2 + rules.blimpReachPixels + ball
                let halfH = rules.blimpHeightPixels / 2 + rules.blimpReachPixels + ball
                if abs(blimp.x * width - bx) <= halfW, abs(blimp.y - by) <= halfH {
                    out.append(ParkEvent(kind: .blimpHit, index: i,
                                         place: .sky(xFraction: blimp.x, y: blimp.y)))
                    wantBlimp = false
                }
            }
        }

        return out.sorted { $0.index < $1.index }
    }

    // MARK: - The burst

    /// The specks of one event's burst, `since` seconds after it happened. Empty once it is over.
    /// Closed form, whole pixels, two frames' worth of life and then nothing — no alpha anywhere
    /// (DESIGN.md §17 "The rules it lives inside").
    public static func burst(_ kind: ParkEventKind, seed: UInt64, since: Double,
                             rules: RareEventRules = .standard) -> [EventParticle] {
        guard since >= 0, since < rules.burstSeconds else { return [] }
        let (count, speed, gravity, colour) = shape(of: kind, rules: rules)
        // The specks step on the same grid everything else in the sky does.
        let t = (since * rules.burstStepsPerSecond).rounded(.down) / rules.burstStepsPerSecond
        let life = since / rules.burstSeconds
        // The last stretch blinks: on one step, off the next, until it is simply gone.
        let blinking = life >= rules.burstBlinkFrom
        let onThisStep = Int(since * rules.burstStepsPerSecond).isMultiple(of: 2)

        var g = SplitMix64(seed: seed &+ UInt64(count) &* 0x9E37_79B9_7F4A_7C15)
        return (0..<count).map { i in
            let angle = (Double(i) + Double.random(in: 0...0.8, using: &g)) / Double(count) * 2 * .pi
            let v = Double.random(in: speed, using: &g)
            return EventParticle(
                dx: (cos(angle) * v * t).rounded(),
                dy: (sin(angle) * v * t + gravity * t * t / 2).rounded(),
                size: life < 0.5 ? 2 : 1,
                colour: colour,
                visible: !blinking || onThisStep)
        }
    }

    private static func shape(of kind: ParkEventKind, rules: RareEventRules)
        -> (Int, ClosedRange<Double>, Double, EventParticle.Role) {
        switch kind {
        case .birdStrike:
            return (rules.featherCount, rules.featherSpeed, rules.featherGravity, .chalk)
        case .blimpHit:
            return (rules.featherCount, rules.featherSpeed, rules.featherGravity, .chalk)
        case .lightsOut:
            return (rules.sparkCount, rules.sparkSpeed, rules.sparkGravity, .score)
        case .scoreboardDent:
            return (rules.shardCount, rules.shardSpeed, rules.shardGravity, .chalk)
        case .windowBroken:
            return (rules.shardCount, rules.shardSpeed, rules.shardGravity, .chalk)
        }
    }
}

/// What a park still carries from earlier in it: a dark bank, a dent, a hole where a pane was.
/// Cleared the moment the park changes, so it is scenery and never a save (#5: "the bank stays
/// dark until the park changes").
public struct ParkScars: Equatable {
    /// Indices into `Scenery.allTowers`.
    public private(set) var darkBanks: Set<Int> = []
    /// Where on the board the dents are, as (x feet, y feet), in the order they arrived.
    public private(set) var dents: [ReplayPoint] = []
    public private(set) var paneIsBroken = false

    public init() {}

    public var isEmpty: Bool { darkBanks.isEmpty && dents.isEmpty && !paneIsBroken }

    mutating func record(_ event: ParkEvent) {
        switch event.kind {
        case .lightsOut: darkBanks.insert(event.target)
        case .scoreboardDent:
            if case let .field(x, y) = event.place { dents.append(ReplayPoint(x: x, y: y)) }
        case .windowBroken: paneIsBroken = true
        case .birdStrike, .blimpHit: break
        }
    }
}
