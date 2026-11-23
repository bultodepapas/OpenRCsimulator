# LU-34 source geometry, November 23, 2026

The High-quality Club field falls within all eight original LU-34 allowances. The changed geometry removes 5,431 source triangles from the production field. Its two affected categories have 238 and 82 triangles of headroom. Counts use the production test rule, including full detail for every MultiMesh instance.

| Subsystem | Historical passing scene | Before repair | After repair | Allowance |
| --- | ---: | ---: | ---: | ---: |
| Merged cells and farm tractor | 171,785 | 178,746 | 174,762 | 175,000 |
| Miscellaneous scenery | 7,268 | 9,365 | 7,918 | 8,000 |
| Imported close vegetation | 132,457 | 149,260 | 149,260 | 150,000 |
| Total across all eight | 1,033,047 | 1,058,908 | 1,053,477 | Per subsystem |

The earlier scene was reconstructed from the scenery inputs at `85a2475f` and reproduces its hosted total. Upstream `843f357c` added 6,961 merged-cell triangles. Per-object damage ranges account for 5,411 of them after savings on existing fences, and the rest comes from untagged cell geometry. The new lane-side wire consumed 4,337 triangles, the two hay wires 4,538, the grazing rails 2,908 and the entrance gate 1,442. In miscellaneous scenery, 1,023 new planted hedge quads added 2,046 triangles and two shadow batches added 51. The woodland edges stayed at 2,656 throughout. [All node and group deltas, counts and source identities](receipt.json)

## Hedge atlas

All 1,447 hedge placements retain their source UV-to-position map, four-view atlas, shader and instance transforms. One triangle encloses the complete bilinear footprint of every nontransparent texel in every frame. Each frame has a transparent outer border, so camera-facing geometry extending past the unit square samples transparent pixels. The fitted triangle occupies 83.50% of the previous square's area in its own plane. Its three vertices replace four vertices and six indices in the shared source card. Each MultiMesh receives a conservative bound over the actual placement centers and uniform scales, including camera-facing rotation and planted-hedge tilt.

The production regression checks the imported texture, mesh and material. Moving the left UV endpoint inward from −0.203125 to +0.2 fails the pixel-support assertion. Woodland shrubs and grass still use their own quad meshes. Regenerating their placement file changes the source-hedge SHA-256 leaf alone. The generator passed its deterministic check and all six woodland Python cases. [Renderer and asset checks](../../../app/tests/test_imported_hedge.gd) · [Woodland generator](../../../tools/trees/place_woodland_edges.py)

## Sampled timber

A 1.8 m picnic or bench plank has four 3 mm corner chamfers. Each long, straight chamfer now receives one wood-grain sample interval for every two used on the broad faces. End bevels, caps, bolts, corners, plank silhouettes, broad-face colors and orientations retain their source geometry or attributes. World cells contain four picnic tables and five benches, including the bench built into the pavilion. They save 3,984 triangles and 11,952 unindexed vertices. The other callers of the timber board routine, including shed cladding, retain their original sampling.

| Complete prefab | Triangles before → after | Surface with changed grain interpolation | Largest absolute RGB difference, 0–255 | Whole-surface RGB RMS, 0–255 |
| --- | ---: | ---: | --- | --- |
| Picnic table | 3,804 → 3,228 | 0.2740 m², 3.24% | 30.0 / 24.0 / 18.0 | 0.784 / 0.639 / 0.468 |
| Bench | 2,452 → 2,116 | 0.1827 m², 4.15% | 33.5 / 27.5 / 19.5 | 0.999 / 0.808 / 0.590 |

The comparison uses the color values read back from the uploaded ArrayMesh. It intersects old and new triangles in local plank coordinates, evaluates extrema at every intersection vertex, and integrates the squared piecewise-linear color differences over true surface area. It independently verifies the full multiset of untouched position, normal and color tuples for both prefabs. Normals on the coalesced faces differ by at most 0.000005 degrees. These figures measure vertex albedo before lighting. [Independent comparison](compare_timber.py)

## Runtime checks

The pinned Linux editor passed the production scenery, vegetation and farm-tractor suites, all 90 furniture checks, all 40 hedge checks, all 54 woodland habitat checks, 117 scenery destruction checks and eight production destruction/reset checks. The runtime destruction test used the GDScript reference fallback and emitted its expected missing-native-library warning. Geometry retessellation can shift the pivots of decorative debris, which are computed from each fragment's vertex population. The standalone tables and benches retain their gameplay damage IDs. The pavilion retains its masonry impact behavior.

The source inventory covers all 6,015 tracked app files at the qualified snapshot. The 29 files whose Git attributes specify CRLF match the exact filtered checkout bytes. A further 5,980 match the unfiltered Git blobs and the six local changes match the measured working files. The earlier interrupted profiler produced no counts. Two preliminary tractor runs failed because the fixture lacked external scripts. The credited tractor run includes the matching baker and attribution code.

The 49-check Club airspace report matched the previously qualified report byte for byte. The field retains 7,295 collision proxies, the Linux world identity and the portable geometry fingerprint. The nine portable fingerprint checks passed. These checked editor runs use the Dummy renderer. Camera-visible crops, rendered furniture appearance and target-hardware frame timing require their own evidence. [Retained airspace driver and prior result](../../research/visual-quality-implementation/L6c/tree-completion/woodland-edges/2026-11-22-ci-audit/README.md) · [Checked-run details](receipt.json)

## Reproduction

Use two complete, imported checkouts with the pinned engine. Choose the audit reference `8ce11eb2` for the before checkout and the geometry repair for the after checkout. Run each source version with the same [measurement driver](dump_geometry.gd). The output directories must exist. One invocation from each checkout follows, with absolute paths supplied for the driver and output directory.

```sh
python3 tools/godot/run_checked.py --out-dir "$CHECKS" --label geometry \
  --timeout 150 --require-text 'Geometry evidence written' -- \
  "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy \
  --script "$DRIVER" -- "$OUTPUT"
```

Each run writes the field's subsystem, node and damage-range totals plus eight little-endian float32 buffers for the two complete furniture meshes. Use Python with NumPy to compare the outputs. [Buffer hashes and expected results](receipt.json)

```sh
python3 docs/audits/geometry-budget-2026-11-23/compare_timber.py "$BEFORE_OUTPUT" "$AFTER_OUTPUT"
```
