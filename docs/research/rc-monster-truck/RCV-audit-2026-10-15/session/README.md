# Session, input, and damage audit

Audit date: 2026-10-15. Scope: `app/sim/ground_vehicle/session.gd`, `app/input/ground_vehicle_input.gd`, and `app/physics/ground_vehicle/vehicle_damage.gd`.

## Findings and fixes

Checkpoint event validation previously accepted any event dictionary with a string `type`, an in-range `tick`, and finite numeric values. A self-hashed checkpoint containing an event the session never emits could be restored; exact replay then discarded that event. The validator now accepts only the emitted `damage`, `jump`, `landing`, `braking_distance`, and `manual_recovery` schemas. It checks exact fields, finite and bounded values, tick/time agreement, and nondecreasing event time. This is consistency validation for an editable checkpoint with an unkeyed digest, not authentication.

The valid `braking_distance` event contains `start_tick` and `end_tick`, not a single `tick`. A 480-tick throttle run followed by full braking emitted this event but produced a checkpoint that the former validator rejected. The current schema treats `end_tick` as the event time. JSON decoding may represent integer ticks as finite integral floats, so validation accepts those values and restore normalizes the tick keys back to integers. The regression replays the same braking tape and checks that state, damage, controls, and regenerated events match.

Native checkpoints recorded the C++ backend identity and the environment script artifact, but not the GDScript integration source that calls the backend. Session solver identity now includes the `vehicle_dynamics.gd` artifact hash and its `gdscript_source` or `gdscript_remapped_bytecode` kind for every backend. Rehashed checkpoints with either a changed hash or a different artifact kind are rejected. Checkpoints predating this field are not accepted under the stricter solver identity; the current solver v5 already changes the identity used for these runs.

No reproducible control-arming, damage-energy, impact-episode, recovery, or reset defect was found in this scope. The ground-control tests cover held-input resume and gamepad/keyboard re-arming. Damage tests cover supported no-wear motion, collision damage, replay, active impact checkpoints, repair through recovery, and reset. The complete control tape remains intentionally unbounded so an active session can retain exact replay; its packed representation is about 27.6 MB per simulated hour. Recording itself is capped at ten minutes.

## Verification

- `test_rcv_session.gd`: 130 checks, 0 failed. Covers the braking checkpoint, strict event-schema mutations, recovery transaction behavior, JSON checkpoints, and integration-artifact hash/kind mutations.
- `test_rcv_damage.gd`: 175 checks, 0 failed.
- `test_rcv_damage_session.gd`: 19/19 passed.
- `test_rcv_effects_activity.gd`: 19 checks, 0 failed.
- `test_controller_ground.gd`: 22/22 passed.
- `test_rcv_input.gd`: 32 checks, 0 failed.
- `test_rcv_powertrain.gd`: 9/9 passed, including braking to rest without reversal and 240/480 Hz agreement.
- `research/rc-monster-truck/audit-2026-10-15/session/checkpoint_event_probe.gd`: the normal braking checkpoint restores; a self-hashed unknown event is rejected without changing state.

The session probe and its machine output are in the adjacent `research/rc-monster-truck/audit-2026-10-15/session/` directory. These checks validate software behavior; they do not calibrate the damage energy model or establish physical accuracy.
