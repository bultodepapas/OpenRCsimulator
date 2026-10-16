# Bounded circulation prototype evidence

Status: research-only feasibility check. No production files were edited. The experiment is not a physical validation and does not recommend changing the runtime aerodynamic law.

## Reproduction and identity

The scripts imported the live working tree at `C:\DEVELOPMENT\OpenRCsimulator`, not a pinned checkout, and use the six-panel D11f geometry. The JSON `repo_head` field records setup context `20dc6efe93cfc0a4149ed7617e0d6e5f6075d59e`; the checkout advanced to `8b8574da` during the work, so that field is not an enforced source identity. The six input SHA-256 values below are the file identities recorded by the run; an independent review confirmed they match the current files. Root also confirmed the relevant physics/simulation/Stik inputs are unchanged relative to `f1ee9e78`.

Source SHA-256:

- candidate-v3 kernel: `d642014e08b415a5c88fb475bdd7e52ff90aecfb8e738a1f473856d9ded8c1c0`
- D11f reference: `b71405f04f9385a27a733c2b719560ca6032f682289a53d996ed338b8ef737e8`
- Stik JSON: `bdcf4d64c45676a112d837513ee1eef7ed017c39fa8b39b21236cd801950f723`
- `aero.gd`: `79231204065bd08ffe5bb576885755a514370ab6767523bdb688397c6097fe44`
- `wing_polar.gd`: `fee5fe7c2f8b13f30e9275675ed421eb6c8a45d62d0d91958ed155b12b4db3be`

Environment: CPython `3.13.11`, NumPy `2.4.6`, SciPy `1.17.1`, invoked with `uv run --no-project --with numpy==2.4.6 --with scipy==1.17.1 --python 3.13 python <script>`.

`prototype.py` checks the D11f/candidate-v3 linear operator identity, the small-angle tangent, zero-flow and axial-flow sign crossings, a proxy lift curve, and finite-difference/panel-count sensitivities. `multiroot_focused.py` and `multiroot_effectivespeed.py` use the same fixed external flow at every seed and retain each converged circulation, effective angle, residual, and KJ force in JSON.

## Model equations

Circulation variable `g = 2 Gamma / c` is in m/s. The dimensionless influence matrix is `K_ij = -0.5 c_j H_ij - delta_ij/(2 pi)`. The attached operator is

`(I / a0 + K) g = w + u alpha0`.

The nonlinear prototype used for the main scan was

`g_i = |V_external,i| Cl(atan2(w_i - (K g)_i, u_i))`.

It preserves the attached first-order tangent for positive `u`; direct candidate-v3 and D11f circulation agree to floating precision. A second check replaced the external speed multiplier with the induced-adjusted local magnitude `sqrt(u_i^2 + (w_i - (K g)_i)^2)`. This change also preserves the attached tangent and is recorded separately; it does not remove the multiple roots below.

Both root solvers use dimensionless unknown `x = g / V_ref` and accept only a finite normalized infinity residual `||x - RHS/V_ref||_inf <= 1e-10`, with `V_ref = max_i sqrt(u_i^2+w_i^2)`. Exact zero input has a separate exact `g=0` root; there is no dimensional epsilon or absolute m/s acceptance floor.

## Multiroot result

For the six-panel Stik-size proxy at external `alpha=20 deg`, `r=0.05 rad/s`, and speed `15 m/s`, every initial seed uses the same external panel arrays:

- `u = [14.1271393118, 14.1144393118, 14.1017393118, 14.0890393118, 14.0763393118, 14.0636393118] m/s`
- `w = [5.13030214989, 5.13030214989, 5.13030214989, 5.13030214989, 5.13030214989, 5.13030214989] m/s`

With external-speed scaling, 29 deterministic seeds found 10 distinct roots. The maximum-yaw-gap pair came from ascending and descending circulation seeds. Their normalized residuals are `1.11e-16` and `6.66e-16`; `max |delta g| = 9.86962 m/s`. The candidate-v3 KJ line-force closure gives yaw moments `-0.761797` and `+0.762136 N m`, a `1.523933 N m` gap. This is circulation/KJ force only, not the aircraft total.

For the induced-adjusted speed form, the same external state and seeds also found 10 distinct roots. The maximum-yaw-gap pair has normalized residuals `1.60e-13` and `1.29e-12`, `max |delta g| = 7.81338 m/s`, and KJ yaw moments `+0.301930` and `-0.301065 N m` (gap `0.602994 N m`). Thus the ambiguity is not solely caused by multiplying lift by the external instead of induced-adjusted speed.

A symmetric `r=0` probe is also retained. It uses identical `u=14.0953893118 m/s`, `w=5.13030214989 m/s` on all six strips. Multistart found 11 distinct roots; a mirrored pair with normalized residuals `6.66e-16` and `4.44e-16` has opposite KJ yaw moments `-0.761966` and `+0.761966 N m`, despite symmetric imposed flow. This documents a symmetry-breaking root of the algebraic proxy, not an aircraft prediction.

The fallback lift curve enters its assumed positive stall blend at `12.126 deg` and ends that blend at `18.128 deg`; effective strip angles of the primary root pair span roughly `9.46–23.06 deg`. Its `CL0=0.1068`, `CLa=4.58/rad`, `CLmax=1.1`, `CLmin=-0.8`, and `CD90=1.2` are whole-aircraft/estimated fallback values reused as a mathematical proxy. No Stik wing section polar or Reynolds distribution was sourced. The nonmonotone stall portion plus strip coupling permits several algebraic roots. The scan shows at least these roots; it is not a proof that the listed root set is complete.

## Interpretation and boundary

This is a concrete rejection of promoting this memoryless full-envelope nonlinear closure with the current proxy curve and no branch-selection rule. Seed choice changes the solved circulation and KJ loads. A physically grounded separated-flow model would need section/Re data plus an explicit dynamic branch or wake-state law; silently retaining a numerical seed is not a branch definition.

The attached positive-slope case is well conditioned for the six-panel kernel (eigenvalues `0.06605, 0.16408, 0.25836, 0.34161, 0.40593, 0.44660`), and candidate-v3 matches D11f in its established attached domain. A later disposable experiment can therefore be restricted to positive axial flow and attached effective angles, and must abort on any out-of-domain sample. The nonlinear reverse-flow convergence in `prototype.py` is only solver behavior: its straight downstream horseshoe kernel is not validated for reversed flow.

No global/local selector, continuous wake state, Stik doublet tape, or production replay was run here. No physical change, complete-flight outcome, or whole-aircraft Cnr prediction follows from these scripts.

