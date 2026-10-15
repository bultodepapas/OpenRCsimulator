# RCV-35 — MONSTER CAR 2 integration evidence

Date: 2026-10-15. Windows, Godot 4.7.2 stable, Blender 5.2.2. This report covers the supplied second vehicle in the current working tree. [Operating and regeneration guide](../../../../research/rc-monster-truck/monster-car-2/README.md).

## Implemented and checked

Home selects either Bisonte MT8 or MONSTER CAR 2. The second car uses the delivered Blender/GLB model, 209 baked suspension/steering transform tracks, independent wheel rotation and engine flywheel animation. Its float64 state adds engine speed and fuel to the shared 31-state body. The nitro model includes an estimated engine curve, inertia, idle control, centrifugal clutch, fixed forward drive, braking and finite fuel. The garage exposes RPM/fuel/clutch engagement, sound, exhaust, lamps, body removal, contacts, damage, water effects, save/restore and replay.

| Check | Result / retained proof |
| --- | --- |
| Nitro kernel | [24 checks, no failures](checks/test_nitro_dynamics.gd.final.log): idle, drive, braking, no reverse, depletion/work budget, stopped engine with fuel, preload, zero/double gravity, half spring rate, 120/240 and 240/480 Hz refinement |
| Nitro session | [28 checks, no failures](session/verification.log): 33-state save/reset/restore, zero-gravity reset, recording identities and exact replay |
| Production Home → garage → Home and CLI | [91 checks, no failures](checks/test_rcv_nitro_activity.gd.final.log), including effects, full-state checkpoint, separate save path and retained aircraft/car selection |
| Authored model fit and animation | [Passed](checks/test_rcv_nitro_visual.gd.final.log): wheel centers within 1 mm, all four positive roll witnesses move forward, independent wheel poses, suspension, symmetric steering signs/limits and flywheel |
| Generated data and copied assets | [Generator freshness and 2/2 mutation tests](checks/generated-data.log); [source/runtime hashes and seven manifest entries](checks/visual-bundle.log) |
| Bisonte regressions | [Data checks](checks/test_rcv_vehicle_data.gd.final.log), [powertrain 9/9](checks/test_rcv_powertrain.gd.log), [session 136/136](session/verification.log), [menu 27/27](checks/test_rcv_menu.gd.final.log) |
| Shared presentation | [Damage 175/175](checks/test_rcv_damage.gd.final.log), [ground effects 91/91](checks/test_rcv_ground_effects.gd.final.log), [water effects 79/79](checks/test_rcv_wet_effects.gd.log), [Home layout](checks/test_ui_home_layout.gd.log) |
| Fresh checkout | [Scoped data/source clone](checkout/fresh-checkout-verification.json) and [visual bundle clone](checkout/visual-checkout-verification.json) with `core.autocrlf=true`; source/generated hashes and source/runtime copies preserved |
| Windows release | [Export passed](checks/windows-release-export.log); [exported executable startup](checks/windows-release-startup.log) exited 0 after 60 frames with `--vehicle=monster-car-2`, no script/resource errors |

`app/test.sh` now includes the data/bundle checks and discovers the new Godot tests. This was a focused integration run; the complete application suite and full application release qualification were not rerun.

## Replay and visual inspection

The [session receipt](session/nitro_session_receipt.json) reports `complete=true`, 480 ticks, 481 recorded samples, 33 state values and exact checkpoint/control replay. Final and replay state SHA-256 are both `0e8f79a780693662715a5ab5f1df314213a17601c6f45d9fc9488e93875f8ddf`. The [CSV](session/nitro_session_recording.csv) and [metadata](session/nitro_session_recording_metadata.json) retain controls, state, events and pinned source/configuration/backend identities. This proves repeatability on that backend, not physical accuracy or equivalence with another backend.

Native Compatibility rendering on an NVIDIA RTX 3090 was inspected at 1280×720: [garage](captures/garage.png), [body removed](captures/mechanics.png), [driving with exhaust](captures/driving.png). The [capture receipt](captures/capture-receipt.json) records the accepted 360-tick run and native solver identity. Wheels sit on the terrain, the original shell and linkage geometry remain present, the body toggle exposes the mechanism, and the nitro HUD and suspension plot do not overlap. These are source-project render captures; the exported executable received a separate headless startup check.

The source/runtime rig binary is 3,553,104 bytes, SHA-256 `4127dc26b64ed2b4ddacd230cc073ec7bab273bb7a624416587264592bfb573d`. A fresh Blender bake into a temporary output matched both binary and manifest. The [asset manifest](../../../../assets/vehicles/monster-car-2/source-manifest.json) pins the editable Blender source, GLBs, simulation metadata, bake generator and derived outputs. Godot remaps the GLB to its imported scene during export; raw source hashes are checked before export, while runtime validates the bake hash, ranges, samples and required scene bindings.

## Qualification limits

Geometry and mass estimates come from the supplied model. Engine, usable fuel, clutch, tire and brake estimates have no measured hardware calibration. The source steering linkage is rendered, while the base solver retains its existing steering approximation and averaged suspension coefficients. Fuel does not alter body mass/CG; thermal, mixture, slosh and automatic shifting are absent. Target-machine performance, physical measurements and pilot/driver acceptance remain open. Export emitted the expected manual-build identity warning; this is a local verification build, not a published release.
