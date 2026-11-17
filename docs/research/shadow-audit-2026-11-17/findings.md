# Shadow findings register

Baseline: `3c91936ab8f9064daa798311b5fb3e89e28d3754` · 17 November 2026.
[Scope and verdict](README.md) · [Reproduction evidence](validation.md) · [Technology decisions](technology-review.md).

There are **26 findings, not 26 newly discovered bugs**. P1 means resolve before claiming convincing, generally supported shadows; P2 means the next correctness, efficiency or clarity slice; P3 is an explicit design decision. These are remediation priorities, not measured crash/security severities. No P0 issue was established.

Evidence labels: **R** = production-module behavior reproduced in the isolated headless fixture; **S** = current source/call-chain inspection; **G** = rendered, GPU or full-activity gate still required. An R pass means the stated observation reproduced, including an undesirable behavior. It does not mean the game is fixed. All line numbers below refer to the frozen baseline; [source-index.json](evidence/source-index.json) binds cited files to their hashes.

## SA-01 — Projected cannot satisfy aircraft self-shadowing

**P1 · R/S/G · Known capability gap · VQ-04b-S01/S04.**

`shadow_settings.gd:64–79` enables native maps only for Auto/Native; Projected suppresses them. `projected_shadow.gd:137–181,238–241` constructs a separate flat ground receiver. That representation cannot shade the wing onto the fuselage, gear onto the body, or tail onto another aircraft surface. The resolver matrix reproduced the routing; it did not run three renderers.

This is a direct explanation for absent self-shadowing **when Projected is selected**. It is not evidence that self-shadowing is universally disabled. Interactive Auto already requests native shadows, and common aircraft builders do not contain a blanket body-shadow disable. Inspect the actual imported materials, light enablement, bias, cascade and pixel coverage before diagnosing Auto/Native images.

**Acceptance:** a fixed lit aircraft must show correct wing/fuselage/strut occlusion in a supported natural-shadow route. Show the Projected limitation or select an explicit supported fallback per activity. Keep the optional height cue independently named.

## SA-02 — Auto retains overlapping direct-shadow routes

**P1 · S/G · Known ownership risk · VQ-04b-S01/S05.**

`shadow_settings.gd:64–79` deliberately enables both routes. The aircraft's native caster and its planar receiver can contribute to the same ground region; the latter uses black alpha blending (`projected_shadow_receiver.gdshader:17–18`). This permits excessive darkening or two edges. Source coexistence does not prove that either artifact occurs in the user's frame.

The plan already requires one direct-shadow owner per caster/receiver/light combination (`docs/plans/shadows.md:60–65`). Light receiver masks and caster masks do not implement an arbitrary pairwise shadow partition. Disabling a runway's shadow reception can also remove tree/building shadows; duplicate lights can change energy and atlas sharing.

**Acceptance:** isolate Native, Projected and Auto at identical light/pose/exposure/AA; attribute each dark region and demonstrate the chosen partition. Test native self-shadow plus ground coverage, building interception and an unoccluded color control. Do not promote a hybrid from a still showing only a darker runway.

## SA-03 — Projected articulation is frozen at binding

**P1 · R/S/G · Known unfinished S04 · VQ-04b-S04.**

`projected_shadow.gd:35–67` merges child transforms once. `main.gd:3595–3617` subsequently animates controls, flaps, folds and mechanisms; the mask cache tracks root basis/light/frame rather than those changes. The fixture rotates a child hinge 35°: fresh collected vertices change, the installed proxy retains the old vertices, and its redraw count remains 1.

Native maps may independently follow the live meshes. Re-rendering the same merged proxy more often would not fix its stale local shape. The dedicated windsock path already demonstrates a bounded shared-deformation approach.

**Acceptance:** compare neutral/full control, gear up/down, fold/unfold and hidden/detached components at the same root pose. Use shared deformation or small separately owned moving casters, with explicit revision/lifetime rules; avoid full-aircraft collection every frame. Preserve model hinge names and the simulation/render boundary.

## SA-04 — Fixed receiver plane ignores terrain and nearer surfaces

**P1 · R/S/G · Known S07 approximation · VQ-04b-S07.**

`projected_shadow.gd:119–134,238–241` projects to a world plane at `Spec.SHADOW.height` (0.05 m). `shadow.gd:189–205,245–257` uses absolute world height for the cue's fade/softness. There is no terrain/roof/receiver query in this path. The fixture moves the source from y=2 to y=12 m; receiver y remains approximately 0.05 m.

That proves the geometric limitation, not an observed floating shadow on a particular bank. Slopes, elevated courses, roofs, intervening objects and lake edges need a valid receiving surface and terrain-relative distance. Simply moving one large plane to one sampled height cannot represent a slope or discontinuity.

**Acceptance:** exercise flat runway, bank, ramp, roof, shoreline and an intervening object; compare against native coverage. Restrict/fade invalid pilot-aid projection or adopt a qualified receiving-surface method. Preserve terrain collision identity and do not alter physics to fit a visual plane.

## SA-05 — Projected masks discard alpha and source material semantics

**P2 · R/S/G · Known representation gap · VQ-04b-S04/S06.**

`projected_shadow.gd:35–67,161–180` retains vertex positions and substitutes one mask shader; UV coverage and source alpha do not survive. The mask emits a solid silhouette (`projected_shadow_mask.gdshader:1–20`). An opaque box and the same box with source alpha zero both produce the same 12 triangles in the fixture. This is collected-geometry evidence, not a headless image comparison.

Thin openings, foliage cards and transparent parts therefore need an explicit supported representation. Actual material use matters: the Timber source glass is made opaque by its runtime detail adapter (`aircraft/timber_visual_details.gd:65–74`), while other inspected canopy materials retain source BLEND intent. The [source material inventory](evidence/asset-materials.json) records these inputs. Do not infer the final imported render pass from GLB JSON alone.

There is a separate native participation risk: `aircraft/custom_skin.gd:223–228,423–433` accepts alpha below 1 and selects alpha blending; `aircraft/procedural_skin.gd:330–354,371–382` writes ALPHA for the corresponding shader variants. Ordinary blending has different native shadow support from alpha scissor/hash. Include an accepted alpha-0.5 custom body in the native material tests; no affected rendered aircraft was demonstrated here.

**Acceptance:** opaque, scissor/hash, blended and two-sided fixtures with native mask captures and an independent coverage reference. Preserve alpha textures/mips/deformation for admitted materials, or explicitly exclude them and provide a bounded alternative. Treat transmission through glass as a separate capability.

## SA-06 — Fixed low-sun aircraft and field cues disagree

**P2 · R/S/G · Integration inconsistency isolated here · VQ-04b-S05/S09.**

`main.gd:3584–3591` and `ui/home_scene.gd:250–254` send raw `sun_direction(snapshot)` to Sun-aligned aircraft cues; `field_projected_shadows.gd:239–250` uses `shadow_direction(snapshot)`, whose minimum elevation is 12° (`atmosphere.gd:557–568`). Flowing Sun-aligned aircraft cues also use the bounded helper. Vertical intentionally overrides the supplied direction with UP (`shadow.gd:241–243`); it is not part of this direction mismatch.

At a fixed 2° sun, actual production projection functions return **19.9878 m** offset per metre of height for the raw direction and **4.70463 m** for the bounded direction: a **4.24854×** difference. The first value already includes the projector's 0.05 denominator clamp; it is not the unconstrained physical 2° ray intersection.

**Acceptance:** choose a single declared Sun-aligned cue rule and apply it consistently in Home, Fly, field and fixed/flowing time, preserving the distinct Vertical aid. Capture the matched state before/after. The returned flight direction also reaches camera code; separate that contract before changing the helper. Leave the physical sunlight direction unchanged.

## SA-07 — Angular mask reuse lacks a geometric error bound

**P2 · R/S/G · Existing optimization with a new counterexample · VQ-04b-S04/S05/S10.**

`projected_shadow.gd:10–17,222–246` accepts 0.25° attitude/light changes and 2 mm blur changes irrespective of object size and grazing projection. In the fixture, a synthetic point 3 m along model +Z moves **49.2667 mm** in projection under a 0.2° X rotation at 12° sun. The basis threshold accepts it. A separate 6 m-long synthetic box exercises `refresh()` at minimum blur: 0.2° reuses the map; the 0.3° positive control redraws it.

The 18 mm minimum blur therefore does not bound all accepted geometric differences. This is not a demonstrated aircraft wingtip, pixel error, clipping, or visible jitter. Square framing may leave additional space; exceeding the nominal margin does not prove clipping.

**Acceptance:** measure maximum projected bound/coverage displacement relative to blur and output pixels across supported scales, light elevations and cameras. Retain an exact-refresh control and an A–A noise floor. Select an error-aware threshold only after comparing total mask cost and temporal quality.

## SA-08 — Projected has incomplete coverage across playable vehicles

**P1 · S/G · Known promotion gap, specific activity routes traced · VQ-04b-S01/S04/S12.**

Global Projected disables directional native maps. `helicopter_main.gd:122–135,172–183`, `vehicles/ground/ground_scene.gd`, `vehicles/multirotor/multirotor_scene.gd` and `vehicles/airship/airship_scene.gd` build their worlds/vehicles without the moving-aircraft projector used by fixed-wing `main.gd`. Field projections may remain. Home can display a projected preview for the same vehicle.

Consequently the selected route cannot supply the same moving-vehicle shadow coverage in every activity. This is a source coverage finding; no helicopter/truck/drone/blimp flight was rendered in this audit. The existing plan already leaves cross-activity qualification open.

**Acceptance:** run each playable activity on a lit flat field in Auto/Native/Projected/Off, including restart and vehicle switch. Provide an admitted moving cue or a truthful activity-specific fallback/limitation. Do not silently make a globally saved setting promise unavailable vehicle coverage.

## SA-09 — Home and Fly disagree on Vertical at zero celestial light

**P2 · S/G · Integration inconsistency isolated here · VQ-04b-S02/S05.**

`ui/home_scene.gd:250–254` gates every cue's visibility/strength by celestial shadow strength. `main.gd:3584–3589` instead gives Vertical strength 1, independent of that light. Thus a saved vertical height aid can be hidden in a moonless Home preview but active in flight.

This does not establish a displayed failure or require physically unrealistic nighttime sunlight. It requires a clear distinction between a pilot aid and natural-light visibility. Existing Main cue-control tests do not compare this Home case.

**Acceptance:** one declared Vertical policy in Home and Fly at full, reduced and zero celestial strength; exercise saved settings, V cycling, explicit launch overrides and Keep/Revert. Verify Sun still follows celestial illumination independently.

## SA-10 — Obsolete cloud seeds can consume all cache slots

**P2 · R/S/G · Bounded cache-admission defect/opportunity · VQ-04b-S09/S10, DT-MAC-06b.**

`cloud_shadow_map.gd:83–94` changes a live consumer's requested seed without retiring its previous tile. `_ensure_tile()` refuses a new seed after four entries (`:305–317`); pruning removes tiles only when consumers disappear or both modes disable (`:193–228,276–293`).

The fixture synchronously requests seeds 101…105 on one material. Four **pending** obsolete tiles remain, only 105 is required, and 105 reports `capacity`; retry still reports capacity. Last-consumer removal releases the cache. This is not an unbounded leak, a failed visual bake, or a measured FPS regression. Retention of ready/failed obsolete seeds follows from source, but paced production transitions still need execution.

**Acceptance:** reclaim only unreferenced entries, safely cancel obsolete pending work, and retry admission. Cover ready/failed/pending tiles, shared ground/sky seeds, multiple layers, late completion tokens and continuous/paced changes. Retain the analytic fallback; compare numerical/image parity and actual GPU cost before attributing a benefit.

## SA-11 — Off/Native field setup still creates projectors

**P2 · S/G · Disabled-path construction opportunity · VQ-04b-S01/S10, DT-11a.**

`field.gd:352–355` attaches `FieldProjectedShadows` before `ShadowFieldPolicy`. The former collects geometry and creates projectors (`field_projected_shadows.gd:20–102`); policy later hides receivers and disables updates (`shadow_field_policy.gd:51–71,358–367`). The retained budget is up to 16 maps and 8,388,608 target pixels.

Construction and retained scene resources are source-confirmed. Actual GPU residency, first-frame work and peak memory cannot be inferred from object counts. Keeping resources for quick toggles is intentional and tested; initialization with a disabled feature still deserves a separate lifetime policy.

**Acceptance:** compare initially Off/Native against Auto, first enable and repeated toggles with construction counters, process memory and native GPU allocation. Preserve exact accepted caster order, source snapshots and activation images. Defer only the resources whose creation is avoidable without breaking those contracts.

## SA-12 — Scenery collection precedes already-known rejection

**P2 · S/G · Concrete avoidable-work path · VQ-04b-S06/S10, DT-11a.**

The cell loop calls `collect_cell_shape()` (`field_projected_shadows.gd:62–65`) before `add_caster()` checks `MAX_MAPS` (`:81–83`). Face traversal/copying/merging can continue after all 16 slots are taken. The pixel check also occurs after collection, but differing map sizes mean that arbitrary early termination at a pixel rejection would be wrong.

Existing budget checks prove no extra children/counters after rejection, not that upstream collection is avoided. This audit establishes order and reachability from source, not a measured saving in a representative field.

**Acceptance:** a fixture with more eligible cells than available map slots must count attempts/collections and preserve accepted meshes, ordering, fallback visibility and source isolation. Stop count-exhausted collection; design any pixel preflight conservatively. Profile construction separately from steady flight.

## SA-13 — Atlas diagnostic reports a project default

**P2 · R/S/G · Configuration-reporting defect · VQ-04b-S00/S02/S10.**

`debug/render_probe.gd:144` labels `ProjectSettings` as `directional_shadow_size`; `shadow_settings.gd:125–139` sends live changes directly to `RenderingServer` without changing that project setting. The isolated run selects 8192 while the diagnostic reports 4096.

Rendering is unavailable in that run, so it does **not** observe an 8192 GPU atlas. It proves the reported-configuration mismatch; the live setter/read-source mismatch is independently visible in source. This can misidentify comparison settings and contaminate performance conclusions.

**Acceptance:** distinguish requested policy, applied owner receipt, project default and actual per-light state. Check Low→Ultra→Off→Revert on a native renderer; bind captures and timing records to the same receipt. Do not label the configured size as measured resident bytes.

## SA-14 — “Active technique” is a global policy, not actual light activity

**P2 · R/S/G · Partly disclosed diagnostics gap · VQ-04b-S00/S02.**

`shadow_settings.gd:94–99` reports native eligibility and global range, while `_apply_light()` respects source enablement and per-light caps (`:219–240`). The fixture has `effective.native=true` with `shadow_enabled=false` after an explicit source veto. The ground activity keeps a 35 m cap (`vehicles/ground/ground_scene.gd:258–261`) independently of a configured 100/300/600 m selection.

Settings already warns that activities may use shorter ranges (`ui/settings_screen.gd:1045–1074`). Explicit engine-off precedence is intentional; do not defeat it to make a label true. The concern is describing a global policy as observed active coverage.

**Acceptance:** show configured technique/range separately from the active light, effective range, celestial-strength/source veto and fallback reason. Cover Home, retained worlds, course cap, renderer fallback and a technical engine-off launch.

## SA-15 — Shadow Off does not offer control of cloud occlusion

**P2 · S/G · Known settings gap · VQ-04b-S02/S09.**

The five saved controls (`shadow_settings.gd:6–25`; `ui/settings_screen.gd:391–410`) do not include cloud occlusion. Its spatial ground transmission is independently applied (`atmosphere.gd:655–677,900–932`; `ground.gdshader:313–324,394–397`). `OPENRC_CLOUD_SHADOW_MAP*` selects cached noise versus analytic computation; it does not disable the cloud shadow.

Current Off promises the two direct-shadow routes, not all possible darkness; AO is also separate. This is an incomplete product control/label contract, not proof that documented native/projected Off failed.

**Acceptance:** decide the scope of the group and provide an independent saved cloud-occlusion option if adopting the existing plan. Disabling it should preserve visible clouds while avoiding ground-only sampling/registration. Test aliases, zero strength, mixed sky/ground use and restored preferences without changing physical weather.

## SA-16 — Cloud shade has incomplete receiver coverage

**P2 · S/G · Known lighting-coherence risk · VQ-04b-S09.**

Atmosphere binds its spatial cloud-shadow parameters/cache to ground and near-grass (`atmosphere.gd:655–677,920–932`). The water adapter supplies sky/sun/haze inputs without the same spatial transmission (`render/lake/water_material.gd:61–88`). The common opaque aircraft material path likewise does not implement that shared world-space cloud mask.

This can make a moving shade region affect the runway differently from an aircraft or water next to it. It is a receiver-coverage inference, not a rendered claim that every surface is wrong. Global sky ambient changes cannot replace location-dependent direct-light occlusion.

**Acceptance:** move one fixed-seed cloud shade across aircraft, runway, near grass, water and a building with fixed camera/exposure/time. Define the affected direct-light term once, preserve ambient response and compare boundaries/transport. Avoid per-material duplicated expensive noise when shared data can be qualified.

## SA-17 — Landing and field lights explicitly omit shadows

**P2 · S/G · Known local-light gap · VQ-04b-S08.**

Selected field floods (`world/field_lights.gd:452–466`), aircraft landing lights (`world/aircraft_lights.gd:820–835`), helicopter lights (`rotor/heli_night_lights.gd:116–131`) and veranda lights (`landscape_upgrade/airfield_lighting.gd:607–619`) set shadow casting off. Direct local light therefore has no native occlusion from those sources; the visible severity remains scene-dependent.

Enabling every lamp, LED or omnidirectional light could increase rendering cost and requires a selection budget. Native directional-atlas presets do not define a local-light atlas budget.

**Acceptance:** begin with one useful landing/field spotlight, then test a stable ranked budget and hysteresis. Cover near blockers, offscreen casters, moving aircraft, shadow-only distance fade and sim-clock deformation. Keep emission/illumination unchanged and measure each complete viewport workload.

## SA-18 — Native field coverage remains deliberately incomplete

**P2 · S/G · Known admitted-caster limits · VQ-04b-S06.**

`shadow_field_policy.gd:111–161,177–245` promotes bounded, eligible opaque sources and complete in-range population batches; it rejects unsupported materials/mixed batches. Shelters have a separate two-mesh cap. `near_grass.gd:270` and the inspected treeline billboard path (`treeline.gd:176`) disable casting. These are not evidence that all vegetation lacks shadows.

Historical S01–S03 and S06 records explicitly describe incomplete Native coverage. Increasing atlas resolution cannot restore a caster that was never admitted. Adding detailed grass everywhere would be a different performance decision.

**Acceptance:** inventory admitted/rejected casters and reasons at each scene-detail tier. Qualify near foliage alpha, wind deformation, people and shelters separately; preserve coverage-preserving mips, colliders and population identity. Use distance/importance/LOD budgets with stable transitions, then test native and projected ownership.

## SA-19 — Propeller/rotor coverage has deliberate omissions

**P2 · S/G · Known animation compromise · VQ-04b-S04.**

`projected_shadow.gd:35–52` excludes the named propeller subtree. Fixed-wing blur retains some source casting behavior but hides blades at speed and uses a noncasting disc (`propeller_blur.gd:357–381,413–416,471–498`). Helicopter blur copies/disc disable casting (`rotor/heli_rotor_blur.gd:207–220,275–279,322–345`).

The omission avoids an obviously frozen projected blade. It does not establish that stopped native propellers cannot cast. A fully opaque shadow disc would also be an incorrect shortcut for rotating transparent coverage.

**Acceptance:** stopped, spool-up, transition, fast rotation and spool-down with fixed/moving cameras and several presentation rates. Investigate a time-averaged coverage proxy only if it improves an identified view at acceptable cost. Keep visual phase tied to the accepted clock.

## SA-20 — Wreck blobs need a declared ambient/contact-aid policy

**P3 · S/G · Intentional approximation requiring a design decision · VQ-04b-S05/S07/S09, CR.**

Fixed-wing wrecks use `0.22 * fade` and a y=0.012 world plane (`crash/wreck.gd:1176–1210`). Helicopter blobs use a contact plane but also fixed strength (`rotor/heli_wreck.gd:318–351`). Neither multiplies by celestial direct-shadow strength.

An ambient contact aid can legitimately survive zero direct sunlight; this is not automatically a nighttime shadow bug. The problem is unqualified composition with direct shadows and differing terrain policies. Existing tests cover pose/cache/policy visibility rather than the lighting intent.

**Acceptance:** define ambient grounding versus direct occlusion, then compare lit/moonless wrecks, elevated/sloped contact, fade, pause and Off/Native changes. Avoid duplicate darkness and keep contact-plane data read-only.

## SA-21 — Fixed and flowing time use different opacity contracts

**P3 · S/G · Explicit existing design decision · VQ-04b-S09.**

`time_of_day_lighting.gd:33–41` produces continuous snapshot strength. `atmosphere.gd:997–1005` applies that continuously to native opacity only in flow; snapshots keep full opacity whenever casting is enabled. Projected Sun-cue opacity follows celestial strength in both routes; Main gives the distinct Vertical aid strength 1.

The comment explicitly preserves calibrated snapshot behavior. A different numeric opacity is not by itself a perceptual discontinuity: light energy, ambient contribution and exposure also affect the image.

**Acceptance:** hold sun/moon state and exposure fixed and compare equivalent snapshot/flow scenes through dusk and lunar phases. Either justify the difference with a declared calibration contract or unify it with a clear-surface energy check. Do not tune darkness by silently changing sunlight energy.

## SA-22 — Disabled native routes still commit atlas settings

**P2 · S/G · Backend allocation question · VQ-04b-S01/S10.**

`shadow_settings.gd:52–99,125–139` resolves and commits atlas/filter settings even for Off/Projected; light casting is vetoed separately. A size commit might rebuild or retain resources depending on the backend. Source alone cannot establish allocation, residency, a leak, or a release opportunity.

**Acceptance:** native Off startup and Low↔Ultra transitions on Compatibility, Mobile and Forward+ with actual resource telemetry. Separate reserved depth storage from resident memory and render work. If deferring allocation is useful, preserve the saved intent and first-enable latency/quality; avoid repeated reallocation during preview callbacks.

## SA-23 — Disabled aircraft cues still collect a geometry snapshot

**P2 · S/G · Conditional CPU/memory opportunity, prior fix preserved · VQ-04b-S04/S10, DT-11a.**

`shadow.gd:130–164` collects/retains shape at binding even when the initial cue is disabled, then defers viewport/receiver creation. This is intentional: mutable Timber geometry and child transforms must retain the bind-time silhouette. The November 9 eager-GPU-startup issue was already fixed and must not be reopened as still present.

The stock Corsair LOD proxy is narrowly admitted by asset, livery, engine, renderer and session context (`aircraft_shadow_proxy.gd:15–88`). Its result cannot be generalized to the whole fleet or renamed a general self-shadow solution.

**Acceptance:** attribute collection cost before changing the contract. Compare immutable shared geometry, small articulated parts or import-time data with exact source ownership and fallback. Preserve initial Off→on images and invalid-source cleanup. Report startup CPU savings separately from whole-flight FPS.

## SA-24 — Quality labels span different work and capability

**P2 · S/G · Clarity/qualification gap · VQ-04b-S02/S03.**

Quality controls native atlas/depth/cascades/filter (`shadow_settings.gd:19–25`), not the fixed 256² aircraft mask or 256²–1024² field targets. High graphics can retain a 0.53° PCSS request even with Low shadow quality and Auto/Soft. The resolver reports PCF for Standard and PCSS for active High (`:80–91`), but the Settings receipt does not display its explanation (`ui/settings_screen.gd:1045–1074`). Actual backend execution remains a native gate.

Thus Low is not a measured whole-shadow cost guarantee, and Soft does not mean the same algorithm on all backends. The UI does correctly mark native-only controls inactive when only projection is selected.

**Acceptance:** show configured/effective technique, native versus cue scope, and backend filter. Qualify named presets from paired flights and scene-detail combinations. Keep Current as the reference until a cheaper acceptable configuration actually passes; do not promote a larger atlas from its label.

## SA-25 — Existing diagnostics cannot be read as total shadow cost

**P1 · S/G · Measurement-boundary gap · VQ-04b-S00/S10.**

`debug/render_probe.gd:69–119` separates root GPU time and subviewports, marking the latter's freshness unverified. `@shadows` toggles light shadow flags, while `@subviewports` is separate (`:312–339`). The retained Compatibility audit records zero shadow-pass counters despite a shadowed fixture. Optional planar reflection captures and sky/reflection refresh add separate work.

Subtracting the root readings from two uncontrolled modes cannot attribute all native maps, aircraft/field masks, cloud bakes and reflected views. Nor can component savings simply be added. These are measurement limitations, not evidence that current accounting code falsely claims a complete total.

**Acceptance:** synchronized pass/frame attribution, fresh timestamp validity and complete view inventory, with cold bakes separated from steady state. Retain CPU wall time, GPU timing, frame tails, draw/primitives, map updates and memory. Use vendor captures for attribution separately from ordinary flight timing.

## SA-26 — Broad shadow quality is not qualified by the retained checks

**P1 · S/G · Acceptance gap · VQ-04b-S00/S11/S12.**

Current tests are valuable for ownership, cache, collection, persistence and lifecycle. They do not establish convincing moving self-shadows across the fleet, renderer/device combinations, all scales/cameras, multiple activities and export packages. Historical 1080p RTX 3090 stills are scoped fixtures on earlier source/engine; Ryzen CPU results are not Radeon GPU evidence. This audit's 156 assertions are headless module checks.

**Acceptance:** complete the [native scenario matrix](validation.md#native-scenario-matrix) with source/engine/asset/setting identity, repeated baseline captures and normal-speed motion. Prioritize actual 1920×1080, then larger outputs, then 720p fallback. Close each affected finding with a reproduction, scoped correction, counterexample controls and target-hardware result. Preserve unrun and rejected cases explicitly; a green aggregate must not hide them.
