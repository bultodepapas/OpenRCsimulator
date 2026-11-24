# Where slow flight frames come from

On 24 November 2026 we decomposed every circuit frame in nine retained three-aircraft tours: Windows and ANGEL from 21 November, and PRIMIS with Automatic graphics. A delay in one frame returns as extra 240 Hz physics ticks in the next, at 0.75–1.9 ms of main-thread time per tick depending on host and aircraft. On Windows most delays start after the application's `_process` callbacks: in rendering, presentation or the OS. On the M1 about 8 ms of script-side work recurs every 500 ms, also outside flight. On PRIMIS isolated 107–150 ms frames contain one-off main-thread work. Offline analysis plus six controlled runs on ANGEL; the [investigation plan](../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps) orders the repairs.

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

The retained tour stream shows the same jumps without physics: about 2 per second of 7–10 ms in the paused flight and in the Settings and Controls screens. The source therefore also runs without physics ticks, flight audio or the flight-only observers. The same test finds no 500 ms or 120-tick pattern on Windows (concentration 0.03–0.11, per-cycle head jump 1.0 ms). A profile of a paused flight on ANGEL is the next step.

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
