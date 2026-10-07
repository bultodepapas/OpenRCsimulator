# H15 — Allocation-free attached-flow evaluation (air data, blend weight, global loads)

2026-10-07 · **Status: implemented; bit-exact. Every fixture now meets 500 µs/tick at the median; P-51 trim/stall still exceed it at batch p95 by up to 36 µs.** Main-line ROADMAP Phase H.

## Measure first: why the target changed

H14 proposed step bookkeeping as H15. A step-anatomy profile ([`step_anatomy.gd`](results/step_anatomy.gd)) and per-piece micro-profiles ([`components.gd`](results/components.gd), [`trim_aero.gd`](results/trim_aero.gd)) on the H14 tree showed that this was the wrong target.

| Per tick (µs) | Stik/Extra/Avanti trim–stall | P-51 trim | P-51 stall |
| --- | ---: | ---: | ---: |
| Whole tick | 297–341 | 515 | 579 |
| Aircraft loads (4 calls) | 217–257 | 421 | 471 |
| `_pre_step` (servos, rpm/shaft) | 7–9 | 16 | 18 |
| Rest of `Simulation.step` | 67–72 | 75 | 86 |

The rest of `Simulation.step` is spread over about 20 safety checks of about 1 µs each (`state_is_valid` 1.0, `_array_is_finite` 1.2, `_configuration_is_valid` 1.0, `_refresh_inertia_inverse` 1.3, `_remember_valid_state` 0.8, `RB.derivative` 3.2–3.9 per call). Removing any of them would trade H8 guarantees for single microseconds. `Dynamics` assembly costs only 2–4 µs. An apparent 22 µs gap in the P-51's `Dynamics.loads` turned out to be run-to-run variation (90–107 µs for identical calls).

The largest fleet-wide cost was the attached-flow path, which every aircraft uses in normal flight: `Aero.loads` at trim cost 25–28 µs (`local_flow_weight` about 11, `_global_loads` about 12, of which `coefficients()` was about 7), and `Air.compute` cost 7–11, four times per tick.

## Change

- `Air.compute` rotates the wind with the conjugate quaternion in scalars, in `M.q_rotate`'s order. Before, the calm-air case allocated eight temporary arrays.
- `Aero._global_loads` inlines `coefficients()` (no result `Dictionary`, no rates array) and the CG moment transfer (no `M.v3`/`M.cross`). `coefficients()` stays public and unchanged for trim and linearization.
- `Aero.local_flow_weight` reads its dictionary values once, outside the station and tail loops.

Every product, sum, comparison and transcendental call keeps the oracle's order, and trig still goes through `math3d` (H6 guard passes). `Air.compute`, `_global_loads`, `coefficients()` and their helpers are frozen verbatim from `77cdae9` in [`attached_flow_reference.gd`](../../../../app/tests/attached_flow_reference.gd). `local_flow_weight` keeps H4's vector oracle.

## Proof

- **Byte-exact oracles:** [`test_attached_flow.gd`](../../../../app/tests/test_attached_flow.gd) compares 10,000 air-data and 10,000 global-load cases (2,500 per aircraft) with 0 failures. Cases cover random attitudes, calm and 5,000 windy cases (wind up to 12 m/s, not yet used in flight but needed by the WIND-PLAN), 8,203 beyond stall onset, and 2,000 envelope-free models (the linear branch). Density varies from 0.8 to 1.05 × sea level, with live CG edits. H4's 10,000 local-flow-weight and H12's 10,000 local-load comparisons stay exact.
- **Mutation checks:** on scratch copies, reassociating the body-wind sum in `Air.compute` fails 1,662 comparisons, and reassociating the pitch-coefficient sum fails 2,042.
- **Trajectories:** 64/64 960-tick fingerprints (4 aircraft × 4 regimes × 4 runs) match the Gate P `oracle-1` hashes.
- **Full suite:** `app/test.sh` on the H14+H15 working tree, with its own `XDG_DATA_HOME`, exits 0 (91 sections, 368 s); goldens unchanged; the H4/H12–H15 oracles are all exact. [Summary](results/suite-summary.log).

## Cost on the target

Same host and method as H12–H14; the xvfb capture renderer still used one core. Baseline is the H14 tree: the working tree with `aero.gd` and `air_data.gd` from `77cdae9`. Four runs in sequence: H14, H15, H15, H14. µs/tick, run 1 / run 2; **bold** exceeds 500. Raw: [H14 1](results/h14-1.json), [H15 1](results/h15-1.json), [H15 2](results/h15-2.json), [H14 2](results/h14-2.json).

| Aircraft / fixture | H14 median | H15 median | H14 batch p95 | H15 batch p95 |
| --- | ---: | ---: | ---: | ---: |
| Ugly Stik / trim | 286.7 / 282.5 | 224.6 / 217.5 | 357.8 / 364.8 | 267.4 / 241.2 |
| Ugly Stik / stall | 282.6 / 294.5 | 226.2 / 235.6 | 435.9 / 399.0 | 245.9 / 278.6 |
| Ugly Stik / spin | 236.2 / 243.0 | 204.6 / 203.6 | 344.0 / 264.2 | 227.5 / 245.2 |
| Ugly Stik / ground | 300.3 / 306.9 | 240.3 / 253.6 | 330.1 / 364.7 | 275.6 / 347.5 |
| Extra 300S / trim | 273.6 / 296.0 | 212.7 / 237.2 | 291.6 / 347.6 | 240.3 / 296.7 |
| Extra 300S / stall | 338.9 / 305.9 | 228.9 / 241.4 | 474.9 / 360.6 | 305.7 / 319.4 |
| Extra 300S / spin | 230.1 / 245.1 | 199.9 / 227.8 | 285.6 / 332.8 | 218.1 / 313.9 |
| Extra 300S / ground | 235.7 / 236.0 | 211.6 / 214.7 | 325.4 / 250.0 | 263.5 / 247.7 |
| P-51D / trim | **505.9** / 486.4 | 476.0 / 444.4 | **659.9** / **598.6** | **522.1** / **535.6** |
| P-51D / stall | **522.3** / **512.3** | 457.0 / 461.2 | **800.9** / **599.3** | **518.8** / 484.6 |
| P-51D / spin | 236.1 / 230.5 | 235.6 / 215.9 | 309.7 / 267.6 | 268.9 / 233.6 |
| P-51D / ground | 307.7 / 359.2 | 305.3 / 303.5 | 371.5 / 495.6 | 329.9 / 334.5 |
| Avanti S / trim | 340.5 / 326.5 | 265.9 / 290.3 | 442.2 / 407.6 | 315.9 / 433.3 |
| Avanti S / stall | 309.9 / 382.5 | 282.1 / 285.5 | 347.5 / **516.8** | 307.2 / 349.6 |
| Avanti S / spin | 241.1 / 231.0 | 208.9 / 220.3 | 256.6 / 260.3 | 253.1 / 271.7 |
| Avanti S / ground | 236.6 / 249.9 | 211.4 / 211.9 | 278.9 / 319.4 | 294.9 / 267.6 |

`Aero.loads` at the trim fixtures' initial state: 24.8–29.6 → 17.9–21.6 µs per call.

## Reading

- Normal flight is about 20% cheaper across the fleet. The Ugly Stik, the PT2 product aircraft, now ticks at 218–236 µs in trim and stall: 53–57% headroom.
- **Every fixture now meets 500 µs/tick at the median**, including P-51 powered trim (444–476) and stall (457–461), in pure GDScript.
- **Batch p95:** P-51 trim exceeds the budget in both runs (522, 536) and stall in one (519). This host runs a capture renderer at 100% of one core during every measurement, and two runs of identical code have differed by up to 95 µs/tick (H12), so p95 values within about 40 µs of the budget cannot be resolved here.
- The H12–H15 series (from fe26ef0 to this tree) took P-51 powered stall from 854–940 to 457–461 µs/tick, bit-exact. That beats the native-slipstream route measured on H12 (510–520), which needs a production native dependency and its Windows/macOS build work.

## Next

1. **Gate P decision (owner):** see the ROADMAP Gate P row for the recommendation and its measurement conditions.
2. A remaining bounded candidate, only if a measurement on a quiet target requires it: sharing `thrust_torque`/`wake` between P-51 propulsion and slipstream (about 7 µs per evaluation). It conflicts with the native experiment's adapter hook, so do it only once the native route is retired.
