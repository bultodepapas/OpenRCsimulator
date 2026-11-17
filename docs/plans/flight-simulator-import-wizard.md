# Automatic Flight Simulator import wizard

**Owner:** Aircraft Creator / AC-FS. **Direction clarified:** 2026-11-16. **Status:** proposed product and engineering contract; no automatic importer implemented. The [feature plan](flight-simulator-aircraft-import.md) owns scope, work packages and release gates. This document owns automatic orchestration, conditional questions and editing behavior. The [conversion specification](../research/aircraft-creator/flight-simulator-2026-11-16/conversion-and-scaling.md) owns mathematical semantics; the [24 investigations](../research/aircraft-creator/flight-simulator-2026-11-16/follow-up-24-investigations/README.md) supply evidence.

## 1. Product contract

The player selects a Flight Simulator aircraft source. OpenRC detects its supported format and dependencies, interprets its configuration and visual structure, translates units and coordinates, converts model/materials, constructs an RC installation, binds supported moving parts and checks the result **inside the application**. The desired outcome is an editable aircraft ready for the supported OpenRC flight experience.

The wizard asks only for information or choices that cannot be resolved from the selected source, retained user choices or an applicable declared RC profile. A complete, uniquely resolvable supported source with an applicable profile reaches the final result with **zero follow-up questions**. Source selection and the final **Save aircraft / Fly** action are not missing-data questions. The user can always inspect or change automatically resolved values before finishing or later in Workshop.

Readable configuration plus a prepared GLB remains a useful development fixture and optional advanced/recovery input. The first completed automatic feature must also accept an advertised supported Flight Simulator source directly, including its qualified buffers, textures and declarative model references, without requiring the player to install a converter, run a script, edit CFG or export a GLB manually. Narrow the advertised source profile when necessary; optional manual recovery cannot satisfy this automatic acceptance journey.

“Understand” means versioned semantic adapters, checked conversions, qualified geometric/rig inference and explicit target-construction policies. No cloud service or generative model is required for the first feature. Application-owned scripts, libraries or bundled workers may implement the pipeline; imported source code remains inert.

## 2. Automatic pipeline and responsibilities

| Stage | Application responsibility | When a question is needed |
| --- | --- | --- |
| Select and capture | Inspect a directory/ZIP or selected package roots, detect supported content, capture a bounded immutable dependency closure | Several indistinguishable aircraft/variants; required base or texture outside selected roots |
| Resolve source | Apply the version-qualified package/overlay/variant rules; retain effective and overridden values and actual source identity | Conflicting declarations or unresolved precedence affect the chosen result |
| Normalize visuals | Select a uniquely evidenced suitable exterior/LOD; convert qualified buffers, textures, materials, transforms and neutral pose; re-admit the output GLB | Unresolved model/pose/paint choice with a supported alternative; an unsupported essential feature instead yields its specific limited/unavailable result |
| Translate and construct | Map known geometry/units/frames; choose the applicable RC profile and target scale; build target inventory, power, controls and supported aerodynamic inputs | No applicable profile or an unresolved target choice, missing geometry or conflicting requested value |
| Bind movement | Use qualified node/behavior mappings and preserve pivots; verify source-to-output correspondence and expected signs/poses | Ambiguous role, hinge, direction or unsupported binding; no arbitrary name-based guess |
| Check candidate | Validate the whole authoring document, compile/load exact physical bytes, evaluate coupled domain and readiness, prepare the preview | A correctable input conflict remains; unsupported capability instead yields its specific unavailable result |
| Finish | Show the editable result, estimates and material omissions; save through the existing immutable Store/Home path; use existing checked launch | User chooses to change a value or start; no repetitive confirmation of already resolved fields |

Dependencies are searched deterministically only within the roots the player selected. Selecting an encompassing package root permits bounded lookup within it. Ask to locate another root only when needed; do not scan the whole installation or download missing aircraft automatically.

The normal product path owns its required conversion runtime. AC-FS-04 must select and qualify redistributable libraries or packaged workers, exact builds and recipes; AC-FS-11 proves them in clean exported builds without authoring tools installed. Existing Blender/MCX/manual workflows remain references and optional recovery routes. External tool availability must not decide whether an otherwise advertised automatic source works. Reuse the existing [tool evaluation](../research/aircraft-creator/flight-simulator-2026-11-16/follow-up-24-investigations/tooling-and-fixtures.md), and keep all normalized outputs behind Creator admission.

The adapter owns source inspection and visual normalization; an automatic target planner owns typed value resolution, dependencies and unresolved decisions; the existing Authoring/Definition/Compiler path owns accepted target inputs and physical emission. The wizard controller sends intents and renders the planner's questions/readouts; UI widgets never contain independent physics or conversion formulas. A readiness coordinator composes the existing candidate, trial and Store/Home contracts. These are proposed responsibilities under AC-FS-02…11, not new implemented APIs.

Resolution uses deterministic dependency order and finite profile/candidate choices. Any numerical fitting or repeated candidate search needs an explicit iteration/time budget and stop reason. Stop with the specific unresolved decision when bounded resolution cannot finish; do not cycle presets or alter locked values until a candidate happens to pass.

## 3. Resolution policy and provenance

Resolve a typed field or capability in this order, subject to validity and matching semantics:

1. Preserve the user's explicit target override or selection, then revalidate it against changed dependencies. An override does not turn an unsupported topology into a supported one.
2. Use unambiguous source declarations that actually describe the target quantity. Retain units, frame, active conditions and provenance.
3. Apply documented unit/frame conversions, deterministic derivations and qualified geometric or rig inference. Preserve the entire source-to-target transformation and uncertainty chain.
4. Apply an applicable versioned RC profile or estimator for target design choices and missing target data. Every supplied value is visible and editable through its supported authoring control; estimates remain estimates.
5. Ask the smallest actionable question that resolves the remaining decision, or report a capability that the implementation cannot provide.

Precedence does not override field roles: full-scale source mass is not an RC inventory mass, and a full-scale span does not specify the player's desired RC size. For the first conventional target, an explicit default mode such as **Create an RC version** may supply a declared target-size policy, estimated airframe construction and supported finite-electric package. Show the resulting span, flying mass, equipment and estimated behavior at the final preview. The user's clarified automatic-RC workflow permits this disclosed design policy without separate permission dialogs for every estimate. A generic replacement wing/tail or silent deletion of another engine is outside that policy.

The profile is versioned data, not constants scattered through UI code. Its target-size/default equipment choices, estimator assumptions, supported source/target topology, units, dependency versions and qualified coupled domain must be fixed before its acceptance campaign. A user preference may choose another supported profile. If no profile fits the actual geometry and selected intent, report why; changing uniform scale cannot repair an out-of-range aspect ratio. A package matching only mass and span is insufficient.

Complete the nonphysical defaults too. Populate an editable aircraft display name from the selected variant's supported display metadata, then its source basename, then **Imported aircraft**. The versioned naming rule removes control characters, trims whitespace, truncates to the shared Store name bound and validates the result; an empty result falls through to the next candidate. Retain the original metadata as an observation. Display names are not aircraft identity and need not be unique. Create/persist the ordinary aircraft UUID once for a new import; resume/retry retains it. Reimport preserves an explicit user name. An invalid user-entered name remains an edit to resolve, rather than being silently replaced. Missing or malformed source display metadata must not introduce a naming question in the zero-question journey.

| Condition | Behavior |
| --- | --- |
| Valid and uniquely translated | Apply automatically and show its origin in the editable result |
| Valid estimate from applicable RC profile | Apply automatically with an estimated origin and visible profile; preserve assumptions |
| Genuinely absent source field | Use a documented version-specific source default only where its semantics permit, otherwise a valid target estimate or a focused question |
| Several valid choices | Use an explicitly selected/persisted policy if it resolves the choice; otherwise ask with the alternatives |
| Invalid token, conflicting units/overlays or invalid user edit | Keep the diagnostic and raw value; resolve or explicitly exclude it from the target mapping with a recorded decision. Never silently relabel it missing |
| Unsupported encoding, topology, source runtime dependency or physical law | Explain the unavailable capability; sliders cannot manufacture support. Preserve an editable limited result only where valid |

Each automatic field records its producer rule/profile and version, input identities, evidence kind, mapping assumptions, current override and dependent outputs. Numerical precision is not confidence: exact arithmetic on estimated inputs retains its estimated ancestry. Do not add informal confidence percentages that imply measurement.

Current [Definition](../../app/workshop/creator/definition.gd) and [Authoring](../../app/workshop/creator/authoring.gd) do not implement this full contract: evidence is restricted, omitted evidence can become manual, and `_origin` mainly tracks estimates. AC-FS-02/07 must version the shared authoring/observation contract and readers, preserving source/derived/estimated/manual origins into emitted quantities. Raw template compilation must not falsely label automatic inputs player-entered. Source observations remain immutable; an edit changes the target override, not the original source.

## 4. Conditional wizard and controls

```mermaid
flowchart TD
    A["Select aircraft source"] --> B["Resolve and convert automatically"]
    B --> C{"Unresolved decision?"}
    C -->|"Yes, correctable"| D["Ask only for missing choices"]
    D --> B
    C -->|"No"| E["Validate exact candidate"]
    C -->|"Unsupported capability"| H["Keep supported result and explain"]
    E -->|"Input needs correction"| D
    E -->|"Ready"| F["Editable preview, save and fly"]
    E -->|"Required gate unavailable"| H
```

This is a branching wizard, not a fixed tour through every Creator page. Show progress while work runs. If everything is resolved, go directly to the result. Otherwise group related unresolved values into the smallest useful screen, in dependency order: source/variant and units → orientation/source scale → target size → mass/equipment/balance → ambiguous controls. Recompute remaining questions after each accepted answer; never ask for a value that the previous answer now determines.

| Question / editable value | Preferred control | Expected behavior |
| --- | --- | --- |
| Aircraft, variant or livery | Thumbnail selector with detected/default choice | Skip if uniquely resolved; changing it refreshes dependent source closure |
| Missing base or texture root | Locate folder/file action with the missing item named | Resume only affected resolution; keep earlier valid choices |
| Source physical scale or orientation | Unit selector, exact dimension entry and axis/landmark preview | Ask only for ambiguous calibration; keep model-unit calibration distinct from target RC scale |
| Target wingspan or scale | Wingspan slider plus precise numeric entry and unit toggle; ratio readout | An applicable RC profile prepopulates it. Choose one independent size input; show the other as derived |
| Flying mass / estimated construction | Total-mass target slider plus numeric entry; component summary | Use the supported inventory proposal policy described below; expose conflicts rather than clamping |
| Balance | Battery-position slider/3D marker and component-position controls | Show computed CG and margin; respect confirmed mounting bounds and locked components |
| Power | Supported motor/propeller/battery package selector, with declared editable parameters | Filter by actual supported laws; show estimated versus measured evidence; re-evaluate loading and power together |
| Surface role, hinge or direction | Highlighted model picker, direction toggle and animated neutral/endpoints | Ask only about unresolved bindings; exact supported mappings can be applied and checked automatically |
| Control travel/timing | Unit-aware sliders and exact entry within represented laws | Preserve source limits versus target RC choices; do not conflate servo speed with aerodynamic effectiveness |

Each control shows the unit, current value, origin, useful bounds, a brief reason when it needs attention, and **Use automatic value** where applicable. Changes support undo/redo and preserve exact typed values. Slider bounds come from the selected profile and dependencies, not arbitrary universal limits. Numeric input may retain an out-of-domain request for correction; never silently clamp it or discard invalid text. Keyboard/controller interaction and readable units are part of the 1080p-first UI acceptance.

An unanswered question is keyed by its semantic field/decision and current dependencies. Revalidation may resolve or replace it; keep a still-applicable entered answer and never apply an answer to a different variant, component or binding merely because a screen position is reused. The shared AC-14 undo/redo slice is an explicit AC-FS-07 dependency, since Creator's current history work is incomplete.

Ordinary users see meaningful choices such as **Wingspan**, **Flying weight**, **Balance** and **Power**. Raw CFG keys, hashes, rule traces and detailed conversion diagnostics live in an expandable report. The final preview shows which values came from source, which were derived/estimated, any required omissions, and the available flight/start modes. It must be possible to expand and edit a known field even when its fallback question was skipped.

### Source help and recovery

Use the existing Creator diagnostic code, localized message arguments, field and step routing. AC-FS-02/03 own any versioned extension for source path/line, dependency chain, affected capability and actionable choices; closed readers must change deliberately. The [game-code studies](../research/aircraft-creator/flight-simulator-2026-11-16/game-repository-survey-2026-11-17.md#reuse-decisions-carried-into-the-plan) motivate this help contract. The copy below is proposed behavior, not an existing screen.

| Condition | Player-facing explanation and available action | Required behavior |
| --- | --- | --- |
| Several failures share one missing base aircraft | **This livery needs its base aircraft.** Offer the relevant folder-selection action and an expandable affected-files list | Ask once for that actual missing source; after capture, recompute the dependent chain and remove only resolved questions |
| Two equally valid sources remain under the same precedence rule | **Choose the aircraft source to use.** Show identifying variant/root information | Preserve both origins; do not silently pick directory order or ask for a value the source already supplies |
| Present configurations form a reference cycle | **These aircraft configurations refer back to each other.** Show the involved references and supported variant/reselection actions | Distinguish the cycle from a missing file; no repeated locate prompt that cannot resolve it |
| A source field is invalid or contradictory | Name the affected value, such as **Wingspan**, and offer only its supported source-choice or typed override route | Preserve raw declarations, error and override intent; do not relabel invalid data as missing or measured |
| Required geometry/encoding/control semantics are unsupported | Explain the unavailable capability and show supported-source details | A slider or diagnostic placeholder cannot make this aircraft ready; retain only the valid limited draft/preview |
| A new import fails or is cancelled | Keep the previous accepted aircraft available, with a specific retry/reselection action where possible | Show cancellation as complete only after owned work drains; a failed replacement does not erase the accepted preview or user edits |

The expanded report shows effective source values, winning and overridden origins, conversion rule/units, target disposition and manual override separately. Group repeated consequences of the same dependency failure, while retaining distinct root causes. Limit message count/text/depth; if analysis is incomplete, state that explicitly and keep the affected gate unresolved. Hide neither uncertainty nor a required failure to reduce the question count. Optional absence creates no question only when the profile proves it is nonessential. A uniquely resolved valid dependency/variant choice proceeds automatically.

## 5. Editable results and coupled recomputation

Automatic conversion creates an ordinary versioned Creator authoring document. Editing is available before finalization and through **Workshop → Edit aircraft** after saving. A saved version stays immutable; edits publish a new revision. Reimport compares old source, new source and current target overrides using the existing planned three-way policy.

Maintain a dependency graph and a generation token. A user edit updates its typed input and origin, invalidates affected automatic proposals/checks, and recomputes only dependent work. A background result for an older source/profile/document generation cannot overwrite a newer answer. Invalid raw edits block finalization even when the authoring object retains an older accepted numeric value.

Raw edit buffers, their units, validity and override intent belong to the versioned authoring/draft state for every editable input, including size, datum, inventory and new equipment controls. A rejected edit still marks the document dirty, advances its generation and enters undo/recovery; the last accepted number may serve an explicitly stale preview only. Saving a draft may retain invalid text, but publication and test flight must collect and validate the current complete edit state immediately before freezing a candidate. Saving, leaving, reopening or restoring a backup must not erase a rejected edit and make the older number eligible. Reuse AC-13/14 storage and departure ownership; if a recovery write fails, retain the unsaved state and existing retry/discard/cancel guard instead of reporting it saved. This requires a shared-state extension: current inventory/datum/size UI buffers are not all covered by Authoring's snapshot.

Track ownership separately from evidence, by stable component ID and independently editable property (including individual position coordinates where exposed). A manual mass override locks that mass; it does not make the component's estimated size or position manual. Recompute eligible properties without replacing the whole item, and preserve the evidence chain of untouched or derived properties. An emitted vector or aggregate with mixed origins uses supported derived evidence with a stable source reference to the complete property lineage, preserving the closed v2 quantity shape. Store the automatic producer/baseline alongside the override. **Use automatic value** removes only the selected override and resolves it against current inputs; undo/redo restores the prior values, ownership and origins as one coherent action. Removed or incompatible IDs become explicit conflicts. Version this contract through Definition, Compiler, snapshots and readers; today's single inventory `kind` and whole-item estimate replacement cannot enforce it.

- **Size:** One uniform source-to-target transform updates source-derived geometry, landmarks, pivots and eligible layout values exactly once. Recompute estimated airframe construction and aerodynamic/package checks. Preserve target values entered in metres and locked hardware choices; do not multiply those by the source scale again. Surface changed dependencies as conflicts where a manual value no longer fits.
- **Mass:** A total-mass slider is a target constraint, not an extra mass component or a patch to emitted physics. A versioned proposal policy may redistribute only eligible estimated airframe mass properties. Preserve measured/manual/locked properties and the selected motor, propeller, ESC and battery masses; include every item once. Show component contributions and remaining infeasibility. Do not add hidden ballast or rescale fixed hardware to force the requested number.
- **Balance and inertia:** Derive them from the resulting inventory and supported mounting changes. A CG control manipulates represented inputs, such as battery position; the readout is computed. Direct tensor/CG overrides require a separately reviewed authoring contract and are not implied by the slider design.
- **Power and controls:** Select/edit only represented equipment and actuator parameters. Recheck finite energy, installation geometry, thrust/weight, control topology and the complete coupled law/data domain. A qualified ideal/estimated electric profile may serve the first simulated RC target; it must show unmodeled current/thermal limits and borrowed data honestly, without claiming real hardware compatibility. A motor, voltage, propeller or battery edit invalidates the previous equipment qualification and must fit another explicitly qualified combination or parameter envelope. Rated-limit behavior and stronger real-installation claims require their own supported law and evidence. The [propulsion contract](../research/aircraft-creator/flight-simulator-2026-11-16/conversion-and-scaling.md#propulsion-controls-and-contact) owns this distinction. Size does not automatically scale battery capacity, hardware mass, servo timing or engine horsepower.
- **Paint and visual bindings:** They update the presentation identity and affected visual checks. They do not rewrite physical quantities merely because a livery or hinge label changes. Changes that also alter physical geometry are classified accordingly.

The minimum editing scope includes target size/scale, flying-mass request and component distribution, balance/mounts, power installation and represented equipment parameters, control travel/timing, and model/part choices. Each player-meaningful generated configuration value needs a typed editor, a coherent governing-input/constraint route, or a validated override supported by its law; document that route in the field registry. Derived readouts remain internally consistent with edited inputs. A selector with only one fixed package does not satisfy an equipment-editing promise. The current fixed estimated power package and generated aero values require explicit AC-FS-02/07 authoring extensions; any remaining fixed parameter is a visible temporary limitation/open owner task, not fulfillment of unrestricted editing. Raw coefficient/tensor overrides require their own validated contract rather than bypassing the compiler. Reuse existing [compiler readouts and diagnostics](../../app/workshop/creator/compiler.gd) and [package inventory proposals](../../app/workshop/creator/packages.gd), but never overwrite resolved source geometry with a whole-model bounding-box trainer estimate.

## 6. Execution, recovery and publication

Use owned captured bytes and bounded jobs with stage receipts, cancellation and resource budgets. Progress reports completed work; do not claim an exact remaining time without measurement. Parsing, image conversion and mesh processing must not monopolize the UI. Keep supported preview operations available while later nondependent work runs, but publish only an exact accepted candidate.

The initial automatic pipeline admits one active import job and one coalesced latest pending selection; internal workers count against its frozen resource budget. A superseded generation remains charged until drained. Include serialization, GLB/PNG re-admission and engine preview creation in the measured limits, since existing code does not make every stage cancellable or move preview construction off the UI thread. Bound fallback rebuilds and old/new retained scenes. The [milestone resource contract](flight-simulator-import-milestones.md#resource-and-responsiveness-contract) and C21/C22 fixtures own the exact capacity and responsiveness evidence.

Keep the previous accepted aircraft and its saved versions intact while preparing the new result privately. Cancellation drains/stops owned work before releasing resources and ignores stale completions. A failed conversion retains actionable diagnostics and any valid draft without replacing a working aircraft. Retry resumes only verified stages whose source, recipe, profile and input identities still match; otherwise recompute them. Draft persistence and quota recovery use the existing Creator owners.

Progress distinguishes completed local work from its required dependency closure: **Configuration read** may coexist with **Model waiting for a texture**, and neither means flight readiness. Only qualified complete stages contribute to finalization. Under the [derived-work contract](flight-simulator-aircraft-import.md#45-dependency-readiness-and-reuse-of-derived-work), exact-input retry may reuse verified results; same-path or same-version changed bytes may not. Index/cache damage rebuilds disposable work where captured inputs are available and preserves manual edits. Keep a replacement preview private until its required closure and visual admission pass; a missing asset's placeholder never becomes an accepted replacement.

Saving and launching use the normal Store/Home and checked launch route; no second catalog or direct solver load is introduced. The finalized source, normalized visual, authoring definition, physical bytes, profile/rule versions and ready receipt must describe the same revision. A later edit invalidates readiness until the affected checks pass again.

Publication and the subsequent draft/backup update have separate outcomes. Reuse Store's root-pointer commit point and expected-revision/CAS contract:

| Observed outcome | Required UI and recovery |
| --- | --- |
| Confirmed failure before publication commits | No new aircraft revision is saved; keep the draft and diagnostics, then retry only from the accepted Store state |
| Confirmed publication, including a later draft/backup failure | Show the exact saved aircraft version and the separate unsaved/recovery problem; retain the new publication identity and retry only the unfinished draft/backup operation |
| Commit/readback outcome uncertain or interrupted | Show **Checking save status**; reopen the Store and reconcile the intended UUID, expected revision and exact record/closure identity against accepted state before claiming success, failure or retrying |
| Reconciliation finds a different concurrent revision | Preserve both accepted data and local edits; surface the existing conflict/new-version or copy choice rather than overwriting or blindly republishing |

Cancellation or process interruption after a commit cannot imply rollback. Reconciliation may find the intended revision already committed; acknowledge it without creating a duplicate revision. A publication that is confirmed absent may be retried with the current accepted revision only after conflict checks. Persist enough bounded pending-operation identity before commit for restart reconciliation through the shared recovery contract. If bounded reopening/reconciliation cannot complete, retain the uncertain outcome and actionable recovery diagnostic. Until uncertainty is resolved, do not present the saved/Home result as known, discard the draft or start a second publication. An already frozen unsaved trial remains a separate identity.

## 7. Meaning of ready

**Ready for the stated OpenRC flight mode** means the exact configuration passes whole-document validation, source/visual/physical closure, loader and complete package-domain checks, supported controls/start/energy constraints, and the applicable numerical, start and lifecycle gates. The final preview names the supported start and estimated/calibrated status. A source report, static model or compiler-accepted experimental draft has a distinct status.

An exact frozen candidate may be ready for a checked **unsaved test flight** before final publication, preserving Creator's existing trial contract. Its candidate/launch identity is required; a Store publication ID is required only for the separate **saved usable aircraft** state. Release acceptance must still qualify the full saving/Home/restart pipeline. Publication follows the confirmed/uncertain outcomes above and cannot alter the frozen trial.

The development/release campaign qualifies the supported profiles, conversion recipes, laws and numerical domains. Runtime import checks each generated candidate against that qualified envelope and its exact identities; it does not rerun a whole 240/480/960 Hz research campaign on every import. A changed candidate outside the envelope cannot inherit readiness. If a required owning gate is unavailable, show the converted/editable result with its specific remaining requirement. That is useful partial progress, but it does not satisfy the completed automatic-feature journey.

Define an executable envelope predicate over every permitted input that affects the qualified behavior, including inventory-derived CG/inertia and edited equipment/actuator parameters. Restrict a parameter when the campaign has not covered its allowed range. Passing static mass/span/thrust bounds or merely receiving an inertia warning does not establish numerical qualification for arbitrary component arrangements. Pin the predicate, laws, datasets and campaign evidence in the profile/ready receipt.

The current AC-12 campaign did not pass. Existing `compile_candidate()` loader/domain acceptance alone therefore cannot prove the ready claim. AC-FS-08/09/10/11 must deliver and enforce the missing readiness path. This is a planned feature contract, not a statement that the current app already has it.

Check-to-launch qualification also freezes the actual field, normalized weather/seeds, backend/integration settings, energy state and start/trim/release context. Re-reading a changed path after checking is not reuse of the same context. C26 requires refusal/recheck with the previous flight preserved; [milestone M6](flight-simulator-import-milestones.md#m6-qualified-frozen-trial) owns the integrated proof.

## 8. Acceptance journeys

These are proposed tests, not executed results. They extend the 24 research fixtures and are assigned to the existing AC-FS work packages.

| ID | Independent setup / action | Required result | Owner |
| --- | --- | --- | --- |
| W01 | Complete, permitted, uniquely resolvable supported Flight Simulator source; applicable qualified RC profile | Select source → in-app model/paint/control/physics conversion → editable result with zero follow-up questions → save, Home, restart and checked flight; no prepared GLB or installed authoring tool required | 03…11 |
| W02 | Two equally valid variants, or a missing base outside selected roots; include a nested dependency and a distinct present-node cycle | Only the relevant picker/locate action appears; shared missing causes are grouped, cycles are identified separately, qualified optional absence asks nothing, and prior valid decisions survive resumed resolution | 02/03/11 |
| W03 | Missing target-size preference with valid default profile; then a case without applicable size policy | First applies the visible editable default; second asks for size once. A synthetic 10 m → 1.5 m case scales independent landmarks by 0.15 exactly once | 06/07 |
| W04 | Missing target mass versus invalid/conflicting source mass and invalid edited text | Applicable estimator handles missing target data; invalid data remains diagnosed, cannot fall through to a hidden default or stale number | 02/03/07 |
| W05 | Uniquely documented rigid control mapping versus two plausible hinges | Automatic binding and independent pose/sign checks for the first; one targeted mapping question for the second; no arbitrary candidate selection | 06 |
| W06 | Edit wingspan, total-mass request, battery position and supported equipment | Independently verify emitted inventory, CG, inertia, loading, margin and thrust/weight; fixed/locked items survive; infeasible request remains visible | 07/08 |
| W07 | Uniformly scale a source outside the supported aspect-ratio or topology domain | Detect invariant incompatibility; no reshaped wing, deleted engine or misleading size-only repair | 03/07/08 |
| W08 | Edit a resolved automatic field, undo, restore automatic, save/reopen | Correct origin/history and exact revision survive; dependencies recompute; source observations stay unchanged | 02/07/10 |
| W09 | Cancel, retry, source change or user edit during asynchronous conversion; include exact-input retry, with verified reuse if selected, and same-path/same-version byte replacement | No stale result overwrites edits, no incomplete closure is published, previous revisions intact, bounded cleanup and responsive UI; any reuse is limited to identity/recipe-matched verified work, while changed source or relevant rules require current results; publication interruption follows W18 | 02/04/10/11 |
| W10 | Livery-only edit, followed by a true geometry edit | Paint preserves physical bytes; geometry invalidates affected physical/visual checks and readiness | 05/07/10 |
| W11 | Unsupported decoder/law, absent closure or unavailable numerical gate | Specific limited/unavailable result; no ready label or launch enabled by a generic fallback template | 03/08/09/11 |
| W12 | Reimport changed source after manual edits and renamed control nodes | Three-way conflicts, retained overrides, invalidated bindings, new immutable revision and access to old version | 02/06/10 |
| W13 | Clean exported desktop install without separately installed Blender, MCX, Python CLI or Microsoft SDK | Advertised source conversion and conditional wizard work with app-owned dependencies, within measured memory/time/cancellation bounds | 04/05/11 |
| W14 | Keyboard/controller interaction, unit changes and rejected numeric input at 1080p | Sliders and exact entry agree; units do not change physical values; focus/errors remain usable; no compulsory skipped screens | 07/11 |
| W15 | W01 with missing, whitespace/control-only or overlong display metadata; repeat import with a duplicate display name | Valid editable name is generated without a naming question; distinct new aircraft use UUIDs; retry/restart retains identity and reimport preserves the user's name | 02/03/10 |
| W16 | Start from a saved valid draft; enter invalid inventory mass, size or datum text as the only edit; save/reopen and separately exercise backup recovery | The edit marks the draft dirty until saved; raw text, unit and invalid status survive save/recovery with appropriate history; no stale number becomes publishable or flyable; rejected recovery writes preserve unsaved status and departure choices | 02/07/10 |
| W17 | Override only a proposed wing mass and one position coordinate; change size/profile, undo/redo, restore one automatic property, save/reopen | The non-restored override survives; the restored property follows its current automatic value; eligible position/size properties update and evidence stays independent; inventory, CG and inertia agree with independent expected values; out-of-envelope distributions cannot inherit readiness | 02/07/08/10 |
| W18 | Inject failure before pointer commit, lose commit readback, interrupt after commit, and fail the following draft save through quota/conflict | Reopen verifies accepted UUID/revision/record; show absent, confirmed or uncertain publication correctly; no duplicate revision or false rollback; a committed aircraft remains saved despite its separate draft failure | 02/10/11 |
| W19 | Inspect an ideal/estimated profile, then edit motor/voltage/propeller/battery beyond its qualified combination; also request unsupported rated-limit behavior | No 60 A prose becomes an enforced ESC limit or borrowed 11×6 data becomes measured 12×6 data; unsupported combinations lose readiness and unsupported rating behavior is unavailable. If a rated-limit profile is advertised, independently test a rating exceedance against that law; adding such a profile is not required for the first ideal-profile release | 07/08 |

Before claiming release completion, bind W01 to an exact authorized real source in addition to original fixtures, publish its supported source profile and target envelope, and retain its complete end-to-end evidence. Question count is a workflow metric, not a reason to suppress uncertainty. Measure completion rate, required-question count and conversion time by source/profile and outcome, without claiming universal compatibility.

The [26-case contingency matrix](flight-simulator-import-milestones.md#contingency-matrix) supplies source-code-backed mechanisms underneath these player journeys. Its fixtures are proposed, not executed; milestone M7 requires the complete applicable W01–W19 suite, including the real-source W01/W13 journey and all required negative/recovery evidence. Earlier milestones close only their explicitly scoped stage assertions.
