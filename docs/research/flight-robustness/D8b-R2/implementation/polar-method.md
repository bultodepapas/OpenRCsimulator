# D8b-R2d — Post-stall polar method review

2026-10-11 · **Status: design review complete; no Stik coefficient or production change selected.**

Owning steps: [D8b-R2d and D8b-R2e](../../../../UGLY-STIK-PULLUP-PLAN.md). This note reviews the smallest defensible quasi-steady candidate for the [D8b-R2 diagnosis](../README.md). It is a method recommendation, not aircraft calibration.

The [implemented experimental path](README.md) accepts explicit finite-wing reference tables. Its three sensitivity fixtures use constructed knots; they do not implement a measured Viterna fit. The continuation formulas below describe a possible future data-preparation step once supported post-peak anchors exist.

## Recommendation

Keep the existing law as the byte-identical default. Add an opt-in, provenance-bearing polar path for controlled research. Its input must contain the complete positive and negative near-stall/post-peak shape from a section or wing source, including drag; use Viterna-Corrigan only to continue a supported post-peak polar where the source data ends below 90°. A CLmax point by itself is not enough to define the falling branch.

The Jensen section has not been identified, and the aircraft polar is not measured. Therefore no unique replacement curve can be selected now. An analog section or constructed family may run as **estimated/experimental**, with the source, Reynolds number, roughness, polar basis, uncertainty bounds and build hash recorded. Its handling result can compare hypotheses; it cannot be called a calibrated repair.

State the coefficient basis explicitly. The current local model's attached induced-angle map is calibrated to the aircraft's inherited lift slope, while its separation weight and flat-plate lift use geometric strip angle. The aircraft's CLmax = 1.1 is labeled a whole-aircraft estimate, not a two-dimensional section measurement. CD90 = 1.2 is borrowed from the finite-wing AR = 5 Viterna estimate. Calling either value a section-polar anchor would mix levels. If a candidate table is two-dimensional, its per-strip application must use a compatible induced-angle solution; the existing linear map alone does not close nonlinear separated circulation. If the existing split is retained for the first experiment, label the input as a local-strip-equivalent finite-wing candidate and preserve that angle convention exactly.

## Viterna continuation and its limits

For the positive side, the standard Viterna extension from a supported anchor (αs, CLs, CDs) to 90° is:

    CL = A1 sin(2α) + A2 cos²(α)/sin(α)
    CD = B1 sin²(α) + B2 cos(α)
    A1 = CDmax/2
    A2 = (CLs - CDmax sin(αs) cos(αs)) sin(αs)/cos²(αs)
    B1 = CDmax
    B2 = (CDs - CDmax sin²(αs))/cos(αs)
    CDmax = 1.11 + 0.018 AR

This is the empirical high-angle method introduced for large horizontal-axis wind-turbine calculations, where AR is part of the rotor geometry. It gives CLs/CDs at αs and CL = 0, CD = CDmax at 90°. It is useful as an extrapolator, not a measured near-stall law for the Jensen. A recent NASA full-range rotor-airfoil table workflow likewise combines target-airfoil computations with experimental NACA 0012 high-angle data; that supports an evidence-based table pipeline, not copying the NACA polar into this aircraft ([NASA TM-82944](https://www.osti.gov/servlets/purl/6763041), [NASA HVAB C81 table report](https://ntrs.nasa.gov/api/citations/20250006213/downloads/NASA_TM_HVAB%20C81%20Deck%20Generation_FINAL.pdf)).

The Viterna start is value-continuous but is not generally slope-continuous. Its lift derivative is:

    dCL/dα = CDmax cos(2α)
             + A2 [-2 cos(α) - cos³(α)/sin²(α)]

For illustration only, CLs = 1.1, αs = 13.5°, and CDmax = 1.2 give A2 ≈ 0.2043 and a Viterna start slope ≈ −2.78/rad. These are not measured Stik values. This shows why starting the formula directly at an estimated CLmax can inject a sharp, unsupported slope change. Move its anchor to the last actual post-peak sample; do not select a start angle or connector width by whether the loop looks better.

Use the measured/borrowed polar knots through the post-peak region, then append Viterna continuation knots beyond its last supported point. Evaluate the joined sequence with a C1 shape-preserving cubic Hermite interpolant (PCHIP). This avoids a free smoothstep width and prevents interpolation overshoot on monotone intervals. Choose extension knot spacing by interpolation-error convergence, not by flight response. If the measured and Viterna secants at the join reverse sign or violate source uncertainty, flag the join for review instead of smoothing it away.

Handle positive and negative stall separately: each side needs its own supported αs, CLs, CDs and uncertainty. Do not infer the negative polar from the positive CLmax. From 90° to 180°, the plate closure is CL = (CDmax/2) sin(2α), CD = CDmax sin²(α); it reaches zero lift and drag at 180° and is periodic with the corresponding reverse-flow branch. CL's value and slope match Viterna at 90° when both use the same CDmax. Viterna drag's slope at 90° is −B2, whereas plate drag's slope is zero; the joined table must set or verify the endpoint tangent against the plate branch and reject negative drag. Apply the same checks on the negative side and across the wrapped ±180° boundary.

## Validation before promotion

- Keep the legacy default path numerically unchanged. Reject malformed knots, non-finite coefficients, unordered angles, missing source/evidence kind, negative CD, invalid angular coverage, and a non-periodic ±180° closure. Check finite values and C1 derivatives at every join.
- Compare the full CL/CD polar and its slope against its source; report positive and negative CL peaks, angle of each peak, post-peak slope, CD growth and the 90°/180° closure. Sweep plausible source uncertainty, not just CLmax.
- Preserve attached-flow loads and the existing trim/oracle checks. Verify the actual summed wing/aircraft CL peak separately from any input-table or coefficient-helper peak.
- Re-run the D8b-R2 static alpha sweep and report dMx/dp plus the stall-weight contribution for both signs. Treat these as mechanism diagnostics, not a target damping value.
- Exercise accelerated entry, gentle and abrupt pulls, release, recovery, stall and spin on the complete coupled session. Retain mirrored seeds, full rate/inertia terms and propulsion effects. Compare 240/480/960 Hz and strip refinement with the polar held fixed; report rate, loop-plane error, altitude loss, α, local separation and recovery time.
- Run current aircraft handling, trim, stall/spin, trace/replay and performance checks. Do not change golden files until the physical meaning of changed trajectories is documented.

No handling threshold for the replacement post-stall slope or roll gain is supported yet. Promotion requires matched polar/build data or explicit, defensible bounds plus held-out maneuver evidence and owner flight review. Until then, the opt-in branch is experimental and the existing diagnosis remains open.
