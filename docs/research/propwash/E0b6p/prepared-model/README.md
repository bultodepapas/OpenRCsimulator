# E0b6p — Prepare native model data once

2026-10-08 · **Status: correctness and paired performance experiment complete; research candidate retained. E0b6p and Gate P remain open.**

## Result and decision

An owned, explicitly prepared native model removes repeated dictionary decoding without changing tested loads or trajectories. Both runs show positive paired median savings in every active swirling regime. Retain this candidate for further performance work, but do not integrate it into production: the tested active swirling medians still exceed 500 µs/tick, runtime model ownership/reload wiring is not implemented, and native platform acceptance remains open. Production continues to use GDScript.

This changes neither force equations nor aircraft parameters. The original decoder and numerical kernel are reused unchanged; static and dynamic kernel validation still run. The earlier stage-local thrust/torque-sharing candidate is **not** included.

## Measurements

Godot 4.7.2, Linux x86_64, Intel i5-10500 shared host, locked g++ 13.3.0. Fifteen alternating pairs measure 64 changing-input Dynamics calls; nine alternating pairs measure 24-tick flight batches. Preparation, setup/trim, comparison and trajectory hashing are excluded. These are batch-average timings, not individual-tick percentiles or quiet-target acceptance. Positive paired savings mean the candidate was faster.

| Smooth wake, swirl 0.4 | Direct saving, run 1 / 2 (µs/call) | Whole-tick saving, run 1 / 2 (µs/tick) | Candidate tick, run 1 / 2 (µs) |
| --- | ---: | ---: | ---: |
| Forward | 10.67 / 14.48 | 129.96 / 17.71 | 571.9 / 577.5 |
| Stall | 17.09 / 12.44 | 48.67 / 82.46 | 607.6 / 577.7 |
| Static | 16.75 / 16.59 | 80.04 / 80.29 | 534.0 / 522.9 |
| Powered spin | 11.45 / 14.33 | 64.71 / 52.75 | 614.0 / 515.0 |
| Reverse fade | 14.88 / 13.33 | 63.75 / 57.75 | 527.3 / 569.2 |
| Reverse cutoff | -1.94 / -1.44 | -8.17 / -45.00 | 388.5 / 397.2 |

Active swirling candidate medians are **515–614 µs/tick**. Direct savings of about **11–17 µs/call** agree with the previous decoder attribution. Whole-tick savings range from 18 to 130 µs across the two runs; the spread cautions against a universal speedup claim. Reverse cutoff avoids the native kernel already and pays the added lifecycle checks: it has negative paired savings in both runs. Axial transport saves 85.46 / 52.71 µs/tick but remains 518.54 / 522.12 µs/tick. No enabled-wake budget gate closes.

## Contract and verification

- The native instance owns a value copy of the decoded model. `prepare_model` first invalidates the previous snapshot and returns a new positive generation only for valid data. Failed preparation and explicit invalidation reject old tokens. Generation overflow refuses; tokens are scoped to their backend instance.
- **68 native lifecycle checks** cover both tail laws, source mutation/snapshot isolation, replacement, invalid preparation, explicit clearing, instance isolation, fresh dynamic inputs and 15 malformed dynamic-input cases. [Lifecycle report](run2/verify_lifecycle.json).
- **35 adapter checks** cover exact native loads, dictionary replacement, backend invalidation, failed preparation without fallback, explicit setup mode, nested edits followed by reprepare, route changes and legacy GDScript handling. [Adapter report](run2/verify_adapter.json).
- **165 field-contract cases** reuse the existing decoder acceptance/refusal suite through `prepare_model` and `loads_prepared`. [Field report](run2/verify_fields.json).
- **297 GDScript-oracle comparisons** cover random geometry, both tail laws, controls, held/instantaneous downwash, zero/nonzero swirl, stopped propulsion, reverse flow and transported wake. All prepared results equal stateless-native bytes; 296 also equal GDScript bytes, with worst absolute oracle difference **4.44e-16**. [Oracle report](run2/verify_native.json).
- Each profile passes **1,216 byte-exact load comparisons** and **30 flights × 241 exact boundaries**, including body, auxiliary, continuous and load arrays. Four aircraft, twelve smooth-wake cases, axial transport and stopped residual wash retain the previous strict roster and shape/finite checks. [Profiles and hashes](run2/profile.json).
- Each profile records **49 explicit preparations**, **38,126 prepared calls**, **54 stateless setup calls**, and zero route refusals. Setup is explicit and finishes before the paired workload; each load evaluation uses its supplied dynamic inputs without a cross-stage cache. Paired timing samples intentionally replay the same workload.
- Two deliberately broken adapters are rejected in disposable projects: allowing an unprepared smooth/legacy route change fails one check; bypassing prepared dispatch fails three, including direct backend invalidation and snapshot behavior. Four malformed-report probes also fail the strict profile comparator. [Run evidence](run2/evidence.json).

The harness does not detect arbitrary in-place dictionary edits. Its caller must prepare again after every edit, including nested values; identity and route checks are only partial guards. The native snapshot itself remains isolated, but using edited GDScript propulsion data with an old native snapshot would violate the caller contract. Production integration therefore needs an owned immutable model or an explicit revision/rebuild boundary covering load, edits and restore. A dictionary-identity cache is insufficient.

## Reproduction and limits

[Runner, build commands and API contract](../../../../../research/propwash/e0b6p/prepared-model/README.md). [Run 1](run1/evidence.json) uses a working-tree app snapshot; [run 2](run2/evidence.json) reproduces from a fresh `git clone --no-hardlinks --dissociate` of `38e72809`, plus the two new research harness folders and the explicitly supplied native binary/generated-source bundle. No ignored app contents are copied. The two app snapshots differ in `aircraft_data.gd` and `flight_session.gd` because DATA-3 was concurrently adding input-file identity; all compared force/integration sources match. Each paired run compares its own identical model inputs and code snapshot.

Build provenance includes original binding, kernel, candidate snippet, locked builder/toolchain, generated C++ and library hashes. Preparation compilation captures source bytes, checks for changes, and serializes prepared builds. The runner rejects stale source/binary manifests. [Validation summary](validation.json) records zero lint errors (the same 12 existing warnings), Python compilation and a successful [full application suite](suite-summary.log) on the clean tracked app. The suite includes trace integrity, golden flights and exact frame-rate hashes at 30/60/144 fps; the prepared candidate is checked separately by the paired probes. The final runner adds the explicit 35-case adapter count gate after run 1; run 2 uses that gate. Both reports contain all 35 cases.

Preparation/startup cost was excluded and is not measured here. This is a Linux experiment, not Windows/macOS proof, cross-platform determinism, a production reload/checkpoint integration or independent aerodynamic calibration. Same-binary equality preserves existing behavior; the manufactured wake fixtures do not validate the real Stik.

## Next bounded work

The [prepared-path attribution](../prepared-cost/README.md) completes that measurement step on 2026-10-08: static validation is small; swirl, non-wake aerodynamics and the simulation remainder dominate. Its next bounded experiment splits local aero and simulation bookkeeping before another optimization. Preserve reverse-cutoff controls and the immutable-model lifecycle. Revisit integration only with sufficient target headroom and an explicit model revision boundary; Gate P, E0b7 independent calibration and Stik circuit prerequisites stay open.

Sources: project-owned [native decoder/kernel](../../../../../research/propwash/e0b6p/native/), [previous attribution](../attribution/README.md), [decoder contract](../decoder/README.md), and [stage-sharing workload](../stage-sharing/README.md). No new physical assumptions or external aerodynamic references are introduced. Code and evidence use the repository MIT license.

Commit message: `E0b6p: verify prepared native models; prove 1,216 exact loads, 30 exact flights and lifecycle refusals; retain budget gate`
