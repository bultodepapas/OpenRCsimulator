# H18 — Evaluate the ground-effect wing wake once per oracle call

2026-10-27 · Linux dev VM (Intel i5-10500 under KVM, shared host) · Godot 4.8-beta1 official editor binary.

[`Aero._global_loads`](../../../../app/physics/aero.gd) is the attached-flow oracle evaluated at every RK stage. In
ground effect (M5-GE-1) it evaluates the strip wing's wake velocity twice with identical arguments
(`_wing_lift_coefficient_with(s, air, d, model, ge, true)`): once for the static ground-effect tail term
(`wake_ge`) and once as the source of the downwash-lag term (D11g). The strip law is pure, so the lag term now reuses
`wake_ge` when the ground-effect block has computed it, and evaluates it as before otherwise. No law, operand
order, output or aircraft data changes. Out of ground effect, and for aircraft without the downwash lag, the path is
unchanged.

## Profile and scope

A runway-idle script profile of the electric Stik (default field, lake and collision world) counted 13 strip-wing
evaluations per tick, each with its own `_wing_flow`: three per RK stage in `_global_loads` (free-air wake,
ground-effect wake, lag source) and one in `_pre_step` for the lag state. The reuse removes one per stage, four of
thirteen. It applies only while the wheels are within the ground-effect reach: taxi, take-off, landing and
low passes.

The same step hoists loop-invariant work in `Aero._wing_flow` (13 calls per tick on the runway, 5 in flight): the
aileron effectiveness is read once, and the second station loop applies `stall_weight` with the envelope bounds read
once (`a1`, `a2 − a1`, `n1`, `n2 − n1`, the same differences and quotients `_wing_lift_coefficient_with` already
hoists). Reads happen only where the loops would have made them: not for tailless strips, an empty station list or a
zero reference speed.

## Exactness

- [`aero_pair.gd`](../../../../research/performance/aero_pair.gd), `HEAD` `aero.gd` (`df4e1ca5c`) against the working
  tree: `Aero.loads`, `_wing_flow`, `wing_wake_velocity` and `local_flow_weight` for 21,000 random states over seven
  aircraft (electric and glow Stik, Extra with its wing polar, P-51 with flaps, X8 tailless, Avanti, Timber), 6,000 of
  them in ground effect, with random attitude, velocity, rates, servo and flap positions and a downwash-lag value
  where the aircraft has one: 0 mismatches. The reference also lacks the NK-2a flap-guard reorder, so this covers it.
- `session_probe.gd --case=runway` fingerprints (600 warmup and 2,400 sampled ticks) are identical for the Extra,
  Avanti, Timber and Corsair between frozen snapshots with and without H18; the cost pairs below add the electric and
  glow Stik and the P-51.

## Regressions

71 aero, ground-effect, downwash, wing-polar, trim, mode and golden scripts ([summary](tests.txt)): 68 pass, including
`test_golden`, `test_ground_effect`, `test_downwash_lag`, `test_wing_polar` and `test_x8_flying_wing`. The three
failures fail identically before H18 (`df4e1ca5c`); `test_yaw_damping` is the deliberately open R02 gate.

## Cost

`session_probe.gd` (2,400 warmup and 14,400 sampled ticks, no presentation observers), three alternating pairs
between frozen hard-linked snapshots that differ only in `aero.gd` ([cost-pairs.jsonl](cost-pairs.jsonl)):

| Case | Pair 1 µs/tick | Pair 2 | Pair 3 | Median change |
| --- | --- | --- | --- | ---: |
| Electric Stik, runway idle (ground effect) | 2,226 → 2,094 | 2,325 → 2,102 | 2,372 → 2,134 | −9.6% |

Fingerprints are identical in every pair. The glow Stik and P-51 runway pairs and the airborne trim pairs ran while
two other agents saturated the shared host (baseline medians up to twice their quiet values, p95 doubled); they are
inconclusive and kept in the JSON only as a record. Repeat them on a quiet host.
