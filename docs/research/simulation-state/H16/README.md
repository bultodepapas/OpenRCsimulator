# H16 — Reuse layout queries within each ground stage

2026-10-19 · Windows · Ryzen 9 5900X · Godot 4.7.2.stable.official.ed1daf0bf.

[`FlightSession._ground_evaluation`](../../../../app/sim/flight_session.gd) now queries gear capability, glow capability,
wheel count and wheel offset once per invocation. The values are local variables;
nothing survives into the next stage. Force arithmetic, validation, output shapes,
240 Hz stepping and aircraft data are unchanged.

## Profile and scope

The current application, including LU-25-R1 lake validation reuse, was frozen before
profiling. Both attribution cases used the default field, lake and 4,980 scenery
proxies. Selected methods were wrapped with nested microsecond clocks for 240
warmup and 2,400 sample ticks. These instrumented numbers identify repeated work;
they are not release timings or an estimate of the saved time.

| Instrumented work per tick | Stik | P-51 |
| --- | ---: | ---: |
| Ground evaluation, inclusive microseconds | 360.2 | 610.1 |
| Wheel offset queries, calls / self microseconds | 14 / 84.8 | 30 / 228.0 |
| Wheel count queries, calls / self microseconds | 28 / 60.2 | 62 / 126.7 |
| Retractable capability queries, calls / self microseconds | 27 / 42.2 | 75 / 105.9 |

The P-51 segmented slipstream remained the largest individual measured leaf
(350.7 microseconds/tick). Repeated layout queries were substantial shared adapter
cost, including during airborne flight. Within the successful wheel-stage branch,
this change reduces direct wheel-offset calls from three to one, wheel-count calls
from four to one, retractable queries from three to one, and glow queries from up
to two to one. Nested queries disappear with the redundant calls. This was the
bounded common-path candidate validated below; no global GPU bottleneck claim is made.

## Before/after method

Ten serialized processes compared actual full before/after session scripts in the
same frozen app. Neither measured implementation contained profiling wrappers or
benchmark switches. Each engine used normal priority and affinity mask 16 (logical
CPU 4). Each case ran two detached production sessions with identical raw-input
sequences, 2,400 warmup ticks and 14,400 measured ticks per session (10 + 60 seconds
of simulation). Order alternated in 120-tick batches. Clocks surround the session
input callback and simulation callback; hashing, checkpoints and health checks are
outside those clocks. The host was shared, not isolated or certified idle.

| Aircraft / case / repeat | Before median tick, us | After median tick, us | Median paired reduction | Faster pairs / 120 |
| --- | ---: | ---: | ---: | ---: |
| Stik / trim / 1 | 922 | 871 | 7.58% | 81 |
| P-51 / trim / 1 | 3100 | 3072 | 4.75% | 83 |
| Lumber / trim / 1 | 1138 | 1077 | 5.30% | 104 |
| Stik / trim / 2 | 845 | 807 | 5.20% | 78 |
| P-51 / trim / 2 | 2616 | 2620 | 1.01% | 68 |
| Lumber / trim / 2 | 1361 | 1285 | 5.06% | 93 |
| Stik / trim / 3 | 936 | 885 | 4.59% | 89 |
| P-51 / trim / 3 | 2381 | 2309 | 2.34% | 73 |
| Lumber / trim / 3 | 1265 | 1200.5 | 4.65% | 88 |
| Stik / runway / 1 | 3084 | 3113 | -0.07% | 60 |

Across the three airborne repeats, the median paired reductions were **5.20% Stik**,
**5.06% Lumber**, and **2.34% P-51**. Run-level ranges were 4.59–7.58%, 4.65–5.30%,
and 1.01–4.75%, respectively. The single runway run was **−0.07%**, with 60/120
wins: no resolved improvement there. Ten-pair block medians include unfavorable
blocks, particularly on P-51; `summary.json` retains them. The consistently positive
airborne run medians support this small common-path change, but shared-host noise
precludes a precise general speedup or idle-host qualification.


The reported reduction is the median of `100 * (1 - candidate_batch / baseline_batch)`.
It is not the ratio of independently calculated tick medians. Repeated measurements
are retained individually. No FPS, GPU, input-latency or real-time deadline gain is
claimed. The earlier unpinned Stik preliminary run is retained separately and is not
pooled into the fixed-core campaign. Gate P remains open.

## Behavior and regression evidence

All ten campaign processes completed every requested tick without crash, pause or
simulation fault. All **1,200 batch-end checkpoints were byte-identical**. Six
numeric arrays (body state, auxiliaries, continuous state, effective inputs, loads
and modes) produced matching per-tick trajectory hashes over **144,000 measured
ticks per implementation**. The frozen runtime/data manifest was rechecked after
verification: none of its 290 files changed. Logs contain the existing Stik inertia
data warning; none of the ten benchmark processes reported an engine error.

The integrated [regression test](../../../../app/tests/test_ground_stage_queries.gd)
passed **195 checks** against the original method retained in
[`ground_stage_reference.gd`](../../../../app/tests/ground_stage_reference.gd).
It covers Stik, P-51, Lumber, Glow Stik and Avanti; airborne, ground and lake stages;
hull enabled/disabled; supplied liquid mass properties; short/nonfinite wheel
state; retractable gear at 0/0.5/1 extension; caller-data preservation; and a
test-only wheel-profile status change followed by restoration/reset. The reference
method matches the frozen original source with line endings normalized.

**15 targeted test scripts passed:** the new oracle, wheel session, ground contact,
stiction, retractable ground, P-51 ground, Timber ground, liquid-fuel session, glow
session, lake ground contact, lake session, checkpoint, checkpoint integrity,
simulation, and ground-start integrity. The three changed/new runtime/test scripts
also passed explicit parser checks. This was scoped verification, not a complete
`app/test.sh` run. [Test ledger](regression-results.json) and compressed full logs
under `raw/` retain the commands, outcomes and test-source hashes.

**The golden suite remains failing:** `roll_15`, `pull_throttle`, `rudder_doublet`
and `glide_15` fail on both the frozen before tree and the integrated tree. All four
failure lines, including numerical worst errors, match exactly. No golden was
re-recorded. This existing failure prevents claiming a completely green suite.

A disposable wrong-wheel-offset mutation, armed only after valid setup and disabled
for reset, caused **76 of 195 checks to fail**, without an engine error. The earlier
always-on mutation also broke session setup; its diagnostic log is retained as
`raw/offset-mutation.log.gz` and is not a production failure. The clean production
oracle run remained 195/195. The public probe smoke completed 1,200 measured ticks
per implementation and ten exact checkpoints against the integrated application;
its short timings are not included in the performance result. [Final checks](final-checks.json).

## Reproduction and identities

The raw outputs, complete process logs, profiling scripts and exact measured session
sources are retained beside this report. `manifest.json` records SHA-256 hashes;
`source-hashes.json` identifies the 290 frozen runtime/data inputs. The benchmark
copies shared asset/import inputs read-only and were not imported. Unrelated work
continued in the live tree; only this method was transplanted after checking that
its original body still matched the frozen baseline. Existing calibration guard
edits were preserved.

The reusable [paired-session probe](../../../../research/performance/session_pair_probe.gd)
can compare the retained original-method test oracle with the current production
session. Its command is in the [performance tool guide](../../../../research/performance/README.md#ground-stage-layout-queries-h16).
That reproduces the isolated method comparison against current dependencies; it
does not recreate the dated full application from hashes alone. The measured
campaign instead loaded complete before/after scripts and records their exact paths
and hashes in `campaign.json`.

The retained one-off preparation/campaign scripts contain their original workspace
paths. Use the tool-guide command for a current-tree comparison; historical hashes
identify inputs and do not substitute for a full application snapshot.
