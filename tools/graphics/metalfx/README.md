# Apple MetalFX engine intake (DT-MAC-11a / 07a1)

This isolated engine experiment does not change `app/get-godot.sh`, install export
templates globally, or promote an unqualified graphics mode. The
[four-technology plan](../../../docs/plans/apple-metalfx.md) owns remaining gates.

`engine.py` pins official Godot commit
`cafc17a192acf67903910a68aeb3c076c0907a4b` (4.8-beta2). Download its
[source ZIP](https://codeload.github.com/godotengine/godot/zip/cafc17a192acf67903910a68aeb3c076c0907a4b)
once into an ignored cache. Required SHA-256:
`83cf257bc53427f2b1ea07015dbad298252c20546e916c5daa30a1cf78c45c1e`.
The helper never downloads dependencies or deletes/reuses an intake directory.
Godot's MIT license and all third-party notices remain in each full source tree;
preserve them when packaging a custom engine.

Use Python 3.11+, Git and native ARM64 macOS for builds. In a task-owned venv,
install `scons==4.10.1 zstandard==0.25.0` (the pinned engine requires zstandard on
Python earlier than 3.14). Use installed Apple developer tools/SDK 26+ for the new
MetalFX APIs. The current native experiment uses SDK 27; compiling a macOS 13
deployment target does not establish execution on macOS 13. No Developer ID is
required for local raw executables. Public signed distribution remains deferred.

Prepare **separate fresh intakes** for editor and release template. This example
selects the complete 0001–0019 experimental stack, in order. Bash/zsh:

```sh
patches=(
  --patch tools/graphics/metalfx/patches/0001-metalfx-allocation-fallback.patch
  --patch tools/graphics/metalfx/patches/0002-metalfx-history-reset.patch
  --patch tools/graphics/metalfx/patches/0003-metalfx-debug-faults.patch
  --patch tools/graphics/metalfx/patches/0004-metalfx-frame-inputs.patch
  --patch tools/graphics/metalfx/patches/0005-metal-triangle-query.patch
  --patch tools/graphics/metalfx/patches/0006-metalfx-gpu-observation.patch
  --patch tools/graphics/metalfx/patches/0007-metalfx-denoised-binding.patch
  --patch tools/graphics/metalfx/patches/0008-metal-paired-presentation.patch
  --patch tools/graphics/metalfx/patches/0009-metalfx-frame-composition.patch
  --patch tools/graphics/metalfx/patches/0010-metal-empty-submit-fence.patch
  --patch tools/graphics/metalfx/patches/0011-metalfx-presentation-adapter.patch
  --patch tools/graphics/metalfx/patches/0012-rd-gpu-failure-stop.patch
  --patch tools/graphics/metalfx/patches/0013-metalfx-real-completion.patch
  --patch tools/graphics/metalfx/patches/0014-metal-present-callback-lock.patch
  --patch tools/graphics/metalfx/patches/0015-metal-present-decision-observation.patch
  --patch tools/graphics/metalfx/patches/0016-metal-present-pacing.patch
  --patch tools/graphics/metalfx/patches/0017-metal-present-submission-lifetime.patch
  --patch tools/graphics/metalfx/patches/0018-metal-rt-scene-inputs.patch
  --patch tools/graphics/metalfx/patches/0019-metalfx-conditional-history-reset.patch
)
python tools/graphics/metalfx/engine.py prepare --archive /cache/godot.zip \
  --out tmp/metalfx-editor "${patches[@]}"
python tools/graphics/metalfx/engine.py build --archive /cache/godot.zip \
  --out tmp/metalfx-editor --target editor --jobs 4 "${patches[@]}"
python tools/graphics/metalfx/engine.py prepare --archive /cache/godot.zip \
  --out tmp/metalfx-template "${patches[@]}"
python tools/graphics/metalfx/engine.py build --archive /cache/godot.zip \
  --out tmp/metalfx-template --target template_release --jobs 4 "${patches[@]}"
python tools/graphics/metalfx/engine.py pair --archive /cache/godot.zip \
  --out tmp/metalfx-editor --template tmp/metalfx-template "${patches[@]}" >tmp/metalfx-pair.json
```

0001 adds allocation/submission guards and per-viewport state; 0002 adds Temporal
reset serials, render-attempt bounds and lifecycle fences. 0003 is an opt-in
diagnostic source patch: `DEBUG_ENABLED` builds accept
`OPENRC_METALFX_TEST_FAILURE=spatial_factory|temporal_factory|spatial_enqueue|temporal_enqueue`.
Its environment is latched on first lookup, so use one fresh process per case.
The controls are absent from release-template code. Normal launches leave it unset.
0004 adds an explicitly requested offscreen HDR scene-input experiment, macOS 26+
SDK bridge and synchronous diagnostic readback. It rejects unsupported scenes,
keeps Temporal reset receipts independent and has no presenter. Its actual M1
readback/lifecycle fixture passed; broader scene motion and product presentation
remain open.
0005 adds an opt-in experimental Metal compute triangle-query backend. Launch
with `GODOT_METAL_TRIANGLE_QUERY=1` only for that experiment; ordinary ray-query
and ray-pipeline support remain unavailable. It admits a bounded triangle/instance
subset, not complete OpenRC scenes. The portable controls compile the changed
validation and binding functions, including development-build object naming,
pipeline changes, inactive descriptor-set holes and current TLAS/BLAS residency.
Native compilation and both binding-mode hit/readback cases passed on M1. The
strict rejection battery exposed empty-submit fence handling; 0010 addresses
that independently. The dated evidence retains both failing and corrected runs.
0006 adds opt-in command-buffer completion observation, described below. Its
compiled controls and the native Spatial/Temporal/interpolation observer fixture
passed on M1. This remains command-buffer observation, not presentation evidence.
0007 adds the bounded RD denoised binding described below. All three later patches
were subsequently built in a separate seven-patch native M1 editor. The earlier
four-patch editor and its receipts remain distinct from later builds.

The presentation experiment requires 0008–0017 in the exact
order shown, after 0001–0007. The current controller additionally uses 0019 for
atomic missed-reset recovery; without it, that recovery stops safely and leaves
Temporal selected. 0018 is the optional RT diagnostic prerequisite described
below. 0010 also supplies the empty-submit fence fix used
by the earlier triangle-query native tests. Select a smaller stack explicitly
when reproducing earlier evidence. Never add patches to an existing intake or
substitute its recorded patch copies.

### Ordinary drawable acquisition observation

The optional 0025 patch adds a main-window ordinary Metal drawable acquisition
receipt. It is enabled only when `OPENRC_NATIVE_DRAWABLE_OBSERVATION=1` is set
before the process starts. With the flag absent it allocates no tracker and does
not request another drawable. When observation is requested, a requested or active
display-link owner is reported as incompatible. With `status=not_requested`, the
`owner` field does not identify the active presenter.
Query `RenderingDevice.openrc_drawable_observation()` on the render thread.
The bounded receipt includes a surface scope, attempts, observed and missed
counts, extent/pixel-format changes, the latest texture width, height and Metal
pixel format, and CPU query-time bounds. `observed` identifies a texture acquired
for framebuffer setup; it does not prove a committed command, presentation,
scanout, displayed frame rate, or latency. Recreated surfaces have a new scope.

For a fresh pair matching the previously verified engine24 selection, start with
the 0001–0019 `patches` array above and append exactly 0021, 0024, then 0025;
do not add the RT viewport or trial patches. Use the same pinned source ZIP,
`engine.py`, Python and toolchain for both new intakes:

```sh
patches+=(
  --patch tools/graphics/metalfx/patches/0021-metal-rt-extension-abi.patch
  --patch tools/graphics/metalfx/patches/0024-apple-arm64-sha256.patch
  --patch tools/graphics/metalfx/patches/0025-metal-ordinary-drawable-observation.patch
)
python tools/graphics/metalfx/engine.py prepare --archive /cache/godot.zip --out tmp/drawable25-editor "${patches[@]}"
python tools/graphics/metalfx/engine.py build --archive /cache/godot.zip --out tmp/drawable25-editor --target editor --jobs 2 "${patches[@]}"
python tools/graphics/metalfx/engine.py prepare --archive /cache/godot.zip --out tmp/drawable25-template "${patches[@]}"
python tools/graphics/metalfx/engine.py build --archive /cache/godot.zip --out tmp/drawable25-template --target template_release --jobs 2 "${patches[@]}"
python tools/graphics/metalfx/engine.py pair --archive /cache/godot.zip --out tmp/drawable25-editor --template tmp/drawable25-template "${patches[@]}" >tmp/drawable25-pair.json
OPENRC_METALFX_SOURCE_ARCHIVE=/cache/godot.zip python -B tools/graphics/metalfx/test_engine_drawable_observation_patch.py
```

Do not alter the engine24 intakes. A separate incremental development build can
check iterations without requalifying a pair; the frozen final source needs one
fresh pair verification and package binding because both artifact identities
change. Native evidence must separately check flag-off behavior, the ordinary-owner
acquisition receipt at the actual 1920×1080 texture extent, scope changes on
surface recreation and the incompatible-owner refusal. Record real runtime,
package and build identities.
Pair verification alone is not that runtime evidence.


Intake freezes and hashes archive/ordered patch copies, reconstructs the expected
patched catalog, rejects unknown source edits, extra inputs, unsafe paths and
symlinks, and records helper identity. New source files require regular mode
100644 and enter the verified catalog; executable/symlink additions are refused.
`source/` stays pristine; each target builds
in its own disposable `build-source-<target>/`. Native builds use Metal and
Compatibility, without Vulkan, AccessKit, LTO or debug symbols. They record exact
commands, SDK, clang, controlled environment, logs, architecture and artifact
hashes. The explicit SDK libc++ include route accommodates the installed CLT
layout observed on the shared M1. Failed/interrupted builds require a new intake.

`verify` rechecks the pristine intake after a build. `pair` additionally compares
editor/template source, patches, helper, toolchain and flags and rehashes exact
artifacts and logs. Pair verification does not qualify rendering, export,
signing, minimum OS compatibility, performance or a product package. Keep the
export's actual template identity bound to the later package receipt.
The fresh verified 0001–0017 native pair has editor SHA-256
`c47636a595313598a399b01ba8d550ef11409beb63b80718aa7fa8fe763bc7b7`
and release-template SHA-256
`c44d06546ebd953514be583b5195b1c0ec9a9e22eff74480d306faebf273aacb`.
The later clean 0001–0019 pair has editor
`8e345b212ab1612b19e67c00541a34eeae31aa43980016517e6e7b2449f2682b` and
release template `f2dfbc94195ba6bdb49b9b34090040a279cf159012e38f5155705a164f5c4e59`.
Optional 0020 was built separately as a development editor, not as this pair.
These identities are build evidence, not hardware or public-release qualification.
Use the same absolute Python invocation spelling for both builds. The verifier
compares recorded command arrays and refuses differing aliases or `..` spellings
even when they resolve to the same interpreter.

```sh
python -m unittest discover -s tools/graphics/metalfx -p test_engine.py
OPENRC_METALFX_SOURCE_ARCHIVE=/cache/godot.zip \
  python -m unittest discover -s tools/graphics/metalfx -p 'test_engine*_patch.py'
```

The second suite compiles selected patched functions with fake rendering/SDK
objects where a compiler is available. This is fault-path source evidence,
separate from the real engine build and native GPU fault injection. Shared-host
Godot runs still use the [checked runner](../../../docs/tools/shared.md#one-godot-script)
and [host admission](../../testqueue/README.md).

The [native API fixture](../../../research/engine-upgrade/metalfx/README.md)
checks the real device independently. Neither fixture is a second profiler.
The verified 0001–0003 pair and the later intake-helper revision are identified
separately in the dated evidence; a helper update deliberately invalidates an
older intake's helper identity until its original frozen helper is restored.

## Optional GPU completion observation

With patch 0006, call
`RenderingServer.viewport_set_metalfx_gpu_observation_requested(viewport_rid, true)`
and read `viewport_get_metalfx_gpu_status(viewport_rid)`. The default is Off. Off
creates no observation state or completion handler. Explicitly requesting it can
allocate CPU state before an effect callback is admitted; an enqueue failure may
therefore have allocated state with ticket zero and `unobserved` status.

Handlers are registered after the actual SDK encode returns. They retain only
shared observation state and value metadata, so retiring a viewport/generation
does not leave a callback holding its owner. Snapshots are coherent per role
(`scaler` or `frame_interpolation`), not an atomic pair. Identify a sample by the
viewport RID, viewport generation, observation generation, frame generation,
role, epoch and ticket. A recovered interpolation context can restart its ticket
counter while its epoch changes. A greatest observed completed ticket is not a
contiguous completion fence or a count of completed frames.

`completed` means the latest encoded ticket's callback reported command-buffer
success; an earlier observed failure stays latched in that observation state.
Temporal GPU reset completion is independent of the legacy encode-call receipt.
Toggling observation does not reset Temporal history or its request serials.

Apple's [completion handler](https://developer.apple.com/documentation/metal/mtlcommandbuffer/addcompletedhandler(_:))
reports the whole command buffer. Its
[GPU start](https://developer.apple.com/documentation/metal/mtlcommandbuffer/gpustarttime)
and [end](https://developer.apple.com/documentation/metal/mtlcommandbuffer/gpuendtime)
timestamps use system Mach seconds; absent, zero or invalid times remain null.
The callback's CPU observation uses `std::chrono::steady_clock` microseconds.
Do not subtract these clocks without calibration, sum durations shared between
roles, or label this effect-only cost, OS presentation, displayed FPS or latency.
`gpu_probe.gd` passed checked parsing and native API/retirement cases on M1.

## Experimental scene/UI composition and presentation

0009 composes two bounded offscreen outputs: the actual SDK-generated scene and
the saved current real scene, with UI drawn once on each. It reuses immutable
tonemap settings rather than executing stateful postprocessing twice. Unsupported
postprocessing, canvases, views and scene inputs reject the pair. Request it with
`viewport_set_metalfx_frame_composition_requested(viewport_rid, true)` together
with `viewport_set_metalfx_frame_requested`. Read
`viewport_get_metalfx_frame_composition_status`; diagnostic
`viewport_read_metalfx_frame_composition` performs synchronous readback. These
engine experiments do not add a normal player setting.

0008 adds a startup-only `OPENRC_METALFX_DISPLAY_LINK=1` opt-in on macOS 26+.
When admitted, one engine-owned CAMetalDisplayLink keeps drawable ownership for
the window's lifetime, including real-only fallback. Its supplied update drawable
is committed and presented through that route; no second `nextDrawable` call or
timed-present method is mixed in. Conversion uses separately allocated, retained
Metal textures rather than transient RD heap regions. Ordinary launches leave
this option unset. The experimental opt-in suppresses the boot logo/background,
including when owner admission later falls back to ordinary presentation.

0011 connects the current in-flight composition pair to that owner. Exact SDK
encode/completion proof and source identity are required before choosing generated
output. Bounded leases preserve source textures through GPU conversion. Cuts,
Off, resize and viewport changes cancel a source generation; a new generation
waits for an already-entered old submission to leave its gate. This cannot revoke
work already accepted by the OS. A blocked epoch can require an explicit history
or lifecycle reset. Render/main loops never wait for the next real frame.

`RenderingDevice.openrc_metalfx_present_status()` must be sampled on the render
thread. `accepted_pair_candidates` counts admitted candidates before SDK proof
is ready. GPU completion, present requests and OS-presented callbacks remain
separate counters; none measures physical latency. Debug-only
`OPENRC_METALFX_DISPLAY_LINK_PROBE=1` submits two converted copies of the same
real source. Its `synthetic_control=true` receipt cannot prove interpolation.

Use `present_probe.gd` for ordinary/real-only/synthetic route controls and
`composition_probe.gd` for offscreen image checks. For the latter's actual
interpolated presentation case, set `OPENRC_METALFX_PRESENT_ADAPTER_PROBE=1`
and the display-link opt-in, leaving the synthetic option unset. Both use the
existing checked runner and isolated projects at 1920×1080. A requested 30-FPS
cap is a diagnostic configuration, not the product's measured-rate admission
policy or a maintained real-frame-rate claim.

0010 fixes empty Metal submissions with a queue-ordered fence signal. 0012 stops
on returned Metal submission/wait failures before recycling resources, including
when FG is Off in this custom engine; other backends retain upstream handling.
A two-second wait timeout is not proof that a slow or suspended GPU is lost. It and a
200-ms source-ticket retirement timeout can terminate the experimental process.
These guards prevent unsafe reuse; they are not graceful device-loss recovery.
Native stress, sleep/wake, visible color, pacing and latency qualification remain
required before this route can become a normal choice or default.

0014 addresses an observed native Core Animation/state-mutex deadlock: drawable
access and Metal encoding/handler registration happen outside the mutex used by
callbacks, then admission revalidates under it before commit. The corrected
development build passed real-only native presentation and the 1080p offscreen
UI case. Its generated presentation cases still failed; their accepted-candidate
counts do not establish generated output. 0015 exposes bounded scheduler decision
facts and native GPU error codes for diagnosing those failures. Its counters
include real-only decisions; `paired_candidate` identifies the sampled job type.

0016 adds bounded display-link pacing and reservation handling. 0017 retains
admitted submission resources until terminal completion and distinguishes
unrequested `NotEnqueued` callbacks from failures of admitted commands. A
nonterminal admitted completion or exhausted retention capacity leaves the
presenter unresolved; it is not proof that real frames continue to display.
In a bounded native M1 development run of the full 0001–0017 stack, the actual
SDK pair adapter reported one generated OS-presented drawable at 1920×1080 in
final presenter generation 9, zero confirmed GPU failures and five ignored
unrequested `NotEnqueued` callbacks. This is not a sustained-rate, visual-quality
or latency result. Hardware qualification remains `not_run` and public use deferred.

## Optional alpha-list diagnostic

Patch 0020 is separate from the clean 0001–0019 pair and leaves transparent-scene
rejection unchanged. Set `OPENRC_METALFX_ALPHA_DIAGNOSTICS=1` before starting its
development editor to retain a bounded historical alpha-list page after an FG
input rejection. `viewport_get_metalfx_frame_status` exposes it as
`alpha_diagnostic`; each page holds at most eight entries plus frame, viewport and
producer generations, total, offset and truncation. The captured material RID is
the actual alpha-list material when available; shader RID can be unavailable.
With the diagnostic startup flag unset, no diagnostic snapshot is allocated.
A captured snapshot can outlive producer Off. Pages from different frames cannot
be combined into an exhaustive single-frame list.

The 1080p native `frame_probe.gd` enabled case matched its known RIDs and retained
the snapshot after producer Off; the diagnostic-Off case skipped it. The explicit
`alpha_scene_census.gd` helper joins historical base resources to bounded current
scene candidates, not unique instances or pixel contributions. One Home page
matched three NightKit light sprites among 35 alpha entries; flight coverage and
the remaining entries are unresolved.

A separate research-only alpha-input patch disables composition and presentation
and failed eight native moving-image gates. It is not part of the pair, a fallback
or a reason to remove the transparent-scene rejection. See the
[dated results](../../../docs/research/desktop-delivery-investigations/DT-MAC-11a/README.md#alpha-diagnostics-and-moving-image-experiment).

## Completed real-frame observation

0013 adds an explicit main-window viewport observer, separate from scaler
callbacks, the process loop and generated presentations:

- `viewport_set_real_gpu_observation_requested(viewport_rid, enabled)`
- `viewport_reset_real_gpu_observation(viewport_rid)`
- `viewport_get_real_gpu_observation(viewport_rid)`
- `viewport_get_metalfx_frame_capability(viewport_rid)`

The observer attaches a graph-tracked read after the real viewport scene, canvas
and resolve work. Only successful whole-command-buffer completion with a valid
GPU end timestamp produces a sample. Callbacks retain bounded CPU state, not a
viewport or render target. Off does not create that optional state or recurring
GPU observation. Unsupported/no-swap/overridden-target and multi-owner cases
remain explicitly ineligible; changing context/configuration invalidates its
generation. The device capability query is independent of factory allocation:
map only affirmative `compiled`, `os_available` and `device_support` facts to
admission, preserving unknown values and later factory/dispatch failure.

Snapshots contain generation/frame identities, bounded `samples`, `pending`,
overflow/failure/invalid-clock flags, `coverage_start_seconds`,
`observed_through_seconds` and `now_seconds`. Samples use `gpu_end_seconds` in
`mach_seconds`; the snapshot clock uses the same native time base. The watermark
stays behind unresolved reservations, so a CPU poll cannot close a rate window
ahead of pending callbacks. Lost history or invalid timestamps fail closed.
Whole-command-buffer completion proves ordering; it does not prove changed pixels
or displayed FPS. This clock stops during system sleep. The controller handles
application pause/resume and focus notifications, but macOS sleep/wake delivery
has not been qualified and must not be inferred from gap arithmetic.

`app/render/frame_generation_policy.gd` is the 12c admission policy, now wired
through `app/render/frame_generation.gd` for an explicit developer startup trial.
Normal Off does not load the controller or request either optional observer.
The technical trial requests all four environment settings below and requires
Forward+/Metal and an actually configured MetalFX Temporal viewport:

```sh
export OPENRC_METALFX_TRIAL=1
export OPENRC_METALFX_DISPLAY_LINK=1
export OPENRC_METALFX_FRAME_GENERATION=1
export OPENRC_RECONSTRUCTION=metalfx_temporal_quality
```

These are not a public player option or a change to defaults. If Temporal is not
configured, a capability is unknown or any other gate fails, the request stays
suspended. The controller polls at most 10 Hz, keeps at most one presenter-status request
outstanding on the render thread, and exposes an experimental receipt in viewport
metadata `openrc_frame_generation_status`. It invalidates on observed cuts,
simulation pause/resume, source, focus and viewport changes. Already submitted OS
work cannot be revoked; presenter generation and sleep/wake limits remain open.

0013's completed-real history drives the two-second 30 FPS floor, the over-100 ms gap
limit and three distinct closed one-second recovery bins of at least 35 FPS. The
separate 0006 observer supplies scoped Temporal scaler and frame-interpolation
GPU completions. A current proof permits only a renderer-gated composition
attempt; it does not bypass per-frame checks or establish presentation. Explicit
input/postprocess rejection suspends the producer with bounded retry backoff.
The current pure policy passed 517 checks and the adapter passed 89 focused
checks on both Windows and the clean 19-patch M1 editor. The rendered history
fixture separately passed conditional rejection/acceptance, resize fencing and
successful GPU reset completion. These are
logic and lifecycle evidence, not a performance or display qualification.
Native full-app Home/Fly/pause/resume trials execute Temporal but have not
qualified full-flight generated presentation. Explicit activation also requires
selecting Temporal in Graphics settings: saved preferences supersede the startup
reconstruction environment value. The first observed selection compiled 336
pipelines and exceeded the confirmation deadline; the later warm selection
succeeded. In a later bounded Home UI trial, a 20-second injected main-thread
stall did not consume the confirmation window: Keep remained available and
saved the Temporal choice. This observes CPU status only, not GPU completion,
presentation or cold-compilation behavior. Preserve shared caches and label
their state in comparisons.
The retained-sample polling cost remains unmeasured.

0019 adds `viewport_request_temporal_history_reset_if_current(viewport,
expected_generation, expected_requested_serial)`. The comparison and existing
reset request execute as one render-server transaction. Stale/unavailable
requests leave reset state unchanged. Its receipt establishes request admission,
not GPU completion. The controller still waits for the matching 0006 GPU reset
receipt and new 0013 rate history before warmup. Diagnostic-only metadata can
retain the latest 16 state/reason transitions when
`OPENRC_METALFX_TRIAL_DIAGNOSTICS=1`; it is not admission evidence.

## Renderer-owned scene geometry diagnostic

Optional 0018 follows the frozen 0001–0017 stack. It supplies an engine-owned
one-shot geometry/query diagnostic, not a viewport RT effect or completion of
DT-MAC-13d1. Enable `OPENRC_METAL_RT_SCENE=1` and
`GODOT_METAL_TRIANGLE_QUERY=1` before startup, with explicit Forward+/Metal.
Normal launches do not capture expanded RT mesh inputs. The query flag selects
the experimental Metal 3 hazard-tracking path; it is not normal renderer policy.

The render-thread methods are `scenario_probe_metalfx_rt(...)` and
`scenario_poll_metalfx_rt_probe()`. Use the supplied `rt_scene_probe.gd` through
the checked runner in an isolated complete app copy. It deliberately flushes and
stalls the main RD graph for a one-shot build, trace and readback. Never use it
as a frame-time benchmark or call it every frame. Results contain value/provenance
receipts, not caller-owned raw input buffers or acceleration structures.

The source capture expands compatible indexed float3 geometry and keeps rigid
transforms, surface and material identities. It scans candidates beyond the
camera frustum, refuses unsupported shader/deformation/material cases, and
invalidates changed or publicly exposed RD buffers. Reentrant diagnostic flushes
are rejected; temporary AS ownership retires before deferred source buffers.
Expanded input allocation attempts have a cumulative 64 MiB charge and 1,024
source slots; diagnostic native AS/scratch reservations have a separate 256 MiB
limit. Input charges are not refunded before deferred native lifetime is known,
so a long diagnostic process can exhaust them and require a restart. These are
conservative accounting bounds, not resident RAM/VRAM measurements.

On M1 the corrected 0018 source compiled and passed checked parsing plus nine
fresh native cases: Off, actual Horizon ground, a production Extra pilot mesh,
offscreen geometry, mesh update, raw-buffer escape, release, unsupported material
and `skip_vertex_transform`. Hit identity/distance was cross-checked against the
CPU. This does not qualify the whole aircraft, moving normal-flight geometry,
material lighting, denoiser guides, raster composition or performance. Exact
source/build identities and the earlier SDK macro failure remain in the
[dated implementation evidence](../../../docs/research/desktop-delivery-investigations/DT-MAC-11a/README.md).

## Experimental RD denoised binding

Patch 0007 exposes `RenderingDevice.metalfx_denoised_capability()`,
`metalfx_denoised_create(input_size, output_size)`,
`metalfx_denoised_encode(context, textures, world_to_view, view_to_clip,
pre_exposure, jitter, reset)` and `metalfx_denoised_status(context)`.
Release a context through that device's `free_rid`. The driver-neutral API returns
unavailable on other backends; the native implementation requires macOS/SDK 26+
and Metal 3 native hazard tracking. For the prepared RT witness,
`GODOT_METAL_TRIANGLE_QUERY=1` selects that tracking mode. Do not switch the normal
product's synchronization policy simply to make this experimental API available.

The texture array has a fixed order:

| Index | Signal | Format / extent |
| --- | --- | --- |
| 0 | Noisy linear HDR color | RGBA16F / input |
| 1 | Non-reversed depth | D32F / input |
| 2 | Pixel-space motion, scale 1 | RG16F / input |
| 3 | Diffuse albedo | RGBA16F / input |
| 4 | Specular albedo | RGBA16F / input |
| 5 | World-space normal | RGBA16F / input |
| 6 | Roughness | R16F / input |
| 7 | Manual exposure | R16F / 1×1 |
| 8 | Denoised output | RGBA16F / output |

Only distinct, device-owned regular 2D, single-sample, single-mip textures are
admitted. Imported textures and shared views are rejected because their backing
storage can alias despite distinct native object pointers. All inputs require
sampling usage; output also requires storage usage, private storage and all
SDK-reported output usage. Dimensions, formats, actual device and queried SDK
usage are checked before graph admission. Pre-exposure must be finite/positive;
jitter and matrices must be finite, and the first accepted frame requires reset.
Optional strength/reactive/hit-distance/transparency inputs are disabled.

Admission joins pending texture uploads and clears to the existing RD graph.
The stateful SDK context is ordered even when callers replace every texture RID.
An empty graph lazily creates its Metal command buffer before SDK dispatch.
Context and callback references keep the SDK object alive through deferred work
and GPU execution. An encode-callback error remains latched for that context;
recovery creates another context. `accepted` and `encoded` are CPU receipts;
`gpu_completion_observed` deliberately remains false. Diagnostic readback or an
independent observer must establish GPU completion and image correctness.

The real-RT fixture is `denoised_query_probe.gd`. Its optional native runner uses
the checked runner, retains reports and exercises both binding modes. On enrolled
hosts these custom rendered fixtures need a suitable inherited exclusive grant;
normal admission refusal is not a result. Native SDK compilation, parsing and
both binding-mode RT/denoising cases passed on M1. Output also needs the SDK's
render-target usage in the observed configuration. The dated record preserves
the corrected fixture and the empty-device warning/fix separately. This binding
does not supply OpenRC's whole-scene RT
lighting, moving geometry/material coverage, composition or a product control.

## Apple ARM64 package hashing (0024)

Optional `0024-apple-arm64-sha256.patch` selects the bundled mbedTLS ARM
SHA-256 implementation in the default macOS ARM64 PSA configuration. It respects
custom PSA configuration and explicit acceleration choices. The vendor Apple
path assumes the instructions exist; verify each intended host. ANGEL reports
`hw.optional.arm.FEAT_SHA256=1`. Full and light configuration controls pass;
native build, vectors and package qualification are separate gates.

Apply it after 0001–0019 and 0021 in fresh editor/template intakes. Preserve the
previous pair and its source/catalog/receipt identities. The source change affects
bundled SHA-256 users and changes engine bytes; renew both build receipts,
API/native qualification and signed package receipts. Package freshness checks
continue to hash the complete inventory at their existing boundaries.

Use the [file-hash fixture](../../../research/engine-upgrade/metalfx/README.md#file-hash-correctness-fixture)
for independently computed vectors and an optional same-file timing comparison.
The fresh 1–19+21+24 native pair passes the unchanged full official extension
API validator and its missing-class controls. Both compiled SHA objects contain
224 ARM SHA-256 instructions, and the editor passes 25 runtime vector controls.
Three interleaved runs per editor hash the same warm-cache 2,484,244,643-byte PCK:
median 7.748414 s before and 1.583237 s after (4.894×). This is file hashing;
actual new-package startup, native physics, FPS and promotion require their own
[evidence](../../../docs/research/desktop-delivery-investigations/DT-MAC-11a/README.md).

## Display-link layer resize (0026)

Optional `0026-metal-displaylink-resize.patch` prevents the Metal layer's
drawable-count setter from being called while the display-link presenter owns
that layer. It preserves the existing ordinary framebuffer ring until the
presenter stops, then requests an ordinary resize before the next acquisition.
Drawable-size, vsync and pixel-format handling remain on their existing paths.
The engine25 M1 control raised `CAMetalLayerInvalidOperation` at that setter;
an incremental 0026 editor subsequently passed an active-owner resize control
with a 1080p admitted texture, generation retirement and renewed real
OS-presented callbacks. Those observations do not establish scanout, displayed
FPS, or that a specific callback corresponds to the latest admitted extent.

For a fresh editor/template pair, append 0026 once after 0025 in the exact
1–19, 21, 24, 25 selection above and use separate intakes and the same pinned
archive/toolchain. Re-run the API and native controls, bind the resulting pair
to new package receipts, and retain the previous pair unchanged. Source-bound
controls run with:

```sh
OPENRC_METALFX_SOURCE_ARCHIVE=/cache/godot.zip python -B tools/graphics/metalfx/test_engine_displaylink_resize_patch.py
```

## Optional opaque RT view (0027)

`0027-metalfx-opaque-rt-view.patch` is an optional, closed-gate source draft
after 0001-0019, 0021, 0024, 0025 and 0026. Its exact source catalog SHA-256 is
`a4754c95a2ed6163f3648562287155e89f11001c8cb3bd5281dab178d5cd9707`.
`GUIDE_INPUT_RECEIPT_IMPLEMENTED` remains false; the patch does not change the
default engine selection or enable RT denoising. With the
RT-view switch off, it performs no optional RT-view state allocation, scene scan
or GPU work; a reference conversion and latched check remain. Separately enabled
0018 scene capture retains its own costs. Native compilation, completion and
image validation remain required before any gate change or product claim.

Source-bound controls: `python -B tools/graphics/metalfx/test_engine_opaque_rt_view_patch.py`.
Set `OPENRC_METALFX_SOURCE_ARCHIVE` to the pinned ZIP for the full-stack check.
