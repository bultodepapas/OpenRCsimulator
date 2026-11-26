# NK-6c — the native kernel integrates the finite-pack step policy

2026-11-26. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick cost](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).
Follows [NK-6a](../NK-6a/README.md) and [NK-6b](../NK-6b/README.md) under the owner's
[native-core decision](../../../DECISIONS.md#native-acceleration-keeps-the-reference-as-its-specification).

## Why

The catalog flies every electric with a finite pack by default: `stik-electric-6s`, `turbo-lumber-evolution` and
`moonrunner-x99`. That mode installs the step policy `FlightSession._electric_step`, so NK-6a left these ticks to
the GDScript reference: the Simulation plumbing, the RK stage lambdas and the policy's integrator.

A headless pack tick cost 280–420 µs of `Simulation.step`. The native stage took 13–56 µs of it. The policy itself
took 106 µs in flight and 277 µs on the runway, where contact refinement splits the tick.

## Change

- `nk_tick.hpp` ports these operation by operation, on NK-6a's event locator and RK4:
  - `electric_battery_step.gd`: `advance`, `_stop_trial` with its derivative tracker and checked rotor projection,
    `_locate_battery_crossing`, `_finish_exhausted`, `_append_rotor_events` and `_append_battery_event`;
  - `electric_stop.gd`;
  - `electric_contact_step.gd`: `advance` and `_append_ordered`.

  The events keep the policy's order, shared times and payloads (`charge_residual_c`, `time_error_bound_s`). A tracker
  failure continues the integration as the reference does. Failure messages are not ported: every policy failure
  returns `[NAN]`, which the step refuses as an invalid integrated state.
- `nk_kernel.cpp` `integrate_tick` admits a step policy only when it is the session's `_electric_step`:
  - It first asks the session's pure plan, `native_electric_step_plan`, and refuses before any evaluation without it.
  - After the tick's first stage, rotor momentum and substeps it refuses more than one substep with the reference's
    reason.
  - It runs the battery step, or the contact pieces, or a fixed source's rotor-stop event step.
  - It calls back `_project_electric_stop` and, for a pack, `_supervise_pack`, where the policy calls them.
  - It validates the policy's events like `_unpack_policy_result`.

  The literal table adds `FLOAT64_EPSILON`.
- `simulation.gd`: `_native_integrator` lets through a step policy named `_electric_step`; the kernel decides.
- `flight_session.gd`: `native_electric_step_plan(combined, dt)` returns `[dynamic, contact pieces, combined rotor
  index, pack supervision]`, evaluated as `_electric_step` evaluates them. It is empty with the hook
  `native_electric_step_enabled` off or for a derived session class.

## Evidence

- `app/tests/test_native_tick_driver.gd` now covers the three packs (`id@pack`): 1,176 checks, none failed.
  - Each pack's takeoff, landing, throttle cut, slowing rotor and battery exhaustion fly byte-identical every tick
    with and without the kernel, with equal stage counts. Both `rotor_stop` and `battery_exhausted` are located.
    The Stik's runway flights run contact pieces, 2,912–9,616 extra stage evaluations per flight. Locating the
    battery exhaustion adds 2,194–2,311 evaluations on the Turbo Lumber and the Moonrunner.
  - Single-tick injections on the bare `Simulation` end exactly like the reference:
    - malformed rotor momentum, substep counts and post-step filters;
    - malformed auxiliary projections, an overflowing state and a subnormal mass;
    - four substeps, which the policy refuses with its own reason.

    The callback spies match.
  - The hook off keeps every pack tick in the reference.
- All nineteen installer gates are identical for binary
  `6b42f1f059e1847627105f2479b53104b6337d4dd05900da5fa5b6e96ee6bdfe`, and the mutant build still fails. Each gate
  checks the new literal. Accepted results (tool root, not in Git):
  - `stage-20261126T224917059825Z.json` `e978a7fb58bb5f52f83bf04d63f98e516b4d7bbce07f5b5a709276a326c4f1d6`
  - `stage_mutant-20261126T224948373874Z.json` `1983e335125d25afc68fa6dd90abfb483b9a86ca008051933517195b59ccfa2b`
  - `trajectory-20261126T225019119407Z.json` `7dcd05158f761f8f91f3a3645a8c3c2d5e4e2baa4ca12587a8a0146202f9098b`
  - `electric-stage-20261126T225214747532Z.json` `5d896346af6b0b58caf32878f8fdad7e08dcace5baa0b73b9218dcf1911872b6`
- With the native stage installed, 77 suites pass:
  - all native suites;
  - every electric, battery, ESC, pack and shaft suite except the fixture-bound one below. They include the battery
    step, the contact step, electric stop, event localization, the Stik 6S low-SOC session and the package probes;
  - golden flights, replay integrity and policy, the runway fleet, reset and restore publication;
  - weather and lake flights, crash cost, the ground-accident session, statistics context and failure events;
  - the integrator, `Simulation`, resource events, the SF event and contact-substep suites, glow flight physics and
    servo-interval flight.

  `test_weather_publication` and `test_shaft_publication` fail only on the shared publication fixture
  (`publication_fixture_bridge.json`), whose source pins await the hosted renewal pending since NK-5d.

## Gain

Headless, alternating 480-tick blocks of the same flight (`Simulation._physics_process`):

| Pack aircraft | Reference | NK-6c |
| --- | ---: | ---: |
| Stik electric 6S, airborne | 297 µs | 168 µs |
| Stik electric 6S, from the runway | 409 µs | 222 µs |
| Turbo Lumber, airborne | 282 µs | 175 µs |
| Turbo Lumber, from the runway | 424 µs | 217 µs |
| Moonrunner X99, airborne | 288 µs | 163 µs |

The kernel removes 107–208 µs from each pack tick (36–49%).

## Limits

- Windows only was built and installed locally; CI's three native-kernel jobs requalify each platform on push.
- The glow step policy (`GlowFlight.step`, resource events and lifecycle) stays in the reference transaction beyond
  NK-6b's endpoint sample.
