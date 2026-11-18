# Contact ownership improvement plan

**Date:** 18 November 2026, America/Bogota.

**Basis:** [CR-AUD-25 through CR-AUD-27](contact-ownership-2026-11-18.md), application baseline `a7de9b35676d891bc2034cc344b910d9e1ef9c61`.

**Status:** proposed implementation work. This audit branch implements reproductions and documentation only.

## Decisions established by this pass

The three reproductions concern different owners. A propeller's finite geometry determines whether a contact exists. A car's contact witness determines which damage channel should receive a localized impact. A deployed aircraft wheel needs a supported obstacle response distinct from terrain support and body-crash detection. A shared contact record can make these boundaries consistent without moving vehicle-specific policies into the simulation kernel.

The recommended sequencing is **CR-AUD-25, then CR-AUD-26, then the capability design for CR-AUD-27**. This ordering does not supersede earlier urgent findings such as omitted world geometry or discarded nonterminal helicopter contacts. The [original plan](improvement-plan.md), [second plan](deep-dive-plan-2026-11-18.md), and [third plan](edge-case-plan-2026-11-18.md) remain their authoritative scopes. In particular, correct contact existence and the coupled energy budget together before treating quad prop strikes as qualified.

| Slice | Primary owner boundary | Reviewable result | Required exit evidence |
|---|---|---|---|
| CO-1 / CR-AUD-25 | Multirotor plant and obstacle adapter | Finite per-proxy prop contact with consistent witness identity | Six retained cases; finite-shape boundary checks; accepted-tick/reset/replay and bounded-cost evidence |
| CO-2 / CR-AUD-26 | Ground-vehicle dynamics telemetry and damage observer | Contact-owned damage location with explicit sharing policy | Both stock cars; signed drift and straight controls; multiple contacts; observer atomicity and visual-consumer qualification |
| CO-3 / CR-AUD-27 | Fixed-wing ground support and scenery arbitration | Explicit wheel-obstacle capability with authored geometry and response | Compression/retraction cases; low obstacles; terrain/body duplicate suppression; gear-up and no-gear controls |

These are audit slice labels, not replacements for the owning DR, GP, CR or vehicle-track step IDs. Implementation PRs should map each slice to those existing plans and preserve their interface ownership. No schedule or performance budget is invented from the headless probe runtimes.

## CO-1 — Preserve finite obstacle identity through prop contact

### Contract and implementation direction

The retained [CR-AUD-25 source path](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/physics/multirotor/controlled_plant.gd#L1024-L1068) currently derives depth from hub clearance and directional disc support. The [session query](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/sim/multirotor/session.gd#L669-L713) returns a minimum scalar and separately selected class. Introduce a bounded query that retains the candidate proxy through geometric admission and response preparation.

The result should identify the proxy and feature, rotor index, represented geometry version, contact witness in a declared frame, normal, signed separation or penetration, material/response class, and query status. Every field used by the response must refer to the same admitted candidate. Define deterministic tie-breaking and distinguish no contact from invalid or unresolved geometry. Avoid mutable query caches that change accepted results or replay identity.

Use the disc's spatial extent to request potentially intersecting proxies. Evaluate the admitted finite box/capsule geometry against the represented thick disc; do not use the nearest object to the hub as the sole candidate. Broad-phase bounds can be conservative, but they must not directly create wear, a kick or a body push-out. A change in normal-sampling step alone would leave the finite-shape and candidate-selection problems unresolved.

Keep the response policy separate. Once contact exists, shaft braking, body impulse, positional correction, material wear and break thresholds still require the energy checks in CR-AUD-21. A new geometric witness must not silently change body/shaft reference frames or multiply one physical contact across adjacent proxy fragments. If multiple props or objects contact simultaneously, declare whether response is accumulated, solved jointly or deterministically reduced, and test that choice.

### Acceptance gates

1. Run the retained six-case probe against the candidate. The 12 mm separated spinning case must produce no contact-caused state change. The true overlap must remain eligible when the separated decoy is added. Remote, stopped and overlap controls must retain their intended distinctions.
2. Add focused boundary cases for admitted shapes: face, edge, corner, inside/outside, rotated boxes, capsule end and side, a nearest-object switch and a spatial-bin seam. Assert finite geometry with an independent witness or separation bound; do not make the same distance-field approximation the test oracle.
3. Specify tolerance units and their relationship to model scale. Check translation/rotation of a whole fixture, stable proxy ordering and more than one intersecting candidate. Preserve an explicit bounded refusal/degradation result for exhausted capacities.
4. Exercise an accepted session transition from a qualified initial state and inspect body, rotor health, angular rates, events and checkpoint content. Direct pure-transition results remain useful unit evidence but cannot close accepted-state coverage.
5. Re-run the affected energy, reset/checkpoint and exact replay controls, including source-off or stopped distinctions when those capabilities apply. Preserve model/solver/contact-geometry identity changes rather than accepting old logs as equivalent by default.
6. Measure actual query work for sparse and dense admitted scenes on the owning track's target hardware. Retain counts, hardware and settings. This pass's roughly three-second process duration includes startup and cannot be used as a collision-cost benchmark.

The first PR should freeze the contact contract and failure semantics with a minimal box implementation. Additional shape coverage and optimization can follow as separately qualified changes. Keep stock behavior behind an explicit capability/version boundary while unsupported shapes remain unresolved.

## CO-2 — Attribute body damage from the contacting feature

### Contract and implementation direction

The [current observer](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/physics/ground_vehicle/vehicle_damage.gd#L103-L136) computes one velocity-derived region before handling the wall episode. The dynamics already exports [per-probe wall loads](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/physics/ground_vehicle/vehicle_dynamics.gd#L863-L902). Preserve enough geometry/ownership information for the observer to associate admitted damage with an explicit body region.

Define how hull probes map to front, rear, left, right and bottom. Use validated authored identifiers or a documented geometry rule; array position alone is not a portable semantic name across the fleet. In this evidence, probe 0 is independently verified as frontmost, but only one vehicle's inventory explicitly labels it a front bumper. Include mapping identity with any state/replay contract affected by the change.

A minimal correction may allocate an existing damage budget using validated per-probe contact weights. State the limitations: an endpoint force is not contact work over an interval, and the existing energy residual is not a calibrated component fracture law. A later contact-work model should preserve impulse/work provenance through the accepted transition. Do not increase total episode damage merely because there are more probes, substeps or mesh pieces.

Preserve the existing wall-versus-hull duplicate guard. Define how simultaneous wheel and body contacts share an episode, how multiple body regions divide a budget, and how a contact that begins and ends within one tick reaches the observer. Reject malformed ownership atomically, keeping the prior damage snapshot intact. Regional body damage and the global drive-damage channel should remain distinct decisions.

### Acceptance gates

The present controls establish a narrow, useful invariant: after a qualified front-only hit, changing the sign of tangential drift must not move localized body damage to the opposite side. Run both stock vehicles, preserve all six admission checks, and retain the straight/no-wall controls. Add a case where the actual side probe contacts, plus a multiple-region case with a declared total budget. A car merely moving sideways without contact must not acquire damage.

For accepted ticks, verify the per-probe load/feature identity, body and damage state, event order and recorded control tape. Keep the reference backend identity explicit; these results do not qualify a native backend. The retained synthetic-road fixture must continue to disclose its override. If future persisted recordings are used as evidence, they must encode or otherwise reproduce that actual fixture rather than identify the unmodified stock course.

The output channels feed [directional mesh and bumper changes](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/vehicles/ground/ground_damage_view.gd#L109-L139). After numerical attribution passes, perform a targeted rendered inspection at the project's primary 1920×1080 target: front, side and mixed-contact damage should affect the intended regions, and reset should restore the original mesh/transforms. This is a future gate; no such capture was made in this pass.

Do not tune damage-energy constants to make the present side-channel failures disappear. The measured defect concerns location. Severity calibration needs separate controlled measurements and cannot be inferred from the 3.0–3.2% channel increments in the synthetic fixture.

## CO-3 — Design wheel-versus-obstacle support as an explicit capability

### Geometry and owner policy first

The [aircraft contract](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/docs/AIRCRAFT_CONTRACT.md#L191) deliberately separates wheel support from crash-hull witnesses. Respect that ownership. Define the wheel's radius, width, axle frame, compression, steering, spin and retract state at the actual accepted pose before selecting a collision representation.

The retained test uses an undeformed support point, supplemented by a derived vertical projection onto terrain. It does not choose a correct finite-wheel model. The first design PR must state what geometry is simulated and what remains unsupported: rolling over a small curb, a face strike, an edge snag, wheel-side scraping, a partly extended gear, and a strut/body hit can need different witnesses and laws. A retract command is not an instantaneous wheel pose.

Create a wheel-obstacle owner that can share candidate geometry and event ordering with existing scenery detection without duplicating terrain support. Decide how the wheel, suspension, brake/spin and airframe exchange forces and impulses; define a bounded response if the obstacle cannot be resolved within the accepted step. A gentle curb response need not be a terminal crash, and a no-response result should only mean a geometrically or physically admitted clearance case.

If physical gear damage is enabled, explicitly connect load/energy and affected parts to its state contract. Cosmetic dents, a gear failure, prop contact and terminal airframe destruction are separate outcomes. The present audit does not authorize assuming a calibrated gear-break threshold or activating an experimental damage module in every stock aircraft.

### Acceptance gates

| Scenario | Required qualification |
|---|---|
| Current Avanti low-box fixture | Preserve the original observation; add finite-wheel geometry and show a defined wheel response or a rigorous geometric clearance result |
| Terrain-only taxi and landing | Ordinary compression/friction/rolling behavior remains covered; no duplicate body crash |
| Low curb, taller face, side brush | Contact witness, normal, force/impulse budget and suspension response match the declared representation |
| Partially extended and fully retracted gear | Geometry follows accepted mechanism state; body/belly owner remains responsible where appropriate |
| Gear-free aircraft | No synthesized wheels; existing belly/airframe policy remains explicit |
| Wheel, strut and hull in one interval | Deterministic event ordering and no duplicate energy/damage allocation |
| High angular rate or narrow obstacle | Swept coverage or an explicit unresolved-domain outcome; endpoint sampling alone does not certify the path |
| Reset, pause, checkpoint and replay | New contact/mechanism state is complete, identified and restored consistently |

The current nominal point enters the low box around tick 22; it does not define when a finite tire should first touch. Preserve that distinction when comparing candidates. Use the actual local terrain height when describing obstacle exposure, and keep sample-based hull-clearance claims separate from full swept-volume claims.

## Integration, observability and closure

Retain a bounded contact record suitable for debugging: accepted tick, vehicle/part identity, obstacle identity, witness frame, normal, query status, region mapping and response type. Record enough to connect geometry to state change without logging unbounded per-frame arrays in the production hot path. Counters for candidate count, rejected/ambiguous queries, capacity exhaustion and response cost should make performance limits observable. Their thresholds need measurement in the owning performance campaign.

Each implementation PR should link its finding, identify the exact runtime tree, enumerate changed contracts, run the smallest behavior-relevant controls, and retain failures as failures. Broaden validation only for a concrete shared dependency or required CI gate. The three audit probes contain intentional red assertions; do not convert them into passing tests by weakening their admission guards or asserting the current wrong result.

Closure requires both the corrected local behavior and the relevant accepted-state/consumer gates above. A source change, a clean parser or an attractive crash animation alone does not close contact geometry, localization or wheel-obstacle coverage. Update the owning implementation plans while retaining this dated baseline and its [verification evidence](contact-ownership-verification-2026-11-18.md).
