# Random failures and emergency practice

**Updated:** 2026-10-14. **Status:** logical-control/throttle mode, glow/electric power loss, aircraft-specific availability and the shared actuator foundation implemented; independent hardware and aircraft recovery qualification remain open. **Owner:** Emergency training track, **EM-00…28**. Shared physics, aircraft contracts, UI, propulsion and damaged-flight work remains with its existing owners in the [track registry](../README.md#tracks-plans-and-step-ids). **Research:** [EM-00 source review and audit](../research/failure-mode/EM-00/README.md). **Implementation evidence:** [EM-01 initial slice](../research/failure-mode/EM-01/README.md), [EM-05 power-loss adapters](../research/failure-mode/EM-05/README.md), [EM-03a controls and availability](../research/failure-mode/EM-03a/README.md).

**Outcome:** any supported airplane can participate in optional emergency practice through the same capability-based system. A player chooses a whole-number failure probability from **0 to 100**, optionally admits catastrophic failures, and optionally sees a notice when the failure happens. The airplane responds through its real simulated controls, propulsion and aerodynamics. Learning, surprise and repeatable challenges are the reasons to use the feature.

The implementation checkpoint below identifies existing behavior. The remaining sections describe the broader target, not delivered or physically validated features. The document is in English following repository policy; the implemented interface supports English and Spanish.

### Implementation checkpoint — current scope

- **Home → Failures** selects integer probability 0–100, catastrophic admission and notices. Pause offers settings for the next flight; Apply also updates notices in the current flight. Cancel discards all draft changes. Restart retains the resolved episode. End flight reports an active incident, a healthy draw or an interruption before onset.
- **Eight ordinary injected mechanisms:** both ailerons held through the existing roll actuator, elevator hold, rudder hold, roll bias, pitch bias, slow roll servo, throttle-demand ceiling and elevated throttle-demand hold. Jams capture actual servo position; trim does not release a jam. Keyboard `[` / `]` adjusts roll trim; existing PgUp/PgDn adjusts pitch trim.
- **Two family-specific ordinary mechanisms:** finite-glow fuel/combustion cutoff and electric motor-drive disconnection. Each eligible aircraft adds only its own mechanism. Propeller RPM remains a continuous physical state, allowing coast or windmilling. Glow fuel delivery stops without deleting remaining fuel; electric motor current stops while modeled auxiliary consumption continues. These persistent failures prevent restart until Repeat or a new flight; controls remain available.
- **One opt-in catastrophic mechanism:** sustained simulated receiver link loss, holding the last accepted control commands with throttle demand at idle. Real controller disconnection retains its existing pause behavior.
- `app/failures/` owns strict configuration, catalog and versioned private RNG/runtime. A draw assigns at most one event. Selection is uniform over the eligible pool: eight ordinary events for control-only profiles, nine for finite-glow/electric profiles, plus radio loss when admitted. This policy supersedes the proposed 90/10 category weighting below. These are training choices, not measured RC reliability.
- New `openrc-failure-plan v2` records bind to the normalized propulsion profile. Historical v1 records retain their original event set, seed mapping and reader. Restore/reload rejects a v2 profile mismatch before changing the flight. Aircraft IDs do not select mechanisms; legacy RPM models, sampled shaft models and turbines retain control/throttle faults with explicit source-shutdown exclusion reasons. **Available failures for this aircraft** shows the eligible pool and those reasons in Home/Pause; catastrophic admission filters the displayed radio-loss event.
- **EM-03a foundation:** the existing scalar servo law now has a shared actuator kernel, a validated detached batch path, and a direct accepted-surface observation for physics/rendering. Isolated four-position fixtures exercise independent aileron angles. Current aircraft keep their three logical servo states; single-side jams and split elevators are not yet installed capabilities or new random events.
- Onset is resolved once at **20–120 seconds of qualified airborne time**: accepted physics ticks at least **5 m above local terrain**, with wheels uncompressed. Paused time does not count. Ending before that time does not satisfy the scheduled emergency. The default technical/direct route remains off; Natural Random and non-airplane routes do not inherit this option.
- The session stages the incident before integration, commits it before external stepped observers and discards it on numerical rejection. `openrc-flight-checkpoint v10` wraps the existing physics format without changing its state layout; native checkpoints carry the complete resolved plan and runtime. Enabled trace headers retain the plan and recording-start state.
- Direct reproduction on the default legacy Stik: `-- --failures=100 --failure-seed=1751` selects a roll-actuator jam after 20 qualified seconds. The same seed can resolve a different event on a different eligibility profile. Additional flags: `--catastrophic=on|off`, `--failure-notices=on|off`. Seed range is 0–4294967295. Technical launches do not read saved preferences.

This advances the logical-topology portions of **EM-01…11**, the capability and source-loss portions of **EM-02/05**, and the receiver profile in **EM-17**. It does **not** close all their acceptance gates. Independent single-aileron/split-elevator hardware, turbine flameout/relight, intermittent power, brownout, in-flight wing separation, richer lessons, exported-build checks, target-hardware performance and RC pilot recovery qualification remain pending. Stuck throttle uses each existing energy model; it does not manufacture finite fuel in a prescribed-fuel installation. The source-loss adapters reuse accepted engine laws; they do not calibrate new shutdown transients.

**Navigation:** [Product](#1-product-decisions) · [Research](#2-evidence-and-realism-boundaries) · [Menus](#4-player-flow-and-menus) · [Probability](#5-exact-probability-time-and-repeat-semantics) · [Fault catalog](#6-fault-catalog) · [Aircraft standard](#7-standardization-across-airplanes) · [Numerics](#8-numerical-and-code-design) · [Wing loss](#10-wing-separation-and-continued-damaged-flight) · [Practice](#11-useful-and-enjoyable-practice) · [Verification](#13-verification-and-acceptance) · [Phases](#14-phased-implementation).

## 1. Product decisions

| Question | Proposed decision |
| --- | --- |
| Checkbox or percentage? | One integer slider plus numeric field, **Failure probability per flight / Probabilidad de falla por vuelo**, 0–100. Display `%` because it is a probability. Zero is Off, so a second enable checkbox would duplicate state. |
| Meaning of 90 | Each new accepted flight independently has a 90% chance of being assigned one failure episode. It does not mean 90% damage, nine guaranteed failures in every ten flights, or a 90% chance every second. |
| Meaning of 100 | Every accepted, compatible flight is assigned an episode, with a bounded activation time. A flight ended before its activation is recorded as interrupted before the event, never as a successful healthy draw. |
| Default | 0%; **Include catastrophic failures** unchecked; **Notify when a failure occurs** checked. Enabling catastrophe does not change the master probability. |
| Number of faults | One initiating episode per flight in the first releases. Consequences of that cause, such as a receiver outage affecting several channels, belong to the same episode. Independent multiple failures are a later, explicit advanced option. |
| Intended difficulty | The ordinary pool contains aircraft-qualified, potentially manageable cases. Recovery still depends on attitude, height, airspeed, weather and pilot action. It never promises survival. |
| Catastrophe | Opt-in admission of cases with major or potentially unrecoverable loss of control/structure, including sustained radio loss and wing separation. A class label is a training category, not a certified severity assessment. |
| Notices | A brief nonmodal, localized message at committed onset; no automatic pause, camera cut or control interception. Hidden notices suppress diagnostic hints, not physical symptoms. A postflight explanation remains available. |
| Restart | **Repeat this flight** restores the original start and the same resolved episode. **New flight** makes a new draw. A failed launch, opening a menu or toggling notices never redraws. |
| Existing normal flight | Remains unchanged at 0%. Physical consequences already present, such as a prop strike or finite-fuel exhaustion, remain possible; 0% disables injected training faults. |
| Assets and dependencies | Reuse the current aircraft, sounds, widgets, sections and tests. No new engine, plugin or asset pack is needed for the core feature. Evaluate existing freely downloadable, appropriately licensed material before creating any later asset. |

These defaults resolve the requested feature without requiring additional design choices before starting EM-01. They remain proposed until implemented and accepted. Record accepted architectural decisions in [DECISIONS](../DECISIONS.md); do not label this entire proposal as an existing decision.

## 2. Evidence and realism boundaries

The [research register](../research/failure-mode/EM-00/README.md#primary-source-register) contains primary references, relevant pages, applicability and limits. The main findings are:

1. **A failed channel, a jammed servo and a detached surface are different faults.** A command can hold its last value while the actuator continues moving toward it; a mechanical jam holds actual surface position. An unpowered or disconnected surface may move under hinge loads. The [JSBSim actuator reference](https://jsbsim-team.github.io/jsbsim/classJSBSim_1_1FGActuator.html) provides useful malfunction semantics, not RC calibration.
2. **Loss of the radio link is not loss of electrical power.** Receiver failsafe may hold outputs or drive presets while powered; brownout can prevent it operating. The [Spektrum DXS/AR410 manual, p.9](https://www.spektrumrc.com/on/demandware.static/Sites-spektrum-us-Site/Sites-horizon-master/default/Manuals/SPM1010-Manual-EN.pdf) documents this distinction. Do not simulate every modern receiver by making the sticks twitch randomly.
3. **An electric motor can lose power while the controls still work.** An ESC may reduce power or cut it at its configured threshold. Battery, BEC, receiver and propulsion wiring determine the outcome. The [EFLA1040 guide, pp.2–4](https://www.horizonhobby.com/on/demandware.static/Sites-horizon-us-Site/Sites-horizon-master/default/Manuals/EFLA1040-Completion%20Guide-EN.pdf) supports separate behaviors, not a universal voltage threshold.
4. **Turbine idle, shutdown, flameout and restart are separate states.** A relight needs an identified ECU and sufficient time and energy. The [Xicoy manual, pp.31 and 34–35](https://www.xicoyturbines.com/assets/files/XicoyTurbojetManual_EN.pdf) is comparison evidence; it cannot add Xicoy features to the simulator's historical JetCat P100-RX. The [AV plan](turbine-realism.md) owns that installation.
5. **RC trim usually changes the command to the same servo.** It cannot free a physically jammed elevator. Full-scale advice involving an independent trim tab, such as the [FAA emergency chapter, p.18-11](https://www.faa.gov/sites/faa.gov/files/regulations_policies/handbooks_manuals/aviation/airplane_handbook/19_afh_ch18.pdf), must not be copied as universal RC recovery advice.
6. **Losing a wing changes more than lift.** Mass distribution, moments, control availability and flow coupling change. [NASA's damaged-body equations](https://ntrs.nasa.gov/citations/20070030307) and [wind-tunnel damage study](https://ntrs.nasa.gov/citations/20080034656) justify a separate physical extension. Their transport-aircraft data do not validate an RC 3D airplane.
7. **A commercial precedent exists for adjustable failures and notification timing.** [RealFlight 9.5, printed pp.67–72](https://www.horizonhobby.com/on/demandware.static/-/Sites-horizon-master/default/dw6b391a4f/Manuals/RealFlight-9.5-Manual.pdf) is a UX reference. Its product options are not measurements of fault rates or a reason to reproduce its undocumented physics.

No reviewed source establishes representative failure incidence for the simulator's aircraft fleet. Selection weights, severity bands and onset windows below are **training-policy estimates**. Hardware quantities belong to their identified installation and carry the aircraft contract's evidence metadata. Keep physical validation, software verification and player usefulness as separate gates.

### Two different meanings of “the wing drops”

An aerodynamic wing drop during a stall/spin leaves the structure attached. It should emerge from asymmetric flow and the existing flight model; it is not a random mesh-removal event. **Wing separation** means a structural panel physically leaves the airplane. The requested feature includes the latter in the catastrophic plan, alongside distinct stall-awareness exercises.

Do not assert that wing loss is common from dramatic videos, or that only 3D airplanes can ever survive it. High thrust, remaining controls, fuselage side force and a suitable attitude may help some models. None is a guarantee. The separation event is intended for every airplane whose damage adapter is supported, with recoverability explicitly unknown or qualified for that configuration; it is not restricted by an `aircraft_is_3d` switch.

Two relevant cases are Todd Bridges at Tucson in 2009, described by [the person who filmed it](https://electricdan.wordpress.com/2009/10/22/tucson-aerobatic-shootout-amazing-one-wing-landing/), and Manuel Santos at XFC 2013, reported by [AMA's Model Aviation](https://www.modelaviation.com/xfc2013). Both accounts describe one-wing landings by expert aerobatic pilots. The [source review](../research/failure-mode/EM-00/README.md#r15--original-account-of-an-rc-one-wing-landing) records provenance and access limits; neither account supplies a calibrated damaged-aircraft model.

## 3. Current repository and integration seams

This snapshot was inspected on 2026-10-13 while other tracks had active edits. The graph was used for discovery, then current source was checked because indexed line ranges were stale. A final readback found Natural Random's initial runtime integration had arrived during this review; its current restrictions are included below. Recheck these seams at implementation time; do not treat the file list as permission to replace concurrent work.

| Existing file or contract | What exists | Planned use or limitation |
| --- | --- | --- |
| [STACK](../STACK.md), [simulation.gd](../../app/sim/simulation.gd) | Custom float64 rigid body and RK4 at 240 Hz; candidate tick validation and accepted `stepped` event. | Fault state must obey the same transaction, fixed timestep and numerical safeguards. Godot rigid bodies do not become the flight solver. |
| [flight_session.gd](../../app/sim/flight_session.gd) | Owns aircraft, trim/start, commands, holds, propulsion, crash/reset and checkpoints. `_pre_step()`, `flown_commands()`, `surfaces()`, `_deflections()` are key seams. | Own one accepted failure context per session; prepare effects before a tick, commit once after success. Keep orchestration outside a growing monolithic session implementation. |
| [control_surfaces.gd](../../app/physics/control_surfaces.gd) | Converts one roll command into left/right aileron angles; pitch and yaw each have one logical surface output. | Both ailerons already appear separately in aero deflections, but their independent servo states do not exist. Add physical actuator topology before claiming a one-side jam. |
| `FlightSession` auxiliary state | Base engine RPM and three logical servo positions; optional modules extend runtime state. One conventional servo-rate setting is used by the current path. | Preserve existing layouts and identity; add a versioned mapping rather than assuming a free array index or editing an array length alone. |
| [AIRCRAFT_CONTRACT](../AIRCRAFT_CONTRACT.md), [AS plan](aircraft-standardization.md) | Closed v2 capability/module contract; conventional controls; no general structural part loss. AS-15 already covers per-surface identity work for flaps. | Coordinate one shared topology extension with AS. No unknown failure fields silently inserted in v2 and no duplicate EM actuator schema beside AS's. |
| [aero.gd](../../app/physics/aero.gd) | Local wing-strip and tail loads plus current normalized control inputs. | Retain sign conventions; independent elevator halves and damaged topology need actual load support, not only render hinges. |
| [propulsion plan](../PROPULSION-CORE-PLAN.md), [electric plan](../ELECTRIC-PROPULSION-PLAN.md), [glow guide](../GLOW-ENGINES.md), [turbine plan](turbine-realism.md) | Different legacy, shaft, electric, finite-glow and turbine paths. Fuel capabilities differ. | Inject family-specific causes through existing lifecycle/stage interfaces; no universal final-thrust multiplier disguised as a mechanism. |
| [app_root.gd](../../app/app_root.gd), [main.gd](../../app/main.gd) | Shell launch/restart/end lifecycle, startup errors and trace/visual context. | Transfer a detached validated failure request into the candidate flight; bind it only on accepted launch. |
| [screen.gd](../../app/ui/screen.gd), [screen_stack.gd](../../app/ui/screen_stack.gd), [widgets.gd](../../app/ui/widgets.gd) | Current shared screen, focus and input isolation components. | Add one small configuration screen now; the proposed UI redesign can move its entry point later. |
| [preferences.gd](../../app/app_state/preferences.gd), [es.po](../../app/i18n/es.po) | Versioned preferences and localization. | Add validated keys through the owner's migration path. Do not hardcode the next preference version while UI-24 is also planned. |
| [Crash guide](../CRASH-DAMAGE-PLAN.md) | Soft hull contacts, prop-strike continuation and experimental postcrash breakup; damaged flight CR-11…15 remains open. | A training fault does not call the terminal crash path. Reuse the eventual damage adapter; postcrash pieces are not evidence of flyable structural damage. |
| [Natural Random plan](natural-random-flight.md), [scenario_config.gd](../../app/scenarios/scenario_config.gd), [natural_random.gd](../../app/scenarios/natural_random.gd) | Initial runtime integration is present. `openrc-flight-scenario v1` has exact keys, five stock IDs and `mode == natural_random`; no failure module. | Reuse its identity/preparation conventions, but extend the schema deliberately. NR remains fault-free by default; a later explicit combined mode needs NR qualification. |
| [Workshop](../AIRCRAFT-WORKSHOP.md), generated bindings | Detached experiments and generated model/physical sources. | Training failures are session effects, never saved into aircraft experiments or hand-edited into generated JSON. |

Current software coverage includes all eight catalog configurations: base Stik, Extra, P-51, Ventage Jet, Timber, Stik 2T, Stik 4T and Stik 61FX. The latter inherits finite-glow eligibility without an aircraft-ID branch. Multiple visual or engine variants do not imply independent control topologies. Future catalog additions inherit applicable mechanisms through capabilities, while their training envelope still needs qualification.

## 4. Player flow and menus

### 4.1 Configuration on today's shell

Add **Failures / Fallas** to the existing Home setup area. Keep Fly as the primary action. Show a short summary beside the entry: **Off**, **30% · Standard**, or **100% · Catastrophic enabled**. Do not hide the active probability only inside global Settings.

```text
FALLAS DEL PRÓXIMO VUELO

Probabilidad de falla por vuelo       [────●────────] [ 30 ] %
0: desactivadas · 100: siempre se programa una falla

[ ] Incluir fallas catastróficas
    Puede perderse todo el control o parte de la estructura.
[x] Avisar cuando ocurra la falla

Las fallas disponibles dependen de los sistemas de este avión.
Se programa como máximo una emergencia por vuelo.
Si terminas antes de su activación, la falla no llega a ocurrir.

[Aplicar]  [Cancelar]
```

Helper text explains that very short flights can finish before activation. Show excluded capabilities in an optional **Available failures** detail view, with meaningful reasons such as **Independent elevators are not modeled**. No raw capability IDs or solver terms in the main flow.

At 0, dependent controls may be visually disabled while retaining their last values. Enabling catastrophe reveals its explanation without a second confirmation dialog. Applying settings changes the next new flight request, not current aircraft source data. Cancel leaves persisted and draft values unchanged. An empty eligible set prevents launching *with failures*, explains why, and lets the player explicitly choose 0; it must not silently substitute a different airplane or reduce probability.

### 4.2 Pause and active flight

- Pause shows the active probability/category and **Failure settings for next flight**. Probability and categories cannot heal or redraw the current event. State-changing edits apply to a new flight; Repeat retains the accepted one.
- The notice checkbox can change immediately as a presentation preference. It neither resamples nor changes physics. Turning it on does not retroactively reveal a hidden fault unless the player explicitly asks for a hint.
- At onset, show a short message such as **Left aileron jammed / Alerón izquierdo trabado** or **Engine stopped / Motor apagado**, then a compact optional status line. Suggested toast duration is 4–6 seconds of visible presentation time; not a physical parameter.
- Hidden mode keeps motor sound, motion and visible surface behavior. It suppresses failure labels, cheat highlights, diagnosis tooltips and voice hints. Intentional technical diagnostics may still reveal state and should label the attempt as assisted.
- Menus, loss of application focus and a real USB/controller disconnect retain the existing pause/arming policy. They are never interpreted as simulated radio failures.
- No default new keyboard shortcut until checked against the canonical controls table. Optional instructor injection goes through a menu/action registry later. Radio sticks continue to control flight, never menu focus.
- Screen readers, keyboard focus, contrast, scaling and EN/ES text are evaluated with the UI track. Do not claim accessibility merely because labels exist.

### 4.3 Postflight explanation and repeat

Provide an emergency section after a landing, crash or explicit End flight. It records what happened, when, how the controls/engine actually responded, and which pilot options remained. Avoid naming a hidden event before the flight ends. A flight with no selected event gets a plain **No training failure this flight** entry; it must not fabricate suspense.

Actions: **Repeat same flight**, **New random flight**, **Practice this failure with explanation**, **Back to Home**. The last action restores ordinary selections. A later **Repeat from before failure** requires a complete accepted checkpoint, including input/arming, fault state, weather and presentation; it is not a cheap teleport.

Do not immediately end control at first wheel contact. Let the airplane settle through the real ground/contact rules; use a qualified dwell and state test for any automatic landing completion. Ventage Jet's current locked-up gear does not qualify a normal runway landing lesson. Until its landing/contact work is accepted, jet practice can grade controlled approach or descent, with the existing collision outcome clearly labeled.

### 4.4 Natural Random and future Home

Failure configuration belongs to a reusable flight modifier, not a second weather/aircraft selector. Ordinary Natural Random remains as specified by NR. Later, an explicitly labeled **Natural Random + failures** option can combine its resolved conditions with this feature after joint qualification; it must not consume the weather RNG or overwrite normal preferences. UI-25 can place the same configuration under **Next flight → Failures**, and a later Training action can offer lessons without duplicating its controls.

At the EM-00 audit, `app_root.start_flight(request)` treated every nonempty request as Natural Random and required its briefing screen. The initial EM implementation introduced a separate failure modifier while retaining NR's exact mode/prepared-identity checks. Natural Random remains fault-free; its five-aircraft allowlist is independent of failure-mode fleet coverage.

## 5. Exact probability, time and repeat semantics

### 5.1 One draw per accepted flight

The request contains an integer `probability_percent` in `[0,100]`. Validate type and bounds; reject booleans, fractional values and nonfinite inputs. Prepare the eligible set before drawing. A rejected candidate does not consume the next accepted flight's identity.

```text
if p == 0: no injected episode; use the existing healthy path
elif p == 100: select exactly one compatible episode
else: select an episode iff a uniform integer in [0,99] is less than p
```

This avoids inclusive floating RNG endpoint mistakes. Probability is independent of frame rate, flight duration after onset, rendering, HUD reads and pause duration. Do not perform repeated per-tick Bernoulli tests: a nominal 1% repeated every tick would make failure almost certain very quickly.

When catastrophe is allowed, select an ordinary versus catastrophic **family first**, then a mechanism/target within the chosen family. Proposed initial policy: **90% ordinary / 10% catastrophic conditional on an episode**, renormalized only over available categories before launch and shown in Details. Thus `p=90`, with both categories available, means 81% ordinary, 9% catastrophic and 10% no injected event. This 10% is a training weight, not a real-world rate. Do not make catastrophic events more likely merely by adding more definitions to their catalog.

At 100 with catastrophe off, every qualifying flight gets one ordinary episode. At 100 with catastrophe on, every flight still gets one episode; not every episode is catastrophic. Named manual lessons bypass the random selector and say **Fixed exercise**, rather than pretending a 0% setting produced a random failure.

### 5.2 Activation clock

For the first release, resolve a tick in a bounded window after airborne handoff; **20–120 seconds of active airborne simulation** is a provisional usability range to qualify, not a hard universal requirement. Runway sessions start that clock after a hysteretic airborne detection; ground taxi and pause do not consume it. Use tick counts and the recorded fixed timestep. An aircraft with a shorter qualified circuit may need a shorter authored window.

Make onset deterministic for the same committed state/input history. The definition includes any ramp duration, intermittent pulse schedule and recovery delay. Repeated disconnect/reconnect pulses belong to one resolved episode; do not draw fresh random noise in the load solver.

The standard scheduler does not defer an event forever waiting for an ideal attitude. Compatible starts and ordinary severity are qualified in advance; at the scheduled time the effect occurs. A pilot can still turn an ordinarily manageable fault into an unrecoverable situation by flying low or at a limit. A future coached mode may wait for a safe setup, but must advertise that different scheduling policy and report timeouts. It must not quietly weaken the meaning of 100%.

End/crash before activation cancels the pending event and records `ended_before_onset`. Keep separate counters for accepted flights, selected episodes, activated episodes and interrupted flights. “100%” guarantees selection and bounded onset in a flight that continues through its activation window; it cannot cause an event after the user has ended a flight. Never force an event during the End flight dialog to repair statistics.

### 5.3 Random identity

Use a private RNG and versioned seed derivation, compatible with the scenario design: uint32 master seed, SHA-256 over canonical bytes and a stable tag for occurrence, category, mechanism, target, onset and magnitude. Stable ID ordering is mandatory. Failure selection must not change turbulence, lighting or cosmetic randomness. A stored resolved episode, not just its seed, is the replay authority.

Godot exposes RNG seed/state but treats its algorithm as an implementation detail ([Godot 4.7 reference](https://docs.godotengine.org/en/4.7/classes/class_randomnumbergenerator.html)). Record engine/build, generator/catalog/policy versions and aircraft fingerprints. Serialize full-width integer RNG states losslessly in native checkpoints or strings, not through a JSON floating-point number. No global `randomize()`, wall-clock event timer, random draw in an RK stage, or RNG consumption by a notice.

### 5.4 Lifecycle rules

| Action | Required behavior |
| --- | --- |
| Open/close configuration | No simulation advance or new accepted seed. |
| Accept new flight | Validate and freeze request, eligible set and resolved episode; keep actual episode hidden if notices are off. |
| Failed launch | Discard candidate; restore old Home/world/preferences and last accepted flight context. |
| Pause/focus loss | Freeze active simulation clocks and pending fault transitions. |
| Repeat/reset | Rebuild original healthy start, original trim and energy state; restore the same resolved episode and clear previous activations/visual remnants. |
| New flight | New occurrence draw and new episode; reuse chosen probability and notice/category preferences. |
| Aircraft change | Revalidate capabilities and discard incompatible drafts; never retarget an active episode to a different airplane. |
| Restore checkpoint | Restore pending/active/resolved fault state, progression and identities atomically; no re-roll and no duplicate onset notice. |
| Actual device disconnect | Existing hold/failsafe/arming behavior; modeled radio outage remains frozen with the flight. |
| Numerical invalidity | Existing diagnostic stop, never relabeled as a training emergency or hidden by a gameplay message. |

## 6. Fault catalog

**O** means a candidate for ordinary practice after per-aircraft qualification. **C** requires catastrophe enabled. **A** means later advanced or named practice, not automatic initial-pool admission. These are proposed eligibility tiers; a severe magnitude can promote an O mechanism to C. “Both” and “one” always refer to actual components and shared dependencies, not mesh count.

### 6.1 Controls and setup

| ID / tier | Event and mechanism | Simulation requirement | Learning and admission |
| --- | --- | --- | --- |
| `aileron.single_hold` O | One actuator freezes at its actual onset position. The other continues responding. | Independent left/right actuator state; bounded jam capture for ordinary admission, full envelope C/advanced. | Recognize reduced/asymmetric roll response; use remaining roll/yaw authority. Qualify left and right separately. |
| `aileron.both_hold` O/C | Both stop responding, usually near their established trim in the manageable lesson. | Explicit common channel/servo cause where topology supports it; otherwise label simultaneous training injection. | Rudder-assisted bank control depends on actual dihedral/yaw-roll coupling. Never inject a hidden rudder-to-roll aid. |
| `aileron.offset` O | A servo/linkage neutral shifts while the actuator still responds. | Per-surface persistent bias with physical travel stops. | Opposite stick/trim may compensate, with asymmetric reserve. Distinguish bias from a stuck surface. |
| `rudder.hold` O | Rudder actuator jams or its command holds. | Identify which mechanism and whether steering shares the linkage. | Use available bank control, reduce difficult crosswind demands; ground steering may also be affected. |
| `elevator.single_hold` O/C | One elevator half freezes; the other remains active. | Independently actuated halves plus separate aerodynamic loads and hinge bindings. | Pitch authority and asymmetry matter. Two visible halves driven by one servo are not independent. |
| `elevator.all_hold` C/A | All elevator motion is lost. | Whole-axis jam and remaining actual throttle/trim architecture. | Advanced energy/attitude management. Digital trim cannot move a jammed servo. |
| `actuator.slow` O | Servo response becomes sluggish or travel is restricted. | Rate/lag/stop change with continuous actual position; no instantaneous angle teleport. | Anticipation and early, small corrections. Mechanical cause remains an estimated scenario unless identified. |
| `actuator.intermittent` A | Connection intermittency creates bounded hold/resume intervals. | Recorded interval sequence, chosen powered/unpowered behavior and recovery dynamics. | Recognize inconsistency without arbitrary frame noise. Ordinary admission only after manageable durations are shown. |
| `setup.trim_offset` O | Airplane begins off trim, or a bounded trim-command offset appears. | Apply after healthy trim/start; retain separate base trim, pilot trim and scenario offset. | Retrim a responsive airplane. Deliver usable roll/pitch/yaw trim controls before admitting each axis. |
| `setup.reversed_channel` A | Incorrect setup reverses a channel before launch. | Preflight setup exercise, separate from spontaneous hardware failure. | Detect during a control check and reject takeoff; no unexplained random reversal midway through an ordinary flight. |
| `surface.linkage_disconnect` A/C | Control linkage disconnects and surface loses commanded constraint. | A stated surrogate or hinge-moment/inertia/damping model; neither a hard jam nor zero aerodynamic area. | Diagnose free response; do not invent a universal neutral angle. Defer free-surface physics. |
| `surface.detached` C | An aileron, rudder or elevator panel leaves the airframe. | Structural mass, aero, contacts and visuals all change. | Separate from servo failure; use the damage phase, even if the detached part is small. |

Ordinary jam profiles need special care. An actuator that freezes at a large current deflection may be catastrophic even if its ID is usually ordinary. EM-04 must choose an explicit policy: initially offer **hold near trim** as a named condition with its own onset predicate and bounded timeout, or admit a measured capture envelope. The random 100% path must always retain a compatible fixed-onset mechanism such as a bounded offset/power fault; resolve any predicate-conditioned choice/fallback in the episode at launch and record which branch activates. Never call a commanded move to neutral a mechanical jam at the previous position.

### 6.2 Power and energy

| ID / tier | Event | Physical requirement | Lesson and constraint |
| --- | --- | --- | --- |
| `engine.combustion_lost` O | Glow/gas engine stops producing combustion torque. | Family lifecycle, shaft rundown/windmilling/drag and wake response where supported. | Deadstick approach. Zero throttle or idle RPM is not necessarily an engine stop. |
| `turbine.flameout` O/C | Turbine loses combustion. | Qualified flameout/stop transient, residual rotor effects and ECU policy. | Energy conservation and a committed approach; no instant thrust restoration or invented in-flight relight. |
| `electric.drive_cut` O | ESC/motor drive torque is removed while control bus remains powered. | Electric drive and propeller state; explicit brake/freewheel behavior. | Glide planning with controls retained; do not automatically declare a receiver brownout. |
| `power.available_reduced` O | Available shaft power or thrust is lower. | Family-specific torque/power/ECU limitation, coherent RPM, current/fuel and wake; magnitude from qualified scenario profile. | Recognize reduced climb margin and avoid relying on a go-around. A motor power percentage is not the same as a thrust percentage. |
| `throttle.slow_response` O | Throttle servo, command channel or controller response is delayed. | Delay/lag at the named layer, with saved buffer/state. | Plan power early. Healthy turbine spool delay remains normal behavior, not itself a fault. |
| `power.intermittent` A | Repeatable brief combustion/drive interruptions. | Resolved pulse sequence entering the real powertrain; physical restart rules. | Recognize unreliable power and commit to a feasible landing. No identical law across electric, glow and turbine. |
| `throttle.stuck_high` O/C | Throttle linkage or received demand holds high despite reduced pilot command. | Fault placement relative to independent engine kill, finite energy and current lifecycle. | Control excess energy; use a genuinely independent cutoff if installed. High thrust can make the situation severe. |
| `fuel.exhaustion` O/A | Usable fuel reaches zero. | Finite tank, consumption, changing mass/CG/inertia and shutdown. | Endurance and glide planning. Do not use a countdown pretending to consume an infinite tank. |
| `battery.lvc` O/A | Loaded battery voltage triggers ESC reduction/cutoff. | Finite battery, under-load voltage and identified ESC threshold/hysteresis. | Reduced power does not always mean loss of servo supply. A fixed-voltage fixture cannot exhaust a fictional charge state. |
| `fuel.feed_interruption` A | Fuel supply is temporarily interrupted. | Identified feed model or explicitly injected supply condition; ECU/engine reaction. | No universal inverted-flight timeout or flameout on bank angle. Correct RC fuel systems can operate inverted. |
| `esc.thermal_derate` A | Controller reduces output on overtemperature. | Thermal state and measured/identified policy; otherwise label generic power limitation. | Teaches limitations without presenting a nonexistent temperature model as real. |

**Stuck throttle and waiting for fuel:** retain the exact requested exercise. First implement it on a finite-fuel configuration such as the explicit Stik glow installations, after validating their cutoff interaction. If engine kill uses the same mechanically jammed carburetor servo, it cannot free that linkage. An independent ignition/fuel shutoff can stop a suitable installation. The lesson may disable a kill only when the scenario declares its absence/failure, not to force waiting. When fuel is finite, consumption and the actual empty-tank event determine the wait. Legacy prescribed-fuel Stik/Extra/P-51 and the current turbine branch cannot claim this exercise until their owning energy extensions exist. Electric endurance has a different depletion/cutoff sequence; do not call it running out of gasoline.

### 6.3 Radio, structure and later systems

| ID / tier | Event | Required behavior and limits |
| --- | --- | --- |
| `radio.link_dropout` C initially | Temporary missing valid receiver frames. | Hold/preset/ECU reaction follows a receiver profile. Recovery uses existing actuator/engine dynamics; no arbitrary new attitude. A brief, qualified form can become an ordinary lesson later without weakening the catastrophic checkbox. |
| `radio.link_lost` C | Sustained complete link loss. | Pilot commands stop reaching the receiver model while the simulation continues. Failsafe outputs can influence the trajectory; pause/reset/menu remain available. No claim that a preset guarantees a safe landing. |
| `receiver.brownout` C | Receiver supply becomes inadequate. | Power-domain model, receiver reboot/reacquisition and actuator/ESC consequences. Powered failsafe cannot be assumed during outage. BEC architecture must be explicit. |
| `wing.partial_separation` C | Outer wing section detaches. | Remove the actual section, affected control and mass; solve asymmetric loads and compatible remaining contacts. Qualify both sides and several locations. |
| `wing.panel_separation` C | A complete left or right wing panel separates. | Same generic damage path for trainer, warbird, jet and aerobatic airplane; no guaranteed recovery and no restriction to a marketing class. Detailed prerequisites in §10. |
| `tail.separation` C | Fin/rudder or horizontal-tail section separates. | Damage topology, stability and control loss are separate from a servo hold. |
| `propeller.loss` C | Propeller or blade is lost. | Distinguish whole-prop separation, imbalance and the existing ground strike. A thrown blade needs rotor imbalance/bearing effects before a physical claim. |
| `gear.asymmetric` A/C | A retract fails, one leg collapses or a wheel seizes. | Defer until real gear/contact topology is supported. Current fixed/locked gear must not animate a retract-only failure. |
| `flap.asymmetric` A/C | One flap sticks or fails to deploy. | Depends on AS-15, flap physics, independent actuation and contact/approach qualification. Modeled neutral flap meshes are insufficient. |
| `stabilization.lost` A/C | Gyro/assist becomes unavailable. | Only if a real modeled stabilization controller is active. No hidden gyro in aircraft currently flying with assists off. |
| `multi_engine.single_lost` A/C | One propulsion unit fails. | Wait for AS's repeated propulsion, real thrust arms and differential effects; never fake a twin with a yaw impulse. |

Causal cascades are later work: for example an explicitly powered servo overload leading to bus sag and receiver reboot. Do not achieve the same spectacle by drawing three unrelated faults and calling it one cause. High-frequency flutter and progressive fatigue require structural models and evidence; the initial structural exercise injects a stated separation event, not an unvalidated material-strength threshold.

## 7. Standardization across airplanes

### 7.1 Three layers of data

1. **Aircraft capabilities and topology:** physical components, independent actuation, linkage/channel groups, power domains, fuel/battery type, section membership, kill paths and supported laws. AS owns the shared authoring extension. Preserve the existing `{value, unit, kind, source}` convention for physical quantities.
2. **Failure definitions:** immutable mechanism ID, schema version, required capabilities, supported target selectors, parameter constraints, model-law identity, dependencies, conflicts, labels and evidence references. EM owns this reusable catalog.
3. **Training policy/resolved episode:** player probability, allowed severity, onset/parameter distribution, qualified aircraft envelope, resolved target/time/magnitude, seed and identities. This is scenario/session data, never an aircraft's permanent health.

Avoid `if aircraft_id == "extra"` in kernels. Stable physical target IDs map to actual actuator/surface/propulsion/section bindings. The catalog ID can select qualification evidence and profiles without becoming a hardcoded solver branch. No matching target means an explicit exclusion with a reason; it does not mean choose a similarly named mesh.

### 7.2 Topology requirements

The minimum shared extension should distinguish:

- Physical control surfaces with aerodynamic area/arm and stable identity.
- Actuators with limits, rates, source channel/mixing and linked surfaces.
- Receiver outputs and dependency groups: one servo driving two ailerons, a Y harness with two servos, two independent receiver outputs, two elevator servos, shared steering and rudder.
- Powerplant/controller/energy source and independent stop mechanisms.
- Optional structural sections linked to inventory components, aero elements, mesh sections and collision points.

A Y harness does not make two servos mechanically identical: a failed single servo can affect one side while loss of the common channel affects both. Conversely, one elevator servo with a joiner cannot provide independent left/right elevator actuation. Do not infer wiring from the number of channels, model nodes or inventory masses alone.

For existing v2 models, supply an explicit compatibility adapter representing their current logical actuators. It can support whole-axis faults and common trim/power exercises immediately. Do not invent hardware detail. The independent-actuator extension must either fit an explicit approved conditional-module revision or advance the authored format with migration; AS chooses this before EM-03b adds installed topology and independent accepted state. Unknown topology or versions fail validation.

### 7.3 Required reusable catalog fields

The following are proposed fields, not accepted v2 aircraft keys:

| Group | Required information |
| --- | --- |
| Definition identity | Stable `failure_id`, definition/law revision, category, localized label key, evidence and assumptions. |
| Eligibility | Supported vehicle family, capability predicates, target role/count, independent/shared dependency requirements, propulsion/energy law requirements. |
| Effect | Mechanism and insertion layer; parameter domains and units; permanent/transient behavior; active state shape. |
| Training envelope | Qualified severity, starts, weather/airspeed/height context, available recovery controls, qualification revision. |
| Composition | Exclusive group, priority/precedence and permitted causal children; no arbitrary modifier stacking. |
| Recording | Required physical observables, event cause/provenance, onset/end rules and checkpoint compatibility. |

One conformance runner enumerates compatible cases for every valid catalog entry and additional authoring fixtures. A future airplane should need data/bindings and qualification, not custom failure code. Invalid aircraft still cannot fly. Preview models, unsupported vehicle families and incomplete Workshop topology are not admitted by a generic checkbox.

### 7.4 Fleet milestone

The first *framework* can land with a small subset of whole-axis/propulsion mechanisms. The first release advertised as **random airplane failures** must cover the complete current conventional-airplane catalog with at least one meaningful ordinary episode and a truthful unavailable-case list. The requested single-aileron and split-elevator features have explicit later acceptance gates; do not call the feature complete merely because an engine can be turned off.

Helicopters, drones and ground vehicles can later reuse occurrence, records and UI, with their own control/energy/damage adapters and owner qualification. Do not map “left aileron” onto a rotor servo or assume “any airplane” already includes every vehicle family.

## 8. Numerical and code design

### 8.1 Proposed file boundaries

All new paths below are **proposed**. Introduce only the files needed by the current step; keep prototypes outside `app/` until parse-valid.

| Proposed path | Responsibility |
| --- | --- |
| `app/failures/config.gd` | Strict player-request and resolved-episode validation/copying. |
| `app/failures/catalog.gd` | Load immutable definitions, capability filtering, stable target resolution. |
| `app/failures/scheduler.gd` | Pure seeded occurrence/type/onset resolution and bounded discrete transitions. |
| `app/failures/runtime.gd` | Detached active effects, candidate/commit/rollback state, reset and checkpoint representation. |
| `app/failures/observations.gd` | Read-only event/affected-control diagnostics for trace, HUD and debrief. |
| `app/data/failures/definitions_v1.json` | Reviewed mechanism metadata and eligibility; no repeated aerodynamic aircraft parameters. |
| `app/data/failures/training_profiles_v1.json` | Estimated training weights/ranges plus qualification references and version. |
| `app/physics/control_actuators.gd` | Proposed shared AS/physics per-actuator kernel; choose the final name with AS rather than adding a competing implementation. |
| `app/ui/failures_screen.gd` | Probability, checkboxes, available-case details and next-flight scope. |
| `app/ui/emergency_debrief.gd` | Explanation and repeat/new-flight actions using current screen components. |
| `app/render/overlays/failure_notice.gd` | HUD-owned optional committed-event notice; no state mutation. |
| `app/tests/test_failure_*.gd` | Contract, mechanism, transaction, lifecycle, trace and fleet tests. |
| `research/failure-mode/` | Offline qualification and distribution/paired-flight tools, created when implemented. |
| `docs/research/failure-mode/EM-xx/` | Accepted sources, model limits, trace/capture/benchmark and pilot evidence. |

Shared edits should be small and reviewed with owners: `flight_session.gd`, `simulation.gd`, `main.gd`, `app_root.gd`, aircraft schema/module registry/generators, propulsion adapters, UI preferences and translations. EM does not own a fork of Aero, the aircraft catalog, the crash solver or Workshop serialization.

### 8.2 Physical signal flow

```text
real input device → calibration/arming → rates/expo + pilot trim
  → transmitter/channel effect (only if that is the selected fault)
  → modeled receiver hold/preset/power state
  → aircraft mixing/linkage mapping
  → actuator dynamics + local jam/bias/limits
  → actual per-surface deflections
  → aerodynamic forces and moments at RK stages

receiver/actuator demand → propulsion controller + energy/lifecycle effect
  → actual torque/RPM/fuel/current/wake → forces and moments

accepted simulation state → render hinges, sound, notices, trace and debrief
```

If a future aircraft uses different mixing location or a stabilizer controller, topology must represent that ordering. Avoid an all-purpose filter after final forces. The receiver model does not replace the real input-device handler.

### 8.3 Continuous state and discrete faults

Keep positions, deflections, timers expressed in seconds, rates, energy and force calculations in scalar doubles or `PackedFloat64Array`. Discrete IDs, tick counts and flags use integer/typed state with explicit serialization. No `Vector3`, `Basis`, `Quaternion` or `Transform3D` in the simulation state. Render conversion remains at its boundary.

For a servo, a useful mechanism specification is a rate/lag-limited response toward a saturated target. An illustrative continuous law is:

```text
target_i = clamp(mapped_command_i + bias_i, physical_min_i, physical_max_i)
rate_i   = clamp((target_i - actual_i) / tau_i, -rate_down_i, rate_up_i)
jammed_i: actual_i stays at the captured actual position
```

This is a design sketch, **not a replacement law to install silently**. Preserve the current healthy rate-limited law and its exact operation order first. Add lag only as an explicit qualified extension with timestep/stiffness checks. A hardover commands an extreme target through the actuator's dynamics; a jam freezes actual state; held receiver demand can still let a servo reach its old target. Keep sign/unit conversion in the shared control-surface adapter.

For reduced engine power, choose a documented insertion point: reduced maximum delivered torque, drive voltage/duty limitation, ECU power cap, or combustion availability. Check rotor energy and fuel/current consistency. Do not multiply total aircraft forces by a “damage factor.” For a surface still physically present, jam does not remove its baseline lift/drag or stability contribution. Lost control effectiveness and lost lifting area require different models.

### 8.4 Atomic tick transaction

1. Read the last accepted tick and complete fault/runtime state. Resolve any due discrete transition into a detached candidate; do not publish it yet.
2. Build an immutable effect view for that candidate interval. Capture jam angles once from the previous accepted actual actuator state, before that interval's healthy movement. The effect's convention and effective tick must be recorded.
3. Run actuator/pre-step and RK evaluations with that same view. RK stages may evaluate continuous effect ramps at stage time, but never advance RNG, event counters or histories.
4. Validate all body, auxiliary, continuous, mode, mass/topology and fault candidates. Existing numerical failure handling retains authority.
5. On acceptance, commit states and the event together. Only then emit the notice, audio transition and event record. All observers see the same tick identity.
6. On rejection, restore all affected state, RNG/cursors, held commands, dependency effects and pending event records. A failed tick must leave no invisible active fault or emitted “ghost” notice.

Existing aux rollback alone is insufficient for new session-side dictionaries, buffers or histories. Implement an explicit transaction adapter; do not rely on signal connection order to make commits atomic. A replay checkpoint is taken only after this complete commit boundary.

### 8.5 Onset, discontinuities and timestep

Quantize injected discontinuities to a recorded fixed-tick boundary; onset quantization is at most one 240 Hz step, about 4.17 ms. State which side of the boundary an event affects. All four RK stages for a smooth interval use the same discrete mode. A known discontinuity inside an interval requires deterministic step splitting or alignment, not stage-dependent random mode changes. Natural fuel exhaustion uses the owning energy integrator's event treatment, coordinated with the same event timeline.

A ramped fault is a deterministic function of elapsed simulated time. Check dt refinement on smooth segments and event-aligned traces; do not demand fourth-order convergence across an unaligned jump or change the production fixed timestep during a live session. Delays use bounded saved buffers; high-frequency random jitter/flutter is excluded from the MVP.

### 8.6 Trim and initialization

First validate and solve the healthy start through the normal aircraft/environment path. Then initialize the fault context. In-flight faults activate later. An explicitly selected off-trim-at-start lesson applies its offset after successful trim and before handoff, and must not ask the trim solver to cancel that offset. The 20–120 s default applies to in-flight failures, not a declared setup exercise at tick zero.

Keep original solved trim, user trim and fault bias separately observable. Retrimming a responsive plane changes the user's command; it does not clear the failure. A future aerodynamic trim/stabilizer system has a distinct physical actuator. Avoid “heal on trim,” reset-only phantom offsets and source-aircraft modifications. On switching back to normal flight, no fault, altered trim, held channel or depleted scenario state can leak across sessions.

## 9. Propulsion and receiver integration details

### 9.1 Common interface, distinct family laws

AS-12's preparation/stage/state/observation boundaries are the integration home. Resolve effects once outside the hot loop, then pass normalized parameters/state to each family. Provide explicit support for commanded stop, injected loss of combustion/drive, limited command, limited available output, and normal versus failed restart. An unsupported effect rejects preparation rather than using a fallback that happens to reduce thrust.

| Family now present | First supported slice | Required later work |
| --- | --- | --- |
| Legacy lagged combustion | Bounded throttle-command faults; a separately qualified stop/rundown surrogate with its limitations visible. | Real finite fuel and detailed restart/mixture behavior before endurance or mixture-cause claims. |
| Coupled shaft combustion | Torque loss/limitation through the accepted shaft law, preserving propeller loading and rotor state. | Identified stop/kill/restart and finite energy where absent. |
| Explicit glow 2T/4T | Existing lifecycle and finite-fuel state supply a stronger seam for cut, depleted fuel and stuck-throttle episodes. | Qualify both cycle families independently; do not copy one transient profile to the other. |
| Electric | Drive cut/limit with actual motor/prop dynamics and explicit brake/control-bus assumptions. | Fixed-voltage stock data cannot support battery exhaustion. OCV/resistance, LVC and BEC/thermal modules need separate admission. |
| Turbine, sampled/RK spool | Input limitation first; flameout after AV's stop/ECU transient is accepted. | Finite fuel, hot shutdown/cooling and installation-specific relight depend on AV. A fault is not `throttle=0` with idle thrust forever. |

Do not reuse an existing collision prop-strike flag as a generic engine failure: it carries different visual and physical meaning. If a new fault causes a later prop strike, preserve both causes in order and apply terminal/contact rules once.

### 9.2 Receiver abstraction

Use a small deterministic receiver state machine: `linked → signal_missing → failsafe_active → reacquiring → linked`, with a distinct `unpowered/rebooting` route. Timings, hold/preset values, output behavior without power and recovery conditions belong to an identified profile or a clearly named training surrogate.

Radio loss stops modeled command delivery while real sticks remain readable for recovery and diagnostics. A failsafe throttle preset means a received output; the attached ESC or turbine ECU interprets it. Do not skip directly from “radio lost” to “zero thrust” for every powertrain. Signal loss and an independent fuel/ignition kill are only coupled if their wiring says so.

Full receiver-battery/BEC dynamics are not required to implement a labeled injected signal outage. They **are** required before claiming that voltage/current caused a brownout. A scripted unavailable-power interval can be a training surrogate if that scope is explicit. Do not expose invented signal-strength measurements or imply a USB radio's simulated connection is the real RF link.

## 10. Wing separation and continued damaged flight

This is a required planned feature, with its own later release gate. It cannot be implemented by hiding a wing and adding a roll impulse. EM owns selecting/recording the training incident; CR-11…15 and physics/AS own the reusable damaged-flight mechanics. It must remain possible to apply the same supported separation type to all conventional airplanes, including those unlikely to recover.

### 10.1 Minimum supported topology

An aircraft damage section needs a stable ID, membership of mass inventory, physical span/area distribution, attached control surfaces/actuators, relevant propulsion/gear attachments, aero elements, mesh pieces and collision geometry. Use generated model/section bindings. A postcrash visual section map may assist authoring, but its names and mass approximations alone do not qualify in-flight separation.

Separate injection from causal strength prediction. The first exercise says a specified panel separates at a resolved tick. It need not invent a universal breaking G limit. Later overload/fatigue/flutter prediction requires evidence for spars, joints, constraints and dynamic loads; material texture or a video does not provide a strength model.

### 10.2 Required physical changes

- Remove the detached inventory contribution and derive remaining mass, CG and full inertia tensor, including off-diagonal terms. Combine correctly with any finite-fuel mass state.
- Remove the detached aerodynamic elements and control authority. Rebuild or select a qualified asymmetric induced-flow model; a symmetric intact-wing matrix with half its outputs set to zero is not automatically valid.
- Update forces/moments about the remaining CG, local flow/downwash, wake interaction and surviving control arms. Keep coefficient reference conventions explicit; avoid accidental rescaling twice.
- Remove lost contacts/hull attachments and update the surviving geometry used by ground/scenery collision. No invisible wing may continue colliding or generating lift.
- Update rendering/audio from the committed physical event. Maintain stable `airplane`, `propeller` and surviving `*_hinge` names, with an explicit active-section mask.
- Keep the surviving airplane under the float64 solver. Detached visual debris can use the bounded CR presentation path only if it cannot feed physical forces back. If debris collision affects the airplane, it needs a qualified simulation-side coupling.

### 10.3 Reference-frame and conservation checks

For an initial no-fracture-impulse approximation, surviving material points retain continuous world position and velocity at separation. If the new CG offset from the old CG is `Δr` in body coordinates, its world position becomes `x_old + R·Δr`, and its body velocity becomes `v_old + ω × Δr`. Angular velocity initially remains the same under that approximation. This coordinate change must not move the actual mesh through the world.

Compute the detached part's initial velocity from the same pre-event rigid-body velocity field, including `ω × r`. Test total linear/angular momentum of retained plus detached bodies about a common inertial reference at the event. If a fracture impulse is later modeled, apply equal/opposite impulse and angular effects with explicit energy assumptions. Do not conserve the intact body's angular momentum on the surviving airplane alone after discarding the detached mass.

Test positive, physically admissible inertia and finite loads before accepting the transaction. Invalid damaged topology is an implementation/configuration error, not a miraculous pilot rescue or arbitrary terminal explosion. The frame concerns are motivated by [NASA's damaged-asymmetric-body work](https://ntrs.nasa.gov/citations/20070030307); the implementation must derive and verify its own coordinates.

### 10.4 Recovery and presentation

Do not switch instantly to a postcrash camera merely because a wing is lost. The player retains available commands until the real contact/terminal condition. A damaged airplane may descend, roll, enter a spin or occasionally remain controllable. Outcomes should arise from the model and initial conditions.

High-angle-of-attack, knife-edge and propwash-dominated recovery on 3D airplanes require a qualified side-force/tail/propulsion envelope. Existing generic post-stall behavior is not sufficient evidence. No hidden lift multiplier, automatic stabilizer, rescued inertia or guaranteed hover is allowed. When outside the validated envelope, show that limitation in the briefing/debrief, not a falsely precise recovery grade.

Qualification matrix: left/right outer panel, left/right full panel, trainer/aerobatic/warbird/jet/electric families, multiple onset attitudes/speeds/power states, finite fuel variants and ground approaches. Publish recoverability as observed for a named setup, not as a global list of “planes that survive losing a wing.”

## 11. Useful and enjoyable practice

Random failures enrich normal flying; named lessons make them learnable. First deliver the random modifier and a short debrief. Add the following exercise cards incrementally after their mechanism gates:

| Exercise | Scenario | Feedback worth showing |
| --- | --- | --- |
| **Bring it home / Tráelo de vuelta** | Power loss from a qualified airborne start. | Recognition, airspeed trend, landing-area choice, energy and approach control. |
| **Rudder day / Hoy toca timón** | Both aileron commands held near trim on a qualified airplane. | Actual rudder/bank response and remaining reserve; no artificial mixing. |
| **One side working / Solo queda uno** | One aileron jammed. | Asymmetric authority, workload and saturation; compare both sides. |
| **Find the trim / Encuentra el trim** | Bounded initial roll/pitch/yaw offset on responsive surfaces. | Stable correction and remaining control travel; discriminate drift from a mechanical jam. |
| **No go-around / Sin segunda aproximación** | Power limit or deadstick. | Whether the chosen path was feasible; no reward for stretching the glide into a stall. |
| **Throttle will not close / No baja de vueltas** | Stuck demand/linkage with truthful independent-cutoff and energy setup. | Excess-energy management, cutoff reasoning, actual fuel/charge used and final approach. |
| **Half the elevator / Media profundidad** | Independent elevator-half jam. | Pitch margin, asymmetric loads and control strategy; only supported hardware. |
| **Listen first / Escucha primero** | Hidden notice and intermittent power. | What symptoms were observable before diagnosis. Audio is a cue, not an exact cause detector. |
| **Failsafe workshop / Prueba de failsafe** | Compare two receiver profiles under the same recorded signal loss. | Output behavior and trajectory differences; neither profile gets a fictitious autopilot. |
| **Last chance / Última oportunidad** | Catastrophic wing separation in a named setup. | Control retained, energy/attitude history and eventual outcome, including unavoidable loss. |
| **Preflight saves the model / Se detecta en tierra** | Reversed channel or severe setup offset before takeoff. | Correctly aborting the launch counts as success. |
| **Same incident, different airplane** | Same mechanism policy applied to two compatible airplanes. | Explain why control authority, inertia and energy make outcomes different. |

Make outcomes descriptive before adding scores: **controlled approach**, **landed and stopped**, **controlled off-runway arrival**, **control lost**, **attempt interrupted**, **outside qualified envelope**. Do not award a runway score where landing gear/contact is unsupported. A catastrophic attempt should not penalize the pilot for an outcome the model could not recover from.

Useful debrief observables include onset airspeed and terrain clearance, actual affected surface angle, commanded versus delivered throttle, response delay, sustained control saturation, minimum clearance, attitude/rates, touchdown speeds and location. Infer “recognition time” only from a declared player acknowledgement or a documented heuristic; the first stick movement is not proof of conscious recognition. Explain uncertainty in automated diagnosis.

Repeatable seeds and short challenges supply variety without progression locks, required accounts, timers pressuring unsafe choices, or unnecessary reward systems. Optional scenario sharing comes after versioned resolved records and compatibility checks; no online leaderboard is needed.

## 12. State, trace, replay and persistence

### 12.1 Resolved episode

A proposed `openrc-failure-scenario v1` record contains the player request, eligible-set digest, resolved occurrence/category/mechanism/target/parameters, source provenance, policy and definition versions, seed streams, onset rule/window, stop/recovery behavior, fallback branch if any, aircraft/model/field/environment identities and its own canonical digest. A healthy draw is explicit. Presentation preferences are distinct from physical episode identity.

NR's current scenario envelope is closed and mode-specific. Coordinate an explicit outer launch context or versioned extension that can carry ordinary-flight failure settings and, later, a combined NR/failure record. Preserve existing NR v1 validation and healthy replay; do not add unknown keys to its current dictionaries or reuse its mode label for a different flight. Reuse nested weather/lighting contracts and identity conventions rather than implementing duplicates. No ad-hoc fields in sealed `openrc-aircraft`, weather or visual checkpoint dictionaries.

### 12.2 Checkpoint content

Version the `FlightSession` checkpoint/identity to include all authoritative fault state: resolved record, activation status and tick, event cursor, captured jam/hold values, offsets, actual per-actuator state, delay buffers, interval index, receiver modes/timers, energy/lifecycle consequences, topology mask and committed history where necessary. Physics state cannot live only in an optional trace sidecar.

Validate before mutation: dimensions, enum/version, finite bounds, target references, dependency closure, source fingerprints and consistency with the embedded simulation state. A restore that fails must leave the current flight completely unchanged. Support older healthy checkpoints through an explicit migration/default-off rule when otherwise compatible; never silently discard unknown active-failure data. Match current native serialization and water/visual wrappers through their owners.

Save enough presentation state to avoid duplicate notices after restore, but never let hiding a toast change physical state. “Repeat same flight” and “resume this checkpoint” are different actions: one starts intact and replays onset, the other retains current damage and consumed energy.

### 12.3 Trace semantics

Add versioned failure metadata and a sparse companion event log, with a hash tying them together. Preserve existing CSV semantics until a deliberate trace-version change is required. Record initial state separately from interval/start/end samples and make onset convention explicit. Useful event fields are episode/event ID, cause, target IDs, scheduled and effective ticks, phase transition, requested versus effective parameters and interruption/rejection reason.

Telemetry needs pilot demand, receiver output, actuator target, actual surface positions, available versus delivered propulsion and relevant lifecycle/energy state. Consumers should never infer a jam from commanded stick values alone. Qualify a sparse event log plus selected additional trace fields before putting every dictionary into every 240 Hz sample. Missing log output must be visible to the user; it must not crash or alter the flight.

The same accepted start, resolved faults, input tape, environment and compatible build reproduce the numerical trajectory according to the repository's replay policy. A seed by itself does not reproduce a human pilot or cross-version floating-point behavior.

## 13. Verification and acceptance

Use the [canonical commands](../TOOLS.md), current per-owner tests and new defect-focused checks. This documentation-only change does not run or claim the future application tests. Re-record golden flights only for an intentional explained physical change; an opt-out feature must preserve healthy baselines.

| Gate | Required evidence |
| --- | --- |
| **G0 — Off is unchanged** | p=0 leaves complete healthy state/load traces identical on the same platform/build/input. No fault RNG advancement, hidden offsets, new energy drain or altered trim. Preserve current natural exhaustion and contact behavior. |
| **G1 — Probability is truthful** | Exact 0/100 boundaries; every integer 0…100 validated; deterministic distribution sweep with independent occurrence/category tests and confidence intervals. Interrupted flights reported separately. No FPS/pause/HUD dependence. |
| **G2 — Mechanism correctness** | Jam captures actual position; channel hold differs from jam; bias saturates; power loss enters the right family; left/right signs and independent controls verified. No nonexistent component is selected. |
| **G3 — Transaction and replay** | Inject before a deliberately rejected RK/contact/continuous-state tick on a disposable fixture: fault state, RNG, ledger and notices all roll back. Restore before/at/after onset, during dropout and after recovery. No duplicate event, stale topology or changed repeat. |
| **G4 — Fleet and lifecycle** | Catalog-driven compatibility matrix for every current configuration; both aileron sides; healthy and faulted starts, pause, reset, reselect, Workshop trial, failed launch and export. Unavailable cases have actionable reasons. |
| **G5 — Numerics and physical scope** | Finite states, physical inertia and dissipation/conservation checks; event-aligned timestep refinement; family-specific energy balances; qualified actuator/engine transients. Evidence labels distinguish analytic tests, estimates and measurements. |
| **G6 — Pilot usefulness** | RC pilot trials with bounded ordinary severity and visible versus hidden notices; workload, symptom clarity, repeatability and recovery options. Recovery is not inferred from finite telemetry alone. |
| **G7 — Presentation and delivery** | EN/ES, 720p/1080p and UI scale/focus/cancel tests; actual affected hinge and motor sound agree with telemetry; no surprise camera changes; source and exported routes agree. |
| **G8 — Structural extension** | Remaining-body/debris conservation, CG-frame continuity, asymmetric aero/contact validity and per-aircraft high-angle limits. CR/AS owner acceptance; unrelated damage gates stay open. |

### Specific test cases that catch likely defects

1. Run the same physical input/fault tape at different rendered frame rates and with notices on/off. Compare all authoritative state, not only final position.
2. Compare p=0 with the unmodified reference path, including each propulsion family, turbulence, ground contact and trim settings. Any no-op drift is investigated before acceptance.
3. Freeze the left actuator while commanding right roll and then left roll; right actuator still moves. Repeat mirrored, with asymmetric aileron throws and nonzero trim. Verify forces and rendered hinges.
4. A single linked elevator servo excludes `elevator.single_hold`; two independent ones admit it. Renamed/permuted model nodes do not change target selection when stable IDs are unchanged.
5. Jam an elevator and vary electronic trim. The command changes but the jammed surface does not. A responsive biased elevator can be retrimmed only within its remaining stops.
6. Drop receiver signal with two different failsafe profiles; interrupt receiver power separately. Verify observed outputs and correct ECU interpretation, including reacquisition without instant actuator teleport.
7. Stuck throttle plus independent kill stops the eligible installation. The same physical jam with no independent kill does not. Finite fuel ends at the actual usable-empty event; prescribed fuel rejects exhaustion practice.
8. Engine-off must not preserve idle thrust, intact powered propwash or normal engine sound unless the identified transient actually permits it. Propeller drag/windmilling assumptions are explicit.
9. Restore a pending, active and completed episode; reject a corrupted target or mismatched source without changing the running flight. Old healthy checkpoint does not inherit a prior active failure.
10. End before onset, crash exactly on an event tick and contact a propeller after a power failure. Check deterministic precedence and complete cause history with no double crash or force application.
11. At p=100, exhaust every onset predicate/fallback branch in fixtures; exactly one compatible episode activates within the declared bound if flight continues. No “100% but silently skipped” path.
12. Damage a wing while rotating: intact and surviving material points are continuous through the event; remaining-plus-detached momentum balances; removed contacts cannot still strike scenery.

For the occurrence sweep, use a fixed reproducible seed corpus (for example 100,000 lightweight resolutions at representative p values, plus all boundary values), report binomial/Wilson uncertainty and predeclare tolerances. A 90% selector need not yield exactly 90,000 events in 100,000 samples. Keep this out of expensive real-world creation loops. Use a small named flight matrix for physical/capture tests.

### Performance and resource limits

Keep source loading, catalog validation, hashing and topology compilation outside the 240 Hz loop. Bound active episodes, causal effects, buffers and retained UI history. Measure added tick cost with no fault, armed scheduler, active jam, intermittent power and structural transitions. Preserve the project's **500 µs total physics budget** as a target-hardware gate; do not claim a new allowance from CI timing. Report p50/p95/max, event spikes and build/hardware identity. Test repeated Home → flight → End/Repeat cycles for stale state, nodes, subscriptions, audio players and memory growth.

## 14. Phased implementation

EM-00's research is delivered. The implementation checkpoint above records the playable portions of EM-01…11 and EM-17, including EM-02/05's glow/electric extension; unlisted work and physical/pilot acceptance remain pending. Each step should land as a small independently reviewable change with proof in its commit message. Split a row further if it cannot preserve a working app. Names and sizes are planning boundaries, not elapsed-time promises.

### Phase 0 — Contract and baseline

| ID | Work | Dependencies and proof/status |
| --- | --- | --- |
| **EM-00** | Research, current-tree audit, UX/probability decisions and track registration. | This plan and linked dated source review. **Documentation delivered.** Runtime scope is recorded in the implementation checkpoint above. |
| **EM-01** | Freeze supported use cases, define ordinary/catastrophic eligibility and baseline corpus. Coordinate EM/AS/CR/UI/AV/NITRO/NR responsibilities. | Capture healthy state identities and source limits for the complete catalog at the recorded baseline, including actual energy/actuator topology. No physical edits. |
| **EM-02** | Strict failure request/definition/resolved-record contracts; capability resolver with exclusion reasons. | Implemented for logical controls and normalized glow/electric propulsion: v2 profile binding, v1 replay, unknown-profile refusal and catalog exclusion reasons, now visible in Home/Pause availability details. G0/G4 and independent AS topology qualification remain open. [Source-loss evidence](../research/failure-mode/EM-05/README.md), [availability evidence](../research/failure-mode/EM-03a/README.md). |

### Phase 1 — Deterministic physical foundation

| ID | Work | Dependencies and proof/status |
| --- | --- | --- |
| **EM-03** | Shared per-actuator state and mapping with an exact healthy compatibility path. Start with existing logical topology, then generated left/right bindings in fixtures. | EM-03a provides the shared scalar/batch kernel, accepted-surface observation and independent-position software fixtures. Existing state layouts remain intact. Authored actuator topology, generated bindings and independent accepted state still require AS; no player-facing independent-side qualification yet. [Evidence](../research/failure-mode/EM-03a/README.md). |
| **EM-04** | Hold/jam, offset and rate/limit mechanisms, including ordinary jam capture/fallback policy. | EM-03; analytic/sign/limits and independent-side fixtures; actual-state jam proof and declared discrete timing. EM-13 owns the fleet's player-facing independent-side qualification. |
| **EM-05** | Family adapters for a minimal honest power failure/limitation. Deliver one family per substep. | Finite-glow combustion cut and electric-drive loss implemented through existing lifecycle/shaft dynamics, with accepted-tick rollback and replay checks. Source behavior, calibrated transients, target hardware and pilot recovery remain separate gates; turbine/legacy shutdown remains excluded. [Evidence](../research/failure-mode/EM-05/README.md). |
| **EM-06** | Episode runtime transaction and deterministic tick scheduling, with reset/rollback. | EM-04/05; forced rejected-tick tests, no stage RNG and event ordering proof. |
| **EM-07** | Complete versioned checkpoint/identity and sparse event recording. | EM-06; compatible old healthy restore, corrupt restore atomicity, before/on/after-event replay and trace semantics. |

Phase 1 exits with deterministic, developer-injected faults working through a real session. It does not yet claim a player-facing random mode. Healthy aircraft and ordinary menus continue to work.

### Phase 2 — First playable random mode

| ID | Work | Dependencies and proof/status |
| --- | --- | --- |
| **EM-08** | Seeded per-flight selector, category/family weighting, onset profiles and resolved fallback branch. | EM-02/06/07; G1 distribution report, p=100 bounded activation, end-before-onset accounting, independent RNG streams. |
| **EM-09** | Home configuration screen, explicit launch-mode/modifier distinction and preferences migration. | EM-08 + UI/NR owners; preserve current NR request/identity checks and ordinary routes, candidate launch failure restores state, Apply/Cancel and keyboard/radio isolation. |
| **EM-10** | Notice checkbox, nonmodal overlay, hidden mode and concise postflight explanation. | EM-07/09 + HUD/AUD/CR owners; actual committed state drives copy/sound; notices do not change trajectory; EN/ES/focus/capture proof. |
| **EM-11** | Repeat same flight versus new draw, pause-setting scope, CLI/direct-route opt-in and lifecycle/export checks. | EM-09/10; repeated cycles, trace-save failures, no interactive preference use in existing automation. CLI spelling chosen through main's parser owner. |
| **EM-12** | Qualify a bounded ordinary pool across the complete current conventional fleet; release the initial mode with its feature matrix. | EM-03…11; G0…G7 with pilot review and target hardware. Explicitly list split-elevator, finite-energy and structural cases still unavailable. |

The first playable release must include a meaningful control failure and a meaningful power-related episode where supported, plus adjustable probability and notices. Do not claim a turbine flameout if only a throttle limit is implemented. Catastrophe control is shown disabled with a plain explanation until at least one catastrophic mechanism passes its gate; it must not be a working-looking no-op checkbox.

### Phase 3 — Requested realism and emergency lessons

| ID | Work | Dependencies and proof/status |
| --- | --- | --- |
| **EM-13** | Complete independent single/both aileron and rudder cases; per-aircraft ordinary envelopes and trim controls. | AS/EM-03/04 + input owner; mirrored flight/pose evidence, rudder-only recovery assessment, trim/jam discrimination. |
| **EM-14** | Independent elevator halves and symmetric baseline parity. | AS topology + Aero/tail owner; no halving of pitch derivative without local-load evidence; single-servo configurations excluded truthfully. |
| **EM-15** | Reduced/intermittent/slow power by family and turbine-off through accepted AV lifecycle. | EM-05 + AV/NITRO/EL; finite traces and measured/estimated transient labels, restart/cutoff distinctions. |
| **EM-16** | Stuck-high throttle and finite-energy waiting/landing exercise, beginning with supported finite-glow configurations. | EM-15 + energy/kill contracts; actual fuel/current progression, cutoff precedence, exhaustion/replay and controllability proof. |
| **EM-17** | Modeled receiver link loss, hold/preset profiles and recovery; enable catastrophic admission. | EM-06/07 + input/propulsion owners; signal loss never invokes app/device disconnect; timing/profile and control-recovery evidence. |
| **EM-18** | Receiver power interruption/brownout and BEC dependencies, initially explicit surrogate intervals if needed. | EM-17 + qualified electrical model for causal voltage claims; current/power/reboot evidence, no unsupported failsafe during outage. |
| **EM-19** | Named training cards, optional hints and richer debrief; repeat from accepted pre-event checkpoint only after lifecycle support. | Accepted mechanism steps; pilot learning/readability trials and honest outcomes. No scoring based on unavailable gear or measured recognition. |

Phase 3 covers the requested recoverable examples as far as the aircraft's actual hardware permits. A delivery report maps every requested example to an accepted mechanism or a named unresolved physical dependency; nothing disappears into an unspecified backlog.

### Phase 4 — Structural catastrophe on any supported airplane

| ID | Work | Dependencies and proof/status |
| --- | --- | --- |
| **EM-20** | Author/generate structural section contract and in-flight damage adapter with AS/CR; choose injected-separation scope. | AS section/mass bindings and CR-11…15 coordination. Closed member/reference validation; intact equivalence; no mesh-name heuristic. |
| **EM-21** | Atomic separation with remaining/debris mass properties and state-reference conversion. | EM-20 + physics mass owner; analytic two-body conservation, tensor validity, world-point continuity and rollback/checkpoint proof. |
| **EM-22** | Asymmetric wing/tail aerodynamic and surviving-contact response. | EM-21 + Aero/GP/CR; independent damaged-aero checks, timestep/domain tests, no invisible lift/collision, high-angle limits identified. |
| **EM-23** | Render detach/retained controls, damage-aware audio/HUD/camera and eventual crash handoff. | EM-21/22 + model/CR/CAM/AUD/HUD owners; same event tick, bounded debris/performance, reset/restore returns the exact physical topology. |
| **EM-24** | Full/partial wing-separation exercises and fleet qualification, including possible 3D recovery experiments. | EM-20…23; G8 and pilot trials across every supported airplane, both sides, survivable and unrecoverable examples, explicit unvalidated regimes. |

Do not delay useful nonstructural training while this work is pending. Conversely, do not close wing-loss planning by presenting postcrash breakup as its implementation. The user-requested arbitrary-airplane applicability remains an explicit Phase 4 acceptance requirement.

### Phase 5 — Expansion, combined scenarios and handover

| ID | Work | Dependencies and proof/status |
| --- | --- | --- |
| **EM-25** | Additional mechanisms: LVC/thermal/feed, flaps/gear/assist/multiengine as their owning capabilities become available. | Each owner's law/state/qualification gate; one mechanism per substep, no generic claims from unsupported hardware. |
| **EM-26** | Explicit multiple-failure/cascade policy and optional Natural Random combination. | EM/NR owners; bounded effects, causal priority/conflict rules, workload qualification, independent environment RNG and accurate briefing. |
| **EM-27** | Resolved-scenario sharing, compatibility diagnostics and third-party/Workshop onboarding conformance. | Versioned packages/identities, missing-content errors, generated-source checks; no silent replacement of aircraft or faults. |
| **EM-28** | Release acceptance, operating guide and plan consolidation. | All chosen release gates, clean-clone/export checks, request-to-delivery matrix and remaining limitations. Move operating instructions to the canonical guide, preserve evidence, then remove completed plan portions per repository policy. |

### Reviewable delivery order

```text
EM-01 → EM-02 → EM-03/04 and family-specific EM-05
                       → EM-06 → EM-07 → EM-08
                       → EM-09 → EM-10 → EM-11 → EM-12

EM-13…19 extend the accepted framework with real subsystem support.
EM-20…24 depend on CR/AS/physics damaged-flight foundations.
EM-25…28 add qualified capabilities and consolidate delivered work.
```

Use separate PRs/commits for contracts, healthy actuator parity, each physical mechanism, scheduler, lifecycle/recording, and UI. A developer can review each without accepting the entire long-term damaged-flight model. If agents work in parallel, give them distinct owned files and use the repository's requested Luna Max model; shared integration files have one integrator at a time.

## 15. Risks, dependencies and decisions to keep visible

| Risk | Mitigation / release blocker |
| --- | --- |
| 100% becomes “maybe, eventually” through filters | Freeze compatible episodes and bounded onset/fallback; verify continued-flight activation and interruption accounting. |
| General failures are accidentally lethal by default | Qualify magnitude, jam capture and actual available authority per configuration; severe variants move to catastrophe/advanced. No guarantee against pilot-created bad states. |
| A render change masquerades as a physical failure | Verify actual forces, mass, actuator state and contacts independently of mesh appearance. |
| Current trim cancels the scenario | Apply scenario offsets after normal start; record base/pilot/fault components separately. |
| Source data or normal preferences get contaminated | Immutable source, detached launch request, migration tests, reset/aircraft-swap and failed-launch recovery. |
| Fault timeline advances on rejected ticks | Explicit prepare/commit/rollback state and one commit boundary for every observer. |
| Finite-energy gameplay is added to prescribed-fuel models | Capability rejection plus owning AV/NITRO/EL extension; no fake empty-tank timer. |
| Existing crash damage is mistaken for flyable damage | EM-20…24/CR gate remains separate with physical evidence. |
| Unqualified “3D survives” behavior teaches the wrong lesson | No rescue forces; publish high-angle model limits and aircraft-specific outcomes, including loss. |
| Two scenario or actuator frameworks grow in parallel | Reuse NR launch-envelope and AS control topology when accepted; record one shared interface decision. |
| Long task overwhelms the current release | Ship bounded Phase 2 and Phase 3 slices; keep structural expansion independently gated and its requirement explicit. |

Default scope excludes persistent wear across sessions, real RF propagation/interference spectra, structural flutter, arbitrary free-floating linkage physics, multiplayer instructor transport and certification claims. These are separate models/features, not missing checkbox wiring.

## 16. Completion checklist for the requested feature

- [ ] 0–100 probability has exact per-flight semantics and a clear 100% activation/interruption rule.
- [ ] Catastrophic admission and onset notices are independent checkboxes with truthful behavior.
- [ ] Single/both aileron, rudder, supported split-elevator, offset/trim and slow/restricted-control cases operate through actual physical surfaces.
- [ ] Engine/electric/turbine-off and weak/slow/intermittent power use supported family mechanisms.
- [ ] Stuck-high throttle includes an honest finite-energy/independent-kill exercise.
- [ ] Radio failure is modeled independently of application focus and real device loss.
- [ ] Wing separation is usable through the same damage interface across supported airplanes, without a survival guarantee or a 3D-only gate.
- [ ] New airplanes enter through standard capabilities and authoring/qualification, not per-aircraft solver edits.
- [ ] Home/pause/launch, preferences, EN/ES, HUD/audio, debrief and repeat/new-flight flows are complete.
- [ ] Whole-tick rollback, reset/checkpoint/replay and trace identities include every authoritative fault state.
- [ ] Healthy baselines, physical/numerical checks, fleet qualification, pilot usefulness and packaged delivery have separate evidence.
- [ ] Accepted behavior is documented in the canonical operating guide; dated sources and evidence remain under `docs/research/`.

The next physical extension is the authored AS/EM actuator-to-surface topology and independent accepted state (EM-03b/13). EM-03a supplies the kernel and surface observation; it does not infer which aircraft have separate servos. Independent elevator halves additionally need local tail loads (EM-14). Turbine shutdown remains owned by AV; structural separation remains EM-20…24 with CR/AS.
