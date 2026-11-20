# Aircraft import: implementation guide

**Reviewed production source:** `08f948265d40d83fbb4726a302b9e1c9490ccfce`, 2026-11-17.
**Purpose:** turn the [closeout phases](closeout-plan.md) into bounded development changes. That plan owns order, status and acceptance; this guide supplies implementation seams, proposed contracts and regression recipes. Existing AC/AC-CV IDs remain authoritative. [Follow-up evidence](followup-02/README.md) distinguishes executed observations from source inspection.

The production `.gd` and `app/data/` files did not change between the original audit and this source. Upstream supplied the missing UID sidecars and additional translations. Its release preflight passed; full CI and export did not. Do not spend the next packet recreating those sidecars or claiming the importer now flies.

**All pseudocode below is a proposed contract, not an existing API or a drop-in patch.** Names in capitals describe work to implement. Keep the actual repository's result envelopes, float64 physical math, resource limits and ownership rules.

## 1. Choose the next change by its boundary

| Boundary | Existing code to extend | Deliverable for the existing phase |
| --- | --- | --- |
| Source identity and candidate choice | `clearview/package.gd`, `params.gd`, selected physical members | Phase 0A: one field-by-field disposition and a named capability/data decision |
| Raw edits and provenance | `authoring.gd`; UI inventory callbacks and draft/recovery paths | Phases 1–2 / AC-10/14: rejected input survives and individual overrides have explicit ownership |
| Physical adoption | `definition.gd`, `compiler.gd`, `packages.gd`; ordinary `record_loader.gd` | Phase 1 / AC-CV-05/06: source-derived candidate with no hidden installation substitution |
| Decoder/inventory completion | `clearview/images.gd`, `package.gd`, `converter.gd`, worker generation handling | Phase 2: cancellation is terminal; unsupported requests remain visible |
| Flight preparation | `trial.gd`, `app_root.gd`, `main.gd`, `sim/flight_session.gd` | Phase 3: assessment and flight consume the same effective request; failed startup preserves the prior flight |
| Saved semantic verification | `compiled_publication.gd`, `store.gd`, `source_resolver.gd`, `published_trial.gd` | Phase 4: a received definition/physics pair is verified before flight admission |
| Home and portable consumer | `app_state/creator_selection.gd`, preferences/Home, existing Store and SourceRef | Phases 4–5: exact revision selection, process restart and clean-profile bundle import |

Creator-relative paths in this table are under [`app/workshop/creator/`](../../../../app/workshop/creator). Root/Main are under `app/`; the wizard is [`app/ui/aircraft_creator.gd`](../../../../app/ui/aircraft_creator.gd). Read the consumers before changing a format. Do not build a second compiler, library or physics catalog.

Two small repairs can proceed while the physical owner resolves Phase 0A: raw inventory persistence (§3), and cancellation propagation (§4). Neither repair grants source-aware flight. The bounded corpus investigation has already produced a [26-model ledger](followup-02/corpus-eligibility.md); continue with a candidate's semantics instead of repeating the format survey.

## 2. Turn source selection into a decision

Use Extra 330 Red as the first v6 **translation reference**, with Beginair as the shared-template counterexample. Neither has been qualified for first flight. The current trainer package admits **1–4 kg**; all 20 v5 source declarations exceed 4 kg. V6 mass units remain inferred. V-22 and B-52 explicitly declare two and eight motors. Propeller and energy correspondence remain unresolved even for superficially plausible masses. [Exact declarations and limits](followup-02/corpus-eligibility.md).

For the chosen source, create one row per required target property or capability:

| Required column | Example / rule |
| --- | --- |
| Target | Stable definition property or capability, including each repeated component |
| Source identity | ZIP hash, selected root, member path/hash, dialect, section/key/occurrence or AC object |
| Source meaning | Raw declaration, units, reference frame, reference point, independent variable and confidence |
| Disposition | Direct translation; supported derivation; user correction; genuinely missing; conflicting; unsupported law |
| Mapping | Reviewed rule/version, inputs, output unit/frame, assumptions and applicability domain |
| Evidence | Borrowed declaration, derived result, measured input or attributed estimate; never infer measurement from a filename |
| Missing dependency | Exact absent member, semantic definition, physical data or shared capability, with owner |
| Acceptance | Independent known answer and at least one ambiguity/out-of-domain counterexample |

Finish this table with a decision: an eligible specimen, or **one named prerequisite** that makes the next attempt meaningful. For example, “interpret this installation's power table and implement its supported energy law” is actionable; “support more aircraft” is not. A mass-domain increase alone cannot repair unknown propulsion, gear or aerodynamic meaning. Do not relabel a gas/fixed-voltage installation as a finite 4S battery to fit the current package.

Use the source's meaning before considering a missing-data estimate. A visual mesh, a shared parameter mesh, a total mass and a power curve do not independently determine aerodynamic coefficients, inertia, motor electrical parameters or battery chemistry. Where information is genuinely absent, a reviewed estimator needs a stated domain and visible provenance. The player should answer a concrete remaining question; data already present and understood must populate automatically.

## 3. Repair raw inventory ownership before adding source prefill

### Current defect and exact seams

The checked [inventory probe](followup-02/probes/inventory_edit_probe.gd) drives the real mass `LineEdit`, saves through Store and reopens the draft. Invalid input remains in UI `_item_texts`/`_item_invalid`; `Authoring.set_item_raw()` returns before `_touch()`. `has_unsaved_changes()`, `snapshot()`, `_draft_record()` and `_write_backup()` therefore miss the edit. `_adopt_document()` clears those UI buffers. Saving succeeds and reopening silently restores the previous number.

Implement the repair in [`authoring.gd`](../../../../app/workshop/creator/authoring.gd) and the UI together:

1. Make the document own raw text, parsed validity and the last accepted value for every editable inventory property. Extend the same ownership to any remaining UI-only physical numeric inputs; audit datum/scale separately before claiming them fixed. The widget renders document state.
2. An invalid or empty edit changes document revision/fingerprint and dirty state. Save draft and automatic recovery retain it. Document-bound compilation, publication and creation of a new trial reject unresolved invalid physical text, including callers that bypass the UI.
3. Keep the old number only as an explicitly stale preview. It must not become an accepted flight input while the document displays a rejected replacement.
4. Extend snapshot/restore deliberately; do not append unvalidated UI caches to a Store record. Old snapshots retain their existing interpretation. Failed restore leaves the prior document intact.
5. Persist edits before attempting departure. Failed save/recovery cannot clear the dirty flag or discard raw text. Reopening reproduces the invalid field and its actionable error.

```text
ON_PROPERTY_EDIT(property_id, text, unit):
    parsed = PARSE_AND_VALIDATE(text, unit, property_contract)
    document.raw[property_id] = {text, unit, parsed.status}
    document.ownership[property_id] = USER_OVERRIDE
    if parsed.accepted:
        document.accepted[property_id] = parsed.exact_value
    document.revision += 1              # also for invalid / empty edits
    INVALIDATE_DEPENDENTS(property_id)
    EMIT_DOCUMENT_CHANGED()

FREEZE_PHYSICAL_INPUTS(document):
    if any required raw property is invalid, unresolved or stale:
        return NAMED_FIELD_REFUSAL()
    return VALIDATED_IMMUTABLE_INPUTS(document)

COMPILE_CURRENT_DOCUMENT(document):
    state_id = CAPTURE_REVISION_AND_COMPLETE_DOCUMENT_IDENTITY(document)
    inputs = FREEZE_PHYSICAL_INPUTS(document)
    if inputs refused: return inputs
    candidate = COMPILE_VALIDATED_INPUTS(inputs)
    if document no longer matches state_id: return STALE_DOCUMENT
    return CANDIDATE_WITH_DOCUMENT_RECEIPT(candidate, state_id)
```

The current `Compiler.compile_candidate(definition)` sees accepted values, not the document's raw-edit state; `Trial.freeze(payload)` receives a candidate, not the current document/revision. Add an atomic document-bound preparation boundary and require a **new launch/publication of that document** to match its receipt. Moving UI buffers alone cannot make those existing APIs detect a stale candidate. A separately supplied valid definition remains compilable, and an already frozen independent trial keeps its own identity; neither should pretend to represent a later edited document.

### Separate ownership from evidence kind

Today, `propose_inventory()` replaces items marked Estimated, and the UI explicitly explains that policy. Editing an Estimated wing mass to 0.75 kg and pressing Propose restores 0.504 kg. That is a **documented current behavior**, not a newly discovered silent-overwrite defect.

Source adoption needs finer ownership. Preserve an edited mass while allowing its unedited position to update. An override lock answers “may automatic work replace this property?” Evidence answers “where did this value come from?” They are independent. Do not mark an entire item Measured because the player edited one coordinate, or change an explicitly estimated origin into a measurement. Record vector components separately when their origins differ; the current `_VECTORS` grouping cannot represent every mixed-origin case without an explicit composition rule.

**Regression recipes:** saved valid draft → invalid mass-only edit → dirty + backup + save/reopen → same invalid text; empty/nonfinite input; failed save; valid candidate → invalid edit without changing the accepted number → attempted direct document-bound compile/publication/new launch with the old candidate refuses; edit mass only → recompute geometry → mass retained, untouched position updated; explicit reset-to-source removes only that override. Extend the authoring cases in `test_creator_trial.gd` and the real controls in `test_creator_persistence_ui.gd`. Do not merely assert a new dictionary contains the string.

## 4. Make cancellation terminal and discovery explicit

[`Package.inspect_archive()`](../../../../app/workshop/creator/clearview/package.gd) currently turns a cancelled last member read into a failed model, then returns overall success because an earlier root succeeded. The new probe reproduces this at callback poll four with two valid roots. Ordinary malformed-model results can coexist with other usable models; cancellation is an operation-level outcome and must propagate immediately.

```text
INSPECT_PACKAGE(archive, token):
    outcomes = []
    for candidate in BOUNDED_CANDIDATES(archive):
        if token.cancelled: return CANCELLED
        read = READ_BOUNDED_MEMBER(candidate, token)
        if read.cancelled or token.cancelled: return CANCELLED
        outcomes.append(VALIDATE_MODEL_OR_DIAGNOSTIC(read))
    if token.cancelled: return CANCELLED
    return COMPLETE_INVENTORY(outcomes)

APPLY_WORKER_RESULT(result, generation):
    if generation != active_generation or token.cancelled:
        RELEASE_RESULT_AND_WORKER()
        return
    APPLY_ONLY_COMPLETE_RESULT(result)
```

Current cancellation diagnostics reuse `SOURCE_INVALID`; decide whether to add a typed internal cancellation outcome or retain that public envelope with an explicit token. Do not classify arbitrary failures by translated message text. Preserve the existing UI generation checks: the API probe does **not** establish that the UI applies a late cancelled result.

Extend the existing PNG/final-GLB cancellation work to every expensive stage and the last-member boundary. Test pre-cancel, first/middle/last member, decode, final admission and close/retry. Measure the declared cancel-to-idle limit in packaged builds; callback counts alone are not a latency test. Bound discovery work and poll even when a candidate will be skipped.

The same probe shows a valid `Outer/Inner` model disappears when a valid `Outer` exists. Preserve the protection against nested sound `params.txt` files. Decide and document whether nested real models are unsupported or selectable; either outcome should name the skipped/ambiguous candidate. Do not automatically import every nested parameter file or call an intentional unsupported layout a decoder corruption.

## 5. Build physical adoption from complete source inputs

The current [`Observations`](../../../../app/workshop/creator/clearview/observations.gd) report is deliberately small: selected keys, 128 rows, bounded raw strings, possible omission and declared archive association. Its checked owner binds a report to an admitted source object; it does not prove original ZIP membership or physical truth. Do not use this display report as the complete physical syntax tree.

Keep `Params.read()` and bounded archive resolution. Add a selected-model physical input owner that captures the necessary original bytes and hashes before interpretation. Preserve dialect, duplicates, section/component namespaces and dependency roles. Resolve configured v5 `paramModelName`; investigate v6 `fmodel.ac`/collision references without assuming a detected filename is authoritative. The shared `PlaneParamModel.ac` used by 15 pack models is a required ambiguity counterexample.

```text
ADOPT_SELECTED_SOURCE(capture, rules, user_edits):
    CHECK_ARCHIVE_AND_SELECTED_ROOT_IDENTITIES(capture)
    inputs = CAPTURE_REQUIRED_PHYSICAL_DEPENDENCIES_WITH_LIMITS(capture)
    ast = PARSE_COMPLETE_SELECTED_INPUTS(inputs)  # not the 128-row UI report
    roster = RESOLVE_DECLARED_COMPONENT_IDENTITIES(ast)
    for target_property in REQUIRED_PROPERTIES(roster, target_law):
        if user_edits.has_invalid(target_property): return FIELD_ERROR
        if user_edits.owns(target_property):
            resolved = VALIDATE_USER_VALUE_AND_LINEAGE(target_property)
        else:
            matches = APPLICABLE_REVIEWED_RULES(ast, target_property)
            resolved = UNIQUE_SUPPORTED_MAPPING_OR_NAMED_GAP(matches)
        RETAIN_VALUE_UNIT_FRAME_AND_LINEAGE_TOGETHER(resolved)
    VALIDATE_TOPOLOGY_AND_PHYSICAL_CONSTRAINTS()
    return VERSIONED_SOURCE_AWARE_DEFINITION()
```

An optional missing-data estimator is a separate explicit resolution of a named gap. It cannot override conflicting source facts or choose a different installation. A dependency cycle, ambiguity or exhausted work budget produces one final diagnostic; it does not restart with a generic package.

Implement and test these mappings before broadening the source subset:

| Input | Required implementation / independent oracle |
| --- | --- |
| Geometry and coordinate markers | Declare source-to-body frame, scale, datum and handedness. Use asymmetric non-axis-aligned fixtures; verify points, directions, hinges and moments independently. Render bounds alone do not establish physical dimensions. |
| Mass and inertia | Use total mass as a constraint, avoid counting power hardware twice, define component mass/stations and tensor convention. Verify CG and positive physical inertia from independent inputs. Do not map `xRotMass` directly to a tensor element. |
| Repeated installations | Preserve all named motor/propeller/surface identities and references. Missing v5 sectioned roster means unknown, not zero engines. Unsupported multiplicity names the required capability. |
| Propulsion | Confirm units and table axes before conversion. Once inch semantics are confirmed, 18×7 becomes 0.4572 m × 0.1778 m; that arithmetic does not establish motor, battery or thrust laws. Preserve the source installation or refuse its missing law/data. |
| Aerodynamics | Establish reference area/span/chord, local axes, coefficient signs, angle/rate conventions and operating range. Compare independent expected forces/moments/control response at admitted states. Similar coefficient names are insufficient. |
| Controls and gear | Distinguish visual motion, physical surface travel, servo dynamics, mixing and contact behavior. Named gear visuals are not by themselves a working contact model; confirmed functional gear cannot silently disappear. |

Freeze the numeric value, units, rule/dependency identity and provenance together. Ordinary aircraft v2 quantities retain their closed `{value, unit, kind, source}` shape; `source` is a string. Use a stable lineage reference with a validated manifest, or a separately reviewed schema extension. Do not insert arbitrary dictionaries into that slot. Keep display wording outside physical identity; changes to adopted values, rules, source identities or evidence may intentionally change the compiled identity.

## 6. Change writers and readers as one versioned contract

| Current carrier | Current handling to inspect | Required migration proof |
| --- | --- | --- |
| Observations v1 / review policy v1 | `inspect`, `from_source`, `validate`, `digest`; report truncation/omission | Full physical capture is distinct; rejected/missing report data cannot turn into physical defaults |
| Creator document v1–v4 | `snapshot`, `restore`, `fingerprint`, dirty state; v4 takes precedence over optional source/install fields | Explicit allowed combinations; old meanings preserved; raw invalid inventory and property ownership round-trip |
| Creator definition v1–v4 | `validate_complete`, evidence paths/kinds, source/install/servo markers | New adoption format or reviewed extension validates complete lineage and mixed-origin fields |
| Compiler and package data | `compile_candidate`, `_study`, `_inventory_entries`, `_record`, `_stated*`; current metadata removal and ID-keyed package cache | Adopted values reach physical emission; package/rule/data hashes bind the result, not just a logical ID |
| Revision v1 / bound revision v2 | `CompiledPublication.capture/valid_pair/match_document`; Store publish/load/marker checks | Trusted local capture stays intact; changed formats cannot bypass the flat-writer restrictions or become legacy by stripping one marker |
| Resolver and UI reopen | `SourceResolver.resolve/_legacy_servo_marker`; UI `_finish_open` version list | Unknown future versions fail closed; all independent carriers agree; semantic verification precedes sealing any new flight-eligible owner, while explicitly marked historical inspection-only resolution remains available |
| SourceRef v1 and published trial v1 | Exact revision/hash reference; `prepare/verify/check_start` | Version only what changes; unchanged reference shape may stay v1. Payload qualification remains separate from source resolution. |

Write the compatibility table and tests **before** emitting a new format. Exercise markers independently in definition, snapshot, raw physics and receipt: a newer declaration in any carrier must not be read as legacy because another marker was removed. Cover unknown formats/profiles, absent source bytes, truncated observations and mismatched rule/package hashes.

## 7. Verify received definition-to-physics correspondence before sealing

The [semantic-pair probe](followup-02/probes/semantic_pair_probe.gd) compiles two valid same-UUID/same-law definitions with servo times 0.14 s and 0.20 s. It pairs definition A with physics B and recomputes the hashes. Current `valid_pair`, `Binding.matches` and `match_document` accept that association; trusted `capture(A)` still returns A's correct bytes. This is the documented limit of local association checks, not evidence that today's unavailable published flight accepts an external bundle.

Place semantic verification in the received-record path while exact definition bytes and all required inputs remain available. [`SourceResolver.Resolved`](../../../../app/workshop/creator/source_resolver.gd) currently retains a definition hash, not the definition/dependency closure. For the new flight-eligible path, verify **before `_seal()`**, or deliberately extend the owner with immutable checked inputs and a receipt. Calling a verifier after those inputs have been discarded is not an implementation. A separately marked `legacy-unbound` inspection-only owner may still be sealed without semantic proof; resolution alone never grants flight.

```text
VERIFY_RECEIVED_REVISION(record):
    CHECK_CLOSED_FORMATS_AND_ALL_CARRIER_MARKERS(record)
    CHECK_PRESENT_BLOB_HASHES(record)
    if SUPPORTED_LEGACY_POLICY_REQUIRES_INSPECTION_OR_NEW_REVISION(record):
        return INSPECTION_ONLY_OR_NEW_REVISION_REQUIRED
    CHECK_REQUIRED_DEPENDENCY_CLOSURE(record)
    verifier = LOOK_UP_INSTALLED_REVIEWED_COMPILER(record.compiler_identity)
    if verifier unavailable: return INSPECTION_ONLY_OR_NEW_REVISION_REQUIRED
    CHECK_PINNED_RULE_PACKAGE_AND_DATA_IDENTITIES(record, verifier)
    expected = verifier.COMPILE(record.definition, record.checked_dependencies)
    if expected.raw_bytes != record.raw_bytes: return SEMANTIC_MISMATCH
    return SEALED_SEMANTIC_RECEIPT(exact_input_and_output_identities)
```

A compiler profile string or two matching hashes do not establish derivation. Do not execute compiler code supplied by an aircraft package. Support known historical verifiers as installed reviewed code, or offer an explicit new revision after recompilation/review. Historical inspection policy can handle absent historical compiler/dependency identities; it must not reinterpret a corrupted or incomplete current-format bundle as valid legacy input. Keep old immutable records available for inspection; do not rewrite history. Semantic correspondence and numerical/flight qualification are separate checks.

Extend `test_creator_compile_binding`, `test_creator_source_ref`, Store and future bundle tests with the exact same-UUID cross-pair **and freshly recomputed hashes**. Include unchanged package ID with changed package bytes, unavailable historical compiler, valid local capture and immutable prior revision. A test that only corrupts a hash does not cover this boundary.

## 8. Resolve one effective start request, then prepare and commit

Two additional source traces justify integration tests: direct technical CLI flights can assess default/calm context while Main loads a different landscape/wind; detaching a prior Main before candidate acceptance runs `_exit_tree()` and stops its flight log. These are [source-derived findings](followup-02/README.md#source-inspected-runtime-defects), not newly executed full-app journeys.

Use `CreatorTrial.freeze/verify` for unsaved candidates. Saved selection goes through `SourceRef` → `SourceResolver.resolve` → `PublishedTrial.prepare/verify`. Preserve current ClearView/published-flight refusals until their owning gates pass.

Freeze a request **after** CLI/Home options are resolved: exact candidate/source/revision; field/landscape; start and trim profile; full effective weather; SOC/fuel/energy choice; actual backend/laws/timestep; input and any supported failure/out-of-trim settings; installed lake/track/collision/soft-contact policy and provider identities. Do not read stale requested properties such as `previous.weather_config` as proof of installed conditions.

Respect existing Session ordering. Explicit backend selection belongs before `setup()`. `setup()` itself resets. Several context setters require an initialized session, and failure setup requires ready tick-zero physics. Install contexts/settings at their supported boundaries, select the requested start, and perform the final reset. A refactor that moves every setter before setup is incorrect.

```text
request = RESOLVE_AND_FREEZE_EFFECTIVE_LAUNCH_OPTIONS(verified_candidate, options)
assessment = PREPARE_DISPOSABLE_SESSION(request)
receipt = CAPTURE_AND_CHECK_TICK_ZERO_CONTEXT(assessment, request)
start_result = ASSESS_START_AND_OPTIONAL_CLIMB_OUT(assessment, request)
if receipt or start_result refused: KEEP_EXISTING_FLIGHT_AND_EDITOR()

candidate = PREPARE_CANDIDATE_WITHOUT_CLOSING_PREVIOUS_FLIGHT(request)
if candidate not ready or INSTALLED_CONTEXT(candidate) differs from receipt:
    DISPOSE_CANDIDATE_AND_RESTORE_PRESENTATION()
    KEEP_PREVIOUS_SESSION_AND_RECORDING_LIVE()
else:
    COMMIT_SCREEN_CONTROLLER_AND_WORLD_OWNERSHIP_ONCE(candidate)
    RETAIN_REQUEST_AND_RECEIPT_FOR_RESET_AND_REPLAY()
```

Compare actual `weather_configuration()`, `lake_context()`, `rc_track_context()`, `collision_world()`, `stage_backend_status()`, `sim.dt()`, data identity and `trace_meta()`/`checkpoint()` at the same tick-zero boundary after final setup/reset. Preserve that receipt separately from any subsequent hand-launch climb-out result: the disposable assessment can advance up to 720 ticks, so its post-probe checkpoint is not the candidate's initial state. Compare the declared physical/context identities, with session-specific metadata handled explicitly. `environment.identity()` alone omits the collision world. `reset()` currently returns `void`; `last_transition()` gives generation/kind, not an acceptance/observer receipt. Add an explicit result boundary if needed; preserve the distinction between refusal before commit and a committed transition with an observer fault.

Do not “suspend” Main with `remove_child(previous)` while expecting `_exit_tree()` to leave its `flight_log` stream open. The F10 ORFL `flight_log` and T-key `recorder` are separate owners; inspect both lifecycle contracts. Candidate failure must preserve scene, controllers, editor state, presentation and the existing log stream. Define successful temporary-trial recording policy separately. Do not fix rollback by silently starting a second file and pretending the first never closed.

**Required integration cases:** Home and Pause routes; actual CLI landscape plus nonzero wind; each start; head/tail wind; changed SOC/backend/timestep/contact provider; candidate initialization failure with a prior active log; return/reset/crash; committed observer fault; saved exact-revision restart. Use an ordinary legacy/v1 Creator fixture for the CLI mismatch so v4's separate backend/calm-law refusal does not mask that case. A useful fault injection sets the previous flight's `lighting_config` to `{mode: "invalid"}` in a disposable test: scratch qualification ignores lighting, candidate startup rejects it, and the old log must still accept a later tick. Restore the injected setting. The test is a rollback counterexample, not a claim a normal UI generates invalid lighting.

Extend `test_creator_trial`, `test_creator_flow`, `test_main_startup_cleanup` and `test_flight_reset_transaction`; add saved-Home integration when that consumer exists. Preserve stock hand-launch behavior until a separately versioned Creator launch law defines local-air calculations.

## 9. Review the packet, then stop

Before merging each implementation packet, retain the baseline, changed contracts, source/dependency identities, smallest meaningful positive/counterexample runs and the exact remaining gate. The [handoff](agent-handoff.md) supplies that record. Freeze inputs before tests; inspect checked engine logs, not only exit codes.

Stop when the packet's exit is proven. Do not add a broad wizard rewrite, every codec, all aircraft families, a generic provenance framework or a new catalog to a bounded repair. Numerical and real exported player journeys remain separate owning gates. The final proof is the advertised source aircraft completing import, flight, save, Home selection and restart in the packaged application.
