# NK-6s — the glow engine vibration in the native kernel

2026-11-28. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F5b per-frame scripts](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).

## Why

Flight audio builds a glow aircraft's voice keys every frame (`audio/glow_audio_state.gd`). One of them is the source
vibration from `physics/glow/vibration.gd` `evaluate`: the slider-crank force and its 1x/2x orders. It cost 10–16 µs
per frame, about half of it re-validating the prepared geometry on every call.

## Change

- `nk_kernel.cpp`: `glow_vibration(geometry, crank_phase, omega, alpha, firing)` returns `evaluate`'s numbers for a
  validated geometry, in its operation order. It uses Godot's `fposmod` and the kernel's qualified `sin`, `cos` and
  `sqrt`. It returns 0 wherever `evaluate` would fail.
- `glow_audio_state.gd` `vibration()`: for a read-only prepared geometry that `evaluate`'s own check accepted once, the
  kernel computes the numbers and GDScript assembles the same read-only dictionary. Any refusal, and every other case,
  runs `evaluate`. Hook: `GlowAudioState.native_vibration_enabled`. The physics file is unchanged.

## Evidence

- `app/tests/test_native_glow_vibration.gd`: 20,016 samples on four stock glow geometries match bit for bit, including
  the read-only flag. The samples cover crank phases of any sign and size, speeds from 0 to beyond redline, zero and
  nonzero angular acceleration, firing fractions, and invalid inputs. An unchecked geometry returns `evaluate`'s
  answer.
- `test_glow_audio_state.gd` (48 checks) still finds every audio key equal to `GlowFlight.telemetry`'s.
- All nineteen installer gates are identical for binary
  `b9a09b33fac9ee70cb03cc62e75ca74af218f1e6f6642686ffff09a6add530ac`, and the mutant build still fails. Accepted
  results (tool root, not in Git):
  - `stage-20261128T021830201511Z.json` `777c76a5cacf730e6603d17775a2d2c7750911c958924df34d01f0b009cddf06`
  - `stage_mutant-20261128T021855849768Z.json` `02100c9560b14f49c7e2ba641fe1c0f1486a901a768e67f8be8ec8872d761611`
  - `trajectory-20261128T021921841611Z.json` `e0dbfc3d16fc485e28b2b45cc1b103962865792b544ae2034c6f06a57209572c`
  - `legacy-ground-20261128T022316962957Z.json` `d14b5b888620d3997246ac89e43549c12b713b38810939f6dc2b96cba80f5261`

## Gain

Headless, GP Extra 300S airborne: the vibration costs 3.8–4.4 µs against 11.5–14.1 µs for `evaluate`.
