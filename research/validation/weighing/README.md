# VAL-5a — aircraft weighing reduction

**Status:** offline tool; synthetic verification only. Real measurements remain VAL-5 in [ROADMAP](../../../ROADMAP.md).

Reduce simultaneous scale readings to aircraft mass and horizontal center of gravity. Python 3.10+; standard library only. No simulator inputs are changed.

From the repository root:

```bash
python3 research/validation/weighing/reduce.py research/validation/weighing/example.synthetic.json
python3 research/validation/weighing/test_reduce.py
python3 research/validation/weighing/check_mutations.py
```

Use `--output /tmp/weighing-result.json` to save a report. Invalid input exits nonzero before opening the output; input/output aliases are refused. Reports include the complete parsed input, exact input-byte and reducer SHA-256 hashes, derived values, standard uncertainties, covariance, individual error contributions and limitations. Output is deterministic for identical input and reducer bytes. Keep the original input alongside the report: parsed JSON does not preserve byte formatting.

## Field procedure and input contract

The [example](example.synthetic.json) is invented test data, **not Stik measurements or default uncertainty estimates**. Replace every value and source before using it for a real build.

1. Record aircraft identity, installed equipment, battery position, fuel quantity and weighing date in `aircraft`/`configuration`; identify raw reading and photo records in each quantity's `source`.
2. Use calibrated mass-reading scales in kg. Level the aircraft's body axes longitudinally and laterally using its reference lines; a taildragger's resting attitude is not level. Record the leveling method and limitations in `setup.notes`.
3. Support the stationary aircraft at three or more non-collinear points. All vertical load must pass through the scales; no person, restraint or unmeasured support may carry load. Set the two `setup` confirmations to true only when established.
4. Record each support's gross reading and tare (blocks/chocks/support equipment), and its horizontal coordinates in meters from one stated datum: **x forward, y right**. Tare belongs at the same point as its gross reading. If a scale already excludes tare, enter zero tare and explain that in its source; do not subtract it twice.
5. Supply uncertainty and provenance for every quantity. For a physical session set `evidence` to `measured`; quantity kinds may be `measured`, `estimated`, `derived` or `manual`. Synthetic quantities are refused in that session. These labels are declarations, not independent checks of authenticity.

Every quantity has `{value, unit, u, kind, source}`. `u` is a finite nonnegative **standard uncertainty**, in the same unit as the value. It is not a maximum error or 95% interval. For an assumed rectangular bound ±a, use a/√3; record the assumption. For a sample mean of independent repeats, use its standard error and preserve the raw readings. Zero `u` asserts that the term is excluded/exact; it does not mean unknown.

| Input | Unit | Error model |
| --- | --- | --- |
| Per-support `gross`, `tare` | kg | Independent readout/repeatability terms, excluding gain errors below. Nonnegative gross/tare readings. |
| Per-support `x`, `y` | m | Independent local placement errors, excluding datum errors below; signed coordinates allowed. |
| Per-support `scale_gain` | `1` | Zero nominal value, fractional gain uncertainty shared by that support's gross and tare; independent across supports. |
| Global `common_scale_gain` | `1` | Zero nominal value, fractional gain uncertainty shared by **every** gross/tare reading. |
| Global `datum_x`, `datum_y` | m | Zero nominal value, common coordinate-origin errors, independent between axes. |

For example, `scale_gain.u = 0.001` means 0.1% standard uncertainty. Apply known calibration corrections to readings/positions first; the error quantities represent remaining uncertainty. Separate independent and shared components without double counting. A stable additive zero offset cancels between gross and tare; drift between the readings does not. Arbitrary inter-scale, repeat-reading, drift, or x/y correlations are unsupported. Do not force such a dataset into independent terms; extend the model only when actual measurement evidence requires it.

This tool requires at least three non-collinear support positions (normalized area tolerance 1e-12, a numerical guard). Negative net reactions, zero total mass, unit/type errors, duplicate keys/IDs, non-finite numbers and overflow are refused. Zero net support load and local-load mass uncertainty above 10% produce diagnostics; 10% is a tooling heuristic, not a metrology acceptance limit. The setup assertions cannot establish actual level or stability.

## Equations and scope

With net scale readings nᵢ = grossᵢ − tareᵢ in kg:

- M = Σnᵢ; X = Σnᵢxᵢ/M; Y = Σnᵢyᵢ/M.
- ∂X/∂grossᵢ = (xᵢ − X)/M; ∂X/∂tareᵢ is its negative; ∂X/∂xᵢ = nᵢ/M. Replace x/X by y/Y for lateral CG.
- A support's fractional gain derivative is nᵢ for mass and nᵢ(xᵢ − X)/M for X.
- A shared gain derivative is M for mass and zero for both CG coordinates: it cancels in the ratio. A shared datum shift has unit sensitivity for its CG axis.

Each independent error contributes a vector a = sensitivity × u in output order `[mass_kg, cg_x_m, cg_y_m]`. Covariance is Σaaᵀ; standard uncertainties are square roots of its diagonal. Off-diagonal units are products of the named output units. Propagating total moment and mass independently would lose their covariance and overstate CG uncertainty.

The result is **horizontal CG only**, for the stated level configuration. It cannot infer vertical CG, correct unknown tilt, establish stability limits, or validate flight behavior. Buoyancy and unquantified setup errors are excluded. Large uncertainties or near-zero total net load can invalidate the first-order ratio approximation.

Method references: [FAA Weight & Balance Handbook, chapter 3](https://www.faa.gov/sites/faa.gov/files/2023-09/Weight_Balance_Handbook.pdf) for level weighing, tare and moments; [NIST TN 1297 Appendix A](https://www.nist.gov/pml/nist-technical-note-1297/nist-tn-1297-appendix-law-propagation-uncertainty) for sensitivity/covariance propagation and standard uncertainties. Our two-axis and shared-error formulas are direct derivations under the assumptions above. [Verification evidence](../../../docs/research/validation/VAL-5a/README.md).
