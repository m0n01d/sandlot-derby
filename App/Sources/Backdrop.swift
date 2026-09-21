import Foundation
import DerbyCore

/// The backdrops' own pixel knobs (DESIGN.md §17). Feet live in `SceneryRules` in Core, where
/// they are a pure function of the park; these are the drawing's numbers and nothing else reads
/// them.
struct BackdropLayout {
    /// At-bat: the horizon sits in the bottom of the `sky3` band, right above the wall band
    /// (§17: "a low band above the wall, y 86–96").
    var atBatHorizonTop = 86.0
    var atBatHorizonBottom = 96.0
    /// At-bat: a near piece stands this far in from the edge of the 320-wide column, on
    /// whichever side of the scoreboard its park's seed picks.
    var atBatNearLeftX = 72.0
    var atBatNearRightX = 248.0
    /// At-bat: the two little flags on the scoreboard, as offsets from its left edge, and how
    /// far their poles rise above it. Static until step 5 gives them a flutter.
    var scoreboardFlagOffsets = [6.0, 55.0]
    var scoreboardFlagPoleHeight = 8.0

    /// Side view: a flag's pole and its pennant, in the wide framing and in the close one. The
    /// close camera is twice the scale, so its flags are the bigger pair (§20, `side.flags`).
    var flagPoleHeight = 11.0
    var flagPennant = (w: 6.0, h: 4.0)
    var flagPoleHeightClose = 16.0
    var flagPennantClose = (w: 9.0, h: 6.0)
    /// Side view, Single-A only: the chain-link mesh above the wall, and its posts, in feet.
    var chainLinkPitchPixels = 3.0
    var fencePostSpacingFeet = 20.0

    /// The ball vanishes with a `chalk` pop this big, for this long (seconds), in two frames
    /// (§17: no alpha — things blink, shrink or stop).
    var popRadius = 3.0
    var popSeconds = 0.45

    // MARK: - The night kit (DESIGN.md §17)

    /// The moon's bite: a night-coloured disc this much of the moon's radius, pushed this far
    /// to the seeded side of it.
    var moonBiteRadius = 0.82
    var moonBiteOffset = 0.62
    /// A lamp and the gap between lamps in a bank. Three pixels is the smallest thing that can
    /// carry a `score` centre and still read as a lamp rather than a speck.
    var lampSize = 3.0
    var lampGap = 1.0
    /// The lattice pole: this wide where it meets the bank, this wide at its foot, with a rung
    /// and a diagonal every so often.
    var towerTopWidth = 4.0
    var towerFootWidth = 9.0
    var towerRungPitch = 7.0
    /// The dithered halo. An ellipse that hugs the bank — this far out beyond it sideways and
    /// this far above and below — rather than a circle around its middle: a bank is a wide,
    /// shallow thing and a round glow around one read as snow falling past it. Three rings at
    /// these fractions of that spread, each thinner than the last. A bank that is dark in the
    /// chase keeps only the innermost, so the glow travels rather than switching off.
    var haloSpreadX = 7.0
    var haloSpreadY = 6.0
    /// How much of that spread the glow gets *below* the bank. A lamp bank is aimed at the
    /// field and its bloom goes up and out; a symmetrical glow put half of itself down the
    /// pole, where it read as grit rather than light.
    var haloBelowShare = 0.5
    var haloRings = [0.5, 0.78, 1.0]
    var haloRingsWhenDark = 1
    /// At-bat: the towers flank the scoreboard (x 128…192), nearest pair first, standing on the
    /// top of the wall band. Well clear of the zone, which starts at y 136.
    var atBatTowerSlots = [96.0, 224.0, 62.0, 258.0]
    var atBatTowerFootY = 96.0
    var atBatTowerHeight = 34.0

    // MARK: - Foul poles in the at-bat camera (#28)

    /// One at each corner, rising from the top of the wall band where each foul line meets it,
    /// in `score` like the side view's. Taller the higher up the ladder you are, the way the
    /// stands' heights step: a sandlot's are just shorter.
    var foulPoleWidth = 2.0
    /// The screen on top of an at-bat pole: this deep, and a pixel wider than the pole on each
    /// side (§20, `golden.at_bat`).
    var foulPoleCapHeight = 2.0
    /// The top of the wall band, which is what they stand on. The same number as the towers'
    /// foot and deliberately its own knob: the two have nothing to do with each other.
    var atBatFoulPoleFootY = 96.0
    var foulPoleHeightSingleA = 16.0
    var foulPoleHeightDoubleA = 20.0
    var foulPoleHeightTripleA = 24.0
    var foulPoleHeightTheShow = 28.0

    func foulPoleHeight(for league: League) -> Double {
        switch league {
        case .singleA: return foulPoleHeightSingleA
        case .doubleA: return foulPoleHeightDoubleA
        case .tripleA: return foulPoleHeightTripleA
        case .theShow: return foulPoleHeightTheShow
        }
    }

    // MARK: - Landmarks and the milestone sky (#5)

    /// A dent in the board: a bright scar with rays, the way a dent in a metal panel catches the
    /// light. (A broken pane keeps no cracks — see `boardDamage`: there is no room for them.)
    /// How the board itself is drawn is `FlightLookRules`', with the stands it stands on.
    var dentRadius = 2.0

    /// The blimp's envelope and its tail fin, in design pixels. Big enough to read as a blimp at
    /// 320 across and no bigger: it shares the sky with the birds and must not crowd them.
    var blimpWidth = 21.0
    var blimpHeight = 7.0
    var blimpFin = 4.0

    /// A searchlight beam starts this far along its own line — inside that it is behind the
    /// stands — and widens by this much per pixel travelled.
    var searchlightStartPixels = 4.0
    var searchlightSpread = 0.055

    /// Every cached layer is drawn with the ground here and copied `dy` rows down, so the close
    /// camera lifting the ground out of frame does not cost a rebuild.
    static let canonicalGround = 176.0

    static let standard = BackdropLayout()
}

/// Everything a cached layer's art depends on. When this changes, and only then, the layer is
/// drawn again: once per park, canvas width and framing, which in the side view means once per
/// flight rather than once per frame.
struct BackdropKey: Equatable {
    enum Camera { case atBat, wide, close }
    let parkNumber: Int
    let width: Int
    let camera: Camera
    /// Pixels per foot × 64, rounded — the side view re-frames per flight, never per frame.
    let scale64: Int
    let originX: Int
    /// Which of the six looks this art was painted in. Every colour in here comes off the phase's
    /// palette lines, so a layer drawn at `midday` is wrong the moment the clock reaches
    /// `goldenHour` and the key has to say so (DESIGN.md §20). It replaces the lamps flag that
    /// step 1 put here: the lamps are one of the things a phase decides, not the only one.
    let phase: DayPhase

    init(parkNumber: Int, width: Int, camera: Camera, phase: DayPhase,
         scale: Double = 0, originX: Double = 0) {
        self.parkNumber = parkNumber
        self.width = width
        self.camera = camera
        self.phase = phase
        self.scale64 = Int((scale * 64).rounded())
        self.originX = Int(originX.rounded())
    }
}

/// One cached layer of static art. It is a sprite, not a picture: it starts as the palette's
/// sixteenth entry (transparent) and is copied onto the frame by colour key, which is how a
/// Mega Drive put anything over anything. No alpha is blended, ever.
final class BackdropLayer {
    let canvas: PixelCanvas
    /// The rows and columns that actually carry paint, so the per-frame copy walks no further.
    private var firstRow = 0, lastRow = -1, firstCol = 0, lastCol = -1
    /// Which of those rows carry paint from `firstCol` to `lastCol` with no gap at all. Most of
    /// the at-bat `front` layer is like that — the wall, the track and the grass go edge to edge
    /// — and a solid row is a `memcpy` rather than a test and a store per pixel. In a Debug
    /// build that is the difference between 12 ms a frame and half of one (§20 "Layers and
    /// speed"; CLAUDE.md on Debug being slow at pixel work).
    private var solidRow: [Bool] = []

    init(width: Int, height: Int) {
        canvas = PixelCanvas(width: width, height: height)
        canvas.fill(Palette.clear)
    }

    func clear() {
        canvas.fill(Palette.clear)
        firstRow = 0; lastRow = -1; firstCol = 0; lastCol = -1
        solidRow = []
    }

    /// Works out the drawn bounds, and which rows are solid across them. Called once, after the
    /// art is in.
    func seal() {
        var top = Int.max, bottom = -1, left = Int.max, right = -1
        var painted = [Int](repeating: 0, count: canvas.height)
        for y in 0..<canvas.height {
            let row = canvas.buffer + y * canvas.width
            for x in 0..<canvas.width where row[x] != 0 {
                painted[y] += 1
                if y < top { top = y }
                if y > bottom { bottom = y }
                if x < left { left = x }
                if x > right { right = x }
            }
        }
        firstRow = top; lastRow = bottom; firstCol = left; lastCol = right
        // Every painted pixel is inside the box by construction, so a row holding as many as the
        // box is wide is a row that fills it.
        let span = right - left + 1
        solidRow = painted.map { $0 == span && span > 0 }
    }

    /// Copies every row straight onto `target`, transparent pixels and all — the opaque blit the
    /// `sky` layer takes (§20 "Layers and speed"). Nothing is keyed out, because the sky is the
    /// bottom of the frame and there is nothing under it to show through.
    func blitOpaque(onto target: PixelCanvas) {
        target.copyRows(from: canvas)
    }

    /// Copies every painted pixel onto `target`, `dy` rows down. A row the art filled end to end
    /// goes over in one move; the rest are keyed pixel by pixel, which is what lets the sky show
    /// through the gap the scoreboard stands in.
    func blit(onto target: PixelCanvas, dy: Int = 0) {
        guard lastRow >= firstRow, lastCol >= firstCol else { return }
        guard target.width == canvas.width else { return }
        let count = lastCol - firstCol + 1
        for y in firstRow...lastRow {
            let ty = y + dy
            guard ty >= 0, ty < target.height else { continue }
            let src = canvas.buffer + y * canvas.width
            let dst = target.buffer + ty * target.width
            if solidRow.indices.contains(y), solidRow[y] {
                (dst + firstCol).update(from: src + firstCol, count: count)
                continue
            }
            // A plain `while` over raw pointers, not `for … where`: this is the one loop in the
            // frame that runs a hundred thousand times, and a Debug build pays for every bit of
            // iteration machinery in it.
            var x = firstCol
            while x <= lastCol {
                let word = src[x]
                if word != 0 { dst[x] = word }
                x += 1
            }
        }
    }
}

/// Three layers per camera, held until the park, the canvas, the framing or the phase changes
/// (DESIGN.md §17 "a backdrop cache", §20 "Layers and speed"):
///
/// - `sky` — the stops and whichever of the sun or the moon is up. Opaque, copied by rows, and it
///   never moves with the ground: the sky is infinitely far away.
/// - `behind` — the hills and the trees, and in the flight camera the low sun, which *is* a thing
///   in the park and does move with the ground.
/// - `front` — the wall, the stands, the poles: everything that goes in on top of the ball.
final class BackdropCache {
    private var key: BackdropKey?
    private var sky: BackdropLayer?
    private var behind: BackdropLayer?
    private var front: BackdropLayer?

    /// The layers for this key, drawing them first if anything moved. `draw` runs rarely; the
    /// rest of the time this is three pointer returns.
    func layers(for key: BackdropKey, height: Int,
                draw: (_ sky: BackdropLayer, _ behind: BackdropLayer, _ front: BackdropLayer) -> Void)
        -> (sky: BackdropLayer, behind: BackdropLayer, front: BackdropLayer) {
        if let sky, let behind, let front, self.key == key { return (sky, behind, front) }
        let s = sky?.canvas.width == key.width ? sky! : BackdropLayer(width: key.width, height: height)
        let b = behind?.canvas.width == key.width ? behind! : BackdropLayer(width: key.width, height: height)
        let f = front?.canvas.width == key.width ? front! : BackdropLayer(width: key.width, height: height)
        s.clear(); b.clear(); f.clear()
        draw(s, b, f)
        s.seal(); b.seal(); f.seal()
        self.key = key; self.sky = s; self.behind = b; self.front = f
        return (s, b, f)
    }
}

/// The backdrop art. Static functions over a `PixelCanvas`, so they can be pointed at a cached
/// layer or at the frame itself. Colours are borrowed by role, one palette line, whole pixels.
enum BackdropArt {

    // MARK: - The at-bat horizon (DESIGN.md §17, §20)
    //
    // §17's low band above the wall is gone: since §20 step 3 the at-bat horizon is two layers
    // of round hills and a treeline, and where a park has wings the wings *are* its far piece
    // (§20 "Stands at bat, by tier"). `AtBatArt.horizon` draws it, and still calls `far` and
    // `near` below for the parks with no stand to hide them.

    /// The two little flags on the scoreboard, pointing with the breeze and fluttering in two
    /// frames. Drawn per frame, not cached: the flutter is what step 5 added.
    static func scoreboardFlags(into c: PixelCanvas, scenery: Scenery, xOffset: Double,
                                frame: Int, look: Look, layout: BackdropLayout = .standard) {
        let pointRight = scenery.breezePixelsPerSecond >= 0
        for dx in layout.scoreboardFlagOffsets {
            let x = (xOffset + 128 + dx).rounded()
            let top = 80 - layout.scoreboardFlagPoleHeight
            c.rect(x, top, 1, layout.scoreboardFlagPoleHeight, look.grey[3])
            pennant(into: c, x: x, top: top, pointRight: pointRight, frame: frame,
                    colour: look.red[2], size: (w: 4, h: 3))
        }
    }

    /// The foul poles in the at-bat camera (#28): one at each corner, standing on the top of
    /// the wall band exactly where its foul line meets it. Drawn after the wings, which they
    /// stand in front of, and before anything on the field.
    static func atBatFoulPoles(into c: PixelCanvas, league: League, xs: [Double], look: Look,
                               layout: BackdropLayout = .standard) {
        let height = layout.foulPoleHeight(for: league)
        // Two columns, lit and shaded, with the lit one on the side the light comes from (§20).
        // The pole is two pixels wide already, so this is the same shape in two colours.
        let lit = look.light.x < 0 ? look.pole[0] : look.pole[1]
        let dark = look.light.x < 0 ? look.pole[1] : look.pole[0]
        for x in xs {
            // No rounding: `PixelCanvas.rect` and `PixelCanvas.line` both truncate, so passing
            // the foul line's own endpoint straight through puts the pole's first column on
            // exactly the pixel the line ends on. Rounding it first put it one to the right.
            c.rect(x, layout.atBatFoulPoleFootY - height, 1, height, lit)
            c.rect(x + 1, layout.atBatFoulPoleFootY - height, layout.foulPoleWidth - 1, height, dark)
            // The screen on top, in `score`: it is the one thing in the park that is the same
            // colour in every phase, and without it a foul pole is a stripe (`golden.at_bat`).
            c.rect(x - 1, layout.atBatFoulPoleFootY - height - layout.foulPoleCapHeight,
                   layout.foulPoleWidth + 2, layout.foulPoleCapHeight, Palette.score)
        }
    }

    // MARK: - The side view (DESIGN.md §17)

    /// How high the stands stand, in feet, at `feet` from the plate. The sum moved into Core
    /// with #5 (`Scenery.standsHeightFeet`): it decides where a home run disappears and what a
    /// landmark on the stands is standing on, which makes it game geometry and not drawing.
    static func standsHeightFeet(at feet: Double, park: Park, scenery: Scenery,
                                 layout: BackdropLayout = .standard) -> Double {
        scenery.standsHeightFeet(at: feet, park: park)
    }

    // MARK: - The out-of-town board (#5)

    /// The board itself moved to `FlightArt.board` with §20 step 4: it is the flight camera's
    /// alone, and its new drawing — a frame with a lit lip, rows of dashes and a lit pane with a
    /// glow — belongs beside the stands it stands on. What a ball has *done* to it stays here,
    /// because it is drawn per frame rather than cached.
    ///
    /// What a ball has already done to the board, drawn per frame over the cached panel: the
    /// dents that stay for the rest of the park, and a pane that is not there any more (#5).
    static func boardDamage(into c: PixelCanvas, park: Park, scenery: Scenery, scars: ParkScars,
                            scale: Double, originX: Double, ground: Double, look: Look,
                            layout: BackdropLayout = .standard) {
        guard let board = scenery.board else { return }
        func x(_ feet: Double) -> Double { originX + feet * scale }
        func y(_ feet: Double) -> Double { ground - feet * scale }
        let w = park.wallDistanceFeet

        if scars.paneIsBroken {
            let pane = board.pane(wallDistanceFeet: w)
            let px = x(pane.near), py = y(pane.top)
            let pw = max(2, (pane.far - pane.near) * scale)
            let ph = max(2, (pane.top - pane.bottom) * scale)
            c.rect(px, py, pw, ph, look.board[2])                     // the dark where a light was
            // Two corners of glass still in the frame, and no more: a pane is four pixels by
            // three at this scale, and cracks drawn across one read as a scribble.
            c.px(px, py, Palette.chalk)
            c.px(px + pw - 1, py + ph - 1, Palette.chalk)
        }

        for dent in scars.dents {
            let dx = x(dent.x).rounded(), dy = y(dent.y).rounded(), r = layout.dentRadius
            // A star, not a disc: a dent in a metal panel is a bright scar with rays.
            c.rect(dx - r, dy, r * 2 + 1, 1, Palette.chalk)
            c.rect(dx, dy - r, 1, r * 2 + 1, Palette.chalk)
            c.px(dx - r + 1, dy - r + 1, Palette.chalk)
            c.px(dx + r - 1, dy + r - 1, Palette.chalk)
        }
    }

    /// Flags along the top of the stands, pointing with the breeze and fluttering in two frames.
    /// Drawn per frame beside the crowd, because it is the wind that moves them.
    ///
    /// §20 leaves the two frames and the flutter exactly where §17 put them and changes only the
    /// size: the close framing is twice the scale, so its poles and cloths are the bigger pair
    /// (`side.flags`).
    static func standsFlags(into c: PixelCanvas, park: Park, scenery: Scenery,
                            scale: Double, originX: Double, width: Double, ground: Double,
                            frame: Int, close: Bool = false, look: Look,
                            layout: BackdropLayout = .standard) {
        let x0 = originX + park.wallDistanceFeet * scale
        guard scenery.flags > 0, width > x0 else { return }
        let top = ground - scenery.standsTopFeet * scale
        let pointRight = scenery.breezePixelsPerSecond >= 0
        let poleHeight = close ? layout.flagPoleHeightClose : layout.flagPoleHeight
        let size = close ? layout.flagPennantClose : layout.flagPennant
        for i in 0..<scenery.flags {
            let t = (Double(i) + 1) / Double(scenery.flags + 1)
            let fx = (x0 + (width - x0) * t).rounded()
            let poleTop = top - poleHeight
            c.rect(fx, poleTop, 1, poleHeight, look.grey[3])
            pennant(into: c, x: fx, top: poleTop, pointRight: pointRight, frame: frame,
                    colour: look.red[2], size: size)
        }
    }

    /// One pennant in one of its two flutter frames: the cloth snaps between a high tail and a
    /// low one. Three rows either way, so a flag never changes size as it flies — with no alpha
    /// and no tweening, two frames is the whole vocabulary (§17).
    private static func pennant(into c: PixelCanvas, x: Double, top: Double,
                                pointRight: Bool, frame: Int, colour: Palette.RGBA8,
                                size: (w: Double, h: Double)) {
        let w = size.w
        let rows: [(dx: Double, w: Double)] = frame == 0
            ? [(0, w), (0, w), (1, w - 1)]
            : [(1, w - 1), (0, w), (0, w)]
        for (j, row) in rows.prefix(Int(size.h)).enumerated() {
            let y = top + Double(j)
            let rw = max(1, row.w)
            c.rect(pointRight ? x + 1 + row.dx : x - row.dx - rw, y, rw, 1, colour)
        }
    }

    // MARK: - The pieces

    /// A far piece: one silhouette along a baseline, at most `rise` tall, in a single colour
    /// with `hole` punched through it for windows and rows — distance with no new colour.
    static func far(_ piece: Backdrop, into c: PixelCanvas, x0: Double, x1: Double,
                    baseline: Double, rise: Double,
                    body: Palette.RGBA8, hole: Palette.RGBA8, seed: UInt64) {
        guard x1 > x0, rise >= 2 else { return }
        var g = SplitMix64(seed: seed)

        switch piece {
        case .treeline:
            // One in five stands well clear of the rest and breaks the top of the band. That
            // raggedness is the whole difference between a treeline and a low ridge.
            var x = x0 - 6
            while x < x1 {
                let w = Double(Int.random(in: 5...9, using: &g))
                let tall = Int.random(in: 0...4, using: &g) == 0
                let span = tall ? 1.05...1.35 : 0.35...0.8
                let h = max(3, (rise * Double.random(in: span, using: &g)).rounded())
                c.rect(x, baseline - h, w, h, body)
                c.rect(x + 1, baseline - h - 1, max(1, w - 2), 1, body)   // a rounded crown
                x += w - 1
            }

        case .mountains:
            var x = x0 - 12
            while x < x1 {
                let w = Double(Int.random(in: 26...48, using: &g))
                let h = (rise * Double.random(in: 0.6...1.0, using: &g)).rounded()
                let peak = x + w / 2
                var j = 0.0
                while j < h {
                    let half = (w / 2) * (j / max(1, h))
                    c.rect(peak - half, baseline - h + j, max(1, half * 2), 1, body)
                    j += 1
                }
                x += w * Double.random(in: 0.45...0.8, using: &g)
            }

        case .skyline:
            var x = x0
            while x < x1 {
                let w = Double(Int.random(in: 6...15, using: &g))
                let h = (rise * Double.random(in: 0.45...1.0, using: &g)).rounded()
                c.rect(x, baseline - h, w, h, body)
                var wy = baseline - h + 2
                while wy < baseline - 1 {
                    var wx = x + 1
                    while wx < x + w - 1 { c.px(wx, wy, hole); wx += 3 }
                    wy += 3
                }
                x += w + Double(Int.random(in: 0...2, using: &g))
            }

        case .bleachers:
            c.rect(x0, baseline - rise, x1 - x0, rise, body)
            var ry = baseline - rise + 2
            while ry < baseline { c.rect(x0, ry, x1 - x0, 1, hole); ry += 3 }
            var ax = x0 + 14
            while ax < x1 { c.rect(ax, baseline - rise, 1, rise, hole); ax += 27 }

        case .upperDeck:
            let deck = (rise * 0.6).rounded()
            c.rect(x0, baseline - rise, x1 - x0, deck, body)
            var ry = baseline - rise + 2
            while ry < baseline - rise + deck { c.rect(x0, ry, x1 - x0, 1, hole); ry += 3 }
            c.rect(x0, baseline - rise + deck, x1 - x0, 1, body)
            var cx = x0 + 6
            while cx < x1 { c.rect(cx, baseline - rise + deck, 2, rise - deck, body); cx += 17 }

        default:
            // A near piece asked to be a horizon: draw it where it stands and no more.
            near(piece, into: c, x: (x0 + x1) / 2, baseline: baseline,
                 body: body, detail: hole, breeze: 0)
        }
    }

    /// A near piece: one landmark standing on `baseline`, centred on `x`.
    static func near(_ piece: Backdrop, into c: PixelCanvas, x: Double, baseline: Double,
                     body: Palette.RGBA8, detail: Palette.RGBA8, breeze: Double) {
        switch piece {
        case .house:
            c.rect(x - 7, baseline - 9, 14, 9, body)
            for j in 0..<7 {                                        // a pitched roof
                c.rect(x - Double(j) - 1, baseline - 15 + Double(j), Double(j) * 2 + 2, 1, detail)
            }
            c.rect(x - 2, baseline - 5, 3, 5, detail)               // the door

        case .waterTower:
            c.rect(x - 6, baseline - 17, 12, 7, body)               // the tank
            c.rect(x - 6, baseline - 18, 12, 1, detail)
            c.rect(x - 5, baseline - 10, 2, 10, body)               // its legs
            c.rect(x + 3, baseline - 10, 2, 10, body)
            c.rect(x - 5, baseline - 6, 10, 1, body)                // and the brace

        case .smokestacks:
            for (dx, h) in [(-6.0, 18.0), (0.0, 23.0), (6.0, 15.0)] {
                c.rect(x + dx, baseline - h, 3, h, body)
                c.rect(x + dx, baseline - h, 3, 2, detail)
            }

        case .bridge:
            c.rect(x - 21, baseline - 7, 42, 2, body)               // the deck
            c.rect(x - 12, baseline - 19, 2, 13, body)              // its towers
            c.rect(x + 10, baseline - 19, 2, 13, body)
            c.rect(x - 12, baseline - 7, 2, 7, detail)              // and their piers
            c.rect(x + 10, baseline - 7, 2, 7, detail)
            var t = -11.0                                           // the cable, sagging
            while t <= 11 {
                let sag = 7 * (1 - (t / 11) * (t / 11))
                c.px(x + t, baseline - 19 + sag, detail)
                t += 1
            }

        case .palms:
            for (dx, h, lean) in [(-9.0, 14.0, 2.0), (1.0, 19.0, -2.0), (10.0, 11.0, 1.0)] {
                let tx = x + dx + lean, ty = baseline - h
                c.line(x + dx, baseline, tx, ty, body)
                for (fx, fy) in [(-7.0, 2.0), (-5.0, -2.0), (0.0, -3.0), (5.0, -2.0), (7.0, 2.0)] {
                    c.line(tx, ty, tx + fx, ty + fy, detail)
                }
            }

        case .ferrisWheel:
            let r = 9.0, cy = baseline - r - 5
            c.ring(x, cy, r, body, gap: 1.2)
            for i in 0..<8 {
                let a = Double(i) * .pi / 4
                c.line(x, cy, x + cos(a) * r, cy + sin(a) * r, detail)
                c.rect(x + cos(a) * r - 1, cy + sin(a) * r - 1, 2, 2, body)   // its cars
            }
            c.line(x - 7, baseline, x, cy, body)
            c.line(x + 7, baseline, x, cy, body)

        case .lightPoles:
            for dx in [-12.0, 12.0] {
                c.rect(x + dx, baseline - 19, 2, 19, body)
                c.rect(x + dx - 4, baseline - 23, 10, 4, detail)
            }

        case .pennants:
            let y0 = baseline - 15.0
            c.line(x - 24, y0, x + 24, y0 + 2, body)
            var t = -22.0
            while t <= 22 {
                let ly = y0 + (t + 24) / 48 * 2
                for j in 0..<4 { c.rect(x + t, ly + Double(j) + 1, Double(4 - j), 1, detail) }
                t += 8
            }

        default:
            // A far piece asked to be a landmark: a modest block of it, and no more.
            far(piece, into: c, x0: x - 26, x1: x + 26, baseline: baseline, rise: 12,
                body: body, hole: detail, seed: 0x5DEE_CAFE)
        }
    }

    /// One seeded stream per park and purpose. Nothing here is ever `random()`: park 87's
    /// backdrop is park 87's backdrop on every phone (§17).
    private static func seed(_ scenery: Scenery, tag: UInt64) -> UInt64 {
        UInt64(scenery.parkNumber) &* 0x7F4A_7C15_9E37_79B9 &+ tag &* 0x9E37_79B9_7F4A_7C15
    }
}
