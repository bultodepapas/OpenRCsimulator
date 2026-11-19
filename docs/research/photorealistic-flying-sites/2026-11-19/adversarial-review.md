# Photographic scenery: adversarial review

2026-11-19. Review of planning commit
`0dac71fc8a829a8a9ea33fd62c4e45703f4021ca`, checked against current
`main` at `1188f1d4a1e31fd8263336b645db86535bca062f`.
[Research scope and sources](research-log.md). [Current plan and step status](../../../plans/photorealistic-flying-sites.md).

## Verdict and evidence standard

The fixed-pilot panorama approach remains the best first experiment. The earlier
plan correctly separates photographs, visual depth and authoritative contacts.
Its weak point was that several acceptance statements could be satisfied by a
convincing screenshot while leaving a broken flight, a misleading measurement or
an unusable release.

This review identifies **18 actionable gaps**. They are plan defects and
source-supported integration hazards, not eighteen observed runtime failures:
the photographic site does not exist yet. High priority means the omission can
invalidate the first site's correctness or usability; medium means it can
invalidate a route, measurement or delivery decision. Conditional items apply
only if their associated feature is admitted.

The fixes are expressed in [implementation contracts](implementation-contracts.md)
and [qualification cases](qualification-protocol.md). Those are proposed
requirements, not passing results. Only the canonical SC-PHOTO ledger owns
implementation status.

## Findings

### R01 — wide-view calibration can conceal severe zoom error

**High; old acceptance rule is insufficient.** The original E1 allowed a
4-pixel median and 8-pixel maximum at 1920×1080, 90° horizontal FOV, then carried
the same angular error to other views. The actual
[CameraRig](../../../../app/render/camera/camera_rig.gd) permits 1° vertical FOV.

At the optical axis, the four-pixel allowance is 0.238731° and becomes
257.824 pixels at 1° vertical FOV and 1080 pixels high. Eight pixels become
515.649. Conversely, four output pixels at 1° correspond to only 0.168564
latitude texel in a 16384×8192 panorama. These are
[reproduced pinhole calculations](../../../../research/photorealistic-flying-sites/optics_review_receipt.json),
not measured calibration failures. The old plan already acknowledged low
panorama detail at extreme zoom; the additional defect is treating a wide-angle
registration gate as sufficient.

**Correction:** C02/Q02 require actual zoom-specific output errors, held-out
landmarks, uncertainty and a declared qualified visual envelope. Keep the
established camera laws. Extreme zoom remains available with an explicit
background-detail limitation; an unacceptable occlusion error cannot be waived
as mere texture softness. Sources: [H01–H05](research-log.md#primary-source-register).

### R02 — a proxy can validate its own wrong depth

**High; oracle independence.** Original E2 places aircraft before and behind
authored proxies. A proxy displaced along the same eye rays can retain the same
projected image while changing where the aircraft is hidden. The photograph
does not independently determine that range.

**Correction:** C02/Q03 require held-out measured near/far feature ranges and
3D test paths independent of the rendering proxy, including holes and overlapping
features. Use uncertainty intervals; do not call a path definitely clear when
the survey cannot resolve it. Collision volume and photographic alpha coverage
remain separate quantities. [H06](research-log.md#h06) supports the image/geometry
method; the oracle failure is a geometric inference, not a reported OpenRC bug.

### R03 — a new site does not inherit the Club near-plane clearance

**High; source-supported clipping risk.**
[CameraRig](../../../../app/render/camera/camera_rig.gd) sets a 0.5 m pilot near
plane and reapplies it on update. Its comment justifies that value from the
current station barrier; [Spec](../../../../app/spec.gd) supplies a 21,000 m far
distance. Euclidean distance alone does not establish camera-space clearance
through the widest allowed view. A clipped proxy leaves its photographed
silhouette visible but loses depth coverage.

**Correction:** C02/Q03 admit the new site's camera-space clearance, far-range
ordering and actual depth format. Start by choosing suitable site geometry.
A smaller near plane is a separately reviewed rig change, not a one-time camera
assignment. Depth precision differs by renderer; source comments and generic
documentation do not prove an actual target format. [H02](research-log.md#h02),
[H12](research-log.md#h12).

### R04 — a casting sun does not establish a photo-ground shadow receiver

**High; source-supported ownership risk.**
[ShadowSettings.resolve](../../../../app/render/shadow_settings.gd) suppresses
the projected cue for Native and enables a native/projected handoff for Auto.
[Shadow.native_handoff](../../../../app/render/shadow.gd) fades according to a
registered casting sun and camera depth. It does not prove that photographed
ground receives that native shadow. A sky background alone is not such a surface.

**Correction:** C04/Q05 define receiver-aware effective policy. The first
candidate gives the projected cue sole photo-ground ownership; aircraft
self-shadow is a separate capability. Native-only is not offered as effective
photo-ground rendering until demonstrated. Preserve the user's requested
preference and explain a fallback. Test all modes, the old handoff band and
restoration to a normal site. [H07](research-log.md#h07).

### R05 — an aircraft shadow can darken an already photographed shadow twice

**Medium; different from duplicate static casters.** The old plan already
forbids rendering a tree's static shadow over the same photographed shadow.
The [projected receiver shader](../../../../app/render/projected_shadow_receiver.gdshader)
also blends a black aircraft shadow. Over a photo region already receiving only
ambient illumination, that overlay reduces the ambient contribution again.

**Correction:** C04/Q05 add a controlled sunny-to-pre-shadowed crossing against
an independently rendered sun-plus-ambient reference. Prefer a simple clear
landing strip for the first site. Where necessary, qualify an authored
sun-visibility/strength mask or limit the receiving area explicitly. A single
display-referred LDR photo cannot be promised to recover separate direct and
ambient illumination. This is a compositing limitation, not an observed release
defect. [H07](research-log.md#h07), [H09](research-log.md#h09).

### R06 — matching background and proxy colors can still be wrong

**High; oracle independence.** Original E1 checks their join. Both could undergo
the same incorrect extra conversion or tone mapping and still agree.
[engine_srgb.gdshaderinc](../../../../app/render/world/engine_srgb.gdshaderinc)
documents a Compatibility workaround with a 4.7.2 rationale; that is not a
qualification of the pinned 4.8.beta2 path.

**Correction:** C03/Q04 define source primaries, transfer, display/scene
reference, exposure and the complete output transform. Compare each photo path
independently with a known color reference before comparing their seam. Review
aircraft lighting in that same environment. [H08](research-log.md#h08),
[H09](research-log.md#h09).

### R07 — projective mapping needs a per-fragment and seam contract

**Medium; underspecified proposed shader.** “Project the photo onto a proxy”
leaves room for interpolating longitude/latitude UVs computed at vertices.
The angular mapping is nonlinear. At the longitude branch cut, implicit
derivatives can also choose the wrong mip even when repeated colors meet.

**Correction:** C01/Q01 compute direction from interpolated world position
at each fragment, with the same orientation as the sky. Test a large triangle
and seam-crossing proxy at varied zooms. If needed, compare gradients derived
from the continuous direction or a seam-safe cube representation; taking
derivatives of an already wrapped UV does not fix the discontinuity.
[H10](research-log.md#h10), [H11](research-log.md#h11). No existing photo shader is
claimed to contain this bug.

### R08 — static photographed objects need an explicit damage policy

**High; physical/visual divergence.** SC-PHOTO-04 previously requested stable
damage IDs but left the policy open.
[SceneryDamage](../../../../app/sim/scenery_damage.gd) can mark wood, wire, foam,
straw and foliage broken; [SceneryCollision](../../../../app/sim/scenery_collision.gd)
then excludes those groups. The
[visual damage director](../../../../app/render/crash/scenery_damage.gd) changes
authored meshes, not pixels baked into a panorama.

**Correction:** C05/Q06 require photo-baked objects to use the existing
nondestructible `none` damage policy for the first pilot, while retaining their
ordinary collision response. A later breakable photo object requires alternate
background/depth state and synchronized contacts. Check a second impact/pass
after a high-energy hit, reset and checkpoint restore. A stable ID alone cannot
close this issue.

### R09 — transition rollback does not solve failed cold startup

**High; missing recovery state.**
[Preferences](../../../../app/app_state/preferences.gd) accepts a saved landscape
by catalog membership; [app startup](../../../../app/app_root.gd) then builds it.
The existing [FieldError](../../../../app/ui/field_error.gd) screen offers Quit.
There may be no previous Home to restore when a saved photo asset is absent.

**Correction:** C06/Q08 define an explicit recovery screen with Retry, Choose
another site and Quit, independent of failed photo resources. Preserve the
requested preference until a successful explicit replacement. Automation fails
with a diagnostic instead of substituting a field. Exercise both startup paths,
missing assets and no admissible texture variant. This respects the existing
no-silent-substitution policy.

### R10 — stale rollback must not restore over a newer world owner

**High if publication can overlap; prevent it by design.** Original loading
text requires shared-state restoration for failed/stale builds.
[World](../../../../app/render/world/world.gd) has process-wide live/night/flow
ownership; detached nodes alone do not isolate it. Blindly restoring an old
snapshot after a newer commit can undo the new owner.

**Correction:** C06 selects preparation without shared publication and a
serialized, owner-checked activation point. Stale candidates only retire their
own allocations. Reuse [Home's existing pending gates](../../../../app/app_root.gd).
Any unavoidable activation rollback must verify its owner/generation.
Q07 covers late completion and attempted stale publication. This sharpens the
existing transactional design rather than claiming it ignored globals.

### R11 — runway starts and Natural Random are coupled

**Medium; specific route failure.**
[Home](../../../../app/ui/home.gd) enables Natural Random from
`runway_available`, as does its [route guard](../../../../app/app_root.gd).
[ScenarioConfig](../../../../app/scenarios/scenario_config.gd) still requires
`field_id == "default"`; [NaturalRandom](../../../../app/scenarios/natural_random.gd)
validates against the loaded field. Generalizing only the runway flag exposes
a briefing/generation path that refuses the photo field.

**Correction:** C05/Q09 separate runway-start and Natural Random capabilities,
enforced in UI and route admission. A photo runway can work while Natural Random
remains unavailable. Do not claim the current code silently starts a valid random
flight on the wrong field; the confirmed downstream behavior is refusal.

### R12 — the surveyed coverage boundary has no operational behavior

**Medium; missing product contract.** The descriptor names an outside-area
policy, but the prior plan does not choose one.
[GroundSurfaces](../../../../app/physics/ground_surfaces.gd) supplies a rough
catch-all outside authored rectangles; it is not a survey validity guard.

**Correction:** C05/Q09 choose a read-only “outside surveyed site coverage”
notice based on accepted NED state. Define inclusive bounds, aircraft extent,
fast crossings, reset and re-entry. Physics continues unchanged. Call this
survey coverage rather than an aircraft flight envelope, which has a different
meaning. It does not make the ground beyond the surveyed area accurate.

### R13 — friction changes can silently change relief

**Conditional medium.** The old plan correctly assigns paved or irregular sites
to SC-PHOTO-04b. The extra dependency is
[GroundTerrain.amplitude_for_rolling_factor](../../../../app/physics/ground_terrain.gd):
relief derives from the rolling multiplier. Its independent relief sampling
entry point is not yet consumed by existing sessions.

**Correction:** C05/Q06 keep a qualified turf pilot or require separately
versioned material and relief definitions before admitting other surfaces.
Changing friction while holding relief fixed must leave support geometry
unchanged. Contact, rendered ground, replay and native/reference ownership all
belong in that extension.

### R14 — numerical replay and material provenance are different promises

**Medium only if exact attribution is claimed.**
[FlightLog](../../../../app/sim/flight_log.gd) records raw surface arrays and
[its CLI](../../../../app/tools/flight_log_cli.gd) reinstalls them. Live
[FlightSession.set_field](../../../../app/sim/flight_session.gd) also installs
region/material provenance. Replay support observations can therefore fall
back to unspecified material; hull-scrape observation consumes that metadata.

**Correction:** C05/Q06 explicitly retain numerical replay for the pilot and
do not promise identical material-attribution reports. If that reporting is
required, scope the versioned provenance capture separately. This finding is
**not evidence of changed numerical flight dynamics**.

### R15 — authoring hashes and exported resource identities are not interchangeable

**High for package admission.** The old descriptor/pipeline names source/output
hashes, but Godot imports images/models into generated resources. A source PNG
may not be readable through FileAccess in an export. The
[three export presets](../../../../app/export_presets.cfg) also need explicit
non-resource filters; existing landscape JSON filters do not generally include
new site notices. [check_field_pack](../../../../app/tests/check_field_pack.gd)
does not yet check the proposed photo descriptor, inventory and notices.

**Correction:** C07/Q10 distinguish source/derivative provenance, raw physical
data identity and release artifact identity; resolve imported assets through
ResourceLoader. Choose final paths and verify every export's actual inventory,
including required offline notices and missing-file negative cases. Do not
assert that `data/*.json` necessarily excludes nested field JSON: inspect the
actual package. [H13–H15](research-log.md#h13).

### R16 — one resident variant can still mean three shipped variants

**Medium; missing distribution budget.** Every current preset uses
`all_resources`. Merely selecting one of 4K/8K/16K at runtime does not exclude
the other recognized resources from the package.

**Correction:** C07/Q10 add separate compressed-download and installed-size
budgets, per-target variant inventories and a baseline delta. Keep a 16K master
outside the exported project until the measured benefit justifies shipping it.
A bounded GPU allocation is not a bounded installer. [H13](research-log.md#h13).

### R17 — memory preflight and stale-result rejection are not allocation guarantees

**High for reliable loading.** The previous plan already warns that cancellation
does not automatically stop work. It still leaves the admission and retirement
mechanism unspecified. RenderingDevice is not available on Compatibility;
used-memory counters are not a free-VRAM reservation. A generation token stops
stale publication but does not stop an in-flight decoder.

**Correction:** C06–C07/Q07 use validated conservative tiers, device queries
where supported, bounded concurrent work, one candidate at a time and explicit
retirement. Include old, candidate, upload/staging and stale loads in peak
accounting. Never call threaded-get early on the UI thread. Unknown capabilities,
load failure and rapid repeated selections must be exercised. Extend
[test_optional_resource_loading](../../../../app/tests/test_optional_resource_loading.gd)
for cache observations, alongside actual process/GPU measurements.
[H15–H17](research-log.md#h15).

### R18 — the GPU budget needs a defined statistic and an inconclusive outcome

**Medium; measurement validity.** Original E5 proposes at most “1.0 ms p95
incremental GPU cost” but does not define the increment. Present intervals under
V-sync are not GPU elapsed time. A difference between unrelated p95 values is
not a p95 of paired frame differences.

**Correction:** C08/Q11 specify matched workloads, a real GPU timing method,
paired-run ordering, the statistic and a noise decision. The default is a
paired difference of run-level GPU p95s for each flight regime, clearly named.
Missing timers or uncertainty crossing the budget is inconclusive. A separate
normal-V-sync complete-flight run qualifies delivered pacing and physics
headroom. [H18](research-log.md#h18), [H19](research-log.md#h19),
[H25](research-log.md#h25).

## Findings rejected or deliberately deferred

The review does not manufacture criticism where the earlier plan was already
correct:

- KTX/Basis, gltfpack, Terrain3D, splats and engine replacement were conditional.
  Refine extension-only versus fallback experiments; do not add dependencies
  without a measured need.
- The pilot already uses trusted bundled assets. Downloaded PCK authentication
  and namespace/content isolation belong to a later feature; a sidecar hash
  alone would not provide authenticity. No downloader is needed now.
- The 5 cm support/visual alignment proposal is not a measured survey accuracy,
  friction validation or universal pixel tolerance.
- The earlier resource pass already acknowledges the adopted maple mipmap
  policy and its bounded beta1 Windows evidence. It must not be described as
  absent, newly implemented, or qualified on beta2/Metal.
- Offline numerical flight replay is not an existing visual replay player.
  No such player is necessary to close the first photo-site experiment.
- A software-only OpenGL capture can validate an image contract, but cannot
  establish target GPU throughput. No new runtime capture or hardware benchmark
  was performed for this review.

## Why the revised plan should produce a better result

The first implementation now has a controlled synthetic target before expensive
capture, independent image/depth/color oracles, an explicit ground-shadow owner,
a physical policy compatible with a static photograph, recoverable startup and
a package that can be tested without the author's checkout. A failure identifies
which contract failed and what evidence is missing; adding visual polish cannot
silently close that gate.
