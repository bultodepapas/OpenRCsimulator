# R02 attached-flow circulation candidate

This is a research-only, attached-domain comparison. It does not change the runtime, aircraft data, goldens, or the open full-aircraft yaw-damping gate. The candidate is limited to a planar unswept wing represented by straight horseshoe panels, attached linear sections, prescribed in-plane flow, and strictly positive axial velocity at every solve and force sample. It is not a full-envelope or validated aircraft law.

The current full-aircraft yaw discrepancy remains open. See the [R11 damping diagnosis](../R11/damping-lag-diagnostic/README.md) and the [physics audit](../../README.md).

## Attached circulation solve

For collocation panel `i` and source panel `j`, the candidate uses the same influence convention as [`AircraftData.strip_influence`](../../../../../app/physics/aircraft_data.gd) and the independent [D11f reference](../../../../../research/aero/d11f/wing_yaw_damping.py):

```text
K_ij = -0.5 * c_j * w_horseshoe_z(i,j) - delta_ij / (2*pi)
E    = inverse(I + a0*K)
```

`w_horseshoe_z` is the induced vertical velocity per unit circulation at the 3/4-chord collocation point. The full horseshoe is used in this solve; the diagonal `1/(2*pi)` correction removes the local two-dimensional bound-vortex term. Source-panel chord `c_j` belongs in `K_ij`; receiving-panel chord `c_i` belongs in the circulation conversion below.

Starting from the D11f rate-dependent attached equation, define `g_i = u_i * CL_i` and multiply row `i` by `u_i`:

```text
CL_i/a0 + sum_j K_ij * (u_j/u_i) * CL_j
    = w_i/u_i + alpha_zero_i + incidence_i

(I/a0 + K) * g = w + u * (alpha_zero + incidence)
g       = a0 * E * (w + u * (alpha_zero + incidence))
CL_i    = g_i / u_i
Gamma_i = 0.5 * c_i * g_i
```

This rewrite is algebraically equivalent to the direct rate-dependent linear solve while every `u_i > 0`. `K` and `E` are dimensionless, `a0` is per radian, `g` is m/s, and `Gamma` is m²/s. A synthetic tapered-chord fixture independently checks both the source chord in `K` and the receiving chord in `Gamma`. The production slope is a whole-aircraft target, and each `alpha_zero_i` is reconstructed from fitted strip `CL0`; neither is presented as a measured airfoil property.

The solve refuses zero or reverse axial flow. A tested near-zero positive panel (`u_min` about `1.5e-5 m/s`) gives algebraic `|CL|` about 19,885, illustrating poor conditioning before the exact refused boundary. No epsilon floor is used.

## Geometry lanes and force closure

The candidate keeps two chord values separate. For the production export, it uses the unrounded strip chord `S/b = 0.464515/1.524 = 0.3047998687664042 m`; the exported `mean_chord_m` is rounded to `0.3048 m`. The independent D11f lane uses its literal authored `c = 0.3048 m`. With these lanes separated, the production `E` export matches to a maximum absolute error of `2.22e-16`. The earlier v2 result used the rounded chord for both lanes and recorded a `1.17e-7` production-map difference; v3 corrects only that geometry input.

The force comparison follows D11f coordinates (`x` downstream, `y` right, `z` up). Circulation is piecewise constant on each span panel. The candidate evaluates trailing-leg-only induced downwash once at the panel center, then samples prescribed external/local `u(y), w(y)` along the bound line with Gauss-Legendre quadrature:

```text
dFx_KJ = -rho * Gamma_i * (w(y) - w_down_i) * dy
dFz_KJ =  rho * Gamma_i * u(y) * dy
dNz    = y * dFx_KJ
P_airframe = -F dot U_D11f
```

This is a specified discrete closure. The first draft evaluated trailing-leg velocity at each bound-line quadrature point. At a shared panel edge, the circulation jump made the pointwise velocity grow approximately as inverse distance, and force quadrature did not converge. The preserved [v1 result](../../../../../research/physics-audit-2026-10-14/remediation/r02-circulation-candidate/candidate-results-v1.json) records that failed probe: with a `-0.0592177 m²/s` adjacent-panel circulation jump at `y=-0.254 m`, the sampled downwash reached about `4,712 m/s` at `1e-6 m` and `47,123,908 m/s` at `1e-10 m` from the edge. The v2/v3 panel-center choice defines a finite discrete evaluation; it does not provide a continuous finite-core wake, a converged continuous self-wake solution, or powered-wing coupling.

The optional profile comparison is the D11f expression `dFx_profile = 0.5 * rho * CD0 * c_i * (u²+w²) * dy`. The borrowed `CD0=0.0434` comes from a whole-aircraft polar and is used only as a numeric comparison assumption, not as a measured wing-section coefficient. The runtime's whole-aircraft induced-drag term is not added to the candidate Kutta–Joukowski force.

## Reproduced checks

The input export describes a six-strip Stik wing with span `1.524 m`, area `0.464515 m²`, target slope `6.0817546481 rad⁻¹`, speed `15 m/s`, and density `1.225 kg/m³`. The reconstructed equivalent `alpha_zero` mean is `0.0234270666 rad`; its six-strip spread is about `1.04e-17 rad`.

| Check | v3 result |
| --- | ---: |
| Production exported `E` map, maximum absolute error | `2.22e-16` |
| Direct rate-dependent solve versus dimensional `g` solve, maximum absolute difference in `CL` | `5.55e-16` |
| Taper fixture, direct solve versus `g` solve, maximum absolute difference in `CL` | `1.67e-16` |
| Taper fixture, `Gamma_i = 0.5*c_i*g_i`, maximum absolute error | `0 m²/s` |
| D11f six-panel zero-camber yaw reproduction, maximum absolute error | `3.95e-16 N·m` |
| Uniform-flow mirrored `Gamma`, maximum pair difference | `9.99e-16 m²/s` |
| Uniform-flow integrated yaw at 4 degrees, zero yaw rate | `1.18e-16 N·m` |
| Density and velocity similarity, maximum absolute ratio error | `1.19e-10` |

For the uniform attached 4-degree case, minimum panel-center downwash is `+0.2833016 m/s`, induced drag is `+0.5285010 N`, and induced power on the airframe is `-7.9082033 W`. The power identity `P_airframe = -u * D_i` differs by `8.0e-15 W` with the stated axes. These are internal sign and consistency checks for this discrete model.

The local-flow quadrature fixture uses `u(y)=V*cos(alpha)-r*y`, `w(y)=V*sin(alpha)` at `alpha=4 degrees` and `r=0.05 rad/s`. Two-point quadrature reproduces the analytic quadratic-velocity profile force to `8.9e-16 N` and its yaw moment to `8.3e-17 N·m`. One-point midpoint quadrature misses the yaw moment by `9.93e-5 N·m`. This demonstrates the sampled-flow and moment-arm integration for the stated fixture; it does not validate the borrowed `CD0` as section data.

The next table compares wing-only `Cnr` values at the existing central difference `r=±0.05 rad/s`. The R02 column uses the current fixed-`E` whole-aircraft polar expression. Candidate profile columns use the borrowed D11f profile assumption; `q=1` is panel-center midpoint sampling and `q=16` integrates along the bound line.

| Angle | Current R02 fixed-`E` polar | Candidate KJ only, q=16 | Candidate KJ plus profile, q=1 | Candidate KJ plus profile, q=16 |
| ---: | ---: | ---: | ---: | ---: |
| 4° | `-0.0118401` | `-0.0000063123` | `-0.0140369` | `-0.0144377` |
| 11° | `-0.0054262` | `+0.000325829` | `-0.0134806` | `-0.0138750` |

These columns compare different force closures and polar semantics. The residual does not establish which closure is physical and does not close the full-aircraft yaw gate. In the panel refinement at 4 degrees, the profile-assumption `Cnr` changes from `-0.01443774` at six panels to `-0.01447993` at 192 panels; the last 96-to-192 step is `4.97e-7`. On 96 panels, increasing force quadrature from order 2 to 32 changes that value by less than `5e-15`. This convergence belongs only to the specified center-downwash discrete closure and tested yaw field. It is not evidence of continuous-wake or physical convergence.

## Scope and outstanding evidence

The tested candidate has no section polar, Reynolds-number dependence, separation, dynamic stall, sweep, spanwise crossflow, rotor-wake field, control deflection, or coupled tail/fuselage forces. Its circulation solve receives prescribed planar flow; its force quadrature samples that flow along a bound line. It does not couple geometry-resolved surface immersion to circulation or force. Stagnation and reverse axial flow are refused at both collocation and force-quadrature samples.

The independent [NASA/TM-2016-219349 record](https://ntrs.nasa.gov/citations/20170000682) describes discrete horseshoe derivative calculations in an unseparated, inviscid, incompressible domain and reports comparisons in a low-angle range. That bounds the context; it does not validate this candidate or the simulator. Further admission would require sourced section properties, a sourced and resolution-tested wake/force law, powered and crossflow cases, and independent physical evidence. The full-aircraft R02 yaw comparison remains a normal open gate.

## Dated nonlinear-feasibility follow-up (2026-10-16)

The [nonlinear feasibility evidence](../../../../../research/physics-audit-2026-10-14/remediation/r02-circulation-candidate/nonlinear-feasibility-20261016/README.md) tests a memoryless nonlinear extension using the Stik whole-aircraft fallback proxy (`CL0=0.1068`, `CLa=4.58 rad⁻¹`, `CLmax=1.1`, `CLmin=-0.8`, `CD90=1.2`, 6° stall blend), six panels (`b=1.524 m`, `c=0.3048 m`, `S=0.4645152 m²`), `V=15 m/s`, and `ρ=1.225 kg/m³`. At 20° and `r=0.05 rad/s`, 29 fixed-seed solves found 10 distinct roots for identical inputs; an independently reproduced pair differs by `1.524 N·m` in KJ yaw, with normalized residuals below `7e-16`. Using induced-adjusted local speed also produced 10 roots. This rejects promotion of this specific memoryless full-envelope closure; it is not an aircraft prediction or physical validation. The evidence records exact inputs, source and artifact hashes, and dependency pins. The files were copied byte-for-byte from `D:\OpenRC-release-v012-temp\yaw-circulation-prototype-20dc6efe`; their absolute path constants and setup HEAD field remain as recorded, not rewritten or treated as pinned checkout provenance.

For this nonlinear follow-up, rerun only from a disposable copy with its repository,
output and imported-prototype paths redirected to a fresh directory. The retained
scripts preserve their original absolute paths and can overwrite their original
scratch outputs if run unchanged. The local `receipt.json` binds all seven retained
artifacts and summarizes the independent equation/force check.

## Reproduction and identities

The v3 run used Python `3.11.9`, NumPy `2.4.6`, and SciPy `1.17.1` from the default interpreter recorded in the result JSON. These dependency pins are listed in [`requirements-v3.txt`](../../../../../research/physics-audit-2026-10-14/remediation/r02-circulation-candidate/requirements-v3.txt). The script uses SciPy's `roots_legendre`, dense inverse, and dense solve; it contains no hand-written quadrature generator or matrix solver.

From the repository root in PowerShell, verify the interpreter and run the probe:

```powershell
python -c "import sys,numpy,scipy; print(sys.executable); print(sys.version.split()[0], numpy.__version__, scipy.__version__)"
python -m py_compile research/physics-audit-2026-10-14/remediation/r02-circulation-candidate/circulation_candidate-v3.py
python research/physics-audit-2026-10-14/remediation/r02-circulation-candidate/circulation_candidate-v3.py
```

The last command writes only [`candidate-results-v3.json`](../../../../../research/physics-audit-2026-10-14/remediation/r02-circulation-candidate/candidate-results-v3.json). The result records the interpreter path, dependency versions, input hashes, production source identities, and candidate-source hash.

| Artifact | SHA-256 |
| --- | --- |
| Superseded pointwise source v1 ([file](../../../../../research/physics-audit-2026-10-14/remediation/r02-circulation-candidate/circulation_candidate.py)) | `48d0f37a933eff00fb8c1d890dbae4925065f27704835629930e3ad8c4607ada` |
| Superseded pointwise result v1 ([file](../../../../../research/physics-audit-2026-10-14/remediation/r02-circulation-candidate/candidate-results-v1.json)) | `c74f00f3fad57f27be9bbef1607a8b69f762075699336a689dba01e37c989465` |
| Panel-center source v2 hash embedded in its result | `52b0a4684ecaa742948644ebc1f51c87d9c60846653fae61083a6e1295e0905` |
| Panel-center result v2, retained history ([file](../../../../../research/physics-audit-2026-10-14/remediation/r02-circulation-candidate/candidate-results-v2.json)) | `0027c9065da5e90a7854fb75206d5a6868a2a41ea4a7a0755b35404e50a685d7` |
| Current retained v2 script bytes ([file](../../../../../research/physics-audit-2026-10-14/remediation/r02-circulation-candidate/circulation_candidate-v2.py)); differs from its result-bound source identity | `a494501305e9607b49d26ae4cd491d108b3284236e722824e6000147254a8bc4` |
| Final attached-domain source v3 ([file](../../../../../research/physics-audit-2026-10-14/remediation/r02-circulation-candidate/circulation_candidate-v3.py)) | `d642014e08b415a5c88fb475bdd7e52ff90aecfb8e738a1f473856d9ded8c1c0` |
| Final result v3 ([file](../../../../../research/physics-audit-2026-10-14/remediation/r02-circulation-candidate/candidate-results-v3.json)) | `9867ffdd4e7bb7290b38eee3df2c271c8330e822f739fa677205192dbe580ca1` |
| v3 dependency pins ([file](../../../../../research/physics-audit-2026-10-14/remediation/r02-circulation-candidate/requirements-v3.txt)) | `aac4b057efd278d60500643489f11048a56091c46634f101ad3ed06055b632ad` |
