# NK-6m — the glow voice's synthesis loop in the native kernel

2026-11-27. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F5b per-frame scripts](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).
Follows [NK-6l](../NK-6l/README.md).

## Why

A glow engine's sound is synthesized sample by sample: `GlowVoice.render_telemetry` (`app/audio/glow_voice.gd`) runs
its loop 22,050 times per audio second on the glow audio pump's worker thread. In GDScript that costs about 26 ms of
CPU per audio second, 1.2 µs per frame, for as long as a glow aircraft is loaded.

## Change

- `nk_glow_voice.hpp`: the per-sample loop in GDScript's operand order, with Godot's `fposmod`, `floori` and
  `clampf`, the same `sin` and `cos` as the qualified stage, and a single-precision conversion per sample, as
  `Vector2(sample, sample)` makes. The voice passes every block constant, its literals included (`0.000001`, `0.28`,
  `0.15`, `0.98`), so both loops read the same parsed values. Audio only: nothing reaches the simulation.
- `nk_kernel.cpp`: `glow_voice_block(parameters, harmonics, state, frames)` returns the block's PCM and loop state.
- `glow_voice.gd`: each voice creates its own kernel object on its worker once the verified library has loaded the
  class, and runs the native loop. It keeps the GDScript loop as the reference and the fallback: no library, a library
  without the method, a malformed answer or `native_loop_enabled = false`. The loop's literals became constants shared
  by both paths; the GDScript loop's arithmetic is unchanged.

## Evidence

- `app/tests/test_glow_audio.gd`: 47 checks, none failed. A native voice and a GDScript voice render the same 960
  blocks: 24 scenarios of 40 blocks with both families, 0–26,000 rpm (past the harmonics' Nyquist limit), firing
  fractions from 0 to 1, one to four blades, a stopped engine, an empty tank, measured source vibration, the
  accepted engine's cycle anchors and block sizes from 1 to 900 frames. Every PCM byte and every loop state value
  is identical, and every block used the native loop.
- All nineteen installer gates are identical for binary
  `dd41d9b1642fd3afafe752223450b36617b96f167f0d7f69c582e83c609d173b`, and the mutant build still fails. Accepted
  results (tool root, not in Git):
  - `stage-20261127T094647509502Z.json` `8cb3e0aa43e2c627c6285b6f88233fd087821819636aacee606053de2cfa13ab`
  - `stage_mutant-20261127T094713209155Z.json` `9383b93a0b9cd119ff55c4e33c028e86fb0122309966bce55beda8c550dd3567`
  - `trajectory-20261127T094738603066Z.json` `2c4f525349ab47686a8967a1b28fc563bdd537da81d4a49c0d39679fafed3930`
  - `legacy-ground-20261127T095112533771Z.json` `457b3884e0d50af3784cb80c1a721c27831c38a4a9b2a08ca652aa81f5d2ec71`
- With the native library installed, the 74 audio, glow and native suites pass, among them the glow audio pump
  (worker thread), engine audio, soundscape and every `test_native_*` suite. `check_native_pack.gd` needs an exported
  RC-car package (`--main-pack`) and does not apply here.

## Gain

Headless, 512-frame blocks at 9,000 rpm, two runs each:

| Family | GDScript loop | Native loop |
| --- | ---: | ---: |
| Two-stroke | 24.8–25.6 ms per audio second (1.12–1.16 µs per frame) | 8.8–9.5 ms (0.40–0.43 µs) |
| Four-stroke | 26.9–27.4 ms (1.22–1.24 µs) | 10.5–10.8 ms (0.48–0.49 µs) |

What remains per block is the voice's GDScript block setup (snapshot parsing and cycle anchors) and the native call.
