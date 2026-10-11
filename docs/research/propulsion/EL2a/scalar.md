# EL2 battery oracle notes

2026-10-11 · **Status: synthetic numerical qualification complete; no hardware calibration. Step prefix: EL.**

## Exact source-off discharge

For a pack with remaining charge `C` coulombs and capacity `Ccap = 3600 × capacity_Ah` coulombs, a disabled motor leaves `Ipack = Iaux` until exhaustion. Therefore `C(t) = C0 − Iaux t` and `t* = C0/Iaux`. With `OCV(C) = Vlow + (Vhigh − Vlow) C/Ccap`, the exact chemical energy removed is

`Echem = integral_C*^C0 OCV(C) dC = Vlow(C0 − C*) + (Vhigh − Vlow)(C0² − C*²)/(2 Ccap)`.

Pack heat is `H = Rpack Iaux² t*`; terminal energy is `Eterminal = Echem − H`. The synthetic source-off fixture starts with 9 C remaining, `Iaux = 13 A`, so exhaustion occurs at 0.6923076923076923 s. At 120/240/480/960 Hz this falls inside the final tick, with that tick's duration reported separately from the event time. The expected endpoint is exactly zero charge and SOC; one post-event step must add no current, terminal energy, or pack heat.

This fixture starts at 1500 rpm and keeps the motor disabled. It also checks that bearing loss continues while the battery supplies only the auxiliary load. In the one-axis no-load rotor model, `Omega_dot = −kt I0 Jlocked/(Jrotor Jcarrier)` and `body_rate_dot = −Jrotor Omega_dot/Jlocked`; total axial angular momentum remains constant. The chosen start speed keeps the rotor turning through the battery event, so the result does not combine stop and exhaustion roots.

## Smooth coupled reference

The second fixture uses one affine OCV curve over SOC `[0,1]`, with no internal OCV knot. At each independent SciPy stage it solves

`Im = max((d(OCV − Rpack Iaux) − E)/(Rm + d²Rpack), 0)`, `Ipack = d Im + Iaux`, and `Vbus = OCV − Rpack Ipack`.

The one-axis body/rotor equations are derived from total angular momentum and motor torque: `Omega_dot = Jlocked Qsource/(Jrotor Jcarrier)`, `body_rate_dot = −Jrotor Omega_dot/Jlocked`, and `Qsource = kt(Im − I0)`. The battery state derivatives are `Cdot = −Ipack`, `Eterminal_dot = Vbus Ipack`, and `Hdot = Rpack Ipack²`. SciPy 1.11.4 DOP853 runs with `rtol=2e−13`, explicit per-state absolute tolerances, and `max_step=0.001 s`. A 201-point dense check confirms positive RPM/current/torque, positive charge, and no event branch crossing.

The chemical budget is evaluated analytically from endpoint charge, not integrated by the reference solver. The recorded DOP853 endpoint is `Omega=714.5737397156753 rad/s`, `body_rate_x=−17.36434349289185 rad/s`, remaining charge `3055.5536366803217 C`, terminal energy `52.42218062910169 J`, and pack heat `2.1956264603862827 J`. The reference chemical-energy residual is `−4.82e−11 J`; axial momentum drift is `1.13e−16 kg·m²/s`.

The focused Godot probe passed against the production modules (installed source hashes match the recorded evidence). Exhaustion time error across the four rates stayed below `6.1e−13 s`; the auxiliary terminal-energy error stayed below `7.8e−11 J`, and the post-event test observed zero battery/motor current while the source-off `0.0119366 N·m` bearing torque remained. Event end-of-tick fractions were about `0.0769`, `0.1538`, `0.3077`, and `0.6154` of a tick. In the smooth run, 120 Hz endpoint errors were `1.34e−6 rad/s` in relative rotor speed, `3.34e−8 rad/s` in body rate, `7.61e−9 C` in charge, `5.78e−5 J` in terminal energy, and `5.78e−5 J` in pack heat; each was within its own budget. Momentum drift stayed below `1.2e−16 kg·m²/s`. Higher-rate state comparisons and source hashes are in the generated evidence JSON.

At 120/240/480/960 Hz, the probe compares each state against its own absolute budget. Refinement orders are emitted as diagnostics; they are not a pass condition. These figures characterize only a synthetic single-segment OCV, direct-drive motor, and principal-axis rotor/body case. They do not establish aircraft behavior, real pack limits, cell imbalance protection, or measured hardware parameters.

## Reproduction

The verifier pins NumPy 1.26.4 and SciPy 1.11.4. `--oracle-only` writes the independent reference without launching Godot; the integrated command will also run the standalone Godot probe and hash the production files it exercises. No full application suite is part of this isolated numerical qualification.

```sh
python3 research/propulsion/el2/verify_battery.py --godot "$(app/get-godot.sh)" --app app --output /tmp/el2-scalar.json
```

[Machine-readable evidence](scalar-evidence.json) records the per-state budgets, event residuals and source hashes. The pinned environment is [EL1a-R2 requirements](../../../../research/propulsion/el1a-r2/requirements.txt).
