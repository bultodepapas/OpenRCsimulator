# D11g — The Stik's own rate derivatives in the oracle

2026-10-07 · **Status: implemented and verified. The oracle data decision is made (owner delegated it); the Stik oracle's Cmq, CLq and Cnr are derived from its verified local model, and the downwash lag acts in both regimes. All four D11b responses are accepted within ±15% through α 0–11°.** Main-line ROADMAP M1 follow-up D11g; closes the [decision brief](../oracle-data-decision.md).

## Decision

Option 2 of the brief now, option 3 later as held-out validation (DECISIONS.md, 2026-10-07):

| Coefficient | Before (UltraStick 25e) | Now | Why |
| --- | ---: | ---: | --- |
| Cmq | −13.5664 | **−7.476** (derived) | The local tail's static pitch damping. Cmα̇ (−3.59) is no longer lumped in: it comes from the downwash lag state, in both regimes |
| CLq | 6.1639 | **2.951** (derived) | Same tail; closed form 2·a_f·(S_t/S)·(l_t/c) = 3.13 |
| Cnr | −0.1833 | **−0.1319** (derived) | Fin invariant −2(l_v/b)·Cnβ_fin plus wing profile −CD0/3 = −0.1324 (D11f); the borrowed value contradicted the data's own fin-derived Cnβ |
| Clp | −0.4496 | kept (borrowed) | The local value is ×1.10 and 3-strip coarse (≈ 12% above converged); the borrowed value is closer to the converged estimate. A strip-refinement step decides |
| Static, control, polar | 25e / derived | kept | No verified Stik replacement yet: the local model has no dihedral or fuselage, and the borrowed polar cannot be split (D11f) |
| Clr, Cnp, CYp, CYr | 25e | kept | Not verified; see findings |

**Why not keep the borrowed values:** they are another airplane's, and two of them contradict the Stik's own data. **Why not wait for measurements:** until the field kit, flight would keep a 20–30% damping change across α 8–12°, where an approach flies. Measured identification (VAL-5/6) will be compared against these values as held-out evidence, never fitted into them.

## Model

- **Generator:** [`research/aero/d11g/derive_rate_derivatives.gd`](../../../../research/aero/d11g/derive_rate_derivatives.gd) measures the local strip model at the 15 m/s level trim (α 4.26°), about the CG, controls neutral, lag settled. [Output](output.txt). The values are flat across α 0–6° (Cmq −7.47…−7.48, Cnr −0.134…−0.131, CLq 3.08…2.91). Closed-form tail and fin formulas from the same data agree within 1% for Cmq, 6% for CLq and 0.4% for Cnr.
- **Lag in the oracle:** `Aero._global_loads` takes the lagged wing CL. Its static coefficients already contain the settled downwash; a lagged CL turns the tail angle by k_ε·(CL_wing − lag) on the free tail slope, at the tail's arm. That adds lift and pitching moment exactly as the local tail does. Settled, it adds nothing (byte-identical); NaN (trim, static solves) is the old path.
- **Flight modes carry the lag:** `FlightModes.analyze` adds the lagged CL as a ninth state, ẋ = (CL_wing − x)·V/l (the session's lag in continuous form), and the longitudinal block becomes 5×5 with one more real root. Aircraft without the lag (Extra, P-51, Avanti) are unchanged.

**RC-scale finding:** the tail's delay is not quasi-steady here. At 15 m/s τ = l/V = 51 ms and the short period is 9 rad/s, so ωτ ≈ 0.46. A lumped Cmα̇ (what the borrowed Cmq did) mispredicts the pitch response: kicked by 0.6 m/s in w, the nonlinear flight's pitch rate is predicted within **0.97%** of its peak by the 9-state linear model, but misses by **27%** with no lag state and **30%** with Cmα̇ lumped into Cmq.

## Proof

- [`test_damping_regimes.gd`](../../../../app/tests/test_damping_regimes.gd), 20 checks: `KNOWN_DEFECTS` is empty. Worst ratios through α 0–11°: **Clp ×1.098, Cmq ×1.011, Cnr ×0.970, CLα ×1.000**, all within ±15%. The data equals the local model at the 15 m/s trim within 0.5% (Cmq −7.4763, CLq 2.9506, Cnr −0.1319), so a geometry change that is not rerun through the generator fails.
- [`test_downwash_lag.gd`](../../../../app/tests/test_downwash_lag.gd), 14 checks: the oracle's plunge-measured Cmα̇ (−3.437) equals the local one (−3.424) within 0.4%; a settled lag leaves the oracle loads byte-identical (2000 states). Effective pitch damping Cmq + Cmα̇: local −10.93, oracle −10.95.
- [`test_yaw_damping.gd`](../../../../app/tests/test_yaw_damping.gd), 4 checks: oracle Cnr within 0.1% of the Stik-consistent value.
- [`test_modes.gd`](../../../../app/tests/test_modes.gd), 42 checks: a 5×5 known-answer eigenvalue case; the lag root is real and at 0.7–1.0 × V/l (−12.0, −16.8, −27.8 1/s at 10, 15, 25 m/s); the time-domain check above. Bands re-recorded:

| Mode (15 m/s / 25 m/s) | Before | After | Cause |
| --- | --- | --- | --- |
| Short period | 1.495 Hz ζ 0.74 / 2.427 Hz ζ 0.75 | 1.429 Hz ζ 0.78 / 2.305 Hz ζ 0.81 | Cmq + lag state |
| Phugoid ζ | 0.26 / 0.74 | 0.21 / 0.64 | CLq, Cmq |
| Dutch roll ζ | 0.29 / 0.28 | 0.24 / 0.23 | Cnr |
| Spiral λ (1/s) | +0.034 / −0.0002 | **+0.086 / +0.032** | Cnr: doubling time 8 s / 21 s |

  At 10 m/s (local regime, data unused) only the lag state changes the modes: short period ζ 0.52 → 0.60. Cnr moves the spiral most, as D10 predicted. The spiral's sign depends on Clβ·Cnr − Cnβ·Clr, and Clβ and Clr are still borrowed, so a hands-off bank-drift test on the real Stik (VAL) decides it; the flight-identified US120 is spirally stable.

- **Slow-flight test pilot:** `test_envelope`'s flown stall moved from 9.60 to 9.99 m/s (5.0% above the 1-g CL_max speed 9.51) and its linear-oracle fixture no longer held below 0.9 V_s. Cause: the scripted altitude-hold PD (gains tuned 2026-10-05) over-controlled the lower static pitch damping, α overshot ~2° and the wing stalled dynamically. The fixture without an envelope also has no lag, so it carried Cmq without its Cmα̇. A gain sweep on the old and new physics showed that adding the pilot's own pitch-rate damping (kq = 0.5 stick per rad/s) makes the result independent of the step: both stall at 9.68 m/s, and the linear oracle holds to 8.21 / 8.19 m/s. `Maneuvers.SLOW_FLIGHT` now has kq; kp and kd are unchanged.
- **Golden flights (deliberate):** with D11g switched off on a scratch copy (borrowed Cmq/CLq/Cnr, oracle lag disabled) all four goldens replay to 1e-15. With it, roll_15, pull_throttle and rudder_doublet move by 1.99, 9.14 and 0.33 m; glide_15 stays within 3e-11 m. All four were re-recorded and replay exactly; inputs unchanged.
- **Mutation checks** on a scratch copy, each caught: oracle lag disabled (test_downwash_lag, test_modes ×7), lag moment arm sign flipped (test_downwash_lag), flight modes without the lag state (test_modes ×13), borrowed Cmq restored (test_damping_regimes ×2), CLq off by 8% (test_damping_regimes).
- **Other consumers:** `test_dynamics` checks the 9×9 Jacobian and its gyroscopic term with the lag held. The P-51, Extra and Avanti modes and handling tests are unchanged (no lag).
- **Sensitivity sweep regenerated** ([results.md](../../../../research/sensitivity/results.md)): 15 m/s baseline equals the new `test_modes` bands. US120 comparison: short period 1.07× → 1.02×, spiral τ −21 s → −9.8 s (the US120 is stable). 25e comparison: short-period ζ 0.75 → 0.80 (flight ID 0.83), frequency 0.87× → 0.83×. In the D10 ranking the spiral is less sensitive to fin area (137 → 40%) and Cnr (107 → 32%), because the pole moved away from neutral.
- **Ground figure-eight margin:** `test_ground_friction`'s idle figure-eight at 30% steer lifted the inside wheel for 299 ticks. Each change alone kept it down; together the Stik's lower yaw damping gives ~3% more yaw rate. Before D11g the inside wheel already kept only 0.45 mm of its ~20 mm static compression: idle accelerates the airplane through the left loop toward the tip-over limit. The fixture now uses the session's real aux layout (it had replaced it with a 4-entry legacy array, which drops the lag), steers 22% (4.4°) and requires ≥ 1 mm compression explicitly: 1.60 mm now, 2.17 mm with the old physics. Other ground fixtures that set a 4-entry aux (deliberately without E3b1 anchors) also run without the lag; at taxi speeds its effect is negligible, but a layout guard is a follow-up.
- **H7 checker:** its branch anchor follows the new `_global_loads(…, downwash_cl)` call; all four goldens replay under one-ulp perturbations.
- **Full suite:** `app/test.sh` with its own `XDG_DATA_HOME` exits 0 (103 sections) both in the shared tree (other tracks' work in progress included) and in a clean worktree with HEAD plus only this change.
- **Cost:** the oracle path now evaluates the wing CL once per loads call (Stik only). Stik physics 274–282 → 324–329 µs/tick, stalled flight 264–273 → 321–336 µs/tick (3 runs each, shared host): +50 µs, inside the 500 µs budget. Gate P's limiting P-51 has no lag and is unchanged. Optimisations if needed: reuse the local wing CL in the blend, or a column-mean form of the induced map in attached flow (must stay the exact input of the lag).

## Findings for later steps

- **Cross-rate derivatives disagree:** the local model gives Cnp −0.013 to −0.096 over α 0–6° (≈ −CL/8, classic wing theory), the borrowed value is **+0.118**, an opposite sign across the blend. Also CYr 0.247 vs 0.15 and Clr 0.04–0.12 vs 0.109. These need their own verification (proposed D11h) before any replacement.
- **CLadot** (borrowed 1.97) is unused by the code; the lag now supplies the tail's CLα̇.
- **First-order lag vs pure delay:** at ωτ 0.46 a pure transport delay has ~17% more quadrature (damping) and ~40% less in-phase effect than the first-order lag. A delay line would be the next refinement if VAL short-period data demand it.
- **Clp:** the converged-strip question (D11d) is now the only damping derivative still borrowed.
