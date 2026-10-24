# CAM-23…27 — camera audit fixes

2026-10-24. These steps act on the [camera audit](../CAM-AUD-2026-10-24/README.md) findings F1, F2, F3, F5, F7, F8 and F9, as the [camera plan](../../../plans/camera-views.md#8-steps) orders them. Checks ran on the shared VM (Godot 4.7.2, Mesa llvmpipe, no GPU). They establish behaviour, not readability, comfort or target-machine timing (CAM-21/22).

## What changed

| Step | Files | Behaviour |
| --- | --- | --- |
| CAM-24 | [chase_view.gd](../../../../app/render/camera/chase_view.gd), [camera_rig.gd](../../../../app/render/camera/camera_rig.gd), [main.gd](../../../../app/main.gd) `_pose_of`/`_render_pose`, [helicopter_main.gd](../../../../app/helicopter_main.gd) `_present` | The chase filters advance in fixed steps of at most 1/240 s (at most 24 per frame), with the target, the nose direction and the velocity interpolated inside the frame. The airplane and helicopter routes pass the CG velocity from the simulation state. It settles the look-ahead at once when the view is entered, then passes through the same 0.08 s damper as the estimate, so contact transients stay smooth. The RC truck keeps the estimate from successive poses. The rig documents that camera consumers run after it and after `focus()` |
| CAM-23 | [spec.gd](../../../../app/spec.gd) `AUTO_ZOOM`, [pilot_camera.gd](../../../../app/render/pilot_camera.gd) `auto_fov`, [telemetry.gd](../../../../app/render/overlays/telemetry.gd) `far_distance` | The auto-zoom target is 30 px of a 1080 px reference height, the same share of the height at every resolution. `auto_fov` no longer takes the viewport height. FAR uses the same reference, so it now fires where the pilot view's zoom reaches its floor: 523 m for the Stik, previously 349 m |
| CAM-26 | [helicopter_main.gd](../../../../app/helicopter_main.gd), [camera_rig.gd](../../../../app/render/camera/camera_rig.gd) `default_pilot_zoom`, [controls_reference.gd](../../../../app/ui/controls_reference.gd), [ground_scene.gd](../../../../app/vehicles/ground/ground_scene.gd), [HELICOPTER](../../../HELICOPTER.md) | Helicopter: Shift+C goes back, Backspace returns to its own 0.35 zoom (it reset to the airplane's 1.0 before), wheel notches honour `factor` and are marked handled, and a restart resets the rig. Help shows the airplane's translated rows. Truck near plane 0.01 → 0.05 m |
| CAM-25 | [project.godot](../../../../app/project.godot) | `physics/common/physics_jitter_fix=0.0`, as Godot documents for a custom interpolation |
| CAM-27 | [camera_rig.gd](../../../../app/render/camera/camera_rig.gd) `focus`, [director.gd](../../../../app/render/crash/director.gd) `focus_point`, [wreck.gd](../../../../app/render/crash/wreck.gd) `core_position`, [main.gd](../../../../app/main.gd) `_process` | After a crash, orbit, chase and close-up look at the wreck's core, not at a fixed offset from the impact point. The orbit turns around the wreck and stays under the player's control. An orbit entered after the slide starts from the previous view's eye around the wreck, so it does not jump. The chase holds its paused position and turns to the wreck. The close-up keeps the former framing offset from the wreck, lifted above the terrain. The pilot view keeps the director's rule. `director.aim` stays for the water-director fixture |

Not done: a shared input router for the airplane route. Its camera keys must stay in `main.gd` `_unhandled_input`, because `test_controls_reference` reads them there, so CAM-26 fixed the helicopter's own handler instead. Camera parameters in the aircraft data contract also remain open. The helicopter span stays at 1.55 m in code.

## Proofs

| Proof | Command | Result |
| --- | --- | --- |
| Views | `python3 tools/godot/run_checked.py -- godot --headless --path app --script res://tests/test_camera_views.gd` | **74/74**. New: 60° bank and loop at 30 vs 144 fps within 1 cm and 2 cm (state and estimated velocity), no slide after entry (≤ 0.01°), airplane in frame through a loop, hard touchdown ≤ 0.6° aim change per 60 fps frame (measured 0.33°; 0.96° with the estimate), hovering pirouette at 30 vs 144 fps within 1 cm, pilot FOV from the reference height in a 64 px viewport, and eight CAM-27 checks (orbit aims at and turns around the wreck, no jump when entered after the slide, chase holds and turns, close-up offset and terrain lift, pilot untouched) |
| Negative control | HEAD's `chase_view.gd` loaded from git into the same metrics | 0.113 m at 30 vs 144 fps (limit 0.01) and a 6.66° slide after entry (limit 0.01°): both new checks fail on the old code |
| Mutations | One at a time on a disposable worktree: no in-frame nose interpolation; unfiltered state velocity; no orbit re-anchor; viewport height back in `aim()`; no sub-steps | Each is caught: pirouette 0.170 m; touchdown 1.78°; orbit jump 13.9 m; FOV 6.0° vs 12.38°; five frame-rate checks fail |
| Route | `… res://tests/test_camera_route.gd` | **29/29**. New: `_pose_of` velocity in render axes; with an active crash director the orbit looks at its focus point and the pilot view keeps its aim; helicopter starts at its own zoom; Shift+C; = and Backspace back to 0.35; half wheel notch; restart forgets the chase |
| Pilot aids | `… res://tests/test_pilot_aids.gd` | **26/26**. New: span ≥ 30/1080 of the height from 20 to 150 m at 720p, 1080p, 1440p and 2160p; at 1080p the FOV equals the former 30 px law **bit for bit** for every distance from 10 to 2000 m |
| FAR | `… res://tests/test_overlay_telemetry.gd` | **41/41** (Stik FAR 523.4 m) |
| Unchanged suites | `test_camera_math`, `test_crash_pose`, `test_water_director`, `test_controls_reference`, `test_ui_help`, `test_heli_control_actions`, `test_heli_render_audit`, `test_heli_night_lights`, `test_controller_flight_actions`, the seven `test_rcv_*` suites that build the truck scene | 21, 281, 22, 13, 38, 28, 32, 47, 32 and 333 checks pass on the final code |
| Compiler warnings | `python3 tools/debug/gdscript_warnings.py --files <each changed script>` | No new warning: the camera scripts, `pilot_camera`, `telemetry`, `spec` and `controls_reference` have none; `main.gd` keeps its 10 earlier ones after renaming one shadowing local this change had added |
| Trace identity | `--trace=… --t=3` with `--view=pilot/chase/orbit`, and before/after CAM-25 | Identical apart from `created_utc` |
| Jitter fix | `research/camera-views/audit-2026-10-24/probe_jitter_fix.gd` | Runtime value 0.0. Audit measurement: at 50 fps, 0.12–0.20 ms RMS presented-time error with 0 against 0.37–0.50 ms with 0.5 |
| Cost (VM) | chase update, 10 000 frames in a turn | 11 µs at 144 fps (2 sub-steps), 17 µs at 60 fps (4), 30–35 µs at 30 fps (8); budget 50 µs |
| Live wreck | `debugctl launch`, then `run research/camera-views/CAM-23-27/wreck_scenario.txt` at 1920×1080 | The wreck slid 12.8 m. After "Inspect wreck": orbit (760, 541) px, and a 500 px drag moved the camera with the wreck still on screen at (1034, 539); chase (960, 540); close-up (960, 540), camera 3.4 m up; pilot (614, 548). The audit's runs had it off screen (x = −540 and −455 px). Clean stop, 0 leaked objects |

The probe tables in [probe_views.gd](../../../../research/camera-views/audit-2026-10-24/probe_views.gd) now print the former and the new auto-zoom law side by side. On a 27-inch screen at 60 cm the new law gives the same on-screen/real size ratio at every resolution: ×1.0 at 100 m, ×3.1 at 300 m. At 720p the span is 20 px instead of 30; 720p is the tertiary target.

## Independent review

A read-only reviewer (Good Enemy role) checked the diff with its own probes. Two defects were fixed before closing:

- Entering the orbit after the wreck slid made the camera jump by the slide (13.9 m in its probe): `focus()` now re-anchors an orbit started this frame on the wreck.
- The raw state velocity carried contact transients into the aim (3.2° per frame at touchdown) and moved in tick steps: it now passes through the look-ahead damper, and only the entry is settled from it.

Its test gaps were closed by the checks above: in-frame interpolation (pirouette), `main.gd` wiring, `aim()` FOV. Its nits were applied: the sub-step count is capped for the truck's raw delta, the nose direction is interpolated instead of the whole basis (a scaled basis made `Basis.slerp` fail), and the comments were corrected. It also confirmed the velocity conversion against the physics quaternion rotation (2.3e-6 m/s), the helicopter state layout, trace independence and every changed caller. Not changed: during a latched water-checkpoint aftermath the director stays active while the airplane flies again, so non-pilot views still follow the impact point (older behaviour; crash track). `research/field-world/fw-moon-01/stepping.py` keeps a dated copy of the former auto-zoom formula.

## Ripple

- The landing kit [e3c2b](../../../../research/landing/e3c2b/) records `reference_height_px` and checks new captures against it; old manifests keep their 540 px meaning. Its `test_kit.py` already failed before this change, in `prepare.py`: the Stik JSON no longer matches the SHA-256 recorded in its evidence.
- Captures at 720p with auto-zoom on show a smaller airplane beyond 39 m. Every 1080p capture is unchanged. Tools that pin `--autozoom=0` are unaffected.

## Open

- CAM-25 needs the owner's A/B with V-Sync on and off at 60/144 Hz on the target machine (CAM-21 metric). Revert is one line.
- The frozen chase shows the wreck small when it slides far; a chase that re-frames the wreck, and a higher default orbit elevation for inspection, are candidates for CAM-03's remainder.
- F19 (the crash text promises C while the accident card blocks it) is for the crash and UI tracks.
