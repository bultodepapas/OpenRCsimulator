# DT-MAC-11a / 07a1: first MetalFX implementation evidence

Started: 2026-11-14; updated 2026-11-16. Implementation and native API intake are
in progress. The later matched screen records a bounded FPS improvement; this
record does not qualify four production technologies or sustained flight performance.
The [plan](../../../plans/apple-metalfx.md) retains integration, motion, lifecycle,
latency, package and promotion gates.

## Source and host

Work started at `5e52336bf5b41e532045c8c03726518568f688b0`. Another concurrent
session incorporated prerequisite edits/plans into mixed commit
`3c0f4c07da68b383bc1cf9e0318bb7dab04e91d0`, then in-progress implementation into
`f32492c3be992376ecea9f2f2571ba4505ef3747`; this task did not create or reset
those commits. HEAD movement is not qualification. Frozen overlays have separate identities.
Vehicle-paint and rotor edits are outside this task.

Strict SSH using the existing identity/known-host entries reached ANGELA_AIR,
`MacBook-Air-de-Angela.local`, account `gius`, Apple M1, native ARM64. Observed OS:
macOS **27.0.1 / 26A434**; CLT clang **21.0.0 / clang-2100.3.34.2**; SDK **27.0 /
26A425**. The Mac was on AC. Initial inventory showed 661 MiB free; a later
inventory showed 35 GiB and the previous workspaces absent. This task did not
delete them or claim credit for that space change.

New workspace: `/Users/gius/OpenRC-m1-work/metalfx-20261114/`. Native venv uses
CPython **3.12.15 ARM64**, psutil **7.2.2**, SCons **4.10.1**, zstandard **0.25.0**.
Existing keys, authorizations and frozen campaigns were preserved. No newer Mac
was available; the second Mac's documented mDNS aliases did not resolve.

## Implemented prerequisite fixes

The resource sampler holds one supported psutil `Process` identity for the
whole interval, checks before and after reads, discards a partially read replaced
process, and uses `Popen` liveness only for owned children. The CPU wrapper keeps
one sampler across its interval. The checked runner supplies its actual owned
game/helper handles; self/attached sampling remains unowned. Public schema and
creation-time metadata remain unchanged.

Native M1 source tests passed: **27** sampler, **14** checked-runner and **22**
CPU-wrapper tests, with one Linux-only skip. The six source-file hashes are bound
in the transferred fixture manifest. A 5.5-second owned Python-child smoke
reported required resource coverage complete, helper host-state coverage complete
and runner/helper overhead separately sampled. This is apparatus evidence, not
a game workload or performance qualification.

DropPool's unchanged-output cache now includes gravity, rain, height, mesh
identity, capacity and explicit mesh generation. All current production pool
mutations invalidate it; the production writer creates a fresh mesh. The sun
glare producer reuses its already calculated daylight background and preserves
the original luminance denominator, without adding halo/aureole to it.

On the official signed ARM64 `4.8.beta2.official.cafc17a19` editor:

| Focused M1 check | Result | Scope |
| --- | --- | --- |
| `test_lens_effects.gd` | 77 checks, zero failures/errors/warnings | Reduced source fixture; includes cache invalidation controls |
| `test_sun_optics.gd` | 118 checks, zero failures/errors/warnings | Full source-packet comparisons; moon assets added after first missing-resource failure |
| `test_metalfx_policy.gd` | 120 checks, zero failures/errors/warnings | Final injected status/rollback fixture; no GPU claim |
| `test_reconstruction.gd` | 127 checks, zero failures/errors | Shared reconstruction boundary |
| `test_fsr_history.gd` | 16 checks, zero failures/errors | Existing provider reset compatibility |
| `test_reconstruction_history.gd` | 51 checks, zero failures/errors | Final 07a2 adapter: stale/coalesced receipts, real-attempt bound and paused polls |

These are checked-runner verdicts, not merely process exit codes. The reduced
fixture's broad editor import failed on unrelated glTF files whose external
binary payloads were omitted. It is not a full-project import pass. The focused
tests passed after supplying their actual moon/font dependencies. Initial policy
tests also intentionally attempted an unsupported mode under Compatibility;
the final fixture skips that real-viewport branch on an unsupported backend.

The Windows shared-host queue never launched Godot: its materialized-copy
verification found file attributes 8224 instead of 32. Its optics attempt ended
`INFRA_FAILED`; the lens request was canceled before dispatch; both confirmed
cleanup and no claims remained. No queue policy was bypassed.

## Native API observations

The [native fixture](../../../../research/engine-upgrade/metalfx/README.md) builds
against the installed Apple headers and uses Metal3 command buffers. The first
compile failed because clang did not find libc++ `<tuple>` by default. Adding
`-isystem <SDK>/usr/include/c++/v1` compiled successfully, matching the previously
recorded CLT header-layout workaround. Nothing was repaired globally.

Retained `probe-r2` source SHA-256:
`d58de090a8e7f5c05bc54f67aaaf21b0e6492f285b18c26f4d7f62872ec810c3`;
binary: `996c3e4be3c73161fe9d052c334ba177e4a5ab886aadaba89a3e0c4e638da154`.
This is a historical fixture revision; later checked-in source also validates
reciprocal integer range and matches the Godot factory's manual exposure mode.

| Effect | Actual M1 observation | Unproven |
| --- | --- | --- |
| Spatial | Supported, allocated, GPU encoded/completed, all 1920×1080 RGBA16F output components finite; uniform-color maximum absolute error 0.00390625 | Moving image, gradients/HDR range, production performance |
| Temporal | Supported and allocated; native ratio bounds 1…3, Godot encoded limits 333333…1000000; later real-engine status/readback control passed | History/reset qualification, moving imagery and product output |
| Frame interpolation | Actual encode/completion and finite uniform output; discriminating moving control remains inconclusive | Correct midpoint, production presenter and refresh pacing |
| Temporal denoised | Standalone real RT producer, native denoiser encode/completion and 1080p readback passed | Godot RT producer/consumer, moving quality and performance |

Input was 1280×720; output was the primary **1920×1080** target. Spatial used one
uniform linear frame; its isolated cold GPU duration is not an FPS benchmark.
No generated frame advanced simulation, controls or audio.

The M1 reported Apple7=true, Apple9=false and ray-tracing API support=true.
Apple's current [feature table](https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)
(October 23, 2026, page 4) still lists Apple9 for denoised upscaling. The actual
`supportsDevice`/allocation observation disagrees with that floor. The subsequent
isolated RT/denoising witness executed too; neither proves hardware ray-intersection acceleration. Eligibility
must query actual OS/symbol/device/descriptor and preserve the engine-input gate.

### RT and validation follow-up

`denoised_rt.mm` revision `d83499feba94703209c44234d450bc3a68d1598187ea788dead4e14a9fabc212`
with shader `c56cfc4af3d6745839e5d7a43386c0ebb727bf734816c05e165968bd08a572aa`
passed the native API-validation run: **911,602** independently compared primary
rays, zero hit/distance mismatches, **57,600** auxiliary samples with zero
mismatches, four denoising frames and all output components finite/non-sentinel.
Its static analytic ROI error is a loose sanity check, not a quality improvement
gate; input/output resolutions differ.

Full shader instrumentation aborted both interpolation and denoising at SDK
dispatches of 1,024 threads versus a pipeline limit of 832. The fixture's own
compute dispatches are 8×8. API-only controls completed; this does not waive the
instrumented failure or qualify all SDK shaders. Apple's
[shader validation guide](https://developer.apple.com/documentation/xcode/validating-your-apps-metal-shader-usage.md)
permits selecting individual pipelines, and
[WWDC20](https://developer.apple.com/videos/play/wwdc2020/10616/) explains that
instrumentation can change the per-pipeline thread limit.

Revision `ada4719d89f1dc68886dc8c9970bf2170842c32fb40c4256c4adf03c897e3c28`
labels the three producer pipelines. A selective run confirmed actual
`shaderValidation=1` for **trace, clear and depth**, with no shader error and the
same analytic hit/auxiliary checks passing. Compute limits were 640 and 896,
above their 64-thread dispatches. SDK internal pipelines were explicitly excluded.
The exact environment and queried pipeline states are in the result JSON.

The interpolation v2 witness
`e09248f8a7663b594f24b8e6ac519896a3fa21c248186992fcc14677bb00e5fb`
completed all seven API-only cases. Uniform passed, but positive, zero and
reversed motion all produced the same midpoint mean error, approximately 0.108987.
The explicit crossfade and endpoint controls prevent calling this correct
interpolation or a verified motion convention. Warmup and SDK-27 matrix controls
are a subsequent, separately identified experiment.

Revision `371f5f8500a724c097665f91ed0372e4a12f9849164a4c32cbd92566cfaeb438`
preserves that baseline and adds independent warmup, SDK-27 matrix, single-edge
and small-shift controls. Without warmup, the measured output equalled the current
real frame. With three additional static encodes, the complete seven-case
comparison distinguished the synthetic midpoint: input-grid motion produced zero
mean/max error, versus 0.108987 crossfade, 0.094125 zero motion and 0.245015
reversed input-grid motion. Color-grid motion gave 0.047063. Matrix-only runs
did not remove the initial endpoint output. This identifies a working warmup/input
configuration for this witness, not a universal motion convention or presentation
qualification. A separately retained D32F+S8 variant also encoded/read back the
exact synthetic midpoint; SDK usage masks were read=1 for color/depth/motion,
render-target=4 for output.

## Engine and application adapter

The [intake helper](../../../../tools/graphics/metalfx/README.md) pins official
Godot commit `cafc17a192acf67903910a68aeb3c076c0907a4b`, source ZIP SHA-256
`83cf257bc53427f2b1ea07015dbad298252c20546e916c5daa30a1cf78c45c1e`, ordered
patches and complete expected source catalog. It freezes inputs, rejects drift,
keeps pristine source separate from target build trees and records actual
toolchain/environment/artifacts. The initial thirteen intake/verifier controls
passed on Windows and native M1; later regular-file intake controls increased
that set to fifteen. Synthetic pair controls and the real pair below have
separate evidence.

The later 0001–0003 pair is now built and verified:

| Artifact | SHA-256 | Bytes |
| --- | --- | --- |
| ARM64 editor | `2718612dc289980d5c0921c561face2982c6f458109413d424f0b8a23f9ea81e` | 113,688,168 |
| ARM64 release template | `eb7fd5e5f23a622b6bd81ebdd29eac244d21cba487fd811df7282b893fb2c3b1` | 51,085,104 |

The complete 14,436-file source catalog SHA-256 is
`dc1daedbc718f6946d147efd536000c088eebbde6106a2d2bdecfe12d44b5c10`;
the frozen intake helper is
`27fdccaa46c9a7fcd27f8f98d9da86d3169d08d7004098ea3d813fdbbcc1257c`.
Later helper support for verified regular new source files is a separate revision.
Mach-O inspection reported minimum macOS 13.0 and SDK 27.0 for both binaries.
The release binary contained no fault-selector string. This does not test launch
on older macOS or certify a complete exported product.

Frozen first patch SHA-256:
`f04167e05f452bfc37e85e90d512373d92c3f6ec808cef8431a0705e197d716a`.
It guards Spatial/Temporal allocation, latches failure until reconfiguration,
fills valid targets with the existing bilinear copy on factory/enqueue failure,
handles callback ownership, and exposes viewport/generation allocation/submission
status. `enqueued` is CPU submission, not GPU execution/completion.
Six focused compiled fake-SDK/rendering checks passed; they are source controls.

The production adapter accepts only coherent current viewport, generation,
requested/configured mode and provider failures. It restores Native/AA, preserves
saved preferences and prevents Auto from immediately reselecting that failed
provider. The official engine lacks the new API and stays unknown. Final app
overlay SHA-256: `2b09286232ba478e1cb9cc8de5d3670b1684ec2b489639a7d1f0d0a957910697`.

The first full native editor build stopped before the changed rendering units:
Godot requires `zstandard` with Python below 3.14. The builder now checks and
records the pinned dependency. A fresh 0001 intake then **built successfully**,
including actual Metal driver, MetalFX and RenderingServer units. Artifact
SHA-256: `15ec647531ca59e36383e4559de6a108fba4edf7fe5789d8216ef13054d44925`,
113,671,624 bytes, ARM64. Build duration was 9m29.71s, not a runtime metric.

The real engine passed separate Mobile/Spatial and Forward+/Temporal fixtures:
created/enqueued status for the correct viewport, 1920×1080 scene readback,
resize to 1921×1081 with increasing generation, isolation from another Native
viewport, and clearing provider state on return to Native. GPU readback has
center/background sanity checks; it is not an independent per-pass GPU trace or
a product flight/physical-presentation qualification. The later 0001–0003 build
supplied the reset/fault results below.

The 07a2 patch adds actual SDK encode-call acknowledgements, per-generation
reset serials, cut coalescing, explicit multiview downgrade, lifecycle invalidation
and render-attempt evidence. The app bounds a pending reset by two observed
Temporal attempts, never wall time or paused polling. GPU completion remains
`unobserved`. Six compiled fake-render/SDK controls passed; native tests remain
separate. Final 07a2 app overlay:
`61eeb5986af5ca72181730b3ecb9f2bf21202579a215c32bb175ac64924d7879`.

0003 supplies opt-in `DEBUG_ENABLED` fault controls, excluded from release
templates. Five focused compile/preprocessor tests passed. Each native injected
case uses a fresh process and explicitly records its environment.

All four native F02 cases passed on the three-patch editor: Spatial/Temporal
factory nil and enqueue refusal. Before invoking the real application guard,
the first observed failed frame showed the changed green scene, matched a Native
reference and rejected the prior red stale image. The real guard then restored
Native at scale 1.0 and saved MSAA, kept the saved request, and blocked immediate
Auto reselection of the failed provider. No engine errors occurred; one or two
deliberate fault/fallback warnings per case were retained.

The final native history fixture
`e70f1293f29a8f157891ee94b87f8ce1cda13850e9e6035b1c6ee6aa39384c44`
passed with zero errors/warnings: two paused requests remained pending without
attempt progress, the resumed SDK callback acknowledged serial 2, resize and
camera/scenario changes invalidated old generations, same-RID setters were no-ops,
and disable/re-enable resumed safely. A direct scenario swap kept the camera
unchanged and rendered no intervening frame. An earlier fixture failed by
releasing its old World3D too soon; retaining it through the ordered server query
fixed that fixture lifetime. Receipt dictionaries are deep-copied at capture.
Pending-request destruction did not deliberately stall an in-flight GPU callback.

The four affected consumer tests passed on both the official and modified editors:
51 history, 120 policy, 127 reconstruction and 16 FSR history checks. All seventeen
unique compiled patch controls passed natively; two intentionally unused mock
variables needed `[[maybe_unused]]` under clang's release/debug branches. Actual
engine source and strict warning policy were unchanged by those test-only fixes.

The experimental scene-input patch 0004
(`2cfc1c4b466dfba51ae940d4c0529d290bf5a4502cd562d52edc4c4712e1ce18`)
also compiled in a fresh native ARM64 editor intake. Editor SHA-256:
`312892e8d53b8d5fd17ed063115e06b52bcaaf5902123d7288d3ecc47da7ba07`,
113,704,856 bytes. Its 14,438-file source catalog is
`3de40ee5b64bcc0a949a0400808dd96005cb5e3fcfa1a34a2370ff9eb1b2fd57`;
intake helper: `f659dec8be4092c20b2889d664634100449ba99bc0f8731319f28254a8399d09`.
The build took 10m34.86s and strict local code-sign verification passed.
This is compilation evidence, not a presenter or interpolation-correctness pass.

The actual 0004 engine producer fixture
`90669012f14912e202869c4739d1aa2e7235be567afcd56c2accd700f00731b7`
then passed checked parsing and a rendered Forward+/Metal run with API validation
enabled. All **2,073,600** RGBA16F pixels were finite and none retained the magenta
sentinel. Cut/toggle controls preserved the pending Temporal receipt, invalidated
the old image and resumed after the encode acknowledgement. Resize and return to
1080p passed. Orthographic, alpha geometry, Canvas/Keep backgrounds and Off refused
readback; restoring the eligible scene recovered. The SDK warmup requirement was
five encodes per epoch. Motion/depth/jitter remain unverified scene conventions;
the output is explicitly not presentable. Reports: `frame-probe-parse-upobyyv9`
and `frame-producer-native-a74si94a` under `candidate/tmp/frame-checks/`.

The first four-patch release template also built (SHA-256
`0760e39fa9255522ad5cc68ccfdb263f615dfc1dd6b79e16042d20bff8114e95`,
51,101,808 bytes). Pair verification refused different literal Python invocation
paths, although they resolved to the same venv. That refusal was retained; a fresh
template used the editor's exact invocation spelling. Its compilation completed,
but pair verification was not completed before the SSH interruption below.

## Frozen full product and normal baseline

The complete original source at `5e52336bf5b41e532045c8c03726518568f688b0`
was transferred separately from the reduced fixtures. TAR identity:
`1f9376991e574669260d976f1a54ac0cdf000c2e892c2fd3df62880d409fdfec`,
7,524,587,520 bytes. All 49,569 regular files passed per-file size/hash comparison;
the manifest SHA-256 is
`32dfc79795984139fc9283fc9e43c5903afad6515b40efa2e11678b7dbf14801`.
The twelve aircraft descriptors were current. Source remains at
`/Users/gius/OpenRC-m1-work/metalfx-product-5e52336-20261114`.

The retained, previously qualified official-engine native kernel was restored
unchanged into that source: dylib SHA-256
`b7852b6d9b8abfdd0edafb2ffd390e9d97e2666bc8cedb7b5ae8dca2451b2c25`.
Its existing marker selects official editor SHA-256
`2051c48febe532a5b156ffd8dd0c9381f74e40fde9177faff07a713851baba80`.
It does not admit either modified editor. Fresh engine-specific qualification
is required before a custom-engine native default can be issued.

A verified isolated full-product baseline imported successfully: zero errors,
eight known OBJ ambient/PBR warnings. An audio-enabled rendered debug session
then reached Home, flew the stock Ugly Stik from the runway and returned Home.
Its live log reported the admitted **native** physical backend. Actual root
render target was 1920×1080, Mobile/Metal on Apple M1, VSync enabled, scale 1.0
and saved 4× MSAA. A short diagnostic sample was about 56 real callback FPS;
cold scene/shader hitches were retained. This is a functional baseline, not a
controlled performance comparison or independently observed presentation rate.
The session stopped gracefully without a crash or leaked objects; no process
exit code was reported by the launcher.

The candidate app overlay is frozen separately:
`a7d29a2395183b1ee021b8948238879facee3df8f88ecc1d5cd6867a8dadb638`.
Only its eight app paths were applied to the unused candidate source after
checking each original against the full-source manifest. Its original research
preparation receipt is superseded; a fresh runtime preparation records the
augmented app. The baseline and its linked author assets remain unchanged.

The complete candidate imported with the four-patch editor: **zero errors** and
the same eight OBJ warnings (`frame-editor-import-mgrvd33t`). Its normal rendered,
audio-enabled route reached Home and flew the stock runway Stik. It correctly
refused the official engine's old native-kernel receipt and used reference physics.
That run cannot be a matched native-physics performance comparison. Selecting
Spatial Quality through Settings produced `spatial/created/enqueued` for the
real product viewport. Home/re-entry kept Spatial and advanced its generation
from 19 to 23. Final Home and shutdown reported `forced=false`, `crash=null` and
zero leaked objects. A saved setting's confirmation deadline and the remaining
pause menu required normal UI actions during the test; diagnostic CLI refusals
were retained. No radio was connected.

## Extension API diagnostic correction

A real custom-editor check against locked godot-cpp's full 4.7 API printed
incompatibilities but returned process exit zero. The old checked runner also
reported success because these records use `Validate extension JSON:` rather
than `ERROR:`. The original report/log remain unchanged at
`frame-editor-api47-5i877j6t`; it is **not** accepted as a compatibility pass.
The 4.7-to-4.8 differences also require an appropriate reference, separately from
the locked bindings input and numerical/native loader oracles.

The checked runner now classifies that diagnostic prefix as an error. Four
observed failure forms and an embedded non-error mention are regression controls.
Native M1 tests passed: 22 checked-runner tests (one optional real-engine matrix
skip) and 14 resource-runner tests. The new isolated Python-only regression also
passed on Windows. A broader local Windows attempt was refused by queue admission
for its Python fixtures; it did not launch Godot or qualify that suite.

The revised custom-engine identity source now creates a fresh API dump using an
independently pinned official 4.8 editor and validates the custom engine against
that reference. Both engines must first detect the same deliberately absent
class in a bounded control dump, including when the process exits zero. Fresh
dumps and selected inputs are rehashed; the locked clean 4.7 bindings input is
verified separately. Campaigns compare the full selected identity against the
installed receipt before and after execution. The source revisions are
`325dfc98bb79c354a5bfb7fda113a5309844288abc11eb1bab6fd3fd90c58068`
(`macos_engine_identity.py`) and
`505620c693fcc35c7e62ad8e99726be31eb10cd3cb5142836c9255b699694e71`
(`build_macos.py`). Portable controls and an independent source review passed;
the corrected API procedure has not yet run on the M1. No new default marker
has been issued.

The performance sampler's parallel admission change is preserved
(`session_baseline.py` SHA-256
`8dcf4569dd5ffc3519010c34478c4afb807a2d70ba6ba307b486dbacc18d72e1`).
Its fake-process unit fixtures now isolate host admission while three explicit
admission controls exercise the production gate. All 64 module tests passed on
Windows with Python 3.11.15; these tests did not launch Godot.

## RT producer port boundary

The pinned fork delta
`f50fc979dd4bc259f7f8c03fa0b2691d0932bed407fa7daab03701b7891d186f`
contains 56 format-patches. Its NVIDIA-derived base alone changes 87 renderer/
Metal-driver files and adds roughly 13,544 lines. Official beta2 already has
generic RD acceleration APIs; the Metal backend still needs the concrete
implementation plus the fork's graph/shader/renderer adaptations. Relevant owners
include `rendering_device_driver_metal.cpp`, `command_update_blas`,
`forward_clustered/render_raytracing.cpp`, `scene_shader_raytracing.cpp`,
`renderer_scene_cull.cpp` and material/mesh storage.

The fork omits unsupported geometry/material variants rather than falling back
the entire viewport. That is unsuitable for OpenRC's MultiMesh, particles, alpha
and custom shaders until coverage or whole-scene rejection is demonstrated. Its
producer is Forward+, whereas the normal ARM64 route is Mobile. The root MIT
notice is insufficient for wholesale intake: the Streamline block includes a
proprietary NVIDIA notice, and the BRDF keeps a separate Epic attribution/permission
note. The subsequent bounded backend below reuses only the needed generic RD,
shader and Metal boundaries. The whole-scene consumer still must establish
eligibility before suppressing raster, demonstrate actual guide buffers and
exercise fallback transitions. This is an implementation dependency, not M1
exclusion.

### Bounded Metal triangle-query backend

Patch 0005 SHA-256
`825920ed18b56dd3d531eda30d25ffb9da33b6becb29dd849c03073ff375e155`
adds an explicitly requested Metal 3 compute backend. It advertises only
`SUPPORTS_METAL_TRIANGLE_QUERY`, leaving general ray-query and ray-pipeline
capabilities false. `GODOT_METAL_TRIANGLE_QUERY=1` selects the experimental path
with native hazard tracking. The first supported subset is immutable opaque,
non-indexed float3 triangles, one geometry per BLAS and a nonempty build-once
TLAS with bounded instance IDs. Moving-scene update/refit support is not implied.

The implementation carries acceleration structures through both argument-buffer
and direct bindings, shader reflection/lowering and deferred GPU lifetime.
Source review found and fixed development-build AS naming, naming a missing
argument buffer, and validation of stale descriptor sets after a pipeline change.
Inactive set holes are skipped before residency tracking; the current shader's
active TLAS and child BLASes are explicitly declared resident. Nine portable
tests passed, including compiled actual-function controls and deliberate
mutations. The final test/runner source SHA-256 is
`350f17484047d176860caeca0061417da2c6e8eafc988f8ee757c5a374434067`.
Seven additional fake-runner controls passed: bounded checked evidence, exact
intentional rejections, extra shader/script errors, incomplete capture, changed
evidence, binding/GPU faults and admission refusal. Each native process now uses
the checked runner and normal host admission. Expected rejection reports retain
`ok=false` / `engine_error`; only a separate fixture verdict can accept their
exact diagnostics, never extras or an incomplete run.
The prepared fixture tests fresh processes for both binding modes. This revision
has not been compiled with Apple's Metal SDK or executed on a GPU.

### Opt-in command-buffer completion observer

Patch 0006 SHA-256
`565aec0587e8d5b8895f8e9025be316437a9cda0f7207e5c02214f0bf9cfd272`
adds an independently requested, default-off observer for Spatial, Temporal and
experimental interpolation. Ten portable tests compiled and exercised the actual
observer/header/helper and viewport/render-buffer status code with fake commands:
disabled allocation/registration, lifetime after owner retirement, errors and
reset acknowledgement, invalid/missing times, invalid callback IDs, late failure,
coherent concurrent snapshots and signed-counter exhaustion. A separate source
review found no further concrete blocker. This is source evidence; the new
`gpu_probe.gd` is unparsed and has not run on Metal.

The [engine guide](../../../../tools/graphics/metalfx/README.md#optional-gpu-completion-observation)
owns sample identity, clocks and timing limits. Observation state may allocate
before an enqueue succeeds; handler registration occurs after SDK encoding.
Command-buffer completion is distinct from the legacy CPU encode acknowledgement,
image correctness, presentation and effect-only cost. No production default or
recovery policy was changed by this observer.

### RenderingDevice denoised binding

Patch 0007 SHA-256
`d3ce4cb242eb311d214535ce695c744c2a15801b1226c940fb707b71bce64166`
adds a driver-neutral context RID interface and an availability-guarded Metal 3
SDK bridge using Godot's device/command buffer. It supplies the nine fixed guide,
exposure and output textures, finite frame parameters and explicit history reset.
Its narrow native route requires hazard tracking; imported and shared textures
are rejected. The [engine guide](../../../../tools/graphics/metalfx/README.md#experimental-rd-denoised-binding)
owns the complete contract. This is not the production scene RT consumer.

Independent review found and fixed four concrete defects: an exposure upload
could remain unsubmitted, distinct imported views could alias backing memory,
the alternative barrier-fence path could wait for an unencoded update, and a
denoiser-only graph could lack a native command buffer. The prepared real-RT
witness now produces/submits its inputs before denoising first in a fresh graph.
Sampled guides, distances and retired-context output explicitly reject NaN/Inf.
Fixture SHA-256:
`9bb9c5a961a85f27b56c930bc03a8f981d47176daef7d62793b46a3c021ba145`.

Nine portable controls passed after the final fixture correction. Test source:
`c466f421477926080fa6e118ca6f74b51488ea98a3d6ca718eea41b8b7a48d39`.
The actual patched `RenderingDevice.cpp` passed Windows GCC 15.2 C++17 syntax
checks in release and DEBUG/DEV configurations. The frozen source revision then
cleared the bounded independent review. None of these checks compiles the
Objective-C++ bridge against Apple's SDK, parses the fixture or executes Metal.

The final frozen portable patch suite passed **60 tests**. A complete fresh 1–7
intake, reconstructed from the pinned ZIP, contains 14,442 files with catalog
SHA-256 `61cdead5b912c1775251477252b71cd3ea9817c6ffdad452336e05fab2b86341`.
Its original receipt/source is retained locally under
`tmp/metalfx-stack7-intake-20261114-r1`. No native build or hardware result is
attached to this intake yet.

The corresponding tools/fixtures overlay is retained at
`tmp/metalfx-20261114/engine-stack-1234567-r2.zip`, 225,347 bytes, SHA-256
`fe8a2d010cc6ef71ef8b573ee33e4db23b244b1df2354c6aea08789c5eaf171d`.
Its 40 payload files have individual size/hash entries; manifest SHA-256:
`1eada54b4c66e4a9cb42a527e3ce2047d2b2fd34e9dbef7d59e237f2bd201de4`.
Every archived byte was read back and compared. The overlay is not a complete
product source, a compiled native engine or a renewed kernel qualification.
Runner dependencies use Git blobs from
`9d131dd94a45badf04c4066cb5ee700c2e978a19`, avoiding unrelated ongoing pool-tool
edits in the shared tree. Its checked runner has LF blob identity
`aec26b085e7fdf9b32cd539c1e8631d84edc2c9cb6ac934936f6ce35f800f66b`.
The earlier `engine-stack-1234567.zip` is superseded before native use; it captured
moving helper inputs and is retained separately.
The final suite ran from the extracted r2 overlay; all 40 recorded payloads were
rehashed unchanged after execution. Captured result:
`tmp/metalfx-20261114/stack7-frozen-portable-result.json`. The earlier combined
run passed 59 tests before the final runner admission control was added.

## Native follow-up after access recovered

The two documented M1 routes became reachable. Tests below are new runs, not
retroactive changes to the earlier pending or failing receipts. Both hosts are
MacBookAir10,1 / M1 / 8 GiB. The original host used macOS 27.0.1, SDK 27.0 and
Apple clang 2100.3.34.2. The second used macOS 27.0 (26A5425a), SDK 27.2 and
clang 2100.4.1.1. Task-owned workspaces and fresh output directories preserve
the old campaigns. Neither Mac had test-queue enrollment; occupancy was checked
before native work. These runs do not establish thermal or sustained performance.

The pinned source archive and unchanged intake helper produced two fresh native
ARM64 editors on the second M1:

| Ordered patches | Editor SHA-256 | Build log SHA-256 |
| --- | --- | --- |
| 0001–0007 | `253b8de37c267028aee81d899158cebfef48921bd54ec27864dbf1abc1f9ec95` | `1263411859a98561c2ea8aeb3e0f2ebd0ab9ea8a41547c8b1d9d6875b1142cb7` |
| 0001–0007, 0010 | `93a99f25cbcf60b5ca90ebf5b1eb691b30f64b877541f1ab09abce826ecd11f1` | `440ba7d85d676ada16f0da0c34f8789dd2f01e7d3218a68909a7d062d7d3cf2d` |

Build durations were 8m44s and 8m38s. The latter pristine source catalog is
`cf8902f8526a35c26dcb03f8d9c29f716281ca172c13791aca47ecfeafea68ad`.
The earlier seven-patch catalog remains `61cdead5…`; its native build is now
established. Neither editor has a verified matching release-template pair or
renewed native-physics qualification. SDK 27.2 does not satisfy the existing
kernel qualification's exact SDK 27.0/toolchain pins; those pins are unchanged.

The original M1 passed the checked 1920×1080 moving-quad interpolation witness
with its earlier four-patch editor. Fixture SHA-256 is
`370ff63627dc4baa4e9d5c62638dc3d2efdb01d08a16a42710d1ab3991e95408`.
Midpoint MAE was 0.004253, versus previous endpoint 0.112593, current endpoint
0.107999 and crossfade 0.107296; static calibration was 0.004771. All 2,073,600
RGBA16F output pixels were finite and none retained the sentinel. An initial run
failed only the render-count check: SubViewport's property retained UPDATE_ONCE
after backend consumption. Explicitly disabling it after frame completion and
checking two idle root frames established a single SDK submission, 22→23→23.
Image hashes stayed identical between those runs; thresholds were not retuned.
This verifies one opaque translating quad with linear tonemapping, not general
flight motion, HDR mapping, composition, OS presentation, FPS or input latency.

The seven-patch editor also passed all six native `gpu_probe.gd` cases on that
host, including Spatial, Temporal GPU reset serials, interpolation epoch changes
and observation retirement. Command-buffer timing is shared with other encoded
work; it is neither effect-only timing nor an FPS measurement.

On the second M1, the final triangle-query r3 battery passed **39 cases** using
the 0001–0007+0010 editor. Both binding modes executed actual hits/readback under
Metal API/shader validation. Rejection cases deliberately produce checked
engine-error reports; the case wrapper accepts only their exact expected
diagnostics and rejects warnings. Fixture SHA-256:
`55428cb8571005ada52f54822adf944315fcd18302e67ad70bf4af647d95cd49`.
Earlier r1/r2 failures remain retained: an empty local RD emitted
`Never signaled fence`. Patch 0010 ensures a queue-ordered command buffer exists
before encoding a non-null completion fence, including the barrier path; it
does not suppress the diagnostic or signal the event early from the CPU.
Patch SHA-256: `e72d1d5659213f34b582b2c55e88e2bf50a54c24bc38f3dc3c985130a3c063a4`.
Its three compiled controls include deliberate mutations; fake completion is not
native fault injection.

Both native denoising binding modes passed r4 with that editor, zero engine
errors and zero warnings. The fixture traced 56,568 samples with 18,336 hits and
zero analytic hit mismatches, read finite/sentinel-free 1920×1080 RGB output,
and measured loose ROI MAE 0.006505. Five accepted/encoded dispatches include
denoising first in a fresh graph; retiring the context before callback completion
preserved output validity. Fixture SHA-256:
`93ad333d91945d6a14b29ff04d3c8594bdb99eb74f683c546c271bf91c43b287`.
Earlier parse and SDK-usage failures are retained separately. The output needs
color-attachment usage as reported by this SDK. `accepted`/`encoded` remain CPU
receipts; actual readback establishes GPU execution for this witness. It does
not qualify whole-scene lighting, dynamic geometry, quality, cost or defaults.

The native process-identity policy was exercised twice with the actual original
four-patch editor and official beta2. Both rounds passed fresh API extraction
and detected the deliberately absent class; no API compatibility diagnostic was
ignored. The fresh official 4.8 API is 7,115,491 bytes, SHA-256
`f44ba46a874368b716dd7c713ffccec27afaa2dbaaf6b32b625c309524a730ba`.
Its identity overlay is `native-api-identity-r1.zip`, SHA-256
`172983105d81eb061031226756c5d50dabc4431d76f9cb3df219ac8b64f19206`.
This repairs the earlier 4.7 comparison apparatus; it does not issue a new kernel
default marker. The attempted four-patch editor/template r2 pair remains refused:
the recorded Python path spellings differ even though they resolve to one
interpreter. Preserve that refusal and use one exact absolute invocation for
future matching builds.

Patch 0012 adds Metal-only fail-stops at four RD queue-submit and two fence-wait
returns before resource/fence recycling. SHA-256:
`55c185f928b9e1d742568f3803d5bec70450177d30ddf976723f8f4197f33fdb`.
Three compiled source-bound controls passed, including ignored-error mutations
and preserving Vulkan's existing recoverable error handling. Metal's current
wait can time out after two seconds: termination can therefore mean a slow or
suspended GPU, not proven device loss. This is experimental failure behavior;
native stress, asynchronous GPU faults and recovery remain unqualified.

For presentation patch 0008 `e4b73172a8025a1702a04ee818b0e0591d68ec814610d22a6441420ebdfef18a`,
the isolated Objective-C++ bridge compiled cleanly on the original M1 with SDK
27.0, deployment floor 13.0 and availability/method-access errors enabled.
The bridge snapshot SHA-256 is
`e26b78ae7b4ce723837ffc214ec210d2b912caf602e4c8368cd669c640ae063a`;
archive `presenter-syntax-r6.zip` is
`32db9011effa343ad3fec768bf452b792d1d7cf967457891be99bbfe8278cbc0`.
Thirteen portable controls passed. This is syntax/control evidence only; the
combined engine, actual adapter and OS presentation remain open.

Retrieved raw phase-2 bundles, without images/binaries, are retained locally:

- `tmp/metalfx-20261114/retained-phase2-m1a.tar.gz`, SHA-256
  `745f0f9b8a86f245928f4696e8897b458e7ebe8097b9c3b3a50dfc32aa2878a2`:
  checked motion/GPU runs, identity tests, failed pair and early bridge syntax.
- `tmp/metalfx-20261114/retained-phase2-m1b.tar.gz`, SHA-256
  `c51362819f380611302242fba533b14648d57e7b423d55a278c23afe945fe4c2`:
  both native builds, query r1–r3, denoising r1–r4 and their exact fixture sources.

Later bridge/adapter work is not included retroactively in either bundle.

## Integrated presentation candidate

The ordered 0001–0012 candidate reconstructed 14,446 source files, catalog
SHA-256 `8313fb46102b8c8cc78b2470bf436ff00da64cb1403850b0867e86a30953b6c1`.
Its native editor build passed in a new second-M1 intake in 8m40s. The ARM64
editor is 113,873,736 bytes, SHA-256
`37f9017d5e4b34cd41a6eef2cf4401aff7284c5c970990963ce10e1ec80b10f0`;
build log SHA-256 is
`c83a7cc44c5f04afc49b0d478df5a9906c1896e57517a753d9f6a7218f0af3fb`.
Source/toolchain verification passed after the build. Both new presentation and
composition fixtures passed native checked parsing; rendered cases remain
separate results. The frozen
tools/fixtures overlay is `tmp/metalfx-20261114/engine-stack-1-12-r1.zip`,
299,993 bytes, SHA-256
`418a9d863fabd7fe0614dbd540dad51ae5f71183a796940ea0959f2c92541457`;
its 53-file manifest is
`e26aa41bc201700801ba804e8b91d1b531c85d948ae4fa24d72fc2b1d1f3e952`.
The frozen overlay passed **91 portable controls** using Windows GCC 15.2.
An initial invocation omitted the source-cache/compiler environment and failed
prerequisite discovery; the corrected run used the exact pinned archive.
These controls are source-bound simulations, not a native presentation result.

Frozen additional patches are 0008 `e4b73172…`, 0009
`5ca9396cc846a7f6b72a42f06d1785124e605e4a983e565a31cdf4273dc29333`,
0010 `e72d1d56…`, 0011
`d6ebee96e1717b7f2d6d5b3b63da82d0c3238582a9bb51bda5a749b70ff55640`
and 0012 `55c185f9…`. Bounded independent source review found no remaining
concrete blocker; it did not establish image correctness or OS timing.
The actual-pair adapter fixture is `composition_probe.gd`, SHA-256
`a6d3928563f1b34fcf45064805be3c63deb079b2be965809be3a20ceac06aa14`.
It is prepared to check generated and real OS-presented callbacks, then real-only
continuity with composition disabled; until run, these remain intended checks.

The experimental owner suppresses the boot background/logo. Cancellation prevents
new admission until an old in-gate submission exits; it is not synchronous
revocation or OS cancellation. Blocked epochs may need an explicit reset, and
200-ms retirement or Metal's two-second fence timeout can terminate the process.
These limitations, native build/fixture results and product integration remain
separate from the existing qualified native-physics default.

### Native presentation failure and bounded correction

The first 0001–0012 rendered route test passed ordinary presentation, then the
display-link real-only case timed out. A three-second native `sample` captured
the lock cycle: the display-link thread called `addPresentedHandler` while holding
the state mutex; Core Animation's presented callback needed that mutex while
holding its own lock. Metal completion callbacks also stalled, eventually
blocking the main thread's command-buffer pool. The sample is retained at
`tmp/metalfx-20261114/present-real-owner-r1.sample.txt`, SHA-256
`2c99925d5fcce1e22591aaef42facb6e7dc8c8a7ce1bfbf0074f5a5330639ca5`.
The redundant synthetic case was interrupted through the checked runner after
the first timeout; it is not a passing or completed case.

Patch 0014 moves drawable/Metal property access, encoding and handler
registration outside that callback mutex. It retains presentation/source/proof
gates and leases, then reacquires the state mutex to revalidate deadline,
cancellation, generation and scheduler reservation before accounting and
submission. The completion callback reads native status before taking the mutex.
Patch SHA-256: `a15caae49bb4d543043e009fd63a63f88c433e8d8ccbbc139ade6acf6a991468`.
Four source-bound controls passed, including a two-thread CA-lock stand-in using
the actual presented callback. Restoring the previous lock order reproduces a
bounded deadlock; the test exits deliberately without an OS crash dialog. The
controls do not model indirect native texture releases or replace native stress.

A separate APFS development clone was incrementally rebuilt, preserving the
original intake and binary. Editor SHA-256:
`1091ddaa48dddebb0b39179214c6a4c8d90a3087b13a1ab98ccdfc993486b8b7`.
This is explicitly a diagnostic build, not a fresh qualified editor/template pair.
Under Metal API validation, its real-only display-link case passed: 176 present
requests, 172 OS-presented callbacks and four unresolved requests at the sampled
instant, zero GPU failures. Callback counts are not physical scanout proof.

The offscreen composition case passed with actual 1920×1080 images. The sampled
translucent UI changed the pixel by 0.411765; saved-real and generated UI errors
against current-real were both zero. Reset/recovery, glow rejection, resize and
Off checks passed. Generated, saved-real and current-real image hashes remain
distinct in the receipt. This checks UI exactly once in that bounded scene; it
does not establish general color correctness or presentation.

Both synthetic and actual-pair presentation cases completed but failed their
generated-output requirements: 178/238 pair candidates were accepted, with zero
generated present requests or OS-presented callbacks. The actual adapter still
presented 235 real frames, and composition Off preserved real-only continuity.
Therefore neither case establishes working generated-frame presentation. Patch
0015 adds observed scheduler predicates/timestamps to distinguish proof, cadence
and deadline rejection before changing behavior; a 30-FPS request alone does not
prove the producer or display cadence.

macOS clamped these requested 1920×1080 windows to **1920×1018**, confirmed by
the window/root viewport receipts. Their presentation results are functional
diagnostics, not 1080p display qualification. The separate 1920×1080 offscreen
composition result retains its narrower image scope.

### Real completion observer and admission-policy follow-up

0013 adds opt-in real-viewport GPU completion and a separate guarded device
capability query. Frozen patch SHA-256:
`4557e956812dd07a5457763d9f59266520c39f04053ecf2977364c345c4e8cda`.
Its six portable controls passed. A development engine with canonical ordered
0001–0015 source then built and passed pre/post source verification: 14,447
files, catalog `3eaf5d41e50f293a7f62f6159ddfe1368a9e42dc700b67e2edad0c99e02f0d68`,
editor `6e9d52a7b2fcb14a24dc70e938ce478bea652aa128ced4111d448d42ca232407`.
It remains an incremental diagnostic build, without a matching qualified template.

The final 0015 diagnostic revision is
`5e1b25dc8e3296423dae24489cd8b936a6cfbaf32a0fc6b006c6bec0b1971b9d`.
It captures proof scalars once for the actual predicate, records the commit
deadline and job kind, and preserves native command status/error code on failure.
Its two compiled controls passed. The earlier native diagnostic source/patch is
retained separately in `presenter-decision-native-r1.zip`, SHA-256
`6d3fe5d8ed2e00e15db30b64e2d611a0071c2cefd0d08af57be672e707a89c59`.

The synthetic native trace observed a 0.016666625-second display period and
0.033584667-second producer interval. Its previous real target was
479646.105649625, next target 479646.138982875, CPU observation 479646.089127583
and reservation 479646.081439917. Proof matched the preceding real, but cadence
and deadline checks rejected all 176 considered decisions. The target was two
display periods after the preceding real and roughly 50 ms in the future;
comparing it with reservation plus one producer interval systematically expired
the candidate. These facts motivate an explicit bounded priming/pacing repair;
they do not justify bypassing identity, stale-work or real-priority checks.
Apple's [display-link contract](https://developer.apple.com/documentation/quartzcore/cametaldisplaylink)
separately describes callback preferences, render timing and commit-before-present.

The native 0013 fixture, SHA-256
`ffb9abaa4296f8338c30957e756a7867bf3ee0b2ad522433c8cb2825c39547be`,
passed with **3,589 assertions and zero failures** under Metal API validation.
FG, composition and Temporal were Off. It observed eight distinct successful
real completions, then reset generation 1→2 with one callback pending. The
immediate post-reset snapshot had zero stale callbacks; a later snapshot had
one stale callback and 29 fresh generation-2 samples, without resurrected old
records. Repeated enable, second-owner rejection and Off checks passed.
The capability query returned compiled/OS `yes`, device `supported` on this M1.
This is successful whole-command-buffer observation, not pixel-change or FPS
qualification. The fullscreen window and root reported 1920×1080; physical
drawable extent remains a separate presenter observation.

The pure admission candidate `f9eaaedbdd697a447b8e84015244a08132c933503cdc4231fc1c3184820e96e7`
and its test `485fcb1f00dea1ec41c2fd124413b32908072eaa101c259d5a1d9927779417cb`
passed 484 assertions both through Windows checked admission and native M1
headless execution. That revision is not connected to settings/runtime. Review
subsequently identified a bootstrap cycle in its unavailable FG-off alpha and
postprocess facts; the correction delegates dynamic eligibility to existing
per-frame renderer gates. The earlier pass remains bound to its actual bytes.

The fullscreen adapter diagnostic still reported zero generated output. One
earlier diagnostic run latched three presenter GPU failures; the later run with
native error-code observation reported zero. The earlier failures are unresolved,
not dismissed by the later zero. No generated-presentation or latency pass is
claimed from these runs.

Retrieved phase-3 evidence is
`tmp/metalfx-20261114/retained-phase3-m1b.tar.gz`, 455,613 bytes, SHA-256
`d7ffef0d8246b8d57d7bb2be6bf7d28f79a57d2c46b12723365c2d500a3764ab`.
All 59 payloads were rehashed against the archived manifest after retrieval.
It includes the full-stack build, timed-out/interrupted and corrected cases,
native sample, diagnostic build identities/inputs, observer/reset and policy runs.
Later pacing changes are not retroactively part of that bundle.

### 2026-11-15: pacing, callback lifetime and complete-app candidate

0016 (`6592562afd4208d211e924cd1330b6fb58a05d88b0161f43a51d133d6863efbe`)
adds bounded two-tick priming followed by one-tick generated/real pacing,
independent CPU freshness and OS timing bounds, and observed drawable extent.
Its native synthetic fixture presented 143 generated frames from 144 requests,
with 171 real presentation callbacks, at an actual 1920×1080 drawable. The actual
SDK adapter instead reported seven failures with native status/error both zero.
That is the recorded earlier result, not a successful SDK presentation run.

0017 (`db0f4aad4eced890cd5a072be1b69aa5ca6331d41c1a700b12a8ed967357b746`)
distinguishes callbacks for commands never requested/admitted from terminal GPU
failures, accounts each owned in-flight command once, and bounds unresolved
submission retention. The native development editor was
`64e781ef2d7fcf56a875bee9447cf2ea5f73fad64d89e18387487dc7dc3f1c6c`;
its verified 14,447-file code catalog was
`82b6b5397ce0093dafb7c255a1278649981d0c65b2a6b6caf7638618169d2ef3`.
Both fullscreen fixtures passed. Synthetic current-generation counters recorded
140 generated and 172 real presentation callbacks. The actual SDK adapter's
final generation 9 recorded one generated request/presentation and 60 real
presentations, five ignored unrequested `NotEnqueued` callbacks, zero confirmed
GPU failures, zero nonterminal owned completions and zero retained/rejected
submission leases. The observed drawable was 1920×1080, pixel format 80.
Counters reset with presenter generations; these values are not entire-run
counts or sustained product FPS. Earlier failures remain bound to their runs.

The preceding real-completion series had a complete two-second coverage window
with 60 successful command-buffer completions, no failure/overflow or pending
callback, and a maximum retained completion gap of 0.159981 seconds. This
instrumented fixture does not establish smooth flight, the policy's sustained
35-FPS recovery condition, generated FPS or physical input latency.

The frozen ordered 0001–0017 packet
`tmp/metalfx-20261114/engine-stack-1-17-r1.zip` is 352,212 bytes, SHA-256
`6eeb1ea4bb7a08a5fce77cced56949815e487c015f937b7874ce39751a97ae21`.
Its manifest is
`ce2e22da278ed2b44ca32ec927ff498d58071ebe6e84e2ab9f76a0ac7b80357f`.
All 112 portable controls passed; all 64 payloads were rehashed unchanged after
the run. The checked source includes isolated Git roots for patch compilation.

Fresh editor and release-template builds used the same absolute Python path,
SDK 27.2, Apple clang 2100.4.1.1, source catalog and ordered 17 patches on ANGEL.
Both passed source verification and `codesign --verify --strict`; the existing
helper then returned `pair_verified`:

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| ARM64 editor | 113,923,976 | `c47636a595313598a399b01ba8d550ef11409beb63b80718aa7fa8fe763bc7b7` |
| ARM64 release template | 51,305,056 | `c44d06546ebd953514be583b5195b1c0ec9a9e22eff74480d306faebf273aacb` |

Build receipt hashes are
`13fd9fc76af01032003b5c4fd1658f93787d457ed18364fae0ac1e16af7f6eb7`
and `dc8730909a5864817253ede1add9ab0ef0b9ff33429ae7b6fd24cbde70f143d5`.
This repairs the previously rejected Python-path pair; it does not qualify the
custom engine for the existing native-physics marker or public distribution.

The complete product source was frozen from
`af897f0307886eb8c3337d44d4eeb2bcddabb1e4`. Its 7,575,644,160-byte source TAR
is `3973a4b45f23dc09da9fc830458086fcbd5c27f1b17e3dba4234421a2b757cb2`.
All 51,217 extracted files (7,529,626,700 file bytes) were rehashed on ANGEL
against the retained manifest
`1d5d3340a68141a021a9d4ad349059246b59c20368004e40598800c4d838e9bf`.
An isolated clone applied only the six-file frame-generation overlay,
`989c3ca716362f61efcab20e583859f8ccbeb55f694f3ff173d2d2e40ddcc692`,
before the existing research-preparation tool made a separate runtime and unique
macOS application profile. Unrelated working-tree paints/tools were excluded.
The complete import succeeded. On the fresh final editor, checked AppRoot/main
parsing passed, followed by 498 policy, 47 controller, 127 reconstruction,
51 reconstruction-history and 24 camera-history checks with zero failures or
diagnostics. The controller includes the real Simulation pause/resume signal;
its check verifies that observing that signal advances no physics tick.

The final policy SHA-256 is
`a0e1330432d3a05fbd1b94519f35287b14273a8cd31c66c613baea6573058d34`;
controller `87c67678f15c6b3ee610048066fb729641b84188b35c49f8b5624030ae432a54`.
Their tests are respectively
`76281236dbc510a920d09dab8326627385333eae15c9c2ef6b54f96e3e267896`
and `ca80d176f4b54e1d573e84bcb567c610de787de71fe87f7a63c0436119d1c142`.
Runtime flags and current source instructions live in the
[MetalFX tool guide](../../../../tools/graphics/metalfx/README.md).
Normal launches leave the controller uninstalled. Rendered Home/Fly lifecycle,
performance/latency, supported old-OS execution and RT viewport consumption remain
separate open gates. The custom research engine currently uses reference physics;
no SDK/compiler pins or native-default qualification marker were relaxed.

On the fresh final editor, the 39 native triangle-query cases and both denoised
binding modes passed again. The GPU-observation and real-completion fixtures
also passed. The final presentation run's actual SDK adapter recorded **31
generated OS-presented drawables**, 232 real presentation callbacks and zero GPU
failures in generation 2, at an actual 1920×1080 drawable. Its synthetic control
recorded 144 generated and 170 real callbacks. These bounded fixture counts
supersede neither the earlier runs nor full-flight qualification.
Both final binaries retain a 13.0 Mach-O minimum OS, weak MetalFX framework load
and weak references to the optional display-link/interpolation/denoised classes.
This is linkage evidence; no macOS 13 execution was performed.

The complete rendered app passed Home→Fly→pause→Home with FG Off at a reported
1920×1080 window/root viewport and then shut down with zero leaked objects.
The real observer remained `not_requested`, no FG owner was installed, and Auto
selected Native. With the trial enabled but Auto still configured, it correctly
reported `temporal_active_unavailable`. One such shutdown reported four ObjectDB
instances; a later verbose trial shutdown reported zero. The earlier warning is
retained and is not declared resolved from that later zero.

The four startup environment settings do **not** override saved display settings:
AppRoot reapplies the user's reconstruction selection. Temporal was then selected
and kept through the existing Graphics settings, in the isolated research profile.
The first selection logged a **262,889.8 ms** frame with 336 new pipelines and
active `MTLCompilerService`; the confirmation deadline expired before it became
responsive, restoring Auto. A second selection with the compiled pipelines
available succeeded immediately. Metal API validation and verbose logging were
enabled. This is an observed activation stall, not a validation-free performance
measurement. Moving the confirmation deadline only after the apply call would
not necessarily cover compilation deferred to the first render; bounded
preparation/readiness and existing renderer-guard recovery need separate work.

Temporal then allocated and enqueued real full-app work. Short controller
snapshots reported 42.5 completed-real FPS in Home and 46 in flight; they are
neither paired comparisons nor sustained performance results. FG stayed
suspended. Native flight receipts exposed an actual reset-order problem:
reset 1 had already encoded before 0006 observation was enabled, so its
`reset_completed_serial` stayed zero. Later successful ordinary callbacks carry
reset serial zero and cannot prove the missed reset. The source correction and
continuous-rendering proof join are being verified separately; no completion
requirement is waived. Actual non-menu pause/resume invalidated the observation
history, and this longer trial returned Home and shut down cleanly.

Retrieved phase-4 evidence is 2,790,860 bytes, SHA-256
`4f5d667ccba3bac09415425129130d0ec397906357734f8b5abece4a3a355351`
(`tmp/metalfx-20261114/retained-phase4-m1b.tar.gz`); all 79 payloads were rehashed.
Phase 5 is 193,199 bytes, SHA-256
`e456b889770f1869e423798fa62a2acbf8fe35b034375b518afbb0fa9120166a`
(`tmp/metalfx-20261114/retained-phase5-m1b.tar.gz`); all 113 payloads were rehashed.
The latter includes the fresh native controls, Mach-O inspection, full-app
trial receipts and the activation-stall sample. Images and binaries are excluded.
A local ARM64 template ZIP reuses the pinned Godot skeleton and verified release
binary: 20,399,673 bytes,
`45e865f7214aa88f41917ef124b36f9b4ce5a0019beafb6b8b23c15111394d60`.
It is prepared export input, not a completed product package or public release.

### Native scene-input prerequisite and conditional reset

The first 0018 native build failed in Apple SDK `math.h`: its `OVERFLOW` macro
collided with the diagnostic enum. That failed source catalog and log are
retained; the copied older binary is not a successful 0018 artifact. The corrected
patch is `8339b8978c21a1133b8b6e144de0dc182a9c29a7cb39677fa628b3105dee5c82`.
Eight portable controls cover the macro, expanded indexed geometry, identity,
budgets, nested-flush reentry and deferred source retirement, with deliberate
mutations. The corrected development clone passed native compilation and source
verification against catalog
`2e9e30b41520fe6f03e0cbe70ca59891069092e42fdfb5f882d7a56091af78a4`
(14,448 files), editor
`e5228cb63665d5082c67f976cbe8ebe25cfb83ae88dabb8187cdc9ef7108f8cd`.
It is an incremental diagnostic build, distinct from the clean 17-patch pair.

Checked parsing and nine fresh Metal API-validation cases passed: Off, actual
Horizon ground, an Extra pilot mesh, offscreen geometry, source update, raw-buffer
escape, release, unsupported material and `skip_vertex_transform`. The CPU
oracle matched actual triangle/instance hit identity and distance. Ground hit
primitive 520 at distance 12.9047908783; the aircraft component hit primitive 268
at 12.3155841827, and its offscreen instance hit primitive 236 at 32.4173622131.
Update/escape returned `source_missing_or_invalidated`; unsupported shader cases
returned `unsupported_material`. No lighting, G-buffer, denoised viewport, full
aircraft coverage, FPS or 13d1 completion is implied.

The proof-join policy is now
`dc1d7736d449bc77280b04d348df91403d4267a8328102faf51b604cc0edc9fc`, test
`ab98392a566d468f17d671c32e239e49a986d40abb1e4c69da2066835d7a5ecb`.
All 517 checks passed on Windows and M1, including the exact R3 watermark/frame
shape. With the preceding 82-check controller, native R4 advanced beyond the
scaler proof gate into FG retry backoff. Home/Fly/pause/resume/Home and clean
shutdown passed, but the transient rejection cause was not retained in those
snapshots; this is not a full-flight FG pass. The current developer diagnostics
retain up to 16 state/reason transitions so the next run can distinguish the
actual renderer rejection, timeout or recovery reason.

0019 is `6a71e3e6eee7542996f52a318085f892ada178b1800c28a173129e07b500b289`.
It compares generation and requested serial and calls the existing reset path
in a single render-server transaction. Stale/absent requests have no reset side
effects. Two source-bound test groups and Metal/non-Metal translation-unit
syntax checks passed, including deliberate stale-check mutations. The latest
controller `ba9c975fa81fa1c8cc51bd19918e1095223f72eda5f4e2e9e70224f1fffb39ea`
and test `ff4357f70190524bf27dc5197a5c0d5c413e5f4ad39fb2810977f76c4abf960f`
passed 89 Windows checks. It accepts a correctly scoped newer lifetime serial,
requires actual 0006 GPU completion and requalifies the 0013 history. Absence of
the new API blocks only synthetic recovery while preserving Temporal selection.
The fresh 19-patch editor and release template subsequently built and passed
strict local signature verification and the immutable helper's pair check.
Editor SHA-256 is `8e345b212ab1612b19e67c00541a34eeae31aa43980016517e6e7b2449f2682b`;
template is `f2dfbc94195ba6bdb49b9b34090040a279cf159012e38f5155705a164f5c4e59`.
The pair binds build receipts `cea3405daebfa0a3b49fa76f5b559283923a970be5427f9668f027b321c8642a`
and `a55413475cb40d618f127d334e33fbc882580ed03c1380143d217ca0f09d5f96`.
All 89 controller and 517 policy checks passed on that native editor, with
Home/main parsing and no diagnostics. This is not a renewed native-physics
qualification of the custom engine.

The rendered history fixture `1f94f095a00b5e087dd22d604e5c586bc6d085b5236b1a8939500a18b1063527`
passed checked parsing and native 1080p execution. Both conditional cases were
actually tested, rather than skipped; the separate 0006 receipt observed a
successful reset serial 3 in viewport generation 8 / observer generation 3.
The completed command was render frame 13, ticket 1. A CPU reset receipt alone
still leaves GPU completion unobserved, and the GPU receipt is not presentation.

Full-app R5 used this editor and the current 89/517-check sources. Its bounded
transition history resolves R4's missing rejection cause: after warming up,
Home and Flight reject `transparent_geometry_has_no_motion_vectors`. The
Forward+ alpha list is nonempty and that pass strips motion-vector writes;
this does not identify a particular visible material. Shadow receivers, field
cues and the evening star field are source candidates, not proven offenders.
Home/Fly/pause/resume/Home and zero-leak teardown passed. The run did not
activate full-flight FG or establish an FPS gain. Do not remove the gate, hide
visual cues or relabel ordinary Temporal output as successful interpolation.

The R1 checkout of public commit `66145a16724d5dc05b7ef36e2450a459d14baf61`
incorrectly converted 60 CRLF working files to LF to match their raw Git blobs.
Although Git considered the result clean, it violated committed `.gitattributes`
checkout rules and the raw-byte aircraft and field pins. An R1 official-engine
companion attempt failed for those identities; the source and failure are retained.
Git object identity alone did not establish equivalent runtime input bytes.

A separate R2 checkout of the same commit and tree
`67c29504cefd89e302f439afac6049a294c056c0` restored the committed checkout
conversions with `git cat-file --filters`. All 51,213 tracked paths matched their
Git identities, status was clean, and the required raw aircraft and field hashes
were checked separately. R1 source, package and earlier trial identities are not
retrofitted with R2's result.

The existing Godot exporter also produced a local ARM64 development `.app` from
the verified 17-patch editor/template and pinned upstream template skeleton.
Its executable is
`ea45d2cd02a8cf307258ccbe456f1ed9faabd4e2eadb3630562f968c3a7adc09`;
deep/strict ad-hoc signature verification passed. The first export correctly
failed because the prepared copy lacked the sibling research probe required by
the native-kernel export plugin; an explicit verified-source link fixed the next
staging copy. This artifact contains the earlier R1 controller, not the current
0019 adapter. A first smoke incorrectly used `--script` with a release template
and timed out; it is retained as an invalid apparatus attempt, not a package
qualification. The fixed packaged diagnostic requires a pre-export Git-bound
input capture and sibling reference receipt. An archive without Git metadata
cannot satisfy that helper, and no synthetic receipt was substituted. Full
package/session and current-source export gates remain open.

The later clean 19-patch pair also produced a source-bound, ad-hoc-signed local
ARM64 development package with executable SHA-256
`f19f2d2583bf85773b91661e2317851eaea3cf3d3f35244f5f8717a3d5f4f5ee`.
Its reference receipt verified, a 10-sample reference-physics session probe
passed, and a bounded rendered quick-flight smoke exited successfully. That
package was built from the R1 checkout and therefore contains the raw-byte
companion-admission defect described above. Those smokes did not qualify the
companion route, current R2 package, native physics, performance or distribution.

### Alpha diagnostics and moving-image experiment

Optional 0020 is a diagnostic-only patch, SHA-256
`64288c65bfedd5391b0032e7ac4feddbb6bfa5a4063ca38b9a648bdff30ec09c`,
built in a development editor
`0d5f979f105476fdc27aa7dc62db135bc6bf656bad610fb347d088414ccda1c3`.
The native `frame_probe.gd` fixture passed its known viewport, base, mesh and
material RID comparisons and retained the snapshot after producer Off. Its
diagnostic-Off case correctly reported unavailable. The fixture and status are
documented in the [engine guide](../../../../tools/graphics/metalfx/README.md#optional-alpha-list-diagnostic).

The R8 Home capture held one historical page: offset 32, three entries of 35,
with `truncated=true`. The value-only scene census joined those entries to
current `NightKit/landing_lamp`, `strobe_left` and `nav_left` resource candidates
using `res://render/world/light_sprite.gdshader`. Those resource matches are not
unique historical node identity, pixel contribution, a complete list or a
flight-scene qualification. The separate flight census did not establish one.

The research-only alpha-input experiment
`06dab095ee03fe4f3a94d6efe97cdd0a1d150fda37b7673e249d06c2dc296107`
temporarily admits the unsupported input for offscreen measurement while
disabling composition/presentation for that process. Its development editor is
`68159b19306c22dae0c6b4cbc96d495a4edb9b662cb56cb97eb0087ecbd70399`;
the final motion fixture is
`dfe6a4316aaba40c5e6bd5de70fa10a52ce124e4e72ce573179ca8bb7c8a3f2a`.
The Off control passed. The enabled 1920×1080 test failed eight image gates.
Full-ROI midpoint MAE was 0.096158 for opaque motion behind static alpha and
0.112968 for alpha motion over static opaque, against the 0.04 bound. In the
latter case, distance to the Temporal endpoint crossfade was 0.0089285. That
crossfade is an approximation reconstructed from 8-bit LDR endpoints, not an
exact HDR input. The result rejects this tested path, not the Apple API in general;
keep the ordinary transparent-scene rejection.

All 21 portable engine test scripts for the normal 0001–0020 stack passed 141
tests on Windows using the dirty working-tree checked runner; its `inspect_log`
was unchanged. The separate alpha experiment was not part of that run, and
exact-candidate clone controls remain pending. These tests do not replace the
failed native image checks or demonstrate full-flight interpolation.
R8's later Home exit left four DummyAudio-related ObjectDB references despite
zero tracked Metal allocations; that teardown remains unresolved. CI run
`43691732964` exposed fixture/pin issues fixed locally. Its separate macOS source
correctness job timed out during the initial import, before native correctness
gates executed; that remains unresolved. Required CI on the corrected candidate
is pending. The frozen phase-6 archive contains 415 text
payloads and is 10,437,879 bytes, SHA-256
`3a5ddbc6a3826c189fe39a821ea0a542f08b8b0ef17110e1bdc7ac0ff2c9158f`.
The retrieved archive and all 415 individual payload hashes matched on Windows.

### Settings preview under a controlled stall

Native Settings parsing first exposed a Variant-inference error; the corrected
Settings source
`e359c4be8d8913c786b1e6ed6ab07946e61c9648d77ca8de636658ab86de3956`
and its test parsed successfully. One checked unit invocation used the wrong
required completion marker and was inconclusive; the corrected-marker Settings
unit rerun passed on the official editor. The focused display-preference suite
passed 175 checks and the renderer-guard suite passed 40; the latter retained its
intentional cannot-save warning control.

In a separate R9 1080p Home trial with FG Off on the 0020 development editor,
the test helper inserted a 20,006,315 µs main-thread delay after application of
the Temporal choice. The choose action took 30.7767 s including preparation. At
the first later snapshot the confirmation window still had 14,727 ms and Keep
was enabled. A separate, non-atomic CPU status query reported Temporal mode 4
created/enqueued in viewport generation 11.
Keep saved `metalfx_temporal_quality`, matched the draft and cleared the deadline.
After 360 Home frames the process stopped unforced with zero reported leaked
objects. This bounded test does not resolve R8's separate four-reference exit,
prove GPU completion or OS presentation, or qualify cold compilation, FPS or
latency. The local R9 command receipt is SHA-256
`3773594ba516f866965c9e1ae3d2194ce435dc763b53fe325a300e4ba838c4c7`.

The [companion behavior receipt](../../ai-companions/AFC-02/rebinds/2026-11-15-metalfx-behavior.json)
records 19 passing checked invocations on the official
`4.8.beta2.official.cafc17a19` editor, including old-manifest refusal, the
two-source `app_root.gd`/`main.gd` renewal, the other 14 unchanged source pins,
strict profiles and a strict Home/Fly/pause/restart path with three pilots. The
198-source solver identity remained
`a81c2b2d1275faba30d3e55ecca3e59cde0f005c50857fe92e48c66a2040866c`.
The retained raw runner receipt is SHA-256
`91348324618172eee459a4dc2cb13803992946af8f37f9910027a7e33e6c0d09`.
This bounded official-engine result does not qualify companions or native physics
on the custom engine and does not relax any public-distribution or native pin.

### Corrected development package and moving-instance witness

The corrected checkout uses public commit
`f5219d7d682a7f2470bbf2af88c2cf64c1fe7833`, tree
`35e5a8cf082f01c48d603820fb2f1d48c908e8f7`. It preserves committed checkout
filters, passes full Git fsck with a clean status, and matches all 16 behavior
sources. The clean 19-patch pair exported a new ARM64 development app. Its
executable SHA-256 is
`1674e23d183b126040a54132a0afa495a48246f7fd05e3fdf21890f0e993c88c`;
the source-input snapshot is
`875768f397ca77a8943b4925d38455970e64c8e58ea52d745acc8037e0c93b63`
and sibling reference receipt is
`e7a847cd8c317d66803f251e061b8a3ce67f48319e19bdc4dc1245ed2ab1e19c`.
Signature/receipt verification, a complete ten-sample reference session and a
bounded rendered quick flight requesting 1920×1080 passed; that smoke did not
record actual drawable dimensions. The custom engine correctly retains
reference-physics fallback; this does not renew native default admission.

The local ZIP is 1,608,871,093 bytes, SHA-256
`5d8d51b251edb43138f9212c51870c0287128b1b4b8bf5e99e95b94f19ab0c2b`.
The Windows transfer and its sibling receipt were independently rehashed. This
supersedes the R1 raw-checkout package for local research only. Public signing,
performance, complete-app quality and required CI remain separate gates. A later
fixed capture measured the windowed output at 1920×1018, so the requested size
does not establish 1080p qualification. That technical capture also reported four
ObjectDB references at immediate exit; it is not a zero-leak result.
The fullscreen repeat produced an actual 1920×1080 PNG, SHA-256
`4fb8181f77558e3b81d27a28fa465e95982ccd47affa49939562bd082af117e8`.
Basic visual review found a coherent field, aircraft and HUD. It also reported
four references at immediate exit. This qualifies the fixed capture's output
dimensions, not normal-flight frame pacing, interpolation or latency.

The later `capture_instance_move` fixture
`45f69ab5b9e41312840997c9189bbcb00691cb7d923bbc257d4f63456cf2df0a`
passed native parsing on the 0020 development editor. Its four-byte asynchronous
download callback ran exactly once inside the probe, after snapshot capture,
and moved the actual aircraft-component renderer instance 20 m. The old snapshot
still reported its original transform and CPU-matched hit at 12.3156 m. A fresh
query reported the moved transform and a different, CPU-matched ground hit at
18.9438 m. Both GPU results completed successfully. Aircraft and Off controls
also passed. The fixture's output has a `failures` array, not an `ok` member;
an initial coordinator asserted the wrong schema after the native case passed.
The corrected rereader validates that retained result without repeating it.

This confirms the diagnostic's historical-snapshot contract, not current-scene
validity. A future viewport consumer needs transform/material/liveness and caster
coverage checks before accepting output; 13d1 remains incomplete. The phase-7
archive contains 41 report/receipt payloads, 112,333 compressed bytes, SHA-256
`c1b1e3cbf4bf62f6359bcb9c666eacc2391e8f7361e7a502f516b023110766eb`.
Its archive and every payload matched after retrieval.

At that commit, the Linux MetalFX workflow passed all 21 scripts / 141 controls,
as did a fresh Windows sparse clone; the Windows queue workflow passed. Full
CI exposed controller failures inherited from its main-line base and 600-second
cold-import timeouts on macOS and Windows. The repairs below are prepared for a
new required workflow; the full workflow has not passed.

The six repaired controller fixtures subsequently passed on M1 with the official
editor. They update test contracts without changing the controller runtime:
connection leases, fresh calibration after reconnect, cancelled-screen disposal,
stable wizard samples and refusal atomicity. The editing-key fixture uses the
platform's actual word-delete binding; it passed 46 checks, menu routing passed
60, helicopter state passed 55 and preflight calibration passed 114. Setup and
end-to-end radio completed their full success markers. The radio fixture retained
19 ObjectDB references at exit, so this is functional evidence, not zero-leak or
physical-radio qualification. Mac orchestration and RC helper controls also
passed 4 and 11 Python/fake-process checks on M1, including the POSIX fixtures.

The inherited D11g refusal was traced to one multirotor-controller input in its
149-file inventory. A genuine last-qualified source and the candidate produced
identical named numerical/provenance fields on M1 with unchanged aircraft and
project bytes. The comparison receipt is
`5added5e9ccc592bb048ff2c21e954d2d571f1be849220ca2a9888d83f2d99cc`.
The original guard passed and the candidate correctly refused its three
historical-source leaves. The isolated renewal then passed both tools; fresh
physics-comment and project-version mutations were refused by both, and restored
checks passed. Its receipt is
`9e142a9afe162916fe525dcb7dc148e77cc114872f1e767a48bbfbcd4196dd33`.
The [D11g qualification](../../aero-consistency/D11g/README.md) owns this narrow
source qualification. Aircraft data, project settings and physics remain unchanged.

The phase-8 archive retains 93 further text reports and scripts, 8,056,127
compressed bytes, SHA-256
`d42962b62d0194a5b5905508106b8c5552fb4211bad3dac8ce74861f145b5a28`.
The archive and every payload matched after retrieval. This includes the native
renewal, controller checks and capture logs, including failed preliminary attempts.

### Requested-mode frame screen and reset diagnosis

The retained `f5219d7d` research package ran four exploratory scripted samples on
M1 using Forward+/Metal, reported 1920×1080 window/viewport dimensions, ten seconds
of warmup and thirty measured seconds each. VSync, frame cap and FG were off;
audio used Dummy. The scripted route disables physical flight and input.

| Request | Mean FPS | p95 wall frame (ms) | p99 (ms) | Observed selection |
| --- | ---: | ---: | ---: | --- |
| Native before | 38.86 | 29.612 | 35.541 | Native |
| Spatial Quality | 54.56 | 21.896 | 24.830 | Selected; effective SDK execution unknown |
| Temporal Quality | 39.00 | 29.613 | 33.497 | Native fallback |
| Native after | 39.01 | 29.511 | 36.128 | Native |

All four streams completed, drawing advanced throughout, and the existing
diagnoser found no invalid measurements or engine errors. The three non-temporal
runs each retained four ObjectDB references at exit. These dimensions are runtime
reports, not independent drawable-pixel observations for each run. This screen
does not establish active-flight performance, presentation timing, physical
latency, image quality or a sustained MetalFX speedup. Spatial's requested-mode
result cannot be attributed to verified SDK execution; the Temporal result is
explicitly Native fallback. Raw reports and verified hashes are retained locally
under `tmp/metalfx-20261114/reconstruction-screen-r1/`.

A diagnostics-only change to Reconstruction records a bounded failure reason and
whitelisted status fields using its existing status reads. Acceptance, fallback,
serial/generation checks and GPU-completion reporting are unchanged. The clean
19-patch editor passed 58 history and 124 MetalFX policy checks. A separate
source-hosted run, with an isolated profile and a route wrapper that defers the
ordinary main scene by one frame, reproduced `before_status_not_ready`: requested
mode 4, generation 10, no render buffers, provider `none`, and allocation/submission
`not_attempted`. Temporal attempts and all reset serials were zero. Its frame
report is `d92a8cd4ab61f4edf5d57d1efe259baec8513acda28ccd6ef9b25d840f142cbc`.
This diagnoses that run, not the identical packaged executable. The fallback
remains required; a fix needs a cut boundary after the affected pose and before
its next draw, with a scoped reset or proof of the generation's initial reset.
The phase-9 archive retains 45 report/script payloads, 658,493 compressed bytes,
SHA-256 `40f6e2e8a5976f718570c076699e77d9df407eb66dd44bdd0d09ba76acfdf812`;
the archive and all payloads matched after retrieval.

Required CI at `f5a0f325` subsequently reached a stale Controls dialog-label
expectation and the guarded shaft/weather publication fixture. The one-line
dialog expectation now matches the existing `Save current` label and passes the
official-engine M1 P0 suite. The publication fixture still guards 19 inputs; only
the Session pin differs. The subsequent Windows/Linux run
[`43717526635`](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43717526635)
passed both collectors at `d61eb0830227e120c64c4fc51462b9feb5052149`.
The strict packer admitted all eight captures without changing typed frames,
events, families or numerical expectations. The
[publication receipt](../../release-readiness/PT1-CI-00/publication-rebind-2026-11-15.json)
binds the independently verified artifact ZIPs and promoted source pin. Required
CI on the later integrated candidate remains separate.

### Post-pose Temporal correction and matched M1 screen

The camera rig now queues one discontinuity reason and commits it after camera
placement. Main defers that commit until crash focus has placed its final pose,
before the next draw. Existing helicopter/capture callers commit at the end of
the rig update. This covers the first updated camera/model pose; intervening
smoke, weather or other scene changes during staged loading are not independently
qualified by this correction.

The reset adapter can recognize an explicitly typed empty buffer generation
only at that post-pose boundary. Its `initial_history` receipt returns false for
explicit submission and records zero serials, no encode and GPU completion
`unobserved`; the engine's first encode must initialize history. Ordinary ready
generations retain explicit reset, scope/generation/serial checks and fallback.
The rendered screen below exercised an explicit reset, not that empty-generation
branch. Missing APIs and other unready states are not admitted by this exception.

Source was frozen tree `35e5a8cf082f01c48d603820fb2f1d48c908e8f7` at
`f5219d7d682a7f2470bbf2af88c2cf64c1fe7833` plus eight code/test overlays in
`temporal-cut-inputs-r2.zip`, SHA-256
`cf4fa2c623d205e95f5f3e3a78953728824bdba98b29d79ea1d2872265c04064`.
The three production-file SHA-256s were:

| File | Raw SHA-256 |
| --- | --- |
| `app/main.gd` | `34fb8d664902446b1292f2d5f328867f1cccd658698826fc0790888f88a41327` |
| `app/render/camera/camera_rig.gd` | `8641d0d89068fbf5b5809d2e3b480105307157faa73ddfc69c67bb41cd89ea35` |
| `app/render/reconstruction.gd` | `ea07f60c844ef0dd6b73330938d1a61471b5523100eb6672f1f71eda5496e910` |

On ANGEL (M1/8 GiB, macOS 27.0/26A5425a, AC), the unchanged clean 19-patch
editor `8e345b212ab1612b19e67c00541a34eeae31aa43980016517e6e7b2449f2682b`
passed six focused headless scripts: history 91, policy 125, camera-history 26,
camera-route 35, camera-views 152 and initial-flight-camera 16 checks, **445 total**.
Three production parses had already passed with identical source. A separate
rendered Forward+/Metal history run passed **94 checks**, zero errors/warnings,
including three additional injected-backend cold-state cases; this count does
not represent 94 native SDK/GPU checks. Its
checked report SHA-256
`3482738e4b600577b3175ae994298cd54de092d083e60bcd4607062c6dc4b0ff`.
The first history-fixture attempt printed 85/0 but emitted engine errors and was
not admitted; its deferred-tree-entry/backend fix changed only test code.

The matched screen used separate processes, the same isolated source/profile,
Forward+/Metal, reported 1920×1080 window/viewport, High scene detail with 127
detailed trees, VSync/cap/FG Off, Dummy audio, 10-second warm-up and 30-second
measurement. It used a scripted circle with physics/input disabled and a
sky-heavy pilot camera. The wrapper deferred the ordinary main scene by one
startup frame. It was source-hosted, not the older packaged executable.

| Mode, in execution order | FPS | p50 ms | p95 ms | p99 ms | Maximum ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Native before | 42.475 | 24.355 | 26.525 | 28.384 | 46.732 |
| Spatial Quality | 60.027 | 17.508 | 19.553 | 20.948 | 32.665 |
| Temporal Quality | 57.646 | 17.755 | 19.821 | 21.583 | 35.762 |
| Native after | 42.478 | 24.363 | 26.602 | 28.132 | 45.092 |

Spatial was 41.3% and Temporal 35.7% faster than the mean Native bracket in this
screen. Each mode has one sample; there is no confidence interval or sustained
flight claim. The reports estimate nominal 1280×720 input for 1080p output in
both scaler modes; these are not independently observed SDK texture dimensions.
Native/Spatial retained 4× MSAA; Temporal replaced it, so this is not equal-AA or
image-quality qualification. Even the scaler p95 exceeds 16.667 ms; these results
do not establish locked 60 FPS or eliminate stutter.

The actual `viewport_get_metalfx_gpu_status` observer sampled each mode during
and after measurement. Both scaler samples matched provider, configured mode,
viewport/observer generations and encoded/completed epochs, with successful
current-generation command-buffer completion and no first-failure ticket.
Temporal's explicit CPU requested/submitted/encoded serial 1 also had GPU
`reset_completed_serial=1` in both samples. Greatest completed tickets are not
contiguous completion counts, fences or displayed-frame FPS. The preceding R2
startup witness queried CPU status only; it is not GPU proof.

All four streams completed, draw counters advanced, the diagnoser found zero
invalid measurements and logs had zero engine errors. Spatial reported four
ObjectDB instances at shutdown; the other three runs had no warnings. A Temporal
viewport-texture readback taken after timing was actually **1920×1080**, SHA-256
`a933a39d7cae31027bc530c11e7c2df310995103eb26673c97b2e8880d0b49d3`.
It shows coherent sky/clouds/field and a small aircraft/HUD; it is not a matched
moving-image quality comparison or a physical display-presentation observation.
Other modes' dimensions are runtime reports. Physical latency, active flight,
ground-heavy workloads and endurance remain unqualified.

Phase 10 retains 206 report/input payloads, **1,779,298 compressed bytes**,
SHA-256 `ee1749f002c8babdbdc393c591229f7613a9492ad36c6b86152626440fbbec4c`;
all payload hashes matched independently after retrieval. It includes failed R1,
successful R2, the matched screen and both companion renewals. The 94-check Metal
history report was retrieved separately afterward. The corrected companion
renewal restores exact editor-import project bytes before runtime and isolates
both imports and tests; the first continuation lacked editor-import isolation
and is not admitted. Its canonical AFC receipt records the bounded qualification.

## R3 package, warm product trial and native intake follow-up

The [required CI run](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43727815769)
for `bffe0ed522efc4e0ab7336ef60d401c4cf4d712d` completed with 21 successful jobs
and five conditional skips. The final visual captures and `CI required` gate
passed. This qualifies that source's required checks, not every MetalFX product
or the later private native-integration candidate.

The R3 local ARM64 development ZIP includes that source and camera-cut fix:
1,643,422,544 bytes, SHA-256
`cd1f081c72343a3f260f36c2f6e74349dc009e05bbfeb646f09e4ceaece89ff7`.
The retrieved ZIP matched independently. Export, local signature/source receipt,
fixed-session and rendered Metal smokes passed. Its custom engine still uses
reference physics. The smoke requested a 1920×1080 window but did not establish
actual pixels; use the separate measured screen above for its scoped pixel proof.

An unwrapped release Temporal startup completed without engine errors and kept
the requested mode, but remained menu-paused with zero simulation ticks. Its
active-simulation acceptance failed. It took 330.9 seconds; a two-second native
stack sample observed render-pipeline compilation and a main-thread worker wait.
That sample does not attribute the whole delay to compilation. Cold startup,
active-flight execution and GPU completion are not established by this attempt.

A separate warm-cache, source-hosted product trial advanced simulation ticks
24 → 351, paused through the normal menu at 652, and resumed to 944. Two GPU
snapshots matched viewport generation 11 / observer generation 3, successful
completed tickets 62 and 130, and explicit requested/encoded/completed reset
serial 1. The process stopped normally with exit 0 and zero reported ObjectDB
leaks. This used an explicit after-ready reset; it is not cold-start, release,
FPS, latency or endurance qualification. A read-only postflight matched seven
source paths to the selected Git tree; only the declared research project and
export settings differed. Its receipt SHA-256 is
`b1916e65e14420ac9960ffaa9772efe3f098d081baf63c7a2521c02b23e5424d`.
Phase 12 retains 19 payloads in 196,470 compressed bytes, SHA-256
`2329b857c59e5b272b72becd4b8f9583a96833da9c6523910031a888d06c9435`;
all retrieved payload hashes matched. The separate postflight is not in that archive.

Native integration draft `90c1e2e3fc1d00da5df28ea49be7ce039abe8e65`
(tree `b7b949fd9efa678b7293fea7005c857220187bac`) adds explicit, independent
native and engine toolchain profiles for Apple clang 2100.4.1.1 / SDK 27.2.
The legacy profile remains the default. All 189 focused portable controls passed
on ANGEL after fixture paths were resolved before constructing their identities;
the initial `/var` versus `/private/var` fixture failures are retained. The proposed
package-specific automatic-admission route remains disabled and lacks its final
producer, packaged consumers/replay and performance qualification.

A separate source correctness suite subsequently passed on the same M1 with the
official ARM64 editor and explicitly selected native clang 2100.4.1.1 / SDK 27.2,
in 1,345.75 seconds. Both native builds completed with local ad-hoc signatures;
all 17 positive oracle rows passed and the separate mutation control was detected.
FPCR and native array-domain guard controls passed. Production-path native stage, lifecycle and exact
replay passed 97, 343 and 190 checks, with explicit native execution markers.
The candidate dylib SHA-256 is
`06f301e2c1a40d6a58c0e7de57882df263adcdc90f19cd93c317eab5a02b306c`.
This is official-engine source correctness, not custom-engine, fleet, performance
or automatic-default qualification. The initial official standalone-executable
copy was killed by macOS; the admitted run copied and verified the complete
signed bundle before adding its isolated editor marker. The task environment
also needed the existing pinned psutil 7.2.2 dependency; earlier failed attempts
are retained.

The real `NativeStage._macos_package_source_error` consumer also passed a bounded
19-check receipt fixture on M1: the independently verified package/row was
accepted and a changed row, unverified package and wrong kind were refused.
Its other parse dependencies are explicit stubs; no extension or release-template
execution is claimed. The Windows MCP attempt failed before source freezing,
and the CLI fallback froze its source but waited for an offline authority. Those
attempts do not establish a Windows test pass. Phase 13 retains 175 payloads,
7,699,113 compressed bytes, SHA-256
`752146aba405bf03ec33a8fffb92c3e0b0880dad78755b50b70e821f898619d8`;
every retrieved payload hash matched independently.

The actual clean19 custom-engine intake then refused its API compatibility
control. The official engine detected only the deliberately missing class;
the custom engine also reported 15 pre-existing RT method metadata changes:
geometry offsets/counts/stride, instance ID/mask and `tlas_create` capacity changed
from uint32/uint8 to int64 in patch 0005. Both validators exited zero, demonstrating
why diagnostic inspection is required. Raw stdout/stderr and inputs remain in
`native-api-control-diagnostic-r1` under ANGEL's task root. This blocked combined
custom-engine/native-physics correctness until the upstream ABI repair below.
The earlier clean19
scaler/SDK observations remain scoped to that engine; they do not prove native
extension compatibility.

Additive patch `0021-metal-rt-extension-abi.patch` is prepared after frozen
0001–0019, excluding optional 0020. It restores actual unsigned-facing methods
and routes wide script/ptrcall integers through the existing checked paths.
Five source/catalog controls passed. Fresh editor/template builds through the
unchanged intake/build helper then passed pair verification in 1,618.51 seconds.
The editor SHA-256 is
`465227d92ac1696cd338d7d17ff2204ae662c51164fb10ae9e558d46c40689a4`;
the release template is
`c93f89c7949fd1c26fe9451b1b47711d73680fb4f1c8f686f65c928752c7cfb2`.
Both use the exact 0001–0019+0021 sequence, excluding optional 0020. The editor
passed the unchanged full official 4.8 API validator without diagnostics; both
engines detected the deliberately missing-class control. The official API dump
SHA-256 is `f44ba46a874368b716dd7c713ffccec27afaa2dbaaf6b32b625c309524a730ba`.

A separate diagnostic GDExtension and the existing checked Metal runner passed
42 fresh processes: 34 raw ptrcall cases and eight explicit `Object.call` cases,
across argument-buffer and direct binding modes. The original typed probe also
passed all 39 planned processes, including feature-off, hit/readback and rejection
controls. Invalid-width inputs still reach the intended BLAS/TLAS refusal; getter
casts alone are not proof. Intentional engine-error cases retain their failing
checked verdicts and are accepted only by the existing exact-diagnostic policy.
These 81 processes are API/query correctness evidence, not 81 flight or rendered
quality/performance samples. The auxiliary build's first validation used the
kernel translation-unit roster and was refused; a separate validation declared
the actual witness source and retained all compiler/SDK/FP checks, preserving
the original attempt. No kernel build was qualified by that auxiliary receipt.

The release-only export-template ZIP is 20,412,246 bytes, SHA-256
`244bf295bd0799f67d23fb7fd2b7d16f350923057713355515f3f6e359bdcc7e`.
Its release member matches the verified template; four skeleton members match
the pinned upstream archive. Phase 14 retains 234 payloads in 21,254,403 compressed
bytes, SHA-256
`102cefaf2a7f5e5163dbe20f3f6fca8e16d156ae39f150cedcc33c38ccc14f9c`;
all retrieved payload hashes matched independently. This does not retroactively
upgrade the clean19 R3 application ZIP or qualify a native-physics package.

The separate pair/ZIP binding producer passed 13 synthetic controls and source
review. Its export integration passed 14 existing and 12 focused Python controls;
native export/PCK/receipt qualification remains pending. Combined private source
`d53afebd7e8935ee7ee30cdaf681c7f190fdf1ff` passed 39 producer controls,
seven actual script parses and six focused startup/log/replay scripts on the
new editor, using a declared warm import cache and isolated research profile.
It is not packaged execution or native replay qualification. The subsequent
`b4442e6a86b58489d67683f56f39623353480a0d` correction rejects a non-string backend
before checkpoint creation. Eight script parses and six focused scripts pass,
including 4,417 flight-log checks. The actual receipt/cache consumer passes 35
checks in a disposable project. A separate editor-plugin entry runs all eight
export-preset checks and closes normally with zero errors or warnings; the
earlier `--editor --script` attempt leaked editor resources and remains failed.

The complete custom-engine native correctness battery then passed on that exact
`b4442e6a` source in 1,544.2 seconds: 17 positive oracle rows, detected mutation,
FPCR/domain controls, and installed production-path stage (97), lifecycle (343)
and exact replay (210) checks. The native dylib is
`3b1549091e1319d1f646e2cf19f53f73824e8aea5d307023f37be294e43a8b31`.
Phase 15 retains 277 payloads in 7,099,849 compressed bytes, SHA-256
`bde6551fe713cc92d3b78a556991431e6e8c88a03030163cf1964d72be81bd94`;
every retrieved payload was independently rehashed. This closes source
correctness for the repaired engine, not release-package or automatic-default
qualification. Later pair/export/measurement tooling passed 122 portable
controls on M1; these do not change the qualified runtime or mirrored sources.
The later main branch lake/contact changes require fresh source-bound native
qualification; these results remain specific to `b4442e6a`.

The actual new editor/template/ZIP binding passes with independently retained
phase-14 pins. The signed executable comparison now uses complete disposable
copies: remove signatures, apply the same fixed ad-hoc signature, then compare
full sizes and SHA-256. Signature removal alone left two differing bytes in
`__LINKEDIT` sizing; no byte region is masked. On M1, the integrated helper
accepts the existing clean19 app and a separately signed copy of template21,
returns stable repeated proofs, and rejects both a code-byte mutation and a
different selected engine. Original files remain unchanged. The template21
copy is not an exported application; actual paired package execution remains open.

The custom-release CPU measurement lane has 73 passing portable controls,
including real pair/package/receipt readers with simulated host operations.
It independently pins the final signed executable, PCK, both receipts and
checked export evidence, and rechecks the executable/template binding. Its
output is callback time per tick and the reference/native ratio, not FPS.

## Actual paired native package and companion rebind (2026-11-15)

The merged runtime at `f99761a7ffe7be2d3851b6b815bd0914419a882b` passes
the 17 positive native oracles, required mutation, FPCR/domain controls and
650 installed stage/lifecycle/replay checks with the 1–19+21 custom editor.
Its native dylib is `ccb90f962583062bde0bab7ddf658c333b690074a245d42fdb48113f570d13e7`.
The later `a5bf3e0c5277d2ad977f74f1fe2bdb9db72f3de9` changes the prepared-export
tooling while preserving that application and mirrored native source.

The actual ARM64 template-release app at `a5bf3e0c` passes checked export,
both endpoint project proofs, exact signed-template binding, strict ad-hoc
signatures and linked reference/native receipts. Executable SHA-256:
`6cd60576161531ae194df8451eb2e20f3a4d519dae1f4d24c687e224f924d6f3`;
PCK: `5343f1b6e4fe051af626fce6d9e53d74dae09f009224ca2ba2c0ca760df36aeb`.
Actual package tests pass stage (97), lifecycle (343) and replay (211), with
`preloaded=false`. The two short fixed sessions each complete 24 warmup and
240 sample ticks with the requested backend; their state fingerprints match.
All five checked processes exit cleanly with zero diagnosed errors or warnings.

Lifecycle takes 1,381.49 seconds and replay 1,335.77 seconds. These are diagnostic
durations with other task work possible, not controlled performance results.
The source shows repeated full-bundle SHA-256 walks at preparation and replay
boundaries. Its default bundled PSA configuration selects generic SHA-256.
Additive optional 0024 enables the vendor ARM implementation on the verified
macOS ARM64 target; its fresh pair, timing and renewed package gates remain open.
No freshness check is removed. Ordinary 1080p active-flight, sustained FPS,
latency/endurance and automatic package default qualification remain open.

CI exposed the stale normalized companion solver pin. A full-baseline comparison
on the pinned official ARM64 editor replays all nine retained tapes: each has
2,881 rows and byte-identical baseline/candidate CSVs. `e7715a841eb188d089095bcdd1a70a0b6242a476`
promotes only the profile, qualification and generated nine-tape receipt to
`2fbe337732bd1a2a42e43fa7fd0a7126d0fd7d765cd8a0c050e95618c9076d37`.
The behavior manifest and 19 publication fixture pins stay unchanged. Earlier
missing-history/resource preparation failures remain retained; they did not
establish behavior parity. The app must be re-exported to include this profile.

Phase 17 retains 205 payloads in 36,709,510 compressed bytes, SHA-256
`cb4ccbc1e0431f1f0300f0509e8e5fa343452ea3aab11c3ad66fc46a72e39f8a`;
every retrieved payload was independently rehashed. The original complete PCK
stays on the M1; this bounded archive retains its signed inventory and hash.
The old R3 ZIP still contains the clean19/reference package. Public Developer ID
distribution remains deferred. The new host's explicit battery/production-trim
options require a new export and runtime evidence; portable controls alone do
not upgrade either retained package.

## ARM SHA-256 native pair and controlled file comparison (2026-11-15)

The separately built 1–19+21+24 pair has editor
`81dcaa54eb0f2e0fed6f0f9ea21fb92c346bf7533b4426733ccf37f605c31c36`
and template
`c64949fa4c95c956a42e9dbe176eba2b2297bf67eae40e2cb6ce74b3cfc8324b`.
Its five-member export ZIP is
`f485ea80cdf0914c4697fa852a850541cbed663495a96cdd253d9bffed8d4f75`.
Fresh intake/catalog, matched toolchain/flags, actual ARM64 builds and pair
verification pass. The two SHA object files are byte-identical and each contains
224 ARM SHA-256 instructions. The 25 runtime vectors and changed-byte negative
pass on the new editor. The unchanged full official extension API validator and
both missing-class controls pass. This does not qualify the new native physics
installation or a new application package.

The complete old/new patched catalogs differ only at
`thirdparty/mbedtls/godot/godot_psa_config.h`; build flags and toolchain agree
apart from build concurrency. On ANGEL/M1 with AC, no competing compiler/Godot
process, warm file cache, no recorded thermal/performance warning, and interleaved
old/new/new/old/old/new order, all six independently checked PCK hashes agree.
The unchanged PCK is 2,484,244,643 bytes, SHA-256
`5343f1b6e4fe051af626fce6d9e53d74dae09f009224ca2ba2c0ca760df36aeb`.
Old call times: 7.748414, 7.747382 and 7.752921 s. New: 1.590479, 1.583107 and
1.583237 s. Medians are 7.748414 vs 1.583237 s: 4.894× faster, about 79.6% less
time in that file-hash call. Timing excludes fixture setup, process startup and
other package checks. End-to-end startup, flight CPU/FPS, stutter, latency and
automatic default remain unqualified for the new pair.

The explicit release battery/trim implementation at `2ac2f8ce` passes 75 Python
tests with one platform skip and 111 actual launch/parser checks on both the
pinned official and new custom editor. The first parser receipt is correctly
failed only because its coordinator required the wrong completion text; it
exited zero with 111 passing checks. The corrected required-text runs pass with
zero diagnosed errors/warnings. An actual new package still must exercise the
production 0.5-throttle and battery options.

Phase 18 retains 205 payloads, 102,467,081 compressed bytes, SHA-256
`c8fd9e76181487896d45eeb525e244c9d1f0ea7a24e8e018cdd221bdaef4c715`.
All retrieved payloads, including both engine binaries, the template ZIP,
instruction dumps, checked hash runs and launch/API records, are independently
rehashed. New binding pins are selected from those retained bytes before any
package binding. The existing a5 development app and R3 ZIP stay unchanged.

## Engine24 actual package and direct-flight observer (2026-11-15)

Source `94d566a7303cf80931b1c977044bd74db2d0fe83` passes the 17 positive
native oracles, detected mutant, FPCR/domain controls and 650 installed checks
with editor `81dcaa54eb0f2e0fed6f0f9ea21fb92c346bf7533b4426733ccf37f605c31c36`.
The native library is `e79aedd42bfa960eefb3f08749c4d02d3969f27f8f786655b60ff22c93d25fe5`.
Phase 19 retains 248 payloads / 7,521,935 compressed bytes, SHA-256
`e09e1fe402628f6d2b3d6bdb1bde625b692cf9c3aa2f6ab5c750943d586416d0`;
every retrieved payload independently rehashes. The final export preset was frozen
before the oracles and preserved through export.

The matching app at `ANGEL:metalfx-stack7-20261114/native24-development-r2`
passes checked prepared export, unchanged endpoint proofs, strict local ad-hoc
signature and both linked package receipts. Its executable SHA-256 is
`46d72247991fe0a1feaac9437917cca7ea4d1471f05964f7cdcbcac865732063`, PCK
`79c850aadfc3a67bd5085e32decec1895578418f4f3a3583b6fc3be641641bbc`, and native
manifest `bb9ec8f4158a84d0ed4b1399b278f0846c846fe358a18c2cd06798063b361f71`.
All five actual release checks pass: stage 97, lifecycle 343, replay 211, and short
reference/native sessions with explicit ideal battery and production trim. The
existing session reader validates both reports and equal fingerprints. These are
functional checks; the later quiet-host three-pair CPU campaign is separate.
Public Developer ID distribution and automatic default remain deferred/unqualified.

Phase 20 retains 60 payloads / 20,827,507 compressed bytes, SHA-256
`10e9871e73d1539a37eeaf01338059ff1c3eec821452686de2f8d99531d9abd4`.
All 60 retrieved payloads independently rehash, including actual executable/library,
signature metadata, export reports/logs and receipts. The large PCK stays in the
unchanged signed M1 bundle. Release diagnostics are retained separately from this
package-provenance snapshot.

The next application overlay adds the opt-in fixed direct-flight observer and
strict frame/health/resource reducer. Its reviewed patch is
`e6a9b272294dfbd91d7b388623b4a65989043d6a6a51c0d2d505e86662309fd4`.
Actual pinned-official Godot parsing on the M1 reports no new-file findings and
only 11 existing Main warnings. The revised 30-check fixture passes, including
real Viewport delivery of V/Z change-and-restore events and disabled input-watch
ownership rejection; 18 Python reducer controls pass. Native-generated UID bytes
are compared before integration. Raw proof remains under `package-live-controls-r4`
on that M1. The prior 13-check proof in phase 20 is not relabeled as this revision.
The observer's new source still needs its own package and actual flight run.

The separate compute-primary draft's exact shader
`568ce48208c5335c80666f082ba6f93c7581ffeeeeff2a4214d9de68d643ab66` compiles
and creates a local Metal pipeline on M1 with API validation. Clean environment
correctly refuses the missing triangle-query opt-in. This is not dispatch or
viewport/SDK qualification. The universal guide gate stays closed; raster-command
provenance, geometric-versus-smooth shading and custom-bound/depth counterexamples
remain explicit review findings. Draft engine patches are not part of this app.

## Actual release CPU pairs and observer admission (2026-11-15)

The locally signed source `94d566a7` / 1–19+21+24 package passes all five
release diagnostics: 97 stage checks, 343 lifecycle checks, 211 replay checks,
and reference/native short sessions with explicit ideal battery and production
trim. The executable is
`46d72247991fe0a1feaac9437917cca7ea4d1471f05964f7cdcbcac865732063`;
PCK `79c850aadfc3a67bd5085e32decec1895578418f4f3a3583b6fc3be641641bbc`.
This is a separate development app; the old R3 ZIP remains unchanged.

Three alternating reference/native CPU pairs run in that actual release app on
ANGEL/M1 with AC and no competing compiler or Godot process. Each run has
2,400 warmup and 14,400 sampled ticks, production 0.5-throttle trim and ideal
battery. All six finish and share state fingerprint
`e5d0acfb1ab13f3182d04a71f9bc117ba39ae25fa2140a4652c43bfdaa9b0665`.
All 16,801 state boundaries and 33,601 domain checks pass per run; native runs
record 67,200 stage calls and 16,800 contexts. Raw arrays are retained and their
means independently recomputed.

| Pair | Reference callback µs/tick | Native callback µs/tick | Reference complete window µs/tick | Native complete window µs/tick |
| --- | ---: | ---: | ---: | ---: |
| 1 | 437.416250 | 290.594722 | 442.967917 | 380.142292 |
| 2 | 445.042847 | 295.638056 | 450.698333 | 386.327222 |
| 3 | 437.329653 | 297.798194 | 442.864028 | 388.981528 |

The median paired callback ratio is 1.505245×, saving 33.5656% callback time.
That callback excludes fingerprint/domain observers. Complete headless sample
windows include those observers and save 12.17–14.28% (median ratio 1.165269×).
Neither measurement establishes whole-game CPU, rendered FPS, stutter or latency.
Phase 21 retains 78 payloads, 381,882 compressed bytes, archive SHA-256
`87ee80fe146f723129f917f6be811bd24e8c2bcd09284a1cf74e42e6b6a2cf89`.
All are independently rehashed, including the revised 30-check observer fixture.

Adding the packaged-flight observer changes Main without changing the simulation
solver fingerprint. CI correctly refuses its stale companion behavior pin. A
fresh candidate at source `1e53d2d0` updates only that pin and the profile's manifest
digest through the existing qualification helper. All 19 official-engine stages
pass on M1, including profiles, manager, airspace, lifecycle, observation, timing,
presentation, session, restore, frame-generation policy and strict shell. The
first attempt failed because two tracked sibling authoring JSON files were absent
from the isolated test environment; the retained retry restores their exact bytes.
No failures are suppressed. Checked reports and before/after bounded inputs agree.
The qualified manifest is
`78057d5e178bbf6268fda791a1ddfb5dd6355574ead5c7f7f889b0f2d7b462a3`;
profile `34a74eed643d18864d7ff94b30ba33c0545e6ae26b05f011851c95b579d1bc56`.

Phase 22 retains 203 payloads, 128,120,424 compressed bytes, archive SHA-256
`fe48184b2c1ff2ba4531d0fa64f8a99b0a0a70ffa5dd3cdac336148c19c040c4`.
All payloads and the 19 checked-stage outcomes independently verify. This proves
official-engine behavior admission only: the current runtime comparison still
refuses the custom engine. A narrow explicit admission and checks on both engines
remain necessary. The source-1e53 native qualification coordinator was stopped
with return code -15 after this stale pin was found; its partial work is retained
and is not counted as a new 650-check result. A fresh final source qualification,
export and active-flight 1080p/pacing evidence remain open before default promotion.

## Scoped custom-engine companion admission and drawable preparation (2026-11-15)

The v2 aircraft profile retains its primary official engine pin and adds an
optional exact `additional_runtime_qualification` object for
`4.8.beta2.openrc_metalfx.unknown`, macOS/arm64, under the same narrow aircraft
profile restrictions. Unknown or malformed declarations fail closed. Legacy v2
profiles without the declaration remain supported on the official engine. The
existing strict JSON parser rejects duplicate keys. Profile identity records the
actual accepted runtime; saved requests survive an unavailable runtime while the
effective roster is suppressed. This is functional metadata admission, not an
executable attestation or cross-engine exact-replay policy change.

The six-file candidate passes 15 portable source/data controls, 15 native-runner
controls and independent source review. Two separate APFS COW workspaces and user
profiles run 20 checked stages each on ANGEL/M1: the previous 19 plus focused
configuration controls. Both exact editors pass current Stik/Club profile
validation, the actual runtime qualification marker and strict Home shell markers
for three real AI pilots, Pause and Restart. A successful unqualified-engine
no-fleet branch cannot satisfy those markers. The stale behavior-source refusal
is checked before installing the two renewed admission files. Original source,
bounded clone inputs, authoring assets, cache metadata and engines pass postflight.

| Runtime | Actual editor SHA-256 | Checks | Runner receipt SHA-256 |
| --- | --- | ---: | --- |
| Official beta2 | `2051c48febe532a5b156ffd8dd0c9381f74e40fde9177faff07a713851baba80` | 20 | `50523e605bf14cd30681fdbad1c85bc711f533f8a235b5940d3b1643713aa782` |
| Custom24 | `81dcaa54eb0f2e0fed6f0f9ea21fb92c346bf7533b4426733ccf37f605c31c36` | 20 | `79c45cc92cdb5499547081dd47d121afbd79f6ee745e3b41445e3ee35af2d8e0` |

These are native CPU/source functional checks using headless rendering and Dummy
audio. They do not establish rendered fleet quality, audio shutdown, release
native-physics integration or performance. The manifest is
`ff1da6295fd0049926498533b48ea3d66cbb856af23ffec1376f958d592d6b61`;
profile `e5aa95afc04676b293322526d1f7cdea660e2abdd556a4c0f7c7108ef9e94728`.
The simulation solver fingerprint is unchanged.

Optional engine patch 0025 adds an explicitly enabled ordinary main-window
drawable acquisition receipt. Four portable tracker/source controls and rejecting
mutants pass; independent source review and exact patched catalog reconstruction
pass. It remains off by default and does not add the private RT-view, shared
argument-buffer or trial gate patches. A fresh editor/template pair, API controls,
actual flag-off/ordinary/scope/incompatible-owner checks and package rebinding
remain pending. Texture acquisition is distinct from GPU completion, presentation
and scanout. The [intake guide](../../../../tools/graphics/metalfx/README.md#ordinary-drawable-acquisition-observation)
owns its exact ordered selection and commands.

The private RT-view experiment now admits its literal opaque material after a
four-byte whitespace correction. A native closed-gate test observes alpha and
invalid-environment refusal and restoration with scene epoch zero and no denoiser
allocation. A separate disposable gate override reaches scaler creation but
fails synchronous native texture validation before any accepted/encoded/consumer
work. A diagnostic proves output slot 8 has usage 3 while the SDK requires 7,
missing render-target bit 4; device, format, dimensions, sample/mip count and
private storage match. Its saved 1920×1080 image is raster fallback, not SDK
output. The product gate remains closed while the allocation is corrected.

Phase 23 retains 251 payloads, 1,241,622 compressed bytes, archive SHA-256
`8f6de0943128c8bc889c14e5419341729730ae8acad2a7d8e6a846b6ef964f1b`.
All payloads independently rehash; all 40 checked reports and logs validate with
zero errors, and both installed six-file candidates match the reviewed overlay.
It retains the failed RT attempt and its diagnostic as failures. Only regenerable
`.o`/`.a` outputs from eight retired build caches were removed to recover about
2.8 GiB; final engine and receipt hashes were verified unchanged. Current native
source/export, acquired 1080p active flight, pacing and automatic-default gates
remain open. The old R3 ZIP remains unchanged.

## Fresh pair, drawable and bounded RT follow-up (2026-11-16)

The fresh 1–19+21+24+25 pair uses the same pinned archive, SDK, compiler and
flags as pair24. Editor SHA-256 is
`8d8b76858e61c899fccf3fa4947b31e5679e8cfa27ecdb51edf7de47749f92c6`;
release template `eeaece65c7dbf67b922d22c5f112a63f5f923977a28dc15526f3263bd0194453`.
Pair receipt `2598d9870c7d34d6e13a9614124cc2a4cd19c02921c05fa8d66bccb389f4a748`
binds both fresh builds. The unchanged official extension API passes on both
editors, both missing-class controls are detected, and 25 runtime SHA-vector
controls pass. A pair/API pass does not qualify a native physics package.

The first ordinary window request acquired 1920×1018, despite requesting
1920×1080. A fresh display inventory reports a 1920×1080 screen; the calibrated
fullscreen control then acquires actual 1920×1080 textures and passes off/on and
resize checks. These are texture-acquisition observations, not GPU completion,
presentation or scanout. The incompatible-owner case fails with the native
`CAMetalLayerInvalidOperation` message that the drawable-count setter must not
run while CAMetalDisplayLink owns the layer. The failed run is retained.

Optional 0026 skips that setter while the per-surface presenter exists, preserves
the ordinary framebuffer ring, then marks an ordinary resize after the presenter
has stopped. Four source-bound portable controls and two rejecting mutations
pass. Incremental editor `d9fcc720d5497ab704367c0dd01d3ae6303804011c33e1a4593c367fd29094d0`
passes the native regression: two advancing real OS-presented callback samples
at an admitted 1080p extent, an explicit post-start resize, generation retirement
and two further advancing callback samples. Receipt
`c6d295625bbd908769b614f992b9d56ff6b730a4ce0f04b4c47e4ac273a0e5d6`
binds that run. The latest admitted extent and OS callback progress are separate
facts, not a per-presented-frame size tuple. Fresh pair26 is still building.

The RT-view trial corrects output render-target usage and joins the dispatch
ledger to the actual driver pipeline identity. Its disposable gate override
runs only in a private incremental engine; the product guide gate stays false.
Editor `de29a25510a1a2c8535cf5be04339fdf115e1e2a2d4b284799c1a884ce8cde99`
passes the bounded trial with no fixture failures. Initial GPU completion is
frame 13/serial 1; opacity restoration completes frame 28/serial 3. Alpha and
invalid environment inputs are refused, then valid input creates fresh epochs.
The 1920×1080 output SHA is
`6c2eb77cf98fd4721aa7c78b828f11c3afa027cf4f772ed271d53d65ede45234`.
This exercises ground and pilot-head geometry with flat opaque materials, not a
moving whole aircraft, full material coverage or image-quality qualification.
The generic denoiser flag remains false; matching viewport command completion
supplies the separate GPU witness. No displayed-FPS benefit is established.

The draft package-default reader, fixed ordinary Home observer and cache fixture
pass nine native script parses and focused admission/terminal/cache controls.
These synthetic/draft checks issue no actual marker and do not qualify a package
or automatic backend. Final runtime/source renewal and real release captures
remain required. No old receipt or development ZIP is relabelled as a new build.

Phase 24 retains 269 payloads, 21,797,056 compressed bytes, archive SHA-256
`fff1badecad9ce7284924a9ad3883ca0209b003ea7fb2e7d0ccff95efde061c7`.
Every payload independently rehashes; successful checked reports/logs validate,
and the original extent, DisplayLink exception, parse and RT dispatch failures
remain explicit. Engine binaries stay retained on M1 with their build receipts
included here. Task-owned old import caches were removed only after inventory;
source, frozen campaigns and final binaries were preserved.

## Evidence retention and open gates

The next complete-app overlay is
`938a4c8b5b1fd36bd8735698a5ec05434dc10dea6c5e2d84e4ab36187a3f282c`
(31,925 bytes). It changes four FG scripts/tests and adds their four native
Godot-generated UID sidecars; the Home/main hooks are unchanged. The controller
`226435e070bc3402da6808ad10bc9da9c79416aee590aeb3246242f32f345fa0`
and policy `73c9ddd1d3121aa6f5ae5a5da673bbf1f6373ce85f6414802365ff7f571dad63`
passed 82 and 499 checks on both Windows and the fresh ARM64 editor. Their tests
are `51f451f271f92729d45cb7ec2bede32ce2b113aada41194204e5157bd9299551`
and `e5506a6ba273bf7838c33be8d535c2d0b30f278d5d4f239a7f86a53ae7b638e0`.
The runtime uses a separate research profile, with only the prior task-owned
import cache reused and changed inputs rechecked.

Native trial R3 selected and kept Temporal through Graphics settings without the
previous activation stall. Home/Fly/non-menu pause/resume/Home succeeded and
shutdown reported zero leaked objects. A single observation-sync reset recovered
actual GPU reset serial 2 in flight and serial 3 after resume. The scoped helper
does not use a CPU acknowledgement as GPU proof. Its separate status/reset calls
still permit an external-cut race; a serial mismatch closes FG admission but
cannot undo an extra visual reset already issued. The later 0019 transaction
and adapter supersede this cross-call implementation; their status is below.

The new bounded diagnostics exposed the remaining Home proof-join bug without
guessing from later debug samples. In the same poll, the scaler completed frame
5768 successfully at Mach time 489378.52254025004. The 0013 ring contained that
exact frame/time and `now` was 489378.5239288334, but its exclusive completeness
watermark was 489378.4982610001, so the rate prefix ended at frame 5767. The
policy consequently rejected the fresh individual completion while reporting
41.5 closed-window real FPS and three recovery bins. The correction must keep
the closed prefix for FPS/gap/recovery accounting and separately join validated
individual successful completions for SDK proof. This run did not activate FG.

Raw receipts/logs remain in the task workspace's `candidate/tmp/` and native
fixture directories, with retrieved copies under ignored local
`tmp/metalfx-20261114/`. Initial sparse source ZIP SHA-256:
`20f2e606cd46831467fb31d26e966f5d37ab0007bce63c64a9f9ad15930b0245`;
dependency overlay: `018729e2438716d56fbd5cb4d157c01c84f638e7e7ae7bc6ac06e54dd03204aa`.
The reduced lens fixture archive is
`492298d00c3fb5bb9c4fa4c5a5b92e659cd08ae29930b46410e79c5ce30eab81`.
Later overlays are recorded separately; these are not a full frozen product build.
The retrieved phase-1 receipt bundle SHA-256 is
`f4c1150ff14bbe2ae7e78374960d7b141e7a1ec424a85d7d1bb3a616ed75c5ea`;
its local path is `tmp/metalfx-20261114/retained-phase1.tar.gz`. Later results are
not retroactively included in that archive.

Remaining: required CI on later integrated candidates, independent Temporal-history
image/lifecycle qualification beyond the bounded reset fixtures, FG scene inputs
and end-to-end presentation, a real engine RT/denoised consumer, moving-image/1080p
workload comparisons, physical latency and lifecycle/endurance. The R2 source-bound
development package is retained above. Newer hardware remains useful for independent qualification;
M1 denoised scene/product qualification remains open despite the native binding
witness. Public Developer ID distribution remains deferred. Normal reconstruction
defaults are unchanged.

Historical interruption before the later native campaigns: after the earlier
template compilation, SSH and Tailscale data-plane probes stopped
responding. Tailscale still advertised the M1 online; that is not SSH availability.
The documented Linux jump host was offline. The motion fixture was prepared
locally, but its transfer timed out, so no native parse/motion result is claimed.
No task-owned rendered application remained running when access was lost.

A Windows-only parse attempt was admitted but failed before Godot launched:
`T-36b1158c202c4e009dafc7eec4250c6f`, cleanup confirmed, evidence incomplete.
Its isolated copy changed `NotContentIndexed` attributes from 8224 to 32 while
bytes, mode and mtime stayed identical. The worker source now reapplies the
frozen metadata after `copy2`; the strict verifier is unchanged. All 27 worker
and snapshot tests passed with Python 3.11.15. A disposable mutation omitting
the metadata restoration reproduced `INFRA_FAILED` and failed the new regression.
The running shared authority had another active claim and was not restarted.
These are fake-process infrastructure controls, not a successful fixture parse
or a native graphics result.

## 2026-11-16 native CPU closeout on ANGEL

The bounded native closeout reached its
screen stop condition. **Reference remains the default.** The native backend
remains an explicit experimental option; no default-admission marker was created.
This CPU comparison does not qualify the four MetalFX technologies above.

Candidate `e272d8708a0b8efbcd2f9921482970581df3dfc7` ran on ANGEL,
MacBookAir10,1 / Apple M1 / 8 GiB, macOS 27.0 (26A5425a), with the existing
Engine 26 editor/template pair. The observer now guards absent optional
frame-generation metadata and decodes finite, integral JSON clock bounds before
joining drawable evidence. Its 119 checked native tests passed. Fresh source
qualification passed 650 checks, 17 positive source oracles, the required mutant
refusal, FPCR and domain controls. The unchanged performance gates were retained.

The R8 ARM64 development app passed all five packaged checks and both complete
Home/Fly/pause/restart/Home/re-entry/audio-shutdown fallback routes. It is at:

`/Users/g/OpenRC-m1-work/metalfx-stack7-20261114/native26-development-r8/OpenRC-MetalFX-Native-Research.app`

The Desktop link is `/Users/g/Desktop/OpenRC Simulator M1.app`. Its `arm64`
project override selects Mobile; the performance screen
above deliberately requests High/Forward+ and does not qualify other render scopes.

One reference-then-native screen used 30-second warmups and 120-second measured
samples, High / Metal Forward+ / native resolution / VSync. Both reported actual
acquired 1920×1080 framebuffer textures, complete host observations, no health
violations and simulation/wall ratios within 0.99–1.01. Five common complete
6,000-tick state/input windows had identical hashes and the screened tick-zero
checkpoint matched. This is software evidence, not physical flight validation.

| Short-screen metric | Reference | Native |
| --- | ---: | ---: |
| Callback FPS | 59.167 | 59.142 |
| Frame p95, ms | 18.646 | 18.650 |
| Frame p99, ms | 20.401 | 20.638 |
| Process CPU seconds per matched simulated second | 0.567579 | 0.571072 |
| Sampled peak process RSS, MiB | 539.875 | 462.688 |

Both p95 values exceeded the predeclared 18 ms gate. Native CPU was about 0.6%
higher and callback FPS essentially unchanged in this single screen; neither
provided the required 5% benefit. The lower sampled native RSS is unreplicated
and does not establish a sustained memory improvement. Callback FPS and acquired
textures do not measure display scanout. The coordinator stopped before the
remaining short/long campaign, fleet admission and four-case candidate Home proof.
No performance threshold, quality setting or reader was changed to admit it.

Original results remain under the task's
`native26-closeout2-first-pair-results-r1/{reference,native}/capture/` directories.
The package record SHA-256 is
`516b4b9e207b94891d1d0034859d3acc428b6caf3addd48ca60710d89ae594bc`;
five-check result: `022c9e86fcbb9a75e557db78289b5671e7e54645859c1daefe67fa1e6f067303`;
fallback proof: `92ea9327d8d26feef57a02d88f0a7ad4fec5f08db9af92267cb0bafe2a2f414a`.
Fresh source/observer evidence and 27 replay tapes were cross-verified in the
private phase-28 archive (`01beec989265a7315f201a29d246a76ce510d90f715c31f2d827c6ba3fb9dd95`).
Earlier R7 failures and stopped r5 evidence remain separate and unaltered.
The completed R8 checks, Home records and all four raw smoke/measured capture
trees were separately cross-verified in the private phase-29 archive
(`cba907ca6afe5175f51ce3fc16ce8066b23dc5e0655326dd594741583e1ad263`,
155 payloads). Completed task import caches were retired after verification;
source, proofs, binaries and the app were unchanged. Final free disk was about
6 GiB. All task application/engine processes exited and the owned keep-awake
assertion was stopped.

The exact-head [MetalFX source CI](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43888123122)
passed. The [required CI](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43888117712)
is still awaiting its visual-capture job at this update; the other jobs passed.
Public Developer ID distribution and integration into main remain pending.

## 2026-11-16 owner-directed native default

The owner's later instruction supersedes the earlier decision to withhold the
product default. Native physics is now the normal macOS ARM64 Home/Quick Flight
choice within the structurally screened stock production-trim domain. Explicit
reference selection, unsupported configurations and failed native validation keep
the reference route. Engine, OS, library, source, package, immutable-context and
runtime guards remain mandatory. No performance-promotion marker was fabricated;
the earlier failed performance screen and incomplete sustained/fleet campaign
remain unchanged.

The tested runtime is `1bb0434c1dff01f9a9ee8f8927f15ee95ef7cce7`. R10 is installed
as a **physical app**, replacing the previous Desktop symlink:
`/Users/g/Desktop/OpenRC Simulator M1.app`. Its app and dylib retain their local
ad-hoc signatures; public Developer ID distribution remains deferred.

Completed verification:

- Fresh M1 native qualification: all 650 stage/lifecycle/replay checks, the
  positive oracles, expected negative control, FPCR and packed-domain guards.
- Ordinary source default: 74 checks, including real native callbacks, exact
  recorded replay, immutable live guards, explicit reference and unsupported
  selection fallback. The companion profile test also passed on the official
  M1 editor.
- Companion rebind: nine retained tapes, 18 complete official Windows replays,
  nine identical CSV pairs of 2,881 rows and 49 offline tool controls. Only the
  companion solver pin changed; aircraft parameters and retained tapes did not.
- R10 package: all five selected-ARM64 checks passed, including native stage,
  lifecycle/replay and separate reference/native sessions.
- Audio-enabled packaged Home: both missing and malformed performance-marker
  cases passed Home → flight → pause → restart → Home → flight → normal quit.
  All six flight/restart/reentry observations reported active `native`, positive
  native context/stage counters and clean checked engine logs. No backend or
  renderer override was supplied; the shipped graphics configuration was used.
  These are functional results, not new performance, focus or scanout evidence.

Package record SHA-256:
`2fbe18e3beae76886c64f889619208f0255ac8432fe9177d9d7cd4bef8ec741c`.
Five-check result:
`25b60da5a8895fe287b71d7094d745ea6325e0fb9fdc49a0135452b15843f660`.
Home proof:
`52ebceca98a9653e5143e52bc98b0a44ea0ae184d2610909ca727d68265e970c`.
The signed executable SHA-256 is
`cdea09c51f15ea29b37b4aff92505e106a057cf7f1fe005992942fe5569cd653`.
The final private archive contains 289 cross-verified payloads, including raw
checks and replay tapes (`2a4bff05b0ff545215f4920dd398e4949702e10143478bf138f68d4623e0b10a`).
It is retained on M1 and under `D:/OpenRCsimulator-evidence/native-default-20261116/`.
Completed import caches were retired; source, signed apps, binaries, receipts,
logs and tapes remain. Task app/engine processes exited and the owned keep-awake
assertion was stopped.

The work branch also contains CI-only follow-up
`c6e81947b105c6cd0b8797620ce1f3e8cb9a9e75`: the visual job's cold import stopped
at its 600-second limit before rendering. A checked 1,800-second pre-import now
runs before the unchanged capture suite, with separate diagnostic retention.
`app`, `research` and `tools` Git trees are identical between that CI head and
runtime `1bb0434c`. The runtime evidence and package receipts retain their actual
`1bb0434c` identity; this equivalence is not acceptance by the legacy promotion
reader, which requires exact commit/tree/CI-head equality.

The [MetalFX source controls](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43921529985)
passed on the CI head. The [aggregate CI](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43921525209)
remains in progress at delivery. No main merge, public app release or new
performance qualification is claimed.

## Integration scope recorded after delivery

The subsequent [main-integration record](https://github.com/bultodepapas/OpenRCsimulator/blob/8d4169f8febfd7d78a028eaa817414217a54f24b/docs/plans/apple-silicon-closeout.md#main-integration) retained the task branch solver, domain and companion inputs byte for byte while preserving independent ClearView and Extra 300S work from main. The earlier M1 receipts apply only to those unchanged inputs; they do not qualify the unrelated aircraft/import changes. That record still left aggregate CI pending and supplies no later performance or public-signing acceptance.
