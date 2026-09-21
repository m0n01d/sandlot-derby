import Foundation
import DerbyCore

/// The at-bat camera's own numbers — the App half of §20's "The look, piece by piece" and
/// "Stands at bat, by tier". Every one of them is a pixel or a fraction; the colours come off
/// `Look` by role. Copied from `prototypes/04-golden-hour/golden.py`'s `at_bat`, `wing`,
/// `leafy`, `near_piece` and `variants.hills` / `speckle`, which are the oracle.
struct AtBatLookRules {

    // MARK: The horizon (`variants.hills`, `golden.leafy`)

    /// Two layers of round hills beyond centre field: the far one rises higher and is drawn in
    /// bigger circles, the near one sits in front of it. `top` is how far above the baseline a
    /// crest may reach; the radius range is how wide each hill is.
    var farHillTop = 20.0
    var farHillRadius = 30...52
    var nearHillTop = 12.0
    var nearHillRadius = 18...30
    /// Round trees along the horizon: each one this far above the baseline, this big, and this
    /// far along from the last. They are placed left to right and then shuffled, so which one
    /// overlaps which is not simply "the one further right".
    var treeRise = 2...7
    var treeRadius = [4.0, 5.0, 5.0, 6.0, 7.0]
    var treeStep = 5...9
    /// Where a lit rim and a body tone start on a tree, as light falling on its fake normal.
    var treeRimCut = 0.75
    var treeBodyCut = 0.1
    /// The gap the scoreboard stands in, where a `full` park's trees show between its wings.
    var treeGap = 118.0...202.0

    // MARK: The wings (`golden.wing`, `golden.TIERS`)

    /// The top row of a wing beside the scoreboard, and how many two-pixel steps it climbs on
    /// the way out to the screen edge, by tier. `full` is the mock: 14 px high at the board and
    /// 34 at the edges. The other three are Claude's and have no mock (§20 "Open", 6).
    var fullTierTop = 82.0
    var fullTierSteps = 10
    var bleachersTierTop = 88.0
    var bleachersTierSteps = 7
    var lowBleacherTierTop = 92.0
    var lowBleacherTierSteps = 3
    /// Where a wing's inner edge is, and how far out the steps are spread. A column further from
    /// the board than `wingSpread` is at full height, which is what holds the edge height from
    /// the design column's edge out to the canvas edge (§20 "Canvases wider than 320").
    var wingInnerLeft = 124.0
    var wingInnerRight = 196.0
    var wingSpread = 124.0
    /// The bottom of the wings, which is the top of the wall band.
    var wingFootY = 96.0
    /// Rows under the roof that seat nobody: the upper deck's own depth in a `full` park, and
    /// just the lip anywhere else.
    var deckHead = 10.0
    var plainHead = 2.0
    /// The upper deck: its fascia starts this far below the roof and is this deep, its lights
    /// sit on this row of it, and its columns hang this far down.
    var deckFasciaTop = 2.0
    var deckFasciaDepth = 5.0
    var deckLampRow = 4.0
    var deckColumnTop = 7.0
    var deckColumnDepth = 3.0
    /// One lamp pair every this many columns, one column every this many, one aisle every this
    /// many — all counted in the design column, so they line up with the mock however wide the
    /// canvas is.
    var deckLampPitch = 6
    var deckLampPhase = 2
    var deckColumnPitch = 17
    var deckColumnPhase = 5
    var aislePitch = 23
    var aislePhase = 11
    /// The tiers' lips: a row of them this far up from the foot, this many of them.
    var tierPitch = 9.0
    var tierCount = 2
    /// The crowd: the back row sits here and they come forward this often, down to this row. A
    /// person is a head pixel over a shirt pixel and only every other column holds one, which is
    /// what leaves room between shoulders.
    var crowdBackRow = 94.0
    var crowdFrontRow = 64.0
    var crowdRowPitch = 3.0

    // MARK: The wall, the track and the grass

    /// The wall band: its top row is the `score` rail, the row under it is the lit cap, and the
    /// face dithers darker from there to its foot. A panel seam every `wallSeamPitch` columns.
    var wallTopY = 96.0
    var wallDepth = 8.0
    var wallSeamPitch = 20
    var wallSeamPhase = 10
    /// The warning track, and how far down it the wall's own shadow reaches.
    var trackTopY = 104.0
    var trackDepth = 4.0
    var trackShadowDepth = 3.0
    /// The grass starts here, and its mown bands get taller as they come to the camera.
    var grassTopY = 108.0
    var grassBandHeights = [3.0, 3.0, 4.0, 4.0, 5.0, 6.0, 7.0, 8.0, 10.0, 12.0, 14.0, 17.0, 20.0, 24.0]
    /// The columns of the checkerboard converge on a point above the middle of the design
    /// column: this wide at the bottom of the screen, narrowing with the rows, and flat (one
    /// column, straight bands) above `grassPerspectiveFromY` where the angle is too shallow to read.
    var grassColumnWidth = 58.0
    var grassPerspectiveFromY = 120.0
    var grassVanishY = 92.0

    // MARK: The low sun, the pool and the mist

    /// The stand's shadow on the outfield grass: its edge starts here on the top row and runs
    /// out this fast, is this soft, and the light raking the rest of the grass reaches this far
    /// and fades out by this row.
    var lowSunEdgeX = 132.0
    var lowSunEdgeSlope = 6.5
    var lowSunShadowLead = 12.0
    var lowSunShadowSoftness = 26.0
    var lowSunWashLead = 14.0
    var lowSunWashReach = 200.0
    var lowSunWashLastRow = 119.0
    var lowSunWashFade = 11.0
    var lowSunWashStrength = 0.9
    /// How dark the pool of light at `night` gets at the very edge of the canvas.
    var nightPoolStrength = 0.8

    // MARK: The dirt (`golden.at_bat`'s ellipses, `variants.speckle`)

    /// The mound: three stacked ellipses shifted toward the light, a lit crest on top of them
    /// and the rubber across it.
    var moundX = 160.0
    var mound: [(y: Double, rx: Double, ry: Double)] = [(120.5, 16, 5), (119.3, 15, 4.2), (118.8, 13, 3.2)]
    var moundCrest = (y: 118.0, rx: 5.0, ry: 1.4, shift: 7.0)
    var rubber = (x: 157.0, y: 117.0, w: 6.0)
    /// The plate circle: the same three ellipses, from x 66 to 254 and from y 180 to the bottom
    /// edge, below the bottom six rows of the strike zone (§20 "Layout that the look moves").
    var plateCircle: [(y: Double, rx: Double, ry: Double, shift: Double)] = [
        (205, 94, 25.5, 0), (205.4, 93, 24.6, 1), (206, 90, 23.5, 3)
    ]
    /// Specks of light and dark dirt over the plate circle: this many, inside this box.
    var speckCount = 90
    var speckBox = (x0: 70.0, y0: 184.0, x1: 252.0, y1: 223.0)
    var speckPairShare = 0.4
    /// A batter's box, in perspective: its four corners on the near side of the plate, mirrored.
    var batterBox: [(dx: Double, y: Double)] = [(22, 189), (68, 189), (82, 221), (26, 221)]
    /// The plate itself: six rows narrowing to a point, with a shaded pixel down its right edge.
    var plateTopY = 190.0
    var plateRows: [(x0: Double, x1: Double)] = [
        (152, 168), (152, 168), (153, 167), (155, 165), (157, 163), (159, 161)
    ]

    // MARK: The scoreboard frame (§20 "Layout that the look moves")

    /// The frame moved out from the face by three pixels on each side and by three rows above
    /// it. The face and the text did not move.
    var boardFrame = (x: 125.0, y: 77.0, w: 70.0, h: 19.0)
    var boardFace = (x: 128.0, y: 80.0, w: 64.0, h: 16.0)
    var boardLitEdgeWidth = 2.0

    static let standard = AtBatLookRules()
}

/// The at-bat camera's static art (DESIGN.md §20 step 3). Static functions over a `PixelCanvas`
/// like `BackdropArt`'s, so a scene can point them at a cached layer or at the frame itself.
///
/// Everything a park places at random — the hills, the trees, the crowd, the specks in the dirt —
/// is placed with `SplitMix64` off the park's number, not the prototype's Python stream: §20 is
/// explicit that for those pieces the rule is the oracle and the exact pixels are not.
enum AtBatArt {

    // MARK: - The horizon, into the `behind` layer

    /// Two layers of round hills, the park's own far piece where there is no stand to hide it,
    /// and a treeline: everything above the wall that does not move and is not a stand.
    static func horizon(into c: PixelCanvas, park: Park, scenery: Scenery, look: Look,
                        width: Double, xOffset: Double,
                        layout: BackdropLayout = .standard,
                        rules: AtBatLookRules = .standard) {
        let baseline = rules.wingFootY
        hills(into: c, colour: look.hill[0], top: rules.farHillTop, radius: rules.farHillRadius,
              baseline: baseline, width: width, seed: seed(scenery, tag: 0x10))
        hills(into: c, colour: look.hill[1], top: rules.nearHillTop, radius: rules.nearHillRadius,
              baseline: baseline, width: width, seed: seed(scenery, tag: 0x11))

        // Where a park has wings they *are* its far piece at bat, so §17's is not drawn there
        // (§20 "Stands at bat, by tier"). Where it has none, the far piece stands on the horizon
        // the way it does today, in the hill colours, and the trees grow in front of it.
        if scenery.stands == .fenceAndTrees {
            BackdropArt.far(scenery.far, into: c, x0: 0, x1: width,
                            baseline: layout.atBatHorizonBottom,
                            rise: layout.atBatHorizonBottom - layout.atBatHorizonTop,
                            body: look.hill[1], hole: look.hill[0], seed: seed(scenery, tag: 0x1))
        }

        // A `full` park's wings leave only the gap the scoreboard stands in; a lower stand lets
        // the far side of town show right over it.
        let gap = scenery.stands == .full
            ? (xOffset + rules.treeGap.lowerBound, xOffset + rules.treeGap.upperBound)
            : (0, width)
        trees(into: c, look: look, x0: gap.0, x1: gap.1, baseline: baseline,
              seed: seed(scenery, tag: 0x13), rules: rules)

        // With no wings the near piece stands on the horizon too, as it does today.
        if scenery.stands == .fenceAndTrees {
            nearPiece(into: c, piece: scenery.near, look: look,
                      x: xOffset + nearPieceX(scenery, layout: layout), baseline: baseline,
                      breeze: scenery.breezePixelsPerSecond)
        }
    }

    /// Round hills along a baseline: circles big enough that only their crowns show, each one
    /// drawn where the last one left off. Nothing is shaded — a hill this far away is a shape.
    static func hills(into c: PixelCanvas, colour: Palette.RGBA8, top: Double,
                      radius: ClosedRange<Int>, baseline: Double, width: Double, seed: UInt64) {
        var g = SplitMix64(seed: seed)
        var x = -20.0
        while x < width + 20 {
            let rad = Double(Int.random(in: radius, using: &g))
            let lift = Double(Int.random(in: Int(top * 0.55)...Int(top), using: &g))
            let cy = baseline + rad - lift
            for p in Mask.ellipse(cx: x, cy: cy, rx: rad, ry: rad) where Double(p.y) < baseline {
                c.px(Double(p.x), Double(p.y), colour)
            }
            x += (rad * Double.random(in: 0.9...1.5, using: &g)).rounded(.towardZero)
        }
    }

    /// Round trees along a baseline, with a lit rim on the side the light comes from. They are
    /// placed in order and then shuffled, so the overlaps read as a wood rather than as a row.
    static func trees(into c: PixelCanvas, look: Look, x0: Double, x1: Double, baseline: Double,
                      seed: UInt64, rules: AtBatLookRules = .standard) {
        guard x1 > x0 else { return }
        var g = SplitMix64(seed: seed)
        var items: [(x: Double, y: Double, r: Double)] = []
        var x = x0 - 3
        while x < x1 {
            let rise = Double(Int.random(in: rules.treeRise, using: &g))
            let r = rules.treeRadius[Int.random(in: 0..<rules.treeRadius.count, using: &g)]
            items.append((x, baseline - rise, r))
            x += Double(Int.random(in: rules.treeStep, using: &g))
        }
        // Fisher-Yates off the same stream, which is what `random.shuffle` does.
        if items.count > 1 {
            for i in stride(from: items.count - 1, to: 0, by: -1) {
                let j = Int.random(in: 0...i, using: &g)
                items.swapAt(i, j)
            }
        }
        let t = look.tree
        let lx = look.light.x, ly = look.light.y
        for item in items {
            for p in Mask.ellipse(cx: item.x, cy: item.y, rx: item.r, ry: item.r) {
                guard Double(p.y) < baseline, Double(p.x) >= x0, Double(p.x) < x1 else { continue }
                let l = p.nx * lx + p.ny * ly
                let tone = l > rules.treeRimCut ? t[2] : (l > rules.treeBodyCut ? t[1] : t[0])
                c.px(Double(p.x), Double(p.y), tone)
            }
        }
    }

    // MARK: - The stands, into the `front` layer

    /// The top row of a wing at this column of the design space. Beyond the spread — which is
    /// every column of a canvas wider than 320 — it is flat at the edge height, so a phone's
    /// extra pixels continue the stand rather than stepping it further (§20).
    static func wingTop(columnX: Double, tier: Stands, rules: AtBatLookRules = .standard) -> Double {
        guard let step = tierStep(tier, rules: rules) else { return rules.wingFootY }
        let d = columnX < 160
            ? (rules.wingInnerLeft - columnX) / rules.wingSpread
            : (columnX - rules.wingInnerRight) / rules.wingSpread
        let climbed = Int(min(1, max(0, d)) * Double(step.steps))
        return step.top - Double(climbed) * 2
    }

    private static func tierStep(_ tier: Stands, rules: AtBatLookRules) -> (top: Double, steps: Int)? {
        switch tier {
        case .fenceAndTrees: return nil
        case .lowBleacher: return (rules.lowBleacherTierTop, rules.lowBleacherTierSteps)
        case .bleachers: return (rules.bleachersTierTop, rules.bleachersTierSteps)
        case .full: return (rules.fullTierTop, rules.fullTierSteps)
        }
    }

    /// Both wings of the stand behind the wall, with their crowd, and §17's near piece standing
    /// on the roof line of whichever one its slot falls in. Nothing here moves: the crowd at bat
    /// does not bounce (§20 "Crowd"), so the whole lot lives in the cached `front` layer.
    static func stands(into c: PixelCanvas, park: Park, scenery: Scenery, look: Look,
                       width: Double, xOffset: Double,
                       layout: BackdropLayout = .standard,
                       rules: AtBatLookRules = .standard) {
        guard scenery.stands != .fenceAndTrees else { return }
        wing(into: c, look: look, side: -1, tier: scenery.stands, width: width, xOffset: xOffset,
             seed: seed(scenery, tag: 0x14), rules: rules)
        wing(into: c, look: look, side: +1, tier: scenery.stands, width: width, xOffset: xOffset,
             seed: seed(scenery, tag: 0x15), rules: rules)

        let slot = nearPieceX(scenery, layout: layout)
        nearPiece(into: c, piece: scenery.near, look: look, x: xOffset + slot,
                  baseline: wingTop(columnX: slot, tier: scenery.stands, rules: rules),
                  breeze: scenery.breezePixelsPerSecond, rules: rules)
    }

    /// One wing: a mass rising to the screen edge in two-pixel steps, a roof line, the lips of
    /// its tiers, and — in a `full` park only — the upper deck's fascia with its row of lights
    /// and its columns. Then the crowd, in rows with aisles, thinned to the hour's `crowdShare`.
    static func wing(into c: PixelCanvas, look: Look, side: Int, tier: Stands,
                     width: Double, xOffset: Double, seed: UInt64,
                     rules: AtBatLookRules = .standard) {
        let stand = look.stand(side: side)
        let mass = stand[0], lip = stand[1], under = stand[2]
        let heads = look.heads(side: side), shirts = look.shirts(side: side)
        let deckMass = look.deck[0], roof = look.deck[1], lamp = look.deck[2], column = look.deck[3]
        let full = tier == .full
        let head = full ? rules.deckHead : rules.plainHead
        let foot = rules.wingFootY

        // The wings run to the canvas edges; a column outside the 320 design column keeps the
        // edge's height and carries on the lamp and aisle rhythm from it.
        let x0 = side < 0 ? 0 : Int((xOffset + rules.wingInnerRight).rounded())
        let x1 = side < 0 ? Int((xOffset + rules.wingInnerLeft).rounded()) : Int(width)
        guard x1 > x0 else { return }

        func columnX(_ x: Int) -> Double { Double(x) - xOffset }
        func top(_ x: Int) -> Double { wingTop(columnX: columnX(x), tier: tier, rules: rules) }

        for x in x0..<x1 {
            let cx = Int(columnX(x).rounded())
            let t = top(x)
            c.rect(Double(x), t, 1, foot - t, mass)
            c.px(Double(x), t, full ? roof : lip)
            c.px(Double(x), t + 1, under)
            if full {
                c.rect(Double(x), t + rules.deckFasciaTop, 1, rules.deckFasciaDepth, deckMass)
                if posMod(cx - rules.deckLampPhase, rules.deckLampPitch) == 0 {
                    c.px(Double(x), t + rules.deckLampRow, lamp)
                    c.px(Double(x) + 1, t + rules.deckLampRow, lamp)
                }
                if posMod(cx - rules.deckColumnPhase, rules.deckColumnPitch) == 0 {
                    c.rect(Double(x), t + rules.deckColumnTop, 1, rules.deckColumnDepth, column)
                }
            }
            for k in 1...rules.tierCount {
                let yy = foot - rules.tierPitch * Double(k)
                if yy > t + head { c.px(Double(x), yy, lip) }
            }
        }

        // The crowd, back row first. Every other column and every third row, so a person is one
        // head over one shirt with air on all sides; the rows that carry a tier's lip are left
        // to the lip.
        var g = SplitMix64(seed: seed)
        var row = 0
        var y = rules.crowdBackRow
        while y > rules.crowdFrontRow {
            for x in x0..<x1 {
                let cx = Int(columnX(x).rounded())
                if posMod(cx + row, 2) != 0 { continue }
                if y - 1 <= top(x) + head { continue }
                if posMod(Int(foot - y), Int(rules.tierPitch)) == 0 { continue }
                if posMod(Int(foot - (y - 1)), Int(rules.tierPitch)) == 0 { continue }
                if posMod(cx - rules.aislePhase, rules.aislePitch) == 0 {
                    c.px(Double(x), y, under)
                    c.px(Double(x), y - 1, under)
                    continue
                }
                guard Double.random(in: 0..<1, using: &g) < look.crowdShare else { continue }
                let h = heads[Int.random(in: 0..<heads.count, using: &g)]
                let sh = shirts[Int.random(in: 0..<shirts.count, using: &g)]
                c.px(Double(x), y - 1, h)
                c.px(Double(x), y, sh)
            }
            y -= rules.crowdRowPitch
            row += 1
        }

        // The inner edge, where the wing meets the sky the scoreboard stands in.
        let edge = side < 0 ? Double(x1 - 1) : Double(x0)
        let edgeTop = wingTop(columnX: edge - xOffset, tier: tier, rules: rules)
        c.rect(edge, edgeTop, 1, foot - edgeTop, under)
    }

    /// §17's near piece where a stand carries it: the same landmark, built out of the stand's
    /// own colours with one lit edge down the side the light comes from (§20). It is drawn into
    /// a scratch sprite first so the lit edge finds the landmark's own outline and not the
    /// grandstand it is standing on.
    static func nearPiece(into c: PixelCanvas, piece: Backdrop, look: Look, x: Double,
                          baseline: Double, breeze: Double,
                          rules: AtBatLookRules = .standard) {
        let w = 80, h = 44, ox = 40, oy = 40
        let scratch = PixelCanvas(width: w, height: h)
        scratch.fill(Palette.clear)
        let stand = look.standLit
        BackdropArt.near(piece, into: scratch, x: Double(ox), baseline: Double(oy),
                         body: stand[0], detail: stand[2], breeze: breeze)

        // One lit edge: the outermost painted pixel of each row, on the side of the light.
        let fromLeft = look.light.x < 0
        for j in 0..<h {
            let row = scratch.buffer + j * w
            var found = -1
            for i in 0..<w where row[i] != 0 {
                found = i
                if fromLeft { break }
            }
            if found >= 0 { row[found] = stand[1].packed }
        }

        for j in 0..<h {
            let ty = Int(baseline) - oy + j
            guard ty >= 0, ty < c.height else { continue }
            let row = scratch.buffer + j * w
            for i in 0..<w where row[i] != 0 {
                let tx = Int(x) - ox + i
                guard tx >= 0, tx < c.width else { continue }
                c.buffer[ty * c.width + tx] = row[i]
            }
        }
    }

    /// Which side of the scoreboard this park's near piece stands on. The same seeded draw §17
    /// has always made — tag `0x2` off the park's number — so no park's landmark moved when the
    /// stand it now stands on appeared.
    static func nearPieceX(_ scenery: Scenery, layout: BackdropLayout = .standard) -> Double {
        var g = SplitMix64(seed: seed(scenery, tag: 0x2))
        return Bool.random(using: &g) ? layout.atBatNearRightX : layout.atBatNearLeftX
    }

    // MARK: - The field, into the `front` layer

    /// The wall, the warning track with the wall's shadow on it, and the outfield grass mown to
    /// a checkerboard in perspective. All three run to both canvas edges (§20).
    static func field(into c: PixelCanvas, look: Look, width: Double, xOffset: Double,
                      rules: AtBatLookRules = .standard) {
        let wall = look.wall
        let top = rules.wallTopY
        c.rect(0, top, width, rules.wallDepth, wall[1])
        c.rect(0, top + 1, width, 1, wall[0])
        c.bayerGradient(0, top + 2, width, rules.wallDepth - 2, wall[1], wall[2])
        var x = 0
        while Double(x) < width {
            if posMod(x - Int(xOffset) - rules.wallSeamPhase, rules.wallSeamPitch) == 0 {
                c.rect(Double(x), top + 1, 1, rules.wallDepth - 1, wall[2])
            }
            x += 1
        }
        // The rail along the top of it: `score`, where it used to be `chalk` (§20).
        c.rect(0, top, width, 1, Palette.score)

        let dirt = look.dirt
        c.rect(0, rules.trackTopY, width, rules.trackDepth, dirt[1])
        c.bayerGradient(0, rules.trackTopY, width, rules.trackShadowDepth, dirt[3], dirt[1])

        grass(into: c, width: width, xOffset: xOffset, rules: rules)
    }

    /// The checkerboard, in bands that get taller as they come to the camera and columns that
    /// converge on a point above the middle of the design column. Above `grassPerspectiveFromY`
    /// the columns are too shallow to read, so the bands are simply striped.
    static func grass(into c: PixelCanvas, width: Double, xOffset: Double,
                      rules: AtBatLookRules = .standard) {
        let height = Double(c.height)
        let vanishX = xOffset + rules.moundX
        var y = rules.grassTopY
        for (n, h) in rules.grassBandHeights.enumerated() {
            var yy = y
            while yy < min(height, y + h) {
                let columnWidth = rules.grassColumnWidth * (yy - rules.grassVanishY)
                    / (height - rules.grassVanishY)
                var x = 0.0
                while x < width {
                    let k = yy > rules.grassPerspectiveFromY
                        ? Int(((x + 0.5 - vanishX) / columnWidth + 0.5).rounded(.down))
                        : 0
                    c.px(x, yy, posMod(n + k, 2) != 0 ? Palette.grassA : Palette.grassB)
                    x += 1
                }
                yy += 1
            }
            y += h
        }
    }

    /// `dawn` and `goldenHour` only: one stand throws a dithered wedge of shadow across the
    /// outfield grass and the sun rakes what is left of it. Both are measured from the canvas
    /// edge on `look.dimSide`, and both stay well above the strike zone (§20).
    static func lowSun(into c: PixelCanvas, look: Look, width: Double,
                       lookRules: LookRules = .standard, rules: AtBatLookRules = .standard) {
        guard look.dimSide != 0, let sun = look.grassSun else { return }
        let rows = lookRules.lowSunRows
        var yy = rows.lowerBound
        while yy < rows.upperBound {
            let edge = rules.lowSunEdgeX - (yy - rows.lowerBound) * rules.lowSunEdgeSlope
            var x = 0.0
            while x < width {
                // Mirrored by which side the light is on: at `dawn` the sun is on the right, so
                // the wedge comes in from the right-hand edge of the canvas instead.
                let xm = look.dimSide < 0 ? x : width - 1 - x
                let threshold = PixelCanvas.threshold(Int(x), Int(yy))
                if xm < edge + rules.lowSunShadowLead,
                   (edge + rules.lowSunShadowLead - xm) / rules.lowSunShadowSoftness > threshold {
                    c.px(x, yy, Palette.shade)
                } else if xm > edge + rules.lowSunWashLead, yy < rules.lowSunWashLastRow {
                    let t = min(1, (xm - edge) / rules.lowSunWashReach)
                        * (1 - (yy - rows.lowerBound) / rules.lowSunWashFade)
                    if t * rules.lowSunWashStrength > threshold { c.px(x, yy, sun) }
                }
                x += 1
            }
            yy += 1
        }
    }

    /// `night` only: the lamps light the middle of the field and the corners fall away, by
    /// dither, measured in from each canvas edge (§20 "Canvases wider than 320").
    static func nightPool(into c: PixelCanvas, look: Look, width: Double,
                          lookRules: LookRules = .standard, rules: AtBatLookRules = .standard) {
        guard look.nightPool else { return }
        // At 320 across the clean middle is `nightPoolInsetPixels` either side of the centre,
        // which leaves exactly `nightPoolFalloffPixels` of dark at each edge. Measured from the
        // edges, that band is the knob itself and a wider canvas simply has more lit middle.
        let band = lookRules.nightPoolFalloffPixels
        var yy = rules.grassTopY
        while yy < Double(c.height) {
            var x = 0.0
            while x < width {
                let d = min(x, width - 1 - x)
                let t = max(0, band - d) / band
                if t * rules.nightPoolStrength > PixelCanvas.threshold(Int(x), Int(yy)) {
                    let word = c.buffer[Int(yy) * c.width + Int(x)]
                    if word == Palette.grassA.packed || word == Palette.grassB.packed {
                        c.px(x, yy, Palette.shade)
                    }
                }
                x += 1
            }
            yy += 1
        }
    }

    /// `dawn` only: a dithered band of ground mist lying on the outfield, thickest on its own
    /// row and thinning both ways. In front of the stands and behind the pitcher, and it stops
    /// a long way short of the strike zone (§20).
    static func mist(into c: PixelCanvas, look: Look, width: Double,
                     lookRules: LookRules = .standard) {
        guard let mist = look.mist else { return }
        let rows = lookRules.mistRows, peak = lookRules.mistPeak
        let above = peak - rows.lowerBound + 1, below = rows.upperBound - peak + 1
        var yy = rows.lowerBound
        while yy <= rows.upperBound {
            let d = 1 - abs(yy - peak) / (yy < peak ? above : below)
            var x = 0.0
            while x < width {
                // The matrix is walked sideways by the row, so the mist reads as drifting rather
                // than as a screen door hung over the outfield.
                if d * lookRules.mistStrength > PixelCanvas.threshold(Int(x) + Int(yy) / 3, Int(yy)) {
                    c.px(x, yy, mist)
                }
                x += 1
            }
            yy += 1
        }
    }

    /// The dirt and the chalk: the mound and the plate circle as lit ellipses with specks in
    /// them, the two foul lines, two batter's boxes in perspective and the five-sided plate.
    static func dirtAndChalk(into c: PixelCanvas, scenery: Scenery, look: Look, xOffset: Double,
                             foulLines: (apex: (x: Double, y: Double), left: Double,
                                         right: Double, wallY: Double),
                             rules: AtBatLookRules = .standard) {
        let d = look.dirt
        // Which way the light comes from, so each ellipse can be nudged toward it and show a rim.
        let sgn = look.light.x < 0 ? -1.0 : 1.0
        let mx = xOffset + rules.moundX

        // Deep shade, shade, body — each one smaller than the last and nudged a pixel toward the
        // light, which is what turns three flat discs into a mound with a lit side.
        for (i, m) in rules.mound.enumerated() {
            c.ellipse(mx + Double(i) * sgn, m.y, m.rx, m.ry, d[3 - i])
        }
        c.ellipse(mx + rules.moundCrest.shift * sgn, rules.moundCrest.y,
                  rules.moundCrest.rx, rules.moundCrest.ry, d[0])
        c.rect(xOffset + rules.rubber.x, rules.rubber.y, rules.rubber.w, 1, Palette.chalk)

        for (i, p) in rules.plateCircle.enumerated() {
            c.ellipse(mx + p.shift * sgn, p.y, p.rx, p.ry, d[3 - i])
        }
        speckle(into: c, seed: seed(scenery, tag: 0x16), xOffset: xOffset,
                tones: [d[0], d[2]], on: d[1], rules: rules)

        // The foul lines, doubled for the near half so they read as chalk laid on grass rather
        // than as a hairline. The endpoints are the scene's own and do not move.
        for ex in [foulLines.left, foulLines.right] {
            c.line(foulLines.apex.x, foulLines.apex.y, ex, foulLines.wallY, Palette.chalk)
            c.line(foulLines.apex.x + (ex > foulLines.apex.x ? 1 : -1), foulLines.apex.y,
                   (foulLines.apex.x + ex) / 2, 150, Palette.chalk)
        }

        for side in [-1.0, 1.0] {
            let pts = rules.batterBox.map { (x: mx + side * $0.dx, y: $0.y) }
            for i in 0..<pts.count {
                let a = pts[i], b = pts[(i + 1) % pts.count]
                c.line(a.x, a.y, b.x, b.y, Palette.chalk)
            }
        }
        for (j, row) in rules.plateRows.enumerated() {
            let y = rules.plateTopY + Double(j)
            c.rect(xOffset + row.x0, y, row.x1 - row.x0, 1, Palette.chalk)
            c.px(xOffset + row.x1 - 1, y, look.ballLo)
        }
    }

    /// Specks of light and dark dirt over the plate circle: an infield that is one flat colour
    /// reads as a carpet. Only where the body colour is already down, and only where the pixel
    /// beside it is too, so a speck never lands on the chalk.
    private static func speckle(into c: PixelCanvas, seed: UInt64, xOffset: Double,
                                tones: [Palette.RGBA8], on: Palette.RGBA8,
                                rules: AtBatLookRules) {
        var g = SplitMix64(seed: seed)
        let box = rules.speckBox
        for _ in 0..<rules.speckCount {
            let x = Int(xOffset) + Int.random(in: Int(box.x0)...Int(box.x1), using: &g)
            let y = Int.random(in: Int(box.y0)...Int(box.y1), using: &g)
            guard x >= 0, y >= 0, x + 1 < c.width, y < c.height else { continue }
            let i = y * c.width + x
            guard c.buffer[i] == on.packed, c.buffer[i + 1] == on.packed else { continue }
            let tone = tones[Int.random(in: 0..<tones.count, using: &g)]
            c.buffer[i] = tone.packed
            if Double.random(in: 0..<1, using: &g) < rules.speckPairShare {
                c.buffer[i + 1] = tone.packed
            }
        }
    }

    /// The scoreboard's frame and its dark face, with one lit edge down the side the light comes
    /// from. The face and everything written on it did not move (§20).
    static func scoreboardFrame(into c: PixelCanvas, look: Look, xOffset: Double,
                                rules: AtBatLookRules = .standard) {
        let f = rules.boardFrame, face = rules.boardFace
        c.rect(xOffset + f.x, f.y, f.w, f.h, look.board[0])
        let litX = look.light.x < 0 ? f.x : f.x + f.w - rules.boardLitEdgeWidth
        c.rect(xOffset + litX, f.y, rules.boardLitEdgeWidth, f.h, look.board[1])
        c.rect(xOffset + f.x, f.y, f.w, 1, look.board[1])
        c.rect(xOffset + face.x, face.y, face.w, face.h, look.board[2])
    }

    // MARK: - Odds and ends

    /// `%` that answers the way Python's does, so the lamp, column and aisle rhythms carry on
    /// unbroken into the columns of a canvas wider than the 320 the mock was drawn in.
    @inline(__always)
    static func posMod(_ a: Int, _ b: Int) -> Int {
        guard b > 0 else { return 0 }
        let m = a % b
        return m < 0 ? m + b : m
    }

    /// One seeded stream per park and purpose, the same shape `BackdropArt` uses. Nothing here
    /// is ever `random()`: park 87's hills are park 87's hills on every phone (§17).
    private static func seed(_ scenery: Scenery, tag: UInt64) -> UInt64 {
        UInt64(scenery.parkNumber) &* 0x7F4A_7C15_9E37_79B9 &+ tag &* 0x9E37_79B9_7F4A_7C15
    }
}
