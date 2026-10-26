# Candidate QP independent review

2026-10-26. Read-only production review and34 focused temporary assertions. No remaining correctness blocker found in the bounded interior-face/extrapolation candidate. This supports promotion with its unchanged final physical-QP publication gate; it is not a universal convergence/performance claim.

The exact captured braking binary converges in8 sweeps. Independently recomputing stationarity using the ORIGINAL physical A, v, limits and published impulse gives1.378e-11, below the unchanged3.190e-11 tolerance. Original physical group caps and passive work are preserved. No matrix regularization, force-cap adjustment or KKT relaxation was observed.

Reviewed acceleration paths:

- Rank-revealing PSD correction permutes row/column/RHS together, transforms the solution back through the original diagonal scale, and verifies the ORIGINAL linear equations. A consistent singular range gives a valid particular correction; an unresolved incompatible nullspace demand refuses. No artificial null stiffness is introduced.
- Restricting a face to currently interior groups is only a trial active-set guess. Cyclic full-group minimization remains in place. First-boundary line clipping uses stable quadratic-root branches for positive/negative directional terms. A large correction is not directly clamped into a physical force.
- Projected extrapolation operates on dimensionless optimization coordinates. It is a valid feasible-trial proposal because the original FULL mobility objective is rechecked afterward. It does not substitute a Euclidean projection for the physical mobility-metric optimum.
- Every published result still passes the original global KKT, feasibility, complementarity, gap and passive-work checks. Interior correction can accept a tiny objective increase only within explicit existing roundoff slack with an improved residual tie condition; the outer objective check and final passive publication remain. This is numerical monotonicity, not an exact-arithmetic strict-descent assertion.

Additional adversarial cases in `review.gd`:

- Positive-diagonal rank-one consistent/inconsistent range equations, including highly disparate diagonal units. Either original-equation accuracy or explicit refusal is required.
- Near-null incompatible RHS, which refuses instead of fabricating mass.
- Large interior corrections from both signs, stopping at the first disk cap with original-objective descent.
- A projected optimization trial compared against a separately constructed anisotropic mobility-metric optimum.
- A rank-two redundant four-row Gram with one interior and one saturated disk. The candidate reaches its independent constructed KKT optimum in73 sweeps with14 accelerations.
- Exact original braking input, independently checked original-matrix stationarity, physical caps, passive objective and non-mutation.

The JSON fixture is human-readable rather than lossless under Godot's parser:27 A entries differ by up to5ULP,2 v entries by1ULP, and5 cap entries by up to61ULP versus the captured binary. Both numerical regressions converge, but only the original `.bin` establishes the exact floating-point reproduction. Root has retained that binary with its SHA in the checked test fixture.

Final successful checked receipt and source hashes are listed in `source-identity.json`. Earlier review receipts include a deliberately rejected assumption that JSON was bit-identical; the final assertions distinguish parsed-JSON convergence from lossless-binary authority.
