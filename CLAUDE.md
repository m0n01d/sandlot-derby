# Sandlot Derby — project guide

Native Swift iOS game. SwiftUI shell, SpriteKit scenes, a pure-Swift core package. Read
[`DESIGN.md`](DESIGN.md) before changing gameplay; it is the spec, and every number in it is a
tuning knob with a name.

## Shared conventions

The workspace-wide rules live in the private repo `m0n01d/claude-conventions` (symlinked to
`~/code/CLAUDE.md` on the Mac, where Claude Code auto-loads it). Cloud sandboxes don't see it; fetch
it if you need the model-budget, subagent and PR rules:

```sh
git clone https://github.com/m0n01d/claude-conventions /tmp/conventions && cat /tmp/conventions/CLAUDE.md
```

This is a Swift project, so the ReScript/resq rules there don't apply. The model-budget, subagent
routing, PR screenshot and grooming rules do.

## Layout

- `Core/` — Swift package `DerbyCore`. **Pure Swift, no UIKit, no SpriteKit, no Foundation beyond
  `Foundation` math.** Flight physics, pitching, slice contact, seeded parks, the six-beat state
  machine. Everything here is deterministic and unit-tested.
- `App/` — the iOS app. The Xcode project is generated and git-ignored:
  `cd App && xcodegen generate && open SandlotDerby.xcodeproj`. SwiftUI `ContentView` → `SKView` →
  two scenes (`AtBatScene`, `WideScene`) driven by `DerbyMachine` through `GameController`. Scenes
  are renderers and gesture sources only; they own no game state. Both draw a whole frame into a
  software `PixelCanvas` (the prototype's `px/rect/line/disc/t3/t5`) shown through one
  nearest-filtered `SKMutableTexture`. DEBUG only: space bar is the dev slice, and the
  `-autoslice` launch argument swings at every pitch.
- `docs/` — physics calibration table (the test oracle), palette, anything durable.
- `prototypes/` — the HTML pages the design came from. Reference code for the port, especially the
  slice hit test and the two views' layouts. Not shipped.

## Rules

- **`DerbyCore` stays pure.** If a change needs a scene, a node or a view to be right, it belongs in
  `App/`. Core must build and test with `swift test` on Linux.
- **The calibration table is the truth.** `docs/physics.md` and `Core/Tests/.../FlightTests.swift`
  carry the same numbers. Change the physics and you change both in the same commit, with the reason.
- **Tuning knobs are named.** Every gameplay constant lives in a `*Rules`/`*Params`/`Timings` struct
  with a doc comment, not inline in a scene. DESIGN.md §12 lists them.
- **Design units are 320×224.** All layout constants in the spec and core are in that space
  (the Genesis screen). Scenes scale up by an integer where possible and never filter textures:
  `texture.filteringMode = .nearest`.
- **One palette line.** Every colour comes from `docs/palette.md`. No alpha, no gradients, no
  anti-aliasing. Dither only in the sky.
- **No outs, no menus, no timers.** A miss brings the next pitch. If a feature needs a menu, it is
  probably the wrong feature.
- **The cut is hard.** `presentScene` with no transition. Never a wipe, fade or zoom. The same goes
  for wide ↔ close inside `WideScene`: the framing changes between one frame and the next, chosen
  by `DerbyMachine.flightCamera`. No tweened camera, ever.

## Verification

- `cd Core && swift test` — must be green before any push that touches core.
- The app has no automated UI tests yet; screenshots of both cameras go on every PR that touches a
  scene (per the shared PR rule).

## Milestones

See DESIGN.md §13. M0–M4 are done. M3 (feel) closed 2026-09-19 after Dwight played it on a phone
with sound and haptics in: the slice knobs stayed at 520 px/s and 9 px, and the unbuilt leftovers
(hitstop, `BARREL` call, third pitcher pose, held-finger swing-miss) are issue #20. What is left
is M5, ship. Its pricing track (§16) has `parkCeiling` in core; next there is the contract card
scene, and §16 wants the daily card (#3) shipped before the paywall. `docs/watch.md` is a
proposal for an Apple Watch version and waits on hardware.
