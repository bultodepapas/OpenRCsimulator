# NK-2a — Battery queries within one physics tick

2026-10-28. Extend the existing [per-tick facts](../README.md) with three configuration
answers: `battery_is_dynamic`, `battery_is_pack` and `_battery_block_size`.
The final change reduces measured complete-session CPU callback cost by **6.4% for
P-51 trim** and **6.1% for Timber finite-pack trim**. Stik runway idle is effectively
unchanged. This is headless GDScript evidence on one Windows development host.

## Change and choice

The [session](../../../../../app/sim/flight_session.gd) repeatedly checks the same
battery definition while deriving shaft, battery and wheel layout. Reuse those
answers only while the kernel tick is active. The implementation adds three scalar
facts to the existing memo, without a new cache owner, dependency or numerical law.
This small extension gives a measured saving above 5% in both affected airborne
cases; splitting scenery construction would require a larger change and separate
loading/visual evidence.

Accepted/rejected ticks and aircraft commits clear the memo. Two first-owner signal
connections also clear it before located-event and pause observers: the kernel can
publish these before `stepped` or `faulted`. Outside a tick, including trim, reset,
tools and direct queries, configuration is read afresh. In-place edits between ticks
remain visible. No golden, aircraft data, tick frequency, integrator, float64 state,
event order or checkpoint format changed.

The existing [paired probe](../../../../../research/performance/session_pair_probe.gd)
now accepts `--battery=ideal|pack` and records the actual data path/hash and battery
flags. Its default remains `ideal`; unsupported selections are rejected with exit 2.

## Protocol and identities

- Baseline: `30dc51cf56536360213068a23f5b07b953b4b829`, frozen app copy. Final Session
  SHA256: `88e3c2b5483dbca6d977dd18167d5b8ab4b7498b4c921a17221aada1f72055d9`.
  [Manifest](manifest.json) retains exact sources, engine/probe hashes and 394 shared
  dependency identities. The integrated runtime equals the measured candidate bytes.
- Windows 11 Pro, Ryzen 9 5900X, 24 logical processors, approximately 64 GB RAM,
  Balanced power plan; official Godot `4.8.beta1.official.4d10419ca` console editor.
  Campaigns ran serially, before the later concurrent correctness checks.
- Three fresh paired processes per case; two detached complete FlightSessions with
  the same input tape and real field, lake and collision world (6,092 proxies).
  Each role runs 2,400 warmup and 14,400 measured ticks: **10 + 60 simulated seconds**
  at 240 Hz. This is an uncapped workload, not a 60-second foreground flight.
- Baseline/candidate execution order alternates every 120-tick batch. Each timer
  includes Session and Simulation callbacks; hashing/checkpoint comparison is outside
  it. Presentation observers and rendering are absent. Means use all measured ticks;
  the reported gain is the median of the three paired percentage reductions.
- The final dependency snapshot was written after the first final P-51 pair started.
  Each raw report independently records its matching Session hashes; both dependency
  snapshots agree and subsequent checks found no drift in the frozen dependencies.

Exact commands are in the checked-runner reports. [Summary](summary.json) provides
the reductions, hashes and links to all compressed [raw reports](raw/), including
every tick sample. Retained source copies allow reconstruction after later edits.

## Final cost

All entries are microseconds per complete callback tick. The p50/p95 column uses
nearest-rank quantiles of pair 3; all repetitions' samples are retained.

| Case | Pair 1 mean | Pair 2 mean | Pair 3 mean | Median reduction | Pair 3 p50 / p95 |
| --- | ---: | ---: | ---: | ---: | --- |
| P-51 trim | 1,850.38 → 1,740.58 | 1,848.88 → 1,728.16 | 1,730.52 → 1,619.94 | **6.39%** | 1,692 → 1,584 / 1,907 → 1,791 |
| Timber finite-pack trim | 1,156.50 → 1,084.28 | 1,083.81 → 1,017.81 | 1,084.01 → 1,017.58 | **6.13%** | 1,053 → 989 / 1,215 → 1,160 |
| Stik runway idle control | 1,608.66 → 1,596.27 | 1,542.32 → 1,537.15 | 1,502.33 → 1,503.27 | 0.34% — neutral | 1,470 → 1,473 / 1,639 → 1,628 |

P-51 reductions range from 5.93–6.53%; Timber from 6.09–6.24%. Runway changes range
from a 0.06% increase to a 0.77% reduction and do not establish a useful gain.
The earlier two-predicate candidate, also retained in the summary/raw data, gave
median reductions of 5.15%, 3.86% and −0.57% respectively. The adopted candidate also
memoizes block size. Do not add these results to older NK-2a or loading speedups.

## Correctness and limits

- All nine final paired runs completed: matching fingerprints across **129,600
  measured paired ticks**, with **1,080 exact complete-checkpoint comparisons**.
  Numeric body, auxiliary and continuous state, inputs, loads and modes are hashed
  at every sampled tick. All nine superseded runs also match.
- Focused integrated checks: **765 checks plus 4 golden flights pass**, covering
  battery facts (91), finite packs (43), OCV batteries (103), checkpoint integrity
  (149), replay integrity (153), reset transactions (148) and native fallback (78).
  Goldens retain their existing cross-platform tolerance; the paired fingerprints
  and checkpoints above are exact. Companion Session checks also pass (65).
- The expanded [fact fixture](../../../../../app/tests/test_session_tick_facts.gd)
  covers fixed voltage, OCV, one- and two-branch ECM packs, block sizes 0/3/11/13,
  changed-layout refusal, invalid aircraft, combustion metadata, direct calls,
  reload/reset, rejected ticks and observer ordering. Both invalid probe modes are
  rejected without creating a result file.
- P-51 flight-card trim sweep, power-off stall, maximum speed and roll rate are valid
  **4/4 on both sources**, with [zero result differences](flight-card/comparison.md)
  at absolute and relative tolerance zero. Wall-clock durations are excluded by the
  existing comparison tool. These are software comparisons, not physical validation.
- `app/test.sh` was started on the isolated candidate copy. Offline generators and
  numeric guards passed; the remaining suite was stopped during the complete parse
  pass after a separate required test reproduced an existing failure. The full suite
  is **incomplete, not green**. `test_fixed_gear_brake_input` reports the same two
  Avanti frozen legacy checkpoint/metadata and CSV identity failures on baseline and
  candidate (257 checks, 2 failed each). The manifest retains both logs and the
  partial suite record; no fixture was re-recorded to hide those failures.
- Windows native admission still refuses the unavailable Linux-only library and
  retains the reference route. `flight_session.gd` participates in the native source
  receipt: eligible native packages require rebuild and oracle/trajectory
  requalification after source changes. No receipt guard or binary was changed.

No rendered-frame, 1080p, release-package, native-backend or physical-flight
qualification is established here. Gate P and the broader performance gates remain
open; this evidence justifies the bounded GDScript work reduction.
