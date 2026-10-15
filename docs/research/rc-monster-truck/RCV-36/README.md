# RCV-36 — Nitro service, mechanics and presentation

2026-10-15. MONSTER CAR 2 now has independent two-stroke engine audio, replayable start/stop/refuel actions, signed clutch power transfer and engine braking, full-shell/tire grime, dry-surface tire dust and load-dependent exhaust. The garage shows fuel mass and flow and offers cosmetic cleaning. The authored clutch bell follows the drivetrain independently of the flywheel. Source Blender/GLB geometry and the 33-value float64 state layout remain unchanged.

Service requires a paused stationary car; refuelling requires a stopped engine. It preserves body state and damage, records ordered actions, and marks the run assisted because starter energy/fuel are externally supplied. Pending recordings must be saved first. Checkpoint restore and same-tape replay preserve service actions and their resulting state exactly. Operating instructions live in the [vehicle guide](../../../../research/rc-monster-truck/monster-car-2/README.md).

| Verification | Retained result |
| --- | --- |
| Start/stop/refuel, rejection atomicity, JSON checkpoint and exact mid-tape replay | [38/38](checks/nitro-service.log) |
| Nitro session and dynamic recording layout | [28/28](checks/nitro-session.log) |
| Home, garage service, sound routing, bell/flywheel and observer state isolation | [99/99](checks/nitro-activity.log) |
| Shared Bisonte session/activity and car menu | [136/136](checks/bisonte-session.log), [24/24](checks/bisonte-activity.log), [27/27](checks/menu.log) |
| Authored visual bindings and motion | [Passed](checks/nitro-visual.log) |
| Physics baseline/candidate comparison, stall and bidirectional clutch | [Physics evidence](physics/README.md): 30 Nitro, 35 data and 55 shared dynamics checks passed; complete 480-tick exact replay, same tape, `solver_changed=true` |
| Grime, wet/dry contact, exhaust and pause/clean lifecycle | [Effects evidence](effects/README.md): 376 focused checks plus existing effects regressions |
| Sound silence, pause, signed load, contact skid, band limits and bounded buffers | [Audio evidence](audio/README.md): 23/23; [4-second WAV](audio/nitro_engine_preview.wav) |

The native OpenGL Compatibility capture uses Godot 4.7.2 on an RTX 3090: [garage off](captures/garage-engine-off.png), [refuelled garage](captures/garage-fuelled.png), [driving dust and exhaust](captures/driving-dust-exhaust.png), [mechanics](captures/mechanics.png), and [dirty](captures/dirty-body.png)/[clean](captures/clean-body.png) views. The [receipt](captures/capture.json) records 960 accepted ticks, four active dust wheels, 70 grime overlays and exact physical-state preservation across cleanup. Four seconds of slow driving deposits only a light coat. Captures use the production activity with a scripted control tape; the harness resumes focus pauses and disables live input for background rendering. Interactive focus/arming remains covered by activity tests. This is source-runtime inspection, not a new packaged-release qualification.

The separate [material probe](captures/grime-material-probe.png) sets cosmetic dirt to 0.45 while paused to inspect lower-body coverage. It is explicitly a shader diagnostic, not the amount deposited by the four-second drive.

The [capture driver](../../../../research/rc-monster-truck/monster-car-2/rcv36/capture_service_effects.gd) takes `--output=<existing absolute directory>` through Godot `--script`. Run with the native renderer, not headless. Generated vehicle data and visual manifest/copy verification passed without asset changes. The full repository test suite and a new release export were not rerun for this scoped update.

The [scoped verification receipt](checks/verification-receipt.json) pins the 14 parsed runtime/test scripts, seven integration logs and physics/audio/render receipts. Recheck with `python research/rc-monster-truck/monster-car-2/rcv36/verify_update.py --godot .tools/Godot_v4.7.2-stable_win64_console.exe`. The physics transcendental-call guard also passed.

The engine curve, consumption, clutch and surface response remain estimates. Fuel inventory does not yet alter mass/CG; the source tank includes an unresolved half-load approximation. Sound, dust, grime and smoke are cosmetic and are not measured acoustic or emissions models. The physics comparison documents software changes, not physical calibration.
