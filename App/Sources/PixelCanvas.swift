import Foundation

/// A software framebuffer in design units: always 224 tall, at least 320 wide, y-down
/// (row 0 is the TOP of the screen — the opposite of SpriteKit's own coordinate space, see
/// `CanvasScene.blit`). Primitives are a 1:1 port of the prototype's `px/rect/line/disc/
/// dither/dashed/t3/t5` (prototypes/03-camera-cut-and-slice.html, roughly lines 219-227).
final class PixelCanvas {
    let width: Int
    let height: Int
    /// One packed RGBA word per pixel (`Palette.RGBA8.packed`), row 0 at the top. A raw buffer,
    /// not an array: the whole frame is redrawn every tick and a Debug build's per-element
    /// bounds and exclusivity checks alone cost the 60 Hz budget.
    let buffer: UnsafeMutablePointer<UInt32>

    init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
        buffer = .allocate(capacity: self.width * self.height)
        buffer.initialize(repeating: 0, count: self.width * self.height)
    }

    deinit { buffer.deallocate() }

    func fill(_ color: Palette.RGBA8) {
        buffer.update(repeating: color.packed, count: width * height)
    }

    @inline(__always)
    private func setPixel(_ x: Int, _ y: Int, _ color: Palette.RGBA8) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        buffer[y * width + x] = color.packed
    }

    func px(_ x: Double, _ y: Double, _ color: Palette.RGBA8) {
        setPixel(Int(x), Int(y), color)
    }

    func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ color: Palette.RGBA8) {
        let x0 = max(0, Int(x)), y0 = max(0, Int(y))
        let x1 = min(width, Int(x) + Int(w)), y1 = min(height, Int(y) + Int(h))
        guard x1 > x0, y1 > y0 else { return }
        for j in y0..<y1 {
            (buffer + j * width + x0).update(repeating: color.packed, count: x1 - x0)
        }
    }

    /// Bresenham with square thickness, ported verbatim from the prototype's `line`.
    func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ color: Palette.RGBA8, thickness: Int = 1) {
        var x0i = Int(x0), y0i = Int(y0)
        let x1i = Int(x1), y1i = Int(y1)
        let dx = abs(x1i - x0i), sx = x0i < x1i ? 1 : -1
        let dy = -abs(y1i - y0i), sy = y0i < y1i ? 1 : -1
        var err = dx + dy
        let t = max(1, thickness)
        while true {
            for i in 0..<t {
                for j in 0..<t {
                    setPixel(x0i + i - (t >> 1), y0i + j - (t >> 1), color)
                }
            }
            if x0i == x1i && y0i == y1i { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x0i += sx }
            if e2 <= dx { err += dx; y0i += sy }
        }
    }

    func disc(_ cx: Double, _ cy: Double, _ r: Double, _ color: Palette.RGBA8) {
        guard r > 0 else { return }
        let cxi = Int(cx), cyi = Int(cy)
        let ri = max(0, Int(r))
        let r2 = r * r + r * 0.5
        for y in -ri...ri {
            for x in -ri...ri {
                if Double(x * x + y * y) <= r2 { setPixel(cxi + x, cyi + y, color) }
            }
        }
    }

    func dither(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ a: Palette.RGBA8, _ b: Palette.RGBA8) {
        let x0 = Int(x), y0 = Int(y), w0 = Int(w), h0 = Int(h)
        guard w0 > 0, h0 > 0 else { return }
        for j in 0..<h0 {
            for i in 0..<w0 {
                setPixel(x0 + i, y0 + j, ((i + j) & 1) != 0 ? a : b)
            }
        }
    }

    // MARK: - The ordered dither (DESIGN.md §20)

    /// The Bayer 4×4 matrix, verbatim from `prototypes/04-golden-hour/engine.py`. §20 replaces
    /// §17's four-row checker band with this everywhere it allows a blend at all: the sky, a
    /// halo, the wall face, the tip of a shadow, the low sun on the grass, the mist and the
    /// corners of the field at night. Nowhere else, and never on a person.
    static let bayer: [Int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

    /// What density a pixel needs before the dither paints it: 1/32, 3/32, … 31/32, by position.
    /// Screen coordinates, not coordinates inside the shape, so two shapes that overlap share one
    /// grid and the seam between them does not show.
    @inline(__always)
    static func threshold(_ x: Int, _ y: Int) -> Double {
        (Double(bayer[(y & 3) * 4 + (x & 3)]) + 0.5) / 16
    }

    /// An ordered-dither blend from `top` to `bottom` across `h` rows — `engine.bayer_gradient`,
    /// pixel for pixel. Every row is written, so this is a fill and not an overlay.
    func bayerGradient(_ x: Double, _ y: Double, _ w: Double, _ h: Double,
                       _ top: Palette.RGBA8, _ bottom: Palette.RGBA8) {
        let x0 = Int(x), y0 = Int(y), w0 = Int(w), h0 = Int(h)
        guard w0 > 0, h0 > 0 else { return }
        for j in 0..<h0 {
            let t = (Double(j) + 0.5) / Double(h0)
            let row = y0 + j
            for i in 0..<w0 {
                let col = x0 + i
                setPixel(col, row, t > Self.threshold(col, row) ? bottom : top)
            }
        }
    }

    /// An ordered-dither *overlay*: `colour` where `density` beats the matrix and whatever was
    /// already there everywhere else. The one way this palette has of laying one colour thinly
    /// over another — the mist, the night pool, the rake of a low sun, a lamp's bloom.
    ///
    /// `density` is asked in canvas coordinates and answers 0 (nothing) to 1 (solid).
    func orderedDither(_ x: Double, _ y: Double, _ w: Double, _ h: Double,
                       _ colour: Palette.RGBA8, density: (Int, Int) -> Double) {
        let x0 = Int(x), y0 = Int(y), w0 = Int(w), h0 = Int(h)
        guard w0 > 0, h0 > 0 else { return }
        for j in 0..<h0 {
            let row = y0 + j
            guard row >= 0, row < height else { continue }
            for i in 0..<w0 {
                let col = x0 + i
                guard col >= 0, col < width else { continue }
                if density(col, row) > Self.threshold(col, row) {
                    buffer[row * width + col] = colour.packed
                }
            }
        }
    }

    /// A filled ellipse on the pixel-centre rule of `engine.ellipse`: a pixel is in when its
    /// middle is, which is what keeps a 5×2 dirt ellipse from growing a row of ears.
    func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ colour: Palette.RGBA8) {
        guard rx > 0, ry > 0 else { return }
        for y in (Int(cy - ry) - 1)...(Int(cy + ry) + 1) {
            for x in (Int(cx - rx) - 1)...(Int(cx + rx) + 1) {
                let nx = (Double(x) + 0.5 - cx) / rx, ny = (Double(y) + 0.5 - cy) / ry
                if nx * nx + ny * ny <= 1 { setPixel(x, y, colour) }
            }
        }
    }

    /// Copies `source` onto this canvas row by row, every pixel of it — the opaque blit the new
    /// `sky` layer takes (§20 "Layers and speed"). Nothing is keyed out, because the sky is the
    /// bottom of the frame and there is nothing under it to show through.
    func copyRows(from source: PixelCanvas) {
        guard source.width == width else { return }
        let rows = min(height, source.height)
        guard rows > 0 else { return }
        buffer.update(from: source.buffer, count: rows * width)
    }

    /// The ball: `chalk`, red laces (`cap`, borrowed by role) from 2 px of radius up, and one
    /// highlight pixel from 3. The laces are a ")" seam right of centre; they do not rotate.
    func baseball(_ cx: Double, _ cy: Double, radius r: Double, highlight: Palette.RGBA8) {
        disc(cx, cy, r, Palette.chalk)
        let x = cx.rounded(.down), y = cy.rounded(.down)
        let seam: [(Double, Double)]
        switch Int(r) {
        case ..<2: seam = []
        case 2: seam = [(1, 0)]
        case 3: seam = [(1, -1), (2, 0), (1, 1)]
        default: seam = [(1, -2), (2, -1), (2, 0), (2, 1), (1, 2)]
        }
        for (dx, dy) in seam { px(x + dx, y + dy, Palette.cap) }
        if r >= 3 { px(x - 1, y - 1, highlight) }
    }

    /// A circle of single pixels about `gap` apart. The only outline shape there is.
    func ring(_ cx: Double, _ cy: Double, _ r: Double, _ color: Palette.RGBA8, gap: Double = 3) {
        let n = max(8, Int((2 * Double.pi * r / gap).rounded()))
        for i in 0..<n {
            let a = 2 * Double.pi * Double(i) / Double(n)
            px(cx + cos(a) * r, cy + sin(a) * r, color)
        }
    }

    func dashed(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ color: Palette.RGBA8) {
        let length = ((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0)).squareRoot()
        let n = max(1, Int((length / 2).rounded(.down)))
        for i in 0...n {
            if ((i >> 1) & 1) != 0 { continue }
            let t = Double(i) / Double(n)
            px(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, color)
        }
    }

    /// 3x5 bitmap face, copied verbatim from the prototype's `F3`
    /// (prototypes/03-camera-cut-and-slice.html ~line 224).
    private static let f3: [Character: [Character]] = [
        "0": Array("111101101101111"), "1": Array("010110010010111"), "2": Array("111001111100111"),
        "3": Array("111001111001111"), "4": Array("101101111001001"), "5": Array("111100111001111"),
        "6": Array("111100111101111"), "7": Array("111001001001001"), "8": Array("111101111101111"),
        "9": Array("111101111001111"), "F": Array("111100110100100"), "T": Array("111010010010010"),
        "H": Array("101101111101101"), "R": Array("110101110101101"), "P": Array("110101110100100"),
        "A": Array("010101111101101"), "K": Array("101110100110101"), "M": Array("101111111101101"),
        "D": Array("110101101101110"), "E": Array("111100111100111"), "G": Array("111100101101111"),
        "S": Array("111100111001111"), "I": Array("111010010010111"), "N": Array("110101101101101"),
        "W": Array("101101101111101"), "L": Array("100100100100111"), "O": Array("111101101101111"),
        "U": Array("101101101101111"), "C": Array("111100100100111"), "B": Array("110101110101110"),
        "V": Array("101101101101010"), "Y": Array("101101010010010"), " ": Array("000000000000000"),
        // Not in the prototype: the stats screen needs the rest of the alphabet and some marks.
        "J": Array("001001001101111"), "Q": Array("111101101111001"), "X": Array("101101010101101"),
        "Z": Array("111001010100111"), ".": Array("000000000000010"), ":": Array("000010000010000"),
        "-": Array("000000111000000"), "%": Array("101001010100101"), "/": Array("001001010100100"),
        ",": Array("000000000010100"),
        // The Warm Up's headline separator, `WARM UP · 3/10` (DESIGN.md §18). One pixel is what
        // a middle dot is at this size; any more and it reads as a full stop.
        "·": Array("000000010000000")
        // No currency symbols here on purpose (DESIGN.md §16): a 3×5 cell has no room for the
        // stroke that has to overshoot the `S` top and bottom, and without it a `$` reads as a
        // blocky `5`. The price is drawn in the 5×7 face below, which has the rows for it.
    ]

    /// True when every character of `text` has a 3×5 glyph.
    static func hasGlyphs3(for text: String) -> Bool {
        text.uppercased().allSatisfy { f3[$0] != nil }
    }

    /// True when every character of `text` has a 5×7 glyph. `Store` asks before offering a price
    /// the way the store wrote it; a currency this face cannot spell falls back to its ISO code.
    static func hasGlyphs5(for text: String) -> Bool {
        text.uppercased().allSatisfy { f5[$0] != nil }
    }

    /// 5x7 bitmap face, copied verbatim from the prototype's `F5`
    /// (prototypes/03-camera-cut-and-slice.html ~line 226).
    private static let f5: [Character: [Character]] = [
        "0": Array("01110100011000110001100011000101110"), "1": Array("00100011000010000100001000010001110"),
        "2": Array("01110100010000100010001000100011111"), "3": Array("11111000100010000010000011000101110"),
        "4": Array("00010001100101010010111110001000010"), "5": Array("11111100001111000001000011000101110"),
        "6": Array("00110010001000011110100011000101110"), "7": Array("11111000010001000100010000100001000"),
        "8": Array("01110100011000101110100011000101110"), "9": Array("01110100011000101111000010001001100"),
        "F": Array("11111100001000011110100001000010000"), "T": Array("11111001000010000100001000010000100"),
        "H": Array("10001100011000111111100011000110001"), "R": Array("11110100011000111110101001001010001"),
        " ": Array("00000000000000000000000000000000000"),
        // Added for the `BARREL` call (DESIGN.md §3, issue #20), same block-letter style as the rest.
        "B": Array("11110100011000111110100011000111110"), "A": Array("01110100011000111111100011000110001"),
        "E": Array("11111100001000011110100001000011111"), "L": Array("10000100001000010000100001000011111"),
        // Not in the prototype: the contract card's price (DESIGN.md §16). Seven rows are the
        // point — the `$`'s stroke overshoots the `S` above and below, which is the one thing
        // that stops it reading as a `5`, and 3×5 has no room for it.
        "$": Array("00100011111010001110001011111000100"),
        "€": Array("00111010001111001000111100100000111"),
        "£": Array("00111010000100011100010000100011111"),
        "¥": Array("10001010100010011111001001111100100"),
        ".": Array("00000000000000000000000000110001100"),
        ",": Array("00000000000000000000011000110001100")
    ]

    /// Draws `text` in the 3x5 face at the given scale (labels, readouts). `shadow` is §20's
    /// one-pixel drop, down and right and drawn first, which is what lets a `chalk` readout sit
    /// on a `dawn` sky without dissolving into it.
    func t3(_ x: Double, _ y: Double, _ text: String, _ color: Palette.RGBA8, scale: Int = 1,
            shadow: Palette.RGBA8? = nil) {
        if let shadow {
            t3(x + Double(scale), y + Double(scale), text, shadow, scale: scale)
        }
        var cx = x
        let sc = Double(scale)
        for ch in text.uppercased() {
            let bits = Self.f3[ch] ?? Self.f3[" "]!
            for j in 0..<5 {
                for i in 0..<3 where bits[j * 3 + i] == "1" {
                    rect(cx + Double(i) * sc, y + Double(j) * sc, sc, sc, color)
                }
            }
            cx += 4 * sc
        }
    }

    /// Draws `text` in the 5x7 face at the given scale (the landing number, HR). `shadow` is
    /// §20's one-pixel drop, down and right and drawn first.
    func t5(_ x: Double, _ y: Double, _ text: String, _ color: Palette.RGBA8, scale: Int = 1,
            shadow: Palette.RGBA8? = nil) {
        if let shadow {
            t5(x + Double(scale), y + Double(scale), text, shadow, scale: scale)
        }
        var cx = x
        let sc = Double(scale)
        for ch in text.uppercased() {
            let bits = Self.f5[ch] ?? Self.f5[" "]!
            for j in 0..<7 {
                for i in 0..<5 where bits[j * 5 + i] == "1" {
                    rect(cx + Double(i) * sc, y + Double(j) * sc, sc, sc, color)
                }
            }
            cx += 6 * sc
        }
    }
}
