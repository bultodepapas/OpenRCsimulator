# NK-6d — the native kernel integrates the glow resource step

2026-11-26. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick cost](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).
Follows [NK-6c](../NK-6c/README.md) under the owner's
[native-core decision](../../../DECISIONS.md#native-acceleration-keeps-the-reference-as-its-specification).

## Why

After [NK-6b](../NK-6b/README.md), a glow tick still cost 540–620 µs of `Simulation.step` headless with the engine
running, the fleet's most expensive tick. Its step policy, `GlowFlight.step`, kept it in the GDScript reference
transaction. That covered:

- the RK stage lambdas and stage dictionaries;
- `resource_event_step.gd` evaluating each resource event's closures at every RK stage;
- the policy's accepted half.

The native glow lifecycle evaluates rates only. Its acceptance and opportunity counting exist only in GDScript.

## Change

- `glow/flight.gd` splits `step()` without changing it:
  - `_recording_events` builds the resource events whose committed transitions append to the ledger.
  - `finish` is the accepted half: lifecycle acceptance, counters, fuel stops and published events.

  `step()` is `_recording_events`, then `ResourceStep.advance`, then `finish`.
- `nk_tick.hpp` ports `resource_event_step.gd` operation by operation:
  - `advance`, `_trial`, `_locate`, `_crossed`, `_crossed_extrema`, `_crossed_before`, `_event_before`;
  - the evaluation budget;
  - the stock glow surfaces (rotor speed, main-tank fuel above the reserve, feed-line liquid) and their `enabled`
    source modes.
- `nk_kernel.cpp` `integrate_tick` admits `GlowFlight.step`:
  - It first reads the session's `native_glow_step_plan`: the recording events, their ledger and the reserve.
  - It checks the events as `advance` checks their definitions, admitting only the stock surfaces; a pickup event
    keeps the reference.
  - It integrates natively and calls each event's recording transition, reporting the events with the reference's
    keys and the transition details.
  - It calls `GlowFlight.finish` and unpacks its result as `Simulation._unpack_policy_result` does.
- `simulation.gd` lets through a step policy named `step`; the kernel decides.
- `flight_session.gd`: `native_glow_step_plan` and the `native_glow_step_enabled` hook; derived session classes keep
  the reference.

## Evidence

- `app/tests/test_native_tick_driver.gd` now covers the four glow aircraft with their engines started (`glow_start`):
  1,549 checks, none failed.
  - Each aircraft's takeoff, landing, throttle cut and fuel exhaustion fly byte-identical every tick with and without
    the kernel, with equal stage counts:
    - the 61FX also in gusty, turbulent and spatial weather;
    - the fuel runs out through `fuel_exhausted`, `glow_stopped` and `glow_rotor_stopped`.
  - The single-tick injections, the spies and the hook off pass for every glow aircraft. Four substeps are refused
    with the policy's own reason.
- All nineteen installer gates are identical for binary
  `e58caebe7eb8979cdd9747cf400d4789910bb04545f180a8dc2188e0ebd8f5e9`, and the mutant build still fails. Accepted
  results (tool root, not in Git):
  - `stage-20261127T004156936321Z.json` `1c8d46fe7b7402faed15ff20832e5d730c183d0c2e8f4229091521cceaf4e62c`
  - `stage_mutant-20261127T004225594561Z.json` `b0b7b1f002682330edb7f75932d2639b06da5e6729a4d4b2f4a537dfd06cce27`
  - `trajectory-20261127T004254248641Z.json` `7eb58a71952b9ef535243661ee6e8ed0da8b3fac19e413b434743757ca9bdd7b`
  - `glow-stage-20261127T004525090839Z.json` `e52ccccd6574a3f4f50a174a624110ec3c14da4ab6b2ed506f3ac80ca0c14b76`
- With the native stage installed, 79 suites pass:
  - all native suites and all 39 glow, nitro and fuel suites;
  - golden flights, replay integrity and policy, the runway fleet, reset and restore publication;
  - weather and lake flights, crash cost, the ground-accident session, the Extra runway and handling;
  - trim throttle, `Simulation`, statistics, resource events, the SF event and contact-substep suites, and the
    electric battery and Stik 6S sessions.

  `test_weather_publication` still fails only on the publication fixture renewal pending since NK-5d.

## Gain

Headless, engines running, alternating blocks of the same flight (`Simulation._physics_process`). NK-6b is the
reference transaction with its native endpoint sample:

| Aircraft | NK-6b | NK-6d |
| --- | ---: | ---: |
| Stik glow 61FX, airborne | 541 µs | 394 µs |
| Stik glow 61FX, from the runway | 615 µs | 486 µs |
| Stik glow FS64V, airborne | 550 µs | 393 µs |
| Stik glow FS64V, on the runway after its engine stopped (60-tick blocks) | 284 µs | 219 µs |
| Extra 300S, rolling | 625 µs | 588 µs |

The 480-tick blocks were biased for the FS64V runway case, whose engine stopped part way through, so it was repeated
with 60-tick blocks. With NK-6b, a glow tick has fallen from 900–1,080 µs to 390–490 µs.

## Finding: a stopped glow rotor can fault the flight

The fuel-exhaustion flights found a fault in the reference policy, which the kernel reproduces bit for bit:
`stik-glow-55ax-2t` runs out of fuel on the runway at full throttle. About 9 s later, with the propeller winding
down below 1 rpm, the step refuses the tick ("integrated state is nonfinite, malformed, or has a degenerate
quaternion") and the flight stops. `ResourceStep._locate` cannot bound the `rotor_stop` root ("event failed time and
surface residual bounds"). The likely cause, not yet confirmed, is that its residual tolerance (`SURFACE_TOL`, 1e-10
rpm) is finer than a time bracket of `TIME_TOL` (1e-12 s) can resolve once the rotor decelerates faster than about
100 rpm/s.

The fix belongs to the glow event law, not to this step. One option is an explicit `surface_tolerance` on the
rotor-stop event, which the definition schema already allows. It needs its own trajectory and golden review.

## Limits

- Windows only was built and installed locally; CI's three native-kernel jobs requalify each platform on push.
- A glow installation with a pickup position keeps the reference policy; no stock aircraft has one.
- `GlowFlight.finish`, the event transitions and the HUD's `glow_state()` remain GDScript.
