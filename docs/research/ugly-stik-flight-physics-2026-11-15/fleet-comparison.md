# Fleet comparison from static and selected dynamic cards

**Source identity.** `ft-card-v5` run at commit `ad21070798bfb9658785576a9c0b8bfc9a71fc7f`, Godot `4.8.beta2.official.cafc17a19`, using the catalog aircraft data. `evidence/fleet-static/run.json` records 11 aircraft; each returned exit 0, zero script errors, three valid requested results, matching input hashes and no missing or unexpected cases. The tests were `trim_sweep`, `modes` and `aero_sweep`. The run record identifies modified flight-test harness files; this is a test-harness candidate on the stated baseline, not a claim that the entire worktree was clean. The lead reports the card registry was hardened while all 40 registered callables and their order were preserved. Each per-aircraft `profile.json` and `run.log` supplies the detailed inputs and outputs.

**What these results mean.** These are simulated equilibrium, static-load and linearized-model results; no dynamic stall, maximum-speed, rollout, spin, climb, pilot handling or physical measurement was performed by this card. A `valid` modes result means it contains the start-speed mode row, not that every requested mode was identified. The 6S Stik, Turbo Lumber and MoonRunner catalog inputs here are their ideal fixed-voltage versions; ordinary 6S Stik flight defaults to its finite-pack version. A separate finite-pack result is required to assess sag and depletion.

## Geometry, trim, and linear modes at each aircraft's own start speed

The first table reports the model inventory mass and `m/S` at the card's modeled initial state. `α` and throttle are the solved level-trim values at the specified start speed, not a recorded flight. Throttles are different engine/ESC commands and should not be compared as equivalent power. Start speeds differ, so the mode columns are **not** a matched-speed comparison.

| Aircraft | Mass kg | Span m | m/S kg/m² | Start m/s | Trim α ° | Trim throttle | Short period Hz / ζ | Phugoid s / ζ | Dutch ζ | Spiral time |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Basic Stik, fixed half fuel | 2.879 | 1.524 | 6.20 | 15.0 | 4.20 | 0.283 | 1.332 / 0.944 | 9.90 / 0.246 | 0.324 | halves 17.9 s |
| Stik 61FX, finite fuel | 3.029 | 1.524 | 6.52 | 20.0 | 1.96 | 0.200 | 1.788 / 0.882 | 12.35 / 0.626 | 0.311 | halves 18.7 s |
| Stik 55AX, finite fuel | 2.766 | 1.524 | 5.96 | 20.0 | 1.67 | 0.224 | 2.208 / 0.908 | 12.69 / 0.638 | 0.327 | halves 19.4 s |
| Stik FS-64V, finite fuel | 2.626 | 1.524 | 5.65 | 20.0 | 1.51 | 0.368 | 0.070 / 1.378* | unavailable* | 0.341 | halves 15.8 s |
| Stik electric 6S, **ideal bus** | 2.600 | 1.524 | 5.60 | 15.0 | 3.64 | 0.411 | 2.800 / 0.854 | 12.34 / 0.368 | 0.359 | halves 12.2 s |
| Extra 300S .60 | 3.820 | 1.626 | 7.96 | 22.0 | 3.62 | 0.244 | 2.421 / 0.827 | 11.67 / 0.294 | 0.232 | doubles 9.3 s |
| P-51D | 21.500 | 2.820 | 15.66 | 25.0 | 4.23 | 0.101 | 0.804 / 0.926 | 10.80 / 0.192 | 0.280 | halves 66.2 s |
| F4U Corsair | 21.500 | 2.778 | 14.92 | 23.0 | 3.68 | 0.075 | 1.027 / 0.899 | 12.66 / 0.226 | 0.184 | halves 14.6 s |
| Vantage / Avanti | 11.439 | 2.000 | 16.29 | 29.0 | 4.50 | 0.091 | 1.057 / 0.725 | 16.12 / 0.095 | 0.176 | doubles 20.2 s |
| Turbo Lumber, **ideal bus** | 2.190 | 1.555 | 6.70 | 13.10 | 4.32 | 0.410 | 1.755 / 0.625 | 6.73 / 0.133 | 0.197 | doubles 6.2 s |
| MoonRunner X99, **ideal bus** | 3.132 | 2.100 | 4.18 | 12.77 | 3.33 | 0.496 | 1.165 / 0.711 | 7.32 / 0.173 | 0.419 | halves 1.4 s |

`*` The FS-64V row's apparent slow, overdamped “short period” and absent phugoid require root-classification investigation; do not interpret 0.070 Hz as an established short-period oscillation. The card explicitly flags its longitudinal roots as not separable. “Halves/doubles” denotes the sign of the **linearized spiral estimate**, not an assertion that the real model or aircraft has demonstrated that behavior in flight.

[`app/physics/flight_modes.gd:1-5,23-57`](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/physics/flight_modes.gd#L1-L5) linearizes the simulated equations around level trim with controls and engine frozen, includes the modeled downwash lag when present, and estimates modes using longitudinal and lateral diagonal-block projections. It omits cross-axis coupling from those modal estimates. The chosen frequencies are **undamped natural frequencies** derived from eigenvalues, while damping ratios are model quantities. These modes do not include a changing throttle, a fuel/pack transient or the complete coupled response; uncertainty in the modeled mass, inertia, controls and derivatives transfers directly into them.

## A fairer Stik-family trim comparison at 15 m/s

The same grid contains 15 m/s for all five configurations; comparing it avoids conflating the electric/basic 15 m/s start with the glow technical models' 20 m/s start. It still mixes different mass, CG, engine law, propeller and power-control scale.

| Configuration | Trim α ° | Pitch command | Throttle command | RPM at trim |
| --- | ---: | ---: | ---: | ---: |
| Basic Stik | 4.20 | 0.138 | 0.283 | 5,159 |
| 61FX | 4.51 | 0.201 | 0.099 | 7,024 |
| 55AX | 4.01 | 0.191 | 0.115 | 6,144 |
| FS-64V | 3.72 | 0.143 | 0.189 | 6,505 |
| 6S, ideal fixed voltage | 3.64 | 0.070 | 0.411 | 4,911 |

These are predicted equilibria, not measured aircraft performance or a power/efficiency ranking. The basic Stik uses an explicitly prescribed RPM target, whereas finite-glow installations use a shaft model and the electric model uses a motor/propeller balance. The different axes and CGs also affect the necessary trim; do not tune throttle or control settings to force the rows to agree.

## Separate scripted dynamic cards

A later run in `evidence/dynamic/` completed eight selected cases for each of the basic Stik, ideal-bus 6S Stik, 61FX and Extra; the separate `evidence/electric-pack/` run completed the same eight using `app/data/aircraft/battery/stik_electric_6s_pack.json`. Both `run.json` receipts record 8/8 valid cases for each requested aircraft, matching input hashes, exit 0, zero script errors and no missing/extra cases. This does **not** mean that all possible maneuvers were flown or that the simulated values match a real aircraft. Per-case definitions and termination criteria are in `research/flight-test/flight_test.gd:552-625,628-689,760-809,1250-1283` and `research/flight-test/card_power.gd:146-219`; Full CSV traces were produced under each original run's aircraft directory. The published evidence retains their hashes and selected raw-row extracts in [trace observations](evidence/trace-observations.json); the [verification commands](verification.md) regenerate the complete traces.

| Modeled configuration | Power-off break speed m/s | Break α ° / bank in first second | Controlled full-throttle level speed m/s | +10 m/s s | Peak right / left roll at start °/s | 30 s disturbed heading / height change |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Basic Stik, start 15 m/s | 9.67 | 18.3 / −80.5° | 32.76 | 1.53 | 186.6 / 177.3 | +68.5° / −0.33 m |
| 6S ideal bus, start 15 m/s | 9.06 | 19.0 / +38.6° | 33.89 | 1.38 | 178.8 / 172.2 | +35.0° / +1.20 m |
| 6S finite pack, start 15 m/s | 9.06 | 19.0 / +39.5° | 35.39 | 1.24 | 178.8 / 172.3 | +37.7° / +0.78 m |
| 61FX, start 20 m/s | 9.98 | 18.6 / −90.2° | 38.11 | 2.02 | 192.3 / 189.5 | +111.4° / −5.54 m |
| Extra, start 22 m/s | 11.12 | 22.2 / −11.4° | 41.21 | 3.71 | 305.7 / 307.6 | +410.3° / −75.64 m |

The break is the card's scripted altitude-hold deceleration and break criterion, followed by powered recovery; the displayed bank is the signed peak during the first second after break, not necessarily bank at the break. Speed is a simulated test result, not a real-world measurement or an analytic CLmax estimate. The full-throttle test holds altitude/bank and stops when speed is sufficiently settled; the maximum is the controlled model result for this flight and pack state. The roll inputs are full aileron with other controls at trim; the 30 s case begins at 400 m after small elevator and aileron pulses. Extra's reported 410.3° heading change and 75.64 m height loss occurred in that model test; its projected spiral mode also grows, but neither result proves the real Extra is unstable. Full paths, controls, saturation and CG should be assessed before assigning a cause. Different start speeds and powertrains preclude treating this table as a direct aircraft ranking.

### Ideal versus finite-pack 6S at matched nominal start

| Scripted metric | 22.2 V ideal bus | Estimated finite pack |
| --- | ---: | ---: |
| Start-speed trim command | 0.411 | 0.367 |
| Power-off break speed m/s | 9.06 | 9.06 |
| Full-throttle controlled level speed m/s | 33.89 | 35.39 |
| 10–90% spool-up s | 0.300 | 0.579 |
| Full-throttle test time to gain 10 m/s s | 1.38 | 1.24 |
| Height gain 10 s after 50% throttle step m | 17.0 | 28.8 |
| 100% step orientation-threshold time from test start s | 7.26 | 6.85 |

The pack begins at modeled SOC 1.0 ([`app/data/aircraft/battery/stik_electric_6s_pack.json:1535-1540`](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/data/aircraft/battery/stik_electric_6s_pack.json#L1535-L1540)); it is a class-estimated pack, not measured Gens ace characterization. In the full-throttle level-speed traces at t=2 s, the ideal bus is 22.2 V while the pack is approximately 23.34 V (SOC 0.9927). The two runs are therefore **not matched-voltage comparisons**, and the 1.50 m/s simulated difference cannot be interpreted as a universal advantage or a hardware estimate. Each spool-up is the card's 10–90% RPM change between its observed pre/post endpoints while the aircraft accelerates; it is not a fixed-inflow motor bench test. The two-mode power-step commands also differ relative to the trim duty.

The power-step card leaves elevator at its trim while a scripted controller actively commands bank and yaw. It labels an event “inverted” as soon as the earth-up direction in body axes crosses a threshold (`research/flight-test/card_power.gd:160-174`). At the closest retained t=6.85 s pack sample, pitch is about 88.35°, roll −88.99° and the bank controller has saturated at +1.0; the ideal run is similarly near vertical with saturated bank command near its t=7.26 s event. This is a crossing of the script's **orientation threshold**, not proof of sustained inverted flight or an isolated longitudinal instability. In the pack run the 75% step also crosses the criterion at 10.75 s. Investigate actual commanded and achieved surfaces, quaternion attitude, force contributions and saturation with the same input tape before judging power-on feel or changing derivatives.

## Findings that need follow-up

1. **61FX modeled trim enters the declared propeller overspeed region.** In the technical 61FX card, the 35–38 m/s solutions report 16,261–17,669 rpm. Its declared APC 12×6 propeller recommendation is 15,833 rpm ([`app/data/glow/stik_61fx_2t.json:154-159`](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/data/glow/stik_61fx_2t.json#L154-L159)); at 38 m/s the computed value is 11.6% above it. The separate dynamic level-speed case reaches 17,720 rpm at 38.11 m/s, approximately 11.9% above that prop recommendation. The modeled engine's recommended maximum is 17,000 rpm ([`app/data/glow/os_max_61fx_installed_candidate.json:427-431`](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/data/glow/os_max_61fx_installed_candidate.json#L427-L431)). This is a model-predicted equilibrium, not measured overspeed or a real-aircraft outcome. The code already computes an `above_recommended_rpm` flag and the HUD can display it ([`app/physics/glow/flight.gd:873-874`](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/physics/glow/flight.gd#L873-L874); [`app/main.gd:1740-1741`](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/main.gd#L1740-L1741)), so a missing warning has not been established. Verify the actual session/HUD flag at a controlled simulated operating point, validate prop/engine/RPM data with a matched installation and separately decide how the simulator should represent a recommended operating limit. Do not infer that a physical propeller failed or automatically clamp shaft RPM.

2. **The FS-64V modal label is unresolved, and several high-speed rows have no distinct phugoid.** At its 20 m/s start, the FS-64V card reports a nominal 0.070 Hz, ζ=1.378 “short period,” while it suppresses the phugoid because the longitudinal roots do not separate under the card's heuristic. The same note occurs for this model at the high-speed sample and for 61FX, 55AX and ideal 6S at their high-speed samples. Those cards remain marked valid because the start row exists. `research/flight-test/flight_test.gd:1144-1167` performs the suppression; [`app/physics/flight_modes.gd:70-99`](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/physics/flight_modes.gd#L70-L99) classifies projected roots, including an overdamped branch. Inspect eigenvalues, eigenvectors, lag-root association, a speed sweep and the full coupled matrix before making a handling or instability claim. Independently verify trim and recorded control/state response.

3. **Stik neutral-control side force changes substantially between model regimes.** At β=20° and each model's trim α, the basic Stik's body-axis `Fy/(qS)` is −0.1748 in the global coefficient oracle and −0.0550 in the local and blended production law (local weight 1). The other Stiks give approximately −0.1736 to −0.1744 global and −0.0551 to −0.0553 production. Extra, which declares body-side terms, gives −0.1678 global versus −0.1437 production in its own state. These are model diagnostics with different start speeds/α and **neutral controls**, not measurements or proof that any particular law is correct. Stik source data omits the optional body-side terms ([`app/data/aircraft/jensen_ugly_stik_60.json:1342-1474`](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/data/aircraft/jensen_ugly_stik_60.json#L1342-L1474); [`app/physics/aero.gd:681-693`](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/physics/aero.gd#L681-L693)), and the neutral-control local model becomes fully active by the sampled β=15° point. Obtain aircraft-specific side-force/yaw measurements and compare control-applied flight/replay, rather than forcing the local law to match a borrowed donor oracle.

4. **Nominal trim boundaries need diagnosis before calling them speed limits.** The static sweep advances on a grid of start-speed multiples. It excludes samples below `1.05 ×` an analytic stall estimate, and stops at the first unsuccessful level trim or throttle above 1 (`research/flight-test/flight_test.gd:509-541`). It does not establish a maximum level speed or a minimum stall speed. For example the FS-64V last solved 27 m/s at throttle 0.845 and the next 28 m/s point was not solved; the card does not identify whether solver convergence, a modeled constraint, or the physical balance caused that boundary. Inspect the detailed trim failure and try independent/continuation seeds before interpreting it.

5. **Do not interpret the card's named auxiliary speeds as measured extremes.** Because this run did not execute `stall_power_off` or `vmax`, `1.3Vs` in the modes card means 1.3 times the analytical estimate `sqrt(2mg/(ρ S CLmax))`; `0.8Vmax` means 0.8 times the first failed trim-sweep point, which may itself reflect a solver failure. For the basic Stik those mode inputs were 12.35 and 25.8 m/s, respectively; neither is an observed stall or maximum speed. The neutral-control side-force “knife-edge” ratio uses this same fallback speed (`flight_test.gd:1216-1230`) and is not a controlled knife-edge flight. A completed dynamic card can supply model trajectory evidence, with its own validity and crash/termination checks; neither it nor a solver result alone establishes physical realism.

The independent physics audit contains the separate power-off propeller, missing Stik propwash, induced-strip weighting, estimated mass/CG/inertia, and post-stall findings. The static fleet table reinforces why a source-matched, same-input replay and real hardware measurements are needed before ranking aircraft realism or changing coefficients.
