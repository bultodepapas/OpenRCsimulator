# H18 — Evaluate the ground-effect wing wake once per oracle call

2026-10-27 · Linux dev VM (Intel i5-10500 under KVM, shared host) · Godot 4.8-beta1 official editor binary.

[`Aero._global_loads`](../../../../app/physics/aero.gd) is the attached-flow oracle evaluated at every RK stage. In
ground effect (M5-GE-1) it evaluates the strip wing's wake velocity twice with identical arguments
(`_wing_lift_coefficient_with(s, air, d, model, ge, true)`): once for the static ground-effect tail term
(`wake_ge`) and once as the source of the downwash-lag term (D11g). The strip law is pure, so the lag term now reuses
`wake_ge` when the ground-effect block has computed it, and evaluates it as before otherwise. No law, operand
order, output or aircraft data changes. Out of ground effect, and for aircraft without the downwash lag, the path is
unchanged.

## Profile and scope

A runway-idle script profile of the electric Stik (default field, lake and collision world) counted 13 strip-wing
evaluations per tick, each with its own `_wing_flow`: three per RK stage in `_global_loads` (free-air wake,
ground-effect wake, lag source) and one in `_pre_step` for the lag state. The reuse removes one per stage, four of
thirteen. It applies only while the wheels are within the ground-effect reach: taxi, take-off, landing and
low passes.
