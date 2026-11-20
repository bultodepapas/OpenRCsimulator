# Import audit verification and next tests

**Source:** `2a3cf04dbbdaf486b9c9c8e983463d828f90c64a`.
**Date:** 2026-11-17. **Engine:** `4.8.beta2.official.cafc17a19`, Linux x86_64, headless.
The [audit](README.md) owns findings; the [closeout plan](closeout-plan.md) owns future acceptance. This file distinguishes executed checks from required future work.

**Later same-day work:** [follow-up 02](followup-02/README.md) retains three new observations on `08f94826`, a checked corpus ledger and the updated upstream CI state. The 15-script runs and original preflight failure below remain evidence only for `2a3cf04d`; they were not rerun or relabelled.

## 1. Exact scope of the executed checks

The repository's large application assets were not fully checked out. The audit used an isolated minimal Godot project with copies of the actual production modules, existing tests, synthetic fixtures and needed preload assets. It used the pinned engine and `tools/godot/run_checked.py`, which treats script/engine errors as failure even when a script prints zero failures or exits zero. The test-pool MCP was unavailable and the pool CLI had no local configuration; the unenrolled-executor checked-runner route was used. No app/physics/test source was patched for the fixture.

[Environment and engine binary hash](evidence/environment.json), [715 verified source/asset copies](evidence/fixture-sources.json), [minimal project configuration](evidence/fixture-project.godot), [check index](evidence/checks.json).

The manifest verifies exact exercised file bytes and their Git blobs, honoring repository `eol=crlf` attributes for affected JSON. It separately discloses 23 generated resource UID sidecars: 21 absent from the copied tracked set and two regenerated asset sidecars. The minimal project/configuration, generated resource metadata and import cache are not claimed to be the full application's exact runtime project. This evidence establishes focused public-module behavior, not whole-app resource identity or export qualification.

Initial fixture attempts lacked some translated UI and glTF preload dependencies; cached failed glTF import receipts also persisted after dependencies were supplied. Those checked runs were rejected, even when assertions printed zero failures. Completing the exact dependencies and regenerating the owned failed import receipts produced clean reruns. An initial corpus probe also used the wrong receipt field name and was corrected. [Attempt history](evidence/attempt-history.json) retains those failed/setup attempts; only the final selected checked runs below count. No production fix is attributed to fixture setup.

## 2. Existing focused scripts — all 15 pass

All selected final reports have `ok=true`, `complete=true`, exit code zero, their required completion marker, and zero checked engine errors/warnings. Counts are script-reported checks, not distinct product capabilities; `test_creator_trial` reports failures without an assertion count. Required CI remains a separate gate.

| Existing script | Script summary | Retained proof |
| --- | --- | --- |
| `test_creator_clearview_readers` | 87 checks, 0 failures | [checked report](evidence/runs/test_creator_clearview_readers/report.json) |
| `test_creator_clearview_visual` | 48 checks, 0 failures | [checked report](evidence/runs/test_creator_clearview_visual/report.json) |
| `test_creator_clearview_jpeg` | 363 checks, 0 failures | [checked report](evidence/runs/test_creator_clearview_jpeg/report.json) |
| `test_creator_clearview_motion` | 221 checks, 0 failures | [checked report](evidence/runs/test_creator_clearview_motion/report.json) |
| `test_creator_clearview_observations` | 290 checks, 0 failures | [checked report](evidence/runs/test_creator_clearview_observations/report.json) |
| `test_creator_source_installation` | 88 checks, 0 failures | [checked report](evidence/runs/test_creator_source_installation/report.json) |
| `test_creator_compiler` | 196 checks, 0 failed | [checked report](evidence/runs/test_creator_compiler/report.json) |
| `test_creator_compile_binding` | 88 checks, 0 failures | [checked report](evidence/runs/test_creator_compile_binding/report.json) |
| `test_creator_source_ref` | 230 checks, 0 failures | [checked report](evidence/runs/test_creator_source_ref/report.json) |
| `test_creator_published_trial` | 62 checks, 0 failures | [checked report](evidence/runs/test_creator_published_trial/report.json) |
| `test_creator_selection_state` | 43 checks, 0 failures | [checked report](evidence/runs/test_creator_selection_state/report.json) |
| `test_creator_trial` | 0 failures | [checked report](evidence/runs/test_creator_trial/report.json) |
| `test_creator_store` | 509 checks, 0 failures | [checked report](evidence/runs/test_creator_store/report.json) |
| `test_creator_clearview_ui` | 68 checks, 0 failures | [checked report](evidence/runs/test_creator_clearview_ui/report.json) |
| `test_creator_publication_ui` | 28 checks, 0 failures | [checked report](evidence/runs/test_creator_publication_ui/report.json) |

These passes establish useful existing reader, visual, motion, observation, compiler, storage and resolver boundaries. They also include intentional refusal behavior: a passing ClearView source-installation or published-trial test does not mean that aircraft can fly. The full `test_creator_flow` root/Main journey, native/physics campaigns and rendered/export targets were not run here.

## 3. Fresh observational probes

| Probe | Observed result | Meaning |
| --- | --- | --- |
| [Corpus](probes/corpus_probe.gd) | 7 captured archives; 26 model roots; 18 converted; 8 refused; every converted receipt says `physics_imported=false` | Actual visual-admission evidence, no physical or flight qualification |
| [Motion/cancellation](probes/gap_probe.gd) | Valid `rotate` prepares one motion; targeted `move`/`input` prepare none with an empty unresolved list. An always-cancelled PNG returns success with zero callback polls | Two reproducible missing behaviors; no timing/memory measurement |
| [V4 trial/context](probes/trial_probe.gd) | Compile/freeze succeeds; start assessment is unavailable for missing explicit reference selection. Direct explicit-reference Session admits before soft contacts and refuses after enabling them | Public-boundary integration mismatch; no full rendered Main claim |

The probe scripts are observational evidence collectors. Their exit zero and completion marker mean the observation completed; they are **not passing regression tests for the desired future behavior**. Add assertions for the intended behavior in the owning production test suites before fixing each defect. Do not modify these dated probes to turn their historical observation into a pass.

[Exact observations](evidence/gap-observations.json), [all probe report/log hashes](evidence/checks.json), [corpus projection](evidence/corpus-summary.json), [download hashes](evidence/download-receipts.json), [candidate source facts](evidence/candidate-source-facts.json).

## 4. Reproduce without the full application assets

Read the repository [tool index](../../../tools/README.md), [Godot runner instructions](../../../../tools/godot/README.md) and [test-queue admission policy](../../../../tools/testqueue/README.md) first. Use the shared queue on enrolled hosts. The following direct commands are for an unenrolled isolated executor, matching this audit's scope. They must not be used to bypass shared-host admission.

From the repository root, keep the audit documents/probes available and the audited Git object accessible. The fixture builder obtains the original source blobs by commit, not the current working tree, and restores their recorded checkout line endings. It refuses an existing destination and verifies every copied hash. It does not touch production files or download third-party aircraft.

```bash
python3 docs/research/aircraft-creator/import-closeout-2026-11-17/probes/prepare_fixture.py --out tmp/import-audit-replay
GODOT=$(bash app/get-godot.sh)
python3 tools/godot/run_checked.py --label import-audit-replay-prepare --out-dir tmp/import-audit-replay-checks --timeout 180 -- "$GODOT" --headless --path tmp/import-audit-replay --audio-driver Dummy --import
python3 tools/godot/run_checked.py --label import-audit-replay-motion --out-dir tmp/import-audit-replay-checks --timeout 180 --require-text '0 failures' -- "$GODOT" --headless --path tmp/import-audit-replay --audio-driver Dummy --script res://tests/test_creator_clearview_motion.gd
```

Repeat the last command only for the relevant script from the table. `test_creator_compiler` prints `0 failed`; the other listed scripts use `0 failures`. Use separate checked output directories/labels for independent jobs. Finish resource import before launching tests; never mutate the fixture while tests are running. Each check requires its completion marker and a clean checked report, not just a process exit.

The three audit probes run as script paths outside the project. For example:

```bash
AUDIT_PROBE="$PWD/docs/research/aircraft-creator/import-closeout-2026-11-17/probes/gap_probe.gd"
python3 tools/godot/run_checked.py --label import-audit-replay-gaps --out-dir tmp/import-audit-replay-checks --timeout 180 --require-text AUDIT_GAPS_COMPLETE -- "$GODOT" --headless --path tmp/import-audit-replay --audio-driver Dummy --script "$AUDIT_PROBE"
```

Use `trial_probe.gd` with marker `AUDIT_TRIAL_COMPLETE` for the v4 observation. For `corpus_probe.gd`, use marker `AUDIT_CORPUS_COMPLETE` and append `-- /absolute/corpus-directory /absolute/output.json` after the script argument. Download the seven URLs in `evidence/download-receipts.json` into an owned scratch directory using their recorded `key` plus `.zip`; verify each complete SHA-256 before running. A changed/unavailable upstream file is a different source, not an equivalent rerun. The retained projection omits bulky coordinate-frame payloads; the probe writes the complete report.

The GDScript probes label the audited baseline explicitly. For observations against changed runtime code, create a new dated probe/record with the actual source identity. Random authoring UUIDs and timing values need not repeat; compare the stated semantic outcomes and independently verify all identities within each run. Do not use the old baseline label for new production behavior.

## 5. Missing tests, ordered by the closeout phases

| Phase / owning steps | Test boundary to add or extend | Required counterexample / proof |
| --- | --- | --- |
| 0 / AC-CV-00 | Hashed source eligibility and physical dependency ledger | Shared `PlaneParamModel.ac` is not accepted as aircraft-specific installation proof; out-of-domain mass or 18×7 versus 12×6 mismatch cannot be hidden |
| 0 / release | Pinned-editor source preparation and release preflight | All tracked scripts/shaders have valid tracked UID sidecars; a clean import does not mutate the selected source |
| 1 / AC-CV-05, AC-06 | Adopted-source definition → compiler → v2 → reopen | Independent expected units, axes, source hashes, evidence kinds, forces/moments and control response under admitted laws; changed adopted value changes the right physics; changed report text alone does not |
| 1 / AC-CV-05/06 | Physics/collision dependency resolution and complete inventory | Missing/ambiguous/case-conflicting source members, reused templates, unsupported effects, duplicate mass and invalid inertia refuse without donor substitutions |
| 1–2 / AC-10/14 | Versioned document and raw-edit conflict handling | Invalid raw input survives save/reopen and blocks flight; re-import cannot silently replace a user override or published revision |
| 2 / AC-CV-04 | Targeted `move`/`input`, v5 motion and pivot/sign mapping | Omitted targets produce named diagnostics; independent parented/oblique/asymmetric rest-pose/control expectations |
| 2 / AC-CV-02/03 | PNG and GLB-stage cancellation; worker generation changes | Already-cancelled work terminates; cancel during work meets the frozen latency budget; stale completion cannot apply/publish and cannot strand retry |
| 2 / AC-CV-03/04 | Actual source appearance and control animation | Independent source reference, original paint/UV/opacity/parts and full neutral/deflection checks at 1080p |
| 3 / AC-09/11 | v4 through real root/Main setup and first tick | Explicit reference backend before setup; actual interactive contacts/environment agree with the admitted law; both allowed and refused cases |
| 3 / G06 | Shared start request/receipt and reset/lifecycle | Mutate field, scenery/contact provider, weather, SOC, law, backend, timestep and candidate independently; stale receipt cannot launch or reset as if unchanged |
| 3 / G05 | Preregistered numerical domain and exact replay | Preserve failed cells and unresolved-floor cases; complete evidence, enforced domain and unchanged accepted metrics; no post-result threshold adjustment |
| 3 / AC-CV-06/08 | Recognized-source admission and lifecycle | UI bypass, source/receipt cross-pairing after metadata removal/change, unsupported topology and malformed sources refuse; ordinary sources still require independently qualified physics; admitted source returns to the same editor after failure/flight |
| 4 / AC-13/18 | Bound publication, SourceRef, Home/preferences, restart | Exact revision survives restart; legacy-unbound records require the explicit policy; missing/corrupt/stale references do not select an unrelated aircraft; archive hides listings but preserves a valid pinned reference |
| 4–5 / AC-13/19 | Untrusted definition/physics correspondence | Same-UUID/same-law valid records cross-paired with all hashes recomputed must fail semantic verification; unavailable historical compiler requires inspection/refusal or an explicit new revision |
| 4 / G03/G06 | Source-aware interruption/lock/reset/log identity | Fail at each new transaction boundary; second process is read-only; recovery preserves prior revision; logs/checkpoints/replay retain admitted identities |
| 5 / AC-19 | Portable bundle into a clean offline profile | Runtime and permitted original-source closure distinguished; duplicate idempotence; conflicting bytes/copy; unsupported schema/law; traversal/corruption/truncation; no half-published aircraft |
| 5 / AC-20, AC-CV-09/14 | Real packaged Windows/Linux/macOS journeys | Raw ZIP and `.orcaircraft` paths, file picker, no editor/source/tool dependency, read-only install, resource/cancellation measurements and 1080p rendering |

Test expectations must come from independent known values or explicit contracts. Do not add tests that only re-run the same translator to calculate its own expected result. Keep existing hostile-reader, stale-publication, downgrade and resolver counterexamples. Run broader suites only for changed shared boundaries or required gates; the objective is a working, qualified player journey, not a higher assertion count.

## 6. CI and evidence interpretation

The [baseline GitHub run](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/44077057768) failed at release preflight on 22 missing tracked UID names; the required aggregate then could not download `ci-selection`. Godot application/native/visual/export jobs were skipped. [CI snapshot](evidence/ci-baseline.json), [independent UID list](evidence/missing-tracked-uids.json). No successful full CI result is claimed by this audit.

The prior 8/17 result and the private, unadopted stage-wake max-piece candidate's 58 accepted / 8 failed / 2 unresolved result are repository campaign reports, not freshly reproduced physics measurements. The latter is not a current-production arrivals-only-law result. The exact source/engine/platform and retained failed results remain authoritative for those campaigns. A local focused Store pass does not supersede platform/export durability gates, and a successful visual conversion does not prove control, flight or physical realism.
