import Foundation
import DerbyCore

/// The clock everything in the sky moves on: the machine's own `secondsPlayed`, never `Date()`
/// (DESIGN.md §17). Clouds, fireworks, stars, birds, flags, the crowd and the lights' chase all
/// read it, so they step together and a replay (#4) reproduces the lot.
enum SceneryClock {
    /// `DerbyMachine.skyClock`: `secondsPlayed` plus whatever `-skyclock` has wound it forward
    /// by. The offset moved onto the machine with #5 — a rare event is judged against the sky in
    /// Core and drawn from the sky here, and the two have to be the same sky.
    static func now(_ machine: DerbyMachine) -> Double { machine.skyClock }

    #if DEBUG
    /// `-skyclock <seconds>`, DEBUG only: winds the sky's clock forward by a fixed amount so a
    /// screenshot can reach a flock of birds without waiting up to forty seconds for one. It
    /// moves nothing but scenery — no career state is faked, so unlike `-park` and `-streak` it
    /// does not have to imply `-nosave`.
    static let offset: Double = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-skyclock"), i + 1 < args.count,
              let seconds = Double(args[i + 1]) else { return 0 }
        return max(0, seconds)
    }()
    #else
    static let offset = 0.0
    #endif
}

/// The sky's life, drawn: stars and a moon, stadium lights with their dithered halos, and birds.
/// `DerbyCore.SkyLife` does all the maths — every position and every on/off is `f(seed, t)` —
/// and this only turns the answers into palette pixels (DESIGN.md §17 "Sky").
enum SkyArt {

    /// The two views look in different directions, so each has its own flocks (§17). The seeds
    /// moved to `DerbyCore.SkyView` with #5: a bird strike is *detected* in Core and only drawn
    /// here, so the number that says which birds are up has to be somewhere both can ask. The
    /// arithmetic is exactly what it was, so no park's flock moved.
    typealias View = SkyView

    static func birdSeed(_ scenery: Scenery, _ view: View) -> UInt64 {
        view.birdSeed(parkNumber: scenery.parkNumber)
    }

    // MARK: - One tower, placed

    /// Where a tower has ended up on screen this frame, worked out once and used twice: the
    /// halos go in before the clouds and the towers themselves long after (§17's draw order).
    struct TowerFrame {
        let x: Double
        /// The top of the lamp bank, and its size.
        let bankY: Double
        let bankW: Double
        let bankH: Double
        /// Where the pole's foot is — under the wall or the stands, which cover it.
        let footY: Double
        let columns: Int
        let rows: Int
        /// Whether this bank is at full blaze this instant. Steady between pitches; chasing
        /// bank to bank while the cheer plays.
        let lit: Bool
        /// Whether a no-doubter has put this bank out (#5). Not the same as dark in the chase:
        /// a bank in the chase keeps its glow's innermost ring and comes back a fifth of a
        /// second later, and this one does neither until the park changes.
        var isOut = false

        var haloX: Double { x }
        var haloY: Double { bankY + bankH / 2 }
    }

    private static func bankSize(columns: Int, rows: Int, layout: BackdropLayout) -> (w: Double, h: Double) {
        let pitch = layout.lampSize + layout.lampGap
        return (Double(columns) * pitch - layout.lampGap + 2,
                Double(rows) * pitch - layout.lampGap + 2)
    }

    /// The side view's towers: real places in the park, in feet, so the close camera simply sees
    /// them bigger and the tallest of them run out of the top of the frame (§17).
    /// `allTowers`, not `lightTowers`: the short standard over the wall stands in the park like
    /// any other and chases with them, and it is the only one a ball can reach (#5).
    static func sideTowerFrames(park: Park, scenery: Scenery, scale: Double, originX: Double,
                                ground: Double, time: Double, chasing: Bool,
                                isOut: (Int) -> Bool = { _ in false },
                                layout: BackdropLayout = .standard) -> [TowerFrame] {
        scenery.allTowers.enumerated().map { i, tower in
            let size = bankSize(columns: tower.bankColumns, rows: tower.bankRows, layout: layout)
            let x = originX + (park.wallDistanceFeet + tower.feetBehindWall) * scale
            return TowerFrame(x: x.rounded(),
                              bankY: (ground - tower.heightFeet * scale).rounded(),
                              bankW: size.w, bankH: size.h, footY: ground,
                              columns: tower.bankColumns, rows: tower.bankRows,
                              lit: SkyLife.bankIsLit(i, at: time, chasing: chasing),
                              isOut: isOut(i))
        }
    }

    /// The at-bat view's towers flank the scoreboard above the wall, well clear of the zone
    /// (§17). They are not the side view's towers seen from another angle — you are looking the
    /// other way down the park — so they take fixed slots rather than the seeded depths, and only
    /// the count and the banks' own shapes carry over.
    static func atBatTowerFrames(scenery: Scenery, xOffset: Double, time: Double, chasing: Bool,
                                 layout: BackdropLayout = .standard) -> [TowerFrame] {
        scenery.lightTowers.prefix(layout.atBatTowerSlots.count).enumerated().map { i, tower in
            let size = bankSize(columns: tower.bankColumns, rows: tower.bankRows, layout: layout)
            return TowerFrame(x: (xOffset + layout.atBatTowerSlots[i]).rounded(),
                              bankY: layout.atBatTowerFootY - layout.atBatTowerHeight,
                              bankW: size.w, bankH: size.h, footY: layout.atBatTowerFootY,
                              columns: tower.bankColumns, rows: tower.bankRows,
                              lit: SkyLife.bankIsLit(i, at: time, chasing: chasing))
        }
    }

    // MARK: - The sky layer (before the clouds)

    /// Stars, the moon and the lights' halos, in that order (§17's draw order). Drawn while the
    /// lamps are on and not otherwise — by day there is nothing here to draw.
    ///
    /// The `phase` decides how much of it: `twilight` shows the first `SceneryRules.twilightStars`
    /// of the forty and no moon at all, so the sky fills in as the light goes rather than arriving
    /// all at once (DESIGN.md §20 "The phases"). Which stars those are is the park's own seeded
    /// order, so the twenty-two that come out at dusk are the same twenty-two every evening.
    ///
    /// Stars are skipped inside a halo: the lights wash them out, which is also the one way a
    /// `chalk` star and a `chalk` halo can share a sky without the star simply disappearing
    /// into it.
    static func nightSky(into c: PixelCanvas, scenery: Scenery, towers: [TowerFrame],
                         time: Double, width: Double, phase: DayPhase,
                         layout: BackdropLayout = .standard,
                         sceneryRules: SceneryRules = .standard) {
        let showing = phase == .twilight
            ? min(scenery.stars.count, max(0, sceneryRules.twilightStars))
            : scenery.stars.count
        for star in scenery.stars.prefix(showing) {
            guard SkyLife.starIsLit(star, at: time) else { continue }
            let x = (star.xFraction * width).rounded()
            guard !isInsideAHalo(x: x, y: star.y, towers: towers, layout: layout) else { continue }
            c.px(x, star.y, Palette.chalk)
        }

        if phase == .night, let moon = scenery.moon {
            let cx = (moon.xFraction * width).rounded()
            c.disc(cx, moon.y, moon.radius, Palette.chalk)
            // The bite is the night sky itself, taken out of one side. Both night sky bands are
            // within a hair of each other (`#221144` and `#222244`), so the top one does for a
            // moon that strays across the boundary between them.
            c.disc(cx + Double(moon.biteDirection) * moon.radius * layout.moonBiteOffset,
                   moon.y - moon.radius * 0.2,
                   moon.radius * layout.moonBiteRadius, Palette.night)
        }

        for tower in towers where !tower.isOut {
            halo(into: c, tower: tower,
                 rings: tower.lit ? layout.haloRings.count : layout.haloRingsWhenDark,
                 layout: layout)
        }
    }

    /// The half-axes of a bank's glow: the bank itself, plus the spread.
    private static func haloAxes(_ tower: TowerFrame, _ layout: BackdropLayout) -> (rx: Double, ry: Double) {
        (tower.bankW / 2 + layout.haloSpreadX, tower.bankH / 2 + layout.haloSpreadY)
    }

    /// How far out a point is, 0 at the middle of the bank and 1 at the edge of the glow.
    /// Squashed below the bank, where the bloom is weaker.
    private static func haloDistance(x: Double, y: Double, tower: TowerFrame,
                                     layout: BackdropLayout) -> Double {
        let (rx, ry) = haloAxes(tower, layout)
        let dy = y - tower.haloY
        let nx = (x - tower.haloX) / rx
        let ny = dy / (dy > 0 ? ry * layout.haloBelowShare : ry)
        return (nx * nx + ny * ny).squareRoot()
    }

    private static func isInsideAHalo(x: Double, y: Double, towers: [TowerFrame],
                                      layout: BackdropLayout) -> Bool {
        towers.contains { haloDistance(x: x, y: y, tower: $0, layout: layout) <= 1 }
    }

    /// The glow. With no alpha a light cannot fade into the sky, so it dithers into it: a
    /// checkerboard of `chalk` in rings that thin outward, which is the one place the palette
    /// rules allow a dither at all ("dither only in the sky", docs/palette.md).
    private static func halo(into c: PixelCanvas, tower: TowerFrame, rings: Int,
                             layout: BackdropLayout) {
        let (rx, ry) = haloAxes(tower, layout)
        let xi = Int(rx.rounded()), yi = Int(ry.rounded())
        guard xi > 0, yi > 0, rings > 0 else { return }
        let cx = Int(tower.haloX.rounded()), cy = Int(tower.haloY.rounded())
        for dy in -yi...yi {
            for dx in -xi...xi {
                let x0 = tower.haloX + Double(dx), y0 = tower.haloY + Double(dy)
                let d = haloDistance(x: x0, y: y0, tower: tower, layout: layout)
                guard d <= 1 else { continue }
                let ring = layout.haloRings.firstIndex { d <= $0 } ?? layout.haloRings.count - 1
                guard ring < rings else { continue }
                let x = cx + dx, y = cy + dy
                guard haloPixel(x, y, ring: ring) else { continue }
                c.px(Double(x), Double(y), Palette.chalk)
            }
        }
    }

    /// Ring `k`'s share of the pixels: a half, then a quarter, an eighth. Bitwise so that a ring
    /// hanging off the left edge of the canvas thins the same way one in the middle of it does.
    private static func haloPixel(_ x: Int, _ y: Int, ring: Int) -> Bool {
        switch ring {
        case 0: return (x &+ y) & 1 == 0
        case 1: return x & 1 == 0 && y & 1 == 0
        default: return (x &+ y) & 1 == 0 && x & 3 == 0
        }
    }

    // MARK: - The towers themselves (after the birds, before the field)

    /// An `ink` lattice pole carrying a bank of `chalk` lamps with `score` centres (§17). A bank
    /// that is dark in the chase keeps its lamps and loses its centres, so the chase reads as
    /// light running along the roof rather than as the towers switching off.
    ///
    /// `poleColour` is the view's, not the spec's. §17 asks for an `ink` lattice, but a night
    /// sky's two upper bands *are* `night` and `ink` — the same trap the side view's far pieces
    /// fell into in step 1 — so the colour has to be whichever of the two reads against the band
    /// the pole actually stands in. The at-bat pole stands entirely in the `#446688` horizon
    /// band and keeps `ink`; the side view's climbs through `night` and `ink` and is drawn
    /// lighter than the sky instead.
    static func towers(into c: PixelCanvas, frames: [TowerFrame], width: Double,
                       poleColour: Palette.RGBA8, layout: BackdropLayout = .standard) {
        for tower in frames {
            guard tower.x > -tower.bankW, tower.x < width + tower.bankW else { continue }
            lattice(into: c, tower: tower, colour: poleColour, layout: layout)
            bank(into: c, tower: tower, layout: layout)
        }
    }

    private static func lattice(into c: PixelCanvas, tower: TowerFrame, colour: Palette.RGBA8,
                                layout: BackdropLayout) {
        let top = tower.bankY + tower.bankH
        let foot = tower.footY
        guard foot > top else { return }
        let halfTop = layout.towerTopWidth / 2, halfFoot = layout.towerFootWidth / 2
        let height = foot - top

        // Two legs splaying out to the foot, and rungs across them: a lattice at this size is
        // three lines and the gaps between them, not a truss.
        c.line(tower.x - halfTop, top, tower.x - halfFoot, foot, colour, thickness: 1)
        c.line(tower.x + halfTop, top, tower.x + halfFoot, foot, colour, thickness: 1)
        c.rect(tower.x - halfTop, top, layout.towerTopWidth, 1, colour)

        var y = top + layout.towerRungPitch
        while y < foot {
            let t = (y - top) / height
            let half = halfTop + (halfFoot - halfTop) * t
            c.rect(tower.x - half, y.rounded(), half * 2, 1, colour)
            // One diagonal per bay, alternating, which is what makes it read as a lattice.
            let next = min(foot, y + layout.towerRungPitch)
            let halfNext = halfTop + (halfFoot - halfTop) * ((next - top) / height)
            let goesRight = Int((y - top) / layout.towerRungPitch) & 1 == 0
            c.line(tower.x + (goesRight ? -half : half), y,
                   tower.x + (goesRight ? halfNext : -halfNext), next, colour)
            y += layout.towerRungPitch
        }
    }

    private static func bank(into c: PixelCanvas, tower: TowerFrame, layout: BackdropLayout) {
        let left = tower.x - tower.bankW / 2
        c.rect(left, tower.bankY, tower.bankW, tower.bankH, Palette.ink)
        let pitch = layout.lampSize + layout.lampGap
        for row in 0..<tower.rows {
            for col in 0..<tower.columns {
                let lx = left + 1 + Double(col) * pitch
                let ly = tower.bankY + 1 + Double(row) * pitch
                // A bank a ball has put out keeps its lamps and loses their light: dimmer than
                // `chalk` and darker than the glass it used to be, so the tower still reads as a
                // tower with its lights off rather than as a hole in the sky (#5).
                c.rect(lx, ly, layout.lampSize, layout.lampSize,
                       tower.isOut ? Palette.nightSky3 : Palette.chalk)
                if tower.lit, !tower.isOut, layout.lampSize >= 3 {
                    c.px(lx + 1, ly + 1, Palette.score)
                }
            }
        }
    }

    // MARK: - Birds

    /// A flock crossing high, every 20–40 s (§17). Three `ink` pixels in two flap frames — but
    /// `ink` is all but invisible on a night sky that is itself `ink`, the same trap the side
    /// view's far pieces fell into, so after dark a bird is drawn lighter than the sky instead.
    ///
    /// `skipping` is the one bird a ball has already gone through (#5). There is no bird state
    /// anywhere to mark, so the machine names it and the sky simply leaves it out for the rest
    /// of the crossing.
    static func birds(into c: PixelCanvas, scenery: Scenery, view: View, time: Double,
                      width: Double, night: Bool, skipping: (slot: Int, index: Int)? = nil) {
        let colour = night ? Palette.nightSky3 : Palette.ink
        for bird in SkyLife.birds(seed: birdSeed(scenery, view), at: time,
                                  breeze: scenery.breezePixelsPerSecond) {
            if let skipping, bird.slot == skipping.slot, bird.index == skipping.index { continue }
            let x = (bird.x * width).rounded()
            guard x >= -2, x <= width + 2 else { continue }
            let tip = bird.wingsUp ? -1.0 : 1.0
            c.px(x, bird.y, colour)
            c.px(x - 1, bird.y + tip, colour)
            c.px(x + 1, bird.y + tip, colour)
        }
    }

    // MARK: - Things a long career arrives at (#5)

    /// The blimp, past park 100. An envelope, a fin, a gondola and a tail beacon that is the
    /// only thing about it that moves in place — a thing that does not flap still gets two
    /// frames and no more (§9). Drawn lighter than the sky after dark, the way the birds are.
    static func blimp(into c: PixelCanvas, scenery: Scenery, view: View, time: Double,
                      width: Double, night: Bool, layout: BackdropLayout = .standard) {
        guard scenery.hasBlimp,
              let b = SkyLife.blimp(seed: view.blimpSeed(parkNumber: scenery.parkNumber),
                                    at: time, breeze: scenery.breezePixelsPerSecond)
        else { return }
        let cx = (b.x * width).rounded(), cy = b.y.rounded()
        guard cx > -layout.blimpWidth, cx < width + layout.blimpWidth else { return }
        let body = night ? Palette.nightSky3 : Palette.chalk
        let detail = night ? Palette.ink : Palette.shade

        // An ellipse, row by row: the one shape a blimp has.
        let halfW = layout.blimpWidth / 2, halfH = layout.blimpHeight / 2
        var j = -halfH
        while j <= halfH {
            let ny = j / halfH
            let half = (halfW * (1 - ny * ny).squareRoot()).rounded()
            if half >= 1 { c.rect(cx - half, cy + j, half * 2 + 1, 1, body) }
            j += 1
        }
        // The tail fin, at the back, and the gondola slung under the middle.
        let back = b.facingRight ? -1.0 : 1.0
        let tail = cx + back * (halfW - 1)
        c.rect(tail + min(0, back * layout.blimpFin), cy - halfH - 2, layout.blimpFin, 2, body)
        c.rect(cx - 2, cy + halfH, 4, 2, detail)
        if b.beaconOn { c.px(tail + back, cy - halfH - 2, Palette.cap) }
    }

    /// Searchlights, past park 500: two beams rising from behind the stands and sweeping. With
    /// no alpha a beam cannot be translucent, so it dithers into the sky the way a lamp's halo
    /// does — which is the one place the palette rules allow a dither at all.
    static func searchlights(into c: PixelCanvas, scenery: Scenery, time: Double,
                             width: Double, footY: Double, layout: BackdropLayout = .standard) {
        guard scenery.hasSearchlights else { return }
        for beam in SkyLife.searchlights(at: time) {
            let fx = (beam.xFraction * width).rounded()
            let a = beam.angleDegrees * .pi / 180
            let dx = sin(a), dy = -cos(a)
            var t = layout.searchlightStartPixels
            while t < beam.lengthPixels {
                let x = fx + dx * t, y = footY + dy * t
                guard y > 0 else { break }
                // The beam widens and thins as it goes, so it reads as light and not as a stick.
                let half = (layout.searchlightSpread * t).rounded()
                var k = -half
                while k <= half {
                    let px = (x + k).rounded(), py = y.rounded()
                    let far = abs(k) > half / 2
                    if (Int(px) &+ Int(py)) & 1 == 0, !far || (Int(px) & 3 == 0) {
                        c.px(px, py, Palette.chalk)
                    }
                    k += 1
                }
                t += 1
            }
        }
    }

    /// The comet, past park 1,000: a head and a tail across the very top of the sky, crossing
    /// once in five minutes. It is always there, which is the point of it.
    static func comet(into c: PixelCanvas, scenery: Scenery, view: View, time: Double,
                      width: Double) {
        guard scenery.hasComet else { return }
        let k = SkyLife.comet(seed: view.cometSeed(parkNumber: scenery.parkNumber), at: time)
        let x = (k.x * width).rounded(), y = k.y.rounded()
        guard x > -k.tailPixels - 2, x < width + k.tailPixels + 2 else { return }
        c.rect(x, y, 2, 2, Palette.chalk)
        let back = k.movingRight ? -1.0 : 1.0
        var t = 2.0
        while t <= k.tailPixels {
            // The tail thins to a dotted line rather than fading: no alpha anywhere (§17). It
            // climbs a pixel every two rather than every four, which is what stops a comet
            // reading as a dash of stray text where it crosses a readout.
            if t < k.tailPixels / 2 || Int(t) % 2 == 0 {
                c.px(x + back * t, y - (t / 2).rounded(), Palette.chalk)
            }
            t += 1
        }
    }

    // MARK: - The bursts (#5)

    /// One rare thing's burst, wherever it happened. `DerbyCore.RareEvents` does all the maths —
    /// every speck is `f(seed, t)` the way a firework is — and this only turns a role into a
    /// palette pixel.
    static func burst(into c: PixelCanvas, kind: ParkEventKind, seed: UInt64, since: Double,
                      at x: Double, y: Double, rules: RareEventRules = .standard) {
        for speck in RareEvents.burst(kind, seed: seed, since: since, rules: rules)
        where speck.visible {
            let colour: Palette.RGBA8
            switch speck.colour {
            case .chalk: colour = Palette.chalk
            case .score: colour = Palette.score
            case .ink: colour = Palette.ink
            case .cap: colour = Palette.cap
            }
            let px = (x + speck.dx).rounded(), py = (y + speck.dy).rounded()
            if speck.size >= 2 { c.rect(px, py, 2, 2, colour) } else { c.px(px, py, colour) }
        }
    }
}
