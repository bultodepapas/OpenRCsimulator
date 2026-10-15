# R04: bounded runway equilibrium evidence

Evidence captured 2026-10-14 with Godot 4.7.2 on the two audit aircraft: Jensen Ugly Stik 60 (`jensen_ugly_stik_60.json`) and Sebart Avanti S A200 P100RX (`sebart_avanti_s_a200.json`). This documents numerical/software verification of the current runway-start solver. It is not physical validation against measured aircraft or runway data.

## Solver contract

`GroundStart.solve()` is a pure candidate search. Stage 1 solves engine-off support equilibrium for down position and roll/pitch. Stage 2 solves all six idle linear/angular accelerations while searching north/east/down placement and local rotation; it retains the exact support anchors. Wind participates in both residuals. The local characteristic length is the maximum norm of a contact position, floored at 0.1 m.

The bounded solver uses dimensionless variables/residuals, a finite-difference Jacobian, branch-aware feasible stencils, damped descent, and line search. Its acceptance targets are scaled residual `1e-9` and raw acceleration residual `1e-11`; the shared cap is 4,096 residual evaluations, with at most 64 iterations per stage and 8 backtracking trials. The idle stage also enforces horizontal placement within 10 mm and yaw change within 0.1°. Every support contact must retain positive compression and normal load, remain below its compression limit, have a valid wheel heading, retain its anchor, and satisfy the longitudinal hold and lateral friction bounds. Failure returns no candidate state. `numerical_unresolved` means the bounded search did not find an accepted root; it does not prove that an equilibrium is impossible.

When `environment_at_state` is supplied, its positive finite density is sampled at each trial state for both stages. A callback error rejects that evaluation without falling back to the legacy scalar density. `test_ground_start_environment.gd` passed 10/10 checks: 116/116 residual queries followed the trial-state height, spanning 0.00085507954639 m down and 0.00017101590928 kg/m³ density. The callback-based final acceleration residual was `1.69e-12`; using the initial scalar density instead gave `9.92920641e-06` for that same state. An injected atmosphere-domain error rejected without publishing a partial candidate and stayed within the evaluation cap.

## Preserved-Newton force-law 2×2

The controlled 2×2 uses the original `_newton` solver copied from the untouched baseline and a disposable shadow application. Each cell covers both aircraft at wind-from 0° and magnitudes 0, 0.5, 1, 1.5, and 2 m/s (10 trials). The outcome counts were:

| Aero source | Turbine source | Converged | Unresolved cases |
| --- | --- | ---: | --- |
| Original | Original | 7/10 | Stik 1 m/s; Jet 1 and 1.5 m/s |
| Original | F02 signed intake momentum | 9/10 | Stik 1 m/s |
| Final R02 | Original | 10/10 | None |
| Final R02 | F02 signed intake momentum | 10/10 | None |

Within this tested grid, the final aero source alone removed all of the old solver's convergence failures. F02 improved the original-aero cell from 7/10 to 9/10 but did not remove the remaining Stik case. This isolates a solver-convergence effect for this matrix; it does not establish the accuracy of either model against flight measurements.

| Source | SHA-256 |
| --- | --- |
| Untouched baseline aero | `CF034742D69332061EB9414CCD57F7D0B6CB6E1C2F17CC5AE39E70FE26655539` |
| Untouched baseline turbine | `1B9559219E1F3542821C6C56C7C62A9B3CBF79D35668175D6C8BEE1EF87B8E2C` |
| Final R02 aero | `FED08E735494B6D2597F639CCA118D84C978F75828811F0D09968BFC67A85BE5` |
| Immutable F02 turbine candidate | `0603A1C38C9F8350F12C5E212489F5180B6B96FC95504A97BB428D57BDE03DC5` |

The machine-readable identities and per-cell logs are `r04-2x2-source-identities.json` and `old-newton-2x2-*.log`. The runner restores the shadow's final-aero/F02-turbine pair in a `finally` block; the captured R00 baseline remains untouched.

## Real FlightSession wind sweep

`ground_start_session_sweep.gd` configures the real `FlightSession`, selects runway start and the default field, disables gust/turbulence, and uses neutral controls. It records solver status, residuals, pose/contact diagnostics, and then advances successful starts for 480 ticks at 240 Hz (2 seconds). The base matrix has 22 cases: eight directions at 1.5 m/s plus 0, 1, and 2 m/s from north, for both aircraft. The seam matrix adds eight directions at 1.5 m/s for both aircraft: 359.999°, 0.001°, 359°, 1°, 179.999°, 180.001°, 179°, and 181°.

Across 38 cases, Jet starts converged in 19/19; Stik starts converged in 18/19. All 32 direction cases at 1.5 m/s, including the seam angles, converged. The single exception was Stik at 2 m/s from 0°:

| Field | Observed value |
| --- | ---: |
| Outcome | `numerical_unresolved`; bounded line search found no feasible descent step |
| Residual evaluations / stage-2 iterations | 213 total / 7 |
| Final acceleration residual | 0.0215291083 m/s² (largest linear component) |
| Last feasible horizontal pose change | 7.8404 mm (east component 7.840008 mm) |
| Last feasible yaw change | −0.0999401°; configured limit 0.1° |
| Minimum reported anchor-friction margin | 4.746575 N |

The final feasible state still had all three contacts loaded, and the reported anchor-friction margins were positive. This is a placement-boundary numerical nonconvergence, not evidence of contact infeasibility or a physical 2 m/s crosswind limit. The requested start was not accepted.

Every accepted case completed all 480 ticks without crash or simulation fault. For the Stik, the largest accepted endpoint speed was `2.21404423e-05 m/s` and the largest horizontal drift was `4.00606927e-05 m` (0.0401 mm). For the Jet, the maxima were `1.80852391e-07 m/s` and `5.68618745e-06 m`. Drift is the horizontal distance between the state immediately after accepted runway reset and the state after 480 successful ticks; speed is the norm of final NED velocity. The largest accepted solver residual norms recorded by the session harness were `5.46444e-12` for Stik and `8.66851e-12` for Jet. These norms mix linear and angular acceleration components as defined by the solver and are software equilibrium residuals, not measured force uncertainty.

In the 16-case seam sweep, all starts converged and all 480-tick stationarity runs completed without faults. The largest absolute achieved-versus-requested heading correction was 0.0868973° for Stik and 0.0183759° for Jet, both within the 0.1° placement cap. The wind conversion changed the east component sign across 359.999°/0.001° while retaining the expected nearly-north flow, so these cases exercise angle wrapping around both 0° and 180°.

## Independent force/moment reconstruction and bounds

The direct magnitude probe independently recomputed net body force and moment from aircraft loads, gravity, and ground loads for 13 accepted equilibria: nine of the ten nominal-density 0–2 m/s cases and four accepted gravity/density variants. Maximum net residuals were `2.44354259e-11 N` and `6.16576235e-12 N·m`. The independent `m*a` and `J*alpha` reconstruction differences were at most `2.18401493e-14 N` and `8.07793567e-28 N·m`. Anchors persisted across accepted direct-probe cases. These checks verify force/torque accounting and rigid-body residual consistency for stationary candidates in the software path. Since these candidates have zero body rates, this measurement does not test nonzero-rate gyroscopic behavior; it also does not validate aerodynamic or tire coefficients physically.

For the default 0–2 m/s direct-probe magnitude grid, 9/10 cases converged; the same Stik 2 m/s case was unresolved. Both aircraft converged at 2 m/s with the low pair (`g=9.0 m/s²`, `rho=0.8 kg/m³`). At the high pair (`g=10.5 m/s²`, `rho=1.4 kg/m³`), Jet converged and Stik remained unresolved after 165 evaluations. At 20 m/s from north, both were bounded as `numerical_unresolved` (Stik residual 21.8848 m/s², Jet 9.01215 m/s²); this is an out-of-range solver stress case and says nothing about real aircraft wind limits. Zero-density Jet input produced a nonfinite initial residual and was rejected; zero density is not an atmospheric validation condition. A NaN runway coordinate was rejected as `invalid_input` before solving.

Focused integrated regressions passed: ground-start integrity 254/254 checks, retractable-gear ground behavior 26/26, runway transaction/failure atomicity 32/32, and state-dependent environment callback 10/10. Logs are retained in `../R04-integrated-checks/` and this directory's `test-ground-start-environment.log`. These checks verify software contracts and do not raise the physical-validation status.

## Reproduction and source identity

From the repository root in PowerShell, using `.tools/Godot_v4.7.2-stable_win64_console.exe`:

```powershell
& '.tools/Godot_v4.7.2-stable_win64_console.exe' --headless --path app --script 'C:/DEVELOPMENT/OpenRCsimulator/app/tests/test_ground_start_environment.gd'
& '.tools/Godot_v4.7.2-stable_win64_console.exe' --headless --path app --script 'C:/DEVELOPMENT/OpenRCsimulator/docs/research/physics-audit-2026-10-14/remediation/R04/ground_start_session_sweep.gd'
& '.tools/Godot_v4.7.2-stable_win64_console.exe' --headless --path app --script 'C:/DEVELOPMENT/OpenRCsimulator/docs/research/physics-audit-2026-10-14/remediation/R04/ground_start_session_sweep.gd' -- --seams
& '.\docs\research\physics-audit-2026-10-14\remediation\R04\run_force_2x2.ps1'
```

The session sweep logs are `session-direction-magnitude-sweep-diagnostics.log` and `session-wind-seam-sweep.log`; the 2×2 logs are listed above. The direct force/moment and gravity/density probes are retained in `bounded-solver-magnitude-branch-safe-f02-final-aero.log`.

| Current source at final session sweep | SHA-256 |
| --- | --- |
| `app/physics/ground_start.gd` | `DDA14919AE3C5B6D9AC094E287F2DDA10D1E78B61BF14510E837BD0AB227307F` |
| `app/sim/flight_session.gd` | `303ADE91ADFE18FCE11364D5E965B8554A37FF17CA72D8CF23AC8B83E11A9B96` |
| `app/physics/aero.gd` | `FED08E735494B6D2597F639CCA118D84C978F75828811F0D09968BFC67A85BE5` |
| `app/physics/turbine.gd` | `A7577B8D2DDFE7DAEC69CF2992E8C566688F5B6C89CF6461C5B462ABEB1CA702` |
| `app/physics/dynamics.gd` | `5D4D8EA9AE713F36DC977F3ED8DD451BDCC46278E3C68DB9F72B2B426046B7F1` |
| `app/physics/wind_config.gd` | `7139ABA2FCE0194C4C740A7DAABAF6BCA1C6F81C170D451FA3F208E20037CA12` |
| `app/physics/atmosphere.gd` | `9E1BE6DEF471318DCEB55B561C13D0C043A7F132F78BD125F0A570DFB003F369` |
| `app/physics/wind_field.gd` | `DB80F80B47DBEC99A93E7392DE339E63E435B8A9FCFA67F750FA8DBB0A3DEC4A` |
| `app/data/fields/default.json` | `A4908850C54F183E8D479623384AE249E2024A893B3FB8288030FD69EB20069D` |
| Stik aircraft data | `5FE8ECE91B7EBE92F304F764F0D50EDC936AE5C4AB1D1C801CF20827EC1EE9B6` |
| Jet aircraft data | `74043C9BC1DE35DE066BC65B971E85F5E099173F2D9CCCEC065C6988ABBB6B9D` |
| Session sweep script | `8E8A504463C262A31814D918E0B3B0D4CC96295DE3A358C931B1A3B680AA34A0` |

The real-session sweep used the current `A757…` turbine and current `Dynamics` sources. The old-Newton 2×2 and direct magnitude probe used the explicitly identified immutable F02 turbine candidate. The force/moment probe ran in the disposable shadow with `GroundStart` hash `DDA14919AE3C5B6D9AC094E287F2DDA10D1E78B61BF14510E837BD0AB227307F`, final aero hash `FED08E735494B6D2597F639CCA118D84C978F75828811F0D09968BFC67A85BE5`, F02 turbine hash `0603A1C38C9F8350F12C5E212489F5180B6B96FC95504A97BB428D57BDE03DC5`, and untouched-baseline `Dynamics` hash `313851831BAA6CCF9769A2A4A28220DE96650FF3B64C60DC5275857DA89806D3`. Current `Dynamics` hash `5D4D8EA9AE713F36DC977F3ED8DD451BDCC46278E3C68DB9F72B2B426046B7F1` was used by the later FlightSession sweep, not by the saved force/moment probe. Therefore the independent force/moment residuals verify the recorded shadow snapshot and must not be read as a force-balance measurement of the later F07 propulsion coupling. The 2×2 is controlled source isolation; the session sweep records integrated runtime stationarity.
