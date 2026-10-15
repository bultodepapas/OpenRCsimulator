# SF-04 — One event protocol: declared boundaries, the kernel's locator and a per-tick event record

2026-10-15 · **Status: implemented, byte-identical: 24/24 fleet runs (eight airplanes and two synthetic electric fixtures, each plain and with a source cut, helicopter hover, hover with rotor hold and pad start, and the truck) hash identically against HEAD; the 38-check protocol test and the event, kernel, electric, glow, helicopter and replay suites pass; the full test loop matches HEAD program for program.** Step SF-04 of the [simulation foundation plan](../../../plans/simulation-foundation.md).

## What the protocol is

- **Declaration.** A `VehicleModel` may declare one tick event: `{type, index, transition}`, where `index` addresses a continuous value (combined index at or beyond the rigid body) that must stay at or above zero, and `transition(state, index)` applies the discrete change at the crossing. A model that composes several boundaries keeps a `step_policy` instead; declaring both is refused.
- **Locator.** [`app/physics/event_step.gd`](../../../../app/physics/event_step.gd) runs RK4 trials through the kernel's validated stage derivative, brackets a crossing with [`event_bracket.gd`](../../../../app/physics/event_bracket.gd) (secant with forced bisection) to 1e-12 of local tick time, applies the transition, and continues the remainder of the tick; a trial that dips below zero without a negative endpoint is halved. Negative trial values are a continuation used only to locate the crossing; accepted states never cross. This is the EL1d rotor-stop algorithm moved verbatim; [`electric_stop.gd`](../../../../app/physics/electric_stop.gd) is now its compatibility wrapper for the battery composition and the EL tests.
- **Record.** Every tick policy may return `{state, events}`; the kernel ([`simulation.gd`](../../../../app/sim/simulation.gd)) validates each event (a type and a time inside the tick window plus rounding slack), copies them into `last_events`, and emits `events_located(tick, events)` before `stepped`. A malformed event record faults the tick, which rolls back like any other rejection. The record is diagnostic: it is not part of the checkpoint and is cleared by reset and restore.

## Change

| File | Change |
| --- | --- |
| [`app/physics/event_step.gd`](../../../../app/physics/event_step.gd) (new) | The locator, with `TIME_TOL` 1e-12 s and `VALUE_TOL` 1e-7 as before. |
| [`app/physics/electric_stop.gd`](../../../../app/physics/electric_stop.gd) | Wrapper over the locator with the EL1d contract (event times as a float64 array) and its constants. |
| [`app/sim/vehicle_model.gd`](../../../../app/sim/vehicle_model.gd) | `events` declaration and its validation; `step_policy` may return `{state, events}`. |
| [`app/sim/simulation.gd`](../../../../app/sim/simulation.gd) | Runs the locator for a declared event when no policy is set; unpacks and validates policy results; `last_events`, `events_located`; configuration refuses an index outside the continuous block. |
| [`app/sim/aircraft_propulsion_runtime.gd`](../../../../app/sim/aircraft_propulsion_runtime.gd), [`app/sim/flight_session.gd`](../../../../app/sim/flight_session.gd) | The fixed-bus electric route declares its rotor stop and owns no policy; the finite-battery route keeps its composed policy and now reports its typed events; the session installs declared events with the callbacks. |
| [`app/physics/rotorcraft/simulation_step_adapter.gd`](../../../../app/physics/rotorcraft/simulation_step_adapter.gd) | Returns `{state, events}` with each located rotor stop and its bracket width; failures stay empty arrays. |
| [`app/physics/glow/flight.gd`](../../../../app/physics/glow/flight.gd) | Returns `{state, events}`: the bounded rotor-stop and tank boundaries (`fuel_exhausted`) and a `glow_stopped` transition with its reason when a running engine stops inside the tick. |
| [`app/tests/test_sf_event_protocol.gd`](../../../../app/tests/test_sf_event_protocol.gd) (new) | 38 checks: analytic crossing located within 1e-12 and the transition applied, record and signal semantics, replay determinism, contract rejections, malformed policy results faulting with rollback, the rotorcraft adapter's record, the fixed-bus route locating a rotor stop at rest, the battery route reporting one, and a glow tank running dry as `fuel_exhausted` plus `glow_stopped`. |
| [`app/tests/test_heli_startup_kernel.gd`](../../../../app/tests/test_heli_startup_kernel.gd) | Reads the adapter's `state`; no assertion changed. |
| [`app/tests/fingerprint_vehicles.gd`](../../../../app/tests/fingerprint_vehicles.gd) | Source-cut and rotor-hold variants, `--extra-data` for non-catalog fixtures, and a per-run count of located events. |

## Proof

| Check | Result | Record |
| --- | --- | --- |
| Fleet fingerprints, HEAD copy versus this tree | **24/24 identical** state bytes, tick counts and fault text | [comparison](results/fingerprint-comparison.txt), [HEAD](results/fingerprints-head.json), [SF-04](results/fingerprints-sf04.json) |
| Protocol test | 38 checks, 0 failed | [log](results/protocol-test.log) |
| Event, kernel, electric, glow, helicopter, replay and session suites on this tree | See the batch log; all pass | [log](results/focused-tests.log) |
| Full test loop on a copy of this tree versus the HEAD copy | See the full-suite section below | [SF-04 table](results/suite-sf04-results.txt), [HEAD table](../SF-01/results/suite-head-results.txt) |

Observations from the fingerprint variants, none caused by this step: no fleet schedule reaches a located stop (a propeller with its source cut windmills in the airstream, the glow cut command edits state between ticks, and 900 ticks of rotor hold do not stop the helicopter's rotor), so the stops themselves are proven by the protocol test at rest and with a nearly empty tank. Cutting the Ventage Jet's source in flight through `engine_running = false` faults the continuous turbine stage identically on both trees; that route has its own shutdown path ([turbine plan](../../../plans/turbine-realism.md)).

## Limits

- The protocol unifies the declaration and the record, not every locator's numerics. The finite-battery composition, the glow lifecycle step and the rotorcraft explicit-midpoint predictor keep their own policies; moving them onto the kernel locator would change trajectories and needs refinement evidence per vehicle (plan step SF-04b with the `h`/`h/2` order proof).
- The kernel locates one declared boundary per model. Several boundaries compose inside a policy, as the battery route does.
- Hull crossing is a post-tick pose estimate for crash detection, not an integration event; it stays an observer.
- No physical validation is implied; the located times are numerical boundaries of the current laws.

Commit message: `SF-04: kernel event protocol; EL1d locator becomes physics/event_step.gd, models declare boundaries, policies report events; 24/24 fleet fingerprints byte-identical, 38-check protocol test`
