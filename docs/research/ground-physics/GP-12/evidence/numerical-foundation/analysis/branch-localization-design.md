# Common gap/load branch partition — proposed contract

Read-only design, 2026-10-26. The live rest source is unchanged. The two retained
probes are numerical experiments, not runtime certificates.

Reuse `app/physics/event_bracket.gd::propose` and the record vocabulary of
`resource_event_step.gd` (`id`, `sense`, `surface_unit`, per-surface tolerance,
stable priority). Do not call `ResourceEventStep.advance` around the present
operator: its RK-only trial cannot own the two finite QPs, contact work receipts,
pre-kick reevaluation or complete-path accuracy contract. `EventStep`'s projected
continuous-index boundary is also inappropriate: these surfaces partition a
constitutive branch without projecting any physical state.

Two surfaces, same locator:

* Ring gap: use the existing authoritative `WheelGeometry.plane` on local
  normalized attitude and authored hub/axle/radius, including when NormalStage's
  broad-phase airborne record intentionally omits `gap_m`. Outgoing surface can
  be `-gap` with falling sense. Incoming crossings use the opposite sense.
* Load clip: use the **unclipped** normal trial force while compression is
  positive. `max(0,trial)` alone has a zero plateau and loses the bracket sign.
  The constitutive helper should expose its existing `trial` as receipt data;
  no second compliance law belongs in the locator. At gap zero the gap surface
  takes precedence and disables the compression-only load surface.

For an actual candidate first fragment of duration `tau`, define the trial as
`PreHalfKick(s,tau/2) -> fresh stage/k1 -> RK4(tau)`. Query the event just BEFORE
the closing halfkick. Recompute the halfkick, normal geometry, force and
certificate for EVERY candidate tau. Holding the original full-piece halfkick
while searching a shorter fragment gives the wrong path and capacity. A
free-normal predictor may seed a bracket only; it cannot certify the root.
After a located fragment is accepted, apply its closing halfkick, resample,
and rebuild all remaining root candidates from that actual new state.

If the pre-kick itself changes the load branch at fixed position, record the
before/after branch in the numerical receipt and start free-flow evaluation
from the fresh post-kick state. Do not invent a positive-time continuous root
or repeatedly emit zero-duration events for that velocity discontinuity. The
complete-path gate still judges this split response. A gap cannot jump in an
impulse because position is unchanged.

Each root keeps oriented positive/nonpositive bracket endpoints. Use safeguarded
secant proposals and mandatory bisection after retaining over half the interval,
as the existing helper requires. Require both a local-time bracket bound and a
surface residual in its declared physical unit. The latter is root-location
accuracy, never a new force/gap dead zone in the law. Near arithmetic uncertainty,
unrepresentable time progress, unsupported geometry, a nonfinite query, or an
unresolved bracket must refine/refuse. A same-sign endpoint with opposite
intermediate RK samples must refine rather than silently skip a crossing.
Any stronger no-crossing screen needs a supplied whole-interval bound.

Solve all support candidates from the same actual start. Select the earliest
bracket; merge only overlapping time brackets within declared time tolerance,
then sort ties by support ID and surface priority. Re-evaluate every tied surface
at the final actual candidate after recomputing its pre-kick. Coupling can move
or remove another support's root, so stale roots never survive an accepted
fragment. Uncertain ordering/ties refine/refuse. Track each oriented crossing
within the attempt; rearm only after a genuinely new side is established. A
boundary state at time0 is a branch state, not a second event.

The final path has at most16 physical pieces INCLUDING event partitions, not
16 plus arbitrary event pieces. At most15 internal boundaries can therefore
publish; a separate bounded root-query/iteration budget accounts all discarded
trials. If m internal branch times require more than n pieces, that n-path is
inadmissible. Allocate at least one piece to each interval and remaining pieces
by interval length/admission demand; re-run whole-piece certificates after each
pre-kick. The existing n/2n gate compares complete independently revalidated
coarse/fine event-aware paths, accepts only the finer path<=16, and has unchanged
physical tolerances. Neither an event nor a failed root consumes hidden extra
accepted substeps or softens stiffness/friction.

Only the final accepted fragments contribute either halfkick loss, normal RK
power, external work or numerical allowance. Locator trials are detached and
discarded. Numerical branch records belong in `integration_receipt`, with
support ID, kind/sense, time bracket, residual/unit and time-error bound. They
are not aircraft damage/landing events and do not reset modes or state. If an
owner separately publishes a physical kernel event, use existing bounded
`{type,time_s,event_id}` validation/deduplication and accepted transaction only.

Minimum tests: both retained failing tapes with unchanged raw gates; actual
post-prekick root versus free predictor; force-clip/gap ties; two coupled wheel
roots whose ordering changes after first kick; zero-time duplicate/rearm;
interior crossing with same-sign endpoints; uncertain/no-progress brackets;
budget exhaustion; all discarded heat/proof/events absent; exact checkpoint
continuation and refusal rollback. Keep old uniform-grid refusals as evidence.
