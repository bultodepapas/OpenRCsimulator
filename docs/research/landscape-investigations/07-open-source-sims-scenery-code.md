# 07 · What open-source flight sims do in their scenery code

Date: 2026-10-05. **Question:** what do FlightGear, CRRCSim, PicaSim, YSFlight, Slope Soaring Simulator, GeoFS and Godot flight projects do for horizon, sky, trees, terrain and field objects, and what should [LANDSCAPE-PLAN.md](../../LANDSCAPE-PLAN.md) take from them?

GPL, LGPL and PolyForm-NC code: ideas only, nothing copied.

## Findings

**FlightGear** (fgdata is GPL-2; SimGear is LGPL-2.1+)
- **Trees** [src] ([TreeBin.cxx](https://gitlab.com/flightgear/simgear/-/blob/next/simgear/scene/tgdb/TreeBin.cxx), [tree-ALS.vert](https://gitlab.com/flightgear/fgdata/-/blob/release/2024.1/Shaders/tree-ALS.vert)):
  - Each tree is **3 crossed quads**, instanced, and the only per-instance data is its position.
  - The shader derives rotation, scale (0.5–1.5) and atlas variety from `fract`/`sin` of that position.
  - Voronoi "forest effects" scale whole clumps of trees, so the silhouette varies.
- **Wind sway** [src] (same file): `x += z·(sin(t·1.8 + Σpos·0.01)+1)·0.0025·WindN`. It is a shear of the top vertices, driven by simulation time.
- **Placement** [src] ([SGTexturedTriangleBin.hxx](https://gitlab.com/flightgear/simgear/-/blob/next/simgear/scene/tgdb/SGTexturedTriangleBin.hxx)):
  - The seed is fixed (`mt_init(&seed,123)`).
  - Trees per triangle: `density²·slope·area/coverage + rand`.
  - Density thins out between 45° and 60° of slope.
  - An optional mask texture (green channel) gates each tree.
- **README.materials** [doc] ([README.materials](https://gitlab.com/flightgear/fgdata/-/blob/next/Docs/README.materials)):
  - "60 % of the objects will become visible at `range-m`, 30 % at 1.5×, and 10 % at 2×": staggered ranges hide pop-in without any fade.
  - Atlas trees need 8 px of free space above them on a 512 px sheet, or mipmaps produce "top hats" from the row above.
- **ALS skydome** [src] ([skydome-ALS.frag](https://gitlab.com/flightgear/fgdata/-/blob/release/2024.1/Shaders/skydome-ALS.frag)):
  - Below and near the horizon, the dome blends into `terrainHazeColor`, the same haze colour the terrain uses.
  - The band width is `hazeBlendAngle ≈ 1000/visibility + …`, so **one visibility value drives both fog and sky**.
  - The band edge is perturbed by azimuth noise (`horizon_roughness`).
  - The `next` branch moved to Hillaire-style lookup tables (LUTs) and a 2×2 checkerboard dither [src] ([Shaders/HDR](https://gitlab.com/flightgear/fgdata/-/tree/next/Shaders/HDR)).
- **Anti-tiling** [src] ([terrain-ALS-detailed.frag](https://gitlab.com/flightgear/fgdata/-/blob/release/2024.1/Shaders/terrain-ALS-detailed.frag)):
  - UVs are scaled by `0.97+0.06·noise_500m`.
  - Brightness noise uses octaves at 5, 10, 50 and 500 m; the fine octaves are faded out with distance.
  - A second texture is overlaid where 1500–2000 m noise selects it.

**CRRCSim** (GPL-2; 0.9.13, 2016 [rel] [news](https://sourceforge.net/p/crrcsim/news/))
- **Untextured sky dome** [src] ([crrc_sky.cpp](https://github.com/mrtbrnz/crrcsim/blob/master/src/mod_video/crrc_sky.cpp)): colour rings at 90°, 60°, 30° and 0°. A **skirt continues below the horizon**, so no gap ever shows between ground and sky.
- **Davis field** [src] ([crrc_builtin_scenery.cpp](https://github.com/mrtbrnz/crrcsim/blob/master/src/mod_landscape/crrc_builtin_scenery.cpp)):
  - The horizon is **4 textured panorama quads**, about 1.8 km out and 120 m tall.
  - Tree groups are **alpha quads**, about 60 × 30 m.
- **Scenery XML** [doc] ([scenery03.html](https://github.com/mrtbrnz/crrcsim/blob/master/documentation/file_format/scenery03.html)):
  - Objects carry `terrain="0|1"` (whether they count for height and wind) and `visible="0"` (invisible collision box).
  - The same flags can be set inside a model with `-visible`/`-terrain` name suffixes.
- **Slope lift** [src] ([wind_from_terrain.cpp](https://github.com/mrtbrnz/crrcsim/blob/master/src/mod_landscape/wind_from_terrain.cpp)): lift is computed from a terrain profile along the wind.

**PicaSim** (PolyForm Noncommercial 1.0.0, **ideas only** [repo] [LICENSE](https://github.com/Rowlhouse/PicaSim/blob/main/LICENSE.txt))
- **Sky lighting** [src] ([Lighting.xml](https://github.com/Rowlhouse/PicaSim/blob/main/data/SystemData/Skyboxes/Sunny/Lighting.xml)): every sky ships its own sun bearing and elevation plus ambient and diffuse values, so the light matches the image.
- **Environment** [src] ([MeadowPanoramic.xml](https://github.com/Rowlhouse/PicaSim/blob/main/data/SystemSettings/Environment/MeadowPanoramic.xml)):
  - The observer stands at 1.81 m.
  - The runway is 100 × 15 m.
  - A fogged flat "plain" reaches past the 4.5 km terrain (inner radius 5 km, fog at 20 km).
- **Terrain height** [src] ([Terrain.cpp](https://github.com/Rowlhouse/PicaSim/blob/main/source/PicaSim/Terrain.cpp)): triangle-exact, with **alternating diagonals** `(i+j)%2`.
- **SkyGrid** [src] ([SkyGrid.cpp](https://github.com/Rowlhouse/PicaSim/blob/main/source/PicaSim/SkyGrid.cpp)): an optional orientation aid of 8 azimuth × 4 elevation circles drawn on the sky.

**YSFlight** (BSD-3, last commit 2023-07 [repo](https://github.com/captainys/YSFLIGHT))
- Ground and sky are background geometry drawn with depth test `ALWAYS` [src] ([fsgroundskygl2.0.cpp](https://github.com/captainys/YSFLIGHT/blob/master/src/graphics/gl2.0/fsgroundskygl2.0.cpp)):
  - a ground strip that follows the camera;
  - a horizon-to-sky gradient;
  - the seam sits at `atan2(eye_h, farZ)`.

**Slope Soaring Simulator** (GPL, 2006): CLOD terrain [doc] ([site](https://www.rowlhouse.co.uk/sss/)).

**GeoFS** (closed source) [sec] ([Cesium blog](https://cesium.com/blog/2021/12/06/geofs-is-a-flight-simulator-that-showcases-global-satellite/)):
- Ray-marched scattering and clouds as a post-process.
- Instanced trees placed from land-use tiles. The authors call the LOD management "complicated".

**Godot flight projects** [repo]:
- [ZenithFlightSim](https://github.com/nadir-line/ZenithFlightSim) (GPL-3) uses HTerrain.
- [PlenFS](https://github.com/cyteon/PlenFS) (AGPL-3, Forward+) uses Terrain3D and a Poly Haven puresky HDRI.
- [RC-PLANES](https://github.com/MrLeefy/RC-PLANES) (**no license**, 5 days old) builds an "outer skirt so the horizon never shows a hard edge": a ring out to 3.5 km, raised 30–40 m.
- None targets Compatibility or deterministic captures.

**Sketch** (written for this note under the project license, from the ALS, YSFlight and CRRCSim ideas, not their code): the sky's lower half is the far-ground haze, so a ground edge can never show sky.

```glsl
shader_type sky;
uniform vec3 zenith : source_color;
uniform vec3 haze : source_color;   // same constant as fog_light_color
uniform float band = 0.06;          // from visibility_m (ALS hazeBlendAngle)
void sky() {
    float y = EYEDIR.y;
    vec3 c = mix(haze, zenith, smoothstep(0.0, 0.6, y));
    COLOR = mix(c, haze, smoothstep(band, 0.0, y));
}
```

## Libraries / tools found

| Name | Version / last release | License | Compatibility / web? | Fit for us |
| --- | --- | --- | --- | --- |
| FlightGear fgdata/SimGear | 2024.1; `next` active 2026-10 | GPL-2 / LGPL-2.1+ | OSG desktop | Ideas only |
| CRRCSim | 0.9.13 (2016) | GPL-2 | OpenGL 1 | Ideas only |
| PicaSim | main 2026-05 | PolyForm NC | GL ES | Ideas only, never copy |
| YSFlight | 2023-07 | BSD-3 | OpenGL 2 | Copying allowed with the notice; only the idea is needed |
| [Universal Sky](https://github.com/j-c7/universal-sky) | 0.2 alpha, 2026-09-02 | MIT | Claims Compatibility, but reads `TIME` and uses half/quarter-res passes, which GLES3 lacks; clouds need noise textures [src] | Scattering maths reference only |

## What this changes in LANDSCAPE-PLAN.md

1. **L1 (modify):** the sky's horizon band and lower hemisphere use the fog colour. The band width comes from one `visibility_m` in the field file, which also sets the fog distance.
   - **Proof:** below the horizon, sky = fog colour within 2 levels in the 4 horizon views, and the spike's grey edge line is gone with the current 2 km plane.
2. **L2 (simplify):** instead of growing the plane to 6 km, add **one fogged skirt ring** from the plane edge out to about 6 km.
   - **Proof:** +1 draw call; the planned pixel-row test.
3. **L6 (split):**
   - **L6a, horizon cards:** 6–12 alpha-scissor treeline strips at 250–600 m (as in CRRCSim). **Proof:** ≤ 12 draw calls; horizon captures.
   - **L6b, crossed-quad trees:** the placement file stores positions only; rotation, scale and variety are hashed in the shader; clumps get height noise. **Proof:** placement SHA-256; byte-repeat; an atlas-mip test showing no "top hats" (free space above each tree ≥ 1/64 of the sheet).
4. **L8 (modify):** **staggered ranges**. Split each chunk 60/30/10 % into MultiMeshes that end at r, 1.5r and 2r, replacing the fade that Compatibility lacks.
   - **Proof:** in a 10-frame strip, the instances that pop per frame are ≤ ⅓ of an unsplit chunk; the draw calls are counted against the budget.
5. **L9 (modify):** use the FlightGear anti-tiling recipe: UV jitter by noise, brightness octaves at 5–500 m, fine octaves faded with distance.
   - **Proof:** no autocorrelation peak at the texture period in the 30 m capture.
6. **L10/L14 (modify):** field objects carry `collision: none|proxy|self` and `height_contributes` (as in CRRCSim).
   - **Proof:** loader tests; a scripted flight hits a proxy and passes through `none`.
7. **L12 (modify):** the grid header declares its **diagonal rule** (fixed or alternating, as in PicaSim), and both the mesh and the sampler read it.
   - **Proof:** known-sample tests for both rules.
8. **L15:** sway is a top-vertex shear driven by sim time and the wind, with phase from the position (as in FlightGear).
   - **Proof:** the same time and wind give the same capture bytes.
9. **L16:** the photo sky carries its own sun bearing, elevation and ambient in the field file (PicaSim, SeligSIM).
   - **Proof:** shadow direction matches the photo's sun within 2°.
10. **New optional L20, sky-grid pilot aid** (PicaSim). Gate L decides.
    - **Proof:** captures with it on and off; trace bytes unchanged.
11. **After M5:** slope lift from the terrain profile (CRRCSim), noted only.

## Not confirmed

- The syntax of CRRCSim's `population` tag: it is announced in the news, but missing from the 2013 GitHub mirror.
- How Universal Sky behaves in Compatibility.
- FlightGear wiki pages returned HTTP 403, so the source code was used instead.
- The cost of 60/30/10 staggering at the L6b tree count; this needs the L0 counters.
