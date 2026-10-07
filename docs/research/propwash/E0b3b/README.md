# E0b3b — bounded neutral geometry and smooth wash transitions

2026-10-07 · **Status: experimental implementation verified; production Stik enablement deferred.** ROADMAP E0b3b. Geometry, radial occupancy and reverse-flow transitions are implemented; calibration (E0b4), transport (E0b5), swirl (E0b6), field validation and the enabled-path performance budget remain open.

## Geometry and load references

[Generator](../../../../research/propwash/e0b3b/derive_profile.py), [geometry handoff](geometry.json), [test-only fixture](../../../../app/tests/fixtures/stik_wash_profile.json). Each of the three E0b2 polygon groups becomes a piecewise-linear chord profile, with intervals `[a,b,chord(a),chord(b)]` in metres. Summing polygon sections preserves the hinge gaps and elevator notch in projected area. One-sided endpoints retain the chord discontinuity at the 30 mm elevator boundary.

| Group | Intervals | Geometric area (m²) |
| --- | ---: | ---: |
| Left horizontal half | 7 | 0.04629457865 |
| Right horizontal half | 7 | 0.04629457865 |
| Fin/rudder | 31 | 0.04758883929 |

These are the neutral relieved areas, not the larger existing aerodynamic reference areas; increments use the actual geometric areas without scaling them up. Seven [Python tests](../../../../research/propwash/e0b3b/test_profile.py) verify generation/freshness, polygon shoelace area and span moments, mirrored halves, notch/hinge relief, the chord jump, and independent polygon clipping in 24 span bands per group. Both generated outputs are checked by `app/test.sh`.

Coverage uses the horizontal neutral plane at **z_LE = −0.040640 m**. Loads, rates and moments retain the established pressure plane at **−0.045640 m**. The 5 mm difference is explicit; the baseline tail data does not move. The vertical pressure centroid follows its weighted span position. Longitudinal coverage and loads use the existing aerodynamic reference x, not chordwise-resolved flow or pressure. The loader restricts this new route to an axial shaft and transverse spans; tilted-shaft P-51 data continues on the legacy route.

## Model and schema

An aircraft opts in by declaring provenanced `edge_fraction` and `reverse_fade` quantities in `propeller.slipstream`, plus `profile` instead of `chords` on each piece. The loader validates finite values, interval ordering/non-overlap, integrated area, provenance and the supported geometry. Legacy configurations retain their arithmetic and schema.

For contracted radius `rs`, the occupancy is one inside `ri=(1−edge)*rs`, zero outside `ro=(1+edge)*rs`, and `1−t²(3−2t)` between them, where `t=(r²−ri²)/(ro²−ri²)`. This is a **load occupancy regularization**, not a measured radial velocity distribution. The test choice `edge=0.15` is estimated. Its full-disc occupancy integral is `(1+edge²)*π*rs²`, 2.25% above the hard-disc area at this width; E0b4 must account for that when evaluating coverage and decay.

Integration splits each linear chord interval at the inner/outer crossings. Plateau moments are analytic; five-point Gauss–Legendre integrates the transition's area and first span moment exactly up to floating-point error (polynomial degrees 7 and 8). One washed-minus-free tail evaluation uses each group's weighted centroid. Exact geometric moments do not make that nonlinear aerodynamic centroid approximation exact.

The entire load increment fades smoothly to zero in reverse flow. The test configuration starts fading at `u=−0.1*vi0` and reaches zero at `−0.2*vi0`; `vi0=n*D*sqrt(2*Ct(0)/π)` uses current rpm, with density cancelling. Stopped propulsion returns exact zero. Signed axial speed is used by the new momentum route; its radius floor is 0.5R so the legacy 0.7071R clamp does not interrupt the admitted reverse region. The radial taper and fade endpoints are C¹. **The whole model is not claimed C¹ at u=0**: existing propeller-table and mass-flow interpolation clamps remain.

These fade bounds follow the repository's [propwash research recommendation](../../roadmap-investigations/03-propeller-propwash.md), not a new validation of reverse-flow aerodynamics. The cited thesis host returned HTTP 403 during this step; the bounds remain labeled estimates. This is not a vortex-ring or four-quadrant propeller model.

## Verification

- [Runtime checks](checks.log): **20 checks pass**, including 13 rejected data mutations, 72 independent dense area/moment integrations (worst absolute component error **9.81e-9**), outer tangency derivative, reverse endpoint slopes, static control authority, exact zero-wash/stopped/cutoff loads, symmetry and a full-angle/rate sweep. Scalar loads agree exactly with helper composition; pressure-plane separation is checked explicitly.
- [Six isolated code mutations](mutations.log), [runner](check_mutations.py), are rejected: discard the centroid, remove the C¹ taper, remove reverse cutoff, move the pressure plane, accept incorrect area, and accept overlapping intervals. The overlap fixture preserves total area to isolate the ordering check. Baseline and restored copies pass.
- [P-51 legacy oracle](legacy.log): **10,001 byte-exact comparisons pass**. [All 16 default-fleet fingerprints](fingerprints.json) remain identical over 960 ticks per case. No production aircraft data or golden changes.
- [Full application suite](suite-summary.log): **109 sections pass in a fresh local clone**, no engine errors, golden flights unchanged, trimmed traces valid and states identical at 30/60/144 FPS. Only the pinned engine binary was reused; no import cache or ignored asset folders were copied. Godot skill lint: zero errors and the same 12 existing warnings before/after.

## Centroid limit and enablement decision

[Dense load experiment](check_centroid.gd), [results](check_centroid.log): integrate local rates and local swirl at 64 midpoint samples per profile interval, using the same occupancy, tail law and reference planes. Across static controls, forward flight with rates, and stall/control cases, normalized force/moment differences are below 0.2% with zero swirl. With estimated swirl factor 0.4, force errors reach **2.625 N / 203%**, moment errors **1.945 N·m / 206%** (absolute and relative maxima occur in different cases). This is a numerical approximation comparison, not measured-aircraft evidence. A single centroid is inadequate for those nonzero-swirl cases; preserve the result for E0b6 rather than tuning a swirl coefficient to hide it.

[Refinement to 128 samples](check_centroid_128.log) changes dense force norms by at most 8.91e-6 N and moment norms by 1.52e-5 N·m. The large swirl discrepancies remain; they are not a coarse-reference artifact. Reproduce with `-- --samples-per-interval=128` after the experiment command.

The reproducible opt-in configuration is confined to the test fixture: wash factors `[1.0,1.4]`, swirl zero, vertical drift 0.543, edge 0.15, reverse fade `[0.1,0.2]`. Every coefficient is labeled estimated; it is not a calibrated aircraft configuration. **Leave production Stik slipstream absent.** E0b4 must establish decay/coverage and cruise response, and the enabled path must meet the target budget before flight enablement. Nonzero swirl also needs a more accurate load integration and convergence evidence.

## Cost

[Real-session benchmark](bench_profile.gd), [raw samples](cost.log): five restored batches of 120 ticks on the shared Linux/i5-10500 host, pinned Godot 4.7.2, no concurrent application suite. Each fixture starts airborne at maximum rpm, then evolves; labels describe its initial condition.

| Initial condition | Wash off median (µs/tick) | Wash on |
| --- | ---: | ---: |
| Forward, 15 m/s, alpha 3° | 327.8 | 799.7 |
| Stall, 15 m/s, alpha 15° | 382.0 | 814.0 |
| Static | 313.9 | 618.1 |
| Spin rates | 391.9 | 838.1 |
| Reverse fade | 303.1 | 597.9 |
| Beyond reverse cutoff | 339.6 | 381.7 |

All batches complete without simulation faults. The active-wash cases exceed **500 µs/tick**; no performance gate is closed. There are still only three aerodynamic piece evaluations, but up to 45 profile intervals add geometric integration work at each load evaluation. Profile and bound any reduction before enabling; do not freeze state-dependent geometry across RK stages merely to meet the budget.

## Reproduce

```bash
python3 research/propwash/e0b3b/derive_profile.py --check
python3 research/propwash/e0b3b/test_profile.py
$(app/get-godot.sh) --headless --path app --script res://tests/test_wash_profile.gd
python3 docs/research/propwash/E0b3b/check_mutations.py
$(app/get-godot.sh) --headless --path app --script "$PWD/docs/research/propwash/E0b3b/check_centroid.gd"
$(app/get-godot.sh) --headless --path app --script "$PWD/docs/research/propwash/E0b3b/bench_profile.gd"
app/test.sh
```
