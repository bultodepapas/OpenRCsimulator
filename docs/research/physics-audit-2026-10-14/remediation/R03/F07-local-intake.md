# R03 F07 — turbine intake-point velocity

The turbine force law now receives air-relative velocity at the authored intake point. For the current constant-mass model, `Air.compute` gives the body-frame air-relative velocity at the CG, and the intake velocity is

```text
v_intake = v_CG + omega_body × r_intake_body
```

The authored intake arm is `[aft, right, up]`; the runtime converts it to body FRD as `[-aft, right, -up]`. `Turbine.intake_offset_body()` is shared by the velocity and captured-air moment calculations, so the point velocity and force arm use the same datum/arm. `Dynamics._components_from_air()` supplies the current stage's body rates to the common turbine path; generic and stage-air routes therefore evaluate the same local kinematics. The law identity is `turbine-capture-vector-signed-axial-local-intake-v3` (`Turbine.LOADS_LAW`), distinct from the continuous spool-state law.

Implementation references: [turbine.gd](../../../../../app/physics/turbine.gd#L147) lines 147–180, [dynamics.gd](../../../../../app/physics/dynamics.gd#L81) lines 81–94, and [flight_session.gd](../../../../../app/sim/flight_session.gd#L2230) lines 2230–2282.

## Verification

The independent fixture computes the point-velocity equation separately, then compares it with the helper and the resulting common Dynamics loads at `q = +2, -2, 0 rad/s`, with nonzero sideslip, vertical velocity, and wind. It also verifies generic and stage-air paths agree at each stage, that reversing q changes local velocity/load for the offset intake, that thrust projection matches the scalar law, and that zero body rate or zero offset reduces to datum velocity.

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script C:\DEVELOPMENT\OpenRCsimulator\docs\research\physics-audit-2026-10-14\remediation\R03\f07_local_intake_test.gd
```

Result: `F07 local turbine intake kinematics: 7 checks, 0 failed`. Maximum helper-vs-independent formula error was `0.000000000000 m/s`; common Dynamics-vs-direct propulsion load error and generic-vs-stage-air load error were each `0.000000000000 N/N·m`. For the supplied state, the test reported `+q local=[40.1318684263667, -1.0, 5.48358195793046] m/s` and `-q local=[39.9992564263667, -1.0, 6.80358195793046] m/s`. Full output: [f07-local-intake-test.log](f07-local-intake-test.log).

The existing turbine regression remained green:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_turbine.gd
```

Result: `27 checks, 0 failed`; see [f07-existing-turbine-test.log](f07-existing-turbine-test.log). The Avanti handling suite also passed:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_avanti_handling.gd
```

Result: `47 checks, 0 failed`; the pre-FlightSession integration run is [f07-avanti-handling-regression.log](f07-avanti-handling-regression.log), and the final run is [f07-avanti-handling-final.log](f07-avanti-handling-final.log). Both aircraft-loading runs emitted the existing experimental wing-polar provenance warning; the suites completed successfully.

An additional fixture exercises the actual continuous `FlightSession._turbine_evaluate()` callback and accepted-endpoint `turbine_state()` observer:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script C:\DEVELOPMENT\OpenRCsimulator\docs\research\physics-audit-2026-10-14\remediation\R03\f07_session_stage_test.gd
```

Result: `F07 FlightSession continuous stage and telemetry: 7 checks, 0 failed`; see [f07-session-stage-test.log](f07-session-stage-test.log). It supplies `112420 rpm` to a stage while the committed RPM is `92100.644`, independently derives local inlet velocity from that stage's body rates, and finds zero load difference against the actual session callback. The stage spool derivative and rotor momentum match that supplied RPM. The accepted observer likewise reports the local intake vector and derives its axial flow, captured-air mass flow and thrust from the accepted RPM/state.

F02's captured-air continuity fixture was rerun against the final F07 implementation (which leaves the `Turbine.loads` force law intact): `F02 captured-air continuity: 9 checks, 0 failed`; see [f02-post-f07-regression.log](f02-post-f07-regression.log). The separately preserved F02-only source checkpoint is [f02-only-turbine.gd](f02-only-turbine.gd), SHA-256 `0603a1c38c9f8350f12c5e212489f5180b6b96fc95504a97bb428d57bde03dc5`; the earlier F02-only evidence remains [F02-capture-vector.md](F02-capture-vector.md).

## Scope and identity

This is kinematic/software verification, not physical validation of the turbine inlet or its installed force map. It accounts for rigid-body point velocity from the current constant-mass CG datum and authored intake arm. It does not model inlet distortion, separated/crossflow ingestion, an internal duct velocity field, or a measured off-axis engine map. F02 reverse/off-axis captured-air behavior remains an explicitly experimental continuation. The change adds no turbine mounting reaction torque and does not change the documented fixed-mass fuel approximation. Actual inlet geometry and mass-property datum remain subject to aircraft-data validation.

Final implementation/test hashes:

| File | SHA-256 |
|---|---|
| `app/physics/turbine.gd` | `a7577b8d2ddfe7daec69cf2992e8c566688f5b6c89cf6461c5b462abeb1ca702` |
| `app/physics/dynamics.gd` | `5d4d8ea9ae713f36dc977f3ed8dd451bdcc46278e3c68db9f72b2b426046b7f1` |
| `f02_capture_test.gd` | `d8f808b3bd4741c0fa89adb1338fe6ba1abfd83860f0e94ae5e53f6037302257` |
| `f07_local_intake_test.gd` | `f537b570a6151d9e0b4e106485f9aad7388e7b09f09b6d36dd08991655f08f05` |
