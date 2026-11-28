# Reproducing the 28 November 2026 audit

The [audit report](../../docs/research/swarm-audit-2026-11-28/README.md) covers OpenRC Simulator source `71306784a250d634854f0c8bab3a927cc46a61b8`. This directory supplies standalone diagnostic witnesses and compact evidence. It adds no production fix and is not automatically enrolled in the app test suite.

## Environment and prerequisites

The recorded runs used Linux x86-64, official Godot `4.8.beta2.official.cafc17a19`, headless, and the GDScript reference backend. The machine exposed nine logical CPUs and no hardware GPU or `/dev/dri`. No enrolled test pool was configured. The lead used the project's permitted local checked runner and owned all Godot launches serially.

A complete checkout is needed. In addition to the app sources and imported resources, the render probes need the root `assets/aircraft/` authoring proofs and the vendored planar-reflection addon. Sparse omissions are setup failures. Do not weaken model contracts to run a partial checkout.

Use the project's existing tool ownership and pool policy if a pool is configured. Obtain the pinned engine through `app/get-godot.sh`, then import resources with checked diagnostics:

```bash
audit_godot="$(app/get-godot.sh)"
python3 tools/godot/run_checked.py --label swarm-import --timeout 600 \
  --out-dir tmp/swarm-audit-import -- \
  "$audit_godot" --headless --path app --audio-driver Dummy --import
python3 research/swarm-audit-2026-11-28/run_probes.py --godot "$audit_godot"
```

The runner requires that exact engine version and writes to a fresh directory under `tmp/`. It runs each probe serially through `tools/godot/run_checked.py`, retaining a process result, engine diagnostics, completion marker and SHA-256 of the log. Specify `--case NAME` for one witness and `--out NEW_DIRECTORY` to choose a new output directory.

This is a **counterexample suite**. On the audited revision, a successful defect probe means the old defect was observed with its controls. After a correct production repair, that witness may deliberately stop matching. Convert the appropriate checks to fixed-behavior assertions when integrating a repair.

## Probe map

| Case | Script | Audit item | Successful baseline meaning |
| --- | --- | --- | --- |
| `box` | [scenery_shell.gd](probes/scenery_shell.gd) | SW-01 | Eleven public-query geometry/control cases match the missed-entry signature. |
| `capsule` | [capsule_seam.gd](probes/capsule_seam.gd) | SW-06 | Both hidden-cap contacts and four controls match. |
| `race` | [race_replay_outbox.gd](probes/race_replay_outbox.gd) | SW-02 | A complete recording refuses its first replay tick after live storage recovery; empty-queue control is exact. |
| `identity` | [unresolved_replay_identity.gd](probes/unresolved_replay_identity.gd) | SW-03 | Real quad/blimp adapters report the unavailable identity as unchanged; known identities and fixed-wing comparator provide controls. |
| `downwash` | [downwash_transport.gd](probes/downwash_transport.gd) | SW-04 | Negative-length custom input grows while stock decays; both complete forty ordinary-input ticks with the reported residual bounds. |
| `fold` | [fold_probe.gd](probes/fold_probe.gd) | SW-05 | Ordering the production callbacks changes the first admitted throttle. |
| `fold-scene` | [fold_scene_probe.gd](probes/fold_scene_probe.gd) | SW-05 | The actual Main scene admits at least one full-throttle tick after the injected accepted fold event and later applies idle. |
| `hud` | [hud_probe.gd](probes/hud_probe.gd) | PERF-05 | Hidden optional widget construction is observed with Off, Pilot and Cockpit controls. |
| `lighting` | [lighting_probe.gd](probes/lighting_probe.gd) | PERF-06 | Active-but-hidden bindings submit changing uniforms; paused and disabled-profile controls do not. |
| `native-refusal` | [prepare_refusal_probe.gd](probes/prepare_refusal_probe.gd) | U-01 | Reference preconditions complete. The outer native result has a separate availability outcome. |

The race and identity scripts require a fresh `--out` directory when invoked directly. The runner supplies one for each. The downwash script writes a PID-named temporary raw JSON file beside itself, loads it through the ordinary production API and removes it afterward. Recordings and logs stay under the selected scratch output.

The native refusal script prints `REFUSAL_NATIVE_UNAVAILABLE` when its real native positive control cannot prepare. The runner records that outcome as `native_unavailable_outer_refusal_unverified`. A completion marker alone does not establish native execution. If a qualified control installs, the diagnostic expects the refused session to remain writable; a nonzero result requires examination of the real native refusal.

## C++ component experiments

Run the two independent baseline/candidate comparisons explicitly:

```bash
python3 research/swarm-audit-2026-11-28/probes/polar_probe.py .
python3 research/swarm-audit-2026-11-28/probes/derivative_probe.py .
```

They copy candidate headers into a temporary directory beside the scripts, compile the unchanged baseline and the candidate, compare outputs and delete temporary executables afterward. They do not patch the source tree. The polar candidate changes branch selection around discarded calculations; the derivative candidate changes ownership transfer from a disposable result.

The recorded compiler was GCC 14.2.0, with C++17, `-O2 -fno-fast-math -ffp-contract=off`. GNU linker wrappers count emitted `pow` and `sin` calls. Allocation counts measure scalar allocation calls and requested bytes in the component boundary. The qualified Linux package instead pins GCC 13.3.0. Neither experiment builds an admitted GDExtension or measures frame time.

The independent verifier rebuilt both comparisons separately and obtained JSON identical to the author's receipts. The derivative fixture covers liquid-turbine stages; the glow sibling is source-reviewed only.

## Physical and mathematical screens

```bash
python3 research/swarm-audit-2026-11-28/probes/coefficient_energy.py .
python3 research/swarm-audit-2026-11-28/probes/verify_tables.py .
```

The first reducer uses floating-point segment calculations. The independently written second reducer uses exact rational decimal values and checks endpoints plus interior stationary minima. Both test `CP − J CT` on intersecting authored forward intervals. Ten direct files comprise six catalog base paths and four synthetic fixtures, with seven distinct table pairs. These screens exclude extrapolation, physical calibration, oblique-force work and blade-element glow installations.

## Evidence index

| File | Contents |
| --- | --- |
| [probe-results.json](evidence/probe-results.json) | Final packaged-probe hashes, checked receipts, exact engine identity and coverage classification |
| [baseline-godot.json](evidence/baseline-godot.json) | Twenty-three unchanged test invocations, result markers and log digests |
| [baseline-python.json](evidence/baseline-python.json) | 407 passed tests and one skip across the two existing tooling suites |
| [native-polar.json](evidence/native-polar.json) | 320 cases, output comparison and libm counters |
| [native-derivative.json](evidence/native-derivative.json) | Eighteen accepted/refused component cases and allocation differences |
| [coefficient-energy.json](evidence/coefficient-energy.json) | Floating-point power/lag screen and known propulsion calculations |
| [exact-tables.json](evidence/exact-tables.json) | Independent exact minima and record classification |
| [github-ci-snapshot.json](evidence/github-ci-snapshot.json) | Existing baseline CI state, source SHA and observation timestamp |
| [probe-development-attempts.json](evidence/probe-development-attempts.json) | Earlier rejected harness/setup attempts; these are not product findings |
| [integrity.json](evidence/integrity.json) | SHA-256 inventory of delivered probes and evidence; excludes itself |

The small `.log` files beside the JSON hold final raw engine output. [fold-scene-initial.log](evidence/fold-scene-initial.log) also preserves the initial full-scene run quoted in the specialist report. Exact scheduling counts can vary; the behavioral predicate is admission of full throttle before the interlock.

Elapsed seconds in runner receipts are execution bookkeeping. They are not comparative performance results. The broader GitHub baseline had six failed jobs at the snapshot; its status must be read separately from the successful local subset.

## Existing baseline commands

The Python suites were run with:

```bash
python3 -m unittest discover -s tools/godtest -p 'test_*.py'
python3 -m unittest discover -s tools/debug -p 'test_*.py'
```

Each engine script named in `baseline-godot.json` ran through the checked runner with a 180-second timeout and required `0 failed` completion text. The exact selected list is retained in that JSON. No result here asserts that every repository test or every release platform passed.
