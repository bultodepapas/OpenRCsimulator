# FUEL 12 fixed wing fuel completion evidence

Checked 2026-10-19 with native Godot 4.7.2 on Windows. The [engineering standard](../../../FUEL-SYSTEM.md) owns current behavior; the [qualification plan](../../../plans/fuel-mass-balance.md) owns remaining measurement, performance and extension gates. This record closes the functional fixed-wing software audit, not physical or release qualification.

The subsequent [FUEL-12-R2 hardening round](HARDENING-R2.md) repairs tiny-fuel event boundaries, unusable-residue restoration, unknown fill provenance and malformed adapter/sample handling. It records 49 passing focused scripts, ten complete same-law comparisons with exact candidate replay, and updated three-family timing evidence. Results below retain the original completion snapshot.

## Implemented result

Current finite Stiks and Extra use the versioned glow adapter. P-51 and Ventage consume their explicit gasoline/turbine stores. Every supported adapter updates mass, CG and inertia, preserves unusable residue, locates exhaustion and continues with its stopped-source law. A glow installation can additionally declare an identified pre-primed line and pickup plane; synthetic tests cover loss of access, finite line depletion and retained unreachable main fuel. Bundled aircraft retain line-free/main-only data until their owners have source-backed delivery geometry.

The selected launch fill is separate from remaining fuel and survives native/JSON checkpoint continuation. Samples, swept contacts, crash effects, HUD/audio, traces, maneuvers and active research recorders use accepted resource state. Workshop validates independent main-tank capacity while refusing unsupported installed-glow scale transforms. Extra's estimated airborne start is 22 m/s: its former 17 m/s start has no admissible bounded installed-engine trim solution. Engine calibration was not adjusted to force that launch.

The [initial A1…A10 audit](../FUEL-00-R1/README.md) remains historical. Typed crash fuel, checkpoint fill provenance, ID/capacity/registry compatibility, datum documentation, angular feed signs, fleet conformance, fatal report drift, event units and enforced blend matching now have implementation and tests. Stale generator/descriptor/economics identities were refreshed through their source pipelines. Earlier invalid FT comparisons remain unqualified; the recordings below replace them as software/replay evidence only.

## Verification

The [native results and logs](../../../../research/fuel-systems/FUEL-12/checks/native-results.json) cover **48 scripts, zero failed**. They include 3247 flight-log checks, 335 glow-installation checks, 110 stage/feed physics checks, 725 trim-integrity checks, 56 selected-fill checks, 29 finite-liquid session checks, 38 contact-session checks, 314 Workshop compiler checks, real Workshop UI/trial routes, crash integration and source/reserve presentation. The result set rejects nonzero exits and engine/script errors. Expected warnings remain in their logs.

The [compile check](../../../../research/fuel-systems/FUEL-12/checks/compile.json) loaded and compiled all **1051 GDScript resources** in the frozen app, with zero failures. A clean import also completed without engine/script/shader errors. The snapshot includes sibling `assets/` authoring inputs and `tools/`; omitting these initially caused fixture setup failures in presentation/Workshop tests. Those tests were rerun after completing the snapshot. A stray literal newline escape in the Extra installation test was removed and its 17 checks rerun successfully.

The [fleet validation transcript](../../../../research/fuel-systems/FUEL-12/checks/fleet-validation.log) covers schema/loader, source migration, module/descriptor, parameter consumer, exact six-installation and 11-output line-ending gates. The report covers 15 configurations, all 9 catalog data paths and 6 additional variants; fatal drift checks pass. Fresh Windows checkout checks confirmed battery LF/aircraft CRLF hash policy. Optional raw battery reference inputs were absent; the existing fit-results consistency check passed. Four synthetic electric fixtures deliberately fail `--qualify` for missing neutral points; 14 configurations have no declared CG range. [FUEL-05 detail](../../../../research/fuel-systems/FUEL-05/README.md).

The final checkout audit added the missing CRLF attribute for the Extra glow installation and byte-preserving attributes for FUEL-12 receipts. A [four-test regression](../../../../research/fuel-systems/FUEL-12/checks/fresh-installation-checkouts.log) constructs disposable Git repositories and confirms that all 11 generated installation/aircraft outputs keep identical bytes with `core.autocrlf=false` and `true`.

Three real production CLI launches emitted [standard-column traces](../../../../research/fuel-systems/FUEL-12/cli/revalidated-results.json), each with 37 accepted rows over 0.15 s: glow v14 and finite gasoline/turbine v15. Strict Python readers validate their mass/store metadata and row layouts. The first Glow validation exposed reader import/boolean/start-summary mismatches; those were corrected and the same saved CSV revalidated. The original result is retained separately.

An exploratory whole-tree unit sweep was stopped after 133 completed scripts, before finishing the repository's 566-script inventory. It ran in a changing shared tree: fuel-related failures found there were repaired and covered by the frozen result set. Landscape placement assertions and transient radio compilation failures also appeared. **The complete repository suite is not reported as passing.** This record does not certify unrelated parallel tracks.

## Recordings and comparison

The [paired-flight manifest](../../../../research/fuel-systems/FUEL-12/flights/verification.json) retains ten complete `.orfl` files with adjacent CSV and export reports: MAX-61FX Stik, FS-64V Stik, Extra, P-51 and Ventage at full and 10% main-tank fill. Every run advances 600 ticks at 240 Hz and exact-replays all 601 samples. Each pair uses identical absolute commands and marker ticks; separately solved launch trims and initial states are recorded explicitly. A fill comparison is not exact equivalence between different initial conditions.

The [protected v2 to v3 comparison](evidence/glow-v2-v3-61fx-20261019-r1/report.json) retains the byte-identical baseline, candidate ORFL, both CSVs and comparison CSV. Baseline replay was checked before implementation. The research-only mapper accepts one source-pinned, line-free MAX-61FX recording: it preserves core slots 0…16 and initial body/inputs, inserts zero line mass and MAIN source mode, and shifts the wheel tail. All 261 baseline samples stay above unusable fuel. It does not migrate legacy Extra hidden engine state or bypass production checkpoint compatibility.

`solver_changed=true` between the baseline (`dc058543…cad66f`) and current model (`db4aba33…105a8`). The candidate recording is complete and exact-replays 261 samples against its own source. Models first diverge at tick 1; maximum main-fuel difference is approximately 3.48e-8 kg. This is a numerical counterfactual, not exact model equivalence or physical validation.

The [source manifest](../../../../research/fuel-systems/FUEL-12/checks/source-manifest.json) records every frozen physics/sim/failure source hash. Independent read-only review found no P1/P2 blockers and confirmed that the material fuel runtime files match the working tree. Recordings pin their aircraft, registry, installation, solver, layout and configuration identities; exact replay requires those sources.

## Cost and remaining qualification

The [timing summary](../../../../research/fuel-systems/FUEL-12/performance/summary.json) uses the same 600-tick command tape, one warm-up and five repeats per fill, excluding import/setup/recording. Median simulation-only cost changed from **1.751 to 4.126 ms/tick at full fill**, and **2.313 to 4.057 ms/tick at 10%**. The new full-fill repeats range from 3.427 to 5.906 ms/tick. The host also ran unrelated Godot jobs; these measurements identify a cost concern, not an isolated causal estimate or GPU/frame-time qualification. The 240 Hz budget is 4.167 ms/tick, so release headroom and the broader propulsion cost target remain open.

Physical acceptance still needs identified empty/full weighing, CG, timed burn, calibrated instruments and uncertainty, plus held-out and pilot comparisons. Borrowed engine curves, estimated line-free geometry, gasoline BSFC and the turbine coast schedule retain their evidence labels. General hopper transfer/re-prime, smoke-liquid consumption and other vehicle adoption remain separately gated extensions.

## Reproduce

Use the engine from [TOOLS](../../../TOOLS.md). Run source generators with `--check`, never by hand-editing generated data. The durable drivers are:

```text
research/fuel-systems/verify_completion.gd -- --out=<new absolute directory>
research/fuel-systems/compare_completion.gd -- --source=<protected baseline.orfl> --out=<new absolute directory>
research/fuel-systems/benchmark_completion.gd -- --out=<new absolute JSON path>
```

Pass each script to Godot's `--headless --path app --audio-driver Dummy --script` option. Comparison preflight uses `--check-only` after the user-argument separator. The production export command is `--script res://tools/flight_log_cli.gd -- --log=<file.orfl> --csv=<new.csv> --report=<new.json> [--replay]`; it refuses overwrite. Preserve the recorded source version before expecting exact replay.

The [Word standard](fuel-system-standard.docx) is generated from the canonical Markdown by `research/fuel-systems/build_standard_document.py`. All four rendered pages were visually reviewed; render intermediates are not deliverables.
