# Downloaded vegetation asset pipeline

`build_library.py` extracts a pinned selection of source geometry without creating or editing plant geometry. It retains the source archives and license evidence under `assets/landscape/vegetation/source/`, preserves the original glTF JSON and all image/OBJ/MTL dependencies, and writes `catalog.json` with source hashes, source and grounded bounds, surface counts and triangle counts. The default output is `app/assets/landscape/vegetation/` and contains 20 assets, including eight reviewed tree forms.

The runtime library contains 8 trees, 2 shrubs, 4 grass/herb assets, 3 flowering assets, 2 crops and 1 reed clump. Quaternius's Stylized Nature MegaKit Standard supplies seven trees, shrubs, grass, herbs and flowers under CC0-1.0. The separately licensed OpenGameArt oak is described below. A second Quaternius CC0 pack supplies mature corn and wheat; Aredon's CC0 low-poly reed supplies the reed clump. Source pages, archive hashes and license evidence are recorded in the catalog and source notices.

```powershell
python tools/landscape/vegetation/build_library.py
python tools/landscape/vegetation/build_library.py --check
python tools/landscape/vegetation/build_library.py --output-root tmp/tree-retained-intake
python tools/landscape/vegetation/build_library.py --output-root tmp/tree-retained-intake --check
python tools/landscape/vegetation/test_build_library.py
```

`--output-root` stages the library files and catalog at a chosen directory; paths relative to the repository root are supported. Staged catalogs retain the eventual runtime `res://assets/landscape/vegetation/...` paths and reference the pinned source notices under `assets/landscape/vegetation/source/`. Staging does not write to `app/` or rewrite those source notices. The staged directory is an intake package, not a runnable Godot project.

Git attributes disable newline conversion for hash-bound model files and source licenses. This preserves upstream glTF/OBJ/MTL bytes on Windows and Linux; whitespace-only differences in historical checkouts are not material or geometry edits. Run `--check` from a fresh checkout as well as the source workspace.

The four retained Quaternius Standard sources below are part of the default library. Their source geometry, topology, indices, normals, UVs, glTF JSON, textures and original archives remain unchanged. The tree role derives each runtime external `.bin` buffer with one narrowly scoped repair: finite float `COLOR_0` components above 1 and at or below 1.0002 are clamped to 1. This matches the reviewed tolerance already used by the offline tree atlas adapter ([pipeline notes](../../trees/README.md)). The builder rejects negative, non-finite, over-limit, normalized, sparse or unsupported color accessors, and rejects any proposed patch overlapping another accessor's storage. Each tree catalog row records the exact method, number of clamped components, source buffer SHA-256 and derived runtime buffer SHA-256. Tests verify all seven accessors are in range, only those color values change, every non-color accessor and every byte outside the changed float values remains identical, and source archives stay untouched. The table records source-space geometry facts from the pinned archive, not Godot-imported LOD or shadow costs.

| Source | Source triangles | Surfaces | Source bounds size (X × Y × Z, m) | glTF SHA-256 |
| --- | ---: | ---: | --- | --- |
| `CommonTree_2` | 5,648 | 2 | 4.464302 × 7.642996 × 4.275852 | `67160975f0ac991b4a2ffb2add4ab4037b5e9c1bef9f66dac5235fcf0ba9bd52` |
| `CommonTree_4` | 4,066 | 2 | 3.825526 × 9.438381 × 3.755373 | `ddf0e8837705702871d3f03de8cf7aeed61ad4bf8ee92052b6f95bdd771297b6` |
| `Pine_2` | 3,648 | 2 | 5.728085 × 7.376238 × 5.221207 | `57bd4732170b6c7e51bcf78fe5adaabf142f95a50378d8d3051d1f20a04d3c2f` |
| `Pine_3` | 4,964 | 2 | 3.611395 × 7.392199 × 3.995804 | `54c72a4d614f053dd4b3d4404076a361de6085ec6a34560e42a76d7e79d89830` |

Counts and bounds come from the pinned archive's glTF accessors. `catalog.json` records full hashes for each copied dependency, source-entry names, source bounds and grounded bounds. These are source geometry counts; Godot-imported LOD and shadow costs remain to be measured separately.

Godot 4.7.2 imports the preserved glTF sources directly and generates mesh LODs and shadow meshes. Crop and reed OBJ/MTL files are also preserved directly and use Godot's OBJ importer; their source geometry does not receive generated LODs.

`ImportedVegetation.get_parts(id)` exposes shared source meshes, effective source materials, part transforms and bounds. Call `queue(batches, id, placement, seed, damage_id)` and `build(batches)` to produce one `MultiMeshInstance3D` per imported source part. The library default keeps source materials. `build(batches, false, {tree_wind = true, tree_cell_size_m = 0})` enables the qualified tree-only shader. The legacy second `true` argument retains its all-role behavior for existing callers.

Production scenery keeps seven mature alias slots, with the first slot selecting the downloaded oak; the two sapling aliases retain their previous sources. This yields eight source forms across the same 17 placements. The seven Quaternius sources support imported-tree wind; the oak retains its static BLEND material. `--tree_wind=off` / `OPENRC_TREE_WIND=off` restores static imported trees; it does not disable the separate field-card wind. The shader preserves the reviewed albedo/normal maps, UV transforms, vertex colors, scalar PBR values and alpha scissor. It follows `sim_clock` and `wind_vec`, fixes the root and updates the normal/tangent frame. Unsupported material features, tilted/nonuniform transforms or separate stem/crown meshes retain source materials. Source textures and other plant roles are not rewritten by this option.

Tree spatial cells are optional: `--tree_cell_size_m=64`, `128` or `256` (or `OPENRC_TREE_CELL_SIZE_M`); `0` retains source-part batching. Instance transforms, colors, phases and damage IDs survive regrouping. No density increase is enabled. `set_wind()` adjusts only wind-enabled builds with per-build materials. `set_damage_hidden()` hides/restores all parts for a damage ID, and `bounds()` reports the live aggregate bounds; tree wind also expands render-culling bounds. See the [native comparison and remaining gates](../../../docs/research/visual-quality-implementation/L6a-R1/README.md).

## Mature oak intake (L6a-R1)

`oak_tree` reuses [lauris71's Oak Tree](https://opengameart.org/content/oak-tree) under **CC BY-SA 3.0**, with a separate `LICENSE_OAK.txt` notice included in every export preset. It is not part of the CC0 Quaternius pack. The pinned original ZIP and Blender file remain under `assets/landscape/vegetation/source/opengameart_oak_tree_lod_2026/`.

`convert_oak.py --blender <Blender-5.2.2-executable>` recreates the reviewed LOD0 glTF from the original 36 parts: 5,303 triangles, one surface and the original 1024² diffuse/alpha atlas. It bakes supplied transforms and consolidates parts without modeling or decimation; the conversion proof checks original positions, UVs and normals. Only supplied LOD0 is included. Supplier LOD1/LOD2 use different envelopes and remain outside runtime; Godot's automatic mesh LODs remain enabled.

Legacy material translation explicitly connects the original atlas to a core PBR material, with metal 0, scalar roughness 1, BLEND and double-sided rendering. This is a reviewed adaptation, not an authored roughness texture: roughness 0.5 produced white highlights in native back/underside views. Godot 4.7.2 does not import the source's zero legacy specular scalar; the effective value remains 0.5. No unsupported extension or runtime material override is added. The wind adapter rejects BLEND and preserves this source material. The atlas is lossless and un-mipped, with 3D auto-compression disabled.

The oak replaces `prop:shade-trees:06` at the existing position, heading, seed and target height. Its broader envelope changes collision-world identity. This is a separately identified world, not an exact-replay claim for previous recordings. See the [intake, native field comparisons and qualification limits](../../../docs/research/visual-quality-implementation/L6a-R1/mature-oak/README.md).

The retained Quaternius bark maps use the [qualified bark-only mip policy](../../trees/README.md#imported-bark-filtering-l6b-r2). Both leaf maps remain un-mipped; source pixels, geometry and alpha cutoffs remain intact.
