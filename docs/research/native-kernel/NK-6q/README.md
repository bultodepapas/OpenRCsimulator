# NK-6q — the step's own checks in the native kernel

2026-11-27. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick cost](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).

## Why

Timers inside real native ticks (a disposable instrumented copy) put `Simulation.step`'s own checks at 14–15 µs per
tick before the pre-step. Most of that time went to GDScript loops: the body's validity, the finiteness of the
inputs, the auxiliary state and the continuous state, and the inertia cache. The session repeated the same kind of
state check around every tick: twice in its guards, and on finite-fuel ticks four more times as the scenery
collision's stricter check (`|q·q − 1| ≤ 1.0e-9`) in the reach-proven scenery and lake paths. Each took about
2.4 µs.

## Change

- `nk_kernel.cpp`: four pure methods that need no prepared stage. `state_valid` is `Simulation.state_is_valid`
  (through the existing `tick_body_valid`, with the GDScript spelling of `1e-24`). `scenery_state_valid` is
  `SceneryCollision._state_is_valid`, with `_dot4`'s order. `arrays_finite` is three `Simulation._array_is_finite`
  calls. `inertia_cached` is `_refresh_inertia_inverse`'s cache test. The literal oracle gains the `1.0e-9`
  spelling.
- `simulation.gd`: when the installed model's stage belongs to the kernel, `step()` asks it for these checks at the
  same points and with the same refusals. Every other stage keeps them in GDScript. Hook:
  `Simulation.native_checks_enabled`.
- `flight_session.gd`: the session's guards and the two reach-proven contact paths call `_state_valid` and
  `_scenery_state_valid`. These answer through the native stage when one is installed. Hook:
  `native_state_checks_enabled`.

## Evidence

- `app/tests/test_native_state_checks.gd`: 17 checks, none failed.
  - 20,000 samples per check: the four native answers equal the GDScript reference. The samples cover NaN, ±inf,
    ±0, subnormals, values up to 1e300, wrong sizes, and quaternion norms a few ULPs around `1e-24` and
    `1 ± 1.0e-9`. Each check accepted between 3,134 and 11,868 samples and refused the rest.
  - The Corsair, Ugly Stik 60 and glow Stik 61FX each flew 1,500 ticks byte-identically with the native checks on
    and off. The native session's model offers the kernel's checks, and the hook keeps them in GDScript.
- All nineteen installer gates are identical for binary
  `5f726f43a5c4e011f4002518234a2a3e524d57a5964f5bcea9a4a57e9e5e44b6`, and the mutant build still fails. Every gate
  compiled the literal table, now 143 spellings including `1.0e-9`, and compared it bit for bit. Accepted results
  (tool root, not in Git):
  - `stage-20261127T224246860585Z.json` `1aa7c8d47273b444b60bf962e9f63f044d4ced88cc5a06e61183fcb6f5a9811d`
  - `stage_mutant-20261127T224312034154Z.json` `8a34e56c623a662799e7e224bd4391a924c56dbfba739ecf60a4cef774fb4346`
  - `trajectory-20261127T224337743362Z.json` `8e98929b693a345a15e1d3b0c0160b9e1f30b759973eb9dcb4e4caaf7045b437`
  - `legacy-ground-20261127T224709901578Z.json` `a6b5345f386cdedd68f0785b6b6a33ebb3fc66895f824b652012a05fddb338a3`
- 81 of 83 scripts pass: those that prepare a native stage or exercise the session, brakes, the lake,
  `test_golden` and `test_simulation`. `test_fixed_gear_brake_input` needs the checked runner's legacy oracle.
  `test_companions_observation` is a runner false positive (its line reads "FAILED 0").

## Gain

Alternating A/B, headless, airborne, whole ticks (session and step) with the checks on and off in the same build.
Three runs of 960 ticks per side:

| Aircraft | On | Off | Difference |
| --- | ---: | ---: | ---: |
| Corsair | 222.0 µs | 226.8 µs | −4.8 µs |
| Ugly Stik 60 | 133.4 µs | 137.5 µs | −4.1 µs |
| Glow Stik 61FX | 206.4 µs | 213.1 µs | −6.7 µs |

Single runs ranged from −16 to +5 µs. The gain is small next to the run-to-run spread, and it is consistent only in
the mean.
