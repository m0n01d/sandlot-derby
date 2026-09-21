import Foundation

/// The Genesis-style, sixteen-entry palette from `docs/palette.md`, as packed RGBA8 pixels.
/// Every channel is one of the Mega Drive's eight levels; no other colour is ever mixed in,
/// there is no alpha blending, and no gradients — one palette line, nothing else.
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
    /// Night-only stand-in for `sky3`, `#446688` per docs/palette.md.
    static let nightSky3 = RGBA8(0x44, 0x66, 0x88)
    static let clear = RGBA8(0, 0, 0, 0)

    /// The three sky colours currently in effect. A lit park swaps `sky1 → night`, `sky2 → ink`,
    /// `sky3 → nightSky3`; nothing else about the palette changes (docs/palette.md).
    struct SkyScheme {
        let sky1: RGBA8
        let sky2: RGBA8
        let sky3: RGBA8
    }

    /// `lampsOn` is `DayPhase.lampsOn` — the clock's answer, not the park's (DESIGN.md §20).
    /// §20 step 2 replaces this pair of lines with `Look.of(_ phase:)` and a line per phase; for
    /// now the two lines that already ship are the two the six phases share out.
    static func scheme(lampsOn: Bool) -> SkyScheme {
        lampsOn
            ? SkyScheme(sky1: night, sky2: ink, sky3: nightSky3)
            : SkyScheme(sky1: sky1, sky2: sky2, sky3: sky3)
    }
}
