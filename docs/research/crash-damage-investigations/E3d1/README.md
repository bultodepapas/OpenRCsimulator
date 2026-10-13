# E3d1 — Soft crash-hull contacts

2026-10-13 · **Status:** implemented for interactive flights; numerical contact choices are estimates. **Serves:** [crash realism plan](../../../plans/crash-realism.md) (owner request: "soft crash wing tips"), [research 04 §6](../../roadmap-investigations/04-ground-handling-collisions.md#6-contact-geometry-crash-versus-scrape-damage) step E3d1. Supersedes the 2026-10-05 "ground contact = crash" rule on interactive flights only.

## Behaviour

On Home and direct interactive flights:

- A light wingtip brush, a tail touch or a belly slide no longer ends the flight. The airplane is pushed back by the ground and slows by friction.
- A **new** contact ends the flight only when the struck point's normal energy per kilogram of airplane reaches the CR-08b C2 cut: ½·m_eff·v_n²/m ≥ 2.5 J/kg, surface transfer 1, graded on the point's state the tick before it touched.
- A point pushed deeper than 8 cm also ends the flight (a slow crush).
- Gear overtravel is unchanged.

The crash card then grades at least C2 and the snapshot records `soft_rule` (`impact` or `depth`).

Scripted, capture and trace routes keep D9d's "any hull contact is a crash", so golden traces are unchanged. `-- --soft-contacts=off` restores it interactively.

## Implementation

- [hull_contact.gd](../../../../app/physics/hull_contact.gd), pure float64:
  - **Normal force.** Each hull point in the field is a spring-damper along the ground normal: k = m_eff,min·ω², c = 2ζ·m_eff,min·ω, with ω = 60 rad/s and ζ = 0.7. m_eff,min is the point's smallest effective mass over 26 body directions, so no point exceeds ω·dt = 0.25 at 240 Hz in any attitude. Damping ramps in over the first 4 mm, and the force never pulls into the ground.
  - **Friction.** Regularized Coulomb friction in the ground plane: μ = 0.4, linear below 0.2 m/s.
  - **API.** `terminal()` applies the crash rule; `contacts()` feeds presentation.
- [flight_session.gd](../../../../app/sim/flight_session.gd) adds the loads inside `_ground_evaluation`, the single ground path for every integrator route; an empty result adds nothing. `soft_hull_contacts` is off by default, and [main.gd](../../../../app/main.gd) turns it on interactively. The scenery post-step no longer turns a ground touch into a crash when the option is on. [impact_snapshot.gd](../../../../app/physics/impact_snapshot.gd) `hull_point()` names the triggering point.
- Presentation: [director.gd](../../../../app/render/crash/director.gd) reads `session.soft_contacts` while no crash is shown.
  - A new touch gets a scuff mark, a small directional puff (`effects.touch()`, a 24-particle emitter of its own) and a surface thud or a scrape.
  - A slide above 1.5 m/s leaves a mark trail every 0.12 s.
  - Restart clears them.

## Evidence

- [test_soft_contacts.gd](../../../../app/tests/test_soft_contacts.gd): **26 checks**. The research 04 anchors:
  - **Wingtip brush** (Stik, bank 40°, 15 m/s, 0.5 m/s sink): touches at tick 5, ≤ 8 mm deep, no crash.
  - **Vertical nose-in at 10 m/s:** crash, naming the spinner and the `impact` rule.
  - **Avanti belly landing** (no gear, 12 m/s, 1 m/s sink): slides to 0.08 m/s in 6 s, 2.5 mm deep, no crash.

  Also covered: the default route remains legacy, one second of flight away from the ground is bit-identical with the option on, runs repeat exactly, the stiffness bounds hold (Stik tip 668 N/m against belly 9,702 N/m), friction stays inside the Coulomb bound, the damper never pulls, the depth backstop crashes, and an existing contact is not re-graded. The terminal cut is pinned to `Severity.CLASS_CUTS_J_PER_KG[1]`.
- [test_soft_contact_feedback.gd](../../../../app/tests/test_soft_contact_feedback.gd): **10 checks** in the production scene. A brush continues with a mark and a puff, the aftermath stays idle, the source airplane stays visible, the effects budget holds, and restart clears the marks.
- [Mutations](../../../../research/crash-damage/e3d1/mutations.log): **13/13 killed**.
  - Physics: no friction, whole-mass stiffness, a pulling damper, cuts too lenient or too strict, existing contacts re-graded, no depth backstop.
  - Integration: loads not applied, on by default, legacy route soft, production not enabled, no feedback, marks not cleared.

  The first run let "existing contacts re-graded" survive; the check now presses an existing contact at 10 m/s.
- [test_crash_integration.gd](../../../../app/tests/test_crash_integration.gd) now arms a real 20 m/s impact instead of a resting touch, because production flights are soft; 95 checks pass for all aircraft.

  These pass unchanged: crash, snapshot, effects (57), audio, wreck, breakup, labels, proportional, pose, ground contact, landing variations and manoeuvre, scenery damage and collision sessions, `test_trace_acceptance.py`, and `check_math_sensitivity.py`.

## Limits

- Flat field only (`down = 0`), as the legacy detector. Terrain heights wait for the L12 sampler.
- μ, ω, ζ, the 8 cm backstop and the 2.5 J/kg rule are estimates. Airframe and turf compliance are not measured.
- Hull points are sparse, so an edge between points can pass through the ground until a point reaches it.
- A long sustained tip slide is not a crash by itself (research 04 proposed > 8 m/s for > 0.2 s); a resulting ground loop is graded when another point first touches.
- No prop strike yet (E3d2): a spinning propeller touching is graded like any other point.
- Damage is not carried over. A scraped airplane flies on undamaged (CR-11–15).
- A crash aftermath clears earlier touch marks.
