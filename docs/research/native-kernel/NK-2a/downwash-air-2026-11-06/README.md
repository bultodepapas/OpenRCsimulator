# NK-2a — Reuse downwash air within one pre-step

2026-11-06. Implements external audit **A6 O4**, selected from the
[consolidated audit](../../../../../external%20Audits/COMPLETED-AUDIT-WORK.md#implemented-corrections).
The bounded change removes duplicate air sampling without changing a physics law,
integration order, state layout or arithmetic expression. Baseline source is the
session at `e72d878b6`; [manifest](manifest.json) records exact source/engine hashes.

## Implementation and compatibility

The exact base `FlightSession` samples air once in the downwash block, after the
anchor update, and uses it for both wing wake and lag speed. Reuse ends within that
callback. No shaft sample, RK stage, previous callback or accepted tick is cached.
This relies on the existing pure, deterministic environment-query contract.

A script-resource identity guard leaves derived sessions on the original route:
`_wing_cl(s, aux)`, then `air_data(s, sim.time())`. The helper's signature and body
remain unchanged, preserving overrides, their order and implicit/explicit time
arguments. The single wake expression is deliberately repeated in the guarded
branch to avoid adding a new virtual call to the compatibility route.

## Measured cost

Windows 11 Pro 10.0.26100, Ryzen 9 5900X, official Godot 4.8-beta2. Both variants
use `gdscript_reference`. Detached Stik in airborne trim, legacy 3 m/s steady wind
or spatial eight-mode wind; identical configuration is embedded in each report.
There is no scenery, circuit, companion, input polling or presentation observer.
`Simulation.step()` includes the session's accepted-step handlers.

The [paired harness](bench_downwash_pair.gd) reuses the existing spatial-wind
benchmark's configuration, reset, finite-state and fingerprint helpers. Each
variant warms up for 32 calls/ticks and restores its fixture before timing. Eight
AB/BA pairs measure 256 callbacks or 960 accepted ticks per batch. Production wind
providers are uninstrumented. Hashing, warmup and reset are outside the stopwatch.

| Boundary / weather | Baseline median µs | Candidate median µs | Median paired reduction | Faster pairs |
| --- | ---: | ---: | ---: | ---: |
| Pre-step / steady | 75.51 | 70.45 | 6.87% | 8/8 |
| Pre-step / spatial | 656.89 | 361.52 | 44.68% | 8/8 |
| Full simulation step / steady | 546.81 | 526.17 | 2.63% | 6/8 |
| Full simulation step / spatial | 2,943.63 | 2,723.29 | **7.47%** | **8/8** |

[Raw longer pairs](timing-long.json) retain every batch and output fingerprint.
These are batch means, not per-tick percentiles. Spatial full-step reductions
range from 0.56–11.10%. The [initial 240-tick batches](timing.json) had a 9.33%
median spatial reduction but two substantial regressions among eight pairs; the
longer run addresses that noisy screen. Steady full-step runs retain large
outliers in both campaigns and do not establish a useful stable improvement.
No sustained, complete-application, FPS, 1080p or target-hardware claim follows.

## Correctness evidence

- The new `test_downwash_air_reuse.gd` passes **342 checks**: base versus legacy
  subclass callback bytes, halved air sampling for active lag, unchanged tailless
  path, flaps, nonzero time, zero/reverse/signed-zero body velocity, live lag-length
  and station-geometry edits, invalid datum/station samples, pending reset,
  rollback/recovery, override dispatch and 144 accepted paired ticks. The original
  332-check fixture failed only its 20 sampling-count assertions on baseline;
  the ten geometry-refusal/recovery assertions were added during review.
- **1,801 checks and four golden flights pass** across ten checked scripts:
  reuse (342), downwash (24), spatial weather session (101), spatial wind flight
  (156), powered stage (277), lean spatial stage (668), wind aircraft flow (88),
  tick facts (91), native session (54), and existing goldens (4). Native execution
  is explicitly skipped on this Windows host; fallback/lifecycle checks pass.
- Three original 240-tick recordings (steady Stik, spatial Stik, spatial Timber)
  were verified by exact replay **before** the runtime edit. Each candidate run
  completes the same tape with `solver_changed=true`; all three exported CSVs are
  byte-identical to baseline, including commands and recorded numeric samples.
  This is sampled agreement under a changed solver, not an exact-replay verdict
  for the candidate or independent physical validation. Original recordings,
  markers, CSVs, comparison reports and source identities are retained in [raw](raw/).
- Both timing campaigns complete with matching callback and final-state hashes
  in every pair. Original and candidate session sources are retained compressed.
  Required full app/visual CI has **not** been run for this uncommitted candidate.
  No golden data, native receipt or native binary was regenerated. Eligible native
  packages still need rebuild and oracle qualification for the changed source.

The manifest links passing checked-runner receipts and engine logs. Earlier
mistyped completion markers (`failed` versus `failures`) were rerun correctly;
they are not counted as passes. A draft geometry rollback check also required
resetting its manually edited diagnostic state to a committed endpoint first.
Those unsuccessful attempts remain under local `tmp/downwash-o4/`.

## Reproduction

Use the pinned engine and the source versions in the manifest. Decompress
`raw/baseline_flight_session.gd.gz` into an external scratch directory, then run:

```powershell
python tools/godot/run_checked.py --out-dir tmp/downwash-rerun --label paired --timeout 300 --require-text 'DOWNWASH_PAIRS_COMPLETE=true' -- $Godot --headless --path app --audio-driver Dummy --script ../docs/research/native-kernel/NK-2a/downwash-air-2026-11-06/bench_downwash_pair.gd -- --baseline=C:/scratch/baseline_flight_session.gd --output=C:/scratch/new-result.json --ticks=960
```

`$Godot` must be the resolved absolute path of the pinned executable. Keep the
output filename fresh. Use `tools/flight_log/flight_log.py` for replay/comparison
after decompressing the retained flights; the candidate argument is the same
aircraft JSON, with the changed solver explicitly disclosed. Exact baseline replay
requires restoring the baseline source identity, not merely its session class.
