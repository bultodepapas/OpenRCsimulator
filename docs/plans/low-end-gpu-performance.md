# Very-low-end GPU performance: corrected Intel execution plan

Updated 22 November 2026 after an adversarial audit of `main` at
`85a2475f60029a4b6b09f23f643119bceea84a45`.
The same-day follow-up integrates Green Paradise and feature-isolation
experiments, refreshed against `main` at
`843f357c07af842054f3ccd6728f93beca9a57ef`. The refresh covers new experimental
flight scaling and Club scenery/material work; the original audit remains a
dated record. This documentation branch does not merge those runtime changes.
Owner: **VQ-07h-A2-R1**, with VQ-06/UI for quality controls, PT1h-R15 for
measurement, DT-11a/UI-05 for loading and the existing scenery/effect owners.
`L0`–`L6` below are substeps of that work, not a new project-wide track.

This is the authoritative execution order for the existing Intel investigation.
It supersedes the priority order in the [sixteen-inquiry report](../research/god-test/2026-11-22-intel-render-internals.md)
and refines the [Intel experiment protocol](../research/god-test/2026-11-22-intel-gpu-experiments.md).
The [automatic-graphics plan](automatic-graphics.md) still owns the shared policy,
saved intent and calibration lifecycle. The [global gates](global-performance-visual-quality.md#gates-to-freeze-in-vq-01c)
remain unchanged. The [adversarial audit](../research/god-test/2026-11-22-intel-plan-adversarial-audit.md)
records why priorities changed and which source claims were rejected.

**Goal:** make the existing UHD 630 installation usable with predictable frame
pacing, responsive loading and readable aircraft, while preserving simulation,
terrain, collision and user choices. Work uses that existing Intel installation.
No other GPU, new hardware purchase, RAM replacement or cross-machine campaign
is a prerequisite. Improvements for other inexpensive GPUs remain hypotheses
until evidence supports their scope.

**Status:** plan corrected; source and retained evidence audited. No runtime
optimization, new setting, benchmark, driver change or host reconfiguration was
performed by this revision.

## 1. Decision: start with pixel cost and Home ground work

The previous follow-up correctly found mechanisms, but promoted some into
first-priority work without measuring their contribution. A 512² target, eight
tree batches or six texture-sampling expressions do not establish a bottleneck.
Use those findings as the residual-work queue in L4.

The strongest retained leads are the [22 November Intel screens](../research/god-test/2026-11-22-linux-uhd630-comparison.md),
with the limitations reconciled in the [evidence audit](../research/god-test/2026-11-22-intel-gpu-investigation.md):

| Evidence | What changes the decision | What it does not establish |
| --- | --- | --- |
| The older ground-heavy Home screen reported about 48 ms for hiding rough ground and about 30 ms for replacing its material. | Prioritize a bounded ground-material experiment in that view. | These overlapping diagnostic estimates are not additive; GPU-poll freshness/raw receipts cannot be rechecked here, and this was a different workload from current Automatic. |
| A one-texture ground replacement in the historical flight screen saved only 1.8–3.7 ms. | Measure Home and pilot flight separately. | Home's larger estimate is not a flight forecast, nor proof that photo sampling alone dominates. |
| Scene Low versus Medium barely changed the fixed Forward+ screen, approximately 13.4 versus 13.2 FPS. | Scene detail alone was not the relevant pixel-cost control there. | Low is not universally ineffective; it changes other work and the current baseline differs. |
| Existing native/bilinear scaling substantially improved the older minimal profile. GFX-IGPU-01 already ships it. | Reuse scale as the first inexpensive pixel-sensitivity screen and existing manual fallback. | Do not count the shipped gain again or add a second render-scale implementation. |
| Current retained Automatic circuits report roughly 38–47 FPS on megatron and simulation/wall 1.00; Home reports 22–30 FPS across the Intel cases. | Start from the improved Automatic bundle and prioritize remaining Home/loading/low-tail problems. | One exploratory pass, ineligible first Home and unverified actual drawable/internal dimensions do not qualify sustained presentation. |

**Expected impact is qualitative.** Screen-filling material/pixel work has the
highest evidence-backed potential for recurring GPU improvement, especially in
Home. Removing a measured construction/compile block has the highest potential
for loading responsiveness. Shadow scheduling, tree culling, sky, water and
smoke are conditional on active work and the view. HUD arithmetic, two-rectangle
relief guards and optional skin composition are lower-priority candidates.
None has a promised FPS gain.

### 1.1 Test the dominant-feature hypothesis with Green Paradise

The user's hypothesis is testable: one expensive feature, an interaction, or a
configuration may dominate the remaining frame cost. Begin with the existing
**Green Paradise → Club field → Green Paradise** screen, followed by controlled
Off/On comparisons inside Club. This is the first discriminating experiment
within L0/L1, before committing to Simple ground or any particular tree,
windsock, flag, bird, reflection or shadow optimization. The
[landscape-isolation protocol](../research/god-test/2026-11-22-intel-gpu-experiments.md#green-paradise-and-club-field-isolation)
owns case order, actual tool support, suspect families and interpretation.

Green builds one rough plane with the shared grass shader and omits Club's
scenery objects and lake. It still has shared sky/sun/weather, aircraft and
aircraft-shadow paths. Club also changes the ground material and mesh: its
photo-detail binding and horizon mesh are absent from ordinary Green. The
refreshed Club also binds four managed pasture/hay/grazing parcels into ground
and, when enabled and bound, worn-path materials, and adds hedges, fences/gates
and trees. The worn-path turf binding is normally inactive at Low. Meadow Off
controls runway plant colonies, not those painted parcels. Their cost remains
unmeasured and hiding Scenery does not undo material bindings. The
cross-landscape screen changes multiple visual and physical inputs; it cannot
identify one culprit or qualify a product optimization.

| Observation, after matching effective state | Next investigation |
| --- | --- |
| Green is much faster and Club repeatedly regresses. | Club ground/painted parcels, vegetation/hedges, fences/property batches, scenery/cues, water/reflection and their interactions; use same-Club reversible masks or material tests to narrow it. |
| Both are slow and a coarse pixel reduction helps. | Shared ground/sky/aircraft pixel work, then the existing L1 scale and L2 material questions. |
| Both are slow and reducing root pixels barely helps. | Check caps, CPU/driver submission, fixed-size auxiliary passes, observer cost and host pressure; this does not prove defective hardware. |
| Frozen views are fast but live motion is slow. | Repeat with advancing accepted time and selectively isolate windsock/shadow updates, flag/bird motion and other live work; pausing also removes simulation work. |
| Only first entry or a particular landscape-switch order is slow. | L3 cache/build/first-draw work or retained-resource/host-state effects, separately from steady rendering. |
| No single feature explains a large combined change. | Check a bounded two-feature interaction or cumulative cost; do not assume one visible object must be responsible. |

Use Home and airborne pilot views as separate populations. Match the camera,
actual pixels and Home-budget state; select airborne on Club as well as Green.
Keep the new experimental flight dynamic-resolution setting Off for attribution
and verify fixed scale in active flight. A saved scalar or phase-end readback
alone is not proof of continuous actual GPU dimensions.
Green is a source of information, not a proposed replacement for Club. Within
Club, keep scenario/contact/collision state unchanged while diagnostic visual
masks are applied and restored. A negative screen is only informative when the
target existed, the intended state held and restoration succeeded.

## 2. Current main: reuse these capabilities

- [Automatic policy](../../app/render/auto_graphics_policy.gd) already recommends
  Standard/Compatibility, Low detail, main MSAA Off, projected Low shadows,
  cloud shadows Off, meadow Off, Few birds and 75% native 3D scale for recognized
  sufficiently weak integrated/software GPUs. Unknown/family-only devices keep
  full scale with a basic bundle; software rendering is not hardware evidence.
- [Display preferences](../../app/app_state/display_preferences.gd) already
  expose 100/85/75/67/50% render scale, frame caps including 30/60, MSAA choices,
  scene levels and many effect switches. [Reconstruction](../../app/render/reconstruction.gd)
  applies the plain scale to Native/bilinear; other providers own their scale
  and AA. Main-view settings do not govern all auxiliary targets.
- [Home's budget](../../app/render/home_render_budget.gd) already temporarily
  multiplies the player's scale by 0.85 or 0.7, verifies benefit and restores
  ownership. Its first reduction needs 90 settling frames and two 90-frame slow
  windows. Time to adjustment is workload-dependent. At a 75% base its lowest
  multiplier is nominally 52.5%; never assume a Home capture is at 75%.
- [Calibration](../../app/render/auto_calibration.gd) is a bounded first-flight
  root-viewport measurement, not a continuous scaler. It can move Automatic
  scene detail by one tier or reject an automatic High renderer. Low cannot
  move lower. New material/scale decisions need L5's stronger identity and
  application lifecycle before automatic promotion.
- Main now includes a separate [experimental flight scale controller](https://github.com/bultodepapas/OpenRCsimulator/blob/843f357c07af842054f3ccd6728f93beca9a57ef/app/render/flight_dynamic_resolution.gd).
  Dynamic resolution defaults to Off. It requires the explicit experiment flag,
  supported completed-frame feedback from a patched engine, Native/bilinear,
  an active flight and a fixed ceiling above its 75% experiment floor.
  Compatibility/OpenGL does not supply that feedback. The current Intel 75%
  baseline therefore has neither a supported adaptive path nor a lower rung.
  Reuse its [owning plan and engine contract](https://github.com/bultodepapas/OpenRCsimulator/blob/843f357c07af842054f3ccd6728f93beca9a57ef/docs/plans/dynamic-resolution.md)
  for any later adaptive candidate; do not build a competing scale writer.
- Source preserves collidable placements across scene tiers through
  [collision setup](../../app/scenery/collision_setup.gd),
  [collision world](../../app/scenery/collision_world.gd) and
  [scenery selection](../../app/scenery/scenery.gd). The collision warning in
  `scene_detail.gd`'s header is stale. The RC-track choice really changes the
  scenario; retain its existing exclusion from graphics reset.

## 3. Success criteria and quality floors

Separate three claims:

1. **A useful optimization:** meet the existing affected-workload gate: repeatable
   benefit beyond paired variation and at least 5% of the complete affected
   workload, or remove a named reproducible hitch/memory defect. A small isolated
   helper saving does not satisfy that gate. Preserve pacing, memory and visuals.
2. **A proposed low-end usability checkpoint:** freeze its named views, workload,
   warmup, frame-cap state and decision rule with the existing VQ/PT owner before
   acceptance. The proposed software targets, evaluated per run rather than
   from a pooled average, are median ≥30 FPS, process-interval p95 ≤40 ms,
   p99 ≤50 ms and simulation/wall 0.99–1.01 in the declared steady flight
   windows. A recurring gameplay stall above 50 ms reproduced in two of three
   candidate runs fails this checkpoint even when its cause is understood;
   cold loading is evaluated separately, never deleted post hoc. A separate
   moving-aircraft/landing/night review must preserve the cues below without a
   material regression against the matched reference. Missing physical
   presentation/input evidence leaves that outcome open. These thresholds are
   a planning proposal, not an approved replacement release gate. At 240 Hz with
   12 maximum physics steps per render frame, 20 FPS is only a catch-up floor.
   A 30 FPS cap remains an explicit user pacing choice, tested separately from
   uncapped capacity; it does not change physics or prove headroom.
3. **Existing product/release qualification:** the 60 Hz process-loop gate remains
   p95 ≤18 ms, p99 ≤25 ms, with the owning visual, native/package and presentation
   requirements. The lower milestone cannot be relabelled as passing that gate.
   Loading retains the owner's Home/Fly readiness targets; record cache state
   and maximum blocking frame rather than averaging away first-use stalls.

Preserve 1920×1080 output as the primary target and distinguish output, drawable
and internal 3D pixels. Keep UI text at output resolution. Lower 3D quality must
retain aircraft silhouette/attitude, runway and pad boundaries, track markings,
shoreline, visible physical obstacles, essential night lights and the aircraft
height cue. Keep current lighting/weather state and the accepted animation
clock; graphics must not alter collision, contacts, fuel, inputs or 240 Hz physics.

## 4. Graphics controls: add useful choices through one settings path

### 4.1 Existing controls and the actual gaps

Use the current Graphics/Display pages, persistence and Keep/Revert flow.
Group later controls in a collapsible advanced section; the Graphics page
already has a constrained 1080p layout. Do not ship a checkbox for every shader
uniform or expose a developer environment variable as a finished feature.

| Area | Current control/behavior | Planned treatment | First delivery |
| --- | --- | --- | --- |
| Renderer, resolution and main AA | Automatic/Standard/High; native 3D scale 100–50%; MSAA; frame cap; reconstruction provider; separately gated experimental flight dynamic resolution, default Off. | Reuse. Clearly distinguish saved scale, effective scale and provider-owned scale. Keep Compatibility and dynamic resolution Off for the fixed Intel attribution baseline. | L1: visibility and matched use of existing controls; no new upscaler. |
| Ground material | Full procedural/photographic work is not selected by an independent player terrain-quality control. Default club photo maps are bound even without enhanced-grass research mode; execution still fades by distance/footprint. | **Ground detail: Auto / Simple / Full.** Two bounded material variants; Simple preserves the flight surface cues and removes only attributed decorative work. | L2: first new quality control. |
| Scene geometry and distant trees | Auto/Low/Medium/High/Extreme; Low uses tree cards and coarser LOD. | Keep physical objects represented. First optimize batching internally; add a separate visual distance/LOD choice only if it changes a measured decision. | L4, conditional. No blanket tree deletion. |
| Near grass and meadow | Meadow Off/On controls runway plant colonies, not Club's newly painted ground parcels. Imported near grass has tier caps; technical grass modes are not a complete player density control. | **Grass density: Auto / Off / Sparse / Standard** only for decorative, non-collidable vegetation. Keep painted parcels in the ground-material investigation, and meadow independently controllable. Do not reinterpret weather or surface friction. | L4, after visible coverage/overdraw attribution. |
| Projected shadows | Technique, quality, distance, softness, aircraft cue and cloud shadows exist. Native atlas quality does not set aircraft mask 256²/4× MSAA or windsock 512²/MSAA-off. | Extend the existing **shadow-quality** resolution to projected targets; investigate a separate aircraft override only if the shared setting cannot express a useful choice. Retain a cheap readable aircraft cue. | L4: bounded resolution/AA experiment before defaults change. |
| Water | Stock lake uses a refresh-on-change probe. Planar is a High-only technical opt-in. Water shader samples screen/depth for refraction. | **Water quality: Auto / Simple / Full.** Simple keeps the water/shoreline/wave representation, tests a material without refraction screen/depth inputs, and a cheaper reflection representation. Do not disable the lake scenario. | L4 only for a costly lake-visible case. |
| Sky and clouds | Ground cloud-shadow Off exists. Sky can still own shared cloud-cache tiles. Density-bound variants are research-only. | **Cloud detail: Auto / Simple / Full** only after a supported, measured simple path exists. Preserve cloud coverage/weather cues, sun occlusion and clock. Keep cache mechanics internal. | L4, conditional; not a promised default win. |
| Lens and aircraft lighting | Lens Auto/Off/Low/Medium/High/Ultra and individual effects; lighting Low/Standard/High and show-VFX switch. | Reuse. Audit inactive processing and release before adding another switch. Preserve essential navigation/landing cues. | L4 internal fast paths if attributed. |
| Smoke | Pilot show-smoke input and technical `--smoke=off`; no general player smoke-quality selector. | **Smoke: Auto / Off / Low / Full**, controlling visual particles/subscriptions only. Preserve pump inputs, engine/fuel state, sound and aircraft profile. | L4 only with active smoke; not a baseline solo-flight claim. |
| Birds, flag motion and HUD | Birds Off/Few/Normal/Many, flags Auto/Static/Basic/Detailed, overlay presets and individual switches. | Reuse. Low Auto flags resolve to Basic, not Static; windsock has a separate motion owner. Prioritize complete-workload cost before micro-optimizing these. | Existing controls; internal work deferred by attribution. |
| RC circuit and lake/world content | Options can change terrain, obstacles and scenario identity. | Keep under scenario selection. Exclude from graphics bundles/calibration, even if disabling them improves a diagnostic frame. | Invariant in every phase. |

### 4.2 Proposed Very Low bundle

Introduce a **manually selected Very Low graphics bundle** only after L2's
Simple ground path is qualified. Use the existing resolved settings and preview
transaction, not a second configuration file or a new scene-detail tier.

The initial candidate explicitly selects the existing Native reconstruction
provider and 75% scale, main MSAA Off, Low
scene detail, Simple ground, projected Low shadows with the existing aircraft
cue retained, cloud shadows Off, meadow Off, Few birds and Basic flag motion.
Existing Low lighting and disabled decorative VFX/lens effects can be explicit
bundle choices after readability checks. The preview lists the fields and
ownership it will change, including the switch from another reconstruction
provider to Native. Revert restores the previous provider and its settings;
the report verifies the effective provider/scale rather than merely a saved
75% request. A kept manual bundle must release Automatic ownership for every
field it deliberately sets, including numeric and string values equal to the
current recommendation. Revert, cancellation or failed save leaves prior
ownership unchanged; return-to-Auto/Restore deliberately reestablishes it.
This scoped transaction is part of L2.4, not deferred to L5.
Keep frame cap, scenario, weather, controls and unrelated accessibility
preferences outside the bundle. A user can select 67% separately when the
matched pixel screen supports the tradeoff; 50% remains an explicit last-resort
choice requiring aircraft-readability review.

Water, grass, cloud and smoke choices join the bundle only after their own L4
deliveries qualify. Do not show nonfunctional options or mark experimental
values as recommended. Existing installations retain their current effective
look until an explicit choice or a separately qualified L5 automatic policy.

### 4.3 Contract required for every new or extended control

**Intent and persistence.** Store requested and effective values separately.
New controls have explicit Auto/manual intent, including a deliberate manual
choice equal to Auto. Existing GPU-owned fields use a type-and-value equality
heuristic, including strings and numeric fields, so they cannot currently
distinguish that case. New controls and the manual bundle must extend the
existing ownership/migration path for their affected fields before shipping;
do not silently take ownership of legacy files. Use one validator, resolver,
save path and
Restore list. Coordinate `graphics_default_keys()` and its telemetry consumer
without expanding telemetry collection. Preview, Keep, Revert, failed save,
cancel and return to Auto must agree in memory, on disk and in diagnostics.
An ownership-only edit is dirty even when every value is unchanged: Keep must
remain available, and Close or preview expiry must restore pending ownership.
Current Settings compares value dictionaries (plus calibration-reset state),
so this requires an affected transaction/UI change as well as persistence.

**Application boundary.** Show whether a value is effective immediately, at the
next world build, or after renderer restart. Prebuild a bounded shader/material
variant outside active flight; avoid runtime compilation while the aircraft is
under control. Update every owning consumer in Home, flight and isolated
previews, including shared ground/near-grass/lake-bank appearance, without
mutating another world's resources. Preserve explicit choices across GPU or
renderer changes.

**Off and ownership.** Off before construction should avoid creating unneeded
nodes, targets and subscriptions. Off in a live scene should stop avoidable
draws, updates, emissions and bake requests; either release resources safely or
document bounded retention and its reason. Shared resources release only after
their last consumer. A cheap suspended state is allowed when immediate teardown
would cause churn. Verify Off-before-build, On→Off, Off→On, scene exit and
cancellation, including no stale first-visible frame or growing residency.

Current examples justify these rules: meadow Off can retain a hidden built
node; a materialized aircraft shadow retains its small target while hidden;
cloud-shadow Off does not remove the sky's legitimate cache ownership; lighting
VFX Off still has some CPU updates. None alone proves a defect or worthwhile
reclamation. Measure retention and transition cost before changing the policy.

**Evidence identity.** New material, vegetation, auxiliary-target, effect and
cache-policy values belong in effective workload receipts. Invalidate or segment
calibration when they change. A saved request, initialized effect and completed
GPU pass are different observations; retain that distinction.

## 5. Phases and subphases

### L0 — reconcile the source, route and baseline

| Subphase | Concrete work | Exit / stop rule |
| --- | --- | --- |
| L0.1 Source and prior evidence | Pin current main, engine and native artifact; inspect changes since the research source. Record which raw runs are available and which measurements are summary-only. Correct stale comments/claims in the next owning source change. | One traceable baseline description; no new profiler framework or broad evidence recreation. |
| L0.2 Existing Intel route | Reconcile the existing test-pool/operator session and its admission. Inventory graphics adapter, actual renderer, audio/compositor, current memory limits, sharing/thermal state read-only. | If no admitted route is available, hardware execution remains blocked; source, settings design and offline checks proceed. Do not bypass admission, substitute another GPU or require new infrastructure before editing a bounded candidate. |
| L0.3 Workload and effective state | Separate usable Home, pilot flight, runway/ground view and loading. Record camera, aircraft, scenery/weather/seed, output/drawable/internal pixels, root AA, auxiliary targets, Home-budget state, experimental flight scale setting/support, caches and actual native backend. | Unknown fields stay unknown. Dynamic resolution stays Off during attribution. A physical scenario/hash is frozen for each A/B; no disabling RC track or lake to qualify a graphics gain. |
| L0.4 Landscape and feature attribution | Use G0–G5 for inventory, warmed Green/Club screening, same-Club isolation, conditional G4 add-back/interaction and live confirmation. G6 belongs to the selected L2/L4 implementation and L6 acceptance. Reuse existing graphics/debug/frame tools and exclude capture overhead from timed acceptance. | Pick the next view/candidate from the result; no assumption that ground or one small object must win. Full three-aircraft/nine-launch tours are not a prerequisite. |

L0 has decision value, not an FPS claim. Its purpose is to keep the rest of the
plan executable and prevent optimizing the obsolete Forward+ baseline.

### L1 — use the working low-cost path and test pixel sensitivity

**L1.1 Preserve the baseline.** Keep the known current Intel Automatic bundle and
manual overrides. Verify native/bilinear scale and main MSAA rather than
reimplementing them. A renderer-restart or save/recovery defect is fixed before
expanding that affected transition; unrelated automatic-classifier refits do
not block a manual material experiment.

**L1.2 Compare one existing scale step.** With fixed effective state, compare
75% and 67% in the affected Home view and separately in pilot flight. A 100% to
75% comparison is relevant where the existing request is 100%; do not relabel
it as a new default gain. Scale is per axis: 75% uses 56.25% of the native pixel
count, and 67% uses about 20.2% fewer pixels than 75%. These are arithmetic
workload ratios, not predicted frame-time reductions. Check distant aircraft,
grounding cues and moving edges at each step. Fixed-size secondary targets and
CPU work do not automatically shrink.
The protocol also permits the existing half-current-scale diagnostic as a
coarse pixel-cost screen. At an effective 75% it becomes 37.5%, not 50% of
native. Restore it after the screen; it is not a new recommendation or a
readability-qualified setting.

**L1.3 Understand Home adaptation.** Record the actual multiplier and elapsed
time to its first decision. For a shader comparison, hold its effective state
constant; test the production adaptation separately. If the long frame-count
settling window is itself a reproducible usability problem, evaluate a bounded
elapsed-time/valid-sample adjustment within the existing owner. Preserve
outlier exclusion, benefit testing, minimum evidence, focus/cover restoration
and provider ownership. Do not add a second Home controller.

**L1.4 Control the new flight scaler.** Explicitly select experimental Dynamic
resolution Off and read back the fixed Native scale in each active flight.
Do not combine an active controller with `@half_res`: both write viewport scale,
and a simulation hold can suspend the controller and restore its ceiling.
Current GOD TEST can seed a fixed scale and Off, but its start/end scalar checks
are not a continuous actual-pixel trace. The protocol owns the supported
Green/Club route and evidence limits. The retained
[Primis synthetic result](https://github.com/bultodepapas/OpenRCsimulator/blob/843f357c07af842054f3ccd6728f93beca9a57ef/docs/research/visual-quality-implementation/VQ-07/dynamic-resolution-primis-2026-11-22.md)
shows a pixel-sensitive patched Mobile/Vulkan test, not a qualified flight
optimization or a reason to replace this Compatibility baseline.

**Exit:** establish whether the remaining view is pixel-sensitive and retain
the sharper setting if a lower one has no useful benefit. Preserve the current
renderer unless a separate residual measurement justifies a different one.

### L2 — qualify the first new-control candidate: Simple ground

**L2.1 Isolate the expensive material component.** Use a reversible A–B–A
diagnostic material on the same field geometry, lighting, camera and scale.
Select this work only after the landscape/family screen leaves ground as an
actionable candidate. A faster Green result alone cannot distinguish Club's
different ground material/mesh from its additional objects.
Keep the normal physical world. Split procedural anti-tiling/noise, fine photo
normal/roughness and other decorative terms only far enough to choose one
bounded simplification. The default field has two relief rectangles, not 32;
photo samples are near-distance/footprint gated. Measure their actual relevance
instead of assigning all ground cost to one expression.

**Decision gate:** if the current Compatibility screen shows no actionable
material cost, or its result remains inconclusive, do not commit to a new
player option from the old ablation alone. Retain Full and rerank the next
attributed L4 or loading candidate. An offline prototype can explore feasibility
while access is unavailable, but cannot count as a performance acceptance.

**L2.2 Implement a bounded Simple/Full variant.** Keep world-space base texture,
runway/pad/track delineation, lighting/haze coherence, shoreline cut and shadow
reception. Simplify the attributed decorative terms; do not substitute an
unreadable flat diagnostic material as the product option. Prefer at most two
maintained shader/material variants initially. Compile-time removal is a
candidate for avoiding unused code/resources, not guaranteed faster code;
include compile time, variant count and memory in the decision. Reuse the
existing include/binder ownership rather than copying the complete shader into
multiple divergent implementations.

**L2.3 Wire Ground detail through settings.** Add Auto/Simple/Full to the existing
validation, persistence, effective report and preview/restore. The initial
application boundary is the next owning world/preview build, labelled as
pending until effective; add live switching only after its shared-resource and
compile/rollback safety is demonstrated. Auto initially preserves the existing behavior;
only L5 may promote a qualified simple recommendation. Do not tie this option
to the RC-circuit toggle, physical relief or enhanced-grass environment flag.

**L2.4 Qualify and expose the manual bundle.** Compare matched Home and pilot
views independently, then the relevant ground/landing and day/night cues. Check
shared material consumers and physical identity. Retain Full if Simple misses
the affected-workload gate or damages readability. The ≥5% gate applies to the
predeclared affected workload; other relevant views must avoid material
regression, not independently gain 5%. After acceptance, add the
small manual Very Low bundle from §4.2. Its transaction must preserve explicit
equal-value intent across restart and GPU recommendation changes for numeric
and string fields; Keep commits ownership and values together, while failed
save/Revert/cancel restores both. Include a non-Native provider's preview,
Keep and Revert, verifying effective scale and provider restoration. Do not
wait for every L4 experiment to deliver this slice. Hardware acceptance remains
open until the admitted comparison exists; software-ready is not
performance-qualified.

**Impact hypothesis:** highest evidence-backed new recurring-GPU opportunity
for ground-heavy Home; smaller or no benefit in some flight views. The original
30 ms diagnostic number is not an acceptance forecast.

### L3 — remove one attributed loading block

This work can run in parallel with L2 after L0, with one owner per capture or
runtime resource. It targets a separate defect and must not be hidden behind
average flight FPS.

**L3.1 Classify cold state.** Distinguish fresh process/profile, Godot shader
cache, Mesa cache, asset import and application preparation. Use isolated owned
cache/profile directories where supported; never clear the player's global
cache or a shared host cache. Retain the preparation notice as UX, not evidence
that the stall was fixed.

**L3.2 Attribute the longest interval.** Time resource acquisition, validation/
aircraft build, geometry extraction, image conversion/upload, deliberate
warmup and first draw. Main's first Home uses a synchronous construction phase;
later preview selection already has staged work and caches. Worker arithmetic
does not remove the preceding GPU-backed surface read. Preserve the indivisible
surface-read maximum instead of treating a 3 ms budget as a hard guarantee.

**L3.3 Change one cause.** Stage one safe construction unit, reuse one bounded
derived result, avoid one proven redundant transfer, or reduce one demonstrated
shader/variant cost. Keep validation, latest-selection cancellation, teardown,
worker ownership, bounded caches and accepted clock. Do not blindly remove
crash warmup, add fleet prefetch, or move active nodes/GPU work to an unsafe
thread. Cache design changes require revision/livery/material invalidation and
peak-memory accounting.

**L3.4 Compare readiness and blocking.** Record process-to-usable Home,
click-to-control-ready flight, worst blocking frame, first visible use and peak
memory for predeclared cold/warm populations. A shifted stall, duplicated
preparation or worse first-flight frame fails. Reuse owning loading gates;
full flight tours are unnecessary for a local construction screen.

### L4 — residual passes, off-state work and additional quality controls

Select **one active, attributed path** after L0/L1 and, where relevant, L2
observations; this is not a mandatory checklist. No improvement is assumed from source inspection.
Use the protocol's suspect matrix to split native shadows, projected aircraft
and windsock masks, water/probe work, sky and lens effects. Flag Static does not
disable the windsock, and a single field-treeline mask does not remove every
tree family. Missing or overridden isolation is an inconclusive experiment.

| Subphase / prior research | First discriminating experiment | Candidate only if useful | Stop / quality condition |
| --- | --- | --- | --- |
| L4.1 Shadows, R01/R02 | Count requests versus actual eligible/rendered target activity; compare shadow-target-only AA/resolution or offscreen receiver updates. | Conservative receiver deferral; shared projected-quality mapping; bounded target retention. | Preserve sun/vertical height cue, thin wings, low sun, reentry, pause and multiple consumers. Never remove the cue merely to pass FPS. |
| L4.2 Vegetation, R03/R07/R08 | Observe card submission/overdraw and draw/CPU cost; compare one near/far split or grass-only density change. | Finer batches, optional nonphysical grass density, later mask/storage or reject-order work. | Keep collidable representations, wind bounds, near-prefix and exactly-600-m behavior. More draws, texture copies or divergent discard may regress. |
| L4.3 Water, R10 | Test the visible water material and actual probe refresh separately; planar-off is already stock on Intel. | Simple water without refraction screen/depth inputs and a qualified cheap reflection path. | Same water body, shoreline and waves; no physical lake deletion or stale first-visible reflection. |
| L4.4 Sky/clouds, R09/R13 | Separate visible sky, radiance refresh and first-use cache bake. | A supported Simple cloud path, bounded cache resolution or owned completion scheduling. | Preserve weather/occlusion and numerical/visual gates. Cache Off can increase analytic work; unsupported half-resolution modes are not a shortcut. |
| L4.5 Effects, R11/R12/R16 plus smoke | Measure inactive VFX/HUD/afterimage CPU work or active smoke/skin composition. | Sleep/fast paths preserving state; manual smoke quality only for an attributed active effect. | Preserve transitions, inputs/fuel/sound, diagnostic state and first-visible payload; skip inactive optional paths. |
| L4.6 Narrow shader work, R04/R05/R06 | Confirm affected pixels and actual compiled/runtime cost after the simpler material decision. | Uniform anchor, derivative-safe zero-mask guard, texture packing or parcel arithmetic. | No inferred six-fetch flight bottleneck; preserve all consumers, compression/mips/precision and ties. Default two-rectangle relief is a small candidate. |

Reuse existing Off/Low switches before adding controls. Make build-time and
live-toggle behavior explicit. Only measured, understandable options enter the
player-facing advanced section or Very Low bundle.

If smoke quality is selected, first separate aircraft equipment/input capability
from visual-node allocation. Current `_supports_show_smoke()` depends on
`_profile_smoke`/`_smoke`; the technical Off fast path also hides AUX assignment,
controller capability and keyboard routing. A player quality switch must retain
profile/capability state independently, then test assignment, keyboard/radio/
controller toggles and reactivation while emissions are Off. Copying the
technical `--smoke=off` path is insufficient. This work remains conditional on
an active, measured smoke cost.

### L5 — safely extend automatic adaptation, after manual choices work

**L5.1 Fix the decision identity for the affected scope.** Reuse A5-R2/R3 and
A7-R1 in the automatic plan. Include source/engine/shader-policy version,
actual renderer/device/driver where available, activity/view, material/effect
tiers, auxiliary workload, output/internal pixels, AA and reconstruction owner.
Current pixel-tolerance matching and root-only timing are insufficient proof
for a new whole-bundle verdict. Unknown evidence cannot promote quality.

**L5.2 Distinguish the decision from its effect.** Keep measured → proposed →
applied → validated states, explicit user intent and a bounded rollback.
Low→Low is not a successful performance adjustment. Apply at a safe boundary;
do not change materials, shader variants or scene identity during active
control. Preserve the current safe renderer and every explicit manual field.

**L5.3 Add a bounded fallback only where measured.** If a qualified Low/Simple
workload remains pixel-limited, consider one existing scale step such as
75→67, then remeasure. Roll back if the gain is absent, readability fails or
another cost dominates. Unknown/family-only GPUs must earn any automatic scale
reduction through the accepted measurement path, rather than being assumed
slow by name. Coordinate Home and experimental flight-controller ownership;
do not introduce a second scale writer. Fixed attribution keeps the latter Off.

**L5.4 Ship the smallest justified policy.** Update the current decision snapshot,
migration/restore cases, effective report and fallback reasons. Keep automatic
changes bounded. The continuous flight controller now exists as a separately
gated experiment; promoting or extending it, a new GPU database model, or a
general quality optimizer is not part of this first delivery. Its completed
viewport feedback does not measure presentation or every secondary target.
Manual controls can ship before automatic promotion completes.

### L6 — integration, evidence and stop

Apply L6 to each selected delivery. It does not wait for all optional L4
experiments or the automatic-promotion work in L5.

**L6.1 Focused verification.** Use the affected existing tests and required CI:
settings validation/migration, ownership, Keep/Revert/save failure, quality
consumer application, cancellation, shadow/vegetation/material contracts and
collision/world identity. Run no GPU benchmark for a prose-only revision.

**L6.2 Existing-Intel comparison.** For a software-ready provisional candidate,
use the smallest
admitted affected-view A/B, then the larger existing tour only when the
three-aircraft whole-session change or final claim requires it. Preserve raw
failures and configuration identity. A headless functional run is not rendered
or physical-presentation evidence; unavailable graphical admission or missing
mandatory Intel monitoring leaves the corresponding formal qualification open.
Offline design and prototype checks can proceed while that access is unavailable;
performance promotion and hardware/presentation qualification cannot.

**L6.3 Adoption and rollback.** Record accepted/rejected changes, measured scope,
quality settings, memory/pacing tradeoffs and exact revert identity in the
existing evidence home. Roll back the single candidate, not unrelated user
preferences. Reject a candidate that lacks useful benefit and rerank the next
attributed cost; one failed experiment does not end the investigation. Meeting
the proposed low-end checkpoint ends that bounded optimization slice, while
any unmet 60-Hz/product/release gates remain visibly open. Stop expanding a
slice once its agreed purpose is met.

## 6. Measurement scope and explicit deferrals

The [Intel protocol](../research/god-test/2026-11-22-intel-gpu-experiments.md)
owns admission and collection details. Initial A–B–A screens choose candidates;
they are not promotion. For retained performance comparisons use the owning
minimum of three alternating pairs, 10 s warmup and 60 s sample, or the stricter
applicable requirement. Loading uses separately declared cold/warm repetitions.
Report run-level distributions, not correlated frames as independent trials.
Avoid screenshot readback inside timed acceptance.

Keep root GPU timing, total process intervals, auxiliary work, simulation pace,
memory and displayed-frame evidence distinct. A root timing decrease may miss
new secondary work. A frame cap is a pacing/power choice, not proof of spare
GPU capacity. Freeze Home's effective scale for component comparison and verify
normal production behavior separately. No unavailable observation becomes zero.

Defer Mobile/HDR or Mesa-version experiments until the known Compatibility path
has a specific remaining defect or attributed cost that the comparison can
resolve. Defer driver flags, GuC/xe changes, engine forks, advanced upscalers,
frame generation, broad tree/sky rewrites, global texture conversions and physics
changes. Preserve shared-host policy and record thermal/resource state; do not
stop other workloads, change power limits or alter Proxmox to improve a report
without the separate existing authorization and owner process.

The first deliverable is the Green/Club and same-Club isolation screen within
L0/L1, followed, if L2.1 supports it, by
**one Simple-ground candidate and its complete settings contract**, with L3
loading attribution in parallel. If ground is not actionable, deliver the next
attributed bounded candidate instead. R01–R16 remain useful evidence, not
sixteen mandatory implementation projects.

## 7. Primary technical references

Checked 22 November 2026. Source-specific behavior above is tied to audited main
and the pinned engine, not inferred from a documentation version.

- [Godot resolution scaling](https://docs.godotengine.org/en/stable/tutorials/3d/resolution_scaling.html): per-axis scale, bilinear availability and the need to check whether a view is pixel-sensitive.
- [Godot shader preprocessor](https://docs.godotengine.org/en/4.4/tutorials/shaders/shader_reference/shader_preprocessor.html): bounded compile-time variants may reduce retained shader code/register pressure; measure against uniform branches and compilation cost.
- [Godot general optimization](https://docs.godotengine.org/en/latest/tutorials/performance/general_optimization.html): identify and retest the bottleneck; the same-device methodology here is constrained by the user's existing hardware.
- [Godot 3D optimization](https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html): culling/LOD and overdraw tradeoffs. Existing project instancing remains the starting point.
- The [earlier primary-source ledger](../research/god-test/2026-11-22-intel-render-internals.json) retains the Intel Gen9, Khronos and exact-engine readback/scheduling evidence; it does not quantify candidate gains.
- [Godot GPU optimization](https://docs.godotengine.org/en/latest/tutorials/performance/gpu_optimization.html) and [Intel render-state experiments](https://www.intel.com/content/www/us/en/docs/gpa/user-guide/2025-1/run-render-state-experiments-with-frame-analyzer.html) support changing one rendering cause and remeasuring. They motivate the isolation method; Intel GPA availability on this Linux/OpenGL installation is not assumed or required.
