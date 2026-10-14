# R03 F02 — Continuous captured-air momentum candidate

The F02-only change versions the turbine load law as `turbine-capture-vector-signed-axial-v2`. It keeps the current nonnegative captured-air flow and positive-axial ram-rise map. The inlet momentum force is now `-mdot_capture * v_in` on both sides of axial zero; scalar axial thrust is the projection `gross_thrust - mdot_capture * u_in` with signed `u_in`. Static and positive-axial behavior remain unchanged for a fixed input velocity.

This is an experimental continuation of the installed force surrogate. Reverse-axial and off-axis capture are not identified by the available engine data. F07 point-velocity kinematics are intentionally absent from this F02-only evidence; at this phase `v_in` is the velocity argument supplied by the caller.

## Verification

Ran the focused independent fixture outside `app/`:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script C:\DEVELOPMENT\OpenRCsimulator\docs\research\physics-audit-2026-10-14\remediation\R03\f02_capture_test.gd
```

Result: `F02 captured-air continuity: 9 checks, 0 failed`. The log is [f02-capture-test.log](f02-capture-test.log). It confirms static thrust `90 N`, positive axial thrust `80 N` at `50 m/s`, the deliberate reverse continuation `98 N` at `-40 m/s`, scalar/vector projection agreement on a rotated axis, independent force and distinct-arm moments, and the applied-load power identity (`1652.386800000000 W` on both sides). Around axial zero with transverse velocity `[20, -13] m/s`, the maximum component difference between `u=-1e-6` and `u=+1e-6 m/s` was `0.0000004`; at `u=0` the force was `[90, -4, 2.6] N`.

The existing focused turbine suite also passed:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_turbine.gd
```

Result: `27 checks, 0 failed`; output is [f02-existing-turbine-test.log](f02-existing-turbine-test.log). It retains the current positive-flow ram-recovery checks (`81.2205 N` at `70 m/s`) and spool/gyro tests.

## F02-only identity

The captured baseline identity is [R00 baseline-identity.json](../R00/baseline-identity.json). At the F02-only checkpoint:

| File | SHA-256 | Baseline relation |
|---|---|---|
| `app/physics/turbine.gd` | `0603a1c38c9f8350f12c5e212489f5180b6b96fc95504a97bb428d57bde03dc5` | F02 candidate |
| `app/physics/dynamics.gd` | `313851831baa6ccf9769a2a4a28220de96650ff3b64c60dc5275857da89806d3` | unchanged from baseline |
| `app/tests/test_turbine.gd` | `479fda875518893f196632aba8e9f999c121b6e7fb453fadef2f9bb8e418bd20` | unchanged from baseline |
