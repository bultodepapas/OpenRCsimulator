# LU-25-R1 — repeated lake validation cost

2026-10-19 · Windows · Ryzen 9 5900X · Godot 4.7.2.stable.official.ed1daf0bf.

The accepted change caches one successful, detached lake definition in
[`lake_surface.gd`](../../../../app/physics/lake_surface.gd). Complete value equality,
including nested values, is required for a hit. A changed dictionary runs the
unchanged structural guard. The identity label alone is never trusted.

## Profiling and choice

The production input/session and simulation callbacks were measured in a frozen
application copy with the default field, lake and 4,980 scenery proxies. Selected
GDScript methods were wrapped with nested microsecond clocks to distinguish
inclusive cost from self cost. Those instrumented times guide attribution; they
are not the before/after benchmark.

In the 2,400-tick P-51 attribution run, the segmented slipstream was the largest
individual measured leaf: 571 microseconds/tick, 12 calls/tick. Lake structural
validation was another large leaf: 322 microseconds/tick, **nine identical full
validations per tick**. Ground, collision, fuel and aerodynamic callbacks account
for the remaining workload. A slipstream lookup-hoisting experiment produced only
a small component improvement and was not adopted. Reusing unchanged validation
was the highest-impact behavior-preserving candidate demonstrated by the complete
callback benchmarks below. This is a CPU attribution result, not a claim about
the largest GPU or presentation bottleneck.

## Paired before/after results

Each case used two detached production sessions, 2,400 warmup ticks and 14,400
measured ticks per session: 10 and 60 simulated seconds at 240 Hz. Both processed
the same deterministic raw-input sequence through the real input shaping and
simulation callbacks. A benchmark-only switch in the disposable lake script
selected the original guard or the cache; both paid that dispatch cost. Order
alternated every 120-tick batch. Clocks exclude hashing, health checks and
checkpoint serialization.

| Aircraft / case | Before median tick, ms | After median tick, ms | Median paired batch reduction | Faster pairs / 120 |
| --- | ---: | ---: | ---: | ---: |
| Stik / trim | 1.077 | 0.932 | 14.13% | 111 |
| P-51 / trim | 2.302 | 2.145 | 7.05% | 106 |
| Timber / trim | 1.288 | 1.151 | 10.42% | 106 |
| Stik / idle runway | 4.525 | 4.162 | 7.02% | 105 |
| P-51 / maneuver pulses | 2.569 | 2.378 | 7.34% | 101 |

Reduction is the median of `100 * (1 - candidate_batch / baseline_batch)`, not the
ratio of the two independently calculated per-tick medians. All 600 batch-end
checkpoints were byte-identical. Per-tick state, auxiliaries, continuous state,
effective inputs, loads and modes produced matching SHA-256 trajectories in all
five cases. Every requested tick completed without crash, pause or fault.

The machine was shared with other work. Adjacent pairing limits drift but does
not make the samples independent or certify an idle machine. All twelve groups
of ten adjacent pairs favored the candidate in each airborne case; the runway
case had one slightly negative group. Raw distributions and these block medians
are retained in [summary.json](summary.json). No FPS, GPU, input-latency or
real-time deadline improvement is claimed.

## Independent production-script check

Six fresh-process Stik runs alternated the actual unmodified before/after lake
scripts, with no benchmark switch. All completed and had identical trajectory
hashes. Unrestricted scheduling was too variable to confirm a gain: median
baseline ticks were 969/1,013/976 microseconds, versus 1,295/859/1,318 for the
candidate. These unfavorable results are retained, not discarded.

A follow-up pinned only the child engine to logical CPU 4, kept normal process
priority, and alternated process order. The actual before/after scripts and
existing session probe remained uninstrumented:

| Repeat | Before median tick, microseconds | After median tick, microseconds | Reduction |
| --- | ---: | ---: | ---: |
| 1 | 967 | 1,052 | -8.79% |
| 2 | 964 | 870 | 9.75% |
| 3 | 955 | 817 | 14.45% |

The median paired reduction was **9.75%**, with one unfavorable pair. All six
trajectory hashes matched. Affinity did not isolate the host from other jobs;
this supports the direction of the paired result but is not a low-noise
qualification or a guarantee for another machine. Exact commands and source
hashes are in the affinity ledger under `raw/`.

## Behavior and regression checks

The original structural validator body is unchanged and retained independently
as a test oracle. The new suite passed **115 checks**, including in-place packed
array edits, nested profile/bounds/wave mutations with unchanged identity,
restoration, type changes, NaN/infinity, signed zero, missing fields, multiple
lake definitions, bounded retention, object lifetime and concurrent callers
with separately owned input dictionaries.

A deliberate identity-only cache defect in a disposable copy was rejected by
70 assertions, without engine errors. The production source was not mutated.

The cache admits only a bounded plain-data tree: at most 512 counted values or
packed scalars, nesting depth four, and strings at most 1,024 characters. Unusual
metadata remains on the original validation path. It retains no objects or
callables and does not recursively copy cycles. A mutex protects snapshot
publication; callers must keep their input stable during a query, as with the
original dictionary/array readers. This does not add a contract for concurrent
mutation of a caller's dictionary.

Fourteen targeted suites passed: cache parity; lake surface, collision, ground
contact and session; water and landscape checkpoints; scenery collision session
and oracle; checkpoint and checkpoint integrity; simulation; vehicle model; and
helicopter ground session. See [verification.json](verification.json) and logs in
`raw/`. The water-checkpoint test also reports the existing unsupported maple
wind-material warning. The complete repository suite and rendered/native frame
qualification were not run.

All four existing golden flights fail in **both** the unchanged frozen baseline
and candidate, with identical reported errors. Their logs are retained. No golden
was regenerated and this patch does not resolve those existing failures.

The frozen guard already emits an engine diagnostic for a numeric `format`
value. The optimization preserves that behavior; it is not a validator-hardening
change. The new parity suite does not disguise that diagnostic as a passing case.

## Reproduce and inspect

From the repository root, after importing the normal application resources:

```powershell
python research/performance/lake_validation_benchmark.py --godot .tools/Godot_v4.7.2-stable_win64.exe --work tmp/lake-validation-new
```

Use `--aircraft p51d-mustang-120` or `turbo-lumber-evolution`; `--case` also accepts
`maneuver` and `runway`. Each work directory must be new. The runner creates a
disposable copy, shares only asset/import files as read-only hard links, records
source hashes and engine logs, and rejects incomplete/mismatched results. Do not
run an import in that copy. Run timing campaigns without other workloads when
possible. The checked-in runner passed a short 24-warmup/240-sample functional
smoke check; that short run is not a performance acceptance measurement.

[`manifest.json`](manifest.json) identifies the before/after leaf, frozen source
manifest and exact measured scripts. [`baseline-source-hashes.json`](baseline-source-hashes.json)
identifies the frozen application source/config. `raw/*.gz` contains complete
timing arrays, fingerprints, attribution and regression logs. `measured-tools/`
preserves the exact one-off tools with their original local paths for audit;
use the portable runner above for a new campaign. Timing verifies software cost
and trajectory preservation, not physical validation or pilot acceptance.
