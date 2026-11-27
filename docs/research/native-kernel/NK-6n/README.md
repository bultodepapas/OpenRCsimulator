# NK-6n — the glow step's steady-tick acceptance in the native kernel

2026-11-27. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick cost](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).
Follows [NK-6d](../NK-6d/README.md), which integrates the glow resource step natively and then calls the policy's
accepted half, `GlowFlight.finish`, in GDScript.

## Why

Timers in a disposable instrumented copy put `GlowFlight.finish` at 55–61 µs per tick on the glow Stiks: about a
fifth of a glow tick. On most ticks nothing happens in it. No resource event fired, the engine keeps its lifecycle
mode, and finish only accepts the integrated candidate: two fractions clamped, the crank phase wrapped and the
combustion opportunities counted.

## Change

- `nk_glow_finish.hpp`: `glow_steady_finish` computes finish's state for such a tick, in the reference's operand
  order. It follows `GlowFlight.unpack` and `put_state`, `lifecycle.gd`'s `_state_error`, `_accepted_validated` and
  `count_opportunities`. It refuses every check that would fail and every lifecycle stop (fuel exhausted, overheat,
  stall), and finish then runs.
- `nk_kernel.cpp`: `integrate_tick` tries it when the bounded result has no events and the plan no transitions. The
  endpoint firing fraction comes from NK-6b's native point evaluation, so a refusal there also leaves the tick to
  finish. `glow_steady_finish_component` exposes the same function to tests, and `glow_finish_answers` counts answers.
- `flight_session.gd`: `native_glow_step_plan` adds the steady terms only where finish would cut nothing and take its
  prepared-evaluator branch, under NK-6b's conditions for the native firing fraction. The terms are the identity
  and family cycles, the maximum and stall rpm, the overheat temperature, and `_accepted_validated`'s literals and
  the lifecycle tolerances, which GDScript parses. Test hook: `native_glow_finish_enabled`.

## Evidence

- `app/tests/test_native_glow_finish.gd`: 76 checks, none failed, for the four native glow aircraft (Stik 55AX,
  Stik 61FX, Stik FS64V, Extra 300S 60).
  - 3,000 start and end stores per aircraft inside guarded ticks. Each end store is plausible, with at most one value
    at or across a check finish makes: the rpm envelope and stall, the fuel floor and rise tolerance, the overheat
    temperature, the transport, servo and air bounds, the phase's backward tolerance and cycle boundaries, the running
    flag, the stop reason, counters and the accumulator. Forty fixed pairs per aircraft add fractional,
    negative-fraction and 2^53 counters, signed-zero start values, a stop reason the end store does not carry and
    finite wheel values. The kernel answered 1,640–1,823 pairs, all fixed ones among them, each identical to
    `GlowFlight.finish` byte for byte. It refused exactly the pairs where finish fails or reports events, and no
    steady one.
  - Takeoffs, airborne flights, throttle cuts and fuel exhaustion fly byte-identical with the answer on and off,
    ticks and glow telemetry alike. The kernel answered every tick except the two or three around the fuel stop,
    which carry resource events.
- `app/tests/test_native_glow_firing.gd` (NK-6b) counts the session's answers inside `finish`, which steady ticks no
  longer call; its flight pairs now turn NK-6n off to keep exercising that path.
- An independent review found no input where the kernel answers and finish would return something else, and no way
  for the plan's terms to differ from what finish reads. It found the NK-6b counter above, a type guard for the
  identity's cycle (added) and the boundary cases above (added).
- All nineteen installer gates are identical for binary
  `18c2b1ee899ca6183c4eb2b38dda9bc83f4406e25bb82c0b6eed2129e24c6773`, and the mutant build still fails. Accepted
  results (tool root, not in Git):
  - `stage-20261127T103551240493Z.json` `5410a25d9106fb1e851bb8168a881dc30b11a3e8cc812d23b65ee056419b486c`
  - `stage_mutant-20261127T103616550599Z.json` `7ebe3036b762c6ccf26f3f20c606d936718be8e265f86572856e5b22b6a694e9`
  - `trajectory-20261127T103641911993Z.json` `52a878a1a361ce45229532a28fa123e80aa20a14feceed323acdbe8cf3e0598d`
  - `legacy-ground-20261127T104015227421Z.json` `4997af288c88c4da45f13afa1a7bc15109f2755d9b3e3c09b337e8a2180d7ff7`
- With the native stage installed, 241 of 242 affected suites pass: the NK-6k set and every glow, fuel and resource
  event suite. `test_native_pre_step` and `test_native_tick_driver` were rerun after an install that overlapped the
  first run; `test_fixed_gear_brake_input` again needs the checked runner's legacy-engine oracle.

## Gain

Headless, alternating 120-tick blocks with the answer on and off, whole tick, two runs:

| Aircraft | Airborne |
| --- | ---: |
| Stik 61FX (two-stroke) | 326–337 → 278–281 µs |
| Stik 55AX (two-stroke) | 317–326 → 265–274 µs |
| Stik FS64V (four-stroke) | 319–327 → 265–283 µs |

On the runway the blocks gain 30–66 µs; two of those flights ended in a taxi crash in both modes, so they are not
comparable.
