# TOD-09b static-cell diagnostic

2026-10-10 · Status: archived same-process discrepancy and renderer-context controls; independent-process acceptance is tracked in the parent report.

[TOD-09b report](../README.md) · [Time-of-day plan](../../../../TIME-OF-DAY-PLAN.md)

The Compatibility capture compares an in-place legacy field with a fresh `FieldBuilder` field at 960×540. The legacy call reports `field_changed=false`, yet the pair differs at `(121,311)`, `(121,312)` and `(576,312)` by at most 4 channel values. Two independently rebuilt fresh fields match exactly. The false pixel-match results and their PNGs are retained under [`runs/`](runs/).

Visibility controls isolate the rendered source to the merged opaque `cell_*` scenery meshes: hiding flowers and motion or hiding `shadows_*` preserves the three-pixel difference; hiding `cell_*` or all scenery makes the pair exact. The static-cell geometry comparison checks serialized surface arrays for all 48 matching meshes. It compares 12,488,904 bytes, reports no mismatches, and produces the same SHA-256 for each side (`6fb5d5dddc97084fbbbece7e3097d4152ead6fc3b0f220d8c78dd9a84f62383a`). See the [JSON result](runs/static-cell-hash/report.json) and [captured console output](runs/static-cell-hash/console.log).

| Control | Result |
| --- | --- |
| Fresh A versus fresh B | Exact match; see [report and captures](runs/fresh-pair-on/) |
| Hide `flowers_*` and `Motion` | 3 pixels remain; [report and captures](runs/hide-flowers-motion/) |
| Hide `shadows_*` | 3 pixels remain; [report and captures](runs/hide-shadow/) |
| Hide `cell_*` | Exact match; [report and captures](runs/hide-cell/) |
| Hide all scenery | Exact match; [report and captures](runs/hide-all-scenery/) |
| Lift every cell by 0.05 m | 3 pixels remain; [report and captures](runs/cell-lift-005/) |
| Lift every cell by 1 m | 2 pixels remain and move to a different image bound; [report and captures](runs/cell-lift-1m/) |

The cell arrays are identical, but their render result is not under this comparison. The visibility and lift controls do not identify whether depth ordering, a cell edge, or another renderer interaction is responsible. These initial controls did not close the exact scenery-on gate. The follow-up below isolates a renderer-context difference; the parent report records the independent-process gate. The legacy Apply pair is byte-identical with [scenery on](../apply-on/legacy-before.png) ([after](../apply-on/legacy-applied.png)) and [scenery off](../apply-off/legacy-before.png) ([after](../apply-off/legacy-applied.png)).

## Reproduction

The probes use the pinned Godot 4.7.2 binary, OpenGL Compatibility under Xvfb, and one llvmpipe thread. From the repository root, run the geometry and no-op legacy comparison with:

```sh
GODOT_BIN="$(app/get-godot.sh)"
OUT=/tmp/tod09b-static-cell-repro
mkdir -p "$OUT/static-cell-hash"
TOD09B_DIAG_ONLY=1 LP_NUM_THREADS=1 OPENRC_CODE_REVISION=diagnostic \
xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT_BIN" --path app \
  --rendering-driver opengl3 --audio-driver Dummy \
  --script "$PWD/docs/research/time-of-day-investigations/TOD-09b/static-cell-diagnostic/static_cell_probe.gd" -- \
  --scenery=on --probe-case=00-legacy --probe-out="$OUT/static-cell-hash"
```

For a visibility control, use a new output directory and add one of `--probe-hide-scenery=flowers-motion`, `--probe-hide-scenery=shadow`, `--probe-hide-scenery=cell`, or `--probe-hide-scenery=all`. The cell-lift control instead uses `--probe-cell-lift=0.05` or `--probe-cell-lift=1.0`.

The separate fresh-versus-fresh control uses [`fresh_pair_probe.gd`](fresh_pair_probe.gd). It runs the same single legacy case, writes both fresh captures and their comparison into the requested output directory, then completes the existing exploratory frame-cost samples.

```sh
mkdir -p "$OUT/fresh-pair-on"
LP_NUM_THREADS=1 OPENRC_CODE_REVISION=diagnostic \
xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT_BIN" --path app \
  --rendering-driver opengl3 --audio-driver Dummy \
  --script "$PWD/docs/research/time-of-day-investigations/TOD-09b/static-cell-diagnostic/fresh_pair_probe.gd" -- \
  --scenery=on --probe-case=00-legacy --probe-out="$OUT/fresh-pair-on"
```


## Follow-up: mesh allocation context

Three additional controls use [mesh_context_probe.gd](mesh_context_probe.gd), extending the archived diagnostic without changing runtime code. Set `TOD09B_MESH_CONTROL` to the control name in the table and use this script in the command above. Set `OPENRC_SCENERY_AUDIO=off`; the image assertion and production camera stay unchanged except in the explicit near-plane diagnostic.

| Control | Result |
| --- | --- |
| `share-mesh`: fresh nodes borrow original static cell Mesh resources | [Exact pixels](runs/share-mesh/report.json) |
| `share-material`: fresh cell meshes borrow only original materials | [Three differing pixels](runs/share-material/report.json) |
| `near-plane`: both captures use a 1 m near plane | [Exact pixels](runs/near-plane/report.json) |

The same CPU geometry can receive a different render order after allocation. The affected cell mesh local indices were `(47,48,49)` in the original scene and `(167,162,129)` in the later scene for `cell_6_-6`, `cell_6_-2`, `cell_6_1`; the order reverses. The pinned engine assigns the mesh local index to the geometry sort key and sorts opaque draws by that key after higher-priority fields. [Key assignment](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/drivers/gles3/rasterizer_scene_gles3.cpp#L331), [key layout and comparison](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/drivers/gles3/rasterizer_scene_gles3.h#L263), [download hashes](engine-source.json).

[Pixel-center ray intersections](cell-ray-hits.json) locate nearby surfaces in overlapping cell meshes at the differing pixels (about 244–286 m from the camera). They are geometric observations, not measurements of MSAA sample depth.

These controls support depth/order sensitivity between overlapping cell meshes as the cause of the same-process discrepancy. They do not measure the depth-buffer format or establish a universal precision formula. A separate-process startup fixture preserves the production camera (near 0.1 m, far 21,000 m), geometry and materials while giving both production paths equivalent initial resource allocation. No tolerance, pixel mask, changed near plane or borrowed mesh is used in that acceptance fixture.

The [verbose original exit log](runs/audio-exit-verbose.log) identifies the two leaked objects as `AudioStreamWAV` and `AudioStreamPlaybackWAV`. The three follow-up runs disable scenery audio and emit no ObjectDB warning. The new acceptance fixture also disables audio and drains frames after freeing Main; this isolates visual testing without claiming to validate production audio teardown.
