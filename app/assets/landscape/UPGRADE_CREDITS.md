# Landscape Upgrade Credits

## LU-16-R1 downloaded mountain relief (2026-10-20)

Club field's mountain backdrop now derives from **SRTM data courtesy of the
U.S. Geological Survey; Mapzen Terrain Tiles**. The
[public terrain dataset](https://registry.opendata.aws/terrain-tiles/) and
[provider's SRTM terms](https://github.com/tilezen/joerd/blob/master/docs/attribution.md#srtm)
permit this derivative. Source tile: `N04W074`, Colombian Eastern Cordillera.
The source was cropped, rotated, resized, height-scaled, filtered and tapered;
it does not represent a surveyed airfield or provide physical terrain.
The generated elevation grid and normal/cavity PNG replace the earlier
synthetic LU-01 ridges. Exact source hashes and transformations are retained in
`assets/landscape/mountains/README.md` in the source distribution. Original
adapter/shader/generator code remains MIT.

## LU-16-R2 mountain surface detail (2026-10-20)

[Aerial Grass Rock](https://polyhaven.com/a/aerial_grass_rock) and
[Aerial Rocks 01](https://polyhaven.com/a/aerial_rocks_01) by **Rob Tuytel /
Poly Haven**, CC0-1.0. Downloaded 1K JPG files are unchanged; Godot imports
compressed mipmaps, and the shader applies artistic palette/scale changes.
The habitat mask is derived from the same SRTM relief using slope, concavity
and altitude. [Packaged sources, hashes and transformations](mountains/sources.json);
[license references](mountains/LICENSES.md).

## Earlier upgrade sources

Status: LU-01–14 implementation credit record, updated 2026-10-12.

The upgrade adds original procedural ridges, people, vegetation detail, support cradles, fixture hardware, shallow clubhouse window inserts, a warm-glazing shader, and sun-glare code. These contributions by OpenRCsimulator contributors are distributed under the repository [MIT license](../../../LICENSE). No new third-party media or runtime dependency was added. The optional screenshot checker uses Pillow 12.3.0 under its MIT-CMU license; Pillow is an offline evidence tool and is not redistributed in the simulator ([versioned license, checked 2026-10-11](https://github.com/python-pillow/Pillow/blob/12.3.0/LICENSE)).

The fixture visuals use display-aware caps: each runway SpotLight is limited to `24.0` scene-linear contribution after view exposure, the windsock SpotLight to `0.6`, and each veranda OmniLight to `0.12`. The FW path uses a local-light gain of `1`; an explicit static SDR lighting snapshot may use `1000` to keep local fittings visible at its fixed exposure. The gain is applied before the output caps and dusk factor. These are art-direction controls, not photometric lux measurements.

LU-08/09 adds original connected tree crowns/root flares, gravel shoulder variation, miniature chargers/battery packs/fuel cans, and depth-tested runway-marker optics. It reuses existing batches and placements. Directional green arrival/red end cues reference [FAA AIM 2-1-4](https://www.faa.gov/air_traffic/publications/aim_html/chap2_section_1.html); no FAA media is redistributed and no airport-compliance claim is made. Marker core/halo sizes (2.5/6.5 pixels), the 0.0025 distant readability gain floor and 300–600 m fade are artistic estimates. The marker cap is 1.0 after view exposure, multiplied by dusk and range fades. All additions are original MIT project work, with no new third-party runtime asset or plugin. [Continued refinement research and proof](../../../docs/research/landscape-upgrade/LU-07/README.md).

LU-12/13 adds original pavilion/shelter construction details, a filtered procedural gravel shader reusing the project's integer cloud hash, and a luminance-preserving artistic twilight palette. LU-14 derives conservative canopy collision dimensions from the existing CC0 tree atlas and adds pavilion structural proxies. These are MIT project contributions; no new map, mesh, plugin or runtime dependency was downloaded. The ambientCG and Poly Haven CC0 gravel candidates were researched but not adopted. [Exact candidate links, permissions and rendering research](../../../docs/research/landscape-upgrade/LU-11/resources.md), [implementation and native evidence](../../../docs/research/landscape-upgrade/LU-11/README.md).

| Content used by the field | Creator / source | License and evidence |
| --- | --- | --- |
| Flood-light and stake positions | OpenRCsimulator, [`app/data/fields/lights.json`](../../data/fields/lights.json) | Original project data, MIT; LU-03 adds geometry at these existing positions. |
| Pavilion window dimensions and placement | OpenRCsimulator, [`app/scenery/prefabs.gd`](../../scenery/prefabs.gd), [`app/data/scenery/default.json`](../../data/scenery/default.json) | Original procedural project content, MIT; LU-03 adds shallow visual inserts matching the existing prefab. |
| Tree atlas and low-poly tree derivatives | Quaternius, *Stylized Nature MegaKit Standard* | CC0-1.0, as recorded with exact archive/license hashes in [`assets/landscape/PROVENANCE.json`](../../../assets/landscape/PROVENANCE.json). |
| Baked car models and farm-animal models | Quaternius | CC0-1.0 evidence and exact source/archive hashes are recorded per model in [`assets/scenery/PROVENANCE.json`](../../../assets/scenery/PROVENANCE.json). The cow and sheep records also cite their Poly Pizza listings. |
| Parked aircraft snapshots | OpenRCsimulator aircraft model teams | Original project models under the repository license; source model IDs and baked outputs are recorded in [`assets/scenery/PROVENANCE.json`](../../../assets/scenery/PROVENANCE.json). |

The detailed provenance files are authoritative for downloaded package identity, license-file hashes, model transforms, and generated-output hashes. All four parked aircraft were rebaked from their existing builders; the changed Extra snapshot's output hash was updated. No third-party mesh was modified. CC0 requires no attribution; the author/source records are retained voluntarily. Original code remains subject to the MIT copyright and permission notice. Current Quaternius QAL terms must not be assumed to apply to, or replace, an exact older archive's preserved CC0 license.

Maintained asset/tool alternatives, exact-version compatibility findings, redistribution restrictions, and reasons for retaining the existing assets are recorded in the [LU-00 resource review](../../../docs/research/landscape-upgrade/LU-00/resources.md). Final native renderer proof is in [LU-06](../../../docs/research/landscape-upgrade/LU-06/README.md).

## LU-21 replacement population (2026-10-12)

The parked passenger cars now use three original, unbranded **Innerscene** models: [sedan](https://www.innerscene.com/tools/library/3d-parts/white-four-door-sedan-1f271353), [hatchback](https://www.innerscene.com/tools/library/3d-parts/silver-five-door-compact-hatchback-6bf4a878), and [crossover](https://www.innerscene.com/tools/library/3d-parts/sage-five-door-crossover-suv-1db314ad). Their individual pages and [library terms, version 2026-09-24](https://www.innerscene.com/tools/library/terms) identify these assets as **CC0-1.0**, permitting modification and redistribution, including commercially, without attribution. Original GLBs, license evidence, and exact hashes are retained in the source distribution under `assets/scenery/population/`. Existing Quaternius car records above remain the provenance for retained legacy geometry.

The clothed people derive from the **MakeHuman Community** CC0 system assets (male1591 proxy, middleage_caucasian_male skin, male_casualsuit04, shoes02, short01 hair, low-poly eyes and eyebrow001), standing02, and **Anrico's anrico_sitting03** pose. [System assets](https://static.makehumancommunity.org/assets/assetpacks/makehuman_system_assets.html), [system poses](https://static.makehumancommunity.org/assets/assetpacks/makehuman_system_poses.html), and [poses01](https://static.makehumancommunity.org/assets/assetpacks/poses01.html) list the selected content as CC0; the seated pose's internal metadata agrees. Credit is retained voluntarily. No Mixamo or ambiguously licensed community pose is included.

Blender 5.2.2 and MPFB 2.0.18 are offline authoring tools. MPFB code is GPL-3.0-or-later; its separately licensed CC0 asset data and exported graphical output do not introduce a runtime plugin dependency. MPFB code is not distributed with this app. Original conversion scripts, bounded animation shader, transmitter geometry, terrain/material/light changes are project MIT work. Exact sources, transformations, shared-texture hashes, runtime file hashes, and native evidence: [LU-21](../../../docs/research/landscape-upgrade/LU-21/README.md), [source manifests](../../../assets/scenery/population/).

## LU-22 lake and vegetation source notice (2026-10-13)

The field data now includes the finite lake defined in [`lake.json`](../../data/fields/lake.json). Its shoreline, bank, bed profile, and 0.45 m mean depth are authored estimates, not a survey. The Compatibility renderer uses the reduced project adapter described in the [LU-22 evidence](../../../docs/research/landscape-upgrade/LU-22/README.md). It uses no third-party water textures. The water shader reference is Boujie Water Shader by Zach Bernal and contributors, pinned to commit `25f3c2da458e0a4f65bdb5903dc068b050930c06`; its preserved shader SHA-256 is `09a74e3b97738da896c9f39c73946e38f9487035c6559433316c2136ce84f607`. The full source and upstream notice are retained in [`water-source`](../../../assets/landscape/lake/water-source/PROVENANCE.md).

The LU-22 delivery imported vegetation from three CC0 sources: Quaternius's *Stylized Nature MegaKit Standard* (`298f6732b872e4cf7b30e6e7abf9641c7f6dc6b326df37ac089533ed7e3d58c9`, embedded license SHA-256 `120710e542c3ebaf83856c4eb55b4a1e680593b39302eba7fdc5d942dfe78c58`); Quaternius's *LowPoly Crops Pack* (`48de7f1e092750a3832501e79d1463abeec8218c76090fc4b81fa8dfccacdb52`); and Aredon's *LowPoly Reed* (`03fd4f90d92618090829bac1152e4280327edb179139ae3f0c66542af31b89bd`). Source license evidence and exact archives are retained under `assets/landscape/vegetation/source/`; the runtime catalog and bundled Quaternius notice are [`vegetation/catalog.json`](vegetation/catalog.json) and [`vegetation/LICENSE.txt`](vegetation/LICENSE.txt). The two four-view impostor image sets are render derivatives of those imported CC0 models; their JSON manifests carry source identifiers, license evidence, and hashes. No source water texture is bundled.

The downloaded audition sounds are CC0-1.0 samples and are not claims about the lake's acoustics. Their exact source pages, file names, and SHA-256 values are listed in [`audio/water/LICENSES.md`](../audio/water/LICENSES.md). That manifest is explicitly included with Linux, Windows, and macOS exports.

The water reference source is MIT-licensed. This permission notice applies to that source-derived shader work:

MIT License

Copyright © 2023-present Zach Bernal and contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Project permission notice

This file is explicitly included in the Linux, Windows and macOS export presets. Repository-relative evidence links refer to the source distribution. The following notice applies to the original project contributions above.

MIT License

Copyright (c) 2026 OpenRCsimulator contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


## Night-lighting resources (FW-67)

The field mast uses a transformed single head from Innerscene’s CC0 motion security floodlight. The optional hearth uses Kenney’s CC0 campfire pit and Mikodrak’s CC0 fire animation frames. Exact source URLs, authors, source/output hashes, license records and conversion details ship in `night-lighting/asset-manifest.json`, `night-lighting/LICENSES.md` and `night-lighting/licenses/`. No external addon runs in the application.

## Downloaded tree additions (L6a-R1, 2026-10-18)

The current vegetation library also includes [Oak Tree by lauris71](https://opengameart.org/content/oak-tree) from the Khayyam/Shinya game project under [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/). Its supplied LOD0 parts are consolidated without modeling or decimation; the original diffuse/alpha atlas is retained and its legacy material is translated to glTF PBR with a documented scalar-roughness adaptation. The asset and this derivative retain CC BY-SA 3.0. Attribution, source link and change details are bundled in [vegetation/LICENSE_OAK.txt](vegetation/LICENSE_OAK.txt).

The seven retained Quaternius Standard tree forms remain CC0-1.0. Their imported vertex-color buffers include the reviewed float-precision clamp; topology, normals, UVs and source textures are preserved. Exact source and derivative hashes are in [vegetation/catalog.json](vegetation/catalog.json).

## Woodland understory refinement (L6c, 2026-10-18)

Fern, tall-grass and short-grass cards are four-view renders of the existing Quaternius CC0 source meshes, with original Base Color/Alpha. Their bake manifests ship under `vegetation/impostors/`. The localized leaf litter uses [Forest Leaves 02 by Rob Tuytel / Poly Haven](https://polyhaven.com/a/forest_leaves_02), released under CC0. Its downloaded diffuse JPG is unchanged; Godot imports a 512 px mipmapped copy. Exact download identity and terms ship in [vegetation/woodland/source.json](vegetation/woodland/source.json) and [vegetation/woodland/LICENSE.txt](vegetation/woodland/LICENSE.txt).

## Club maple (L6c, 2026-10-18)

The maple source is also reused at the farm and southwest forest. New understory uses [LOLIPOP's Grass pack](https://sketchfab.com/3d-models/grass-pack-lowpoly-game-ready-422f42f618d342c6958b02613dc57403) and one shrub from [dasy444's forest scene](https://sketchfab.com/3d-models/a-forest-3-with-a-road-at-night-for-game-61f8c7817fe6457fb26e4814cfc48a3f), both CC BY 4.0. Selected supplied meshes are transformed to standalone glTF without modeling or decimation; grass alpha is adapted to MASK, shrub BLEND is retained. Attribution and modifications ship in [LICENSE_GRASS.txt](vegetation/LICENSE_GRASS.txt) and [LICENSE_FOREST.txt](vegetation/LICENSE_FOREST.txt).

3D tree model by [LOLIPOP](https://sketchfab.com/lolipop_1707), licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Source: [Maple Trees Pack](https://sketchfab.com/3d-models/maple-trees-pack-lowpoly-game-ready-lods-b5d2833c258f4054a01ee2b4ef85adf0). OpenRCsimulator selects the supplied `Acer_large_3_LOD1`, removes its gallery placement, converts its PBR materials and leaf alpha to glTF, and fits it uniformly beside the club. No tree geometry was modeled or decimated. Attribution and change details ship in [vegetation/LICENSE_MAPLE.txt](vegetation/LICENSE_MAPLE.txt); source and derivative identities are in [vegetation/catalog.json](vegetation/catalog.json).

## Agricultural plain (LU-28, 2026-10-20)

Roads reuse **Aerial Asphalt 01** by **Rob Tuytel / Poly Haven**, CC0-1.0:
[asset](https://polyhaven.com/a/aerial_asphalt_01), [license and exact download](countryside/LICENSES.md).
Fields reuse the retained CC0 grass/dirt photographs. Houses, farms, fences,
trees and cattle reuse the existing scenery library and its attribution records.
