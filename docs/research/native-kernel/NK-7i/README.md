# NK-7i — flight audio's wind and air data from the published endpoint

2026-11-28. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F5b per-frame scripts](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).

## Why

Every frame, `FlightAudio.snapshot()` evaluated the session's wind (`wind_at(sim.time())`, about 10 µs) and air data
(`air_data(sim.state)`, about 12 µs) in GDScript, for the accepted state that the last tick just published. The native
stage already evaluates both for that endpoint. NK-5i's `published_endpoint_facts` answers the airspeed from it, and
NK-5g's pre-step uses the same `pre_step_air`.

## Change

- `nk_kernel.cpp` `stage_endpoint_air(s, aux, time_s)` answers `[wind north, east, down, v_air x, y, z, V]` at the
  endpoint, as `pre_step_air` evaluates them. Spatial weather answers empty, so GDScript keeps it.
- `NativeStage.endpoint_air` binds it.
- `FlightSession.published_endpoint_air()` answers under `published_endpoint_facts`'s own conditions:
  - this publication's guarded context;
  - `sim.state` and `sim.aux` still carrying its bits;
  - no RC track, no pending weather reset, no derived class.

  Otherwise it answers empty. Hook: `native_endpoint_air_enabled`.
- `FlightAudio.snapshot` uses it for the wind vector, `air.v_air` and `air.V`, and otherwise calls the reference.

## Evidence

- `app/tests/test_native_endpoint_air.gd` (13 checks) flies the P-51, the glow Stik 61FX and the electric Stik 6S on
  the production field for 600 frames of four ticks each, with throttle and pitch changes.
  - It runs in calm, gusty, turbulent and spatial weather.
  - Every frame the whole `FlightAudio.snapshot()` is byte-identical with the native answer on and off.
  - The native answer served all 600 calm, gusty and turbulent frames; spatial weather kept the reference.
  - A 10⁻⁹ change to the airspeed is detected.
- 136 of 140 suites pass on the installed binary: every `test_native_*` script and every suite that reads flight
  audio, the session's wind or air data, or its published endpoint answers. Of the other four:
  - one exits cleanly but trips the local runner's pattern;
  - one needs a research fixture absent from the build tree;
  - one is `test_yaw_damping`'s open R02 gate;
  - one is the companion test, which stops on the `main.gd` pin. That pin is renewed in the working tree and goes in
    at push.
- All nineteen installer gates pass for binary `68ae740dc324f55195d6cd124a1e9172e8e8f20f4160dc9f14bfb6566942d11b`,
  and the mutant build still fails. Accepted results (tool root, not in Git):
  - `stage-20261128T104901086199Z.json` `5d3dbfe70cced302dec31f4055639bf7feac9e454bd244e8100656b6e9b0f3f0`
  - `stage_mutant-20261128T104926692662Z.json` `019bfac0eafcf937aebfe3a9d127668926de0e3f6916a3131f1653e838d7bc87`
  - `trajectory-20261128T104952081327Z.json` `2e8adbbaae829dd56f153e22f6b2fa9a7da71f7079ef7b4d132b2c688fb7473a`
  - `legacy-ground-20261128T105325750697Z.json` `fc0265844efbda2c6c47736b63c34c16ba9a28c09b7b0a7383b177104128cb5a`

## Gain

Headless, native backend, production field with cost observations on (as the app flies), 1,200 frames of four ticks,
the hook alternating each frame, two runs. Median `FlightAudio.snapshot()`:
- P-51: 58–59 → 47–48 µs per frame;
- glow Stik 61FX: 76–78 → 64–66 µs per frame.

## Scope

- Windows x86_64 only. The macOS and Linux parity runs are not done yet.
- Spatial weather and the atmosphere configuration (sound speed, humidity) stay in GDScript.
