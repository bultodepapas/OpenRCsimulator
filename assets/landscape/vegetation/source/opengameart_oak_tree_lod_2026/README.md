# Oak tree source and conversion

This is lauris71's **Oak tree** from [OpenGameArt](https://opengameart.org/content/oak-tree), downloaded 2026-10-18 from the [original ZIP](https://opengameart.org/sites/default/files/quercus_A_packed_v1_0.zip). The page offers CC BY-SA 3.0 and GPL 3.0; this copy selects [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/legalcode). Keep the attribution and share-alike terms in [LICENSE_OAK.txt](LICENSE_OAK.txt).

The source page lists three LODs: LOD0 has 4,407 vertices and 2,791 faces; LOD1 has 645 vertices and 442 faces; LOD2 has 21 vertices and 7 faces. LOD1/LOD2 use a separate texture with prerendered branches and foliage. Only supplied LOD0 is converted for the runtime candidate; LOD1 and LOD2 are not used because those versions have not been qualified here. The original archive and Blender file remain available in this folder.

The conversion proof records LOD0's baked source bounds before glTF axis conversion, in Blender XYZ: **10.831 × 9.198 × 11.651 m** (min `[-5.828, -4.425, -0.858]`, max `[5.003, 4.772, 10.793]`). The source origin is not at the bottom of the tree; verify terrain contact before placement.

The source provides one diffuse/alpha atlas and no authored normal or roughness maps. The adapted glTF uses metallic 0, scalar roughness 1, and `BLEND`; roughness 1 is a reviewed legacy-material adaptation, not source texture data. The source's specular intensity is 0, but core glTF cannot represent that scalar and Godot 4.7.2 imports its specular extension as the default 0.5. This limitation and the material conversion are recorded in [CONVERSION-PROOF-LOD0.json](CONVERSION-PROOF-LOD0.json).

From the repository root, reproduce the LOD0 export with Blender 5.2.2 LTS:

```powershell
python tools/landscape/vegetation/convert_oak.py --blender "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"
```

The converter verifies the archived ZIP and BLEND hashes, batches only supplied LOD0 geometry, and writes the glTF files under `gltf/lod0/` and the canonical `CONVERSION-PROOF-LOD0.json` in this source folder.
