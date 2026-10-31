# Detailed shadows and grounding plan

2026-10-31 · Owner: VQ with UI, FW/TOD/SUN, L/LU/SC, CAM, GDU and vehicle visual owners · Steps: **VQ-04b-S00…S12**.

**Status: first configuration/settings slice implemented; broader visual and performance qualification remains open.**
The [implementation record](../research/visual-quality-implementation/VQ-04b/S01-S03-2026-10-31/README.md)
owns checks, captures and limits. Current defaults are preserved; Native is an opt-in, bounded comparison.
Deliver convincing contact, detailed silhouettes and stable motion before increasing range or adding expensive effects.
Primary acceptance is **1920×1080**, then 1440p/4K and above, then 720p compatibility.

This is the detailed shadow subplan of [VQ-04b](../VISUAL-QUALITY-PLAN.md#open-work). The [advanced graphics plan](advanced-graphics.md) retains VQ-07e renderer/effect promotion, VQ-06a/b retains settings integration, and [GDU-11](godot-4.8-upgrade.md#phase-11-owner-authorized-48-improvements) retains engine opportunity work. The [dated source audit](../research/shadows-2026-10-31.md) records the inspected implementation and internet references. Parent acceptance gates remain in their existing homes; this document owns the shadow-specific sequence.

[Section 13](#13-targeted-c-efficiency-work) incorporates six additional internet investigations into C++ efficiency. It selects a small optional geometry-preparation helper for consideration after current profiling, while reusing Godot's existing native rendering/import operations.

## 1. The visual result

During a landing, wheels should visibly meet the runway, the wing should shade the fuselage, and the aircraft's shadow should separate and soften as it climbs. A low afternoon sun should reveal fence gaps, bench legs, landing gear and foliage without crawling edges or sudden cascade transitions. Pavilion shade should retain readable color and detail. Night lamps should place useful shadows behind nearby obstacles; moon shadows should follow the existing moon illumination rather than resemble daylight with a blue tint.

Detail has three useful scales: small contact and self-shadow detail around the aircraft; stable mid-distance shadows around the flying field; and broad, coherent terrain/cloud shading. A distant aircraft must remain easy to locate and orient. More dark pixels are not an acceptance criterion.

The first visible release should offer a dedicated **Shadows** settings group, a reliable Standard fallback, improved landing contact, and a measured native-shadow option. Later slices add foliage, local lights and atmospheric coherence. Each slice remains independently reviewable.

## 2. What exists and what needs work

The audit examined HEAD `70709ff4b600fbce361b0bea9f88726c60bcff86` plus the working files on 2026-10-31. The engine pin is official **Godot 4.8-beta1**, `4d10419ca`. Unrelated overlay/CI edits were present. This is source inspection, not a new rendered baseline.

| Existing implementation | Implication for this plan |
| --- | --- |
| Standard uses Compatibility. Interactive engine shadows are enabled by default; the sun starts with two splits and a 300 m maximum distance. | Standard is already capable of native shadow maps. Compare their color, contact and cost with projection instead of describing native shadows as absent. |
| High already selects an 8192² directional atlas, four blended cascades, splits 0.06/0.20/0.50, medium soft filtering and 0.53° directional PCSS. | Increasing atlas size is not the starting solution. Tune allocation and attribution; a smaller qualified atlas could retain useful detail. |
| Aircraft projection uses a 256² isolated mask, a flat receiver and a fixed 13-tap blur. Geometry is collected at binding; propellers are excluded. | The silhouette is model-specific, but does not automatically follow later hinge deformation or implement general surface/self shadowing. |
| Field projection is limited to 16 maps / 8,388,608 target pixels; map sizes are 256²–1024². The windsock has a dedicated moving 512² caster. | Preserve bounded allocation and caching. Reuse windsock deformation/lifecycle lessons for other animated casters. |
| The projected height cue uses bounded low-sun direction, height-dependent blur and artistic opacity. | Preserve its training value while clearly separating an optional aid from natural-light shadows. |
| High has SSAO and startup multi-bounce occlusion. Contact shadows are explicitly experimental and off by default after failed visual adoption. | AO and contact rays need separate switches and tests. Do not ship the rejected contact configuration as a new quality preset. |
| Near grass and the inspected treeline billboard path disable casting; field and aircraft landing lights disable native shadows in their inspected creation paths. | Audit other vegetation and lighting paths individually. Select useful new casters/lights by visible benefit and measured cost. |
| Graphics settings already include renderer restart, Scene detail, MSAA/reconstruction and aircraft-lighting quality, but no dedicated shadow configuration. | Extend the existing preferences, validation, Apply/Revert and restart flow. Avoid a separate settings store. |

Current sources and historical evidence are linked in the [audit](../research/shadows-2026-10-31.md#repository-audit). No visible defect is considered reproduced solely because a source path permits it.

## 3. Ownership and architecture

| Boundary | Owning paths / collaboration |
| --- | --- |
| Shadow policy, projected masks and renderer adaptation | VQ: `app/render/shadow.gd`, `projected_shadow*`, `field_projected_shadows.gd`, `windsock_projected_shadow.gd`, `high_graphics_profile.gd`; shared atmosphere hooks with FW |
| Saved controls and presentation | VQ-06a/b + UI: `app/app_state/display_preferences.gd`, `app/ui/settings_screen.gd`, `app/i18n/`; preserve camera, audio, controller and lighting preferences |
| Sun, moon, clouds and local lights | FW/TOD/SUN and FW-RGB: `app/render/atmosphere.gd`, `app/render/world/`, relevant existing environment configuration; retain their intensity/time contracts |
| Trees, grass, buildings and people | L/LU/SC: existing generators, imported materials, batching and caster bounds; no collider or placement changes hidden inside visual tuning |
| Aircraft, rotors, hinges and wrecks | Vehicle/AS/CR owners: stable `airplane`, `propeller` and `*_hinge` bindings; authoring-source changes only when necessary |
| Verification | Existing `app/tests/test_*shadow*.gd`, profile/settings tests, `tools/shadows/`, `tools/graphics/`, debug bridge and performance collectors |

Introduce one small resolved shadow configuration at the presentation boundary if the audit confirms it is needed. Its input is saved user intent plus actual renderer capabilities; its output is an immutable effective configuration and explicit reasons for fallback. Extend existing owners instead of adding another world controller.

The resolved configuration should describe technique, sun atlas/filter/cascades/range, projected-map budgets, caster groups, local-light budget, contact status and AO status. Each world consumes the same result in Home, Workshop, fixed-wing, helicopter and ground activity. Diagnostics record requested and effective values independently.

The [second research round](../research/shadows-2026-10-31.md#second-round-18-internet-investigations) refines this boundary: directional atlas size/depth and both native shadow-filter qualities are global, while positional atlas allocation is per viewport. One presentation owner must commit global changes; a preview or retained world must not overwrite flight's configuration. Keep requested preferences separate from this global effective state, and measure map reconstruction on Apply.

Preserve these contracts:

- Shadows observe interpolated presentation transforms and existing visual time. They never write forces, collision, simulation state, physical weather or flight-log identity. Do not change the 240 Hz kernel or re-record golden flights.
- A caster/receiver/light combination has one direct-shadow owner. Audit simultaneous engine and projected coverage before changing anything. If a hybrid is needed, require a proven receiver mask or coverage partition; otherwise select one route.
- Engine self-shadowing and ground projection cannot be combined by merely enabling both. Demonstrate how aircraft-to-ground duplication is prevented while retaining aircraft-to-aircraft self-occlusion; reject the hybrid if the engine's supported masks cannot express the partition safely.
- `light_cull_mask` selects recipients of the whole light; `shadow_caster_mask` selects casters. Neither is an arbitrary caster-to-receiver shadow matrix. Turning off shadow reception on the runway also removes other useful shadows. A split-light workaround is research only: it can lose aircraft-to-building shadows, change lighting and reduce each light's share of the directional atlas.
- Keep atmosphere exposure and sunlight energy fixed during shadow comparisons. Preserve Standard's existing compensation until a separate color oracle justifies changing it; never transfer that compensation to High.
- Heavy map/geometry changes apply at a declared safe boundary. Light scalar updates may apply live when tested. Do not allocate a new map on every slider event or collect triangles every frame.
- Cache invalidation includes mesh/material/alpha revision, pose, sun/moon direction, receiver changes and world lifecycle. Pause, reset, source destruction and retained-world reattachment must not leave stale masks.

## 4. Coverage: every relevant shadow family

| Shadow family | Proposed improvement | Evidence needed |
| --- | --- | --- |
| Aircraft ground silhouette | Compare current projection with native maps; optionally increase projected resolution by screen footprint and include animated control surfaces. | Landing/taxi, bank/roll, climb and low sun; attached gear, no doubled silhouette or stale hinge pose. |
| Aircraft self-shadow | Native sun/moon maps on wing roots, tail, fuselage, landing gear, struts and open structural gaps. | Inspection and pilot views across aircraft scales; no acne, detached contact or lost canopy/paint detail. |
| Moving controls and mechanisms | Reuse visible hinge transforms and material coverage in a bounded shadow proxy or native pass. | Full control deflection, folding/retracting parts only where installed; no binding/name changes. |
| Propellers and helicopter rotors | Preserve stopped-blade shape where useful; compare a time-averaged coverage proxy at speed, including blur transitions. | Idle/start/stop/spool-down at multiple frame rates; no frozen blade stripe, flicker or solid opaque disc. This is optional, not a new rotor simulation. |
| Wheels, skids and object contact | Tune map allocation/bias first; evaluate short-range AO separately; revisit contact rays only with a cleaner candidate. | Zero-height contact versus lift-off, grass/runway boundary, pavilion floor and thin struts. |
| Buildings, fences and furniture | Preserve slats, legs, roof overhangs and gaps; add useful interior shade without crushing ambient illumination. | Low-angle sun, grazing views and moving cameras; reject light leaks and disappearing thin parts. |
| Trees and shrubs | Match leaf alpha coverage, wind deformation and shadow LOD; retain trunks/branches beyond expensive leaf detail. | Native motion at LOD transitions, strong qualified wind, backlighting and aircraft against treeline. |
| Grass | Optional bounded near-camera/landing-zone clump casting; keep distant grass cheap. | Grounded appearance versus increased noise/overdraw. Individual blade shadows are not mandatory at subpixel scale. |
| People, vehicles and moving scenery | Audit current animation support; follow current poses for visible near-field actors and use stable reduced casters farther away. | Actor motion, pauses, visibility and scene switches; no stale neutral silhouette or unrelated animation overhaul. |
| Sloped ground and obstacles | Prefer native depth shadows for non-planar receivers. Projection fallback must restrict itself to valid receivers or visibly fade. | Banks, ramps, shoreline and objects above the ground; no floating plane, hillside penetration or shadow through a roof. |
| Clouds | Keep broad cloud occlusion aligned with existing sky layers, wind/time and sunlight direction; apply spatial occlusion to direct light consistently where feasible. | Sun overhead/low, moving cloud deck, aircraft crossing shade, runway and lake coherence; no second independent cloud clock. |
| Moon and twilight | Use the resolved celestial direction and direct-light share; control long-shadow fade and sun/moon handover. | Moonlit/moonless cases, horizon crossing and time acceleration; no duplicate full-strength sun/moon shadow. |
| Field lamps and landing lights | Enable a small selected set of native spot/omni shadows; prefer useful spotlight coverage for runway/pavilion/landing cues. | Moving aircraft/lights, overlapping pools, obstacle occlusion and budget transitions; no allocation popping. |
| Smoke, transparent canopy and water | Establish supported opacity/transmission behavior per material. Preserve transparent rendering and avoid solid silhouette artifacts. | Smoke against shade, canopy tint, lake receiver/reflection and offscreen geometry. Colored transmission/volumetric shadowing remain conditional research. |
| Crash fragments and wrecks | Follow existing geometry/visibility ownership; retire shadow resources with their source. | Reset, fragment disappearance, source-first destruction and retained-world reattachment. |

## 5. Techniques and decisions

### 5.1 Cascaded shadow maps: spend detail where it is visible

Use Godot's existing directional shadow system. The pinned engine already stabilizes cascade bounds; inspect that behavior before considering custom stabilization. [Pinned engine source](https://github.com/godotengine/godot/blob/4d10419ca/servers/rendering/renderer_scene_cull.cpp#L2099-L2143).

Start with the current two-split Standard and four-split High configurations. Sweep maximum distances **100 / 200 / 300 / 500 m**, atlas sizes **2048 / 4096 / 8192**, and supported two/four-split modes independently. These are experiment candidates, not released settings or guaranteed useful combinations. Keep 300 m/8192/four-split High as an explicit baseline.

Camera FOV and pilot autozoom strongly affect texel allocation. Compare fixed pilot, autozoom, chase, orbit, overhead and Workshop views. Do not move the physics camera or force a zoom change to conceal a shadow defect. Prefer per-view-class qualified allocation over continuous retuning that causes resolution pumping. Split blending and distant fade must be tested in motion. Godot's [shadow guide](https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html) motivates distance/split tuning; engine-pin behavior still needs native verification.

At the pin, orthographic cameras bypass the maximum-shadow-distance clamp; apply that caveat only after identifying an actual orthographic view. FOV, source angle and light orientation can change cascade footprints despite grid snapping. Separate these motions in the first experiment. Native PSSM split diagnostics are available in Forward+/Mobile, but their debug material suppresses custom vertex deformation: pair diagnostics with normal rendering, particularly for foliage. [Investigations I06–I07](../research/shadows-2026-10-31.md#i06--global-settings-viewport-settings-and-live-apply).

Tune depth bias and normal bias against thin RC geometry and low sun. Use per-category evidence if needed, not a giant global bias that makes wheels float. Diagnose clipped/large casters and pancake settings separately. Keep precision settings fixed until a measured defect warrants a comparison.

### 5.2 Filtering, penumbrae and contact

PCF filters sampled visibility; PCSS estimates widening softness with blocker/receiver separation. High already has directional PCSS. Compare hard/PCF and PCSS at fixed atlas/cascade allocation to learn whether missing detail comes from resolution, filter width or bias. Natural softness starts from the current **0.53°** sun size; an optional bounded artistic multiplier must not alter the rendered sun disc accidentally. Directional PCSS is Forward+ only at this pin. [Light3D source](https://github.com/godotengine/godot/blob/4d10419ca/doc/classes/Light3D.xml).

Record source angle, quality enum and effective filter path together. A “Hard” quality enum alone does not turn off High PCSS when source size remains nonzero. Conversely, changing the angle to zero changes both the filtering path and cascade expansion; label that comparison as coupled. Standard groups quality enums into fewer shader sampling branches, so six UI labels need not represent six useful quality tiers. Test thin-blocker coverage, softness and temporal noise independently. [Investigations I01 and I08](../research/shadows-2026-10-31.md#i01--which-quality-options-have-distinct-native-behavior).

Preserve a crisp near-contact region and widening penumbra with height. Do not blur every shadow equally. The projected path's present blur clamp is an artistic flight cue; a more physical profile should remain distinguishable from that cue and be checked at low sun and high altitude.

Screen-space contact rays can recover small visible gaps but cannot replace offscreen-caster shadows. The [GDU-11g failed visual gate](../research/engine-upgrade/GDU-11/implementation.md#gdu-11g--high-contact-shadow-experiment) is binding evidence: wall bands persisted across AA controls, so enabling TAA is not an established repair. Keep contact default-off; retry after a demonstrated engine fix or cleaner isolated technique. Preserve offscreen ordinary-shadow contribution and test viewport edges/disocclusion.

### 5.3 Ambient occlusion and material grounding

AO is ambient occlusion, not another sun shadow. Conceptually separate emitted light, ambient illumination attenuated by AO, and each direct light attenuated by its visibility. This is a review model, not a proposal to replace Godot's lighting equations.

Use small-scale material AO for seams/recesses only when appropriate source assets already contain it. Avoid baking a fixed sun into albedo or applying AO twice. High already uses SSAO with zero direct-light influence and multi-bounce occlusion. The engine pin also supports a simplified Compatibility SSAO path; test it as a separate Standard experiment, not an assumed installed feature. [Pinned Environment API](https://github.com/godotengine/godot/blob/4d10419ca/doc/classes/Environment.xml).

Do not bundle SSAO, contact rays, exposure and stronger shadow opacity into one unreviewable “realism” change. Reject halos around wings, smeared small aircraft, crushed underwing markings and new wall banding.

### 5.4 Vegetation and animated coverage

Reuse existing foliage assets and wind functions. Verify visible-pass versus shadow-pass alpha cutout, UVs, material double-sidedness, deformation and conservative bounds. Use authored or source-generated reduced shadow meshes only when they preserve visible openings; do not substitute opaque leaf-card rectangles.

Godot's alpha-scissor/hash paths support casting, whereas ordinary alpha blend does not. Test alpha-test coverage preservation through the actual imported texture/mipmap path. The pinned Compatibility renderer does **not** implement alpha-to-coverage in its GLES3 branch, despite the general material tutorial's MSAA advice; no Standard quality promise may rely on that feature. [Pinned material API](https://github.com/godotengine/godot/blob/4d10419ca/doc/classes/BaseMaterial3D.xml), [GLES3 implementation](https://github.com/godotengine/godot/blob/4d10419ca/drivers/gles3/rasterizer_scene_gles3.cpp#L3178-L3184).

A shadow LOD must be coordinated with the visible tree LOD and object scale. Preserve meaningful trunk/canopy coverage beyond leaf detail range. Use hysteresis and test fades to prevent popping; do not assume a visual mesh's distance fade also gives correct shadow behavior.

Match the texture import's alpha-test threshold to the intended material test before assessing mip coverage; these values are independent. Check whether camera-dependent wind/billboard code uses the current rendering-pass view or the main camera. Native shadow passes use a different view. `SHADOWS_ONLY` permits a separate native caster proxy, but that proxy cannot supply missing screen-space contact depth. [Investigations I05 and I10](../research/shadows-2026-10-31.md#i05--animated-casters-invisible-proxies-and-custom-clocks).

Inspect existing imported shadow meshes before generating another asset. Godot already vendors meshoptimizer and normally requests optimized shadow meshes at import. `ArrayMesh.shadow_mesh` requires identical positions, including LODs; it is not the attachment point for a silhouette-simplified proxy. The native importer skips that optimization for blend shapes and bone/weight data. Genuine reduced geometry needs a separate qualified caster path and source ownership. [Investigation I18](../research/shadows-2026-10-31.md#i18--meshoptimizer-and-godots-existing-import-pipeline).

### 5.5 Local lights, clouds and long-range shadows

Rank eligible local shadow lights by visible contribution, distance and gameplay relevance. Start with one landing or field spotlight, then test a budget of two and four. Keep a stable selection with hysteresis; map allocation changes cannot flicker during approach. Emissive LEDs are not automatically shadow-casting lights. Omni and spot atlas allocation is separate from the directional atlas; multiple omnidirectional shadows can be expensive. [Godot light/shadow reference](https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html).

Test shadow-only distance fade before fading the useful light itself. Measure slot transitions and cache invalidation with the camera fixed and moving. In particular, the pin's material-animation detection recognizes certain built-in `TIME` paths; that does not establish correct local-shadow refresh for OpenRC's `sim_clock` uniforms. Test stopped/advancing wind under a fixed local light and use a forced-refresh diagnostic control if needed. Preserve the project's deterministic clock rule; changing shaders to `TIME` is not the remedy. [Investigations I03 and I05](../research/shadows-2026-10-31.md#i03--local-light-atlases-fade-and-cache-behavior).

Reuse world-space cloud transport and existing sky settings. Audit every relevant receiver before claiming a universal cloud-shadow solution: ground darkening alone does not establish aircraft/material/light coherence. Do not change physical wind to align a visual texture. Baked fixed-sun lightmaps are unsuitable as the sole solution for flowing outdoor time; consider static local-light baking only for a separate justified, invariant case.

Native directional maps handle ordinary terrain receivers. Extremely long landscape shadows, cloud self-shadowing, smoke transmission, area-light colored shadows and ray tracing need separate feasibility evidence; none is required for the first release. Virtual shadow maps, SDF shadowing or a custom renderer are not drop-in Godot settings.

## 6. More useful settings

Add a collapsible **Shadows** group within Graphics; place AO in a neighboring **Ambient shading** group and retain current sky/night ownership. Show concise visual explanations and an estimated cost category, not unmeasured FPS promises. The renderer profile **High** and shadow quality **High** must be visibly distinct.

| Player control | Proposed choices | Behavior / dependency |
| --- | --- | --- |
| Shadow quality | Off / Low / Medium / High / Custom; Ultra only after qualification | Presets resolve to validated combinations; individual edits select Custom. Off disables cast-shadow paths including projected cues, but does not make surfaces unlit or disable separate material AO. |
| Shadow technique | Automatic / Projected / Native, where qualified | Automatic resolves from actual renderer and qualified profile. Hybrid remains a developer experiment until ownership is proven. |
| Aircraft shadows | On / Off | Governs aircraft cast shadows; explain if a selected technique cannot provide separate self/ground controls. |
| Aircraft height cue | Natural / Assisted / Off | Natural follows the selected light path; Assisted explicitly enables the bounded training cue. Prevent duplication. Master Off takes precedence. |
| Field and scenery shadows | Off / Nearby / Full qualified range | Includes structures/actors; no change to collisions or scenery placement. |
| Vegetation shadows | Off / Trees / Trees + near grass | Only expose a level after its caster/LOD path passes; distant grass remains budgeted. |
| Shadow distance | Near / Balanced / Far; meters in Advanced | Resolve to measured camera/profile ranges, initially testing 100/200/300/500 m. Show fade behavior. |
| Shadow detail | Low / Medium / High | Advanced view may show atlas/mask resolution. Never imply atlas resolution equals the full per-cascade texture size. |
| Edge softness | Sharp / Filtered / Natural soft | Natural soft maps to PCSS in qualified High; Standard uses a labeled supported fallback, not a false PCSS option. |
| Contact detail | Off / On, initially marked Experimental in High | Remains default-off until GDU/VQ visual gates pass. Disabled with an explanation where unsupported. |
| Local-light shadows | Off / Low / Medium / High | Initially evaluate 0/1/2/4 selected lights; does not change lamp/LED emission itself. |
| Cloud shadows | Off / On, linked to Sky settings | One saved owner. Disables spatial cloud occlusion, not the whole weather/sky preset. |
| Ambient shading | Off / Low / Medium / High | Separate AO control; renderer-specific capability and quality mapping. Preserve High multi-bounce behavior unless independently changed. |
| Shadow strength | Natural; optional restrained artistic adjustment | Natural uses resolved lighting. Artistic adjustment must not become a substitute for exposure, double-shadow or color fixes. |
| Restore shadow defaults | Action | Resets this group only, preserving camera, input, reconstruction and unrelated lighting choices. |

Advanced developer controls may expose cascade count/splits, fade start, bias/normal bias, filter quality, local atlas subdivision, caster/receiver masks and update counters. These belong in diagnostics until a player need is established. A “show cascades/casters/receiver ownership” overlay is more useful for debugging than exposing every engine property to players.

Settings integration requirements:

1. Extend the existing versioned preference mechanism with validated optional keys or an explicit migration. Old files keep accepted behavior; reject nonfinite/out-of-range values and preserve unsupported stored intent without falsely reporting it active.
2. Use one resolver for UI, CLI, Home, flight and tools. Define precedence explicitly: supported explicit launch overrides, saved interactive settings, then defaults; retain existing direct-flight isolation from Home preferences.
3. Reuse Apply/Revert and the existing display safety flow where a change affects that flow. Label “applies now”, “next flight” and “restart required” truthfully. Atlas/caster rebuilds need a deliberate commit point, not continuous slider callbacks.
4. Renderer fallback shows the effective technique and a short reason. A saved High-only option cannot silently activate on Compatibility or repeatedly trigger restarts.
5. Repeated Apply, revert, defaults, malformed files and renderer restart are idempotent. Surviving worlds must receive the effective configuration once after reattachment.
6. Keep keyboard/controller focus, EN/ES labels, tooltips and large-text layout usable at actual 1080p; test higher resolutions next and 720p overflow last.

## 7. Candidate quality tiers and budgets

These are **starting experiments**, not product defaults or hardware support claims. Standard and High renderer profiles retain their current behavior until a selected tier passes.

| Candidate | Directional / projected allocation to compare | Detail and scope |
| --- | --- | --- |
| Off | No cast-shadow maps or projected receivers | Preserve ordinary lighting; separate AO remains independently configured. |
| Low | 2048 native/two splits where useful, or current bounded projection | Aircraft/essential near structures; local-light shadows off; no new grass casting. |
| Medium | 4096 native/two or four splits; 256²–512² aircraft projection alternative | Balanced field range, trees with reduced distant casters; optional one local spotlight. |
| High | Compare 4096 and current 8192/four splits; current 0.53° PCSS as control | Detailed aircraft/near foliage, optional two local lights, independently qualified AO; contact still off. |
| Ultra / capture | Current 8192 baseline plus only demonstrably useful detail/range | Optional four local lights and near-grass detail; label unqualified capture experiments honestly. No automatic 16K atlas. |

Sun-atlas depth storage alone, before driver allocation and other buffers:

| Square atlas | Nominal 16-bit depth | Nominal 32-bit depth |
| --- | --- | --- |
| 2048 | 8 MiB | 16 MiB |
| 4096 | 32 MiB | 64 MiB |
| 8192 | 128 MiB | 256 MiB |

These are arithmetic estimates, not VRAM measurements. Four cascades share the atlas. Projected-map color/depth, MSAA, local-light atlases, AO/contact buffers and reflection views add separate costs. The current field-pixel cap must not be silently raised; measure total peak memory and teardown retention before changing it.

For a proposed 60 Hz tier, use the existing whole-frame gate, with **16.67 ms** as the frame interval. Before implementation, record an incremental shadow allowance on a named target GPU. A useful initial screening hypothesis is **at most 2 ms additional GPU p95** versus the selected baseline, while still meeting the whole-frame budget; a faster baseline does not make 2 ms automatically acceptable. This is a proposed experiment threshold, not a replacement for VQ/DT pacing gates. Higher refresh profiles need their own budgets.

Record wall/CPU/GPU p50/p95/p99, worst-frame bursts, shadow draw calls/primitives, update counts and peak/residual memory. Report full main plus offscreen shadow/reflection cost. Never add isolated component speedups together or infer GPU performance from llvmpipe/headless timings.

## 8. Reuse free tools and existing work

| Resource | Intended use | Adoption decision |
| --- | --- | --- |
| Godot native shadows, SSAO and OpenRC's existing projected-mask code | Directional/local maps, PCSS, ambient grounding and bounded fallback | First choice, subject to renderer capabilities. OpenRC's silhouette projection is separate from Godot light projector textures, which are unavailable in Compatibility at this pin. |
| [RenderDoc](https://github.com/baldurk/renderdoc) | Inspect actual passes, atlas occupancy, caster draws and duplicate work | Free MIT tool; use on supported graphics APIs. It is not the normal benchmark run and does not cover Metal. |
| [NVIDIA FLIP](https://github.com/NVlabs/flip) and existing capture comparators | Perceptual A/B image differences and regression localization | Reuse existing tooling; BSD-3-Clause project. Difference magnitude does not score realism or motion stability. |
| [Intel XeGTAO](https://github.com/GameTechDev/XeGTAO) | Read its AO sampling/denoising design if stock AO has an attributed shortcoming | MIT, discontinued by Intel; a port requires HLSL/API adaptation and a maintenance owner. Defer until stock paths fail a defined gate. |
| [AMD FidelityFX CACAO](https://gpuopen.com/manuals/fidelityfx_sdk/techniques/combined-adaptive-compute-ambient-occlusion/) | Compare its AO design with stock SSAO only after an attributed gap | MIT code; SDK 1 maintenance/version scope and RD integration need review. Defer a port; it does not replace direct shadows. |
| Godot's vendored meshoptimizer and native shadow-mesh importer | Reduce redundant static shadow vertices using existing import paths | Inspect the actual imported resource first. Preserve positions/LODs and alpha/deformation semantics; no extra library needed initially. |
| Nsight Graphics / Radeon GPU Profiler / Xcode Metal tools | Attribute native GPU work on the corresponding supported device/API | Use the [I14 tool matrix](../research/shadows-2026-10-31.md#i14--choosing-a-profiler-for-the-actual-gpu-and-api); vendor capture/counters are separate from normal-flight timing. |
| Official Godot light demo / GodotFarShadow experiment | Isolated reference comparisons and distant-shadow feasibility | The [I17 source review](../research/shadows-2026-10-31.md#i17--free-godot-examples-and-distant-shadow-add-ons) favors the pinned official example; the C#/two-world far-shadow experiment remains deferred. |
| Existing asset-source catalog, licensed field/aircraft materials and generators | Suitable AO maps, foliage alpha textures or reusable caster meshes | Search available free assets first; record redistribution rights and provenance. No new asset pack is needed for the initial slices. |
| Existing shadow, tree, graphics, capture, debug and frame-diagnosis tools | Oracles, scripted views, lifecycle interaction and timing | Extend the smallest missing capability; do not write a replacement harness. |

Technique inspiration and exact source applicability are retained in the [research ledger](../research/shadows-2026-10-31.md#external-sources-and-applicability). These are reuse candidates; the planning task installs no dependencies. When a dependency is selected for implementation, pin its exact version/commit and retain its license.

The [18-investigation follow-up](../research/shadows-2026-10-31.md#decisions-from-the-second-round) adds concrete decisions under the existing stages: prioritize mask ownership, global-setting scope and native diagnostics; then motion/bias/filter experiments; then imported coverage and animated/local-light refresh. External AO, variance/moment maps, virtual shadow maps and ray tracing remain conditional renderer projects. A free download is useful only when its integration and maintenance fit this application.

## 9. Implementation sequence

S01/S02 and candidate S03 controls are implemented in the first slice. This does not complete the full
coverage or promotion gates below. Slice evidence lives beneath the existing VQ evidence home, with
large captures in ignored/external directories and compact reports linking identities and reproduction instructions.

| ID | Work | Proof / status |
| --- | --- | --- |
| VQ-04b-S00 | Inventory actual caster/receiver/light paths, renderers, cameras, existing settings and concurrent shadow contributions. Freeze present Standard and High baselines. | Source audit and native 1080p static baselines recorded. Motion and broader activity baseline pending. |
| VQ-04b-S01 | Define effective shadow configuration, capability reporting and direct-shadow ownership. Compare projected/native routes without unrelated visual changes. | Implemented global allocation owner, route suppression/restoration and bounded opaque Native casters. Current/Auto intentionally retains legacy combined coverage. Complete Native coverage and promotion remain open. |
| VQ-04b-S02 | Integrate a small first settings slice: quality/technique, aircraft cue, distance and restore defaults; advanced groups expand with accepted features. | Implemented additive persistence, malformed-value recovery, live preview/Revert, five controls and eight translations; focused UI checks and native menu inspection recorded. Wider package/restart qualification remains open. |
| VQ-04b-S03 | Tune directional distance, atlas, cascade allocation, blending and bias at fixed filter/AA. | Candidate 2048/4096/8192 atlases, two/four cascades, 100/300/600 m limits and hard/soft filtering implemented as opt-in controls. Bias unchanged. No cheapest acceptable preset or new default selected. |
| VQ-04b-S04 | Improve aircraft self-shadow and animated control/gear coverage; compare adaptive projected detail only where it helps. | Pending with aircraft/AS. Source bindings stable; matching poses, scale variants, stopped/fast rotor controls and no per-frame geometry rebuild. |
| VQ-04b-S05 | Refine penumbrae and natural-versus-assisted cue behavior; separately compare AO/contact candidates. | Pending. Contact default remains off unless the previously failed scene and expanded motion matrix pass. Preserve marks/paint and direct-light energy. |
| VQ-04b-S06 | Coordinate vegetation, people and structure caster coverage, alpha, wind, LOD and bounds. | Pending with L/LU/SC. Stable moving foliage and actors; measured near-grass tradeoff; no stale poses or lost fence gaps. |
| VQ-04b-S07 | Qualify non-planar receivers and distant fade for both landscapes and activity cameras. | Pending with L/LU. Slopes, shoreline, roofs, offscreen casters and landscape switches; projections cannot masquerade as valid terrain shadows. |
| VQ-04b-S08 | Introduce bounded field/landing-light shadow selection and local atlas allocation. | Pending with FW/FW-RGB. Start with one light, then budget tiers; no popping, unbounded lights or emission changes. |
| VQ-04b-S09 | Align cloud, sun/moon and twilight shadow behavior with existing world state. | Pending with FW/TOD/SUN. Flowing and frozen time, low horizon, pause/reset, lake/aircraft/terrain consistency. |
| VQ-04b-S10 | Finish presets, diagnostics, cache invalidation and resource/lifecycle budgets. | Pending with VQ-06 and DT. Idempotent settings; bounded maps/casters; repeated Home/Workshop/Fly/reset/destruction/restart cycles without growth. |
| VQ-04b-S11 | Run controlled native visual, motion and performance campaigns; integrate the selected slice. | Pending with VQ-06c/VQ-07g and CAM/DT. 1080p first, then higher resolutions, then 720p; named target-hardware and package receipts. |
| VQ-04b-S12 | Publish accepted settings and limitations in canonical player/tool guides; consolidate completed plan material. | Pending. Only implemented/qualified claims; retain source and negative evidence, remove completed-plan duplication per documentation policy. |

Suggested reviewable releases: **A** = S00–S03 (clear controls and allocation); **B** = S04–S07 (aircraft and field detail); **C** = S08–S10 (night/world coherence and complete presets). Each goes through the applicable portion of S11 before use as a default. This is dependency order, not a promise that every optional effect will ship. S12 follows the accepted scope.

## 10. Acceptance matrix

| Axis | Minimum representative coverage |
| --- | --- |
| Resolution | Actual 1920×1080 render target/output first; actual 2560×1440 and 3840×2160 next; 1280×720 fallback last. Record internal scale separately. |
| Renderer / AA | Standard and High native baseline; selected MSAA and reconstruction combinations separately. Do not compare two shadow techniques with different AA/exposure. |
| Aircraft / vehicle | Ugly Stik, Extra 300S and P-51 for initial variety, then every enabled fixed-wing family and installed helicopter/ground activities before shared promotion; representative Workshop scales. |
| View | Pilot autozoom on/off, low approach, chase, orbit/inspection, overhead and close Workshop; tested camera transitions/FOV changes. |
| Lighting | Noon, low sun, sunset/twilight, moonlit and moonless night, moving cloud shade, selected field and landing lights; existing storm cases where affected. |
| Geometry | Wheel/skid ground contact, thin struts/fence, wing-root recesses, leaf cutouts, grass edge, pavilion roof, slopes and shoreline. |
| Motion | Taxi/takeoff/landing, bank/roll, moving controls/rotors, wind/actors, camera pan/zoom and light motion; 30/60/120/144 Hz presentation where supported. |
| Lifecycle | Home → Fly → pause → Workshop → return; reset, landscape change, crash/source destruction, retained-world reattachment, repeated setting Apply/Revert and renderer restart. |

Visual gates:

- At fixed light/pose, contact remains attached and finite. Establish a proposed **≤2 output-pixel gap at 1080p** for agreed wheel/skid close-view fixtures, after accounting for the baseline edge noise; freeze fixtures and tolerance before candidate selection.
- No newly obvious acne, detached shadows, cascade bands, frozen animation, duplicate dark outlines, foliage rectangles, screen-edge disappearance of ordinary shadows or shadow through a nearer receiver.
- A completely lit control panel retains the existing [shadow-energy oracle](../../tools/graphics/README.md) result. Stronger darkness elsewhere is not evidence that this gate passed.
- Thin features and penumbra widths are measured in fixed ROIs; a paused identical scene does not drift beyond its documented repeat envelope. In motion, inspect video at normal speed and frame-step the difficult transitions.
- Preserve aircraft silhouette/orientation readability against sky, field and treeline. Use existing VQ/CAM evidence procedures and independent pilot judgment; a sharper shadow cannot compensate for a less readable aircraft.

Performance protocol:

1. Freeze the same source/assets/engine, settings, camera/input tape and world time for each pair. Record GPU, driver, OS, thermal/power state, foreground status and actual renderer/resolution. Exclude overlapping rendered workloads.
2. Separate cold allocation/first-use hitches from steady state. Use at least three valid alternating A/B pairs with an agreed warmup and a representative active-flight window; record all exclusions and raw timing identities.
3. Require the existing whole-frame, loading and resource gates as well as the agreed incremental shadow budget. A cheap static scene or idle offscreen viewport does not qualify flight.
4. Inspect shutdown and long lifecycle resource behavior. Changing world/light/renderer configuration cannot accumulate maps, stale visibility or retained caster resources.
5. Keep accepted/rejected candidates identifiable. Change one independent variable per initial comparison; test the final combined preset again because individually acceptable effects may exceed the combined budget.

For temporal artifacts, first capture baseline A twice and candidate B with a fixed camera and stationary shadow region. Compare exploratory luminance-change distributions against the A–A noise floor and a deliberate flicker/jitter control; retain paired still differences and normal-speed video. Moving-camera numerical comparisons require reliable motion alignment and disocclusion handling. FLIP per frame is not a temporal-perception metric, and diagnostic ROI masks must not silently replace the existing full-image acceptance checks. [Investigation I15](../research/shadows-2026-10-31.md#i15--image-differences-versus-temporal-shadow-stability).

## 11. Verification tools and first implementation packet

Use [graphics tools](../tools/graphics.md), [shadow tools](../../tools/shadows/README.md), [High/contact probes](../../tools/graphics/README.md), [debug bridge](../../tools/debug/README.md) and [performance collection](../../research/performance/README.md) as the command authorities. The legacy `vq04a_verify.py` requires its documented pre-feature baseline; do not point it at arbitrary modern snapshots and call that a valid comparison.

Relevant existing checks include projected/field/windsock/collection/blur/wreck-shadow tests, High profile/restart tests, display preferences, advanced graphics settings and affected landscape/material tests. Extend focused checks for resolved settings and ownership only when implementing those contracts. Rendered changes also require applicable capture checks and actual image review; follow repository requirements for the final runtime suite. This documentation-only delivery needs link/content checks, not a flight-suite rerun.

The first implementation packet should contain: the S00 caster/receiver inventory, matched current Standard/High 1080p landing and pavilion clips, clear requested/effective shadow diagnostics, a minimal S01 ownership decision and one S03 allocation comparison. It should answer **which specific detail improves, at what measured cost, on which hardware**, before default settings change.

## 12. Deferred research and completion rule

Revisit custom GTAO, screen-space shadow addons, temporal shadow accumulation, cached far-shadow engines, virtual shadow maps, hardware ray tracing, colored glass transmission or volumetric smoke/cloud self-shadowing only after a reproducible shortcoming in the native/bounded paths. Require license/maintenance/renderer/version evidence and an isolated prototype. Do not convert an interesting paper or impressive screenshot into an engine dependency.

The selected scope is complete when its settings are truthful and persistent, its moving shadows improve the stated details without reducing flight readability, its named hardware/package gates pass, and its fallback remains usable. Optional features may be explicitly rejected with evidence. “All options enabled” is never the completion condition.

## 13. Targeted C++ efficiency work

The [C01–C06 investigations](../research/shadows-2026-10-31.md#third-round-six-c-efficiency-investigations) assess where native code could help. **No new C++ helper or engine patch is implemented or benchmarked.** The first implementation instead resumes the existing ordered field bounds scan after its already-scanned static prefix; exact-output checks are in the implementation record. No speedup is claimed without uncontended current measurements. Keep this work under S00/S04/S06/S10/S11 with DT-11a construction/performance ownership. Rendering-native helpers remain separate from the existing physics evaluator and its ABI, qualification and float64 simulation contracts.

### First candidate: packed geometry preparation

`Projected.collect()` already uses native bulk transforms and packed appends. Its remaining per-triangle cutoff and ordered bounds work, together with field population collection, is the strongest *conditional* CPU candidate identified by source inspection. Re-profile it on the current engine before selecting a port. The target is faster shadow binding/field construction; a steady-state FPS benefit needs separate evidence.

Proposed optional helper boundary:

| Stage | Responsibility |
| --- | --- |
| Existing GDScript owner | Traverse/select sources, honor visibility/propeller exclusions and placement ownership, snapshot accepted transforms/geometry and retain world/source identity. |
| Existing native bulk APIs | Continue transforming packed face streams; compare any later fusion against this accepted path. |
| One coarse C++ operation per meaningful batch | Process immutable transformed faces and cutoff parameters; preserve triangle ordering, original cutoff semantics and ordered AABB expansion. Avoid engine/property calls inside the vertex loop. |
| Returned data | Independently owned packed faces, exact bounds/counts and explicit status; no borrowed pointers or mutation of the caller's mesh arrays. |
| Existing presentation owner | Build/install meshes and receivers, apply renderer/material settings and discard stale results. Preserve the GDScript reference path. |

Use pre-sized output and direct packed-array access with correct copy-on-write/lifetime handling. Preserve the distinction between GDScript's 64-bit scalar cutoff/accumulation and ordinary 32-bit rendering vectors. Keep compiler reassociation/contraction controlled until exact-output tests justify otherwise. Existing nonfinite-cutoff behavior and boundary equality belong in the comparison; silently changing them is not a pure optimization.

Do not start with the fallback blur: its completed mip bytes are already cached after the first call. Any remaining benefit concerns first generation. The eight-corner framing calculation and cached per-frame refresh also need attribution before a native port. These smaller candidates cannot inherit the historical collection timings.

### Other opportunities and their triggers

| Investigation | Candidate / reusable path | Trigger and acceptance |
| --- | --- | --- |
| C01/C02 | Optional pure GDExtension geometry helper | Current collection is a material CPU cost; complete snapshot → call → output → binding beats current bulk GDScript beyond run variability, with exact reference output. |
| C03 | One bounded worker job over immutable geometry | Construction causes a visible main-thread hitch after synchronous optimization. Improve first usable frame/pacing, not merely worker throughput. Cap jobs/bytes; use generation checks and reap every task. |
| C04 | Whole MultiMesh buffer preparation/submission | Profiling identifies repeated CPU instance preparation. Compare current per-instance work, script bulk and native bulk; retain spatial partitioning and measure extra GPU shadow draws. |
| C05 | Native import optimization / bounded immutable geometry cache | The actual imported resource or repeated static collection is wasteful. Reuse the engine's existing meshoptimizer/import path first; prove identity/invalidation and regenerate through owning pipelines. |
| C06 | Independently packaged optional GDExtension | A small public-API helper produces meaningful application-level benefit. Match engine API/precision and release toolchain; verify platform packages and missing/incompatible-library refusal. |
| C04/C06 | Compute implementation, engine module or private-renderer patch | A measured requirement cannot be met through supported APIs. Separate renderer, portability and upgrade-maintenance evidence is required; no initial adoption. |

Godot's renderer is already native. C++ cannot eliminate GPU PCSS sampling, alpha overdraw or cascade passes simply by replacing the GDScript caller. RenderingDevice compute is a separate modern-renderer route and does not supply a Compatibility implementation or an automatic hook into private shadow passes.

If asynchronous preparation is justified, snapshot on the owning thread, compute over CPU data only, and install on the main thread if the source/world generation remains valid. Reset and teardown must discard obsolete results and eventually join/reap submitted tasks. Do not capture live scene nodes, perform direct GPU work from the worker or immediately wait after submission on the frame-critical path. A thread pool is an optional scheduling improvement, not a default architecture change.

For a native package, reuse the existing native tooling's pin/receipt/fallback patterns without adding shadow work to the physics library. Its current OS/RefCounted-only binding profile is not sufficient evidence for a RenderingServer-based helper. Record API description, precision, compiler/flags, library/source hashes, OS and architecture; qualify Windows/Linux/macOS individually where intended. A module/fork additionally needs matching editor/export builds and recurring upgrade ownership. Preserve a normal reference launch when the optional library is unavailable; that fallback cannot recover an arbitrary in-process native crash.

### Measurement and promotion

1. Use the current source and engine as baseline, including native transforms, run batching and the mask cache. Separate source traversal, input packing, cutoff/bounds, allocations, mesh creation/upload and GPU work before choosing a C++ boundary.
2. Compare release builds, starting with a boundary-overhead control and realistic small/large geometry batches. Report kernel time and complete binding/loading time separately; retain at least three valid alternating native process pairs and the existing exclusion rules.
3. Reuse the collection/population/blur oracles as applicable: exact faces/order, counts, AABB, cutoff boundaries, source isolation and image/mip bytes. Test absent/incompatible helper, reset, repeated scene replacement, teardown and peak/residual memory.
4. Verify actual 1080p Standard and High shadows, including masks and full scenes; only then expand resolution coverage. Account for subviewport GPU work separately from root-viewport timing. No shader/quality change may be bundled into a pure CPU comparison.
5. Set a useful absolute improvement target for the affected user action before measuring. The gain must exceed the observed noise and improve that action without worsening whole-frame/load/resource gates. An inner-loop percentage alone is insufficient. Do not add overlapping CPU/GPU/wall measurements or multiply a first-load saving into an FPS claim.

Only after this evidence should a candidate become the default on its qualified platforms. Until then, the concrete next action is **current construction attribution followed, if warranted, by one pure face-filter/bounds prototype**. The [shadow tools](../../tools/shadows/README.md) and [performance tools](../../research/performance/README.md) remain the command authorities.
