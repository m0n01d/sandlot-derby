# Formicarium — idea spec

Working title; *Ant Farm* is Uncle Milton's registered trademark (1956, still live) and cannot be
used. Chosen by Dwight on 2026-09-20 from the brainstorm ("an ant farm in your pocket… everyone's
farms will hopefully be different"), prototyped the same day at
https://claude.ai/artifact/UUt1P8JXx3ykv1BwbA5AHc. A sibling app to Sandlot Derby, not a feature
of it. **Spec only, nothing built; the numbers are the sketch's and unreviewed.** The playable
sketch the numbers come from is [`formicarium-sketch.html`](formicarium-sketch.html),
self-contained, open it in a browser.

---

## 1. The pitch

A pixel ant colony in a frame of sand that runs on the real clock. Open the app and see what they
did while you were away. The sand is a physics simulation with cohesion; the tunnels are dug grain
by grain and the spoil piles up around the door; the brood goes egg, larva, pupa, worker; the whole
farm is a pure function of a seed, your weather and the few times you fed them. Gravity is wherever
the phone says it is: tip it and the loose sand runs to the low side, turn it on its side and the
farm pours, shake it and the grains next to the tunnels fluidise. Every kid who owned one did that
once and regretted it, and there is no undo.

**Pillars**

1. **Nothing to do but look.** Feed and mist are the only taps. No energy meter, no timers to buy,
   no raids. The farm is checked on, not played.
2. **Real physics.** Falling sand with cohesion, and the phone's own gravity vector as the sand's.
3. **Real ants.** A seeded dig plan, spoil heaps from the same physics, brood stages, torpor in the
   cold, cannibalised brood and a real starvation timeline (§4) behind a switch.
4. **Seeded and yours.** Species and sand from the region you are in, activity from your weather, a
   winter diapause where winters are cold. A farm in Phoenix and a farm in Vermont are different
   animals doing different things on the same day.
5. **Sixteen colours, whole pixels.** The derby's palette line; the frame is Uncle Milton green,
   the back panel `wall`, the tunnels read against it.
6. **Counted, never ended.** Even a dead colony leaves its tunnels, and a new queen starts in them.

**Why this and not the market:** Ant Farm Simulator (Dzmitry Smirnou, October 2023) has the same
one-line pitch, "continues to develop even when the game is not running", built with ads, a $1.99
VIP tier and a $0.99 energy pack. Pocket Ants is Clash of Clans with ants. The colony sims are 3D
strategy. Viridi (Ice Water Games, 2015) is the template for the loop: a pot of succulents in real
time, tended two or three times a week, that can die. Nothing glanceable, physical and honest exists.
Ant keeping is a hobby with millions in it (AntsCanada: four million followers, hundreds of
thousands of farms sold; National Geographic, "the unlikely rise of antkeeping").

## 2. The loop

```
open ─▶ catch up (simulate the hours since) ─▶ look ─feed / mist / tip / shake─▶ close
                  ▲                                                                  │
                  └───────────── local notifications for milestones ◀────────────────┘
```

Nothing runs in the background. On open, the elapsed farm-minutes are simulated from the seed, the
weather log and the tap log; the sketch does eight farm-hours in about 120 ms on a laptop. Past a
few days away a coarser day-level model takes over (open question 3).

## 3. The model

Three systems, each pure, each in a core package with tests, as `DerbyCore` is.

**Sand.** A cellular automaton on a 160×112 grid of 2×2 px cells (`FarmRules.grid`). Cell types:
air, sand (with a stratum for colour), tunnel, food. A grain moves only while **loose**
(`loose` counts down from `SandRules.looseSteps` = 30 and the grain packs at 0). A loose grain
falls one cell along the gravity direction if that cell is empty; else slides to one of the two
diagonal neighbours if that cell is *air* (never into a tunnel, which is how tunnel walls hold);
else its counter drops. Grains come loose when an ant digs beside them
(`SandRules.digLoosen` = 0.04 per neighbour), when a vacated cell inside the mass loosens its
neighbours (`SandRules.avalanche` = 0.12 upright, rising linearly to 0.92 at 90° of tip), when the
gravity direction changes (every grain touching a void, p = 0.9) and when the phone is shaken
(acceleration above `SandRules.shakeG` = 4 m/s² loosens grains touching a void with
p = min(0.5, 0.08 × magnitude ÷ 3)). A vacated cell becomes tunnel if the cell "above" it (opposite
gravity) is sand or tunnel, else air. Gravity is one of eight directions, quantised from the phone's
`accelerationIncludingGravity` in the screen plane, zeroed to "upright" when the user enables it.

**Digging.** The colony has a **plan**: a list of cells generated from the seed, 4-connected,
extended lazily whenever fewer than 8 remain: from a random *dug* cell, a wandering shaft down
14–26 cells ending in a chamber, or a gallery of 10–22 cells sideways with a chamber at its end.
Workers claim the next unclaimed plan cell that has a dug neighbour they can walk to
(breadth-first search over passable cells: tunnels, any empty cell below the original surface,
and air within a cell of the ground), walk there at `AntRules.speed` = 3.5 cells per farm-minute,
dig for `AntRules.digMinutes` = 16, carry the grain to the entrance and drop it 3–10 cells to either
side. The heap and the crater are the automaton's work on what they carried. Cells that collapse
(a grain entering a cell that was dug) are re-dug first. Ants stand in tunnels when idle; ants left
outside walk home.

**Brood.** The queen lays every 110–170 farm-minutes while the store has food and the colony is not
hungry (§4), up to 12 brood and 40 workers. Egg to `BroodRules.larva` = 3 farm-days, larva to
`pupa` = 7, pupa to worker = 12. Each larva eats one food unit per farm-day; with none stored it
stalls. A quarter of new workers are nurses who stay with the brood. A real *Lasius niger* takes six
to eight weeks from egg to worker; the farm's clock against the real one is open question 1.

**Weather and region.** Activity (`WeatherRules.activity`): clear 1.0, rain 0.7 and no surface
trips, cold 0.15 (torpor). Rain darkens the top four rows of sand for five farm-hours. Region picks
the species colour and the four sand strata: temperate (black ants, brown loam), desert (red
harvesters, pale sand), tropical (reddish ants, dark soil). In the app the region comes from coarse
location, the weather from WeatherKit, and where the first frost comes the colony enters diapause
until spring.

## 4. Starvation, behind a switch

`FarmRules.canDie`. From the last meal: the store empties around day 4 (larvae eat a unit a day
each); from day 6 the workers eat an egg or larva every 12 farm-hours, each buying half a day; from
about day 15 one worker dies per farm-day and is carried to the pile by the door; the queen dies
when hunger passes `StarveRules.queen` = 12 days (about day 19); the last workers a week later. The
sand keeps every tunnel and *A new queen* starts four workers in them. Hunger only recovers when the
store holds two or more units (`StarveRules.fedStore`), at three days per day. Ant-keeping forums
and one deprivation study put workers at one to two weeks without food (carpenter ants two to six),
queens at weeks to months on reserves, and brood cannibalism first; the sketch's three weeks is in
range. With the switch off the colony only stalls.

## 5. Tuning knobs

| Knob | Sketch | Meaning |
|---|---|---|
| `FarmRules.grid` | 160 × 112 cells of 2 px | the frame's interior at 320×224 |
| `FarmRules.clock` | ×1 real; sketch default ×1200 | farm-minutes per real minute |
| `SandRules.looseSteps` | 30 | steps a disturbed grain stays loose |
| `SandRules.digLoosen` | 0.04 | chance each neighbour of a dug cell comes loose |
| `SandRules.avalanche` | 0.12 → 0.92 | loosening around a vacated cell, upright → tipped 90° |
| `SandRules.tipLoosen` | 0.9 | loosening of grains touching a void when gravity changes direction |
| `SandRules.shakeG` | 4 m/s² | acceleration that counts as a shake |
| `PlanRules.shaft` / `.gallery` | 14–26 / 10–22 cells | branch lengths |
| `PlanRules.chamber` | 7–9 × 3 cells | rounded rectangles |
| `AntRules.speed` | 3.5 cells/min | walking, times activity |
| `AntRules.digMinutes` | 16 | one grain |
| `AntRules.dropRange` | 3–10 cells | either side of the entrance |
| `AntRules.maxWorkers` / `.maxBrood` | 40 / 12 | caps |
| `AntRules.nurseShare` | 0.25 | new workers who stay with the brood |
| `BroodRules.egg` / `.larva` / `.pupa` | 110–170 min / 3 d / 7 d → 12 d | laying interval and stage ends |
| `BroodRules.larvaEats` | 1 unit per farm-day | from the store |
| `StarveRules.eatBrood` / `.workerDies` / `.queen` | 2 d / 6 d / 12 d of hunger | the timeline |
| `StarveRules.fedStore` | 2 units | recovery needs a real meal |
| `WeatherRules.activity` | clear 1, rain 0.7, cold 0.15 | speed and digging |
| `WeatherRules.wetHours` | 5 | how long the surface stays dark |

## 6. Input

One finger, rarely: **Feed** drops a crumb on the surface; **Mist** (not in the sketch) raises
humidity, which real formicaria need. Gravity from Core Motion, zeroed on enable; rotation locked
while the farm is up. Shake from the acceleration magnitude. No pinch, no drag, nothing to steer.

## 7. Art and sound

The green frame with a glass glint, four sand strata by region, `wall` for the back panel so ants
read against it, brood as one- and two-pixel marks, the queen three cells long. Sound: the sand's
hiss when it slides, and nothing else; a formicarium is silent (open question 5).

## 8. The desk mode (the one purchase)

Free in the hand, paid on the desk: §16's shape, and the purchase changes nothing about how the
ants live. Extrude the same 2D sim six voxels deep with a seeded depth profile per tunnel, ants on
the front glass; greedy-mesh it per 16×16 chunk into unlit RealityKit meshes shaded with palette
pairs; anchor it on a detected plane with a tap and save the world map on device, with "place it
again" as the fallback after relocalisation fails; dither the whole frame in a Metal post-process
(`ARView.renderCallbacks.postProcess`) so tank and desk share the sixteen colours. Looking and
walking around only: an anchored tank cannot be tipped, so gravity stays a handheld feature. No
occlusion without LiDAR. About four extra weekends, most of it the mesher.

## 9. The kit

Core Motion (gravity and shake), WeatherKit, coarse location (or a city picker), `UserNotifications`
for milestones scheduled from the forecast and corrected on open. No network beyond weather, no
accounts. ARKit and RealityKit for the desk mode.

## 10. Prior art, checked 2026-09-20

Ant Farm Simulator (2023, ads and energy purchases, 56 ratings); Pocket Ants; Ant Simulation 3D,
Ant Colony Simulator, Ant Sandbox, Idle Ant Colony; Empires of the Undergrowth (PC only, 2024);
Viridi (2015); SimAnt (1991); the Uncle Milton trademark.

## 11. Cost and order

Four to five weekends for the handheld farm. F0: the core package (sand, plan, ants, brood,
starvation, catch-up), pure Swift with tests, a port of the sketch's `<script>` function for
function. F1: the frame on the derby's `PixelCanvas`, gravity and shake. F2: weather, region,
notifications. F3: sound, the mist, polish. F4 (separate, paid): the desk mode.

## 12. Open questions

1. **The clock.** ×1 is honest and slow; nothing visible happens for an hour. ×7 reaches the first
   workers in two days. Try both on a phone for a fortnight.
2. **Death.** Built, behind a switch. Whether it ships on is the decision.
3. **Long absences.** A month away at a quarter of a millisecond per farm-minute is eleven
   seconds; a day-level model (grains per worker-day, brood by stage) is needed past a week.
4. **A queen or not.** Uncle Milton farms shipped workers only and died in weeks, which is the
   honest memory. The hobby starts from a founding queen. The sketch has a queen.
5. **Hibernation.** Four months of nothing is faithful and empties the app until March.
6. **Sharing.** A snapshot of the frame with the day count.

## 13. Non-goals

Raids, other players, currencies, energy, ads, anything money can buy that changes how the ants
live. The desk mode is the only purchase.
