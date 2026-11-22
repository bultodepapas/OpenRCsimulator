# Existing-Intel experiment protocol — 22 November 2026

The [corrected low-end plan](../../plans/low-end-gpu-performance.md) owns
execution order after the [adversarial audit](2026-11-22-intel-plan-adversarial-audit.md)
of main `85a2475f60029a4b6b09f23f643119bceea84a45`. The
[render-internals follow-up](2026-11-22-intel-render-internals.md)
retains sixteen code-linked candidates. This protocol owns admission, evidence
identity and comparison scope; a full tour is conditional, not the entry ticket
for every experiment.

Companion to the [investigation](2026-11-22-intel-gpu-investigation.md), under
VQ-07h-A2-R1 / PT1h-R15 / GOD-12/13. **Proposed hardware experiments, not completed
measurements.** Use the same currently owned Intel device for every paired
comparison. The earlier M1 records are context, not a new test dependency.

## 1. Establish the correct baseline

The [GOD TEST tour guide](../../../tools/godtest/PERFORMANCE_TOUR.md) owns its
launch, admission, output and acceptance procedure. Its `--graphics automatic`
option writes the first-run graphics bundle; it does **not** independently
select the product's renderer. In
[`runner.rendering_options()`](../../../tools/godtest/runner.py), renderer
`auto` resolves to Forward+ on Linux. Explicitly select Compatibility/OpenGL
to reproduce the current UHD 630 product recommendation.

This exact **full-tour offline preflight** was checked against source
`91d7d6dd`. It is retained for a later claim that actually needs the complete
three-aircraft scope; it is not the first command for L0/L1 attribution:

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

First reconcile the actual operated session and its existing admission. When
available, use the smallest affected Home or pilot-view comparison with matching
native binary/imports and retained engine/source receipts. Reuse a matching
current receipt; do not require a three-aircraft route pass or nine-case baseline
before a pixel/material screen. Expand to the existing complete tour only when
the change or final whole-session claim affects all three aircraft. Keep the
current Dummy-audio workaround for hosts without playback devices, and the
documented X11-through-Weston path constant. Compare Wayland separately only
for an attributed display/shutdown question.

If the required graphical route or mandatory monitoring is unavailable, record
that limitation and leave formal qualification open. Source changes, settings
design and deterministic checks can proceed. An existing functional container
lane is not a desktop performance route; no alternative launcher, validator
bypass or replacement machine is authorized by this protocol.

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

These observations supplement the artifact set. They do not add an Intel
backend to the current GOD TEST validator: its automatic Intel utilization
coverage remains unavailable until a reviewed implementation consumes it.
A diagnostic comparison may report its supported observations and explicit
unknowns, but cannot claim to pass a validator whose mandatory fields are
missing. Building that backend is not a prerequisite for source attribution or
offline implementation; formal hardware qualification remains separate.

## 3. Controlled experiment matrix

Run one applicable experiment at a time, stopping once the evidence settles the
decision. IDs below are stable references, not a requirement to execute every
row. Start with I0/I6 inventory and I1 pixels, then I3 ground; I5 loading is a
separate workstream whose hardware captures still serialize. I2 is conditional
because current Automatic already disables main AA. I4/I7/I8/I9 are deferred
until evidence identifies their question. Shared-host admission, memory
headroom and clean teardown remain required. No row requires different physical
hardware.

| ID | Question and controlled comparison | Keep fixed / retain | Decision rule and limitation |
| --- | --- | --- | --- |
| I0 / L0 | Is the current product profile actually being tested? Explicit Compatibility/OpenGL and current Automatic effective bundle. | Same source/engine/native backend, effective settings, output/internal dimensions, named affected phase and telemetry availability. | Wrong renderer, software fallback, missing identity or forced shutdown invalidates the affected claim. Fix that evidence gap before a performance conclusion; source work need not wait. |
| I1 / L1 | Does pixel work dominate? Start with existing 75% versus 67%; compare 100% versus 75% only where the saved baseline is actually 100%. | Output 1920×1080, same camera/world, main MSAA off, equal thermal state. Hold Home's effective multiplier constant for the component A/B and verify production adaptation separately. | A repeatable frame-time response supports pixel sensitivity, not a unique ALU/bandwidth diagnosis. Existing 75% gains are not new gains. Check distant-aircraft readability and UI sharpness. |
| I2 / conditional L4 | What is a target's AA marginal cost? Main off versus 2× only if that choice is at issue; inspect projected-shadow AA independently. | Same scale, renderer, camera/materials and cache state; record effective target, enum and sample count. | Current main AA is already Off. Do not count disabling it again, or assume it disables aircraft-shadow AA. Preserve edge/thin-wing/motion readability. |
| I3 / L2 | Which terrain term is expensive? Existing reversible `ablate` screen, then one bounded Simple/Full material candidate only if current attribution supports it. | Separate fixed Home and flight views; keep geometry, physical scenario, effective scale, light and AA identical; review day/night, runway, pad, track and shoreline. | Cached GPU polls and layer hiding are diagnostic leads only. Do not qualify deletion of collidable scenery or lake/track. Accept only repeated matched whole-workload improvement and preserved cues. |
| I4 / deferred | Does a specific remaining Compatibility problem justify Mobile/HDR investigation? Compare only after that question is established. | Same Intel, camera, internal resolution and AA, recorded effective HDR/color format; matching warmup and safe recovery. | No general renderer migration follows from newer API support. Speed alone cannot justify lost night detail; a Mobile-only improvement need not beat GL. |
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

For a promising product candidate, first run matched affected-view comparisons
on the same admitted host. Follow the [owning gate](../../plans/global-performance-visual-quality.md#gates-to-freeze-in-vq-01c):
at least three alternating pairs, 10 s warmup and 60 s measurement, or a stricter
applicable requirement. Expand to the complete three-aircraft tour only when
the whole-session scope or final claim requires it. Preserve native backend,
240 Hz physics, physical route and output targets. Compare phase p50/p95/p99,
longest stalls, time above 33/50/100 ms, sim/wall pace, memory and clean shutdown.
Inspect run distributions before pooling; correlated frames are not independent
experiments. Gain must exceed paired variability and reach the existing 5%
complete-affected-workload gate, or remove a named reproducible hitch/memory
defect, with no repeatable harmful tradeoff. Keep visual/presentation and formal
coverage evidence separate.

Twenty FPS is only the ideal catch-up floor for 12 steps/frame at 240 Hz.
Successful circuits should preserve sim/wall near 1 with no sustained slowdown;
startup/menu validity and the existing phase/coverage validators remain gates.
Do not relax them to turn an ineligible first Home into a pass. A cap/VSync
player-pacing campaign is separate from the uncapped capacity baseline.
The corrected plan's proposed 30-FPS usability checkpoint does not replace the
existing 60-Hz product or physical-presentation gates.

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
