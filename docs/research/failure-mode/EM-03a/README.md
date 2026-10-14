# EM-03a — Shared actuator mechanics and surface observations

Date: 2026-10-14. Scope: first EM-03/AS-11 control-mechanics slice, plus EM-02/09's aircraft-specific availability detail. The [active failure-mode plan](../../../plans/failure-mode.md) retains the full implementation and qualification gates. [EM-00](../EM-00/README.md) supplies the earlier hardware/source review; [EM-05](../EM-05/README.md) records the delivered power-loss mechanisms.

## Why this boundary

The current normalized aircraft model contains three logical servo positions: roll, pitch and yaw. `controls.surface_ids` identifies four surfaces but does not specify independent servos, linkages or a mixing graph. A mesh with two elevator hinges still uses one physical elevator angle. Inventory names and visual hinges cannot establish new hardware relationships.

Existing aerodynamic code already accepts different left/right aileron angles. Its global terms use the respective roll/yaw derivatives, and local wing strips read the angle for their own side. The horizontal tail remains an aggregate element with one elevator deflection. Independent elevator halves require side-specific geometry, forces and moments before admission.

This increment establishes a common numerical kernel and the actual-surface observation boundary without changing catalog aircraft topology. Independent positions in software fixtures are explicitly experimental inputs, not a new selectable aircraft capability or a claim of measured servo behavior.

## Code boundary

- `app/physics/control_actuators.gd` owns the existing sampled rate-limit law. `Commands.rate_limit()` remains its compatibility entrypoint. The scalar hot path preserves the original operation order; it introduces no new lag, friction, spring or servo-load law.
- The pure `step_normalized()` batch path accepts independently owned positions, demands, nominal rates and optional rate factors. Zero factor holds the current actual position. It validates the complete input and returns a detached candidate, or an empty array on rejection. It owns no clock, random generator, commit or checkpoint; those remain the caller's responsibility.
- `ControlSurfaces.independent_deflections_deg()` maps the explicit fixture order `[aileron_right, aileron_left, elevator, rudder]` to actual trailing-edge degrees, including differential down-going throw. Every position is positive trailing-edge up/right; conventional roll supplies `[roll, -roll]` for the ailerons.
- `FlightSession.surface_angles_deg()` exposes actual accepted surface angles. Physics and presentation share the same auxiliary-to-surface conversion. Scripted visual captures retain their explicit command path.

Production flight retains its three servo entries, current rate factors and ordering, and existing checkpoint/trace layouts. The failure catalog and resolved-plan versions do not change. Future independent actuators must own separate accepted state and declare their topology through the aircraft contract before joining the random pool.

## Player-facing availability

The failure settings screen adds a read-only detail for the selected aircraft. Home derives it from validated source data; Pause uses the accepted session model, including Workshop variants. Reading details neither starts a session nor draws a failure. The catastrophic checkbox controls whether receiver-link loss appears in the displayed eligible pool. The view also explains why an unsupported source shutdown is excluded; unavailable model data does not produce an invented list.

The existing probability, Apply/Cancel, notice and next-flight semantics are retained. This view describes supported injected mechanisms, not an active hidden incident or a recovery guarantee.

The bounded list accepts keyboard focus through Tab. Arrow keys, Page Up/Down and Home/End scroll it; Back or Escape returns to the unchanged settings draft. Escape from settings retains the existing cancellation behavior. English and Spanish use the same layout.

Reviewed 1280 × 720 captures: [Spanish Pause settings and entry point](captures/settings-es-pause.png), [English electric eligibility](captures/availability-en-electric.png) and [Spanish turbine exclusion](captures/availability-es-turbine-exclusion.png). The longer exclusion view scrolls; the key-event test verifies that the last event can be reached and made visible.

## Acceptance and remaining work

Godot 4.7.2 stable through WSL. These focused checks distinguish existing-flight preservation, analytical kernel behavior, asymmetric software-fixture loads/poses, and real aircraft qualification. The last category remains open. No aircraft data, aerodynamic coefficients or golden flights were changed by this increment.

| Check | Result | Scope |
| --- | --- | --- |
| Before/after fleet capture | 512/512 exact serialized matches; both captures passed 833 checks | Eight catalog airplanes, with unconfigured and explicitly zero-probability failure modes, 32 varied-input steps each at 240 Hz. Body/previous state, aux, continuous state, modes, loads, inputs, surface outputs and hinge poses match. |
| `test_control_actuators.gd` | 47 checks, 0 failed | Frozen scalar float64 samples, independent analytic motion bounds, no overshoot, zero-rate-factor jam, invalid-input atomicity, constant-demand timestep split, differential signs, one-sided aerodynamic roll response and actual model hinge poses. |
| `test_control_surface_observation.gd` | 50 checks, 0 failed | All eight aircraft expose detached actual angles matching aerodynamic input; saved-state restore restores observations. The real main render adapter consumes asymmetric observed angles while scripted captures keep explicit commands. |
| `test_controls.gd` / `test_servo.gd` / `test_control_surfaces.gd` | 17 / 6 / 26 checks, 0 failed | Existing command, servo and surface mapping behavior. |
| `test_failures.gd` | 5,150 checks, 0 failed | Existing failure mechanisms, versioned records, selection and transactions. |
| `test_failure_session.gd` / `test_failure_power.gd` | 99 / 88 checks, 0 failed | Real session onset/rejection, healthy fleet and power-demand adapters. |
| `test_failure_shutdown.gd` | 206 checks, 0 failed | All supported source-loss families, accepted/rejected ticks, energy and replay. |
| `test_failure_availability_ui.gd` | 62 checks, 0 failed | Eight Home selections, a distinct accepted-model Pause fixture, eligible-event filtering, translated exclusion reasons, bounded cards, Tab focus and real key events reaching the last list item. |
| `test_failure_ui.gd` / `test_failure_routes.gd` | Pass / 52 checks, 0 failed | Existing settings/notices behavior and real Home/Pause flight transitions. Route regression ran after AppRoot integration; the new availability test covers the final list-navigation changes. Spanish settings, notices, event labels and exclusion text are checked. |
| `test_golden.gd` | Four flights, 0 failed | Unmodified healthy reference flights. |
| Editor import; transcendental guard and self-test | Pass | Integrated resources/scripts and the existing float64 math boundary. |

The before/after artifacts have the same SHA-256, `e8a68892dd0ce5a17c80aacd6b636b1443feeae540c110b024d8b1e9abd93b89`. The ignored local capture/comparison files live under `.tools/em03/`. They contain post-step samples at ticks 1–32, including tick zero's body in the first sample's `previous_state`; no complete standalone tick-zero boundary was captured. This short varied-input comparison establishes byte preservation for those cases, not a long-flight or target-hardware performance qualification.

Permanent tests use the standard [focused Godot invocation](../../../TOOLS.md). For example:

```sh
.tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path app \
  --audio-driver Dummy --script res://tests/test_control_actuators.gd
.tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path app \
  --audio-driver Dummy --script res://tests/test_control_surface_observation.gd
.tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path app \
  --audio-driver Dummy --script res://tests/test_failure_availability_ui.gd
```

The full app suite, exported packages and target-machine performance were not run for this slice. Captured poses and finite loads do not qualify independent installed servo/linkage hardware or pilot recovery.

Next: an authored actuator-to-surface topology and strict loader/schema agreement; separate accepted positions with reset/checkpoint/rejected-tick coverage; per-aircraft single-aileron qualification; then independent tail elements for split elevators. The next topology slice must preserve the conventional compatibility path and cannot infer hardware from display names.
