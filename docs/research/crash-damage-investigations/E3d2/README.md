# E3d2 — Prop strike

2026-10-13 · **Status:** implemented for interactive flights. The 300 rpm threshold is an estimate. **Serves:** [crash realism plan](../../../plans/crash-realism.md), [research 04 §6](../../roadmap-investigations/04-ground-handling-collisions.md#6-contact-geometry-crash-versus-scrape-damage) step E3d2. Builds on [E3d1 soft contacts](../E3d1/README.md).

## Behaviour

A turning propeller (≥ 300 rpm) whose disc reaches the field breaks. The engine stops (dead stick) and the flight goes on: a landing nose-over rolls or tips over physically instead of ending the flight with the propeller spinning inside the ground.

- **Presentation:** the blades disappear, 12 blade fragments fly along the slide with a surface puff, a crack sounds and the engine cuts. If the flight later crashes, the wreck keeps the propeller broken (hidden, never thrown again), and the cause line adds "after a prop strike".
- **Scope:** scripted, capture and trace routes are unchanged (soft contacts off).

## How

[hull_contact.gd](../../../../app/physics/hull_contact.gd):
- **`prop_disc()`** builds the disc from the same hub and axis the thrust uses (`propulsion.offset`/`axis`) and half the propeller `diameter`. It returns nothing for turbines.
- **`prop_disc_depth()`** projects the ground-down direction onto the disc plane to find the lowest blade tip. An axis pointing straight down leaves the whole rim at hub depth.

This works for every propeller aircraft from its data, independent of sparse hull points: the Stik has only a spinner point, yet its blade tips touch first.

[flight_session.gd](../../../../app/sim/flight_session.gd) `_check_prop_strike()` runs after the crash checks, only on a tick that continues the flight, so a crash still freezes an untouched checkpoint. It stops the engine through `engine_running` (a simulation mode, part of the checkpoint) and records `prop_strike`. The contact law string includes the threshold.

## Evidence

- [test_prop_strike.gd](../../../../app/tests/test_prop_strike.gd): **16 checks**.
  - Disc geometry, level and nose-down; no disc for a turbine.
  - Every runway-qualified aircraft clears the runway at rest (Stik 7.5 cm, Timber 13.7 cm) and does not strike on a 2 s full-throttle takeoff run.
  - A full-power Stik nose-over at 4 m/s strikes at 9,255 rpm. The engine stops (rpm 0), with no crash, and the result is deterministic.
  - The legacy route never strikes.
- [test_prop_strike_feedback.gd](../../../../app/tests/test_prop_strike_feedback.gd): **12 checks** in the production scene.
  - The blades hide, fragments fly, the flight continues and no aftermath starts. The particle budget stays at 700.
  - A later crash records `prop_broken` and the cause factor, keeps the propeller hidden on the wreck, and conserves mass (2.8851 kg).
  - Restart restores everything.
- [Mutations](../../../../research/crash-damage/e3d2/mutations.log): **8/8 killed**. "Strike checked before the crash" is caught by the existing `test_crash_integration` checkpoint check, which first exposed the ordering fault.
- **Unchanged:** soft contacts, crash, snapshot, integration (95), effects, energy, audio, wreck, breakup, sections, cause, ladder, Timber ground, landing manoeuvre, ground contact, start choice and runway UI suites, and `test_trace_acceptance.py`.

## Limits

- The Extra and the P-51 are not yet runway-qualified, so their takeoff clearance is not exercised.
- An electric motor whose blades broke would keep spinning; the strike stops it. Thrust is zero either way.
- No impulse from the blades hitting the ground is applied.
- Restarting the engine in flight is not modelled (ROADMAP G2).
