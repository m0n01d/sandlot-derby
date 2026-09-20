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

    /// Side view: how many steps the bleacher profile climbs in.
    var standsSteps = 6
    /// Side view: the far piece rises this many pixels above the top of the stands.
    var sideFarRisePixels = 13.0
    /// Side view: the foul pole stands this many feet above the top of the wall.
    var foulPoleFeet = 30.0
    /// Side view: one crowd speckle per this many square pixels of seating, and the odds of
    /// each being a face, a shirt or a cap. Sparse on purpose — packed tight it stopped being
    /// a crowd and became television static.
    var crowdPixelsPerHead = 13.0
    var crowdSkinShare = 0.45
    var crowdChalkShare = 0.35
    /// Side view: a flag's pole and its pennant.
    var flagPoleHeight = 9.0
    var flagPennant = (w: 5.0, h: 3.0)
    /// Side view, Single-A only: the chain-link mesh above the wall, and its posts, in feet.
    var chainLinkPitchPixels = 3.0
    var fencePostSpacingFeet = 20.0

    /// The ball vanishes with a `chalk` pop this big, for this long (seconds), in two frames
    /// (§17: no alpha — things blink, shrink or stop).
    var popRadius = 3.0
    var popSeconds = 0.45

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

    init(parkNumber: Int, width: Int, camera: Camera, scale: Double = 0, originX: Double = 0) {
        self.parkNumber = parkNumber
        self.width = width
        self.camera = camera
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

    init(width: Int, height: Int) {
        canvas = PixelCanvas(width: width, height: height)
        canvas.fill(Palette.clear)
    }

    func clear() {
        canvas.fill(Palette.clear)
        firstRow = 0; lastRow = -1; firstCol = 0; lastCol = -1
    }

    /// Works out the drawn bounds. Called once, after the art is in.
    func seal() {
        var top = Int.max, bottom = -1, left = Int.max, right = -1
        for y in 0..<canvas.height {
            let row = canvas.buffer + y * canvas.width
            for x in 0..<canvas.width where row[x] != 0 {
                if y < top { top = y }
                if y > bottom { bottom = y }
                if x < left { left = x }
                if x > right { right = x }
            }
        }
        firstRow = top; lastRow = bottom; firstCol = left; lastCol = right
    }

    /// Copies every painted pixel onto `target`, `dy` rows down.
    func blit(onto target: PixelCanvas, dy: Int = 0) {
        guard lastRow >= firstRow, lastCol >= firstCol else { return }
        guard target.width == canvas.width else { return }
        for y in firstRow...lastRow {
            let ty = y + dy
            guard ty >= 0, ty < target.height else { continue }
            let src = canvas.buffer + y * canvas.width
            let dst = target.buffer + ty * target.width
            for x in firstCol...lastCol where src[x] != 0 { dst[x] = src[x] }
        }
    }
}

/// Two layers per camera — what sits behind the field and what sits in front of the ball — held
/// until the park, the canvas or the framing changes (DESIGN.md §17, "a backdrop cache").
final class BackdropCache {
    private var key: BackdropKey?
    private var behind: BackdropLayer?
    private var front: BackdropLayer?

    /// The layers for this key, drawing them first if anything moved. `draw` runs rarely; the
    /// rest of the time this is two pointer returns.
    func layers(for key: BackdropKey, height: Int,
                draw: (_ behind: BackdropLayer, _ front: BackdropLayer) -> Void)
        -> (behind: BackdropLayer, front: BackdropLayer) {
        if let behind, let front, self.key == key { return (behind, front) }
        let b = behind?.canvas.width == key.width ? behind! : BackdropLayer(width: key.width, height: height)
        let f = front?.canvas.width == key.width ? front! : BackdropLayer(width: key.width, height: height)
        b.clear(); f.clear()
        draw(b, f)
        b.seal(); f.seal()
        self.key = key; self.behind = b; self.front = f
        return (b, f)
    }
}

/// The backdrop art. Static functions over a `PixelCanvas`, so they can be pointed at a cached
/// layer or at the frame itself. Colours are borrowed by role, one palette line, whole pixels.
enum BackdropArt {

    // MARK: - The at-bat horizon (DESIGN.md §17)

    /// A low band above the wall: the park's far piece as a `sky2` silhouette on the `sky3`
    /// band, one near landmark in `wall` and `shade` beside the scoreboard, and two small flags
    /// on the scoreboard itself. Night turns every silhouette to `ink`.
    ///
    /// Everything here is above y = 96. The strike zone starts at y = 136, so nothing new is
    /// drawn anywhere near it (§17's motion budget).
    static func atBatHorizon(into c: PixelCanvas, park: Park, scenery: Scenery,
                             width: Double, xOffset: Double, layout: BackdropLayout = .standard) {
        let night = park.isNight
        let baseline = layout.atBatHorizonBottom
        let rise = baseline - layout.atBatHorizonTop
        let band = night ? Palette.nightSky3 : Palette.sky3

        far(scenery.far, into: c, x0: 0, x1: width, baseline: baseline, rise: rise,
            body: night ? Palette.ink : Palette.sky2, hole: band, seed: seed(scenery, tag: 0x1))

        var g = SplitMix64(seed: seed(scenery, tag: 0x2))
        let onTheRight = Bool.random(using: &g)
        near(scenery.near, into: c,
             x: xOffset + (onTheRight ? layout.atBatNearRightX : layout.atBatNearLeftX),
             baseline: baseline,
             body: night ? Palette.ink : Palette.wall,
             detail: night ? Palette.ink : Palette.shade,
             breeze: scenery.breezePixelsPerSecond)

        // Two on the scoreboard, pointing with the breeze. Still until step 5.
        let pointRight = scenery.breezePixelsPerSecond >= 0
        for dx in layout.scoreboardFlagOffsets {
            let x = (xOffset + 128 + dx).rounded()
            let top = 80 - layout.scoreboardFlagPoleHeight
            c.rect(x, top, 1, layout.scoreboardFlagPoleHeight, Palette.chalk)
            c.rect(pointRight ? x + 1 : x - 4, top, 4, 3, Palette.cap)
        }
    }

    // MARK: - The side view (DESIGN.md §17)

    /// How high the stands stand, in feet, at `feet` from the plate: the stepped bleacher
    /// profile, flat at its top once past the back row. Zero where nothing is built, which is
    /// Single-A — the one park where you watch the ball all the way down.
    ///
    /// This is the same number the drawing uses and the same one that decides where a home run
    /// disappears, so the pop is always exactly where the ball went in.
    static func standsHeightFeet(at feet: Double, park: Park, scenery: Scenery,
                                 layout: BackdropLayout = .standard) -> Double {
        guard scenery.stands.swallowsTheBall else { return 0 }
        let back = feet - park.wallDistanceFeet
        guard back >= 0 else { return 0 }
        guard back < scenery.standsDepthFeet else { return scenery.standsTopFeet }
        let steps = Double(layout.standsSteps)
        let i = (back / scenery.standsDepthFeet * steps).rounded(.down)
        return park.wallHeightFeet
            + (scenery.standsTopFeet - park.wallHeightFeet) * (i + 1) / steps
    }

    /// Everything behind the wall in the side view, into the two cached layers. `behind` is
    /// drawn before the field, `front` after the ball — which is what makes a home run drop
    /// into the crowd and vanish.
    ///
    /// Drawn with the ground at `BackdropLayout.canonicalGround`; the scene copies it down by
    /// however far the close camera has lifted.
    static func sideBackdrop(behind: PixelCanvas, front: PixelCanvas,
                             park: Park, scenery: Scenery,
                             scale: Double, originX: Double, width: Double,
                             layout: BackdropLayout = .standard) {
        let ground = BackdropLayout.canonicalGround
        let night = park.isNight
        func x(_ feet: Double) -> Double { originX + feet * scale }
        func y(_ feet: Double) -> Double { ground - feet * scale }

        let wallX = x(park.wallDistanceFeet)
        let wallTopY = y(park.wallHeightFeet)
        // Everything behind the wall reads as one near mass at this range, so it takes §17's
        // near colours rather than the horizon's: `wall` and `shade`.
        //
        // Night turns them round. This backdrop sits in the side view's `sky2` band, and at
        // night that band *is* `ink` — an `ink` silhouette there is invisible, which is what
        // the first night frames showed. So after dark the distant things are lighter than the
        // sky behind them, the way a city's glow really does pick them out.
        let body = night ? Palette.nightSky3 : Palette.wall
        let detail = night ? Palette.ink : Palette.shade
        let hole = night ? Palette.ink : Palette.sky2

        let standsTopY: Double
        if scenery.stands.swallowsTheBall {
            standsTopY = y(scenery.standsTopFeet)
            drawStands(into: front, park: park, scenery: scenery,
                       scale: scale, originX: originX, width: width, layout: layout)
        } else {
            // Single-A: a chain-link fence over the wall and nothing to sit in.
            standsTopY = wallTopY
            chainLink(into: front, park: park, scenery: scenery,
                      scale: scale, wallX: wallX, wallTopY: wallTopY, width: width, layout: layout)
        }

        // The park's own skyline, sitting on whatever the last thing built was. For Single-A
        // this is §17's "trees": its far piece is a treeline.
        far(scenery.far, into: behind, x0: wallX, x1: width,
            baseline: standsTopY + 1, rise: layout.sideFarRisePixels,
            body: body, hole: hole, seed: seed(scenery, tag: 0x3))

        // One landmark over the grandstand, the way a water tower or a wheel sits over a real one.
        if width - wallX > 60 {
            near(scenery.near, into: behind, x: wallX + (width - wallX) * 0.62,
                 baseline: standsTopY + 1, body: body, detail: detail,
                 breeze: scenery.breezePixelsPerSecond)
        }

        // The foul pole: the one thing on the wall that is always `score`.
        let poleHeight = layout.foulPoleFeet * scale
        let poleWidth = max(1, (scale * 1.5).rounded())
        front.rect(wallX, wallTopY - poleHeight, poleWidth, poleHeight, Palette.score)
    }

    /// The stepped bleacher profile, its crowd, and its flags.
    private static func drawStands(into c: PixelCanvas, park: Park, scenery: Scenery,
                                   scale: Double, originX: Double, width: Double,
                                   layout: BackdropLayout) {
        let ground = BackdropLayout.canonicalGround
        func x(_ feet: Double) -> Double { originX + feet * scale }
        func y(_ feet: Double) -> Double { ground - feet * scale }
        let wallTopY = y(park.wallHeightFeet)
        let wallX = x(park.wallDistanceFeet)
        let steps = layout.standsSteps

        // The wall's own face belongs in this layer too, drawn exactly as the field already
        // draws it. Everything past the wall is behind it, and without this a ball that had
        // dropped below the wall's top line came back into view over the wall it had just
        // cleared — it vanished into the crowd and then fell out of it again.
        c.rect(wallX, wallTopY, width - wallX, ground - wallTopY, Palette.wall)
        c.rect(wallX, wallTopY, width - wallX, 1, Palette.chalk)
        c.rect(wallX, wallTopY - 1, 2, ground - wallTopY + 1, Palette.chalk)

        // The stepped mass sits on top of it.
        for i in 0..<steps {
            let f0 = park.wallDistanceFeet + scenery.standsDepthFeet * Double(i) / Double(steps)
            let f1 = park.wallDistanceFeet + scenery.standsDepthFeet * Double(i + 1) / Double(steps)
            let h = park.wallHeightFeet
                + (scenery.standsTopFeet - park.wallHeightFeet) * Double(i + 1) / Double(steps)
            let x0 = x(f0), x1 = x(f1), top = y(h)
            guard x1 > 0, x0 < width, top < wallTopY else { continue }
            // `ink` for the mass and `wall` for each deck's lip (§17). The mass has to be the
            // darker of the two: in `wall` the stands and the outfield wall were one green
            // shape, and the wall stopped reading as a wall at all.
            c.rect(x0, top, max(1, x1 - x0), wallTopY - top, Palette.ink)
            c.rect(x0, top, max(1, x1 - x0), 1, Palette.wall)
        }
        // Behind the back row the profile is flat, all the way out of frame: there is no green
        // band behind an outfield wall, which is the whole point of §17's stands.
        let backX = x(park.wallDistanceFeet + scenery.standsDepthFeet)
        let topY = y(scenery.standsTopFeet)
        if backX < width, topY < wallTopY {
            c.rect(backX, topY, width - backX, wallTopY - topY, Palette.ink)
            c.rect(backX, topY, width - backX, 1, Palette.wall)
        }

        crowd(into: c, park: park, scenery: scenery, scale: scale, originX: originX,
              width: width, wallTopY: wallTopY, layout: layout)
        flags(into: c, scenery: scenery, x0: x(park.wallDistanceFeet), x1: width,
              top: topY, layout: layout)
    }

    /// A `chalk` / `skin` / `cap` speckle over the seating. Seeded by the park, so the same
    /// crowd turns out every time you come back. It sits still until the cheer bounces it (step 5).
    private static func crowd(into c: PixelCanvas, park: Park, scenery: Scenery,
                              scale: Double, originX: Double, width: Double,
                              wallTopY: Double, layout: BackdropLayout) {
        let ground = BackdropLayout.canonicalGround
        let left = max(0, originX + park.wallDistanceFeet * scale)
        guard width - left > 2, scale > 0 else { return }
        let topY = ground - scenery.standsTopFeet * scale
        let area = (width - left) * max(0, wallTopY - topY)
        let heads = Int(area / layout.crowdPixelsPerHead)
        guard heads > 0 else { return }

        var g = SplitMix64(seed: seed(scenery, tag: 0x4))
        for _ in 0..<heads {
            let px = Double.random(in: left..<width, using: &g)
            let feet = (px - originX) / scale
            let h = standsHeightFeet(at: feet, park: park, scenery: scenery, layout: layout)
            let seatTop = ground - h * scale
            guard wallTopY - seatTop > 2 else { continue }
            let py = Double.random(in: (seatTop + 1)..<wallTopY, using: &g)
            let roll = Double.random(in: 0..<1, using: &g)
            let colour: Palette.RGBA8
            if roll < layout.crowdSkinShare { colour = Palette.skin }
            else if roll < layout.crowdSkinShare + layout.crowdChalkShare { colour = Palette.chalk }
            else { colour = Palette.cap }
            c.px(px.rounded(.down), py.rounded(.down), colour)
        }
    }

    /// Flags along the top of the stands, pointing with the breeze. Two flutter frames are
    /// step 5; today they simply point.
    private static func flags(into c: PixelCanvas, scenery: Scenery,
                              x0: Double, x1: Double, top: Double, layout: BackdropLayout) {
        guard scenery.flags > 0, x1 > x0 else { return }
        let pointRight = scenery.breezePixelsPerSecond >= 0
        for i in 0..<scenery.flags {
            let t = (Double(i) + 1) / Double(scenery.flags + 1)
            let fx = (x0 + (x1 - x0) * t).rounded()
            let poleTop = top - layout.flagPoleHeight
            c.rect(fx, poleTop, 1, layout.flagPoleHeight, Palette.chalk)
            c.rect(pointRight ? fx + 1 : fx - layout.flagPennant.w,
                   poleTop, layout.flagPennant.w, layout.flagPennant.h, Palette.cap)
        }
    }

    /// Single-A's chain-link: a sparse `chalk` mesh over the wall with `ink` posts. It is drawn
    /// in front of the ball like the stands are, but you can see straight through it — which is
    /// the point, because this is the park where the ball is simply seen landing.
    private static func chainLink(into c: PixelCanvas, park: Park, scenery: Scenery,
                                  scale: Double, wallX: Double, wallTopY: Double,
                                  width: Double, layout: BackdropLayout) {
        let meshFeet = scenery.standsTopFeet - park.wallHeightFeet
        let top = wallTopY - meshFeet * scale
        guard wallTopY - top >= 2, width > wallX else { return }
        var y = top
        while y < wallTopY {
            var x = wallX + (Int(y - top) % 2 == 0 ? 0 : layout.chainLinkPitchPixels / 2)
            while x < width { c.px(x, y, Palette.chalk); x += layout.chainLinkPitchPixels }
            y += layout.chainLinkPitchPixels
        }
        c.rect(wallX, top, width - wallX, 1, Palette.chalk)          // the top rail
        var postFeet = park.wallDistanceFeet
        while originXPost(postFeet, wallX: wallX, park: park, scale: scale) < width {
            let px = originXPost(postFeet, wallX: wallX, park: park, scale: scale)
            c.rect(px, top, 1, wallTopY - top, Palette.ink)
            postFeet += layout.fencePostSpacingFeet
        }
    }

    private static func originXPost(_ feet: Double, wallX: Double, park: Park, scale: Double) -> Double {
        wallX + (feet - park.wallDistanceFeet) * scale
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
