# Trailer 2.0 — R3 claims, review gates and work queue

**Current screenplay:** [R3](cinematic-script-r3.md). **Status:** script/source review, not filmed acceptance.
**Baseline:** game source 57abea025f62b20233ca281d58d2acbee4ab8b8e; the promoted release/build is not yet selected. Source support, historical footage, current capture and public-release availability are separate evidence.

## Source-to-screen claim matrix

| R3 claim | Basis | Boundary and required future proof |
| --- | --- | --- |
| All 13 visible configurations | [Roster](../../../app/app_state/vehicle_roster.gd), [aircraft catalog](../../../app/app_state/aircraft_catalog.gd), [storyboard ledger](storyboard-90s.md#complete-fleet-coverage--distributed-not-repeated) | Count identifiable appearances across the whole film, not a compulsory contiguous reel. Distinguish baseline glow and Electric 6S on mute; do not count inspector as a second playable helicopter. |
| Corsair surfaces, fold and canopy | [Bindings](../../../app/data/aircraft_models/f4u-corsair-250.json), [main mechanisms](../../../app/main.gd), [geometry](../../../assets/aircraft/f4u-corsair-250/model-geometry.json) | Grounded, stopped, genuine input/state. Full wing travel is about 8 s, canopy about 2.5 s; master uses excerpts. No animated cockpit stick/pedals or cowl flaps are promised. |
| Collective pitch mechanism | [Articulated mechanism](../../../app/render/rotor/hx700_mechanism.gd), [inspector](../../../app/render/rotor/hx700_mechanics_view.gd) | Separate labelled studio inspection, blades visible, fixed phase, neutral cyclic. Both roots must visibly feather. Old cyclic footage and increased RPM do not qualify it. |
| Playable helicopter | [Rotor adapter](../../../app/render/rotor/heli_rotor_visual.gd), [helicopter guide](../../HELICOPTER.md) | X-Cell .60 with legacy HX-700 visual; collective is telemetry only in that visual. Show actual flight separately from the articulated inspector. |
| Corsair cockpit/gear/hook detail | [Mechanical evidence sheet](mechanical-sequences.md#what-the-current-source-actually-supports), [gear interlock](../../../app/sim/flight_session.gd) | Canopy movement is supported; cockpit-control animation is not. Tailhook is ground-limited. Retraction belongs in an airborne companion take; current authored retraction is 4 s, blocked on loaded wheels. |
| Original livery orbit and lake | [Historical orbit](../../research/cinematic-trailer/revision-9-2026-10-29.md), [planar adapter](../../../app/render/lake/lake_planar_reflection.gd) | Preserve continuous orbit and editorial skin changes; no in-flight paint-control claim. One final lake skin must match its actual moving reflection. Corsair reflection remains unverified; no synthetic mirror. |
| Skins beyond Corsair | [Livery picker](../../../app/ui/livery_picker.gd), [skin support](../../../app/aircraft/custom_skin.gd), [casting ledger](shot-bible.md#skin-and-continuity-ledger) | Use real supported schemes in existing shots. Actual IDs/assets and rights remain to be selected; templates do not prove a finished skin exists. |
| 10/100/500% Stick | [Workshop compiler](../../../app/workshop/compiler.gd), [size choreography](../../../tools/trailer/capture_formation.gd) | Supported baseline Stick only, not all models or Electric 6S. Real separate trial passes precede the labelled same-depth cinematic trio. Approximate spans 0.1524 / 1.524 / 7.62 m. |
| FPV racing | [Quad camera](../../../app/vehicles/multirotor/multirotor_camera.gd), [gates](../../../app/vehicles/multirotor/race_course_visual.gd) | Real local course, real gate order and guidance. Separate camera takes do not establish synchronized replay. No online score or invented result. |
| Brief FPV contact/lens effect | [Quad scene lens/contact integration](../../../app/vehicles/multirotor/multirotor_scene.gd), [lens stack](../../../app/render/lens/lens_stack.gd) | Separate genuine ION R5 attempt after successful gate coverage; actual trigger/view/settings must qualify. A ground crash does not imply blood. R3 retains one non-blood effect only. |
| Instruments and camera views | [Camera rig](../../../app/render/camera/camera_rig.gd), [widget presets](../../../app/render/overlays/overlay_settings.gd) | Genuine session values and supported external views. Cockpit instruments do not imply a fixed-wing cockpit-interior camera. |
| Smoke and night | [Workshop guide](../../AIRCRAFT-WORKSHOP.md), [Lumber lighting](../../../app/aircraft/timber_visual_lighting.gd) | Extra show smoke requires its actual eligible profile/trial route. Lumber has aircraft-specific light anchors; do not assume every generic strip group. Body, smoke and lights need visual proof. |
| Creator preview to trial | [Creator](../../../app/ui/aircraft_creator.gd) | Same rights-cleared model, same compatible promoted build, eligible trial and honest estimated/donor handling. Phoenix support is post-v0.3.0; no normal saved-Home flight promise. |
| Both trucks | [Vehicle roster](../../../app/app_state/vehicle_roster.gd), [nitro truck guide](../../../research/rc-monster-truck/monster-car-2/README.md) | Bisonte electric, MONSTER CAR 2 nitro; complete landings and distinguishable bodies/sounds. No reverse for MONSTER CAR 2; no normal car-race feature claim. |
| Capture quality / final release | [Retained capture study](windows-rtx3090-capture.md) | 1080p60 first, highest supported stable settings on selected host; offline 60 fps output is not real-time performance evidence. Final build, URL, product status and rights require rechecking. |

## Stage A — screenplay review now

**A1 — Narrative and coverage.** Current screenplay is R3, with all 13 configurations mapped to meaningful actions. The required Corsair orbit survives, lake gets its hold, grounded mechanisms and collective are present, and the Creator trial ends successfully.

**A2 — Timing and text.** Current paper cut is exactly 90 s / 5,400 intended frames at 60 fps. Budget: 65.5 G, 5.5 U, 14 P, 5 E. One shared two-second reserve exists in R3-31; spend it once and recalculate all affected times/classes. Names, disclosures and HUD share the reading budget. No measured media duration is claimed.

**A3 — Source truth and document agreement.** Use code/configuration as implementation evidence; use the old film report only for its historical scope. README, script, storyboard, mechanics sheet, treatment, bible and these gates agree on R3. The [audit](script-audit-r3-2026-11-21.md) records completed checks and remaining limits.

**A4 — Visual story review.** A later actual storyboard/animatic must test whether an unfamiliar viewer can recognize the opening action, understand a gate passage, distinguish the two Stick configurations, read the mechanisms and follow the final invitation. This is pending; a source audit is not a mute/phone playback test.

## Stage B — tools after the screenplay

Select the exact promoted build, approved source assets and actual shot priorities first. Then compare the existing capture/editing routes against those needs. The [Windows study](windows-rtx3090-capture.md) and [music research](research-music-and-trailers.md) are retained input, not current tool or soundtrack selections.

No new video package, model API, paid generation, renderer change or game modification is implied by reading the nine skills or by this document. User authorization already covers preparing this working script and supporting branch documents; it does not require another approval request to complete them.

## Stage C — proof takes and production later

| Gate | Future work | Pass evidence and honest fallback |
| --- | --- | --- |
| C1 | Ground mechanism readability | Actual full takes and chosen native-speed excerpts; fixed references visible, correct ground interlocks. Extend tail details if needed. |
| C2 | Collective close-up | New stopped-rotor collective take with both blade roots/swashes visible and inspection identification; separate playable X-Cell take. Old cyclic footage is insufficient. |
| C3 | Orbit / lake signature | Smooth orbit across all 13 current stock schemes, subject to individual qualification and explicit recording of any reduced coverage, final skin held in lake shot with actual matching moving reflection. If mirror fails, retain orbit and honest unmirrored Corsair lake; no fake reflection. |
| C4 | Action / fleet | All 13 recognizable across finished cut, real inverted-or-banked jet, valid gate clearance and both complete truck landings. |
| C5 | Scale and light | Supported baseline trial configurations, same-depth labelled trio, actual smoke profile and readable night body. |
| C6 | Creator / contact | Same eligible imported model goes preview to trial; separate actual FPV contact produces its claimed non-blood lens effect. |
| C7 | Score and source sound | Actual audition, measured cue map and licences; engines recognizable, no clipped mix or stationary-inspector flight-rotor mismatch. |
| C8 | Finished edit and delivery | Full-motion mute/phone/headphone review, native frame/dimension/colour/audio checks, complete decode, exact final duration, readable copy and rights. All currently pending. |
| C9 | Public invitation | Verified destination and exact promoted build/status; English/Spanish copy and any derivatives. Publication is a separate later action. |

## Shot priority and deferred coverage

First resolve the new mechanics/collective, the preserved orbit/lake and the actual sequence readability. Then qualify gates, scale, Creator, lights, trucks and contact at the selected build. Do not make person-strike blood or a five-plane formation a prerequisite for this master: they are absent from R3.

The separate 32-second mechanical idea preserves fuller tailhook, taxi, propeller and airborne gear coverage. A detailed named/custom-livery catalogue, additional weather, settings, import formats and detailed training functions can have their own follow-up pieces rather than unreadable inserts in this acquisition trailer.

## Evidence receipt

Future takes record build/engine/host, actual settings, vehicle/skin, camera, source class, real contact/race state, media/audio identities and visual result. Use the [shot identity record](shot-bible.md#future-per-shot-identity-record). Mark unsupported, not examined and failed explicitly; a planned fallback is not a successful take.
