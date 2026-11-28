# NK-7l — the glow voice's whole block render in the native kernel

2026-11-28. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F5b per-frame scripts](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).

## Why

The glow engine's voice renders 256-frame PCM blocks on its pump's worker thread, about 86 per audio second.
[NK-6m](../NK-6m/README.md) moved the per-sample loop into the kernel. Each block still ran `render_telemetry`'s
GDScript preparation first: the snapshot parsing, the family switch, the physical phase anchor and its fire
accounting, `source_vibration_pcm_peaks` and about thirty block constants.

## Change

- `nk_glow_voice_render.hpp` `render` ports that preparation line by line and then calls NK-6m's loop.
  - Every decimal literal comes from `GlowVoice._RENDER_CONSTANTS`, which GDScript parses and binds once per voice
    (`glow_voice_bind`).
  - `exp`, `sqrt` and `absf` are the engine's own.
  - It refuses a snapshot value whose GDScript conversion it does not reproduce: a non-bool `running`, a non-numeric
    `blade_count`, or a non-bool `ok` or non-string family in the source vibration. GDScript then renders that block.
- `nk_kernel.cpp` `glow_voice_render(snapshot, frames, state, last_family)` answers `[PCM, next state, last family]`
  from the voice's fourteen state fields.
- `GlowVoice.render_telemetry` uses it through its own kernel object, on the worker thread, and keeps the GDScript
  preparation as the reference and fallback.
  - Hook: `native_render_enabled`. `native_loop_enabled` off disables it too.
  - Diagnostic: `native_render_answers`.

## Evidence

- `app/tests/test_native_glow_voice_render.gd` (8 checks) renders three voices in lockstep:
  - the native render;
  - the GDScript preparation with the native loop;
  - the pure GDScript voice.

  Every block compares the PCM bytes and all fourteen state fields and the last family.
  - Telemetry from glow flights of the 2-stroke 61FX and the 4-stroke FS64V goes through the pump's own
    `snapshot_for_render`, with anchored blocks on new revisions and extrapolated repeats: 1,050 blocks each, all
    answered natively.
  - Nineteen crafted cases:
    - an engine stop and restart;
    - a family switch;
    - phase without counters;
    - bare telemetry;
    - an empty tank;
    - six malformed source vibrations;
    - three odd blade counts;
    - throttle as load;
    - no maximum;
    - the family as a StringName;
    - a non-glow family;
    - zero and negative frame counts;
    - a numeric `running`, which the native render refuses.

    The native render answered every crafted block except the refused one.
  - A one-sample change is detected.
- 92 affected suites pass on the candidate: every `test_native_*` script and the audio, glow, soundscape and
  powertrain suites. The local runner flags one, `test_rcv_nitro_audio`, on its own `FAILURES=0` line; it exits 0
  with 23 of 23 checks.
- All nineteen installer gates pass for binary `f23a8167df1b0943af8e08e5f1fe86c708425ea6e90e6d1ef318baf2769308c5`,
  and the mutant build still fails. Accepted results (tool root, not in Git):
  - `stage-20261128T125624643258Z.json` `6fc58a335fc85235c50e4db1f32e99503cb5a1d40c8f35995df5e7a03e868d80`
  - `stage_mutant-20261128T125651027274Z.json` `3385e43418dc16a70b606f9b2f7dcae0ec6c1ac1a9dc57ff57b11f9911f3c878`
  - `trajectory-20261128T125717552563Z.json` `e16a5334db9a88d2c80ac4ba04795879adb0aff46068fcf7f222f96f73a13a7a`
  - `legacy-ground-20261128T130053384130Z.json` `6930b8b6520017dd24ec23ab656e8089563b0490d57a637cb7fca50f42b34fbb`

## Gain

Headless, native backend, telemetry of a glow Stik 61FX flight, 4,000 blocks of 256 frames, with the native render on
and off on the same snapshots. Median `render_telemetry`: 134 → 119 µs per block. That is about 1.3 ms less worker CPU
per audio second, or 11 % of the voice. The rest is NK-6m's per-sample loop: about a dozen engine `sin`/`cos`
calls per sample, which byte-identical PCM must keep.

## Scope

- Windows x86_64 only. The macOS and Linux parity runs are not done yet.
- The pump's per-block snapshot copy and status updates (about 6 µs) stay in GDScript.
