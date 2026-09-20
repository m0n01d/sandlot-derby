# Sandlot Derby — design spec

Working title. A minimalist home run derby for iPhone, native Swift, 16-bit Sega look, one gesture.
This document is the contract between the three research pages (see `prototypes/`) and the code.
Every number in it is a named knob in `Core/`; §12 lists them.

---

## 1. The pitch

Desert Golfing's restraint pointed at a batter's box. You stand in, the pitch comes, you slice
through it Fruit Ninja style, the frame freezes on your slash, and the view cuts to a wide shot
where the ball flies with real drag and the distance ticks up under it. No outs, no menus, no
timers. Parks are seeded and endless. The score is how deep you are and how many pitches it took,
forever.

**Pillars**

1. **One gesture.** A slice. Its direction is the swing angle, its speed is the power. Nothing else
   is ever asked of the player. No buttons.
2. **Three cameras, hard cuts only.** At-bat for the pitch; wide as the ball leaves the bat; close
   on the wall as the ball gets there; back out to wide when it lands, for the number over the
   whole arc. Every change is a hard cut. Nothing ever tweens, zooms or scrolls: the hardware this
   imitates could not scale. (Was "two cameras, one edit" until 2026-09-19; the close camera exists
   because a 6 ft wall is 4 px in the wide view.)
3. **Sixteen colours.** One Genesis palette line, 320×224 design space, integer scaling, no
   anti-aliasing, dither only in the sky.
4. **Never punished, only counted.** A miss brings the next pitch. Nothing ever stops or resets the
   game. What is counted is the point: the headline is `PARK n · PITCHES` (progress and what it
   cost, Desert Golfing's strokes), the short game is the **home run streak** (the one number that
   can go back to 0), and everything else is on the stats board (§10). Decided 2026-09-19; total
   feet was the original score and is now one stat among many.

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
| 3 | **contact** | at-bat | `contactHoldWeak` (0.22 s) … `contactHoldBarrel` (0.50 s), linear on the swing's `SliceCrossing.quality` (`DerbyMachine.contactHoldNow`) | ball frozen at the crossing, slash through it along the swing, speed lines, `SWING 30  POWER 84`. On a barrel (`StatRules.isBarrel`, `DerbyMachine.isBarrelNow`) `BARREL` is called in the 5×7 face next to the readout, static (no blink — the freeze is too short). No screen shake, no camera move. One white frame at start. |
| — | cut | | 1 frame | white frame, hard cut. |
| 4 | **flight** | wide, then close | flight ÷ 2 (≈ 2–3 s) | ball plays back at 2×. Readouts: exit velo, angle, pitch type, power. Distance ticks under the ball. A ball that will get within `closeReachFeet` (60) of the wall cuts to the close camera when it is `closeLeadFeet` (100) short of it and stays there until it lands; anything else is wide throughout. `DerbyMachine.flightCamera`, a pure function of the flight and the playback index. |
| 5 | **result** | wide | 1.30 s | landing number big (5×7 face). `HR` flashes on a home run. `OFF THE WALL` on a wall hit. Then hard cut back to 1. |
| — | **miss** | at-bat | 1.20 s | miss markers (§7), `MISS` / `STRIKE` / `BALL`. Then back to 1. Never cuts. |

A pitch is *taken* when `elapsed > duration × 1.15 + 0.05 s` with no contact. If a slice is in
progress at that moment (`DerbyMachine.sliceInProgress`, mirrored every frame from whether a
finger is on the glass — `AtBatScene.fingerDown` — however that finger got there) it resolves
exactly as `sliceMissed()` does — a swing and a miss, with markers, streak rules as for any miss,
never a call; otherwise it is a called strike or ball. Taken pitches count as pitches. Only contact
counts as a hit.

State machine (`DerbyMachine`): six beats, one scene-changing edge (contact → flight; the wide and
close framings are one scene and `flightCamera` picks between them), no knowledge of nodes.

```
windup ─0.5s─▶ pitch ─slice crosses ball─▶ contact ─0.22-0.50s─▶ flight ─playback ends─▶ result
                 │                                       (CUT)                             │
                 └─taken / slice misses─▶ miss ─1.2s─▶ windup ◀──1.3s, cut back────────────┘
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

**Wide view (320×224).** Side view, batter at x = 0 ft, wall to the right. The field gets the
screen: each park is framed so its wall sits two thirds of the way across, and what is behind the
wall is the last third and no more (2026-09-19; it was a fixed `320/540` px per foot, which put a
280 ft wall halfway across). It pulls back only as far as this ball needs: its first landing stays
20 ft inside the right edge and its apex 16 px under the top. A pure function of the park and the
flight, so it holds still from the cut to the end of the result. Batter, mowing stripes (16 ft)
and foot ticks all follow the scale. View starts at −24 ft, ground at y = 176. Sky bands `0–70 / 70–130 / 130–176`.
Wall drawn at its real height. Foot ticks every 100 ft. Readouts top-left in the 3×5 face at 2×:
exit velo, angle; pitch type and power in 1×. Distance ticks beside the ball in flight. Result
number centred at y = 52 in the 5×7 face at 3×; `HR` below it, blinking at 3 Hz.

Wider phones extend the sky and grass to the edges; the wall and readouts anchor to the right and
left edges respectively.

**Close view.** The same side view at 2× the wide scale, fixed (it does not follow the ball
sideways), wall 55 % of the way across so the ball cuts in about a quarter of the way in. The sky
never moves; if the ball would leave the top, the ground drops out of frame instead (24 px of
headroom). 6 px ball with its highlight pixel and a `shade` shadow on the grass; grass stripes and
foot ticks are drawn in world space, so they are twice as wide. Same readouts and distance ticker.
The batter is a stamp, not scaled art, and is off screen here.

**Night parks.** Sky swaps per `docs/palette.md`. Stars, moon and stadium lights are specced in
§17 and not built yet.

## 9. Art

- Palette: `docs/palette.md`. Fifteen colours plus transparent.
- Sprites (all silhouettes, no outlines):

  | Asset | View | Size | Frames |
  |---|---|---|---|
  | Pitcher | at-bat | 12×24 | set, leg kick, release |
  | Batter, rear ¾ | at-bat | 32×56 | stance, contact, follow-through |
  | Batter, side | wide / close | to the field's scale: 6.5 ft, never under 6 px | stance, contact, follow-through. He is the yardstick for the wall (most real walls are a man tall or more); a 42 px batter was 57 ft at the wide scale and made every fence look knee-high (2026-09-19) |
  | Ball | both | 2, 4, 6, 8 px | red laces (`cap`, borrowed by role) from 4 px up: one pixel, then a three-pixel and a five-pixel ")" seam. One highlight pixel at 6 px and up. No rotation (2026-09-19, `PixelCanvas.baseball`) |
  | Zone, plate, mound, wall, scoreboard | — | rects | static |
  | 3×5 and 5×7 bitmap faces | both | — | from the prototype bit strings |

  Eleven drawn frames total.
- Motion budget: the ball and its trail are smooth at 60 Hz; people are stamps. That contrast is
  the 16-bit sports feel.
- Type is the only decoration: the landing number is the chunkiest thing on screen.

## 10. Parks and score

- Park N is a pure function of N (SplitMix64 seeded by N). Parks 1–4 are fixed day games (the
  minors and The Show, below). Park N ≥ 5: wall 330–410 ft, height 6–26 ft, night with p = 0.25.
  Wind is reserved for later.
- A home run advances to the next park at the end of the result hold. Anything else stays.
- **The minors** (decided 2026-09-19, issue #7). Park 1 at 380 ft needed ~97 mph, so a first-timer
  could not hit the home run that is the hook. Parks 1–3 are now a ladder (`Ladder`, `Rung`,
  `League`), park 4 is The Show (the old park 1), park 5 on is seeded as above. Each rung takes one
  thing away, which is how the mechanics get uncovered without a tutorial (§15):

  | Park | Scoreboard | Wall | Clears at | Pitches | Strikes | Reach / timing | Help |
  |---|---|---|---|---|---|---|---|
  | 1 | `SINGLE-A` | 280 / 6 | ~80 mph | fastball 68–76 | all | 14 px / 0.40 | swing guide, timing ring, coaching |
  | 2 | `DOUBLE-A` | 320 / 8 | ~88 mph | fastball 80–88, changeup 68–76 | 85 % | 12 px / 0.34 | timing ring, coaching |
  | 3 | `TRIPLE-A` | 350 / 10 | ~93 mph | full table | 75 % | 10 px / 0.30 | coaching |
  | 4 | `PARK 4` | 380 / 10 | ~97 mph | full table | 65 % | 9 px / 0.28 | none, ever again |

  **Swing guide:** a 2 px dashed chalk arrow through the pitch's target at 28°, during windup and
  pitch. **Timing ring:** a chalk dotted ring on the target and a `score` ring that closes onto it as
  the ball arrives. Both give the target away before the throw, on purpose. **Coaching:** one word
  under the landing number for a ball that stayed in: `SWING UP` (< 12°), `LEVEL OUT` (> 42°),
  `FASTER` (< 88 mph), aim before power. Clearing Triple-A blinks `CALLED UP` once per career and
  records `pitchesToTheShow`. The minors count toward every stat and the streak. A one-way door:
  nobody is sent down. These are a trial: judge the guide and ring on a phone and cut what
  hand-holds (Fruit Ninja teaches with no overlays at all; its menu *is* the slice).
- **Headline:** `PARK n  p PITCHES`, top-left of the at-bat view. Pitches are the cost and never
  reset.
- **Home run streak:** consecutive home runs. Shown under the headline from 2 up (hidden during
  the contact freeze, which would spoil the cut) and under `HR` in the wide view. A whiff, a called
  strike or any contact that is not a home run sets it to 0. Taking a ball keeps it
  (`StatRules.takenBallKeepsStreak`): plate discipline is a skill, and balls carry a contact penalty.
  Best streak persists.
- **Tally** (`Tally`, a keyed bag of `Stat`s, so old saves load in new builds): count everything,
  Rocket League style. Pitches, parks cleared, fewest pitches to clear a park, time at the plate;
  swings, whiffs, called strikes, balls taken, chases; hits, barrels, average and best exit velo,
  average launch angle, grounders / liners / fly balls / pop-ups, off the wall; total feet,
  longest, highest apex, longest hang; home runs, no-doubters, wall scrapers, moonshots, lasers;
  HR and hit streaks with bests; seen / hit / HR per pitch type. Sorting rules are `StatRules`.
- **Stats board:** tap the outfield scoreboard in the at-bat view; tap anywhere to leave. It is the
  scoreboard up close, not a menu: nothing on it can be chosen or changed. The machine does not
  tick while it is up, and the tap is not a swing.
- Persist at every beat change (`UserDefaults`, one JSON blob: park number + tally). The pitch
  sequence is not saved.
- Game Center (M5): best HR streak, fewest pitches to park 100, and the daily card. **Not**
  longest: exit velo is capped and flight is deterministic, so everyone reaches the same maximum.
- **Approved 2026-09-19, not built:** a daily card (the first ten pitches of the day are seeded by
  the date, same park and pitches for everyone, Wordle-style share string; name undecided, not
  "Daily Ten"), a pixel-perfect **replay** clip as the share artifact (re-rendered from seed +
  launch through `PixelCanvas`), **more park variety** (seeded landmarks and rare events, same for
  everyone on park N), and **more feel** (M3). See issues.

## 11. Audio and haptics (M5)

First pass built 2026-09-19 at Dwight's request ("simple beeps and boops will work for now… a
crack of the bat, an ump grunting, and crowds cheering"). **No audio files.** Every sound is
arithmetic in `Synth` (noise, oscillators, biquads: the spirit of an FM chip and a noise channel),
rendered to buffers at launch and fired by `SoundBoard`. Placeholders by design; replace them one
at a time.

| Moment | Cue from Core | Sound | Haptic |
|---|---|---|---|
| Bat on ball | `slice` | crack, 9 steps by exit velo: a weak one is a low *tock*, a barrel is bright with the stands' slap coming back | `.rigid`, harder the better it is hit |
| Swing and miss | `sliceMissed` | a whiff of air | — |
| Taken strike / ball | `.called` | the ump: a two-beat bark for a strike, one low short grunt for a ball | — |
| Clears the wall | `.clearedWall` | crowd cheer, 5 sizes by how far past the wall it lands; whistles in the big ones | `.success` |
| Off the wall | `.hitWall` | wall thump, the crowd's *ohh*, then the sad trombone: *womp, wommmp* | `.heavy` |
| Two straight home runs | — | the organ runs up the scale over the landing number and the crowd answers *CHARGE!*: one more starts the fireworks (§17). The pitch cuts the organ off mid-note if it is still playing, and then nobody answers | — |
| Lands in the park | `.landed` | ground thud (a home run lands out of earshot) | — |
| A streak of 3+ ends | — | three square notes down, held until the landing number so it cannot spoil the flight | — |
| Called up | `.calledUp` | a major arpeggio, up | — |

**The organ** (#17) is a synthesized drawbar organ with its own player node. It lives in the gaps
and **stops dead when the pitch is thrown**, as a real organist does when the pitcher comes set.
The rally prompt is a run up the major scale, deliberately **not** the famous six-note "Charge!"
fanfare, which was written in 1946 and is still under copyright; license it or leave it.

The cues are `Transition`s that fire as playback reaches the moment, so the crowd reacts when the
ball clears the wall, not when the bat meets it. **Nothing sounds during the pitch: silence is the
tension.** The audio session is `.ambient`: the ring/silent switch mutes the game and the
player's own music or podcast keeps playing underneath. `-mute` silences it for simulator runs.

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
| every column of the minors table (§10) | `Ladder` → `Rung` | table | how gentle each rung is, and what help it shows |
| `guideAngleDegrees`, `coachLowAngle` / `coachHighAngle` / `coachWeakExitVelocity` | `Ladder` | 28°, 12° / 42° / 88 mph | the swing guide's angle and when each coaching word fires |
| `closeReachFeet` / `closeLeadFeet` | `CameraRules` | 60 / 100 ft | which balls earn the close camera, and how early it cuts in |
| `takenBallKeepsStreak` | `StatRules` | true | whether a taken ball ends the HR streak |
| `barrelMinExitVelocity` / `barrelWindow` | `StatRules` | 98 mph / 26–30° | barrel call, window widens 1.1° a side per mph |
| `noDoubterMarginFeet` / `wallScraperMarginFeet` | `StatRules` | 50 / 12 | how far past the wall a HR landed |
| `moonshotApexFeet` / `laserMaxAngle` | `StatRules` | 150 ft / 20° | the other two HR kinds |
| `lineDriveFrom` / `flyBallFrom` / `popUpFrom` | `StatRules` | 10° / 25° / 50° | Statcast batted-ball classes |

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
  screenshots, store listing. Name decision. The contract card and the one purchase (§16), which
  wants the daily card (#3) shipped first.

## 14. Open questions

1. **Name.** "Sandlot Derby" is a working title.
2. **Portrait?** Landscape is assumed because the wide view is a side view. A portrait variant
   would stack the wide view above the at-bat view and lose the cut. Decide after M2 on a phone.
3. **Wind.** Parks reserve it. It would show as a flag on the wall and a horizontal term in
   flight. Not before M4.
4. **Sharing.** A park number plus the tally is a screenshot-able brag. Nothing more is planned.
5. **The wrist.** An Apple Watch version is specced in [`docs/watch.md`](docs/watch.md): the centre
   column of the at-bat frame cut out 1:1, the number over the arc in the wide view, haptics
   instead of sound. A proposal until its W2 go/no-go; nothing in this document changes for it yet.

## 15. Non-goals

Fielders, pitching, base running, teams, licences, multiplayer, seasons, a tutorial. Ads of any
kind. Any purchase other than the one in §16: no consumables, currencies, energy, upgrades,
subscriptions, loot, store screen or nag prompts, and nothing money can buy ever changes how the
ball flies.

## 16. Pricing: free to start, pay once at the call-up

Decided by Dwight 2026-09-19 (issue #11): free to start, **$1.99** ("easy impulse buy, still
leaves room for discounts"), and the three minor-league parks are the whole trial ("try before
you buy for sure, that should be enough"). Not freemium: one purchase, once, no ads. Nothing here
applies to TestFlight, which is free.

**Why this and not the others.** Paid upfront (Desert Golfing) puts a price tag at the end of
every shared link for a game nobody has heard of. Ads only pay at a scale a solo launch will not
reach, would wreck the pitch → cut rhythm and the 16-colour canvas, and throw away "no ads, no
tricks", which is the pitch to players and press. At ~10k installs all three earn about the same
small money, so price for reach and brand.

**What is free, forever:** the minors (parks 1–3), the daily card (#3, played in a Show-league
park so it is a taste of what is sold), replay sharing (#4), the stats board and every stat, the
daily and HR-streak leaderboards. A paywalled share loop is a dead share loop.

**What the purchase buys:** The Show, meaning park 4 and every park after it, and with them the
career (the "fewest pitches to park 100" board). One non-consumable, `show.contract`, Family
Sharing on, **$1.99**. Discounts are store-side price changes (a launch week, Opening Day, the
Home Run Derby): the card simply shows whatever the store charges today. The game itself never
announces a sale, counts one down or strikes a price through.

**The moment.** The home run that clears Triple-A plays out as now: result hold, `CALLED UP`. If
the player is not entitled, the cut back goes to the **contract card** instead of park 4:

- A scoreboard-styled card in the bitmap face: `THE SHOW`, the price, `ONE TIME`, `NO ADS  NO
  SUBSCRIPTION`, and a dotted line ending in `X`. **Slicing the dotted line signs it**, because a
  slice is the only input the game has. That opens the system purchase sheet.
- Success: one white frame, hard cut to the windup in park 4. Pending (Ask to Buy): `PENDING`, back
  to Triple-A, and the cut to park 4 happens when the transaction lands. Cancel or failure: the
  card stays, with one plain word (`CANCELLED`, `NO CONNECTION`).
- `RESTORE` in the corner calls `AppStore.sync()`. Entitlements are also read silently at every
  launch, so a reinstall or a new phone just works; the word is there because App Review requires it.
- A tap anywhere off the line declines. **Declining is never punished and never nagged:** the
  player returns to Triple-A, which goes on counting every stat and the streak. The card is offered
  automatically exactly once per career. After that it lives on the stats board as one row
  (`THE SHOW  $1.99  SLICE TO SIGN`). No timers, sale banners, badges or reminders.
- The price is the store's localized `displayPrice`. The 3×5 face gains `$ € £ ¥`; any other
  currency is shown as its ISO code (`BRL 14.90`), which the face already has.

**Core.** `DerbyMachine.parkCeiling: Int?` (nil = no ceiling). A home run in the ceiling park does
not advance; it emits `.calledUp` so the scene can show the card, and counts as a home run in
every other way. Core knows nothing about money; the app sets the ceiling from the entitlement.
Tested like everything else.

**App.** StoreKit 2 only, no server: `Product.products`, `purchase()`,
`Transaction.currentEntitlements` at launch, `Transaction.updates` for purchases made elsewhere and
for refunds. A cached flag in `UserDefaults` lets an entitled player start offline. On a refund
the ceiling becomes the park the player is standing in: nothing is taken away, they just stop
advancing. A `.storekit` configuration file in the project so the whole flow runs in the simulator.

**Grandfathering.** Any save already at park 4 or beyond on the first launch of the paywalled
build is entitled for good. Only beta testers can be in that state, since a new save cannot pass
park 3 without the purchase.

**Cosmetics.** Earned, not sold, at launch. A theme is another 16-colour palette line (Game Boy
green, CGA, night-only, cream throwbacks) and a uniform is two colours, so they are cheap to make
and are rewards for the long game (park 100, a 10-HR streak, `pitchesToTheShow` under some
number). Chosen on the stats board. They are screenshots and retention, not revenue.

**Store listing says it straight:** "Free to start. One purchase unlocks The Show. No ads, no
subscription." Privacy label: Data Not Collected, because there is no SDK to collect any. Enrol in
the App Store Small Business Program (15 %).

**If it ever gets big**, the only ad that fits is diegetic: a sponsor board on the outfield wall,
direct-sold or swapped with other indies, drawn in the palette. Never an interstitial, a banner
or a rewarded video.

**Build order (M5):** `parkCeiling` + tests → contract card scene → StoreKit 2 with the local
configuration file → sandbox on TestFlight → grandfathering → listing copy.

**Worth watching in the beta, not a blocker:** a good player clears the minors in three swings, so
the trial can be short. Median pitches-to-call-up says how short, and the free daily card (#3) is
what keeps a non-payer around, so ship it first.

**Open:**
1. One paid "supporter pack" of palettes later, or cosmetics stay earned-only forever?
2. Fallback if the paywall tests badly: paid upfront at $1.99, smaller audience, lean on press.

## 17. Life: fireworks, sky and backdrops

Asked for by Dwight 2026-09-19 ("fireworks celebration on HR and add a bit of life like clouds and
birds and background elements"). **Spec only, nothing built; the choices are Claude's and
unreviewed.** Folds in the unbuilt night kit from §8 and the plain green band behind the wall (#5).

**The rules it lives inside.** One palette line: every new thing borrows a colour by role, no new
hex. No alpha, so nothing fades: it blinks, shrinks or stops. Whole pixels only. The motion budget
(§9) holds: the ball and its trail are the only smooth things on screen, so everything here steps
at 10 Hz or slower and animates in two frames. Nothing new moves in the strike zone's
neighbourhood, and nothing new makes a sound during the pitch.

**Everything is a pure function.** What a park looks like is seeded data in Core
(`Park.scenery`, a pure function of N like the wall, tested the same way), and what moves is a
function of that seed and a clock the machine already owns (`secondsPlayed`), so park 87 looks the
same on every phone and the replay clip (#4) reproduces the sky, the birds and the fireworks
exactly. Scenes only draw.

### Fireworks

- **When:** on `.clearedWall`, the same cue as the cheer. They run through the rest of the flight
  and the result hold and **stop dead at the cut back to the plate**. About two seconds. The next
  pitch gets a clean sky and silence.
- **Where:** in the sky, which "never moves" (§8), so they are screen-space and identical in the
  close and wide framings: the right 45 % of the screen, bursting between y = 20 and y = 110,
  behind the field and behind all text. The landing number is always drawn on top.
- **How big follows the streak, not the hit** (Dwight, 2026-09-19: "maybe we build up to fireworks
  after a few homers"; the numbers are Claude's). One home run does not get fireworks. The sky is
  something you build, and it goes dark the moment the streak does, which is the streak's whole
  point: the one number that can go back to 0 now has something to lose on screen.

  | HR streak | The sky |
  |---|---|
  | 1 | nothing. The cheer, the crowd bounce, the lights chase at night |
  | 2 | nothing, but the crowd is a size louder: something is starting |
  | 3 | **the first firework:** one shell |
  | 4 | 2 shells |
  | 5 | 3 shells |
  | 6–9 | 4, 5, 6, 7 shells |
  | 10, and every 5 after | a finale: 10, overlapping |
  | between finales past 10 | 8 shells |
  | the call-up, whatever the streak | a finale, once per career |

  Two separate dials, so neither muddies the other: **distance drives the crowd** (the cheer's
  size, §11) and **the streak drives the sky**. A no-doubter adds one shell, but only once the
  streak has earned fireworks at all; a lone 450-footer gets the loudest cheer there is and a
  quiet sky. When a streak of 3+ ends, the three notes down (§11) play under an empty sky.

- **A shell:** a 1 px `chalk` streak climbs for 0.25 s, then 28–40 particles burst on a ring with
  seeded jitter, fall under gravity with drag (closed form, so there is no particle state: every
  particle's position is `f(seed, t)`), and live 0.7 s. They die without alpha: 2 px for the first
  half, 1 px after, blinking on alternate frames for the last 0.15 s. Shells launch 0.18 s apart.
- **Colour:** one per shell, borrowed by role: `score`, `cap`, `chalk`, `skin`, and `sky3` at
  night. By day they sit in the dark top sky band where they read; at night they are the show.
- **Sound:** a soft pop per burst (short noise burst, then a crackle tail), mixed under the cheer.
  Synthesized like the rest (§11). No extra haptic: `.success` already fired.
- **Seed:** park number and career pitch count, so no two are alike and a replay matches.

### Sky

- **Clouds.** Two to four per view, seeded per park: blocky stamps of three or four `chalk`
  rectangles with a `sky3` underside. They drift in whole pixels at the park's **breeze** (seeded,
  −3…+3 px/s, stepping at most 4 times a second) and wrap. Night: `#446688` stamps, dimmer. The
  at-bat view and the side view look in different directions, so each has its own clouds; wide and
  close share one sky. The breeze is cosmetic today and is the tell for **wind** when §14 ships it:
  the same number will push the ball, and the clouds and flags will already be showing it.
- **Birds.** Every 20–40 s (seeded) a flock of one to five crosses high, y < 60, well above the
  scoreboard and nowhere near the zone: 3 px `ink` marks, two flap frames at 4 Hz, with the breeze.
  *Later, with #5:* in the side view a bird can be on the flight path; a ball passing within 2 px
  bursts it into `chalk` feathers, counts `birdsHit`, and changes nothing about the flight. Rarity
  comes free from the geometry.
- **Night kit (§8, still unbuilt).** Forty fixed stars, one in eight blinking on a slow seeded
  period, and a `chalk` moon with a night-coloured bite, in a seeded place in one park in four.
- **Stadium lights at night** (Dwight, 2026-09-19). Every night park has them, two to four towers,
  seeded. A tower is an `ink` lattice pole carrying a lamp bank: a grid of `chalk` lamps with
  `score` centres. With no alpha, the glow is a **dithered halo**: a checkerboard of `chalk` on the
  night sky, three or four rings thinning outward, which the "dither only in the sky" rule already
  allows. Side view: the towers stand behind the stands and rise out of frame in the close camera,
  so the bank is what you see in the wide one. At-bat view: they flank the scoreboard above the
  wall, well clear of the zone. Stars are not drawn inside a halo: the lights wash them out. The
  field does not change colour (night swaps the sky and nothing else, `docs/palette.md`).
  The lamps are steady during the pitch. On a home run they **chase**, bank to bank, in two frames
  for as long as the cheer plays, with the fireworks going off between them. The minors and The
  Show are day games, so the first lights a player sees are a seeded park's: something to arrive
  at. *Later, with #5:* a no-doubter that reaches a bank puts it out in a shower of `score` sparks
  and counts `lightsOut`. One per career would be enough.

### Backdrops

- **Side view: stands instead of the green band.** Behind the wall, a stepped bleacher profile in
  `ink` and `wall` rising to about 60 ft at 150 ft back; a `score` foul pole on the wall; flags
  (`cap`, `chalk`) in two flutter frames pointing with the breeze; towers at night. The crowd is a
  `chalk` / `skin` / `cap` speckle that **bounces two frames while the cheer plays** and sits still
  otherwise. The stands draw in front of the ball, so a home run drops into the crowd and is gone,
  with a little `chalk` pop where it went in.
- **That makes the landing number a projection, and says so by being honest about it:** the flight
  is still integrated to the ground as if nothing were in the way, exactly what Statcast's
  "projected distance" is. No physics changes; wall hits and balls in play are untouched.
- **At-bat view: a horizon.** A low band above the wall, y 86–96, and two small flags on the
  scoreboard. Far things are `sky2` on the `sky3` band (distance with no new colour), near things
  `wall` and `shade`, night silhouettes `ink`.
- **The ladder has its own backdrops**, so moving up looks like moving up:

  | Park | At-bat horizon | Side view behind the wall |
  |---|---|---|
  | SINGLE-A | a treeline, one house | a chain-link fence, trees, no stands |
  | DOUBLE-A | trees, a water tower | one low bleacher |
  | TRIPLE-A | bleachers, light poles | bleachers, flags |
  | The Show | an upper deck, flags | full stands, flags, towers |

  From park 5 the backdrop is drawn from a kit, a pure function of N: skyline, mountains, treeline,
  water tower, smokestacks, bridge, palms, ferris wheel. One far piece and one near piece per park.

### Building it

- **`Park.scenery`** in Core: backdrop pieces, cloud seeds, breeze, moon, flags. Seeded, Equatable,
  tested for determinism and for the ladder's fixed entries. No drawing knowledge.
- **A backdrop cache** in the app: everything that does not move is drawn once per (park, canvas
  width, camera) into a `PixelCanvas` and copied each frame. Only clouds, birds, flags, the crowd
  and fireworks are drawn per frame, a few hundred pixel writes.
- **`Fireworks`**: a pure `particles(seed:time:) → [(x, y, size, colour)]` in the app, unit-testable
  without a scene.
- **Draw order, side view:** sky → stars / moon → light halos → clouds → fireworks → birds → towers
  → field and wall face → trail and ball → stands and crowd → text.
- **Order of work:** (1) backdrop cache, stands in the side view, horizon in the at-bat view;
  (2) clouds and breeze; (3) fireworks and pops; (4) night kit: stars, moon, stadium lights and
  their chase; (5) birds, flags, crowd bounce; (6) the bird strike, the lights-out shot and their
  stats, with #5.

**Open:**
1. ~~Fireworks on every home run or only notable ones?~~ Answered 2026-09-19: they build with the
   streak, first shell on the third straight. Still open: is 3 the right place to start, or 2?
   Judge it once it is on a phone; a streak of 3 in The Show is rare, in Single-A it is not.
2. Daytime fireworks at all, or night parks only with something else by day (streamers, a
   scoreboard light show)?
3. ~~Should a home run vanish into the stands?~~ Answered 2026-09-19: yes ("ball vanish sounds
   good"). The landing number is a projected distance.
4. Crowd murmur as ambience between pitches would add life and break "silence is the tension".
   Claude says no; worth hearing once before deciding.
