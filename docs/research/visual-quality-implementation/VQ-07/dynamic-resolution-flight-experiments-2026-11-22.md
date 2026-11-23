# Dynamic resolution from the GPU bench to flight

VQ-07d · 2026-11-22 · Decision and experiment design for the production flight path. The hardware screens use the same synthetic pixel shader, individually chosen loads, VSync off and a 240 FPS process cap. Compare modes within a host and load. The paired scores below are callback measurements. [RTX 3090](dynamic-resolution-rtx3090-2026-11-22.md) · [UHD 630](dynamic-resolution-primis-2026-11-22.md) · [M1 Retina](dynamic-resolution-angela-2026-11-22.md)

| Screen | Target | Fixed 100% | Adaptive | Late callbacks, fixed → adaptive | Fixed 85% |
| --- | ---: | ---: | ---: | ---: | ---: |
| RTX 3090 · 4K | 120 | 115.46 FPS | 147.82 FPS | 33.0% → 4.9% | 156.20 FPS, zero late |
| UHD 630 · 1080p | 60 | 48.95 FPS | 64.20 FPS | 100% → 8.9% | 65.13 FPS, zero late |
| M1 · 2560×1600 | 60 | 50.36 FPS | 63.22 FPS | 100% → 18.6% | 67.13 FPS, zero late |

An 85% linear scale shades 72.25% of the full pixel count. The measured median GPU cost dropped by about 28%, 25% and 25% in the three fixed comparisons. That identifies a pixel-sensitive test load. Real flight adds costs such as geometry, shadows, simulation and presentation. The better fixed result during constant stress sets the comparison bar. The adaptive benefit must earn its place through more readable pixels during quiet flight or fewer late frames across variable load. The 30 FPS pressure cases fell to 85% after about six seconds on both integrated GPUs. The 30 FPS headroom controls stayed at full scale.

## What to borrow from other engines

- Epic separates GPU budget, headroom, history and minimum update period. Its fast over-budget response is an experiment candidate for sustained bursts. OpenRC should compare it against the existing controller using completed GPU samples and account for buffer reallocation and visible transitions. [Unreal dynamic resolution](https://dev.epicgames.com/documentation/en-us/unreal-engine/dynamic-resolution-in-unreal-engine)
- Unity exposes distinct CPU and GPU timing and associates scale with frame timing. Keep the configured scalar, actual completed 3D extent, CPU/process callbacks and presentation evidence separate. [Unity FrameTiming](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/FrameTiming.html)
- Godot scales the 3D buffer independently of the output UI and reallocates RD scene buffers when the scale changes. Measure the transition tails and retained allocations before reducing dwell. Keep the HUD at output resolution. [Godot 3D resolution scaling](https://docs.godotengine.org/en/stable/tutorials/3d/resolution_scaling.html) · [Godot rendering architecture](https://docs.godotengine.org/en/stable/contributing/development/core_and_modules/internal_rendering_architecture.html)
- Apple GPU stages can overlap. Use concurrent GPU captures for attribution and collect ordinary runtime pacing separately. [Apple GPU performance](https://developer.apple.com/documentation/xcode/optimizing-gpu-performance)

## Comparable flight experiments

Freeze the scene, source, engine, native evaluator, aircraft, route, input, camera, display and graphics. Start with the stock Ugly Stik and the `recover` and `runway_circuit` phases. Use at least three interleaved repeats of the decisive modes. Pair frames and flight sections by recorded route landmarks and simulation ticks, and qualify geometric equivalence before scoring a whole-flight comparison. Keep loading and shader-cold work visible as separate phases. [GOD TEST performance tour](../../../../tools/godtest/PERFORMANCE_TOUR.md)

| Experiment | Method | Decision |
| --- | --- | --- |
| E1 · Pixel sensitivity | Measure fixed 100%, 85% and 75% across the same quiet, high-terrain and approach sections. Record completed GPU time, process p95/p99, target misses and simulation seconds per wall second. | Select the best readable fixed comparison. Keep the configuration fixed if fewer pixels fail to improve the pressure section. |
| E2 · Adaptation and burst length | Compare the best fixed mode and adaptive on the same sequences. Use measured load increases of roughly 0.5, 2, 5 and 12 s in the synthetic probe, then compare analogous camera changes and field passes. Measure missed callbacks before/after confirmation, scale changes per minute, worst transition and time at each observed size. | Evaluate a faster downstep only if sustained GPU pressure repeatedly defeats the current dwell. Keep upsteps conservative and compare against the best fixed mode with the same readability. |
| E3 · Pacing and CPU controls | Repeat the quiet route at equal VSync/cap with low GPU load, then on a CPU-heavy route with weak fixed-scale response. Compare with the uncapped session separately. Validate a 30/60/120 target against the effective cap and the display in the relevant row. | Hold scale with headroom, a frame cap or CPU pressure. Use presentation measurements where supported and label callback measurements with their scope. |
| E4 · Readability and flight tempo | Review identical moving views at each rung. Score orientation and flare cues, silhouette shimmer, propeller and HUD legibility. Match the trajectory and simulation at 240 Hz and check sustained and one-second simulation/wall pace. | Derive the lowest readable configuration-specific rung. Require the existing 60 FPS screen limits of p95 ≤18 ms, p99 ≤25 ms and simulation/wall 0.99–1.01 when claiming that target. |
| E5 · Lifecycle and packaged gate | Run pause, settings preview, focus/visibility changes, resize, Home/flight, invalid samples, provider change and an Off switch on actual packages. Compare timing-observer overhead, GPU memory after repeated steps and restored settings on relaunch. | Admit only configurations with bounded transition and memory cost, fresh feedback, reliable fixed restoration and preserved user settings. |

Run the first native comparisons at 1080p and 4K on the RTX 3090, 2560×1600 Retina on Angela, and 1080p on Primis. Primis currently recommends Compatibility/OpenGL and a 75% fixed scale. That configuration has unavailable feedback and no adaptive range at its saved ceiling. Compare Mobile/Vulkan as a distinct candidate with the same readable workload and within Primis's available memory. On Angela compare the product reconstruction selection separately, including MetalFX Spatial when available. Keep synthetic and product measurements associated with their actual provider.

### E2 pulse screen on Angela

On the M1 at 2560×1600, Mobile/Metal, the controlled shader switched between 1 and 56 iterations with a 60 FPS target. Each pulse had a light gap before the next pulse. The 5 s pulse had a 13 s gap afterward so the controller could restore its ceiling before the sustained load.

| Pressure interval | Observed adaptive behavior | Late callbacks, adaptive | Late callbacks, fixed 85% |
| --- | --- | ---: | ---: |
| 0.5 s | Full throughout | 25 / 27 | 1 / 36 |
| 2 s | Full throughout | 105 / 106 | 1 / 142 |
| 5 s | 85% confirmed at 3.92 s, full again 10.93 s into the gap | 204 / 283 | 1 / 355 |
| 18 s | 85% confirmed at 4.30 s, full again 10.44 s into recovery | 224 / 1197 | 1 / 1274 |

The 5 s case spent about 1.1 s at the lower scale before the pulse ended and another 10.9 s there in the light gap. Fixed 85% was considerably steadier in this sequence and spent every gap at the lower scale. Score that tradeoff in flight. Keep the current dwell as the control. Compare a shorter fast-down path for persistent GPU-only misses and a recovery rule that estimates the next rung's cost from fixed-scale data. Adopt either change only after measuring transition tails, useful time at higher scale and aircraft readability. The display was restored after both runs. Receipts are under `U:/OpenRC-drs-godtest-flight-20261122/mac-bursts`.

## Rollout decision

The [current first-run policy](../../../plans/dynamic-resolution.md#phase-3--implement-the-controller-and-player-controls-m2) applies a conservative low-end default when the viewport supports completed GPU timing. Native flight and package evidence are still open. Qualification covers the GPU, driver, renderer, provider, display and fixed ceiling, with observed GPU pressure and measured fixed-scale response. A GPU name supplies a starting hypothesis. Preserve manual Off, manual targets and the saved fixed ceiling. Treat unavailable timing, mismatched targets and an unreadable floor as fixed cases. Recheck changed renderer, driver and package identities before qualifying further rows.

The first-run smoke used the same patched engines on Primis and Angela with a
small 3D scene and no experimental argument. Primis Mobile/Vulkan on the UHD 630
selected 30 FPS at an 85% ceiling on a 1366×768 virtual output. The controller
received a completed 1161×652 frame at that ceiling. The Compatibility/OpenGL
control held a fixed 75%. Angela Mobile/Metal on the M1 detected MetalFX Spatial
and kept it at its fixed Quality scale with a 2560×1600 Retina viewport. This
smoke verifies selection and initial GPU feedback. Loaded-flight transitions and
pilot readability remain open.

A matched synthetic load on the same Primis output exercised the adjusted floor
without the flag. With 270 shader iterations and an 18 s heavy phase, the
adaptive 85% ceiling averaged 36.84 FPS and fixed 85% averaged 30.94 FPS.
Both had zero late callbacks in that phase. Adaptive confirmed 1025×576 at the
floor and restored 1161×652 in recovery. The output stayed at 1366×768.

GOD TEST now accepts `--dynamic-resolution-fps 0|30|60|90|120`. A positive request enables the experiment in the isolated profile and records phase transitions with the controller target, actual input and output pixels and completed-frame generation. The reducer requires completed evidence and rejects a fallback as an adaptive result. The tour retains its native physics requirement. [Operating guide](../../../../tools/godtest/PERFORMANCE_TOUR.md)

## Windows flight integration screen

An isolated Windows debug export with the experiment and the GOD TEST pilot completed the Ugly Stik recovery and runway circuit on the RTX 3090 at 1920×1080, Forward+/Vulkan and a 60 FPS target. The native preflight identified a different verified executable. The debug flight selected the GDScript reference backend and its performance is outside the native benchmark comparison.

The Automatic High startup calibration owned the timing window throughout `recover`. It finished during `runway_circuit`, about 61 s of wall time after the first measured flight callback. The controller began observing and retired with `stale_gpu_feedback` about 0.16 s later. The scale stayed configured at 100%, with no verified adaptive extent during either phase. The case completed its flight but fails the adaptive evidence gate.

That calibration recorded 1.63 ms root-viewport GPU p95 and 122.32 ms callback p95 with active subviewports. This difference makes per-stage and per-viewport attribution essential before choosing a scale response. A CPU or pacing diagnosis also needs matching native-physics and display evidence.

Fixed comparison profiles now explicitly choose the renderer in their isolated settings. This gives fixed and adaptive runs the same renderer startup and removes the Automatic High calibration from those trials. It remains measurable in the automatic profile experiment. In the controlled repeat, the profile recorded High and the controller began observing 58 ms after the `recover` phase opened. It retired on `stale_gpu_feedback` 102 ms later. Recovery and return Home completed. This separates the calibration delay from the stale-feedback problem. Keep the freshness bound for this experiment. Native validation needs the qualified engine/kernel pair and current gameplay workloads.

Windows diagnostic receipts, including the native mismatch, incomplete attempts and flight record, are under `U:/OpenRC-drs-godtest-flight-20261122`. These runs used private profiles and the shared worker's desktop reservation. Post-run inspection found executables from earlier debug attempts still alive after their launcher reported cleanup. Their start times overlap the diagnostic flights, so use the Windows records for controller state and integration only. The controlled case returned exit zero and acknowledged quit. The remaining task-owned processes were stopped by their verified executable identities.
