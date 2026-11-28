> Historical R5 revision. [R6](cinematic-script-r6.md) is the current directing and implementation authority.

# OPEN RC SIMULATOR — Trailer 2.0

## Director’s shooting script — Revision 5: EXPAND YOUR HANGAR

**21 November 2026 · Current working shooting script and initial capture code**
**Track / owner:** V2 / trailer director-editor and lead developer. **Master:** 150.000 seconds, 16:9, 1920×1080 at 60 fps; English; no voice-over required.
**Source baseline:** `57abea025f62b20233ca281d58d2acbee4ab8b8e`; trailer parent `55935b5bb31a5178fdf767b430ba35ad852be256`. No new footage or model imports have been accepted.

R5 replaces the [R4 screenplay](cinematic-script-r4.md) as the working directing document. It keeps the same 150-second edit and stable **R4-01…R4-45 / R4-42a…r shot IDs**, so existing notes still locate the right cut. The [storyboard](storyboard-150s.md) owns edit boundaries. The [machine-readable shot plan](shot-plan-r5.json) owns cast identities, exact proposed coordinates, camera targets and actions. The shot cards below are its readable companion. Keep them synchronized when changing blocking.

### What changes in this pass

Every cut now states how to prepare it, what is already happening when the edit starts, where the subject enters and exits, how to place the camera, which controls or state changes matter, and what makes the take usable. The cast has concrete factory/stock choices. Unknown imported source hashes remain explicit production dependencies.

The Corsair’s six seconds now tell a complete **approach → water crossing → exit**. Its configured 23 m/s start speed implies 138 m in six seconds, longer than the selected water chord. We preserve the six-second hold and the real shoreline instead of asking for an impossible six-second straight run entirely above this lake. The 13-skin orbit ends on **Coastal Three Tone**, matching the ground sequence and lake.

The first runtime change is deliberately narrow: the existing capture director accepts `--livery-hold-last`. It prevents the cycle wrapping to the first skin near the end of the orbit. The new offline plan tool checks timing, cast/skin references, source hashes and continuity, converts coordinates and draws blocking maps. It does not fly the aircraft or turn proposed points into physical evidence.

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

The proposed eastbound corridor is **N128 / E55 → E124 → E193**, at **D−2.55**. That is 3 m above the mean water plane, with a nominal 23 m/s planning speed. The camera is at **N145 / E125 / D−1**, on the north-bank side, panning toward the real aircraft. Eastbound movement therefore reads **right-to-left** from this camera. Match the final orbit’s dominant nose orientation; the hard cut is between separately filmed views.

The actual polygon intersects this line near **E88.73** and **E162.91**. Its water chord is approximately **74.18 m**, or **3.225 seconds at the nominal speed**. The remaining part of the six-second shot includes approach and exit. CG/wingtip/prop clearance, camera support, objects, actual speed and reflection still require a real rehearsal. A generic “altitude above terrain” spawn can measure from the lakebed; it must not be confused with height above water.

The [lake blocking map](diagrams/r5-lake-blocking.svg) visualizes these source/target coordinates; the [truck blocking map](diagrams/r5-truck-blocking.svg) shows the source tabletop footprint and proposed vehicle/camera marks. Dashed lines connect proposed marks; they are not recorded trajectories.

## Detailed shot cards

Times below use **MM:SS:FF at 60 fps**. A camera FOV is the proposed/native Godot property value, not a measured full-frame lens. Pilot inputs are rehearsal cues, not promises of an exact trajectory. Every continuous action must come from advancing real session state; P and E sources retain their explicit labels.

### R4-01 — Vantage Jet · 00:00:00–00:04:00 · G

**Cast / paint:** Vantage Jet — Sabre Plata. **Environment:** `day_calm`.

**Preparation:** Home Vantage, Sabre Plata, airborne. Rehearse the roll well before the selected clip. **At the edit’s start:** Already established inverted flight on entry; runway and horizon visible.

**Blocking (NED):** 0s: (15, -58, -8) → 2s: (15, 0, -8) → 4s: (15, 58, -8) 29 m/s is configured launch speed, not measured pass speed; points are a 116 m nominal corridor.

**Camera:** fixed_tracking, NED, FOV 38°. 0s: (0, 0, -1.6) Fixed eye; pan/tilt to actual aircraft CG. Keep world horizon upright.

**Action:**

- Before edit: establish altitude and inversion with genuine roll input.
- 0–3 s: hold a stable canopy-down pass; no video rotation.
- 3–4 s: leave the camera line cleanly; keep the real turbine sound.

**Exit / cut:** Aircraft clears east side of framing; attitude remains readable. Hard cut from turbine pass to nitro truck ramp; carry momentum left-to-right.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Implementation:** `adapter_needed` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Genuine inversion and ground/horizon agree. If unsafe/unreadable in simulation, use the declared real upright banked pass; update take status.

### R4-02 — MONSTER CAR 2 · 00:04:00–00:08:00 · G

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

**Implementation:** `existing_adapter` — `tools/trailer/capture_car_jump.gd + production ground activity`. Existing jump capture supplies ordinary driving; camera/skin and exact clip must be rehearsed for this cast.

**Accept only when:** Monster-specific jump must be demonstrated; Bisonte tests do not qualify the nitro truck. Actual take contains the complete landing; no speed-up or cropped outcome.

### R4-03 — Ugly Stick Electric 6S · 00:08:00–00:11:00 · G

**Cast / paint:** Ugly Stick Electric 6S — NEON RONIN · Cyberpunk. **Environment:** `day_calm`.

**Preparation:** Home Ugly Stick Electric 6S, NEON RONIN; airborne. **At the edit’s start:** Enter west of runway at about 4 m above reference ground; trim before mark.

**Blocking (NED):** 0s: (18, -22.5, -4) → 1.5s: (18, 0, -4) → 3s: (18, 22.5, -4) 45 m reference corridor at the configured 15 m/s start speed; actual track may differ.

**Camera:** fixed_tracking, NED, FOV 38°. 0s: (4, 0, -1.2) Fixed eye; pan/tilt to actual aircraft CG. Keep world horizon upright.

**Action:**

- Preroll at least two settled seconds before entry.
- Hold a simple lateral pass; avoid a roll that hides the selected paint.
- Keep UGLY STICK · ELECTRIC 6S readable without covering the model.

**Exit / cut:** Full airframe exits east. Match left-to-right travel into MoonRunner launch.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Implementation:** `adapter_needed` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-04 — MoonRunner · 00:11:00–00:14:00 · G

**Cast / paint:** MoonRunner X99 — BOLIDO - re-entry heat shield. **Environment:** `day_calm`.

**Preparation:** Home MoonRunner X99, BOLIDO, explicit hand_launch. Verify the choice was not replaced. **At the edit’s start:** Native release at N9 E0, terrain +1.9 m, 6.5 m/s, 5° climb in calm eastbound setup.

**Blocking (NED):** 0s: (9, 0, -1.9) → 3s: (10, 18, -4.5) First point uses the flat-reference terrain; verify actual sampled release altitude. Exit is a gentle climbing target, not source launch behavior.

**Camera:** fixed_tracking, NED, FOV 42°. 0s: (1, 6, -1) Fixed eye; pan/tilt to actual aircraft CG. Keep world horizon upright.

**Action:**

- Start the cut at the actual release state; no throwing person.
- Keep wings identifiable through a shallow climbing bank.
- Do not cut until positive climb is visible.

**Exit / cut:** Flying wing clears the launch area, nose still moving right. Cut from dark BOLIDO silhouette to the white blimp envelope.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Implementation:** `adapter_needed` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-05 — Blimp · 00:14:00–00:18:00 · G

**Cast / paint:** RC Blimp 5 m — Tiburón Blanco. **Environment:** `day_calm`.

**Preparation:** Home RC blimp, Tiburón Blanco; use its own launch menu and settle before the take. **At the edit’s start:** Blimp already moving slowly west of center; whole envelope and gondola visible.

**Blocking (NED):** 0s: (30, -6, -6) → 4s: (30, 6, -6) 3 m/s is a proposed composition pace; obtain actual trim/motion through normal airship controls.

**Camera:** fixed_tracking, NED, FOV 45°. 0s: (16, 0, -1.7) Fixed eye; pan/tilt to actual aircraft CG. Keep world horizon upright.

**Action:**

- Preroll until yaw and pitch settle.
- Translate gently right without pitching the nose out of frame.
- Birds are welcome only if they do not obscure the blimp.

**Exit / cut:** The gondola remains visible through the final frame. Let quieter prop sound breathe, then cut to the gate-course geometry.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Implementation:** `adapter_needed` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-06 — ION R5 · 00:18:00–00:19:30 · G

**Cast / paint:** ION R5 — Factory ION R5; no stock paint selector. **Environment:** `day_calm`.

**Preparation:** Home ION R5, pad, practice oval; use actual course/race controls. **At the edit’s start:** Pad N28 E38, Angle mode, ready for the genuine countdown ending.

**Blocking (NE_surface):** 0s: (28, 38, 0) Ground reference; use the actual supported quad pose, not D=0 as CG.

**Camera:** fixed_tracking, NED, FOV 48°. 0s: (24, 34, -2.2) Overview establishes pad and first gate N35 E43; camera target is that corridor.

**Action:**

- T selects course if needed; G requests race.
- Retain the actual end of countdown, not an edited fake start signal.

**Exit / cut:** First gate and departure direction are understood. Hard cut to rigid FPV from the same course; no synchronized replay claim.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-07 — Rigid FPV · 00:19:30–00:24:00 · G

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

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Correct direction, next-gate order, speed and aperture clearance pass actual race logic. Center height follows sampled terrain; frame panels are physical obstacles.

### R4-08 — Exterior valid gate passage; separate take unless a real continuous switch exists. · 00:24:00–00:26:00 · G

**Cast / paint:** ION R5 — Factory ION R5; no stock paint selector. **Environment:** `day_calm`.

**Preparation:** Separate exterior take on the same practice oval; identify it as edited coverage. **At the edit’s start:** West approach to first gate; do not imply a replay system.

**Blocking (NED):** 0s: (35, 40, -2) → 1s: (35, 43, -2) → 2s: (35, 46, -2) Same terrain-relative center correction as R4-07.

**Camera:** fixed_tracking, NED, FOV 42°. 0s: (30, 43, -1.1) Frame gate and at least one model length before/after; follow actual quad.

**Action:**

- Record a real correctly directed pass.
- Let the quad exit the opening before the cut.

**Exit / cut:** Gate and vehicle are visibly separated after clearance. Match quad position into the Angle demonstration.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Implementation:** `adapter_needed` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-09 — Angle mode · 00:26:00–00:28:30 · G

**Cast / paint:** ION R5 — Factory ION R5; no stock paint selector. **Environment:** `day_calm`.

**Preparation:** Separate clear part of course; Angle mode read back on actual OSD. **At the edit’s start:** At least 5 m above sampled ground, clear of gates; neutral roll.

**Blocking (NED):** 0s: (43, 48, -5) → 2.5s: (43, 58, -5) Loose demonstration corridor. Hold altitude through ordinary throttle; points are not a commanded motion path.

**Camera:** native_rigid_fpv, FRU, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Native FPV shows the horizon and genuine Angle indicator.

**Action:**

- 0–0.8 s: a modest roll input, starting rehearsal around +0.25.
- 0.8–2.5 s: release roll and retain the actual assisted response.

**Exit / cut:** Horizon/response and mode label read together. Cut on a similar horizon to Acro.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-10 — Acro mode · 00:28:30–00:31:00 · G

**Cast / paint:** ION R5 — Factory ION R5; no stock paint selector. **Environment:** `day_calm`.

**Preparation:** Separate pass; set Acro and verify OSD. Increase clearance before entering clip. **At the edit’s start:** About 8 m above ground in clear air; no gate immediately ahead.

**Blocking (NED):** 0s: (43, 58, -8) → 2.5s: (43, 68, -8) Entry/exit volume only; roll changes the actual path.

**Camera:** native_rigid_fpv, FRU, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Preserve native horizon motion; no counterrotation in post.

**Action:**

- Use a real roll input and neutralize before the next action.
- Accept only a complete readable maneuver; if it needs more time, retime explicitly.

**Exit / cut:** Control recovery visible and Acro indication readable. Cut to a clearly separate low-height tip-over attempt.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-11 — Separate graded-impact attempt · 00:31:00–00:33:00 · G

**Cast / paint:** ION R5 — Factory ION R5; no stock paint selector. **Environment:** `day_calm`.

**Preparation:** Isolated recovery attempt near the pad; same quad, battery and damage state across 11–13. **At the edit’s start:** Use open ground around N28 E33; reset is forbidden inside this recovery chain.

**Blocking (NE_surface):** 0s: (28, 33, 0) Plan-view recovery patch; actual contact/CG and final offset are recorded, not assigned.

**Camera:** fixed_tracking, NED, FOV 38°. 0s: (24, 33, -0.55) Close low eye; quad must not be hidden by a gate, grass or its own overlay.

**Action:**

- Preroll: approach an empty patch at low height; use a real survivable contact.
- Retain approach, contact and tipped resting pose; no person strike.

**Exit / cut:** Tipped pose established. Keep one attempt through the recovery edits.

**Continuity:** Same attempt and location; no restart, terminal-crash revival, depleted-pack revival or invisible repair.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Actual state gates admit each arm/turtle transition. If recovery timing does not fit, obtain a clearer successful attempt or explicitly retime.

### R4-12 — Disarmed turtle selection and real righting action; intervening control-state time may be omitted honestly. · 00:33:00–00:37:00 · G

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

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Actual state gates admit each arm/turtle transition. If recovery timing does not fit, obtain a clearer successful attempt or explicitly retime.

### R4-13 — Normal rearm and successful lift-off from the same recovered quad attempt. · 00:37:00–00:39:00 · G

**Cast / paint:** ION R5 — Factory ION R5; no stock paint selector. **Environment:** `day_calm`.

**Preparation:** Isolated recovery attempt near the pad; same quad, battery and damage state across 11–13. **At the edit’s start:** Use open ground around N28 E33; reset is forbidden inside this recovery chain.

**Blocking (NE_surface):** 0s: (28, 33, 0) Plan-view recovery patch; actual contact/CG and final offset are recorded, not assigned.

**Camera:** fixed_tracking, NED, FOV 38°. 0s: (24, 33, -0.55) Close low eye; quad must not be hidden by a gate, grass or its own overlay.

**Action:**

- Once upright, E disarm and establish low throttle.
- Fresh normal arm, then gentle throttle to lift; retain the same recovered attempt.

**Exit / cut:** Quad clearly airborne again. Match motor/rotor movement into Corsair mechanism detail.

**Continuity:** Same attempt and location; no restart, terminal-crash revival, depleted-pack revival or invisible repair.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Actual state gates admit each arm/turtle transition. If recovery timing does not fit, obtain a clearer successful attempt or explicitly retime.

### R4-14 — Grounded Corsair · 00:39:00–00:42:00 · G

**Cast / paint:** F4U Corsair — Coastal Three Tone. **Environment:** `ground_breeze`.

**Preparation:** Home Corsair, Coastal Three Tone, runway; verify support and stable idle at the west threshold. **At the edit’s start:** N15 E−47, heading east; ground solver owns supported CG/attitude. Wheels stay down.

**Blocking (NE_surface):** 0s: (15, -47, 0) Ground reference, never an instruction to put CG at D=0.

**Camera:** subject_relative, FRU, FOV 38°. 0s: (2.5, -4, 1.3) Camera offsets in horizontal forward/right/up from the actual aircraft CG; target the named mechanism, with fixed structure visible. Rehearse near-plane/mesh clearance.

**Action:**

- Before edit: stationary Corsair, idle throttle, fold completely, then request spread with O.
- Use only the final three seconds of the native eight-second estimated spread, ending fully locked.

**Exit / cut:** Mechanism motion and its settled end are readable. Hard detail cut; keep ground position, skin and light constant.

**Continuity:** Coastal Three Tone throughout. Same heading/support; no running takeoff during ground checks. Gear remains down; no unshown fold-state jump.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Fold: weight on wheels, speed below 0.5 m/s, idle until spread/locked. Native travel is recorded without time compression; excerpts are acknowledged.

### R4-15 — Corsair · 00:42:00–00:44:00 · G

**Cast / paint:** F4U Corsair — Coastal Three Tone. **Environment:** `ground_breeze`.

**Preparation:** Home Corsair, Coastal Three Tone, runway; verify support and stable idle at the west threshold. **At the edit’s start:** N15 E−47, heading east; ground solver owns supported CG/attitude. Wheels stay down.

**Blocking (NE_surface):** 0s: (15, -47, 0) Ground reference, never an instruction to put CG at D=0.

**Camera:** subject_relative, FRU, FOV 38°. 0s: (0.2, -4.5, 2) Camera offsets in horizontal forward/right/up from the actual aircraft CG; target the named mechanism, with fixed structure visible. Rehearse near-plane/mesh clearance.

**Action:**

- Wings spread/locked; frame both wing trailing edges.
- 0–0.7 s neutral, 0.7–1.3 s modest right roll, then neutral and hold; show opposite aileron movement.

**Exit / cut:** Mechanism motion and its settled end are readable. Hard detail cut; keep ground position, skin and light constant.

**Continuity:** Coastal Three Tone throughout. Same heading/support; no running takeoff during ground checks. Gear remains down; no unshown fold-state jump.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Fold: weight on wheels, speed below 0.5 m/s, idle until spread/locked. Native travel is recorded without time compression; excerpts are acknowledged.

### R4-16 — Corsair · 00:44:00–00:45:30 · G

**Cast / paint:** F4U Corsair — Coastal Three Tone. **Environment:** `ground_breeze`.

**Preparation:** Home Corsair, Coastal Three Tone, runway; verify support and stable idle at the west threshold. **At the edit’s start:** N15 E−47, heading east; ground solver owns supported CG/attitude. Wheels stay down.

**Blocking (NE_surface):** 0s: (15, -47, 0) Ground reference, never an instruction to put CG at D=0.

**Camera:** subject_relative, FRU, FOV 35°. 0s: (-2.5, -2, 0.9) Camera offsets in horizontal forward/right/up from the actual aircraft CG; target the named mechanism, with fixed structure visible. Rehearse near-plane/mesh clearance.

**Action:**

- Hold the fixed tailplane against the moving elevator.
- Pitch back for a short visible deflection, release, finish neutral.

**Exit / cut:** Mechanism motion and its settled end are readable. Hard detail cut; keep ground position, skin and light constant.

**Continuity:** Coastal Three Tone throughout. Same heading/support; no running takeoff during ground checks. Gear remains down; no unshown fold-state jump.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Fold: weight on wheels, speed below 0.5 m/s, idle until spread/locked. Native travel is recorded without time compression; excerpts are acknowledged.

### R4-17 — Corsair · 00:45:30–00:47:00 · G

**Cast / paint:** F4U Corsair — Coastal Three Tone. **Environment:** `ground_breeze`.

**Preparation:** Home Corsair, Coastal Three Tone, runway; verify support and stable idle at the west threshold. **At the edit’s start:** N15 E−47, heading east; ground solver owns supported CG/attitude. Wheels stay down.

**Blocking (NE_surface):** 0s: (15, -47, 0) Ground reference, never an instruction to put CG at D=0.

**Camera:** subject_relative, FRU, FOV 35°. 0s: (-2.8, -1.8, 1) Camera offsets in horizontal forward/right/up from the actual aircraft CG; target the named mechanism, with fixed structure visible. Rehearse near-plane/mesh clearance.

**Action:**

- Reframe rear-oblique so rudder is separated from fin.
- A/D yaw deflection then center; keep fuselage stationary.

**Exit / cut:** Mechanism motion and its settled end are readable. Hard detail cut; keep ground position, skin and light constant.

**Continuity:** Coastal Three Tone throughout. Same heading/support; no running takeoff during ground checks. Gear remains down; no unshown fold-state jump.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Fold: weight on wheels, speed below 0.5 m/s, idle until spread/locked. Native travel is recorded without time compression; excerpts are acknowledged.

### R4-18 — Corsair · 00:47:00–00:49:00 · G

**Cast / paint:** F4U Corsair — Coastal Three Tone. **Environment:** `ground_breeze`.

**Preparation:** Home Corsair, Coastal Three Tone, runway; verify support and stable idle at the west threshold. **At the edit’s start:** N15 E−47, heading east; ground solver owns supported CG/attitude. Wheels stay down.

**Blocking (NE_surface):** 0s: (15, -47, 0) Ground reference, never an instruction to put CG at D=0.

**Camera:** subject_relative, FRU, FOV 35°. 0s: (-0.2, -2.6, 0.55) Camera offsets in horizontal forward/right/up from the actual aircraft CG; target the named mechanism, with fixed structure visible. Rehearse near-plane/mesh clearance.

**Action:**

- Reset flap state before the take.
- Request actual full detent with F; record the complete 2.5 s cycle and retain a two-second excerpt ending settled.

**Exit / cut:** Mechanism motion and its settled end are readable. Hard detail cut; keep ground position, skin and light constant.

**Continuity:** Coastal Three Tone throughout. Same heading/support; no running takeoff during ground checks. Gear remains down; no unshown fold-state jump.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Fold: weight on wheels, speed below 0.5 m/s, idle until spread/locked. Native travel is recorded without time compression; excerpts are acknowledged.

### R4-19 — Corsair · 00:49:00–00:51:00 · G

**Cast / paint:** F4U Corsair — Coastal Three Tone. **Environment:** `ground_breeze`.

**Preparation:** Home Corsair, Coastal Three Tone, runway; verify support and stable idle at the west threshold. **At the edit’s start:** N15 E−47, heading east; ground solver owns supported CG/attitude. Wheels stay down.

**Blocking (NE_surface):** 0s: (15, -47, 0) Ground reference, never an instruction to put CG at D=0.

**Camera:** subject_relative, FRU, FOV 35°. 0s: (1, -1.7, 0.85) Camera offsets in horizontal forward/right/up from the actual aircraft CG; target the named mechanism, with fixed structure visible. Rehearse near-plane/mesh clearance.

**Action:**

- Frame canopy against fixed cockpit rim; no animated stick/pedals implied.
- U opens canopy; record complete 2.5 s travel and select a two-second excerpt plus settled end.

**Exit / cut:** Mechanism motion and its settled end are readable. Match canopy movement into the stationary rotor-head inspection.

**Continuity:** Coastal Three Tone throughout. Same heading/support; no running takeoff during ground checks. Gear remains down; no unshown fold-state jump.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Fold: weight on wheels, speed below 0.5 m/s, idle until spread/locked. Native travel is recorded without time compression; excerpts are acknowledged.

### R4-20 — HX-700 mechanical inspector · 00:51:00–00:55:00 · P

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

**Implementation:** `inspector_adjustment` — `app/tools/inspect_hx700.gd`. Existing capture_hx700_mechanism.gd includes 12 rpm and cyclic motion; that old schedule is not this stopped-rotor take.

**Accept only when:** Native inspection/presentation motion and its disclosure are readable; no flight session is implied. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-21 — Clearly separate playable X-Cell .60 · 00:55:00–00:59:00 · G

**Cast / paint:** X-Cell .60 research helicopter — Blanco Ártico. **Environment:** `day_calm`.

**Preparation:** Home X-Cell .60, Blanco Ártico, native pad N6 E0. Preroll: center cyclic/yaw, B arm, H release hold; wait for GOVERNED, lift and stabilize before the edit. **At the edit’s start:** Already hovering over the pad at target N6 E0 D−2.5, governor stabilized, neutral cyclic/yaw; the four-second shot starts here.

**Blocking (NED):** 0s: (6, 0, -2.5) → 1s: (6, 0, -2.5) → 4s: (6, 6, -2.5) Hover and forward-motion targets; actual initial heading and collective must be rehearsed. Estimated governor ramp is not squeezed into the clip.

**Camera:** fixed_tracking, NED, FOV 38°. 0s: (0, -3, -1.2) Fixed eye; pan/tilt to actual aircraft CG. Keep world horizon upright.

**Action:**

- 0–1 s: stable full helicopter hover.
- 1–4 s: gentle forward cyclic, starting with a modest input, then stabilize; no barrel roll.

**Exit / cut:** Helicopter visibly displaced past the pad landmark. Rotor sound hands over to Mustang prop sound.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Implementation:** `manual_ui` — `Home X-Cell .60 pad start and livery selection; manually staged hover/advance`. capture_vehicles.gd --vehicle=xcell-60-research --heli-shot=flight is an airborne-flight reference only: it hardcodes --start=airborne and has no --livery input. It needs adaptation for the specified pad, skin and governed preroll; no ready automation is claimed.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-22 — P-51 clean external view establishes model, actual livery and direction. · 00:59:00–01:00:00 · G

**Cast / paint:** P-51D Mustang — P-51D Mustang factory. **Environment:** `day_calm`.

**Preparation:** One continuous Mustang factory-paint take; prepare genuine transmitter overlay before recording. **At the edit’s start:** Trimmed eastbound flight at target N20 and D−12; no second shipped Mustang paint exists.

**Blocking (NED):** 0s: (20, -75, -12) → 1s: (20, -50, -12) One-second clean lead plus five-second HUD section from the same six-second take at nominal source start speed 25 m/s.

**Camera:** subject_relative, FRU, FOV 38°. 0s: (-8, -5, 2.4) Track in heading frame. Look target slightly below CG so plane sits clear of bottom HUD; verify actual overlay readback.

**Action:**

- Keep the first second clean; add genuine HUD coverage at the next edit.

**Exit / cut:** Identity established. Continue same take into the HUD shot.

**Continuity:** One real take, factory Mustang, same camera and trim; overlay artwork alone makes no hardware-radio claim.

**Implementation:** `existing_adapter` — `tools/trailer/capture_flight.gd overlay support + live session`. R5 camera/input beat needs a focused director; do not use an invented physical-controller animation.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-23 — P-51 live transmitter input and visible bank in one take; sparse real speed/height/fuel values. · 01:00:00–01:05:00 · G

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

**Implementation:** `existing_adapter` — `tools/trailer/capture_flight.gd overlay support + live session`. R5 camera/input beat needs a focused director; do not use an invented physical-controller animation.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-24 — Separate supported-aircraft failure-practice flight · 01:05:00–01:07:00 · G

**Cast / paint:** Ugly Stick .61 glow — HONEYBEE · 07. **Environment:** `day_calm`.

**Preparation:** Separate ordinary glow Stick / HONEYBEE flight. Enable only eligible engine stop, 100%, Early, then launch anew. **At the edit’s start:** Fly a stable approach rehearsal. Actual failure timing is event-driven; source event and approach must belong to one recorded attempt.

**Blocking (NED):** 0s: (15, -140, -15) → 2s: (15, -112, -14) These are proposed onset/glide/landing framing volumes. They are excerpts separated by omitted flight time, not a forced eight-second continuous trajectory. Ground point is support map only.

**Camera:** fixed_tracking, NED, FOV 32°. 0s: (0, -30, -1.7) Fixed eye; pan/tilt to actual aircraft CG. Keep world horizon upright.

**Action:**

- Retain actual power-loss alert and real propulsion change.
- Do not schedule a fake stop at the desired point.

**Exit / cut:** Failure identified. Cut forward in the same attempt; retain FAILURE PRACTICE · ENGINE OUT.

**Continuity:** Same recorded practice attempt across 24–26, same HONEYBEE paint and wind. Failure is configured, not caused by later storm or a fabricated empty fuel gauge.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Generic capture_flight.gd hard-codes failures=0: do not use it unchanged for this scene. Use ordinary production failure settings or a later reviewed adapter.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-25 — Same attempt · 01:07:00–01:10:00 · G

**Cast / paint:** Ugly Stick .61 glow — HONEYBEE · 07. **Environment:** `day_calm`.

**Preparation:** Separate ordinary glow Stick / HONEYBEE flight. Enable only eligible engine stop, 100%, Early, then launch anew. **At the edit’s start:** Fly a stable approach rehearsal. Actual failure timing is event-driven; source event and approach must belong to one recorded attempt.

**Blocking (NED):** 0s: (15, -94, -6) → 3s: (15, -58, -2.4) These are proposed onset/glide/landing framing volumes. They are excerpts separated by omitted flight time, not a forced eight-second continuous trajectory. Ground point is support map only.

**Camera:** fixed_tracking, NED, FOV 32°. 0s: (0, -30, -1.7) Fixed eye; pan/tilt to actual aircraft CG. Keep world horizon upright.

**Action:**

- Select a readable controlled glide excerpt from the same incident.
- Maintain actual speed/altitude evidence.

**Exit / cut:** Glide remains controlled. Cut forward in the same attempt; retain FAILURE PRACTICE · ENGINE OUT.

**Continuity:** Same recorded practice attempt across 24–26, same HONEYBEE paint and wind. Failure is configured, not caused by later storm or a fabricated empty fuel gauge.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Generic capture_flight.gd hard-codes failures=0: do not use it unchanged for this scene. Use ordinary production failure settings or a later reviewed adapter.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-26 — Same attempt · 01:10:00–01:13:00 · G

**Cast / paint:** Ugly Stick .61 glow — HONEYBEE · 07. **Environment:** `day_calm`.

**Preparation:** Separate ordinary glow Stick / HONEYBEE flight. Enable only eligible engine stop, 100%, Early, then launch anew. **At the edit’s start:** Fly a stable approach rehearsal. Actual failure timing is event-driven; source event and approach must belong to one recorded attempt.

**Blocking (NE_surface):** 0s: (15, -47, 0) → 3s: (15, -15, 0) These are proposed onset/glide/landing framing volumes. They are excerpts separated by omitted flight time, not a forced eight-second continuous trajectory. Ground point is support map only.

**Camera:** fixed_tracking, NED, FOV 32°. 0s: (0, -30, -1.7) Fixed eye; pan/tilt to actual aircraft CG. Keep world horizon upright.

**Action:**

- Select flare, supported touchdown and roll-out from the same attempt.
- No reset or different successful landing substituted.

**Exit / cut:** Controlled touchdown visibly completed. Resolve landing, then open up to AI circuit traffic.

**Continuity:** Same recorded practice attempt across 24–26, same HONEYBEE paint and wind. Failure is configured, not caused by later storm or a fabricated empty fuel gauge.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Generic capture_flight.gd hard-codes failures=0: do not use it unchanged for this scene. Use ordinary production failure settings or a later reviewed adapter.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-27 — Calm Club-field flight with actual AI Ugly Stik circuit companions; no close-formation promise. · 01:13:00–01:17:00 · G

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

**Implementation:** `existing_adapter` — `capture_flight.gd normal lighting route + accepted companions`. Companion qualification depends on the exact source/build; current branch must pass its ordinary admission. Do not use Workshop lighting route or re-pin acceptance.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-28 — Eligible airplane in an exact calibrated Phoenix panorama; fixed pilot-eye view and experimental-runway label. · 01:17:00–01:21:00 · G

**Cast / paint:** Ugly Stick .61 glow — HONEYBEE · 07. **Environment:** `phoenix_airfield`.

**Preparation:** Import/select exact calibrated Airfield panorama; confirm matching hash and experimental runway admission. **At the edit’s start:** Photo-eye remains at N0 E0, eye height 1.7 m in this separate field coordinate system.

**Blocking (NED):** 0s: (12, -29, -4) → 4s: (12, 31, -4) This field runway is centered N12 E1, length 42 m, width 9 m. Corridor extends beyond runway ends in the image; actual collision/imagery fit must pass.

**Camera:** fixed_tracking, NED, FOV 40°. 0s: (0, 0, -1.7) Keep the calibrated photo eye fixed; pan direction only. No translated orbit or parallax claim.

**Action:**

- Launch supported runway aircraft through the real imported-site flow.
- Retain four seconds of a readable pass and IMPORTED SCENERY · EXPERIMENTAL RUNWAY.

**Exit / cut:** Aircraft remains identifiable against panorama. Hard cut to separately configured storm flight.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Calibrated source entry exists; installed local panorama and usable source images are not supplied by this plan.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-29 — Separate ordinary airplane flight against an actual storm cloud flash; bolt only if recorded. · 01:21:00–01:25:00 · G

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

**Implementation:** `existing_adapter` — `capture_flight.gd --shot=storm`. Existing adapter uses the real sky preset; specific framing and event interval require rehearsal.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-30 — Extra 300S · 01:25:00–01:29:00 · G

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

**Implementation:** `existing_adapter` — `capture_flight.gd + stock smoke / existing Extra director`. Select and verify an existing supported show-smoke color; no custom color/paint is claimed from its name alone.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-31 — Turbo Lumber · 01:29:00–01:33:00 · G

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

**Implementation:** `existing_adapter` — `capture_flight.gd + Lumber lighting/director route`. Existing dusk director supplies a useful camera; exact night preset and body exposure still require footage.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-32 — Bisonte Physics Lab comparison · 01:33:00–01:35:45 · G

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

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-33 — Actual paused lab setting/application excerpt; setup/reset time is omitted between the two runs. · 01:35:45–01:37:15 · U

**Cast / paint:** MT8 Bisonte — Amarillo Rayo. **Environment:** `day_calm`.

**Preparation:** Pause the actual Bisonte Lab flow between the two comparison runs. **At the edit’s start:** Damping slider reads 1.00; all other experiment controls unchanged.

**Blocking (none):** Native UI/preset or actual camera readback; no invented world coordinates.

**Camera:** actual_UI, none, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Crop only enough to keep Damping and apply action legible.

**Action:**

- Select Damping (damper_scale) 1.50, within source range 0.25–2.00.
- Show actual apply/preparation excerpt; omit waiting/reset time openly.

**Exit / cut:** Applied experiment is read back as damping 1.50. Cut to separately prepared changed-setting run.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Source apply prepares/restarts the session; there is no live in-air parameter change.

**Accept only when:** Genuine UI state, selected values and completed loading are readable; no advancing flight tick is required. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-34 — Second real Bisonte run · 01:37:15–01:40:00 · G

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

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-35 — Baseline .61 glow Ugly Stick · 01:40:00–01:41:30 · U

**Cast / paint:** Ugly Stick .61 glow — HONEYBEE · 07. **Environment:** `day_calm`.

**Preparation:** Open Workshop for baseline glow Stick / HONEYBEE. **At the edit’s start:** Show actual scale selector; prepare distinct 500% and 10% trials.

**Blocking (none):** Native UI/preset or actual camera readback; no invented world coordinates.

**Camera:** actual_UI, none, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Keep scale control and aircraft identity readable.

**Action:**

- Show the real scale control and value change.
- Setup time and separate trial preparation are omitted by the edit.

**Exit / cut:** Actual 500% choice visible before giant flight. Cut to real giant trial.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Genuine UI state, selected values and completed loading are readable; no advancing flight tick is required. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-36 — Actual 500% baseline Stick trial by a fixed landmark. · 01:41:30–01:43:15 · G

**Cast / paint:** Ugly Stick .61 glow — HONEYBEE · 07. **Environment:** `day_calm`.

**Preparation:** Freeze actual 500% Workshop trial; preserve HONEYBEE presentation. **At the edit’s start:** Airborne giant trial before the cut; retain field/runway as familiar scale context.

**Blocking (NED):** 0s: (30, -30, -8) → 1.75s: (30, 30, -8) Large-model corridor is a rehearsal target. Actual scaled trim/speed must be read from the trial; no original-size speed is imposed.

**Camera:** fixed_tracking, NED, FOV 40°. 0s: (12, 0, -1.4) Wide framing fits 7.62 m approximate span and runway context; not the tiny take camera.

**Action:**

- Record actual 500% flight behavior at native speed.
- Keep GIANT · 500% / approx. 7.62 m readable.

**Exit / cut:** Whole giant model remains visible. Cut to tighter real tiny trial, retaining explicit size label.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Implementation:** `existing_adapter` — `capture_flight.gd --workshop-scale=5 + validated lighting preset`. Real trial and cinematic trio are separate sources; framing changes are explicit.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-37 — Actual 10% baseline Stick trial in a deliberately closer readable view, with explicit size label and field context. · 01:43:15–01:45:00 · G

**Cast / paint:** Ugly Stick .61 glow — HONEYBEE · 07. **Environment:** `day_calm`.

**Preparation:** Freeze actual 10% Workshop trial from same baseline and paint. **At the edit’s start:** Tiny trial passes near a recognizable ordinary field marker; verify body is findable.

**Blocking (NED):** 0s: (30, -4, -1.5) → 1.75s: (30, 4, -1.5) Eight-metre proposed corridor; actual scaled speed and safe clearance need trial evidence.

**Camera:** fixed_tracking, NED, FOV 30°. 0s: (27, 0, -0.9) Closer optical view makes the 15 cm approximate span readable. Different framing is intentional; no equal-camera size inference.

**Action:**

- Record the real 10% trial without speed-up.
- Keep TINY · 10% / approx. 15 cm on screen.

**Exit / cut:** Tiny aircraft can be recognized in full-motion playback. Cut to the disclosed same-depth comparator.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Implementation:** `existing_adapter` — `capture_flight.gd --workshop-scale=0.1 + validated lighting preset`. Size comparison is established by values, field context and the next same-depth presentation, not matched framing of these two trials.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-38 — Same-depth 500/100/10% cinematic comparator; correct span labels and disclosure. · 01:45:00–01:49:00 · P

**Cast / paint:** Ugly Stick .61 glow — HONEYBEE · 07. **Environment:** `editorial`.

**Preparation:** Use existing three-size presentation scene; all three represent the same glow Stick baseline. **At the edit’s start:** Giant / Original / Tiny at one depth, with labels 7.62 m / 1.52 m / 15 cm.

**Blocking (model_local):** 0s: (0, 0, 0) Formation origin only. Existing --sizes layout owns separation; log actual model/paint identity before acceptance.

**Camera:** existing_sizes_director, FRU, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Use the existing same-depth layout and move toward original/tiny; actual camera sample/trim remains to be selected.

**Action:**

- Hold enough of all three to read the ratio before moving closer.
- Keep CINEMATIC SIZE COMPARISON throughout.

**Exit / cut:** All three sizes and disclosure have been readable. Match central aircraft into Corsair hero orbit.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Implementation:** `existing_adapter` — `tools/trailer/capture_formation.gd --sizes`. Existing comparator skin must be verified/adapted to HONEYBEE or explicitly recorded as factory; plan does not apply a new paint to this adapter.

**Accept only when:** Native inspection/presentation motion and its disclosure are readable; no flight session is implied. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-39 — Continuous eased Corsair orbit with all 13 stock liveries; final scheme holds. · 01:49:00–01:59:00 · P

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

**Implementation:** `existing_adapter` — `tools/trailer/capture_flight.gd --shot=corsair-orbit + flight_director.gd`. Exact new entry coordinates need a reviewed pre-start fixture; existing orbit flight and camera already exist. Hold-last is implemented/tested, footage timing remains unqualified.

**Accept only when:** Real session ticks advance; no pause/reset hidden inside a continuous action. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-40 — Six uninterrupted seconds of Corsair shoreline approach, water crossing and exit, holding Coastal Three Tone and actual matching reflection if qualified. · 01:59:00–02:05:00 · G

**Cast / paint:** F4U Corsair — Coastal Three Tone. **Environment:** `golden_calm`.

**Preparation:** Separate real Corsair pass, Coastal Three Tone, same golden-hour exposure and clean flight configuration. **At the edit’s start:** Rehearsal entry mark N128 E55 D−2.55, heading east. Preroll target N128 E9 at the same height, nominally two seconds earlier.

**Blocking (NED):** 0s: (128, 55, -2.55) → 3s: (128, 124, -2.55) → 6s: (128, 193, -2.55) 138 m straight reference corridor at 23 m/s configured start speed. D−2.55 is 3 m above mean water D+0.45, not 3 m above lakebed. Actual flight/terrain clearance remains unverified.

**Camera:** fixed_tracking, NED, FOV 42°. 0s: (145, 125, -1) North-bank fixed eye, 1 m above the reference datum, tracking south. Eastbound subject reads right-to-left. Keep shore, plane and real reflection together; camera clearance must be checked.

**Action:**

- 0–about 1.47 s nominal: land/shore approach into the lake composition.
- About 1.47–4.69 s nominal: cross water between E≈88.73 and E≈162.91.
- Last ~1.31 s nominal: exit across the far shoreline while camera continues its pan.

**Exit / cut:** Aircraft clears water and shoreline with the final skin unchanged. Cut after the pass resolves to genuine Creator interface; no added slogan over the lake.

**Continuity:** Coastal Three Tone, closed canopy, spread wings, clean gear/flaps/hook. Match dominant nose orientation and color; this is an edited transition from orbit, not proof of a continuous world trajectory.

**Implementation:** `adapter_needed` — `manual rehearsal / existing production session`. Current capture_flight.gd has no arbitrary lake spawn flag. Use a real flown approach or a later reviewed pre-tree external fixture; never mutate live pose per frame.

**Accept only when:** Nominal geometry gives only ~3.23 s above water, not six; actual speed/path govern footage. Check actual CG, wingtip and prop clearance against water/shore/objects. Reflection must be from the same real frame and paint; keep an honest unmirrored take if it fails.

### R4-41 — Genuine Creator import/source-selection excerpt; edited introduction to both source families. · 02:05:00–02:07:00 · U

**Cast / paint:** Brand/end card — Not applicable. **Environment:** `creator`.

**Preparation:** Open Aircraft Creator through the real menu; prepare permitted local Phoenix/ClearView sources. **At the edit’s start:** Readable genuine import/source controls; EXPAND YOUR HANGAR title in a clear area.

**Blocking (none):** Native UI/preset or actual camera readback; no invented world coordinates.

**Camera:** actual_UI, none, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Use actual preview/interface crop; title does not hide selected source type.

**Action:**

- Show the real source/import workflow for two seconds.
- Conversion and file-selection waiting are omitted by the edit.

**Exit / cut:** Viewer understands that this is an import feature. Cut to Easystar preview on the first strong editorial accent.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Genuine UI state, selected values and completed loading are readable; no advancing flight tick is required. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

### R4-42a…r — the eighteen-model reveal · 02:07:00–02:17:00 · U

Use the genuine Creator preview and admitted original source textures. Prepare every model completely before the selected frames. Target a stable nose-right three-quarter view, approximately 25° from front and 15° above, with about 70% width occupancy. These are composition targets; capture and record the actual native preview camera rather than assuming numeric UI controls. Normalize screen occupancy, preserve native proportions, and keep one stable exposure/background.

The Phoenix block lasts five seconds, then ClearView five. Each begins with a 60-frame leader and continues with eight 30-frame cuts. A persistent source label replaces flickering model names. Conversion waiting is omitted; the edit does not suggest a bulk importer or instantaneous processing.

| ID | Candidate | Source | Master interval |
| --- | --- | --- | --- |
| R4-42a | Easystar | Phoenix RC | 02:07:00–02:08:00 |
| R4-42b | J3 Piper Cub | Phoenix RC | 02:08:00–02:08:30 |
| R4-42c | Fokker DR-1 | Phoenix RC | 02:08:30–02:09:00 |
| R4-42d | Radian | Phoenix RC | 02:09:00–02:09:30 |
| R4-42e | Spitfire | Phoenix RC | 02:09:30–02:10:00 |
| R4-42f | Beaver Float-plane | Phoenix RC | 02:10:00–02:10:30 |
| R4-42g | Tiger Moth | Phoenix RC | 02:10:30–02:11:00 |
| R4-42h | Extra | Phoenix RC | 02:11:00–02:11:30 |
| R4-42i | P-51 Mustang | Phoenix RC | 02:11:30–02:12:00 |
| R4-42j | F-117 | ClearView | 02:12:00–02:13:00 |
| R4-42k | BD-5J | ClearView | 02:13:00–02:13:30 |
| R4-42l | B-25 | ClearView | 02:13:30–02:14:00 |
| R4-42m | C-130 | ClearView | 02:14:00–02:14:30 |
| R4-42n | Beluga | ClearView | 02:14:30–02:15:00 |
| R4-42o | A6-Zero | ClearView | 02:15:00–02:15:30 |
| R4-42p | Agri Duck Duster | ClearView | 02:15:30–02:16:00 |
| R4-42q | MC Tiburon-bipe-7-2 | ClearView | 02:16:00–02:16:30 |
| R4-42r | MC 3D Hobby Shops Extra 330 Red | ClearView | 02:16:30–02:17:00 |

The final Extra 330 Red preview must match the exact draft/model/texture identity of R4-43. If another candidate qualifies, reorder both records together. Source locators, count conditions and preview-only fallback remain in the [import showcase](import-showcase.md).

### R4-43 — Same final previewed model in its genuine eligible Creator trial; experimental/estimated or donor qualification. · 02:17:00–02:20:00 · G

**Cast / paint:** MC 3D Hobby Shops Extra 330 Red — Original admitted source textures; source hash and exact texture identity pending.. **Environment:** `day_calm`.

**Preparation:** Use the exact last-previewed Extra 330 Red Creator draft. Complete eligible estimated/donor setup and its actual trial gates. **At the edit’s start:** Same model/source textures. Retain the real trial qualification; aircraft has stabilized before the three-second selection.

**Blocking (NED):** 0s: (25, -20, -10) → 3s: (25, 20, -10) Provisional framing corridor only. Actual scaled dimensions, donor/derived trim, speed and spawn are unknown until this exact draft qualifies.

**Camera:** subject_relative, FRU, FOV 40°. 0s: (-7, -4, 2) Scale camera distance to actual imported bounds after admission; no numeric lens/size guarantee before the model is loaded.

**Action:**

- Show real eligible flight, with EXPERIMENTAL TEST FLIGHT and actual estimated/donor qualification.
- Keep same source model/paint from final preview.

**Exit / cut:** Three seconds of readable controlled flight. Cut from model expansion to Bisonte shoreline action.

**Continuity:** R4-42r and R4-43 use the exact same draft/model-root/texture hashes. If another model qualifies, reorder the last preview and plan together.

**Implementation:** `manual_ui` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Visual conversion alone is insufficient; trial admission and flight must be demonstrated. If no candidate qualifies, change ending to clearly labelled preview-only and remove flight promise.

### R4-44 — Bisonte at the shallow shore · 02:20:00–02:25:00 · G

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

**Implementation:** `adapter_needed` — `manual rehearsal / existing production session`. Use existing session inputs; numeric blocking is proposed, not applied or flown.

**Accept only when:** Source spawn checks entry sample only; this full driving route still needs runtime qualification. N137 may be materially deeper; reject overshoot, deep water and unobserved effect claims.

### R4-45 — Stable OPEN RC SIMULATOR / PLAY FREE / verified official URL / verified actual product status. · 02:25:00–02:30:00 · E

**Cast / paint:** Brand/end card — Not applicable. **Environment:** `editorial`.

**Preparation:** Use official brand assets, verified destination and accurate promoted-build status. **At the edit’s start:** Full card already settled at start of five-second hold.

**Blocking (none):** Native UI/preset or actual camera readback; no invented world coordinates.

**Camera:** end_card, none, native preset/readback. Native UI/preset or actual camera readback; no invented world coordinates. Logo / PLAY FREE / full official destination; readable safe areas.

**Action:**

- Hold five full seconds; no extra model flicker or additional feature list.
- Resolve score and fade real final sound.

**Exit / cut:** Destination and call to action have been readable. End cleanly.

**Continuity:** Preserve cast identity, chosen paint, time, scale and source take; record actual setup/readback.

**Implementation:** `editorial` — `existing assemble.py / title tools`. No export or soundtrack selection in this pass.

**Accept only when:** Editorial card duration, readable destination and accurate product status are checked. Actual source frames and visual readability remain to be accepted; spatial clearance applies only to world shots.

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

## From script to implementation

The [trailer tool README](../README.md#r5-shot-plan-and-livery-finish) owns commands for the new validator, per-shot output, coordinate export and map. Its plan checks are executable now. They validate the paper/source contract; passing them does not accept a flight or image.

The existing capture tools already supply real-session pilot commands, camera placement, mesh-only livery changes, recorded per-frame identities, ground-vehicle routes and presentation comparators. Reuse those seams. For R5, qualify one narrow adapter/take at a time:

1. **Ground Corsair details:** production supported runway state; exact skin; named mechanism requests; settled full-speed travel. Start with this controllable setup.
2. **Orbit:** use the 13-asset order and hold-last option; verify all presented identities, exact source clock/frames and final skin. The software schedule test does not replace rendering the actual GLBs.
3. **Lake:** create a reviewed pre-start fixture or fly the approach, sample actual trajectory/clearances, then place the low bank camera. `external_spawn_airborne` is pre-tree/tick-zero setup and measures height above local terrain; it is not a live teleport API. Do not keyframe a G-class aircraft through the listed positions.
4. **Truck and FPV:** rehearse actual outcome first, then trim coverage. Read real support, crash, race/arm/turtle and battery state. Bisonte’s source test does not qualify the nitro truck jump.
5. **Practice/UI/import:** use ordinary failure settings, actual Lab/Workshop/Creator state and same-attempt or same-model evidence. The generic flight-capture harness forces failures off, so it cannot film engine-out practice unchanged. Each imported source and the final trial remains an individual admission.

Keep one owner for a recording session. Give every take its own output directory and record source commit, actual runtime build/backend, resolution, renderer, settings, camera/vehicle identities, advancing ticks, source movie boundaries and selected edit range. Use the existing capture/admission documentation; this pass does not choose a new video-generation or editing platform.

## Coverage, rhythm and honest source classes

The master retains **62 cuts / 9,000 frames / 150 seconds**, planned as **112 G + 15 U + 18 P + 5 E**. The [90-second Field Notes](feature-companion-films.md) and [32-second Preflight Ballet](mechanical-sequences.md#separate-32-second-idea--the-preflight-ballet) retain the detailed opportunities outside the master. The [integration ledger](feature-opportunities.md) remains complete.

The orbit/lake, import chapter, genuine recovery outcome, core fleet and five-second invitation keep their protected screen time. If a real action cannot fit, explicitly transfer a complete eligible standalone feature to Field Notes and retime all authorities; there is no spare reserve. Scale flights now have deliberately different readable framing; the simultaneous same-depth comparator is the labelled presentation evidence for relative size.

The numerical import title remains **EXPAND YOUR HANGAR**. The conditional 300+ variant still requires its own counted compatible-model evidence. No new source model, runtime take, soundtrack or rendered image is claimed from this script/code pass. The [R5 audit](script-audit-r5-2026-11-21.md) records checks, resolved issues and remaining production evidence.
