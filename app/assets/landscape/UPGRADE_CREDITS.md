# Landscape Upgrade Credits

Status: LU-01–10 implementation credit record, updated 2026-10-12.

The upgrade adds original procedural ridges, people, vegetation detail, support cradles, fixture hardware, shallow clubhouse window inserts, a warm-glazing shader, and sun-glare code. These contributions by OpenRCsimulator contributors are distributed under the repository [MIT license](../../../LICENSE). No new third-party media or runtime dependency was added. The optional screenshot checker uses Pillow 12.3.0 under its MIT-CMU license; Pillow is an offline evidence tool and is not redistributed in the simulator ([versioned license, checked 2026-10-11](https://github.com/python-pillow/Pillow/blob/12.3.0/LICENSE)).

The fixture visuals use display-aware caps: each runway SpotLight is limited to `24.0` scene-linear contribution after view exposure, the windsock SpotLight to `0.6`, and each veranda OmniLight to `0.12`. The FW path uses a local-light gain of `1`; an explicit static SDR lighting snapshot may use `1000` to keep local fittings visible at its fixed exposure. The gain is applied before the output caps and dusk factor. These are art-direction controls, not photometric lux measurements.

LU-08/09 adds original connected tree crowns/root flares, gravel shoulder variation, miniature chargers/battery packs/fuel cans, and depth-tested runway-marker optics. It reuses existing batches and placements. Directional green arrival/red end cues reference [FAA AIM 2-1-4](https://www.faa.gov/air_traffic/publications/aim_html/chap2_section_1.html); no FAA media is redistributed and no airport-compliance claim is made. Marker core/halo sizes (2.5/6.5 pixels), the 0.0025 distant readability gain floor and 300–600 m fade are artistic estimates. The marker cap is 1.0 after view exposure, multiplied by dusk and range fades. All additions are original MIT project work, with no new third-party runtime asset or plugin. [Continued refinement research and proof](../../../docs/research/landscape-upgrade/LU-07/README.md).

| Content used by the field | Creator / source | License and evidence |
| --- | --- | --- |
| Flood-light and stake positions | OpenRCsimulator, [`app/data/fields/lights.json`](../../data/fields/lights.json) | Original project data, MIT; LU-03 adds geometry at these existing positions. |
| Pavilion window dimensions and placement | OpenRCsimulator, [`app/scenery/prefabs.gd`](../../scenery/prefabs.gd), [`app/data/scenery/default.json`](../../data/scenery/default.json) | Original procedural project content, MIT; LU-03 adds shallow visual inserts matching the existing prefab. |
| Tree atlas and low-poly tree derivatives | Quaternius, *Stylized Nature MegaKit Standard* | CC0-1.0, as recorded with exact archive/license hashes in [`assets/landscape/PROVENANCE.json`](../../../assets/landscape/PROVENANCE.json). |
| Baked car models and farm-animal models | Quaternius | CC0-1.0 evidence and exact source/archive hashes are recorded per model in [`assets/scenery/PROVENANCE.json`](../../../assets/scenery/PROVENANCE.json). The cow and sheep records also cite their Poly Pizza listings. |
| Parked aircraft snapshots | OpenRCsimulator aircraft model teams | Original project models under the repository license; source model IDs and baked outputs are recorded in [`assets/scenery/PROVENANCE.json`](../../../assets/scenery/PROVENANCE.json). |

The detailed provenance files are authoritative for downloaded package identity, license-file hashes, model transforms, and generated-output hashes. All four parked aircraft were rebaked from their existing builders; the changed Extra snapshot's output hash was updated. No third-party mesh was modified. CC0 requires no attribution; the author/source records are retained voluntarily. Original code remains subject to the MIT copyright and permission notice. Current Quaternius QAL terms must not be assumed to apply to, or replace, an exact older archive's preserved CC0 license.

Maintained asset/tool alternatives, exact-version compatibility findings, redistribution restrictions, and reasons for retaining the existing assets are recorded in the [LU-00 resource review](../../../docs/research/landscape-upgrade/LU-00/resources.md). Final native renderer proof is in [LU-06](../../../docs/research/landscape-upgrade/LU-06/README.md).

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
