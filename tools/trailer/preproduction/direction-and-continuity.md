# R7 — Direction, screen continuity and lighting

**Date:** 22 November 2026. **Track:** V2. **Authority:** the [R7 shot plan](shot-plan-r7.json) owns numeric blocking and the cut order; the [shooting script](cinematic-script-r7.md) owns the film's intent. This sheet explains the decisions and capture boundaries. All new compositions are proposed until actual takes are reviewed. The [R7 audit](script-audit-r7-2026-11-22.md) records the checks actually performed.

## 1. The film's argument

Give a new player a reason to care before asking them to read. Start with a close, legible jet already in flight, then show the range of play through a truck landing, electric airplane, launch and blimp. The race section has an objective and a resolved recovery. The next two chapters make the machines tangible: a labelled rotor inspection, a separate flying helicopter, then the grounded Corsair's visible mechanisms. A real control input leads to a real response and a completed practice landing.

Tuning and scale now precede the landscape and beauty passage. They turn curiosity into experimentation before the film settles into its signature: the full thirteen-skin Corsair orbit, the uninterrupted lake pass and a sunset shore approach. Creator opens another chapter; its last preview becomes one eligible trial of the same model. A clearly identified stock Turbo Lumber at night supplies the final flight image. Hold the invitation for five seconds.

This is an anthology of play sessions. It does not depict one aircraft journey or a continuous simulated day. The shot-to-shot cuts, captions and UI establish changes of session, vehicle and source class.

## 2. Entrances, exits and direction

Every R7 shot has `screen_direction`, `axis_note`, `cut_to` and `cut_kind`. These are directing instructions, not claims about recorded footage. An eastbound aircraft can face either side of the screen depending on the camera's side. A tracking camera can hold it almost stationary in the frame. Do not confuse **world travel**, **projected nose direction** and **screen translation**.

| Passage | Entrance and exit | Camera / cut decision |
| --- | --- | --- |
| Vantage, 0–4 s | Enter the edit already in a readable genuine inverted pass; a real banked pass is the declared rehearsal alternate. Nominal N15, E−58→+58, D−8. Cut at the world exit mark while the aircraft remains visible. | Parallel eye N6, D−6.5, E=actual CG east−6; vertical FOV 32°. It stays south of the eastbound aircraft, giving a nose-right silhouette. Upright horizon; no opening text. |
| MONSTER CAR 2, 4–8 s | Approach, departure, apex, actual touchdown and suspension compression must form a complete event. | South-side view continues the dominant nose-right energy. Do not cut away before landing simply to preserve a beat. Ground support comes from the real solver. |
| Electric Stick, 8–11 s | Nominal N18, E−22.5→+22.5, D−4. Establish the actual electric variant and alternate paint. | Parallel eye N10, D−2.5, E=CG east−6; FOV 34°. Retain full silhouette and field context; a world exit is a cut point, not an offscreen exit. |
| Race, 18–39 s | Establish the gate, clear it, show the two modes, then a separate recoverable impact and its real righting/rearm outcome. | FPV-to-exterior establishes a new view; it does not silently claim a continuous camera switch. Recovery excerpts retain the same actual attempt and genuine state indicators. |
| Rotor to Corsair, 39–59 s | Four-second stopped HX-700 mechanism inspection; separate four-second X-Cell hover-to-forward flight; then six grounded Corsair mechanism cuts. | Fixed references make mechanical movement readable. Clear aircraft labels prevent the inspector from being mistaken for the playable helicopter. End the Corsair passage with a settled canopy view before the Mustang's clean exterior. |
| Input and practice, 59–73 s | Establish the P-51, show input and bank in one take, then a separate configured failure, glide and resolved landing. | R4-22→23 is the same take. R4-24…26 is the same practice attempt with honest omissions; source timestamps will document the ellipses. |
| Lab and scale, 73–89 s | Baseline suspension response, actual setting application, matched changed run; then scale UI, giant trial, tiny trial and disclosed comparator. | Match Lab position/input/camera and change one declared parameter. Tiny trial uses its own closer camera: N28.5, D−1.2, E=CG east−1, FOV 24°. Only the comparator promises equal depth and direct apparent-size comparison. |
| World, 89–105 s | AI companions, separate calibrated panorama, separate storm, then a readable afternoon Extra bank with admitted smoke. | These are distinct contexts. The photo panorama keeps its calibrated pilot eye. Match subject size and eye trace where possible; never mirror controls, markings or a scene to hide an axis change. |
| Corsair orbit→lake, 105–121 s | Orbit ends in Coastal Three Tone with clean gear, flaps and hook; the lake retains the same paint and frozen golden setting. | The continuous orbit visibly crosses the axis. Its final front-left view gives a nose-left image; the lake's north-bank camera keeps that orientation. This is an edited visual match, not proof of a continuous world path. |
| Lake→Bisonte, 121 s | Finish the six-second lake take, then enter a separately prepared shallow-shore approach from N145.5/E125 toward N138/E125. | Water surface, shoreline color and low camera motivate the cut. Vehicle, direction and time change openly. Stop the truck in the qualified shallow region; do not infer safe depth from a plan-view dot. |
| Preview→trial, 138 s | Last accepted ClearView model becomes the exact same admitted draft/texture set in its real trial. | Keep nose-right in both. Proposed flight eye is rear-right FRU(−7,+4,+2), FOV 40°, resized to the admitted model's bounds. The previous negative-right offset would reverse the nose. No image mirroring. |
| Trial→night→invitation, 141–150 s | Finish the trial in daylight; hard-cut to stock Turbo Lumber with the full 141–145 s identity label, then the settled end card. | A new session is explicit. Use the actual Lumber director's root-relative right-side camera, not a fictitious generic chase. The body must remain readable alongside its lights. |

At rehearsal, inspect first, midpoint and final retained frame **and the intervening motion**. Preserve the focal point across a cut unless a deliberate reset is useful. Aircraft, transmitter, controls, genuine warnings and qualifiers share one visual budget. If the necessary evidence cannot be read, simplify the composition or revise the whole affected interval; do not accelerate simulation to squeeze it in.

## 3. The lighting script and the source API

The source's two time interfaces are different. This production plan uses field-world presets from [`conditions.gd`](../../../app/render/world/conditions.gd), consumed by [`world.gd`](../../../app/render/world/world.gd). They use underscore arguments such as `--time_of_day=golden_hour`. The separate astronomical configuration in [`time_of_day_config.gd`](../../../app/environment/time_of_day_config.gd) uses `--time-of-day=HH:MM[:SS]`. Do not swap one spelling for the other or treat a preset word as a clock time.

| Source state | Implemented meaning | R7 use |
| --- | --- | --- |
| Legacy Day | Fixed sun azimuth 225° / elevation 45° in [`spec.gd`](../../../app/spec.gd); **not** a `PRESETS.day` entry. | Stable reference daylight for mechanics, race, practice and comparisons. Use Home Day or a fresh direct process with empty `session_preset` and explicit `--time= --time_of_day= --time_scale=0`. `--time_of_day=day` is not the correct direct-preset command. |
| `dawn` / `sunrise` | Rising solar elevation −4° / +1°. | Available alternates, not extra mandatory shots. Dawn is deliberately not the opening default because the first airplane must read immediately. |
| `morning` | Rising solar elevation +25°. | Opening five cuts, 0–18 s. Valid direct preset, although it is not a choice in the Home cycling list. |
| `noon` / `afternoon` | Daily highest sun / setting elevation +35°. | Afternoon for the Extra at 101–105 s. `afternoon` is direct-preset functionality, not a promised Home menu item. |
| `golden_hour` | Setting solar elevation +6°. | Both Corsair signature takes, 105–121 s. Same environment, wind and exposure qualification. |
| `sunset` | Setting solar elevation +0.5°. | Bisonte shore, 121–126 s, as a separate session. |
| `blue_hour` | Setting solar elevation −4°. | Declared alternate for the final flight if the night body is unreadable. Record the substitution; do not label blue-hour footage as full night. |
| `night` | Moon-view night selection; the resolved date/phase are part of its identity. | Turbo Lumber, 141–145 s, with admitted `night_radian` aircraft lighting. |
| `night_dark`, `moonrise`, `moonrise_golden` | Dark-new-moon or moonrise variants. | Available for companion work, not required in this master. A bright moon must not be pasted into a take to imply an unavailable recorded view. |

The reference preset calculation uses 21 June 2026, latitude 40°N, longitude −3.7°, UTC+2 unless a preset resolves another date. These are source defaults, not the user's local time. The `night` search targets at least 97% illuminated moon near its selected date, not an exact 100% promise. Record actual resolved conditions, date and phase. A forced moon phase can change the final date; the earlier conditions manifest alone may not tell the whole story.

All matched R7 Club-field environments set `--time_scale=0`. This freezes the sky clock. **Exposure still adapts** in the world update; allow it to settle and record its actual output before comparing takes. Do not assert a fixed exposure merely because the sun stopped moving. Home's `evening` and moving moonrise choices advance time at 20× and unfold over minutes; they are not instantaneous four-second sunrise transitions.

The JSON contains exact `field_world_args` for each environment. Every set starts with `--time=`: an inherited `OPENRC_TIME` clock otherwise overrides even an explicit named preset. Fixed Day also uses `--time_of_day=` and requires a fresh direct session with empty `session_preset`. Clear `OPENRC_DATE`, `OPENRC_LAT`, `OPENRC_LON` and `OPENRC_UTC_OFFSET` to retain the source reference date/place, or record intentional alternatives. These are field-world arguments, not a promise that every capture harness accepts them. These flags alone do not establish physical wind, model paint, spawn, lighting profile or GPU configuration. Apply each through its owning path and read back the result. Decimal clock-hour values such as 21:51→21.85 must not be entered as 21.51.

### Sky, weather and field detail

[`sky_appearance_config.gd`](../../../app/environment/sky_appearance_config.gd) provides the actual sky preset names, seed and appearance controls. Physical wind and the sky's visual motion remain separate systems. For this master, use `clear` for calm chapters and `electrical_storm` for the four-second storm excerpt. A seeded storm has roughly 12-second event slots and can omit a slot; record a longer real flight and select a readable actual flash. Most flashes can be intracloud; a visible bolt is conditional on the recorded event.

The current `capture_flight.gd` harness forwards selected sky options, but not every direct-app cloud seed, cloud motion, wind-aloft or storm-flash flag. Adding an unsupported argument to a command does not prove that Main received it. Similarly, Main's supplied defaults can override process-level campfire requests in this harness. Use a qualified route with actual readback before showing those details. Birds, grass, windsocks, people looking at the aircraft, field lamps and campfire can enrich an otherwise readable composition; they do not each earn another master cut.

The calibrated Phoenix panorama is a separate source with baked photographic illumination and a fixed eye. Do not animate the photo sky or move the camera as though it were the Club field. Neutral Creator UI separates the sunset shore from the subsequent daylight imported trial, so that reset is intentional.

## 4. The lake must frame a real aircraft and a real reflection

The source mean-water plane is NED D+0.45. The nominal Corsair CG is D−2.55, three metres above that plane. The proposed six-second corridor is N128, E55→193 at 23 m/s; the pinned shoreline intersects that line at approximately E88.73 and E162.91. Only about 74.18 m / 3.23 s of that nominal route is over water. The edit contains approach, crossing and exit; it does not promise six seconds entirely above the lake.

The R7 camera follows east eight metres behind the **actual presented CG**, with eye N145/D−1 and vertical FOV 34°. Its aim has the CG's north/east position projected onto the mean-water plane. This balances the airplane above the aim and its mirror below it. The recipe's `water_down_m` is checked against the pinned lake data; both actual CG and aim are recorded separately. That change moves a camera only. It does not constrain the aircraft or manufacture reflection.

The default lake cubemap excludes moving aircraft. A matching moving-aircraft mirror requires `OPENRC_LAKE_REFLECTIONS=planar`, active High graphics, a **non-headless Forward+ renderer**, a visible water surface and the renderer's admitted camera/height/projection conditions. Compatibility is useful for some software checks but cannot qualify this mirror. Inspect the same livery, pose and frame in the actual reflection; retain water clearance, clean configuration and readable bank. An unmirrored genuine lake take is an honest fallback, not evidence of the mirror feature. Sources: [lake data](../../../app/data/fields/lake.json), [planar implementation](../../../app/render/lake/lake_planar_reflection.gd), [reflection selection](../../../app/render/lake/lake_reflection.gd), [High profile](../../../app/render/high_graphics_profile.gd).

An inherited low-sun caveat remains: [`sun_glare.gd`](../../../app/render/landscape_upgrade/sun_glare.gd) updates at ordinary process priority before the trailer directors. Planar reflection runs later. Glare or afterimage state may therefore use the earlier native camera. Review real golden/sunset captures for this; R7 does not change the game's glare implementation or claim a rendered fix.

## 5. Camera implementation and evidence

The [camera adapter](../planned_camera.gd) supports `fixed_world` and `parallel_east` for admitted stock fixed-wing Club-field G-class takes. R7 adds `presented_cg_water_plane` while retaining `presented_cg` recipes. `Camera3D.KEEP_HEIGHT` makes the recipe's FOV explicitly vertical. Projection, optical offsets, eye, rotation, aim and FOV are checked against the live camera. Camera processing follows Main and the existing director; it does not replace the pilot director.

Every successful camera application records the actual engine process frame and, in capture, the current simulation tick. The post-draw guard requires the camera, live session and director record to agree. A stationary CG is not permission to reuse an earlier frame's evidence. Read the audit for tested scope; a source contract is not proof of a finished take.

| Route | What it supplies | What is still separate |
| --- | --- | --- |
| Camera recipe | Presentation eye, aim and vertical FOV; exact plan-byte hash and per-frame evidence. | Skin, scale, initial conditions, real trajectory, terrain/water clearance, exposure, renderer and sound. |
| Corsair orbit director | Existing seven-metre eased orbit about the **visual model root**, thirteen-livery schedule and final hold. | Exact retained source window, admitted presentation classification and actual orbit-to-lake visual match. |
| Lumber dusk director | Existing root-relative FRU eye: forward 5.4→4.5, right 2.2→1.8, up 0.1; look 0.4 above root, FOV 33°. | Its source-clock phase, real night body readability and admitted Workshop lighting. `night_radian` is customization, not factory paint. |
| Ground / rotor / Creator / panorama routes | Their own real session, inspector, UI or calibrated view. | They do not become supported airplane recipe routes merely because a shot card contains proposed coordinates. The existing vehicle capture is four seconds; the five-second shore shot needs a qualified manual or adapted route. The strict `capture_car_jump.gd` harness rejects time/sky arguments and uses classic sky with a 46° orbit; the R4-02 morning/clear/42° composition requires manual or adapted capture. The R4-37 scale trial has a `workshop-<hash>` model identity and is refused by the stock recipe guard; its close camera is proposed, not an admitted combined route. |

No photographic focal length is inferred from Godot FOV without a sensor convention. No moving cockpit stick or pedals are promised by the fixed-wing `Cockpit` widget preset. Keep the grounded Corsair's supported surfaces, wing fold, flaps and canopy as the actual mechanism proof.

## 6. Text, sound and what stays outside the master

The only main-copy lines remain **A SKY WITHIN REACH**, **FEEL EVERY INPUT** and **EXPAND YOUR HANGAR**. Functional captions are 52 px at 1080p in the R7 plan; their 48–56 px acceptance range is a software constraint, not a phone-legibility certificate. The lake has no added text. Keep the two provider captions continuously visible across their nine previews each. The final trial's actual estimated/donor basis must be bound before publication, and **TURBO LUMBER** identifies the following stock night take.

The [zoom-through-text study](research-text-window-transition-2026-11-22.md) remains an optional title transition. It would consume footage and reading time if adopted. It has not replaced the direct gameplay opening or been added on top of the current 150-second edit. The unverified `300+` claim likewise remains inactive; source installation counts cannot be advertised as a deduplicated, accepted import catalog.

Use source sound to mark cause and effect: jet pass, actual truck contact, propeller, rotor, servos, power loss, landing and shallow-water contact. The HX-700 inspector must not borrow a flying-helicopter sound that changes its meaning. Keep rotor/engine energy below the point where it hides the music or mechanical detail. Let density ease during the orbit/lake; the import reel can accelerate the editing rhythm without speeding physics. Resolve the night sound into the invitation. No track, tempo, licensed master or audio mix is accepted by this sheet.

Extra cockpit layouts, repair economics, weather controls, field life, moon variations, additional mechanical views and deeper import explanations belong in the [90-second Field Notes and 32-second Preflight Ballet](feature-companion-films.md). The master already includes each reviewed Home roster/configuration entry. Add a feature only if it improves the film and a named interval is replaced; no hidden time reserve exists.

## 7. Required take record

For each accepted source, record build/tree identity; exact vehicle/configuration, paint/texture hashes and scale; source route and source frames/ticks; renderer/backend/host; output and internal 3D resolution; actual field/time/date/sky/wind/exposure; camera anchor/eye/aim/FOV and movement; genuine UI/qualification; start/middle/end contact sheet plus full-speed playback; clearances and actual outcome; audio channels and intended edit handle. A planned timecode never substitutes for a recorded source in/out.

The [verification gates](verification-gates.md) own acceptance. Keep failed or conditional takes explicitly classified. Rehearsal may change geometry; regenerate the dependent script cards, storyboard, recipes and title windows together when it does.
