# Graphics performance technologies: external audit

**Research date:** 2026-11-15. **Scope:** dynamic resolution and reconstruction, NVIDIA Reflex/Boost and other latency paths, and ray tracing in Godot. This is a source audit and implementation proposal; it does not change the simulator or qualify new graphics modes.

| Identity | Value |
| --- | --- |
| Repository | `bultodepapas/OpenRCsimulator` |
| Audited `main` commit | [`e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc`](https://github.com/bultodepapas/OpenRCsimulator/commit/e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc) |
| Baseline commit date | 2026-11-15 11:41:51 America/Bogota |
| Audit branch | `audit/graphics-performance-technologies-2026-11-15` |
| Official engine pin | `4.8.beta2.official.cafc17a19` |
| Resolution priority | 1920 × 1080 first; higher resolutions next; 1280 × 720 last, per [repository policy](../../../AGENTS.md#display-resolution-priorities) |
| Evidence boundary | Current source, retained project evidence, and newly checked primary internet sources. No new GPU, radio, latency or flight-performance measurements were collected for this audit. |

## Executive assessment

The project already contains meaningful implementations. Strengthen the existing measurement path in a **maximum five-engineering-day M0 milestone**, then deliver one fixed-provider correction or complete the existing Reflex comparison. M0 ends with proceed, static-only or blocked/defer; it does not expand into a new profiling product. Prototype controlled dynamic resolution where a named target is measurably GPU-bound and existing fixed-scale options do not meet the performance and readability gates.

- **Dynamic resolution:** the reconstruction menu already offers FSR, DLSS and MetalFX requests where capability gates allow them. Effective execution needs separate evidence. Its `Auto` policy selects a fixed mode from capability and output size; it does not continuously regulate GPU load. A real feedback controller is new work, and the engine's buffer/history behavior must be qualified first.
- **NVIDIA Reflex:** the separate Windows/Vulkan NVIDIA build contains real SDK scheduling and markers, with Off/On/Boost controls. The official cross-platform engine is a separate product path. Existing functional evidence does not establish a measured input-to-photon improvement.
- **Ray tracing:** recent Godot exposes useful low-level Vulkan APIs. OpenRC also has isolated Metal triangle-query and scene-input work. Neither fact alone provides a complete, qualified real-time ray-traced effect for normal flight. Reuse these foundations for one bounded optional effect after the performance baseline is dependable.

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

Machine-readable evidence: [audited source manifest](evidence/source-manifest.json) and [documentation validation](evidence/validation.json). The topic studies contain claim-specific primary sources; the manifest preserves source identities without copying upstream engine code into the repository.

## Recommended first work

Repair shared GPU-timing ownership, preserve truthful sample validity/scope in the existing consumers/reducers, and establish a source-identical 1080p active-flight control plus unchanged repeat. M0 includes its initial attribution and overhead check within the five-day ceiling. Then choose one current provider's demonstrated transition/history/fallback correction; additional measurement development has a named decision and a one-day review limit. Unknown GPU sample identity leaves that row static-only for DRS, while useful independent work continues.

After its relevant baseline, measure the existing Reflex Off/On/Boost path independently of DRS. Physical trials use the existing live-radio optical mode, with incompatible scripted/frame diagnostics collected separately; missing SDK flash verification remains an explicit gap without automatically blocking that comparison. Keep RT and frame generation under their own correctness, quality and latency gates. RT starts with a visible defect/headroom decision and one bounded direct-sun result, not a whole renderer replacement.

The [twenty-study catalog](08-twenty-external-investigations.md) is complete as source research. Its purpose is to select implementation and rejection decisions; it is not a backlog of twenty tools or twenty new SDK integrations. None of the new milestones or proposed measurement repairs is claimed implemented by this documentation branch.

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
