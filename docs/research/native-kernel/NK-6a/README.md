# NK-6a — the native kernel integrates the tick

2026-11-26. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick cost](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).
Follows [NK-5i](../NK-5i/README.md). Owner decision: [a native core](../../../DECISIONS.md#native-acceleration-keeps-the-reference-as-its-specification).

## Why

After NK-5a–5i, a headless flying tick of the Corsair cost about 495 µs: the session's input about 55 µs and
`Simulation.step` about 440 µs. Inside the step, the native stage itself took about 40 µs for its four evaluations.
Most of the rest was GDScript plumbing around the native calls:

- the RK stage lambdas;
- a Variant dictionary per stage evaluation;
- stage-validity checks;
- the rigid-body derivative where the stage does not publish one;
- RK4 combinations;
- the event locator's trials.

The owner chose to move the tick itself into the native core rather than shave that GDScript.

## Change

- `nk_tick.hpp` ports, operation by operation:
  - `rigid_body.gd` `derivative`;
  - `integrator.gd` `rk4_step_at`;
  - Simulation's `_rk4_substeps` and `_locate_substeps`;
  - `event_step.gd` `advance`, `_trial` and `_locate_crossing`;
  - `event_bracket.gd` `propose`.
- `nk_kernel.cpp` `integrate_tick(model, state, continuous, aux, t, dt, tick, mass, gravity, inertia, inertia_inv)`
  runs Simulation's legacy joint tick from its first stage to the accepted endpoint. It calls the prepared stage
  directly (`tick_stage`, with `stage`'s counters, timing and rejection diagnostics) and checks each stage as
  `_joint_stage_is_valid` and `_stage_state_is_valid` do.
  - The model's GDScript callbacks are called where the reference calls them:
    - rotor momentum, then substeps (the joint form receives the tick's stage dictionary);
    - the declared event's transition;
    - the post-step filter, then the auxiliary projection.
  - Every refusal carries the reference's reason.
  - `{}` refuses before any evaluation: the helicopter stage, an unprepared stage or context, or another continuous
    layout.
  - `tick_stats()` counts calls, answers and faults.
  - The literal table adds `1e-9` and `1e-7`.
- `simulation.gd`:
  - `_native_integrator()` qualifies a tick only under all of these conditions:
    - the legacy protocol, with no interval and no endpoint owner;
    - no step policy and a continuous block;
    - the stage is exactly the kernel's own unbound `stage`.
  - After the legacy pre-step installs `aux`, the step asks that kernel. A fault restores `old_aux` and fails safe, as
    the reference does; an answer goes to `_commit_step`.
  - The reference's own commit now goes through `_commit_step` too.
  - `native_tick_enabled` is the test hook.
  - Reference fix found by the callback spies: `derive` read a stage's `body_derivative` into a local and appended the
    continuous derivative to it. Packed arrays are shared, so `substeps_joint` received the tick's stage dictionary with
    a 13+n `body_derivative`, against `vehicle_model.gd`'s read-only `current_joint`. `derive` now copies it. No
    callback reads that key; states, loads and events are unchanged.

Step-policy families (finite glow, finite-battery electric) and the helicopter keep the reference transaction
until their NK-6 steps.

## Evidence

- `app/tests/test_native_tick_driver.gd`: 890 checks, none failed.
  - Seven native fixed-wing aircraft fly in pairs, one through the kernel and one through the reference:
    `jensen-das-ugly-stik-60`, `stik-electric-6s`, `p51d-mustang-120`, `f4u-corsair-250`,
    `sebart-avanti-s-a200-p100rx`, `turbo-lumber-evolution` and `moonrunner-x99`.
  - After every tick, the following are byte-identical, with equal stage-evaluation counts:
    - tick, state, previous state, continuous state, aux, modes and loads;
    - located events, fault, pause, inputs and crash record.
  - The flights are takeoffs, landings, throttle cuts, retractable-gear cycles, fuel exhaustion and a slowing rotor.
    Both of the last two locate their event. The Corsair, Turbo Lumber and Stik also fly gusty, turbulent and spatial
    weather.
  - Single ticks of a bare `Simulation` are restored from a native session checkpoint. They borrow that session's
    guarded pre-step and replace one callback or value each. Every reference refusal in the integrated span occurs,
    with its reason, restored state and fault count:
    - malformed rotor momentum, substep counts and post-step filters;
    - malformed auxiliary projections and event transitions, and an empty event type;
    - an overflowing state and a subnormal mass.
  - Spies record every callback's order, arguments and result; the two paths match.
  - Step-policy aircraft (`stik-glow-*`, `gp-extra-300s-60`) never reach the kernel. The hook off and a reference
    stage leave no integrator.
- All nineteen installer gates are identical for binary
  `90b25a13f927ffbe13b8c5c1c71de8b92d4eb5d06315a476f830b25958a11ad8`, and the mutant build still fails. Each gate
  compares two more values than at NK-5i: the literal oracle's `1e-9` and `1e-7`. Accepted results (tool root, not
  in Git):
  - `stage-20261126T214135242382Z.json` `194ad044fb922c4fc45fed67463a920cadbdbfa6b40e2aba3914e0a00862eddd`
  - `stage_mutant-20261126T214204289074Z.json` `ce614520167a3b70c0d28fc4a206cb209ba29969100f70c5d2d4198793dc34c3`
  - `trajectory-20261126T214233289386Z.json` `030da957397e0f0cfe9c99840daae5adff0cf9954f972883c91a7ed94542be90`
  - `liquid-stage-20261126T214447710390Z.json` `1aa8f0ce65ac29a58a3060cb24ea72c9c3de5f2c503c213e2006cb8acdbb9eb9`
- With the native stage installed, 59 suites pass:
  - all native suites, including this one;
  - golden flights, replay integrity and policy, the runway fleet and transaction;
  - reset and restore publication;
  - out-of-trim, turbulence, wind, atmosphere (flight and column session) and spatial-weather flights;
  - retractable gear (session and ground), flaps and lake;
  - crash cost (fleet), ground accidents (two suites), statistics context and failure events;
  - the electric and Extra runways, trim throttle, servo-interval flight and helicopter weather admission;
  - helicopter flight, the electric session, shaft and wheel coupling, and ground dynamics;
  - the integrator, rigid body, `Simulation`, resource events and the SF kernel suites (event protocol and
    refinement, contact substeps, framed, interval, local interval and vehicle model).

  `test_weather_publication` still fails only on the publication fixture renewal pending since NK-5d; it also binds
  `simulation.gd`.
- An independent review (Good Enemy) found no divergence on production paths. Its findings shaped three changes:
  - the callback spies;
  - the exact-Callable eligibility (a bound kernel `stage` keeps the reference);
  - the `derive` copy above.

## Gain

Live app, Windows, Forward+ (Vulkan), 1080p, muted debug session, airborne at 60% throttle. The kernel was switched on
and off in alternating 240-tick blocks of the same flight; both modes fly identical physics. The first 24 ticks of
each block are dropped. `Simulation.step` is `sim.step_usec` with its moving average inverted per tick: pre-step to
commit, without the `stepped` observers. The whole tick spans every physics callback.

| Aircraft | `Simulation.step` mean (p95), reference | NK-6a | Whole tick mean, reference | NK-6a |
| --- | ---: | ---: | ---: | ---: |
| Corsair (three runs) | 455–462 µs (724–738) | 338–356 µs (583–585) | 686–813 µs | 568–721 µs |
| Ugly Stik 60 | 303 µs (489) | 204 µs (362) | 643 µs | 544 µs |
| P-51D | 452 µs (740) | 349 µs (588) | 792 µs | 704 µs |

Headless, alternating 480-tick blocks over 5,040 ticks per case (`Simulation._physics_process`):

| Aircraft | Airborne, reference → NK-6a | Runway at idle, reference → NK-6a |
| --- | ---: | ---: |
| Corsair | 329 → 236 µs | 510 → 354 µs |
| Ugly Stik 60 | 234 → 135 µs | 307 → 218 µs |
| P-51D | 363 → 273 µs | 515 → 375 µs |
| Turbo Lumber (fixed bus) | 261 → 169 µs | 311 → 204 µs |
| Stik electric 6S | 282 → 171 µs | 445 → 238 µs |

The kernel removes 90–230 µs from every tick it integrates: 25–47% of `Simulation.step`. What remains in the step is
GDScript: the prologue checks, the session's pre-step with its configuration guard, and the post-step contact filter.
The rotor-momentum, substep and projection callbacks also remain. Those are the next NK-6 steps.

The application's Turbo Lumber flies its finite battery by default. Its `_electric_step` step policy keeps the
reference until the step-policy step; so do the finite-glow aircraft.

## Limits

- Windows only was built and installed locally; CI's three native-kernel jobs requalify each platform on push.
- After an RK stage error the reference finishes the tick on zero derivatives before refusing it. Its event locator
  could still call a declared transition on those values. The kernel stops at the error. The refusal, state and
  stage count are identical, and the declared transitions (`LiquidFlight.project_exhaustion`,
  `_project_electric_stop`) are pure.
- The kernel passes callbacks copy-on-write arrays. A callback that mutated its arguments in place would be seen by
  the reference but not by the kernel. `vehicle_model.gd` makes `block_aux` a pure projection and `substeps_joint`'s
  arguments read-only; the installed callbacks duplicate before writing.
- The pre-step, the session's input and the `stepped` observers remain GDScript (next NK-6 steps).
