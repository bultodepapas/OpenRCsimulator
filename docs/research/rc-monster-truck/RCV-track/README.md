# RCV airfield track: siting and design research

Date: 2026-10-14  
Status: RC activity implementation and software verification; physical parameters and dimensions remain estimates.

## Siting

The default field data puts the runway at N=15 m, E=0, with a 100 m east-west length and 12 m north-south width. Its rectangle is therefore N=9–21 and E=−50–50. These source values are marked estimated in the field file, so the derived site clearances are estimates too ([field data](../../../../app/data/fields/default.json)).

The implemented capsule box, N=36.2–53.8 and E=−20.8–20.8, leaves 15.2 m north of the runway edge. A dirt approach at E=−10 from N=21 to 39 begins at the runway’s north edge, stays clear of the runway rectangle, and can meet a gate on the south straight. The explicit placements in [default scenery](../../../../app/data/scenery/default.json) do not enter either box or approach: the nearby pavilion is at N=−22 and pit shelters at N=−18.5. The [lake bank data](../../../../app/data/fields/lake.json) has an N/E bounding box starting at N=76, E=74; its conservative diagonal gap from the capsule box is about 58 m. No fixed scenery or lake conflict was found. The RC activity passes an additional grass exclusion for the access lane to the shared field builder. Near-pilot grass is limited to 30 m; the loop itself lies beyond that region.

The scenery profile places this site inside its flight-box region and caps props there at an estimated 1.5 m ([scenery data](../../../../app/data/scenery/default.json)). Keep walls, berms and dressing low; that cap is a project estimate, not an aviation standard.

The loop footprint is 41.6 × 17.6 m. The 1.2 m access shoulder begins exactly at N=21, so it leaves the runway height and material unchanged. The car still starts on the runway; circuit spawn choices are optional.

## Vehicle-scale guidance

This section records the initial 4 m/s layout assumptions. The later [power and driving revision](../RCV-drive/README.md) raises available straight-line speed; its route driver slows for this existing geometry. The initial verification figures below remain historical evidence for the original motor.

The values below are estimates for this simulator’s truck and stated maximum speed of about 4 m/s; they are not published RC track standards.

- A 6 m bend radius at 4 m/s gives about 2.7 m/s² lateral acceleration. A simple steady-turn calculation gives a roughly 15° balancing bank angle. Start around 12–18° and blend each bank smoothly into the straights; tire grip and suspension will change the actual limit.
- The proposed 3.2 m lane and 1.2 m shoulders leave room for steering error and recovery. The initial implementation uses five low AABB walls: three alternating infield slalom barriers and two short start-lane barriers. The access lane remains open.
- Ramp heights and profiles are tuned with the simulated vehicle and remain authored gameplay estimates. Keep their takeoffs smooth, leave several metres for landing before the next turn, and avoid placing a jump in a banked curve. Traxxas’s T-Maxx manual advises keeping the nose up and landing level on all four wheels; its shock guide explains how suspension absorbs a jump landing and settles afterward.
- Three rollers around 0.12 m high, spaced at least 3 m apart, give a controllable rhythm section. Velosolutions specifies a 3 m minimum roller spacing and a 4 m standard corner radius for human pump tracks, and says turn radius should grow with entry speed. Those are useful shape references only; the 0.12 m roller height and RC layout are estimates.
- Keep the infield slalom as a deliberate shortcut/practice branch with clear merge points. Avoid an uncontrolled crossing or bridge: the current road representation samples a single ground surface.

The [Velosolutions pump-track standards](https://velosolutions.com/velosolutions-pump-track-standards/) supply the roller-spacing and speed/radius references. Traxxas primary sources are the [T-Maxx owner’s manual](https://traxxas.com/media/productattach/C-49077-3/2/kc2892-r01-49077-3-t-maxx-tqi-owners.pdf) and [shock tuning guide](https://traxxas.com/news/suspension-tuning-guide-part2).

[Parkitect's pump-track explanation](https://www.parkitect.ch/blog/what-is-a-pumptrack) supports the linked-loop, berm and roller concept. [Traxxas's Maxx dirt-jump demonstration](https://traxxas.com/articles/maxx-dirt-mud-jumps-video) is visual inspiration, not a source of the simulator's dimensions or coefficients.

## Reuse and asset scope

Use the bundled CC0 Poly Haven Dirt and ambientCG Grass maps through the [shared ground material](../../../../app/render/ground.gdshader); the [gravel shader](../../../../app/scenery/gravel.gdshader) covers the no-material fallback. The rideable rollers, tabletops, berms and walls should be represented by the same course/terrain data that drives contact; a decorative mesh that disagrees with that surface would mislead the driver.

Do not model new cones or barrier props. If the course needs those decorations, [OpenGameArt’s Traffic Road Assets](https://opengameart.org/content/traffic-road-assets) is a low-poly CC0 pack that includes cones, crush barriers and roadblocks. [Kenney Road Textures](https://kenney.nl/assets/road-textures) is another CC0 source for simple surface details; Kenney confirms its asset pages use CC0 on its [license FAQ](https://kenney.nl/support). Reuse only the needed files and retain their license/source record.

## Implemented contact and presentation contract

The [track descriptor](../../../../app/data/ground_vehicle/airfield_track.json) owns dimensions, dirt friction, ramp/roller profiles, walls and spawns. The float64 [track sampler](../../../../app/physics/ground_vehicle/airfield_track.gd) adds a continuous elevation profile and analytic gradient to the accepted airfield terrain. The default field/runway geometry is matched explicitly; custom fields retain their own ground and two runway starts. The course identity pins descriptor bytes and the sampler/contact source artifacts.

The [renderer](../../../../app/vehicles/ground/airfield_track_view.gd) samples that same road on a 0.1 m grid, adds only a 2 mm separation, duplicates the shared ground material for the circuit, and fits each barrier to its physical box bounds. The existing gravel shader remains a fallback when no shared ground material is supplied. Lane paint, direction arrows, grounded bilingual signs and low timing hardware identify the loop and the infield practice branch. The garage adds three circuit entries and an overview camera.

On 2026-10-20 the five plain BoxMesh barriers were replaced visually with the supplier's weathered concrete [Poly Haven barrier LOD2](../../../../assets/source-deliveries/concrete-road-barrier-polyhaven/README.md). The CC0 mesh supplies tapered concrete, chipped checker paint, rough edges and metal lifting eyes; its 1K diffuse, normal and roughness maps remain on the fitted mesh. The renderer adjusts vertices, normals and tangents for each authored AABB and caches fitted variants. IDs, collision boxes and vehicle dynamics are unchanged. Five barriers total 23,610 rendered triangles. [The focused check](test_rcv_track_view-barrier-20261020.log) and [checked-run receipt](test_rcv_track_view-barrier-20261020.json) verify exact AABBs, UV/PBR preservation and no second physical world.

[Before](../../rc-ground-implementation-2026-10-15/verification/fence-upgrade-isolated-baseline-perf-20261020/mt8-bisonte__track_start__low-orbit__day.png), [after](../../rc-ground-implementation-2026-10-15/verification/fence-upgrade-isolated-candidate-20261020/mt8-bisonte__track_start__low-orbit__day.png), and [chase view of all five barriers](../../rc-ground-implementation-2026-10-15/verification/fence-upgrade-chase-20261020/mt8-bisonte__track_start__chase__day.png) are native Compatibility captures at the RC circuit start. Before and after receipts retain the same paused vehicle-state SHA-256; draw calls rose from 346 to 358 and the 60-frame p95 render interval was 4.556 ms before, 4.557 ms after on this RTX 3090. The captures disabled unrelated scenery because concurrent power-line work in the shared tree emitted script errors. Camera framing also varied between runs, so the frame intervals are a diagnostic, not a controlled performance comparison or hardware qualification.

Wall contact uses sphere/AABB signed distances for the four moving tire hubs and existing hull probes, with unilateral spring/damper loads and regularized dissipative friction. Both native and reference backends apply the same additive generalized loads through the coupled mass matrix. Wall loads are separate from terrain wheel loads; diagnostics highlight wall contacts. The existing recording format retains its terrain wheel channels and total energy; dedicated wall-load export channels are not included. Nearby-wall ticks larger than 1/120 s subdivide locally; the production 240 Hz tick is unchanged.

### Track detail pass, 2026-10-20

The shared ground shader now calls the [track-only finish](../../../../app/vehicles/ground/track_surface_detail.gdshaderinc) for finer near-view aggregate, faint compacted wheel paths and a broken, lighter shoulder. Its worn chalk lane lines follow the analytic capsule and sampled road surface; the old raised-looking stripe mesh is gone. [Direction arrows and the start grid](../../../../app/vehicles/ground/track_mark_paint.gdshader) have chipped pigment. These are visual treatments: the descriptor, sampled elevations, wheel contact and friction are unchanged.

The [course furniture](../../../../app/vehicles/ground/track_furniture.gd) uses [Kenney Racing Kit CC0 sign frames and checker flags](../../../../app/assets/landscape/track-signage/README.md), recolored into four grounded course boards with face rivets, a reflective rail, short checkered flags and paired low timing heads. Three off-course stacks use eight [Poly Haven CC0 Old Tyres](../../../../assets/source-deliveries/old-tyre-polyhaven/README.md) at the supplier's 0.6 m diameter and 0.165 m thickness, with its original 1K color, normal and roughness maps. The [rebuild check](../../../../tools/landscape/export_track_tyre.py) confirms 2,880 triangles and byte-exact embedded maps per tyre. All these props are render-only and outside the driving lane; the signs and tyre stacks are entirely beyond sampled road coverage. Do not treat them as contact obstacles.

[Baseline chase](../../rc-ground-implementation-2026-10-15/verification/track-detail-baseline-20261020/mt8-bisonte__track_start__chase__day.png) and [final chase](../../rc-ground-implementation-2026-10-15/verification/track-detail-final-20261020/mt8-bisonte__track_start__chase__day.png) show the same paused Bisonte state; the [low-orbit final](../../rc-ground-implementation-2026-10-15/verification/track-detail-final-20261020/mt8-bisonte__track_start__low-orbit__day.png) and [roller-side view](../../rc-ground-implementation-2026-10-15/verification/track-detail-paint-marks-20261020/mt8-bisonte__track_rollers__low-orbit__day.png) check the surface, signage and marks from additional angles. The [capture summary](../../rc-ground-implementation-2026-10-15/verification/track-detail-final-20261020/summary.json) records both complete native Compatibility views, and [parity](../../rc-ground-implementation-2026-10-15/verification/track-detail-final-20261020/parity.json) confirms exact vehicle state, model, source and solver identities versus baseline. Render-mesh identity changes intentionally with the new dressing. The capture command returned nonzero because of an unrelated maple-tree wind material warning; its log contains no track script or shader error. Its frame timings are diagnostics, not a controlled performance comparison.

The [track-view check](track-detail-checks/rcv-track-detail-final-20261020-sjx76bei/report.json) passes with 0 failures: road-mesh height and normals, exact five barrier AABBs, sign/tyre clearance, source PBR maps and no extra collision world. The [ground-material check](track-detail-checks/rcv-ground-material-final-20261020-vmu2qygi/report.json) passes with 0 failures and preserves the mesh arrays exactly. Both ran in native Godot 4.7.2. The tyre export script's `--check` also passed.

### Trackside service detail, 2026-10-20

Two full-scale [Innerscene CC0 safety-tape spans](../../../../assets/source-deliveries/barrier-tape-innerscene/README.md) mark the off-course jump and roller verges. A scaled [Poly Haven CC0 utility cabinet](../../../../assets/source-deliveries/utility-box-01-polyhaven/README.md) stands by the start timing heads. The source manifests retain supplier URLs and file hashes. These low, render-only assets add weighted posts, striped ribbon, metal enclosure, latch, vent and original textures without placing a false collision obstacle in the driving corridor. The [placement helper](../../../../app/vehicles/ground/track_service_detail.gd) samples all nine points across each footprint and omits a prop if the road/shoulder reaches it or the terrain height is invalid. The accepted default placements are below the estimated 1.5 m local scenery cap.

The supplier tape GLB has 24 primitives. At runtime its unchanged 4,816 triangles are combined by source material into three surfaces and reused for both spans; the source GLB and embedded textures remain available untouched. The [native track-view check](service-detail-checks/rcv-service-detail-final-20261020-tsvg14gr/report.json) passes with zero failures, including footprint clearance, height, source bounds, triangle count, three textured tape materials, cabinet color/normal maps and absence of a duplicate collision world.

[Before service props](../../rc-ground-implementation-2026-10-15/verification/track-detail-v2-current-20261020/mt8-bisonte__track_start__chase__day.png) and [finished start view](../../rc-ground-implementation-2026-10-15/verification/track-detail-v2-batched-20261020/mt8-bisonte__track_start__chase__day.png) share the exact paused Bisonte state SHA-256; the [finished roller view](../../rc-ground-implementation-2026-10-15/verification/track-detail-v2-batched-20261020/mt8-bisonte__track_rollers__chase__day.png) checks the second span. The [four-case capture summary](../../rc-ground-implementation-2026-10-15/verification/track-detail-v2-batched-20261020/summary.json) records complete native Compatibility renders. Compared with the unbatched trial, visible draw calls fall from 500 to 458 in roller chase and 657 to 589 in start chase. During these runs unrelated shared ground-shader source changed, so frame timings are diagnostics rather than an isolated performance result. Physical vehicle states match the earlier production captures; no contact data or solver source was changed for this detail pass.

This is an experimental RC course, not deformable soil or calibrated tire enveloping. The aircraft view/contact pipeline and ordinary scenery collision inventory are not extended by this activity-local course.

## Accepted layout and verification

| Feature | Authored geometry |
| --- | --- |
| Loop | Center N45/E0; 24 m straights, 6 m bend radii, 3.2 m lane, 1.2 m shoulders |
| Banks | Smooth cross-lane rise up to 0.85 m, blended into both straights |
| Main tabletop | N39/E−4; 0.48 m rise, 1.00 m approach, 0.45 m deck, 1.80 m descent |
| Secondary ramp | N39/E6; 0.28 m rise, 1.00 m approach, 0.35 m deck, 1.50 m descent |
| Rollers | N51/E−4,0,4; 0.12 m rise and 2 m total length each |
| Slalom | 3.8 m infield lane and three alternating barriers; two short barriers frame the start lane |
| Walls | Tops at 0.55 m above datum; bottoms at −0.03 m; exact AABB meshes and contact boxes |

The 0.32 m initial ramp was too gentle to produce a complete loss of tire support. The accepted profile produces a short controllable hop without changing the vehicle equations or injecting launch impulses.

Godot **4.7.2**, Windows x86_64, native vehicle evaluator:

- All **16 focused verification groups passed** in [verification-02](verification-02/verification.json): source freshness, mutation checks, float64 guard, loaders, course, airfield, track, wall contact, render geometry, input, dynamics, session, activity, presentation and menus. The overall manifest flag is false because another workstream changed `app/ui/home.gd` during that run. The [follow-up](integration-followup.json) identifies that sole change and passes the RC menu and shared field loader checks against an unchanged final source snapshot. The earlier `verification-01` is intermediate evidence from before the final label polish.
- [Track checks](verification-02/test_rcv_airfield_track.log): **19/19**. Main-ramp flight spans ticks 402–426, **0.104 s** with all four tires unsupported; touchdown at tick 427 is almost level (upright cosine **0.9998**). The western bank test retains full lane coverage, maximum path error **0.51 m**, maximum speed **2.51 m/s**, and no wall impacts. Every 1 m runway-grid sample at N9–21/E−50–50 retains the original terrain and material.
- [Wall checks](verification-02/test_rcv_obstacle_contacts.log): **12/12**, including forward/reverse impacts at 4 m/s, dissipative sliding, malformed metadata and native/reference parity. The authored slalom impact reaches about **115 N** normal load; this is a model result, not a measured wall force.
- [Render checks](verification-02/test_rcv_track_view.log): vertices match physical heights plus the declared 2 mm separation within **1.9 µm**; sampled triangle-centroid interpolation error is **6.14 mm** or less. All five wall meshes match their contact bounds. Clockwise front faces and packed-normal precision are checked.
- Final [RC menu checks](test_rcv_menu-final.log): **25/25**. Final [field loader checks](test_field_loader-final.log): **178/178**. The shared loader also needed a compatibility fix: a rotorcraft pad's tree exclusion is finite, rather than an infinite airplane approach strip; existing runway/mown clearances remain intact.
- [Fresh Windows RC-only package](package-verification.json): import, export, packaged start and native backend check passed. [Pinned source snapshot](package-source-sha256.json). This verifies the isolated RC entry, not the full application release. The package timing benchmark still uses the synthetic fixture; its recording p95 exceeded the 4.167 ms tick budget, so this run does **not** close performance qualification.

Native captures show the actual shared field and accepted simulation state:

- [Circuit overview](circuit-map-es.png), [state/backend receipt](circuit-map-es.png.json), [log](circuit-map-es.log).
- [Airborne at tick 414](circuit-jump-es.png), [receipt with four zero tire-contact flags](circuit-jump-es.png.json), [log](circuit-jump-es.log). The capture uses full throttle for 402 ticks, then coasts; no physical state is staged.

The overview capture emitted a four-ObjectDB cleanup warning at process exit. The final verbose jump capture exited without that warning or script/shader errors. These captures and numerical tests are software evidence, not physical calibration or a user playtest.
