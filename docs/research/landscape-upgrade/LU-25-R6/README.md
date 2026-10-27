# LU-25-R6 — Reject the lake swept query before building its probes

2026-10-27. Working-tree change on baseline `b6e3fe7d4`. Headless CPU evidence on the Linux
dev VM (Godot 4.8-beta1 official editor binary, shared host). No contact, event or
timing-rule change.

## Finding and change

`LakeCollision.first_hit` runs at every accepted tick. In the airborne profile it cost
2.26 ms per sample far from the lake: before its altitude and bank-bounds rejects it built a
probe dictionary (slice, norm and dictionary) for every hull point, gear contact and the
propeller, and computed both polygon bounds. The rejects need only the bounding radius.

`_first_hit_core` now computes the radius first (same points, filters and order), runs both
rejects, and only then computes the shoreline bounds and builds the probe list exactly as
before. `_gear_probe_point` holds the shared gear-contact filter.

## Parity

[`lake_collision_pair.gd`](../../../../research/performance/lake_collision_pair.gd) runs
the baseline and candidate `first_hit` on the default Stik hull, gear and propeller with
the default lake: 5,844 tick pairs (a 31 × 31 grid across the bank bounds ± 60 m at four
heights from 1.5 m to below the water level, plus 2,000 distant airborne ticks, random
attitude, velocity and rates). All 112 water or bank hits and all misses are equal by
content, including the nested crossing record. Lake collision, lake session, lake ground
contact, water checkpoint/director/effects, prop strike and feedback, crash hull labels,
checkpoint and checkpoint integrity scripts pass, and `test_golden` reports 0 failures
([summary](tests.txt)).

## Cost

Distant airborne `first_hit`, median of 12 alternating rounds over 2,000 ticks:
62.1 → 29.4 µs (ratio 0.474). About 33 µs per tick in flight on this host, roughly 1% of
main-thread CPU; a component result, not resolvable in whole-app pairs.
