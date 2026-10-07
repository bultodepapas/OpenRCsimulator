# E0b4 — Stik wash sensitivity and evidence limits

2026-10-07 · **Status: sensitivity study complete; Stik calibration and production enablement remain open.**

The existing experimental wake predicts material changes in tail authority at cruise as well as low speed. The published sources do not identify one calibrated Stik decay factor or coverage law. Keep the production Stik unconfigured; retain these results as sensitivity evidence for E0b5–E0b7. No runtime, aircraft data or golden flight was changed by E0b4.

## Sources and parameter choices

[Primary-source audit](sources.md): Selig's Fig. 5 gives approximate induced-speed endpoints of 0.8 and 1.8 times the disc-induced increment, with a transition over inflow ratio 0–0.75. These are generic graph readings, not Stik measurements. Khan's static radial fit describes another propeller and includes wake spreading; transferring its normalized stations to the Stik is a separate model-form comparison. Neither source establishes powered Stik cruise derivatives. Third-party publications are linked, not redistributed.

The finite grid uses static factor `[0.8, 1.1, 1.4]`, forward factor `[1.4, 1.7, 1.9]`, occupancy-edge fraction `[0.05, 0.15, 0.30]` and vertical drift `[0, 0.543, 1]`. All are estimated sensitivity inputs. The E0b3b nominal geometry regularization is edge 0.15 and drift 0.543; no measurement selects these values. Swirl is zero. A separate case evaluates Selig's approximate `[0.8, 1.8]` endpoints, and another retains `[2, 2]` as an ideal-speed reference. The latter uses the same experimental geometry, so it is not an independently validated whole-tail upper bound.

The velocity factor scales the induced increment, not total speed or whole-tail dynamic pressure. At rest, centre pressure is `ks² T/(4 A_disc)`; a ratio to zero free-stream pressure is undefined. The smooth edge weights loads, rather than describing a measured radial velocity profile. Pressure averages in this study are occupancy-weighted proxies. Ranges are sampled extrema, not statistical confidence intervals or continuous-domain bounds. Changing the two speed endpoints tests uncertainty at the fixed tail stations; it does not fit a spatial decay law.

## Experiment

[Sweep](../../../../research/propwash/e0b4/sweep.gd) uses the actual E0b3b fixture and physics modules. Each of 81 configurations is evaluated at seven fixed conditions: baseline no-wash trims at 10/15/25 m/s, and neutral axial states at 0/5/15/25 m/s with full 11,149 rpm. State, controls and rpm are identical for each on/off comparison. The seven-point source-typical and ideal references bring the checked total to 581 conditions. [Tables](tables.md) list throttle, rpm, alpha, occupancy, pressure, derivatives, static controls and modes; [raw results](results.json) preserve 15 source hashes.

The aerodynamic partials include aero plus wash, excluding propeller forces and gravity. Rate derivatives use `q c/(2V)` and `r b/(2V)`; angle/control derivatives use radians. Quasi-static `Cma` resettles wing downwash, whereas `Cma_held` freezes the downwash lag-state input. The existing global aero correction still responds to current minus lagged wing lift. These are different partials of a lagged system.

Separately, nine endpoint pairs are retrimmed at three speeds with nominal edge/drift, full Dynamics, propulsion and the existing wing-downwash lag. Three baseline and three source-typical cases give 33 mode solves. This is the existing block-projected modal analysis, not a full coupled eigensystem. Wash transport is absent; modal checks do not span the edge/drift extremes.

## Findings

- At the no-wash 15 m/s trim (throttle 0.2844, 5,174 rpm, alpha 4.2603°), elevator authority rises **7.86–18.62%** and rudder authority **18.98–28.97%**. Pitch damping rises 3.14–7.28%; yaw stiffness rises 8.89–13.46%. Selig's approximate endpoints give +14.66% elevator and +27.32% rudder. An old +12% cruise allowance is not a universal physical acceptance criterion; reducing factors merely to pass it would be an unsupported fit.
- Full-rpm centre pressure ratios at 5 m/s span **12.58–24.36**, but at 15 m/s baseline trim they span **1.21–1.29**. Neither is a multiplier for the whole tail. Horizontal geometric occupancy at the 10 m/s trim spans 0–54.63% as the estimated drift displaces the wake: geometry/flow direction matters as much as a speed factor.
- Static sampled elevator moment spans −5.501 to +4.690 N·m and rudder moment ±3.996 N·m. These are model predictions across the parameter grid and 17 deflections per control. At zero speed, forcing lagged wing CL to zero while preserving E0a2 incidence changes its intercept compensation; it is a parameter perturbation, not a corrected physical downwash model.
- At untrimmed 5 m/s/full rpm, quasi-static `Cma` changes sign while the lag-held partial stays negative. This is a sensitivity finding, not a dynamic stability verdict. The retrimmed oscillatory modes remain damped at the tested points; the signed spiral e-fold times remain divergent. Do not summarize the result as a stable aircraft.

The separate [donor-profile integration](donor-profile.json) applies Khan's static radial equation at the actual tail reference stations, `x/D = 3.721/3.787`. Unknown hub radius is varied as `Rh/Rp = [0, 0.1, 0.2]`; no value is selected. Geometric area-mean pressure divided by centreline pressure is **0.475–0.506 horizontally** and **0.758–0.779 vertically**, compared with the experimental static occupancy proxies of 0.382 and 0.720. Thus even at matched centreline speed, radial shape changes the pressure averaged over a surface. This calculation resolves spanwise chord-weighted area at fixed reference x, not chordwise wake development, actual Stik measurements or tail forces. The source fit is static and uses another propeller; it supplies no cruise calibration.

## Proof and next work

[Independent checker](../../../../research/propwash/e0b4/check_results.py) checks source freshness, grid completeness, matched conditions, thrust-table interpolation, momentum conservation, speed/pressure identities, static invariance, derivative units/signs and all 33 mode solves. Six isolated corruptions are rejected ([log](checks.log)). Central-difference refinement from 1e-4 to 5e-5 changes coefficients by at most 5.21e-7, normalized by `max(1, |refined coefficient|)` ([engine log](sweep.log)). This is numerical verification, not measured aerodynamic validation.

A fresh clone with the tracked diff and nonignored new files reproduced `results.json` and `tables.md` byte for byte, without an imported app cache. The donor calculation also has a regeneration check and 128→256 midpoint refinement. [Verification log](verification.log). App static lint remains at zero errors and 12 pre-existing warnings; no app file was edited in this step. The full app suite was last run for the preceding [E0b3b implementation](../E0b3b/README.md), not repeated for this research-only change.

E0b5 can now investigate transport through the existing state contract using an explicitly estimated configuration. E0b6 must address the known nonzero-swirl centroid error. E0b7 needs recorded Stik configuration, rpm/throttle and independent static/taxi/takeoff observations before fitted parameters or enablement. The E0b3b active-wash cost of 598–838 µs/tick also remains unresolved; E0b4 did not remeasure performance or change the runtime.

Reproduce from the repository root with the E0b3b fixture present:

```sh
$(app/get-godot.sh) --headless --path app --script "$PWD/research/propwash/e0b4/sweep.gd" -- --output="$PWD/docs/research/propwash/E0b4/results.json"
python3 research/propwash/e0b4/check_results.py --probes
python3 research/propwash/e0b4/summarize.py
python3 research/propwash/e0b4/donor_profile.py
python3 research/propwash/e0b4/donor_profile.py --check
```
