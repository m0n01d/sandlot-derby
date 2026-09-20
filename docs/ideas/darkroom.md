# Darkroom — idea spec

Working title. Chosen by Dwight on 2026-09-20 from the second brainstorm board ("Cozy Sketchbook",
https://claude.ai/artifact/SM4Rrq5BDbnu4aEeMdG7v8). A sibling app to Sandlot Derby, not a feature of
it; it lives in this folder until it has a repo of its own. **Spec only, nothing built; the numbers
are the sketch's and unreviewed.** The playable sketch the numbers come from is
[`darkroom-sketch.html`](darkroom-sketch.html), self-contained, open it in a browser.

---

## 1. The pitch

You pick a photo from your library. It goes into the developing tray as a blank sheet under a red
safelight. You rock the phone, and the shadows come up first, the way they do on real paper. Rock
evenly and the print is even; hold it tilted and one side runs dark. Tap the lights and the hard
cut turns the red room into a warm-tone print in the game's sixteen colours. That print is the thing
you keep.

**The hard thing:** developing a print is fussy, timed and done in the dark. **The cozy move:** keep
the motion (rocking a tray), make the phone's roll that motion, and count instead of judge.

**Pillars**

1. **One gesture.** Rocking. The phone's roll is the tray's tilt. Nothing else is asked during a
   print. Lights and "new sheet" are the only taps, and they come between prints.
2. **Your own photo.** The input is the camera roll, through the system picker, so it never asks for
   a permission and never sees the library.
3. **Sixteen colours.** The derby's palette line (`docs/palette.md`), whole pixels, Bayer dither.
   Under the safelight the print is drawn in a four-step red ramp; under white light in a five-step
   warm ramp. Two ramps, no new hex.
4. **The lights are a hard cut.** No fade from red to white. One frame it is the safelight, the next
   it is the print.
5. **Never punished, only counted.** An uneven print is still a print, and it is the honest one.
   The verdict names what happened (`EVEN`, `A LITTLE UNEVEN`, `UNEVEN`, `THIN`, `DARK`); it never
   stops you hanging it.

**Why this and not the market:** Retrospecs has turned photos into Mega Drive palettes since 2014,
so the output alone is not new. The store's darkroom apps are timers and lab databases (DevelopFilm,
The Darkroom Lab). Nothing lets you *do* the developing. The mechanic is open.

## 2. The loop

```
pick ─▶ sheet in the tray ─rock─▶ developing ─lights (CUT)─▶ print + verdict ─hang─▶ gallery
                                                                     └─new sheet──▶ pick
```

| Beat | What happens |
|---|---|
| **pick** | `PHPickerViewController`, one image. Downsampled to the print size, luminance only, stretched to full range. |
| **sheet** | Blank paper in the tray, safelight on, timer at 0:00. |
| **developing** | Every frame: the tray's slosh integrates the phone's roll; development advances per column at a rate set by depth and activity (§3). The HUD says `ROCK THE TRAY` → `KEEP IT MOVING` → `ABOUT DONE`. |
| **lights** | Hard cut. Ramp swaps, development freezes, the verdict is computed once. |
| **hang** | The print joins a strip of hung prints. Share and Save to Photos export at 4× (`PrintRules.exportScale`) as a PNG with the white border. |

## 3. The model

All of this is pure and belongs in a core package, tested the way `DerbyCore` is.

**Luminance.** `L[x, y] ∈ [0, 1]` from Rec. 709 weights, then `(L − min) / (max − min)` so any photo
uses the whole ramp.

**Slosh.** One scalar `s` (developer displacement, −1 left … +1 right) with velocity `sv`:

```
force = tiltGain · roll + dragGain · dragVelocity
sv   += (−k·s − c·sv + force) · dt
s    += sv · dt,  clamped to ±sMax
```

**Development** is per column, so unevenness is left–right, which is what a tilted tray does:

```
depth(x)    = 1 + s · (2x/(w−1) − 1) · depthGain
activity    = min(1, |sv| / activityRef)
P[x]       += base · (idleFactor + (1 − idleFactor) · activity) · max(depthFloor, depth(x)) · dt
```

**Tone** shown at a pixel, then dithered into the ramp:

```
density = min(devMax, P[x]) · (1 − L[x, y])
tone    = clamp(1 − density)             1 = paper white, 0 = full black
index   = floor((1 − tone) · (ramp.count − 1) + bayer4x4[y mod 4][x mod 4] / 16)
```

The darkest parts of the photo have the highest `1 − L`, so they come up first. Past `P = 1` the
print keeps darkening to `devMax`: an over-developed print goes muddy, not black.

**Verdict**, computed once at the lights:

```
spread = max(P) − min(P)  over columns     mean = average(min(devMax, P))
EVEN if spread < evenSpread, A LITTLE UNEVEN if < unevenSpread, else UNEVEN
+ THIN if mean < thinMean, + DARK if mean > darkMean
```

## 4. Tuning knobs

Every number is a named knob. The sketch's values are the starting point; the real developing time
should be a good deal longer than the sketch's twenty seconds, and that is the first thing to tune on
a phone.

| Knob | Sketch | Meaning |
|---|---|---|
| `PrintRules.width × height` | 96 × 64 | print pixels; the sketch draws them at 2× on a 320×224 canvas |
| `PrintRules.exportScale` | 4 | PNG export scale |
| `PrintRules.safelightRamp` | skin, cap, dirtD, night | four steps, light to dark |
| `PrintRules.printRamp` | chalk, skin, dirt, dirtD, ink | five steps, warm tone |
| `DevRules.base` | 1/19 per s | full development in ~19 s of steady rocking |
| `DevRules.idleFactor` | 0.4 | rate with the tray still |
| `DevRules.activityRef` | 1.6 | slosh speed that counts as full agitation |
| `DevRules.depthGain` | 0.9 | how much a tilt favours one side |
| `DevRules.depthFloor` | 0.1 | the shallow side never fully stalls |
| `DevRules.devMax` | 1.35 | over-development cap |
| `SloshRules.k` / `.c` | 12 / 1.6 | spring and damping (period ≈ 1.8 s) |
| `SloshRules.tiltGain` | 7 | force per unit of roll (roll normalised to ±1 at 30°) |
| `SloshRules.dragGain` | 0.9 | force per px of drag, the fallback input |
| `SloshRules.sMax` | 1.2 | displacement clamp |
| `VerdictRules.evenSpread` / `.unevenSpread` | 0.2 / 0.45 | spread thresholds |
| `VerdictRules.thinMean` / `.darkMean` | 0.55 / 1.2 | mean thresholds |

## 5. Input

- **Roll** from Core Motion, zeroed on the first touch of a sheet, normalised to ±1 at
  `SloshRules.rollFull` (30°). No permission is needed for attitude.
- **Drag** across the tray as the fallback and for iPad-on-a-stand: horizontal pointer velocity is
  the force.
- Dev only: arrow keys.

## 6. Art and sound

Bench, tray, safelight bulb with a dithered halo, tongs, the print's white border under white
light. All borrowed by role from the palette. Sound: the developer sloshing (procedural, pitched by
`|sv|`), a timer tick every second, the click of the light switch, and nothing else. Haptic: one soft
tick when the first shadow comes up (`P` crossing `firstShadow`, a knob), and one on the click.

## 7. The kit

`PhotosUI` (`PHPickerViewController`, no permission), Core Motion (roll), `PHPhotoLibrary` with the
add-only authorisation for Save, `ShareLink` for the PNG. No network, no accounts.

## 8. Prior art, checked 2026-09-20

- Retrospecs (John Parker, 2014): photos into forty retro palettes with eight dithers, Mega Drive
  included. The output; not the mechanic.
- DevelopFilm: Darkroom Lab, The Darkroom Lab Timer, Darkroom Solutions: timers and databases for
  real developing.
- "Darkroom" is the name of Bergen Co's photo editor, so the working title cannot ship. Candidates:
  Safelight, Tray, Fixer.

## 9. Cost and order

Three weekends. D0: the core package (luminance, slosh, development, dither, verdict), pure Swift
with tests, a port of the sketch's `<script>` function for function. D1: the tray scene on the
derby's `PixelCanvas` approach, tilt and drag. D2: picker, lights, hang, export. D3: sound, haptics,
the gallery strip.

## 10. Open questions

1. **Real developing time.** Twenty seconds is a demo. A minute reads as a ritual; two is a chore.
2. **Stop bath and fixer.** Real prints go through two more trays. Two more beats of rocking, or a
   single tap, or nothing.
3. **Print size.** 96×64 keeps the dither honest at 2×; 128×96 would flatter photos and cost the
   look.
4. **Dodging.** A finger held over the print to hold back development is the obvious second gesture,
   and pillar 1 says no. Decide after D1 on a phone.
5. **Colour.** One warm ramp. An RA-4 colour mode would need the full palette and a different reveal
   and is a non-goal until the first version has shipped.
6. **Pricing.** Undecided. The derby's §16 (free to start, pay once) is the default to argue against.

## 11. Non-goals

Filters, sliders, adjustment layers, sharing to social from inside the app, accounts, ads, anything
money can buy that changes the print.
