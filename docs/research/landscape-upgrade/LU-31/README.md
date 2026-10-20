# LU-31 — Lossless landscape construction optimizations

2026-10-20. Two measured CPU changes preserve the downloaded assets, density,
materials, lighting, collisions and rendered detail.

- Botanical placement builds the existing near-grass exclusion grid once for
  land and once for shore candidates. The narrow-phase acceptance checks,
  clearance, deterministic seeds and bounded scalar fallback are unchanged.
  Grids are local to each layout call, so edited fields do not reuse stale data.
- Imported vegetation and population triangle accounting uses ArrayMesh buffer
  lengths instead of fetching and unpacking every vertex attribute. Primitive
  meshes retain the general array fallback. Indexed meshes count indices.

The [Godot ArrayMesh API](https://docs.godotengine.org/en/stable/classes/class_arraymesh.html)
provides the vertex/index length queries used by the fast path. No new
dependency, resource cache or per-frame callback is introduced.

## Measurements

Pinned Godot 4.7.2; native Windows, RTX 3090, Compatibility/OpenGL. The
component comparisons alternate reference/candidate order in the same process.

| Work | Before | After | Scope |
| --- | --- | --- | --- |
| Count 48 source/primitive meshes, 149,074 triangles | 11.889 ms | 0.051 ms | Median per pass, seven pairs of ten passes |
| Default lake, high-quality botanical layout | 43.047 ms | 37.512 ms | 15 alternating pairs |
| No-lake, high-quality botanical layout | 15.333 ms | 10.498 ms | 15 alternating pairs |
| Complete warm scenery rebuild | 311.529 ms | 224.058 ms | Median of five alternating pairs after warming both variants |
| Native capture scenery construction | 824.287 ms | 788.681 ms | One process per variant |

Botanical median improvements range from 12.6% to 53.3% across the 12 tested
quality/world combinations. The complete-build samples vary substantially
with shared desktop load; the observed 28% warm-rebuild difference is not a
guaranteed application startup or frame-rate improvement. The stable component
measurements, not an FPS claim, justify keeping the changes.

Native captures use identical 1280×720 cameras, noon, fixed botanical clock,
4× MSAA and 360 measured intervals after warmup:

| View | Before/after p95 | Before/after draw calls | RGB pixels |
| --- | --- | --- | --- |
| Farm | 1.067 / 1.109 ms | 48 / 48 | Identical |
| Airfield | 2.508 / 2.384 ms | 294 / 294 | Identical |
| Pilot looking east | 2.062 / 2.129 ms | 167 / 167 | Identical |

These frame measurements show no conclusive FPS gain. Rendered primitive
counts are identical. CPU construction and bookkeeping are the optimized work.

## Verification and limits

- Exact recursive plant-record parity in all three qualities with the default
  lake, no lake, a custom gravel exclusion and a translated field/scenery.
  The custom exclusion demonstrably changes placement; all indexed cases use
  nonempty grids. Default high quality still contains 285 botanical plants.
- All 48 mesh counts agree with the original array-reading implementation,
  including QuadMesh and BoxMesh fallbacks.
- Complete scenery rebuilds preserve the cell position/normal/color hash
  `7b444a3defa85b016599c992f945459b6cd2e0f7d98a3874127f67134656bc22`.
- Existing imported-vegetation, botanical-habitat, population-asset and
  complete scenery-build tests pass, including the existing build budget,
  determinism, winding and quality checks.
- The grass-mask integration suite has **three existing failures** concerning
  grass row IDs and translated-field expectations. All three reproduce using
  the preserved pre-optimization implementations; both checked logs are
  retained. This round does not claim a fully green repository suite.
- The pre-existing unsupported maple wind-material warning remains.
  Lower-end hardware and complete flight-session performance are unmeasured.

The first native attempt needed resource import for concurrently added
flightline textures. Accepted before/after captures use those same imported
assets. Unrelated field, ground and flightline edits were preserved.

## Evidence and reproduction

[Measurement summary](performance.json), [paired rebuild records](build-pairs.json),
[botanical parity/timing report](botanical/exclusion-grid-probe.json),
[checked runs](checks/), [source hashes](source-identity.json),
[before screenshots/report](native-before/), [after screenshots/report](native-after/).

The retained `bench_counts.gd` compares the old array read with the production
fast paths. Run it with the checked runner and the native console engine.
`bench_build.gd`, `prepare_build_probe.py` and the `*.before.gd` files retain
the dated comparison harness. To reproduce that harness on the recorded
Windows workspace, copy this folder's probe files and `botanical/` into
`tmp/landscape-perf/`, run `prepare_build_probe.py`, then launch
`bench_build.gd` through the checked runner with `--headless --path app`.
The botanical runner records its source identities and full parity results.
Absolute scratch paths in the original harness identify the measured
workspace; adjust them when reproducing elsewhere.
