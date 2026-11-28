# NK-6r — the soundscape's retarded emission in the native kernel

2026-11-28. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F5b per-frame scripts](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).
Follows [NK-6m](../NK-6m/README.md), which first moved an audio loop into the kernel.

## Why

Measured live in the Windows app (Corsair, airborne), the soundscape's per-frame update costs 74–94 µs. Its largest
piece was `heard_snapshot`, the AUD-11 propagation delay, at 13–18 µs. Inside it, `SoundscapeModel.retarded_emission`
finds when the sound now heard left the aircraft. It scans the recent source history, then bisects the crossing over
40 iterations, each with a `Vector3.lerp` and a `distance_to`.

## Change

- `nk_kernel.cpp`: `retarded_emission(times, positions, listener, now, sound_speed, min_index)` returns
  `[index, alpha, delay, truncated]`. It keeps GDScript's mixed precision. Times, the sound speed and the bisection
  run in double. `Vector3.lerp` (with its weight cast to float), the difference and the length run in float, as
  Godot's `real_t` does. The square root is SSE `sqrtss` on x86-64, so it is correctly rounded without a library
  call. It is presentation only and reads no stage state.
- `soundscape.gd`: `heard_snapshot` asks the kernel when the verified library has loaded the class, as the glow
  voice does. Otherwise it runs the model in GDScript. Hook: `native_emission_enabled`. The delayed-key list is
  also a constant now, so it is no longer concatenated every frame.

## Evidence

- `app/tests/test_native_retarded_emission.gd`: 4,000 random source histories give bit-identical answers. They span
  slow to supersonic sources, listeners up to 1.5 km, sound speeds across and beyond the clamp, any history start,
  empty and mismatched histories, and more than 1,000 interpolated crossings.
- All nineteen installer gates are identical for binary
  `d6b984df47ab59fbb52021bfdb6ad158215c2dc262803f72a3745f409ac857ce`, and the mutant build still fails. Accepted
  results (tool root, not in Git):
  - `stage-20261128T001748900821Z.json` `dd048dc3092512e2f5acd07404f652c85d1ad414a451fc41d98ea43a467f1f1f`
  - `stage_mutant-20261128T001814003133Z.json` `40b67c5103970d0458026a7d4958c98832ad406eeee36f15e1ce75d00a2fc940`
  - `trajectory-20261128T001839352023Z.json` `85d47b8d32c38464938e1648dc830835a83c8b611d1f14272be4df70386889e9`
  - `legacy-ground-20261128T002211574092Z.json` `9d3cee06b75f6bb0ed6a306b814a54b00803b5aaf4fc48c6bdd1e6cd6d09119b`
- 52 of 53 audio, soundscape, glow and catalog scripts pass. `test_rcv_nitro_audio` is a runner false positive (its
  line reads "FAILURES=0").
- Live Windows app, Corsair airborne, chase and orbit views: the heard snapshot is identical with the hook on and off,
  and no errors are logged.

## Gain

Live, per frame: `heard_snapshot` costs 10.5–11.7 µs native and 16.3–18.5 µs in GDScript.
