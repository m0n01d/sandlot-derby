# Sandlot Derby on the wrist — watch spec

Proposal, 2026-09-19. Not yet part of the contract in [`DESIGN.md`](../DESIGN.md); section numbers
below that say "§n" point there. Written because an Apple Watch Ultra is on its way and the loop
(no outs, no menus, no timers, a pitch every three seconds) is already the shape of a watch game:
raise wrist, pitch comes, slice, number, lower wrist.

The whole port rests on one observation: **the centre column of the phone's at-bat frame, cut out
1:1, is almost exactly an Ultra screen.** The pitch corridor is vertical and the watch is portrait.
So the core, the pitch geometry and the slice test run untouched in 320×224 space, and the watch is
a fourth framing, not a second game.

---

## 1. What survives, what is cut

**Survives unchanged:** all of `DerbyCore`. The five beats and a miss, pitch types, flight physics,
seeded parks, the ladder and the minors, the tally, the streak, miss markers, swing guide and
timing ring, night parks, the three cameras and the hard cuts between them. The laced ball, the
streak's fireworks, the stands that swallow a home run and the rest of §17 as it gets built: all
of it arrives through the same painters. The one purchase and its ceiling (§16) apply on the wrist
exactly as on the phone (§7 below).

**Cut or shrunk:**

| Phone | Watch |
| --- | --- |
| Full 320-wide at-bat frame | The centre column of it, 1:1 (§3 below) |
| Pitch speed readout in the at-bat view | Gone; it is already on the wide view |
| `t3` 3×5 face | Not used. `t5` 5×7 is the smallest face (a `t3` glyph would be 1.1 mm tall) |
| Stats board, dozens of lines | Same stats, eight to a page, Crown flips pages by hard cut |
| 9 crack levels, 5 cheers pre-rendered at launch | 3 and 2, rendered after the first frame; organ, trombone and firework pops rendered on first use |
| The Warm Up (§18), the replay clip (§19), leaderboards | Phone only in v1 |
| Contract card price glyphs (`$ € £ ¥`) | Already drawn in the `t5` face since #25 — the watch needs nothing new |
| Coaching lines | Re-cut to ≤ 20 characters or two lines |
| CoreHaptics-grade impacts | Four canned taps (§6) |
| Game Center (M5) | Not on the watch |
| One career | A separate watch career in v1 (§7) |

**Added, watch only:** a haptic tick at the pitcher's release, a resume delay after wrist-raise,
an always-on idle frame, optionally a complication.

## 2. Platform and stack

- **Ultra first.** Other watches run it with a finer pixel, the way iPad runs by letterbox (§3).
- One new target, `SandlotDerbyWatch`, in the same XcodeGen project: `type: application`,
  `platform: watchOS`, deployment target **watchOS 10.0**, bundle id
  `com.m0n01d.sandlotderby.watchkitapp`, Info keys `WKApplication`, `WKCompanionAppBundleIdentifier`
  and **`WKRunsIndependentlyOfCompanionApp: true`**. The iOS target embeds it. It ships with the
  phone app, so it cannot ship before M5.
- SwiftUI `App` → one `SpriteView` → one `SKScene` holding one sprite on one nearest-filtered
  `SKMutableTexture`. There is no `presentScene` on the watch: each frame the host picks the
  painter from `machine.beat` and `machine.flightCamera`, so every cut is hard by construction.
- **Input is a SwiftUI `DragGesture(minimumDistance: 0)`** over the sprite. SpriteKit nodes get no
  touches on watchOS.
- Fallback if `SKMutableTexture` misbehaves on the device: `TimelineView(.animation)` drawing a
  `CGImage` of the buffer with `.interpolation(.none)`. The buffer is 23k pixels; either path is
  cheap.
- The Ultra's Action button cannot be claimed by a game. A player can bind it to "open app" in
  Shortcuts; we do nothing.

### Code layout: painters out of scenes

Today drawing and touch handling live inside `AtBatScene`/`WideScene`, which are `SKScene`
subclasses that import UIKit. The watch needs the drawing and none of the rest. So before any watch
pixels, a phone-only refactor:

- New package **`Stage/` → `DerbyStage`**, depends on `DerbyCore`, Foundation only, builds on
  Linux. It takes `PixelCanvas`, `Palette`, the fonts and sprites, `Synth`, `SaveState`, and:
  - `AtBatPainter`, `WidePainter`, `StatsPainter` — pure functions of
    `(DerbyMachine, layout, PixelCanvas)`. The bodies of today's `render(into:)`.
  - `SliceTracker` — today's trail, lag window and `fingerSpeed` logic from `AtBatScene`'s
    `touchesBegan/Moved/Ended`, fed `(Point, timestamp)` samples in design space, returning
    `SliceOutcome`. Both hosts feed it; neither re-implements it.
  - `GameDirector` — the platform-free half of `GameController`: owns the machine, the tracker and
    the save, turns `Transition`s into calls on a `CueSink` protocol, one method per row of §11's
    table plus `pitchThrown`. It also sets `parkCeiling` from an `Entitlement` it is handed; it
    never imports StoreKit. `-autoslice` and `-nosave` live here so they work on both.
  - `Fireworks.particles(seed:time:)` and the backdrop cache (§17). The cache is already keyed by
    canvas width and camera, so the watch's canvas is just another key.
- `PixelCanvas` gains an **`origin: Point`** subtracted from every draw. Writes are already
  bounds-checked, so a 136×167 canvas with origin `(92, 45)` *is* the crop. No second copy of the
  field art, no second set of at-bat coordinates.
- `App/` keeps the SpriteKit hosts, `SoundBoard`, UIKit haptics. `Watch/` gets its host,
  a `CueSink` over `SoundBoard` + `WKInterfaceDevice`, and nothing else.
- Bonus: painters that run headless mean `swift test` can write golden-frame PNGs. That is the
  cheap way to satisfy the PR screenshot rule for the watch, and for the phone.

### Changes to `DerbyCore`

1. `Package.swift`: add `.watchOS(.v10)` to `platforms`.
2. `DerbyMachine.abandonPitch()`: from `windup` or `pitch`, back to the top of `windup`. Counts
   nothing, emits nothing, streak untouched. Tested: tally identical before and after. Needed
   because a lowered wrist must never cost a called strike (§5).

Nothing else. `majorsSliceRules`, `majorsPitchingRules` and `cameraRules` are already settable on
the machine; the watch passes its own.

## 3. The canvas

| Watch | Physical px | Scale | Canvas (units) |
| --- | --- | --- | --- |
| Ultra, Ultra 2 (49 mm) | 410×502 | 3 | **136×167** |
| Ultra 3 | 422×514 | 3 | 140×171 |
| 46 mm | 416×496 | 3 | 138×165 |
| 45 / 44 / 42 / 41 / 40 mm | 396×484 … 324×394 | 2 | 198×242 … 162×197 |

Pixel sizes from memory; W0 reads them from `WKInterfaceDevice.current().screenBounds × screenScale`.

- **The scale is an integer number of physical pixels, not points.** The rule: the largest integer
  scale at which the canvas is still ≥ `WatchCanvas.minWidth × minHeight` = **136×165**. Leftover
  pixels are a black border, at most 2 px.
- Three physical pixels is 1.5 pt, so `.aspectFit` is wrong here: it would land on 3.01 and smear
  rows. The host sizes the sprite to exactly `canvas × scale / screenScale` points and snaps its
  origin to the pixel grid.
- On an Ultra one unit is about 0.225 mm. On the phone it is about 0.29 mm. Close enough that the
  game looks like the same hardware.
- The canvas is never taller than 224. Rows above design `y = 0` take the top sky band's colour.
- **Corners and clock.** The display's corners are round and watchOS draws the time top-right.
  Art may run under both. Text may not: HUD text sits inside the system safe-area insets and below
  `WatchAtBatLayout.hudTop`. W0 measures the corner on a test pattern and finds out whether the
  clock can be hidden without private API. The spec assumes it cannot.

## 4. The three framings (canvas units, y down; Ultra values)

### At-bat: the centre column

`WatchAtBatLayout`: `cropCentreX = 160`, `cropBottom = 212`, `hudTop = 16`, `ballRadiusBonus = 1`.

Canvas origin in design space is `(cropCentreX − W/2, cropBottom − H)` = **`(92, 45)`**. What
falls inside, in watch coordinates:

| Thing | Design space (§8) | On the watch |
| --- | --- | --- |
| Scoreboard | `(128, 80, 64×16)` | `(36, 35)`, whole |
| Wall band | `y 96–104` | `y 51–59` |
| Pitcher, foot point | `(160, 117)` | `(68, 72)`, dead centre |
| Release point | `(166, 108)` | `(74, 63)` |
| Strike zone | `(150, 136, 40×50)` | `(58, 91, 40×50)` |
| Plate | `(152, 190, 16×4)` | `(60, 145)` |
| Batter, 32×56 on `(104, 222)` | x 88–120 | loses 4 columns left, shins under the corner |

- The crop stops at 212, not 224, on purpose: the bottom 12 rows are the batter's feet, which the
  round corner eats anyway, and the trade buys 12 rows of sky for the HUD. It also puts the zone at
  70 % of the way down the glass, where the slicing hand is already, so the hand covers less of
  the pitch's runway. The ball comes from above; the finger comes from below.
- HUD: `PARK n · PITCHES` at `(safeLeft, hudTop)`, streak on the line under it, both `t5` at 1×,
  left-aligned, over sky. Nothing else. Top-right belongs to the clock.
- The ball is drawn at `sample.radius + ballRadiusBonus`. Drawing only; the hit test is unchanged.
  `PixelCanvas.baseball` picks its laces from the radius it is given, so a radius-5 ball gets the
  five-pixel seam with no new art.
- **§17 through the window.** The crop keeps design columns 92–228 and rows 45–212. The horizon
  band (y 86–96) and the scoreboard's flags are inside it. Birds fly at y < 60, so the wrist sees
  the bottom of a flock at most. Whatever `Park.scenery` puts outside the columns (a tower, the
  water tower, the one house) is not seen. Scenery is never moved for the watch: park 87 is park 87.
- Touch: watch point → canvas unit → plus origin → design-space `Point` → `SliceTracker`. The
  scoreboard tap that opens the stats board works as on the phone; its grown target
  `(112…208, 70…106)` is inside the crop and 21×8 mm on the glass.
- Miss markers, swing guide and timing ring are drawn in design space around the zone, so they
  arrive for free.

### Wide: the number on top, the arc beneath

Portrait wastes sky in a side view. Spend it on the number, which is the payoff and the one thing
worth a glance.

`WatchWideLayout`: `groundY = 132`, `wideLeftFeet = −24`, `wideWallAt = 2/3`,
`landingMarginFeet = 20`, `apexMarginPixels = 12`, `numberY = 30`, `numberScale = 4`, `hrY = 64`.

- Same framing function as the phone with these values. At a 380 ft wall that is about 4.5 ft per
  unit: wall at x = 91, a 150 ft apex is 34 rows, and the batter, to the field's scale, is two
  pixels tall. That is correct and a little funny.
- Distance ticks up during flight **in the place the result will sit**: centred, `t5` at 4×
  (three digits are 68 units wide), `y = 30–58`. `HR` under it at `hrY`, `t5` at 2×, blinking at
  the phone's 3 Hz. The arc stays under the number up to about a 250 ft apex; beyond that
  `apexMarginPixels` rescales as it does on the phone.
- Readouts: one line at `(safeLeft, hudTop)`, `104 MPH 28°`, pitch type on the line under it.
  `t5` at 1×.
- **Fireworks** (§17) are screen-space and sit behind all text, so the number-on-top layout and
  the streak's sky want the same pixels and do not fight: the shells burst *behind* the number.
  The phone's "right 45 %, y 20–110" becomes `WatchWideLayout.fireworksRect = (8, 16, 120×96)`,
  the whole sky. Same shell table, same `particles(seed:time:)`. A finale of ten on a screen this
  small may be mud; judge it at W3 and cap the shells with a knob if so.
- The stands draw in front of the ball as on the phone. At this scale they are about 13 rows high
  and a home run still drops into them and is gone.
- Foot ticks every 100 ft under the ground line. The bottom corners hold nothing but dirt.

### Close: more needed here than on the phone

A 6 ft wall is 4 px in the phone's wide view and **1 px** in the watch's. The close camera stays.

`WatchWideLayout`: `closeScale = 4.0`, `closeWallAt = 0.55`, `closeHeadroom = 24`.
`CameraRules` for the watch: `closeReachFeet = 60`, **`closeLeadFeet = 70`**.

- 4× the wide scale is about 1.1 ft per unit: walls of 6–26 ft are 5–23 rows.
- Only about 83 ft of field fits left of the wall at that scale, so the phone's 100 ft lead would
  cut to a frame with no ball in it. Hence 70.
- Result beat cuts back out to wide, as on the phone.

## 5. The slice, and the life of a pitch

**One gesture, still.** A slice across the glass with the other hand's finger. `Contact.test` and
`Contact.resolve` are unchanged. Only the numbers that describe a *finger* move, because a finger
on 31 mm of glass has less room than on a phone:

`WatchSliceRules`, applied over `majorsSliceRules` — **starting guesses, to be retuned in W4**:

| Knob | Phone | Watch | Why |
| --- | --- | --- | --- |
| `fullPowerSpeed` | 520 u/s (~150 mm/s) | **440 u/s** (~100 mm/s) | Short strokes never reach phone speeds |
| `fullPowerLength` | 0.28 × 320 = 90 u (26 mm) | **0.45 × 136 = 61 u** (14 mm) | 26 mm is most of the screen |
| `minAngleLength` | 12 u | **8 u** | Same reason |
| `hitMarginBonus` | — | **+3 u** on every rung | 9 u is 2.6 mm on a phone, 2.0 mm here; +3 restores the physical margin |

Timing knobs (`timingWindow`, `lagWindowSeconds`, `earlyLoftDegrees`) do not change. Time is time.

**Wrist-down is not a strike.** The host watches `scenePhase` and `isLuminanceReduced`:

- Not active, or luminance reduced: stop ticking, `abandonPitch()`, draw one idle at-bat frame
  (pitcher set, no ball). That frame is the always-on face of the game.
- Active again: hold in `windup` for `WatchTimings.resumeDelay = 1.0 s` before ticking, so a
  finger can get to the glass. Launch counts as a resume.
- Mid-`flight` or `result` when the wrist drops: finish silently on return. The swing happened.

`WatchTimings.framesPerSecond = 60`. W0 measures a five-minute session's battery; 30 is the fallback.

**If the slice does not work on glass this small** (W2 is the go/no-go), the fallback is a tap:
timing only, with loft from `earlyLoftDegrees` as today and a fixed swing angle and power. It
would be a lesser game and pillar 1 would need rewording. Not designed further until needed.

## 6. Haptics and sound

**Design for silence.** Most watches live in silent mode, where `.ambient` audio does not play.
The game must be whole with haptics alone; sound is a bonus.

watchOS has no CoreHaptics and no impact generators: only `WKInterfaceDevice.current().play(_:)`
and its canned types, which watchOS also rate-limits. So four cues, not eight:

| Cue | `WKHapticType` (starting choice) |
| --- | --- |
| `.pitchThrown` — **new, watch only**, `WatchHaptics.pitchTick = true` | `.click` |
| Contact, `quality < 0.5` / otherwise | `.click` / `.start` |
| `.clearedWall` | `.success` |
| `.hitWall` | `.directionDown` |
| Whiff, called pitch, landed, called up, the organ, fireworks | none |

The pitch tick exists because the pitcher is 2.7 mm wide on the wrist and the release is the one
moment that must not be missed. It is also the accessible version of the windup.

- `Synth` is shared as it is. `SoundBoard` is shared if `AVAudioEngine` behaves on the device
  speaker (W0), with the smaller pre-render set from §1 built off the main thread after the first
  frame. Launch time matters more here than anywhere.
- The organ, the *womp, wommmp* and the firework pops (§11, §17) all come along when sound is on.
  In silence they have no stand-in, on purpose: a streak of three already lights the sky, and a
  buzzing wrist between pitches would break "silence is the tension" harder than a murmur would.
- **Known trap:** `play(_:)` also sounds a system tone when the watch is *not* silenced, which
  would fight the synth. W0 finds out which types do. If all do: with sound on, haptics drop to
  `.click` only and the synth carries the rest.

## 7. Career, stats, extras

- **A separate career in v1.** Same `SaveState`, same `"save.v1"` key, the watch's own
  `UserDefaults`. Parks are a pure function of their number, so park 12 on the wrist is park 12 on
  the phone, but progress is not shared. Merging two tallies that advanced apart needs deltas, not
  a bag of totals; that is a design problem, not a sync problem, and it can wait.
- **The Show costs the same $1.99, once, anywhere (§16).** The watch app is part of the phone
  app's store record, so `show.contract` bought on either device is an entitlement on both, read
  silently from `Transaction.currentEntitlements` at launch and cached in `UserDefaults` for
  offline. That is the store doing the sharing; there is still no phone-to-watch link. Verify in
  the sandbox at W5 before believing it.
  - The watch sets `parkCeiling` exactly as the phone does. A watch career is separate, so an
    unentitled player meets the **contract card** on the wrist once too. Same card, recut for
    136 columns in `t5`: `THE SHOW` / price / `ONE TIME` / `NO ADS` / `NO SUBSCRIPTION` / the
    dotted line ending in `X`. **Slicing the line signs it**, then the system sheet (a double-click
    of the side button). `RESTORE` in a corner the round glass does not eat.
  - The watch must sell, not just read: it runs without the phone app installed, and a card that
    says "buy this on your iPhone" is both a dead end and an App Review problem.
  - Declining, pending, refunds, grandfathering and the stats-board row all behave as in §16.
- **Stats board:** `StatsPainter` with a watch layout: eight lines a page, `t5`, a Crown detent
  flips the page by hard cut, a tap leaves. The machine does not tick while it is up, as on the
  phone. The Crown does nothing anywhere else.
- **Complication / Smart Stack widget** (W5, optional): `PARK 12` and the streak, tap to launch. A
  twenty-second game lives or dies on how fast it starts.

## 8. Tuning knobs (watch)

All in `Watch/` or `DerbyStage`, each with a doc comment, none inline:
`WatchCanvas` (minWidth, minHeight) · `WatchAtBatLayout` (cropCentreX, cropBottom, hudTop,
ballRadiusBonus) · `WatchWideLayout` (groundY, wideLeftFeet, wideWallAt, landingMarginFeet,
apexMarginPixels, numberY, numberScale, hrY, fireworksRect, closeScale, closeWallAt,
closeHeadroom) ·
`WatchSliceRules` (fullPowerSpeed, fullPowerLength, minAngleLength, hitMarginBonus) ·
`CameraRules` watch instance (closeReachFeet, closeLeadFeet) · `WatchTimings` (resumeDelay,
framesPerSecond) · `WatchHaptics` (pitchTick, the cue table).

## 9. Milestones

- **W0 — spike, half a day, the day the watch arrives.** Target builds from XcodeGen. A 136×167
  test pattern on the glass at exactly 3 px per unit (screenshot, zoom, count). `DragGesture`
  sample rate logged. `SKMutableTexture` on device. One `crack` through the speaker. Every
  `WKHapticType` felt, tones noted. Corner and clock measured. Battery over five minutes at 60 fps.
  **Output: the guessed numbers in this file replaced with measured ones.**
- **W1 — painters out of scenes.** Phone only, no behaviour change. Proof: before/after
  screenshots of both cameras are pixel-identical, `swift test` green in `Core/` and `Stage/`.
- **W2 — at-bat on the wrist.** Crop, slice, pitch tick, contact haptic, miss markers.
  **Go/no-go:** twenty pitches on the wrist. If the slice is not fun, stop here or take the tap
  fallback.
- **W3 — the whole loop.** Wide, close, result, `abandonPitch`, resume delay, always-on frame.
  Whatever of §17 exists by then comes through the painters; judge the fireworks on the glass.
- **W4 — feel.** Retune `WatchSliceRules` and the haptic table on the wrist. Decide the mirror
  question below.
- **W5 — career and ship.** Save, stats pages, `parkCeiling` from the entitlement, the contract
  card and StoreKit 2 on the watch (after the phone's, reusing its `.storekit` file), the shared
  entitlement proven in the sandbox, optional complication. Ships inside the phone's M5.

**Order against the phone's milestones:** W0 whenever the hardware lands; it is a spike and
informs nothing else. W1 is worth doing on its own merits. W2 onward was gated on M3, because M3
could have retuned the `SliceRules` the watch inherits. **M3 closed 2026-09-19 with the knobs
unchanged** (520 px/s, 9 px), so that gate is met: W2 now waits only on W1 and the watch itself.

## 10. Open questions

1. **Right-wrist players.** With the watch on the left wrist the slicing hand comes in from the
   right, away from the batter. On the right wrist it comes in over him. `wristLocation` is
   readable; mirroring the playfield (a lefty batter) at blit time is cheap, mirroring the HUD is
   not needed. Decide at W4 with a right-wrist tester.
2. **Small watches.** At scale 2 the units are 0.15 mm and every physical margin shrinks with
   them. They run; they are harder. Tune for them only if anyone asks.
3. **One career across both devices.** See §7.
4. **The clock.** If it can be hidden honestly, the HUD moves up to `hudTop = 6`.
5. **Swing the arm?** CoreMotion could read a real swing. You cannot watch a pitch on a wrist you
   are swinging, and it breaks pillar 1. Parked, not rejected: it is the only thing a watch can do
   that a phone cannot.

## 11. Non-goals (watch)

Everything in §15, plus: Game Center, the daily card (#3), replay sharing (#4) and leaderboards in
v1, the double-tap pinch gesture (far too slow to time a pitch),
Crown-as-swing, workout sessions, phone-to-watch connectivity, any settings screen.
