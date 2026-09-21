import Foundation

/// The sixteen named colours of `docs/palette.md`, as packed RGBA8 pixels. Every channel is one
/// of the Mega Drive's eight levels; there is no alpha blending and no gradient.
///
/// These sixteen keep their roles, but since §20 they are no longer the whole frame: a phase
/// carries three palette lines of its own and `Look.of(_:)` hands them out by role. What is left
/// here is what has one job whatever the hour — the chalk lines, the readout yellow, the grass,
/// the label ink — plus the two the fireworks and the ball still borrow.
enum Palette {
    struct RGBA8: Equatable {
        let r: UInt8
        let g: UInt8
        let b: UInt8
        let a: UInt8
        /// The four bytes as one little-endian word, in the R,G,B,A memory order
        /// `SKMutableTexture` expects. What `PixelCanvas` actually stores.
        let packed: UInt32

        init(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) {
            self.r = r; self.g = g; self.b = b; self.a = a
            packed = UInt32(r) | UInt32(g) << 8 | UInt32(b) << 16 | UInt32(a) << 24
        }

        /// One opaque colour written the way `docs/palette.md` and the prototype write it,
        /// `0xRRGGBB`. The phase lines are hundreds of entries long and a triple of bytes for
        /// each of them hid the colour behind its punctuation; this reads as the hex in the
        /// table, which is also what `scripts/check-looks.py` compares against `golden.py`.
        init(hex: UInt32) {
            self.init(UInt8((hex >> 16) & 0xFF), UInt8((hex >> 8) & 0xFF), UInt8(hex & 0xFF))
        }
    }

    static let sky1 = RGBA8(0x44, 0x66, 0xCC)
    static let sky2 = RGBA8(0x66, 0xAA, 0xEE)
    static let sky3 = RGBA8(0xAA, 0xCC, 0xEE)
    static let grassA = RGBA8(0x22, 0xAA, 0x44)
    static let grassB = RGBA8(0x22, 0x88, 0x44)
    static let wall = RGBA8(0x22, 0x66, 0x44)
    static let dirt = RGBA8(0xCC, 0x88, 0x44)
    static let dirtD = RGBA8(0xAA, 0x66, 0x22)
    static let chalk = RGBA8(0xEE, 0xEE, 0xEE)
    static let ink = RGBA8(0x22, 0x22, 0x44)
    static let skin = RGBA8(0xEE, 0xAA, 0x88)
    static let cap = RGBA8(0xCC, 0x22, 0x22)
    static let bat = RGBA8(0xAA, 0x88, 0x44)
    static let score = RGBA8(0xEE, 0xDD, 0x22)
    static let shade = RGBA8(0x11, 0x66, 0x33)
    static let night = RGBA8(0x22, 0x11, 0x44)
    static let clear = RGBA8(0, 0, 0, 0)
}
