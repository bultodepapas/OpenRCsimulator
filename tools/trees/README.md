# L6a tree authoring pipeline

The three Quaternius sources are **offline authoring geometry**. `app/` ships only the 1024² albedo atlas, JSON catalog and license. A runtime tree is three crossed quads (six triangles, one lit alpha-scissor surface). This step does not place trees in the field; L6b owns distribution and L6c owns flight readability. The source GLBs are not approved as L8 close-range LODs.

```sh
npm ci --prefix tools/trees
PYTHONDONTWRITEBYTECODE=1 "$(app/tests/visual-env.sh)" -m unittest discover -s tools/trees -p 'test_*.py'
PYTHONDONTWRITEBYTECODE=1 "$(app/tests/visual-env.sh)" tools/trees/build.py --out /tmp/tree-bake-A
PYTHONDONTWRITEBYTECODE=1 "$(app/tests/visual-env.sh)" tools/trees/build.py --out /tmp/tree-bake-B
```

Requires pinned Godot 4.7.2 (`app/get-godot.sh`), Node 24, Xvfb and the existing pinned visual Python environment. `--out` must be new/empty. The pipeline verifies source hashes, validates glTF/GLB, normalizes tree height to 1 m, decodes both GLBs with GLTFDocument in an isolated project, renders source/derived comparisons, assembles the atlas, repairs alpha borders and inspects all mip levels. Subprocesses have timeouts and engine-error gates. Nothing writes back to `app/` automatically.

Normalization preserves topology, UVs, normals, textures and alpha cutoff. The upstream glTF has COLOR_0 components up to 1.00016785; the adapter permits only that reviewed small excursion (<=1.0002) and clamps it to 1. Any other source validation error is refused. The remaining Khronos warning is generated tangent space on the normal-mapped bark; Godot's importer ensures tangents. This is irrelevant to the unshaded albedo bake, and retained in the lit diagnostic.

Source and derived decoders explicitly use lossless images, generated mipmaps, full geometry and uncompressed mesh attributes. An editor-import prototype gave external and embedded textures different mip defaults, and fresh imports changed pine pixels. The final offline loader uses `GLTFDocument` with embedded uncompressed images and explicit image mip generation, avoiding editor extraction/cache jobs. The runtime atlas still goes through the normal editor importer and clean-export tests. The bake is unshaded: it does not bake the diagnostic sun into the atlas. Original authored texture/vertex coloration is retained. The atlas has no baked geometric normals: close views of its crowns will look flatter than the source mesh.

Each 1024² binary-alpha raw image is resolved to a 512² tile with alpha-weighted RGB and coverage alpha. Margins must be >=16 px. Acceptance is silhouette IoU >=0.995, RGB MAE <=0.05/255 and <=0.1% common opaque pixels differing by >2 channel levels. High per-pixel errors at rare leaf occlusion boundaries are reported, not hidden; float32 normalization changes a few raster edge samples. A source or palette change still needs human review. Runtime import is lossless, straight alpha, fix-alpha-border and mipmaps, with 3D auto-compression disabled.

After inspecting source/derived, mips and repeat hashes, copy only `atlas/atlas.png` and `atlas/catalog.json` into `app/assets/landscape/trees/`; retain the exact source license. Refresh `assets/landscape/PROVENANCE.json` and proof reports. Do not overwrite imported assets during a running editor/test.

```sh
app/test.sh
mkdir -p /tmp/tree-card-review
LP_NUM_THREADS=1 xvfb-run -a "$(app/get-godot.sh)" --path app \
  --rendering-driver opengl3 --audio-driver Dummy --script "$PWD/tools/trees/inspect_cards.gd" \
  -- --out=/tmp/tree-card-review
```

The fixture shows the actual runtime factory at four rotations. A caller in L6b should build one mesh per species and reuse it in sector MultiMeshes; disable card shadow casting. The transparent card frame extends below zero, while the **visible trunk** is at zero; its center is `pivot_y_m`, not half the padded image height. The test checks the lowest visible texel rather than only the quad bounds.

Run `app/export.sh` in a fresh clone to verify every pack without loose-file fallback. `check_field_pack.gd` loads the catalog, license and imported atlas through the adapter in all three packs. No GLB, source texture, npm package or runtime generator belongs in the exported tree family. llvmpipe images do not establish RTX 3090 frame times.

## L6b/L7 placement and rendering

`python3 tools/trees/place.py` regenerates only `objects` in the default field. `--check` verifies the committed data without writing it. Positions are pilot-relative NED offsets on a 0.25 m grid, marked as derived estimates rather than surveyed geography. The L6b recipe remains frozen at 480 near trees, seed `610602`, radius 270–570 m; its position digest is `9b42b61ff36e5df25ef0245702e4d75965ea805f81de56a1c353fd1f0c722875`.

L7 adds 1,200 far trees from seed `610607`: twelve 100-tree clusters with 55 m patch radii, tree centers in the 600–1,500 m ring, 4.5 m minimum within-patch spacing and the same two crown-cleared gaps and runway/mown corridor. They share the existing eight azimuth-sector MultiMeshes, so the model keeps six triangles per tree and adds no draw calls. The field loader caps the combined set at 1,680 positions and 1,500 m.

The CPU and shader keep the original +2400 identity hash coordinates for every L6b position. They use +8192 only when a south/west coordinate falls below that original unsigned range. Packed transforms use four exact bytes with +8192, which covers the full L7 radius through Compatibility's float16 instance-data path. Near instances form a prefix in each sector; `near_instance_count` and `far_instance_count` metadata let captures show only the near ring through `MultiMesh.visible_instance_count`.

The tree shader scales alpha gently from the screen-space mip footprint for far instances only. This compensates for the atlas's averaged alpha mips in the Compatibility renderer, where alpha-to-coverage is unavailable. Near trees keep the L6b alpha path unchanged.

Run the recipe regression with `python3 tools/trees/test_place.py` and the app's generated-data check with `python3 tools/trees/place.py --check`. `python3 tools/trees/check_review.py --app app --godot "$(app/get-godot.sh)" --out /tmp/l7-forest-review` uses Xvfb/OpenGL to measure draws and verify all 1,680 shader identities through the real MultiMesh custom-data path, then repeats thirteen PNGs byte-for-byte. It also runs `tests/test_treeline.gd` with the real renderer; the headless dummy renderer cannot prove GPU buffer readback. `app/capture.sh` runs the review as part of its visual checks.

## L15b tree wind

The render-only tree response is ready for M5's shared `wind_vec`; production remains calm. Run the focused GPU evidence with:

```sh
"$(app/tests/visual-env.sh)" tools/trees/check_wind.py \
  --app app --godot "$(app/get-godot.sh)" --out /tmp/l15b-wind \
  --baseline-app /path/to/pre-L15b/app
```

Use a fresh output directory. The baseline is optional for later regression runs; initial acceptance includes baseline parity. The complete capture wrapper also runs this check. See [L15b evidence](../../docs/research/visual-quality-implementation/L15b/README.md) for the card-specific root rotation, parameter estimates, culling proof and limits.
