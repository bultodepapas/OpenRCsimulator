# R06 follow-up: stopped wake and idle propeller evidence

This is a read-only follow-up to the experimental Stik wash candidate. It adds no runtime, catalog, or aircraft-data changes. The two boundary discontinuities below are reproduced in the current runtime; the negative-thrust values are source-range-limited model outputs, not a newly established propeller defect.

## Direct production idle results

The runtime probe calls the current `Propulsion.thrust_torque`, `Propulsion.coefficient`, and `Slipstream.wake` functions for the separate Stik candidate at fixed `rho=1.225 kg/m³`, authored idle `2,800 rpm`, diameter `0.3048 m`, and its zero-degree shaft axis. Both advance ratios exceed the last candidate table point, `J=0.788`.

| Airspeed | J | CT raw → used | CP raw → used | T | Q | tail `dv` |
|---:|---:|---:|---:|---:|---:|---:|
| 15 m/s | 1.05455568053993 | −0.0592497616369382 → −0.0592497616369382 | −0.0257854330708661 → 0 | −1.36425674232575 N | 0 N·m | −0.738225092147645 m/s |
| 29 m/s | 2.03880764904387 | −0.265473983609191 → −0.1 | −0.154968503937008 → 0 | −2.30255228820234 N | 0 N·m | −0.631630731946447 m/s |

`P` is also zero in both rows because the production CP floor is zero. At 29 m/s, CT reaches the production floor of −0.1. The candidate table identifies borrowed APC Sport 11×6 data applied to a 12×6 propeller; the extrapolation is well beyond that table’s final `J`. Negative thrust with zero modeled shaft torque does not by itself violate energy conservation: drag work can dissipate in the wake without shaft absorption, and the thrust sign is physically possible. These samples demonstrate high-advance-ratio coefficient extrapolation and floor behavior; they do not prove an incorrect windmilling energy balance. Quantitative validation needs matched propeller measurements over this operating range.

The numerical source-equivalent Python probe independently evaluates the same table and verifies the relevant production-law text. The direct Godot probe calls the production functions themselves. Their values agree to floating-point rounding. See [direct runtime output](idle-propulsion-runtime-numeric-output.json) and [independent equation reproduction with source hashes](stopped-wake-idle-numeric-output.json).

## Two reproduced stopped-wake boundaries

The first edge is the explicit transported-wake fade in [slipstream.gd](../../../../../app/physics/slipstream.gd#L50). With `rpm=0`, held increments `[2,2,2] m/s`, zero crossflow, and `v_x=[−1e−8, 0, +1e−8] m/s`, production returns zero wash on the negative side and finite wash at zero/positive flow. The existing R06 probe records a one-sided force jump of `0.00431066530899893 N` and moment jump of `0.00292460828335164 N·m` in [authority-extended.log](authority-extended.log). This is caused by the `v[0] >= 0` branch at `slipstream.gd:56–57`.

There is a separate current-geometry edge. `drifts` in [slipstream.gd](../../../../../app/physics/slipstream.gd#L80) is gated by `speed > 1e−6` and `wake.vs > 1e−6`; the center shift is then applied at lines 120–121. A direct current-runtime sweep held `rpm=0`, the same transported increments, `v_y=10 m/s`, and sampled `v_x=0.999e−6`, `1.000e−6`, and `1.001e−6 m/s`. The first two stay on the no-drift branch with finite loads; the last enters drift and returns exact zero loads because the instantaneous wake center moves off the modeled tail pieces. Across the 2e−9 m/s outer-sample change, the force delta is `0.0778022629399881 N` and the moment delta is `0.0571768026147101 N·m`. Full values are retained in [geometry-threshold output](stopped-wake-geometry-numeric-output.json).

These cases isolate different predicates: the first crosses axial-velocity sign while the second stays positive and crosses the instantaneous wake-speed gate under large crossflow. Neither result establishes the real wake shape or its reversal behavior.

## State and closure limit

[wash_transport.gd](../../../../../app/physics/wash_transport.gd#L17) stores one axial increment per tail piece and relaxes its source toward zero after the propeller stops or reverse weighting removes the source. Its header explicitly says geometry, reverse occupancy, and wash direction remain instantaneous. In the load consumer, that held increment changes local section velocity, while radius, occupancy, wake center, and drift still come from the current quasi-steady `wake()` calculation. Therefore, removing the sign fade alone may close the first narrow edge but cannot define a continuous transported wake center or a general axial/crossflow reversal law.

A limited consumer experiment could compare each section's load at its local velocity plus the held axial increment with its free-flow load, using fixed, continuous occupancy. That would only test a scalar residual-flow approximation. It would not supply the missing wake-center, radius, direction, or reversal history. A general transport closure needs either those state variables or a separately specified and validated reversal model; do not claim that changing the scalar fade alone solves it.

Future acceptance coverage should sweep stored wake values through zero and both axial-flow signs, then repeat across positive and negative lateral/vertical crossflow and around the current `1e−6` gates. Check per-piece and total force/moment limits as the step shrinks, exact zero wash for zero stored wake at stopped RPM, smooth decay after stop, and checkpoint/replay identity. Establish derivative-based numerical tolerances for a reviewed closure; do not loosen existing oracles or choose a gain from these discontinuity measurements.

## Reproduction and identities

From the repository root:

```powershell
python research/physics-audit-2026-10-14/remediation/stik_wash_candidate/stopped_wake_idle_readonly_probe.py
& '.tools/Godot_v4.7.2-stable_win64_console.exe' --headless --path app --audio-driver Dummy --script 'C:/DEVELOPMENT/OpenRCsimulator/research/physics-audit-2026-10-14/remediation/stik_wash_candidate/idle_propulsion_runtime_readonly_probe.gd'
& '.tools/Godot_v4.7.2-stable_win64_console.exe' --headless --path app --audio-driver Dummy --script 'C:/DEVELOPMENT/OpenRCsimulator/research/physics-audit-2026-10-14/remediation/stik_wash_candidate/stopped_wake_geometry_readonly_probe.gd'
```

The Python probe's `--output` option uses exclusive file creation and refuses to replace an existing path. The three retained outputs above contain the direct production values, the Python reproduction with hashes, and the geometry sweep.

| Input/source | SHA-256 |
|---|---|
| Candidate aircraft v2 | `dfd289f5c8f392fb12e247b1cb14803feafd337339f1baf372154d2c53cedb20` |
| `app/physics/propulsion.gd` | `4368f5636a983757e2587eadf92db07677d6283d0fe2b3cb3a43cb83e37ebff5` |
| `app/physics/slipstream.gd` | `bb810e8e9e93b1b89ad1750cd4db507eb7fe66fad070a5cce51dfd0dce58ab06` |
| `app/physics/wash_transport.gd` | `2814d3d640997d1ac62b9c45c32d4ff632c29f37a113f263a0f2bca9ed86b67d` |
| Idle runtime probe | `290d7d64d2d10ca8d08175b26b305a767422258b1835d23a49f18ff60d1bcd14` |
| Geometry runtime probe | `d7c1b3a57203fb1e572d346ae5e16b44f063bb9364a0a4ccb74593b078e976c1` |
| Python source-equivalent probe | `c3529f8ecca9b6622ba782a558dbcf7638c9878f489ee222618214178384af96` |

