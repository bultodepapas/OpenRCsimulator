# SC-HUM-07 — Six different club members

Status: **partial, software-verified, 2026-10-24.** People variety, faces and clothing are delivered; the skin shader (plan §5.4) is still open. Owner: Scenery and field life. Plan: [field people plan](../../../plans/field-people.md). Builds on [SC-HUM-02](../SC-HUM-02/README.md) (one draw per pose) and [SC-HUM-00](../SC-HUM-00/README.md) (toolchain).

## What changed

LU-21 repeated one androgynous man (MPFB default gender 0.5) in a logo t-shirt across all 13 placements. The field now has six people, all from CC0 sources:

| Outfit | Person | Clothing | Poses | Height |
| --- | --- | --- | --- | ---: |
| `pilot_polo` | Middle-aged man | Polo shirt, cargo pants, ankle boots, dark glasses | pilot | 1.72 m |
| `veteran_cap` | Older man | Fedora, white t-shirt, jeans, cloth shoes | pilot, sitting | 1.75 m |
| `mechanic_overalls` | Young African man | Denim work overalls, t-shirt, work shoes | standing (pits) | 1.71 m |
| `casual_shirt` | Younger man, stubble | Striped shirt, jeans | standing | 1.71 m |
| `casual_jacket` | Middle-aged Asian man | Light jacket, jeans, reading glasses | standing | 1.66 m |
| `woman_tee` | Woman, ponytail | Tucked t-shirt, cargo pants, sneakers | standing, sitting | 1.63 m |

Outfits live in [tools/scenery/population/outfits/](../../../../tools/scenery/population/outfits/). [generate_people.py](../../../../tools/scenery/population/generate_people.py) gained `--outfit`: MPFB macros, proxy, skin, assets, decimation, texture sizes, natural metric height and an optional CC0 pose per pose kind. Without `--outfit` it still reproduces the LU-21 person byte for byte (standing `.gltf` and `.bin` hashes unchanged; the pilot's primitive transmitter varies its index order between any two runs, as before). [merge_people_atlas.py](../../../../tools/scenery/population/merge_people_atlas.py) `--shared` merges all eight poses into **one** atlas. Regions are deduplicated by image content, the atlas size is searched for minimal area with no edge above 4096 texels, and the sources are sorted by name, so the output is byte-identical whatever the command-line order.

Runtime ([population.gd](../../../../app/scenery/population.gd)):
- `OUTFITS` and `ZONE_OUTFITS` assign variants in turn per pose and zone. The pits favour the mechanic; the two flight-line pilots differ.
- Asset keys are `"<pose>/<outfit>"` → `people/<outfit>_<pose>.glb`.
- Outfits render at natural size, capped by the prefab's collision envelope (`min(1, fit)`); placements and collision are unchanged.
- [field_projected_shadows.gd](../../../../app/render/field_projected_shadows.gd) keys shadow casters by asset key, because several variants now share a pose.

## Budgets

| Item | SC-HUM-02 | SC-HUM-07 |
| --- | --- | --- |
| Distinct people | 1 | 6 |
| People draw surfaces (default field) | 3 | 8 (LU-21: 19) |
| People triangles, all instances at LOD0 | 96,415 | 96,185 |
| Max triangles per person | 7,880 | 7,822 (limit 8,000) |
| Diffuse / normal atlas | 2112² / 1056² | 2720 × 4064 / 1360 × 2032, VRAM-compressed with mipmaps (≈15 MB + ≈4 MB estimated; LU-21's single uncompressed person set was ≈17.5 MB) |

## Verification

| Check | Result |
| --- | --- |
| `test_field_people_gaze` (head mask on every variant: eyes rigid, shoes, transmitter and every garment or skin vertex below the neck band fixed; shader-mirror signs) | PASS, headless and native |
| `test_landscape_population_assets` (every declared variant must ship; source audits; production batches; native fit: each person inside its catalog envelope) | PASS, headless and native |
| `test_scenery_build`: each variant's drawn size fits its envelope with ≤8 % shrink and is ≥75 % of it | PASS. It caught `woman_tee` seated at 0.70 m wide (envelope 0.61 m); she now uses CC0 `callharvey3d_sittingnatural` (shrink 4 %). The old person-size check had been aborting on a script error without failing the test; that is fixed |
| `test_field_population_collection` 54/0, `test_landscape_population`, `test_field_projected_shadows` 59/0 | PASS |
| `capture_population_assets` (native) | All eight variants: motion changes; paused = held; reset = wrap = start |
| Running app, debug bridge, `OPENRC_SCENERY_QUALITY=high`, 1920×1080 | Pits show the mechanic, the striped-shirt man and the woman; veranda shows three different people; the flight line shows the polo pilot |
| Reproducibility | Shared merge byte-identical with reversed input order; default recipe unchanged |

Installation was staged and tested in a disposable full copy of `app/` before being applied to the tree in one step.

## Sources and rejections

All sources are CC0. Archive hashes and per-pack licence evidence are in [HUMAN_SOURCES.json](../../../../assets/scenery/population/HUMAN_SOURCES.json) (`sc_hum_07_outfits`). Credits are in [UPGRADE_CREDITS.md](../../../../app/assets/landscape/UPGRADE_CREDITS.md). New archives: shirts01, pants01, shoes01, glasses01 and bodyparts05.

Rejected:
- `toigo_maga_hat`: political slogan.
- `jujube_newsboy_cap`: its `.mhclo` has no material line, so it exports untextured; the merge now refuses such parts with a clear message.
- Garments with the MakeHuman logo.
- `toigo_flats`: 25,920 triangles after decimation.
- `cortu_jeans_shorts`: women's short shorts, wrong for the older man. CC0 therefore offers no men's shorts, which keeps plan decision D9 open.

## Limits

- The skin shader (wrap lighting, warm terminator) and baseball caps (CC-BY, D9) are not done.
- The pilots still hold the primitive transmitter until the owner's models arrive (SC-HUM-01).
- Texture memory is an estimate; a renderer memory reading on the owner's GPU is still needed.
- Body poses are the existing CC0 poses; pits work poses are SC-HUM-06.
