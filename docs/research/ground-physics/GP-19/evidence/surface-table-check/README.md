# GP-19g — Memoize the surface-table guard

2026-10-27. Working-tree change on baseline `df4e1ca5c`. Headless CPU evidence on the Linux dev VM (Godot 4.8-beta1
official editor binary, shared host). No terrain, contact or validation-rule change.

## Finding and change

A runway-idle script profile of the default Stik (after NK-2a) showed `GroundTerrain.is_valid_surface_table` about
20 times per tick: every wheel, compression, anchor, support and audio entry point re-checks the same field table
before sampling it. Unprofiled, one check of the default four-row table costs 2.0 µs.

[`ground_terrain.gd`](../../../../../../app/physics/ground_terrain.gd) keeps the last table checked as a detached
copy, with its verdict, under a mutex (callers include worker threads). A call returns the stored verdict only when
its table equals that copy by value (`==` on packed arrays); otherwise the unchanged row walk
(`_surface_table_is_valid`) decides and replaces the entry. Equal tables can differ only in the sign of a zero, which
none of the checks distinguishes, and a table containing NaN never compares equal, so it is always walked.

The edit restamps the default-lake geometry bake (`ground_terrain.gd` is a stamped input):
`tools/ground/bake_lake_geometry.gd` regenerated it, `--check` passes, and the basin and water content digests are
unchanged (`5861457b…`, `666a839d…`).

A packed per-wave table for the microrelief sampler was also tried. It was exact but saved only 4.5% of a terrain
sample (4.19 → 4.00 µs), so it was reverted.

## Parity

[`terrain_pair.gd`](../../../../../../research/performance/terrain_pair.gd), prior script against the working tree:
256,703 calls of `is_valid_surface_table`, `max_height`, `sample`, `sample_profiled`, `sample_validated` and the
raw microrelief sampler. The tables interleave the default field's table with ±0, NaN, bad-friction, bad-outside-row,
empty and truncated variants and one table edited in place between calls; points include NaN, ±INF and ±0, with and
without the default lake; plus 200,000 raw samples across the runway, mown and rough edges. 0 mismatches.

## Cost

Unprofiled, median of 12 alternating rounds of 20,000 calls on the default field table:

| Call | Prior µs | Candidate µs | Change |
| --- | ---: | ---: | ---: |
| `is_valid_surface_table` | 2.006 | 0.286 | −86% |
| Table check + one runway `sample_validated` with the lake | 8.41 | 6.34 | −25% |
