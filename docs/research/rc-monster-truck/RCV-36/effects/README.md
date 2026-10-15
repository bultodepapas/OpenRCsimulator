# RCV-36 effects — MONSTER CAR 2

The shared ground effects now bind grime overlays to every mesh in MONSTER CAR 2's authored `body_nodes` list and its four tires. The dirt mask uses the car-root height frame, so the lower-body band stays coherent across the flattened GLB pieces. Dry dust requires tire contact and a loose surface, scales with speed and slip, and is suppressed by a waterline, wheel submersion, body submersion, or mud. Nitro dirt accrues from contacted loose-surface travel (`max(vehicle speed, tire slip speed) × elapsed time`); wet-road wash and mud deposition continue through the shared path. Bisonte retains its previous grime rate.

`GroundEffects.clean_vehicle()` clears grime, wet sheen, and dust buffers without touching telemetry or the authored mesh, livery, or visibility. Tire dust reuses `res://assets/crash/smoke.png`; particle budgets remain 24 per tire. CPU particle simulation is fixed at 60 Hz and pause sets particle speed to zero.

Native inspection found the original opacity too faint on the dark tires. Full-shell Monster overlays use a 1.8 opacity gain; Bisonte keeps 1.0. The physical input, deposition rate and vehicle-space height mask are unchanged. The final [contrast regression](contrast-verification.log) and [fixed-load material probe](../captures/grime-material-probe.png) cover this adjustment; the probe's 0.45 dirt amount is cosmetic test input, not a driving result.

`NitroExhaust.observe(snapshot, paused, simulation_delta := 0.0)` remains compatible with two-argument callers. New nitro telemetry drives output from accepted fuel flow, throttle, positive engine-leading clutch slip, and RPM. Fuel flow is scaled against an estimated `0.0012 kg/s` peak; the vehicle model does not have calibrated engine measurements. Fuel depletion stops exhaust. Older snapshots without the flow key keep the former RPM/fuel gate. The fixed exhaust budget is 32 particles, and paused snapshots freeze the existing puff buffer.

## Verification

| Check | Result |
| --- | --- |
| Focused RCV-36 effects | `test_rcv36_effects.gd`: 376 checks, 0 failures; covers full-shell and tire bindings, untouched source materials, gravel/asphalt and water behavior, airborne contact, distance/time partition, pause, clean/reset, accepted nitro load at equal RPM, fuel cutoff, legacy telemetry, and read-only state |
| Bisonte ground effects | `test_rcv_ground_effects.gd`: 91 checks, 0 failures |
| Bisonte water and grime | `test_rcv_wet_effects.gd`: 79 checks, 0 failures |
| Shared effects activity | `test_rcv_effects_activity.gd`: 19 checks, 0 failures |
| Nitro activity | `test_rcv_nitro_activity.gd`: 91 checks, 0 failures |
| Authored model visual contract | `test_rcv_nitro_visual.gd`: passed; wheels, suspension, steering, and flywheel checks |

The focused checks use Godot 4.7.2 headless mode; [complete command output](headless-verification.log) contains the six initial runs. The final integration adds eight garage/animation checks: [99/99](../checks/nitro-activity.log). Native rendered inspection is retained in the [RCV-36 capture pass](../README.md).

Implementation: [`ground_effects.gd`](../../../../../app/vehicles/ground/ground_effects.gd), [`ground_grime_overlay.gdshader`](../../../../../app/vehicles/ground/ground_grime_overlay.gdshader), [`nitro_exhaust.gd`](../../../../../app/vehicles/ground/nitro_exhaust.gd). Test: [`test_rcv36_effects.gd`](../../../../../app/tests/test_rcv36_effects.gd).
