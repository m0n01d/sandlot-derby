# Palette: one Genesis line

Sixteen entries, fifteen colours plus transparent. Every channel is one of the Mega Drive's eight
levels (0, 34, 68, 102, 136, 170, 204, 238 in the common emulator mapping). This constraint plus no
anti-aliasing is most of what makes 16-bit art read as 16-bit.

| Name | Hex | 9-bit RGB | Job |
|---|---|---|---|
| sky1 | `#4466CC` | 2 3 6 | high sky |
| sky2 | `#66AAEE` | 3 5 7 | sky |
| sky3 | `#AACCEE` | 5 6 7 | horizon |
| grassA | `#22AA44` | 1 5 2 | grass |
| grassB | `#228844` | 1 4 2 | grass stripe |
| wall | `#226644` | 1 3 2 | outfield wall, scoreboard ground |
| dirt | `#CC8844` | 6 4 2 | infield dirt, mound |
| dirtD | `#AA6622` | 5 3 1 | dirt shade |
| chalk | `#EEEEEE` | 7 7 7 | lines, the ball, trail |
| ink | `#222244` | 1 1 2 | silhouettes, label backgrounds |
| skin | `#EEAA88` | 7 5 4 | face, hands |
| cap | `#CC2222` | 6 1 1 | cap, HR flash, miss X |
| bat | `#AA8844` | 5 4 2 | bat |
| score | `#EEDD22` | 7 6 1 | scoreboard numbers, readouts, ring, slash core |
| shade | `#116633` | 0 3 1 | ball shadow |
| night | `#221144` | 1 0 2 | night sky (swaps for sky1) |

Rules:

- A colour has one job. If a new element needs a colour, it borrows one by role, never a new hex.
- Night parks swap `sky1 → night` and `sky2 → ink`, `sky3 → #446688` (2 3 4). Nothing else changes.
- Dither: one checkerboard band per sky transition, four rows tall. Nowhere else.
- No outlines on the batter. The silhouette sits directly on the grass.
- Text: 3×5 face for labels and readouts, 5×7 for the landing number. Both are in the prototype
  scripts as bitmaps; port them as `SKTexture`s or draw them from the same bit strings.
