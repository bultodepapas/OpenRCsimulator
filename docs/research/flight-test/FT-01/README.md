# FT-01: standard flight-test battery and fleet baseline

2026-10-16 · Revision 2 · **Status: standard battery `ft-card-v2` implemented, verified (deterministic, catches a deliberate change) and run on all eight fixed-wing catalog aircraft. Knife-edge exposes a shared side-force gap; the glow Stiks cannot fly slowly.** [Tool, card and workflow](../../../../research/flight-test/README.md)

## Baseline

| Item | Value |
| --- | --- |
| Commit | `208f0b89`, no modified paths under `app/` or `research/flight-test/` ([run.json](run.json)) |
| Engine and conditions | Godot 4.7.2 official, native Windows, 240 Hz; calm standard air |
| Aircraft | Every fixed-wing catalog aircraft; the helicopter is excluded by the catalog listing |
| Runtime | About 10 minutes with 4 parallel jobs; each glow Stik alone takes 6–7 |

Each aircraft folder holds `profile.md`, `profile.json` and `run.log`. The P-51 folder also keeps the 20 Hz CSV traces; the others regenerate with `run.py`. These are model predictions, not physical validation. Compare a later candidate against this folder with `compare.py`.

## Verification of the battery

- **Deterministic.** Two complete runs of the same code match at zero tolerance across all eight aircraft ([report](verification/determinism.md)). The data files of every aircraft had identical SHA-256 in both runs. During the second run another track had uncommitted edits elsewhere in `app/`.
- **It catches a deliberate change.** In a disposable copy, the P-51 got 20 % more elevator throw. The comparator flags 76 changes and exits 1 with `--fail-on-change` ([report](verification/negative-control-elevator-throw.md), [run](verification/negative-control-run.json)). The changes are the expected ones:
  - the full-up pull reaches 13–14 % more pitch rate and 2° more α;
  - the trimmed elevator stick changes;
  - spin entry and recovery change.

  The steady speeds do not move: maximum level speed, stall speed and climb.
- **Changes between versions are explained.** From the previous run to this baseline, the comparator lists only two groups ([report](verification/previous-run-to-baseline.md)). The Extra 300's data changed and it gained a qualified runway start in `208f0b89`, so its takeoff and landing went from skipped to valid. In the glow Stiks, the new mode check removed "phugoids" of 0.2–0.33 s that were mislabelled roots.

## Fleet comparison

From [`summary.md`](summary.md). A dash means not measured.

| Metric | Ugly Stik 60 (electric) | Stik · MAX-61FX | Stik · MAX-55AX | Stik · FS-64V | Extra 300S .60 | P-51D Mustang 1/4 | Ventage Jet | Turbo Lumber Evolution |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Mass (kg) / start speed (m/s) | 2.89 / 15.0 | 2.89 / 20.0 | 2.62 / 20.0 | 2.59 / 20.0 | 3.42 / 17.0 | 21.50 / 25.0 | 11.71 / 29.0 | 2.19 / 13.1 |
| Power-off stall (m/s), wing drop | 9.60 left | – | – | – | 10.51 left | 15.45 left | 18.02 right | 8.58 left |
| Power-on stall, 50 % throttle (m/s) | 8.72 | 6.42 | 7.40 | 6.69 | 9.80 | 13.02 | 13.30 | 8.27 |
| Max level speed (m/s) | 32.7 | 38.1 | 38.9 | 27.6 | 34.6 | 58.2 | 73.1 | 30.1 |
| Time +10 m/s, full throttle (s) | 1.52 | 2.00 | 2.28 | – | 1.84 | 2.39 | 2.63 | 2.15 |
| Cruise throttle at start speed | 0.282 | 0.013 | 0.102 | 0.110 | 0.357 | 0.100 | 0.086 | 0.410 |
| Best full-throttle climb (m/s) | 17.2 | 20.9 | 16.2 | 14.2 | 15.2 | 17.1 | 20.2 | 10.7 |
| Best idle glide ratio | 9.3 | – | – | – | 8.0 | 11.3 | 9.8 | 13.9 |
| Full-aileron roll at start speed (°/s) | 201 | 208 | 207 | 200 | 272 | 137 | 363 | 300 |
| 60° level turn, full throttle (°/s) | 31.2 | 26.1 | 25.5 | 36.1 | 30.0 | 17.7 | 14.3 | 33.3 |
| Loop height (m) / time (s) | 43 / 4.5 | 43 / 3.9 | 42 / 3.7 | 31 / 4.0 | 47 / 4.8 | 101 / 6.5 | 118 / 6.3 | 38 / 4.6 |
| Knife-edge, full top rudder, full throttle: vertical speed (m/s) / sideslip (°) | −4.8 / 17.3 | +9.1 / 17.3 | +10.6 / 17.3 | −12.0 / 17.2 | −37.7 / 20.7 | −20.3 / 22.0 | +0.5 / 15.5 | −24.8 / 16.9 |
| Inverted pass: elevator stick / α (°) | −0.028 / −4.5 | −0.021 / −3.7 | −0.019 / −3.4 | −0.024 / −4.1 | −0.116 / −3.5 | −0.085 / −4.0 | −0.026 / −1.8 | −0.494 / −8.0 |
| Spin (right): entry / time per turn (s) / recovery turns | spin / 1.32 / 0.16 | spin / 1.24 / 0.29 | spin / 1.13 / 0.28 | spin / 1.15 / 0.29 | spin / 1.26 / 0.26 | spin / 1.46 / 0.34 | spiral / 15.7 / – | spiral / 5.7 / – |
| Modes at start speed: phugoid period (s), ζ / dutch roll ζ / spiral | 11.2, 0.29 / 0.25 / doubles 8.8 s | 15.4, 0.84 / 0.24 / doubles 16.0 s | 16.1, 0.88 / 0.25 / doubles 16.6 s | –, – / 0.25 / doubles 16.6 s | 9.4, 0.21 / 0.25 / doubles 4.8 s | 10.6, 0.18 / 0.28 / halves 68.9 s | 16.7, 0.09 / 0.17 / doubles 20.0 s | 6.7, 0.13 / 0.20 / doubles 6.2 s |
| Hands off 30 s after small pulses: heading (°) / height (m) | 374 / −88.8 | 270 / −115.9 | 256 / −101.8 | 263 / −197.0 | 627 / −121.1 | 110 / −11.8 | 292 / −77.4 | 851 / −52.5 |
| Lift-off speed (m/s, Vs) / ground roll (m) | 16.2 (1.69) / 15 | 16.8 (1.77) / 16 | 15.6 (1.72) / 16 | 15.4 (1.71) / 18 | 15.3 (1.45) / 14 | 21.4 (1.38) / 34 | 25.6 (1.42) / 56 | 12.3 (1.43) / 10 |
| Landing: touchdown speed (m/s) / sink (m/s) / rollout (m) | 12.0 / 0.48 / 40 | 22.4 / 0.44 / 122 | 19.4 / 0.44 / 98 | 19.4 / 0.44 / 130 | 12.9 / 0.53 / 88 | 19.2 / 0.53 / 170 | 21.6 / 0.47 / 120 | 10.9 / 0.55 / 63 |
| Spool-up 10–90 % (s) | 0.55 | 2.66 | 3.46 | 2.07 | 0.55 | 4.35 | 1.24 | 0.50 |
| Valid tests | 20 / 20 | 18 / 20 | 19 / 20 | 19 / 20 | 20 / 20 | 20 / 20 | 20 / 20 | 20 / 20 |

Stall recovery heights, maneuver times, loop size and landing distances describe this battery's pilot technique, not the best each airplane can do.

## P-51 against its references

[P-51 profile](p51d-mustang-120/profile.md). The references come from the [P-51 realism research](../../p51-flight-realism.md).

- **Power-off stall:** 15.45 m/s, 0.99 of the CL_max estimate. It drops the left wing, like the XP-51's stall break (NACA MR L-566).
- **Takeoff:** lift-off at 21.4 m/s (1.38 Vs) after a 34 m roll, against the 20–50 m class estimate.
- **Landing:** touchdown at 19.2 m/s with 0.53 m/s of sink; 170 m rollout without brakes.
- **Maximum level speed:** 58.2 m/s gear up. The gear-down envelope test gives 51.4 m/s, against a Top Flite Giant owner's ~51 m/s.
- **Roll:** 134–138°/s at 20–25 m/s and 186–189°/s at 47 m/s.
- **Turns:** a 60° turn at full throttle is symmetric at 17.7°/s.
- **Spins:** they develop at 1.46 s per turn and recover in a third of a turn.
- **Spiral:** the P-51 is the only aircraft in the fleet with a stable spiral at its start speed (halves in 69 s).

## Findings for the owning tracks

**1. Knife-edge loses its side force beyond 15° of sideslip (physics, all aircraft).** Every aircraft blends from the empirical oracle to the local surface model between 15° and 25° of sideslip (`aero.envelope.sideslip_blend`). The local model has no fuselage crossflow side force. Under full top rudder, the side force on wing area falls well below each aircraft's own linear CYβ:

| Aircraft | Sideslip | CY in the trace | CY from linear CYβ |
| --- | ---: | ---: | ---: |
| Extra 300 | 20.7° | −0.023 | −0.173 |
| P-51 | 22.0° | −0.054 | −0.161 |
| Ugly Stik | 17.3° | −0.092 | −0.148 |

The Extra, an aerobatic design built for knife-edge, sinks 38 m/s. Only the glow Stiks climb in knife-edge, on full-throttle thrust, and the jet holds height only because its thrust carries weight at 16° of nose-up attitude. A fix is a fuselage crossflow side-force law in the local model, with per-aircraft side-area data, checked against this battery's knife-edge cases. No coefficient was changed here.

**2. The glow Stiks cannot fly slowly (glow engines).** The MAX-61FX trims no lower than 20.0 m/s, the MAX-55AX 15.0 and the FS-64V 18.0; the electric Stik trims down to 10.5 m/s. The session trim fails below those speeds. At idle in flight the MAX-61FX still turns about 10,900 rpm, so none of the three can slow down to a power-off stall in 40 s. Their landings touch down at 19–22 m/s, about 2 Vs. The electric Stik idles at 2800 rpm on the same card. This belongs to the [glow engine track](../../../GLOW-ENGINES.md).

**3. Fast-diverging spirals (aircraft data).** At the start speed, the spiral doubles in:

- 4.8 s on the Extra 300;
- 6.2 s on the Turbo Lumber Evolution;
- 8.8 s on the electric Stik.

Hands off after a small aileron pulse, the Timber turns 851° in 30 s. A dihedral high-wing STOL design is normally spirally stable, so its dihedral effect (Clβ) deserves a check against sources. The fast spirals are reported, not judged: no source here fixes their real values.

## Lessons from building the battery

- **Coordination means the ball.** β = 0 coordination made the P-51's left and right 60° turns differ by 17 %. The slipstream adds 8–10 N of side force at zero sideslip, which loads one turn and unloads the other. Centring the ball made both 17.7°/s, matching g·tanφ/V.
- **Schedule gains and keep integrators in stick units.** A fixed sideslip gain diverged at 54 m/s. Integrators bounded inside a scheduled gain stopped at a third of the stick.
- **Bound α near the limits, couple the approach.** An attitude-holding inverted pilot stalled the P-51's cambered wing negatively. A throttle-for-path approach let the jet's poorly damped phugoid (ζ 0.04 at 1.3 Vs) and its spool lag put it short of the runway. Elevator-for-path with throttle-for-speed lands every aircraft.
- **An exact trim needs a disturbance.** Hands-off flight from an exact trim in calm air shows nothing.
- **Judge validity on what the pilot commanded,** because the recorded command columns include the radio trims.
- **Report the airplane's limits as results:** thrust above weight, a mushing wing, a spiral instead of a spin, no trim at a slow speed, the floor reached in a spiral dive.
- **Reject mislabelled modes.** A "phugoid" faster than the short period is not one.

## Limits

- The battery is pilot-dependent, as stated in the tool README.
- It flies calm air with flaps up and the gear up in the air; landings are flown without brakes.
- The glow Stiks' power-off stalls are unmeasured, and one MAX-61FX knife-edge hold did not converge (+0.6 m/s).
- `modes` relies on the 4×4 projections of `physics/flight_modes.gd`.
- No result here was compared against measured flights of these exact models.
