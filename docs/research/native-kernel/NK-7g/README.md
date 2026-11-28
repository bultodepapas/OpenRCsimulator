# NK-7g — the glow audio keys in one native call

2026-11-28. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F5b per-frame scripts](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).

## Why

Every glow aircraft's flight audio assembles its glow keys each frame. After [NK-7f](../NK-7f/README.md), that work
was still GDScript plumbing around native numbers:
- `GlowAudioState.build` reads the native firing fraction (NK-6b);
- it unpacks the glow state;
- it wraps the native vibration numbers (NK-6s) in a read-only dictionary;
- `FlightAudio.snapshot` then fills in its own keys.

## Change

- `nk_kernel.cpp` `stage_glow_audio_keys` builds the final key set in one call, with the GDScript's key order, key
  types and value types:
  - `GlowFlight.unpack`'s checks;
  - the firing fraction;
  - the vibration dictionary, read-only;
  - the snapshot's own keys. The snapshot adds `max_rpm`, `load`, `throttle` and `sample_tick` by assignment, so
    those are String keys; the rest come from a literal, so they are StringName keys.

  It answers empty wherever the GDScript would refuse or fall back.
- `GlowAudioState.native_keys` keeps the GDScript's own checks: the evaluator identity, and a read-only prepared
  geometry that the vibration check accepted. It then calls `FlightSession.presented_glow_audio_keys`, which shares
  `presented_glow_firing`'s conditions (`_presented_glow_allowed`).
- `FlightAudio.snapshot` uses that key set, and otherwise assembles the keys as before. Hook:
  `GlowAudioState.native_keys_enabled`.

## Evidence

- `app/tests/test_native_glow_audio_keys.gd` (4 checks) flies the glow Stik 61FX, FS64V and 55AX for 900 frames
  of four ticks each: idle, full and half throttle, a pitch-up, then the engine cut and the propeller winding down.
  - Every frame, the whole `FlightAudio.snapshot()` is byte-identical with the native keys on and off. The native
    key set answered 600 frames per aircraft; the 300 frames after the cut were assembled in GDScript.
  - A 10⁻⁷ change to one assembled value is detected.
- 48 suites pass on the installed binary: every `test_native_*` script and every suite that exercises flight audio,
  the glow audio state or the presented glow answers.
- All nineteen installer gates pass for binary `ad8e38391c4527ac8cfafd7dc56f462ee5e6d22f67440caa9ef346e9eba87b6c`,
  and the mutant build still fails. Accepted results (tool root, not in Git):
  - `stage-20261128T085745198357Z.json` `5f4788e392dd64c56279975c0c4313cb685fbcde6474de9246243a44d3dde9b7`
  - `stage_mutant-20261128T085810907695Z.json` `5e00707f41e2be95a054737a24edb2593c6d4f974367af3c1a5ce8a4ef52adfe`
  - `trajectory-20261128T085836657179Z.json` `2da88eb1d3d01cedbc805493ac17d6f0c49955b9dd9ff7b7c09514c0e44e9688`
  - `legacy-ground-20261128T090210232344Z.json` `2928da901feb6caeded0c3551cf1ce3e2465dc4c374ad7c681e449caaf6881ab`

## Gain

Headless, native backend, glow Stik 61FX and FS64V, 1,200 frames of four ticks, the hook alternating each frame,
two runs: median `FlightAudio.snapshot()` 84–86 → 75–76 µs per frame.

## Scope

- Windows x86_64 only. The macOS and Linux parity runs are not done yet.
- The snapshot's wind, air data and propeller and atmosphere reads stay in GDScript. Matching the weather's
  turbulence-layered `wind_world` exactly at render time is not shown yet.
