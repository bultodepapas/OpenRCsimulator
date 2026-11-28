# Import audit follow-up 02 — implementation boundaries

**Date:** 2026-11-17. **Production source:** `08f948265d40d83fbb4726a302b9e1c9490ccfce`.
**Branch:** `audit/aircraft-import-closeout-2026-11-17`.

This continues the [first audit](../README.md) with three new executed probes, a checked corpus ledger and a closer review of draft, launch and publication boundaries. The [implementation guide](../implementation-guide.md) turns the findings into code seams, pseudocode and regression recipes. The [Creator task](../../../../plans/aircraft-creator.md) owns current acceptance.

**Result:** invalid inventory input can be lost on save/reopen; cancellation during the last model can return a successful partial inventory. Two further runtime defects are supported by source traces and still need full integration reproductions. Existing hash-pair checks are demonstrably insufficient to establish external definition-to-physics derivation. None of this evidence qualifies a source aircraft for flight, and this follow-up does not change production runtime logic.

## Baseline and upstream changes

The branch incorporates upstream `08f94826` after the original audit at `2a3cf04d`. The [Git-tree comparison](evidence/baseline-delta.json) finds **no changed `app/**/*.gd` or `app/data/` files** between those production commits. The application delta consists of 22 UID sidecars and seven localization files. Testqueue tools and documentation also changed; their wider resilience implementation is outside this importer audit.

The 22 previously missing sidecars are now tracked upstream: 19 arrived through `2ec329f3`, with the final three in `e0e71e24`. A Git-tree inventory finds zero missing script/shader sidecars. The audit's minimal project now copies the actual tracked UIDs instead of relying on editor-generated replacements for those files.

The upstream [CI run 44109522803](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/44109522803), on `08f94826`, **passed “CI selection and release preflight” but failed overall**. Selected failed-job logs show:

| Boundary / owner | Observed failure | Implication for this plan |
| --- | --- | --- |
| Companions qualification | Several units report a solver identity mismatch; one profile test then accesses a missing dictionary `format` and times out | Requalify or investigate with that owner; do not bless stale profiles by changing hashes alone |
| Home/companions flow | `test_companions_draft_refresh` reports “normal Home flight starts” failed | Existing full-app baseline is not green; exact cause was not isolated by this audit |
| Shaft source fixture | `test_shaft_publication` reports its manifest/source identity differs | Restore valid source-bound fixture evidence through its owner |
| Shaft capacity law | `test_shaft_capacity` reports motor-off capture rejected because the step policy returned no state | Numerical/runtime owner must investigate the actual law; do not classify this as a mere stale hash |
| D11g provenance | Rate-derivative source fields do not match current or qualified historical provenance | Preserve provenance validation and resolve through the aircraft-data owner |
| Native export | Linux export reports prepared NK-3 manifest inputs differ; checked runner rejects engine error even with process exit zero | Export readiness remains open |

[Job statuses, source SHA, URLs and retained log excerpts](evidence/ci-upstream.json). These are observed upstream failures, not a demonstrated common root cause. Successful native/visual jobs do not cancel failed required jobs. This receipt describes upstream main, not the later audit merge commit or a newly qualified release. The original audit's failed preflight remains correct historical evidence; the next developer should not recreate the already supplied UID files.

## Executed observations

### 1. Invalid inventory edits disappear from saved drafts — confirmed defect

The probe uses the real Creator mass input and Store draft path in an isolated headless project:

1. Adopt the existing valid authoring fixture, open Weight and balance, and save a named draft with wing mass **0.504 kg**.
2. Enter `not-a-number` in `ItemMassItemWingAirframe` and submit it.
3. Inspect document/UI state, request a recovery write, save the draft and load it through Store.
4. Reopen through the UI's `_finish_open("draft", …)` path with the same admitted source.

| Observation | Before edit | After invalid edit | After save/reopen |
| --- | --- | --- | --- |
| Visible mass text | `0.504` | `not-a-number` | `0.504` |
| Last accepted mass | 0.504 | 0.504 | 0.504 |
| Dirty state | false | **false** | false |
| Document fingerprint | Original | **Unchanged** | Unchanged |
| Inventory error | None | Invalid mass field | **None** |

The edit left revision 7 unchanged; the stored snapshot omitted the rejected text; a forced backup call produced zero recovery entries. Save and reopen both returned success. The live UI reports the invalid field while open, so this is not evidence that the current visible invalid state launches a trial. It is a persistence/dirty-state defect that can remove that state on reopen.

Source chain: UI [`_commit_item_number`, `_draft_record`, `_write_backup`, `_adopt_document`][ui] and Authoring [`set_item_raw`, `snapshot`, `has_unsaved_changes`][authoring]. The raw inventory text lives only in UI dictionaries. The invalid parse returns before document revision changes.

[Probe](probes/inventory_edit_probe.gd), [checked report](evidence/runs/followup-inventory/report.json), [observations](evidence/observations.json). Scope: real widget callbacks, actual draft write/read and reopen/adoption; source import and asynchronous re-admission were bypassed by installing the admitted fixture. No file-picker, rendered usability or full departure journey was exercised.

The probe also records the existing Estimated-item policy: edit wing mass 0.504 → 0.75; `propose_inventory()` restores 0.504 while kind remains Estimated. The UI explicitly warns that Propose replaces Estimated items. This is **not a defect against the current documented contract**. Future source adoption needs property-level override ownership so one edited mass can be retained without falsely marking the whole item measured.

### 2. Last-model cancellation becomes partial success — confirmed API defect

The production `Package.inspect_archive()` is given a synthetic ZIP with two independently valid roots. A monotonic cancellation callback first returns true at poll four, during the second root's parameter read. The result is:

- `package_ok=true`, with an empty top-level diagnostic list;
- root `One` remains valid;
- root `Two` is invalid with “The import was cancelled.”

The uncancelled control returns both roots as valid; cancellation at the first three polling thresholds returns overall failure. The final-member case falls through to success because a prior root was accepted. Propagate cancellation as an operation outcome, including a final pre-success check. Ordinary per-model incompatibility may remain a partial inventory; cancellation must not masquerade as completed discovery.

[Package source][package], [probe](probes/package_inventory_probe.gd), [checked report](evidence/runs/followup-package/report.json), [full threshold sweep](evidence/observations.json). This does not prove a stale cancelled result is adopted by the wizard; its worker-generation guards are a separate boundary. Callback counts do not measure cancellation latency or memory behavior.

### 3. Nested valid roots are suppressed — confirmed behavior, policy decision open

The same probe creates valid `Outer` and `Outer/Inner` models with separate parameter and visual files. Together, only `Outer` is listed. `Outer/Inner` is admitted when tested alone. `Package.inspect_archive()` suppresses descendants of an accepted root before validating the descendant's own dependencies.

The current test deliberately prevents nested sound parameter files from appearing as aircraft. That remains useful. Decide whether genuinely nested models should be selectable or explicitly reported as unsupported/ambiguous. The probe establishes suppression, not a universal promise that every nested layout must work. Do not remove nesting protection indiscriminately.

### 4. Matching hashes do not prove semantic compilation — demonstrated contract limit

The probe creates valid ordinary Creator definitions A and B with the same UUID and selected servo law. A uses **0.14 s** servo time; B uses **0.20 s**. Their compiled bytes differ. It then combines definition A with physics B and creates a matching receipt for the newly calculated hashes.

| Current check | Result on the cross-pair |
| --- | --- |
| `CompiledPublication.valid_pair(A, raw_B, uuid)` | true |
| `CompileBinding.matches(recomputed_receipt, …)` | true |
| `CompiledPublication.match_document(A, received_value)` | success |
| Trusted `CompiledPublication.capture(A)` | Still returns A's corresponding bytes |

This matches the source comments: pair validation checks structure/scope/UUID/law, while the receipt records a trusted local association. It is not compiler authentication. The probe constructs a received dictionary only; it does not publish into Store, import an external bundle or launch a flight. Published start is currently refused.

The future untrusted bundle/restore route must establish derivation before granting flight. Recompile with an installed reviewed verifier and pinned dependency identities, or implement another reviewed semantic mechanism. [`Resolved`][resolver] currently retains only the definition hash, so verification for a new flight-eligible owner belongs before its `_seal()` boundary unless that owner is deliberately extended. Historical `legacy-unbound` owners can remain explicitly inspection-only without this proof. Preserve historical bytes and local capture's correct association.

[Probe](probes/semantic_pair_probe.gd), [checked report](evidence/runs/followup-semantic-pair/report.json), [exact hashes/results](evidence/observations.json), [publication source][publication], [binding source][binding].

## Source-inspected runtime defects

These findings trace unchanged production source. **No new full AppRoot/Main integration run was performed for them.** Their regression recipes are the next proof, not completed checks.

### Failed trial startup can finalize the previous flight log

[`AppRoot._start_workshop_trial()`][root] says the previous world/recorder will be retained until candidate startup succeeds, but calls `remove_child(previous)` first. That invokes [`Main._exit_tree()`][main], which calls `flight_log.stop("flight closed")`. [`FlightLog.stop()`][log] writes its footer, disconnects observers, sets `recording=false` and closes the file. On candidate startup failure, Root re-adds the previous node; it does not resume the finalized log.

Required integration test: start a stock flight and a real isolated log; Pause → Workshop; prepare a valid ordinary Creator trial; inject invalid candidate lighting through the prior node's copied `lighting_config`; request flight; assert the original scene returns **and its same log remains open and accepts a subsequent tick**. The injection isolates rollback; it does not assert that ordinary UI settings generate invalid lighting. Define successful temporary-trial recording policy separately.

### Technical launches can check a different field/weather from the flight

Root's direct-flight path returns before its Home preference/landscape synchronization. Main resolves `--landscape` and `_weather_options()` independently. With a direct flight that requests Green Paradise and nonzero wind, Root can still hold the default field path, while `previous.weather_config` is the requested calm property rather than `session.weather_configuration()`.

Later `_start_workshop_trial()` assesses Root's `field_path` and the previous node's `weather_config`. The candidate Main inherits the OS user arguments and resolves the landscape/wind again. Conditional on successful scratch assessment, the checked context therefore differs from the launched context. Relevant source: Root's direct-route early return, `start_flight()` and `_start_workshop_trial()`; Main's `user_args`, `_weather_options()`, landscape selection and `session.setup_weather()` calls.

Required integration test: actual direct technical launch with `--landscape=green_paradise --wind-speed=4 --wind-from=270 --physics-backend=gdscript_reference`; capture previous installed field/weather; request an ordinary legacy/v1 Creator trial; compare assessed and candidate-installed context. Using v1 keeps the separate v4 backend/calm-law refusal from masking this case. A test injecting only Root's `user_args` must explicitly supply equivalent candidate args because Main's default comes from the OS. Assert exact agreement or a named refusal, not only “flight started.”

The [implementation guide](../implementation-guide.md#8-resolve-one-effective-start-request-then-prepare-and-commit) defines the shared-request and setup-order work. Existing v4 backend and soft-contact incompatibilities remain separate blockers from these two defects.

## Corpus decision and remaining work

The [human-readable ledger](corpus-eligibility.md) and [machine ledger](evidence/eligibility-ledger.json) cover all 26 model roots in the seven hash-pinned ZIPs. Independent verification checked seven archive hashes, 26 parameter-member hashes, **1,075 retained record locations**, 26 auxiliary-member hashes and all 26 prior visual outcomes. [Verification receipt](evidence/ledger-check.json), [reproducible verifier](probes/verify_ledger.py).

The ledger is a bounded lexical inventory, not a complete physical mapping. It establishes no ready first-flight specimen. V5 mass declarations all exceed the current trainer domain; v6 units and installation semantics remain unresolved; repeated motor rosters and reused auxiliary geometry constrain the next decision. Continue with Extra's field-by-field semantic/dependency table and one named prerequisite, using Beginair for ambiguity. Do not repeat the broad corpus survey or replace source facts with artificial trainer data.

## Verification scope and reproduction

New execution used Linux x86_64, pinned **Godot `4.8.beta2.official.cafc17a19`**, a minimal project with **738 exact tracked source/asset copies**, and `tools/godot/run_checked.py`. The checked project import and all three observations completed with zero checked engine errors/warnings. All 738 source bytes still matched the manifest afterward. [Environment](evidence/environment.json), [manifest](evidence/fixture-sources.json), [project](evidence/fixture-project.godot), [four checked reports/log identities](evidence/checks.json).

The 15 passing focused scripts from the [first audit](../verification.md) were not rerun simply to increase the count. The new probes isolate the actual remaining questions. Completion markers mean the observations completed; they are **not passing regression tests for the desired behavior**. No production application/test code was modified to obtain these results.

The test-pool MCP was unavailable and this private executor had no configured local pool; the unenrolled-executor checked-runner path was used. Follow [queue admission](../../../../../tools/testqueue/README.md) on enrolled hosts. The minimal project is not full-app, native OS/GPU, rendered 1080p or export evidence.

To reproduce from the repository root, with the pinned Git objects available:

```bash
python3 docs/research/aircraft-creator/import-closeout-2026-11-17/followup-02/probes/prepare_fixture.py --out tmp/import-followup-replay
AUDIT_GODOT=$(bash app/get-godot.sh)
python3 tools/godot/run_checked.py --label followup-replay-prepare --out-dir tmp/import-followup-replay-checks --timeout 180 -- "$AUDIT_GODOT" --headless --path tmp/import-followup-replay --audio-driver Dummy --import
AUDIT_PROBE="$PWD/docs/research/aircraft-creator/import-closeout-2026-11-17/followup-02/probes/inventory_edit_probe.gd"
python3 tools/godot/run_checked.py --label followup-replay-inventory --out-dir tmp/import-followup-replay-checks --timeout 90 --require-text AUDIT_INVENTORY_COMPLETE -- "$AUDIT_GODOT" --headless --path tmp/import-followup-replay --audio-driver Dummy --script "$AUDIT_PROBE"
```

Use `package_inventory_probe.gd` / `AUDIT_PACKAGE_COMPLETE` or `semantic_pair_probe.gd` / `AUDIT_SEMANTIC_PAIR_COMPLETE` for the other two observations. Import first; do not mutate the fixture while a check is running. The fixture builder verifies each pinned source hash and refuses an existing output directory. Random UUIDs/fingerprints differ between independent runs; semantic outcomes and within-run identities are the comparison.

For the corpus ledger, obtain the seven exact archives from the first audit's [download receipts](../evidence/download-receipts.json) into an owned directory and run:

```bash
python3 docs/research/aircraft-creator/import-closeout-2026-11-17/followup-02/probes/verify_ledger.py --corpus /absolute/path/to/the/seven-archives
```

The verifier checks transcription and hashes only; it does not invoke the converter or establish physics. A changed upstream archive is a different fixture. No third-party archive or model binary is redistributed in this follow-up.

[ui]: ../../../../../app/ui/aircraft_creator.gd
[authoring]: ../../../../../app/workshop/creator/authoring.gd
[package]: ../../../../../app/workshop/creator/clearview/package.gd
[publication]: ../../../../../app/workshop/creator/compiled_publication.gd
[binding]: ../../../../../app/workshop/creator/compile_binding.gd
[resolver]: ../../../../../app/workshop/creator/source_resolver.gd
[root]: ../../../../../app/app_root.gd
[main]: ../../../../../app/main.gd
[log]: ../../../../../app/sim/flight_log.gd
