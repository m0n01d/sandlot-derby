import Foundation
import DerbyCore

/// The people's own numbers — the App half of §20's "Batter at bat", "Pitcher" and "Cast
/// shadows" rows. Every one of them is a pixel or a fraction; the colours are the phase's
/// (`Look.red`, `.grey`, `.skin`, `.wood`, `.glove`, `.hair`).
struct PeopleRules {

    // MARK: The batter's rig (`rig34.batter34`)

    /// The sprite the rig is drawn into, and where his feet sit inside it. It has to hold the
    /// bat at every cached swing angle, whose tip reaches up to about 60 px to one side of his
    /// feet and 86 px above them, so the canvas is wide and the origin is low and left of centre.
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

    /// Degrees between cached contact/finish stamps: a slice angle is quantised to this before a
    /// pose is picked, so a swing at 23° and one at 24° share a stamp instead of each building
    /// its own (§20 "Layers and speed", `BatterFrame`).
    var swingAngleStep = 5.0
    /// How far the finger must have travelled from `dragStart`, in design pixels, during a pitch
    /// before the batter's rig shows the mid-swing pose rather than his stance.
    var swingFrameAfterPixels = 8.0

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

/// One pose of the three-quarter rig, in sprite-local pixels measured from his feet, y up the
/// screen being negative (`rig34.P34`). The camera sits behind and above the plate, looking at a
/// right-handed hitter's back-right: his front foot, front knee and far arm are up and to the
/// right, toward the pitcher, his back foot and back knee down and to the left, and his near arm
/// — the one drawn in front, closest to the camera — is his right one.
///
/// R = his right = his back leg and his near arm, drawn in front. L = his left = his front leg
/// and his far arm, drawn behind.
struct BatterPose {
    let ankleR: (x: Double, y: Double)
    let ankleL: (x: Double, y: Double)
    let kneeR: (x: Double, y: Double)
    let kneeL: (x: Double, y: Double)
    let hipR: (x: Double, y: Double)
    let hipL: (x: Double, y: Double)
    let shoulderR: (x: Double, y: Double)
    let shoulderL: (x: Double, y: Double)
    let elbowR: (x: Double, y: Double)
    /// Where both hands meet the bat.
    let hands: (x: Double, y: Double)
    let batTip: (x: Double, y: Double)
    /// The far (left) elbow. `nil` when the front arm shows only its sleeve cap at the shoulder;
    /// a point, reached by a full sleeve and forearm, when it swings all the way across to help
    /// grip the bat.
    let elbowL: (x: Double, y: Double)?
    /// Whether the bat is drawn in front of the head rather than behind it.
    let batInFront: Bool
    /// The back foot up on its toe and pivoting, rather than flat on the ground.
    let heelUp: Bool
    let torso: [(Double, Double)]
    let number: (x: Int, y: Int)
    let buckle: (x: Int, y: Int)

    /// The stance: weight even, both heels down, waiting on the pitch (`rig34.STANCE`).
    static let stance = BatterPose(
        ankleR: (-8, -3), ankleL: (6, -12), kneeR: (0, -17), kneeL: (9, -24),
        hipR: (-3, -31), hipL: (4, -34), shoulderR: (-5, -50), shoulderL: (6, -54),
        elbowR: (-15, -50), hands: (-8, -55), batTip: (-22, -86), elbowL: nil,
        batInFront: true, heelUp: false,
        torso: [(-10, -51), (-4, -56), (5, -57), (10, -53), (9, -44), (7, -30), (-6, -30), (-10, -42)],
        number: (-7, -44), buckle: (6, -32))

    /// Mid-swing: the bat coming through, no particular angle settled yet — shown while a finger
    /// is dragging across the screen but has not yet crossed the ball (`rig34.MID`).
    static let swing = BatterPose(
        ankleR: (-8, -3), ankleL: (6, -12), kneeR: (0, -17), kneeL: (9, -24),
        hipR: (-2, -30), hipL: (4, -34), shoulderR: (-4, -50), shoulderL: (7, -54),
        elbowR: (-9, -44), hands: (0, -46), batTip: (-34, -52), elbowL: nil,
        batInFront: false, heelUp: false,
        torso: [(-10, -51), (-4, -56), (5, -57), (10, -53), (9, -44), (7, -30), (-6, -30), (-10, -42)],
        number: (-7, -44), buckle: (6, -32))

    /// The instant of contact: the bat lies along the slice angle, the hands sliding down and in
    /// as the swing steepens, the back heel up on its toe (`rig34.contact34`).
    static func contact(swingAngleDegrees theta: Double) -> BatterPose {
        let s = (theta - 20) / 50.0
        let hands = (x: 17 + 2 * s, y: -44 + 10 * s)
        let a = theta * Double.pi / 180
        let batTip = (x: hands.x + 44 * cos(a), y: hands.y - 44 * sin(a))
        let shoulderR = (x: -4.0, y: -51.0), shoulderL = (x: 8.0, y: -54.0)
        let elbowR = (x: shoulderR.x + (hands.x - shoulderR.x) * 0.5 + 1,
                      y: shoulderR.y + (hands.y - shoulderR.y) * 0.5 + 2)
        let elbowL = (x: shoulderL.x + (hands.x - shoulderL.x) * 0.5,
                      y: shoulderL.y + (hands.y - shoulderL.y) * 0.5 - 2)
        return BatterPose(
            ankleR: (-7, -3), ankleL: (6, -12), kneeR: (2, -18), kneeL: (8, -24),
            hipR: (-1, -31), hipL: (5, -34), shoulderR: shoulderR, shoulderL: shoulderL,
            elbowR: elbowR, hands: hands, batTip: batTip, elbowL: elbowL,
            batInFront: false, heelUp: true,
            torso: [(-9, -52), (-2, -57), (7, -57), (11, -52), (10, -44), (8, -30), (-6, -30), (-9, -42)],
            number: (-3, -44), buckle: (8, -32))
    }

    /// The follow-through: the finish rises with the slice, the bat wrapping back round in front
    /// of the head (`rig34.finish34`).
    static func finish(swingAngleDegrees theta: Double) -> BatterPose {
        let phi = (52 + (theta - 20) * 0.6) * Double.pi / 180
        let hands = (x: -8.0, y: -56.0)
        let batTip = (x: hands.x - 30 * cos(phi), y: hands.y - 30 * sin(phi))
        return BatterPose(
            ankleR: (-6, -3), ankleL: (6, -12), kneeR: (1, -18), kneeL: (7, -24),
            hipR: (-2, -31), hipL: (5, -34), shoulderR: (8, -53), shoulderL: (-6, -52),
            elbowR: (0, -49), hands: hands, batTip: batTip, elbowL: nil,
            batInFront: true, heelUp: true,
            torso: [(-9, -53), (-2, -57), (7, -57), (11, -53), (10, -44), (8, -30), (-6, -30), (-9, -42)],
            number: (-2, -44), buckle: (9, -32))
    }
}

/// Which frame of the batter's rig to draw: the stance, the generic mid-swing, or — quantised to
/// `PeopleRules.swingAngleStep` so the sprite cache holds a handful of stamps rather than one per
/// pixel of finger drift — the instant of contact or the follow-through at a given slice angle.
enum BatterFrame: Hashable {
    case stance
    case swing
    case contact(step: Int)
    case finish(step: Int)

    /// `SliceRules` clamps a slice angle to −20°…80°, so at the default 5° step this is −4…16.
    static func contact(angleDegrees: Double, rules: PeopleRules = .standard) -> BatterFrame {
        .contact(step: Int((angleDegrees / rules.swingAngleStep).rounded()))
    }

    static func finish(angleDegrees: Double, rules: PeopleRules = .standard) -> BatterFrame {
        .finish(step: Int((angleDegrees / rules.swingAngleStep).rounded()))
    }

    /// The quantised step's angle, back in degrees — the inverse of `contact(angleDegrees:)` /
    /// `finish(angleDegrees:)`.
    var angleDegrees: Double {
        switch self {
        case .stance, .swing: return 20
        case .contact(let step), .finish(let step):
            return Double(step) * PeopleRules.standard.swingAngleStep
        }
    }

    var pose: BatterPose {
        switch self {
        case .stance: return .stance
        case .swing: return .swing
        case .contact(let step):
            return .contact(swingAngleDegrees: Double(step) * PeopleRules.standard.swingAngleStep)
        case .finish(let step):
            return .finish(swingAngleDegrees: Double(step) * PeopleRules.standard.swingAngleStep)
        }
    }

    /// A cache key stable across the whole range a slice angle can quantise to.
    var cacheID: Int {
        switch self {
        case .stance: return 0
        case .swing: return 1
        case .contact(let step): return 100 + step + 4
        case .finish(let step): return 200 + step + 4
        }
    }
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
    ///
    /// A consistent three-quarter rear view (`rig34.batter34`): the camera behind and above the
    /// plate sees a right-handed hitter's back-right, so his front foot, knee and far arm are up
    /// and to the right toward the pitcher, and his near arm — his right one, drawn in front of
    /// the torso — is the one that swings the bat home.
    static func batter(frame: BatterFrame, look: Look, rules: PeopleRules = .standard) -> ShadedSprite {
        let s = ShadedSprite(width: rules.batterWidth, height: rules.batterHeight,
                             ox: rules.batterOriginX, oy: rules.batterOriginY,
                             light: look.light, cuts: look.cuts)
        let p = frame.pose
        let red = look.red, grey = look.grey, skin = look.skin
        let ink = Palette.ink

        // The shoes first, so everything above lands on top of them. A dark sole with one grey
        // upper is the whole shoe at this size, the toe cap its one pixel of light — or, up on
        // the toe and pivoting through contact and the finish, a capsule instead.
        let shoe = [ink, ink, grey[0], grey[2]]
        func leg(hip: (x: Double, y: Double), knee: (x: Double, y: Double),
                 ankle: (x: Double, y: Double), heelUp: Bool) {
            if heelUp {
                s.part(Mask.capsule(x0: ankle.x + 5, y0: ankle.y + 1.5, r0: 2.0,
                                    x1: ankle.x - 2, y1: ankle.y - 1.5, r1: 2.4), shoe, contour: ink)
            } else {
                s.part(Mask.ellipse(cx: ankle.x + 1.5, cy: ankle.y + 2, rx: 5.8, ry: 2.5),
                       shoe, contour: ink)
                s.set(Int(ankle.x + 5), Int(ankle.y + 1), grey[2])
            }
            // The red sock, the flannel over it, the thigh, a stripe down the outside and a fold
            // behind the knee.
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

        leg(hip: p.hipL, knee: p.kneeL, ankle: p.ankleL, heelUp: false)   // the front leg is the far one
        leg(hip: p.hipR, knee: p.kneeR, ankle: p.ankleR, heelUp: p.heelUp)
        // The hips: a seat across both thigh tops so the two legs read as one pelvis.
        s.part(Mask.ellipse(cx: (p.hipL.x + p.hipR.x) / 2, cy: (p.hipL.y + p.hipR.y) / 2 + 1,
                            rx: 8.0, ry: 3.4), grey, contour: grey[0])

        func sleeve(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double),
                    r0: Double = 3.4, r1: Double = 2.8) {
            s.part(Mask.capsule(x0: a.x, y0: a.y, r0: r0, x1: b.x, y1: b.y, r1: r1), red, contour: red[0])
        }
        func forearm(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) {
            s.part(Mask.capsule(x0: a.x, y0: a.y, r0: 2.8, x1: b.x, y1: b.y + 1, r1: 2.3),
                   skin, contour: skin[0])
            let wristT = 0.72
            let wx = a.x + (b.x - a.x) * wristT
            let wy = a.y + (b.y + 1 - a.y) * wristT
            s.part(Mask.ellipse(cx: wx, cy: wy, rx: 2.4, ry: 1.6), flat: red[1])
        }

        // The torso, the shoulders across the top of it, the belt and its buckle, and his number.
        s.part(Mask.poly(p.torso), grey, contour: grey[0])
        s.part(Mask.ellipse(cx: 0.5, cy: -53, rx: 9.0, ry: 3.8), grey)
        s.part(Mask.poly([(-7.5, -33), (8.5, -33), (8.5, -30), (-7.5, -30)]), flat: ink)
        s.set(p.buckle.x, p.buckle.y, Palette.score)
        s.set(p.buckle.x + 1, p.buckle.y, Palette.score)
        s.stamp(["RRR", "..R", ".R.", ".R.", ".R."], legend: ["R": red[1]], x: p.number.x, y: p.number.y)

        // The far arm: a full sleeve and forearm to the hands when it reaches all the way across
        // (`elbowL` given), or just its shoulder cap peeking past the torso when it does not.
        if let elbowL = p.elbowL {
            sleeve(p.shoulderL, elbowL, r0: 3.2, r1: 2.7)
            forearm(elbowL, (x: p.hands.x, y: p.hands.y - 2))
        } else {
            s.part(Mask.ellipse(cx: p.shoulderL.x, cy: p.shoulderL.y + 1, rx: 3.4, ry: 3.0),
                   red, contour: red[0])
        }

        func drawBat() {
            bat(on: s, from: (p.hands.x, p.hands.y + 2), to: (p.batTip.x, p.batTip.y),
                look: look, rules: rules)
        }
        if !p.batInFront { drawBat() }

        // The head from behind and to the right: the nape, the helmet with its brim toward the
        // pitcher, his right ear and a sliver of cheek on the near side, and the glint off the
        // dome. No face from this camera, and no ear hole — only the ear itself.
        s.part(Mask.poly([(0, -58), (5, -58), (5, -54), (0, -54)]), skin)
        s.part(Mask.ellipse(cx: 3, cy: -61.5, rx: 5.2, ry: 5.6), skin, contour: skin[0])
        s.set(0, -57, look.hair); s.set(1, -57, look.hair)
        s.set(0, -56, look.hair); s.set(2, -57, look.hair)
        s.part(Mask.ellipse(cx: 2, cy: -63, rx: 7, ry: 6.2).filter { $0.y < -59 },
               red, contour: red[0])
        s.part(Mask.poly([(-4, -61), (1, -61), (1, -57), (-3, -57), (-4, -59)]), red, contour: red[0])
        s.part(Mask.poly([(5, -61), (10, -61), (10, -57), (7, -57)]), red, contour: red[0])
        s.part(Mask.poly([(7, -67), (14, -66), (14, -64), (8, -64)]), flat: red[1])
        s.set(7, -59, skin[1]); s.set(8, -59, skin[0]); s.set(7, -58, skin[1])
        s.set(9, -58, skin[2]); s.set(9, -57, skin[1])
        s.set(-2, -67, skin[3]); s.set(-3, -66, skin[3]); s.set(-1, -68, skin[3])

        if p.batInFront { drawBat() }

        // The near arm last, in front of everything: sleeve, forearm, a wrist strap and the
        // batting glove over the hands.
        sleeve(p.shoulderR, p.elbowR)
        forearm(p.elbowR, p.hands)
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
    ///
    /// `groundRise` lets the ground itself slope under the figure. The batter's front foot is
    /// drawn several rows higher on screen than his back one — he is not standing in the air, the
    /// ground he stands on is drawn rising toward the pitcher — so without it every pixel above
    /// his front foot would project as if that many rows off the ground. With it, a column's
    /// height is measured from where the ground passes under that column instead of from the
    /// sprite's own foot row: `t` is how far across the line a pixel's `lx` sits (0…1), `g` is
    /// that many rows of the rise the ground has already climbed under it, and the shadow is
    /// measured from the ground point under the column, `g` rows up the screen.
    static func shadowStamp(for sprite: ShadedSprite, shadows: [Look.Shadow],
                            groundRise: (x0: Double, x1: Double, rise: Double)? = nil) -> ShadowStamp {
        var hit = Set<ShadowStamp.Offset>()
        let w = sprite.canvas.width, h = sprite.canvas.height
        for shadow in shadows {
            for y in 0..<h {
                let row = sprite.canvas.buffer + y * w
                for x in 0..<w where row[x] != 0 {
                    let lx = Double(x - sprite.ox)
                    let g: Double
                    if let groundRise {
                        let span = groundRise.x1 - groundRise.x0
                        let t = span != 0 ? max(0, min(1, (lx - groundRise.x0) / span)) : 0
                        g = groundRise.rise * t
                    } else {
                        g = 0
                    }
                    let height = max(0, Double(sprite.oy - y) - g)
                    let sx = Int(lx - height * shadow.slope)
                    let sy = Int(-g - height * shadow.rise)
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
