# LU-21 — Replacement cars and people

Status: **integrated and native-verified, 2026-10-12**. Full regression status is recorded below. Owner: landscape integration lead; three bounded Luna max reviewers. [Plan](../../../plans/landscape-upgrade.md) · [landscape changes](../LU-16/README.md).

The owner's rejected population is replaced by **11 textured vehicles in three body styles and 13 clothed people in three poses**. Existing parking locations, aircraft, flying corridors and object response policy remain intact. The runtime uses shared meshes, materials and textures, MultiMeshes, import-generated mesh LOD and bounded simulation-clock movement. No runtime plugin was added.

## Visual evidence

These are unedited Godot captures. Click an image link for full resolution.

| View | Before | Installed result |
| --- | --- | --- |
| Parking | [Old cars](evidence/final-before-day/car_park.png) | [New vehicles](evidence/final-after-day/car_park.png) |
| Close vehicle | [Before](evidence/final-before-day/cars_5m.png) | [After](evidence/final-after-day/cars_5m.png) |
| Standing visitor | [Before](evidence/final-before-day/people_5m.png) | [After](evidence/final-after-day/people_5m.png) |
| Seated visitors | [Before](evidence/final-before-day/seated_5m.png) | [After](evidence/final-after-day/seated_5m.png) |
| Pilot with transmitter | [Before](evidence/final-before-day/pilot_5m.png) | [After](evidence/final-after-day/pilot_5m.png) |
| Whole club | [Before](evidence/final-before-day/postcard_club.png) | [After](evidence/final-after-day/postcard_club.png) |
| Night pavilion | [Before](evidence/final-before-night/postcard_pavilion.png) | [After](evidence/final-after-night/postcard_pavilion.png) |

Also reviewed: [people at 15 m](evidence/final-details/people_15m.png), [40 m](evidence/final-details/people_40m.png), [runway at night](evidence/final-after-night/runway_threshold.png), [blue-hour aircraft](evidence/final-blue-hour/twilight_aircraft.png), and [isolated model/LOD/motion images](evidence/assets-final/). All four parked aircraft remain visible: [Stik](evidence/final-details/parked_stik.png), [Extra](evidence/final-details/parked_extra.png), [P-51](evidence/final-details/parked_p51.png), [Avanti](evidence/final-details/parked_avanti.png).

## Selection and integration

- **Cars:** Innerscene's original, unbranded sedan, hatchback and crossover, CC0-1.0. Selective reduction preserves complete glass panes; a rejected global reduction produced holes. The hatchback also fills the existing sport-compact ID. Paint varies by instance. Generic source bodies are fitted to the existing estimated gameplay envelopes, not manufacturer-certified dimensions. [Research and primary links](assets-research.md), [vendored originals and manifest](../../../../assets/scenery/population/SOURCE_MANIFEST.json), [license evidence](../../../../assets/scenery/population/LICENSES.md).
- **People:** MakeHuman CC0 system assets and standing02; Anrico's anrico_sitting03 has matching CC0 catalog and internal metadata. Blender 5.2.2 / MPFB 2.0.18 produce static posed glTF meshes; GPL authoring code is not shipped. Shared 1K/512/256 textures, restrained clothing/skin tint and a simple original transmitter. [Research](people-research.md), [exact sources](../../../../assets/scenery/population/HUMAN_SOURCES.json), [licenses](../../../../assets/scenery/population/HUMAN_LICENSES.md).
- **Placement/physics:** a shared scalar helper places feet and person capsules on the 0.15 m veranda or 0.10 m pit slab. The seated contact is measured at 0.47421 m, with a 0.006 m fitting offset for the 0.48 m bench. Updated person envelopes preserve anatomy. Vehicle envelope tests use the actual native MultiMesh transforms. No new collision body per mesh triangle is introduced.
- **Grounding:** nearby human silhouettes join existing static-cell projected maps using cached CPU instance transforms. A separate `PopulationContacts` batch retains four tire patches and a compact directional hull per car, plus person support-plane patches; it participates in the day/night lighting transaction. This adds one draw and no projector maps or lights. These remain approximate custom shadows; characters do not cast engine shadow maps.
- **Sources:** 50 shipped resource/import files total **8,206,479 bytes (7.83 MiB)**. SHA-based image externalization shares identical textures between poses and vehicles. [Runtime file manifest](../../../../assets/scenery/population/RUNTIME_MANIFEST.json), [exported credits](../../../../app/assets/landscape/UPGRADE_CREDITS.md), [authoring tools](../../../../tools/scenery/population/README.md).

Integration points: `scenery/population.gd`, `population_person.gdshader`, `scenery.gd`, `support_surfaces.gd`, `collision_world.gd`, person entries in `prefabs.gd`, `ground_features.gd`, and `render/field_projected_shadows.gd`. Old procedural human/car helpers remain available for legacy checks but are no longer the production population. No aircraft physics/model, UI, preference, or other developer's edits were overwritten. [Guarded install](evidence/installed-files.json), [reviewed shadow correction](evidence/shadow-install.json), [final installed source hashes](evidence/final-source-sha256.json).

## Measured budgets

Godot **4.7.2.stable.official.ed1daf0bf**, Compatibility, OpenGL 3.3, NVIDIA RTX 3090, driver 610.88, Windows. Native 1920×1080, VSync disabled, scenery high, visual audio disabled, 60 warm-up frames and **600 measured frames per performance view**. Before/after captures are sequential; no task-owned render jobs overlap. Other user applications remained open, so these are shared-workstation measurements, not minimum-spec certification. `engine_shadows=on` was requested; the renderer reports zero shadow-map draws for these scenery captures, which use the project's custom contact shadows.

| Budget | Result |
| --- | --- |
| Close car ≤30k triangles (documented glass-preservation exception) | 26,066 / 27,002 / 27,517 |
| Close person ≤8k | 7,332 standing / 7,333 seated / 7,880 pilot |
| All scenery ≤600k | **539,383** indexed triangles including every MultiMesh instance; 47 static cells |
| Visible draws ≤300 / rendered primitives ≤1M | **246 / 481,453** maximum across the 600-frame views |
| Frame p95 <16.67 ms | **4.069 ms** maximum across those views |
| Matched increase ≤1.5 ms | Maximum **+0.498 ms** (day aerial); night maximum +0.399 ms in the final back-to-back pair |
| New runtime assets ≤20 MiB | **7.83 MiB**, including import settings |
| New texture budget ≤32 MiB | **23.59 MiB** conservative RGBA8 plus mip estimate; whole-scene reported video memory ≤184.10 MiB |
| Scene build hard gate <400 ms | 313.1 ms Windows / 290.0 ms Linux headless; older aspirational 150 ms remains open |
| No new light budget | Existing fixture/light count retained |

Raw frame samples, counters and exact commands: [comparison](evidence/performance-comparison.json), [runs](evidence/native-runs.json), individual `report.json` files. These timings measure the capture world/render loop, not full flight CPU time. Automatic LOD is measured independently: sedan 25,501→17,037 visible primitives at 5→120 m; standing person 7,150→890. [All six assets](evidence/assets-final/report.json). Manually generated far-car variants were researched but are not shipped.

The first post-shadow measurement compared against an earlier baseline and exceeded the incremental target (+1.744 ms). A fresh sequential baseline/upgrade pair measured +0.498 ms maximum; both baseline and upgraded absolute times rose. This is consistent with shared-workstation variability, not proof of a particular external cause. [The first samples are retained](evidence/first-shadow-timing/); the table uses the final paired result. No averaging away failures or low-end hardware qualification is claimed.

## Acceptance results

| Check | Proof / result |
| --- | --- |
| Native asset import, UVs/normals/materials, fit, sharing, instance count | [Native log](evidence/installed-population-native.log), all checks pass |
| Production scene budget, themes, quality tiers, deterministic geometry | [Build log](evidence/final-scenery-build.log), all pass |
| Three people poses: movement, pause, reset and 1024 s clock wrap | [Image hashes](evidence/assets-final/report.json): motion changes; paused image equals held frame; reset/wrap equal initial frame |
| Swept collisions, support heights and checkpoint identity | [Six focused scripts](evidence/final-collision/summary.md), 279 checks pass |
| Actual flight at 80 m/s into car/building/tree/lamp/parked aircraft, wreck, pause and reset | [Native production run](evidence/installed-runtime/runtime.json), **56/56**; [screenshots](evidence/installed-runtime/) |
| Glare angle, intensity, exposure, clouds, partial/full obstruction and aircraft crossing | [10 image checks](evidence/final-glare/glare-checks.json), all pass |
| Night marker visibility, fade, opaque occlusion, directional threshold colors | [8 image checks](evidence/final-markers/marker-checks.json), all pass |
| Aircraft crosses the solar disc in motion | [121-frame metadata](evidence/final-sun-transit/report.json), [hashes and five retained raw frames](evidence/final-sun-transit/frames.json); PNG readback timings excluded |
| Portable car conversion recipe | Blender 5.2.2 rebuilt all three close models byte-for-byte: [log](evidence/car-rebuild.log), [report](evidence/car-rebuild.json) |
| Population shadows and lighting transaction | [Field shadows](evidence/regression-corrections/test_field_projected_shadows.log): 63/0; [lighting updates](evidence/regression-corrections/test_time_of_day_scenery_update.log): 25/0 |
| Exported resource pack | [Pack proof](evidence/pack-check.json): all six models and matching credits load from an empty project; [finite 60-tick trimmed flight](evidence/pack-flight-check.log) |
| Fresh checkout without ignored caches or authoring files | [Clone and reviewed overlay](evidence/fresh-checkout/summary.json): clean import, population, field-shadow and scenery-build checks pass |
| Full Linux regression | **221/222 GDScript scripts pass** across initial run, continuation and corrections; shell tail passes. One previously documented Linux trim failure remains; details below |

All source archives, 23 selected human source/generated files and 12 export/package hash links were independently reviewed. Human recipe syntax and provenance pass; the final parameterized human recipe was not rerun after moving it from the tested prototype. [Evidence SHA-256 manifest](evidence/sha256.json).

### Regression qualification

The unchanged `app/test.sh` ran in an LF-normalized Linux copy of the installed working tree. Offline generation guards, float64 guard and every-script parsing passed. It stopped at the previously documented `test_atmosphere_flight.gd` extreme-density fresh-trim failure, followed by an empty-checkpoint diagnostic error. The same current test passes **140/140 on Windows**. [Initial log](evidence/regression/full-linux-suite.log), [Windows log](evidence/regression/windows-atmosphere-flight.log), [prior Linux baseline evidence](../LU-06/atmosphere-baseline.md).

The continuation ran all remaining 212 GDScript tests and the original shell tail. It found the actual missing population shadows, two stale scenery-count assertions, and missing Git HEAD metadata in the disposable test checkout. The shadow integration and count fixtures were corrected; the checkout received the existing repository HEAD and object access without changing application content. **Twelve final targeted reruns pass**, including all four failures, scenery lighting, field lights, checkpoints and production crash/reset. The shell tail, including flight/input and frame-rate checks, passes. [Combined summary](evidence/regression/summary.json), [original continuation](evidence/regression/continuation/remaining-summary.json), [final corrections](evidence/regression-corrections/summary.json), [source snapshot](evidence/regression/regression-snapshot.json). `app/test.sh` still exits 1; this is not a fully green suite.

## Remaining limits

There is one adult base with three poses, not a diverse character library. Pilot fingers are relaxed around the radio rather than individually posed on every control. Nearby trees and buildings remain stylized; this pass does not claim photorealism. People use small shader motion, not walking, facial animation or ragdolls. Window interiors remain shallow visual inserts.

The 3,877-proxy collision world is deterministic (`481b7b5dc048ef33dab7c4c6bcd261236a7143903f81c9af33e0930fdc4b5f13`). At 80 m/s, 240 Hz, first-hit p95 is **27 µs empty / 335 µs car / 321 µs tree**. The 100 µs nearby-obstacle target remains open; sampled hits agree with the independent exhaustive oracle. Impact coefficients remain documented estimates, not physical calibration. Independent pilot readability, lower-end GPUs, release installers and hardware radios were not qualified by this pass.

Automatic approval review rejected cleanup of a 14-byte MPFB `log_levels.json` outside the workspace. That logging-settings file remains. Subsequent authoring used isolated settings; the remaining file is documented in the human source record.
