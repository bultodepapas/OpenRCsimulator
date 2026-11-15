# Sources, review and verification record

Research date: 2026-11-15. Application baseline: `e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc`. This report documents how the [audit](README.md) supports its conclusions. It is not a native qualification report.

## Evidence order

1. **Current implementation:** the baseline's actual runtime, settings, native patch stack, build/package logic and tests. The GitHub default branch identity was checked through both the repository API and Git remote before work began.
2. **Retained observations:** original dated project receipts and reports, with their own engine/source/hardware/workload identity. They do not become fresh tests of the audited commit by being cited here. The late 2026-11-15 Apple follow-ups were read alongside the earlier evidence.
3. **External technical contracts:** exact pinned upstream source where obtainable, official release/version records and original Godot, Apple, NVIDIA, AMD, Intel and Khronos documentation/repositories. General current documentation is labeled where it differs from the project pin.
4. **Proposed design and estimates:** a reasoned engineering proposal, explicitly conditional on workload, capability and acceptance evidence. No proposed threshold, effort range or vendor performance claim is represented as an OpenRC measurement.

The [source manifest](evidence/source-manifest.json) records selected inspected project files using Git blob IDs and raw SHA-256, plus the exact upstream source files fetched for the engine questions. It is a reproducibility aid for this focused review, not a complete asset/runtime dependency closure or a guarantee about uninspected branches.

## Primary-source map

Each topic report maps more detailed claims to direct source links. This compact index identifies the references that change the implementation decision.

| Question | Primary evidence and interpretation |
| --- | --- |
| Which engine is being audited? | [Godot beta 2](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-2/) and [beta 3](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-3/) plus the checked-in getters. Beta 3 exists; beta 2 remains this project's official pin. |
| Does runtime scale mean low-cost DRS? | Pinned [Viewport](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/scene/main/viewport.cpp), [renderer viewport](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_viewport.cpp), and [RD render buffers](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/storage_rd/render_scene_buffers_rd.cpp). Exact-float guards and reconfiguration/resource work make this a qualification problem. |
| What does AMD's current SDK include? | [FSR SDK release notes](https://gpuopen.com/manuals/fsr_sdk/whats-new/), [analytical upscaler guide](https://gpuopen.com/manuals/fsr_sdk/techniques/super-resolution-upscaler/) and [ML guide](https://gpuopen.com/manuals/fsr_sdk/techniques/super-resolution-ml/). The SDK bundle version, stock Godot FSR and selected runtime implementation have distinct identities. |
| Does Apple support changing temporal input content? | [MetalFX temporal descriptor](https://developer.apple.com/documentation/metalfx/mtlfxtemporalscalerdescriptor), [dynamic input setting](https://developer.apple.com/documentation/metalfx/mtlfxtemporalscalerdescriptor/isinputcontentpropertiesenabled), [reset](https://developer.apple.com/documentation/metalfx/mtlfxtemporalscalerbase/reset). The Apple API contract is not proof that the current Godot wrapper preserves its history and allocations. |
| What is real Reflex integration? | NVIDIA's [pinned Streamline 2.11.1 guide](https://github.com/NVIDIA-RTX/Streamline/blob/v2.11.1/docs/ProgrammingGuideReflex.md), [current guide](https://github.com/NVIDIA-RTX/Streamline/blob/main/docs/ProgrammingGuideReflex.md), [changelog](https://github.com/NVIDIA-RTX/Streamline/blob/main/changelog.txt) and [latency explanation](https://www.nvidia.com/en-us/geforce/news/reflex-low-latency-platform/), checked against the OpenRC patch stack. Modes, capabilities, markers, Sleep, Boost and verification have distinct purposes. |
| Are latency alternatives portable? | Khronos [`VK_NV_low_latency2`](https://docs.vulkan.org/refpages/latest/refpages/source/VK_NV_low_latency2.html) and [`VK_AMD_anti_lag`](https://docs.vulkan.org/refpages/latest/refpages/source/VK_AMD_anti_lag.html); [AMD Anti-Lag 2 requirements](https://gpuopen.com/anti-lag-2/) and [public SDK](https://github.com/GPUOpen-LibrariesAndSDKs/AntiLag2-SDK); [Intel XeLL](https://github.com/intel/xess/blob/main/doc/xell_developer_guide_english.md). An extension specification or Windows SDK does not establish Linux driver/runtime integration. |
| Does current Godot have RT APIs? | [GodotCon integration description](https://talks.godotengine.org/godotcon-ams-2026/talk/JDYVQ3/), exact beta 2 [RenderingDevice](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/rendering_device.cpp) and [Vulkan driver](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/vulkan/rendering_device_driver_vulkan.cpp), plus [the original query bug](https://github.com/godotengine/godot/issues/121286). Low-level APIs exist; whole-scene effects and actual device execution remain distinct. |
| Does an Apple GPU imply Godot RT support? | [Apple Metal RT](https://developer.apple.com/documentation/metal/accelerating-ray-tracing-using-metal), [Apple family 9 hardware](https://developer.apple.com/videos/play/tech-talks/111375/), the pinned Metal driver stubs and OpenRC's isolated Metal patches. API capability, dedicated hardware acceleration and engine integration must be established separately. |

All sources were checked on the research date. URLs under `main`, `master`, `latest` or `stable` can change; exact commit links and the manifest preserve the pin-specific findings.

## Contradictions resolved explicitly

- The NVIDIA marketing FAQ still describes Vulkan as forthcoming, while SDK source/changelog and OpenRC's retained Vulkan integration are newer evidence. The report uses version-specific SDK evidence, without pretending the project's 2.11.1 pin is current 2.14.16.
- The generic Reflex hardware table is not a universal rule: the 2.14.0 changelog changes Vulkan support and removes pre-Turing eligibility in that version. That does not silently change the already pinned build's contract.
- AMD's Anti-Lag page lists Vulkan driver support while the public SDK examples expose DX11/DX12 headers. A native Vulkan extension investigation is required; the Windows DX examples alone do not solve the current Vulkan application.
- An old Godot ray-query request defect is not carried into the audited beta blindly. The exact beta 2 Vulkan source contains the request, feature query and enablement. The separate SBT/query-only and build/update limitations remain explicit.
- Positive M1 provider and presentation observations coexist with failed or incomplete full-application cases. Requested Temporal that fell back to Native is not a Temporal benchmark; isolated generated presentation is not full-flight FG or physical scanout evidence.

## Independent review and checks

Three bounded specialist studies covered reconstruction, latency and RT, with separate file ownership. A critical review challenged the repository conclusions and integrated plan. Resolved points include conditional DRS admission, unknown effective state, the actual timer-overlap path, physical-radio versus PCL endpoints, CPU-bound Reflex/Boost cases, independent experiment ordering, and uncertainty across sessions and small optical sample counts. This review is an additional source-quality check, not hardware evidence or certification.

The final [validation receipt](evidence/validation.json) records document/link checks, source preservation, manifest verification and the exact scope checked. Local links and Markdown anchors are checked using the repository's existing `tools/ci/check_docs.py` parsing and Git-object target validation. Comparing Git objects makes the check independent of a sparse worktree's omitted files. Newly cited non-Markdown source line fragments are contextual references; the link checker establishes the file target, not semantic correctness of each line claim, which was reviewed separately.

The audit also checks whitespace/conflict markers, valid UTF-8 and JSON, hashes against the baseline, and that no production source or existing plan was modified. No simulation suite was needed for these documentation-only changes. No native app, GPU, benchmark, physical controller or export-template validation was run by this audit. Required CI and hardware acceptance for any future implementation remain in their owners' gates.

## Remaining uncertainty

No target-host measurements establish the current commit's DRS benefit, scale-transition hitch size, physical RC latency gain, Boost power benefit, RT cost or cross-device compatibility. Existing historical measurements remain useful within their recorded scopes. The proposed work order obtains those missing observations before any general support claim, default change or performance promise.
