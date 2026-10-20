# P-51D ground and lifecycle audit

2026-10-12 · **Status: audit and four frozen-app probe runs complete; physical acceptance remains open.** Prefix: P51-15.

## Method

[`ground_probe.gd`](../../../../research/p51/p51-15/ground_probe.gd) runs the P-51 through the real `FlightSession` reset, input, crash-check and `Simulation.step()` paths on the default field. It supports `--hz=240|480` and writes JSON with `--output=<path>`. Reports label all outcomes as model predictions; `physical_validation` is always false.

The parked fixture uses the P-51 gear contact geometry to set its three-point attitude, settles for three seconds at idle with aft stick, then restores the threshold position and zeros body velocity and rates. This is a deterministic research fixture, not a selectable product runway launch. The cases cover engine-off and idle ground motion, the same throttle-ramp takeoff with rudder free and with heading hold, and a 1.3 Vs / 4° approach with flare and rollout. Metrics include finite state, contact count, crash/fault, ground distance, speed, heading, liftoff/touchdown, and rudder-command peaks.

Lifecycle evidence checks the selected airborne reset, a 240-tick session-checkpoint replay for exact tick-boundary equality (1 s at 240 Hz; 0.5 s at 480 Hz), and a deliberate P-51 hull-contact crash followed through the session's 1.5-second automatic restart countdown. The restart must reproduce the trimmed start state exactly. The probe preserves the session's reset auxiliary layout and calls `_settled_continuous()` for the installed state; it stops on unsupported anchored-stiction or turbulent-weather layouts instead of inventing their state. A case crash remains visible in JSON as an incomplete outcome. Final review hardened both script and runner to require all cases complete, in addition to numerical/reset/replay checks; incomplete cases now exit nonzero.

## Interpretation limits

The production runway-start route still refuses the P-51: it is currently restricted to the Ugly Stik and requires gear stiction. P-51 ground tests therefore synthesize their start pose and cannot establish that a player can launch this model from the product runway. The reported three-point contact count comes from the configured spring gear; it does not measure tire behavior. The aircraft has no modeled brakes, flaps, retracts, fuel burn, or measured engine/propeller transient map. Pilot guidance and modeled contact/crash events are reported explicitly; no test result here is physical flight validation.

## Run evidence

The [ground results](ground-results.md) link all baseline/candidate outputs, logs and identities at both rates. All five cases completed without faults or unintended crashes; checkpoint and crash/restart checks passed exactly. A guided takeoff demonstrates only the specified feedback pilot, while the rudder-free case preserves the model's own yaw response. Contact-only path length is rate-sensitive during a landing rebound; gross rollout displacement is reported separately.

See the [P-51 guide](../../../P51-PLAN.md), [`p51_envelope_base.gd`](../../../../app/tests/p51_envelope_base.gd), and [`test_p51_ground.gd`](../../../../app/tests/test_p51_ground.gd).
