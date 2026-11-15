# Apple MetalFX — four-technology implementation plan

Updated: 2026-11-15. Owner: DT/VQ/GDU, with PT for measurement and UI for settings.
Status: implementation in progress. The [first implementation evidence](../research/desktop-delivery-investigations/DT-MAC-11a/README.md)
separates prerequisite fixes, injected checks, native API observations and the
engine build. No four-feature product qualification is claimed. Source inspected at
`0bc2a52e129248ed91632f02f448e7d6455f6a5f`; engine baseline:
Godot `4.8-beta2`, `cafc17a192acf67903910a68aeb3c076c0907a4b`.

This is the detailed subplan for Spatial, Temporal, Frame Interpolation and
Temporal Denoised Upscaling under the [Apple master plan](apple-silicon-performance.md).
It owns the substeps registered below; the master retains platform/default,
performance and release gates. The [dated research](../research/desktop-delivery-investigations/metalfx-frame-generation-2026-11-14.md)
owns earlier findings and measurements. Public signed distribution remains
deferred by the owner; local development packaging is still required.

The [twenty-investigation reinforcement](../research/desktop-delivery-investigations/metalfx-20-investigations-2026-11-14.md)
provides exact engine seams, scoped issue/forum evidence and the prepared fixture
cases below. I01–I20 are research IDs, not completed implementation steps.

The two [external performance handoffs](../research/desktop-delivery-investigations/external-handoffs-2026-11-14.md)
are reconciled in the [master's current work order](apple-silicon-performance.md#17-external-handoff-work-order-2026-11-14).
Use its two-consumer process-identity repair/qualified apparatus and actual product
route manifest for resource/performance claims. Record audio, radio, cost observers,
lens/weather and companion activation: a detached or effects-off fixture cannot
qualify those product paths. Include the drop-cache gravity/rain/mesh negative
controls when the image workload exercises that pool. These prerequisites improve
evidence; they do not replace MetalFX input/history/presentation tests or require
every optional CPU experiment before feature implementation. All four remain in scope.

## 1. Scope and completion

Deliver all four technologies as real, separately selectable, capability-gated
paths on supported Macs. Keep M1 as a required baseline and negative-test host;
its inability to execute a feature does not remove that feature from scope.
Spatial already exists: complete its execution/failure evidence and qualification
instead of reimplementing its scaler. Temporal needs engine/history work.
Interpolation needs engine presentation work. Denoised scaling needs a real
ray-traced consumer as well as its scaler binding.

For the fourth technology this request expands the master plan's previously
conditional RT branch into a planned optional graphics feature. Missing RT
infrastructure is work to implement or reuse, not permission to call a disabled
checkbox complete. Missing supported hardware leaves native qualification open.
An infeasible engine dependency produces a documented incomplete milestone,
with its smallest remaining dependency; it does not close the four-feature goal.

Current implementation boundary: ordered patches 0001–0019 have a clean native
M1 editor/template pair with matching verified build inputs and local signatures.
The moving-quad interpolation witness passed at 1080p; triangle-query hit/readback,
real-RT denoising, GPU completion and Temporal reset observation also ran on M1.
The presentation follow-up fixes an observed callback deadlock, conservative
display-link pacing and unrequested-command callback accounting. Its bounded
native fixture presented an actual SDK-generated drawable at 1920×1080 without
a confirmed GPU failure. This does not establish sustained presentation, flight
image quality, latency or a frame-rate gain.

An opt-in application controller now connects the real-completion admission
policy to the existing Temporal producer and presentation adapter. The current
Windows and the clean native editor pass 89 controller and 517 policy checks.
The rendered 0019 fixture also passes conditional-reset rejection, acceptance,
resize fencing and independently observed reset GPU completion. Complete-app Home/flight
script parsing and the affected reconstruction/history tests also pass. Rendered
product trials now exercise Home/Fly/pause/resume and show actual Temporal GPU
work. The latest trial reaches the renderer and refuses its nonempty transparent
draw list because that pass has no complete motion vectors. Correct transparent
composition and workload qualification remain open. An optional 0020 diagnostic
identified three current Home-scene resource candidates in one truncated page;
it is not a complete flight census or proof of pixel contribution. A separate
research-only alpha experiment failed eight 1080p moving-image gates, so the
ordinary rejection remains required. This is an observed failure of that input
path, not an Apple API-wide prohibition. Ordinary launches do
not install this controller. No whole-scene RT consumer, public FG control or
four-feature default has been qualified. Exact revisions and results belong to
the linked implementation evidence, not this status paragraph.

The official pinned Godot editor passed the bounded companion requalification
after the actual CRLF aircraft/field checkout bytes and two behavior-source pins
were restored. That does not qualify companions or native physics on the custom
engine. The earlier R1 development package used the wrong raw checkout bytes;
its source-bound receipt and smokes do not repair that admission limitation.
A bounded native Settings trial now preserves the confirmation window through
an injected main-thread stall, and the focused Settings consumers pass. A corrected
source-bound ARM64 development package also passes fixed-session and bounded
rendered smokes. The newer R3 local package is bound to `bffe0ed522efc4e0ab7336ef60d401c4cf4d712d`
and includes the camera-cut correction. That candidate's required CI passed,
including visual captures and macOS ARM64 source correctness. Cold startup and
the custom-engine native-physics package remain unqualified.

In the tested direct-start run, Temporal kept its selection on M1. Camera cuts are coalesced
until the final camera pose, including crash focus, before the next draw. Only a
typed, empty buffer generation can rely on the engine's initial-history reset;
that path reports no explicit submission, encode or GPU completion. The clean
19-patch editor passed 445 focused headless checks and 94 rendered Metal history
checks, including injected-backend cold-state cases. A matched exploratory 1080p screen measured Native 42.48 FPS, Spatial
Quality 60.03 and Temporal Quality 57.65, with successful current-generation SDK
completions for both scalers and Temporal reset serial 1 independently observed
on the GPU. This was one sky-heavy scripted sample per mode, with physics/input
disabled and different Temporal AA. It does not qualify active-flight quality,
sustained 60 FPS, presentation or latency. The implementation evidence preserves
the earlier Native fallback, exact sources, raw results and remaining gates.

The custom-engine/native-physics preflight found 15 existing RT method metadata
incompatibilities in patch 0005. Additive 0021 restores the unsigned API while
retaining checked wide inputs. Its fresh editor/template pair passes the unchanged
full official API validator and 81 native query/dispatch processes. The combined
`b4442e6a` source candidate also passed native numerical, mutation, FPCR/domain
and production-path stage/lifecycle/exact-replay gates on M1. The later main
branch lake/contact changes require fresh source-bound native qualification. Paired export tooling
and signed-executable/template checks are implemented and tested; actual
packaged native execution and automatic-default qualification remain open.
The R3 development ZIP still contains clean19 and reference physics; the new
pair does not upgrade it. The linked evidence identifies each tested source.

Completion has three distinct levels per technology:

| Level | Required result |
| --- | --- |
| Integrated | Real inputs, native SDK dispatch, production adapter, capability rejection and recovery exist; focused source/engine checks pass. |
| Qualified | Named device/OS/output/profile passes execution, moving-image, lifecycle, performance and control gates in this plan. A sample or mocked device is insufficient. |
| Promoted | A qualified configuration is offered normally or selected by a documented Auto rule. Promotion is separate; all four need not become defaults. |

Keep float64 simulation, 240 Hz, accepted-tick/input/collision contracts and the
existing native evaluator route unchanged. GPU history is presentation state.
Generated frames never call simulation, sample flight controls again, advance
audio/gameplay observers or enter recorded physics/input hashes. Preserve the
[kernel boundary](../STACK.md#boundaries-and-data-flow).

## 2. Verified starting point and support matrix

Apple's [feature table](https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)
lists M1 as Apple7, interpolation from Apple5, temporal from Apple7 and denoised
upscaling from Apple9 (October 23, 2026 table, page 4). The actual M1/macOS 27.0.1
fixture returned denoised `supportsDevice=true` and created a denoised object;
a later standalone real-RT/denoising witness also encoded and read back output.
Its producer shaders passed selective validation; the SDK-wide instrumentation
run failed a threadgroup limit. Preserve this runtime/documentation disagreement
instead of enforcing an Apple9/model-name rejection. These are distinct from
execution and qualification.
Check symbol availability, descriptor support and successful instance creation
on the actual device. Never gate only on a model-name string.

| Feature | macOS API floor | Initial engine route | Required hardware evidence |
| --- | --- | --- | --- |
| Spatial | 13+ | Existing Mobile/Metal and Forward+/Metal | M1; one newer supported Mac before a broader claim |
| Temporal | 13+ | Existing Forward+/Metal integration, repaired status/reset | M1 when actual device supports it; one newer Mac |
| Frame Interpolation | 26+ | Proposed engine-owned Forward+/Metal presentation path | Actual supported M1 if available, plus a supported Mac/display at 120 Hz or higher |
| Temporal Denoised Upscaling | 26+ | Proposed Forward+/Metal RT input producer and SDK binding | Actual descriptor support/allocation, real RT inputs and execution; investigate M1 result and retain newer-Mac qualification |

Availability sources: [Spatial](https://developer.apple.com/documentation/metalfx/mtlfxspatialscalerdescriptor),
[Temporal](https://developer.apple.com/documentation/metalfx/mtlfxtemporalscalerdescriptor),
[interpolator](https://developer.apple.com/documentation/metalfx/mtlfxframeinterpolator.md)
and [denoised descriptor](https://developer.apple.com/documentation/metalfx/mtlfxtemporaldenoisedscalerdescriptor.md).
The interpolation reference's macOS 15 claim conflicts with actual symbol
availability; require macOS 26 and installed SDK checks. Do not make the macOS 27
[`requiresPrevColorTexture`](https://developer.apple.com/documentation/metalfx/mtlfxframeinterpolatordescriptor/requiresprevcolortexture.md)
property a prerequisite of the macOS 26 implementation. Explicitly retain previous
color where that API requires it.

Current OpenRC facts, verified in source:

- [metalfx_policy.gd](../../app/render/metalfx_policy.gd) queries driver, renderer,
  RD features and scale limits; macOS 13 bounds use engine assumptions, while
  macOS 14+ queries the native limits. Spatial is a regular supported-device choice,
  while Temporal remains behind `OPENRC_METALFX_TRIAL=1`.
- [reconstruction.gd](../../app/render/reconstruction.gd) already owns mode
  selection, AA restoration, requested/effective receipts and discontinuities.
  Auto uses Spatial only with at least 1,000 nominal internal rows. At 1080p it
  currently chooses Native; manual Spatial remains possible. Keep that rule until
  a separately qualified policy change.
- `guard_runtime_failure()` now has an allocation/enqueue-failure adapter for the
  patched engine's viewport/generation status; injected policy/rollback checks
  passed on M1. Official beta2 lacks that API and returns unknown. Native patch
  compilation, fault injection and GPU/lifecycle qualification remain distinct.
  `request_history_reset()` consumes the patched engine's generation/serial
  acknowledgement after the SDK encode call returns. It bounds pending requests
  by actual Temporal attempts and falls back on a missing or expired receipt.
  This acknowledgement does not establish GPU completion.
- The pinned [viewport source](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_viewport.cpp#L126-L213)
  admits Spatial on Mobile/Forward+ and Temporal on Forward+ only. A menu enum
  does not establish scaler execution, FG or a ray-tracing backend.

## 3. Ownership, files and engine intake

| Boundary | Existing home / intended change |
| --- | --- |
| Provider policy and receipts | Extend `app/render/metalfx_policy.gd` and `reconstruction.gd`; preserve current FSR/DLSS behavior. |
| Camera discontinuities | Reuse `app/render/camera/camera_rig.gd` and its existing reset notifications. No second camera-history system. |
| Settings and persistence | Extend `app/app_state/display_preferences.gd`, `renderer_guard.gd`, `app/ui/settings_screen.gd` and locale sources. Keep draft/apply/cancel behavior. |
| Frame/resource observation | Extend existing `app/render/frame_samples.gd`, `frame_diagnostics.gd`, `research/performance/` reducers and native status bridge only for missing fields. |
| Engine patches and builds | Proposed `tools/graphics/metalfx/` for patch/build manifests and focused engine fixtures; reuse suitable native-build/package helpers instead of copying Windows SDK pins or launchers. |
| Standalone API/RT experiments | Proposed `research/engine-upgrade/metalfx/`; keep drafts outside `app/`. Import existing licensed samples, record provenance and write only missing integration. |
| Durable evidence | Existing `docs/research/desktop-delivery-investigations/`, under the owning substep; generated binaries, images, traces and engine caches remain ignored. |

Before patching, inventory the current upstream Godot implementation and any
existing extension. Prefer an official integrated implementation; otherwise pin
the smallest maintainable patch set against one engine commit. Identify actual
MetalFX creation/encode, render-buffer, viewport, Metal submission and macOS
presentation owners by source trace. Record concrete engine paths in the build
manifest; names in this plan are contracts, not claims that new APIs exist.

Reusable leads already identified:

1. Apple's [Spatial/Temporal sample](https://developer.apple.com/documentation/metalfx/applying-temporal-antialiasing-and-upscaling-using-metalfx)
   and [Metal sample library](https://developer.apple.com/metal/sample-code/).
2. Apple's [interpolation integration reference](https://github.com/apple/game-porting-toolkit/tree/main/game-porting-skills/skills/using-metalfx-frame-interpolation)
   and [integration session](https://developer.apple.com/videos/play/wwdc2025/211/).
   Check licenses and actual SDK declarations; reference prose is not runtime proof.
3. The [experimental Godot Metal RT fork](https://github.com/josephsmithberger/godot-metal-path-tracing)
   advertises `metal_rt`, but that ref returned 404 during review. Inspect immutable
   `eeac9e05dbff0b273b6e4c483c4675530ead992b` instead: 4.7-rc, divergent from our
   4.8-beta2, and not recommended by its author for shipping. Its path replaces
   opaque/motion rendering; it is not a drop-in hybrid pass. Audit ancestry,
   component notices, shader/material coverage and focused tests before reuse.
4. Open [Godot PR 114670](https://github.com/godotengine/godot/pull/114670) is an
   upstream hook candidate, not a merged native-device or presentation solution.
   The [comparable-port review](../research/desktop-delivery-investigations/metalfx-20-investigations-2026-11-14.md#i20--which-comparable-game-ports-offer-useful-reusable-boundaries)
   supplies immutable MetalFX integration references with different licenses and
   rendering architectures. Reuse appropriate source boundaries after intake;
   do not import their engine, game assets or per-frame GPU drains wholesale.

Each custom engine manifest must bind upstream SHA, ordered patch hashes, SDK
build, deployment target, compiler/options, enabled backends, editor/template
hashes, architecture slices and notices. Build editor and export templates from
the same inputs. Preserve the official engine as rollback. A GDExtension that
duplicates Godot's private Metal device/queue/drawable ownership is not the
integration strategy. Metal 4 migration is a separate decision: use the Metal 3
API variants when that matches the selected engine command backend.

## 4. Shared contracts to implement first

### Capability, execution and fallback

Extend the current provider policy with independently represented facts:
`compiled`, `os_available`, `device_supported`, `renderer_supported`,
`inputs_ready`, `instance_created`, `execution_state`, `reason` and context
generation. Scale limits carry native/upscale versus Godot input/output units,
reciprocal conversion, millionths precision and `limit_source` (`device_query`,
`engine_assumption`, `unavailable`). Unknown facts remain unknown; never map them
to success. Probe Metal 3 and Metal 4 descriptor support separately when both
command backends are actually integrated.

Proposed states are `unavailable -> eligible -> allocating -> warming -> active`,
with `failed`/`suspended` and a stable fallback reason. The engine, not settings,
owns transitions after allocation and dispatch. A context becomes active after
successful encoding and observed error-free GPU completion for its generation;
native capture verifies the intended pass during qualification. That still does
not prove the output changed correctly, OS presentation or visual acceptance.
The native fixture must also verify a sentinel-prefilled output and the intended
image; no-op or current-color copy cannot pass as interpolation. Keep operational
status separate from qualification.

Repair the actual native factory and callback boundary: the pinned Temporal
factory result is dereferenced without a nil guard, and Spatial can return a
wrapper with a nil scaler. Guard both before setters/dispatch and propagate a
stable failure category; do not guess an internal failure reason the SDK omits.
Asynchronous scaler optimization may produce valid but slower interim output.
Separate `image_valid`, history warmup and optimized-performance readiness;
record unknown optimization state rather than treating it as failed or waiting
forever. Choose synchronous creation only at an appropriate load/apply boundary.

Factory nil, invalid formats/bounds, incomplete inputs, feature-local GPU error
and stale generation must return a reason without
dereferencing invalid objects. Distinguish these from device loss, queue invalidation
or a GPU hang: those can invalidate Native/raster too. For a device-wide failure,
mark effective execution unknown, stop submissions and attempt bounded engine-owned
teardown/recreation. If that cannot recover, use the existing guarded restart into
Compatibility with Native reconstruction. Retain the request and fault identity,
allow at most one recovery restart for that fault/build, and require a usable
diagnostic exit rather than a restart loop if fallback also fails. Test local
provider recovery and whole-device failure separately in disposable builds.
Pending asynchronous optimization reports readiness without implying failure.
No per-frame effect compilation/recreation or unlimited retries. Prepare
at load/apply boundaries, keep the previous working path during preparation,
cancel stale requests, and retire resources after engine-owned GPU completion.

On FG failure, disable FG while retaining the valid real rendering path. On
denoised/RT failure, restore complete raster lighting and Native reconstruction;
never show unqualified noisy RT. On Spatial/Temporal failure, return to Native
and saved Native AA. Preserve requested preferences and show the session's
effective fallback. Explicit retry after Native or a new valid context is allowed;
repeated faults do not restart every frame. Extend the existing per-build crash
guard, binding failures to engine/patch/provider identity rather than permanently
blocking a machine after an unrelated build change.

### History and observability

Reuse the existing `viewport_request_temporal_history_reset` concept and provider
advertisement where present. Add generation-based status that distinguishes
requested, submitted, encoded, GPU-completed and failed reset; method presence
alone must not unblock Temporal. Capture the requested generation atomically
with dispatch; a late completion cannot acknowledge a later camera cut.

Reset on existing camera cut/target teleport/session replacement, viewport-size,
scale/provider/projection change and invalid resume. Do not reset ordinary motion.
Discard interpolation pairs crossing a reset, pause/resume or incompatible size.
Warm history with valid real frames before resuming interpolation. Drain/cancel
callbacks safely on viewport destruction and app exit.

Initial Temporal admission is one view. The pinned engine shares a context across
its view loop, so multi-view requires independent scaler/history/reset generations
or explicit rejection until proven. Test alternating contrasting view streams and
a cut affecting only one view. The FG/RT branches must retain that restriction
until each has independently isolated per-view resources.

Proposed diagnostic payload, added to existing receipts rather than a new service:

| Group | Required fields |
| --- | --- |
| Identity | Provider/context generation; engine/SDK/patch/package hashes; viewport/view ID; requested/effective modes and fallback reason |
| Images | Observed input/output dimensions, format/color space, HDR/exposure convention, nominal estimates explicitly labeled |
| History | Requested/submitted/encoded/completed reset generations; last reset/failure reason; warm-history state |
| Cadence | Real render IDs/counts, successful generated count, source pair, unique present instance, scheduled/OS-presented/unresolved counts, timestamp clock and observation scope |
| Cost | Whole-frame CPU/GPU, scaler/interpolator/RT passes where available, live allocation bytes/peak and initialization time |

Use a versioned optional payload so older readers reject unsupported qualification
claims without crashing. Derive rates over matching clock windows. Missing actual
presentation feedback stays unavailable; process-loop or scheduled counts cannot
be renamed displayed FPS. Disabled features create no scaler, RT acceleration
structure, extra history ring, FG thread or recurring diagnostic allocation.

Use `MTLDrawable` presented handlers/times for OS-reported onscreen feedback when
supported. Timestamp zero means not yet presented or dropped; do not classify it
as a definite drop. GPU completion, scheduled presentation, OS feedback and
camera-observed photons remain distinct. Never block teardown for a missing
present callback. Calibrate GPU/CPU clocks and qualify observer overhead separately.

### Product controls and valid combinations

Reuse the existing reconstruction picker. Add an independent FG control (`off`
and initially experimental `on`) and an optional RT lighting control only after
their real paths exist. Denoised scaling is one reconstruction provider attached
to RT lighting; it replaces Temporal, rather than running both scalers in series.
Keep saved user overrides, full-output HUD/menu resolution and Native AA settings.
Explain unsupported combinations before Apply; do not silently change renderer,
lighting or unrelated settings to satisfy one dropdown.

| Initial supported combination | Reconstruction | FG |
| --- | --- | --- |
| Current Mobile/Metal raster | Native or existing Spatial | Off; motion-input integration not assumed |
| Forward+/Metal raster | Native, Spatial or qualified Temporal | First implement with qualified Temporal; other inputs need their own gate |
| Forward+/Metal RT experimental | Denoised scaler with valid signals | Off first; denoised + FG tested only after each works independently |
| Compatibility/other drivers/unsupported device | Existing valid raster reconstruction | MetalFX advanced paths rejected; normal flight remains available |

No new automatic renderer switch. Temporal, FG and denoised paths begin opt-in.
Existing Spatial availability and Auto behavior are preserved. Default proposals
are per device/OS/profile evidence, never “enable every Apple feature.”

## 5. Ordered implementation work packages

All rows below are pending implementation/qualification unless a preceding
section explicitly identifies existing code. Dependencies allow source-only
preparation in parallel; native builds and performance runs on a host are serial.
Sizes are relative engineering scope, not delivery dates.

| Substep / owner / size | Work and dependency | Reviewable exit |
| --- | --- | --- |
| DT-MAC-11a — GDU/DT, M | Engine/SDK intake, upstream/fork comparison, exact command backend and build manifests; first step | Reproducible isolated editor/template pair, maintained patch boundary and rollback; native API probe results or explicitly pending hardware rows |
| DT-MAC-07a1 — GDU/VQ, M | Shared capabilities, factory/error status and honest execution; depends on 11a | Real status adapter and nil/error/stale-generation fixtures; existing Native/Spatial behavior preserved |
| DT-MAC-07a2 — GDU/VQ, M | Shared generation-based history acknowledgement; depends on 07a1 | Reset only acknowledged after dispatch completion; multiple viewport/cut/race/destruction fixtures pass |
| DT-MAC-07b1 — VQ/PT, S–M | Qualify existing Spatial; depends on 07a1 | M1 1080p A/B, moving readability, fallback and AA/UI proof; Auto change remains separate |
| DT-MAC-07b2 — GDU/VQ/PT, M | Temporal inputs, AA/history integration; depends on 07a2 | Forward+ comparison, moving/reset evidence and actual device bounds; trial latch removed only for proven engine capability |
| DT-MAC-12a — GDU, L | Interpolator inputs and dispatch, after 07b2 | Valid real-frame pair produces one verified generated image; first-frame/cut/invalid-input bypass works |
| DT-MAC-12b — GDU/PT, L | Engine scheduling, presentation, UI and latency, after 12a | Real/generated identities and cadence verified on suitable display; no duplicated UI, unbounded queue or synthetic simulation tick |
| DT-MAC-12c — VQ/UI/PT, M | FG settings, rate-drop suspend/resume, lifecycle and pilot qualification, after 12b | Optional production path, fallback, sustained/control evidence and hysteresis tests; no default promotion from FPS alone |
| DT-MAC-13d1 — GDU/VQ, L | RT reuse/feasibility and bounded signal producer; after 11a, independent of FG | Native RT fixture and one real OpenRC scene produce validated radiance/G-buffer; material/geometry coverage and remaining gaps explicit |
| DT-MAC-13d2 — GDU/VQ, L | Denoised binding, masks/history and scene coverage; after 13d1 and 07a2 | Supported-device SDK pass, noisy/denoised/reference comparison and safe raster recovery; moving normal-flight coverage before product label |
| DT-MAC-13d3 — VQ/UI/PT, M–L | Denoised product controls and newer-Mac qualification; after 13d2 | Named supported Mac passes full feature gates; M1 loads same app and refuses unsupported path safely |
| DT-MAC-07c1 — DT/GDU/UI/PT, L | Integrated lifecycle, valid combinations and development package; after each selected feature's own gate | Exact package and required CI pass, eligible combinations tested, current defaults recoverable; all four statuses reported separately |

Suggested PR sequence is 11a → 07a1 → Spatial → 07a2/Temporal → 12a →
12b → 12c; the RT producer and denoised sequence can progress independently after
intake. Keep policy/engine/measurement changes independently reviewable; do not
hold a working Spatial correction for the large RT project.

## 6. Spatial and Temporal implementation details

**Spatial:** start with Native versus the existing 0.85 mode on the same
Mobile/Metal workload. At 1920×1080 the nominal input is 1632×918; query actual
SDK inputs in the candidate. Keep full-output UI and identical effects/MSAA.
Add same-input bilinear only as an attribution control: reducing pixels provides
the opportunity; MetalFX has its own cost. Test 2/3 only after 0.85 readability.
Do not lower the 1,000-row Auto threshold to manufacture an improvement.

Before changing the descriptor's Linear color mode, inspect actual MTL formats,
sRGB texture views, transfer functions, alpha and tone-map placement. The current
pass is after tone mapping, but that label alone does not establish incorrect
Linear processing. Use captured gradients, highlights, transparency and output/UI
composition to choose compatible Linear/perceptual/HDR treatment. Every fallback
must restore projection jitter as well as saved AA; historical engine fixes are
regression seeds, not claims that this pin retains their defects.

**Temporal:** compare Forward+ Native against Forward+ Temporal at 1.0, 0.85 and
2/3 only when actual scale bounds admit them. Compare the winning complete
Forward+ configuration against Mobile afterward; report renderer and AA changes
so they are not credited to the scaler alone. Preserve reciprocal-bound/millionths
decoding, distinguish macOS 13 assumed limits, and reject NaN, zero, inverted or
unavailable limits. Test both bounds and ±0.000001, independently rounded X/Y
ratios and actual native factory acceptance.

Use Godot's producers, with a per-signal audit of depth, de-jittered camera/object
motion, jitter and exposure; producer presence is not correctness proof. Record
format/usage, space, direction, sizes, optional nil inputs and exposure conversion.
Verify coordinate sign/scale, reversed depth and projection using captured textures
and known motion. The pinned alpha pass does not provide complete transparent
velocity, and a reactive-format field does not prove a reactive SDK input. Test hinges,
propellers, wind vegetation, skinned actors and particles; camera-only motion is
not enough. Validate reactive handling where supported. Restore saved MSAA when
leaving Temporal; do not stack TAA/MSAA or apply FSR sharpening to MetalFX.

## 7. Frame Interpolation implementation details

Begin with one main viewport and one generated image between two real images.
Use Apple's [descriptor](https://developer.apple.com/documentation/metalfx/mtlfxframeinterpolatordescriptor)
and [input contract](https://developer.apple.com/documentation/metalfx/mtlfxframeinterpolatorbase.md).
Freeze color/exposure/tonemap location, depth/motion dimensions, projection and
actual interval between real rendered frames. Previous/current real images must
belong to the same context generation. An image made by interpolation never
becomes the next real input. Disable unsupported additional views explicitly.

For macOS 26, bind real-pair seconds, vertical FOV in degrees, scalar near/far and
depth convention, pixel-space current-to-previous motion and explicit previous
color. A +10-pixel surface displacement has a -10-pixel previous-position vector
when scale is one. Previous color follows the previous interpolator encode;
skipped/discontinuous pairs require SDK reset and re-priming. Validate first/reset
encode behavior. Projection matrices, content offsets and automatic previous-color
storage controls are 27-only enhancements, not minimum-26 dependencies. Resolve
descriptor/base input-dimension wording against the installed SDK and non-square
scaled fixture; do not assume every input/output extent is equal. Bind the qualified
Temporal scaler for the first path as an integration/performance choice, not a
claim the SDK requires it for every mode.

Reuse Apple's presentation design inside Godot's renderer/display ownership.
If a dedicated presentation thread is needed, the engine owns its drawable
acquisition, bounded frame ring, events and teardown. Do not block the main or
render thread indefinitely waiting for a future real frame; bound and measure
backpressure from drawable and command-buffer pools. Do not run an app-side swap chain.
Preserve real-intermediate-real display order with evenly spaced timestamps.
Late generated work is dropped rather than delaying an already-due real frame.
Handle 60/120/144 Hz, VSync/cap/VRR, focus, minimization and display changes.

Choose either a coherent manual timed-drawable route or `CAMetalDisplayLink`
updates with their supplied drawable/deadline. Respect each route's commit/present
contract; do not combine display-link drawables with incompatible timed-present
methods. The shown PresentThread reference is illustrative and has incomplete
pacing-thread shutdown; design stop/join for every worker, callback, event waiter
and drawable acquisition. An absent producer signal must not prevent shutdown.

Declare resource usage from the created interpolator, not fixed example flags.
Close conflicting active encoders before native effect dispatch. Preserve single
CPU-thread ownership of a command buffer; use appropriate events across queues,
with fences only in their supported hazard-tracking scope. If a Metal 4 backend
is selected, establish residency after each command-buffer begin and preserve it
through all consumers. Completion without a valid output image is a failed probe.

Choose a single verified UI route: isolated full-output UI texture or composition
after the scene image, matching the selected SDK/sample. Keep cursor, menus,
radio/HUD text and overlays free from duplicate blending or interpolated text.
Verify tone mapping and alpha exactly once; test letterboxing and Retina scaling.
The initial reference path interpolates tone-mapped scene color. Freeze a different
HDR ordering only with SDK/input proof and a separate test. Do not assume the
upscaler's reactive mask can repair interpolated smoke or bright lights; test those
effects explicitly. Avoid precomposed-UI removal as the default quality strategy.

Apple's [guidance](https://developer.apple.com/videos/play/wwdc2025/211/) recommends
at least 30 real FPS before interpolation. Developer-only 12a/12b probes report
the observed base without claiming a maintained runtime floor. Product step 12c
adds this proposed initial policy, frozen before native tests: observe completed
real-frame counts over a rolling two-second monotonic window; suspend FG below
30 FPS or after a real-frame gap above 100 ms. Resume only after three consecutive
one-second observations at or above 35 real FPS, with fresh valid history. Start
with FG suspended while collecting that history/rate evidence. A 30-FPS cap may
therefore remain without interpolation; show the rate-related reason and preserve
the user's request. Test rate drops, pauses, missing observations and flapping
around both thresholds. This observed-window policy is not a guarantee about the
next frame. Use a
60-real/120-presented workload as the first high-refresh test target, not a promised
M1 result. At 60 Hz do not imply 120 distinct visible refreshes. Suspend on invalid
pairs and history cuts, then resume with valid real history. Any dynamic base-rate
adaptation beyond this suspend/resume rule is a separate candidate, outside the
first patch. Apple's [latency warning](https://developer.apple.com/videos/play/wwdc2026/357/)
requires measurement, not an assumption that more displayed frames improve control.

## 8. Denoised Upscaling and its RT prerequisite

This is the largest branch. Treat the ray-traced lighting producer as a separate
GDU/VQ deliverable, rather than pretending raster color is a noisy RT signal.
First run a licensed Apple RT sample, or a pinned reusable Godot RT implementation,
on supported hardware and add the real denoised dispatch. This establishes API
use only; it does not qualify OpenRC or justify replacing its engine wholesale.

The first OpenRC vertical slice is an engine-owned, one-sample-per-pixel,
one-bounce diffuse-lighting experiment for existing opaque aircraft/ground meshes,
composited with the existing raster scene in linear HDR. Reuse current mesh/material
data and read-only presentation transforms. Compare reuse of an upstream RT path
against a bounded pass before choosing implementation. If it needs a general
shader compiler or scene renderer rewrite, split that prerequisite explicitly and
keep 13d1 incomplete until the required infrastructure exists.

That prerequisite is now explicit: 0018 adds an opt-in renderer-owned scene
geometry diagnostic before the viewport effect. It expands actual indexed mesh
inputs, retains instance/material provenance, includes candidates outside the
camera frustum, invalidates changed or externally exposed buffers, and checks a
one-shot main-RD ray hit against the CPU. Its input budget is a conservative
cumulative allocation charge, not reclaimed native memory. This work does not
produce lighting or denoiser guides and cannot close 13d1. Native compilation and
the actual field/aircraft cases must pass before using it as a producer boundary.
An additional native move-during-capture case confirms that returned transforms
and hits can remain valid historical data after an instance moves. A current-scene
consumer must independently validate its scene generation, transforms, materials,
liveness and complete relevant caster set; this diagnostic is not that gate.

The next consumer must preserve the custom ground material and existing raster
lighting semantics. A bounded hybrid Sun/contact-visibility contribution is a
candidate for reuse; it requires an explicit split of the selected light's
existing shadow visibility to avoid applying the same shadow twice. It still
needs real linear-HDR noisy radiance and correctly aligned material/depth/motion
guides for denoising. A grayscale visibility image cannot stand in for the SDK's
noisy-radiance input. Keep raster and candidate output isolated until the actual
per-frame encode and GPU outcome permits consumption; an enqueue acknowledgement
or neutral prefill cannot prove a partially recorded SDK pass safe to sample.

The pinned Metal driver has unsupported RT stubs even though generic RD exposes
RT types. Intake must explicitly resolve Metal driver/compute traversal, shader
lowering and resource declarations; this is not a feature flag. The inspected RT
fork replaces opaque/motion passes. Demonstrate that selected pieces can support
the proposed bounded consumer before attempting a wholesale renderer adaptation.

The producer contract includes BLAS reuse and invalidation for mesh changes, TLAS
updates for moving instances, instance/material identity, GPU completion before
reuse/free and scene-stream cancellation. No collision mesh becomes a rendering
proxy silently. Freeze the supported material subset in the fixture; refuse or
return to full raster for unimplemented opaque/alpha/deformation cases. Extend
coverage to actual moving aircraft, their controls and scenery before normal-flight
qualification. A static hangar/inspection demo alone cannot close 13d3.

Classify updates explicitly: rigid instance motion updates the TLAS; same-topology
deformation may use refit; topology/asset/LOD addition or removal requires rebuild.
Measure scratch/AS memory and build/refit plus traversal time together; refit is
not presumed to improve the complete frame. Validate hit/miss/instance identity
through moving hinges, deformation, alpha cutouts and streaming replacement.

Feed the [denoised scaler](https://developer.apple.com/documentation/metalfx/mtlfxtemporaldenoisedscalerbase.md)
actual noisy HDR color, clean depth/motion, diffuse/specular albedo, world-space
normals and roughness. Bind exposure, jitter and reset consistently. Derive optional
hit-distance, strength/reactive masks and transparency overlay only when enabled
and valid; match descriptor formats and queried texture usage. Freeze exact formats,
coordinate spaces and material conventions in 13d1's fixture/manifest, rather than
guessing a packing from property names. Cross-check installed SDK and captures.

Use separate debug views for every input. Keep sky, smoke, fog and other clean
non-surface contributions out of inappropriate denoising, using documented masks
or overlay composition. Avoid double-counting raster and RT lighting. Mirror/glass
signal handling needs its own coverage before those materials are admitted.
Apple's [neural rendering session](https://developer.apple.com/videos/play/wwdc2026/359/)
is the primary input-quality reference; no custom neural-network training is needed.

Strength-mask polarity is unresolved: the current property documentation and the
WWDC explanation disagree. Before enabling that optional input, inspect the
installed SDK and test no-mask versus 0/1 split-mask on noisy and clean patches;
record actual SDK/OS/device semantics. Reactive masking is a different history
control. Keep the optional strength mask disabled until resolved. Compare image
correctness with validation both enabled and disabled: instrumentation can change
behavior, not only timing. Establish high-SPP reference convergence using higher
SPP and independent seeds. Call it a converged in-model reference and record
bounce limits, sampling, clamping and estimator assumptions; convergence alone
does not remove bias or establish physical ground truth.

Compare: same RT workload without denoising; same low-SPP workload with denoising;
and a high-SPP converged reference using the same lighting/materials and fixed
seed/camera. Separately compare whole raster versus RT product cost, without
claiming those different images are an equal-quality speedup. Measure BLAS/TLAS
build/update, ray work, denoise, composite, memory and full-frame time. Verify
disocclusion convergence, thin markings and motion, not only static noise removal.
If 60-real-FPS 1080p is missed, label the feature below the primary performance
target; it may remain an explicit experimental quality option, not Auto.

## 9. Verification matrix and acceptance

Use the [existing tool index](../tools/README.md), [graphics tooling](../../tools/graphics/README.md),
[performance fixtures](../../research/performance/README.md), [debug bridge](../../tools/debug/README.md)
and [M1 access guide](../tools/macos-m1.md). Shared-host admission and isolated
preferences apply. Extend existing checked tests and collectors; do not create
another benchmark framework. Current historical 720p visibility capture is not
a 1080p motion gate: extend its production-path coverage or record native moving
clips at the actual required output.

| Layer | Required checks and cases |
| --- | --- |
| Portable policy/UI | Existing `test_metalfx_policy.gd`, `test_reconstruction.gd`, `test_reconstruction_history.gd`, `test_camera_history.gd`, `test_display_preferences.gd`, `test_advanced_graphics_settings.gd`, renderer/restart tests; add cases for new controls and compatibility rules. |
| Engine correctness | Creation nil, unsupported descriptor/device/OS, delayed initialization, encode/GPU error, stale/reset races, multiple viewport isolation, removal while work is pending, retry and format/size violations. Inject deliberate faults only in disposable builds. |
| Observation/readers | Producer plus existing frame/resource/summary reader tests together; old/missing payload, clock mismatch, generated/real separation and incomplete/substituted runs fail qualification honestly. |
| Native execution | Each claimed provider captured on the real Metal backend; SDK/validation clean, actual device/allocation/pass identity and matching package/engine hashes. Repeat timing without GPU validation/HUD capture. |
| Motion/quality | Distant orientation/markings, landing/gear, propellers/hinges, trees/wind, smoke, sky/water, fast pan, disocclusion, zoom, pilot/chase/flyby, night lights and readable full-output UI. Include normal flight and fixed matched motion. |
| Lifecycle | Native/provider switch, failed creation and retry, Home/Fly, aircraft/landscape replacement, resize/fullscreen/Retina, 60↔high-refresh display switch, pause/resume, minimize, sleep/wake, shutdown with GPU work pending. |
| Simulation | Same-host exact replay/input hashes for stable integrated candidate and observed 240 Hz behavior; retain existing cross-platform policy. No golden/tolerance changes. |
| Negative hosts | Actual unsupported denoised descriptor/device and missing RT producer; missing SDK symbol/older OS, Compatibility, non-Metal and official-engine-without-new-API paths. M1 is not an automatic denoised rejection after its observed support/allocation. Windows/Linux continue launching without Apple framework dependencies. |

Hardware qualification rows are independent: M1 raster/Spatial/Temporal; any
actually supported M1 interpolation; newer supported Mac high-refresh FG;
actually supported denoised/RT (including investigating the M1 observation, plus
a newer Mac); and non-Apple regression. Test one OS below each new
26+ API boundary and the existing project minimum using an actual compatible host
when claiming those OS releases; fixtures alone do not establish OS compatibility.
Do not raise the overall application deployment floor for an optional feature.

1920×1080 actual output is first. Then qualify 1440p/Retina and 4K where claimed;
720p is last. Record logical, viewport, internal, drawable and physical-presentation
observations separately. A render-target estimate cannot qualify a physical output.

Reuse the master's [campaign budgets and protocol](apple-silicon-performance.md#campaign-protocol-and-acceptance-budgets):
five alternating independent short pairs; finalist three 30-minute active-flight
runs per compared role; 20 resource-ownership transitions and final 50 Home/flight
cycles. Separate diagnostic traces from release-equivalent timing. AC and battery,
cold and warm caches, and instrumented/uninstrumented results are separate claims.

Additional feature decisions, frozen before collecting comparisons:

| Decision | Acceptance / report |
| --- | --- |
| Spatial/Temporal performance promotion | Existing ≥5% practical whole-workload screen beyond variation/observer uncertainty, or a named defect/hitch repair; readable motion and no unexplained >5% required-case regression. No gain forecast from the old Retina screen. |
| Process-loop pacing | Retain master's p95 ≤18 ms / p99 ≤25 ms callback-loop proposal and report maxima/bursts. This is distinct from completed real renders and presentation. |
| Real-render pacing | Independently observe completed real render IDs/counts and intervals on a common clock, against the declared real cap. At a 60-real-FPS target, proposed p95 ≤18 ms / p99 ≤25 ms and ≥59 completed real frames/s over each complete ten-second window; report stalls and exclusions. Callback frequency and FG counts cannot satisfy this gate; physical presentation remains separate. |
| High-refresh FG | Compare FG on/off at the same real render cap and workload; report real rate, generated/dropped and actual presented interval distributions against measured refresh. Predeclare a refresh-relative missed-deadline tolerance before native trials. |
| Control latency | Matched input-to-photon experiment: independently visible physical transmitter/control actuation, or a calibrated electrical witness, and a known screen response recorded by the same high-speed camera/clock. Use the actual radio/HID path for an RC-control claim. At least 100 events per role; report sampling resolution, uncertainty and p50/p95/p99. An on-screen input indicator or software input-to-submit alone is diagnostic, not full-path latency. |
| FG latency promotion | Proposed maximum additional p95 latency: one real-render interval at the test cap, plus pilot acceptance. Freeze that budget before tests; if no physical method is available or it fails, keep experimental and unqualified for normal piloting. |
| Denoised quality | Fixed reference clips, noise/error and temporal stability comparisons plus pilot readability; optional quality benefit is distinguished from speed. Define quantitative image tolerances from the reference before the trial; no post-hoc widening. |
| Memory/disabled cost | Document live incremental allocations and actual floor-host headroom before runs. No candidate-attributable sustained pressure/swap or unbounded growth; disabled paths allocate none of their optional GPU work/history/RT structures. |

Memory preparation inventories unique texture/buffer/AS allocations and aliases,
extent/format/mips/sample count, queried alignment and frame-ring depth. At 1080p,
one RGBA16F image is 15.82 MiB and three are 47.46 MiB before additional storage;
this excludes SDK-private histories and RT structures. Track process footprint,
Metal allocated size, RID counts and OS pressure independently; do not add aliased
GPU allocations to RSS as separate physical RAM. Pool uniform sets/resources
instead of allocating them each frame, and retain them until all GPU consumers
complete. Treat `recommendedMaxWorkingSetSize` as a recommendation, not a hard
independent VRAM budget. Separate image-valid and optimized-cost warmup when
comparing synchronous/asynchronous initialization; retain unknown readiness.

Present real FPS, generated/presented FPS, physics rate and latency separately in
reports and any player overlay. Apple's [Metal HUD metrics](https://developer.apple.com/documentation/xcode/understanding-metal-performance-hud-metrics)
may include interpolated frames; retain the counter's actual scope. No “2× faster
simulation” claim and no assertion that interpolation repairs shader/asset stalls.
Keep shader warmup, pipeline caching, Game Mode and display scheduling experiments
separate from the four-feature comparisons.

## 10. Package, rollback and delivery checklist

Before integration, the selected engine must parse/import current app sources and
pass affected renderer/AA/history/UI boundaries. Run required CI for the frozen
candidate and the existing full release gates for an engine-wide change, once
inputs are stable. Focused development tests do not replace those checks.

Create an isolated native development package with matching engine/templates and
normal resource imports. Verify exact same-source replay, all four capabilities,
safe older-engine/unsupported-device launches, preference apply/cancel/restart and
crash-marker recovery. Verify macOS framework weak linking and availability guards
by launching below the new API floor; do not merely compile with an older target.
Preserve existing supported architecture slices, signing mode and entitlements.
No public Developer ID/notarization claim is made without the deferred credentials.

Inspect every Mach-O slice's build target, SDK/load commands and weak imports
using existing Apple tools, not only the app plist. Optional symbols need compile
guards for older SDKs and runtime availability guards for older systems. A new
macOS 27 property cannot enter a minimum-26 path unguarded. Add isolated
fresh-profile and warm-profile baked/unbaked export controls: a reported 4.7
baked-shader startup crash is a test lead, not a proven 4.8-beta2 defect. Metal
baking needs native non-headless export with the actual Metal target driver;
intermediate MIL does not precompile every final device pipeline. Preserve shared
driver caches and label process/user-profile/driver cache state separately.

Each PR carries its owning substep, mechanism, exact paths, tested identities,
focused tests, missing hardware rows and rollback. Each qualified row retains
compact result JSON/Markdown with source/config/engine/SDK/package identities,
paired distributions, pass evidence, visual/latency decision and exclusions.
Raw clips/traces/binaries remain outside Git with hashes and reproduction links.

Final handoff must account for all four technologies individually, including
any incomplete integration or unsupported hardware rows. A completed M1 fallback,
a standalone Apple demo or an experimental fork's screenshot cannot close a
supported-device implementation. Consolidate completed instructions into the
owning runtime/tool guides and retain dated evidence before retiring this plan.

## 11. Prepared fixture specification and first PR

These are fixture IDs, not new track steps or completed tests. The first PR
implements the 11a intake manifest, F01 and pure conversion/receipt cases from
F03 using existing test infrastructure. Native nil injection F02 and actual
factory-boundary F03 cases land with the 07a1 native guards in the next PR; the
unsafe official baseline is never reported as a passing fault test. Any baseline
fault reproduction is isolated in a disposable fixture and labeled an expected
failure. Establish this boundary before attempting a presenter or RT port.
Later PRs add only the affected cases below.

| Fixture | Prepared input / discriminating result | Research |
| --- | --- | --- |
| F01 intake | Official and selected patched engine/templates, SDK/backend/ABI/patch/notices manifest; reject mismatched pair or unavailable ref | I01/I13/I19/I20 |
| F02 factories | Separate unsupported support-query, nil Spatial, nil Temporal, stale callback and device-fatal injections; distinguish provider recovery from guarded restart | I02/I03 |
| F03 bounds | Native versus Godot ratios, provenance, endpoints ± one millionth and unequal rounded dimensions; bind actual creation result | I02 |
| F04 signals | Static/translated/rotated camera plus independent moving/deforming surface and exposure step; analytic displacement versus captured texture | I04/I12 |
| F05 history | Alternating contrasting views, one-view reset, two rapid cuts and late completion; independent histories or explicit admission rejection | I05 |
| F06 AA/color | Failed Temporal then Native with saved AA and zero residual jitter; Spatial gradients/HDR/alpha/texture-view interpretation and thin moving objects | I06/I07 |
| F07 interpolation API | 26-compatible scalar inputs versus optional 27 additions, previous-encode color, reset/skip and non-square scaled extents; direct rendered midpoint reference | I08 |
| F08 presentation | Separate selected manual/display-link route, 60/120/144/VRR, exhausted drawables and missing callbacks; bounded waits and source-ordered outputs | I09 |
| F09 composition | Scene-only history, changing small HUD/cursor and bright particles; UI exactly once on both output kinds and no duplicate tone mapping | I10 |
| F10 dispatch/lifetime | Nonzero sentinel, actual expected image, interrupted signal, resize/destroy while work pending, all workers/callbacks retired; Metal 4 residency after begin when applicable | I11 |
| F11 RT scene | CPU-checked rigid/deforming/LOD/alpha geometry and material coverage; report rebuild/refit/trace plus allocation cost and raster fallback | I14 |
| F12 denoise | Raw/no-mask/0/1 split-mask, noisy/clean patches, converged independent reference and validation on/off, then motion/disocclusion | I15 |
| F13 resource/warmup | Repeated provider/size/Home-Fly cycles, pooled RID/resources, live allocations and sync/async creation first-use versus steady cost | I16/I17 |
| F14 measurements | Real/generated/scheduled/OS-presented IDs, zero/missing presented timestamps, clock calibration, actual radio/physical witness and observer-overhead controls | I18 |
| F15 package | Same-source baked/unbaked, fresh/warm isolated profiles and older-OS loader; no shared-cache deletion | I19 |

Every fixture receipt carries `schema_version`, source/engine/patch/SDK/package
identity, host/OS/device/backend, fixture/case ID, input-buffer conventions and
generation, observation clock/scope, expected versus observed outcome, failure or
unknown reason, and artifact hashes. Record fields unavailable to an older engine
as unavailable. An injected fact is labeled injected and cannot qualify hardware.
The [research ledger](../research/desktop-delivery-investigations/metalfx-20-investigations-2026-11-14.md)
defines evidence limits and source links; this plan owns implementation status.
