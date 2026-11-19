# Stutter diagnostics: evidence and implementation plan

Owner: PT debug tooling, coordinated with VQ/DT performance, GOD TEST, UI loading,
CAM and simulation owners. Prefix: **PT1h-R15-S0…S7**, subordinate to PT1h-R15.
Updated: **2026-11-19**. Branch: `perf/stutter-diagnostics-2026-11-17`.
Inspected baseline: `594c15b5ad7fe1828ffc7a05e3ce7e288dc1e948`.

**Status:** S0 research and planning are complete. S1–S7 are proposed work; this
revision changes documentation only. Existing commands and metric definitions
remain in the [debug guide](../../tools/debug/README.md#frame-pacing-and-stutter-captures-pt1h-r15).
The [24 investigations](../research/release-readiness/PT1h-R15/research-2026-11-19.md)
own dated evidence and source limitations. The [global performance plan](global-performance-visual-quality.md#4-measurement-and-acceptance-contract)
owns product gates; this plan does not replace them.

## 1. Outcome and existing foundation

Make an intermittent freeze or sustained FPS drop produce an inspectable incident:
what was observed, which interval is covered, what happened before and after it,
which measurements are missing, and which experiment can distinguish plausible
causes. A report may remain unattributed. A smooth callback trace does not prove
smooth camera motion, displayed frames, or low input latency.

The branch already implements the following; preserve it rather than scheduling
it as new work. Source authority: [bridge](../../app/debug/debug_bridge.gd),
[statistics](../../app/debug/frame_statistics.gd),
[render probe](../../app/debug/render_probe.gd),
[exporter](../../tools/debug/frame_capture.py), and [R15 verification](../research/release-readiness/PT1h-R15/README.md).

| Existing behavior | Boundary to preserve |
| --- | --- |
| Relative stutters, independent absolute stalls, target-budget overruns and legacy hitches | Live flags use preceding history and are retained with their original baseline; a policy change starts a new epoch |
| 7,200 callback intervals; separate bounded legacy/event details | Exact flags survive detail suppression; ring eviction and selected-window omission have different meanings |
| Mean FPS, explicit tail-average lows, nearest-rank percentiles, slow episodes and adjacent-duration variation | Keep formulas, rounding, sample counts and the observed interval source; similarly named external metrics may differ |
| JSON, CSV, HTML and Chrome JSON/Perfetto export; typed `sim_frames` | One bounded snapshot, client-side files, no implicit reset, no overwrite of an existing destination |
| Route/event context, physics counts, pipeline categories and diagnostic-query flags | Correlations are observations; queries and logging can perturb subsequent callbacks |
| `render`, `ablate` and optional last-read GPU values | Root viewport scope and `unverified_freshness`; no manufactured CPU/GPU/presentation timeline |

The source pin is Godot `4.8.beta2.official.cafc17a19`. Standard desktop rendering
uses Compatibility, with the Apple Silicon Mobile/Metal override; actual renderer,
driver and fallback must come from the running process. High/custom-engine routes
retain their own admission and qualification. Physics remains float64 at 240 Hz,
with 12 maximum engine physics steps per frame and the existing custom interpolation.
See [runtime configuration](../../app/project.godot) and [engine pin](../../app/get-godot.sh).

At research time, this branch was one commit ahead of and 55 behind `main`
(`99e5a5ac024935c32028e5332d31a3e09da4dc42`); the merge base was
`a7de9b35676d891bc2034cc344b910d9e1ef9c61`. Before a later integration, compare
the then-current heads and shared bridge/GOD TEST interfaces again. This is a
dated integration dependency, not a requirement to mix unrelated changes into this update.

## 2. Scope and ownership

The implementation boundary is `app/debug/debug_bridge.gd`, `frame_statistics.gd`,
`render_probe.gd`, `tools/debug/`, their focused tests, this plan and R15 research.
UI loading and camera markers need their owners' narrow integration seams. GOD TEST
owns full-session orchestration and its comparison reports. PT/VQ/DT own metric
meaning and hardware qualification; SF/FL retain simulation and replay contracts.

Keep diagnostics opt-in and bounded. Reuse session admission and the existing
transport/exporter. Keep detailed profiling and screenshots outside acceptance
timing runs. No new telemetry service, mandatory vendor profiler, default renderer
change, physics-rate reduction, automatic graphics downgrade, or engine fork is
part of these initial deliveries. An external tool's availability does not establish
compatibility with the running engine/API/hardware.

## 3. Ordered deliveries and proof

| ID | Work and dependency | Required proof / status |
| --- | --- | --- |
| **PT1h-R15-S0** | Audit branch behavior; research 24 questions; reconcile plans, guide and decisions | **Complete, documentation only:** dated source register and explicit dispositions; no new performance result |
| **PT1h-R15-S1** | Capture provenance, capability/freshness dictionary, comparison identity; first slice | Old v1 fixtures still import; unknown runtime revision stays unknown; absent, stale and zero values remain distinct; engine source and rendered availability receipts agree |
| **PT1h-R15-S2** | Owned automatic incident collection with lead-up/recovery and coverage accounting; depends on S1 | One explicit arming yields at most one incident; sampled budget detection and cumulative event triggers retain their different coverage; epoch changes, storms, late polling and rollover cannot silently lose or duplicate rows |
| **PT1h-R15-S3** | Scoped phase/marker context and detector characterization; S1, with S2 for incident fixtures | Loading/camera/physics/render symptoms stay distinct; periodic monitors are not frame-local; retained live flags stay unchanged; exact threshold and alternating-cadence cases documented |
| **PT1h-R15-S4** | Offline comparable-run analysis through existing GOD TEST/performance tools; S1 and explicit coverage | Metric/configuration mismatches are refused or visibly incomparable; per-run paired deltas and failures retained; short tails do not receive confidence claims |
| **PT1h-R15-S5** | Optional native sidecars and clock correspondence; S1/S3 | Named Windows, Linux and Apple routes report capability and alignment uncertainty; unsupported/unaligned channels remain explicit; original captures preserved |
| **PT1h-R15-S6** | Rendered incident, observer-cost and package qualification; S2–S5 as applicable | 1080p-first matched campaigns, real UI/flight/first-use incidents, report/Perfetto import review, and separate native platform outcomes; unsupported sidecars do not block core qualification |
| **PT1h-R15-S7** | Conditional deeper attribution or long recording | **Deferred:** native Tracy/signposts, vendor GPU captures, JSONL streaming or MAD labels require a named unresolved incident and their own bounded experiment |

The first implementation should deliver S1 and one S2 incident end to end before
adding more diagnostic channels. Each step is separately reviewable. None closes
product performance gates merely by producing a report.

## 4. Capture identity and measurement contract

Prefer a small, versioned incident manifest beside untouched `openrc-debug-frames v1`
snapshots. The manifest and fields below are **proposed**, not current CLI/API options.
Keep `openrc-frametimes` and flight-log formats distinct; do not fabricate their
simulation/session fields to coerce a bridge capture into a benchmark format.

| Group | Proposed receipt / interpretation |
| --- | --- |
| Identity | Incident/run/scenario IDs; runtime-reported source/build identity and provenance; client revision separately; engine executable/version, actual backend, renderer/driver, PID and independently validated nonsecret launch/session-instance identity plus epoch |
| Workload | Aircraft/field/configuration identity, reproducible input/scenario, route/phase, camera, output and internal dimensions, VSync/cap/refresh, time scale, warmup/cache state, power/thermal conditions and profiler state |
| Coverage | Requested and observed sequence/time ranges, complete/partial/invalid outcome, gap reasons, trigger/stop reason, actual lead-up/recovery, and raw/detail/log loss counters separately |
| Channels | Name, unit, source API/revision, scope, aggregation, availability, measurement enabled state, observation time and source-frame/age if actually known. Unknown age remains unknown |
| External evidence | Original file hash, tool version/options, process/swap-chain or thread identity, clock units/domain, correlation method, raw anchor pairs and error bounds; no implicit joining |

Two exact-pin findings require care (research R03/R08). The process/physics timing
monitors publish periodic window maxima. The GLES3 query collector reads earlier
GPU results, and viewport getters expose stored durations without a source-frame
ID; toggling measurement does not itself clear those durations. The current render
probe already guards disabled measurement. Preserve that guard and its unverified
freshness label; test re-enable and sparse viewport updates before tightening claims.
Do not hard-code a two-callback offset or apply an OpenGL implementation detail to Metal.

Unknown runtime identity must not be filled from the checkout running `debugctl`.
The current capture ID combines PID, engine origin and epoch; it is not a proven
unique identifier across process replacement. Require a verified launch-instance
receipt before joining snapshots across connections. If it is unavailable, retain
the files separately and mark the join unverified. Never export the session token.
An unavailable channel must not become zero. A nominally nanosecond integer is a
representation, not a measured accuracy. Preserve the original capture and bounded
validation rules when enriching reports; define reader compatibility before adding
required fields or changing a major format version.

## 5. Automatic incident capture without an unbounded recorder

Start with **one owned client collector**, one shot per explicit arming. Save the
verified session identity, epoch, `frames_total` cursor and cumulative selected-event
counters at arm time; do not reset another client's history. The initial proposed
poll policy is 500 ms, at most 120 selected rows, `samples=false`, `events=0`.
Use `frames_total` as the last recorded sequence within that epoch. With `window=0`,
the existing `last_sequence` is zero even after recording; it describes a nonempty
selected window only. Empty startup/arm polls must still advance the session cursor.
These are bounded engineering defaults to measure in S6, not perceptual thresholds.
Even a summary scans and sorts its window, so compact JSON is not proof of cheap work.

Relative/stall triggers use increments in their cumulative counters. Record the
sequence bracket between polls, then retrieve the first raw snapshot and locate
matching flags inside the retained bracket. If the rows are gone, preserve the
counter observation with an unknown exact trigger location and partial coverage.
For sustained slowdown, the first policy is **30 consecutive over-budget samples**
inside a 120-row observation window; this is a frame-count condition, not a fixed
duration. Validate `1 <= K <= W <= 7200` if made configurable. Request only a window
known from the previous poll to fit after the arming sequence, and confirm its
reported range before evaluating it. The current summary exposes longest-run
aggregates, not cumulative over-budget/episode counters. Verify any candidate in
the raw flags before assigning a trigger interval.

Track the union of examined summary ranges. Disjoint/late windows leave detection
coverage gaps; an untriggered run then cannot certify absence of sustained slowdown.
Once at least K post-arm rows exist, consecutive test windows also need at least
K−1 rows of overlap to cover every possible K-frame run across their boundary.
Contiguous windows alone can split a 30-frame run into two undetected 15-frame tails.
Preserve the whole initial shorter prefix until a K-row window can be examined.
If required overlap is absent, mark detection coverage unknown even when no raw
sequence is missing; do not claim continuous sustained-slowdown screening.
Positive detections remain useful. Do not infer missing budget-episode totals from
cumulative stutter/stall counters. Current event counts count frames, not episodes.

Capture available lead-up/trigger rows promptly, then one bounded recovery snapshot.
The proposed incident manifest references both immutable original files. A separate
incident reducer may deduplicate their union only after validating launch identity,
capture/epoch, sequences and exact overlap values. **Never export this union or a
cropped interval as a v1 frame snapshot:** the existing v1 validator requires a
newest-window report and caps it at 7,200 rows.

The collector has `armed`, `collecting_recovery`, `complete`, `partial`, `cancelled`,
`failed` and `expired_without_trigger` outcomes. There is no automatic rearm or
promise of episode deduplication across separate armings. A new arming records a
new cursor and explicit policy. Set maximum poll count/duration, recovery frames/time
and total output before arming. The first delivery caps raw snapshots at two, each
within the current 16 MiB/7,200-row v1 bounds; the incident union at 14,400 rows;
manifest at 1 MiB; and generated incident files at 128 MiB total. These payload caps
do not state Python heap use, which needs measurement. Reject an over-limit request
or output with an explicit outcome; no unbounded retry or retained history.

A storm extends neither the deadline nor storage indefinitely. Preserve additional
proven event-counter changes; unknown episode totals remain unknown. A repeated
sequence with different values invalidates the join. Interrupted recovery retains
the first capture and an explicit partial/cancelled outcome.

Reusing transport requires a bounded collector receive path: enforce cumulative
reply bytes while reading, an absolute monotonic deadline across partial reads,
request identity, and cancellation. Existing `debugctl.request()` waits for a newline
using a per-socket timeout and accumulates bytes before exporter validation; it
cannot by itself establish these caps. Keep the bridge's normal protocol behavior
compatible and apply the collector's stricter v1 limits before retaining a full reply.

Completeness is relative to the requested incident interval. Ring eviction before
that interval is expected; eviction inside it is a gap. Late polling may miss
lead-up even when cumulative event counts prove an event occurred. Label the lost
scope explicitly and preserve the available suffix. Startup with insufficient
history cannot claim complete prehistory. Reset/policy change, process restart or
clock discontinuity ends the incident; it must not merge separate epochs.

A recovering freeze becomes a long callback interval only when the main thread
resumes. A permanent hang may provide only client timeout and the last received
snapshot. Timeout is not an exact hang start, a measured long frame, or permission
to kill another session. Recovery collection must stop promptly on cancellation;
files are written outside the simulator and completed outputs remain immutable.

If measured polling/query overhead or missed retention makes this client design
inadequate, reopen a bounded in-engine trigger/freeze ticket with its own cost and
ownership contract. It is not a prerequisite assumed in S2. Renderer captures
requested after a hitch describe a subsequent frame, not the completed slow frame.

## 6. Attribution and external tools

Use evidence labels such as `observed_long_callback`, `budget_episode`,
`loading_correlated`, `physics_catchup_observed`, `rendering_correlated`,
`presentation_anomaly_observed`, `motion_jitter_reported` and `unattributed`.
These are proposed report labels. A causal finding needs a repeatable controlled
intervention plus relevant timeline evidence; simultaneous counter changes are
insufficient. Avoid ranking a single supposed cause with an invented probability.

Instrument existing loading request/ready/retrieval/instantiate/attach boundaries
before considering new loaders. Preserve latest-selection cancellation and the
existing preparation cache. Compare camera motion separately from callback pacing.
Keep physics cap pressure as a consequence: either a CPU or rendering stall can
force catch-up. Do not change 240 Hz or interpolation to improve a diagnostic score.

| Observed question | Optional evidence route | Eligibility / limit |
| --- | --- | --- |
| Script or main-thread work? | Godot standard profiler, then self/inclusive attribution | Profiled reproductions have their own overhead; nested costs cannot be summed |
| Rendering pass or viewport? | Existing `render`/`ablate`, Visual Profiler | Actual renderer and timing freshness determine coverage; overlapping passes are not additive |
| Windows display/presentation anomaly? | PresentMon, optionally CapFrameX for independent analysis | Windows; OpenGL/Vulkan `Runtime=Other` and GPU scheduling have documented accuracy caveats |
| Windows wait/I/O/scheduler gap? | WPR/WPA; PIX timing where applicable | PIX graphics analysis requires an eligible D3D12 route; standard OpenGL is not that route |
| Linux pacing/system context? | MangoHud plus `perf sched` for an unexplained scheduling gap | Actual OpenGL/Vulkan path, sensor cadence, permissions and present overrides recorded |
| Apple Silicon Metal discrepancy? | Instruments Game Performance / Metal timeline | Native Metal run; display, CPU and GPU evidence remain separate observations |
| Unexplained supported GPU pass? | Nsight, Radeon GPU Profiler, RenderDoc | Verify vendor/API/version first; RGP excludes the standard OpenGL and Metal routes; capture overhead is separate |

Research R09–R21 supplies sources and exact applicability. No external profiler
must be installed for basic frame capture. Reuse local files; do not add automatic
uploads. Third-party code reuse would require a separate license/version review.

For cross-process alignment, add an explicit engine observation timestamp sampled
while handling the identified request, paired with its collector send/receive times.
The existing last-frame `sample_end_usec` may predate the request and is not a valid
bracketed observation. Retain repeated valid anchors and their round-trip bounds
across the run; absent a request-time stamp, alignment remains unavailable.
A midpoint is an estimate under delay asymmetry;
fit/drift/residual and validity interval must be explicit. Restart invalidates the
mapping. If uncertainty is too large for the questioned interval, show side-by-side
unaligned evidence. Converting both clocks to microseconds does not synchronize them.

## 7. Comparison and validation design

S4 extends the [GOD TEST comparison contract](god-test.md#10-comparisons-and-observer-cost)
and [existing optimization protocol](optimization-priorities.md#6-acceptance-and-stop-rules).
Match workload, renderer, engine, hardware/driver, display, detector policy, metric
formula and sample policy; declare the intended A/B intervention. Different source
revisions are allowed when that is the experiment, but unknown identities are not
qualified equivalence. Never pool cold loading, menus and steady flight into a
single improvement percentage or treat adjacent frames as independent trials.

Retain all per-run raw reports, exclusions and failed runs. Compare frame-time tails,
maxima, incident frequency/duration, budget excess, simulation pace and completeness,
with run-level variation and paired absolute/relative changes. Zero baseline counts
need an absolute delta, not division by zero. Small 0.1% tails stay descriptive.
The existing product protocol starts with 10 s warmup, 60 s measured flight and
three alternating pairs; loading uses separate first-use/warm repetitions. Stricter
owning-track gates prevail. These are project policies, not universal statistical thresholds.

| Test group | Cases / required observation |
| --- | --- |
| Detector characterization | 60/120/144 Hz synthetic cadence; exact factor/difference boundaries; isolated stall; sustained 60→30 FPS; alternating cadence; startup and phase change. Preserve v1 flags when running an offline reference |
| Statistics | Tail sizes around 100/1,000, ties, maxima, paired slow episodes, duration-weighted versus sample-weighted metrics, malformed/nonfinite inputs |
| Capture integrity | Empty arm/poll cursors, ring rollover, duplicate/conflicting/no-overlap snapshots, union over 7,200 rows, late/disjoint/under-overlapping test windows and a split K-frame run, persistent slowdown, missing prehistory, reset/policy/reused-PID restart, cancellation, trickled/oversized replies, no recovery, disk failure and storm; preserve precise coverage, limits and one-shot outcomes |
| Metric freshness | Periodic-max monitor pulse, measurement off/on, disabled SubViewport, unsupported/headless route; no stale value promoted to a frame-local measurement |
| Export/interoperability | Existing v1 fixtures round-trip; actual HTML/CSV inspection and Perfetto import verify units/counts/markers; separate synchronous tracks for independent durations; clocks shifted deliberately remain unaligned |
| Observer cost | Same reproducible workload with bridge absent, history enabled, bounded collection, and optional deep profiler in separate matched runs. Use an independent timing source for the bridge-absent case; never subtract estimated recorder cost from frames |
| Rendered product | 1080p first; Home→immediate Fly, warmed flight, aircraft/scene first use, camera/reset/pause/focus, cap/refresh configurations; Windows/Linux/Apple evidence kept separate |

S6 cannot pass solely from injected sleeps, headless tests, VM rendering or prettier
reports. Retain software proof separately from a reproduced organic incident and
native hardware qualification. Before adding any diagnostic channel, freeze an
observer-cost ceiling for the named target in the campaign manifest, then require
both that ceiling and the existing whole-workload gates. No unmeasured universal
overhead guarantee is introduced by this plan.

## 8. Deferred ideas and reopening conditions

| Idea | Current disposition | Reopen when |
| --- | --- | --- |
| MAD or centered-median alternative detector | Offline characterization only; keep causal live v1 policy | A retained corpus demonstrates a specific miss/false-positive improvement, including zero MAD and phase shifts |
| Native Tracy zones / Apple signposts | Deferred S7 | A real native attribution gap survives standard tools, and build/overhead scope is justified |
| Automatic GPU frame capture | Deferred S7 | Reproducible supported renderer case; subsequent-frame semantics and perturbation are accepted |
| JSONL continuous history | Deferred S7 | A campaign needs longer coverage than bounded snapshots; schema, gap records, disk cap and interrupted-tail recovery are specified |
| Multi-clock native Perfetto export | Deferred S7 | Verified clock receipts and a useful simultaneous trace exist; current Chrome JSON stays supported |
| Shader warmup, threading, dynamic resolution or lower physics cadence as a generic fix | Not part of diagnostic adoption | The owning track has a measured cause and its own correctness/visual acceptance; lower physics cadence is not an instrumentation optimization |

The research register maps every investigation to these steps. Close each runtime
step only with evidence tied to its actual candidate; this documentation update
does not re-run or expand the historical R15 test results.
