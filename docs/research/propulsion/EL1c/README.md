# EL1c — Electric source, propeller balance and trim

2026-10-10 · **Status: focused software checks pass; integrated regression recorded under EL1d. Step prefix: EL.**

The normalized `electric_prop` source uses the existing propeller Ct/Cp interpolation, axis, aerodynamic load and locked-inertia coupling. `has_shaft()` retains its combustion-layout meaning; `has_rotor_dynamics()` includes the electric source. No aircraft ID enters propulsion physics. Legacy lag, combustion shaft and turbine arithmetic remains on its existing paths.

`steady_operating_point()` returns a structured success/failure, residual and local torque slopes. A bounded geometric search includes propeller-table knots and the current-cutoff speed. It can find airflow-driven equilibria above Kv × voltage; that electrical reference is not an overspeed governor. Acceptance requires a finite torque residual and restoring slopes on both sides. The existing float-returning `steady_rpm()` wrapper returns NaN on failure. Electric trim uses bounded duty probes and reports failed equilibria without fabricating a start.

The search is not a proof of uniqueness or complete detection of arbitrarily narrow multiple-root branches. It qualifies the declared fixtures and fails explicitly when it cannot establish a stable operating point. Propeller extrapolation remains the existing law, not measured coverage.

Proof: `test_electric_propulsion.gd` passes **20 checks**: independent constant-Cp quadratic, restoring residual, density effect, windmilling above KvV, unbracketed/cutoff/unstable negative controls, source-off loss, sub-1-RPM coast, breakaway, source dispatch and powered six-axis trim. Both canonical synthetic aircraft also trim and fly in [EL1d](../EL1d/README.md) and [EL1e](../EL1e/README.md).

```sh
"$(app/get-godot.sh)" --headless --path app --script res://tests/test_electric_propulsion.gd
```

The initial review caught a legacy `rpm <= 1` derivative hold that prevented electric stopping; it now applies only to combustion. The electric source reaches zero through the session's event solver. These results verify software; they do not identify motor parameters or validate a stock Timber propeller.
