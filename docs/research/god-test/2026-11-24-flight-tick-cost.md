# Where slow flight frames come from

On 24 November 2026 we decomposed every circuit frame in nine retained three-aircraft tours: Windows and ANGEL from 21 November, and PRIMIS with Automatic graphics. A delay in one frame returns as extra 240 Hz physics ticks in the next, at 0.75–1.9 ms of main-thread time per tick depending on host and aircraft. On Windows most delays start after the application's `_process` callbacks: in rendering, presentation or the OS. On the M1 a disturbance recurs every 500 ms, also outside flight; direct timing places its start outside the simulation, in macOS event, input or audio work between iterations. On PRIMIS isolated 107–150 ms frames contain one-off main-thread work. Offline analysis, six controlled runs on ANGEL and [direct phase timing](#direct-phase-timing) on ANGEL and PRIMIS; the [investigation plan](../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps) orders the repairs.

## Data

All nine runs used native physics at 240 Hz (`runtime.json` backend `native`). Windows: RTX 3090, Forward+/Vulkan, 1920×1080, uncapped. ANGEL: M1, Mobile/Metal, mirrored external 1920×1080. PRIMIS: UHD 630 container, Compatibility/OpenGL, Automatic graphics, Xwayland 1920×1080. Only the `runway_circuit` phase is used, except where stated. [Tour hardware](2026-11-21-stutter-map.md) · [PRIMIS setup](2026-11-22-linux-uhd630-comparison.md)

The tour driver writes each stream row in its `_process` ([`godtest_driver.gd`](../../../app/debug/godtest_driver.gd), `process_priority` 1000), after the application's other `_process` callbacks. `wall` is the interval between two such callbacks. `engine_delta` is Godot's process delta: the interval between the starts of two main-loop iterations. Ticks per frame are the difference of consecutive `sim_tick` samples. An iteration runs its physics ticks, then `_process`, then rendering and presentation. So:

- *head*(*n*), from iteration start to the stream callback, holds the ticks and the ordinary `_process` work;
- *tail*(*n*), from the callback to the next iteration start, holds deferred calls, rendering, presentation and OS event processing;
- `wall`(*n*) = *tail*(*n*−1) + *head*(*n*) and `engine_delta`(*n*+1) = *head*(*n*) + *tail*(*n*).

## Cost of one tick

With *head* = *c*·ticks + *h*, `wall`(*n*) − `engine_delta`(*n*) = *head*(*n*) − *head*(*n*−1). Regressing it on the change in tick count gives *c* without the rendering tail. Fitting the current and previous tick counts separately gives the two bounds in brackets. Tick share is *c* × 240 per second.

| Host | Aircraft | Circuit FPS | Cost per tick | Bounds | Tick share of main thread |
| --- | --- | ---: | ---: | ---: | ---: |
| Windows | Stik | 174 | 1.01 ms | 0.87–1.15 | 24% |
| Windows | jet | 185 | 1.17 ms | 1.02–1.32 | 28% |
| Windows | Corsair | 182 | 1.28 ms | 1.07–1.49 | 31% |
| ANGEL | Stik | 97 | 0.75 ms | 0.44–1.06 | 18% |
| ANGEL | jet | 79 | 0.94 ms | 0.73–1.15 | 23% |
| ANGEL | Corsair | 74 | 1.06 ms | 0.56–1.54 | 25% |
| PRIMIS | Stik | 50 | 1.30 ms | 1.24–1.35 | 31% |
| PRIMIS | jet | 41 | 1.49 ms | 1.48–1.51 | 36% |
| PRIMIS | Corsair | 41 | 1.93 ms | 1.90–1.95 | 46% |

On the GPU-limited M1 part of each tick overlaps GPU work, so the two bounds differ widely. NK-4 measured 311–426 µs per airborne native tick in a headless trajectory harness without the flight scene ([measured cost](../native-kernel/NK-4/README.md#measured-cost)). Roughly 0.6–0.9 ms per Windows tick is therefore spent outside that path: `stepped` observers, session guards and engine per-step work. The 27 October profile attributed about half of the scripted step to presentation and statistics observers ([VQ-01c](../visual-quality-implementation/VQ-01c/tick-observers-2026-10-27/README.md)). Audio, windsock, profile smoke and ground gear have since moved to frame cadence. A current attribution is still needed.

A plain regression of `wall` on ticks gives about 3 ms per tick, and grouping by the previous interval about 2 ms. Both are biased upward. A long tail raises the next frame's tick count and its `wall` together. An independent review identified this before publication.

## Direct phase timing

The same day [`frame_phases.gd`](../../../app/render/frame_phases.gd) (PT1h-R15-S3, plan step F0) was added to the tour stream. Bracket nodes at the extreme process priorities and Godot's `physics_frame`, `process_frame`, `frame_pre_draw` and `frame_post_draw` signals split each stream interval into eight phases that sum exactly to it. The engine order behind the split was checked against the 4.8-beta2 source. Each aircraft then flew recover, circuit and a 15 s pause once on ANGEL (tour-r4 configuration) and once on PRIMIS (Automatic graphics, as `tour-pauto1`). The sources were the earlier frozen snapshots plus only the probe and its driver hook. Every run was valid and complete with native physics, and every circuit and pause interval split completely.

| Run | Circuit FPS | Median frame | Ticks | Per tick | Ticks' share | Render | `_process` | Other phases | Paused tick | Paused render |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ANGEL Stik | 100 | 9.6 ms | 2 | 0.92 ms | 22% | 5.6 ms | 1.5 ms | 0.6 ms | 0.06 ms | 7.4 ms |
| ANGEL jet | 75 | 12.8 ms | 3 | 1.13 ms | 27% | 7.2 ms | 1.7 ms | 0.6 ms | 0.08 ms | 9.1 ms |
| ANGEL Corsair | 78 | 12.4 ms | 3 | 1.20 ms | 29% | 6.6 ms | 1.8 ms | 0.6 ms | 0.07 ms | 8.1 ms |
| PRIMIS Stik | 50 | 20.0 ms | 5 | 1.35 ms | 32% | 9.5 ms | 2.7 ms | 1.3 ms | 0.05 ms | 19.4 ms |
| PRIMIS jet | 40 | 24.6 ms | 6 | 1.55 ms | 37% | 11.2 ms | 2.9 ms | 1.2 ms | 0.04 ms | 22.4 ms |
| PRIMIS Corsair | 39 | 25.0 ms | 6 | 1.83 ms | 44% | 9.1 ms | 3.3 ms | 1.2 ms | 0.04 ms | 22.3 ms |

*Per tick* is circuit physics time over circuit ticks; *ticks' share* is physics time over wall time. *Render* runs from `frame_pre_draw` to `frame_post_draw`: CPU render recording, acquire, submit, present and fence waits. *`_process`* covers the callbacks before the tour driver. *Paused tick* is the median while the flight menu is open.

- **The tick model holds.** Direct per-tick cost agrees with the [head-difference fit](#cost-of-one-tick) within 0.2 ms on every run. 99% of physics time lies between `physics_frame` and the last `_physics_process` callback; engine per-step work outside those callbacks is negligible. These runs carried one probe; a second observer sharing it adds no callbacks.
- **The cost is the flying step.** A paused tick runs the same callbacks for 0.04–0.08 ms. In flight one tick costs 0.9–1.8 ms, against NK-4's 0.31–0.43 ms for the native step alone in its headless harness. The remainder is callback time not yet attributed in full; the [first attribution](#first-attribution-of-a-flying-tick) follows.
- **On PRIMIS the ticks are a steady load.** It needs 5–6 ticks every frame, 32–44% of wall time, so a slow render frame is followed by more ticks and little slack to recover. Frames above 33.3 ms (166–177 per circuit for the jet and Corsair) exceed the circuit mean by 6.1–6.2 ms of render and 3.2–3.4 ms of physics. One Stik frame of 186 ms was a 145 ms render stall followed by 12 ticks.
- **Slow M1 frames carry slower ticks.** In frames above 16.7 ms a tick averages 1.4–2.4 ms, up from about 1.0 ms. The 500 ms cycle below causes most of them.
- **ANGEL and PRIMIS behave GPU-limited.** A paused frame lasts about as long as a circuit frame (ANGEL 10.4–13.2 ms against 9.6–12.8 ms; PRIMIS 22.8–26.3 ms against 20.0–25.0 ms) although its ticks cost almost nothing. Its render phase absorbs the time instead (ANGEL 7.4–9.1 ms, PRIMIS 19.4–22.4 ms). With vsync off and no frame cap, that phase holds fence, swapchain-acquire and present waits; the tour measured the M1 GPU at 94–96% utilization, and Intel has no utilization reading here. In flight the ticks and `_process` fill part of that wait. Cheaper ticks therefore shorten catch-up spikes on these hosts but do not by themselves raise their mean FPS; on the CPU-limited Windows workstation they do.
- **`_process` callbacks before the driver cost 1.5–1.8 ms per frame on ANGEL and 2.7–3.3 ms on PRIMIS.** This is the second script load after the ticks.

## First attribution of a flying tick

The probe's running totals (`totals()`) and the debug bridge's `eval` measured a headless Corsair flight on the Windows workstation from the current source (`19e9e69dd` plus this work, native backend). A climbing Corsair costs 1.4–1.6 ms per tick there; the circuit's ground proximity changes it.

| Work per accepted tick | Owner | Cost | Pinned |
| --- | --- | ---: | --- |
| Hull-scrape audio observation, `FlightSession.hull_scrape_observation()` called by the crash director | `render/crash/director.gd` calls it | ≈ 150 µs per call, about 130 µs even from its same-tick cache | Caller no; function yes |
| inside it: `mass_properties()` before the reach check that makes the hull airborne-clear | `sim/flight_session.gd` | 85 µs per call (liquid fuel) | yes |
| Statistics sample, `fixed_wing_adapter.gd` `sample()` plus its consumer | `statistics/` | ≈ 70 µs at 30 m; near the ground its wheel compressions cost 80 µs instead of 25 µs | no |

Times are means of 20 repeated calls on a paused flight at 30 m, so caches that only help repeats make them lower bounds. Toggling observers within one climbing flight gave the same order (hull scrape about 135 µs per tick) but drifted with altitude, so those A/Bs are not used. The rewind recorder and flight audio could not be resolved from that drift. The remaining time is the session pre-step, contact resolution and integrator glue in pinned sources. [NK-5a](../native-kernel/NK-5a/README.md) splits a native Corsair tick further and moves its largest pure evaluation, the pre-step's wing wake, into the native stage (tick core 728 → 665 µs). [NK-5b](../native-kernel/NK-5b/README.md) then removes the substep preview's rebuilt source-off response from liquid gas aircraft (`substeps_joint` 78 → 14–25 µs).

**First repair.** The crash director now takes the hull-scrape observation at [presentation cadence](../../../app/render/presentation_cadence.gd) while no hull point penetrates: once per rendered frame, at once on every touching tick and the tick after it. Crash audio accepts the cadence's `since_tick`, so a touchdown after skipped airborne ticks keeps its first grain. A test descends from flight into a sliding touchdown, with a pause while observations wait, and gets the same queued, emitted and dropped grains frame by frame as per-tick observation. With the same flight protocol (two 15 s windows each), the per-tick callback time fell from 1,543 and 1,540 µs to 1,260 and 1,255 µs. The drop exceeds the observation's own cost, so part of it is run-to-run variation. While airborne the observation still runs once per frame in `_process`, so the net saving per frame is about 150 µs × (ticks per frame − 1): about 0.05 ms at the workstation's 180 FPS, 0.3 ms on ANGEL, 0.75 ms on PRIMIS and up to 1.6 ms in a 12-tick catch-up frame. On PRIMIS the same frozen snapshot plus only this change flew the same three phase-timed cases again (`phasesB-20261124`, one run each, all valid and complete with native physics):

| PRIMIS circuit | Per tick | `_process` per frame | Frames > 33.3 ms | 1% low | Mean FPS |
| --- | ---: | ---: | ---: | ---: | ---: |
| Stik (electric) | 1.35 → 1.29 ms | 2.82 → 2.84 ms | 1 → 1 | 32.6 → 34.6 | 50.2 → 50.0 |
| jet | 1.55 → 1.33 ms | 2.95 → 3.07 ms | 166 → 145 | 27.4 → 27.6 | 39.9 → 39.9 |
| Corsair | 1.84 → 1.61 ms | 3.42 → 3.56 ms | 177 → 147 | 27.0 → 27.3 | 39.4 → 39.2 |

The fuel aircraft save 0.22 ms per tick, about 1.2 ms of main-thread time per 6-tick frame after the per-frame observation, and 13–17% of their frames above 33.3 ms. The electric Stik skips the fuel mass computation, so it gains least. Mean FPS stays GPU-bound. ANGEL repeated the same comparison on 25 November (`phasesB-20261124/run2-*`, all valid and complete with native physics; the baseline ran the day before):

| ANGEL circuit | Per tick | `_process` per frame | Mean FPS | 1% low | Frames > 16.7 ms | Frames > 33.3 ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Stik (electric) | 0.92 → 0.91 ms | 1.62 → 1.67 ms | 100.4 → 100.2 | 44.2 → 45.2 | 140 → 143 | 2 → 0 |
| jet | 1.13 → 0.94 ms | 1.90 → 1.87 ms | 75.1 → 82.3 | 31.6 → 39.2 | 1,133 → 485 | 27 → 4 |
| Corsair | 1.20 → 1.08 ms | 1.93 → 2.07 ms | 78.2 → 78.4 | 35.7 → 35.6 | 570 → 530 | 8 → 9 |

The jet gains most because its slow frames were catch-up after the 500 ms disturbance. These are single runs on different days; the fanless Air's thermal state was not recorded, so the jet's FPS gain is an upper bound until repeated. Windows has no phase-timed baseline yet.

## Per-frame script cost on Windows

On 25 November a rendered jet flight on the Windows workstation (current source, native physics, a fresh profile, which chose Compatibility at about 106 FPS) was split by the probe and timed per call through the bridge's `eval`. The frame held about 2.2 ms of physics for two ticks, 2.8 ms of render (2.1 ms viewport render CPU, GPU 1.4 ms) and the `_process` callbacks. Twenty nodes process every frame; their own `_process`, timed as ten consecutive calls, costs:

| Per frame | Cost | Pinned |
| --- | ---: | --- |
| `Main._process` | ≈ 800 µs: `World.update` 214 (clouds 104, flow 50, adapt 39), `_render_pose` 165, `_update_smoke` 51, presentation observers 33 | `main.gd` by the companion manifest; `airplane.gd` by the fleet manifests |
| `FlightAudio._process` | 400–750 µs, also with sound muted: `snapshot()` 114, soundscape 167, mechanical 82 | no |
| `GroundGearMotion` (retractable gear) | 159 µs, 89 of it `Retraction.apply` re-posing an unchanged gear | `retractable_model.gd` yes; caller no |
| Hull-scrape observation (after the first repair) | ≈ 150 µs once per frame | caller no |
| Sun glare, birds, windsock shadow | 45, 23, 17 µs | no |

The overlay's number refresh costs about 340 µs whenever it updates. The sun skyline builds once per pilot position within about 10 s and then costs nothing. Repeated calls can hit caches the first call of a frame misses, so these are lower bounds.

Two further repairs followed. The crash director now observes the hull only on touching ticks, the tick after, and the cadence's 0.1 s bound; the per-frame observation is gone, so in flight it runs about 10 times per second instead of once per frame. `GroundGearMotion` calls `Retraction.apply` only when the extension or rig changes. On other frames it restores the few posed nodes it rewrites (spin, steering, compression) through the same setters and values, so every node stays bit-identical to per-frame posing, including the Corsair's quarter-turned retracted wheels; its frame cost fell from 159 to 92 µs. Both are presentation-only and keep their tests; a phase-timed Windows tour remains the acceptance measurement.

## What a slow frame contains

Godot gives the next frame more ticks when an iteration runs long. A delay of *d* ms therefore adds about *d*·0.24·*c* ms of ticks, and those ticks add more again. The total is *d*/(1 − 0.24·*c*): 1.3–1.45× on Windows and 1.45–1.85× on PRIMIS. Previous intervals predict the tick count with a correlation of 0.70–0.78 on these hosts.

Using the fitted *c*, each slow frame's excess over the circuit median splits into the previous iteration's non-tick time and tail, the extra ticks, and a remainder in its own non-tick head:

| Host | Frames | Count | Median wall | Previous tail and non-tick | Extra ticks | Own non-tick head |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Windows (3 aircraft) | > 9 ms | 931–2,118 | 10.0–10.5 ms | 3.5–4.2 ms | 1.1–2.3 ms | 0.1–0.3 ms |
| Windows (3 aircraft) | > 16.7 ms | 4–44 | 18.3–19.8 ms | 9.6–10.1 ms | 3.4 ms | 0.4–1.9 ms |
| PRIMIS jet, Corsair | > 30 ms | 585–734 | 31.9–32.2 ms | 4.5–4.7 ms | 3.1 ms | 0.4–0.5 ms |
| PRIMIS (3 aircraft) | 107–150 ms | 1–2 each | 107–150 ms | 27–31 ms | 9–11 ms | 45–88 ms |

GPU and render-CPU readings, draw calls and resource counts do not change in ordinary slow frames. GPU timings are last readings of unverified freshness. The Windows GPU readings stay near 1.6 ms, so its tail delays are not GPU load; presentation, graphics-driver work, deferred calls and OS scheduling remain. The PRIMIS outliers are one-off stalls inside the frame and are not attributed.

## Opening seconds of flight

Each Windows `recover` phase opens with a burst of 20–87 ms intervals between 0.46 and 1.65 s after the phase starts (sim ticks 121–405). In the Stik and jet the burst begins in the interval where video memory grows by 7.2–7.3 MB. The burst then continues as catch-up: 6–12 ticks per frame with GPU readings below 1 ms. The Stik reached the 12-step cap once (87 ms). Every launch used a fresh profile; the state of Godot's shader and pipeline caches was not recorded. This is the same window as the PRIMIS opening freeze near tick 391 ([cache experiment](2026-11-22-intel-green-club-screen.md)). What allocates that memory is not identified.

## The M1 half-second disturbance

On 24 November we repeated the jet circuit six times on ANGEL from the same frozen tour source (`tour-r4` snapshot), engine, native library and mirrored 1080p display. Each case ran startup, selection, loading, recover, circuit and shutdown. The debug bridge stayed loaded in every run. Arms: the tour's frame watcher polling every 500 ms; watcher off; watcher and both CPU/GPU hardware samplers off. All runs used the native backend and completed with valid data.

| Run | Watcher | Samplers | Circuit FPS | p99 | > 16.7 ms | > 33.3 ms | Slow-frame concentration at 500 ms | Per-cycle maximum excess |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | on | on | 74.5 | 28.5 ms | 1,170 | 48 | 0.97 | 12.8 ms |
| 2 | off | on | 73.9 | 30.0 ms | 1,246 | 61 | 0.95 | 13.4 ms |
| 3 | on | on | 73.9 | 29.5 ms | 1,188 | 64 | 0.99 | 12.8 ms |
| 4 | off | on | 74.3 | 29.4 ms | 1,217 | 47 | 0.97 | 12.9 ms |
| 5 | off | off | 74.1 | 29.3 ms | 1,245 | 58 | 0.98 | 12.6 ms |
| 6 | off | off | 74.0 | 30.4 ms | 1,260 | 73 | 0.98 | 13.9 ms |

**Neither the frame watcher nor the hardware samplers cause the disturbance.** In every run the per-cycle maximum falls mainly in the frame's own head: 7.7–8.2 ms of non-tick `_process` or physics-callback work before the driver's callback (90th percentile 13–16 ms). Another 4.9–5.5 ms falls in the previous tail. The period fits 500.00 ms to within ±0.25 ms over 156 s. A timer that accumulates `delta` and resets to zero would add about half a frame (≈ 6 ms) per cycle and lose this alignment within seconds. That rules out the 0.5 s `ControllerService` refresh. The phase within the 120-tick cycle differs between runs, so the schedule is not tied to absolute simulation ticks.

The retained tour stream shows the same jumps without physics: about 2 per second of 7–10 ms in the paused flight and in the Settings and Controls screens. The source therefore also runs without physics ticks, flight audio or the flight-only observers. The same test finds no 500 ms or 120-tick pattern on Windows (concentration 0.03–0.11, per-cycle head jump 1.0 ms).

Direct phase timing corrects the head/tail attribution above. Folding each [phase-timed](#direct-phase-timing) run at 500 ms, the frames in the slowest 30 ms of each cycle exceed frames away from it by these mean amounts per frame. The other phases add 0.2 ms or less:

| ANGEL run | Mean excess per frame | Between iterations | `_process` | Physics ticks | Render |
| --- | ---: | ---: | ---: | ---: | ---: |
| Circuit, 3 aircraft | 5.8–9.0 ms | +1.7–2.1 ms | +1.7–2.2 ms | +2.5–4.7 ms | −0.7 to +0.2 ms |
| Pause, 3 aircraft | 2.1–4.6 ms | +1.3–1.6 ms | +0.4–1.7 ms | +0.2–0.8 ms | −0.9 to +0.9 ms |

**Between iterations** rises by a similar amount in every run, flight and pause; on macOS that phase covers run-loop event dispatch, input flush, audio update and the frame limiter. `_process` rises in the same frames. In flight the delay then returns as catch-up ticks. Ticks inside these frames also run slower: while paused, in most cycles one tick that normally costs 0.06 ms takes 2.5–3.4 ms longer (1.2–1.5 such ticks per second, phase concentration 0.91–0.98); averaged over the window's frames that is the +0.2–0.8 ms above. Slow work spread over three unrelated phases points to the main thread being stalled or slowed, not to one script callback. ANGEL has only the Command Line Tools, so no Instruments trace was possible. `sample` or a Time Profiler from a full Xcode install across a paused flight is the next step.

In these six runs one tick adds 0.71–0.78 ms by the head-difference fit, within the tour's bounds for the jet (0.73–1.15 ms).

| A/B stream on ANGEL (`~/OpenRC-m1-work/stutter-ab-20261124/`) | SHA-256 | Frames |
| --- | --- | ---: |
| `watch-1` | `bf7e4f4cfac053022a03a0706202e20cfdc96d59273b01876ddb7e6a4b84f99e` | 13,958 |
| `nowatch-1` | `d4245da7b7c04e72666975d51a4b8f04bb8512b81755c88af4899aa098195119` | 13,715 |
| `watch-2` | `d75b791bbd75a7fcb1330024406ef2a7940c1388dc8dc9c2893906ed54c5801a` | 13,800 |
| `nowatch-2` | `c51203e7c671b0332bc641fc283b28106ee503c95629b6ed1e3acb464ccfd811` | 13,846 |
| `nomon-1` | `86b753b2fcf3b2b779410c8e42b53f67d0fb605e7b8c18aad0fb4329e24cf9f0` | 13,809 |
| `nomon-2` | `6dee81954cf3df2bd0f6f00096f43e8d1821de6dc2a41e4c6af4ad93a8282286` | 13,817 |

## Limits

These are single runs per aircraft from tours that predate the Club Field restoration (`2014cafbb`). Callback intervals are not presented frames. The model assumes one tick costs the same within a circuit; ground contact, flaps and companions change it. `engine_delta` is assumed to be the raw iteration interval (`physics_jitter_fix` is 0 in [`project.godot`](../../../app/project.godot)). Frames above 60 ms are excluded from the cost fit. PRIMIS is a container on a shared node.

## Reproduce

Streams are verified by `tools/godtest/analysis.py` `validate_stream`. Read the circuit window from the `phase_start`/`phase_end` events in `events.jsonl`. For each frame take `wall_usec`, `engine_delta_s` and ticks(*n*) = `sim_tick`(*n*) − `sim_tick`(*n*−1). Exclude intervals above 60 ms. Fit `wall` − `engine_delta` on ticks(*n*) − ticks(*n*−1) by least squares, and separately on ticks(*n*) and ticks(*n*−1). For the split, estimate *h*(*n*−1) + *tail*(*n*−1) as `engine_delta`(*n*) − *c*·ticks(*n*−1). Subtract its circuit median, and subtract *c* times the excess ticks over the median tick count; the remainder is the frame's own non-tick head.

| Stream | SHA-256 | Frames |
| --- | --- | ---: |
| Windows `tour-20261121-r1/001` Stik | `ca95d1bf68f9d7e0c1fed346a3400bd0473d8944f167463f1a481b168eeac15b` | 24,945 |
| Windows `tour-20261121-r1/002` jet | `aea79d4cba7f4e7a99c26979ed580a5a756abb1663d755a08f30620cf4615c65` | 45,495 |
| Windows `tour-20261121-r1-retry/003` Corsair | `cffc096020d230f320ad4b697a685343af964362e13748664c9e12111d2f3282` | 43,427 |
| ANGEL `tour-r4/001` Stik | `e89dc0fa3e5e8fbd1a12e301fd54e8bca85f418a23e87d5dbf720716f136dacd` | 11,692 |
| ANGEL `tour-r4/002` jet | `439403d68083f7fa305d7db794fe74394304780051a73dec01db7c071ebb0474` | 16,443 |
| ANGEL `tour-r4/003` Corsair | `db720232793e16f0c44641beb9f74469412790567d7869d95e43ee4259b925c4` | 14,886 |
| PRIMIS `tour-pauto1/001` Stik | `ff925a9430ca149a582d305dbdf1d936d234d6ffb14f9d9164e37a8030475230` | 6,893 |
| PRIMIS `tour-pauto1/002` jet | `f0c14f7300eb86df8e49aec3cabc0de206602ead886576ded02d7198257bd120` | 9,409 |
| PRIMIS `tour-pauto1/003` Corsair | `69dce97cef3dcb2a541eeb04d7b6807cca39bf5bbf993a8a1c36edf7c7c32432` | 8,619 |

Phase-timed runs (`~/OpenRC-m1-work/phases-20261124/` on ANGEL, `phases-20261124/` beside the PRIMIS tour workspace) are summarized with `python tools/godtest/frame_phases.py RUN_DIR --phase runway_circuit`.

| Phase-timed stream | SHA-256 | Frames |
| --- | --- | ---: |
| ANGEL `run-stik` | `67d41fb483d1253401958a781e07104b09729334759bb24389a374cd94a94e68` | 11,656 |
| ANGEL `run-jet` | `131f3c6dde186737a540bc226a6181f7f2dc2f92acdc536a95b8efdd76e34940` | 15,412 |
| ANGEL `run-corsair` | `1d31625d18caf32074907fce92d922e9344dcf75f8257eafb4eb751657d05853` | 15,271 |
| PRIMIS `run-stik` | `cf0fb966506dad0b73bfaa8ecdaacdeeea5e849dfe2f2df1d5cdf0aa8ce22f62` | 6,526 |
| PRIMIS `run-jet` | `ee709a79abe5c3606f6bbb98f42bee4bedd476e30362cf2a0ae743bddcb49c71` | 8,981 |
| PRIMIS `run-corsair` | `38b103c9f236130cfe80e81aa844d7190ec424a8a91c036eb87b16b5d4cfbff7` | 8,276 |
| PRIMIS `phasesB-20261124/run-stik` | `d12c94025629ec7dd5445658a2a6e76d09fa4fd64c065586ddad5dc06908a8ce` | 6,503 |
| PRIMIS `phasesB-20261124/run-jet` | `a0893a54605d00fc2b1ba45c2e7956f1154868491f9d3e94458dde7baf8b924f` | 8,985 |
| PRIMIS `phasesB-20261124/run-corsair` | `4504ed049a1773b853891639197a2c7e51b831d27b8cd3ebf754816364a032b8` | 8,270 |
| ANGEL `phasesB-20261124/run2-stik` | `685702de485d4399a71794387316d7f0bec07468cd9f899f14c344138c489b27` | 11,667 |
| ANGEL `phasesB-20261124/run2-jet` | `1822c8f2aa6c843445092c66f9c871beb1b4ed4b831d4cbb220c71b763820b59` | 16,857 |
| ANGEL `phasesB-20261124/run2-corsair` | `ae8bfdcf1096b4dda283608d96d47544f4624e00a384cc064d390752a2685b36` | 15,326 |
