# AS-04: Bounded aircraft lifecycle comparison

2026-10-11 · Prefix: AS-

**Status: Passed. Post-integration lifecycle parity and descriptive timing captured against the frozen pre-migration baseline.**

## Driver

Run `python research/aircraft-standardization/verify.py --candidate .tools/as-integration/app --run-id <unique-id>` from the repository root after the full suite completes. By default it compares the frozen `.tools/as-baseline/app` to the stable integration snapshot, with two alternating process-order rounds and a 180-second limit per process. Use `--candidate app --alternating-runs 1` for a later smoke of the live tree. Retained reports, logs, source manifests and SHA-256 provenance go under `docs/research/aircraft-standardization/AS-04/evidence/<run-id>/`.

The GDScript probe captures loader source numerics and normalized model numerics, verifies session setup preserves the normalized model, and runs all four catalog aircraft plus the four existing synthetic electric fixtures. Each catalog model receives the same two-second manual command schedule except the P-51, which uses one second; electric cases use 0.5 seconds. Every 240 Hz step records packed state, auxiliary, input, continuous and mode arrays as exact bytes. Each case also checks reset to its initial boundary, checkpoint restore and deterministic replay, refusal of a preceding model's checkpoint, and malformed reload rollback. Electric cases must select `coupled-rk4`.

The comparison requires exact normalized numeric-model equality and exact per-tick simulation-array bytes on the same engine and platform. It excludes only the model-root metadata keys `capabilities`, `convention_id` and `data_sha256` from that numeric comparison, retaining them in each case report. It reports raw-source numeric changes (including moved/reference-only values) without treating those paths as runtime mismatches. A comparator self-check injects one model-number and one state-byte change and requires both to be detected.

Each process times seven warm `AircraftData.load_file()` validations per aircraft and each real `Simulation.step()` after discarding the first 20 ticks. Two alternating process rounds aggregate per-aircraft p50/p95 for both measures. These are same-host descriptive observations only; they have no hard deadline or timing-based pass/fail threshold. Source manifests omit runtime `app/captures`, Godot import/cache files and `.uid` files, while retaining code, data, schema and assets.

Existing per-aircraft handling, visual/model verification, ground, crash/audio and full `app/test.sh` checks remain separate; this bounded probe does not claim display-backed animation or physical flight validation.

## Pre-migration capture

The historical `AS04-pre-migration-20261011-r2` capture compared the frozen `.tools/as-baseline/app` to the current working `app` before the schema migration using the original one-pass probe. All eight cases passed: 8/8 normalized numeric models and 8/8 complete recorded flight sequences matched exactly. Reset, own-checkpoint replay, paused restore, and malformed reload rollback passed for all eight; cross-case checkpoint refusal passed for the seven cases with a preceding case. This capture predates the metadata filtering and paired timing extension above, so use it only as a pre-migration parity record.

The baseline and candidate source manifests differed, so this result establishes numeric/runtime parity across the captured snapshots rather than source identity. Both processes used Godot `4.7.2.stable.official.ed1daf0bf`, 240 Hz. Runtime warnings about the electric fixtures' scaled UltraStick25e `Jyy` remain in the retained logs and are existing data-quality warnings, not script errors.

Evidence: [run summary](evidence/AS04-pre-migration-20261011-r2/README.md), [comparison JSON](evidence/AS04-pre-migration-20261011-r2/comparison.json), [baseline log](evidence/AS04-pre-migration-20261011-r2/baseline.log), [candidate log](evidence/AS04-pre-migration-20261011-r2/candidate.log). The adjacent raw probe JSON and source manifests retain every sample and input hash.

| Provenance | SHA-256 |
| --- | --- |
| Frozen baseline app manifest | `ec0f0ca2df96abe701ab290b60ef6cb8eedfee8abb2321fcb46e61e75a1bd421` |
| Historical candidate app manifest | `9987d22cf41c274df17443456e66329752910e58ef01b00f4fff049b36695447` |
| Godot 4.7.2 executable | `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643` |
| AS-04 GDScript probe | `b7499a0c009bb4f12fe18ea01c39363ac25bec32e7690402c241e89c2023e116` |

This pre-migration capture is a reproducibility baseline, not an acceptance result for the migrated contract.

## Post-integration acceptance run

`AS04-v2-integrated-20261011-r2` passed with two alternating process-order rounds. All eight catalog and electric cases had exact normalized numeric-model equality and exact per-tick state, auxiliary, input, continuous and mode-array bytes. Reset, checkpoint restore/replay, malformed reload rollback and the seven applicable cross-aircraft checkpoint refusals passed. All four processes exited cleanly with no engine errors; baseline and candidate manifests were stable across both rounds.

The comparator's deliberate model-value/state-byte mutation self-check passed. Raw source numerics differ in 15–17 reported paths per case but do not change the normalized model or flight trace. Differences include moving `CLadot` to `aero.reference_coefficients`, explicit zero `max_steering` entries, explicit 15 m/s Stik-derived starts, capabilities metadata and inventory size values. Review the exact changed paths and values in `comparison.json`; raw input hashes and metadata are provenance, not parity gates.

The first attempt, `AS04-v2-integrated-20261011-r1`, is retained as superseded provenance evidence. `tests/test_aircraft_render_contract.gd` appeared in the candidate while that run was executing, so its source-manifest gate failed even though all eight model and trace comparisons matched. The successful r2 run began with the test present and kept a stable manifest.

The timings aggregate seven warm aircraft-data loads and steady simulation ticks from each of two runs per app. Times are microseconds, shown as p50/p95. The engine is Godot `4.7.2-stable (official)` at 240 Hz. These same-host measurements are descriptive and have no performance threshold.

| Aircraft | Load p50/p95 baseline → candidate | Tick p50/p95 baseline → candidate |
| --- | ---: | ---: |
| Extra 300S | 16,242/19,407 → 18,168/20,736 | 269/402 → 336/409 |
| Ugly Stik | 15,023/17,410 → 19,052/21,210 | 398/524 → 413/539 |
| P-51D Mustang | 16,200/18,751 → 21,979/27,399 | 469/671 → 558/701 |
| Avanti S | 13,710/17,431 → 17,802/23,429 | 349/554 → 336/519 |
| Electric 4S | 14,305/16,615 → 16,154/21,459 | 794/950 → 584/911 |
| Electric 4S battery | 16,004/18,608 → 16,493/26,313 | 621/859 → 875/1,065 |
| Electric 6S | 14,851/17,130 → 18,318/21,403 | 774/1,054 → 753/929 |
| Electric 6S battery | 11,555/16,201 → 19,023/21,928 | 674/969 → 833/1,054 |

A follow-up same-process comparison isolates v2 sessions against explicit `AircraftData.legacy_v1_input` clones on identical physics. All eight models and all six 120-tick paired batches per aircraft matched their exact simulation byte boundaries. The P-51's initial paired p50 v2/legacy ratio was 1.202, with a six-pair range of 0.822–1.420 while the WSL Godot suite and native Godot processes were active. A quieter P-51-only 24-pair repeat yielded p50 ratio 0.986 (range 0.754–1.134) and p95 ratio 0.972 (range 0.690–1.369); it did not reproduce a persistent slowdown, but its spread remains far wider than 5%. These timings are inconclusive: they establish neither a P-51 regression nor that the ≤5% target is met. See the [paired metadata benchmark report](paired-metadata-benchmark.md), [all-aircraft r1 evidence](evidence/AS04-paired-metadata-20261011-r1/README.md) and [P-51-only 24-pair evidence](evidence/AS04-paired-p51-24-20261011-r1/README.md).

Evidence: [successful run summary](evidence/AS04-v2-integrated-20261011-r2/README.md), [comparison and timings](evidence/AS04-v2-integrated-20261011-r2/comparison.json), [successful candidate log](evidence/AS04-v2-integrated-20261011-r2/candidate_r1.log), [superseded provenance-gate run](evidence/AS04-v2-integrated-20261011-r1/README.md).
