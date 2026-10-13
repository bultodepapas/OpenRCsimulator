# HELI-04: Johnson mean inflow reference

This is the independent Python reference and small known-answer oracle for the static mean-inflow slice of HELI-03a. It is not the complete HELI-03 implementation or evidence of physical validation. The reference is in `research/helicopter/reference/` and uses only the Python standard library.

## Sources and interpretation

- Johnson, *Model for Vortex Ring State Influence on Rotorcraft Flight Dynamics*, NASA/TP-2005-213477, §3 and Tables 3–4 (printed pp. 22–24; Table 3 on p. 23 and Table 4 on p. 24): [NASA report PDF](https://rotorcraft.arc.nasa.gov/Publications/files/Johnson_TP-2005-213477.pdf). Table 3 supplies the baseline momentum splice and VRS correction. Table 4 supplies the A, B, C, D, N, X, E, and M anchors. The momentum relation solved here is `v*sqrt(x²+(z+v)²)=1`.
- Khromov and Rand, ICAS 2008 paper 085, printed p. 2, Eq. (1.4): [paper PDF](https://icas.org/ICAS_ARCHIVE/ICAS2008/PAPERS/085.PDF). This reproduces Hayden's `k_G = 0.9926 + 0.03794*(2R/h)²` factor.

The Johnson variables are normalized by hover inflow `v_h = sqrt(T/(2ρπR²))`: `z = V_z/v_h`, where climb is positive and descent negative; `x = |V_x|/v_h`; and `v/v_h` is positive downward. `f` is the VRS increment suppression factor, in `[0,1]`, and `κ` multiplies the resulting induced inflow. Table 4's normalized anchors are A=-1.5, B=-2.1, C=0.75, D=-0.2, N=-0.45 with `(z+v)_N=0.85`, X=-1.5 with `(z+v)_X=1.25`, E=-2, and M=0.95.

The baseline endpoints shift to `A_x=A+0.2(x/C)²` and `B_x=B+0.2(x/C)²`; when `x/C>0.5`, the additional B shift is `0.7(A_x-B_x)(2x/C-1)³`. Between the shifted endpoints the reference fits `v=bz+cz²+dz³` to the normal momentum root and slope at A and the windmill-brake root at B. The momentum relation is `v*sqrt(x²+(z+v)²)=1`. Root finding brackets each monotonic interval separated by stationary points, so descent does not depend on a fixed-point iteration choosing a branch accidentally.

Table 3 moves the VRS boundaries with crossflow using `z_N=0.5(N+X)+0.5(N-X)(1-(x/M)²)^0.2`, `z_X=0.5(N+X)-0.5(N-X)(1-(x/M)²)^1.5`, and `z_E=E+(z_X-X)`; `z_D=D`. It defines cubic corrections to `z+v` over D-to-N, N-to-X, and X-to-E, blended by `f`. Two apparent Table 3 errors are present in the printed report and are handled explicitly: §3.2.3 describes the `E < z < X` segment but says to match at D; this implementation uses E, the endpoint of that interval. The printed cubic derivative says `b + 2cz + 2cz²`; differentiating the printed polynomial gives `b + 2cz + 3dz²`, which is used here. For the outer E-to-X segment, the reference honors the stated zero constant coefficient and matches the value and slope at X and zero value at E; it does not impose a slope match at E.

The Table 3 law has literal transition discontinuities. With `f=1`, approaching the published crossflow limit `M=0.95` from below versus above gives ratios `1.14508296835` versus `1.00539832760` at `z=-1.3`, and `0.89880059144` versus `1.00289100744` at `z=-0.7`. The baseline splice at `C=0.75` also has a smaller jump at `z=-1.428`: `1.31603547024` just below versus `1.31962823890` just above, with `f=0`. These are captured as source-law behavior in tests; no smoothing is added. They are an integration gate: the law is not session-ready until the dynamic-flow refinement explicitly handles these seams.

For dimensional targets, the signed-thrust extension reflects the normalized climb input and induced velocity for negative thrust. The optional Hayden factor is applied only to positive, upright thrust. Its raw expression tends to `k_G=0.9926`, so the reference uses `0.9926/k_G` as the induced-velocity multiplier to make far-field clearance exactly unity. It clamps `h/R` to at least `0.5`, following the HELI-01 plan. This is a near-hover scalar correction based on Eq. (1.4), not the full ICAS forward-flight reflected-upwash model in Eqs. (2.1)–(2.8). The `height_over_radius=-1` sentinel disables it.

## API and artifacts

`johnson_inflow.py` exposes:

- `normalized(vz, vx, instability=1, loss=1)` → `{ok, ratio}`. `vz` and the magnitude `vx` are already normalized by `v_h`; `instability` is `f`; `loss` is `κ`.
- `target(thrust, density, radius, climb, crossflow, height_over_radius=-1, loss=1, instability=1)` → `{ok, velocity, hover, ground_factor}`. Inputs are SI quantities, climb is positive upward, and crossflow is treated as a magnitude. The returned induced velocity is positive downward for positive thrust.
- `hayden_ground_factor(height_over_radius)` → the far-field-normalized Hayden multiplier.

`oracle.json` stores 11 normalized cases and 2 dimensional target cases, rounded to 12 decimal places. Its anchors include hover `1`, axial climb `z=1` ratio `0.61803398875`, forward hover `x=1` ratio `0.786151377757`, windmill `z=-2.5` ratio `0.5`, and Table 4's N/X full-VRS results `1.3` and `2.75`. The tests derive analytic momentum answers independently, check the baseline splice from separate endpoint constraints, and verify Table 4 anchors, symmetry, ground-effect behavior, oracle reproducibility, and the known seams.

Run from the repository root:

```powershell
python -m unittest discover -s research/helicopter/reference -p 'test_*.py' -v
python research/helicopter/reference/make_oracle.py --check
```

Recorded result: 16 tests passed; oracle check reported `oracle check: OK (oracle.json)`. Run `python research/helicopter/reference/make_oracle.py` only when intentionally regenerating the checked oracle.

This reference models steady mean inflow only. It has no rotor/induced-flow time response, blade-resolved wake, transient VRS development, or full ground-effect flow field. Software agreement with this oracle is implementation evidence, not flight-data validation.
