# GOD TEST measurement hardening — 2026-11-21

Owning steps: **GOD-12-R2f / GOD-12-R2g / GOD-13-R2**. Base revision:
`a9c3950fbbfcc09607f207e509ba4c992bce98e3`, on
`perf/three-aircraft-performance-cycle-2026-11-20`.

## Outcome and scope

Implemented the first corrections from the [independent audit](2026-11-20-plan-audit.md):
requested rendering now fails closed, CPU/GPU completeness is rebuilt from raw
observations and owner timestamps, local simulation pace is visible in the primary
reports, and automatic managed execution budgets the entire expanded roster.

This is a tooling implementation and verification result. It is **not** a V2
flight acceptance or a MacBook/Linux GPU/Windows performance result. The command
still runs the existing V1 airborne/menu workload. The revised runway takeoff,
low right turn past pavilion/trees/house, one/two same-flight laps, browse-only
menus, horizontal roll and intentional impact remain in the
[scenic/crash plan](../../plans/god-test.md#4a-planned-scenic-and-crash-tour).

## Changes and independent counterexamples

Three helpers implemented bounded components; cross-component review then tried
to falsify the integrated verdicts. The lead integrated the fixes and added
end-to-end offline checks through the real reducers and suite projection.

| Area | Previously possible misleading result | Implemented correction |
| --- | --- | --- |
| Requested graphics | Losing `rendered=true` could bypass graphics and monitoring success checks | Bind original/resolved manifests and explicit requested mode; require positive runtime and raw drawing evidence for every requested phase |
| Raw rendering | Runtime booleans could disagree with undrawable/zero-draw stream observations | Reconcile absolute draw counters and deltas; each contiguous phase segment needs an in-phase positive draw, excluding its first crossing interval |
| Renderer/phase identity | Missing launcher renderer metadata, truthy non-boolean phase flags, duplicate phase labels | Validate actual renderer against the requested options and recorded host; strict flags, canonical cycle/index/name IDs and index-based target projection |
| CPU sampling | Two samples, a self-declared complete label or an enlarged interval could hide a long blind period | Validate raw required fields/statuses/counts, monotonic counters, uncapped clean stop, fixed configuration and first/inter-sample/tail gaps |
| CPU owner binding | An internally consistent sample clock could be shifted away from its owner | Bind construction/finish anchors and poll brackets to independent runner timestamps; missing historical owner receipts remain unavailable |
| GPU sampling | Poll-start spacing could hide long backend/device gaps or queries after stop | Recompute conservative per-poll and per-device gaps using full query brackets, fixed cadence and the owner window |
| Combined monitoring | Internally valid CPU and GPU windows could be disjoint or in the wrong order | Verify the complete CPU-start → GPU-start → CPU-finish → GPU-stop lifecycle, including return markers |
| Simulation pace | A whole-phase ratio near one could hide slowdown followed by catch-up | Add bounded fixed-window reduction, tick-derived pace extrema and maximum observed accumulated lag to child/suite JSON and HTML |
| Incomplete local evidence | A stalled partial tail, large first interval or imprecise high-epoch clock could receive a positive target | Keep unscored tails inconclusive, reject material boundary exclusions and inadequate simulation-clock precision |
| Managed execution | A nine-case campaign inherited the generic one-hour deadline | Compute the entire expanded plan's lease before automatic submission; propagate it through the queue integration and reject over-limit plans without dropping cases |
| Worker inputs | Abbreviated flags could evade the raw preset's blocked-option spellings | Reject worker-owned inputs before automatic plan IO and disable option abbreviation in every GOD TEST command parser |

Implementation is split into [render evidence](../../../tools/godtest/render_evidence.py),
[CPU coverage](../../../tools/godtest/resource_coverage.py),
[GPU coverage](../../../tools/godtest/gpu_coverage.py),
[local pace](../../../tools/godtest/pace_windows.py) and
[admission budgeting](../../../tools/godtest/admission.py). The
[runner](../../../tools/godtest/runner.py) records owner boundaries; the
[case reducer](../../../tools/godtest/analysis.py) and
[suite reducer](../../../tools/godtest/tour_report.py) retain independent data,
coverage, monitoring and performance outcomes. `reducer_sources` records helper
hashes, and `reducer_sha256` now identifies that aggregate source map. Campaign
observer identities include the new modules so a changed reducer/helper cannot
silently continue an old retained campaign.

## Measurement policy

### Rendering

Original requested mode is authoritative. A graphics run with missing/contradictory
raw draw evidence is ineligible with partial coverage. An explicitly requested,
verified headless run may still complete its functional checks, without a graphics
performance claim. Raw observations establish engine draw progress and drawable
endpoints; they do not establish physical presentation or native drawable pixels.

### CPU and GPU

The implemented observer contract remains 1 Hz and a 4,000-sample cap. The maximum
permitted first/inter-observation/tail gap is 3.25 s, calculated from conservative
poll/query brackets rather than treating an observation as an instantaneous sample.
Raw evidence cannot choose a larger cadence to make its own gaps acceptable.

Owner records bracket CPU construction/finish and GPU construction/start/stop.
CPU uses the sampler's rounded `perf_counter` convention; GPU uses the sampler's
`perf_counter_ns() // 1000` convention. Cross-observer ordering permits only the
documented two-microsecond representation difference. This is host-clock binding,
not a host-to-engine-phase join.

GPU queries overlapping stop are retained but not credited to pre-stop coverage.
The declared 50 ms stop race permits retained/excluded late reads; later starts
make timing incomplete. This is deliberately conservative: a sequential Linux
multi-backend poll can start its second query after that margin even if earlier
observations were sufficient. The producer's existing timing verdict also rejects
that situation. No relaxed acceptance is claimed here.

Owner windows begin after bridge readiness and setup. They do not prove that the
observers began promptly from the bridge-ready boundary, and they exclude earlier
startup. Optional temperature/power sensors remain optional. Device utilization
still includes other processes, and renderer-to-device association is unresolved.

### Local simulation pace

The stream reducer uses integer tick differences at the existing 240 Hz physics
rate. Simulation-time consistency has a bounded serialization tolerance; a large
clock value cannot gain seconds of tolerance through a relative comparison.
Inadequate precision remains unavailable.

Each contiguous active phase segment has a fixed one-second grid. A full supported
window needs at least 0.9 s of admitted wall time and two intervals. Crossing
intervals are not split or interpolated. A positive local screen additionally
requires supported full windows throughout the declared coverage, at least 90%
supported active wall time, no first/window-boundary exclusion over 100 ms, no
unexpected hold, and no unscored partial tail. Detailed exclusions and partial
support remain in JSON. A supported bad window is still an observed miss when
other coverage is incomplete.

The 0.99–1.01 ratio screen and observed lag are exploratory. They do not supply
confidence intervals, resolve peaks between callbacks or qualify target hardware.
For example, the raw-stream integration fixture with five seconds at 0.5× followed
by five seconds at 1.5× has a near-one phase total but reports 0.5×/1.5× local
extrema and 2.5 s of peak observed lag. A separate healthy-window fixture with a
0.4 s stall/catch-up inside its final partial tail reports inconclusive local
coverage instead of a positive target.

### Managed execution

The automatic CLI computes a lease from every manifest timeout plus documented
history/import, identity, launch, monitoring and cleanup allowances. Filesystem
and reduction work receive an explicit heuristic reserve because those operations
do not currently have individual hard deadlines. The lease is enforced execution
time, not a guarantee of completion or an end-to-end wall bound.

The nine-case dry run with `--repeats 3` and otherwise default settings reports
8,100 s of scenario timeouts and a 14,924 s
lease. The default three-case plan receives 5,630 s. Calculated leases above the
21,600 s queue limit are rejected before automatic submission, keeping the entire
requested roster visible. Generic suite/CI/capture defaults are preserved.

Direct `testctl`/MCP preset submissions still do not enforce this full-roster
minimum; their caller must supply the matching source's calculated budget.
Queue waiting and pre-adapter preparation remain outside the execution lease.
Windows-local graphical admission remains experimental; Linux/macOS graphical
adapters and enrolled-host resume remain unimplemented. See the
[operating guide](../../../tools/godtest/PERFORMANCE_TOUR.md#managed-host-admission).

## Verification

Environment: Linux x86_64, Python 3.12.14. No Godot launch, GPU query, remote worker,
hosted CI or physical target-machine campaign was performed in this follow-up.
The [machine-readable record](2026-11-21-measurement-hardening.json) retains commands,
counts, source hashes and scope.

| Check | Observed result |
| --- | --- |
| `python3 -B -m unittest discover -s tools/godtest -p 'test_*.py'` | 204 passed; includes raw stream → child report → suite/HTML projection, negative controls, resume behavior and bounded reducers |
| `python3 -B -m unittest tools.testqueue.test_integration tools.testqueue.test_adapter_completeness tools.testqueue.test_contracts tools.testqueue.test_request_limits` | 49 passed; no real queue submission or worker launch |
| `python3 -B tools/godtest/godtest.py performance-tour --repeats 3 --dry-run` | Nine cases retained; calculated 14,924 s execution lease; no launch |
| Real `ResourceSampler` on an owned Python process | Three samples; required fields, temporal gaps and owner-clock binding all complete; this is a sampler schema/lifecycle smoke check, not simulator performance |
| Changed-document links and `git diff --check` | 28 added relative links/anchors resolve; staged whitespace check passes |

Pure tests include real sampler lifecycle code with controlled fake backends/clocks;
the separate owned-process CPU smoke check used the actual process sampler. No
synthetic fixture timing is reported as measured aircraft FPS. The earlier
[2026-11-20 headless tour](2026-11-20-performance-tour.md) and audit are unchanged.

## Remaining acceptance work

The [plan ledger](../../plans/god-test.md#13-execution-steps-and-evidence-ledger)
marks these steps partially implemented. Still required: calibrated ground starts
and low routes for all three aircraft, same-flight lap/roll proof, per-action
settings invariants, preview-generation binding, new terminal impact/live-report
binding, host/engine clock joins, actual rendering-GPU and drawable-pixel proof,
all-attempt retention/relocation, preparation/storage bounds, observer-cost controls,
thermal/power conditions, repeated decision policy and real MacBook/Linux GPU/Windows
campaigns. This follow-up closes specific false-pass paths without turning those
unverified conditions into a passing benchmark.
