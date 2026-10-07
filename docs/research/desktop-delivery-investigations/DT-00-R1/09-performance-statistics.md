# Desktop delivery research 09 — Performance statistics and frame evidence

2026-10-07 · Research round **DT-00-R1** · Item 09. Supports [DT-01 and DT-10/DT-11](../../../DESKTOP-DELIVERY-PLAN.md). This item number is research numbering; it is not plan milestone DT-09.

**Status:** logger/code audit and measurement-design research. No benchmark, export or hardware run was performed.

## Question

What does the existing frame logger actually measure, how much evidence do the proposed ten launches and three 60-second runs provide, and how should DT-10 separate frame cadence, render work, simulation real time and presentation?

## Code audit

`app/main.gd::_process()` calls `_log_frame_time(delta)` once per app process callback. It stores the elapsed `Time.get_ticks_usec()` interval between those callbacks, Godot's `delta`, and point-in-time performance counters. `app/render/frame_samples.gd` retains raw intervals and reports p50/p95/p99/max for monotonic wall interval and `delta`. It also stores `TIME_PROCESS`, `TIME_PHYSICS_PROCESS`, draw calls and other values as raw per-callback metrics. The output is versioned `openrc-frametimes v2`.

This is useful evidence of process-callback cadence under the specified window, VSync, cap and workload. It is not a physical monitor presentation timestamp. The callback runs before the rest of `_process()` updates the rendered scene; it does not observe compositor queueing, scanout or photons. Godot's `RenderingServer.frame_post_draw` signal means the RenderingServer finished updating all viewports; its documented contract does not say the image has reached the display. [Godot RenderingServer 4.7](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html).

The existing values `Performance.TIME_PROCESS` and `TIME_PHYSICS_PROCESS` are engine work-time monitors (one frame / one physics frame), not end-to-end frame intervals. Godot documents `TIME_FPS` as a count over the last second updated only once per second. Do not label any of those as display presentation. [Godot Performance 4.7](https://docs.godotengine.org/en/4.7/classes/class_performance.html).

## The key measurement distinction

| Metric | What it answers | Use and limit |
| --- | --- | --- |
| Monotonic interval between `_process` samples | How often the app loop reaches the sampling point, including blocking/waiting and OS scheduling effects | Keep raw data; call it process/frame-loop interval. Useful for cadence, stalls and matching app simulation progress to wall time. It is not a present-to-present or input-to-photon timestamp. |
| `delta` / `TIME_PROCESS` | Godot's per-frame timing values sampled by the logger | The logger stores a sample of `TIME_PROCESS` at each callback in `raw_metrics`; it is an engine monitor value, not the monotonic callback interval or a display-presentation timestamp. Keep it separate from wall cadence and do not describe it as GPU/present time. |
| `TIME_PHYSICS_PROCESS`, `physics_step_usec` | Simulation work time/cost | Keep under physics team's 500 µs/tick contract; collect per-tick distributions in its owned benchmark if needed. Do not infer visual frame pacing from average tick cost. |
| Godot viewport render CPU/GPU time | Last-frame render time for a viewport | Godot 4.7 offers `viewport_set_measure_render_time`, CPU/GPU viewport timings and frame-setup CPU. CPU render timing excludes `_process` and other engine work. Use it as an optional diagnostic after verifying the active Compatibility/backend returns valid values. [API](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html). |
| OS/display present cadence or input-to-visible response | Whether frames reach the actual display and when visible input response occurs | Requires native platform/display tooling or high-speed video/photodiode. Retain the existing F6 method for radio-to-visible latency; an engine callback cannot measure USB and scanout delay. |

Godot's 4.7 API warns that GPU render time is impacted by the GPU's power-state clocks under low utilization/capped frame rate. Run separate uncapped/GPU-capacity diagnostics and normal VSync/user-experience tests; do not compare GPU time alone as if the two conditions were equivalent. [Godot RenderingServer 4.7](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html).

## Percentiles need sample scope and method

NIST defines a sample percentile through ordered observations; different interpolation conventions can yield slightly different values, especially with small samples. The report uses `Hud.percentile`, so record and freeze that exact method when thresholds are evaluated. [NIST percentile definitions](https://www.itl.nist.gov/div898/handbook/prc/section2/prc262.htm).

At an idealized steady 60 Hz, a 60-second run has about 3,600 frame-loop intervals. A p99 rank therefore has only about 36 observations in the upper one percent; a 20-second run would have about 12. Those are arithmetic counts, not a confidence claim. Frame times are serial observations from one continuously running process, affected by shared cache, thermal and scheduling state, so 3,600 intervals do not equal 3,600 independent hardware trials.

Report p50/p95/p99/max separately for every run, plus its frame count and actual duration. Do not concatenate all frames across A and B candidates and publish one percentile: that erases between-run variance and weights faster runs with more frames. A pooled sample can be a diagnostic, but it cannot replace run-level results.

Ten launch samples are ten observations of that launch protocol on that machine. “All ten met the target” is an observed acceptance rule; it does not establish a general startup percentile or reliability across other machines, OS versions, cache states or temperature. A fresh process does not guarantee cold OS, disk, shader or driver caches. Include timeouts/failures as failed observations and publish all ten values.

Three 60-second runs are a reasonable initial **screening baseline**, but too few run-level observations to claim a stable population p99 or a general performance improvement when variation is unknown. NIST's confidence-interval guidance emphasizes that uncertainty depends on both sample count and observed spread. Treat 3 runs as evidence to estimate variability, not as a vendor-backed sufficient sample size. [NIST confidence limits](https://www.itl.nist.gov/div898/handbook/eda/section3/eda352.htm).

## Tighten the comparison protocol

1. Freeze the final candidate package digest and a named host profile: OS/build, CPU/GPU/RAM, driver/API, renderer, monitor mode/refresh/DPI, power mode, thermals, aircraft, field, scene, camera, input route, VSync and cap.
2. Use paired runs on the same host and condition. Alternate or randomize baseline/candidate order (for example A-B/B-A blocks) to reduce warm-up/order bias. Restart processes between runs; use a documented cache protocol. Do not compare a clean Linux runner with an owner laptop.
3. Keep current 10 startup launches as an initial acceptance sample only. Report each launch and failure. After pilot variance is known, choose more independent launches only if the interval around the measured change is too wide to decide; do not fabricate a universal N.
4. Keep three 10-second warm-up + 60-second runs/case for the first instrumented baseline, clearly marked as exploratory. If a small optimization is near run noise, add paired blocks until the run-level uncertainty is smaller than the agreed minimum useful effect, or reject the change as unproven.
5. For frame-loop cadence report every run's p50/p95/p99/max plus histogram or empirical CDF, number of intervals and missed-refresh bins. State the quantile formula/interpolation and whether p99 is within-run or over independent run summaries.
6. For A/B decisions calculate a paired run-level change in the relevant statistic (e.g. each run's p95), show all paired differences, median/mean and an uncertainty interval at the run/block level. Only retain the optimization when the practical benefit exceeds observed variation and no protected metric worsens. Keep the proposed 10% improvement/5% regression figures labeled as local screening choices, not statistical truths.
7. Capture CPU and GPU render instrumentation separately from wall interval. Enable Godot's viewport measurements only in the diagnostic run; record whether the API returned nonzero/valid results, since it requires explicit enabling and backend support. Add presentation timing/high-speed measurements only for claims that depend on actual displayed frames or radio response.
8. Align simulation progress with the exact measured wall interval. The app's `measured_simulation` sample uses the first to last sampled frame-end tick and excludes the first sampled interval; compare against that stated interval, not an entire process duration or the first-sample-to-exit wall clock. Exclude intentional paused time and fail the evidence if paused/faulted state is observed.

## Specific plan corrections to consider

- DT-01's ten launches should say “initial per-host sample; report all values and failures” and explicitly deny a cross-hardware percentile claim.
- DT-10 should rename p95/p99 currently based on `frame_ms` to **process-loop interval p95/p99** until an OS display-presentation source is added and validated. Keep present/pixel latency under F6 or native display evidence.
- DT-10 should request raw per-run files and run-level summaries, not only a three-run aggregate. Use frame count and actual sampled seconds to interpret each percentile.
- Add an optional Godot CPU/GPU render-time capture to diagnose bottlenecks. Do not silently insert instrumentation into all pilot runs if it changes cost; compare instrumented and uninstrumented runs before using it for budget gates.
- Keep `physics_us_per_tick` and simulation/wall ratio distinct. The smoothed physics cost in this logger is not the 240 Hz per-tick distribution owned by Phase H/Gate P.
- Leave 60 Hz p95/p99 budgets, 0.99–1.01 simulation/wall and optimization percentages explicitly **proposed local engineering budgets** until measured on named hardware and accepted by the owner. No official source validates these simulator-specific limits.

## Reproduction and evidence schema

Static audit commands: `sed -n '205,250p' app/main.gd`, `sed -n '550,660p' app/main.gd`, and `sed -n '1,240p' app/render/frame_samples.gd`. Existing visual-quality trial code already uses 3 × 10-second warm-up + 60-second scripted runs and warns that Xvfb/llvmpipe is harness evidence, not hardware performance approval; keep it as a useful protocol precedent, not as a native-live-flight result. `docs/research/visual-quality-implementation/VQ-01b/README.md` states that raw monotonic intervals are wall-clock, while `engine_*` fields are the separate Godot delta.

For each trial preserve immutable JSON files, candidate/package hash, case ID, route, wall-clock sample boundaries, warm-up/cache declaration, frame count, raw `frame_deltas_s` and `frame_wall_usec`, selected profiler measurements, system metadata, and all run-level p50/p95/p99/max. The current logger already emits most timing samples; process CPU/GPU profiler and presentation measurements are additions to consider after a scoped spike.

## Limits and sources

The source audit proves what the current logger stores, not how a given driver presents frames. NIST formulas describe statistical estimation under their stated sampling assumptions; adjacent engine frames violate a simplistic independent-sample interpretation. The sample counts above are illustrative arithmetic at 60 Hz, not power calculations. No hardware, release, native display, radio, or before/after optimization measurement was performed.

Primary references:

- [Godot 4.7 `Performance`](https://docs.godotengine.org/en/4.7/classes/class_performance.html).
- [Godot 4.7 `RenderingServer`](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html) (`frame_post_draw`, viewport render timing, frame setup CPU).
- [Godot 4.7 performance profiling](https://docs.godotengine.org/en/4.7/engine_details/development/profiling/index.html).
- [NIST Engineering Statistics Handbook — percentiles](https://www.itl.nist.gov/div898/handbook/prc/section2/prc262.htm) and [confidence limits for a mean](https://www.itl.nist.gov/div898/handbook/eda/section3/eda352.htm).
- Repository audit: `app/main.gd`, `app/render/frame_samples.gd`, `app/tests/visual_quality_cases.py`, `docs/research/visual-quality-implementation/VQ-01b/README.md`, and [DT-00 performance acceptance](../DT-00/03-performance-acceptance.md).
