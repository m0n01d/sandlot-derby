import Foundation

/// One piece of backdrop. Enums and numbers only: Core knows what a park has behind it, never
/// how to draw it (DESIGN.md §17). A park gets one far piece — a silhouette along the horizon —
/// and one near piece, a single landmark standing in front of it.
public enum Backdrop: String, Equatable, CaseIterable, Codable {
    // Far.
    case treeline, mountains, skyline, bleachers, upperDeck
    // Near.
    case house, waterTower, smokestacks, bridge, palms, ferrisWheel, lightPoles, pennants

    /// The kit a seeded park draws its far piece from (DESIGN.md §17).
    public static let farKit: [Backdrop] = [.skyline, .mountains, .treeline]
    /// And its near piece. The ladder's own pieces (`bleachers`, `upperDeck`, `house`,
    /// `lightPoles`, `pennants`) are fixed by the table and never drawn at random.
    public static let nearKit: [Backdrop] = [.waterTower, .smokestacks, .bridge, .palms, .ferrisWheel]

    public var isFar: Bool {
        switch self {
        case .treeline, .mountains, .skyline, .bleachers, .upperDeck: return true
        default: return false
        }
    }
    public var isNear: Bool { !isFar }
}

/// What is behind the wall in the side view. The ladder climbs it: a rec-park fence, one low
/// bleacher, bleachers, then the full thing (DESIGN.md §17).
public enum Stands: String, Equatable, CaseIterable, Codable {
    /// Single-A: a chain-link fence and trees, and no stands at all.
    case fenceAndTrees
    case lowBleacher
    case bleachers
    case full

    /// Whether a ball landing back here is swallowed by the crowd. Single-A is the one park
    /// where you watch the ball all the way down.
    public var swallowsTheBall: Bool { self != .fenceAndTrees }
    /// Whether there is a crowd to speckle.
    public var hasCrowd: Bool { self != .fenceAndTrees }
}

/// One cloud stamp: a few blocks sharing a baseline. Whole pixels, no shape knowledge beyond
/// "these rectangles" — the scene turns them into `chalk` rects with a `sky3` underside.
public struct Cloud: Equatable {
    /// Where the stamp's left edge starts, as a fraction of the view's width, before any drift.
    /// A fraction because the canvas is wider than 320 on a modern phone and Core does not know it.
    public let xFraction: Double
    /// The stamp's baseline — its bottom row — in design pixels from the top. The screen is
    /// always 224 tall, so this one is absolute.
    public let baselineY: Double
    public let blocks: [Block]

    public struct Block: Equatable {
        /// From the stamp's left edge.
        public let dx: Int
        /// How far this block's top sits above the baseline.
        public let rise: Int
        public let w: Int
        public init(dx: Int, rise: Int, w: Int) { self.dx = dx; self.rise = rise; self.w = w }
    }

    public init(xFraction: Double, baselineY: Double, blocks: [Block]) {
        self.xFraction = xFraction; self.baselineY = baselineY; self.blocks = blocks
    }

    /// The whole stamp's width in pixels, which is what the drift has to wrap around.
    public var width: Int { blocks.map { $0.dx + $0.w }.max() ?? 0 }
    /// Its tallest rise, for a scene that wants to know how much sky it eats.
    public var height: Int { blocks.map(\.rise).max() ?? 0 }
}

/// The moon: one night park in four gets one, in a seeded place, with a night-coloured bite
/// taken out of one side (DESIGN.md §17). Not drawn until step 4.
public struct Moon: Equatable {
    public let xFraction: Double
    public let y: Double
    public let radius: Double
    /// Which side the bite is on: −1 left, +1 right.
    public let biteDirection: Int
}

/// The knobs behind a park's scenery. Every number §17 names, and nothing inline.
public struct SceneryRules: Equatable {
    /// −3…+3 px/s. Cosmetic today; when §14 ships wind this same number pushes the ball, and
    /// the clouds and flags will already have been showing it.
    public var breeze: ClosedRange<Double> = -3...3
    /// Two to four clouds per view, each a stamp of three or four blocks: a wide flat base with
    /// narrower, taller steps heaped on it. Side by side they read as a shelf; stacked they read
    /// as a cloud.
    public var cloudsPerView: ClosedRange<Int> = 2...4
    public var cloudBlocks: ClosedRange<Int> = 3...4
    public var cloudBaseWidth: ClosedRange<Int> = 15...26
    public var cloudBaseRise: ClosedRange<Int> = 2...3
    /// How much taller and how much narrower each step above the base is, and how far it shifts.
    public var cloudStepRise: ClosedRange<Int> = 2...4
    public var cloudStepShrink: ClosedRange<Int> = 3...7
    /// The tallest a stamp may end up, so no cloud ever eats its band.
    public var cloudMaxRise = 13
    /// Where a cloud's baseline may sit in each view, in design pixels. Both bands are well
    /// clear of the strike zone, the wall band and the scoreboard (§17: nothing new moves near
    /// the zone).
    public var atBatCloudBand: ClosedRange<Double> = 30...62
    public var sideCloudBand: ClosedRange<Double> = 20...46

    /// How high the stands climb above the ground and how far back they run, in feet, by tier.
    /// The full tier is §17's "about 60 ft at 150 ft back"; the rest of the ladder is Claude's,
    /// unreviewed (2026-09-19).
    public var fenceTopFeet: Double = 15
    public var fenceDepthFeet: Double = 40
    public var lowBleacherTopFeet: Double = 18
    public var lowBleacherDepthFeet: Double = 50
    public var bleachersTopFeet: Double = 36
    public var bleachersDepthFeet: Double = 100
    public var fullStandsTopFeet: Double = 60
    public var fullStandsDepthFeet: Double = 150

    /// Flags along the top of the stands, by tier. The minors' lower two rungs fly none.
    public var bleachersFlags: Int = 2
    public var fullStandsFlags: Int = 3

    /// Every night park has two to four light towers (§17). The minors and The Show are day
    /// games, so the first lights a player ever sees belong to a seeded park.
    public var towersPerNightPark: ClosedRange<Int> = 2...4
    /// A moon in one night park in four.
    public var moonProbability: Double = 0.25
    public var moonRadius: ClosedRange<Double> = 5...8
    public var moonBand: ClosedRange<Double> = 14...40

    public init() {}
    public static let standard = SceneryRules()
}

/// Everything about how a park *looks* that is not the wall: a pure function of the park number,
/// seeded and `Equatable` exactly like the wall is, so park 87 looks the same on every phone and
/// a replay (#4) reproduces its sky (DESIGN.md §17).
///
/// It draws from its **own** RNG stream, deliberately: `Park.generate`'s stream decides the wall,
/// the height and the night flag, and adding scenery must not shift a single one of them.
/// `ParkTests.testParkFieldsAreUnchangedByScenery` is the guard on that.
public struct Scenery: Equatable {
    public let parkNumber: Int
    /// The silhouette along the horizon.
    public let far: Backdrop
    /// The one landmark standing in front of it.
    public let near: Backdrop
    public let stands: Stands
    /// How high the stands climb above the ground, and how far back they run, in feet. Where
    /// these two meet the flight is where a home run vanishes into the crowd.
    public let standsTopFeet: Double
    public let standsDepthFeet: Double
    /// Flags along the top of the stands, pointing with the breeze. Static until step 5.
    public let flags: Int
    /// px/s, positive to the right.
    public let breezePixelsPerSecond: Double
    /// The two views look in different directions, so each has its own sky. Wide and close
    /// share the side one: the sky never moves, whatever the camera does (§8).
    public let atBatClouds: [Cloud]
    public let sideClouds: [Cloud]
    /// Night only, and only one night park in four. Not drawn until step 4.
    public let moon: Moon?
    /// Night only: two to four light towers. Not drawn until step 4.
    public let towers: Int

    /// The fixed entries from §17's table. Each rung of the ladder looks like one more rung of
    /// a real climb, which is the point of having them.
    static func ladderEntry(for league: League) -> (far: Backdrop, near: Backdrop, stands: Stands) {
        switch league {
        case .singleA: return (.treeline, .house, .fenceAndTrees)
        case .doubleA: return (.treeline, .waterTower, .lowBleacher)
        case .tripleA: return (.bleachers, .lightPoles, .bleachers)
        case .theShow: return (.upperDeck, .pennants, .full)
        }
    }

    /// Park N's scenery, a pure function of N. The seed is its own constant, nothing to do with
    /// `Park.generate`'s.
    public static func generate(for park: Park, rules: SceneryRules = .standard) -> Scenery {
        let n = max(1, park.number)
        var g = SplitMix64(seed: UInt64(n) &* 0xA24B_AED4_963E_E407 &+ 0x1D2B_8F3A_51C6_7E09)

        let league = League(parkNumber: n)
        let far: Backdrop, near: Backdrop, stands: Stands
        if n <= League.theShow.rawValue {
            (far, near, stands) = ladderEntry(for: league)
        } else {
            far = Backdrop.farKit[Int.random(in: 0..<Backdrop.farKit.count, using: &g)]
            near = Backdrop.nearKit[Int.random(in: 0..<Backdrop.nearKit.count, using: &g)]
            stands = .full
        }

        let top: Double, depth: Double, flags: Int
        switch stands {
        case .fenceAndTrees: top = rules.fenceTopFeet; depth = rules.fenceDepthFeet; flags = 0
        case .lowBleacher: top = rules.lowBleacherTopFeet; depth = rules.lowBleacherDepthFeet; flags = 0
        case .bleachers: top = rules.bleachersTopFeet; depth = rules.bleachersDepthFeet; flags = rules.bleachersFlags
        case .full: top = rules.fullStandsTopFeet; depth = rules.fullStandsDepthFeet; flags = rules.fullStandsFlags
        }

        // Whole pixels per second, so a stepped drift lands on whole pixels too. Rounded, not
        // truncated: truncation would never reach ±3 and would make a dead calm twice as likely
        // as any other breeze.
        let breeze = Double.random(in: rules.breeze, using: &g).rounded()
        let atBat = clouds(band: rules.atBatCloudBand, rules: rules, using: &g)
        let side = clouds(band: rules.sideCloudBand, rules: rules, using: &g)

        // Night only, and drawn from the same stream whether or not it is used, so that a day
        // park and a night park with the same number never share a cloud.
        let moonRoll = Double.random(in: 0..<1, using: &g)
        let moonX = Double.random(in: 0.08...0.92, using: &g)
        let moonY = Double.random(in: rules.moonBand, using: &g).rounded()
        let moonR = Double.random(in: rules.moonRadius, using: &g).rounded()
        let bite = Bool.random(using: &g) ? 1 : -1
        let towers = Int.random(in: rules.towersPerNightPark, using: &g)

        return Scenery(
            parkNumber: n, far: far, near: near, stands: stands,
            standsTopFeet: top, standsDepthFeet: depth, flags: flags,
            breezePixelsPerSecond: breeze, atBatClouds: atBat, sideClouds: side,
            moon: park.isNight && moonRoll < rules.moonProbability
                ? Moon(xFraction: moonX, y: moonY, radius: moonR, biteDirection: bite) : nil,
            towers: park.isNight ? towers : 0)
    }

    /// Two to four stamps in one band, left to right across the view.
    private static func clouds(band: ClosedRange<Double>, rules: SceneryRules,
                               using g: inout SplitMix64) -> [Cloud] {
        let count = Int.random(in: rules.cloudsPerView, using: &g)
        var out: [Cloud] = []
        for i in 0..<count {
            // One per slice of the view, jittered inside it: seeded, but never all in a heap.
            let slice = 1.0 / Double(count)
            let x = (Double(i) + Double.random(in: 0.05...0.75, using: &g)) * slice
            let y = Double.random(in: band, using: &g).rounded()
            // A heap, not a row: the base spans the stamp and every step above it is narrower,
            // taller and shifted along. Each block runs from its own top down to the shared
            // baseline, so the stamp is one solid stepped mound.
            let blockCount = Int.random(in: rules.cloudBlocks, using: &g)
            var w = Int.random(in: rules.cloudBaseWidth, using: &g)
            var rise = Int.random(in: rules.cloudBaseRise, using: &g)
            var dx = 0
            var blocks = [Cloud.Block(dx: dx, rise: rise, w: w)]
            for _ in 1..<blockCount {
                let shrink = Int.random(in: rules.cloudStepShrink, using: &g)
                dx += Int.random(in: 1...max(1, shrink - 1), using: &g)
                w -= shrink
                let taller = rise + Int.random(in: rules.cloudStepRise, using: &g)
                guard w >= 3, taller <= rules.cloudMaxRise else { break }
                rise = taller
                blocks.append(Cloud.Block(dx: dx, rise: rise, w: w))
            }
            out.append(Cloud(xFraction: x, baselineY: y, blocks: blocks))
        }
        return out
    }
}

extension Park {
    /// What this park looks like behind the wall and in the sky. Computed, not stored: `Park`
    /// is compared, copied and generated all over the machine, and scenery has no business
    /// changing what any of that means. Callers that draw it every frame cache the value.
    public var scenery: Scenery { Scenery.generate(for: self) }
}
