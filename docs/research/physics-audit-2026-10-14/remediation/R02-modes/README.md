# R02 mode-reference update

This note explains the three Jensen Ugly Stik 60 regression-band updates in [`test_modes.gd`](../../../../../app/tests/test_modes.gd). The values are software references for the current equations; they are not measured flight modes and do not establish physical accuracy. The wider R02 scope and its limitations are in the [audit](../../README.md) and [R01/R02 evidence](../R01-R02/README.md).

## Why three bands changed

R02 changed the local section/load and dynamic-wake law. The current model declares its load-law and wake units as `section-plane-source-weighted-wake-velocity-v2` and m/s, respectively ([`aero.gd:20`](../../../../../app/physics/aero.gd#L20), [`aero.gd:21`](../../../../../app/physics/aero.gd#L21)). Its instantaneous tail-wake driver is the equal-area mean of section speed times lift coefficient, `mean(Vp·CL)`, not a dimensionless wing `CL` ([`aero.gd:641`](../../../../../app/physics/aero.gd#L641), [`aero.gd:643`](../../../../../app/physics/aero.gd#L643)). The model maps that velocity to downwash with `atan2(gain·wake_velocity, tail_plane_speed)` ([`aero.gd:259`](../../../../../app/physics/aero.gd#L259)).

For the Timber/Jensen lagged-tail path, `FlightModes.analyze` appends this m/s driver as its ninth state, computes its target from the same section law, and uses `dU_L/dt = (U_L,target − U_L)·V/l` ([`flight_modes.gd:23`](../../../../../app/physics/flight_modes.gd#L23), [`flight_modes.gd:43`](../../../../../app/physics/flight_modes.gd#L43), [`flight_modes.gd:52`](../../../../../app/physics/flight_modes.gd#L52)). `Aero.loads` uses the held state in the tail load, while the session advances the same state with the corresponding first-order response ([`aero.gd:182`](../../../../../app/physics/aero.gd#L182), [`flight_session.gd:2825`](../../../../../app/sim/flight_session.gd#L2825), [`flight_session.gd:2828`](../../../../../app/sim/flight_session.gd#L2828)). Therefore the old values—recorded before R02—are not a valid regression oracle for those derivatives. The shift is the expected consequence of the changed model definition; it is not evidence that the new modes better match a real Stik.

Only these three old values exceeded the existing 3% band:

| Mode reference | Previous band center | Independent R02 value | Shift |
| --- | ---: | ---: | ---: |
| 10 m/s phugoid damping ratio | 0.08278454 | 0.068793816 | −16.90% |
| 10 m/s signed spiral eigenvalue | 0.45051607 1/s | 0.486933537 1/s | +8.08% |
| 15 m/s phugoid damping ratio | 0.30299182 | 0.286539267 | −5.43% |

`test_modes.gd` updates those centers only ([`test_modes.gd:30`](../../../../../app/tests/test_modes.gd#L30), [`test_modes.gd:35`](../../../../../app/tests/test_modes.gd#L35)); it retains the same `TOL = 0.03` ([`test_modes.gd:40`](../../../../../app/tests/test_modes.gd#L40)). Every other previous modal center remained within that band. The existing 15 m/s nonlinear perturbation check still passes: with the wake lag it predicts the peak pitch-rate response within 0.70% of its peak; the quasi-static comparison differs by 52.6%.

## Independent calculation

`manual_mode_probe.gd` constructs the trimmed state and held wake state, then composes each derivative from `Air.compute`, `Aero.loads`, `Propulsion.loads`, and `RigidBody.derivative`. It does not call `FlightModes` or `Linearize` for that derivative/Jacobian path. RPM, controls, density, and gravity are held at the converged trim; rotor momentum is included. It central-differences all nine state components at `h = 1e−5`, `1e−6`, and `1e−7`. The script separately emits the production `FlightModes` matrix as a comparison value. `mode_reference.py` runs this probe and uses SciPy `eigvals` on the same stated 5×5 longitudinal `[u,w,q,theta,U_L]` and 4×4 lateral `[v,p,r,phi]` diagonal projections used by `FlightModes` ([`flight_modes.gd:16`](../../../../../app/physics/flight_modes.gd#L16), [`flight_modes.gd:17`](../../../../../app/physics/flight_modes.gd#L17)). Frequency is the natural frequency `sqrt(real²+imag²)/(2π)`, matching the in-engine classifier.

At `h = 1e−6`, the manually composed Jacobian and production Jacobian had zero difference in all three cases. SciPy's modal metrics differed from the production classifier by at most `3.1e−13` in these runs. Across the three finite-difference steps, the largest infinity-norm Jacobian difference versus `h = 1e−6` was `3.83e−6` at 10 m/s, `4.54e−7` at 15 m/s, and `5.88e−7` at 25 m/s. The changed references are numerically stable under this step-size sweep.

| Speed | Trim α | RPM | Held wake | SP `Hz / ζ` | Phugoid `Hz / ζ` | Roll τ | Dutch roll `Hz / ζ` | Spiral λ | Wake root |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 m/s | 11.376860° | 3956.591 | 9.366570 m/s | 0.920537 / 0.810971 | 0.164259 / 0.068794 | 0.071670 s | 0.562472 / 0.300133 | +0.486934 1/s | −11.050815 1/s |
| 15 m/s | 4.184144° | 5155.658 | 6.105285 m/s | 1.180427 / 1.039523 | 0.089863 / 0.286539 | 0.051323 s | 0.744537 / 0.248572 | +0.076933 1/s | −15.399403 1/s |
| 25 m/s | 0.658501° | 8476.966 | 3.683913 m/s | 1.873700 / 1.108456 | 0.051126 / 0.895408 | 0.030555 s | 1.193437 / 0.234250 | +0.027510 1/s | −25.178326 1/s |

The complete 9×9 matrices, roots, trim records, step-size comparisons, current production comparison, and SHA-256 inputs are in [`mode-reference-results.json`](mode-reference-results.json). The matrices are projections of this model and do not include control-actuator, RPM, or other states that the mode routine freezes.

## Reproduction and controls

From the repository root, run:

```powershell
python docs/research/physics-audit-2026-10-14/remediation/R02-modes/mode_reference.py
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_modes.gd
```

The Python probe used NumPy 2.4.6 and SciPy 1.17.1. The current Godot mode test reports **42 checks, 0 failed** with these three references.

As a pre-R02 control, the immutable R00 app snapshot with its original test references reported **42 checks, 0 failed**. Before updating the three centers, the current R02 app with the old test reported **42 checks, 3 failed**, exactly the 10 m/s phugoid ζ, 10 m/s spiral λ, and 15 m/s phugoid ζ comparisons. This control confirms that the update is localized to the behavior intentionally changed by R02; the other regression bands and the nonlinear lag-response check remain active. It is not a corrupted-law mutation or an external physical validation.

The reference script records hashes of the aircraft model, relevant aero/trim/rigid-body modules, the mode test, and the probe in its JSON output. These checks establish reproducibility of this software comparison only. Empirical mode validation still needs flight or wind-tunnel evidence for the actual aircraft and configuration.
