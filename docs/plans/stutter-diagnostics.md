# Stutter diagnostics: evidence and implementation plan

Owner: PT debug tooling, coordinated with VQ/DT performance, GOD TEST, UI loading,
CAM and simulation owners. Prefix: **PT1h-R15-S0…S7**, subordinate to PT1h-R15.
Updated: **2026-11-19** (lead audit, merge to `main` and S1a/S2a implementation).

**Status:** S0 research, S3a offline analysis, **S1a capture identity and
S2a automatic session watch are implemented** with focused software checks and a
headless live-protocol probe. Rendered 1080p qualification, observer-cost
measurement and S3–S7 remain open. Commands and metric definitions live in the
[debug guide](../../tools/debug/README.md#frame-pacing-and-stutter-captures-pt1h-r15).
Dated evidence: [24 investigations](../research/release-readiness/PT1h-R15/research-2026-11-19.md),
[tool integration](../research/release-readiness/PT1h-R15/tools-integration-2026-11-19.md) and
[watch implementation](../research/release-readiness/PT1h-R15/watch-2026-11-19.md).
The [global performance plan](global-performance-visual-quality.md#4-measurement-and-acceptance-contract)
owns product gates; this plan does not replace them.

## 1. Outcome

Make an intermittent freeze, stutter or FPS drop produce an inspectable incident
without someone having to capture at the right moment: what was observed, which
interval is covered, what happened before and after it, which measurements are
missing, and which experiment can distinguish plausible causes. A report may remain
unattributed. A smooth callback trace does not prove smooth camera motion,
displayed frames or low input latency.

## 2. Audit of the branch plan (2026-11-19)

The lead reviewed the merged branch plan against the code, with an independent
review and measurements on the pinned engine. Accepted corrections:

| Finding | Evidence | Change |
| --- | --- | --- |
| Bridge `over_budget` uses `target_fps` (default 60); a fall from 140 to 75 FPS sets no flag, and changing the target resets every client's history | `debug_bridge.gd` policy/epoch code | Triggers run client-side on raw `wall_usec` with the watcher's own budget and a route-scoped relative-drop detector |
| Polling 120-row summary windows every 500 ms misses rows above 240 FPS | 150+ rows per poll exceed the window by construction | Incremental `since=<cursor>` reads every row exactly once; gaps are counted |
| A 7,200-row v1 fetch costs about **51 ms** on the game thread | Measured: 30-row lean poll 0.33 ms, 120 rows 0.95 ms, 600-row v1 4.4 ms, 1,800 rows 12.9 ms | Rows come from cheap lean polls; the v1 snapshot at incident close is capped (default 1,200 rows) and its own perturbed interval cannot trigger |
| Any bridge request turns on 20 Hz `state` publishing on the game thread for 30 s | `_route_line` / `_process` snapshot code | `passive=true` requests do not refresh that timer |
| A cursor from another epoch or process could select foreign rows | Epoch/PID reuse | `epoch` guard on `since`; random `launch_instance` in `ping` and `frames` |
| One-shot arming with a two-snapshot union reducer delays the goal | Plan §5 of the branch | Bounded multi-incident watch; each incident keeps client rows plus one ordinary v1 snapshot |
| No whole-session view beyond the 7,200-row ring | Ring covers ~2 min at 60 FPS | Streaming per-segment, per-route statistics, exact slow tail, per-second series |
| `unittest discover -s tools/debug` failed after the merge | Branch's `tools/debug/test_frame_capture.py` shadowed by `tools/godot/` on `sys.path` | `test_debugctl.py` appends instead of prepending the godot path |

Retained from the branch plan: live detector policy and v1 formulas, causal labels
as observations only, separate clock domains, no automatic upload, no default
renderer/physics change, optional platform profilers and GOD TEST ownership of
campaign comparisons.

## 3. Scope and ownership

The runtime boundary is `app/debug/debug_bridge.gd`, `frame_statistics.gd` and
`render_probe.gd`. Client integration owns `tools/debug/` (`debugctl.py`,
`frame_capture.py`, `frame_watch.py`, MCP), narrow offline changes in
`tools/godtest/analysis.py`, their focused tests, guides and R15 research. UI
loading and camera markers need their owners' seams. GOD TEST owns full-session
orchestration and comparisons; PT/VQ/DT own metric meaning and hardware
qualification; SF/FL retain simulation and replay contracts.

Keep diagnostics opt-in and bounded. Reuse session admission and the existing
transport/exporter. Keep detailed profiling and screenshots outside acceptance
timing runs. An external tool's availability does not establish compatibility
with the running engine, API or hardware.

### Existing tool integration

| Existing path | Use and boundary |
| --- | --- |
| `debugctl frames`, `frame_capture.py` | One bounded v1 snapshot or offline reanalysis (S3a) |
| `debugctl frames watch`, `frame_watch.py` | Session watch, incidents and session statistics (S2a) |
| `tools/godtest/analysis.py`, `runner.py` | Scenario runs, frozen inputs, phase reports; campaign comparisons stay here |
| `research/performance/frame_diagnose.py` | Native fixed-duration diagnosis; strict 16.667 ms default differs from the debug budget plus tolerance |
| `app/render/frame_samples.gd`, `frame_diagnostics.gd` | Native/GOD TEST frame stream; no parallel full-flight recorder |
| `tools/godot/run_checked.py`, `resource_samples.py` | Checked completion and sparse process CPU/RSS/I/O |
| `tools/godot/incident_bundle.py`, `perfetto_export.py` | Native packaging and timelines; debug formats need explicit adapters |
| `tools/testqueue/`, debug launcher | Admission, session handle, owned teardown |
| `tools/graphics/`, bridge `render` / `ablate` | Targeted rendering experiments, separate from acceptance timing |

## 4. Ordered deliveries and proof

| ID | Work and dependency | Status / required proof |
| --- | --- | --- |
| **S0** | Branch audit, 24 investigations, reconciled plans | **Complete** (documentation only) |
| **S3a** | Offline episodes/import, GOD TEST phase slow time | **Implemented**; software checks in the tool-integration record |
| **S1a** | `launch_instance`, cached `source`, `request_usec`, `since`/`epoch`/`lean`, `passive`, build fields; development runs keep `runtime_revision: not_observed` | **Implemented**: 68 frame-history checks; live probe |
| **S2a** | `frames watch`: triggers, incidents, gaps, freezes, segments, reconciliation, reports | **Implemented**: 28 deterministic client tests; three live headless watches with induced 300 ms/1.2 s stalls, a 4 s freeze and an epoch reset; independent candidate review resolved |
| **S2b** | Rendered 1080p qualification on the owner's machine: real flight, menus and first-use loads; observer cost with bridge absent / history only / watch running in matched runs | Open. Freeze an observer-cost ceiling first; do not subtract estimated cost from frames |
| **S1b** | Launcher-asserted source revision: `debugctl launch` passes git HEAD plus dirty state; bridge reports it as `launcher_revision`, never as runtime identity | Open; one small slice |
| **S2c** | Agent access: MCP start/status/stop for a background watch with the same policy and outputs | Open; long synchronous MCP calls are not acceptable |
| **S3** | Scoped phase markers (loading request/ready/attach, camera switch, reset/respawn, pause/focus) as row-aligned context | Open; owners' seams; loading/camera/physics/render symptoms stay distinct |
| **S4** | Offline comparison of two watch or capture directories per route/segment through existing GOD TEST/optimization protocols | Open; refuse mismatched policy/workload; per-run paired deltas; no pooled menus+flight |
| **S5** | Optional native sidecars (PresentMon, MangoHud, Instruments) with clock correspondence anchored on `request_usec` | Open; unsupported/unaligned channels stay explicit |
| **S6** | Rendered incident, observer-cost and package qualification across Windows/Linux/Apple | Open; 1080p first; separate platform outcomes |
| **S7** | Conditional deeper attribution or long recording | Deferred (see §8) |

Next order: S2b → S1b → S2c → S3 → S4 → S5/S6. Each step is separately reviewable.
No step closes product performance gates merely by producing a report.

## 5. Watch contract (S2a)

The authoritative command and output description is in the
[debug guide](../../tools/debug/README.md#automatic-session-watch-pt1h-r15-s2).
Design constraints that later work must preserve:

- **Incremental, passive reads.** `frames since=<cursor> epoch=<E> lean=true passive=true`
  returns rows after the cursor, exact cumulative totals and identity only. A
  cursor from another epoch returns no rows; another `launch_instance` starts a
  new segment and re-reads that history from sequence 1. Rows evicted before a
  poll are counted gaps; counts in such segments are lower bounds.
- **Client-side triggers on raw intervals.** `stall` and `stutter` use the
  bridge's recorded flags. `sustained` counts consecutive intervals above the
  watcher's budget (default: the bridge target) and re-arms after in-budget rows.
  `drop` compares the median interval of a 1 s window with the median of the
  preceding 10 s on the same route, with settling, an absolute floor, hysteresis,
  a frozen reference and a baseline rebuilt after recovery (about 6 s blind after
  each restart). `hang` is a `frames` poll timed out after `hang_s` while two
  `ping` replies (network thread) show the same engine frame; its duration is a
  client-side lower bound and the resumed interval is the measurement.
- **Failure handling.** Any end (duration, interrupt, lost bridge, protocol error)
  still writes the session files; 16 MiB of the output budget is reserved for them.
- **Incidents.** Lead-up and recovery are row counts; triggers during an open
  incident join it; `max_incidents` bounds captures while later triggers stay
  counted. Each incident keeps its client rows (`openrc-debug-frame-incident v1`)
  and, when the segment is unchanged, one bounded v1 snapshot exported with the
  standard HTML/CSV/Perfetto pipeline. The interval perturbed by that fetch is
  excluded from triggering and counted.
- **Statistics.** Per segment and route, never pooled across them. Exact counts,
  exact slowest-tail lows up to 5,000 retained intervals, histogram percentiles
  with stated resolution, and a per-second series. Bridge totals reconcile the
  watched rows exactly when the segment has no gap.
- **Limits.** Not presented frames, CPU busy time or GPU completion. Triggers are
  screening rules, not perceptual thresholds or causes. Polling still costs a
  small amount of game-thread work and flags the next interval `diagnostic_query`.

## 6. Capture identity and alignment

Unknown runtime identity must not be filled from the checkout running `debugctl`.
Development runs report `build_source: development` and `runtime_revision:
not_observed`; exported builds report their embedded commit. A launcher-asserted
revision (S1b) is labelled as such. Never export the session token.

`request_usec` is the engine clock sampled while handling each request. A future
sidecar alignment (S5) pairs it with client send/receive times, retains repeated
anchors and their round-trip bounds, and treats a midpoint as an estimate under
delay asymmetry. A restart invalidates the mapping. Without anchors, show
unaligned evidence side by side.

Pinned-engine caveats (research R03/R08): process/physics timing monitors publish
periodic window maxima; GLES3 timestamp queries are read late; viewport getters
have no source-frame ID. Keep `unverified_freshness`; do not hard-code a callback
offset or apply an OpenGL detail to Metal.

## 7. Attribution and comparison

Use observation labels such as `observed_long_callback`, `budget_episode`,
`loading_correlated`, `physics_catchup_observed`, `rendering_correlated`,
`presentation_anomaly_observed` and `unattributed`. A causal finding needs a
repeatable controlled intervention plus timeline evidence. Instrument existing
loading boundaries before considering new loaders. Physics catch-up is a
consequence; do not change 240 Hz or interpolation to improve a diagnostic score.

| Observed question | Optional evidence route | Limit |
| --- | --- | --- |
| Script or main-thread work? | Godot profiler (`launch --script-profile`, `profile`) | Profiling perturbs timing; nested costs are not additive |
| Rendering pass or viewport? | `render` / `ablate`, Visual Profiler | Renderer and timing freshness define coverage |
| Windows presentation anomaly? | PresentMon, optionally CapFrameX | OpenGL/Vulkan `Runtime=Other` caveats |
| Windows wait/I/O/scheduler gap? | WPR/WPA; PIX where eligible | PIX graphics needs D3D12, not the standard OpenGL route |
| Linux pacing/system context? | MangoHud, `perf sched` | Record actual API path and permissions |
| Apple Silicon Metal? | Instruments Game Performance / Metal | Native Metal run; separate observations |
| Unexplained supported GPU pass? | Nsight, RGP, RenderDoc | Verify vendor/API/version; capture overhead separate |

Comparisons (S4) extend the [GOD TEST contract](god-test.md#10-comparisons-and-observer-cost)
and the [optimization protocol](optimization-priorities.md#6-acceptance-and-stop-rules):
match workload, renderer, engine, hardware/driver, display, detector policy and
metric formulas; retain every per-run report and failure; compare tails, maxima,
incident frequency/duration and budget excess with paired absolute and relative
changes. Never pool cold loading, menus and steady flight into one percentage.

| Test group | Required observation |
| --- | --- |
| Detector characterization | 60/120/144/240 Hz cadences, exact boundaries, isolated stall, sustained 60→30, above-budget drop, alternating cadence, route change, startup |
| Capture integrity | Empty cursors, rollover, eviction gaps, epoch/launch change with equal epoch numbers, freeze/lost bridge, storms, incident overlap and limits — covered for S2a by `test_frame_watch.py` |
| Metric freshness | Periodic-max pulses, measurement off/on, disabled SubViewport, headless |
| Observer cost (S2b) | Same workload with bridge absent, history only and watch running, in matched runs with an independent timing source |
| Rendered product (S2b/S6) | 1080p first; Home→Fly, warmed flight, first-use aircraft/scene, camera/reset/pause/focus, cap/refresh; Windows/Linux/Apple separate |

S6 cannot pass from injected sleeps, headless runs, VM rendering or prettier reports.

## 8. Deferred ideas and reopening conditions

| Idea | Disposition | Reopen when |
| --- | --- | --- |
| In-engine O(1) trigger counters | Deferred | Measured polling cost or missed rows make the client design inadequate |
| MAD/centered-median detector | Offline characterization only | A retained corpus shows a specific improvement |
| Native Tracy zones / Apple signposts | Deferred S7 | A native attribution gap survives standard tools |
| Automatic GPU frame capture | Deferred S7 | Reproducible supported renderer case; subsequent-frame semantics accepted |
| JSONL continuous raw history | Deferred S7 | A campaign needs raw rows beyond incidents and per-second statistics |
| Multi-clock native Perfetto export | Deferred S7 | Verified clock receipts and a useful simultaneous trace exist |
| Shader warmup, threading, dynamic resolution, lower physics cadence as generic fixes | Not diagnostic work | The owning track has a measured cause and its own acceptance |

The research register maps each investigation to these steps. Close each runtime
step only with evidence tied to its actual candidate.
