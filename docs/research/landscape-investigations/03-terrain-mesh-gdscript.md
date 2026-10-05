# 03 · Chunked heightmap terrain in GDScript with a float64 exact sampler

Date: 2026-10-05 · **Question:** how do we build heightmap terrain chunks (and distant terrain) in Godot 4.7 GDScript so that a float64 sampler in `sim/` returns the rendered height exactly, and what does it cost?

## Findings

**Engine facts (Godot 4.7.2-stable source, tag `ed1daf0`)**

- **16-bit indices up to 65 536 vertices.** `if (p_vertex_len <= (1 << 16))` picks 2-byte indices ([rendering_server.cpp L1048](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/rendering_server.cpp#L1048)) [src]. Measured: 256×256 vertices → 2.0 bytes/index, 257×257 → 4.0 [measured]. **A 255-quad chunk is the largest with 16-bit indices.**
- **Positions stay float32 unless `ARRAY_FLAG_COMPRESS_ATTRIBUTES` is set.** With the flag they are stored as 16-bit fractions of the AABB ([L465–473](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/rendering_server.cpp#L465)) [src], which would break exactness. Normals are always octahedral 2×16-bit ([L611–628](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/rendering_server.cpp#L611)) [src], which affects lighting only.
- **The AABB comes from the vertices** (`_compute_aabb_from_points`, same file) [src]. `custom_aabb` is only needed when a shader moves vertices ([ArrayMesh doc](https://docs.godotengine.org/en/stable/classes/class_arraymesh.html)) [doc]. CPU-built chunks don't need it.
- **Winding:** Godot front faces are clockwise ([ArrayMesh tutorial](https://docs.godotengine.org/en/stable/tutorials/3d/procedural_geometry/arraymesh.html)) [doc]. With x = i·h and z = j·h, the triangles `(a, b, d)` and `(a, d, c)` (a = (i,j), b = (i+1,j), c = (i,j+1), d = (i+1,j+1)) give `Plane(a,b,d).normal = (0,1,0)`, and Plane takes points in clockwise order ([Plane.xml](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/Plane.xml)) [doc][measured].
- **EXR:** in 4.7 the tinyexr module builds on every platform (`can_build → True`, [config.py](https://github.com/godotengine/godot/blob/4.7.2-stable/modules/tinyexr/config.py)) [src], and `Image.load_exr_from_buffer` exists ([Image.xml](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/Image.xml)) [doc]. But a `.exr` under `res://` is imported as a texture, so use it only offline (GDAL) [inference].
- **Raw data:** `FileAccess.get_buffer()` with `PackedByteArray.to_int32_array()` or `decode_s16()` ([PackedByteArray.xml](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/PackedByteArray.xml)) [doc]. Exports only ship `data/*.json` today (`app/export_presets.cfg` `include_filter`) [src], so a `.bin` needs a filter change in all three presets.

**How others do it**

| Project | Mesh | Diagonal | Physics vs render |
|---|---|---|---|
| Terrain3D ([mesher](https://github.com/TokisanGames/Terrain3D/blob/main/src/terrain_3d_mesher.cpp)) [src] | Clipmap (tile/edge/fill/trim pieces), recentred on the camera, shader displacement | LOD0 "standard" grid has a fixed diagonal; LOD1+ alternates `(x+y)%2` | The collision code turns the `HeightMapShape3D` −90° "to match triangulation of heightmapshape with the mesh" ([collision.cpp L42–47](https://github.com/TokisanGames/Terrain3D/blob/7c11fd2fe293a0a520679180ba3446a9171434e5/src/terrain_3d_collision.cpp#L42)) [src]: the diagonal trap is real |
| HTerrain ([mesher](https://github.com/Zylann/godot_heightmap_plugin/blob/master/addons/zylann.hterrain/hterrain_mesher.gd), MIT) [src] | Flat chunks, 16 seam variants × LODs, shader displacement, custom AABB | Checkerboard flip | Bilinear CPU height: no match |
| cuberact planet ([chunk.gd](https://github.com/cuberact/godot-cuberact-planet-chunked-lod/blob/main/scripts/chunk.gd), MIT, 2026-03) [src] | GDScript chunked LOD with **skirts** (0.15 × chunk radius) | — | — |
| GPU Gems 2 ch. 2 ([Asirvatham & Hoppe](https://developer.nvidia.com/gpugems/gpugems2/part-i-geometric-complexity/chapter-2-terrain-rendering-using-gpu-based-geometry)) [AP] | n = 255 rings, 64² blocks, L-trim, degenerate perimeter triangles, morph width n/10; simplified by [Savage](https://mikejsavage.co.uk/geometry-clipmaps/) [sec] | — | — |

**For us the camera is the pilot, and the pilot doesn't move** [inference]. Clipmaps exist for a moving camera; for us the same nested rings can be **built once and never recentred**: no LOD switching, popping or runtime seams. The chase camera stays inside LOD0.

**Spike** [measured]: `spike_terrain.gd` (sha256 `4b61fda0…`, scratch only), Godot 4.7.2 `--headless`, this VM, 2 runs. Grid 256×256 at h = 4 m, integer-hash relief of 0–8 m, heights quantised to 1/256 m.

| Measurement | Result |
|---|---|
| Build a 256² mesh, direct `Packed*Array`s + central-difference normals | 88–105 ms (best of 3) |
| Same area as 16 chunks of 64² quads (normals from the **global** grid, so no lighting seam) | 100–125 ms |
| `SurfaceTool` + `generate_normals()` | 228–237 ms (2.3× slower) |
| `surface_get_arrays()` readback in headless (dummy server) | works: 65 536 verts, 390 150 indices |
| max \|vertex − grid\| (x and y) | **0.0** |
| 100 000 random points, float64 sampler vs barycentric on the readback triangles | **0.0 m** |
| Same, sampler using the *other* diagonal | **0.025 m** (with only 8 m relief) |
| Unquantised 0–60 m heights stored as float32 | up to 1.9e-6 m error; quantised 1/256 m within ±128 m: 0.0 |
| Sampler cost (GDScript) | 1.1–1.8 µs per call |
| sha256 of vertex bytes, run 1 and run 2 | `031eb94a94684284` both runs |

Sampler core (project MIT; diagonal (i,j)–(i+1,j+1), `hq` = int/256.0):

```gdscript
func height(x: float, z: float) -> float:
	var u := (x - X0) / H
	var v := (z - Z0) / H
	var i := clampi(int(floor(u)), 0, N - 2)
	var j := clampi(int(floor(v)), 0, N - 2)
	var fu := u - i
	var fv := v - j
	var h00 := hq(i, j)
	var h11 := hq(i + 1, j + 1)
	if fu >= fv:   # triangle a,b,d
		var h10 := hq(i + 1, j)
		return h00 + fu * (h10 - h00) + fv * (h11 - h10)
	var h01 := hq(i, j + 1)   # triangle a,d,c
	return h00 + fv * (h01 - h00) + fu * (h11 - h01)
```

Exactness depends on four rules: spacing H and origin are powers of two (or integers), heights are multiples of 1/256 m within ±128 m (or ±8192 m with int32), compression flags are never set, and the sampler and the index builder share one diagonal constant.

## Libraries / tools found

| Name | Version / last activity | License | Compatibility / web | Fit for us |
|---|---|---|---|---|
| DIY `ArrayMesh` chunks (spike) | Godot 4.7.2 | ours (MIT) | plain meshes: yes / yes | **Chosen**: exact, ~0.1 s build |
| Terrain3D | v1.0.2 (2026-05-19), pushed 2026-10-03 | MIT | yes / experimental | Reference for clipmap pieces and the diagonal trap; stays the L18 gate |
| HTerrain (Zylann) | no releases; pushed 2026-07-30 | MIT (LICENSE.md; GitHub shows NOASSERTION) | undocumented | Reference for seam index patterns |
| cuberact planet chunked LOD | pushed 2026-03-22 | MIT | GDScript, 4.6 | Reference for skirts in GDScript |
| tinyexr in Godot | built into 4.7 templates | BSD-3 | yes | Offline DEM interchange only |

## What this changes in LANDSCAPE-PLAN.md

1. **L12 (split into L12a/L12b).**
   - **L12a `sim/terrain.gd`:** sampler + grid loader. Format `openrc-terrain v1` JSON (exported by the existing `data/*.json` filter): `{value, unit, kind, source}` for H, origin, N, quantum; `heights_q` ints or `"constant": 0`; `sha256`. Add an **altitude early-out**: skip the query when the lowest body point is above `max_height + 1 m`.
     *Proof:* known-sample tests (vertices, both triangles, the diagonal line, the clamped edge); goldens and `--trace` bytes unchanged; `bench_physics` µs/tick before and after.
   - **L12b `render/terrain_mesh.gd`:** builds the LOD0 chunks from the same loader and the same `DIAGONAL` constant: 4 m spacing, 257² vertices over ±512 m, 4×4 chunks of 64 quads (65² vertices, 16-bit indices, one `MeshInstance3D` each), global central-difference normals, no compression flag.
     *Proof:* a headless readback test runs `surface_get_arrays` on every chunk and checks, at 10⁵ seeded points, sampler − mesh = 0 (tolerance 1e-9); vertex hash stable; capture byte-repeat; 16 draw calls.
2. **New L12c, far ring (visual only):** one static ring from 512 m out to about 2.5 km at 32 m spacing, built once around the pilot (a fixed clipmap, no recentring). Cracks are removed **offline**: the generator makes LOD0's outer border heights linear between every 8th vertex, so the coarse edge matches exactly (no skirts). Add an out-of-range boundary at ±512 m so physics never needs the far ring.
   *Proof:* a watertight test where every edge is shared by 2 triangles except the outer rim; horizon capture without sky through the seam.
3. **L13 (amend):** the offline generator writes `heights_q` as integers and records its seed and tool version. Integer/fixed-point noise, not FastNoiseLite.
   *Proof:* regenerate → same sha256; crash on a hillside caught in a scripted trace.
4. **L17 (amend):** a DEM (CNIG) goes GDAL → EXR/GeoTIFF → offline resample to the 4 m power-of-two grid → `heights_q`. Never load EXR at runtime.
5. **Budget line:** terrain build ≤ 150 ms at startup; LOD0 is 66k vertices / 1.3 MB VRAM.

## Not confirmed

- Real GPU upload and draw cost of 16 chunks + ring on llvmpipe and on the web. Only the headless dummy server was measured, with no visual capture of the terrain.
- Sampler cost inside the 240 Hz loop with several contact points (measured per call in isolation only).
- JSON parse time for 66k integers (estimated tens of ms; not measured).
