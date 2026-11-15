# Gliders, soaring, and aerotow — implementation plan

**Status:** proposed development plan; no glider or towing feature is implemented by this document.  
**Review date:** 15 November 2026.  
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

The first playable milestone is a solo air-start glider with calm air, a valid descent, landing, and replay. Add realistic hand launch next; then thermal lessons; then airborne towing; finally ground aerotow. This sequence exposes the aerodynamic, ownership, and solver problems separately before combining them.

## 2. Read this handoff by responsibility

| Document | Authoritative topic | Primary readers |
| --- | --- | --- |
| This plan | Scope, architecture choice, ten ideas, dependencies, and step status | Technical lead, product, all owners |
| [Launch and control](glider-soaring/01-launch-and-control.md) | Player journeys, launch state, AI duties, ownership transfer, interruption and UI behavior | UI/input, AFC, session, camera |
| [Physics and towing](glider-soaring/02-physics-and-tow.md) | Aerodynamics, trim, energy, two-body mechanics, integration and event contracts | Physics, SF, AS, GP/CR |
| [Aircraft and weather](glider-soaring/03-aircraft-and-weather.md) | Aircraft comparison, data intake, speeds, thermal scenarios and asset provenance | Aircraft/data, M5, art, product |
| [Acceptance and delivery](glider-soaring/04-acceptance-and-delivery.md) | Work packages, verification matrix, rollout, risks and evidence receipts | Engineering lead, QA, release |
| [Dated source review](../research/glider-soaring/2026-11-15-source-review.md) | Exact inspected paths, existing-work reconciliation, primary references and research limits | Reviewers and future implementers |

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

### First release scope

One conventional unpowered trainer; calm and a small set of finite thermal exercises; hand and air starts; two explicit towing roles; physical release and a measured or clearly synthetic towline; receiver/control power assumptions; landing; paired pause/reset/logging; and readable RC controls. Both aircraft continue in the same pair transaction with zero line force after release, until an explicit activity-end transition.

Absent propulsion does not imply absent electrical power. The first trainer must retain the receiver/servo/release-actuator battery mass and an explicit ideal-supply assumption, or use a qualified electronics supply model. Battery depletion and radio/servo failure are separate capabilities; they cannot be inferred from deleting the motor.

Ground tow is a later gate within this plan because it combines glider belly/skid contact, tug wheels, line take-up, AI takeoff, event ordering, and both aircraft's terrain clearance. A complete airborne tow milestone must not be marketed as ground takeoff support.

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
2. Declare and verify both quaternion paths: finite/nondegenerate validation at trial stages, and projection at the qualified accepted integration, substep and event boundaries, resets and restores. Do not blindly normalize every RK trial and thereby change the method.
3. Establish a generic SF-owned layout/projection extension if the adapter cannot satisfy the contract without hidden corrections. No aircraft-type branches in `Simulation`.
4. Qualify event composition before any admitted airborne tow: line release can intersect tug propulsion, energy or failure events even without ground contact. Unsupported intersections reject the whole candidate and pause with a diagnostic. Expand that policy to both bodies' contact events before ground towing; never suppress requested substeps to fit the current single-event interface.
5. Publish and restore the complete pair, including controller memory, weather epoch and ownership.

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
| I06 | Trim, CG and ballast laboratory | Explains wing loading and stability | P2; AS/AE and SG-03 | Inventory changes recalculate mass/CG/inertia and measured performance; invalid builds refuse and baseline can be restored |
| I07 | RC transmitter and mixed-surface trainer | Practices real control assignments | P2; SG-13, AS/AE | Commanded and achieved surfaces, rates, differential and mixes agree; saved mapping and role handoff do not cause surprise deployment |
| I08 | Landing accuracy and approach drills | Adds skill goals beyond duration | P2; SG-04/12/15 | Scoring uses actual touchdown/contact and identifies overspeed, damage and assistance |
| I09 | Two-pilot club aerotow | Makes cooperation a meaningful activity | P3; complete local pair/authority first | One controller owns each aircraft and both observe one release; later network authority handles latency explicitly |
| I10 | Ridge and terrain soaring | Adds slope decisions and new flying sites | P3; M5/LU terrain-flow work | Implemented physical terrain flow passes its tests; calm air does not produce ridge lift from scenery alone |

P1/P2/P3 are recommended sequencing, not estimates of completed work. Competition tasks can be added through I03/I08 with pinned rule editions; no full-scale or competition altitude/speed limit becomes a universal RC rule.

## 7. Delivery sequence and canonical step status

All implementation steps remain pending. The documentation and research intake completed here are the evidence for SG-00's review portion only; owner agreement, implementation and validation remain separate.

| Step | Work | Proof / status required |
| --- | --- | --- |
| SG-00 | Reconcile source, owners, aircraft choice, constraints and decisions | Review captured; confirm owner interfaces and accepted decisions before implementation |
| SG-01 | Extend absent-propulsion data/runtime contract | Invalid data refuses; no phantom thrust/wake/energy/audio; legacy fleet preserved |
| SG-02 | Author the trainer and asset/data pipeline | Provenance, actual configuration, generated conformance and geometry/control checks |
| SG-03 | Qualify aerodynamic model, trim and speed/sink outputs | Calm glide, stall/control, polar and independent measurement evidence |
| SG-04 | Deliver solo airborne flight, landing and replay | Valid descending start, contact lifecycle and exact same-identity replay |
| SG-05 | Deliver unpowered hand launch | Ground-relative release, no post-release energy injection, boundary and real-controller checks |
| SG-06 | Add finite thermal presets and instruments | Current weather schema, analytic field checks, matched flight and honest TE/netto |
| SG-07 | Establish joint body, event, projection and persistence contract | Both-body normalization, atomic rollback/publication, pair checkpoint and legacy equivalence |
| SG-08 | Implement the compliant line and releases | Mechanics/passivity, stiffness admission, convergence and release/event evidence |
| SG-09 | Qualify tow installations and speed overlap | Hook/line/tug data, compatible envelope, weight/balance and available power |
| SG-10 | Airborne tow: AI tug, player glider | Controller envelope, shared weather, manual release and deterministic recovery |
| SG-11 | Airborne tow: player tug, AI glider, then transfer | One owner per actor, actuator continuity, axis pickup and complete pair replay |
| SG-12 | Ground aerotow and aborts | Take-up, dual contact/events, takeoff, clearance, cable-scope and recovery gates |
| SG-13 | Complete input, camera, HUD, accessibility and localization | 1080p inspection; keyboard/gamepad/radio, focus/reconnect and English/Spanish coverage |
| SG-14 | Add bounded failure practice | Evidence-based break if available; engine/control faults and consistent pair lifecycle |
| SG-15 | Lessons, debrief, challenges and statistics | Accepted-event scoring; assistance/version identity; no credit on rollback/restore |
| SG-16 | Physical, pilot and instrument validation | Independent RC measurements, held-out flights, real devices and declared uncertainties |
| SG-17 | Performance, backend, CI and package qualification | Complete supported matrix, 1080p target-host evidence, exact source/package identities |

SG-13 starts with SG-04 and progresses with each new mode; it is not deferred until the end. SG-16 data collection starts with SG-02. SG-07/08 can proceed in synthetic fixtures while aircraft evidence is collected, but must not establish a named-aircraft realism claim.

### Milestones

- **M0 — Data and contract readiness:** SG-00…02. A defensible aircraft can enter the system.
- **M1 — Solo soaring foundation:** SG-03…06 and the relevant SG-13 slice. Deliver air and hand starts, landing, finite thermals and replay. A software-only experimental prototype may precede this gate with explicit estimated data; a qualified named-aircraft claim requires SG-03's independent evidence and SG-16 validation.
- **M2 — Coupled airborne tow:** SG-07…11 and pair presentation. Both requested towing roles work from a validated airborne pair.
- **M3 — Complete launch activity:** SG-12/14/15. Ground tow, aborts and a usable learning loop.
- **M4 — Qualified release:** SG-16/17. Publish exactly the aircraft, modes, weather and platforms that passed.

Assign one writer per path, integrate small reviewable changes, and use the existing test queue/tool workflow. Do not estimate a firm release date until the aircraft data gate and SG-07 prototype have resolved their uncertainty.

## 8. Decisions and explicit limits

Proposed decisions to record in `docs/DECISIONS.md` when accepted:

- D1: pure EasyGlider 4 configuration is the first named physical target; FunCub pairing is the initial towing reference.
- D2: solo gliding precedes paired and ground towing.
- D3: one physical transaction owns both aircraft during the activity.
- D4: v5 spatial weather is shared by position/time; no actor-specific substitute turbulence for a tow pair.
- D5: “release and take glider” is a recorded atomic intent; camera animation does not determine ownership.
- D6: finite thermal recipes and training assistance are labelled explicitly.
- D7: physical aircraft/rope coefficients and software tuning fixtures have separate evidence.
- D8: initially omit unqualified wake, rope entanglement, dynamic soaring, full DLG launch, and networked towing; add through their own gates.

No hidden approval gate is introduced by these proposed decisions. They identify implementation choices for the owning team. This branch contains planning documents and the documentation registry entry; it does not change the runtime, claim passing flight tests, or qualify a real aircraft.
