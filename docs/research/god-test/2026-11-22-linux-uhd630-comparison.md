# Linux UHD 630: PRIMIS and megatron tours, causes and fix

On 2026-11-22 the three-aircraft [performance tour](../../../tools/godtest/PERFORMANCE_TOUR.md)
ran on both Linux Intel UHD 630 hosts with identical source, engine, native
physics and settings. This record compares them, explains the Linux findings of
the [2026-11-21 stutter map](2026-11-21-stutter-map.md) and records one harness
fix with its before/after result. One pass per aircraft and host: an exploratory
screen, not qualification.

| Host | CPU visible to the container | GPU | Container RAM |
| --- | --- | --- | --- |
| PRIMIS CT 405 (test pool host) | i5-9500T, 4 cores | UHD 630 (CFL GT2) | 4096 MiB + 512 MiB swap |
| megatron CT 206 (bench host) | i5-10500, 6 cores | UHD 630 (CML GT2) | 4096 MiB + 512 MiB swap |

Common setup: source `7f4db1b1b` (identical 9,651-file digest on both hosts),
pinned Godot 4.8-beta2 (`34d0599a…`), native physics for this source, Mesa
25.0.7 ANV, headless Weston 14 at 1920×1080 borderless, Forward+/Vulkan, Medium
detail, no frame cap. megatron ran with Frigate, the other user of its iGPU,
stopped.

## The two hosts behave the same

Both GPUs are the same Gen9.5 part; results differ by run-to-run noise, not by host.

| Phase (Stik / jet / Corsair) | PRIMIS | megatron |
| --- | --- | --- |
| First Home | 6.0–6.4 FPS | 6.1–6.3 FPS |
| Runway circuit | 13.2–13.6 / 8.8–9.1 / 8.7–9.3 FPS | 12.2–12.4 / 8.3–8.7 / 8.3–8.4 FPS |
| Simulation/wall in the circuit | 0.66–0.68 / 0.44–0.45 / 0.43–0.46 | 0.61–0.62 / 0.41–0.43 / 0.41–0.42 |
| Peak RSS | 1.7–1.8 GB | 1.4–1.9 GB |

## Causes

| Finding (2026-11-21 map) | Cause | Evidence |
| --- | --- | --- |
| 36–45 s flight-loading freeze, forced kill at shutdown | **Test-host audio setup.** Without a sound device the hosts used an ALSA `pcm null` default. Godot opens ALSA non-blocking and mixes while holding the driver lock; a null device never returns `EAGAIN`, so the mix thread spins and starves the main thread whenever it needs the audio lock | One Godot thread at 99.9 % CPU with ALSA null and ~7 % with the Dummy driver. Home → flight 13.6–19.0 s against 6.5–6.6 s. The 74 audio samples load in 46 ms headless, yet the freeze was spent between consecutive `.wav` loads |
| Slow motion below ~15 FPS | Intended: `max_physics_steps_per_frame=12` at 240 Hz keeps real time only above 20 FPS ([project.godot](../../../app/project.godot)) | 12 ticks/frame ÷ ticks needed per frame matches every measured pace: 0.41–0.68 |
| 6 FPS Home, slower than flight | GPU fill rate in the field. Home's camera sees more field and scenery than the flight camera | Home GPU 138 ms per frame: field 86 ms (62 %), of which scenery 22 ms; half resolution saves 76 ms; MSAA ×2 34 ms. Flight GPU 82 ms |
| A Godot shader-cache cost | Rejected as the cause | A cold `user://` cache gave 18.5 s Home → flight and a warm one 22.4 s (both with ALSA null) |

On these hosts the product's Automatic mode would not choose this workload. It
selects Standard (Compatibility/OpenGL) and Low detail for an integrated GPU
([auto_graphics_policy.gd](../../../app/render/auto_graphics_policy.gd)). The tour
deliberately keeps Forward+ Medium as its fixed comparison workload.

## Fix and before/after

The runner now launches Godot's Dummy audio driver on Linux when no accessible
ALSA playback device exists (`/dev/snd/pcmC*D*p`). The driver still mixes every
period at real-time pace, without output. `execution.json` records
`audio_output`. Containers can list the host's cards in `/proc/asound/cards`
without any `/dev/snd` node, so the check uses the device nodes.

| Loading phase (Stik / jet / Corsair) | Before: wall, worst frame | After: wall, worst frame |
| --- | --- | --- |
| megatron | 36.6 / 40.9 / 41.3 s; 31.6–36.8 s | **4.7 / 4.7 / 6.8 s; 1.02–1.07 s** |
| PRIMIS | 16.0 / 20.9 / 20.3 s; 11.0–15.3 s (45.1 s Stik in an earlier pass) | **5.2 / 5.3 / 8.0 s; 1.17–1.21 s** |

Flight frame rates did not change. The forced kills disappeared on megatron
(0 of 3, earlier 2 of 2 passes on the Stik). Loading and Home-return phases now have complete draw evidence.

Still ineligible after the fix:

- **Startup:** the window is undrawable for ~16 s while the first Home is built.
- **Jet and Corsair circuits:** they reach the 300 s wall deadline in slow motion.

## Shutdown race (open)

PRIMIS still needed one forced kill after the fix (Corsair, 1 of 3). A direct
repeat on megatron quit the app 0.3–8 s after Home was ready. With a 1 s delay,
the process outlived a 25 s stop wait; every other delay exited within 2.5 s.
Home's flight preparation starts loading `main.tscn` on a thread about then
([home_flight_preparation.gd](../../../app/ui/home_flight_preparation.gd),
[flight_scene_load.gd](../../../app/ui/flight_scene_load.gd)). The debug bridge's
`quit` ends the tree directly. AppRoot's own quit drains that preparation first.
The cause still needs a thread backtrace before a fix is accepted.

## Host notes

- PRIMIS CT 405 at 5120 MiB let the iGPU's shmem buffers and page cache lower the
  node to its 1536 MiB watchdog threshold; the watchdog stopped the container in
  the Corsair case. At 4096 MiB all three cases completed, with the node at
  1.6–2.1 GB available.
- No GPU utilization backend exists for Intel; GPU monitoring is incomplete by
  design on these hosts.
