# R11: integration of regenerated Stik rate derivatives

2026-10-15. Software integration of the [D11g regeneration](../damping-lag-diagnostic/README.md). This does not resolve the independent yaw-damping or powered-wing/tail questions in R02, establish physical accuracy, or close the canonical full-suite gate.

## Exact change and scope

The [root structural comparison](data-overlay.json) independently verifies that only `value` and `source` changed for `Cmq`, `CLq`, and `Cnr` in the Stik and its five generated Glow variants. Four Workshop descriptors change only their base hash. [Previous inputs](previous/) retain the original bytes. The source pipeline, full-precision derivation, input/source identity checks, step refinement, and negative controls belong to the [derivation evidence](../damping-lag-diagnostic/d11g-repair/).

The accepted rounded ARP derivatives are `Cmq=-8.009`, `CLq=2.003`, and `Cnr=-0.1335`. They reconcile the attached model's stored derivatives with the current local law; they are explicitly model-derived. No flight-force equation, aircraft geometry, test tolerance, or pilot input was adjusted in this integration.

The physical app copy was `tmp/physics-audit-keyboard-fixture/app`, based on the previously verified R11 snapshot. Its per-run manifests identify the actual source and data. The P-51 file is the exact newer Linux candidate version (`3ef8334f…553ff2`), including ground effect. It must not be confused with the older Windows-only configuration. [Authoring-source context](authoring-source-context.json) identifies the 13 required sibling model-binding sources copied into the isolated workspace.

## Independently checked mode reference

The original 25 m/s spiral band center, `0.02751213 s^-1`, fails after regeneration: the new root is about 4.74% higher, outside the unchanged 3% tolerance. The other 41 assertions pass in the [old-band control](focused-before-reference-update/test_modes.gd.log).

The [reproduction runner](../../../../../../research/physics-audit-2026-10-14/remediation/run_mode_reference.py) uses the preserved manually composed derivative/Jacobian and a separately implemented SciPy eigensolve. It bypasses production mode assembly/eigenvalue classification, while deliberately sharing the actual Air/Aero/Propulsion/RigidBody force kernels. Thus it checks the modal machinery against the implemented equations; it is not an independent aerodynamic validation.

| Jacobian perturbation | 25 m/s spiral root, s^-1 |
| --- | ---: |
| `1e-5` | 0.028815463655672037 |
| `1e-6` | 0.028815463661805575 |
| `1e-7` | 0.028815463685604975 |

The manual/production Jacobian infinity-norm difference is zero at 10, 15 and 25 m/s; modal metric differences are below `1.3e-13`. [Matrices, roots, toolchain pins and source identities](independent-modes/mode-reference.json) accompany the [raw output](independent-modes/probe.log). Only the 25 m/s spiral center changes to `0.02881546`; its 3% tolerance is unchanged. The [updated suite](modes-catalog-after/test_modes.gd.log) passes 42/42, including the existing nonlinear lag-response comparison.

## Same-input flight comparison and exact replay

The [first complete flight batch](flights/verification.json) has no GDScript/data-JSON source drift. It uses the pinned Windows Godot SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643` and solver fingerprint `85d0b19b66d118bf4a735e253b4f2d5c0d1d73a7a35f11f6e146dfc16b207a1b`.

For each aircraft, the previous normal-rate positive-yaw `.orfl` first replays byte-exactly. The candidate then uses that same initial body/internal state and post-conditioning input tape with the current aircraft JSON. Every report is complete, with 1,441 rows and `solver_changed=false`; candidate mode is explicitly `candidate`, not exact equivalence. The Stik input changes from `5fe8ece9…1ee9b6` to `bdcf4d64…50f723`. The Jet input is unchanged.

| Maximum difference over the six-second yaw tape | Stik | Jet |
| --- | ---: | ---: |
| Position component | 0.119668225 m | 0 m |
| Body velocity component | 0.013444949 m/s | 0 m/s |
| Angular-rate component | 0.006099138 rad/s | 0 rad/s |
| Quaternion attitude angle | 0.002648361 rad | 0 rad |

These are model-change measurements, not error bounds. [Stik comparison](flights/stik-comparison.json), [Jet comparison](flights/jet-comparison.json). The batch also completes all 28 current-catalog neutral/positive/negative roll, pitch and yaw cases at normal/full rates, and separately replays each new normal-yaw recording exactly: [current sessions](flights/catalog-pulses/session-results.json), [Stik own exact replay](flights/stik-current-exact/replay.json), [Jet own exact replay](flights/jet-current-exact/replay.json).

That first batch directly compares only the yaw tape; its other 26 cases are current-catalog operation checks. Its manifest hashes GDScript/data JSON, the runner and engine, but omits external probe/comparer and `project.godot` hashes. The subsequent [all-axis comparison](all-axis-flights/README.md) closes both evidence gaps without modifying historical receipts: 28 baseline tapes, 28 exact replays, 28 same-tape data candidates and 28 aligned CSV comparisons all complete. Before/after hashes include the project settings and external harness inputs, with no drift. All 14 Jet comparisons are exactly zero; both signs and both rate profiles exercise Stik pitch, roll and yaw sensitivity. The largest position-component difference is 0.4977 m in the full-rate pitch cases, not a physical error bound.

Root review separately checked all 40,348 compared rows: the complete case matrix, tape hashes against both replay reports, identical initial bodies and time/control sequences, finite metrics, independently recomputed position/velocity/rate component maxima, and zero Jet controls. The accepted [all-axis verification](all-axis-flights/verification.json) SHA-256 is `4a5bc52f8028b1f67ff469c23f2501472ab806a48119578ebc5644fd1c69504e`.

## Intentional golden refresh

The [pre-refresh test](focused-before-reference-update/test_golden.gd.log) fails the roll, pull/throttle and rudder goldens after the intentional derivative-data change. The glide already passes. The [isolated refresh](golden-refresh/verification.json) calls the original `record_golden.gd` and independently checks unchanged input tapes, replay policy, record layout and checkpoint coverage. Original files remain in [golden-refresh/previous](golden-refresh/previous/).

Only the three affected records are integrated, as recorded by [integration.json](golden-refresh/integration.json). Tick counts remain 600/720/720; the original 1,200-tick glide is retained byte-for-byte because its differences are only roundoff-scale. The exact integrated combination passes [4/4 golden replays](integrated-goldens/test_golden.gd.log). No tolerance was widened. Generated build labels inherit the enclosing repository's Git metadata; the full source/configuration receipts, rather than that label alone, identify the isolated app.

This refresh establishes regression references for an intentional data change. It is not evidence that R02's unresolved physical closure is correct. Reproduce only an intentional refresh with [refresh_rate_reference_goldens.py](../../../../../../research/physics-audit-2026-10-14/remediation/refresh_rate_reference_goldens.py) in a physical app copy; the helper refuses the working app and hardlinked golden outputs.

## Failed attempts and remaining gates

The first isolated catalog run lacked required sibling authoring JSON files and timed out after reporting that missing context. It remains in [focused-before-reference-update](focused-before-reference-update/); it is not an aerodynamic regression. After restoring the exact source context, [catalog validation](modes-catalog-after/test_aircraft_catalog.gd.log) passes 98/98. Damping-regime checks pass 20/20 in the pre-reference batch.

The original whole-range yaw criterion remains a separate R02 integration gate, alongside the new algebraic derivative check. The [powered-tail counterexample](../washed-downwash-diagnostic/README.md) also remains open. Neither focused integration nor new goldens can replace the outstanding canonical Linux suite, package smoke, target-machine cost and physical measurement gates.
