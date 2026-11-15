# Gliders, soaring, and aerotow — final development plan

**Status:** final audited planning baseline, ready to start the bounded work below; implementation and qualification remain pending. No glider or towing feature is implemented by this document.  
**Review date:** 15 November 2026.  
**Final audit:** [findings, corrections and remaining evidence](../research/glider-soaring/2026-11-15-plan-audit.md), against planning commit `270203ac8a6b0d66385b6705487a0483eccb4ed9`.  
**Research expansion:** [24 additional investigations, GI-01…GI-24](../research/glider-soaring/2026-11-15-investigations.md), completed 15 November 2026; their implementation and qualification experiments remain pending.  
**Reviewed source:** [main at ad21070798bfb9658785576a9c0b8bfc9a71fc7f](https://github.com/bultodepapas/OpenRCsimulator/commit/ad21070798bfb9658785576a9c0b8bfc9a71fc7f).  
**Track:** SG-00…SG-17; physics/simulation leads, with AS, SF, M5, AFC, GP/CR, input/UI, FL, CAM/HUD/AUD, AE, and platform owners retaining their existing interfaces.

## 1. Recommended outcome

Deliver a coherent RC soaring activity with an explicitly unpowered aircraft, credible gliding and landing, repeatable weather, and these four player journeys:

1. Throw the glider by hand and fly it from release to landing.
2. Start airborne in a valid trimmed glide and practice soaring.
3. Control the glider while an AI tug performs the tow.
4. Fly the tug manually while AI flies the glider, then release and transfer control to the glider while AI continues flying the tug.

Treat the paired aircraft as one coupled physical transaction while they share a tow activity. Control ownership and camera target are separate state. Changing either must not reset, teleport, freeze, or retune an aircraft.

The preferred first physical target is a **MULTIPLEX EasyGlider 4 in its documented pure-glider configuration**, followed by a **FunCub-class tug matched to the exact manufacturer-documented pairing**. The aircraft dossier below contains the important missing-data and configuration caveats. A measured named replica is the target; a clearly labelled engineering prototype can unblock software work while its physical evidence is incomplete.

The first playable milestone is a solo air-start glider with calm air, a valid descent, an accepted belly/skid landing outcome, and replay. Add hand launch, then a qualified finite thermal exercise, then the two airborne towing roles, then ground aerotow. Estimated prototypes and physically validated configurations use the same explicit scope/evidence rules below. The synthetic coupled-model experiment and physical measurement program can proceed in parallel with the solo work.

## 2. Read this handoff by responsibility

| Document | Authoritative topic | Primary readers |
| --- | --- | --- |
| This plan | Scope, architecture choice, ten ideas, dependencies, and step status | Technical lead, product, all owners |
| [Launch and control](glider-soaring/01-launch-and-control.md) | Player journeys, launch state, AI duties, ownership transfer, interruption and UI behavior | UI/input, AFC, session, camera |
| [Physics and towing](glider-soaring/02-physics-and-tow.md) | Aerodynamics, trim, energy, two-body mechanics, integration and event contracts | Physics, SF, AS, GP/CR |
| [Aircraft and weather](glider-soaring/03-aircraft-and-weather.md) | Aircraft comparison, data intake, speeds, thermal scenarios and asset provenance | Aircraft/data, M5, art, product |
| [Acceptance and delivery](glider-soaring/04-acceptance-and-delivery.md) | Work packages, verification matrix, rollout, risks and evidence receipts | Engineering lead, QA, release |
| [Dated source review](../research/glider-soaring/2026-11-15-source-review.md) | Exact inspected paths, existing-work reconciliation, primary references and research limits | Reviewers and future implementers |
| [24 follow-up investigations](../research/glider-soaring/2026-11-15-investigations.md) | Decision evidence, applicability limits and discriminating experiments in four research volumes | Aircraft/physics, SF/M5, AFC/input, QA/product |
| [Final plan audit](../research/glider-soaring/2026-11-15-plan-audit.md) | Inspected gaps, their disposition, evidence limits and closure checks | Technical lead, implementers and reviewers |

The [aircraft contract](../AIRCRAFT_CONTRACT.md), [kernel contract](../STACK.md#boundaries-and-data-flow), [wind reference](../WIND-ATMOSPHERE-REFERENCE.md), [flight-log workflow](../FLIGHT-LOGGING.md), and [tool index](../tools/README.md) remain authoritative for existing systems. Do not copy their commands or silently change another track's policy.

## 3. What exists, and what this project must add

The snapshot uses Godot `4.8.beta2.official.cafc17a19`, an application version of `0.2.8`, and float64 simulation state. The application is configured for 240 Hz fixed-step RK4; the kernel fixes the selected timestep for a run, while refinement tests can select other rates. Simulation axes are NED/FRD; rendering converts at its boundary. [Source review](../research/glider-soaring/2026-11-15-source-review.md)

| Area | Inspected foundation | Required work |
| --- | --- | --- |
| Fixed-wing dynamics | Six-degree-of-freedom aircraft, local airflow, trim, control/actuator paths and optional finite-wing polar | Admit and validate a true propulsion-free configuration, its polar and ground contact |
| Starts | Runway, airborne and powered hand-launch machinery | Capability-specific unpowered starts and mission resolution |
| Weather | Versioned spatial wind and finite balanced kinematic thermals | Soaring recipes, shared pair identity, domain-aware admission and truthful lesson design |
| AI | Experimental airborne Ugly Stik circuits with strict source/weather admission | Tow-specific guidance, glider follower, recovery controller and new qualifications |
| Integration | One `VehicleModel` per kernel transaction, sampled controller protocol, continuous state and endpoint transitions | A reviewed multi-body adapter/layout, both-body validation/projection and event composition |
| Persistence | Accepted-state checkpoints and fixed-wing flight logs | Whole-pair restore, event/ownership records and two-aircraft presentation |
| Presentation | RC cameras, HUD, input profiles, audio and localization | Glider controls, vario semantics, tow status, clear ownership and quieter aircraft sound |
| Model data | Generated `openrc-aircraft v2` quantities and capability registry | Explicit absent propulsion and measured glider/tow installations |

Three distinctions prevent misleading scope:

- The current power-off glide of a powered aircraft does not establish propulsion-free aircraft support.
- The existing companion manager is not a tow manager. Its independent sessions, weather restrictions and player-only restoration limitations are material boundaries.
- A visible thermal, cloud, bird or rope does not establish the corresponding physical force or flow.

The consolidated audit was read first. Existing wind/energy, hand-launch, source-admission, recording and control issues keep their original owners and evidence. Historical reports are not treated as newly reproduced bugs.

## 4. Product scope and capability admission

### Initial product scope

One conventional unpowered trainer; calm and a small set of finite thermal exercises; hand and air starts; two explicit towing roles; physical release and a measured or clearly synthetic towline; receiver/control power assumptions; landing; paired pause/reset/logging; and readable RC controls. Both aircraft continue in the same pair transaction with zero line force after release, until an explicit activity-end transition.

Deliver this scope in independently reviewable slices. The claim made by a slice determines its additional evidence; it never changes the implemented forces or bypasses repository checks.

| Declared claim | Evidence needed before making it | What can remain open |
| --- | --- | --- |
| Bounded experimental playtest | Versioned estimated/synthetic inputs with provenance; applicable software, numerical, contact/clearance, control, lifecycle and replay gates; usable supported device/viewport and package evidence for any distributed playtest | Independent aircraft/rope measurements, with physical-fidelity claims withheld |
| Physically representative configuration | Independent measurements and final held-out validation for the exact aircraft, mode and conditions; uncertainty and limitations | Other modes/configurations; solo qualification does not require a tug/rope dossier |
| Practice exercise | Defined objective, achievable admitted scenario, usable controls/cues and honest accepted outcomes | A causal learning-effect claim; that requires a separately designed controlled study |
| Supported package/platform | The existing CI/export/backend rules and actual source/package, device, native 1080p and host evidence for advertised support | Unadvertised platform/device combinations, subject to the repository's required coverage |

These claims are independent: deterministic replay does not establish physical fidelity, and a physically supported model does not establish learning gains. An engineering fixture may start with unmeasured values without closing SG-03/09/16's physical obligations. The tightly separated, contact-disabled SG-07 fixture is not an interactive towing release.

Absent propulsion does not imply absent electrical power. The first trainer must retain the receiver/servo/release-actuator battery mass and an explicit ideal-supply assumption, or use a qualified electronics supply model. Battery depletion and radio/servo failure are separate capabilities; they cannot be inferred from deleting the motor.

Ground tow is a later gate within this plan because it combines glider belly/skid contact, tug wheels, line take-up, AI takeoff, event ordering, and both aircraft's terrain clearance. A complete airborne tow milestone must not be marketed as ground takeoff support.

Minimum solo landing uses the existing authored intended-hull-support observation and statistics chain within its qualified flat-solid/no-lake scope. Contact forces, intended-support observations and landing/stop outcomes remain distinct. For airborne pair use, qualify swept-aircraft exclusion and a truthful rope-clearance outcome before SG-10/11 admission; ground expansion belongs to SG-12. Unknown slack clearance cannot earn successful-tow credit.

### Capability map

The following names describe proposed semantics, not accepted current schema identifiers:

| Capability | Meaning and consumers |
| --- | --- |
| Explicit absent propulsion | No thrust, shaft, propeller wake, fuel draw or engine sound; receiver/servo power remains a separate question |
| Hand release | Supported grip/release geometry, configuration-specific throw envelope and ground clearance |
| Air start | A valid trimmed or explicitly authored airborne state |
| Tow receiver / tow source | Hook geometry, release actuation, compatible line and installation evidence |
| Airbrake / spoiler / flaperon | Only the surfaces and mixes actually installed, with physical and visual response |
| Pair activity | Two actors, shared world, ordered events, whole-pair persistence and ownership |
| Soaring instruments | Explicit altitude-rate, TE and estimated-netto meanings and assistance level |

AS chooses the final names and schema evolution. Unknown combinations refuse launch with an actionable explanation. An absent engine must not be represented by a fake stopped motor. Workshop must not inherit powered-aircraft transformations automatically.

## 5. Architecture recommendation

**Use one coupled model and one transaction for the pair.** Reuse aerodynamic and propulsion evaluators, environment contracts and controller infrastructure. Keep tow-specific laws outside the generic kernel.

~~~mermaid
flowchart TD
  Human["Player input"] --> Commands["Per-actor command ownership"]
  AI["Tug and glider controllers"] --> Commands
  Commands --> Pair["Coupled vehicle model"]
  Weather["Shared weather and terrain"] --> Pair
  Pair --> Kernel["One simulation transaction"]
  Kernel --> Accepted["Accepted pair frame"]
  Accepted --> Commands
  Accepted --> Observers["Views, audio, logs and debrief"]
~~~

The source can carry extra continuous state, but this is not finished multi-body support. In particular, existing integration and stage validation privilege the primary 13-value body, and normal publication exposes that primary body. The plan therefore requires SG-07 before towing:

1. Prove a reference-only airborne composite using both same-stage poses and derivatives.
2. Declare and verify both quaternion paths: finite/nondegenerate validation and a consistent q-to-rotation/inverse convention at trial stages, then projection at qualified accepted integration, substep and event boundaries, resets and restores. Do not blindly normalize stored RK trials and thereby change the method.
3. Establish a generic SF-owned layout/projection extension if the adapter cannot satisfy the contract without hidden corrections. No aircraft-type branches in `Simulation`.
4. Qualify event composition before any admitted airborne tow: line release can intersect tug propulsion, energy or failure events even without ground contact. Unsupported intersections reject the whole candidate and pause with a diagnostic. Expand that policy to both bodies' contact events before ground towing; never suppress requested substeps to fit the current single-event interface.
5. Publish and restore the complete pair, including controller memory, weather epoch and ownership. Bring the minimum SG-15 paired recording/replay slice into SG-07/10/11; richer debrief and scoring can follow.

A second rigid body packed in the continuous tail is a prototype representation to assess, not an adopted public format. The architecture decision must include the smallest generic alternative and its legacy-vehicle equivalence evidence. Separate independently advanced `FlightSession` objects connected by a one-frame-old rope force are not the proposed solution.

Reference GDScript is the first backend. Existing native receipts do not cover a new glider or coupled tow adapter. Native adoption follows the owning backend policy after complete support and qualification; no aircraft requires a native backend.

## 6. Exactly ten simulator ideas

These ideas are proposed development opportunities. Launch, towing and soaring are the core activity; the ideas below turn it into useful RC practice without claiming unimplemented physics.

| ID | Idea | Value | Priority / dependency | Observable acceptance |
| --- | --- | --- | --- | --- |
| I01 | Guided hand-launch and recovery lessons | Makes the first session understandable | P1; SG-04/05 | Guidance identifies release, airspeed margin and landing; any automatic help is recorded and does not secretly change forces |
| I02 | Energy and variometer trainer | Teaches speed, height, sink and lift | P1; SG-03/06 | A zoom climb is distinguishable from sustained rising air; TE/netto labels, filters and units are correct |
| I03 | Repeatable weather challenges | Allows fair comparisons of decisions | P1; SG-06 | Full law, agenda, epoch, aircraft and assistance identity reconstruct the exercise |
| I04 | Flight debrief and comparison | Connects stick use to aircraft behavior | P1; SG-03/15 | Event timeline, ground track, speed and thermal circles match the accepted flight and show missing data honestly |
| I05 | Tow instructor and abort practice | Teaches slack, climb, turns and release | P2; SG-08…12/14 | Successful and aborted runs use the same pair dynamics; interventions and line assumptions are visible |
| I06 | Trim, CG and ballast laboratory | Explains wing loading and stability | P2; AS/AE and SG-03 | Inventory changes recalculate mass/CG/inertia and predicted performance, with measured comparisons identified separately; invalid builds refuse and baseline can be restored |
| I07 | RC transmitter and mixed-surface trainer | Practices real control assignments | P2; SG-13, AS/AE | Commanded and achieved surfaces, rates, differential and mixes agree; saved mapping and role handoff do not cause surprise deployment |
| I08 | Landing accuracy and approach drills | Adds skill goals beyond duration | P2; SG-04/12/15 | Scoring uses actual touchdown/contact and identifies overspeed, damage and assistance |
| I09 | Two-pilot club aerotow | Makes cooperation a meaningful activity | P3; complete local pair/authority first | One controller owns each aircraft and both observe one release; later network authority handles latency explicitly |
| I10 | Ridge and terrain soaring | Adds slope decisions and new flying sites | P3; M5/LU terrain-flow work | Implemented physical terrain flow passes its tests; calm air does not produce ridge lift from scenery alone |

P1/P2/P3 are recommended sequencing, not estimates of completed work. Competition tasks can be added through I03/I08 with pinned rule editions; no full-scale or competition altitude/speed limit becomes a universal RC rule.

## 7. Delivery sequence and canonical step status

All implementation steps remain pending. The documentation, research and final audit complete SG-00's review portion only; owning-interface decisions, implementation and qualification remain separate. The milestones select explicit slices of these steps. A passed experimental slice does not close its physical-evidence obligations or an entire cross-cutting step.

| Step | Work | Proof / status required |
| --- | --- | --- |
| SG-00 | Reconcile source, owners, aircraft choice, constraints and decisions | Review captured; confirm owner interfaces and accepted decisions before implementation |
| SG-01 | Extend absent-propulsion data/runtime contract | Versioned absence through identity, normalized data, observations, rotor/contact metadata, logs and consumers; invalid data refuses; legacy powered identities/behavior preserved |
| SG-02 | Author the trainer and asset/data pipeline | File-specific provenance, exact build, independent mass/CG/inertia, source polar meaning and generated geometry/control checks |
| SG-03 | Qualify aerodynamic model, trim and speed/sink outputs | Bounded prototype trim/polar first; independent physical data, model-selection/final-holdout separation and uncertainty for the declared Re/rigidity/configuration claim |
| SG-04 | Deliver solo airborne flight, landing and replay | Valid descending start; authored intended-hull support, accepted landing/stop/incident outcome; basic recording, restart and exact same-identity replay |
| SG-05 | Deliver unpowered hand launch | Correlated measured ground-relative release state, marker-to-CG conversion, no extra energy injection and real-controller checks |
| SG-06 | Add finite thermal presets and instruments | Current weather schema, analytic field checks, matched flight and honest TE/netto |
| SG-07 | Establish joint body, event, projection and persistence contract | Both-body normalization, atomic rollback/publication, pair checkpoint and legacy equivalence |
| SG-08 | Implement the compliant line and releases | Mechanics/passivity, stiffness admission, convergence and release/event evidence |
| SG-09 | Qualify tow installations and joint tow envelope | Synthetic prototype bounds or measured installation identified; hook moments, joint trim/control margins and power always checked; physical claims additionally need installed rope/pair evidence; wake limits explicit |
| SG-10 | Airborne tow: AI tug, player glider | Controller/shared-weather envelope, airborne swept exclusion, release, deterministic recovery/fault outcome and minimum full-pair record/replay |
| SG-11 | Airborne tow: player tug, AI glider, then transfer | Combined and release-first/later takeover; bounded AI free-glide/recovery; one writer, actuator/pickup continuity, airborne exclusion and complete pair replay |
| SG-12 | Ground aerotow and aborts | Take-up, dual contact/events, takeoff, clearance, cable-scope and recovery gates |
| SG-13 | Complete input, camera, HUD, accessibility and localization | Native 1080p visibility/response timing, actual radios, applied-command/actuator continuity, focus/reconnect and English/Spanish coverage |
| SG-14 | Add bounded failure practice | Evidence-based break if available; engine/control faults and consistent pair lifecycle |
| SG-15 | Recording, lessons, debrief, challenges and statistics | Minimum solo outcome/record with SG-04; paired format/replay with SG-07/10/11; richer accepted-event lessons/debrief later, without duplicate rollback/restore credit |
| SG-16 | Physical, pilot and instrument validation | Evidence per advertised claim: independent RC measurements, final holdout, uncertainty and applicable device/usability checks; controlled studies for causal learning claims |
| SG-17 | Performance, backend, CI and package qualification | Applicable evidence at every distributed slice; required supported matrix/CI, 1080p target-host and exact source/package identities |

SG-13/15/17 start with the first affected slice and progress with each new mode. SG-16 measurement design starts with SG-02; causal learner studies are conditional on the claim. SG-07/08 can proceed in synthetic fixtures while aircraft evidence is collected, but must not establish a named-aircraft realism claim.

### Milestones and dependencies

M1 and M2 have smaller checkpoints so the first useful slice is explicit. All remain pending. The [acceptance guide §12](glider-soaring/04-acceptance-and-delivery.md#12-select-gates-for-the-declared-milestone-and-claim) owns the applicable proof matrix.

| Checkpoint | Depends on | Deliverable and completion condition |
| --- | --- | --- |
| M0 — Contract and data entry | SG-00 reviewed first-slice interfaces | SG-01/02 admit a generated unpowered configuration, explicit source assumptions, intended support and negative cases while preserving powered aircraft; estimates may remain experimental |
| M1a — Calm solo, first playable slice | M0; bounded SG-03 trim | SG-04 plus first SG-13/15/17 slices: air start, descending flight, control, landing/stop/incident outcome, basic record/debrief, restart and exact replay |
| M1b — Hand launch | M1a | SG-05 release state, cancellation and one-shot action; estimated or measured release clearly identified, with the claimed launch envelope checked |
| M1c — Finite soaring exercise | M1a; SG-06 field/instrument checks | At least one admitted finite thermal recipe with useful cues, expiry and return; each additional recipe qualifies separately |
| M2a — Coupled feasibility proof | Independent of real-aircraft data; SF/physics fixture scope | SG-07/08 bounded same-stage pair, line, rotation/event/rollback proofs; choose production representation from this evidence; establish the minimum pair state/record contract |
| M2b — AI tug, player glider | M1a + M2a; SG-09 envelope for declared parameters | SG-10, airborne T13 exclusion, release/recovery/fault lifecycle and complete pair record/restore/replay; physical installation remains experimental until separately validated |
| M2c — Player tug, then glider | M2b; admitted follower/free-glide and tug recovery | SG-11 combined action and release-first/later takeover, input readiness, one effective writer, complete accepted-event replay and post-release failure outcome |
| M3 — Ground activity and richer lessons | M2c; GP/CR/SF ground event proof | SG-12 ground take-up/release/abort and dual contact; applicable SG-14 failure practice; SG-15 richer debrief/scoring and no unsupported success credit |
| M4 — Release of the declared slice | Applicable earlier checkpoint and required repository gates | SG-13/16/17 evidence supports exactly the advertised aircraft, modes, weather, devices, platforms and claims; an earlier scoped release does not require completion of later optional modes |

Hand-launch/thermal work and the coupled feasibility work can overlap. Nonzero-weather towing waits for its own pair/controller/weather evidence; solo thermal completion does not admit it. M4 is applied to each distributed release candidate, including a scoped experimental release, rather than delaying all use until the largest feature set exists.

### First implementation packets

| Packet | Accountable lead / collaborators | Bounded result |
| --- | --- | --- |
| 1. Absent-propulsion contract | AS / physics, SF, FL, AE, AUD | Version the absence/identity/observation design; implement one generated reference fixture and incompatible-data cases; preserve powered IDs and consumers |
| 2. First solo activity | Session/physics / GP, UI-FS, input, FL | After packet 1: calm descending start, authored belly support, accepted outcome, controls and minimum complete replay; use current flat-solid field scope |
| 3. Pair feasibility | SF / physics, FL | In parallel: fixed-mass synthetic two-body fixture, passive line, stage rotation/event policy, rollback, bounded refinement/cost and a documented representation choice |
| 4. Physical data program | Aircraft/FT / AS, physics | In parallel: exact build/asset intake, mass/CG/inertia and control/release protocol; separate calibration, selection and final validation data |
| 5. Pair control and record interfaces | AFC/input / session, SF, FL | Alongside packet 3: actor IDs, command arbitration, released-glider fallback, takeover/readiness, recovery outcomes and pair record schema before SG-10/11 integration |

Assign one writer per path, integrate small reviewable changes, and use the existing test queue/tool workflow. Do not estimate a firm release date until the aircraft data gate and SG-07 prototype have resolved their uncertainty.

## 8. Decisions and explicit limits

Planning defaults to carry into the owning design decisions, with the implemented choice and evidence recorded in `docs/DECISIONS.md`:

- D1: pure EasyGlider 4 configuration is the first named physical target; FunCub pairing is the initial towing reference.
- D2: solo gliding precedes paired and ground towing.
- D3: one physical transaction owns both aircraft during the activity.
- D4: v5 spatial weather is shared by position/time; no actor-specific substitute turbulence for a tow pair.
- D5: “release and take glider” is a recorded atomic intent, with release-only followed by later takeover also supported; camera animation does not determine ownership.
- D6: finite thermal recipes and training assistance are labelled explicitly.
- D7: physical aircraft/rope coefficients and software tuning fixtures have separate evidence.
- D8: initially omit unqualified wake, rope entanglement, dynamic soaring, full DLG launch, and networked towing; add through their own gates.

The remaining engineering decisions have named owners and deadlines in the sequence. They are implementation work, not requests for new user approval.

| Open decision | Owner | Resolve before / required output |
| --- | --- | --- |
| Absent propulsion, identity and observation version | AS + SF/FL | M0 production admission; compatible normalized model, trace/log and consumer contract with negative cases |
| Minimal pair layout, trial rotations, projections and events | SF + physics | Production adoption after M2a; fixture comparison, bounded failure and legacy-equivalence evidence |
| Synthetic/installed line, solver policy and admitted envelope | Physics + aircraft/FT | M2b; versioned law/parameters, convergence, joint trim and cost; physical claims additionally need installed measurements |
| Input pickup, free-glide/recovery and terminal policies | AFC + input/session + FL | M2b/M2c; one-writer state transitions, source/device identity and both takeover/failure paths |
| Belly support and landing observation | AS + GP/UI-FS | M1a; generated hull identity/pose, accepted support and correct outcome in supported terrain |
| Weather, instrument identity and task feasibility | M5 + scenarios/HUD | M1c and each later weather admission; complete field/epoch/sensor object and return/expiry proof |
| Named build, permitted assets and final validation data | Aircraft/AS + FT | Any named physical claim; exact installation, file provenance and independent held-out evidence |

Do not invent calendar estimates while the data and coupled-model feasibility are unresolved. The first packets can start now, and evidence from them determines subsequent sizing. This final plan does not claim executed simulator, physical, device or learner qualification.

## 9. Research refinements adopted into this plan

The [GI-01…24 investigation set](../research/glider-soaring/2026-11-15-investigations.md) strengthens the existing sequence without adding new SG implementation steps. The four supporting guides now require:

- **Aircraft evidence:** independent air-motion-aware polars and mass/inertia, meaningful low-Re and rigid-airframe domains, actual surface mixing and correlated release samples.
- **Tow evidence:** installed line histories, joint trim/control authority, both-body energy ledgers, solver/event comparison, swept clearance and attainable AI commands.
- **Weather and instruments:** shared-field coherence and M5 boundary/flux qualification, bank/sink/return tasks, explicit truth-versus-sensor cues and complete atmosphere/epoch identity.
- **Usability and delivery:** controller-state tracking at the correct command boundary, RC camera/latency evidence, exact pair replay, file-specific reuse checks and decision-based lesson evaluation.

The first wake-omitted tow remains experimental with respect to wake exposure. The cited small-propeller measurement range does not justify a three-diameter clearance rule, and no such rule is adopted. A future wake capability needs its own installation-specific data and law identity. Existing independent collision gates still apply.

Start the measurement program with SG-02/03 and GI-01…06/GI-22 while SG-07/08 uses bounded synthetic fixtures. Prioritize unresolved inputs by their demonstrated effect on the intended flight or lesson, and keep prototype, physical, human and platform claims separate. The [acceptance additions](glider-soaring/04-acceptance-and-delivery.md#11-research-driven-acceptance-additions) map every investigation to an observable gate.

The [final audit](../research/glider-soaring/2026-11-15-plan-audit.md) closes the planning gaps in takeover/recovery, milestone logging, early collision and landing outcomes, claim-dependent admission, ground release, feasibility sequencing and final-holdout independence. It preserves the ten ideas, 18 SG steps and 24 investigations. Use this master and the four topic guides as the current plan; the dated research/audit records explain the evidence and corrections.
