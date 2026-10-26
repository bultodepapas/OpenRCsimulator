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

The generic kernel now accepts an optional bounded `integration_receipt` from an opt-in `step_policy`, detaches it and forwards it only to the endpoint transition. It is neither a fake flight event nor another checkpoint state. [36 transport checks](../../../../app/tests/test_integration_receipt.gd) exercise the oscillator's accepted substep evidence, rollback, payload limits, mutation rejection, exact continuation and the body-filter flag. The kernel verifies transport integrity; the aircraft policy still must qualify its receipt's physical meaning and failure-localization error. Carrying a peak alone does not authorize applying failure energy at a different endpoint state.

Before enabling stock damage, bind a qualified failed support law and failure-time policy to the complete session state, then qualify continued belly/airframe contact. Full material fracture, accessories, detached mass/aerodynamics, propeller impact transfer and visual recovery remain later masterplan requirements. This foundation neither claims them nor creates a second failure/statistics service.

## Attached effective-compliance response (GP-16b/17b)

2026-10-26. [AircraftGroundDamage](../../../../app/physics/aircraft_ground_damage.gd) closes the former gap between a persistent failure flag and actual subsequent normal forces. `prepare(raw, ground_profile, model)` reuses `AircraftGroundStage.prepare`; `select(prepared, modes, losses, tick)` chooses healthy or authored failed normal resources for that component's existing supports. A healthy stage is byte-identical to the original. Failed stages retain the same fixed hubs, radii, rotor tensors and steering bindings. This is a weaker effective leg/tire response, **not geometric leg collapse or detachment**.

The versioned `openrc-attached-gear-response v1` input contains:

| Field | Contract |
| --- | --- |
| `source` | Bounded nonempty provenance text. |
| `damage` | Existing `openrc-gear-damage v1` component/capacity resource; unknown strength still cannot fail. |
| `supports` | Exactly one `{contact_id, failed_normal}` per installed support; `failed_normal` is the existing provenance-bearing normal-compliance resource. |
| `component_axes` | Exactly one component ID and provenance-bearing `positive_load_axis_body` unit vector in body FRD. Scalar capacity applies only when actual loaded normals align with this axis. |

Both elastic laws retain stroke, stop scale and stop exponent. Failed spring and stop stiffness cannot exceed healthy values, and at least one decreases. Thus, for every compression `x`, `U_failed(x) <= U_healthy(x)`; damping remains passive and may differ independently. This restricted family gives a testable transition without inventing material strength or an energy source.

`transition_at_boundary` evaluates the existing geometry and current normal law at the supplied accepted body state. It checks actual normal directions against each declared structural axis, aggregates each component's load once and evaluates its prospective failed potential at the **same gaps**. Existing `GearDamage.transition` selects simultaneous new failures and books `U_before-U_after` once. The returned selected stage is evaluated again at the same body state. Subsequent stages use the failed response; there is no body-velocity edit or extra normal force. Banked/shear/mount-wrench cases outside the declared scalar domain refuse. A discarded body-filter path also refuses.

The adapter returns detached modes, losses, actual before/after normal observations and existing nonterminal `gear_failure` events with response identity. It changes no live session itself. The caller commits through the existing endpoint transaction; no event escapes a rejected tick. Initial state and checkpoint/reset rules retain their existing owner. Prepared data is bounded before traversal, rebuilt from its authored response and consumed healthy stage/model inputs, then compared in full. A recomputed public hash alone cannot validate altered compiled forces or geometry.

The [125-check adapter suite](../../../../app/tests/test_aircraft_ground_damage.gd) runs the existing common-rotor/RK kernel with synthetic symmetric supports: a light landing remains intact and rebounds, the same gear fails under a heavier dynamic load, and a harder landing fails the otherwise identical light structure. Failed motion continues. Other checks cover progressive-stop energy, an independent left-leg failure producing a roll moment, exact checkpoint continuation, rollback and malformed/tampered resources. The [retained 657-check cohort](evidence/attached-response/README.md) includes existing damage, stage and endpoint regressions.

This API labels sampling `accepted_boundary_only_not_interval_peak`. The synthetic 240/480 Hz comparison does not solve the within-tick overload counterexample above. Locating failure along the accepted contact path, full session/source composition, force-aware hull continuation, moving geometry, calibrated stock capacities and performance remain open. The current correctness-first resource rebuilding is not a hot-path qualification; a runtime owner must safely reuse immutable selected stages across unchanged failure masks and rebind after lifecycle changes. Stock advanced ground profiles remain unavailable.
