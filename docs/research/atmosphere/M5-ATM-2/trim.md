# M5-ATM-2 trim density

**Status:** Trim density and engine charge inputs are implemented and verified; field and session wiring is tracked by the atmosphere owner.

`Trim.solve` accepts total air density after the existing arguments. Its default is the sea-level literal from `Air.RHO_SEA_LEVEL`. The Newton residual, steady RPM calculation and returned thrust evaluation receive the same density. Scenario adapters append the same `1.225 kg/m³` default. The requested `V` stays true airspeed; the trim solver does not convert it to equivalent airspeed.

The optional engine charge ratio is a separate input after density. It defaults to `1.0` to preserve legacy engine torque for existing callers; atmospheric session code can pass the dry-air correction explicitly. Invalid density and invalid charge ratios return a numerical failure before the solver evaluates loads.

The focused check uses the Ugly Stik at `σ = 0.78`. At `V = 15 m/s`, sea-level dynamic pressure is `137.8125 Pa`; density-scaled speed `15 / √0.78 ≈ 16.986 m/s` produces the same dynamic pressure. The solved glide keeps angle of attack and glide angle, matches total loads within `1e-8`, and both cases meet the six-axis residual tolerance. At fixed TAS, the Stik glide solves at a higher alpha under lower density. A 5 m/s level request at reduced density is refused with a reason. A P-51 case confirms that changing the explicit engine charge ratio changes solved throttle and that the scenario adapter forwards it.

The report establishes trim API plumbing and numerical consistency for these cases. It does not validate field weather, the atmosphere model, or every aircraft's low-density operating envelope.

**Reproduction:** `$(app/get-godot.sh) --headless --path app --check-only --script res://tests/test_trim_density.gd`, then the same command without `--check-only`. The focused test reports 35 checks and 0 failures.

**Code:** [trim solver](../../../../app/physics/trim.gd), [scenario adapters](../../../../app/sim/scenarios.gd), [density regression](../../../../app/tests/test_trim_density.gd).
