# CAM-06, CAM-06b, CAM-28, CAM-18 — pilot-view aids and magnifier as options; CAM-14 fly-by view

2026-10-25. Three pilot-view aids from the [camera plan](../../../plans/camera-views.md#51-pilot-v1-refactor-of-todays-view-then-improved), offered in **Settings → Camera** and off by default, so the reference picture is unchanged until the pilot compares them in flight (CAM-22). Checks ran on the shared VM (Godot 4.7.2, llvmpipe). They prove the laws and their wiring, not which one reads best.

## What changed

| Step | Files | Behaviour |
| --- | --- | --- |
| CAM-06 | [pilot_camera.gd](../../../../app/render/pilot_camera.gd) `law_fov`, [camera_rig.gd](../../../../app/render/camera/camera_rig.gd) `zoom_law` | Three auto-zoom laws. **Constant size** is today's law, unchanged. **Keeps looming** lets the span shrink as d^−0.5 beyond the distance where the constant law starts, so approach and retreat still read from size. **Gentle** is CRRCSim's form, `atan(tan(base)·21.5 / (21.5 + (d − 21.5)·0.05))`. One Settings picker covers Off, Constant size, Keeps looming and Gentle; Z still turns auto zoom off and on in flight. A law change eases in like a zoom change |
| CAM-06b | [camera_rig.gd](../../../../app/render/camera/camera_rig.gd) `_tilt_to_horizon` | **Keep the horizon in view**: the pilot's look tilts down only as far as keeps the aircraft within 75 % of the half-frame from the centre, and lifts the horizon 30 % of the half-frame above the lower edge. Azimuth, eye, FOV and a level horizon are unchanged; an aircraft that is already low is looked at directly; the tilt eases in and out (half-life 0.25 s). It tilts the view instead of shifting the frustum, because `frustum_offset` breaks Godot's `project_ray_*` and `is_position_in_frustum`, which other code and tests use |
| CAM-28 | [camera_rig.gd](../../../../app/render/camera/camera_rig.gd) `_smooth_overhead` | **Smooth overhead passes**: the picture's up direction turns at most 180°/s; the gaze stays exact, so the aircraft stays centred |
| Settings | [camera_settings.gd](../../../../app/render/camera/camera_settings.gd), [display_preferences.gd](../../../../app/app_state/display_preferences.gd), [settings_screen.gd](../../../../app/ui/settings_screen.gd), [es.po](../../../../app/i18n/es.po), [FIRST-LAUNCH](../../../FIRST-LAUNCH.md) | `display.cfg [camera]` keys `zoom_law`, `horizon_bias` and `overhead_smoothing`, with the CAM-17 per-key fallback. Settings applies them live during a flight |

Not done: keep ground in view (KGIV, which also widens the FOV), the dead and soft zones, hold-to-look snaps (CAM-06c), and a natural FOV computed from the screen. CAM-07 is served by the FOV presets.

## Proofs

| Proof | Result |
| --- | --- |
| `test_camera_views.gd` **91/91** | Constant law bit-identical to today's auto-zoom (10–2000 m). Partial: span ∝ d^−0.5 from 59 to 300 m within 5 %, and never more zoom than constant. Gentle reproduces CRRCSim's 35/26.3/20.4° at 21.5/200/400 m. The rig shows the chosen law. Horizon tilt is off by default; it eases in; the horizon shows with its margin; the aircraft stays within 75 % of the half-frame with a level horizon; a low aircraft is looked at directly. Overhead smoothing off flips the picture at > 1000°/s on the exact pass beside the zenith; on, it turns at < 200°/s with the aircraft exactly centred |
| `test_camera_settings.gd` **42/42** | New keys validate, round-trip and fall back alone. Aids are off at start and apply live. The Camera page shows them off; "Off" keeps the chosen law, and choosing a law turns auto zoom on |
| UI suites | `test_settings_ui` passes: the eight-row Camera page fits 1080p without scrolling. `test_ui_modal_responsive`: 672 cases, the same 6 overlays-dialog failures as pristine HEAD. `test_display_preferences` 64, `test_camera_route` 29 and `test_pilot_aids` 26 pass |
| Compiler warnings | None in the changed scripts |
| Live (1920×1080, [scenario](../../../../research/camera-views/CAM-06-28/live_scenario.txt)) | Airborne Stik about 70 m away and 30 m up: the reference pilot view (FOV 40.3°, look 22.3° up) shows only sky. With the horizon tilt the look drops to 16.6° and the treeline, the mountains and a strip of grass show under the aircraft, which sits 150 px above the centre. The first try with a 10 % margin left the horizon on the lower edge under the HUD bar, so the margin is 30 %. Keeps looming showed 46.5° at 67 m, where the constant law shows 40–42° |

The pilot judges which law, whether to tilt and whether to smooth in CAM-22 on the target display. These software checks do not choose the defaults.

## CAM-14 fly-by view

[flyby_view.gd](../../../../app/render/camera/flyby_view.gd) is a spectator camera. It waits ahead of the aircraft, watches it pass, and re-places itself once the aircraft is 1.7 × D past. Placement follows FlightGear's law ([`Nasal/view.nas`](https://gitlab.com/flightgear/fgdata/-/raw/next/Nasal/view.nas), CAM-AUD survey):

- ahead along the course by 0.8 × (3.5 s × speed), plus half the climb over that time;
- deviated 0.7–1.2 × D (D = 25 m) at any angle around the track when the aircraft is high, and to the side (±90° ± 0.15π) when it is lower than D;
- never below the terrain + 2 m.

One rule is ours: of the two mirror sides, the one with the sun behind the camera. Between placements the camera stands still, turns, and sizes the aircraft to 12 % of the frame height (3–50°); +/− and the wheel change that framing. Its random draws use its own fixed-seed generator, never the simulation's. A hovering or taxiing aircraft gets one spot about D to the side of its nose. Key **4** selects it; it is in the C cycle between chase and orbit and is a Settings first-view choice. After a crash it holds its spot, turns to the wreck and narrows its FOV, as the chase does.

| Proof | Result |
| --- | --- |
| `test_camera_views.gd` (104 total, 14 fly-by) | Exactly 0.8 × 3.5 s × speed ahead with the deviation across the course; deviation 0.7–1.2 D; several shots in 20 s; a new spot only after 1.7 D past; identical placements on a repeat run; 12 % framing; low aircraft from the side; the sun east → camera east, west → west; never below terrain + 2 m; holds while paused; a teleport is placed again; a hover keeps one spot |
| `test_camera_route.gd` 30/30 | Key 4 selects the fly-by and the panel names it "fly-by" |
| `test_controls_reference`, `test_ui_help` | Help lists 4 in the views row and still fits; Spanish "pasada" |
| Live (1920×1080, [scenario](../../../../research/camera-views/CAM-06-28/flyby_scenario.txt)) | Key 4 placed the camera 56 m ahead of the airborne Stik; it approached head-on over the treeline at 13–17° FOV, centred. At about 1 fps on llvmpipe the simulation ran too slowly for a pass during the run; re-placement is covered by the tests |

## CAM-18 magnifier inset

[magnifier.gd](../../../../app/render/camera/magnifier.gd) is a small window at the top centre of the pilot view (22 % of the screen height, framed). It shows the aircraft large, so its attitude reads while the main view keeps the real distance cues. The idea comes from CRRCSim's auto model view, PicaSim's zoom inset and RealFlight's binoculars.

- **Cost.** Like PicaSim's "only plane in zoom view", it draws only the aircraft over the sky. The aircraft's meshes, its propeller-blur disc and the helicopter's rotor discs join render layer `1 << 18`; crash debris uses `1 << 19`. The inset camera's cull mask holds only that layer, so the inset costs a few draw calls, not a second scene render in the Compatibility renderer. It renders nothing while hidden.
- **Framing.** Godot refuses a Camera3D FOV below 1°. The inset camera therefore stands on the pilot's line of sight, at the distance where a 10° FOV frames the span at 60 % of the inset: the same viewing direction, so the same attitude the pilot sees, with a depth range of a few spans around the aircraft. A closer aircraft is framed from the pilot's eye with a wider FOV (up to 60°).
- **Modes.** Off (default), On, or Auto: Auto shows below 4 % of the main view's height and hides above 5 %, so it never flickers. It shows only in the pilot view with an intact aircraft. Settings → Camera → **Magnifier**.
- **Page fit.** To keep the Camera page within 1080p without scrolling, the horizon tilt and overhead smoothing share one picker, **Pilot view aids** (Off, Keep the horizon in view, Smooth overhead passes, Both). They remain two settings.

| Proof | Result |
| --- | --- |
| [test_camera_magnifier.gd](../../../../app/tests/test_camera_magnifier.gd) 21/21 | Tagging covers every aircraft mesh, nested ones included, leaves scenery out and avoids the debris layer. Auto hysteresis: hidden, shown below 4 %, kept up to 5 %, hidden above. The inset sees only the aircraft layer from the pilot's line of sight at 10°, with the span at 60 % and a tight depth range; a close aircraft is framed from the eye; hidden, it does not render. A Home flight with it on shows it in the pilot view, tags every mesh of the flown airplane and no field mesh, and hides it in chase; a command-line flight never shows it |
| Settings | `test_camera_settings` 45/45, including the aids picker (Both, horizon alone) and the stored values. `test_settings_ui` passes: eight rows fit 1080p. `test_ui_modal_responsive`: only the 6 pre-existing overlays-dialog failures |
| Live (1920×1080, [scenario](../../../../research/camera-views/CAM-06-28/magnifier_scenario.txt)) | Magnifier on, horizon tilt on, Keeps-looming law: the inset showed the banked Stik large at the top centre over the sky (238 px, 10°, 14.5 m along the line of sight). The main view kept it small at 44° FOV with the treeline and field below. Pressing 2 (chase) hid the inset |

