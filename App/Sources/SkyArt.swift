import Foundation
import DerbyCore

/// The clock everything in the sky moves on: the machine's own `secondsPlayed`, never `Date()`
/// (DESIGN.md §17). Clouds, fireworks, stars, birds, flags, the crowd and the lights' chase all
/// read it, so they step together and a replay (#4) reproduces the lot.
enum SceneryClock {
    static func now(_ machine: DerbyMachine) -> Double {
        machine.tally[.secondsPlayed] + offset
    }

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

    /// The two views look in different directions, so each has its own flocks (§17).
    enum View {
        case atBat, side
        /// Two seeds off the same park, so the at-bat sky and the side one never share a bird.
        var birdTag: UInt64 { self == .atBat ? 0x17 : 0x51 }
    }

    static func birdSeed(_ scenery: Scenery, _ view: View) -> UInt64 {
        UInt64(scenery.parkNumber) &* 0x9E37_79B9_7F4A_7C15 &+ view.birdTag
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
    static func sideTowerFrames(park: Park, scenery: Scenery, scale: Double, originX: Double,
                                ground: Double, time: Double, chasing: Bool,
                                layout: BackdropLayout = .standard) -> [TowerFrame] {
        scenery.lightTowers.enumerated().map { i, tower in
            let size = bankSize(columns: tower.bankColumns, rows: tower.bankRows, layout: layout)
            let x = originX + (park.wallDistanceFeet + tower.feetBehindWall) * scale
            return TowerFrame(x: x.rounded(),
                              bankY: (ground - tower.heightFeet * scale).rounded(),
                              bankW: size.w, bankH: size.h, footY: ground,
                              columns: tower.bankColumns, rows: tower.bankRows,
                              lit: SkyLife.bankIsLit(i, at: time, chasing: chasing))
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

    /// Stars, the moon and the lights' halos, in that order (§17's draw order). Night only —
    /// by day there is nothing here to draw and nothing is drawn.
    ///
    /// Stars are skipped inside a halo: the lights wash them out, which is also the one way a
    /// `chalk` star and a `chalk` halo can share a sky without the star simply disappearing
    /// into it.
    static func nightSky(into c: PixelCanvas, scenery: Scenery, towers: [TowerFrame],
                         time: Double, width: Double, layout: BackdropLayout = .standard) {
        for star in scenery.stars {
            guard SkyLife.starIsLit(star, at: time) else { continue }
            let x = (star.xFraction * width).rounded()
            guard !isInsideAHalo(x: x, y: star.y, towers: towers, layout: layout) else { continue }
            c.px(x, star.y, Palette.chalk)
        }

        if let moon = scenery.moon {
            let cx = (moon.xFraction * width).rounded()
            c.disc(cx, moon.y, moon.radius, Palette.chalk)
            // The bite is the night sky itself, taken out of one side. Both night sky bands are
            // within a hair of each other (`#221144` and `#222244`), so the top one does for a
            // moon that strays across the boundary between them.
            c.disc(cx + Double(moon.biteDirection) * moon.radius * layout.moonBiteOffset,
                   moon.y - moon.radius * 0.2,
                   moon.radius * layout.moonBiteRadius, Palette.night)
        }

        for tower in towers {
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
                c.rect(lx, ly, layout.lampSize, layout.lampSize, Palette.chalk)
                if tower.lit, layout.lampSize >= 3 {
                    c.px(lx + 1, ly + 1, Palette.score)
                }
            }
        }
    }

    // MARK: - Birds

    /// A flock crossing high, every 20–40 s (§17). Three `ink` pixels in two flap frames — but
    /// `ink` is all but invisible on a night sky that is itself `ink`, the same trap the side
    /// view's far pieces fell into, so after dark a bird is drawn lighter than the sky instead.
    static func birds(into c: PixelCanvas, scenery: Scenery, view: View, time: Double,
                      width: Double, night: Bool) {
        let colour = night ? Palette.nightSky3 : Palette.ink
        for bird in SkyLife.birds(seed: birdSeed(scenery, view), at: time,
                                  breeze: scenery.breezePixelsPerSecond) {
            let x = (bird.x * width).rounded()
            guard x >= -2, x <= width + 2 else { continue }
            let tip = bird.wingsUp ? -1.0 : 1.0
            c.px(x, bird.y, colour)
            c.px(x - 1, bird.y + tip, colour)
            c.px(x + 1, bird.y + tip, colour)
        }
    }
}
