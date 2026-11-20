# ClearView importer completion plan

**Updated:** 2026-11-19. **Status:** v1 incomplete; preview and drafts are available, flight and release gates are open. **Owner:** Aircraft Creator / Workshop, with the main technical lead accountable for integration and closure. **Step IDs:** AC-CV-00…14. **Working branch:** `docs/clearview-import-guide`.

This is the single execution plan for finishing the ClearView importer. Implement the required scope below, attach evidence to each gate, and stop when the final checklist passes. The [Creator plan](aircraft-creator.md) owns shared AC dependencies; [dated research](../research/aircraft-creator/clearview-2026-11-15.md) owns findings and run receipts. Do not create another competing roadmap.

## 1. Fixed delivery contract

**Done means a player completes this entire journey in packaged Windows, Linux and macOS builds:**

1. Select a local ClearView ZIP and choose one aircraft when it is a pack.
2. See the original appearance, a concise conversion report and actionable refusals.
3. Confirm orientation, real size, datum, moving parts and a complete, explicitly identified OpenRC physical configuration.
4. Test-fly that exact configuration using qualified Airborne and Hand-launch starts.
5. Save an immutable aircraft revision, select it in Home, close the application, restart and fly the same revision.
6. Export the permitted complete bundle, import it into a clean profile without the external ZIP or previous library, and reopen and fly the same revision with its appearance and provenance intact.

Every mandatory gate must pass. A preview, draft, successful trim, one flight, passing component suite or saved file does not close this contract. Completion is **ClearView importer v1 for the declared supported subset**; it is not universal ClearView compatibility or a physical-realism claim.

### Required v1 scope

| Area | Fixed requirement |
| --- | --- |
| Input | Local, bounded v5/v6 airplane ZIPs; one aircraft or packs; declared AC3Db/image subset with exact support and refusal rules |
| Visuals | Original textures, supported transforms/materials, correct neutral pose, independently checked control directions and propeller motion; visible reporting of omissions |
| Flight | Conventional wing and aft tail, one tractor electric motor, finite battery, no ground gear, within the qualified Creator package domain |
| Physical authoring | Explicit independent OpenRC installation; complete evidence-bearing v2 data. Source declarations remain attributed observations unless a separately tested adoption rule exists |
| Saved use | Exact revision publication, Home selection, restart, recovery, flight lifecycle, logging/checkpoint/replay and portable source/visual/physical closure |
| Delivery | All three desktop OSs above, every architecture advertised by the release, current application translations and all eleven website/manual translations |

**Outside v1:** Runway starts and fixed gear; gasoline/glow; elevons, pushers, gliders and flaps; biplanes, multiple propulsion units, jets, V-tail/canard, variable geometry and retractable gear; helicopters, multirotors, tiltrotors and scenery; importing ClearView sound, scripts or simulator settings; automatic flight-model equivalence; named-skin authoring and unrelated UI redesign. AC-CV-10…13 retain the future aircraft work. None may enter the critical path without a concrete defect in the required v1 contract.

The bounded AC-19 portability work is mandatory. It does **not** close all of Creator G08 or M3: those also include skin and broader Creator work. Report only the dependencies actually qualified.

## 2. Verified starting point

Planning baseline: branch commit `4c9da3b052f09f0e12eaf508cdb8ed0b732b5952`, with importer runtime inherited from `b2f81d1771031964446a1cbddd83770d6d1c87ff`. The fetched `main` commit `e0a733937e255bacfe95ff09db0fb3838697239f` changes website v0.2.9 links/highlights, with no importer or Creator-plan change. Recheck upstream at integration; preserve this branch's guides and evidence when reconciling website content.

| Boundary | Implemented evidence | Work still required |
| --- | --- | --- |
| ZIP → preview → draft | Bounded archive/parameter readers, pack picker, AC3Db/image conversion and re-admitted GLB; working Creator path | Independent fidelity, complete declared-subset coverage, malformed/resource/cancellation and exported-target qualification |
| Controls and source context | Conservative v6 hinge proposals, manual bindings, source reports and explicit independent-configuration confirmation | v5/manual and propeller semantics, sign/pivot/role coverage, source-aware definition and saved-publication closure |
| Physical flight | Complete estimated-package authoring and trial foundations exist | AC-12/G05 remains unqualified; recognized ClearView sources are deliberately refused by trial, publication and saved-flight paths |
| Publication and Home | Captured v4 publication, compile-binding receipt, exact SourceRef/resolver and selection prerequisites exist | ClearView-aware capture/readback; Home/preferences/Main integration; exact saved-start and restart admission |
| Persistence and portability | Immutable GLB blobs, drafts, revisions, lock, quota and recovery foundations | Separate original-ZIP storage, exact bundle closure, platform filesystem qualification and clean-profile transfer |
| Documentation | Matching short Markdown and website guides in eleven languages | Final supported-subset/release copy, rendered layout and links on the delivered candidate |

The [2026-11-19 check record](../research/aircraft-creator/clearview-guide-checks-2026-11-19.json) contains **1,097 focused checks** and **25 model roots from six ZIPs: 15 visual admissions, 10 refusals**. It is an isolated Linux headless subset, not a full-app or release qualification. Its source-installation/trial attempt emitted engine errors and is explicitly excluded; browser layout was unverified. Keep the older 26-model corpus separate until deduplicated by archive hash and model root. Do not add overlapping sample counts or convert historical evidence into a current-build pass.

## 3. Execution discipline

1. **One owner per active deliverable.** Before work starts, the lead assigns a named person/agent to the role in section 4, records the exact input commit and states the expected evidence. Helpers return bounded findings or patches; the lead owns design, integration and acceptance.
2. **One gate-sized change at a time.** Every patch identifies its AC-CV/AC step, failing acceptance criterion, changed paths and proof. No speculative refactor, new framework, alternate importer, new aircraft family or cosmetic redesign. Reuse existing Creator, Store, resolver, debug, export and test tools.
3. **Keep numerical rules fixed.** Do not lower tolerances, change floors, remove failing cases, narrow the domain after a failure, replace exact replay with candidate replay or remove admission guards to show progress. Each changed law/policy/source candidate needs a separately registered identity before rerunning the unchanged full G05 matrix and acceptance protocol. This plan authorizes no weaker replacement rule or reduced matrix. Required physics fixes belong to AC-12 with its owner.
4. **Keep failed and unavailable results visible.** A skipped platform, missing asset, timeout, engine error, incomplete trace or unreviewed capture is not a pass. Fix the cause or leave the gate blocked with an owner and next action. Repeatedly requesting the same unresolved run is not progress.
5. **Do not widen compatibility to fit one download.** Classify each case against the frozen support contract. A defect inside that contract must be fixed; a genuinely unsupported case must be refused clearly. Do not silently discard a motor, wing, texture, control or other required dependency.
6. **Use proportional verification.** Run affected checks during development; run integration and required CI on the release candidate. Reuse unaffected evidence only when input identities and scope still match. No repeated full-suite campaigns for documentation or local parser edits.
7. **Update the same evidence and plan.** At each handoff report: completed criterion and receipt; exact remaining blocker; next bounded action. Mark a step complete only after lead inspection of the integrated candidate and evidence. Once the checklist passes, close this work; additional features are separate work.

## 4. Ordered work and acceptance

All release gates below are **open**. Existing code is a starting point, not an instruction to rebuild it. Gate 1 and the AC-12 investigation can progress independently after Gate 0. Home/storage work may use existing admissible Creator fixtures while ClearView flight is blocked; that work cannot qualify the final ClearView journey early.

| Gate / steps | Accountable role | Required output and pass rule | Stop condition |
| --- | --- | --- | --- |
| **0. Freeze scope — AC-CV-00** | Lead + QA/evidence owner | One support/corpus manifest: exact baseline/build/engine, admitted syntax/image/geometry subsets, legal fixture uses, hashes/model roots, expected per-model outcomes, chosen real first-flight specimen and compatible field/weather/contact context; register resource thresholds as described below | No identified compatible real specimen/context, uncertain required fixture rights, missing threshold/expected outcome or unassigned owner |
| **1. Finish input, preview and controls — AC-CV-01…04** | Adapter owner + independent visual reviewer | Pass the parser/decoder/geometry/pack/refusal matrix; deterministic GLB readmission; independent transform, UV, pivot, sign and instance checks; complete appearance and truthful report; cancellation leaves the document/library unchanged | Malformed input reaches an unsafe decoder, unsupported content is silently dropped, controls are unverified, or any promised-subset case fails |
| **2. Qualify configuration and flight — AC-CV-05/06; AC-05/06/09/11/12** | Creator owner + physics owner, with UI/field owners | Complete versioned source-aware definition/inventory; explicit configuration confirmation; full unchanged G05 campaign; exact-context start receipt and runtime domain enforcement, including the actual weather/contact witness through the normal UI; qualified Airborne and Hand-launch | G05 incomplete/failed; ambiguous physical values; unsupported layout/power/context; mismatched check/start identities; any bypass of a flight boundary |
| **3. Publish, reopen and select — AC-CV-07; AC-13/18** | Creator persistence owner + UI owner | Source-aware captured publication, immutable ZIP/GLB/definition/physical closure, exact resolver, Home/preferences/Main consumption, real process restart; all corruption/stale/interruption/lock/quota cases preserve valid revisions | Wrong revision/source/configuration resolves, silent stock fallback, partial publication, legacy/downgrade bypass or lost draft/revision |
| **4. Transfer and exercise lifecycle — AC-CV-07/08; AC-09/11/19 + FL** | Creator owner + flight-log owner | Fresh-profile bundle round trip with original paths absent; idempotence/conflict tests; reset/crash/return/recovery; complete exact recorder/checkpoint/replay using the same saved candidate | External source dependency remains, reconstructed visuals differ, failed exact replay, lost return state or altered physical identity |
| **5. Qualify packaged targets — AC-CV-09; AC-20** | Release/QA owner | The player-facing journey from Gates 1–4 through the normal UI on packaged Windows, Linux and macOS; numerical/hostile/native checks through their proper test paths; platform decoder/lock/recovery evidence, rendered fidelity, measured resources and responsive cancellation; required CI passes on exact candidate | Missing OS/advertised architecture, editor-only success, absent native rendering, missing measurement, engine error or failed required CI |
| **6. Finish guidance and release review — AC-CV-14 + WEB/UI** | Documentation owner + independent reviewer; lead closes | Truthful compatibility matrix; concise guides and new UI strings in every applicable locale; working actual-release links; rendered desktop/narrow/RTL website checks; clean final review and checklist below | Copy promises unavailable behavior, required translation/link/layout fails, unresolved release-blocking finding or stale evidence |

### Gate 0: freeze evidence before implementation campaigns

Use the existing research directory, not a new tracking system. Record one result per **archive SHA-256 + model root**, including expected refusal reason and the exact permission needed for local testing, retained evidence and any intended transfer. Keep third-party ZIPs outside Git and mandatory CI unless redistribution rights are explicit; use synthetic known-answer fixtures in CI. At least one identified, lawfully usable real download must complete the player journey. An attractive Extra 330 preview is not evidence that its installation fits the trainer domain.

Freeze the implemented ceilings: **64 MiB ZIP, 256 MiB summed declared expansion, 32 MiB per selected member, 4,096 entries and 64 model roots**, together with stricter downstream Creator limits. Each decoded member must match its bounded declared length and CRC; the aggregate archive ceiling does not measure cumulative work across repeated reads. Include repeated decoding in the measured work/resource budget. Original-package storage must not weaken the separate **32 MiB GLB source** limit. Measure a baseline on named target hardware, then register numeric limits and rationale for import wall time, worst main-thread stall, cancellation latency, peak process RAM, decoded texture bytes, VRAM and frame time before the release campaign. Freeze flight durations, repeated-import/reopen counts and measurement windows with those limits. Missing numbers keep Gate 0 open; these policy ceilings are not measured performance. Never raise a threshold after seeing a failing qualification result.

### Gate 1: preserve the existing trust boundaries

- Read bounded captured bytes; do not extract arbitrary paths, fetch model URLs, execute source settings or search the host for missing assets. Test traversal/drive/UNC/symlink paths, case collisions, duplicate/overlapping members, CRC/local-central mismatches, encryption, unsupported compression, truncation and expansion limits. Resolve a case-insensitive reference only when unique in the selected root, and report it.
- Parse v5/v6 separately using the declared version and `modelName`. Preserve raw unknown/repeated declarations with diagnostics. Render only the declared visual dependency closure; keep `fmodel.ac`, `colbody.ac`, point/line markers and smoke helpers out of the visible aircraft unless their role is explicitly supported.
- Admit only the frozen AC3Db, PNG, BMP and JPEG subsets. Preflight before allocation/decoding, check actual output and aggregate resources, and re-admit every generated GLB through `SourceImporter`. Cover malicious streams and exported-engine behavior. Use correct concave triangulation or refuse it; never substitute a triangle fan for an unsupported polygon. An independent comparator is useful evidence, not a new runtime dependency by default.
- Independently verify asymmetric known-answer transforms, handedness, winding, normals, texture UVs, opacity and hierarchy. Confirm source-to-OpenRC `[x_aft, y_right, z_up]` frame, real span and leading-edge datum; do not assume one source unit is one metre. Normalize supported reflections into geometry before rigid GLB admission; refuse unverified shear/singular transforms.
- Verify v5 and v6 fixtures, neutral pose, parented/offset/oblique pivots, left/right/up/down deflections, propeller direction and two independent instances. Manual confirmed bindings are acceptable when a proposal cannot be derived. Unrepresentable groups, extra parts or role limits require explicit refusal of affected flight capability; no lost aileron or fake axis. Preserve stable `airplane`, `propeller` and hinge conventions.

### Gate 2: flight requires a qualified exact candidate

Source parameters and geometry do not automatically establish OpenRC mass, inertia, aerodynamic coefficients, controls or power. Preserve exact source units, hashes and uncertainty; unknown is not zero. The player must confirm the independent OpenRC installation and its differences from the source. Any adopted value needs an explicit tested unit/frame conversion and correctly labelled provenance, never a relabel as measured data. Inventory must derive total mass, CG and full inertia once, without duplicate components or invisible ballast; all required v2 laws, capabilities and physical IDs must validate.

For the current AC-12 path, qualify **all 68 registered C01–C17 × four-tape cells at 240/480/960 Hz**, retaining the seven metrics, formulas, floors, tolerances and **0.75 convergence-ratio limit**. Each cell needs its own complete exact 240 Hz baseline/replay through tick 1,440, with 1,441 replay rows, `complete=true` and `solver_changed=false`. Preserve source, case maps, policy/law and engine identities. An independent collector and physics-owner review must accept the whole campaign. The [registered campaign](../research/aircraft-creator/AC-12-servo-arrivals-2026-11-16.md#fixed-campaign) owns details; historical 60/68, 64/68 and partial diagnostic results do not close it. A dated “running” note is not current completion evidence.

Keep `gdscript_reference` pinned for Creator trials. Do not add ClearView/aircraft-ID branches to the float64 kernel or inherit stock native-backend qualification. The check and actual start/reset must share the frozen source, definition, compiled bytes, placement/bindings, package/compiler, solver policy, backend, field, weather, energy, tick and start-mode identities. Enforce the qualified domain in trial creation, verification, publication, saved-source resolution, start, step and restore boundaries.

Resolve the existing interactive-context conflict explicitly. The selected servo-law domain requires **calm Reference atmosphere** and refuses soft hull contact, scenery/lake/RC-track collision contexts and the other exclusions in its registration. Home's Calm choice alone can preserve a different atmosphere, and normal flights enable soft contacts. Reuse an actually compatible field, provide a visible validated flight option for the qualified contact policy, and verify the installed weather/collision world before launch and reset. Carry the exact choice through Creator, Home, Main and any versioned preferences without changing stock defaults. Do not silently remove collision data from a drawn field or use `--soft-contacts=off` as a substitute for the normal UI journey. The [AC-18 context boundary](../research/aircraft-creator/AC-18-source-reference-2026-11-16.md#actual-flight-configuration-boundary) specifies the existing seams; a wider context is outside this frozen qualification until separately owned and validated.

Replace each existing refusal only with its proven admission check: `authoring.gd`, `trial.gd`, `compiled_publication.gd`, the Creator UI publish handler, `source_resolver.gd` and `published_trial.gd`. Removing `FLIGHT_UNAVAILABLE` alone is a release-blocking defect. Until the relevant gates pass, recognized ClearView sources retain preview/edit/draft behavior. Metadata identifies recognized sources and checks consistency; it does not authenticate authorship or prove the origin of an arbitrary untagged GLB.

### Gates 3–4: exact publication, Home and portable closure

Extend the existing captured-publication path; do not introduce another Store. Current capture binds a live document/candidate, but its reader checks and paired hashes are not proof that arbitrary physical bytes were derived from a definition. Version source-aware capture, records and verification together. Test stale confirmation, cross-paired definitions/physical bytes/visuals, spoofed receipts, tampering, absent reports, legacy records and downgrade attempts. A changed source/package/compiler must require a new review/revision; preserve historical records and fail unavailable builds clearly.

For the new ClearView-aware format, enforce derivation again when admitting portable or edited stored records: select a recognized compiler/package profile installed with the application, compile the exact stored definition and compare its canonical physical bytes with the immutable stored bytes before flight. Never execute a compiler supplied by a bundle. Prove this comparison on all target platforms; compiler math is not assumed to be byte-identical across OSs. If the pinned profile is unavailable or the result differs, retain the original revision for recovery and keep flight unavailable, without silently rewriting it. An alternative verifier needs a separately specified and tested proof of the same derivation relationship; paired hashes are insufficient. Include a same-UUID/same-law cross-pair with every public hash/receipt recomputed, a forged compiler identity and a downgrade attempt. This rule applies to the new format; preserve documented historical Creator read/legacy-unbound behavior. Derivation consistency still does not authenticate authorship, source claims or physical realism.

Store the captured original ZIP as a **separate bounded, immutable blob** with a versioned receipt, alongside the admitted GLB and complete definition/physical/dependency closure. Capture each pack ZIP once and account for shared references, scratch and store quota. Retain attribution and the original parameter bytes even when an optional GLB report is too large. Do not put a 64 MiB ZIP in the 32 MiB GLB slot, inflate that slot, or treat an archive hash without bytes as portable original-source proof.

Reuse locks, compare-and-swap and atomic publication. Cover disk/quota exhaustion, cancellation, interrupted conversion/save, two writers, stale revision, corrupt/missing dependencies and explicit recovery. Previous valid revisions must remain readable; missing data must not silently select a stock aircraft, newer revision or different source. Home/preferences use the existing exact SourceRef resolver, including stale asynchronous results and restored selection. Do not insert user models into the static stock catalog.

The `.orcaircraft` round trip must contain the permitted original-source, visual and physical closure. Remove access to the external ZIP/old profile for the test; verify identity before and after transfer, idempotent repeated import and explicit conflict copies. Test actual visual reconstruction as well as physical replay: a flight-log hash cannot reconstruct a missing mesh. Do not distribute restricted source assets by default. Complete reset, crash, return-to-editor, unsaved/recovery, log and checkpoint journeys using the same frozen candidate; preserve stock behavior and existing goldens.

### Gates 5–6: packaged evidence and public claims

For **each Windows, Linux and macOS release target**, use a fresh profile and a read-only application installation, with no Godot editor, Blender, Python or conversion tool required by the player. Capture the normal UI journey, pack selection, supported example, clear unsupported example and recovery. Check keyboard/controller navigation, focus, dirty guards, actionable messages, text scaling and every application locale touched by this feature.

Use actual **1920×1080** first on standard displays. On **Apple Silicon Retina**, use the native physical-panel requirement in the [Apple plan](apple-silicon-performance.md), recording output, drawable and internal 3D pixels separately. A headless pass or another OS cannot replace native decoder, renderer, lock, filesystem or measured-resource evidence. Exercise conversion cancellation and repeat import/reopen cycles against the frozen resource limits; record the target hardware and renderer.

Keep the short [player guide](../../site/clearview-import-en.md), its website section and all eleven translations synchronized with the shipping behavior. Reconcile the newer v0.2.9 website changes and this branch's v0.2.7 warning against the **actual release being delivered**, not an assumed version. Verify links, tested example identity, credits, supported-file limits and visible limitations. Update generated pages through the existing site workflow and verify publication includes the Markdown files. Render desktop, narrow and RTL layouts; prior static tests do not establish visual quality.

## 5. Verification and evidence ownership

Use the [tool index](../tools/README.md), [checked runner/test admission policy](../tools/shared.md#one-godot-script), [flight logging workflow](../FLIGHT-LOGGING.md) and [release sequence](../TOOLS.md#release-sequence). Do not invent replacement harnesses where existing entry points cover the contract.

| Boundary | Existing starting points; extend only for uncovered behavior |
| --- | --- |
| Archive, conversion and UI | The six `test_creator_clearview_*.gd` suites; `test_creator_import.gd`, `test_creator_glb.gd`, `test_creator_visual.gd` |
| Definition, identity and flight | `test_creator_source_installation.gd`, `test_creator_compile_binding.gd`, `test_creator_compiler.gd`, `test_creator_trial.gd`, `test_creator_flight.gd`, `test_creator_flow.gd`; registered AC-12 campaign and exact replay |
| Publication, Home and recovery | `test_creator_store.gd`, `test_creator_publication_ui.gd`, `test_creator_persistence_ui.gd`, `test_creator_source_ref.gd`, `test_creator_published_trial.gd`, `test_creator_selection_state.gd`; affected Home/preferences tests |
| Localization and website | `test_creator_language.gd`; `python3 site/build_locales.py --check`; `python3 site/test_locales.py`; `node site/test_downloads.cjs`; rendered layout review |
| Packaged delivery | Existing export/release tools, debug bridge, resource measurements, native filesystem/decoder checks and required repository CI |

The Godot test scripts above are under `app/tests/`. Run compatible independent headless jobs through the shared test pool when available; inspect completion, assertions, warnings and engine errors. A zero process exit or zero failed-assertion line alone is insufficient. Keep rendered and hardware campaigns separate from competing load.

Every gate receipt records: exact tested commit/tree and relevant generated inputs; engine/export hashes; fixture archive/member/model hashes; GLB, definition, compiled physics and package/compiler/solver identities; command and complete verdict; OS/hardware/renderer/actual pixels where applicable; log/report hashes; failures and limitations; reviewer and date. Store small summaries in the existing Creator research home, with retrievable raw evidence outside Git. Do not commit unnecessary screenshots or third-party archives.

## 6. Step status and closure

| Step IDs | Current status / completion evidence required |
| --- | --- |
| AC-CV-00 | **Open:** frozen deduplicated support/corpus/rights/resource manifest and compatible real first-flight fixture |
| AC-CV-01 | **Implemented, qualification open:** bounded readers; close Gate 1 and applicable packaged-input evidence |
| AC-CV-02/03 | **Implemented, qualification open:** converter, preview, report and guide baseline; close fidelity/resources/cancellation/exported evidence |
| AC-CV-04 | **Partial:** conservative v6 proposals/manual bindings; complete declared v5/v6 and propeller/control coverage |
| AC-CV-05 | **Partial:** source reports and explicit configuration choice; complete source-aware definition/publication round trips |
| AC-CV-06 | **Blocked:** G05 and exact start/domain admission; preview/draft guards stay in place |
| AC-CV-07/08 | **Open:** original archive, captured publication, Home/restart, portable closure and full flight lifecycle |
| AC-CV-09 | **Open:** complete packaged Windows/Linux/macOS and registered resource evidence |
| AC-CV-10…13 | **Deferred, outside v1:** gear, combustion, additional control/airframe families and expanded-layout research; no completion claim for them |
| AC-CV-14 | **Partial:** short guides exist in eleven languages; final supported release, rendered guidance, rights and claims still require Gate 6 |

### Final checklist — every box is required

- [ ] Frozen supported subset, compatible real specimen, fixture rights and resource budgets are complete; all promised cases pass and unsupported cases have verified diagnostics.
- [ ] Source/visual/control correctness and hostile/resource boundaries pass on the declared targets, with independent comparison and reviewed captures.
- [ ] Complete physical configuration, full unchanged G05 qualification, domain guards and exact start/reset identity pass; the physics owner accepts the evidence.
- [ ] ClearView-aware captured publication and separate ZIP/GLB/definition/physics closure pass integrity, historical-read, quota, interruption, lock and recovery checks.
- [ ] The normal UI completes ZIP → confirmed configuration/controls → flight → save → Home → real process restart → the same flight.
- [ ] Clean-profile portable export/import works without the external source or old library, preserving visual/source/physical identity, replay, credits and permitted use.
- [ ] Windows, Linux and macOS packages, and every advertised architecture, pass the required rendered journey, lifecycle and measured-resource checks; required CI is green on the exact candidate.
- [ ] All affected application strings and all eleven website/Markdown versions match delivered behavior and release links; desktop/narrow/RTL review passes.
- [ ] The lead resolves every concrete release-blocking review finding and signs off the integrated candidate with links to complete evidence. Missing infrastructure or evidence keeps the affected box open.

**First action for the implementation team:** assign Gate 0 and the AC-12 physics owner, freeze the current inputs and corpus outcomes, select the eligible real specimen, and register measurement thresholds. Then complete the ordered gates. Do not start another feature, rewrite the roadmap or declare the importer finished while a required box remains open.

After accepted delivery, consolidate the final support contract and verified commands into the canonical [Workshop guide](../AIRCRAFT-WORKSHOP.md) and existing evidence. Transfer AC-CV-10…13 and their owners/status to the surviving Creator plan without reopening v1. Update all incoming plan links and the documentation registry before retiring this active plan according to repository documentation policy.
