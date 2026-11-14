# Apple MetalFX — four-technology implementation plan

Updated: 2026-11-14. Owner: DT/VQ/GDU, with PT for measurement and UI for settings.
Status: implementation work order; no new runtime implementation or hardware
qualification is claimed by this document. Source inspected at
`bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c`; engine baseline:
Godot `4.8-beta2`, `cafc17a192acf67903910a68aeb3c076c0907a4b`.

This is the detailed subplan for Spatial, Temporal, Frame Interpolation and
Temporal Denoised Upscaling under the [Apple master plan](apple-silicon-performance.md).
It owns the substeps registered below; the master retains platform/default,
performance and release gates. The [dated research](../research/desktop-delivery-investigations/metalfx-frame-generation-2026-11-14.md)
owns earlier findings and measurements. Public signed distribution remains
deferred by the owner; local development packaging is still required.

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
upscaling from Apple9. These are eligibility facts, not measured execution.
Check symbol availability, descriptor support and successful instance creation
on the actual device. Never gate only on a model-name string.

| Feature | macOS API floor | Initial engine route | Required hardware evidence |
| --- | --- | --- | --- |
| Spatial | 13+ | Existing Mobile/Metal and Forward+/Metal | M1; one newer supported Mac before a broader claim |
| Temporal | 13+ | Existing Forward+/Metal integration, repaired status/reset | M1 when actual device supports it; one newer Mac |
| Frame Interpolation | 26+ | Proposed engine-owned Forward+/Metal presentation path | Actual supported M1 if available, plus a supported Mac/display at 120 Hz or higher |
| Temporal Denoised Upscaling | 26+ | Proposed Forward+/Metal RT input producer and SDK binding | Supported Apple9-or-later family, e.g. M3-series or later; M1 rejection/fallback |

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
  RD features and scale limits; Spatial is a regular supported-device choice,
  while Temporal remains behind `OPENRC_METALFX_TRIAL=1`.
- [reconstruction.gd](../../app/render/reconstruction.gd) already owns mode
  selection, AA restoration, requested/effective receipts and discontinuities.
  Auto uses Spatial only with at least 1,000 nominal internal rows. At 1080p it
  currently chooses Native; manual Spatial remains possible. Keep that rule until
  a separately qualified policy change.
- `guard_runtime_failure()` currently covers FSR2/FSR3/DLSS, not MetalFX.
  `request_history_reset()` deliberately refuses to treat MetalFX Temporal
  submission as SDK acknowledgement and latches Native on discontinuity.
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
   reports Metal RT and denoised scaling on `metal_rt`, based on NVIDIA's RT fork.
   Its author explicitly warns against shipping it. Inspect ancestry, notices,
   shader/material support and focused tests; pin a commit before reuse. Do not
   adopt its entire engine or borrow its benchmark as OpenRC evidence.

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
generation. Unknown facts remain unknown; never map them to success.

Proposed states are `unavailable -> eligible -> allocating -> warming -> active`,
with `failed`/`suspended` and a stable fallback reason. The engine, not settings,
owns transitions after allocation and dispatch. A context becomes active after
successful encoding and observed error-free GPU completion for its generation;
native capture verifies the intended pass during qualification. That still does
not prove physical display presentation or visual acceptance.

Factory nil, invalid formats/bounds, incomplete inputs, asynchronous initialization,
feature-local GPU error and stale generation must return a reason without
dereferencing invalid objects. Distinguish these from device loss, queue invalidation
or a GPU hang: those can invalidate Native/raster too. For a device-wide failure,
mark effective execution unknown, stop submissions and attempt bounded engine-owned
teardown/recreation. If that cannot recover, use the existing guarded restart into
Compatibility with Native reconstruction. Retain the request and fault identity,
allow at most one recovery restart for that fault/build, and require a usable
diagnostic exit rather than a restart loop if fallback also fails. Test local
provider recovery and whole-device failure separately in disposable builds.
No per-frame blocking compilation/allocation or unlimited retries. Prepare
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

Proposed diagnostic payload, added to existing receipts rather than a new service:

| Group | Required fields |
| --- | --- |
| Identity | Provider/context generation; engine/SDK/patch/package hashes; viewport/view ID; requested/effective modes and fallback reason |
| Images | Observed input/output dimensions, format/color space, HDR/exposure convention, nominal estimates explicitly labeled |
| History | Requested/submitted/encoded/completed reset generations; last reset/failure reason; warm-history state |
| Cadence | Real render IDs/counts, successful generated count, scheduled/presented/dropped counts, timestamp clock and observation scope |
| Cost | Whole-frame CPU/GPU, scaler/interpolator/RT passes where available, live allocation bytes/peak and initialization time |

Use a versioned optional payload so older readers reject unsupported qualification
claims without crashing. Derive rates over matching clock windows. Missing actual
presentation feedback stays unavailable; process-loop or scheduled counts cannot
be renamed displayed FPS. Disabled features create no scaler, RT acceleration
structure, extra history ring, FG thread or recurring diagnostic allocation.

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

**Temporal:** compare Forward+ Native against Forward+ Temporal at 1.0, 0.85 and
2/3 only when actual scale bounds admit them. Compare the winning complete
Forward+ configuration against Mobile afterward; report renderer and AA changes
so they are not credited to the scaler alone. Preserve millionths decoding and
reject NaN, zero, inverted or unavailable limits.

Let Godot produce depth, de-jittered camera/object motion, jitter, exposure and
temporal AA. Verify coordinate sign/scale, reversed depth, FOV/near/far and input
versus output sizes using captured textures and known motion. Test moving hinges,
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

Reuse Apple's presentation design inside Godot's renderer/display ownership.
If a dedicated presentation thread is needed, the engine owns its drawable
acquisition, bounded frame ring, events and teardown. Do not block the main or
render thread waiting for a future real frame; do not run an app-side swap chain.
Preserve real-intermediate-real display order with evenly spaced timestamps.
Late generated work is dropped rather than delaying an already-due real frame.
Handle 60/120/144 Hz, VSync/cap/VRR, focus, minimization and display changes.

Choose a single verified UI route: isolated full-output UI texture or composition
after the scene image, matching the selected SDK/sample. Keep cursor, menus,
radio/HUD text and overlays free from duplicate blending or interpolated text.
Verify tone mapping and alpha exactly once; test letterboxing and Retina scaling.

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

The producer contract includes BLAS reuse and invalidation for mesh changes, TLAS
updates for moving instances, instance/material identity, GPU completion before
reuse/free and scene-stream cancellation. No collision mesh becomes a rendering
proxy silently. Freeze the supported material subset in the fixture; refuse or
return to full raster for unimplemented opaque/alpha/deformation cases. Extend
coverage to actual moving aircraft, their controls and scenery before normal-flight
qualification. A static hangar/inspection demo alone cannot close 13d3.

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
| Negative hosts | M1 denoised rejection; missing SDK symbol/older OS, unsupported descriptor, Compatibility, non-Metal and official-engine-without-new-API paths. Windows/Linux continue launching without Apple framework dependencies. |

Hardware qualification rows are independent: M1 raster/Spatial/Temporal; any
actually supported M1 interpolation; newer supported Mac high-refresh FG;
Apple9-or-later denoised/RT; and non-Apple regression. Test one OS below each new
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
