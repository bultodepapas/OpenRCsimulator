# Camera and views plan

**Date:** 2026-10-13. **Status:** CAM-00, 01, 02, 04, 05, 08 and 10 implemented; CAM-03 partial; the rest proposed ([evidence](../research/camera-views/CAM-01-10/README.md)). **Prefix:** CAM-00…CAM-22 ([registry](../README.md#tracks-plans-and-step-ids)). **Owner:** camera-views track, under the main line's acceptance (Gate 2 readability).
**Owns:** `app/render/camera/`, `app/tests/test_camera_*.gd`, `docs/research/camera-views/`; `app/render/pilot_camera.gd` remains the pilot-view law the rig calls.
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

New facts from the 2026-10-13 survey ([§10](#10-external-evidence)) that change the design:

- **Our base FOV is wide for an RC sim.** 50° vertical is ≈ 79° horizontal at 16:9. SeligSIM defaults to 30° ("approximately what you see in real life") and CRRCSim to 35° (roughly horizontal). The geometric FOV of a 24″ monitor at 60 cm is ≈ 28° vertical.
- **Depth precision is poor at our range.** Compatibility uses a 24-bit depth buffer without reverse Z. With near 0.1 m the depth error is ≈ z²/(near·2²⁴): 6 mm at 100 m, 0.6 m at 1 km, 5 m at 3 km, 60 m at 10 km (derived). The pilot view does not need a 0.1 m near plane: the nearest geometry, the pilot-station barrier, is ≈ 1.1 m from the eye (0.75 m high, 0.6 m from the centre; derived from `default.json`). A 0.5 m near plane gives 5× better precision for free.
- **Mature sims converge on the same pilot-view aids:** distance-driven zoom with a strength setting, a vertical shift or "keep ground in view" mode, a dead zone that imitates head tracking, a magnifier inset, hold-to-look snaps (horizon, windsock), several pilot positions, and RealFlight-like keys (C, Shift+C, +/−, Backspace, Z).
- **A horizon-fixed view reduces visually induced motion sickness**; a fixation cross does not (Hemmerich et al. 2020). This supports a horizon-locked chase as the default.

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

`main.gd` keeps one seam: it builds the rig next to `PilotCamera.create`, and `_render_pose` calls `rig.update(...)` instead of `PilotCamera.aim/look`. `_view_name()` delegates to the rig.

As built (CAM-02): the rig is a `RefCounted` with explicit arguments (target, airplane transform, body basis, dt, paused, terrain callable) rather than a context object; views with state are `chase_view.gd` and `orbit_view.gd`; pilot, close-up and look call `PilotCamera` directly, which keeps their pictures byte-identical. Camera keys stay in `main.gd` `_unhandled_input`, because `test_controls_reference.gd` reads the handled keys from that function; they call rig methods. `_inspect` remains a property mapped to the close-up view for existing fixtures. `camera_context.gd`, `camera_pose.gd`, `camera_mode.gd`, `camera_transition.gd` and `camera_collision.gd` are introduced only when a later step needs them.

### 4.2 Frame order

```
_physics_process (240 Hz)  → Simulation ticks
_process (main.gd)         → pose = interpolated(fraction) → _render_pose(airplane, shadow)
                           → rig.update(ctx(pose, dt))     → Camera3D transform/FOV
                           → crash director requests (via rig, not direct writes)
_process (priority 100)    → FlightAudio reads rig.listener_position()
```

### 4.3 Coordinates and precision

Render units are metres, Y-up (`frames.gd`). Camera positions stay within the 21 km ground rim, where float32 resolution is ≤ 2 mm: no origin shifting is needed.

Near/far are per mode, because Compatibility's 24-bit, non-reversed depth buffer makes the near plane the dominant precision term (§2):

| Mode | Near | Far | Reason |
| --- | --- | --- | --- |
| Pilot, field cameras, fly-by | 0.5 m (CAM-02b) | 21 km | Nearest geometry ≈ 1.1 m; 5× better depth precision on the treeline, shadow and runway |
| Chase, orbit | 0.25 m | 21 km | Camera ≥ 0.6 m from any surface (clearance rule) |
| Onboard/FPV | 0.03 m | 6 km | Airframe within centimetres; shorter far plane recovers precision; distant terrain still within the fog/haze |
| Magnifier inset | d − 50 m (≥ 1 m) | d + 50 m | CRRCSim's tight range around the model |

Raising the pilot near plane changes pixels and is therefore its own step (CAM-02b) after the pixel-identical refactor (CAM-02). If the onboard view still z-fights on the 0.05 m ground shadow, it shortens `far` again rather than raising the shadow. A split-depth (far pass + near pass) renderer is out of scope unless CAM-11 shows it is required.

Camera follow runs in `_process` on the interpolated float64 pose, as Godot recommends for cameras under physics interpolation (manual `top_level` camera, updated per frame, following the interpolated transform). The rig never smooths on physics ticks only.

### 4.4 Input map (proposal, D2)

| Input | Action | Note |
| --- | --- | --- |
| **C** | Next view in the enabled cycle | Today: pilot ↔ close-up. Crash text "[C] Change view" stays true. RealFlight: C changes camera mode |
| **Shift+C** | Previous view | RealFlight uses Shift+C for its follow camera |
| **1…7** (top row) | Direct view: 1 pilot, 2 chase, 3 onboard/FPV, 4 fly-by, 5 orbit, 6 field camera, 7 PiP on/off | Number keys are free today; aerofly RC 10 uses 1–4 for its camera modes |
| **Z** | Pilot: zoom law on/off (today's auto-zoom); Shift+Z cycles the law (constant / partial / KGIV) | Unchanged meaning; RealFlight's Z changes zoom mode |
| **= / −**, mouse wheel | Zoom (pilot: manual FOV factor; chase/orbit: distance) | `KEY_EQUAL/KEY_MINUS`; RealFlight uses +/−. Numpad keys are not bound: Help has no room for another key cap at 720p |
| **Backspace** | Reset zoom and the current view's offsets | RealFlight's zoom reset |
| **X / Shift+X** | Next / previous pilot station (CAM-15) | RealFlight's pit-position keys; X is free |
| **G** (hold) | Look at the horizon/ground under the aircraft; release returns | SeligSIM G snap; G is free |
| **Y** (hold) | Look at the windsock | SeligSIM Y snap; Y is free |
| Right mouse drag | Orbit / look around (orbit, chase, onboard head-look) | Phoenix free-look; never captures the mouse while the pause menu or overlays need it |
| Transmitter switch (optional) | Next view / pilot↔chase | Read from an unmapped aux axis, routed to the rig only (never to commands); D9. No surveyed sim documents this; CRRCSim maps joystick buttons to zoom |

The keyboard table in [controls_reference.gd](../../app/ui/controls_reference.gd) and [FIRST-LAUNCH](../FIRST-LAUNCH.md) is updated in the same step that changes a key; its consistency test already enumerates every key.

### 4.5 Settings

Additive `[camera]` section in `settings.cfg`, validated per key like `[hud]` (older builds ignore it): `default_view`, `cycle` (enabled views), `fov_mode` (`fixed` / `natural` / `custom`), `fov_deg`, `screen_diag_in`, `view_distance_cm`, `zoom_law` (`off` / `constant` / `partial` / `gentle` (CRRCSim form) / `kgiv`), `zoom_k`, `zoom_half_life_s`, `vertical_shift`, `magnifier` (`off` / `auto` / `on`), `pilot_station`, `chase_distance_m`, `chase_height_m`, `chase_style` (`horizon` / `follow3d`), `chase_roll_follow`, `fpv_uptilt_deg`, `fpv_fov_deg`, `fpv_lens` (`rectilinear` / `barrel`), `comfort_reduce_motion`, `audio_listener` (`camera` / `pilot`). Direct (automation) routes ignore preferences and accept `--view=<id>` plus the existing `--autozoom`, `--look_*`, `--inspect` arguments.

## 5. Views

Every view lists its law, defaults (all **estimated** unless a source is given) and its specific risks.

### 5.1 Pilot (V1; refactor of today's view, then improved)

The RC pilot standing at a station, turning the head to keep the airplane centred.

Improvements, each optional and measured:

| Option | Law | Why |
| --- | --- | --- |
| Smoothed FOV | Filter the FOV in `ln(tan(fov/2))` space with an exact exponential damper, half-life ≈ 0.15 s; snap on view entry | Removes the jump when **Z** toggles and the "pumping" when distance changes quickly near the clamp |
| Zoom law family (X-PERC-2) | (a) **constant** px (today); (b) **partial**: span `px(d) = max(px_fixed(d), P0·(d0/d)^k)` for d > d0, k = 0.5; (c) **CRRCSim form**: `fov = atan(S / (d0 + (d − d0)·a))`, `S = tan(fov0)·d0`, d0 = 21.5 m, a = 0.05 (35° → 26° at 200 m → 20° at 400 m). (b) and (c) keep part of the looming cue | Today's law removes looming between 39 and 349 m; Phoenix, aerofly and SeligSIM all expose zoom strength |
| Vertical shift | Off-axis projection (`Camera3D.frustum_offset` / `set_frustum`) so the aircraft sits above or below centre in proportion to its elevation relative to the eye, without tilting the view | Phoenix "Normal", aerofly "height dependence", SeligSIM "Shifted": height relative to the observer becomes readable; the ground under the aircraft stays in frame more often |
| Keep ground in view (KGIV) | Widen the FOV (never past the base) and shift, until the ground point under the aircraft stays inside the frame; manual zoom disabled in this law, as in Phoenix | Horizon/ground as attitude and height reference when the aircraft is high ([research 10, theory](../research/roadmap-investigations/10-audio-perception-presentation.md#theory-and-models)) |
| Manual zoom | Multiplicative factor on the law's FOV (0.25×…2×), wheel or +/−; Backspace resets | Phoenix, RealFlight, SeligSIM, CRRCSim, aerofly all have it |
| Base and natural FOV (X-PERC-1) | `fov_v = 2·atan(h_screen / (2·v))` from screen diagonal and viewing distance; settings label the axis (vertical) | Orthoscopic: on-screen angular size equals real angular size. SeligSIM 30° and CRRCSim 35° defaults are close to it; our 50° is not (D11) |
| Head-like tracking (VQ-03) | Dead zone + soft zone around the centre (Cinemachine composer terms): no rotation while the aircraft is inside the dead zone (e.g. 10 % of the half-frame), critically damped rotation in the soft zone, hard limit at the frame edge | Phoenix "Shift-look" and "Camera Speed", CRRCSim "sloppy camera", SeligSIM "Lagged" cameras; reject if it delays tracking in CAM-22 |
| Flying-area bias | Bias the look direction toward the running mean of the aircraft's bearing (window ≤ 60 s), up to 0.6 of the half-FOV | CRRCSim "smart camera": the pattern stays framed and the aircraft drifts less to the edge |
| Hold-to-look snaps | G: horizon/ground under the aircraft; Y: windsock; release returns with a 0.2 s blend | SeligSIM V/G/Y/T snaps; RealFlight quick looks |
| Pilot stations | Choose among stations from field data (CAM-15), X / Shift+X | RealFlight pit positions, aerofly observer positions |
| Magnifier inset | PiP (§5.7): aircraft framed to fill the inset; appears automatically when its main-view span drops below a threshold, with hysteresis | CRRCSim auto model-view inset, RealFlight binocular/viewport gadgets, SeligSIM binocular inset. Keeps looming and background scale in the main view and attitude in the inset |

Hard constraints: the eye never moves with the aircraft; the look direction is exact (no lag) unless the dead-zone option is on; `--autozoom=0` and today's captures remain reproducible bit-for-bit after the refactor (CAM-02).

### 5.2 Chase (V2)

A camera behind the aircraft, for familiarization, aerobatic learning and filming.

Two styles (D5). Horizon-locked is the norm elsewhere: FlightGear's fixed-angle chase does not inherit roll and pitch, aerofly's model camera ignores roll and pitch, and Cinemachine's "Lock To Target With World Up" is the same binding.

As built (CAM-08), the position spring acts on the camera's **offset from the airplane**, not on its world position: a spring chasing a moving point lags by 2v/ω (≈ 7 m at 20 m/s), so straight flight would drag the camera to its lag cap. Wherever this section says "position follows p\*", read "the offset follows p\* − cg".

- **Horizon-locked follow** (default). The camera's yaw follows an alignment heading; its up vector is world up. Alignments (SeligSIM offers all four): **track** (horizontal velocity heading; default), **heading** (body yaw), **air** (relative-wind heading; shows crab in wind), **north** (fixed). Position target: `p* = cg − D·ĥ + H·ŷ`. Below 3 m/s ground speed, track blends to heading over 1 m/s; on the ground it is heading. Position follows `p*` with a critically damped spring (half-life ≈ 0.25 s); yaw follows with half-life ≈ 0.35 s. A lag cap (Unreal `CameraLagMaxDistance`) keeps the boom within 1.5·D. Aim point: `cg + v·t_la` (look-ahead 0.15 s, clamped to 0.6·D; vertical look-ahead ignored, as Cinemachine's "Lookahead Ignore Y") so the aircraft sits slightly below centre.
- **3D follow** (aerobatic). The camera rides a damped copy of the body attitude: `q_cam = slerp_damped(q_cam, q_body, half-life ≈ 0.2 s)`, offset `(−D, H, 0)` in that frame; up vector blended between world up and body up by `roll_follow ∈ [0, 1]` (0.3 default; Cinemachine "Lock To Target No Roll" is 0, "Lock To Target" is 1). Loops and rolls then look like an on-rails chase without the nausea of a rigid mount.

Smoothing kernels (CAM-01), all exact for any dt: the damper `x += (g − x)·(1 − exp(−ln2·dt/h))` and the critically damped spring parameterized by half-life h (Holden, "Spring-It-On"), or Juckett's closed-form spring whose coefficients depend only on (dt, ω, ζ). The naive `k·dt` form is unstable when `k·dt > 1`; Unreal's `CriticallyDampedSmoothing` is accurate only for dt < half the smoothing time. A frame longer than 0.1 s is clamped as `main.gd` already does.

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
- **Optics:** settings and mounts state horizontal, vertical and diagonal FOV separately, because lens labels disagree: two RunCam 2.1 mm lenses are listed as H128°/V91°/D165° and H115°/V83°/D150°. Rectilinear rendering is used up to ~110° horizontal; it stretches badly beyond ~120° and cannot reach 180°. Wider lenses use a barrel warp (CAM-12).
- **Warp method:** render the onboard camera into a `SubViewport` at 1.2–1.5× resolution with overscan, then warp its texture on a full-screen quad. Do **not** use `hint_screen_texture` in 3D: Godot copies the screen after opaque and before transparent geometry, so the transparent propeller-blur disc, smoke and glare would be missing. Liftoff's post-process fisheye shows the trade-off: cropping the black corners made 120° "almost unplayable" from pixelation, hence the supersampled viewport. A cubemap remap (up to 6 renders) is rejected for cost in Compatibility.
- **Uptilt:** default 5° for airplanes, range −10…+30°. Fixed-wing practice is near 0° (community practice, unverified); quads use 20–35° freestyle and 40–60° racing because they fly nose-down. An OSD horizon, if added, compensates the uptilt (INAV `osd_camera_uptilt`).
- **Head look:** right-drag or a head-tracking source rotates the view relative to the mount, recentred by Backspace.
- **Rigid:** no smoothing (a real camera is bolted on); optional ≤ 2 Hz vibration from rpm is off by default and never shakes in comfort mode.
- **Near plane** 0.03 m; hide the propeller blur disc and spinner only when they occlude more than a threshold (D8).
- **Cockpit** (P-51 scale) needs an interior and a pilot figure that the model teams own; out of scope beyond a canopy-frame view at a declared mount.
- **Analog FPV look** (noise, horizontal tearing, colour-sync loss, black frames as a toy SNR from range, antenna orientation and line-of-sight obstruction) is a later presentation option, never presented as a radio-link model. Analog degrades gradually into snow; digital systems freeze or drop frames instead.
- **Padlock variants** (SeligSIM F9/F10): the onboard head locks onto a target (the pilot station or runway threshold). Optional, after head look works.

### 5.4 Fly-by / tracking (V4)

A spectator or photographer by the flight path (SeligSIM FlyBy "jump ahead/behind" at 6 ft and 100 ft AGL). The camera is placed on the ground (or at altitude) ahead of the aircraft, at `cg + v̂·L + lateral·S` (L ≈ 60 m, S ≈ 15 m at 1.7 m eye height, both scaled by speed), looks at the aircraft with the pilot-view zoom law, and re-places itself after the aircraft passes and is farther than L. Placement rejects points inside obstacles or below terrain and prefers the side opposite the sun (no backlit aircraft). This is the cheapest "cinematic" view and the best aircraft beauty shot; it is not a piloting view.

### 5.5 Orbit / inspect (V5)

Replaces today's rigid close-up. A camera on a sphere around the CG: azimuth/elevation by right-drag, distance by wheel (0.6…20 × span), no roll, world up, look at the CG. The "close-up" preset reproduces today's `INSPECT_OFFSET` framing (left, above, behind) in the airplane's yaw frame so existing inspection captures keep a comparable view. Works paused (the pause-backdrop alternative in [MENU-REDESIGN-PLAN §7](../MENU-REDESIGN-PLAN.md#7-decisions-for-the-owner)).

### 5.6 Field cameras (V6)

Fixed cameras defined by field data: tower, runway threshold, pits, spectator line. Each has position, look mode (`track` the aircraft with the pilot zoom law, or `fixed` direction) and FOV. The same data block declares alternative **pilot stations** used by V1 (D10). Both extend `openrc-field` additively with `{value, unit, kind, source}` quantities and are owned by the field-world/scenery tracks.

### 5.7 Picture-in-picture (V7)

A `SubViewport` sharing the main `World3D`, rendered small (≈ 15–25 % of the screen; CRRCSim uses 15 %) in a corner, showing a second view: the **magnifier** (from the pilot's eye, FOV framed so the aircraft fills the inset) or a chase inset. The magnifier appears automatically when the aircraft's main-view span falls below a threshold (CRRCSim: angular size × 1.3 < 15 % of the main FOV) and hides above it plus a hysteresis band (CRRCSim has none; we add it to avoid flicker). Compatibility has "low base cost, high scaling cost": every extra 3D viewport re-renders the scene. The inset therefore uses a tight depth range around the aircraft (§4.3), render layers that exclude far scenery where acceptable, lower MSAA, no sun-glare pass, its own audio listener disabled, update mode "when parent visible", and optionally a 30 Hz update. Kept only if its measured cost is within budget on the target GPU (§7) and the orientation kit shows a benefit.

### 5.8 Off-screen indicator

When the aircraft leaves the frame (field cameras, orbit, onboard), an edge arrow points toward it, with distance. Implemented by the overlays track (HUD) from `rig.evidence()` and the aircraft position; this plan only provides the seam.

### 5.9 Crash and replay

The crash director stops writing the camera. It calls `rig.request_focus(point, duration_s, reason)`; each mode answers: pilot keeps the station and widens to FOV ≥ 12° (today's rule); chase freezes position and looks at the wreck; onboard cuts to an orbit around the wreck; orbit retargets. Replay cameras (CR-20…27) use the same rig with a recorded pose stream; their design stays in the crash plan.

### 5.10 Head tracking and VR

Remain spikes X-PERC-8 (opentrack UDP → head rotation offset on V1/V3 only) and X-PERC-9 (OpenXR at the pilot station) in research 10. opentrack's UDP output is a raw `double[6]` datagram (TX, TY, TZ, yaw, pitch, roll) to port 4242 by default; units by convention cm and degrees (unverified). A `PacketPeerUDP` reader in the rig can consume it; it is camera input only and never reaches the session. TrackIR is reported to work with RealFlight; RealFlight Evolution and aerofly RC 10 support VR, and aerofly offers "model magnification" in VR instead of zoom. The rig's "head offset" input is designed so either spike can feed it later without a new seam.

## 6. Cross-cutting rules

| Topic | Rule |
| --- | --- |
| Transitions | Pilot ↔ fly-by/field: blend 0.4 s (position lerp, attitude slerp, FOV in tan-space). Any change into or out of onboard, and any blend whose path would cross terrain/obstacles: cut. Reset and restart: cut |
| Audio listener (D3) | Per view: pilot, field cameras and fly-by place the listener at the camera's eye (zoom changes FOV, never the eye, so the pilot hears from the station); onboard places it at the mount; chase places it at the camera by default, with an option to keep it at the pilot station. The rig exposes `listener_position()`; FlightAudio reads that instead of `_camera.global_position`. On a cut, the rig emits `cut` and FlightAudio calls `soundscape.reset_observer()` so Doppler and delay do not jump. PiP viewports never own a listener |
| Exposure | Onboard and chase use the same `ground_share` input with a 0.5 s low-pass in the rig's context, so a roll through the horizon does not pump exposure; field-world owners review |
| Overlays | Wind arrow uses the active camera heading (unchanged). FAR, LOW and distance values remain pilot-referenced in every view |
| Scenery LOD | Captures from chase/fly-by at 300 m and 800 m from the pilot verify population ranges, grass fade and impostors; any pilot-centred assumption is reported to its owner, not patched here |
| Comfort | `comfort_reduce_motion` = horizon lock, no FOV kick, no vibration, slower transitions, no automatic camera motion (dead zone and area bias off). No camera shake anywhere by default (crash plan keeps none). Xbox Accessibility Guideline 117 and the Game Accessibility Guidelines ask to avoid or allow disabling shake, bob and motion blur, to offer an adjustable FOV and to allow disabling automatic camera movement. Wider FOV raised simulator-sickness scores in Lin et al. (2002) |
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
| CAM-00 | Register prefix and paths in the [registry](../README.md#tracks-plans-and-step-ids); owner decisions D1–D10; DECISIONS row; confirm keys | Registry row, DECISIONS row / done: registry row, DECISIONS row; D1–D12 defaults adopted provisionally ("proceed") |
| CAM-01 | `camera_math.gd`: exponential damping, analytic critically damped spring, damped slerp, look basis with zenith handling, FOV conversions (vertical/horizontal/diagonal, focal length), `projected_px`, zoom laws (constant, partial k, KGIV), natural FOV | `test_camera_math.gd`: known values, step responses at 30/60/144 fps equal at matched times, no NaN at vertical look / done: 21 checks; spring frame-rate equality to float32 rounding |
| CAM-02 | `camera_rig.gd`, context, pose, mode base; port pilot, close-up and landscape `look` as modes; `main.gd` seam; `PilotCamera` wrappers kept | Pixel-identical captures vs `main` for pilot (auto-zoom on/off), close-up and three `--look_*` cases; trace identity; `test_pilot_aids` unchanged / done: six byte-identical captures, trace identity, existing tests pass |
| CAM-02b | Per-mode near/far (§4.3); pilot near 0.1 → 0.5 m | Depth-error table recomputed; treeline/runway/shadow captures at 100 m, 1 km, 3 km before/after (less z-fighting, no clipping of the station barrier or people); explained capture change / proposed |
| CAM-03 | Crash director through `rig.request_focus`; remove its direct camera writes | `test_crash_pose` and crash captures unchanged for pilot and close-up / partial: `main.gd` passes "not pilot" to `director.aim`; the director (crash track) still writes the camera |
| CAM-04 | View selection input (C, Shift+C, 1…7, Backspace), `--view=`; controls reference, FIRST-LAUNCH, es.po | Key consistency test; trace identity per view / done for 1, 2, 5, C, Shift+C, =, −, Backspace, wheel, right-drag, `--view`; G, Y, X with their views |
| CAM-05 | Pilot: smoothed FOV, manual zoom (+/−, wheel) | Step test: Z toggle reaches 95 % in 3τ with no overshoot; capture series / done: no frame jumps > 3°, exact law FOV restored |
| CAM-06 | Pilot: zoom law family (constant, partial k, CRRCSim form) and Shift+Z (implements X-PERC-2) | On-screen size ∝ d<sup>−k</sup> within 5 % from 20–300 m; CRRCSim form reproduces 35°/26°/20° at 21.5/200/400 m / proposed |
| CAM-06b | Pilot: vertical shift (off-axis frustum) and KGIV | Ground point under the aircraft stays in frame for KGIV over a recorded circuit at 30–150 m height; no tilt of the horizon line; captures / proposed |
| CAM-06c | Pilot: hold-to-look snaps (G, Y), dead zone/soft zone and flying-area bias (VQ-03) | Release returns to the exact tracking pose; aircraft never leaves the frame in a recorded aerobatic sequence; options default off until CAM-22 / proposed |
| CAM-07 | Natural FOV from screen size and distance (implements X-PERC-1) | Pure test vs research 10 table; rendered span within ±1 px of prediction / proposed |
| CAM-08 | Chase, horizon-locked style, terrain clearance | Synthetic trajectories (circle, loop, vertical line, tail slide, ground roll, reset): continuity, clearance ≥ 0.6 m, jitter budget; captures / done: offset spring (see §5.2), 12 s circle, vertical, tail slide, terrain, teleport, paused |
| CAM-09 | Chase, 3D follow style, roll-follow, look-ahead, obstacle shortening | Loop and four-point roll captures; boom shortens at the pavilion fixture; frame-rate independence / proposed |
| CAM-10 | Orbit/inspect replacing the rigid close-up; works paused | Close-up preset capture comparable to CAM-02; mouse never steals focus from overlays/pause / done: orbit added beside the close-up (not replacing it yet); continuity and clamps tested |
| CAM-11 | Onboard/FPV with derived default mounts; near/far per mode; depth check on the shadow | Captures for every catalog aircraft; z-fighting check on the ground shadow at 1, 5, 50 m / proposed |
| CAM-12 | FPV lens: supersampled `SubViewport` (1.2–1.5×) + barrel warp | Distortion matches the chosen lens model within 1 % of radius; propeller blur and smoke visible (no screen-texture copy); cost within budget, or rejected / proposed |
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

Order: CAM-00 → 01 → 02 → 02b → 03/04 → 05 → 06 → 07 → 08 → 10 → 06b → 09 → 16 → 11 → 17 → 18 → 06c → 14 → 13 → 12 → 15 → 19 → 20 → 21 → 22. The pilot-view improvements come early because they serve Gate 2; the magnifier (CAM-18) moves ahead of the cinematic views because three of the surveyed sims treat it as a readability aid.

## 9. Decisions for the owner

Status: the recommended defaults are adopted provisionally (2026-10-13, owner: "proceed with the implementation"); any of them can be overridden.

| ID | Question | Recommended default | Alternatives |
| --- | --- | --- | --- |
| D1 | Default view for Home flights | Pilot | Remember last view |
| D2 | Key layout | §4.4 (C cycles, 1…7 direct) | Function keys; C keeps pilot ↔ close-up only |
| D3 | Audio listener | Per view (§6): pilot station for pilot views, mount for onboard, camera for chase with a pilot-station option | Always pilot station (more "RC-true") |
| D4 | Pilot zoom law default | Today's constant 30 px until CAM-22 picks a law | Partial k = 0.5; CRRCSim form; natural FOV + magnifier |
| D5 | Default chase style | Horizon-locked | 3D follow |
| D6 | Views enabled in the C cycle | Pilot, chase, onboard, orbit | All |
| D7 | Camera mounts in the aircraft contract | Optional capability, derived default labelled `estimated` | Render-side table per aircraft |
| D8 | FPV propeller | Keep the blur disc visible | Hide it in onboard view |
| D9 | Transmitter switch for views | Off by default, assignable in calibration | Not offered |
| D10 | Extra pilot stations | Data-defined per field, chosen in conditions or with X | Free placement; walking pilot (Heli-X, RealFlight) |
| D11 | Base pilot FOV | Keep 50° vertical until CAM-22; offer natural FOV and 30–35° presets now | Switch default to ≈ 30° (SeligSIM/CRRCSim practice) before Gate 2 |
| D12 | Pilot near plane | 0.5 m (CAM-02b) | Keep 0.1 m |

## 10. External evidence

Web survey, 2026-10-13. Primary documentation was available for RealFlight Evolution, Phoenix R/C 3.0, aerofly RC 10, SeligSIM/FS One and CRRCSim (whose camera source was read). Primary docs for AccuRC 2, ClearView, PicaSim, Heli-X, neXt, Velocidrone, DRL and TRYP were thin or missing; their behaviour is not relied on. "Derived" marks our own arithmetic.

### 10.1 RC simulators compared

| Feature | RealFlight Evo | Phoenix 3.0 | aerofly RC 10 | SeligSIM / FS One | CRRCSim 0.9.13 | This plan |
| --- | --- | --- | --- | --- | --- | --- |
| Pilot auto-zoom | Zoom modes (Z) | Yes, plus extra zoom for small models | FOV regulated by distance | Autozoom-1/-2 | `fov = atan(S/(d0+(d−d0)·0.05))` | Law family, CAM-06 |
| Manual zoom | +/−, Backspace reset | Wheel on top of autozoom | Z / Shift+Z | Z/X, D reset | ±5°, 5–65° | CAM-05 |
| Vertical shift / ground in view | Older "keep ground in view" (unverified for current) | Normal (shift) and KGIV modes | Height-dependent shift | Shifted and KGIV cameras | — | CAM-06b |
| Dead zone / head-like lag | — | Shift-look, Camera Speed | — | Lagged cameras | Sloppy and smart camera | CAM-06c |
| Magnifier / inset | Binocular, viewport gadget (PiP) | — | Screen split | Inset window: binoculars, chase, top-down | Auto model-view inset, 15 % | CAM-18 |
| Pilot positions | Pit positions X/Shift+X, walk | — | Observer positions V/B | — | — | CAM-15 |
| Snaps | Look at windsock/ground/aircraft | — | — | V/G/Y/T hold-to-look | — | CAM-06c |
| Chase | F3, follow Shift+C | — | "Elastic rope" follow | Track/heading/air/north aligned | — | CAM-08/09 |
| Onboard | Nose F2, onboard F4–F10 | — | Model camera, cockpit | Onboard, padlock | — | CAM-11 |
| Orbit / free | Pivot E, orbit Ctrl+E | Free-look right-drag | Fixed observer orbit | Mouseable chase | — | CAM-10 |
| Fly-by | — | — | — | Jump ahead/behind | — | CAM-14 |
| Default FOV | — | — | — | 30° | 35° (≈ horizontal) | 50° vertical today (D11) |
| VR / head tracking | VR; TrackIR reported | — | VR, model magnification | — | — | Spikes X-PERC-8/9 |

### 10.2 Engineering references

- Smoothing: T. Lowe, "Critically Damped Ease-In/Ease-Out Smoothing", *Game Programming Gems 4* §1.10 (basis of Unity `SmoothDamp`); R. Juckett, damped springs (closed form); D. Holden, "Spring-It-On" (half-life damper and spring); Unreal `FMath::CriticallyDampedSmoothing` (dt < half the smoothing time).
- Composition: Cinemachine Transposer binding modes and Composer dead/soft zones, lookahead and "ignore Y"; Unreal `USpringArmComponent` lag, lag cap, substepping and probe sphere; FlightGear fixed-angle chase (`from-model=false`).
- Design literature: J. Nesky, "50 Game Camera Mistakes", GDC 2014; M. Haigh-Hutchinson, *Real-Time Cameras* (2009), ch. 9–10.
- Godot: Camera3D (`keep_aspect` KEEP_HEIGHT, `frustum_offset`, `set_frustum`); physics interpolation and the manual camera approach (4.4+); renderer comparison (Compatibility: 24-bit depth, no reverse Z, no CompositorEffects); screen-reading shaders (copy before transparents); viewports (each 3D viewport re-renders; own audio-listener flag); `AudioListener3D.make_current()`.
- FPV: Oscar Liang camera-angle and lens guides; RunCam/GetFPV lens listings; Liftoff developers on post-process fisheye; INAV `osd_camera_uptilt`, Betaflight `fpv_mix_degrees`; opentrack UDP protocol source (port 4242, `double[6]`).
- Human factors: 1 arcmin acuity (Snellen); Lin et al., IEEE VR 2002 (FOV vs presence and sickness, n = 10); Hemmerich, Keshavarz & Hecht 2020 (earth-fixed horizon reduces VIMS); Xbox Accessibility Guideline 117; Game Accessibility Guidelines (FOV defaults, disable shake/tilt).

### 10.3 Source links (accessed 2026-10-13)

- RealFlight Evolution Help Guide: <https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/1314820/manuals/RealFlight_Help_Guide.pdf>
- Phoenix R/C 3.0 manual: <https://www.astramodel.cz/manualy/runtime/RTM3000-Manual_EN.pdf>
- aerofly RC 10 manual: <https://www.ikarus.net/en/rc10-manual/>
- SeligSIM cameras: <https://www.seligsim.com/manual/cameras.html>; FS One camera views: <https://michaelselig.substack.com/p/exploring-camera-views-in-fs-one>
- CRRCSim 0.9.13 source (`src/zoom.cpp`, `src/mod_video/crrc_graphics.cpp`): <https://deb.debian.org/debian/pool/main/c/crrcsim/crrcsim_0.9.13.orig.tar.gz>
- Heli-X eye height in photo sceneries: <https://forum.heli-x.info/viewtopic.php?p=5368>
- TrackIR with RealFlight: <https://www.modelaviation.com/article/trackir-5>
- Unity SmoothDamp: <https://docs.unity3d.com/ScriptReference/Mathf.SmoothDamp.html>; GPG4 entry: <https://www.gameenginegems.com/gemsdb/article.php?id=274>
- Unreal CriticallyDampedSmoothing: <https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Core/FMath/CriticallyDampedSmoothing>; SpringArm: <https://docs.unrealengine.com/4.27/en-US/API/Runtime/Engine/GameFramework/USpringArmComponent/>
- Juckett damped springs: <https://www.ryanjuckett.com/damped-springs/>; Holden: <https://theorangeduck.com/page/spring-roll-call>
- Cinemachine Transposer: <https://docs.unity3d.com/Packages/com.unity.cinemachine@2.10/manual/CinemachineBodyTransposer.html>; Composer: <https://docs.unity3d.com/Packages/com.unity.cinemachine@2.10/manual/CinemachineAimComposer.html>
- FlightGear views: <https://wiki.flightgear.org/Configuring_Views_in_FlightGear>
- Nesky GDC 2014: <https://www.youtube.com/watch?v=C7307qRmlMI>; Haigh-Hutchinson: <https://www.routledge.com/Real-Time-Cameras-A-Guide-for-Game-Designers-and-Developers/Haigh-Hutchinson/p/book/9780429258190>
- Godot Camera3D: <https://docs.godotengine.org/en/latest/classes/class_camera3d.html>; interpolation: <https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/advanced_physics_interpolation.html>; renderers: <https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html>; reverse Z: <https://godotengine.org/article/introducing-reverse-z/>; screen-reading shaders: <https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html>; viewports: <https://docs.godotengine.org/en/stable/tutorials/rendering/viewports.html>; AudioListener3D: <https://docs.godotengine.org/en/stable/classes/class_audiolistener3d.html>
- FPV: <https://oscarliang.com/camera-angle/>, <https://oscarliang.com/fpv-camera-lens>, <https://www.getfpv.com/runcam-rc21-fpv-short-lens-2-1mm-fov165-wide-angle.html>, <https://steamcommunity.com/app/410340/discussions/0/1496741765128458084>, <https://intofpv.com/archive/index.php/thread-25676.html>
- opentrack UDP: <https://raw.githubusercontent.com/opentrack/opentrack/master/proto-udp/ftnoir_protocol_ftn.cpp>
- Human factors: <https://research.polyu.edu.hk/en/publications/effects-of-field-of-view-on-presence-enjoyment-memory-and-simulat/>, <https://public-pages-files-2025.frontiersin.org/journals/virtual-reality/articles/10.3389/frvir.2020.582095/text>, <https://devdocs.xbox.com/gaming/accessibility/xbox-accessibility-guidelines/117>, <https://gameaccessibilityguidelines.com/if-the-game-uses-field-of-view-3d-engine-only-set-an-appropriate-default-for-the-expected-viewing-environment/>

Gaps: no surveyed sim publishes pixel-size targets, zoom hysteresis or transmitter-switch camera mapping; no study of roll-coupled third-person cameras was found; fixed-wing FPV uptilt values are community practice. CAM-00 copies this survey into `docs/research/camera-views/` as dated evidence before implementation, so the plan can later shrink to a link.

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
