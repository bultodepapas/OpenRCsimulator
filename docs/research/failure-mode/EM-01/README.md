# EM-01 — Initial failure-mode implementation

Date: 2026-10-13. Scope: software verification of the first logical-actuator and throttle-demand slice. [Current scope and remaining phases](../../../plans/failure-mode.md#implementation-checkpoint--current-scope); [source review](../EM-00/README.md).

## Contracts and numerical boundary

`app/failures/config.gd` accepts only integer probability 0–100 and boolean catastrophic/notice settings. `catalog.gd` exposes eight ordinary events and one opt-in receiver outage. `runtime.gd` resolves one immutable plan using private versioned xorshift32 draws, bounded rejection sampling, seed, exact timestep and resolved parameters. Notification preference is retained but excluded from physical plan identity.

The runtime stages effects once per simulation step. Actual servo positions are captured for jams. The session applies command bias, servo rate reduction and throttle-demand changes before their existing physical responses. RK stages read the same candidate. The session's first `stepped` connection commits the runtime; `faulted` discards pending state. Neither a derivative nor rendering can consume RNG state or announce an unaccepted event. The healthy 0% path retains its existing arrays, state layout and checkpoint formats.

The v10 failure checkpoint retains top-level `simulation`, stores the previous flight format in `failure_physics_format`, and includes a self-contained `failure_state`. It rejects malformed plan identities, clocks, control values and mismatched timesteps before mutating the destination. Older failure-unaware readers reject its version. Restoring an ordinary checkpoint clears injected failure state. The visual checkpoint envelope recognizes v10 and retains its complete physics payload.

## Tests executed

Godot 4.7.2 stable; Windows native and/or Linux binary through WSL as noted. This implementation did not re-record golden flights.

| Check | Result | Scope |
| --- | --- | --- |
| `test_failures.gd` | 5,150 checks, 0 failed; native Windows and WSL | Strict settings; 0/100 boundaries; seed repeatability; opt-in catalog; bounded mechanisms; trim versus jam; radio hold; rejected candidates; self-contained snapshots and corrupt-data refusal. |
| `test_failure_session.gd` | 93 checks, 0 failed; final WSL run, 240 Hz | Seven-airplane zero-probability parity for 12 actual steps each; 20-second roll-jam onset; late rejected physics step before onset; no ghost event; recovery and single accepted notification; notification observers see a complete restorable checkpoint; jam hold, exact checkpoint continuation, visual wrapper and restore back to ordinary physics. |
| `test_failure_power.gd` | 74 checks, 0 failed; native Windows | A capped-demand adapter fixture versus healthy demand through real `sim.step()` for all seven aircraft: exact body/aux/continuous/load equality with raw pilot demand retained. Independent glow cutoff stays latched under stuck-high demand without additional fuel consumption. This isolates routing, not onset scheduling. |
| `test_failure_launch.gd` | 24 checks, 0 failed; WSL | Direct-route argument validation, reproducible seed, no preference reads, hidden notices, actual incident card and reset/menu visibility. |
| `test_failure_ui.gd` | Pass; WSL | Preference defaults/round-trip/refusal; slider and integer field synchronization; checkbox defaults; Apply/Cancel; Spanish labels; pause summary and postflight explanation. |
| `test_failure_routes.gd` | 54 checks, 0 failed; final WSL verbose run | Actual Home → settings → flight → Pause → End → new flight; Apply changes current notices and next-flight settings, Cancel discards every draft field; unsupported rotorcraft CLI flags are refused. Home, Pause, failure card and debrief fit the declared 1280×720 logical viewport. |
| `test_ui_pause.gd` | 46 checks, 0 failed; WSL | Existing pause/restart/end navigation, keyboard reachability of Failures, and six returns to Home with stable node counts. |
| Failure-menu rendered capture | Pass; Xvfb | English and Spanish at 1280×720 and 1920×1080, plus the final Spanish Pause hint at 1280×720; card fits viewport, Apply focus, Escape/Back. Local captures are under `.tools/failure-ui-captures/`. |
| `test_checkpoint.gd` | 92 checks, 0 failed; WSL | Existing physics checkpoint and reload behavior. |
| `test_checkpoint_integrity.gd` | 149 checks, 0 failed; WSL | Existing malformed-state/atomicity guards. |
| `test_glow_session.gd` | 140 checks, 0 failed; WSL | Existing finite-glow starts, running flight and state. |
| `test_glow_flight_physics.gd` | 82 checks, 0 failed; WSL | Existing physical fixtures retain their input contract. |
| `test_glow_stage_reuse.gd` | 2,005 comparisons, 0 failed; WSL | Includes 2,000 byte-exact existing load checks. |
| `test_controls_reference.gd` | Pass; WSL | Every handled key, including aileron trim, is in the shared Help reference. |
| `test_trace_metadata.gd` | 297 checks, 0 failed; WSL | Existing healthy trace metadata remains valid. |
| `test_trace.gd` | 19 checks, 0 failed; WSL | Existing trace format and recording behavior. |
| `test_golden.gd` | 4 flights, 0 failed; final WSL run | Final shared-tree replay, after concurrent aircraft-data/reference updates; maximum position difference about 1.5e-14 m. The isolation check below separately verifies the original model and references. |
| Transcendental guard and self-test | Pass | Existing physics/sim math boundary; changed simulation/failure files contain no float32 vector/matrix state types. |

The 240 Hz integration test has an explicit 180-second suite timeout to allow slower machines; it advances a real 20-second onset instead of changing production timestep or bypassing the scheduler. The full UI route test also allows 180 seconds for two flight/scenery rebuilds.

The final full UI route run exited 0 in approximately 70 seconds, without script errors or ObjectDB leak warnings. An earlier run reported 24 objects at shutdown; the verbose final run did not reproduce that warning, and its cause is not established. The existing pause test also exited cleanly with stable Home node counts. The headless route fixture declares a 1280×720 content scale because the dummy display otherwise reports a 64×64 viewport.

### Golden-flight isolation during concurrent work

`test_golden.gd` against the live working tree reported four mismatches. Concurrent edits to `app/data/aircraft/jensen_ugly_stik_60.json` changed the aerodynamic reference point (0.1209 to 0.0844 m), tail incidence and rate derivatives. These edits belong to the climb/trim work, not EM.

To isolate the failure implementation, the unchanged Stik JSON was read from commit `73e28b75` into an ignored disposable file and the same golden test was run against that data with the **new session/failure code still loaded**. All four golden flights passed, with maximum position difference about 3.6e-15 m and matching auxiliary/discrete state. This track changed neither shared aircraft files nor golden records.

The aircraft-data track subsequently updated its golden records. A final replay against the current shared tree also passed all four flights. This distinguishes the initial data/reference mismatch from the failure-mode integration. The full `app/test.sh` release gate is not claimed by this report.

## Scope limits

- Software tests establish scheduling, state integrity and adapter behavior. They do not establish that a particular airplane can recover from every selected event.
- The first mechanism model uses the three logical actuators already present. It does not assert independent left/right servo hardware or simulate a disconnected surface's hinge dynamics.
- Throttle ceiling/hold are command-path failures. Turbine idle is not flameout; prescribed fuel remains prescribed. Existing finite-glow consumption and independent stop behavior remain owned by the glow installation.
- Radio loss uses one explicit training receiver profile. It is separate from physical transmitter unplug/focus-loss safety behavior, and does not model loss of receiver electrical power.
- Wing separation and split-elevator mechanisms remain in the active plan with their structural/topology dependencies. No wing mesh or force was removed as a substitute.
- Full exported-build qualification, target-hardware timing, damage aerodynamics and pilot trials remain open. The working tree contained concurrent sky, vehicle and aircraft work; those changes are outside EM ownership.
