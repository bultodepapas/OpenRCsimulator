# MetalFX, frame generation and the M1 — 2026-11-14

Owner: DT/PT, with VQ/GDU for renderer integration. This dated research supports
DT-MAC-06b and DT-MAC-07a–c in the [Apple master plan](../../plans/apple-silicon-performance.md).
It does not replace that plan or its acceptance gates.

Reviewed repository: `b80a4b214878e97313d2f93901b32174bb0713ea`;
Godot `4.8-beta2`, engine commit `cafc17a192acf67903910a68aeb3c076c0907a4b`.
Unrelated pending version/release edits were preserved. This is primary-source
and code research: no new M1 capability probe, benchmark, runtime change or
feature promotion was performed.

## Findings

Apple's equivalent family is **MetalFX**. Upscaling, generated frames and
denoising solve different problems. Metal 4 is the graphics/compute API; it is
not itself an upscaler or a frame-generation switch.

| Technology | Purpose | M1 applicability |
| --- | --- | --- |
| MetalFX Spatial | Reconstruct a larger image from one lower-resolution frame | Supported hardware family; macOS 13+ API. Already integrated in OpenRC. |
| MetalFX Temporal | Reconstruct detail using history, depth and motion; includes temporal AA | M1 is Apple7, the published minimum family. macOS 13+ API; query actual device support and scale bounds. |
| MetalFX Frame Interpolation | Generate an intermediate image between rendered frames | M1 is within the published hardware families. Both command-buffer API variants require macOS 26+ and runtime support checks. No M1 interpolation run was made here. |
| MetalFX Temporal Denoised Scaling | Combine ray-tracing denoising with reconstruction | Published minimum Apple9, corresponding to M3-series and later Macs; outside the M1 target. |

Hardware-family statements come from Apple's [October 23, 2026 feature tables](https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf).
OS availability and capability contracts are specified separately by the
[Spatial descriptor](https://developer.apple.com/documentation/metalfx/mtlfxspatialscalerdescriptor),
[Temporal descriptor](https://developer.apple.com/documentation/metalfx/mtlfxtemporalscalerdescriptor)
and [frame-interpolator descriptor](https://developer.apple.com/documentation/metalfx/mtlfxframeinterpolatordescriptor).
Family eligibility is not a successful allocation or a performance result.

Functionally, Temporal addresses the reconstruction problem also addressed by
DLSS Super Resolution and FSR temporal upscalers; Frame Interpolation addresses
frame generation. These are not interchangeable SDKs. NVIDIA's [DLSS suite](https://developer.nvidia.com/rtx/dlss)
targets RTX hardware, and AMD's [FSR Frame Generation](https://gpuopen.com/amd-fsr-framegeneration/)
has its own integration and supported-hardware contracts. Neither vendor's
latest generation features become available on a Mac merely because an engine
has an FSR or DLSS menu label.

### Important availability discrepancy

The official Apple Game Porting Toolkit's [frame-interpolation integration reference](https://github.com/apple/game-porting-toolkit/blob/main/game-porting-skills/skills/using-metalfx-frame-interpolation/SKILL.md)
currently says macOS 15+ for its Metal 3 variant. The actual documented symbols
[MTLFXFrameInterpolator](https://developer.apple.com/documentation/metalfx/mtlfxframeinterpolator.md),
[MTL4FXFrameInterpolator](https://developer.apple.com/documentation/metalfx/mtl4fxframeinterpolator.md)
and [supportsDevice](https://developer.apple.com/documentation/metalfx/mtlfxframeinterpolatordescriptor/supportsdevice(_:).md)
declare macOS 26+. Use symbol availability and the installed SDK header as the
integration authority; do not advertise macOS 15 support from that reference.
The Metal 3 command-buffer variant does not require migrating an app's entire
renderer to Metal 4.

## Existing OpenRC and exact engine boundaries

[Reconstruction](../../../app/render/reconstruction.gd) already exposes guarded
Spatial and Temporal choices. Its Auto policy tries Spatial only when the
nominal internal input retains at least 1,000 rows; otherwise it selects Native.
At 1920×1080, neither Spatial 85% nor Quality reaches that threshold, so Auto
chooses Native. Spatial remains manually selectable when capability checks pass.
At scale 1.0, selecting a spatial mode does not perform useful enlargement.

In the pinned engine, Spatial supports Mobile and Forward+ on Metal. Temporal
and FSR 2.2 require Forward+; Compatibility cannot provide these paths. Verify
these constraints in the exact [viewport implementation](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_viewport.cpp#L126-L213),
rather than inferring Mobile support from the existence of an API enum.
OpenRC's standard Apple Silicon route is Mobile/Metal. Switching to Forward+
adds a separate renderer-cost comparison before crediting Temporal gains.

The inspected integration provides reconstruction, not a confirmed generated-frame
presentation path. The pinned [scaling enum](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/scene/main/viewport.h#L97-L110)
contains FSR 1/2 and MetalFX Spatial/Temporal; OpenRC's conditional FSR3/DLSS
labels do not establish their availability. Frame generation needs a separate
engine/presentation implementation assessment, not another scaling enum.

### Existing measured opportunity, not a new benchmark

The [November 5 M1 screen](DT-MAC-00-R4/README.md#dt-mac-06b-c1-retina-input-scale-screen-2026-11-05)
retains one 10-second warmup plus 20-second sample per mode at **2560×1600 output**:

| Mode | Nominal internal 3D | GPU ms | Recorded FPS |
| --- | --- | ---: | ---: |
| Native | 2560×1600 | 28.26 | 34.5 |
| Spatial 85% | 2176×1360 | 25.36 | 39.0 |
| Spatial 67% | 1707×1067 | 18.68 | 52.2 |
| Bilinear 67% | 1707×1067 | 16.87 | 59.0 |

Spatial 67% was about 51.3% faster in recorded FPS than Native in this short
screen. Lower internal pixel work produced the opportunity; MetalFX itself
added about 2.16 ms in Tonemap relative to Bilinear at the same scale. Static
aircraft crops favored Spatial's detail preservation. Moving-aircraft quality,
repeated comparison and current-source 1080p qualification were not established.
Do not transfer this percentage to today's 1080p circuit or to frame generation.
It is separate from the [native CPU evaluator's callback results](../native-kernel/DT-MAC-04n4/README.md).

## Generated frames: benefits and costs

Apple's [integration session](https://developer.apple.com/videos/play/wwdc2025/211/)
uses consecutive rendered images, motion vectors and depth. Integration must
handle camera conventions, UI composition and evenly spaced real/generated
presentation. Apple advises a base rate of at least 30 FPS. An illustrative
60-rendered/120-presented pipeline describes cadence, not a measured M1 result
or a guaranteed doubling after interpolation overhead.

Apple explicitly identifies an [input-latency cost](https://developer.apple.com/videos/play/wwdc2026/357/).
Generated pictures do not create new physics steps or control decisions. For
RC piloting, input-to-display latency and the readability of a small moving
aircraft matter alongside displayed FPS. Evaluate propellers, thin gear, smoke,
wind-blown vegetation, disocclusion, HUD and camera/reset transitions. Existing
Temporal history/reset requirements remain in [DT-MAC-07](../../plans/apple-silicon-performance.md#9-phase-7--qualify-existing-metalfx-trials-conditionally).

Apple's [Metal HUD metrics](https://developer.apple.com/documentation/xcode/understanding-metal-performance-hud-metrics)
can include generated frames in reported FPS. Keep real rendering FPS,
generated/presented FPS, simulation rate and presentation intervals separate.
A higher HUD number alone cannot establish lower latency or fewer stalls.

## Complementary technologies and next research order

1. **Spatial at 1080p first.** Compare existing Native and Spatial 85% on the
   same Mobile/Metal workload, including distant-aircraft motion and whole GPU
   time. Its nominal input is 1632×918; output remains 1920×1080. Preserve the
   user's overrides and Auto's current Native fallback.
2. **Address actual stutter causes.** Godot's [pipeline precompilation and shader baker](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html)
   target different compilation stages. Baking intermediate shaders is not
   final GPU-pipeline precompilation. Compare cold and warm loads and monitor
   pipeline creation; frame generation cannot be assumed to repair an asset or
   shader stall. Metal baking requires the supported native export environment.
3. **Measure presentation and latency.** [CAMetalDisplayLink](https://developer.apple.com/documentation/quartzcore/cametaldisplaylink)
   provides display-driven scheduling; [preferredFrameLatency](https://developer.apple.com/documentation/quartzcore/cametaldisplaylink/preferredframelatency)
   is a request and windowed presentation can add latency. Audit the exact
   engine path before adding another scheduler. [Game Mode](https://support.apple.com/en-asia/105118)
   is another candidate on Apple Silicon/macOS 14+ in supported native full
   screen; do not assume the windowed benchmark activates it.
4. **Temporal as a separate Forward+ experiment.** Compare Forward+ Native
   against Forward+ Temporal, then compare the winning complete configuration
   against Mobile. Require actual scaler allocation/status and reset behavior.
5. **Frame generation last, optional.** Probe support and display refresh first;
   prototype engine-owned interpolation/presentation using Apple's existing
   references. Measure GPU cost, unified-memory growth, real/presented cadence,
   p95/p99 and control latency. A 60 Hz display cannot show 120 distinct refreshes.

These are research priorities, not approved defaults or performance forecasts.
Keep float64 simulation and its 240 Hz contract unchanged. No new MetalFX,
frame-generation, shader, memory, latency or energy benefit was measured here.
