# G2-R1 — Steady shaft equilibrium integrity

2026-10-08 · **Status: complete; focused and full regression verified.** Scope: startup shaft-RPM solving. No aircraft data, force law, sampled shaft update or session/UI changes.

## Failure and repair

The old 80-iteration bisection returned its interval endpoint without establishing a torque root. A modified P-51 input accepted by the complete aircraft loader gives positive net torque at both bounds: +9.549296585 N·m at 1 RPM and +9.542330497 N·m at 3,200 RPM. The old solver returned 3,200 RPM. A second accepted input has a finite final curve RPM of `1.2e308`; multiplying by the existing 1.6 ceiling overflows, and the old solver returns infinity.

`Propulsion.steady_rpm` now requires finite query inputs, a finite ordered bracket and finite net torque with the supported positive-to-negative endpoint orientation. Exact endpoint roots are accepted. Every midpoint evaluation must be finite. The final returned candidate must satisfy a finite torque residual within `1e-10 * max(1, |Q_engine|, |Q_prop|)` N·m. This is a float64 numerical acceptance tolerance, not an empirical accuracy band. Failure returns `NAN`; existing trim and ground-start numerical guards refuse it. Supported solves retain the same 80 iterations and arithmetic order. Lag and turbine branches are unchanged.

A bracket check is a prerequisite for bisection, as documented by [SciPy's primary algorithm reference](https://docs.scipy.org/doc/scipy-1.10.0/reference/generated/scipy.optimize.bisect.html). No SciPy dependency was added. This repair does not establish uniqueness, monotonicity, a valid equilibrium outside the existing bracket, or measured engine accuracy. The physically incomplete stopped-propeller branch and coupled transient shaft dynamics remain separate work.

## Proof

- 46 focused checks: analytic constant-torque/constant-Cp roots across density and signed inflow, endpoint roots, both unbracketed orientations, nonfinite inputs/evaluated torques, finite arithmetic overflow, accepted-loader reproductions and caller refusal. The unchanged solver fails 22 checks.
- Disposable-copy fault injection: a nonfinite midpoint and a fake inner root are refused. Three deliberately weakened guard variants fail their regression checks; the shared tree is never mutated for these controls.
- Four aircraft: 60 steady-RPM queries, eight production level/glide trims and four 240-tick flight endpoints retain all 16 packed-float SHA-256 hashes exactly. This is verification against the prior implementation, not real-aircraft validation.
- Full `app/test.sh` passes on the shared pre-fix working tree and isolated patched baseline; golden flights, four aircraft trimmed traces and 30/60/144 fps state/wake hashes pass. The integrated working tree repeats the focused checks, fault controls and all 16 fleet hashes. See [verification manifest](verification.json), [before](before.log), [after](after.log), [original failures](regression-before.log), [focused result](regression-after.log) and [fault controls](faults.log).
- Static Godot skill lint: zero errors before/after, the same 12 pre-existing warnings. Debug execution adds no warnings in the changed lines; existing dependencies still emit integer-division/shadowing warnings.

The repair runs at startup/trim, not in the physics tick. No hot-loop cost or aerodynamic calibration claim is made. The baseline is commit `ce4a80c4774dd4c398e6f8ae55f82e63e111a691`; the shared working tree also contained separately owned runway/UI changes. The isolated full run uses that committed baseline plus this repair.

## Reproduce

From the repository root:

```sh
"$(app/get-godot.sh)" --headless --path app --script res://tests/test_shaft_equilibrium.gd
"$(app/get-godot.sh)" --headless --path app --script "$PWD/research/propulsion/g2-r1/probe.gd"
python3 research/propulsion/g2-r1/verify_faults.py
app/test.sh
```

[Focused tests](../../../../app/tests/test_shaft_equilibrium.gd) · [counterexamples and fleet probe](../../../../research/propulsion/g2-r1/probe.gd) · [fault verifier](../../../../research/propulsion/g2-r1/verify_faults.py). The probes use synthetic inputs and the repository's existing aircraft data; no external asset or new dependency is included. Code retains the repository MIT license.

Ready-to-paste commit message:

```text
fix(physics): reject unproven steady shaft equilibria (G2-R1)

Proof: 46 checks, 3 rejected guard mutations, 16 unchanged fleet hashes,
and full app/test.sh; preserve existing lag/turbine and valid shaft results.
```
