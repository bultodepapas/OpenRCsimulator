# NK-2a — Per-tick memo of aircraft capability answers

2026-10-27. First GDScript slice of [NK-2](../../native-kernel-scoping-2026-10-27.md#phases-r-research-i-implementation)
(validate immutable model data once; [optimization scan](../../godot-optimization-scan-2026-10-27.md) item 4).
Bit-identical refactor: no law, constant, layout or trace change. Headless evidence on the Linux dev VM (Godot
4.8-beta1 official editor binary, shared host); not release-build, native or target-hardware qualification.

## Finding

`FlightSession` answers capability and layout questions by re-reading `aircraft` on every call. A script profile of
the electric Stik idling on the runway ([LU-25-R4 listing](../../landscape-upgrade/LU-25-R4/profile/runway-idle-by-self.txt))
shows, per accepted tick: `wheel_brake_available` 6 calls (a full provenance walk over every wheel, 1.7 ms of the
59 ms profiled script per sample), `gear_is_retractable` 33, `wheel_count` 21, `anchor_count` 13, `glow_is_active`
17, `_rotor_index` 12, `downwash_index` 6. Together they took about 8% of profiled script time. Their answers
depend only on the committed aircraft data, but tests and tools edit that data in place between ticks
(15 test files), so a cache keyed on load events alone would serve stale answers.

## Change

[`flight_session.gd`](../../../../app/sim/flight_session.gd) memoizes eight answers for one kernel tick:
`glow_is_active`, `gear_is_retractable`, `wheel_brake_available`, `flaps_available`, `wheel_count`, `anchor_count`,
`downwash_index` and `_rotor_index`. Composites such as `_input_count`, `wheel_brake_input_index`,
`gear_aux_index`, `flap_aux_index` and `wheel_index` read through them.

- The kernel's `pre_tick` is now `_kernel_pre_step`, which arms the memo and calls the unchanged `_pre_step`.
  Direct `_pre_step` calls (two tests) and solves outside the kernel step (trim, runway equilibrium,
  linearisation) never arm it.
- The session's existing `stepped` and `faulted` handlers drop it first, so an accepted or rejected tick ends it;
  committing aircraft data drops it too. Every caller outside a tick (UI, observers, tests) reads the data afresh.
- No runtime code writes into `aircraft` (only the two load paths reassign it), so inside a tick a memoized answer
  equals the direct one.

[`aero.gd`](../../../../app/physics/aero.gd) tests the flap angle before `Flaps.enabled(model)` in its four flap
guards (41 calls per tick); both operands are pure, so only the evaluation order changes.

## Exactness

- [`session_probe.gd`](../../../../research/performance/session_probe.gd), baseline = this tree with `HEAD`'s two
  files in a hard-linked snapshot: 14 aircraft/case pairs (electric, glow, Extra, P-51, Corsair, Avanti turbine,
  Timber, X8; trim, runway idle and manoeuvre; 600 warmup + 2,400 sampled ticks) give identical state fingerprints
  ([parity.jsonl](parity.jsonl)). Retractable gear, wheel brakes and flaps are exercised by the P-51, Corsair and
  Avanti; anchors, wheels and the downwash lag by every wheeled aircraft.
- [`test_session_tick_facts.gd`](../../../../app/tests/test_session_tick_facts.gd) (16 checks) pins the life
  cycle: armed inside the tick with the direct answers, dropped by accepted and rejected ticks, never armed by a
  direct `_pre_step`, in-place edits visible after a tick, a reload clears a stale memo. On a disposable copy,
  removing the `stepped` or `faulted` drop, or arming inside `_pre_step`, fails it. Removing the commit-time drop
  does not, because the kernel reset of a reload also drops the memo; that drop is kept as a guard for staged and
  Workshop commits.

## Cost

`session_probe.gd` (2,400 warmup and 14,400 sampled ticks, real input and simulation callbacks, no presentation
observers), three alternating pairs per case against the same baseline snapshot ([cost-pairs.jsonl](cost-pairs.jsonl)):

| Case | Pair 1 µs/tick | Pair 2 | Pair 3 | Median change | p95 |
| --- | --- | --- | --- | ---: | --- |
| Electric Stik, airborne trim | 1,190 → 949 | 1,157 → 985 | 1,186 → 997 | −15.9% | 1,972 → 1,640 (pair 3) |
| Electric Stik, runway idle | 2,568 → 2,308 | 2,733 → 2,428 | 2,673 → 2,452 | −10.1% | 4,387 → 3,996 |
| P-51 (gear, brakes, flaps), runway idle | 4,027 → 3,691 | 3,800 → 3,592 | 3,647 → 3,275 | −8.3% | 5,634 → 4,391 |

All nine pairs improve and keep one fingerprint per case. The gain exceeds the profile estimate (about 8%), which
does not count the call overhead charged to the callers; the session pairs, not the profile, are the evidence.

## Regressions

95 scripts ([summary](tests.txt)): 91 pass, including `test_golden`, replay integrity, retracts, flaps, wheel
brakes, downwash lag, wind flight, checkpoint and reset transactions. The other four fail identically with `HEAD`'s
files, at clean `HEAD` and at `f9e6dbe8d`, so they predate this change.

## Battery-query follow-up, 2026-10-28

The current session also memoizes `battery_is_dynamic`, `battery_is_pack` and
`_battery_block_size` within the same kernel tick. Located-event and pause signals
drop all facts before external observers, covering publication before `stepped` and
fault notification before `faulted`. The [follow-up evidence](battery-queries-2026-10-28/README.md)
owns the current-source timings, exact checkpoint comparisons and battery-layout
regressions; the original Linux measurements above remain historical.

## Remaining

The lake and surface-table guards (`LakeSurface.is_valid_definition`, `Terrain.is_valid_surface_table`) run inside
static physics functions that receive the data, not the session; a per-tick memo cannot reach them without an API
change across the ground, lake and contact owners. NK-2 proper (an immutable prepared model with a revision boundary)
is still needed before a native evaluator can hold a model handle.
