# EL1d — Coupled electric flight, stopping and replay

2026-10-10 · **Status: focused, numerical and full app regressions pass; the 500 µs/tick performance target is missed. Step prefix: EL.**

Electric aircraft automatically select the existing coupled rotor/body RK4 route. An explicit split-integrator request is refused. Propeller loads use stage RPM, air-relative velocity and field density; the electrical source has no density correction, separate Node clock or added RPM lag. Accepted continuous RPM is mirrored into the existing render/auxiliary slot. Invalid evaluations roll back body, shaft, auxiliary state, modes and tick together.

**2026-10-23, EL1d-R1:** electric propeller loads and shaft torque now include the hub's rigid-point velocity during rotation. [Defect, regression and recorded-flight comparison](hub-inflow-2026-10-23/README.md).

## Rest boundary and supported numerical envelope

`electric_stop.gd` localizes a downward zero-speed crossing within the tick, applies a tiny momentum-preserving projection and advances the remaining time from rest. Negative trial RPM uses an explicitly declared moving-side continuation only for localization; no negative endpoint is committed. At exact rest, bounded static bearing friction either holds the relative shaft, permits forward breakaway or refuses unsupported reverse departure. Body acceleration participates in that decision. An independent review exposed missing moving-side friction during body-driven forward breakaway; a gyroscopic session fixture now guards it.

Localization is bounded to 128 segments and 60 bisection iterations, with 1e-12 s and 1e-7 RPM numerical tolerances. Qualification covers monotone stopping segments and shared-endpoint events. This is not a general detector of arbitrarily fast hidden oscillatory events. Source-off coasting retains bearing loss; the existing stopped-propeller aerodynamic cutoff remains, so this work does not validate dead-stick drag or air-driven restart from rest (G1d).

Launch also requires `dt*kt²/(R*Jr*delta) <= 0.25`, where `delta = 1 − Jr*aᵀ*Jlocked⁻¹*a`. This bounds the active-current source's explicit mechanical eigenmode and refuses excessively stiff configurations before trim. It does not qualify propeller, aerodynamic or contact stiffness. The two provided configurations are qualified at 240 Hz; new aircraft still need refinement evidence.

## State and observation contracts

- Native-byte checkpoint **v5** records the electric law, coupled state, source-enabled mode, inputs and complete weather/RNG boundary. Fresh-owner replay is exact on the pinned executable. Wrong law, configuration or negative RPM is refused without changing the active session.
- CSV **v7** adds enabled mode, effective duty, bus voltage, equivalent motor current, drive-input current, standalone source torque and shaft/copper/rotational powers. Electrical values describe the accepted endpoint with that tick's input/mode; aerodynamic loads retain the existing k1 timing. Motor current is not phase RMS current, and drive-input current omits receiver/servo consumption.
- Source torque is the standalone motor-port value. The body-dependent bearing constraint at exact relative rest is enforced by the coupled solve and is not a separate CSV torque channel. Its relative shaft work is zero there.
- The recorder refuses missing, nonfinite or mismatched endpoint samples and mixed electrical/combustion metadata. Existing v3–v6 readers retain their format boundaries. Weather and atmosphere columns compose with v7; no old version number is reused.

## Proof

| Check | Result |
| --- | --- |
| Stop solver | 37 checks: exact/inside-step event, no duplicate rest event, restart, tilted-axis momentum projection, malformed derivatives, bounded unsupported motion |
| Real session | 86 checks: both trims, stop/restart, static and forward/reverse body-driven breakaway, pause/reset, independent owners, fault rollback, checkpoint replay, trace negative controls, turbulent/hot-high replay and source stiffness refusal |
| Independent scalar motor/rotor reference | DOP853 plus analytic momentum/work equations; 120/240/480/960 Hz angular-speed errors 1.437e-3 / 8.251e-5 / 4.943e-6 / 3.025e-7 rad/s; observed orders 4.12 / 4.06 / 4.03 |
| Scalar budgets and stop time | Momentum drift below 1e-13 kg·m²/s; electrical energy residual below 2e-12 J; coarsest kinetic-work residual 3.163e-4 J decreases with refinement; analytical stop 0.367566340470006 s, maximum timing error 4.648e-13 s |
| Real-session 0.5 s duty transient | 120/240/480/960 Hz versus 1920 Hz; at 240 Hz maximum body-component errors 2.172e-7 / 1.857e-7 in component units, RPM errors 2.310e-6 / 6.004e-7 for 4S/6S |
| Product and flight | [Eight 30-second flights](../EL1e/README.md), [real input/FPS/Linux-package proof](../EL1e/product.md) |
| Full application | `app/test.sh` exits 0 before and after integration; existing golden flights and model contracts pass; four legacy aircraft files remain byte-identical |
| Clean checkout | Fresh clone plus the exact implementation, without the original `.godot` cache: import, 43 data/86 session/6 input checks and both real-app traces pass |

The scalar oracle independently formulates one principal-axis rotor/body equation; it excludes propeller/external moments and does not establish whole-aircraft order. Full-session comparisons bound each position/velocity/rate component at 2e-6 in SI units, quaternion components at 2e-7 and RPM at 1e-4 for this transient. They demonstrate convergence and bounded error, not fourth-order convergence of every sampled/switched subsystem.

Reproduce from the repository root:

```sh
"$(app/get-godot.sh)" --headless --path app --script res://tests/test_electric_stop.gd
"$(app/get-godot.sh)" --headless --path app --script res://tests/test_electric_session.gd
# Use the pinned NumPy/SciPy environment from EL1a-R2 for this independent oracle.
python3 research/propulsion/el1/verify_scalar.py --godot "$(app/get-godot.sh)" --app app --output /tmp/el-scalar.json
python3 research/propulsion/el1/verify_flights.py --godot "$(app/get-godot.sh)" --directory /tmp/el-flights
app/test.sh
```

[Verification manifest](verification.json), [full app log](app-regression.log), [baseline log](baseline-app.log), [scalar equations/fixture](scalar.md), [scalar evidence](scalar-evidence.json), [flight/refinement evidence](../EL1e/flights.json) and [clean-checkout evidence](clean-checkout.json) preserve the results. The full app run includes 1,342 electric checks; the additional real-input routes contribute 38 checks. All configurations are synthetic. Measured hardware accuracy, endurance and matched propeller coverage remain separate acceptance work.

## Performance: target missed

The Linux/i5-10500 profile matches the owner's [confirmed slowest target](../../simulation-state/H4-H5/README.md). Godot 4.7.2 measures complete `Simulation.step()` calls, including coupled loads and stop tracking. Each case warms 240 ticks, then runs 40 batches of 120 ticks, restoring the same warmed checkpoint outside the timer. Median averages ranks 20/21; p95 is nearest rank 38. These are headless batch averages, not rendered-frame percentiles or worst-case tick latency. [Raw batches and fingerprints](cost.json)

| Configuration/regime | Median µs/tick | p95 µs/tick |
| --- | ---: | ---: |
| Electric 4S, powered | 709.36 | 767.58 |
| Electric 4S, coast | 704.85 | 774.37 |
| Electric 6S, powered | 695.56 | 769.14 |
| Electric 6S, coast | 713.30 | 773.42 |
| Legacy Stik | 346.56 | 375.27 |
| Legacy Extra | 247.27 | 268.49 |
| Legacy P-51 | 469.94 | 515.92 |
| Legacy Avanti | 284.43 | 314.07 |

The separate electric source-call loop averages 12.00–12.52 µs/call; it cannot establish the source's whole-session incremental cost because the coupled path also changes integration and load sampling. Electric medians and p95 exceed **500 µs/tick**. Keep the development route experimental and Gate P open. These fixtures do not replace the wider fleet/regime/rendering matrix in [Gate P](../../simulation-state/Gate-P/README.md).

An isolated positive-RPM comparison disables only the event-step callback and checks complete checkpoint equality against ordinary RK4. This measures stop tracking overhead; removing the callback loses the stop-event guarantee and is not a production optimization. The [diagnostic script](../../../../research/propulsion/el1/bench_stop_overhead.gd) and [recorded output](stop-overhead.log) preserve that bounded experiment. The saved repeat gives tracked/direct medians of 741.01/717.28 µs powered and 782.96/747.69 µs coast, with exact matching checkpoints and no faults. Host variability is visible against the main timing run, but both direct medians still exceed the target. Removing roughly 24–35 µs of tracking does not close the gap or justify changing the physical stop solver.

```sh
mkdir -p /tmp/el-cost
"$(app/get-godot.sh)" --headless --path app --script "$PWD/research/propulsion/el1/flight_probe.gd" -- cost /tmp/el-cost
"$(app/get-godot.sh)" --headless --path app --script "$PWD/research/propulsion/el1/bench_stop_overhead.gd"
```
