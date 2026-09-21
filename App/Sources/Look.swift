import Foundation
import DerbyCore

/// One colour of a phase line, written the way `docs/palette.md` writes it: `0xRRGGBB`. Every
/// channel is one of the Mega Drive's eight levels (§20), which `scripts/check-looks.py` checks
/// along with the value itself.
private func c(_ hex: UInt32) -> Palette.RGBA8 { Palette.RGBA8(hex: hex) }

/// The drawing's own numbers for the six looks — the App half of §20's knob table. Every one of
/// them is a pixel or a fraction, never a colour: the colours are the phase lines below.
struct LookRules {

    // MARK: The sky

    /// At bat the sky's stops end here; the wall band starts on the next row.
    var skyBottomAtBat = 96.0
    /// The flight camera stretches the same stops down to here, in both framings, and fills
    /// whatever the close camera exposes below it with the last stop (§20 "The look, piece by
    /// piece"). It is `BackdropLayout.canonicalGround`, and deliberately its own number: the sky
    /// is infinitely far away and does not care where the ground went.
    var skyBottomFlight = 176.0
    /// …but not quite proportionally. The stops are squeezed by this much on the way down, so the
    /// horizon band stays a band rather than growing to a sixth of the screen (`golden.flight`).
    var flightStretch = 0.97

    /// The sun's halo: how much wider than tall it spreads, how much its rows are squashed, and
    /// how much of the ring nearest the disc is filled at all (`golden.sun`).
    var sunHaloSpreadX = 1.3
    var sunHaloSquashY = 1.2
    var sunHaloStrength = 0.95
    /// The moon's halo, as a multiple of the moon's own seeded radius. `golden.py` writes the
    /// pair out (r 7, halo 17 at bat; r 8, halo 20 in the flight camera) and this park's moon is
    /// whatever size its seed drew, so the ratio is the thing that carries over.
    var moonHaloScale = 2.4

    // MARK: The stars (§20 "Stars")

    /// A star is `chalk` this often and `starDim` the rest of the time, and this many of the
    /// bright ones get the four dim neighbours §20 asks for. Both rolls are `golden.stars`'; the
    /// neighbours are tied to the bright stars rather than rolled independently, which is what
    /// makes the rule "a bright star has four dim neighbours" true of every crossed star without
    /// carpeting the sky with crosses.
    var starBrightShare = 0.35
    var starNeighbourShare = 0.08
    var starBright = Palette.chalk
    var starDim = c(0xAAAACC)
    var starNeighbour = c(0x666688)

    // MARK: The crowd and the light

    /// How many of the seats hold a person, from `dawn` to `night`. The crowd fills with the day.
    var crowdShare = [0.25, 0.5, 0.8, 0.88, 0.92, 0.92]

    /// Pixels of cast shadow for each pixel of a person's height: a low sun throws one nearly as
    /// long as the figure is tall, the lamps throw two short ones.
    var lowSunShadowSlope = 0.9
    var morningShadowSlope = 0.5
    var middayShadowSlope = 0.1
    var lampShadowSlope = 0.34
    /// How far up the screen a shadow climbs as it goes, and above what height its far end
    /// dithers out. A shadow that never softens reads as a painted stripe.
    var lowSunShadowRise = 0.22
    var morningShadowRise = 0.16
    var flatShadowRise = 0.1
    var lowSunShadowSoftFrom = 62.0
    var highSunShadowSoftFrom = 99.0

    // MARK: The three things the low light does to the field (step 3 draws them)

    /// The ground mist at `dawn`: these rows, thickest at `mistPeak`, and this much of the
    /// densest row actually painted.
    var mistRows = 99.0...120.0
    var mistPeak = 107.0
    var mistStrength = 0.62
    /// The low sun's two marks on the outfield grass: one stand's shadow and the rake of light
    /// on the rest, both inside these rows and nowhere near the zone.
    var lowSunRows = 108.0...132.0
    /// The pool of light at `night`: the grass goes dark this far in from each canvas edge.
    var nightPoolInsetPixels = 96.0
    var nightPoolFalloffPixels = 64.0

    static let standard = LookRules()
}

/// Everything one phase paints with: three palette lines by role, where its light comes from, and
/// the handful of switches a phase carries (DESIGN.md §20 "The look, piece by piece").
///
/// The tables are copied from `prototypes/04-golden-hour/golden.py`, which is the oracle —
/// `docs/palette.md`'s phase tables were written out of that file, and `scripts/check-looks.py`
/// reads both and fails on any difference. A scene asks `Look.of(machine.phase)` and takes every
/// colour it draws from the answer by role; it never picks a hex of its own.
struct Look {

    /// One stop of a sky: the row it sits on, in the 0…96 space of the at-bat camera, and the
    /// colour there. Two stops of the same colour make a flat band; two that differ make an
    /// ordered-dither blend across the rows between them.
    typealias Stop = (y: Double, colour: Palette.RGBA8)

    /// A sun or a moon: where its middle sits in the 320-wide design column, the radius of the
    /// disc and the radius of the dithered halo around it.
    struct Disc {
        let x: Double
        let y: Double
        let radius: Double
        let halo: Double

        /// Where the middle of it falls on a canvas wider than the column. Measured from the
        /// nearer edge, so a sun that sits in the corner of the mock is still in the corner of a
        /// phone (§20 "Canvases wider than 320").
        func x(width: Double) -> Double { x <= 160 ? x : width - (320 - x) }
    }

    /// One cast shadow: pixels sideways per pixel of height, pixels up the screen per pixel of
    /// height, and the height above which its far end dithers out. The lamps throw two.
    struct Shadow: Equatable {
        let slope: Double
        let rise: Double
        let softFrom: Double
    }

    /// The phase this look belongs to, and the name `golden.py` calls it by.
    let phase: DayPhase

    // MARK: The sky
    let skyAtBat: [Stop]
    /// The flight camera's own stops, where they differ. Only `dawn` has them: that camera looks
    /// across the field away from the sunrise, so it sees a pink band over a blue one and no sun.
    let skyFlight: [Stop]?
    /// The disc and its halo — a sun in four phases, the moon at `night`, nothing at `midday`
    /// (it is out of frame, above) or at `twilight` (it is under the horizon).
    let sun: [Palette.RGBA8]?
    /// Where it sits at bat, and in the flight camera. A `midday` or `twilight` look has neither.
    let sunAtBat: Disc?
    let sunFlight: Disc?
    /// Whether that flight-camera disc moves with the ground. The low sun does — it is a thing in
    /// the park, behind the hills — and the moon does not.
    let sunFlightMovesWithGround: Bool

    // MARK: Everything in the sky that is not the sky
    /// top, body, lower, underside
    let cloud: [Palette.RGBA8]
    /// Cumulus that the light shades, rather than a flat streak with dithered ends.
    let cumulus: Bool
    let bird: Palette.RGBA8
    /// body, belly
    let blimp: [Palette.RGBA8]

    // MARK: The horizon and the stands
    /// far, near
    let hill: [Palette.RGBA8]
    /// shade, body, lit rim
    let tree: [Palette.RGBA8]
    /// mass, lip, under the lip
    let standLit: [Palette.RGBA8]
    let standDim: [Palette.RGBA8]
    let headsLit: [Palette.RGBA8]
    let headsDim: [Palette.RGBA8]
    let shirtsLit: [Palette.RGBA8]
    let shirtsDim: [Palette.RGBA8]
    /// mass, roof edge, lamp, column
    let deck: [Palette.RGBA8]
    /// pole, outer bloom, inner bloom, lamp
    let tower: [Palette.RGBA8]

    // MARK: The field
    /// lit top, face, foot
    let wall: [Palette.RGBA8]
    /// The grass a low sun rakes. Only `dawn` and `goldenHour` have one.
    let grassSun: Palette.RGBA8?
    /// light, body, shade, deep shade
    let dirt: [Palette.RGBA8]
    /// The ground mist. `dawn` only.
    let mist: Palette.RGBA8?
    /// The grass goes dark toward the canvas edges. `night` only.
    let nightPool: Bool

    // MARK: The people, four tones from one light
    let red: [Palette.RGBA8]
    let grey: [Palette.RGBA8]
    let skin: [Palette.RGBA8]
    let wood: [Palette.RGBA8]
    let glove: [Palette.RGBA8]
    let hair: Palette.RGBA8
    /// With the lamps on a figure is lit from everywhere at once, so the pitcher's stamp takes
    /// its body tone where it would take its lit one. `golden.pitcher`'s `flat`.
    let flatFigures: Bool

    // MARK: The furniture
    /// lit, shaded
    let pole: [Palette.RGBA8]
    /// frame, lit edge, face
    let board: [Palette.RGBA8]
    let ballHi: Palette.RGBA8
    let ballLo: Palette.RGBA8

    // MARK: Where the light comes from
    /// A unit vector, x positive to the right and y positive *down* the screen, so a sun in the
    /// top right is `(0.7, -0.7)`.
    let light: (x: Double, y: Double)
    /// The two cuts in a four-tone ramp: above the first a surface is lit, below the second it is
    /// in shade (`Sprite.part`).
    let cuts: (lit: Double, dark: Double)
    let shadows: [Shadow]
    /// Which wing of the stands stands in shadow: -1 the left, +1 the right, 0 neither. It is
    /// also the side the low sun comes from, so the same number aims its wash on the grass.
    let dimSide: Int
    let crowdShare: Double

    /// Whether the park's lamps are lit — the clock's answer, from the phase itself.
    var lampsOn: Bool { phase.lampsOn }

    /// Whether the disc in the sky is the moon rather than the sun. It matters because the moon
    /// is the *park's*: one park in sixteen has one at all, and where it hangs, how big it is and
    /// which way it is bitten are seeded (§17). `sunAtBat` and `sunFlight` keep the prototype's
    /// numbers for it so the phase line is a complete copy of `golden.py`, but the scene draws
    /// `Scenery.moon` instead — a park with no moon has a bare sky, which is the point.
    var sunIsMoon: Bool { phase == .night }

    /// The stand colours for one wing: the shaded pair on `dimSide`, the lit pair everywhere else.
    func stand(side: Int) -> [Palette.RGBA8] { side == dimSide ? standDim : standLit }
    func heads(side: Int) -> [Palette.RGBA8] { side == dimSide ? headsDim : headsLit }
    func shirts(side: Int) -> [Palette.RGBA8] { side == dimSide ? shirtsDim : shirtsLit }

    /// The stops this camera draws, and the row they end on.
    func skyStops(flightCamera: Bool) -> [Stop] {
        flightCamera ? (skyFlight ?? skyAtBat) : skyAtBat
    }

    /// The look for a phase. Six constants and a switch: nothing here is computed, because every
    /// number in it was chosen by eye in the mock.
    static func of(_ phase: DayPhase) -> Look {
        switch phase {
        case .dawn: return dawn
        case .morning: return morning
        case .midday: return midday
        case .goldenHour: return goldenHour
        case .twilight: return twilight
        case .night: return night
        }
    }
}

// MARK: - The six lines (golden.py's DAWN, MORNING, DAY, DUSK, TWILIGHT, NIGHT)

extension Look {

    /// `golden.DAWN`. Forty minutes before sunrise: a low sun behind the plate on the right, long
    /// shadows to the left, the right wing in its own shadow, and mist on the grass.
    static let dawn = Look(
        phase: .dawn,
        skyAtBat: [
            (0, c(0x222266)), (8, c(0x222266)), (24, c(0x444488)), (30, c(0x444488)),
            (46, c(0x8888CC)), (50, c(0x8888CC)), (62, c(0xCCAACC)), (66, c(0xCCAACC)),
            (76, c(0xEEAAAA)), (79, c(0xEEAAAA)), (88, c(0xEECCAA)), (90, c(0xEECCAA)),
            (96, c(0xEEEECC))
        ],
        skyFlight: [
            (0, c(0x444488)), (10, c(0x444488)), (30, c(0x8888CC)), (38, c(0x8888CC)),
            (56, c(0xCCAACC)), (62, c(0xCCAACC)), (74, c(0xEEAAAA)), (79, c(0xEEAAAA)),
            (88, c(0x8888AA)), (91, c(0x8888AA)), (96, c(0x6666AA))
        ],
        sun: [c(0xEEEECC), c(0xEECCAA)],
        sunAtBat: Disc(x: 293, y: 63, radius: 9, halo: 27),
        sunFlight: nil,
        sunFlightMovesWithGround: false,
        cloud: [c(0x8888CC), c(0xCCAACC), c(0xEEAAAA), c(0xEECCAA)],
        cumulus: false,
        bird: c(0xEECCAA),
        blimp: [c(0xEECCCC), c(0xCCAACC)],
        hill: [c(0x8888AA), c(0x666688)],
        tree: [c(0x224444), c(0x226644), c(0x88CC88)],
        standLit: [c(0x666688), c(0xEECCCC), c(0x444466)],
        standDim: [c(0x444466), c(0x8888AA), c(0x222244)],
        headsLit: [c(0xEEAA88), c(0xEECCAA), c(0xCC8866)],
        headsDim: [c(0x884444), c(0xCC8866)],
        shirtsLit: [c(0xCC2222), c(0xAAAACC), c(0xCCAACC), c(0xEEAAAA), c(0x8888AA), c(0x6666AA)],
        shirtsDim: [c(0x660022), c(0x444488), c(0x666688), c(0x6666AA)],
        deck: [c(0x666688), c(0xEECCCC), c(0xEEEECC), c(0x444466)],
        tower: [c(0x446688), c(0x444488), c(0x6666AA), c(0xEEEEAA)],
        wall: [c(0x44AA66), c(0x226644), c(0x004422)],
        grassSun: c(0x66AA44),
        dirt: [c(0xEEAA66), c(0xCC8844), c(0xAA6622), c(0x884422)],
        mist: c(0xCCCCEE),
        nightPool: false,
        red: [c(0x660022), c(0xAA2222), c(0xCC2222), c(0xEE8888)],
        grey: [c(0x444466), c(0x666688), c(0x8888AA), c(0xCCCCEE)],
        skin: [c(0x884444), c(0xCC8866), c(0xEEAA88), c(0xEECCCC)],
        wood: [c(0x442222), c(0x884422), c(0xAA8844), c(0xEECC88)],
        glove: [c(0x666688), c(0xAAAACC), c(0xEEEEEE), c(0xEEEEEE)],
        hair: c(0x442222),
        flatFigures: false,
        pole: [c(0xEEEE88), c(0xCCAA22)],
        board: [c(0x444466), c(0xEECCCC), c(0x222244)],
        ballHi: c(0xEEEECC),
        ballLo: c(0xAAAACC),
        light: (0.85, -0.5),
        cuts: (0.3, -0.35),
        shadows: [Shadow(slope: LookRules.standard.lowSunShadowSlope,
                         rise: LookRules.standard.lowSunShadowRise,
                         softFrom: LookRules.standard.lowSunShadowSoftFrom)],
        dimSide: 1,
        crowdShare: LookRules.standard.crowdShare[0])

    /// `golden.MORNING`. Fifty minutes after sunrise: the sun in frame, top right, and cumulus.
    static let morning = Look(
        phase: .morning,
        skyAtBat: [
            (0, c(0x4466CC)), (24, c(0x4466CC)), (46, c(0x66AAEE)), (54, c(0x66AAEE)),
            (72, c(0xAACCEE)), (78, c(0xAACCEE)), (90, c(0xCCEEEE)), (96, c(0xEEEECC))
        ],
        skyFlight: nil,
        sun: [c(0xEEEECC), c(0xAACCEE)],
        sunAtBat: Disc(x: 286, y: 22, radius: 7, halo: 16),
        sunFlight: nil,
        sunFlightMovesWithGround: false,
        cloud: [c(0xEEEEEE), c(0xEEEEEE), c(0xAACCEE), c(0x88AACC)],
        cumulus: true,
        bird: c(0x222244),
        blimp: [c(0xEEEEEE), c(0xAACCEE)],
        hill: [c(0x88AACC), c(0x66AA88)],
        tree: [c(0x116633), c(0x228844), c(0x66CC44)],
        standLit: [c(0x666688), c(0xEEEECC), c(0x444466)],
        standDim: [c(0x666688), c(0xEEEECC), c(0x444466)],
        headsLit: [c(0xEEAA88), c(0xEECCAA), c(0xCC8866), c(0x884422)],
        headsDim: [c(0xEEAA88), c(0xEECCAA), c(0xCC8866), c(0x884422)],
        shirtsLit: [c(0xCC2222), c(0xEEEEEE), c(0x4466CC), c(0xEEDD22), c(0x66CC44), c(0xEE6666),
                    c(0xAAAACC)],
        shirtsDim: [c(0xCC2222), c(0xEEEEEE), c(0x4466CC), c(0xEEDD22), c(0x66CC44), c(0xEE6666),
                    c(0xAAAACC)],
        deck: [c(0x8888AA), c(0xEEEEEE), c(0x66AAEE), c(0x666688)],
        tower: [c(0x446688), c(0x444488), c(0x6666AA), c(0xEEEEAA)],
        wall: [c(0x44AA66), c(0x226644), c(0x004422)],
        grassSun: nil,
        dirt: [c(0xEEAA66), c(0xCC8844), c(0xAA6622), c(0x884422)],
        mist: nil,
        nightPool: false,
        red: [c(0x880022), c(0xAA2222), c(0xCC2222), c(0xEE6666)],
        grey: [c(0x666688), c(0x8888AA), c(0xAAAACC), c(0xEEEEEE)],
        skin: [c(0xAA6644), c(0xCC8866), c(0xEEAA88), c(0xEECCAA)],
        wood: [c(0x664422), c(0xAA6622), c(0xCC8844), c(0xEECC88)],
        glove: [c(0x8888AA), c(0xAAAACC), c(0xEEEEEE), c(0xEEEEEE)],
        hair: c(0x442222),
        flatFigures: false,
        pole: [c(0xEEEE88), c(0xCCAA22)],
        board: [c(0x444466), c(0xEEEEEE), c(0x222244)],
        ballHi: c(0xEEEECC),
        ballLo: c(0xAAAACC),
        light: (0.7, -0.7),
        cuts: (0.35, -0.3),
        shadows: [Shadow(slope: LookRules.standard.morningShadowSlope,
                         rise: LookRules.standard.morningShadowRise,
                         softFrom: LookRules.standard.highSunShadowSoftFrom)],
        dimSide: 0,
        crowdShare: LookRules.standard.crowdShare[1])

    /// `golden.DAY`. Two hours before solar noon: the sun out of frame above, short shadows,
    /// nothing in shadow anywhere.
    static let midday = Look(
        phase: .midday,
        skyAtBat: [
            (0, c(0x4466CC)), (30, c(0x4466CC)), (50, c(0x66AAEE)), (60, c(0x66AAEE)),
            (78, c(0xAACCEE)), (86, c(0xAACCEE)), (96, c(0xCCEEEE))
        ],
        skyFlight: nil,
        sun: nil,
        sunAtBat: nil,
        sunFlight: nil,
        sunFlightMovesWithGround: false,
        cloud: [c(0xEEEEEE), c(0xEEEEEE), c(0xAACCEE), c(0x88AACC)],
        cumulus: true,
        bird: c(0x222244),
        blimp: [c(0xEEEEEE), c(0xAACCEE)],
        hill: [c(0x88AACC), c(0x66AA88)],
        tree: [c(0x116633), c(0x228844), c(0x66CC44)],
        standLit: [c(0x666688), c(0xEEEEEE), c(0x444466)],
        standDim: [c(0x666688), c(0xEEEEEE), c(0x444466)],
        headsLit: [c(0xEEAA88), c(0xEECCAA), c(0xCC8866), c(0x884422)],
        headsDim: [c(0xEEAA88), c(0xEECCAA), c(0xCC8866), c(0x884422)],
        shirtsLit: [c(0xCC2222), c(0xEEEEEE), c(0x4466CC), c(0xEEDD22), c(0x66CC44), c(0xEE6666),
                    c(0xAAAACC)],
        shirtsDim: [c(0xCC2222), c(0xEEEEEE), c(0x4466CC), c(0xEEDD22), c(0x66CC44), c(0xEE6666),
                    c(0xAAAACC)],
        deck: [c(0x8888AA), c(0xEEEEEE), c(0x66AAEE), c(0x666688)],
        tower: [c(0x446688), c(0x444488), c(0x6666AA), c(0xEEEEAA)],
        wall: [c(0x44AA66), c(0x226644), c(0x004422)],
        grassSun: nil,
        dirt: [c(0xEEAA66), c(0xCC8844), c(0xAA6622), c(0x884422)],
        mist: nil,
        nightPool: false,
        red: [c(0x880022), c(0xAA2222), c(0xCC2222), c(0xEE6666)],
        grey: [c(0x666688), c(0x8888AA), c(0xAAAACC), c(0xEEEEEE)],
        skin: [c(0xAA6644), c(0xCC8866), c(0xEEAA88), c(0xEECCAA)],
        wood: [c(0x664422), c(0xAA6622), c(0xCC8844), c(0xEECC88)],
        glove: [c(0x8888AA), c(0xAAAACC), c(0xEEEEEE), c(0xEEEEEE)],
        hair: c(0x442222),
        flatFigures: false,
        pole: [c(0xEEEE88), c(0xCCAA22)],
        board: [c(0x444466), c(0xEEEEEE), c(0x222244)],
        ballHi: c(0xEEEEEE),
        ballLo: c(0xAAAACC),
        light: (-0.15, -0.99),
        cuts: (0.35, -0.3),
        shadows: [Shadow(slope: -LookRules.standard.middayShadowSlope,
                         rise: LookRules.standard.flatShadowRise,
                         softFrom: LookRules.standard.highSunShadowSoftFrom)],
        dimSide: 0,
        crowdShare: LookRules.standard.crowdShare[2])

    /// `golden.DUSK`. Ninety minutes before sunset: a low sun on the left, long shadows to the
    /// right, the left wing in its own shadow — and the one phase the flight camera looks
    /// straight into the sun.
    static let goldenHour = Look(
        phase: .goldenHour,
        skyAtBat: [
            (0, c(0x222266)), (8, c(0x222266)), (22, c(0x444488)), (28, c(0x444488)),
            (42, c(0x6666AA)), (46, c(0x6666AA)), (58, c(0xAA88AA)), (61, c(0xAA88AA)),
            (70, c(0xCC8888)), (73, c(0xCC8888)), (81, c(0xEEAA88)), (84, c(0xEEAA88)),
            (92, c(0xEECC88)), (96, c(0xEECC88))
        ],
        skyFlight: nil,
        sun: [c(0xEEEEAA), c(0xEECC88)],
        sunAtBat: Disc(x: 27, y: 63, radius: 9, halo: 27),
        // Reckoned up from the ground, not down from the top: this one is a thing in the park,
        // sitting behind the hills, and the close camera lifts it with them.
        sunFlight: Disc(x: 58, y: 27, radius: 11, halo: 34),
        sunFlightMovesWithGround: true,
        cloud: [c(0xAA88AA), c(0xCC8888), c(0xEEAA88), c(0xEECC88)],
        cumulus: false,
        bird: c(0xEECC88),
        blimp: [c(0xEECC88), c(0xCC8888)],
        hill: [c(0x886688), c(0x664466)],
        tree: [c(0x224444), c(0x226644), c(0xCCAA66)],
        standLit: [c(0x666688), c(0xEECC88), c(0x444466)],
        standDim: [c(0x444466), c(0x886688), c(0x222244)],
        headsLit: [c(0xEEAA88), c(0xEECCAA), c(0xCC8866)],
        headsDim: [c(0x884444), c(0xCC8866)],
        shirtsLit: [c(0xCC2222), c(0xEE8866), c(0xAAAACC), c(0xCC8888), c(0xEECC88), c(0x8888AA),
                    c(0x6666AA)],
        shirtsDim: [c(0x660022), c(0x444488), c(0x666688), c(0x6666AA), c(0x664466)],
        deck: [c(0x664466), c(0xEECC88), c(0xEEEEAA), c(0x444466)],
        tower: [c(0x446688), c(0x444488), c(0x6666AA), c(0xEEEEAA)],
        wall: [c(0x44AA66), c(0x226644), c(0x004422)],
        grassSun: c(0x66AA44),
        dirt: [c(0xEEAA66), c(0xCC8844), c(0xAA6622), c(0x884422)],
        mist: nil,
        nightPool: false,
        red: [c(0x660022), c(0xAA2222), c(0xCC2222), c(0xEE8866)],
        grey: [c(0x444466), c(0x666688), c(0x8888AA), c(0xCCAAAA)],
        skin: [c(0x884444), c(0xCC8866), c(0xEEAA88), c(0xEECCAA)],
        wood: [c(0x442222), c(0x884422), c(0xAA8844), c(0xEECC88)],
        glove: [c(0x666688), c(0xAAAACC), c(0xEEEEEE), c(0xEEEEEE)],
        hair: c(0x442222),
        flatFigures: false,
        pole: [c(0xEEEE88), c(0xCCAA22)],
        board: [c(0x444466), c(0xEECC88), c(0x222244)],
        ballHi: c(0xEEEE88),
        ballLo: c(0xAAAACC),
        light: (-0.85, -0.5),
        cuts: (0.3, -0.35),
        shadows: [Shadow(slope: -LookRules.standard.lowSunShadowSlope,
                         rise: LookRules.standard.lowSunShadowRise,
                         softFrom: LookRules.standard.lowSunShadowSoftFrom)],
        dimSide: -1,
        crowdShare: LookRules.standard.crowdShare[3])

    /// `golden.TWILIGHT`. Sunset: the sun under the horizon, the lamps on, the first stars, and
    /// nothing in the sky to light the stands but the lamps themselves.
    static let twilight = Look(
        phase: .twilight,
        skyAtBat: [
            (0, c(0x000022)), (14, c(0x000022)), (34, c(0x222244)), (40, c(0x222244)),
            (58, c(0x222266)), (62, c(0x222266)), (76, c(0x444488)), (80, c(0x444488)),
            (88, c(0x886688)), (90, c(0x886688)), (96, c(0xCC8866))
        ],
        skyFlight: nil,
        sun: nil,
        sunAtBat: nil,
        sunFlight: nil,
        sunFlightMovesWithGround: false,
        cloud: [c(0x444466), c(0x664466), c(0x886688), c(0xCC8866)],
        cumulus: false,
        bird: c(0x8888AA),
        blimp: [c(0x8888AA), c(0x444466)],
        hill: [c(0x444466), c(0x222244)],
        tree: [c(0x002222), c(0x224444), c(0x446666)],
        standLit: [c(0x444466), c(0xAAAACC), c(0x222244)],
        standDim: [c(0x444466), c(0xAAAACC), c(0x222244)],
        headsLit: [c(0xEEAA88), c(0xEECCAA), c(0xCC8866)],
        headsDim: [c(0xEEAA88), c(0xEECCAA), c(0xCC8866)],
        shirtsLit: [c(0xCC2222), c(0xAAAACC), c(0xEEEEEE), c(0x4466CC), c(0xEEDD22), c(0x666688),
                    c(0xEE6666)],
        shirtsDim: [c(0xCC2222), c(0xAAAACC), c(0xEEEEEE), c(0x4466CC), c(0xEEDD22), c(0x666688),
                    c(0xEE6666)],
        deck: [c(0x222244), c(0xAAAACC), c(0xEEEEAA), c(0x222244)],
        tower: [c(0x446688), c(0x444488), c(0x6666AA), c(0xEEEEAA)],
        wall: [c(0x44AA66), c(0x226644), c(0x004422)],
        grassSun: nil,
        dirt: [c(0xEEAA66), c(0xCC8844), c(0xAA6622), c(0x884422)],
        mist: nil,
        nightPool: false,
        red: [c(0x660022), c(0xAA2222), c(0xCC2222), c(0xEE6666)],
        grey: [c(0x444466), c(0x8888AA), c(0xAAAACC), c(0xEEEEEE)],
        skin: [c(0x884444), c(0xCC8866), c(0xEEAA88), c(0xEECCAA)],
        wood: [c(0x442222), c(0x884422), c(0xAA8844), c(0xEECC88)],
        glove: [c(0x666688), c(0xAAAACC), c(0xEEEEEE), c(0xEEEEEE)],
        hair: c(0x442222),
        flatFigures: true,
        pole: [c(0xEEEE88), c(0xCCAA22)],
        board: [c(0x222244), c(0xAAAACC), c(0x000022)],
        ballHi: c(0xEEEEEE),
        ballLo: c(0xAAAACC),
        light: (-0.3, -0.95),
        cuts: (0.35, -0.4),
        shadows: [Shadow(slope: -LookRules.standard.lampShadowSlope,
                         rise: LookRules.standard.flatShadowRise,
                         softFrom: LookRules.standard.highSunShadowSoftFrom),
                  Shadow(slope: LookRules.standard.lampShadowSlope,
                         rise: LookRules.standard.flatShadowRise,
                         softFrom: LookRules.standard.highSunShadowSoftFrom)],
        dimSide: 0,
        crowdShare: LookRules.standard.crowdShare[4])

    /// `golden.NIGHT`. Forty minutes after sunset: all forty stars, a moon in the parks that have
    /// one, the lamps at full blaze and the corners of the field gone dark.
    static let night = Look(
        phase: .night,
        skyAtBat: [
            (0, c(0x000022)), (34, c(0x000022)), (54, c(0x222244)), (62, c(0x222244)),
            (84, c(0x222266)), (90, c(0x222266)), (96, c(0x444488))
        ],
        skyFlight: nil,
        sun: [c(0xEEEECC), c(0x444488)],
        sunAtBat: Disc(x: 262, y: 26, radius: 7, halo: 17),
        sunFlight: Disc(x: 230, y: 40, radius: 8, halo: 20),
        sunFlightMovesWithGround: false,
        cloud: [c(0x666688), c(0x444488), c(0x444466), c(0x222244)],
        cumulus: false,
        bird: c(0x8888AA),
        blimp: [c(0x8888AA), c(0x444466)],
        hill: [c(0x222244), c(0x000022)],
        tree: [c(0x002222), c(0x224444), c(0x446666)],
        standLit: [c(0x444466), c(0xAAAACC), c(0x222244)],
        standDim: [c(0x444466), c(0xAAAACC), c(0x222244)],
        headsLit: [c(0xEEAA88), c(0xEECCAA), c(0xCC8866)],
        headsDim: [c(0xEEAA88), c(0xEECCAA), c(0xCC8866)],
        shirtsLit: [c(0xCC2222), c(0xAAAACC), c(0xEEEEEE), c(0x4466CC), c(0xEEDD22), c(0x666688),
                    c(0xEE6666)],
        shirtsDim: [c(0xCC2222), c(0xAAAACC), c(0xEEEEEE), c(0x4466CC), c(0xEEDD22), c(0x666688),
                    c(0xEE6666)],
        deck: [c(0x222244), c(0xAAAACC), c(0xEEEEAA), c(0x222244)],
        tower: [c(0x446688), c(0x444488), c(0x6666AA), c(0xEEEEAA)],
        wall: [c(0x44AA66), c(0x226644), c(0x004422)],
        grassSun: nil,
        dirt: [c(0xEEAA66), c(0xCC8844), c(0xAA6622), c(0x884422)],
        mist: nil,
        nightPool: true,
        red: [c(0x660022), c(0xAA2222), c(0xCC2222), c(0xEE6666)],
        grey: [c(0x444466), c(0x8888AA), c(0xAAAACC), c(0xEEEEEE)],
        skin: [c(0x884444), c(0xCC8866), c(0xEEAA88), c(0xEECCAA)],
        wood: [c(0x442222), c(0x884422), c(0xAA8844), c(0xEECC88)],
        glove: [c(0x666688), c(0xAAAACC), c(0xEEEEEE), c(0xEEEEEE)],
        hair: c(0x442222),
        flatFigures: true,
        pole: [c(0xEEEE88), c(0xCCAA22)],
        board: [c(0x222244), c(0xAAAACC), c(0x000022)],
        ballHi: c(0xEEEEEE),
        ballLo: c(0xAAAACC),
        light: (-0.3, -0.95),
        cuts: (0.35, -0.4),
        shadows: [Shadow(slope: -LookRules.standard.lampShadowSlope,
                         rise: LookRules.standard.flatShadowRise,
                         softFrom: LookRules.standard.highSunShadowSoftFrom),
                  Shadow(slope: LookRules.standard.lampShadowSlope,
                         rise: LookRules.standard.flatShadowRise,
                         softFrom: LookRules.standard.highSunShadowSoftFrom)],
        dimSide: 0,
        crowdShare: LookRules.standard.crowdShare[5])
}
