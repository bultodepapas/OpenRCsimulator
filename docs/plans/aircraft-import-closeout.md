# Aircraft import closeout

**Date:** 2026-11-17. **Audited source:** `2a3cf04dbbdaf486b9c9c8e983463d828f90c64a`.
**Status:** audit complete; usable source-aircraft import is not complete.
**Owners:** Aircraft Creator / ClearView, with the existing physics, AS, UI, FL, GP and energy owners at their shared boundaries.

This is the execution order for finishing **download → import → fly → save → restart → fly**. The [Creator plan](aircraft-creator.md) continues to own AC-00…25 and G01…G10; the [ClearView subplan](clearview-aircraft-import.md) owns AC-CV-00…14 and format contracts. Phase numbers below sequence those existing steps; they are not another step registry. This document owns the import closeout order and acceptance. Existing plans retain broader Creator features and later aircraft families. Current code and checked results determine implemented status.

Read the [dated audit](../research/aircraft-creator/import-closeout-2026-11-17/README.md) for findings, the [verification record](../research/aircraft-creator/import-closeout-2026-11-17/verification.md) for actual runs and missing tests, and the [agent handoff](aircraft-import-agent-handoff.md) before starting a work packet. Do not repeat the audit as the next development task.

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

The [audit](../research/aircraft-creator/import-closeout-2026-11-17/README.md#implemented-boundaries) establishes reusable foundations: bounded ZIP/parameter readers; AC3Db and admitted texture conversion into self-contained GLB; model selection and worker ownership; read-only source observations; conservative v6 hinge proposals; explicit independent-installation declarations; compiler/loader boundaries; immutable draft/revision storage; captured publication binding; exact SourceRef resolution; and detached published-payload verification.

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

1. Repair the baseline's **22 missing tracked Godot UID sidecars** with the pinned editor, commit them with their owning scripts, and run release preflight. The [baseline CI evidence](../research/aircraft-creator/import-closeout-2026-11-17/evidence/ci-baseline.json) shows this stops application/export jobs. This is build hygiene, not importer or flight qualification.
2. Reuse the seven hash-verified archives and their 26-model inventory. Use **Extra 330 Red as the v6 translation-reference fixture**, and **Beginair/shared `PlaneParamModel.ac` as the v5 ambiguity fixture**. Neither is a qualified first-flight specimen. The [source facts](../research/aircraft-creator/import-closeout-2026-11-17/evidence/candidate-source-facts.json) prevent assumptions based on an aircraft name or an `electricMotor` node.
3. Perform one bounded eligibility pass over this existing corpus. For the candidate, list every required OpenRC quantity/capability, exact source location, unit/frame confidence, disposition, missing dependency and supported law. Include render/physics/collision correspondence, topology, controls, total mass and distribution, inertia, aero data, propulsion/energy, gear and starts. Record local-use availability separately from permission to redistribute a fixture or converted package.
4. Select an actual flight specimen only when that ledger supports it. Extra declares an 18×7 propeller; its `modelMass 10.1` has unresolved v6 units and its power curve does not establish a battery installation. Beginair declares 5 kg under the documented v5 convention; the current trainer domain is 1–4 kg. Neither can be made eligible by substituting the 4S/12×6 package or changing its mass. Reused auxiliary geometry also needs correspondence proof.
5. If no existing specimen fits, publish that result and choose the **smallest named capability/data extension**, with its owner and acceptance test, or identify a genuinely matching source. Do not continue cycling models or implement unrelated formats. Fixed gear or a different energy law may be a real first-import dependency; the previous gearless/electric milestone is not evidence those source packages fit it.
6. After selecting a specimen and resolving its named prerequisite, freeze the actual flight domain and numerical experiment before its qualification campaign: law/version, supported configuration range, backend, starts, contact/environment policy, input tapes, timesteps, metrics, tolerances and required evidence. Earlier diagnostics may test a bounded hypothesis but cannot claim qualification for an undecided candidate/domain. Use the current failed campaigns to choose discriminating tests, not another unbounded matrix by default.

**Exit 0A — eligibility decision:** checked-in source eligibility/semantic ledger and repaired release preflight; either select a supported specimen or name one bounded capability/data prerequisite and start that owner's packet. Phase 1 translation work and preview can proceed from this explicit decision.

**Exit 0B — flight-domain decision:** after that prerequisite, reassess/select the specimen and preregister its actual domain and numerical plan. Phase 3 qualification and player flight remain blocked until 0B; a named prerequisite is not a qualified aircraft. This gives missing-capability work a concrete place in the sequence rather than reopening source selection indefinitely.

### Phase 1 — Translate source data into an honest compiled candidate

**Owners:** AC/AS with physics, energy and GP where the ledger requires them.
**Seams:** `clearview/package.gd`, `params.gd`, `ac3d.gd`, `observations.gd`; `definition.gd`, `authoring.gd`, `compiler.gd`, `packages.gd`; `record_loader.gd`, publication/reopening consumers.

1. Capture and hash the selected physical dependencies, including the configured v5 `paramModelName`, v6 `fmodel.ac` and collision/contact declarations when present. Resolve them inside the selected model closure. Keep render, physical and collision roles distinct; missing members cannot be borrowed from another aircraft or the host filesystem.
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
5. Resolve source versus user conflicts explicitly. Re-import does not overwrite user corrections or a published revision. Retain invalid raw edits and make the candidate unavailable until corrected. Changing an adopted physical field must change the intended physical bytes; editing a report label must not.

**Exit:** the chosen source produces a complete accepted candidate with a trace from every required output to a declaration, checked derivation, explicit user input or reviewed and labelled estimator for genuinely missing data. Independent known-answer tests prove unit/frame/mass/inertia/control/power mappings **and resulting aerodynamic forces/moments/control response** under the admitted laws. Use source-simulator comparisons where obtainable and permitted; otherwise state the unverified behavioral-equivalence limit. Numerical convergence and stable flight do not substitute for semantic mapping evidence. Counterexamples refuse unsupported semantics. A complete candidate is still not flight permission.

### Phase 2 — Finish the player's import review

**Owners:** AC/UI; converter owner for decoder and motion boundaries.
**Seams:** `aircraft_creator.gd`, `aircraft_creator_source_report.gd`, `aircraft_creator_installation.gd`, `clearview/motion.gd`, `images.gd`, source admission and visual bindings.

1. Populate all unambiguous supported fields automatically. The player reviews consequential choices and answers only actual missing/conflicting inputs. Do not send the player through a generic trainer questionnaire for data already present in the source. A source-only path makes zero synthetic physical substitutions. A qualified estimator may precomplete a genuinely absent field for explicit review without changing aircraft identity or topology; label the result partly estimated and retain its provenance. Replacing the installation or topology requires the distinct workflow and configuration identity.
2. Show one coherent state: ready for the next operation, needs named information, unsupported capability, or invalid source. List exact affected member/field and consequence. Distinguish optional visual omissions from missing flight-critical information. Keep unavailable aircraft visible and explain why.
3. Fix the reproduced motion-report gap: targeted `controlledPartMovement move` and `input` currently disappear from unresolved motion reporting. Keep a safe static part and name the unsupported request; never invent a rotation. Add v5 unmapped-motion reporting and implement only the bindings needed by the selected supported configuration, with independently checked pivots, signs and rest poses.
4. Fix cancellation through PNG validation/decode and the final GLB admission boundary. The audit proves a missing callback poll, not a measured hang. Measure actual cancel-to-idle latency and freeze a target before qualification. Late results must not replace the active source, retain a store lock, publish a revision or indefinitely prevent a new import. Give each edit/import generation a token and one owner for worker cleanup.
5. Compare original appearance and articulated motion against an independent source view/reference for the chosen fixture. Preserve original paint, UVs, transforms, opacity and required parts. Address the eight corpus visual refusals only when needed for the advertised subset; do not relax hostile-input bounds to raise a success count.
6. Every automatic resolution attempt must resolve a dependency, produce a specific question/refusal, or terminate on a cycle/budget. The same missing input cannot trigger another silent preset/solver attempt. A new user answer is a new generation; stale work is discarded.

**Exit:** a rendered 1080p journey for the chosen source, all resolved data preserved through draft reopen, accurate control/paint preview, bounded cancel/retry, and no hidden defaults. Headless widget tests alone do not close this phase.

### Phase 3 — Qualify one actual flight and its context

**Owners:** physics/AC with FL, energy and GP. Begin the numerical/context work during Phase 0.
**Seams:** `trial.gd`, `servo_interval_flight.gd`, `flight_session.gd`, `app_root.gd`, `main.gd`, logs/replay/reset.

1. Add the missing v4 boundary regression before changing admission. A compiled and frozen ordinary-source v4 candidate currently reaches `Trial.check_start` without explicit `gdscript_reference` selection and is unavailable. Select/validate the backend before session setup through one shared path. A reference default is not equivalent to the law's explicit-selection contract.
2. Resolve the real contact/environment mismatch. The new servo law refuses soft hull contacts and scenery/lake/RC-track contexts; Main normally enables soft hull contacts for interactive flight. Choose and expose a lawful first-flight policy with the owning tracks, install it before checking, and enforce it through the whole session. Do not silently switch global contact behavior or weaken the law to get past startup.
3. Define one immutable start request/receipt binding candidate/raw/source identity, start/trim profile, normalized field and relevant scenery/contact providers, weather, energy state, actual backend/law identity and timestep. Check and launch consume the same request. Changed field, weather, SOC, law, backend, tick or contact policy invalidates the receipt before flight. Reset and replay preserve the admitted configuration and identify deliberate changes.
4. Close G05 for the stated domain with preregistered results. The historical 8/17 result and later **private, unadopted stage-wake max-piece candidate** with 58 accepted / 8 failed / 2 unresolved cells remain failed evidence. The latter result is not a measurement of the current production arrivals-only law. Preserve failing cells and unresolved comparisons. Any new law, tolerance or domain is a separate registered decision with enforcement and regression coverage; no retroactive pass. Do not assume every importer needs the newest servo law or that switching back to a legacy law supplies qualification.
5. Prove the real root/Main route: unsaved candidate → assessment → flight → reset/crash/log/checkpoint/replay as applicable → return to the same document. Verify control surfaces follow actual actuator state and the propeller follows the shaft. Failed startup must preserve the previous app state and never publish a partial flight.
6. Replace recognized-source refusals only after the source-aware candidate, numerical domain and full-context route pass. Admission must be based on verified configuration/capabilities, not a user-editable label or a caller bypassing the UI. An admitted source-aware receipt/candidate cannot be cross-paired with changed or metadata-stripped source bytes. A newly imported GLB with all origin metadata removed cannot reliably reveal its former simulator origin; it must still satisfy the independently authored ordinary-source physical/qualification contract. Keep malformed, mismatched and unsupported-source counterexamples at Trial, publication and resolver boundaries.

**Exit:** retained complete flight/log/replay evidence for the exact first source/configuration and enforced domain, plus start-context mutation tests. Successful compiler, resolver, trim or script exit alone does not close G05/G06.

**Investigation stop rule:** one written hypothesis, one discriminating experiment and a retained verdict per iteration. After two failed iterations on the same hypothesis, the lead must choose a different bounded mechanism, an explicitly justified new domain proposal, or a named blocker. Do not keep producing numerical variants without an acceptance decision. This rule never converts failed qualification into permission to fly.

### Phase 4 — Publish once, select in Home, survive restart

**Owners:** AC/UI/FL, with existing Store and SourceRef owners.
**Seams:** `compiled_publication.gd`, `store.gd`, `source_ref.gd`, `source_resolver.gd`, `published_trial.gd`, `app_state/creator_selection.gd`, preferences, Home, root and Main.

1. Reuse captured publication's in-process definition→raw association and the Store root-index commit point. Reuse exact UUID/revision/record-hash resolution and presentation/source re-admission. The stored hash pair is not compiler authentication or proof of derivation: `valid_pair` checks structure/scope/UUID/law. Before accepting an untrusted imported or restored pair for flight, regenerate with the applicable pinned compiler/dependencies and compare exact physical bytes, or implement another explicitly reviewed semantic-verification mechanism. If historical verification is unavailable, retain inspection and offer recompile-as-new-revision or refuse flight; do not silently rewrite history. Preserve local capture's existing association and define where its trust ends. Do not build a parallel imported-aircraft store or resolve to a mutable latest revision.
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

The immediate next packet is **Phase 0's eligibility ledger and baseline UID repair**, with a parallel bounded physics/context investigation. Then implement the smallest source-to-definition mapping that the ledger justifies. Do not start by rewriting the ZIP converter, SourceRef, Store, Home catalog or entire wizard.

A packet stops when its exit evidence is complete. Broaden tests only for a changed boundary, unresolved risk or required gate. Reopening a failed campaign, expanding a supported domain, or adding a source adapter requires a concrete new question and acceptance rule. Preserve failed evidence; move to the next dependency once the current one is resolved.
