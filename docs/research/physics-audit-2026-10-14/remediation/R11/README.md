# VAL-AUD-R11 integration evidence

2026-10-14. This qualifies the implemented [remediation slices](../README.md), not the complete plan or physical aircraft. Original R00 recordings and the original audit remain unchanged.

## Stable recordings and control scenarios

[`final-scenarios-03/verification.json`](final-scenarios-03/verification.json) passes with no source drift. It ran against an isolated native Windows app snapshot with Godot 4.7.2.stable.official.ed1daf0bf. The retained `solver-source.tar.gz` and source manifest identify that snapshot; its solver SHA-256 is `3877ec2dab0d72194f979ad85c396a2ecc40aa8388cd31b252ea99dd10584123`.

The R02 wake changes meaning from dimensionless coefficient to velocity. The old checkpoint is deliberately incompatible. [`compare_scenario.gd`](../../../../../research/physics-audit-2026-10-14/remediation/compare_scenario.gd) instead preserves each baseline's accepted aircraft snapshot, body state, actual RPM/servos and post-conditioning command tape, then uses the new law's fresh settled wake. Both scenarios run all 1,440 ticks (six seconds at 240 Hz), produce 1,441 rows, and record `complete=true`, `solver_changed=true`. These are explicitly initialized new-law scenarios, not exact historical replay or arbitrary mid-flight migration.

Each new recording then passes its own **byte-exact replay** under that snapshot: `complete=true`, `mode=exact`, `solver_changed=false`, 1,441 rows. The historical R00 recordings separately passed exact replay with their original source. Aircraft data is frozen from R00 for the law comparison; concurrent catalog edits are not folded into that comparison.

| Same-input old/new law comparison | Stik | Jet |
| --- | ---: | ---: |
| Maximum position component difference | 0.490442 m | 0.237006 m |
| Maximum body velocity component difference | 0.027500 m/s | 0.052116 m/s |
| Maximum angular-rate component difference | 0.019697 rad/s | 0.009508 rad/s |
| Maximum quaternion attitude angle | 0.014834 rad | 0.003023 rad |

These are model differences, not accuracy bounds or acceptance tolerances. Component maxima are not vector norms. Both first diverge at tick 1, as expected after the law change. Complete reports: [Stik scenario](final-scenarios-03/stik/scenario.json), [Stik differences](final-scenarios-03/stik/comparison.json), [Stik exact replay](final-scenarios-03/stik/exact/replay.json), [Jet scenario](final-scenarios-03/jet/scenario.json), [Jet differences](final-scenarios-03/jet/comparison.json), [Jet exact replay](final-scenarios-03/jet/exact/replay.json).

The original actual-session control probe also completes **28/28 finite, fault-free runs** using the snapshot's current catalog: Stik/Jet, normal/full authority, neutral and positive/negative roll, pitch and yaw. Each six-second run starts at 300 m, applies its 0.5-second pulse at 0.5 seconds, then releases it. [Raw session results](final-scenarios-03/catalog-pulses/session-results.json). This establishes bounded numerical operation in those scenarios; it does not establish measured handling quality.

## Intentional reference changes

Four golden flights were re-recorded only after the section-force/wake checks and their independent comparisons passed. The four original fixtures are retained in [`final-scenarios-01/previous-goldens/`](final-scenarios-01/previous-goldens/). [`golden-changes.json`](final-scenarios-01/golden-changes.json) records both hashes, unchanged input tapes, and the R02 reason for each change. Tick counts remain 600, 720, 720 and 1,200. Before refresh, the old fixtures fail under the deliberately changed law; the glide body remains within about 6e-12 m but its auxiliary wake units change. [Before-refresh output](golden-before-refresh/golden.log). The refreshed golden test passes 4/4; this is a regression reference, not the independent proof of the new equations.

Only three modal band centers changed. Their existing 3% tolerance was not widened. An independently composed derivative/Jacobian and SciPy eigensolve establish the new references, including a finite-difference step sweep. The 42 mode checks pass, including the existing nonlinear lag-response test. [Mode evidence and old/new controls](../R02-modes/README.md).

Failed runs are retained honestly. `final-scenarios-01` refreshed the goldens successfully but its recording verification failed because concurrent ground-vehicle source changed the solver fingerprint between recording and exact replay. `final-scenarios-02` passed the isolated Stik record/replay, then stopped on a comparison-runner path error. Neither is a passing integration gate. `final-scenarios-03` corrects the path and uses an immutable source snapshot; it is the accepted recording run.

## Remaining release gates

The canonical Linux `app/test.sh` run and target-machine timing evidence are recorded here when complete. Native focused checks and scenario recordings alone do not close those gates. Fresh export/package smoke and the unimplemented R05-B/R06-B/C/R07/R08 compositions remain separate work; there is no catalog promotion or release claim.

Reproduce the recording batch with [`final_scenarios.py`](../../../../../research/physics-audit-2026-10-14/remediation/final_scenarios.py), a matching immutable `--app`, the pinned `--godot`, and a fresh `--out`. Do not use `--refresh-goldens` for routine verification.
