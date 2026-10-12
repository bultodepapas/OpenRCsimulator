# TT-03 — the r1 GLB in the app and the isolated viewer

2026-10-12 · **Status: complete; owner review of the captures pending.** Owning plan: [Timber integration](../../../TIMBER-INTEGRATION-PLAN.md). Guide: [asset README](../../../../assets/aircraft/turbo-timber-evolution/README.md). Captures: [captures/](captures/) with `manifest.json` (camera records and PNG hashes of all 12 views; six PNGs kept here).

## Asset and import

`app/assets/aircraft/turbo-timber-evolution/timber.glb` is the r1 `export/aircraft.glb` byte for byte (SHA-256 `fb7586f190…`, checked by `research/timber/tt03/check_asset.py --check` against TT-01's manifest, together with the copied `LICENSE.txt`, the committed `timber.glb.import` sidecar and the revision strings of the generated artifacts). The sidecar keeps Godot 4.7.2's default scene-import settings (LODs, shadow meshes and compressed vertex attributes on). The importer produces a `PackedScene` whose root (`timber`, identity) has one child `TurboTimberEvolution` with 15 `MeshInstance3D`, 36 surfaces, 64,291 triangles, 10 `StandardMaterial3D` resources (one alpha-blend glass, two emissive lenses), no animation, camera or light.

Fresh-clone import: in two disposable copies of `app/` without `.godot/`, `--import` exited 0 both with and without the Timber asset, and a second run exited 0 (this checkout's first import after copying the file aborted at editor-layout teardown after a complete import; it did not recur). `app/test.sh` runs the import first, so a clean CI checkout regenerates `.godot/imported/`.

Vertex precision: on this import `Mesh.get_faces()` returns positions that differ from `surface_get_arrays()` by up to 28 µm (spinner tip −0.283489 vs −0.283461 m; airframe cowl 25 µm), with or without `meshes/force_disable_compression`. Shadow, night kit and crash consumers that read faces are unaffected at that scale; the measurement script and the verifier read the arrays.

## Checks

```bash
bash app/test.sh   # section "Turbo Timber Evolution asset identity and generated geometry" and "model contract"
"$(app/get-godot.sh)" --headless --path app --script res://aircraft/verify_timber.gd
# timber preview r1-fb7586f19029: 15 meshes, 36 surfaces, 64291 triangles, extent 1.5479 x 0.4340 x 1.1166 m
# PASS 283 checks
```

`verify_timber.gd` proves (TT-03 part): the on-disk GLB hash equals the geometry inputs and the root metadata; root `airplane` with the aircraft node at the datum; 15/36/64,291 counts, every mesh identity under its pivot, no animation/camera/light; all 13 pivots found with the parents, rest bases (within 1e-5) and rest translations of the constants, world pivots/axes within 1e-6, and the imported glTF `extras` (id, positive sense, range) equal to the constants; landmarks within 0.5 mm of both the measurement and the author; span within 1 % of the manual (and equal to the measurement), length and height equal to the measurement, forward extent = spinner tip; ten shared material resources with one transparent and two emissive; a deterministic double build (identical node paths, classes, transforms and surface counts), independent instances sharing meshes and materials. The TT-05 part (signs, propeller, gear) is listed in [TT-05](../TT-05/README.md).

## Captures (Compatibility renderer, llvmpipe under Xvfb)

```bash
xvfb-run -a "$(app/get-godot.sh)" --path app --rendering-driver opengl3 --script res://aircraft/inspect_timber.gd -- --output-dir=/tmp/timber-views   # 12 views in 4 s
```

| View | What to look at |
| --- | --- |
| `inspection_front.png`, `inspection_side_left.png`, `inspection_top.png` | Orthographic, 1.2 spans tall: silhouette for the owner's overlay on the manual three-view |
| `inspection_oblique_front_left.png` | Materials: red/white/black livery, glazing, foam tyres, metal, emissive nav lenses |
| `inspection_oblique_rear_right_full.png` | Controls at the manual high rates and flaps at 35 mm: right aileron up, left down, elevator up, rudder right |
| `inspection_gear_front.png` | Legs, axle bolts, cosmetic cables/springs, tailwheel wire |

Review notes from the capture set (software review, not the owner's): the livery, glazing (alpha 0.45) and emissive lenses render under Compatibility without visible z-fighting at these distances; decals sit 1–2.5 mm proud of the skin as documented by the author; the gear cables are static. TT-04 measures the frame cost and inspects decals at the pilot-view distances.

## Limits

Verification establishes that the app shows the frozen asset with the documented structure; it does not validate the aircraft's shape against the real airframe (owner overlay, TT-02) and does not measure rendering cost (TT-04). The catalog entry, `render/airplane.gd` dispatch and the test sweep are TT-06.
