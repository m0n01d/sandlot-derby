import Foundation
import DerbyCore

/// The people's own numbers — the App half of §20's "Batter at bat", "Pitcher" and "Cast
/// shadows" rows. Every one of them is a pixel or a fraction; the colours are the phase's
/// (`Look.red`, `.grey`, `.skin`, `.wood`, `.glove`, `.hair`).
struct PeopleRules {

    // MARK: The batter's rig (`golden.batter`)

    /// The sprite the rig is drawn into, and where his feet sit inside it. It has to hold the
    /// contact pose's bat, whose tip reaches 63 px to the right of his feet and 91 px above
    /// them in the stance, so the canvas is wide and the origin is low and left of centre.
    var batterWidth = 128
    var batterHeight = 104
    var batterOriginX = 50
    var batterOriginY = 100

    /// The bat: the handle's radius at the hands, the barrel's at the tip, how far behind the
    /// hands the knob sits and how much wider than the handle it is (`variants.bat_part`).
    var batHandleRadius = 1.0
    var batBarrelRadius = 2.6
    var batKnobNear = 1.5
    var batKnobFar = 2.5
    var batKnobExtra = 0.8
    /// Pine tar: two dark pixels at each of these fractions along the bat from the hands. Six
    /// smudges is what reads as a taped grip at this size; more and the handle goes black.
    var pineTarAlong = [0.12, 0.16, 0.2, 0.24, 0.28, 0.32]

    // MARK: The pitcher's stamps (`golden.PITCH`)

    /// His sprite. Only 15×20 of it carries paint; the rest is the margin the shadow scan walks.
    var pitcherWidth = 44
    var pitcherHeight = 44
    var pitcherOriginX = 16
    var pitcherOriginY = 40
    /// Where the stamp's left column sits relative to his feet. The rows are written so the
    /// bottom one is the ground, so the top is simply `-rows.count`.
    var pitcherStampX = -5
    /// A light further to the right than this flips which side of the stamp is modelled light —
    /// the pose does not change, only the shading (`golden.pitcher`).
    var lightFromTheRight = 0.3

    // MARK: Cast shadows (`golden.cast`)

    /// The pitcher stands on a mound eight pixels across, so his shadow has nowhere near the
    /// room the batter's has: its far end starts dithering this high up the figure rather than
    /// at the phase's own height, which is what keeps it on the dirt.
    var pitcherShadowSoftFrom = 14.0

    static let standard = PeopleRules()
}

/// One pose of the batter, in sprite-local pixels measured from his feet, y up the screen being
/// negative (`golden.POSES`). Nine points are the whole rig: the rest is hung off them.
struct BatterPose {
    let kneeL: (x: Double, y: Double)
    let ankleL: (x: Double, y: Double)
    let kneeR: (x: Double, y: Double)
    let ankleR: (x: Double, y: Double)
    /// The near shoulder, the near elbow, and where both hands meet on the bat.
    let shoulder: (x: Double, y: Double)
    let elbow: (x: Double, y: Double)
    let hands: (x: Double, y: Double)
    /// The end of the bat, and the far shoulder the far arm reaches from.
    let batTip: (x: Double, y: Double)
    let farShoulder: (x: Double, y: Double)

    /// Stance, contact, miss — the three the at-bat camera asks for, in `AtBatScene`'s own order.
    static let all: [BatterPose] = [
        BatterPose(kneeL: (-8, -16), ankleL: (-9, -4), kneeR: (9, -17), ankleR: (10, -4),
                   shoulder: (5, -51), elbow: (11, -44), hands: (14, -55),
                   batTip: (10, -91), farShoulder: (-3, -50)),
        BatterPose(kneeL: (-5, -16), ankleL: (-8, -4), kneeR: (11, -17), ankleR: (12, -4),
                   shoulder: (6, -50), elbow: (14, -46), hands: (21, -43),
                   batTip: (63, -58), farShoulder: (-2, -49)),
        BatterPose(kneeL: (-6, -17), ankleL: (-8, -4), kneeR: (9, -17), ankleR: (10, -4),
                   shoulder: (-3, -50), elbow: (-10, -44), hands: (-16, -40),
                   batTip: (-41, -57), farShoulder: (4, -49))
    ]
}

/// The shape of one figure's cast shadow: every ground pixel it darkens, as an offset from the
/// figure's feet. Working it out means walking the whole sprite once per `Look.Shadow`, which is
/// far too much to do twice a frame — and it depends on nothing but the pose and the phase, so
/// it is worked out once and kept (§20 "Layers and speed").
struct ShadowStamp {
    /// One darkened ground pixel, as an offset from the figure's feet.
    struct Offset: Hashable {
        let dx: Int
        let dy: Int
    }

    let offsets: [Offset]
}

/// The people, drawn from one light (DESIGN.md §20). A port of `golden.batter`, `golden.PITCH` /
/// `golden.pitcher` and `golden.cast`, static functions over a `ShadedSprite` or a `PixelCanvas`
/// so a scene can point them at a frame or at an off-screen copy of one.
enum PeopleArt {

    // MARK: - The batter

    /// His rig: capsules for the limbs, ellipses for the head and the glove, polygons for the
    /// torso and the helmet, each shaded off `look.light` into four tones and each drawing a
    /// darker contour on the part below it. No outer outline anywhere — §20 is explicit, and a
    /// figure that has one stops being lit and starts being a sticker.
    static func batter(pose frame: Int, look: Look, rules: PeopleRules = .standard) -> ShadedSprite {
        let s = ShadedSprite(width: rules.batterWidth, height: rules.batterHeight,
                             ox: rules.batterOriginX, oy: rules.batterOriginY,
                             light: look.light, cuts: look.cuts)
        let p = BatterPose.all[min(max(0, frame), BatterPose.all.count - 1)]
        let red = look.red, grey = look.grey, skin = look.skin
        let ink = Palette.ink

        // The shoes first, so everything above lands on top of them. A dark sole with one grey
        // upper is the whole shoe at this size; the toe cap is the one pixel of light on it.
        let shoe = [ink, ink, grey[0], grey[2]]
        for a in [p.ankleL, p.ankleR] {
            s.part(Mask.ellipse(cx: a.x + 1.5, cy: a.y + 2, rx: 5.8, ry: 2.5), shoe, contour: ink)
            s.set(Int(a.x + 5), Int(a.y + 1), grey[2])
        }

        // Each leg: a red sock, the flannel over it, the thigh, a stripe down the outside and a
        // fold behind the knee. The hips are fixed — a batter's stance is all knees and ankles.
        let hipL = (x: -4.0, y: -31.0), hipR = (x: 4.0, y: -31.0)
        for (hip, knee, ankle) in [(hipL, p.kneeL, p.ankleL), (hipR, p.kneeR, p.ankleR)] {
            s.part(Mask.capsule(x0: knee.x, y0: knee.y, r0: 3.6, x1: ankle.x, y1: ankle.y, r1: 2.7),
                   red, contour: red[0])
            let mid = (x: (knee.x + ankle.x) / 2, y: (knee.y + ankle.y) / 2 - 1)
            s.part(Mask.capsule(x0: knee.x, y0: knee.y, r0: 4.0, x1: mid.x, y1: mid.y, r1: 3.3),
                   grey, contour: grey[0])
            s.part(Mask.capsule(x0: hip.x, y0: hip.y, r0: 5.3, x1: knee.x, y1: knee.y, r1: 4.1),
                   grey, contour: grey[0])
            s.canvas.line(hip.x + Double(s.ox), hip.y + Double(s.oy) + 2,
                          knee.x + Double(s.ox), knee.y + Double(s.oy), red[1])
            s.canvas.line(knee.x + Double(s.ox), knee.y + Double(s.oy),
                          mid.x + Double(s.ox), mid.y + Double(s.oy), red[1])
            s.set(Int(knee.x) - 3, Int(knee.y) - 1, grey[0])
            s.set(Int(knee.x) - 2, Int(knee.y), grey[0])
        }

        // The torso, the shoulders across the top of it, the belt and its buckle, his number and
        // the undershirt showing at the collar.
        s.part(Mask.poly([(-8, -54), (-2, -57), (7, -55), (9, -44), (7, -30), (-7, -30), (-9, -42)]),
               grey, contour: grey[0])
        s.part(Mask.ellipse(cx: -0.5, cy: -53, rx: 8.6, ry: 3.6), grey)
        s.part(Mask.poly([(-7.5, -33), (7.5, -33), (7.5, -30), (-7.5, -30)]), flat: ink)
        s.set(5, -32, Palette.score)
        s.set(6, -32, Palette.score)
        s.stamp(["RRR", "..R", ".R.", ".R.", ".R."], legend: ["R": red[1]], x: -6, y: -43)
        s.set(1, -55, red[1]); s.set(2, -54, red[1]); s.set(3, -55, red[1])

        // The far arm, reaching across to the bat. Three tones and no rim: it is the arm in
        // shadow, and a highlight on it would put two lights in the park.
        s.part(Mask.capsule(x0: p.farShoulder.x, y0: p.farShoulder.y, r0: 3.0,
                            x1: p.hands.x, y1: p.hands.y + 3, r1: 2.2),
               [grey[0], grey[0], grey[1]], contour: grey[0])

        bat(on: s, from: (p.hands.x, p.hands.y + 2), to: (p.batTip.x, p.batTip.y),
            look: look, rules: rules)

        // The neck, the head, the hair at the nape, the helmet with its ear flap and brim, the
        // ear hole, the glint off the helmet and the face.
        s.part(Mask.poly([(0, -58), (5, -58), (5, -54), (0, -54)]), skin)
        s.part(Mask.ellipse(cx: 3, cy: -61.5, rx: 5.2, ry: 5.6), skin, contour: skin[0])
        s.set(-1, -57, look.hair); s.set(0, -57, look.hair); s.set(-1, -56, look.hair)
        s.part(Mask.ellipse(cx: 2, cy: -63, rx: 7, ry: 6).filter { $0.y < -61 },
               red, contour: red[0])
        s.part(Mask.poly([(-4, -62), (1, -62), (1, -56), (-3, -56), (-4, -58)]), red, contour: red[0])
        s.part(Mask.poly([(7, -63), (13, -62), (13, -61), (7, -61)]), flat: red[1])
        s.set(-2, -60, red[0]); s.set(-1, -60, red[0])
        s.set(-2, -59, red[0]); s.set(-1, -59, ink)
        s.set(-2, -67, skin[3]); s.set(-3, -66, skin[3]); s.set(-1, -68, skin[3])
        s.stamp(["DDDD", ".K..", "...L", "..D."],
                legend: ["D": skin[0], "K": ink, "L": skin[3]], x: 5, y: -61)

        // The near arm last, in front of everything: sleeve, forearm, a wrist strap and the
        // batting glove over the hands.
        s.part(Mask.capsule(x0: p.shoulder.x, y0: p.shoulder.y, r0: 3.4,
                            x1: p.elbow.x, y1: p.elbow.y, r1: 2.8), red, contour: red[0])
        s.part(Mask.capsule(x0: p.elbow.x, y0: p.elbow.y, r0: 2.8,
                            x1: p.hands.x, y1: p.hands.y + 1, r1: 2.3), skin, contour: skin[0])
        let wristT = 0.72
        let wx = p.elbow.x + (p.hands.x - p.elbow.x) * wristT
        let wy = p.elbow.y + (p.hands.y + 1 - p.elbow.y) * wristT
        s.part(Mask.ellipse(cx: wx, cy: wy, rx: 2.4, ry: 1.6), flat: red[1])
        s.part(Mask.ellipse(cx: p.hands.x, cy: p.hands.y, rx: 2.8, ry: 3.3),
               look.glove, contour: look.glove[0])
        return s
    }

    /// The bat: a tapered capsule from the hands to the tip, a knob just behind the hands, and
    /// the pine tar smudged up the handle (`variants.bat_part`).
    private static func bat(on s: ShadedSprite, from hands: (x: Double, y: Double),
                            to tip: (x: Double, y: Double), look: Look, rules: PeopleRules) {
        let wood = look.wood
        s.part(Mask.capsule(x0: hands.x, y0: hands.y, r0: rules.batHandleRadius,
                            x1: tip.x, y1: tip.y, r1: rules.batBarrelRadius),
               wood, contour: wood[0])
        let dx = tip.x - hands.x, dy = tip.y - hands.y
        let n = max(1e-9, (dx * dx + dy * dy).squareRoot())
        let knobR = rules.batHandleRadius + rules.batKnobExtra
        s.part(Mask.capsule(x0: hands.x - dx / n * rules.batKnobFar,
                            y0: hands.y - dy / n * rules.batKnobFar, r0: knobR,
                            x1: hands.x - dx / n * rules.batKnobNear,
                            y1: hands.y - dy / n * rules.batKnobNear, r1: knobR),
               wood, contour: wood[0])
        for u in rules.pineTarAlong {
            let bx = hands.x + dx * u, by = hands.y + dy * u
            s.set(Int((bx - 0.5).rounded()), Int((by - 0.5).rounded()), wood[0])
            s.set(Int((bx + 0.5).rounded()), Int((by - 0.5).rounded()), wood[0])
        }
    }

    // MARK: - The pitcher

    /// His three frames, written a character to a pixel: set, leg kick, release. Copied verbatim
    /// from `golden.PITCH`, which is where the proportions were settled.
    ///
    /// `R`/`r`/`H` cap, `S`/`s` skin, `U`/`u` flannel, `L`/`W` its lit side, `K` the ink line,
    /// `G`/`g` the glove, `B` the ball, `N` the chest logo.
    static let pitchFrames: [[String]] = [
        ["....RRR....",
         "...HRRRr...",
         "...RRRRr...",
         "...rrrrrr..",
         "...SSSSs...",
         "...SKSKs...",
         "....SSs....",
         "..WLUUUUu..",
         ".WLUUNUUUu.",
         ".WLUGGGUUu.",
         ".SLUGGgUus.",
         "..LUGggUu..",
         "..LUUUUUu..",
         "..KKKKKKK..",
         "..WLUuLUu..",
         "..WLU.LUu..",
         "..WLU.LUu..",
         "..HRr.HRr..",
         "..HRr.HRr..",
         ".KKKK.KKKK."],
        ["....RRR......S.",
         "...HRRRr....SB.",
         "...RRRRr...LU..",
         "...rrrrrr.LU...",
         "...SSSSs.LU....",
         "...SKSKsLU.....",
         "....SSs.U......",
         ".GWLUUUUu......",
         "GGGLUUNUu......",
         "GgWLUUUUu......",
         ".g.LUUUUUUu....",
         "...LUUUUULUUu..",
         "...KKKKKK.LUu..",
         "...WLUu...LUu..",
         "...WLUu...HRr..",
         "...WLUu...HRr..",
         "...WLUu...KKKK.",
         "...HRr.........",
         "...HRr.........",
         "..KKKK........."],
        [".....RRR.......",
         "....HRRRr......",
         "....RRRRr......",
         "....rrrrrr.....",
         "....SSSSs......",
         "....SKSKs......",
         ".....SSs.......",
         ".G.WLUUUUUu....",
         "GGGLUUNUUULUu..",
         "Gg.LUUUUUu.LUS.",
         ".g.LUUUUUu..SS.",
         "...LUUUUUu.....",
         "...KKKKKKK.....",
         "..WLUu.LUUu....",
         ".WLUu...LUUu...",
         ".WLu.....LUu...",
         ".HRr.....HRr...",
         ".HRr.....HRr...",
         "KKKK.....KKKK.."]
    ]

    /// One of those three stamps in the phase's own cloth and skin. When the light is on the
    /// right the modelling is mirrored rather than the pose: a pitcher who turned round to face
    /// the sunrise would be throwing the wrong way (`golden.pitcher`).
    static func pitcher(pose frame: Int, look: Look, rules: PeopleRules = .standard) -> ShadedSprite {
        var rows = pitchFrames[min(max(0, frame), pitchFrames.count - 1)]
        if look.light.x > rules.lightFromTheRight { rows = rows.map(mirrorModelling) }
        let s = ShadedSprite(width: rules.pitcherWidth, height: rules.pitcherHeight,
                             ox: rules.pitcherOriginX, oy: rules.pitcherOriginY,
                             light: look.light, cuts: look.cuts)
        let red = look.red, grey = look.grey, skin = look.skin, wood = look.wood
        let legend: [Character: Palette.RGBA8] = [
            "R": red[2], "r": red[0], "H": red[3],
            "S": skin[2], "s": skin[1],
            "U": grey[2], "u": grey[0],
            // With the lamps on a figure is lit from everywhere at once, so the flannel's lit
            // side takes the body tone instead of the rim.
            "L": look.flatFigures ? grey[2] : grey[3], "W": grey[3],
            "K": Palette.ink, "G": wood[1], "g": wood[0],
            "B": Palette.chalk, "N": red[1]
        ]
        s.stamp(rows, legend: legend, x: rules.pitcherStampX, y: -rows.count)
        return s
    }

    /// Swaps the lit and shaded sides of one stamp row. `WL` — the two-pixel lit edge — becomes
    /// `uU`, and everything else trades its lit tone for its shaded one, so the figure keeps its
    /// silhouette exactly and only its shading turns round.
    private static func mirrorModelling(_ row: String) -> String {
        var out = ""
        out.reserveCapacity(row.count)
        let chars = Array(row)
        var i = 0
        while i < chars.count {
            if chars[i] == "W", i + 1 < chars.count, chars[i + 1] == "L" {
                out += "uU"
                i += 2
                continue
            }
            switch chars[i] {
            case "W", "L": out.append("u")
            case "u": out.append("W")
            default: out.append(chars[i])
            }
            i += 1
        }
        return out
    }

    // MARK: - Cast shadows

    /// Where a figure's shadow falls: each painted pixel of it projected away from the light,
    /// sideways by `slope` and up the screen by `rise` for every pixel of its height, with the
    /// far end dithered out above `softFrom`. The offsets are gathered into a set first, so a
    /// ground pixel two parts of the figure land on is darkened **once** — twice and an elbow
    /// would burn a hole in the grass (§20 "Cast shadows", `golden.cast`).
    static func shadowStamp(for sprite: ShadedSprite, shadows: [Look.Shadow]) -> ShadowStamp {
        var hit = Set<ShadowStamp.Offset>()
        let w = sprite.canvas.width, h = sprite.canvas.height
        for shadow in shadows {
            for y in 0..<h {
                let row = sprite.canvas.buffer + y * w
                for x in 0..<w where row[x] != 0 {
                    let lx = Double(x - sprite.ox), height = Double(sprite.oy - y)
                    let sx = Int(lx - height * shadow.slope)
                    let sy = Int(-height * shadow.rise)
                    if height > shadow.softFrom && ((sx + sy) & 1) != 0 { continue }
                    hit.insert(ShadowStamp.Offset(dx: sx, dy: sy))
                }
            }
        }
        return ShadowStamp(offsets: Array(hit))
    }

    /// Darkens the ground under a figure. `table` says what each ground colour turns into, keyed
    /// by its packed word, so a shadow on the grass goes to `shade` and one on the dirt goes a
    /// step down the dirt ramp — and a pixel that is neither (the chalk of a batter's box, the
    /// plate) is left alone, because a shadow does not fall on a line.
    static func cast(_ stamp: ShadowStamp, into c: PixelCanvas, footX: Double, footY: Double,
                     table: [UInt32: Palette.RGBA8]) {
        let fx = Int(footX), fy = Int(footY)
        for o in stamp.offsets {
            let x = fx + o.dx, y = fy + o.dy
            guard x >= 0, y >= 0, x < c.width, y < c.height else { continue }
            let i = y * c.width + x
            guard let darker = table[c.buffer[i]] else { continue }
            c.buffer[i] = darker.packed
        }
    }

    /// What a cast shadow does to each thing it can land on: the grass goes to `shade`, and the
    /// dirt goes one step down its own four-tone ramp rather than green (`golden.at_bat`'s
    /// `table`).
    static func shadowTable(look: Look) -> [UInt32: Palette.RGBA8] {
        let d = look.dirt
        return [
            Palette.grassA.packed: Palette.shade,
            Palette.grassB.packed: Palette.shade,
            d[1].packed: d[2],
            d[2].packed: d[3],
            d[0].packed: d[2]
        ]
    }
}

/// The cast-shadow shapes, one per pose and phase, beside `ShadedSpriteCache`'s stamps. Working
/// one out walks a 128×104 sprite once for every `Look.Shadow` the phase carries, which is far
/// too much to do twice in a frame and depends on nothing that changes between frames.
final class ShadowStampCache {
    private struct Key: Hashable {
        let name: String
        let pose: Int
        let phase: DayPhase
    }

    private var stamps: [Key: ShadowStamp] = [:]

    func stamp(_ name: String, pose: Int, phase: DayPhase, build: () -> ShadowStamp) -> ShadowStamp {
        let key = Key(name: name, pose: pose, phase: phase)
        if let hit = stamps[key] { return hit }
        let made = build()
        stamps[key] = made
        return made
    }
}
