# Acceptance scenarios and independent oracles

**Status:** executable-test specifications for future implementation, not runnable test files or passed tests.  
**Source:** main `ad21070798bfb9658785576a9c0b8bfc9a71fc7f`; planning baseline `f10619263cb74596d001064b9bc4cc5c3d55396c`; reviewed 15 November 2026.  
**Read with:** [acceptance matrices](04-acceptance-and-delivery.md), [interface contracts](06-interface-contracts.md), [work packets](05-implementation-packets.md) and [evidence kit](08-data-and-evidence-kit.md).

SC IDs below identify concrete cases beneath A/T/C and SG gates. They do not create another implementation-status register. Every case requires a positive supported case and the stated negative control where applicable: an implementation that refuses everything cannot pass the requested usable flow.

The [packet proof scopes](05-implementation-packets.md) distinguish foundational fixture variants from complete interactive workflows. Name the variant and declared mode in each result. A synthetic controller/state record can prove a serialization or transaction boundary before a playable controller exists; it cannot close the later AI-tug or manual-tug takeover case. Ground variants wait for ground admission. This avoids making the foundation depend on the later feature while retaining every applicable integrated gate.

## 1. Common case record

Before running a case, pin source/build/backend/law/layout, aircraft or synthetic fixture, weather/datum/epoch, solver/step policy, controller/input cadence and phase, start state, stimulus timing, expected outcome, comparison domain, tolerance and evidence path. State the tested branch of each piecewise law. Preserve raw outputs, failed attempts and incomplete records.

Use exact equality only where the same-identity contract promises it; use predeclared absolute/relative errors and refinement for numerical oracles, and independently justified uncertainty for physical measurements. A finite output, successful process exit or same-input replay is not physical validation. One advanced state is not a complete user-flow result.

### Rejection and publication ledger

The new pair boundary must distinguish the following, including a session sidecar if one is selected:

| Boundary outcome | Accepted physical/controller/ownership state | Recording and diagnostics |
| --- | --- | --- |
| Prepared start/restore refused | Preserve the previous accepted session, inputs and identity | Report refusal; do not publish a successful new-flight sample |
| Candidate tick rejected before commit | No accepted pair advance, located transition, intent consumption or score from that candidate | A fault/pause diagnostic and incomplete footer may be written at the unchanged accepted boundary |
| Pair committed, observer/writer then fails | Preserve the newly accepted pair; follow qualified hold/fault handling | Identify missing/failed observation or recording; never claim rollback or a complete sample that was not written |
| Normal accepted tick | Advance both actors and all authoritative transactional state once | Publish one declared accepted boundary and its ordered outcomes |

At the inspected source, guarded publication exists for prepared reset/restore; ordinary tick publication does not automatically inherit it. SC-09 qualifies the proposed pair mechanism. A checkpointed external object is transactional only when its staging, commit/refusal recovery and restore are demonstrated. Diagnostic `last_events` is not a persisted intent-consumption ledger.

## 2. Data, preflight and solo cases

### SC-01: Absent propulsion through every consumer

**Maps:** WP-01/02; SG-01/02; A01/A02.  
**Setup/stimulus:** one source-generated unpowered fixture, a powered baseline and variants with contradictory/missing absence, identity, module or observation data. Exercise load, prepared launch, telemetry, log/trace, Workshop, contact identity and audio consumers.

**Oracle:** the admitted absence produces no fabricated motor/rotor identity, thrust, shaft/fuel/RPM or engine sound. Receiver/servo/release masses and the declared supply remain. Contradictory or unsupported versions refuse before replacing the old session; powered identities and expected behavior remain compatible.

**Evidence:** normalized data/identity comparison, consumer results and compatibility receipt. Do not declare a real glider calibrated.

### SC-02: Prepared launch, cancellation and source equivalence

**Maps:** WP-03/07; SG-04/05/13; C07/C10.  
**Setup/stimulus:** an accepted flight plus edited Home draft; exercise Cancel, invalid trim, missing controller capability, unsupported weather, failed prepared load and equivalent explicit CLI/Home inputs.

**Oracle:** draft failure preserves the accepted flight, clock, record and configuration; a successful start commit has one accepted activity/transition generation and complete start state. Reusing the same resolved recipe preserves its scenario identity; an explicit new challenge changes the appropriate resolved content/identity. Explicit equivalent inputs resolve equally without CLI borrowing unrelated Home preferences. A postcommit observer failure is classified under SC-09 rather than pretending the start never committed.

**Evidence:** before/candidate/accepted identities and ordered lifecycle notifications; inspect actual navigation for UI claims.

### SC-03: Belly landing, intended support and outcome

**Maps:** WP-02/03/13; SG-02/04/15; A16.  
**Setup/stimulus:** the admitted authored hull/support/soft-contact identity on current flat solid ground, plus wrong pose, incidental hull contact, changed identity, lake and unsupported terrain variants.

**Oracle:** physical contacts, accepted support facts and landing/stop/incident classification agree through their separate owners. Unsupported observation cannot become a successful landing. Include a genuine supported landing/stop and an incident. Restart, restore and repeated observation do not duplicate touchdown or credit.

**Evidence:** accepted contact/support/accident facts, statistics profile identity, outcome timeline and replay; a rendered belly touch alone is insufficient.

### SC-04: One correlated ground-relative hand release

**Maps:** WP-07; SG-05; A10/GI-05.  
**Setup/stimulus:** a complete synthetic or measured release state with position, attitude, CG ground velocity, angular rate and achieved controls; calm/head/tail/crosswind variants; cancel and held-button input.

**Oracle:** air motion follows ground motion minus local wind. The specified initial state commits once; wind is not added again and no post-separation hand force/impulse adds energy. Correlated state remains one observation/recipe, not independent marginal maxima. Cancellation creates no accepted launch; a held edge creates no repeated release or score.

**Evidence:** release receipt, early trajectory/rates, event count, initial energy accounting and replay. Measured realism requires the appropriate independent release data.

## 3. Pair mechanics, timing and atomicity

### SC-05: Independent stretched-line oscillator

**Maps:** WP-04/05; SG-07/08; T01/T04/GI-09/10.  
**Fixture only:** two equal `1 kg` point bodies, centered hooks, no net external acceleration, no rotation, `L0=10 m`, `k=100 N/m`, `c=0`, initial separation `10.01 m` and both velocities zero. These are analytic test constants, not aircraft, rope or launch recommendations.

Use a generic reference fixture, explicitly configuring zero gravity before the run as existing kernel tests do, and ensure the secondary derivative uses the same configuration. Disable all other external loads for this fixture and retain its identity. Do not add a production flight option or assume setting the primary field changes a separately implemented secondary derivative.

If represented through the rigid-body kernel, supply valid positive-definite synthetic inertia tensors; zero-inertia bodies are invalid. Centered hooks, zero initial spin and no applied moments make these placeholder inertias irrelevant to this translational oracle. Retain identity orientations and the secondary-body validity contract.

While extension remains positive:

```text
mu = (1/m_g + 1/m_t)^(-1) = 0.5 kg
omega = sqrt(k/mu) = sqrt(200) rad/s
e(t) = 0.01 cos(omega t)
e_dot(t) = -0.01 omega sin(omega t)
T(t) = k e(t)
x_com = 5.005 m                         for x_g(0)=0, x_t(0)=10.01
x_g = x_com - (L0 + e)/2
x_t = x_com + (L0 + e)/2
v_g = -e_dot/2; v_t = e_dot/2
E = 0.5*m_g*v_g² + 0.5*m_t*v_t² + 0.5*k*e² = 0.005 J
```

The first slack boundary is `pi/(2*sqrt(200)) ≈ 0.111072073454 s`. Compare at `t=0.1 s`, which is 24 ticks at the application's configured 240 Hz, and remains before that boundary:

| Observable | Analytic value |
| --- | ---: |
| Extension | 0.00155943694765 m |
| Extension rate | −0.139691199727 m/s |
| Tension | 0.155943694765 N |
| Speed magnitude of each body | 0.0698455998637 m/s |
| Total momentum | 0 kg m/s |
| Kinetic plus spring energy | 0.005 J |

These arithmetic values were independently calculated while authoring the document; no simulator comparison was run. Predeclare combined absolute/relative tolerances. Compare common sample times under `h, h/2, h/4, h/8` using separate reset fixtures or a qualified internal-subdivision policy; do not change the live kernel's fixed rate mid-run. Record error and cost; do not extrapolate this smooth pre-slack result to event or aircraft accuracy.

### SC-06: Slack, clipped damping and detached energy

**Maps:** WP-05; SG-08; T03/T04/T08.  
**Setup/stimulus:** separate cases for slack, coincident hooks, positive extension/positive tension, rapid shortening that clips tension to zero, engagement and commanded release while stretched.

**Oracle:** no compression or zero-length normalization. Let `K` include both bodies' translational/rotational kinetic energy and `P_external` be the power of all non-line forces and moments, including gravity when enabled. For positive extension and unclipped tension, `d(K+U)/dt - P_external = -c*e_dot²`. For a clipped shortening branch with `e>0` and `T=0`, `d(K+U)/dt - P_external = k*e*e_dot<=0`. A zero-external-work fixture sets `P_external=0`. Use an independent work ledger; these identities assume the stated fixed-mass, fixed-length line law and apply away from its switching boundary.

At release, no unexplained velocity impulse appears and stored line energy is accounted for as leaving this two-body model. No later reattachment occurs without the admitted reset. Check discrete residual/refinement and event time separately; no physical line hysteresis claim follows.

### SC-07: Rotating hooks and secondary attitude

**Maps:** WP-04/05/09; SG-07/08; T02/T06.  
**Setup/stimulus:** offset hooks, both rotating bodies, changing orientation, valid non-unit trial quaternions under the selected extension, and invalid/degenerate trial or restored states.

**Oracle:** independent geometric checks for hook position/velocity, `r × F`, force action/reaction, total angular momentum about one world origin, and per-hook power. Rotation and inverse are consistent under the declared trial convention. Accepted/substep/event/reset/restore projections preserve the intended method; do not silently normalize stored RK trials. Inject secondary-body failure and verify SC-08.

**Evidence:** algebraic fixtures, frame/units ledger, orientation and work residuals under refinement, and exact layout identity.

### SC-08: Rejected stage, retry and diagnostic output

**Maps:** WP-04/05/06; SG-07/08/15; T07/GI-09/21.  
**Setup/stimulus:** fail each actor at sample preparation, each RK stage, weather query, endpoint validation and staged sidecar preparation. Include a pending/held release intent. After failure, use the qualified recovery/restore path before retry; the current faulted kernel cannot simply resume unchanged.

**Oracle:** both physical frames, authoritative controller/RNG/owner state, cadence and intent-consumption state match the last accepted boundary; no new accepted sample, located event or score comes from the rejected candidate. A correctly attributed pause/fault diagnostic and incomplete log footer are allowed. Repeat/restore applies a retained release at most once. State whether the pending request is already in the checkpointed transactional ingress or is re-fed from its timed external tape; a checkpoint cannot recover a later unrecorded input.

**Evidence:** compare physical and diagnostic ledgers separately, including actual session sidecars. A guard over kernel arrays alone does not prove arbitrary external state rollback.

### SC-09: Committed pair with observer or writer failure

**Maps:** WP-04/06; SG-07/15; accepted-publication contract.  
**Setup/stimulus:** inject renderer/log/observer mutation, attempted transition reentry and write failure before physical commit and after the accepted pair has committed, including an ownership transition.

**Oracle:** precommit rejection retains the old pair. A postcommit observer failure retains the new accepted pair, reports the qualified accepted-fault/hold result and cannot reissue the transition as if it never happened. A missing disk row cannot be called complete exact replay; preserve the verified prefix/incomplete status. No recursive notification or second commit is allowed.

**Evidence:** boundary identity, committed result, observer failure, writer completeness and intent/result counts. This is a required new pair-boundary qualification, not a claim that ordinary baseline tick publication already has the reset/restore guard.

### SC-10: Intent effective time and held-controller phase

**Maps:** WP-04/06/10/11; SG-07/10/11/15; T08/T10/C03.  
**Setup/stimulus:** version the SF/AFC/FL timing decision first. Exercise all phases of a declared guidance hold; a four-tick divisor is a useful synthetic phase fixture, not a production default. Submit release and transfer immediately before, on and after guidance refresh, including a held-control tick.

**Oracle:** the record identifies observed/sampled input, effective mechanical/ownership time, which owner/commands drive each interval, and the accepted publication boundary. Release intent handling cannot silently wait for a different cadence than declared. A left-boundary and endpoint implementation must not be mixed.

Include ideal instantaneous release versus any separately admitted finite actuation; request acknowledgment alone does not prove the hook opened. Test retry, duplicate intent, equal-time events and restore. The baseline endpoint merge appends events; the owner must supply and verify causal composition/tie policy rather than assume automatic sorting.

## 4. Ownership, replay and encounter cases

### SC-11: Combined refusal, release-first and later takeover

**Maps:** WP-10/11; SG-10/11; C13/T16.  
**Setup/stimulus:** begin with human tug/AI glider. Make pickup or tug recovery unavailable, refuse combined transfer, accept independently available release, restore readiness, then Take glider.

**Oracle:** the human retains the tug until an accepted takeover. The released AI glider has bounded free flight or the whole activity holds; no tow follower targets a disconnected tug. Later takeover preserves released line state, publishes one new ownership result, initializes tug control at the correct boundary and creates no duplicate release or credit. Repeated already-completed requests are idempotent under the declared policy.

**Evidence:** both command sources, applied/achieved controls, line state, effective event times and full decision replay.

### SC-12: Input pickup, lag, trims and reconnect

**Maps:** WP-11/15; SG-11/13; C04/C05/C06/C11/GI-19.  
**Setup/stimulus:** high tug throttle, both brake-axis polarities if installed, nonzero trims, flight modes, saturated commands, lagging servos, discrete AUX states and disconnect/reconnect. Restore midway through a blend/pickup.

**Oracle:** one arbiter writes effective commands; requested intent, post-limit command and achieved position stay distinct. No silent brake deployment, stale switch, actuator-position reset or inherited wrong profile. The pending/timeout policy and held command remain explicit. Real-device claims require actual devices; synthetic axis fixtures cover software only.

**Evidence:** signal chain, owner/axis readiness, timer/cadence state and accepted sequence across restore.

### SC-13: Two replay modes and compatibility

**Maps:** WP-06/11/13; SG-07/11/15; T11/T12/GI-21.  
**Setup/stimulus:** record a full pair through slack, release, interruption and restore. The manual-tug variant also includes transfer; the AI-tug/human-glider variant needs no takeover or transfer back to the tug. Preserve the initial complete checkpoint, source identities and all external control/intent interventions. Compare decision replay and command-driven solver replay separately.

**Oracle:** decision replay reconstructs controller/pickup/cadence and decisions plus accepted physical state. Solver replay uses the pinned command boundary and exogenous-event policy, recomputes/compares endogenous events, and declares its physical projection; it cannot silently claim full controller-memory equality. Neither mode double-injects a recomputed break/contact. Camera/quality/cosmetic RNG changes leave the physical contract unaffected.

Reject incompatible source/law/layout/backend/field or label a changed-solver comparison. A truncated log remains incomplete. Test actor IDs and intent deduplication across restore.

### SC-14: Swept aircraft and uncertain rope path

**Maps:** WP-09/12; SG-07/10/11/12; T13/T14/GI-11.  
**Setup/stimulus:** between-tick wing crossings with clear endpoints, rotating thin proxies, tangency, fast closure and simultaneous release. Separately exercise a taut swept line and a slack length enclosure near terrain/airframe/propeller geometry with defined hook exemptions.

**Oracle:** a qualified swept-aircraft incident prevents success; endpoint-only clearance is insufficient. A conservative rope enclosure intersection means possible/unknown contact, not proved impact. Inconclusive required clearance follows the declared refusal/hold/terminal policy without tow-success credit. A solver-only separated fixture cannot establish this gate.

**Evidence:** independent analytic/high-precision geometry cases, trajectory-bound assumptions, false positives/negatives, accepted event ordering and complete-pair outcome.

## 5. Weather, failures and end-to-end delivery

### SC-15: Finite thermal and instrument truth

**Maps:** WP-08; SG-06; A11/A12/A15/GI-13…16.  
**Setup/stimulus:** isolate the thermal component using otherwise identical zero-cell control and full legal objects. For the proposed wide-cell example, evaluate peak age, center and `H/2`, then `R`, compact support, birth/expiry and low height.

**Oracle:** with `P=1.8 m/s, H=200 m`, center/half-height/peak-age updraft is `1.8 m/s`; at `h=10 m` it is about `0.0440491 m/s`. These field values are not aircraft climb. Test the actual radial/age law and stage domains, mass-flux assumption, instrument filter/latency/warmup/dropout and restored state. Separate physical truth from sensor estimates and assistance.

**Evidence:** analytic residuals plus flown task feasibility when implemented; a weak-lift negative case must not gain hidden lift.

### SC-16: Shared epoch, domain, pause and remaining life

**Maps:** WP-08/10; SG-06/07; A13/A14/C09/GI-14/18.  
**Setup/stimulus:** equal and separated world queries for both actors/stations, changed query order, translated cell, domain edges, pause, restart and restore. Preserve full field/atmosphere/instrument identity.

**Oracle:** equal position/time/config queries agree; spatial phase/coherence is tested where enabled. A `3600 s` world horizon with `300 s` offset leaves `3300 s` of simulation time, not a renewed cell. Pause freezes physical clocks/filter state together. Invalid secondary-stage or station queries reject the candidate coherently. Cosmetic time or random draws cannot move physical lift.

**Evidence:** scenario serialization, domain/epoch trace, field sample comparisons, accepted pair record and explicit finite-cell outcome.

### SC-17: Concurrent events and separated recovery failure

**Maps:** WP-05/10/11/12; SG-08/10/11/14; T09/T10/T15/T16/C14.  
**Setup/stimulus:** release near a located contact/source-loss boundary, plus post-release recovery-path/controller failure and unsupported intersections. Add an overload excursion between endpoints only when a physical break law is actually admitted.

**Oracle:** qualified compositions have one deterministic causal outcome with the stated timing error and tie policy. Unsupported compositions refuse/hold with no partial state or success. After separation, no actor disappears or freezes independently; both final states and ownership remain complete. Disabled physical break cannot appear as an unexplained strength threshold; scripted release stays labelled.

**Evidence:** independent event oracle/refinement, ordered events, rejected versus committed faults and complete/incomplete record classification.

### SC-18: Ground take-up, release and abort

**Maps:** WP-12; SG-12; T08/T10/T14.  
**Setup/stimulus:** admitted flat field, both contact configurations, slack take-up, allowed lift-off order, release during take-up and during ground roll, and a rejected airborne-only takeover.

**Oracle:** both ground states and line geometry evolve under the admitted laws. Ground release opens the line once and produces the defined abort/stop outcome without unrequested ownership change. A still-attached endpoint cannot be removed. Unsupported entanglement/contact combinations cannot be rescued by teleport, rope extension or hidden force caps.

**Evidence:** contact/support facts, line/ownership events, clearance, abort result and restored/replayed activity, including a positive supported takeoff case.

### SC-19: Actual controls, RC view and response chain

**Maps:** WP-03/07/10/11/15; SG-13/17; GI-19/20.  
**Setup/stimulus:** actual advertised keyboard/gamepad/radio and OS path, native 1920×1080 viewport, declared FOV axis/camera/aids, intended distances/orientations/backgrounds, focus loss and reconnect.

**Oracle:** players can identify the controlled actor, attitude, release binding and pickup state in the scoped tasks. Measure input-to-accepted-command, command-to-accepted-motion and motion-to-visible-response with synchronized clocks and defined events; distinguish transport delay from actuator/airframe response. FPS alone is insufficient. Record assistance and physical dimensions independently.

**Evidence:** device/profile identities, rendered observations, task errors and timing distributions. Synthetic screenshots, mocked input and a 720p run cannot qualify the 1080p/device claim.

### SC-20: Release scope, complete evidence and package

**Maps:** WP-13/14/15; SG-15/16/17.  
**Setup/stimulus:** one declared aircraft/mode/weather/device/platform release candidate plus incomplete-data, unsupported capability and incompatible-log cases.

**Oracle:** UI/catalog/help expose the admitted scope and limitations; package resources, source/backend identities and required CI/export evidence agree. Basic outcomes and debrief use accepted events without duplicate restore credit. Synthetic fields are marked as such; physical measurement/validation receipts are required only for the corresponding claim. Causal learning claims have their separate evidence.

**Evidence:** the 08 claim receipt, applicable A/T/C/SC results, actual 1080p complete-activity cost, device/platform/package artifacts and retained failures. Do not convert missing evidence into a pass, and do not treat a narrower claim as a waiver of repository release gates.

## 6. Existing test roots and execution route

The following paths exist in the inspected source. Extend/reuse only the relevant cases; these checks have not been run for this handoff and are not current glider/tow coverage.

| Source test roots under `app/tests/` | Relevant new cases |
| --- | --- |
| `test_aircraft_modules.gd`, `test_aircraft_contract.gd` | SC-01, source/generated compatibility |
| `test_trim.gd`, `test_flight_session_staged.gd`, `test_home_launch_setup.gd` | SC-02/03 and prepared lifecycle |
| `test_hand_launch.gd` | SC-04 |
| `test_sf_vehicle_model.gd`, `test_sf_framed_sampled.gd` | SC-05/07/08/10, layout and finite guards |
| `test_sf_event_protocol.gd`, `test_sf_event_refinement.gd`, `test_sf_contact_substeps.gd` | SC-06/07/10/17/18 |
| `test_checkpoint.gd`, `test_replay_integrity.gd`, `test_flight_log_inputs.gd` | SC-08/09/11/12/13 |
| `test_companions_session.gd`, `test_companions_lifecycle.gd`, `test_companions_record.gd`, `test_companions_restore.gd` | Existing companion regressions only; independent sessions do not substitute for atomic pair tests |

Follow the [tool index](../../tools/README.md), [physics tooling](../../tools/physics.md) and [flight-log workflow](../../FLIGHT-LOGGING.md). Use the repository's checked runner and shared-host admission for actual execution; preserve required OS, session handle, request ID and exact source snapshot. Required CI still applies. Do not invent a glider CLI flag or test filename from these scenario titles.

**Authoring verification:** the SC-05 and SC-15/16 arithmetic is an independent calculation of stated equations; it is not an executed simulator, physical, hardware, performance or learning result. Each future case must retain the implemented check and its observed result.
