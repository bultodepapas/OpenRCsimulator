# H17 — Reuse segmented slipstream quadrature invariants

2026-10-19. A one-method change reduces repeated array reads and Gauss interval
calculations in `Slipstream._segmented_increment`. Three complete P-51 trim runs
measured a median paired CPU reduction of **1.14%** (range 0.90–1.66%). This is a
small, repeatable improvement in this headless workload, not an FPS/GPU result.

## Profile and scope

The baseline is commit `8abefc50f0281526bdd13604f84694fee1686f27`, including the
previous LU-25-R1/R2 and H16 changes. [Identity verification](baseline-identity.json)
matched all 290 captured runtime/data files to that commit after CRLF-to-LF
normalization only; [source hashes](source-hashes.json) record the measured bytes.

Selected methods were instrumented with nested self/inclusive timers for 240
warmup and 2,400 sample ticks per workload. The largest measured P-51 trim leaf
was `_segmented_increment`: 12 calls/tick, 338.0 microseconds self time/tick.
The next measured costs were coupled response (283.3) and liquid-fuel evaluation
(205.1). In the runway case, wing flow (254.9), hull loads (251.0) and microrelief
(250.3) led instead. Stik trim's largest measured leaf was wheel evaluation
(108.0). This pass targets the P-51 hotspot; it does not establish the largest
bottleneck in rendering or every aircraft. Profiler overhead makes these numbers
unsuitable as release timing; all three raw profiles and their logs are retained.

The change loads twelve geometry values into local float64 scalars once per
invocation and evaluates the unchanged interval midpoint and half-width once
per segment. The five Gauss samples reuse them. Cut construction, integration
order, all force expressions, mathematical wrappers, state precision, model data
and 240 Hz stepping remain unchanged. There is no stateful cache. See the
[production patch](measured-tools/target.patch). The scoped junior review was
checked against the actual diff, and its draft test was reviewed, extended and
executed before integration.

## Paired full-session timing

Godot `4.7.2.stable.official.ed1daf0bf`, native Windows binary, Ryzen 9 5900X,
normal process priority, affinity mask 16 (logical CPU 4). Timing processes were
serialized on a shared development host; system-wide idle conditions were not
established. The same pinned engine and callbacks were used for both versions.

Each run warms two detached complete sessions for 2,400 ticks each, then alternates
120 pairs of 120-tick AB/BA batches: 14,400 measured ticks per implementation.
Field, lake, 4,980 scenery proxies and input tape are identical. The clock covers
the session/input and simulation callbacks, excluding hashes/checkpoints. The
paired runs contain no profiler wrappers. Reduction is the median of
`100 * (1 - candidate_batch / reference_batch)`; it is not the ratio of the two
independent per-tick medians.

| Workload | Before median µs/tick | After median µs/tick | Paired reduction | Faster pairs |
| --- | ---: | ---: | ---: | ---: |
| P-51-trim-r1 | 1997 | 1982 | 0.90% | 85/120 |
| P-51-maneuver-r1 | 2020 | 1995 | 1.26% | 89/120 |
| P-51-trim-r2 | 1993 | 1960 | 1.66% | 102/120 |
| Stik-trim-r1 | 717 | 718 | -0.09% | 56/120 |
| P-51-trim-r3 | 1975 | 1950 | 1.14% | 105/120 |

The trim repeats have 292/360 faster pairs. The maneuver case is a single control
with small roll/pitch doublets; it is not a broad flight-envelope qualification.
The Stik control bypasses segmented quadrature and is effectively flat, retaining
its slightly unfavorable measurement. The short preliminary P-51 run (1.32%)
is retained separately and is not pooled. [Campaign ledger](campaign.json) records
exact commands and summary values. `raw/paired-*.json.gz` retains every tick and
batch timing plus fingerprints, with separate engine logs.

### Component measurement

Direct `Slipstream.loads` calls used 100 warmup calls per version followed by ten
alternating pairs of 2,000 calls per case. These isolate the component, not the
full-session cost. The exact fixture and all samples are retained.

| Case | Before µs/call | After µs/call | Paired reduction |
| --- | ---: | ---: | ---: |
| powered | 86.9822 | 82.9433 | 5.18% |
| static | 89.9725 | 85.1527 | 5.32% |
| wide sideslip | 19.3715 | 19.5865 | -0.36% |
| stopped | 0.6745 | 0.6745 | 0.44% |

Powered/static cases benefit from the changed helper. Wide sideslip and stopped
controls are near flat; their small positive/negative changes are not credited
as improvements. No best-of selection or dropped unfavorable run is used.

## Behavior and regression checks

All five complete-session comparisons pass without engine errors: equal numeric
trajectory hashes over **72,000 measured ticks per implementation** and **600
byte-identical complete batch checkpoints**. Hashes cover state, auxiliary and
continuous state, input, loads and modes. The integrated production file exactly
matches the measured intended source.

The new `test_segmented_slipstream_parity.gd` passes **381 checks**, including 336
exact load-array comparisons: 50 direct-helper cases, 30 whole-load cases and
256 seeded comparisons (all seeded outputs nonzero). It covers both tail
surfaces, core/center/no-cut cases, tilted axes, nonzero rates, controls and
downwash, subdivisions 1/2/4/8, zero/negative-area early exits, stopped and reverse
flow, residual axial velocity, P-51 legacy and three Stik models, and changed
inputs between calls. Finite results are required; matching NaNs cannot pass.
A one-ULP comparator control and coverage floors guard against vacuous success.
The oracle retains the original `loads` and `_segmented_increment` methods,
verified against the baseline, and inherits unchanged helpers. A disposable
0.001 m shift in the Gauss midpoint is rejected with 297 failures.

Eight targeted suites pass: segmented parity, slipstream sidewash, slipstream
scalar (10,001 projected-load comparisons), slipstream downwash, P-51 ground,
P-51 flaps, P-51 retracts and checkpoints. Three suites remain failing:

- Wash transport: two production state-layout expectations (P-51 and Avanti).
- P-51 handling: full-up power-off reaches 9.3 degrees alpha against an 11.9
  degree stall-start expectation.
- Golden replay: `roll_15`, `pull_throttle`, `rudder_doublet`, `glide_15`.

All seven failure lines, including the numeric handling/golden errors, reproduce
exactly on the untouched frozen baseline. No goldens, tolerances or tests were
weakened. These existing failures remain unresolved. [Verification](verification.json)
links the baseline comparisons; all suite logs, commands and test hashes are under
`raw/`. Existing aircraft-data warnings remain in the logs. Full `app/test.sh`,
full CI, rendered performance and physical validation were not run or established.

## Reproduction and audit

Use a separate checkout of the baseline commit and the same pinned engine.
Import that checkout once before benchmarking. Preserve its application tree,
resource imports and root resource paths as `tmp/perf-pass4-20261019/base/app`.
The captured `project.godot` is retained as `measured-tools/project.godot.txt`.
Do not import a disposable copy whose assets/imports are shared read-only.

Copy `make_candidate.py`, `segmented_increment_candidate.gd.txt`, `campaign.py`
and `paired_session.gd` from `measured-tools` into `tmp/perf-pass4-20261019/`,
then run from the checkout root:

```powershell
python tmp/perf-pass4-20261019/make_candidate.py
python tmp/perf-pass4-20261019/campaign.py
```

The generator uses the repository's public `session_pair_probe.gd`; compare it
with the retained exact probe when running from a later revision. It creates an
isolated three-script graph (slipstream, dynamics, flight session). Only the
benchmark candidate rewrites preload paths; `intended` contains production bytes.
All complete before/candidate/intended scripts and integrated regression sources
are gzipped under `sources/`. Use a fresh output directory or preserve earlier
results. Original absolute commands are retained; regenerating the candidate
updates checkout-dependent paths. The component and draft-regression scripts
retain their original scratch path, which must likewise be updated if relocated.

`prepare_pass4.py` records the original copying procedure and adaptation from the
previous temporary instrumenter. The complete adapted `instrument.py`, profiler
clock and probe are retained directly; the old temporary directory is not needed
to inspect or rebuild instrumentation. Keep timing copies uninstrumented.
[Manifest](manifest.json) hashes the retained artifacts.
