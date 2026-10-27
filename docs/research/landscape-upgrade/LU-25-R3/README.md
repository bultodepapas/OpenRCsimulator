# LU-25-R3 — Inline the lake polygon edge distance

2026-10-27. Implemented in `226f66b98` (baseline `f9e6dbe8d`). Headless CPU evidence on
the Linux dev VM (Godot 4.8-beta1, 12 vCPU, shared host); not FPS, GPU or target-hardware
qualification.

## Finding and change

A complete live-app script profile ([VQ-01c tick attribution](../../visual-quality-implementation/VQ-01c/tick-observers-2026-10-27/README.md))
flew the Stik near the default lake. Per profile sample (about 11 ticks),
`LakeSurface._point_segment_distance_sq` ran 111,120 times from 5,508 `_polygon_state`
calls. Each terrain stencil point walks both 20-vertex polygons, and a GDScript call per
edge cost more than its arithmetic.

`_polygon_state` now computes the clamped point-segment distance inline, with the same
operations in the same order, and replaces `(index + 1) % count` with a conditional.
`_contains` and `_polygon_boundary_distance` keep the helper; they are not hot. No
data, timestep, cache or physics arithmetic changes.

## Parity

[`lake_polygon_pair.gd`](../../../../research/performance/lake_polygon_pair.gd) compares
the baseline script with the candidate on the default lake: 7,001 points (61 × 61 grid
over the bank box plus 20 m, every vertex and edge midpoint, edge offsets of 1e-9 to
0.03 m, 3,000 seeded random points). Per point it compares `_polygon_state`,
`_polygon_boundary_distance`, `_contains` and the expanded-bounds test for both polygons,
then `sample_terrain_validated`, `sample_covered_terrain_validated` and
`shore_distance_validated`, all bytewise: **0 mismatches**.

An independent read-only review found no counterexample. It checked zero-length edges
(the loader allows duplicate consecutive vertices), NaN/INF inputs, polygon sizes 0 and
1, and that GDScript evaluates each operator separately, so nothing fuses. These edge
cases are argued analytically; the probe exercises only the real lake.

Passing scripts: lake surface, covered sampling (761 checks), lake collision, lake ground
contact, lake session (35), lake definition cache, ground support query (114), hull
support normal (70), RCV airfield course, lake probe ambient (8), lake world (27).
`test_golden` output is identical, line for line, to the unmodified baseline.

## Cost

Twelve alternating rounds of `sample_terrain_validated` over the 2,730 probe points
inside the expanded bank box:

| Run | Baseline median µs/query | Candidate median µs/query | Ratio |
| --- | ---: | ---: | ---: |
| 1 | 138.68 | 86.60 | 0.624 |

A control run with the unchanged script as both roles gave a ratio of 0.962, which
bounds this probe's order/noise effect. This is a component result: it applies while
the aircraft or a wheel samples terrain inside the lake's expanded bounds, which
LU-25-R2 already rejects elsewhere. No complete over-lake session gain is claimed here.
