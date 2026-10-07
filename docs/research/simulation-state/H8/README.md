# H8 — Bounded physics state and checkpoints

2026-10-06 · **Status: complete; 90 focused checks and full Phase H regression pass.** Main-line ROADMAP H8. [H8a](../H8a/README.md) established stage time.

## Contract

| State | Owner and update rule | Reset / checkpoint / failure |
| --- | --- | --- |
| Position, body velocity, attitude, body rates | `Simulation.state`, 13 float64 values; `RigidBody.derivative` owns their derivatives at the RK stage state and absolute stage time | Reset normalizes attitude. Checkpoint accepts finite, already-normalized state. A failed tick restores the previous committed boundary |
| Engine RPM and actual servo positions | `Simulation.aux`, four float64 values in FlightSession; `pre_step` advances once before k1, frozen through k4 | Session reset initializes trim values. Snapshot and rollback include every entry. Existing split propulsion semantics remain until G2a |
| Pilot input | `Simulation.inputs`, four post-shaping/post-trim values, sampled before stepping | Frozen during the synchronous stage evaluations; checkpoint replay supplies these samples directly |
| Engine mode | `Simulation.modes[0]`, int64 0/1, exposed by `FlightSession.engine_running` | Explicit tick-boundary update; reset derives it from the start scenario; failed steps restore the committed mode |
| Clock and continuity | Tick, previous body state, last k1 loads, stop-at-tick | Included in checkpoint/rollback; reset returns tick to zero and retains the caller's stop condition |
| Physical configuration | Mass, full inertia, gravity, fixed timestep; resolved aircraft model and ground surfaces | Mass/inertia/gravity roll back on failure. A run owns its fixed timestep: changing the global engine rate faults without reinterpreting committed time; reset adopts an explicitly changed rate. Restore rejects mismatched configuration or timestep; callbacks stay with the existing session |
| Fault/pause diagnostic | Simulation fault string, paused state | Fault stays sticky until valid reset or explicit checkpoint restore; restoration pauses and emits no fake completed-step sample |

Loads and rotor-momentum callbacks are read-only evaluators. Derivatives must not advance sampled state, modes or random generators. The successful boundary is committed before `stepped` is emitted; recorders therefore observe a completed tick. New sampled entries must be initialized at reset and have a fixed layout during a run. New coupled continuous variables require an explicit derivative/layout change with their consumer; the RK kernel already supports an inert extra entry without changing body arithmetic. No generic component registry is introduced.

`Simulation.checkpoint()` returns detached typed arrays. Native `var_to_bytes` / `bytes_to_var` encoding preserves their exact float64 bits on this build. JSON and CSV are not exact checkpoint containers. The format is `openrc-simulation-checkpoint v1`, wrapped by `openrc-flight-checkpoint v1` with a SHA-256 identity of the exact resolved aircraft/ground Variant encoding. This identity checks compatibility within the current build; it is not DATA-3's raw input-file hash or a portable asset-package format.

`FlightSession.restore_checkpoint()` validates everything before changing state, closes an active recorder before moving the clock, clears the crash presentation, disables live input sampling, and remains paused. The replay driver feeds `sim.inputs` and calls `sim.step()`. This is a bounded **physics replay** API, not a saved interactive session: menu holds, physical radio arming/calibration and raw keyboard accumulators are not deserialized. Restoring across an engine/layout/configuration change needs an explicit future migration.

Reload prepares the candidate before mutation. A failure during the subsequent reset also restores the previous aircraft, trim, command state and complete physics boundary. Normal reset and reload initialize the same trim state and engine mode as before H8.

## Verification

`app/tests/test_checkpoint.gd`: 90 checks, including every missing field, wrong types, nonfinite arrays, incompatible timestep/mass/layout, malformed quaternion, detached ownership and native encoding round trip. Injected pre-step/k1/k2/k3/k4 failures restore sampled/discrete/body state, clock, trace loads and stop condition. Invalid reset restores clock/modes/mass properties. An unused sampled/discrete entry and an unused continuous RK entry leave body trajectories unchanged.

All four catalog aircraft replay exactly from a mid-flight checkpoint after control slew and an engine-off transition, even after reset. Changed ground configuration and invalid engine mode are rejected atomically. Successful reload restores trim auxiliaries and engine mode; an injected late reload failure retains a flyable previous state. Existing session guards pass 32 checks. H8a supplies the coupled analytic stage-time/order proof.

```sh
$(app/get-godot.sh) --headless --path app --script res://tests/test_checkpoint.gd
$(app/get-godot.sh) --headless --path app --script res://tests/test_session_guards.gd
```

Sources: [simulation](../../../../app/sim/simulation.gd), [session](../../../../app/sim/flight_session.gd), [tests](../../../../app/tests/test_checkpoint.gd). Original implementation/tests, repository MIT license. This verifies state ownership and numerical replay; it does not validate aircraft handling.

Commit message: `H8: checkpoint and roll back bounded physics state; prove 90 checks and four-aircraft exact replay`

Final integration evidence: [suite, scene/resource checks and source fingerprints](../H8/integration-verification.json).
