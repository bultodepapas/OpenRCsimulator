# FPV source audit and executed evidence

**Baseline:** read-only source inspection of `bultodepapas/OpenRCsimulator` at `7bff78490f9af5c1664f47c8ba865a92b3430920`. The October plan examined `22396c6e`; its DR IDs are preserved. The initial source-review findings below are followed by the **executed validation dossier** and complete reproducible probe/oracle code. Current implementation observations and proposed changes remain separate. The final proposed ABI, full-frame reset, event-local cut, recovery and race rules are owned by [02_ENGINEERING_CONTRACTS.md](02_ENGINEERING_CONTRACTS.md); this audit explains their source basis.

All links below point to the immutable inspected commit. `app/sim/AGENTS.md`, `app/physics/AGENTS.md`, the root `AGENTS.md`, and `docs/STACK.md` govern the implementation. Keep simulation state in scalar float64 / `PackedFloat64Array`, NED world / FRD body; rendering alone converts at `render/frames.gd`. Continue using the shared custom 240 Hz RK4 kernel; do not make a Godot rigid-body node the flight solver. Prioritize 1920×1080 native presentation and performance evidence, then higher resolutions, with 720p last. Do not rerecord existing golden flights for this work without an intentional, explained physics change.

## Findings requiring a design decision

### 1. DR-16a must cover reset, stage evaluation, sample state, and fault recovery as one contract

**Existing.** `VehicleModel.pre_tick(aux, inputs, dt)` returns only the sampled aux array; it has no accepted body, continuous state, modes, tick, or time. `stage(body, continuous, t)` has no sampled state or modes. The kernel calls pre-tick once, assigns its returned aux, calls joint stage for k1, holds aux through all RK stages and substeps, then runs filters, endpoint transition, projection and validation before committing. See [vehicle_model.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/vehicle_model.gd#L1-L9), [callbacks](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/vehicle_model.gd#L38-L96), and [simulation step](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/simulation.gd#L274-L369).

The laboratory `Plant.pre_tick` writes `Plant.duties`; its stage reads those duties from the plant object rather than its arguments. `Simulation._fail_safe` restores its own accepted arrays, clock and configuration but does not restore that object's field. `prepare_reset` also evaluates the stage before any new pre-tick, so stale duties can influence the reset's evaluated loads. The current test fixture explicitly primes `plant.duties = sim.aux.duplicate()` before reset, masking that boundary; its twin replay checks body/rotor-speed bytes and only asserts that restore succeeds, not a continued closed-loop replay after divergent cached duties. This mechanism was subsequently reproduced in the executed validation dossier below; the original 15-check fixture still passes its narrower assertions. [Plant](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/physics/multirotor/plant.gd#L20-L24), [sample and stage](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/physics/multirotor/plant.gd#L78-L120), [reset evaluation](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/simulation.gd#L118-L155), [rollback](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/simulation.gd#L716-L755), [fixture](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/tests/test_dr_multirotor_kernel.gd#L37-L53), [replay check](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/tests/test_dr_multirotor_kernel.gd#L167-L182).

**Proposed opt-in ABI sketch; names subject to SF review:**

```text
sample_tick(previous_frame, input_snapshot, clock) -> {aux, modes}
stage_sampled(body, continuous, stage_time, sampled_context)
    -> {loads, derivative, rotor_momentum[, body_derivative][, stage_context]}
```

- `previous_frame` is a detached accepted start-of-tick `{body, continuous, aux, modes}`, and `clock` pins `{tick, time_s, dt}`. `input_snapshot` is the validated pilot/action sample for the interval. The pure sample callback computes controller integrators, filter/delay history, output commands and any boundary arm/mode transition exactly once; fixed-size returned aux/modes are validated before k1 and replace only a candidate frame. Arm/disarm becomes effective for all stages of that tick. If the design chooses to keep arming outside this callback, define and prove an equally atomic pre-stage boundary instead.
- `sampled_context` carries detached, immutable candidate aux/modes through **all** stage calls, including reset preparation, k1, k2–k4, step-policy trials and substeps. Reset must evaluate from the prepared reset frame, not a cached previous flight; restore must resume from the restored frame. The purity/aliasing guard covers the new callback and registered finite context, including reentry and representative mutation tests; arbitrary captured/global state is prohibited by contract, not magically sandboxed. Reuse `state_layout_identity`, validator, endpoint guard and checkpoint v2 where applicable; include new callback fields in model validation and guarded-field capture.
- Opt in explicitly and require compatible callback combinations; reject ambiguous simultaneous legacy/new callbacks. Preserve byte-for-byte legacy `pre_tick` and `stage` dispatch, checkpoint v1/v2 identity and event/observer ordering for non-opted-in airplane, helicopter and ground models. Do not run control or alter filters in derivative evaluations. Pin law/layout/controller/sample rate/filter/actuator/scheduler identities in the session envelope, not just `VehicleModel.identity`.
- Reset is prepare → validate detached full candidate → commit/publish; a rejected preparation leaves the old session, recorder and input state intact. Accepted publication observer failure is a committed observer fault, not a rolled-back reset. `Simulation.reset()` itself calls fail-safe on a failed prepare, while `prepare_reset()` is the non-mutating primitive. Respect its documented [prepare/commit ownership](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/simulation.gd#L109-L200), [protected publication](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/simulation.gd#L203-L249), and [restore](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/simulation.gd#L758-L850).
- Also account for state outside `Simulation`: controller input ownership and any rate-throttle accumulator, pending actions, sampled wind/turbulence state, race state, recorder cursor and session identity. The final contract in 02 places the authoritative input/action cursor, source generation and deterministic throttle accumulator in checkpointed aux/modes, committed before observers. Device-reader reservations and recovery proposals are staged non-authoritative evidence in the session envelope; later input-tape reclamation is storage housekeeping. Hardware samples cannot be undone; define the next sample after a fault and consume queued actions only on a declared accepted boundary. A sticky simulation fault and automatic pause are expected even though the accepted physical frame is restored.

**Focused proof to write in DR-16a, on an isolated copy first:** divergent stale plant duties versus candidate aux at `prepare_reset`; sampling a changed command then injecting nonfinite k1, k2 and k4; malformed event/endpoint/projection; and restoring an earlier snapshot into an owner with a different prior command. Assert complete accepted-frame bytes, owner caches, recorder row count, queued actions and observer counts, plus expected sticky fault/pause. A newly restored healthy session must produce the same next accepted load and state as a fresh control from the same checkpoint. Test accepted reset observer faults separately from rejected reset. Coordinate before executing mutations or deliberate failures.

Two easy-to-miss boundaries: `Simulation.step()` itself does not check `paused`; only its engine `_physics_process` does, so a manually stepped activity must guard holds itself. And `last_loads` is the k1 **start-of-tick** load, not endpoint telemetry; do not present it as the accepted endpoint measurement. [step/hold](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/simulation.gd#L274-L280), [process guard and interpolation](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/simulation.gd#L506-L549), [load definition](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/simulation.gd#L30-L45).

### 2. Race state can use the existing atomic endpoint, with a path-policy dependency

**Existing.** The opt-in endpoint callback sees detached previous/candidate frames, tick/time/dt, located events, `body_filtered`, and optionally an integration receipt. It returns `{body, continuous, aux, modes, events}`; final projection/validation runs before state is committed. `events_located` and `stepped` then fire synchronously. `test_endpoint_transition.gd` checks that observers see the committed combined state and that checkpoint/replay preserves it. `last_events` and integration receipts are transient, not checkpoint state. [endpoint callback](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/vehicle_model.gd#L21-L36), [commit order](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/simulation.gd#L448-L519), [endpoint proof](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/tests/test_endpoint_transition.gd#L123-L163), [receipt proof](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/tests/test_integration_receipt.gd#L45-L87).

**Proposed.** A composite drone `VehicleModel` allocates a versioned, bounded race slice in `aux`/`modes`; its one pure `endpoint_transition` composes terminal-contact/crash handling and `RaceDirector.step`, then returns a single frame. Observers and the recorder cannot see a physics tick with the prior race tick. The session envelope pins vehicle, controller, field, track, rules, collision world and initial race state. The race slice must include enough to resume exactly: race phase/start clock, next gate/lap, last crossing/side and debounce information, lap validity/penalty/respawn state, stable ordering/generation, and bounded lap times/results. If results cannot fit a fixed bound, explicitly define an independently validated, bounded durable projection with the same commit semantics; do not assume transient events reconstruct an incomplete checkpoint.

**Limits and decisions.**

1. `integration_receipt` is produced only by a model `step_policy`; ordinary RK4, kernel substeps and its declared-event locator do not produce one. The kernel checks receipt transport and limits, not its physical truth. If DR-25 requires accepted trajectory segments, DR-09b must provide a compatible whole-tick policy that records only accepted pieces. Alternatively, explicitly admit only a straight endpoint segment, state its approximation and bound curved-path error against refined trajectories before release. `body_filtered` means the integrated path may no longer describe the accepted path: reject or recompute crossing evidence for that tick rather than scoring it. [policy selection](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/simulation.gd#L370-L399), [receipt validation](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/simulation.gd#L679-L707), [filter test](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/tests/test_integration_receipt.gd#L125-L143).
2. A whole-tick `step_policy` cannot be combined with a kernel substep request >1; it must itself handle required contact refinement, all four stop events, pack exhaustion, coincident boundaries and bounded accepted-path output, or SF must first qualify a generic extension. Validate segment count, version, monotone times, continuity with accepted endpoints, physical identity and size; bounded receipt payloads cannot be arbitrarily large. [contract](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/vehicle_model.gd#L68-L95), [refusal](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/simulation.gd#L372-L390).
3. `endpoint_transition` is a single callable, so compose all physical and race transitions intentionally. `_endpoint_events` appends located events before endpoint events and does **not** globally sort by timestamp. Race rules must compare crash/contact and crossings in a deterministic chronological order with an explicit tie rule, independent of publication-list order. [event merge and limits](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/simulation.gd#L1059-L1098).
4. Test snapshot immediately before, on and after a gate; spawn/coplanar starts; wrong direction; edge/frame touch; multiple gates in one tick; coincident crossing/crash; invalid lap/respawn; storage exhaustion; filtered bodies; malformed receipts; identity mismatch; and byte-identical continuation. Capture results only from an accepted terminal finish or abort, never a trial/rejected tick. Retain the old terminal record in the bounded checkpointed session outbox atomically with attempt replacement, then persist asynchronously under 02 section 9. Keep automation isolated from player storage. A session observer which updates race state only after `sim.step()` is insufficient because kernel observers have already fired.

### 3. Current controller input is already shaped; input readiness is not motor arming

**Existing.** Profile normalization applies calibrated endpoints/inversion. `ControllerProfile.condition_axis` applies rescaled deadzone **and cubic expo for gamepads**; radios bypass that gamepad shaping. `RcInput.sticks()` returns `channel_value`, so feeding it into a Betaflight/Actual expo curve composes two nonlinearities for gamepads. Absolute radio/trigger throttle uses direct `[0,1]` endpoint normalization. Stick-rate throttle is a stateful fixed-tick accumulator; `poll(..., integrate=false)` can gather readiness without advancing it during a hold. [normalization/conditioning](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/input/controller_profile.gd#L553-L608), [poll](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/input/rc_input.gd#L273-L367), [stick output](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/input/rc_input.gd#L396-L433).

`RcInput.armed` is device/readiness evidence: a verified live gamepad may become ready immediately. It is not the explicit drone motor-arm state. Radio low-throttle evidence, fresh samples after focus loss, retained virtual throttle and menu auxiliary gating are device lifecycle semantics. Helicopter adds its own arm/drive-hold state on top, which is useful precedent but has helicopter-specific collective/zero-pitch conditions and is not a quad policy. [reader readiness](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/input/rc_input.gd#L183-L205), [gamepad/readiness and rate throttle](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/input/rc_input.gd#L324-L367), [helicopter hold and focus](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/helicopter_flight_session.gd#L934-L965), [motor arm](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/helicopter_flight_session.gd#L1067-L1115).

**Proposed.** DR-14/15 should add an explicit calibrated/pre-expo semantic-stick API or documented opt-in input transform, retaining the appropriate gamepad deadzone while making the DR rates curve the single intended nonlinear owner. If any composition is intentionally supported, expose and identify it, test the complete curve and never silently apply it twice. Keep `RcInput` as device authority, but separately require a low throttle plus a fresh explicit arm transition; a high switch on entry, bounce, reconnect or resume is not a new request. Define pending switch and action ordering, neutral/release/focus/device-loss behavior, and a visible fixed-tick policy for centered keyboard/gamepad throttle. Freeze that accumulator, FC, pack and race clocks during holds. `airship_input.gd` is a useful compact example of reader reuse and sample/integrate separation, not an implementation of motor arming or the required transactional rollback. [airship input](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/input/airship_input.gd#L57-L85).

### 4. A third catalog type crosses more than the launcher

**Existing.** `AircraftCatalog.is_rotorcraft` treats older entries as airplanes; `airplane_flyable_entries()` is `not is_rotorcraft`, so a new `vehicle="multirotor"` would be admitted to airplane-only loops. The shell chooses helicopter script versus airplane scene using the same binary predicate and prefetches airplane trim for non-helicopters. Home uses airplane or helicopter start, failure, trim, battery and help controls; its preview path calls `AirplaneBuilder.build` and has helicopter-only branches. The airship now has a separate activity/direct CLI route and is not in the aircraft catalog. [catalog](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/app_state/aircraft_catalog.gd#L206-L219), [shell route](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/app_root.gd#L475-L505), [prefetch](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/app_root.gd#L414-L437), [airship route](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/app_root.gd#L296-L317), [Home start](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/ui/home.gd#L1415-L1452), [preview](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/ui/home_scene.gd#L155-L205).

**Proposed.** DR-36a must enumerate all `is_rotorcraft` and negated checks, introduce explicit vehicle/capability routing, and admit the quad only to compatible start, controller, weather, help, telemetry, preview, Workshop and CLI consumers. Preserve airplane-only lists as airplane-only. Implement or explicitly support a truthful unavailable/loading preview; include async cancel/cache/ownership and airplane/helicopter selection after switching. Reject unsupported CLI combinations rather than falling through to fixed-wing parsing. `app_root.gd` also handles staged loading, session controller ownership, exit/recording and return-to-Home, so route acceptance is broader than instantiating a script. Test failure during candidate launch leaves prior Home selection/field/preview alive. [script construction](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/app_root.gd#L1284-L1319), [Home preview async](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/ui/home_scene.gd#L263-L311).

## Concrete file and symbol map

| DR IDs | Existing source and exact seam | Proposed change / owner coordination |
| --- | --- | --- |
| 03, 06, 07, 09, 16a | [rigid_body.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/physics/rigid_body.gd#L1-L20), [vehicle_model.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/vehicle_model.gd#L38-L96), [simulation.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/simulation.gd#L274-L519) | SF-reviewed opt-in sampled-feedback/stage context; independent controller and numerical reference, including nonzero body acceleration. Model-specific laws remain outside kernel. Rigid-body spinning momentum enters gyroscopic cross term; verify shaft/body coupling and relative momentum derivative exactly once; current sign check alone is not conservation. |
| 04a–06a, 05–07 | [multirotor/plant.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/physics/multirotor/plant.gd#L27-L69), [rotor.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/physics/multirotor/rotor.gd#L13-L35), [powertrain.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/physics/multirotor/powertrain.gd#L1-L20) | Keep the 152 mm-diagonal estimated fixture a named software baseline. Replace hidden `duties` authority and add explicitly independent motor-arm mode: the existing duty clamp always enforces idle, so zero input does not mean disarm. Validate rotor signs, drag passivity, energy/work and selected-build parameters separately. |
| 05, 09b | [electric_motor.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/physics/electric_motor.gd#L1-L55), [battery/pack_ecm.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/physics/battery/pack_ecm.gd#L1-L19), [single-load solve](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/physics/battery/pack_ecm.gd#L147-L201), [electric_battery_step.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/physics/electric_battery_step.gd#L19-L35) | Existing motor and pack are one-quadrant, one-load APIs; pack state already includes charge, terminal energy, losses, RC, temperature and supervisor fields, and the battery-step adapter accepts **one** RPM index plus charge. Generalize/adapt the stage-local active-load bus solve for four motors sharing one pack; choose and identify per-ESC vs shared limiting. Do not call the current single-load pack solver four times as if four full packs existed. Derive a deterministic bounded active set for motoring or qualify another solver; test zero duty, stalled, different back-EMFs, depleted, bad/no feasible bus, conservation, limit switches and coincident stop/exhaustion. Braking/regeneration is unsupported by these laws. |
| 02, 10–13 | [battery_data.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/physics/battery/battery_data.gd#L1-L25), [load/hash check](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/physics/battery/battery_data.gd#L24-L58) | Create proposed sibling multirotor data reader/schema/generator and licensed build manifest; share suitable strict quantity and provenance helpers, not wing/trim assumptions. Hash normalized data and rates separately, reject incoherent geometry/inertia/hover, label estimates, and retain source bytes/GLB hashes/licenses. |
| 14–17 | [rc_input.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/input/rc_input.gd#L273-L367), [helicopter_flight_session.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/helicopter_flight_session.gd#L1210-L1225) | New dedicated multirotor session and input adapter; reuse ownership/calibration primitives and session identity/validation patterns, not helicopter controls or a fixed-wing session rewrite. Own one model, fixed-tick driver, checkpoint envelope, read-only observers and explicit motor arm/hold semantics. |
| 17 | [airship/flight_log.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/airship/flight_log.gd#L1-L18), [fresh-session verify](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/airship/flight_log.gd#L277-L330), [rotorcraft_recorder.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/rotorcraft_recorder.gd#L194-L223) | Dated plan's statement that `.orfl` currently serves only fixed wing is stale: BL has a versioned airship `.orfl` adapter on the common bounded packet container; the helicopter recorder is a separate trace path. Build a distinct drone format/adapter on shared primitives, not a false claim of existing drone support. Airship's state+continuous restart and tick-zero reset rely on its admitted time-invariant law; they are insufficient for FC, scheduler, arm, weather or race state. Record the **pilot tape** and switch edges and rerun FC, with full accepted state and identity; require `complete`, `!solver_changed`, same-platform identity and per-tick byte match for exact replay. Candidate FC comparison uses the same pilot tape, never baseline motor duties. |
| 18–20, 23–25 | [scenery_collision.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/scenery_collision.gd#L62-L80), [helicopter impact](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/physics/rotorcraft/impact_detector.gd#L13-L20), [landscapes catalog](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/landscapes/catalog.gd#L22-L56) | Reuse float64 terrain/support and swept-hull/contact methods with explicitly sized quad hull and rotor geometry; helicopter detector contains helicopter-specific probes and speed thresholds and is not a generic four-rotor collision contract. Build/validate a versioned, data-defined race track and its separate scoring apertures. |
| 24, 32 | [collision_world.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/scenery/collision_world.gd#L133-L174), [box/capsule geometry](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/scenery/collision_world.gd#L858-L893), [proxy validity](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/scenery/collision_world.gd#L961-L982) | Current world hashes sorted proxies and bounded broadphase; supported boxes rotate only by heading and capsules are vertical. Arbitrarily tilted/dive gates need a qualified 3D-oriented proxy and matching narrowphase/bounds/identity/cache/test changes, or such gates must be rejected. Do not represent a tilted gate with a misleading heading-only solid. Keep visual gate, solid proxy and scoring aperture aligned yet distinct; pin the complete resulting world in checkpoint identity. |
| 29–31, 35–37 | [camera_rig.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/render/camera/camera_rig.gd#L1-L20), [helicopter_main.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/helicopter_main.gd#L246-L266), [frames.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/render/frames.gd#L1-L9) | FPV is not in current camera views; add a CAM-owned mount/view using the **same** interpolated body pose as the model, full roll and configured tilt; no second smoothing/interpolation. Reset visual/camera histories on respawn, pause and teleport. Draw four prop phases from achieved RPM/spin and keep stopped blades visible. Verify horizontal-to-vertical FOV at both aspects, near-plane/depth, 30/60/144 fps, plus 1080p render evidence. HUD/audio are observational and must not feed flight. |
| 23–26 | [simulation endpoint](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/simulation.gd#L448-L519) | Add versioned track/rule loader, composite endpoint race director and bounded race state; deterministic ordered gate timing, ties, validity and atomic result persistence. Keep free flight independently releasable. |

## Suggested reviewable PR dependency order

1. **DR-02/03 + DR-16a:** assembly/license manifest and independent reference work in parallel with generic sampled transaction design and failing-then-fixed isolated proof. SF owns kernel review. Specify reset/restore and all legacy paths, not just the live tick.
2. **DR-10/11/13 + DR-06/07/09a:** strict sibling loader/generator and named research fixture; motor/body momentum audit; reference-controller/mixer/anti-windup on the laboratory law; fixed-sample numerical refinement. Keep no playable catalog entry yet.
3. **DR-16b/17:** dedicated headless session, full identity/checkpoint envelope and new closed-loop recording adapter. Prove exact same-build replay and fault/observer boundaries before tuning; this is M1 laboratory evidence.
4. **DR-05/09b/12 + DR-14/15 + DR-18–22:** sourced build and single-bus pack, four-stop/charge/contact policy, calibrated input/actions and explicit arming, solved pad support, crash/reset, controller qualification and endurance. M2 control gains must be qualified on the chosen product powertrain, not borrowed from the lab.
5. **DR-29–31/35–37 + DR-36a:** licensed reusable visual adapter, four achieved-RPM rotors, FPV, basic audio/OSD, capability-aware Home/direct route. Qualify 1080p first and expose experimental status. Audit shared catalog consumers, native packaging, controller selection, observers and startup-failure/return-to-Home.
6. **DR-23–26/32 + DR-36b:** data-defined track and solid proxies, path representation and atomic endpoint race state, scoring and result persistence. M3 depends on the chosen DR-09b path-policy contract or an explicitly qualified straight-segment approximation.
7. **DR-04/38–40:** advanced prop/inflow laws and held-out/physical evidence remain separately qualified, not implied by playable racing.

## Existing tests to preserve and new discriminating gates

Coverage below was source-inspected. Of these targets, only the **15-check DR kernel test** was executed, in the 73-source minimal project, as recorded in E.2. The remaining listed suites were not run. The separate expected-defect probe and 20 Python synthetic reference cases have their own evidence below. Select the smallest affected checks while implementing; full `app/test.sh` and required CI are the feature-merge gates specified in the existing plan. `app/sim/AGENTS.md` additionally calls for relevant session checks and `test_golden.gd`, and the flight-test battery when trajectories or response can change. Do not rerecord fleet goldens to make routing or documentation pass.

| Boundary | Existing relevant source | New proof that existing tests do not establish |
| --- | --- | --- |
| Kernel/layout | `test_sf_vehicle_model.gd`, `test_simulation.gd`, `test_checkpoint.gd`, `test_checkpoint_integrity.gd`, `test_endpoint_transition.gd` | Opt-in body-aware sample and stage context across reset, k1–k4, rejection, projection, validation, checkpoint, restore, aliasing, callback reentry and observer order; v1/v2 byte/order parity for unmodified models. Include live fixed-wing, helicopter and truck callers. |
| Events/substeps | `test_sf_event_protocol.gd`, `test_sf_event_refinement.gd`, `test_sf_contact_substeps.gd`, `test_integration_receipt.gd`, `test_electric_battery_step.gd` | Four stops + depletion + stiff contact, ties and stop/restart under one qualified policy; bounds, negative-stage handling, accepted-path only, no silent contact-policy incompatibility. Existing one-rotor tests do not prove four-rotor behavior. |
| Drone physics | `test_dr_multirotor_kernel.gd`, `test_rotor_coupling.gd`, `test_rotor_disc_terrain.gd` | Independent torque/shaft-work and momentum closure, all motor mixes and signs, replay after different cached duties, prop clearance and swept terrain/post/edge at high speed, disarm vs armed idle, pack energy closure and held fixed-rate plant refinement. |
| Controller and ownership | `test_controller_conditioning.gd`, `test_controller_actions.gd`, `test_controller_pause_recovery.gd`, `test_controller_recovery_focus.gd`, `test_rc_input.gd` | Full rates vectors on pre-expo calibrated samples; radio/gamepad/keyboard, already-high arm switch, bounce, mode switch, device loss/focus/reconnect and pause/resume/reset; distinct device readiness and motor arm; no rate-throttle or pending-action advancement on failure/hold. |
| Replay | `test_flight_log.gd`, `test_flight_log_inputs.gd`, `test_airship_flight_log.gd`, `test_rotorcraft_trace_chunks.gd`, `test_replay_integrity.gd` | Complete versioned drone record, truncated/corrupt rejection, identity mismatch, exact replay of FC/pack/modes/accepted pilot tape, resume from mid-maneuver and stop, observer/recorder fault boundaries and closed-loop candidate comparisons. |
| Presentation and route | `test_camera_views.gd`, `test_camera_history.gd`, `test_camera_route.gd`, `test_aircraft_catalog.gd`, `test_home_flight_preparation.gd`, `test_home_launch_setup.gd`, `test_ui_home_preview_cache.gd`, `test_airship_activity.gd` | FPV full roll/tilt/FOV/aspect, history rebase and telemetry correctness; no airplane camera change; three distinct catalog families, no fixed-wing loader/trim/failure/Workshop fallthrough, failed startup and rapid switching/prefetch cancellation; native fresh-export asset/route smoke. |
| Course | `test_landscape_collision_world.gd`, `test_landscape_collision_oracle.gd`, `test_rotor_disc_terrain.gd` | Gate and frame geometry at arbitrary permitted orientations; world hash changes on geometry/rule edits, wrong/multiple crossing and deterministic crash ties; linear versus refined curved timing error; exact lap replay and results isolation. |

Software determinism does not establish physical fidelity; 1080p qualification requires the named native host, renderer, actual frame/tick distributions and pilot-facing capture, and selected-build validation remains DR-40. Current physical wind is an environment-provider query with owner-sampled turbulence; do not claim resolved spatial gusts or silently omit the owner's sampled/RNG identity. [environment.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/environment.gd#L1-L5), [wind query](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/sim/environment.gd#L37-L70).


# Executed validation dossier — 11 November 2026

## E.1 Environment and scope

The reviewer cloned the current GitHub source into an isolated sparse checkout and froze it at `7bff78490f9af5c1664f47c8ba865a92b3430920`. The repository's `app/get-godot.sh` obtained the exact pinned Linux x86_64 editor and verified its archive, executable and version. The tests below ran with **Godot 4.8.beta2.official.cafc17a19** through the repository's checked runner.

The existing DR test and its transitive source dependencies were copied without edits into a **73-source minimal headless project**, with the same 240 Hz tick and 12-step cap. A minimal project intentionally omitted product autoloads, assets, UI, exported resources and renderer qualification. The source manifest in E.7 records every copied source SHA-256. The isolated fault probe was added only to that validation copy. The source checkout's tracked files remained unchanged.

This is a focused current-kernel verification and defect reproduction, not a full project import/CI pass, physical experiment, playable activity or native 1080p benchmark. The independent numerical suite checks stated equations and synthetic values; it does not execute the proposed Godot controller or new ABI.

**Verified editor executable SHA-512:**

```text
428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9
```

## E.2 Checked-runner results

| Run | Complete | OK | Meaning | Raw log SHA-256 |
| --- | --- | --- | --- | --- |
| dr-existing-kernel-yo9bo4j1 | true | true | 15 existing checks passed | `9808c4119c4bc770ae9800643fda83ad7a328bb1e3da5e82b4bdb4715f33f3bd` |
| dr-minimal-import-fzo091wh | true | true | Minimal source closure imported | `0f2efc4409010571ed4a29bbc5ee05fbad0d2732989f1388285a28b0e767d322` |
| dr-transaction-gap-5b8ol7uw | true | true | Known defect successfully reproduced | `55ad32ea25f37ff108bd8170f67ffd5823668c7c4c68df81a51747afbd7f55fc` |

Each checked result reported no engine/script diagnostic records. The transaction-gap probe deliberately produces a handled simulation fault; that is an observed kernel refusal, not an engine parse/runtime error. Its exit status is zero only when the expected defect is reproduced.

### Existing test output

```text
Godot Engine v4.8.beta2.official.cafc17a19 - https://godotengine.org

ok   the plant installs on the kernel and resets at hover 
ok   layout: four inputs, four sampled duties, four rotor speeds, no discrete modes 
ok   hover closed form: four thrusts carry the weight 
ok   one second of hover holds altitude within 1 mm and stays level z -1.500000 p 0 q 0 r 0
ok   rotor speeds stay at the hover speed under the lag law 
ok   the spinning momentum of matched pairs cancels 
ok   raising the right rotors rolls left (negative p), no pitch [-1.11384893318239, 0.0, 0.0]
ok   raising the front rotors pitches up (positive q), no roll [-0.0, 1.32601063474094, -0.0]
ok   speeding the counter-clockwise pair yaws clockwise (positive r) with no roll or pitch [-0.0, 0.0, 0.63960952888147]
ok   rotor acceleration yaws the body inertially: more clockwise yaw after one tick with rotor inertia than without with 5.22e-2 without 6.24e-4
ok   rotor drag never does positive in-plane work (200 random states) -0.22878531671036414
ok   a steady wind builds []
ok   flying with the wind through the environment contract gives the still-air loads (Galilean, 1e-9) 0
ok   two kernels replay the same bytes 
ok   the plant's kernel checkpoints and restores 
15 checks, 0 failed
```

### Fault/reset reproduction output

```text
Godot Engine v4.8.beta2.official.cafc17a19 - https://godotengine.org

FAULT_OBSERVATION {"accepted_aux":[0.472729046616718,0.472729046616718,0.472729046616718,0.472729046616718],"aux_rolled_back":true,"body_rolled_back":true,"continuous_rolled_back":true,"fault_reason":"step rejected: RK joint stage evaluation is nonfinite or malformed","initial_reset":true,"installed":true,"private_duties":[0.1,0.8,0.8,0.1],"private_duties_rolled_back":false,"stage_calls":2,"tick_after_fault":0}
RESET_OBSERVATION {"primed_prepare_ok":true,"primed_yaw_moment_nm":0.0,"stale_prepare_ok":true,"stale_yaw_moment_nm":0.787007672634271}
Transaction gap reproduced: true
```

**Interpretation:** the refused tick remains tick 0 and restores body, continuous and aux arrays. The plant's object-owned duties retain the attempted new commands. `prepare_reset` then evaluates different yaw loads for the same candidate body/continuous/aux when only that stale private cache changes. This proves the isolated reset/load consistency defect. It does not establish the rate controller or any proposed fix, because neither has been implemented here.

## E.3 Reproducing the current-source probes

Use a complete checkout at the frozen SHA and the repository's checked runner/import procedure. Save the GDScript below **outside** `app/` as an absolute temporary file. After importing the full project with the pinned engine, run:

```sh
python3 tools/godot/run_checked.py --timeout 90 \
  --label dr-existing-kernel --require-text '15 checks, 0 failed' -- \
  "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy \
  --script res://tests/test_dr_multirotor_kernel.gd

python3 tools/godot/run_checked.py --timeout 90 \
  --label dr-transaction-gap --require-text 'Transaction gap reproduced: true' -- \
  "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy \
  --script /absolute/temporary/path/probe_dr_transaction_gap.gd
```

These are reproduction instructions for a full checkout; the recorded run used the isolated closure described above. The full-project environment can add errors or dependencies not present in the minimal run. Do not downgrade assertions or hide those differences. After the new contract is implemented, preserve this baseline and add a new-path regression expecting full context consistency; do not mark the old defect probe as a product success merely because it continues to reproduce the defect.

### Complete isolated GDScript probe

```gdscript
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Sim := preload("res://sim/simulation.gd")
const Plant := preload("res://physics/multirotor/plant.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var plant := Plant.new()
	plant.data = Plant.research_quad()
	var sim := Sim.new()
	root.add_child(sim)
	var installed: bool = sim.set_model(plant.build())
	sim.mass = float(plant.data.mass_kg)
	sim.inertia = plant.data.inertia_kg_m2.duplicate()
	var hover: Dictionary = plant.hover()
	sim.inputs = PackedFloat64Array([hover.duty, hover.duty, hover.duty, hover.duty])
	sim.aux = sim.inputs.duplicate()
	sim.continuous = PackedFloat64Array([hover.omega, hover.omega, hover.omega, hover.omega])
	plant.duties = sim.aux.duplicate()
	var initial := RB.make_state(M.v3(0.0, 0.0, -1.5), M.v3(0.0, 0.0, 0.0), M.q_identity(), M.v3(0.0, 0.0, 0.0))
	var reset_ok: bool = sim.reset(initial)
	var old_body: PackedFloat64Array = sim.state.duplicate()
	var old_aux: PackedFloat64Array = sim.aux.duplicate()
	var old_continuous: PackedFloat64Array = sim.continuous.duplicate()
	var old_duties: PackedFloat64Array = plant.duties.duplicate()
	var calls := {count = 0}
	sim.model.stage = func(body: PackedFloat64Array, continuous: PackedFloat64Array, t: float) -> Dictionary:
		calls.count += 1
		if calls.count == 2:
			return {} # Deliberate malformed k2 result, not a production source edit.
		return plant.stage(body, continuous, t)
	sim.inputs = PackedFloat64Array([0.1, 0.8, 0.8, 0.1])
	sim.step()
	var fault_observation := {
		installed = installed, initial_reset = reset_ok, stage_calls = calls.count,
		fault_reason = sim.fault_reason, tick_after_fault = sim.tick,
		body_rolled_back = sim.state.to_byte_array() == old_body.to_byte_array(),
		aux_rolled_back = sim.aux.to_byte_array() == old_aux.to_byte_array(),
		continuous_rolled_back = sim.continuous.to_byte_array() == old_continuous.to_byte_array(),
		private_duties_rolled_back = plant.duties.to_byte_array() == old_duties.to_byte_array(),
		accepted_aux = Array(sim.aux), private_duties = Array(plant.duties)
	}
	print("FAULT_OBSERVATION " + JSON.stringify(fault_observation))
	sim.model.stage = plant.stage
	var stale_reset: Dictionary = sim.prepare_reset(initial)
	plant.duties = sim.aux.duplicate()
	var primed_reset: Dictionary = sim.prepare_reset(initial)
	var reset_observation := {
		stale_prepare_ok = stale_reset.ok,
		primed_prepare_ok = primed_reset.ok,
		stale_yaw_moment_nm = stale_reset.loads[5],
		primed_yaw_moment_nm = primed_reset.loads[5]
	}
	print("RESET_OBSERVATION " + JSON.stringify(reset_observation))
	var reproduced: bool = installed and reset_ok and not sim.fault_reason.is_empty() \
		and fault_observation.body_rolled_back and fault_observation.aux_rolled_back \
		and fault_observation.continuous_rolled_back and not fault_observation.private_duties_rolled_back \
		and stale_reset.ok and primed_reset.ok and absf(stale_reset.loads[5] - primed_reset.loads[5]) > 1e-6
	print("Transaction gap reproduced: " + str(reproduced))
	sim.free()
	quit(0 if reproduced else 1)
```

## E.4 Numerical reference suite

Twenty cases passed and a second run generated the same JSON bytes. The expected values are frozen independent reference constants or independent formulations, not assertions about selected real hardware. The code uses the Python standard library and writes `reference_oracles.json` next to itself. It is a compact research harness, **not a production input validator, electrical solver library or Betaflight firmware port**. It covers the documented fixture domain only; runtime malformed-input, lifecycle and performance tests remain in the backlog.

| Artifact | SHA-256 |
| --- | --- |
| `reference_oracles.py` | `628a33a210269feb6db17fde2422089288bd3f7e0089eb7963d6180d7a1571ae` |
| `reference_oracles.json` | `757183c5a71c6d20ac9891d288c40569e2c78b62a3cbf38ec6f1158647303b56` |
| `source_manifest.json` | `74ac306b3a769aac87dc62c272c42c91449c56b2626912082cdb86d647e1e7e0` |

Save the exact source below as `reference_oracles.py`, then run `python3 reference_oracles.py`. Exact source-byte preservation is needed to reproduce the embedded script hash. A formatting or newline change alters that identity even when calculations agree. Do not merge this research fixture into production without the proposed API/domain/precision tests.

### Complete numerical source

```python
#!/usr/bin/env python3
"""Reproducible research-only reference calculations for the Open RC drone plan.

Run: python3 validation/reference_oracles.py
Writes reference_oracles.json next to this script and prints that complete report.
Only Python's standard library is used. The expected constants below were prepared
independently from the equations and are not measurements of an aircraft.

Actual-rate target: Betaflight 4.5.2, commit
024f8e13d4e642eb6a380308685b9ea3aa3ef1a2, src/main/fc/rc.c.
The remaining models and their numerical parameters are synthetic fixtures. A
passing result establishes arithmetic and conventions, not simulation behavior,
hardware fidelity, or equivalence to a complete Betaflight flight controller.
"""

import hashlib
import json
import math
from pathlib import Path
import sys


HERE = Path(__file__).resolve().parent
REPORT_PATH = HERE / "reference_oracles.json"
REL_TOL = 1e-10
ABS_TOL = 1e-10


def compare(actual, expected, path="root"):
    """Return mismatch descriptions, using fixed expected values and tolerances."""
    problems = []
    if isinstance(expected, bool):
        if actual is not expected:
            problems.append(f"{path}: {actual!r} != {expected!r}")
    elif isinstance(expected, (int, float)):
        if (isinstance(actual, bool) or not isinstance(actual, (int, float))
                or not math.isfinite(actual)
                or not math.isclose(actual, expected, rel_tol=REL_TOL, abs_tol=ABS_TOL)):
            problems.append(f"{path}: {actual!r} != {expected!r}")
    elif isinstance(expected, list):
        if not isinstance(actual, list) or len(actual) != len(expected):
            problems.append(f"{path}: list shape differs")
        else:
            for i, (a, e) in enumerate(zip(actual, expected)):
                problems.extend(compare(a, e, f"{path}[{i}]"))
    elif isinstance(expected, dict):
        if not isinstance(actual, dict) or set(actual) != set(expected):
            problems.append(f"{path}: dictionary keys differ")
        else:
            for key in expected:
                problems.extend(compare(actual[key], expected[key], f"{path}.{key}"))
    elif actual != expected:
        problems.append(f"{path}: {actual!r} != {expected!r}")
    return problems


def actual_rate(x, center_dps, max_dps, expo, limit_dps):
    if not -1.0 <= x <= 1.0 or not 0.0 <= expo <= 1.0:
        raise ValueError("stick/expo outside the stated rate-curve domain")
    delta = max(0.0, max_dps - center_dps)
    rate = center_dps * x + delta * abs(x) * (expo * x**5 + (1.0 - expo) * x)
    return max(-limit_dps, min(rate, limit_dps))


def matvec(matrix, vector):
    return [sum(a * b for a, b in zip(row, vector)) for row in matrix]


def solve_square(matrix, rhs):
    """Gaussian elimination with partial pivoting, independent of the known f."""
    n = len(rhs)
    augmented = [list(row) + [value] for row, value in zip(matrix, rhs)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(augmented[r][col]))
        if abs(augmented[pivot][col]) < 1e-14:
            raise ValueError("singular wrench matrix")
        augmented[col], augmented[pivot] = augmented[pivot], augmented[col]
        p = augmented[col][col]
        for j in range(col, n + 1):
            augmented[col][j] /= p
        for r in range(n):
            if r == col:
                continue
            factor = augmented[r][col]
            for j in range(col, n + 1):
                augmented[r][j] -= factor * augmented[col][j]
    return [augmented[i][n] for i in range(n)]


def make_wrench_matrix(hubs, spins, kappa):
    return [
        [1.0 for _ in hubs],
        [-hub[1] for hub in hubs],
        [hub[0] for hub in hubs],
        [spin * kappa for spin in spins],
    ]


def solve_bus(voc, pack_resistance, aux_current, loads):
    """Enumerate active sets of the ideal averaged one-quadrant DC model.

    load = (effective duty, back EMF in V, motor equivalent R in ohm, enabled).
    At exact branch equality choose the inactive side. d is bridge duty, not a
    DShot number, pilot throttle, stator-phase current, or asserted ESC protocol.
    """
    candidates = []
    for mask in range(1 << len(loads)):
        active = [i for i in range(len(loads)) if (mask >> i) & 1]
        if any(not loads[i][3] or loads[i][0] == 0.0 for i in active):
            continue
        numerator = voc - pack_resistance * aux_current
        denominator = 1.0
        for i in active:
            duty, emf, resistance, _enabled = loads[i]
            numerator += pack_resistance * duty * emf / resistance
            denominator += pack_resistance * duty * duty / resistance
        voltage = numerator / denominator
        if voltage <= 0.0:
            continue
        implied_active = [i for i, (d, e, _r, enabled) in enumerate(loads)
                          if enabled and d > 0.0 and d * voltage > e]
        if active != implied_active:
            continue
        currents = [max(0.0, (d * voltage - e) / r) if enabled and d > 0.0 else 0.0
                    for d, e, r, enabled in loads]
        pack_current = aux_current + sum(loads[i][0] * currents[i]
                                         for i in range(len(loads)))
        candidates.append({
            "bus_voltage_v": voltage,
            "motor_current_a": currents,
            "pack_current_a": pack_current,
            "active_indices": active,
        })
    if len(candidates) != 1:
        raise ValueError(f"expected one valid bus active set; found {len(candidates)}")
    return candidates[0]


def celsius_to_kelvin(celsius):
    if celsius < -273.15:
        raise ValueError("temperature is below absolute zero")
    return celsius + 273.15


def main():
    results = []

    def check(name, actual, expected, note):
        failures = compare(actual, expected)
        results.append({"name": name, "passed": not failures, "actual": actual,
                        "expected": expected, "mismatches": failures, "note": note})

    # Expected constants are frozen independently of the calculation functions.
    sticks = [-1.0, -.75, -.5, -.25, 0.0, .25, .5, .75, 1.0]
    check("actual_rates_full_curve_deg_s",
          [actual_rate(x, 200.0, 670.0, .58, 1998.0) for x in sticks],
          [-670.0, -309.554443359375, -153.609375, -62.404052734375,
           0.0, 62.404052734375, 153.609375, 309.554443359375, 670.0],
          "Pinned Actual curve; values at nine signed stick positions.")
    check("actual_zero_expo_is_not_linear",
          actual_rate(.5, 200.0, 670.0, 0.0, 1998.0), 217.5,
          "For zero expo, 0.5 stick does not give half the endpoint rate.")
    check("actual_full_expo_midstick",
          actual_rate(.5, 200.0, 670.0, 1.0, 1998.0), 107.34375,
          "Checks the fifth-power term separately.")
    check("actual_max_below_center_floor",
          [actual_rate(x, 200.0, 100.0, .58, 1998.0) for x in [-1.0, -.5, .5, 1.0]],
          [-200.0, -100.0, 100.0, 200.0],
          "The max-minus-center contribution is floored at zero.")
    check("actual_axis_rate_cap",
          [actual_rate(x, 200.0, 670.0, .58, 500.0) for x in [-1.0, 1.0]],
          [-500.0, 500.0], "A separate per-axis cap binds after the curve.")
    check("actual_deg_to_radians_per_second",
          actual_rate(.5, 200.0, 670.0, .58, 1998.0) * math.pi / 180.0,
          2.6809893556806648, "Convert deg/s to rad/s once at the boundary.")

    hubs = [(-.1, .1), (.1, .1), (-.1, -.1), (.1, -.1)]
    spins = [-1.0, 1.0, 1.0, -1.0]
    matrix = make_wrench_matrix(hubs, spins, .01)
    check("wrench_forward_frd_signs",
          matvec(matrix, [.5, 1.1, 1.3, 1.1]), [4.0, .08, .04, .008],
          "Wrench order is total positive thrust, FRD roll, pitch and yaw.")
    check("wrench_inverse_four_forces",
          solve_square(matrix, [4.0, .08, .04, .008]), [.5, 1.1, 1.3, 1.1],
          "General Gaussian elimination recovers known synthetic motor thrusts.")

    locked_inertia, rotor_inertia, omega, motor_torque = .002, .00001, 1000.0, .1
    alpha_z = motor_torque / (locked_inertia - rotor_inertia)
    rotor_accel = motor_torque / rotor_inertia + alpha_z
    body_l_dot = locked_inertia * alpha_z
    relative_l_dot = -rotor_inertia * rotor_accel
    check("rotor_total_angular_momentum",
          {"alpha_z_rad_s2": alpha_z, "relative_rotor_accel_rad_s2": rotor_accel,
           "body_momentum_rate_nm": body_l_dot, "relative_momentum_rate_nm": relative_l_dot,
           "total_momentum_rate_nm": body_l_dot + relative_l_dot},
          {"alpha_z_rad_s2": 50.25125628140704,
           "relative_rotor_accel_rad_s2": 10050.251256281406,
           "body_momentum_rate_nm": .10050251256281408,
           "relative_momentum_rate_nm": -.10050251256281406,
           "total_momentum_rate_nm": 0.0},
          "One free rotor, no external torque; signs are FRD and thrust axis is -z.")
    cross_energy_rate = alpha_z * (-rotor_inertia * omega)
    relative_energy_rate = rotor_inertia * omega * rotor_accel
    check("rotor_motor_work_with_cross_term",
          {"relative_spin_energy_rate_w": relative_energy_rate,
           "cross_term_rate_w": cross_energy_rate,
           "total_rotational_energy_rate_w": relative_energy_rate + cross_energy_rate,
           "internal_motor_work_w": motor_torque * omega},
          {"relative_spin_energy_rate_w": 100.50251256281406,
           "cross_term_rate_w": -.5025125628140704,
           "total_rotational_energy_rate_w": 100.0, "internal_motor_work_w": 100.0},
          "The body/relative-spin cross term is required for work closure.")

    voc, rp, iaux = 24.0, .05, .2
    identical = [(.5, 8.0, .1, True) for _ in range(4)]
    bus4 = solve_bus(voc, rp, iaux, identical)
    check("shared_bus_four_identical_motors",
          bus4,
          {"bus_voltage_v": 21.326666666666668,
           "motor_current_a": [26.633333333333333] * 4,
           "pack_current_a": 53.46666666666667, "active_indices": [0, 1, 2, 3]},
          "All four DC-equivalent motor loads share one common pack voltage.")
    vb = bus4["bus_voltage_v"]
    im = bus4["motor_current_a"][0]
    ip = bus4["pack_current_a"]
    check("shared_bus_and_motor_energy_balance",
          {"ocv_power_w": voc * ip, "terminal_power_w": vb * ip,
           "pack_resistive_loss_w": rp * ip**2, "aux_power_w": vb * iaux,
           "each_motor_bus_input_w": vb * .5 * im, "each_em_power_w": 8.0 * im,
           "each_motor_copper_loss_w": .1 * im**2},
          {"ocv_power_w": 1283.2, "terminal_power_w": 1140.2657777777778,
           "pack_resistive_loss_w": 142.93422222222222,
           "aux_power_w": 4.265333333333333,
           "each_motor_bus_input_w": 284.0001111111111,
           "each_em_power_w": 213.06666666666666,
           "each_motor_copper_loss_w": 70.93344444444445},
          "Pack source, terminal, heat, auxiliary, motor conversion and copper losses close.")
    mixed_loads = [(.4, 3.0, .1, True), (.5, 7.0, .1, True),
                   (.6, 20.0, .1, True), (0.0, 0.0, .1, False)]
    check("shared_bus_mixed_active_and_coast",
          solve_bus(voc, rp, iaux, mixed_loads),
          {"bus_voltage_v": 21.858921161825726,
           "motor_current_a": [57.4356846473029, 39.29460580912863, 0.0, 0.0],
           "pack_current_a": 42.82157676348548, "active_indices": [0, 1]},
          "Third motor overruns and coasts; fourth is disabled.")
    bus1 = solve_bus(voc, rp, iaux, identical[:1])
    check("one_load_versus_shared_four_loads",
          {"one_load_bus_v": bus1["bus_voltage_v"],
           "one_load_pack_a": bus1["pack_current_a"],
           "four_load_bus_v": bus4["bus_voltage_v"]},
          {"one_load_bus_v": 23.10222222222222,
           "one_load_pack_a": 17.955555555555556,
           "four_load_bus_v": 21.326666666666668},
          "Four isolated single-pack calls would report the wrong bus voltage.")

    diagonal_mm = 152.0
    adjacent_mm = diagonal_mm / math.sqrt(2.0)
    check("fixture_5_0_inch_disc_clearance",
          {"adjacent_hub_spacing_mm": adjacent_mm,
           "signed_disc_clearance_mm": adjacent_mm - 127.0,
           "zero_gap_diagonal_mm": 127.0 * math.sqrt(2.0)},
          {"adjacent_hub_spacing_mm": 107.48023074035521,
           "signed_disc_clearance_mm": -19.51976925964479,
           "zero_gap_diagonal_mm": 179.60512242138307},
          "Coplanar square-X disc envelope; zero gap is not a safety margin.")
    check("fixture_5_1_inch_disc_clearance",
          {"adjacent_hub_spacing_mm": adjacent_mm,
           "signed_disc_clearance_mm": adjacent_mm - 129.54,
           "zero_gap_diagonal_mm": 129.54 * math.sqrt(2.0)},
          {"adjacent_hub_spacing_mm": 107.48023074035521,
           "signed_disc_clearance_mm": -22.05976925964478,
           "zero_gap_diagonal_mm": 183.19722486981073},
          "A nominal 5.1-inch disc is 129.54 mm, not 127 mm.")

    def vertical_fov(hfov_degrees, aspect):
        return math.degrees(2.0 * math.atan(math.tan(math.radians(hfov_degrees) / 2.0) / aspect))

    check("fpv_horizontal_to_vertical_fov",
          {"v_fov_16_9_degrees": vertical_fov(120.0, 16.0 / 9.0),
           "v_fov_4_3_degrees": vertical_fov(120.0, 4.0 / 3.0)},
          {"v_fov_16_9_degrees": 88.50715548032275,
           "v_fov_4_3_degrees": 104.82182106205009},
          "Perspective conversion; actual engine projection needs its own test.")

    frequencies = [20.0, 40.0, 60.0, 80.0]
    sample_period = 1.0 / 240.0
    zoh_phase = [-180.0 * f * sample_period for f in frequencies]
    zoh_db = [20.0 * math.log10(math.sin(math.pi * f * sample_period)
                                / (math.pi * f * sample_period)) for f in frequencies]
    delay_phase = [-360.0 * f * sample_period for f in frequencies]
    check("zoh_240hz_phase_and_magnitude",
          {"phase_degrees": zoh_phase, "magnitude_db": zoh_db,
           "extra_full_tick_phase_degrees": delay_phase},
          {"phase_degrees": [-15.0, -30.0, -45.0, -60.0],
           "magnitude_db": [-.09944792154339814, -.4005723594894283,
                            -.9120975839632401, -1.6499597255724274],
           "extra_full_tick_phase_degrees": [-30.0, -60.0, -90.0, -120.0]},
          "Zero-order hold only; extra delay values exclude the hold's own phase.")

    kv_rpm_per_volt, w, duty, voltage, resistance = 1000.0, 1000.0, .5, 24.0, .1
    kv_si = kv_rpm_per_volt * math.tau / 60.0
    kt = 1.0 / kv_si
    emf = kt * w
    motor_i = (duty * voltage - emf) / resistance
    check("motor_kv_kt_and_ideal_bridge_units",
          {"kv_rad_s_per_v": kv_si, "kt_nm_per_a": kt, "back_emf_v": emf,
           "equivalent_motor_current_a": motor_i, "pack_motor_current_a": duty * motor_i,
           "bus_power_w": voltage * duty * motor_i,
           "em_power_w": kt * motor_i * w, "copper_loss_w": resistance * motor_i**2},
          {"kv_rad_s_per_v": 104.71975511965977, "kt_nm_per_a": .009549296585513721,
           "back_emf_v": 9.549296585513721,
           "equivalent_motor_current_a": 24.50703414486279,
           "pack_motor_current_a": 12.253517072431395,
           "bus_power_w": 294.0844097383535, "em_power_w": 234.0249374806064,
           "copper_loss_w": 60.05947225774707},
          "Kt=1/Kv only in the stated ideal reciprocal DC-equivalent convention; effective bridge duty is not DShot.")
    caught_invalid_temperature = False
    try:
        celsius_to_kelvin(-273.16)
    except ValueError:
        caught_invalid_temperature = True
    check("kelvin_is_absolute_temperature_not_motor_kv",
          {"minus_40_c_in_k": celsius_to_kelvin(-40.0),
           "plus_20_c_in_k": celsius_to_kelvin(20.0),
           "absolute_zero_k": celsius_to_kelvin(-273.15),
           "below_absolute_zero_rejected": caught_invalid_temperature},
          {"minus_40_c_in_k": 233.15, "plus_20_c_in_k": 293.15,
           "absolute_zero_k": 0.0, "below_absolute_zero_rejected": True},
          "Kelvin is K, an absolute temperature; motor Kv is a speed constant in rpm/V.")

    passed = sum(bool(case["passed"]) for case in results)
    report = {
        "schema": "openrc-dr-reference-oracles-v1",
        "scope": "Synthetic software and mathematical reference checks; not physical validation.",
        "rate_source": {"project": "Betaflight", "tag": "4.5.2",
                        "commit": "024f8e13d4e642eb6a380308685b9ea3aa3ef1a2",
                        "path": "src/main/fc/rc.c"},
        "script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "tolerances": {"relative": REL_TOL, "absolute": ABS_TOL},
        "total": len(results), "passed": passed, "failed": len(results) - passed,
        "results": results,
    }
    rendered = json.dumps(report, indent=2, allow_nan=False) + "\n"
    REPORT_PATH.write_text(rendered, encoding="utf-8")
    print(f"Reference checks: {passed}/{len(results)} passed, {len(results) - passed} failed")
    print(rendered, end="")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
```

## E.5 Complete numerical result

```json
{
  "schema": "openrc-dr-reference-oracles-v1",
  "scope": "Synthetic software and mathematical reference checks; not physical validation.",
  "rate_source": {
    "project": "Betaflight",
    "tag": "4.5.2",
    "commit": "024f8e13d4e642eb6a380308685b9ea3aa3ef1a2",
    "path": "src/main/fc/rc.c"
  },
  "script_sha256": "628a33a210269feb6db17fde2422089288bd3f7e0089eb7963d6180d7a1571ae",
  "tolerances": {
    "relative": 1e-10,
    "absolute": 1e-10
  },
  "total": 20,
  "passed": 20,
  "failed": 0,
  "results": [
    {
      "name": "actual_rates_full_curve_deg_s",
      "passed": true,
      "actual": [
        -670.0,
        -309.554443359375,
        -153.609375,
        -62.404052734375,
        0.0,
        62.404052734375,
        153.609375,
        309.554443359375,
        670.0
      ],
      "expected": [
        -670.0,
        -309.554443359375,
        -153.609375,
        -62.404052734375,
        0.0,
        62.404052734375,
        153.609375,
        309.554443359375,
        670.0
      ],
      "mismatches": [],
      "note": "Pinned Actual curve; values at nine signed stick positions."
    },
    {
      "name": "actual_zero_expo_is_not_linear",
      "passed": true,
      "actual": 217.5,
      "expected": 217.5,
      "mismatches": [],
      "note": "For zero expo, 0.5 stick does not give half the endpoint rate."
    },
    {
      "name": "actual_full_expo_midstick",
      "passed": true,
      "actual": 107.34375,
      "expected": 107.34375,
      "mismatches": [],
      "note": "Checks the fifth-power term separately."
    },
    {
      "name": "actual_max_below_center_floor",
      "passed": true,
      "actual": [
        -200.0,
        -100.0,
        100.0,
        200.0
      ],
      "expected": [
        -200.0,
        -100.0,
        100.0,
        200.0
      ],
      "mismatches": [],
      "note": "The max-minus-center contribution is floored at zero."
    },
    {
      "name": "actual_axis_rate_cap",
      "passed": true,
      "actual": [
        -500.0,
        500.0
      ],
      "expected": [
        -500.0,
        500.0
      ],
      "mismatches": [],
      "note": "A separate per-axis cap binds after the curve."
    },
    {
      "name": "actual_deg_to_radians_per_second",
      "passed": true,
      "actual": 2.6809893556806648,
      "expected": 2.6809893556806648,
      "mismatches": [],
      "note": "Convert deg/s to rad/s once at the boundary."
    },
    {
      "name": "wrench_forward_frd_signs",
      "passed": true,
      "actual": [
        4.0,
        0.08,
        0.04000000000000002,
        0.008
      ],
      "expected": [
        4.0,
        0.08,
        0.04,
        0.008
      ],
      "mismatches": [],
      "note": "Wrench order is total positive thrust, FRD roll, pitch and yaw."
    },
    {
      "name": "wrench_inverse_four_forces",
      "passed": true,
      "actual": [
        0.5000000000000002,
        1.0999999999999999,
        1.3,
        1.0999999999999999
      ],
      "expected": [
        0.5,
        1.1,
        1.3,
        1.1
      ],
      "mismatches": [],
      "note": "General Gaussian elimination recovers known synthetic motor thrusts."
    },
    {
      "name": "rotor_total_angular_momentum",
      "passed": true,
      "actual": {
        "alpha_z_rad_s2": 50.25125628140704,
        "relative_rotor_accel_rad_s2": 10050.251256281406,
        "body_momentum_rate_nm": 0.10050251256281408,
        "relative_momentum_rate_nm": -0.10050251256281408,
        "total_momentum_rate_nm": 0.0
      },
      "expected": {
        "alpha_z_rad_s2": 50.25125628140704,
        "relative_rotor_accel_rad_s2": 10050.251256281406,
        "body_momentum_rate_nm": 0.10050251256281408,
        "relative_momentum_rate_nm": -0.10050251256281406,
        "total_momentum_rate_nm": 0.0
      },
      "mismatches": [],
      "note": "One free rotor, no external torque; signs are FRD and thrust axis is -z."
    },
    {
      "name": "rotor_motor_work_with_cross_term",
      "passed": true,
      "actual": {
        "relative_spin_energy_rate_w": 100.50251256281406,
        "cross_term_rate_w": -0.5025125628140704,
        "total_rotational_energy_rate_w": 99.99999999999999,
        "internal_motor_work_w": 100.0
      },
      "expected": {
        "relative_spin_energy_rate_w": 100.50251256281406,
        "cross_term_rate_w": -0.5025125628140704,
        "total_rotational_energy_rate_w": 100.0,
        "internal_motor_work_w": 100.0
      },
      "mismatches": [],
      "note": "The body/relative-spin cross term is required for work closure."
    },
    {
      "name": "shared_bus_four_identical_motors",
      "passed": true,
      "actual": {
        "bus_voltage_v": 21.326666666666664,
        "motor_current_a": [
          26.633333333333322,
          26.633333333333322,
          26.633333333333322,
          26.633333333333322
        ],
        "pack_current_a": 53.46666666666665,
        "active_indices": [
          0,
          1,
          2,
          3
        ]
      },
      "expected": {
        "bus_voltage_v": 21.326666666666668,
        "motor_current_a": [
          26.633333333333333,
          26.633333333333333,
          26.633333333333333,
          26.633333333333333
        ],
        "pack_current_a": 53.46666666666667,
        "active_indices": [
          0,
          1,
          2,
          3
        ]
      },
      "mismatches": [],
      "note": "All four DC-equivalent motor loads share one common pack voltage."
    },
    {
      "name": "shared_bus_and_motor_energy_balance",
      "passed": true,
      "actual": {
        "ocv_power_w": 1283.1999999999996,
        "terminal_power_w": 1140.2657777777772,
        "pack_resistive_loss_w": 142.93422222222213,
        "aux_power_w": 4.265333333333333,
        "each_motor_bus_input_w": 284.000111111111,
        "each_em_power_w": 213.06666666666658,
        "each_motor_copper_loss_w": 70.93344444444439
      },
      "expected": {
        "ocv_power_w": 1283.2,
        "terminal_power_w": 1140.2657777777779,
        "pack_resistive_loss_w": 142.93422222222222,
        "aux_power_w": 4.265333333333333,
        "each_motor_bus_input_w": 284.0001111111111,
        "each_em_power_w": 213.06666666666666,
        "each_motor_copper_loss_w": 70.93344444444445
      },
      "mismatches": [],
      "note": "Pack source, terminal, heat, auxiliary, motor conversion and copper losses close."
    },
    {
      "name": "shared_bus_mixed_active_and_coast",
      "passed": true,
      "actual": {
        "bus_voltage_v": 21.858921161825723,
        "motor_current_a": [
          57.43568464730289,
          39.29460580912861,
          0.0,
          0.0
        ],
        "pack_current_a": 42.82157676348547,
        "active_indices": [
          0,
          1
        ]
      },
      "expected": {
        "bus_voltage_v": 21.858921161825727,
        "motor_current_a": [
          57.4356846473029,
          39.29460580912863,
          0.0,
          0.0
        ],
        "pack_current_a": 42.82157676348548,
        "active_indices": [
          0,
          1
        ]
      },
      "mismatches": [],
      "note": "Third motor overruns and coasts; fourth is disabled."
    },
    {
      "name": "one_load_versus_shared_four_loads",
      "passed": true,
      "actual": {
        "one_load_bus_v": 23.10222222222222,
        "one_load_pack_a": 17.95555555555555,
        "four_load_bus_v": 21.326666666666664
      },
      "expected": {
        "one_load_bus_v": 23.10222222222222,
        "one_load_pack_a": 17.955555555555556,
        "four_load_bus_v": 21.326666666666668
      },
      "mismatches": [],
      "note": "Four isolated single-pack calls would report the wrong bus voltage."
    },
    {
      "name": "fixture_5_0_inch_disc_clearance",
      "passed": true,
      "actual": {
        "adjacent_hub_spacing_mm": 107.48023074035521,
        "signed_disc_clearance_mm": -19.51976925964479,
        "zero_gap_diagonal_mm": 179.60512242138307
      },
      "expected": {
        "adjacent_hub_spacing_mm": 107.48023074035521,
        "signed_disc_clearance_mm": -19.51976925964479,
        "zero_gap_diagonal_mm": 179.60512242138307
      },
      "mismatches": [],
      "note": "Coplanar square-X disc envelope; zero gap is not a safety margin."
    },
    {
      "name": "fixture_5_1_inch_disc_clearance",
      "passed": true,
      "actual": {
        "adjacent_hub_spacing_mm": 107.48023074035521,
        "signed_disc_clearance_mm": -22.05976925964478,
        "zero_gap_diagonal_mm": 183.19722486981073
      },
      "expected": {
        "adjacent_hub_spacing_mm": 107.48023074035521,
        "signed_disc_clearance_mm": -22.05976925964478,
        "zero_gap_diagonal_mm": 183.19722486981073
      },
      "mismatches": [],
      "note": "A nominal 5.1-inch disc is 129.54 mm, not 127 mm."
    },
    {
      "name": "fpv_horizontal_to_vertical_fov",
      "passed": true,
      "actual": {
        "v_fov_16_9_degrees": 88.50715548032275,
        "v_fov_4_3_degrees": 104.82182106205009
      },
      "expected": {
        "v_fov_16_9_degrees": 88.50715548032275,
        "v_fov_4_3_degrees": 104.82182106205009
      },
      "mismatches": [],
      "note": "Perspective conversion; actual engine projection needs its own test."
    },
    {
      "name": "zoh_240hz_phase_and_magnitude",
      "passed": true,
      "actual": {
        "phase_degrees": [
          -15.0,
          -30.0,
          -45.0,
          -60.0
        ],
        "magnitude_db": [
          -0.09944792154339814,
          -0.4005723594894283,
          -0.9120975839632401,
          -1.6499597255724274
        ],
        "extra_full_tick_phase_degrees": [
          -30.0,
          -60.0,
          -90.0,
          -120.0
        ]
      },
      "expected": {
        "phase_degrees": [
          -15.0,
          -30.0,
          -45.0,
          -60.0
        ],
        "magnitude_db": [
          -0.09944792154339814,
          -0.4005723594894283,
          -0.9120975839632401,
          -1.6499597255724274
        ],
        "extra_full_tick_phase_degrees": [
          -30.0,
          -60.0,
          -90.0,
          -120.0
        ]
      },
      "mismatches": [],
      "note": "Zero-order hold only; extra delay values exclude the hold's own phase."
    },
    {
      "name": "motor_kv_kt_and_ideal_bridge_units",
      "passed": true,
      "actual": {
        "kv_rad_s_per_v": 104.71975511965977,
        "kt_nm_per_a": 0.009549296585513721,
        "back_emf_v": 9.549296585513721,
        "equivalent_motor_current_a": 24.50703414486279,
        "pack_motor_current_a": 12.253517072431395,
        "bus_power_w": 294.0844097383535,
        "em_power_w": 234.0249374806064,
        "copper_loss_w": 60.05947225774707
      },
      "expected": {
        "kv_rad_s_per_v": 104.71975511965977,
        "kt_nm_per_a": 0.009549296585513721,
        "back_emf_v": 9.549296585513721,
        "equivalent_motor_current_a": 24.50703414486279,
        "pack_motor_current_a": 12.253517072431395,
        "bus_power_w": 294.0844097383535,
        "em_power_w": 234.0249374806064,
        "copper_loss_w": 60.05947225774707
      },
      "mismatches": [],
      "note": "Kt=1/Kv only in the stated ideal reciprocal DC-equivalent convention; effective bridge duty is not DShot."
    },
    {
      "name": "kelvin_is_absolute_temperature_not_motor_kv",
      "passed": true,
      "actual": {
        "minus_40_c_in_k": 233.14999999999998,
        "plus_20_c_in_k": 293.15,
        "absolute_zero_k": 0.0,
        "below_absolute_zero_rejected": true
      },
      "expected": {
        "minus_40_c_in_k": 233.15,
        "plus_20_c_in_k": 293.15,
        "absolute_zero_k": 0.0,
        "below_absolute_zero_rejected": true
      },
      "mismatches": [],
      "note": "Kelvin is K, an absolute temperature; motor Kv is a speed constant in rpm/V."
    }
  ]
}
```

## E.6 What the adversarial review changed

The final handoff incorporates corrections discovered during independent review:

1. **Sub-tick drive cut:** the sampled controller remains fixed, but a qualified event-addressable terminal latch reaches subsequent stages; endpoint-only motor cut is not equivalent.
2. **Reset preparation:** current body-only `prepare_reset` is insufficient for the proposed detached full frame; the plan names a new opt-in same-owner full-frame seam and separate-owner replacement path.
3. **Command cursor:** checkpointed state commits consumption before observers; later tape-prefix reclamation is only storage housekeeping.
4. **Guard scope:** registered finite state can be checked/restored; arbitrary captured object/global mutation is not generally sandboxed.
5. **Recovery:** non-integrating device checks stage OFF→ON/Continue evidence; centered virtual throttle has an explicit zero-throttle recovery proposal committed only on the resumed tick.
6. **Race paths:** validate against the final composed physical endpoint, not only `body_filtered`; root direction needs accepted path evidence and uncertainty.
7. **GO and reset rules:** check fresh pre-inhibit throttle at the exact GO boundary; failed GO stays inhibited; crash/reset aborts the complete attempt, whose terminal record is retained.
8. **Event order and display:** tie adjudication does not reorder physical dynamics; native pacing, input-buffer ownership and physical latency remain separately measured.
9. **Crash telemetry:** preserve the interval's sampled command/allocation evidence while the event latch cuts effective drive; record both and replay the terminal checkpoint.
10. **Gate edges:** require the complete root-position uncertainty interval to clear the aperture, not just a nominal chord crossing point.
11. **Terminal results:** retain the old result in a bounded checkpointed outbox atomically with reset, then persist asynchronously with visible failure, capacity and retry rules.
12. **Stopped-rotor allocation:** use the finite quadratic-law coefficient ratio rather than evaluating torque/thrust as 0/0 at zero speed.

These are planning/specification corrections. No proposed runtime fix, controller, gate director or new schema was implemented during this task.

## E.7 Source closure manifest

The minimal project configuration used for the recorded run was:

```ini
config_version=5
[application]
config/name="DR source-only verification"
[physics]
common/physics_ticks_per_second=240
common/max_physics_steps_per_frame=12
[rendering]
renderer/rendering_method="gl_compatibility"
```

Below are the exact copied source hashes; the project file and isolated probe are separately shown above. This manifest describes source scope, not full-app resources or a package manifest.

```json
{
  "repository": "bultodepapas/OpenRCsimulator",
  "commit": "7bff78490f9af5c1664f47c8ba865a92b3430920",
  "purpose": "Unmodified dependency closure for existing DR test; minimal project omits product/autoload/assets",
  "files_sha256": {
    "tests/test_dr_multirotor_kernel.gd": "07ff8b6bf554d6f0a97b8683d344c6174f77b8d5cf2b5e11e4e9656ea4535a3a",
    "tests/law_properties.gd": "99b8e9bba837b231909b652f5b40f809f1d275422982844d77093909c58d6ba9",
    "physics/multirotor/rotor.gd": "9210aaf70c8a85d15b378da5594131331e957f20d68741d10f3e7997894abb0e",
    "physics/math3d.gd": "4c2eee2f8ef4d38352014628ba9665fdd4f50d4b1edcf90ffc680c7763de8832",
    "physics/multirotor/plant.gd": "c11a5900c02d311fd8222917123ebcdae931bff25bf861d8a5a1969f4b8a0ce4",
    "physics/multirotor/airframe.gd": "50787469821ef326206a42d37eb604edcaf9a4d9b529b2bf5896c79e8be1a9af",
    "physics/multirotor/powertrain.gd": "027ab3cc2cf3f446d70eec96a7c7f00d7781a1e15230fce2b50a6ef6df53d39b",
    "sim/vehicle_model.gd": "e065d8b8b52c223c0260ac3da3976fd528755d5052d8245ae070cccd4b287174",
    "physics/rigid_body.gd": "4e9a11a45bc6a442a6bf987d4efebbca11a893e5b6451d22e2d74b1b2905e5ce",
    "physics/wind_config.gd": "4824223a8fb6c85ad6edd347a24d74bf1d5152451db6263d4eba2a621a981f66",
    "physics/wind_spatial_config.gd": "f7a05dc2990092aa9558e941249d50eee7b5c7d33a4e6b583c474fd3218d534d",
    "physics/wind_thermal_field.gd": "2e2b33f3cf0ae0247d7bef8a8ff75ea03d814dbd4d4eb1c2a60ae6c9a71e075e",
    "physics/wind_spatial_presets.gd": "82b5388be121f8538e529f7227d0b22fbceb5cee4b80f7a98046a6cf19667a72",
    "physics/atmosphere.gd": "800bc5b098b4e51c4758e3a0cf1e505e9ab0cc451fbbca102b3a0094e2bf89be",
    "physics/wind_field.gd": "dbf50f0a45cbe55a3e225a4a162001a271f6df25de95adc2d7665500425ea776",
    "physics/wind_spatial_field.gd": "873800debb660a65567182f639bfa47e996b15ec67d31250e1d6b6d2d757e644",
    "sim/environment.gd": "e1bea3c5e9bf78edb552c26f91f9ff5235313a2735e81a6d847fa778d0973fd1",
    "physics/ground_vehicle/airfield_track.gd": "8e7098ab347384eef95340f4e6a884930b8e4e5a3f6e48feff488e0c7061a0e2",
    "physics/ground_vehicle/airfield_course.gd": "5164d012df12ddd0579a54ab8c71419c7a856bc443aacbe5a0d9684350f7e746",
    "physics/ground_vehicle/vehicle_environment.gd": "06cc677241aae081be431ec4348fa8366cffb5cdf8b234262fe6d964910c38ad",
    "physics/ground_vehicle/vehicle_dynamics.gd": "6b4dfc1a90e44a2153771d98d052cc20af4d06a1b4b6e9e174027a392aaffb46",
    "physics/generalized_coordinates.gd": "dfc38f8a268930683538b182c4c3d07c3aca48bec16bd2ea6bd4aeb4cbaef47d",
    "physics/integrator.gd": "6bac447d3744c59813c3fabc567e0edc21f24680138a12ea317a441e1a5de11d",
    "physics/lake_surface.gd": "89d6b91689429181f4147bea607dd04a67e2f5edd88b439359bf72579120a19f",
    "physics/ground_contact.gd": "19784e88b2d4b0f8e4164a5d8a82c3d6774f9cb169ba7bd97f1ab1af687fb6b6",
    "physics/ground_terrain.gd": "3703ba2ed59d77b710b9b83e1b1991c878255072f1f0ac7adabd345697b96a97",
    "physics/ground_wheels.gd": "fa2c2473b26ee093d0e4fef2c1b232877751e9564ebce5725d0f5eb368099d87",
    "physics/ground_surfaces.gd": "0bc7f3638920841a294690c81b5b19d90bfb14431bf6f7788e6f2ac708758128",
    "physics/ground_support.gd": "c2e1b42f05f3cef25a7ed2a908acd672878c81557611393c005c4621a993dd9e",
    "physics/aircraft_data.gd": "ae2ced8856cdd9f1fd478db60e7b69f9e7d06465cf53c56be3dd158896a75358",
    "physics/turbine.gd": "a4a7ae297adb894423b052021075da37d1667c2c2ba40afb370c792b1be093b0",
    "physics/mass_inventory.gd": "1fa317ae0258b4d48e1d6e14396b3e3adc6b29e31e1082ec6a0565b20bf1366d",
    "physics/fuel_properties.gd": "eabd2f37920f83936e869d28b1be5975d8d329e98906fe52b0da4af5cdece014",
    "physics/battery/esc_supervisor.gd": "df32dc65f89501f8ebe07c173abe821a8a5c569c79c97bbd003c9629b2e58c5d",
    "physics/battery/battery_data.gd": "d0649c7113284496c3257a10313e697f201452c514d28a098c179eba090efc3c",
    "physics/glow/installation.gd": "743669589c65ac083aa32f5bccf899ef5039f2f9476f943786cec59b28f59593",
    "physics/glow/carburetor.gd": "2f172faf92565467067df370293052d2ac253c4d68631e597c9986d58dc42e8a",
    "physics/glow/fuel_feed.gd": "d90e14139fcfc98dd724f7c97f2e5c6d403db59ed935477cd1dc0cd4e81d8101",
    "physics/glow/fuel_mass.gd": "43187d7495fcc2f1d19acfc511c8de8a7512b87cf094616e87ff4c2e47cb4f55",
    "physics/fixed_datum_body.gd": "bb0c9ec1238acbbe4b786db4e54ae61a647658b3656f36257a7de7824d715e1e",
    "physics/glow/profile.gd": "ea77427d916a75163ac66bbb6361d0339aeae6572d77989fab996df58ddba522",
    "physics/intended_hull_support.gd": "c4e9c16ddb9a99a383799bc96df3b051f86a695ac9b44e418171e4be67780819",
    "physics/hull_contact.gd": "95c4b969ef54daa2d14ff2846d55dc55447790fe0e8aef6e2b290966b5029c67",
    "physics/effective_mass.gd": "3ef462e14bc65ebcf4a99a78b8a064b9ec07715aaba60cd1fe30ab7453f9949f",
    "physics/wheel_profiles.gd": "bdb76ff17b575b19eb0374375fcd62a10c4f6df2a99a74bc816c08094097d2a0",
    "physics/aircraft_ground_profile.gd": "b51fa509a7c9685444f3cdf9cf27ed864dd6a1c25f38ab2eb5a54c324f790af2",
    "physics/control_actuators.gd": "1eed4b39dbd194ef26f55295250e6187023d562c1a788df9a0bae31d80b62988",
    "physics/propulsion.gd": "e85734749f6f1fae5ad61858a267d4393b9b21bd2f0c85afd0dc19946f816f6f",
    "physics/battery/pack_ecm.gd": "ff5dd20f3c2ac83e747a12126198d29e4f7dc4bc35fd35f2ee23a0fe60ae89d9",
    "physics/electric_motor.gd": "4abd3455f49d59dc26e51843225a617fcb36f0c74ff4fabc81d2f1a015b5de10",
    "physics/electric_supply.gd": "ebe6a97d19194bc397ab91cefa4a4afcb1a174b64b53efd741f8b41e22c81229",
    "physics/glow/operating_point.gd": "fe8f7718eaae59cb17279cb3b4fc2d4072e7e80e2e84376d0250ef55d7f45e7b",
    "physics/glow/propeller.gd": "24b7dfb2803b4e546891bcccbc5aa549fdc1352ea46152280ddcb1999618215e",
    "physics/glow/source.gd": "57f729133ee2ab08843ab5adcdf06c1ca5bbed845f25655340118e5011dd0338",
    "physics/glow/four_stroke.gd": "a9d9a4151713955e2a3247349527f5181a0821b10770f4ae6f196ed1b3e22978",
    "physics/glow/two_stroke.gd": "10dc8b59d92e5335c7d5167adb9c4f29978618591db8fe8928ba21e45480b622",
    "physics/rotor_coupling.gd": "fa52e266fe523f7d9eae6aaaf20f0f72cf0efad07978d6bbddd8df5b6f623330",
    "physics/wheel_geometry.gd": "219c9654f8cab79bfeb518c0994117eb7387857f9d0f02f03e6c1a573ac5d60b",
    "physics/normal_compliance.gd": "7fdda97336cffec821a420d0666e6f8eb530ae77c628e767b212b1d31590d785",
    "physics/wing_polar.gd": "0bac361ded5d5276464121c531dcd21f4b5168ee91d1656382821376d105cf56",
    "physics/aero.gd": "c0141d609c9e12866dba457c04a412a5609c0ca637222d2057e71771b522ebb8",
    "physics/flaps.gd": "9dbbc35cb2e3edef04359c31fe18a91dd0f4d8b23732cc31b69176afe1cdbff9",
    "physics/ground_effect.gd": "62fc76291c36c3899e65660b216ebf22aff5fa54516d7544be88f1ec8d1f9e3a",
    "physics/control_surfaces.gd": "8c0054a2abe900225d0e0fafa7b3df3586e9d1de0e6dca5457be11635a0dd447",
    "physics/physical_identity.gd": "af80165c937ea486858265da2c6d560d534319c399dbf8d2326c49547c83f628",
    "physics/aircraft_contract.gd": "379746e005fa50a9f488552c4e34f531578a84c616ee35313e5aa85170315278",
    "physics/aircraft_modules.gd": "b6601333e649e5a3bba4a0b5640c34a73d2d26d63b6e2b6022455d94f37370d5",
    "data/lake_loader.gd": "793ade2b5c65695491489bb10cacf3562ca44488353c492fcf8551ddf1da51e6",
    "data/field_loader.gd": "3b6f797fa1a85f235a48eb1f3c5069d244ece212c6c1c2f21b3921ac749419e1",
    "physics/ground_vehicle/course.gd": "e2b47e8f339311647342c25018e71093f1cf200071a2d92d4396974a2dc7747e",
    "sim/simulation.gd": "56953f116a293a984cbc5315b9cd97dc156e63cdd98c12fbc041e6df6baaab92",
    "physics/event_step.gd": "92a5a1ed9d0505efb6b0db4397543a923b6088f22cdf2155c84ca56559141cc3",
    "physics/event_bracket.gd": "92e5bd10e7eb49c0e69d16cab49dcaae12a5c253b6c2a305770896e754300ddf"
  }
}
```

## Settings follow-up evidence

The later settings investigation is recorded in [07](07_BETAFLIGHT_INAV_SETTINGS_RESEARCH.md) and [09](09_SETTINGS_EVIDENCE_AND_REFERENCE_PROBE.md), with the proposed implementation in [08](08_SETTINGS_SCHEMA_IMPORT_AND_TESTS.md). It uses BF 2026.6.2 and INAV 9.1.0 source pins, 34 investigations and a scoped 14-evaluation extracted throttle experiment. The 15 existing kernel checks and 20 synthetic cases in this document retain their original scope and were not rerun during that follow-up. Current firmware research does not imply a new OpenRC implementation or upgrade the older BF 4.5.2 rate-only compatibility target.
