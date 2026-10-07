# E0b6p — Enabled-wake performance

2026-10-07 · **Status: GDScript optimization verified; E0b6p budget remains open.** No production aircraft-data change or native dependency.

## Scope

E0b6's distributed correction resolves the centroid swirl error, but costs 16–24 ms per active 240 Hz tick on the shared target. The current step removes avoidable implementation overhead while retaining the same five-point quadrature, chord intervals, core/occupancy splits, local force law, reverse fade and RK-stage evaluation. It does not loosen the accuracy criterion, lower the physics rate or hold stage-dependent loads across a tick.

The frozen [E0b6 reference](../../../../app/tests/swirl_e0b6_reference.gd) and independent dense midpoint integration serve different purposes: the former detects numerical changes introduced by optimization; the latter checks integration accuracy against the same assumed physical model. Neither supplies independent flight validation. The [E0b6 source and uncertainty audit](../E0b6/README.md) remains applicable.

## Measurements and proof

The implementation hoists piece/control/curve constants once per piece and evaluates both washed tail laws as scalar float64 arithmetic. It preserves operation and summation order and removes explicit arrays and dictionary lookups from each quadrature point. Interval and piece result arrays remain; this is not a fully allocation-free implementation.

The [interleaved profile](profile.json) alternates frozen/current correction calls on the same fixture in one process (three warm-up pairs, 16 measured pairs). The median correction cost falls **3.76–4.31×**. Structural counts follow the unchanged sample grid: 250–265 candidate nodes, 140–190 positive-area nodes and 280–380 local tail evaluations per call. `tail_load_calls` in the report counts the frozen reference's generic helper calls; the optimized version replaces those calls with scalar arithmetic. Four RK stages repeat this work every tick.

| Regime | Frozen correction, µs/call | Scalar correction, µs/call | Speed-up |
| --- | ---: | ---: | ---: |
| Forward | 6,318.5 | 1,519.0 | 4.16× |
| Stall | 6,956.5 | 1,614.0 | 4.31× |
| Static | 6,288.0 | 1,542.0 | 4.08× |
| Spin | 5,601.0 | 1,486.0 | 3.77× |
| Reverse fade | 4,502.0 | 1,197.5 | 3.76× |

[Whole-tick comparison and trajectory proof](cost-comparison.json) retain five 24-tick batches after warm-up and every boundary of a separate 240-tick trajectory. These separate runs overlap other checks on the shared i5-10500 host; unchanged zero-swirl cases also become slower, so their variation is not caused by this optimization. The interleaved correction profile isolates the improvement more clearly. Neither measurement closes Gate P.

| Regime, swirl factor 0.4 | Before, µs/tick | After, µs/tick |
| --- | ---: | ---: |
| Forward | 24,458.3 | 12,979.8 |
| Stall | 21,873.1 | 11,577.9 |
| Static | 19,518.0 | 9,070.0 |
| Spin | 23,270.2 | 13,160.0 |
| Reverse fade | 22,370.5 | 10,197.0 |
| Reverse off | 419.9 | 777.2 |

The disposable-copy benchmark reproducer also [passes in a second run](cost-repeat.json): active cases measure 8.2–11.0 ms/tick after optimization, and all trajectory values remain equal. The spread between runs reinforces the shared-host timing limitation.

All **12 trajectories × 240 boundaries** retain exactly equal sampled body, auxiliary and continuous values (including the six zero-swirl cases). The checker allows `1e-9 * max(1, abs(reference))` for nonzero swirl and requires exact zero-swirl values; observed error is zero. These numeric comparisons are not a claim about cross-platform byte identity.

- [200 seeded equivalence cases](equivalence.log) match the frozen helper exactly. They vary provenanced synthetic geometry, density, rpm, controls and rates; 150 use the downwash law and 50 the classic horizontal-tail law; both held/default wing CL are covered. Core/inner/outer crossings occur in 72/94/105 cases; full/partial/cutoff reverse weights in 140/16/44. The regression tolerance is absolute plus relative `1e-10`; observed error is zero.
- [41 dense-reference and continuity checks](accuracy.log) and [23 torque checks](torque.log) pass unchanged. Accuracy acceptance remains the E0b6 criterion; no node reduction or parameter tuning occurred.
- [8,192-sample dense probe](dense-probe.log) retains the E0b6 peak normalized correction errors: `1.035e-6` force and `1.024e-6` moment.
- [Resource/scene checks](integration.json) pass with zero errors and no new-file diagnostics; 184 existing validator warnings remain. [Manifest](manifest.json) identifies the isolated files and frozen-reference hash.
- [Four physics mutations](mutations.log) are rejected by assertions in disposable copies. E0b6's mutation runner now targets the corresponding scalar expressions, so its reproduction command remains usable.
- [Full isolated regression](suite-summary.log): `app/test.sh` exits 0, 116 sections and 90 GDScript test programs. Concurrent landscape/radio/desktop edits are excluded. The newly registered [nonzero-swirl frame check](frames.log) produces identical hashes of all 480 body/aux/load/input boundaries at 30/60/144 fps; the production and continuous axial-wash frame checks also pass.
- [16 production fleet fingerprints](fleet.json) remain identical. No production data or golden regeneration.

## Remaining budget and next work

**The 500 µs/tick target is still missed. E0b6p is not complete as a budget gate.** The correction alone takes 1.2–1.6 ms per load evaluation in the interleaved profile, before the other three RK stages and the rest of the dynamics. Axial-only slipstream evaluations add about 175–252 µs each in that profile. These are separate costs; optimizing only force allocation cannot close the whole-tick budget.

The next bounded E0b6p investigation should evaluate the complete smooth-wake evaluator (axial occupancy plus distributed swirl), retaining this frozen reference, dense accuracy, current-stage state and exact production trajectories. Do not reduce the physics rate, freeze geometry between RK stages, tune coefficients to hide the error, or treat a faster legacy P-51 native experiment as proof for the new profile/transport path. Native **adoption** still requires Gate P and platform evidence; the existing native experiment remains research-only. Production Stik remains unconfigured, and E0b7's independent field calibration remains open.

## Reproduce

```sh
$(app/get-godot.sh) --headless --path app --script res://tests/test_swirl_optimization.gd
$(app/get-godot.sh) --headless --path app --script res://tests/test_swirl_accuracy.gd
$(app/get-godot.sh) --headless --path app --script res://tests/test_swirl_torque.gd
$(app/get-godot.sh) --headless --path app --script "$PWD/research/propwash/e0b6p/profile_swirl.gd" -- /tmp/e0b6p-profile.json
python3 research/propwash/e0b6p/compare_cost.py --godot "$(app/get-godot.sh)" --output /tmp/e0b6p-cost.json
python3 research/propwash/e0b6p/check_frames.py --godot "$(app/get-godot.sh)"
app/test.sh
```

Commit message: `E0b6p: scalarize distributed swirl; prove 200 equivalent cases, 12 exact trajectories and full regression; retain budget gate`
