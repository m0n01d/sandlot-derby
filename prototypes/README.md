# Prototypes

The three HTML pages the design was derived from, in order. Each is self-contained (fonts come from
Google Fonts; everything else is inline). Open in a browser.

1. `01-research-note.html` — market survey, calibrated flight physics with a playable
   timing-vs-flick toy, the Apple guidelines fact-check, the SpriteKit recommendation, and what
   carries over from g0lf.
2. `02-mood-board.html` — the 16-colour Genesis palette, live pixel studies (screen, sprite sheet,
   ball, type, parks), and fifteen classic reference games with links.
3. `03-camera-cut-and-slice.html` — the two-camera loop as a playable prototype: pitch mix, the
   slice hit test with lag forgiveness, contact freeze with swing readout, miss markers. **This is
   the reference implementation for `Core/`**: the JavaScript in its `<script>` block maps
   function-for-function onto `Flight`, `Pitching`, `Contact` and `DerbyMachine`.
4. `04-golden-hour/` — the look and the clock (DESIGN.md §20). Python, no dependencies:
   `python3 golden.py` draws the six phases of both cameras into `targets/`. `engine.py` is a copy
   of `PixelCanvas` with the ordered dither and the shaded shapes added. `now.py` and `side.py`
   port the shipped at-bat and flight frames, so each mock has an honest "before". **This is the
   reference implementation for the §20 port**: `golden.at_bat`, `golden.flight`, `golden.batter`,
   `golden.pitcher` and the `DAWN` … `NIGHT` tables map onto `AtBatScene`, `WideScene`, the sprites
   and `Look`.

These are reference material, not shipped code. Do not edit them; change the spec and the core.
