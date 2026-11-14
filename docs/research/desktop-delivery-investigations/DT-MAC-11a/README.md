# DT-MAC-11a / 07a1: first MetalFX implementation evidence

Date: 2026-11-14. Implementation and native API intake are in progress. This
record does not qualify four production technologies or establish an FPS gain.
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
note. No RT feature bit or partial producer patch was added. The coherent next
port must reconcile RD/Metal/Forward+ with RT off, establish complete scene
eligibility before suppressing raster, then demonstrate real guide buffers and
fallback transitions. This is an implementation dependency, not M1 exclusion.

## Evidence retention and open gates

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

Remaining: complete production import/required CI, independent Temporal-history
image/lifecycle qualification beyond the bounded reset fixtures, FG input/presenter
integration, real engine RT/denoised consumer, moving-image/1080p workload
comparisons, physical latency, lifecycle/endurance and local development package.
Newer hardware remains useful for independent qualification; M1 denoising is an
open runtime finding, not an automatic unsupported result. Public Developer ID
distribution remains deferred. Normal reconstruction defaults are unchanged.
