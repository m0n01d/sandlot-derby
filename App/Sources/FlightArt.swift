import Foundation
import DerbyCore

/// The flight camera's own numbers — the App half of §20's knob table for the side view, in the
/// same spirit as `LookRules` and `BackdropLayout`: every one of them is a pixel, a foot or a
/// fraction, never a colour. The colours all come off `Look` by role.
///
/// They are the prototype's, near enough one for one: `prototypes/04-golden-hour/side.py`'s
/// `checker_mow`, `field_marks`, `lens`, `crowd_rows`, `tiers`, `foul_pole`, `board`,
/// `upper_deck`, `pennant_string` and `trail`, and the last `flight` in `golden.py` that wraps
/// them. Where §20 and the prototype disagree on a shape, the prototype wins.
struct FlightLookRules {

    // MARK: The grass (§20 "Grass in the flight camera", `side.checker_mow`)

    /// A mow stripe is this many feet wide — world space, so it widens with the scale — and never
    /// narrower than this on screen, or the far grass turns to noise.
    var stripeFeet = 16.0
    var minStripePixels = 4.0
    /// Three depth bands below the ground line, each starting on the other colour. Together they
    /// are the 48 rows from the wide camera's ground to the bottom edge.
    var grassBandRows = [9.0, 16.0, 23.0]

    /// The low sun's wash on the near grass: this many rows below the ground line, reaching this
    /// far across the canvas from the sun's own edge, at this density where it is strongest.
    var washRows = 9.0
    var washReach = 0.8
    var washStrength = 1.0

    // MARK: The field's marks (§20 "Field marks in the flight camera", `side.field_marks`)

    /// How deep a patch of dirt is, seen almost edge-on: a couple of rows wide, more in the close
    /// framing where everything is twice the size.
    var markDepthWide = 3.0
    var markDepthClose = 5.0
    /// The three patches, in feet from the plate: the circle round the plate, the mound, and the
    /// infield skin out through second base.
    var plateCircleFeet = -14.0...16.0
    var moundFeet = 51.0...69.0
    var infieldFeet = 108.0...156.0
    var secondBaseFeet = 127.0
    /// The warning track: this many feet of dirt in front of the wall.
    var warningTrackFeet = 16.0
    /// A chalk tick and a number every hundred feet, stopping this far short of the wall.
    var markPitchFeet = 100.0
    var markKeepOutFeet = 20.0
    var markTickRows = 8.0
    var markNumberDrop = 11.0
    /// Where a lens turns from body to lip (its near edge, rolling toward the camera) and where
    /// the light catches it (its far edge, on the side the light comes from).
    var lensLipBelow = 0.62
    var lensLightAbove = 0.3
    var lensLightSide = 0.2

    // MARK: The horizon (§20 "Horizon", `variants.hills`, `golden.leafy`)

    /// Two layers of round hills: how far the crest of each may rise above the ground line, and
    /// how big the discs that make it are. The far layer is bigger and lower-contrast; the near
    /// one is smaller and sits in front of it.
    var farHillRise = 30.0
    var farHillRadius = 34.0...60.0
    var nearHillRise = 17.0
    var nearHillRadius = 20.0...34.0
    /// How far apart the hill discs march, as a multiple of the disc just drawn.
    var hillStride = 0.9...1.5
    /// A hill's crest sits somewhere in this share of its rise, so a ridge is not a picket fence.
    var hillCrestShare = 0.55

    /// The trees along the ground line: the radii a crown is drawn from, how far above the line
    /// its middle sits, and how far apart they stand.
    var treeRadii = [4.0, 5, 5, 6, 7]
    var treeRise = 2...7
    var treeStride = 5...9
    /// Above this much light a crown takes its lit rim; above this its body; below, its shade.
    var treeRimAbove = 0.75
    var treeBodyAbove = 0.1

    // MARK: The far and near pieces (`side.upper_deck`, `side.pennant_string`)

    /// How far the far piece rises above the top of the stands, in each framing. The close camera
    /// is twice the scale, so its roof is twice as deep.
    var farRiseWide = 13.0
    var farRiseClose = 24.0
    /// The upper deck: how much of its rise is the deck itself (the rest is the columns under
    /// it), how far in from the wall it starts, and the lamp/window grid across its fascia.
    var deckShare = 0.58
    var deckInsetFeet = 18.0
    var deckWindowRows = 3.0
    var deckWindowPitchWide = 4.0
    var deckWindowPitchClose = 5.0
    var deckColumnPitchWide = 17.0
    var deckColumnPitchClose = 26.0

    /// The pennant string: where it hangs across the far piece, how far above the roof, how wide,
    /// how far each cloth is from the next, and how far the two posts stand out beyond it.
    var pennantAcross = 0.62
    var pennantAboveWide = 9.0
    var pennantAboveClose = 14.0
    var pennantHalfSpan = 30.0
    var pennantPitch = 7.0
    var pennantSag = 3.0
    /// The box §17's other near pieces stand in, so the lit rim knows where to look for them.
    var nearPieceHalfWidth = 28.0
    var nearPieceHeight = 26.0

    // MARK: The stands (§20 "Stands in the flight camera", `side.tiers`, `side.crowd_rows`)

    /// The crowd's seat pitch, across and up, in each framing. A person at bat-level scale is a
    /// head pixel over a shirt pixel; in the close framing he is 2×4.
    var crowdPitchWide = (x: 2.0, y: 3.0)
    var crowdPitchClose = (x: 3.0, y: 5.0)
    /// An aisle every this many feet of depth, this wide.
    var aisleEveryFeet = 30.0
    var aisleWidthWide = 3.2
    var aisleWidthClose = 2.4

    /// The upper deck's roof throws a dithered shadow down this many of the top rows, at this
    /// density, starting this far behind the wall.
    var roofShadowRowsWide = 7.0
    var roofShadowRowsClose = 12.0
    var roofShadowStrength = 0.8
    var roofShadowFromFeet = 40.0

    // MARK: The furniture

    /// The foul pole: how far above the wall it stands, how wide its two columns are, how wide
    /// its mesh wing is, and how far down the pole the wing reaches.
    var foulPoleFeet = 30.0
    var foulPoleWidthFeet = 2.0
    var foulPoleWingFeet = 5.0
    var foulPoleWingShare = 0.35

    /// The out-of-town board: how far in from its edges the legs stand, how wide they are, and
    /// the pitch of the rows of dashes in each framing.
    var boardLegInsetFeet = 6.0
    var boardLegWidth = 2.0
    var boardRowPitchWide = 3.0
    var boardRowPitchClose = 4.0
    var boardBraceDrop = 0.4

    // MARK: The ball, its trail and the batter

    /// The trail is sampled every this many points of the flight, closer together in the close
    /// framing where the ball covers more screen per point. The newest `trailBigDots` are 2×2
    /// and after `trailThinAfter` only every other one is drawn.
    var trailStepWide = 8
    var trailStepClose = 4
    var trailBigDots = 6
    var trailThinAfter = 30
    /// The ball sits this far above its own flight point, so the dot reads as its middle.
    var ballLift = 3.0
    var trailLift = 2.0
    /// The ground shadow under the ball: its size in each framing, how far below the ground line
    /// it sits, and how far its near end leads the ball, away from the light.
    var ballShadowWide = (w: 5.0, h: 1.0, drop: 2.0, lead: 1.0)
    var ballShadowClose = (w: 8.0, h: 2.0, drop: 1.0, lead: 0.0)

    /// The batter's long shadow when the sun is low: this many pixels away from it, solid for the
    /// first `batterShadowSolid` and every other pixel after that, dropping a row every
    /// `batterShadowDropEvery`.
    var batterShadowPixels = 21
    var batterShadowSolid = 12
    var batterShadowDropEvery = 8.0

    static let standard = FlightLookRules()
}

/// The flight camera's art: the horizon, the field, the stands, the crowd, the furniture and the
/// ball, ported from `prototypes/04-golden-hour/side.py` (DESIGN.md §20 step 4). Static functions
/// over a `PixelCanvas`, like `BackdropArt`, so the same code paints a cached layer or the frame
/// itself.
///
/// Everything here is measured in world feet through `SideView`, which is what makes the two
/// framings one drawing: the close camera is the same park at twice the scale.
enum FlightArt {

    /// Which of the crowd's three cached layers this is: nobody up, the even people up, the odd
    /// people up. §17's bounce lifts half the crowd on each step so the stand ripples rather than
    /// sliding, and §20 asks for the three to be drawn once and one of them picked per frame.
    enum CrowdLift: Hashable { case none, even, odd

        /// Whether person `i` is lifted in this layer.
        func lifts(_ i: Int) -> Bool {
            switch self {
            case .none: return false
            case .even: return i.isMultiple(of: 2)
            case .odd: return !i.isMultiple(of: 2)
            }
        }
    }

    // MARK: - The cached layers

    /// `behind`: the horizon and the park's two backdrop pieces. It moves with the ground, so the
    /// close camera carries the hills and the trees down with it (§20 "Layers and speed").
    static func behind(into c: PixelCanvas, park: Park, scenery: Scenery, view: SideView,
                       width: Double, close: Bool, look: Look,
                       towers: [SkyArt.TowerFrame] = [],
                       layout: BackdropLayout = .standard,
                       rules: FlightLookRules = .standard) {
        horizon(into: c, park: park, scenery: scenery, view: view, width: width,
                look: look, rules: rules)
        // The lattices stand between the treeline and the roof, which is where a real tower
        // stands: behind the grandstand and in front of the hills (`golden.flight`'s order).
        SkyArt.towerLattices(into: c, frames: towers, width: width, look: look, layout: layout)
        farPiece(into: c, park: park, scenery: scenery, view: view, width: width,
                 close: close, look: look, rules: rules)
        nearPiece(into: c, park: park, scenery: scenery, view: view, width: width,
                  close: close, look: look, rules: rules)
    }

    /// `front`: everything that goes in on top of the ball — the wall, the stepped stands, the
    /// foul pole and the out-of-town board. Which is what makes a home run drop into the crowd
    /// and be gone.
    static func front(into c: PixelCanvas, park: Park, scenery: Scenery, view: SideView,
                      width: Double, close: Bool, look: Look,
                      layout: BackdropLayout = .standard,
                      rules: FlightLookRules = .standard) {
        wall(into: c, park: park, view: view, width: width, look: look, rules: rules)
        if scenery.stands.swallowsTheBall {
            tiers(into: c, park: park, scenery: scenery, view: view, width: width, look: look)
        } else {
            chainLink(into: c, park: park, scenery: scenery, view: view, width: width, look: look,
                      layout: layout)
        }
        foulPole(into: c, park: park, view: view, look: look, rules: rules)
        board(into: c, park: park, scenery: scenery, view: view, width: width, close: close,
              look: look, rules: rules)
    }

    // MARK: - The horizon (§20 "Horizon")

    /// Two layers of round hills along the whole ground line, then round trees with a lit rim on
    /// the side of the light. The flight camera gets this horizon everywhere it can see the
    /// ground — in front of the wall, which is as far as the ground goes.
    ///
    /// The prototype places all three with Python's `random`; here they come off the park's own
    /// `SplitMix64` stream, so park 87's ridge is park 87's ridge on every phone. The rule is the
    /// oracle for these, not the prototype's exact pixels (§20).
    static func horizon(into c: PixelCanvas, park: Park, scenery: Scenery, view: SideView,
                        width: Double, look: Look, rules: FlightLookRules = .standard) {
        let baseline = view.ground
        hills(into: c, colour: look.hill[0], rise: rules.farHillRise, radius: rules.farHillRadius,
              baseline: baseline, width: width, seed: seed(scenery, tag: 0x11), rules: rules)
        hills(into: c, colour: look.hill[1], rise: rules.nearHillRise, radius: rules.nearHillRadius,
              baseline: baseline, width: width, seed: seed(scenery, tag: 0x12), rules: rules)
        trees(into: c, look: look, x0: 0, x1: min(width, view.x(park.wallDistanceFeet)),
              baseline: baseline, seed: seed(scenery, tag: 0x13), rules: rules)
    }

    /// One ridge: overlapping discs whose crests wander inside `rise` of the ground line. Only
    /// the half above the line is painted, so what is left is a row of round hills
    /// (`variants.hills`).
    private static func hills(into c: PixelCanvas, colour: Palette.RGBA8, rise: Double,
                              radius: ClosedRange<Double>, baseline: Double, width: Double,
                              seed: UInt64, rules: FlightLookRules) {
        var g = SplitMix64(seed: seed)
        var x = -20.0
        while x < width + 20 {
            let r = Double.random(in: radius, using: &g).rounded()
            let crest = Double.random(in: (rise * rules.hillCrestShare)...rise, using: &g).rounded()
            let cy = baseline + r - crest
            for p in Mask.ellipse(cx: x, cy: cy, rx: r, ry: r) where Double(p.y) < baseline {
                c.px(Double(p.x), Double(p.y), colour)
            }
            x += (r * Double.random(in: rules.hillStride, using: &g)).rounded(.down)
        }
    }

    /// The treeline: round crowns, shuffled so the ones in front are not always the ones drawn
    /// last, each shaded from the phase's own light — shade, body, and the lit rim §20 asks for
    /// on the side the light comes from (`golden.leafy`).
    private static func trees(into c: PixelCanvas, look: Look, x0: Double, x1: Double,
                              baseline: Double, seed: UInt64, rules: FlightLookRules) {
        guard x1 > x0 else { return }
        var g = SplitMix64(seed: seed)
        var items: [(x: Double, y: Double, r: Double)] = []
        var x = x0 - 3
        while x < x1 {
            let rise = Double(Int.random(in: rules.treeRise, using: &g))
            let r = rules.treeRadii[Int.random(in: 0..<rules.treeRadii.count, using: &g)]
            items.append((x, baseline - rise, r))
            x += Double(Int.random(in: rules.treeStride, using: &g))
        }
        // A Fisher–Yates shuffle off the same stream: the prototype's `random.shuffle`, which is
        // what stops the crowns overlapping in one direction like roof tiles.
        var i = items.count - 1
        while i > 0 {
            let j = Int.random(in: 0...i, using: &g)
            items.swapAt(i, j)
            i -= 1
        }

        let t = look.tree
        for item in items {
            for p in Mask.ellipse(cx: item.x, cy: item.y, rx: item.r, ry: item.r) {
                guard Double(p.y) < baseline, Double(p.x) >= x0, Double(p.x) < x1 else { continue }
                let l = p.nx * look.light.x + p.ny * look.light.y
                let tone = l > rules.treeRimAbove ? t[2] : (l > rules.treeBodyAbove ? t[1] : t[0])
                c.px(Double(p.x), Double(p.y), tone)
            }
        }
    }

    // MARK: - The far and the near piece

    /// The park's skyline over the grandstand. The Show's own piece is the upper deck, which §20
    /// draws properly now — a roof line, a row of lamps or windows, and columns under it. Every
    /// other far piece (treeline, mountains, skyline, bleachers) keeps the shape §17 gave it, in
    /// the phase's hill and stand colours.
    static func farPiece(into c: PixelCanvas, park: Park, scenery: Scenery, view: SideView,
                         width: Double, close: Bool, look: Look,
                         rules: FlightLookRules = .standard) {
        let wallX = view.x(park.wallDistanceFeet)
        let base = standsTopY(park: park, scenery: scenery, view: view) + 1
        guard width > wallX else { return }
        if scenery.far == .upperDeck {
            upperDeck(into: c, view: view, wallX: wallX, base: base, width: width,
                      close: close, look: look, rules: rules)
        } else {
            BackdropArt.far(scenery.far, into: c, x0: wallX, x1: width, baseline: base,
                            rise: farRise(close: close, rules: rules),
                            body: look.hill[1], hole: look.hill[0],
                            seed: seed(scenery, tag: 0x3))
        }
    }

    /// One landmark over the grandstand, the way a water tower or a wheel sits over a real one.
    /// The Show's is a string of pennants whose two posts stop at the roof; the rest are §17's
    /// shapes in the stand colours, with the one lit edge §20 asks for on the side of the light.
    static func nearPiece(into c: PixelCanvas, park: Park, scenery: Scenery, view: SideView,
                          width: Double, close: Bool, look: Look,
                          rules: FlightLookRules = .standard) {
        let wallX = view.x(park.wallDistanceFeet)
        let base = standsTopY(park: park, scenery: scenery, view: view) + 1
        guard width - wallX > 60 else { return }
        let rise = farRise(close: close, rules: rules)
        if scenery.near == .pennants {
            pennantString(into: c, wallX: wallX, base: base, width: width, rise: rise,
                          close: close, look: look, rules: rules)
        } else {
            let x = wallX + (width - wallX) * rules.pennantAcross
            let roof = base - rise
            // Drawn on its own first, so the rim finds the landmark's edge and not the ridge
            // behind it. A scratch canvas once per flight is cheaper than a shape-by-shape rim.
            let scratch = PixelCanvas(width: c.width, height: c.height)
            scratch.fill(Palette.clear)
            BackdropArt.near(scenery.near, into: scratch, x: x, baseline: roof,
                             body: look.standLit[0], detail: look.standLit[2],
                             breeze: scenery.breezePixelsPerSecond)
            litEdge(into: scratch, x0: x - rules.nearPieceHalfWidth, x1: x + rules.nearPieceHalfWidth,
                    y0: roof - rules.nearPieceHeight, y1: roof,
                    colour: look.standLit[1], fromLeft: look.light.x <= 0)
            copyKeyed(from: scratch, onto: c)
        }
    }

    /// Copies every painted pixel of `source` onto `target`, transparent ones skipped — the same
    /// colour key `BackdropLayer.blit` uses, for a scratch canvas that never becomes a layer.
    private static func copyKeyed(from source: PixelCanvas, onto target: PixelCanvas) {
        guard source.width == target.width else { return }
        for y in 0..<min(source.height, target.height) {
            let src = source.buffer + y * source.width
            let dst = target.buffer + y * target.width
            for x in 0..<source.width where src[x] != 0 { dst[x] = src[x] }
        }
    }

    /// How far the far piece rises above the stands in this framing.
    private static func farRise(close: Bool, rules: FlightLookRules) -> Double {
        close ? rules.farRiseClose : rules.farRiseWide
    }

    /// The upper deck: a roof line, a fascia with a row of lamps or windows behind it, and the
    /// columns that carry it (`side.upper_deck`).
    private static func upperDeck(into c: PixelCanvas, view: SideView, wallX: Double,
                                  base: Double, width: Double, close: Bool, look: Look,
                                  rules: FlightLookRules) {
        let rise = farRise(close: close, rules: rules)
        let deck = (rise * rules.deckShare).rounded()
        let x0 = wallX + rules.deckInsetFeet * view.scale
        guard width > x0 else { return }
        let mass = look.deck[0], roof = look.deck[1], lamp = look.deck[2], column = look.deck[3]

        c.rect(x0 - 2, base - rise - 1, width - x0 + 2, 2, roof)
        c.rect(x0, base - rise + 1, width - x0, deck - 1, mass)

        // The row of lamps and dark windows along the fascia. Which ones are lit is a fixed
        // pattern off the pixel itself, not a roll: a deck's lights do not flicker (§17).
        var ry = base - rise + 3
        while ry < base - rise + deck - 1 {
            var wx = x0 + 2
            while wx < width {
                let lit = (Int(wx) * 7 + Int(ry)) % 5 < 2
                c.rect(wx, ry, close ? 3 : 2, 1, lit ? lamp : column)
                wx += close ? rules.deckWindowPitchClose : rules.deckWindowPitchWide
            }
            ry += rules.deckWindowRows
        }

        var cx = x0 + 4
        while cx < width {
            c.rect(cx, base - rise + deck, 2, rise - deck, column)
            cx += close ? rules.deckColumnPitchClose : rules.deckColumnPitchWide
        }
    }

    /// A string of pennants slung across the roof, on two posts that stop at it
    /// (`side.pennant_string`).
    private static func pennantString(into c: PixelCanvas, wallX: Double, base: Double,
                                      width: Double, rise: Double, close: Bool, look: Look,
                                      rules: FlightLookRules) {
        let line = look.deck[3]
        let cloths = [look.red[2], look.deck[1]]
        let px = wallX + (width - wallX) * rules.pennantAcross
        let y0 = base - rise - (close ? rules.pennantAboveClose : rules.pennantAboveWide)
        let half = rules.pennantHalfSpan, sag = rules.pennantSag
        c.line(px - half, y0, px + half, y0 + sag, line)
        var t = -(half - 2), n = 0
        while t <= half - 4 {
            let ly = y0 + (t + half) / (half * 2) * sag
            for j in 0..<4 {
                c.rect(px + t, ly + Double(j) + 1, Double(4 - j), 1, cloths[n % cloths.count])
            }
            t += rules.pennantPitch
            n += 1
        }
        // The two posts, stopping at the roof line and no lower.
        c.rect(px - half - 1, y0 - 1, 1, base - rise - y0, line)
        c.rect(px + half, y0 + sag - 1, 1, base - rise - y0 - sag, line)
    }

    /// A one-pixel lit rim down the side of the light: the first painted pixel of each row inside
    /// the box, from that side. It is an *inner* edge — nothing is painted outside the shape —
    /// which is the difference between §20's lit edge and the outline it forbids.
    private static func litEdge(into c: PixelCanvas, x0: Double, x1: Double, y0: Double, y1: Double,
                                colour: Palette.RGBA8, fromLeft: Bool) {
        let lo = max(0, Int(x0)), hi = min(c.width - 1, Int(x1))
        let top = max(0, Int(y0)), bottom = min(c.height - 1, Int(y1))
        guard hi >= lo, bottom >= top else { return }
        for y in top...bottom {
            var found = false
            var x = fromLeft ? lo : hi
            while fromLeft ? x <= hi : x >= lo {
                if c.packed(x, y) != 0 { found = true; break }
                x += fromLeft ? 1 : -1
            }
            if found { c.px(Double(x), Double(y), colour) }
        }
    }

    // MARK: - The wall and the stands

    /// The outfield wall: a lit top row under the `score` rail, an ordered-dither face that gets
    /// darker to its foot, panel seams, and the lit post where the foul pole meets it
    /// (`golden.flight`). §20's one change of role is the cap: `chalk` becomes `score`.
    static func wall(into c: PixelCanvas, park: Park, view: SideView, width: Double, look: Look,
                     rules: FlightLookRules = .standard) {
        let wallX = view.x(park.wallDistanceFeet)
        let top = view.y(park.wallHeightFeet)
        let ground = view.ground
        guard width > wallX, ground > top else { return }
        let lit = look.wall[0], face = look.wall[1], foot = look.wall[2]

        c.rect(wallX, top, width - wallX, ground - top, face)
        c.rect(wallX, top + 1, width - wallX, 1, lit)
        c.bayerGradient(wallX, top + 2, width - wallX, max(1, ground - top - 2), face, foot)
        var f = park.wallDistanceFeet + 20
        while view.x(f) < width {
            c.rect(view.x(f), top + 1, 1, ground - top - 1, foot)
            f += 20
        }
        c.rect(wallX, top, width - wallX, 1, Palette.score)
        c.rect(wallX, top - 1, 2, ground - top + 1, look.pole[0])
    }

    /// The stepped bleacher profile: a lit lip along each deck, a dark line under it, and a lit
    /// riser where one step climbs onto the next (`side.tiers`). The mass is the darkest of the
    /// phase's three stand tones — a stand in the lip's own colour and an outfield wall read as
    /// one shape.
    static func tiers(into c: PixelCanvas, park: Park, scenery: Scenery, view: SideView,
                      width: Double, look: Look) {
        let mass = look.standLit[2], lip = look.standLit[1], under = look.standLit[0]
        let wallTop = view.y(park.wallHeightFeet)
        let topY = view.y(scenery.standsTopFeet)
        let steps = max(1, scenery.standsSteps)
        for i in 0..<steps {
            let f0 = park.wallDistanceFeet + scenery.standsDepthFeet * Double(i) / Double(steps)
            let f1 = park.wallDistanceFeet + scenery.standsDepthFeet * Double(i + 1) / Double(steps)
            let h = park.wallHeightFeet
                + (scenery.standsTopFeet - park.wallHeightFeet) * Double(i + 1) / Double(steps)
            let x0 = view.x(f0), x1 = view.x(f1), top = view.y(h)
            guard x1 > 0, x0 < width, top < wallTop else { continue }
            let w = max(1, x1 - x0) + 1
            c.rect(x0, top, w, wallTop - top, mass)
            c.rect(x0, top, w, 1, lip)
            c.rect(x0, top + 1, w, 1, under)
            let prev = i == 0
                ? wallTop
                : view.y(park.wallHeightFeet
                         + (scenery.standsTopFeet - park.wallHeightFeet) * Double(i) / Double(steps))
            c.rect(x0, top, 1, prev - top, lip)
        }
        // Behind the back row the profile is flat, all the way out of frame.
        let backX = view.x(park.wallDistanceFeet + scenery.standsDepthFeet)
        if backX < width, topY < wallTop {
            c.rect(backX, topY, width - backX, wallTop - topY, mass)
            c.rect(backX, topY, width - backX, 1, lip)
            c.rect(backX, topY + 1, width - backX, 1, under)
        }
    }

    /// Single-A's chain-link: a sparse `chalk` mesh over the wall with posts in the stand colour.
    /// It is in front of the ball like the stands are, but you can see straight through it —
    /// which is the point, because this is the park where the ball is simply seen landing. §20
    /// leaves its shape alone.
    static func chainLink(into c: PixelCanvas, park: Park, scenery: Scenery, view: SideView,
                          width: Double, look: Look, layout: BackdropLayout = .standard) {
        let wallX = view.x(park.wallDistanceFeet)
        let wallTopY = view.y(park.wallHeightFeet)
        let meshFeet = scenery.standsTopFeet - park.wallHeightFeet
        let top = wallTopY - meshFeet * view.scale
        guard wallTopY - top >= 2, width > wallX else { return }
        var y = top
        while y < wallTopY {
            var x = wallX + (Int(y - top) % 2 == 0 ? 0 : layout.chainLinkPitchPixels / 2)
            while x < width { c.px(x, y, Palette.chalk); x += layout.chainLinkPitchPixels }
            y += layout.chainLinkPitchPixels
        }
        c.rect(wallX, top, width - wallX, 1, Palette.chalk)          // the top rail
        var postFeet = park.wallDistanceFeet
        while view.x(postFeet) < width {
            c.rect(view.x(postFeet), top, 1, wallTopY - top, look.standLit[2])
            postFeet += layout.fencePostSpacingFeet
        }
    }

    // MARK: - The crowd (§20 "Crowd")

    /// People in rows with aisles, thinned by the hour: a head pixel over a shirt pixel in the
    /// wide framing and 2×4 in the close one (`side.crowd_rows`). `look.crowdShare` says how many
    /// of the seats are taken — a quarter at dawn, nearly all at night — and thins the same
    /// seeded stream rather than reseeding it, so the people who are there at dawn are there at
    /// noon too.
    ///
    /// Drawn into one of three cached layers: nobody up, the even people up, the odd people up
    /// (§20 "Layers and speed"). A frame picks one, which is what §17's bounce costs now.
    static func crowd(into c: PixelCanvas, park: Park, scenery: Scenery, view: SideView,
                      width: Double, close: Bool, look: Look, lift: CrowdLift,
                      rules: FlightLookRules = .standard) {
        guard scenery.stands.hasCrowd, view.scale > 0 else { return }
        let pitch = close ? rules.crowdPitchClose : rules.crowdPitchWide
        let aisleWidth = close ? rules.aisleWidthClose : rules.aisleWidthWide
        let wallTop = view.y(park.wallHeightFeet)
        let topY = view.y(scenery.standsTopFeet)
        let heads = look.headsLit, shirts = look.shirtsLit
        let aisle = look.standLit[0]
        let bounce = SkyLifeRules.standard.crowdBounceLift

        var g = SplitMix64(seed: seed(scenery, tag: 0x4))
        var person = 0
        var row = 0
        var y = wallTop - (close ? 3 : 2)
        while y > topY + 1 {
            var x = view.x(park.wallDistanceFeet) + 2
                + Double(row % 2) * (Double(Int(pitch.x) / 2) + (close ? 1 : 0))
            while x < width {
                let feet = (x - view.originX) / view.scale
                let seatTop = view.y(scenery.standsHeightFeet(at: feet, park: park))
                let onAisle = (feet - park.wallDistanceFeet)
                    .truncatingRemainder(dividingBy: rules.aisleEveryFeet) < aisleWidth
                if y - (close ? 3 : 1) > seatTop {
                    if onAisle {
                        c.rect(x, y - (close ? 2 : 1), close ? 2 : 1, pitch.y, aisle)
                    } else {
                        // Every seat draws from the stream whether or not it is taken, so who is
                        // in the park at dawn is a subset of who is there at noon.
                        let taken = Double.random(in: 0..<1, using: &g)
                        let head = heads[Int.random(in: 0..<heads.count, using: &g)]
                        let shirt = shirts[Int.random(in: 0..<shirts.count, using: &g)]
                        if taken < look.crowdShare {
                            let up = lift.lifts(person) && y - bounce - (close ? 3 : 1) > seatTop
                            let py = y - (up ? bounce : 0)
                            if close {
                                c.rect(x, py - 3, 2, 2, head)
                                c.rect(x, py - 1, 2, 2, shirt)
                            } else {
                                c.px(x, py - 1, head)
                                c.px(x, py, shirt)
                            }
                            person += 1
                        }
                    }
                }
                x += pitch.x
            }
            y -= pitch.y
            row += 1
        }
    }

    /// The roof's own shadow, down the top rows of the stands and over the people in them — one
    /// of the places §20 allows a dither at all. Drawn per frame, after the crowd, because it
    /// falls on the crowd; the lit lips are left alone so the tiers still read as steps.
    static func roofShadow(into c: PixelCanvas, park: Park, scenery: Scenery, view: SideView,
                           width: Double, close: Bool, look: Look,
                           rules: FlightLookRules = .standard) {
        guard scenery.stands.swallowsTheBall else { return }
        let topY = view.y(scenery.standsTopFeet)
        let span = close ? rules.roofShadowRowsClose : rules.roofShadowRowsWide
        let x0 = max(0, view.x(park.wallDistanceFeet + rules.roofShadowFromFeet))
        guard width > x0 else { return }
        let lip = look.standLit[1], under = look.standLit[2]
        // Column by column rather than pixel by pixel: the profile's step is a divide and a
        // floor, and it is the same answer for every row of a column.
        var x = Int(x0)
        let lastX = min(c.width - 1, Int(width) - 1)
        let firstY = Int(topY) + 2, lastY = min(c.height - 1, Int(topY + span))
        guard lastY >= firstY else { return }
        while x <= lastX {
            let feet = (Double(x) - view.originX) / view.scale
            let seatTop = view.y(scenery.standsHeightFeet(at: feet, park: park))
            for y in firstY...lastY {
                guard Double(y) > seatTop + 1 else { continue }
                let density = (1 - (Double(y) - topY) / span) * rules.roofShadowStrength
                guard density > PixelCanvas.threshold(x, y) else { continue }
                guard c.packed(x, y) != lip.packed else { continue }
                c.px(Double(x), Double(y), under)
            }
            x += 1
        }
    }

    // MARK: - The furniture

    /// The foul pole: two columns, lit and shaded, with the mesh wing that catches a ball down
    /// the line (`side.foul_pole`). It is the one thing on the wall that is lit in every phase.
    static func foulPole(into c: PixelCanvas, park: Park, view: SideView, look: Look,
                         rules: FlightLookRules = .standard) {
        let wallX = view.x(park.wallDistanceFeet)
        let wallTop = view.y(park.wallHeightFeet)
        let lit = look.pole[0], dark = look.pole[1]
        let height = rules.foulPoleFeet * view.scale
        let w = max(2, (view.scale * rules.foulPoleWidthFeet).rounded())
        let wing = max(3, (rules.foulPoleWingFeet * view.scale).rounded())

        var y = wallTop - height
        while y < wallTop - height * rules.foulPoleWingShare {
            var x = wallX + w
            while x < wallX + w + wing {
                if (Int(x) + Int(y)) % 2 == 0 { c.px(x, y, dark) }
                x += 1
            }
            y += 1
        }
        c.rect(wallX, wallTop - height, w, height, lit)
        c.rect(wallX + w - 1, wallTop - height, 1, height, dark)
        c.rect(wallX - 1, wallTop - height - 1, w + 2, 1, lit)
    }

    /// The out-of-town board over the stands: a frame with a lit lip, a dark face, rows of dashes
    /// and the operator's lit pane with a glow around it (`side.board`). Drawn with the stands,
    /// in front of the ball, so a ball that reaches it goes into it — and §17's dents and its
    /// broken pane go over the top of this, per frame.
    ///
    /// The pane keeps the seeded corner it has always had rather than the prototype's fixed one:
    /// `RareEvents` judges a pane hit in feet, and the drawing has to agree with it (#5).
    static func board(into c: PixelCanvas, park: Park, scenery: Scenery, view: SideView,
                      width: Double, close: Bool, look: Look,
                      rules: FlightLookRules = .standard) {
        guard let board = scenery.board else { return }
        let w = park.wallDistanceFeet
        let left = view.x(board.nearFeet(wallDistanceFeet: w))
        let right = view.x(board.farFeet(wallDistanceFeet: w))
        let top = view.y(board.topFeet), bottom = view.y(board.bottomFeet)
        guard right > 0, left < width, bottom - top >= 4, right - left >= 6 else { return }

        let frame = look.board[0], lip = look.board[1], face = look.board[2]
        let legs = look.standLit[2]

        // Two legs down onto the stands it stands on, and the brace across them.
        let inset = (rules.boardLegInsetFeet * view.scale).rounded()
        let foot = view.y(scenery.standsHeightFeet(at: w + board.feetBehindWall, park: park))
        for lx in [left + inset, right - inset - rules.boardLegWidth] {
            c.rect(lx, bottom, rules.boardLegWidth, max(0, foot - bottom), legs)
        }
        c.line(left + inset, bottom, right - inset - 1, bottom + (right - left) * rules.boardBraceDrop,
               legs)

        c.rect(left - 1, top - 1, right - left + 2, bottom - top + 2, frame)
        c.rect(left, top, right - left, bottom - top, face)
        c.rect(left - 1, top - 1, right - left + 2, 1, lip)

        // Rows of dashes: at this size a board says "there is writing here" and nothing more.
        let dash = [look.grey[3], look.deck[1]]
        let pitch = close ? rules.boardRowPitchClose : rules.boardRowPitchWide
        var row = top + (close ? 3 : 2)
        while row < bottom - 1 {
            var dx = left + 2
            while dx < right - 2 {
                c.rect(dx, row, 2, 1, dash[Int(row / 3) % dash.count])
                dx += 4
            }
            row += pitch
        }

        // The operator's pane, lit, in its seeded top corner, with the glow §20 asks for.
        let pane = board.pane(wallDistanceFeet: w)
        let px = view.x(pane.near), py = view.y(pane.top)
        let pw = max(2, (pane.far - pane.near) * view.scale)
        let ph = max(2, (pane.top - pane.bottom) * view.scale)
        c.rect(px - 1, py - 1, pw + 2, ph + 2, look.deck[1])
        c.rect(px, py, pw, ph, look.deck[2])
    }

    // MARK: - The field (per frame: it is under the ball and moves with the ground)

    /// The mow: 16 ft stripes in three depth bands, each band starting on the other colour, so
    /// the outfield reads as a mown field seen almost edge-on (`side.checker_mow`).
    static func grass(into c: PixelCanvas, view: SideView, width: Double, look: Look,
                      rules: FlightLookRules = .standard) {
        let stripe = max(rules.minStripePixels, (rules.stripeFeet * view.scale).rounded())
        let height = Double(c.height)
        var y = view.ground
        for (n, rows) in rules.grassBandRows.enumerated() {
            let h = min(rows, height - y)
            guard h > 0 else { break }
            // Stripe zero starts at the plate, so the bands stay put as the ball flies: every
            // stripe is the same 16 ft of grass in every frame of the flight.
            var k = ((0 - view.x(0)) / stripe).rounded(.down) - 1
            while view.x(0) + k * stripe < width {
                let x = view.x(0) + k * stripe
                let even = Int(k) + n
                c.rect(x, y, stripe, h, even.isMultiple(of: 2) ? Palette.grassB : Palette.grassA)
                k += 1
            }
            y += rows
        }
    }

    /// The low sun's rake across the near grass, brightest at the edge it comes from and fading
    /// out over nine rows: an ordered-dither wash, and one of the six places §20 allows a dither.
    /// `dawn` has a low sun too, but behind this camera — only `goldenHour` gets the wash.
    static func lowSunWash(into c: PixelCanvas, view: SideView, width: Double, look: Look,
                           rules: FlightLookRules = .standard) {
        guard let sun = look.grassSun, look.sunFlight != nil, look.sunFlightMovesWithGround else { return }
        let fromLeft = look.light.x <= 0
        c.orderedDither(0, view.ground, width, rules.washRows, sun) { x, y in
            let xm = fromLeft ? Double(x) : width - 1 - Double(x)
            let across = max(0, 1 - xm / (width * rules.washReach))
            let down = 1 - (Double(y) - view.ground) / rules.washRows
            return across * down * rules.washStrength
        }
    }

    /// The field's marks: the circle round the plate, the mound, the infield skin out through
    /// second base, the warning track in front of the wall, and a chalk tick with a number under
    /// it every hundred feet (`side.field_marks`).
    static func fieldMarks(into c: PixelCanvas, park: Park, view: SideView, width: Double,
                           close: Bool, look: Look, rules: FlightLookRules = .standard) {
        let d = close ? rules.markDepthClose : rules.markDepthWide
        let body = look.dirt[1], lip = look.dirt[2], light = look.dirt[0]

        lens(into: c, view: view, feet: rules.plateCircleFeet, depth: d + 1,
             body: body, lip: lip, light: light, look: look, rules: rules)
        lens(into: c, view: view, feet: rules.moundFeet, depth: d - 1,
             body: body, lip: lip, light: light, look: look, rules: rules)
        lens(into: c, view: view, feet: rules.infieldFeet, depth: d + 1,
             body: body, lip: lip, light: light, look: look, rules: rules)
        c.rect(view.x(rules.secondBaseFeet) - 1, view.ground, close ? 3 : 2, 2, Palette.chalk)

        let trackX = view.x(park.wallDistanceFeet - rules.warningTrackFeet)
        let trackW = rules.warningTrackFeet * view.scale
        c.rect(trackX, view.ground, trackW, d, body)
        c.rect(trackX, view.ground + d, trackW, 1, lip)

        var f = rules.markPitchFeet
        while f < park.wallDistanceFeet - rules.markKeepOutFeet {
            let x = view.x(f)
            if x > 0, x < width {
                c.rect(x, view.ground + 1, 1, rules.markTickRows, Palette.chalk)
                c.t3(x + 3, view.ground + rules.markNumberDrop, "\(Int(f))", Palette.chalk,
                     shadow: Palette.ink)
            }
            f += rules.markPitchFeet
        }
    }

    /// A patch of dirt seen almost edge-on: flat on the far side, rounded toward the camera, with
    /// a light edge on the side the light comes from and a darker lip nearest the camera
    /// (`side.lens`).
    private static func lens(into c: PixelCanvas, view: SideView, feet: ClosedRange<Double>,
                             depth: Double, body: Palette.RGBA8, lip: Palette.RGBA8,
                             light: Palette.RGBA8, look: Look, rules: FlightLookRules) {
        guard depth > 0 else { return }
        let x0 = view.x(feet.lowerBound), x1 = view.x(feet.upperBound)
        let cx = (x0 + x1) / 2, rx = max(2, (x1 - x0) / 2)
        let lightSign: Double = look.light.x <= 0 ? -1 : 1
        // `Mask.ellipse`'s loop, written out: this one runs every frame, and the array of
        // `MaskPixel` it would build is an allocation the frame budget does not need.
        let yLo = Int(view.ground), yHi = Int(view.ground + depth) + 1
        let xLo = Int(cx - rx) - 1, xHi = Int(cx + rx) + 1
        guard yHi >= yLo, xHi >= xLo else { return }
        for y in yLo...yHi {
            let ny = (Double(y) + 0.5 - view.ground) / depth
            guard ny >= 0, ny <= 1 else { continue }
            for x in xLo...xHi {
                let nx = (Double(x) + 0.5 - cx) / rx
                guard nx * nx + ny * ny <= 1 else { continue }
                var tone = body
                if ny > rules.lensLipBelow {
                    tone = lip
                } else if ny < rules.lensLightAbove, nx * lightSign > rules.lensLightSide {
                    tone = light
                }
                c.px(Double(x), Double(y), tone)
            }
        }
    }

    // MARK: - The batter, the trail and the ball

    /// The batter, seven pixels by eight and never smaller — the one figure in this camera, at
    /// the far left of the field with his back to you (`side.TINY_A`). With the sun low he throws
    /// a long shadow away from it, thinning to every other pixel as it goes.
    static let tinyBatter = ["B...RR.", ".B..RRR", "..B.SS.", "..KKKK.",
                             "...KKK.", "...KKK.", "...K.K.", "..KK.KK"]

    static func batter(into c: PixelCanvas, view: SideView, look: Look,
                       rules: FlightLookRules = .standard) {
        let x = view.x(0), ground = view.ground

        // The long shadow: only when the sun is low enough to cast one across the grass, and
        // always away from it (§20 "Cast shadows").
        if look.dimSide != 0 {
            let away: Double = look.light.x <= 0 ? 1 : -1
            for k in 1...rules.batterShadowPixels where k < rules.batterShadowSolid || k % 2 == 0 {
                c.px(x + away * Double(k), ground + 1 + (Double(k) / rules.batterShadowDropEvery).rounded(.down),
                     Palette.shade)
            }
        }

        let legend: [Character: Palette.RGBA8] = [
            "B": look.wood[2], "R": look.red[2], "S": look.skin[2], "K": look.grey[2]
        ]
        let left = x.rounded(.down) - 4, top = ground.rounded(.down) - 8
        for (j, row) in tinyBatter.enumerated() {
            for (i, ch) in row.enumerated() {
                guard let colour = legend[ch] else { continue }
                c.px(left + Double(i), top + Double(j), colour)
            }
        }
    }

    /// The trail from the bat to the ball: always `chalk`, the six newest dots 2×2 and the oldest
    /// one in two. The colour never changes with age — a trail that cools reads as two trails
    /// (§20 "Trail", `side.trail`).
    static func trail(into c: PixelCanvas, points: [FlightPoint], index: Int, view: SideView,
                      close: Bool, rules: FlightLookRules = .standard) {
        let step = close ? rules.trailStepClose : rules.trailStepWide
        var k = index - step
        var n = 0
        while k > 0 {
            let p = points[k]
            let x = view.x(p.xFeet), y = view.y(p.yFeet) - rules.trailLift
            if n < rules.trailBigDots {
                c.rect(x, y, 2, 2, Palette.chalk)
            } else if n < rules.trailThinAfter || n.isMultiple(of: 2) {
                c.px(x, y, Palette.chalk)
            }
            k -= step
            n += 1
        }
    }

    /// The ball, with its shadow on the ground in both framings (§20 "Ball"). Four pixels with a
    /// highlight and an underside in the wide framing; the six-pixel baseball of §9 in the close
    /// one.
    static func ball(into c: PixelCanvas, at point: FlightPoint, view: SideView, close: Bool,
                     look: Look, rules: FlightLookRules = .standard) {
        let x = view.x(point.xFeet), y = view.y(point.yFeet) - rules.ballLift
        let away: Double = look.light.x <= 0 ? 1 : -1
        let s = close ? rules.ballShadowClose : rules.ballShadowWide
        // The shadow leans away from the light, the way the batter's long one does.
        let shadowX = away > 0 ? x + s.lead : x - s.w - s.lead + 1
        c.rect(shadowX, view.ground + s.drop, s.w, s.h, Palette.shade)
        if close {
            c.baseball(x, y, radius: 3, highlight: look.ballHi)
            c.px(x + 2, y + 2, look.ballLo)
            c.px(x + 1, y + 3, look.ballLo)
        } else {
            c.rect(x - 1, y - 1, 4, 4, Palette.chalk)
            c.px(x - 1, y - 1, look.ballHi)
            c.px(x + 2, y + 2, look.ballLo)
            c.px(x + 1, y + 1, Palette.cap)     // all the lace a 4 px ball has room for
        }
    }

    // MARK: - Shared

    /// The top of whatever is built behind the wall: the stands where there are stands, the wall
    /// itself where there are none (Single-A).
    static func standsTopY(park: Park, scenery: Scenery, view: SideView) -> Double {
        scenery.stands.swallowsTheBall
            ? view.y(scenery.standsTopFeet)
            : view.y(park.wallHeightFeet)
    }

    /// One seeded stream per park and purpose, the same arithmetic `BackdropArt` uses: park 87's
    /// ridge is park 87's ridge on every phone (§17). Nothing here is ever `random()`.
    private static func seed(_ scenery: Scenery, tag: UInt64) -> UInt64 {
        UInt64(scenery.parkNumber) &* 0x7F4A_7C15_9E37_79B9 &+ tag &* 0x9E37_79B9_7F4A_7C15
    }
}

/// One cached layer of the flight camera, sealed into runs.
///
/// `BackdropLayer` seals to a bounding box and tests every pixel inside it. That is right for the
/// at-bat camera's pieces, which are small; §20 hands this camera a `behind` layer that is hills
/// and trees along the whole ground line with a tower lattice standing the full height of the
/// frame, and a box round that is the whole screen. So this one remembers, per row, the runs of
/// painted pixels, and copies each run with one `memmove`. Same picture, a twentieth of the work.
final class FlightLayer {
    let canvas: PixelCanvas
    /// `runs[rowFirst[y]..<rowFirst[y + 1]]` are row `y`'s painted spans. Flat arrays rather than
    /// an array of arrays: this is walked 60 times a second and never grown after `seal`.
    private var rowFirst: [Int]
    private var runX: [Int32] = []
    private var runLength: [Int32] = []

    init(width: Int, height: Int) {
        canvas = PixelCanvas(width: width, height: height)
        canvas.fill(Palette.clear)
        rowFirst = Array(repeating: 0, count: height + 1)
    }

    func clear() {
        canvas.fill(Palette.clear)
        runX.removeAll(keepingCapacity: true)
        runLength.removeAll(keepingCapacity: true)
        for i in rowFirst.indices { rowFirst[i] = 0 }
    }

    /// Works out the runs. Called once, after the art is in.
    func seal() {
        runX.removeAll(keepingCapacity: true)
        runLength.removeAll(keepingCapacity: true)
        for y in 0..<canvas.height {
            rowFirst[y] = runX.count
            let row = canvas.buffer + y * canvas.width
            var x = 0
            while x < canvas.width {
                guard row[x] != 0 else { x += 1; continue }
                let start = x
                while x < canvas.width, row[x] != 0 { x += 1 }
                runX.append(Int32(start))
                runLength.append(Int32(x - start))
            }
        }
        rowFirst[canvas.height] = runX.count
    }

    /// Copies every painted run onto `target`, `dy` rows down.
    func blit(onto target: PixelCanvas, dy: Int = 0) {
        guard target.width == canvas.width else { return }
        for y in 0..<canvas.height {
            let ty = y + dy
            guard ty >= 0, ty < target.height else { continue }
            var i = rowFirst[y]
            let end = rowFirst[y + 1]
            guard i < end else { continue }
            let src = canvas.buffer + y * canvas.width
            let dst = target.buffer + ty * target.width
            while i < end {
                let x = Int(runX[i])
                (dst + x).update(from: src + x, count: Int(runLength[i]))
                i += 1
            }
        }
    }

    /// Copies every row straight onto `target`, transparent pixels and all — the opaque blit the
    /// `sky` layer takes (§20 "Layers and speed").
    func blitOpaque(onto target: PixelCanvas) {
        target.copyRows(from: canvas)
    }
}

/// Six cached layers per framing, and both framings held at once (§20 "Layers and speed"):
/// `sky`, `behind`, `front` and the crowd's three. The wide and the close set are built together,
/// during the contact freeze at the head of a flight, so the cut between them costs nothing but a
/// pointer — the cut has to stay hard.
final class FlightLayers {
    let sky: FlightLayer
    let behind: FlightLayer
    let front: FlightLayer
    /// Nobody up, the even people up, the odd people up. A frame draws exactly one of them.
    let crowdSeated: FlightLayer
    let crowdEven: FlightLayer
    let crowdOdd: FlightLayer

    init(width: Int, height: Int) {
        sky = FlightLayer(width: width, height: height)
        behind = FlightLayer(width: width, height: height)
        front = FlightLayer(width: width, height: height)
        crowdSeated = FlightLayer(width: width, height: height)
        crowdEven = FlightLayer(width: width, height: height)
        crowdOdd = FlightLayer(width: width, height: height)
    }

    /// The crowd layer for one of the bounce's three states.
    func crowd(_ lift: FlightArt.CrowdLift) -> FlightLayer {
        switch lift {
        case .none: return crowdSeated
        case .even: return crowdEven
        case .odd: return crowdOdd
        }
    }

    var all: [FlightLayer] { [sky, behind, front, crowdSeated, crowdEven, crowdOdd] }

    func clear() { for layer in all { layer.clear() } }
    func seal() { for layer in all { layer.seal() } }
}

/// The flight camera's backdrop cache. `BackdropCache` holds one key, which is right for the
/// at-bat camera; this one holds two, because the wide and the close framings are two drawings of
/// the same park and the cut between them must not stop to paint (§20 "Layers and speed").
final class FlightBackdropCache {
    private var keys: [BackdropKey] = []
    private var sets: [FlightLayers] = []

    /// The layers for this key, drawing them first if anything moved. At most two entries are
    /// kept — the wide and the close framing of the flight that is on screen — and the older one
    /// is thrown away when a third arrives.
    func layers(for key: BackdropKey, height: Int, draw: (FlightLayers) -> Void) -> FlightLayers {
        if let i = keys.firstIndex(of: key) { return sets[i] }
        let made = FlightLayers(width: key.width, height: height)
        draw(made)
        made.seal()
        keys.append(key)
        sets.append(made)
        if keys.count > 2 { keys.removeFirst(); sets.removeFirst() }
        return made
    }

    /// Whether this key is already painted, so a caller can decide to paint the other framing
    /// while the game is frozen rather than at the cut.
    func holds(_ key: BackdropKey) -> Bool { keys.contains(key) }
}
