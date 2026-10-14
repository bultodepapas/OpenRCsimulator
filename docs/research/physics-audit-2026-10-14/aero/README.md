# Aerodynamics audit: Avanti S and Ugly Stik 60

**Date:** 2026-10-14  
**Scope:** current `app/physics/aero.gd` behavior for the catalog Avanti S and Jensen Ugly Stik 60. No production code, aircraft data, existing tests, or existing documentation were edited for this audit.

## Finding: local loads are path-dependent as the wing sees spanwise flow

The local surface model does not have a continuous force/moment limit at 90° sideslip when chord-plane flow approaches zero. For the same finite airspeed and nearly identical body velocity vectors, an arbitrarily small residual forward component selects the attached wing drag coefficient, while an arbitrarily small vertical component selects the 90° separated coefficient. The difference survives as the residual tends to zero; at the exact `[0, V, 0]` vector, `atan2(0, 0)` selects the low-drag branch.

The probe constructs the vectors directly in body coordinates rather than deriving them from α/β trigonometry. It holds total airspeed exactly at the aircraft's authored start speed, body rates and controls at zero, and sea-level density at 1.225 kg/m³. The reported flow-parallel coefficient is

`CD_flow = -F·v_air / (V * qbar * S)`, where `qbar = 0.5 * rho * V²`.

This definition remains valid for side-on flow; it does not depend on selecting a wind-axis direction where the chord-plane projection is zero. Forces and moments below are body-axis loads about the CG (x forward, y right, z down). Negative `Fy` opposes the positive-y air velocity. `P = F·v_air + M·omega`; with zero body rates this equals translational aerodynamic power.

| Aircraft and body velocity (m/s) | α / β | Wing-strip CD | Total `CD_flow` | Total `Fy` (N) | Total `Mx`, `Mz` (N·m) | Aero power (W) |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Avanti, `[1e-9, 29, 0]` | 0° / 90° | 0.035284 | 0.328998 | −119.015 | −25.107, +61.239 | −3,451.445 |
| Avanti, `[0, 29, 1e-9]` | 90° / 90° | 1.247277 | 1.822522 | −659.299 | −28.943, +120.610 | −19,119.658 |
| Stik, `[1e-9, 15, 0]` | 0° / 90° | 0.044812 | 0.173625 | −11.115 | −0.800, +5.994 | −166.722 |
| Stik, `[0, 15, 1e-9]` | 90° / 90° | 1.243400 | 1.619006 | −103.642 | −5.450, +14.569 | −1,554.634 |

At exact `[0, V, 0]`, both aircraft take the same low branch as `[1e-9, V, 0]`. The contrasting `+u` and `+w` velocities differ in direction by only about `2.8e-9°` for the Avanti and `5.4e-9°` for the Stik at `epsilon = 1e-9`. The measured response also stays on its respective branch at `epsilon = 1e-2`, `1e-4`, and `1e-6`; this is not a one-ulp effect. At Avanti start speed the total side force changes by 540.283 N and yaw moment by 59.371 N·m between the two limiting paths. At Stik start speed they change by 92.527 N and 8.574 N·m.

The lead independently repeated the Cartesian paths at a common 20 m/s: Stik `Fy` changed from −19.75965 N to −184.25289 N (Δ −164.49324 N), and Avanti from −56.60659 N to −313.57838 N (Δ −256.97179 N). This confirms the result is not an artifact of comparing the aircraft's different authored start speeds.

The source explains the mechanism. `air_data.gd:34-37` defines α as `atan2(w, u)` and β from `v` and the chord-plane magnitude. `aero.gd:327` defines each wing strip's effective α from `atan2(f2, f0)`. At `aero.gd:380-393`, the strip drag coefficient is selected from that angle, and the drag magnitude and vector use full 3-D speed and flow; only lift uses the projected chord-plane speed. Thus the coefficient can jump between its attached and separated branches while the projected speed goes to zero and full speed remains finite. At `aero.gd:577`, 90° sideslip selects the local-load branch, and the reported cases confirm `Aero.loads` equals `_local_loads` (`local_match=true`).

This is a current model-form defect in the extreme side-on-flow region. The audit does not claim that the low branch gives the real aircraft's correct edgewise drag. A future treatment should define edgewise surface forces separately or otherwise make the three-dimensional load map continuous as the chord-plane projection vanishes; simply substituting a different exact-90° coefficient would leave the path dependence unresolved. The same response appears on the Stik, which has no optional tabulated wing polar, so it is not caused by the Avanti polar data.

## Results that did not reveal another defect

The aero power grid contains 1,683 states per aircraft: α in `{-180, -150, -120, -90, -60, -30, -25, -15, 0, 15, 25, 30, 60, 90, 120, 150, 180}°`; β in `{-90, -75, -45, -25, -15, 0, 15, 25, 45, 75, 90}°`; and body rates `(0,0,0)`, each signed unit-axis rate, and `(2,-2,2)` / `(-2,2,-2)` rad/s. With controls and propulsion absent, every load and power was finite and `F·v_air + M·omega` was non-positive. The least-negative case was attached, zero-rate flight: −368.761 W for the Avanti at 29 m/s and −42.862 W for the Stik at 15 m/s. The Cartesian crossflow case is also dissipative; its defect is the size/path dependence of the drag and moments, not energy creation.

Full-throw positive and negative pilot roll, pitch, and yaw commands produced the expected respective body moment signs (`+Mx`, `+My`, `+Mz` for positive input) at each aircraft's start speed, with zero initial α, β, and rates. These are sign checks, not claims that the estimated throw/effectiveness gives realistic control authority. Central rate probes at ±0.01 rad/s and start speed recovered the current input derivatives exactly in the attached branch. For the Avanti, the recovered p/q/r tuples were `CYp/Clp/Cnp = −0.157629/−0.606891/+0.008622`, `CLq/Cmq = +6.248243/−7.549994`, and `CYr/Cnr/Clr = +0.382447/−0.142153/+0.124960`. For the Stik they were `−0.0375/−0.4496/+0.1180`, `+1.977/−7.944`, and `+0.1500/−0.1354/+0.1086`.

The sampled α/β blend boundaries had no force jump at the tested ±0.01° offsets; the regular envelope test found finite reference coefficients throughout α −180…180° and β −90…90°, with maximum adjacent change 0.0213 per 0.1°. The Cartesian limit above is separate: angle-based coefficient continuity does not test continuity in the 3-D velocity vector at zero chord-plane projection.

The full-aircraft local-load CL peak differs from the declared `CL_max` on these two inputs (Avanti 0.889612 vs 0.85; Stik 1.104807 vs 1.10). I do not classify this as a defect: `aero.gd:7, 61-90` explicitly identifies `coefficients()` as the reference empirical curve rather than summed nonlinear surface loads, and `aircraft_data.gd:1413-1467` solves the labeled limit for that reference curve. The test `test_envelope.gd` validates this coefficient curve and its flight-speed behavior, not the aggregate local-surface peak.

## Focused checks and oracle note

Executed with native Godot `4.7.2.stable.official.ed1daf0bf`:

| Command script | Result |
| --- | --- |
| `res://tests/test_aero.gd` | 23 checks, 0 failed |
| `res://tests/test_envelope.gd` | 15 checks, 0 failed |
| `res://tests/test_envelope_integrity.gd` | 64 checks, 0 failed |
| `res://tests/test_damping_regimes.gd` | 20 checks, 0 failed |
| `res://tests/test_aero_flow.gd` | H4 20,000/20,000 passed; H12 byte-parity reported 1,556 differences across 20,001 comparisons, beginning on Avanti samples |
| `research/physics-audit-2026-10-14/aero/test_aero_flow_no_polar.gd` | Disposable copy with only `envelope.wing_polar` removed from both H12 models: H4 20,000/20,000 and H12 20,001/20,001 passed; D11j analytic strip moment passed |

The current Avanti catalog input enables `aero.wing_polar`; its loader warns that this experimental tabulated polar needs aircraft-specific post-stall review. The frozen `app/tests/aero_flow_reference.gd` H12 oracle predates that term and does not evaluate it. The unmodified parity failure therefore identifies a stale oracle for the enabled polar, not a separate live-load mismatch; the neutralized comparison isolates that difference. The original failure and neutralized reproduction logs are retained under `checks/`.

## Reproduction

From the repository root in PowerShell:

```powershell
$GodotAudit = 'C:\DEVELOPMENT\OpenRCsimulator\.tools\Godot_v4.7.2-stable_win64_console.exe'
& $GodotAudit --headless --path app --audio-driver Dummy --script 'C:\DEVELOPMENT\OpenRCsimulator\research\physics-audit-2026-10-14\aero\probe.gd'
& $GodotAudit --headless --path app --audio-driver Dummy --script res://tests/test_aero.gd
& $GodotAudit --headless --path app --audio-driver Dummy --script res://tests/test_envelope.gd
& $GodotAudit --headless --path app --audio-driver Dummy --script res://tests/test_envelope_integrity.gd
& $GodotAudit --headless --path app --audio-driver Dummy --script res://tests/test_damping_regimes.gd
& $GodotAudit --headless --path app --audio-driver Dummy --script res://tests/test_aero_flow.gd
& $GodotAudit --headless --path app --audio-driver Dummy --script 'C:\DEVELOPMENT\OpenRCsimulator\research\physics-audit-2026-10-14\aero\test_aero_flow_no_polar.gd'
```

The main raw output is `checks/corrected-probe.log`; focused check outputs are adjacent `.log` files. `checks/probe.log` is retained as the first probe run, but is superseded: its force-to-wind lift transform had the wrong sign and its CL values must not be used. The final probe includes pure-drag/pure-lift transform checks at α=30° and reports both as passing.

## Input and source identity

| File | SHA-256 |
| --- | --- |
| `app/data/aircraft/sebart_avanti_s_a200.json` | `74043c9bc1de35de066bc65b971e85f5e099173f2d9cccec065c6988abbb6b9d` |
| `app/data/aircraft/jensen_ugly_stik_60.json` | `5fe8ece91b7ebe92f304f764f0d50edc936ae5c4ab1d1c801cf20827ec1ee9b6` |
| `app/physics/aero.gd` | `cf034742d69332061eb9414ccd57f7d0b6cb6e1c2f17cc5ae39e70fe26655539` |
| `app/physics/air_data.gd` | `8c5f96b93e60638f01624d4871a41da07b8b464e1b30e3d79d3fbdb43f325ca2` |
| `app/physics/wing_polar.gd` | `fee5fe7c2f8b13f30e9275675ed421eb6c8a45d62d0d91958ed155b12b4db3be` |
| `research/physics-audit-2026-10-14/aero/probe.gd` | `21e4052fb39ed67d989a144dd9257f1dbf8f686d148d696287b2d1c55be1baf0` |

The Stik evidence remains limited by its borrowed/estimated attached derivatives and stall limits, which existing AS-00 documentation already flags. The Avanti uses an experimental tabulated NACA 0015-derived proxy rather than an identified Avanti section polar. Neither software checks nor this extreme-flow discontinuity probe provide physical flight validation. `aero.gd:5-8` also records the local-element approximation and the absence of dynamic-stall memory and propwash.
