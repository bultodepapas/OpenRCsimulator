# NK-6b — the glow step policy's endpoint sample from the native stage

2026-11-26. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick cost](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).
Follows [NK-6a](../NK-6a/README.md) under the owner's [native-core decision](../../../DECISIONS.md#native-acceleration-keeps-the-reference-as-its-specification).

## Why

The application flies half its fixed-wing fleet through a step policy, which NK-6a does not integrate:

- the four glow aircraft (`stik-glow-61fx-2t`, `stik-glow-55ax-2t`, `stik-glow-fs64v-4t`, `gp-extra-300s-60`), through
  `GlowFlight.step`;
- the finite-pack electrics (`stik-electric-6s`, `turbo-lumber-evolution`, `moonrunner-x99`), the catalog's default
  battery mode, through `_electric_step`.

A glow tick was the fleet's most expensive: `Simulation.step` cost 750–1220 µs headless with the engine running, of
which the native stage took 34–47 µs. Timing each piece of `GlowFlight.step` alone found its endpoint `point()` at
312 µs in flight and 530 µs on the runway. That call is the whole GDScript glow source evaluation: propeller,
lifecycle, fuel-feed solve and coupled response.

`step()` and `_count_segment` read only `ok` and `firing_fraction` from it. The native glow stage computes the same
point evaluation for every RK stage it answers.

## Change

- `nk_glow_stage.hpp` and `nk_stage.hpp`:
  - `GlowStageResult` and `StageResult` carry the lifecycle point's `firing_fraction`, from the evaluation already
    made.
  - No law changes.
- `nk_kernel.cpp`:
  - `stage_glow_firing(body, values, time_s)` evaluates the prepared glow stage at that endpoint with the tick
    context of the guarded pre-step.
  - It returns the fraction, or NaN to refuse: no glow stage or context, another layout, a refused stage or a
    nonfinite fraction.
  - It is not counted as an RK stage; `tick_stats()` counts its calls and answers.
- `native_stage.gd`: `glow_firing`, bound for the glow family (`_glow_firing_bound`).
- `flight_session.gd`: `native_glow_firing` answers only inside the tick whose guarded pre-step installed the native
  context (`_native_endpoint_tick`). It refuses with:
  - injected failures, an RC track or a pending weather reset;
  - a derived session class, whose point inputs may differ.

  `native_glow_firing_enabled` is the test hook; `native_glow_firing_answers` counts its answers.
- `glow/flight.gd`: the step policy's endpoint and `_count_segment`'s intermediate samples go through
  `_firing_sample`. It returns `{ok, firing_fraction}` from the native answer, or calls `point()` on NaN.

A native refusal is always exact, because `point()` then runs. The stage composes `point()` with the airframe,
ground and coupled response, so it can refuse states where `point()` alone succeeds; those keep the reference cost.

## Evidence

- `app/tests/test_native_glow_firing.gd`: 89 checks, none failed, for the four native glow aircraft with their
  engines started (`glow_start()`).
  - At 1,600 random endpoints inside guarded ticks, every answer equals `point().firing_fraction` bit for bit. The
    endpoints vary body, rpm, head temperature, crank phase, fuel and time; 1,215 of them were firing.
  - The stage refused 17, all of them where `point()` had no finite fraction either.
  - These flights are byte-identical tick by tick with and without the answer, glow telemetry included:
    - runway takeoffs, airborne starts and idle cuts;
    - fuel exhaustion through the resource events, with `fuel_exhausted`, `glow_stopped` and
      `glow_rotor_stopped`, and the transition segments' samples;
    - gusty and turbulent flights.
  - The kernel answered every endpoint.
  - Refusals: outside the guarded tick, the hook off, a pending weather reset, a derived session class.
- All nineteen installer gates are identical for binary
  `b3bd91414ff63e4ab738a5b31ac199f15e37e5356bd52c1bfbb484f85bea172d`, and the mutant build still fails. Accepted
  results (tool root, not in Git):
  - `stage-20261126T222548901822Z.json` `5ce09922b54f91c4ebcdca3a0addcc144be6e847cdafe9dc09f0955afb0573cb`
  - `stage_mutant-20261126T222617565208Z.json` `621431ec0a56724b66ab70c11a6333e053f2c878a0f2d9e1788b1924411f6f5d`
  - `trajectory-20261126T222646537573Z.json` `ed91d14aed08a19f71d500de899f197664a8be81e41c57ed7d38d95a62c0cf13`
  - `glow-stage-20261126T222922683728Z.json` `6534e46f0f6ae7154048b10876b6883dbd9402dc0051a611629fcc126b90aaf5`
- With the native stage installed, 75 suites pass:
  - all native suites, including NK-6a's tick driver and this one;
  - all 39 glow, nitro and fuel suites, including the glow oracle;
  - golden flights, replay integrity and policy, the runway fleet, and reset and restore publication;
  - turbulence, wind, atmosphere and spatial-weather flights, and the lake session;
  - crash cost (fleet), the ground-accident session, and the Extra runway and handling;
  - trim throttle, `Simulation`, statistics context and failure events, and resource events.

  `test_weather_publication` still fails only on the publication fixture renewal pending since NK-5d.

## Gain

Headless, engines running, alternating 480-tick blocks of the same flight (`Simulation._physics_process`):

| Aircraft | Reference | NK-6b |
| --- | ---: | ---: |
| Stik glow 61FX, airborne | 911 µs | 622 µs |
| Stik glow 61FX, from the runway | 1,081 µs | 628 µs |
| Stik glow FS64V, airborne | 923 µs | 584 µs |
| Extra 300S, rolling | 769 µs | 701 µs |

The Stik glow installations solve a fuel feed in `point()`; the Extra's endpoint is cheaper, so it gains less.
What remains of a glow tick is GDScript:

- the mass-aware contact filter (`_resolve_mass_contact_step`, 125–292 µs);
- the session pre-step (100–118 µs);
- `ResourceStep` with its event closures (about 60 µs beside the stages);
- the lifecycle acceptance.

Those are the next NK-6 steps, with the finite-pack `_electric_step`.

## Limits

- Windows only was built and installed locally; CI's three native-kernel jobs requalify each platform on push.
- The HUD's glow line (`main.gd`, `glow_state()`) still evaluates `point()` at presentation cadence; it is outside the
  tick and outside this step.
