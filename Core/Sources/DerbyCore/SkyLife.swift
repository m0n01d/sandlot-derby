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
    /// Which crossing this bird belongs to and where it is in the line. Not decoration: a bird
    /// a ball has gone through has to stay gone for the rest of that crossing (#5), and there is
    /// no bird state anywhere to mark — so the strike names the bird and the sky leaves it out.
    public let slot: Int
    public let index: Int

    public init(x: Double, y: Double, wingsUp: Bool, slot: Int = 0, index: Int = 0) {
        self.x = x; self.y = y; self.wingsUp = wingsUp
        self.slot = slot; self.index = index
    }
}

/// A blimp, crossing very slowly and very high. Past park 100 and never announced (#5). Like
/// everything else in the sky it is `f(seed, t)` with no state of its own.
public struct Blimp: Equatable {
    /// Fraction of the view's width, and design pixels down: the middle of the envelope.
    public let x: Double
    public let y: Double
    /// Which way the nose points, which is the way it is drifting.
    public let facingRight: Bool
    /// Its tail beacon, the two-frame animation a thing that does not flap is allowed (§9).
    public let beaconOn: Bool

    public init(x: Double, y: Double, facingRight: Bool, beaconOn: Bool) {
        self.x = x; self.y = y; self.facingRight = facingRight; self.beaconOn = beaconOn
    }
}

/// One beam, sweeping. Past park 500 (#5).
public struct Searchlight: Equatable {
    /// Where its foot stands, as a fraction of the view's width, and how high off the ground.
    public let xFraction: Double
    public let footY: Double
    /// Degrees from straight up, positive to the right, in whole stepped degrees.
    public let angleDegrees: Double
    public let lengthPixels: Double

    public init(xFraction: Double, footY: Double, angleDegrees: Double, lengthPixels: Double) {
        self.xFraction = xFraction; self.footY = footY
        self.angleDegrees = angleDegrees; self.lengthPixels = lengthPixels
    }
}

/// A comet across the top of the sky, past park 1,000 (#5). It never hurries and it never leaves:
/// by the time a player has come this far, the sky owes them something that is simply always there.
public struct Comet: Equatable {
    public let x: Double
    public let y: Double
    /// How long the tail is, in pixels, and which way it trails.
    public let tailPixels: Double
    public let movingRight: Bool

    public init(x: Double, y: Double, tailPixels: Double, movingRight: Bool) {
        self.x = x; self.y = y; self.tailPixels = tailPixels; self.movingRight = movingRight
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

    // MARK: Things past park 100 / 500 / 1,000 (#5)

    /// A blimp crosses on its own slot, built exactly the way a flock's is but ten times slower
    /// and three times longer: it is up for about half the time, which is what makes it
    /// something you notice rather than something you wait for.
    public var blimpSlotSeconds = 90.0
    public var blimpStartJitter = 30.0
    public var blimpSpeedFraction: ClosedRange<Double> = 0.018...0.030
    public var blimpMargin = 0.16
    /// Its tail beacon is on for a moment this often. Two frames: a thing that does not flap
    /// still only gets two (§9).
    public var blimpBeaconPeriod = 2.0
    public var blimpBeaconOnSeconds = 0.5

    /// Two beams, sweeping this far either side of straight up, once this often, in whole
    /// stepped degrees at this rate — the same 5 Hz the flags flutter at.
    public var searchlightCount = 2
    public var searchlightSweepDegrees = 32.0
    public var searchlightPeriodSeconds = 11.0
    public var searchlightStepsPerSecond = 5.0
    /// Where the two beams stand, as fractions of the view's width, and how long they reach.
    public var searchlightFeet: [Double] = [0.72, 0.9]
    public var searchlightLengthPixels = 150.0

    /// A comet crosses the top of the sky once in this long and trails this far behind itself.
    public var cometCrossSeconds = 300.0
    public var cometTailPixels = 9.0

    public init() {}
    public static let standard = SkyLifeRules()
}

/// The two directions the game looks in. They have their own skies, so their own seeds: the
/// at-bat view and the side view never share a bird or a blimp (DESIGN.md §17).
///
/// The seeds were `SkyArt`'s until #5: a rare event is *detected* in Core and only drawn in the
/// app, so the number that decides which birds are up had to be somewhere both can ask. The
/// arithmetic is unchanged, and `SkyLifeTests` fingerprints it — no park's flock moved.
public enum SkyView: Equatable, CaseIterable {
    case atBat, side

    var tag: UInt64 { self == .atBat ? 0x17 : 0x51 }

    public func birdSeed(parkNumber: Int) -> UInt64 {
        UInt64(max(0, parkNumber)) &* 0x9E37_79B9_7F4A_7C15 &+ tag
    }
    public func blimpSeed(parkNumber: Int) -> UInt64 {
        birdSeed(parkNumber: parkNumber) &+ 0xB11E_B11E_B11E_B11E
    }
    public func cometSeed(parkNumber: Int) -> UInt64 {
        birdSeed(parkNumber: parkNumber) &+ 0xC0_4E_7A_C0_4E_7A_C0
    }
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
                            wingsUp: (beat &+ i).isMultiple(of: 2),
                            slot: Int(slot), index: i))
        }
        return out
    }

    // MARK: - The blimp (#5, past park 100)

    /// The blimp over the park at `time`, or nil for the stretch between crossings. Built the
    /// same way a flock is — one slot with a jittered start — so it is closed form, has no state
    /// and reproduces in a clip.
    public static func blimp(seed: UInt64, at time: Double, breeze: Double,
                             rules: SkyLifeRules = .standard,
                             scenery: SceneryRules = .standard) -> Blimp? {
        guard time >= 0, rules.blimpSlotSeconds > 0 else { return nil }
        let slot = (time / rules.blimpSlotSeconds).rounded(.down)
        // A blimp takes far longer than its own slot to cross, so up to three are asked after.
        for s in [slot - 2, slot - 1, slot] where s >= 0 {
            if let b = blimp(seed: seed, slot: s, at: time, breeze: breeze,
                             rules: rules, scenery: scenery) { return b }
        }
        return nil
    }

    private static func blimp(seed: UInt64, slot: Double, at time: Double, breeze: Double,
                              rules: SkyLifeRules, scenery: SceneryRules) -> Blimp? {
        var g = SplitMix64(seed: seed &+ UInt64(slot) &* 0x94D0_49BB_1331_11EB &+ 0xB11E)
        let start = slot * rules.blimpSlotSeconds
            + Double.random(in: 0...rules.blimpStartJitter, using: &g)
        let y = Double.random(in: scenery.blimpBand, using: &g).rounded()
        let base = Double.random(in: rules.blimpSpeedFraction, using: &g)
        let ownWay = Bool.random(using: &g) ? 1.0 : -1.0

        let direction = breeze > 0 ? 1.0 : (breeze < 0 ? -1.0 : ownWay)
        let speed = (base + abs(breeze) / rules.designWidth / 8) * direction
        guard speed != 0 else { return nil }

        let span = 1 + 2 * rules.blimpMargin
        guard time >= start, time - start < span / abs(speed) else { return nil }

        // Whole steps on the same grid as everything else in the sky.
        let stepped = max(0, (time * rules.stepsPerSecond).rounded(.down) / rules.stepsPerSecond - start)
        let x = (direction > 0 ? -rules.blimpMargin : 1 + rules.blimpMargin) + speed * stepped
        var phase = time.truncatingRemainder(dividingBy: rules.blimpBeaconPeriod)
        if phase < 0 { phase += rules.blimpBeaconPeriod }
        return Blimp(x: x, y: y, facingRight: direction > 0,
                     beaconOn: phase < rules.blimpBeaconOnSeconds)
    }

    // MARK: - Searchlights (#5, past park 500)

    /// The beams this instant. They sweep in whole stepped degrees, and the two of them are half
    /// a period apart so they cross rather than march together.
    public static func searchlights(at time: Double, rules: SkyLifeRules = .standard) -> [Searchlight] {
        guard rules.searchlightPeriodSeconds > 0, rules.searchlightStepsPerSecond > 0 else { return [] }
        let stepped = (time * rules.searchlightStepsPerSecond).rounded(.down) / rules.searchlightStepsPerSecond
        return (0..<min(rules.searchlightCount, rules.searchlightFeet.count)).map { i in
            let phase = (stepped / rules.searchlightPeriodSeconds
                         + Double(i) / Double(max(1, rules.searchlightCount))) * 2 * .pi
            return Searchlight(xFraction: rules.searchlightFeet[i],
                               footY: 0,
                               angleDegrees: (sin(phase) * rules.searchlightSweepDegrees).rounded(),
                               lengthPixels: rules.searchlightLengthPixels)
        }
    }

    // MARK: - The comet (#5, past park 1,000)

    /// The comet, always up, always crossing. A whole-pixel step like everything else.
    public static func comet(seed: UInt64, at time: Double, rules: SkyLifeRules = .standard,
                             scenery: SceneryRules = .standard) -> Comet {
        var g = SplitMix64(seed: seed &+ 0xC0_4E_7A)
        let y = Double.random(in: scenery.cometBand, using: &g).rounded()
        let right = Bool.random(using: &g)
        let stepped = (time * rules.stepsPerSecond).rounded(.down) / rules.stepsPerSecond
        var t = (stepped / max(1, rules.cometCrossSeconds)).truncatingRemainder(dividingBy: 1)
        if t < 0 { t += 1 }
        let span = 1.2
        let travelled = -0.1 + t * span
        return Comet(x: right ? travelled : 1 - travelled,
                     y: y, tailPixels: rules.cometTailPixels, movingRight: right)
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
