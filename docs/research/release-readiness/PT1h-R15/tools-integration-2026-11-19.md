# PT1h-R15-S3a: tool integration and sustained slowdown analysis

Date: **2026-11-19**. Owner: PT debug tooling with GOD TEST/VQ/DT.
Branch: `perf/stutter-diagnostics-2026-11-17`.
Inspected branch base: `717b1ccc57603ce8d7d04003574a7fe4fcd2b52f`.

This follow-up adds **eight investigations, R25–R32**, to the existing
[24-investigation record](research-2026-11-19.md), and implements a bounded offline
slice in the existing tools. These include repository integration audits and
external primary-source research; they are not eight hardware experiments.
The [active plan](../../../plans/stutter-diagnostics.md) owns remaining work.
Commands and schema interpretation live in the [debug guide](../../../../tools/debug/README.md#offline-slowdown-analysis-pt1h-r15-s3a)
and [GOD TEST guide](../../../../tools/godtest/README.md#measurements-and-reports).

## Findings that changed the implementation

The live bridge already retains over-budget flags and aggregate slow-run statistics.
Its exported HTML emphasized individual worst frames, leaving a stable low-FPS run
less visible when the adaptive stutter detector had no new event. The implemented
extension locates all selected-window runs, exposes their observed duration and
coverage, and keeps the existing raw snapshot and detector flags intact.

The GOD TEST audit also found a correctness defect: a stream without `phase_index`
could reduce to no phase samples, followed by zero-valued fallback percentiles.
Those values could appear to satisfy pacing targets. The reducer now requires that
channel, derives phase percentiles from verified samples, and keeps unavailable
measurements and target results null. A completed requested phase without samples
is ineligible. These changes improve diagnostic evidence, not measured runtime FPS.

## R25 — Existing tools are complementary, but their inputs are not interchangeable

**Evidence.** The [debug exporter](../../../../tools/debug/frame_capture.py) validates
a newest-window `openrc-debug-frames v1` ring of at most 7,200 intervals. The
[GOD TEST collector](../../../../research/performance/godtest/frames.gd) writes
`openrc-godtest-frames-v1`, with scenario-event completion and a frame-stream sidecar.
The [native analyzer](../../../../research/performance/frame_diagnose.py),
[incident bundle](../../../../tools/godot/incident_bundle.py) and
[native Perfetto exporter](../../../../tools/godot/perfetto_export.py) depend on the
fixed-duration native validator. Native bundling also expects checked-run evidence
and root `engine.log`; GOD TEST retains execution/runtime files and `bridge/engine.log`.

**Decision.** Extend the two existing offline reducers within their formats. Document
the routing boundary in all three tool guides. Defer a shared attachment envelope
until source/session identity, coverage and clock correspondence have defined receipts.
No format relabeling, fabricated simulation fields, or new full-flight recorder.

**Check.** Existing native tools are unchanged; focused debug/GOD TEST regression
tests exercise their own accepted formats. The integration map identifies the
owners of future adapters rather than claiming current cross-format compatibility.

## R26 — Stable low FPS needs episode coordinates and time-weighted burden

**Evidence.** [FrameStatistics](../../../../app/debug/frame_statistics.gd) already
calculates slow count, occupied time, nominal-budget excess and longest run. The
[bridge](../../../../app/debug/debug_bridge.gd) retains exact live flag bits even
when event details are suppressed. A 33.333 ms steady cadence can exceed a 60-FPS
budget while producing no new relative-stutter or 50-ms-stall details. The native
analyzer already groups bursts, but uses a strict 16.667-ms default and ranks its
bounded returned bursts by peak interval first.

**Decision.** Group maximal consecutive recorded bit-8 runs; do not recreate the
relative detector, split at route changes, or drop diagnostic-query rows. Emit all
episodes in a separate bounded analysis file, and display the 20 longest by observed
duration in HTML. Keep longest-by-count and longest-by-duration IDs separate.
Time share and frame share answer different questions; preserve both alongside tails.

**Check.** The 20/10/20-ms vector has two of three slow rows, 80% slow wall time and
60 callbacks/s. A 30-frame stable slowdown without event details is detected. Tests
also cover no slow frames, split runs and distinct count/duration maxima.

## R27 — A capture boundary does not establish onset or recovery

**Evidence.** [NIST's censoring guidance](https://itl.nist.gov/div898/handbook/apr/section1/apr131.htm)
describes observations ending before an event's time becomes known. Applied here
as an analogy, a run touching the retained window edge has an unobserved onset or
recovery. Even sequence 1 follows recorder priming; it provides no earlier frame.

**Decision.** Record `left_censored` and `right_censored`. The observed length is a
lower bound. `observed_sustained` says whether the retained run meets K;
`full_episode_sustained` is true when K is observed, false only for a shorter run
with both boundaries observed, otherwise null. This is a descriptive classification,
not survival analysis or a statistical confidence claim.

**Check.** One-, 29-, 30- and 7,200-frame all-slow windows exercise the boundary
states. Rollover fixtures keep ring eviction separate from retained-but-unselected
rows. Event-detail omission does not become a missing raw-frame interval.

## R28 — Consecutive-run screens miss intermittent slowdown; keep context

**Evidence.** [Google's SRE alerting chapter](https://sre.google/workbook/alerting-on-slos/)
shows that a brief recovery resets a sustained-threshold timer and can prevent an
alert despite substantial repeated failures. This is a detector-design analogy,
not a game-performance policy. [Android JankStats](https://developer.android.com/topic/performance/jankstats)
associates frame timing with application/UI state and stresses keeping observation
callbacks short. The bridge already records route at interval start, while GOD TEST
assigns a whole interval to the phase observed at its end.

**Decision.** Keep a configurable K-frame screen, default 30, beside time-share,
tail and isolated-stall views. Describe sampled route changes as context; do not
infer exact transition times or causes. Perform the new reduction in Python after
capture, adding no scene access or recorder work to the simulator loop.

**Check.** Two 29-frame slow runs separated by one fast interval have no observed
K=30 run but exceed 99% slow wall time in the test fixture. A route change and a
query-marked interval do not split a continuous run. Unknown edge continuations
remain null, rather than false full-episode conclusions.

## R29 — Presentation metrics provide inspiration, not replacement thresholds

**Evidence.** [Android Games Slow Sessions](https://developer.android.com/games/optimize/vitals/slow-session)
uses the proportion of slow presentation intervals, with 50-ms and 34-ms targets,
and starts monitoring after one minute. Its source is SurfaceFlinger observations
of app-owned surfaces. Those presentation intervals and coverage are different
from OpenRC's bridge callbacks and startup/flight phases.

**Decision.** Adopt explicit scope, sample burden and coverage reporting. Do not
import Android's thresholds, exclude the first minute, call callbacks displayed
frames, or present K=30 as a perceptually validated rule. Preserve OpenRC's existing
target plus tolerance in debug captures and GOD TEST's separate fixed thresholds.

**Check.** Reports state callback scope and selected-window coverage. Strict equality
tests use 20,000/20,001 microseconds at a 20-ms debug threshold and 16,667/16,668
microseconds at GOD TEST's 16.667-ms threshold. Integer units establish representation,
not independently measured instrument accuracy.

## R30 — Offline imports need bounded, unambiguous JSON and honest precision

**Evidence.** [Python's JSON documentation](https://docs.python.org/3.11/library/json.html)
describes acceptance of repeated object names and non-finite numbers by default,
and recommends limiting input size. [Godot JSON documentation](https://docs.godotengine.org/en/4.5/classes/class_json.html#class-json-method-stringify)
describes full-precision float decoding; the inspected bridge explicitly passes
`full_precision=true`. However, the existing v1 validator uses approximate policy
equality. A new exact flag/threshold comparison cannot silently redefine that contract.

**Decision.** Read at most 16 MiB plus one sentinel byte before decoding, require
UTF-8, reject repeated keys/non-finite values, then reuse bounded v1 validation.
Preserve recorded flags and expose reconstructed-threshold disagreements. Any
disagreement makes policy screening uncertain and total budget excess unavailable;
it does not rewrite or automatically reject a formerly valid snapshot. This warning
also appears in the standalone Perfetto metadata and episode labels/context.

**Check.** Malformed, deeply nested, oversized, duplicate-key, non-finite and invalid
snapshot cases fail before bundle creation. Conflicting flags retain their original
membership without producing negative excess. Offline argument-error tests assert
no live-session discovery/request; optional live summary fields are not required
for offline text output. Re-export preserves values and the source file, and binds
its new `frames.json` bytes with SHA-256; it does not claim byte-identical reserialization.

## R31 — Verified phase reduction must not turn missing measurements into success

**Evidence.** The inspected [GOD TEST reducer](../../../../tools/godtest/analysis.py)
accepted a metric schema without `phase_index` and used zero percentiles when a
phase had no reduced samples. It also retained a phase's current consecutive count
across intervening phases. [Runtime sampling](../../../../app/debug/godtest_driver.gd)
provides phase index at interval end, while phase event timestamps are sampled
separately; their duration is not the sum of attributed frame intervals.

**Decision.** Require the phase channel, reduce percentiles from verified samples,
and mark missing completed requested phases ineligible. Unavailable pacing targets
remain null. Add callback FPS, slow-wall share, run count/duration and frame share
to the existing threshold records. Break a run on any adjacent phase-index change,
including across chunks, and use attributed wall time as the FPS/share denominator.
Maximum run length and maximum run duration are independent statistics.

**Check.** Tests cover a missing channel, a completed phase without samples, supplied
zero summaries contradicted by the verified stream, cross-chunk phase changes,
time-weighted shares, threshold equality and existing corruption/comparison cases.
The comparison's single-pair and matched-transition limitations remain in force.

## R32 — Reuse ownership, evidence and trace tracks before adding integrations

**Evidence.** [Test queue](../../../../tools/testqueue/README.md) and the debug launcher
own live admission and teardown. [GOD TEST runner](../../../../tools/godtest/runner.py)
freezes inputs and can reuse the existing resource sampler. Native timelines require
their own identity/clock receipts. [Perfetto's external-format documentation](https://perfetto.dev/docs/getting-started/other-formats)
supports Chrome JSON complete events and requires duration events to nest on their
track. GitHub comparison before this change showed 2 branch-only commits and 60
main-only commits, with main at `372053ac9448942e154801e3299cf77669161d08`.

**Decision.** Add a separate logical episode track, carrying local-clock scope,
policy and quality. Keep source frame slices intact. Offline reanalysis performs
no live-session lookup and needs no launch permission. Document format-aware
attachment and clock adapters as future work. Before runtime integration, reconcile
upstream changes in `debug_bridge.gd`, `render_probe.gd` and `frame_diagnostics.gd`;
the inspected upstream list did not change the Python files extended here.

**Check.** Trace fixtures verify exact relative start/duration, distinct track IDs,
all raw flags and standalone uncertainty. No main merge, application launch,
resource sampling or native profiling was performed for this offline delivery.

## Verification and limits

Stable-candidate checks on Linux/Python 3.12.14:

| Check | Result |
| --- | --- |
| `python3 -m unittest discover -s tools/debug -p 'test_frame_capture.py'` | 18 tests passed, including existing validation/escaping/cleanup cases and the new episode/import cases |
| `python3 -m unittest discover -s tools/debug -p 'test_debugctl.py'` | 79 tests: 78 passed, one existing native-Windows locking test skipped on Linux |
| `python3 -m unittest discover -s tools/godtest -p 'test_*.py'` | 23 tests passed, including phase reduction and comparison guards |
| Python compilation of the three changed production modules | Passed |
| `git diff --check` | Passed |
| Documentation validation against the candidate Git tree | 27 new local links/anchors across 10 changed Markdown files passed; R25–R32 each has evidence, decision and check |

Total: **120 tests, 119 passed and one platform-specific skip**. These are focused
software checks, not a full app suite or remote CI verdict. The prior R15 engine/
runtime results remain historical and are not reruns of this change.

A standalone 100-row synthetic capture exercises the real offline CLI and produces
all five files, with three episodes, one observed K=30 run and an unknown final
boundary. Source-value equality and the exported JSON hash matched. Its data are
deliberately synthetic, including steady slowdown,
an isolated stall and a window-ending short run; they establish software behavior
only. No measured FPS improvement, GPU cause or native 1080p qualification is claimed.

A Chromium/Playwright visual check was attempted, but the execution environment
denied Chromium's process-singleton socket (`Operation not permitted`) before any
page opened. Browser rendering/visual review and a real Perfetto UI import remain
unverified. Report construction, escaping, trace structure and CLI behavior are
covered by the focused software checks; those do not replace native visual review.

Independent review identified the malformed offline-argument fallthrough, optional
live-summary assumptions in offline output, and missing uncertainty in standalone
Perfetto exports. The candidate includes the corresponding fixes and regression
tests. Review also required three-state boundary interpretation and distinct phase
denominators. The lead inspected and integrated these findings.

Next: S1 provenance/capabilities, S2 owned one-shot collection with bounded transport
and detection coverage, then phase markers/adapters and matched native 1080p runs.
Existing transport still has a per-socket timeout and accumulates a full reply;
this offline file-reader cap does not close S2's live receive/deadline requirement.
