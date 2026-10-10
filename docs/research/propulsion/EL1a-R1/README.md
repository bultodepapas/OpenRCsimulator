# EL1a-R1 — Twelve investigations to strengthen electric propulsion

2026-10-10 · **Status: research complete; recommendations incorporated into Electric Propulsion Plan revision 2.** No runtime, aircraft data, dependencies or physical calibration changed.

The owner requested at least ten carefully selected Internet investigations. These twelve address distinct decisions and failure modes in the [electric plan](../../../ELECTRIC-PROPULSION-PLAN.md). Each report identifies primary sources, their applicability, remaining unknowns and a concrete measurement or verification requirement. Source facts are separated from proposed project policy. Earlier EL1a sources were revisited where a closer reading exposed important limits; this is not a claim that every cited paper is newly discovered.

## Investigation and decision matrix

| # | Question and research | Change to the plan | Required evidence / owning step |
| --- | --- | --- | --- |
| 01 | [BLDC parameter conventions](01-motor-esc.md#01--what-do-kv-r-and-i0-mean-for-a-three-phase-motor): Infineon application note and measured motor identification | Define equivalent-port Kv/R/I0, winding/measurement conventions and temperature; distinguish motor-only from combined ESC fits. | Identification manifest and held-out current/torque; EL1b, EL5. |
| 02 | [Command, effective duty and current](01-motor-esc.md#02--is-throttle-command-the-esc-duty-and-current-in-el1a): experimental electric-drive models | Declare the initial ideal command mapping; do not infer current limiting from 70 A or add an unidentified RPM lag. | Synchronized command/electrical/RPM steps; EL1b–d, EL3/5. |
| 03 | [Coast, brake, freewheel and regeneration](01-motor-esc.md#03--what-does-zero-throttle-mean-on-the-selected-avian-70-a): exact Timber manual, Avian guide and TI topology | Read back exact ESC firmware/settings; generic Avian tables omit SPMXAE70E. State braking energy destination. | Matched off/brake modes, signed pack power; EL1f, EL3. |
| 04 | [Battery model order](02-battery.md#04--battery-model-order-and-identifiability): fixed-wing LiPo pulse/hysteresis study | Begin with OCV plus resistance; promote an RC state only when identifiable residuals warrant it. | Pulse/recovery fit and held-out traces across intended SOC/temperature/current; EL2a/b. |
| 05 | [Usable charge and energy](02-battery.md#05--usable-charge-energy-and-endurance): experimentally validated UAV pack discharge model | Integrate total pack current for SOC and voltage × current for energy; include auxiliary draw or label motor-only endurance. | Exact pack/load/cutoff and held-out flights; EL2a, EL6. |
| 06 | [LVC, weak cells and receiver supply](02-battery.md#06--lvc-imbalance-recovery-and-receiver-power): matched aircraft manual and Avian family limits | Separate transmitter alarm, ESC cutoff, recovery and BEC supply; do not invent weakest-cell sensing. | Exact-unit trip/recovery and receiver-rail measurements; EL3/6. |
| 07 | [Propeller RPM/Re coverage](03-propeller-validation.md#07--rpm-and-reynolds-number-dependence): UIUC tests and APC source classification | Preserve measured/computational provenance and RPM/Re/J domain; no stock Timber map inferred from another propeller. | Matched three-blade static/advancing-flow grid; G1a/b, EL1f/5. |
| 08 | [Stopped and windmilling drag](03-propeller-validation.md#08--stopped-and-windmilling-propeller-drag): NACA negative-thrust tests and small-UAS experiments | Treat locked, free-spinning and ESC-controlled states separately; finite stopped loads cannot come from a singular J lookup. | Exact installation drag/torque/RPM, including breakaway; G1d, EL1d/3. |
| 09 | [Installed transient identification](03-propeller-validation.md#09--installed-powertrain-torque-and-transient-response): calibrated small-aircraft stand and motor/prop transient study | Separate inertia, ESC behavior and observation delay; identify the torque measurement plane. | Calibrated steady loads plus synchronized steps and independently constrained inertia; EL1d/5. |
| 10 | [Numerical events and stability](04-numerics-telemetry-uncertainty.md#10--can-one-fixed-timestep-handle-stopping-cutoff-and-different-motors): LLNL solver guidance and FNC stability analysis | Define trial-state domain, event priority and stable equilibrium branch; bound the multi-model timestep envelope. | Stop/cutoff event-time refinement, unstable-root negative control, replay/rollback; EL1c/d, EL3. |
| 11 | [Telemetry meaning and timing](04-numerics-telemetry-uncertainty.md#11--does-a-telemetry-rpmcurrent-sample-mean-what-the-model-assumes): ArduPilot protocol/sensor documentation | Record electrical/mechanical RPM, current plane, cadence, filtering, missing samples and timestamp meaning. | Optical tachometer cross-check, scaling and delayed/dropped-sample fixtures; EL1d/5. |
| 12 | [Uncertainty and acceptance](04-numerics-telemetry-uncertainty.md#12--what-evidence-is-sufficient-for-the-10-and-15-targets): NIST uncertainty propagation/coverage | Preserve shared-input covariance; predeclare validation bins and absolute floors; allow an inconclusive outcome. | Independent validation observations and pass/fail/inconclusive report fixtures; EL5/6. |

## Integration order

1. **EL1b first:** explicit electric source kind, two synthetic motor/voltage configurations, measurement conventions and the ideal command-to-duty policy. The real Timber parameters remain unmeasured.
2. **EL1c/d next:** source dispatch, stable operating-point/trim solve, coupled rotor/body integration, stopping events, defined electrical sample time and complete replay. Reuse G2a/G2b; do not add a second RPM lag.
3. **EL1e/f:** synthetic flight/session proof, followed by the exact Timber loadout under TT-07–09. Read the SPMXAE70E configuration and obtain motor, inertia and stock-prop evidence alongside software work.
4. **EL2/3:** pack characterization, total-current accounting and identified cutoff behavior. Only measured residuals justify polarization, thermal/hysteresis or richer ESC modes.
5. **EL5/6:** independent static, transient and endurance validation with the revised uncertainty rule. Physical validation remains open even when software checks pass.

The existing [VAL-7a](../../validation/VAL-7a/README.md) and [VAL-7c](../../validation/VAL-7c/README.md) reducers, [G1a1 normalization](../G1a1/README.md), and [G1b1 coverage audit](../G1b1/README.md) are starting points. Their historical timestamp and uncertainty contracts must be extended explicitly before new electrical/filtered/coupled-stage data can be accepted.

## Evidence boundary and checks

The reference remains **EFL105250B, 4S 3200 mAh pack class**, selected after the owner delegated the choice. [Exact hardware and outstanding measurements](../EL1a/timber-reference.md). No sales ranking, matched stock-prop curve, fitted Timber winding resistance, verified ESC defaults or real endurance result is established by this research.

[Documentation verification](verification.json) records the twelve numbered questions, source-link inventory, local-link/anchor checks, whitespace checks and unchanged EL1a code hashes. Small algebra checks cover the newly documented auxiliary-current sag equation and RPM/uncertainty examples only. These do not verify their future runtime integration. Godot regression tests were not rerun for this documentation-only revision; the [previous EL1a proof](../EL1a/README.md) retains its original scope.
