# R08 — Streamline Reflex: what must the existing fork prove?

2026-11-15 · External source investigation against audited application baseline `e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc`. **Decision:** finish a bounded measurement of the existing Windows/Vulkan Reflex path before replacing it or upgrading the SDK. The source establishes a plausible integration, not a latency benefit. This investigation supports [VQ-07h](../../../plans/advanced-graphics.md), [F6](../../../plans/controller-support.md) and the shared VQ-07d comparison; it does not make any of them complete.

## Sources inspected

| Source and identity | Type and relevant evidence |
| --- | --- |
| [Streamline Reflex guide](https://github.com/NVIDIA-RTX/Streamline/blob/019994e18d256a3e92347888deb527feb7f58bc0/docs/ProgrammingGuideReflex.md), `v2.11.1`, commit `019994e18d256a3e92347888deb527feb7f58bc0`, 2026-04-16 | Pinned SDK guide: feature checks, options, sleep, markers and verification. |
| [Sample callbacks](https://github.com/NVIDIA-RTX/Streamline_Sample/blob/94da85b6594e6c5109e84f995f5969811014c71f/src/StreamlineSample.cpp#L164) and [wrapper implementation](https://github.com/NVIDIA-RTX/Streamline_Sample/blob/94da85b6594e6c5109e84f995f5969811014c71f/src/SLWrapper.cpp#L1404), commit `94da85b6594e6c5109e84f995f5969811014c71f`, 2026-10-16 | Actual newer 2.14.16 application code; useful as a lifecycle example, not the pinned SDK's binary or API contract. |
| [Streamline changelog](https://github.com/NVIDIA-RTX/Streamline/blob/625db07d4bca5abc67d781c42af7e7fb0761f1b6/changelog.txt), commit `625db07d4bca5abc67d781c42af7e7fb0761f1b6`, 2026-10-16 | The 2.14.0 entry changes the Vulkan Reflex implementation and support boundary. |
| [DXVK-NVAPI issue 323](https://github.com/jp7677/dxvk-nvapi/issues/323), opened 2025-10-24 | Engineering discussion: the reporter and an NVIDIA participant observed mode/cap problems in a particular translated game and debated where calls were lost. This is a test case, not evidence of an OpenRC defect. |

## Implementation findings

The 2.11.1 guide separates `kFeatureReflex` from `kFeaturePCL`: for supported features it calls `slReflexSleep` and sends PCL markers even when low latency is Off. Set Reflex options at least once and again on changes; `lowLatencyAvailable` governs the available choice. Boost is a different mode, not frame generation. A token identifies a render frame; it does not identify an entire physical radio path.

In the newer sample, `beforeFrame` obtains a token and sleeps, `beforeAnimate`/`afterAnimate` mark simulation, and callbacks bracket rendering and present. Its wrapper asks for the same frame ID when producing each marker. This demonstrates why the engine must own frame ordering. A sample callback name alone cannot show where a particular Godot radio sample is consumed, or prove actual scanout timing.

The newer changelog says 2.14.0 uses `VK_NV_low_latency2` when exposed and otherwise falls back to an NvAPI v1 path; it removes Vulkan Reflex support for pre-Turing hardware. Do not silently project that implementation onto 2.11.1. OpenRC's [native build](../../../../tools/graphics/native/build.py#L24) pins 2.11.1; its [documented 2.14.16 trial](../../../../tools/graphics/native/README.md#engine-provenance-and-historical-trial) encountered startup errors and was rejected. A later version is a separately pinned, tested upgrade, not a repair prerequisite.

## OpenRC mapping and choice

The [lifecycle patch](../../../../tools/graphics/native/reflex_lifecycle.patch#L98) obtains a token and sleeps on the pre-message-loop route; the [frame lifecycle patch](../../../../tools/graphics/native/dlss_frame_lifecycle.patch#L69) carries the render token to the render thread; the [synchronization patch](../../../../tools/graphics/native/reflex_sync.patch#L22) serializes non-thread-safe option/state work. The [adapter](../../../../app/render/nvidia_reflex.gd) separates saved request from accepted support and preserves fallback. These are meaningful code, but counters and SDK success do not show correct event-to-visible-frame attribution or a shorter physical response.

The [flight reader](../../../../app/sim/flight_session.gd#L1332) samples axes in a fixed-tick session; [project settings](../../../../app/project.godot#L44) specify 240 Hz physics. A render iteration may include zero, one or multiple ticks. Do not move input sampling, alter interpolation or physics, or add a second independent wait merely to improve a PCL number. Preserve the existing user-facing mode, fallback and separate opt-in Boost. An issue report of a cap or toggle failure motivates lifecycle checks; it does not prove the same failure here.

## Bounded deliverable and stop

After the common 1080p baseline is usable, use the existing native package and diagnostics for one within-build Off/On/Boost comparison. Record exact application, engine/template/patch/runtime hashes, renderer, GPU/driver, cap, VSync, effective presentation and thermal/power conditions; verify token/marker ordering, sleep while Off, hot mode changes, resize, minimize/restore and shutdown. Apply the SDK's flash/verification procedure with already available equipment where applicable, recording any missing vendor verification as a gap; do not hold the optical comparison for a new tool installation. Separately test ordinary player presentation. An official-engine versus fork comparison includes engine differences and is not the isolated Reflex effect.

For F6 film the real transmitter and the existing [optical patch](../../../../app/input/latency_patch.gd#L147) with fixed threshold, camera, display scan position and transport. Record stick-to-patch and stick-to-first-visible-control response separately; the PCL or mouse metric is complementary. At least 30 transitions per condition is an initial screen; target at least 100 across repeated sessions for p95, report interval and between-session uncertainty, and collect more or mark inconclusive if the decision is smaller than measurement resolution. Reuse the [validation plan](../06-validation-and-benchmark-plan.md); no new measurement product is required.

**Accept only for the named configuration** if repeated paired results exceed uncertainty without pacing, lifecycle, input or simulation regressions. Retain the baseline or mark inconclusive when evidence, hardware, physical equipment or correct attribution is unavailable. This is a source study; no runtime or physical test was performed here.
