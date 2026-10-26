# Independent bounded shaft-publication source review

2026-10-26. Reviewer: GP14 lifecycle/event owner. **No actionable issue found**
in the reviewed ordinary caller/preparation/publication path. No app edits and no
independent test rerun were performed for this review.

Reviewed main and draft FlightSession bytes are identical:
`2722c3d8d28382c38a81cf2f4311eb42f96430a765d4937e288bc91b3e7913d6`.
Compared against `flight_session.before.gd` SHA
`dd8278224b72e52dac03b37545d48c9e798d653f9ea11496d06c786c7061b345`.
Also read AircraftPropulsionRuntime.prepare_callbacks/_context, source selection,
the existing shared transaction/publication owner, main CLI setup order and
FlightLog CLI replay setup order.

Findings:

- Mode/type/live-flight/finite-source validation precedes mutation. Pre-setup
  selection remains separate from an installed-flight notification; a same-mode
  request stays silent.
- The transaction captures the old closing checkpoint before mode/layout choice.
  Checkpoint-validator reentry or protected mutation refuses through the existing
  quiet rollback before recorders close. The known callback preparer is structural
  and calls the established pure source/layout accessors; it does not advance a
  vehicle stage or physical state.
- `_install_continuous_callbacks` is an extraction of the previous assignments:
  same CALLBACK_FIELDS, substep selection after stage installation, then declared
  events. It changes no integrator/derivative arithmetic.
- Accepted pending selection installs its callbacks before guarded notification,
  retains the old closing context for recorder/pause listeners, publishes no tick
  or statistics receipt, and cannot be rolled back by a publication observer.
  Protected faults leave the new pending choice paused; the explicit later reset
  alone constructs the new physical layout and advances generation.
- Re-selection while pending intentionally has no available new full checkpoint;
  the original old footer remains intact. Returning to another mode still requires
  the explicit reset, avoiding a false-ready intermediate state.

Reviewed root-run receipts (not independently rerun):

- `checks/draft02-z2gq9ik5/report.json`: focused155/0, complete, zero diagnostics.
- `checks/coupled-draft-68qza9_7/report.json`: existing coupled99/0, complete, zero diagnostics.

Root reports the subsequent production cohort separately; this note is source
review and does not claim those executions as an independent measurement. The
guard remains bounded to declared kernel/model/owner fields and normal Session
entry points, not arbitrary external callback globals.
