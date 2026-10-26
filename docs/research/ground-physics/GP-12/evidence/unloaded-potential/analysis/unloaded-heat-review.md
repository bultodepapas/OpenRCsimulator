# Unloaded rebound: exact support-potential heat experiment

2026-10-26. Draft-only numerical experiment, using the unchanged retained gentle
tape. No Step, Accuracy, normal law, force, state, material, geometry, tolerance or
production code was changed. This is narrower than a general floating root guard.

## Result

`test_unloaded_heat.gd`:103 checks,0 failed. Its8/16 uniform paths have exactly the
same final state bytes as their original split paths. All accepted-piece reference
guards close; every actual RK force evaluation has all normal loads exactly zero
(40/80 samples including endpoint observations). No branch root is located and no
extra physical piece is inserted.

| Quantity | Original uniform path | Candidate ledger-only path |
| --- | ---: | ---: |
| raw8/16 normalized physical error |1.3397203884, refuses |2.8421709431e-12, passes |
|8/16 normal heat difference |2.5829242632e-6 J |0 J |
| normal heat, both candidate paths | — |0.0001850110305772057 J |
| coarse total mechanical/work residual |−2.0024112794e-6 J |−1.0326516118e-13 J |
| fine total mechanical/work residual |5.8051287009e-7 J |−2.1695199890e-13 J |

The production Accuracy validator **refuses** the truthful new quadrature marker.
`heat_accuracy.gd` is an isolated copy extending only receipt method validation;
the complete body/continuous/peak/work channel formulas and all prepared physical
tolerances remain byte-for-byte unchanged. Its passing gate is a proposed receipt
protocol result, not production runtime admission. The original validator refusal
and original raw error are retained in `unloaded-heat-results.bin/json`.

## Physical identity and ownership

The sole compliance owner has `dV/dx=F_el` and
`Ddot=(N-F_el)*xdot`. On an all-support `N=0` interval,

`D=V_support(start)-V_support(end)`.

This includes crossing x=0 because support potential and elastic force have the
declared unilateral continuation. It needs no root, restitution impulse, second
force law or heat clamp. The experiment reads **only** `physical.ground.potential_j`,
not the combined sample potential (which includes CM gravity). The end support
potential is exactly zero on both paths. A negative potential difference refuses.
No other work/loss field or state/velocity is modified. The existing independent
force/state/raw error channels remain active; the identity does not excuse force
integration error. It evaluates constitutive heat from the same approximate
endpoints instead of numerically integrating a known antiderivative's kink.

Each accepted piece computes its own potential difference and corrected energy
residual, checks the original piece-energy target, and only then contributes to
the heat sum and maximum residual. The receipt retains piece start/end potentials,
losses and corrected residuals. Maxima are1.451e-13 J /1.781e-13 J; old RK-heat
maxima are preserved in the baseline and are not copied into the candidate. This
fixes an independently discovered stale-diagnostic issue in the initial draft.
Altered piece heat, broken potential chains and stale maxima refuse in tests.

The normal potential cancels identically from the corrected total energy residual.
That residual therefore cannot independently validate support geometry/potential
or exit timing. The fixture separately checks direct closed-form plane-ring gap
and `.5*k*x^2` at every accepted endpoint, independently of Normal.evaluate, with
operand-derived gap arithmetic bounds propagated to potential. It also retains
the unchanged complete state/work comparisons. Independent agent review agrees
with the identity and this limitation; final source review remains separate.

This correction cannot be applied across a loaded piece: the omitted term would
be `integral N*xdot dt`. A future mixed path must sum this difference only on each
individually qualified all-zero piece and retain ordinary RK heat on all other
pieces, with explicit per-method counts and accepted-piece-only accounting. It
must not telescope the entire outer tick when any intervening piece is loaded.

## Useful qualified exact reference-flow slice

`test_unloaded_reference_guard.gd`:168 checks,0 failed. Unlike a sampled-zero flag,
its `_bound` proves the following for this source-free, constant live mass/CG,
fixed body-axis/zero-carrier, no-brake/hold, static-plane owner fixture:

1. The angular+spin stage matrix is already at CM. Stage transfers total moment
   `O->CG` before Rotor.evaluate_system using the live CM inertia; FixedDatum
   separately corrects datum translational acceleration with the final alpha.
   Impulse uses `diag(m I3, stage.matrix)` with `V_CM=v_O+omega cross cg`.
   Thus the angular reduction does not omit datum translational coupling. Tests
   independently reconstruct CM position/velocity and verify ballistic motion.
2. Partition the actual constant CM angular matrix as `[[B,U],[U^T,D]]`, where D
   is the positive free-spin diagonal. Zero local torque conserves
   `ell=D sigma+U^T omega`. Set `A=B-U D^-1 U^T`, `h=U D^-1 ell`.
   Euler's equation becomes `A omegadot=-omega cross(A omega+h)`, giving conserved
   reduced energy `.5 omega^T A omega`. This uses the actual noncanonical P51
   shaft axis; a canonical-axis shortcut was correctly refused and retained.
3. A3x3 Schur center has a Cholesky/congruence SPD proof, inverse lower witness
   and explicit symmetric assembly error. The resulting true-Schur beta is
   3.7079524830 kg*m^2; entry-error row norm bound5.4344e-14 kg*m^2.
   Direct reduced energy (no large shaft-energy subtraction) yields
   `|omega|<=0.01341886568 rad/s` over the exact zero-load reference flow.
4. Each plane gap satisfies
   `gdot >= n.V_CM0 - gravity*h - (|hub-cg|+R)*Omega_upper`.
   The lower bounds are0.6362913970 m/s at the mains and0.6349487566 m/s at the
   tail. Kappa stays above0.999944088. All gaps strictly increase, so separated
   mains are event-free and the initially compressed tail has at most one gap
   exit. Compression never exceeds its initial upper bound.
5. No support reaches its progressive stop. With negative compression rate and
   x<=xmax, the damping-ramp ratio `ramp(x)/x` is nonincreasing. Therefore
   `trialN/x <= k-c_rebound*ramp(xmax)/xmax*gdot_lower`.
   Its tail upper bound is−5173.304535 N/m. The other supports remain separated.
   Hence all normal forces stay zero by a self-consistent free-flow bootstrap.
   Initial impulse rows are empty and remain empty; the halfkick is identity.

The actual17 RK duration samples stay inside these reference bounds, with
constant stage matrix bytes. Independently measured CM ballistic errors are
2.239e-16 m and8.951e-16 m/s; reduced-energy-times-two variation is2.169e-19 J.
The loaded hard tape, inward motion and an entering brake boundary refuse.

The reference helper explicitly returns `floating_rk_admitted=false`. These
measurements are not a formal enclosure of every floating intermediate duration
or an all-loaded/full-aircraft RHS proof. Root localization is unnecessary for
this non-force heat kink, reducing what a future opt-in ledger policy must prove.
Before production, the owner certificate and numerical evaluation contract still
need independent review; the validator's method/count/algebra checks do not turn
caller metadata into a physics theorem.

## Proposed truthful receipt extension

Keep default receipt bytes/validation unchanged. Candidate marker:

`quadrature_method=RK4_external_work_unloaded_normal_potential_difference_v1`.

An explicit `unloaded_normal_loss` dictionary identifies
`all-zero-normal-support-potential-loss-v1`, start/end support potentials,
qualified accepted-piece count, actual zero-force RK sample count and owner scope.
The draft validator checks nonnegative per-piece exact potential-loss algebra,
the continuous potential chain, ordered loss sum, corrected maximum residual,
piece/sample counts and zero accepted normal samples; altered heat, increasing
potential and loaded accepted samples refuse. It is structural validation only. Actual
interval qualification is supplied by the owner proof and checked force samples.

No new numerical energy allowance is charged: this is an exact constitutive
antiderivative at the same endpoints, not a roundoff waiver or an accuracy floor.
The raw interpath state/work targets are unchanged. The harder loaded cap-area
case remains open and is not covered by this result.
