# Trailer 2.0 — R5 claims, review gates and work queue

**Current screenplay:** [R5](cinematic-script-r5.md). **Status:** integrated scripts and source review, not filmed acceptance.
**Baseline:** game source 57abea025f62b20233ca281d58d2acbee4ab8b8e. Promoted-build availability, source capability, historical results and newly captured footage are separate evidence.

## Source-to-screen claim matrix

| R5 claim | Source basis | Boundary / future proof |
| --- | --- | --- |
| Core fleet coverage | [Aircraft catalog](../../../app/app_state/aircraft_catalog.gd), [vehicle roster](../../../app/app_state/vehicle_roster.gd), [coverage ledger](storyboard-150s.md#fleet-coverage) | 13 selectable roster/configuration entries, not 13 unique airplane designs. Distinguish the two Sticks. Hidden technical configurations and inspector are excluded. |
| Corsair ground mechanisms | [Bindings](../../../app/data/aircraft_models/f4u-corsair-250.json), [runtime](../../../app/main.gd), [geometry](../../../assets/aircraft/f4u-corsair-250/model-geometry.json) | Stopped on wheels, real state and native travel. Full wing travel about 8 s; master uses a 3 s end excerpt. Canopy about 2.5 s. No moving cockpit stick/pedals or cowl-flap promise. |
| Collective / playable helicopter | [Mechanism](../../../app/render/rotor/hx700_mechanism.gd), [inspector](../../../app/render/rotor/hx700_mechanics_view.gd), [playable visual](../../../app/render/rotor/heli_rotor_visual.gd) | Four-second labelled studio study, stopped rotor, neutral cyclic and both feathering roots. Then clearly separate X-Cell flight. Neither rotor RPM nor the old cyclic take proves this collective shot. |
| Hook, taxi and airborne retracts | [Mechanics sheet](mechanical-sequences.md#what-the-current-source-actually-supports), [session gear interlock](../../../app/sim/flight_session.gd) | Full coverage lives in Preflight Ballet. Retraction is airborne and authored at 4 s; loaded wheels block it. Tailhook remains ground-limited. |
| Full Corsair orbit / lake | [Stock schemes](../../../app/data/aircraft_models/f4u-corsair-250.json), [planar adapter](../../../app/render/lake/lake_planar_reflection.gd), [historical orbit](../../research/cinematic-trailer/revision-9-2026-10-29.md) | Ten-second continuous orbit, all 13 stock schemes, six-second Three Tone shoreline approach/crossing/exit. Proposed path: ~3.23 s above the source water polygon at nominal speed; not a clearance proof. Livery changes are editorial. Actual corresponding Corsair reflection needs proof; honest unmirrored lake is the fallback. |
| Other vehicle skins | [Picker](../../../app/ui/livery_picker.gd), [support](../../../app/aircraft/custom_skin.gd), [skin ledger](shot-bible.md#skin-and-continuity-ledger) | Real supported assets/IDs and individual output checks. A template does not establish a finished skin. |
| Live transmitter / instruments | [Manager](../../../app/render/overlays/overlay_manager.gd), [presets](../../../app/render/overlays/overlay_settings.gd) | Real simultaneous input/response, stable readable layout; select transmitter explicitly. Artwork is not hardware identity. Cockpit is a widget preset. |
| Hand launch | [Home](../../../app/ui/home.gd), [session](../../../app/sim/flight_session.gd) | Actual no-gear release/start and climb; no invented throwing-person animation. |
| FPV gates / modes / recovery | [Scene](../../../app/vehicles/multirotor/multirotor_scene.gd), [input](../../../app/input/multirotor_input.gd), [controller](../../../app/physics/multirotor/flight_controller.gd) | Real local gate order and OSD; Angle/Acro proven by actual mode. Turtle requires graded survivable contact, disarmed selection and correct arming, then same-attempt lift-off. No terminal reset or repaired-prop implication. |
| Practice failure | [Menu](../../../app/ui/failures_menu.gd), [catalog](../../../app/failures/catalog.gd) | Only eligible power-loss type selected; 100%/Early on a new ordinary Home flight. Actual event and same-attempt landing. Edited elapsed time, not an eight-second complete approach or natural failure-rate claim. |
| AI traffic | [Manager](../../../app/ai/companions/manager.gd), [agents](../../../app/ai/companions/agent.gd) | Actual accepted circuits in calm Club conditions, readable companions, no multiplayer/close formation/runway operations. |
| Scenery import | [Importer](../../../app/ui/landscape_import.gd), [library](../../../app/landscapes/phoenix_library.gd), [panorama](../../../app/landscapes/phoenix_flight.gd) | Exact calibrated revision, eligible runway aircraft, fixed eye, estimated ground/contact. Source images need usable rights; other imports may remain previews. |
| Storm / living field / night | [Integration ledger](feature-opportunities.md), [world](../../../app/render/world/world.gd), [events](../../../app/environment/storm_events.gd) | Actual flash, wind response, supported vegetation/gaze, birds and enabled fire. Rain is presentation; no traversable-cloud claim. Preserve readable vehicle/body/lights. |
| Physics Lab | [Dashboard](../../../app/vehicles/ground/ground_dashboard.gd), [model changes](../../../app/physics/ground_vehicle/vehicle_data.gd), [session](../../../app/sim/ground_vehicle/session.gd) | Real paused apply/restart; damping multiplier 1.00 versus 1.50, separate comparable runs and one visible setting effect. Estimated parameters; no live in-flight knob change. |
| Bisonte shore | [Airfield course](../../../app/physics/ground_vehicle/airfield_course.gd), [wet effects](../../../app/vehicles/ground/ground_wet_effects.gd), [environment loads](../../../app/physics/ground_vehicle/vehicle_environment.gd) | Normal shallow-shore route, actual wheel effects; certify the selected short route. Estimated open-truck model, not deep-water/boat or wave-physics validation. |
| Scale / smoke | [Workshop compiler](../../../app/workshop/compiler.gd), [size choreography](../../../tools/trailer/capture_formation.gd), [Workshop guide](../../AIRCRAFT-WORKSHOP.md) | Baseline Stick range only; actual giant/mini trials deliberately framed at different distances for readability, then labelled same-depth trio. Extra smoke must use an eligible actual profile. |
| Phoenix/ClearView montage | [Import sheet](import-showcase.md), [Creator](../../../app/ui/aircraft_creator.gd), [trial](../../../app/workshop/creator/trial.gd) | 18 planned distinct real previews, not accepted footage. Exact source identity, actual preview output and same final model's eligible trial. No blanket physics-fidelity, direct-PKG, bulk-import or normal-Home promise. |
| 300+ numerical variant | [Count gate](import-showcase.md#the-requested-300-title-prepared-not-yet-substantiated) | Inactive. Require deduplicated, current-build compatible-model evidence for the exact wording; a flyable-count claim additionally needs trial evidence. |
| Field Notes outcomes | [Companion screenplay](feature-companion-films.md), [source ledger](feature-opportunities.md) | Actual touch-and-go statistic, real Natural Random selection, supported energy, separate fixed-wing wreck/report, correct field/rain routes. No fabricated statistics, repair economy or unlabelled time compression. |
| Production / public invitation | [Retained capture study](windows-rtx3090-capture.md) | Exact build, device, renderer, source rights and official destination. Offline 60 fps output does not establish real-time hardware performance. |

## Stage A — screenplay review now

**A1 — Narrative and complete integration.** R5 retains a location for every discovered opportunity and supplies explicit preparation, start/end targets, camera, cast and skin for every cut. R4 gave every discovered opportunity a master or companion location. Core fleet, original full-skin Corsair orbit/lake, ground mechanisms and separate collective remain. Imports receive a rapid 15-second expansion chapter with a same-model flight payoff.

**A2 — Paper timing.** Master: 150 s / 9,000 intended frames; 112 G, 15 U, 18 P, 5 E; 62 cuts including 18 preview cuts. Field Notes: 90 s / 5,400 frames. Preflight Ballet: 32 s / 1,920 frames. No old shared reserve survives. Retiming must change screenplay/storyboard/coverage together.

**A3 — Claims and document agreement.** Source/count evidence controls copy. The 300+ variant stays inactive. R4/R3/R2 are historical; current index, screenplay, storyboard, mechanics, treatment, bible, integration ledger and these gates follow R5. The [R5 audit](script-audit-r5-2026-11-21.md) records completed checks.

**A4 — Actual visual story.** Later moving footage/animatic must pass mute and phone-size review: recognizable opening, clear gates/recovery, readable mechanisms, input-to-bank relation, actual comparison result, diverse preview silhouettes and five-second invitation. Script/source review alone cannot pass this gate.

**A5 — Numeric/source agreement.** The [R5 plan](shot-plan-r5.json) retains 62 R4 IDs and pins 32 source files. Its offline checker verifies source hashes/assertions, catalog-to-data/visual-family/selectability bindings, actual skin IDs, storyboard boundaries, source classes, 18 preview intervals and the exact 13-livery order/45×12+60 frame rhythm. NED maps and render-coordinate exports remain proposed staging. Ground NE markers do not fabricate supported CG heights; the existing orbit uses visual-model-root anchoring.

## Stage B — first code and remaining capture routes

Select the promoted build, approved source assets and exact shot needs, then qualify existing capture/editing routes. The [Windows study](windows-rtx3090-capture.md) and [music research](research-music-and-trailers.md) are retained input; they do not choose a new package, model API, paid generation service or soundtrack. No game change is implied.

The current request authorizes incremental code on the trailer branch. The first increment supplies offline validate/show/export/map commands and an opt-in `--livery-hold-last` in the existing director. Focused software evidence is recorded in the R5 audit; no simulation law or app runtime changes.

Remaining routes require actual implementation or manual staging: safe pre-tree fixed-wing origins, camera targets and state records, stopped HX-700 collective schedule, X-Cell pad/livery/governor preparation, scale-trio paint and source-identified imports. `capture_vehicles.gd` starts X-Cell airborne without livery input; `capture_flight.gd` disables configured failures. They do not yet perform those R5 setups. Actual per-frame livery evidence must align simulation time with the intended edit frames.

## Stage C — proof takes and production later

| Gate | Future work | Acceptance / fallback |
| --- | --- | --- |
| C1 | Ground mechanisms and collective | Native-speed full takes/excerpts; fixed references; both blade roots; readable full-time inspector label; separate X-Cell identity. Extend/retime when needed. |
| C2 | Orbit/lake signature | Continuous full orbit, all 13 stock schemes at the R5 rhythm, final Three Tone held into approach/crossing/exit; source root anchor preserved. Matching actual reflection if qualified; otherwise retain genuine unmirrored Corsair lake. |
| C3 | Core fleet/actions | Every roster entry recognizable; real jet attitude, valid gate clearance, correct modes, complete nitro-truck landing and playable helicopter motion. |
| C4 | Recovery and practice | Surviving graded contact, actual turtle flip and same-attempt lift-off; separate authentic configured failure and controlled landing excerpts. |
| C5 | Experiment and water | Comparable real suspension runs around an actual apply/reset; shallow route and observed tire/water/mud effects. No guaranteed giant splash. |
| C6 | AI, scenery, storm and night | Accepted runtime routes and exact settings; readable distant companions; calibrated panorama; actual flash; visible Lumber body/lights. Transfer a failed standalone feature explicitly to the companion rather than inventing proof. |
| C7 | Scale, smoke and skins | Supported real trial configurations, same-depth disclosed trio, actual smoke profile and selected skins. Tiny models and dark bodies must pass visual reading. |
| C8 | All import preview slots | Exact model/source hash, admitted conversion, real Creator preview, usable footage rights, silhouette/readability and source label. Reject/refill individual slots; no repaint-count padding. |
| C9 | Import flight payoff | Same final previewed model, eligible setup/start and actual successful trial on the promoted build; correct estimated/donor label. Recast/reorder explicitly or remove the flight promise. |
| C10 | Numerical copy | Count evidence per import-sheet gate. If absent, retain EXPAND YOUR HANGAR with no numeric claim. |
| C11 | Companion outcomes | Real touch-and-go statistic, chosen Natural Random flight, real energy states, same-incident wreck/report and supported field effects. |
| C12 | Sound and finished media | Actual audition/cue map/licences, distinct propulsion, no inspector/flight audio mismatch, full decode, frame/dimension/colour/audio checks and actual final duration. |
| C13 | Public invitation | Verified official destination, promoted build/status and language versions. Campaign publication is a separate later action. |

## Timing and evidence rules

R5 has no spare timing pool; it retains the R4 cut IDs and boundaries. When real takes need more time, first transfer a complete standalone scenery, AI, storm or Angle/Acro chapter to Field Notes and record the resulting coverage change. Preserve orbit/lake, the import chapter, successful recovery, core-vehicle identification and five-second invitation. Never spend one released interval twice.

Future takes record build/engine/host, vehicle/model/source identity, skin, settings, camera, source class, real contact/race state, media/audio hashes and review result. Use the [shot identity record](shot-bible.md#future-per-shot-identity-record). Unsupported, not examined and failed remain explicit; a planned fallback is not a successful take.
