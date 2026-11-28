# OPEN RC SIMULATOR — A SKY WITHIN REACH

## Director's shooting script — Revision 7

**Date:** 22 November 2026. **Track:** V2. **Branch:** `docs/trailer-v2-preproduction-2026-11-21`.
**Status:** current directing and implementation plan; actual game footage, soundtrack and target-host acceptance are pending. **Master:** 150 seconds / 9,000 frames at 60 fps / 62 cuts. The R4-prefixed IDs remain stable even though their order changes.
**Game-source baseline:** `57abea025f62b20233ca281d58d2acbee4ab8b8e`, with 40 exact source-file hashes in the [R7 shot plan](shot-plan-r7.json). R7 builds on branch parent `fd2eb1f31b4df31571aed35d8a31df7006c97ce6`; this is not a release-build selection.

The [shot plan](shot-plan-r7.json) owns the numeric edit, cast, skins, blocking, cameras, lighting and handoffs. The [storyboard](storyboard-r7.md) presents the exact cut and title tables. The [direction sheet](direction-and-continuity.md) explains screen axes, entrances/exits and source-backed lighting. The [R7 audit](script-audit-r7-2026-11-22.md) distinguishes implementation checks from unfilmed plans. Read this revision instead of mixing earlier shooting instructions.

### The directing decision

The promise is a place to fly, race, experiment and make a machine your own. Begin with close action and recognizable outcomes. Follow the race recovery with the rotor mechanism and its clearly separate playable helicopter, then the grounded Corsair's mechanical details. The P-51 input-to-bank and engine-out landing make control useful. Put setup experiments and scale before the world opens into afternoon, the signature Corsair orbit, lake and sunset shore. Creator then expands the hangar; its final model earns one actual trial. Finish on a legible night flight, then a five-second invitation.

This is a sequence of distinct sessions, not one continuous flight or day. Each camera has one job. Aircraft identity, control movement and an outcome must read before decorative field detail earns attention. No additional feature has been inserted by silently shortening the orbit, lake, preview reel or end card.

## Master shape

| Time | Chapter | Lighting / session |
| --- | --- | --- |
| 0–18 s | Discover the playground | Morning clarity |
| 18–39 s | Choose a line; recover and fly | Reference daylight |
| 39–47 s | See the mechanism; see it fly | Studio to daylight |
| 47–59 s | Make every movement tangible | Matched ground daylight |
| 59–73 s | Input, response and a resolved landing | Reference daylight |
| 73–89 s | Change a setup; understand the result | Reference daylight / explicit UI |
| 89–105 s | Explore places, weather and afternoon flight | Day / baked panorama / storm / afternoon |
| 105–126 s | Make it yours; stay by the water | Golden hour to sunset |
| 126–141 s | Open the hangar; prove one trial | Neutral Creator / separate daylight trial |
| 141–145 s | One last flight | Moonlit night or declared blue-hour alternate |
| 145–150 s | Play free | Editorial card |

[Measured edit and lighting map](diagrams/r7-edit-map.svg). Its swatches describe intended mood, not measured game colors. Source-class allocation remains **112 s actual sessions (G) + 15 s real UI (U) + 18 s presentation/inspection (P) + 5 s end card (E)**.

## Text direction

Only three main-copy cues remain: **A SKY WITHIN REACH** at 14.25–17.5 s, **FEEL EVERY INPUT** at 60.25–64.75 s and **EXPAND YOUR HANGAR** at 126–128 s. Use warm-white Barlow Condensed with restrained tracking and brief, settled entrances. The [R7 title plan](title-plan-r7.json) owns all global frame windows. Functional captions are 52 px at 1080p, larger than R6; they still require real-background and phone review. Required source/inspection/presentation labels remain fully visible for their whole intervals. The six-second lake shot has no added title.

The 18 previews have two continuous provider labels rather than 18 separate animated entrances. The actual estimated/donor basis must qualify the imported trial before publication. **TURBO LUMBER** identifies the separate stock night flight at 141–145 s. The end card holds **OPEN RC SIMULATOR / PLAY FREE / bultodepapas.github.io/OpenRCsimulator/** for all five seconds; recheck the source-known destination and actual delivery flow before release. No inherited beta badge, old slogan, unverified 300+ copy or unselected soundtrack credit is carried forward.

The [text-window transition study](research-text-window-transition-2026-11-22.md) remains optional. It has not replaced the visible-gameplay opening or added seconds to this master. If selected later, assign it a specific replacement interval and review the reading/footage tradeoff.

## Camera and edit grammar

Use parallel cameras for the opening jet and electric Stick so the subject does not shrink to a distant dot at both ends. The jet eye is N6/D−6.5/E=CG east−6 with vertical FOV 32°; the electric Stick eye is N10/D−2.5/E=CG east−6 with FOV 34°. Both sit south of eastbound aircraft and keep a nose-right silhouette. The tiny 10% Stick has a dedicated closer view, N28.5/D−1.2/E=CG east−1, FOV 24°, with a fixed field reference. Those distances are proposed composition, not flown acceptance. The tiny Stick camera cannot yet be combined with its Workshop trial through the stock recipe guard; a separately qualified route is required. The existing truck-jump harness also needs a manual/adapted camera and sky route for the stated morning shot.

A camera tracking an aircraft does not make it travel across the frame. The cards' world exit marks tell the editor where to cut while the subject is still readable. `screen_direction` describes the intended projected orientation; `axis_note` explains it. `cut_to` and `cut_kind` name every actual next shot. Same-take control evidence, same-attempt recovery and practice, separate UI contexts and deliberate axis changes are explicit.

Retain the Corsair orbit's actual visual-model-root anchor. Its final front-left Three Tone image leads to the north-bank lake view, also nose-left. The lake's R7 aim is the aircraft's actual north/east position projected onto the source water plane, leaving room above for the aircraft and below for a real reflection. The imported preview-to-trial cut is nose-right on both sides; the proposed flight camera is rear-right FRU(−7,+4,+2), resized to admitted model bounds. The final Lumber uses its existing root-relative director, not a newly invented chase route. See the [direction sheet](direction-and-continuity.md#2-entrances-exits-and-direction).

## Sound and rhythm

Let physical events shape the cut: jet, truck touchdown, electric propeller, hand launch, quiet blimp; gate passage and recovery; rotor mechanism, flying helicopter, Corsair servos; control response and a successful landing. Lab and scale explain cause and effect before the pace relaxes for the lake. The import reel accelerates the image changes without speeding source physics. The night flight resolves into the invitation.

Reserve space for actual engine, rotor, servo and water/contact sound. Avoid a continuous wall of rotor noise. Do not give a studio inspector a flying-helicopter soundtrack that changes its meaning. Musical accents and sound bridges remain editorial intentions: no track, BPM, source EDL, mixed sound or accepted recording is fabricated here.

## Coordinate and take contract

| Quantity | Meaning |
| --- | --- |
| `(N, E, D)` | Simulation north, east and down in metres. Negative D is above the reference datum. |
| Render `(x, y, z)` | `(E, −D, −N)`. Example: Corsair lake entry `(128, 55, −2.55)` becomes `(55, 2.55, −128)`. |
| Heading | Clockwise from north: 0° north, 90° east, 180° south, 270° west. |
| `NE_surface` | A plan-view ground/support marker. Its zero D is a drawing datum; the production ground solver supplies actual CG height, attitude and suspension support. |
| Camera `FRU` | Forward/right/up metres in the aircraft’s **horizontal heading frame**. Proposed cameras use actual CG unless specified; the existing R4-39 orbit and R4-31 Lumber director use **visual model root**, which is offset from simulated CG. |
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

Twelve 45-frame holds plus the final 60-frame hold total 600 frames. `midnight` is the first real livery asset but Home normalizes its selection to an empty string; the cycle uses the asset ID. The hold-last option keeps `three_tone` selected after its final change. The director’s clock is simulation time: inspect actual `sim_time_s` and `presented_livery` for source-frame alignment before accepting this exact edit cadence.

### Lake: origin, crossing, exit — 115–121 s

The proposed eastbound corridor remains **N128 / E55 → E124 → E193**, at **D−2.55**, three metres above the source mean-water plane D+0.45, with nominal 23 m/s planning speed. The camera eye is **N145 / D−1 / E=actual presented CG east−8**. At the nominal marks its eyes are **(145,47,−1) → (145,116,−1) → (145,185,−1)**. These are samples of the tracking law, not instructions forcing the aircraft along a path.

R7 uses **vertical FOV 34°** and `presented_cg_water_plane`, aiming at the actual CG north/east projected onto D+0.45. The aircraft sits above the aim and a genuine reflection can fit below. The adapter records actual CG and aim separately. Both camera and aircraft clearances, exposure, motion and relative screen sizes require an actual take. The north-side camera gives an eastbound aircraft a screen-left nose; match the final orbit's accepted orientation and paint.

The source polygon intersects the nominal corridor near **E88.73** and **E162.91**. About **74.18 m / 3.225 s** of the six-second planned route is over water; the rest is approach and exit. The camera eye is 1.45 m above mean water, but its bank/terrain clearance remains unqualified. A lakebed-relative terrain altitude must not be mistaken for height above the surface.

A moving-aircraft mirror requires the real planar path, active High and non-headless Forward+ rendering; the default cubemap excludes it. See the [reflection instructions](direction-and-continuity.md#4-the-lake-must-frame-a-real-aircraft-and-a-real-reflection), [lake map](diagrams/r7-lake-blocking.svg) and [unchanged truck geometry](diagrams/r5-truck-blocking.svg). An unmirrored genuine lake take is a declared fallback. No reflection is synthesized by the camera recipe.

## Detailed shot cards

These 62 cards are generated from `shot-plan-r7.json`. Edit numeric/action/source values there, regenerate this block and check the storyboard and title plan together. Frames are zero-based, end-exclusive, at 60 fps. Source-media in/out remains unassigned until a real take is accepted.

<!-- BEGIN GENERATED SHOT CARDS -->

### R4-01 — Vantage Jet · 00:00:00–00:04:00 · G

**Picture:** Vantage Jet: genuine inverted external pass; real banked pass is the rehearsal fallback.

**Cast / paint:** Vantage Jet — Sabre Plata. **Environment:** `morning_calm`.

**Preparation:** Home Vantage, Sabre Plata, airborne. Rehearse the roll well before the selected clip. **At the edit’s start:** Already established inverted flight on entry; runway and horizon visible.

**Blocking (NED):** 0s: (15, -58, -8) → 2s: (15, 0, -8) → 4s: (15, 58, -8) 29 m/s is configured launch speed, not measured pass speed; points are a 116 m nominal corridor.

**Camera:** parallel_east, NED, FOV 32°. 0s: (6, -64, -6.5) → 2s: (6, -6, -6.5) → 4s: (6, 52, -6.5) Parallel eye stays 9 m south and 6 m aft of the nominal aircraft, 1.5 m lower. Approximate nominal range 10.9 m; this replaces the old 60 m endpoints. Vertical FOV 32 degrees; keep an upright visible horizon and full silhouette. Camera/world clearance and actual inversion still need a take.

**Action:**

- Before edit: establish altitude and inversion with genuine roll input.
- 0–3 s: hold a stable canopy-down pass; no video rotation.
- 3–4 s: pass the east world exit mark with attitude readable; retain real turbine sound.

**Exit / cut:** Aircraft reaches the east world exit mark; tracking keeps its CG near frame center. Cut while the inverted or accepted banked attitude remains readable. Hard cut to the nitro truck after a readable inverted or banked pose. Both proposed south-side cameras give a screen-right nose; match subject eye position and scale if the actual takes allow it.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Screen / axis:** screen right. Eastbound subject; camera south gives nose-right, north gives nose-left. Tracking holds subject position while scenery moves. **Next cut:** R4-02 · hard cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `camera_adapter_implemented_flight_pending` — `capture_flight.gd --camera-recipe plus a qualified pilot director / real flown take`. Camera follows the actual displayed aircraft. It does not select the paint, establish a spawn or force the proposed flight. Keep source identity and real advancing ticks.

**Accept only when:** Genuine inversion and ground/horizon agree. If unsafe/unreadable in simulation, use the declared real upright banked pass; update take status.

### R4-02 — MONSTER CAR 2 · 00:04:00–00:08:00 · G

**Picture:** MONSTER CAR 2: nitro ramp departure, apex, touchdown and suspension response.

**Cast / paint:** MONSTER CAR 2 — Naranja Lava. **Environment:** `morning_calm`.

**Preparation:** Garage MONSTER CAR 2, Naranja Lava; select track_start and verify actual spawn. **At the edit’s start:** Start N39 E−9 heading east, wheels supported. Begin recording before acceleration.

**Blocking (NE_surface):** 0s: (39, -9, 0) → 1s: (39, -5.225, 0) → 2s: (39, -3.775, 0) → 4s: (39, 3, 0) Ramp geometry anchors; time-to-ramp and landing point are rehearsal targets, not a ballistic prediction. D=0 is a map reference only.

**Camera:** fixed_tracking, NED, FOV 42°. 0s: (34, -3, -0.35) Low south-side eye follows body; preserve full tire silhouette and actual touchdown; no camera through the ramp.

**Action:**

- Accelerate east with W/Up; steer neutral.
- Retain takeoff, apex, actual touchdown and first suspension settle in the four-second edit.
- Use Space/S brake after the landing outside the retained action.

**Exit / cut:** Upright landing visible with tires taking load. Cut on landing sound into electric Stick pass.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Screen / axis:** screen right. Eastbound subject; camera south gives nose-right, north gives nose-left. Tracking holds subject position while scenery moves. **Next cut:** R4-03 · hard cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `reference_adapter_needs_scene_and_camera_adaptation` — `capture_car_jump.gd as a reference; manual or adapted R7 sky/camera route required`. The existing jump harness has a strict argument allowlist that rejects time/sky flags, uses classic sky, and supplies a 46-degree orbit. It does not establish this morning/clear/42-degree planned shot. Preserve the real jump/landing; qualify a manual or adapted route with actual conditions and camera readback. Prior reference captures retain their original settings.

**Accept only when:** Monster-specific jump must be demonstrated; Bisonte tests do not qualify the nitro truck. Actual take contains the complete landing; no speed-up or cropped outcome.

### R4-03 — Ugly Stick Electric 6S · 00:08:00–00:11:00 · G

**Picture:** Ugly Stick Electric 6S: clear lateral pass, actual alternate skin and variant identification.

**Cast / paint:** Ugly Stick Electric 6S — NEON RONIN · Cyberpunk. **Environment:** `morning_calm`.

**Preparation:** Home Ugly Stick Electric 6S, NEON RONIN; airborne. **At the edit’s start:** Enter west of runway at about 4 m above reference ground; trim before mark.

**Blocking (NED):** 0s: (18, -22.5, -4) → 1.5s: (18, 0, -4) → 3s: (18, 22.5, -4) 45 m reference corridor at the configured 15 m/s start speed; actual track may differ.

**Camera:** parallel_east, NED, FOV 34°. 0s: (10, -28.5, -2.5) → 1.5s: (10, -6, -2.5) → 3s: (10, 16.5, -2.5) Parallel eye stays south of the eastbound aircraft; nose reads screen-right while background slides. The nominal approximately 10.1 m range avoids a distant entry and fast fixed-eye pan. Full skin and electric identity remain visible targets.

**Action:**

- Preroll at least two settled seconds before entry.
- Hold a simple lateral pass; avoid a roll that hides the selected paint.
- Keep UGLY STICK · ELECTRIC 6S readable without covering the model.

**Exit / cut:** Aircraft passes the east world exit mark while the entire airframe remains readable near frame center. Cut to the real MoonRunner release with a compatible screen-right nose. Both actions stay visible; an east world exit mark does not mean a frame-edge exit.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Screen / axis:** screen right. Eastbound subject; camera south gives nose-right, north gives nose-left. Tracking holds subject position while scenery moves. **Next cut:** R4-04 · hard cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `camera_adapter_implemented_flight_pending` — `capture_flight.gd --camera-recipe plus a qualified pilot director / real flown take`. Camera follows the actual displayed aircraft. It does not select the paint, establish a spawn or force the proposed flight. Keep source identity and real advancing ticks.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-04 — MoonRunner X99 · 00:11:00–00:14:00 · G

**Picture:** MoonRunner: actual hand-launch release into a climbing bank; no throwing-person animation.

**Cast / paint:** MoonRunner X99 — BOLIDO - re-entry heat shield. **Environment:** `morning_calm`.

**Preparation:** Home MoonRunner X99, BOLIDO, explicit hand_launch. Verify the choice was not replaced. **At the edit’s start:** Native release at N9 E0, terrain +1.9 m, 6.5 m/s, 5° climb in calm eastbound setup.

**Blocking (NED):** 0s: (9, 0, -1.9) → 3s: (10, 18, -4.5) First point uses the flat-reference terrain; verify actual sampled release altitude. Exit is a gentle climbing target, not source launch behavior.

**Camera:** fixed_tracking, NED, FOV 42°. 0s: (1, 6, -1) Fixed eye; pan/tilt to actual aircraft CG. Keep world horizon upright.

**Action:**

- Start the cut at the actual release state; no throwing person.
- Keep wings identifiable through a shallow climbing bank.
- Do not cut until positive climb is visible.

**Exit / cut:** Flying wing clears the launch area in world space, with its eastbound nose pointing screen-right; CG tracking keeps it near frame center. Cut from dark BOLIDO silhouette to the white blimp envelope.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Screen / axis:** screen right. Eastbound subject; camera south gives nose-right, north gives nose-left. Tracking holds subject position while scenery moves. **Next cut:** R4-05 · hard cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `adapter_needed` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-05 — RC Blimp 5 m · 00:14:00–00:18:00 · G

**Picture:** Blimp: full envelope/gondola, quiet motion and real birds if readable.

**Cast / paint:** RC Blimp 5 m — Tiburón Blanco. **Environment:** `morning_calm`.

**Preparation:** Home RC blimp, Tiburón Blanco; use its own launch menu and settle before the take. **At the edit’s start:** Blimp already moving slowly east from the west world mark; whole envelope and gondola are visible near frame center.

**Blocking (NED):** 0s: (30, -6, -6) → 4s: (30, 6, -6) 3 m/s is a proposed composition pace; obtain actual trim/motion through normal airship controls.

**Camera:** fixed_tracking, NED, FOV 45°. 0s: (16, 0, -1.7) Fixed eye; pan/tilt to actual aircraft CG. Keep world horizon upright.

**Action:**

- Preroll until yaw and pitch settle.
- Travel gently east through the proposed world corridor. The camera follows CG; the nose points screen-right while the background moves behind it.
- Birds are welcome only if they do not obscure the blimp.

**Exit / cut:** The gondola remains visible through the final frame. Let quieter prop sound breathe, then cut to the gate-course geometry.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Screen / axis:** screen right. Eastbound subject; camera south gives nose-right, north gives nose-left. Tracking holds subject position while scenery moves. **Next cut:** R4-06 · hard cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

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

**Screen / axis:** neutral. Context or native UI defines the frame; inspect the real image. **Next cut:** R4-07 · hard cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

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

**Screen / axis:** forward. Rigid onboard view; retain real horizon/gate orientation. Vehicle body is not an exterior screen-direction reference. **Next cut:** R4-08 · hard cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

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

**Screen / axis:** screen right. Eastbound subject; camera south gives nose-right, north gives nose-left. Tracking holds subject position while scenery moves. **Next cut:** R4-09 · hard cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

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

**Screen / axis:** forward. Rigid onboard view; retain real horizon/gate orientation. Vehicle body is not an exterior screen-direction reference. **Next cut:** R4-10 · hard cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

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

**Screen / axis:** forward. Rigid onboard view; retain real horizon/gate orientation. Vehicle body is not an exterior screen-direction reference. **Next cut:** R4-11 · hard cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

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

**Screen / axis:** neutral. Context or native UI defines the frame; inspect the real image. **Next cut:** R4-12 · same attempt ellipsis.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

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

**Screen / axis:** neutral. Context or native UI defines the frame; inspect the real image. **Next cut:** R4-13 · same attempt ellipsis.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

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

**Exit / cut:** Quad clearly airborne again. Finish the real recovery lift-off, then make a clear context cut to the labelled, stopped HX-700 inspection. Cut off quad motor sound before the stationary mechanism.

**Continuity:** Same attempt and location; no restart, terminal-crash revival, depleted-pack revival or invisible repair.

**Screen / axis:** neutral. Context or native UI defines the frame; inspect the real image. **Next cut:** R4-20 · context reset.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Actual state gates admit each arm/turtle transition. If recovery timing does not fit, obtain a clearer successful attempt or explicitly retime.

### R4-20 — HX-700 articulated mechanism · 00:39:00–00:43:00 · P

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

**Screen / axis:** neutral. Context or native UI defines the frame; inspect the real image. **Next cut:** R4-21 · context reset.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `inspector_adjustment` — `app/tools/inspect_hx700.gd`. Existing capture_hx700_mechanism.gd includes 12 rpm and cyclic motion; that old schedule is not this stopped-rotor take.

**Accept only when:** Native inspection/presentation motion and its disclosure are readable; no flight session is implied. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-21 — X-Cell .60 research helicopter · 00:43:00–00:47:00 · G

**Picture:** Clearly separate playable X-Cell .60: hover into forward flight past a landmark.

**Cast / paint:** X-Cell .60 research helicopter — Blanco Ártico. **Environment:** `day_calm`.

**Preparation:** Home X-Cell .60, Blanco Ártico, native pad N6 E0. Preroll: center cyclic/yaw, B arm, H release hold; wait for GOVERNED, lift and stabilize before the edit. **At the edit’s start:** Already hovering over the pad at target N6 E0 D−2.5, governor stabilized, neutral cyclic/yaw; the four-second shot starts here.

**Blocking (NED):** 0s: (6, 0, -2.5) → 1s: (6, 0, -2.5) → 4s: (6, 6, -2.5) Hover and forward-motion targets; actual initial heading and collective must be rehearsed. Estimated governor ramp is not squeezed into the clip.

**Camera:** fixed_tracking, NED, FOV 38°. 0s: (0, -3, -1.2) Fixed eye; pan/tilt to actual aircraft CG. Keep world horizon upright.

**Action:**

- 0–1 s: stable full helicopter hover.
- 1–4 s: gentle forward cyclic, starting with a modest input, then stabilize; no barrel roll.

**Exit / cut:** Helicopter visibly displaced past the pad landmark. Complete visible forward travel, then hard-cut to the grounded Corsair in a clearly new scene. Rotor sound resolves before the surface-check details.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Screen / axis:** screen right. Eastbound subject; camera south gives nose-right, north gives nose-left. Tracking holds subject position while scenery moves. **Next cut:** R4-14 · context reset.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `Home X-Cell .60 pad start and livery selection; manually staged hover/advance`. capture_vehicles.gd --vehicle=xcell-60-research --heli-shot=flight is an airborne-flight reference only: it hardcodes --start=airborne and has no --livery input. It needs adaptation for the specified pad, skin and governed preroll; no ready automation is claimed.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-14 — F4U Corsair · 00:47:00–00:50:00 · G

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

**Screen / axis:** neutral. Stationary grounded Corsair; name the viewed side and fixed hinge reference. Angle changes are explicit detail cuts, not a moving-flight axis. **Next cut:** R4-15 · hard cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Fold: weight on wheels, speed below 0.5 m/s, idle until spread/locked. Native travel is recorded without time compression; excerpts are acknowledged.

### R4-15 — F4U Corsair · 00:50:00–00:52:00 · G

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

**Screen / axis:** neutral. Stationary grounded Corsair; name the viewed side and fixed hinge reference. Angle changes are explicit detail cuts, not a moving-flight axis. **Next cut:** R4-16 · hard cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Fold: weight on wheels, speed below 0.5 m/s, idle until spread/locked. Native travel is recorded without time compression; excerpts are acknowledged.

### R4-16 — F4U Corsair · 00:52:00–00:53:30 · G

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

**Screen / axis:** neutral. Stationary grounded Corsair; name the viewed side and fixed hinge reference. Angle changes are explicit detail cuts, not a moving-flight axis. **Next cut:** R4-17 · hard cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Fold: weight on wheels, speed below 0.5 m/s, idle until spread/locked. Native travel is recorded without time compression; excerpts are acknowledged.

### R4-17 — F4U Corsair · 00:53:30–00:55:00 · G

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

**Screen / axis:** neutral. Stationary grounded Corsair; name the viewed side and fixed hinge reference. Angle changes are explicit detail cuts, not a moving-flight axis. **Next cut:** R4-18 · hard cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Fold: weight on wheels, speed below 0.5 m/s, idle until spread/locked. Native travel is recorded without time compression; excerpts are acknowledged.

### R4-18 — F4U Corsair · 00:55:00–00:57:00 · G

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

**Screen / axis:** neutral. Stationary grounded Corsair; name the viewed side and fixed hinge reference. Angle changes are explicit detail cuts, not a moving-flight axis. **Next cut:** R4-19 · hard cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Fold: weight on wheels, speed below 0.5 m/s, idle until spread/locked. Native travel is recorded without time compression; excerpts are acknowledged.

### R4-19 — F4U Corsair · 00:57:00–00:59:00 · G

**Picture:** Corsair: sliding-canopy excerpt ends in a readable settled position.

**Cast / paint:** F4U Corsair — Coastal Three Tone. **Environment:** `ground_breeze`.

**Preparation:** Home Corsair, Coastal Three Tone, runway; verify support and stable idle at the west threshold. **At the edit’s start:** N15 E−47, heading east; ground solver owns supported CG/attitude. Wheels stay down.

**Blocking (NE_surface):** 0s: (15, -47, 0) Ground reference, never an instruction to put CG at D=0.

**Camera:** subject_relative, FRU, FOV 35°. 0s: (1, -1.7, 0.85) Camera offsets in horizontal forward/right/up from the actual aircraft CG; target the named mechanism, with fixed structure visible. Rehearse near-plane/mesh clearance.

**Action:**

- Frame canopy against fixed cockpit rim; no animated stick/pedals implied.
- U opens canopy; record complete 2.5 s travel and select a two-second excerpt plus settled end.

**Exit / cut:** Mechanism motion and its settled end are readable. Hold the settled canopy, then introduce the separate clean Mustang view before the live input demonstration. A new aircraft is intentional.

**Continuity:** Coastal Three Tone throughout. Same heading/support; no running takeoff during ground checks. Gear remains down; no unshown fold-state jump.

**Screen / axis:** neutral. Stationary grounded Corsair; name the viewed side and fixed hinge reference. Angle changes are explicit detail cuts, not a moving-flight axis. **Next cut:** R4-22 · hard cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Fold: weight on wheels, speed below 0.5 m/s, idle until spread/locked. Native travel is recorded without time compression; excerpts are acknowledged.

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

**Screen / axis:** screen left. Heading-relative side determines projected nose. Camera follows the subject; subject screen translation is not promised. **Next cut:** R4-23 · same take continuation.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

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

**Screen / axis:** screen left. Heading-relative side determines projected nose. Camera follows the subject; subject screen translation is not promised. **Next cut:** R4-24 · hard cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

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

**Screen / axis:** screen right. Eastbound subject; camera south gives nose-right, north gives nose-left. Tracking holds subject position while scenery moves. **Next cut:** R4-25 · same attempt ellipsis.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

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

**Screen / axis:** screen right. Eastbound subject; camera south gives nose-right, north gives nose-left. Tracking holds subject position while scenery moves. **Next cut:** R4-26 · same attempt ellipsis.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

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

**Exit / cut:** Controlled touchdown visibly completed. Let the genuine practice landing settle, then cut to the Bisonte baseline bump response. This begins the setup-and-response chapter; no shared flight or failure cause is implied.

**Continuity:** Same recorded practice attempt across 24–26, same HONEYBEE paint and wind. Failure is configured, not caused by later storm or a fabricated empty fuel gauge.

**Screen / axis:** screen right. Eastbound subject; camera south gives nose-right, north gives nose-left. Tracking holds subject position while scenery moves. **Next cut:** R4-32 · context reset.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Generic capture_flight.gd hard-codes failures=0: do not use it unchanged for this scene. Use ordinary production failure settings or a later reviewed adapter.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-32 — MT8 Bisonte · 01:13:00–01:15:45 · G

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

**Screen / axis:** screen right. Eastbound subject; camera south gives nose-right, north gives nose-left. Tracking holds subject position while scenery moves. **Next cut:** R4-33 · hard cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-33 — MT8 Bisonte · 01:15:45–01:17:15 · U

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

**Screen / axis:** neutral. Context or native UI defines the frame; inspect the real image. **Next cut:** R4-34 · hard cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Source apply prepares/restarts the session; there is no live in-air parameter change.

**Accept only when:** Genuine UI state, selected values and completed loading are readable; no advancing flight tick is required. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-34 — MT8 Bisonte · 01:17:15–01:20:00 · G

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

**Screen / axis:** screen right. Eastbound subject; camera south gives nose-right, north gives nose-left. Tracking holds subject position while scenery moves. **Next cut:** R4-35 · hard cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-35 — Ugly Stick .61 glow · 01:20:00–01:21:30 · U

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

**Screen / axis:** neutral. Context or native UI defines the frame; inspect the real image. **Next cut:** R4-36 · hard cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Genuine UI state, selected values and completed loading are readable; no advancing flight tick is required. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-36 — Ugly Stick .61 glow · 01:21:30–01:23:15 · G

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

**Screen / axis:** screen right. Eastbound subject; camera south gives nose-right, north gives nose-left. Tracking holds subject position while scenery moves. **Next cut:** R4-37 · hard cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `existing_adapter` — `capture_flight.gd --workshop-scale=5 + validated lighting preset`. Real trial and cinematic trio are separate sources; framing changes are explicit.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-37 — Ugly Stick .61 glow · 01:23:15–01:25:00 · G

**Picture:** Actual 10% baseline Stick trial in a deliberately closer readable view, with explicit size label and field context.

**Cast / paint:** Ugly Stick .61 glow — HONEYBEE · 07. **Environment:** `day_calm`.

**Preparation:** Freeze actual 10% Workshop trial from same baseline and paint. **At the edit’s start:** Tiny trial passes near a recognizable ordinary field marker; verify body is findable.

**Blocking (NED):** 0s: (30, -4, -1.5) → 1.75s: (30, 4, -1.5) Eight-metre proposed corridor; actual scaled speed and safe clearance need trial evidence.

**Camera:** parallel_east, NED, FOV 24°. 0s: (28.5, -5, -1.2) → 1.75s: (28.5, 3, -1.2) Dedicated close parallel view, nominal range about 1.83 m. Follow the actual 10 percent trial; retain an ordinary fixed field marker and the size label. This is different framing from the giant trial. No screen-size comparison is implied; tiny-aircraft and camera clearance still need proof.

**Action:**

- Record the real 10% trial without speed-up.
- Keep TINY · 10% / approx. 15 cm on screen.

**Exit / cut:** Tiny aircraft can be recognized in full-motion playback. Cut to the disclosed same-depth comparator.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Screen / axis:** screen right. Eastbound subject; camera south gives nose-right, north gives nose-left. Tracking holds subject position while scenery moves. **Next cut:** R4-38 · hard cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `camera_trial_composition_pending` — `Real 10 percent Workshop trial with a separately qualified close-camera route`. The close geometry is proposed. The current stock camera-recipe guard rejects the Workshop trial runtime model ID (workshop-<hash>); exporting this shot is refused. Qualify a route that preserves the immutable Workshop base/trial/model identity before capture. Do not weaken the guard to compare only the visual family.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-38 — Ugly Stick .61 glow · 01:25:00–01:29:00 · P

**Picture:** Same-depth 500/100/10% cinematic comparator; correct span labels and disclosure.

**Cast / paint:** Ugly Stick .61 glow — HONEYBEE · 07. **Environment:** `editorial`.

**Preparation:** Use existing three-size presentation scene; all three represent the same glow Stick baseline. **At the edit’s start:** Giant / Original / Tiny at one depth, with labels 7.62 m / 1.52 m / 15 cm.

**Blocking (model_local):** 0s: (0, 0, 0) Formation origin only. Existing --sizes layout owns separation; log actual model/paint identity before acceptance.

**Camera:** existing_sizes_director, FRU, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Use the existing same-depth layout and move toward original/tiny; actual camera sample/trim remains to be selected.

**Action:**

- Hold enough of all three to read the ratio before moving closer.
- Keep CINEMATIC SIZE COMPARISON throughout.

**Exit / cut:** All three sizes and disclosure have been readable. After the labelled size comparison, reset geography with real AI circuit traffic. Remove presentation labels at the cut; keep AI identity explicit.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Screen / axis:** neutral. Context or native UI defines the frame; inspect the real image. **Next cut:** R4-27 · context reset.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `existing_adapter` — `tools/trailer/capture_formation.gd --sizes`. Existing comparator skin must be verified/adapted to HONEYBEE or explicitly recorded as factory; plan does not apply a new paint to this adapter.

**Accept only when:** Native inspection/presentation motion and its disclosure are readable; no flight session is implied. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-27 — Ugly Stick .61 glow · 01:29:00–01:33:00 · G

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

**Screen / axis:** screen right. Eastbound subject; camera south gives nose-right, north gives nose-left. Tracking holds subject position while scenery moves. **Next cut:** R4-28 · hard cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `existing_adapter` — `capture_flight.gd normal lighting route + accepted companions`. Companion qualification depends on the exact source/build; current branch must pass its ordinary admission. Do not use Workshop lighting route or re-pin acceptance.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-28 — Ugly Stick .61 glow · 01:33:00–01:37:00 · G

**Picture:** Eligible airplane in an exact calibrated Phoenix panorama; fixed pilot-eye view and experimental-runway label.

**Cast / paint:** Ugly Stick .61 glow — HONEYBEE · 07. **Environment:** `phoenix_airfield`.

**Preparation:** Import/select exact calibrated Airfield panorama; confirm matching hash and experimental runway admission. **At the edit’s start:** Photo-eye remains at N0 E0, eye height 1.7 m in this separate field coordinate system.

**Blocking (NED):** 0s: (12, -29, -4) → 4s: (12, 31, -4) This field runway is centered N12 E1, length 42 m, width 9 m. Corridor extends beyond runway ends in the image; actual collision/imagery fit must pass.

**Camera:** fixed_tracking, NED, FOV 40°. 0s: (0, 0, -1.7) Keep the calibrated photo eye fixed; pan direction only. No translated orbit or parallax claim.

**Action:**

- Launch supported runway aircraft through the real imported-site flow.
- Retain four seconds of a readable pass and IMPORTED SCENERY · EXPERIMENTAL RUNWAY.

**Exit / cut:** Aircraft remains identifiable against panorama. Deliberate context and direction reset into a separate storm flight. Match brightness/subject eye position if possible; do not call the opposite-side views a continuous direction match.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Screen / axis:** screen right. Eastbound subject; camera south gives nose-right, north gives nose-left. Tracking holds subject position while scenery moves. **Next cut:** R4-29 · context reset.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Calibrated source entry exists; installed local panorama and usable source images are not supplied by this plan.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-29 — P-51D Mustang · 01:37:00–01:41:00 · G

**Picture:** Separate ordinary airplane flight against an actual storm cloud flash; bolt only if recorded.

**Cast / paint:** P-51D Mustang — P-51D Mustang factory. **Environment:** `storm`.

**Preparation:** Ordinary Mustang factory-paint flight, electrical_storm appearance preset; no configured practice failure. **At the edit’s start:** Trim in a clear-air corridor with dark clouds behind the aircraft; record until an actual flash occurs.

**Blocking (NED):** 0s: (60, -50, -20) → 4s: (60, 50, -20) Nominal four-second corridor at source start speed; choose the real flash interval, not an invented time trigger.

**Camera:** subject_relative, FRU, FOV 36°. 0s: (10, -7, 3) FRU = forward/right/up metres in horizontal heading frame; follow actual subject, not its roll. This is a camera target, not a new player camera.

**Action:**

- Keep readable model body against the cloud bank.
- Select actual flash and native storm audio if present.
- A visible bolt is optional; no added lightning graphic.

**Exit / cut:** Flash resolves while plane remains readable. Cut after a recorded flash resolves into the clearly separate afternoon Extra smoke pass. The warm scene is a new flight, not instant weather clearing.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Screen / axis:** screen left. Heading-relative side determines projected nose. Camera follows the subject; subject screen translation is not promised. **Next cut:** R4-30 · context reset.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `existing_adapter` — `capture_flight.gd --shot=storm`. Existing adapter uses the real sky preset; specific framing and event interval require rehearsal.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-30 — Extra 300S · 01:41:00–01:45:00 · G

**Picture:** Extra 300S: warm-light bank/climb in its shipped factory finish with a qualified show-smoke profile.

**Cast / paint:** Extra 300S — Extra 300S factory. **Environment:** `afternoon_calm`.

**Preparation:** Extra factory paint; admit authored stock show-smoke profile and actual pump control. **At the edit’s start:** Establish smoke before selected clip; aircraft enters in a gentle climbing bank.

**Blocking (NED):** 0s: (30, -44, -10) → 2s: (34, 0, -13) → 4s: (43, 40, -18) Climbing arc is a proposed composition; speed and bank are pilot-controlled, not animated positions.

**Camera:** subject_relative, FRU, FOV 36°. 0s: (-9, -6, 3) FRU = forward/right/up metres in horizontal heading frame; follow actual subject, not its roll. This is a camera target, not a new player camera.

**Action:**

- Preroll until plume is established and real outlet/color verified.
- Use one climbing bank, not a compressed multiple-roll stunt.
- Leave breathing room behind tail for the actual plume.

**Exit / cut:** Plane and smoke arc remain in frame. Resolve the real smoke bank and open the musical texture into the Corsair orbit. The new aircraft and golden-hour setting begin the signature chapter.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Screen / axis:** screen left. Heading-relative side determines projected nose. Camera follows the subject; subject screen translation is not promised. **Next cut:** R4-39 · hard cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `existing_adapter` — `capture_flight.gd + stock smoke / existing Extra director`. Select and verify an existing supported show-smoke color; no custom color/paint is claimed from its name alone.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-39 — F4U Corsair · 01:45:00–01:55:00 · P

**Picture:** Continuous eased Corsair orbit with all 13 stock liveries; final scheme holds.

**Cast / paint:** F4U Corsair — Coastal Three Tone. **Environment:** `golden_calm`.

**Preparation:** Corsair airborne, wings spread, gear/flaps/hook retracted, canopy closed. Load full ordered 13-asset cycle. **At the edit’s start:** Real session established before recording; camera settles into front-left quarter.

**Blocking (NED):** 0s: (15, -115, -6) → 5s: (36, -2.5, -6) → 10s: (96, 95, -6) Illustrative turning corridor for the existing light-left-bank director (~9.7°), not a straight 230 m rail. Coordinates are proposed and unflown; actual heading/track must be logged.

**Camera:** continuous_heading_orbit, FRU, FOV 34°. 0s: (5.3623, -4.4995, 0.9) → 5s: (-5.3623, 4.4995, 1.4) → 10s: (5.3623, -4.4995, 0.9) Existing _orbit_camera is relative to the visual model-root origin, not simulated CG: 7 m radius, angle −40° + 360° smoothstep(t/10); height 0.9 + 0.5 sin(pi*p); look 0.2 m above visual root. These three samples illustrate the analytic orbit, not linear interpolation.

**Action:**

- Show twelve 45-frame planned skin holds, then a 60-frame Coastal Three Tone finish.
- Use the new --livery-hold-last flag so the visual cycle never returns to midnight at 9.75 s.
- Check actual simulation-time/presented-frame alignment; the driver clock and edit clock are different.

**Exit / cut:** Final presented paint is three_tone; framing returns to front-left quarter. Hard cut from the final Three Tone front-left orbit view to a compatible screen-left Corsair lake silhouette. Compare actual exposure and configuration; the location and capture route intentionally change.

**Continuity:** Only livery assets change inside the orbit; no airframe, scale, gear, canopy, weather or camera-path jump. Ground and final lake use the same Coastal Three Tone asset.

**Screen / axis:** variable. Continuous full orbit deliberately crosses the axis; the crossing is visible. Its final nose-left Three Tone view motivates the lake cut. **Next cut:** R4-40 · graphic match.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `existing_adapter` — `tools/trailer/capture_flight.gd --shot=corsair-orbit + flight_director.gd`. Exact new entry coordinates need a reviewed pre-start fixture; existing orbit flight and camera already exist. Hold-last is implemented/tested, footage timing remains unqualified.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-40 — F4U Corsair · 01:55:00–02:01:00 · G

**Picture:** Six uninterrupted seconds of Corsair shoreline approach, water crossing and exit, holding Coastal Three Tone and actual matching reflection if qualified.

**Cast / paint:** F4U Corsair — Coastal Three Tone. **Environment:** `golden_calm`.

**Preparation:** Separate real Corsair pass, Coastal Three Tone, matching resolved golden-hour date/place/sky and clean flight configuration. Compare view-dependent exposure in the actual selected frames. **At the edit’s start:** Rehearsal entry mark N128 E55 D−2.55, heading east. Preroll target N128 E9 at the same height, nominally two seconds earlier.

**Blocking (NED):** 0s: (128, 55, -2.55) → 3s: (128, 124, -2.55) → 6s: (128, 193, -2.55) 138 m straight reference corridor at 23 m/s configured start speed. D−2.55 is 3 m above mean water D+0.45, not 3 m above lakebed. Actual flight/terrain clearance remains unverified.

**Camera:** parallel_east, NED, FOV 34°. 0s: (145, 47, -1) → 3s: (145, 116, -1) → 6s: (145, 185, -1) Parallel north-bank eye N145/D-1, east = actual displayed CG east - 8 m. Aim at that CG north/east projected onto mean water D+0.45, so the aircraft sits above the aim and its real reflection can sit below it. Vertical FOV 34 degrees. Both CG and actual aim are recorded; no aircraft pose, reflection or exposure is fabricated.

**Action:**

- 0–about 1.47 s nominal: land/shore approach into the lake composition.
- About 1.47–4.69 s nominal: cross water between E≈88.73 and E≈162.91.
- Last ~1.31 s nominal: clear the far shoreline while the camera continues alongside the actual aircraft; cut on a readable settled silhouette.

**Exit / cut:** Aircraft clears water and shoreline with the final skin unchanged. Complete the water crossing and shore exit, then cut to the Bisonte at the same lake in a distinct sunset scene. Match the waterline/subject eye position; no continuous trajectory is implied.

**Continuity:** Coastal Three Tone, closed canopy, spread wings, clean gear/flaps/hook. Match dominant nose orientation and color; this is an edited transition from orbit, not proof of a continuous world trajectory.

**Screen / axis:** screen left. Eastbound subject; camera south gives nose-right, north gives nose-left. Tracking holds subject position while scenery moves. **Next cut:** R4-44 · graphic match.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `camera_adapter_implemented_flight_pending` — `capture_flight.gd --camera-recipe plus an explicitly qualified pilot director / real flown approach`. R7 water-plane aim is a camera-only extension. It follows actual subject north/east and the pinned mean-water height, and records actual CG separately. It does not fly the path, certify clearance or produce reflection; use a qualified real approach and planar/renderer evidence for any mirrored take.

**Accept only when:** Nominal geometry gives only ~3.23 s above water, not six; actual speed/path govern footage. Check actual CG, wingtip and prop clearance against water/shore/objects. Reflection must be from the same real frame and paint; keep an honest unmirrored take if it fails. Read camera recipe, source-plan hash, actual eye/CG/FOV and advancing ticks from the take manifest. Reject faults, pause, crash, stale camera records or unexplained trajectory drift. Match final orbit nose orientation to the accepted lake take. Actual subject/HUD readability and camera/shoreline clearance require rendered footage. Inspect both complete airframe and complete same-frame reflection with margin in the actual water-crossing frames. Record actual exposure; frozen sun does not freeze view exposure.

### R4-44 — MT8 Bisonte · 02:01:00–02:06:00 · G

**Picture:** Bisonte at the shallow shore: real tires, mud/water contact, modest droplets/rings and actual sound.

**Cast / paint:** MT8 Bisonte — Amarillo Rayo. **Environment:** `sunset_calm`.

**Preparation:** Bisonte Amarillo Rayo, native lake_shore spawn, separate sunset session; restore damping 1.00 after the earlier Lab comparison. Verify real tyre/body contrast before filming. **At the edit’s start:** Supported dry spawn N145.5 E125 facing south; read back native staging acceptance.

**Blocking (NE_surface):** 0s: (145.5, 125, 0) → 3.5s: (138.5, 125, 0) → 5s: (138, 125, 0) Plan-view only; stop at N138, do not continue to N137. Proposed 7.5 m route with braking; actual tire footprint/depth and stopping distance require proof.

**Camera:** fixed_tracking, NED, FOV 42°. 0s: (142, 130, -0.45) Low east-side three-quarter camera tracks tires and waterline. Keep camera on verified dry support; actual native moving orbit is a fallback with its own recorded eye.

**Action:**

- Start rolling before the cut; ease toward the shore on low throttle.
- Brake early to stop at or north of N138; retain wheels and modest real effects.
- Hold actual settling and electric motor/shore sound.

**Exit / cut:** Truck remains controllable and stops in the proven shallow route. Hold the real shallow stop and let water/electric sound resolve, then make a deliberate UI chapter cut into Creator. The following preview/trial is a separate setup.

**Continuity:** Same Amarillo Rayo throughout, normal scale and restored damping 1.00. No continuation of the earlier Lab experiment is implied.

**Screen / axis:** screen left. Southbound subject viewed from the east/west side; confirm actual projection at the cut. **Next cut:** R4-41 · context reset.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `adapter_needed` — `manual rehearsal / existing production session`. Shared GroundScene World supports the sunset preset. Existing capture_vehicles.gd is a four-second chase/input reference, not this five-second shore route. Use a qualified adapted/manual take; capture_car_jump.gd is hardcoded to Monster Car 2.

**Accept only when:** Source spawn checks entry sample only; this full driving route still needs runtime qualification. N137 may be materially deeper; reject overshoot, deep water and unobserved effect claims.

### R4-41 — Brand/end card · 02:06:00–02:08:00 · U

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

**Screen / axis:** neutral. Context or native UI defines the frame; inspect the real image. **Next cut:** R4-42a · hard cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Genuine UI state, selected values and completed loading are readable; no advancing flight tick is required. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-42a — Easystar · 02:08:00–02:09:00 · U

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

**Screen / axis:** screen right. Actual Creator three-quarter view; keep nose-right, centre and approximate occupancy consistent without distorting model proportions. **Next cut:** R4-42b · silhouette cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42b — J3 Piper Cub · 02:09:00–02:09:30 · U

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

**Screen / axis:** screen right. Actual Creator three-quarter view; keep nose-right, centre and approximate occupancy consistent without distorting model proportions. **Next cut:** R4-42c · silhouette cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42c — Fokker DR-1 · 02:09:30–02:10:00 · U

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

**Screen / axis:** screen right. Actual Creator three-quarter view; keep nose-right, centre and approximate occupancy consistent without distorting model proportions. **Next cut:** R4-42d · silhouette cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42d — Radian · 02:10:00–02:10:30 · U

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

**Screen / axis:** screen right. Actual Creator three-quarter view; keep nose-right, centre and approximate occupancy consistent without distorting model proportions. **Next cut:** R4-42e · silhouette cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42e — Spitfire · 02:10:30–02:11:00 · U

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

**Screen / axis:** screen right. Actual Creator three-quarter view; keep nose-right, centre and approximate occupancy consistent without distorting model proportions. **Next cut:** R4-42f · silhouette cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42f — Beaver Float-plane · 02:11:00–02:11:30 · U

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

**Screen / axis:** screen right. Actual Creator three-quarter view; keep nose-right, centre and approximate occupancy consistent without distorting model proportions. **Next cut:** R4-42g · silhouette cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42g — Tiger Moth · 02:11:30–02:12:00 · U

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

**Screen / axis:** screen right. Actual Creator three-quarter view; keep nose-right, centre and approximate occupancy consistent without distorting model proportions. **Next cut:** R4-42h · silhouette cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42h — Extra · 02:12:00–02:12:30 · U

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

**Screen / axis:** screen right. Actual Creator three-quarter view; keep nose-right, centre and approximate occupancy consistent without distorting model proportions. **Next cut:** R4-42i · silhouette cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42i — P-51 Mustang · 02:12:30–02:13:00 · U

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

**Screen / axis:** screen right. Actual Creator three-quarter view; keep nose-right, centre and approximate occupancy consistent without distorting model proportions. **Next cut:** R4-42j · silhouette cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42j — F-117 · 02:13:00–02:14:00 · U

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

**Screen / axis:** screen right. Actual Creator three-quarter view; keep nose-right, centre and approximate occupancy consistent without distorting model proportions. **Next cut:** R4-42k · silhouette cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42k — BD-5J · 02:14:00–02:14:30 · U

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

**Screen / axis:** screen right. Actual Creator three-quarter view; keep nose-right, centre and approximate occupancy consistent without distorting model proportions. **Next cut:** R4-42l · silhouette cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42l — B-25 · 02:14:30–02:15:00 · U

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

**Screen / axis:** screen right. Actual Creator three-quarter view; keep nose-right, centre and approximate occupancy consistent without distorting model proportions. **Next cut:** R4-42m · silhouette cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42m — C-130 · 02:15:00–02:15:30 · U

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

**Screen / axis:** screen right. Actual Creator three-quarter view; keep nose-right, centre and approximate occupancy consistent without distorting model proportions. **Next cut:** R4-42n · silhouette cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42n — Beluga · 02:15:30–02:16:00 · U

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

**Screen / axis:** screen right. Actual Creator three-quarter view; keep nose-right, centre and approximate occupancy consistent without distorting model proportions. **Next cut:** R4-42o · silhouette cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42o — A6-Zero · 02:16:00–02:16:30 · U

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

**Screen / axis:** screen right. Actual Creator three-quarter view; keep nose-right, centre and approximate occupancy consistent without distorting model proportions. **Next cut:** R4-42p · silhouette cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42p — Agri Duck Duster · 02:16:30–02:17:00 · U

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

**Screen / axis:** screen right. Actual Creator three-quarter view; keep nose-right, centre and approximate occupancy consistent without distorting model proportions. **Next cut:** R4-42q · silhouette cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42q — MC Tiburon-bipe-7-2 · 02:17:00–02:17:30 · U

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

**Screen / axis:** screen right. Actual Creator three-quarter view; keep nose-right, centre and approximate occupancy consistent without distorting model proportions. **Next cut:** R4-42r · silhouette cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-42r — MC 3D Hobby Shops Extra 330 Red · 02:17:30–02:18:00 · U

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

**Screen / axis:** screen right. Actual Creator three-quarter view; keep nose-right, centre and approximate occupancy consistent without distorting model proportions. **Next cut:** R4-43 · graphic match.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Current-build visual admission and source/texture hashes are recorded. This preview does not establish flight eligibility; no repaints count as extra models.

### R4-43 — MC 3D Hobby Shops Extra 330 Red · 02:18:00–02:21:00 · G

**Picture:** Same final previewed model in its genuine eligible Creator trial; experimental/estimated or donor qualification.

**Cast / paint:** MC 3D Hobby Shops Extra 330 Red — Original admitted source textures; source hash and exact texture identity pending.. **Environment:** `day_calm`.

**Preparation:** Use the exact last-previewed Extra 330 Red Creator draft. Complete eligible estimated/donor setup and its actual trial gates. **At the edit’s start:** Same model/source textures. Retain the real trial qualification; aircraft has stabilized before the three-second selection.

**Blocking (NED):** 0s: (25, -20, -10) → 3s: (25, 20, -10) Provisional framing corridor only. Actual scaled dimensions, donor/derived trim, speed and spawn are unknown until this exact draft qualifies.

**Camera:** subject_relative, FRU, FOV 40°. 0s: (-7, 4, 2) Proposed rear-right/south-side view for an eastbound model so the nose reads screen-right, matching the final Creator preview. Scale distance to admitted model bounds; verify actual orientation/size, do not mirror footage.

**Action:**

- Show real eligible flight, with EXPERIMENTAL TEST FLIGHT and actual estimated/donor qualification.
- Keep same source model/paint from final preview.

**Exit / cut:** Three seconds of readable controlled flight. Hard cut to a clearly new, labelled Turbo Lumber night flight. Match screen-right nose/eye position if the accepted take permits it; the new aircraft and session remain explicit.

**Continuity:** R4-42r and R4-43 use the exact same draft/model-root/texture hashes. If another model qualifies, reorder the last preview and plan together.

**Screen / axis:** screen right. Heading-relative side determines projected nose. Camera follows the subject; subject screen translation is not promised. **Next cut:** R4-31 · context reset.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Visual conversion alone is insufficient; trial admission and flight must be demonstrated. If no candidate qualifies, change ending to clearly labelled preview-only and remove flight promise.

### R4-31 — Turbo Lumber Evolution · 02:21:00–02:25:00 · G

**Picture:** Turbo Lumber: a clearly identified, readable night-flight silhouette and real admitted lights form the final gameplay image.

**Cast / paint:** Turbo Lumber Evolution — Turbo Lumber factory. **Environment:** `night_calm`.

**Preparation:** Turbo Lumber factory paint with the admitted Night Radian Workshop lighting profile, in a separate field-world night session. Record the actual profile/trial and resolved nearly-full-moon date. **At the edit’s start:** Body, wing and genuine lights visible before first retained frame.

**Blocking (NED):** 0s: (25, -26.2, -6) → 4s: (25, 26.2, -6) Nominal distance uses ~13.1 m/s configured start speed; actual flight readback owns the take.

**Camera:** existing_lumber_dusk, FRU, FOV 33°. 0s: (5.4, 2.2, 0.1) → 4s: (4.5, 1.8, 0.1) Use the actual lumber_dusk_director path in the horizontal heading frame around the visual model root; look 0.4 m above that root. Source time runs over the director duration; align the retained source window instead of assuming edit frame zero is driver zero. Right-side view aims for a screen-right nose. Rehearse real night body readability.

**Action:**

- Use a calm pass; do not bury the airframe in darkness.
- Keep actual navigation/lighting behavior; no glowing-dot-only composition.
- If night cannot expose the body, use the declared blue-hour replacement and update metadata.

**Exit / cut:** Last frame still identifies Turbo Lumber. Let the recognizable aircraft and lights resolve, then cut cleanly to the five-second invitation. Engine sound can tail under the card; preserve a settled readable end.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Screen / axis:** screen right. Heading-relative side determines projected nose. Camera follows the subject; subject screen translation is not promised. **Next cut:** R4-45 · hard cut.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `existing_adapter` — `capture_flight.gd + Lumber lighting/director route`. The real dusk director provides the listed root-relative camera. --lighting-preset=night_radian uses the admitted Workshop route by default; lights are customization, not factory paint. The stock vehicle harness/capture options do not automatically enable campfire or all direct-app world flags. No campfire insert is required here.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-45 — Brand/end card · 02:25:00–02:30:00 · E

**Picture:** Stable cinematic OPEN RC SIMULATOR / PLAY FREE / official project destination; five fully settled seconds.

**Cast / paint:** Brand/end card — Not applicable. **Environment:** `editorial`.

**Preparation:** Use the R7 title plan and a neutral dark end-card base. Confirm the official destination before publishing. Add product status or music credits only if explicitly verified and required by the selected assets. **At the edit’s start:** Full card already settled at start of five-second hold.

**Blocking (none):** Native UI/preset or actual camera readback; no invented world coordinates.

**Camera:** end_card, none, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Centered product name, invitation and full destination in the R7 typography system. No inherited beta badge, old slogan or soundtrack attribution.

**Action:**

- Hold five full seconds; no extra model flicker or additional feature list.
- Resolve score and fade real final sound.

**Exit / cut:** Destination and call to action have been readable. End cleanly.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Screen / axis:** neutral. Context or native UI defines the frame; inspect the real image. **Next cut:** end · end.

**Text:** title-plan-r7.json; real HUD and model-attached span labels require their own captured/layout evidence.

**Implementation:** `editorial` — `assemble.py style=cinema with title-plan-r7.json`. Cinema renderer and global-frame overlays; actual footage and soundtrack remain unselected.

**Accept only when:** Five fully settled seconds, correct destination, final phone readability and any actual asset-credit obligations are checked before release. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

<!-- END GENERATED SHOT CARDS -->

## Rehearsal and remaining work

Use [direction and continuity](direction-and-continuity.md) for the field-world preset API, fixed Day distinction, frozen sky clock versus adaptive exposure, scene axes, reflection requirements and actual camera routes. Start with the hardest proof: readable opener, ground mechanisms, real recovery, lake airframe/reflection, last-import identity and night body. Build the remaining takes around accepted results, not around a simulated paper trajectory.

The [verification gates](verification-gates.md) and [Windows/RTX3090 capture guide](windows-rtx3090-capture.md) own actual footage acceptance. Each source needs its build, model/skin/scale, session/readback, source frames and ticks, renderer/backend, camera, time/sky/wind/exposure and actual audio. Check native speed and phone/muted reading. The [90-second and 32-second companion films](feature-companion-films.md) retain deeper field and mechanism material without overloading this master.

R7 is a coherent production specification with bounded camera/title implementation. It does not establish a filmed 150-second trailer, imported-model release qualification, a selected soundtrack, a measured performance result or a finished public download flow.
