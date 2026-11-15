# Glider implementation handoff — start here

**Outcome:** build an unpowered RC soaring activity covering air start, hand release, AI aerotow, and a human-flown tug followed by glider takeover. The [master plan](../glider-soaring.md) is the sole authority for SG-00…17 scope, dependencies and implementation status. All implementation and qualification remain pending; the reviewed planning and research are ready to use.

**Source identity:** runtime main [`ad21070798bfb9658785576a9c0b8bfc9a71fc7f`](https://github.com/bultodepapas/OpenRCsimulator/commit/ad21070798bfb9658785576a9c0b8bfc9a71fc7f). This senior pass extends planning baseline [`f10619263cb74596d001064b9bc4cc5c3d55396c`](https://github.com/bultodepapas/OpenRCsimulator/commit/f10619263cb74596d001064b9bc4cc5c3d55396c), reviewed 15 November 2026. Reconcile changed source interfaces before implementation. Proposed semantic fields, file homes and test cards are not current APIs or executed tests.

## First work to assign

Start **WP-01 → WP-02 → WP-03** for explicit absent propulsion, a generated trainer with intended landing support, and a complete calm solo loop. That loop includes descending trim, real controls, landing/stop/incident observations, basic recording, restart and replay. Preserve existing powered aircraft and source pipelines.

In parallel, assign **WP-04/05** to SF/physics for the bounded synthetic coupled-model and line experiment. Use its evidence to choose the production representation and event policy. Draft **WP-06** with FL alongside that experiment; adopt its record/timing contract after the physical transaction is defined. Begin **WP-14** build, asset and measurement preparation immediately. Missing measured aircraft/rope data does not block the clearly synthetic experiment; it keeps the corresponding physical-fidelity claim open.

After the solo loop, hand release and a finite thermal exercise can proceed separately. Airborne towing follows pair mechanics, complete recording, joint envelope and swept exclusion; manual tug and takeover follow the AI tug slice. Ground towing adds dual contact and event composition. Apply **WP-15** to each distributed candidate and its advertised devices/platforms, not only to the last milestone.

The [packet dependency table](05-implementation-packets.md#dependency-map) names prerequisites and accountable leads. Its WP IDs subdivide the master SG work; they are not a second status system or fixed delivery estimates.

## Read by responsibility

| Role / decision | Start with | Work and evidence |
| --- | --- | --- |
| Technical lead / scope | [Master plan](../glider-soaring.md), [audit](../../research/glider-soaring/2026-11-15-plan-audit.md) | Assign packets; keep implementation, physical claims and release scope distinct |
| AS / aircraft / assets | [Aircraft and weather](03-aircraft-and-weather.md), [absence contract](06-interface-contracts.md#2-proposed-admission-and-absent-propulsion-semantics) | WP-01/02/14; SC-01/03; build, parameter and per-file provenance cards |
| SF / physics / GP/CR | [Physics and tow](02-physics-and-tow.md), [interface contracts](06-interface-contracts.md) | WP-04/05/09/12; SC-05…10/14/17/18; solver, state, event and clearance receipts |
| AFC / session / input | [Launch and control](01-launch-and-control.md), [action contract](06-interface-contracts.md#5-arbitration-and-action-results) | WP-03/07/10/11; SC-02/04/10…12/17/19; role, timing, fallback and device proof |
| M5 / scenarios / HUD | [Weather recipes](03-aircraft-and-weather.md), [acceptance gates](04-acceptance-and-delivery.md) | WP-08; SC-15/16; complete field/epoch, instrument and task-feasibility evidence |
| FL / UI-FS | [Record/replay contract](06-interface-contracts.md#7-checkpoint-tapes-and-replay), [acceptance](04-acceptance-and-delivery.md#7-recording-telemetry-and-debrief-schema) | WP-03/06/13; SC-03/08…13/17/20; complete accepted outcomes and honest replay domains |
| QA / flight test / release | [Scenario cards](07-acceptance-scenarios.md), [evidence kit](08-data-and-evidence-kit.md) | Applicable positive/negative cases and claim receipts; WP-14/15 with actual owners |

## Document map

The four core guides own player behavior, physical assumptions, aircraft/weather choices and acceptance gates. The four implementation appendices make those requirements actionable:

- [05 — Implementation packets](05-implementation-packets.md): 15 bounded work descriptions, dependencies, source seams, deliverables, stop/admit rules and a PR handoff template.
- [06 — Proposed interface contracts](06-interface-contracts.md): source facts versus design decisions for absence, scenario identity, composite state, control arbitration, action identity, timing, publication faults, checkpoints and replay.
- [07 — Acceptance scenarios](07-acceptance-scenarios.md): 20 setup/stimulus/oracle/evidence cards, including an independent analytic tow fixture and a rejection/publication ledger. They refine the acceptance matrices; none is a passed runtime test.
- [08 — Data and evidence kit](08-data-and-evidence-kit.md): copyable build, parameter, holdout/exclusion, hand-release, installed-line, weather/instrument and claim receipts. Unknown measurements stay unknown.

The [24-investigation index](../../research/glider-soaring/2026-11-15-investigations.md) links primary evidence and proposed discriminating experiments across aerodynamics, towing, weather and delivery. The [source review](../../research/glider-soaring/2026-11-15-source-review.md) records the earlier repository inspection; the [audit](../../research/glider-soaring/2026-11-15-plan-audit.md) records corrected planning gaps and the senior integration pass. Keep new implementation decisions in the existing project decision process and SG evidence in its owning paths.

## Contract boundaries to settle first

AS must admit absence through identity, generated data, runtime observations and consumers; an empty propulsion object is insufficient. SF/session must demonstrate one same-stage pair transaction, both-body validation/projection and complete rejection/restore. External checkpoint serialization alone does not make controllers, intent queues or RNG transactional.

SF/AFC/input/FL must choose one effective-time convention and guidance phase, including release actions between guidance updates. Define request/result identity and mechanical opening independently of ownership. The ordinary pair publication fault path needs its own proof; the existing guarded reset/restore path is only a precedent. Final-command physics replay requires timed external interventions and a declared comparison projection; full decision replay also regenerates controller and arbiter state.

Every packet needs a successful supported case and its discriminating refusal/fault cases. Select numerical tolerances before judging results. Use the [existing tool index](../../tools/README.md) and repository queue/owner rules for execution; this handoff introduces no glider-specific CLI or mandatory third-party solver.

Accept narrower, explicitly described experimental results when their applicable gates pass. Physical fidelity, device support, usable exercises and learning-effect claims each need their own evidence. Preserve failures and omissions in the release receipt; do not promote a synthetic oracle, exact replay, mocked radio or plausible rendered scene into a different kind of proof.
