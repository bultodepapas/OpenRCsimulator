# VAL-7a — Matched static propeller readings

2026-10-07 · **Status: offline reducer verified; physical measurements remain VAL-7.** Owns `research/validation/static-prop/`. No runtime, aircraft-data, trace or force-model changes.

## Purpose and scope

The [propeller investigation](../../roadmap-investigations/03-propeller-propwash.md) identifies unmatched propeller/RPM evidence as a limit on powered-flight claims. The current Stik's derived static thrust/RPM are not measurements. This tool prepares matched static measurement reduction while propwash performance, mass/CG measurement tooling and trace identity are handled independently.

The [tool](../../../../research/validation/static-prop/README.md) reduces net thrust, RPM, diameter and density to Ct and ideal-disc power. Optional net shaft torque enables shaft power, Cp and static figure of merit. Every input carries units, standard uncertainty and provenance. Measured campaigns refuse estimated/catalogue thrust, RPM and torque; corrected measurement-derived readings are allowed with identified sources. Reports preserve inputs and code/input hashes; no inferred coefficient is installed in an aircraft file.

## Proof

[18 tests](tests.log) cover hand-calculated coefficients, RPM conversion, shaft power, dimensional scaling, finite-difference uncertainty sensitivities, no-torque behavior, conflicting ideal-disc evidence, strict input failures and CLI reproducibility. Three source mutations fail assertions on disposable copies: omitted RPM conversion, omitted `2*pi` in shaft power, and missing sensitivity exponents. The unmodified copied control passes.

The [synthetic report](example-result.json) uses 4.6875 N, 6,000 RPM, 0.25 m diameter, 1.2 kg/m³ and optionally 0.1 N·m torque. It yields Ct = 0.1 and shaft power = 62.8318530718 W. The second run omits torque and correctly leaves Cp, shaft power and figure of merit unavailable. These are algebra fixtures, not independent propeller observations.

Reproduce from the repository root:

```sh
python3 research/validation/static-prop/test_reduce.py
python3 research/validation/static-prop/reduce.py research/validation/static-prop/example.synthetic.json
```

Validation is scoped to the new offline code, input and CLI. No app code or dependencies changed, so another full Godot suite was not needed for this step. The prior VAL-6a shared-tree app run is separate evidence, not presented as a VAL-7a validation run.

## Findings and limits

- Thrust and RPM alone do not determine shaft power. Ideal-disc power is a theoretical bound, not an engine rating or substitute for torque data.
- Static figure of merit differs from propulsive efficiency. Keep it named explicitly and preserve values above one as diagnostics; clamping would hide measurement or setup problems.
- Reusing Ct and Cp in a ratio does not make their errors independent. Compute sensitivities from the original measurements; density and diameter are shared.
- Inputs assume one stabilized static condition, corrected net loads and independent error terms. The tool cannot certify alignment, negligible inflow, sensor synchronization, free-air clearance or calibration from text declarations.
- Physical thrust/RPM observations, matched-propeller operating-range comparisons and throttle-step lag remain open. No fit or held-out-validation claim is made.

## Primary references

- [UIUC Propeller Database](https://m-selig.web.engr.illinois.edu/props/propDB.html) and [Volume 1](https://m-selig.web.engr.illinois.edu/props/volume-1/propDB-volume-1.html): standard coefficients, static measurements over RPM and power coefficient derived from measured torque.
- MIT, [*Performance of Propellers*](https://web.mit.edu/16.unified/www/SPRING/thermodynamics/notes/node86.html): dimensional thrust/torque scaling, `P = 2*pi*n*Q` and `eta = T*V/P`.
- NASA, [NTRS 19970005490](https://ntrs.nasa.gov/api/citations/19970005490/downloads/19970005490.pdf), PDF pp. 38–45: actuator-disc induced velocity/power and ideal-to-actual static power comparison.
- Acree, [NASA TM-20210021872](https://ntrs.nasa.gov/api/citations/20210021872/downloads/Acree%20TM-20210021872_FINAL.pdf?attachment=true), pp. 16–18: distinction between hover figure of merit and propulsive efficiency.
- NIST, [TN 1297 Appendix A](https://www.nist.gov/pml/nist-technical-note-1297/nist-tn-1297-appendix-law-propagation-uncertainty): first-order uncertainty, covariance and standard uncertainty conventions.

Sources consulted 2026-10-07; linked, not redistributed. Tests and example data are original synthetic fixtures.

Ready-to-paste commit message:

```text
VAL-7a: add static propeller measurement reducer

Proof: 18 analytic, scaling, uncertainty, contract and CLI tests pass;
three isolated formula mutations fail, unmodified control passes.
Torque-free runs leave Cp/shaft power/FOM unavailable. Real VAL-7
measurements and transient lag remain open; runtime/data unchanged.
```
