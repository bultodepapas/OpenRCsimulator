# CAM-00…10 — first camera-views delivery

2026-10-13 · Evidence for [docs/plans/camera-views.md](../../../plans/camera-views.md) steps CAM-00, 01, 02, 04, 05, 08, 10 and the partial CAM-03. Software verification on the shared VM (Xvfb, Mesa llvmpipe, no GPU, no sound). It does not establish pilot readability, comfort or target-machine cost.

## What was built

| File | Step | Content |
| --- | --- | --- |
| [camera_math.gd](../../../../app/render/camera/camera_math.gd) | CAM-01 | Exact exponential damper (half-life), Holden critically damped spring, shortest-way angle damper, ln(tan) FOV space, zoomed FOV, vertical ↔ horizontal FOV, headings, a look basis that stays finite at the zenith |
| [camera_rig.gd](../../../../app/render/camera/camera_rig.gd) | CAM-02/05 | One `Camera3D`; views pilot, chase, orbit, closeup; landscape look override; pilot manual zoom and Z toggle blended in ln(tan) space without lag on a moving airplane |
| [chase_view.gd](../../../../app/render/camera/chase_view.gd) | CAM-08 | Horizon-locked chase: track heading (nose when slow, sliding backwards or vertical), spring on the offset from the airplane, lag cap, look-ahead, terrain clearance, teleport snap, frozen while paused |
| [orbit_view.gd](../../../../app/render/camera/orbit_view.gd) | CAM-10 | Orbit around the CG: right-drag, wheel/=/−, elevation and distance limits, ground clearance; starts from the previous view's direction or behind-left on a fresh flight |
| [main.gd](../../../../app/main.gd) seam | CAM-02/03/04 | Builds the rig, routes C/Shift+C, 1/2/5, Z, =, −, Backspace, wheel and right-drag; `--view=`; `_inspect` kept as a property for existing fixtures; terrain height from the session's own ground table; crash director still aims the camera (closeup/chase/orbit use its wreck view) |
| [controls_reference.gd](../../../../app/ui/controls_reference.gd), [key_labels.gd](../../../../app/ui/key_labels.gd), [es.po](../../../../app/i18n/es.po), [FIRST-LAUNCH](../../../FIRST-LAUNCH.md) | CAM-04 | Two Help rows (no new row: Help had 2 px to spare at 720p); "Backspace" key name; Spanish texts |

## Proofs

Run from a disposable worktree of HEAD plus these files, because the shared tree held another track's unparsable in-progress audio edit at the time.

| Proof | Command | Result |
| --- | --- | --- |
| Math | `godot --headless --path app --script res://tests/test_camera_math.gd` | 21/21. Damper equal to 1e-12 at 30/60/144 fps; spring equal to float32 rounding (Vector3 is 32-bit); 50° vertical = 79.32° horizontal at 16:9 |
| Views | `… res://tests/test_camera_views.gd` | 39/39. Pilot, close-up and look views are exactly `PilotCamera` output; Z and zoom never jump, settle on the law, Backspace restores the exact law FOV; chase settled pose, straight-flight offset equal at 30/60/144 fps and exactly one boom behind, 12 s circle bounded and aimed within 10°, vertical climb holds heading, tail slide/taxi follow the nose, crab follows the track, terrain clearance, NaN terrain, teleport snap, paused freeze; orbit continuity, clamps, zenith, clearance |
| Route | `… res://tests/test_camera_route.gd` | 19/19 through `main.gd` `_unhandled_input`: every key, wheel, right-drag vs plain move, `_inspect` property, restart settles the chase, `--view=chase`, `--inspect`, simulation tick and state untouched |
| Existing tests | `test_controls_reference`, `test_pilot_aids` (22), `test_crash_pose` (107), `test_latency_patch_route`, `test_ui_help` | Pass. Help still fits at 720p in English and Spanish (598 ≤ 600 px) |
| Pixel identity (CAM-02) | `--capture` under Xvfb/opengl3, baseline HEAD vs candidate | Byte-identical PNGs for: pilot `--t=1.5`, `--autozoom=0`, `--inspect`, `--look_az=90 --look_el=10`, `--scripted`, `--scripted --inspect` |
| Trace identity | `--trace=… --t=3` with no view, `--view=chase`, `--view=orbit` | 777-line traces identical except `# created_utc` |
| Refusal | `--view=cockpit` | Exit 31 (`ERR_INVALID_PARAMETER`) with the list of views |
| Live run | `--quick-flight --view=chase` and `--view=orbit`, 25 s under Xvfb | No script or engine errors |
| Cost (VM) | 20 000 updates per view on a 60 m circle, flat ground table | pilot 4.6 µs, chase 12.2 µs, orbit 5.8 µs, closeup 1.5 µs per frame (budget 50 µs) |

Captures reviewed: the chase at t = 1.5 s shows the Stik centred, slightly below the middle, tail toward the camera, horizon level. The first orbit capture started 30 m away, from the camera's unplaced origin; a flight that starts in orbit now begins behind-left of the nose.

## Findings

- **A spring that chases a moving point lags by 2v/ω.** The first chase design sprang the camera's world position. At 20 m/s with a 0.25 s half-life the steady lag is ≈ 7 m, so the camera would drift to its lag cap at any speed. The spring now acts on the offset from the airplane: straight flight has no lag, and only heading, height and zoom changes are smoothed. [LEARNINGS](../../../LEARNINGS.md).
- **Help had 2 px of height left at 720p.** Any extra row overflows. A wide key cap ("Retroceso") widened the cap column and wrapped other rows; Spanish uses "Borrar". The camera keys share the existing C and Z rows, and the numpad +/− are not bound.
- **Tolerances must respect 32-bit render types.** `Vector3` results agree to about 1e-6, not to 1e-9.

## Limits and open items

**2026-10-31 projection-write repair (CAM-02).** Relative to `cfad9b9fc`, the rig
computes the final pilot FOV before assigning it, and skips unchanged FOV/near-plane
writes. Comparisons use the engine's `real_t` precision and read the current camera
properties, preserving native rounding and restoring external projection changes.
No zoom law, camera trajectory or physics behavior is intentionally changed.
Native Windows Godot 4.8-beta1 passes **152/152 camera-view**, **45/45 settings** and
**25/25 history** checks, plus 647 exact baseline comparisons and 786 independent
edge-case comparisons. Valid settings preserve transform, FOV, near plane and
projection. An invalid zero-degree base FOV behaves differently because the former
intermediate native setter rejected it; player settings admit only 30–70 degrees.
Avoided projection writes do not establish a frame-time improvement.
Matched native **1920×1080** captures at 1.5 s are byte-identical for pilot, chase,
orbit and close-up against the baseline checkout: Godot 4.8-beta1, Compatibility,
RTX 3090, NVIDIA 617.42, scenery/birds/engine shadows disabled. Images remain in
ignored scratch output. The full capture runner could not start under Git Bash
because `flock` was unavailable; these four comparisons do not replace that suite.

- The audio listener follows the camera (FlightAudio reads `_camera.global_position`): in chase and orbit the engine is heard from the camera. CAM-16 (cut signal, per-view listener) is not done, and the audio owner has not reviewed it.
- The crash director still writes the camera (CAM-03 partial): non-pilot views get its fixed wreck view. `request_focus` waits for the crash track.
- No onboard/FPV, fly-by, field cameras, PiP, natural FOV, zoom-law family, vertical shift or near-plane change yet (CAM-02b, 06, 07, 11–22).
- No pilot judgement of chase comfort or framing; the defaults are estimates (CAM-22).
