# Existing-Intel experiment protocol — 22 November 2026

The [render-internals follow-up](2026-11-22-intel-render-internals.md#experiment-order-and-acceptance)
adds sixteen code-linked candidates and a prioritized experiment order. The
admission, baseline and evidence requirements in this protocol apply to them.

Companion to the [investigation](2026-11-22-intel-gpu-investigation.md), under
VQ-07h-A2-R1 / PT1h-R15 / GOD-12/13. **Proposed hardware experiments, not completed
measurements.** Use the same currently owned Intel device for every paired
comparison. The earlier M1 records are context, not a new test dependency.

## 1. Establish the correct baseline

The [GOD TEST tour guide](../../../tools/godtest/PERFORMANCE_TOUR.md) owns the
launch, admission, output and acceptance procedure. Its `--graphics automatic`
option writes the first-run graphics bundle; it does **not** independently
select the product's renderer. In
[`runner.rendering_options()`](../../../tools/godtest/runner.py), renderer
`auto` resolves to Forward+ on Linux. Explicitly select Compatibility/OpenGL
to reproduce the current UHD 630 product recommendation.

This exact **offline preflight** was checked against source `91d7d6dd`:

```sh
python3 tools/godtest/godtest.py performance-tour --dry-run \
  --repeats 3 --graphics automatic \
  --resolution 1920x1080 --window-mode borderless \
  --rendering-method gl_compatibility --rendering-driver opengl3 \
  --scene-detail low
```

It expands nine complete cases: Stik, jet, Corsair, repeated three times.
Requested native physics, continuous frame watch, hardware monitoring and all
menu/circuit/shutdown phases remain enabled. The plan requests uncapped FPS and
VSync disabled. It does not prove actual renderer, scale, hardware coverage or
completion. The reported execution lease is planning information, not duration.

For execution, follow the guide's admitted route. The reviewed managed graphical
adapter is Windows-local/experimental; checked-pool SSH access does not by
itself authorize an alternate graphical launcher on an enrolled Linux host.
Use the existing owning session/authority and reconcile its capabilities with
the deployed host. Do not disable enrollment or change queue roots to bypass an
unsupported adapter. The earlier operator-owned Intel campaign does not turn
an unavailable route in this workspace into a live connection.

Begin with one three-aircraft pass to confirm the route only if no equivalent
current receipt exists. Then run the nine-case baseline. Use the matching
qualified native binary/imports and preserve its engine/source receipts. Keep
the current Dummy-audio workaround for hosts without playback devices, and the
documented X11-through-Weston path constant. Compare Wayland separately.

The older direct `--scripted` route is a technical workload. App arguments take
it before first-run player settings are loaded. It must not be described as
the current Automatic product behavior. Supported direct-route knobs include
`OPENRC_MSAA=0|2|4|8` and `--scene_detail=low|medium|high|extreme`; there is no
implemented direct `--render-scale` argument in `Reconstruction.startup_config()`.
Use the existing player settings or an owned debug session for scale trials.

## 2. Required identity and telemetry

Retain raw samples in the existing ignored/external evidence location. Publish
only concise, sanitized summaries, hashes and a recovery location. A hash of
this investigation's transcription is not a hash of the unavailable raw run.

| Layer | Required record | Interpretation |
| --- | --- | --- |
| Source/executable | Commit and dirty-input digest, engine version/hash, native binary/receipt, driver/tool versions. | Source-only, package and hardware results are different claims. |
| Workload | Aircraft/model, scene/landscape/collision identity, camera, fixed view or real circuit, time/weather/seed, graphics identity, phases and raw frame stream. | Preserve the same route and effective settings within a pair. |
| Display/rendering | Engine adapter/vendor/API, renderer, DRM render-node mapping/BDF, Weston renderer, Wayland versus X11, output/drawable/internal 3D dimensions, actual scale, HDR2D, AA enum and sample count, reconstruction, VSync/cap, Home budget state. | A compositor can use hardware while the app uses another adapter; verify both. A saved scale is not the final Home scale. |
| Host GPU | Per-engine busy/time observations, actual/requested/configured maximum clocks, package/GPU power and temperature where available, thermal/power-limit indications, timestamped i915 errors/reset counters. | Render, video, copy and compute engines are distinct. Frequency alone is not utilization; device totals include other processes. |
| Process/CPU | Existing process CPU/RSS/threads/I/O, thread hot spots when necessary; actual CT CPU quota/cpuset/weight and `cpu.stat` throttling deltas. | 100% process CPU is one logical CPU; 6 assigned threads do not imply six exclusive physical cores. |
| Memory | Existing module sizes/slots/channels/configured speed; host available memory, swap activity and PSI; actual CT `memory.current`, `memory.stat`, `memory.events`, `memory.swap.current`, high/max limits and pressure. | Resolve the process's cgroup and relevant ancestors; container-visible `/proc/meminfo` alone is insufficient. Do not add overlapping RSS/shmem/engine counters. |
| Shared work | GPU clients and co-tenant workload class/activity, capture/encoder state, timestamps and thermal settling. | Keep services unchanged by default. A past one-time stop permission is not a new standing maintenance window. |
| Cache | Godot user-profile/cache identity, Mesa cache path/state/hit statistics, imports and process state. | Fresh process, fresh profile and cold driver cache mean different things. |

Use existing `render`, `frames`, `layers`, `memory` and `frames watch` through
the [debug bridge](../../../tools/debug/README.md), and the existing
[resource sampler](../../../tools/godot/README.md). For fields they lack, the
admitted host operator can collect bounded read-only Intel/OS observations:

- Resolve the render node through sysfs and `lspci -nnk`; retain vendor/device
  and driver identity. Avoid relying on a hardcoded `card0`/`card1` numbering.
- If already available with appropriate read access, retain Intel GPU Tools
  per-engine/clock JSON or supported DRM `fdinfo` counters with device identity,
  units, monotonic query brackets and an owned process lifetime. Check the
  installed tool's help/version for its exact invocation. Do not change kernel
  permissions or give the container additional device privileges to get a number.
- Treat unsupported or denied PMU/temperature/power fields as unavailable.
  Do not fabricate zero values. Per-client cumulative engine time requires two
  ordered samples; account for engine capacity, duplicated client IDs, resets,
  process restarts and elapsed-time units. It is not device-wide busy percent.
- Keep detailed traces, Mesa shader statistics and thread profiling in separate
  diagnostic runs. Measure observer-off versus observer-on overhead before
  accepting the instrumented workload as a reference.

These observations supplement the artifact set. They do not magically add an
Intel backend to the current GOD TEST validator: its automatic Intel utilization
coverage remains unavailable until a reviewed implementation consumes it.

## 3. Controlled experiment matrix

Run the matrix sequentially, stopping once the evidence settles the decision.
Do not launch all rows concurrently. Shared-host admission, memory headroom and
clean teardown remain required. No row requires different physical hardware.

| ID | Question and controlled comparison | Keep fixed / retain | Decision rule and limitation |
| --- | --- | --- | --- |
| I0 | Is the current product profile actually being tested? Explicit GL/Automatic baseline above. | Same source/engine/native backend, all effective settings, output/internal dimensions, complete phases and telemetry availability. | Wrong renderer, software fallback, missing identity or forced shutdown invalidates the affected claim; fix the route before optimization. |
| I1 | Does pixel work dominate? On the same GL profile, compare 100%, 85%, 75%; use 67% only if needed. | Output 1920×1080, same camera/world, MSAA off, equal thermal state; freeze diagnostic views separately from real flight. Pin or observe Home's budget consistently. | A repeatable frame-time response supports pixel sensitivity, not a unique ALU/bandwidth diagnosis. Check distant-aircraft readability and UI sharpness. |
| I2 | What is AA's marginal cost? Explicit off versus 2×, then 4× only if useful. | Same scale, renderer, camera/materials and cache state; record effective enum/sample count. | AA savings must exceed pair variability and retain acceptable edge/shimmer quality. Do not substitute a mislabeled default. |
| I3 | Which terrain term is expensive? Existing `ablate` screening, then one bounded material candidate. | Separate fixed Home and flight views; keep geometry/collision, scale, light and AA identical; review day/night and runway boundaries. | Stock cached GPU polls and layer hiding are screening evidence. Accept only a repeated matched candidate with total-frame improvement and preserved appearance. |
| I4 | Does Mobile's forced HDR cost justify a different design? Mobile/ANV HDR on/off, then compare the acceptable variant to GL. | Same Intel, camera, internal resolution and AA, recorded effective HDR and color format; matching warmup. | Speed alone cannot justify lost night detail or altered captures. A Mobile-only improvement need not beat GL. |
| I5 | Is the startup freeze compilation or recurring loading? Separate Godot-cache-cold/Mesa-warm, both-warm, and isolated both-cold conditions. | Same scene/order/source/audio path; separate owned profiles/cache directories and retained cache states; retain time-to-first-usable-frame and worst frame. | A cache-dependent stall identifies first-use work. Remaining warm stalls need a stage/thread trace. No deletion of shared/player caches; OS-cache state stays explicitly uncontrolled unless measured. |
| I6 | Are host limits active during slow intervals? Observe the unchanged workload with synchronized CPU/cgroup/memory/thermal counters. | Same GL baseline and co-tenant state; compare counter deltas over the run, not historical totals. | Rising reclaim/pressure/throttling/reset evidence supports further attribution. High temperature or allocated swap alone does not prove a frame bottleneck. |
| I7 | Does sharing materially change the game? If an existing operator-authorized window permits, pair the same baseline with one co-tenant workload state changed. | Same cache/temperature/scene, service state and restoration receipt; per-engine activity and service health. | Without controlled state change and matched conditions, report correlation only. Do not stop Frigate or another service just to complete this row. |
| I8 | Is Mesa version a reproducible factor? One supported/pinned user-space candidate versus 25.0.7 on the same Intel host. | Same kernel, engine, assets, compositor, effective settings and labelled warm caches; record actual loaded libraries and rollback identity. | A repeated gain/regression justifies that version finding. It does not attribute all remaining cost to Mesa or support a simultaneous kernel change. |
| I9 | Is display backend trading throughput for reliability? Existing X11/Weston versus Wayland/Weston only if the shutdown issue needs a bounded reproducer. | Same workload and current engine; own processes; retain cleanup evidence and watchdog-safe limits. | A forced kill is a failure, not a faster run. Throughput and clean shutdown are separate results; no physical-presentation claim from a headless compositor. |

### Pairing and acceptance

For fixed-view diagnostics, establish a warm stable reference, alternate A/B
order in at least three paired blocks, and return to the reference between
candidates. Retain all repeats, including failed or incomplete attempts. Use
time-based windows appropriate to the low frame rate, not a few favorable
frames. The bridge's existing `ablate` already uses A–B–A and restoration;
its unverified GPU deltas are deliberately not ranked or called significant.

For a promising product candidate, run the complete three-aircraft tour on the
same host, with paired reference/candidate blocks. Preserve native backend,
240 Hz physics, route completion and output targets. Compare phase p50/p95/p99,
1% lows, longest stalls, time above 33/50/100 ms, sim/wall pace, memory and
clean shutdown. Inspect per-run distributions before pooling; thousands of
correlated frames are not thousands of independent experiments. Any practical
gain must exceed the observed run-to-run spread and include its quality cost.

Twenty FPS is only the ideal catch-up floor for 12 steps/frame at 240 Hz.
Successful circuits should preserve sim/wall near 1 with no sustained slowdown;
startup/menu validity and the existing phase/coverage validators remain gates.
Do not relax them to turn an ineligible first Home into a pass. A cap/VSync
player-pacing campaign is separate from the uncapped capacity baseline.

The main [investigation](2026-11-22-intel-gpu-investigation.md) distinguishes
observed outcomes, hypotheses and current code. This protocol creates no
runtime toggle, renderer default, driver setting, cache deletion or host change.

## 4. GitHub and offline verification scope

GitHub can check source contracts, plan expansion, metadata validation,
regression fixtures and documentation. The current CI's software-rendered
visual lanes cannot establish UHD 630 frame time, memory pressure, thermal
behavior or presentation. Preserve those gates; do not rename a CI capture
as Intel performance evidence.

Use [GOD TEST report/compare](../../../tools/godtest/README.md) and
[`frame_diagnose.py`](../../../research/performance/frame_diagnose.py) for their
own artifact formats. Do not feed tour output to the legacy reducer without
checking its schema. Do not run the older
[`graphics_ladder/ladder.py`](../../../research/performance/graphics_ladder/ladder.py)
unchanged on Linux: its documented implementation covers macOS and
Windows/NVIDIA and takes the non-Windows path as macOS.

Before accepting a new evidence bundle, recover the exact engine logs,
`execution.json`, manifest/frozen-source identity, graphics identity, frame
stream, phase/incident streams, CPU/GPU samples and ownership/cleanup receipts
defined in the tour guide. Hash the real files, preserve failures, and rebuild
reports from those files. A narrative's “valid” label or a screenshot of FPS
cannot replace that process.
