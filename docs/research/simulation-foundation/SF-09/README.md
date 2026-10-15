# SF-09 — Generalized-coordinate kernel

2026-10-15 · **Status: implemented, byte-identical: the RC ground vehicle's mass-matrix assembly, block factorization, solves and inversion moved verbatim into a shared float64 kernel with the sizes as parameters; the truck lost 175 lines and keeps its trajectories; the kernel passes a cart–pendulum known answer.** Step SF-09 of the [simulation foundation plan](../../../plans/simulation-foundation.md).

## What moved

[`app/physics/generalized_coordinates.gd`](../../../../app/physics/generalized_coordinates.gd) holds the "one base body plus local degrees of freedom" kernel:

| Routine | Role | Origin |
| --- | --- | --- |
| `add_point_mass(matrix, jacobian, mass, n, active)` | adds m·JᵀJ of a point mass over its active coordinates | the truck's hub Gram assembly |
| `factor_body_local(matrix, body, locals, tol)` | Schur-complement factorization of a matrix whose local coordinates couple only to the body block | the 6 + 8 truck factorization, now any sizes |
| `solve_body_local(factor, rhs, body, locals)` | solves M·a = rhs with that factor | same |
| `cholesky_factor`, `solve_cholesky`, `matrix_vector`, `dot`, `invert` | dense building blocks with a relative pivot tolerance | the truck's private helpers |

[`app/physics/ground_vehicle/vehicle_dynamics.gd`](../../../../app/physics/ground_vehicle/vehicle_dynamics.gd) keeps its private names as one-line calls into the kernel with its own sizes (6 body + 8 local) and pivot tolerance, so its parity tests and the native backend's reference comparison are untouched. The hub geometry, its Jacobians and bias terms stay with the truck: they are its kinematics, not the kernel's.

What is deliberately not here: a general constraint or Featherstone solver. Closed loops wait for a consumer; the plan's rule is to evaluate a double-precision Jolt build or a float64 Featherstone port before writing one (owner decision D4).

## Proof

| Check | Result | Record |
| --- | --- | --- |
| Known answers ([`test_sf_generalized_coordinates.gd`](../../../../app/tests/test_sf_generalized_coordinates.gd)) | A cart carrying a pendulum assembled as body + one local coordinate and integrated with the shared RK4 at 240 Hz: energy drifts 1.2e-13 J in ten seconds, the small-amplitude period matches ω² = g (M + m) / (M l) within 1.2e-5, horizontal momentum holds within RK4 truncation (1.8e-9 kg·m/s) through a 1.2 rad swing; the block factorization agrees with the dense inverse and satisfies M·a = rhs to 3.6e-15 on twenty random coupled matrices of 7 to 14 coordinates; a zero local mass is refused; the point-mass assembly reproduces m·JᵀJ exactly | [log](results/kernel-test.log) |
| Truck, nitro, support, suspension, handling, road-batch and kernel suites on this tree | 12 programs, all pass (vehicle dynamics 53, RCV session 162, nitro dynamics 30, nitro session 28, support 111, suspension 83, obstacle contacts 14, handling 21, road batch 55, SF kernel tests, law properties 203) | [log](results/focused-tests.log) |
| Fleet fingerprints, baseline commit `f78901b9` (the merge before SF-09) versus this tree | **24/24 identical**, the ground vehicle included. A first comparison against the SF-07 run showed the P-51 differing; that run predated the upstream P-51 changes merged in `f78901b9`, so the baseline was rebuilt at that commit | [comparison](results/fingerprint-comparison.txt), [baseline](results/fingerprints-head.json), [SF-09](results/fingerprints-sf09.json) |

The integrator renormalizes the rigid-body attitude slot after every step, so the pendulum state rides in the first four entries of a 13-value vector whose attitude slot holds the identity quaternion; its norm is exactly one, so renormalization changes nothing.

## Limits

- The kernel covers the tree-structured case (locals coupled only to the base body). A vehicle whose local coordinates couple to each other needs a dense or banded factor; `cholesky_factor` and `invert` are there for it, the block solver is not.
- Coriolis and gravity bias terms stay with each vehicle's kinematics; the kernel solves the linear system it is given.
- The native ground-vehicle evaluator keeps its own C++ copy of these routines, as before; the GDScript reference is what moved.

Commit message: `SF-09: generalized-coordinate kernel (physics/generalized_coordinates.gd); truck mass-matrix assembly, factorization and solves moved verbatim, 175 lines removed; cart–pendulum known answer, truck fingerprints byte-identical`
