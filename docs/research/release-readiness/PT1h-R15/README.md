# PT1h-R15 — Stutter detection and frame-pacing evidence

Date: 2026-11-17. Base: `a7de9b35676d891bc2034cc344b910d9e1ef9c61`.
Branch: `perf/stutter-diagnostics-2026-11-17`.

Follow-up: [24 investigations, 2026-11-19](research-2026-11-19.md) inform the
[remaining implementation plan](../../../plans/stutter-diagnostics.md). That
documentation update preserves the historical verification scope below.
The later [tool integration follow-up](tools-integration-2026-11-19.md) adds eight
investigations and PT1h-R15-S3a offline tools; its proof is separate from these
2026-11-17 runtime/bridge checks. The [session watch record](watch-2026-11-19.md)
covers the post-merge plan audit and the S1a/S2a automatic watch.

## Purpose and boundary

Strengthen the existing opt-in debug bridge so a short interruption, sustained FPS loss or long stall is easier
to detect, preserve and investigate. The implementation extends `frames`, `timeline`, the Python client and
the MCP server. It does not change the flight model, simulation timing, renderer policy or production FPS cap.

The operational contract and commands live in the [debug tools guide](../../../../tools/debug/README.md#frame-pacing-and-stutter-captures-pt1h-r15).
This record owns the investigation, decisions and verification scope. The measurements are monotonic wall
intervals between bridge process callbacks. They are not display presentation intervals, CPU busy time,
GPU completion, input latency or proof of the cause of a hitch.

## Findings established in the base source

| Finding | Practical effect | Change |
| --- | --- | --- |
| Hitch detection requires `ms > max(50, 3 × median)` by default. | A 33 ms interruption after 16 ms frames is not recorded as a hitch. | Add relative stutters and independent absolute stalls; preserve the legacy hitch channel. |
| `hitch_total` is the length of a 200-record array. | The displayed total stops growing during a long or troubled session. | Separate cumulative detections, selected-window counts and bounded retained details. |
| A requested frame window does not also constrain old hitch details. | Event evidence and statistics can describe different intervals. | Filter both detail buffers to the exact selected sequence interval. |
| Reset leaves the previous clock, median and monitor baselines. | A new measurement can include pre-reset time or compare against old state. | Start a fresh epoch, clear baselines/counters, prime a new clock and measure the next complete interval. |
| All pipeline-compilation categories are added together for attribution. | Background specialization can look like foreground blocking work. | Preserve the aggregate for compatibility and report separate category deltas as correlations. |
| Frame summaries have no export of exact chronological intervals. | A rare spike is difficult to inspect alongside its lead-up, recovery and context. | Retain bounded aligned raw columns and export one snapshot to JSON, CSV, HTML and Chrome JSON/Perfetto. |

These are source-level and deterministic software findings. No new organic in-flight stutter, target GPU
bottleneck, performance gain or complete elimination of stuttering is claimed here.

## Research and adopted decisions

Primary sources were reviewed before implementation. Defaults below are project policy, not externally
validated perceptual thresholds.

| Source | Relevant idea | Application and limits |
| --- | --- | --- |
| [NVIDIA Nsight Systems, Stutter Analysis](https://docs.nvidia.com/nsight-systems/UserGuide/) | Compare a frame with a nearby median and require both a relative increase and an absolute difference; median detection has alternating-cadence limits. | Default relative rule is `frame > 1.5 × baseline` **and** `frame − baseline > 4 ms`. The live baseline uses preceding samples, unlike Nsight's surrounding-window offline analysis. |
| [CapFrameX, explanation of performance metrics](https://www.capframex.com/blog/post/Explanation%20of%20different%20performance%20metrics) | Percentiles, tail averages and time-integral lows differ. Sample percentages differ from elapsed-time percentages. Very small tails are unstable. | Preserve the existing floor-based 1% low formula; add 0.1% low, p99.9, tail counts, sample-status labels and separate slow-frame time share. |
| [Perfetto trace configuration](https://perfetto.dev/docs/concepts/config) | A bounded ring preserves preceding context; trigger captures can also wait for recovery. | Extend the existing 7,200-frame ring. Export already-observed lead-up and recovery on request; this version does not implement an automatic delayed-stop trigger. |
| [Perfetto external formats](https://perfetto.dev/docs/getting-started/other-formats) | Chrome JSON supports complete slices, counters, instant markers and metadata with microsecond timestamps. | Export wall-interval slices and honest sampled context on separate tracks. Use a local time origin; do not invent cross-process clock synchronization. |
| [Godot Performance API](https://docs.godotengine.org/en/stable/classes/class_performance.html) | Some monitors lag, and some are unavailable in release builds. FPS is updated only once per second. | Detect from monotonic callback intervals. Treat monitor changes as supporting observations, never a proven per-frame cause. |
| [Godot pipeline compilation](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html) | Canvas, mesh, surface, draw and background specialization have different meanings; renderer support differs. | Preserve separate category deltas and renderer identity. Specialization alone does not establish blocking. Zero pipeline counters in Compatibility do not exclude shader-related stutter. |
| [PresentMon console documentation](https://github.com/GameTechDev/PresentMon/blob/main/README-ConsoleApplication.md) | Application, GPU and displayed-frame timing are different observations. | Keep GPU last readings marked `unverified_freshness`; recommend a native presented-frame capture for follow-up. Budget failures are not named dropped display frames. |
| [Godot jitter and stutter guide](https://docs.godotengine.org/en/stable/tutorials/rendering/jitter_stutter.html) | Uneven motion can also come from physics/render cadence and time-source mismatches. | Keep physics tick counts and context. A clean callback trace does not qualify camera/interpolation smoothness. |
| [Godot profiler](https://docs.godotengine.org/en/stable/tutorials/scripting/debug/the_profiler.html) | Detailed profiling introduces overhead. | Keep continuous recording bounded, report sampling cost, tag diagnostic-query coincidence and write files in the client process. |

## Detector and statistics contract

Three signals answer different questions:

- **Relative stutter:** sudden change compared with the preceding baseline. Require eight preceding intervals;
  use the upper median of up to 60, refreshed every 15 samples (also during initial baseline formation).
- **Absolute stall:** more than 50 ms by default, regardless of an adapted median.
- **Budget overrun:** more than `1000 / target_fps + budget_tolerance_ms`. Defaults are 60 FPS and 0.5 ms.
  This remains useful after a relative detector adapts to sustained lower FPS.

Each recorded row retains the actual baseline and detection flags used then. Summary queries do not reclassify
old frames against a newer median. Changing any detector policy starts a new epoch; all numeric options are
validated before mutation. The legacy `reset` boolean spellings remain accepted.

Average FPS is `1000 × N / sum(frame_ms)`. The existing 1% low remains
`1000 / mean(slowest max(1, floor(N × .01)) frame durations)`; 0.1% uses `.001`.
Nearest-rank frame-time percentiles are separate metrics. An isolated worst frame can matter even when p99
does not move, so raw maxima and event markers remain visible. The longest slow episode is selected by its
consecutive frame count, then duration on ties; its two reported values belong to that same episode.

Slow-time share sums the full durations of frames over the threshold. Budget-excess time sums their duration
minus the ideal budget. Neither quantity is measured presentation latency. Short-tail labels describe sample
availability, not statistical confidence; a one-observation tail is weak evidence even when nominally available.

## Retention, compatibility and cost

The raw ring retains 7,200 intervals. Each of the existing legacy-hitch and combined-event buffers retains at
most 200 detail records; their distinct union can contain 400. Session retained/evicted counts and window
returned/omitted counts use this union. Old details are never reported as lost while still available through
the legacy buffer. `timeline --stutter` selects the largest event across both returned arrays and uses the
recorded log cursors; `timeline --hitch` remains legacy-only.

New nonlegacy detail work is throttled to one record per 100 ms, except an event larger than the previous
retained event. New nonlegacy log output is throttled to one per second. Legacy hitch logging is preserved.
Every detected frame still gets flags and counts. Detail suppression, log suppression and eviction are explicit.
The source keeps bounded storage; target-hardware recorder overhead has not been qualified.

Reset clears measurement clock, counters, median, physics accumulator, histories and monitor/log baselines.
The next callback primes the clock; the following full interval is the first measured sample. Nonincreasing
clock input also starts a clean epoch and increments a lifetime discontinuity count. Policy updates cannot
leave a half-mutated configuration after a later option fails validation.

Query construction and JSON encoding remain main-thread work. The next measured interval is tagged
`diagnostic_query`; no interval is silently removed or adjusted. The final capture query affects a later
interval outside its own snapshot. Sampling-cost fields cover the preceding recorder call, not all bridge
work or a full application profile. Users should collect bounded snapshots rather than poll all raw rows every frame.

The exporter uses a separate `openrc-debug-frames v1` schema. Existing native `openrc-frametimes` exporters
require native simulation/session fields that the bridge does not measure; adapting those by fabricating
metadata would weaken their contract. The new exporter validates bounds, exact row alignment, monotonic
timestamps, sequence/window metadata and detail-to-row correspondence before writing. It refuses existing
destinations, escapes report text, neutralizes CSV formula entry points and removes only its own partial files.
It adds no runtime Python dependency beyond the standard library.

`frames --out` refuses reset and configuration keys before contacting the app. Configure first, reproduce,
then export. Otherwise an apparently convenient `target_fps=120 --out ...` would reset the ring before export
and lose the evidence being investigated.

## Verification

The pinned engine is **Godot 4.8.beta2.official.cafc17a19**, obtained through `app/get-godot.sh` and hash-verified.
The checked runner's diagnostic verdict is required; a process exit code alone is not a pass. Targeted test
scripts are discovered by the existing `app/test.sh` roster, and Python tests by `research/test-tools.sh`.

Final scoped results and exact changed-source hashes are recorded in [verification.json](verification.json).

| Executed check | Result and scope |
| --- | --- |
| New deterministic frame-history script | **51/51** assertions pass; zero engine errors or warnings. Includes 60/120 FPS relative detection, sustained slowdown, metric definitions, paired episodes, atomic options, reset, query flags, ring wrap, more than 200 events, independent detail buffers and bounded logging. |
| Existing bridge contract script | **26/26** assertions pass; real loopback framing, numeric/reset/retention and checkpoint controls. |
| Existing step and observer scripts | **24/24** and **36/36** assertions pass; no engine errors or warnings. |
| Existing broad bridge script | **114/114** assertions pass; zero errors and the two expected intentional logger warnings. |
| Python client, capture exporter, MCP server, registration and transport | **116 tests: 115 passed, one native-Windows locking test skipped** on Linux. The final report-only changes also pass the 11 exporter tests. |
| Godot JSON to exporter | A **126-frame** deterministic snapshot, serialized by Godot's default bridge JSON encoder, exports successfully to all four artifacts with its flagged event and exact timestamps. |
| Actual bridge → CLI → files | An owned empty headless scene with deliberate 25 ms and 80 ms sleeps produces a **150-frame** capture containing two relative stutters, one absolute stall and one marked prior frame query. The actual `frames --out ... --json` client writes all four artifacts; the checked Godot process exits cleanly. This is a software integration probe, not a rendered flight or performance benchmark. |
| Chart checks | JavaScript syntax and mocked-canvas checks pass for a 7,200-frame spike, logarithmic/linear redraw, narrow widths, resize and pixel ratios 1/2. Actual browser visual review remains unverified because Chromium's required local socket creation is denied in this environment. |
| Independent source review | Four concrete findings were fixed and rechecked: capture-before-reset safety, paired longest episodes, union retention/timeline selection and legacy reset spellings. |

The Godot checks use the real candidate debug sources and unchanged existing test scripts in a disposable
source-only project with their static dependencies. As in the earlier PT1h-R14 isolation, two unrelated seams
are substituted: landscape catalog membership is `club_field`, and preferences expose English. Production
input/physics settings are retained; the asset-dependent font autoload, internationalization, editor plugins
and main scene are removed from this fixture. The broad bridge wrapper seeds aircraft ground-start answers
to avoid loading the flight scene; aircraft start support and visual assets are therefore outside this pass.
No production runtime or existing test assertion is weakened to obtain it.

Initial full-dependency editor imports exited with signal 9 or timed out, and incomplete imports caused
asset-loader errors in a subsequent parse attempt. The smaller editor import also timed out. Those attempts
are not passes; the source-only standalone scripts require no imported textures and successfully parse/run.
The first new test run also exposed an exact floating-point comparison against a rounded 33.3 FPS value;
the assertion now uses a narrow `1e-8` numerical tolerance without changing the expected metric.

The local environment has no enrolled remote test pool. Required app/visual CI and a rendered target-hardware
flight remain separate from these focused checks. No native Windows, presentation-timing or GPU performance
qualification is implied. Import/startup failures and browser limitations are retained as limitations, not
converted into successful test results.

## Repeatable target-machine investigation

1. Run a rendered 1920×1080 session on the target machine. Record aircraft, route, renderer/settings, display
   refresh, VSync/FPS cap and source revision. Warm the intended route consistently; record a separate cold-load
   case when first-use stutters are the question.
2. Configure diagnostics once, then reset at the intended starting point. Keep the same target FPS, tolerance
   and stutter thresholds for baseline/candidate comparisons.
3. Reproduce the same flight segment. Capture promptly after the problem so the preceding frames remain in
   the ring; allow observed recovery when useful. Preserve all four files together.
4. Inspect raw spikes and budget episodes as well as average FPS and lows. Check tail counts, duration, route
   changes, focus/pause, physics ticks and diagnostic-query markers before attributing a cause.
5. Use observed context to choose one follow-up experiment: script CPU profiling, resource/scene loading,
   foreground pipeline preparation, physics catch-up or a native PresentMon/Nsight capture. Repeat comparable
   runs after a targeted fix. A changed counter alone is not a causal verdict.

Automatic trigger/post-trigger capture was added later as the
[session watch](watch-2026-11-19.md). Richer platform presentation timing and automated before/after
qualification remain follow-ups.
