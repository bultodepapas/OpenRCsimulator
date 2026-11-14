# D11g — The Stik's own rate derivatives in the oracle

2026-10-07 · **Status: implemented and verified. The oracle data decision is made (owner delegated it); the Stik oracle's Cmq, CLq and Cnr are derived from its verified local model, and the downwash lag acts in both regimes. All four D11b responses are accepted within ±15% through α 0–11°.** Main-line ROADMAP M1 follow-up D11g; closes the [decision brief](../oracle-data-decision.md).

## R02 provenance qualification for v4

The current R02 derivation gives ARP Cmq **−8.082**, CLq **2.357**, and Cnr **−0.136** at the 15 m/s level trim. The aircraft records retain their original v3 source strings; “current” in those strings describes when they were derived. Updating those strings would also change the aircraft configuration identity.

For this specific transition, the v3 solver was reconstructed from `630c8a5d7e3a89d22176b256bba47a38a56e3413` on the project, aircraft, wheel data and derivation script at `4f0ca86823a2398e668d63abbcb2d09a5a15974d`. In the two reconstructed projects only `aero.gd`, `aircraft_data.gd`, and `wing_polar.gd` differ: the separated-force option and stall-progression continuation. With the pinned Godot 4.8 beta2 on Windows and Linux, the original v3 stored-data check passed, and v3 and v4 returned exactly equal trim conditions, unrounded CG and ARP derivatives, four-significant-digit values, and the 0°, 2°, 4°, and 6° sensitivity rows on each host. The three provenance texts differed only in their law version.

The generator always recomputes the v4 result. Its historical admission is restricted to the beta2 engine source-commit hash, normalized aircraft input, complete LF-normalized solver/input inventory, rounded values, and three individually pinned v3 source strings. The source inventory includes every physics GDScript, wheel profiles, and project settings; the generator itself is checked before and after derivation and excluded from the extra aggregate only to avoid a self-hash cycle. Any change to the qualified inputs or solver requires a new review and reconstruction, even if the displayed values still agree. The updater accepts the same qualified historical records in `--check`; its explicit `--write` advances the three source strings to the newly generated current law and consequently changes the aircraft configuration identity. Do not refresh the qualification hashes without reproducing and reviewing the comparison.

For v0.2.3, the complete 140-file normalized inventory was compared against `c912ee8e774d8439e6c9a31b6d6ab325421cbcde`: 139 inputs were identical, and `app/project.godot` changed only `config/version` from `0.2.2` to `0.2.3`. The previous aggregate was `f676516ffbad54911a4fead1daf0d1cf5fc4351819761ed5566b6f59226cb57f`; the metadata-only renewal is `b0c8111473cc50a3ce28751a801f1981e1011325047ca45506985de4307d5946`. Before renewal, both Windows and Linux correctly refused the old provenance; their newly calculated trim, unrounded and rounded derivatives, sensitivity rows, and generated provenance exactly matched the earlier qualified reports. After renewal, both platforms passed; an isolated version-only change to `0.2.4` was refused by the generator and updater on both platforms. The v3/v4 numerical qualification above remains the basis for admission.

### 2026-11-11 release provenance renewal

For v0.2.5, isolated Windows and Linux projects reconstructed baseline
`4dd64ed5c84c8933bf9cb218c122b79dc1b22b62` and candidate
`f29a42c2f45c23ec96254b4146aeb0724720568e` using pinned Godot 4.8 beta2.
Of the 140 prior inventory files, 139 were unchanged and `app/project.godot`
changed only version `0.2.3` to `0.2.5`. Nine airship and multirotor physics
scripts were added; none of the prior physics inputs was removed or modified.
The new complete 149-file normalized aggregate is
`8091f2bc5c168f16558c09b59a6d7582a68387dd00683c4de259593d1d815443`.

On each host, the baseline generator and updater passed; the unmodified
candidate refused only the three historical-source checks. The aircraft input,
trim condition, unrounded CG and ARP derivatives, rounded values, four
sensitivity rows and generated provenance matched exactly between baseline and
candidate. After renewing the two exact-inventory guards, fresh generator and
updater checks passed on both hosts and in the Windows working tree. Separate
mutations of an added physics script and the project version were refused by
both guards on both hosts. All mutations were restored; the aircraft bytes and
historical source strings were not changed. The
[qualification receipt](2026-11-11-release-v025-qualification.json) records the
source, report and checked-log identities.

The initial concurrent Windows imports of copied caches reported engine errors
and were not used as passes. Subsequent sequential checked imports completed
without engine errors, as did both Linux imports and the derivation checks.

### 2026-11-11 H6 wrapper follow-up

The H6 source change at `10db558ffe24e05ec3df5604a8eb66fccb9eb406` routes
13 existing transcendental calls through the existing `math3d` wrappers; the
five-file diff contains only those substitutions and one required preload. Of
the 149 D11g inventory inputs at baseline
`fc3e5d16ad36b2469d0cc29c2703f14f8470d5e1`, 147 are unchanged and only
`physics/airship/airship_data.gd` and
`physics/multirotor/flight_controller.gd` changed. The new complete normalized
aggregate is `28069054e72cb6fa3181f5e5b4e8d3db9dfacf5f81193a9975e95e8d347e8fa5`.

On Windows and Linux, the reconstructed baseline passed both guards and the
candidate initially refused only the three historical-source checks. Trim,
unrounded and rounded derivatives, sensitivity rows and provenance matched
exactly. After renewal, fresh generator and updater checks passed on both hosts.
Separate physics-source and project-version mutations were refused by both
guards on each host and restored byte for byte. The Stik bytes and historical
source strings remain unchanged. The receipt's `h6_followup` records this
comparison and its checks; its earlier qualification fields are preserved.
Initial Windows imports of copied caches reported engine errors and were
rejected; clean checked reimports passed.

### 2026-11-12 v0.2.6 release renewal

On Linux x86_64 under WSL2 with pinned Godot 4.8 beta2, isolated projects
reconstructed v0.2.5 (`3d2f60443ffa1cdfa711de20855127327976505d`) and
`249febcce810f746a0b93b219479aa9d08a08d4d` plus version `0.2.6`.
The 149-file inventory retained 147 identical inputs; only the multirotor
controlled plant and project version changed. The complete normalized aggregate
is `5c83d4e5911493abce076bbf979adf7f588f21aa59fd488a80ea1faad87d5bb2`.

The baseline passed both guards. The candidate initially refused exactly the
three historical-source leaves; normalized aircraft input, trim, unrounded and
rounded derivatives, sensitivity rows and generated provenance matched exactly.
After renewal, fresh generator and updater checks passed. Disposable source and
version mutations were refused by both guards and restored byte for byte. The
aircraft bytes and historical provenance remain unchanged. The
[qualification receipt](2026-11-12-release-v026-qualification.json) retains the
reports and checked-log identities. This renewal did not rerun the Windows D11g
reconstruction locally; required release CI and native platform checks remain
separate evidence.

The subsequent v0.2.7 metadata renewal reconstructed the v0.2.6 tag
`0cdb3cfd2cb4fca6d71cf508555501c153e15f37`. Of the same 149 inventory paths,
148 were unchanged; only `config/version` advanced to `0.2.7`. The normalized
aggregate is `291e82dd6530ca66dfa1a70b3c98e49fa5236ab5e9f81d51cbe8a793844c276b`.
The Linux baseline passed, the initial candidate refused exactly the three
historical-source leaves, and every retained numerical/provenance field matched
exactly. Renewed checks passed; separate source/version mutations were refused
and restored. The [v0.2.7 receipt](2026-11-12-release-v027-qualification.json)
retains the exact comparison and command/check identities, with the same
Linux-only scope. The failed v0.2.6 publication candidate did not invalidate its
independent D11g comparison.

### 2026-11-14 v0.2.8 release renewal

On Linux x86_64 under WSL2 with pinned Godot 4.8 beta2, isolated projects
reconstructed the v0.2.7 tag `e766561c7cebc6b0d69b650449ace66f8b225cc2` and
`b80a4b214878e97313d2f93901b32174bb0713ea` with version `0.2.8`. Of the 149
qualified inventory paths, 148 were unchanged; only `config/version` changed.
The complete normalized aggregate is
`66bf3b51214237e1a1d0dca77014f8b7c1276c8f23248694420406e625ef4255`.

The baseline passed both guards, while the initial candidate refused exactly
the three historical-source leaves. Normalized aircraft input, trim, unrounded
and rounded derivatives, sensitivity rows and generated provenance matched
exactly. After renewal, fresh generator and updater checks passed; separate
physics-source and version mutations were refused by both guards and restored
byte for byte. A further restored check passed. The aircraft bytes and historical
provenance remain unchanged, and the working-tree inventory and guards matched
the checked candidate after line-ending normalization. The
[qualification receipt](2026-11-14-release-v028-qualification.json) records
report and checked-log identities. Both checked imports completed without engine
errors; the baseline reported eight OBJ material warnings and the candidate had
none. The candidate reused the baseline project's imported-resource cache; both
imports shared an XDG profile isolated from the user's profile. This renewal did
not rerun the Windows reconstruction; release CI and native checks remain
separate evidence.

This establishes model consistency only for these inputs and sampled conditions, not general equivalence of the laws or physical validation. The original 2026-10-07 values and checks below describe the earlier D11g decision, not the present R02 values.

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

- **Generator:** [`research/aero/d11g/derive_rate_derivatives.gd`](../../../../research/aero/d11g/derive_rate_derivatives.gd) measures the local strip model at the 15 m/s level trim (α 4.26°), about the CG, controls neutral, lag settled. The original console output was not committed; the reported values and regression evidence are retained below. The values are flat across α 0–6° (Cmq −7.47…−7.48, Cnr −0.134…−0.131, CLq 3.08…2.91). Closed-form tail and fin formulas from the same data agree within 1% for Cmq, 6% for CLq and 0.4% for Cnr.
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
