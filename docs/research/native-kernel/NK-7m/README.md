# NK-7m — flight audio's shaft torques from the published endpoint

2026-11-28. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F5b per-frame scripts](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).

## Why

Every frame, `FlightAudio.snapshot()` normalizes the engine load from the propeller's shaft torque at the accepted
state: `GlowAudioState.shaft_torques` at `(rpm, axial speed)` and at `(rpm, 0)`. It evaluated the session's air
density and, for a Ct/Cp propeller, `Propulsion.thrust_torque` and `prop_torque` in GDScript. A glow engine already
used the native blade model, but its density and axial speed were still computed in GDScript.
[NK-7i](../NK-7i/README.md) already answers the endpoint's air data natively.

## Change

- `nk_kernel.cpp` `stage_endpoint_torques(s, aux, time_s, rpm)` evaluates the endpoint's `v_air` and density as
  `pre_step_air` does. A glow stage answers from its blade model at `Propulsion.axis`' axial speed. Otherwise the
  stage's Ct/Cp propeller answers `thrust_torque()[1]` and `prop_torque(rpm, 0)`. It answers empty for spatial weather
  and for a stage without propeller tables.
- `NativeStage.endpoint_torques` binds it. `FlightSession.published_endpoint_torques(rpm)` answers under
  `published_endpoint_air`'s own conditions.
  - Hook: `native_endpoint_torques_enabled`.
- `FlightAudio.snapshot` uses it whenever its endpoint air was native. Otherwise it calls the reference.

## Evidence

- `app/tests/test_native_endpoint_torques.gd` (21 checks) covers five propeller models:
  - the glow 2-stroke 61FX and 4-stroke FS64V (blade model);
  - the P-51, the Corsair and the electric Stik 6S (Ct/Cp).

  Each flies 480 frames of four ticks on the production field in calm, gusty, turbulent and spatial weather, with
  throttle and pitch changes. Every frame:
  - the native torques equal `GlowAudioState.shaft_torques` bit for bit;
  - the whole `FlightAudio.snapshot()` is byte-identical with the native torques on and off.

  The native torques served all 480 calm, gusty and turbulent frames; spatial weather kept the reference. A 10⁻⁹
  change is detected.
- 124 affected suites pass on the candidate: every `test_native_*` script and the audio, ground, glow, soundscape,
  powertrain, mechanical and flight-session suites. The local runner flags one, `test_rcv_nitro_audio`, on its own
  `FAILURES=0` line; it exits 0 with 23 of 23 checks.
- All nineteen installer gates pass for binary `590cf6b4e2e8933e445408e43c278966b6777c05edea0d6b8e7c121c72343278`,
  and the mutant build still fails. Accepted results (tool root, not in Git):
  - `stage-20261128T131414617693Z.json` `021446adf7da5d05fea975113259707797b63d2ee9eb0a86cad3faa7d3760a34`
  - `stage_mutant-20261128T131440148249Z.json` `ef2bc4b091ac19a9160f0bdc9300c5374e1b5a0ae756767a29c7ce41cf42fae9`
  - `trajectory-20261128T131505836564Z.json` `5dcc1c569a76c8d5b5a055888ff85f3324cf0cf9ce0c5fdb4abe1a3166b65b8b`
  - `legacy-ground-20261128T131832307625Z.json` `c10c23df02d6fd6a5174d32f79ba0cbbf14c85b77ec3356f583713acde112c59`

## Gain

Headless, native backend, production field with cost observations on, 1,200 frames of four ticks, with the hook
alternating each frame. Median `FlightAudio.snapshot()`:

| Aircraft | µs per frame |
| --- | --- |
| P-51 | 50 → 43 |
| Electric Stik 6S | 42 → 36 |
| Glow Stik 61FX | 68 → 65 |

## Scope

- Windows x86_64 only. The macOS and Linux parity runs are not done yet.
- A turbine's load reads its throttle, as before; spatial weather keeps the reference.
