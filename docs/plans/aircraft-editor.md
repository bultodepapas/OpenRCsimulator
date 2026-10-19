# Aircraft experiment editor plan

**Date:** 2026-10-19. **Revision:** 5 — future customization, smoke and simple experiment workflow. **Status:** the shared Workshop has an implemented slice; the new ideas in section 5 are proposed, with full fleet and release gates open. **Prefix:** AE-00…AE-26. **Owner:** aircraft-editor track.

The plan owns remaining work and acceptance. The [Aircraft Workshop guide](../AIRCRAFT-WORKSHOP.md) owns current player behavior and implementation details. The [aircraft contract](../AIRCRAFT_CONTRACT.md) owns physical and generated authoring schemas. [DECISIONS](../DECISIONS.md) owns durable rationale. Use the current repository state and linked evidence when a dated proposal differs.

**Owns:** `app/workshop/`, `app/ui/workshop.gd`, `app/ui/workshop_preview.gd`, `app/data/workshop/`, `app/tests/test_workshop_*.gd`, `research/aircraft-editor/`, this plan and [AE evidence](../research/aircraft-editor/AE-01-10/README.md). Existing implementation paths are `app/workshop/` and `research/aircraft-editor/`; do not create a parallel `aircraft_editor/` subsystem.

**Coordinates:** physical schemas and generated bindings with aircraft-standardization/model owners; session and propulsion inputs with their owners; Workshop screens and preview with AE; the shared menu shell, preferences, routes and localization with UI. Check the [track registry](../README.md#tracks-plans-and-step-ids) before changing shared files. Do not edit generated aircraft geometry or physics data by hand.

## 0. Implemented slice and remaining acceptance

The guide describes the current interface, supported operations, schemas, persistence, verification commands and limitations. [AE-01–10 evidence](../research/aircraft-editor/AE-01-10/README.md) records the initial tests, later audits, native captures and limits. The table below separates delivered behavior from remaining acceptance.

| Steps | Implemented baseline | Remaining acceptance |
| --- | --- | --- |
| AE-00 | Initial source/ownership audit and implemented-path reconciliation | Keep interfaces coordinated as new aircraft families and authoring seams arrive |
| AE-01/02 | Shared compiler, catalog-discovered descriptor generator, versioned bindings, exact source/dependency/compiler pins and deterministic trial identity; eight descriptors currently pass generation checks | Revalidate fleet behavior after Extra's finite-glow migration and P-51/Ventage finite-liquid changes; richer module composition and migration remain open |
| AE-03 | Local variant library, immutable revisions, copy/load/trash/restore, atomic index replacement, stale-save refusal and backup recovery | First-write interruption recovery, revision-bound delete confirmation, unambiguous trash generations, draft recovery, and explicit orphan-lock policy |
| AE-04…07 | Detached shared compiler, conventional controls, legacy prescribed-RPM transforms and initial Stik/legacy-Extra fixtures with synthetic identities | Requalify current sources and fixtures after Extra's finite-glow migration; wider combinations/refinement and family transforms remain open |
| AE-08/09 | Shared preview/editor, catalog selection, presets, comparison, undo/redo, Home/Pause routes, English/Spanish and captured viewport checks | Broader presentation-anchor coverage, persistent drafts, control-response editing, accessibility and owner playtests |
| AE-10 | Frozen airborne trials, return to the same draft, F5 identity and preservation of the previous flight on failed preparation | Full crash/replay/recording and longer-duration trial matrix |
| AE-11…26 | Not complete | Work and gates are sequenced in [delivery sequence](#3-delivery-sequence-and-acceptance-gates); AE-19 is the current-fleet gate and AE-25 is the twenty-airframe gate |

The catalog currently has **eight fixed-wing configurations** and a separately selected rotorcraft. Identified airplane sources use stable physical IDs and Workshop v3 ID bindings; explicit readers retain ID-less v2 and historical v1/v2 behavior. The compiler must derive support from validated modules and never dispatch transformations by aircraft name or ID. [2026-10-19 diagnostics](../research/aircraft-editor/AE-01-10/README.md#source-checks--2026-10-19) pass descriptor generation but leave compiler, legacy-trial and integration failures unresolved. Rotorcraft authoring and qualification stay outside airplane conformance.

The initial legacy prescribed-RPM proof used the Stik and the then-current Extra. Extra now uses finite glow and no longer qualifies for legacy size/mass/power transforms. Current fixtures and the two-aircraft V1 gate need reconciliation with the NITRO/aircraft owners; do not enable legacy transforms to satisfy a historical fixture. Other families retain registered conventional-control and tank-capacity operations where supported. Twenty synthetic IDs establish only the behavior of that recorded fixture, not current fleet or packaging acceptance.

## 1. Scope and delivery gates

Aircraft Workshop creates detached, experimental local variants from a shipped aircraft. It must preserve the source, explain the requested and effective changes, save reproducible identities and prepare each trial as a new validated flight. A numerically valid candidate is not a physical-validation claim.

| Gate | Steps | Exit condition |
| --- | --- | --- |
| V1 shared experiment loop | AE-00…10 | Stik and Extra use the same supported editing, save, airborne trial, pause/return and rollback path |
| V2 current-fleet standard | AE-11…19 | Every eligible fixed-wing catalog entry passes generated-binding, module, session, persistence and conformance checks; adding an ordinary supported aircraft changes data/assets/bindings, not editor behavior |
| V3 research and scale-out | AE-20…25 | Bounded performance tools and recipes remain truthful, the editor is qualified for its declared ranges, and a twentieth ordinary airplane passes onboarding with the editor frozen |
| Documentation closeout | AE-26 | Delivered behavior, authoring contracts, evidence and remaining limitations have one linked authoritative home each |

No gate requires a CAD editor, arbitrary physics scripts, cloud sharing, multiplayer, or a new vehicle branch in the simulation kernel.

## 2. Ownership, source of truth and fleet onboarding

| Concern | Owner and rule |
| --- | --- |
| Current player workflow and implementation details | [Aircraft Workshop guide](../AIRCRAFT-WORKSHOP.md) |
| Physical v2 data, stable IDs, model manifests and generated authoring rules | [Aircraft contract](../AIRCRAFT_CONTRACT.md), with aircraft/model source pipelines |
| Descriptor generation | `research/aircraft-editor/build_descriptors.py`; regenerate after source or model-manifest changes and commit the generated descriptor |
| Runtime editing and storage | `app/workshop/`; candidates remain detached from catalog source files |
| Screen and isolated preview | `app/ui/workshop.gd`, `app/ui/workshop_preview.gd`; AE owns these screens, UI owns shared shell and routing |
| Session integration | `app/sim/flight_session.gd` and application routes remain coordinated with their existing owners |
| Dated implementation proof | `docs/research/aircraft-editor/AE-01-10/` and later AE step evidence; keep raw proof with its owning step |

### 2.1 Common aircraft editing standard

The physical aircraft remains `openrc-aircraft v2`. The generated companion descriptor uses the current `openrc-aircraft-workshop v3` format for identified sources; ID-less source and saved-record readers retain their explicitly versioned compatibility behavior. Descriptors bind source bytes, module assertions, presentation identity and generated model manifests without copying physical values into Workshop metadata. The contract owns the complete binding rules.

The validated physical model and closed module registry select available operations. Descriptor module assertions must match that classification; they do not select a solver law or provide executable transformation rules. Stable component keys survive inventory rename/reorder, while exact source and manifest pins still require descriptor regeneration. Saved variants keep their historical identity and are never silently rewritten or rebound.

The shared compiler, recipe and launch path must not branch on aircraft ID, display name, maker, filename or inventory text. Catalog/resource lookup and provenance may use IDs. A new physical capability needs an owned schema/module change and reusable tests; an ordinary aircraft using existing capabilities should need only its generated sources, bindings and conformance evidence.

### 2.2 Current fleet coverage

| Configuration family | Current role in Workshop acceptance |
| --- | --- |
| Jensen Ugly Stik baseline | Current simple prescribed-RPM scaling path; broader combinations still need qualification |
| Great Planes Extra 300S | Now finite glow; legacy scaling evidence is historical. Regenerate bindings and requalify supported operations, trim and trials |
| Three finite-glow Stik configurations | Separate 2T/4T module and installation gates; do not infer family behavior from the legacy Stik |
| Turbo Lumber Evolution | Shared imported-model bindings exist; electric editing and complete presentation qualification remain open |
| P-51D Mustang and Ventage Jet | Finite-liquid modules are registered; generated descriptors and fleet conformance must follow the updated sources |
| X-Cell research rotorcraft | Separate vehicle schema and qualification path; excluded from fixed-wing Workshop conformance |

Catalog discovery, not this table, defines the fleet. New catalog entries must be checked automatically; the table explains the current coverage boundary.

### 2.3 Fleet onboarding and twenty-airframe proof

For an airplane using existing capabilities:

1. Create physical data, model manifests and assets through the owning source pipelines.
2. Declare its vehicle class and physical identities in the source contract; do not encode editor behavior in the aircraft name.
3. Generate and check its Workshop descriptor after physical or model-manifest changes.
4. Run catalog-discovered module, compiler, persistence, session and presentation conformance.
5. Record exact source identities, commands, results and limits in the owning evidence report.

AE-25 freezes the editor before onboarding the twentieth ordinary airplane. Passing means only the aircraft's normal data, assets, generated bindings and evidence are added; no airplane-specific editor branch, compiler formula, recipe copy or screen change is needed. A genuinely new physical law follows the shared contract/module path before its aircraft is counted as supported.

## 3. Delivery sequence and acceptance gates

Dependencies are explicit. A gate may split into smaller reviews, but its acceptance condition remains required.

| ID | Work and dependency | Acceptance evidence |
| --- | --- | --- |
| AE-00 | Source audit, ownership and current implementation reconciliation | Current catalog/module/source map; agreed shared-file boundaries and migration limits |
| AE-01 | Common descriptor, parameter/module contract and conformance approach; AE-00 | Schema-backed field map, generated bindings, unknown capability refusal and no duplicated physical values |
| AE-02 | Recipe/descriptor versions, dependency pins and trial identity; AE-01 | Strict malformed/version/stale-binding cases; exact input identity; deterministic equivalent fingerprints |
| AE-03 | Local library, immutable revisions and deletion/recovery; AE-02 | Interrupted-write, corrupt-record, stale-delete, trash-generation, duplicate identity and restart cases retain a recoverable record |
| AE-04 | Generic resolver and detached no-op compiler; AE-02 | No-op numerical/trajectory parity; unsupported modules and incompatible bindings fail closed |
| AE-05 | Shared inventory mass and conventional controls; AE-04 | Independent mass, CG, inertia and surface checks; reordered/renamed inventory does not redirect edits |
| AE-06 | Legacy prescribed-RPM propulsion transform; AE-04 | Power, RPM, thrust and trim bounds on two compatible airframe fixtures; retain the original Stik/Extra proof and reconcile Extra's changed family before closing V1 |
| AE-07 | Uniform geometry, virtual propeller/suspension and plausibility policy; AE-05/06 | Six exposed Stik sizes and a second compatible airframe's declared envelope; derived geometry/mass checks and real session startup |
| AE-08 | Shared presentation binding and preview integration; AE-07 | Datum, CG, hinges, propeller, hull, contacts and imported-model cases match effective data without ID-specific editor paths |
| AE-09 | Workshop library UI, Home/Pause route, editing history and localization; AE-03/08 | Keyboard journey, EN/ES viewport captures and resolution of the too-small preview reported in [UI-29 evidence](../research/menu-investigations/UI-29-R3/README.md); save/load/history and invalid-draft behavior remain usable |
| AE-10 | Transactional trial, return, restart and frozen identity; AE-04/09 | Stik/Extra workflow, failed-start rollback, retained draft and correct trace/checkpoint identity |
| AE-11 | Effective-model runway-start qualification; AE-10 | Gear, wheel profile, equilibrium, clearance and selected-field fixtures; no aircraft-ID permission list |
| AE-12 | Stable component editing, ballast and mass/CG fitting; AE-05/10 | Independent first-moment/full-tensor oracles; impossible targets, negative ballast and unsupported mounts reject cleanly; hubs stay fixed in structural coordinates while their offsets are recomputed from the new CG |
| AE-13 | Match-my-airplane wizard and measurement provenance; AE-12 | Measured mass/CG round trip; unknown inputs remain estimated; reference chord and MAC remain distinct; matched geometry stays inside source-backed limits |
| AE-14 | Coupled shaft, thrust-axis and optional wake modules; AE-01/12 | No-op parity, source-backed ranges and correct composition with geometry, gear and loads |
| AE-15 | Electric motor and battery modules; AE-01/12 | Fixed-voltage, OCV/resistance and pack-ECM behavior remain distinct; include pack mass/energy, numerical stiffness, reset/replay and unsupported combinations; coordinate with [BAT](battery-realism.md) |
| AE-16 | Scoped installation/profile inputs and independent finite-glow 2T/4T modules; AE-01/12 | Qualify fixed-hardware transforms first; cover exact dependency identity, moving mass/CG, thermal/fuel lifecycle and reset/replay; reject cross-family transforms (never apply 2T rules to 4T or vice versa) |
| AE-17 | Turbine module and start/gear qualification; AE-01/12 | Spool, intake, timestep, identity and actual start modes are validated without Ventage-specific editor behavior |
| AE-18 | Shared parameter pages generated from supported module definitions; AE-14…17 | UI/compiler/tests share bounds and labels; physical/rendered travel agrees, radio shaping is not applied twice, and unsupported operations are explained |
| AE-19 | Current fixed-wing fleet conformance, migration, data-only variants and variant CLI; AE-03/11…18 | Every discovered airplane entry passes fresh-install and missing/newer/corrupt dependency cases; regenerate stale descriptors before qualification. Data-only bundles reject executable resources and unsafe paths; migration preserves the original. Proposed `--aircraft-variant=<bundle-or-local-path>` is mutually exclusive with `--aircraft` and does not read or write player preferences |
| AE-20 | Unpowered/glide starts and bounded performance experiments; AE-10 plus family adapter | Bind results to exact initial state, commands, environment and termination. Label static outputs separately from scripted speed, climb, roll or endurance results and state each method's limits |
| AE-21 | Supported aerodynamic packages and later authored wingtip/tail geometry packages; AE-01/20 plus AS/model contracts for geometry | Domain, trim, stall-join and numerical limits are reported per field/module; changed geometry, mass, aero, hinges and contacts agree before shape options become available |
| AE-22 | Capability-based shared recipes, parameter sweeps and seeded discovery; AE-20/21 | Same recipe applies to compatible bases, explains incompatibility and searches within fixed bounds |
| AE-23 | Wider scale targets and combinations; relevant AE-14…22 modules | Qualify 25–400% targets with boundary/field-clearance diagnostics, offline 240/480/960 Hz refinement and bounded runtime cost |
| AE-24 | Registered paint/decal slots, smoke profiles, thumbnails and simple customization; local editing after AE-08/09 and AS slot contracts, portable profiles after AE-19; SM-10…15 for smoke | Follow the staged delivery below; appearance preserves physical identity/trace values, has a separate presentation identity, and passes instance isolation, save/load, localization and bounded-render checks |
| AE-25 | Twenty-airframe onboarding plus cross-platform, accessibility and playtest acceptance; AE-19…24 | Frozen editor; data/assets/bindings/evidence only for the twentieth ordinary aircraft; fresh-clone and package checks |
| AE-26 | Consolidate delivered guide, authoring standard and evidence links; AE-25 | Current contracts are linked once, dated evidence is retained, and superseded planning prose is removed |

## 4. Cross-cutting acceptance rules

- Compile from a detached copy. Never edit shipped/generated aircraft files or mutate a live flight while a draft is open.
- Classify every affected quantity as invariant, transformed by an identified rule, recomputed from dependencies, or unsupported. Reject incomplete transforms and conflicting writers.
- Validate the complete candidate with the aircraft contract, module validators, trim/start checks and selected session path. A local numerical check alone does not make a candidate launchable.
- Bind a trial to its exact base, recipe, descriptor, compiler, dependencies and resolved model. Restart, replay and checkpoint restoration must use those frozen inputs; a changed dependency refuses the trial without deleting the saved variant.
- Preserve existing aircraft/model node names and generated source ownership. Keep physics state in scalar/packed float64 representations; render transforms remain at the presentation boundary.
- Prove no-op parity, independent transform arithmetic, invalid-input refusal and rollback. Use actual session/model builders for presentation and gear claims; screenshots alone do not establish interaction behavior.
- Keep numerical/simulation consistency distinct from measured aircraft data, flight performance and pilot acceptance. Record tested envelopes and unresolved model assumptions beside each result.
- Run focused checks for the changed owner paths, then the repository's required integration checks. Keep the test report tied to the source revision and commands that produced it.
- For physics/control tuning, follow the [flight logging workflow](../FLIGHT-LOGGING.md): retain an exact-replayed baseline and compare one explicit candidate with the same tick/input tape. Check `complete` and `solver_changed`; do not rerecord golden flights for editor-only work.

### Verification dimensions

| Dimension | Required distinction |
| --- | --- |
| Transform math | Use independent fixtures for mass, CG, inertia and geometric scaling; do not validate a helper only by calling it twice |
| Identity | Test exact source/dependency pins, cosmetic-only changes, stale revisions and same-name physical changes separately |
| Capability composition | Exercise valid, unsupported and conflicting module combinations; no silent partial transform or family fallback |
| Session lifecycle | Cover launch, failed preparation, old-flight rollback, restart, crash return and checkpoint/replay against frozen inputs |
| Presentation | Compare effective datum, CG, hinge/rotor, hull and contacts in the actual flight builder; a still preview alone does not prove flight alignment |
| Usability | Cover keyboard flow, localization, constrained preview size, text scaling and status/diagnostic visibility |
| Evidence limits | Report tested envelope, solver conditions and unknown physical support; passing software checks do not establish flight validation |

## 5. Planned player-facing work

**Future design, not implemented functionality.** Make experimentation fun and easy: choose an aircraft, pick a preset, change a few understandable settings, preview, save a copy and test fly. This section is the product backlog; the linked owner plans define renderer, model, fuel and session work. An idea does not become a release requirement until its bounded slice and acceptance evidence are selected.

### 5.1 A simple editor first

1. Start with preset cards and a useful aircraft preview. Offer **Appearance**, **Smoke**, **Flight setup** and **Compare** only when the corresponding capabilities are available; keep deeper controls under **More options**.
2. Choose a named part or declared attachment on the preview. Use color swatches, clear units and an explanation of the result. Distinguish a painted wingtip from a wingtip shape that changes flight.
3. Link a declared left/right pair by default; allow independent colors or edits after unlinking. Offer copy-to-pair, per-page reset, before/after comparison and one undo operation per edit or slider drag. Extend the existing history instead of creating a second undo system.
4. Preview appearance and bounded smoke playback in the isolated Workshop scene. Provide Play, Pause and Restart preview; entering this mode must not run another flight or change the retained session. The existing preview is still-only; playback is new work.
5. Show what changed, save a named preset/build or copy, then use the validated trial route. Keep camera/HUD choices in the trial setup, under their existing owners.

Unsupported controls stay unavailable with a short reason. Keep the supported preset list useful; advanced settings must not fill the first screen with technical parameters. Reuse free tools and licensed assets where suitable, with provenance retained.

### 5.2 Idea catalogue

All entries are pending candidates. Paint and show effects belong to AE-24; changes to installed hardware or aerodynamic shape follow the physical module gates even when their controls look simple.

| Idea | Easy example | Owning gate / dependency |
| --- | --- | --- |
| Body and wing colors | Blue body, cream wings; choose upper and underside separately | AE-24a; AS material slots |
| Wingtip and tail accents | Bright tips and a contrasting rudder for orientation | AE-24a; authored paint regions |
| Stripes and patterns | Select a built-in stripe, checker or roundel and adjust its accent color | AE-24a; bounded decal/pattern slots |
| Name and number | Put “RC-27” or a short build name on a declared tail/body panel | AE-24a; text/decal bounds |
| Spinner and prop-tip accents | Match a spinner to the tail; color supported prop tips | AE-24a; rotor/blur presentation checks |
| Reusable palettes | Apply one palette to compatible trim slots, then reset one part | AE-24a/d; compatible slot mapping |
| One or several smoke colors | Red left trail, blue right trail, white center trail | AE-24b/c; SM-10…12 |
| Emitter positions | Select supported left/right wingtip, exhaust, rear-fuselage or tail-surface slots | AE-24b/c; AS anchors and SM-11 |
| Smoke amount and shape | Fine ribbon, soft cloud or wide fan; simple Low/Medium/High amount | AE-24b/c; SM width/fullness budget |
| Smoke bursts | Hold while pressed, or emit a three-second burst | AE-24c; SM-13 and AUX/UI ownership |
| Smoke persistence | Short or long puff life and soft fade after release | AE-24c; SM-13/14 |
| Color sequences | Alternate two colors or step through a saved rainbow palette | AE-24c; bounded presentation timeline |
| Smoke preview | Play the same short pass in calm wind or a chosen preview wind | AE-24c; SM/M5 preview contract |
| Display lights | Pick a supported steady or strobe accent for a show setup | Later AE-24; AS/FW slots and bounded lighting; physical hardware separate |
| Mass and CG wizard | Enter measured mass/CG or move an allowed battery/ballast component | AE-12/13; inventory/mount constraints |
| Battery packages | Compare a lighter pack with a compatible higher-capacity pack | AE-15; BAT mass/energy laws |
| Powerplant packages | Select a compatible engine/motor/ESC installation | AE-14…17; family-specific data and validators |
| Propeller packages | Choose a qualified diameter/pitch option with matching visual blades | AE-14…17; load maps, inertia and clearance |
| Servo packages | Compare compatible servo mass, speed and control response | AE-12/18; SAV/AS actuator contract |
| Travel and response | Trainer/Sport throw presets, independent axes and supported response settings | AE-18; input shaping applied once |
| Flaps and mixed controls | Choose supported differential, flaps or airbrake settings | AE-18; qualified AS/aircraft modules |
| Wingtip shapes | Select an authored rounded tip, tip plate or winglet package | Later AE-21b; geometry/aero/mass agreement |
| Tail shapes | Compare supported fin or stabilizer packages with coherent hinges and loads | Later AE-21b; AS/model and aero owners |
| A/B comparison | See original versus candidate and a concise “what changed” list | AE-09/20; common conditions and valid starts |
| One-change experiments | Suggest one bounded change while preserving locked settings | AE-22; seeded capability-based proposals |
| Glide and bench cards | Prepare a power-off glide, or evaluate static thrust/RPM/torque | AE-20; session starts and evaluator limits |
| Goal recipes | Explore “lighter trainer” or a supported endurance comparison | AE-20/22/23; show predicted results and conditions |
| Build notes | Keep measured dimensions, weighing date and setup notes with the build | AE-03/13; provenance separate from cosmetic metadata |
| Favorite presets | Save a palette or smoke profile and copy only compatible settings | AE-24d; capability checks and revision history |
| Thumbnail and test view | Save a model thumbnail; choose an existing camera/HUD preset for the trial | AE-24 / CAM / HUD; shared view settings |
| Portable recipe cards | Export a data-only build/profile with preview and required capabilities | AE-19/24d; dependency and safe-import validation |

Changing color does not qualify a new material system or a physical aircraft part. VQ keeps its [targeted material-repair scope](global-performance-visual-quality.md#vq-02b--conditional-aircraft-repair); AE owns these future per-build controls. Reuse the [model/authoring plan](aircraft-standardization.md#workbench-customization-bindings-proposed), [smoke plan](../SMOKE-PLAN.md#future-user-customization--proposed-sm-10-onward), [battery plan](battery-realism.md), [servo plan](savox-servos.md), [camera plan](camera-views.md) and [HUD plan](flight-overlays.md) rather than duplicating their implementations.

### 5.3 Smoke presets and understandable controls

The detailed emitter/render contract lives in SM-10…15. In the Workshop, select a preset, toggle available emitters on the model, pick a color per emitter and adjust **Smoke amount**. **More options** separates width, fade, burst time and puff lifetime. **Smoke amount** means visual fullness; physical smoke-fluid capacity in ml and supply endurance need the separate [FUEL extension](fuel-mass-balance.md#future-smoke-fluid-resource).

The following are illustrative profile values to qualify, not implemented defaults or measured emissions:

| Preset | Proposed setup | Simple example |
| --- | --- | --- |
| Classic Exhaust | Supported authored engine outlet; source-driven operation | Faint neutral exhaust; engine state retains authority |
| Twin Ribbons | Red left wingtip and blue right wingtip, linked amount | Medium amount; 3 s burst; each puff fades within 6 s |
| Tricolor Pass | Red/white/blue across two tips and one approved center/tail mount | One button controls the enabled group; per-emitter colors remain editable |
| Tail Comet | An approved rear-fuselage or separately declared tail-surface slot | Gold soft plume; 5 s burst; 8 s puff lifetime |
| Rainbow Burst | One or more declared show emitters, discrete palette steps | Change the color of new puffs each second during a bounded burst |
| Clear Trainer | Contrasting top/underside, bright tips and tail, show smoke off | One preset for aircraft orientation without extra effects |

Turning emission off stops new puffs; existing puffs retain their birth color and continue to age and drift. A long lifetime is not an unlimited supply. Show plumes on electric or turbine aircraft require an explicit authored show-effect route; they do not activate healthy-engine exhaust or claim installed smoke hardware. Keep flight physics, physical identity and physical trace values unchanged; store visual profile/seed/timing identity separately for captures or any future visual replay.

### 5.4 Small delivery slices and acceptance

| Slice | Scope and dependencies | Completion evidence |
| --- | --- | --- |
| AE-24a — simple appearance | Local palettes, declared paint regions, short names/numbers and selected built-in patterns; AE-08/09 plus AS bindings | Two independent instances, reset/undo, EN/ES and small-window journeys; shared materials and physical flight results unchanged |
| AE-24b — simple smoke | One qualified emitter profile, color/amount presets and isolated preview; SM-10…12 and AS effect slots | Save/load and old-build compatibility; missing slots explained; source exhaust/show behavior remains distinct; bounded preview and identical physical results |
| AE-24c — airshow profiles | Multiple named emitters, linked pairs, bursts/fade, palette sequences and optional preview wind; SM-11…15 | Stop/expiry/pause/reset/return and sequence timing checked at different render rates; one total particle/GPU budget; no material bleed or stale plumes |
| AE-24d — reusable profiles | Favorites, compatible-only copy, thumbnails and versioned data-only import/export; portability after AE-19 | Fresh-install round trip, missing/changed-slot refusal and explicit migration; original build remains intact; imported profiles contain no executable resources |
| AE-21b — shape packages, later | Authored wingtip/tail options after the physical/model contracts and AE-20/21 | Visual geometry, mass/CG/inertia, aero, control hinges, hull/gear and trim/start checks agree; source-backed limits and modeling assumptions remain visible |

Start with AE-24a and one smoke profile after the shared contracts are ready. Local cosmetic work can proceed before full-fleet portability; it does not close the existing save/trial, physics, platform or pilot gates. Keep later lights, shape packages and performance recipes behind their named owners and validation.

Performance displays distinguish measured user inputs, static evaluator results and scripted simulation results. Speed, climb, roll and endurance labels require a declared setup, duration/termination rule and supported domain. User mass/CG measurements retain their evidence; unknown values remain estimated. A cosmetic preset must not silently install hardware, alter weather or add stabilization.

## 6. Evidence and references

[AE-01–10 evidence](../research/aircraft-editor/AE-01-10/README.md) is a dated record of the initial implementation, robustness follow-ups, reproduced issues, verification and limits. Preserve its logs, captures, original failed attempts and source audit. Do not rewrite historical results as current behavior.

For each later delivery, keep the concise report, source/config identities, reproduction commands, raw logs and captures under its owning AE step in `docs/research/aircraft-editor/`; keep generators and reproducible tooling in `research/aircraft-editor/`. Link each report from the [research index](../research/README.md). Do not create archives or cleanup reports.

Each step report should state whether its gate is complete or partial, identify the source/config revision and dependencies, list exact commands and retain failed attempts alongside successful reruns. Keep summaries readable; raw logs and captures remain beside that report, while reusable source tools stay in the root `research/` tree.

Authoritative references:

- [Aircraft Workshop guide](../AIRCRAFT-WORKSHOP.md) — current interface, supported operations and implementation details.
- [Aircraft contract](../AIRCRAFT_CONTRACT.md#workshop-authoring-standard) — physical schema, generated descriptor and authoring rules.
- [Kernel boundaries](../STACK.md#boundaries-and-data-flow) — shared simulation ownership.
- [Track registry](../README.md#tracks-plans-and-step-ids) — file ownership and step IDs.
- [DECISIONS](../DECISIONS.md) and [LEARNINGS](../LEARNINGS.md#keeping-this-useful) — durable decisions and reusable lessons.
