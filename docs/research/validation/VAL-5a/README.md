# VAL-5a — verified weighing reduction

**Status:** verified offline tooling complete; isolated app regression passed. Real mass/CG measurements remain VAL-5. **Date:** 2026-10-07. **Owner:** Codex mass/CG tooling agent.

## Result

The [offline reducer](../../../../research/validation/weighing/README.md) converts kg scale readings and signed forward/right support coordinates into tare-corrected mass and horizontal CG. Reports retain configuration, datum, provenance, raw-input/reducer SHA-256 identity, standard uncertainties and their full covariance. Invalid shape, units, numeric types, non-finite values and physically impossible net readings are refused. It does not edit simulator data.

The synthetic three-support fixture has known net loads 1.3, 1.1 and 0.2 kg:

| Output | Value | Combined standard uncertainty (k=1) |
| --- | --- | --- |
| Mass | 2.6 kg | 0.00599833 kg |
| Forward CG | 0.123076923 m | 0.00216751 m |
| Right CG | −0.023076923 m | 0.00212756 m |

Every example reading and uncertainty is invented and labelled synthetic. These numbers establish no aircraft property or physical tolerance. [Full reproducible result](example-result.json).

## Verification

- [15 tests](tests.txt): asymmetric/symmetric statics, tare-offset and coordinate-translation invariance, gain cancellation, shared-datum propagation, numerical derivatives for every local input, invalid inputs and CLI failure behavior.
- A seeded 20,000-sample Monte Carlo check compares all entries of the 3×3 covariance with a 3.5%-of-diagonal-scale sampling allowance. This checks the stated stochastic model, not its adequacy for a real scale.
- [Four source mutations](mutations.json), made only in disposable files, are rejected by actual assertion failures: omit tare; lose mass/moment covariance; average down the shared datum error; leak common gain into CG. The unmodified control passes.
- CLI output matches byte for byte on repeated runs; the report checks input-byte and reducer hashes. Whitespace-only input changes alter the raw hash without altering derived values. Invalid input preserves an existing report; input/output aliases, missing paths and overflow fail cleanly.
- The independent Luna Max review confirmed the equations and found a diagnostic issue: common gain could spuriously trigger a CG-linearity warning. The warning now depends on local load uncertainty only; a separate test proves that 20% common gain alone does not trigger it.
- All 15 tool tests also pass in an isolated clone. Full `app/test.sh` exits 0 on committed baseline `38e72809ff06`: 102 GDScript test programs, all four aircraft traces, and identical 30/60/144 FPS hashes for standard flight, wash transport and distributed swirl. [Run identity](verification.json) · [Selected suite output](app-checks.txt). Concurrent working-tree changes were excluded. Existing aircraft-data plausibility messages and fixture shutdown warnings remain baseline diagnostics; no engine errors occurred.

## Scientific basis and limits

FAA's level-weighing procedure subtracts tare at each station and obtains CG from summed moments divided by total weight. We apply that statics balance in two horizontal axes. [FAA Weight & Balance Handbook, chapter 3](https://www.faa.gov/sites/faa.gov/files/2023-09/Weight_Balance_Handbook.pdf).

Uncertainty follows the first-order sensitivity/covariance rule. Per-support gain is shared by gross and tare; global gain is shared by every support and cancels from CG. A shared coordinate-origin uncertainty contributes once. These are derived consequences of the measurement model, rather than uncertainty values supplied by a reference. [NIST TN 1297 Appendix A](https://www.nist.gov/pml/nist-technical-note-1297/nist-tn-1297-appendix-law-propagation-uncertainty).

Only the stated independent local errors, per-scale gains, global gain and independent shared x/y datum errors are represented. Known calibration corrections belong in the input readings first. Vertical CG is unobservable from this setup. Leveling, buoyancy, drift and arbitrary correlations require additional evidence; setup flags only record the operator's attestations. No new runtime schema, parameter tuning, golden update or flight-fidelity claim is made.

## Reproduce and hand off

```bash
python3 research/validation/weighing/test_reduce.py
python3 research/validation/weighing/check_mutations.py
python3 research/validation/weighing/reduce.py research/validation/weighing/example.synthetic.json --output /tmp/val5a-result.json
cmp /tmp/val5a-result.json docs/research/validation/VAL-5a/example-result.json
```

For VAL-5, collect actual readings, calibration/uncertainty records, level-reference and scale-placement photos, and the equipment/fuel configuration. Preserve original files with the generated report. Compare a known load and known CG before using the reduction on the aircraft. Any later simulator-data update needs its own datum conversion and deliberate validation review.

Suggested commit message:

```text
VAL-5a: add provenance-aware mass and horizontal CG weighing reducer

Proof: 15 statics/uncertainty/CLI tests, 20,000-sample covariance check,
four isolated mutations rejected, isolated app/test.sh regression.
Synthetic evidence only; real weighing remains VAL-5.
```
