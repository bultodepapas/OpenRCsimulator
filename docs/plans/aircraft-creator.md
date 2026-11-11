# Aircraft Creator plan

**Date:** 2026-11-10. **Revision:** 7 — first repository revision; re-baselined, re-ordered and reduced from the external [Revision 6 specification](../research/aircraft-creator/2026-11-07-creator-specification-rev6.md). **Status (2026-11-11):** AC-00…11, AC-13, AC-14 and first slices of AC-15 and AC-17 are implemented: a player can import an STL or GLB, place it, describe an estimated electric trainer, bind moving parts, paint it one colour, test-fly it, and save drafts and aircraft versions in a local library. The AC-12 numerical campaign ran and its gate is not passed; Home integration, skins, the bundle and every qualification gate remain open; the package is `experimental`. **Prefix:** AC-00…AC-25. **Owner:** aircraft-creator track.

This plan owns the remaining work and acceptance. The [evidence index](../research/aircraft-creator/README.md) owns probes, commands and results. The Revision 6 specification stays the detailed reference for contracts this plan does not restate (record inventory, storage protocol, UI state machines, hostile fixture lists); where the two differ, this plan wins. [DECISIONS](../DECISIONS.md#aircraft-creator-imports-a-model-but-never-its-physics) owns the durable rationale.

**Owns:** `app/workshop/creator/`, `app/data/creator/`, `app/ui/aircraft_creator*.gd`, `app/tests/test_creator_*.gd`, `docs/research/aircraft-creator/`, this plan.

**Coordinates:** the Workshop host, `Trial`, `Store` and Workshop UI with AE; `app/physics/aircraft_data.gd`, sessions and `app/main.gd` with physics; the v2 contract and model bindings with AS; `app/app_root.gd`, Home, preferences and localization with UI; skins with AE/skin owners; propulsion and battery context with EL/BAT; contact and starts with GP. Check the [track registry](../README.md#tracks-plans-and-step-ids) before editing a shared file.

## 1. Product result and scope

A player brings a local STL or self-contained GLB into the Workshop, sees it as soon as it is safely admitted, confirms orientation, real size and the wing leading-edge datum, supplies the physical description, and test-flies that exact configuration without first saving a named aircraft. The model supplies geometry only. A separate, complete and evidence-labelled physical definition supplies mass distribution, aerodynamics, propulsion, controls, contact and launch behaviour: **a mesh is never a source of physics**.

The first flight slice is one estimated conventional electric airplane: wing and aft tail, aileron/elevator/rudder, a single tractor motor, a finite battery, no landing gear, Airborne and Hand-launch starts. Fixed gear and Runway, combustion power, flaps, elevons, canard, V-tail and retractable gear follow as separately gated steps; **retractable gear is last**. An unavailable card stays visible with its reason and never substitutes another physical topology.

| Milestone | Deliverable | Steps | Availability condition |
| --- | --- | --- | --- |
| M1 Import and author | Strict STL/GLB admission, explicit placement and datum, preview, typed definition | AC-01…08, AC-10 | Admission and preview gates pass; no flight claim |
| M2 First flight | Estimated conventional electric candidate, exact Airborne/Hand checks, test-fly and return | AC-05, AC-06, AC-09, AC-11, AC-12 | Package, numerical, start and identity gates pass independently |
| M3 First player release | Drafts and published revisions, paint and named skins, Home selection, portable bundle, guide | AC-13…20 | The whole import–paint–save–fly–restart–reopen path passes on each advertised desktop target |
| M4 Fixed gear | Tricycle/taildragger contacts, wheel profiles, Runway start | AC-21 | Gear, ground and reset/replay gates pass |
| M5 More modules | Guided balance, more equipment, gasoline/glow, flaps, elevons | AC-22, AC-23 | Each combination has its own compiler, state, visual and numerical contract |
| M6 New layouts | Canard, V-tail, optional format adapters | AC-24 | Dedicated laws and evidence; no aft-tail substitution |
| M7 Retractable gear | Imported rig, contacts, deployment law, interlocks | AC-25 | All earlier contact foundations plus the retract campaign |

## 2. What Revision 7 changes

Revision 6 was written against `997e2127`, 135 commits before the current tree, and had not been run against the application. Revision 7 keeps its product journey, trust boundary and identity model and changes the following.

| # | Change | Reason and evidence |
| --- | --- | --- |
| 1 | **Re-baselined on the current source.** File and line references are refreshed; the airship branch added since (`Compiler`/`Trial`/`app_root` predicate-first dispatch) is the precedent for a new Workshop branch. | `FlightSession.setup(path, expected_id, frozen_data)` already accepts an in-memory model, so a compiled candidate flies with no kernel change. A rendered flight needs about seven narrow branches in `main.gd` and `app_root.gd` ([seam inventory](../research/aircraft-creator/README.md#source-seams-2026-11-10)). |
| 2 | **Risk-first order.** Import → preview → define → compile → fly unsaved comes before durable storage. | Revision 6 built records, a lock utility, the store and the resolver (PR-01…04) before anything flew. Whether an estimated definition yields a stable, flyable aircraft was the largest unknown; storage is known technology, and an unsaved test flight is independent of publication by design. |
| 3 | **No native I/O utility** (drops Revision 6 PR-02). | Probes on the pinned engine: `StreamPeerGZIP` gives bounded streaming inflate, and a loopback `TCPServer` listener is an OS-owned process lock that a second process cannot take and that the OS releases on exit. `FileAccess` offers no exclusive lock. This removes a three-platform native build, toolchain and licence dependency. Linux and macOS lock behaviour is qualified in AC-13; an unavailable lock makes the Creator read-only, never unsafe. |
| 4 | **No third-party STL parser.** | The candidate Revision 6 proposed to harden accepted two malformed fixtures. A strict reader written to the rules is smaller than hardening and carrying another licence. |
| 5 | **Exact zero-area STL facets are dropped and counted**, not a reason to refuse the file. | CAD exports routinely contain them; refusing would reject a large share of real models. No epsilon is used and thin non-zero triangles are kept. Non-finite values still refuse. |
| 6 | **One candidate type with an `experimental` label** instead of parallel research and accepted types with a test-only provider. | Mirrors the catalog's existing `experimental` status. Labelling stays honest; AC-12 changes the label only for a bounded, passing domain. |
| 7 | **The estimated package is named and derived**, not left as an open owner decision. | It uses the closed forms this repository already documents in the Stik data provenance, with the donor coefficient set bounded by a stated domain ([derivation](../research/aircraft-creator/estimated-trainer-package.md)). |
| 8 | **One step registry.** | Revision 6 carried three overlapping backlogs (P1–P8, PR-00…25 and six UI cuts). The AC table below replaces them; the [mapping](#7-revision-6-mapping) keeps old IDs traceable. |
| 9 | **Repository conventions.** The plan lives here, is registered, and links resolve in a fresh checkout. | The Revision 6 companion pack and its historical probe receipts (H01, H02) were never in the repository and are treated as unavailable; needed probes were re-run. |
| 10 | **No pixel-exact layout contract.** | The shell follows `UiScale`, `UiTheme` and the Workshop's responsive rules, 1080p first. Fixed coordinates in a plan age badly and were never rendered. |
| 11 | **Code lives under `app/workshop/creator/`**, not as flat `imported_*.gd` files in `app/workshop/`. | A clear ownership boundary inside the Workshop subsystem, with no parallel editor. |
| 12 | **The physics loader source is not edited.** Revision 6 factored a checked-byte loader inside `aircraft_data.gd`. | That file's bytes are pinned by the solver identity and the fixed-brake legacy gate. `record_loader.gd` repeats the file boundary with the loader's public functions, and a test proves it equals `load_file`. |
| 13 | **Embedded images are decoded once at admission.** Revision 6 relied on prechecks alone. | The independent review reproduced a parser differential between the inflater and the PNG decoder. A structural check plus one real decode refuses such a file at import instead of losing its texture later. |
| 14 | **Unconfirmed starting values are recorded as estimates.** | A value scaled from the model's extent or the reference trainer must not be written as the player's own; the definition carries per-field evidence. |

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
| AC-18 | Home "My aircraft", source-aware defaults and Fly gate, preferences branch, thumbnail/preview/audio/crash consumers | Open. Gate G06/G07 |
| AC-19 | Portable `.orcaircraft` bundle: exact closure export/import, idempotent import, conflict copy | Open. Gate G08 |
| AC-20 | Release evidence: exported targets, resources and stalls at 1080p first, accessibility, offline guide generated from the support manifest | Open. Gate G09; gates M3 |
| AC-21 | Fixed tricycle/taildragger contacts, wheel-profile provider, Runway start with a stopped shaft | Open |
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
| G05 Numerical domain | Preregistered refinement campaign, enforced guard | Not passed: campaign run, 8 of 17 cases pass; upset behaviour explained, not a solver artefact. Second preregistration open |
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
