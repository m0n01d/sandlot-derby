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
  machine. Everything here is deterministic and unit-tested. Wave 1 (2026-09-19) added
  `Scenery.swift` (`Park.scenery` — a park's seeded backdrop pieces, clouds, stands tier, night
  towers/moon) and `Fireworks.swift` (`FireworksRules` — the closed-form home-run shell math).
- `App/` — the iOS app. The Xcode project is generated and git-ignored:
  `cd App && xcodegen generate && open SandlotDerby.xcodeproj`. SwiftUI `ContentView` → `SKView` →
  scenes (`AtBatScene`, `WideScene`, `ContractScene`) driven by `DerbyMachine` through
  `GameController`. Scenes are renderers and gesture sources only; they own no game state. Both
  play/at-bat scenes draw a whole frame into a software `PixelCanvas` (the prototype's
  `px/rect/line/disc/t3/t5`) shown through one nearest-filtered `SKMutableTexture`. DEBUG only:
  space bar is the dev slice; see "DEBUG launch arguments" below for the full set. Wave 1 also
  added `Backdrop.swift` and `Clouds.swift` (the cached backdrop layers and cloud drift behind
  `Scenery`), `ContractScene.swift` (the paywall card, §16), and `Store.swift` with
  `App/SandlotDerby.storekit` (StoreKit 2, no server).
- `docs/` — physics calibration table (the test oracle), palette, anything durable.
- `prototypes/` — the HTML pages the design came from. Reference code for the port, especially the
  slice hit test and the two views' layouts. Not shipped.

## DEBUG launch arguments

All are `#if DEBUG` only — none exist in a release build. "Implies `-nosave`" means `SaveStore`
never reads or writes the real career; "entitled" refers to `Store.forcedEntitlement`, which
overrides whatever StoreKit itself would say.

| Argument | Meaning | Implies `-nosave` | Entitled |
|---|---|---|---|
| `-autoslice` | swings at every pitch (a robot career) | yes | yes |
| `-autobarrel` | with `-autoslice`, swings at full power (1.0× not 0.7×) so every contact clears the barrel threshold; no effect on its own | no | no |
| `-autosign` | on the contract card, signs the dotted line ~1 s after it appears, through the real hit test | no | no |
| `-contract` | start in Triple-A, not entitled, card not yet offered | yes | no (forced) |
| `-declined` | like `-contract`, but the card has already been offered and turned down | yes | no (forced) |
| `-entitled` | force entitled, whatever else is passed | no | yes (forced) |
| `-showstats` | once an `-autoslice` career reaches 12+ pitches at a windup, cuts to the stats board once, for a screenshot | no | no |
| `-park <n>` | start in park `n` instead of wherever the save left off | yes | yes |
| `-streak <n>` | start the career with a home-run streak of `n` already going | yes | yes |
| `-mute` | mutes all sound | no | no |
| `-nosave` | a human run that never reads or writes the real save | yes (itself) | yes |

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
  scene (per the shared PR rule). Build and capture them with `scripts/shots.sh` (see its header
  comment for the `FRAMES` / `GAP` / `KEEP_BOOTED` env vars):
  ```sh
  FRAMES=30 GAP=0.2 scripts/shots.sh /path/to/checkout-or-worktree "iPhone 17" /tmp/out -autoslice -showstats
  ```
  Three lessons from wave 1:
  - `simctl`'s screenshot capture lags the game clock, so landing a frame inside a beat's ~1 s
    window takes dense bursts (short `GAP`, high `FRAMES`) and retries, not one lucky shot.
  - A `.storekit` configuration only applies when the app is launched from Xcode (or an
    `SKTestSession`, which this project doesn't have) — never from `simctl`. A `shots.sh` run
    against `ContractScene` will always show `NO CONNECTION`; that is not a bug in the card.
  - An agent working in a worktree must pass that worktree's path to `shots.sh` literally (its
    first argument) — it cannot assume the checkout root, and it must not `cd` to the main
    checkout to build.

## Milestones

See DESIGN.md §13. M0–M4 are done. Wave 1 of M5 merged 2026-09-19: #22 (Warm Up spec, §18), #23
(feel leftovers — hitstop by quality, `BARREL` call, third pitcher pose, held-finger swing-miss),
#24 (the rest of the organ), #25 (contract card + StoreKit 2), #27 (backdrops/sky/clouds), #26
(fireworks). Audio, haptics, the organ tunes, `parkCeiling`, the contract card and StoreKit 2
wiring (a local `.storekit` file) are all in; the purchase/pending/refund/restore paths have not
been exercised for real, since a `.storekit` configuration only works launched from Xcode. Next:
building the Warm Up itself (#3), §17 steps 4–6 of #14 (stars, moon and tower chase, birds, flag
flutter, crowd bounce), park variety (#5), and the replay clip (#4). `docs/watch.md` is a proposal
for an Apple Watch version and waits on hardware; `docs/ports.md` surveys everything else
(SDL3 → Steam Deck/Windows/Linux, Android, web, consoles) and waits on M5. Both start with
the same first step: lifting the blit and tick out of `CanvasScene` behind a host protocol.
