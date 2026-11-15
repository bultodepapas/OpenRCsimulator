# Graphics performance technologies: external audit

**Research date:** 2026-11-15. **Scope:** dynamic resolution and reconstruction, NVIDIA Reflex/Boost and other latency paths, and ray tracing in Godot. This is a source audit and implementation proposal with offline executable design examples; it does not change the simulator or qualify new graphics modes.

| Identity | Value |
| --- | --- |
| Repository | `bultodepapas/OpenRCsimulator` |
| Audited `main` commit | [`e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc`](https://github.com/bultodepapas/OpenRCsimulator/commit/e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc) |
| Baseline commit date | 2026-11-15 11:41:51 America/Bogota |
| Audit branch | `audit/graphics-performance-technologies-2026-11-15` |
| Official engine pin | `4.8.beta2.official.cafc17a19` |
| Resolution priority | 1920 × 1080 first; higher resolutions next; 1280 × 720 last, per [repository policy](../../../AGENTS.md#display-resolution-priorities) |
| Evidence boundary | Current source, retained project evidence, and newly checked primary internet sources. No new GPU, radio, latency or flight-performance measurements were collected for this audit. |
| Publication checkpoint | Later `main` at `273a7e4c0617fdf4cacc39c360796fd79afa5f2c` was reviewed for drift; [newer Apple, aircraft and test-queue context](13-community-driven-execution-plan.md#4-newer-main-checkpoint-and-retained-project-results) is recorded separately from the pinned audit baseline and the earlier handoff checkpoint. |

## Executive assessment

The project already contains meaningful implementations. Strengthen the existing measurement path in a **maximum five-engineering-day M0 milestone**, then deliver one fixed-provider correction or complete the existing Reflex comparison. M0 ends with proceed, static-only or blocked/defer; it does not expand into a new profiling product. Prototype controlled dynamic resolution where a named target is measurably GPU-bound and existing fixed-scale options do not meet the performance and readability gates.

- **Dynamic resolution:** the reconstruction menu already offers FSR, DLSS and MetalFX requests where capability gates allow them. Effective execution needs separate evidence. Its `Auto` policy selects a fixed mode from capability and output size; it does not continuously regulate GPU load. A real feedback controller is new work, and the engine's buffer/history behavior must be qualified first.
- **NVIDIA Reflex:** the separate Windows/Vulkan NVIDIA build contains real SDK scheduling and markers, with Off/On/Boost controls. The official cross-platform engine is a separate product path. Existing functional evidence does not establish a measured input-to-photon improvement.
- **Ray tracing:** recent Godot exposes useful low-level Vulkan APIs. OpenRC also has isolated Metal triangle-query and scene-input work. Neither fact alone provides a complete, qualified real-time ray-traced effect for normal flight. The expanded [quality and delivery plan](14-ray-tracing-quality-and-delivery-plan.md) prioritizes one conditional sunlight-shadow result against existing PCSS, then selected reflections against the existing planar/probe path. It separates NVIDIA/AMD SDK opportunities from cloud/material improvements and preserves bounded cost, readability and fallback gates.

## How to read the audit

| Report | Purpose |
| --- | --- |
| [01 · Repository audit](01-repository-audit.md) | Engine families, code-to-behavior map, seven findings and source/evidence limits. |
| [02 · Dynamic resolution and upscaling](02-dynamic-resolution-and-upscaling.md) | Apple/Windows/Linux/vendor matrix, exact engine allocation behavior, current M1 evidence and a guarded controller design. |
| [03 · Latency, Reflex and Boost](03-latency-reflex-and-boost.md) | Actual native integration, RC input path, Boost tradeoffs, AMD/Intel/Linux alternatives and measurement requirements. |
| [04 · Ray tracing in Godot](04-ray-tracing-in-godot.md) | Current Vulkan APIs, stock versus experimental Metal, existing OpenRC prerequisites and a bounded optional effect. |
| [05 · Integrated implementation plan](05-integrated-implementation-plan.md) | Explicit objectives and M0–M5 milestones; five-day measurement repair with file boundaries and exit decisions; product deliverables, settings contract and stop conditions. |
| [06 · Validation and benchmarks](06-validation-and-benchmark-plan.md) | A bounded screen → finalist → export funnel; existing-tool improvements, native 1080p evidence, motion/readability, physical RC latency and lifecycle gates. |
| [07 · Sources and verification](07-sources-and-verification.md) | Source precedence, version contradictions, independent review and validation receipts. |
| [08 · Twenty external investigations](08-twenty-external-investigations.md) | Twenty linked studies of real GitHub code, official documentation and developer discussions: seven reconstruction, five latency, three measurement and five RT questions, each mapped to OpenRC with adopt/avoid and bounded next steps. |
| [09 · Timing and DRS design](09-timing-and-drs-design.md) | Detailed caller/lifetime, sample-schema, native timing, integer range, settings and transaction pseudocode with exact existing test seams. |
| [10 · Reflex and ray integration design](10-reflex-and-ray-integration-design.md) | Patched frame ordering, failure/flash cases, concrete sun-light and scene-buffer seams, and proposed native/optical/RT test oracles. |
| [11 · Test and execution playbook](11-test-and-execution-playbook.md) | Verified existing commands, selective test matrix, comparison pitfalls, native and optical execution cards, and rollback decisions. |
| [12 · Senior developer handoff](12-senior-developer-handoff.md) | Next reviewable changes, day-by-day M0 scope, new findings and implementation-ready acceptance boundaries. |
| [13 · Community evidence and execution](13-community-driven-execution-plan.md) | Seventeen additional practical cases from developer forums and GitHub discussions, tied to existing work slices, expected outcomes, conditional tests, provider-specific pseudocode and stop decisions. |
| [14 · Ray-tracing quality and delivery](14-ray-tracing-quality-and-delivery-plan.md) | Where RT could visibly help normal RC flight, benefit/cost ranking, NVIDIA/AMD route, source-specific cloud/material/water boundaries, frame/lifetime pseudocode and bounded implementation/test milestones. Includes a [vendor guide with 12 source entries](ray-tracing/01-nvidia-amd-integration-guide.md) and a [cloud/material/water guide with nine selected references](ray-tracing/02-clouds-materials-and-water.md). |
| [15 · Ray-tracing fixture handoff](15-ray-tracing-fixture-handoff.md) | Three exact-engine source findings, concrete correction order, a [native Vulkan fixture work order](ray-tracing/03-vulkan-fixture-work-order.md), and a [26-test offline reference](../../../research/performance/graphics_handoff/rt_fixture_README.md) with 14 geometry/five lighting cases and seven caught deliberate regressions. Positive native execution remains pending. |

Machine-readable evidence: [audited source manifest](evidence/source-manifest.json), [prior documentation validation](evidence/validation.json), [handoff validation](evidence/handoff-validation.json), [community continuation validation](evidence/community-validation.json), [ray-tracing continuation validation](evidence/ray-tracing-validation.json), and [RT fixture validation](evidence/rt-fixture-validation.json). The [DRS reference and 38 tests](../../../research/performance/graphics_handoff/README.md) and [RT reference and 26 tests](../../../research/performance/graphics_handoff/rt_fixture_README.md) are runnable offline research examples with no engine or measurement I/O. The topic studies contain claim-specific primary sources; the manifests preserve source identities without copying upstream engine code into the repository.

The latest forum round has three case chapters: [six resolution/upscaling cases](community/01-resolution-and-upscaling-cases.md), [six latency/pacing cases](community/02-latency-and-pacing-cases.md), and [five RT/integration cases](community/03-ray-tracing-cases.md). They distinguish observed reports, unresolved explanations, subsequently corrected artifacts and fixes already present in the official pin. Each case identifies an existing OpenRC seam and a falsifiable next check. Their reported milliseconds, camera-frame counts and allocation gains are external observations, not simulator measurements. The next implementation remains bounded M0 followed by one product correction or the independent Reflex comparison.

The later RT expansion answers the visual-quality question directly: shadows near landing, selected lake/glossy reflections, close-up occlusion and indirect lighting have different value and cost. It records existing soft-shadow, material and atmosphere baselines; separates volume raymarching from hardware triangle tracing; and explains why DLSS Ray Reconstruction, NVIDIA NRD/RTXDI and AMD Ray Regeneration are conditional integrations rather than consequences of having an upscaler installed. The first hard-ray fixture tests correctness before any soft-shadow denoiser or full-flight option is justified.

The latest fixture continuation makes that first step executable offline and specific natively. Exact-source review found a Vulkan AS-address contract mismatch, incomplete AS creation-error propagation and a same-TLAS repeated-build input risk. The [work order](ray-tracing/03-vulkan-fixture-work-order.md) requires reviewed corrections based on the existing pin before the positive portability witness. Its small independent corpus checks transforms, masks, identity, closest distance and Sun energy; it does not claim that a GPU, shader or flight image has passed. The next RT implementation is the engine prerequisite followed by the known-answer witness, within the existing decision deadline.

## Recommended first work

Repair shared GPU-timing ownership, preserve truthful sample validity/scope in the existing consumers/reducers, and establish a source-identical 1080p active-flight control plus unchanged repeat. M0 includes its initial attribution and overhead check within the five-day ceiling. Then choose one current provider's demonstrated transition/history/fallback correction; additional measurement development has a named decision and a one-day review limit. Unknown GPU sample identity leaves that row static-only for DRS, while useful independent work continues.

After its relevant baseline, measure the existing Reflex Off/On/Boost path independently of DRS. Physical trials use the existing live-radio optical mode, with incompatible scripted/frame diagnostics collected separately; missing SDK flash verification remains an explicit gap without automatically blocking that comparison. Keep RT and frame generation under their own correctness, quality and latency gates. RT starts with a visible defect/headroom decision and one bounded direct-sun result, not a whole renderer replacement.

The [twenty-study catalog](08-twenty-external-investigations.md) is complete as source research. Its purpose is to select implementation and rejection decisions; it is not a backlog of twenty tools or twenty new SDK integrations. The later handoff adds executable contract examples, while the production milestones and proposed measurement repairs remain unimplemented on this research branch.

The strongest current source risks are stale/ambiguous GPU samples, multiple owners of the measurement flag, repeated buffer reconfiguration, incomplete temporal-reset coverage across engine families, and overgeneralizing limited native results. None of this audit's source findings establishes a measured speedup or a measured hitch on its own.

## Existing authoritative owners

| Work | Current owner/home |
| --- | --- |
| Renderer integration, reconstruction and advanced graphics | [VQ-07a…h](../../plans/advanced-graphics.md) |
| FSR completion and separate frame generation | [VQ-07d/h FSR completion](../../plans/amd-fsr-completion.md) |
| Apple Silicon performance | [DT-MAC master plan](../../plans/apple-silicon-performance.md) |
| MetalFX, frame presentation and Apple RT producer | [DT-MAC MetalFX subplan](../../plans/apple-metalfx.md) |
| Shared performance priorities | [Global performance/visual plan](../../plans/global-performance-visual-quality.md) |
| Engine and desktop delivery | [GDU engine plan](../../plans/godot-4.8-upgrade.md), [DT desktop plan](../../DESKTOP-DELIVERY-PLAN.md), [DT-LNX](../../plans/linux-support-distribution.md) |

This dated audit is advisory input to those homes. A recommendation here is not an accepted architecture decision or a completed implementation step. Software correctness, actual SDK execution, visual quality, performance, presentation latency and target-hardware qualification remain separate claims.
