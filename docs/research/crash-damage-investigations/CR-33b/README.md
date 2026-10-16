# CR-33b — Isolated impact-energy accounting foundation

2026-10-15. Adds a pure float64 estimate and budget allocator. This is a software foundation only; no physical damage threshold, component failure resolver, automatic destruction, or accepted solver-work measurement is added.

## Scope and equations

[`impact_budget.gd`](../../../../app/economy/impact_budget.gd) consumes a single contact sample expressed entirely in the aircraft body frame. It validates positive mass and reciprocal inverse mass, a finite positive-definite symmetric inverse-inertia tensor, finite three-vectors, a normalized normal, passive restitution in `[0, 1]`, stable contact/episode identity, an accepted tick, and input provenance. The six tensor values use the existing `RigidBody` order `[Ixx, Iyy, Izz, Ixy, Ixz, Iyz]`.

For arm `r` from center of mass to contact and outward unit normal `n`, the scalar effective inverse mass is

```text
k_n = 1 / m + (r × n)ᵀ I_body⁻¹ (r × n)
m_eff = 1 / k_n
```

Contact velocity includes rigid-body rotation:

```text
v_contact = v_linear + ω × r
v_n = v_contact · n
v_t = v_contact − n v_n
```

Only the closing normal mode contributes a candidate restitution loss:

```text
E_candidate = 0.5 m_eff max(−v_n, 0)² (1 − e²)
```

This is an isolated rigid-body estimate against an immovable surface. Tangential speed is reported as a diagnostic; without an accepted/measured friction impulse the helper assigns it no dissipated energy. A separating sample produces zero candidate loss. No gravitational, spring, speculative-stage, later-tick, or rebound energy is added.

Every returned quantity contains a value, SI unit, `isolated_estimate` basis, and source/evidence provenance. The sample's provenance must identify `state_stage: "accepted_tick"`; speculative solver trials are refused. An episode rejects duplicate contact IDs and mixed episode/tick samples. It sorts unique IDs before allocation so input order does not change the result. Each candidate receives a proportional share of `min(caller_budget, sum(candidate_energy))`; every allocation is bounded by its source candidate and the total remains bounded by the supplied budget. Candidate and budget partitions are nonnegative and sum to at most one. Caller-supplied component partitions are retained as given; the helper does not normalize them, and any remainder stays unassigned.

The budget's source string is provenance, not verification that the value is accepted solver work. `accepted_work_observed` remains false and every result remains `isolated_estimate`. The caller must deduplicate an episode across calls and must provide one immutable accepted-tick contact set. These functions do not infer survival, repair, replacement, salvage, or any component disposition.

## Verification

The focused [`test_economy_impact_budget.gd`](../../../../app/tests/test_economy_impact_budget.gd) passes **36 checks** under pinned Godot 4.7.2 headless. It checks central and off-center analytic effective mass, head-on versus glancing energy at equal speed, combined translation/rotation point velocity, no separating or tangential loss, deterministic bounded episode allocation, duplicate contacts, partition limits and order, positive-definite tensor validation, provenance, speculative-state refusal, and invalid/nonfinite inputs.

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --check-only --script res://economy/impact_budget.gd
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --check-only --script res://tests/test_economy_impact_budget.gd
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_economy_impact_budget.gd
```

These analytic fixtures establish code behavior only. They are not measured impacts, accepted-work validation, restitution calibration, or evidence of structural capacity.

## Measurements still required

Before the estimate can represent an accepted physical impact, a source-hash-pinned aircraft/configuration record must provide as-built mass, center of gravity, full inertia tensor, contact geometry and stable contact-to-component/joint IDs. Each sample needs synchronized pre/post accepted states, relative surface/obstacle velocity, contact normal, accepted normal/tangent impulse or calibrated force-time history, contact duration, solver/build identity for simulation data, and uncertainty. The current helper assumes a stationary contacted surface and one body's effective mass; moving obstacles and coupled multi-body effective mass are not measured here.

To estimate tangential dissipation, measure accepted friction impulse/work and validate the friction response over the tested surface, load, speed, and contact-duration range. Restitution also needs representative measured outcomes; the input coefficient is bounded for passivity but is not calibrated by this change. Record simultaneous-contact identity and accepted-stage semantics so repeated ticks and speculative slapdown trials cannot enter the same incident allocation.

To infer damage, the model still needs aircraft-specific construction and joint evidence; instrumented representative coupons, joints, gear mounts, and whole-assembly load paths; measured deformation, slip, tear, fracture, function, and post-event serviceability; repeated conditions, uncertainty, and held-out validation; and an evidence-backed map from contact/load path to non-overlapping economic components. Energy alone is not a failure observation. The measurement contract in [CR-33a](../CR-33a/README.md) lists these requirements and thermal/gear extensions.

The [crash research index](../README.md) still marks CR-07's report 03 (RC construction/material/joint impact thresholds with applicability and uncertainty) as pending, and notes that its source document is missing. CR-33 requires that evidence and an independently validated outcome model. This implementation closes neither CR-07 nor CR-33; do not add or tune physical thresholds from these equations or fixtures. See the [CR-33–35 billing gate](../CR-33a/README.md#billing-gate) and [economics plan](../../../plans/crash-damage-economics.md#4-contact-to-damage-calculation).
