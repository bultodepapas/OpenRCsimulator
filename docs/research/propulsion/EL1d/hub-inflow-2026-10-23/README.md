# EL1d-R1 — Electric propeller hub inflow

2026-10-23. Confirmed kinematic defect repaired; software evidence only. Native Windows, Godot `4.7.2.stable.official.ed1daf0bf`, float64, 240 Hz. No aircraft coefficients or golden flights were changed.

## Defect and correction

Electric propeller loads and the coupled shaft used air velocity at the fixed body datum even when the offset propeller hub moved differently during rotation. Explicit glow propulsion already included that point velocity. For spatially uniform wind, the required velocity is `v_hub,air = v_datum,air + omega × r_hub`, with the authored aft/right/up offset converted to forward/right/down. This follows the [University of Illinois rigid-body point relations](https://mechref.engr.illinois.edu/dyn/rkg.html#rkg-er), accessed 2026-10-23. It requires no fitted correction factor.

The repair applies hub flow consistently to electric thrust, torque and the shaft balance. The v2 electric propeller schema does not permit `slipstream`; an attempted electric-wash fixture was rejected as an unknown field. The final patch therefore leaves slipstream and wash transport unchanged and does not expand the schema. Legacy prescribed-fuel propeller and explicit glow/turbine laws retain their existing conventions. The generic simulation kernel is unchanged.

`electric-propeller-local-hub-inflow-v1` is included in the electric configuration hash and trace metadata. An old native checkpoint cannot silently resume under the new law. State layout and the motor/ESC constitutive law are unchanged; explicit candidate replay can reuse admissible body/internal initial states.

The independent synthetic regression sets body rates to `[1.5, 6, 4] rad/s` and an off-axis propeller offset to `[-0.414176, 0.08, 0.11] m` in aft/right/up coordinates. These are test inputs, not a proposed aircraft installation. Before repair:

| Mode | Expected hub-flow thrust | Actual datum-flow thrust | Shaft angular-balance residual |
| --- | ---: | ---: | ---: |
| Fixed voltage | 3.747201813 N | 3.128852328 N | +0.013226878 N·m |
| Dynamic battery | 3.747201812 N | 3.128852327 N | +0.013226878 N·m |

The zero-rate controls passed. After repair the loads match and `I_rotor * (Omega_dot + axis dot body_alpha) = Q_motor - Q_prop,hub` closes within `1e-8 N·m`. The pre-fix suite had four failures; the repaired electric-session suite passes 98 checks. [Pre-fix extracted console evidence](pre-fix.txt), [checked run records](checks.json), and [source identity](identity.json).

## Flight evidence

The existing FL-04 fixture recorded six aircraft before source edits and verified exact replay. The retained [Timber baseline](baseline.orfl) has 260 ticks plus its initial sample, with the fixture's roll-reversal marker and engine-off intervention. [Export report](baseline-export.json), [baseline CSV](baseline.csv), [exact replay report](exact-before.json) and [zero-difference comparison](exact-comparison.json) retain the original identity and completion evidence.

The [candidate](candidate.json) holds aircraft data, initial state and command tape fixed and uses the repaired solver: `complete: true`, `solver_changed: true`, 261 rows. [Candidate CSV](candidate.csv) and [comparison](comparison.json) show first divergence at tick 1. Over 1.0833 seconds the largest component differences are 0.000175 m position, 0.000374 m/s velocity and 0.0000278 rad/s angular rate. This short manufactured maneuver measures numerical impact; it does not establish real Timber handling or long-duration stability.

[Five non-electric controls](non-electric-controls.json) produced byte-identical CSV files when replayed as explicit candidates: Stik, Extra, P-51, Avanti and finite-glow Stik. Their source fingerprints differ, so these are preserved-output controls, not claims of exact-mode replay under the old solver.

Reproduce the Timber comparison from the repository root, choosing new output paths:

```powershell
python tools/flight_log/flight_log.py replay docs/research/propulsion/EL1d/hub-inflow-2026-10-23/baseline.orfl --candidate app/data/aircraft/turbo_lumber_evolution.json --out tmp/hub-candidate
python tools/flight_log/flight_log.py compare docs/research/propulsion/EL1d/hub-inflow-2026-10-23/baseline.csv tmp/hub-candidate/flight.csv --out tmp/hub-comparison.json
```

## Verification and limits

Checked native regressions passed: electric equilibrium/source, electric session, battery session, rotor stop, event localization, runway start, coupled shaft, shaft refinement, propulsion scalar reference, slipstream scalar reference, simulation, checkpoints and the six-aircraft flight-log suite. The reference suites include 25,001 propulsion comparisons and 30,001 slipstream comparisons; FL-04 passes 3,247 checks both before and after repair. Core rigid-body and aerodynamic checks pass 15 and 23 checks respectively. Detailed commands and logs are retained in [checks.json](checks.json) and the adjacent `.log` files. The transcendental guard passes.

The complete `app/test.sh` invocation through WSL could not start: this shared Windows checkout has CRLF shell scripts (`set: pipefail\r: invalid option name`). These focused native runs do not constitute a full Linux suite, a rendering qualification or a performance benchmark. No visual behavior was changed deliberately or visually qualified.

Independent reviews found no additional confirmed defect in the examined rigid-body equations, fixed-datum acceleration conversion or aerodynamic sign/reference-point paths. They are bounded inspections, not a proof of the entire physics system. Pure spanwise/high-sideslip wing behavior remains a declared unvalidated domain; no arbitrary drag coefficient was added. The existing stopped-propeller cutoff, inferred aerodynamic/propeller data, and empirical wake drift remain limitations. Read-only audio torque and smoke-wash estimates still use their earlier datum-flow convention and do not feed physics state. A future electric propwash feature must explicitly define hub induction separately from datum-based wake geometry and cover its authoring contract.

Baseline HEAD was `16b82bcb5897025c0fdcb23823552112604234d7`. Concurrent commit `d9638018` included the in-progress production fix and electric regression with unrelated camera/Corsair work. History was left intact; the working tree removes the speculative wash changes that commit captured. Review the listed physics paths against the original baseline; the retained identity names the observed shared-tree commit and exact source hashes.
