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

Use the project’s existing gravel shader and ground/path materials ([gravel shader](../../../../app/scenery/gravel.gdshader), [ground materials](../../../../app/render/ground.gd)). The rideable rollers, tabletops, berms and walls should be represented by the same course/terrain data that drives contact; a decorative mesh that disagrees with that surface would mislead the driver.

Do not model new cones or barrier props. If the course needs those decorations, [OpenGameArt’s Traffic Road Assets](https://opengameart.org/content/traffic-road-assets) is a low-poly CC0 pack that includes cones, crush barriers and roadblocks. [Kenney Road Textures](https://kenney.nl/assets/road-textures) is another CC0 source for simple surface details; Kenney confirms its asset pages use CC0 on its [license FAQ](https://kenney.nl/support). Reuse only the needed files and retain their license/source record.

## Implemented contact and presentation contract

The [track descriptor](../../../../app/data/ground_vehicle/airfield_track.json) owns dimensions, dirt friction, ramp/roller profiles, walls and spawns. The float64 [track sampler](../../../../app/physics/ground_vehicle/airfield_track.gd) adds a continuous elevation profile and analytic gradient to the accepted airfield terrain. The default field/runway geometry is matched explicitly; custom fields retain their own ground and two runway starts. The course identity pins descriptor bytes and the sampler/contact source artifacts.

The [renderer](../../../../app/vehicles/ground/airfield_track_view.gd) samples that same road on a 0.1 m grid, adds only a 2 mm separation, reuses the existing gravel shader and palette, and renders each wall from its physical box bounds. Painted edges, direction arrows and bilingual labels identify the loop and the infield practice branch. The garage adds three circuit entries and an overview camera.

Wall contact uses sphere/AABB signed distances for the four moving tire hubs and existing hull probes, with unilateral spring/damper loads and regularized dissipative friction. Both native and reference backends apply the same additive generalized loads through the coupled mass matrix. Wall loads are separate from terrain wheel loads; diagnostics highlight wall contacts. The existing recording format retains its terrain wheel channels and total energy; dedicated wall-load export channels are not included. Nearby-wall ticks larger than 1/120 s subdivide locally; the production 240 Hz tick is unchanged.

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
