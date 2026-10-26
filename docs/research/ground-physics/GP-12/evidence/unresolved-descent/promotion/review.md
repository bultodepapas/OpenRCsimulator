# Exact scalar feasibility and bounded unresolved-direction trial

Draft production targets are in `manifest.json`; no main application writes by
this agent. The three runtime edits are rebased on the promoted mass-prefix AR
`406b89fbe2a4a09754bf10a2db07d2dfb87fb86038d807cb22396a175a4b9831`.
Its mass prefix, inverse/SPD witnesses, reuse/factory and all variable assembly,
slip/work proofs remain unchanged. No Impulse/Step payload is supplied.

## Separate scalar correction

For an original finite1D capacity D>=0, `abs(p)<=D` is the exact binary64-number
interval test. Outward division/squaring incorrectly made the sufficient upper
bound1.0000000000000036 at an exact saturated endpoint. The scalar-only patch
removes those unnecessary operations, preserving p and D. Zero capacity still
requires exact zero impulse; two-row ellipses retain their outward norm proof.
Tests include both signs, signed zero, subnormals, equality/oneULP outside,
zero capacity, unsupported nonfinite and finite overflow-domain inputs.

This alone does NOT accept the gentle143 QPs. Their old candidate true-gap upper
bounds are3.8e-13..9.5e-13 J against derived Gamma7.4e-16..1.6e-15 J. They correctly
continue to refuse; the owner's larger ceiling is not substituted for Gamma.

## Convergence correction

The interior tire-face correlation has a weak positive eigenvalue around4.3e-13,
below the existing1e-12 numerical rank threshold, with a genuine linear component.
The old range correction omits that unresolved component and cyclic sweeps stall.
No eigenvalue/rank/KKT threshold is changed.

After the existing8-sweep probe and zero/retained/range physical-proof attempts
have failed, the bounded strategy permits a new fallback proposal. Symmetric
rank-revealing elimination builds a direction from the largest unresolved reduced
linear component (deterministic first-index tie). This is an optimization direction,
NOT an asserted exact nullspace or a new mass. Its maximum component is normalized
to one. The original full gradient must establish descent; original positive
quadratic curvature limits the line step. The step also stays at or before the
first feasible original interval/disk boundary. Finite-range refusal remains.
Existing full-objective/feasibility/KKT/work publication is authoritative.

The direct QP opt-in solves both retained cases in17 sweeps with original strict
KKT. The actual strategy accounts for8 probe+17 fallback sweeps (25 total), within
the caller budget; lower-budget checks never report extra sweeps. The new proposal
is unavailable to pure `QP.solve`, ordinary direct AR callers or the first probe.
This preserves pure default complete bytes, ordinary<=8 strict outputs and the
preference for exact zero when it already meets the verified input-resolution
contract. Numerical strategy/acceleration identities and proposal counts identify
actual use. Physical objective, authored capacities, regularization (zero) and
all physical comparison tolerances are unchanged.

`direction-results.json` records a proposal from each retained old8-sweep iterate:

| Input | original gradient dot applied delta | retained positive curvature | objective decrease |
| --- | ---: | ---: | ---: |
|8-piece failure |−7.0619234e-13 J |5.8912971e-18 J |about7.0619e-13 J |
|16-piece failure |−3.6811256e-13 J |1.6022909e-18 J |about3.6811e-13 J |

The complete normalized delta and group norms are retained. The diagnostic move
from an old failed iterate is not an accepted historical state. Actual new common
mass/slip/work impulse publication passes its original independent checks.

## Validation and limits

- Focused production-target test56/0; QP659/0; strategy34/0; AR53/0; Impulse314/0:
  **1,116** compatibility/focused assertions. Lossless controls pin pure defaults
  and zero-optimal results. An independent symmetric coupled-disk optimum and a
  positive-curvature interior line minimum distinguish weak from true-null motion.
- The original complete gentle initial-condition tape now accepts all180 ticks:
  **16 checks /0 failed**, unchanged geometry/material/coefficients/quality/16-piece
  limit. Mechanical balance−5.4173e-6 J meets its original2e-4 J target. Rebound,
  all-wheel spin and touchdown/unload/second-touchdown pass.
- The full-run exact draft sources are preserved in `full-run-source`; final
  source differs only by the requested documentation-header clarification.
  `manifest.json` verifies code-only equality of the three modules.
- The harder tick78 cap-area raw accuracy refusal remains a separate problem.
  No full hard-drop, fleet, calibration, stock activation or performance claim.
  Shared-host full gentle wall duration72.8 s is diagnostic only.

The production patch adds one focused test and three lossless binary fixtures,
already covered by `/app/tests/fixtures/ground_contact_*.bin -text`. Independent
review/production promotion is the next step; this package has not staged or
committed the actual repository.
