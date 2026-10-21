# L6b-R2: Tree bark mipmap evidence

This record evaluates native Godot 4.7.2 Compatibility mip filtering for the imported tree textures. The retained candidate enables mipmaps on the bark albedo and bark normal maps only. Both alpha-card leaf textures remain un-mipped. Source PNGs and tree meshes are unchanged; the frozen 19-entry vegetation catalog and texture import settings are retained, while source model binaries remain in the repository and are not duplicated here.

## Decision evidence

The paired sweep covers eight imported forms (seven trees and `bush_common_flowers`), three camera distances (16, 48 and 128 m), two output sizes (1280×720 and 1920×1080), and eight fixed subpixel phases. Each baseline/candidate project produced 384 raw frames, for 1,536 sweep PNGs in total. The renderer was native Compatibility (OpenGL), with 4× MSAA, fixed lighting, matched source geometry/materials, and wind disabled. See `captures/mip-sweeps/accepted-bark-only/comparison.json` and `captures/mip-sweeps/rejected-all-maps/comparison.json` for per-frame hashes and measurements.

The 384 PNGs under `captures/mip-sweeps/rejected-all-maps/baseline/` were pruned after matching all 384 files by name and SHA-256 to `captures/mip-sweeps/accepted-bark-only/baseline/`. The accepted-run baseline files remain the canonical copies. `manifest.json` keeps its original entries and hashes as a dated snapshot; the rejected-run baseline paths in it no longer resolve.

The bark-only candidate kept the binary silhouette mask exactly equal to baseline in all 48 asset/distance/size groups (mean mask IoU 1.0); the 96 `bush_common_flowers` baseline/candidate PNGs are byte-identical. Its two bark maps have 11 mip levels each; `Leaf_Pine_C.png` and `Leaves_NormalTree_C.png` have none. The four original source PNG hashes match across both projects.

The supersampled reference check is limited to `common_tree_3` and `bush_common_flowers` at 128 m and phase 0. It uses 4× and 2× baseline renders downsampled with BOX filtering as a finite raster reference, not analytic truth. Bark-only mips left mask coverage and outline error unchanged. `common_tree_3` RGB MAE over the union mask improved from 14.913 to 14.557 channel levels at 1280×720 and from 14.002 to 13.692 at 1920×1080. The shrub result is unchanged. This is modest evidence for bark texture filtering, not a claim of broad visual improvement or resolved temporal shimmer.

The all-four-texture mip trial is rejected. Filtering the alpha-card leaf maps increased coverage bias and RGB error against the same finite reference: for `common_tree_3`, coverage bias rose from 3.26% to 20.63% at 720p and from 1.28% to 14.08% at 1080p; for the flowering shrub it rose from 13.40% to 41.75% and from 3.91% to 25.78%. The reports also show reduced mask IoU throughout the 48 groups. The source materials use alpha scissor threshold 0.2, so ordinary leaf mip filtering fills gaps in these cards. Keep leaf maps un-mipped unless a separate alpha-aware filtering treatment is proven.

Decoded RGBA8 image data totals 54,525,952 bytes (52 MiB) without mipmaps and 65,710,760 bytes (62.667 MiB) with bark-only mips, an increase of 11,184,808 bytes (10.667 MiB). These are decoded image-data totals, not GPU residency or total runtime memory. The rejected all-map trial totals 72,701,264 bytes (69.333 MiB).

## Integration checks and limits

The production inventory retained here reports 4,958 proxies, 80,177 source tree triangles, and world identity `5dd45231f977010fc272bb1c34dd82210c92fbdde68a7d5dba4e7c868f62b3ca`; this is the unchanged production-world baseline identity, not a flight result. Focused headless logs cover imported tree rendering, imported vegetation, tree bounds, landscape vegetation, and collision proxies. The native bark candidate passed import/PCK texture-payload parity (`source_and_pack_identical: true`) and an 11-capture gallery with wind off and on, covering three source trees under Compatibility at 1280×720 and 4× MSAA. The PCK itself is excluded; its recorded SHA-256 is `4fce07c330d87094d8e95a2687427eb1d68b021a6c8f6af7ac3d7ef1458644ac` (167,136,448 bytes).

The paired captures identify the same project, catalog, imported vegetation script and wind shader in both mip configurations. Their hashes are recorded in the comparison reports. The native inventory also records the frozen 19-entry catalog SHA-256 `65dda4519ced099e043262c4ee5a821210d6bc86665cdcfb3a622247617dd7f9`. The source-tree import configs are retained under `source/import-configs/`; `source/quaternius-standard/` contains only the frozen catalog and license, not duplicate models or textures.

Subsequent bark-only field captures and the five-pair bark-plus-oak static scene profile are retained with the [mature oak continuation](../L6a-R1/mature-oak/README.md#static-profile-and-lifecycle). Flight validation, owning-track review, and full release remain pending. The earlier strict-suite AUD-12 result is linked in [L6a-R1](../L6a-R1/README.md); this evidence does not claim a new full-suite pass.

## Reproduction

Use frozen baseline and candidate application snapshots matching the report identities, with the import configs in `source/import-configs/`. The snapshots, `.godot` caches, and PCK are intentionally excluded from this evidence package. Run from the repository root with a native Godot 4.7.2 executable and Python dependencies `numpy` and `Pillow`:

```powershell
python docs/research/visual-quality-implementation/L6b-R2/fixtures/all-maps/mip_compare.py `
  --godot .tools/Godot_v4.7.2-stable_win64.exe `
  --baseline <baseline-app> --candidate <all-maps-candidate-app> --out <new-output-dir>

python docs/research/visual-quality-implementation/L6b-R2/fixtures/bark-only/mip_compare.py `
  --godot .tools/Godot_v4.7.2-stable_win64.exe `
  --baseline <baseline-app> --candidate <bark-only-candidate-app> `
  --mip-scope bark --out <new-output-dir>
```

Each output directory must be new or empty. The retained all-map fixture is the version from Git object `422641c9`; the bark-only fixture is the final scoped variant used for the accepted run. The supersampled capture/analyzer scripts and their four reference PNGs are in `fixtures/supersampled-reference/` and `captures/supersampled-reference/`. Raw sweep frames, reports, native gallery captures, logs, import configs, catalog/license snapshot, production inventory and fixture sources are listed with SHA-256 hashes in `manifest.json`.

Related records: [tree/forest plan](../../../plans/tree-forest-quality.md), [dated research](../../../research/tree-forest-quality-2026-10-17.md), and [prior imported-tree delivery](../L6a-R1/README.md).
