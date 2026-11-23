# Cost models and mathematical bounds

Every number here is either current-source arithmetic or an explicitly invented illustration. None is a new FPS measurement. Reproduce the calculations with [`cost_models.py`](../../../research/performance/graphics-audit-2026-11-21/cost_models.py); [cost-models.json](cost-models.json) retains the output at the audited SHA. Source mechanisms are linked from the rendering and runtime reports.

## Fixed 240 Hz constrains the CPU budget

The [project clock configuration](https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/project.godot#L47-L56) sets 240 ticks/s and at most 12 physics steps per engine frame. Thus one tick advances 4.1667 ms and the maximum simulated time advanced in a frame is 50 ms. With ordinary time scale, no pause and no fixed-FPS test override, a sustained engine cadence F imposes:

$$
\frac{\text{simulated time}}{\text{wall time}}\leq\min\left(1,\frac{12F}{240}\right).
$$

| Sustained engine frames/s | Cap-derived maximum progress | Interpretation |
| ---: | ---: | --- |
| 10 | 0.50× | Real time impossible under the cap |
| 15 | 0.75× | Real time impossible under the cap |
| 20 | 1.00× | The cap permits real time; CPU work still may not |
| 60 | 1.00× | Four ordinary fixed ticks per frame on average |
| 120 | 1.00× | Two ordinary fixed ticks per frame on average |

The formula is a ceiling, not a prediction that the simulator reaches it. An isolated long frame is not enough to establish long-run slowdown. More catch-up steps may increase the same frame's CPU pressure, so blindly increasing the cap does not solve an expensive tick. Lowering 240 Hz would change the simulator's numerical and input contract. [Godot's Engine documentation](https://docs.godotengine.org/en/stable/classes/class_engine.html#class-engine-property-max-physics-steps-per-frame) describes the general relationship; exact application settings supply the arithmetic.

At 60 frames/s, four ticks each costing an illustrative 2 ms leave only about 8.67 ms of a 16.67 ms main-thread budget for other work. Four 4 ms ticks leave about 0.67 ms. These invented examples must use **complete callback cost**, including synchronous observers, not the smoothed `step_usec` subsection. GPU overlap means CPU and GPU durations cannot always be added as if they were a serial stopwatch.

For three companions plus the player, the ordinary fleet advances 960 session ticks per simulated second. In the simple four-stage RK4 path this entails 3,840 stage evaluations/s across all four sessions, before extra event-location/substep work. The planner already runs less often. That count motivates profiling and per-agent native admission; it is not a measured cost or permission to batch dependent stages.

## Native speedup follows the measured bottleneck

If a measured serial CPU fraction p is accelerated by a factor s while the rest remains unchanged, the ideal serial speedup is:

$$
S=\frac{1}{(1-p)+p/s}.
$$

| Illustrative affected CPU fraction | Component becomes twice as fast | Ideal total serial speedup |
| ---: | ---: | ---: |
| 20% | 2× | 1.111× |
| 40% | 2× | 1.250× |
| 60% | 2× | 1.429× |

These values are conditional illustrations, not estimated gains for OpenRC. The CPU-only artifact's 1.77×/2.65× ratios cannot be substituted as full-frame speedups. In a pipelined renderer, steady frame duration is constrained by the slowest relevant CPU, GPU and pacing stage. A CPU optimization may improve headroom or rare catch-up frames without increasing a GPU-bound steady FPS result. Measure both consequences.

## Nitro source identity checks multiply small work

The two current source files total 124,444 bytes: 21,400 for `nitro_dynamics.gd` and 103,044 for `vehicle_dynamics.gd`. At 240 successful guard calls/s, two full-file reads imply **480 logical opens/s**, **29,866,560 logical bytes/s**, or **28.48 MiB/s**. The path also allocates/compares buffers and hashes a small composite identity. See [N1](runtime-native.md#n1-nitro-vehicle-performs-artifact-reads-on-every-240-hz-callback).

This is not physical storage bandwidth: OS caching, PCK/remapped script representation, failures and lifecycle alter the actual cost. A packaged immutable identity could avoid repeated work only with an explicit proof that it preserves live-mutation and replay refusal semantics. A path/size/mtime cache is not that proof.

## Resolution and cloud storage are quadratic, time is not automatically so

For output width W, height H and uniform internal scale r, nominal internal pixels are approximately WHr², subject to engine rounding and reconstruction details. A half-width/half-height pass uses one quarter of the pixels; scale 0.75 uses 56.25%. UI, geometry, shadows, reconstruction, fixed shader overhead and additional viewports do not all scale identically.

| Output | Pixels relative to 1920×1080 |
| --- | ---: |
| 1920×1080 | 1.000× |
| 2560×1440 | 1.778× |
| 2560×1600 | 1.975× |
| 3840×2160 | 4.000× |

The 2560×1600 row is an arithmetic example, not an assertion about every Mac's panel. Apple Silicon Retina validation uses the actual native panel/drawable and the effective internal scale. A model fitted to 1080p external/mirrored output is not native-panel qualification. [Godot's scaling documentation](https://docs.godotengine.org/en/stable/tutorials/3d/resolution_scaling.html) provides the general pixel-cost context.

One ready 2048×2048 cloud tile in RGH has two half-float channels, four logical bytes/texel: **16 MiB** of base texels. Four distinct ready tiles therefore total **64 MiB**. [Image format documentation](https://docs.godotengine.org/en/stable/classes/class_image.html#enum-image-format) identifies RGH as RG16F. The cache capacity includes pending/failed entries, sky and ground can share a seed, and the default may need only one tile. This is not measured VRAM/RSS, nor a claim four allocations always exist. It excludes render targets, readback/conversion buffers, uploads, alignment, driver formats and any mip overhead. A unified-memory host requires ownership-aware accounting rather than adding CPU and GPU counters indiscriminately.

## Diagnostic cadence can contaminate the series being measured

At steady retained process-sample rate F, a 512-frame chunk is completed about every 512/F seconds:

| Retained samples/s | Chunk cadence |
| ---: | ---: |
| 30 | 17.067 s |
| 60 | 8.533 s |
| 120 | 4.267 s |
| 144 | 3.556 s |

Header/trailer writes and the final partial chunk add other writes. Native presentation cadence can differ from this process rate. Align write timing to subsequent measured intervals before attributing a hitch; current aggregate write totals alone cannot align it. The 500,000-frame default cap covers about **57.87 minutes at 144 samples/s**, so an uninterrupted one-hour run at that rate requires 518,400 samples or will be explicitly incomplete. Two float64 series at the cap contain 7.63 MiB of values, before capacity and other allocations. Neither the sidecar-byte cap nor this calculation is a process memory measurement.

## Smoothed meters and percentiles can conceal severe isolated stalls

The runtime meter uses smoothing weight 0.05. An illustrative stable 500 µs value followed by one 4,000 µs sample becomes only **675 µs** in the meter. Its excess has a half-life of about **13.51 samples**. Work after the meter stops is invisible regardless of smoothing. Retain unsmoothed full-callback distributions and event correlation.

A second invented series has 5,999 intervals of 16.667 ms and one 300 ms interval. Both nearest-rank p95 and p99 remain 16.667 ms, while maximum is 300 ms. Consequently a report limited to averages/p95/p99 can miss a conspicuous rare freeze. Include maximum, counts above named absolute and target-relative thresholds, duration of contiguous slow episodes, route phase, first-control-ready time and sim/wall ratio. Distinguish one event from many overlapping threshold counts; preserve the entire bounded series and dropped/incomplete state.

## What the equations rule out

The arithmetic does not justify a promised FPS increase, a universal Mobile-versus-Compatibility ranking, exact plant-count reduction, fourfold total sky speedup, or adding historical percentage improvements. It does justify a measurement order: verify identity and completeness, locate the constrained stage, measure a matched bounded change, then test whether the end-to-end and tail results exceed paired variation.
