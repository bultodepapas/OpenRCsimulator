# Downloaded vegetation and nearby lake — implementation plan

Date: 2026-10-13. **Status: planning only; implementation paused at the owner's request.** Owner: landscape integration lead. Steps: **LU-22–27**, continuing the [landscape track](landscape-upgrade.md). This revision supersedes this document's previous procedural-vegetation direction.

## Owner's requirement and delivery order

**Download existing tree and plant assets and integrate them. Do not model trees, shrubs, grasses, herbs, flowers, reeds or crops.** Then add a realistic lake near the runway, with an actual basin, depth, natural banks, shoreline vegetation, convincing water and a distinct aircraft water-impact sound and effect.

The current delivery is this Markdown plan only. Asset downloads, application changes, lake excavation, physics and audio integration belong to the later implementation. Earlier procedural vegetation experiments are not the selected delivery: first inventory the task-owned changes and replace or retire them carefully, preserving other developers' work. Do not revert shared commits wholesale.

Execute in this order: **resource selection → downloaded vegetation integration → landscape composition → lake basin and water → water impacts/audio → complete verification**. Keep each implementation step working and reviewable.

## Visual target

A beautiful rural airfield with believable plant silhouettes, bark, leaves and ground detail. Use mixed mature trees and saplings, tall and low shrubs, several grass/herb families, restrained flower drifts and distinct crop plots. Variation comes from different downloaded models, their authored material variants, natural scale ranges, orientation and habitat placement.

Keep the runway's maintained turf, pilot line, paths and landing approaches clear. Place taller vegetation behind the pilot and outside the approach corridors. Build irregular clusters with quiet gaps; combine fresh green, olive, sage, darker foliage and occasional straw tones. Flower colour accents belong around the club and meadow edges. Lakeside planting transitions from dry grass to damp soil, low bank plants and small reed clusters, with open shoreline sections where the water and bed remain visible.

Allowed asset processing: format conversion, axis/unit corrections, material adaptation, automatic LOD or reduction, texture optimization and instancing. Preserve the downloaded asset's recognizable shape. These operations must not become manual plant reconstruction or new procedural plant generators.

## Resource shortlist and selection gate

Primary pages checked on 2026-10-13. These are **candidates**, not downloaded or Godot-qualified selections. Inspect the exact archive, included license, available LODs and materials during LU-22.

| Resource | Intended use | Evidence and limits |
| --- | --- | --- |
| [Poly Haven Pine Forest collection](https://polyhaven.com/collections/pine_forest), including [Pine Tree 01](https://polyhaven.com/a/pine_tree_01) | Realistic tree/bark/foliage family; inspect supplied lower-detail versions first | [Poly Haven assets are CC0](https://polyhaven.com/license). Pine Tree 01's full source is listed at **17M triangles**: source/catalog size is not a runtime budget. Require supplied LODs or automatic optimization with silhouette review. |
| [Poly Haven Shrub 01](https://polyhaven.com/a/shrub_01) | Textured shrubs and bank planting | Full asset listed at **282K triangles**, with a LOD tag. Verify the actual download's lower-detail content; the original is unsuitable for mass instancing. |
| [Poly Haven Grass Medium 01](https://polyhaven.com/a/grass_medium_01) | Real grass clumps and dry/fresh variants | Full asset listed at **2M triangles**, with a LOD tag and dry diffuse map. Inspect actual mesh decomposition and lower-detail variants before choosing it. |
| [Poly Haven Flower Heliophila](https://polyhaven.com/a/flower_heliophila) | Small flowering groundcover trial | Real downloaded botanical detail; compare its visual/ecological fit. It supplies one flower family, not the complete flower assortment. |
| Existing Quaternius tree sources and [Stylized Nature MegaKit](https://quaternius.com/packs/stylizednaturemegakit.html) | Ready asset family for additional silhouettes, shrubs, grasses and flowers | Three local glTF trees and textures already have exact-package CC0 evidence in [provenance](../../assets/landscape/PROVENANCE.json). Newly downloaded packs need their own license review. Compare against the realistic candidates before choosing foreground content. |
| [ambientCG Grass001](https://ambientcg.com/view?id=Grass001) and Poly Haven ground/soil/rock materials | Turf variation, damp earth, mud, stones and lake bed | Download appropriate PBR maps and preserve their source/license records. Ground textures complement actual plant meshes. |
| [Kenney Nature Kit](https://kenney.nl/assets/nature-kit) | Lightweight backup for missing vegetation families and distant props | CC0 asset pack; its simple visual style needs comparison before use alongside more realistic foreground assets. |
| [Poly Haven Coast Rocks 01](https://polyhaven.com/a/coast_rocks_01) | Shore stone/pebble source trial | Check freshwater visual fit, source complexity and lower-detail options; avoid repeating a complete coastal formation around the lake. |
| [Big Water Splash — qubodup](https://freesound.org/people/qubodup/sounds/442773/) | Initial water-impact sound audition | Asset page declares CC0; approximately 2.17 s, 48 kHz stereo WAV. Download currently requires login. Use an accessible, exactly licensed alternative if necessary; verify and retain the actual file's license. |

**Remaining resource searches:** additional broadleaf trees/saplings, flowers of different shapes and colours, reeds/rushes, low shoreline plants, crop meshes, water normal maps and quiet shoreline recordings. Do not invent these models to fill a catalog gap. Continue the asset search and record a substitute when a candidate fails quality, license or performance checks.

For each adopted item retain source URL, author, retrieval date, exact version/commit or archive, SHA-256, original license, source files and a reproducible conversion recipe. Shipped credits must include any required attribution. A shader's code license does not automatically cover its example textures, recordings or models.

Start with a small comparison scene: at least two tree variants, two shrubs, three grasses/herbs and three flower variants. Inspect native 5/15/40 m views for bark, leaf transparency, ground contact, material response and repetition before multiplying the assets across the field. Quality and coherent style decide the selection.

## Godot water research and proposed choice

The project pins **Godot 4.7.2 / Compatibility / OpenGL**, with 4× MSAA. Preserve that engine and renderer for this work.

The [official renderer comparison](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html) documents screen/depth texture access and ReflectionProbe support in Compatibility; built-in SSR and compute shaders are unavailable. A water solution must work on this actual renderer. Support advertised for Godot 4.x alone is insufficient.

[Screen-reading shaders](https://docs.godotengine.org/en/4.7/tutorials/shaders/screen-reading_shaders.html) and [depth reconstruction](https://docs.godotengine.org/en/4.7/tutorials/shaders/advanced_postprocessing.html) explain the relevant inputs. OpenGL's NDC depth range is −1…1; do not import Vulkan's 0…1 reconstruction unchanged. Verify foreground occlusion, shallow-water depth, low camera angles and MSAA edges with controlled geometry. Transparent materials also require deliberate draw ordering and reflection tests.

| Candidate | Why evaluate it | Selection condition |
| --- | --- | --- |
| [Boujie Water Shader](https://github.com/Chrisknyfe/boujie_water_shader) — MIT | Existing Godot 4.1+ shader with waves, Fresnel, refraction, shore effects and depth controls | First compatibility trial. Adapt the downloaded material to a bounded lake and the existing clock; retain only useful features and verify all accompanying asset licenses. Its published test version is 4.1.1, not the project's version. |
| [Water with Caustics](https://godotshaders.com/shader/water-with-caustics/) — shader code CC0 | Alternative offering depth colour, refraction, foam and optional caustics | Second trial; Compatibility and external texture licenses remain unverified. Caustics should remain subtle in shallow water. |
| [GodotSSRWater](https://github.com/marcelb/GodotSSRWater) — MIT | Downloaded custom SSR/refraction alternative; author documents Godot 4.3+ and a 4.4.1 example | Reserve for a measured quality improvement. Custom SSR is separate from Godot's unavailable built-in SSR and must independently pass Compatibility, off-screen reflection and cost tests. |

**Proposed first implementation:** adapt an existing downloaded shader, use restrained wave/normal detail, Fresnel, depth-dependent absorption and shallow refraction. Compare sky/environment reflections and one bounded [ReflectionProbe](https://docs.godotengine.org/en/4.7/tutorials/3d/global_illumination/reflection_probes.html). Evaluate planar reflection only if those fail the visual target and its extra render pass fits the budget. Choose the tested result, not a promotional screenshot.

Water should have a darker blue-green deep centre, translucent shallows, shoreline ripples and sun/sky reflections that follow the existing lighting. Use small wind-driven lake waves. Foam is localized to appropriate banks, disturbances and impacts. Pause/reset/replay must hold or restore the effect through the simulation clock; imported shader uses of wall-clock time must be adapted.

## Lake siting and actual depth

**Initial placement estimate:** north-east of the club, centre approximately **N=110 m, E=125 m**, with an irregular footprint around **90 m east–west × 60 m north–south**. For the present runway this places the closest approximate shore roughly **65–85 m from its edge**, depending on the final shoreline. Verify the complete bank footprint against current scenery, approach corridors and ground data before accepting this location. These are design estimates, not surveyed or regulatory distances.

| Element | Initial design estimate |
| --- | --- |
| Shoreline | Irregular outline with one small inlet and open viewing banks |
| Water level | Roughly 0.3–0.6 m below surrounding ground |
| Shallow shelf | Approximately 3–8 m wide; progressively submerged stones/soil visible |
| Deep region | Approximately 4–6 m below the water surface, with continuous slopes |
| Bank | Gradual dry grass → damp soil/mud → shallow shelf transition; occasional rocks and imported reeds |

Depth requires a **real basin mesh and a matching scalar terrain sampler**. The existing nearby ground presentation does not displace a metre-deep basin, and the ground-physics guide describes separate millimetre relief ([GP-05](../research/ground-physics/GP-05/README.md)). Extend the local terrain contract explicitly. Cut the existing ground surface out of the lake footprint, connect the bank/bed mesh continuously, and use the same source boundary/heights for rendering and contacts. The old flat ground must not occlude the bed or falsely support an aircraft over the water.

Bank height, water level, bed depth, plant exclusions and shoreline distance should come from one validated lake definition. Record units and estimated provenance. Leave terrain and runway behaviour outside the bounded lake region unchanged. Imported shoreline plants and rocks must be grounded against this terrain, with appropriate obstacle proxies for solid objects. Remove or relocate existing grass, wildflowers, bales and other land props from the basin footprint; retain stable identities and update their placement source rather than hiding unexplained intersections.

## Water impacts, sound and presentation

1. Detect the earliest swept aircraft-probe crossing of the lake's water surface inside its shoreline polygon. Compare its time of impact with bank/bed and existing obstacle contacts. Check wing/gear/body probes, high-speed entries and grazing shore contacts; a centre-point-only detector is insufficient.
2. Produce one immutable impact event with water material, position, time, approach velocity/normal, depth and aircraft identity. Keep authoritative state and geometry in scalar float64/PackedFloat64Array math. The first delivery treats current land aircraft entering water as a crash; a later floatplane capability would require a separate flight-model scope.
3. Route that event through existing crash/session/audio interfaces. Play a **distinct downloaded splash recording**, with small bounded variants for impact strength; avoid also firing the usual dry-ground impact for the same entry. Stop or fade aircraft engine audio consistently with the crash state.
4. Present a bounded splash plume, droplets and spreading rings at the actual contact point. Follow with a short water disturbance and submerged/partly submerged wreck presentation. Clearly separate visual sinking from any implemented hydrodynamic response; do not label a visual animation as validated buoyancy.
5. Add quiet localized lapping-water ambience at the shore. Use spatial playback and the existing soundscape mixer, keeping the engine audible during normal flight. [Godot audio streams](https://docs.godotengine.org/en/4.7/tutorials/audio/audio_streams.html) and the [audio owner guide](../AUDIO-PLAN.md) are the integration references.
6. Reset and checkpoint restore must clear or restore splash/ripple/audio state without duplicate sounds. Include lake geometry and effect identity in the relevant world/checkpoint contracts. A lake-disabled configuration must consistently remove its water hazard and restore the normal field terrain.

Choose a shared water-surface definition for visual and contact height. If visible waves affect impact height, use the same bounded analytic parameters and simulation time in shader and scalar queries; measure their agreement. Test pause, clock wrapping and replay. Full fluid simulation, large ocean waves and general-purpose buoyancy are later scope.

## Steps, ownership and proof

All implementation steps remain **planned**. Lead owns resource selection, shared integration, this plan and final evidence. Coordinate ground/water-contact changes with physics/GP/CR, sound with AUD, and lighting with FW/TOD. Read git status before each shared patch. Optional Luna Max tasks must have bounded file ownership; resource research can remain read-only.

| Step | Work | Required proof |
| --- | --- | --- |
| LU-22 | Inventory earlier experiments; shortlist/download exact assets; license/hash review; isolate samples | Retained sources/licenses, clear adopted/rejected list and native visual comparisons; no newly authored plant models |
| LU-23 | Integrate selected tree, sapling, shrub, grass/herb and flower resources | Correct materials/scale, stable placement IDs, explicit collision envelopes, shared meshes/materials and usable LODs |
| LU-24 | Compose club, meadow, field margins and downloaded crop plots | Attractive native near/raised/pilot views; natural variation; clear runway, paths and approaches; stable quality subsets |
| LU-25 | Validate lake placement; compare downloaded water shaders; implement continuous basin, bed, bank and water | Measured 4–6 m depth, matched render/contact terrain, tested Compatibility shader, shoreline vegetation and day/dusk/night views |
| LU-26 | Add water-contact events, downloaded splash/ambient sound and splash/ripple/submersion presentation | High-speed swept tests, shore/body/wing/gear cases, one impact sound per event, recorded listening evidence, pause/reset/checkpoint behaviour |
| LU-27 | Verify the complete field and exported resources | Relevant app tests, native flight/water crash, repeated captures, paired performance, exact asset/credit packaging and honest limitations |

Proposed paths: external originals under assets/landscape/vegetation and assets/landscape/lake; accepted runtime resources under app/assets/landscape and app/assets/audio; reusable import/optimization tooling under tools/landscape. New lake renderer/definition/float64 contact modules should have their own files. Keep changes to scenery/world/session/audio seams narrow. Existing aircraft node/hinge names, authored aircraft data and golden flights remain outside this visual work.

Future dated evidence belongs in docs/research/landscape-upgrade/LU-22; required rationale and results should have one authoritative home. Do not create an archive of discarded plant prototypes.

## Acceptance and performance gates

- Downloaded assets visibly improve trees and low vegetation at 5/15/40 m, with coherent materials and grounded scale. The accepted library includes different silhouettes/heights, grass/herb families, varied flowers and crop vegetation.
- The lake is clearly visible near the flying field while preserving landing approaches. Its bed and continuous banks exist geometrically and physically; shallow and deep water look different from ground, low flight and raised views.
- A real aircraft water entry produces the water-specific crash event, audible splash, droplets and ripples. A near miss, bank collision and dry-ground impact produce their appropriate outcomes.
- Tests cover deterministic placement, plant/shore exclusions, surface crossing, terrain continuity, collision bounds, pause/reset, lighting changes, replay and resource loading from an exported pack.
- Compare 1280×720 and 1920×1080 on the same native renderer/GPU. Record frame median/p95/p99, visible/shadow draws, primitives, memory and scene-build time. Initial targets retain **300 visible draws, 1M rendered primitives and <16.67 ms frame p95**; aim for **≤1.5 ms added p95** in a matched complete-field comparison.
- The existing **600k scenery-triangle budget** is the starting limit, not permission to force high-detail downloads into it by destroying their silhouettes. Select supplied LODs/appropriate assets first. Any needed revised geometry or texture budget must be proposed with a small measured comparison before field-wide adoption. Reflection rendering and transparent overdraw must be included in cost measurements.
- Initial asset targets: shared 1K/2K maps, bounded spatial batches and **≤64 MiB added resident textures**. Treat this as a provisional cap to validate, not current usage. Keep effect pools bounded and water queries inside the existing per-tick physics budget.

Independent pilot preference, lower-end hardware acceptance and physical water-impact/buoyancy calibration are separate from software verification. Existing Linux atmosphere-trim and nearby collision-cost limitations remain documented in their owning reports.

## Next action after this plan

Begin LU-22 with **downloads and an isolated comparison of existing assets**. Select the vegetation library from native images, integrate that library, and then proceed to the lake. The procedural-plant modelling route is superseded.
