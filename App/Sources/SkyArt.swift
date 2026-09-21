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

    // MARK: - The sky itself (DESIGN.md §20)

    /// The phase's colour stops, top to horizon: a flat band where two stops share a colour and
    /// an ordered-dither blend where they do not (`golden.sky`). Every row of the canvas is
    /// written, the last stop carrying on to the bottom edge, because this is the floor of the
    /// frame and the field goes in on top of it.
    ///
    /// The at-bat camera ends its stops on the top of the wall band; the flight camera stretches
    /// the same six or seven stops down to the canonical ground in *both* framings — the sky is
    /// infinitely far away, so the close camera lifting the ground does not move it, it only
    /// exposes more of the last stop.
    static func sky(into c: PixelCanvas, look: Look, width: Double, flightCamera: Bool,
                    rules: LookRules = .standard) {
        let source = look.skyStops(flightCamera: flightCamera)
        guard let last = source.last else { return }
        let bottom = flightCamera ? rules.skyBottomFlight : rules.skyBottomAtBat
        let stretch = flightCamera ? bottom / rules.skyBottomAtBat * rules.flightStretch : 1

        var stops = source.map { (y: ($0.y * stretch).rounded(), colour: $0.colour) }
        stops[stops.count - 1].y = bottom

        for i in 0..<(stops.count - 1) {
            let (y0, a) = stops[i], (y1, b) = stops[i + 1]
            guard y1 > y0 else { continue }
            if a == b {
                c.rect(0, y0, width, y1 - y0, a)
            } else {
                c.bayerGradient(0, y0, width, y1 - y0, a, b)
            }
        }
        // Whatever the close camera exposes below the last stop is that last stop, flat.
        c.rect(0, bottom, width, Double(c.height) - bottom, last.colour)
    }

    /// A sun or a moon: a disc with a halo that dithers into the sky, because with no alpha a
    /// light cannot fade into anything (`golden.sun`). The halo is an ellipse wider than it is
    /// tall, which is what a low sun in haze actually looks like.
    ///
    /// `clipY` stops it at the ground, so the low sun at `goldenHour` sits *behind* the horizon
    /// rather than on it. `bite` is the moon's: a disc of the top sky stop taken out of one side.
    static func sunOrMoon(into c: PixelCanvas, look: Look,
                          x sx: Double, y sy: Double, radius r: Double, halo: Double,
                          clipY: Double? = nil, biteDirection: Int? = nil,
                          rules: LookRules = .standard, layout: BackdropLayout = .standard) {
        guard let tones = look.sun, tones.count >= 2 else { return }
        let body = tones[0], glow = tones[1]
        guard halo > r else { return }

        let spread = halo * rules.sunHaloSpreadX
        var y = (sy - halo).rounded(.down)
        while y < sy + halo {
            if let clipY, y >= clipY { break }
            var x = (sx - spread).rounded(.down)
            while x < sx + spread {
                let dx = x + 0.5 - sx, dy = (y + 0.5 - sy) * rules.sunHaloSquashY
                let d = (dx * dx + dy * dy).squareRoot()
                if d <= r {
                    c.px(x, y, body)
                } else if d < halo,
                          (halo - d) / (halo - r) * rules.sunHaloStrength
                            > PixelCanvas.threshold(Int(x), Int(y)) {
                    c.px(x, y, glow)
                }
                x += 1
            }
            y += 1
        }

        // The bite: a disc of the very top of the sky, pushed to the seeded side and kept inside
        // the moon, so the moon is a crescent and not a disc with a hole beside it.
        if let biteDirection, let top = look.skyAtBat.first?.colour {
            let bx = sx + Double(biteDirection) * r * layout.moonBiteOffset
            let by = sy - r * 0.2
            let br = r * layout.moonBiteRadius
            for p in Mask.ellipse(cx: bx, cy: by, rx: br, ry: br) {
                let ddx = Double(p.x) + 0.5 - sx, ddy = Double(p.y) + 0.5 - sy
                if (ddx * ddx + ddy * ddy).squareRoot() <= r {
                    c.px(Double(p.x), Double(p.y), top)
                }
            }
        }
    }

    /// The moon, wherever its park hung it. The disc is the park's — one park in sixteen has one
    /// at all, and its place, its size and which way it is bitten are seeded (§17) — and the
    /// phase only says what colour it is and how far its halo reaches.
    static func moon(into c: PixelCanvas, look: Look, moon: Moon, width: Double,
                     clipY: Double? = nil, rules: LookRules = .standard,
                     layout: BackdropLayout = .standard) {
        sunOrMoon(into: c, look: look, x: (moon.xFraction * width).rounded(), y: moon.y,
                  radius: moon.radius, halo: moon.radius * rules.moonHaloScale,
                  clipY: clipY, biteDirection: moon.biteDirection, rules: rules, layout: layout)
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
                         time: Double, width: Double, look: Look,
                         layout: BackdropLayout = .standard,
                         rules: LookRules = .standard,
                         sceneryRules: SceneryRules = .standard) {
        let showing = look.phase == .twilight
            ? min(scenery.stars.count, max(0, sceneryRules.twilightStars))
            : scenery.stars.count
        for star in scenery.stars.prefix(showing) {
            guard SkyLife.starIsLit(star, at: time) else { continue }
            let x = (star.xFraction * width).rounded()
            guard !isInsideAHalo(x: x, y: star.y, towers: towers, layout: layout) else { continue }
            // Two rolls off the star's own place, so the same star is the same star every night
            // and Core keeps a `Star` that says where one is and nothing about how it burns
            // (§20 "Stars", `golden.stars`).
            let roll = hashRoll(star.xFraction, star.y, salt: 0x51ED)
            let bright = roll < rules.starBrightShare
            c.px(x, star.y, bright ? rules.starBright : rules.starDim)
            // A bright star gets four dim neighbours — and only a bright one does, which is what
            // keeps the crosses to a handful instead of a third of the sky.
            if bright, roll < rules.starNeighbourShare {
                for (ax, ay) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)] {
                    c.px(x + ax, star.y + ay, rules.starNeighbour)
                }
            }
        }

        if look.phase == .night, let m = scenery.moon {
            moon(into: c, look: look, moon: m, width: width, rules: rules, layout: layout)
        }

        for tower in towers where !tower.isOut {
            halo(into: c, tower: tower, look: look,
                 rings: tower.lit ? layout.haloRings.count : layout.haloRingsWhenDark,
                 layout: layout)
        }
    }

    /// A 0…1 roll off two numbers that never change. Not `SplitMix64`: this has to answer for one
    /// star without walking the stream, so the star's own coordinates are the seed.
    private static func hashRoll(_ a: Double, _ b: Double, salt: UInt64) -> Double {
        var h = UInt64(bitPattern: Int64((a * 4096).rounded())) &* 0x9E37_79B9_7F4A_7C15
        h ^= UInt64(bitPattern: Int64((b * 4096).rounded())) &* 0xBF58_476D_1CE4_E5B9
        h ^= salt &* 0x94D0_49BB_1331_11EB
        h ^= h >> 29; h = h &* 0xBF58_476D_1CE4_E5B9; h ^= h >> 32
        return Double(h % 10_000) / 10_000
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

    /// The glow. With no alpha a light cannot fade into the sky, so it dithers into it: rings
    /// that thin outward, the innermost in the phase's inner bloom and the rest in its outer one
    /// — one of the places §20 allows a dither at all.
    private static func halo(into c: PixelCanvas, tower: TowerFrame, look: Look, rings: Int,
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
                c.px(Double(x), Double(y), ring == 0 ? look.tower[2] : look.tower[1])
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

    /// A lattice pole carrying a bank of lamps (§17, §20). A bank that is dark in the chase keeps
    /// its lamps in the pole colour, so the chase reads as light running along the roof rather
    /// than as the towers switching off.
    ///
    /// The pole colour is the phase's `tower[0]`. Step 1 had to pick one of two palette entries
    /// per view, because a night sky's upper bands *were* `night` and `ink` and an `ink` lattice
    /// in them was invisible; §20 gives the tower a colour of its own that reads against every
    /// sky it stands in, and both views take it.
    static func towers(into c: PixelCanvas, frames: [TowerFrame], width: Double, look: Look,
                       layout: BackdropLayout = .standard) {
        for tower in frames {
            guard tower.x > -tower.bankW, tower.x < width + tower.bankW else { continue }
            lattice(into: c, tower: tower, colour: look.tower[0], layout: layout)
            bank(into: c, tower: tower, look: look, layout: layout)
        }
    }

    /// The poles alone, and the banks alone. §20's flight camera caches its lattices in the layer
    /// *behind* the upper deck — a tower stands further back than the roof and the roof cuts it
    /// off — and draws only the banks per frame, because a bank is what the chase moves. Added
    /// beside `towers(into:frames:width:look:layout:)`, which is unchanged and is still what the
    /// at-bat camera draws with.
    static func towerLattices(into c: PixelCanvas, frames: [TowerFrame], width: Double,
                              look: Look, layout: BackdropLayout = .standard) {
        for tower in frames where tower.x > -tower.bankW && tower.x < width + tower.bankW {
            lattice(into: c, tower: tower, colour: look.tower[0], layout: layout)
        }
    }

    static func towerBanks(into c: PixelCanvas, frames: [TowerFrame], width: Double,
                           look: Look, layout: BackdropLayout = .standard) {
        for tower in frames where tower.x > -tower.bankW && tower.x < width + tower.bankW {
            bank(into: c, tower: tower, look: look, layout: layout)
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

    private static func bank(into c: PixelCanvas, tower: TowerFrame, look: Look,
                             layout: BackdropLayout) {
        let left = tower.x - tower.bankW / 2
        c.rect(left, tower.bankY, tower.bankW, tower.bankH, look.board[2])
        let pitch = layout.lampSize + layout.lampGap
        for row in 0..<tower.rows {
            for col in 0..<tower.columns {
                let lx = left + 1 + Double(col) * pitch
                let ly = tower.bankY + 1 + Double(row) * pitch
                // A bank a ball has put out, and one that is merely dark in the chase, both keep
                // their lamps in the pole colour: the tower still reads as a tower with its
                // lights off rather than as a hole in the sky (#5, §20 "Towers").
                let alight = tower.lit && !tower.isOut
                c.rect(lx, ly, layout.lampSize, layout.lampSize,
                       alight ? look.tower[3] : look.tower[0])
                if alight, layout.lampSize >= 3 {
                    c.px(lx + 1, ly + 1, Palette.chalk)
                }
            }
        }
    }

    // MARK: - Birds

    /// A flock crossing high, every 20–40 s (§17). Three pixels in two flap frames, in the
    /// phase's own bird colour — a bird has one in each of the six lines precisely because `ink`
    /// does not show on a dark sky (§20 "What the clock replaces").
    ///
    /// `skipping` is the one bird a ball has already gone through (#5). There is no bird state
    /// anywhere to mark, so the machine names it and the sky simply leaves it out for the rest
    /// of the crossing.
    static func birds(into c: PixelCanvas, scenery: Scenery, view: View, time: Double,
                      width: Double, look: Look, skipping: (slot: Int, index: Int)? = nil) {
        let colour = look.bird
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
    /// frames and no more (§9). Its envelope and its belly come off the phase line, like the
    /// birds', so it reads against every sky.
    static func blimp(into c: PixelCanvas, scenery: Scenery, view: View, time: Double,
                      width: Double, look: Look, layout: BackdropLayout = .standard) {
        guard scenery.hasBlimp,
              let b = SkyLife.blimp(seed: view.blimpSeed(parkNumber: scenery.parkNumber),
                                    at: time, breeze: scenery.breezePixelsPerSecond)
        else { return }
        let cx = (b.x * width).rounded(), cy = b.y.rounded()
        guard cx > -layout.blimpWidth, cx < width + layout.blimpWidth else { return }
        let body = look.blimp[0]
        let detail = look.blimp[1]

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
