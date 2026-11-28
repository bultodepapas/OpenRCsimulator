# Aircraft Creator plan

The Workshop Creator imports local models, builds experimental configurations, test-flies them and saves local drafts and revisions. Start with the [player guide](../AIRCRAFT-WORKSHOP.md#aircraft-creator-experimental). This task owns AC-00…25, shared interfaces and qualification. The [ClearView contract](clearview-aircraft-import.md) covers estimated and donor flights, the [Phoenix task](phoenix-aircraft-import.md) covers supported source-derived estimates, and [Flight Simulator compatibility](flight-simulator-aircraft-import.md) is a separate design. None closes AC-12 numerical qualification, AC-18 launch from Home, AC-19 bundles or AC-20 packaged-platform acceptance.

The [evidence index](../research/aircraft-creator/README.md) holds dated runs and [Revision 6](../research/aircraft-creator/2026-11-07-creator-specification-rev6.md) preserves the record inventory, storage protocol, UI state machines and hostile fixtures. This task supersedes that revision where they differ. See the [design rationale](../DECISIONS.md#aircraft-creator-imports-a-model-but-never-its-physics).

**Owns:** `app/workshop/creator/`, `app/data/creator/`, `app/ui/aircraft_creator*.gd`, `app/tests/test_creator_*.gd`, `docs/research/aircraft-creator/`, this plan.

**Coordinates:** the Workshop host, `Trial`, `Store` and Workshop UI with AE; `app/physics/aircraft_data.gd`, sessions and `app/main.gd` with physics; the v2 contract and model bindings with AS; `app/app_root.gd`, Home, preferences and localization with UI; skins with AE/skin owners; propulsion and battery context with EL/BAT; contact and starts with GP. Check the [track registry](../TRACKS.md) before editing a shared file.

## 1. Product result and scope

A player brings a local STL or self-contained GLB into the Workshop, sees it as soon as it is safely admitted, confirms orientation, real size and the wing leading-edge datum, supplies the physical description, and test-flies that exact configuration without first saving a named aircraft. The model supplies geometry only. A separate, complete and evidence-labelled physical definition supplies mass distribution, aerodynamics, propulsion, controls, contact and launch behaviour: **a mesh is never a source of physics**.

The first generic STL/GLB flight slice was one estimated conventional electric airplane: wing and aft tail, aileron/elevator/rudder, a single tractor motor, a finite battery, no landing gear, Airborne and Hand-launch starts. Fixed gear/Runway and flaps now have format-specific slices (AC-21 and IAQ-T7). Combustion, elevons, canard, V-tail and broader module qualification have separate gates; **retractable gear is last**. An unavailable card stays visible with its reason and never substitutes another physical topology.

| Milestone | Deliverable | Steps | Availability condition |
| --- | --- | --- | --- |
| M1 Import and author | Strict STL/GLB admission, explicit placement and datum, preview, typed definition | AC-01…08, AC-10 | Admission and preview gates pass; no flight claim |
| M2 First flight | Estimated conventional electric candidate, exact Airborne/Hand checks, test-fly and return | AC-05, AC-06, AC-09, AC-11, AC-12 | Package, numerical, start and identity gates pass independently |
| M3 First player release | Drafts and published revisions, paint and named skins, Home selection, portable bundle, guide | AC-13…20 | The whole import–paint–save–fly–restart–reopen path passes on each advertised desktop target |
| M4 Fixed gear | Tricycle/taildragger contacts, wheel profiles, Runway start | AC-21 | Gear, ground and reset/replay gates pass |
| M5 More modules | Guided balance, more equipment, gasoline/glow, flaps, elevons | AC-22, AC-23 | Each combination has its own compiler, state, visual and numerical contract |
| M6 New layouts | Canard, V-tail, optional format adapters | AC-24 | Dedicated laws and evidence; no aft-tail substitution |
| M7 Retractable gear | Imported rig, contacts, deployment law, interlocks | AC-25 | All earlier contact foundations plus the retract campaign |

## Source-derived flight and release criteria

An independently authored estimate or donor trial has its own identity. To qualify a configuration as a translation of its source, the owner must demonstrate all of the following.

| Boundary | Required evidence |
| --- | --- |
| Source eligibility | Select a permitted, hash-identified fixture. Resolve render, physical and collision dependencies inside the selected model. List units, frames, law, capabilities, missing inputs and redistribution rights separately. The [26-model ledger](../research/aircraft-creator/import-closeout-2026-11-17/followup-02/corpus-eligibility.md) identifies Extra 330 Red as a translation reference and Beginair as an ambiguity case. If a candidate lacks a capability, name its owner and one acceptance test before freezing its flight domain. |
| Mapping and player review | Retain member/hash/key, source and normalized value/unit/frame, derivation version, evidence kind and individual overrides. Label estimates for absent fields. Check asymmetric geometry, controls and forces/moments at representative states. A total mass does not determine inertia. Report unsupported motion and optional visual omissions. Show the effective installation before accepting it. Verify cancellation latency, stale worker rejection, retry, draft recovery and invalid raw edits. |
| Start and flight (G05/G06) | Preregister domain, laws, effective backend, starts, timestep, input tapes, metrics and tolerances. Bind one start receipt to exact source/candidate, trim, energy, field/weather and contact providers. Mutate these inputs to prove invalidation. Exercise real Root/Main launch, rollback with an active recording, reset, replay and return. Keep failed cells and calibration limits visible. |
| Saved identity (AC-18) | Home must consume a pinned published UUID/revision/hash, survive restart and report unavailable dependencies. Archive hides a listing without revoking a pinned revision. Check definition→physics correspondence before sealing an untrusted pair, including a cross-pair with recomputed hashes. Keep historical unverified records inspectable or recompile as a new revision. |
| Portable release (AC-19/20) | Bound bundle members and decompression, verify complete dependencies offline and test interruption, conflicts and import-as-copy. Qualify both raw-source import and bundle import on each advertised packaged target with a clean profile. Record renderer, permissions, cancellation, time/stalls, RAM/VRAM and frame budgets specified before the run. The ClearView v1 receipt retains provenance; its original ZIP remains the player's file. |

The generic importer drops and counts exact zero-area STL facets, retains thin nonzero triangles, and refuses non-finite values. Malformed exporter fixtures motivated the strict STL reader. Embedded PNGs undergo structural validation and a real decode at admission because the preflight and engine decoder differed on a reproduced input. Model-scaled starting values retain estimated provenance until confirmed.

The dated [implementation guide](../research/aircraft-creator/import-closeout-2026-11-17/implementation-guide.md) retains the seam-specific examples and counterexamples.

## 3. Decisions

Revision 6 decisions ADR-01…14 stand, with ADR-04 changed in mechanism.

| ID | Decision | Obligation |
| --- | --- | --- |
| ADR-01 | The Creator lives inside the Workshop host; root keeps departure and flight ownership. | Preserve stock dirty/recovery guards and the single Workshop screen identity. |
| ADR-02 | A persistent `SourceRef` is separate from an unsaved draft and its accepted candidate. Test fly does not publish. | Home and preferences accept published sources only. |
| ADR-03 | Identity is SHA-256 over the exact bytes written once under `openrc-json-bytes-v1`. | No canonical cross-producer equality claim; Store and Trial v1 identities are untouched. |
| ADR-04 | One OS-owned process lock governs Creator writes; other processes are read-only. **Mechanism: loopback listener, not a native utility.** | Never steal a lock by age or PID; an unavailable primitive disables writing. |
| ADR-05 | Accepted data is immutable and append-only; archive hides records; no physical garbage collection. | History, drafts, recovery and trial dependencies keep their bytes. |
| ADR-06 | A single root-index pointer is the publication commit point. | Orphan files are never treated as published. |
| ADR-07 | First formats: strict STL and a bounded self-contained GLB subset; PNG only. | JPEG, sidecar glTF, OBJ, FBX and CAD are refused with export guidance. |
| ADR-08 | The first compiler authors a complete inventory and an estimated conventional package. | No donor mass double count, hidden balancing mass or mesh-derived aerodynamics. |
| ADR-09 | Every launch binds the energy, environment, solver, timestep and laws used in its check. | Changed or fallback configurations need a fresh check. |
| ADR-10 | Physical, visual, skin and full-trial identities are separate. | Paint-only edits keep physical bytes. |
| ADR-11 | Same UUID/revision and same bytes is an idempotent import; different bytes is a conflict. | Import as copy allocates new identities. |
| ADR-12 | A session's reset commit is distinct from root publication of a trial. | Never call a committed reset rolled back; never commit twice. |
| ADR-13 | Numerical verification and physical calibration are separate gates. | Estimated handling stays labelled estimated. |
| ADR-14 | Retractable gear is last. | Fixed contacts, rig geometry and replay foundations precede it. |

## 4. Architecture

```text
file ─► SourceImporter.capture_and_inspect ─► InspectedSource ─► VisualBuilder.build_preview
          (bounded read, hash, StlReader | GlbPreflight + PngCheck)      (fresh nodes, placement)

definition ─► Definition.validate_complete ─► Compiler.compile_candidate ─► AcceptedCandidate
                                                (packages, inventory once, derived aero,
                                                 exact bytes, RecordLoader.load_bytes, domain)

AcceptedCandidate ─► CreatorTrial.freeze ─► qualify (scratch FlightSession) ─► root/Main trial
```

The preview path needs no datum or physics. The flight path needs a complete definition and never reads the player's file path again: the `InspectedSource` owns the captured bytes. Both are data only; no player script, scene or path is loaded. The session installs one `VehicleModel` into `Simulation` as for every aircraft; the kernel gains no aircraft-ID branch.

| Module (`app/workshop/creator/`) | Role |
| --- | --- |
| `result.gd`, `limits.gd`, `bytes.gd` | Result envelope and diagnostic codes; versioned admission ceilings; exact-byte writer/reader with lexical integer tokens |
| `stl_reader.gd`, `inflate.gd`, `png_check.gd`, `glb_preflight.gd` | Strict bounded readers that run before any engine decoder |
| `source_importer.gd`, `inspected_source.gd` | Capture once, choose the format from content, own the admitted bytes |
| `placement.gd`, `visual_builder.gd` | Source-to-structural transform (float64); fresh preview/flight nodes |
| `definition.gd`, `packages.gd`, `compiler.gd`, `record_loader.gd`, `accepted_candidate.gd` | Authoring record, estimated packages, compiler, in-memory record boundary and trusted owner |
| `trial.gd` | Frozen trial, start check and typed outcome |

Existing seams used, all unchanged: `AircraftData.validate_and_derive` and `WheelProfiles.apply_to_model` (the Creator's `record_loader.gd` repeats the `load_file` boundary for in-memory bytes, so the pinned loader source keeps its bytes), `AircraftContract`, `AircraftModules`, `PhysicalIdentity`, `FlightSession.setup` with frozen data, `StrictJSON`, `ScreenStack`, `UiTheme`, `UiScale`, `Widgets`.

## 5. Steps

`ID | work | proof / status`. Status values: **delivered** (with evidence), **in progress**, **open**.

| ID | Work | Proof / status |
| --- | --- | --- |
| AC-00 | Register the track; re-baseline Revision 6; probe engine facts (bounded inflate, process lock, JSON writer, partial float parse) | **Delivered 2026-11-10.** [Engine probes](../research/aircraft-creator/README.md#engine-probes-2026-11-10) |
| AC-01 | Result envelope, limits policy `openrc-creator-limits v1`, writer `openrc-json-bytes-v1`, lexical integer tokens, bit-exact float reader | **Delivered.** `test_creator_bytes.gd`. The reader returns bit for bit the floats the writer wrote; the engine's own text-to-float conversion does not |
| AC-02 | Strict binary/ASCII STL reader | **Delivered.** `test_creator_stl.gd`, 262 checks ([evidence](../research/aircraft-creator/README.md#software-checks)). Real exporter corpus open (G02) |
| AC-03 | Bounded streaming inflate; strict PNG check with CRC, exact scanline byte count and declared-window rule before decode | **Delivered.** `test_creator_png.gd`, 207 checks |
| AC-04 | GLB preflight: container, strict JSON, full-graph acyclicity, accessors, materials, embedded PNG checked and decoded once at admission; refusal before the scene importer | **Delivered.** `test_creator_glb.gd`, 356 checks. Whether to build meshes from the validated accessors instead of the engine importer is open (G02) |
| AC-05 | Estimated conventional trainer package and one complete electric power package, with provenance and domain | **Delivered as `experimental`.** [Derivation](../research/aircraft-creator/estimated-trainer-package.md). Independent source review open (G04) |
| AC-06 | `Definition` with per-field evidence, `Compiler`, `RecordLoader`, `AcceptedCandidate` | **Delivered.** `test_creator_compiler.gd` 196 checks, `test_creator_flight.gd` 56 checks (wing dihedral input added 2026-11-11) |
| AC-07 | Source importer and `InspectedSource` owner | **Delivered.** `test_creator_import.gd` |
| AC-08 | Placement transform and runtime visual builder (static STL and rigid GLB) | **Delivered.** `test_creator_import.gd`. Moving parts: AC-17 |
| AC-09 | Frozen Creator trial bound to its exact bytes; Airborne and Hand-launch checks on the exact candidate, field and weather; outcome separating assessment from availability | **Delivered slice.** `test_creator_trial.gd`. Uses the stock hand-launch law plus a three-second climb-out gate. Open: per-aircraft launch profile, context-aware electric trim with EL/BAT, receipt reuse across check and launch |
| AC-10 | Creator screen in the Workshop: eight steps, typed fields with raw buffers, live summary, issue routing, datum picking, eight catalogs | **Delivered slice.** `test_creator_ui.gd` 201 checks, `test_creator_language.gd`; viewed rendered at 1080p; estimate marker per field. Open: display units other than SI, keyboard orbit, screen-reader and controller journeys, 200 % text (G07) |
| AC-11 | Root/Main bridge: test flight of an unsaved candidate on the pinned reference evaluator, and return to the same wizard and document | **Delivered slice.** `test_creator_flow.gd` through the real root and Main. Open: rendered and long-flight matrix, crash/replay/flight-log and statistics for a Creator trial, restart identity (G06) |
| AC-12 | Numerical and handling qualification: preregistered metrics and tolerances, step refinement, stiff counterexample, enforced domain; a physics-owner review of behaviour after a large upset (roll divergence hands-off at full throttle and after a hard pull; see the [review](../research/aircraft-creator/README.md#independent-review-2026-11-11)); only then drop `experimental` for that domain | **Campaign run 2026-11-11; gate not passed.** [Record](../research/aircraft-creator/AC-12-numerical-campaign.md): 8 of 17 preregistered cases pass the frozen rule; attitude and position stay within tolerance everywhere, body rates during abrupt commands do not (up to 6.7°/s against 2°/s), and seven tapes fail on non-shrinking differences far below tolerance. The upset behaviour is explained (propeller torque, gyroscopic precession, a near-neutral spiral mode: [derivation](../research/aircraft-creator/estimated-trainer-package.md#behaviour-after-a-large-upset-ac-12-2026-11-11)) and wing dihedral is now an input. No bound narrowed; label stays `experimental`. Open: a second preregistration with measured noise floors and an owner decision on the body-rate metric |
| AC-13 | Creator store: immutable hash-addressed objects, root-index pointer, CAS, drafts and recovery, quota, loopback process lock qualified on Windows, Linux and macOS | **Delivered slice (Windows).** `store.gd`, `process_lock.gd`; `test_creator_store.gd` 509 checks including a kill at every transaction stage and a second process; survived an [independent attack](../research/aircraft-creator/README.md#second-independent-review-2026-11-11) after eight fixes. Drafts, automatic-backup slots, immutable aircraft versions, archive flag, 4 GiB quota; nothing accepted is ever deleted. Interrupted-process durability only: power loss is not claimed. Open: Linux and macOS lock and filesystem evidence, exported builds, compaction and consistent limits ([open items](../research/aircraft-creator/README.md#open-items)) (G03) |
| AC-14 | Authoring history (grouped commands, bounded assets), recovery UI, dirty guards joined to root departure and both recorders | **Delivered slice.** Save draft, Open… library, Save aircraft (versions), automatic backup with a recovery question, three-way leave guard joined to the Workshop's navigation and quit guards; `test_creator_persistence_ui.gd` 95 checks. Open: undo/redo history, recorder joins (G07) |
| AC-15 | Appearance foundation: Original/solid, model-bound paint layout, named skin revisions, appearance snapshot through preview, trial and restart | **Delivered slice: Original or one solid colour**, validated, pinned in the frozen trial and stored with drafts and versions; `test_creator_visual.gd`. Open: paint layout, named skins (G08) |
| AC-16 | Generated patterns, bounded STL atlas, PNG-to-group upload, imported `.orskin` branch, model-specific paint kit | Open. Gate G08 |
| AC-17 | Articulated GLB: confirmed hinges, pivots, signs and optional rotor bound to actual actuator state | **Delivered slice.** Player-confirmed bindings of GLB nodes to ailerons, elevator, rudder and propeller, with suggested axis and sign and a preview animation; surfaces follow the simulated deflections and the propeller the shaft in flight; pinned in the trial. `test_creator_visual.gd` 223 checks, flown through the real root in `test_creator_flow.gd`. A part turns about its own node origin (no separate pivot authoring). Open: a rendered review, wreck behaviour of bound parts in a real crash |
| AC-18 | Home "My aircraft", source-aware defaults and Fly gate, preferences branch, thumbnail/preview/audio/crash consumers | [Exact SourceRef, published-payload consistency and selection-state prerequisites](../research/aircraft-creator/AC-18-source-reference-2026-11-16.md) implemented and checked on Windows/macOS. Home/preferences/flight consumers and G06/G07 remain open. |
| AC-19 | Portable `.orcaircraft` bundle: exact closure export/import, idempotent import, conflict copy | Open. Gate G08 |
| AC-20 | Release evidence: exported targets, resources and stalls at 1080p first, accessibility, offline guide generated from the support manifest | Open. Gate G09; gates M3 |
| AC-21 | Fixed tricycle/taildragger contacts, wheel-profile provider, Runway start with a stopped shaft | First slice 2026-11-20 ([decision](../DECISIONS.md#creator-fixed-landing-gear)): optional `landing_gear` definition member (three or four wheel bottoms, steered-wheel travel), compiled spring-damper gear, hull kept above the gear's ground lines, Runway start card and start check; filled automatically from Phoenix wheels. No player editing UI, no wheel-profile provider, no brakes yet |
| AC-22 | Guided residual-mass balance; more qualified electric and pusher packages | Open |
| AC-23 | Gasoline and glow packages; symmetric flaps; the constrained elevon family — each separately | Open |
| AC-24 | Canard and V-tail laws and mixers; optional OBJ/glTF-sidecar/FBX adapters | Open |
| AC-25 | Retractable gear: rig, contacts, deployment law, interlocks, replay | Open; last |

### Definition of done for a step

A step names its source seam and data version, says what the player can now do and which combinations stay unsupported, tests at its public boundary with hostile and known-answer inputs, records evidence with source, engine and platform identity, and refuses malformed, stale or incompatible input without a destructive fallback. Focused checks never replace required CI.

## 6. Gates

| Gate | Pass rule | Status |
| --- | --- | --- |
| G01 Contract and identity | Byte-policy vectors, closed records, defensive boundaries | Writer and integer-token vectors pass; a frozen trial is re-verified against its exact bytes; record schemas for storage open |
| G02 Source and resources | Hostile corpus refused before the scene importer; admitted subset within declared limits on exported targets | Generated hostile corpus passes on the Windows editor build and survived an independent attack after one fix. Real exporter corpus, exported targets and measured peaks open |
| G03 Persistence and recovery | Lock, transaction and fault matrix per filesystem target | Fault matrix and two-process lock pass on Windows (NTFS). Linux, macOS and exported targets open |
| G04 Package completeness | Source-reviewed package, exact inventory, stated domain | Estimated package documented, domain extended to control travel, servo time, thrust angles and charge; source review open |
| G05 Numerical domain | Preregistered refinement campaign, enforced guard | Not passed. Original campaign: 8/17; later [versioned-law and private-candidate investigations](../research/aircraft-creator/AC-12-servo-arrivals-2026-11-16.md) also do not grant qualification. Preregister and enforce the selected domain; retain failed and unresolved results |
| G06 Starts and flight identity | Exact environment, energy, backend and tick across check, start and reset | Reference evaluator pinned and both starts fly; check and launch do not yet share one receipt |
| G07 UI and departure | Real Godot journey, input/history/recovery, 1080p-first accessibility | Journey passes headless including save, reopen, publish, recovery and the three-way leave guard; history and accessibility journeys open |
| G08 Appearance and portability | Layout-bound skins through flight; fresh-install bundle round trip | Solid colour flies and is pinned; skins and the bundle open |
| G09 Export and performance | Target export, renderer, lock and decoder evidence; resources and stalls | Open |
| G10 Calibration claim | Independent measurements and held-out flights | Not claimed: everything is labelled estimated |

Software checks on one development machine establish neither target-hardware performance nor physical realism. The estimated package approximates a trainer inside its stated domain; it is not a measurement of any real airplane.

## 7. Revision 6 mapping

| Revision 6 | Revision 7 |
| --- | --- |
| PR-00 | AC-00 |
| PR-01, P1 (records, identity, checked bytes) | AC-01, AC-06 (loader seam), AC-13 (durable record schemas) |
| PR-02 native I/O utility | Removed; bounded inflate in AC-03, lock in AC-13 |
| PR-03, PR-04 | AC-13, AC-18 (resolver) |
| PR-05 | AC-02, AC-03, AC-04, AC-07 |
| PR-06 | AC-08, AC-17 |
| PR-07, PR-08 | AC-10, AC-14 |
| PR-09, P2 | AC-05, AC-06 |
| PR-10, P3 | AC-17 |
| PR-11, P4 (electric initial context) | AC-09, with the context-aware trim entry points coordinated with EL/BAT |
| PR-12, P5 | AC-09, AC-11 |
| PR-13, P6 | AC-12 |
| PR-14, PR-15 | AC-15, AC-16 |
| PR-16, PR-17, PR-18 | AC-18, AC-19, AC-20 |
| PR-19, P7 | AC-21 |
| PR-20…PR-24, P8 | AC-22, AC-23, AC-24 |
| PR-25 | AC-25 |
