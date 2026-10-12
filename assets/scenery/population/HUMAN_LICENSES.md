# Human asset license record

Status: **CC0 source assets selected and audited for LU-21.** This file covers the MakeHuman-derived human meshes and textures only; car assets are documented separately in [LICENSES.md](LICENSES.md). Exact downloaded-archive and selected-file hashes are in [HUMAN_SOURCES.json](HUMAN_SOURCES.json).

## Included source content

- The MakeHuman system asset catalog marks the selected **male1591** body proxy, **middleage_caucasian_male** skin, **low-poly** eyes, **eyebrow001**, **short01** hair, **male_casualsuit04** clothes and **shoes02** as CC0. Catalog: [MakeHuman system assets](https://static.makehumancommunity.org/assets/assetpacks/makehuman_system_assets.html).
- The standing and pilot base use **standing02**, catalogued as CC0 by MakeHuman. Catalog: [MakeHuman system poses](https://static.makehumancommunity.org/assets/assetpacks/makehuman_system_poses.html).
- The seated pose is **anrico_sitting03**, credited to **Anrico** and marked CC0 both in the poses01 catalog and in its vendored `.meta` file. Catalog: [poses01](https://static.makehumancommunity.org/assets/assetpacks/poses01.html); item record: [Anrico's pose](http://www.makehumancommunity.org/node/2217).

The seven exported PNG maps are downscaled and converted copies of the selected CC0 asset textures. Their filenames, byte lengths and SHA-256 hashes are recorded in `HUMAN_SOURCES.json`. The pilot transmitter is simple geometry authored by the repository's MIT-licensed recipe; no third-party transmitter model or Mixamo content is included.

## Authoring software and output

The recipe uses Blender **5.2.2** and MPFB **2.0.18** as offline authoring tools. MPFB program code is **GPL-3.0-or-later**; its bundled asset collection is separately CC0. MPFB's own license file says generated graphical output is user data and makes no claim over exports. MPFB code is not copied into this repository's human assets or linked at runtime. MPFB source release: [v2.0.18](https://github.com/makehumancommunity/mpfb2/releases/tag/v2.0.18); the release's [license statement](https://github.com/makehumancommunity/mpfb2/blob/v2.0.18/LICENSE.md) distinguishes source-code and asset licenses.

The generated meshes and image maps are made from the listed CC0 source assets, with pose placement and small transmitter geometry authored by this project. The generated human assets are therefore recorded as **CC0-derived content**; the generator itself remains under the repository's MIT license. Blender and MPFB are authoring dependencies only and are not runtime dependencies of the simulator.

CC0 does not grant trademark, patent or publicity rights. No recognizable real person, brand or logo was intentionally used. Anrico is recorded as provenance even though CC0 does not require attribution.

## Redistribution note

The 267.7 MiB MakeHuman system-assets archive, MPFB source archive and full pose packs remain in local-only `.tools/` research storage and are not included. The repository preserves only the selected small proxy/material/clothing references and the two chosen BVH poses. The complete MakeHuman system pack is needed to rebake the textures and models; see [the source manifest](HUMAN_SOURCES.json) for archive URLs, hashes and exact selected assets.
