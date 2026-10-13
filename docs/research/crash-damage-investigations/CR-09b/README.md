# CR-09b — Proportional, momentum-directed breakup

2026-10-13 · **Status:** implemented; presentation only. **Serves:** [crash realism plan](../../../plans/crash-realism.md) §3.3. Builds on [CR-09a](../CR-09a/README.md), [CR-08b](../CR-08b/README.md) grading and [CR-01d](../CR-01d/README.md) hull names.

## What changed

[wreck.gd](../../../../app/render/crash/wreck.gd) no longer breaks every structural crash the same way.

| Class | Struck component | Released sections |
| --- | --- | --- |
| C2 | spinner, propeller, nose | propeller |
| C2 | stab tip / fin top / canopy / gear | tailplane / fin / canopy / gear |
| C2 | wing tip, belly, tail end, fuselage | none (one body, as before) |
| C3 | left / right wing tip | that wing half (the single wing section on models without halves) |
| C3 | spinner, propeller, nose, engine | propeller, engine, canopy |
| C3 | stab, fin, tail | both tail sections |
| C3 | canopy (inverted) | canopy and fin |
| C3 | gear | gear and propeller |
| C3 | belly, fuselage, unnamed | previous set: wings and tails |
| C4 | any | every section |

The later C3 contact-exposure releases (propeller, gear, canopy, engine) are unchanged.

- **Order.** [director.gd](../../../../app/render/crash/director.gd) passes the contact point (`contact_point_world`). Each section's release delay is its distance from that point divided by an estimated 15 m/s break speed, clamped to 0.02–0.35 s. The struck section goes at 0 s. Without a contact point the previous fixed delays remain.
- **Scatter.** The bounded scatter impulse (unchanged 12 % / 600 J caps) now points along the horizontal momentum, with an outward share of 0.35 and a lift share of 0.25. Before, it pointed radially out from the core centre, which read as an explosion.

All values are presentation estimates, not material limits.

## Evidence

- [test_crash_breakup.gd](../../../../app/tests/test_crash_breakup.gd): **27 checks** on the Stik twin.
  - Every row of the table above.
  - C2 adds no scatter energy and conserves mass.
  - Nearer sections never release later than farther ones; the left wing goes before the right for a left contact.
  - The delay bounds hold, and the legacy delays remain without a contact point.
  - Summed scatter along the slide is 9.0 m/s against 2.4 m/s across it.
  - Reset clears the release state.
- **Unchanged suites:** `test_crash_wreck` (163), `test_crash_integration` (95), hull labels (112), effects (56) and pose (107).
- [Mutations](../../../../research/crash-damage/cr-09b/mutations.log): **7/7 killed** — radial scatter, no C2 release, C3 ignoring the component, contact ignored, inverted ordering, a nose hit releasing a wing, a C2 tip releasing the wing.

## Limits

- The section sets are typical RC outcomes chosen for presentation; CR-07 evidence is still needed for physical claims.
- The break speed is an estimate.
- Sections are the model's existing node groups; a wing tip cannot break off alone.
- The ordering test drives the wreck directly; the director's contact handoff is covered by the integration suite only through its normal crash path.
