# Numerics and ground audit evidence bundle

This bundle supports the [audit note](../../../docs/research/physics-audit-2026-10-14/numerics-ground/README.md). Commands ran against the shared working tree on 2026-10-14 using Godot 4.7.2-stable console; the repository contained unrelated existing edits. No runtime file was modified.

The actual-aircraft diagnostic is [`current_aircraft_invariants.gd`](current_aircraft_invariants.gd). It loads `sebart_avanti_s_a200.json` and `jensen_ugly_stik_60.json` through `AircraftData.load_file`, computes symmetric-tensor principal moments with a Jacobi iteration, and checks tilted free fall and torque-free rotation at 240 Hz. Its complete output is [`logs/current_aircraft_invariants.log`](logs/current_aircraft_invariants.log).

From the repository root, run the diagnostic with:

```powershell
& '.tools\Godot_v4.7.2-stable_win64_console.exe' --headless --path app --audio-driver Dummy --script 'C:\DEVELOPMENT\OpenRCsimulator\research\physics-audit-2026-10-14\numerics-ground\current_aircraft_invariants.gd'
```

Each passing test below was run with:

```powershell
& '.tools\Godot_v4.7.2-stable_win64_console.exe' --headless --path app --audio-driver Dummy --script res://tests/<test_name>.gd
```

All listed scripts exited successfully with zero failed checks. Full raw output is in `logs/`.

| Area | Test script | Checks | Log |
|---|---|---:|---|
| Rigid body | `test_rigid_body` | 15 | [`test_rigid_body.log`](logs/test_rigid_body.log) |
| RK4 | `test_integrator` | 9 | [`test_integrator.log`](logs/test_integrator.log) |
| Dynamics/gyro | `test_dynamics` | 7 | [`test_dynamics.log`](logs/test_dynamics.log) |
| Coupled state | `test_continuous_state` | 42 | [`test_continuous_state.log`](logs/test_continuous_state.log) |
| Nonautonomous RK4 | `test_rk_stage_time` | 22 | [`test_rk_stage_time.log`](logs/test_rk_stage_time.log) |
| Ground normal load | `test_ground_contact` | 22 | [`test_ground_contact.log`](logs/test_ground_contact.log) |
| Ground friction/steering | `test_ground_friction` | 26 | [`test_ground_friction.log`](logs/test_ground_friction.log) |
| Ground stiction | `test_ground_stiction` | 25 | [`test_ground_stiction.log`](logs/test_ground_stiction.log) |
| Ground surfaces | `test_ground_surfaces` | 29 | [`test_ground_surfaces.log`](logs/test_ground_surfaces.log) |
| Crash crossing | `test_hull_crossing` | 40 | [`test_hull_crossing.log`](logs/test_hull_crossing.log) |
| Crash snapshots | `test_crash_snapshot` | 42 | [`test_crash_snapshot.log`](logs/test_crash_snapshot.log) |
| Rotor coupling | `test_rotor_coupling` | 17 | [`test_rotor_coupling.log`](logs/test_rotor_coupling.log) |
| Glow/prop coupling | `test_glow_coupling` | 65 | [`test_glow_coupling.log`](logs/test_glow_coupling.log) |
| Coupled shaft transaction | `test_shaft_coupled` | 43 | [`test_shaft_coupled.log`](logs/test_shaft_coupled.log) |
| Shaft timestep refinement | `test_shaft_refinement` | 3 | [`test_shaft_refinement.log`](logs/test_shaft_refinement.log) |

Aircraft-data and retractable-gear suites also passed 87/87 and 68/68 in this working tree; their captured logs are [`test_aircraft_data.log`](logs/test_aircraft_data.log) and [`test_retractable_gear.log`](logs/test_retractable_gear.log). The loader's Stik inertia-reference warning is preserved in those logs and is not interpreted here as a proven data error.

The additional Avanti brake/ground-start suite `test_retractable_gear_ground.gd` exited 1 on two runs: 25 checks, 1 failed. Both brake-response checks passed; the steady-crosswind runway-start solver check failed with `idling pose did not converge (residual 9.239795830815291)`. Preserve both outputs: [`first run`](logs/test_retractable_gear_ground.log) and [`rerun`](logs/test_retractable_gear_ground_rerun.log). This failure is kept as observed rather than filtered from the audit.

The failing assertion is at `app/tests/test_retractable_gear_ground.gd:256–260`; it expects `_session(240, crosswind).ok`. That is false because `reset_on_runway` rejects the setup during `GroundStart.solve` stage 2 (idle engine with anchors fixed), before the test's follow-on roll/stationarity checks. At fixed `from_deg=0°` and the default eastbound spot, [`runway_crosswind_probe.gd`](runway_crosswind_probe.gd) accepted starts at 0.0, 0.5, and 1.0 m/s and rejected 1.5 m/s with the same mixed linear/angular acceleration residual `9.239795830815291`. This samples only four speeds for this aircraft and direction; it does not establish an operating limit or root cause. The script intentionally exits 1 if any start is rejected; raw output is [`runway_crosswind_probe.log`](logs/runway_crosswind_probe.log).

Reproduce that sweep from the repository root with:

```powershell
& '.tools\Godot_v4.7.2-stable_win64_console.exe' --headless --path app --audio-driver Dummy --script 'C:\DEVELOPMENT\OpenRCsimulator\research\physics-audit-2026-10-14\numerics-ground\runway_crosswind_probe.gd'
```
