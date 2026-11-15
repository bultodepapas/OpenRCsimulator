# Glider launch, towing roles, and control transfer

**Owner:** SG session/product with input/UI, AFC, CAM, GP/CR and FL.  
**Status:** proposed contracts for [SG-04…14](../glider-soaring.md#7-delivery-sequence-and-canonical-step-status).  
**Source baseline:** `ad21070798bfb9658785576a9c0b8bfc9a71fc7f`. Existing paths and limitations are recorded in the [source review](../../research/glider-soaring/2026-11-15-source-review.md).

## 1. Mode matrix

The launch method, the human-controlled aircraft, and assistance level are separate choices. Resolve them once before launch and show the resolved result in Home, the loading page, pause, log and debrief.

| Mode | Start | Human owns | AI owns | Completion / scope |
| --- | --- | --- | --- | --- |
| Solo air start | Valid trimmed glide at selected position/height | Glider | None | Soar and land; first playable slice |
| Hand release | Ground-relative throw at a real release pose | Glider from release | Optional explicit launch assistance only | Short glide and landing first; do not promise a thermal rescue |
| AI aerotow | Valid airborne pair initially; ground roll after SG-12 | Glider | Tug | Human releases; tug follows a qualified post-release route |
| Manual tug → glider | Same pair | Tug until transfer, then glider | Glider until transfer, then tug | One recorded “release and take glider” action |
| Manual tug only | Same pair | Tug throughout | Glider throughout | Optional tow-training variant; requires a defined autonomous glider outcome |
| Two-pilot aerotow | Pair | Each user owns one actor | Optional fallback | Later local/network feature, I09 |
| Electric self-launch | Explicit motor-glider installation | Motor glider | Optional instructor | Separate propulsion/propeller/energy data; not a pure glider flag |
| DLG, bungee, winch, slope | Method-specific initial state/constraints | Appropriate glider | Method-specific support | Deferred; each needs its own physical/terrain and release gates |

A line-of-sight RC camera is the default presentation. Chase/FPV are optional views and assistance/classification settings for challenges. The same physics runs in every view.

## 2. Preflight resolution

The resolver returns either a complete immutable scenario or a specific unavailable reason. It must consider:

- Aircraft configuration and supported launch capabilities; physical data and visual/control binding identity.
- Tug/glider speed-envelope overlap, installed hooks, line law and numerical stiffness envelope.
- Human role, selected input profile, release/transfer binding, and required axis pickup.
- Current mass, CG, control trim, brakes/flaps and electronics assumptions.
- Field/runway geometry, glider skid/belly support, person/obstacle exclusion and both wingspans.
- Complete weather configuration, domain, horizon, epoch, start altitude and all station locations.
- Required AI controllers and source-bound admission, restart behavior and post-release outcome.
- Supported contact, propulsion, cable and failure event combinations.
- Backend availability, pair recording/checkpoint version and display assistance.

Do not add aircraft-ID checks throughout the UI. The capability resolver owns admission; the UI shows its reason and the nearest valid option. Loading cancellation or failed preparation preserves the previous accepted activity and preferences. Apply, Cancel, save-as-default and trial-flight semantics follow the existing shell.

Direct-flight CLI and Home must produce the same resolved scenario when given equivalent explicit inputs. Direct launches must not accidentally read Home preferences.

## 3. Solo airborne start

Choose the complete configuration first, then:

1. Set a position with valid terrain clearance and weather/station clearance; distinguish height above actual terrain from height above the weather's flat datum.
2. Solve an unpowered trim at the requested **airspeed**, density and configuration. Include its descent angle, pitch and actual control settings.
3. Convert air-relative velocity to ground velocity by adding local wind exactly once.
4. Initialize actual actuators, sampled control state, instrument filters and event modes consistently.
5. Commit the prepared state and observers through the existing accepted-start transaction.

A constant altitude with zero thrust is not the default trim. Optional “start level and let it settle” is an authored non-equilibrium exercise and must be named as such.

Height choices such as 30, 80 and 150 m are proposed training UI values, not aircraft limits or legal guidance. Their availability depends on terrain, weather ceiling, station clearance and aircraft visibility. Use a model-relative speed preset—minimum sink, best glide or a tested recovery margin—and display the resolved numeric airspeed after calibration.

The glider should remain usable with an entirely calm atmosphere. This is the primary polar and energy reference.

## 4. Hand launch

### Physical contract

The throw is a **ground-relative initial condition**. Store release position, orientation, velocity and angular velocity; compute initial local airflow from ground velocity minus the complete local wind. Ground contact and the person animation do not continue applying a hand force after release.

Specify and validate:

| Input | Requirement |
| --- | --- |
| Release position | Grip/CG relation, terrain datum, body/wing/tail clearance and pilot placement |
| Velocity | World vector derived from the selected throw profile; source or estimation label |
| Attitude | Body heading, pitch and roll; pitch is not automatically angle of attack |
| Rates | Explicit small or measured angular rates; never inherited from a previous flight |
| Controls | Prepared actual surfaces and trim; the same stick mapping used after release |
| Wind | Local full field at release time, including any enabled stochastic component |
| Assistance | Off by default for physical validation; declared actions, duration and logging when enabled |
| Timing | Countdown and single accepted release event; cancellation remains reversible until commit |

The existing powered MoonRunner hand-start settings—1.9 m, 6.5 m/s ground-relative, 5° climb and full throttle—are source facts about that aircraft, not defaults for this glider. Its motor-off negative control further shows why copying the settings is insufficient.

A proposed trainer launch may begin from a tested airspeed margin above that build's stall onset. It must still be a physically plausible ground-relative throw. In a headwind, airspeed can exceed throw speed; a tailwind reduces it. Do not “correct” every throw to the target airspeed after release.

### Interaction

Home shows “Hand launch → you fly the glider.” In the field the player gets a stable view, control readiness, wind cue and a release action. The simulator can depict an assistant holding the aircraft so a transmitter user has both hands available; the visual helper does not own physics.

Cancellation leaves the aircraft held and does not start a flight record or statistics. A successful release starts one record. Press-and-hold cannot generate repeated impulses. Restart uses the same resolved recipe, with an explicit separate choice for a new randomized attempt.

A physical short hand toss in calm air is a valid lesson. The current tall thermal law has weak lift near the ground; the [weather dossier](03-aircraft-and-weather.md) explains why most sustained thermal lessons should use air starts or tow.

Full discus launch is deferred. It needs a different aircraft, grip/rotation and release-state evidence; an overhand throw with a large velocity multiplier does not establish DLG behavior.

## 5. The tow activity state machine

Keep control ownership orthogonal to the mechanical line state. For example, a player may still own the tug after the line has released.

~~~mermaid
stateDiagram-v2
  [*] --> Prepared
  Prepared --> AirborneTow: Valid paired air start
  Prepared --> TakingUpSlack: Ground start qualified
  TakingUpSlack --> GroundRoll: Line ready
  GroundRoll --> AirborneTow: Both aircraft airborne
  TakingUpSlack --> Aborted: Cancel or fault
  GroundRoll --> Aborted: Abort or contact failure
  AirborneTow --> Separated: Release or qualified break
  AirborneTow --> Aborted: Pair failure
  Separated --> Recovering: Glider free and tug clears
  Recovering --> Finished: Qualified end condition
  Aborted --> Finished: Accepted terminal outcome
~~~

Internal line modes include attached/slack, attached/tensioned, released and, only if qualified, broken. Slack/taut transitions do not transfer the human controls. Rendering may show sag but must not imply an unimplemented catenary or collision law.

### Ground sequence, after SG-12

Start with both aircraft and a clear line corridor in valid contact configurations. The tug takes up slack at bounded speed, then accelerates according to the admitted installation. The glider may lift before the tug and must remain in its allowed tow geometry. The controller holds an airspeed/attitude envelope and shallow initial route; steep turns and overhead passages require separate qualification.

Tug runway width alone is insufficient: check both airframes, tail/line routing, hook positions, skid/belly friction, takeoff order, terrain gradient and obstacle clearance. The first line model omits rope-ground/propeller entanglement. Admission and presentation must state that limit; do not teach a recovery whose success depends on unmodeled rope contact.

At any unsafe or unsupported combination, the defined outcome is a refused start, a recorded release/abort, or a paused fault. No force clamp, aircraft teleport, indefinite frozen glider, or secretly extended rope may conceal the failure.

Terrain contact does not add aircraft-to-aircraft collision automatically. The existing companion fleet has no such contact forces. For this activity, qualify a geometry-based pair exclusion and terminal-incident policy before scored towing; it must detect relevant swept encounters and prevent a success outcome for intersecting airframes. If full inter-aircraft impact mechanics are deferred, identify that limit explicitly. A controlled solver prototype may disable collision only inside a strictly separated airborne fixture; that is not product collision qualification.

## 6. AI tug with human glider

The tug controller receives a detached accepted pair snapshot, shared weather, route, aircraft envelope and line observations. It commands the actual tug surfaces and propulsion. It cannot write positions, speeds or attitudes.

Use nested guidance and bounded control:

- Route and altitude guidance select an attainable path and energy target.
- Airspeed, roll/pitch and coordinated-turn control respect the **pair's** envelope.
- Tow supervision observes glider position, attitude, closure, slack/tension and terrain.
- Abort/release supervision produces versioned deterministic intents.
- Anti-windup and saturation handling prevent controller memory from accumulating impossible commands.

Candidate control cadence is 60 Hz with commands held for four 240 Hz ticks, subject to measurement; this is a design seed, not an existing qualification. Stage evaluations reuse the accepted tick sample. Controllers' integrators, previous errors, mode, held commands, timers and decisions belong to the checkpointed pair.

The current companion circuit controller can supply patterns and utilities. Its admission must not simply be bypassed: towing, spatial weather, terrain and takeoff are new conditions. Evaluate a new tow profile on a defined matrix. A control law that passes straight calm towing is not automatically qualified in gusts, turns or at low release height.

Human glider controls remain normal. A novice overlay can show alignment and tension, but automatic corrections are an explicit instructor mode. Instructor status follows the flight into scoring and debrief.

## 7. Manual tug, followed by glider control

From the start, the glider requires its own follower controller. It flies the aerodynamic model and actual surfaces; it is not fixed to a point behind the tug.

Provide three distinct commands:

| Command | Mechanical action | Ownership action |
| --- | --- | --- |
| Release tow | Release the specified available hook | Keep current human aircraft |
| Take glider | None, only in a separately admitted attached-transfer mode | Human → glider; AI → tug |
| Release and take glider | Release and transfer in one accepted intent | Human → glider; AI → tug |

The third is the primary requested journey. Attached transfer is an advanced option and can remain unavailable initially. Display each command's actual binding rather than inventing a global key that may conflict with existing controls.

Every release intent identifies an actor and an installed hook. A human flying the tug normally commands the tug's release. A command to the glider's hook while its receiver is AI-owned is an explicit simulator coordination command, with admitted cross-actor authority and a recorded reason; it does not imply that one physical transmitter operates both receivers. Offer a separate release action even if a combined transfer is refused for pickup/recovery readiness. Show the refusal reason without disabling a physically available emergency release.

### Atomic handoff

At the chosen accepted tick boundary:

1. Validate the intent, actor identities, connection mode, input readiness and available tug recovery controller.
2. Capture both actual aircraft/actuator states and the current held commands.
3. Initialize each tug-controller loop at its actual output boundary, using the accepted post-limit/arbiter command and a guidance target consistent with the accepted trajectory. Preserve achieved physical servo positions separately. Seed/track integrators and filters under explicit anti-windup and saturation semantics; a lagging servo position is not the previous actuator command.
4. Release the line if requested, change ownership, and update takeover/axis-pickup state as one transaction.
5. Publish a single ordered event containing tick, reason, old/new owners and release status.
6. Change the camera target from the accepted event and animate the view separately.

If validation fails, none of these changes commit. If a postcommit observer fails, follow the kernel's accepted-fault contract rather than claiming rollback.

Actual servo positions remain continuous. A brief command blend is permissible only as a versioned assistance/input policy with recorded duration; it must not blend physical positions or velocities. “No physical jump” means no unauthorized state reset, not that a genuine control command cannot change acceleration.

Apply the takeover policy to **all** controls, not just the former throttle axis. The proposed assisted mode uses one command arbiter: for roll/pitch/yaw it transitions from the saved glider command to live human commands over a bounded, tested interval; for brakes, flap modes, gear and other discrete AUX roles it holds the accepted state until explicit pickup/acknowledgment. The glider AI ceases writing commands when ownership changes; the arbiter is the only effective writer during the transition. Its saved commands, timer, per-axis status and input samples are checkpointed and recorded. A provisional 0.25 s primary-axis transition is a tuning candidate, not a qualified default; physical/manual validation can select immediate takeover with its abrupt-command semantics clearly disclosed.

Show which axes are pending. A pickup timeout must never silently deploy a surface or assign a stale switch state: retain the held command and request an explicit action, or pause the whole pair under the chosen interruption policy. A disconnected device follows the pair hold policy. Neither a timed transition nor a waiting AUX leaves the aircraft without an explicit command source. Validate mode switches and trims as well as primary stick axes.

### Prevent the throttle-to-brake surprise

A tug pilot may have the throttle stick high at transfer. When the selected glider has an explicitly admitted airbrake or spoileron mix, mapping that value instantly to braking can deploy full brake. A trainer without that capability must not display or invent it.

Use named role mappings and a recorded pickup policy. On transfer, hold the glider's already accepted brake command until the axis enters a defined neighborhood of that command, then grant control. Show “Move brake axis to pick up” and a visual position cue; support keyboard/gamepad and an optional explicit neutralization action. Test both polarities and flight-mode switches. Preserve trim and flap selections by actor.

The exact tolerance, blend duration and any novice holding assistance are provisional UI/control parameters; select them with real transmitter users. They must never change unnoticed between identical recorded scenarios.

The [GI-19 investigation](../../research/glider-soaring/2026-11-15-investigations-04-delivery.md) sharpens this existing transfer requirement. Telemetry distinguishes requested intent, applied actuator command and achieved physical position with units/polarity. Tracking state advances only through the pair transaction; an inactive controller cannot write effective commands. Test transfer with saturation, servo lag, bank, trims, flight modes and reconnect. A matching initial command does not establish that the new guidance target is reachable.

## 8. What the tug does after release

Both aircraft continue to exist and fly. Choose a bounded, tested recovery route using the accepted state, present airspeed, terrain and actual separation. Do not always hard-code “turn left” if the glider or terrain is there.

The first airborne slice may use a safe circuit/loiter with a defined distance/altitude envelope. Autonomous landing is a separate gate; existing companion takeoff/landing research does not establish runtime support. A mission can end when the player lands, but the pair's terminal event and final aircraft states must remain complete. Removing a tug for presentation/performance is allowed only after an explicit out-of-activity transition, with persistence/logging semantics; never delete a still-attached actor.

If the tug engine fails, loss of thrust comes from the propulsion/failure owner. If the human releases, the free glider remains controllable. Unknown structural strength must not be replaced with a fabricated break rating. Scripted emergency-release lessons can exist separately from physically modeled weak-link breakage.

## 9. Interruption, reset and failure behavior

| Condition | Required behavior |
| --- | --- |
| Pause or focus loss | Freeze both aircraft, AI timers, rope, weather epoch and physical instrument state together |
| Controller disconnected | Apply the selected existing activity hold policy; default pause both, with explicit resume/reconnect flow |
| Reconnect | Revalidate profile/polarity and axis pickup; never send a stale high-throttle command to a new role |
| Restart | Rebuild the complete recipe, actors, controllers and epoch; define same-seed versus new-challenge actions |
| Restore | Restore the entire pair and ownership; unsupported historical or mismatched formats refuse without replacing the old flight |
| Invalid second-body weather/force | Reject the entire candidate; no first-body advance or leaked event/controller memory |
| Simultaneous release and failure | Apply only a qualified versioned composition; otherwise reject/roll back the whole candidate and pause with the unsupported-intersection reason |
| Tug crash before release | Follow an explicitly admitted pair incident policy; do not freeze only one endpoint |
| Glider landing first | Contact/finish rules identify which actor landed and whether the line remains attached |
| Repeated or held action | One event per accepted edge; no duplicate release, credit or owner assignment |
| Time scale or catch-up limit | Preserve fixed simulation ticks and event order; no independently running AI or wind clock |
| Menu trial/settings edit | Preserve accepted configuration until the existing prepared-commit boundary succeeds |

The default run has one human owner and one AI owner per pair before/after transfer. It never has two input writers for the same actuator and never leaves an actor uncontrolled for a tick.

## 10. Presentation and accessibility

Always identify **You control: Glider/Tug**, line status and the release/transfer bindings. Use shape/text as well as color for warnings. Show commanded versus achieved surfaces in the debug/trainer view; the ordinary flight view stays concise.

Suggested optional instruments: TAS, groundspeed, actual terrain height, weather-datum height when relevant, altitude rate, TE or estimated netto, line tension/slack and elapsed task time. Indicate provisional or unavailable aircraft limits rather than drawing authoritative colored speed bands from guessed data.

The camera transition must preserve orientation and a useful horizon. The RC ground camera keeps the pilot location; chase/FPV blend toward the selected actor. Configure transition motion and reduced-motion behavior. The user can inspect the line and both aircraft without accidentally transferring control.

Vario sound, wind sound and servo sound are observers. A pure glider has no phantom engine sound. Tone indicates the selected instrument and has independent mute/volume. Diagnostic thermal visualization is an explicit aid and can be hidden until debrief for challenges.

Verify native 1920×1080 first, then higher resolutions and 720p fallback. Include small distant silhouettes, contrast against sky/trees, ultrawide/zoom behavior, 200% UI scale, keyboard/controller focus, English/Spanish text, and focus/controller-loss recovery. Headless tests do not prove visual readability or real-radio usability.

## 11. Research additions to launch, guidance and learning

The [24 investigations](../../research/glider-soaring/2026-11-15-investigations.md) add the following observable requirements without changing the four player journeys.

**Release measurements — GI-05.** Author release position, CG ground velocity, attitude, angular rate and achieved controls as a correlated configuration-specific state. Transform tracked markers to the CG using the measured lever arm/rates. Do not assemble independent marginal maxima into an unobserved throw; DLG swing energy and flexible launch behavior require their own dataset.

**Reachable towing and swept clearance — GI-08/11/12/17.** Admit routes using joint force/moment trim, available tug power, actual actuator travel/rate and recoverable separation. Check swept aircraft motion and any claimed line corridor over the full interval, with explicit hook exemptions and unmodeled slack/contact outcomes. Simulation-truth tension or lift-center access is idealized assistance when not supplied by an admitted sensor. Keep the wake omission visible; the source's three-propeller-diameter measurement extent is not a clearance rule. Release remains independently available if takeover readiness fails.

**RC view and timing — GI-20.** Record projection and FOV axis, viewport, zoom/tracking, visual scale and aids. Keep physical dimensions/forces unchanged by graphics settings. Measure input → accepted applied command → accepted motion → visible response with synchronized timestamps and a defined response event. Report actuator/aircraft dynamics separately from transport delay. Evaluate actual attitude recognition, alignment and approaches at intended distances; neither FPS nor a nominal camera angle establishes usability.

**Learning flow — GI-15/16/24.** Give each lesson explicit objectives, prerequisite skills, assistance, finite weather and accepted end events. Teach short glide/landing before centering and return, then tow position, release/transfer and admitted aborts. Separate physical-truth diagnostics, sensor-derived instruments and assisted cues. Debrief accepted outcomes and choices; distinguish completion, assistance, deliberate abort and technical refusal. Preserve version/reset/restore identity, and assess withheld scenarios rather than duration alone.
