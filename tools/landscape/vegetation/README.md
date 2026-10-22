# Downloaded vegetation asset pipeline

`build_library.py` extracts a pinned selection of source geometry without creating plant geometry. It retains source archives and license evidence under `assets/landscape/vegetation/source/`, preserves original dependencies and records reviewed conversions, and writes `catalog.json` with hashes, bounds and geometry counts. The default output is `app/assets/landscape/vegetation/` and contains 28 assets, including 11 reviewed tree forms.

The runtime library contains 11 trees, 3 shrubs, 7 grass/herb assets, 4 flowering assets, 2 crops and 1 reed clump. Quaternius's Stylized Nature MegaKit Standard supplies seven trees, shrubs, grass, herbs and flowers under CC0-1.0. The separately licensed OpenGameArt oak, LOLIPOP maple and grass, dasy444 shrub, LandscapeLab trees and Poly Haven understory additions are described below. A second Quaternius CC0 pack supplies mature corn and wheat; Aredon's CC0 low-poly reed supplies the reed clump. Source pages, hashes and license evidence are recorded in the catalog and source notices.

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

The seven mature alias slots remain stable, and the weighted sapling alias still chooses from two source variants. Compatible imported trees can use the qualified tree-only wind shader; `--tree_wind=off` / `OPENRC_TREE_WIND=off` restores static imported trees without disabling separate field-card wind. The shader preserves reviewed albedo/normal maps, UV transforms, vertex colors, scalar PBR values and alpha scissor. It follows `sim_clock` and `wind_vec`, fixes the root and updates the normal/tangent frame. Unsupported material features, tilted/nonuniform transforms or separate stem/crown meshes retain source materials. Source textures and other plant roles are not rewritten by this option. The four LandscapeLab trees use it with measured per-asset sway limits ([L15b-R2](../../../docs/research/visual-quality-implementation/L15b-R2/README.md)); maples, the oak and library-only forms keep static source materials.

Current close-tree placement ([L6c-R1](../../../docs/research/visual-quality-implementation/L6c/species-variety/README.md)) has four maples, two LandscapeLab Quercus (oak), four Fagus (beech) and five pines, plus two young Quercus 2 saplings: 17 instances and 116,962 source triangles. The mature aliases select the maple, Quercus, Fagus and pine; the sapling alias uses the young Quercus 2 and pine. For the LandscapeLab draws, runtime duplicates each imported `StandardMaterial3D` and sets metallic to 0.0 because the supplier GLBs mark dielectric bark and foliage as 0.5; source resources, textures, alpha and roughness remain unchanged. The older note about eight source forms describes the superseded placement set. See the [renewal evidence](../../../docs/research/visual-quality-implementation/L6c/vegetation-renewal/README.md) for source, atlas and placement checks and remaining acceptance gates.

Tree spatial cells are optional: `--tree_cell_size_m=64`, `128` or `256` (or `OPENRC_TREE_CELL_SIZE_M`); `0` retains source-part batching. Instance transforms, colors, phases and damage IDs survive regrouping. No density increase is enabled. `set_wind()` adjusts only wind-enabled builds with per-build materials. `set_damage_hidden()` hides/restores all parts for a damage ID, and `bounds()` reports the live aggregate bounds; tree wind also expands render-culling bounds. See the [native comparison and remaining gates](../../../docs/research/visual-quality-implementation/L6a-R1/README.md).

## Mature oak intake (L6a-R1)

`oak_tree` reuses [lauris71's Oak Tree](https://opengameart.org/content/oak-tree) under **CC BY-SA 3.0**, with a separate `LICENSE_OAK.txt` notice included in every export preset. It is not part of the CC0 Quaternius pack. The pinned original ZIP and Blender file remain under `assets/landscape/vegetation/source/opengameart_oak_tree_lod_2026/`.

`convert_oak.py --blender <Blender-5.2.2-executable>` recreates the reviewed LOD0 glTF from the original 36 parts: 5,303 triangles, one surface and the original 1024² diffuse/alpha atlas. It bakes supplied transforms and consolidates parts without modeling or decimation; the conversion proof checks original positions, UVs and normals. Only supplied LOD0 is included. Supplier LOD1/LOD2 use different envelopes and remain outside runtime; Godot's automatic mesh LODs remain enabled.

Legacy material translation explicitly connects the original atlas to a core PBR material, with metal 0, scalar roughness 1, BLEND and double-sided rendering. This is a reviewed adaptation, not an authored roughness texture: roughness 0.5 produced white highlights in native back/underside views. Godot 4.7.2 does not import the source's zero legacy specular scalar; the effective value remains 0.5. No unsupported extension or runtime material override is added. The wind adapter rejects BLEND and preserves this source material. The atlas is lossless and un-mipped, with 3D auto-compression disabled.

The oak previously occupied `prop:shade-trees:06`; the club maple now replaces it. Its earlier broader envelope changed collision-world identity. See the historical [intake, native field comparisons and qualification limits](../../../docs/research/visual-quality-implementation/L6a-R1/mature-oak/README.md).

The retained Quaternius bark maps use the [qualified bark-only mip policy](../../trees/README.md#imported-bark-filtering-l6b-r2). Both leaf maps remain un-mipped; source pixels, geometry and alpha cutoffs remain intact.

## Club maple intake (L6c)

`maple_tree` uses LOLIPOP's supplied `Acer_large_3_LOD1` under CC BY 4.0: 5,541 triangles, two PBR surfaces and six 2K maps. The club tree remains 14 m; three additional placements at the farm and southwest forest vary from 10.01 to 11.52 m. The previous oak remains available in the library. `convert_maple.py` preserves supplied topology and records original/derived hashes; `build_library.py` validates its manifest. Six tracked texture settings enable VRAM compression. Five maps use mipmaps; the leaf color/alpha atlas stays unmipped to retain canopy coverage at distance. Both normals use normal-map mode. Export presets include `LICENSE_MAPLE.txt`.

See [source intake, conversion commands, native views, checks and the remaining cold-build limitation](../../../docs/research/visual-quality-implementation/L6c/house-tree/README.md).

## LandscapeLab trees and Poly Haven understory (L6c vegetation renewal)

The downloaded LandscapeLab Quercus, Quercus 2, Fagus and Pine models are pinned to commit `dfdde034c3547f9876967653d98827bd5348e52e` and licensed CC BY-SA 4.0. Fagus leaf maps derive from photographs by Krzysztof Golik (CC BY-SA); its upstream `LICENSE.md` is kept as `LICENSE_Fagus.md` and pinned per asset. `LICENSE_LANDSCAPELAB_LIBRARY.txt` is the four-tree notice the library ships as `LICENSE_LANDSCAPELAB.txt`; the source `LICENSE_LANDSCAPELAB.txt` stays the Quercus and Pine notice pinned by the far-tree atlas recipe. The table records source-space geometry before placement scaling.

| Source asset | License | Source triangles / surfaces | Source height |
| --- | --- | ---: | ---: |
| Quercus (`landscapelab_quercus`) | CC BY-SA 4.0 | 7,016 / 2 | 59.556 m |
| Pine (`landscapelab_pine`) | CC BY-SA 4.0 | 4,246 / 2 | 41.154 m |
| Fagus (`landscapelab_fagus`) | CC BY-SA 4.0 | 9,312 / 2 | 1.019 m |
| Quercus 2 (`landscapelab_quercus2`) | CC BY-SA 4.0 | 11,144 / 2 | 71.854 m |
| Fern 02 A (`polyhaven_fern_02_a`) | CC0-1.0 | 784 / 1 | 0.287 m |
| Flower Empodium A (`polyhaven_flower_empodium_a`) | CC0-1.0 | 758 / 1 | 0.267 m |

LandscapeLab source and derived GLBs retain the supplied mesh geometry, transforms, material names, textures and alpha conventions. The offline atlas adapter applies a grounded root wrapper to normalize each tree to 1 m without editing source geometry. The imported-vegetation library keeps source dimensions; runtime placement computes a uniform instance scale from the grounded source bounds and requested height. Poly Haven conversion preserves the supplied plant meshes and records the paired base-color/alpha inputs and conversion hashes. No plant geometry is generated. The adopted understory has 11 ferns and seven flowering Empodium A instances among 285 botanical placements, totaling 89,655 / 90,000 source triangles. Source checks do not establish full-scene or hardware acceptance; consult the current evidence report below.

At runtime, LandscapeLab tree batches set `lod_bias` to their largest instance scale, because MultiMesh LOD ignores per-instance scale. Their alpha-scissor foliage keeps only generated LOD levels that retain at least 25% of its triangles, and the tree-wind shader samples foliage albedo no coarser than mip 6. Leaf maps keep their mipmaps. Without these rules, distant crowns turned bare ([L6c-R1](../../../docs/research/visual-quality-implementation/L6c/species-variety/README.md#distant-landscapelab-foliage)). The static fallback (`--tree_wind=off`) has no mip clamp.

Run the source converters and library checks from the repository root:

```powershell
python tools/landscape/vegetation/convert_landscapelab_trees.py --check
python tools/landscape/vegetation/convert_realistic_understory.py --check
python tools/landscape/vegetation/build_library.py --check
python tools/landscape/vegetation/test_build_library.py
```

The LandscapeLab conversion manifest and per-source notices are under `assets/landscape/vegetation/derived/landscapelab_tree_2026/` and `assets/landscape/vegetation/source/landscapelab_tree_2026/`; the Poly Haven receipts and conversion proofs are under `assets/landscape/vegetation/source/realistic_understory_2026/` and `assets/landscape/vegetation/derived/realistic_understory_2026/`. See the dated [vegetation-renewal research record](../../../docs/research/vegetation-renewal-2026-10-20.md) and its [current evidence report](../../../docs/research/visual-quality-implementation/L6c/vegetation-renewal/README.md).

## Downloaded map accents (L6c)

`convert_grass_pack.py` extracts LOLIPOP's 26-triangle small and 20-triangle tall tufts. `convert_forest_shrub.py` extracts one 144-triangle leafy shrub from dasy444's forest scene. Both use supplied meshes/maps under CC BY 4.0, pin the licensed glTF archives and preserve source geometry. The grass uses double-sided MASK; the shrub preserves source BLEND. All seven new maps use compressed mipmaps. Runtime notices are `LICENSE_GRASS.txt` and `LICENSE_FOREST.txt`.

Run each converter with `--check`, then `build_library.py --check`. The deterministic habitat layout adds 60 grass tufts and four shrubs at the club, meadow and farm, using existing ground/exclusion sampling and a reserved seed range. [Map expansion evidence](../../../docs/research/visual-quality-implementation/L6c/map-expansion/README.md) records the native views, geometry budget and filtering comparison.
