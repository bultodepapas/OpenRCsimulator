# Advanced graphics: source audit and planning evidence

2026-10-21 · VQ-07 planning input · Source/documentation review only; no new runtime experiment or hardware qualification.

The resulting [upgrade plan](../../plans/advanced-graphics.md) separates the existing Compatibility delivery from a Forward+ study and conditional High profile. This report preserves dated findings; current implementation and acceptance remain in the owning guides.

The [follow-up ledger contains 25 additional investigations](round-2.md): six documentation studies, three tool/author references, eight GitHub studies, four Reddit threads and four Godot Forum discussions. Each records a question, evidence limit and an OpenRC experiment/disposition. It adds targeted material, LOD, motion-history, shadow/probe, profiling and sky ideas; the [plan's disposition table](../../plans/advanced-graphics.md#9-disposition-of-the-25-follow-up-investigations) maps all 25 to existing owners. No addon was installed or runtime benchmark performed.

## Input and method

The user supplied **OpenRC Simulator — Advanced Graphics and AAA Visual Quality Research**, dated October 20, 2026. The [unaltered supplied brief](supplied-brief.md) is retained as source material, including claims corrected below. It is not accepted implementation evidence. Original attachment SHA-256 at intake:

`635406b2af5adf63ad05b52a1bbe789c7d7098f9cfbb66c2bb50359158f03b90`

Review covered local runtime configuration, representative renderer code, VQ/global plans, ownership, current sky/smoke work, flight logging and measurement contracts. Repository HEAD: `ef91916374cee18b8bc84e736f69b9623e681adf`. The tree already contained trailer work and a documentation-index edit; these were preserved. This is not a clean-build attestation.

Code discovery used the existing codebase-memory index. Its atmosphere snippet ranges were stale, so current file contents were inspected before drawing conclusions. External checks used Godot's versioned 4.7 documentation, official vendor repositories/manuals and asset-provider license pages. Context7's 4.7 documentation was a discovery aid; primary links below are the retained references. Moving upstream pages must be rechecked and exact versions/commits pinned at implementation intake.

## Local findings

| Observed source | Finding | Planning consequence |
| --- | --- | --- |
| [project.godot](../../../app/project.godot), [get-godot.sh](../../../app/get-godot.sh) | 4.7.2-stable pin; Compatibility; 720p base; 4× MSAA; 240 Hz with at most 12 catch-up steps per frame | Compare renderers on the same official engine. Graphical overload can still cause wall-time slowdown even when numerical laws are unchanged. |
| [VQ guide](../../VISUAL-QUALITY-PLAN.md), [global plan](../../plans/global-performance-visual-quality.md) | VQ-07 is open and outside the current Compatibility delivery. Materials, baseline/visibility and settings already have owners. | Expand VQ-07, preserve existing step status and sequence. Do not reopen every deferred idea as a prerequisite. |
| [sky shader](../../../app/render/sky.gdshader) | Explicit inverse encoding for the GLES3 sky colour conversion; deterministic CPU-supplied cloud time | Forward+ needs colour/radiance parity checks, not an assumption that every shader is portable. |
| [atmosphere](../../../app/render/atmosphere.gd), [exposure](../../../app/render/world/exposure.gd) | Environment creation, fog/ambient colours, tonemapper choice, reflected-light policy and global exposure are coordinated; glow is initially disabled | Preserve existing scene-local update and night adaptation. Do not replace WorldEnvironment or add competing exposure logic wholesale. |
| [water shader](../../../app/render/lake/water.gdshader) | `view_depth_at()` explicitly maps sampled depth to OpenGL NDC Z; water uses screen/depth textures | Test/adapt depth reconstruction, shore and refraction before judging Forward+ water. This is a specific migration risk, not a demonstrated current Compatibility defect. |
| [ground](../../../app/render/ground.gdshader), [bank](../../../app/render/lake/bank.gdshader) | Some colour handling already branches on `OUTPUT_IS_SRGB` | Inventory renderer assumptions by shader family; avoid blanket gamma changes. |
| [sky plan](../../plans/sky-clouds-weather.md), [smoke overhaul](../../../SMOKE_SYSTEM_MASTER_PLAN.md) | Sky profiles, storm presentation and a bounded smoke overhaul already exist with qualification work remaining; FW-85 owns backend exploration | Reuse their state, assets and tests. A GPU-trail experiment is not authorization for another smoke system. |
| [STACK](../../STACK.md), [ROADMAP](../../../ROADMAP.md) | Desktop exports exist; web/mobile delivery and broad hardware/pilot acceptance do not | Preserve Compatibility but distinguish engine capability from shipped platform support. |

These observations identify test targets. They do not establish that Forward+ is faster, that current materials are defective, or that a visual technique will improve flight.

## Godot findings that change the plan

**Renderer capability is not a quality score.** Godot 4.7 documents Forward+ on RenderingDevice and Compatibility on OpenGL. The feature table includes Compatibility glow, SSAO and reflection probes; it reserves directional PCSS, SSIL/SDFGI/VoxelGI, SSR, volumetric fog and temporal reconstruction for Forward+. Decals, native particle trails and compositor effects also work in Mobile. Thus neither “all post-processing requires Forward+” nor “every modern effect is Forward+-exclusive” is accurate. Verify the exact built binary before relying on a documented feature. [Renderer comparison](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html)

**Colour and depth portability are first-order risks here.** Godot documents distinct NDC reconstruction between Compatibility and RenderingDevice, plus renderer conditionals. Combined with the local water/sky findings, this makes parity a separate phase before artistic tuning. [Depth and post-processing](https://docs.godotengine.org/en/4.7/tutorials/shaders/advanced_postprocessing.html), [spatial shader built-ins](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html)

**Temporal AA is a tradeoff for small aircraft.** FSR2.2 is built in; native-resolution use adds cost. SMAA 1x is a useful additional spatial candidate in 4.7. Motion blur/ghosting and distant markings require moving tests. FSR2 supplies temporal AA itself; the separate TAA setting is ignored when it is selected. [AA methods](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_antialiasing.html), [resolution scaling](https://docs.godotengine.org/en/4.7/tutorials/3d/resolution_scaling.html)

**First-use stutter deserves its own comparison.** Forward+/Mobile support pipeline precompilation and ubershaders; Compatibility requires the legacy visible warmup approach. Runtime-created meshes/materials and changing render settings can still trigger compilation. Measure the first aircraft, smoke, storm and night pass as well as warmed steady flight. An existing shader cache does not establish first-run behavior. [Pipeline compilation guidance](https://docs.godotengine.org/en/4.7/tutorials/performance/pipeline_compilations.html)

**Materials and transparency should precede extra effects.** Standard/ORM materials already provide the needed base surface controls. Alpha blending has sorting/cost restrictions; adding SSR does not automatically solve canopy or smoke reflection. Keep realistic texture scale and channel conventions, then inspect actual application materials. [Material documentation](https://docs.godotengine.org/en/4.7/tutorials/3d/standard_material_3d.html) **Follow-up correction:** the earlier blanket statement that alpha objects are omitted from SSR is insufficient after the 4.6 prior-frame-color overhaul. Upstream reports show both missing reflections and unwanted alpha inclusion depending on depth/history; test both on 4.7.2. [R11 and upstream links](round-2.md#r11--lake-reflections-and-the-changed-ssr-path)

**Vegetation cost is not just triangle count.** Godot distinguishes automatic instancing, manual MultiMesh, LOD and transparency fill cost. For this project, the inference is to profile overdraw and batching in its existing foliage before adopting a replacement. Open RC fields also provide fewer occlusion opportunities than enclosed levels; an occlusion system needs an actual measured workload. [3D performance guide](https://docs.godotengine.org/en/4.7/tutorials/performance/optimizing_3d_performance.html)

**GI and volumetric effects need a specific scene.** Dynamic/baked GI solve different lighting requirements. Existing variable time of day limits the usefulness of fixed baked sunlight. Volumetric fog is a Forward+ feature with spatial-resolution and temporal-reprojection tradeoffs; fast lights and moving aircraft need inspection. Our prioritization of shadows/probes before full GI is a project-specific judgment, not a measured Godot comparison. [GI overview](https://docs.godotengine.org/en/4.7/tutorials/3d/global_illumination/introduction_to_global_illumination.html), [volumetric fog](https://docs.godotengine.org/en/4.7/tutorials/3d/volumetric_fog.html)

**Particle features do not define effect semantics.** Godot's ribbon/tube particle trails require Forward+ or Mobile. Use them only if they improve the existing SM/CR presentation with bounded cost and compatible lifecycle behavior. [Particle trails](https://docs.godotengine.org/en/4.7/tutorials/3d/particles/trails.html)

## Vendor claims and corrections

| Supplied claim/topic | Verified finding, 2026-10-21 | Disposition |
| --- | --- | --- |
| Native FSR2.2 | Godot's [4.7 AA documentation](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_antialiasing.html) confirms Forward+ support on suitable recent GPUs across vendors. | First native reconstruction experiment; no external SDK required for this trial. |
| New AMD SDK versus older Vulkan path | [AMD FSR SDK 2.3.0 repository](https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK) lists Vulkan unsupported in its known issues despite broad introductory wording. The [current SDK page](https://gpuopen.com/amd-fsr-sdk/) lists DX12/UE5. The older [FSR3.1 interpolation manual](https://gpuopen.com/manuals/fidelityfx_sdk/techniques/super-resolution-interpolation/) describes Vulkan implementation. | The brief's version caveat is justified. Distinguish SDK, component version, API and sample; do not transfer support between generations. |
| AFMF 2.1 for the OpenGL application | [AMD's AFMF page](https://www.amd.com/en/products/software/adrenalin/afmf.html) includes OpenGL and Vulkan, with specific Radeon/Ryzen, driver and display-mode requirements. | Optional compatible-host driver experiment; not native OpenRC functionality or cross-vendor support. |
| Streamline DLSS-G requires DX12 | **Overbroad/outdated.** The [current DLSS-G programming guide](https://github.com/NVIDIA-RTX/Streamline/blob/main/docs/ProgrammingGuideDLSS_G.md) exposes D3D12 and Vulkan support and documents Vulkan presentation integration. Dynamic Multi Frame Generation and VSync with FG retain D3D12-only restrictions in that guide. | Check exact feature/runtime capability, rather than rejecting all Vulkan or claiming all Vulkan modes work. Integration in OpenRC is unproven. |
| Streamline openness | The [repository](https://github.com/NVIDIA-RTX/Streamline) identifies version 2.14.16 and states that `sl.dlss_g.dll` cannot be built from source. | Review component redistribution and binary requirements independently of the framework license; not a fully source-buildable dependency assumption. |
| NVIDIA Godot path tracing | [NVIDIA's `nvidia-pt-dlss` branch](https://github.com/NVIDIA-RTX/godot/tree/nvidia-pt-dlss) is a separate fork. [RTXPT](https://github.com/NVIDIA-RTX/RTXPT) is an integration/reference project. | Neither proves compatibility with this 4.7.2 pin, portable exports or production maintenance. Start with a disposable vendor sample. |
| DLSS 5 announced September 2026 | **Incorrect announcement date.** NVIDIA's [initial announcement](https://www.nvidia.com/en-us/geforce/news/dlss5-breakthrough-in-visual-fidelity-for-games/) is March 16, 2026. Its [September 3 launch article](https://www.nvidia.com/en-us/geforce/news/dlss-5-3d-guided-neural-rendering/) concerns NBA 2K27; the [September developer article](https://developer.nvidia.com/blog/whats-new-for-game-developers-dlss-5-with-3d-guided-neural-rendering-nvidia-ace-updates-and-new-rtx-kit-capabilities) is a later update. | A shipped integration elsewhere does not establish a general Godot plugin or OpenRC availability. Keep outside committed delivery. |

Frame generation adds presented images, not authoritative physics updates or fresh player inputs. Its actual latency depends on the integration and presentation path. The plan therefore requires separate real/displayed-frame metrics and input-to-photon measurements, rather than assuming either an improvement or a fixed latency penalty. Vendor feature support remains distinct from tested support in the simulator.

## Free resources and reuse decisions

| Source | Verified basis | Proposed use / limitation |
| --- | --- | --- |
| [Poly Haven license](https://polyhaven.com/license) | HDRIs, textures and models are CC0; redistribution permitted | First external material/HDRI reference source after retained assets. Preserve source provenance; asset rights do not imply unrestricted website scraping. |
| [ambientCG license](https://docs.ambientcg.com/license/) | Downloadable assets and material preview renders are CC0 | Ground/building/material candidates. Choose by actual scale and available channels, not maximum resolution. |
| [Godot AA demo linked by official documentation](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_antialiasing.html) | Official tutorial supplies a reusable demo link | Start from a pinned version-compatible example where useful. The initial direct fetch failed; the [follow-up read the repository README successfully](round-2.md#r16--dithered-lod-transitions-under-temporal-aa). No checkout or execution was verified. |
| [Terrain3D upstream](https://github.com/TokisanGames/Terrain3D) | Downloadable terrain system, MIT license listed upstream | Reference only. No demonstrated terrain-authoring/performance need here justifies replacing the current field/contact contract. Binary/version/platform qualification would be a separate LU decision. |

No new art, plugin, SDK or engine was downloaded or installed by this review. No free-library catalog is a pre-approved asset list. Intake must retain the exact file/license/hash and use existing generators for transformed runtime output.

## Recommendation and remaining unknowns

The highest-confidence next work is a reproducible source/visibility baseline, evidence-led improvements to retained content, then a bare Forward+ parity/cost study. New findings added to the supplied brief are concrete sky/water portability risks, first-use pipeline behavior, a spatial SMAA comparison, transparency limitations, and a corrected vendor capability/date record.

Unknowns remain: target-host Forward+ overhead, which AA method best preserves distant attitude, first-use stalls after adaptation, combined effect headroom, cross-platform fallback behavior and owner preference in flight. Native paired experiments must answer these. The research does not justify a renderer migration, a new minimum GPU, physical-realism claims or an Ultra preset.
