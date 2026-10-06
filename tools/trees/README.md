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
