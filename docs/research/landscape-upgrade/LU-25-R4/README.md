# LU-25-R4 — Reject lake sampling for a hull wholly outside the bank bounds

2026-10-27. Implemented in `b6e3fe7d4` (baseline `d434865f2`). Headless CPU evidence on the
Linux dev VM (Godot 4.8-beta1 official editor binary, shared host); not FPS, release-build
or target-hardware qualification.

## Finding and change

A script profile of the default Stik idling on the runway, with the default field and
lake ([by total](profile/runway-idle-by-total.txt), [by self](profile/runway-idle-by-self.txt)),
put `HullContact.loads` at 14.3 ms of a 67.5 ms step per sample: five calls per tick
(four RK stages and the stage-one evaluation). With a lake installed, each call built a
`{point_ned, terrain}` dictionary for all 36 hull points, rotating each point and
checking it against the bank bounds, before the flat contact law could run. The
runway is far outside those bounds, so every sample was `{covered = false}`.
`HullContact.terminal` repeated the same per-point sampling once per tick.

`_hull_clear_of_lake` returns true when the whole hull is outside the bank bounds
rectangle that `_lake_sample` rejects. It bounds every hull point by
`reach · (1 + 4|q|²) + 1 mm` around the CG. `reach` is the largest hull-point norm, and
`q_rotate`'s formula lengthens a vector by at most `1 + 4|q|²` even for the non-unit
quaternions of RK stage states; the slack covers rounding at field-scale positions. A
nonfinite state compares false and keeps per-point sampling. `loads` (when the caller
supplies no samples) and `terminal` then skip the sampling and take the unchanged flat
branch. Diagnostics still see a lake-equipped contact, so their availability rules are
unchanged.

Unchanged in this slice: `loads_at_properties` (the glow path also uses each point's
position for its finiteness failure) and the prop-disc path.

## Parity

[`hull_lake_pair.gd`](../../../../research/performance/hull_lake_pair.gd) compares the
baseline script with the candidate on the real prepared Stik hull with the default lake.
It builds 2,081 near-ground states: a 41 × 41 grid across the bank bounds ± 40 m and 400
around the runway start, with random attitude, quaternion length 0.9–1.1, velocity and
rates. Per state it compares `loads` without diagnostics, with Array and with
Dictionary diagnostics, the diagnostics themselves and `terminal`, bytewise: **0
mismatches**. The rejection fired for 1,556 states, the covered-lake branch ran for 312,
and 870 states produced contact loads.

`session_probe.gd --case=runway` (default field, lake and collision world, real input
and simulation callbacks) gives the same state fingerprint `9bdb4b7b1a088893` in all six
runs below.

## Cost

Complete session callbacks, 2,400 warmup and 14,400 sampled ticks per run, alternating
order; the baseline file was in the tree only while each process loaded its scripts:

| Pair | Baseline median µs/tick | Candidate median µs/tick | Change | p95 baseline → candidate |
| --- | ---: | ---: | ---: | --- |
| 1 | 3,266 | 2,548 | −22.0% | 4,694 → 3,675 |
| 2 | 3,269 | 2,634 | −19.4% | 4,608 → 4,009 |
| 3 | 3,289 | 2,545 | −22.6% | 4,515 → 3,371 |

Component: `loads` on the 400 runway states falls from 166.1 to 32.9 µs per call
(ratio 0.198, 12 alternating rounds). Airborne flight is unaffected: there the existing
reach test already returns before any sampling.

## Extension to the remaining hull entry points

The post-change runway profile still showed `HullContact.contacts` (the per-tick
presentation feed) at 2.1 ms per sample with the same per-point sampling. The same
rejection now also gates `contacts`, `terminal_at_properties` and, for live-mass glow
aircraft, the per-point `_lake_sample` inside `loads_at_properties`. That function still
computes every point's position, because its finiteness check can fail the stage; only
the known `{covered = false}` answer is skipped.

The extended `hull_lake_pair.gd` adds a glow Stik session (geometry-only hull, live mass
properties). Over the same 2,081 states, `contacts`, `loads_at_properties` with
diagnostics and `terminal_at_properties` (unit previous attitude) are bytewise equal to
the baseline, alongside the original checks; live-mass contact loads occur in more than
100 states. Session runway pairs against the first LU-25-R4 commit:

| Aircraft | Pair 1 | Pair 2 | Pair 3 | Fingerprints |
| --- | ---: | ---: | ---: | --- |
| Electric Stik, median µs/tick | 2,528 → 2,431 (−3.8%) | 2,538 → 2,434 (−4.1%) | 2,550 → 2,473 (−3.0%) | one across 6 runs |
| Glow Stik 61FX, median µs/tick | 5,754 → 5,321 (−7.5%) | 5,458 → 5,273 (−3.4%) | 5,541 → 5,551 (+0.2%) | one across 6 runs |

27 hull, lake, accident, checkpoint, prop-strike, glow and fuel scripts pass with the
extension ([run summary](tests.txt)). The glow runway tick, about 5.5 ms, is more than
twice the electric one and is the next attribution target.

## Rejected follow-up: LU-25-R5

After this change the runway profile's next lake leaf was
`LakeSurface._outside_expanded_polygon_aabb` (38 calls per tick). Replacing its 80
`minf`/`maxf` calls with the identical ternaries `a < b ? a : b` / `a > b ? a : b` kept
parity (0 mismatches over 4,000 points × 3 margins, and 0 in `lake_polygon_pair.gd`) but
was **16% slower** (2.50 → 2.91 µs median, 12 alternating rounds). Built-in utility calls
are cheap in Godot 4.8; the costly calls are into script functions. The change was
reverted.

## Regressions

31 hull, crash, lake, accident, checkpoint, prop-strike and reset scripts ran; 30 passed
at once ([run summary](tests.txt)). `test_lake_geometry_bake` failed one check because
LU-25-R3 had changed a stamped source; after the regeneration recorded there it passes
18/18, and lake world passes 27/27. `test_golden` output is identical, line for line, to
the original baseline `f9e6dbe8d`, across LU-25-R3, GP-19e and this change.
