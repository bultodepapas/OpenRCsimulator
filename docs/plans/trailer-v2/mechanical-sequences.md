# Trailer 2.0 — mechanisms that tell a story

**22 November 2026 · V2 · Screenplay support, not capture instructions**
**Current master:** [R7](cinematic-script-r7.md), 00:39–00:59; the [shot plan](shot-plan-r7.json) retains the R4-prefixed IDs. The [storyboard](storyboard-r7.md) owns edit boundaries and the [direction sheet](direction-and-continuity.md) owns cut-to-cut continuity. **Source reviewed:** game code at 57abea025f62b20233ca281d58d2acbee4ab8b8e. The first offline plan tools and opt-in livery hold-last have historical focused software evidence; no mechanism was newly rendered or filmed.

## Director's idea: let the mechanism explain itself

The viewer should see a fixed part, a moving part and the relationship between them. A blade root changing angle is more informative than a spinning rotor blur. Opposed ailerons need both wings in frame. Elevator and rudder need distinct angles. The canopy should slide against a visible cockpit rim. A partly moving wing must finish in a clear gull-wing silhouette.

Use one movement per insert, usually with a locked camera. The fast cut comes from changing the subject, not from speeding up the simulation. Record full movements later, then choose honest native-speed excerpts for the master. Avoid suggesting that a twelve-second montage is a complete real-time preflight procedure.

## What the current source actually supports

| Subject / movement | Where it exists | Filmable proposition and boundary | Evidence |
| --- | --- | --- | --- |
| Helicopter collective: swashplate, links, grips and main-blade pitch | **Separate articulated HX-700 inspector** | A stopped-rotor collective change can reveal both blade roots feathering together. Keep cyclic neutral. It is a mechanical presentation, not playable X-Cell flight. | [Articulated model](../../../app/aircraft/hx700_articulated_model.gd), [mechanism](../../../app/render/rotor/hx700_mechanism.gd), [inspection UI](../../../app/render/rotor/hx700_mechanics_view.gd). |
| Independent rotor rotation and blade visibility | **Inspector only for this articulated demonstration** | Phase and 0–12 rpm presentation speed are separate from collective. Main blades start hidden; make them visible for this shot. Prefer 0 rpm. Inspection smoothing is not a physical servo-response claim. | Inspection UI: control sliders, main-blade toggle and camera presets; [inspection motion](../../../app/render/rotor/hx700_inspection_motion.gd). |
| Collective on the playable helicopter | Input/telemetry exists; visible blade feathering is **absent from the legacy visual** | Do not call faster spin or whole-disc tilt a collective mechanism demonstration. The visual adapter explicitly has no blade-feather hinge. | [Playable rotor adapter](../../../app/render/rotor/heli_rotor_visual.gd), update; [helicopter session presentation](../../../app/helicopter_main.gd). |
| Playable helicopter flight | X-Cell .60 research trainer with older HX-700 visual | Show actual hover/forward movement, full silhouette and field landmark. The articulated HX-700 candidate is refused by the live flight session. | [Helicopter guide](../../HELICOPTER.md), [catalog](../../../app/app_state/aircraft_catalog.gd), [session admission](../../../app/sim/helicopter_flight_session.gd). |
| Corsair ailerons | Actual flight-session controls | Show opposite movement against fixed wings. Keep wing panels spread/locked. | [Model bindings](../../../app/data/aircraft_models/f4u-corsair-250.json), [surface mapping](../../../app/physics/control_surfaces.gd), [render pose](../../../app/main.gd). |
| Corsair elevator / rudder | Actual flight-session controls | Film separately so vertical pitch-control movement and lateral yaw-control movement are distinguishable. These are surface movements, not proof of cockpit stick/pedal animation. | Model bindings; [imported model control application](../../../app/aircraft/imported_model.gd). |
| Corsair flaps | Actual flight-session flap state | Three panels per side; the 30-degree maximum is sourced from the CARF manual. The approximately 2.5-second actuator travel is an authored estimate. Show a settled end pose; neither establishes a measured servo-response validation. | [Aircraft configuration](../../../app/data/aircraft/f4u_corsair_250.json), main render pose. |
| Corsair wing fold/spread | Playable presentation mechanism | Available while stopped on wheels; throttle held at idle until spread/locked. Authored full travel about eight seconds, first 12% releases locks, maximum fold 112 degrees. The three-second master insert is an excerpt. | [Ground interlock and mechanism update](../../../app/main.gd), [geometry](../../../assets/aircraft/f4u-corsair-250/model-geometry.json). |
| Corsair sliding canopy | Playable presentation mechanism | Real canopy travel, about 2.5 seconds and 0.1556 m in the authored geometry. Side view needs fixed cockpit rim. Interior appearance remains a visual-inspection question. | Main mechanism update; geometry canopy entry. |
| Corsair tailhook | Playable presentation mechanism | About 1.5-second authored travel; ground contact limits the lowered pose. Do not promise a full 45-degree travel through the runway or carrier arresting gameplay. | Main mechanism update and ground_limited_fraction; geometry tailhook entry. |
| Corsair retracts / doors | Actual session-driven rig, **airborne for retraction** | Gear fold/twist and doors can be shown after takeoff. The simulator blocks retraction under weight on wheels. Do not stage the aircraft on the runway with retracting support wheels. | [Gear samples](../../../assets/aircraft/f4u-corsair-250/gear-samples.json), [gear renderer](../../../app/render/ground_gear.gd), [session gear interlock](../../../app/sim/flight_session.gd). |
| Wheel roll, tail steering, oleo compression | Session-driven ground presentation | A short taxi turn/settle can show these together. Do not claim a separately animated brake mechanism from the fact that a wheel stops. | Gear renderer, wheel and compression paths. |
| Cockpit stick / pedals | Animation **not supported by identified bindings**; interior readability unverified | Use the sliding canopy as the shot. Do not invent moving internal controls, an onboard Corsair camera or clickable cockpit. | Model bindings and runtime mechanism list; [asset handoff request](../../F4U-BLENDER-HANDOFF.md) is a request, not delivery proof. |
| Cowl flaps | **Not implemented as articulated sectors in this model** | Exclude from the mechanism promise. | [G2/G3 request](../../F4U-G2-3-REQUEST.md): sectors merged into the cowl. |

The old [v9.13 revision record](../../research/cinematic-trailer/revision-9-2026-10-29.md) contains a separate **cyclic** inspector shot and a Corsair deck test. Those records help direct the new material; they do not validate the requested collective shot or current-build footage.

## Main-trailer insert — twelve seconds of Corsair, four of collective

| Master ID | Master time | Frame and movement | End condition |
| --- | --- | --- | --- |
| R4-20 | 00:39–00:43 | Clearly labelled HX-700 studio inspection, tight head view; stopped rotor and visible blade roots. About 1 s neutral, 2 s movement and 1 s hold are creative targets. | Both blade-pitch changes and swash/link relationship can be understood. |
| R4-21 | 00:43–00:47 | Hard cut to playable X-Cell, full side silhouette, forward movement past a field landmark. | Viewers recognize a new context and actual flight. |
| R4-14 | 00:47–00:50 | Low front three-quarter; last part of wing spreading. Both outer panels and runway remain visible. | Spread/locked silhouette holds briefly. |
| R4-15 | 00:50–00:52 | Grounded view with both ailerons and fixed wing. One roll input. | Opposed deflection is visible; no hidden far aileron. |
| R4-16 | 00:52–00:53.5 | Side close-up; elevator plus fixed tailplane. | Movement direction is readable on mute. |
| R4-17 | 00:53.5–00:55 | Rear-oblique close-up; rudder plus fixed fin. | Lateral movement is distinct from previous insert. |
| R4-18 | 00:55–00:57 | Low wing detail; final portion of flap deployment. | Panels reach a settled angle. |
| R4-19 | 00:57–00:59 | Side canopy close-up; fixed cockpit rim remains in view. | Sliding canopy settles; no promised cockpit controls. |

The [R7 shot plan](shot-plan-r7.json) owns camera positions and Godot FOV. Use the `three_tone` Corsair for the ground checks, matching the final orbit and lake. The 1.5-second tail details need real readability checks: capture full travel and retime if the action cannot be read. The master has no spare reserve; a lower-priority feature must be transferred explicitly before extending these inserts. The inspector is a stationary studio presentation, not a shown grounded X-Cell; do not invent an outdoor scene or remove its identification.

### Collective-specific acceptance

- The frame includes both blade roots, the swashplate and enough fixed mast to judge motion. Main blades are visible; a blade does not wipe across the lens.
- Collective changes while cyclic remains neutral and phase stays fixed. Rotor RPM is not the visual explanation.
- The full four-second insert carries an opaque **HX-700 · MECHANICAL INSPECTION** label from first frame to last. The following field clip identifies the playable X-Cell; do not match-cut between the rigs as if they were one aircraft in one session. Placement and readability remain unqualified until actual frames are reviewed.
- The requested neutral/move/hold timing is checked in real output later. Source support and the old cyclic clip do not count as a passed visual test.

## Separate 32-second idea — THE PREFLIGHT BALLET

**Purpose:** a future companion film for viewers who want to see the mechanisms properly. This is an additional screenplay idea, not another deliverable being rendered now and not an extension silently appended to the 150-second master.

| Proposed interval | Duration | Shot |
| --- | ---: | --- |
| 00:00–00:04 | 4.0 s | Labelled HX-700 collective study: neutral, collective movement, held blade-pitch result. |
| 00:04–00:12 | 8.0 s | Full authored Corsair wing-spreading movement on the ground, at native speed. |
| 00:12–00:13.5 | 1.5 s | Both ailerons respond in opposition. |
| 00:13.5–00:15 | 1.5 s | Elevator check, with fixed tailplane reference. |
| 00:15–00:16.5 | 1.5 s | Rudder check, rear-oblique. |
| 00:16.5–00:19 | 2.5 s | Flaps deploy through the authored travel. |
| 00:19–00:21.5 | 2.5 s | Canopy slides and settles. |
| 00:21.5–00:23 | 1.5 s | Tailhook lowers to the ground-limited position. |
| 00:23–00:26 | 3.0 s | Separate correctly configured taxi take: propeller, wheel roll, steering and ground response are visible in one action. |
| 00:26–00:32 | 6.0 s | Separate airborne departure: the current authored four-second gear/door retraction, with time to establish the view and hold a clean silhouette. |
| **Total** | **32.0 s** | Proposed edit only; full-travel timing remains subject to capture handles and readability. |

This is a montage of distinct demonstrations, not one unbroken checklist. Restore the flight configuration between demonstrations: wings spread and locked, canopy/hook/flaps in the intended takeoff/flight states. Retain native speed; if actual travel and useful holds do not fit this 32-second plan, revise the companion edit explicitly. An optional later cyclic/tail-pitch explanation belongs in another clearly identified inspector study.

## Sound and light

Use soft directional daylight on the Corsair so hinges and surfaces read against the fuselage. A consistent real skin and uncluttered ground keep the mechanism visible. Retain the inspector's contrasting studio treatment to identify the change of context.

Use actual mechanical/engine sound where available. A restrained score pulse can join the cuts. Do not invent a loud hydraulic system, add flight rotor sound over a stationary bench rotor, or equate a soundtrack cue with measured mechanical behavior. The new collective idea is about pitch, not rotor speed.

## Pending decisions for the later tools phase

R7 proposes camera access and blocking; confirm the selected build exposes the supported mechanisms and produces readable frames. The inspector launcher is [inspect_hx700.gd](../../../app/tools/inspect_hx700.gd); this reference establishes a source route, not a successful launch. Shot-specific capture routes, actual rig visibility and footage remain pending; this sheet does not select a renderer or video package.
