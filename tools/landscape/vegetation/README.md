# Downloaded vegetation asset pipeline

`build_library.py` extracts a pinned selection of source geometry without creating or editing any plant geometry. It retains the source archives and license evidence under `assets/landscape/vegetation/source/`, copies exact glTF or OBJ/MTL members into the library output, and writes `catalog.json` with source hashes, source and grounded bounds, surface counts and triangle counts. The default output remains `app/assets/landscape/vegetation/` and keeps the existing 15-asset selection.

The runtime library contains 3 trees, 2 shrubs, 4 grass/herb assets, 3 flowering assets, 2 crops and 1 reed clump. Quaternius's Stylized Nature MegaKit Standard supplies the trees, shrubs, grass, herbs and flowers under CC0-1.0. A second Quaternius CC0 pack supplies mature corn and wheat; Aredon's CC0 low-poly reed supplies the reed clump. Source pages, archive hashes and license evidence are recorded in the catalog and source notices.

```powershell
python tools/landscape/vegetation/build_library.py
python tools/landscape/vegetation/build_library.py --check
python tools/landscape/vegetation/build_library.py --output-root tmp/tree-retained-intake --include-reviewed-tree-variants
python tools/landscape/vegetation/build_library.py --output-root tmp/tree-retained-intake --include-reviewed-tree-variants --check
python tools/landscape/vegetation/test_build_library.py
```

`--output-root` stages the library files and catalog at a chosen directory; paths relative to the repository root are supported. Staged catalogs retain the eventual runtime `res://assets/landscape/vegetation/...` paths and reference the pinned source notices under `assets/landscape/vegetation/source/`. Staging does not write to `app/` or rewrite those source notices. The staged directory is an intake package, not a runnable Godot project.

`--include-reviewed-tree-variants` explicitly adds the four retained Quaternius Standard sources below. Without this flag, generated output and catalog asset selection stay at the existing 15 assets. The candidate command above writes only under ignored `tmp/`; it does not integrate the added sources into the runtime library.

| Source | Source triangles | Surfaces | Source bounds size (X × Y × Z, m) | glTF SHA-256 |
| --- | ---: | ---: | --- | --- |
| `CommonTree_2` | 5,648 | 2 | 4.464302 × 7.642996 × 4.275852 | `67160975f0ac991b4a2ffb2add4ab4037b5e9c1bef9f66dac5235fcf0ba9bd52` |
| `CommonTree_4` | 4,066 | 2 | 3.825526 × 9.438381 × 3.755373 | `ddf0e8837705702871d3f03de8cf7aeed61ad4bf8ee92052b6f95bdd771297b6` |
| `Pine_2` | 3,648 | 2 | 5.728085 × 7.376238 × 5.221207 | `57bd4732170b6c7e51bcf78fe5adaabf142f95a50378d8d3051d1f20a04d3c2f` |
| `Pine_3` | 4,964 | 2 | 3.611395 × 7.392199 × 3.995804 | `54c72a4d614f053dd4b3d4404076a361de6085ec6a34560e42a76d7e79d89830` |

Counts and bounds come from the pinned archive's glTF accessors. `catalog.json` records full hashes for each copied dependency, source-entry names, source bounds and grounded bounds. These are source geometry counts; Godot-imported LOD and shadow costs remain to be measured separately.

Godot 4.7.2 imports the preserved glTF sources directly and generates mesh LODs and shadow meshes. Crop and reed OBJ/MTL files are also preserved directly and use Godot's OBJ importer; their source geometry does not receive generated LODs.

`ImportedVegetation.get_parts(id)` exposes shared source meshes, effective source materials, part transforms and bounds. Call `queue(batches, id, placement, seed, damage_id)` and `build(batches)` to produce one `MultiMeshInstance3D` per imported source part. The default build keeps the original materials; pass `true` as the second `build` argument to opt into the private wind shader after visual validation. `set_wind()` adjusts only wind-enabled builds. `set_damage_hidden()` hides and restores all batched parts for a damage ID, and `bounds()` reports the live aggregate bounds without per-plant nodes.
