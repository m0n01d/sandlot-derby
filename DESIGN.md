# Sandlot Derby — design spec

Working title. A minimalist home run derby for iPhone, native Swift, 16-bit Sega look, one gesture.
This document is the contract between the three research pages (see `prototypes/`) and the code.
Every number in it is a named knob in `Core/`; §12 lists them.

---

## 1. The pitch

Desert Golfing's restraint pointed at a batter's box. You stand in, the pitch comes, you slice
through it Fruit Ninja style, the frame freezes on your slash, and the view cuts to a wide shot
where the ball flies with real drag and the distance ticks up under it. No outs, no menus, no
timers. Parks are seeded and endless. The score is total feet, forever.

**Pillars**

1. **One gesture.** A slice. Its direction is the swing angle, its speed is the power. Nothing else
   is ever asked of the player. No buttons.
2. **Two cameras, one edit.** At-bat view for the pitch, wide view for the flight. The only cut in
   the game is contact → flight, and it is always a hard cut.
3. **Sixteen colours.** One Genesis palette line, 320×224 design space, integer scaling, no
   anti-aliasing, dither only in the sky.
4. **Never punished, only counted.** A miss brings the next pitch. The only number that matters is
   feet, and it never resets.

**Why this and not the market:** every existing hitting game (Flick Home Run!, Baseball Boy!,
Homerun Clash, the MLB app) wraps a simple input in upgrades, ads, modes or seasons. Nothing
ships the bare loop. The classic derby modes of the 90s (World Series Baseball '94, the Griffey
games) were bolt-ons inside full sims. The bare loop is open.

## 2. Platform and stack

- iPhone first, landscape. iPad works by letterbox. No Android, no web.
- SwiftUI shell → `SpriteView` → two `SKScene`s (`AtBatScene`, `WideScene`), or one scene with two
  root nodes; either way, `SKView.presentScene(_:)` with **no transition**.
- `DerbyCore` (Swift package, pure): flight physics, pitching, slice contact, parks, the state
  machine. No UIKit, no SpriteKit. `swift test` on Linux must pass.
- No physics engine. The flight is integrated once on contact and played back. SpriteKit's
  `linearDamping` is linear in velocity and cannot do baseball drag; precomputing also keeps park
  seeds deterministic across devices.
- Textures: `filteringMode = .nearest`. Scene height 224 design units, width = 224 × aspect
  (≈ 485 on a 19.5:9 phone, 298 on a 4:3 iPad). Layouts anchor to edges and centre; the 320-wide
  prototype coordinates are the *minimum* width.
- Persistence: `UserDefaults` for the tally and park number, `Codable`. Game Center leaderboard
  for total feet and longest, later (§13, M5).
- Apple Developer Program required for TestFlight and the store. The "Apple rejects JS apps"
  premise was checked and is a myth (guideline 4.7 explicitly permits JS games); Swift is chosen
  for frame-loop smoothness, free frameworks and having no web version to share code with.

## 3. The loop: five beats and a miss

| # | Beat | Camera | Duration | What happens |
|---|---|---|---|---|
| 1 | **windup** | at-bat | 0.50 s | pitcher's three frames. A slice made now is ignored, not punished. |
| 2 | **pitch** | at-bat | `0.60 × 90/speed` s (0.55 – 0.73) | ball travels release → plate, radius 1 → 4 px. Player slices. |
| 3 | **contact** | at-bat | 0.35 s | ball frozen at the crossing, slash through it along the swing, speed lines, `SWING 30  POWER 84`. One white frame at start. |
| — | cut | | 1 frame | white frame, hard cut. |
| 4 | **flight** | wide | flight ÷ 2 (≈ 2–3 s) | ball plays back at 2×. Readouts: exit velo, angle, pitch type, power. Distance ticks under the ball. |
| 5 | **result** | wide | 1.30 s | landing number big (5×7 face). `HR` flashes on a home run. `OFF THE WALL` on a wall hit. Then hard cut back to 1. |
| — | **miss** | at-bat | 1.20 s | miss markers (§7), `MISS` / `STRIKE` / `BALL`. Then back to 1. Never cuts. |

A pitch is *taken* when `elapsed > duration × 1.15 + 0.05 s` with no contact. If a slice is in
progress at that moment it resolves as a miss with markers; otherwise it is a called strike or
ball. Taken pitches count as pitches. Only contact counts as a hit.

State machine (`DerbyMachine`): six beats, one camera-changing edge, no knowledge of nodes.

```
windup ─0.5s─▶ pitch ─slice crosses ball─▶ contact ─0.35s─▶ flight ─playback ends─▶ result
                 │                                    (CUT)                            │
                 └─taken / slice misses─▶ miss ─1.2s─▶ windup ◀──1.3s, cut back────────┘
```

## 4. Pitching

Three pitch types, one table row each. No art cost.

| Type | Speed (mph) | Late drop (px) | Drift (px) | Weight | Exit velo bonus |
|---|---|---|---|---|---|
| FASTBALL | 92 – 99 | 0 | 0 | 0.45 | +3 mph |
| CHANGEUP | 74 – 82 | 6 | 0 | 0.25 | −3 mph |
| CURVE | 76 – 84 | 22 | −8 (toward batter) | 0.30 | 0 |

- **Strike probability 0.65.** Strikes land 4 px inside the zone; balls land 6–16 px outside one
  of its four sides.
- **Zone** (at-bat design units): `x 150, y 136, w 40, h 50`. Oversized for thumbs; a true zone
  at this scale is ~24×32. Drawn as a dotted chalk rectangle.
- **Release point** `(166, 108)`. Ball path at progress `p` (0 release, 1 plate, runs to 1.15):

  ```
  x = rel.x + (tx − rel.x)·p + driftX·sin(πp)
  y = rel.y + (ty − rel.y)·p² − dropY·(1−p)·p·1.6 + dropY·(p³ − p²)
  r = p<0.3 ? 1 : p<0.6 ? 2 : p<0.85 ? 3 : 4
  ```
  The `p²` term makes the ball ease down late; the curve's drop lands in the last quarter, which
  is exactly when the player is committing.
- The pitch type is hidden until thrown and shown after the pitch resolves (`CURVE 81 MPH`).
- Pitches come from a seeded generator (SplitMix64) so a session replays identically for a seed.

## 5. The slice (input)

Every pointer move is a segment `a → b` tested against the ball. First segment to cross wins.

1. **Lag forgiveness.** Test against the ball's position now and at 4 samples back over the last
   120 ms; take the closest. Thumb latency at arrival speed moves the ball 10–20 px; without this,
   correct slices miss.
2. **Reach** = ball radius + 9 px. Closest distance beyond reach → **miss** (record closest
   approach for markers).
3. **Timing** `tq = max(0, 1 − |p − 1| / 0.28)`. If zero, the ball was too far away → **early**
   (keeps slicing; resolves as a miss on pointer-up with an `EARLY  BALL 32 FT OUT` label).
4. **Centring** `cq = 1 − min(1, d / reach) × 0.4`.
5. **Quality** `q = tq × cq`, × 0.8 if the pitch was a ball.
6. **Swing angle** = direction from where the drag *started* to the crossing point, so the whole
   stroke counts. Falls back to the last segment for drags under 12 px. `atan2(−dy, |dx|)`,
   clamped −20° … 80°. Sign of `dx` is ignored: slicing toward or away from the pitcher is the
   same swing.
7. **Power** = `max(0.3, min(1, max(fingerSpeed / 520 px/s, dragLength / (0.28 × 320))))`.
   Speed is the intent; length is the floor so a slow deliberate stroke still hits.
8. **Launch** (`Contact.resolve`):
   ```
   exitVelo  = 55 + 57 × (0.4·q + 0.6·power) + typeBonus        (mph, 55 … 115)
   launchAng = clamp(swingAngle + (1 − p) × 40, −8, 70)          (early = under it = loft)
   ```
   Perfect quality with a lazy slice and a sloppy slice at full speed land about the same; only
   both together clear the wall.

Space bar / keyboard (dev only): a medium 27° slice through the ball.

## 6. Flight

See `docs/physics.md`. Constants: `k 0.0174`, `Cd 0.33`, `Cl 0.15`, `g 9.81`, `dt 1/240`,
contact height 1 m. Ground bounce keeps 40 % vertical and 75 % horizontal, rolls out at 0.985 per
step. Wall is a plane crossing: below the top is a wall hit (35 % rebound), at or above before
first landing is a home run. Distance is first ground contact.

The calibration table there is the test oracle. 100 mph at 28° = 398 ft (Statcast says ~400).
Without air the same ball goes 560 ft; drag is the whole feel.

## 7. Miss markers

On any miss the at-bat frame freezes for 1.2 s and draws:

- **Your trail** (the last 24 pointer samples) as a 2 px chalk line with a yellow core on the
  last segments, plus 8 speed lines and a red X at its closest point to the ball.
- **The ball** where it actually was (ghost) with a pulsing dotted ring.
- **A dashed connector** and a label on an ink box: `HIGH OUT 11 IN`, `LOW IN 4 IN`, or for an
  early slice `EARLY  BALL 32 FT OUT`. Inches are real: the 8 px ball is 2.9 in, so 1 px = 0.36 in.
  `IN` is toward the batter (left), `OUT` away. In the wide-only debug camera horizontal error is
  time, so the words become `EARLY` / `LATE`.
- Called strike or ball: ring at the plate, no trail.

This is Fruit Ninja's lesson: a miss has to be legible on the object, not on a meter.

## 8. Cameras and layout (design units, y down)

**At-bat view (320×224).** Sky bands `0–44 / 44–70 / 70–96` with 4-row dither at each boundary;
wall band `96–104` with the scoreboard `(128, 80, 64×16)` showing wall distance and park number;
grass from 104 with 6-row stripes every 12; foul lines from `(160,196)` to `(40,104)` and
`(280,104)`; mound dirt `(148,116, 24×5)`; plate dirt `(120,184, 80×14)`, plate `(152,190, 16×4)`.
Pitcher at `(160,117)` foot point, 12×24. Batter foot point `(104,222)`, rear three-quarter,
32×56. Zone and release point per §4. `PARK n` top-left, pitch speed bottom-left.

**Wide view (320×224).** Side view, batter at x = 0 ft, wall to the right. Scale `320/540`
px per foot, view starts at −24 ft, ground at y = 176. Sky bands `0–70 / 70–130 / 130–176`.
Wall drawn at its real height. Foot ticks every 100 ft. Readouts top-left in the 3×5 face at 2×:
exit velo, angle; pitch type and power in 1×. Distance ticks beside the ball in flight. Result
number centred at y = 52 in the 5×7 face at 3×; `HR` below it, blinking at 3 Hz.

Wider phones extend the sky and grass to the edges; the wall and readouts anchor to the right and
left edges respectively.

**Night parks.** Sky swaps per `docs/palette.md`, 40 fixed stars, a light tower behind the wall.

## 9. Art

- Palette: `docs/palette.md`. Fifteen colours plus transparent.
- Sprites (all silhouettes, no outlines):

  | Asset | View | Size | Frames |
  |---|---|---|---|
  | Pitcher | at-bat | 12×24 | set, leg kick, release |
  | Batter, rear ¾ | at-bat | 32×56 | stance, contact, follow-through |
  | Batter, side | wide | 32×48 | contact hold, follow-through |
  | Ball | both | 2, 4, 6, 8 px | one highlight pixel at 6 px and up, no rotation |
  | Zone, plate, mound, wall, scoreboard | — | rects | static |
  | 3×5 and 5×7 bitmap faces | both | — | from the prototype bit strings |

  Eleven drawn frames total.
- Motion budget: the ball and its trail are smooth at 60 Hz; people are stamps. That contrast is
  the 16-bit sports feel.
- Type is the only decoration: the landing number is the chunkiest thing on screen.

## 10. Parks and score

- Park N is a pure function of N (SplitMix64 seeded by N). Park 1 is always 380 ft / 10 ft, day.
  Park N ≥ 2: wall 330–410 ft, height 6–26 ft, night with p = 0.25. Wind is reserved for later.
- A home run advances to the next park at the end of the result hold. Anything else stays.
- Tally: pitches, hits, home runs, longest, **total feet**. Total feet is the score and never
  resets. Persist on every change. Game Center: total feet and longest.
- No sessions, no lives, no daily anything.

## 11. Audio and haptics (M5)

One contact sound, one wall sound, one landing thud, and a soft "took it" tick. Haptic on contact
(`.rigid`) and on a home run (`.success`). Nothing during the pitch: silence is the tension.

## 12. Tuning knobs

All live in `DerbyCore` structs with doc comments. Defaults are the prototype's.

| Knob | Where | Default | Effect |
|---|---|---|---|
| `hitMarginPixels` | `SliceRules` | 9 | forgiveness around the ball |
| `lagWindowSeconds` | `SliceRules` | 0.12 | thumb latency forgiveness |
| `timingWindow` | `SliceRules` | 0.28 | how early a slice can still count |
| `fullPowerSpeed` | `SliceRules` | 520 px/s | the single most likely number to retune on device |
| `qualityWeight` | `SliceRules` | 0.4 | contact vs power blend |
| `exitVelocityBase/Span` | `SliceRules` | 55 / 57 | mph range 55–112 before type bonus |
| `earlyLoftDegrees` | `SliceRules` | 40 | pop-ups from early swings |
| `strikeProbability` | `PitchingRules` | 0.65 | difficulty lever, with fastball speed |
| `strikeZone` | `PitchingRules` | 40×50 | thumb-sized; shrink only if it feels like a cheat |
| speed ranges | `PitchType` | table | difficulty lever |
| `flightSpeed` | `Timings` | 2× | 1× is too slow, verified in the prototype |
| `contactHold` | `Timings` | 0.35 s | the slash freeze |
| `liftCoefficient` | `FlightParams` | 0.15 | under-rewards high spinny hits on purpose |
| wall ranges | `Park.Rules` | 330–410 / 6–26 | park variety |

The prototype measured ~60 % of taps as hits with a mouse. Expect thumbs to be lower. If it feels
like a cheat on device, the levers are the miss margin and fastball speed, not the zone.

## 13. Milestones

- **M0 — core green.** `cd Core && swift test` passes on a Mac. Fix compile errors (this package
  was written without a compiler), keep the calibration numbers.
- **M1 — wide view.** Xcode project, SwiftUI shell, `WideScene` playing back a hard-coded flight
  with readouts and the landing number. Palette and both bitmap faces ported.
- **M2 — at-bat view and slice.** `AtBatScene`, pitcher, batter, ball path, `UIPanGesture` /
  touch samples → `Contact.test` each move, `DerbyMachine` driving both scenes, the cut.
- **M3 — feel.** Miss markers, contact freeze with slash and readout, flash frame, hitstop.
  Retune `fullPowerSpeed` and `hitMarginPixels` on a real phone.
- **M4 — parks and score.** Seeded parks, night swap, tally persistence, park advance on HR.
- **M5 — ship.** Audio, haptics, app icon (a ball on a chalk line), Game Center, TestFlight,
  screenshots, store listing. Name decision.

## 14. Open questions

1. **Name.** "Sandlot Derby" is a working title.
2. **Portrait?** Landscape is assumed because the wide view is a side view. A portrait variant
   would stack the wide view above the at-bat view and lose the cut. Decide after M2 on a phone.
3. **Wind.** Parks reserve it. It would show as a flag on the wall and a horizontal term in
   flight. Not before M4.
4. **Sharing.** A park number plus the tally is a screenshot-able brag. Nothing more is planned.

## 15. Non-goals

Fielders, pitching, base running, teams, licences, multiplayer, ads, IAP, seasons, a tutorial.
