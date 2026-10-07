# E0b4 — numerical sensitivity tables

**Status: generated numerical evidence; not calibrated flight data.**
Regenerate with python3 research/propwash/e0b4/summarize.py. Source: [results.json](results.json).
Ranges are extrema of the stated finite grid, not statistical confidence bounds or continuous-domain bounds.

## Fixed operating points

| Condition | Speed m/s | Throttle | RPM | Alpha ° |
| --- | ---: | ---: | ---: | ---: |
| baseline_trim_10 | 10 | 0.1448 | 4008.62 | 12.1569 |
| baseline_trim_15 | 15 | 0.2844 | 5174.25 | 4.2603 |
| baseline_trim_25 | 25 | 0.6814 | 8488.84 | 0.6862 |
| axial_full_0 | 0 | 1.0000 | 11149.00 | 0.0000 |
| axial_full_5 | 5 | 1.0000 | 11149.00 | 0.0000 |
| axial_full_15 | 15 | 1.0000 | 11149.00 | 0.0000 |
| axial_full_25 | 25 | 1.0000 | 11149.00 | 0.0000 |

## Occupancy and pressure proxy

Fractions use neutral geometric area; pressure averages use the unchanged aerodynamic area. These are load-occupancy weights and area-weighted pressure proxies, not measured coverage or force multipliers.

| Condition | H occupancy % | V occupancy % | Centre q / q∞ | H mean q proxy (Pa) | V mean q proxy (Pa) |
| --- | ---: | ---: | ---: | ---: | ---: |
| baseline_trim_10 | 0.00…54.63 | 47.94…99.91 | 1.417…1.584 | 61.25…80.18 | 73.29…96.40 |
| baseline_trim_15 | 32.76…56.18 | 90.49…100.00 | 1.213…1.295 | 147.14…159.90 | 163.98…177.73 |
| baseline_trim_25 | 52.65…56.34 | 90.64…95.40 | 1.196…1.270 | 421.03…439.20 | 449.61…479.75 |
| axial_full_0 | 37.89…39.39 | 71.56…73.31 | undefined at V=0 | 33.19…105.68 | 63.65…199.67 |
| axial_full_5 | 41.51…43.13 | 76.16…77.88 | 12.584…24.363 | 86.63…164.74 | 148.15…289.26 |
| axial_full_15 | 47.62…49.43 | 83.49…85.02 | 2.893…3.891 | 258.11…328.53 | 351.94…470.83 |
| axial_full_25 | 51.86…53.81 | 88.15…89.37 | 1.581…1.821 | 494.57…546.59 | 575.67…658.97 |

## Aerodynamic derivatives at the no-wash 15 m/s trim

Same state, controls and frozen RPM on/off. Aerodynamic + tail-wash loads only; propulsion/gravity omitted here. Cma is quasi-static; Cma_held freezes the downwash lag-state input. Rates use q·c/(2V), r·b/(2V); angles/controls use radians. Percentage change is 100·(on/off−1), meaningful only with the same sign/definition.

| Coefficient | Off | On range | Change % | Selig figure-typical endpoints change % |
| --- | ---: | ---: | ---: | ---: |
| Cma | -0.866742 | -0.965017…-0.868565 | 0.21…11.34 | 2.91 |
| Cma_held | -1.587942 | -1.755691…-1.670218 | 5.18…10.56 | 7.23 |
| Cmde | -0.852804 | -1.011586…-0.919869 | 7.86…18.62 | 14.66 |
| Cmq | -7.550955 | -8.100964…-7.787914 | 3.14…7.28 | 5.76 |
| Cnb | 0.121424 | 0.132219…0.137771 | 8.89…13.46 | 12.67 |
| Cndr | -0.066783 | -0.086127…-0.079461 | 18.98…28.97 | 27.32 |
| Cnr | -0.131900 | -0.148069…-0.142694 | 8.18…12.26 | 11.60 |

## Untrimmed low-speed alpha partials

5 m/s, alpha=beta=0, neutral controls, full RPM. These are different partials of a lagged system, not dynamic-stability conclusions.

| Partial | Off | On range |
| --- | ---: | ---: |
| Cma | -0.768648 | 0.954317…4.000322 |
| Cma_held | -1.484677 | -4.080882…-2.917827 |

## Static full-RPM controls

Extrema across 17 sampled deflections within each control's actual throw and across the 81 grid points. Not proven continuous-control extrema. Positive body My is nose-up; positive Mz is nose-right. Each control is varied alone.

| Control moment | Current law (N·m) | Lag CL input forced to zero (N·m) |
| --- | ---: | ---: |
| elevator | -5.501…4.690 | -5.562…4.457 |
| rudder | -3.996…3.996 | -3.996…3.996 |

At V=0, CL_wing=0.09295183=CL_wing0. The E0a2 intercept cancels: the neutral effective tail angle is 0.02087835 rad. Forcing the CL input to zero without re-deriving incidence changes it to 0.03094484 rad. This perturbation is **not** a physically corrected no-downwash model.

## Full-model retrimmed modes

Nine wash endpoint pairs × three speeds; edge=0.15 and drift=0.543 only. Full Dynamics, propulsion and the existing downwash lag included, wash transport absent. Existing block-projected modal analysis; cross-axis coupling is not diagonalized.

| Speed m/s | Short-period ζ off | Short-period ζ on | Dutch-roll ζ off | Dutch-roll ζ on | Signed spiral e-fold time on (s) |
| --- | ---: | ---: | ---: | ---: | ---: |
| 10 | 0.5993 | 0.5676…0.5765 | 0.3384 | 0.3392…0.3398 | -1.674…-1.670 |
| 15 | 0.7840 | 0.7975…0.8033 | 0.2430 | 0.2482…0.2501 | -11.922…-11.851 |
| 25 | 0.8091 | 0.8297…0.8382 | 0.2277 | 0.2316…0.2330 | -30.540…-30.465 |

Negative spiral time means divergence in this modal convention; damping of the oscillatory modes alone is not a whole-aircraft stability claim.

Finite-difference h→h/2 worst normalized change: 5.2021701e-07, normalized by max(1, |refined coefficient|).
