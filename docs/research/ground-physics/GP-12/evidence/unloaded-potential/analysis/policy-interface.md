# Opt-in normal-loss policy draft contract

Production targets (drafts will live in `tmp/gp12-unloaded-policy`):

- `app/physics/aircraft_ground_step.gd`
- `app/physics/aircraft_ground_accuracy.gd`
- new `app/physics/aircraft_ground_unloaded.gd`
- focused new helper/policy tests and the owned composition test integration.

`advance(..., error_gate=Callable(), normal_loss_policy=Callable())` adds ONE final
optional trusted owner Callable. No option/sample boolean activates the method.
The callback has the same authority boundary as the existing derivative and
whole-piece certificate; generic Step cannot authenticate its captured evaluator.

Per piece, after the real prekick (identity on the Lie path), call
`policy(kicked_state, time_s, h, kicked_sample)` with detached read-only inputs.
Return exactly `{ok:bool,eligible:bool,identity:bounded nonempty String}`. A malformed
result, false ok or mutation refuses the attempt. A false eligible retains ordinary
RK normal heat. The identity is fixed across the complete candidate/refinement
comparison; receipt metadata cannot invoke the policy itself.

The owner closure must bind/revalidate actual prepared stage, live properties,
static plane provider, fixed motion and the actual source/brake/external-wrench
evaluator/configuration. It must exclude any nonzero external wrench or source,
brake/hold/carrier/heat-feedback changes over the entire interval before invoking
the specific zero-force reference helper. Instantaneous zero loads and
`source_policy=none` do not establish those assumptions. Captured-resource mutation
must refuse even if callback inputs themselves remain pure.

Eligible samples must explicitly supply `normal_support_potential_j>=0` and a
stable `normal_support_identity`. Step verifies support potential is unchanged
across pose-frozen kicks, fixed mechanical bindings remain unchanged, every actual
RK normal-force evaluation is zero and endpoint loads are zero. It then computes
the per-piece potential difference itself, refuses a negative result without a
clamp, and computes corrected piece residual/admission before accumulation.

With a policy present, a distinct mixed-method receipt records every accepted
piece as RK-normal-power or unloaded-support-potential-difference, actual loss and
corrected residual. Qualified entries also record support potential pair, identity
and actual zero-force sample count. Sum/max algebra and normal boundary samples
are validated structurally by Accuracy. Default absent-policy receipt bytes and
all physical comparison tolerances remain unchanged. Discarded attempts publish
no heat/proof/events. These receipt strings and counts confer no physical authority.
