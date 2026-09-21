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

## The phase lines (DESIGN.md §20)

**Built (2026-09-21, #52). The mock and the prototype remain the reference.** When §20 is built, a
frame has three palette lines, and the clock selects the set. The sixteen colours above keep their
roles in each phase. The night swap above goes away, because `night` is one of the six sets.

- Each new colour uses one of the eight levels in each channel: `00 22 44 66 88 AA CC EE`.
- One frame uses 45 colours at most, and transparent.
- A person has four tones: deep shade, shade, body, lit. The light of the phase selects the tone.
- The ordered Bayer 4×4 dither replaces the four-row checker band. §20 lists where it is permitted.
- The birds, the blimp and the towers have a colour in each phase, because `nightSky3` goes away.
- At `dawn` the flight camera looks away from the sunrise, so it has its own sky stops.
- Three entries above are not on the eight levels: `score #EEDD22` (its 9-bit value gives
  `#EECC22`), `shade #116633` (`#006622`) and `night #221144` (`#220044`). They stay as they are
  until Dwight decides.

The tables come from `prototypes/04-golden-hour/golden.py`. If a table and that file disagree, the
file is correct.

### `dawn`

| Role | Colours |
|---|---|
| sky at bat, top to horizon | `#222266` `#444488` `#8888CC` `#CCAACC` `#EEAAAA` `#EECCAA` `#EEEECC` |
| sky in the flight camera, where it differs | `#444488` `#8888CC` `#CCAACC` `#EEAAAA` `#8888AA` `#6666AA` |
| sun or moon, then its halo | `#EEEECC` `#EECCAA` |
| cloud: top, body, lower, underside | `#8888CC` `#CCAACC` `#EEAAAA` `#EECCAA` |
| birds | `#EECCAA` |
| blimp: body, belly | `#EECCCC` `#CCAACC` |
| hills: far, near | `#8888AA` `#666688` |
| trees: shade, body, lit rim | `#224444` `#226644` `#88CC88` |
| stand in the light: mass, lip, under the lip | `#666688` `#EECCCC` `#444466` |
| stand in shadow: mass, lip, under the lip | `#444466` `#8888AA` `#222244` |
| crowd heads | `#EEAA88` `#EECCAA` `#CC8866` |
| crowd shirts | `#CC2222` `#AAAACC` `#CCAACC` `#EEAAAA` `#8888AA` `#6666AA` |
| upper deck: mass, roof edge, lamp, column | `#666688` `#EECCCC` `#EEEECC` `#444466` |
| wall: lit top, face, foot | `#44AA66` `#226644` `#004422` |
| grass the low sun rakes | `#66AA44` |
| dirt: light, body, shade, deep shade | `#EEAA66` `#CC8844` `#AA6622` `#884422` |
| team red: deep, shade, body, lit | `#660022` `#AA2222` `#CC2222` `#EE8888` |
| flannel grey: deep, shade, body, lit | `#444466` `#666688` `#8888AA` `#CCCCEE` |
| skin: deep, shade, body, lit | `#884444` `#CC8866` `#EEAA88` `#EECCCC` |
| bat: deep, shade, body, lit | `#442222` `#884422` `#AA8844` `#EECC88` |
| batting glove: shade, body, lit | `#666688` `#AAAACC` `#EEEEEE` |
| foul pole: lit, shaded | `#EEEE88` `#CCAA22` |
| scoreboard: frame, lit edge, face | `#444466` `#EECCCC` `#222244` |
| ball highlight | `#EEEECC` |
| ball underside | `#AAAACC` |
| ground mist | `#CCCCEE` |

### `morning`

| Role | Colours |
|---|---|
| sky at bat, top to horizon | `#4466CC` `#66AAEE` `#AACCEE` `#CCEEEE` `#EEEECC` |
| sun or moon, then its halo | `#EEEECC` `#AACCEE` |
| cloud: top, body, lower, underside | `#EEEEEE` `#EEEEEE` `#AACCEE` `#88AACC` |
| birds | `#222244` |
| blimp: body, belly | `#EEEEEE` `#AACCEE` |
| hills: far, near | `#88AACC` `#66AA88` |
| trees: shade, body, lit rim | `#116633` `#228844` `#66CC44` |
| stand in the light: mass, lip, under the lip | `#666688` `#EEEECC` `#444466` |
| stand in shadow: mass, lip, under the lip | `#666688` `#EEEECC` `#444466` |
| crowd heads | `#EEAA88` `#EECCAA` `#CC8866` `#884422` |
| crowd shirts | `#CC2222` `#EEEEEE` `#4466CC` `#EEDD22` `#66CC44` `#EE6666` `#AAAACC` |
| upper deck: mass, roof edge, lamp, column | `#8888AA` `#EEEEEE` `#66AAEE` `#666688` |
| wall: lit top, face, foot | `#44AA66` `#226644` `#004422` |
| dirt: light, body, shade, deep shade | `#EEAA66` `#CC8844` `#AA6622` `#884422` |
| team red: deep, shade, body, lit | `#880022` `#AA2222` `#CC2222` `#EE6666` |
| flannel grey: deep, shade, body, lit | `#666688` `#8888AA` `#AAAACC` `#EEEEEE` |
| skin: deep, shade, body, lit | `#AA6644` `#CC8866` `#EEAA88` `#EECCAA` |
| bat: deep, shade, body, lit | `#664422` `#AA6622` `#CC8844` `#EECC88` |
| batting glove: shade, body, lit | `#8888AA` `#AAAACC` `#EEEEEE` |
| foul pole: lit, shaded | `#EEEE88` `#CCAA22` |
| scoreboard: frame, lit edge, face | `#444466` `#EEEEEE` `#222244` |
| ball highlight | `#EEEECC` |
| ball underside | `#AAAACC` |

### `midday`

| Role | Colours |
|---|---|
| sky at bat, top to horizon | `#4466CC` `#66AAEE` `#AACCEE` `#CCEEEE` |
| cloud: top, body, lower, underside | `#EEEEEE` `#EEEEEE` `#AACCEE` `#88AACC` |
| birds | `#222244` |
| blimp: body, belly | `#EEEEEE` `#AACCEE` |
| hills: far, near | `#88AACC` `#66AA88` |
| trees: shade, body, lit rim | `#116633` `#228844` `#66CC44` |
| stand in the light: mass, lip, under the lip | `#666688` `#EEEEEE` `#444466` |
| stand in shadow: mass, lip, under the lip | `#666688` `#EEEEEE` `#444466` |
| crowd heads | `#EEAA88` `#EECCAA` `#CC8866` `#884422` |
| crowd shirts | `#CC2222` `#EEEEEE` `#4466CC` `#EEDD22` `#66CC44` `#EE6666` `#AAAACC` |
| upper deck: mass, roof edge, lamp, column | `#8888AA` `#EEEEEE` `#66AAEE` `#666688` |
| wall: lit top, face, foot | `#44AA66` `#226644` `#004422` |
| dirt: light, body, shade, deep shade | `#EEAA66` `#CC8844` `#AA6622` `#884422` |
| team red: deep, shade, body, lit | `#880022` `#AA2222` `#CC2222` `#EE6666` |
| flannel grey: deep, shade, body, lit | `#666688` `#8888AA` `#AAAACC` `#EEEEEE` |
| skin: deep, shade, body, lit | `#AA6644` `#CC8866` `#EEAA88` `#EECCAA` |
| bat: deep, shade, body, lit | `#664422` `#AA6622` `#CC8844` `#EECC88` |
| batting glove: shade, body, lit | `#8888AA` `#AAAACC` `#EEEEEE` |
| foul pole: lit, shaded | `#EEEE88` `#CCAA22` |
| scoreboard: frame, lit edge, face | `#444466` `#EEEEEE` `#222244` |
| ball highlight | `#EEEEEE` |
| ball underside | `#AAAACC` |

### `goldenHour`

| Role | Colours |
|---|---|
| sky at bat, top to horizon | `#222266` `#444488` `#6666AA` `#AA88AA` `#CC8888` `#EEAA88` `#EECC88` |
| sun or moon, then its halo | `#EEEEAA` `#EECC88` |
| cloud: top, body, lower, underside | `#AA88AA` `#CC8888` `#EEAA88` `#EECC88` |
| birds | `#EECC88` |
| blimp: body, belly | `#EECC88` `#CC8888` |
| hills: far, near | `#886688` `#664466` |
| trees: shade, body, lit rim | `#224444` `#226644` `#CCAA66` |
| stand in the light: mass, lip, under the lip | `#666688` `#EECC88` `#444466` |
| stand in shadow: mass, lip, under the lip | `#444466` `#886688` `#222244` |
| crowd heads | `#EEAA88` `#EECCAA` `#CC8866` |
| crowd shirts | `#CC2222` `#EE8866` `#AAAACC` `#CC8888` `#EECC88` `#8888AA` `#6666AA` |
| upper deck: mass, roof edge, lamp, column | `#664466` `#EECC88` `#EEEEAA` `#444466` |
| wall: lit top, face, foot | `#44AA66` `#226644` `#004422` |
| grass the low sun rakes | `#66AA44` |
| dirt: light, body, shade, deep shade | `#EEAA66` `#CC8844` `#AA6622` `#884422` |
| team red: deep, shade, body, lit | `#660022` `#AA2222` `#CC2222` `#EE8866` |
| flannel grey: deep, shade, body, lit | `#444466` `#666688` `#8888AA` `#CCAAAA` |
| skin: deep, shade, body, lit | `#884444` `#CC8866` `#EEAA88` `#EECCAA` |
| bat: deep, shade, body, lit | `#442222` `#884422` `#AA8844` `#EECC88` |
| batting glove: shade, body, lit | `#666688` `#AAAACC` `#EEEEEE` |
| foul pole: lit, shaded | `#EEEE88` `#CCAA22` |
| scoreboard: frame, lit edge, face | `#444466` `#EECC88` `#222244` |
| ball highlight | `#EEEE88` |
| ball underside | `#AAAACC` |

### `twilight`

| Role | Colours |
|---|---|
| sky at bat, top to horizon | `#000022` `#222244` `#222266` `#444488` `#886688` `#CC8866` |
| cloud: top, body, lower, underside | `#444466` `#664466` `#886688` `#CC8866` |
| birds | `#8888AA` |
| blimp: body, belly | `#8888AA` `#444466` |
| hills: far, near | `#444466` `#222244` |
| trees: shade, body, lit rim | `#002222` `#224444` `#446666` |
| stand in the light: mass, lip, under the lip | `#444466` `#AAAACC` `#222244` |
| stand in shadow: mass, lip, under the lip | `#444466` `#AAAACC` `#222244` |
| crowd heads | `#EEAA88` `#EECCAA` `#CC8866` |
| crowd shirts | `#CC2222` `#AAAACC` `#EEEEEE` `#4466CC` `#EEDD22` `#666688` `#EE6666` |
| upper deck: mass, roof edge, lamp, column | `#222244` `#AAAACC` `#EEEEAA` `#222244` |
| tower: pole, outer bloom, inner bloom, lamp | `#446688` `#444488` `#6666AA` `#EEEEAA` |
| wall: lit top, face, foot | `#44AA66` `#226644` `#004422` |
| dirt: light, body, shade, deep shade | `#EEAA66` `#CC8844` `#AA6622` `#884422` |
| team red: deep, shade, body, lit | `#660022` `#AA2222` `#CC2222` `#EE6666` |
| flannel grey: deep, shade, body, lit | `#444466` `#8888AA` `#AAAACC` `#EEEEEE` |
| skin: deep, shade, body, lit | `#884444` `#CC8866` `#EEAA88` `#EECCAA` |
| bat: deep, shade, body, lit | `#442222` `#884422` `#AA8844` `#EECC88` |
| batting glove: shade, body, lit | `#666688` `#AAAACC` `#EEEEEE` |
| foul pole: lit, shaded | `#EEEE88` `#CCAA22` |
| scoreboard: frame, lit edge, face | `#222244` `#AAAACC` `#000022` |
| ball highlight | `#EEEEEE` |
| ball underside | `#AAAACC` |

### `night`

| Role | Colours |
|---|---|
| sky at bat, top to horizon | `#000022` `#222244` `#222266` `#444488` |
| sun or moon, then its halo | `#EEEECC` `#444488` |
| cloud: top, body, lower, underside | `#666688` `#444488` `#444466` `#222244` |
| birds | `#8888AA` |
| blimp: body, belly | `#8888AA` `#444466` |
| hills: far, near | `#222244` `#000022` |
| trees: shade, body, lit rim | `#002222` `#224444` `#446666` |
| stand in the light: mass, lip, under the lip | `#444466` `#AAAACC` `#222244` |
| stand in shadow: mass, lip, under the lip | `#444466` `#AAAACC` `#222244` |
| crowd heads | `#EEAA88` `#EECCAA` `#CC8866` |
| crowd shirts | `#CC2222` `#AAAACC` `#EEEEEE` `#4466CC` `#EEDD22` `#666688` `#EE6666` |
| upper deck: mass, roof edge, lamp, column | `#222244` `#AAAACC` `#EEEEAA` `#222244` |
| tower: pole, outer bloom, inner bloom, lamp | `#446688` `#444488` `#6666AA` `#EEEEAA` |
| wall: lit top, face, foot | `#44AA66` `#226644` `#004422` |
| dirt: light, body, shade, deep shade | `#EEAA66` `#CC8844` `#AA6622` `#884422` |
| team red: deep, shade, body, lit | `#660022` `#AA2222` `#CC2222` `#EE6666` |
| flannel grey: deep, shade, body, lit | `#444466` `#8888AA` `#AAAACC` `#EEEEEE` |
| skin: deep, shade, body, lit | `#884444` `#CC8866` `#EEAA88` `#EECCAA` |
| bat: deep, shade, body, lit | `#442222` `#884422` `#AA8844` `#EECC88` |
| batting glove: shade, body, lit | `#666688` `#AAAACC` `#EEEEEE` |
| foul pole: lit, shaded | `#EEEE88` `#CCAA22` |
| scoreboard: frame, lit edge, face | `#222244` `#AAAACC` `#000022` |
| ball highlight | `#EEEEEE` |
| ball underside | `#AAAACC` |

