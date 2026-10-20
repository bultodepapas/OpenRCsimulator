# LU-16-R2 — Mountain surface detail and finer crests

2026-10-20 · Native Windows, Godot 4.7.2 Compatibility / RTX 3090, 1280 × 720.
Baseline is the [LU-16-R1 implementation](../LU-16-R1/README.md) from the same
working tree; its geometry and shader fixtures are retained here.

The first relief pass left broad uniform slopes and visibly angular crests.
This refinement adds source-shaped dark gullies, green uplands, photographic
rock/scree variation and a finer silhouette. The 1.6–8.6 km placement, shared
atmospheric haze and visual-only role remain unchanged.

[Before detail](before-detail.png) · [After detail](after-detail.png) ·
[Pilot](pilot.png) · [Oblique](oblique.png) · [Aircraft](aircraft.png) ·
[Dusk](dusk.png) · [Night](night.png).

## Research and implementation

- Downloaded **Aerial Grass Rock** and **Aerial Rocks 01**, by Rob Tuytel /
  Poly Haven, under CC0. Official asset pages:
  [grass/rock](https://polyhaven.com/a/aerial_grass_rock),
  [rocks](https://polyhaven.com/a/aerial_rocks_01);
  [provider license explanation](https://docs.polyhaven.com/en/faq).
  Use unchanged 1K JPG downloads, not the much larger full material packages.
  [Exact source URLs, SHA-256 and modifications](../../../../app/assets/landscape/mountains/sources.json).
- `bake_mountain_habitat.py` classifies slope, broad concavity and relative
  altitude into a 513 × 193 RGB mask. This is artistic vegetation/rock placement,
  not a measured biome or hydrological prediction. Runtime uses four texture
  samples: source normal/cavity, habitat, grass/rock and scree. World coordinates
  keep texture projection continuous across chunks. Rotated photographic layers
  use different artistic footprints to reduce aligned repetition.
- Mipmapped anisotropic filtering limits distant aliasing; the photographs use
  VRAM compression, while normal/cavity and habitat masks stay lossless.
  [Godot texture import guidance](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html)
  describes these compression and mipmap tradeoffs.
- Use a dry Lambert response consistent with the field, without mountain
  specular calculations. Haze and lighting still update the same scene-local
  material. Vertex colors are no longer needed and were removed.
- Increase the static grid from 128 × 48 to 192 × 72 cells, retaining four
  cullable chunks. This is **27,648 triangles**, up from 12,288. No added draw
  calls, shadow-caster passes, per-frame terrain callbacks or runtime plugin.

### Why automatic LOD was not adopted

The [ImporterMesh API](https://docs.godotengine.org/en/stable/classes/class_importermesh.html)
and [mesh LOD guidance](https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html)
motivated an offline 256 × 96 probe. Five generated levels halved triangles
from 49,152 down to 1,536. But independently simplified chunks changed shared
edge segments: one seam at LOD1 and all three at LOD2. Their transition thresholds
also differed. Keeping these levels would require additional seam management.
The four saved meshes totaled 1,189,028 bytes. The probe was rejected.

Against 24,929 samples on the filtered source's 256 × 96 grid, triangle-height
p95/max error falls from **31.18/127.61 m** for 128 × 48 to
**19.49/73.09 m** for 192 × 72. These are sampled approximation errors, not
camera-space measurements or physical accuracy. The source is artistically
scaled and the comparison grid favors the 256 × 96 candidate.
[Profile comparison](profile-report.json) · [LOD/seam report](lod-report.json).

## Repeated render measurement

Three alternating R1/R2 pairs, 360 measured frames per view per process,
same cameras and disabled VSync. Values below are the **median of the three
per-run p95 values**, not pooled p95. The benchmark reconstructs R1's mesh and
shader before warmup, leaving the field and lighting shared.

| View | R1 p95 ms | R2 p95 ms | Draws, unchanged | Scene primitives R1 → R2 |
| --- | ---: | ---: | ---: | ---: |
| Pilot north | 1.618 | 1.710 | 84 | 204,089 → 219,449 |
| Mountain detail | 0.946 | 0.955 | 4 | 94,176 → 105,696 |
| Oblique | 1.840 | 1.948 | 19 | 116,233 → 127,753 |
| Aircraft readability | 1.427 | 1.532 | 312 | 302,745 → 318,105 |

Scheduling variation is visible in the raw reports; no speedup is claimed.
The highest individual candidate p95 was 2.177 ms. This is a render-only
desktop measurement, not full-flight or lower-end hardware acceptance.
Benchmark references preload candidate textures too, so their memory totals
must not be used as the full R1 memory baseline.

The clean R1 reference reports 421,348,166 total GPU bytes; final R2 reports
423,364,710: **+2,016,544 bytes / 1.92 MiB**. Of that, 1,793,456 bytes are
the new imported textures and 223,088 are net mesh growth. The uncompressed
candidate reached 430,412,420 bytes; compression and removing unused vertex
colors avoided about 6.7 MiB. These totals include the whole field.

Raw [summary](measurement-summary.json), `reference-1/2/3-report.json`,
`final-1/2/3-report.json`, and the clean `r1-memory-reference-report.json`
are retained. Reproduce alternating captures with:

```powershell
python docs/research/landscape-upgrade/LU-16-R2/benchmark.py
```

The driver rebuilds scratch reference fixtures and invokes the checked runner.
Its default output is `tmp/mountains-r2-repeat`; paths and process arguments
are recorded in each report. It requires the repository's installed Windows
Godot binary. The checked-runner logs are in `checks/`.

## Verification and limits

- Both offline generator `--check` commands reproduce committed outputs.
  A disposable edited habitat image is rejected.
- Native import and all final day/dusk/night captures complete without
  script or shader errors. Images were visually inspected.
- `test_landscape_horizon.gd`: **48 checks, zero failed**, including every
  triangle's winding, exact seams, bounds, texture sizes/mips, shared material
  ownership and time updates without replacement geometry.
- `test_landscapes.gd`: **49 checks, zero failed**, including Club/Green
  switching, persisted selection and airplane/helicopter simulation.
- `test_world_flow.gd`: **26 checks, zero failed**.
- Download identities, generated resources and final implementation hashes
  are retained in [verification.json](verification.json).

The known maple-material wind warning persists; the flow test also deliberately
checks an invalid negative time scale. No new warning was introduced. R1's broader
field/runway integration results remain recorded in its report. This pass does
not rerun the full test suite or exports, and does not change physics, collisions,
controls or golden flight recordings. Close flight into this decorative backdrop
is not physical terrain support.
