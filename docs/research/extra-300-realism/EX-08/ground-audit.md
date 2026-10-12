# EX-08: Extra 300S ground-handling probe

Status: baseline 240 Hz and changed-build 240/480 Hz probes complete; physical qualification remains open. Step: EX-08a.

## Scope

[The standalone probe](../../../../research/extra-300/ex06/ground_probe.gd) measures parked, taxi, takeoff, and exploratory landing behavior through the current Extra `FlightSession` and `Simulation` tick path. It runs at 240 Hz by default; `--hz=480` is available for a deterministic time-step comparison. It records finite state, faults/crashes, gear contacts, wheel rim speeds, ground travel, runway-axis distance, speed, heading, tail-up/liftoff, rudder command, engine RPM, and touchdown/sink metrics as JSON.

The scenarios are engine-off and modeled-idle parking; taxi with left and right rudder; full-power takeoff with neutral pitch/rudder; takeoff with heading hold and a speed-gated shallow pitch command; and a feedback-guided powered approach, flare, and touchdown. Engine-on cases begin at the model's target idle RPM; the takeoff pilot ramps throttle over 1.5 seconds. Guidance settings are named in the JSON and are probe choices, not manual-derived speeds or acceptance limits. The landing case is exploratory until both app snapshots complete without crashes or faults and the resulting time histories have been reviewed.

## Ground-start method

The current Extra gear has the applied `WheelProfiles` radii, wheel inertias, spin-relaxation times, and no-brake declarations. The flight session uses those profile values and stores rim speeds in `sim.continuous` beginning at `FlightSession.wheel_index()`. The probe uses `FlightSession._settled_continuous()` when installing each scenario so the wheel slots and any wash/shaft state keep the session's live layout; it does not replace the session's auxiliary array with the legacy four-value P-51 layout.

`GroundStart.solve()` requires stiction anchors, while the actual Extra gear has no stiction or brake model. The probe does not add a fake breakaway guard, brake, or anchor spring. For fixture initialization only, it reuses the current `GroundStart` engine-off acceleration path on the unmodified model with an empty anchor array (the `Ground.loads` no-stiction path) and enhanced wheel contact enabled. It seeds the pose from the loaded Extra's own main and tail contact points, then a 3-variable Newton solve adjusts down position, roll, and pitch until world-vertical acceleration and world angular accelerations about north and east are zero. This uses the actual engine-off gear forces and does not create persistent wheel anchors or run `GroundStart`'s idle-thrust stage.

The probe rejects a pose that misses any of the three contacts, puts the CG at or below the NED datum, exceeds ±30° pitch/roll, or fails the vertical/roll/pitch acceleration constraints. It reports the other acceleration components because free, unbraked wheels have no static tangential hold. The solver residual is the maximum absolute component across linear acceleration (m/s²) and angular acceleration (rad/s²), so those units are mixed. The solved pose is a quiet initial condition, not a fully stationary equilibrium or accepted runway-start solution. Cases with setup errors or zero completed simulation ticks make the probe exit unsuccessfully.

The current 240 Hz run gives the reason for the residual distinction: the solver and the real `FlightSession` reset produced identical six-component body loads (zero component-wise difference), with zero wheel rim speeds and zero session anchors. The solver's constrained residual was `4.19e-14`; actual world vertical acceleration was `8.91e-15 m/s²` and world north/east angular accelerations were `4.19e-14` and `-2.87e-15 rad/s²`. The remaining actual horizontal accelerations were `+0.01357 m/s²` north and `-0.01101 m/s²` east, with `-0.06719 rad/s²` yaw acceleration. The three contact points sampled different deterministic terrain slopes: main-left `(-0.00298, +0.00395)`, main-right `(-0.00117, -0.00108)`, and tail `(+0.00306, -0.00090)` for north/east slope. The 1 mm runway micro-relief is analytic and estimated, not surveyed; with no brakes or stiction, it can create horizontal/yaw acceleration at a zero-velocity pose. The probe therefore records this as an unheld terrain residual and measures its subsequent motion instead of concealing it with a fake brake or widening a full-equilibrium threshold.

## Current-app 240 Hz results

All seven scenarios completed with finite state, no simulation fault, and no crash. The takeoff rows stop after stable liftoff observation; approach runs through touchdown and four seconds of rollout.

| Case | Duration or event | Ground distance / liftoff distance | Speed | Heading / contact result |
| --- | --- | ---: | ---: | --- |
| Parked, engine off | 8.00 s | 0.0022 m ground travel | 0.0010 m/s max | 3 contacts; 0.495° heading drift |
| Parked, idle | 8.00 s | 0.0618 m ground travel | 0.0168 m/s max; 2800 rpm | 3 contacts; 0.255° heading drift |
| Taxi, left rudder | 6.00 s | 4.10 m | 1.56 m/s final | 72.28° left heading change; 3 contacts |
| Taxi, right rudder | 6.00 s | 4.24 m | 1.61 m/s final | 69.02° right heading change; 3 contacts |
| Unguided takeoff | Liftoff at 3.429 s | 24.77 m | 20.17 m/s at liftoff | 13.88° max heading error; 7.13 m max cross-track |
| Feedback-guided takeoff | Liftoff at 2.967 s | 16.62 m | 16.72 m/s at liftoff | 2.65° max heading error; 1.36 m max cross-track |
| Approach / flare / touchdown | Touchdown at 11.179 s | 36.65 m ground travel incl. rollout | 12.52 m/s, 1.34 m/s sink at touchdown | 3 contacts after 4 s rollout; no crash |

These are predictions from the isolated changed app. The [baseline 240 Hz](ground-baseline-240.json), [changed 240 Hz](ground-after-240.json) and [changed 480 Hz](ground-after-480.json) reports all complete seven cases with finite state, no faults and no crashes. Matching probe/wheel-profile hashes and distinct aircraft hashes are retained in their identity sidecars. The manual supplies qualitative cues, not numeric performance bands, so these values are not physical acceptance limits.

## Before/after and numerical refinement

| Metric at 240 Hz | Baseline | Changed |
| --- | ---: | ---: |
| Engine-off 8 s ground travel | 0.00216 m | 0.00222 m |
| Idle 8 s ground travel | 0.06294 m | 0.06184 m |
| Taxi left/right heading change | −73.70° / +75.79° | −72.28° / +69.02° |
| Unguided tail-up / liftoff | 1.992 / 3.396 s | 1.983 / 3.429 s |
| Unguided liftoff distance / speed | 24.94 m / 20.30 m/s | 24.77 m / 20.17 m/s |
| Unguided final heading change | −0.879° | +9.790° |
| Guided liftoff distance / speed | 15.42 m / 16.25 m/s | 16.62 m / 16.72 m/s |
| Guided peak left/right rudder command | −0.0322 / +0.0192 | −0.1768 / +0.00155 |
| Touchdown time / sink | 11.475 s / 1.322 m/s | 11.179 s / 1.342 m/s |
| Ground travel during touchdown/4 s rollout | 34.49 m | 36.65 m |

**The corrected installation does not yet reproduce the manual's power-on left-turn tendency.** With ordinary session flight trims retained, the changed unguided takeoff turns right and the guidance uses predominantly left rudder. Neutral pilot command is not neutral mechanical deflection: changed yaw trim is −0.03628 command and also reaches the rudder-linked tail wheel. The force-axis correction is independently verified; the qualitative ground-yaw mismatch remains visible. These runs do not isolate wake, P-factor, gyro, tyre and trim contributions, and do not justify a compensating rudder bias or disabling the documented thrust angles.

The [240/480 comparison](refinement.json) gives identical liftoff event times for both takeoffs, liftoff-speed differences below 0.000116 m/s, and ground-distance differences below 0.000082 m. Touchdown differs by one 480 Hz tick (0.002083 s), sink by 0.01125 m/s and accumulated ground travel by 0.01187 m. Taxi distance differs by at most 0.00000493 m. Every crash classification agrees. These two resolutions establish observed numerical sensitivity, not integration order or measured accuracy. Event sentinels (`-1` time and zero associated metrics) mean the event did not occur in that case; zero differences for such events do not count as event verification.

The landing ends while still rolling at 8.54 m/s; it does not qualify stopping distance. The takeoff and approach are separate initialized cases, not a continuous circuit. The research rest-pose initializer is not a product runway-start implementation. `test_runway_start.gd` verifies that Extra's runway reset is refused while preserving its airborne start: the shared static start solver requires stiction, which this aircraft intentionally lacks.

## Evidence and limits

The [manual audit](../EX-06/primary-sources.md) supports qualitative checks: use low rate for normal flight; anticipate left-turn tendency as power comes on and the tail rises; apply right rudder; avoid up elevator until flying speed; and lift off smoothly into a shallow climb. It gives no numeric rotation speed or takeoff distance. For landing it recommends a first approach slightly above stall speed with residual power, without a numeric speed or glide angle.

The takeoff feedback has no preset right-rudder bias: it holds the runway heading and reports the rudder command needed by this model. The speed gate is tied to the EX-05 1-g stall estimate, and the shallow-pitch target is a controller setting. The landing approach uses 1.25 times that estimated stall, a 3-degree path, and a 5-degree flare attitude; these values make the case repeatable but do not establish Extra flight performance. `flare_observed` means the recorded CG height above the NED datum crossed the 1.5 m trigger; it does not assert a successful flare or touchdown.

The [EX-06 implementation audit](../EX-06/implementation-audit.md) records that Extra has no configured propwash, P-factor, or slipstream block. Those omissions limit interpretation of power-on rudder demand and takeoff yaw. The current spring/damping/tyre and tail-wheel steering parameters are also provisional. Results are simulator predictions only; this probe is neither an independent model validation nor physical flight evidence. Do not tune coefficients just to make its outcomes match the qualitative manual text.

## Run commands

Use the same pinned Godot binary for each app tree. The script path resolves from the repository working tree; `--path` selects which app data and physics implementation to measure.

```sh
$(app/get-godot.sh) --headless --path .tools/extra-realism-baseline/app --script "$PWD/research/extra-300/ex06/ground_probe.gd" -- --hz=240 --output=/tmp/extra-ground-baseline-240.json
$(app/get-godot.sh) --headless --path app --script "$PWD/research/extra-300/ex06/ground_probe.gd" -- --hz=240 --output=/tmp/extra-ground-current-240.json
$(app/get-godot.sh) --headless --path app --script "$PWD/research/extra-300/ex06/ground_probe.gd" -- --hz=480 --output=/tmp/extra-ground-current-480.json
```

Review scenario completeness, finite-state status, contact sequence, and crash/fault fields before comparing numeric behavior. For fresh evidence, prefer the bounded runner in the [reproduction guide](../../../../research/extra-300/ex06/README.md), which rejects stale output and engine errors.
