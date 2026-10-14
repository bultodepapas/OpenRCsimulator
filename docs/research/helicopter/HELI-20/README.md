# HELI-20 — Ground trainer implementation

Date: 2026-10-14. Engine: Godot 4.7.2 stable, native Windows. This report records software implementation and experiments after the [ground/3D audit](../HELI-16/ground-3d-audit-2026-10-14.md). [Current controls](../../../HELICOPTER.md) and [plan §14.8](../../../plans/helicopter.md#148-implementation-status--2026-10-14) are the operating guide and remaining work register.

## Delivered boundary

Normal trainer play now starts with four loaded skids on an authored flat pad, zero rotor speed/wake, motor disarmed and hold engaged. Explicit arm and hold release start a 12 s torque ramp. Collective produces liftoff; there is no runtime position/height autopilot. Airborne practice remains explicit and preserves its six-state rotor fixture. The ground session adds eight float64 bristle states; body, rotor, wake, contact and controller derivatives share RK stages.

The separate HX-700 profile has independent physical identity and body-rate FBL control, but is **laboratory-only**. It is not a published second playable helicopter. Its release gates require identified FBL/head dynamics, achieved servos, freewheel and power-off energy, signed inversion qualification, its own ground lifecycle and aircraft-specific response evidence. The supplied neutral articulated asset is preserved; this change does not animate command values as achieved mechanics.

## Pad and support

[Ground-support report](ground-support.json) retains authored quantities, force/moment residuals and conservative placement calculations. CG is N=6/E=0 m, yaw +90°, height 0.10778963675 m. The runway is N=9…21/E=−50…50 m. This is beside its longitudinal midpoint, not among the decorative parked aircraft. The nearest parked center is 33.658 m away; no airplane start or parked model moved.

Four equal reactions of 20.1036325 N compress the configured springs by 2.01036325 mm. Force residual is about 2.27×10⁻¹³ N and moment residual zero. The authored 6×6 m `rotorpad` material uses the field's shared physics/rendering surface source; its reserved rolling-factor value selects zero analytic relief. Friction is 0.7, with the skid factor 0.5 giving μ=0.35. These are estimates, not measured turf properties. The historical ±4 mm grass relief could not support the requested all-six-residual normal-only equilibrium; there is no hidden raised plane.

The main/tail-disc and skid reach bound is 1.04351 m. With the explicit 0.75 m margin, remaining runway clearance is 1.20649 m, barrier-post-box clearance 1.54290 m and nearest conservative parked-mesh clearance 30.13999 m. The authored envelope is larger at 1.25 m plus margin. Boom/fuselage geometry, full rotational scenery sweeps and the complete camera/aircraft matrix remain separate gates; these figures are simulator layout checks, not real-world field separation standards.

The [day pilot capture](pad-pilot.png) shows ground support and nose/tail orientation. The [night capture](pad-night.png), with full moon and airfield lighting, is dark: it proves the route renders but does **not** qualify night readability. Both were inspected at 1280×720 using native OpenGL on the RTX 3090; logs retain engine output.

## Model changes and experiments

- **Static tangential support:** eight north/east bristle strains provide bounded friction on the flat pad. With normal reaction N, stiffness K, damping C, velocity v and strain z, `a=min(1, μN/|−Kz−Cv|)`, `F=a(−Kz−Cv)`, `zdot=a v−βz`. Thus `F·v + d(K|z|²/2)/dt = −aC|v|²−Kβ|z|² ≤ 0`. The 100 s⁻¹ relaxation bound avoids a stiff near-unloaded division; separated memory decays over 0.2 s and applies no adhesive force. Other surfaces retain the previous sliding law. The ideal static yaw capacity is 3.653271 N·m.
- **Spool experiment:** the first 4 s torque ramp exceeded that yaw capacity and rotated the aircraft about 155°. The selected 12 s smooth ramp keeps the tested spool displacement below 0.518 mm and yaw below 0.938°. This is an estimated startup response, not an identified ESC/engine calibration.
- **Ground yaw compensation:** the original limited yaw integral could supply about 0.003 rad, versus roughly 0.121 rad of tail hover bias, and the first liftoff continued yawing. The trainer now derives a calm-air 3 m hover reference at the selected density and scales its tail bias by achieved collective up to the reference. Actual wind still enters every flight stage. The integral does not wind up while grounded. Legacy airborne behavior without the new paired reference keys is unchanged.
- **Low RPM:** bounded dimensional main/tail startup estimates retain actual crossflow and blend into the existing flight equations. Startup and blended metadata do not claim identified aerodynamics. Blended force/moment totals use actual loads; unavailable coefficients/decompositions are absent rather than stale end-member values.
- **Rotor stop:** a bounded full-tick adapter prevents negative shaft stages, locates the stop and integrates the remaining time. Static zero-speed shaft friction prevents numerical restart chatter. Hold is zero drive torque, not a rotor brake or a qualified one-way freewheel.
- **Mode/input ownership:** arming requires hold, zero blade pitch within 1°, centered cyclic/yaw, a ready controller and explicit resume. Hold release is refused while paused/lost. Releasing standard throttle cut never starts the motor. A pitch-curve jump above 0.5° requires a second action without moving the pilot's stick.

## Repeated ground flights

The [test pilot](../../../../research/helicopter/ground_start/cycles.gd) sends only the normal four input axes; it never edits body pose, velocity or forces after initialization. Each condition runs ten consecutive ground→spool→takeoff→hover→land→hold→stop cycles in one session, without scene reload or body reset. It lands before cutting power and physically coasts to exact zero rotor speed. The repeated gust phase is intentional, with the global wind clock retained between cycles.

| Condition | Passed cycles | Simulated time | Max hover height error | Max touchdown down speed | Max spool displacement / yaw |
| --- | ---: | ---: | ---: | ---: | ---: |
| [Calm](cycles-calm.json) | 10/10 | 849.175 s | 0.02601 m | 0.01832 m/s | 0.509 mm / 0.938° |
| [Steady](cycles-steady.json), 3 m/s from 90° | 10/10 | 832.467 s | 0.02013 m | 0.01946 m/s | 0.514 mm / 0.891° |
| [Gusts](cycles-gusts.json), same base, +1 m/s horizontal/+0.2 m/s up | 10/10 | 842.133 s | 0.12751 m | 0.06934 m/s | 0.518 mm / 0.895° |

Gust duration/period/delay are 4/12/2 s. Gates were peak altitude 0.9–1.5 m, horizontal radius below 2.5 m, hover error below 0.15 m, touchdown speed below 0.35 m/s, actual contact before shutdown, exact final zero RPM and disarmed hold. All 30 pass; maximum horizontal radius was 1.49852 m. Reports retain 1 Hz samples of all 27 body/rotor/contact values, inputs and lifecycle. This covers these wind fixtures, not every speed/direction selectable by the product, turbulence or a human pilot's handling.

The shared tree changed during the long runs: another track added an unconnected `before_step` signal/emission in `Simulation`; helicopter physics/session sources stayed unchanged. [Before](cycle-source-sha256.json) and [after](final-cycle-source-sha256.json) hashes are retained. [Three fresh complete cycles](final-cycle-parity.json), one per condition, pass and exactly reproduce every cycle-0 report value and retained 1 Hz state/control sample (84/83/85 samples). Sources remained stable during that recheck. This distinguishes the earlier loaded source snapshot from current shared integration rather than claiming the tree was frozen.

[Five-second startup refinement](refinement.json) compares common endpoints at 240/480/960 Hz for all three conditions. Maximum 240-vs-960 errors were 5.90×10⁻¹¹ m position, 1.67×10⁻¹⁰ rad/s body rate and 3.26×10⁻⁷ rad/s shaft speed; quaternion geodesic error rounded to zero at the reported precision. This smooth startup passes the plan's engineering gates. High-slip bristle refinement and analytic rotor-stop cases are separate unit checks. It does not qualify aggressive 3D maneuvers or all contact events.

## State, replay and verification

Checkpoint v3 includes the selected pad/start, power/ramp, all 14 continuous ground states and accepted-tick main/tail phases. Restore validates before committing and pauses. Trace v2 contains 46 columns, including all eight bristle strains; metadata declares the selected layout and control reference. Airborne records use zero bristle columns. Historical checkpoints are explicitly refused rather than guessed.

[Native regression batch](checks/verification.json): **38 suites passed**, including every then-current `test_heli_*.gd` and nine input/UI/field suites; 8,051 explicitly numbered checks, plus suites using other reporting formats. [Follow-up checks](followup-checks/verification.json) cover the expanded 32-check render/replay audit, controller actions/profiles, RC input and unchanged airplane goldens/replay. The [17-check helicopter action test](controller-lifecycle.log) exercises the real scene action dispatcher and lifecycle refusal paths. The earlier render batch's 26-check result is superseded by the 32-check follow-up.

The [native all-script parse](parse-all.json) checked 822 scripts with no syntax error. Its source-stability guard flagged one concurrent edit to `tools/flight_log_cli.gd`; [the targeted recheck](parse-followup.json) passed that file and the newly added helicopter action fixture with stable hashes. [Final render checks](render-final.log) retain 32/32 after suppressing the identified-envelope warning during expected cold-start/coast lifecycle states; telemetry still records the estimated regime.

Ground-session checks include 60 s rotor-off rest with zero drift, 60 s coast to exact zero, aborted spool, repeated hold, malformed future-ramp atomic rejection, mode confirmation, pad invalidation and exact body/continuous/phase replay in disarmed, armed-hold, spooling, governed and stopped-hold states. Kernel checks cover passive contact, no adhesion, wind startup, startup/flight blending, finite dynamics, gearing and torque limits.

The actual AppRoot route with injected B/H/W keys produces the same complete checkpoint SHA-256 at 30/60/144 fps after 3,360 ticks:

`6ed56b3ee49bd25ce1cb140f51bce0443fbc89f9c75cf934a6d9a17058d182bc`

[30 fps](cadence-30.log), [60 fps](cadence-60.log), [144 fps](cadence-144.log). Some fixture exits report ObjectDB cleanup warnings; no script error or cadence/state failure occurred. These headless frame schedules establish deterministic sampling, not GPU frame-rate acceptance.

The attempted [full WSL suite](full-suite.log) passes rotor reference/schema freshness stages, then stops in the model LF/CRLF clone test because it is running from a Windows CRLF checkout. [The same 14 model tests pass natively](models-native.log). WSL also required an LF runner and pinned binary path because the checkout's shell shebangs contain CRLF. This is not a release-wide green `app/test.sh`; use the documented fresh LF Linux checkout for that gate. No golden was re-recorded to hide a change.

## Performance

[Profile and source snapshot](performance.json), [raw JSON](samples.json) and [CSV samples](samples.csv) measure 10,080 accepted complete `session.sim.step()` calls at 240 Hz, including the session observer, excluding setup and trace recording. Warmup is 120 ticks; percentiles use nearest rank. This was the 24-logical-CPU Windows development host under concurrent track work, not an isolated H15 qualification run.

| Regime | Samples | p50 µs | p95 µs | p99 µs | Max µs |
| --- | ---: | ---: | ---: | ---: | ---: |
| Stopped pad | 2,400 | 2,022 | 2,553 | 3,303 | 6,196 |
| Complete 12 s spool | 2,880 | 2,063 | 2,904 | 3,379 | 6,356 |
| Governed on pad | 2,400 | 2,024 | 2,841 | 3,543 | 13,515 |
| Legacy airborne hover | 2,400 | 1,201 | 1,596 | 1,871 | 10,095 |

The ≤500 µs whole-tick gate is unmet. No tick-rate reduction, force clamp or stale cross-stage cache was used to claim a speedup. [Earlier rejected profiling attempts](diagnostics/profile-attempts.json) retain the setup and source-change reasons; only the stable-hash run supplies this table. Rendered scene timing, input latency and VFX budgets remain open.

A [disposable contact optimization](optimization/README.md) reused the terrain/material lookup within the same stage. Two AB/BA runs retained exact per-tick body/auxiliary/continuous/phase bytes over 51,840 measured A+B ticks. The second run reduced the apparent spool/governed median gain to 8/1 µs and made stopped contact slower; the airborne control also varied. It is **not integrated** because a stable speedup was not demonstrated. Raw samples, source hashes, candidate diff and the rejected harness attempt are retained.

## Reproduce

From the repository root, with the pinned native engine:

```powershell
$heliGodot = '.tools/Godot_v4.7.2-stable_win64_console.exe'
python research/helicopter/ground_start/verify.py --godot $heliGodot --out .tools/heli20-repeat/checks
python research/helicopter/ground_start/parse_all.py --godot $heliGodot --out .tools/heli20-repeat/parse.json
& $heliGodot --headless --path app --script ../research/helicopter/ground_start/cycles.gd -- --case=calm --cycles=10 --out=C:/DEVELOPMENT/OpenRCsimulator/.tools/heli20-repeat/cycles-calm.json
# Repeat with --case=steady and --case=gusts; keep each complete report.
& $heliGodot --headless --path app --script ../research/helicopter/ground_start/refinement.gd -- --out=C:/DEVELOPMENT/OpenRCsimulator/.tools/heli20-repeat/refinement.json
& $heliGodot --headless --path app --fixed-fps 60 --script ../research/helicopter/ground_start/cadence.gd
python research/helicopter/ground_start/profile.py --help
python research/helicopter/xcell/derive.py --check
python research/helicopter/xcell/test_derive.py
```

Use fresh output paths and retain source hashes. Run performance samples in isolation when assessing a target-host budget. Software tests and this estimated trainer's successful cycles do not establish physical validation of an X-Cell, the visual HX-700 or a full aerobatic model.
