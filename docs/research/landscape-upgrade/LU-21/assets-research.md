# LU-21 — Replacement vehicle assets

Date: **2026-10-12**. **Status: three vehicle styles are integrated in the application; native acceptance is complete (see the final LU-21 report).** Step: LU-21. Scope: source/license audit, reproducible geometry reduction, and native Godot import/render checks. Human-asset work is recorded by the scenery owner.

## Adopted candidate

Adopt the original, unbranded Innerscene sedan, hatchback, and crossover as replacements for the current low-poly vehicle models. This is a coherent three-body-style family with full glazing, wheels, interiors, embedded materials, and a real-scale GLB workflow. The result reads as a parked passenger vehicle from side, front, rear, and top views in the pinned renderer. Keep all eleven current parking placements and fit the models to the existing estimated gameplay envelopes; the source dimensions are not manufacturer measurements.

The current budget-adjusted close models contain **24,470–25,686 triangles each**, within the plan's provisional **30k close-car exception**. Their original profile contained 26,066–27,517 triangles each; this modest reprocessing brought the default 11-car scenery scene below its existing 650k source-triangle ceiling while retaining protected glass. The manually reduced far variants contain **10,723–11,579 triangles**. They preserve every glass panel but miss the preferred 6–8k range; no further glass reduction was accepted without visual proof.

## Sources and license

All three pages identify the models as original and unbranded, provide GLB files at real-world scale, and dedicate them to CC0. Innerscene's library terms identify the dedication as CC0 1.0 and permit copying, modifying, and redistribution, including commercially, without credit. The terms also say parts may be removed and library files are kept for a limited period; the sedan, hatchback, and crossover pages currently show availability through **2031-10-07**. Preserve local copies and hashes with any production adoption. CC0 does not grant trademark or patent rights, so keep these unbranded variants and do not add real manufacturer marks.

| Candidate | Source / direct GLB endpoint | Page dimensions (length × width × height) | Downloaded source bytes / SHA-256 |
| --- | --- | ---: | --- |
| White four-door sedan | [Model page](https://www.innerscene.com/tools/library/3d-parts/white-four-door-sedan-1f271353) · [GLB](https://www.innerscene.com/api/library/white-four-door-sedan-1f271353/download) | 4.867 × 2.230 × 1.450 m | 5,063,600 · `0CD9FE7520255F93F0B1B56B6597100B058579AF980506C23E285ABD511C2845` |
| Silver five-door compact hatchback | [Model page](https://www.innerscene.com/tools/library/3d-parts/silver-five-door-compact-hatchback-6bf4a878) · [GLB](https://www.innerscene.com/api/library/silver-five-door-compact-hatchback-6bf4a878/download) | 4.281 × 2.160 × 1.490 m | 5,044,784 · `B91FD6ABFA24F1056B408517CE4DDBCD8E3E92406625A85790756C05A9A5849E` |
| Sage five-door crossover SUV | [Model page](https://www.innerscene.com/tools/library/3d-parts/sage-five-door-crossover-suv-1db314ad) · [GLB](https://www.innerscene.com/api/library/sage-five-door-crossover-suv-1db314ad/download) | 4.786 × 2.290 × 1.814 m | 5,034,660 · `D8DE49CEF044F82816F9C1CB99597CB6FB6090AA90BEE1AB182C64856FE210D5` |

The exact license evidence is on the [asset pages](https://www.innerscene.com/tools/library/3d-parts/white-four-door-sedan-1f271353) and in the [library terms](https://www.innerscene.com/tools/library/terms), version **2026-09-24**. The pages state CC0 and identify these as Innerscene original models; no attribution is legally required. The project evidence record is [LICENSES.md](../../../../assets/scenery/population/LICENSES.md), SHA-256 `E8DA1C723E60AA7549405A8502BC56A864991407B7D130D581CDC0E55E1F384C`; [SOURCE_MANIFEST.json](../../../../assets/scenery/population/SOURCE_MANIFEST.json) pins the snapshot hash, source URLs, original GLB hashes, and the reviewed close/far outputs.

The existing [scenery provenance](../../../../assets/scenery/PROVENANCE.json) records the current Quaternius cars as CC0 derivatives. LU-02 records eleven parked vehicles and four existing model IDs/styles. Those remain the baseline and are not reused as the visual replacement. Three new bodies can cover the four current IDs by reusing the hatchback style for the sport-compact slot without changing the eleven placements.

## Isolated reduction and outputs

Inputs were imported with **Blender 5.2.2 LTS** (`d13f752e3b9c`). Original inputs were left unchanged. The committed recipe in [preprocess_cars.py](../../../../tools/scenery/population/preprocess_cars.py) checks each source SHA-256, byte count, imported mesh/triangle count, and protected-glass count before reducing geometry. It removes tire-tread blocks, removes small non-paint/non-lens details by LOD, selectively decimates other meshes, joins each output into one mesh while retaining source material slots, and rotates the geometry so the Godot-space nose points **−Z** and the long axis is **Z**. The [source manifest](../../../../assets/scenery/population/SOURCE_MANIFEST.json) also pins the reviewed output hashes, sizes, triangle counts, and surface counts.

The original close profile used ratios `0.07`, `0.12`, `0.50`, `0.42`, `0.12`, and `0.22` for those groups. The current budget-adjusted close profile uses `0.064` for tire/rim/lug/center-cap/valve/brake parts, `0.108` for interior, `0.45` for the body shell, `0.38` for roof/pillars/fender lips, `0.108` for other parts above 500 triangles, and `0.197` for other parts above 150 triangles. Smaller untouched parts remain. The far reduction removed non-paint/non-lens parts with maximum bound at or below 5 cm, then used ratios `0.03` for wheel parts, `0.05` for interior, `0.15` for the body shell, `0.12` for roof/pillars/fender lips, `0.05` for other parts above 500 triangles, `0.08` above 150, and `0.15` above 50; smaller remaining details are removed. Tread blocks are removed in both passes. All ratios apply per mesh part before material joining; glass panels are excluded from both passes.

| Body | Source meshes / triangles | Glass panels preserved | Close output: triangles / surfaces / bytes / SHA-256 |
| --- | ---: | ---: | --- |
| Sedan | 304 / 132,082 | 6 / 4,032 triangles | 25,686 / 10 / 1,042,088 / `8DD24F39B09B062E1BCF235BA06FC48661EAE1271ECC498257BC149C7A8EEE17` |
| Hatchback | 314 / 130,902 | 8 / 5,376 triangles | 24,470 / 10 / 967,164 / `257AC6A3F9FBEEFE58A69068166B352209C79D056C98EAA22B67A1808B6086C5` |
| Crossover | 317 / 132,132 | 8 / 5,376 triangles | 25,359 / 10 / 1,015,168 / `4C86A201E4DA60B8E39D77E92530E564CC20AE107286985E4F51C7B923940A98` |

Each close GLB imports in Godot as one mesh with ten material surfaces. The Godot-measured bounds, before fitting to the game's estimated envelope, are:

| Body | Width × height × length | Lowest Y |
| --- | ---: | ---: |
| Sedan | 2.1871 × 1.5624 × 4.8403 m | −0.0134 m |
| Hatchback | 2.1231 × 1.6028 × 4.2648 m | −0.0139 m |
| Crossover | 2.2419 × 1.8442 × 4.7604 m | −0.0152 m |

These bounds differ slightly from page dimensions because they are imported geometry bounds, not source-page nominal dimensions. The lead should center each fitted model in X/Z, put its lowest rendered vertex at Y=0, and keep its collision envelope matched to rendered extents.

The far variants use the same protected panes and material join, with more aggressive per-part reductions and removal of objects no larger than 5 cm (except paint and lamp lenses). They produce:

| Body | Triangles / surfaces / bytes / SHA-256 |
| --- | --- |
| Sedan | 10,723 / 10 / 446,804 / `E6978709A58931760C8C407D5B885C87F99A03DFCBA0E9DECC32F8FE62B27346` |
| Hatchback | 11,541 / 10 / 456,452 / `CFCB053CA796956289AEB31CF6DC75388498CDC50D73F6F5F8F145933150F35A` |
| Crossover | 11,579 / 9 / 451,988 / `BE9EB2D859E2107497D6A0873F0FD2311690966668D07378FFCA5BC43AF2464B` |

The glass remains 4,032 triangles for the sedan and 5,376 for each five-door body in both variants. This prevents the missing-pane artifacts seen in a rejected whole-mesh reduction. The far outputs therefore favor intact vehicle windows over the 6–8k target; Godot's automatic mesh LOD is the adopted distance path; native 5/15/40/120 m captures and counters are recorded in the final LU-21 report.

## Godot compatibility and visual check

The installed application engine is **Godot 4.7.2 stable**, using the **Compatibility/OpenGL** renderer. The [Godot 4.7 feature list](https://docs.godotengine.org/en/4.7/about/list_of_features.html) recommends glTF 2.0 for 3D-scene import and identifies Compatibility as the OpenGL renderer. The [Godot 4.7 mesh-LOD guide](https://docs.godotengine.org/en/4.7/tutorials/3d/mesh_lod.html) says imported glTF scenes generate mesh LOD by default, and also cautions that decimation may introduce visual issues. Those documents establish available engine behavior, not that these particular panes remain intact at every LOD.

All six reduced GLBs imported successfully in Godot 4.7.2 and were rendered in native Compatibility/OpenGL on an RTX 3090. The focused importer check measured the triangle/surface counts above and confirmed each close and far output has one mesh, width on X, height on Y, length on Z. Native isolated views covered side, front, rear, and top for each body and LOD (24 images total). The close and far images retained their windshields, side panes, rear glass, wheels, and recognizable body shape; the earlier incorrect Y-axis conversion that tipped the cars was corrected and discarded before this check.

This is an asset staging capture, not proof of final field lighting, collision fit, automatic LOD selection, or frame cost. The 2026-10-16 budget-adjusted close outputs were also rendered with the existing Godot capture script at 5/15/40/120 m using Compatibility/OpenGL on Mesa llvmpipe. They kept ten material draws at each tested distance, and the 5 m views retained the windshields, side glass, wheels, and recognizable silhouettes. This software-renderer review checks geometry and appearance; it is not a hardware performance benchmark. Captures and binaries remain local review artifacts until the lead promotes selected files and evidence. The current 11-car close-mesh range is **269,170–282,546 triangles** across possible body mixes. The default two-sedan/five-hatch/four-crossover mix totals **275,158 triangles**; one of each body totals **75,515 triangles**. This is below the provisional 30k-per-close-car exception, but its impact on the 600k total-scenery and frame-time budgets still requires full-scene measurement. Each close model retains ten material surfaces, so the lead should verify actual instanced render submissions after integration.

The original source models and license evidence are vendored under `assets/scenery/population/source/cars`; the current close derivatives ship under `app/assets/scenery/population`. The portable rebake recipe is [preprocess_cars.py](../../../../tools/scenery/population/preprocess_cars.py), pinned to Blender 5.2.2 LTS, hash-checking the original sources and reviewed outputs, and requiring no runtime plugin. The 2026-10-16 Godot 4.7.2 checks measured 643,787 / 650,000 triangles for the complete default scenery and 2,992 / 3,000 additional triangles over the simple-prefab baseline for the pavilion plus two default pit shelters.

## Alternatives and remaining checks

The existing Quaternius cars are permissive CC0 and lightweight, but LU-02's native images show the low-poly look the user asked to replace. A [generic Sketchfab passenger-car pack](https://sketchfab.com/3d-models/generic-passenger-car-pack-20f9af9b8a404d5cb022ac6fe87f21f5) offers multiple 6–8k vehicles, but its page describes a low-poly pack and requires CC Attribution; it does not address the visual-quality objection. The [MMC Works generic sedan](https://sketchfab.com/3d-models/generic-sedan-car-58c33766470d46e7b2aed542650494e5) has 113.2k triangles, CC Attribution, and a NoAI restriction; it exceeds this scene's per-car budget by several times and is not needed for the tested unbranded family.

Before adoption, the lead should check the three source materials under production daylight/night exposure, preserve the body-paint vertex-color path, fit all eleven instances against their existing collision envelopes, inspect any importer-generated LOD at close and distant views, and measure the complete scene at the plan's target resolutions. Keep copied source files and hashes alongside final derivatives because the source library may remove its hosted downloads later.

## Release budget verification — 2026-10-16

Against committed baseline `978c36c7`, the close-car source pipeline reduces the eleven parked cars by 18,214 triangles while retaining all placements, ten surfaces per car and protected glazing. Bench planks use 14 longitudinal segments instead of 16; picnic furniture keeps 16. The pavilion saves 192 triangles and the complete scene saves 960 through its benches. No triangle ceiling or collision contract changed.

The [architecture check](budget-20261016/architecture.log) passes at **2,992/3,000 additional triangles**, and [complete scenery](budget-20261016/vegetation.log) passes at **643,787/650,000** (baseline 662,961). [Population asset checks](budget-20261016/population-assets.log), their [native renderer rerun](budget-20261016/population-native.log), and [scenery build checks](budget-20261016/scenery-build.log) pass. The [pinned Blender source rerun](budget-20261016/source-generator.log) reproduces the reviewed derived outputs; original downloaded models and license evidence are unchanged.

Paired 1280×720 Compatibility/OpenGL captures on llvmpipe retain the visible silhouettes, glazing, wheels and club furniture: [hatch before](budget-20261016/hatch-baseline.png)/[after](budget-20261016/hatch-candidate2.png), [sedan before](budget-20261016/sedan-baseline.png)/[after](budget-20261016/sedan-candidate2.png), [crossover before](budget-20261016/crossover-baseline.png)/[after](budget-20261016/crossover-candidate2.png), and [pavilion before](budget-20261016/pavilion-baseline.png)/[after](budget-20261016/pavilion-candidate2.png). This is geometry and appearance evidence, not target-GPU frame-time qualification.
