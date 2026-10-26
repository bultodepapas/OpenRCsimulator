# GP-14a — survivable accident classification

2026-10-25 · **Status: bounded P0 classifier slice implemented and unit-checked; complete GP-14 remains open.** Owner: ground physics / UI-FS. Scope follows [masterplan §8.5](../../../advanced-ground-flight-physics-masterplan.md#85-shared-accepted-event-model). Software evidence only; no physical landing, damage or pilot-intent validation is claimed.

## Behavior and boundary

The existing pure [statistics detector](../../../../app/statistics/detector.gd) remains the flight and incident classifier. An accepted gear-up contact emits a semantic `accident` with `kind=gear_up_contact` and increments M7 once per activity generation through the existing `crash` event. Its `terminal=false` value leaves the flight active and physics running. It does not call `FlightSession._crash()`, pause the simulation or infer structural failure.

Persistent scrape ticks and short bounce recontacts retain one accident ID. Confirmed airborne rearm permits a distinct later semantic accident, while the generation M7 latch stays set. A terminal escalation updates the same active incident and closes the flight as `crashed` without another M7 increment. A supported quiet hull stop resolves a failed landing and `damaged_stop` without requiring a successful wheel-stop geometry. Resting persistent contact retains its last incident identity until confirmed departure, preventing idle scrape spam; general independent taxi-incident grouping is not qualified here. Previously earned touch-and-go credit is retained.

The rearm regression exposed an ordering defect: unavailable success geometry took precedence over an already accepted incident, producing an unknown departure. The fix gives the incident precedence, matching damaged-stop behavior. A contact with unavailable geometry and no known incident remains unknown. The new regression failed two assertions before the fix; only the final passing receipts are retained below.

## Accepted physical receipt

The public physical observation is the read-only `FlightSession.accident_observation()` method, with exactly eight keys:

| Key | Contract |
| --- | --- |
| `schema` | `openrc-aircraft-accident-observation` |
| `version` | Integer `1` |
| `tick` | Nonnegative integer accepted contact tick, matching the current simulation tick |
| `generation` | Nonnegative integer `statistics_generation`, matching the current session |
| `gear_up_contact` | Boolean accepted hull contact with installed retractable gear outside its fully-down endpoint |
| `ground_contact` | Boolean current accepted hull support/contact |
| `intended_support` | Boolean authored normal support fact; current legacy hull probes expose `false` |
| `terminal` | Boolean terminal physical-session outcome |

Current gear-up production requires a positive accepted tick, active hull contact IDs, valid retractable-gear auxiliary state, nonempty installed support bindings and actual extension below `1.0`. A command alone does not establish contact. Wheel-less aircraft cannot satisfy that installed-retractable-gear condition. No intended skid/belly role is inferred from missing gear; the optional authored support contract below supplies that separate evidence.

The [adapter](../../../../app/statistics/fixed_wing_adapter.gd) rejects stale tick/generation, negative identities, wrong schema/version, extra keys, nonboolean flags and inconsistent gear-up facts. The detector consumes accepted facts and owns accident grouping and timers. The historical five-field `openrc-aircraft-contact-state v1` returned by `contact_events()` and stored in checkpoints is unchanged; the new receipt is not appended to that strict envelope.

`gear_up_contact` describes the observed contact configuration. Whether the gear was deliberately commanded up, failed mechanically or remained in transit is unavailable in this receipt. Damage severity, component breakage and repair need are also unavailable; classification alone does not establish them.

## Versions and historical coverage

`flight-statistics-rules-v2` widens M7 from terminal crashes to the first accepted accident per activity generation. Detector snapshot v2 carries the accident serial, active ID and escalation state separately from the M7 latch. JSON-round-tripped snapshots reproduce the same semantic continuation, and snapshot rollback/retry preserves deterministic IDs.

V1 detector snapshots remain readable without inventing accident state. Existing v1 ledger records keep their terminal-only observation coverage; they are not retallied as if survivable accidents had been observed. The statistics store schema remains v1 because its existing versioned metric fields and bounded metadata hold this slice; a rules version is not a claim of additional historical observations.

## Retained checks

These checked-runner receipts executed the isolated candidate based on `cb2924b3676b72ee49497c92fe742b0b1dcd2d9c` at `tmp/gp-implementation-20261025`, with candidate changes. Exact commands, timestamps, engine output and log SHA-256 values are preserved in the reports. Engine: official Windows Godot `4.8.beta1.official.4d10419ca`, headless. The runner reported complete execution, zero engine diagnostics and success for both checks.

| Check | Result | Evidence |
| --- | --- | --- |
| [test_ground_accidents.gd](../../../../app/tests/test_ground_accidents.gd) | 47 checks, 0 failed | [report](checks/pure-accidents-47/report.json), [engine log](checks/pure-accidents-47/engine.log) |
| [test_flight_statistics_detector.gd](../../../../app/tests/test_flight_statistics_detector.gd) | 67 checks, 0 failed | [report](checks/existing-detector-67/report.json), [engine log](checks/existing-detector-67/engine.log) |

Focused cases cover 100 sliding scrape ticks, 100 persistent rested-contact ticks, continuing unsupported airborne time, same-tick terminal escalation, terminal-first contact, pre-flight ground accident cause, hull rest without landing geometry, failed rearm with unavailable geometry, short-bounce deduplication, new incidents after rearm, prior touch-and-go preservation, v2 JSON restoration, v1 coverage, rollback/retry IDs, duplicate/invalid/gapped ticks and strict packet identity/no-gear exemption. The existing detector suite covers prior takeoff, landing, timing, speed-filter and profile behavior.

These receipts are unit evidence for that candidate run, not complete application integration or latest-source identity receipts. Subsequent combined session/service changes require the integrated checks below. Reproduction uses the canonical [checked script runner](../../../tools/shared.md#one-godot-script); the reports retain the original absolute paths intentionally as historical run identity.

## Remaining scope

The original GP-14a slice did not include the shared subscriber bus; GP-14b below adds its endpoint-observation contract and eight producers. Physical component-damage/gear-failure producers, nonpersistent semantic observers for technical routes, comprehensive per-accident archive, full physical observation identity/evidence envelope, mechanical/damage causality, general taxi-incident grouping and physically calibrated damage remain open. Neither slice qualifies physical realism, audibility, hardware performance or rendered presentation.

## Integrated receipts

The final main-tree [integrated collection](../GP-08/evidence/integration/README.md) retained the latest successful receipt for each of **15 scripts: 841 checks, zero failures** on 2026-10-25. GP-14 pure classification has 55 checks and the live session/service suite has 29, including fixed-gear exemption after an accepted contact tick. The collection also covers the existing detector, lifecycle, reset, store, writer, contact, checkpoint and wheel regressions. [Raw source identities and receipt selection](../GP-08/evidence/integration/report.json) pin base commit `9f12c79e1490c4c72895d450910d9c916743d7b9`, final runtime/test hashes and concurrent unrelated aero/audio/wind changes; [JUnit](../GP-08/evidence/integration/results.xml) verifies 15 passed invocations.

The service now updates terminal escalation by deep-copying and replacing the crash record, preserving the immutable snapshot already handed to the background writer. The [live persistence fixture](../../../../app/tests/test_ground_accident_session.gd) checks that a pre-escalation writer snapshot remains unchanged and that the saved record retains one M7, its original cause, the terminal update and rules version. Persisted accident IDs use the service's activity UUID namespace rather than session-local generation counters; accepted physical receipts continue to use their session tick/generation identity. The final lifecycle checks also preserve the accepted aircraft configuration hash after reload.

The [55-check pure suite](../GP-08/evidence/integration/test_ground_accidents/engine.log) adds atomic rejection of fractional/string snapshot versions and inconsistent v2 serial, M7/incident-latch and terminal-group state. Valid JSON snapshots and historical v1 coverage remain supported. The earlier [candidate numerical replays](../GP-08/evidence/candidate/README.md) have a separate captured source identity: final main detector/service changes are covered by these integrated checks, not by attributing the earlier replay proof to later source. This selected headless collection is not a full suite, physical validation, performance measurement or rendered acceptance.

## Shared semantic events (GP-14b)

2026-10-26. [flight_event.gd](../../../../app/statistics/flight_event.gd) defines `openrc-ground-flight-event` v1 with a closed vocabulary, generation/tick/sequence identity, flight/contact-episode/accident IDs, explicit coverage, unknown severity/cause and continuation independent of crash classification. The **existing** detector supplies eight event types; there is no second takeoff/landing state machine. `COMPONENT_DAMAGE` and `GEAR_FAILURE` are reserved names, not implemented physical emitters.

| Producer | Behavior |
| --- | --- |
| `TAKEOFF` | Existing confirmation rule, requiring actually observed prior support. Retains first unsupported tick and confirmation tick. Air starts and missing prior support earn no semantic takeoff. Existing statistical rules/counters are unchanged. |
| `TOUCHDOWN` | First actual supported endpoint of an active flight's unresolved contact episode. Intended-support flags alone cannot invent contact. Spawn/reset priming emits none. |
| `BOUNCE` | Actual unsupported samples followed by recontact before episode rearm. One event per completed hop, sharing the episode ID; records the sum of observed unsupported sample durations. This is endpoint evidence, not a located crossing or continuous hop-height measurement. |
| `LANDING_SUCCESS`, `TOUCH_AND_GO` | Existing clean support/stop/rearm decisions produce one success and, when applicable, its touch-and-go subtype. No new success threshold or force toggle. |
| `GEAR_UP_CONTACT`, `CRASH` | First accepted accident group. Persistent scraping/recontacts do not duplicate it. Terminal escalation is `CRASH` revision 1 for the same accident; M7 still increments only once per generation. |
| `GROUND_STOP` | Existing supported-rest decision, including damaged hull rest. It does not imply landing success or termination. General independent taxi-stop classification remains open. |

The service exposes `flight_events_accepted(events)` after ingesting the whole detector batch. The signal's nested arrays/dictionaries are frozen so one listener cannot corrupt another's evidence. Mutable consumer copies and compact persisted detail are detached. Flight detail retains the existing 128-event bound and now checks the store's 64 KiB metadata limit before adding longer semantic entries; overflow increments the omitted-detail count while the complete accepted subscriber batch still emits. This bounded detail is **not** a comprehensive per-accident archive, especially for pre-flight ground accidents.

Snapshot v3 records event sequence, observed support, active hop timing and flight identity. V1/v2 snapshots preserve their accident coverage while seeding unknown support-edge history without fabricated bounces. Invalid durations, tick ordering and inconsistent support flags reject atomically. A valid terminal recontact preserves its factual bounce before closure; duplicate, invalid or discontinuous terminal guards can retain the outcome but cannot manufacture a newly accepted support edge. Coverage distinguishes these cases.

The current packet is deliberately limited to the accepted endpoint support law. It contains no fabricated contact/component/material IDs, pre-impact speed, substep time, structural severity or pilot-intent cause. Missing aircraft/configuration/field identity remains empty until supplied by the owner. The service supplies aircraft and accepted activity/configuration identity where available. A richer physical observation producer must extend/version this contract before claiming the full masterplan envelope.

The [retained GP-14b evidence](evidence/shared-events/README.md) includes the new 88-check event suite and real-session checks. The actual 900-tick Avanti belly slide emits one gear-up event and one nonterminal semantic crash, continues moving, and stays byte-exact against the unobserved reference body and complete kernel checkpoint. Rejected physical intervals publish no shared event. These checks establish observer behavior and noninterference, not new advanced contact, structural damage or calibrated bounce physics.

The later [primitive-validation correction](evidence/event-validation/README.md) adds 47 malformed-selector checks. Type checks now precede equality comparisons, preventing engine errors from invalid event fields. The current event suite passes 135 checks and the real-session suite still passes 33. The earlier cohort remains immutable; no valid event or physics behavior changed in this correction.

The [accident observation correction](evidence/observation-validation/README.md) applies the same type-before-comparison rule at the statistics adapter boundary. Thirteen added checks cover malformed schema types and detached valid receipts; 236 focused accident/event/session checks pass without engine diagnostics. Packet versions and physical behavior are unchanged.

## Optional authored hull support (GP-14c)

2026-10-26. The optional v2 `intended_hull_support` module requires
`capabilities.landing_support: authored_hull_v1`, existing stable hull IDs,
provenance, allowed contact IDs, stop groups and explicit rest/control envelopes.
The [pure resource](../../../../app/physics/intended_hull_support.gd) pins existing
geometry and the selected soft-hull law; no geometry or force parameters are
duplicated. Invalid present authoring fails load. Absent authoring keeps existing
behavior. The v1 numerical adapter strips the module/capability, and historical v1
metadata cannot acquire inferred intent. Registry identities are
`aircraft.ground.intended_hull.v1` and the `.belly.v1` or `.skid.v1` subtype.

`FlightSession.hull_support_observation()` exposes a detached, accepted-tick
`openrc-aircraft-hull-support-observation` v1 packet. Physical role coverage is
separate from pose qualification: mixed or wrong-pose contact cannot be intended
support and latches the existing incident rule even without compact event detail.
Stop requires an authored group; empty wheel maps cannot satisfy it. The initial
scope is the actual flat solid hull plane, with explicit unavailability for
lake-enabled sessions. Existing contact/accident envelopes, one classifier/timer
owner and physical state remain unchanged. Configuration hashes already include
the prepared policy through the normalized model; traces declare its identity.

The [retained cohort](evidence/intended-hull-support/README.md) has 2037 passing
observer/contact/statistics/checkpoint checks plus dated pipeline evidence and
exact loaded sources. Its original baseline remains unchanged: all 32 unopted
description byte comparisons pass, while 11 external input-identity changes are
retained as failures rather than claimed as same-input equivalence. Stock X8 has
no authored role or calibrated envelope and gains no landing credit. Lake support,
stock authoring/qualification, richer physical event evidence and performance
qualification remain open.


## Accepted runway reset publication (GP-14d)

2026-10-26. The prepared runway route validates and commits physical state before
its synchronous reset notification, then publishes tick0. A detached closing
checkpoint/tick is captured before staging the new commands, aux or continuous
state and exists only during that notification. FlightLog footer/pause events and
fleet alignment retain the old flight's boundary; the existing accident ledger
archives its stored assessment before the new ledger starts. Empty kernel hooks
retain the frozen legacy checkpoint bytes.

Rejected candidates and preparation/final-validation reentry emit no reset/sample,
close no recorder and advance no generation. Post-commit holds may pause the new
flight. Forbidden protected kernel/model edits or transition reentry restore the
committed protected frame and fault/pause; physical acceptance remains `ok=true`
with explicit `status=observer_fault`, `committed=true`, `ready=false`. One existing
lifecycle receipt advances statistics without phantom takeoff/M7. Ordinary success
keeps its prior result keys. The guard covers listed kernel/model fields and normal
Session entry points, not arbitrary listener globals or captured external data.

The [immutable evidence cohort](evidence/reset-publication/README.md) retains the
original real-session defect reproduction, source hashes, actual recordings,
discarded harness parse failure and seven current production checks: **3882 passed,
zero engine diagnostics**. The focused suite has 180 checks, including the actual
writer/footer replay and bounded fleet consumer. No force law or checkpoint schema
changed. GP-14d covered the **prepared runway route only**. GP-14e below extends
the same owner to other start/reload routes; restore/configuration publication
remains open.
It does not activate advanced aircraft ground physics or qualify physical behavior,
native audio, whole-suite coverage or target-host performance.


## Common start and reload transactions (GP-14e)

2026-10-26. The same Session owner now starts before trim selection and model
staging for runway, airborne/half-power, hand launch, explicit fallback and reload.
A precommit refusal restores the original protected kernel/model reference,
declared owner context, commands, failure resource/RNG and old recording without
notifications or generation changes. Rollback performs no old-model reset or
force evaluation. The existing generic kernel hook still owns physical commit,
old closing-context notification and tick0 publication.

Reload consumes an explicit commit receipt: quiet refusal cannot be reported as
reloaded, and accepted observer fault cannot restore the old flight or claim it
was retained. Accepted faults remain paused/nonready with one generation. Ordinary
public result keys and successful reload strings stay compatible. The explicit
airborne fallback remains distinct from refusal of the requested runway; failed
fallback preserves the old flight, while committed fallback faults expose
nonreadiness. The existing technical airborne helper retains a Boolean wrapper
over the shared receipt helper. Only initial invalid initialization may park an
inert failed start.

The [new immutable cohort](evidence/start-transactions/README.md) retains the
original 48-case defect/control audit and original 51-check/four-failure fixture mismatch, followed by
**4066 passing production checks** across nine scripts with completion markers,
warnings-as-errors and zero engine diagnostics. The new 148-check suite covers refusal,
reentry, failure/RNG preservation, actual recorder footers, accepted observer faults,
X8 hand launch and exact continuation. Two old failed-reload fixtures now inject a
precommit candidate refusal; their original invariants remain unchanged. Prior
cohorts remain historical. Restore/weather/shaft publication migration, full-suite,
physical and performance qualification remain open; no force law, checkpoint schema,
stock hull role or advanced ground activation changed.
