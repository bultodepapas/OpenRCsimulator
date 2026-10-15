# Browser model assets

`assets/models/*.glb` contains one model-only export for each key and catalog ID in `assets/turntables.json`. The exporter calls the native builder at `res://render/airplane.gd`; it does not create substitute geometry. Each file keeps the visible builder hierarchy, node names, local transforms, meshes, and standard materials with embedded textures. It offsets the `airplane` root so the visible mesh bounds are centered at the origin. Lights, cameras, scenery, physics, and flight state are not included.

## Inventory

Bounds are the visible mesh dimensions in meters. `Mesh nodes` counts nodes that reference a mesh; `primitives` counts glTF mesh surfaces.

| Key | Catalog ID | Nodes / mesh nodes | Meshes / primitives | Materials | Textures / images | Bounds (m) | Bytes | SHA-256 |
| --- | --- | ---: | ---: | ---: | ---: | --- | ---: | --- |
| `stik` | `jensen-das-ugly-stik-60` | 109 / 77 | 77 / 120 | 29 | 4 / 3 | 1.522343 × 0.436287 × 1.325974 | 6,136,440 | `4ba7172eb3b2fa1c05007ac375251f2eca317b2a68018df23e9ae74c55c59aa2` |
| `extra` | `gp-extra-300s-60` | 50 / 32 | 32 / 32 | 15 | 0 / 0 | 1.623600 × 0.551921 × 1.386270 | 2,428,072 | `90bb3a0ab6ff99b7b4c05143fec41aaf1d5e3924d6d0843cbc6f5139b169e9d5` |
| `mustang` | `p51d-mustang-120` | 151 / 132 | 132 / 140 | 28 | 0 / 0 | 2.822548 × 0.950000 × 2.460789 | 5,659,836 | `4a678361f281035c4c123411271179bc5d9bb2df0855029aeafe8a354d17d32e` |
| `jet` | `sebart-avanti-s-a200-p100rx` | 70 / 38 | 38 / 105 | 26 | 20 / 20 | 1.996400 × 0.675602 × 2.261217 | 8,194,392 | `18aab4f8588e47c8348bc85fcabcbf9d8d0cf882fdb8f4f22c09e24fb925169f` |
| `timber` | `turbo-lumber-evolution` | 47 / 21 | 21 / 49 | 12 | 0 / 0 | 1.545504 × 0.434000 × 1.123326 | 1,921,560 | `063e8ec644b51ed76b1adb7c1079a10109f7f05077d63b906a67d05608ee33ac` |
| `heli` | `xcell-60-research` | 34 / 22 | 22 / 62 | 18 | 3 / 3 | 1.328287 × 0.362300 × 1.479871 | 4,215,664 | `61501ea8f1a47bf6701af255698539567af9082cb241cc77c7e032b14cbe1e8c` |

The assets total 28,555,964 bytes. The `jet` GLB is the largest at 8,194,392 bytes; the site can load only the selected model. Textured GLBs use lossy WebP at quality `0.90` and declare the required `EXT_texture_webp` extension. The [Three.js GLTFLoader extension list](https://threejs.org/docs/pages/GLTFLoader.html) includes `EXT_texture_webp`.

## Source identity

The export used Godot `4.7.2-stable.official.ed1daf0bf`. `GLTFDocument.append_from_scene()` exports the Godot node and descendants, and `write_to_filesystem()` writes the binary GLB selected by the file extension ([Godot GLTFDocument documentation](https://docs.godotengine.org/en/4.7/classes/class_gltfdocument.html)). The exporter records an `EXPORT_INPUTS_SHA256` over the ordered source paths in `export_web_models.gd` plus that script's bytes:

`97cccf885c02bb1d4d2d49012915da5041f854c49bc297049a091cb650cdd147`

For the five airplane catalog entries, the native builder validated these model manifest hashes before export:

| Key | Model manifest SHA-256 |
| --- | --- |
| `stik` | `d40127cb3b9ef8e7c6ccb25026eef675c38c2c508a11051b4b24d9d75c95c9b3` |
| `extra` | `c011f753e97d63edac36eba8db37996897a42ac5e9ab1c73e963fbe53963bfd7` |
| `mustang` | `b77b7bf1d8371a5d126ae3d32694b8b5ba27f3895b48ec96359bbfb1eeebdfe9` |
| `jet` | `e3a620364459dc4ce88e30f471d7cf572caadee5842fa86c3c8e04e2fe180177` |
| `timber` | `283b6179e0ec13aee17942042efe5474d9cbb3d1d2601c99b19139308bc19a9b` |

The helicopter uses the HX-700 visual adapter rather than the airplane model registry. Its source asset, `app/assets/aircraft/hx-700/hx-700.glb`, has SHA-256 `88424432c8cbfbc7c7278aa9c72e2188e138aa3551c2c1cf815494db281ce764`.

## Rebuild

Run from the repository root with the pinned Godot console executable. By default, the script overwrites the six named GLBs in `site/assets/models/`. Pass an absolute `--out-dir` after `--` to write elsewhere.

```powershell
$godot = Join-Path $PWD '.tools\Godot_v4.7.2-stable_win64_console.exe'
$script = (Resolve-Path 'site/export_web_models.gd').Path
& $godot --headless --path app --script $script
```

The script prints each output size and SHA-256, the source manifest identity, model bounds, visible node count, mesh node count, and a digest of sorted visible node names. It exits with an error if a catalog ID, builder result, source input, bounds, or GLB write is invalid.
