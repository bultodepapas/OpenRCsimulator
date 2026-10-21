# Graphics research, round 2: 25 investigations

2026-10-21 · VQ-07 planning evidence · Internet/source review; no new runtime measurements.

This follow-up answers the request for at least 20 additional investigations, including GitHub, Reddit and forums. It contains **25 distinct questions**, each with sources actually opened, an evidence limit and a proposed OpenRC action. R01–R25 are research references, not new implementation-step IDs. Execution and prioritization belong to the [upgrade plan](../../plans/advanced-graphics.md); the [first audit](README.md) retains the supplied brief and baseline.

Source mix by lead investigation: six Godot documentation studies (R01–R05, R25), three tool/author references (R06–R08), eight GitHub studies (R09–R16), four Reddit discussions (R17–R20) and four Godot Forum discussions (R21–R24). Supporting links are not counted as extra investigations. Community reports are primary accounts of their authors' experience, not proof of a current engine defect or a benchmark for OpenRC. Technical recommendations use official documentation or upstream code/discussion as corroboration. Dates and issue states are snapshots as inspected today; pin exact revisions before reuse.

**Disposition:** “Selected” adds a bounded diagnostic or comparison to an existing step; it does not adopt a feature. “Conditional” requires a measured defect or budget before a prototype. “Deferred” adds no delivery dependency. All candidates retain the [measurement contract](../../plans/advanced-graphics.md#6-measurement-and-acceptance), unchanged physics and owner acceptance.

## R01 — Camera and aircraft interpolation phase

**Question:** Can a renderer/AA comparison introduce jitter by mixing simulation-tick and rendered poses?

**Read:** Godot 4.7 [advanced physics interpolation](https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/advanced_physics_interpolation.html), alongside the local [camera contract](../../plans/camera-views.md) and [simulation interpolation](../../../app/sim/simulation.gd). The manual describes camera interpolation and parent-transform interactions. OpenRC already interpolates its float64 simulation state and feeds a rendered pose to the camera; this is a regression risk, not a missing feature.

**Action / decision:** **Selected**, VQ-07b/d with CAM. Observe aircraft, camera, shadow and smoke attachment through the same tape at 30/60/120/144 Hz where supported, including pause, reset and cuts. Diagnose phase mismatches before adding smoothing. Retain one presentation interpolation path and 240 Hz physics; do not apply built-in interpolation a second time. Pass with stable relative motion and unchanged simulation results.

## R02 — Import-time roughness filtering for specular sparkle

**Question:** Can stock texture import reduce material shimmer before changing AA or making the whole aircraft matte?

**Read:** Godot 4.7 [image import options](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html). Roughness filtering uses an identified roughness channel and source normal map during import to reduce specular aliasing. It does not repair thin-geometry aliasing, and it needs suitable texture inputs.

**Action / decision:** **Conditional**, VQ-02a/b with the aircraft owner. Inventory existing normal/roughness pairs and importer applicability, including embedded/generated textures. If a moving highlight demonstrates a defect, compare one correct stock-import recipe against the current asset at native resolution. Preserve the intended finish, markings and generator provenance. Retain the candidate only if sparkle improves without excessive loss of material identity. This does not reopen the deferred custom mip/import pipeline or mandate new texture packs.

## R03 — Vegetation batch bounds and night-light reach

**Question:** Can a draw-call improvement make culling or night lighting worse?

**Read:** Godot 4.7 [MultiMesh class](https://docs.godotengine.org/en/4.7/classes/class_multimesh.html) and [MultiMesh performance tutorial](https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html). The tutorial carries an outdated-content notice; the class reference corroborates whole-batch visibility, custom bounds and a per-object light limit shared by instances.

**Action / decision:** **Selected refinement**, L/LU/SC and VQ-07c, of the existing [tree batching study](../../plans/tree-forest-quality.md). Compare existing sectors/grid candidates with identical placement and contacts. Include maximum wind deformation in bounds and inspect lamp reach at night as well as daytime culling. Record total main/shadow-pass work, not only draw count. Change batching only if overall timing improves without disappearing foliage, incorrect illumination or altered collision/population state; do not create another chunking system.

## R04 — Reflection-probe environment and refresh policy

**Question:** Do reflected surroundings match the visible environment, and which captures are worth their cost?

**Read:** Godot 4.7 [ReflectionProbe reference](https://docs.godotengine.org/en/4.7/classes/class_reflectionprobe.html). Probes obtain environment information from WorldEnvironment, not a camera's environment override. UPDATE_ONCE is not a promise to refresh on every nearby-object change; capture masks, shadows and continuous updates affect cost.

**Action / decision:** **Selected** source/environment parity in VQ-07b/e; **conditional** refresh optimization. Compare Home, Workshop and Fly, then day-to-dusk transitions and scene restoration. Trial bounded refresh and a capture mask that omits expensive fine detail only when its reflection is immaterial. Preserve meaningful aircraft, structure and sky response. Reject stale sunset reflections or refresh hitches. Keep capture masks distinct from which objects receive a probe; no new reflection framework is implied.

## R05 — Shadow-map allocation before soft shadows

**Question:** Can targeted cascade allocation improve landing contact without a blanket resolution increase?

**Read:** Godot 4.7 [lights and shadows](https://docs.godotengine.org/en/4.7/tutorials/3d/lights_and_shadows.html). Directional shadow distance, cascade coverage, split blending and bias trade precision, artifacts and rendering work. Geometry can be drawn in several cascades. Local atmosphere setup currently chooses two splits; do not assume a four-split baseline.

**Action / decision:** **Selected**, VQ-04b/VQ-07e. At fixed atlas resolution, change maximum shadow distance, cascade allocation and bias one at a time before PCSS. Include landing gear, fences, runway cues, low sun and the far flight envelope; distinguish camera far clip from shadow distance. Preserve useful long shadows and compare the projected-silhouette reference. Pass only with more stable contact cues and measured cost within the owning budget.

## R06 — Attribute overdraw with an existing free profiler

**Question:** Is expensive foliage/smoke limited by covered pixels, small triangles, texture use or shadow passes?

**Read:** RenderDoc's upstream [introduction](https://github.com/baldurk/renderdoc/blob/v1.x/docs/introduction.rst), [platform/API overview](https://github.com/baldurk/renderdoc/blob/v1.x/docs/include/intro_header_inc.rst) and [texture-viewer manual](https://github.com/baldurk/renderdoc/blob/v1.x/docs/window/texture_viewer.rst). The MIT-licensed tool documents pass inspection, texture/mip inspection and overdraw/triangle-size overlays. Feature availability depends on API; these sources do not establish macOS Metal support. The direct documentation host was inaccessible, so repository documentation was read instead.

**Action / decision:** **Selected diagnostic when attribution is needed**, VQ-07c, reusing the [existing tools investigation](../debugging-tools-2026-10-19.md). Retain one annotated worst-case native frame to explain vegetation, smoke, water or shadow cost. Measure performance separately without capture overhead. Download/pin the existing tool if needed; do not implement a replacement profiler or treat a captured frame as steady-state timing.

## R07 — Rendered, displayed and input metrics are different

**Question:** Can presentation telemetry support honest frame-generation and pacing comparisons?

**Read:** Intel's MIT-licensed [PresentMon repository](https://github.com/GameTechDev/PresentMon) and [console manual](https://github.com/GameTechDev/PresentMon/blob/main/README-ConsoleApplication.md) (manual modified 2026-06-05). The Windows tool distinguishes CPU/GPU/display timing and presentation mode. Frame-type tracking requires application/driver instrumentation. Its keyboard/mouse latency fields do not measure the full RC-radio path or replace a physical input-to-photon test.

**Action / decision:** **Selected measurement refinement**, VQ-07a/c/h with DT. Identify the simulator process and swapchain, retain dropped-frame rows and record VSync, cap, refresh and presentation mode. Label unsupported fields unavailable. Report generated-frame separation only when instrumentation supports it; otherwise leave that vendor claim unqualified. Reuse exported CSV and existing plotting tools. Compare ordinary native pacing first, and keep physical latency acceptance separate.

## R08 — A reusable atmosphere reference before a replacement

**Question:** Can a published reference help judge horizon/sunset errors without immediately building another sky renderer?

**Read:** Eric Bruneton's [2017 precomputed-atmosphere implementation](https://ebruneton.github.io/precomputed_atmospheric_scattering/) and [BSD-3-Clause license](https://github.com/ebruneton/precomputed_atmospheric_scattering/blob/master/LICENSE). The author provides C++/GLSL code, demos and validation machinery including spectral reference comparisons and dimensional checks. It is a reference implementation, not a drop-in Godot addon or validation of OpenRC.

**Action / decision:** **Deferred production replacement; conditional reference use**, FW/SUN. If the existing sky has a documented horizon or sunset defect, use the available demo/reference to compare a controlled clear-sky case, recording solar direction, exposure and assumptions. Reuse licensed code only after an explicit need and integration review. Do not turn visual research into a planetary atmosphere system or alter physical density/weather laws.

## R09 — Octahedral impostors as a far-field LOD

**Question:** Could an available impostor baker reduce distant scenery cost while retaining its silhouette?

**Read:** The [octahedral-impostor addon README](https://github.com/hdrsniped/octahedral-impostor-lod-godot/blob/main/README.md), at [2026-10-19 revision e3513a4](https://github.com/hdrsniped/octahedral-impostor-lod-godot/commit/e3513a4c1879f1ef9cdc289c7b20b90f3ca4ef7f), claims Godot 4.7+ and lit depth/normal/material atlases, wind and LOD support. A license was not established for this fork; public source is insufficient reuse permission. The older [v2.0-new-baker branch](https://github.com/wojtekpil/Godot-Octahedral-Impostors/tree/v2.0-new-baker) has an [MIT license](https://github.com/wojtekpil/Godot-Octahedral-Impostors/blob/v2.0-new-baker/LICENSE), but pinned-engine compatibility remains unverified.

**Action / decision:** **Deferred adoption; conditional licensed prototype**, L/LU/SC with VQ-07c. Only after a measured far-field bottleneck, compare one distant tree or rock against the existing LOD. Keep near meshes, placement and collisions. Check angle-dependent silhouette, wind, shadows, atlas memory, bake reproducibility and transition cost on the circuit. Do not download/integrate the current fork until its licensing is clear; do not assume the MIT alternative runs on 4.7.2.

## R10 — Reuse Material Maker for an otherwise unmet material need

**Question:** Is a free existing authoring tool preferable to writing a custom material generator?

**Read:** Material Maker's [README](https://github.com/RodZill4/material-maker/blob/master/README.md), [2026-10-21 README revision](https://github.com/RodZill4/material-maker/commit/497af15843a740f3994f5913350e0cd2ee76461a) and [MIT license](https://github.com/RodZill4/material-maker/blob/master/LICENSE.md). It offers procedural texture graphs and model painting. Automated master builds are described as at-risk; this review did not qualify a specific release. The tool's license does not grant rights to arbitrary graph inputs.

**Action / decision:** **Conditional offline tool**, VQ-02b and aircraft owners, only after retained/free downloads fail a named need. Use one material, preserve graph and input provenance, pin a release and export through the established source pipeline. Validate channel conventions, real-world scale and appearance at close/20/50/100 m. This adds neither a runtime dependency nor authorization to recreate freely downloadable content.

## R11 — Lake reflections and the changed SSR path

**Question:** Would a reusable ocean shader or SSR actually improve the existing lake?

**Read:** [godot4-oceanfft](https://github.com/tessarakkt/godot4-oceanfft/blob/devel/README.md) describes an early Godot 4.3+ WIP with remaining rendering/refraction/optimization work; licensing was not established for the inspected branch. Separately, the merged [SSR overhaul #111210](https://github.com/godotengine/godot/pull/111210) uses prior-frame color. Open [issue #115541](https://github.com/godotengine/godot/issues/115541) reports alpha color leaking through a moved occluder in 4.6. A [maintainer comment](https://github.com/godotengine/godot/issues/115541#issuecomment-3815704963) calls the old blanket transparency exclusion outdated; a later 4.7-dev test reports missing alpha reflections, with a reply explaining the lack of a depth hit behind the alpha object. Neither reliable inclusion nor universal omission follows.

**Action / decision:** **Selected SSR test correction; deferred FFT replacement**, VQ-07e with LU. Keep probe-first water. On 4.7.2, compare alpha sources with/without an opaque depth surface and a moving occluder; inspect omissions, false inclusion, history lag, edges and depth/refraction. Require a demonstrated wave gap, explicit license and cost evidence before any ocean prototype. No ocean system is needed merely to improve lake highlights.

## R12 — Animated UVs and temporal reconstruction

**Question:** Can a scrolling texture leave history trails even when object motion is correct?

**Read:** Open [Godot #69493](https://github.com/godotengine/godot/issues/69493) (created 2022-12-02; updated 2025-11-23) reports ghosting with animated material UV transforms and shader TIME on 4.0 beta 7. Open [proposal #5888](https://github.com/godotengine/godot-proposals/issues/5888) asks for shader motion-vector access. A proposal is not a shipped API, and these reports do not establish current behavior.

**Action / decision:** **Conditional test**, VQ-07d. Inventory actually animated UV/material inputs in water and other affected shader families. Where present, include them in native TAA/FSR2/spatial-AA clips with identical animation and camera motion. Inspect texture trails separately from transform interpolation and AA blur. Keep the existing CPU-controlled visual time; do not switch to TIME or invent a motion-vector API as a workaround. Adopt only on exact-runtime evidence.

## R13 — Version-specific first particle emission

**Question:** Are GPU particle initialization and transparent history safe on the exact engine build?

**Read:** Open/reopened [Godot #122005](https://github.com/godotengine/godot/issues/122005) (updated 2026-09-08) reports a first-emission uniform problem. [Fix #122006](https://github.com/godotengine/godot/pull/122006) merged 2026-08-14, but later discussion identifies a second userdata-mismatch path reproduced in 4.7/4.8-dev. Separately, the older transparent-particle TAA report [#88208](https://github.com/godotengine/godot/issues/88208) was closed 2025-07-16 by [#108664](https://github.com/godotengine/godot/pull/108664). Do not present the closed report as a current known defect, or the partial fix as resolving every path.

**Action / decision:** **Selected when a GPU-particle path is used**, SM/CR with VQ-07b/f. Test first emission after instantiation/re-entry, relevant resource/buffer changes and reset on pinned 4.7.2. Capture renderer errors, first-frame transforms and transparent shimmer under candidate AA. Reuse SM's lifecycle evidence; a failure blocks that candidate, not an automatic engine upgrade or smoke replacement.

## R14 — A reusable LUT stack, with bounded scope

**Question:** Could an existing free compositor supply a missing trailer grading capability?

**Read:** [godot-post-effect-stack](https://github.com/HotSpudLab/godot-post-effect-stack/blob/main/README.md), version 0.2.3 with README updated 2026-10-20, and its [MIT license](https://github.com/HotSpudLab/godot-post-effect-stack/blob/main/LICENSE). The author lists 4.7/4.7.1 checks, LUT grading, Forward+ compositor and CanvasLayer paths, plus MSAA/callback limits. Mobile compute is not claimed to work; related open [Godot #96737](https://github.com/godotengine/godot/issues/96737) originated on 4.3. These are upstream claims, not OpenRC export verification.

**Action / decision:** **Conditional trailer-only trial**, under the existing cinematic workflow if its current tools cannot meet a named grading need. Pin the addon and test 4.7.2 exports, color space, 4× MSAA and the intended renderer path. Keep pilot appearance, exposure ownership and runtime dependencies unchanged unless separately accepted. A new LUT stack is not a VQ-07 prerequisite.

## R15 — Exported macOS startup has its own cache evidence

**Question:** Does a warmed editor hide a slow first launch of the actual Mac package?

**Read:** The [4.7 pipeline-compilation source guide](https://github.com/godotengine/godot-docs/blob/4.7/tutorials/performance/pipeline_compilations.rst) and open [Godot #106757](https://github.com/godotengine/godot/issues/106757) (updated 2026-07-12). The latter describes first-load Metal compilation on 4.4.1/M1/macOS 15.3–15.5 and separate exported-project caching. It is an older, platform-specific report; neither its timings nor reproduction status transfer to the pinned build.

**Action / decision:** **Selected for advertised macOS profiles**, VQ-07c/DT. On a real target Mac, compare the exported package with an isolated empty cache, subsequent fresh-process launches and warm runs; record exact renderer/backend. Preserve existing loading samples and first-effect coverage. Never clear a user's general driver cache for this test. Without target hardware, leave Mac qualification open instead of inferring it from Windows or the editor.

## R16 — Dithered LOD transitions under temporal AA

**Question:** Can a seemingly smooth distance fade produce a moving checkerboard?

**Read:** Open [Godot #94841](https://github.com/godotengine/godot/issues/94841) (updated 2024-07-27) reports TAA artifacts with pixel/object dither fade, tested through 4.3 RC. The official [AA demo README](https://github.com/godotengine/godot-demo-projects/blob/master/3d/antialiasing/README.md) supplies an available comparison example and notes moving-object TAA limitations. This successful repository read supplements the failed direct-demo fetch recorded in the first audit; no demo checkout was run.

**Action / decision:** **Conditional test**, VQ-07d and L/LU/SC, only where existing or candidate LOD uses dithering. Repeat a transition at actual target resolutions and camera speeds under TAA, FSR2 and spatial AA. Reject a fade that introduces checkerboarding or damages aircraft contrast. Reuse a pinned, license-checked official example if a minimal reproduction is needed; keep the project circuit as final evidence. An old open issue alone does not justify banning dither.

## R17 — Separate foliage aliasing from specular shimmer

**Question:** Are disappearing thin edges and sparkling highlights the same problem?

**Read:** Reddit, [“Has anyone solved this kind of temporal stability issue?”](https://www.reddit.com/r/godot/comments/1wlgpij/has_anyone_solved_this_kind_of_temporal_stability/) (2026-09-20). The poster reports leaf/branch flicker under stacked supersampling/MSAA/sharpening, but distinguishes a reflective-surface symptom improved by temporal methods. These are personal observations, not controlled comparisons. Godot's [AA guide](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_antialiasing.html) distinguishes geometry and specular aliasing and temporal tradeoffs.

**Action / decision:** **Selected**, VQ-07d. Label each observed defect by type; compare one AA method at a time with fixed sharpening. Use the same foliage-crossing and rolling-aircraft tape. Record projected aircraft size, silhouette, markings and attitude independently from highlight stability. A smoother image fails if the pilot loses useful attitude cues.

## R18 — Clouds when the flying camera crosses their boundary

**Question:** Does a cloud treatment still look coherent from inside it?

**Read:** Reddit, [“How to make volumetric clouds you can go inside of?”](https://www.reddit.com/r/godot/comments/1hu38uh/how_to_make_volumetric_clouds_you_can_go_inside_of/) (2025-01-05). The author reports that tried cloud shaders lose their illusion on entry; suggested replacements are unvalidated for this project. Godot's [volumetric-fog guide](https://docs.godotengine.org/en/4.7/tutorials/3d/volumetric_fog.html) documents finite range and temporal-reprojection limitations.

**Action / decision:** **Selected test for a cloud candidate; deferred new architecture**, FW-85/VQ-07f. Where the supported camera route can reach the layer, inspect entry, transit and exit, horizon continuity, aircraft contrast, pause and reset. A distant sky layer need not support arbitrary free-flight through it unless that view is in scope. Prototype volumetrics only for an owner-confirmed gap; reject boundary artifacts, unreadable aircraft or excessive cost.

## R19 — Warmup coverage must match actual first use

**Question:** Does a warm run conceal compilation stalls in a new session?

**Read:** Reddit, [“Made a web build of my godot game, shader compilation is a way bigger pain than on desktop”](https://www.reddit.com/r/godot/comments/1wvzhyb/made_a_web_build_of_my_godot_game_shader/) (2026-10-02). The author reports first-visit and effect hitches in a 4.7 Compatibility web build, improved repeat visits and a playthrough-derived warmup. Browser durations do not transfer to desktop OpenRC. The official [pipeline-compilation guide](https://docs.godotengine.org/en/4.7/tutorials/performance/pipeline_compilations.html) supplies renderer-specific behavior.

**Action / decision:** **Selected**, VQ-07c with VQ-01c/d. Separate fresh process from cold driver/import cache, declare each condition, and record first smoke, storm, night and settings use on the actual desktop export. Attribute the stall before extending warmup. A new loading UI or exhaustive precompilation scheme stays conditional on measured benefit and the existing startup budget.

## R20 — Material recognition matters more than extra gloss

**Question:** Does an intentional glossy finish read as the intended material in flight?

**Read:** Reddit, [“Some of my first 3D shaders in action. What do you think?”](https://www.reddit.com/r/godot/comments/1l16ew7/some_of_my_first_3d_shaders_in_action_what_do_you/) (2025-06-02). Viewers describe a tent as plastic; its author likes the glossy appearance in motion. This disagreement is subjective evidence, not a roughness prescription. Godot's [material guide](https://docs.godotengine.org/en/4.7/tutorials/3d/standard_material_3d.html) documents the relevant controls.

**Action / decision:** **Conditional bounded comparison**, VQ-02b and the aircraft owner. If a material fails the baseline review, compare one modest roughness/clearcoat variant under fixed lighting, with stills and a pilot-camera clip. Ask what material reviewers perceive before disclosing the variant. Preserve livery, readable markings and useful highlights; no fleet-wide clearcoat or roughness change follows from a forum opinion.

## R21 — Temporal afterimages during motion and discontinuities

**Question:** Does history accumulation leave a false aircraft or propeller position?

**Read:** Godot Forum, [“Blurriness in animations (3D)”](https://forum.godotengine.org/t/blurriness-in-animations-3d/55008) (2024-04-08; 4.2.1). A user reports animated-object afterimages improving after changing TAA to MSAA. The discussion's motion-vector explanation is not an OpenRC diagnosis. The current [AA guide](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_antialiasing.html) retains temporal blur/ghosting caveats; the old report does not establish a 4.7.2 defect.

**Action / decision:** **Selected history test**, VQ-07d. Inspect rolls, propeller motion, zoom, camera cut, pause/resume, reset and checkpoint restore for trails and disocclusion. Retain native spatial AA when reconstruction damages flight cues. This asks whether temporal history is correct; R01 separately asks whether presentation components consume the same physical pose.

## R22 — LOD must preserve a tree's outer silhouette

**Question:** Do distant trees become skeletal before their detail becomes irrelevant?

**Read:** Godot Forum, [“VR world in Godot”](https://forum.godotengine.org/t/vr-world-in-godot/138560) (2026-05-12; follow-up 2026-05-19). The developer reports outer foliage disappearing with automatic LOD and some 4× MSAA shimmer. Their VR density/hardware figures are not OpenRC measurements. Godot's [3D performance guide](https://docs.godotengine.org/en/4.7/tutorials/performance/optimizing_3d_performance.html) covers LOD, visibility ranges, impostors and fill-rate tradeoffs.

**Action / decision:** **Selected diagnostic; conditional asset change**, L/LU/SC under existing grass/tree plans. Film the circuit through current LOD transition distances, including a fast lateral pass and aircraft crossing the treeline. If silhouette loss is demonstrated, compare one retained or free, license-verified alternative with timing and memory evidence. Preserve runway visibility, collision and population; do not automatically increase all mesh detail.

## R23 — Screen-copy ordering and transparent layers

**Question:** Would a screen-space distortion affect opaque scenery but miss the canopy or smoke?

**Read:** Godot Forum, [“Hint_Screen_Texture doesn't render transparent materials”](https://forum.godotengine.org/t/hint-screen-texture-doesnt-render-transparent-materials/131176) (2026-01-19; reported 4.3). A user sees transparent objects omitted from a screen-wide effect. Godot's [screen-reading shader guide](https://docs.godotengine.org/en/4.7/tutorials/shaders/screen-reading_shaders.html) explains the 3D screen-copy position between opaque and transparent rendering. This is distinct from SSR's previous-frame behavior in R11.

**Action / decision:** **Selected parity check**, VQ-07b with SM/CR/aircraft owners. Inspect water/refraction and any proposed distortion with canopy, smoke, propeller disc and alpha scenery crossing it. Record the pass order and required effect scope. Defer a compositor or additional viewport until a required effect needs it; do not introduce a second scene-rendering architecture just because a discussion suggests one.

## R24 — Use the running scene as the visual reference

**Question:** Can editor preview illumination invalidate a material or renderer comparison?

**Read:** Godot Forum, [“Why does viewport look differently to an in-game scene”](https://forum.godotengine.org/t/why-does-viewport-look-differently-to-an-in-game-scene/141572) (2026-07-13; 4.6.3). A user sees a lit editor scene become dark at runtime. The official [environment guide](https://docs.godotengine.org/en/4.7/tutorials/3d/environment_and_post_processing.html) explains preview sun/environment behavior. This is a capture-method warning, not evidence that OpenRC lacks lights.

**Action / decision:** **Selected**, VQ-07a. Freeze reference images from the running application with explicit camera, exposure, environment, resolution and renderer. Record editor views as authoring aids only. Home and Workshop are useful supplemental views; the pilot scene remains mandatory. Do not “repair” runtime lighting to match an unrecorded editor preview.

## R25 — Separate sky background cost from radiance updates

**Question:** Could existing sky work be made cheaper without reducing aircraft resolution?

**Read:** Godot 4.7 [sky shaders](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/sky_shader.html) and [Sky process modes](https://docs.godotengine.org/en/4.7/classes/class_sky.html). Visible background, radiance updates and lower-resolution subpasses are separate work. Uniform changes can invalidate radiance even without TIME. Incremental and realtime filtering trade latency/quality; realtime filtering has a documented cubemap-size restriction. Local atmosphere code deliberately selects QUALITY for deterministic results, so a blind mode change is inappropriate.

**Action / decision:** **Conditional**, FW-85/VQ-07c/f. First attribute sky and radiance cost. If material, trial either bounded radiance work or a half-resolution cloud subpass in the isolated renderer, one change at a time. Keep aircraft and sharp sky features at full resolution and the CPU-controlled visual clock. Check reflected sky, bright edges, horizon, storm flashes and cuts/restores; declare convergence time. This is a stock sky-shader experiment, not a split aircraft/background viewport architecture. Retain only a repeatable improvement with all visual/lifecycle gates intact.
