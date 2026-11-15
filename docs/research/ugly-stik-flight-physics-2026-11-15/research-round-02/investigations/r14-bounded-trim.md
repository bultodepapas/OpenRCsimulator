# R14 — Bounded trim, continuation and proof of a limit

**Decision: integrate clearer status semantics in a future separately tested card revision; prototype any new numerical solve offline first.** A failed solve is an observation about a specified algorithm, initial guesses, bounds and tolerance. It does not by itself establish that no equilibrium exists.

## Current behavior and evidence

`app/physics/trim.gd:96–139` validates inputs, attempts a valid optional warm start, then tries documented cold seeds. The glow Newton/backtracking solve respects throttle bounds and demands a residual-decreasing step (`:142–206`); results and throw limits retain distinct failure messages. `research/flight-test/flight_test.gd:511–541` samples a fixed speed grid and records the first failed trim as `first_untrimmable_mps`. The grid is useful reproducible evidence, but that field's name can be read as proving infeasibility.

The retained [FS-64V trim investigation](../../follow-up-01/mode-and-trim-diagnosis.md) used the **session** mass/inventory conditions, distinct from the modal reference model. A 27.5 m/s solution required throttle about 0.981; a separate six-equation solve using the production residual with throttle fixed at 1 found a local equilibrium near 27.6184 m/s. The next grid point at 28 m/s failed after the tested seeds. This supports a nearby local throttle-bound explanation; it neither proves a global maximum speed nor excludes another branch. The original probe and receipt are retained there; no new numerical or hardware run is claimed here.

## What other approaches offer

[SciPy `least_squares`, version 1.17 (REV-S04)](https://docs.scipy.org/doc/scipy-1.17.0/reference/generated/scipy.optimize.least_squares.html) supports bound-constrained residual minimization, scaling and optimality/active-bound diagnostics. A solver's convergence or small objective change still does not establish a sufficiently small physical residual, and an active-mask tolerance is not an infeasibility proof. Compare the residual in declared force/moment or acceleration units and verify control/throttle/rpm constraints separately.

[AUTO-07P (REV-S05)](https://github.com/auto-07p/auto-07p) is a maintained research tool for continuation and bifurcation problems. A parameterized predictor/corrector, and eventually pseudo-arclength continuation around folds, can explore a connected branch more effectively than isolated guesses. It remains local to the traversed branch and may require handling nonsmooth thrust, saturations and admissibility boundaries. No AUTO code is imported and no license conclusion is made for an unselected version.

In an original [JSBSim trim discussion (REV-S06)](https://github.com/JSBSim-Team/jsbsim/discussions/988), developers discuss a user's difficult custom aircraft and later configuration issues. It is a practical lead to distinguish model setup from solver behavior, not a controlled comparison of JSBSim and OpenRC or evidence that either solver finds every trim.

The simplest useful future change is a versioned result separating `first_unsolved_mps`, residual norm/units, attempted seeds, iteration/step exhaustion, active throttle or throw bound, and the actual accepted model/configuration. Preserve the legacy field only with its historical meaning documented. A continuation prototype should start from a known successful trim, store its chosen step and seed, stop at an explicit bound or failed corrector, and test independent cold starts. A fixed-throttle augmented solve can provide a constructive point on a bound, as the retained diagnostic did, without claiming uniqueness. Another alternative is a coarse multistart scan; it is simpler, slower and still incomplete.

## Acceptance

Use the exact retained FS session configuration: verify the 27.5 m/s solution and the approximately 27.6184 m/s fixed-full-throttle root with reported residual and throw checks; retain the original 28 m/s failure as `unsolved` unless a valid new root is actually found. Add known bounded synthetic roots, a fold, two disjoint branches, an unreachable bound, malformed/nonfinite model and residual-at-bound-but-not-zero cases. Compare warm and cold runs without assuming their internal paths match; require bounded iteration and reproducible status. Test old and revised card consumers and exact replay separately if production behavior ever changes. Do not infer engine safety or hardware rpm operation from these model solutions.

Primary sources: [REV-S04](https://docs.scipy.org/doc/scipy-1.17.0/reference/generated/scipy.optimize.least_squares.html), [REV-S05](https://github.com/auto-07p/auto-07p), [REV-S06](https://github.com/JSBSim-Team/jsbsim/discussions/988), accessed 2026-11-15. Source register: [`../sources-review.json`](../sources-review.json).
