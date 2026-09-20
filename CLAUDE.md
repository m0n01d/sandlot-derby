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
  Wave 2 (2026-09-19) added `WarmUp.swift` (`WarmUp.generate(day:)` — the day's ten pitches, a
  pure function of the date, §18), `Replay.swift` (`Replay` — the record a clip is re-rendered
  from, §19) and `SkyLife.swift` (`SkyLifeRules` — star blink, the lights' chase, crowd bounce,
  flag flutter and the bird flock, §17). Wave 3 (2026-09-20) added `RareEvents.swift`
  (`RareEvents.detect` — finds every rare thing a batted ball passes through: a bird, the blimp,
  the out-of-town board and its lit pane, the light standard over the wall, §17 step 6, #5) and
  `SideView.swift` (`SideViewRules` / `SideView.framing` — the side view's wide and close framing,
  hoisted out of `WideScene` so a rare event can be judged against where the ball is drawn). Wave 4
  (2026-09-20) added `Records.swift` (`Records.kind(before:after:swing:)` — a pure comparison of
  the tally before and after a swing, plus `RecordRules`/`RecordKind`, so the live game, a replay
  clip and a test all agree on which record fell, §10, #41).
- `App/` — the iOS app. The Xcode project is generated and git-ignored:
  `cd App && xcodegen generate && open SandlotDerby.xcodeproj`. SwiftUI `ContentView` → `SKView` →
  scenes (`AtBatScene`, `WideScene`, `ContractScene`, `WarmUpCardScene`) driven by `DerbyMachine`
  through `GameController`. Scenes are renderers and gesture sources only; they own no game state.
  Both play/at-bat scenes draw a whole frame into a software `PixelCanvas` (the prototype's
  `px/rect/line/disc/t3/t5`) shown through one nearest-filtered `SKMutableTexture`. DEBUG only:
  space bar is the dev slice; see "DEBUG launch arguments" below for the full set. Wave 1 also
  added `Backdrop.swift` and `Clouds.swift` (the cached backdrop layers and cloud drift behind
  `Scenery`), `ContractScene.swift` (the paywall card, §16), and `Store.swift` with
  `App/SandlotDerby.storekit` (StoreKit 2, no server). Wave 2 added `WarmUpCardScene.swift` (the
  Warm Up's result card, modelled on `ContractScene`, §18), `ReplayRenderer.swift` (renders a
  `Replay` to an off-screen `.mp4`, §19) and `SkyArt.swift` (turns `SkyLife`'s answers into
  palette pixels — stars, towers, birds, §17). Wave 4 added `ReplayScene.swift`
  (`ReplayScreenLayout` plus the replay screen itself — the swing again, in real time, hard-cut
  over the paused live machine, §19, #42), `ReplayPlayback.swift` (`ReplayPlayback` — ticks a
  private rebuilt machine and draws it through off-screen copies of `AtBatScene`/`WideScene`, the
  one path both the replay screen and the exported clip drive, §19) and `ReplayIcon.swift`
  (`ReplayIconLayout` plus the camera in the corner and its hit test, replacing #4's long press,
  §19, #42).
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
| `-records` | a career standing one home run short of a record: seeds the 25 swings the gate asks for, a longest any home run beats, and a fewest-to-clear that clearing a park beats; pair with `-park <n>` for a park with an organ, since Single-A has no organist (§10, #41) | yes | yes |
| `-warmup <day>` | force the Warm Up for a `YYYYMMDD` day, faking the one cleared park the gate asks for (§18) | yes | yes |
| `-warmupcard` | jump straight to the Warm Up's result card with a made-up ten, the way `-streak` fakes a streak (§18) | yes | yes |
| `-replayscreen` | with `-autoslice`, opens the replay screen once, at the windup after the first swing that earns the camera, and leaves it there — for screenshots of #42 | yes | yes |
| `-replay <path>` | implies `-replayscreen`; with `-autoslice`, writes the first home run's clip to `<path>` (absolute) or a filename in Documents **from the replay screen, game paused** — through the very same door `SHARE` uses, not during live play — and logs where it went (§19, #42) | yes | yes |
| `-skyclock <seconds>` | winds the sky's clock forward so a screenshot can reach a bird flock without waiting; moves scenery only and fakes no career state, so it is on **neither** list (§17) | no | no |
| `-autoloft` | with `-autoslice`, the dev swing takes a steep 53° stroke instead of 27°, so it puts up a towering fly the birds and the blimp can be pinned against; like `-autobarrel` it changes only the stroke and fakes no career state, so it is on **neither** list (§17, #5) | no | no |
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
  Nine lessons from waves 1–4:
  - `simctl`'s screenshot capture lags the game clock, so landing a frame inside a beat's ~1 s
    window takes dense bursts (short `GAP`, high `FRAMES`) and retries, not one lucky shot.
  - A `.storekit` configuration only applies when the app is launched from Xcode (or an
    `SKTestSession`, which this project doesn't have) — never from `simctl`. A `shots.sh` run
    against `ContractScene` will always show `NO CONNECTION`; that is not a bug in the card.
  - An agent working in a worktree must pass that worktree's path to `shots.sh` literally (its
    first argument) — it cannot assume the checkout root, and it must not `cd` to the main
    checkout to build.
  - A burst `GAP` that happens to land on an animation's own period aliases it — a 0.4 s gap made
    a 5 Hz light chase read as frozen in every frame. Vary `GAP` across a run rather than trusting
    one burst at a fixed interval.
  - Two features built in parallel, each correct against a main that has never seen the other, can
    be wrong together (wave 2: a replay clip made during a Warm Up would have been labelled with
    the career's park, #33). The conductor builds one integration tree and screenshots the
    *combination*, not just each feature alone, before merging a wave.
  - `simctl io screenshot` stills are too lossy to catch a rare event's ~0.5 s two-frame burst
    (wave 3): the shutter and the game clock are not synced tightly enough to land inside a window
    that short, even with a dense `GAP`/`FRAMES` sweep. Record video instead and pull frames:
    ```sh
    xcrun simctl io <udid> recordVideo --codec h264 out.mp4   # stop it with Ctrl-C (SIGINT)
    ffmpeg -i out.mp4 -vf fps=30 v%03d.png
    ```
  - Dwight plays on a real **iPad mini 6**, not a phone (wave 4, #42's three complaints came from
    that device). UI work should be checked on an iPad mini simulator as well as a phone:
    `DEVICE_TYPE="iPad mini (A17 Pro)" scripts/shots.sh /path/to/checkout "derby-ipad" /tmp/out
    -autoslice` (see the script's header comment for the full `DEVICE_TYPE`/`ROTATE` contract).
  - **Debug builds are far slower than Release at pixel work** — a replay export measured 16 s in
    Debug and 3 s in Release before #43's fixes (§19). Judge performance in Release:
    `xcodebuild -configuration Release …`. A build installed from Xcode onto a device is Debug
    unless the scheme says otherwise, so a laggy Xcode run does not by itself mean a laggy shipped
    build.
  - The iOS Simulator tap/capture tools (`xcrun simctl`, this project's screenshot and video
    recipes) need `xcode-select` pointing at `Xcode.app`, not just the Command Line Tools —
    switching it needs Dwight's password, so an agent that hits an `xcode-select` error should say
    so rather than trying to work around it.

  `SURVEY=1 swift test --filter RareEventSurvey` un-skips `RareEventTests`' two rarity-survey
  tests, which sweep every park (and, for the sky, every half-second of the clock) against the
  `-autoslice -autobarrel` robot's *whole* launch envelope, not one idealised swing, and print the
  parks most robust for a screenshot: `ROBUST <kind>: park N (X%), ...` for the board dent, the
  broken window and lights-out, and `ROBUST birdStrike` / `ROBUST blimpHit: park N -skyclock S, ...`
  for the sky.

## Milestones

See DESIGN.md §13. M0–M4 are done. Wave 1 of M5 merged 2026-09-19: #22 (Warm Up spec, §18), #23
(feel leftovers — hitstop by quality, `BARREL` call, third pitcher pose, held-finger swing-miss),
#24 (the rest of the organ), #25 (contract card + StoreKit 2), #27 (backdrops/sky/clouds), #26
(fireworks). Wave 2 merged the same day: #30 (the replay clip, §19), #31 (the Warm Up itself,
§18), #32 (the night kit, birds, flag flutter, crowd bounce and the at-bat foul poles — §17 steps
4–5, #28). Wave 3 merged 2026-09-20: #34 (the replay-during-Warm-Up fix, #33, and the wave 2 docs
batch) and #37 (park variety, #5, §17 step 6). Wave 4 merged 2026-09-20: #43 (the instant replay
rebuilt around a camera icon and a lead-in, closing #42, §19) and #44 (three-home-run parks and the
record celebration, closing #40 and #41, §10). Audio, haptics, the organ tunes, `parkCeiling`, the
contract card, StoreKit 2 wiring (a local `.storekit` file), the Warm Up, the instant replay, park
variety, three-home-run parks and the record celebration are all in; the purchase/pending/refund/
restore paths have not been exercised for real, since a `.storekit` configuration only works
launched from Xcode. Next: every buildable issue is
closed; what remains is Dwight's — #11 (pricing, §16) needs the purchase, pending, refund and
restore paths run from Xcode, and the review of every decision still marked unreviewed; then the
rest of M5 (the app icon, Game Center, TestFlight, the store listing). `docs/watch.md` is a
proposal for an Apple Watch version and waits on hardware.
