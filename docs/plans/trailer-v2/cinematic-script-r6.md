# OPEN RC SIMULATOR — Trailer 2.0

## Director’s shooting script — Revision 6: A SKY WITHIN REACH

**22 November 2026 · Current directing, typography and capture-tool specification**
**Track / owner:** V2 / trailer director-editor and lead developer. **Master:** 150.000 seconds, 16:9, 1920×1080 at 60 fps; English; no voice-over required.
**Source baseline:** `57abea025f62b20233ca281d58d2acbee4ab8b8e`; branch parent `f7cf8a13673d8b4243418ab2d9804e40ee6b8f94`. Actual gameplay, imported models, soundtrack and target-host takes remain unqualified.

R6 replaces [R5](cinematic-script-r5.md) as the active directing document. It retains **62 cuts / 9,000 frames** and the stable **R4-prefixed shot IDs**. [The numeric plan](shot-plan-r6.json) owns cast, skins, proposed marks and camera settings. [The storyboard](storyboard-150s.md) owns edit boundaries. [The title plan](title-plan-r6.json) owns every added text cue on a global frame clock. The detailed cards below are generated from the numeric plan; the plan validator rejects text/number drift in that block.

### The creative decision

Let the opening fly. The jet, truck jump, electric Stick, launch and blimp establish the breadth of the simulator before a large title appears. Controls and mechanisms are shown through physical movement and real indicators. Short identity labels explain a change of model or context. Three restrained story titles carry the invitation; the footage supplies the argument.

Keep the **ten-second Corsair orbit**, all **13 real stock liveries**, and the **six-second lake hold**. The final orbit scheme is **Coastal Three Tone**, also used in the ground mechanisms and lake. The import chapter remains **2 seconds Creator + 10 seconds / 18 previews + 3 seconds same-model eligible trial**. No numerical inventory headline is active: **300+** still requires compatible, deduplicated model evidence.

## Text direction and reading load

| Master time | Exact main copy | Entry / full-size hold / exit | Placement target |
| --- | --- | --- | --- |
| 14.25–17.50 s | A SKY WITHIN REACH | 18-frame entrance, 12-frame exit; at least 2.75 s settled | Upper-left negative space of the blimp composition. |
| 60.25–64.75 s | FEEL EVERY INPUT | 18-frame entrance, 12-frame exit; at least 4.00 s settled | Upper-left; keep real transmitter/input display and aircraft clear. |
| 125.00–127.00 s | EXPAND YOUR HANGAR | 8-frame entrance and exit; at least 1.73 s settled | Upper-left in the Creator introduction; gone when the model reel begins. |
| 145.00–150.00 s | OPEN RC SIMULATOR / PLAY FREE / official destination | Fully opaque for all 300 frames | Centered editorial end card; no moving model or competing feature list. |

Use the already-vendored **Barlow Condensed**: SemiBold for story titles and invitation, Regular for functional labels. The authored ink is warm white **#F2EFE7**, with measured tracking and a restrained dark shadow. The entrance combines a brief opacity fade with at most eight pixels of vertical settling. No luminous green panels, scanning edges, decorative feature cards or long reveal animations. This is a film title treatment, not a redesign of the official logo.

The upper-left position is a composition proposal. Bounds are measured inside the 1920×1080 title-safe area; actual aircraft, HUD, Creator controls and background contrast must be reviewed in the captured frames. If an overlay obscures evidence, move that cue to verified empty space and revalidate its bounds. Do not shrink required qualifications into unreadability to keep a decorative headline.

Required labels stay fully opaque for their complete relevant exposures. The HX-700 insert identifies mechanical inspection; X-Cell identifies the separate playable helicopter. AI, engine-out, imported scenery and scale/comparison labels preserve the meaning of the images. **PRESENTATION · LIVERY SHOWCASE** is visible for all ten seconds of the orbit. The Phoenix and ClearView source labels remain continuous across their nine cuts each; they do not re-enter every half second. The lake carries no added title. The imported trial must state its actual **estimated** or **donor** physics basis before a public export; a generic trial title does not close that requirement.

Use **bultodepapas.github.io/OpenRCsimulator/** as the source-known destination. The destination returned HTTP 200 with the matching project page title on 22 November 2026. Recheck it before publication; the download and installation flow has not been tested in this pass. Do not inherit the first trailer’s BETA PREVIEW, older slogan, description or music credit. Final soundtrack attribution follows the music actually selected; no music is selected by this revision.

## Camera and edit grammar

The camera has one job per shot: establish geography, reveal a mechanism, follow a response or let the viewer admire a model. The short Corsair mechanism details remain separate controlled views; a single fast orbit would hide the surface movement. The stopped-rotor HX-700 insert is a four-second inspection, followed by a clearly separate X-Cell flight. The import reel uses consistent three-quarter model framing, genuine source textures and normalized screen occupancy rather than artificial changes to proportions.

The opening fixed eyes pan/tilt to actual CG. “Exit” means the aircraft passes the world exit mark and we cut with it readable. It does not mean the centered aircraft travels out of the screen. The lake uses a parallel camera so the scenery provides motion while the Corsair remains legible. The signature livery orbit retains its existing **visual-model-root** anchor; it is not silently changed to the CG anchor used by the new flight camera.

| Executable camera recipe | Eye / behavior | FOV | Remaining flight work |
| --- | --- | --- | --- |
| R4-01 · Vantage | Fixed world eye N0/E0/D−1.6; aim at actual presented CG | 38° | Genuine inversion or accepted banked fallback, source frame window, paint and clearance. |
| R4-03 · Electric Stick | Fixed world eye N4/E0/D−1.2; aim at actual presented CG | 38° | Trimmed real pass, identity/paint readback and readable framing. |
| R4-40 · Corsair lake | N145/D−1; east follows actual CG east−8 m | 42° | Real approach, clean configuration, height/shore/prop clearance, matching reflection and native-speed take. |

These are Godot camera FOV properties, not invented photographic lens equivalents. A recipe exports camera settings only. It does not select a skin, establish a spawn, implement an autopilot, force a trajectory or qualify an imported model. Other fixed-wing Club-field fixed-eye shots can use the supported exporter; UI, rotorcraft, panoramas, model inspections, ground activities and the livery orbit keep their owning capture routes.

## Sound and emotional rhythm

Build the first cuts on recognizable source sounds: turbine, nitro landing, electric propeller, hand launch, then the quieter blimp. Let servo and mechanism details breathe around the Corsair surfaces. The collective insert can use its actual mechanism/inspection sound if available; do not manufacture a flying helicopter sound to imply that the inspector is in a flight session.

Reserve the strongest musical opening for flight breadth and the import reel. Ease the density for the livery orbit and let the lake sustain one clean sound bed. The 18 model images can cut on a faster subdivision without accelerating physics or source previews. Finish with the Bisonte’s real water/contact sound, then the five-second invitation. Music remains an audition/rights decision; these are editorial accents, not a selected track or fabricated sound proof.

## Coordinate and take contract

| Quantity | Meaning |
| --- | --- |
| `(N, E, D)` | Simulation north, east and down in metres. Negative D is above the reference datum. |
| Render `(x, y, z)` | `(E, −D, −N)`. Example: Corsair lake entry `(128, 55, −2.55)` becomes `(55, 2.55, −128)`. |
| Heading | Clockwise from north: 0° north, 90° east, 180° south, 270° west. |
| `NE_surface` | A plan-view ground/support marker. Its zero D is a drawing datum; the production ground solver supplies actual CG height, attitude and suspension support. |
| Camera `FRU` | Forward/right/up metres in the aircraft’s **horizontal heading frame**. Proposed cameras use actual CG unless specified; the existing R4-39 orbit uses **visual model root**, which is offset from simulated CG. |
| Shot-local time | Seconds or frames from the proposed edit’s start. An endpoint at the cut duration is a geometric boundary, not an included extra frame. |
| Source time | Actual simulation ticks and recorded movie frames, determined during capture. Startup, arm/governor wait, maneuver setup and UI loading are outside the edit unless explicitly shown. |

Source anchors come from [field data](../../../app/data/fields/default.json), [lake data](../../../app/data/fields/lake.json), [truck track data](../../../app/data/ground_vehicle/airfield_track.json), [race course](../../../app/data/race/tracks/openrc-practice-oval-1.json), [frame conversion](../../../app/render/frames.gd) and the current launch/session implementations. Full source hashes are in the plan. Coordinates are proposed staging targets until a real take demonstrates them.

### Geography we can actually refer to

| Anchor | Source-backed position or extent |
| --- | --- |
| Club pilot | N0 / E0; eye 1.7 m above station. |
| Club runway | Center N15 / E0; N9…21, E−50…50. Normal eastbound threshold N15 / E−47; actual ground equilibrium determines aircraft CG. |
| Helicopter pad | Center N6 / E0, 6 × 6 m. |
| MoonRunner release | N9 / E0, 1.9 m above sampled terrain, 6.5 m/s, 5° climb. Calm launch heads east. |
| Truck start / tabletop | Start N39 / E−9 eastbound. Ramp approach begins E−5.225; deck E−4.225…−3.775; descent ends E−1.975; rise 0.48 m. |
| FPV pad / first gate | Pad N28 / E38. Gate center N35 / E43, 2 m above sampled terrain, east-facing, 3 m × 2 m aperture. |
| Lake | Origin N110 / E125; mean water D+0.45. Shoreline is the actual source polygon, not a circular approximation. |
| Bisonte shore start | Native `lake_shore` N145.5 / E125, heading south, subject to its actual staging checks. Proposed stop N138 / E125. |
| Phoenix Airfield | Separate calibrated photo-eye N0 / E0, eye 1.7 m; runway center N12 / E1, 42 m × 9 m. Exact installed panorama must match the selected source calibration. |

## Casting and paint lock

These are concrete authored choices for rehearsal; their appearance has not been visually accepted. An empty selection value means the stock default, not a missing texture. The Mustang, Extra and Turbo Lumber each keep their one shipped factory livery. Custom skin capability does not supply a ready-made alternate.

| Cast | Exact Home/catalog ID | Chosen asset/paint | Selection value |
| --- | --- | --- | --- |
| Vantage Jet | `sebart-avanti-s-a200-p100rx` | Sabre Plata | `sabre_plata` |
| MONSTER CAR 2 | `monster-car-2` | Naranja Lava | `naranja_lava` |
| Ugly Stick Electric 6S | `stik-electric-6s` | NEON RONIN · Cyberpunk | `neon_ronin` |
| MoonRunner X99 | `moonrunner-x99` | BOLIDO - re-entry heat shield | `bolido` |
| RC Blimp 5 m | `rc-blimp-5m` | Tiburón Blanco | `tiburon-blanco` |
| ION R5 | `openrc-fpv5-x1` | Factory ION R5; no stock paint selector | `empty/default` |
| F4U Corsair | `f4u-corsair-250` | Coastal Three Tone | `three_tone` |
| X-Cell .60 research helicopter | `xcell-60-research` | Blanco Ártico | `blanco_artico` |
| P-51D Mustang | `p51d-mustang-120` | P-51D Mustang factory | `empty/default` |
| Extra 300S | `gp-extra-300s-60` | Extra 300S factory | `empty/default` |
| Turbo Lumber Evolution | `turbo-lumber-evolution` | Turbo Lumber factory | `empty/default` |
| MT8 Bisonte | `mt8-bisonte` | Amarillo Rayo | `amarillo_rayo` |
| Ugly Stick .61 glow | `jensen-das-ugly-stik-60` | HONEYBEE · 07 | `honeybee` |

The separate **HX-700 inspector** has a studio mechanism/inspection layer, not a Home-flight skin. The 18 imported preview candidates keep their actual admitted source textures; exact local model roots, texture hashes and final trial eligibility remain to be recorded in the [import sheet](import-showcase.md).

## The Corsair signature

### Orbit: exact intended paint rhythm

Keep spread wings, closed canopy, clean gear/flaps/hook, one scale and one weather/exposure setting. The camera uses the existing seven-metre heading-relative orbit around the **visual model-root origin**, starting front-left at −40°, ending at 320°, with a smoothstep full revolution. Its height starts and ends 0.9 m above that root and rises to 1.4 m halfway; it looks 0.2 m above the root, with `Camera3D.fov = 34`. The visual root is offset from simulated CG. These are the capture driver’s values, not a claim about a player camera.

| Local edit interval | Frames, end exclusive | Livery asset ID | Home selection |
| --- | --- | --- | --- |
| 0–0.75 s | 0–45 | `midnight` | `empty/default` |
| 0.75–1.5 s | 45–90 | `p40` | `p40` |
| 1.5–2.25 s | 90–135 | `japan` | `japan` |
| 2.25–3 s | 135–180 | `luftwaffe` | `luftwaffe` |
| 3–3.75 s | 180–225 | `italy` | `italy` |
| 3.75–4.5 s | 225–270 | `scarlet` | `scarlet` |
| 4.5–5.25 s | 270–315 | `thunderbirds` | `thunderbirds` |
| 5.25–6 s | 315–360 | `blueangels` | `blueangels` |
| 6–6.75 s | 360–405 | `chrome` | `chrome` |
| 6.75–7.5 s | 405–450 | `carbon` | `carbon` |
| 7.5–8.25 s | 450–495 | `spectrum` | `spectrum` |
| 8.25–9 s | 495–540 | `splash` | `splash` |
| 9–10 s | 540–600 | `three_tone` | `three_tone` |

Twelve 45-frame holds plus the final 60-frame hold total 600 frames. `midnight` is the first real livery asset but Home normalizes its selection to an empty string; the cycle uses the asset ID. The new hold-last option keeps `three_tone` selected after its final change. The director’s clock is simulation time: inspect actual `sim_time_s` and `presented_livery` for source-frame alignment before accepting this exact edit cadence.

### Lake: origin, crossing, exit

The proposed eastbound corridor remains **N128 / E55 → E124 → E193**, at **D−2.55**: 3 m above mean water, with nominal 23 m/s planning speed. R6 uses a **parallel tracking camera**, at fixed **N145 / D−1** and **E = actual presented CG east − 8 m**, with **FOV 42°**. At the nominal marks its eyes are **(145,47,−1) → (145,116,−1) → (145,185,−1)**. They illustrate the rig law; the camera follows the real rendered aircraft even when its flight differs from the proposed corridor.

The aircraft stays near frame center. Its eastbound nose points screen-left from this north-bank view; the shoreline and background move behind it. This is a steady six-second breathing space after the 13-skin orbit. Do not ask a CG-tracking camera to make the aircraft cross the picture or exit a frame edge. Match the final orbit’s accepted nose orientation on the cut.

The earlier fixed eye at N145/E125 would turn approximately 152° over the nominal pass, with a peak pan near 77.5°/s. The parallel move removes that nominal whip-pan geometry. It is a camera design decision, not proof of actual stability or clearance. The low eye is 1.45 m above mean water but its route is near the bank; rendered shore/terrain clearance remains unqualified.

The actual polygon intersects this line near **E88.73** and **E162.91**. Its water chord is approximately **74.18 m**, or **3.225 seconds at the nominal speed**. The remaining part of the six-second shot includes approach and exit. CG/wingtip/prop clearance, camera support, objects, actual speed and reflection still require a real rehearsal. A generic “altitude above terrain” spawn can measure from the lakebed; it must not be confused with height above water.

The [lake blocking map](diagrams/r6-lake-blocking.svg) visualizes these source/target coordinates; the [truck blocking map](diagrams/r5-truck-blocking.svg) shows the source tabletop footprint and proposed vehicle/camera marks. Dashed lines connect proposed marks; they are not recorded trajectories.

## Detailed shot cards

The following block is generated with `python3 tools/trailer/shot_plan.py cards`. Frame intervals are half-open at 60 fps; endpoint marks are geometric targets, not included extra frames.

<!-- BEGIN GENERATED SHOT CARDS -->

### R4-01 — Vantage Jet · 00:00:00–00:04:00 · G

**Picture:** Vantage Jet: genuine inverted external pass; real banked pass is the rehearsal fallback.

**Cast / paint:** Vantage Jet — Sabre Plata. **Environment:** `day_calm`.

**Preparation:** Home Vantage, Sabre Plata, airborne. Rehearse the roll well before the selected clip. **At the edit’s start:** Already established inverted flight on entry; runway and horizon visible.

**Blocking (NED):** 0s: (15, -58, -8) → 2s: (15, 0, -8) → 4s: (15, 58, -8) 29 m/s is configured launch speed, not measured pass speed; points are a 116 m nominal corridor.

**Camera:** fixed_tracking, NED, FOV 38°. 0s: (0, 0, -1.6) Fixed eye; pan/tilt to actual aircraft CG. Keep world horizon upright.

**Action:**

- Before edit: establish altitude and inversion with genuine roll input.
- 0–3 s: hold a stable canopy-down pass; no video rotation.
- 3–4 s: pass the east world exit mark with attitude readable; retain real turbine sound.

**Exit / cut:** Aircraft reaches the east world exit mark; tracking keeps its CG near frame center. Cut while the inverted or accepted banked attitude remains readable. Hard cut from turbine sound to the nitro truck. Match the dominant nose orientation where possible; do not claim left-to-right screen translation from a CG-tracking shot.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `camera_adapter_implemented_flight_pending` — `capture_flight.gd --camera-recipe plus qualified shot-specific pilot director`. R6 can export the fixed presentation eye and actual-CG aim. Launch, pilot inputs, selected paint and full flight corridor still require real-session rehearsal; the recipe applies no aircraft state.

**Accept only when:** Genuine inversion and ground/horizon agree. If unsafe/unreadable in simulation, use the declared real upright banked pass; update take status.

### R4-02 — MONSTER CAR 2 · 00:04:00–00:08:00 · G

**Picture:** MONSTER CAR 2: nitro ramp departure, apex, touchdown and suspension response.

**Cast / paint:** MONSTER CAR 2 — Naranja Lava. **Environment:** `day_calm`.

**Preparation:** Garage MONSTER CAR 2, Naranja Lava; select track_start and verify actual spawn. **At the edit’s start:** Start N39 E−9 heading east, wheels supported. Begin recording before acceleration.

**Blocking (NE_surface):** 0s: (39, -9, 0) → 1s: (39, -5.225, 0) → 2s: (39, -3.775, 0) → 4s: (39, 3, 0) Ramp geometry anchors; time-to-ramp and landing point are rehearsal targets, not a ballistic prediction. D=0 is a map reference only.

**Camera:** fixed_tracking, NED, FOV 42°. 0s: (34, -3, -0.35) Low south-side eye follows body; preserve full tire silhouette and actual touchdown; no camera through the ramp.

**Action:**

- Accelerate east with W/Up; steer neutral.
- Retain takeoff, apex, actual touchdown and first suspension settle in the four-second edit.
- Use Space/S brake after the landing outside the retained action.

**Exit / cut:** Upright landing visible with tires taking load. Cut on landing sound into electric Stick pass.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `existing_adapter` — `tools/trailer/capture_car_jump.gd + production ground activity`. Existing jump capture supplies ordinary driving; camera/skin and exact clip must be rehearsed for this cast.

**Accept only when:** Monster-specific jump must be demonstrated; Bisonte tests do not qualify the nitro truck. Actual take contains the complete landing; no speed-up or cropped outcome.

### R4-03 — Ugly Stick Electric 6S · 00:08:00–00:11:00 · G

**Picture:** Ugly Stick Electric 6S: clear lateral pass, actual alternate skin and variant identification.

**Cast / paint:** Ugly Stick Electric 6S — NEON RONIN · Cyberpunk. **Environment:** `day_calm`.

**Preparation:** Home Ugly Stick Electric 6S, NEON RONIN; airborne. **At the edit’s start:** Enter west of runway at about 4 m above reference ground; trim before mark.

**Blocking (NED):** 0s: (18, -22.5, -4) → 1.5s: (18, 0, -4) → 3s: (18, 22.5, -4) 45 m reference corridor at the configured 15 m/s start speed; actual track may differ.

**Camera:** fixed_tracking, NED, FOV 38°. 0s: (4, 0, -1.2) Fixed eye; pan/tilt to actual aircraft CG. Keep world horizon upright.

**Action:**

- Preroll at least two settled seconds before entry.
- Hold a simple lateral pass; avoid a roll that hides the selected paint.
- Keep UGLY STICK · ELECTRIC 6S readable without covering the model.

**Exit / cut:** Aircraft passes the east world exit mark while the entire airframe remains readable near frame center. Match the dominant eastbound nose orientation into MoonRunner launch; the tracking pass does not require the aircraft to leave the picture.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `camera_adapter_implemented_flight_pending` — `capture_flight.gd --camera-recipe plus qualified shot-specific pilot director`. R6 can export the fixed presentation eye and actual-CG aim. Launch, pilot inputs, selected paint and full flight corridor still require real-session rehearsal; the recipe applies no aircraft state.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-04 — MoonRunner X99 · 00:11:00–00:14:00 · G

**Picture:** MoonRunner: actual hand-launch release into a climbing bank; no throwing-person animation.

**Cast / paint:** MoonRunner X99 — BOLIDO - re-entry heat shield. **Environment:** `day_calm`.

**Preparation:** Home MoonRunner X99, BOLIDO, explicit hand_launch. Verify the choice was not replaced. **At the edit’s start:** Native release at N9 E0, terrain +1.9 m, 6.5 m/s, 5° climb in calm eastbound setup.

**Blocking (NED):** 0s: (9, 0, -1.9) → 3s: (10, 18, -4.5) First point uses the flat-reference terrain; verify actual sampled release altitude. Exit is a gentle climbing target, not source launch behavior.

**Camera:** fixed_tracking, NED, FOV 42°. 0s: (1, 6, -1) Fixed eye; pan/tilt to actual aircraft CG. Keep world horizon upright.

**Action:**

- Start the cut at the actual release state; no throwing person.
- Keep wings identifiable through a shallow climbing bank.
- Do not cut until positive climb is visible.

**Exit / cut:** Flying wing clears the launch area in world space, with its eastbound nose pointing screen-right; CG tracking keeps it near frame center. Cut from dark BOLIDO silhouette to the white blimp envelope.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `adapter_needed` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-05 — RC Blimp 5 m · 00:14:00–00:18:00 · G

**Picture:** Blimp: full envelope/gondola, quiet motion and real birds if readable.

**Cast / paint:** RC Blimp 5 m — Tiburón Blanco. **Environment:** `day_calm`.

**Preparation:** Home RC blimp, Tiburón Blanco; use its own launch menu and settle before the take. **At the edit’s start:** Blimp already moving slowly east from the west world mark; whole envelope and gondola are visible near frame center.

**Blocking (NED):** 0s: (30, -6, -6) → 4s: (30, 6, -6) 3 m/s is a proposed composition pace; obtain actual trim/motion through normal airship controls.

**Camera:** fixed_tracking, NED, FOV 45°. 0s: (16, 0, -1.7) Fixed eye; pan/tilt to actual aircraft CG. Keep world horizon upright.

**Action:**

- Preroll until yaw and pitch settle.
- Travel gently east through the proposed world corridor. The camera follows CG; the nose points screen-right while the background moves behind it.
- Birds are welcome only if they do not obscure the blimp.

**Exit / cut:** The gondola remains visible through the final frame. Let quieter prop sound breathe, then cut to the gate-course geometry.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `adapter_needed` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-06 — ION R5 · 00:18:00–00:19:30 · G

**Picture:** ION R5: exterior course geography and end of the actual countdown.

**Cast / paint:** ION R5 — Factory ION R5; no stock paint selector. **Environment:** `day_calm`.

**Preparation:** Home ION R5, pad, practice oval; use actual course/race controls. **At the edit’s start:** Pad N28 E38, Angle mode, ready for the genuine countdown ending.

**Blocking (NE_surface):** 0s: (28, 38, 0) Ground reference; use the actual supported quad pose, not D=0 as CG.

**Camera:** fixed_tracking, NED, FOV 48°. 0s: (24, 34, -2.2) Overview establishes pad and first gate N35 E43; camera target is that corridor.

**Action:**

- T selects course if needed; G requests race.
- Retain the actual end of countdown, not an edited fake start signal.

**Exit / cut:** First gate and departure direction are understood. Hard cut to rigid FPV from the same course; no synchronized replay claim.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-07 — ION R5 · 00:19:30–00:24:00 · G

**Picture:** Rigid FPV: approach, enter and clear a valid gate; retain genuine guidance.

**Cast / paint:** ION R5 — Factory ION R5; no stock paint selector. **Environment:** `day_calm`.

**Preparation:** Same course and stock ION; fly from pad into the gate approach. **At the edit’s start:** Correct next-gate state active; quad approaches first gate from its west side.

**Blocking (NED):** 0s: (35, 38, -2) → 2.25s: (35, 43, -2) → 4.5s: (35, 48, -2) Gate is 2 m above sampled terrain: replace D=-2 with sampled-ground-down minus 2. Timing is a pilot target, not a scoring guarantee.

**Camera:** native_rigid_fpv, FRU, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Use production mounted FPV; no independent camera orbit, roll stabilization or invented lens position.

**Action:**

- Arm with actual input; establish suitable normal speed before the gate.
- Fly through aperture center with actual race guidance visible.
- Continue beyond the plane until the pass is counted.

**Exit / cut:** Valid crossing recorded; no panel strike. Cut to exterior coverage of a valid passage.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Correct direction, next-gate order, speed and aperture clearance pass actual race logic. Center height follows sampled terrain; frame panels are physical obstacles.

### R4-08 — ION R5 · 00:24:00–00:26:00 · G

**Picture:** Exterior valid gate passage; separate take unless a real continuous switch exists.

**Cast / paint:** ION R5 — Factory ION R5; no stock paint selector. **Environment:** `day_calm`.

**Preparation:** Separate exterior take on the same practice oval; identify it as edited coverage. **At the edit’s start:** West approach to first gate; do not imply a replay system.

**Blocking (NED):** 0s: (35, 40, -2) → 1s: (35, 43, -2) → 2s: (35, 46, -2) Same terrain-relative center correction as R4-07.

**Camera:** fixed_tracking, NED, FOV 42°. 0s: (30, 43, -1.1) Frame gate and at least one model length before/after; follow actual quad.

**Action:**

- Record a real correctly directed pass.
- Let the quad exit the opening before the cut.

**Exit / cut:** Gate and vehicle are visibly separated after clearance. Match quad position into the Angle demonstration.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `adapter_needed` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-09 — ION R5 · 00:26:00–00:28:30 · G

**Picture:** Angle mode: real bank and stick-release response, actual mode indicator visible.

**Cast / paint:** ION R5 — Factory ION R5; no stock paint selector. **Environment:** `day_calm`.

**Preparation:** Separate clear part of course; Angle mode read back on actual OSD. **At the edit’s start:** At least 5 m above sampled ground, clear of gates; neutral roll.

**Blocking (NED):** 0s: (43, 48, -5) → 2.5s: (43, 58, -5) Loose demonstration corridor. Hold altitude through ordinary throttle; points are not a commanded motion path.

**Camera:** native_rigid_fpv, FRU, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Native FPV shows the horizon and genuine Angle indicator.

**Action:**

- 0–0.8 s: a modest roll input, starting rehearsal around +0.25.
- 0.8–2.5 s: release roll and retain the actual assisted response.

**Exit / cut:** Horizon/response and mode label read together. Cut on a similar horizon to Acro.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-10 — ION R5 · 00:28:30–00:31:00 · G

**Picture:** Acro mode: a readable real roll/bank maneuver with the actual mode indicator.

**Cast / paint:** ION R5 — Factory ION R5; no stock paint selector. **Environment:** `day_calm`.

**Preparation:** Separate pass; set Acro and verify OSD. Increase clearance before entering clip. **At the edit’s start:** About 8 m above ground in clear air; no gate immediately ahead.

**Blocking (NED):** 0s: (43, 58, -8) → 2.5s: (43, 68, -8) Entry/exit volume only; roll changes the actual path.

**Camera:** native_rigid_fpv, FRU, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Preserve native horizon motion; no counterrotation in post.

**Action:**

- Use a real roll input and neutralize before the next action.
- Accept only a complete readable maneuver; if it needs more time, retime explicitly.

**Exit / cut:** Control recovery visible and Acro indication readable. Cut to a clearly separate low-height tip-over attempt.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-11 — ION R5 · 00:31:00–00:33:00 · G

**Picture:** Separate graded-impact attempt: survivable tip-over; authentic non-blood lens/contact effect only if triggered.

**Cast / paint:** ION R5 — Factory ION R5; no stock paint selector. **Environment:** `day_calm`.

**Preparation:** Isolated recovery attempt near the pad; same quad, battery and damage state across 11–13. **At the edit’s start:** Use open ground around N28 E33; reset is forbidden inside this recovery chain.

**Blocking (NE_surface):** 0s: (28, 33, 0) Plan-view recovery patch; actual contact/CG and final offset are recorded, not assigned.

**Camera:** fixed_tracking, NED, FOV 38°. 0s: (24, 33, -0.55) Close low eye; quad must not be hidden by a gate, grass or its own overlay.

**Action:**

- Preroll: approach an empty patch at low height; use a real survivable contact.
- Retain approach, contact and tipped resting pose; no person strike.

**Exit / cut:** Tipped pose established. Keep one attempt through the recovery edits.

**Continuity:** Same attempt and location; no restart, terminal-crash revival, depleted-pack revival or invisible repair.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Actual state gates admit each arm/turtle transition. If recovery timing does not fit, obtain a clearer successful attempt or explicitly retime.

### R4-12 — ION R5 · 00:33:00–00:37:00 · G

**Picture:** Disarmed turtle selection and real righting action; intervening control-state time may be omitted honestly.

**Cast / paint:** ION R5 — Factory ION R5; no stock paint selector. **Environment:** `day_calm`.

**Preparation:** Isolated recovery attempt near the pad; same quad, battery and damage state across 11–13. **At the edit’s start:** Use open ground around N28 E33; reset is forbidden inside this recovery chain.

**Blocking (NE_surface):** 0s: (28, 33, 0) Plan-view recovery patch; actual contact/CG and final offset are recorded, not assigned.

**Camera:** fixed_tracking, NED, FOV 38°. 0s: (24, 33, -0.55) Close low eye; quad must not be hidden by a gate, grass or its own overlay.

**Action:**

- Begin from the same nonterminal grounded attempt.
- E disarm; F request turtle; throttle low; fresh E arm; roll/pitch toward the intended righting direction.
- Keep actual righting in view; omit waiting between states only as explicit edits.

**Exit / cut:** Quad genuinely upright. Keep one attempt through the recovery edits.

**Continuity:** Same attempt and location; no restart, terminal-crash revival, depleted-pack revival or invisible repair.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Actual state gates admit each arm/turtle transition. If recovery timing does not fit, obtain a clearer successful attempt or explicitly retime.

### R4-13 — ION R5 · 00:37:00–00:39:00 · G

**Picture:** Normal rearm and successful lift-off from the same recovered quad attempt.

**Cast / paint:** ION R5 — Factory ION R5; no stock paint selector. **Environment:** `day_calm`.

**Preparation:** Isolated recovery attempt near the pad; same quad, battery and damage state across 11–13. **At the edit’s start:** Use open ground around N28 E33; reset is forbidden inside this recovery chain.

**Blocking (NE_surface):** 0s: (28, 33, 0) Plan-view recovery patch; actual contact/CG and final offset are recorded, not assigned.

**Camera:** fixed_tracking, NED, FOV 38°. 0s: (24, 33, -0.55) Close low eye; quad must not be hidden by a gate, grass or its own overlay.

**Action:**

- Once upright, E disarm and establish low throttle.
- Fresh normal arm, then gentle throttle to lift; retain the same recovered attempt.

**Exit / cut:** Quad clearly airborne again. Match motor/rotor movement into Corsair mechanism detail.

**Continuity:** Same attempt and location; no restart, terminal-crash revival, depleted-pack revival or invisible repair.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Actual state gates admit each arm/turtle transition. If recovery timing does not fit, obtain a clearer successful attempt or explicitly retime.

### R4-14 — F4U Corsair · 00:39:00–00:42:00 · G

**Picture:** Grounded Corsair: last three seconds of wing spreading, ending spread and locked.

**Cast / paint:** F4U Corsair — Coastal Three Tone. **Environment:** `ground_breeze`.

**Preparation:** Home Corsair, Coastal Three Tone, runway; verify support and stable idle at the west threshold. **At the edit’s start:** N15 E−47, heading east; ground solver owns supported CG/attitude. Wheels stay down.

**Blocking (NE_surface):** 0s: (15, -47, 0) Ground reference, never an instruction to put CG at D=0.

**Camera:** subject_relative, FRU, FOV 38°. 0s: (2.5, -4, 1.3) Camera offsets in horizontal forward/right/up from the actual aircraft CG; target the named mechanism, with fixed structure visible. Rehearse near-plane/mesh clearance.

**Action:**

- Before edit: stationary Corsair, idle throttle, fold completely, then request spread with O.
- Use only the final three seconds of the native eight-second estimated spread, ending fully locked.

**Exit / cut:** Mechanism motion and its settled end are readable. Hard detail cut; keep ground position, skin and light constant.

**Continuity:** Coastal Three Tone throughout. Same heading/support; no running takeoff during ground checks. Gear remains down; no unshown fold-state jump.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Fold: weight on wheels, speed below 0.5 m/s, idle until spread/locked. Native travel is recorded without time compression; excerpts are acknowledged.

### R4-15 — F4U Corsair · 00:42:00–00:44:00 · G

**Picture:** Corsair: both ailerons move in opposition against fixed wings.

**Cast / paint:** F4U Corsair — Coastal Three Tone. **Environment:** `ground_breeze`.

**Preparation:** Home Corsair, Coastal Three Tone, runway; verify support and stable idle at the west threshold. **At the edit’s start:** N15 E−47, heading east; ground solver owns supported CG/attitude. Wheels stay down.

**Blocking (NE_surface):** 0s: (15, -47, 0) Ground reference, never an instruction to put CG at D=0.

**Camera:** subject_relative, FRU, FOV 38°. 0s: (0.2, -4.5, 2) Camera offsets in horizontal forward/right/up from the actual aircraft CG; target the named mechanism, with fixed structure visible. Rehearse near-plane/mesh clearance.

**Action:**

- Wings spread/locked; frame both wing trailing edges.
- 0–0.7 s neutral, 0.7–1.3 s modest right roll, then neutral and hold; show opposite aileron movement.

**Exit / cut:** Mechanism motion and its settled end are readable. Hard detail cut; keep ground position, skin and light constant.

**Continuity:** Coastal Three Tone throughout. Same heading/support; no running takeoff during ground checks. Gear remains down; no unshown fold-state jump.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Fold: weight on wheels, speed below 0.5 m/s, idle until spread/locked. Native travel is recorded without time compression; excerpts are acknowledged.

### R4-16 — F4U Corsair · 00:44:00–00:45:30 · G

**Picture:** Corsair: elevator detail with fixed tailplane reference.

**Cast / paint:** F4U Corsair — Coastal Three Tone. **Environment:** `ground_breeze`.

**Preparation:** Home Corsair, Coastal Three Tone, runway; verify support and stable idle at the west threshold. **At the edit’s start:** N15 E−47, heading east; ground solver owns supported CG/attitude. Wheels stay down.

**Blocking (NE_surface):** 0s: (15, -47, 0) Ground reference, never an instruction to put CG at D=0.

**Camera:** subject_relative, FRU, FOV 35°. 0s: (-2.5, -2, 0.9) Camera offsets in horizontal forward/right/up from the actual aircraft CG; target the named mechanism, with fixed structure visible. Rehearse near-plane/mesh clearance.

**Action:**

- Hold the fixed tailplane against the moving elevator.
- Pitch back for a short visible deflection, release, finish neutral.

**Exit / cut:** Mechanism motion and its settled end are readable. Hard detail cut; keep ground position, skin and light constant.

**Continuity:** Coastal Three Tone throughout. Same heading/support; no running takeoff during ground checks. Gear remains down; no unshown fold-state jump.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Fold: weight on wheels, speed below 0.5 m/s, idle until spread/locked. Native travel is recorded without time compression; excerpts are acknowledged.

### R4-17 — F4U Corsair · 00:45:30–00:47:00 · G

**Picture:** Corsair: rudder from a separate rear-oblique angle.

**Cast / paint:** F4U Corsair — Coastal Three Tone. **Environment:** `ground_breeze`.

**Preparation:** Home Corsair, Coastal Three Tone, runway; verify support and stable idle at the west threshold. **At the edit’s start:** N15 E−47, heading east; ground solver owns supported CG/attitude. Wheels stay down.

**Blocking (NE_surface):** 0s: (15, -47, 0) Ground reference, never an instruction to put CG at D=0.

**Camera:** subject_relative, FRU, FOV 35°. 0s: (-2.8, -1.8, 1) Camera offsets in horizontal forward/right/up from the actual aircraft CG; target the named mechanism, with fixed structure visible. Rehearse near-plane/mesh clearance.

**Action:**

- Reframe rear-oblique so rudder is separated from fin.
- A/D yaw deflection then center; keep fuselage stationary.

**Exit / cut:** Mechanism motion and its settled end are readable. Hard detail cut; keep ground position, skin and light constant.

**Continuity:** Coastal Three Tone throughout. Same heading/support; no running takeoff during ground checks. Gear remains down; no unshown fold-state jump.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Fold: weight on wheels, speed below 0.5 m/s, idle until spread/locked. Native travel is recorded without time compression; excerpts are acknowledged.

### R4-18 — F4U Corsair · 00:47:00–00:49:00 · G

**Picture:** Corsair: flap-deployment excerpt reaches and holds its end pose.

**Cast / paint:** F4U Corsair — Coastal Three Tone. **Environment:** `ground_breeze`.

**Preparation:** Home Corsair, Coastal Three Tone, runway; verify support and stable idle at the west threshold. **At the edit’s start:** N15 E−47, heading east; ground solver owns supported CG/attitude. Wheels stay down.

**Blocking (NE_surface):** 0s: (15, -47, 0) Ground reference, never an instruction to put CG at D=0.

**Camera:** subject_relative, FRU, FOV 35°. 0s: (-0.2, -2.6, 0.55) Camera offsets in horizontal forward/right/up from the actual aircraft CG; target the named mechanism, with fixed structure visible. Rehearse near-plane/mesh clearance.

**Action:**

- Reset flap state before the take.
- Request actual full detent with F; record the complete 2.5 s cycle and retain a two-second excerpt ending settled.

**Exit / cut:** Mechanism motion and its settled end are readable. Hard detail cut; keep ground position, skin and light constant.

**Continuity:** Coastal Three Tone throughout. Same heading/support; no running takeoff during ground checks. Gear remains down; no unshown fold-state jump.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Fold: weight on wheels, speed below 0.5 m/s, idle until spread/locked. Native travel is recorded without time compression; excerpts are acknowledged.

### R4-19 — F4U Corsair · 00:49:00–00:51:00 · G

**Picture:** Corsair: sliding-canopy excerpt ends in a readable settled position.

**Cast / paint:** F4U Corsair — Coastal Three Tone. **Environment:** `ground_breeze`.

**Preparation:** Home Corsair, Coastal Three Tone, runway; verify support and stable idle at the west threshold. **At the edit’s start:** N15 E−47, heading east; ground solver owns supported CG/attitude. Wheels stay down.

**Blocking (NE_surface):** 0s: (15, -47, 0) Ground reference, never an instruction to put CG at D=0.

**Camera:** subject_relative, FRU, FOV 35°. 0s: (1, -1.7, 0.85) Camera offsets in horizontal forward/right/up from the actual aircraft CG; target the named mechanism, with fixed structure visible. Rehearse near-plane/mesh clearance.

**Action:**

- Frame canopy against fixed cockpit rim; no animated stick/pedals implied.
- U opens canopy; record complete 2.5 s travel and select a two-second excerpt plus settled end.

**Exit / cut:** Mechanism motion and its settled end are readable. Match canopy movement into the stationary rotor-head inspection.

**Continuity:** Coastal Three Tone throughout. Same heading/support; no running takeoff during ground checks. Gear remains down; no unshown fold-state jump.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Fold: weight on wheels, speed below 0.5 m/s, idle until spread/locked. Native travel is recorded without time compression; excerpts are acknowledged.

### R4-20 — HX-700 articulated mechanism · 00:51:00–00:55:00 · P

**Picture:** HX-700 mechanical inspector: stopped-rotor collective, fixed phase, neutral cyclic, both blade roots visible.

**Cast / paint:** HX-700 articulated mechanism — Native inspection layer; canopy hidden, roots visible. **Environment:** `inspector`.

**Preparation:** Open the native articulated HX-700 inspector. Select Cabeza, then enable main blades again. **At the edit’s start:** Neutral cyclic, 0 rpm, fixed 0° azimuth; both blade roots and the fixed mast visible.

**Blocking (model_local):** 0s: (0, 0, 0) Static mechanism-root anchor; no field position and no playable helicopter claim.

**Camera:** native_Cabeza_preset, inspector, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Use the real head preset, not invented external coordinates. Tighten only until both grips, links and fixed mast remain visible.

**Action:**

- 0–1 s: neutral reference.
- 1–3 s: move Colectivo toward the native +10° preset while cyclic stays neutral.
- 3–4 s: hold blade-root pitch; retain HX-700 · MECHANICAL INSPECTION throughout.

**Exit / cut:** Both blade roots visibly changed pitch without rotor rotation. Hard cut and new vehicle label before real X-Cell flight.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `inspector_adjustment` — `app/tools/inspect_hx700.gd`. Existing capture_hx700_mechanism.gd includes 12 rpm and cyclic motion; that old schedule is not this stopped-rotor take.

**Accept only when:** Native inspection/presentation motion and its disclosure are readable; no flight session is implied. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-21 — X-Cell .60 research helicopter · 00:55:00–00:59:00 · G

**Picture:** Clearly separate playable X-Cell .60: hover into forward flight past a landmark.

**Cast / paint:** X-Cell .60 research helicopter — Blanco Ártico. **Environment:** `day_calm`.

**Preparation:** Home X-Cell .60, Blanco Ártico, native pad N6 E0. Preroll: center cyclic/yaw, B arm, H release hold; wait for GOVERNED, lift and stabilize before the edit. **At the edit’s start:** Already hovering over the pad at target N6 E0 D−2.5, governor stabilized, neutral cyclic/yaw; the four-second shot starts here.

**Blocking (NED):** 0s: (6, 0, -2.5) → 1s: (6, 0, -2.5) → 4s: (6, 6, -2.5) Hover and forward-motion targets; actual initial heading and collective must be rehearsed. Estimated governor ramp is not squeezed into the clip.

**Camera:** fixed_tracking, NED, FOV 38°. 0s: (0, -3, -1.2) Fixed eye; pan/tilt to actual aircraft CG. Keep world horizon upright.

**Action:**

- 0–1 s: stable full helicopter hover.
- 1–4 s: gentle forward cyclic, starting with a modest input, then stabilize; no barrel roll.

**Exit / cut:** Helicopter visibly displaced past the pad landmark. Rotor sound hands over to Mustang prop sound.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `Home X-Cell .60 pad start and livery selection; manually staged hover/advance`. capture_vehicles.gd --vehicle=xcell-60-research --heli-shot=flight is an airborne-flight reference only: it hardcodes --start=airborne and has no --livery input. It needs adaptation for the specified pad, skin and governed preroll; no ready automation is claimed.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-22 — P-51D Mustang · 00:59:00–01:00:00 · G

**Picture:** P-51 clean external view establishes model, actual livery and direction.

**Cast / paint:** P-51D Mustang — P-51D Mustang factory. **Environment:** `day_calm`.

**Preparation:** One continuous Mustang factory-paint take; prepare genuine transmitter overlay before recording. **At the edit’s start:** Trimmed eastbound flight at target N20 and D−12; no second shipped Mustang paint exists.

**Blocking (NED):** 0s: (20, -75, -12) → 1s: (20, -50, -12) One-second clean lead plus five-second HUD section from the same six-second take at nominal source start speed 25 m/s.

**Camera:** subject_relative, FRU, FOV 38°. 0s: (-8, -5, 2.4) Track in heading frame. Look target slightly below CG so plane sits clear of bottom HUD; verify actual overlay readback.

**Action:**

- Keep the first second clean; add genuine HUD coverage at the next edit.

**Exit / cut:** Identity established. Continue same take into the HUD shot.

**Continuity:** One real take, factory Mustang, same camera and trim; overlay artwork alone makes no hardware-radio claim.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `existing_adapter` — `tools/trailer/capture_flight.gd overlay support + live session`. The live camera/input beat needs a focused director; do not use an invented physical-controller animation.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-23 — P-51D Mustang · 01:00:00–01:05:00 · G

**Picture:** P-51 live transmitter input and visible bank in one take; sparse real speed/height/fuel values.

**Cast / paint:** P-51D Mustang — P-51D Mustang factory. **Environment:** `day_calm`.

**Preparation:** One continuous Mustang factory-paint take; prepare genuine transmitter overlay before recording. **At the edit’s start:** Trimmed eastbound flight at target N20 and D−12; no second shipped Mustang paint exists.

**Blocking (NED):** 0s: (20, -50, -12) → 5s: (20, 75, -12) One-second clean lead plus five-second HUD section from the same six-second take at nominal source start speed 25 m/s.

**Camera:** subject_relative, FRU, FOV 38°. 0s: (-8, -5, 2.4) Track in heading frame. Look target slightly below CG so plane sits clear of bottom HUD; verify actual overlay readback.

**Action:**

- Explicitly enable transmitter; the Player preset omits it, application default pilot does not.
- After a short neutral reference, rehearse roll +0.25 for about 0.6 s, then center; preserve real input-to-bank relationship.
- Show only real speed/height/fuel values that fit the frame.

**Exit / cut:** Input and aircraft bank are visible together. Clear cut/title to the separate engine-out exercise.

**Continuity:** One real take, factory Mustang, same camera and trim; overlay artwork alone makes no hardware-radio claim.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `existing_adapter` — `tools/trailer/capture_flight.gd overlay support + live session`. The live camera/input beat needs a focused director; do not use an invented physical-controller animation.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-24 — Ugly Stick .61 glow · 01:05:00–01:07:00 · G

**Picture:** Separate supported-aircraft failure-practice flight: actual engine/motor power loss and real alert.

**Cast / paint:** Ugly Stick .61 glow — HONEYBEE · 07. **Environment:** `day_calm`.

**Preparation:** Separate ordinary glow Stick / HONEYBEE flight. Enable only eligible engine stop, 100%, Early, then launch anew. **At the edit’s start:** Fly a stable approach rehearsal. Actual failure timing is event-driven; source event and approach must belong to one recorded attempt.

**Blocking (NED):** 0s: (15, -140, -15) → 2s: (15, -112, -14) These are proposed onset/glide/landing framing volumes. They are excerpts separated by omitted flight time, not a forced eight-second continuous trajectory. Ground point is support map only.

**Camera:** fixed_tracking, NED, FOV 32°. 0s: (0, -30, -1.7) Fixed eye; pan/tilt to actual aircraft CG. Keep world horizon upright.

**Action:**

- Retain actual power-loss alert and real propulsion change.
- Do not schedule a fake stop at the desired point.

**Exit / cut:** Failure identified. Cut forward in the same attempt; retain FAILURE PRACTICE · ENGINE OUT.

**Continuity:** Same recorded practice attempt across 24–26, same HONEYBEE paint and wind. Failure is configured, not caused by later storm or a fabricated empty fuel gauge.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Generic capture_flight.gd hard-codes failures=0: do not use it unchanged for this scene. Use ordinary production failure settings or a later reviewed adapter.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-25 — Ugly Stick .61 glow · 01:07:00–01:10:00 · G

**Picture:** Same attempt: selected native-speed excerpt of the engine-out glide.

**Cast / paint:** Ugly Stick .61 glow — HONEYBEE · 07. **Environment:** `day_calm`.

**Preparation:** Separate ordinary glow Stick / HONEYBEE flight. Enable only eligible engine stop, 100%, Early, then launch anew. **At the edit’s start:** Fly a stable approach rehearsal. Actual failure timing is event-driven; source event and approach must belong to one recorded attempt.

**Blocking (NED):** 0s: (15, -94, -6) → 3s: (15, -58, -2.4) These are proposed onset/glide/landing framing volumes. They are excerpts separated by omitted flight time, not a forced eight-second continuous trajectory. Ground point is support map only.

**Camera:** fixed_tracking, NED, FOV 32°. 0s: (0, -30, -1.7) Fixed eye; pan/tilt to actual aircraft CG. Keep world horizon upright.

**Action:**

- Select a readable controlled glide excerpt from the same incident.
- Maintain actual speed/altitude evidence.

**Exit / cut:** Glide remains controlled. Cut forward in the same attempt; retain FAILURE PRACTICE · ENGINE OUT.

**Continuity:** Same recorded practice attempt across 24–26, same HONEYBEE paint and wind. Failure is configured, not caused by later storm or a fabricated empty fuel gauge.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Generic capture_flight.gd hard-codes failures=0: do not use it unchanged for this scene. Use ordinary production failure settings or a later reviewed adapter.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-26 — Ugly Stick .61 glow · 01:10:00–01:13:00 · G

**Picture:** Same attempt: flare, touchdown and controlled landing outcome.

**Cast / paint:** Ugly Stick .61 glow — HONEYBEE · 07. **Environment:** `day_calm`.

**Preparation:** Separate ordinary glow Stick / HONEYBEE flight. Enable only eligible engine stop, 100%, Early, then launch anew. **At the edit’s start:** Fly a stable approach rehearsal. Actual failure timing is event-driven; source event and approach must belong to one recorded attempt.

**Blocking (NE_surface):** 0s: (15, -47, 0) → 3s: (15, -15, 0) These are proposed onset/glide/landing framing volumes. They are excerpts separated by omitted flight time, not a forced eight-second continuous trajectory. Ground point is support map only.

**Camera:** fixed_tracking, NED, FOV 32°. 0s: (0, -30, -1.7) Fixed eye; pan/tilt to actual aircraft CG. Keep world horizon upright.

**Action:**

- Select flare, supported touchdown and roll-out from the same attempt.
- No reset or different successful landing substituted.

**Exit / cut:** Controlled touchdown visibly completed. Resolve landing, then open up to AI circuit traffic.

**Continuity:** Same recorded practice attempt across 24–26, same HONEYBEE paint and wind. Failure is configured, not caused by later storm or a fabricated empty fuel gauge.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Generic capture_flight.gd hard-codes failures=0: do not use it unchanged for this scene. Use ordinary production failure settings or a later reviewed adapter.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-27 — Ugly Stick .61 glow · 01:13:00–01:17:00 · G

**Picture:** Calm Club-field flight with actual AI Ugly Stik circuit companions; no close-formation promise.

**Cast / paint:** Ugly Stick .61 glow — HONEYBEE · 07. **Environment:** `day_calm`.

**Preparation:** Club field, HONEYBEE player aircraft; enable accepted AI companion count/profile and read actual admission. **At the edit’s start:** Player crosses in front of real autonomous Ugly Stik circuits; no formation placement.

**Blocking (NED):** 0s: (25, -30, -8) → 4s: (25, 30, -8) Only player corridor is proposed. Companion coordinates remain their admitted autonomous circuit.

**Camera:** fixed_tracking, NED, FOV 28°. 0s: (0, 0, -1.7) Fixed eye; pan/tilt to actual aircraft CG. Keep world horizon upright.

**Action:**

- Keep player large enough to distinguish its HONEYBEE paint.
- Select a real interval when companions are separately readable.
- Hold AI FLIGHT COMPANIONS label; calm conditions and normal stock route.

**Exit / cut:** Player and at least one companion can both be identified. Hard cut from 3D Club field to labelled imported panorama.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `existing_adapter` — `capture_flight.gd normal lighting route + accepted companions`. Companion qualification depends on the exact source/build; current branch must pass its ordinary admission. Do not use Workshop lighting route or re-pin acceptance.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-28 — Ugly Stick .61 glow · 01:17:00–01:21:00 · G

**Picture:** Eligible airplane in an exact calibrated Phoenix panorama; fixed pilot-eye view and experimental-runway label.

**Cast / paint:** Ugly Stick .61 glow — HONEYBEE · 07. **Environment:** `phoenix_airfield`.

**Preparation:** Import/select exact calibrated Airfield panorama; confirm matching hash and experimental runway admission. **At the edit’s start:** Photo-eye remains at N0 E0, eye height 1.7 m in this separate field coordinate system.

**Blocking (NED):** 0s: (12, -29, -4) → 4s: (12, 31, -4) This field runway is centered N12 E1, length 42 m, width 9 m. Corridor extends beyond runway ends in the image; actual collision/imagery fit must pass.

**Camera:** fixed_tracking, NED, FOV 40°. 0s: (0, 0, -1.7) Keep the calibrated photo eye fixed; pan direction only. No translated orbit or parallax claim.

**Action:**

- Launch supported runway aircraft through the real imported-site flow.
- Retain four seconds of a readable pass and IMPORTED SCENERY · EXPERIMENTAL RUNWAY.

**Exit / cut:** Aircraft remains identifiable against panorama. Hard cut to separately configured storm flight.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Calibrated source entry exists; installed local panorama and usable source images are not supplied by this plan.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-29 — P-51D Mustang · 01:21:00–01:25:00 · G

**Picture:** Separate ordinary airplane flight against an actual storm cloud flash; bolt only if recorded.

**Cast / paint:** P-51D Mustang — P-51D Mustang factory. **Environment:** `storm`.

**Preparation:** Ordinary Mustang factory-paint flight, electrical_storm appearance preset; no configured practice failure. **At the edit’s start:** Trim in a clear-air corridor with dark clouds behind the aircraft; record until an actual flash occurs.

**Blocking (NED):** 0s: (60, -50, -20) → 4s: (60, 50, -20) Nominal four-second corridor at source start speed; choose the real flash interval, not an invented time trigger.

**Camera:** subject_relative, FRU, FOV 36°. 0s: (10, -7, 3) FRU = forward/right/up metres in horizontal heading frame; follow actual subject, not its roll. This is a camera target, not a new player camera.

**Action:**

- Keep readable model body against the cloud bank.
- Select actual flash and native storm audio if present.
- A visible bolt is optional; no added lightning graphic.

**Exit / cut:** Flash resolves while plane remains readable. Cut on brightness into warm Extra smoke.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `existing_adapter` — `capture_flight.gd --shot=storm`. Existing adapter uses the real sky preset; specific framing and event interval require rehearsal.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-30 — Extra 300S · 01:25:00–01:29:00 · G

**Picture:** Extra 300S: warm-light bank/climb in its shipped factory finish with a qualified show-smoke profile.

**Cast / paint:** Extra 300S — Extra 300S factory. **Environment:** `golden_calm`.

**Preparation:** Extra factory paint; admit authored stock show-smoke profile and actual pump control. **At the edit’s start:** Establish smoke before selected clip; aircraft enters in a gentle climbing bank.

**Blocking (NED):** 0s: (30, -44, -10) → 2s: (34, 0, -13) → 4s: (43, 40, -18) Climbing arc is a proposed composition; speed and bank are pilot-controlled, not animated positions.

**Camera:** subject_relative, FRU, FOV 36°. 0s: (-9, -6, 3) FRU = forward/right/up metres in horizontal heading frame; follow actual subject, not its roll. This is a camera target, not a new player camera.

**Action:**

- Preroll until plume is established and real outlet/color verified.
- Use one climbing bank, not a compressed multiple-roll stunt.
- Leave breathing room behind tail for the actual plume.

**Exit / cut:** Plane and smoke arc remain in frame. Match bank/airframe size into Lumber night pass.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `existing_adapter` — `capture_flight.gd + stock smoke / existing Extra director`. Select and verify an existing supported show-smoke color; no custom color/paint is claimed from its name alone.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-31 — Turbo Lumber Evolution · 01:29:00–01:33:00 · G

**Picture:** Turbo Lumber: readable body and actual night lights; moon, field lights or campfire only if composition remains clear.

**Cast / paint:** Turbo Lumber Evolution — Turbo Lumber factory. **Environment:** `night_calm`.

**Preparation:** Turbo Lumber factory paint, supported Night Radian lights; full-moon night in a separate session. **At the edit’s start:** Body, wing and genuine lights visible before first retained frame.

**Blocking (NED):** 0s: (25, -26.2, -6) → 4s: (25, 26.2, -6) Nominal distance uses ~13.1 m/s configured start speed; actual flight readback owns the take.

**Camera:** subject_relative, FRU, FOV 37°. 0s: (6, -5, 1.8) FRU = forward/right/up metres in horizontal heading frame; follow actual subject, not its roll. This is a camera target, not a new player camera.

**Action:**

- Use a calm pass; do not bury the airframe in darkness.
- Keep actual navigation/lighting behavior; no glowing-dot-only composition.
- If night cannot expose the body, use the declared blue-hour replacement and update metadata.

**Exit / cut:** Last frame still identifies Turbo Lumber. Match lower-body detail into Bisonte suspension.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `existing_adapter` — `capture_flight.gd + Lumber lighting/director route`. Existing dusk director supplies a useful camera; exact night preset and body exposure still require footage.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-32 — MT8 Bisonte · 01:33:00–01:35:45 · G

**Picture:** Bisonte Physics Lab comparison: baseline suspension response over a fixed bump.

**Cast / paint:** MT8 Bisonte — Amarillo Rayo. **Environment:** `day_calm`.

**Preparation:** Bisonte Amarillo Rayo, same track_start, camera and input program for both independent runs. **At the edit’s start:** Baseline damping 1.00 for R4-32; changed damping 1.50 for R4-34. Other Lab knobs remain 1.00/default with zero ballast.

**Blocking (NE_surface):** 0s: (39, -7, 0) → 1.35s: (39, -4, 0) → 2.75s: (39, -1, 0) Same bump, same actual approach-speed target. These timestamps are framing targets; physical response must be observed.

**Camera:** fixed_tracking, NED, FOV 38°. 0s: (35, -4, -0.25) Exact same low side eye/FOV for both takes; tire contact and body heave visible.

**Action:**

- Accelerate from the same supported spawn and reproduce the approach input.
- Retain compression and rebound, not only airborne frames.
- Measure/read back actual approach speeds; do not claim improvement from unequal runs.

**Exit / cut:** Suspension response visibly settles. Hard cut to actual Lab UI.

**Continuity:** Same truck paint, bump, wind, camera, input source and scale; separate reset/prepared sessions explicitly labelled BASELINE and CHANGED SETUP.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-33 — MT8 Bisonte · 01:35:45–01:37:15 · U

**Picture:** Actual paused lab setting/application excerpt; setup/reset time is omitted between the two runs.

**Cast / paint:** MT8 Bisonte — Amarillo Rayo. **Environment:** `day_calm`.

**Preparation:** Pause the actual Bisonte Lab flow between the two comparison runs. **At the edit’s start:** Damping slider reads 1.00; all other experiment controls unchanged.

**Blocking (none):** Native UI/preset or actual camera readback; no invented world coordinates.

**Camera:** actual_UI, none, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Crop only enough to keep Damping and apply action legible.

**Action:**

- Select Damping (damper_scale) 1.50, within source range 0.25–2.00.
- Show actual apply/preparation excerpt; omit waiting/reset time openly.

**Exit / cut:** Applied experiment is read back as damping 1.50. Cut to separately prepared changed-setting run.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Source apply prepares/restarts the session; there is no live in-air parameter change.

**Accept only when:** Genuine UI state, selected values and completed loading are readable; no advancing flight tick is required. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-34 — MT8 Bisonte · 01:37:15–01:40:00 · G

**Picture:** Second real Bisonte run: changed suspension setting, same bump and comparable camera/input.

**Cast / paint:** MT8 Bisonte — Amarillo Rayo. **Environment:** `day_calm`.

**Preparation:** Bisonte Amarillo Rayo, same track_start, camera and input program for both independent runs. **At the edit’s start:** Baseline damping 1.00 for R4-32; changed damping 1.50 for R4-34. Other Lab knobs remain 1.00/default with zero ballast.

**Blocking (NE_surface):** 0s: (39, -7, 0) → 1.35s: (39, -4, 0) → 2.75s: (39, -1, 0) Same bump, same actual approach-speed target. These timestamps are framing targets; physical response must be observed.

**Camera:** fixed_tracking, NED, FOV 38°. 0s: (35, -4, -0.25) Exact same low side eye/FOV for both takes; tire contact and body heave visible.

**Action:**

- Accelerate from the same supported spawn and reproduce the approach input.
- Retain compression and rebound, not only airborne frames.
- Measure/read back actual approach speeds; do not claim improvement from unequal runs.

**Exit / cut:** Suspension response visibly settles. Cut to Workshop size control.

**Continuity:** Same truck paint, bump, wind, camera, input source and scale; separate reset/prepared sessions explicitly labelled BASELINE and CHANGED SETUP.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-35 — Ugly Stick .61 glow · 01:40:00–01:41:30 · U

**Picture:** Baseline .61 glow Ugly Stick: actual Workshop scale control.

**Cast / paint:** Ugly Stick .61 glow — HONEYBEE · 07. **Environment:** `day_calm`.

**Preparation:** Open Workshop for baseline glow Stick / HONEYBEE. **At the edit’s start:** Show actual scale selector; prepare distinct 500% and 10% trials.

**Blocking (none):** Native UI/preset or actual camera readback; no invented world coordinates.

**Camera:** actual_UI, none, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Keep scale control and aircraft identity readable.

**Action:**

- Show the real scale control and value change.
- Setup time and separate trial preparation are omitted by the edit.

**Exit / cut:** Actual 500% choice visible before giant flight. Cut to real giant trial.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Genuine UI state, selected values and completed loading are readable; no advancing flight tick is required. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-36 — Ugly Stick .61 glow · 01:41:30–01:43:15 · G

**Picture:** Actual 500% baseline Stick trial by a fixed landmark.

**Cast / paint:** Ugly Stick .61 glow — HONEYBEE · 07. **Environment:** `day_calm`.

**Preparation:** Freeze actual 500% Workshop trial; preserve HONEYBEE presentation. **At the edit’s start:** Airborne giant trial before the cut; retain field/runway as familiar scale context.

**Blocking (NED):** 0s: (30, -30, -8) → 1.75s: (30, 30, -8) Large-model corridor is a rehearsal target. Actual scaled trim/speed must be read from the trial; no original-size speed is imposed.

**Camera:** fixed_tracking, NED, FOV 40°. 0s: (12, 0, -1.4) Wide framing fits 7.62 m approximate span and runway context; not the tiny take camera.

**Action:**

- Record actual 500% flight behavior at native speed.
- Keep GIANT · 500% / approx. 7.62 m readable.

**Exit / cut:** Whole giant model remains visible. Cut to tighter real tiny trial, retaining explicit size label.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `existing_adapter` — `capture_flight.gd --workshop-scale=5 + validated lighting preset`. Real trial and cinematic trio are separate sources; framing changes are explicit.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-37 — Ugly Stick .61 glow · 01:43:15–01:45:00 · G

**Picture:** Actual 10% baseline Stick trial in a deliberately closer readable view, with explicit size label and field context.

**Cast / paint:** Ugly Stick .61 glow — HONEYBEE · 07. **Environment:** `day_calm`.

**Preparation:** Freeze actual 10% Workshop trial from same baseline and paint. **At the edit’s start:** Tiny trial passes near a recognizable ordinary field marker; verify body is findable.

**Blocking (NED):** 0s: (30, -4, -1.5) → 1.75s: (30, 4, -1.5) Eight-metre proposed corridor; actual scaled speed and safe clearance need trial evidence.

**Camera:** fixed_tracking, NED, FOV 30°. 0s: (27, 0, -0.9) Closer optical view makes the 15 cm approximate span readable. Different framing is intentional; no equal-camera size inference.

**Action:**

- Record the real 10% trial without speed-up.
- Keep TINY · 10% / approx. 15 cm on screen.

**Exit / cut:** Tiny aircraft can be recognized in full-motion playback. Cut to the disclosed same-depth comparator.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `existing_adapter` — `capture_flight.gd --workshop-scale=0.1 + validated lighting preset`. Size comparison is established by values, field context and the next same-depth presentation, not matched framing of these two trials.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-38 — Ugly Stick .61 glow · 01:45:00–01:49:00 · P

**Picture:** Same-depth 500/100/10% cinematic comparator; correct span labels and disclosure.

**Cast / paint:** Ugly Stick .61 glow — HONEYBEE · 07. **Environment:** `editorial`.

**Preparation:** Use existing three-size presentation scene; all three represent the same glow Stick baseline. **At the edit’s start:** Giant / Original / Tiny at one depth, with labels 7.62 m / 1.52 m / 15 cm.

**Blocking (model_local):** 0s: (0, 0, 0) Formation origin only. Existing --sizes layout owns separation; log actual model/paint identity before acceptance.

**Camera:** existing_sizes_director, FRU, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Use the existing same-depth layout and move toward original/tiny; actual camera sample/trim remains to be selected.

**Action:**

- Hold enough of all three to read the ratio before moving closer.
- Keep CINEMATIC SIZE COMPARISON throughout.

**Exit / cut:** All three sizes and disclosure have been readable. Match central aircraft into Corsair hero orbit.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `existing_adapter` — `tools/trailer/capture_formation.gd --sizes`. Existing comparator skin must be verified/adapted to HONEYBEE or explicitly recorded as factory; plan does not apply a new paint to this adapter.

**Accept only when:** Native inspection/presentation motion and its disclosure are readable; no flight session is implied. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-39 — F4U Corsair · 01:49:00–01:59:00 · P

**Picture:** Continuous eased Corsair orbit with all 13 stock liveries; final scheme holds.

**Cast / paint:** F4U Corsair — Coastal Three Tone. **Environment:** `golden_calm`.

**Preparation:** Corsair airborne, wings spread, gear/flaps/hook retracted, canopy closed. Load full ordered 13-asset cycle. **At the edit’s start:** Real session established before recording; camera settles into front-left quarter.

**Blocking (NED):** 0s: (15, -115, -6) → 5s: (36, -2.5, -6) → 10s: (96, 95, -6) Illustrative turning corridor for the existing light-left-bank director (~9.7°), not a straight 230 m rail. Coordinates are proposed and unflown; actual heading/track must be logged.

**Camera:** continuous_heading_orbit, FRU, FOV 34°. 0s: (5.3623, -4.4995, 0.9) → 5s: (-5.3623, 4.4995, 1.4) → 10s: (5.3623, -4.4995, 0.9) Existing _orbit_camera is relative to the visual model-root origin, not simulated CG: 7 m radius, angle −40° + 360° smoothstep(t/10); height 0.9 + 0.5 sin(pi*p); look 0.2 m above visual root. These three samples illustrate the analytic orbit, not linear interpolation.

**Action:**

- Show twelve 45-frame planned skin holds, then a 60-frame Coastal Three Tone finish.
- Use the new --livery-hold-last flag so the visual cycle never returns to midnight at 9.75 s.
- Check actual simulation-time/presented-frame alignment; the driver clock and edit clock are different.

**Exit / cut:** Final presented paint is three_tone; framing returns to front-left quarter. Hard cut to lake with same paint and compatible nose orientation; a separately filmed pass is allowed.

**Continuity:** Only livery assets change inside the orbit; no airframe, scale, gear, canopy, weather or camera-path jump. Ground and final lake use the same Coastal Three Tone asset.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `existing_adapter` — `tools/trailer/capture_flight.gd --shot=corsair-orbit + flight_director.gd`. Exact new entry coordinates need a reviewed pre-start fixture; existing orbit flight and camera already exist. Hold-last is implemented/tested, footage timing remains unqualified.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-40 — F4U Corsair · 01:59:00–02:05:00 · G

**Picture:** Six uninterrupted seconds of Corsair shoreline approach, water crossing and exit, holding Coastal Three Tone and actual matching reflection if qualified.

**Cast / paint:** F4U Corsair — Coastal Three Tone. **Environment:** `golden_calm`.

**Preparation:** Separate real Corsair pass, Coastal Three Tone, same golden-hour exposure and clean flight configuration. **At the edit’s start:** Rehearsal entry mark N128 E55 D−2.55, heading east. Preroll target N128 E9 at the same height, nominally two seconds earlier.

**Blocking (NED):** 0s: (128, 55, -2.55) → 3s: (128, 124, -2.55) → 6s: (128, 193, -2.55) 138 m straight reference corridor at 23 m/s configured start speed. D−2.55 is 3 m above mean water D+0.45, not 3 m above lakebed. Actual flight/terrain clearance remains unverified.

**Camera:** parallel_east, NED, FOV 42°. 0s: (145, 47, -1) → 3s: (145, 116, -1) → 6s: (145, 185, -1) Parallel north-bank dolly: fixed N145 and D−1; E follows actual presented CG east minus 8 m. Listed eyes correspond only to nominal subject marks. CG stays near frame center, the eastbound nose points screen-left and shoreline/background moves. No smoothing, time warp or scripted aircraft pose. Check actual clearance and reflection.

**Action:**

- 0–about 1.47 s nominal: land/shore approach into the lake composition.
- About 1.47–4.69 s nominal: cross water between E≈88.73 and E≈162.91.
- Last ~1.31 s nominal: clear the far shoreline while the camera continues alongside the actual aircraft; cut on a readable settled silhouette.

**Exit / cut:** Aircraft clears water and shoreline with the final skin unchanged. Cut after the pass resolves to genuine Creator interface; no added slogan over the lake.

**Continuity:** Coastal Three Tone, closed canopy, spread wings, clean gear/flaps/hook. Match dominant nose orientation and color; this is an edited transition from orbit, not proof of a continuous world trajectory.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `camera_adapter_implemented_flight_pending` — `capture_flight.gd --camera-recipe plus an explicitly qualified pilot director / real flown approach`. R6 exports a presentation-only parallel camera. It does not spawn at N128/E9, fly the route, select the skin or certify height above water. Existing generic pilot logic is not a qualified lake driver; use a real flown approach or a later reviewed pre-tree fixture. Never mutate live aircraft pose per frame.

**Accept only when:** Nominal geometry gives only ~3.23 s above water, not six; actual speed/path govern footage. Check actual CG, wingtip and prop clearance against water/shore/objects. Reflection must be from the same real frame and paint; keep an honest unmirrored take if it fails. Read camera recipe, source-plan hash, actual eye/CG/FOV and advancing ticks from the take manifest. Reject faults, pause, crash, stale camera records or unexplained trajectory drift. Match final orbit nose orientation to the accepted lake take. Actual subject/HUD readability and camera/shoreline clearance require rendered footage.

### R4-41 — Brand/end card · 02:05:00–02:07:00 · U

**Picture:** Genuine Creator import/source-selection excerpt; edited introduction to both source families.

**Cast / paint:** Brand/end card — Not applicable. **Environment:** `creator`.

**Preparation:** Open Aircraft Creator through the real menu; prepare permitted local Phoenix/ClearView sources. **At the edit’s start:** Readable genuine import/source controls; EXPAND YOUR HANGAR title in a clear area.

**Blocking (none):** Native UI/preset or actual camera readback; no invented world coordinates.

**Camera:** actual_UI, none, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Use actual preview/interface crop; title does not hide selected source type.

**Action:**

- Show the real source/import workflow for two seconds.
- Conversion and file-selection waiting are omitted by the edit.

**Exit / cut:** Viewer understands that this is an import feature. Cut to Easystar preview on the first strong editorial accent.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Genuine UI state, selected values and completed loading are readable; no advancing flight tick is required. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-42a — Easystar · 02:07:00–02:08:00 · U

**Picture:** Phoenix RC imported preview: Easystar; provisional casting, exact source and new visual acceptance required.

**Cast / paint:** Easystar — Original admitted source textures; source hash and exact texture identity pending.. **Environment:** `creator`.

**Preparation:** Admit exact local source and textures for Easystar; retain input/model-root hashes. **At the edit’s start:** Actual Creator preview is fully loaded and stable before the selected frames.

**Blocking (model_local):** 0s: (0, 0, 0) Use actual preview bounds center; numeric zero is local model-centered framing, not a new field spawn.

**Camera:** native_preview_three_quarter, preview, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Target a nose-right three-quarter view, about 25° yaw / 15° elevation from front, ~70% frame-width occupancy. Use native preview orbit/fit and record resulting camera; angles are composition targets, not implemented UI numeric controls.

**Action:**

- Hold native proportions and original source texture set.
- Retain 60 planned frames; persistent PHOENIX RC · MODEL PREVIEWS label.
- No model-name flash; use a hard cut to the next silhouette.

**Exit / cut:** Model complete and readable; no loading texture or clipping. Hard cut to next admitted preview.

**Continuity:** Same preview background, apparent center and exposure; normalize framing, not physical size. Source-family blocks remain contiguous.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42b — J3 Piper Cub · 02:08:00–02:08:30 · U

**Picture:** Phoenix RC imported preview: J3 Piper Cub; provisional casting, exact source and new visual acceptance required.

**Cast / paint:** J3 Piper Cub — Original admitted source textures; source hash and exact texture identity pending.. **Environment:** `creator`.

**Preparation:** Admit exact local source and textures for J3 Piper Cub; retain input/model-root hashes. **At the edit’s start:** Actual Creator preview is fully loaded and stable before the selected frames.

**Blocking (model_local):** 0s: (0, 0, 0) Use actual preview bounds center; numeric zero is local model-centered framing, not a new field spawn.

**Camera:** native_preview_three_quarter, preview, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Target a nose-right three-quarter view, about 25° yaw / 15° elevation from front, ~70% frame-width occupancy. Use native preview orbit/fit and record resulting camera; angles are composition targets, not implemented UI numeric controls.

**Action:**

- Hold native proportions and original source texture set.
- Retain 30 planned frames; persistent PHOENIX RC · MODEL PREVIEWS label.
- No model-name flash; use a hard cut to the next silhouette.

**Exit / cut:** Model complete and readable; no loading texture or clipping. Hard cut to next admitted preview.

**Continuity:** Same preview background, apparent center and exposure; normalize framing, not physical size. Source-family blocks remain contiguous.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42c — Fokker DR-1 · 02:08:30–02:09:00 · U

**Picture:** Phoenix RC imported preview: Fokker DR-1; provisional casting, exact source and new visual acceptance required.

**Cast / paint:** Fokker DR-1 — Original admitted source textures; source hash and exact texture identity pending.. **Environment:** `creator`.

**Preparation:** Admit exact local source and textures for Fokker DR-1; retain input/model-root hashes. **At the edit’s start:** Actual Creator preview is fully loaded and stable before the selected frames.

**Blocking (model_local):** 0s: (0, 0, 0) Use actual preview bounds center; numeric zero is local model-centered framing, not a new field spawn.

**Camera:** native_preview_three_quarter, preview, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Target a nose-right three-quarter view, about 25° yaw / 15° elevation from front, ~70% frame-width occupancy. Use native preview orbit/fit and record resulting camera; angles are composition targets, not implemented UI numeric controls.

**Action:**

- Hold native proportions and original source texture set.
- Retain 30 planned frames; persistent PHOENIX RC · MODEL PREVIEWS label.
- No model-name flash; use a hard cut to the next silhouette.

**Exit / cut:** Model complete and readable; no loading texture or clipping. Hard cut to next admitted preview.

**Continuity:** Same preview background, apparent center and exposure; normalize framing, not physical size. Source-family blocks remain contiguous.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42d — Radian · 02:09:00–02:09:30 · U

**Picture:** Phoenix RC imported preview: Radian; provisional casting, exact source and new visual acceptance required.

**Cast / paint:** Radian — Original admitted source textures; source hash and exact texture identity pending.. **Environment:** `creator`.

**Preparation:** Admit exact local source and textures for Radian; retain input/model-root hashes. **At the edit’s start:** Actual Creator preview is fully loaded and stable before the selected frames.

**Blocking (model_local):** 0s: (0, 0, 0) Use actual preview bounds center; numeric zero is local model-centered framing, not a new field spawn.

**Camera:** native_preview_three_quarter, preview, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Target a nose-right three-quarter view, about 25° yaw / 15° elevation from front, ~70% frame-width occupancy. Use native preview orbit/fit and record resulting camera; angles are composition targets, not implemented UI numeric controls.

**Action:**

- Hold native proportions and original source texture set.
- Retain 30 planned frames; persistent PHOENIX RC · MODEL PREVIEWS label.
- No model-name flash; use a hard cut to the next silhouette.

**Exit / cut:** Model complete and readable; no loading texture or clipping. Hard cut to next admitted preview.

**Continuity:** Same preview background, apparent center and exposure; normalize framing, not physical size. Source-family blocks remain contiguous.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42e — Spitfire · 02:09:30–02:10:00 · U

**Picture:** Phoenix RC imported preview: Spitfire; provisional casting, exact source and new visual acceptance required.

**Cast / paint:** Spitfire — Original admitted source textures; source hash and exact texture identity pending.. **Environment:** `creator`.

**Preparation:** Admit exact local source and textures for Spitfire; retain input/model-root hashes. **At the edit’s start:** Actual Creator preview is fully loaded and stable before the selected frames.

**Blocking (model_local):** 0s: (0, 0, 0) Use actual preview bounds center; numeric zero is local model-centered framing, not a new field spawn.

**Camera:** native_preview_three_quarter, preview, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Target a nose-right three-quarter view, about 25° yaw / 15° elevation from front, ~70% frame-width occupancy. Use native preview orbit/fit and record resulting camera; angles are composition targets, not implemented UI numeric controls.

**Action:**

- Hold native proportions and original source texture set.
- Retain 30 planned frames; persistent PHOENIX RC · MODEL PREVIEWS label.
- No model-name flash; use a hard cut to the next silhouette.

**Exit / cut:** Model complete and readable; no loading texture or clipping. Hard cut to next admitted preview.

**Continuity:** Same preview background, apparent center and exposure; normalize framing, not physical size. Source-family blocks remain contiguous.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42f — Beaver Float-plane · 02:10:00–02:10:30 · U

**Picture:** Phoenix RC imported preview: Beaver Float-plane; provisional casting, exact source and new visual acceptance required.

**Cast / paint:** Beaver Float-plane — Original admitted source textures; source hash and exact texture identity pending.. **Environment:** `creator`.

**Preparation:** Admit exact local source and textures for Beaver Float-plane; retain input/model-root hashes. **At the edit’s start:** Actual Creator preview is fully loaded and stable before the selected frames.

**Blocking (model_local):** 0s: (0, 0, 0) Use actual preview bounds center; numeric zero is local model-centered framing, not a new field spawn.

**Camera:** native_preview_three_quarter, preview, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Target a nose-right three-quarter view, about 25° yaw / 15° elevation from front, ~70% frame-width occupancy. Use native preview orbit/fit and record resulting camera; angles are composition targets, not implemented UI numeric controls.

**Action:**

- Hold native proportions and original source texture set.
- Retain 30 planned frames; persistent PHOENIX RC · MODEL PREVIEWS label.
- No model-name flash; use a hard cut to the next silhouette.

**Exit / cut:** Model complete and readable; no loading texture or clipping. Hard cut to next admitted preview.

**Continuity:** Same preview background, apparent center and exposure; normalize framing, not physical size. Source-family blocks remain contiguous.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42g — Tiger Moth · 02:10:30–02:11:00 · U

**Picture:** Phoenix RC imported preview: Tiger Moth; provisional casting, exact source and new visual acceptance required.

**Cast / paint:** Tiger Moth — Original admitted source textures; source hash and exact texture identity pending.. **Environment:** `creator`.

**Preparation:** Admit exact local source and textures for Tiger Moth; retain input/model-root hashes. **At the edit’s start:** Actual Creator preview is fully loaded and stable before the selected frames.

**Blocking (model_local):** 0s: (0, 0, 0) Use actual preview bounds center; numeric zero is local model-centered framing, not a new field spawn.

**Camera:** native_preview_three_quarter, preview, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Target a nose-right three-quarter view, about 25° yaw / 15° elevation from front, ~70% frame-width occupancy. Use native preview orbit/fit and record resulting camera; angles are composition targets, not implemented UI numeric controls.

**Action:**

- Hold native proportions and original source texture set.
- Retain 30 planned frames; persistent PHOENIX RC · MODEL PREVIEWS label.
- No model-name flash; use a hard cut to the next silhouette.

**Exit / cut:** Model complete and readable; no loading texture or clipping. Hard cut to next admitted preview.

**Continuity:** Same preview background, apparent center and exposure; normalize framing, not physical size. Source-family blocks remain contiguous.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42h — Extra · 02:11:00–02:11:30 · U

**Picture:** Phoenix RC imported preview: Extra; provisional casting, exact source and new visual acceptance required.

**Cast / paint:** Extra — Original admitted source textures; source hash and exact texture identity pending.. **Environment:** `creator`.

**Preparation:** Admit exact local source and textures for Extra; retain input/model-root hashes. **At the edit’s start:** Actual Creator preview is fully loaded and stable before the selected frames.

**Blocking (model_local):** 0s: (0, 0, 0) Use actual preview bounds center; numeric zero is local model-centered framing, not a new field spawn.

**Camera:** native_preview_three_quarter, preview, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Target a nose-right three-quarter view, about 25° yaw / 15° elevation from front, ~70% frame-width occupancy. Use native preview orbit/fit and record resulting camera; angles are composition targets, not implemented UI numeric controls.

**Action:**

- Hold native proportions and original source texture set.
- Retain 30 planned frames; persistent PHOENIX RC · MODEL PREVIEWS label.
- No model-name flash; use a hard cut to the next silhouette.

**Exit / cut:** Model complete and readable; no loading texture or clipping. Hard cut to next admitted preview.

**Continuity:** Same preview background, apparent center and exposure; normalize framing, not physical size. Source-family blocks remain contiguous.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42i — P-51 Mustang · 02:11:30–02:12:00 · U

**Picture:** Phoenix RC imported preview: P-51 Mustang; provisional casting, exact source and new visual acceptance required.

**Cast / paint:** P-51 Mustang — Original admitted source textures; source hash and exact texture identity pending.. **Environment:** `creator`.

**Preparation:** Admit exact local source and textures for P-51 Mustang; retain input/model-root hashes. **At the edit’s start:** Actual Creator preview is fully loaded and stable before the selected frames.

**Blocking (model_local):** 0s: (0, 0, 0) Use actual preview bounds center; numeric zero is local model-centered framing, not a new field spawn.

**Camera:** native_preview_three_quarter, preview, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Target a nose-right three-quarter view, about 25° yaw / 15° elevation from front, ~70% frame-width occupancy. Use native preview orbit/fit and record resulting camera; angles are composition targets, not implemented UI numeric controls.

**Action:**

- Hold native proportions and original source texture set.
- Retain 30 planned frames; persistent PHOENIX RC · MODEL PREVIEWS label.
- No model-name flash; use a hard cut to the next silhouette.

**Exit / cut:** Model complete and readable; no loading texture or clipping. Hard cut to next admitted preview.

**Continuity:** Same preview background, apparent center and exposure; normalize framing, not physical size. Source-family blocks remain contiguous.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42j — F-117 · 02:12:00–02:13:00 · U

**Picture:** ClearView imported preview: F-117; provisional casting, exact source and new visual acceptance required.

**Cast / paint:** F-117 — Original admitted source textures; source hash and exact texture identity pending.. **Environment:** `creator`.

**Preparation:** Admit exact local source and textures for F-117; retain input/model-root hashes. **At the edit’s start:** Actual Creator preview is fully loaded and stable before the selected frames.

**Blocking (model_local):** 0s: (0, 0, 0) Use actual preview bounds center; numeric zero is local model-centered framing, not a new field spawn.

**Camera:** native_preview_three_quarter, preview, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Target a nose-right three-quarter view, about 25° yaw / 15° elevation from front, ~70% frame-width occupancy. Use native preview orbit/fit and record resulting camera; angles are composition targets, not implemented UI numeric controls.

**Action:**

- Hold native proportions and original source texture set.
- Retain 60 planned frames; persistent CLEARVIEW · MODEL PREVIEWS label.
- No model-name flash; use a hard cut to the next silhouette.

**Exit / cut:** Model complete and readable; no loading texture or clipping. Hard cut to next admitted preview.

**Continuity:** Same preview background, apparent center and exposure; normalize framing, not physical size. Source-family blocks remain contiguous.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42k — BD-5J · 02:13:00–02:13:30 · U

**Picture:** ClearView imported preview: BD-5J; provisional casting, exact source and new visual acceptance required.

**Cast / paint:** BD-5J — Original admitted source textures; source hash and exact texture identity pending.. **Environment:** `creator`.

**Preparation:** Admit exact local source and textures for BD-5J; retain input/model-root hashes. **At the edit’s start:** Actual Creator preview is fully loaded and stable before the selected frames.

**Blocking (model_local):** 0s: (0, 0, 0) Use actual preview bounds center; numeric zero is local model-centered framing, not a new field spawn.

**Camera:** native_preview_three_quarter, preview, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Target a nose-right three-quarter view, about 25° yaw / 15° elevation from front, ~70% frame-width occupancy. Use native preview orbit/fit and record resulting camera; angles are composition targets, not implemented UI numeric controls.

**Action:**

- Hold native proportions and original source texture set.
- Retain 30 planned frames; persistent CLEARVIEW · MODEL PREVIEWS label.
- No model-name flash; use a hard cut to the next silhouette.

**Exit / cut:** Model complete and readable; no loading texture or clipping. Hard cut to next admitted preview.

**Continuity:** Same preview background, apparent center and exposure; normalize framing, not physical size. Source-family blocks remain contiguous.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42l — B-25 · 02:13:30–02:14:00 · U

**Picture:** ClearView imported preview: B-25; provisional casting, exact source and new visual acceptance required.

**Cast / paint:** B-25 — Original admitted source textures; source hash and exact texture identity pending.. **Environment:** `creator`.

**Preparation:** Admit exact local source and textures for B-25; retain input/model-root hashes. **At the edit’s start:** Actual Creator preview is fully loaded and stable before the selected frames.

**Blocking (model_local):** 0s: (0, 0, 0) Use actual preview bounds center; numeric zero is local model-centered framing, not a new field spawn.

**Camera:** native_preview_three_quarter, preview, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Target a nose-right three-quarter view, about 25° yaw / 15° elevation from front, ~70% frame-width occupancy. Use native preview orbit/fit and record resulting camera; angles are composition targets, not implemented UI numeric controls.

**Action:**

- Hold native proportions and original source texture set.
- Retain 30 planned frames; persistent CLEARVIEW · MODEL PREVIEWS label.
- No model-name flash; use a hard cut to the next silhouette.

**Exit / cut:** Model complete and readable; no loading texture or clipping. Hard cut to next admitted preview.

**Continuity:** Same preview background, apparent center and exposure; normalize framing, not physical size. Source-family blocks remain contiguous.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42m — C-130 · 02:14:00–02:14:30 · U

**Picture:** ClearView imported preview: C-130; provisional casting, exact source and new visual acceptance required.

**Cast / paint:** C-130 — Original admitted source textures; source hash and exact texture identity pending.. **Environment:** `creator`.

**Preparation:** Admit exact local source and textures for C-130; retain input/model-root hashes. **At the edit’s start:** Actual Creator preview is fully loaded and stable before the selected frames.

**Blocking (model_local):** 0s: (0, 0, 0) Use actual preview bounds center; numeric zero is local model-centered framing, not a new field spawn.

**Camera:** native_preview_three_quarter, preview, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Target a nose-right three-quarter view, about 25° yaw / 15° elevation from front, ~70% frame-width occupancy. Use native preview orbit/fit and record resulting camera; angles are composition targets, not implemented UI numeric controls.

**Action:**

- Hold native proportions and original source texture set.
- Retain 30 planned frames; persistent CLEARVIEW · MODEL PREVIEWS label.
- No model-name flash; use a hard cut to the next silhouette.

**Exit / cut:** Model complete and readable; no loading texture or clipping. Hard cut to next admitted preview.

**Continuity:** Same preview background, apparent center and exposure; normalize framing, not physical size. Source-family blocks remain contiguous.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42n — Beluga · 02:14:30–02:15:00 · U

**Picture:** ClearView imported preview: Beluga; provisional casting, exact source and new visual acceptance required.

**Cast / paint:** Beluga — Original admitted source textures; source hash and exact texture identity pending.. **Environment:** `creator`.

**Preparation:** Admit exact local source and textures for Beluga; retain input/model-root hashes. **At the edit’s start:** Actual Creator preview is fully loaded and stable before the selected frames.

**Blocking (model_local):** 0s: (0, 0, 0) Use actual preview bounds center; numeric zero is local model-centered framing, not a new field spawn.

**Camera:** native_preview_three_quarter, preview, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Target a nose-right three-quarter view, about 25° yaw / 15° elevation from front, ~70% frame-width occupancy. Use native preview orbit/fit and record resulting camera; angles are composition targets, not implemented UI numeric controls.

**Action:**

- Hold native proportions and original source texture set.
- Retain 30 planned frames; persistent CLEARVIEW · MODEL PREVIEWS label.
- No model-name flash; use a hard cut to the next silhouette.

**Exit / cut:** Model complete and readable; no loading texture or clipping. Hard cut to next admitted preview.

**Continuity:** Same preview background, apparent center and exposure; normalize framing, not physical size. Source-family blocks remain contiguous.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42o — A6-Zero · 02:15:00–02:15:30 · U

**Picture:** ClearView imported preview: A6-Zero; provisional casting, exact source and new visual acceptance required.

**Cast / paint:** A6-Zero — Original admitted source textures; source hash and exact texture identity pending.. **Environment:** `creator`.

**Preparation:** Admit exact local source and textures for A6-Zero; retain input/model-root hashes. **At the edit’s start:** Actual Creator preview is fully loaded and stable before the selected frames.

**Blocking (model_local):** 0s: (0, 0, 0) Use actual preview bounds center; numeric zero is local model-centered framing, not a new field spawn.

**Camera:** native_preview_three_quarter, preview, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Target a nose-right three-quarter view, about 25° yaw / 15° elevation from front, ~70% frame-width occupancy. Use native preview orbit/fit and record resulting camera; angles are composition targets, not implemented UI numeric controls.

**Action:**

- Hold native proportions and original source texture set.
- Retain 30 planned frames; persistent CLEARVIEW · MODEL PREVIEWS label.
- No model-name flash; use a hard cut to the next silhouette.

**Exit / cut:** Model complete and readable; no loading texture or clipping. Hard cut to next admitted preview.

**Continuity:** Same preview background, apparent center and exposure; normalize framing, not physical size. Source-family blocks remain contiguous.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42p — Agri Duck Duster · 02:15:30–02:16:00 · U

**Picture:** ClearView imported preview: Agri Duck Duster; provisional casting, exact source and new visual acceptance required.

**Cast / paint:** Agri Duck Duster — Original admitted source textures; source hash and exact texture identity pending.. **Environment:** `creator`.

**Preparation:** Admit exact local source and textures for Agri Duck Duster; retain input/model-root hashes. **At the edit’s start:** Actual Creator preview is fully loaded and stable before the selected frames.

**Blocking (model_local):** 0s: (0, 0, 0) Use actual preview bounds center; numeric zero is local model-centered framing, not a new field spawn.

**Camera:** native_preview_three_quarter, preview, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Target a nose-right three-quarter view, about 25° yaw / 15° elevation from front, ~70% frame-width occupancy. Use native preview orbit/fit and record resulting camera; angles are composition targets, not implemented UI numeric controls.

**Action:**

- Hold native proportions and original source texture set.
- Retain 30 planned frames; persistent CLEARVIEW · MODEL PREVIEWS label.
- No model-name flash; use a hard cut to the next silhouette.

**Exit / cut:** Model complete and readable; no loading texture or clipping. Hard cut to next admitted preview.

**Continuity:** Same preview background, apparent center and exposure; normalize framing, not physical size. Source-family blocks remain contiguous.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42q — MC Tiburon-bipe-7-2 · 02:16:00–02:16:30 · U

**Picture:** ClearView imported preview: MC Tiburon-bipe-7-2; provisional casting, exact source and new visual acceptance required.

**Cast / paint:** MC Tiburon-bipe-7-2 — Original admitted source textures; source hash and exact texture identity pending.. **Environment:** `creator`.

**Preparation:** Admit exact local source and textures for MC Tiburon-bipe-7-2; retain input/model-root hashes. **At the edit’s start:** Actual Creator preview is fully loaded and stable before the selected frames.

**Blocking (model_local):** 0s: (0, 0, 0) Use actual preview bounds center; numeric zero is local model-centered framing, not a new field spawn.

**Camera:** native_preview_three_quarter, preview, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Target a nose-right three-quarter view, about 25° yaw / 15° elevation from front, ~70% frame-width occupancy. Use native preview orbit/fit and record resulting camera; angles are composition targets, not implemented UI numeric controls.

**Action:**

- Hold native proportions and original source texture set.
- Retain 30 planned frames; persistent CLEARVIEW · MODEL PREVIEWS label.
- No model-name flash; use a hard cut to the next silhouette.

**Exit / cut:** Model complete and readable; no loading texture or clipping. Hard cut to next admitted preview.

**Continuity:** Same preview background, apparent center and exposure; normalize framing, not physical size. Source-family blocks remain contiguous.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42r — MC 3D Hobby Shops Extra 330 Red · 02:16:30–02:17:00 · U

**Picture:** ClearView imported preview: MC 3D Hobby Shops Extra 330 Red; provisional casting, exact source and new visual acceptance required.

**Cast / paint:** MC 3D Hobby Shops Extra 330 Red — Original admitted source textures; source hash and exact texture identity pending.. **Environment:** `creator`.

**Preparation:** Admit exact local source and textures for MC 3D Hobby Shops Extra 330 Red; retain input/model-root hashes. **At the edit’s start:** Actual Creator preview is fully loaded and stable before the selected frames.

**Blocking (model_local):** 0s: (0, 0, 0) Use actual preview bounds center; numeric zero is local model-centered framing, not a new field spawn.

**Camera:** native_preview_three_quarter, preview, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Target a nose-right three-quarter view, about 25° yaw / 15° elevation from front, ~70% frame-width occupancy. Use native preview orbit/fit and record resulting camera; angles are composition targets, not implemented UI numeric controls.

**Action:**

- Hold native proportions and original source texture set.
- Retain 30 planned frames; persistent CLEARVIEW · MODEL PREVIEWS label.
- No model-name flash; use a hard cut to the next silhouette.

**Exit / cut:** Model complete and readable; no loading texture or clipping. Match the same Extra 330 Red identity into its eligible flight.

**Continuity:** Same preview background, apparent center and exposure; normalize framing, not physical size. Source-family blocks remain contiguous.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-43 — MC 3D Hobby Shops Extra 330 Red · 02:17:00–02:20:00 · G

**Picture:** Same final previewed model in its genuine eligible Creator trial; experimental/estimated or donor qualification.

**Cast / paint:** MC 3D Hobby Shops Extra 330 Red — Original admitted source textures; source hash and exact texture identity pending.. **Environment:** `day_calm`.

**Preparation:** Use the exact last-previewed Extra 330 Red Creator draft. Complete eligible estimated/donor setup and its actual trial gates. **At the edit’s start:** Same model/source textures. Retain the real trial qualification; aircraft has stabilized before the three-second selection.

**Blocking (NED):** 0s: (25, -20, -10) → 3s: (25, 20, -10) Provisional framing corridor only. Actual scaled dimensions, donor/derived trim, speed and spawn are unknown until this exact draft qualifies.

**Camera:** subject_relative, FRU, FOV 40°. 0s: (-7, -4, 2) Scale camera distance to actual imported bounds after admission; no numeric lens/size guarantee before the model is loaded.

**Action:**

- Show real eligible flight, with EXPERIMENTAL TEST FLIGHT and actual estimated/donor qualification.
- Keep same source model/paint from final preview.

**Exit / cut:** Three seconds of readable controlled flight. Cut from model expansion to Bisonte shoreline action.

**Continuity:** R4-42r and R4-43 use the exact same draft/model-root/texture hashes. If another model qualifies, reorder the last preview and plan together.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Visual conversion alone is insufficient; trial admission and flight must be demonstrated. If no candidate qualifies, change ending to clearly labelled preview-only and remove flight promise.

### R4-44 — MT8 Bisonte · 02:20:00–02:25:00 · G

**Picture:** Bisonte at the shallow shore: real tires, mud/water contact, modest droplets/rings and actual sound.

**Cast / paint:** MT8 Bisonte — Amarillo Rayo. **Environment:** `golden_calm`.

**Preparation:** Bisonte Amarillo Rayo, native lake_shore spawn; restore normal Lab settings after the separate comparison. **At the edit’s start:** Supported dry spawn N145.5 E125 facing south; read back native staging acceptance.

**Blocking (NE_surface):** 0s: (145.5, 125, 0) → 3.5s: (138.5, 125, 0) → 5s: (138, 125, 0) Plan-view only; stop at N138, do not continue to N137. Proposed 7.5 m route with braking; actual tire footprint/depth and stopping distance require proof.

**Camera:** fixed_tracking, NED, FOV 42°. 0s: (142, 130, -0.45) Low east-side three-quarter camera tracks tires and waterline. Keep camera on verified dry support; actual native moving orbit is a fallback with its own recorded eye.

**Action:**

- Start rolling before the cut; ease toward the shore on low throttle.
- Brake early to stop at or north of N138; retain wheels and modest real effects.
- Hold actual settling and electric motor/shore sound.

**Exit / cut:** Truck remains controllable and stops in the proven shallow route. Resolve sound into five-second invitation.

**Continuity:** Same Amarillo Rayo throughout, normal scale and restored damping 1.00. No continuation of the earlier Lab experiment is implied.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `adapter_needed` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Source spawn checks entry sample only; this full driving route still needs runtime qualification. N137 may be materially deeper; reject overshoot, deep water and unobserved effect claims.

### R4-45 — Brand/end card · 02:25:00–02:30:00 · E

**Picture:** Stable cinematic OPEN RC SIMULATOR / PLAY FREE / official project destination; five fully settled seconds.

**Cast / paint:** Brand/end card — Not applicable. **Environment:** `editorial`.

**Preparation:** Use the R6 title plan and a neutral dark end-card base. Confirm the official destination before publishing. Add product status or music credits only if explicitly verified and required by the selected assets. **At the edit’s start:** Full card already settled at start of five-second hold.

**Blocking (none):** Native UI/preset or actual camera readback; no invented world coordinates.

**Camera:** end_card, none, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Centered product name, invitation and full destination in the R6 typography system. No inherited beta badge, old slogan or soundtrack attribution.

**Action:**

- Hold five full seconds; no extra model flicker or additional feature list.
- Resolve score and fade real final sound.

**Exit / cut:** Destination and call to action have been readable. End cleanly.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Text:** title-plan-r6.json; genuine HUD and model-attached size labels are separate captured/layout evidence.

**Implementation:** `editorial` — `assemble.py style=cinema with title-plan-r6.json`. R6 renderer and global-frame overlays; actual footage and soundtrack remain unselected.

**Accept only when:** Five fully settled seconds, correct destination, final phone readability and any actual asset-credit obligations are checked before release. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

<!-- END GENERATED SHOT CARDS -->

## Environment settings

Use explicit readback for each take; remembered Home preferences are not a shot recipe. Freeze time rather than compressing a sunset into seconds. “Day” is the source’s calibrated fixed sun; named ephemeris presets use the game’s reference location/date, not the filming computer’s timezone.

| Setup | Chosen conditions |
| --- | --- |
| day_calm | Club field, Day, clear sky, zero wind/gust, time frozen. |
| ground_breeze | Club field, Day, proposed 0.5 m/s steady wind, no gusts; stationary support/fold gates still required. |
| golden_calm | Club field, Golden hour, zero wind/gust, time frozen; same exposure for orbit and lake. |
| night_calm | Club field, actual full-moon Night, supported Night Radian profile; Blue hour is a documented alternative if body readability fails. |
| storm | Separate ordinary Club flight, actual Electrical storm appearance preset; capture a real event. |
| phoenix_airfield | Exact Airfield calibration hash `68a9a01bbfee97e0480c49dd6f34d51ef6b8660f947dab639b776410862354d9`; fixed photo eye, admitted local imagery required. |
| inspector / creator | Their native studio/preview interfaces. No invented playable field geometry. |

## Implementation and production order

1. **Validate the shared plan.** Run the offline checker, generate cards/maps and export a camera recipe. Preserve the pinned game-source hashes; source drift requires investigation, not automatic repinning.
2. **Qualify controlled mechanics and the orbit.** Use grounded, supported Corsair state and real mechanism commands. Capture the 13-asset schedule with hold-last, then verify actual presented skins and source-clock alignment.
3. **Rehearse one lake take.** Compose the independent camera after the existing pilot director. Fly the approach or review a correct pre-tree fixture separately; the current generic pilot commands are not a qualified straight-lake flight. Record actual CG/eye/FOV and advancing ticks for every retained frame.
4. **Review typography against the real pictures.** The typography study contains only generated graphics on a neutral background. It checks the look and timing of letters, not gameplay, reflection, HUD clearance or phone readability over real footage.
5. **Bind real media and trial qualification.** Use actual source ranges, full preview/source identities and the exact final imported-model trial basis. The cinema assembler checks all 62 cut IDs and lengths before compositing global-frame titles. It keeps source labels continuous and supplies a clean end-card base.
6. **Finish sound and delivery.** Use explicit new metadata, description, filename and soundtrack attribution. Qualify the final full-length encode, audio, reading distance, destination and requested capture host after real takes exist.

The [capture-tool guide](../../../tools/trailer/README.md#r6-cinematic-titles-and-camera-recipes) owns commands and supported routes. The [R6 audit](script-audit-r6-2026-11-22.md) owns actual software-check results and limitations. A headless camera check cannot accept a gameplay image or real hardware performance.

## Coverage and remaining evidence

The master remains **112 G + 15 U + 18 P + 5 E = 150 seconds**, with no reserve pool. [Field Notes](feature-companion-films.md) and [Preflight Ballet](mechanical-sequences.md#separate-32-second-idea--the-preflight-ballet) retain the opportunities outside the master. Preserve full outcomes for gate crossing, recovery, landing and the truck jump. Retime every authority if a feature must move out of the master.

No new real gameplay take, imported-model batch, soundtrack, RTX 3090 capture or finished trailer is accepted in this revision. Camera geometry, software composition and typography can now be reviewed concretely. Actual trajectories, source-frame choices, skin textures, collision clearance, reflection, control response and target-host performance remain production evidence under the [verification gates](verification-gates.md).
