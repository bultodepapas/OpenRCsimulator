# EM-05 — Capability-bound propulsion failures

Date: 2026-10-14. Scope: EM-02 profile/record support and EM-05 finite-glow/electric source-loss adapters. This extends the [initial logical-control mode](../EM-01/README.md). The [active plan](../../../plans/failure-mode.md#implementation-checkpoint--current-scope) owns current controls and remaining phases; [EM-00](../EM-00/README.md) retains the dated primary-source review. This increment reuses the repository's existing powertrain laws; it adds no measured shutdown data or new physical-validation claim.

## Implemented mechanisms

`glow_fuel_cut` invokes the finite-glow lifecycle cut on detached RK stage state and commits it with the accepted continuous state. Combustion and delivered fuel cease; tank fuel remains, and the shaft/propeller retains inertia, passive loads and existing thermal behavior. The persistent training cause refuses the external starter. This is an immediate modeled fuel/combustion interruption, not a calibrated residual-fuel or flameout transient.

`electric_drive_loss` disables the motor source through the existing coupled shaft/electrical evaluator. Motor current and driven torque cease while the rotor can coast or windmill. An OCV/resistance pack still supplies its modeled auxiliary current; a fixed-voltage installation has no finite charge state. The event neither disconnects the receiver nor adds active braking or regeneration.

Both events leave pilot throttle and control inputs available. Existing source/shaft/wake observables supply the resulting loads, audio and traces; there is no extra final-thrust multiplier. Each is an ordinary-pool training event, which does not imply guaranteed recoverability from any altitude or attitude.

## Eligibility and compatibility

| Catalog aircraft ID | Resolved profile | Additional source-loss event |
| --- | --- | --- |
| `jensen-das-ugly-stik-60` | `logical-controls-v1` | Excluded: legacy RPM response has no qualified shutdown law. |
| `gp-extra-300s-60` | `logical-controls-v1` | Excluded: legacy RPM response. |
| `p51d-mustang-120` | `logical-controls-v1` | Excluded: sampled shaft behavior lacks a continuous rundown law. |
| `sebart-avanti-s-a200-p100rx` | `logical-controls-v1` | Excluded: turbine flameout/rundown and ECU relight remain AV work. Idle is not shutdown. |
| `stik-glow-61fx-2t` | `finite-glow-v1` | `glow_fuel_cut` |
| `stik-glow-55ax-2t` | `finite-glow-v1` | `glow_fuel_cut` |
| `stik-glow-fs64v-4t` | `finite-glow-v1` | `glow_fuel_cut` |
| `turbo-lumber-evolution` | `electric-drive-v1` | `electric_drive_loss` |

The resolver consumes validated normalized propulsion data, not IDs. The newly added 61FX inherits its profile without an EM solver branch. `Catalog.availability()` exposes supported IDs and exclusion reasons for future detail UI; that view is not delivered here. The existing eight ordinary control/throttle events and optional radio loss remain available on every listed model. Each physical profile adds one event, so an airplane has at most ten eligible events including radio loss, rather than all eleven definitions in the global catalog.

New plans use catalog version 2 and `openrc-failure-plan v2`, with the exact profile included in identity. Uniform selection uses only the eligible pool. V1 plans retain catalog version 1, their eight/nine-event pool, RNG progression and seed mapping. The same seed can therefore select different events across profiles or plan versions. Historical snapshots remain readable without a redraw; unknown versions/profiles fail closed. The flight checkpoint wrapper remains v10, without a physics-array migration.

## Transaction and saved-state boundary

The runtime prepares one pending onset before integration. `_pre_step` stages the source mode inside Simulation's existing modes transaction; no RK evaluator mutates accepted runtime or consumes RNG. A rejected step restores modes, body, continuous state and loads, then rolls back the pending event. Accepted state is remembered before stepped observers publish the incident. This ordering also preserves an off source if the first tick after activation faults.

An active-cut checkpoint must have source mode off; glow additionally requires stopped lifecycle state, reason `cut`, and zero transported fuel. Restore validates these relationships and the destination profile before mutation. Reload refuses a changed profile while an episode is bound. Repeat resets the physical start and retains the same resolved plan. New-flight selection and the three existing Home/Pause settings remain unchanged.

## Verification

Godot 4.7.2 stable, Linux binary through WSL, production 240 Hz for session/onset tests. No golden flight was re-recorded and no generated aircraft data was changed by this increment.

| Check | Result | Scope |
| --- | --- | --- |
| `test_failure_profiles.gd` | 119 checks, 0 failed | All eight catalog entries, identity-independent capability derivation, eligible pools, 0/100 settings, notices excluded from physical identity, strict v2 records and v1 restore. |
| `test_failures.gd` | 5,150 checks, 0 failed | Existing logical mechanisms, deterministic scheduling, rollback and historical records. |
| `test_failure_session.gd` | 99 checks, 0 failed | All eight healthy baselines, real onset/rejection, complete observed checkpoints and exact continuation. |
| `test_failure_power.gd` | 88 checks, 0 failed | All eight real demand paths, raw-input retention and finite-glow cutoff precedence. |
| `test_checkpoint.gd` / `test_checkpoint_integrity.gd` | 92 / 149 checks, 0 failed | Existing checkpoint/reload and malformed-state atomicity. |
| `test_glow_session.gd` / `test_glow_flight_physics.gd` | 140 / 82 checks, 0 failed | Existing finite-glow session and physical fixtures. |
| `test_electric_session.gd` / `test_electric_battery_session.gd` | 86 / 103 checks, 0 failed | Existing electric shaft and finite-pack behavior. |
| `test_glow_audio.gd` / `test_glow_trace.gd` | 42 / 276 checks, 0 failed | Existing audio lifecycle and trace observables; not a listening qualification of the new event. |
| `test_failure_launch.gd` | 24 checks, 0 failed | Direct configuration and optional incident card. |
| `test_ui_language.gd` | Pass; 491 Spanish catalog texts, none untranslated | Both new labels/hints and existing Home/direct-route language isolation. The stale route-only fixture now uses a live `--quick-flight` instead of invalid zero-duration trace arguments. |
| `test_golden.gd` | Four flights, 0 failed | Existing healthy flight references. |
| Transcendental guard and self-test | Pass | Shared float64 math boundary. |

Commands follow [TOOLS](../../../TOOLS.md). A focused invocation is:

```sh
.tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path app \
  --audio-driver Dummy --script res://tests/test_failure_shutdown.gd
```

For interactive reproduction, choose the aircraft and keep the flight airborne long enough for its resolved onset. With catastrophic admission off, seed `6` selects the additional source-loss event on either supported family:

```sh
.tools/Godot_v4.7.2-stable_linux.x86_64 --path app -- --quick-flight \
  --aircraft=stik-glow-61fx-2t --failures=100 --failure-seed=6
.tools/Godot_v4.7.2-stable_linux.x86_64 --path app -- --quick-flight \
  --aircraft=turbo-lumber-evolution --failures=100 --failure-seed=6
```

The onset clock still requires accepted airborne ticks at least five metres above terrain with uncompressed wheels. A seed selects an episode; it does not bypass these conditions. A short flight may end before activation.

## Remaining gates

Independent ailerons/elevator halves need the shared actuator/topology extension. Turbine flameout/relight, intermittent power, receiver supply loss and in-flight wing separation remain outside this increment. Propeller rundown and glow residual-fuel transients inherit existing estimated parameters; pilot recovery, target-hardware timing, new event listening/capture checks and packaged delivery remain unqualified. The software tests prove deterministic implementation behavior, not real RC failure frequencies or emergency-training effectiveness.
