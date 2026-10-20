# LU-10-R1 — reject empty hull envelopes before probe transforms

2026-10-19. Native Windows, official Godot 4.7.2-stable (`ed1daf0bf`).
This is a bounded scenery-query repair. Overall session, frame pacing and the
landscape's nearby-contact performance gates remain open.
Luna Max helpers reviewed the broadphase invariant and validation coverage; the
lead integrated the change and ran the retained benchmarks and regression checks.

## Mechanism and preservation

`SceneryCollision.contacts()` already builds a conservative padded whole-hull
envelope and filters bin candidates against it. When that filter returns no
proxies, it previously continued interpolating attitudes and allocating/translating
every hull probe for every rotation subdivision. The three-line repair returns the
already-empty contact list immediately. Every probe sweep is enclosed by this
envelope; no event can be produced without a surviving proxy.

Validation, damage filtering, inclusive bounds, rotational padding, exact narrowphase
geometry and event ordering retain their existing paths. There is no persistent
cache, aircraft-data change, physics tuning or golden-flight replacement.

## Reproduction

The reference is `app/sim/scenery_collision.gd` at
`5e2fbe32da2531928f01164fc9923cde943918f9`. Extract that file outside `app/`.
With the reference at an absolute path and a new output filename, run:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy `
  --script "$PWD/research/performance/scenery_empty_probe.gd" -- `
  --reference=<absolute-reference.gd> --output=<new-report.json>
```

Run alone. The probe uses the actual eight-point Stik hull and a tiny normalized
lamp inventory. Each fresh process warms both detectors 50 times, then alternates
five pairs of 200 complete `contacts()` calls per fixture. It records raw batch
times, source hashes, machine/engine identity, input states, contact parity and
input immutability. Crossing-object fields are checked by the separate frozen
oracle suite. The synthetic 180° sweep is a robustness workload, not a normal
240 Hz flight or physical spin-rate claim. Empty-bin and actual-contact cases are
controls. Microseconds below refer to complete query calls, not inner loops.

Repeated batches follow Godot's [manual CPU timing guidance](https://docs.godotengine.org/en/4.7/tutorials/performance/cpu_optimization.html#manually-timing-functions).
The existing [session probe contract](../../../../research/performance/README.md#complete-callback-cpu-probe)
defines complete-session timing and fingerprint limits. The retained session runner
source ([run_sessions.py.txt](run_sessions.py.txt)) documents the alternating
disposable-copy campaign; timings are serialized. To replay it, copy that source
to `tmp/<new-directory>/run_sessions.py`, place the reference and current detector
there as `reference.gd` and `candidate.gd`, then run
`python tmp/<new-directory>/run_sessions.py 2400 12000 3 trim` from the repository root.
Snapshots copy code/data and share imported asset resources. No benchmark reserves
this workstation from unrelated activity, and no target-hardware or FPS acceptance
is inferred.

## Results and verification

Host: Ryzen 9 5900X, Windows x86_64, official editor/debug engine. Three fresh
processes produced 15 paired batches per query case (3,000 calls per detector).
The table is the median of the 15 batch means, in microseconds per complete call;
raw process/batch variation remains visible in [query-0](query-0.json),
[query-1](query-1.json) and [query-2](query-2.json).

| Complete query | Reference, µs | Candidate, µs | Local reduction |
| --- | ---: | ---: | ---: |
| Occupied bin, clear hull envelope | 228.455 | 35.705 | 84.37% |
| Same case, 0.02 rad rotation | 248.060 | 41.360 | 83.33% |
| Cell-boundary clear sweep | 927.085 | 41.385 | 95.54% |
| Synthetic 180° clear sweep | 14880.255 | 32.950 | 99.78% |
| Existing empty-bin control | 27.600 | 26.740 | control |
| Actual contact control | 624.430 | 638.285 | control, 2.22% slower |
| Rotating contact control | 2377.645 | 2365.750 | control |

All 21 process/case comparisons match contact bytes, and all three processes preserve
the input/world bytes. The real-hit controls retain their full geometry path;
their mixed small timing differences do not establish a speedup or a repeatable
regression. The 180° fixture removes a reproducible multi-millisecond empty query.

Three alternating complete-session pairs each used 2,400 warmup + 12,000 measured
240 Hz ticks (10 + 50 simulated seconds), including input shaping, integration,
4,980 scenery proxies and post-step work. Every run completed, with exactly the
same numeric trajectory fingerprint. Baseline/candidate p50 pairs were
**888/905, 938/914 and 938/1253 µs**. Median of medians: **938 → 914 µs (2.56%)**,
below 5% and smaller than host variation. This does not establish a general speedup.
This narrow repair does not close the global plan's complete-flight gain gate.
The two shorter trim/runway pairs also match fingerprints. Raw reports/logs,
engine hashes and the frozen code/data manifests are indexed in
[summary.json](summary.json). The two snapshot manifests differ only in the detector.

The long lake baseline crashes before completing its requested sample. That failure
is retained rather than shortening the fixture to report success. Both versions stop
after 1,407 measured ticks with the same failure, world identity and numeric
fingerprint; neither is a complete passing lake workload.

Verification details and exact results are in [verification.json](verification.json).
Both changed/new scripts parse. All **10 focused suites** pass without engine errors:
collision (51), frozen oracle (339, including 160 differential sweeps), collision
session (25), setup (22), scenery damage session (51), destruction (78), checkpoints
(92), checkpoint integrity (149), lake collision and replay integrity (153).
The oracle additions explicitly cover occupied-bin false positives, large rotation,
cell boundaries and a true hit. Existing damage/session/checkpoint checks exercise
the unaffected response, reset and restore paths. `git diff --check` also passes.
Software parity does not establish physical validity. Full `app/test.sh`, captures,
exports and GPU/platform qualification are outside this focused campaign.
