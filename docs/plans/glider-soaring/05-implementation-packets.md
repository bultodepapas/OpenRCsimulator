# Implementation packets for the glider handoff

**Status:** proposed, issue-ready work descriptions; no packet is implemented by this document.  
**Source:** main `ad21070798bfb9658785576a9c0b8bfc9a71fc7f`; planning baseline `f10619263cb74596d001064b9bc4cc5c3d55396c`; reviewed 15 November 2026.  
**Authority:** the [master](../glider-soaring.md#7-delivery-sequence-and-canonical-step-status) owns SG status and milestone order. WP IDs below subdivide work; they do not replace SG IDs, create completed steps or set dates.

## 1. How to use the packets

Copy a packet into the team's work system, name an accountable implementer and reviewer, and pin the actual code/data revision before starting. A packet may require several small PRs; keep each working and reviewable. Admission stays unavailable until its complete consumer path and required evidence work together. Do not merge a partially supported aircraft and rely on users to avoid the broken path.

Source-path lists are inspection boundaries, not instructions to edit every listed file. Reuse current owners, source generators, test runners and log tooling. A named existing test is a starting regression check, not proof that it covers the new feature or has passed. The [scenario cards](07-acceptance-scenarios.md) specify new discriminating cases; the [contracts](06-interface-contracts.md) distinguish current APIs from proposed semantics; the [evidence kit](08-data-and-evidence-kit.md) supplies fill-in records.

A card can contain fixture, airborne and later ground/role variants. Each packet below names the portion it establishes; record that exact portion in its receipt. A foundational synthetic result does not close the later interactive variant. In particular, WP-04…06 do not depend on finished WP-10/11 controllers, while full manual-tug takeover and real pickup remain WP-11 gates. Every applicable earlier invariant must be demonstrated again at its integrated boundary.

SC-19's actual-device/display qualification and SC-20's package/release portions apply to advertised support and distributed candidates. A nondistributed engineering increment may establish its specified software boundary first; it must not claim those unperformed qualifications. WP-15 and existing repository release gates remain required for the declared release.

### Dependency map

Dependencies mean a demonstrated usable boundary, not completion of every physical-evidence obligation in an SG step. Drafting an interface can overlap its producer; production integration waits for its adopted identity.

| Packet | SG / checkpoint | Start after | Accountable lead |
| --- | --- | --- | --- |
| WP-01 Absence contract | SG-00/01; M0 | Current source and consumer inventory | AS + physics |
| WP-02 Generated trainer and support | SG-02; M0 | WP-01 for runtime admission; source intake can start immediately | Aircraft/AS + GP |
| WP-03 Calm solo loop | SG-03/04/13/15; M1a | WP-01/02 | Session/physics + UI-FS/FL |
| WP-04 Pair transaction experiment | SG-07; M2a | Bounded synthetic fixture; independent of real aircraft | SF + physics |
| WP-05 Line and event experiment | SG-08; M2a | A WP-04 candidate; their evidence jointly selects production design | Physics + SF |
| WP-06 Pair recording and replay | SG-07/15; M2a–M2b | Design alongside WP-04/05; freeze/adopt after their contract choice | FL + SF/session |
| WP-07 Hand release | SG-05/13; M1b | WP-03 | Session/input + physics |
| WP-08 Finite thermal exercise | SG-06/13/15; M1c | WP-03 and applicable M5 field evidence | M5/scenarios + HUD |
| WP-09 Pair installation and exclusion | SG-09/07; M2b prerequisite | WP-03/04/05/06 | Aircraft/physics + GP/CR |
| WP-10 AI tug activity | SG-10/13; M2b | WP-09 and minimum complete pair recording | AFC/session |
| WP-11 Manual tug and takeover | SG-11/13; M2c | WP-10; follower/free-glide and input readiness | AFC/input + SF/FL |
| WP-12 Ground tow and bounded faults | SG-12/14; M3 | WP-11 and ground/contact event design | GP/CR + SF/AFC |
| WP-13 Lessons and debrief | SG-15/16; M3 scope | Applicable playable mode and accepted outcomes; basic recording already exists | Product/UI-FS + FL |
| WP-14 Physical data and assets | SG-02/03/09/16 | Start protocols/intake now; measurements need the identified build | Aircraft/FT + AS |
| WP-15 Per-slice release qualification | SG-13/17, applicable SG-16; M4 | Each selected candidate and its advertised scope | Release/platform + owners |

WP-04/05 and WP-14 can proceed beside WP-01…03. Neither a measured rope nor a finished thermal lesson is required for a synthetic pair experiment. Physical claims require the corresponding measurements before promotion. A release candidate cannot bypass existing CI/export/backend policy.

## 2. Contract and first playable slice

### WP-01 — Admit explicit absent propulsion through all consumers

**Result:** one versioned, generated unpowered reference configuration loads and behaves consistently across physics, observations and presentation. The old powered fleet remains compatible.

Inspect `app/physics/aircraft_modules.gd`, `aircraft_data.gd`, `physical_identity.gd`, the schema/compiler, `app/sim/aircraft_propulsion_runtime.gd`, session contact/trace/log metadata, Workshop, audio and catalog consumers. AS owns the representation; do not invent a motor/rotor ID, zero-thrust engine or undocumented schema escape.

Produce the consumer/absence decision, source-owned fixture, contradictory-data fixtures and compatibility receipt. Include receiver/servo/release supply assumptions and installed masses. Existing roots: `test_aircraft_modules.gd` and `test_aircraft_contract.gd`. New proof: SC-01 plus the preflight preservation portion of SC-02.

**Stop/admit:** a loader-only change is insufficient. Keep public capability exposure unavailable until every required consumer either supports absence or gives the declared unsupported result. This packet does not qualify a physical aircraft.

### WP-02 — Generate a trainer and its intended landing support

**Result:** an identified engineering trainer with correct units/axes, inventory, controls, render bindings and authored belly/skid intent. Keep source estimates and asset rights visible.

Reuse an appropriate distributable source or existing generator before creating a substitute. Inspect source inventories and the current hull-support path: `app/physics/intended_hull_support.gd`, normalized aircraft data, session accepted observations and `app/statistics/profiles.gd`. Geometry and physics are regenerated from their owning sources, never hand-edited output.

Produce the build/parameter/asset receipts from 08, a generator/check receipt, and valid versus wrong-pose/identity fixtures. Prove the current flat-solid/no-lake scope; intended-support observation adds no contact force and is not itself a landing classifier.

**Stop/admit:** SC-01/03 and source-pipeline checks. Missing measured EG4 data permits a clearly estimated engineering configuration, not a calibrated named replica.

### WP-03 — Complete the calm solo loop

**Result:** choose a supported unpowered aircraft, resolve calm air start, descend in valid trim, control it, land, inspect an accepted outcome, restart and replay.

Inspect `app/sim/flight_session.gd`, `scenarios.gd`, `app/app_root.gd`, shared prepared-launch/input paths, `app/statistics/fixed_wing_adapter.gd` and `app/sim/flight_log.gd`. Keep Home draft cancellation separate from accepted session replacement; equivalent explicit CLI/Home inputs must resolve the same scenario.

Include minimal actor-neutral outcome/logging and the first SG-13/17 slices now. Existing roots: `test_trim.gd`, `test_flight_session_staged.gd`, `test_home_launch_setup.gd`, `test_checkpoint.gd` and `test_flight_log_inputs.gd`. New proof: SC-02/03 and applicable SC-19/20.

**Stop/admit:** successful positive flow plus invalid-trim, unsupported terrain, cancellation and restore negatives. Refusing every landing is not a passing playable milestone.

## 3. Coupled foundation and recording

### WP-04 — Prove the pair transaction and publication boundary

**Result:** a generic, source-identified synthetic pair candidate, with both bodies validated and restored together. Its experiment informs the production representation.

Inspect `app/sim/vehicle_model.gd`, `simulation.gd`, `app/physics/integrator.gd`, sampled-frame callbacks and endpoint/event contracts. Keep one model/transaction; use float64. Determine trial rotation/inverse and accepted projection, state ownership, cadence phase, complete previous/current publication and restore generations. An external checkpoint envelope needs an actual staged commit/rollback mechanism; its existence alone is not atomicity.

Produce the decision record, state inventory and failure ledger. Distinguish rejected candidates from committed observer faults. Current guarded reset/restore publication does not supply a generic ordinary-tick guarantee; qualify that pair boundary before interactive admission.

**Proof:** the synthetic frame, projection, rejection/publication and timing portions of SC-07…10, plus SC-13's initial-state/identity/restore checks on this fixture. Start from `test_sf_vehicle_model.gd`, `test_sf_framed_sampled.gd` and checkpoint/staged-session checks. Complete synthetic pair replay belongs to WP-06; live-role replay follows in WP-10/11. A separated fixture may omit collision only under its declared experiment scope.

### WP-05 — Prove the line law, solver and events

**Result:** a bounded tension-only line coupled at the same stage, with correct hook loads, energy and release accounting.

Use the independent SC-05 oracle before aircraft aerodynamics. Add SC-06/07 for slack, clipping, rotating hooks and detached energy. Choose a credible solver candidate from explicit bounded subdivision or a separately justified alternative; implementing every researched method is unnecessary. Do not suppress current step-policy/substep restrictions or weaken stiffness to hide failure.

Produce a parameter-envelope record, predeclared tolerances, refinement/error/cost results and versioned event composition. The installed physical rope remains a separate WP-14 claim. Existing roots: `test_sf_event_protocol.gd`, `test_sf_event_refinement.gd` and `test_sf_contact_substeps.gd`.

**Stop/admit:** SC-05…08/10 in the synthetic line fixture, and SC-17's synthetic event-ordering, within-step detection and unsupported-intersection cases. Full controller recovery and dual-contact combinations are qualified by WP-10/11/12, not prerequisites to this experiment. Unresolved crossings or unsupported event intersections refuse coherently. A synthetic spring value never becomes a measured weak-link rating.

### WP-06 — Record and replay the whole pair before towing

**Result:** a bounded paired envelope with initial complete state, identity, timed external inputs/intents, per-interval commands and accepted physical events.

FL/SF freeze the adopted actor IDs, time/phase convention, layouts, restore identity and event semantics after WP-04/05. Reuse current file integrity, completion and compatibility practices; do not label independent companion logs as an atomic pair record.

Provide two explicit modes: decision replay re-executes controllers from their state and external input/intent tape; solver replay uses the declared command boundary and timed external interventions, recomputes endogenous events, and compares its declared physical projection. Bypassed controller memory is not automatically exact. Keep JSON/CSV diagnostic exports separate from lossless checkpoints.

**Proof:** synthetic record-boundary cases from SC-08…10/13 and SC-17's event-stream ordering/refusal portion, using relevant checkpoint/log/restore tests. Demonstrate both replay modes with a deterministic fixture controller and explicit synthetic ownership/pickup state; preserve the complete initial state, command/intervention tapes and declared comparison domains. Include truncated recording, writer failure after commit, incompatible identity, held-action retry and restored idempotency state. Diagnostics may record a rejected attempt without inventing an accepted step.

This establishes the record foundation before interactive integration. Complete SC-11/12 takeover/pickup workflows require WP-11, and live-role SC-13/17 must pass with WP-10's AI tug and WP-11's manual tug respectively. Their future completion cannot be claimed from fixture serialization, but their unfinished gameplay controllers do not block this foundational packet.

## 4. Solo launch and weather additions

### WP-07 — Implement hand release as one initial state

**Result:** prepared hold, cancellation, one accepted ground-relative release and a controlled short glide/landing.

Use the current launch resolver/session seam and explicit capability; preserve correlated pose, CG velocity, rates and achieved controls. Add no hand force or second impulse after separation. Wind is subtracted to derive air motion from the authored ground-relative release state. DLG is a later aircraft/method.

Produce release-recipe identity, cancellation/held-button behavior, record-start semantics and input readiness. An estimated release is labelled experimental; WP-14 measurements support a realistic release claim. Existing roots: `test_hand_launch.gd` and staged/Home launch checks.

**Proof:** SC-02/04, then the solo landing and replay gate; SC-19 for advertised device/display support or distribution. No assumption that a low throw reaches useful lift.

### WP-08 — Qualify one finite thermal exercise, then additional recipes

**Result:** a complete admitted weather object and usable exercise, starting with one of the five proposed recipes.

Reuse M5's atmosphere/spatial/thermal schemas, preset builder and provider; no second wind engine or hidden lift. Preserve epoch, finite life, world horizon, field translation and all station-domain checks. Use true state, sensor-derived instruments and assisted cues as separate channels.

Produce schema/identity and analytic checks, sensor/filter policy, task-feasibility evidence and saved scenario behavior. Test sampled lift against banked sink and return/expiry requirements. Additional recipes and nonzero-weather towing qualify independently.

**Proof:** SC-15/16/19 plus A11…A15 and relevant current weather tests identified through the tool/source index. A rendered thermal or a configured peak is not a flown or measured task result.

## 5. Interactive airborne pair

### WP-09 — Admit installation, joint envelope and swept exclusion

**Result:** an identified pair and line with feasible starts, controls/power margins and a qualified airborne incident/clearance policy.

Bind both hooks, aircraft configurations, release assumptions and contact proxies through their owners. Use synthetic values only within the declared engineering envelope. Establish joint force/moment trim, reachable transitions and calm shared weather. Source-specific AI/native receipts must be regenerated/qualified through their existing owners when affected.

Qualify swept aircraft encounters and conditional rope bounds with GP/CR. Unknown required slack clearance cannot earn successful-tow credit; a conservative enclosure intersection is not proved impact. Full crash/entanglement physics remains a separate capability.

**Proof:** SC-07, the airborne geometry/rope portions of SC-14, the installation's event-admission/refusal portions of SC-17, and applicable data/trim checks, with the minimum WP-06 record. Actual controller recovery follows in WP-10/11. T13 precedes interactive airborne towing; ground T14 follows later.

### WP-10 — Deliver AI tug with player glider

**Result:** a calm airborne tow with actual actuators, independent release, bounded tug recovery and complete pair logging.

Reuse AFC observation/controller utilities without bypassing their current source/weather admission. A new tow profile needs its own reachable speed/climb/turn envelope, anti-windup, held-sample policy and recovery behavior. Label any simulation-truth sensor as assistance.

Include interruption, free-flight continuation, unsafe encounter and recovery-controller failure. The AI does not set aircraft position or velocity. A successfully released glider does not permit discarding the still-live tug.

**Proof:** C01 and SC-08…10/13/14/17/19 as integrated with the AI-tug/human-glider role, including a positive straight/turning flow, release/recovery, complete replay and deliberate negative cases. This SC-13 variant covers release, interruption, restore and full replay without takeover: the human already owns the glider. SC-13's transfer variant and full SC-11/12 manual-tug takeover/pickup belong to WP-11 and are not dependencies of this packet. Autonomous landing and nonzero-weather towing remain unavailable until separately qualified.

### WP-11 — Deliver manual tug, follower and both takeover paths

**Result:** the player flies the tug while AI flies the glider, then either releases and takes the glider together or releases first and takes it later.

Build the follower's bounded released free-glide state and the tug's admitted recovery before exposing transfer. Freeze intent effective time and cadence with SF/FL. Use one command arbiter, actual applied-command tracking, achieved servo continuity and per-axis/AUX readiness. Hold, reject or pause according to the declared policy without disabling an independently available release.

Record the old/new owner, requested versus effective release, pickup state and accepted result. A repeated action creates no duplicate mechanical event or score. Attached transfer is separately gated.

**Proof:** SC-10…13/17/19, C02/C04/C05/C11/C13/C14. Restore in every pickup/hold phase and retain clear current-owner feedback.

## 6. Ground, lessons, physical evidence and delivery

### WP-12 — Extend to ground take-up, release and bounded faults

**Result:** valid dual-contact starts, slack take-up, the allowed takeoff order, release in either ground phase and an explicit abort outcome.

GP/CR/SF qualify both contacts, line/propulsion/source-loss events and the selected substep policy together. Reuse the actual field and support geometry. No wheel-only substitution for a glider belly, frozen attached endpoint, unmodeled entanglement rescue or universal break force.

Physical break remains unavailable unless its installation, threshold/time/rate law and event evidence support it. Scripted release practice is identified separately. Preserve ownership/contact semantics after a ground release and refuse airborne-only takeover when inappropriate.

**Proof:** SC-14/17/18, T08/T10/T14/T15 and complete pair replay. Do not expose ground towing merely because airborne towing passes.

### WP-13 — Build useful lessons, scoring and comparative debrief

**Result:** objectives, prerequisites, clear assistance, accepted outcomes and debrief for admitted modes.

Basic recording/outcomes already exist from WP-03/06. Extend them with comparisons, thermal/return decisions and failure practice. Scores consume accepted events and distinguish completion, assistance, deliberate abort, technical refusal and unknown clearance; restore or retry cannot mint credit.

Keep controls/camera assistance separate from physical coefficients. An exercise can ship without a causal effectiveness claim; any such claim needs the WP-14 evidence design and appropriate learner study.

**Proof:** select SC-03/11/13/14/16/20 portions for the lesson's admitted modes and claims, plus GI-24's applicable methodology. Tow-transfer cases belong to tow lessons, SC-16 to thermal lessons and SC-20's package portion to a distributed candidate; a ground-tow lesson does not require an unrelated thermal feature. Include failures and incomplete records in debrief rather than selecting only successful flights.

### WP-14 — Collect physical and asset evidence for the claimed configuration

**Result:** traceable build/asset/parameter records and independent validation data sufficient for the next physical claim.

Use 08's templates. Identify the exact aircraft, instrumentation, installed components, source dimensionality/Re domain, measurement uncertainty and immutable raw data. Prepare calibration/selection/final-validation splits before fitting. A final set used for reselection becomes development data.

Scope measurements to the claimed mode: solo air start need not wait for towline or hand-release data. Installed-line histories, actual tug performance and any break evidence precede their physical claims. Asset availability never supplies aerodynamic calibration.

**Proof:** reviewers can reproduce the reduction and trace each claim to an independent artifact and exact configuration, with exclusions and failures retained. Missing data stays missing; estimated parameters do not become measured after a software test.

### WP-15 — Qualify each advertised release slice

**Result:** a candidate whose package, performance, device support and advertised claims match its evidence.

Measure the complete activity at actual 1920×1080 on the declared host/renderer, including pair physics, input, AI, weather, logging, presentation and audio. Retain the current budget and required CI/export/backend policies. Native optimization is optional and must cover the entire claimed law/layout; reference fallback follows the owning policy.

Test actual supported devices and OS paths, focus/reconnect, log compatibility and resource packaging. Retain unsupported capabilities as unavailable. A narrower experimental release still needs the appropriate software/user-flow/package evidence.

**Proof:** SC-19/20 and the applicable 04 milestone slice, exact source/package identities and unperformed checks explicitly recorded. Publication to an end-user release is a separate delivery action from this planning branch.

## 7. PR and handoff record

Use this structure for each implementation PR; retain the exact commands and artifacts in their owning evidence location:

```markdown
## Problem and user-visible result
<one bounded behavior; WP / SG / milestone and claim>

## Boundary and source identity
<base commit, affected owners, authored/generated sources, selected contracts>

## Changes and compatibility
<implemented paths, schema/layout/receipt impact, old behavior preserved>

## Evidence
<existing checks + new SC/A/T/C cases; exact inputs and artifacts; failures;
 numerical/physical/device/visual/platform claims distinguished>

## Admission and remaining work
<supported configuration, explicit refusals, provisional values, rollback;
 no whole SG completion from a partial slice>
```

Before integration, review the actual combined diff, source identity and affected consumers. Inspect checked verdicts/logs, not only process exit codes. Re-run only what changed inputs or required gates justify. Source/hash changes may invalidate AI/native receipts even when visible behavior appears unchanged; the owner must qualify or refuse the changed combination.
