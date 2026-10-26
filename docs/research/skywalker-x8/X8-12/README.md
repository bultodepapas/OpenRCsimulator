# X8-12: optimization and efficiency round

2026-10-26, Godot 4.8-beta1 on the development VM. Scope: what the X8 integration (X8-02…10) and its hand launch (X8-07) added or exercise: physics tick, data load, launch trim, start-support checks and the model asset. Another session saturated the disk and CPU during part of this round, so timings are compared within one process (interleaved A/B), never across runs.

## Measured

| Item | Result | Action |
| --- | --- | --- |
| Physics tick (session gate + RK4 step, 1200 ticks, medians of 3) | X8 933 µs; Stik 828, Timber 1259, Avanti 1716, P-51 2768 | none: the tailless strip law costs less than the other pack-electric airplane |
| Aircraft data load (validation and derivations) | X8 21 ms; fleet 18–31 ms | none |
| X8 model | 38,504 triangles with generated LODs, 24 primitives, 9 materials; four 2048² textures (Basis Universal), all used (the emission map lights the livery); one GLB per livery like the Corsair | none |
| Electric level trim | X8 and Timber Newton solves end at the 50-iteration cap in 6 of 14 fleet cases | **fixed** (1) |
| Glow level trim | 4 Newton steps, but each residual solves the glow operating point by scanning the rpm envelope (≈130 nodes plus bisection), 7 times per step | **reduced** (2) |
| Start-support menu hints | `runway` and `hand_launch` each loaded and validated the whole data file; preferences did so three times per read, uncached; Home twice per aircraft | **fixed** (3) |

## Changes

1. **Electric trim stops at its residual floor** (`Trim._solve_electric_from`). The electric source equilibrium leaves a residual floor near 1e-10, just above the solver's 1e-10 goal. On the X8, Newton converges quadratically to 1.1e-10 in three steps and then alternates between two states (±1.1e-10, ±1.3e-10) until the cap. The trim was accepted (≤ 1e-8), but 46 extra steps of 7 evaluations each were wasted. Now a step that ends with an accepted residual (≤ 1e-8) that it did not at least halve ends the solve. The non-electric loop is unchanged: no fleet case reaches its cap.
2. **Generic trim reuses the steady rpm across surface probes** (`Trim._rpm_at`, optional `steady_rpm` in `_evaluate`/`_residual`). The steady rpm depends on alpha, throttle and sideslip only. The elevator, aileron and rudder (or bank) Jacobian probes reuse the iterate's value instead of solving the shaft again: 4 shaft solves per Newton step instead of 7. This applies to the generic path what UI-34c-R2 did for the electric one ([evidence](../../menu-investigations/UI-34c-R2/README.md)).
3. **One cached load answers both ground starts** (`FlightSession.ground_start_support`, `AircraftCatalog._ground_starts`). Preferences use the catalog's cached answers.

## Proof

| Check | Result |
| --- | --- |
| Fleet trim parity: 10 flyable airplanes × 7 trims (level at 1.0/1.2/1.5/2.0 start speed, glide, cruise at 50 % and 30 %), digest of the full result | change 1: 61/70 bit-identical. The 9 changed cases are all electric (X8, Timber), and each was stagnating. Largest change: 2.4e-9 relative in a 3.6e-4 rad elevator (8.5e-13 rad); throttle ≤ 8.6e-11 absolute; thrust ≤ 1.1e-9 relative. All still meet the 1e-8 acceptance. Change 2: 70/70 bit-identical to change 1 |
| Interleaved A/B, three level trims (1.0/1.2/1.5 start speed), medians of 3 | X8 853 → 144 ms (5.9×), Timber 894 → 193 ms (4.6×), Extra 300S 2723 → 1702 ms (1.6×), Stik FS64V 3053 → 1856 ms (1.65×) |
| Newton steps | X8 cruise trim 50 → 2, level at start speed 50 → 4; Timber above 1.2 start speed 50 → 5–6 |
| Preferences read for the X8 | first read one data load, repeats 0.4–0.7 ms; before, three uncached loads (≈59 ms) on every read |
| Home first pass over the catalog | one load per aircraft (11, 386 ms once per run) instead of two |
| Suites | golden flights 4/4 unchanged. Pass: `test_trim` 14, `test_trim_integrity` 731, `test_trim_density` 35, `test_cruise_trim` 22, `test_electric_trim_reuse` 18, `test_launch_trim_cache` 47, `test_launch_trim_async` 24, `test_trim_throttle` 47, `test_half_power_start` 74, `test_pilot_trim` 145, `test_x8_flying_wing` 37, `test_hand_launch` 136, the glow suites (`equilibrium` 196, `session` 140, `flight_physics` 110, `oracle` 723, `prepared` 580, `stage_reuse` 2005, `dive_support` 10), electric/battery/Timber session, runway and data suites, `test_aircraft_catalog` 113, `test_start_choice`, `test_ui_runway`, `test_ui_aircraft`, `test_runway_fleet` 136, `test_workshop_starts` 402. `test_ui_home` (45) and `test_ui_aircraft_flow` (helicopter page at 1080p) fail on the Flight page scroll that the merged Flight Statistics button introduces; Home is unchanged here. |

## Not changed (opportunities for their owners)

- **Glow cruise trims still take 4–7 s** (Extra, glow Stiks), because the cruise speed search needs several full trims. Each trim scans the whole rpm envelope for the highest restoring root (`glow/operating_point.gd`). Bracketing near the previous root would change root-selection semantics and result bits, so it belongs to the glow track (NITRO). Home's launch-trim cache hides part of this behind the menu.
- **Electric source floor:** tightening the operating-point root tolerance would lower the floor, but it changes every electric result. The stagnation stop leaves the physics untouched.
