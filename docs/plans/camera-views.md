# Camera and views plan

**Date:** 2026-10-13. **Status:** proposed; nothing implemented. **Prefix:** CAM-00…CAM-22 (to register; see CAM-00). **Owner:** camera-views track, under the main line's acceptance (Gate 2 readability).
**Would own:** `app/render/camera/`, `app/tests/test_camera_*.gd`, `docs/research/camera-views/`; after CAM-02, `app/render/pilot_camera.gd`.
**Coordinated, not owned:** `app/main.gd` seams (main line); `app/render/crash/director.gd` (crash track); `app/audio/flight_audio.gd` (audio); `app/render/overlays/` (HUD track); `app/ui/`, `app/app_state/preferences.gd`, `app/i18n/es.po` (menu track); `app/data/fields/` and `openrc-field` (field-world/scenery); aircraft camera mounts (aircraft contract and each model team); `app/scenery/runway_scenario.gd` capture views (scenery).
**Builds on:** [research 10: audio, perception and presentation](../research/roadmap-investigations/10-audio-perception-presentation.md) (X-PERC-1…9), [DT-00-R1-05 DPI and readability](../research/desktop-delivery-investigations/DT-00-R1/05-dpi-camera-readability.md), [VISUAL-QUALITY-PLAN](../VISUAL-QUALITY-PLAN.md) VQ-03, [DECISIONS](../../DECISIONS.md) 2026-10-05 "fixed ground pilot camera". External survey: [§10](#10-external-evidence).

## 1. Purpose

Give the pilot more and better ways to see the aircraft without weakening the reason the simulator exists: learning to fly an RC model **from the ground**. The pilot view stays the default and the reference for every readability claim. Every other view is an aid, a training tool or a spectator tool, and must say so.

Success means:

1. The pilot view reads an aircraft's attitude at 100–300 m better than today, measured with the blinded orientation kit, not by opinion.
2. A chase, an onboard/FPV, an orbit and a fly-by view exist, are smooth at 30–144 fps, never jitter against the 240 Hz simulation, never enter the ground and never change a trace.
3. Every view is selectable from keyboard, mouse and (optionally) a transmitter switch, and persists as a preference.
4. Each view has a measured cost on the target machine and an automated capture.

## 2. What exists (2026-10-13)

| Item | Where | Behavior |
| --- | --- | --- |
| Pilot view | [pilot_camera.gd](../../app/render/pilot_camera.gd) `aim()` | Eye at the field's pilot station + `eye_height` 1.7 m; `look_at(airplane)` every frame; vertical FOV 50°, `KEEP_HEIGHT`; near 0.1 m, far 21 km ([spec.gd](../../app/spec.gd) `CAMERA`) |
| Auto-zoom | `PilotCamera.auto_fov()`, `Spec.AUTO_ZOOM` | FOV chosen so the span covers 30 px of the viewport height, clamped 6°…50°; **Z** toggles; instantaneous (no smoothing); `--autozoom=0` |
| Close-up ("inspect") | `aim(inspect=true)`, `Spec.INSPECT_OFFSET` | Camera rigidly fixed to the airplane frame at (−1.2, 0.9, 2.0) m; rolls with it; **C** toggles |
| Landscape review | `PilotCamera.look()`; `--look_az/--look_el/--look_alt` | Fixed direction from above the station, for captures |
| Crash view | [director.gd](../../app/render/crash/director.gd) `aim()` | Overrides the camera after an impact: pilot view keeps FOV ≥ 12° and looks at the impact; close-up jumps to impact + (5, 3.2, 6) m, FOV 58° |
| Capture-only views | [runway_scenario.gd](../../app/scenery/runway_scenario.gd) `_render()` | `chase` (7 m behind on the horizontal heading, 2.2 m up, 45°), `side`, `wide`: a precedent, not a runtime view |
| Frame order | [main.gd](../../app/main.gd) `_process` → `_render_pose()` | Camera aimed from the **interpolated** pose (`sim.interpolated(fraction)`), after the airplane transform: no lag-induced jitter today |

Consumers of the camera that a new view changes:

| Consumer | Reads | Consequence for new views |
| --- | --- | --- |
| [flight_audio.gd](../../app/audio/flight_audio.gd) (priority 100) | `flight._camera.global_position` as the **listener** | Chase/onboard move the ear with the camera; a cut makes propagation delay and Doppler jump (D3) |
| [world.gd](../../app/render/world/world.gd) `ground_share(camera)` | Camera pitch and FOV | Eye adaptation; an onboard view pitching through the horizon pumps exposure |
| [sun_glare.gd](../../app/render/landscape_upgrade/sun_glare.gd) | `get_viewport().get_camera_3d()` | Works for any active camera; PiP viewports need their own decision |
| Overlays wind arrow ([overlay_manager.gd](../../app/render/overlays/overlay_manager.gd)) | Camera forward heading | Correct for any view |
| Overlays FAR warning | `Spec.AUTO_ZOOM`, pilot distance | Must stay pilot-geometry based in every view |
| [visual_evidence.gd](../../app/render/visual_evidence.gd), capture JSON | `_view_name()`, camera transform/FOV | Must record mode and parameters |
| [population.gd](../../app/scenery/population.gd) | `visibility_range_end` 1200 m from the camera | A chase 1 km from the pilot shows/hides people differently than the pilot view |

Gaps: no chase, onboard/FPV, orbit, fly-by, tower or multi-station view; no manual zoom; no camera smoothing or transitions; zoom law fixed at "constant 30 px"; FOV not related to the real display; nothing persisted; crash camera hard-coded; camera logic spread over `pilot_camera.gd`, `main.gd`, `director.gd` and `runway_scenario.gd`.

Facts already established in research 10 that this plan relies on:

- The display, not the eye, limits readability: the Stik at 100 m subtends 52 arcmin but projects 11.8 px at 720p/50°.
- The 50° camera minifies (0.44–0.63× real angular size on common monitors); orthoscopic FOV on a 27″ monitor at 60 cm is ≈ 31°.
- Constant-pixel auto-zoom removes looming between ≈ 39 m and 349 m at 720p, so approach/recede is unreadable from size; partial zoom (size ∝ d<sup>−k</sup>) and "keep ground in view" are the known alternatives.

## 3. Principles

1. **Presentation only.** Cameras read the session and the interpolated render pose; they never write session state, input, random state or traces. Proof per step: `--trace` with every `--view` equals the default trace except creation time.
2. **One pose source.** Every view derives from the same interpolated pose the airplane mesh is drawn with, in the same frame, after `_render_pose`. Never from `sim.state` directly (a 1-tick mismatch is 4.2 ms of motion, i.e. 12.5 cm at 30 m/s: visible shimmer in a chase view).
3. **Frame-rate independent smoothing.** Filters use exact discretizations (exponential `1 − e^(−dt/τ)`, analytic critically damped spring). The same trajectory sampled at 30/60/144 fps yields the same camera pose at matched times within tolerance.
4. **Deterministic captures.** In capture/automation routes the rig advances with the simulation clock, not wall time, and a view can be started "settled" (filters initialized to their steady state).
5. **Pilot view is the reference.** It stays the default for Home and direct routes; changing its law needs owner evidence (Gate 2).
6. **Render types at the boundary.** Camera math lives in `app/render/camera/` and may use `Vector3/Basis` (render space). It never moves into `app/sim/` or `app/physics/`. Scalar inputs from physics (terrain height, proxies) stay float64 until converted.
7. **Small, measured steps.** Each view lands alone, with tests, captures and a frame-time measurement; a view that costs more than its budget or worsens readability is rejected, not tuned forever.

## 4. Architecture

### 4.1 Components (all under `app/render/camera/`)

| File | Kind | Responsibility |
| --- | --- | --- |
| `camera_math.gd` | pure static | Damping, springs, angle/quaternion helpers, projection and FOV conversions, zoom laws, natural FOV |
| `camera_context.gd` | value | Per-frame read-only snapshot: interpolated pose (render), velocity and angular rate (render), pilot station, aircraft extent and mounts, terrain sampler, collision proxy query, viewport size, paused/crash/ground flags, frame `dt`, clock mode |
| `camera_pose.gd` | value | Output of a mode: position, orientation (basis), vertical FOV, near, far, `cut` flag |
| `camera_mode.gd` | base | `enter(ctx, from_pose)`, `update(ctx) -> CameraPose`, `exit()`, `id`, `settings_schema`, `handles_input(event) -> bool` |
| `modes/*.gd` | modes | One file per view (§5) |
| `camera_rig.gd` | Node | Owns the `Camera3D`, the active mode, transitions, input routing, the settings and the crash/replay request API; applies the final pose; exposes `view_id()`, `listener_position()`, `evidence()` |
| `camera_transition.gd` | pure | Blend between two poses (position, slerp, FOV in tan-space) or cut |
| `camera_collision.gd` | pure | Terrain clearance from `GroundTerrain.sample`, proxy clearance from `CollisionWorld.nearby` |
| `lens_distortion.gdshader` | shader | Optional FPV barrel distortion (CAM-12) |

`main.gd` keeps one seam: it builds the rig instead of `PilotCamera.create`, and `_render_pose` calls `rig.update(ctx)` instead of `PilotCamera.aim/look`. `_view_name()` delegates to the rig. Key handling for camera keys moves to `rig.handles_input()`. `PilotCamera`'s static functions stay as compatibility wrappers until every caller (tests, `runway_scenario.gd`, `telemetry.gd`) migrates.

### 4.2 Frame order

```
_physics_process (240 Hz)  → Simulation ticks
_process (main.gd)         → pose = interpolated(fraction) → _render_pose(airplane, shadow)
                           → rig.update(ctx(pose, dt))     → Camera3D transform/FOV
                           → crash director requests (via rig, not direct writes)
_process (priority 100)    → FlightAudio reads rig.listener_position()
```

### 4.3 Coordinates and precision

Render units are metres, Y-up (`frames.gd`). Camera positions stay within the 21 km ground rim, where float32 resolution is ≤ 2 mm: no origin shifting is needed. Near/far are per mode: the onboard view needs a smaller near plane (cockpit/fuselage at 2–10 cm), which costs depth precision on the ground shadow (0.05 m above the grass) in a non-reversed Z buffer. CAM-11 measures it; if z-fighting appears, the onboard view lowers `far` (it never needs 21 km of field detail at full precision) rather than raising the shadow.

### 4.4 Input map (proposal, D2)

| Input | Action | Note |
| --- | --- | --- |
| **C** | Next view in the enabled cycle | Today: pilot ↔ close-up. Crash text "[C] Change view" stays true |
| **Shift+C** | Previous view | |
| **1…7** (top row) | Direct view: 1 pilot, 2 chase, 3 onboard/FPV, 4 fly-by, 5 orbit, 6 field camera, 7 PiP on/off | Number keys are free today |
| **Z** | Pilot: zoom law on/off (today's auto-zoom) | Unchanged meaning |
| **+ / −**, mouse wheel | Zoom (pilot: manual FOV factor; chase/orbit: distance) | `KEY_EQUAL/KEY_MINUS/KEY_KP_ADD/KEY_KP_SUBTRACT` |
| Right mouse drag | Orbit / look around (orbit, chase, onboard head-look) | Never captures the mouse while the pause menu or overlays need it |
| **Backspace** | Reset the current view's offsets | |
| Transmitter switch (optional) | Next view / pilot↔chase | Read from an unmapped aux axis, routed to the rig only (never to commands); D9 |

The keyboard table in [controls_reference.gd](../../app/ui/controls_reference.gd) and [FIRST-LAUNCH](../FIRST-LAUNCH.md) is updated in the same step that changes a key; its consistency test already enumerates every key.

### 4.5 Settings

Additive `[camera]` section in `settings.cfg`, validated per key like `[hud]` (older builds ignore it): `default_view`, `cycle` (enabled views), `fov_mode` (`fixed` / `natural` / `custom`), `fov_deg`, `screen_diag_in`, `view_distance_cm`, `zoom_law` (`off` / `constant` / `partial`), `zoom_k`, `zoom_smoothing_s`, `chase_distance_m`, `chase_height_m`, `chase_style` (`horizon` / `follow3d`), `chase_roll_follow`, `fpv_uptilt_deg`, `fpv_fov_deg`, `fpv_lens` (`rectilinear` / `barrel`), `comfort_reduce_motion`, `audio_listener` (`camera` / `pilot`). Direct (automation) routes ignore preferences and accept `--view=<id>` plus the existing `--autozoom`, `--look_*`, `--inspect` arguments.

## 5. Views

Every view lists its law, defaults (all **estimated** unless a source is given) and its specific risks.

### 5.1 Pilot (V1; refactor of today's view, then improved)

The RC pilot standing at a station, turning the head to keep the airplane centred.

Improvements, each optional and measured:

| Option | Law | Why |
| --- | --- | --- |
| Smoothed FOV | Filter the FOV in `ln(tan(fov/2))` space with τ ≈ 0.25 s; snap on view entry | Removes the jump when **Z** toggles and the "pumping" when distance changes quickly near the clamp |
| Partial zoom (X-PERC-2) | On-screen span `px(d) = max(px_fixed(d), P0·(d0/d)^k)` for d > d0; k = 0 today's constant size, k = 0.5 partial, k = 1 off | Restores the looming cue the constant-size law removes |
| Keep ground in view (KGIV) | Widen the FOV (never past the base) until the horizon row stays inside the frame | Keeps the horizon as an attitude reference when the aircraft is high ([research 10, theory](../research/roadmap-investigations/10-audio-perception-presentation.md#theory-and-models)) |
| Manual zoom | Multiplicative factor on the law's FOV (0.25×…2×) | Pilots asked for it in every sim surveyed |
| Natural FOV (X-PERC-1) | `fov_v = 2·atan(h_screen / (2·v))` from screen diagonal and viewing distance | Orthoscopic: on-screen angular size equals real angular size |
| Framing dead zone (VQ-03) | The aircraft may drift inside a central box (e.g. 10 % of the frame) before the head turns; critically damped | Lets the background slip less and shows direction of travel; reject if it delays tracking |
| Pilot stations | Choose among stations from field data (CAM-15) | Left/right of the runway, upwind/downwind practice |
| Magnifier inset | PiP (§5.7) showing the aircraft at a constant pixel size while the main view keeps natural FOV | Keeps looming and background scale in the main view and attitude in the inset |

Hard constraints: the eye never moves with the aircraft; the look direction is exact (no lag) unless the dead-zone option is on; `--autozoom=0` and today's captures remain reproducible bit-for-bit after the refactor (CAM-02).

### 5.2 Chase (V2)

A camera behind the aircraft, for familiarization, aerobatic learning and filming.

Two styles (D5):

- **Horizon-locked follow** (default). The camera's yaw follows the flight-path heading; its up vector is world up. Position target: `p* = cg − D·ĥ + H·ŷ`, where ĥ is the horizontal unit heading of the velocity above 3 m/s (body heading below, with a 1 m/s blend band; on the ground the body heading). Position follows `p*` with a critically damped spring (ω from τ ≈ 0.35 s); yaw follows with τ ≈ 0.5 s. Aim point: `cg + v·t_la` (look-ahead 0.15 s, clamped to 0.6·D) so the aircraft sits slightly below centre.
- **3D follow** (aerobatic). The camera rides a damped copy of the body attitude: `q_cam = slerp_damped(q_cam, q_body, τ_rot ≈ 0.3 s)`, offset `(−D, H, 0)` in that frame; up vector blended between world up and body up by `roll_follow ∈ [0, 1]` (0.3 default). Loops and rolls then look like an on-rails chase without the nausea of a rigid mount.

Edge cases that must be designed, tested and captured:

| Case | Rule |
| --- | --- |
| Vertical up/down line | ĥ is undefined; hold the last valid heading while the horizontal speed < 20 % of the speed; 3D follow has no singularity |
| Tail slide, hover, knife edge | Use body heading when the velocity is opposite the nose (dot < 0) |
| Ground roll and taxi | Body heading; height clamp ≥ terrain + 0.6 m |
| Terrain | `y_cam ≥ GroundTerrain.sample(cam) + clearance`; move along the boom toward the aircraft, never through the ground |
| Obstacles | Sphere (r = 0.3 m) against `CollisionWorld.nearby` boxes; foliage cards (tree crowns) are ignored, trunks/structures shorten the boom; hysteresis 0.3 s before lengthening again |
| Reset/restart | Snap to the settled pose; no blend from the old position |
| Crash | Freeze position, keep looking at the wreck (§5.9) |
| Large dt (stall, window drag) | Clamp dt to 0.1 s as main does; snap if the target jumped > 50 m |

Defaults: D = 3.5 × span (Stik ≈ 5.3 m), H = 0.35 × D, vertical FOV 55°. FOV may widen with speed by ≤ 5° (off under comfort mode).

### 5.3 Onboard / FPV (V3)

A camera mounted on the airframe, as on a real FPV or "action camera" installation.

- **Mount:** each aircraft declares optional camera mounts (D7): `{id, position (model datum, m), pitch_up_deg, yaw_deg, roll_deg, fov_deg, kind: "fpv" | "wing" | "tail" | "cockpit", source}`. Until an aircraft declares one, a derived default (top of the fuselage, 15 % of the length aft of the spinner, labelled `estimated`) is used and shown as such.
- **Optics:** rectilinear up to ~110° horizontal. Wider FPV lenses use a barrel-distortion post shader over an overscanned render (CAM-12), never a curved projection in the 3D pass.
- **Uptilt:** default 5–10° for airplanes (FPV quads use 20–45° because they fly nose-down; airplanes cruise near level) — confirm against the survey.
- **Head look:** right-drag or a head-tracking source rotates the view relative to the mount, recentred by Backspace.
- **Rigid:** no smoothing (a real camera is bolted on); optional ≤ 2 Hz vibration from rpm is off by default and never shakes in comfort mode.
- **Near plane** 0.03 m; hide the propeller blur disc and spinner only when they occlude more than a threshold (D8).
- **Cockpit** (P-51 scale) needs an interior and a pilot figure that the model teams own; out of scope beyond a canopy-frame view at a declared mount.
- **Analog FPV look** (noise, breakup with distance/obstruction) is a later presentation option, never presented as a radio-link model.

### 5.4 Fly-by / tracking (V4)

A spectator or photographer by the flight path. The camera is placed on the ground (or at altitude) ahead of the aircraft, at `cg + v̂·L + lateral·S` (L ≈ 60 m, S ≈ 15 m at 1.7 m eye height, both scaled by speed), looks at the aircraft with the pilot-view zoom law, and re-places itself after the aircraft passes and is farther than L. Placement rejects points inside obstacles or below terrain and prefers the side opposite the sun (no backlit aircraft). This is the cheapest "cinematic" view and the best aircraft beauty shot; it is not a piloting view.

### 5.5 Orbit / inspect (V5)

Replaces today's rigid close-up. A camera on a sphere around the CG: azimuth/elevation by right-drag, distance by wheel (0.6…20 × span), no roll, world up, look at the CG. The "close-up" preset reproduces today's `INSPECT_OFFSET` framing (left, above, behind) in the airplane's yaw frame so existing inspection captures keep a comparable view. Works paused (the pause-backdrop alternative in [MENU-REDESIGN-PLAN §7](../MENU-REDESIGN-PLAN.md#7-decisions-for-the-owner)).

### 5.6 Field cameras (V6)

Fixed cameras defined by field data: tower, runway threshold, pits, spectator line. Each has position, look mode (`track` the aircraft with the pilot zoom law, or `fixed` direction) and FOV. The same data block declares alternative **pilot stations** used by V1 (D10). Both extend `openrc-field` additively with `{value, unit, kind, source}` quantities and are owned by the field-world/scenery tracks.

### 5.7 Picture-in-picture (V7)

A `SubViewport` sharing the main `World3D`, rendered at a small size (≈ 25 % of the height, 16:9) in a corner, showing a second view: the **magnifier** (aircraft at a constant 120 px span, looking from the pilot's eye with a narrow FOV) or a chase inset. Cost is a second render of the scene; the inset therefore uses lower MSAA, no sun-glare pass and optionally a 30 Hz update. Kept only if its measured cost is within budget on the target GPU (§7) and the orientation kit shows a benefit.

### 5.8 Off-screen indicator

When the aircraft leaves the frame (field cameras, orbit, onboard), an edge arrow points toward it, with distance. Implemented by the overlays track (HUD) from `rig.evidence()` and the aircraft position; this plan only provides the seam.

### 5.9 Crash and replay

The crash director stops writing the camera. It calls `rig.request_focus(point, duration_s, reason)`; each mode answers: pilot keeps the station and widens to FOV ≥ 12° (today's rule); chase freezes position and looks at the wreck; onboard cuts to an orbit around the wreck; orbit retargets. Replay cameras (CR-20…27) use the same rig with a recorded pose stream; their design stays in the crash plan.

### 5.10 Head tracking and VR

Remain spikes X-PERC-8 (OpenTrack UDP → head rotation offset on V1/V3 only) and X-PERC-9 (OpenXR at the pilot station) in research 10. The rig's "head offset" input is designed so either can feed it later without a new seam.

## 6. Cross-cutting rules

| Topic | Rule |
| --- | --- |
| Transitions | Pilot ↔ fly-by/field: blend 0.4 s (position lerp, attitude slerp, FOV in tan-space). Any change into or out of onboard, and any blend whose path would cross terrain/obstacles: cut. Reset and restart: cut |
| Audio listener (D3) | Default: listener follows the camera (what the viewer sees is what they hear). Option: listener stays at the pilot station. On a cut, the rig emits `cut`; FlightAudio calls `soundscape.reset_observer()` so Doppler and delay do not jump |
| Exposure | Onboard and chase use the same `ground_share` input with a 0.5 s low-pass in the rig's context, so a roll through the horizon does not pump exposure; field-world owners review |
| Overlays | Wind arrow uses the active camera heading (unchanged). FAR, LOW and distance values remain pilot-referenced in every view |
| Scenery LOD | Captures from chase/fly-by at 300 m and 800 m from the pilot verify population ranges, grass fade and impostors; any pilot-centred assumption is reported to its owner, not patched here |
| Comfort | `comfort_reduce_motion` = horizon lock, no FOV kick, no vibration, slower transitions. No camera shake anywhere by default (crash plan keeps none) |
| Pause | All views freeze with the simulation except orbit, which may rotate while paused |
| Accessibility | Every view reachable from the keyboard; mouse optional |

## 7. Budgets and evidence

| Measure | Budget | Method |
| --- | --- | --- |
| Rig update (any single view) | ≤ 50 µs mean, ≤ 150 µs p95 per frame on the VM | `Time.get_ticks_usec` around `rig.update`, frametimes logger |
| Chase collision query | ≤ 30 µs mean | Same, with the default scenery on |
| PiP | ≤ 25 % added GPU frame time at 1080p on the target machine | VQ-01b frametimes on/off pairs; VM numbers are not acceptance |
| FPV barrel shader | ≤ 0.5 ms at 1080p on the target machine | Same |
| Jitter | Aircraft screen-position second difference ≤ 0.5 px RMS in a steady 60 m circle, chase view, at 30/60/144 fps | Capture harness with `unproject_position` per frame |
| Frame-rate independence | Pose difference at matched times ≤ 1 cm and ≤ 0.2° between 30 and 144 fps | Headless replay of a recorded trajectory |
| Trace identity | Byte-equal trace except creation time for every `--view` | Existing trace comparison |

Software checks prove behavior and cost on the VM only. Readability and comfort need the owner on the target display (Gate 2, X-PERC-3).

## 8. Steps

| ID | Work | Proof / status |
| --- | --- | --- |
| CAM-00 | Register prefix and paths in the [registry](../README.md#tracks-plans-and-step-ids); owner decisions D1–D10; DECISIONS row; confirm keys | Registry row, DECISIONS row / proposed |
| CAM-01 | `camera_math.gd`: exponential damping, analytic critically damped spring, damped slerp, look basis with zenith handling, FOV conversions (vertical/horizontal/diagonal, focal length), `projected_px`, zoom laws (constant, partial k, KGIV), natural FOV | `test_camera_math.gd`: known values, step responses at 30/60/144 fps equal at matched times, no NaN at vertical look / proposed |
| CAM-02 | `camera_rig.gd`, context, pose, mode base; port pilot, close-up and landscape `look` as modes; `main.gd` seam; `PilotCamera` wrappers kept | Pixel-identical captures vs `main` for pilot (auto-zoom on/off), close-up and three `--look_*` cases; trace identity; `test_pilot_aids` unchanged / proposed |
| CAM-03 | Crash director through `rig.request_focus`; remove its direct camera writes | `test_crash_pose` and crash captures unchanged for pilot and close-up / proposed (crash track reviews) |
| CAM-04 | View selection input (C, Shift+C, 1…7, Backspace), `--view=`; controls reference, FIRST-LAUNCH, es.po | Key consistency test; trace identity per view / proposed |
| CAM-05 | Pilot: smoothed FOV, manual zoom (+/−, wheel) | Step test: Z toggle reaches 95 % in 3τ with no overshoot; capture series / proposed |
| CAM-06 | Pilot: partial zoom law k and KGIV (implements X-PERC-2) | On-screen size ∝ d<sup>−k</sup> within 5 % from 20–300 m; horizon row in frame for KGIV / proposed |
| CAM-07 | Natural FOV from screen size and distance (implements X-PERC-1) | Pure test vs research 10 table; rendered span within ±1 px of prediction / proposed |
| CAM-08 | Chase, horizon-locked style, terrain clearance | Synthetic trajectories (circle, loop, vertical line, tail slide, ground roll, reset): continuity, clearance ≥ 0.6 m, jitter budget; captures / proposed |
| CAM-09 | Chase, 3D follow style, roll-follow, look-ahead, obstacle shortening | Loop and four-point roll captures; boom shortens at the pavilion fixture; frame-rate independence / proposed |
| CAM-10 | Orbit/inspect replacing the rigid close-up; works paused | Close-up preset capture comparable to CAM-02; mouse never steals focus from overlays/pause / proposed |
| CAM-11 | Onboard/FPV with derived default mounts; near/far per mode; depth check on the shadow | Captures for every catalog aircraft; z-fighting check on the ground shadow at 1, 5, 50 m / proposed |
| CAM-12 | FPV lens: overscan + barrel shader option | Distortion matches the chosen model within 1 % radius; cost within budget, or rejected / proposed |
| CAM-13 | Aircraft camera mounts in the contract (optional capability), then per-aircraft data by each model team | Contract tests: invalid mounts refuse; aircraft without mounts fly unchanged / proposed (AS owner) |
| CAM-14 | Fly-by camera | Placement never inside obstacles/terrain over a recorded circuit; sun-side rule test; captures / proposed |
| CAM-15 | Field cameras and alternative pilot stations in `openrc-field` | Field schema test; captures from each camera / proposed (field owners) |
| CAM-16 | Transitions and cut rules; audio listener policy and `cut` → `reset_observer` | Blend continuity test; audio observer reset on cut; owner listens / proposed (audio track) |
| CAM-17 | Settings `[camera]` and dialog (menu track builds the UI) | Round trip and per-key fallback like HUD-06 / proposed |
| CAM-18 | PiP inset: magnifier and chase inset | Cost on/off on the target machine within budget, or rejected / proposed |
| CAM-19 | Off-screen indicator seam (HUD track draws it) | Indicator angle test for points around and behind the camera / proposed |
| CAM-20 | Scenery and LOD survey from far camera positions | Captures at 300/800 m from the pilot; issues filed to owners / proposed |
| CAM-21 | Cost and smoothness on the target machine (30/60/144 Hz) | Frametimes per view; jitter metric; owner notes / proposed |
| CAM-22 | Pilot acceptance: moving-clip orientation kit per view and zoom law (with X-PERC-3); comfort rating per chase style | Error rate and response time per mode; owner −2…+2 ratings / proposed |

Order: CAM-00 → 01 → 02 → 03/04 → 05 → 08 → 10 → 06/07 → 09 → 11 → 16 → 17 → 14 → 13 → 12 → 15 → 18 → 19 → 20 → 21 → 22. The pilot-view improvements (05–07) come before most new views because they serve Gate 2.

## 9. Decisions for the owner

| ID | Question | Recommended default | Alternatives |
| --- | --- | --- | --- |
| D1 | Default view for Home flights | Pilot | Remember last view |
| D2 | Key layout | §4.4 (C cycles, 1…7 direct) | Function keys; C keeps pilot ↔ close-up only |
| D3 | Audio listener | Follows the camera; option for pilot station | Always pilot station (more "RC-true") |
| D4 | Pilot zoom law default | Today's constant 30 px until CAM-22 picks a law | Partial k = 0.5; natural FOV + magnifier |
| D5 | Default chase style | Horizon-locked | 3D follow |
| D6 | Views enabled in the C cycle | Pilot, chase, onboard, orbit | All |
| D7 | Camera mounts in the aircraft contract | Optional capability, derived default labelled `estimated` | Render-side table per aircraft |
| D8 | FPV propeller | Keep the blur disc visible | Hide it in onboard view |
| D9 | Transmitter switch for views | Off by default, assignable in calibration | Not offered |
| D10 | Extra pilot stations | Data-defined per field, chosen in conditions | Free placement by mouse |

## 10. External evidence

To be completed from the survey (see §11).

## 11. Risks

1. **The pilot view is quietly weakened.** Mitigation: CAM-02 pixel identity; any law change waits for CAM-22.
2. **Chase views teach the wrong skill.** RC flying is control-reversal from the ground; a chase hides it. Mitigation: label views as aids; pilot view default; Gate 2 is judged in the pilot view only.
3. **Jitter from mixing tick and frame poses.** Mitigation: one pose source (§3.2) and the jitter metric.
4. **Gimbal problems** at vertical lines and inverted flight. Mitigation: quaternion state for 3D follow, heading hold for horizon style, explicit test cases.
5. **Camera inside terrain or buildings.** Mitigation: clearance and proxies; cut instead of blend through obstacles.
6. **Audio jumps on view change.** Mitigation: `cut` signal and observer reset; listener option.
7. **Second-viewport cost in Compatibility.** Mitigation: PiP is optional, measured and rejectable.
8. **Pilot-centred world assumptions** (population range, grass, impostors) look wrong from far cameras. Mitigation: CAM-20 survey, owners fix.
9. **Motion sickness** with roll-coupled views and wide FOV. Mitigation: comfort mode, horizon lock default, no shake.
10. **Shared-file conflicts** (`main.gd`, director, audio, preferences). Mitigation: single small seams per step, owners review.
