# Trailer feature opportunities from the code

**Reviewed:** 21 November 2026. **Track / owner:** V2 / trailer director-editor.
**Source baseline:** `57abea025f62b20233ca281d58d2acbee4ab8b8e`.
**Status:** source-backed shot proposals. [R3](cinematic-script-r3.md) and its [storyboard](storyboard-90s.md) remain the current 90-second cut; this document owns the additional candidates and their timing tradeoffs.

The strongest opportunities are **live transmitter inputs**, **the Bisonte entering shallow water**, and **MoonRunner's actual hand-launch release**. Wind, birds and moonlight can improve existing compositions. Turtle recovery provides a particularly clear miniature story, but needs a longer beat.

This review followed player controls into their runtime consumers. It establishes implemented paths, not the appearance, handling quality or readability of an unrecorded take. The source baseline may contain features beyond the eventual promoted release. Recheck selected features against that build before filming.

## Recommended changes to consider first

| Priority | Candidate | Proposed placement | Runtime and coverage consequence |
| --- | --- | --- | --- |
| High | Live stick input and aircraft response | Rework R3-18…20, 00:38.5–00:43.5 | Keep five seconds: one clean second, then four seconds with a stable transmitter display and a few genuine flight values. Move the separate Cockpit-preset demonstration to a follow-up. This is an explicit change from R3's two-preset coverage. |
| High | Bisonte shallow-shore pass | Alternate for R3-30, 01:18.5–01:23 | Use the existing 4.5 seconds. MONSTER CAR 2 retains the opening jump; Bisonte demonstrates another activity. Its own jump/landing leaves this alternate master. |
| High | MoonRunner hand-launch release | Enrich R3-04, 00:08.5–00:11 | Same 2.5 seconds, beginning at the real release and following the initial climb. No visible throwing person is established. |
| High | Wind and moonlit field | Compose within existing ground/flight shots and R3-22 | No added cuts. Keep the featured vehicle and its movement dominant. |
| Conditional | Storm flash behind a flying wing | Alternate composition for R3-04 | Same 2.5 seconds if a real flash and readable aircraft occur together. Choose this or the launch emphasis; avoid asking the shot to prove both. |
| Companion / longer cut | FPV turtle recovery | A separate recovery sequence | Allow roughly 6–8 seconds on paper for tip-over, righting and return to flight. R3-09 has only 1.5 seconds; its two-second shared reserve cannot fund this alone. |

These are proposed substitutions and framing choices. Preserve the Corsair orbit, all its requested stock skins, the six-second lake hold, the mechanical chapter and the five-second invitation. If a candidate is adopted, update the screenplay, storyboard and coverage ledger together. The two substitutions above keep the master length and source-class totals unchanged because both replace session footage with session footage.

## 1. Make the player's input visible

**Implemented path.** During an ordinary airplane flight, Pause → Session options → Flight overlays exposes the transmitter display. It follows live roll, pitch, yaw, throttle and trims, with Mode 1/Mode 2 layouts. The artwork can be selected independently as JETI DS-24 II or Radiolink T16D. Controls also provides radio, gamepad and joystick profiles; a radio needs an appropriate saved/calibrated profile.

**Shot.** Keep a Mustang large in an external view. The displayed roll input moves; the aircraft enters a clear bank in the same take. Hold that relationship for four seconds. A stable layout with a few useful values is more legible than asking the viewer to inspect several changing dashboards.

**Why it earns time.** It connects the grounded mechanisms to what a player actually does. For RC pilots, the control relationship is a more concrete invitation than an additional instrument close-up.

**Limits.** The default Player preset does not include the transmitter; enable it explicitly. Selecting a radio picture does not identify the connected physical device. A claim or caption about flying with a compatible RC transmitter needs a take driven by that actual calibrated device. The overlay also displays inputs from other supported control routes. Preserve the real response and do not animate a replacement stick over unrelated flight.

**Source:** [pause entry](../../../app/ui/pause_menu.gd), [overlay controls](../../../app/ui/overlays_dialog.gd), [live input snapshot and refresh](../../../app/render/overlays/overlay_manager.gd), [gimbal drawing](../../../app/render/overlays/transmitter.gd), [preset contents](../../../app/render/overlays/overlay_settings.gd), [controller setup](../../../app/ui/controller_setup.gd).

## 2. Give Bisonte a different relationship with the lake

**Implemented path.** Home → Bisonte MT8 → Drive opens its garage. Free drive → Start location → **Lake · Shallow shore** uses the normal driving session. The shore choice appears only when the matching Club field, default scenery/lake and staging checks are available. Selecting a new location after driving requires the offered restart.

Moving tires at the waterline can produce modest droplets, per-wheel ripple rings and splash audio. Mud contact can produce clods; separate visual effects add wet sheen and grime. The ground scene drives these effects from vehicle telemetry. The underlying model also includes estimated buoyancy, water drag and wheel-spin drag, and changes surface friction/rolling resistance in mud.

**Shot.** Begin with Bisonte already rolling. A close, low three-quarter view follows its front tires off the muddy bank into shallow water, then keeps the wheel contact readable. Let the actual electric motor, tires and splash supply the sound. A different supported truck skin adds the requested paint variety.

**Editorial recommendation.** This is the strongest alternative to Bisonte's second jump. Using its existing 4.5-second slot keeps both trucks and gives each a distinct action. The earlier Corsair pass makes the lake a flight setting; the Bisonte shows that the shore is also a place to drive.

**Limits.** The spawn checks a dry staging sample and one entry sample below 0.2 m; it does not certify an entire crossing. Choose and prove a short shallow route. The source describes an estimated open-truck displacement model. Rendered waves do not drive the water physics. Large splashes, deep-water traversability and lens spray are not guaranteed. The rings and droplets may require a closer composition than the current jump shot.

**Source:** [garage choices](../../../app/vehicles/ground/ground_dashboard.gd), [normal scene and effects](../../../app/vehicles/ground/ground_scene.gd), [shore checks and muddy surface](../../../app/physics/ground_vehicle/airfield_course.gd), [wet visuals and sound](../../../app/vehicles/ground/ground_wet_effects.gd), [wet sheen/grime](../../../app/vehicles/ground/ground_effects.gd), [estimated water loads](../../../app/physics/ground_vehicle/vehicle_environment.gd), [loads applied to dynamics](../../../app/physics/ground_vehicle/vehicle_dynamics.gd).

## 3. Start MoonRunner from its actual release

**Implemented path.** Home offers **Start: hand launch** for supported airplanes without landing gear. The flight session installs a low, powered release state and then advances actual flight. The authored release is 1.9 m above the sampled terrain, at 6.5 m/s with a slight climb angle and full throttle.

**Shot.** A close low external view catches the flying wing immediately after release and follows its first climbing bank. It gives the existing 2.5-second silhouette shot a recognizable starting action.

**Limits.** The implementation initializes the aircraft at release; it does not establish a visible hand, person or throwing animation. The particular aircraft, starting camera and climb still need a readable real take. Keep the native flight speed.

**Source:** [Home start choice](../../../app/ui/home.gd), [release construction and accepted reset](../../../app/sim/flight_session.gd).

## 4. Make the existing field feel alive

| Detail | Existing feature and route | Useful composition | Qualification |
| --- | --- | --- | --- |
| Windsock and foliage | Conditions → Wind & Gusts; the session's sampled wind advances the sock, Club grass and eligible trees. | Put the sock in the foreground of an existing runway/pass shot while keeping the aircraft clear. | Use nonzero wind. Supported tree assets and graphics choices matter; subtle motion must read in the actual framing. |
| Moon, stars and runway lights | Home time choices include Evening, Moonrise and night; world lighting and the sky follow the selected time. | Enrich the existing Turbo Lumber night/blue-hour pass with a moon or lit runway. | Preserve the aircraft's real light pattern. Cloud, exposure and framing determine visibility. |
| Birds | Settings → Graphics → Birds selects density; the Club scenery builds animated bird circuits. | Let a real flock add depth to the blimp's three-second pass. | Species/activity depend on time and conditions. Do not add a cut just to show an unreadable distant bird. |
| Club people | The field populates pilots and spectators; supported quality levels advance head tracking toward aircraft. | Include the flight line in the background of a ground or low-pass shot. | Balanced/high scenery is needed for gaze; low quality remains static. This is head motion, not full-body character animation. |
| Campfire | Time-of-day controls can enable a Club-field fire with flames, embers and local light. | Optional warm foreground in the existing night composition. | It must be enabled and must not obscure the vehicle. Current fire has no smoke. |

Evening and Moonrise flow at 20×; the source describes minutes of flight for the transition. A full sunset in a few trailer seconds would be an editorial time-lapse. The enlarged moon option is explicitly labelled cinematic; keep any depiction consistent with the chosen setting. Use only the details that fit the composition.

**Source:** [live field wind and people updates](../../../app/main.gd), [windsock response](../../../app/render/windsock_motion.gd), [Club grass wind](../../../app/scenery/imported_grass.gdshader), [eligible tree wind](../../../app/scenery/imported_tree_wind.gdshaderinc), [time choices and flow](../../../app/render/world/conditions.gd), [world/field lighting](../../../app/render/world/world.gd), [night options](../../../app/ui/time_of_day_controls.gd), [birds](../../../app/scenery/birds.gd), [gaze](../../../app/scenery/people_gaze.gd), [fire](../../../app/render/world/campfire.gd).

## 5. Capture an actual storm event

**Implemented path.** Conditions → Sky & clouds includes Electrical Storm. The airplane runtime presents a distant storm bank, rain curtains and seeded cloud flashes; some events can draw a cloud-to-ground bolt when Full flashes are selected.

**Shot.** An aircraft remains large and recognizable against a cloud bank that genuinely flashes. The MoonRunner's current 2.5-second bank is a candidate alternate to its launch emphasis. Keep R3's rule that atmosphere supports a vehicle.

**Limits.** A flash is not guaranteed within any given 2.5 seconds: the schedule can skip slots, and only some events produce a visible bolt. Select the actual recorded event. This is a distant presentation system, not evidence of traversable clouds or rain aerodynamics. The traced integration is ordinary airplane flight; it does not establish the same storm route for helicopters or Natural Random.

An airplane chase/orbit shot can also use the optional rain-on-lens system. This is a lower-priority alternative, since drops can hide the aircraft. Pilot view does not show glass beads by default; scripted/capture paths have additional enablement rules, and storm audio may be disabled there. Those are later capture requirements, not new tool selections.

**Source:** [sky choices](../../../app/ui/sky_controls.gd), [runtime](../../../app/main.gd), [storm bank](../../../app/render/weather/storm_bank.gd), [seeded event schedule](../../../app/environment/storm_events.gd), [flash/bolt consumer](../../../app/render/weather/lightning.gd), [visual rain mapping](../../../app/render/lens/rain_model.gd), [lens rendering](../../../app/render/lens/lens_stack.gd).

## 6. Turn an FPV mistake into a recovery story

**Implemented path.** The playable quad offers graded impacts and a stricter crash setting. Select graded mode and restart on the pad before recording this take. After a survivable tip-over, the player can disarm, request **Turtle mode**, arm with a fresh OFF-to-ON transition at low throttle and push the stick toward the desired flip. Selected motors run in reverse. The player then disarms and rearms for normal flight.

**Shot.** One clearly separate attempt: a small tip-over, a grounded exterior view of the quad righting itself, then a clean lift-off. A brief real mode indicator helps identify the action. Sound moves from the impact pause to the short recovery motor burst and normal flight.

**Why it earns attention.** It has a beginning, setback and payoff. It also communicates something useful to FPV pilots without another menu tour.

**Limits and time.** Terminal crashes and depleted packs require a reset; this does not repair damaged props. Keep a real survivable case. Allow roughly 6–8 seconds as an initial edit target, with control-state changes omitted honestly between shots where needed. This does not fit R3-09's 1.5 seconds, even with its entire shared two-second reserve. Recommend a short companion film or an explicitly retimed longer cut.

**Source:** [crash setting and restart](../../../app/vehicles/multirotor/multirotor_scene.gd), [player instructions](../../../app/vehicles/multirotor/multirotor_hud.gd), [mode input](../../../app/input/multirotor_input.gd), [arming and reverse-motor commands](../../../app/physics/multirotor/flight_controller.gd), [graded contact/damage](../../../app/physics/multirotor/controlled_plant.gd).

## 7. Show learning and experimentation in follow-ups

These features have genuine player value but need enough time for a cause and its consequence.

| Feature | Implemented behavior | Proposed sequence | Scope / source |
| --- | --- | --- | --- |
| Angle and Acro FPV | Player-selectable attitude assistance in Angle and rate commands in Acro; the live OSD identifies the mode. | A readable bank/release in Angle, then a real Acro roll, approximately 4–5 seconds on paper. | Replacing the existing gate passage would lose racing clarity. Preserve mode labels in actual footage and use the comparison in an FPV follow-up. [Input](../../../app/input/multirotor_input.gd), [controller](../../../app/physics/multirotor/flight_controller.gd), [OSD](../../../app/vehicles/multirotor/multirotor_hud.gd). |
| Engine-out failure practice | Home → Practice → Failure practice can inject one eligible failure in an ordinary airplane flight. | Engine sound stops; an identified failure leads to a genuine glide and landing. Allow a longer sequence, initially 6–10 seconds of selected excerpts. | For filming, leave only an eligible engine-stop or motor-power-loss type checked, set 100% probability and Early onset, then start a new flight from Home. The event still waits for eligible airborne time. Training injection, not a claim about real failure rates. [Menu](../../../app/ui/failures_menu.gd), [catalog](../../../app/failures/catalog.gd), [session](../../../app/sim/flight_session.gd). |
| Ground Physics Lab | The garage can change gravity, grip, springs, damping, ballast mass and ballast height, then apply an experiment. | Same bumps, same angle, two actual suspension settings; allow roughly 6–8 seconds for a comparison. | Applying the settings prepares/restarts a paused session; it is not an in-air live slider. Parameters are estimated. [Dashboard](../../../app/vehicles/ground/ground_dashboard.gd), [model changes](../../../app/physics/ground_vehicle/vehicle_data.gd), [session admission](../../../app/sim/ground_vehicle/session.gd). |
| Airplane touch-and-go | The statistics detector distinguishes a qualified touch-and-go from a bounce and records it. | Low side view of touchdown followed by climb; inspect the actual recorded result before calling it a success. | Default classification needs 0.5 s of qualified support followed by 2 s airborne. No dedicated landing-challenge mode is implied. [Rules](../../../app/statistics/rules.gd), [detector](../../../app/statistics/detector.gd), [statistics screen](../../../app/ui/statistics_screen.gd). |

## 8. Other useful discoveries to retain

**AI companions.** The Flight companions dialog can enable one to three autonomous Ugly Stiks flying circuits. Their sessions receive pilot commands, render controls and play engine sound. A 3–5-second player pass with distant circuit traffic could make Club field feel populated. Current restrictions include ordinary fixed-wing flight, Club field, a qualified engine/profile and calm or tightly bounded mild weather; use calm for a future proof take. They do not provide multiplayer, close formation, aerobatics, runway operations or aircraft-to-aircraft contact. Their circuit distance may make them too small in a hero shot. [Dialog](../../../app/ui/companions_dialog.gd), [launch admission](../../../app/ai/companions/manager.gd), [active agents](../../../app/ai/companions/agent.gd), [circuits](../../../app/ai/companions/circuit_controller.gd).

**Imported scenery.** This is separate from R3's imported-aircraft trial. Home → Import scenery can install a Phoenix panorama preview. An exact matching calibration exposes **Fly calibrated runway** for an eligible airplane. A labelled 2–3-second pilot-eye pass could demonstrate it in a longer feature piece. The route uses six photographs around a fixed eye, calm physical weather and estimated ground/contact; it is not a freely explored 3D recreation. Other imported revisions remain previews. Select a source with suitable rights and promoted-build support before filming. The built-in Green paradise is also playable, but its open flat grass offers less visual contrast. [Importer](../../../app/ui/landscape_import.gd), [revision/calibration verification](../../../app/landscapes/phoenix_library.gd), [flight route](../../../app/app_root.gd), [panorama rendering](../../../app/landscapes/phoenix_flight.gd), [landscape catalog](../../../app/landscapes/catalog.gd).

**Natural Random.** The player can review a seeded aircraft/weather/daylight briefing, draw another flight and fly the selected setup. It is limited to its Club-field stock-airplane/daylight pool and airborne starts. Useful for a practice explainer, but the briefing needs reading time. [Screen](../../../app/ui/natural_random_screen.gd), [generator](../../../app/scenarios/natural_random.gd), [scope](../../../app/scenarios/scenario_config.gd).

**Finite energy and aftermath.** Supported aircraft expose fuel fill or finite battery behavior; the latter is marked experimental. Fixed-wing accidents can also lead to cosmetic wreck inspection and an estimated damage report. These offer training depth, but fuel depletion needs real elapsed flight and wreck inspection would require a separate fixed-wing incident, competing with R3's existing single-impact beat. Reserve them for focused demonstrations. [Flight details](../../../app/ui/home.gd), [fuel behavior](../../../app/physics/glow/flight.gd), [fuel instrument](../../../app/render/overlays/fuel_instrument.gd), [accident report](../../../app/ui/accident_report.gd).

## Acceptance and next action

| Step | Work | Proof / status |
| --- | --- | --- |
| V2-FEATURE-01 | Inspect player-facing source paths for omissions in R3 | Complete as source review at the baseline above; source links accompany each candidate. |
| V2-FEATURE-02 | Choose substitutions and synchronize the current screenplay | Pending creative selection and readable proof material. Preferred candidates: transmitter, Bisonte shore and MoonRunner release. |
| V2-FEATURE-03 | Qualify selected shots on the promoted build | Pending real footage; use the existing [verification gates](verification-gates.md). |

For each chosen take, retain the actual vehicle, skin, field, settings and player route. Require one understandable action, readable framing at the intended output size, and sound from the demonstrated behavior. Review any disclosure in the same frame as the feature it qualifies. Preserve the [skin and continuity ledger](shot-bible.md#skin-and-continuity-ledger).

This pass changed planning documentation only. It did not launch the game, capture footage, measure hardware or validate handling. The source review therefore supplies candidates for the screenplay, with visual acceptance still open.
