# GP-16/17: persistent attached-gear damage transactions

2026-10-25/26 software foundation. [GearDamage](../../../../app/physics/gear_damage.gd) implements the explicitly experimental `experimental-brittle-normal-capacity-attached-v1` law. It does not yet change stock aircraft support geometry or provide measured breaking loads. The [GP-11 integration record](../GP-11/README.md) and [masterplan](../../../advanced-ground-flight-physics-masterplan.md) retain those gates.

## Component and failure ownership

`prepare(raw, installed_support_ids)` binds every installed support to exactly one component, with disjoint groups and canonical component ordering. A main gear assembly may own both main-wheel supports. Its capacity is not duplicated per wheel, contact probe or scrape frame. Optional `normal_failure_force` is a positive provenance-bearing N quantity. Missing strength remains unknown and cannot trigger this physical failure law.

`sum_aligned_normal_loads` is available only after the aircraft adapter explicitly qualifies aligned positive structural axes. Arbitrary banked contact normals, bending/shear, mounting moments and combined-load envelopes require a local structural wrench model; the scalar helper does not silently stand in for one.

Each component has a healthy/failed-attached mode, its first failure tick and a cumulative transition-loss entry in joules. A known healthy component fails once when its accepted aggregate normal load exceeds its declared capacity. The criterion contains no aircraft-mass category, arbitrary universal sink-speed threshold or automatic simulation termination. Using the same actual gear on a heavier aircraft changes applied loads through dynamics, not through a special heavy-aircraft multiplier.

At the same body state, the caller supplies current total support potential and the candidate failed support's potential. Both include elastic spring, progressive stop and any anchor energy once. Only a new failure may consume the nonnegative difference. Damper heat, slip heat and an unrelated aircraft kinetic-energy budget are not fracture inputs. A candidate that needs extra potential energy, produces overflow or has invalid state rejects the entire multi-component batch. Velocities, mass and CG are untouched by this helper.

`gear_failure` events carry deterministic generation/component/tick identities, the criterion and capacity, load, before/after potentials, loss provenance, profile identity and `terminal=false`. Repeated contact cannot charge the loss or emit the same failure again. The adapter must install its declared failed support law after acceptance; an event alone does not collapse a visual or physical leg.

## Kernel transaction

[VehicleModel](../../../../app/sim/vehicle_model.gd) adds optional `state_layout_identity`, `endpoint_transition` and `state_validator`. Opt-in models declare explicit continuous/auxiliary/mode sizes. The transition receives detached previous/candidate frames and accepted clock/body-filter context, then returns same-size body, continuous, aux, modes and bounded events. The kernel validates the entire result after final auxiliary projection and commits it together. Rejected results restore the previous boundary and emit no phantom damage.

The final validator receives `{tick,time_s,dt}` at reset, current/accepted step boundaries and checkpoint restore. A future failure tick cannot become valid merely because the currently running simulation is older than the saved checkpoint. Opt-in checkpoint v2 pins the state-layout identity; legacy models retain the previous v1 route. New callback guards reject live state/model edits and reentrant operations; these are deterministic contract checks, not a sandbox for arbitrary scripts. Prepared reset receipts are sealed to their preparing owner and context, and commit reports rejection to callers.

[113 damage checks](../../../../app/tests/test_gear_damage.gd) cover strict binding/provenance, unknown capacities, grouping invariance, persistent modes, exact loss closure, batch atomicity, event deduplication, malformed clock/state, checkpoint continuation, reset and continued body motion. [274 endpoint checks](../../../../app/tests/test_endpoint_transition.gd) cover fixed-layout validation, callback mutation/reentry, final-projection rejection, event constraints, restored clock and owner-specific reset receipts. Repeated assertions are software verification, not independent real-aircraft observations.

## Required adapter work

The current FlightSession's propulsion/ground prefixes, mode counts, checkpoint identities and reset lifecycle must admit these blocks explicitly. The existing travel-overrun `_crash` path must not be used as this strength criterion. A body filter that discarded part of a trajectory invalidates any energy proof evaluated at the discarded body; the new context exposes that condition. Peak loads between accepted ticks need an integration policy that locates or carries qualified accepted substep evidence, not a presentation observer.

A concrete kernel reproduction demonstrates the last requirement: a 1 kg body on an undamped 1000 N/m support, starting at zero compression and 1 m/s closing speed, reaches about 31.65 N within a 0.1 s tick resolved with 16 substeps. The endpoint is already airborne with zero support force. A 20 N capacity is exceeded during accepted motion but an endpoint-only comparison reports no failure. The analytical peak is 31.623 N. Carry only evidence from the accepted integration path, locate the transition or qualify a conservative admission bound; mutable maxima collected from trial RK stages can include discarded paths and are not a valid repair.

Before enabling damage, define the actual failed support geometry/law, validate its potential transition and qualify continued belly/airframe contact. Full material fracture, accessories, detached mass/aerodynamics, propeller impact transfer and visual recovery are later masterplan requirements. This foundation neither claims them nor creates a second failure/statistics service.
