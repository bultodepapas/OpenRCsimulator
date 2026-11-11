# FPV engineering contracts

**Status:** proposed implementation specification; names and layout version must be accepted in DR-16a before runtime adoption. **Baseline:** `7bff78490f9af5c1664f47c8ba865a92b3430920`. Existing APIs and their limitations are linked in [06](06_SOURCE_AUDIT_AND_EVIDENCE.md); flight mathematics is in [03](03_FLIGHT_DYNAMICS_AND_RESEARCH.md).

## 1. Invariants

1. One session installs one `VehicleModel` into the existing `Simulation`. No `if multirotor` branch, controller callback special case or racing rule enters the generic kernel.
2. Body, controller, actuator, battery and authoritative race state use scalar float64 / packed float64 arrays, plus the existing discrete-state representation. World is NED; body is FRD. Renderer transforms never become physics input.
3. A model's stage evaluation is a pure function of its arguments and immutable prepared definitions. It cannot advance PID filters, consume an input event, increment a race timer, mutate RNG state, write a recorder row or change an owner cache.
4. A failed candidate preserves the complete last accepted physical/controller/race frame and command-consumption position. The kernel may set its documented sticky fault and pause. Those diagnostic changes are not physical advancement.
5. Reset and restore are prepared and validated against the complete candidate context. A previous flight's commands, camera pose or race state cannot participate accidentally.
6. Exactly one fixed-tick driver owns a session. Manual/headless callers guard pause/hold themselves: the current `Simulation.step()` does not do so.
7. Same-build/platform exact replay is a stated, tested contract. Cross-platform numerical equivalence is tested separately, never assumed.

## 2. Pure sampled feedback and stage context — DR-16a

### Current problem

The current `pre_tick(aux, inputs, dt)` has no body/continuous/mode feedback. The current `stage(body, continuous, t)` has no sampled command argument. `Plant.pre_tick()` therefore writes `Plant.duties`, and `Plant.stage()` reads that mutable field. Kernel rollback does not restore the object field. The existing test primes it before reset. The isolated reproduction and raw result in [06](06_SOURCE_AUDIT_AND_EVIDENCE.md) establish why a new controller must not inherit that authority.

### Proposed opt-in protocol

Add a generic explicit protocol selector with legacy as the default. The illustrative names below are not current APIs:

```text
callback_protocol = "legacy" | "framed-sampled-v1"

sample_tick(previous_frame, input_snapshot, clock)
    -> {aux: float64[], modes: discrete[]}

stage_sampled(body, continuous, stage_time_s, sampled_context)
    -> {loads: float64[6], derivative: float64[continuous_size],
        rotor_momentum: float64[3],
        optional body_derivative: float64[13],
        optional stage_context: Dictionary}

previous_frame = {body, continuous, aux, modes}
clock = {tick, time_s, dt}
sampled_context = {aux, modes, sample_tick, sample_time_s}
```

`sample_tick` receives the detached **accepted** frame at `t_k`, the validated input snapshot for interval `[t_k,t_(k+1)]`, and the fixed clock. It returns only candidate sampled/discrete arrays. It cannot change body or continuous state. Model validation enforces declared lengths, finite values, enum domains and protocol-compatible callbacks before a flight can start.

The explicit protocol selector determines which callback family is active. Do not infer it from the presence of the legacy default no-op `pre_tick`, which is already a valid callable. For the new protocol, reject an actively selected legacy joint/split stage route and define how inactive default fields are treated. Existing models keep the exact historical dispatch; optional new fields enter model identity/guard validation only as appropriate. Pin the protocol and layout in the checkpoint envelope.

`sampled_context` is the **same candidate control sample** for k1–k4, plant substeps, event bracketing and whole-tick policy evaluations. The PID is not resampled inside the tick. The joint evaluator combines its held command with the event-addressable terminal cut latch specified in §7; that latch can disable drive for later subintervals without changing the held controller sample. At reset the context is built from the prepared initial frame; at restore it is built from the restored accepted frame. Every route that calls `_stage_loads` or a derivative must dispatch through the same protocol adapter. A special fix only in the main `step()` path leaves reset and policy stages broken.

The implementation checklist includes `VehicleModel.uses_joint_stage()`, callback validation and `substeps_joint` admission, `Simulation._configuration_is_valid()`, `_stage_loads()`, both direct joint-stage call sites, continuous-size checks, reset/restore and guarded-field capture. At the baseline several predicates inspect `model.stage.is_valid()` directly; adding only `stage_sampled` would otherwise misclassify the model or dispatch to a legacy split/default path.

Keep endpoint callbacks and their current semantics. The new sample transition happens before integration; the existing endpoint transition happens after integration/filtering and before final projection/validation/publication. Both are pure. Do not use endpoint evaluation to apply arming one interval late.

### Guard and compatibility obligations

| Boundary | Required behavior |
| --- | --- |
| Model installation | Validate protocol, active callback family, explicit sizes and bounded layout identity; reject malformed combinations before replacing the accepted model. |
| Sample callback | Detached arguments, no aliases into live arrays; guard the explicitly registered previous/input/clock, prepared value-only configuration and new callback fields; reject reentry. |
| Stage callback | Detached/guarded sampled data; no owner cache is authoritative. Validate every stage result, including trial/refinement stages. |
| Reset preparation | Evaluate candidate loads using candidate continuous/aux/modes; no live sampler advance or input consumption. Failed preparation preserves old activity and recording. |
| Commit reset | Keep the existing accepted-commit/observer-fault distinction. Observer failure after commit pauses the new accepted session; it is not described as rollback. |
| Restore | Validate identities, sizes, domain, modes, schedule and source/race envelope before replacement; reconstruct all stage context from restored state. |
| Legacy dispatch | Unchanged callback counts/order, accepted trajectories, v1/v2 checkpoint behavior and notifications for all unmodified models. |

Start with correctness and explicit copies/guards. Optimize copying or allocation only after profiling and after mutation/alias tests prove equivalent isolation. GDScript arrays and dictionaries are not made immutable merely by calling a parameter read-only in a comment.

The guard is a finite contract, not a sandbox: current guards compare enumerated kernel/model state and object/callable identity, and cannot generally discover arbitrary mutation of a captured object or global. Register any session/environment participant whose state can affect simulation, retain a detached value-only snapshot/fingerprint with a defined restore operation, and prohibit other authoritative mutable closure state. Test representative mutation/reentry failures. Do not claim every external side effect is automatically detected or rolled back.

### Full-frame reset preparation

The current `prepare_reset(initial_body)` reads aux/modes/continuous/inputs from live `Simulation` fields. Changing stage dispatch alone does not make it a detached full-frame preparation. Add an opt-in `prepare_reset_frame(candidate_frame, candidate_inputs)` for the already installed immutable model/configuration, returning an owner-sealed candidate with its full layout, initial clock, evaluated loads and configuration identity. Preparation runs no input sampler, changes no accepted arrays and emits nothing. A matching commit validates the same owner and unchanged configuration, then publishes all candidate arrays together. Preserve the historical reset API for legacy models.

A different model/configuration is prepared in a separate session/Simulation owner and swapped through the activity's accepted replacement transaction, preserving old recording/observer ownership on rejection. Do not pass a prepared candidate between owners: current reset seals are owner-specific. A failed candidate with malformed rotor, aux, mode, input or pack data must leave the old flight and recorder intact. Restore remains a full-envelope operation against its matching model and clock, not a tick-zero reset approximation.

## 3. Tick ordering

The proposed 240 Hz path has one control sample per accepted outer tick. A request that fails may be evaluated again, but it never consumes committed state twice.

```text
0. Session checks hold/pause/fault and availability of bounded input/record space.
1. Reserve a detached pilot/action sample; do not consume the accepted cursor.
2. Validate accepted frame, input sample, model/configuration and fixed clock.
3. sample_tick:
   a. resolve source/arm/mode boundary;
   b. update any fixed-tick throttle policy;
   c. apply exactly one rates mapping;
   d. sample gyro/attitude and update declared digital filters;
   e. compute torque request, bounded allocation and held motor commands;
   f. calculate next integrator/filter memory with declared anti-windup order.
4. Build one candidate sampled_context; integrate body/rotors/pack jointly.
5. Complete the compatible event/contact policy; retain accepted path only.
6. Apply existing filter contract, then composed physical/race endpoint transition.
7. Project sampled telemetry without overwriting controller/race memory;
   validate the entire candidate and all state/identity invariants.
8. Commit frame, tick, checkpointed command cursor and accepted event list together.
9. Notify read-only recorder/presentation observers; reclaim consumed tape storage.
```

For the reference PID order, `tau_req,k` uses `I_k`, allocation produces held `u_k`, and the anti-windup calculation produces `I_(k+1)` stored with `u_k`. Derivative is on the declared filtered gyro measurement. The stage reads `u_k`; it does not recompute the PID from `I_(k+1)`. See the equations and distinctions between requested, allocated and produced torque in [03](03_FLIGHT_DYNAMICS_AND_RESEARCH.md).

New connection/source generation invalidates old arm-edge evidence. An action reservation is immutable until the candidate commits or fails. The authoritative accepted command/action cursor and source generation are in checkpointed aux/modes; the virtual-throttle accumulator is also checkpointed. Reclaiming a consumed immutable tape prefix after notification changes storage only. Kernel observers already see the new cursor. A failed attempt leaves the prior cursor and reservation unconsumed. Hardware samples cannot be undone; the recorded accepted logical tape, source generation and explicit recovery policy define subsequent behavior.

Holds do not call the sample transition and do not advance any integrator, delayed-input history, virtual throttle, battery, environmental sample index or race clock. Readiness polling during a hold uses the existing non-integrating mode. Reconnection is device evidence, not automatic motor rearming.

## 4. Proposed state layout and identities

Freeze offsets in a generated/constant layout descriptor when DR-16a/10 is accepted. These layouts are **proposed ABI content**, not files the current loader already accepts.

### Physical state

| Block | Initial law contents | Notes |
| --- | --- | --- |
| Body | Existing 13 float64 values | Existing position, body velocity, body-to-NED attitude and body rates; preserve ordering. |
| Lab continuous | Four relative rotor speeds, rad/s | Keep the historical raw-duty law/identity as its own fixture. The new controlled fixture has a distinct protocol/layout identity. |
| Product continuous, EL baseline | Rotor speeds 0–3; remaining charge `Q_C` at 4; terminal-energy integral `E_terminal_J` at 5; pack electrical-loss integral `E_pack_loss_J` at 6 | `SOC=Q_C/(3600 capacity_Ah)`; `Qdot=-I_pack`; energy derivatives are stage-local. Discharge changes energy, not modeled aircraft mass. |
| Product hybrid-event slot | `terminal_cut_latch` at 7 for the EL baseline | Exactly 0 or 1, zero derivative; an accepted terminal event changes it 0→1 inside the event policy. Only a qualified prepared reset clears it. This is a proposed SF-reviewed use of the event-addressable combined block; see §7. |
| Rich BAT alternative | Four shafts plus the one selected pack's declared state block | Current BAT includes charge, energy/loss, polarization, temperature and supervisor state. Its layout, limits and first-flight scope require separate acceptance; never allocate one full pack per shaft. |

Use a model identity for every changed physical law. A first-order command-to-speed law and an electromechanical shaft law are not interchangeable just because both expose four RPM values.

### Controller/sample block

A minimal explicit controller descriptor can reserve the following 31 float64 values before any optional race suffix:

| Proposed offsets | Meaning | Units/initialization |
| --- | --- | --- |
| 0–2 | PID integral contribution | N·m; initialize to zero |
| 3–5 | Filtered gyro memory | rad/s; initialize from prepared body rate |
| 6–8 | Filtered measurement derivative memory | rad/s²; initialize zero unless a validated restored value exists |
| 9–11 | Previous rate setpoint for optional feed-forward | rad/s; initialize consistently with the selected initial mode |
| 12–15 | Actuator commands allocated by the last accepted control sample | Law-defined normalized command, retained unchanged through that interval's endpoint for recording; a disarmed sample allocates zero. Effective stage drive additionally applies the event cut latch and pack/start policy. |
| 16–18 | Requested body moments for the accepted control sample | N·m; telemetry/anti-windup evidence |
| 19–21 | Allocated predicted body moments | N·m; static command prediction, not measured produced torque |
| 22–24 | Rate setpoint | rad/s |
| 25 | Collective command after the declared throttle policy | [0,1] |
| 26–29 | Allocated rotor thrust targets | N; baseline allocation diagnostics |
| 30 | Virtual throttle accumulator | [0,1], used only by a selected rate/incremental throttle policy |

If optional FF, sensor noise, delayed inputs or different filters require more memory, declare a different layout/version with explicit state. Never hide that memory in a node, static variable, closure or external mutable queue. Derived values can be removed from this proposed sample block if the final ABI provides the same accepted-sample telemetry elsewhere without hidden authority; record the accepted layout once, not as runtime magic offsets.

Discrete state contains motor lifecycle, flight mode, previous arm level, OFF-observed latch, accepted source generation, filter-initialization state, any accepted input/action cursor, and an arm-block reason enum. Use bounded integer domains. Distinguish `flight_mode` (Acro/Angle) from `motor_state` (disarmed/armed/crashed/depleted/failsafe exercise). Race-only fields are a suffix admitted by a separate layout.

### Pilot sample contract

Define a small immutable `PilotFrame` before flattening to the kernel's declared input array. It contains:

- logical roll/pitch/yaw signals in [-1,1], with the pitch sign convention explicitly converted once;
- throttle signal and a **pinned** absolute-versus-rate interpretation;
- arm level/explicit action, requested flight mode, source readiness and connection generation;
- integer sample/action sequence, target simulation tick and any deliberately enabled exercise event.

All numbers, integer-like fields, enum values, lengths and chronology are validated. Identity fixes the flattening order and `input_size`. Live radio/gamepad, keyboard and recorded tape use the same logical contract. Do not flatten an untyped dictionary opportunistically or silently accept a different channel order. Absolute throttle is [0,1]; a centered rate-throttle source can be [-1,1] only under its explicitly identified policy. A proposed calibration/rates importer must never reinterpret one as the other.

### Session envelope

The checkpoint is a versioned binary-preserving container around the kernel frame plus:

| Identity/state | Why it matters |
| --- | --- |
| Repository/build, engine, solver/backend and model-law identity | Prevent a same-name but changed implementation from being called exact replay. |
| Data/schema/generator/configuration hash | Distinguish physical builds, normalized parameter versions and source handling. |
| Controller/rates/profile/filter/sample schedule | Pin the complete command-to-actuator path, including semantics and units. |
| Environment provider/configuration and any sampled/RNG state | Resume the same physical wind/atmosphere sequence at the same clock. |
| Field/collision world/track/rules and race layout | Prevent restoring a lap into changed gate or obstacle geometry. |
| Input policy, accepted source/action cursor, pending semantic actions and hold/rearm state | Preserve command ordering and recovery without pretending OS input can be rewound. |
| Kernel checkpoint, exact tick/time and initialized/terminal state | Restore the actual coupled accepted state, not just body pose and RPM. |
| Bounded pending-result outbox and acknowledged attempt IDs | Preserve terminal results across accepted reset/restore and retry file writes idempotently; memory alone is not durable storage. |

Visual assets/preferences have their own provenance/configuration identity but cannot invalidate physical identity unnecessarily. For a visual replay, retain relevant camera/presentation configuration separately. JSON/CSV are readable diagnostics; use the established exact checkpoint serialization for bitwise state.

## 5. Strict multirotor data — DR-10…13

Create proposed sibling `openrc-multirotor v1`. Reuse proven quantity/provenance helpers from `openrc-aircraft v2`; do not require wings, trim, control surfaces or fixed-wing start laws. Unknown keys and unsupported capabilities fail admission, with a useful field-path error.

| Required block | Minimum contents | Admission checks |
| --- | --- | --- |
| `identity` | Schema, family/variant, immutable source manifest, generator and physical-law IDs | Exact versions, bounded identifiers, matching hashes |
| `capabilities` | Multirotor, supported starts, modes, energy/contacts/replay/race support | No advertised capability without compatible modules/gates |
| `mass_inventory` | Components with mass, placement, orientation, component inertia and provenance | Sum mass/CG/full inertia; positive-definite total; no rotor inertia double count |
| `rotors[4]` | Stable IDs, hubs from CG, axis, spin, diameter, prop/model/source | Exactly four unique motors; normalized axes; supported geometry/spins; non-overlapping swept volumes |
| `aerodynamics` | Thrust/torque law, rotor/body drag, density convention and supported flow/RPM domain | Units, finite coefficients, passivity where appropriate, explicit extrapolation refusal/policy |
| `motors_esc` | Four motor identities/parameters, actuator mapping, loss/braking/limit/idle law | Matched voltage/prop configuration; no DShot-to-duty assumption; zero-drive disarm distinct from idle |
| `battery` | One pack, chemistry/cell configuration, capacity, charge/OCV/resistance and selected law | Positive feasible voltage, valid interpolation/domain, exactly one state block, cutoff/depletion convention |
| `controller` | Simulator controller version, gains, filter/sample timing, allocator and limits | SI units, stable declared filters, bounded outputs, no above-Nyquist imported settings |
| `collision_supports` | Pads/contact points, hull, four rotor envelopes and support material law | Correct origin/scale, solved pad equilibrium, consistent CG and qualified geometry |
| `camera` | Mount offset/orientation and declared default tilt/FOV/aspect | Rigid mount from CG; distinguish an estimate from camera calibration |
| `starts` | Qualified pad/heading/initial energy; optional explicit research-only hover | No airplane trim fallback or impossible hovering/start configuration |

Every physical quantity carries the existing `{value, unit, kind, source}` convention. The generator maintains a richer provenance/uncertainty ledger identifying measured, manufacturer-reported, borrowed, derived and estimated values. A quoted manufacturer's number is not a measurement performed by this project. Immutable data/asset source bytes and license decisions belong in the manifest, not just a link to a mutable web page.

Required derived checks include full 3D hub separation/prop clearance; prop/frame clearance; assembly mass/CG/inertia; positive-definite locked and effective inertia; per-motor force/moment signs; feasible collective authority and hover balance under the declared fresh-pack and low-charge conditions; valid idle/output range; correct motor/prop/pack voltage; and camera/hull/visual origin agreement. An arbitrary build can have unequal hover rotor forces: solve constrained force/moment equilibrium rather than using the symmetric closed form universally.

The illustrative minimum square-X diagonal formula does not apply to all stretched, dead-cat or vertically staggered layouts. Validate actual hub/rotor geometry and the supported physical law. Do not reject a potentially valid non-square aircraft solely by a wheelbase label, or admit one solely by a rendered model's nominal size.

### Authoring pipeline

```text
Immutable source evidence + measured/estimated tables + licensed CAD/mesh
  → versioned source manifest and explicit selected assembly
  → deterministic generator with unit/frame conversions and balance calculation
  → strict multirotor JSON + derived diagnostics + visual adapter metadata
  → loader validates and prepares an immutable runtime model
  → only a successful prepared model may replace the accepted session
```

The proposed command `research/drone-racing/<build>/derive.py --check` must compare regenerated bytes and provenance, never silently overwrite accepted output. A normal generation command writes explicit candidate outputs. Do not hand-edit generated physical JSON or hub positions in the GLB to compensate for a bad source conversion. Rates are a separate `openrc-rates v1` artifact; tracks/rules use separate identities and schemas.

## 6. Input and motor lifecycle — DR-14/15/18/20

| State/transition | Requirements and next behavior |
| --- | --- |
| Enter activity / reset | Prepared pad/body/rotor/pack/controller state; motor disarmed, arm latch cleared, zero drive. No held-high arm signal is a fresh request. |
| Ready to arm | Accepted source calibration/readiness, valid low throttle, OFF observed in current source generation, valid nonterminal configuration. |
| Fresh arm ON | At the sampled boundary, enter armed state; idle and Airmode become available under the selected motor law. If requirements fail, remain disarmed and expose a deterministic reason. |
| Arm OFF / explicit disarm | Zero drive from that sample independently of idle/Airmode. Residual angular speed evolves under the declared coast/brake law. |
| Pause / settings / focus or device loss | Session hold; no physical/control/pack/race/virtual-throttle advancement. Continue only non-integrating source recovery checks. |
| Resume / reconnect | While held, stage new source evidence and an explicit OFF→ON recovery request without physical advancement; explicit Continue submits it to the first resumed sample. See the recovery contract below. Never grant fresh motor authority from a previously held switch alone. |
| Crash / qualified rotor strike | Locate terminal event, apply the declared motor cut and aftermath behavior, invalidate affected race attempt, publish one accepted cause, require pad reset/rearm. |
| Exhausted pack | Apply the declared simultaneous electrical boundary; no current/drive after disconnection, rotors coast under the admitted domain. Reset/recharge is explicit. |
| Simulated failsafe-drop exercise | Deliberately selected feature with recorded event/timing; distinguish from actual host/device-loss hold policy. |

The low-throttle threshold, any switch debounce and mode-change behavior are versioned product parameters, not undisclosed magic constants. Acro release holds angular rate near zero, not attitude near level. Angle defines its limited-tilt domain and inverted/near-vertical behavior before implementation. Switching modes must not create an unintentional yaw request or a derivative kick; make the integral/filter reset or preservation policy explicit and test it.

Calibrated profiles can contain gamepad expo already. DR adds a pre-expo semantic path or an explicit opted-in conditioning mode while retaining calibration and appropriate deadzone behavior for other vehicles. Source-side transmitter expo cannot generally be reconstructed from HID values; surface it as a setup assumption. Keyboard/centered-gamepad throttle integration is fixed-tick and checkpointed. Input/API tests cannot substitute for one real-device acceptance run.

### Recovery without a hold/rearm deadlock

While held, the device reader performs non-integrating checks and builds one bounded immutable recovery proposal: current source generation, observed OFF sample, later fresh ON sample, low-throttle evidence and explicit Continue intent. It does not update the accepted FC or advance the physical clock. Record this proposal in the session envelope until consumed; replace it on source changes and discard stale/repeated recovery actions.

For an absolute radio throttle, require the actual calibrated position to be low. For a centered gamepad/keyboard rate-throttle profile, a frozen accumulator may be above zero. The recovery UI explicitly offers **Resume with throttle reset to zero** (or pad reset); the accepted accumulator is not changed while held. The proposal carries that zero-throttle override, and the first accepted resumed sample applies it atomically with arm validation before k1. Show the consequence for a midair hold. Cancel or a failed resumed tick preserves the old accepted state and unconsumed proposal.

The session first validates the recovery proposal without running the FC or stepping physics; an expected readiness refusal retains the hold. Explicit Continue then releases only the scheduling hold for that candidate attempt. The sampler rechecks the ordered evidence and configuration/source generation, applies its throttle override and fresh arm request, and commits them with the first resumed tick. An unexpected in-kernel mismatch refuses the tick under the sticky-fault/pause contract. Replay records the accepted recovery proposal on the logical tape. Test focus loss, unplug/replug, high arm switch, stale generation, midair recovery, cancellation, rate-throttle above zero and a failed first resumed tick.

Initialize the intended global `Input.use_accumulated_input` policy explicitly for a direct multirotor launch and define its shell/activity ownership and restoration. The fixed-wing route's current setting is not inherited reliably by a standalone drone route. Test direct launch, Home launch and airplane→drone→Home transitions on the pinned engine; measure device delivery rather than assuming the flag alone establishes latency.

## 7. Continuous events and contacts — DR-09b/18/19

The current generic event locator supports one declared zero boundary, and it can evaluate beyond zero while finding the root. The current multirotor product needs up to four rotor-stop boundaries, charge depletion and contact refinements. A law that rejects negative speed cannot be repaired by clamping only the accepted endpoint.

Choose one whole-tick policy for these coupled requirements. That policy owns its bounded subinterval selection, stages, domain-safe root locations, simultaneous-event batches and accepted-path receipt. The current kernel's `MAX_SUBSTEPS=16` is the legacy substep path; a custom policy cannot also request more than one kernel substep. Do not compose two independent step owners.

### Concrete event-local drive cut

The sampled commands stay frozen, but a terminal event must affect later stage evaluations. For the initial product law, propose an SF-reviewed `terminal_cut_latch` in the model's event-addressable combined state: a zero-derivative scalar constrained to exactly 0 or 1. Its initial value is 0. Stage drive is enabled only when the sampled motor-arm/race-start policy authorizes it, the latch is 0, and the pack branch is available. The richer BAT layout adds this one latch after its shared pack block.

At a located terminal crash/rotor strike or terminal exhaustion, the policy sets the candidate latch to 1, restarts derivative evaluation from the event state, and integrates the remainder with zero drive; residual RPM and loads continue under the admitted coast law. Do not reuse pre-event k1 across the discontinuity. Within a tick the latch can only move 0→1; it cannot arm or resample the controller. The composed endpoint maps the accepted event into the matching motor lifecycle/reason and validates consistency with the latch. It preserves the interval's sampled actuator commands and allocation diagnostics: these describe the commands held before the event, not permission to drive after it. The latch makes effective drive zero immediately; the next disarmed sample allocates zero. Restore at this terminal endpoint must therefore produce zero drive even while the preserved last-sample commands are nonzero. A prepared pad/reset clears the latch with a new disarmed state; ordinary reconnect/rearm cannot clear a crash/exhaustion latch.

This hybrid marker has a declared layout and checkpoint identity despite being carried in the kernel's continuous block. Qualify that use with SF rather than silently treating a floating flag as an ordinary ODE state. Tests enforce exact domain values, zero derivative between events, monotonic transitions, sub-tick cut, coincident boundaries, reset/restore and full rollback. If SF rejects this representation, DR-09b must instead deliver a generic piecewise stage-context API with equivalent proofs before M2; an endpoint-only cut is not an equivalent fallback.

For each candidate interval:

1. Determine conservative event/domain/contact limits using the declared law and current state; do not equate a guess at endpoint sign with a bound on all RK stages.
2. Advance only through valid stage domains or a specifically documented mathematical continuation qualified for root location.
3. Locate the earliest boundary within the accepted time/error budget, group genuinely simultaneous roots under a deterministic rule, apply all affected transitions, and continue the remaining interval.
4. Retain accepted path/event records only. Reject if a work/iteration/payload limit is exceeded; no silently dropped stop, collision or race crossing.
5. Integrate pack power and all rotor/body states consistently across the same accepted intervals. Apply motor cut at a located crash according to the chosen policy, not retrospectively only at the end while claiming sub-tick actuation.

Qualify flat-pad support first, with isotropic ground contact appropriate to the frame. Test equilibrium, friction, tip-over, takeoff without spontaneous lift at idle, disarmed spin-down, touchdown and low-charge authority. Spinning-disc strikes require swept rotor-envelope checks, while stationary blades/body remain physical geometry under an explicit conservative hull rule. Reuse existing terrain/collision laws only where their geometry, origins and thresholds actually fit the quad.

## 8. Race-state composition — DR-23…26

### Authoritative state

Append a bounded race suffix to the model's sampled/discrete layout. Include race phase, attempt generation, GO tick/time, next required gate, current lap start time, valid-lap count, attempt validity, missed/reset/crash status, crossing-side/debounce state and the fixed three-lap result slots. Store both lap duration and validity. A terminal event ID/generation prevents duplicate finish publication. The session envelope pins immutable track/rules/world identities.

One `endpoint_transition` composes final physical terminal state with `RaceDirector.advance(previous, candidate, receipt, track, rules)`. The sampled callback preserves race suffixes except the explicitly staged countdown/GO transition below; `block_aux` preserves the resulting race state. Crossings and terminal adjudication remain endpoint-owned. The final validator checks race and physical clock/state together. `last_events` and a transient receipt are not substitutes for checkpointed race memory.

### Accepted-path receipt

The following is a proposed receipt schema, produced only by the qualified policy:

```text
version, policy_id, tick_start, time_start_s, time_end_s,
complete=true,
segments=[{t0,t1,p0_NED,p1_NED,accepted orientation/velocity data,
           interpolation_kind,error_bound_or_qualification_id}],
physical_events=[{id,type,time_s,root_uncertainty_s,affected_ids,...}],
endpoint_identity
```

The final schema must bound every array, string, nesting depth and total payload. Current kernel transport limits include 256 array elements and a 4096-value aggregate budget. Choose a smaller policy-specific bound from worst-case payload accounting and measured cost; the API must explicitly fail when exhausted. Do not promise arbitrary path resolution within a fixed real-time budget.

Validate ordered times, accepted endpoint match, continuity, immutable policy identity, finiteness, event references, segment coverage, uncertainty and explicit physical discontinuities. The physical endpoint composition runs before scoring validation; compare the receipt against that **final physical endpoint**, including any body changes made inside the endpoint callback itself. `body_filtered` only reports the earlier legacy filter and is insufficient alone. Never sweep an impact correction jump or pad teleport. With `body_filtered=true` or an unrepresented endpoint position/attitude correction, require a separately qualified replacement path or refuse/mark the race attempt unresolved according to its rule. Missing receipt must not fall back silently to a chord. A qualified located/dense accepted-path root, or an explicit policy split at the gate plane, supplies root direction/velocity and its uncertainty; linearly interpolated endpoint velocities are not automatically an accepted root state. Gate admission also requires a qualified crossing point with bounded uncertainty along both aperture axes. Its complete uncertainty interval must lie strictly inside the aperture. If it overlaps an edge, refine or mark the crossing/attempt unresolved under the rule; do not score a nominal chord point alone. The exact inequalities are in 04.

### Canonical event list

The current kernel concatenates policy events before endpoint events. For the new composite race model, prefer a policy that returns `events=[]` and puts its bounded physical records in the receipt. The composed endpoint validates and sorts those records together with gate crossings, applies terminal/arming/race rules, and emits **one** complete ordered list. Do not copy this convention into unrelated existing models. Verify all recorder/crash consumers for the new model use that canonical list.

Use exact time sort followed by deterministic anchored tie groups; do not use an approximate-equality sort comparator. Tie-window choice is a versioned race rule with root uncertainty evidence. Crash tied with a crossing wins; a crossing earlier by more than the tie tolerance and qualified uncertainty can count in diagnostic lap progress, subject to final attempt validity. Within a tie group, published adjudication priority may differ from raw timestamp order; it does not retroactively reorder the physical transitions already applied by the policy. Events after a terminal/reset jump cannot score. Complete gate mathematics and adversarial cases are in [04](04_FPV_RACING_INPUT_AND_PRESENTATION.md).

### Concrete first local race rules

Adopt proposed `openrc-local-race-v1` as an explicitly local practice format:

- Ready state requires the selected pad, complete track and valid controls. Countdown lasts exactly `3*240=720` simulation ticks. Pause freezes it. Motor drive is inhibited during countdown; this is a simulator start aid and not a physical-launch or federation rule simulation.
- Define GO at the **start** of interval `[t_720,t_721]`, exactly three simulation seconds after countdown starts. The pure sample transition at `t_720` checks the fresh calibrated **pre-inhibit** throttle, current source validity and arm authorization, stages phase/start time and removes countdown drive inhibition for that interval. The endpoint commits that staged GO together with the physical tick and publishes its event timestamp `t_720`; if the tick fails, neither GO nor drive history commits. A high-throttle/invalid-source GO stays drive-inhibited in staging, clears arm authorization, and requires fresh OFF→ON at low throttle before a new countdown. Do not test the always-zero inhibited motor command or the previous `t_719` input instead.
- Ordered gates are `0…N-1`; the last is the finish plane. Every valid lap passes the full sequence in the permitted direction. The first lap starts at GO; subsequent lap clocks start at the previous valid finish crossing. Finish after exactly three valid laps. Geometry must provide a continuous loop from finish back toward gate 0.
- Missing a gate requires returning and crossing it correctly; an out-of-order crossing has no progress effect. Wrong-way crossing and exact aperture-edge contact do not score.
- A crash, pad reset or mid-race physical/rates/rule change aborts the current **race attempt**. Preserve its invalid/incomplete result for diagnostics; a new attempt restarts countdown and all three lap slots. This deliberately resolves the older plan's underspecified 'invalid current lap after respawn' into a simple restart policy. A lap-retry mode can be a separate future ruleset.
- Pause produces practice/noncompetitive metadata; there is no online ranking or compliance claim. Changing purely visual preferences does not change physics or the current attempt's physical hash, but presentation metadata can record it.

These choices make implementation and test expectations concrete while keeping rule complexity small. If product review selects another start/reset rule, change the version and all corresponding fixtures before release.

## 9. Recording, replay and result persistence — DR-17/26

Reuse the shared bounded, checksummed packet/container primitives and current airship adapter as a structural precedent. Define a separate multirotor envelope that serializes **full** controller, actuator, source, environment and race state. Airship's reduced restart assumptions are not transferable to this closed-loop vehicle.

Every accepted row identifies tick, accepted logical pilot sample/actions, requested rate/moments, allocated commands, produced body/rotor/battery telemetry, modes and canonical events. Retain the immutable sampled commands in aux through endpoint publication, including a crash tick. Record the located cut time and resulting effective zero-drive branch separately; never overwrite pre-impact command evidence with a post-impact zero. A nonzero command followed by an interior crash must replay both the sampled request and the cut. Distinguish start-of-tick controller/`k1` values from accepted endpoint values; current `last_loads` is k1, not an endpoint sensor. Optional endpoint telemetry is a pure evaluation against the accepted frame, with no state advancement.

Exact replay acceptance is the conjunction: complete log, matching identities/backend/clock policy, `solver_changed=false`, and accepted per-tick state/event equality under the declared platform/build. A parser reporting `exact=true` alone is insufficient. Truncated recoverable prefixes remain explicitly incomplete. After restore, compare continued closed-loop state, not just whether restore returned success.

A candidate controller run replays the **pilot tape** through the candidate controller and plant. Replaying baseline motor duty bypasses feedback and cannot assess controller changes. Changed law/controller/backend creates candidate-comparison evidence, not exact-equivalence evidence. Reuse existing plotting/reducers and retain one baseline, one explicit candidate, parameter hashes, markers and meaningful response/energy metrics.

Keep recording read-only and bounded. Reserve required capacity before a tick or define a nonblocking bounded sink; a postcommit I/O failure marks the recording incomplete and applies the documented pause/fault policy, never retroactively rewinds accepted physics. Results are a projection of a committed **terminal** state, whether finish or abort: retain completed lap slots, attempt validity and the terminal reason. Before a reset replaces an attempt, capture its bounded terminal record into the session's pending-result outbox as part of the accepted session reset transaction. Reserve capacity before accepting a terminal tick or a replacement; failure to reserve refuses the new operation without discarding the current attempt. Pin and checkpoint the pending outbox in the session envelope. Observers see the accepted replacement and retained old result together.

Persist that outbox asynchronously: write a complete temporary result, flush as supported, then atomically replace/rename in the same filesystem. Include attempt ID for idempotence, exact lap list, validity, all identities and timing-error qualification. On a write failure, retain the queued record, show an unsaved/error status and provide bounded retry; do not rewind accepted physics. A full outbox blocks further attempt replacement until capacity is available. A queued in-memory record is not claimed durable against process/power loss before its file or checkpoint is saved. Remove it only after confirmed persistence. Automated tests use isolated user data and cannot overwrite player records.

## 10. Rendering and routing boundaries

Add a dedicated multirotor activity/session and view adapter. Audit every `is_rotorcraft` and negated use before catalog exposure; aircraft-only enumeration must remain explicitly aircraft-only. Fix Home preparation/preview/trim cancellation, device selection, starts, help, energy controls, Workshop admission, CLI options, return-to-Home and failed-launch preservation. Direct flags that are not supported by the drone must return a useful rejection rather than be ignored by an airplane parser.

Presentation consumes one accepted/interpolated pose and read-only telemetry. A proposed stable visual naming scheme is `airframe_root`, `motor_1…4`, `propeller_1…4`, `camera_mount`, with exact mappings in the import manifest. It is new-drone naming; existing aircraft node/hinge names stay stable. Convert CAD axes/units once. Spin direction and phase follow achieved rotor speed; low-speed stopped blades remain visible. Audio and OSD do not infer battery values for an ideal-energy lab law or use commanded duty as measured RPM.

Use the current camera helpers where appropriate, one interpolation owner, history reset on teleport, and primary 1080p native checks. The camera mount/FOV and latency specifications in [04](04_FPV_RACING_INPUT_AND_PRESENTATION.md) are normative for the proposed view. Optional high-cost effects are independently disabled and must release their update/allocation cost; settings cannot alter the simulation timestep or laws.

## 11. Settings research and configuration application

The settings follow-up in [07](07_BETAFLIGHT_INAV_SETTINGS_RESEARCH.md) and [08](08_SETTINGS_SCHEMA_IMPORT_AND_TESTS.md) extends configuration/schema obligations without changing this baseline's one sample per outer tick. The 31-value controller block is not a layout for every optional filter/modifier. New histories, clocks, latches, spectral windows and telemetry state require explicit bounded layouts and identities. P19a is a separately reviewed conditional generic sampled-event protocol if the 240 Hz qualification fails; extra RK stages never substitute for fresh control samples.

The initial settings workflow stages candidates as data and applies physical/control/input changes through the full-frame reset/replacement contract. A settings hold leaves an armed accepted frame armed and frozen. Ordinary Apply cannot silently reset or accept a polled disarm; the explicit Reset to pad and apply action can prepare a disarmed replacement, preserve the old terminal race record and commit the configuration/state together. Precommit refusal preserves the old session. Postcommit recorder/UI observer failure retains the new accepted identity, pauses it and marks affected recording incomplete. Fresh post-reset arm evidence remains required. Visual-only settings stay observational. Full parser/profile/default rules and additional tests belong to 08.
