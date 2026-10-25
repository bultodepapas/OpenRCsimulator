# GDU-06: native audio compatibility

2026-10-25, Windows x86-64. The existing menu, glow-worker stress and guarded wind
paths pass with official Godot 4.8-beta1, native WASAPI and headless display.
No accepted audio data, simulation source or runtime workaround was changed.

| Existing probe | Observed result |
| --- | --- |
| Menu, run by the lead | 35%, 100% and mute captures pass; four committed-Quit cases pass, including time scales 0/16 and a 100 ms preceding stall |
| Glow-worker stress, 4.8 | All 12 gates pass over 125 seconds and five 600 ms main-thread stalls; zero generator skips, capture drops, fallback or worker errors |
| Wind, 4.8 | 48 kHz WASAPI; finite samples, no clipping, pause, distance cutoff and bus cleanup pass; zero Master/fabric capture drops |
| Wind, 4.7.2 baseline | The same gates pass with the same source WAVs, import settings and audio scripts |

The two wind snapshots contain the same 149 files (31,307,002 bytes each), with
separate fresh import caches and profiles. All copied source files remain
unchanged after both imports. Captured durations are 21.024 s on 4.8 and
21.0133 s on 4.7.2, versus approximately 21.0165/21.0169 s wall intervals.
Overall RMS levels are −37.973/−37.968 dBFS and peaks −19.063/−19.014 dBFS.
These asynchronous real-time captures are not expected to be sample-identical.

All six retained Godot invocations (the menu, stress, two imports and two wind
runs) complete with zero engine errors/warnings. Native audio probes ran
sequentially; the display remained headless and no additional renderer was
started. Other suites and the lead's UI were active, so these results do not
qualify quiet-host performance, hardware output latency or loaded-flight audio.
No listening or acoustic-realism claim is made.

## Version-scoped workarounds

The bounded upstream audit compares the 4.7.2 source with commit `4d10419ca`:

- The [filter coefficient source](https://github.com/godotengine/godot/blob/4d10419ca/servers/audio/audio_filter_sw.cpp)
  is byte-identical. Keep the existing half-dB conversion for the squared
  high-shelf gain; this is source evidence, not a new isolated mixer-response capture.
- The [HardLimiter processing source](https://github.com/godotengine/godot/blob/4d10419ca/servers/audio/effects/audio_effect_hard_limiter.cpp)
  differs only in the editor's release-unit suffix; its processing function is
  identical. The legacy limiter source is also identical. Keep the existing
  −1 dB Master ceiling and 2 s release; isolated overload/recovery remeasurement
  remains separate.
- [WAV source](https://github.com/godotengine/godot/blob/4d10419ca/scene/resources/audio/audio_stream_wav.cpp)
  includes data-length, QOA and loader changes. Keep the PCM loop guard until a
  dedicated wrap-seam comparison qualifies its removal.
- The 3D player's `play()` function is unchanged, although its surrounding source
  includes API changes. Keep positioning before playback; the staged wind result
  does not isolate the historical first-buffer artifact.

The existing isolated loop/filter/limiter projects require Movie Maker rendering.
They were not run while the lead owned the renderer. No workaround was removed
on the strength of a source comparison or a broader guarded-path pass.

[Verification](verification.json) retains the lead's menu report, gate summaries,
source URLs/hashes, exact checked commands and raw artifact hashes.
[Audio source manifest](source-manifest.json) identifies the A/B inputs. Full
reports, source audit copies and WAVs remain outside Git under
`D:/OpenRCsimulator-experiments/gdu03-audio-native/`; the lead's menu artifacts
remain in the frozen suite's `tmp/gdu03-audio/`. Commands remain owned by the
[audio tool guide](../../../../../tools/audio/README.md).
