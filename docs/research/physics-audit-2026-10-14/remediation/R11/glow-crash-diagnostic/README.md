# Accepted-step Glow crash fixtures

2026-10-15. This test-only repair replaces manufactured callback-only crashes with accepted `Simulation.step()` ticks. No runtime source, aircraft data, collision threshold, crash-energy threshold, or golden was changed.

## Diagnosis and contract

The old fixtures wrote `sim.previous` and `sim.state` and called `FlightSession._physics_process()` directly. That bypassed Glow's terminal hull decision in `Simulation.post_step_joint`. On the captured Glow fixtures, direct callback classification selected `gear_limit/main_left` at roughly 0.2085–0.20894 m compression against 0.12 m travel, even though the independent hull terminal calculation found the 20 m/s hull impact at index 7, 1 mm penetration, with the `impact` rule. The raw direct-call and accepted-tick outputs are retained in [diagnose-02.log](diagnose-02.log); the original test sources are retained as `*.before.gd`.

The fixture now submits a one-tick descending contact through `Simulation.step()`. Glow's incoming-energy decision is checked using the documented previous-state continuous-mass properties (`_contact_mass_sampler(...).call(0.0)`) supplied to `HullContact.terminal_at_properties`; it does not substitute endpoint wet mass or static mass. The render test separately checks the accepted impact tick, available crossing, crossing pose, and detected endpoint. A second accepted tick that begins in deep contact verifies the unavailable-crossing fallback. Full per-event/resource interpolation remains outside this fixture and belongs to R05-B.

The rendered hull point's ground-plane residual is at most `3.0e-8 m`. Contact-to-event-point differences reach `3.815e-6 m` after conversion to Godot `Vector3`; the assertion now uses a scale-aware allowance of `2e-6 m + 2 float32 epsilons × world-coordinate scale` for that render-space comparison. The ground-plane check remains `2e-6 m`. The observed crossing pose is 0.051485–0.067773 m from the accepted endpoint across the eight tested aircraft, so the test distinguishes TOI rendering from endpoint rendering.

## Focused verification

Both runs used Godot `4.7.2.stable.official.ed1daf0bf` and the R11 candidate app at `/home/bulto/openrc-r11-b09-r05b-20261014-03/app`. Only the test script was loaded from the working tree; project resources and runtime code came from the candidate. The scripts, logs, and hashes are:

| Test | Result | Test SHA-256 | Log |
| --- | ---: | --- | --- |
| `test_crash_integration.gd` | 179 checks, 0 failed | `DF80F84B0A799E6E353C70F5633D1694FF5498E29AE61BD1F7473FB8478524DA` | [linux-focused-crash-integration-02.log](linux-focused-crash-integration-02.log) |
| `test_crash_pose.gd` | 226 checks, 0 failed | `453E6E526218FFFC33DCC4938A28A5DEAB2DCF09F2C970C9FB0DC57FDED303BB` | [linux-focused-crash-pose-05.log](linux-focused-crash-pose-05.log) |

Reproduction command pattern (substitute the test name and matching `.accepted-step-*` script):

```sh
timeout 240 /home/bulto/openrc-r11-b09-r05b-20261014-03/.tools/Godot_v4.7.2-stable_linux.x86_64 \
  --headless \
  --path /home/bulto/openrc-r11-b09-r05b-20261014-03/app \
  --audio-driver Dummy \
  --script /mnt/c/DEVELOPMENT/OpenRCsimulator/docs/research/physics-audit-2026-10-14/remediation/R11/glow-crash-diagnostic/test_crash_pose.accepted-step-05.gd
```

The matching integration script is `test_crash_integration.accepted-step-02.gd`. Failed iterations remain preserved in `linux-focused-crash-integration-01.log` and `linux-focused-crash-pose-01.log` through `-03.log`; they expose the remaining direct-callback fixture, a test-harness label error, and the measured float32 boundary. `linux-focused-crash-pose-04.log` is also green; `-05.log` additionally records crossing-to-endpoint separation values.

The source-after reconciliation against `linux-rate-guard-candidate-before.json` is [linux-focused-candidate-after.json](linux-focused-candidate-after.json): zero paths added or removed and one changed path, `app/tests/check_math_sensitivity.py` (`9b5dd202…` before, `9715901a…` after). This is the queued H7 return-inventory guard: it checks the expected four early returns plus terminal return before instrumenting `local_flow_weight`, so a branch-shape change cannot silently bypass the rate guard. It is test instrumentation only; it changes no runtime source or physics. The crash test scripts were external overlays and were not written into the candidate. Do not use `linux-focused-after.json` for this comparison; it used the unoverlaid archive manifest and therefore reports the candidate's intentional overlays.

These focused tests establish the software path and render contract for the current candidate. They do not establish aircraft crash realism or replace the outstanding canonical full-suite gate.
