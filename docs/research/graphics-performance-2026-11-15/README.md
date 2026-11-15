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

The project already contains meaningful implementations. The best next investment is to connect and qualify the existing pieces through reliable measurements and a controlled dynamic-resolution policy.

- **Dynamic resolution:** the reconstruction menu already selects FSR, DLSS and MetalFX paths where the actual engine supports them. Its `Auto` policy selects a fixed mode from capability and output size; it does not continuously regulate GPU load. A real feedback controller is new work, and the engine's buffer/history behavior must be qualified first.
- **NVIDIA Reflex:** the separate Windows/Vulkan NVIDIA build contains real SDK scheduling and markers, with Off/On/Boost controls. The official cross-platform engine is a separate product path. Existing functional evidence does not establish a measured input-to-photon improvement.
- **Ray tracing:** recent Godot exposes useful low-level Vulkan APIs. OpenRC also has isolated Metal triangle-query and scene-input work. Neither fact alone provides a complete, qualified real-time ray-traced effect for normal flight. Reuse these foundations for one bounded optional effect after the performance baseline is dependable.

## How to read the audit

The [repository audit](01-repository-audit.md) anchors findings to the baseline. Topic reports, the integrated work order, and the validation plan are being assembled in this directory and will be linked here when complete. All recommendations retain the existing track owners below.

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
