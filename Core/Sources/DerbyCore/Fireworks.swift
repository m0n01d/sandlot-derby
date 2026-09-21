import Foundation

/// A colour a firework shell can borrow, by role — the same "one palette line" rule as
/// everything else (DESIGN.md §17). The app maps a role to `Palette`; `sky3` only ever turns up
/// at night, when it reads against the dark sky instead of disappearing into it by day.
public enum FireworkColour: Equatable, CaseIterable {
    case score, cap, chalk, skin, sky3
}

/// One drawn point of a firework, a riser or a burst particle. Every position is `f(seed, t)` —
/// there is no stored particle state, so `Fireworks.particles` can be called fresh every frame
/// and a replay reproduces the show exactly (DESIGN.md §17 "Everything is a pure function").
public struct FireworkParticle: Equatable {
    /// Fraction of the screen's width, left to right. Screen-space, not world feet, so a burst
    /// sits in the same place in the wide and close framings (DESIGN.md §17 "Where").
    public let x: Double
    /// Design-space y. 20...110 while bursting (DESIGN.md §17 "Where").
    public let y: Double
    /// 1 or 2 design pixels.
    public let size: Int
    /// False on the off frames of the last-life blink. No alpha: a particle blinks, shrinks or
    /// stops, it never fades (DESIGN.md §17 "the rules it lives inside").
    public let visible: Bool
    public let colour: FireworkColour

    public init(x: Double, y: Double, size: Int, visible: Bool, colour: FireworkColour) {
        self.x = x; self.y = y; self.size = size; self.visible = visible; self.colour = colour
    }
}

/// One home-run fireworks show: how many shells, and when it started. `DerbyMachine` sets this
/// the moment the ball clears the wall and holds it through the result hold (DESIGN.md §17
/// "When"). Plain data — `Fireworks.particles` is what turns it into points for an instant.
public struct FireworksShow: Equatable {
    /// Total shells, from the streak table (`FireworksRules.shellCount`).
    public let shellCount: Int
    /// Seeds every shell's burst point, particle count and jitter: park number and career pitch
    /// count (DESIGN.md §17 "Seed"), so no two shows are alike and a replay matches.
    public let seed: UInt64
    /// The machine's own clock (`Tally[.secondsPlayed]`) at the moment the ball cleared the
    /// wall — never `Date()`. `Fireworks.particles` measures elapsed time from this.
    public let start: Double
    /// `DayPhase.lampsOn` at the same moment: `sky3` is only ever offered as a colour against a
    /// dark sky. The phase, not the park, since §20 — the same park puts on a differently
    /// coloured show at noon and at nine.
    public let lampsOn: Bool

    public init(shellCount: Int, seed: UInt64, start: Double, lampsOn: Bool) {
        self.shellCount = shellCount; self.seed = seed; self.start = start; self.lampsOn = lampsOn
    }
}

/// Tuning knobs for the home-run fireworks show. DESIGN.md §17 "### Fireworks".
public struct FireworksRules: Equatable {
    // MARK: The streak table — how many shells

    /// HR streak at which the first shell fires.
    public var firstShellStreak = 3
    /// Streak at which a finale first fires, and every `finaleEvery` after.
    public var finaleStreak = 10
    public var finaleEvery = 5
    /// Shells in a finale.
    public var finaleShellCount = 10
    /// Shells fired between finales, once the streak has passed the first one.
    public var shellsBetweenFinales = 8
    /// A no-doubter (`StatRules.noDoubterMarginFeet`) adds this many shells, but only once the
    /// streak has already earned fireworks at all.
    public var noDoubterBonusShells = 1

    // MARK: A shell's timing (seconds)

    /// Shells launch this far apart.
    public var shellLaunchInterval = 0.18
    /// The riser climbs for this long before it bursts.
    public var risePeriod = 0.25
    /// A burst's particles live this long after they appear.
    public var burstLifetime = 0.7
    /// Particles blink on alternate steps for the last this many seconds of life.
    public var blinkWindow = 0.15
    /// The motion budget (§9): nothing but the ball and its trail is smooth, so blinking and
    /// jitter step no faster than this.
    public var stepRate = 10.0

    // MARK: A shell's shape

    public var particleCountRange: ClosedRange<Int> = 28...40
    /// Screen-space burst window (DESIGN.md §17 "Where"): the right 45 % of the screen...
    public var bandXRange: ClosedRange<Double> = 0.55...1.0
    /// ...between these design-space y's.
    public var burstYRange: ClosedRange<Double> = 20...80
    /// The riser climbs from here up to its burst height.
    public var riserStartY = 110.0
    /// Ring radius the particles ease outward to (fraction of screen width in x, design pixels
    /// in y — a screen-space burst is an ellipse on a wide phone, which reads fine).
    public var burstRadiusXFraction = 0.05
    public var burstRadiusY = 16.0
    /// Per-particle jitter on the ring angle (radians) and radius (fraction of the ring radius).
    public var angleJitter = 0.35
    public var radiusJitter: ClosedRange<Double> = 0.6...1.0
    /// Drag's time constant: outward travel eases toward its radius as `1 - exp(-t / dragTau)`,
    /// never a stepwise simulation, so a particle's position stays closed-form.
    public var dragTau = 0.18
    /// Gravity's pull on the burst, design pixels per second².
    public var gravity = 90.0

    public init() {}
    public static let standard = FireworksRules()

    /// Shells for a home-run streak, the call-up, and a no-doubter — DESIGN.md §17's table.
    /// `isCalledUp` wins outright ("whatever the streak"); the no-doubter bonus only ever adds
    /// to a show that already exists.
    public func shellCount(homeRunStreak streak: Int, isCalledUp: Bool, isNoDoubter: Bool) -> Int {
        let base: Int
        if isCalledUp {
            base = finaleShellCount
        } else if streak < firstShellStreak {
            base = 0
        } else if streak < finaleStreak {
            base = streak - firstShellStreak + 1
        } else if (streak - finaleStreak) % finaleEvery == 0 {
            base = finaleShellCount
        } else {
            base = shellsBetweenFinales
        }
        guard base > 0 else { return 0 }
        return base + (isNoDoubter ? noDoubterBonusShells : 0)
    }
}

/// Turns a `FireworksShow` into the particles on screen at one instant. Pure and closed-form:
/// nothing here is a simulation with state carried frame to frame, so calling this twice with
/// the same arguments always gives the same answer back (DESIGN.md §17 "Everything is a pure
/// function").
public enum Fireworks {
    /// Every particle alight at `time` (the machine's clock) for `show`.
    public static func particles(show: FireworksShow, at time: Double, rules: FireworksRules = .standard) -> [FireworkParticle] {
        let t = time - show.start
        guard t >= 0 else { return [] }
        var out: [FireworkParticle] = []
        for shell in 0..<max(0, show.shellCount) {
            let local = t - Double(shell) * rules.shellLaunchInterval
            guard local >= 0 else { continue }

            var g = shellRNG(show.seed, shell)
            let bandWidth = rules.bandXRange.upperBound - rules.bandXRange.lowerBound
            let shellX = rules.bandXRange.lowerBound + Double.random(in: 0..<1, using: &g) * bandWidth
            let shellY = Double.random(in: rules.burstYRange, using: &g)
            let colour = pickColour(using: &g, night: show.lampsOn)
            let count = Int.random(in: rules.particleCountRange, using: &g)

            if local < rules.risePeriod {
                let p = local / rules.risePeriod
                out.append(FireworkParticle(x: shellX, y: rules.riserStartY + (shellY - rules.riserStartY) * p,
                                             size: 1, visible: true, colour: .chalk))
                continue
            }

            let burstT = local - rules.risePeriod
            guard burstT < rules.burstLifetime else { continue }
            let outward = 1 - exp(-burstT / rules.dragTau)
            let fallY = 0.5 * rules.gravity * burstT * burstT
            let lifeLeft = rules.burstLifetime - burstT
            let size = burstT < rules.burstLifetime / 2 ? 2 : 1
            var visible = true
            if lifeLeft <= rules.blinkWindow {
                let step = Int(((rules.burstLifetime - lifeLeft) * rules.stepRate).rounded(.down))
                visible = step.isMultiple(of: 2)
            }

            for i in 0..<count {
                // A fresh generator per particle, advanced from the shell's own seed by a fixed
                // number of draws — so a particle's jitter is `f(seed, shell, i)` and never
                // depends on the particles drawn before it (no stored state, drawn or otherwise).
                var pg = particleRNG(show.seed, shell, i)
                let baseAngle = 2 * Double.pi * Double(i) / Double(count)
                let angle = baseAngle + Double.random(in: -rules.angleJitter...rules.angleJitter, using: &pg)
                let radius = Double.random(in: rules.radiusJitter, using: &pg)
                let x = shellX + cos(angle) * radius * rules.burstRadiusXFraction * outward
                let y = shellY + sin(angle) * radius * rules.burstRadiusY * outward + fallY
                out.append(FireworkParticle(x: x, y: y, size: size, visible: visible, colour: colour))
            }
        }
        return out
    }

    private static func shellRNG(_ seed: UInt64, _ shell: Int) -> SplitMix64 {
        SplitMix64(seed: seed &+ UInt64(shell) &* 0x9E37_79B9_7F4A_7C15)
    }

    private static func particleRNG(_ seed: UInt64, _ shell: Int, _ particle: Int) -> SplitMix64 {
        SplitMix64(seed: seed &+ UInt64(shell) &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(particle + 1) &* 0xD1B5_4A32_D192_ED03)
    }

    private static func pickColour<G: RandomNumberGenerator>(using g: inout G, night: Bool) -> FireworkColour {
        let roles: [FireworkColour] = night ? [.score, .cap, .chalk, .skin, .sky3] : [.score, .cap, .chalk, .skin]
        return roles[Int.random(in: 0..<roles.count, using: &g)]
    }
}
