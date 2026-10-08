# VAL-6a — Auditable swing-test reduction

2026-10-07 · **Status: offline tooling verified; real rig, plank and aircraft measurements remain VAL-6.** Scope: `research/validation/inertia/`; no simulation, input-data, trace or rendering changes.

## Why this step

The [validation investigation](../../roadmap-investigations/08-validation-flight-testing.md) identifies uncertain inertia as a major obstacle to interpreting the roll-response mismatch. Flight-response tuning cannot resolve that uncertainty. With DATA-3, E0b6p and landscape work occupied, this independent measurement tool prepares a real measurement without changing flight behavior or claiming a gate is closed.

## Implementation and proof

The [reducer and input contract](../../../../research/validation/inertia/README.md) support bifilar and compound timings, fixture tare, analytic first-order uncertainty and a uniform-plank comparison. Quantity IDs retain shared-measurement covariance; strict fields, units, provenance and finite-value checks reject malformed input. Reports preserve input and reducer hashes. The CLI only reads its input and prints its report.

[20 tests](tests.log) cover closed-form plank inertias with/without tare, three compound pivot heights, finite-difference verification of uncertainty sensitivities, shared geometry, timing counts, invalid input and CLI failure behavior. Three mutations on disposable copies are rejected by assertion failures: wrong spacing factor, omitted parallel-axis shift and halved timing sensitivity. The unmodified copied control passes. No mutation touches shared source files.

The [synthetic report](synthetic-result.json) recovers `0.246666666666667 kg*m^2` for a 2 kg, 1.2 × 0.2 m uniform plank with both methods, after subtracting a 0.5 kg rig. Its uncertainties are manufactured test inputs, not field estimates. The input is [synthetic.json](../../../../research/validation/inertia/synthetic.json).

Reproduce from the repository root:

```sh
python3 research/validation/inertia/test_reduce.py
python3 research/validation/inertia/reduce.py research/validation/inertia/synthetic.json
```

The full `app/test.sh` integration run exited 0 (131 sections), including all aircraft model contracts, fleet trimmed traces and standard/experimental frame-rate checks. [Log](app-suite.log) · [Verification summary](verification.json). This ran against the shared working tree with concurrent changes present; it is not an isolated release-build certification.

## Findings and limits

- Compound tare must be subtracted about a common pivot **before** shifting the remaining object to its CG. Loaded and tare CGs generally differ.
- Shared geometry is one uncertain input, so combine its loaded/tare sensitivities before computing variance. The plank comparison also shares object mass with the reduced inertia.
- NACA distinguishes structure inertia from in-air virtual inertia. This bounded tool reports effective inertia in air and explicitly neglects buoyancy; it does not implement added-air, amplitude or damping corrections. The net pivot result is preserved; the compound CG estimate uses a rigid-mass shift with added-air axis transfer unresolved.
- Distinct measurements are assumed independent. Common instrument biases and partial covariance are not modeled. First-order uncertainty is unsuitable for strongly nonlinear or poorly resolved measurements. The untared compound stationary-height flag catches a zero first-order contribution despite nonzero height uncertainty; it is not a general nonlinear uncertainty bound.
- A nominal 3% plank band is a diagnostic, not proof of physical validation. Repeated observations, axis alignment, amplitude/decay records and a real known-plank test remain required. No inferred inertia is written to aircraft data.

## Primary references

- Soule and Miller, [NACA TR-467, *The experimental determination of the moments of inertia of airplanes*](https://ntrs.nasa.gov/citations/19930091541), 1934: aircraft pendulum procedures and air-effect corrections. Public NASA report; consulted, not redistributed.
- Gracey, [NACA TN-1629, *The experimental determination of the moments of inertia of airplanes by a simplified compound-pendulum method*](https://ntrs.nasa.gov/citations/19930082299), 1948: compound-pendulum measurements and suspension-length comparison. Public NASA report; consulted, not redistributed.
- Jardin and Mueller, [*Optimized Measurements of UAV Mass Moment of Inertia with a Bifilar Pendulum*](https://doi.org/10.2514/1.34015), 2009: nonlinear dynamics, geometry, tare and uncertainty limitations. Citation only; no paper content redistributed.
- NIST, [TN 1297 Appendix A](https://www.nist.gov/pml/nist-technical-note-1297/nist-tn-1297-appendix-law-propagation-uncertainty): first-order propagation including covariance and standard uncertainty conventions. Consulted 2026-10-07.

Ready-to-paste commit message:

```text
VAL-6a: add offline swing-test inertia reduction

Proof: 20 analytic, contract and CLI tests pass; three isolated formula
mutations fail and the unmodified control passes. Synthetic bifilar and
compound plank results agree; full app/test.sh passes. Real VAL-6
measurements remain open.
```
