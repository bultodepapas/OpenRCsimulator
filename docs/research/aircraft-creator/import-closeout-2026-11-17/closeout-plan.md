# Aircraft import closeout

**Historical, superseded 2026-11-20.** This was the active plan from 2026-11-17 until its packets were merged into main on 2026-11-20. The [ClearView importer plan](../../../plans/clearview-aircraft-import.md) now owns status and remaining work; this file keeps the audit-era contract and the packet log as dated evidence.

**Date:** 2026-11-17. **Original audited source:** `2a3cf04dbbdaf486b9c9c8e983463d828f90c64a`.
**Follow-up production source:** `08f948265d40d83fbb4726a302b9e1c9490ccfce`, incorporated into the same audit branch.
**Status:** audit and implementation guidance delivered; packet 1 repairs integrated ([§6](#6-implementation-status)); usable source-aircraft import is not complete.
**Owners:** Aircraft Creator / ClearView, with the existing physics, AS, UI, FL, GP and energy owners at their shared boundaries.

This is the execution order for finishing **download → import → fly → save → restart → fly**. The [Creator plan](../../../plans/aircraft-creator.md) continues to own AC-00…25 and G01…G10; the [ClearView subplan](../../../plans/clearview-aircraft-import.md) owns AC-CV-00…14 and format contracts. Phase numbers below sequence those existing steps; they are not another step registry. This document owns the import closeout order and acceptance. Existing plans retain broader Creator features and later aircraft families. Current code and checked results determine implemented status.

Read the [dated audit](README.md), [follow-up evidence](followup-02/README.md) and [verification record](verification.md) for actual findings/runs. Use the [implementation guide](implementation-guide.md) for exact seams, pseudocode and regression recipes, and the [agent handoff](agent-handoff.md) before starting a packet. Do not repeat the audit as the next development task.

## 1. Product contract

A player runs a packaged OpenRC build, selects an aircraft ZIP downloaded from its author, selects a model in a pack, reviews the converted aircraft and any genuinely unresolved information, and flies a supported configuration. After saving, the same aircraft appears in Home and flies after a process restart. A portable `.orcaircraft` package can later carry that exact published configuration to a clean profile. Players need no Blender, Python, editor, terminal or manual file conversion for an advertised supported package.

The default import path must use the source's actual declared data wherever its meaning is established. It must distinguish:

| Value origin | Required treatment |
| --- | --- |
| Source declaration with known units and meaning | Translate deterministically; retain member/key/hash and mapping version; label as borrowed source data, not a measurement |
| Derived quantity | Retain its equation, inputs, frame and assumptions; independently test the derivation |
| Missing or conflicting information | Name the exact gap; resolve from an identified dependency or ask one actionable question |
| User correction or measurement | Retain the raw edit, value, unit, evidence and override of the original declaration |
| Genuinely missing field completed by an estimate | Use an attributed estimator only within its reviewed/qualified domain; expose the estimated field for review and label the result partly estimated. Never claim this value was translated from the source |
| Replacement installation or changed topology | Offer as an explicitly different configuration, with its own identity and visible changes; never silently select it to make import succeed |

Unknown is not zero. A valid mesh, a source-reported mass, or a successful trim does not supply a complete aerodynamic, inertia or power model. Source simulation coefficients require a demonstrated semantic mapping into an OpenRC law. Faithful data translation does not by itself establish identical trajectories in two different simulators or calibration against a real aircraft.

**Import completion:** one identified source-aware configuration, in its advertised capability/start/environment domain, passes the whole player journey on each advertised packaged target. It may contain explicitly reviewed, justified estimates for genuinely absent fields; those fields remain labelled and do not become source evidence. Unsupported essential features stay visible with a precise reason. Do not describe omitted engines, gear, surfaces or mixers as a complete conversion. An intentionally different RC design may remain available as a separate authoring workflow; it does not satisfy this contract.

**Creator scope:** original appearance and necessary control motion are required here. A full paint editor, generated skins and general undo/redo infrastructure need not precede the first unsaved proof. The broader Creator M3/G08 claims remain open until their own skin and portability requirements pass.

## 2. Baseline to preserve

The [audit](README.md#implemented-boundaries) establishes reusable foundations: bounded ZIP/parameter readers; AC3Db and admitted texture conversion into self-contained GLB; model selection and worker ownership; read-only source observations; conservative v6 hinge proposals; explicit independent-installation declarations; compiler/loader boundaries; immutable draft/revision storage; captured publication binding; exact SourceRef resolution; and detached published-payload verification.

Preserve those implementations and their negative tests. Source observations currently do **not** drive physical emission. Recognized ClearView flight/publication is intentionally refused. Published start checking and Home consumption are unfinished. The current fixed estimated trainer/4S package must not become the implicit import result.

## 3. Delivery sequence

| Phase | Existing steps | Concrete exit | Depends on |
| --- | --- | --- | --- |
| 0. Freeze one honest target | AC-CV-00; AC-05/12; release preflight | Eligibility ledger and buildable baseline; select a specimen or start one named prerequisite, then freeze its actual flight domain | Audit evidence |
| 1. Translate a complete definition | AC-CV-05/06; AC-05/06/13 | Source-aware candidate compiled through the ordinary v2 loader; all required inputs accounted for | Phase 0A decision and the named capability/data contract |
| 2. Complete the import review | AC-CV-02…05; AC-10/17 | Accurate appearance/controls, automatic resolved fields, bounded actionable gaps, reliable cancellation | Phase 1 contract; decoder/motion fixes can start earlier |
| 3. Qualify the actual flight route | AC-09/11/12; AC-CV-06/08 | Exact-context unsaved flight and lifecycle proof, with qualified/enforced numerical domain | Phase 0B domain and Phase 1 candidate; diagnostic work starts during Phase 0A |
| 4. Save and fly from Home | AC-13/14/18; AC-CV-07/08 | SourceRef-based Home selection, restart and exact published flight | Phases 2–3; existing resolver/storage reused |
| 5. Package and release | AC-19/20; AC-CV-07/09/14 | Portable clean-profile round trip and advertised desktop journeys, measured limits and support guide | Phase 4 |

Parallelize format/translation work and the bounded numerical/context investigation. Integration stays behind the same admission rules. Do not make a finished Home screen, every source format, or a general editor framework a prerequisite for learning whether one real candidate can fly.

### Phase 0 — Freeze the target and remove baseline ambiguity

**Owners:** AC/ClearView lead; physics/AS/energy/GP for the actual capability decision; CI owner for preflight.

1. Preserve the **22 UID sidecars already supplied upstream** through `2ec329f3` and `e0e71e24`. The [follow-up CI evidence](followup-02/evidence/ci-upstream.json) shows preflight now passes on `08f94826`, while other required jobs/export fail. Recheck release preflight and required CI for the eventual implementation candidate; route remaining provenance, numerical and export failures to their owners. The [original failed preflight](evidence/ci-baseline.json) is historical, not a request to redo resolved work.
2. Reuse the seven hash-verified archives and their 26-model inventory. Use **Extra 330 Red as the v6 translation-reference fixture**, and **Beginair/shared `PlaneParamModel.ac` as the v5 ambiguity fixture**. Neither is a qualified first-flight specimen. The [source facts](evidence/candidate-source-facts.json) prevent assumptions based on an aircraft name or an `electricMotor` node.
3. Continue from the [checked 26-model lexical ledger](followup-02/corpus-eligibility.md); its bounded corpus pass is available, but it does not complete physical eligibility. For one candidate, list every required OpenRC quantity/capability, exact source location, unit/frame confidence, disposition, missing dependency and supported law using the implementation guide's table. Include render/physics/collision correspondence, topology, controls, total mass and distribution, inertia, aero data, propulsion/energy, gear and starts. Record local-use availability separately from permission to redistribute a fixture or converted package.
4. Select an actual flight specimen only when that ledger supports it. Extra declares an 18×7 propeller; its `modelMass 10.1` has unresolved v6 units and its power curve does not establish a battery installation. Beginair declares 5 kg under the documented v5 convention; the current trainer domain is 1–4 kg. Neither can be made eligible by substituting the 4S/12×6 package or changing its mass. Reused auxiliary geometry also needs correspondence proof.
5. If no existing specimen fits, publish that result and choose the **smallest named capability/data extension**, with its owner and acceptance test, or identify a genuinely matching source. Do not continue cycling models or implement unrelated formats. Fixed gear or a different energy law may be a real first-import dependency; the previous gearless/electric milestone is not evidence those source packages fit it.
6. After selecting a specimen and resolving its named prerequisite, freeze the actual flight domain and numerical experiment before its qualification campaign: law/version, supported configuration range, backend, starts, contact/environment policy, input tapes, timesteps, metrics, tolerances and required evidence. Earlier diagnostics may test a bounded hypothesis but cannot claim qualification for an undecided candidate/domain. Use the current failed campaigns to choose discriminating tests, not another unbounded matrix by default.

**Exit 0A — eligibility decision:** checked-in source eligibility/semantic ledger and repaired release preflight; either select a supported specimen or name one bounded capability/data prerequisite and start that owner's packet. Phase 1 translation work and preview can proceed from this explicit decision.

**Exit 0B — flight-domain decision:** after that prerequisite, reassess/select the specimen and preregister its actual domain and numerical plan. Phase 3 qualification and player flight remain blocked until 0B; a named prerequisite is not a qualified aircraft. This gives missing-capability work a concrete place in the sequence rather than reopening source selection indefinitely.

### Phase 1 — Translate source data into an honest compiled candidate

**Owners:** AC/AS with physics, energy and GP where the ledger requires them.
**Seams:** `clearview/package.gd`, `params.gd`, `ac3d.gd`, `observations.gd`; `definition.gd`, `authoring.gd`, `compiler.gd`, `packages.gd`; `record_loader.gd`, publication/reopening consumers.

1. Capture and hash the selected physical dependencies, including configured v5 `paramModelName` and any v6 `fmodel.ac`/collision members whose physical role has been established. Filename presence alone is not a reference contract. Resolve them inside the selected model closure. Keep render, physical and collision roles distinct; missing members cannot be borrowed from another aircraft or the host filesystem. The bounded 128-row observation report is not the complete physical input tree.
2. Add a versioned mapping/adoption record. Each adopted target field retains source dialect, archive/member hash, section/key or object, raw value/unit, normalized value/unit/frame, mapping/equation version, evidence kind and any override. Preserve unsupported/unknown observations in the report. Hashes establish integrity, not truth or author identity.
3. Adopt the narrow set that completes the chosen candidate. Validate units, dimensions, axes and references before adoption. In particular:

   | Source information | Completion rule |
   | --- | --- |
   | Span, chord, geometry/marker coordinates | Prove scale, frame, role and source correspondence with asymmetric independent fixtures |
   | Total mass, CG and mass distribution | Keep total mass as a constraint; construct one non-duplicated inventory and valid inertia from supported evidence. A total mass alone cannot determine the inventory or tensor |
   | Propeller diameter/pitch, RPM, power/thrust tables | Convert explicit units; establish independent-variable axes, installation and target law. `maxThrust` or a watt table does not create motor, propeller or battery curves |
   | Control links/rates, hinges and mixers | Establish actual travel, timing, neutral, signs and aerodynamic authority. Visual rigging and source tuning rates are not servo timing |
   | Airfoil names, source coefficients and tuning offsets | Require a documented law/convention/domain mapping or leave unresolved. Independently check resulting forces/moments and control response at representative admitted states, including reference points, axis/sign, angle and rate conventions. Do not treat `pWingCG`/`pBodyCG` as measured CG or `xRotMass` as an inertia tensor |
   | Gear/contact geometry and repeated components | Preserve multiplicity and capability; use an owning supported contract or report the missing capability |

4. Extend authoring and compilation together. The current `manual/measured/estimated` authoring evidence and metadata-only observations do not implement borrowed/derived source adoption. New versions must be read, validated, saved and reopened deliberately; old definitions retain their existing bytes/meaning. The compiler emits ordinary `{value, unit, kind, source}` v2 quantities through the existing loader. No ClearView/aircraft-ID branch in the float64 kernel, no second physics catalog, and no unreviewed edit to the pinned loader.
5. Resolve source versus user conflicts explicitly. Re-import does not overwrite user corrections or a published revision. Repair the [reproduced inventory raw-edit loss](followup-02/README.md#1-invalid-inventory-edits-disappear-from-saved-drafts--confirmed-defect): document dirty state, draft/recovery and reopen must retain rejected text. Bind a new launch/publication to the current complete document state so an old accepted candidate cannot represent a later invalid edit. Track individual property overrides separately from evidence kind; the current whole-Estimated-item replacement policy cannot represent all source/user combinations. Changing an adopted physical field must change the intended physical bytes; editing a report label must not. [Implementation and counterexamples](implementation-guide.md#3-repair-raw-inventory-ownership-before-adding-source-prefill).

**Exit:** the chosen source produces a complete accepted candidate with a trace from every required output to a declaration, checked derivation, explicit user input or reviewed and labelled estimator for genuinely missing data. Independent known-answer tests prove unit/frame/mass/inertia/control/power mappings **and resulting aerodynamic forces/moments/control response** under the admitted laws. Use source-simulator comparisons where obtainable and permitted; otherwise state the unverified behavioral-equivalence limit. Numerical convergence and stable flight do not substitute for semantic mapping evidence. Counterexamples refuse unsupported semantics. A complete candidate is still not flight permission.

### Phase 2 — Finish the player's import review

**Owners:** AC/UI; converter owner for decoder and motion boundaries.
**Seams:** `aircraft_creator.gd`, `aircraft_creator_source_report.gd`, `aircraft_creator_installation.gd`, `clearview/motion.gd`, `images.gd`, source admission and visual bindings.

1. Populate all unambiguous supported fields automatically. The player reviews consequential choices and answers only actual missing/conflicting inputs. Do not send the player through a generic trainer questionnaire for data already present in the source. A source-only path makes zero synthetic physical substitutions. A qualified estimator may precomplete a genuinely absent field for explicit review without changing aircraft identity or topology; label the result partly estimated and retain its provenance. Replacing the installation or topology requires the distinct workflow and configuration identity.
2. Show one coherent state: ready for the next operation, needs named information, unsupported capability, or invalid source. List exact affected member/field and consequence. Distinguish optional visual omissions from missing flight-critical information. Keep unavailable aircraft visible and explain why.
3. Fix the reproduced motion-report gap: targeted `controlledPartMovement move` and `input` currently disappear from unresolved motion reporting. Keep a safe static part and name the unsupported request; never invent a rotation. Add v5 unmapped-motion reporting and implement only the bindings needed by the selected supported configuration, with independently checked pivots, signs and rest poses.
4. Fix cancellation through PNG validation/decode, package inventory and the final GLB admission boundary. The follow-up reproduces a cancelled final model returning successful partial inventory; cancellation must terminate the whole operation. The PNG probe proves a missing callback poll, not a measured hang. Measure actual cancel-to-idle latency and freeze a target before qualification. Late results must not replace the active source, retain a store lock, publish a revision or indefinitely prevent a new import. Preserve worker-generation guards and one cleanup owner. Decide/report nested-root discovery policy without indiscriminately importing sound parameter files. [Implementation and tests](implementation-guide.md#4-make-cancellation-terminal-and-discovery-explicit).
5. Compare original appearance and articulated motion against an independent source view/reference for the chosen fixture. Preserve original paint, UVs, transforms, opacity and required parts. Address the eight corpus visual refusals only when needed for the advertised subset; do not relax hostile-input bounds to raise a success count.
6. Every automatic resolution attempt must resolve a dependency, produce a specific question/refusal, or terminate on a cycle/budget. The same missing input cannot trigger another silent preset/solver attempt. A new user answer is a new generation; stale work is discarded.

**Exit:** a rendered 1080p journey for the chosen source, all resolved data preserved through draft reopen, accurate control/paint preview, bounded cancel/retry, and no hidden defaults. Headless widget tests alone do not close this phase.

### Phase 3 — Qualify one actual flight and its context

**Owners:** physics/AC with FL, energy and GP. Begin the numerical/context work during Phase 0.
**Seams:** `trial.gd`, `servo_interval_flight.gd`, `flight_session.gd`, `app_root.gd`, `main.gd`, logs/replay/reset.

1. Add the missing v4 boundary regression before changing admission. A compiled and frozen ordinary-source v4 candidate currently reaches `Trial.check_start` without explicit `gdscript_reference` selection and is unavailable. Select/validate the backend before session setup through one shared path. A reference default is not equivalent to the law's explicit-selection contract.
2. Resolve the real contact/environment mismatch. The new servo law refuses soft hull contacts and scenery/lake/RC-track contexts; Main normally enables soft hull contacts for interactive flight. Choose and expose a lawful first-flight policy with the owning tracks, install it before checking, and enforce it through the whole session. Do not silently switch global contact behavior or weaken the law to get past startup.
3. Define one immutable start request/receipt binding candidate/raw/source identity, start/trim profile, normalized field and relevant scenery/contact providers, effective weather, energy state, actual backend/law identity and timestep. Resolve CLI/Home options once; requested Root/Main properties are not evidence of installed context. Check and launch consume the same request. Changed field, weather, SOC, law, backend, tick or contact policy invalidates the receipt before flight. Reset and replay preserve the admitted configuration and identify deliberate changes. Cover the [source-traced technical-route field/weather mismatch](followup-02/README.md#source-inspected-runtime-defects) with an actual root/Main regression.
4. Close G05 for the stated domain with preregistered results. The historical 8/17 result and later **private, unadopted stage-wake max-piece candidate** with 58 accepted / 8 failed / 2 unresolved cells remain failed evidence. The latter result is not a measurement of the current production arrivals-only law. Preserve failing cells and unresolved comparisons. Any new law, tolerance or domain is a separate registered decision with enforcement and regression coverage; no retroactive pass. Do not assume every importer needs the newest servo law or that switching back to a legacy law supplies qualification.
5. Prove the real root/Main route: unsaved candidate → assessment → flight → reset/crash/log/checkpoint/replay as applicable → return to the same document. Verify control surfaces follow actual actuator state and the propeller follows the shaft. Failed startup must preserve the previous app state and live recording, and never publish a partial flight. The source-traced `remove_child(previous)` → `Main._exit_tree()` → log finalization path needs a Pause-route rollback test with a real log. Follow the [setup-order and transaction guide](implementation-guide.md#8-resolve-one-effective-start-request-then-prepare-and-commit); do not assume `reset()` already returns a commit receipt.
6. Replace recognized-source refusals only after the source-aware candidate, numerical domain and full-context route pass. Admission must be based on verified configuration/capabilities, not a user-editable label or a caller bypassing the UI. An admitted source-aware receipt/candidate cannot be cross-paired with changed or metadata-stripped source bytes. A newly imported GLB with all origin metadata removed cannot reliably reveal its former simulator origin; it must still satisfy the independently authored ordinary-source physical/qualification contract. Keep malformed, mismatched and unsupported-source counterexamples at Trial, publication and resolver boundaries.

**Exit:** retained complete flight/log/replay evidence for the exact first source/configuration and enforced domain, plus start-context mutation tests. Successful compiler, resolver, trim or script exit alone does not close G05/G06.

**Investigation stop rule:** one written hypothesis, one discriminating experiment and a retained verdict per iteration. After two failed iterations on the same hypothesis, the lead must choose a different bounded mechanism, an explicitly justified new domain proposal, or a named blocker. Do not keep producing numerical variants without an acceptance decision. This rule never converts failed qualification into permission to fly.

### Phase 4 — Publish once, select in Home, survive restart

**Owners:** AC/UI/FL, with existing Store and SourceRef owners.
**Seams:** `compiled_publication.gd`, `store.gd`, `source_ref.gd`, `source_resolver.gd`, `published_trial.gd`, `app_state/creator_selection.gd`, preferences, Home, root and Main.

1. Reuse captured publication's in-process definition→raw association and the Store root-index commit point. Reuse exact UUID/revision/record-hash resolution and presentation/source re-admission. The stored hash pair is not compiler authentication or proof of derivation: the [fresh cross-pair probe](followup-02/README.md#4-matching-hashes-do-not-prove-semantic-compilation--demonstrated-contract-limit) demonstrates that limitation while local capture remains correct. Before accepting an untrusted imported or restored pair for flight, regenerate with an installed reviewed verifier and pinned compiler/rule/package/data identities, comparing exact physical bytes, or implement another explicitly reviewed semantic-verification mechanism. Verify before sealing a new flight-eligible owner discards the definition inputs, or extend that owner deliberately. Explicitly inspection-only historical owners remain permitted without semantic proof. If historical verification is unavailable, retain inspection and offer recompile-as-new-revision or refuse flight; do not silently rewrite history. Preserve local capture's existing association and define where its trust ends. Do not build a parallel imported-aircraft store or resolve to a mutable latest revision.
2. Keep every runtime dependency in the immutable published closure: exact compiled physics, admitted visual bytes, placement, controls, appearance, adopted-source provenance and required referenced records. For full AC-CV-07 source closure, implement its separate bounded original-ZIP blob and receipt; capture each pack once and share it across model revisions, with quota accounting. Keep the existing admitted-GLB source slot and limits. Deleting/moving the downloaded file must not break flight or retained-source inspection. If original retention is deferred, state runtime-closure-only completion and leave the original-source/re-import part of AC-CV-07 open; hashes alone do not retain absent originals.
3. Define a closed, backward-compatible preferences branch for published Creator selection and connect Home, preview, defaults and Fly. The current selection-state helper is only a prerequisite; it is not a live Home consumer. Missing/corrupt revisions have an actionable unavailable state, never an unrelated stock-aircraft fallback. Preserve archive semantics: hide archived aircraft from normal listings while an already-pinned valid revision remains resolvable; archive is not revocation.
4. Route a resolved published owner through the same qualified context/lifecycle path as an unsaved candidate. `PublishedTrial.check_start` is currently an unconditional refusal. `prepare/verify` establish consistency only. Integrate consumers before changing that behavior.
5. Give legacy unbound Store v1 revisions an explicit policy: inspection/draft reopening, or a new bound revision after recompile/review/qualification. The resolver's ability to return historical bytes does not make them eligible for the new flight route. Never overwrite or silently trust the old record pairing.
6. Test process restart, edited draft versus old published revision, conflict, stale publication, second process/read-only lock, interruption/recovery, unavailable dependencies, reset and log identity. Cross-pair two individually valid same-UUID/same-law definitions and physics records with freshly recomputed hashes; semantic verification must refuse the mismatched pairing before granting source-aware flight. Preserve raw edits on failed save/load. Qualify platform durability separately from the local Linux headless Store test.

**Exit:** clean-profile import → review → unsaved flight → save → Home → process exit → restart → exact saved flight, with revision/physical/presentation identity assertions and deliberate missing/corrupt/stale counterexamples.

### Phase 5 — Portable packages and player release

**Owners:** AC/UI/release; platform, renderer and resource owners for their evidence.

1. Implement `.orcaircraft` export/import around the exact published dependency closure, including the permitted original-source closure required for the full AC-CV-07/AC-19 claim. A permitted runtime-only bundle must be labelled as such and does not close source-archive portability. Bound member paths, bytes and decompression; reject unsupported schema/law/capability versions and missing/corrupt dependencies before a transaction commits. Verify the received definition→physics relationship under Phase 4's untrusted-pair policy; a self-consistent hash manifest is insufficient. Same UUID/revision and same bytes is idempotent; different bytes is a conflict; import-as-copy assigns new identities. No partial overwrite of a working aircraft.
2. Run both journeys in packaged builds: a supported raw external ZIP → fly/save/restart, and an exported `.orcaircraft` → fresh profile/offline import → Home → fly. Do not require the editor, source checkout, external conversion tools, original ZIP path or developer caches.
3. Qualify each advertised Windows/Linux/macOS target, its actual renderer, file picker, read-only install, worker cancellation, lock/recovery, decoder behavior and resources at 1920×1080 first. Measure import duration, maximum UI stall, cancel-to-idle time, peak RAM/decoded images, resulting geometry/draw calls/VRAM and steady/peak frame time on named hardware. Freeze budgets before the release campaign; do not invent passing thresholds afterward.
4. Generate the support guide from a tested manifest: source dialect/archive/model hashes, adapter/law versions, exact supported capabilities/starts, optional omissions, unresolved-data behavior, platform evidence and credits/rights. Source download instructions and redistributed converted packages are separate deliverables; distribute only what permission allows. A public download is not a redistribution grant.
5. Run required CI and retain the packaged journey evidence. Mark only the tested subset available. Additional eight visual refusals, other aircraft families and later formats remain named follow-up work, not an implied universal compatibility claim.

**Exit:** a player can complete the advertised import journey without developer assistance, and the support manifest describes exactly what was tested. Full Creator M3 and physical calibration remain separate claims where their remaining gates are open.

## 4. Continuity and later formats

The existing [Flight Simulator import plan](https://github.com/bultodepapas/OpenRCsimulator/blob/2e83947f9c1d7acf257ff2971cee58151e569106/docs/plans/flight-simulator-aircraft-import.md) and [wizard plan](https://github.com/bultodepapas/OpenRCsimulator/blob/2e83947f9c1d7acf257ff2971cee58151e569106/docs/plans/flight-simulator-import-wizard.md) are on `plan/flight-simulator-aircraft-import-2026-11-16`, not audited main. Preserve their research and later adapter intent. Do not merge that branch's older runtime over the newer publication/resolver implementation.

Those plans investigate editable MSFS 2020 authoring sources and an explicitly estimated full-scale-to-RC design workflow. They do not establish that an arbitrary player-downloaded built package is editable, complete or redistributable. Reuse the closed source/adoption/flight/publication contracts from this closeout for later adapters. Before starting one, require an actual downloaded fixture, dependency/format proof, a semantic mapping and its capability delta. Scaling a full-scale model into a new RC design remains a distinct operation; it must not be presented as preserving its original physical installation.

## 5. Work packet and completion discipline

Each implementation packet names the existing AC/AC-CV step, owner, baseline commit, exact seams, one player-visible outcome, necessary schema change, smallest positive and negative tests, remaining boundary, and next packet. Update this plan's phase status and append dated evidence after integration; do not copy its status into a new competing backlog.

The immediate next packet is **Phase 0A's candidate-specific semantic/dependency table and named prerequisite**, using the completed lexical corpus inventory. Raw inventory persistence and cancellation repairs can proceed independently; the physics owner can investigate the bounded context/lifecycle defects in parallel. The UID omission is already resolved upstream. Then implement the smallest source-to-definition mapping justified by that decision, following the [implementation guide](implementation-guide.md). Do not start by rewriting the ZIP converter, SourceRef, Store, Home catalog or entire wizard.

A packet stops when its exit evidence is complete. Broaden tests only for a changed boundary, unresolved risk or required gate. Reopening a failed campaign, expanding a supported domain, or adding a source adapter requires a concrete new question and acceptance rule. Preserve failed evidence; move to the next dependency once the current one is resolved.

## 6. Implementation status

### Packet 1 — independent repairs (2026-11-17)

```text
Existing step / phase: AC-CV-02/04 and AC-10/14 (Phase 1–2 independent repairs); AC-09/11 and AC-13/18 boundary fixes (Phases 3–4 prerequisites).
Baseline and integrated commit: main f0ed7dec + audit branch efc93d07; branch feat/aircraft-import-closeout-2026-11-17.
Owner and changed source/schema boundaries:
  clearview/package.gd, images.gd, converter.gd, motion.gd — cancellation is terminal at every poll, including the last
    model, PNG decode and final GLB admission; complete nested models are listed unavailable with a reason;
    targeted move/input servos report "unsupported_servo_movement"; v5 models state that motion is unmapped.
  authoring.gd + ui/aircraft_creator.gd — the document owns rejected inventory text ("inventory_raw" snapshot member,
    written only when non-empty; format unchanged). It dirties the document, is backed up/saved/reopened, and
    blocks Authoring.compile() and therefore capture, publication and new trials.
  compiled_publication.gd / source_resolver.gd — verify_derivation() recompiles and compares exact raw bytes before
    a bound v2 owner is sealed.
  trial.gd / main.gd — Trial.check_start selects the same explicit reference backend as Main (FLIGHT_BACKEND);
    servo-law aircraft fly with hard hull contacts, as checked.
  app_root.gd / main.gd — workshop trials detach the previous flight tentatively (its log stays open on failure,
    is finalized at commit) and assess/launch the previous flight's installed field and weather.
Player-visible outcome: cancel always cancels; no silently missing nested model or moving part; a typo in an
  inventory mass survives save/reopen and blocks flight until corrected; a failed trial start keeps the F10 log.
Source fixture and semantic assumptions: synthetic ZIP/AC3D/PNG fixtures in the existing tests; no corpus archive.
Positive and counterexample checks (Windows 11, Godot 4.8.beta2, headless, worktree candidate):
  test_creator_clearview_{readers 91, visual 51+, motion 224+, jpeg 363}; test_creator_trial; test_creator_compile_binding 91;
  test_creator_source_ref 240; test_creator_published_trial 62; test_creator_store 509; test_creator_clearview_ui 68;
  test_creator_persistence_ui 104; test_creator_ui 201; test_creator_publication_ui 28; test_creator_flow;
  test_workshop_integration (rollback keeps the same log for a later tick; commit finalizes it). All 0 failures.
Observed result and exact remaining limitation: no source-aware physical adoption, no qualified flight domain and
  no Home consumer. Cancel-to-idle latency is unmeasured. Property-level override ownership, wingspan/datum raw
  ownership and a full effective start request/receipt (lake, track, collision, SOC, timestep) remain open.
  The CLI field/weather fix aligns check and launch with the previous flight's installed context but has no
  dedicated direct-launch regression yet. Cross-platform byte determinism of compile_candidate is unproven.
Next packet, dependency and exit condition: Phase 0A candidate table for Extra 330 Red (needs the hash-pinned archives),
  then Phase 1 source adoption; Phase 3 start request/receipt with a direct --landscape/--wind regression.
```

### Packet 2 — ClearView models test fly (2026-11-17)

Owner request: make downloaded ClearView aircraft importable and flyable now. This is a deliberate policy change ([decision](../../../DECISIONS.md)): a labelled independent estimate may test fly before source-faithful adoption. It does not close Phase 1 (source adoption), Phase 3 (G05/G06 qualification) or Phase 4 (Home/publication).

```text
Existing step / phase: AC-CV-02..05, AC-09/10 (Phase 2 review; Phase 3 unsaved trial for the estimated configuration only).
Baseline and integrated commit: packet 1 on feat/aircraft-import-closeout-2026-11-17 (uncommitted).
Owner and changed source/schema boundaries:
  clearview/setup.gd (new) — documented ClearView render frame (metres, nose -X, up +Y) and a leading edge estimated
    by cutting triangle edges at 0.35/0.65 of the half-span (propeller, disk, wheel, gear, strut and smoke nodes
    excluded; sweep extrapolation capped). Elevon models are refused.
  authoring.gd apply_clearview_setup — one explicit, revision-guarded action. It fills only unresolved placement and
    empty fields (marked Estimated), proposes the inventory, keeps estimated tail volumes and aspect ratios inside the
    package domain, balances to static margin 0.15 (battery, then a visible "Nose balance weight (estimated)"),
    and records the existing independent-installation declaration.
  source_installation.gd / trial.gd / authoring issues — ClearView flight is refused only under the servo-interval
    law. freeze pins the declaration in the trial identity; verify refuses a ClearView trial without it.
  converter.gd — undecodable texture formats (GIF) are omitted with a note; invalid or oversized images still fail.
  UI — "Set up for flight automatically" with a confirmation; Save aircraft explains that publication is unavailable.
Player-visible outcome: Import ZIP -> Set up for flight automatically -> Test fly; Save draft; restart; Open -> Test fly.
Source fixture: CVplanesPk7 (16 local folders, zipped under tmp/, not redistributed). Not adopted: ClearView
  coefficients, modelMass (Yak 54 Lightning declares 10.8; estimate 3.6 kg), motors, gear.
Corpus result (headless, Windows): 12/16 convert visually (14/16 with the GIF fix). Flying: Yak 54 Lightning (airborne;
  hand launch honestly refused). Refused with reasons: span < 0.9 m (Yak 55 Electric, Y-Wing, VJ-101, Waterflyer),
  span > 2.2 m (V-22, U32 Pitts, Yak-55), elevons (Zagi x2, XF5U, Waterflyer), propeller offset (X-wing, X-35B),
  verNumber 0 params (XFV-1, VJ-101 VTOL), ambiguous marker (Votec 351, refusal kept deliberately).
Real app (Windows, 1920x1080, local session): imported Yak 54 Lightning, setup, test fly 120 fps, roll/pitch response,
  Save draft, process restart on the same profile, Open draft, test fly again (same aircraft id).
Checks: new test_creator_clearview_setup (21); updated source_installation (90), clearview_visual (54), language;
  creator trial/ui/persistence/flow/publication/compile_binding/source_ref/servo_document/clearview_ui/motion, 0 failures.
Remaining: Home listing and publication of ClearView aircraft (Phase 4); wider package domain or source adoption for
  small/large/elevon models; verNumber 0 dialect; render comparison against ClearView itself.
```

### Packet 3 — ClearView corpus robustness (2026-11-17)

```text
Existing step / phase: AC-CV-02..04 (conversion robustness), AC-09/10 (estimated setup), owner request "import all".
Source fixture: the owner's seven CVPlanesPk1..7 ZIPs (132 model roots; local only, hashes in the run log, not redistributed).
Changes:
  setup.gd — the wing span is measured from the wing (rotors and props excluded). Outside the 0.9-2.2 m domain the
    model is proposed at the nearest supported size, as an explicitly scaled configuration stated first in the dialog.
    A missing propeller is stated.
  authoring.gd — when setup chose the size, a too-heavy or overpowered small model is tried larger (<= 5 attempts, from
    the same state); a tail-heavy estimate whose battery is already at the nose gets the largest permitted estimated
    tailplane; the nose weight never exceeds the package mass range.
  converter.gd / ac3d.gd / motion.gd / params.gd — non-fatal with counted notes: missing textures, up to 32
    self-intersecting or untriangulable polygons, float32 slivers, subdivided surfaces (control mesh), ambiguous
    helper markers (hidden, part static). Float32 tolerance 0.1 % of a part. Flat v0-v4 parameters accepted.
    Hostile/limit guards (size, work, pixels, 1e8 offsets, >128 meshes) unchanged.
Corpus (headless Windows, conversion -> setup -> compile -> frozen trial -> airborne start check):
  before this packet 42/132 fly; after 105/132 fly; 131/132 convert visually.
  Refused with reasons: 15 jets (nose estimate > 1 m from the balance point), 8 elevon/flying wings, 3 unbalanceable
  estimates (A6-Zero, Fokker DR1, Stearman), 1 autogyro, 1 model over 128 meshes (Hindenburg).
Real app (1080p): PA-Cub (3.48 m) proposed at 2.16 m with the stated scale, test flight 98 fps.
Checks: 20 Creator/ClearView/Workshop suites, 0 failures.
Remaining: jet/ducted-fan and flying-wing packages (physics owner); Home/publication (Phase 4); source adoption (Phase 1).
```

### Packet 4 — park jets and balance (2026-11-17)

```text
Existing step / phase: AC-CV-05/06 estimate quality; Phase 0A evidence on source mass.
Changes:
  data/creator/power-electric-4s-800kv-apc12x6-pusher-estimated-v1.json (new) — same donor hardware, "layout": "pusher";
    the mirrored APC pusher shares the tractor CT/CP tables (as the stock single_pusher record does).
  packages.gd — registry entry; is_pusher/aft_sign; motor ahead of a pusher hub. compiler.gd — single_pusher capability,
    firewall and crash-hull spinner point ahead/behind by layout, nose-hub domain only for tractors.
  authoring.gd — the power package is a document choice (snapshot member written only for the pusher; unknown ids
    refuse the draft). The ClearView setup picks the pusher when no propeller node exists and places the hub 0.04 m
    behind the wing root at the fuselage centre line. A tail-heavy estimate that the mass range cannot ballast is
    tried at 90 % size (setup-chosen size only, labelled scaled).
Findings: v5 modelMass is unreliable (5.2 kg shared default; e.g. 1.48 m Twinstar II declares 3.0 kg), v6 plausible
  (EasyStar 0.70 kg, Sky Surfer 1.0 kg). Not adopted.
Corpus (7 packs, 132 roots): 105 -> 122 fly. Refused with reasons: 8 elevon flying wings (tailless estimator needed),
  Lockheed XFV-1 tail-sitter, Kellett autogyro, Hindenburg airship (>128 meshes).
Real app (1080p): F-104 set up as a pusher park jet (hub behind the wing), test flight at 30 m, 16.8 m/s.
Checks: test_creator_clearview_setup 34 (pusher compile, firewall/motor ahead of hub, offset aft of CG, draft
  round trip, unknown package refused) plus the regression batch below.
Next (physics owner): a tailless/elevon estimated airframe package; an EDF/turbine estimate; pusher wash and wake.
```

### Packet 5 — helicopters recognised; donor adapters designed (2026-11-17)

```text
Done: params.gd defaults modelName to the ClearView body.ac for old flat dialects (v0-v4, mostly helicopters), with a
  note; setup.gd reads the receipt modelType and refuses helicopters (0) instead of estimating them as aeroplanes.
  Helicopter corpus (CVHeliPak1/2 + four MC Exceed Roboheli, 41 roots): 0 -> 37 import visually; 4 refuse
  (material limit, unsafe member path, render precision). Plane corpus unchanged at 122/132.
Probe evidence (WorkshopCompiler on stock donors): moonrunner_x99 (Skywalker X8: tailless, elevon, single_pusher)
  and sebart_avanti_s_a200 (turbine jet) compile only at scale 1.0 — the Workshop refuses scaling for the
  electric_prop and turbine families. xcell_60_research and hx700_electric_3d_experimental are helicopter-format
  records, not openrc-aircraft v2.
Design for the next packets (each a labelled, different configuration, never the ClearView flight model):
  1. Donor airframe for aircraft: definition member `donor {id}` (new definition/snapshot version with a
     compatibility table), a Creator `compile_donor` that re-identifies the exact stock record (no edits), and a
     placement whose unit_scale fits the visual to the donor span. Flying wings -> X8 (elevon bindings from the
     ClearView LElevon/RElevon frames); jets -> Avanti S (turbine, fuel, flaps, retracts). Trial identity pins the
     donor id and record hash; publication stays closed.
  2. Rotorcraft: a Creator helicopter trial that installs the existing helicopter session with a donor by size
     class (HX700 electric 3D or XCell 60) and binds the ClearView main/tail rotor render groups
     (`mainrotor.*` renderGroupName) to the rotor visuals.
  3. Scaling donors (physics owner): propeller and turbine scaling laws for the Workshop compiler, so donors can
     match each model's size instead of resizing the visual.
  4. Landscapes: CVLandPk1/2 hold 22 ClearView sceneries (landscape-params.txt). They need a landscape importer
     owned by the landscape track, not the aircraft importer.
```

### Packet 6 — donor flights: helicopters and flying wings (2026-11-17)

```text
Owner request: make the remaining imported models useful and flyable; labelled donor configurations accepted.
Helicopters (implemented by a helper, reviewed and re-verified by the lead): clearview/heli_donor.gd,
  helicopter_main.gd `creator_visual`, Creator offer "Fly as a helicopter (X-Cell .60 donor)", AppRoot
  donor trial. The ClearView model sits on the donor CG and skid plane; it is scaled only when its rotor is more
  than 1.5x off the donor rotor; physics bit-identical to the stock X-Cell route. Rotor geometry is static
  (disc/blade parts switch by rotor speed). test_creator_clearview_heli 37/0; real Roboheli flight at 1080p.
Flying wings: clearview/donor.gd chooses the stock MoonRunner X99 (Skywalker X8: tailless, elevons, electric
  pusher, 6S) for elevon models; Main `donor_visual` builds the imported appearance fitted to the 2.1 m donor span
  on the exact stock physics; the automatic setup offers it instead of refusing elevons; AppRoot routes
  `creator_donor` through the shared donor-trial lifecycle (tentative detach, rollback, Return to Workshop).
  Zagi (real app, 1080p) climbs on the X8 6S power at 118 fps; XF5U, Predator, TwinJet and Waterflyer
  (headless, 480 ticks) fly without faults. test_creator_clearview_donor 6/0; Creator, UI, language, Workshop
  integration and Main startup suites 0 failures.
Plane corpus: 122 estimated + 8 flying-wing donors = 130 of 132 roots fly (remaining: Kellett autogyro,
  Hindenburg airship). Helicopter corpus: 37 of 41 import and fly on the X-Cell donor.
Limits: donors fly their own mass, inertia and power; the imported model only changes appearance (stated
  in every confirmation). Elevon visuals are static; publication and Home are not available for donor trials.
Next: helicopter donor by size class (HX-700 electric); moving elevons/rotors bound to the donor's surfaces;
  Avanti S turbine donor for jets as an alternative to the pusher park-jet estimate; landscape importer.
```

### Packet 7 — robustness and realism audit (2026-11-17)

```text
Method: Good Enemy source review of the whole candidate (helper, source-read-only); an RC-physics realism
  review (helper, with sources); a mutation fuzz (540 runs: Yak 54, Zagi and Roboheli packages with corrupted
  numbers, deleted/duplicated lines, truncation, byte flips and 1e6/1e-6/0/-1 geometry scales through package ->
  convert -> setup -> compile, flying-wing donor and helicopter donor build); a handling sweep of all 122
  estimated corpus aircraft and six stock references through the real session loop (trim, level-trim speed
  envelope, 10 s hands-off, 10 s power-off, 6 s full throttle, full aileron and elevator pulses).
Fuzz: 0 script errors, 0 hangs, no accepted non-finite or absurd scale.
Robustness defects fixed:
  - apply_clearview_setup: a size fit that had not converged by the fifth attempt restored the empty draft
    and still reported success; the last attempt now keeps its state. A refused declaration now rolls back
    placement, values, inventory and the power package; an invalid typed span is no longer overwritten.
  - Donor wing flights: the CG used the stock X8 model datum, shifting the imported appearance; the stock
    shadow proxy, stock smoke, scenario binding and Companions treated the flight as a stock X8 flight.
  - Helicopter donor: the visual scale was unbounded (a degenerate rotor gave ~1e9) and a rotor-less model was
    shown unscaled; rotor-less models are now sized by their length and scales beyond 20x are refused.
  - Untyped flight payloads: the source is type-checked before use (AppRoot and HeliDonor.is_helicopter).
  - Omitted textures share the 16-image limit; _fit_estimates and the model-type reader guard non-finite input.
Realism (handling sweep, before this packet):
  - Span <1.3 m: 21 of 22 diverge hands-off within 10 s (bank 72-180 deg, 36-166 m lost); mid 1.3-1.9 m: 2/38;
    >=1.9 m: 0/62. Stock Stik 6S: bank 14 deg. Cause: the single 4S/800 kV/12x6 installation (~1 kg) makes
    small estimates 2-3x too dense (WL 5.1-7.6 kg/m2, relative density ~4.8 vs ~1.3), the opposite of real
    models (wing loading rises with size). Fix: the automatic setup no longer chooses a span under 1.6 m
    (Authoring.SETUP_MIN_SPAN_M); smaller models fly as a labelled larger version, and a long model grows only
    until its body is 1.85 m from the datum (Setup.MAX_REACH_M). After: of 34 small models re-flown, divergent
    hands-off 17 -> 2 (A-10, Beginair, Cessna: bank 72-83 deg diving -> 25-27 deg climbing); WL 3.8-5.6 kg/m2.
  - Every estimate shares one AR-5 rectangular wing, 20/20/25 deg throws and the same package: same-size
    models fly almost identically (2.16 m: roll 80-101 deg/s, Vmax 23-25 m/s vs stock Extra 300S 391 deg/s).
  - Gliders get trainer drag (L/D ~8); jets fly as 12x6 pusher park jets (Vmax 23-33 m/s); biplanes and
    twins get one wing and one nose/aft propeller. Flipper and Harrier keep a pitch-sensitive divergence
    (q ~190 deg/s) after resizing.
  - Donors fly their own mass and size: a 0.48 m Waterflyer is a 2.1 m X8, a 450-size heli an X-Cell .60.
Next realism batch, by pilot-visible impact: measured planform (trailing edge, taper) instead of the AR-5
  rectangle; a small power package (3S, ~9 in) and a large one (6S) chosen by size, then lower the 1.6 m
  floor; a fast jet pusher; category throws (aerobatic, glider) where the source gives a signal; Froude-
  scaled donors (small wing, small electric heli).
```

### Packet 8 — realism batch: measured planform, size classes, EDF stand-ins (2026-11-17)

```text
Owner request: fix the packet 7 realism findings. Supersedes the 1.6 m setup floor.
Planform: Setup.planform() cuts the wing at 0.3/0.45/0.6/0.75 of the half-span (edges, not vertices), takes the
  contiguous section at the leading edge's height, fits root/tip chord by least squares (outlier stations
  dropped; more than one disagreeing station keeps the template) and dihedral from the outboard stations;
  taper 0.62-1 and AR 4.2-6.8 are kept inside the airframe domain. A second wing layer at three or more
  stations 0.25-1.6 chords apart is a biplane: one equivalent wing of 1.7x one wing's area. Examples:
  Cessna AR 5.6 taper 0.81 dihedral 3.7; Yak 54 AR 4.4 dihedral 0; F-86 1.4 deg; Stearman/DR1/Pitts biplanes.
Size classes (Authoring.setup_classes): 0.7-1.45 m conventional-parkflyer-estimated-v1 (foam densities, 9 g
  servos; calibrated on EasyStar II, FMS Ranger 1220, Apprentice 15e, FMS P-51D 1100) with 3S 1250 kV 9x6
  (SunnySky X2212-10 winding data) or its pusher; 1.45-2.2 m the trainer with 4S 800 kV 12x6. Jets: 4S
  1900 kV 6x4.5 pusher (16 N static, 70 mm EDF class) and from 1.9 m 6S 1200 kV 7x5 (27.5 N, 90 mm class),
  both tuned with the runtime electric solver; T/W 0.52-0.85 on the corpus jets. Drafts store
  `airframe_package` only for the park-flyer class. Good Enemy review: 8 findings; fixed the empty class list,
  the -1 class index, the pusher hub past the tail, the overpowered first jet package (27 N), the canard case
  and the dialog line; planform cost measured at <=153 ms on the largest corpus model (10.6k triangles).
Handling sweep, 122 corpus aircraft, before (packet 7 baseline) -> after:
  <1.3 m (22): mass 1.47-2.20 -> 0.79-1.38 kg; WL 5.1-7.6 -> 2.8-5.0 kg/m2; stall ~9.2-10.8 -> 6.8-8.7 m/s;
    flown at their own size; violent departures (>60 m lost in 10 s hands-off) 15 -> 2 (MiG-15, VJ-101).
  1.3-1.9 m (37): violent 1 -> 0; >=1.9 m (63): 0 -> 0. No NaN or failed flight; 0 script errors.
  Remaining: 18 small and 3 mid models still bank past 45 deg within 10 s hands-off. Traces show a slow spiral
  (about 5 deg/s; stock Stik recovers via sideslip and dihedral, light low-dihedral foamies do not), consistent
  with their measured 0-3.7 deg dihedral and low mass; not a solver fault. Full-throttle hands-off roll-off on
  A-10, Yak 55, Harrier, VJ-101 VTOL, X-wing (prop torque on light airframes).
Limits: one borrowed nondimensional aero set (UltraStick25e) for every class; new propellers reuse the APC
  Sport 11x6 tables; EDF stand-ins have no duct, inlet or exhaust model; throws stay 20/20/25 deg.
Next: per-category throws/rates where the source gives a signal; Froude-scaled donors (small flying wing,
  small electric heli); a measured-chord tailplane.
```
