# LU-17 — near vegetation

Status at this snapshot: isolated implementation staged for lead review; native visual acceptance pending. Evidence date: 2026-10-12. Current status: [landscape integration guide](../../../LANDSCAPE-PLAN.md#landscape-integration).

## Image review

I inspected the LU-11 daylight `car_park.png` and `postcard_pavilion.png` captures directly, alongside the LU-15 critique. The nearby shade trees read as broad, sharply faceted masses with similarly spaced lobes. The tiny flowers are bright ground specks, and the shrubs repeat the same low-poly lump treatment. The distant forest has a different visual character. LU-15 correctly prioritizes these broad forms over additional props.

## Staged changes

The implementation is isolated in `.tools/lu17-stage/app`; no live `app/` source was changed.

- `scenery/vegetation.gd` builds crown masses with interpolated vertex normals and a restrained vertex-colour light field. It uses less regular, seed-stable branch-end sprays with small gaps, while keeping the three crown habits. The same helper rounds shrub foliage. Tree/shrub construction remains in the existing opaque cell batches; no nodes, materials, per-instance callbacks, collision objects or downloads were added. Existing `crown` and `bush_tips` motion dictionaries, mode, pivots and rates are retained.
- `scenery/flowers.gd` keeps `cushion_mesh()` and `Flowers.build()` interfaces. The old 21-triangle ground dome is replaced by a 24-triangle cluster: three narrow stems, three two-triangle leaf blades and three small four-petal heads. Petal vertices still use `INSTANCE_CUSTOM` for species colour; the gold centers and foliage use vertex colour. Placement, species mix, theme handling, 60 m chunks and per-chunk MultiMesh count are unchanged.
- `scenery/flowers.gdshader` maps the existing clock-driven sway to the new 0.42 m plant height. The same `sim_clock`, wind input and displacement amplitude remain in use; custom bounds still include the existing 0.2 m allowance.
- `tests/test_landscape_vegetation.gd` checks the three seeded habits, deterministic geometry, a 256-seed canopy envelope sample, the single mode-3 crown part, plant parts/footprint, shared flower mesh/chunking, existing 48 cells/28 moving parts/2,970 instances, and the 180,000-triangle ceiling.

The tree catalog and collision sources are untouched. Across 256 baseline seeds, the prior maximum absolute X/Z crown extents were 3.836/3.814 m and maximum height was 9.996 m. The staged test keeps geometry within ±3.84 m X/Z and 0–10.0 m Y, including the rotating mode-3 crown tips. The seed-1234 prefab probe is slightly narrower than before: 5.89 × 9.56 × 5.65 m staged versus 6.09 × 9.56 × 6.05 m baseline. This remains inside the existing 8 × 10.5 × 8 m catalog envelope; the lead should review its visible silhouette in the native close capture.

## Budgets and checks

| Metric | LU-11 baseline | Staged LU-17 | Result |
| --- | ---: | ---: | --- |
| Whole-scene geometry triangles | 158,953 | 174,281 | +15,328; 5,719 below the 180k cap |
| Wildflower mesh | 21 per plant | 24 per plant | +8,910 across 2,970 plants |
| Static cells | 48 | 48 | unchanged |
| Motion parts | 28 | 28 | unchanged: 10 crowns and 6 shrub tips |
| Flower instances / chunks | 2,970 / existing 60 m layout | 2,970 / same layout | unchanged |
| Added draw/material/node | 0 | 0 | unchanged batching paths |

Godot 4.7.2 headless checks in the isolated project:

- `test_landscape_vegetation.gd`: **23 checks, 0 failures**; total **174,281** triangles.
- `test_scenery_build.gd`: **all checks pass**, including deterministic rebuilds, catalog sizes, triangle winding, tier counts, **48 cells**, **28 motion parts**, and the existing **400 ms** build guard (279.8 ms reported in this run).
- `--headless --editor --path .tools/lu17-stage/app --quit`: completed the project scan with exit code 0.

No native renderer or capture was run. The 279.8 ms value is the existing headless scene-construction guard, not a performance benchmark. Geometry and batching regressions are covered headlessly, but foliage readability, smoothness at 5/15/40 m, flower shimmer during camera movement, paused-clock stability in the live scene and image contrast remain pending the lead's matched native review after LU-16 integration.
