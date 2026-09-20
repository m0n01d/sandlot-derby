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

/// The out-of-town board: a flat panel standing on the stands behind the wall, with one lit pane
/// in a top corner where the operator works (#5, "a scoreboard you can dent", "a window behind
/// the wall that breaks"). One park in `SceneryRules.boardInEveryPark` has one.
///
/// Everything here is in **feet**, measured the way the flight is, so hitting it needs no
/// knowledge of any camera: the ball either passes through the panel or it does not.
public struct OutfieldBoard: Equatable {
    /// How far behind the wall its middle stands.
    public let feetBehindWall: Double
    /// The feet above the ground of its bottom edge, and how big it is.
    public let bottomFeet: Double
    public let widthFeet: Double
    public let heightFeet: Double
    /// Which top corner carries the lit pane: −1 left, +1 right.
    public let paneSide: Int
    public let paneWidthFeet: Double
    public let paneHeightFeet: Double

    public init(feetBehindWall: Double, bottomFeet: Double, widthFeet: Double, heightFeet: Double,
                paneSide: Int, paneWidthFeet: Double, paneHeightFeet: Double) {
        self.feetBehindWall = feetBehindWall; self.bottomFeet = bottomFeet
        self.widthFeet = widthFeet; self.heightFeet = heightFeet
        self.paneSide = paneSide
        self.paneWidthFeet = paneWidthFeet; self.paneHeightFeet = paneHeightFeet
    }

    public var topFeet: Double { bottomFeet + heightFeet }
    /// Its two edges, in feet from the plate.
    public func nearFeet(wallDistanceFeet: Double) -> Double {
        wallDistanceFeet + feetBehindWall - widthFeet / 2
    }
    public func farFeet(wallDistanceFeet: Double) -> Double {
        wallDistanceFeet + feetBehindWall + widthFeet / 2
    }

    /// The lit pane's own box: inset a foot from the board's top and from the corner it is in.
    public func pane(wallDistanceFeet w: Double) -> (near: Double, far: Double, bottom: Double, top: Double) {
        let inset = 1.0
        let top = topFeet - inset
        let near = paneSide < 0 ? nearFeet(wallDistanceFeet: w) + inset
                                : farFeet(wallDistanceFeet: w) - inset - paneWidthFeet
        return (near, near + paneWidthFeet, top - paneHeightFeet, top)
    }

    /// Whether a point of the flight is inside the panel.
    public func contains(xFeet: Double, yFeet: Double, wallDistanceFeet w: Double) -> Bool {
        xFeet >= nearFeet(wallDistanceFeet: w) && xFeet <= farFeet(wallDistanceFeet: w)
            && yFeet >= bottomFeet && yFeet <= topFeet
    }

    /// And whether it is inside the lit pane, which is the smaller prize.
    public func paneContains(xFeet: Double, yFeet: Double, wallDistanceFeet w: Double) -> Bool {
        let p = pane(wallDistanceFeet: w)
        return xFeet >= p.near && xFeet <= p.far && yFeet >= p.bottom && yFeet <= p.top
    }
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

    /// How many steps the bleacher profile climbs in. A Core number, not a drawing one: it is
    /// what decides where a home run disappears into the crowd, so the pop is always exactly
    /// where the ball went in and a landmark standing on the stands knows what it is standing on.
    public var standsSteps: Int = 6
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
    /// How far behind the wall a tower stands and how high it carries its bank, in feet. The
    /// towers are shared out along the depth range rather than drawn independently, so two of
    /// them never stand in the same place.
    public var towerDepthFeet: ClosedRange<Double> = 25...165
    /// Tall on purpose: at the close camera's scale a tower this high runs out of the top of
    /// the frame, which is what makes the bank something you see in the wide one (§17).
    public var towerHeightFeet: ClosedRange<Double> = 150...190
    public var towerBankColumns: ClosedRange<Int> = 3...4
    public var towerBankRows: ClosedRange<Int> = 2...3

    /// A moon in one night park in four.
    public var moonProbability: Double = 0.25
    public var moonRadius: ClosedRange<Double> = 5...8
    public var moonBand: ClosedRange<Double> = 14...40

    /// Forty fixed stars, one in eight blinking on a slow seeded period (§17). The band is dark
    /// in both views: at night the at-bat sky is `night` to y 44 and `ink` to 70, and the side
    /// view's is `night` to 70 — so a `chalk` star reads anywhere inside it, and it sits well
    /// above the scoreboard and the horizon.
    public var starCount = 40
    public var blinkingStarInEvery = 8
    public var starBand: ClosedRange<Double> = 3...64
    public var starBlinkPeriod: ClosedRange<Double> = 3...7

    /// Where a flock of birds crosses, in design pixels. §17 says y < 60: well above the
    /// scoreboard and nowhere near the zone.
    public var birdBand: ClosedRange<Double> = 14...52

    // MARK: - Landmarks (#5)

    /// One park in this many carries an out-of-town board over the stands: a flat panel with a
    /// lit pane in one top corner. The ladder's four rungs never have one — a sandlot has no
    /// out-of-town board, and the first one a player sees belongs to a seeded park.
    public var boardInEveryPark = 3
    /// Where it stands and how big it is. The range is not decoration: past about 50 ft behind
    /// the wall the airspace above the stands closes, so a board further back than this could
    /// never be hit by anything (see DESIGN.md §17 "Rare things").
    public var boardDepthFeet: ClosedRange<Double> = 20...50
    /// How far its bottom edge clears the stands where it stands. High on purpose as well as
    /// honest: it has to read as standing *on* them, and a board any lower than this was dented
    /// by a quarter of every hard swing in a park that had one (measured, 2026-09-19).
    public var boardClearanceFeet: ClosedRange<Double> = 15...30
    public var boardWidthFeet: Double = 28
    public var boardHeightFeet: Double = 14
    /// The lit pane in its top corner: the operator's slot, and the smaller prize.
    public var boardPaneWidthFeet: Double = 6
    public var boardPaneHeightFeet: Double = 5

    /// One night park in this many carries a short light standard over the wall, on top of the
    /// seeded towers. It is the **one** bank a batted ball can ever reach: the towers proper
    /// stand 150–190 ft up, and nothing this game can hit gets within eighty feet of one
    /// (DESIGN.md §17 "Rare things"). Day parks have no lights at all, so no lights to put out.
    public var wallTowerInEveryNightPark = 2
    public var wallTowerDepthFeet: ClosedRange<Double> = 14...38
    public var wallTowerHeightFeet: ClosedRange<Double> = 74...98

    // MARK: - Things past park 100 / 500 / 1,000 (#5)

    /// Never announced, never explained: a long career simply arrives at a sky with more in it.
    /// Each is a pure function of the park number, so park 1,000 has all three for everyone.
    public var blimpFromPark = 100
    public var searchlightsFromPark = 500
    public var cometFromPark = 1_000
    /// Where a blimp crosses and where a comet hangs, in design pixels. Both sit in the same
    /// dark upper sky the birds and the stars do, well above the scoreboard and the zone.
    ///
    /// The comet is deliberately **not** at the very top of the sky, where it first was: a long
    /// near-horizontal streak on row 8 ran straight through `PARK 1000  1 PITCH` and read as two
    /// stray characters rather than as a comet. Down here it keeps the birds' company instead.
    public var blimpBand: ClosedRange<Double> = 18...44
    public var cometBand: ClosedRange<Double> = 20...32

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
    /// How many steps the profile climbs in, carried here so `standsHeightFeet(at:park:)` needs
    /// nothing but the scenery itself.
    public let standsSteps: Int
    /// Flags along the top of the stands, pointing with the breeze. Static until step 5.
    public let flags: Int
    /// px/s, positive to the right.
    public let breezePixelsPerSecond: Double
    /// The two views look in different directions, so each has its own sky. Wide and close
    /// share the side one: the sky never moves, whatever the camera does (§8).
    public let atBatClouds: [Cloud]
    public let sideClouds: [Cloud]
    /// Night only, and only one night park in four.
    public let moon: Moon?
    /// Night only: where this park's two to four light towers stand and how tall they are.
    /// Empty by day, so `towers` reads 0 there.
    public let lightTowers: [Tower]
    /// Night only: forty fixed stars, one in eight of them blinking. Empty by day.
    public let stars: [Star]

    /// The out-of-town board over the stands, in one seeded park in three (#5). Nil everywhere
    /// else, and never on the ladder's four rungs.
    public let board: OutfieldBoard?
    /// Night only, and only some night parks: the short light standard over the wall. The
    /// seeded towers are far too tall to hit, so this is the bank a no-doubter can put out
    /// (DESIGN.md §17 "Rare things"). It is drawn and chases exactly like the others.
    public let wallTower: Tower?
    /// Things a long career arrives at, never announced (#5). Pure functions of the park number.
    public let hasBlimp: Bool
    public let hasSearchlights: Bool
    public let hasComet: Bool

    /// How many light towers this park has. The count and the towers themselves were two fields
    /// for one fact, which is one too many: this is the count of what was actually seeded.
    public var towers: Int { lightTowers.count }

    /// Every bank in this park, in the order the chase runs along them: the seeded towers first,
    /// then the short one over the wall. Appending keeps every existing tower's index — and so
    /// its place in the chase — exactly where it was.
    public var allTowers: [Tower] { lightTowers + (wallTower.map { [$0] } ?? []) }
    /// The index of the wall tower among `allTowers`, nil when there is none. The one bank a
    /// batted ball can reach, so the one the lights-out shot is judged against.
    public var wallTowerIndex: Int? { wallTower == nil ? nil : lightTowers.count }

    /// How high the stands stand, in feet, at `feet` from the plate: the stepped bleacher
    /// profile, flat at its top once past the back row. Zero where nothing is built, which is
    /// Single-A — the one park where you watch the ball all the way down.
    ///
    /// This is the same number the drawing uses and the same one that decides where a home run
    /// disappears, so the pop is always exactly where the ball went in — and it is what a
    /// landmark standing on the stands is stood on.
    public func standsHeightFeet(at feet: Double, park: Park) -> Double {
        guard stands.swallowsTheBall else { return 0 }
        let back = feet - park.wallDistanceFeet
        guard back >= 0 else { return 0 }
        guard back < standsDepthFeet else { return standsTopFeet }
        let steps = Double(max(1, standsSteps))
        let i = (back / standsDepthFeet * steps).rounded(.down)
        return park.wallHeightFeet + (standsTopFeet - park.wallHeightFeet) * (i + 1) / steps
    }

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
        let towerCount = Int.random(in: rules.towersPerNightPark, using: &g)

        // Step 4's draws come last on purpose. Everything above keeps the number it had before
        // the night kit existed, so no park's clouds, breeze or moon moved when it arrived.
        let lightTowers = towers(count: towerCount, rules: rules, using: &g)
        let stars = starfield(rules: rules, using: &g)

        // …and #5's landmarks come after *those*, for exactly the same reason: no park's
        // clouds, breeze, moon, towers or stars moved when the board and the wall tower
        // arrived. Every draw happens whether or not it is used, so a day park and a night
        // park with the same number still never share one (`SceneryTests` guards both rules).
        let boardRoll = Int.random(in: 0..<max(1, rules.boardInEveryPark), using: &g)
        let boardDepth = Double.random(in: rules.boardDepthFeet, using: &g).rounded()
        let boardClearance = Double.random(in: rules.boardClearanceFeet, using: &g).rounded()
        let paneSide = Bool.random(using: &g) ? 1 : -1
        let wallTowerRoll = Int.random(in: 0..<max(1, rules.wallTowerInEveryNightPark), using: &g)
        let wallTowerDepth = Double.random(in: rules.wallTowerDepthFeet, using: &g).rounded()
        let wallTowerHeight = Double.random(in: rules.wallTowerHeightFeet, using: &g).rounded()
        let wallTowerColumns = Int.random(in: rules.towerBankColumns, using: &g)
        let wallTowerRows = Int.random(in: rules.towerBankRows, using: &g)

        // The board stands on the stands, so where its foot goes is read off the profile rather
        // than guessed: `standsHeightFeet` needs the scenery, which is what is being built, so
        // the bare profile is worked out here from the same three numbers it uses.
        let standsAtBoard = stands.swallowsTheBall
            ? standsProfile(back: boardDepth, wallHeightFeet: park.wallHeightFeet,
                            topFeet: top, depthFeet: depth, steps: rules.standsSteps)
            : park.wallHeightFeet
        // The ladder's four rungs keep the backdrops §17's table gives them and nothing else.
        let hasBoard = n > League.theShow.rawValue && boardRoll == 0

        return Scenery(
            parkNumber: n, far: far, near: near, stands: stands,
            standsTopFeet: top, standsDepthFeet: depth, standsSteps: rules.standsSteps,
            flags: flags,
            breezePixelsPerSecond: breeze, atBatClouds: atBat, sideClouds: side,
            moon: park.isNight && moonRoll < rules.moonProbability
                ? Moon(xFraction: moonX, y: moonY, radius: moonR, biteDirection: bite) : nil,
            lightTowers: park.isNight ? lightTowers : [],
            stars: park.isNight ? stars : [],
            board: hasBoard
                ? OutfieldBoard(feetBehindWall: boardDepth,
                                bottomFeet: (standsAtBoard + boardClearance).rounded(),
                                widthFeet: rules.boardWidthFeet,
                                heightFeet: rules.boardHeightFeet,
                                paneSide: paneSide,
                                paneWidthFeet: rules.boardPaneWidthFeet,
                                paneHeightFeet: rules.boardPaneHeightFeet)
                : nil,
            wallTower: park.isNight && wallTowerRoll == 0
                ? Tower(feetBehindWall: wallTowerDepth, heightFeet: wallTowerHeight,
                        bankColumns: wallTowerColumns, bankRows: wallTowerRows)
                : nil,
            hasBlimp: n >= rules.blimpFromPark,
            hasSearchlights: n >= rules.searchlightsFromPark,
            hasComet: n >= rules.cometFromPark)
    }

    /// The stepped profile, before there is a `Scenery` to ask. `standsHeightFeet(at:park:)` is
    /// the same sum with the scenery's own numbers filled in.
    private static func standsProfile(back: Double, wallHeightFeet: Double,
                                      topFeet: Double, depthFeet: Double, steps: Int) -> Double {
        guard back >= 0 else { return 0 }
        guard back < depthFeet else { return topFeet }
        let s = Double(max(1, steps))
        return wallHeightFeet + (topFeet - wallHeightFeet) * ((back / depthFeet * s).rounded(.down) + 1) / s
    }

    /// Two to four towers, shared out along the depth range one to a slice and jittered inside
    /// it — seeded, but never two of them standing in the same place.
    private static func towers(count: Int, rules: SceneryRules,
                               using g: inout SplitMix64) -> [Tower] {
        let lo = rules.towerDepthFeet.lowerBound
        let slice = (rules.towerDepthFeet.upperBound - lo) / Double(max(1, count))
        return (0..<count).map { i in
            Tower(feetBehindWall: (lo + (Double(i) + Double.random(in: 0.15...0.85, using: &g)) * slice).rounded(),
                  heightFeet: Double.random(in: rules.towerHeightFeet, using: &g).rounded(),
                  bankColumns: Int.random(in: rules.towerBankColumns, using: &g),
                  bankRows: Int.random(in: rules.towerBankRows, using: &g))
        }
    }

    /// Forty stars across the band, of which every eighth blinks. The period and the phase are
    /// drawn for all forty whether or not they are used, so which stars blink can never shift
    /// where the rest of them sit.
    private static func starfield(rules: SceneryRules, using g: inout SplitMix64) -> [Star] {
        (0..<rules.starCount).map { i in
            let x = Double.random(in: 0.01...0.99, using: &g)
            let y = Double.random(in: rules.starBand, using: &g).rounded()
            let period = Double.random(in: rules.starBlinkPeriod, using: &g).rounded()
            let phase = Double.random(in: 0..<period, using: &g)
            return Star(xFraction: x, y: y,
                        blinkPeriod: i.isMultiple(of: rules.blinkingStarInEvery) ? period : nil,
                        blinkPhase: phase)
        }
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
