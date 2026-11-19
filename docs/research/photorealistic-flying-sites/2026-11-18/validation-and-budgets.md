# Validation experiments and resource budgets

2026-11-18. **All new limits below are proposed engineering acceptance criteria,
not measurements or guarantees.** Confirm the device/scene envelope before the
implementation experiment. Existing [Gate P](../../../../ROADMAP.md) and
[SC/VQ](../../../SCENERY-PLAN.md) ownership remain authoritative.

**Strengthened 2026-11-19:** the [Q01–Q12 protocol](../2026-11-19/qualification-protocol.md)
supersedes the corresponding E1–E5 acceptance details. It retains the calculations
and platform boundaries here, while defining independent oracles, zoom-specific
limits, cold recovery, loader retirement and an unambiguous GPU statistic.

## Evidence must answer different questions

| Question | Required evidence | Insufficient substitute |
| --- | --- | --- |
| Does the image project correctly? | Synthetic known geometry and same-eye rendered captures | A plausible-looking screenshot |
| Does it represent the real site? | Surveyed, held-out landmark/runway measurements and actual site photos | The model's own authored coordinates |
| Does contact match the picture? | Independently checked support/obstacle fixtures and debug overlay | A Godot collider or visible tree alone |
| Is the simulation preserved? | Same physical world, engine/backend/input and accepted-state comparison | Two different fields producing similar-looking flight |
| Is it fast enough? | Complete live-flight CPU/GPU/frame-pacing and memory evidence on the named device | Headless tests, editor FPS or a plugin demo benchmark |
| Is the package complete? | Clean offline export with no source checkout/assets available | A successful editor import |
| Can a pilot use it? | Takeoff, landing, low pass and distant attitude/readability review | Renderer correctness or automated image similarity alone |

No runtime test or capture in this matrix was executed while writing the plan.

## Texture-detail and memory calculations

For a 2:1 panorama of width `W`, height `H = W/2`, the approximate full mip
chain adds one third to base storage. At `b` bits per pixel:

`base_MiB = W × H × b / 8 / 2^20`

`mipped_MiB ≈ base_MiB × 4/3`

These are arithmetic estimates. Block padding, driver allocation, decoded CPU
copies, import/transcode staging, reflection/radiance maps and simultaneous old/new
worlds add cost. BC1/8-bpp columns are illustrative block-compression rates, not
a promise of a particular format or quality on every renderer
([G04](sources.md#g04), [M01](sources.md#m01)).

| Panorama | RGBA8 base | RGBA8 + mips | 4-bpp + mips | 8-bpp + mips |
| --- | ---: | ---: | ---: | ---: |
| 4096×2048 | 32 MiB | 42.7 MiB | 5.3 MiB | 10.7 MiB |
| 8192×4096 | 128 MiB | 170.7 MiB | 21.3 MiB | 42.7 MiB |
| 16384×8192 | 512 MiB | 682.7 MiB | 85.3 MiB | 170.7 MiB |

RGBA16F doubles the RGBA8 figures. A small JPEG download does not imply a small
GPU texture. An HDR lighting map need not have the same resolution as the
visible background. Record actual resident/imported format and the measured
load-time peak rather than reporting these calculations as measured VRAM.

### Resolution depends on field of view

At the equator, a panorama supplies approximately `W/360` texels per degree.
The angular content in a horizontal field of view `h` is `W × h/360` texels.
This is a rough sampling count, not a prediction of uniform perspective-space
sharpness or visual quality.

| Horizontal FOV | 8K source texels in view | 16K source texels in view | Width needed for 1920 angular samples |
| --- | ---: | ---: | ---: |
| 90° | 2048 | 4096 | 7680 |
| 60° | 1365 | 2731 | 11520 |
| 30° | 683 | 1365 | 23040 |
| 15° | 341 | 683 | 46080 |

The current pilot camera stores **vertical** FOV. Convert it with
`h = 2 × atan(aspect × tan(v/2))`, in consistent angular units, before using this
table. Test the actual manual-plus-auto result: `CameraRig` permits a final
vertical FOV as narrow as **1°**, not just the auto-zoom law's 6° minimum.
At 1° near the equator, a 16K×8K panorama contains only about **45.5 vertical
source texels across a 1080-pixel-high output**. The backdrop will be heavily
magnified; no plausible modest panorama-resolution increase eliminates this
extreme. This is a declared photographic-detail limitation, not a reason to
silently change the established zoom/aircraft-readability laws.

Native Retina panels and high-resolution PC outputs also need more angular
detail than a 1080p screenshot. Review both normal flight and extreme zoom;
allow lower-detail background where the pilot accepts it and the aircraft stays
legible. Do not call upscaled/generated detail captured ground truth.

## Candidate resource limits

Use these starting limits for a small pilot experiment, then record a justified
revision before changing them. They are additional photo-presentation budgets,
not total application memory or a guarantee for an unspecified computer.

| Variant | Initial photo GPU allocation ceiling | Selection policy |
| --- | ---: | --- |
| 4K low-memory | 32 MiB | Compressed resources and small lighting map; choose a smaller image or revise with evidence if the target requires an expensive uncompressed format |
| 8K normal | 96 MiB | Initial desktop comparison; exact device format and visual artifacts must pass |
| 16K optional | 256 MiB | Only when source detail, texture dimensions and measured headroom justify it |

Ceilings include panorama mips, its lighting resource and photo-specific proxy
textures; common aircraft/world allocations are recorded separately. Measure
GPU allocation where supported and report the limitations of estimates. On
unified-memory devices record total process/driver context without counting the
same bytes twice. Set an explicit whole-process/load-peak envelope from the
selected host baseline in SC-PHOTO-01; no new default is admitted without it.

Only one site's full-resolution variants should be resident during normal
flight. A transition can temporarily need old and candidate resources; budget
that peak using conservative admission estimates and handle reported allocation
failure. Preflight cannot reserve free VRAM, and Compatibility lacks a global
RenderingDevice. [C06–C07](../2026-11-19/implementation-contracts.md#c07--four-identities-and-four-resource-budgets)
define bounded requests, stale retirement and separate package/install budgets.
A bounded low-resolution
preview is a separate allocation. On return to a nonphoto site, no photo
rendering work continues and retained resources fit the declared cache budget.

For frame pacing, propose **60 fps / 16.67 ms** as the first full-flight target
on named supported configurations, with p95/p99, worst hitches and frame
distribution reported. This is not a claim about current OpenRC performance.
Retain the proposed **1.0 ms incremental GPU budget** for the initial photo
layer, using [Q11's defined paired difference of run-level GPU p95s](../2026-11-19/qualification-protocol.md#q11--timing-noise-and-resource-qualification),
regime matching and empirical noise/inconclusive rule. It is not a p95 of
unmatched frame deltas or a V-sync present interval. A baseline already
missing its target cannot qualify a release merely because the photo adds little.

Physics retains the existing **500 µs per 240 Hz tick target**, with p50/p95
and regime-specific evidence as defined by Gate P. The 4.17 ms tick interval is
not the project's allowed physics-computation budget. Adding native scenery
preparation must not take over that budget or change accepted state.

## Experimental matrix

### E1 — projection, registration and color

Use a small synthetic panorama with compass labels, latitude/longitude lines,
known horizon, pole markers and known 3D landmarks. At 1920×1080 and a stated
base FOV, propose at most **2 rendered pixels** of synthetic landmark error.
Test nonzero yaw/pitch/roll, the wrap and poles, serialization and reload.
Repeat on each admitted renderer/format with identical station/orientation.
Inspect background/proxy edges for color, filtering, fog and exposure changes.

For the real capture, retain **4-pixel median / 8-pixel maximum** as an initial survey screen on
held-out hard landmarks at a specified 90° horizontal FOV, with capture/survey
uncertainty reported. It is not the final zoom gate: its four-pixel allowance
can become about 258 output pixels at 1° vertical FOV. [Q02](../2026-11-19/qualification-protocol.md#q02--real-site-calibration-and-optical-detail)
now requires actual per-view errors and independent uncertainty/critical-feature
limits. [Q04](../2026-11-19/qualification-protocol.md#q04--independent-color-reference-and-world-refresh)
compares background and proxy separately to a color reference. Natural foliage
silhouettes have a separately documented approximation; do not average a failed
runway corner away with distant easy points.

### E2 — independent contact and occlusion

Exercise aircraft in front of, beside and behind each opaque proxy and through
intentional gaps. Test low/high speed, tangent hits, just-missing trajectories,
obstacle edges, landing and taxi. Compare physical contact time/position/normal
against independently calculated box/capsule/support cases and show debug
overlays. Verify that visual-only masks do not introduce physical barriers.

The authored proxy cannot be its own depth oracle: [Q03](../2026-11-19/qualification-protocol.md#q03--independent-visibility-clipping-and-contact-geometry)
adds independently measured feature ranges, uncertain-boundary cases and
near/far clipping checks. [Q06](../2026-11-19/qualification-protocol.md#q06--static-scenery-surfaces-state-identity-and-replay)
adds the nondestructible photo-obstacle policy and its impact/reset/restore tests.

For the initial flat runway, propose a **5 cm maximum visual/support surface
misregistration** across its admitted landing area, separately from the existing
estimated millimetre-scale turf relief. This bounds rendering/calibration mismatch;
it does not certify real turf microgeometry or friction. If the survey cannot
support that tolerance, improve the data or narrow the site claim. Reject a
material mismatch such as photo asphalt paired with the stock turf table unless
the scoped surface-law work is explicitly admitted.

Compare all graphics tiers' physical inventory hashes and same-backend accepted
state using the same recorded input and physical world. Changing panorama
resolution or visual shadows must not change contacts. Turning *physical*
obstacles off is a different scenario and is not a valid visual-invariance test.

### E3 — aircraft grounding and world policy

Use resting aircraft, rotation on takeoff, low passes and landing along the
photo-matched light direction. Inspect contact-shadow detachment, shadow edges,
z-fighting, double static shadows, incorrect obstacle shadows, alpha ordering and
reflection content. Check clouds, sky, sun, exposure and time controls before
and after refresh, pause, reset and returning to a 3D site. Photo restrictions
must preserve the user's saved preferences for other sites.

### E4 — capabilities and lifecycle failures

Test every route to a camera/scene: Home, saved camera view, keyboard selection,
cycling, CLI/debug requests, `--look_alt`, crash framing, magnifier and Workshop
trial. Verify the selected site cannot enter an incompatible FPV/airship/ground
builder. Refusal retains the prior accepted selection/session with a clear
reason and a usable way back. Helicopter remains separately admitted.

Run Club → photo → Green → Club; repeat normal transitions enough to expose
retained resources. Inject corrupt metadata, a missing image, unsupported
dimensions, failed import, a cancelled stage and a superseded pending request.
Check synchronous and staged paths. Verify both scene nodes and mutable shared
World/Atmosphere/appearance/cloud-transport ownership restore correctly: the
previous scene must still update, refresh and flow time after failure.

Check existing technical checkpoint restoration and offline numerical replay
with matching physical/backend identity. Current flight-log replay is not a
visual player; no new player-facing replay is required for this pilot. Any later
visual playback has a separate presentation identity and camera-capability gate.

### E5 — target hardware and package qualification

At each named device, test the effective renderer and simulation backend rather
than assuming them from an operating-system label. Start with Windows/Linux
Compatibility, Apple Silicon Mobile/Metal, and the applicable opt-in Forward+
configuration. Additional renderer combinations are diagnostic experiments,
not claims that every combination is supported.

Use 1920×1080 first on ordinary targets. For Apple Silicon Retina, use native
physical-panel resolution and record **output, drawable and internal 3D pixels**
separately, plus scaling/reconstruction mode. A 1080p Mac run cannot close that
panel's gate. Follow [shared resolution policy](../../../../AGENTS.md#display-resolution-priorities)
and the [Apple plan](../../../plans/apple-silicon-performance.md).

Use a repeatable live flight with a fixed aircraft, physical scenario, input,
camera path/FOV, weather and settings. Capture a cold load and at least three
warmed paired runs, long enough for normal cruise, low pass, takeoff/landing,
pause/resume and sustained thermals/device behavior. Start with a 10-minute
qualification workload per selected configuration; adjust only with the owning
tool protocol and record why. Separate loading from flight frame distributions.

Report source/engine/binary hashes, OS/GPU/driver, requested/effective renderer
and physics backend, texture formats, output dimensions, reconstruction, V-sync,
frame p50/p95/p99/max, CPU/GPU timing, ticks/catch-up/slowdown, draw/primitive
counts, RAM/GPU memory, cold/warm loading and retained resources. Compare
panorama-only, occlusion/shadow additions and the complete site while preserving
the same physical definition. A reduced fixture diagnoses cost; only the full
live route qualifies the experience.

Finally inspect an offline clean release package without the source checkout.
Verify images, descriptor, notices and correct fallback resources are present.
Native Mac scope remains a separate exact-domain question; use reference
fallback where required and report it without treating that as native acceptance.

## Existing focused harnesses to extend

Names below exist at the audited baseline. They are relevant starting points,
not evidence that the proposed site already passes. Run only the affected checks
during each implementation slice, through the existing checked runner/test queue.

| Existing test / tool | New behavior to add or verify |
| --- | --- |
| `app/tests/test_field_loader.gd` | Strict field schema remains strict; new descriptor/contact input has separate validation and malformed-data coverage |
| `app/tests/test_landscapes.gd` | Intentionally update the current two-ID expectation; descriptor admission, supported routes, switching and resource ownership |
| `app/tests/test_field_integration.gd` | Site-specific pilot, field, contact and Home/flight agreement |
| `app/tests/test_ui_runway.gd` | New-field runway capability, stale choices and surface-material admission |
| `app/tests/test_landscape_collision_coverage.gd` | Survey/proxy bounds, IDs and clear-space negative cases |
| `app/tests/test_landscape_checkpoint.gd` | Different physical world rejected without mutation; visual resolution does not change physical identity |
| `app/tests/test_camera_route.gd` / `test_camera_settings.gd` | All selection paths, fixed eye and restoration of saved preferences |
| `app/tests/test_world_presentation_refresh.gd` / `test_world_flow.gd` | Photo policy, captured lighting and retained normal 3D behavior |
| `app/tests/test_world_staged_build.gd` | Successful parity plus cancelled/stale/failed candidate global-state restoration |
| `app/tests/test_optional_resource_loading.gd` | Unselected, failed, superseded and released photo-resource cache lifecycle, alongside measured process/GPU settling |
| `app/tests/test_native_macos_domain_world.gd` | New-site refusal/fallback remains truthful; stock-domain evidence is not silently broadened |
| `app/tests/test_native_replay.gd` | Required if backend/contact identity changes; same-backend numerical evidence |
| `app/tests/check_field_pack.gd` | Sidecar/asset/notices resolution from clean exports, beyond existing field JSON coverage |
| `app/tests/test_mr_camera.gd` | Conditional later FPV route and camera integration |

Use [graphics diagnosis](../../../tools/graphics.md),
[landscape tools](../../../../tools/landscape/README.md),
[flight logging](../../../FLIGHT-LOGGING.md) and
[test admission](../../../../tools/testqueue/README.md). Inspect each current
tool contract before invoking it. Historical fixed-engine or 720p scenery
fixtures cannot qualify current 4.8.beta2/1080p/native-panel behavior; a
report-only mode is not a passing gate. Rendering-only captures do not measure
live simulation cost.

## Go / no-go record

The renderer experiment advances when projection, essential occlusion, aircraft
grounding and required target paths are demonstrated. The real-site pilot
advances when field/contact accuracy, activity restrictions, lifecycle,
performance, pilot readability and package rights/resources pass. Unresolved
gates stay explicit; a pretty image cannot overrule a physical mismatch.

For Terrain3D or splats, compare the same bounded field against the ordinary
mesh baseline. Adopt only with measured benefit and acceptable physics,
platform, rights and maintenance implications. Keep all source data and known
limitations so a renderer choice can change without losing the field survey.
