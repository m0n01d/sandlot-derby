# Sandlot Derby

A minimalist home run derby for iOS. Sixteen colours, two cameras, one gesture.

The pitch comes at you. You slice through it, Fruit Ninja style. The direction of your slice is the
swing angle, its speed is the power. The frame freezes on the slash, then cuts to a wide side view
where the ball flies with real drag, and the only number that matters ticks up under it: feet.

No outs. No menus. No timers. Parks are seeded and endless. The score is total feet, forever.

- **Spec:** [`DESIGN.md`](DESIGN.md)
- **Physics and calibration oracle:** [`docs/physics.md`](docs/physics.md)
- **Palette:** [`docs/palette.md`](docs/palette.md)
- **Pure-Swift core (physics, pitching, contact, parks, state machine) with tests:** [`Core/`](Core/)
- **Playable HTML prototypes the spec was derived from:** [`prototypes/`](prototypes/)

## Status

Design and core spec complete; no Xcode project yet. `Core/` was written in a Linux sandbox with no
Swift toolchain and has **not been compiled**. First task on a Mac:

```sh
cd Core && swift test
```

Fix whatever the compiler says, keep the calibration tests green, then build the app around the core
(milestones in `DESIGN.md` §13).

## Research trail

Three private pages hold the research, mood board and mechanic prototype this repo distils:

- Research note (market, physics, Apple guidelines, stack): https://claude.ai/artifact/HRGsgjyjBDuL8BAjeyyWfW
- 16-bit mood board: https://claude.ai/artifact/8U47awQommcAap6e6nza6n
- Camera cut and slice prototype: https://claude.ai/artifact/MnDGhy6sJmSNQciwWwvB7T

The same three pages are checked in under `prototypes/` so the repo stands on its own.
