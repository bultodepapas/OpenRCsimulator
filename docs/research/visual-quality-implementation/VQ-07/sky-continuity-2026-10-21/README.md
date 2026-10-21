# VQ-07 / FW-MOON-06d: High sky continuity

2026-10-21. Base `6943058dd0e059395e325480573e475e1087ffd6`.
Follow-up to [field-cue parity](../high-followup-2026-10-21/README.md).
`manifest.json` identifies changed source, binary builds and retained evidence.

## Implemented behavior

High's sky reflections made `radiance_unused` false. The existing safety gate
therefore skipped all between-step moon, star and twilight updates. At 20× world
time this caused a visible jump every 1.5 simulation seconds.

Flowing High worlds now configure the stock realtime sky filter before attachment.
The frame-write gate checks the actual sky mode and required 256-pixel cubemap.
Frozen worlds keep QUALITY; Standard retains its existing unused-radiance policy.
No physical state, aircraft data, assets or celestial calculation changed.

This trades reflection-filter quality for dynamic continuity. Godot documents
REALTIME as a fast, lower-quality filter for dynamic skies requiring a 256-pixel
cubemap; QUALITY is intended for infrequent changes.
[Godot Sky reference](https://docs.godotengine.org/en/4.7/classes/class_sky.html).
This does not add volumetric clouds, GI or a custom atmosphere renderer.

## Controlled continuity evidence

Windows / RTX 3090 / NVIDIA 617.42 / Godot 4.7.2 `ed1daf0bf`. Native runs were
serialized. The production World probe uses 1920×1080, 4× MSAA, 10 s warmup,
481 draws at a prescribed 60 Hz clock and 20× world time. It has no aircraft or
flight simulation. PNG readbacks occur afterward. `reduce_probe.py` validates
metadata and reproduces `probe-summary.json` from the retained reports.

| High case / measurement | Before | After |
| --- | ---: | ---: |
| Moon maximum angular increment per sample | 0.117588° | 0.001309° |
| Stars maximum angular increment, moon case | 0.125343° | 0.001399° |
| Twilight maximum absolute zenith log-luminance increment | 0.219943 | 0.002446 |
| Moon view GPU p95 | 0.526 ms | 1.502 ms |
| Twilight view GPU p95 | 1.474 ms | 1.529 ms |

The timing uses uncapped manual draws, not real-time 60 FPS presentation. The
moon view has a narrow 2° FOV; twilight uses 65°. These are different workloads,
not a flight budget. GPU queries may lag. The candidate-only paused-clock samples
report GPU p95 0.547/1.478 ms after discarding eight draws; no matched paused
baseline exists, so they cannot isolate realtime-mode overhead. Those 120 samples
were added after the baseline; the earlier active loop was unchanged.

Standard's four numeric trace fields and all **12 PNGs are exactly identical**
before/after. The rendered moon remains textured and the twilight horizon/field
renders; stills do not establish motion readability or glossy-reflection parity.

## Native packaged flight diagnostic

One before/after Windows pair uses the Stik, Club field, airborne half power,
ideal battery, pilot camera, 2026-09-26 20:30, 20× time, actual 1920×1080,
VSync on and no additional FPS cap. Each records 10 s warmup plus 60 s sample.
Checked-runner commands/logs and raw reports retain the full configuration.

| Measurement | Before | After |
| --- | ---: | ---: |
| Wall p95 | 18.323 ms | 18.272 ms |
| Wall p99 | 21.448 ms | 22.082 ms |
| Root GPU p95 | 5.196 ms | 5.681 ms |
| Root render CPU p95 | 0.668 ms | 0.858 ms |
| Simulation / aligned wall time | 1.000044 | 0.999960 |

Both complete active simulation; both miss the 18 ms wall-p95 gate. One native
window snapshot was taken near simulation second 63 in the baseline only. This
and the lack of repetitions prevent treating the pair as a clean performance
comparison or speedup. The offscreen controls establish the continuity fix;
the flight pair is a cost screen and exported execution check only.

## Checks, limitations and decision

- Native High profile: 61 checks; native High moon flow: 33. Headless profile: 50,
  moon flow: 33, world flow: 26, presentation context: 17. All passed their final
  checked invocation. Existing tests cover pause, replay clock, frozen time,
  step endpoints, twilight continuity and the protected QUALITY path.
- The first presentation-context invocation used an incorrect completion marker
  and was rejected despite passing assertions. Its receipt is retained alongside
  the corrected passing invocation; it is not counted as a passed runner call.
- Existing `OpVectorExtractDynamic`, maple-wind and seven Texture RID exit
  warnings remain. The full app suite was not run for this bounded change.
- A separate 18:00 packaged visual inspection retained `visual-flight-pilot.png`.
  Its collector completed, but shutdown reported 21 ObjectDB instances and one
  resource still in use: `checks/visual-flight-o_vfgkej` is a **failed** check.
  Verbose 30 s repeats without input passed on both builds; a baseline keyboard
  inspection also passed. The final candidate repeat lost focus, paused and
  later recorded a crash; it passed engine-log inspection but is not an active
  flight comparison. The original exit error remains unisolated, not fixed or
  established as pre-existing. These visual runs are excluded from timing claims
  and do not establish camera-switch or package lifecycle acceptance.
- Daytime steady filter cost, glossy aircraft/water reflection parity, sustained
  memory, repeated native pairs, pilot readability and other GPUs/platforms
  remain unqualified. The candidate-only paused observation does not close them.

Retain the localized repair in **experimental High**: it restores existing
continuous world behavior with two runtime-file changes and a measurable cost.
It does not qualify High as a supported performance preset. Next work is to
isolate the shutdown resource error, then native presentation/pacing attribution
and ordinary moving-aircraft/reflection checks, before expanding effects.

Local unsigned trial:
`D:/OpenRCsimulator-scratch/sky-continuity-20261021/release/OpenRC Simulator.exe`,
with exporter-managed `openrc_ground_vehicle.dll` beside it. Normal launch is
Standard; use Home **Settings → Graphics → Try High (restart)**. This manual
Windows export is separate from the tagged multi-platform release pipeline.
