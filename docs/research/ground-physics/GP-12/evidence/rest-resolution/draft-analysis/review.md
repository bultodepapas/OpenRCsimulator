# GP-12 numerical-rest draft (2026-10-26)

Review only. No production promotion. The sealed earlier cohort is unchanged.

The exact `resting-failed-qp-symmetric-16.bin` assembly has a physical contact
Jacobian weak singular value around `2e-11`; forming its Gram matrix squares
that scale below binary64 resolution. A strict original-QP KKT residual remains
an explicit failing oracle. Resolving the floating Jacobian's weak mode directly
would ask for approximately `0.126 N s` of circulating impulse, outside the
original roughly `0.006 N s` caps, for energy benefit around `1e-27 J`.

The draft introduces a **distinct opt-in epsilon-optimality contract**. It does
not relabel that strict KKT oracle as success. The default pure QP and Impulse
API remains strict. The owner's explicit energy ceiling is an upper budget;
it cannot increase the derived numerical uncertainty. The original physical
caps, passive-work test, common-mass solve, slip check and energy closure remain.

## Derivation

Take the supplied binary64 operand values as the exact input data. Let `J`,
`z`, `b`, `M` and response columns `x_j` be those actual operands. The adapter
binds `v_i = fl(b_i + J_i z)` and `A_ij = fl(J_i x_j)` by exact repeated
operation order and byte binding. `M` must be symmetric SPD and every response
must satisfy a bounded backward-stable residual gate.

`gamma(k) = k*EPS/(1-k*EPS)`, using `EPS=2^-52` (twice unit roundoff), bounds
separately rounded products/additions in the supported finite arithmetic
domain. Every positive bound operation is padded outward, including the exact
IEEE minimum-subnormal absolute rounding allowance. That immutable constant is
`M.MIN_NORMAL_FLOAT64*EPS`; the pinned parser rounds the equivalent decimal
literal to zero. A bit-level gradual-underflow/rounding-mode check guards the
bound computation. Overflow refuses, and source dot products that underflow
to zero refuse. No arbitrary exponent or physical velocity cutoff is used. Thus `delta_v` follows the uncancelled absolute dot operands rather
than the tiny cancelled result. The response residual is bounded using
`|fl(M*x_j-J_j^T)| + gamma*sum(abs(operands))`.

True SPD is independently established: an inverse-L witness bounds both
induced norms, and `||L^-1||inf*||M-LL^T||inf*||L^-1||1 < 1` verifies the
positive symmetric congruence. Its actual upper bound is
`1.4730120908787795e-8 < 1`; floating Cholesky success alone is insufficient.

An inverse witness `X` is rebuilt from that verified SPD matrix. A rounded-residual bound
`r = ||I-MX||inf < 1` yields the Neumann bound
`M^-1 = X*(I-R)^-1`. For each response residual vector `e`, the component bound
is `|X|*|e| + ||X_row||1*r/(1-r)*||e||inf`. This avoids multiplying every
coordinate by the largest inverse mass. Contact dot error, response error,
symmetric averaging and antisymmetric assembly discrepancy yield `delta_A`.
Each `delta_Aij/sqrt(Aii*Ajj)` must be at most the existing `1e-10` relative
KKT requirement; materially unresolved contexts refuse.

For original capacities `D`, a uniform objective uncertainty is

`Gamma = sum(D_i*delta_vi) + 0.5*sum(D_i*delta_Aij*D_j)`.

The **true** Gram objective is PSD because the verified physical `M` is SPD;
the proof does not assume a rounded Gram matrix is exactly PSD. At candidate
`p`, its compact feasible duality gap is bounded by the original gradient's
support gap plus `sum((D_i+|p_i|)*(delta_vi+sum(delta_Aij*|p_j|)))`, including
gradient/support evaluation roundoff. Convexity bounds true objective
suboptimality by that gap. Acceptance requires this upper bound `<= Gamma`
and `Gamma <= owner's energy ceiling`. No fixed speed/force tolerance enters.

The ordinary strict path runs first, byte-preserving successful results without
building inverse witnesses. The draft tries exact zero following strict
numerical refusal. This is the
minimum-norm feasible impulse, avoiding gratuitous null circulation. If zero
does not qualify, the original refusal is retained; this draft does not add a
new approximate candidate optimizer. Existing strict success is preserved.

Computed bounds are never trusted as caller capabilities: recertification
rebuilds them from their complete operands and checks exact original A/v bytes.
Capture recertification uses the same contract and owner ceiling, and still
checks the original passive objective and capacities.

## Results

- Exact Sym16: `Gamma=5.98078702310756e-17 J`;
  true objective gap upper `1.6235698676675174e-20 J`;
  original gap `1.6235698644378183e-20 J`.
- Distinct status `converged_at_assembly_resolution`; `strict_kkt_passed=false`.
  Original raw residual, tolerance and strict attempt are retained.
- Zero impulse/loss; unchanged physical CM/body/spin velocity; independent
  mass/slip/work checks pass. No physical capacity, force law or heat changes.
- Outward arithmetic covers subnormal bound multiplication and subsequent
  amplification; overflow and invalid bound operands refuse. True-SPD proof
  rejects a nonsingular indefinite matrix with a fabricated identity factor.
  Every genuine-motion case resolves an opposing reaction and positive loss.
- 51 new checks: ceilings below Gamma and zero refuse; genuine
  `0.001/0.1/1 m/s` motion cannot accept zero; bad solve, altered operands,
  forged uncertainty fields, non-SPD and unresolved ill-conditioned mass
  contexts refuse; velocity scales `0..1` and row units `1e-3/1e3` qualify.
- 659 strict regression checks pass, retaining Sym16's strict refusal as an
  expected oracle. 314 unchanged Impulse checks pass through the draft.

See `report.json` for exact source/fixture hashes and checked receipt paths.
The one earlier Impulse runner receipt used the wrong completion marker; its
raw 314 checks passed, but that receipt is **not** a successful checked run.
The corrected later receipt passes both checks and completion policy.

## Review boundaries and limitations

`traction.gd` starts from root's certificate-before-monotonic candidate and
adds only a private publication path for the explicit resolution receipt.
`assembly_roundoff.gd` keeps this study separate for review; its functions may
be folded into the QP by the owner. `impulse.gd` appends the opt-in energy ceiling
after capture; absent opt-in keeps strict behavior. Nothing consumes this
contract in production or runtime policy yet.

This certifies numerical objective resolution for the frozen-pose, fixed-mass
free common-rotor impulse assembly. It does not establish physical calibration,
whole-trajectory accuracy, contact entry accuracy, static-rest convergence,
performance, or the masterplan's ten-second conservation gate. The matrix
relative gate and owner energy ceiling are both necessary. Extreme arithmetic
may refuse; this is not an all-finite-input admission promise. The interval
bound helpers, exact operand binding, SPD theorem and status propagation still
require owner review before any production promotion.

Run from the repository root with the absolute console engine path:

```powershell
python tools/godot/run_checked.py --out-dir tmp/gp12-rest-fix/checks --label assembly-resolution-review --timeout 120 --require-text 'GP-12 assembly resolution:' -- C:/DEVELOPMENT/OpenRCsimulator/.tools/Godot_v4.8-beta1_win64_console.exe --headless --path app --audio-driver Dummy --script C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-rest-fix/test.gd
```
