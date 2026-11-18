# VQ-01c: shared GPU timing ownership and sample status (M0)

2026-11-17 · Implements the first measurement repair from the [graphics technology audit](https://github.com/bultodepapas/OpenRCsimulator/tree/audit/graphics-performance-technologies-2026-11-15/docs/research/graphics-performance-2026-11-15) (branch `audit/graphics-performance-technologies-2026-11-15`, findings F02/F03, milestone M0). Base: `main` at `035c43eae` plus the working-tree status change below. Engine: official `4.8.beta2.official.cafc17a19`.

## Changes

| Finding | Change | Checks |
| --- | --- | --- |
| F02: `FrameDiagnostics` and the debug-bridge `RenderProbe` wrote the same per-viewport measurement flag, so the first to stop disabled the other; the bridge never released its interest on exit. | [`render_timing_lease.gd`](../../../../../app/render/render_timing_lease.gd) owns the flag with opaque leases (first lease enables, last disables, freed viewports retired without writing their RID). `frame_diagnostics.gd`, `render_probe.gd` (root and SubViewports, departed ones released) and `debug_bridge.gd` `_exit_tree` use it. | `test_render_timing_lease.gd` 31/31 headless with a recording fake setter. Mutations caught on disposable copies: release always disabling (5 failures); diagnostics `stop()` skipping release (3 failures). `test_frame_diagnostics`, `test_render_probe`, `test_debug_bridge` pass. |
| F03: positive stock GPU polls were reported as measured samples. | Diagnostics metadata v2: per-sample integer `render_gpu_status` with a published codebook ([format](../../../../../research/performance/README.md)). `frame_diagnose.py` and `perfetto_export.py` label positive polls `positive_freshness_unverified`, count codes and fail closed on unknown/contradictory codes or a v2 report without the column; Perfetto omits the status track whenever it omits the GPU track. v1 reports stay readable. | `test_frame_diagnostics.gd` 32/32 headless and native; `test_frame_diagnose.py` 35/35; `test_perfetto_export.py` 31 pass (1 engine-gated skip). |

## Native screen

One host: Windows 11 10.0.26100, Ryzen 9 5900X, RTX 3090 (OpenGL 3.3, driver 617.42), Standard profile (`gl_compatibility`), Native reconstruction, 1920×1080 windowed, VSync on (120 Hz display), `--scripted --warmup=5 --t=15 --frame-diagnostics`, audio Dummy. Both the v2 report and the v3 stream (`--frametimes-stream`) recorded and diagnosed valid, no engine errors.

| Metric (1,800 frames) | p50 | p95 | max |
| --- | --- | --- | --- |
| Wall frame interval | 8.33 ms | 8.46 ms | 18.20 ms |
| Root GPU poll (freshness unverified) | 1.64 ms | 1.84 ms | 16.43 ms |
| Root render CPU | 1.44 ms | 2.06 ms | 15.97 ms |
| Observer poll cost | 21 µs | 31 µs | 54 µs |

All 1,800 samples carried status 2. Raw reports stayed outside the repository.

### Uncapped profile and fixed-reconstruction screen (M1 input)

Same host, 1920×1080 windowed, `--disable-vsync`, `--scripted --warmup=5 --t=20 --frame-diagnostics`, one run per row. High rows use `--rendering-method forward_plus` (Vulkan 1.4) with `OPENRC_RECONSTRUCTION`; every row reported `render_progress: observed`.

| Row | Frames | Wall p50 / p95 / max | Root GPU poll p50 / p95 |
| --- | --- | --- | --- |
| Standard, Native, MSAA 2× | 9,095 | 2.10 / 2.96 / 17.2 ms | 1.24 / 2.32 ms |
| High, Native, MSAA 2× | 11,990 | 1.56 / 2.25 / 12.2 ms | 1.08 / 1.51 ms |
| High, FSR2 85% (1632×918 nominal) | 8,764 | 2.22 / 3.26 / 6.4 ms | 1.24 / 1.55 ms |
| High, FSR2 Quality (1280×720 nominal) | 8,898 | 2.25 / 3.10 / 6.8 ms | 1.04 / 1.47 ms |

On this GPU at 1080p, FSR2 is slower than Native: the fixed scaler cost exceeds the pixel saving. Frames above 5–6 ms were rare (2–9 per run), isolated and not GPU-attributed. A physics-route control (`--scene_detail=high`, live input without a radio, so the simulation stayed paused) gave Standard 2.06 / 3.24 / 12.9 ms over 13,447 drawable frames. Both High physics-route attempts reported `window_not_drawable` (Windows minimized state) for 4,097/4,097 and 2,175/9,076 samples; the diagnoser rejected them, and they are not High results. Vulkan runs print `OpVectorExtractDynamic is not supported yet.` after collection ends (8×; 28× with FSR2); it does not overlap the samples and is not investigated here.

## Decision and limits

M0 closes **proceed, static-only** for this row: the scripted 1080p workload is VSync-limited with the root GPU poll near 20% of the frame, so there is no pixel-sensitive GPU bottleneck for dynamic resolution to address, and stock timing has no completed-frame identity to drive it. The observer cost is well inside the audit's proposed 0.2 ms p95 screening ceiling.

M1 on this row has no fixed-provider correction to make: Native is the fastest option and FSR2 is a quality/AA choice, not a speed choice, on a GPU this strong. A useful M1 screen needs a GPU where High Native misses the 1080p budget.

One short scripted run on one high-end GPU is not active flight, pilot evidence, a Forward+ High result, or a weaker-GPU row. DRS remains ineligible until a named target shows a pixel-bound miss and an associated GPU sample exists. Fixed-provider (M1) and Reflex (M3) work need the High/native NVIDIA builds and, for Reflex, the F6 optical rig.
