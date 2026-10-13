# Aircraft standardization and Blender onboarding plan

**Date:** 2026-10-13. **Revision:** 1. **Status:** proposed continuation of delivered AS-00–05; implementation steps below are pending. **Owner:** aircraft-standardization track. **Prefix:** AS-06…AS-18. **Review baseline:** `969c9fee` plus the working tree inspected on this date. Concurrent Workshop, scenery and physics work must be reconciled before implementation.

Make adding an airplane a repeatable authoring operation: supply its Blender delivery, physical data and declared bindings; run common checks; register it. An airplane using supported capabilities must not require changes to the flight solver, shared presentation, Workshop operations, audio or crash logic. A genuinely new capability adds a tested shared module that subsequent aircraft can reuse.

The first delivery standardizes the existing fleet without changing its flight equations or calibration. The second proves controlled extension of surfaces, propulsion and contact policies. Future compatibility means explicit interfaces, versions, dependencies and rejection of unsupported combinations; it does not mean accepting an arbitrary future engine through an unimplemented enum.

## Ownership and authoritative sources

The [aircraft contract](../../AIRCRAFT_CONTRACT.md) remains the current physical authority. This plan owns pending cross-system standardization, not the detailed implementation status of other tracks. [AS-00–05 evidence](../research/aircraft-standardization/README.md) remains a historical record.

| Owner | Responsibility in this plan |
| --- | --- |
| AS | Contract/schema evolution, common semantic IDs and compatibility rules, authoring conformance, fleet migration coordination; `app/physics/aircraft_contract.gd`, contract/schema sources and `research/aircraft-standardization/` |
| Aircraft/model tracks | Source geometry, `.blend`/GLB deliveries, generators, physical calibration and per-model bindings; generated outputs stay generated |
| AE | Existing `app/workshop/`, Workshop UI, recipes, compiler, descriptor/dependency resolution and editing conformance; [AE plan](aircraft-editor.md#21-common-aircraft-editing-standard) |
| Physics and propulsion | Normalized model consumers, solver state, trim, pure stage evaluation, energy/mass coupling and lifecycle; G2/EL, NITRO and AV retain their physical laws |
| GP and CR | Tire/hull/scenery contact laws, event response, collision profiles, damage policy and wreck presentation |
| UI, HUD, AUD and camera | Capability-driven availability and read-only presentation of accepted model/session state |

Integrate shared loader/session/render files serially. Use the [ownership registry](../README.md#tracks-plans-and-step-ids), inspect the live diff and retain concurrent changes. No new parallel editor, tire solver, asset exporter or destruction framework is needed.

## Findings in the current source

These findings describe the inspected code, not acceptance results for the evolving working tree.

| Boundary | What exists | Standardization gap |
| --- | --- | --- |
| Physical validation | [AircraftData](../../app/physics/aircraft_data.gd) validates/derives v2 through [AircraftContract](../../app/physics/aircraft_contract.gd); [structural spec](../../app/data/schema/aircraft-contract-v2.json), generated JSON Schema and coupled numerical checks are separate layers | Extend them together and test agreement. A new schema field alone cannot enable a physical law |
| Fleet discovery | [Catalog](../../app/app_state/aircraft_catalog.gd) exposes seven configurations across five airframes, including finite-fuel 2T/4T Stiks | Discover entries and dependencies automatically instead of copying a five-aircraft list into new tools |
| Controls | `_controls()`, [Commands](../../app/input/commands.gd) and the session use roll/pitch/yaw/throttle, three servo states and fixed conventional surface outputs | Independent actuators, flaps, elevons, V-tail and other mixing need a physical/control interface extension; existing flap animation is not flight support |
| Propulsion | `_propulsion()` selects one `glow_prop`, `electric_prop` or `turbine` object; [Dynamics](../../app/physics/dynamics.gd) and [Propulsion](../../app/physics/propulsion.gd) consume one installation | Solver family, hardware, energy source and layout must be distinguished. Pusher, EDF and multiple engines cannot be represented by renaming a tractor or adding an array without consumers |
| Session and replay | [FlightSession](../../app/sim/flight_session.gd) has specialized preparation, continuous-state callbacks, reset, trace and checkpoint branches | New modules must own all their state and identity. Existing exclusions, including continuous turbine plus dynamic wheel profiles, remain enforced |
| Workshop | [Descriptor](../../app/workshop/descriptor.gd), [compiler](../../app/workshop/compiler.gd), trial/store/dependency code and generated descriptors already exist | The AE plan still describes implementation as proposed. Module classification is repeated in the Python generator, descriptor validator and compiler; current descriptors do not describe full hinges or model anchors |
| Visual binding | [AirplaneBuilder](../../app/render/airplane.gd) dispatches by aircraft ID and contains datum/control special cases. [TimberModel](../../app/aircraft/timber_model.gd) imports GLB, captures pivot transforms and builds rotor/gear wrappers | Lift reusable bindings out of aircraft-ID switches while retaining the existing procedural builders and compatibility node names |
| Blender handoff | [Timber delivery specification](../BLENDER-AIRCRAFT-HANDOFF.md) already defines editable source, GLB, axes, articulation, section tags, export and verification | Extract reusable rules through a common checked manifest. Keep the Timber letter authoritative for its r2 delivery rather than treating every Timber-specific requirement as universal |
| Ground and impact | [GroundContact](../../app/physics/ground_contact.gd), [WheelProfiles](../../app/physics/wheel_profiles.gd), [HullContact](../../app/physics/hull_contact.gd), session collision and [wreck](../../app/render/crash/wreck.gd) are distinct consumers | Link their geometry and identities explicitly; support points, hull probes, rotor discs and detachable visual sections are different objects |

Two mismatches need explicit reconciliation. Timber's shipped data declares `fixed_voltage`, although the AE fleet table calls its battery finite. The contract's `terminal_hull` summary also omits the current interactive soft-contact route: `_after_step()` can report a scrape and continue, or `_check_prop_strike()` can stop the engine without ending flight. Legacy/script/trace routes can retain immediate hull-contact termination. `HullContact.law()` and session identity already record the soft-contact law. Preserve these distinct behaviors during the first migration; expose their policy instead of silently unifying them.

### Fleet migration fixtures

| Configuration | Behavior that migration must preserve |
| --- | --- |
| `jensen-das-ugly-stik-60` | Legacy prescribed-RPM glow-family propeller, fixed tricycle, explicit wheel-profile attachment and qualified runway route |
| `stik-glow-55ax-2t` | Explicit 2T installation/profile, finite fuel and thermal/lifecycle state; current wheel-profile fallback |
| `stik-glow-fs64v-4t` | Independent 4T law and finite-fuel lifecycle; current wheel-profile fallback |
| `gp-extra-300s-60` | Legacy propeller and fixed taildragger; physical ground support does not itself grant product runway qualification |
| `p51d-mustang-120` | Gasoline hardware under historical `glow_prop`, coupled shaft, angled thrust and wake; gear locked down |
| `sebart-avanti-s-a200-p100rx` | Turbine, declared spool integration policy, gear locked up, airborne-only product route |
| `turbo-lumber-evolution` | Imported r1 model, electric motor/ESC, fixed-voltage bus, taildragger, flaps up and qualified runway route |

Include existing electric regression specimens for finite OCV/resistance batteries. They exercise a capability the shipped Timber configuration does not. Synthetic fixtures prove software behavior, not a measured airplane.

## Contract structure

### Keep one authority for each kind of information

Use the existing data and authoring pipelines with a shared set of stable references:

| Record | Owns | References rather than duplicates |
| --- | --- | --- |
| Physical aircraft definition | Geometry used by physics, inventory, aerodynamic laws/data, control hardware, propulsion/energy installation and contact configuration, with `{value, unit, kind, source}` | Model asset nodes, editor recipes and mutable state |
| Generated model manifest | Asset identity, source/export versions, model-to-datum transform, node/hinge/rotor/gear bindings, visual anchors, section membership and declared clearances | Mass, aero coefficients, force laws, live deflection/RPM and damage thresholds |
| Existing Workshop descriptor | Physical component bindings, module assertions, operation policies and references to the model manifest/dependencies | Another handwritten set of hinges, dimensions or physical values |
| Prepared model | Validated references, transformed arms, derived mass/CG/inertia, compiled control/module layout and immutable lookup tables | Authoring copies of derived quantities or mutable flight history |
| Session state | Continuous, sampled and discrete state, events, model identity and accepted configuration | Hidden constants selected by aircraft name |

The model manifest is a common generated form of existing asset metadata, not a second mesh format. Generalize Timber's existing `openrc-timber-geometry v1` in `geometry.json`, its delivered `metadata.json` and import measurements; do not create a second Timber articulation table. Reuse existing source manifests and the Workshop dependency resolver where applicable. Catalog/resource registration points to these records; do not add another manually maintained fleet database. A saved variant pins their exact relevant revisions and attachments.

Keep physical configuration ID, visual-family key, asset revision and saved-variant ID distinct. The three Stik configurations share a visual family; they should not need three copied model manifests. Replace the current Workshop requirement `visual_id == base_id` with a validated catalog/model binding during the versioned migration. Per-configuration rotor size or other supported appearance changes reference physical inputs through declared bindings.

Stable IDs identify components, surfaces, actuators, propulsion instances, energy stores, contacts and visual sections. Display names and array indices are not durable identities. Current index/name-hash Workshop bindings remain an explicit compatibility adapter until source generators emit stable IDs. Reordering or renaming source entries must regenerate valid bindings or fail; it must never redirect an edit to another part.

A visual section can contain several components and moving nodes. A physical component can have no visible mesh. A contact references its physical role and optional visual section separately. Do not derive mass from mesh volume/material names or fracture strength from `openrc_section`.

### Share semantics without replacing the numerical validators

Extend the existing structural spec/parameter register into a versioned shared description of supported module IDs, law versions, fields, units, defaults, requirements, exclusions and consumers. AS and AE must choose one classification implementation/source, with generated or checked projections for Python tooling and GDScript. Descriptor module lists remain assertions checked against the validated physical model.

Keep coupled constraints in their owning kernels: positive inertia, inventory/CG agreement, force-table coverage, contact support, actuator limits, carrier inertia, timestep stiffness and successful start/trim. A generic schema cannot establish these. Preserve the distinction between an absent module, unsupported module, inactive visual hardware and a physically meaningful zero.

Return structured diagnostics containing a stable code, aircraft/module/component ID, source path, failed condition and remediation. CLI, Workshop and catalog preflight should consume the same result. Unsupported capability combinations fail before flight; optional visual features can be explicitly absent. Declare physically supported, numerically qualified, product-enabled and externally validated status separately.

### Versioning and compatibility

1. Keep `openrc-aircraft v2` accepted through its current strict loader and explicit defaults. V1 remains historical research only. Preserve catalog IDs and public `airplane`, `propeller` and `*_hinge` bindings.
2. Add model metadata and evolve the existing Workshop descriptor through explicit versioned readers. Its current validator has a closed key set: new keys require a reviewed descriptor version/schema change, not an assumed permissive extension. Ordinary catalog flight must continue during descriptor migration.
3. First normalize current data into reusable interfaces with unchanged operation order and laws. Do not force authors to rewrite working aircraft before the compatibility adapter is proved.
4. Use a successor physical format, proposed `openrc-aircraft v3`, when arrays of independently controlled surfaces/propulsors, stable physical component IDs or changed field meanings cannot fit v2 compatibly. Deliver its schema and real consumers together, beginning with an actual extension fixture. Do not publish placeholder active capabilities for unimplemented physics.
5. A migration generates a reviewed candidate; it never silently overwrites source data. Keep v2 input support after adopting v3. Unknown versions/laws fail with a clear upgrade requirement. Export to v2 is allowed only when lossless; otherwise refuse it.
6. Model format, module law, descriptor and checkpoint/trace layout versions are separate. Changed byte/configuration identities may intentionally invalidate old checkpoints even when trajectories match. Preserve existing historical checkpoint rejection rules; never reinterpret an old state array by guessing its layout.

AS-07 records this direction in [DECISIONS](../../DECISIONS.md) after the current interfaces are reconciled. The exact successor schema is an AS-15 deliverable, not a format accepted by today's runtime.

## Blender authoring and import

Use Blender's existing glTF exporter and the pinned Godot importer. glTF provides application metadata through `extras`; OpenRC must validate its own meaning. Keep any downloaded or supplied reusable assets with their provenance and terms. The proposed work is OpenRC binding/verification tooling, not a custom exporter. [glTF specification](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#reference-extras)

The common delivery profile requires an editable `.blend`, a neutral GLB, declared source/export versions and settings, generated metadata, an asset/dependency hash inventory, and inspection evidence. Pin the actual tested tool builds; do not upgrade Blender/Godot as part of this refactor. Preserve Timber r1 and its external delivery. Extend the existing source/measurement/generation pipeline for r2 as its handoff requires: update manifests, measurements, generated bindings, section-map selection and asset-specific checks. It is not a drop-in replacement for the hashed r1.

Common checks must establish:

- **Frames and scale:** explicit units and the transform from Blender/GLB model coordinates to the aircraft datum, applied once. D0 is distinct from CG; do not bake a ground-rest attitude into the flight model. Validate transformed landmarks and left/right signs. V2 retains `openrc-le-frd-v1`; a future convention needs its own adapter.
- **Articulation:** unique stable bindings, correct parent, pivot, named axis frame, saved rest transform and positive deflection. Compare accepted simulator poses with the authored range and checked clearance envelope, retaining distinct values and provenance; Timber's authored aileron range and current flight throw differ. Never silently clamp physical commands to hide a mesh intersection. Specify whether rotation is local-after-rest or parent-frame-before-rest. Timber's two expressions are equivalent only when the axis is transformed consistently. Reject mirrored/sheared or unexpected scaled pivots rather than silently changing signs.
- **Separation:** movable surfaces remain independently driven; rotor, steering, wheel spin and suspension use independent bindings. An aileron can move independently yet detach with its wing. Retain `openrc_section` and its current supported vocabulary through compatibility mappings; no inference from English object names.
- **Neutral and witness poses:** zero restores the imported neutral transform; positive/negative physical commands move the correct trailing edge, hub or wheel. Check full travel and combined supported commands, not just the presence of node names.
- **Geometry alignment:** compare actual mesh landmarks with physical wing/hub/contact/hull data and report intentional differences with their sources. Measured export agreement is distinct from measured real-aircraft accuracy. Reuse Timber's tolerances for its delivery; qualify tolerances for other asset profiles rather than imposing them as physical accuracy.
- **Clean delivery:** no missing resources or studio objects, all required metadata survives Blender export and Godot import, section hierarchy remains usable, material/triangle budgets are recorded, and two independent instances/reset work correctly.

Render front/side/top and witness poses plus overlays for datum, CG, hinge axes, thrust axes, wheel support and hull probes. An exploded section view verifies membership and closure faces. Re-export from a clean package; compare hashes where reproducible and declared normalized geometry/metadata where exporter output is not byte deterministic. Any allowed difference must be explicit and bounded.

Metadata must never invent aerodynamic derivatives, propeller maps, fuel dynamics or fracture strengths. Export measurements carry provenance; the physical generator and loader decide whether the aircraft can fly. No Blender installation is required by the shipped simulator.

## Control surfaces and actuators

Separate pilot intent, mixing, actuator response and aerodynamic surfaces. The initial adapter represents the current roll/pitch/yaw/throttle contract exactly, including differential, rates/expo and servo timing. Keep radio shaping behavior and convert signs/units once. Physics and visuals consume the same accepted actuator/surface state.

The extensible interface identifies each surface's role, attachment/hinge, actuator reference, limits/neutral, control-to-surface mapping and aerodynamic consumer. Mixing is a bounded, validated shared operation with explicit order, saturation and rate limits; no embedded aircraft scripts. Repeated or paired surfaces do not require a new aircraft-specific code branch.

Independent flaps, flaperons/elevons, split elevators, V-tail, spoilers, airbrakes, steering, brakes, retracts and thrust vectoring need separate capability support. A hinge may be declared visual-only while its physical module is unavailable. Stability assists and autopilots belong to an explicit controller module with lifecycle state; hardware presence does not activate them.

Control topology and aerodynamic layout are separate capabilities. The current fixed-wing wing/tail law is not automatically valid for a flying wing, canard, biplane or unusual high-lift layout because its mesh imports successfully. Each new layout must define reference quantities, local load locations, control effectiveness, interference/stall coverage and applicability limits through a supported aero module. An unpowered glider also needs an explicit no-propulsion/start contract. Keep geometry, evidence and law selection separate; six existing wing strips are an implementation of the current law, not a universal authoring requirement.

The first physical extension should be **symmetric flaps on Timber**, after conventional parity, through TT-14 and the shared physics/input capability also required by AV-09. AS owns its contract, while those tracks own flight behavior and calibration. It has existing authored pivots and a concrete user-visible result. Require a flap aero law covering lift, drag, pitching moment, stall interaction and deployment transients, plus provenance and trim/refinement tests. Neutral flaps must preserve baseline behavior. Follow with one mixed-control synthetic fixture to prove the interface is not hardcoded to six Timber nodes; aerodynamic qualification remains separate. AE-05/18 retain Workshop control transformations and editing pages.

## Propulsion and energy

Describe installation geometry independently from the source of power and the device producing force. Initially wrap the existing legacy propeller, coupled shaft, electric, finite-glow 2T/4T and turbine laws without replacing them. `glow_prop` stays a legacy solver-family label; it does not imply nitro fuel or exclude gasoline hardware.

Each supported module must declare:

| Interface | Required meaning |
| --- | --- |
| Preparation | Validated hardware/law/energy/installation references, frame and supported operating domain; qualified solver/attachment combinations |
| Stage evaluation | Pure loads about the shared CG, continuous derivatives and rotating angular momentum/coupling at the stage state/time; no mutation or duplicate stage evaluation |
| State | Ordered named layout with units/domains, continuous versus sampled/discrete ownership, reset/start, finite checks, rollback and versioned restore |
| Energy and mass | Source/store/consumer ownership, power and fuel accounting, mass/CG/inertia contribution policy and exhaustion/cutoff events; no double counting inventory or shared stores |
| Observation | Stable per-instance telemetry and physical anchor references for HUD, sound, smoke and rotor animation; observers never select or modify the law |

Retain fixed voltage versus finite batteries, prescribed fuel versus finite glow, and sampled versus continuous turbine spool as distinct laws. Do not pretend one generic RPM lag models all of them. Preserve current unsupported combinations until their owners supply a consumer and evidence.

Compile module dependencies and deterministic state offsets at preparation, reject cycles/duplicate state writers and commit discrete transitions once after an accepted step. Preserve old trace columns through explicit version adapters; per-instance telemetry needs a declared new layout rather than repurposing the single-engine RPM column. Fingerprint all physics-affecting attachments and record model-asset identity separately so cosmetic revisions cannot masquerade as physics changes.

Prepare for repeated propulsion instances and energy-store references in the successor schema, with deterministic instance ordering and state layouts. Prove a single instance first. A later twin-electric fixture must exercise mirrored mounts, asymmetric power/cutoff, net moment, rotor sense and independent/shared supply behavior only for explicitly supported topologies. A new engine array must not multiply-count fuel, battery current, inertia or gyroscopic reaction.

EDF, pusher, geared/reversible/variable-pitch propulsion, turboprops, hybrid supplies and vectoring remain explicit extension candidates. Each needs installed-force/torque and wake/momentum semantics, energy ownership, failure/start behavior and performance evidence. Reuse available primary data and existing kernels where applicable; do not reuse tractor coefficients as an EDF law. HELI/DR keep their rotorcraft physics and schemas; agree common identity/state/presentation seams without forcing rotors into fixed-wing coefficient fields.

## Contact friction and damage

Model the interfaces separately: **geometry** locates a contact; a **contact law** supplies force/friction; a **response policy** decides scrape, engine stop, collapse or terminal impact; **presentation** consumes the accepted event. Share identities between them without treating them as one mesh or one threshold table.

The common binding identifies wheel support points, hull probes/regions, rotating discs and optional visual sections. Wheel profiles reference stable contact IDs. Wheels must not become duplicate hull crash points. Collision geometry stays simple scalar/float64 data for the flight solver; Godot wreck bodies remain presentation after the flight transition. The field owns terrain/material conditions; aircraft data owns hardware and explicit material/profile references.

Brake parameters in a wheel profile do not supply a player brake command; the inspected session keeps braking off. Deployable gear likewise needs actuator state, changing contacts/drag and qualified start rules before animation can make it an active capability.

Preserve and name the current soft-hull, terminal-hull, prop-strike, gear-collapse and scenery policies. Record policy versions, affected component/contact IDs, tick/event timing, contact lifecycle (new/persistent/ended), point, normal and available impact measures in the shared event interface. A persistent sliding contact must not repeatedly become a new terminal-eligible impact. Do not label a spring force sample as an impulse or assume a scrape carries fracture energy. Define simultaneous-event precedence. Stage damage and presentation events, commit them only after an accepted physics tick and discard them on rollback; replay/reset must reproduce this boundary.

Current `HullContact` estimates include friction 0.4, a 2.5 J/kg terminal normal-energy threshold, 0.08 m crush depth and a 300 RPM prop-strike threshold. These are existing law settings, not universal aircraft properties. First expose their policy identity without retuning them. Wheel friction receives field-surface factors; current hull friction does not. Preserve that difference in compatibility fixtures. A subsequent GP/CR slice can introduce validated material/response profiles with documented estimates or measurements and clear timestep limits.

Keep `crash_hull_components` point labels distinct from detachable `openrc_section` categories. The r1 Timber triangle map remains tied to its GLB hash until a sectioned delivery replaces it. New models declare section membership; they do not need new `wreck.gd` branches. When multiple engines/rotors or new layouts require repeated sections, extend stable section instances and role mappings explicitly while adapting the existing vocabulary.

A broken visual wing is not a flightworthy partial-damage model. Structural failure, flying with detached parts, abrasion accumulation, deformable gear and floats/skis require additional mass/aero/contact state and separate evidence. Existing lake/scenery interactions remain owned by their current systems; a water surface or floating wreck does not enable a floatplane capability.

## Implementation sequence

Every row is pending. Split shared-file changes into reviewable substeps; each must leave the existing application working. Proof is retained under the existing AS evidence hierarchy and linked to the owning physical track where appropriate.

| Step | Work and dependencies | Acceptance evidence |
| --- | --- | --- |
| **AS-06** | Reconcile actual catalog, source pipelines, Workshop state, law/profile selection and documentation; record a reproducible baseline including route/contact policy and dirty-tree boundaries | Auto-discovered fleet/dependency inventory; current module/support matrix; explicitly resolve Timber battery and soft-contact documentation mismatches; baseline test/trace/capture identities |
| **AS-07** | Establish shared module/parameter classification and structured diagnostics using existing AS sources; coordinate AE classification consumers; depends on 06 | Python/GDScript classification and schema/runtime parity; unknown module/field/version and invalid combinations rejected; no change to physical outputs; decision record |
| **AS-08** | Define and generate the model manifest and stable component/contact/section references; AE-01/02 owns the corresponding descriptor/version/resolver change; depends on 07 | Schema, generator `--check`, duplicate/dangling/reordered-binding mutations and exact dependency closure; consume AE's legacy descriptor-reader proof; no handwritten duplicate mass/hinge table |
| **AS-09** | Common Blender/package/import preflight and reusable inspection harness, derived from the existing Timber handoff; depends on 08 | Clean export/import, known landmark transforms, sign/rest/full-travel tests, metadata and section retention; missing-hinge/tag/asset mutations fail; bounded asset/render budgets |
| **AS-10** | Supply AS/model bindings to the shared AE-08 presentation adapter and catalog resolver; retain old procedural builders; coordinate declared anchors with UI/audio/camera/crash owners; depends on 08–09 | Consume AE-08's imported/procedural adapter proof and add physical landmark/anchor checks; independent instances, reset and actual control poses; no second adapter implementation |
| **AS-11** | Normalize the physical/model conventional-control interface and actuator observations with unchanged dynamics; AE-05/18 consumes it for editing; depends on 07–10 | Existing sign/differential/servo/rate/radio behavior and physics/render parity; no-op traces, checkpoint/replay and trim remain correct; no duplicated Workshop transformation rules |
| **AS-12** | Adapt existing single propulsion installations to a common preparation/stage/state/observation interface; one family per substep; depends on 07 and 11 | Legacy, shaft, electric fixed/finite, 2T, 4T and sampled/continuous turbine cases; load/energy/angular-momentum checks, exclusions, reset/cutoff/exhaustion and state-complete replay; measured tick cost |
| **AS-13** | Bind contacts, wheel attachments, rotor discs and sections; expose current response policies and shared impact events; depends on 08, 10 and 12 | Existing tire/soft-hull/terminal/prop-strike/scenery results preserved under the same route/policy; new/persistent contacts, accepted-tick commit/rollback, no double contacts, replay/reset, wheel fallback and correct detached section |
| **AS-14** | Migrate all current physical/model sources and bindings through their generators; depends on 09–13 | All seven configurations plus existing regression specimens; catalog-discovered generator, physics/model/start/contact conformance. Consume AE-19 for Workshop fleet acceptance; this step does not close that gate |
| **AS-15** | Deliver the contract slice for the TT-14/shared AV-09 flap capability: per-surface/actuator identities and symmetric Timber flaps; use v3 if topology changes require it; depends on 14 and the owning input/aero implementation | Explicit v2 adapter/migration, neutral parity, independent flap loads/poses, aero/trim/deployment/refinement evidence, saved variants and traces; second mixed-control software fixture; physical promotion remains TT/physics-owned |
| **AS-16** | Prove propulsion extensibility with a bounded repeated-instance module/fixture; G2/EL owns the law work; depends on 12, 14 and the successor schema decision | Single-instance parity; twin fixture with asymmetric load/cutoff, supported rotor sense, force/moment/energy balance and deterministic per-instance state. Unsupported supply/wake layouts rejected |
| **AS-17** | Make the existing scrape/contact response selectable through qualified shared profiles and harmonize entry routes where deliberately chosen; GP/CR owns changed laws; depends on 13–14 | Same explicit policy yields the same interactive/scripted outcome; dissipative friction, wheel-surface versus hull-factor parity, rest/sticking/sliding/oblique impact, event precedence and rollback/replay; explain intentional new baselines |
| **AS-18** | Supply the authoring/import slice of the AE-25 onboarding experiment and consolidate delivered AS guidance; depends on 14 and each extension advertised as supported | Freeze shared code, import a second distinct Blender delivery using supported capabilities with data/assets/bindings only; link existing AE conformance/fresh-clone/package evidence; author-facing guide/templates; remove completed planning text when consolidated |

Deliver **AS-06–14 first**. This makes the present fleet consistent and new conventional Blender aircraft easier to add. AS-15–17 each introduce or qualify a specific capability; keep them independently reviewable and do not delay the first delivery waiting for EDF, hybrid, rotorcraft or structural damage.

AS-18's second Blender model need not be a newly commissioned airframe: reuse a suitable supplied or freely available asset with suitable terms. It must have genuinely different bindings/geometry, not merely a renamed Timber. AS-08–10 provide the shared contract/import slice of AE-08, not a competing adapter implementation. AE-19 owns Workshop fleet acceptance and AE-25 owns its twenty-entry growth experiment; reuse those results and fixtures instead of creating competing gates or requiring twenty newly modeled airplanes.

AS authoring acceptance can complete independently of AE's later laboratory and UI milestones. Share the import fixture and evidence; report any remaining Workshop gate under AE rather than blocking the physical/model standard or claiming the editor has passed.

## Verification and completion criteria

Use the [canonical tooling](../TOOLS.md), [AS authoring checks](../research/aircraft-standardization/AS-05/README.md#reproduce-or-add-an-aircraft), existing schema/loader mutations, per-aircraft generators and family tests. Extend the common harness; do not copy a test suite per aircraft.

| Gate | What must be demonstrated |
| --- | --- |
| Contract | Strict shapes/units/provenance, references, law composition and Python/Godot agreement; malformed, missing, newer and incompatible input produces actionable errors |
| Numerical compatibility | Same platform/tool build, input, environment, route and policy; compare complete state and relevant loads. Require exact no-op parity when laws/order are unchanged. Any tolerance or operation-order change is justified and measured; never rerecord goldens to hide drift |
| Lifecycle | Fresh start, trim/runway permission, pause, reset, failed load/reload rollback, exhaustion/cutoff/strike, save/restore and replay; all continuous, sampled, discrete and random state accounted for |
| Geometry and controls | Datum/CG/hub/hull/wheel/hinge agreement, left/right and deflection witnesses, physical/visual state agreement, independent instances, correct section membership and restoration |
| Physical changes | Independent analytic/known-answer checks, conservation or dissipation as applicable, local timestep refinement and held-out evidence. Software conformance never promotes estimated aircraft data to measured validation |
| Cost | No source parsing, descriptor traversal or dependency resolution in the 240 Hz tick. Measure per-family p50/p95 and worst relevant contact/wake/event scenarios against the existing 500 µs target; no new performance claim from CI timing alone |
| Distribution | Fresh-clone regeneration/import, packaged resources and hashes, existing platform smoke workflows, and actionable missing-dependency failures; preserve exact pinned dependency versions |
| Onboarding | A supported aircraft is added without changes to solver, shared controls/presentation, Workshop compiler, HUD/audio/crash or per-aircraft test allowlists; only normal source data/assets/registration, generated bindings and evidence change |

The finished author workflow is: select a supported configuration → prepare the Blender package → bind physical components and measured/source-backed data → generate → run one conformance entrypoint → inspect poses/contact overlays → register with its actual qualification status. The tool must distinguish an importable visual model, a numerically admissible airplane and an externally validated airplane.

This planning change modifies documentation only. It does not assert that the new interfaces exist or that the inspected concurrent working tree has passed the implementation gates.
