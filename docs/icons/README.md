# App icon candidates

Five icons, one palette line. Each is drawn as 64×64 pixel art and scaled ×16 to the App Store's
1024, nearest-neighbour, so the pixel grid survives all the way to the home screen. Regenerate with:

```sh
python3 scripts/icons.py
```

Pick one with `scripts/pick-icon.sh 01` (or `02`…`05`); it copies that candidate into
`App/Assets.xcassets/AppIcon.appiconset/`. **01 CONTACT ships today.**

![contact sheet](contact-sheet.png)

## The rules the icons obey

The same ones the game does, because an icon that breaks them is advertising a different game:

- **One palette line.** Every colour is from `docs/palette.md` and keeps its job — `cap` red is only
  a cap and a seam, `score` yellow is only the slash and the scoreboard, `chalk` is only the ball
  and its trail. No sixteenth colour was invented for the icon.
- **No anti-aliasing, no gradients, no alpha.** The ×16 scale is an integer, so a source pixel is a
  16×16 block and nothing is ever resampled. The sky's bands are the only soft-looking thing on
  screen, and they are a four-row checkerboard dither, exactly as §2 of the palette doc allows.
- **Inside the mask.** iOS rounds the corners at ~22.4% of the width. Nothing that carries meaning
  sits in a corner; the contact sheet renders the mask so you can see what gets cut.
- **It has to work at 60 px.** The contact sheet shows every candidate at 256, 120 and 60 — the
  last is the real home-screen size, and it is the only one that decides anything.

## Where the ideas came from

Straight out of `prototypes/02-mood-board.html`, which already did the research:

| Source | What the icons take |
|---|---|
| **Champion Baseball** (Sega, 1983) | That a baseball game may cut to a *portrait* for the moment of contact. That is icon 01 — not a field, a swing. |
| **R.B.I. Baseball** (Tengen, 1988) | Stubby proportions. A three-head-tall batter reads instantly at 16 px, which is the whole problem an app icon has. |
| **Hardball!** (Accolade, 1985) | How little colour a ballpark needs to still read as a ballpark. Icon 03 is a fence, a horizon and an arc. |
| **Clutch Hitter** (Sega, 1991) | Sega arcade colour: saturated primaries against one dark ink. That is the palette's `cap`/`score`/`ink` triangle. |
| **World Series Baseball** (BlueSky/Sega, 1994) | The outfield scoreboard: yellow type on wall green. Icon 05 is that and nothing else. |
| **Super Baseball 2020** (SNK, 1991) | Big scoreboard type over the wall — borrowed for 05's `HR`, and nothing else, because its palette is far too rich for us. |
| **Desert Golfing** | The restraint. One subject per icon. No badge, no burst, no wordmark. |

## The five

**01 CONTACT** — *ships today.* The hero beat, cropped close: the batter's silhouette at the
contact frame, the ball frozen where the bat met it, the slash through it in `score` yellow. This
is the one with a character in it, which is what earns the tap from a seven-year-old; it is also
the only one that shows the input and the result in the same picture. Busiest of the five at 60 px,
but the red cap and the yellow slash carry it — those two shapes are what the eye finds.

**02 THE BALL** — one object, as big as the frame allows, with the every-fourth-frame trail coming
in from the corner. The cleanest and the most legible of the five at any size, and the most
replaceable: any baseball app could wear it. Pick this if the App Store grid is the priority.

**03 OVER THE WALL** — the whole game as one shape. The wall is on screen from the first frame so
the goal is never explained (mood board, constraint two) and the icon does the same job: an arc,
a fence, a ball that has already cleared it. Warmest and most immediately readable as *home run*.

**04 THE SLASH** — the one gesture as a mark. A tapering `score` slice across a night field with
the ball frozen at the crossing and the contact ring around it. The boldest and by far the most
distinctive — nothing else on a home screen looks like this — but the most abstract, and it reads
as *baseball* a half-second later than the others do.

**05 NIGHT GAME** — the outfield scoreboard read, yellow on wall green, under the light towers.
The most nostalgic of the five and the one that most looks like a 1994 cartridge. Its `HR` is the
5×7 face the game uses for the landing number, unchanged.

## Notes

- The file is a flat, opaque 1024 with no alpha, which is what the App Store requires and what a
  16-bit game should want. If iOS 26's light/dark/tinted variants are wanted later they can be
  added as a layered Icon Composer document; a single flat icon is a deliberate choice, not an
  oversight — the tinted treatment would grey out the exact three colours doing the work.
- `scripts/icons.py` shares its drawing primitives (`px`/`rect`/`line`/`disc`/`dither`) and both
  bitmap faces with the prototypes, so an icon and a frame of the game are drawn the same way.
