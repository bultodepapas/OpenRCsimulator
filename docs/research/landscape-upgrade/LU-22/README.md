# LU-22 lake water and imported vegetation evidence

**Snapshot date:** 2026-10-13. This report records source identity, export inclusion, and headless checks for the current working tree. Water appearance, sound choice, and target-device performance remain unqualified.

## Sources and runtime data

The lake is a finite, irregular basin in [`app/data/fields/lake.json`](../../../../app/data/fields/lake.json). Its shoreline and bathymetry are estimates, not survey data. The water surface uses the project's separate Compatibility renderer adapter and the shared lake wave data; mean depth is 0.45 m down, with two bounded wave components and a 5.5 m shore fade. The renderer is pinned to Godot 4.7.2 Compatibility/OpenGL and reconstructs scene depth using OpenGL NDC Z. The upstream source review records the renderer references and why built-in SSR and compute are not used.

The shader reference is the [Boujie Water Shader](https://github.com/Chrisknyfe/boujie_water_shader), pinned at `25f3c2da458e0a4f65bdb5903dc068b050930c06`. Its preserved source file SHA-256 is `09a74e3b97738da896c9f39c73946e38f9487035c6559433316c2136ce84f607`; the preserved upstream MIT license SHA-256 is `fbde0da26c3bec6344219a8da2936e5ecb7eee6254f6080d2fe47d6b315ae856`. The adapted app shader SHA-256 is `8d5128e5e805d531bedb8cf46382b71c087b42154abdccebf1d77d4f1f302943` and [`water_material.gd`](../../../../app/render/lake/water_material.gd) is `31eec0518bb1d6e1750e1160f4d61bd769821d297b67211e3412dee1c360dfa7`. The adaptation removes the infinite ocean, third-party texture dependencies, and upstream vertex Gerstner waves. It uses no downloaded water textures. The exact source record and hashes are in [`water-source/PROVENANCE.md`](../../../../assets/landscape/lake/water-source/PROVENANCE.md); the MIT notice is also reproduced in the exported [`UPGRADE_CREDITS.md`](../../../../app/assets/landscape/UPGRADE_CREDITS.md).

The water audio is an audition/prototype set, not a claim about lake acoustics. The two Peludo splash files are CC0-1.0: `peludo-splash1.wav` SHA-256 `e45d466f7e63e5d566f8a822a7a1a3f7d5131319d17ca0436dcc615b251e9277`, and `peludo-splash2.wav` SHA-256 `ad9472b711666de2d43c3b102d155a5d1118b1fcd0ecd29cb63177256ab63f31`. RandomMind's five-minute Vistula wave recording is CC0-1.0: `randommind-vistula-short.mp3` SHA-256 `8c24607e41edd6f018ec3582a07e5a8dbc57347276339cb68440951a0fb4cfb1`. Exact source pages, download names, and the missing itch.io reference note for Peludo are in [`LICENSES.md`](../../../../app/assets/audio/water/LICENSES.md), SHA-256 `cf0adcdc34f0620d374d798ebfe16b707e4b4bd824d280c528ee6c2e6a726792`.

The runtime vegetation catalog contains 15 unchanged imported model assets: 3 trees, 2 shrubs, 4 grass/herbs, 3 flowers, 2 crops, and 1 reed clump. Their source geometry sums to 21,640 triangles for one of each catalog asset. The catalog SHA-256 is `65d8df415bbcb162405ecbdd7231c38ec41e83e5c9940e8d3a708f2c976a1c99`; the bundled Quaternius CC0 notice SHA-256 is `120710e542c3ebaf83856c4eb55b4a1e680593b39302eba7fdc5d942dfe78c58`. Its three source archives are pinned in the catalog: Quaternius *Stylized Nature MegaKit Standard*, `298f6732b872e4cf7b30e6e7abf9641c7f6dc6b326df37ac089533ed7e3d58c9`; Quaternius *LowPoly Crops Pack*, `48de7f1e092750a3832501e79d1463abeec8218c76090fc4b81fa8dfccacdb52`; and Aredon *LowPoly Reed*, `03fd4f90d92618090829bac1152e4280327edb179139ae3f0c66542af31b89bd`. Each is identified as CC0 in its retained source record. The two runtime four-view impostor manifests are also included in the pack: `bush_common_4view.json` SHA-256 `a5edd61c74228db18157e51975261b638ea72a20425ab69e577d4d849f600006` and `bush_common_flowers_4view.json` SHA-256 `1c673aea5119ad0de5a040d3271fd5ba979e70363a20ede170437c02177e3c85`.

## Export and headless verification

Linux, Windows, and macOS presets now explicitly include the lake JSON, vegetation catalog and CC0 notice, both impostor JSON manifests, water audio license manifest, and the credits file containing the upstream MIT notice. [`export_presets.cfg`](../../../../app/export_presets.cfg) SHA-256 is `6dbfec49eaf4e62014387beb605d7a1953a6d378f7441683d5fc2056608af30a`; [`UPGRADE_CREDITS.md`](../../../../app/assets/landscape/UPGRADE_CREDITS.md) is `4dbe30a6874fbbcd407c07da88665f1939e09aba4a251d5a250a938dcb8c2ddc`. A temporary Windows resource pack was exported with Godot 4.7.2 and mounted from an empty project. The empty-project check found all seven direct data/notice files and loaded all three imported water audio streams. The temporary pack was 46,512,024 bytes, SHA-256 `7967d311348d149d21bb41e2cd732979671f354c1b3930f61705ed5eb3fc6d4c`; it is a verification artifact, not a release package.

Headless Godot 4.7.2 checks used `--audio-driver Dummy` and completed without a native renderer capture:

| Check | Result |
| --- | --- |
| `test_imported_vegetation.gd` | Passed; this script prints a pass sentinel but no assertion total. |
| `test_lake_collision.gd` | 22 checks passed. |
| `test_lake_surface.gd` | 46 checks passed. |
| `test_lake_session.gd` | 29 checks passed. |
| `test_lake_ground_contact.gd` | 14 checks passed. |
| `test_water_effects.gd` | 39 checks passed. |
| `test_water_director.gd` | 14 checks passed. |
| `test_landscape_vegetation.gd` | 30 checks reported, 2 failed. The failures are the ten-crowns/six-shrub assertion and wildflower instance count; execution then reports `QuadMesh.surface_get_array_index_len` missing at `app/scenery/population.gd:101`. This current-tree failure is recorded without changing that separately owned code. |

## Evidence still pending

- Native Compatibility/OpenGL shader compilation and basin image review, including depth refraction, shoreline transition, and environment/probe reflections.
- Human splash and ambience audition, loop/mix review, and sound-level balance.
- GPU, frame-time, memory, and lower-end hardware measurements.
- Final exported application smoke test after the parent integration and any follow-up fixes.
