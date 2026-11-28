# NK-5g — native pre-step

2026-11-26. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick cost](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).
Follows [NK-5f](../NK-5f/README.md).

## Why

Every tick starts with the session's `_pre_step`, which builds the next aux: servos, wheel anchors, the tail's
downwash lag, the gear and flap actuators, the throttle lag and the turbulence draw. Timed headless under real tick
conditions (tick facts armed, native wing wake admitted) across the fixed-wing fleet:

| `_pre_step` per tick | In flight | Rolling |
| --- | ---: | ---: |
| Total | 26–48 µs | 100–128 µs |
| `Ground.anchor_step` | 6–8 µs | 70–91 µs |
| `_gear_weight_on_wheels` (retractable gear) | 1–2 µs | 26–32 µs |
| `air_data` for the downwash lag | 5–8 µs | 5–8 µs |

About half of the flying cost was GDScript glue between those calls.

## Change

- `nk_pre_step.hpp` (`nk::pre_step`) returns `_pre_step`'s next aux and `sim.modes[1]`. It mirrors each piece in
  operation order:
  - the input and aux checks;
  - `Flaps.advance` and the manual elevator mix (`move_toward` and `sign` as Godot defines them);
  - the RPM: the coupled-shaft or continuous-turbine passthrough, the engine-off zero, and `Propulsion.rpm_step`;
  - `ControlActuators.rate_limit`;
  - `ground_wheels.gd anchor_step`, over the stage's oracle-verified `wheel_frame` and `wheel_coefficients` and the
    retractable pose of the incoming extension;
  - the downwash lag, from the stage's own air at `sim.time()` with the incoming aux (datum, gusty, turbulent or
    spatial weather), `stage_ground_up` and the NK-5a wing wake;
  - `_gear_weight_on_wheels` on the authored gear, then `RetractableGear.advance`;
  - `WindTurbulence.step` with its active-normal pairs and open uniforms.
- Engine math stays the engine's own. `exp`, `log`, `sin` and `cos` call the engine's utility functions, the same
  functions GDScript calls. The engine `RandomNumberGenerator` is not in the library's godot-cpp build profile, so
  Godot's `RandomPCG` is reproduced in integers. `seed` then `state` leaves only the raw state and the default stream
  increment, which `pre_step_rng_probe` exposes for testing. Constants whose GDScript spelling the engine might
  parse differently from C++ are not compiled in. The weight-on-wheels threshold `1.0e-5`, `UINT53_DENOMINATOR` and
  `MAX_OPEN_UNIFORM` arrive in the preparation config as the engine parsed them on the running platform.
- Any reference `[NAN]` result, a running turbine spool or shaft-step engine, the legacy wheel-less anchor path, a
  spatial refusal, a NaN wing wake or a non-finite output refuses. The session then evaluates the reference.
- `nk_kernel.cpp` binds `prepare_pre_step(config)`, `pre_step(...)`, `pre_step_rng_state()`, `pre_step_stats()` and
  `pre_step_rng_probe(state, count)`. Preparing a new stage clears the prepared pre-step. `nk_stage.hpp`'s wind callback context takes an optional aux, so a pre-step air sample reads
  the incoming aux as `air_data` does.
- `stage_config.gd` adds `pre_step_config_for(session)`. It holds the fixed inputs: servo rate, RPM branch flags and
  lag, flap times and mix, layout indices, lake presence, downwash length and turbulence parameters. The aircraft,
  shaft integrator, lake and weather it reads are all guarded per tick. `native_stage.gd` prepares it at
  installation and wraps `pre_step(session, aux, inputs, dt)`. That wrapper passes `_deflections(aux)`, the committed
  state, wheel speeds, time, engine state, flap-mix owner and `sim.modes[1]`, and after a turbulent answer it writes
  `sim.modes[1]` as `_pre_step` does.
- `flight_session.gd` `_kernel_pre_step` asks the native pre-step only after the configuration guard passed, with no
  active failures, no pending weather or shaft reset and no RC-track overlay. An empty answer runs `_pre_step`.
  `native_pre_step_enabled` is the test hook; `native_pre_step_answers` counts answers.

## A parser finding

A first build compiled the turbulence bound in as a C++ literal. The installer gates' literal oracle compiles every
spelling the native code assumes, and it failed one entry: the pinned x86 GDScript parser reads
`WindTurbulence.MAX_OPEN_UNIFORM`, spelled `0.9999999999999999`, as exactly `1.0`, while C++ reads the double just
below it. The native pre-step now takes that bound and its sibling constants from the engine-parsed GDScript values
(see Change), so the result is exact on any platform's parser. The reference's "open" uniform can therefore reach
1.0 (when the 53-bit midpoint rounds up), where `log(1.0) = 0`. That is harmless, but the clamp does not do what
its comment says.

## Evidence

- `app/tests/test_native_pre_step.gd` (194/194), the eleven fixed-wing stock aircraft with a native stage:
  - RNG: 400 raw states, negative ones included, with a random seed each. The port's 24 draws and the state read
    back equal the engine `RandomNumberGenerator`'s.
  - Direct: 1,200 random committed endpoints per aircraft in each of calm, gusty, turbulent and spatial weather
    (52,800 in all), over the runway, grass and lake, airborne and with the wheels on the ground. The samples vary
    the aux, inputs, gear and flap poses, anchors (sliding, stuck on the wheel point, stuck off it), rim speeds on and
    off the stick band, engine state, flap-mix owner, time and turbulence RNG state, plus a few invalid inputs.
    Every native answer, and `sim.modes[1]` after it, is byte-identical to the pure GDScript `_pre_step` (reference
    wing wake). The native pre-step refused exactly the samples where the reference returns an invalid aux: invalid
    inputs, and spatial-flow refusals away from the field. Anchors held and stuck, the gear interlock engaged and every
    turbulent sample advanced the RNG.
  - Flights: paired sessions with and without the native pre-step recorded byte-identical tick, state, continuous
    state, aux, modes, faults, crashes and contact events through a takeoff with flap and gear cycles, a hard
    landing and an engine-off glide with a gear and flap cycle for each aircraft. Gusty, turbulent and spatial
    takeoffs ran for the Corsair, the Stik and the Avanti. The native session answered every guarded pre-step.
  - Routing: with failures armed, every pre-step stays on the reference.
- All nineteen installer gates are identical for binary
  `4b495b09937ccb537ef5b7ed71561021953199727b20037bbb991bbbf3468666`, and the mutant build still fails. Accepted
  results (tool root, not in Git): `stage-20261126T133908830471Z.json`
  `282314234c8361f79076e465da525be4fcde6f3d786f75f0714611420af521b1`, `stage_mutant-20261126T133942502998Z.json`
  `9485bf02ffc5ec4768c1f8f925639149e0c10877300e2bcbeff360d74800b428`, `trajectory-20261126T134019444472Z.json`
  `1c17a2f27c23a8b42d195b924dc0bd3ea4fae0330a9b49721133bf8a74dad301`, `liquid-stage-20261126T134309839879Z.json`
  `462ccb48c75e2abe9a6221dc673b1305b23d1398f2e970d2204fb807b7513cba`.
- With the native stage installed, 58 suites pass. They cover:
  - the native suites, golden flights and replay integrity;
  - the runway fleet, the retractable-gear and P-51 retract suites, and the flap suites (session, P-51, mix
    ownership, offset, aero, controller mix profile);
  - downwash lag, air reuse and tail downwash;
  - turbulence, wind, atmosphere and spatial-weather flights, observer wind and out-of-trim;
  - trim, servo and servo-interval;
  - the electric, Extra, Lumber and Stik electric grounds, ground contact and lake session;
  - crash cost, statistics, reset and restore publication, ground accidents and intended hull support;
  - spatial gear drag and powered stage, and engine smoke.
  `test_weather_publication.gd` alone fails, on its source-pinned publication fixture, which needs the hosted renewal
  that every `flight_session.gd` change in this series requires before push.
- An independent review compared each mirrored law line by line and found no defect. Its notes are included: a
  corrected header comment, the turbulence bound check at seven entries, and the engine-parsed constants (an Apple
  parser could read a spelling differently from x86).

## Gain

Headless app (debug bridge), paused accepted endpoint, five alternating rounds of 40 calls; minimum–median per call:

| Per tick | Reference | Native |
| --- | ---: | ---: |
| `_pre_step`, in flight (Corsair, P-51, Stik, Avanti) | 62–74 µs | 4–7 µs |
| `_pre_step`, rolling | 135–232 µs | 8–12 µs |
| guarded `_kernel_pre_step`, in flight | 134–174 µs | 71–102 µs |
| guarded `_kernel_pre_step`, rolling | 215–350 µs | 55–135 µs |

Whole real ticks (session input, kernel step and the session's observers), alternating eight blocks of 120 ticks
with the native pre-step on and off in one headless flight:

| Whole tick | Reference | Native pre-step |
| --- | ---: | ---: |
| Corsair, in flight / rolling | 551 / 1,096 µs | 505 / 892 µs |
| P-51 | 529 / 889 µs | 506 / 717 µs |
| Stik 60 | 504 / 844 µs | 447 / 647 µs |
| Avanti | 453 / 822 µs | 371 / 715 µs |

What remains of the guarded pre-step is mostly the configuration guard (35–70 µs) and the tick context.

## Limits

- Windows only was built and installed locally; CI's three native-kernel jobs requalify each platform on push.
- Not native, and evaluated by the reference: active failures, a running turbine spool or shaft-step engine (no
  stock aircraft uses one), the legacy anchor path without wheels or a lake, an RC-track overlay (the stage itself
  refuses that terrain), pending weather or shaft resets, and any refusal.
