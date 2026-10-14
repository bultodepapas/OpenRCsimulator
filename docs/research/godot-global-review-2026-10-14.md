# Godot global performance and visual review

2026-10-14 · Research snapshot · Base commit `cb2c5b229a579bfaeae80faae5b5ac7b55badc21`.

Purpose: support the [cross-track improvement plan](../plans/global-performance-visual-quality.md). This review inspected current configuration/source, existing measurements and native images, official Godot 4.7 documentation, upstream repositories, Godot Forum and Reddit. It did not run a new benchmark, fly the simulator, install an addon or change runtime code. Measurements below belong to the linked historical snapshots, not automatically to this commit.

## 1. Method and confidence

- **Observed source:** current files read after graph discovery. The existing codebase-memory index was refreshed, but some symbol ranges still returned unrelated lines; direct source reads resolved those gaps. Graph complexity/recursion flags were not treated as runtime profiles.
- **Recorded measurement:** a result with a workload, hardware and source record in the repository. Scope and sample size matter.
- **Documented capability:** an upstream 4.7 API/feature statement. It does not prove that this application's shaders work unchanged.
- **Hypothesis:** an optimization or visual preference requiring a paired experiment.
- **Community observation:** a first-person report from a different project. It supplies a reproduction idea, never a performance forecast.

The official [4.7.2 announcement](https://godotengine.org/article/maintenance-release-godot-4-7-2/) identifies the August 18, 2026 release and commit `ed1daf0bf`, consistent with the repository's pinned build. No engine upgrade is proposed by this review. Documentation URLs use `/en/4.7/`; third-party repository heads remain mutable and need an exact revision before any adoption.

## 2. What the repository actually has

| Observation | Evidence | Consequence |
| --- | --- | --- |
| Compatibility/OpenGL; 1280×720 default; 4× MSAA; 240 Hz; 12 catch-up ticks; two reflection-atlas slots | [project.godot](../../app/project.godot), [engine pin](../../app/get-godot.sh), [STACK](../../STACK.md) | Preserve a known baseline. Two slots and MSAA are implemented, not new recommendations. |
| Custom float64 flight state, RK4, strict aircraft validation, deterministic checkpoints and render-boundary conversion | [Simulation](../../app/sim/simulation.gd), [Frames](../../app/render/frames.gd), [contract](../../AIRCRAFT_CONTRACT.md) | A physics-engine swap, float32 conversion or reduced tick rate would change the product's core guarantees. |
| Shared field/world construction, simulated visual clocks, evolving lighting and scene-context restoration | [World](../../app/render/world/world.gd), [Atmosphere](../../app/render/atmosphere.gd) | Loading and caching must preserve scene ownership, time, exposure and invalidation. |
| Spatial batching, imported LOD, downloaded population/plants, hedge impostors and a bounded reflective lake | [LU-21](landscape-upgrade/LU-21/README.md), [LU-22](landscape-upgrade/LU-22/README.md) | Do not plan to introduce these from scratch or use obsolete procedural-tree captures as the current baseline. |
| Ground already uses detiling, macro variation, explicit texture gradients, anisotropic mip sampling and filtered mowing stripes | [ground shader](../../app/render/ground.gdshader), [grass sampling](../../app/render/grass_surface.gdshaderinc), [turf detail](../../app/render/turf_detail.gdshaderinc) | Remaining work is visual tuning and attribution of cost, not a generic “add mipmaps/noise” patch. |
| Turf detail is packed linear data, currently lossless with mipmaps; grass albedo carries `source_color` | [detail import](../../app/assets/landscape/turf/detail.png.import), shader includes above | Compression and color-space changes need channel-aware checks. Applying sRGB conversion to packed slopes would be wrong. |
| Projected field/aircraft shadows and RPM-driven propeller blur are delivered | [VQ guide](../VISUAL-QUALITY-PLAN.md), [field projectors](../../app/render/field_projected_shadows.gd), [shadow](../../app/render/shadow.gd) | Compare an alternative only against the existing result and include all viewport costs. |
| Main interpolates presentation, samples diagnostics and updates HUD; ordinary flight and screenshot paths are distinct | [Main](../../app/main.gd) | Render-loop allocation/HUD frequency is only a profile candidate. A capture-only result cannot stand in for interactive flight. |
| Desktop exports exist; native platform, display and hardware acceptance remain open | [desktop plan](../DESKTOP-DELIVERY-PLAN.md), [tools](../TOOLS.md) | Export success, Linux headless success and native GPU qualification are different evidence. |

The comment in `project.godot` saying the application imports no textures is stale: runtime textures and import files now exist. A later configuration-documentation edit should correct that comment without changing the ETC2/ASTC export setting on assumption.

## 3. Measurements that change the priority

| Recorded result | Exact scope / limitation | Planning implication |
| --- | --- | --- |
| H15 P-51 trim median 444–476 µs/tick; batch p95 522–536 µs. Stall median 457–461 µs | [H15](simulation-state/H15/README.md), 2026-10-07; four-aircraft fixtures, 16×120-tick batches, development target with a capture renderer active | GDScript optimization already delivered substantial gains. Gate P is still open, and the expanded current fleet/world needs a new qualification. |
| Earlier H4/H5 P-51 stall median 878–898 µs | [H4/H5](simulation-state/H4-H5/README.md) predates H12–H15 optimization stages | These figures are optimization history, **not evidence of a regression from H15**. Do not mix source revisions. |
| Near-car/tree first-hit p95 297/289 µs at 240 Hz after broadphase reuse | [LU-10 report](landscape-upgrade/LU-07/collision-performance.md); 3,867 proxies, native paired calls | The 100 µs nearby-query objective was missed. Hoisting the broadphase is already implemented. |
| Later LU-21 near-car/tree p95 335/321 µs | [LU-21](landscape-upgrade/LU-21/README.md); 3,877-proxy world | Different content means a different baseline. Preserve world identity in comparisons. |
| LU-22 lake-off/on airborne wall p95 847/1,297 µs; paired median increment 330 µs; states identical | [LU-22](landscape-upgrade/LU-22/README.md), 4,980 proxies/1,038 bins, four warmup ticks and 20 measured precontact steps 10 m above water | A high-value CPU investigation. This small evolving-session sample is neither pure GPU timing nor a worst-case water-contact qualification. |
| LU-22 final four 1080p views: maximum frame p95 4.69 ms; reported video memory 323.09 MiB | RTX 3090, Windows/OpenGL, 600 frames/view; scene-render loop, shared workstation | Useful evidence of that scene on that GPU; no minimum-GPU or whole-flight claim. |
| Reflection atlas reduction lowered reported memory from 567.26 to 323.09 MiB; final lake-on/off difference 17.32 MiB | Same [LU-22 report](landscape-upgrade/LU-22/README.md) | The large atlas reservation fix is done. Future work concerns refresh cost/content, not repeating it. |
| Cold complete field construction 4.694 s; focused scenery build 534 ms; warm scenery 166–179 ms | LU-22; different build scopes | Split import, resource loading, procedural construction and first draw before choosing threading or caching. |
| Complete field source geometry 624,109 triangles against a revised 650k ceiling | LU-22, before distance LOD | The old LU-21 600k figure is not the current cap. Source triangles differ from visible primitives and draw calls. |

H4/H5's nearest-rank p95 over 16 batch averages equals its maximum batch average. It is not a per-tick p95. New reports should retain the old metric for comparison and add individually sampled whole-session ticks, with observer overhead characterized separately.

Existing integration reports also disclose incomplete Linux suites, timeouts and isolated-copy verification. Preserve those qualifications; this review does not declare them fixed or assert that they still reproduce on today's commit. A coherent current baseline comes first.

## 4. Visual inspection

Inspected unedited LU-21 day/night images, then the newer LU-22 [club](landscape-upgrade/LU-22/native/postcard_club.png) and [lake overview](landscape-upgrade/LU-22/native/lake_overview.png). LU-22 supersedes the old near-tree shapes. These are recorded stills, not new captures.

The latest images suggest three art-review candidates: broad ground color/texture frequency still dominates a large fraction of the image; the distant horizon has strong horizontal bands; the lake's shallow/deep transition and polygonal bank are conspicuous from above. These are visual judgments, not measured defects. Test them from pilot height and in motion before changing the art. The stylized downloaded vegetation is an intentional current choice, not a missing system.

The [LU-21 night threshold](landscape-upgrade/LU-21/evidence/final-after-night/runway_threshold.png) is very dark outside lit areas. It contains no flying subject that could establish aircraft readability. Increasing exposure globally could destroy lamps, sky and aircraft lights; use FW's existing night-flight acceptance work.

An older [Grass001 trial](visual-quality-material-trial-2026-10-06.md) already retained licensed 1K albedo/NormalGL/roughness files. It used runtime `ImageTexture` creation in a tiny llvmpipe scene, bypassing Godot's texture importer. It proves neither current field improvement nor the desired import/compression settings. Reuse the source and provenance for an in-field A/B before creating or downloading another tile.

## 5. Godot 4.7 source findings

Each source was consulted on 2026-10-14. The “application” column is this review's proposed use, not an upstream performance promise.

| Source | Supported finding and application |
| --- | --- |
| [Renderer matrix](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html) | Compatibility supports MSAA, glow and SSAO. It lacks TAA/FSR2, compute, volumetric fog, SDFGI, decals and HDR output. Use the matrix when defining presets; reject advice inherited blindly from older releases. |
| [HDR output announcement](https://godotengine.org/article/hdr-output-arrives-in-godot-4-7/) | 4.7 HDR output applies to Forward+/Mobile. An HDR-capable monitor does not upgrade this Compatibility application's output automatically. |
| [Debugger / visual profiler](https://docs.godotengine.org/en/4.7/tutorials/scripting/debug/debugger_panel.html) | Visual profiling measures rendering tasks, not all script/physics CPU work. It supports Compatibility except on macOS. Keep unsupported GPU measurements explicitly unavailable. |
| [RenderingServer timing API](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html) | Enable viewport timing before reading it; include every drawn viewport and CPU frame setup. Cross-check totals and avoid mistaking a disabled zero counter for a free pass. |
| [GPU optimization](https://docs.godotengine.org/en/4.7/tutorials/performance/gpu_optimization.html) | Driver submission, pixel work and geometry can bottleneck separately; material reuse and spatially local batches matter. Attribute before flattening meshes or lowering fidelity. |
| [3D optimization](https://docs.godotengine.org/en/4.7/tutorials/performance/optimizing_3d_performance.html) | Automatic mesh instancing is Forward+-only; transparent rendering constrains sorting; mesh LOD and visibility ranges solve different costs. Compatibility's existing manual batching remains relevant. |
| [MultiMesh class](https://docs.godotengine.org/en/4.7/classes/class_multimesh.html) | Instances form one culling object and share its per-object light limit. Tune spatial chunks, conservative animation bounds and light coverage together; a single global MultiMesh is not a universal optimization. |
| [Occlusion culling](https://docs.godotengine.org/en/4.7/tutorials/3d/occlusion_culling.html) | CPU occlusion has overhead and benefits depend on actual occluders. Test club buildings locally; an open aerial view may gain nothing. Do not add walls to a flying field just to improve culling. |
| [Antialiasing](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_antialiasing.html) | MSAA treats geometry edges, not general shader/specular aliasing. Alpha-to-coverage and import-time normal-guided roughness limiting are separate tools. Compare aircraft visibility in motion; TAA's ghosting matters for small fast subjects. |
| [Image importing](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html) | Lossy disk compression does not imply smaller VRAM. VRAM compression can help but high-quality BPTC/ASTC mode is ignored by Compatibility. Filters live on materials/sampler hints. Classify maps before changing presets. |
| [Shader language](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/shading_language.html) | Color samplers and linear data samplers need different treatment. Preserve `source_color` for albedo; do not apply it to packed slopes, roughness or masks. |
| [Pipeline compilation](https://docs.godotengine.org/en/4.7/tutorials/performance/pipeline_compilations.html) | The ubershader/precompilation workflow covers Forward+/Mobile, not Compatibility. Measure first visible use in OpenGL; consider bounded visible warmup only when it addresses a reproduced hitch. |
| [Background loading](https://docs.godotengine.org/en/4.7/tutorials/io/background_loading.html) | A threaded request still blocks if its result is retrieved too early. Poll completion and distinguish loading from scene instantiation. |
| [Thread-safe APIs](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html) | Active SceneTree access is not thread-safe; GPU resource operations can synchronize. Stage pure data work separately and attach scene nodes on the main thread. |

The repository's [earlier native-rendering study](visual-quality-round2/01-native-rendering-tricks.md) already discusses material sharing, deformation bounds, warmup, depth reconstruction and screen-texture limitations. Carry its qualified results forward. In particular, [water.gdshader](../../app/render/lake/water.gdshader) explicitly reconstructs OpenGL depth and writes `ALPHA`; neither line is automatically a bug, but both require a dedicated renderer-switch test.

## 6. Repositories and free resources

| Upstream / license evidence | Proposed disposition | Integration condition |
| --- | --- | --- |
| [Godot demo projects](https://github.com/godotengine/godot-demo-projects), MIT repository | Reuse a version-matched rendering/AA example when it answers a specific test | Pin the revision, check individual asset notices and the demo renderer. A demo is not a production-world benchmark. |
| [ambientCG Grass001](https://ambientcg.com/view?id=Grass001), [CC0 terms](https://docs.ambientcg.com/license/) | First material comparison uses the already-retained maps | Preserve source scale, normal orientation and provenance. Prefer 1K/2K until screen coverage justifies larger maps. |
| [Poly Haven](https://polyhaven.com/license), CC0 downloadable assets | Shortlist ground/wood/metal/roof maps for an identified visible need | Select individual assets; normalize material scale and palette. A static HDRI is a look-development reference, not a replacement for deterministic solar/weather behavior. |
| [Kenney Particle Pack](https://kenney.nl/assets/particle-pack), CC0 | Reuse existing bundled masks or an appropriate free derivative for effects | Preserve per-file provenance, transparent-edge quality and bounded particle count. No new custom mask authoring before this check. |
| [ProtonScatter](https://github.com/HungryProton/scatter), MIT addon; GitHub mirrors Codeberg | Conditional offline placement-authoring trial | Export stable placement data into the existing pipeline. Its demo textures have separate Textures.com restrictions; addon MIT is not a blanket asset license. |
| [Terrain3D](https://github.com/TokisanGames/Terrain3D), MIT C++ GDExtension | Candidate only for L12/L13 terrain authoring, after profiling/quality work | Prove the exact selected release on 4.7.2 and each export. Share height/normal queries with float64 ground physics; do not replace the current field just to obtain PBR maps. |
| [HTerrain](https://github.com/Zylann/godot_heightmap_plugin) | Alternate terrain spike, not a second simultaneous adoption | README targets Godot 4.6+ and declares maintenance/bug-fix focus. Test renderer/version behavior and inspect its license/files before selecting it. |

No addon was installed and no new asset downloaded in this review. Existing Quaternius/Aredon assets and provenance in [LU-22](landscape-upgrade/LU-22/README.md) take precedence over shopping for a replacement library. Procedural adaptation remains useful for packing, placement and project-specific physics contracts; it is not a reason to recreate freely downloadable content.

## 7. Forums and Reddit: useful questions, bounded evidence

| Firsthand thread | What it contributes | What it cannot establish here |
| --- | --- | --- |
| [Godot Forum: MultiMesh vs RenderingServer instances](https://forum.godotengine.org/t/multimesh-vs-renderingserver-meshinstances-for-an-extremely-high-number-of-instances/143319/5) | User-reported differences between editor/tool and runtime behavior motivate profiling the exported application and chunking experiments. | A universal FPS gain, optimum cell size or benefit for this already-batched field. |
| [Godot Forum: Forward+ stutter](https://forum.godotengine.org/t/stutter-fps-lag-when-using-forward-instead-of-compatibility/50389) | Renderer switches can change pacing as well as image quality. Include first-use and steady-state traces. | A Godot 4.7.2 defect or proof that either renderer is always faster. |
| [Reddit: Compatibility web shader compilation](https://www.reddit.com/r/godot/comments/1wvzhyb/made_a_web_build_of_my_godot_game_shader/) | Developer describes a much slower first browser visit than cached revisits. Add cold/warm distinction to desktop tests. | Desktop timing, the cause of LU-22 construction time, or justification for a web release. |
| [Reddit: MultiMesh fade discussion](https://www.reddit.com/r/godot/comments/1k5npkm/whats_the_best_way_to_smoothly_fade_out_multimesh/) | Multiple practitioners discuss chunking, fades and geometry shrink alternatives. Compare vegetation transitions in motion. | Correct renderer support, acceptable overdraw or readiness of a linked engine pull request. Validate against the official API and pinned engine. |

No forum snippet was copied into the application. Conflicting community advice was resolved with versioned primary documentation and the repository's own evidence, not vote counts.

## 8. Unresolved facts

The minimum supported GPU/driver and sustained frame target are not frozen; DT must own them. Today's complete suite, whole-session cost across the expanded fleet, cold exported launch distribution, measured input-to-photon latency and human night-flight readability were not established by this research. They are the first execution gates in the plan, not missing claims to fill with estimates.
