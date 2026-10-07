# D11d — Wing induced-flow map: consistent roll damping and lift slope

2026-10-07 · **Status: implemented and verified. Stik Clp and CLα accepted across α 0–11°; Cmq (E0a2) and Cnr (D11f) remain pinned defects.** Main-line ROADMAP M1 follow-up D11d.

## Problem

D11b measured that the local strip model, which flies from α ≈ 8° up to and past the stall and blends with the oracle in between, disagreed with the oracle. Ratios to the oracle at α 2°:

| Derivative | Before D11d | Cause |
| --- | ---: | --- |
| Clp | ×1.73 | Strip theory without induced flow: Clp ≈ −a/6 |
| CLα | ×1.34 | Each strip used the whole-airplane CLα, and the local tail added its own lift on top |
| Cmq | ×0.28 | Local tail (E0a2) |
| Cnr | ×0.72 | Fin (D11f) |

An approach at 1.3 V_s flies inside this blend. The knowledge base had already identified the cause and the fix: an induced-flow map, not more strips ([02 §5–6, T2](../../roadmap-investigations/02-aerodynamics-rc-scale.md)).

## Model

`AircraftData._induced_map` precomputes, per aircraft, a Weissinger influence matrix `K`:
- bound vortex at the quarter chord and control point at three-quarter chord;
- planar, unswept, straight trailing legs;
- the three equal-area strips per side already used, with taper supported;
- each strip's own 2-D bound-vortex term (1/2π) removed, so that a section slope a₀ carries it.

The loader stores the effective-angle map `E = (I + a₀K)⁻¹`. At runtime `Aero._local_loads` maps the geometric strip angles (flow incl. ω×r, aileron, twist) through `E`. Attached strip lift is `strip_cl0 + a₀·(E·α)`. Stall weighting and the post-stall flat plate still use the geometric angle, because separated flow has no circulation to induce downwash. Antisymmetric (rolling, aileron) loads induce more downwash than symmetric ones, which strip theory misses.

**Consistency, not a fit.** a₀ is solved so the local wing plus horizontal tail CLα equals `aero.CLa`; `strip_cl0` is solved so the local CL(0) equals `aero.CL0`. These are the same airplane in two models. Clp is then a **prediction**.
- Section slopes come out at 6.08 (Stik), 5.41 (Extra), 5.14 (P-51) and 5.58 (Avanti) per radian, 0.82–0.97 × 2π, which is plausible.
- Models without a map, such as hand-built test models, use the old strip law, and the code path stays byte-identical to it.

**Strip count stays 3 per side.** Refinement with the same kernel, a₀ = 2π, AR 5 rectangular:

| Strips per side | 3 | 5 | 8 | 20 | 80 |
| --- | ---: | ---: | ---: | ---: | ---: |
| CLα | 4.317 | 4.170 | 4.079 | 3.983 | 3.933 |
| Clp | −0.481 | −0.449 | −0.427 | −0.403 | −0.390 |

The calibrated Stik wing predicts Clp −0.474 at n = 3, about 12% above the converged lifting-surface value. The local total is ×1.12 the oracle, inside the ±15% band. Doubling the strips would cost about 60% more local-wing time on a tight budget, so refinement does not yet justify it (roadmap: "increase strip count only when refinement proves it necessary").

## Proof

- **Known answers:** [`test_strip_induced.gd`](../../../../app/tests/test_strip_induced.gd), 21 checks.
  - An elliptic AR 50 wing reaches Prandtl's lifting line (6.026 vs 6.042).
  - Elliptic AR 5 and rectangular AR 5 with 3/5/8 strips per side match an independent Python implementation to 1e-3 ([`research/aero/d11d/lifting_line.py`](../../../../research/aero/d11d/lifting_line.py), [output](../../../../research/aero/d11d/output.txt)). That implementation reproduces the knowledge base's VLM (4.32/4.17/4.08, −0.481/−0.449/−0.427).
  - For all four aircraft: calibration exact to 1e-9, plausible a₀, mirror-symmetric map. The GDScript and Python Stik a₀ agree to 1e-6.
- **Acceptance:** [`test_damping_regimes.gd`](../../../../app/tests/test_damping_regimes.gd), 17 checks.
  - **Clp ×1.116 and CLα ×0.983**, within ±15% at every α 0–11°.
  - Cmq (×0.278) and Cnr (×0.715) stay pinned in `KNOWN_DEFECTS` for E0a2 and D11f.
- **Refactor safety:** `test_aero_flow.gd` without the map stays byte-exact to the frozen H12 oracle (10,001 comparisons).
- **Mutation checks** on scratch copies:
  - Keeping the self term fails 10 known-answer checks and CLα (×0.81).
  - Calibrating without the tail share fails 4 checks, plus Clp (×1.18) and CLα (×1.28).
- **Golden flights (deliberate):** with the map removed, all four goldens replay at 1e-14 m; with it, roll_15, pull_throttle and rudder_doublet move by 0.12, 0.07 and 0.44 m, and glide_15 stays bit-identical. All four were re-recorded and replay exactly; the inputs are unchanged.
- **Flight modes:** `test_modes` 15 and 25 m/s (oracle regime) are bit-identical. 10 m/s trims at α 12.2° (local) and was re-recorded:
  - roll τ 0.048 → **0.092 s** (the 25e identification is 0.088 s);
  - short-period ζ 0.61 → 0.47;
  - spiral 0.34 → 0.59.

  The removed lift-slope bump had been masking the tail's weak pitch damping. The 10 m/s short-period floor of 0.45 is pinned as the E0a2 defect.
- **Other tracks' tests unchanged:** P-51 handling/envelope/ground, Extra and Avanti handling, spin, envelope and physical envelope all pass.
- **Cost:** `_local_loads` 22 → 26 µs per call (+18%; matrix-vector product). Fleet tick medians are within this shared host's noise ([raw](results/)). Fingerprints change only in the local regime (stall, spin, nose-high or falling ground fixtures); every trim and the Stik ground fixture are unchanged.
- **Full suite:** `app/test.sh` with its own `XDG_DATA_HOME` exits 0 (99 sections). [Summary](results/suite-summary.log). H9's legacy-readability check now builds its legacy record by stripping the additive fields, instead of relying on an unrecorded file.

## Findings for other owners

- **Extra and P-51 oracle Clp** (−0.60 / −0.56, generated by EX-05/P51-05 from a strip formula) is about 1.4× a VLM value. The coupled local model now reads ×0.88 and ×0.84 of those oracles. The local value is the physically better one; the generated data should be revisited by those tracks.
- **Stik local-regime roll authority:** the steady roll rate per aileron (Clδa/Clp) in the local regime is ×0.60 of the oracle, both before (×0.58) and after D11d. It is not one of D11b's derivatives; it is a follow-up for the aileron effectiveness or stall model.
- **Limits:** a planar unswept quarter-chord line is assumed (taper is approximate); there is no dihedral, no fuselage carry-over, no ground effect and no wake lag. Stalled strips keep the linear induced map in their attached part. D11c (AVL) remains optional supporting research.
