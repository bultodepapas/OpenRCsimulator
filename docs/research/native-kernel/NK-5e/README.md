# NK-5e — native wheel compressions for the accepted-tick contact observer

2026-11-25. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick cost](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).
Follows [NK-5d](../NK-5d/README.md).

## Why

The session's first `stepped` handler observes every accepted endpoint for the crash-cost support events
(`_observe_contact_tick`, active in the app). A headless split of a flying Corsair put it at 56–81 µs per tick, of
which `gear_compressions(sim.state)` took 38–58 µs and `current_landing_gear()` 9–11 µs. The same terrain and lake
arithmetic already runs natively for the wheel loads (`nk::wheels_compressions`, compared by the component oracle).

## Change

- `nk_kernel.cpp` binds `stage_compressions(s, aux)`. It evaluates `nk::wheels_compressions` over the prepared stage
  ground: `stage_.ground`, or for retractable gear the `tick_.posed_ground` that `set_tick_context` posed from the
  tick's aux. It answers empty, so the session evaluates the reference, unless:
  - the stage and its tick context are ready and the layout has wheels;
  - the state passes `Simulation.state_is_valid` (13 finite values, quaternion norm² > 1e-24);
  - for retractable gear, the endpoint aux has the same size as the context's aux and its extension and deployed flag
    carry the same bits as the values the context validated;
  - the gear is not empty, the surface table is non-empty and valid and the lake is valid, so the reference takes the
    same terrain branch. Without a table, lake or track the reference uses a flat-ground formula that can return
    `-0.0` where the terrain branch returns `+0.0`, so the native stage refuses an empty table.
- `native_stage.gd` exposes it as `endpoint_compressions(s, aux)` for installed fixed-wing families.
- `flight_session.gd`:
  - `_kernel_pre_step` records `_native_endpoint_tick = sim.tick + 1` once the configuration guard and
    `tick_context` accepted the tick. Every tick-fact drop (pre-step start, fault, pause, aircraft commit) clears it.
  - `_on_sim_stepped` reads it before its own fact drop and admits the native answer only while it observes that
    tick's endpoint. A restore or reset that publishes `stepped` without a guarded pre-step is never admitted.
  - `_endpoint_compressions()` uses the native answer only when admitted, with no RC-track overlay; any refusal
    evaluates `gear_compressions(sim.state)`. `native_endpoint_answers` counts native answers for diagnostics.
  - The support-event loop reads `current_landing_gear()` and calls `ContactEvents.support_event` only when some
    contact is compressed now or was on the previous tick; otherwise every call returns `{}`.

## Why the answer is exact

- The configuration guard accepted the session's aircraft, gear, surfaces and lake at this tick's pre-step, and the
  stage ground was prepared from them (`stage_config.gd`). Nothing between that pre-step and the session's own
  `stepped` handler, which runs before external observers, can change them.
- The reference poses retractable gear with `RetractableGear.pose(original, extension)` from `sim.aux`. The native
  stage posed the same contacts from the context aux, and the native wheel loads that use that pose already match
  the reference in the stage oracle. The answer is used only when the endpoint aux carries the same bits.
- With valid surfaces and lake, `Ground.compressions` delegates to `Wheels.compressions`, whose per-contact rotation,
  `Terrain.sample_validated` and slope division `nk::wheels_compressions` reproduces.

## Evidence

- `app/tests/test_native_endpoint_compressions.gd` (110/110), Corsair, P-51 and Stik:
  - Direct: 3,000 random endpoints each over the runway, grass and lake, from 3 m up to 0.6 m into the ground, with
    random gear extensions and flags. Every one was answered natively and was byte-identical to the reference
    (699–797 compressed samples per aircraft).
  - Refusals: a non-finite state, a zero attitude, a short state, an extension one ulp off, a different flag, a
    short aux, a `-0.0` extension where the context holds `+0.0` (GDScript folds a literal `-0.0` to `+0.0`; the test
    negates a variable) and a stage prepared without a surface table. A guarded pre-step admits exactly the next
    endpoint; a fact drop withdraws it.
  - Equivalence: paired sessions with and without the native answer recorded byte-identical state, continuous
    state, aux, support history, contact events and located events on every tick of a 1,440-tick runway roll, a
    2,100-tick gear retraction and extension, a hard landing and a lake ditching. The native session took the native
    answer on every accepted tick (12,241 ticks in all); the reference session never did.
- All nineteen installer gates are identical for binary `e7fb24c3b160d7975204c660e72d2952ddc4395d7c4c35d09c3ee9dc3a672cfc`, and the mutant build still fails.
  Accepted results (tool root, not in Git): `stage-20261126T024639590776Z.json`
  `1ee18da209db7308565f8b246ce7b48a0e2df21d58bfca27aba0e95ca3fdc17e`, `stage_mutant-20261126T024708381007Z.json`
  `f870b56f75838fa6e8e5a54a86f8790b35e5d0c92208e13ca88fd461296dd154`, `trajectory-20261126T024737947052Z.json`
  `85ac674e1c3f1cee2ca04b92b1770426b332d5f0f0eb1bafaf487209d56e89a2`, `liquid-stage-20261126T024950791080Z.json`
  `fb5a7030e558f1fd84d5fabac8d38728872d93f0a879523b4b9e89833d6f9428`.
- With the native stage installed, these suites pass: crash-cost coverage, fleet and producers; electric, Extra,
  fleet and Lumber runways; statistics terrain; ground contact and gear clearance; lake session; P-51 and
  retractable-gear ground, input and trace; Stik electric ground; trim throttle; the native suites (contact reach,
  fallback, guard leaves, replay, session, stage, substep preview, wake admission); golden flights and replay
  integrity.
- An independent review found no exactness defect. Its follow-ups are included: the empty-table refusal above, and
  confirming that every step rejected after the pre-step reaches `_fail_safe`, whose `faulted` drops the token.

## Gain

Headless app (debug bridge), paused accepted endpoint, five alternating rounds of 40 calls; minimum–median per call:

| Contact observer per tick | Off (µs) | On (µs) |
| --- | ---: | ---: |
| Corsair, 39 m | 39.6–47.1 | 3.6–3.7 |
| Corsair, rolling | 103.1–106.5 | 66.1–70.2 |
| P-51, 43 m | 46.8–68.3 | 4.5–6.5 |
| P-51, rolling | 101.4–104.0 | 60.5–63.5 |
| Stik, 36 m | 31.7–32.3 | 3.7 |
| Stik, rolling | 110.0–123.6 | 70.4–70.9 |

The compressions alone fall from 28–61 µs to 1.7–2.9 µs. On the ground the remainder is the soft-hull contact sample
and the support events themselves.

## Limits

- Windows only was built and installed locally; CI's three native-kernel jobs requalify each platform on push.
- The reference backend, an RC-track overlay, a tick that located kernel events (its `events_located` drops the tick
  facts first) and any refusal evaluate the reference.
- A retracted pose built from a `-0.0` extension could differ from the reference's cached `+0.0` pose only in the sign
  of zero. The session's initial gear aux and `RetractableGear.advance` never produce `-0.0`.
