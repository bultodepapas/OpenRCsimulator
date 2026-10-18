# L6c vegetation impostor bake evidence

Date: 2026-10-18

The existing `tools/landscape/vegetation/bake_hedge_impostor.py` baker rendered the pinned Quaternius catalog meshes with Blender 5.2.2 LTS in background mode. It imported each source glTF and routed the imported Principled Base Color network, including its image and COLOR_0 chain, directly to emission; glTF alpha remained thresholded at the source cutoff. No source mesh, source texture, or new geometry was created or edited. The two source meshes contain 900 and 288 triangles respectively; these counts describe the reused source assets.

Both outputs are four 256 px views at azimuths 0, 90, 180, and 270 degrees, combined into a 1024 × 256 RGBA atlas.

| Source | Imported height | Square frame | Height / frame | Atlas SHA-256 | Manifest SHA-256 |
| --- | ---: | ---: | ---: | --- | --- |
| `bush_common` | 1.581786 m | 2.161655 m | 0.73175 (187 px) | `954bb172b6825494aa308fa13144ab7bd1140129db587ab1a97df3c58395f878` | `7c1a4d9ec3fbe1561dd6ee02e9e0d4fd5113ce033e423068e8ba73659e43542d` |
| `fern_1` | 0.840243 m | 3.109627 m | 0.27021 (69 px) | `6177218399bb6554d67971c5c3e2a0172d3febb40d4799fd0b9de2999fb3ad9f` | `5b84dafde1d9e7affec29ee1a9471faff2ce645c146676fdf2b26a38a4c17b75` |

The fern scale was reviewed before runtime adoption. Its baked imported bounds are 2.826934 × 2.652320 × 0.840243 m, so its height fills about 27% of the square frame. That is a visibly broad, low silhouette beside the flowering bush, whose height fills about 73%. The catalog currently lists fern bounds of 9.046188 × 8.487424 × 2.688778 m; all three dimensions are 3.2 times the baker's measured imported bounds. This bake preserves the imported glTF node transforms and applies no corrective scale. Runtime uses the measured frame/height ratio, caps the entire card inside the old patch envelope and produces 0.255–0.452 m fern heights; native readback verifies ground contact and bounds. No catalog or existing mesh placement was rescaled.

Source texture SHA-256 values recorded in the manifests:
- `bush_common` `Leaves_TwistedTree_C.png`: `0e459b56b14c0e81b1b7cf3d1e8c6f0bb71790eb6c46bb02a76a922d8df646ea`
- `fern_1` `Leaves.png`: `23248cebe28a24e78add32db3c2ee2f4d7b9219e9d2467279722f0197a7b6bd5`

The baker's `--check` passed for both assets after rendering. It verified source geometry, archive, license evidence, texture, and atlas hashes against the pinned catalog.

Rebuild commands:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --python tools/landscape/vegetation/bake_hedge_impostor.py -- --source-asset-id bush_common --output-stem bush_common_4view --frame-size 256
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --python tools/landscape/vegetation/bake_hedge_impostor.py -- --source-asset-id fern_1 --output-stem fern_1_4view --frame-size 256
```


Visual review confirmed four non-empty, transparent views in each atlas. The `bush_common` foliage is red because its pinned `Leaves_TwistedTree_C.png` source albedo is red; the bake preserves that source color network as requested. The existing flowering atlas and `bush_common_4view.gdshader` were left untouched.

## L6c third silhouette: tall grass

On 2026-10-18, `grass_common_tall` was baked through the same Blender 5.2.2 background pipeline as a 1024 × 256 atlas with four 256 px views. The mesh and its Base Color/Alpha material were reused; no new geometry was created. The source has 326 triangles.

- Imported bounds: 0.895089 × 0.993112 × 1.872695 m; frame: 2.059965 m.
- Native import/catalog height ratio: 1.0; the catalog bounds and measured imported bounds agree.
- Height/frame ratio: 0.90909 (about 233 px per 256 px frame).
- Atlas SHA-256: `da8c1ffadb27b4db066de3a535cbb9d67aa4f1c9f3ad4d6cb6be5395bcf44c`.
- Manifest SHA-256: `a267a3b854bab65e6123561a328d297fb0e8adc7ebb7f16ab0c71b3af205f06c`.
- Source `Grass.png` SHA-256: `5d69048193b246a73c996b892607fb36c75d0c60afcb2dab8aa12de3c0b2d9bd`.
- Baker `--check` passed; visual review confirmed four green grass silhouettes.

The red `bush_common` is rejected as the dominant silhouette for the green temperate setting. Its prior bake remains recorded as a rejected palette trial; no files were restored or deleted.

Rebuild command:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --python tools/landscape/vegetation/bake_hedge_impostor.py -- --source-asset-id grass_common_tall --output-stem grass_common_tall_4view --frame-size 256
```
