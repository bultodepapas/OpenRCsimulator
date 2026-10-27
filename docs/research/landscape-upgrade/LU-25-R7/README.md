# LU-25-R7 — Memoize the lake bank bounds

2026-10-27. Working-tree change on baseline `df4e1ca5c` (`lake_surface.gd` from `d434865f2`). Headless CPU
evidence on the Linux dev VM (Godot 4.8-beta1 official editor binary, shared host). No contact, terrain or
geometry change.

## Finding and change

A fresh script profile of the default Stik idling on the runway, after NK-2a, put
`LakeSurface._outside_expanded_polygon_aabb` at 1.44 ms of 50.5 ms script per sample: 38 calls per tick, each
recomputing the 20-vertex bank polygon's bounds with four `minf`/`maxf` calls per vertex. Every wheel terrain sample
(`Terrain.sample_validated` → `_compose_lake` → `sample_covered_terrain_validated`) asks it whether the wheel is
near the lake; on the runway the answer is always no.

[`lake_surface.gd`](../../../../app/physics/lake_surface.gd) now keeps the bounds of the last polygon seen with a
detached copy of that polygon, under a mutex like the existing definition cache. A call reuses the bounds only when
its polygon equals the copy by value (`!=` on packed arrays, so NaN never matches); otherwise it recomputes them with
the unchanged loop (`_polygon_aabb`). Equal polygons can differ only in the sign of a zero vertex, which cannot change
a comparison against a bound ± margin.

The edit restamps the default-lake geometry bake: `tools/ground/bake_lake_geometry.gd` regenerated it, `--check`
passes, and the basin and water content digests are unchanged (`5861457b…`, `666a839d…`).

## Parity

- [`lake_aabb_pair.gd`](../../../../research/performance/lake_aabb_pair.gd), prior script against the working tree:
  1,141,240 calls in a seeded interleaving of the bank, shoreline, ±0-different copies, a NaN vertex, empty and
  one-vertex polygons, a shifted bank and one array edited in place between calls, with points on every bound ±
  margin and the neighbouring doubles, then the covered-terrain and shore-distance queries through the default
  lake: 0 mismatches.
- [`lake_polygon_pair.gd`](../../../../research/performance/lake_polygon_pair.gd) (LU-25-R3 probe, 7,001 points,
  alternating shoreline and bank): 0 mismatches.
- 45 lake, ground, hull and golden scripts ([summary](tests.txt)): 44 pass, including `test_lake_geometry_bake` and
  `test_golden`; `test_companions_lifecycle` fails identically with the prior file, at clean `HEAD` and at
  `f9e6dbe8d`.

## Cost

`sample_covered_terrain_validated` far from the lake (the runway case), 20,000 queries, median of 12 alternating
rounds: 3.16 → 0.94 µs (−70%).

`session_probe.gd --case=runway` (default field, lake and collision world; 2,400 warmup and 14,400 sampled ticks;
no presentation observers), three alternating pairs against a hard-linked snapshot with the prior file, stamp and
bake ([cost-pairs.jsonl](cost-pairs.jsonl)):

| Aircraft | Pair 1 µs/tick | Pair 2 | Pair 3 | Median change |
| --- | --- | --- | --- | ---: |
| Electric Stik | 2,247 → 2,222 | 2,308 → 2,201 | 2,313 → 2,295 | −1.1% |
| Glow Stik 61FX | 4,634 → 4,640 | 4,539 → 4,621 | 4,271 → 4,177 | +0.1% (noise) |

Fingerprints are identical in every pair. The session gain is small because the probe makes about 20 far-lake terrain
samples per tick; the live app adds the ground-audio and statistics observers' samples (38 per tick in the profile).
