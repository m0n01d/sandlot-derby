import Foundation

/// One fixed star. Seeded per park and never moves; the only thing that changes is whether it is
/// alight this instant (DESIGN.md §17 "Night kit": forty of them, one in eight blinking).
public struct Star: Equatable {
    /// Fraction of the view's width. A fraction because the canvas is wider than 320 on a modern
    /// phone and Core does not know how wide.
    public let xFraction: Double
    /// Design pixels from the top. The screen is always 224 tall, so this one is absolute, and
    /// the band it sits in is dark in both views' skies.
    public let y: Double
    /// Seconds between winks, nil for a star that simply burns — seven in eight of them.
    public let blinkPeriod: Double?
    /// Where in that period this star starts, so forty of them never wink together.
    public let blinkPhase: Double

    public init(xFraction: Double, y: Double, blinkPeriod: Double?, blinkPhase: Double) {
        self.xFraction = xFraction; self.y = y
        self.blinkPeriod = blinkPeriod; self.blinkPhase = blinkPhase
    }
}

/// One stadium light tower: an `ink` lattice pole carrying a lamp bank (DESIGN.md §17 "Stadium
/// lights at night"). Night parks only, two to four of them, seeded. Core carries where it
/// stands and how big the bank is; the scene knows what a lattice looks like.
public struct Tower: Equatable {
    /// How far behind the wall it stands, in feet. World space, so the side view's two cameras
    /// place it at the same spot in the park and the close one simply sees it bigger.
    public let feetBehindWall: Double
    /// How high the pole carries its bank, in feet. Tall enough that the close camera runs it
    /// out of the top of the frame and the bank is a thing you see in the wide one.
    public let heightFeet: Double
    /// The lamp grid on top.
    public let bankColumns: Int
    public let bankRows: Int

    public init(feetBehindWall: Double, heightFeet: Double, bankColumns: Int, bankRows: Int) {
        self.feetBehindWall = feetBehindWall; self.heightFeet = heightFeet
        self.bankColumns = bankColumns; self.bankRows = bankRows
    }
}

/// One bird of a flock, at one instant. There is no bird state anywhere: `SkyLife.birds` is
/// `f(seed, t)` exactly the way `Fireworks.particles` is, so a replay (#4) flies the same flock
/// across the same sky (DESIGN.md §17 "Everything is a pure function").
public struct Bird: Equatable {
    /// Fraction of the view's width, and design pixels down. Always above `birdBand`'s top, which
    /// is well clear of the scoreboard and nowhere near the zone (§17).
    public let x: Double
    public let y: Double
    /// Two flap frames and no more (§17). Neighbours in a flock are on opposite beats, so a
    /// flock ripples rather than marching.
    public let wingsUp: Bool

    public init(x: Double, y: Double, wingsUp: Bool) {
        self.x = x; self.y = y; self.wingsUp = wingsUp
    }
}

/// The clocks behind everything in the sky that moves, and the crowd under it. Seeded *shapes*
/// live in `SceneryRules`; these are the rates, and every one of them obeys §9's motion budget —
/// the ball and its trail are the only smooth things on screen, so nothing here steps faster
/// than 10 Hz and nothing here has more than two frames.
public struct SkyLifeRules: Equatable {

    // MARK: Stars

    /// How long a blinking star is out each time round. A wink, not a strobe: with no alpha a
    /// star can only be there or not, so it is away for a moment and back for seconds.
    public var starBlinkOffSeconds = 0.4

    // MARK: The lights

    /// On a home run the banks chase bank to bank in two frames, this many steps a second, for
    /// as long as the cheer plays (`DerbyMachine.crowdIsUp`). Steady the rest of the time.
    public var chaseStepsPerSecond = 5.0

    // MARK: The crowd and the flags

    /// The crowd bounces in two frames while the cheer plays and sits still otherwise. Half the
    /// speckle is up on each step, so the stand ripples instead of sliding.
    public var crowdBounceStepsPerSecond = 8.0
    /// How far a raised head lifts. One pixel: it is a speckle, not a sprite.
    public var crowdBounceLift = 1.0
    /// The flags' two flutter frames. Slow enough to read as cloth at this size.
    public var flutterStepsPerSecond = 5.0

    // MARK: Birds

    /// A flock every 20–40 s (§17), built out of one slot this long with its start jittered
    /// inside it: consecutive flocks are `flockSlotSeconds ± flockStartJitter` apart, which is
    /// 20–40 s exactly, and the whole thing stays closed-form.
    public var flockSlotSeconds = 30.0
    public var flockStartJitter = 10.0
    public var flockSize: ClosedRange<Int> = 1...5
    /// A bird's own speed across the view, in fractions of the width per second, before the
    /// breeze is added to it.
    public var birdSpeedFraction: ClosedRange<Double> = 0.10...0.16
    /// How far off each edge a flock starts and finishes, so none of them pops into being.
    public var flockMargin = 0.08
    /// How far apart down the line the birds of a flock trail, and how much that wanders.
    public var flockSpacingFraction = 0.035
    public var flockSpacingJitter = 0.02
    /// How far above and below the flock's line a bird may sit.
    public var flockSpreadPixels = 4
    /// Wing beats a second: two frames at 4 Hz (§17).
    public var flapsPerSecond = 4.0
    /// Birds cross in whole pixels at this rate, like everything else that is not the ball.
    public var stepsPerSecond = 10.0
    /// The design column a breeze in pixels per second is quoted against, so a breeze can be
    /// added to a speed that is a fraction of the width.
    public var designWidth = 320.0

    public init() {}
    public static let standard = SkyLifeRules()
}

/// The sky's life, and the crowd's: stars that wink, banks that chase, flags that flutter, a
/// crowd that bounces, and birds that cross. Every one of them is a pure function of a seed and
/// a clock the machine owns (`Tally[.secondsPlayed]`) — never `Date()`, never stored state, so
/// two calls with the same arguments always agree and a replay reproduces the lot (DESIGN.md §17).
public enum SkyLife {

    // MARK: - Stars

    /// Whether this star is alight at `time`. A star that never blinks always is.
    public static func starIsLit(_ star: Star, at time: Double, rules: SkyLifeRules = .standard) -> Bool {
        guard let period = star.blinkPeriod, period > 0 else { return true }
        var phase = (time + star.blinkPhase).truncatingRemainder(dividingBy: period)
        if phase < 0 { phase += period }
        return phase >= rules.starBlinkOffSeconds
    }

    // MARK: - The lights, the crowd, the flags

    /// Whether tower `index`'s bank is at full blaze this instant. All of them are, steadily,
    /// until a home run clears the wall; then they chase bank to bank in two frames for as long
    /// as the cheer plays (DESIGN.md §17 "The lamps are steady during the pitch").
    public static func bankIsLit(_ index: Int, at time: Double, chasing: Bool,
                                 rules: SkyLifeRules = .standard) -> Bool {
        guard chasing else { return true }
        return alternates(time, rules.chaseStepsPerSecond, index)
    }

    /// Whether head `index` of the crowd speckle is on its way up. Half the crowd on each step,
    /// so the stand ripples; still on every step when the cheer is not playing.
    public static func crowdHeadIsUp(_ index: Int, at time: Double, cheering: Bool,
                                     rules: SkyLifeRules = .standard) -> Bool {
        guard cheering else { return false }
        return alternates(time, rules.crowdBounceStepsPerSecond, index)
    }

    /// Which of a flag's two flutter frames is showing: 0 or 1. Flags fly whatever the beat —
    /// it is the wind that moves them, not the crowd.
    public static func flutterFrame(at time: Double, rules: SkyLifeRules = .standard) -> Int {
        alternates(time, rules.flutterStepsPerSecond, 0) ? 0 : 1
    }

    // MARK: - Birds

    /// Every bird in the sky at `time`, for one view's seed. Empty most of the time: a flock
    /// crosses every 20–40 s and takes about eight seconds over it (DESIGN.md §17 "Birds").
    ///
    /// `breeze` is the park's, in design pixels per second. A flock flies downwind, and on a
    /// dead calm day it picks its own way, which is the one thing the seed decides about it.
    public static func birds(seed: UInt64, at time: Double, breeze: Double,
                             rules: SkyLifeRules = .standard,
                             scenery: SceneryRules = .standard) -> [Bird] {
        guard time >= 0, rules.flockSlotSeconds > 0 else { return [] }
        let slot = (time / rules.flockSlotSeconds).rounded(.down)
        var out: [Bird] = []
        // A flock that set off late in the slot before this one may still be crossing, so both
        // slots are asked. No flock ever outlives two.
        for s in [slot - 1, slot] where s >= 0 {
            out += flock(seed: seed, slot: s, at: time, breeze: breeze, rules: rules, scenery: scenery)
        }
        return out
    }

    private static func flock(seed: UInt64, slot: Double, at time: Double, breeze: Double,
                              rules: SkyLifeRules, scenery: SceneryRules) -> [Bird] {
        var g = SplitMix64(seed: seed &+ UInt64(slot) &* 0xBF58_476D_1CE4_E5B9)
        let start = slot * rules.flockSlotSeconds + Double.random(in: 0...rules.flockStartJitter, using: &g)
        let count = Int.random(in: rules.flockSize, using: &g)
        let lineY = Double.random(in: scenery.birdBand, using: &g).rounded()
        let base = Double.random(in: rules.birdSpeedFraction, using: &g)
        let ownWay = Bool.random(using: &g) ? 1.0 : -1.0

        // Downwind, or its own way on a dead calm day.
        let direction = breeze > 0 ? 1.0 : (breeze < 0 ? -1.0 : ownWay)
        let speed = (base + abs(breeze) / rules.designWidth) * direction
        guard speed != 0 else { return [] }

        let span = 1 + 2 * rules.flockMargin
        let local = time - start
        guard local >= 0, local < span / abs(speed) else { return [] }

        // Whole steps, ten a second at most: the ball and its trail stay the only smooth things
        // on screen (§9). The *clock* is quantised, not the time since this flock set off, so
        // the birds step on the same grid the clouds drift on (`Clouds.drift`) rather than each
        // flock keeping a private phase.
        let stepped = max(0, (time * rules.stepsPerSecond).rounded(.down) / rules.stepsPerSecond - start)
        let lead = (direction > 0 ? -rules.flockMargin : 1 + rules.flockMargin) + speed * stepped
        let beat = step(time, rules.flapsPerSecond)

        var out: [Bird] = []
        for i in 0..<count {
            var bg = SplitMix64(seed: seed &+ UInt64(slot) &* 0xBF58_476D_1CE4_E5B9
                                &+ UInt64(i + 1) &* 0x94D0_49BB_1331_11EB)
            let back = Double(i) * rules.flockSpacingFraction
                + Double.random(in: 0...rules.flockSpacingJitter, using: &bg)
            let dy = Double(Int.random(in: -rules.flockSpreadPixels...rules.flockSpreadPixels, using: &bg))
            // Neighbours beat on opposite frames, so the flock ripples instead of marching.
            out.append(Bird(x: lead - back * direction, y: lineY + dy,
                            wingsUp: (beat &+ i).isMultiple(of: 2)))
        }
        return out
    }

    // MARK: - Steps

    /// Which whole step of a `rate`-per-second clock `time` is in. Negative clocks never reach
    /// here (the machine's own only counts up), but the floor is the right answer either way.
    private static func step(_ time: Double, _ rate: Double) -> Int {
        Int((time * rate).rounded(.down))
    }

    /// The two-frame test everything here shares: step `n` and `n + 1` disagree, and an `offset`
    /// splits a crowd or a flock into halves that disagree with each other.
    private static func alternates(_ time: Double, _ rate: Double, _ offset: Int) -> Bool {
        (step(time, rate) &+ offset).isMultiple(of: 2)
    }
}
