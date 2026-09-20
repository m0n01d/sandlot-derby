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
- Game Center (M5): best HR streak, fewest pitches to park 100, and the Warm Up (#3, §18). **Not**
  longest: exit velo is capped and flight is deterministic, so everyone reaches the same maximum.
- **Approved 2026-09-19, not built:** the Warm Up (#3, §18; the first ten pitches of the day,
  seeded by the date, same park and pitches for everyone, Wordle-style share string), a
  pixel-perfect **replay** clip as the share artifact (re-rendered from seed + launch through
  `PixelCanvas`), **more park variety** (seeded landmarks and rare events, same for everyone on
  park N), and **more feel** (M3). See issues.

## 11. Audio and haptics (M5)

First pass built 2026-09-19 at Dwight's request ("simple beeps and boops will work for now… a
crack of the bat, an ump grunting, and crowds cheering"). **No audio files.** Every sound is
arithmetic in `Synth` (noise, oscillators, biquads: the spirit of an FM chip and a noise channel),
fired by `SoundBoard`. Placeholders by design; replace them one at a time. Most buffers render at
launch; the three longest ones (the tunes below) render off the main thread the first time they
are needed instead, so opening the app never pays for a tune nobody has reached yet.

| Moment | Cue from Core | Sound | Haptic |
|---|---|---|---|
| Bat on ball | `slice` | crack, 9 steps by exit velo: a weak one is a low *tock*, a barrel is bright with the stands' slap coming back | `.rigid`, harder the better it is hit |
| Swing and miss | `sliceMissed` | a whiff of air | — |
| Taken strike / ball | `.called` | the ump: a two-beat bark for a strike, one low short grunt for a ball | — |
| Two called strikes in a row | `.calledStrikesInARow` | the organ plays *Three Blind Mice*'s opening call (there is no third strike in this game) | — |
| Clears the wall | `.clearedWall` | crowd cheer, 5 sizes by how far past the wall it lands; whistles in the big ones | `.success` |
| Off the wall | `.hitWall` | wall thump, the crowd's *ohh*, then the sad trombone: *womp, wommmp* | `.heavy` |
| Two straight home runs | — | the organ runs up the scale over the landing number and the crowd answers *CHARGE!*: one more starts the fireworks (§17). The pitch cuts the organ off mid-note if it is still playing, and then nobody answers | — |
| Lands in the park | `.landed` | ground thud (a home run lands out of earshot) | — |
| A streak of 3–4 ends | — | three square notes down, held until the landing number so it cannot spoil the flight | — |
| A streak of 5+ ends | — | the organ plays the opening of Chopin's *Marche funèbre* instead, same lead-in. Doesn't replace the streak of 3–4 above | — |
| Stats board open | `showStats`/`hideStats` | the organ plays *Take Me Out to the Ball Game* (first two lines), starting a beat after the board opens, looping once if still up, stopping dead the moment it closes | — |
| Called up | `.calledUp` | a major arpeggio, up | — |

**The organ** (#17) is a synthesized drawbar organ with its own player node. It lives in the gaps
and **stops dead when the pitch is thrown**, as a real organist does when the pitcher comes set.
The rally prompt is a run up the major scale, deliberately **not** the famous six-note "Charge!"
fanfare, which was written in 1946 and is still under copyright; license it or leave it.

**The rest of the organ** (#17, 2026-09-19, Claude's, unreviewed — nobody has heard any of this
against the real songs yet): three more tunes through the same voice, all public domain on
purpose — *Three Blind Mice* (trad., 1609), the opening of Chopin's *Marche funèbre* (1837, from
his Piano Sonata No. 2), and the first two lines of *Take Me Out to the Ball Game*
(Norworth/Von Tilzer, 1908), none of them transcribed from a score, so treat the exact notes as a
best effort pending a listen. The Chopin is tempo'd differently from the other two on purpose: its
real tempo is a slow Lento, so rather than compress the whole phrase to fit (which would lose the
dotted "dum, dum-da-dum" that makes it recognisable), only its first bar is paced to clear the
tightest gap before the next windup (~1.6 s); the turn that follows is left at its natural speed
and is **not** guaranteed to finish — `.pitchThrown` is free to cut it off dead mid-phrase, exactly
as it already does to the charge prompt. That's the organ's normal behaviour here, not a bug. Also
undecided by the issue, so Claude's call: **Single-A has no organist.** `Rung.organ` is `false`
there and `true` in Double-A and Triple-A; The Show has no rung and always has one.
`DerbyMachine.hasOrgan` reads it, and every organ cue in the table above — the existing charge
prompt included — is gated on it. Where Single-A would have played Chopin (a streak of 5+ dying),
it just gets the ordinary three notes down instead, same as a streak of 3–4; nothing is silent
there that used to make a sound.

The cues are `Transition`s that fire as playback reaches the moment, so the crowd reacts when the
ball clears the wall, not when the bat meets it. **Nothing sounds during the pitch: silence is the
tension.** The audio session is `.ambient`: the ring/silent switch mutes the game and the
player's own music or podcast keeps playing underneath. `-mute` silences it for simulator runs.

## 12. Tuning knobs

All live in `DerbyCore` structs with doc comments, except a few marked `(App)` — pure layout, no
gameplay effect, living beside the scene that draws them. Defaults are the prototype's.

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
| `contactHoldWeak` / `contactHoldBarrel` | `Timings` | 0.22 s / 0.50 s | the slash freeze, interpolated linearly on the swing's contact quality (issue #20) |
| `liftCoefficient` | `FlightParams` | 0.15 | under-rewards high spinny hits on purpose |
| wall ranges | `Park.Rules` | 330–410 / 6–26 | park variety |
| every column of the minors table (§10) | `Ladder` → `Rung` | table | how gentle each rung is, and what help it shows |
| `Rung.organ` | `Ladder` → `Rung` | false (Single-A) / true (Double-A, Triple-A, The Show) | whether the rung has a ballpark organ; gates every organ cue |
| `guideAngleDegrees`, `coachLowAngle` / `coachHighAngle` / `coachWeakExitVelocity` | `Ladder` | 28°, 12° / 42° / 88 mph | the swing guide's angle and when each coaching word fires |
| `closeReachFeet` / `closeLeadFeet` | `CameraRules` | 60 / 100 ft | which balls earn the close camera, and how early it cuts in |
| `takenBallKeepsStreak` | `StatRules` | true | whether a taken ball ends the HR streak |
| `barrelMinExitVelocity` / `barrelWindow` | `StatRules` | 98 mph / 26–30° | barrel call, window widens 1.1° a side per mph |
| `noDoubterMarginFeet` / `wallScraperMarginFeet` | `StatRules` | 50 / 12 | how far past the wall a HR landed |
| `moonshotApexFeet` / `laserMaxAngle` | `StatRules` | 150 ft / 20° | the other two HR kinds |
| `lineDriveFrom` / `flyBallFrom` / `popUpFrom` | `StatRules` | 10° / 25° / 50° | Statcast batted-ball classes |
| `threeBlindMiceBPM` / `funeralMarchBPM` / `takeMeOutBPM` | `Synth` | 300 / 225 / 150 | tempo of the three organ tunes (§11) |
| `statsOrganDelay` | `SoundBoard` | 1.0 s | delay before *Take Me Out* starts over the stats board |
| the streak table, plus shell timing and shape | `FireworksRules` | table | how many shells a HR streak (or the call-up) earns, and how each shell launches, bursts and falls (§17) |
| the cloud, breeze, stands and night-sky ranges | `SceneryRules` | table | clouds, breeze, stands height/depth by tier, night towers and moon odds (§17) |
| the horizon, stands and cloud-drift ranges | `BackdropLayout` / `Clouds.Rules` (App) | table | horizon band, stands profile, crowd density, cloud drift rate and colours (§17) |
| the card's panel, text and signature-line geometry | `ContractCardLayout` (App) | table | where the contract card draws each line (§16) |
| `contractRowBand` / `contractMinimumSliceLength` | `StatsScene` (App) | 6 / 12 | hit test for the stats-board contract row (§16) |

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
  Retune `fullPowerSpeed` and `hitMarginPixels` on a real phone. Closed 2026-09-19; the leftovers
  (hitstop by quality, `BARREL` call, third pitcher pose, held-finger swing-miss) were built in
  #23.
- **M4 — parks and score.** Seeded parks, night swap, tally persistence, park advance on HR.
- **M5 — ship.** Built: audio and haptics, the organ tunes, `parkCeiling`, the contract card, and
  StoreKit 2 wiring with a local `.storekit` file. Not built or not exercised: the purchase,
  pending, refund and restore paths have never been run for real — a `.storekit` configuration
  only takes effect when the app is launched from Xcode, never from `simctl` — plus the app icon,
  Game Center, TestFlight, the store listing, and the Warm Up (#3, §18).

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

**What is free, forever:** the minors (parks 1–3), the Warm Up (#3, §18; played in a Show-league
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
- The price is the store's localized `displayPrice`, drawn on the card in the **5×7** face, which
  gains `$ € £ ¥` plus `.` and `,`. Not the 3×5 face, as this section first said: a 3×5 cell has
  no room for the stroke that has to overshoot the `S` above and below, and without it a `$`
  reads as a blocky `5` — "$1.99" came out as "51.99" (corrected 2026-09-19). Any currency the
  5×7 face cannot spell is shown as its ISO code (`BRL 14.90`) in the 3×5 face. The stats-board
  row always uses the ISO form (`USD 1.99`): its rows are 7 px apart and its grammar is 3×5
  throughout, so a 7 px-tall glyph would touch its neighbours.

**Core.** `DerbyMachine.parkCeiling: Int?` (nil = no ceiling). A home run in the ceiling park does
not advance; it emits `.calledUp` so the scene can show the card, and counts as a home run in
every other way. Core knows nothing about money; the app sets the ceiling from the entitlement.
Tested like everything else. **Built 2026-09-19**, with two things the paragraph above left open:

- **Paying the advance.** The home run at the ceiling leaves an advance *owed*. When the app sets
  `parkCeiling` back to nil (signed, restored, a pending purchase landing), the machine pays it at
  the next windup: `.parkChanged`, the park's books close, `pitchesToTheShow` is recorded, a fresh
  windup under the new park's rules, and **no second `.calledUp`**. A pitch already in the air
  resolves in Triple-A first. With nothing owed, lifting the ceiling changes nothing.
- **The debt is not saved.** Decline, quit, come back and sign from the stats board, and it takes
  one more Triple-A home run to go up. That is a call-up with the fanfare, not a penalty, and it
  keeps a bookkeeping key out of the tally.
- The park's books (`parksCleared`, `pitchesThisPark`, `fewestPitchesToClearPark`) stay open at
  the ceiling. `isAtCeiling` is `park.number >= parkCeiling`, so a refund's ceiling just works.

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

**Built 2026-09-19** (Claude, unreviewed), app side: `Store` (StoreKit 2, no server),
`ContractScene`, the ceiling wired to the entitlement, the stats-board row, and
`App/SandlotDerby.storekit`. What the paragraphs above left for the build to decide:

- **The ceiling is `max(lastMinorsPark, currentPark)`**, derived from `League.theShow`, so the
  refund rule and the ordinary rule are one line: a refunded player stops where they stand and a
  new player stops at Triple-A. It is applied at launch and on every entitlement change.
- **A tap on the dotted line neither signs nor declines.** Signing needs a stroke of at least
  `minimumSliceLength` that crosses the line. A tap that lands on the band was aimed at it, so
  treating it as a decline would punish a missed stroke; a tap anywhere else declines, as specced.
- **The board row goes first, not last.** The board runs out of columns on a 320-wide canvas and
  drops whatever is last, and a row nobody can reach is not an offer.
- **The price is `-` until the store answers**, rather than a number the game made up.
- **The currency glyphs are in the 5×7 face, not the 3×5 one**, and the 3×5 face has none, so
  the bad `$` cannot be drawn again. Two 3×5 attempts were tried and both failed to read: a
  zigzag-plus-stroke came out as `£`, and the face's own `S` with the middle column filled came
  out as `5`. Seven rows are what the symbol needs.
- **Not built, because it cannot be reached from `simctl`:** the purchase, pending, refund and
  restore paths were never exercised. A `.storekit` file only takes effect when the app is
  launched from Xcode, so every screenshot was taken against no store at all.

**Build order (M5):** ~~`parkCeiling` + tests~~ (done) → ~~contract card scene~~ (done) →
~~StoreKit 2 with the local configuration file~~ (done, untested against a real store) → sandbox
on TestFlight → ~~grandfathering~~ (done) → listing copy.

**Worth watching in the beta, not a blocker:** a good player clears the minors in three swings, so
the trial can be short. Median pitches-to-call-up says how short, and the free Warm Up (#3, §18)
is what keeps a non-payer around, so ship it first.

**Open:**
1. One paid "supporter pack" of palettes later, or cosmetics stay earned-only forever?
2. Fallback if the paywall tests badly: paid upfront at $1.99, smaller audience, lean on press.
3. **Is `.calledUp` on every ceiling home run a nag?** As specced and built, a player who declined
   gets `CALLED UP` and the arpeggio on *every* Triple-A home run, forever. Read one way that is a
   celebration; read another it is exactly the reminder "never nagged" rules out. The quiet
   alternative: the machine announces the first one per session and the app treats the rest as
   ordinary home runs. Decide when the contract card is built and it can be heard.
   **Still open, now with a number** (2026-09-19): a `-declined -autoslice` run reached 11 home
   runs and 0 parks cleared in about a minute, so a robot saw `CALLED UP` and heard the arpeggio
   eleven times in Triple-A. It is built as specced and not decided. A human swinging at a
   fraction of that rate may find it a celebration; the robot makes it look like a nag.

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
- **Built 2026-09-19 (Claude's, unreviewed).** Live in `Core/Sources/DerbyCore/Fireworks.swift`,
  not the app as first written above: the maths (the streak table, a shell's ring and fall,
  `FireworksRules`) is pure and Foundation-only, so `swift test` covers it and the planned replay
  clip and any other host can reuse it without SpriteKit. `WideScene` only turns
  `Fireworks.particles(show:at:)`'s roles into palette pixels. `DerbyMachine.fireworks` is set at
  the `.clearedWall` cue (the streak `countContact` already extended at contact, well before the
  cue, so the third straight home run's own show sees a streak of 3) and cleared the instant the
  machine leaves `.result`. The call-up's "once per career" needs no extra flag: Triple-A is a
  one-way door, so `isBeingCalledUp` can only ever fire once regardless. A no-doubter's bonus
  shell stacks even on a finale or a call-up (untested by the table above, which doesn't say);
  seen in practice on a 90+ ft no-doubter, e.g. streak 3 + no-doubter = 2 shells, streak 10/finale
  + no-doubter = 11. Screenshots and a DEBUG `-streak <n>` launch argument (starts a career at a
  given home-run streak, implies `-nosave`) are on the PR for issue #14.

### Sky

- **Clouds.** Two to four per view, seeded per park: blocky stamps of three or four `chalk`
  rectangles with a `sky3` underside. They drift in whole pixels at the park's **breeze** (seeded,
  −3…+3 px/s, stepping at most 4 times a second) and wrap. Night: `#446688` stamps, dimmer. The
  at-bat view and the side view look in different directions, so each has its own clouds; wide and
  close share one sky. The breeze is cosmetic today and is the tell for **wind** when §14 ships it:
  the same number will push the ball, and the clouds and flags will already be showing it.
  **Built 2026-09-19** (Claude's, unreviewed). A stamp is a heap, not a row: a wide flat base
  with two or three narrower, taller steps on it, every block running down to a shared baseline
  whose bottom row is the `sky3` underside. Laid side by side as the spec's wording allows, the
  three or four rectangles read as a shelf and not as a cloud. The breeze is rounded, not
  truncated, or it would never reach ±3 and a dead calm would be twice as likely as any other.
- **Birds.** Every 20–40 s (seeded) a flock of one to five crosses high, y < 60, well above the
  scoreboard and nowhere near the zone: 3 px `ink` marks, two flap frames at 4 Hz, with the breeze.
  *Later, with #5:* in the side view a bird can be on the flight path; a ball passing within 2 px
  bursts it into `chalk` feathers, counts `birdsHit`, and changes nothing about the flight. Rarity
  comes free from the geometry.
  **Built 2026-09-19** (Claude's, unreviewed). The 20–40 s is one 30 s slot with its start
  jittered 0–10 s inside it, so consecutive flocks are 30 ± 10 s apart by construction and the
  whole thing stays closed-form — no flock state, no list of upcoming flocks, just
  `f(seed, t)` over the current slot and the one before it (a flock takes 7–11 s to cross, so it
  can outlive its own slot but never two). A bird's mark is a V one frame and a Λ the next, and
  **neighbours beat on opposite frames**, so a flock ripples instead of marching. A flock flies
  downwind; on a dead calm day it picks its own way, which is the only thing the seed decides
  about its direction. At night a bird is drawn **lighter than the sky**, not in `ink`: the same
  trap the side view's far pieces fell into in step 1, since the night sky's upper bands *are*
  `night` and `ink`.
- **Night kit (§8).** Forty fixed stars, one in eight blinking on a slow seeded period, and a
  `chalk` moon with a night-coloured bite, in a seeded place in one park in four.
  **Built 2026-09-19** (Claude's, unreviewed). A blinking star is *out* for 0.4 s every 3–7 s
  rather than on half the time: with no alpha the only choice is there or not, and a 50 % duty
  cycle read as a strobe. Stars sit in y 3–64, which is dark in both views. The moon's bite is a
  `night` disc at 0.82 of its radius, pushed 0.62 of a radius to its seeded side.
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

  **Built 2026-09-19** (Claude's, unreviewed). Five things the spec did not settle:

  - **The halo is an ellipse hugging the bank, not a circle around it**, and it is squashed to
    half height below. A bank is a wide, shallow thing; a round glow around one read as snow
    falling past it, and a symmetrical one put half of itself down the pole, where it read as
    grit rather than light. Three rings — half the pixels, a quarter, an eighth — not four: the
    sparser outer rings of a four-ring halo were scattered confetti, not a glow.
  - **A dark bank in the chase keeps its lamps and loses its `score` centres and all but the
    innermost ring of its halo.** Switching a bank off outright made the towers blink; this way
    the light *travels*, which is what a chase is.
  - **The lattice's colour is the view's, not the spec's `ink`.** The at-bat pole stands wholly
    in the `#446688` horizon band, where `ink` reads, and keeps it. The side view's climbs
    through `night` and `ink` and is drawn lighter than the sky instead — agent C's night rule
    for the far pieces, hit again by the one other thing tall enough to reach those bands.
  - **The at-bat towers are not the side view's seen from the other end.** You are looking the
    other way down the park, so they take fixed slots flanking the scoreboard (x 96/224/62/258,
    standing on the wall band) and only the count and the banks' own shapes carry over. The side
    view's stand at seeded depths behind the wall, in feet, so the close camera simply sees them
    bigger — at 150–190 ft they run out of the top of that frame, which is what makes the bank
    a thing you see in the wide one.
  - **Nothing here is cached.** The chase changes the halo, so the halos are drawn per frame
    before the clouds and the towers per frame after the birds. It is a few thousand pixel
    writes and it keeps §17's draw order honest.

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
- **At-bat view: foul poles** (Dwight, 2026-09-19, #28: "add foul poles to the at bat cam"). One
  at each corner in `score`, 2 px wide, standing on the top of the wall band exactly where its
  foul line meets it, and `score` at night too so they catch the lights. Per league, the way the
  stands' heights step: 16 / 20 / 24 / 28 px from Single-A to The Show and the seeded parks.
  **Built 2026-09-19** (Claude's, unreviewed). Their x comes from the same two constants the
  foul lines are drawn from, hoisted out of `AtBatScene.render` for the purpose, so they stay
  married however wide the canvas is — and **not rounded**: `PixelCanvas.rect` and
  `PixelCanvas.line` both truncate, so passing the line's own endpoint straight through puts the
  pole's first column on the pixel the line ends on. Rounding it first put it one to the right,
  which a full-resolution crop of the corner showed and nothing else would have.
- **The ladder has its own backdrops**, so moving up looks like moving up:

  | Park | At-bat horizon | Side view behind the wall |
  |---|---|---|
  | SINGLE-A | a treeline, one house | a chain-link fence, trees, no stands |
  | DOUBLE-A | trees, a water tower | one low bleacher |
  | TRIPLE-A | bleachers, light poles | bleachers, flags |
  | The Show | an upper deck, flags | full stands, flags, towers |

  From park 5 the backdrop is drawn from a kit, a pure function of N: skyline, mountains, treeline,
  water tower, smokestacks, bridge, palms, ferris wheel. One far piece and one near piece per park.

**Built 2026-09-19** (steps 1 and 2; all of it Claude's and unreviewed). Four things the spec did
not settle, settled by looking at the frames:

- **The stands are `ink` with `wall` deck lips, not the other way round.** In `wall` the stands and
  the outfield wall were one green shape and the wall stopped reading as a wall.
- **The wall's own face is drawn in the same layer as the stands**, after the ball. Without it a
  home run vanished into the crowd and then fell back out of it: past the wall and below its top
  line the ball was painting over the wall it had just cleared. The wall looks exactly as it did.
- **Night turns the side view's backdrop round.** It sits in the `sky2` band, and at night that
  band *is* `ink`, so an `ink` silhouette there is invisible. After dark the far and near pieces
  are lighter than the sky behind them (`#446688`, holes in `ink`), the way a city's glow really
  does pick them out. The at-bat horizon keeps §17's `ink`: its band is `#446688`, where `ink` reads.
- **The Show has no towers**, though the table above lists them: the prose is the tie-breaker
  ("the first lights a player sees are a seeded park's: something to arrive at"), and parks 1–4 are
  day games. Towers are seeded 2–4 for night parks only.

The stands climb in six steps. `SceneryRules` carries each tier's height and depth in feet, so the
place a ball disappears is one number and not a drawing accident: the pop is drawn at the first
point of the flight that is inside the profile the stands were drawn from.

**Step 5, built 2026-09-19** (Claude's, unreviewed). The flags and the crowd **left the backdrop
cache**, because the thing that makes them step 5 is that they move:

- **The flags flutter in two frames**, a high tail and a low one, three rows either way so a flag
  never changes size as it flies. They fly whatever the beat — it is the wind that moves them,
  not the crowd — and they still point with the breeze.
- **The crowd bounces while the cheer plays**, and *half of it* is a pixel higher on each step, so
  the stand ripples instead of sliding. A head near the front of its deck stays down rather than
  float off it.
- **"While the cheer plays" is `DerbyMachine.crowdIsUp`,** a pure property on the machine and not
  a timer in a scene: the ball has cleared the wall (the `.clearedWall` cue's own index) and the
  beat is `.flight` or `.result`. The lights' chase reads the same window. It is deliberately
  *not* `fireworks != nil` — a streak under three earns no shells, and §17's own table says the
  crowd is up for every home run there is. Tested both ways round.
- Drawing the crowd per frame costs about 200 pixel writes and 200 draws from a seeded stream,
  against a backdrop rebuild it no longer forces.

### Building it

- **`Park.scenery`** in Core: backdrop pieces, cloud seeds, breeze, moon, flags. Seeded, Equatable,
  tested for determinism and for the ladder's fixed entries. No drawing knowledge. **Built**: a
  computed property on its own RNG stream, so no park's wall, height or night flag moved —
  `ParkTests` fingerprints all 200 of them to keep it that way.
- **A backdrop cache** in the app: everything that does not move is drawn once per (park, canvas
  width, camera) into a `PixelCanvas` and copied each frame. Only clouds, birds, flags, the crowd
  and fireworks are drawn per frame, a few hundred pixel writes. **Built** as two layers — what
  sits behind the field and what sits in front of the ball — each a sprite on the palette's
  sixteenth entry, transparent, copied by colour key rather than blended. Each is drawn with the
  ground at a canonical 176 and copied down by however far the close camera has lifted it, so the
  lift costs no rebuild; the key is park, canvas width, camera, scale and origin, which in the
  side view means about one rebuild per home run.
- **`Fireworks`**: a pure `particles(seed:time:) → [(x, y, size, colour)]` in the app, unit-testable
  without a scene.
- **Draw order, side view:** sky → stars / moon → light halos → clouds → fireworks → birds → towers
  → field and wall face → trail and ball → stands and crowd → text.
- **Order of work:** (1) backdrop cache, stands in the side view, horizon in the at-bat view;
  (2) clouds and breeze; (3) fireworks and pops; (4) night kit: stars, moon, stadium lights and
  their chase; (5) birds, flags, crowd bounce; (6) the bird strike, the lights-out shot and their
  stats, with #5. **(1) through (5) are built** (2026-09-19); only (6) is left, and it waits on #5.
- **Where step 4 and 5 live.** `Core/Sources/DerbyCore/SkyLife.swift` holds `Star`, `Tower`,
  `Bird`, `SkyLifeRules` and the pure functions — a star's blink, a bank's place in the chase, a
  head's place in the bounce, a flag's flutter frame, and a flock's whole crossing. Every one is
  `f(seed, t)` the way `Fireworks.particles` is, so `swift test` covers them and the replay clip
  (#4) will reproduce them. The seeded *shapes* (how many stars, how tall a tower, where a flock
  may fly) went into `SceneryRules` beside the clouds'; the *rates* are `SkyLifeRules`.
  `App/Sources/SkyArt.swift` turns the answers into palette pixels. This is one Core file rather
  than the `Birds.swift` + `NightSky.swift` the issue sketched: birds, stars and lights are the
  same kind of thing — sky life on a shared clock — and they share the two-frame step helper.
- **The new scenery draws come last in `Scenery.generate`'s stream**, deliberately, so that
  adding the towers and the starfield moved no park's clouds, breeze or moon. `Scenery.towers` is
  now the count of `Scenery.lightTowers` rather than a second stored field saying the same thing.
- **One clock, `SceneryClock.now`.** Clouds, fireworks, stars, birds, flags, the crowd and the
  chase all read `Tally[.secondsPlayed]`, so they step on the same grid. The birds quantise the
  *clock* rather than the time since their own flock set off, for exactly that reason.
- **`-park <n>`**, DEBUG only, starts in park n and implies `-nosave`: the ladder's four rungs and
  a night park are otherwise hours of play away from a screenshot.
- **`-skyclock <seconds>`**, DEBUG only, winds the sky's clock forward: a flock of birds is
  otherwise up to forty seconds away. It moves nothing but scenery, fakes no career state, and so
  is the one debug argument that does *not* imply `-nosave`.

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

## 18. The Warm Up: the first ten pitches of the day

Issue #3; what §16 and §13 used to call "the daily card" before this section existed. Decided by Dwight 2026-09-19: the name ("first 10
pitches is a Warm Up"), the day ("whatever wordle does": the **local calendar day**), and what it
counts toward ("professional batters have to warm up too": everything but the cost). The rest of
this section is Claude's and unreviewed. **Built 2026-09-19** (Claude, unreviewed) — see "What the
build decided" at the end of this section for the eight things the spec left open and one place
where building it showed the spec was wrong.

**What it is.** The first ten pitches of each day are the same for everyone: one park and one pitch
sequence, seeded by the date. There is no menu and no mode to pick: it is how the day starts. Ten
pitches, a result card, a hard cut to your own park's windup. It is free forever (§16) and it is
played in a Show-league park under The Show's rules, so it is a daily taste of what is sold.

**When it starts.** At launch, and whenever the app comes back to the foreground, the app hands
Core today's day number (`YYYYMMDD`, local calendar, local time zone). Core never reads a clock. If
that day is not the saved `warmUp.day`, the Warm Up begins **at the next windup**, never in the
middle of a pitch. Two exceptions:

- **Not before the player can swing.** A save that has not cleared Single-A
  (`parksCleared < WarmUpRules.minParksCleared`, 1) gets no Warm Up: ten Show-league pitches with
  no swing guide are a bad first minute. It starts the first day after they have hit one out.
- `-autoslice` and `-nosave` on their own never start one, so screenshot runs stay what they were.
  DEBUG `-warmup <day>` forces one for that day number and implies `-nosave`.

**The day's card, in Core.** `WarmUp.generate(day:rules:) -> WarmUp`: a pure function of the day
number, like a park is of its number. It holds the park (a wall from the ordinary seeded ranges,
night allowed, league The Show, scenery from §17 seeded by the day) and **all ten pitches,
generated up front** from a `SplitMix64` seeded by the day, so the sequence cannot depend on what
the player does. The career's own generator is never drawn from: the career pitch sequence is
identical whether or not the Warm Up was played. Tested: same day, same card; different days
differ; ten pitches whatever the swings; the career machine is bit-for-bit what it was apart from
the stats below.

**In the machine.** `DerbyMachine.beginWarmUp(_:)` queues it for the next windup, the same way an
owed advance is paid (§16). While it runs, `machine.warmUp` is non-nil, the career park and pitch
are set aside, and the beats are exactly the usual five and a miss. A home run does not change the
park, never emits `.parkChanged` or `.calledUp`, and ignores `parkCeiling`. New transitions:
`.warmUpBegan`, and `.warmUpEnded(WarmUpResult)` when the tenth pitch has resolved and its hold
has played out, after which the machine is back in the career windup. A pitch is spent at
`.pitchThrown`: quit with one in the air and it comes back as taken, so a pitch cannot be peeked
at by quitting.

**What it counts toward.** Every stat in the tally, **except the cost**: `pitches`,
`pitchesThisPark`, and with them `pitchesToTheShow` and `fewestPitchesToClearPark`. They are thrown
in the day's park, not the one being cleared, and a warm-up that made `PARK n · PITCHES` worse
would punish showing up. The career `homeRunStreak` is neither fed nor ended by a Warm Up swing;
the Warm Up has **its own streak**, and `machine.streakNow` is whichever is live, so the fireworks
(§17) and the streak cues (§11) follow it without knowing. New stats: `warmUps` (days played),
`warmUpBestFeet`, `warmUpBestHomeRuns`, `warmUpDaysInARow` and its best. The days-in-a-row count is
on the stats board and nowhere else: it is counted, never dangled.

**On screen.** The headline reads `WARM UP · 3/10` where `PARK n · PITCHES` would be, and the
scoreboard says `WARM UP`. Nothing else changes: same cameras, same cuts, same sounds.

**The result card.** A scoreboard-styled card like the contract card (§16), shown by hard cut on
`.warmUpEnded`, the machine not ticking: `WARM UP 212` (the day's number, counted from
`WarmUpRules.epochDay`, set when the game ships), the ten pitches as ten cells in the palette, the
total feet big in the 5×7 face, home runs, and the day's longest. **Any slice or tap leaves**, by
hard cut to the career windup. `SHARE` sits in a corner the way `RESTORE` does on the contract
card. Afterwards the card is one row on the stats board (`WARM UP 212  1847 FT  SHARE`) until
tomorrow's replaces it.

**The share string.** Text, because it has to paste anywhere:

```
WARM UP 212 · 1,847 FT
💥⬜🟩💥⬛🟨💥🟩⬜💥
<link>
```

One glyph per pitch: 💥 home run, 🟨 off the wall, 🟩 in play, ⬜ swing and miss, ⬛ taken. Emoji
squares are outside the sixteen colours and that is fine: the string lives in other people's apps,
not in the game. The replay clip (#4), when it exists, can ride along.

**The save.** `SaveState` gains an optional `warmUp: { day, results, done }`, so older blobs still
decode. `results` is one entry per spent pitch (outcome and feet), which is what lets a Warm Up
interrupted at pitch six resume at pitch seven, and what the card and the share string are drawn
from. Nothing is stored about other days.

**Knobs:** `WarmUpRules`: `pitches` 10, `minParksCleared` 1, `epochDay` (at ship),
`shareLink` (at ship). `WarmUpCardLayout` holds the card's geometry, as `ContractCardLayout`
does the contract's.

**Build order:** ~~`WarmUp.generate` and its tests~~ → ~~the machine's warm-up state, stat routing
and `streakNow`, with tests~~ → ~~the save~~ → ~~headline and scoreboard~~ → ~~the result card~~ →
~~the share sheet~~ → ~~the stats-board row~~. All done 2026-09-19.

**What the build decided** (2026-09-19, Claude, unreviewed — the paragraphs above left these open):

- **The day number *is* the park number.** `WarmUp.generate(day:)` builds the day's park as
  `Park.generate(number: day)`, and everything else falls out of that for free: a `YYYYMMDD` is far
  past The Show, so the wall comes from the ordinary seeded ranges with night allowed,
  `League(parkNumber:)` answers The Show, and §17's scenery — itself a pure function of the park
  number — is seeded by the day with no new seeding code and no change to `Park` or `Scenery`.
- **Which meant the spec's "nothing else changes" was wrong in three places.** A park whose number
  is a date has a `displayName` of `PARK 20260920`, and it was drawn in three of them. The at-bat
  scoreboard says `WARM UP` as specced; so must the **wide view's corner** (it is the same word in
  the other camera) and the **stats board's heading corner**, which is the *career's* park, since
  the board is headed `CAREER` and a Warm Up only ever borrows the field. For the same reason the
  save records `careerPark.number`, and `isAtCeiling` is false throughout a Warm Up — otherwise a
  day-numbered park would clear any ceiling and a refund landing mid-Warm-Up would lift it.
- **`bestHomeRunStreak` is fed by the Warm Up's streak, the live career streak is not.** The
  carve-out exists so a warm-up cannot *break* a career streak and so the fireworks read the right
  number; letting a genuinely good day set the career best is what "counts toward everything but
  the cost" says. **Worth a look:** a robot swinging perfectly at all ten set `BEST HR STREAK` to
  10 off one Warm Up. If that reads as cheapening the career record, this is the line to cut.
- **Only the *home-run* streak is carved out.** `hitStreak` and its best are fed and ended by
  warm-up swings like any other counted stat, because §18 names only the home-run streak and that
  is the one the fireworks and the §11 cues read.
- **Handing the field back leaves nothing behind.** `endWarmUp` restores the career's park and
  pitch and also clears the transients (`flight`, `launch`, `playbackIndex`, `lastCall`,
  `calledStrikesInARow`, the cue indices, the contact quality). That is what makes the promise
  testable as written: `WarmUpTests` asserts the career machine after a Warm Up is `==` to one
  rebuilt from its own seed, park and tally, so the stats are provably the only thing that moved.
- **A run with no save never starts one.** `SaveStore.isEnabled` is the gate, not a separate flag:
  a run with no save has no yesterday to differ from. That is what keeps `-autoslice` and `-nosave`
  screenshot runs exactly what they were, with no extra condition to remember.
- **The fireworks seed carries the Warm Up's spent count**, because `pitches` does not move during
  one and all ten of a day's shows would otherwise be the same show. Outside a Warm Up the seed is
  bit-for-bit what it was.
- **`epochDay` is a placeholder** (2026-04-01) until there is a ship date, and so is `shareLink`.
  On the placeholder, 20 September 2026 is `WARM UP 173`.
- **The 3×5 face gained `·`**, one pixel, for the `WARM UP · 3/10` headline the spec asks for in
  those words. Checked at full resolution: it reads as a separator, not a full stop.
- **DEBUG launch arguments:** `-warmup <day>` forces the day's Warm Up (implies `-nosave`, and
  fakes the one cleared park the gate asks for); `-warmupcard` jumps straight to the result card
  with a made-up ten, the way `-streak` fakes a streak. With `-showstats`, a finished Warm Up goes
  to the board rather than the card, because a robot has no finger to leave the card with.
- **Not exercised:** the share sheet. `UIActivityViewController` cannot be driven from `simctl`,
  so the `SHARE` word and the row were only confirmed to draw and to hit-test; the sheet itself
  has never been opened. The share *string* is built in Core and is tested there.

**Open:**
1. The glyphs. Squares and one 💥, or all baseballs and bats?
2. A Game Center board for the day's feet at launch, or later? §16 lists "the daily … leaderboard"
   as free; M5 owns Game Center.
3. Should the first Warm Up wait for the call-up instead of the first cleared park? Later is
   kinder to a beginner; sooner gives a non-payer the daily habit §16 is counting on.
4. The Watch (`docs/watch.md`) leaves this phone-only in v1. Ten pitches is a very wrist-sized
   game; revisit if the watch gets past its W2.

## 19. The replay clip

> **Status: built 2026-09-19 (#4), unreviewed.** Dwight approved the idea ("Replay is a great
> idea", #2 item 4); every decision below is Claude's unless it is quoted from the issue.

A home run is re-rendered off screen, frame by frame, into an H.264 `.mp4` and handed to the
system share sheet. Not a screen recording: there is no ReplayKit, no permission prompt, and
nothing the player sees is captured. The clip is drawn again from a record of how the swing
happened, by the same code that drew it live.

**Why it is possible at all.** Every frame is already a pure function of `DerbyMachine` and the
park (§8, §17). Flight is integrated once at contact and played back; the sky, the clouds, the
stands and the fireworks are functions of the park number and the machine's own clock, never of
`Date()`. So a machine rebuilt from the right few numbers draws the identical picture.

**The record** (`Core/Sources/DerbyCore/Replay.swift`). `Codable`, `Equatable`, about half a
kilobyte. It keeps the *inputs*, never anything derived:

- the park by value (number, wall distance, wall height, night), so a clip does not move if the
  `Ladder` or `Park.Rules` later move the wall;
- the pitch (type by name, speed, strike, target);
- the `SliceCrossing` the finger made;
- the whole `Tally` as it stood **the instant before** `slice(_:)` ran;
- `marks`: the slash direction and the finger's trail, the only two things the contact freeze
  draws that the machine knows nothing about (§3).

`Replay.machine(from:)` builds a machine at that pitch (`DerbyMachine.atPitch`, the one door that
exists for it) and replays the single `slice(_:)` call. The launch, the flight, the cue indices,
the hitstop, the fireworks seed and the landing number are therefore all recomputed by the game's
own code and cannot drift from it. `ReplayTests` ticks the original and the rebuild side by side
at 1/60 and asserts every number a frame reads is equal on every frame, from the contact freeze
to the end of the landing number — including the drawn fireworks particles.

**The clip.** §3's beats and nothing else: the contact freeze, one white frame, the flight across
both cameras, the landing number. `ReplayRenderer` calls the very same `AtBatScene.render(into:)`
and `WideScene.render(into:)` on off-screen copies of those scenes, so there is no second copy of
the drawing code to keep in step. Frames go up by a whole number with nearest neighbour; no
filtering, ever. Always 320×224 at heart, never the phone's wider canvas, so a clip made on any
phone is the same picture. The park number and, at two or more, the streak are already on those
frames (§10, §17), which is the stamp the issue asks for — "always stamp the park number so the
reply is *let me try park 87*".

**The trigger.** A long press anywhere during the result hold of a home run. No button, no menu,
no toast: for 1.30 s the landing number is the only thing on the screen, so it is the target. The
press has to mature *during* the hold, so `WideScene` watches the clock rather than waiting for
the finger to lift — a finger still down at the cut would otherwise never be answered. Drawing
takes longer than the hold it was asked in, so it runs behind the game: the next pitch is never
held up, and if the player is already swinging again the sheet waits for the next miss or landing
number. While a clip is being drawn one word, `CLIP`, sits in the corner in the ordinary 3×5 face.
That is the whole of the interface.

**Knobs** (`ReplayClipRules`, `App/Sources/ReplayRenderer.swift`):

| Knob | Value | What it is |
|---|---|---|
| `canvasWidth` × `canvasHeight` | 320 × 224 | the design frame, fixed for clips whatever the phone is |
| `scale` | 4 | whole-number upscale, nearest neighbour → 1280 × 896 |
| `framesPerSecond` | 60 | and the exact `dt` the machine is ticked at |
| `bitrate` | 12 Mbit/s | generous, so one white frame survives as one white frame |
| `maxSeconds` | 20 | a stop, not a length; a home run is about four |
| `framesPerYield` | 1 | frames drawn between yields, so the game stays playable behind it |
| `crop` | `.landscape` | v1 is the native frame; see below |
| `WideScene.longPressSeconds` | 0.35 | long enough not to misfire, twice over inside the hold |

DEBUG: `-replay <path>` with `-autoslice` writes the first home run's clip and logs the path, so a
clip can be made with nothing touching the glass. Absolute paths are used as given, anything else
is a filename in Documents. It is in `SaveStore`'s no-save list and `Store`'s robot list.

**Open:**
1. **Crop.** The game is landscape and the clip is its native frame. TikTok and Reels want square
   or vertical, which would mean either pillar-boxing (honest, wastes half the frame) or a second
   framing that is not the one the player saw. The knob is there; the variant is not built, and it
   is a design question, not a rendering one.
2. **Audio.** None in v1. `Synth`/`SoundBoard` are pure and already drive off the same cues
   `DerbyMachine.tick` returns, so the crack, the crowd and the fireworks pops could be rendered
   to a buffer on the same fixed clock and muxed in as a second `AVAssetWriter` track. Worth doing
   before this is a share loop anyone uses; a silent clip of a pixel home run is half the brag.
3. **The link.** `Replay` is `Codable` and tiny, so the clip could carry a park number and a swing
   that another player could *play*, not just watch. Nothing is built for it and §14 Q4 still says
   sharing is a screenshot, so this needs a yes before anyone builds a URL scheme for it.
4. **Where the clip goes.** It is written to the temporary directory and never cleaned up
   explicitly; iOS reclaims it. If sharing becomes common that should become a real cache policy.
5. **What it costs to draw.** Measured in the simulator on a **Debug** build: about 5 s of wall
   time for a 5.5 s clip, with the game behind it at ~20 fps (it was 7 fps at `framesPerYield` 3,
   which is why that knob is 1). The clip is a second full software frame plus a 1.1-megapixel
   upscale per display frame, and `PixelCanvas` says in its own comments that a Debug build's
   bounds and exclusivity checks alone cost the 60 Hz budget — so Release should be far cheaper.
   **Not measured in Release, and not measured on a phone.** If it is still this visible there,
   the answer is probably to drop the clip to 30 fps rather than to draw it any coarser.
