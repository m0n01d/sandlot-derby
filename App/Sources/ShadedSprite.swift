import Foundation
import DerbyCore

/// The numbers behind a shaded figure (DESIGN.md §20 "People", `engine.Sprite`).
struct ShadedSpriteRules {
    /// Above this much light a four-tone ramp takes its fourth colour — the rim, the one pixel
    /// wide edge where the light actually catches. The two cuts below it belong to the phase
    /// (`Look.cuts`), because how hard the light falls off is what the hour changes.
    var rimCut = 0.72
    /// `m_poly`'s fake normal: the top and bottom two rows of a flat polygon are tipped this far
    /// away from the camera, so a torso is not a slab lit only from the side.
    var polyCapRows = 2
    var polyCapTilt = 0.35
    /// …and how far its sides tip. Never a full 1.0: at the very edge of a shape the ramp would
    /// jump straight to the rim and the silhouette would grow a bright outline, which §20 forbids.
    var polySideTilt = 0.95

    static let standard = ShadedSpriteRules()
}

/// One pixel of a shape, with the fake surface normal that decides its tone. The normal is not
/// geometry — nothing here is 3D — it is "which way would this bit of a cylinder be facing", which
/// is all a four-tone ramp needs (`engine.m_ellipse` / `m_capsule` / `m_poly`).
struct MaskPixel {
    let x: Int
    let y: Int
    let nx: Double
    let ny: Double
}

/// The three shapes a person is made of. Each returns every pixel it covers, with its normal.
enum Mask {

    /// A filled ellipse: a head, a shoulder, a glove, a cloud.
    static func ellipse(cx: Double, cy: Double, rx: Double, ry: Double) -> [MaskPixel] {
        guard rx > 0, ry > 0 else { return [] }
        var out: [MaskPixel] = []
        out.reserveCapacity(Int(rx * ry * 4) + 8)
        for y in (Int(cy - ry) - 1)...(Int(cy + ry) + 1) {
            for x in (Int(cx - rx) - 1)...(Int(cx + rx) + 1) {
                let nx = (Double(x) + 0.5 - cx) / rx, ny = (Double(y) + 0.5 - cy) / ry
                if nx * nx + ny * ny <= 1 { out.append(MaskPixel(x: x, y: y, nx: nx, ny: ny)) }
            }
        }
        return out
    }

    /// A tapered capsule between two points: an arm, a leg, a bat. The normal is across the
    /// capsule, so it shades like a cylinder however it is turned.
    static func capsule(x0: Double, y0: Double, r0: Double,
                        x1: Double, y1: Double, r1: Double) -> [MaskPixel] {
        var out: [MaskPixel] = []
        let dx = x1 - x0, dy = y1 - y0
        let l2 = max(1e-9, dx * dx + dy * dy)
        let r = max(r0, r1) + 1
        let yLo = Int(min(y0, y1) - r) - 1, yHi = Int(max(y0, y1) + r) + 1
        let xLo = Int(min(x0, x1) - r) - 1, xHi = Int(max(x0, x1) + r) + 1
        guard yHi >= yLo, xHi >= xLo else { return [] }
        for y in yLo...yHi {
            for x in xLo...xHi {
                let px = Double(x) + 0.5, py = Double(y) + 0.5
                let u = max(0, min(1, ((px - x0) * dx + (py - y0) * dy) / l2))
                let qx = x0 + dx * u, qy = y0 + dy * u
                let rr = r0 + (r1 - r0) * u
                let ex = px - qx, ey = py - qy
                if ex * ex + ey * ey <= rr * rr {
                    out.append(MaskPixel(x: x, y: y, nx: ex / rr, ny: ey / rr))
                }
            }
        }
        return out
    }

    /// A filled polygon, scan-line by scan-line: a torso, a helmet brim, a jersey panel. It is
    /// flat, so its normal is invented — across from the middle of each row, tipped away at the
    /// top and bottom edges (see `ShadedSpriteRules.polyCapTilt`).
    static func poly(_ points: [(Double, Double)],
                     rules: ShadedSpriteRules = .standard) -> [MaskPixel] {
        guard points.count >= 3 else { return [] }
        let ys = points.map(\.1)
        let yLo = Int(ys.min()!) - 1, yHi = Int(ys.max()!) + 1
        guard yHi >= yLo else { return [] }

        var rowY: [Int] = [], rowXs: [[Int]] = []
        for y in yLo...yHi {
            let yc = Double(y) + 0.5
            var xs: [Double] = []
            for i in 0..<points.count {
                let (ax, ay) = points[i], (bx, by) = points[(i + 1) % points.count]
                if (ay <= yc && yc < by) || (by <= yc && yc < ay) {
                    xs.append(ax + (yc - ay) / (by - ay) * (bx - ax))
                }
            }
            xs.sort()
            var here: [Int] = []
            var k = 0
            while k + 1 < xs.count {
                let lo = xs[k], hi = xs[k + 1]
                var x = Int((lo - 0.5).rounded(.down))
                let last = Int((hi + 0.5).rounded(.up))
                while x < last {
                    if lo <= Double(x) + 0.5 && Double(x) + 0.5 <= hi { here.append(x) }
                    x += 1
                }
                k += 2
            }
            if !here.isEmpty { rowY.append(y); rowXs.append(here) }
        }
        guard let first = rowY.first, let last = rowY.last else { return [] }

        var out: [MaskPixel] = []
        for (i, y) in rowY.enumerated() {
            let xr = rowXs[i]
            let lo = Double(xr.min()!), hi = Double(xr.max()!)
            let mid = (lo + hi) / 2, half = max(1, (hi - lo) / 2)
            let ny: Double
            if y - first < rules.polyCapRows { ny = -rules.polyCapTilt }
            else if last - y < rules.polyCapRows { ny = rules.polyCapTilt }
            else { ny = 0 }
            for x in xr {
                out.append(MaskPixel(x: x, y: y,
                                     nx: (Double(x) - mid) / half * rules.polySideTilt, ny: ny))
            }
        }
        return out
    }
}

/// A small transparent canvas that shapes are shaded onto and that is then stamped whole onto the
/// frame — `engine.Sprite`, less its `outline`, which this game does not have: §20 is explicit
/// that a person has no outer outline, and draws a darker contour on the part *below* instead.
///
/// Sprite-local coordinates put (0, 0) at the figure's feet, so a pose is written the way the
/// prototype writes it and the scene only says where the feet are.
final class ShadedSprite {
    let canvas: PixelCanvas
    /// Where sprite-local (0, 0) sits inside `canvas`.
    let ox: Int
    let oy: Int
    /// A unit vector; `Look.light` after normalising.
    private let light: (x: Double, y: Double)
    private let cuts: (lit: Double, dark: Double)
    /// Whether a part draws its own darker contour over what is already under it.
    private let contoured: Bool
    private let rules: ShadedSpriteRules

    init(width: Int, height: Int, ox: Int, oy: Int,
         light: (x: Double, y: Double), cuts: (lit: Double, dark: Double),
         contoured: Bool = true, rules: ShadedSpriteRules = .standard) {
        canvas = PixelCanvas(width: width, height: height)
        canvas.fill(Palette.clear)
        self.ox = ox
        self.oy = oy
        let n = (light.x * light.x + light.y * light.y).squareRoot()
        self.light = n > 0 ? (light.x / n, light.y / n) : (0, -1)
        self.cuts = cuts
        self.contoured = contoured
        self.rules = rules
    }

    /// The tone this normal takes out of a ramp: deep shade, shade, body, and — for a four-entry
    /// ramp — the rim the light actually catches.
    func tone(_ ramp: [Palette.RGBA8], nx: Double, ny: Double) -> Palette.RGBA8 {
        guard ramp.count > 1 else { return ramp.first ?? Palette.clear }
        let l = nx * light.x + ny * light.y
        if ramp.count >= 4 && l > rules.rimCut { return ramp[3] }
        if l > cuts.lit { return ramp[min(2, ramp.count - 1)] }
        if l < cuts.dark { return ramp[0] }
        return ramp[1]
    }

    /// One shaded part. `contour` is drawn first, on whatever of the sprite is already painted
    /// around this part's edge — never outside the figure, which is the difference between §20's
    /// inner contour and the outline it forbids.
    func part(_ mask: [MaskPixel], _ ramp: [Palette.RGBA8], contour: Palette.RGBA8? = nil) {
        if contoured, let contour {
            var inside = Set<Int>(minimumCapacity: mask.count * 2)
            for p in mask { inside.insert(key(p.x + ox, p.y + oy)) }
            for p in mask {
                let x = p.x + ox, y = p.y + oy
                for (ax, ay) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let qx = x + ax, qy = y + ay
                    guard !inside.contains(key(qx, qy)), isPainted(qx, qy) else { continue }
                    canvas.px(Double(qx), Double(qy), contour)
                }
            }
        }
        for p in mask {
            canvas.px(Double(p.x + ox), Double(p.y + oy), tone(ramp, nx: p.nx, ny: p.ny))
        }
    }

    /// One part in a single flat colour — a shoe sole, a belt, the black of a bat's grip.
    func part(_ mask: [MaskPixel], flat colour: Palette.RGBA8) {
        for p in mask { canvas.px(Double(p.x + ox), Double(p.y + oy), colour) }
    }

    /// One pixel, in sprite-local coordinates.
    func set(_ x: Int, _ y: Int, _ colour: Palette.RGBA8) {
        canvas.px(Double(x + ox), Double(y + oy), colour)
    }

    /// An ASCII stamp in sprite-local coordinates: one character per pixel, `.` and space are
    /// nothing. The pitcher's three poses are written this way (`golden.PITCH`).
    func stamp(_ rows: [String], legend: [Character: Palette.RGBA8], x: Int, y: Int) {
        for (j, row) in rows.enumerated() {
            for (i, ch) in row.enumerated() {
                guard let colour = legend[ch] else { continue }
                set(x + i, y + j, colour)
            }
        }
    }

    /// Copies the figure onto a frame by colour key, with sprite-local (0, 0) landing at `x`, `y`.
    func blit(onto target: PixelCanvas, x: Int, y: Int) {
        for j in 0..<canvas.height {
            let ty = y - oy + j
            guard ty >= 0, ty < target.height else { continue }
            let src = canvas.buffer + j * canvas.width
            let dst = target.buffer + ty * target.width
            for i in 0..<canvas.width where src[i] != 0 {
                let tx = x - ox + i
                guard tx >= 0, tx < target.width else { continue }
                dst[tx] = src[i]
            }
        }
    }

    @inline(__always) private func key(_ x: Int, _ y: Int) -> Int { y &* canvas.width &+ x }

    @inline(__always) private func isPainted(_ x: Int, _ y: Int) -> Bool {
        guard x >= 0, y >= 0, x < canvas.width, y < canvas.height else { return false }
        return canvas.buffer[y * canvas.width + x] != 0
    }
}

/// The figures, built once each and kept. A rig is a few hundred masks' worth of arithmetic and
/// the same pose comes back a thousand times in a career, so §20 asks for the stamp to be drawn
/// "one time for each pose and phase". The key is exactly that: who, which pose, which hour.
final class ShadedSpriteCache {
    struct Key: Hashable {
        let name: String
        let pose: Int
        let phase: DayPhase
    }

    private var sprites: [Key: ShadedSprite] = [:]

    /// The sprite for this key, building it the first time it is asked for.
    func sprite(_ name: String, pose: Int, phase: DayPhase,
                build: () -> ShadedSprite) -> ShadedSprite {
        let key = Key(name: name, pose: pose, phase: phase)
        if let hit = sprites[key] { return hit }
        let made = build()
        sprites[key] = made
        return made
    }

    /// Throws the lot away. The phase is part of the key, so nothing here goes stale on its own;
    /// this is for a scene that is being torn down.
    func flush() { sprites.removeAll(keepingCapacity: true) }
}

#if DEBUG
extension ShadedSprite {

    /// The prototype's batter torso, shaded at `goldenHour`, against the tones `golden.py` itself
    /// produces for it. Steps 3 and 4 build the people out of `Mask` and `part`, so the port of
    /// the masks and of the ramp has to be right before either of them starts — and a handful of
    /// counted tones catches a wrong cut, a wrong normal or an off-by-one scan line in a way that
    /// looking at a 17×27 figure never would. Run in Debug only, once, from `GameController`.
    ///
    /// The numbers come from:
    ///     python3 -B -c "import golden as G; from engine import *
    ///     s = Sprite(128, 104, 50, 100, G.DUSK['light'], G.DUSK['cuts'], inner=True)
    ///     s.part(m_poly(TORSO), G.DUSK['grey'], G.DUSK['grey'][0])"
    static let batterTorso: [(Double, Double)] = [
        (-8, -54), (-2, -57), (7, -55), (9, -44), (7, -30), (-7, -30), (-9, -42)
    ]

    /// Every way the port differs from the prototype, as a list of sentences. Empty is a pass.
    static func selfCheck() -> [String] {
        let look = Look.of(.goldenHour)
        let sprite = ShadedSprite(width: 128, height: 104, ox: 50, oy: 100,
                                  light: look.light, cuts: look.cuts)
        sprite.part(Mask.poly(batterTorso), look.grey, contour: look.grey[0])

        var counts = [0, 0, 0, 0], painted = 0
        for y in 0..<sprite.canvas.height {
            for x in 0..<sprite.canvas.width {
                let word = sprite.canvas.buffer[y * sprite.canvas.width + x]
                guard word != 0 else { continue }
                painted += 1
                if let i = look.grey.firstIndex(where: { $0.packed == word }) { counts[i] += 1 }
            }
        }

        var wrong: [String] = []
        if painted != 419 { wrong.append("torso covers \(painted) pixels, golden.py paints 419") }
        if counts != [128, 156, 102, 33] {
            wrong.append("torso tones are \(counts), golden.py gives [128, 156, 102, 33]")
        }
        // Three pixels the ramp has to place by name: the lit rim up the left side (the sun is
        // low on the left at `goldenHour`), the deep shade on the right, and plain body below.
        for (lx, ly, want) in [(-8.0, -52.0, 3), (8.0, -42.0, 0), (0.0, -31.0, 1)] {
            let x = Int(lx) + sprite.ox, y = Int(ly) + sprite.oy
            let word = sprite.canvas.buffer[y * sprite.canvas.width + x]
            let got = look.grey.firstIndex { $0.packed == word }
            if got != want { wrong.append("torso (\(Int(lx)), \(Int(ly))) is tone \(got.map(String.init) ?? "none"), golden.py gives \(want)") }
        }
        return wrong
    }
}
#endif
