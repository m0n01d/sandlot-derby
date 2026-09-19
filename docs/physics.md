# Flight physics and calibration oracle

One body, three forces. Gravity, quadratic drag, a small backspin lift. Semi-implicit Euler at
240 Hz, integrated once on contact and played back. No physics engine.

## Constants

| Symbol | Value | Meaning |
|---|---|---|
| m | 0.145 kg | ball mass |
| d | 0.0732 m | ball diameter, A = π(d/2)² = 0.00421 m² |
| ρ | 1.2 kg/m³ | air density |
| k | ½·ρ·A/m = **0.0174 /m** | the only derived constant |
| C_d | **0.33** | drag coefficient |
| C_l | **0.15** | lift coefficient (backspin), deliberately a little low |
| g | 9.81 m/s² | |
| dt | 1/240 s | integration step |
| h₀ | 1.0 m | contact height |

Per step, with `s = |v|`:

```
ax = -k·Cd·s·vx  -  k·Cl·s·vy
ay = -g  -  k·Cd·s·vy  +  k·Cl·s·vx
vx += ax·dt ; vy += ay·dt ; x += vx·dt ; y += vy·dt
```

Ground: on `y < 0`, first contact sets the distance; then `vy = -0.4·vy`, `vx *= 0.75`; rolling
decays `vx *= 0.985` per step and stops below 0.3 m/s.

Wall: tested as a plane crossing, `prevX < wall ≤ x`. Below the wall height it is a wall hit
(`vx = -0.35·vx`, ball placed just short of the wall). At or above it, and before first ground
contact, it is a home run. A ball that lands short and rolls into the wall is a wall hit, not a
home run.

Units: SI inside the integrator, **feet** at the API boundary, **mph** and **degrees** for launch.

## Calibration table (the test oracle)

These are the numbers `FlightTests` asserts, at a 380 ft / 10 ft wall. Statcast's rule of thumb
is that 100 mph at about 28° is a 400 ft ball; the calibrated model gives 398.

| Exit velo | Angle | No air | Drag only | Drag + lift (calibrated) | Result at 380/10 |
|---|---|---|---|---|---|
| 90 mph | 20° | 357 ft | 258 ft | **310 ft** | off the wall |
| 90 mph | 28° | 455 ft | 303 ft | **344 ft** | short |
| 100 mph | 28° | 560 ft | 348 ft | **398 ft** | home run |
| 105 mph | 28° | 617 ft | 371 ft | **424 ft** | home run |
| 110 mph | 28° | 676 ft | 393 ft | **450 ft** | home run |
| 110 mph | 40° | 800 ft | 420 ft | **440 ft** | home run |
| 113 mph | 28° | — | — | **465 ft** | home run, 68 ft high at the wall |

Tolerance in tests: ±1.5 % on distance. Drag is the whole feel: 100 mph at 28° flies 560 ft in a
vacuum and 398 ft in air. Real backspin lift is stronger than 0.15, so high spinny hits are
slightly under-rewarded. That is a knob, not a bug.

## Where the numbers came from

`prototypes/sandlot-derby.html` (research note) carries the same integrator in JavaScript and the
table above was produced by it and cross-checked against a separate Python run. If Swift disagrees
with both by more than the tolerance, Swift is wrong.
