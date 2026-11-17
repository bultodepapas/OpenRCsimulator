# Shadow technology review and adoption decisions

Research date: 17 November 2026. Repository baseline and evidence scope are in the [audit overview](README.md). Engine-specific claims below use the inspected **4.8-beta2** revision `cafc17a192acf67903910a68aeb3c076c0907a4b`; current vendor pages are dated research, not a claim that their SDKs execute in OpenRC. No vendor benchmark is transferred into a simulator performance estimate.

**Recommendation:** repair coverage, ownership, materials, invalidation and measurement first. Tune the existing native maps at fixed lighting before adopting a new renderer technique. A better filter cannot restore geometry omitted from its caster input, and a larger atlas cannot give a planar receiver aircraft self-shadowing.

## Raster techniques and the current engine

| Technique | What it contributes | Decision for this baseline |
| --- | --- | --- |
| Cascaded shadow maps (CSM/PSSM) | Allocates directional depth detail across camera-distance regions | First production route for self-shadow and nonplanar receivers. Compare range, cascade distribution, bias and caster coverage before resolution. |
| Percentage-closer filtering (PCF) | Filters binary depth comparisons to soften sampled edges | Retain as the Standard reference. Diagnose lost struts/gear separately from jaggedness. |
| Percentage-closer soft shadows (PCSS) | Estimates blockers and penumbra width before filtering | Already configured by active High graphics under its default/Soft policy. Qualify contact versus height, low-sun noise and cost; do not present it as an unimplemented NVIDIA upgrade. |
| Current planar projection | Cheap, deliberately simplified height/location cue on a flat receiver | Keep only with explicit capability/ownership. Its height-based 13-tap blur is not PCSS: it has no blocker search. |
| Screen-space contact shadows | Adds short visible-surface occlusion from available depth | Conditional experiment after native map tuning; cannot recover unavailable offscreen geometry. Preserve default-off after the prior rejected visual gate. |
| SSAO / CACAO | Estimates ambient occlusion around nearby geometry | Separate ambient grounding control. It cannot replace the directional visibility term or correct a missing wing shadow. |

CSM distributes a limited shadow-map budget; extending distance usually reduces local sampling density unless allocation changes. The useful experiment for an RC aircraft is the same camera, FOV, scale and pose over a range/cascade sweep, including a distant aircraft and landing contact. Microsoft's [CSM reference](https://learn.microsoft.com/en-us/windows/win32/dxtecharts/cascaded-shadow-maps) explains the allocation and transition problem. It does not establish Godot's exact stabilization implementation or a universally optimal split.

NVIDIA's [original PCSS description](https://developer.download.nvidia.com/shaderlibrary/docs/shadow_PCSS.pdf) separates blocker search, penumbra estimation and filtering. It is a rendering algorithm, not an RTX hardware requirement. In the pinned Godot [Light3D API](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/Light3D.xml#L57-L60), directional PCSS is **Forward+ only**. Positional PCSS supports Forward+ and Mobile, not Compatibility (`:97–100`). The default project routes Compatibility generally and Mobile on ARM64; inspect the actual engine/package route before promising identical softness on a Mac or PC.

The same pinned API describes the bias tradeoff: too little produces self-intersection artifacts; too much detaches contact. Inspect actual per-light bias and the aircraft's thin surfaces rather than increasing a global value until acne disappears. Check wheel contact, wing roots, struts, thin sheet geometry, reverse/double-sided casting, low sun and cascade transitions. Make an exact native-depth/normal/caster diagnosis before deciding that an emissive or blended surface is a bias defect.

### Material participation is a prerequisite

The pinned [BaseMaterial3D API](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/BaseMaterial3D.xml#L591-L608) states that ordinary alpha blending disables casting, while scissor/hash support it; unshaded surfaces do not receive lighting/shadows. That distinction matters for custom body alpha and canopy materials. Scissor/hash must be tested with the actual alpha texture, mip coverage, two-sided policy and wind/deformation. Do not replace a canopy's visual transparency with an opaque material merely to make a dark patch appear.

The repository's prior [contact-shadow experiment](../../research/engine-upgrade/GDU-11/implementation.md#gdu-11g--high-contact-shadow-experiment) retained wall-banding failures and rejected default adoption. That earlier beta1 result is evidence against automatic promotion of that configuration, not proof that every beta2 contact implementation fails. AMD's [CACAO](https://gpuopen.com/fidelityfx-cacao/) is a screen-space ambient-occlusion implementation; an engine integration would still require view/depth/normal compatibility and controlled composition with existing SSAO/material AO. Neither technology should be used to hide a missing direct-shadow route.

### Allocation arithmetic, not measured VRAM

For a single tightly packed depth surface, `width × height × bytes_per_texel` yields:

| Square atlas | Nominal 16-bit payload | Nominal 32-bit payload |
| --- | --- | --- |
| 2048² | 8 MiB | 16 MiB |
| 4096² | 32 MiB | 64 MiB |
| 8192² | 128 MiB | 256 MiB |

Doubling each dimension quadruples this payload. Thus **High shadow quality → Ultra shadow quality** can quadruple nominal depth payload even before filter cost changes; the active High **graphics profile** already starts at 8192². Actual engine formats, driver allocation, alignment, retained/reallocated resources and additional views determine residency. These figures exclude field/aircraft masks, MSAA, depth attachments, cloud caches, reflection captures and RT history. They are not measured memory usage, and Off does not imply that an existing allocation was freed. SA-11/22/25 require actual native evidence.

### Alternative raster research

| Candidate | Benefit and failure mode | Disposition |
| --- | --- | --- |
| Variance shadow maps (VSM) | Filterable depth moments; variance bounds can leak light | Research only if a demonstrated filter/coverage case warrants new engine work. See [GPU Gems 3](https://developer.nvidia.com/gpugems/gpugems3/part-ii-light-and-shadows/chapter-8-summed-area-variance-shadow-maps). |
| Exponential variance (EVSM) | Computes moments of exponentially warped depth distributions to reduce leakage; precision, range and filtering still need control | Conditional comparison. The [author's thesis](https://uwspace.uwaterloo.ca/items/57f02644-02bf-41bf-86e9-8a8dd2858f22) is the primary reference; this is not an already integrated feature. |
| Moment shadow maps (MSM) | Four-moment representation improves reconstruction at higher storage/processing complexity | [Original research](https://www.momentsingraphics.de/I3D2015.html) describes a 64-bit representation; one 8192² payload is nominally 512 MiB before ancillary resources. Require a smaller bounded case first. |
| Virtual shadow maps | Paged high-detail maps and cache reuse instead of one uniform allocation | Unreal's [implementation](https://dev.epicgames.com/documentation/en-us/unreal-engine/virtual-shadow-maps-in-unreal-engine) has page/cache/invalidating-geometry contracts. This is distinct from **variance** VSM and is not a Godot switch. Flight, moving foliage, controls and lights can invalidate cached work. |
| Static or reduced native caster meshes | Reduces submitted geometry where visible occlusion remains equivalent | More proportionate early experiment. The existing aircraft proxy is qualified only for a narrow **projected mask** context; reuse its validation approach, while testing a native proxy's own shadow pass, pose, alpha and coverage. |

These approaches have engineering and maintenance costs beyond their image examples. None repairs the fixed receiver, stale hinge snapshot, setting mismatch or omitted vehicle route by itself. Do not replace an established engine path without a counterexample it fails and a candidate that passes it.

## NVIDIA technologies

| Technology | Actual role | OpenRC disposition |
| --- | --- | --- |
| RTX ray queries / traced sun visibility | Tests surface-to-light occlusion against an acceleration structure | Potential bounded self-shadow/near-detail prototype after raster diagnosis; actual caster/material/motion support is the main dependency. |
| NRD SIGMA | Denoises per-light shadow signals, including supported translucency inputs | Relevant optional denoiser once valid traced visibility and guides exist. It does not generate missing geometry or rays. |
| RTXDI / ReSTIR | Samples and reuses lighting distributions; current framework includes direct and path-traced indirect work | Larger lighting architecture, disproportionate as the first answer to one sun and a few selected landing lights. |
| DLSS Super Resolution / DLAA | Reconstructs or antialiases the image | May change edge stability; cannot establish physically correct occlusion absent from the renderer. Hold reconstruction fixed while diagnosing shadow ownership. |
| DLSS Ray Reconstruction | Reconstructs noisy ray-traced lighting using specified buffers/history on supported NVIDIA RTX hardware | Requires a valid noisy ray-traced color/radiance producer and required guides; a bare visibility mask or enabled DLL does not satisfy that contract. |

[NRD's official repository](https://github.com/NVIDIA-RTX/NRD) documents SIGMA's shadow role and D3D11/D3D12/Vulkan integration. Integration must provide coherent normal/depth/motion inputs, light/penumbra information and reset rules; verify exact requirements against the version selected. It is not intrinsically a new renderer and does not prove a cross-platform Godot backend path.

Vendor names alone are not hardware admission rules. NVIDIA's [RTX Kit FAQ](https://forums.developer.nvidia.com/t/rtx-kit-faq/322358) says many components can run on other vendors' GPUs, with DLSS among the exceptions; check the selected SDK's actual capability contract. NRD publishes [NVIDIA RTX SDK terms](https://github.com/NVIDIA-RTX/NRD/blob/master/LICENSE.txt), distinct from AMD's MIT-licensed analytical denoiser below.

The current [RTXDI repository](https://github.com/NVIDIA-RTX/RTXDI) covers ReSTIR DI, GI and PT. Using its samples entails scene representation, sampling/history and rendering integration; copying a many-light demo's performance result is not an OpenRC forecast. The [DLSS RR programming guide](https://github.com/NVIDIA-RTX/Streamline/blob/main/docs/ProgrammingGuideDLSS_RR.md) requires correctly formatted inputs such as depth, motion, material and noisy lighting data. This audit recommends a small visibility-focused experiment before full radiance reconstruction.

**Current repository distinction:** [Windows NVIDIA tooling](../../../tools/graphics/native/README.md) already exposes capability-checked DLSS/DLAA/Reflex. Its documented product path leaves Frame Generation, Ray Reconstruction and path tracing disabled/unqualified. That is not evidence that NVIDIA shadow reconstruction is installed. The fork and official engine also have different provenance/import capabilities; keep their receipts separate.

## AMD technologies

| Technology | Actual role | OpenRC disposition |
| --- | --- | --- |
| FidelityFX Shadow Denoiser | Reconstructs a noisy shadow signal using depth, normals, motion/history and scene parameters | Relevant analytical baseline for a traced-shadow prototype; inspect selected API/backend and sample contracts. |
| FidelityFX Hybrid Shadows | Combines raster coverage and selectively traced work | Useful experiment pattern for near aircraft/contact detail with raster distance coverage, provided ownership is explicit. |
| FidelityFX CACAO | Ambient occlusion | Independent grounding experiment; not aircraft self-shadow replacement. |
| FSR upscaling | Image reconstruction | Useful existing adjacent work; missing casters and plane-only receivers remain missing. |
| FSR Ray Regeneration 1.2.1 | Machine-learning denoising of supported ray-traced signals, including dominant-light visibility | Conditional on an actual supported producer/backend/device. It is distinct from the current Vulkan upscaling candidate. |

AMD's [FidelityFX Denoiser documentation](https://gpuopen.com/manuals/fidelityfx_sdk/techniques/denoiser/) describes shadow reconstruction from stochastic visibility with motion/depth/normal support. [Hybrid Shadows](https://gpuopen.com/fidelityfx-hybrid-shadows/) illustrates selective ray tracing alongside raster shadowing. These are implementation references, not proof that their API formats, material handling or performance transfer directly into Godot.

The [FidelityFX SDK v1 denoiser](https://gpuopen.com/fidelityfx-denoiser/) is published under MIT and lists D3D12/Vulkan support. That analytical shadow-mask denoiser is a different component from the newer Ray Regeneration model; do not transfer its license or device support to the latter by name association.

As checked on 17 November, [FSR Ray Regeneration](https://gpuopen.com/amd-fsr-rayregeneration/) **1.2.1** requires Radeon RX 9000-series or later, Windows 11 and DirectX 12 with Shader Model 6.6. Its denoising feature is separate from FSR upscaling; the [SDK page](https://gpuopen.com/amd-fsr-sdk/) also distinguishes their responsibilities. The repository's [SDK 2.4 Windows/Vulkan candidate](../../../tools/graphics/native/README.md#amd-sdk-24-candidate) is not evidence of a qualified Ray Regeneration route. Existing AMD completion work remains under [its plan](../../plans/amd-fsr-completion.md).

Do not infer Radeon GPU coverage from a Ryzen CPU benchmark. Do not assign a vendor's published milliseconds to the simulator. Validate the supported installed GPU, driver, API, SDK/engine hashes and real ray workload, including the no-RT fallback.

## Apple and existing engine RT work

It would be inaccurate to say that OpenRC must start every RT prerequisite from zero. The pinned [RenderingDevice API](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/RenderingDevice.xml) already exposes experimental BLAS/TLAS interfaces. API presence is distinct from a supported renderer, complete scene producer, execution on a particular GPU and product qualification. RenderingDevice is unavailable in Compatibility/headless; this audit did not execute those interfaces.

The long [DT-MAC-11a evidence record](../desktop-delivery-investigations/DT-MAC-11a/README.md) contains successive states. Its early uncompiled descriptions are superseded by later, narrower native results:

| Retained stage | What the repository evidence establishes | What it does not establish |
| --- | --- | --- |
| Triangle-query backend (`:532`, repeated `:845`) | 39 native query cases on M1, actual Metal hit/readback and validation, including a fresh-editor repeat | Full scene rendering, moving aircraft and all material semantics |
| Real-RT denoising witness (`:545–555`) | Both binding modes, 56,568 samples, 18,336 hits, zero analytic hit mismatches and finite 1920×1080 fixture output | Flight image quality, production integration or an FPS benefit |
| Scene-input diagnostic (`:900` onward) | Bounded actual scene geometry/hit identity and explicit unsupported-input rejection | A complete dynamic/material-capable viewport producer |
| Private RT-view follow-up (`:1768` onward) | Disposable gate override completed producer → MetalFX denoiser → GPU consumer for opaque ground/pilot-head geometry at 1080p | Whole-aircraft self-shadow, final visual quality, sustained cost, package qualification or an opened product gate |

The [Apple MetalFX plan](../../plans/apple-metalfx.md) and [optional 0027 intake](../../../tools/graphics/metalfx/README.md#optional-opaque-rt-view-0027) retain the current gate and provenance distinctions. The private trial and the later source-bound optional patch are not interchangeable artifacts. Product RT remains gated. MetalFX denoised upscaling needs noisy HDR radiance plus guides; a grayscale shadow-visibility mask alone is not that radiance input. Reuse the bounded native lessons without relabeling them a completed shadow solution.

## Smallest justified RT experiment

If tuned CSM/PCSS still fails a retained aircraft case, build one isolated sun-visibility comparison with a normally lit opaque aircraft, flat ground and a thin external blocker. Keep the user-selected raster fallback. Admit or reject each geometry/material category explicitly, including hinge motion, skinning, instancing/MultiMesh, alpha cards, two-sided parts, water, particles and rotor proxies.

Measure **all** producer costs: scene extraction, BLAS creation/refit/rebuild, TLAS updates, ray dispatch, guides, denoising, composition, synchronization and resident/history memory. Tie motion/history to presentation transforms; reject invalid history locally for motion/disocclusion, and reset history on discontinuities such as camera cuts, resize and scene changes as required by the selected SDK. Test scale/vehicle/material switches and pause/replay/reset explicitly. Preserve a deterministic higher-sample reference and exact-raster baseline. Verify world units and source-angle units: a 0.53° full sun angle corresponds to a 0.265° half-angle (about 0.004625 radians). AMD's [dominant-light angularRadius contract](https://gpuopen.com/manuals/fsr_sdk/techniques/denoising/) explicitly requests a half-angle in radians matched to the sampled ray cone; it must not receive Godot's degree value unchanged.

The acceptance packet must demonstrate a useful improvement at actual 1920×1080 on named hardware, no frozen or missing unsupported casters, stable motion and an honest unavailable/fallback state. Add higher resolutions next, then 720p fallback. Before SDK intake, pin its code/runtime/license notices and redistribution conditions; an MIT root in one dependency does not automatically license every bundled component. No RT or denoiser adoption is performed by this audit branch.

## Source provenance

All external links above are primary engine, vendor or author sources inspected for this audit. The three engine XML documents were retrieved at the exact engine commit, with blob identities retained in [external-sources.json](evidence/external-sources.json). Other web pages can change; the research date bounds this assessment. Repository capability claims refer to the frozen app baseline, not the newest page, a historical experiment or a helper's unverified recollection.
