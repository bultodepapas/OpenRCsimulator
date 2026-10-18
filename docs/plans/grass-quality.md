# Grass texture, shape and motion improvement plan

2026-10-17. **Status: implementation available as an opt-in preview; full-session and owner acceptance remain open.** Owner: landscape **L**, coordinated with **VQ**, **SC/LU**, **M5** and **RCV**. Evidence: [44 source investigations and current-code audit](../research/grass-quality-2026-10-17.md), including **24 additional investigations** in the second round; [implementation, comparisons and remaining gates](../research/visual-quality-implementation/grass-quality/README.md). Research decisions and conditional experiments are mapped in [section 9](#9-second-round-decisions-and-experiment-queue).

`OPENRC_GRASS_QUALITY=enhanced` selects shared photographic grass detail, the 100/30/20 high-quality species allocation and bounded imported-grass wind. The default retains the existing appearance and allocation. The Laplacian candidate was rejected after visual screening. Do not enable the preview by default until complete-session headroom, moving-view/RC review and owner gates pass; a native baseline run was ineligible because focus loss paused simulation.

2026-10-18 follow-up: Windows-preset packaged resource checks and 20 native enhanced Home/fixed-wing/both-RC lifecycle cycles pass. The extended imported-route seam check fails the existing FLIP limit in both default and enhanced modes; the identical-reference and deliberately bad seam controls behave correctly. This static result requires moving-boundary diagnosis before any transition repair. The five-pair native-session runner is implemented, but host preflight stopped the attempted campaign before launch because another Godot process was running. Current receipts and qualification limits live in the [implementation report](../research/visual-quality-implementation/grass-quality/README.md#2026-10-18-integration-follow-up).

2026-10-18 audit: exact-output rank caching reduces measured warm layout-selection CPU time from 49.721 to 0.887 ms in the enhanced open-field case; 92 parity checks preserve placement and geometry. Effective scene observations now guard performance comparisons. The six-profile moving-boundary matrix and bounded 8×/16× photographic sampling checks are complete; exact current Stik/P-51 and both-RC replay invariance passes. A subsequent session attempt again stopped before launch while an unrelated native tree capture ran. No camera-distance fade was justified by these diagnostics, and the static seam/owner/full-session gates remain open. [Audit, improvements and evidence](../research/visual-quality-implementation/grass-quality/README.md#2026-10-18-audit-and-optimization).

Improve the impression of short, maintained turf near the runway and irregular living grass at rough margins. The result should read naturally from pilot, chase and low RC cameras, retain aircraft orientation cues, and fit measured frame-time headroom. Prioritize scale, stable sampling, silhouettes and coherent motion before increasing resolution or density.

The [global performance/visual plan](global-performance-visual-quality.md) owns cross-track order and shared budgets. This document refines grass work under existing **VQ-02a**, **L9e-R1**, **L15c**, **L9d-05/06** and new **L9e-R2**, **L11a-R1/R2** follow-ups registered in the [landscape guide](../LANDSCAPE-PLAN.md). Shared phototexture adoption is a separate proposed extension, not an import-error correction. This plan does not reset completed L9d material work, duplicate the tree-specific L6b-R1 experiment, or close its pending acceptance gates.

## 1. Starting point and ownership

The field already has filtered turf and procedural macro variation. RC activities additionally use downloaded 2K Grass001. Default scenery uses three static imported grass types, at most 150 clumps and 49,579 source triangles; the separate scenery-off fallback has opaque blades, wind and a 22–30 m geometric fade. Detailed evidence and source references belong to the [dated audit](../research/grass-quality-2026-10-17.md#project-findings).

| Boundary | Owned paths / coordination |
| --- | --- |
| Ground appearance | [ground shader](../../app/render/ground.gdshader), [grass sampling](../../app/render/grass_surface.gdshaderinc), [turf detail](../../app/render/turf_detail.gdshaderinc), [RC detail](../../app/render/rc_ground_detail.gdshaderinc), [grass binder](../../app/render/grass_ground_material.gd), [RC binder](../../app/render/rc_ground_material.gd); L/VQ, with RCV for track shoulders |
| Imported grass | [placement](../../app/scenery/imported_near_grass.gd), [grass adapter](../../app/scenery/imported_grass_material.gd), [grass wind shader](../../app/scenery/imported_grass.gdshader), [shared vegetation library](../../app/scenery/imported_vegetation.gd); coordinate SC/LU because trees/flowers reuse the library |
| Fallback and integration | [near grass](../../app/render/near_grass.gd), its shader, [field builder](../../app/render/field.gd); preserve both construction paths and isolated material lifetime |
| Assets and tools | [RC intake](../../assets/landscape/rc-ground/README.md), [vegetation source pipeline](../../tools/landscape/vegetation/README.md), [grass tools](../../tools/grass/README.md), [ground tools](../../tools/ground/README.md) |
| Wind/state | Consume existing detached render wind and clock. M5 owns physical weather; simulation, tire contact, terrain identity and replay contracts stay unchanged. |

Read Git status before each slice. Keep source meshes and generated data authoritative; regenerate derivatives through their existing pipeline. No new grass texture or plant mesh should be authored while a suitable free retained/downloadable asset meets the requirement. Record source URL, author, license, exact archive/map hashes, units, import settings and generator version for any new intake.

Keep the initial comparison on retained assets. If those fail a named visual criterion, admit at most **two challengers per comparison**: a free cutout candidate to qualify in Compatibility and a free low-poly clump, selected from R35/R38. Inspect actual topology, UVs and material features before downloading more variants. Clover is an optional habitat accent, and the 224,000-triangle Bermuda source is reference-only under the current cap. Free availability does not establish fitness, redistribution terms for bundled content, or target performance. Tool candidates R31–R34 remain outside production unless an authoring requirement independently justifies them.

## 2. Target appearance by scale

Distances below are initial experiment ranges, not measured optima or new terrain classes. Use projected size, FOV and output resolution to qualify transitions; a zoomed pilot camera must not force high-detail grass across the whole field.

| Layer | Appearance target | Starting implementation |
| --- | --- | --- |
| Near surface, roughly 0–8 m | Short blades/thatch with credible millimetre detail, moderate contrast and no shiny plastic response | Retained 2K Grass001, existing 1.4 m scale and filtered normals; compare with accepted turf before sharing outside RC |
| Near rough-margin silhouette, roughly 0–12 m | Unequal heights, leaning tips, small gaps and clumps rooted in the ground | Reuse short/tall/wispy source meshes; favor short grass near maintained edges; taller sparse clumps farther into rough areas |
| Transition, roughly 12–30 m | Similar coverage/color with progressively less individual blade detail | Stable subset/LOD and geometric transition, then actual batch culling; retain the 30 m envelope initially |
| Far surface, beyond near geometry | Quiet macro variation, legible mowing/runway cues and stable optical flow | Existing ground, footprint filtering, haze and landscape palette; no field-wide 3D carpet |

Keep the mown runway and rotor pad clear. Do not add 12–25 cm grass to areas declared short turf. If current rough clumps appear too tall, compare a modest lower height range while checking width and coverage: uniform scaling also shrinks the clump footprint. Establish a reference sheet from the retained asset photographs and actual supported camera views; proposed heights are art-direction estimates, not surveyed vegetation.

Variation must be coherent: world-space patches may jointly influence density, short/tall mix and mild dry tint. Avoid independent random neon hues or identical isolated tufts at regular spacing. Preserve exclusions around runway, mown surfaces, buildings, paths and lake banks, including the full bent-tip envelope. Visual softness comes from graded density, silhouette and lighting, not from blurring the full image.

## 3. Reviewable implementation sequence

Every row ends with an adopt/reject decision and retained evidence. Conditional work may finish as **trigger absent / skipped**. Integrate one mechanism at a time; measure performance serially. Existing global prerequisites remain in force.

| ID | Work and dependency | Proof / status |
| --- | --- | --- |
| VQ-01c/01d, grass baseline | Freeze the current source, cameras, environment, profiles and real grass route. Reuse full-session timing and visibility kits. | Frozen baseline and native render fixtures retained. Complete-session headroom remains open: focus-paused collection is not qualification. |
| VQ-02a, grass intake/filter audit | Inventory base, turf, RC maps and imported materials. Verify scale, channels, mips, effective anisotropy and material overrides. Run the Compatibility alpha-support probe before considering cards. | Audit delivered; source/import/adapter stages separated. No alpha cards selected, so their conditional probe is not triggered. |
| L9e-R1 | Existing current-blend versus Laplacian experiment on retained turf, with its original baseline frozen. | Rejected: no clear visual gain in the five-pose screen, eight texture fetches versus two. Disabled-detail and aerial controls exact; no timing claim. |
| L9e-R2 | Compare the accepted flight/Home turf against one grass-only binding of retained 2K Grass001. Preserve the existing RC dirt/shoulder route. | Implemented behind the preview selector; separate grass-only binding, retained RC route, native captures and isolation checks. Full adoption gates remain open. |
| L11a-R1 | Improve imported-grass silhouette, species allocation, root/ground match and habitat placement inside the existing envelope. | Preview retains 150 clumps/three batches with 37,720 source triangles; nested quality subsets and exclusions tested. No new assets, ordering algorithm or habitat generator. Owner preference remains open. |
| L11a-R2 | Repair a demonstrated batch-culling or transition problem. Compare existing batching with a bounded spatial split; add a qualified geometric transition where needed. | Conditional; range/FOV sweeps, complete displacement bounds, no seam/pop and measured gain or named visual defect removed. |
| L15c, imported-grass slice | Add bounded root-weighted wind to the default imported route; preserve source material features and deterministic render time. | Implemented in the opt-in preview. Source parity under front/back/shadow/local lights, calm/repeat/wrap controls and displacement contracts verified; complete lifecycle/owner gates remain open. |
| L9d-05 | If RC driving still exposes missing nearby silhouette, evaluate a bounded world-anchored placement window using existing assets. | Conditional; world-cell stability, authoritative ground/exclusions, bounded uploads and lifecycle. No change to the normal fixed-pilot placement. |
| L9d-06, L6c, VQ-06c | Qualify accepted combination across RC, flight and Home, supported native hardware and packaged resources. | Pending; existing open gates remain open until their actual evidence is collected. |

The combined L9e-R2, L11a-R1 and imported-grass L15c evidence lives in [grass-quality](../research/visual-quality-implementation/grass-quality/README.md), including five paired render measurements and the independent acceptance limits. Extend that home for the remaining grass gates rather than creating parallel status reports. Other tracks retain their existing evidence homes. The opt-in implementation decision is recorded in DECISIONS; consolidate this plan only when its remaining acceptance work is complete or superseded.

## 4. Material specification

**Reuse and bind narrowly.** A shared grass-only opt-in must not blindly reuse `rc_surface_enabled` if that also changes soil behavior or unrelated consumers. Audit the include/binder first; split the smallest needed binding responsibility while preserving the RC baseline. Keep original and candidate materials private to each scene. Home, aircraft, RC track shoulders and return-to-Home must all use the intended effective material after transitions.

**Correct scale before detail strength.** Preserve the supplier's approximately 1.4 m tile and inspect blade size against tires/landing gear. Keep albedo color separate from linear normal/roughness/mask data. Retain the existing Compatibility-aware source means and normal projection; do not rotate decorrelation UVs without rotating their normal vectors. No vertex displacement or parallax-occlusion layer is proposed.

**Keep minification stable.** Retain explicit derivatives computed before hashed offsets and discontinuous masks. Use the same sample coordinates/weights across paired maps. Preserve major-footprint and distance filtering so unresolved blade detail converges toward the established far ground. Compare effective anisotropy at the existing setting and 8x; try 16x only if the remaining grazing blur warrants the cost. Negative mip bias is not a default fix for softness.

**Spend samples deliberately.** RC currently uses two samples per map: albedo, normal and roughness already mean six grass-map fetches before other ground work. Adding another full three-map layer approximately duplicates that work. Inspect shader branches and actual GPU cost; a zero visual blend weight does not by itself prove sampling disappeared. Keep the lossless packed turf data policy unless a separate error study qualifies compression.

**Preserve lighting.** Existing custom ground lighting does not provide a general grass specular lobe merely because a roughness map is bound. Treat new specular/backlight behavior as a separate conditional experiment. Start matte; match ground/root tone under both sun directions, clouds and night exposure. For clumps, retain tip normals and source texture detail; test only a modest root-normal/ground-color blend where a seam is demonstrated. No whole-clump emission, universal upward normals or per-blade dynamic shadows.

**Qualify material conversion before wind (R27, R40–R43).** Add a per-source feature manifest: source material → effective imported material → wind adapter. Check UV transforms, albedo/vertex color, normal texture/scale, roughness/metallic textures and channels, alpha mode/cutoff, culling/back-face lighting, filtering and shadow reception. Mark unused features explicitly. The current adapter copies only a subset; implement only missing behavior used by the accepted source. Compare the original material with wind amplitude zero under front/back sun and headlights before comparing animation. Turning off grass shadow casting does not turn an incorrect received-shadow response into an acceptable result.

**Separate normal operations (R22).** Only consider reoriented normal mapping when stacking distinct relief layers. Do not replace interpolation between alternative stochastic samples with a composition operator. Require flat-detail and detail-disabled controls before a visual comparison.

**Diagnose alpha coverage before choosing cards (R23, R42).** Inspect cutout coverage and RGB borders across mips; use a no-mip control to locate distant disintegration, then inspect its shimmer cost. Keep the initial solution within existing import capabilities or choose another free source. Custom mip import remains outside the global plan's initial slice. No-mip, negative-bias and alpha-blend workarounds are not defaults.

## 5. Geometry, distribution and visibility specification

First compare the existing 150-clump maximum with a different allocation **within 50,000 source triangles**. The wispy type consumes over half the current nominal total; shifting some instances to the retained 155-triangle short type creates room for coverage without inventing a new mesh. This is a hypothesis: reject it if the field becomes repetitive or loses useful silhouettes.

Use deterministic source-row or world-cell identity for species, yaw, size and phase. Quality levels must form nested subsets; switching quality must not move retained plants. Reuse authoritative exclusion predicates and the existing mask-bounds optimization. An optional broad patch weight can organize tufts, but cannot introduce gaps along runway borders or move placement with camera jitter.

If sparse profiles show accidental gaps, test progressive sample elimination as an **offline ordering experiment**, preserving the existing approximately 1/r radial density outside the central cap (R21). Rank eligible candidates within controlled radial/habitat strata and use stable tie-breaking. Compare ring counts, retained identities, nearest-neighbor distances and mask-edge holes. Store/validate the ordering through the existing generator; do not rank plants every frame or promise a uniform Poisson distribution. Conditional world cells also need deterministic shared-border handling to avoid seams.

Count batches by actual mesh parts/material surfaces. The current grass capture ceiling is **+5 draws / +100,000 primitives relative to grass hidden**, alongside the imported 50,000 source-triangle cap. Start with three batches; a first split can partition the expensive wispy batch into up to three spatial groups, reaching five total if the source-part contract still holds. Do not ship an unrestricted cell-by-species grid under an unchanged five-draw claim. If splitting does not save work within the gate, keep three batches.

Automatic mesh LOD does not provide per-plant LOD inside a batch. Qualify bounds and transitions explicitly. For imported clumps, prototype a root-preserving geometric shrink only when a visible range problem is demonstrated, retaining grounded base coordinates and suitable normals. Cull whole batches only once all their instances are outside the active envelope. Shader shrink/discard alone still submits work. Test from above, side-on and moving backward as well as toward the field.

Keep apparent coverage and submitted work as separate results (R25, R44). A modest compensation experiment is justified only after a visible transition band remains; cap footprint growth and recheck exclusions/overlap. Do not adopt the mesh-shader implementation that inspired the idea. Open-field occlusion is deferred (R28); only an existing building that meaningfully hides whole grass bounds can justify an isolated occlusion comparison.

Alpha-to-coverage is not a promised solution: the [research records the open upstream implementation](../research/grass-quality-2026-10-17.md#r11--msaa-does-not-prove-alpha-to-coverage-support). Favor existing opaque geometry; use scissored downloaded cards only if their silhouette, filtering and cost win in the pinned renderer. No alpha-blended grass carpet, TAA-dependent dither fade or Forward+-only visibility fade is part of the default design.

For conditional RC-local coverage, keep a capped pool of cells and update only on cell transitions, with hysteresis and bounded uploads. Derive each plant from stable world coordinates; car speed must not drag vegetation. Initially restrict placement to existing supported flat rough surfaces. Extending onto a bank requires the authoritative height/normal/exclusion sampler and separate alignment proof; a texture normal is not a terrain height. Test teleports, reset, return Home and failed scene creation before any wider use.

## 6. Motion and feel specification

The default imported grass is currently static; keep this as the control. Reusing the vegetation library's wind switch is only an integration starting point, because its material adapter serves other plant roles and must preserve every grass material feature actually used.

Compute a source-space root-to-tip weight from the asset's grounded bounds, rather than assuming texture `UV.y` is a bending mask. Keep roots fixed; increase bend toward tips with a smooth squared weight. Feed existing render wind, apply scale-aware bounded displacement and give neighboring plants coherent gust motion with small deterministic phase differences. Reuse existing noise/resources if needed; do not create another procedural texture asset or per-blade CPU update loop.

Use `sim_clock`, including its existing wrap behavior. Calm must have zero wind-driven motion. Freeze/resume and restored scene time must be reproducible; additional world-space waves must remain continuous across clock wrap. Wind direction is the existing render-space velocity, not a newly interpreted compass convention. Retain the full maximum displacement in both culling bounds and runway/path clearance.

Add translated, 90/180-degree-yawed and supported uniformly scaled copies to the wind fixture (R24, R39). Their roots must remain fixed and their bend must follow the same world direction. Reject unsupported nonuniform scale rather than silently assuming transpose equals inverse. Watch blade stretching before adding tip flutter; retain source vertex colors used for appearance. Per-plant phase/stiffness belongs in bounded custom data, not unique materials or batch-level instance uniforms. Compatibility's packed custom-data precision must be sufficient for the selected normalized values; keep world coordinates and identity hashes outside those channels.

Compare grass, trees and windsock under the same recorded gust. A plausible animation does not calibrate physical wind response; it must not imply a strong gust absent from the simulation. Wheel flattening, propwash deformation and persistent tracks are deferred: they need a demonstrated benefit and a separate bounded, read-only presentation design. Grass appearance must not change grip, rolling resistance, terrain or flight handling.

## 7. Acceptance and measurement

The global plan's gates remain authoritative: frame pacing p95 <=18 ms and p99 <=25 ms at the qualified 60 Hz profile, simulation/wall ratio 0.99–1.01, and an initial **+0.5 ms frame-p95 ceiling for all new visual work combined**. That is not an extra allowance for each grass effect. Reserve a measured portion before implementation; if there is no headroom, trade away an existing cost or retain the baseline. The stricter applicable RC regression gate also remains in force.

For timings, freeze engine/build/dirty-file hashes, field/asset identities, camera/FOV, input tape, weather, shader time, quality, resolution, VSync/cap, GPU/driver and power mode. Use 10 s warmup plus 60 s measurement, at least **five alternating baseline/candidate pairs** for this combined study; image capture stays outside timed runs. Keep raw failures and variation. Collect frame p50/p95/p99, CPU and GPU measurements where supported, draws, submitted primitives, texture payload/residency, construction/upload time and cold/warm scene load. Mark unavailable GPU metrics rather than calling wall time GPU time.

Record monitor names, units, cadence and build availability (R30). Derive percentiles from frame durations, not sampled FPS. Preserve the existing rendered-primitives gate's harness semantics separately from source triangles; unsupported zero values are unavailable. Distinguish compressed payload, allocation and residency. If material readback is inconclusive, use a versioned RenderDoc capture on supported Windows/Linux OpenGL hardware to inspect actual submissions (R26); capture/replay stays outside timing.

Screen each candidate on fixed representative pilot and RC workloads. Apply the paired protocol to each workload/profile whose performance is being qualified, including demonstrated worst cases and the final target hardware/output profiles. Use the remaining camera/lighting matrix for visual regression, adding timed cases when those views reveal a cost concern. State the covered profiles explicitly and retain the global plan's final complete-session requirements.

| Gate | Required evidence |
| --- | --- |
| Appearance and scale | Paired 720p/1080p images/clips: pilot normal/zoom, runway threshold, rough edge, chase, overhead and both RC vehicles in low orbit. Fixed sunlight, low sun, dusk and headlights/night. Owner checks scale, shape, ground contact and overall preference. |
| Temporal stability | Slow grazing pan, straight driving, turn, low flight pass, camera cut and movement through all LOD/fade boundaries. No new repeatable crawling, ring, synchronized sway or disappearing tuft. Static screenshots do not pass. |
| Material and transform fidelity | Source versus zero-wind material at fixed time; front/back light, local light, an occluder and translated/yawed/scaled instances. Preserve the features actually used, receiving-light response and fixed roots. Optional cards also need mip-coverage/edge crops and moving controls. |
| Near/far seam | Reuse the existing [grass seam protocol](../../tools/grass/README.md); extend the actual imported/candidate path and its envelope. Preserve the existing 3% channel-change / FLIP p99 0.1 engineering limits where applicable; include local strip checks and a deliberately bad seam control. Do not compare differently timed wind frames. |
| Alias attribution | Extend the [ground filtering protocol](../../tools/ground/README.md): known camera motion, detail-off control and independently supersampled reference. Subtract expected image movement; retain near-detail controls so deleting the feature cannot pass. |
| Flight readability | Reuse L6c/VQ visibility clips with contrasting aircraft and runway edge checks. Randomized A/B order; no repeatable loss of attitude or landing cue. Independent owner flight remains required. |
| State/contact invariance | Same exact accepted tape, ticks, state arrays/checkpoint identity and contact/terrain samples under existing contracts. Fixed-wing uses the [flight-log discipline](../FLIGHT-LOGGING.md), including complete/exact replay and `solver_changed`; RC uses its own existing recorder/harness. No new physics goldens. |
| Resource/runtime | No new grass colliders; bounded source/visible geometry and texture budgets; culling bounds contain deformed vertices. Parse all integrated GDScript and inspect native shader logs. Keep fresh material instances isolated across scenes. |
| Delivery/lifecycle | Fresh-clone generation/import and packaged asset/license checks; repeated Home/Fly/RC/reset cycles, with the global DT soak gate retained. Qualify named lower-end Windows/Linux/macOS hardware separately when available. |

Do not reuse the historical RTX 3090 timing dispersion as a performance pass. Diagnose with grass-hidden, material-simplified, wind-off and density-only controls before choosing a repair. For this proposal the first material experiment adds no new full-field pass or mandatory texture set; keep the existing 2K assets. Any additional maps require measured incremental residency and an explicit allocation within the owning resource budget.

## 8. Execution and rollback

The first delivery is a reproducible comparison kit and import audit. Complete the separately owned Laplacian experiment in its global-plan slot, then compare grass-only use of retained 2K detail against the accepted shared-field baseline. Geometry comes next only where the actual view shows a deficit. Qualify wind and RC-local placement independently, then test the accepted combination.

Reuse existing commands rather than introducing another toolchain:

- [Grass placement, imported/fallback captures and seam checks](../../tools/grass/README.md).
- [Turf, moving-reference and runway-surface checks](../../tools/ground/README.md).
- [RC source/import integrity](../../assets/landscape/rc-ground/README.md) and [actual-scene capture harness](../../research/rc-monster-truck/ground-closeup/README.md).
- [Vegetation source regeneration/checks](../../tools/landscape/vegetation/README.md), repository [test/capture/export workflow](../TOOLS.md).

Keep candidate selection explicit in research fixtures until each gate passes; production keeps the last accepted configuration. Reverting a material, placement or motion slice must not require a physics/data migration. Publish each adopted slice with its before/after evidence and measured limits; retain rejected experiments only as concise findings in the owning evidence report. Do not estimate a delivery date until the baseline identifies the actual bottleneck and target hardware is named.

## 9. Second-round decisions and experiment queue

This queue strengthens the existing steps; it does not create 24 implementation tasks or override global sequencing. Complete required audits first. Run a conditional experiment only when its trigger exists, and stop at the simplest candidate that passes the stated visual and cost gates. The [dated research](../research/grass-quality-2026-10-17.md#second-round-24-additional-investigations) owns external links, licenses and version observations.

| Priority / disposition | Research → owner | Trigger, concrete work and exit |
| --- | --- | --- |
| Required audit | R27, R30, R40–R43 → VQ-02a/VQ-01c, SC/LU | Add used-material feature manifest and counter semantics to the existing capture kit. Exit with actual route/material identity, zero-wind reference and light/transform controls; make only reproduced corrections. |
| Conditional diagnostic | R26 → VQ-02a | Unexplained readback/render discrepancy: inspect one versioned API frame capture. Exit with the responsible binding/pass identified, or record the unresolved limitation; never substitute capture timing for paired runs. |
| Conditional free-asset comparison | R35, R38 → L11a-R1 | Retained assets fail silhouette/shape review: inspect at most two free challengers at equal apparent coverage and existing caps. An atlas requires suitable free geometry. Exit adopt/reject with license/hash, imported topology/materials and motion evidence. |
| Conditional alpha repair | R23, R42 → VQ-02a/L11a-R1 | A chosen card loses blades or develops fringes: isolate cutoff, mip and border effects. Accept an existing-import/source solution or reject the card. Custom mip generation is deferred. |
| Conditional shading comparison | R22, R40, R41, R43 → L9e-R2/L11a-R1 | Demonstrated flattened relief or contact-light seam: separate normal composition, material lighting and source normals. Require identity controls plus day/night and back-face comparisons; no universal upward-normal fix. |
| Conditional placement comparison | R21 → L11a-R1 | Low-quality selection creates accidental holes: compare deterministic offline progressive ordering while retaining radial density and masks. Exit with stable nested subsets and improved field views inside unchanged budgets. |
| Required wind constraints | R24, R27, R39 → L15c | Before enabling wind on the imported route, pass zero-amplitude material fidelity, fixed roots, world direction and yaw/scale checks. Add bend correction/detail only if the simple candidate fails. |
| Conditional transition comparison | R25, R44 → L11a-R2 | A demonstrated pop/band remains: test root-preserving transition and, only if necessary, capped coverage compensation. Record visual continuity and actual submission separately. |
| Conditional first-use repair | R29 → global loading owner, coordinated with L15c | Reproduce a Compatibility compile stall on first visible grass. Compare bounded in-view loading warmup with baseline; preserve startup, cancellation and scene-lifetime gates. Resource preload or hidden nodes alone are not proof. |
| Deferred authoring options | R31, R32 → L/SC/LU | Only a documented editing bottleneck can trigger a disposable ProtonScatter or SimpleGrassTextured trial. Pin exact version/commit, preserve masks, test save/reopen/export and compare maintenance cost. Install neither by default. |
| Deferred/reference/rejected | R28, R33, R34, R36, R37 → owning track | No field-wide occlusion, terrain migration, legacy scatter port, mandatory clover layer or full-detail Bermuda scatter. Revisit only if the named prerequisite and existing total budgets change through the owning plan. |

The resulting minimum implementation remains small: establish material fidelity and a reproducible baseline, qualify retained ground detail, improve existing clump allocation/placement, then add bounded imported-grass wind and any demonstrated transition repair. Research breadth narrows the implementation choices; it does not justify enabling every technique.
