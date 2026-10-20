# LU-28 — agricultural plain and connected rural scenery

2026-10-20. Windows, Godot 4.7.2, Compatibility/OpenGL, NVIDIA RTX 3090,
1280×720. This delivery follows the owner's request to focus on the plain,
roads, cultivated fields, farms and houses.

## Implemented

The Club plain now has 50 parcels, including green crops, wheat-colored fields,
tilled soil and a small shrub crop bed. Rows, paired tractor tramlines, darker
field margins, varied parcel widths and slight shears provide scale cues.
A 28 m divided highway has a grass median, shoulders and filtered lane markings.
A 6.5 m rural road connects the eight-house hamlet, club access and western
village; gravel branches reach both farmyards. All eight houses have connected
driveways and small yards.

The existing NNE farm gains a fenced yard and road access. A second farm reuses
the existing barn, farmhouse, silo, tractor and three round bales. Twelve
downloaded shrubs form compact crop rows; four downloaded cattle occupy a
separate wire paddock. Eight fence groups leave both farm entrances open.
No new building or vegetation model was authored.

The layout is art-directed, in estimated metres, rather than a surveyed map.
Roads/crops are visual surfaces; they add no terrain height or tire-friction
model and no traffic simulation. Existing scenery collision machinery supplies
the added object proxies. No flight solver, aircraft data or golden flight changed.

## Rendering and constraints

`tools/scenery/bake_countryside.py` writes deterministic static geometry from the
retained field, scenery and visual-horizon data. The bake records their SHA-256
identities. Geometry follows the visual horizon at sampled vertices and keeps
the central 400 m radius clear. Runtime uses 6,380 triangles in 24 spatial cells, one shared
scene-local material, no surface shadow draws and no surface frame callbacks.

Only one photograph is added: the unchanged 1K CC0 asphalt diffuse from Poly
Haven (635,143 bytes). Grass and dirt reuse existing photos. Texture mipmaps and
analytic pixel-coverage filtering reduce distant row/line aliasing. Crop detail
uses two photo samples; roads use one, or two for the divided highway median.

Small fixed height lifts alone produced visible z-fighting from the 680 m
overview. A bounded view-depth offset now separates the visual layers while
preserving their perspective screen coverage: `min(6 m, z² × 0.0000015)`, with
1.15 priority for roads/yards. At 100 m view depth this is about 1.5 cm; near
farm and aerial captures check the result. This is a rendering offset, not a
physical surface displacement.

Unbounded corner smoothing disconnected the first house access and crossed
trees. Bounded quadratic corner cuts, projection of driveway endpoints onto
the actual road path, and explicit gate crossings fix those failures.
The offline regression checks every route against retained tree trunks, all
access connections, both farm gates, crop shear, clockwise triangles, source
identities and geometry budgets.

The first 12-tree crop proposal exceeded the unchanged 650,000 scenery
triangle ceiling (691,496). Reusing the retained low shrub source preserves
the agricultural detail without that tree cost. The final scenery count is
642,884, leaving 7,116 below that ceiling; the separate surface meshes add
6,380 triangles. Shrub placement and collision dimensions use the same source bounds.

## Primary-source research

- [Poly Haven: Aerial Asphalt 01](https://polyhaven.com/a/aerial_asphalt_01),
  Rob Tuytel: the asset describes a 30 m footprint. The 1K diffuse is sufficient
  for restrained surface variation here; road paint is generated in metre
  coordinates. [CC0 terms](https://polyhaven.com/license), exact download/hash
  in [the bundled asset record](../../../../app/assets/landscape/countryside/source.json).
- [Godot: optimizing 3D performance](https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html)
  and [MultiMesh](https://docs.godotengine.org/en/stable/classes/class_multimesh.html):
  batching reduces submission overhead, but a large batch has shared visibility
  bounds. The implementation therefore uses compact static surface cells and
  reuses the existing scenery batches.
- [Nathan Reed / NVIDIA: Visualizing Depth Precision](https://developer.nvidia.com/blog/visualizing-depth-precision/)
  explains reciprocal view-depth precision and near-plane sensitivity. This
  informed the distance-dependent offset experiment; the actual coefficient
  was qualified with native captures, not claimed as a universally safe value.

## Reproduce

Run in repository order:

```text
python tools/scenery/place.py --check
python tools/scenery/bake_countryside.py --check
python tools/scenery/test_countryside.py
godot --headless --path app --script res://tests/test_countryside.gd
```

Use the checked runner in `tools/godot/run_checked.py` for native verification:

```text
godot --path app --audio-driver Dummy --resolution 1280x720 \
  --script res://tests/capture_landscape_upgrade.gd -- \
  --out=<absolute-output> \
  --cases=plain_overview,plain_east,plain_farm,plain_farm_gate,plain_village,plain_highway,plain_crop,pilot_north \
  --frames=360
```

For the reference, add `--scenery_file=<absolute-path-to-reference-scenery.json>`.
That retained fixture excludes only the new `countryside-*` groups, so the
adapter also omits the corresponding surfaces. It preserves the mountains and
the existing club/woodland. Normal launches enable the addition for Club;
scenery-off, the landscape comparison switch and ineligible custom fields
omit it. Green paradise remains separate.
