# LU-22-R2 · Aquatic plant detail

2026-10-20 · Godot 4.7.2 Compatibility, native NVIDIA RTX 3090 capture.

The Club lake now has 105 notched Nymphaea leaves, 14 small blossoms and 21
emergent reed clumps. Seven floating colonies and three reed coves leave the
center open. A fixed seed, nearest-shore distance, and validated lake-bed
samples place leaves in 0.30–1.15 m water and reeds in at most 0.38 m water.
The leaves and blossoms are one MultiMesh each; reed source parts retain their
four materials with local, muted freshwater colors. The floating shader uses
the lake's simulation clock, wave parameters and shore fade. Plants are visual
only and add no aircraft contacts or buoyancy.

The leaf and flower are downloaded [CC0 source meshes](../../../../assets/landscape/pond-plants/README.md).
Existing Aredon CC0 reeds are reused. The [RHS growing guide](https://www.rhs.org.uk/plants/waterlilies/growing-guide)
informed the shallow planting band and the decision to leave open water. The
[Missouri Conservation cattail guide](https://mdc.mo.gov/discover-nature/field-guide/cattails)
informed the emergent plant margin. These are artistic placements, not a
habitat survey.

## Native evidence

- [Matched baseline](before/lake_shore.png) and [accepted lake shore](accepted/lake_shore.png).
- [Matched baseline overview](before/lake_overview.png) and [accepted overview](accepted/lake_overview.png).
- [Close plant and shallow shelf view](accepted/lily_detail.png).
- [Same close view at simulation clock 3 s](accepted/lily_wave_3s.png), showing
  the floating plants against a changed analytic water surface.
- [Baseline](before/capture.json) and [accepted](accepted/capture.json) renderer records.

The three matched camera views rose from 78/32/104 to 93/47/115 visible draw
calls (shore/bank/overview). Those are scene-view counts on this machine, not
an FPS or lower-end GPU claim. The bank shader and baked geometry sources are
unchanged. The captures show the pad silhouette and open-water composition;
some low-poly character remains in the reused reed asset at close range.

## Checks

- `test_lake_plants.gd`: deterministic counts, depth/shore constraints, source
  mesh batches, no added collision and bounded source triangles — pass.
- `test_lake_world.gd`: 27 checks, 0 failed.
- `test_lake_geometry_bake.gd`: 18 checks, 0 failed.
- `test_lake_surface.gd`, `test_field_integration.gd`: pass.
- `test_downloaded_habitats.gd`: 329 checks, 0 failed.
- Blender 5.2.2 re-export reproduced both GLB SHA-256 values in the source ledger.
- `git diff --check`: pass.

Independent pilot readability and target lower-end hardware cost remain open.
