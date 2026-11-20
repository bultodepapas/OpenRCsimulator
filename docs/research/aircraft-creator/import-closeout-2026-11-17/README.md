# Aircraft import audit — 2026-11-17

**Continuation:** [follow-up 02](followup-02/README.md) reviews upstream `08f94826`, reproduces additional edit/cancellation boundaries and supplies the [implementation guide](implementation-guide.md). Upstream has resolved the 22 missing UID sidecars; preflight now passes, while other required CI/export checks fail. The results below remain the original `2a3cf04d` audit and have not been relabelled as new runs.

## Verdict

**The compatibility adapter is useful and substantially implemented; importing a source aircraft into a complete, saved, flyable OpenRC configuration is not implemented.** The main missing bridge is source-aware physical adoption. Visual conversion, parameter reporting, an explicitly different estimated installation, numerical qualification and saved-flight integration are distinct boundaries. They must not be treated as one success.

This audit reviews main at [`2a3cf04dbbdaf486b9c9c8e983463d828f90c64a`](https://github.com/bultodepapas/OpenRCsimulator/commit/2a3cf04dbbdaf486b9c9c8e983463d828f90c64a), plus the separate Flight Simulator planning branch at `2e83947f9c1d7acf257ff2971cee58151e569106`. Runtime, tests and accepted records are implementation evidence; plans are requirements and history. The audit branch changes documentation and retains observational probes/evidence; it does not fix production code or grant flight admission.

**Fresh evidence:** seven downloaded archives match the earlier recorded SHA-256 values; the production converter admits 18 of 26 model roots as visual sources, with `physics_imported=false` for every success. Fifteen existing focused test scripts pass in an isolated Linux headless fixture on `4.8.beta2.official.cafc17a19`. Additional probes reproduce missing motion reporting, missing PNG cancellation polling and a v4 start/backend mismatch. The baseline's required CI is red before application tests, due to 22 missing tracked Godot UID sidecars. [Verification and limitations](verification.md), [corpus](evidence/corpus-summary.json), [checks](evidence/checks.json), [CI](evidence/ci-baseline.json).

The [closeout plan](closeout-plan.md) owns next-work order. The [handoff](agent-handoff.md) is the next agent's entry point.

## Recent commits and what they actually deliver

| Commit | Relevant contribution | What it does not establish |
| --- | --- | --- |
| [`273a7e4c`](https://github.com/bultodepapas/OpenRCsimulator/commit/273a7e4c) | ClearView source inventory and compatibility planning | A qualified importable aircraft |
| [`63640861`](https://github.com/bultodepapas/OpenRCsimulator/commit/63640861) | Bounded ZIP32/raw-DEFLATE and parameter intake | Physical translation or target decoder qualification |
| [`cfb5acd5`](https://github.com/bultodepapas/OpenRCsimulator/commit/cfb5acd5) | Texture/JPEG conversion work | Every downloaded texture variant supported |
| [`34d4adb0`](https://github.com/bultodepapas/OpenRCsimulator/commit/34d4adb0) | Conservative visual-motion proposals and tests | Verified physical control authority or all v5/v6 motion semantics |
| [`6dfe1b91`](https://github.com/bultodepapas/OpenRCsimulator/commit/6dfe1b91), [`b27b16f2`](https://github.com/bultodepapas/OpenRCsimulator/commit/b27b16f2) | Source observations, metadata recognition and explicit independent-installation choice | Source data adopted into physics, or ClearView flight permission |
| [`f5c4b97d`](https://github.com/bultodepapas/OpenRCsimulator/commit/f5c4b97d), [`c16706b2`](https://github.com/bultodepapas/OpenRCsimulator/commit/c16706b2), [`793f76cc`](https://github.com/bultodepapas/OpenRCsimulator/commit/793f76cc) | Servo/interval laws, campaigns and local-clock protocol | Passing G05 or integration into every real flight route |
| [`c5f2ceef`](https://github.com/bultodepapas/OpenRCsimulator/commit/c5f2ceeff151790b648155ae8cbd92ab89fc7f7e) | Captured publication and definition/raw binding | Source-aware import or Home launch |
| [`2a3cf04d`](https://github.com/bultodepapas/OpenRCsimulator/commit/2a3cf04dbbdaf486b9c9c8e983463d828f90c64a) | Exact SourceRef resolver, selection-state prerequisites and published-payload consistency | Published flight: its start check still always refuses |

These are working increments worth preserving. The remaining work should connect and qualify them, not restart parser, compiler, storage or resolver architecture.

## Implemented boundaries

| Boundary | Current implementation and evidence | Remaining acceptance |
| --- | --- | --- |
| ZIP intake/model selection | Bounded archive access, v5/v6 parameter parsing and model inventory; focused readers/UI checks pass | Exported resource/decoder limits and first supported flight fixture |
| Render source → GLB | AC3Db hierarchy/material/texture normalization and re-admission through `SourceImporter`; 18 actual corpus conversions | Independent appearance comparisons, refused subtypes where required, packaged targets |
| Motion proposals | Conservative v6 pivots plus manual Creator bindings; actual Extra preview has six prepared proposals | v5 mapping, unsupported-target reporting, physical signs/authority and rendered checks |
| Parameter report | Versioned read-only observations with source context | Per-field adoption, dependency semantics and evidence-bearing physical compilation |
| Installation choice | Explicit source/report/package-bound independent estimated installation; recognized sources remain guarded | Faithful installation translation; no generic-power fallback |
| Definition/compiler | Complete estimated conventional, single-tractor electric, gearless v2 candidate through existing loader | Source-aware evidence/schema, actual installations/topologies and qualified domain |
| Unsaved ordinary Creator trial | Existing freeze/verify/start path; focused legacy trial checks pass | v4 explicit backend/context integration, complete lifecycle and numerical acceptance |
| Store/publication | Immutable objects, drafts/revisions, root commit, compile binding and reopen checks | Full target durability/export evidence; source-aware versions |
| Resolver/published payload | Exact indexed UUID/revision/hash, admitted source/presentation, detached owner and consistency verification | Actual start qualification and Home/root/Main/preferences consumers |
| Home/portable player journey | Prerequisites exist; consumer and `.orcaircraft` work remains open | Clean-profile save/restart/flight and portable round trip |

Source seams: [package][package], [converter][converter], [motion][motion], [observations][observations], [definition][definition], [compiler][compiler], [packages][packages], [trial][trial], [publication][publication], [resolver][resolver], [published trial][published], [selection helper][selection], [root][root], [Main][main]. Fresh test scope is in [verification](verification.md); a passing focused script does not establish a full application or exported journey.

## Findings requiring implementation

### 1. Source reporting stops before physical adoption — product blocker

`Package` resolves parameter/render dependencies and `Converter` consumes render AC3D/textures; it does not ingest `fmodel.ac`, `colbody.ac` or configured v5 `paramModelName` as physical inputs. The conversion receipt explicitly sets `physics_imported=false`. `Observations` exposes selected declarations and retains unknown semantics. Authoring explicitly says observations are not adopted. The compiler removes `source_observations` and `source_installation` before physical emission and still uses the fixed estimated packages. The v4 servo-law selector is separately added to the emitted control record; it is not correct to say all v4 inputs are discarded. [Package][package], [converter][converter], [observations][observations], [authoring][authoring], [compiler][compiler], [packages][packages].

The current authoring evidence vocabulary is `manual`, `measured`, `estimated`; ordinary package/v2 quantities also support borrowed/derived evidence. A real adoption contract must cross definition, compiler, raw record, saved revision and reopening together. A UI prefill alone would misstate both provenance and completeness. **Next:** closeout Phases 0–1, AC-CV-05/06 and AC-05/06.

### 2. First source-aircraft eligibility has not been established — product blocker

The downloaded names do not prove compatibility with the current trainer/4S package. Independent reads of exact archive members establish:

- **Extra 330 Red:** v6 parameters link one motor, an 18×7 propeller, servos and named surfaces; `modelMass` is `10.1` with v6 mass units unresolved in the inspected evidence. Its RPM/watt fields do not identify battery/ESC/motor/propeller laws. Gear and source-effect correspondence still need review. Do not replace it with the current 4S/12×6 installation or assume 10.1 lies in the trainer's 1–4 kg domain.
- **Beginair:** v5 `modelMass 5.0` uses the documented kilogram convention, already outside that trainer range. Its auxiliary `PlaneParamModel.ac` is byte-identical in **15** pack models, including very different aircraft. An `electricMotor` object in that shared file cannot establish Beginair's actual installation or geometry correspondence.

[Exact member hashes and selected declarations](evidence/candidate-source-facts.json), [existing unit research](../clearview-2026-11-15.md), [trainer domain][trainer-data], [fixed packages][packages]. Neither specimen is qualified for flight. Extra is a useful first translation-reference fixture; Beginair is a useful ambiguity regression. A bounded eligibility ledger must either select a supported real specimen or identify the smallest necessary law/domain/data extension. This is a concrete dependency, not an invitation to research more formats indefinitely.

### 3. ClearView flight and publication are deliberately closed — preserve until qualified

`SourceInstallation`, both `Trial.freeze` and `Trial.verify`, captured publication, the resolver and the UI publication handler refuse recognized ClearView flight/publication. Draft saving remains possible. Those guards prevent a converted appearance plus an estimated replacement from being mistaken for a finished source-aircraft import; they are not accidental missing buttons. [Installation][installation], [trial][trial], [publication][publication], [resolver][resolver], [Creator UI][creator-ui].

The original numerical campaign reports 8/17 passing cases. The later complete 68-cell campaign for a **private, unadopted stage-wake max-piece candidate** reports **58 accepted, eight failed, two unresolved**, with `numerical_campaign_pass=false` and `flight_qualified=false`. These are prior repository evidence, not campaigns rerun by this audit; the latter candidate is not the current production arrivals-only implementation. Passing selected diagnostics, exact replay or the checked process does not close G05. [Original campaign](../AC-12-numerical-campaign.md), [later retained result](../AC-12-servo-arrivals-2026-11-16.md). **Next:** Phase 3 with a frozen domain and bounded experiments; preserve all failed/unresolved evidence.

### 4. The v4 start path violates its explicit backend contract — reproduced defect

The public authoring API can select the new servo law, compile and freeze an ordinary-source v4 candidate. `Trial.check_start` creates a `FlightSession` and calls `setup` without `setup_stage_backend("gdscript_reference")`. The selected law requires that explicit selection. The fresh probe returns `ok=true`, `available=false`, reason **"servo law requires an explicit gdscript_reference backend selection"**. Here `ok` means the assessment completed, not that flight is available. [Trial start setup][trial-start], [backend selection][backend], [law admission][servo-admission], [retained probe](evidence/gap-observations.json).

Scope: authoring/Trial/Session public boundaries. The normal UI does not currently expose a general v4 selector; this is not a claim that every existing legacy Creator trial fails. Existing legacy trial tests pass and do not exercise this new combination. **Next:** Phase 3 regression plus shared pre-setup backend selection.

### 5. The new law and normal interactive contact policy disagree — integration blocker

The selected servo law refuses soft hull contacts, non-reference/calm conditions and scenery/lake/RC-track contact contexts. Main normally turns on soft hull contacts for interactive flights. A direct Session probe with explicit reference selection admits the candidate before soft contacts, then refuses it after enabling them. This establishes the contract incompatibility; the audit did not run a rendered Main flight to observe its complete UI outcome. [Law admission][servo-admission], [Main contact policy][main-contacts], [probe](evidence/gap-observations.json).

Separately, the scratch start check installs field/weather while Main also configures contact/world providers. Check and launch still lack one shared full-context receipt. Fix the actual configuration flow; merely selecting the backend or bypassing the guard leaves a second failure boundary. **Next:** Phase 3, G06, owning physics/GP/UI paths.

### 6. Targeted unsupported motion can disappear from the report — reproduced defect

For a valid synthetic target, `rotate` produces one prepared motion; changing only `controlledPartMovement` to `move` or `input` still converts successfully, produces zero prepared motions, and leaves `unresolved` empty. Only generic conversion notices remain. The request collector skips non-rotation movement before reporting whether a real target was omitted. [Motion request collector][motion-requests], [probe](evidence/gap-observations.json).

The safe repair is a named unsupported-motion diagnostic and a static admitted part, unless a separately tested motion mapping is implemented. Existing motion tests cover other invalid mappings, not this targeted counterexample. V5's empty request collection also needs an explicit unmapped-motion outcome; that latter observation is from source inspection, not a separate fresh v5 defect probe. **Next:** Phase 2, AC-CV-04.

### 7. PNG normalization ignores cancellation — reproduced defect, latency unmeasured

`Images.normalize` accepts a cancellation callback, but its PNG branch calls `PngCheck` and decode without polling it. A valid 1×1 PNG with an always-cancelled callback returns success with **zero callback polls**. The final `SourceImporter` GLB re-admission similarly has no cancellation argument. UI generation checks protect against stale application of results but do not make the underlying work cancellable; new conversion is withheld while an abandoned worker is still running. [Images][images], [converter][converter], [Creator worker ownership][creator-ui], [probe](evidence/gap-observations.json).

This audit measures no maximum latency, memory peak or UI stall. Do not describe the probe as a reproduced hang. **Next:** Phase 2 callback propagation and adversarial bounded-latency evidence, then target qualification in Phase 5.

### 8. A resolved saved payload is not a launchable aircraft — unfinished integration

The new resolver is a useful exact-revision boundary. `PublishedTrial.prepare/verify` rechecks its detached payload, but `check_start` unconditionally returns unavailable. Root/Main still dispatch the unsaved Creator route; the standalone Creator selection helper is not wired into Home/preferences. [Resolver][resolver], [published trial][published], [selection helper][selection], [root][root], [Main][main].

The resolver also explicitly distinguishes `bound-v2` from `legacy-unbound`. Published-payload preparation can accept historical unbound provenance without establishing the new compilation pairing. That is presently a non-flight inspection path, not an active flight vulnerability. A future Home consumer must define migration/revalidation/refusal before granting flight. **Next:** Phase 4 using the implemented resolver/publication owners; do not recreate them.

### 9. Compile-binding hashes do not prove derivation — future package-import trust boundary

`compile_binding.gd` explicitly records an in-process association, not compiler authentication or store history. `CompiledPublication.valid_pair` validates structure/scope/UUID/law, not derivation of raw physics from the definition; reopening intentionally preserves historical raw bytes without recompiling. A received pair with internally consistent hashes therefore needs a separate semantic-verification policy before source-aware flight. [Compile binding][binding], [pair/reopen checks][publication-pair].

This is source-inspection evidence, not a newly executed cross-pair exploit or a current published-flight attack: published start remains unavailable. The missing acceptance test pairs individually valid same-UUID/same-law definition and physical records from different compilations, recomputes all receipt hashes, and requires semantic verification to reject the mismatch. **Next:** Phases 4–5: applicable pinned compiler/dependency comparison or another reviewed semantic mechanism; unavailable historical verification leads to inspection/refusal or an explicitly new revision, never silently rewritten physics.

### 10. Baseline CI stops before application qualification — release blocker

[Run 44077057768](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/44077057768) is failed for the audited SHA. Its release-preflight step reports **22 missing or invalid tracked UID sidecars**; an independent Git-tree check finds 22 missing names. The required aggregation job also fails to download the absent selection artifact. Application, native, visual and export jobs are skipped. This is **not** evidence of a red importer assertion suite, and it is **not** a full CI pass. [API/job-log extract](evidence/ci-baseline.json), [complete missing list](evidence/missing-tracked-uids.json). **Next:** Phase 0 pinned-editor sidecars and a fresh preflight/required run on the repaired source.

## Re-downloaded corpus

All archive hashes match the [2026-11-15 inventory](../clearview-source-inventory-2026-11-15.json). The audit reads the actual downloaded archives through production `Package.capture` and `Converter.convert`; it does not infer compatibility from extensions or inventory names. [Download receipts](evidence/download-receipts.json), [per-model outcomes](evidence/corpus-summary.json).

| Archive key | Models | Visual conversions | Refusals |
| --- | ---: | ---: | ---: |
| ken-pack1 | 20 | 14 | 6 |
| extra-v6 | 1 | 1 | 0 |
| calmato | 1 | 0 | 1 |
| biplane-v5 | 1 | 1 | 0 |
| osprey | 1 | 1 | 0 |
| paint | 1 | 0 | 1 |
| f117 | 1 | 1 | 0 |
| **Total** | **26** | **18** | **8** |

Refusals are three unsupported JPEG encodings/metadata cases (Calmato 40 Sports, Beech99, Bellanca C-27), three unsupported texture-format cases (701f, 701F2, Brown-B1 Racer), and two intersecting-polygon cases (Ascent Park Glider, MC 300S-Air Guard). These are observed boundary refusals, not all proven converter bugs. They require independent source/decoder comparison before changing acceptance. Admitted V-22, multi-engine or other complex visuals do not become supported flight topologies. Every successful receipt still reports no physics import.

No downloaded aircraft binary is committed. The retained corpus projection includes all model outcomes, diagnostics and dependency hashes plus motion counts/unresolved records; bulky coordinate-frame payloads are omitted, with the full output hash recorded. The probe can reproduce the complete output locally. Download access does not establish redistribution rights.

## Plan corrections and limits

The existing plans correctly preserve strict admission, ordinary v2 output, separate numerical/calibration claims, immutable storage and delayed unsupported families. Their old baseline tables and milestone wording can nevertheless obscure newer delivered slices. This branch links one closeout order and updates those stale navigation/status statements.

The separate Flight Simulator plans contain valuable later-adapter and wizard work, but their editable MSFS source and estimated RC-design assumptions do not establish the user's general downloaded-aircraft outcome. The [closeout continuity section](closeout-plan.md#4-continuity-and-later-formats) preserves them without importing older runtime or treating a replacement installation as faithful translation.

This audit did not run full application CI, native numerical campaigns, the actual original simulator, a rendered visual comparison, crash/long-flight journeys, or packaged Windows/macOS/Linux imports. It proves the narrow current-source results above. Its completion does not close G05/G06/G09 or any source-aircraft release claim.


## Independent review and document checks

Two bounded, read-only reviews checked the plan against its source and the retained evidence; the lead independently inspected the material code and resolved their findings. The final plan distinguishes missing-field estimates from replacement installations, Phase 0A prerequisites from Phase 0B qualification, runtime closure from original-source closure, and current production laws from private numerical candidates. It preserves archived pinned references, adds aerodynamic force/moment mapping tests, scopes stripped-metadata checks to provable cross-pairing, and requires semantic verification of untrusted definition/physics pairs. Both reviewers confirmed closure of their findings; neither ran additional application tests.

The fixture reconstruction command successfully reproduced all 715 recorded source/asset copies with their expected hashes. [Document/evidence verification](evidence/documentation-check.json) records focused link/source-target checks, receipt/log integrity and the reviewed Markdown hashes. This document check is separate from required CI and from the open application/export gates.

[package]: https://github.com/bultodepapas/OpenRCsimulator/blob/2a3cf04dbbdaf486b9c9c8e983463d828f90c64a/app/workshop/creator/clearview/package.gd
[converter]: https://github.com/bultodepapas/OpenRCsimulator/blob/2a3cf04dbbdaf486b9c9c8e983463d828f90c64a/app/workshop/creator/clearview/converter.gd
[motion]: https://github.com/bultodepapas/OpenRCsimulator/blob/2a3cf04dbbdaf486b9c9c8e983463d828f90c64a/app/workshop/creator/clearview/motion.gd
[motion-requests]: https://github.com/bultodepapas/OpenRCsimulator/blob/2a3cf04dbbdaf486b9c9c8e983463d828f90c64a/app/workshop/creator/clearview/motion.gd#L231-L288
[observations]: https://github.com/bultodepapas/OpenRCsimulator/blob/2a3cf04dbbdaf486b9c9c8e983463d828f90c64a/app/workshop/creator/clearview/observations.gd
[authoring]: https://github.com/bultodepapas/OpenRCsimulator/blob/2a3cf04dbbdaf486b9c9c8e983463d828f90c64a/app/workshop/creator/authoring.gd#L185-L194
[definition]: https://github.com/bultodepapas/OpenRCsimulator/blob/2a3cf04dbbdaf486b9c9c8e983463d828f90c64a/app/workshop/creator/definition.gd
[compiler]: https://github.com/bultodepapas/OpenRCsimulator/blob/2a3cf04dbbdaf486b9c9c8e983463d828f90c64a/app/workshop/creator/compiler.gd#L59-L92
[packages]: https://github.com/bultodepapas/OpenRCsimulator/blob/2a3cf04dbbdaf486b9c9c8e983463d828f90c64a/app/workshop/creator/packages.gd
[trainer-data]: https://github.com/bultodepapas/OpenRCsimulator/blob/2a3cf04dbbdaf486b9c9c8e983463d828f90c64a/app/data/creator/airframe-conventional-trainer-estimated-v1.json
[installation]: https://github.com/bultodepapas/OpenRCsimulator/blob/2a3cf04dbbdaf486b9c9c8e983463d828f90c64a/app/workshop/creator/source_installation.gd
[trial]: https://github.com/bultodepapas/OpenRCsimulator/blob/2a3cf04dbbdaf486b9c9c8e983463d828f90c64a/app/workshop/creator/trial.gd
[trial-start]: https://github.com/bultodepapas/OpenRCsimulator/blob/2a3cf04dbbdaf486b9c9c8e983463d828f90c64a/app/workshop/creator/trial.gd#L200-L240
[backend]: https://github.com/bultodepapas/OpenRCsimulator/blob/2a3cf04dbbdaf486b9c9c8e983463d828f90c64a/app/sim/flight_session.gd#L758-L770
[servo-admission]: https://github.com/bultodepapas/OpenRCsimulator/blob/2a3cf04dbbdaf486b9c9c8e983463d828f90c64a/app/sim/servo_interval_flight.gd#L27-L60
[publication]: https://github.com/bultodepapas/OpenRCsimulator/blob/2a3cf04dbbdaf486b9c9c8e983463d828f90c64a/app/workshop/creator/compiled_publication.gd
[resolver]: https://github.com/bultodepapas/OpenRCsimulator/blob/2a3cf04dbbdaf486b9c9c8e983463d828f90c64a/app/workshop/creator/source_resolver.gd
[published]: https://github.com/bultodepapas/OpenRCsimulator/blob/2a3cf04dbbdaf486b9c9c8e983463d828f90c64a/app/workshop/creator/published_trial.gd
[selection]: https://github.com/bultodepapas/OpenRCsimulator/blob/2a3cf04dbbdaf486b9c9c8e983463d828f90c64a/app/app_state/creator_selection.gd
[root]: https://github.com/bultodepapas/OpenRCsimulator/blob/2a3cf04dbbdaf486b9c9c8e983463d828f90c64a/app/app_root.gd#L3128-L3187
[main]: https://github.com/bultodepapas/OpenRCsimulator/blob/2a3cf04dbbdaf486b9c9c8e983463d828f90c64a/app/main.gd#L3373-L3395
[main-contacts]: https://github.com/bultodepapas/OpenRCsimulator/blob/2a3cf04dbbdaf486b9c9c8e983463d828f90c64a/app/main.gd#L1245-L1248
[creator-ui]: https://github.com/bultodepapas/OpenRCsimulator/blob/2a3cf04dbbdaf486b9c9c8e983463d828f90c64a/app/ui/aircraft_creator.gd
[images]: https://github.com/bultodepapas/OpenRCsimulator/blob/2a3cf04dbbdaf486b9c9c8e983463d828f90c64a/app/workshop/creator/clearview/images.gd#L9-L22

[binding]: https://github.com/bultodepapas/OpenRCsimulator/blob/2a3cf04dbbdaf486b9c9c8e983463d828f90c64a/app/workshop/creator/compile_binding.gd
[publication-pair]: https://github.com/bultodepapas/OpenRCsimulator/blob/2a3cf04dbbdaf486b9c9c8e983463d828f90c64a/app/workshop/creator/compiled_publication.gd#L116-L181
