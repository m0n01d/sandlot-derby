# Sandlot Derby off the phone — port survey

Proposal, 2026-09-19. Not yet part of the contract in [`DESIGN.md`](../DESIGN.md); section numbers
below that say "§n" point there. **§2 currently reads "No Android, no web."** This file argues for
revising that line, and nothing here is agreed until it is.

Written because the game turned out to be far more portable than it was designed to be, by
accident of two early decisions: the core is pure Swift, and the renderer is a software blitter
rather than a scene graph. Nobody planned a port. The architecture backed into one anyway.

---

## 1. The measurement

Counted 2026-09-19, at the merge of wave 2.

| | Lines | Platform dependency |
| --- | --- | --- |
| `DerbyCore` (11 files) | 2,430 | `import Foundation` and nothing else |
| `PixelCanvas`, `Backdrop`, `SkyArt`, `Clouds`, `Palette`, `Synth`, `SaveStore` | 1,725 | Foundation only |
| Scenes (`AtBatScene`, `WideScene`, `StatsScene`, `ContractScene`, `WarmUpCardScene`, `CanvasScene`) | 1,879 | SpriteKit shell, `PixelCanvas` body |
| `GameController` | 615 | SpriteKit for `presentScene` only |
| `SoundBoard`, `ReplayRenderer`, `Store`, shell | 808 | AVFoundation, StoreKit, SwiftUI |

**4,155 of 7,457 lines — 56% — are already platform-free.** The scene files are mostly
`canvas.px/rect/line/disc/t3/t5` calls wearing a thin SpriteKit coat.

The entire SpriteKit API surface in the project is five types and four methods: `SKScene`,
`SKView`, `SKSpriteNode`, `SKMutableTexture`, `presentScene`, `touchesBegan/Moved/Ended`,
`filteringMode`. That is the whole of it. Grep and see.

So the port seam is four things, and they are the same four on every target:

1. Hand a `width × 224` RGBA8 buffer to the screen, nearest-filtered, once a frame
2. Deliver a pointer or stick event as down / move / up
3. Push mono PCM at 44.1 kHz (`Synth` already generates it arithmetically — no audio files ship)
4. Read and write a small `Codable` save blob

On any target with a Swift compiler that is a platform layer of roughly 300 lines. **The port cost
is not the game. It is the toolchain, the store paperwork, and §4 below.**

## 2. What "port" means here, and what it doesn't

The game is at its best on an **iPad mini**: a screen big enough to see the arc, held in two hands,
with a touchscreen under the thumbs. That is the target profile, and it is worth naming because it
reorders the list. A platform that preserves *big screen + two hands + touch* inherits the game as
designed. A platform that replaces the finger with a stick is a **different game wearing the same
art**, and §4 is the price of admission.

By that measure the Steam Deck is closer to an iPad mini than a docked Switch is.

| Preserves the finger | Replaces the finger |
| --- | --- |
| Steam Deck (touchscreen + two trackpads) | Switch docked, Xbox, PlayStation |
| Android tablets and phones | Steam on a desktop with a pad |
| Windows and Linux laptops with touch / a mouse | tvOS (Siri Remote is a touch surface — halfway) |
| Web on a tablet | Switch handheld (has a touchscreen — also halfway) |

A mouse counts as a finger for our purposes: `touchesMoved` and a dragged cursor produce the same
segment stream, and §5's hit test cannot tell them apart.

## 3. The tiers

### Tier 1 — near-free (days each)

- **macOS.** SpriteKit, SwiftUI and Swift all exist there; the scenes compile as they are. Two
  jobs: `UIKit` → `AppKit` in the four files that import it, and mouse events into the same slice
  path. Or skip even that — tick "Designed for iPad" and the iOS binary runs unmodified on Apple
  Silicon. Mac App Store listing for close to zero work.
- **tvOS.** SpriteKit runs. The Siri Remote's touch surface takes a swipe honestly, which is more
  than a gamepad can say. 320×224 upscaled to a TV is the intended look, finally at the intended
  size. Small audience, good money per user, no §4 problem.
- **visionOS.** A floating Genesis cabinet. Novelty, low revenue, and there is RealityKit muscle
  memory next door in `Reywas`.
- **Apple Watch.** Already specced in [`watch.md`](watch.md), waiting on hardware.

### Tier 2 — the SDL layer (2–3 weeks, and the one that earns)

One platform layer over **SDL3** buys Windows, Linux, Steam Deck and macOS at once. Swift's C
interop means there is no binding package to write or borrow: a module map over `SDL3/SDL.h` and
the C API is callable directly. Nothing in `DerbyCore` changes. Nothing in the painters changes.

SDL gives us exactly our four seams and nothing we don't need:

| Seam | SDL3 |
| --- | --- |
| Blit | `SDL_Texture` (`SDL_PIXELFORMAT_RGBA8888`, streaming) with `SDL_SCALEMODE_NEAREST` |
| Input | `SDL_EVENT_MOUSE_*`, `SDL_EVENT_FINGER_*`, `SDL_EVENT_GAMEPAD_*` |
| Audio | `SDL_AudioStream`, fed the same PCM `Synth` hands `SoundBoard` |
| Save | A JSON file next to `SDL_GetPrefPath` |

**Steam Deck is not a port target.** The Deck is Linux; you ship a Linux build, or a Windows one
through Proton, and it runs. Deck Verified is a checklist — controller glyphs, legible text at the
default resolution, no launcher — and a 320×224 game passes most of it by existing. The Deck's
touchscreen means the real slice survives; the trackpads mean it survives even with the screen at
arm's length.

This is the highest revenue per hour of work on the list, and the only tier where we own the store
page. A premium pixel sports game at $4.99–7.99 with no IAP is a shape Steam understands.

### Tier 3 — Android (3–6 weeks, and a real fork in the road)

Two routes that are not variations of each other. Decide before starting, not halfway.

**(a) Swift on Android.** The Swift Android Workgroup ships SDK bundles now; `DerbyCore` and the
1,725 portable lines should compile untouched. The platform layer is Kotlin over the NDK: a
`SurfaceView` or a GLES texture for the blit, `AudioTrack` for PCM, `MotionEvent` for the slice.
The game is not the hard part. The toolchain, the CI and being an early adopter of a path that is
still moving are the hard part. **Spike this for two days before committing** — the claim that it
compiles clean is an assumption in this document, not a measurement.

**(b) Hand-port the renderer to Kotlin.** Rewrite ~4,150 lines of pure logic and drawing. Boring,
mechanical, zero toolchain risk, and the output is an ordinary Android project. For a codebase
this small that is genuinely competitive: the physics is arithmetic and the renderer is loops over
a byte array. The cost is a second copy of the truth, which the calibration table in
[`physics.md`](physics.md) would have to police across both.

Either way Play Billing maps onto the §16 contract card conceptually, and Google Play Games on PC
throws in a Windows build.

### Tier 4 — Web (1–2 weeks, marketing not revenue)

SwiftWasm is mature enough, and a software renderer writing into a buffer that becomes `ImageData`
on a `<canvas>` is almost comically well-suited — it is how the pages in `prototypes/` already
work. We would be porting the game back to where it was born.

Won't earn directly. Is the best possible demo: a playable link in every post, itch.io, and the
web-game portals (Poki, CrazyGames) pay real money for exclusivity windows on something that plays
well on a tablet.

### Tier 5 — Switch, PlayStation, Xbox (months, or money)

Be clear-eyed. **There is no Swift toolchain for Nintendo Switch.** The SDK is NDA'd, C/C++ only,
and no public LLVM backend targets it. The same is fundamentally true of PS5 and the Xbox GDK. So
the Swift codebase cannot go there in any form. What can:

- A **C++ translation**. The silver lining is that a software renderer and pure-math physics port
  to C++ about as cleanly as code ever does — `PixelCanvas` is `memset` and loops, `Flight` is
  arithmetic. Call it 3–6 weeks of mechanical translation, not a rewrite. The calibration table
  becomes the acceptance test for the translation, which is exactly what it is for.
- A **porting house**, for a fee or a rev share. They do this constantly for indies.
- An **engine with a console backend** — which for us would mean abandoning the architecture, so:
  no.

Gates, in order: a business entity, approval as a licensed developer (free to apply; they do take
indies), a devkit purchase, then the work. **ID@Xbox is the most accessible of the three** — free
devkit program, C++ GDK.

Console players pay upfront and expect no F2P, which suits §16 badly (the contract card has
nowhere to go) and suits a flat $6.99 very well. That is a pricing decision, not just a port.

## 4. The slice on a gamepad — the actual blocker

This is more work than the entire SDL layer, and it should be prototyped before any tier-2 or
tier-5 commitment. It is the only part of this document that touches game design.

§5 turns a finger into exactly four numbers, and `Contact.resolve` wants nothing else:

| Number | Where it comes from on a screen |
| --- | --- |
| **crossing point** | Where the stroke passed the ball — feeds centring `cq` |
| **progress** | Which ball sample was crossed — feeds timing `tq` |
| **swing angle** | Start of the drag → crossing point, clamped −20°…80° |
| **power** | `max(fingerSpeed / 520, dragLength / 89.6)`, floored at 0.3 |

A gamepad has no cursor, so three of the four have obvious homes and one does not.

**The proposal: the stick is the bat's line, not a cursor.**

- **Swing angle** — left stick direction, read continuously. `atan2` of the deflection, through
  the same clamp. The player aims the *stroke*, which is what §5's angle has always meant.
- **Timing** — the instant the button goes down. This is cleaner than touch, not worse: a single
  sampled moment instead of a swept segment, so `progress` comes straight from the ball sample at
  press time and the §5 lag window can shrink or go away.
- **Power** — analog trigger depth, mapped onto `minPower`…1. A light pull is a contact swing, a
  full pull is a hack. Falls back to stick deflection magnitude on a pad with digital triggers.
- **Centring** — the part with no free answer, and the reason for the framing above. On press,
  synthesise a segment: a line through the plate anchor at the stick's angle, of length
  `fullPowerLength`, and hand it to the existing hit test. Centring then falls out honestly — it
  measures whether the ball was *on the line you aimed*, which is what it measures on a screen.

The prize for doing it this way: **`DerbyCore` does not change at all.** The gamepad produces a
synthetic segment and `Contact` cannot tell the difference. A new `PadSliceRules` lives in the
platform layer beside `SliceRules`, not inside it, and the core stays pure per the standing rule.

What has to be judged on hardware, not here: whether aiming a line and pressing a button is *fun*
the way dragging a finger through a ball is fun. It may not be. The go/no-go is twenty pitches on
a Deck, the same shape as `watch.md`'s W2 gate.

Rejected before prototyping: a stick-driven cursor that the ball must be swept through (turns it
into a twin-stick game and demands two hands for one verb), and dropping centring entirely
(`cq = 1` flattens a quality axis and makes the game easier in the one place it should not be).

## 5. Tuning knobs (ports)

Each with a doc comment, in the platform layer, never inline:

`PadSliceRules` (aimDeadzone, triggerFloor, triggerCurve, syntheticSegmentLength, plateAnchorX,
plateAnchorY, digitalTriggerPower) · `PadTimings` (aimSampleRate, pressLatencyCompensation) ·
`HostCanvas` (minWidth, minHeight, integerScaleOnly, letterboxColour) ·
`HostAudio` (bufferFrames, sampleRate) · `DeckLayout` (glyphSet, safeInsets).

`SliceRules` is untouched by all of this, by design.

## 6. Milestones

- **P0 — the seam, half a day.** Pull `CanvasScene`'s blit and tick into a `DerbyHost` protocol
  with the SpriteKit implementation behind it. Phone only, no behaviour change. **Proof:**
  before/after screenshots of both cameras pixel-identical, `swift test` green. Worth doing on its
  own merits whatever happens to this document — it is `watch.md`'s W1 by another name, and the
  two should be one piece of work.
- **P1 — SDL3 on the Mac, a week.** Same game, same pixels, in an SDL window driven by a mouse.
  **Proof:** a mouse-dragged slice produces the same `SliceOutcome` as the same stroke on a phone.
- **P2 — Linux and the Deck, a week.** Cross-compile, run on the Deck, play twenty pitches on the
  touchscreen. Nothing about §4 yet. This is the point where the Steam decision gets made with a
  real thing in hand.
- **P3 — the gamepad slice.** §4 on the Deck's own sticks. **Go/no-go: twenty pitches. If aiming a
  line is not fun, tier 2 ships touch-and-mouse only and tier 5 dies here** — which would be a
  cheap way to find out, and is the reason P3 comes before any console paperwork.
- **P4 — Steam.** Store page, wishlists, Deck Verified checklist, a build without the §16 contract
  card and with a price instead.
- **P5 — Android spike.** Two days on route (a). Decide (a) or (b) with a measurement.

Nothing here starts before M5 ships on the phone. A port of an unfinished game is two unfinished
games.

## 7. Open questions

1. **§16 off the phone.** The contract card is a mobile free-to-start shape. On Steam and consoles
   the game is bought before it is played, so the call-up beat has no purchase to carry. Does the
   card stay as a story moment with nothing attached, or does the ladder change? This wants
   answering before P4, not during.
2. **One career across devices, again.** `watch.md` §7 parked this for the watch. Steam and phone
   makes it louder, and there is no iCloud on Steam.
3. **Which way the second copy points.** If Android goes route (b), Kotlin and Swift both claim to
   implement [`physics.md`](physics.md). The table is the arbiter, but somebody has to run it on
   both in CI.
4. **Integer scaling off 224.** The phone letterboxes gracefully because layouts anchor to edges.
   A 1280×800 Deck screen is 3.57× of 224. Do we integer-scale at 3× and letterbox, or take the
   fractional scale and lose the pixel grid? The rule in CLAUDE.md says integer where possible;
   the Deck may be a place it is not.
5. **Does a 320×224 game read on a 55-inch TV?** Suspect yes and better than on a phone. Unmeasured.

## 8. Non-goals (ports)

Everything in §15, plus: any engine (Unity, Godot, GameMaker), a second renderer of any kind, a
cross-platform UI framework, cloud saves, cross-play, a launcher, per-platform gameplay
differences beyond the input scheme in §4, and shipping any port before M5 closes on the phone.
