# RCV-09-R2: power, braking and combined-slip handling

Date: 2026-10-14. Scope: the estimated Bisonte MT8 on the existing aircraft airfield, Godot 4.7.2, float64 vehicle dynamics. This is software verification and tuning, not identification of a physical RC truck. The aircraft-runway startup and the existing dirt circuit remain the user scenario.

## Power and mass placement

The current generated curve uses 5.2 N m stall torque per wheel and a 120 rad/s torque-fade endpoint, versus 4.2 N m and 100 rad/s previously. Stall torque rises 23.8%; peak mechanical power implied by the four linear curves rises from 420 to 624 W (48.6%). The 0.100 m tires imply an unloaded endpoint of 12 m/s, or 43.2 km/h. Actual road speed is measured separately; this is not a battery/thermal rating.

Simply raising the curve caused a nose-up flip during a supported full-throttle launch on the high-grip fixture, even though the lower-grip runway and controlled-speed circuit completed. Several torque/fade combinations reproduced that limit. The selected virtual electric layout lowers the estimated CG from 95 to 65 mm above the chassis underside datum. The [native CG sweep](../../../../research/rc-monster-truck/handling-r2/native-cg-height-grid.json) revalidates the descriptor and recomputes all datum-relative hull geometry before initialization: at 95 mm it flips; at 80/65/50 mm it reaches 11.891 m/s with no hull strikes and peak tilt 13.50/9.05/7.30 degrees. The 65 mm choice retains a margin without an active wheelie or heading controller.

This is an explicit estimated mass-layout change, consistent with a lower electric installation, not a measurement or physical modification of the Blender asset. Sprung mass and inertia about the CG remain estimated and unchanged. Visual/collision geometry stays tied to the original chassis datum, while dynamics and rendering use the new CG offset. Raised ballast and higher-grip laboratory settings can still overturn the truck.

## Contact and brake changes

The tangent solver now minimizes each contact's quadratic objective in its local inverse-mass metric. The previous radial force clamp only solves that problem for isotropic mobility; wheel spin makes longitudinal and lateral mobility different. Saturated contacts solve `(W + lambda I) f = W f_free`, with a bracketed scalar multiplier and the existing Coulomb circle. Longitudinal braking and lateral skid forces still share the same available tire force. The local mobility blocks are computed once per evaluation.

The cap rises from 6 to 128 sweeps with adaptive force/torque update tolerances of 1e-6 N and N m. The [investigation](research.md) separates numerical asymmetry at low sweep counts from instability under small lateral disturbances. Some solves still reach the cap: agreement between 128- and 256-sweep trajectories is bounded repeatability, not proof that every contact reached a residual tolerance. Native and GDScript versions implement the same equations. Solver identity is `openrc-ground-vehicle-dynamics-rk4-v3`; native evaluator identity is `openrc-ground-vehicle-native-evaluate-v2`, still ABI 1. Prior checkpoints cannot silently resume with a different solver/build.

Wheel slip angle now measures the wheel hub's lateral/longitudinal velocity relative to the tangent plane. The old denominator used the residual longitudinal contact slip, which approaches zero during rolling and could report nearly 90 degrees despite a small hub slip angle. Locked-wheel longitudinal slip remains separately reported.

The authored brake capacity is 1.35 N m nominal mean per wheel, 5.4 N m total, with a fixed 85/15 front/rear axle allocation: 2.295 N m at each front wheel and 0.405 N m at each rear wheel. Missing `brake_front_fraction` in a legacy descriptor retains equal braking. The fraction has quantity provenance and strict finite [0,1] validation. This is an estimated virtual independent-axle arrangement, not a claim about Traxxas central-driveline hardware. It uses no yaw, slip or speed feedback.

The brake choice follows a controlled 11.87 m/s sweep. Nominal capacities 1.2, 1.35, 1.5 and 1.65 N m all crossed the stopping threshold at the same sampled time, while peak tilt rose from 3.775 to 4.455, 6.468 and 13.280 degrees. The chosen 1.35 retains margin below the larger pitch response; 2.0 N m caused a tumble. These tests do not qualify arbitrary ballast, grip, gravity or suspension experiments.

## Evidence and reproduction

- [Controlled braking and swerve protocol, traces and comparisons](drive-handling.md): pinned initial states, matched control tapes, three uniform synthetic materials, validity-gated yaw and slip metrics. Both models start with four supported tires; the CG change gives different initial support heights.
- [Solver, load-transfer and brake-allocation research](research.md): frozen-source probes, cap sensitivity, mirrored disturbances and primary references.
- [Windows/Linux native identity and 50-case parity evidence](performance-native-final/README.md): float64 smoke, compiler details and binary/source hashes.
- [Track sampler optimization](performance-track-scalar-r2.md): exact output comparisons over 4,615 cases and separate timing scope.
- [Current Session cost profile](performance-active-session-r2.md): a bounded production-course measurement, with source and host-process snapshots.

### Measured driving results

| Experiment | Result |
| --- | --- |
| Production aircraft runway, three seconds of throttle | 11.680 m/s (42.05 km/h); subsequent 0.35-input brake stop in 11.466 m / 1.958 s |
| Production dirt circuit, controlled fast lap | 85.699 m in 22.471 s; peak 5.974 m/s; maximum route error 1.117 m |
| Supported asphalt fixture, full brake from 11.87 m/s | Baseline 10.463 m / 1.917 s; candidate 9.654 m / 1.633 s |
| Supported asphalt fixture, 0.6 brake from 11.87 m/s | Baseline 12.021 m; candidate 13.288 m; peak lateral speed falls from 7.299 to 0.020 m/s |
| Supported steering-only tape at 10 m/s | Both versions recover in about 0.25 s after steering returns to neutral |

Both production routes completed without rollover, hull/wall contact or airborne ticks. Their driver commands ordinary throttle/brake/steering inputs; it does not modify state during the route. The circuit's 38.36-degree maximum tilt includes its banked geometry. Jumps are checked separately with controlled approaches and supported landings. These are bounded simulated drives, not a guarantee for arbitrary player input.

Stop distances in the matched fixture are planar displacement from brake start; receipts also retain actual path length, which matters for the skidding baseline. Partial stops are longer on all three fixtures after the change. Full stops are shorter on asphalt and grass, and slightly longer on gravel. The demonstrated benefit is stable braking under a small lateral disturbance, not uniformly shorter stops or a new steering recovery capability. The [comparison plot](drive-supported-handling-comparison.png) shows those tradeoffs.

The exact track-sampler rewrite reduced median direct sampling time from 38.70 to 18.72 microseconds (51.6%) in seven paired trials. This is not a whole-simulation speedup. The final circuit's Session tick median/P95 was 3.204/4.573 ms; a separate short active-session profile measured 4.034/4.963 ms. Shared-host overlap affects timing, and both P95 values exceed the 4.167 ms budget at 240 Hz. Clean-machine sustained frame-time qualification remains open.

The controlled material fixtures preserve the older practice-course inputs for a matched comparison. Their `rolling` quantities multiply the vehicle's rolling coefficient; they are not measurements of asphalt, grass or gravel. Actual runway/circuit traces are needed separately to assess the integrated airfield.

Run focused runtime checks from the repository root, choosing a fresh evidence directory:

```powershell
python -B research/rc-monster-truck/verify_runtime.py --godot .tools/Godot_v4.7.2-stable_win64.exe --out tmp/rcv-handling-checks
```

The new handling regression checks independent analytic contact solutions, tire-force bounds and dissipation, spin-independent slip telemetry, symmetric braking, per-corner brake capacity, mirrored disturbed stops and 240/480 Hz agreement. The wider suite covers generated-data freshness, model validation, terrain, obstacles, jumps, session/checkpoint/replay and menu integration.

The final [runtime verification receipt](checks-accepted/verification.json) passes all 18 groups, with unchanged source hashes during the run. The native harness separately passes 50 parity checks on each of Windows and Linux. These checks cover software behavior and numerical agreement, not measured real-vehicle fidelity.

The [whole-app parse pass](parse-all.json) covered 842 scripts. Three helicopter scripts initially failed while that independent track was being edited; the [targeted follow-up](parse-followup.json) passed all seven changed, failed or newly added scripts. Together the latest checks cover 844 scripts with no remaining parse failures and matching file hashes. No helicopter implementation was changed by this RC handling work.

The jump and runway-edge tests now use ordinary speed-controlled approaches because their former fixed throttle overshoots with the stronger motor. Landing/support assertions remain intact. A checkpoint regression also exposed contact-event JSON rounding: event hashes now use the same canonical JSON values that are stored. Authoritative float64 state/control payloads are unchanged; the session round-trip and replay tests cover the correction.

## Physical limits and references

The model still uses an estimated Coulomb combined-force circle and a slip relaxation time. It has no measured RC tire curves, temperature/wear model, calibrated ESC/battery, ABS or traction controller. A large steering command can still create a skid or rollover. All three supported steering-only cases recover, but this does not qualify every high-speed steering maneuver. Earlier drop-start traces include a landing transient and are explicitly excluded from supported-stop comparisons. The native fallback in GDScript is correctness-oriented and is not qualified for real-time use at the increased iteration cap. Current Windows/Linux evaluator parity does not replace release-export qualification.

The constrained contact update follows the local quadratic/conic interpretation described in [MuJoCo's computation documentation](https://mujoco.readthedocs.io/en/stable/computation/). [Project Chrono's tire documentation](https://api.projectchrono.org/wheeled_tire.html) distinguishes combined-slip coupling and model-specific validity limits. These references motivate the mathematical checks and remaining calibration work; neither supplies physical Bisonte parameters. Brake load-transfer references and their scope are recorded in the [research report](research.md#primary-references).
