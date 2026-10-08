# VAL-7c — Uncertainty in RPM step diagnostics

2026-10-07 · **Status: COMPLETED — offline uncertainty tooling verified; physical VAL-7 measurements remain open.** Owner: Codex transient-uncertainty agent. Scope: `research/validation/rpm-step/`; no simulator, aircraft-data or dependency changes.

## Result

The [reducer contract](../../../../research/validation/rpm-step/README.md) now accepts an explicit `uncertainty_model: independent-inputs v1`. It propagates endpoint, sample RPM, sample time and command-time standard uncertainties into crossing times, rise time, lag, delay and the 63.2% consistency residual. Signed contributions preserve covariance when crossings reuse endpoints or samples. The complete output covariance is retained.

Old inputs retain their nominal diagnostic values and get `measurement_uncertainty.status: not_requested`. The opt-in model requires independent primitive errors; it does not silently reinterpret existing uncertainty declarations. Common calibration/clock errors, overlapping endpoint windows and filtered/correlated observations need another acquisition model. These limitations matter before reducing real recordings.

A local uncertainty calculation cannot describe a crossing that switches segments under small perturbations. An estimated 3-standard-uncertainty screen checks threshold margins (including earlier samples), endpoint separation, timestamp order and crossing/command order. Unresolved or repeated crossings retain nominal diagnostics but report uncertainty as unavailable. The screen is not a probability guarantee or confidence interval. Interpolation error, model mismatch and unobserved intersample motion remain outside the uncertainty calculation.

## Equations and source

The method uses first-order sensitivity propagation with covariance, as described by [NIST TN 1297, Appendix A](https://www.nist.gov/pml/nist-technical-note-1297/nist-tn-1297-appendix-law-propagation-uncertainty) (consulted 2026-10-07). The crossing derivatives below are derived directly from this reducer's interpolation equation; the screening multiplier is an explicitly estimated implementation policy.

For endpoint RPM estimates `r0, r1`, threshold fraction `f`, adjacent samples `(tL,yL), (tR,yR)`:

```text
b = (1-f)*r0 + f*r1
h = tR-tL; d = yR-yL; q = (b-yL)/d
T = tL + h*q

dT/d(tL,tR,r0,r1,yL,yR)
  = (1-q, q, h*(1-f)/d, h*f/d, -h*(1-q)/d, -h*q/d)
```

For each independent primitive input `i`, retain `g_i = derivative_i * u_i` in seconds. Combine these signed contributions through the existing rise/lag/delay equations **before** calculating `u = sqrt(sum(g_i²))`. Output covariance is `sum(g_Ai*g_Bi)`. Command error cancels from rise, lag and the consistency residual, but contributes to delay and command-relative crossing times. No normality assumption or coverage factor is needed for the reported local standard uncertainties. Normal draws are used only in the verification experiment.

## Verification

- [34 tests](tests.log): 20 existing regression/contract/CLI tests and 14 uncertainty tests. They cover both step directions, all primitive sensitivities against central differences, shared and disjoint segments, command cancellation, covariance symmetry/positive-semidefinite probes, clock/RPM scaling, zero uncertainty, explicit opt-in and each unresolved-case screen.
- **12,000 seeded synthetic trials:** all ten output standard deviations agree with propagation within the declared 3% test band; lag/delay covariance is also checked. This verifies calculation under the assumed input distribution, not real instrument errors.
- [Four isolated mutations](mutations.json) rejected by assertions: treating shared endpoints as independent, reversing a sample contribution, losing command cancellation, and omitting the bracket screen. A passing 34-test control precedes mutation runs. [Reproduction script](check_mutations.py).
- [Fresh clone](fresh-clone.log): all 34 tests pass on the recorded tracked baseline with only this step's reducer/tests/README overlaid. No untracked shared-tree dependency.
- [Synthetic input](example.synthetic.json) and [deterministic CLI result](example-result.json) retain exact input/reducer SHA-256 hashes. The fixture is a piecewise linear RPM ramp, not an engine or a delayed exponential. Its diagnostic lag is 0.364096 s with standard uncertainty 0.000147966 s; delay is 0.261639 s with standard uncertainty 0.00102436 s. Its large 63.2% consistency residual remains visible: precise measurement of a ramp does not make it first-order engine dynamics.

```sh
python3 -m unittest discover -s research/validation/rpm-step -p 'test_*.py' -v
python3 docs/research/validation/VAL-7c/check_mutations.py
python3 research/validation/rpm-step/reduce.py docs/research/validation/VAL-7c/example.synthetic.json
```

An independent Luna Max review checked the crossing/metric derivatives and branch-screen assumptions. Only offline Python changed; Godot physics tests and tick timing were not rerun because runtime, data and hot paths are untouched. Concurrent work is excluded from this step's proof.

## Next evidence

Record matched increasing/decreasing throttle steps with identified steady windows and an acquisition uncertainty model. Use the independence option only where justified; preserve correlated-source limitations otherwise. Keep fitted response diagnostics separate from held-out propulsion validation. VAL-7 and production propwash calibration remain open.

Ready-to-paste commit message:

```text
VAL-7c: propagate uncertainty in offline RPM step diagnostics

Proof: 34 tests pass, including 12,000 seeded trials; four isolated
mutations rejected; fresh-clone tests pass. Retain shared-input covariance
and withhold unresolved crossing uncertainty. Runtime/data unchanged;
physical VAL-7 measurements remain open.
```
