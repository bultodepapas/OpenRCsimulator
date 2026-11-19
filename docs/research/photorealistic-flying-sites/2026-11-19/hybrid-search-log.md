# Hybrid scenery: search record and primary sources

2026-11-19. Follow-up to the [hybrid design](hybrid-scenery.md).
**47 retained search strings, 30 grouped source records and 12 precedent
dossiers.** A source record can contain several closely related primary URLs;
these counts are not unique websites, successful implementations, elapsed hours
or adopted dependencies. Direct page/code retrieval and in-page searches are
additional verification, not inflated into extra research queries.

## Search method

The investigation asked three independent questions: who has actually combined
photo scenery with visible 3D objects; which Godot/Blender operations support
that combination; and what the current OpenRC repository already implements.
The first searches looked for direct RC authoring evidence and named production
accounts. Follow-ups targeted the gaps: actual scene files, camera/depth limits,
renderer support, provenance and source licenses. Routine searches used the
lighter search engine; stronger primary-source/coverage checks used the other
engine. Official manuals, project source and first-person creator posts were
preferred over image-based guesses or tutorial aggregation.

The earlier explicitly ordered **ten searches followed by ten more** remain
preserved in the [original technique log](../2026-11-18/search-rounds.md).
The [78-string resource investigation](../2026-11-18/resource-search-record.md)
and the [25-string adversarial review](research-log.md) are separate studies.
The parallel tracks below are not presented as one globally sequential search.

## Retained queries

### Lead searches: first four, then four adaptive searches

| ID | Exact query |
| --- | --- |
| HL01 | `"Godot" "panorama" "3D" "background" photorealistic` |
| HL02 | `site:cgm-online.com next scenery construction Blender 3D` |
| HL03 | `site:developer.valvesoftware.com "3D Skybox" "trees"` |
| HL04 | `site:theastronauts.com Ethan Carter photogrammetry vegetation` |
| HL05 | `site:developer.valvesoftware.com/wiki/3D_Skybox` |
| HL06 | `site:docs.godotengine.org sky_shader "AT_CUBEMAP_PASS"` |
| HL07 | `site:docs.blender.org "UV Project" "perspective"` |
| HL08 | `Godot photogrammetry forest demo source GitHub` |

### Precedent searches: initial twelve

| ID | Exact query |
| --- | --- |
| HPQ01 | `RC flight simulator photofield 3D objects panorama collision official scenery trees` |
| HPQ02 | `RealFlight PhotoField 3D objects panoramic photograph collision official` |
| HPQ03 | `aerofly RC simulator 4D photo scenery 3D objects official` |
| HPQ04 | `Valve developer 3D skybox 2D skybox map geometry trees official` |
| HPQ05 | `site:theastronauts.com Ethan Carter photogrammetry trees foliage artist workflow` |
| HPQ06 | `site:unity.com book of the dead photogrammetry forest trees production assets created 3d models` |
| HPQ07 | `site:unrealengine.com kite demo photogrammetry scanned trees foliage artist workflow` |
| HPQ08 | `site:quixel.com Rebirth photogrammetry environment 3d artists vegetation scans` |
| HPQ09 | `"photofield" "3d objects" visible trees scenery editor simulator` |
| HPQ10 | `RC flight simulator "panorama" "3D objects" scenery photorealistic` |
| HPQ11 | `RC flight simulator photorealistic panorama 3D objects scenery creator trees collision` |
| HPQ12 | `game virtual production real time panorama photo background foreground 3D trees hybrid production` |

### Precedent searches: fifteen follow-ups

| ID | Exact query |
| --- | --- |
| HPQ13 | `site:unity.com "Book of the Dead" "branches" photogrammetry trees scanned wind artist` |
| HPQ14 | `site:developer.valvesoftware.com "3D Skybox" "2D" scale geometry` |
| HPQ15 | `site:github.com PicaSim panorama scenery 3D objects render depth collision simulator GPL` |
| HPQ16 | `site:cgm-online.com "neXt" scenery Blender template scenery license` |
| HPQ17 | `"PicaSim" "ParallaxPanorama" depth panorama Danny Chapman` |
| HPQ18 | `"PicaSim" "panorama" "terrain" "depth" github` |
| HPQ19 | `"jaafit" "RealFlight" "Knife Edge" photofield programmer` |
| HPQ20 | `"3D skybox" "Portal" "Jay Stelly" skybox commentary` |
| HPQ21 | `CRRCSim scenery panorama skybox 3d objects trees xml site github scenery files` |
| HPQ22 | `FlightGear scenery photographic sky background 3d models trees orthoimagery scenery author` |
| HPQ23 | `site:github.com CRRCSim Davis scenery panorama planes trees license` |
| HPQ24 | `site:docs.flightsimulator.com photogrammetry aerial images trees 3d scenery data` |
| HPQ25 | `"Jay Stelly" "3D Skybox" Portal commentary 1/16 Valve` |
| HPQ26 | `site:developer.valvesoftware.com/wiki/3D_Skybox 1/16 skybox 2d` |
| HPQ27 | `site:github.com/ValveSoftware/source-sdk-2013 3d skybox sky_camera render 2D` |

The `GPL` and `1/16` strings were search hypotheses. The retained evidence
corrects them: PicaSim's current README specifies PolyForm Noncommercial;
the inspected Valve code exposes configurable scale, without establishing a
universal numerical value. Search wording is not a factual conclusion.

### Godot and Blender method searches

| ID | Exact query |
| --- | --- |
| HG01 | `Blender manual camera projection mapping UV project modifier background photo render camera project from view` |
| HG02 | `site:docs.blender.org manual clone brush texture paint stencil perspective photo cleanup object removal` |
| HG03 | `Godot 4 sky shader AT_CUBEMAP_PASS AT_BACKGROUND_PASS radiance sky reflections fog compatibility renderer` |
| HG04 | `site:docs.godotengine.org 4 visibility ranges fade modes Forward+ Mobile Compatibility geometryinstance3d` |
| HG05 | `site:docs.godotengine.org 4 alpha scissor hash antialiasing foliage depth prepass transparency shadows vegetation billboard` |
| HG06 | `site:docs.godotengine.org 4 MultiMesh visibility range culling instancing AABB whole multimesh chunks` |
| HG07 | `github godot engine panorama photosphere environment 3d real photograph photogrammetry game github` |
| HG08 | `github godot game 360 panoramic photo environment 3d objects panorama shader sky github` |
| HG09 | `Godot terrain panorama sky projected terrain seamless transition foreground background photograph occlusion github` |
| HG10 | `github godot photograph panorama projected textures geometry camera projection photomatching mesh shader demo` |
| HG11 | `site:docs.blender.org manual baking texture cycles emit image textures bake UV image active` |
| HG12 | `site:docs.godotengine.org 4 reflection source background ambient light source sky color custom sky background reflections separate` |

## Primary-source register

All entries were consulted on 2026-11-19. Manuals using `latest`, old versioned
manuals and historical project configurations are method references; the actual
OpenRC pin still requires qualification. Facts and limits are developed in the
[precedents](hybrid-precedents.md) and [technique dossiers](hybrid-scenery.md#twelve-technique-investigations)
instead of being repeated at length here.

### HS01

**neXt / Eiperle CGM:** [official scenery construction](https://www.cgm-online.com/rc-flight-simulator/next-scenery-construction_e.html)
and [FAQ](https://www.cgm-online.com/rc-flight-simulator/next-faq_e.html).
Direct RC photo/Blender authoring precedent. Template availability is not a
blanket asset license. Supports HP01/HM01/HM03/HM06.

### HS02

**ClearView:** [official scenery/collision authoring](https://rcflightsim.com/docs/CVCollision.html).
Visible `loadObjects` and separate collision content in photo fields.
Supports HP02/HM01; file formats are simulator-specific.

### HS03

**RealFlight G3:** [`jaafit` development posts](https://www.rcuniverse.com/forum/rc-flight-simulator-software-138/3301096-realflight-g3-hi-res-photofields.html)
and [panorama-authoring discussion](https://www.rcuniverse.com/forum/rc-flight-simulator-software/3381125-importing-panos-g3-guide-print.html).
First-person 2005 evidence, not current API documentation. Supports HP03.

### HS04

**aerofly creators:** [`jparia` / `momentmal` thread](https://www.aerofly.com/community/forum/index.php?postID=149121&thread/23332-user-created-4d-scenery-content-rc10/=).
Read the dated progression, including the December 2024 update, rather than
stopping at the initial RC7/newer-version difficulty. Supports HP04.

### HS05

**PicaSim:** [parallax panorama design](https://github.com/Rowlhouse/PicaSim/blob/main/ParallaxPanorama.md)
and [README license/data notes](https://github.com/Rowlhouse/PicaSim/blob/main/README.md).
Depth/stereo design precedent with restricted PicaSim-owned code and separately permissioned
artwork. No code or scenery was imported. Supports HP05/HM12.

### HS06

**Valve Source SDK**, commit `e1f1fd42271805072f052051c26c21caa2c87b04`:
[sky camera](https://github.com/ValveSoftware/source-sdk-2013/blob/e1f1fd42271805072f052051c26c21caa2c87b04/src/game/server/SkyCamera.cpp),
[view rendering](https://github.com/ValveSoftware/source-sdk-2013/blob/e1f1fd42271805072f052051c26c21caa2c87b04/src/game/client/viewrender.cpp),
[sky flags](https://github.com/ValveSoftware/source-sdk-2013/blob/e1f1fd42271805072f052051c26c21caa2c87b04/src/public/bspflags.h),
[lighting transform](https://github.com/ValveSoftware/source-sdk-2013/blob/e1f1fd42271805072f052051c26c21caa2c87b04/src/utils/vrad/vrad.cpp),
[license](https://github.com/ValveSoftware/source-sdk-2013/blob/e1f1fd42271805072f052051c26c21caa2c87b04/LICENSE).
Primary source replaced an inaccessible wiki and an unneeded secondary
commentary transcript. Supports HP06/HM11; code is not a Godot dependency.

### HS07

**Adam Bryla / The Astronauts:** [Ethan Carter foliage production](https://www.theastronauts.com/2014/02/approached-3d-foliage-vanishing-ethan-carter/),
2014-02-18. First-person production method, not downloadable cleared assets.
Supports HP07/HM05/HM08.

### HS08

**Andrzej Poznański / The Astronauts:** [Ethan Carter photogrammetry](https://www.theastronauts.com/2014/03/visual-revolution-vanishing-ethan-carter/),
2014-03-25. Photo-derived 3D-world production; not a fixed panorama camera claim.
Supports HP07 and the later 3D-site route.

### HS09

**Zdravko Pavlov / Unity:** [Book of the Dead assets and trees](https://unity.com/blog/industry/book-of-the-dead-photogrammetry-assets-trees-vfx),
2018-06-15. Trunk/crown/atlas production account. Supports HP08/HM05; proprietary
production tools and asset agreements are not adopted.

### HS10

**Julien Heijmans / Unity:** [wind, scene building and optimization](https://unity.com/blog/industry/book-of-the-dead-quixel-wind-scene-building-and-content-optimization-tricks),
2018-06-29. First-person assembly/optimization lessons, with separate sample and
supplier rights. Supports HP08/HM08/HM09.

### HS11

**Unity:** [DeLightingTool source](https://github.com/Unity-Technologies/DeLightingTool).
MIT authoring-tool source targeting an older Unity workflow. Possible reference
for asset preparation only; no tool installation, modern-version support or
automatic runtime relighting is claimed.

### HS12

**Epic Games:** [Harrison Moore, Open World assets](https://www.unrealengine.com/blog/creating-assets-for-open-world-demo)
and [Min Oh, Imperfection for Perfection, part 2](https://www.unrealengine.com/blog/imperfection-for-perfection-part-2).
Capture/lighting-reference and optimized asset production. Supports HP09/HM05/HM07;
does not grant unrestricted use of Epic's sample collection.

### HS13

**Microsoft Flight Simulator 2020:** [Using the SDK](https://docs.flightsimulator.com/html/Introduction/Using_The_SDK.htm?rhhlterm=shapefiles).
Official heterogeneous terrain/content pipeline and package description.
Supports HP10/HM11, without adopting proprietary data or planetary scope.

### HS14

**GamesNotDeveloped**, commit `623212ffeb4efbf4c95323a4a6a57e726be4f6e9`:
[README](https://github.com/GamesNotDeveloped/godot-forest-demo/blob/623212ffeb4efbf4c95323a4a6a57e726be4f6e9/README.md),
[project configuration](https://github.com/GamesNotDeveloped/godot-forest-demo/blob/623212ffeb4efbf4c95323a4a6a57e726be4f6e9/project.godot),
[main scene](https://github.com/GamesNotDeveloped/godot-forest-demo/blob/623212ffeb4efbf4c95323a4a6a57e726be4f6e9/levels/test_biomes.tscn),
[environment](https://github.com/GamesNotDeveloped/godot-forest-demo/blob/623212ffeb4efbf4c95323a4a6a57e726be4f6e9/materials/environment.tres),
[sky resource](https://github.com/GamesNotDeveloped/godot-forest-demo/blob/623212ffeb4efbf4c95323a4a6a57e726be4f6e9/materials/sky.tres),
[sky material](https://github.com/GamesNotDeveloped/godot-forest-demo/blob/623212ffeb4efbf4c95323a4a6a57e726be4f6e9/scenery/materials/M_layered_cloud_sky.tres),
[sky shader](https://github.com/GamesNotDeveloped/godot-forest-demo/blob/623212ffeb4efbf4c95323a4a6a57e726be4f6e9/scenery/shaders/layered_cloud_sky.gdshader),
[terrain builder](https://github.com/GamesNotDeveloped/godot-forest-demo/blob/623212ffeb4efbf4c95323a4a6a57e726be4f6e9/scenery/TerrainPatch3D.gd),
[biome batching](https://github.com/GamesNotDeveloped/godot-forest-demo/blob/623212ffeb4efbf4c95323a4a6a57e726be4f6e9/addons/gnd_biomes/Biomes.gd),
[pine license](https://github.com/GamesNotDeveloped/godot-forest-demo/blob/623212ffeb4efbf4c95323a4a6a57e726be4f6e9/objects/pine-tree-1/license.txt).
Scene/code evidence, not runtime execution. Initial web retrieval failed for
directories/scene files; primary repository text retrieval resolved that gap.
Supports HP11/HM04/HM07/HM10 with explicit renderer and per-asset limits.

### HS15

**Navier8:** [panorama demo](https://github.com/Navier8/Godot-Simple-Stereoscopic-360VR-Panorama),
[world scene](https://github.com/Navier8/Godot-Simple-Stereoscopic-360VR-Panorama/blob/main/world.tscn),
[stereo shader](https://github.com/Navier8/Godot-Simple-Stereoscopic-360VR-Panorama/blob/main/stereoequi.gdshader).
Source exposes the hidden glTF and sphere-depth limitation. Supports HP12 as a
control, not a successful photo-ground/visible-mesh integration claim.

### HS16

**Rokojori:** [Example-Grass.tscn at a fixed commit](https://community.rokojori.com/Rokojori/example-grass/src/commit/6e57c7ec7699fbdf3c89281e61f67a8c0356b330/Example%20Grass/Example-Grass.tscn).
Indexed primary scene text connects a panorama sky, ground, light and GrassPatch.
Direct open timed out. Image origin, renderer/version, asset rights and runtime
behavior remain unestablished; this is a bounded auxiliary example only.

### HS17

**Blender:** [UV Project modifier](https://docs.blender.org/manual/en/latest/modeling/modifiers/modify/uv_project.html).
Perspective/orthographic model and low-poly projection limits. Indexed manual
text and versioned pages were used when a direct latest-page fetch failed.
Supports HM06; it is not an equirectangular projector.

### HS18

**Blender 4.5:** [UV editing / Project from View](https://docs.blender.org/manual/en/4.5/modeling/meshes/editing/uv.html).
Planar view projection reference. Supports HM06; exact current authoring build
still needs the project's normal generated-asset workflow.

### HS19

**Blender 5.0:** [Cycles baking](https://docs.blender.org/manual/en/5.0/render/cycles/baking.html).
Destination UV/image-target requirements. Supports HM06; baking cannot create
unobserved photographic surfaces or establish contact geometry.

### HS20

**Blender 4.2:** [texture-paint tools](https://docs.blender.org/manual/en/4.2/sculpt_paint/texture_paint/tools.html).
Clone-paint operation for authored cleanup. Supports HM02, without claiming
automatic recovery of hidden scene content.

### HS21

**Blender:** [paint tiling](https://docs.blender.org/manual/en/latest/sculpt_paint/texture_paint/tool_settings/tiling.html)
and [painting introduction/image saving](https://docs.blender.org/manual/en/latest/sculpt_paint/texture_paint/introduction.html).
Panorama seam wrapping and explicit image persistence. Supports HM02; originals
and working derivatives remain separate.

### HS22

**GIMP 3.0:** [layer offset](https://docs.gimp.org/3.0/en/gimp-layer-offset.html).
Wrapped image offset brings a horizontal seam into the working area. Supports
HM02 as an alternative editing operation, not an extra runtime dependency.

### HS23

**Godot:** [sky shader reference](https://docs.godotengine.org/en/latest/tutorials/shaders/shader_reference/sky_shader.html).
Visible/cubemap pass distinction and radiance-update triggers. Supports HM07;
latest documentation is not an exact-pin capture/compilation result.

### HS24

**Godot 4.7:** [environment and post-processing](https://docs.godotengine.org/en/4.7/tutorials/3d/environment_and_post_processing.html).
Ambient/reflection source choices and environment responsibilities. Supports
HM07; a separate ambient color does not replace sky reflections.

### HS25

**Godot:** [standard 3D materials](https://docs.godotengine.org/en/latest/tutorials/3d/standard_material_3d.html).
Alpha-scissor/hash/blend, depth and shadow tradeoffs. Supports HM09; imported
source-specific materials and the actual pin take precedence over broad recipes.

### HS26

**Godot:** [renderer comparison](https://docs.godotengine.org/en/latest/tutorials/rendering/renderers.html)
and [Compatibility alpha-to-coverage PR](https://github.com/godotengine/godot/pull/114845).
The latest table marks Compatibility alpha-to-coverage unsupported; the PR was
open when inspected. A proposed feature is not an implemented requirement.
Supports HM09 and the renderer matrix.

### HS27

**Godot:** [image importing](https://docs.godotengine.org/en/latest/tutorials/assets_pipeline/importing_images.html).
Alpha-test coverage preservation and alpha-border processing. Supports HM09;
keep the import threshold distinct from the material cutoff and from MSAA
alpha-to-coverage. Existing maple evidence is in the OpenRC reuse audit.

### HS28

**Godot:** [GeometryInstance3D](https://docs.godotengine.org/en/latest/classes/class_geometryinstance3d.html).
Visibility-range fades and renderer restrictions. Supports HM04/HM09; disabled
fade with hysteresis is distinct from requesting an unsupported alpha fade.

### HS29

**Godot 4.4:** [visibility ranges / HLOD](https://docs.godotengine.org/en/4.4/tutorials/3d/visibility_ranges.html).
Two-object material-dither recipe as a separate technique. Supports HM09; noise,
shadow correctness and beta2 renderer behavior remain experimental.

### HS30

**Godot 4.5:** [MultiMesh](https://docs.godotengine.org/en/4.5/classes/class_multimesh.html).
Shared submission and whole-object culling. Supports HM10; optimal cell size and
complete-scene benefit require measurement, not an assumption from API choice.

## Repository and retrieval checks

The [reuse audit](hybrid-reuse-audit.md) records current catalog counts, generator
ownership, source formats/licenses, near/far vegetation, wind/filtering, parked
aircraft and physical limits. Relevant paths at planning commit
`f5dbf743f3e5229687688149fcda3215b8228a70` were compared against observed main
`99e5a5ac024935c32028e5332d31a3e09da4dc42`: `app/render`, `app/scenery`,
`app/landscapes`, `app/assets/landscape`, `app/project.godot`,
`app/get-godot.sh`, `tools/landscape`, `tools/trees`, `tools/ground`,
`tools/blender` and the Blender skill. That scoped comparison was empty.
Other tracks on main were not merged or certified by this study.

Rejected shortcuts include claiming full hybrid integration from a panorama
repository that hides its model; accepting a generic `free` label as export
rights; copying a Forward+ demo into Compatibility; using a third-party Valve
transcript after primary code became available; and carrying stale vegetation
counts or mipmap descriptions into the new plan. The aerofly thread's later
progress was retained after checking the complete dated discussion.

Source text established designs and existing code choices. No external sample
was run, no photo/Blender asset was produced, and no renderer, simulator,
import/export or device was qualified. The separate parallax receipt is an
analytical planning result. Implementation proof remains with the
[experiment plan](hybrid-experiments.md) and Q01–Q12.
