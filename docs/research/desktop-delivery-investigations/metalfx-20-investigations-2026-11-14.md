# MetalFX implementation — twenty investigations, 2026-11-14

Owner: DT/VQ/GDU/PT. Execution home: [four-technology plan](../../plans/apple-metalfx.md).
Reviewed OpenRC: `0bc2a52e129248ed91632f02f448e7d6455f6a5f`; engine:
Godot `4.8-beta2`, `cafc17a192acf67903910a68aeb3c076c0907a4b`.
This extends the [initial MetalFX research](metalfx-frame-generation-2026-11-14.md).
All twenty investigations below are source research, not native benchmarks.
No engine build, SSH experiment, device qualification or runtime change occurred.

## Method and decision map

Each investigation answers one implementation question, identifies primary
evidence and uncertainty, changes an owning plan step, and supplies a discriminating
test. Official API declarations and exact source precede reference prose.
GitHub issues and forum reports retain their actual versions and reproduction
limits; a report about another device/engine is not an OpenRC defect. Apple DTS
responses strengthen the named case, not an entire hardware-family claim.

Source confidence labels: **contract** = documented API; **code** = inspected
implementation; **case** = scoped author/maintainer report; **unresolved** = conflicting
or unexecuted behavior. All links were consulted on 2026-11-14. Moving web pages
need rechecking at intake; named engine/fork commits below are immutable references.

| Investigation | Implementation decision / owning step |
| --- | --- |
| I01 Engine integration | Inventory exact factory/callback/driver seams; evaluate upstream hook without changing engine blindly — 11a |
| I02 Capabilities and bounds | Track queried versus assumed bounds and reciprocal/fixed-point units — 07a1/07b2 |
| I03 Failure paths | Check native factories and callbacks; do not invent nil failure reasons — 07a1 |
| I04 Temporal inputs | Audit each produced signal instead of assuming valid motion/exposure — 07b2 |
| I05 History isolation | One history per view or explicit multi-view rejection — 07a2 |
| I06 AA and tiny aircraft | Restore projection jitter as well as AA; qualify moving readability — 07b1/b2 |
| I07 Color/HDR/alpha | Verify actual transfer functions and composition before changing mode — 07b1 |
| I08 Interpolation inputs | Separate macOS 26 and 27 contracts; previous-encode history — 12a |
| I09 Presentation scheduling | Choose manual timed drawables or display-link drawables coherently — 12b |
| I10 UI and effects | Interpolate scene after tone mapping, composite UI exactly once — 12b |
| I11 Synchronization | Prove output and bounded teardown, not only completed dispatch — 12a/b |
| I12 Denoised signal contract | Versioned buffer manifest and clean guides for real noisy RT — 13d1/d2 |
| I13 RT implementation reuse | Immutable fork intake, divergence and component-license audit — 11a/13d1 |
| I14 RT scene updates | Implement missing Metal RT boundary and classify refit/rebuild — 13d1 |
| I15 Denoised acceptance | Resolve mask polarity by experiment and validate references — 13d2 |
| I16 Memory and pooling | Account shared allocations, retain resources safely and test RID reuse — 07c1 |
| I17 Compilation and warmup | Separate valid interim output, optimized readiness and shader stages — 07a1/07c1 |
| I18 Frame and latency evidence | Add OS-reported presentation IDs/timestamps with honest unknowns — 12b/c |
| I19 Export and deployment | Test fresh-profile baked/unbaked packages and older-OS loading — 11a/07c1 |
| I20 Comparable ports | Reuse proven boundaries selectively; do not import another present loop — 11a/12a/b |

Step prefixes in this table are `DT-MAC-`. This ledger owns dated evidence;
the plan owns future status. Native tests described below remain **prepared,
not executed**.

## I01 — What exists in the exact engine, and what should be reused?

**Evidence — code.** The pinned [MetalFX effect](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/effects/metal_fx.cpp)
and [Forward+ caller](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp#L2300-L2382)
already provide Spatial/Temporal dispatch. The effect blob is
`4076d0bee50470b58701db003fff4ae1a2024456`, also found in upstream snapshot
`960f4db5be16e2f1f7b46f9db7c824c2e0af1035`. That is one-file equivalence,
not a complete upstream audit. Open [PR 114670](https://github.com/godotengine/godot/pull/114670)
proposes a Forward+ custom-upscaler callback; it is not a merged presenter or
proof that public callbacks expose safe native Metal ownership.

**Change/preparation.** 11a must map creation → RD resource declaration → encoder
boundary → callback → completion/reset → disposal. Compare a pinned hook candidate
with a narrow native patch before creating another integration system.
**Test.** Build matching isolated editor/templates and capture the same official
and patched fixture. Confirm actual backend, pass placement and resource ownership;
do not attribute every engine difference to an upscaler.

## I02 — Which capability and scale limits are really queried?

**Evidence — code/contract.** Pinned [device properties](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/metal/metal_device_properties.cpp#L338-L350)
query scale bounds on macOS 14+, but use native 1–3 defaults on macOS 13.
The [driver](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/metal/rendering_device_driver_metal.cpp#L2758-L2761)
converts reciprocal upper/lower bounds into input/output ratios and integer
millionths. The [Apple descriptor](https://developer.apple.com/documentation/metalfx/mtlfxtemporalscalerdescriptor)
and [hardware table](https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)
are separate capability contracts. Neither OS nor GPU family proves allocation.

**Change/preparation.** 07a1/07b2 receipts need bound value, unit and provenance
(`device_query`, `engine_assumption`, `unavailable`), plus descriptor dimensions.
Preserve the existing millionths decoding; do not call the macOS 13 defaults
device measurements. **Test.** Each bound and ±0.000001, independently rounded X/Y
ratios, invalid/nonfinite limits and native factory outcomes. Reject an unsupported
configuration rather than silently guessing scale.

## I03 — Can a positive feature check still crash at creation?

**Evidence — code/contract.** In the [pinned creation/callback code](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/effects/metal_fx.cpp#L97-L170),
Spatial can return a wrapper containing a nil scaler, and Temporal immediately
dereferences its factory result. Apple's [factory contract](https://developer.apple.com/documentation/metalfx/mtlfxtemporalscalerdescriptor)
permits no instance. This is a source-proven unchecked path, not an observed
OpenRC crash. Nil alone does not reveal whether the cause was memory or another
internal condition.

**Change/preparation.** 07a1 must guard actual native creation, property setters
and callback entry, propagate a bounded reason/generation, and cancel failed work.
Keep feature-local recovery distinct from device-wide invalidation.
**Test.** Inject nil separately at Spatial and Temporal factories in disposable
builds; verify valid Native image, AA/jitter restoration, no stale callback and
bounded retry. Inject fatal device status separately; do not expect Native to
draw on a lost device.

## I04 — Are Temporal's motion and exposure inputs correct?

**Evidence — contract/code.** Apple's [motion scale](https://developer.apple.com/documentation/metalfx/mtlfxtemporalscalerbase/motionvectorscalex)
and [exposure input](https://developer.apple.com/documentation/metalfx/mtlfxtemporalscalerbase/exposuretexture)
define different signal units. Pinned [dispatch](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp#L2342-L2365)
uses internal-size motion scale and flipped jitter; its [motion shader](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/shaders/effects/motion_vector_inc.glsl)
derives previous UV minus current UV. A caller's reactive-format value is not
evidence that a reactive texture reaches the SDK effect. Auto exposure and a
supplied exposure texture must not be assumed equivalent.

**Change/preparation.** 07b2 needs a per-buffer manifest: producer, extent, format,
usage, current/previous direction, jitter inclusion, exposure convention and
context generation. Capture actual optional inputs, including nil exposure.
**Test.** Known signed pixel displacement, camera-only rotation/translation,
independently moving geometry, depth edges and an exposure step. Compare analytic
motion with actual texture values before judging the reconstructed image.

## I05 — Are multiple views and camera cuts isolated?

**Evidence — code.** At the pin, one [temporal context per render buffer](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp#L87-L102)
is reused by the [view loop](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp#L2342-L2365).
This creates an isolation question; source structure alone does not establish
visible corruption. Apple's [integration reference](https://github.com/apple/game-porting-toolkit/blob/main/game-porting-skills/skills/using-metalfx-temporal-upscaler/references/integration-guide.md)
identifies discontinuities requiring history reset.

**Change/preparation.** 07a2 must allocate history/reset generation per viewport
and view or explicitly reject more than one view until isolated. Ordinary camera
motion remains continuous. **Test.** Alternate contrasting left/right streams
against two independent references; reset one view only; issue two cuts before
GPU completion; destroy/recreate the viewport while old callbacks remain. A
completion may acknowledge only the generation actually encoded.

## I06 — How should AA fallback and a tiny moving aircraft be judged?

**Evidence — contract/case.** [Apple's Spatial guidance](https://developer.apple.com/videos/play/wwdc2022/10103/)
expects antialiased input. Historical [Godot issue 103782](https://github.com/godotengine/godot/issues/103782)
and [fix 103792](https://github.com/godotengine/godot/pull/103792) show Temporal
fallback could leave jitter active in Godot 4.4; this is a regression seed, not
proof the pinned engine retains that bug. The [2024 animation-blur forum discussion](https://forum.godotengine.org/t/blurriness-in-animations-3d/55008)
is subjective TAA/FSR experience, not an M1 MetalFX result.

**Change/preparation.** 07b1/b2 must restore projection jitter as well as saved
MSAA/TAA state on failure and record effective AA in every A/B role.
Prepare deterministic 1080p moving aircraft, thin gear/propeller, high-contrast
vegetation and distant 1–5-pixel-span detection cases; orientation claims must
respect the reference's actual visibility. **Test.** Compare trails, shimmer,
disappearance and landing cues across real-frame sequences and scale/base-rate
changes. Static crops cannot close moving-readability acceptance.

## I07 — Is Spatial's color mode aligned with the real pass?

**Evidence — code/contract.** Godot's [effect](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/effects/metal_fx.cpp#L110-L117)
selects Linear. Its [postprocess route](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/renderer_scene_render_rd.cpp#L689-L698)
tonemaps before the [Spatial pass](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/renderer_scene_render_rd.cpp#L782-L785).
Apple's [color-processing mode](https://developer.apple.com/documentation/metalfx/mtlfxspatialscalercolorprocessingmode)
describes input and output transfer behavior. Pass labels alone cannot prove
Linear is wrong: sRGB texture-view decoding and output HDR behavior matter.

**Change/preparation.** 07b1 records format, texture view, transfer function,
alpha representation and tone-map stage before changing descriptor mode.
**Test.** Linear/perceptual/HDR variants only with compatible actual inputs;
capture gradients, thin black/white edges, transparent composition and highlights
above 1.0. Verify pixel values, UI composition and full GPU cost. Reject unsupported
transparent viewport use until its alpha behavior is separately demonstrated.

## I08 — Which interpolation contract applies on macOS 26 versus 27?

**Evidence — contract/unresolved.** Apple's [motion convention](https://developer.apple.com/documentation/metalfx/mtlfxframeinterpolatorbase/motionvectorscalex.md)
is current-to-previous pixel displacement. [Previous-color control](https://developer.apple.com/documentation/metalfx/mtlfxframeinterpolatordescriptor/requiresprevcolortexture.md),
[world/view matrix](https://developer.apple.com/documentation/metalfx/mtlfxframeinterpolatorbase/worldtoviewmatrix.md)
and [projection matrix](https://developer.apple.com/documentation/metalfx/mtlfxframeinterpolatorbase/viewtoclipmatrix.md)
have macOS 27 availability; they cannot define a mandatory 26 path. The
[base API](https://developer.apple.com/documentation/metalfx/mtlfxframeinterpolatorbase)
does expose history reset, contradicting reference prose saying it has none.
Versioned header excerpts differ in their input-dimension wording; installed
SDK headers and API-validated scaled inputs must settle actual layout.

**Change/preparation.** 12a uses real-pair seconds, vertical FOV degrees and
explicit 26-compatible scalar projection/depth inputs. Keep previous color from
the prior interpolator encode, not an arbitrary physics frame; test skipped
encodes and reset behavior. Temporal/scaler sharing is the first integration
choice, not a universal SDK requirement. **Test.** Known midpoint motion versus
a directly rendered midpoint, non-square upscaled input, first/reset frame,
skip, cut and resize. Query each texture's usage and verify actual output.

## I09 — Can display-link and manual presentation recipes be mixed?

**Evidence — contract.** A [Metal display-link callback](https://developer.apple.com/documentation/quartzcore/cametaldisplaylinkdelegate/metaldisplaylink(_:needsupdate:))
supplies a drawable and submission deadline. Its prescribed commit/present route
does not accept arbitrary time-targeted presentation alternatives. Requested
[frame latency](https://developer.apple.com/documentation/quartzcore/cametaldisplaylink/preferredframelatency)
is not a measured bound; windowed latency can be larger. The finite layer pool
can block [drawable acquisition](https://developer.apple.com/documentation/quartzcore/cametallayer/allowsnextdrawabletimeout).

**Change/preparation.** 12b first chooses one coherent engine-owned scheduling
route: display-link-provided drawables or independently acquired timed drawables.
Do not splice both examples into one swap chain. **Test.** Actual 60/120/144 Hz,
available VRR, refresh changes, deadlines missed, minimization and drawable
exhaustion. Bind each queued/presented item to its real source pair and generation;
never display a stale generated image after its current real image. Bound waiting
and teardown even when no further display callback arrives.

## I10 — Where do UI, transparency and tone mapping belong?

**Evidence — contract/case.** Apple's [integration pipeline](https://developer.apple.com/videos/play/wwdc2025/211/)
places interpolation after tone mapping and discusses separate UI composition.
The [UI texture API](https://developer.apple.com/documentation/metalfx/mtlfxframeinterpolatorbase/uitexture)
supports a distinct overlay; decompositing precomposed UI has quality limits.
An upscaler's reactive mask does not establish an equivalent interpolator input.

**Change/preparation.** 12b chooses one route and records scene/UI producer IDs,
transfer functions, alpha convention and composition point. Keep scene history
free of HUD/cursor, and add UI exactly once to both real and generated outputs.
**Test.** Alternating real/generated captures with changing small text, translucent
HUD, cursor, letterbox edges and Retina scale. Separately test smoke, particles,
rapid bright lights and screen-space effects whose color lacks reliable depth or
motion. Double UI, brightness pumping and text interpolation are explicit failures.

## I11 — Does completed GPU work prove interpolation and safe teardown?

**Evidence — contract/case/code.** Apple's [synchronization rules](https://developer.apple.com/documentation/metal/resource-synchronization)
and [events](https://developer.apple.com/documentation/metal/about-synchronization-events)
distinguish tracked resources, fences and cross-queue dependencies. [Metal 4 begin](https://developer.apple.com/documentation/metal/mtl4commandbuffer/begincommandbuffer(allocator:options:))
clears prior command-buffer residency declarations. In [forum 840795](https://developer.apple.com/forums/thread/840795),
August 2026, an M3/26.6 no-op report and DTS's related M5 Max/26.5.1 experiment
show why completion alone is insufficient; residency and usage were material.
This does not establish an OpenRC or Metal 3 defect.

The shown [PresentThread reference](https://github.com/apple/game-porting-toolkit/blob/main/game-porting-skills/skills/using-metalfx-frame-interpolation/references/present-thread.md)
waits for capacity and omits pacing-thread shutdown in its destructor fragment.
It is not a complete drop-in lifecycle contract.

**Change/preparation.** 12a/b inventory all consumers, worker/event/drawable waits,
residency and resource retirement. **Test.** Prefill a nonzero sentinel, inspect
changed bytes and the expected midpoint image; copying current color is not
interpolation proof. Interrupt producers and pending presentation during resize,
failure and destruction; require bounded joins/cancellation and no stale callbacks.

## I12 — What signal makes denoised scaling meaningful?

**Evidence — contract/case.** Apple's [neural-rendering guidance](https://developer.apple.com/videos/play/wwdc2026/359/)
uses real noisy color with clean guides, including world-space normals and
material albedo/roughness. The [exposure texture](https://developer.apple.com/documentation/metalfx/mtlfxtemporaldenoisedscalerbase/exposuretexture.md)
and [pre-exposure](https://developer.apple.com/documentation/metalfx/mtlfxtemporaldenoisedscalerbase/preexposure.md)
need explicit, consistent interpretation. Camera-only motion cannot describe moving
or deforming surfaces. In [forum 819276](https://developer.apple.com/forums/thread/819276),
March–September 2026, DTS acknowledged a Metal 4 factory crash despite support
returning true on iPhone 15 Pro; the author later reports an iOS 27 fix. That
specific case does not prove the same failure on Mac.

**Change/preparation.** 13d1/d2 gets a versioned per-buffer manifest, debug views
and per-command-backend factory tests. **Test.** Known moving hinge plus camera,
deforming geometry, signed normal orientations and exposure transitions. Poison
one guide at a time to verify rejection/diagnosis; valid handles and a static
scene alone do not validate the signals. Reuse the command backend actually
integrated by Godot; a positive feature check never bypasses creation handling.

## I13 — Is the experimental Godot RT fork ready to adopt?

**Evidence — code/case.** The author's [warning](https://github.com/josephsmithberger/godot-metal-path-tracing)
explicitly excludes shipping. The advertised `metal_rt` ref returned 404 during
review; the inspectable sample commit is
[`eeac9e05dbff0b273b6e4c483c4675530ead992b`](https://github.com/josephsmithberger/godot-metal-path-tracing/commit/eeac9e05dbff0b273b6e4c483c4675530ead992b),
2026-07-22. Its [version](https://github.com/josephsmithberger/godot-metal-path-tracing/blob/eeac9e05dbff0b273b6e4c483c4675530ead992b/version.py)
is 4.7-rc. The [comparison](https://github.com/josephsmithberger/godot-metal-path-tracing/compare/cafc17a192acf67903910a68aeb3c076c0907a4b...eeac9e05dbff0b273b6e4c483c4675530ead992b)
is divergent: 57 ahead/3,382 behind the OpenRC engine, not a port-effort estimate.
Its [MIT root](https://github.com/josephsmithberger/godot-metal-path-tracing/blob/eeac9e05dbff0b273b6e4c483c4675530ead992b/LICENSE.txt)
does not clear every bundled component. Actual [denoised creation](https://github.com/josephsmithberger/godot-metal-path-tracing/blob/eeac9e05dbff0b273b6e4c483c4675530ead992b/servers/rendering/renderer_rd/effects/metal_fx.cpp#L283-L318)
exists, but the [scene route](https://github.com/josephsmithberger/godot-metal-path-tracing/blob/eeac9e05dbff0b273b6e4c483c4675530ead992b/servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp#L2590-L2682)
replaces opaque/motion rendering rather than adding a bounded hybrid pass.

**Change/preparation.** 11a/13d1 pin that SHA only for inspection, audit notices
and dependency/driver/shader scope, and choose minimal reusable boundaries.
**Test.** Matching patched editor/templates, raw RT and scaler execution on a real
OpenRC fixture plus disabled/M1 fallback. A stale branch name or demo screenshot
does not pass intake or integration.

## I14 — Which RT engine and geometry operations are missing?

**Evidence — code/contract.** Pinned [Metal RT methods](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/metal/rendering_device_driver_metal.cpp#L2380-L2437)
are unsupported stubs despite generic RD RT names. Apple's [refit contract](https://developer.apple.com/documentation/metal/mtlaccelerationstructurecommandencoder/refit%28sourceaccelerationstructure%3Adescriptor%3Adestinationaccelerationstructure%3Ascratchbuffer%3Ascratchbufferoffset%3A%29)
does not permit topology additions/removals; [refit usage](https://developer.apple.com/documentation/metal/mtlaccelerationstructureusage/refit)
can trade build cost for slower tracing. The fork's [material warning](https://github.com/josephsmithberger/godot-metal-path-tracing/blob/eeac9e05dbff0b273b6e4c483c4675530ead992b/servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp#L2748)
excludes transparent blending and some custom-shader features.

**Change/preparation.** 13d1 explicitly includes driver/compute traversal and
shader-lowering feasibility. Classify rigid motion as instance updates,
same-topology deformation as a refit candidate, and asset/LOD/topology replacement
as rebuild. Declare alpha/material coverage and scene-wide raster fallback.
**Test.** CPU-checked hit/miss/instance IDs through hinge motion, deformation,
add/remove/LOD and alpha cards. Record scratch/AS peak bytes, build/refit and trace
time together; repeat at least 20 ownership cycles. Do not presume refit is faster
for the complete frame or render from collision proxies silently.

## I15 — How can masks and denoised quality be verified?

**Evidence — unresolved/case.** The [strength-mask API](https://developer.apple.com/documentation/metalfx/mtlfxtemporaldenoisedscalerbase/denoisestrengthmasktexture.md)
says 1 marks ignored pixels; the [WWDC26 session](https://developer.apple.com/videos/play/wwdc2026/359/)
describes 0 as off and 1 as maximum denoising. Preserve this conflict until an
installed SDK/native experiment resolves it. The [reactive mask](https://developer.apple.com/documentation/metalfx/mtlfxtemporaldenoisedscalerbase/reactivemasktexture.md)
is a separate history control. The fork's [corruption handoff](https://github.com/josephsmithberger/godot-metal-path-tracing/blob/eeac9e05dbff0b273b6e4c483c4675530ead992b/mac-rt-planning/metal_rt_corruption_handoff.md)
reports corruption hidden by validation; [Blender WIP 160045](https://projects.blender.org/blender/blender/pulls/160045)
reports integration-specific temporal/depth/alpha concerns. Neither is a universal
SDK diagnosis.

**Change/preparation.** 13d2 freezes SDK/OS/device, raw/no-mask/0/1 split-mask
variants and validation-on/off image controls. **Test.** A noisy patch beside a
clean textured patch, independent-seed higher-SPP reference convergence, motion,
disocclusion and exposure steps. Compare regional error, temporal flicker and
trail persistence at common output dimensions with finite-value checks. A
high-SPP image is a reference candidate until convergence is checked.
Even then it is a converged in-model reference: record bounce, sampling and clamp
assumptions; increasing SPP cannot remove model/estimator bias or prove realism.

## I16 — How much memory is added, and can examples leak resources?

**Evidence — contract/case.** Apple's [working-set recommendation](https://developer.apple.com/documentation/metal/mtldevice/recommendedmaxworkingsetsize.md)
is approximate; [allocated size](https://developer.apple.com/documentation/metal/mtldevice/currentallocatedsize.md)
tracks GPU resources, not extra independent physical RAM to add to process RSS.
[Demo issue 1269](https://github.com/godotengine/godot-demo-projects/issues/1269),
2025-10-30, was initially reported as a Metal leak in 4.5.1. A maintainer identified
per-frame uniform-set allocation in the demo; [fix 1275](https://github.com/godotengine/godot-demo-projects/pull/1275)
closed the case in February 2026. It was not a proven Metal driver leak.

**Change/preparation.** 07c1 inventories unique allocations, aliases, frame-ring
depth, alignments and lifetime. One uncompressed 1920×1080 RGBA16F image is
15.82 MiB before alignment/other storage; three are 47.46 MiB. These arithmetic
estimates exclude hidden SDK history, depth/motion, masks and RT structures.
**Test.** Repeated switch/resize/Home-Fly cycles with CPU footprint, Metal allocation,
RID and OS-pressure trends; verify uniform-set/resource reuse and GPU retirement.
No fixed fraction of “VRAM” qualifies an 8 GiB unified-memory host.

## I17 — Can initialization and shader compilation hide early stalls?

**Evidence — contract.** Apple's [initialization control](https://developer.apple.com/documentation/metalfx/mtlfxtemporalscalerdescriptor/requiressynchronousinitialization?changes=la_8&language=objc)
permits a valid slower interim scaler while background optimization finishes;
synchronous initialization moves cost to creation. This is not automatically an
invalid/no-output state. Godot's [pipeline/shader-baker documentation](https://docs.godotengine.org/en/latest/tutorials/performance/pipeline_compilations.html)
separates intermediate MIL baking from device-specific final pipelines; Metal
baking requires the native supported renderer and is unavailable in headless export.

**Change/preparation.** 07a1/07c1 separate image validity, history warmup and
optimized-performance readiness. Record initialization mode/time, first usable
frame, first stable cost and cold/warm pipeline counts. Do not wait forever for
a readiness API that the SDK does not expose. **Test.** Fresh-process and warm
provider activation, sync versus async initialization outside active-flight hot
paths, and first appearance of materials/effects. Fixed warmup alone cannot prove
background optimization completed; retain that uncertainty in timing evidence.

## I18 — What did the GPU, window server and display each do?

**Evidence — contract.** [`presentedTime`](https://developer.apple.com/documentation/metal/mtldrawable/presentedtime.md)
and [`addPresentedHandler`](https://developer.apple.com/documentation/metal/mtldrawable/addpresentedhandler(_:).md)
offer OS-reported presentation feedback. Zero means not yet presented or dropped,
not definitely one of those. The [HUD](https://developer.apple.com/documentation/xcode/understanding-metal-performance-hud-metrics)
counts generated frames. [GPU/CPU timestamp conversion](https://developer.apple.com/documentation/metal/converting-gpu-timestamps-into-cpu-time)
needs calibration and can add overhead. GPU completion and a predicted display
deadline are not input-to-photon measurements.

**Change/preparation.** 12b/c bind real-render, generated-completion, scheduled
and OS-presented IDs to matched clock windows and source pairs. Missing feedback
stays unknown; teardown cannot await it indefinitely. **Test.** FG on/off at an
identical real render cap, source-tagged draws and callback coverage, compared
with an independent camera. Keep physical radio/input witness and screen response
in the same measurement; report calibration, sampling resolution and overhead.

## I19 — Can the same package launch cold and below the new API floor?

**Evidence — contract/case.** Apple's archived [weak-linking guide](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPFrameworks/Concepts/WeakLinking.html)
explains optional symbols; its old build-UI instructions are not current tooling
instructions. Godot's [macOS build guide](https://docs.godotengine.org/en/stable/engine_details/development/compiling/compiling_for_macos.html)
requires appropriate matching export targets/slices. Open [issue 124539](https://github.com/godotengine/godot/issues/124539),
opened 2026-10-16, reports a fresh-cache baked-shader crash on 4.7.0/4.7.2,
M2 Pro/macOS 26, without an attached minimal reproduction. Its proposed root
cause and applicability to 4.8-beta2 remain unconfirmed.

**Change/preparation.** 11a/07c1 add per-slice minimum-OS/load-command/weak-import
inspection (`vtool`, `otool`, `nm`) and compile-time plus runtime availability
guards. **Test.** Matching baked/unbaked exports under isolated fresh and warm
user profiles, correct real Metal export driver, current eligible OS and an
actual supported older OS. Preserve shared caches/campaigns; label driver-cache
state honestly. Do not lower compatibility by raising the app deployment floor,
and do not adopt an unconfirmed issue workaround as a global setting.

## I20 — Which comparable game ports offer useful reusable boundaries?

**Evidence — author code/docs, not OpenRC validation.** Inspectable references:
[LostOdysseyRecomp notes at ab968e46966a472008e2cd910a24a9687ccc9530](https://github.com/freefrank/LostOdysseyRecomp/blob/ab968e46966a472008e2cd910a24a9687ccc9530/docs/notes/vulkan-fg-fsr4-metalfx.md)
and [pt-pc notes at bf15693d11782d1accca44ad98b94343407c45df](https://github.com/LoreanXavier/pt-pc/blob/bf15693d11782d1accca44ad98b94343407c45df/docs/macos.md).
The former documents a macOS 26 Metal 3 FG route with conservative waits and
quality/performance limits; the latter describes a MoltenVK/Metal event bridge,
UI composition and experimental bright-effect flicker. These are architecture
leads, not permission to transplant swap chains or proof of M1 gains. Repository
metadata identifies GPL-3.0 and MIT respectively; notices and individual files
still require inspection before any code reuse. No game assets were acquired.

**Change/preparation.** 11a compares native Metal engine integration against
those boundaries; keep native Godot ownership instead of adding a Vulkan interop
bridge to solve a problem the current Metal route does not have. Read matched
input leases, reset and lifecycle designs selectively; do not copy foreign
per-frame GPU drains. **Test.** An independent minimal Godot fixture with resize,
skipped input, bright moving effects and full-resolution UI; measure event ordering,
real rate and latency before claiming a reused design helps.

## Prepared implementation handoff

The plan incorporates these results into its existing substeps. The first
implementation PR delivers source/SDK intake and pure conversion/receipt checks;
the next adds native guards and factory/input-output fault fixtures. Neither
needs to port RT or a presenter first. The unsafe baseline is never counted as
passing nil handling. Fixtures
must bind exact source/SDK/device/OS and distinguish failure, unknown and a passed
check. Proposed fixture cases and payloads are specified in the plan; none have
been executed by this research.

Highest-priority corrections are native nil handling, limit provenance, view
isolation, macOS 26-compatible interpolation fields, truthful output/presentation
observation and the RT driver's missing boundary. Independent RT and FG development
can follow that common foundation. All four features remain in scope; hardware,
image/control and release gates remain separate from research completion.
