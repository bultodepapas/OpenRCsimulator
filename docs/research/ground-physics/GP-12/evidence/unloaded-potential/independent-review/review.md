# Independent review: all-zero-normal-support heat

Read-only review, 2026-10-26. Variable-piece drafts remain unchanged. Reviewed
`gp12-branch-step/unloaded-heat-review.md`, reference guard, corrected per-piece
heat experiment and isolated marker validator. No production approval is implied
for an as-yet unwritten target policy.

## Physics conclusion

For fixed compliance parameters and matching compression coordinate/rate,
`dV/dt=Fel*xdot` and `Ddot=(N-Fel)*xdot`. Hence an interval with every support
`N=0` has `D=Vnormal(start)-Vnormal(end)`. The unilateral continuation has
`V(0)=Fel(0)=0`, so gap exit introduces no missing boundary impulse or heat term.
Use only the sum of the same normal-support potentials, excluding gravity,
shaft energy and other stored energy. Do not apply this identity to a loaded
interval: its missing term is `integral N*xdot dt`.

The constitutive law's positive elastic force and nonnegative damper imply
nonincreasing potential on a true zero-load compressed branch. A computed
negative difference must refuse; no zero clamp, rounding floor or extra physical
dissipation is justified. This is the exact antiderivative FUNCTIONAL evaluated
at approximate endpoints, not an assertion that the physical endpoints or
floating potential evaluations are exact. Bound endpoint geometry/potential
arithmetic in the qualified numerical domain.

For this narrow uniform-piece rule, an exact zero-load reference-flow theorem
plus zero normal force at every actual RK RHS evaluation makes the actual
discrete update identical to RK4 applied to the free RHS. A theorem about the
entire floating-duration family is unnecessary because no root is located.
That does not prove a continuous floating interpolant is unloaded, a global
trajectory error bound, or a loaded/aerodynamic aircraft guard.

## Concrete issue found and corrected

The initial experiment changed total normal heat and total residual while
retaining `maximum_piece_energy_residual_j` from old RK heat. That value is stale
and need not be conservative: an old heat error can cancel an unrelated flow
error. gp08's corrected 103-check source now computes each `D_i`, recomputes the
piece residual, applies the unchanged piece-energy gate before aggregation,
and rebuilds the maximum. Corrected maxima are about1.45e-13/1.78e-13 J. Original
baseline diagnostics remain preserved. This resolves the identified issue.

## What energy cancellation does and does not establish

With this rule, `K+Vnormal+D` cancels normal potential algebraically. A small
mechanical energy residual therefore cannot independently validate normal
geometry, potential evaluation, exit time or missed interior contact. It still
measures remaining kinetic/gravity/external-work integration balance. Keep the
unchanged raw full-state/work/heat comparison and independent endpoint geometry
and potential oracle. In the particular all-detached endpoint example, total
heat is physically independent of gap-exit time; zero coarse/fine heat difference
is valid but carries no exit-time information.

My checked independent oracle has11/0 assertions. Clipped linear unloading
through gap exit gives0.0005J, matching direct integration of the existing loss
rate. A separate smooth polynomial compression cycle is exactly detached at
RK4 stage times0,.5,.5,1 but loaded between them: normal force0.1402179565N and
positive heat1.724744677e-7J despite zero endpoint potential difference. Thus zero
sample counts and truthful-looking receipt strings alone are insufficient.
The oracle also shows why time-varying stiffness needs parameter work and why
combined gravitational potential would manufacture detached normal heat.

## Required production acceptance contract

1. A trusted model-owner policy is installed explicitly; absence preserves all
   old Step/Accuracy output bytes. A receipt marker or caller `unforced=true`
   flag cannot enable the rule. Generic Step cannot authenticate an arbitrary
   derivative closure; document this boundary and keep the actual owner factory
   narrow, sealed and revalidated against the same evaluator/configuration.
2. Bind fixed mass/CG/full common angular matrix, fixed hubs/axes/carriers,
   immutable normal profiles and support IDs, static qualified plane/provider,
   and source/brake/hold/event configuration over the entire piece. Current
   guard is source-free with empty impulse rows; instantaneous zero aero/source
   wrench is insufficient. Nonzero relief/lake geometry, live mass/fuel, external
   aero or future source/brake transitions need their own proof or refusal.
3. Call the guard on the actual POST-prekick state/sample and actual duration,
   independently for every candidate and accepted piece. Revalidate captured
   resources, not just detached callback arguments. Unsupported eligibility
   falls back to ordinary RK heat; malformed authority or an eligible guard
   contradicted by actual force samples should refuse explicitly.
4. Independently inspect every actual RK RHS normal reaction, including cached
   k1 when used, plus relevant initial/end samples. Require zero, never mask or
   overwrite a force. The method changes no state, force, impulse, external
   work, tangent heat or prescribed-work ledger. Pose-frozen kicks must preserve
   the same support-potential binding and value.
5. Read an explicit finite nonnegative NORMAL-support potential field; do not
   subtract the combined sample potential. Compute per-piece loss and corrected
   residual before its existing energy gate; accumulate accepted pieces only.
   Rebuild maxima and accepted work/allowance counts without discarded probes.
6. Mixed paths need a method for EACH piece. Use potential difference only on
   individually qualified all-zero pieces and RK heat otherwise. Never telescope
   the whole tick across an intervening loaded piece. Retain actual uniform
   clocks, piece counts, phase work/loss signs and sampled-peak semantics.
7. Receipt validation is structural/algebraic, not interval authority. Pin the
   explicit heat/partition law and declared owner scope, type-check selectors,
   and reject altered piece loss, potential chain, corrected maxima and loaded
   method samples. No metadata string or force-sample count is a theorem.
8. Preserve raw Accuracy channels/tolerances and default compatibility. The
   opt-in ledger/method belongs in solver/profile identity: altered heat and
   piece-energy gates can change accepted refinement and therefore the actual
   trajectory even when fixed-count states are identical. Existing protocol
   refusal of the new marker remains honest until reviewed integration.

Final concrete payload reviewed: `tmp/gp12-unloaded-policy/manifest.json`, SHA256
`76ba1936985d61183f97c58d125c527de855d0d127777fc195b0e19f70127d7d`.
All six payload hashes, both main prehashes and six report/log hashes matched at
review time. Production scripts use res:// imports only. No app writes here.

The Step/Accuracy/helper satisfy this bounded contract; no remaining numerical
or ownership blocker was found. The trusted caller remains responsible for the
actual source/aero/brake exclusions over the interval. The focused test owner
binds and revalidates those resources and its source law on every evaluation.
Receipt metadata supplies structural accounting only. Arbitrarily inconsistent
or malicious derivative/evaluator closures remain outside this kernel contract.

Final targeted receipts report 130 policy + 167 Step + 84 Accuracy checks, all
complete with zero errors/warnings. Their warnings-as-errors setting is false;
observed logs are clean. These are gp08 runs reviewed by identity, not rerun here.
Default full-dictionary bytes are covered by retained 8/16 gentle parity tests.
The independent review retains 11 constitutive-oracle checks and the resolved
malformed-selector reproduction.

Promotion condition: add `/app/tests/fixtures/ground_unloaded_*.bin -text` as
declared by the manifest, then run production-location checks. This review does
not establish full-tape completion, loaded-contact qualification, stock admission,
a floating-duration guard theorem or performance qualification.
