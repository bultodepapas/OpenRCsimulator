# Duration-dependent prekick: proven bound and remaining owner guard

2026-10-26. Draft-only analysis/tests. No production changes, no accepted runtime
policy, no all-aircraft qualification. The prior known-bracket experiment remains
in `review.md`; its actual nonuniform Accuracy refusals remain unmodified.

## Frozen impulse is a proximal map

Use the actual full CM/common-rotor velocity `z`, SPD mass matrix `M`, fixed
Jacobian `J`, fixed prescribed bias `b`, and a compact centrally symmetric set
`C` of rate impulses. The current groups partition all rows into1D intervals and
2D ellipses. Each cap is multiplied by the same positive duration once.

The exact dual QP is

`min_{p in a C} .5 p^T A p + (Jz+b)^T p`, `A=J M^-1 J^T`.

Its physical velocity is the unique minimizer

`K_a(z)=argmin_w [.5 ||w-z||_M^2 + a R(w)]`,
`R(w)=support_C(Jw+b)`.

The sign follows by setting the support-function dual variable to `-p/a`;
central symmetry makes this the same feasible set. Singularity of A allows
nonunique row impulses but does not destroy uniqueness of the physical velocity.
This connection uses the proximal/resolvent definitions in
[Parikh and Boyd, sections1.1,2.3,3.2](https://web.stanford.edu/~boyd/papers/pdf/prox_algs.pdf).
The parameter-sensitivity derivation below is ours, not a theorem attributed to
that reference.

Write `M(w_a-z)=-a g_a`, `g_a in partial R(w_a)`, similarly for b, and assume
`a>=b>=0`. With `d=w_a-w_b`, subgradient monotonicity gives

`||d||_M^2 = -b d^T(g_a-g_b) -(a-b)d^T g_a`
`<= (a-b) ||d||_M ||g_a||_{M^-1}`.

Thus `||K_a(z)-K_b(z)||_M <= |a-b| L`, where
`L=max_{q in C} sqrt(q^T A q)`. For disjoint current groups a directly usable
conservative bound is

`L <= sum_groups sqrt(sum_{i in group} c_i^2 A_ii)`.

This uses the operator norm<=Frobenius norm for each grouped ellipse and the
triangle inequality across groups, retaining cross-coupling in a conservative
bound. Row-unit transformations `J_i<-s_i J_i`, `b_i<-s_i b_i`,
`c_i<-c_i/s_i` leave it unchanged. The first halfkick has parameter `a=tau/2`,
so its exact derivative norm is at most `L/2` almost everywhere.

Current code satisfies the frozen assumptions at one prekick: Step supplies one
initial sample, scales all its fixed rate caps by half-duration, and Impulse
assembles the common SPD response. It does **not** keep M/J/C fixed between
accepted pieces; rebuild the bound from every piece's actual initial sample.
Changing the normal load/caps during a single duration query would invalidate
this particular proof. Bias is allowed if it is fixed; current Step restricts it
to zero. Relative holds, moving carriers/hubs, live mass change and source events
are outside this guard. Capture's finite roundoff polish is not the exact prox;
exclude it initially or include its separately bounded final velocity correction
and any domain refusal. Never silently continue a reverse/domain-refused branch.

## Finite precision is a tube, not a derivative theorem

For a feasible impulse with a **verified physical objective gap** epsilon,
convex optimality gives `.5 ||w_p-w_exact||_M^2 <= epsilon` even when A is singular.
The ideal velocity error is therefore at most `sqrt(2 epsilon)`.
An ordinary rounded strict KKT report alone is not that physical proof. The
existing assembly-resolution machinery can establish a true physical gap, but
the owner's maximum energy budget is an acceptance ceiling, not the actual error.

Add response/update arithmetic, not a velocity floor. If
`rho=(M delta-g)+(g-J^T p)`, the exact response error has M-norm at most
`sqrt(||M^-1||_2) ||rho||_2`, using actual residual intervals and the verified
inverse witness. Add the M-norm of the published addition error, recoverable
with TwoSum under the existing arithmetic contract. Also enclose Step's actual
CM-to-datum and rad/s-to-state conversions/reconstruction; the flow consumes
those published state bytes, not the ideal direct generalized velocity.

For two evaluated durations the total bound is

`||Ktilde_tau-Ktilde_sigma||_M <= L |tau-sigma|/2 + E_tau + E_sigma`.

An additive E tube permits arbitrarily fast small oscillations. It does not
justify a duration derivative for the floating implementation. Enclose a single
root of the qualified exact reference family and propagate an explicit surface
tube/root-time uncertainty; do not promise a unique floating zero. Certified
endpoint signs must exceed the propagated surface error. If the error tube is
larger than the existing surface/time targets, refuse or improve the arithmetic
bound rather than replacing it with the owner's budget as a floor.

## Normal-flow sensitivity closes the mathematical gap

For an exact smooth qualified flow, with E embedding velocity into state,

`G(tau)=s(Phi_tau(K_{tau/2}(z)))`,
`G' = Ds f + Ds D Phi_tau E K'`.

The second term is the missing duration-dependent prekick contribution. Suppose
the owner proves a comparison enclosure in compatible position/velocity norms:

`d/dt [||delta q||,||delta u||]^T <= B [||delta q||,||delta u||]^T`,
`B=[[a,b],[c,d]] >=0`, `P(t)=exp(Bt)`.

With initial position perturbation zero, the additional surface derivative is
bounded by `(gq P12 + gu P22) L/2`, where gq/gu bound the position/velocity
parts of Ds over the full family. For a ring gap gu=0, so the extra term starts
at order tau. For trial normal load `F_el(x)+c(x,xdot) xdot`, gu includes damping
times the gap Jacobian and need not vanish at tau=0; position sensitivity also
includes damping-ramp and gap-rate geometry derivatives.

If the owner encloses ordinary `Ds f` in `[l,u]`, a sufficient increasing guard
is `l > correction`; a decreasing guard is `u < -correction`. A range/Lipschitz
bound from the same terms can exclude zero on a covered interval. Intervals not
excluded or covered by a single-root guard refine/refuse. This is also how to
detect/exclude interior double crossings without trusting a finite sample set.

For the **actual RK4 duration family**, exact-flow derivatives are insufficient.
It is possible to enclose the discrete duration derivative using only validated
first-Jacobian bounds at every algebraic stage:

`y0'=K'`, `k1'=Df(y0)y0'`,
`y2'=y0'+k1/2+tau*k1'/2`, `k2'=Df(y2)y2'`,
`y3'=y0'+k2/2+tau*k2'/2`, `k3'=Df(y3)y3'`,
`y4'=y0'+k3+tau*k3'`, `k4'=Df(y4)y4'`,
`Y'=y0'+(k1+2k2+2k3+k4)/6+tau*(k1'+2k2'+2k3'+k4')/6`.

Include the derivative/enclosure of the actual endpoint quaternion normalization,
local normalized stage rotations, raw quaternion ODE and final surface arithmetic.
Nonsmooth constitutive branches use valid one-sided/Clarke bounds or are themselves
partitioned; a sampled finite-difference Jacobian is not an enclosure.

## What is practical now, and what is missing

The frozen prox part is usable now. `test_prox_duration.gd` passes130/0 including
scalar sticking, a coupled physical SPD mass with singular dual Gram, affine bias,
row-unit rescaling, harmonic normal-flow sensitivity, and a duration-family double
crossing. Actual frozen gentle-tape L=0 (no initial rows/caps); hard-tape L is
23.02281443603744 in common-M rate units, with measured kick sensitivity only
0.000622904 of that conservative bound. These measurements validate implementation
sanity; they do not prove a whole interval or replace outward arithmetic.

The independent counterexample has exact scalar prox `K_{tau/2}(.75)=.75-tau/2`
on `[0,1]` and free flow `G(tau)=-.26+.75*tau-.5*tau^2`. Every individual normal
trajectory has positive speed (at least.25), yet the duration family has two
crossings and a turning point. The complete derivative guard correctly refuses
monotonicity. Bounded objective error alone also fails a derivative test.

The concrete missing owner machinery is a validated full normal-RHS/algebraic-RK
enclosure including common-rotor gyro/transport, gravity rotation, camber-dependent
gap/rate geometry and actual state conversions. `Normal.bounds_interval` supplies
scalar force slopes. `plane_envelope` supplies mobility/material/geometric rate
bounds and explicitly disclaims a full RHS certificate. Neither supplies the B,
directional `Ds f`, or discrete stage Jacobian enclosures above. Claiming a complete
guard now would replace missing terms with an assumption. An interval/analytic
RHS extension is a real bounded implementation task, not a constant to tune.

## Internal-normal-subflow alternative, measured honestly

`internal_step.gd` keeps each outer halfkick at its original half-duration and
locates the selected known bracket only inside that fixed-initial-velocity normal
subflow. It splits RK quadrature there, sums both normal fragments' work, then
executes the original closing halfkick. No impulse is inserted at the inner root.
This removes the prekick duration term for that root search, but still requires
normal-flow uniqueness/exclusion and finite arithmetic enclosures.

Both original and locally tightened conditional rate-envelope experiments pass
14/0 software checks. With8 outer pieces they use9 normal fragments, energy
residual magnitudes below2.50e-13 J. Four outer pieces refuse rate admission;
16 outer pieces plus a branch correctly refuse the same16-fragment ceiling.
Therefore there is no admitted complete4/8 or8/16 error-gate pair to publish.
The raw gate is retained as unavailable, not replaced by channel checks.

The harder tape's tangent heat remains exactly the original8-piece value
0.0001786378217859407 J. Normal-only splitting does not remove the first/last
impulse cap-area kink, so it does not resolve the harder tape's actual raw
interpath failure. It is a useful simpler route for the gentle zero-kick heat
case, not a demonstrated replacement for the complete split branch method.

## Evidence

Latest passing receipts: `checks/prox-duration-coupled-*` (130/0),
`checks/internal-known-brackets-*` (14/0), and
`checks/internal-local-known-brackets-*` (14/0). Original rejected development
receipts remain: the first prox test used unsupported packed-array subtraction;
the next queried the positive-cap halfkick at duration zero (correctly refused);
the first internal draft had an untyped variable parse error. They are not passing
evidence. `guard-manifest.json` pins the current exact sources/inputs/engine and
all final receipts/results. No Godot job remains live for this task.
