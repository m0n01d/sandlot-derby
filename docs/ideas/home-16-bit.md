# Home, 16-bit — idea spec

Working title. Asked by Dwight on 2026-09-20 ("scan a place, turn it into a Zelda-style or any
style map, does that exist?"), prototyped the same day at
https://claude.ai/artifact/CbSGZ3W8SntFXk16vgPuWB. A small sibling app. **Spec only, nothing built;
the numbers are the sketch's and unreviewed.** The playable sketch is
[`home-16-bit-sketch.html`](home-16-bit-sketch.html), self-contained, with seeded flats standing in
for a scan.

---

## 1. The pitch

Scan your flat and get it back as a top-down pixel map. A sixty-second RoomPlan sweep gives walls,
doors, windows and sixteen kinds of furniture as boxes; snap them to a 25 cm tile grid, draw them
with a tileset in the derby's sixteen colours, add a tiny you standing where the phone is, and
export the map at 8× as a wallpaper. A keepsake, made once, shared once.

**Does it exist?** The scanning half does, and well: magicplan, RoomScan Pro, Room Scanner and Room
Mapper sell floor plans on RoomPlan. The other half does not: nothing turns the scan into a game
map. The closest things are hand-drawn fan maps of people's houses and a 2012 blog post turning
Bing aerial imagery into Zelda-style tiles, which is the same conversion for the outdoors.

**Pillars**

1. **Sixty seconds of phone.** One sweep, then the phone goes down. AR that passes the test.
2. **A keepsake.** The output is a picture of where you live.
3. **Three tilesets of a dozen glyphs.** A bed is always a bed; each style draws it differently.
4. **Nobody's IP.** "Zelda-style" is what you say to a friend, never the store listing. Original
   tiles in the derby's palette.
5. **Pro phones, honestly.** RoomPlan needs LiDAR. The fallback (§5) works on everything and is
   rougher.

## 2. The conversion

```
RoomPlan scan ─▶ CapturedStructure ─▶ snap to 25 cm tiles ─▶ tile classes ─▶ tileset by style ─▶ PNG at 8×
                 walls, doors,          (a 4 m room is           floor / wall /      overworld /        + a live you
                 windows, openings,      16 tiles; a bed          door / window /     dungeon /          from ARKit
                 16 object boxes         is 3×2)                  object(kind)        cottage
```

- **Walls** become 1-tile lines; doors and windows are marked on the wall they sit in; openings are
  gaps.
- **Objects** keep their RoomPlan category (storage, refrigerator, stove, bed, sink, washer or
  dryer, toilet, bathtub, oven, dishwasher, table, sofa, chair, fireplace, television, stairs) and
  their footprint rounded to tiles: bed 3×2, sofa 3×1, table 2×2, television 2×1, storage 1×3,
  bathtub 3×1, the rest 1×1 (`TileRules.footprints`).
- **Rooms** are labelled from their contents (a toilet makes a bathroom, a stove a kitchen, a bed a
  bedroom), which is all the styles need to vary floors.
- **Off-map** is `ink` (overworld, dungeon) or lawn (cottage).

## 3. Styles

| Style | floor | wall | door | window | bed | table | fridge | stove | sink, toilet, bath |
|---|---|---|---|---|---|---|---|---|---|
| overworld | grass checker | hedge (`shade`/`wall`) | dirt path | sky gap | flower bed | rock | chest | campfire | ponds |
| dungeon | stone checker (`bat`/`dirtD`) | `night` blocks, `ink` mortar | dark gap, two torches | barred | sarcophagus | altar | treasure chest | brazier | pools |
| cottage | planks (`dirt`/`bat`) | logs (`dirtD`) | `bat` | `sky3` | quilt (`chalk`/`cap`) | `bat` | `chalk` | `ink` with `cap` rings | white porcelain |

Each style is about a dozen glyphs of 6×6 px in the sketch; a fourth style is an afternoon.

## 4. The live part

ARKit knows where the phone is inside the scanned space, so a sprite stands where you are standing
and walks the map as you walk the flat. That turns a one-shot picture into something glanced at, at
a map rather than through a camera.

## 5. The fallback without LiDAR

ARKit's visual-inertial tracking runs on the iPad mini and base iPhones. Walk the walls with the
phone held against them and the recorded path is the outline; tap as you pass a door. No furniture,
a rougher map, every device from the last six years.

## 6. Tuning knobs

| Knob | Sketch | Meaning |
|---|---|---|
| `TileRules.tile` | 25 cm | one tile |
| `TileRules.grid` | 52 × 36 tiles | the canvas at 6 px a tile inside 320×224 |
| `TileRules.footprints` | see §2 | object sizes in tiles |
| `ExportRules.scale` | 8× | wallpaper export |
| `StyleRules.*` | three tables | the glyphs per style |
| the sketch's flats | 30–43 × 20–29 tiles, four rooms | seeded stand-ins for a scan |

## 7. The kit

RoomPlan (`RoomCaptureSession`, `CapturedStructure`), ARKit for the live sprite and the fallback,
`ShareLink` and `PHPhotoLibrary` add-only for the export. No network, no accounts. Devices: iPhone
12 Pro and later Pro models, iPad Pro with LiDAR; anything with ARKit for the fallback.

## 8. Prior art, checked 2026-09-20

RoomPlan and its floor-plan apps (magicplan, RoomScan Pro, Room Scanner, Room Mapper, Polycam);
Aitchison's 2012 Zelda tiles from aerial imagery; Zelda-like tilesets as commodities on itch.io and
OpenGameArt. No app makes the conversion.

## 9. Cost and order

Two to three weekends. H0: the conversion (boxes to tiles to classes) and the three tilesets, pure
Swift with a fixture scan as the test. H1: RoomPlan capture and export. H2: the live sprite, the
walk-the-walls fallback.

## 10. Open questions

1. **How often is it opened?** Twice, then shared. That is fine at a weekend of cost and wrong at a
   month.
2. **Phantom chairs.** RoomPlan is strong on the eight big categories and weaker on chairs and
   storage; a wrong chair is charming until it is not. A tap to remove one.
3. **Multi-floor.** `CapturedStructure` handles a floor; stairs are a category; two floors are two
   maps or one with a staircase link.
4. **The name.** Not a Nintendo word.

## 11. Non-goals

A floor-plan tool, measurements, furniture shopping, anything the floor-plan apps already do well.
