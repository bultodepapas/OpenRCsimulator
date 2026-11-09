# CPU report integration — 2026-11-09

Reconciled the [supplied report](../../external%20Audits/cpu-mathematical-optimization-2026-11-09.md)
against `ca529cb88476a22fbb1c8edf957d6917ab9b6042`. The linked external HTML,
patch and ZIP were not available locally; the implementations were checked against
current source and reconstructed with permanent regression checks. Intake SHA-256:
`242f50409140c802214bf88a927345d2da82ddc9e18ace453082f8745cbc086a`.

## Retained production changes

- **D6-GP controller resolution:** lazily index valid occupied flight/both-context
  buttons once per resolution. Preserve declaration order, explicit Clear/remap,
  AUX ownership, unknown bindings, contexts and detached result ownership. No
  cross-event cache or profile invalidation protocol is introduced.
- **G3b engine voice:** inline the identical interpolation expression within the
  finite, normalized oscillator domain. Keep the original helper loop for unusual
  initial state or a short table, including its existing diagnostic behavior.
  Smoothing, phase update, PCM allocation and simulation remain unchanged.
- **PT1-CI / G3a fixtures:** add both Stik 6S generators to the expected ordered
  roster and the electric Stik's explicit two-blade audio expectation. Exact roster
  coverage and fail-stop checks remain intact.

The controller regression compares the original scan across **1,344** cases spanning
all 32 capability combinations, overrides and AUX conflicts; the complete extended
suite passes **1,451** checks. Controller actions, binding audit (14), profiles (74),
conditioning (57) and integration (27) pass. Voice (78), engine-sound (28) and
engine-audio integration (147) pass, including exact PCM/state comparisons and
simulation/checkpoint isolation. The WSL CI phase suite passes all **11** tests,
including every ordered generator failure boundary.

## Windows component measurements

Godot `4.8.beta2.official.cafc17a19`, native Windows x86-64, headless/Dummy.
Seven alternating baseline/candidate pairs, 500 warmup resolver calls per variant,
2,000 complete resolver calls per timed batch. The baseline is the original source
at `ca529cb88`; current-source hashes and raw batches are retained in the
[compact evidence](performance-report-2026-11-09.json).

| Component | Baseline median | Candidate median | Reduction |
| --- | ---: | ---: | ---: |
| Full airplane automatic bindings | 356.954 µs/call | 119.171 µs/call | 66.6% |
| Rates/restart automatic bindings | 167.003 µs/call | 113.376 µs/call | 32.1% |
| Fully explicit bindings | 87.956 µs/call | 88.398 µs/call | No useful gain; median 0.5% higher |
| Radio bindings | 57.959 µs/call | 59.319 µs/call | No useful gain; median 2.3% higher |
| Voice, per generated audio second | 5.447 ms | 2.989 ms | 45.1% |

Audio batches render 512 blocks of 512 stereo frames at 22,050 Hz after preparation
and 100 warmup blocks per variant. Each pair starts both oscillators in the same
state and checks exact final state. This saves about **2.46 ms per generated audio
second per voice** in this fixture. Shared development-host measurements are
component screens, without a controlled thermal/power campaign. They do not
establish whole-game FPS, GPU cost, physical-input latency or listening quality.
An initial screen showed the same direction: 65.4%, 32.3% and 43.9% reductions
for the two automatic-binding fixtures and voice. The reusable
[probe and reproduction contract](../../research/performance/README.md)
retain the same workloads with explicit baseline/output paths and source hashes.

HEAD advanced concurrently to `a188a1d1b` during the final checks and incorporated
the six production/test/CI edits plus the retained wind patch. The two optimized
runtime source hashes remained unchanged; the compact evidence records both
revisions. No commit or publication was performed by this task.

## Wind candidate retained outside production

The [apply-ready candidate](../../research/wind/temporal_phase_candidate.patch)
implements one temporal-remainder array per immutable stage query, preserving
point-dependent phase reductions, trigonometry and ordered sums. It includes
**1,463** permanent checks: historical Windows fixture bytes, 8/24/64 modes,
real signed-zero construction, invalid queries/refusals, live noise callbacks,
provider/configuration replacement, subclass/factory overrides, retained sampler
rebinds and actual FlightSession activation. Fourteen existing affected wind and
environment suites also passed during development, including powered fleet,
checkpoint continuation, midpoint rollback, wash and tailless replay checks.

One preliminary stock-Stik 24-mode full-session pair measured **4.256 → 3.925 ms/tick**
median batch cost. All three baseline/candidate final-state hashes matched, as did
the untimed counting replay; both completed nine restore checks. Batch means vary
substantially, so this is a screening result, not an accepted speedup or tick-tail
latency claim. The final guard/test refinements were not separately timed.

**The wind candidate is not enabled.** All four changed reference files participate
in the NK-3 mirrored-source identity. Applying it invalidates the previously
qualified native receipt across the fleet, including calm weather. A source
installation would fall back to GDScript and packaged admission would fail until
fresh native qualification. The four production files were restored byte-for-byte,
and each again matches its original installed receipt hash. No receipt was edited.

Before promotion, follow the [native qualification/install workflow](../../research/native-kernel/README.md#verification-and-local-installation)
on an isolated pinned Linux snapshot, compare exact baseline/candidate input-tape
trajectories and run controlled paired session measurements. Keep source identities
with every oracle/fleet/replay result. Do not reuse the existing binary's old evidence.

Offscreen afterimage culling, F10 hashing and indexed
shadow preparation retain the report's separate visual, numerical, lifecycle and
target-hardware gates. Existing concurrent shadow/tractor changes were preserved.
Full required CI, exports and physical device/audio qualification remain separate;
the focused checks here do not establish them.

Raw local runs remain under `tmp/perf-report-input-audio-20261109`,
`tmp/perf-report-components-20261109`, `tmp/perf-report-wind-20261109` and
`tmp/perf-report-final-20261109`. Early test-fixture/CLI mistakes and the native-Windows
shell-fixture attempt are retained as failed/inconclusive runs, not passes.

## A33 follow-up: Timber grid and current companion scorer

Integrated the second supplied report against clean baseline
`7e8ce3a4d0ea88943979ff0403fbb3cfeb3c3fe9`. Its external patch/archive were not
attached. Intake SHA-256:
`1c29eb499445efe92fc9239190a403962448ce1b392a9a10df7d2f70adc79988`.
The [compact evidence](performance-followup-2026-11-09.json) retains both timing
screens, exact source/engine and Timber source/import identities, checked-run
receipts and encounter comparisons. The reusable
[probe contract](../../research/performance/README.md) owns reproduction.

- **TT-21:** use the existing `Vector3i` cell coordinates as paint-index keys.
  Builder and lookup change together; geometry, tolerances, bucket/material order
  and empty/missing-bucket behavior remain unchanged. Actual cold/warm repaired
  arrays, serialized LOD records, formats, names and transforms match the baseline.
  Source meshes remain unchanged. Renew only the exact current paint identity;
  the distributed kit's legacy identity stays unchanged.
- **AFC-04:** the current AFC-04-R9 scorer already uses interval closest approach
  and arc-error bounds, so the older report's endpoint-minimum rewrite is obsolete.
  Skip unused endpoint roots after sample zero when tracing is off, preserving
  every interval calculation and traced endpoint. This reduces 65 roots to 33 per
  threat/bank, rather than the older scorer's 33-to-one claim. Reuse the first
  original saturated `lerpf`/turn-rate result locally; do not substitute the target
  bank at that transition. Renew the pilot raw hash, normalized behavior-source
  hash and profile's manifest hash. Solver, engine, circuit and aircraft pins stay
  unchanged.
- **PT1-CI:** both UID omissions named in the report were already fixed. Generate
  the missing `test_companions_behavior_manifest.gd.uid` and the new paint-grid
  test's UID with the pinned editor. The exact tracked-sidecar gate passes with
  these candidate additions in a temporary Git index; the real index is unchanged.

Native Windows 11 Pro, Ryzen 9 5900X, official Godot
`4.8.beta2.official.cafc17a19`, editor binary, headless/Dummy. Each screen uses five
alternating ABBA/BAAB groups, ten adjacent pairs per workload. Cold repair clears
the repair cache in an already-imported warm process; instantiation and comparison
are outside timing. Command batches follow 300 warmup/parity calls. Source
identities remain unchanged across both screens.

| Component | First baseline → candidate | Repeat baseline → candidate | Observed reduction |
| --- | ---: | ---: | ---: |
| Complete cold Timber repair | 408.928 → 327.025 ms | 391.243 → 310.242 ms | 20.0–20.7%; all 20 pairs faster |
| Command, one nearby threat | 987.711 → 926.315 µs | 991.025 → 934.695 µs | 5.7–6.2%; 18/20 pairs faster |
| Command, three nearby threats | 1875.776 → 1688.287 µs | 3494.746 → 2906.585 µs | 10.0–16.8%; 19/20 pairs faster |

These are shared-host component screens. Absolute command costs vary substantially
between screens; power, thermal state and competing work were not controlled.
Warm repair moved in opposite directions (−3.4% and +1.8% savings), so no warm-path
benefit is claimed. No displayed FPS, GPU cost, frame percentiles, 1080p readiness,
physical input latency or peak-memory improvement is established.

The retained probe passes **1,626 checks**, including 600 exact score/trace cases,
600 command/latch comparisons and actual imported-mesh cold/warm comparisons.
The final **14 affected suites pass 1,222 checks**: prediction (350), paint grid
(157), LOD/paint identity (58), profiles (52), behavior manifest (39), pilot (24),
clearance (20), terrain/traffic (60), manager (53), encounters (191), session (65),
session failures (24), traffic lifecycle (40) and actual Timber stock/custom skins
and material lifetime (89). The expanded prediction and grid tests also pass
against the baseline sources. Analytic ramp references cover samples 7, 8, 9 and
32 in both directions. Import and checked execution report no engine errors.

Seven 12-second real-session encounters plus the repeat have identical result
objects, state/control digests and trajectory CSV bytes (SHA-256
`bda3a6c8190a8869c9222ba8d52ef9912c6c717b6c6c204b38fa3ed44e65ad9b`).
The deliberately conflicting parallel two-threat fixture still misses separation
in both versions; this remains a survey, not expanded operating qualification.
Baseline Timber text matches the commit after CRLF normalization; its measured
raw hash and the Git blob hash are retained separately. Raw local runs are in
`tmp/perf-followup-20261109`. Required full CI, exports and native 1080p/sustained
qualification remain pending. No commit, push or publication was performed.

The subsequent [VQ-04a packed-index follow-up](visual-quality-implementation/VQ-04a/collection-decoder-20261109/README.md)
retains a modest native shadow-collection improvement, exact 1080p image parity
and the rejected traversal/gather experiments. Geometry collection remains
synchronous; complete-flight and first-interactive-frame qualification stay open.
