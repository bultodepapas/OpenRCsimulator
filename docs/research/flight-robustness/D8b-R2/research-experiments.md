# D8b-R2 — Additional numerical investigations

2026-10-11 · **Status: four synthetic investigations executed; no candidate adopted.**

[Plan](../../../UGLY-STIK-PULLUP-PLAN.md) · [Data](supplement.json) · [Independent force reduction](decomposition.json) · [Fingerprints](supplement-manifest.json)

These experiments complement the 18 source-based investigations in the Godot, aerodynamics and simulation reports. They distinguish parameter sensitivity, discretization sensitivity and numerical differentiation from physical validation. All use the current Stik, 25 m/s, calm air, neutral controls and zero nominal body rates. Wing downwash is instantaneous in these static calls. Production files are unchanged.

## E01 — Does the same CLmax imply the same stall departure?

**Question.** Is matching the lift peak sufficient to constrain the instability?

**Method.** Change only the input stall-blend width in an in-memory JSON copy; run the real loader so it solves each transition start again. Sweep alpha 0–25° in 0.05° increments. Read whole-aircraft lift from actual summed loads projected on the wind-normal axis, and differentiate actual Mx at p = ±1e-5 rad/s. This is not a flight test or an optimization.

| Width | Loader's positive start/end | Helper peak CL | Actual total peak CL | Maximum dMx/dp, N·m/(rad/s) |
| --- | --- | ---: | ---: | ---: |
| 4° | 12.29–16.29° | 1.09999 | 1.10221 | 17.1308 |
| 6° (production) | 12.13–18.13° | 1.09998 | 1.10511 | 11.1210 |
| 8° | 11.89–19.89° | 1.09999 | 1.10912 | 8.0846 |
| 10° | 11.59–21.59° | 1.09999 | 1.11410 | 6.2345 |
| 12° | 11.22–23.22° | 1.09999 | 1.11991 | 4.9769 |

**Finding.** All five inputs pass the loader and retain essentially the same reference lift peak. Nevertheless the maximum destabilizing roll derivative changes by a factor of **3.44**. The actual neutral-control total CL peak is close to the label in the baseline (1.105 versus 1.1); this experiment does **not** support a large baseline CLmax mismatch as the principal defect.

**Plan change.** Define acceptance for the falling lift-curve slope and roll growth, not only CLmax. Report helper, wing and total-aircraft CL separately. Choose a transition from matched evidence and uncertainty, not the width that gives the lowest roll rate. No width in this table is recommended for production.

**Limit.** Static positive-alpha/neutral-control screening does not test transient elevator loading, negative stall, recovery or a loop. The re-solved onset changes with width, so this is a complete envelope-parameter sensitivity, not a fixed-onset width-only perturbation.

## E02 — Can strip refinement remove the departure mechanism?

**Method.** Rebuild equal-area rectangular stations, the Weissinger influence matrix, effective-angle map, section slope and offsets for 3/6/12/24 strips per side. Preserve the current loader's attached total-lift slope and zero-angle lift targets. Keep tail, stall law, planform and inertia fixed. The 3-per-side reconstruction is a positive control: its tested dMx/dp values agree with production within **1.45e-10 N·m/(rad/s)**.

| Strips per side | Regenerated section slope, /rad | dMx/dp at 11° | Maximum positive dMx/dp |
| --- | ---: | ---: | ---: |
| 3 | 6.08175 | −4.08051 | 11.12097 |
| 6 | 6.48725 | −3.88719 | 10.35706 |
| 12 | 6.74750 | −3.75219 | 9.79427 |
| 24 | 6.89381 | −3.67674 | 9.47137 |

The positive-feedback peak decreases approximately **14.8%** from 3 to 24 strips per side but remains large and positive. The neutral total CL peak stays 1.10511 in this calibrated symmetric case.

**Plan change.** Increasing resolution is a verification exercise, not the primary repair. Repeat refinement on the eventual polar candidate and full maneuver before selecting production resolution. Keep geometry/discretization and parameter fitting separate: the rising derived section slope shows that this sweep recalibrates the attached oracle at each resolution. Also run a fixed-section-polar refinement when that independent input exists; do not call this a strict fixed-constitutive-law grid-convergence result.

**Limit.** No asymptotic convergence proof, CPU budget or refined-mesh flight was established. These are static samples; four meshes do not establish physical validity of the induced-flow treatment in separated flow.

## E03 — Is the destabilizing derivative a numerical-difference artifact?

At alpha 15.5°, central differences of actual total loads give:

| Perturbation ±p, rad/s | dMx/dp, N·m/(rad/s) |
| ---: | ---: |
| 1e-2 | 11.1206228341 |
| 1e-3 | 11.1207022949 |
| 1e-4 | 11.1207030896 |
| 1e-5 | 11.1207030977 |
| 1e-6 | 11.1207031000 |

**Finding.** The strong positive derivative persists over four decades of perturbation size; the widest interval differs from the smallest by about 0.00072%. The saved original sweep agrees with the supplemental native run within the required 1e-7 tolerance.

**Plan change.** Retain perturbation-size checks around candidate joins, stall peaks and blend boundaries. Use a coupled finite-time perturbation analysis for the maneuver; dividing by Jxx remains only a scalar screening measure. This local check does not validate the entire tangent dynamics or provide physical evidence for the derivative.

## E04 — Which part of the wing law produces the positive feedback?

**Method.** Independently reconstruct the current wing force/moment reduction in Python at small ±p. Verify it against Godot's `_local_loads` with tail areas zeroed only in a diagnostic copy: maximum wing derivative discrepancy is **5.33e-10 N·m/(rad/s)** across five angles. Then freeze each strip's stall blend weight at the base state while still perturbing local velocity, induced attached lift, flat-plate angle and force direction. This isolates the derivative of the transition weight; it is not a physically valid candidate model.

| Alpha | Complete wing dMx/dp | Wing dMx/dp with frozen weights | Contribution from changing blend weights |
| --- | ---: | ---: | ---: |
| 11° | −4.1496 | −4.1496 | 0 |
| 13° | +2.2358 | −4.0650 | +6.3008 |
| 14° | +7.8025 | −3.6312 | +11.4338 |
| 15.5° | **+11.1307** | **−2.7481** | **+13.8788** |
| 18° | −0.5370 | −1.8317 | +1.2947 |

At 15.5°, the tail contributes about −0.0100, leaving the previously measured +11.1207 total. At 11°, the production total also contains the global/local blend; the total-minus-local-wing residual there is **not** just the tail.

The strip law is `CL = (1-w) CL_attached + w CL_plate`. Its differential includes `(CL_plate - CL_attached) dw/dp`. Near the falling branch this term dominates the stabilizing contributions. This local decomposition identifies a specific model term for investigation; it does not show that the term should be deleted. Real changing separation can produce autorotation too.

**Plan change.** Record the transition-weight contribution as well as per-wing loads in development telemetry. Test the slope and regularity of the complete joined polar. Reject a repair that simply freezes weights, deletes autorotation, or adds enough damping to mask an unsupported lift collapse.

## Reproduction and integrity

```powershell
python research/flight-robustness/d8b-r2/run_supplement.py --godot .tools/Godot_v4.7.2-stable_win64_console.exe
```

Uses [supplement.gd](../../../../research/flight-robustness/d8b-r2/supplement.gd) and [run_supplement.py](../../../../research/flight-robustness/d8b-r2/run_supplement.py). It requires the original `results.json` to compare against the preceding native baseline. The driver rejects engine errors/nonzero exit, missing outputs, nonfinite values, wrong scenario counts, a failed 3-strip positive control, an independent wing-reduction mismatch or source changes during the run. All app GDScript/JSON/project files outside `.godot` and both supplemental scripts are fingerprinted. The prior 28 flight trials and their artifacts are preserved.

This is verification and sensitivity evidence. None of these four experiments supplies a measured Stik polar, measured stall growth rate or a validated replacement setting.
