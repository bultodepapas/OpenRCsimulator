# RCV-05/09/18: power revision and simulated driving

Date: 2026-10-14. Scope: estimated Bisonte MT8, real float64 vehicle solver and Session on the existing airfield, Windows x86_64 / Godot 4.7.2. These are software experiments, not measured RC hardware performance.

This is the retained first power revision. The subsequent [RCV-09-R2 handling revision](../RCV-handling/README.md) supersedes its current tuning and partial-brake limitation; the measurements below retain their original snapshot identities.

## Implemented revision

The former motor curve reached zero torque at 40 rad/s wheel speed: with the authored 0.100 m tires, its unloaded rolling speed was only 4 m/s (14.4 km/h). Increasing stall torque alone could not remove that limit.

The [source generator](../../../../research/rc-monster-truck/build_vehicle_data.py) now produces:

| Parameter | Previous | Revised |
| --- | ---: | ---: |
| Motor stall torque, per wheel | 3.0 Nm | 4.2 Nm |
| Linear torque-fade endpoint | 40 rad/s | 100 rad/s |
| Unloaded rolling speed implied by radius | 4 m/s | 10 m/s |
| Peak mechanical power implied by the four identical linear curves | 120 W | 420 W |
| Maximum brake torque, per wheel | 6 Nm | 2 Nm |

The power calculation is `4 × T0 × ω0 / 4`. It describes the mathematical torque curve, not electrical input, battery rating or continuous thermal capacity. Grip still limits launch acceleration; no speed clamp, artificial launch impulse, heading stabilization, gravity change or increased tire friction was added. The vehicle descriptor hash changes, so older checkpoints cannot silently use different mechanical parameters.

The former brake estimate pitched the faster vehicle over in an abrupt full-stop test. A 1.8/2.0/2.2 Nm sweep supported the 2.0 Nm compromise. Flat-fixture braking from 9.887 m/s stops below 0.1 m/s in 1.417 s over 6.806 m; minimum upright cosine is 0.9942. Halving the integration step changes that distance by 0.00039 m. This is a flat fixture, distinct from the actual runway result below. Abrupt partial braking can still produce substantial yaw in the estimated model; the [braking audit](braking-audit/findings.md) records that limitation and the scope of its numerical checks.

Traxxas documents the relationship between gearing, torque and speed in its [glossary](https://traxxas.com/support/glossary/), and its [VXL introduction](https://traxxas.com/news/getting-started-with-vxl-models) distinguishes available power from beginner command limits. These are qualitative references only. The fictional Bisonte parameters above are engineering estimates, not a claimed Traxxas motor curve or top speed.

## Driving protocol and results

[run_drive.gd](../../../../research/rc-monster-truck/driving/run_drive.gd) drives the production Session at 240 Hz, without changing state after initialization. It supplies throttle, steering and brake commands; the course sampler and coupled vehicle equations determine motion. Every CSV row retains all 31 state values, controls, contacts, terrain feature, path progress and tick cost. JSON records source identities, sample count and CSV hash. The Python wrapper enforces process timeout, refuses overwritten evidence and checks engine errors and the result/CSV contract.

The runway trial uses three seconds of full throttle followed by full braking, starting at the ordinary runway spawn. The circuit follows the same 85.7 m loop, with speed planning for bends and obstacles. The steady comparison uses identical controller policy. A separate fast policy anticipates upcoming curvature and ramps; it is an offline test driver, not a hidden gameplay assist.

| Measured quantity | Original drivetrain | Revised drivetrain |
| --- | ---: | ---: |
| Runway speed after 3 s | 3.839 m/s | 9.695 m/s |
| Peak runway speed | 13.84 km/h | 34.90 km/h |
| Time to 3 m/s | 0.563 s | 0.517 s |
| Peak scalar speed increase | 6.17 m/s² | 7.50 m/s² |
| Runway stopping distance | 1.277 m | 8.070 m |
| Runway braking time | 0.688 s | 1.692 s |
| Steady circuit time | 32.13 s | 31.09 s |
| Steady circuit maximum path error | 1.126 m | 1.125 m |

The stopping-distance comparison starts at different speeds and uses different brake torque; it is not evidence that the new brakes shorten stopping distance. Both runway runs stay upright with no hull impacts. The steady laps retain full track coverage and visit both ramps, all three rollers and both banked turns, without wall contacts or rollovers. Steady controller speed limits explain its modest 3.2% lap improvement despite much more available straight-line speed.

The [verified faster lap](candidate-fast-signed-verified.json) takes **22.771 s**, peaks at **21.09 km/h**, and retains full track coverage. It finishes 0.435 m from its first recorded position, with maximum path error 1.129 m, no rollover, no hull/wall impact and no complete loss of support. Signed progress subtracts backward movement and requires return to the start, preventing repeated forward/backward motion from counting a false lap. Its full source manifest is unchanged during the run. An [independent coordinate review](trace-review.json) also checks earlier steady CSVs: 172 forward waypoint advances, no backward advances, one complete route; those earlier receipts have no before/after source manifest. The faster lap uses a different speed policy, so its 29.1% time reduction against the old steady lap must not be attributed to the motor alone.

[Trajectory and speed comparison](drive-comparison.png), generated from hash-verified raw CSV by [plot_drive.py](../../../../research/rc-monster-truck/plot_drive.py). Individual measurements: [original runway](baseline-runway-1.json), [revised runway](candidate-runway.json), [original steady lap](baseline-circuit.json), [revised steady lap](candidate-circuit.json).

The five accepted CSV traces are retained as `.csv.gz`; [retained-csv.json](retained-csv.json) binds compressed and original hashes. The JSON run receipts retain their original `.csv` output names. Decompress to recover those exact bytes; the plot tool reads either form. Exploratory logs are not substitutes for the accepted run receipts.

The separate full-throttle tabletop test now produces about 1.04 s of flight, compared with the earlier 0.104 s hop. All four tires lose support, and the first landing remains on the track with upright cosine 0.961. This test releases throttle after takeoff; it does not establish that full throttle throughout a jump is safe. [Native airborne capture](power-jump-es.png), [physical state receipt](power-jump-es.png.json).

## Reproduce

From the repository root, create a fresh output directory and run:

```powershell
python -B research/rc-monster-truck/build_vehicle_data.py --check
python -B research/rc-monster-truck/driving/run_drive.py --scenario runway --output .tools/rcv-drive/new-runway.csv
python -B research/rc-monster-truck/driving/run_drive.py --scenario circuit --pace steady --output .tools/rcv-drive/new-steady.csv
python -B research/rc-monster-truck/driving/run_drive.py --scenario circuit --pace fast --output .tools/rcv-drive/new-fast.csv
```

Pass `--vehicle docs/research/rc-monster-truck/RCV-drive/baseline-vehicle.json` to repeat the retained original mechanical configuration. Output files must not exist. The [baseline descriptor](baseline-vehicle.json) is retained only as experiment evidence; the application still loads its regenerated default.

## Optimization and limits

All **17 focused runtime verification groups passed**, with unchanged source inputs during the [verification run](verification/verification.json). The new [powertrain regression](verification/test_rcv_powertrain.log) passes 9 checks, including acceleration, high-speed stopping, 240/480 Hz convergence and active/reference derivative parity. [Wall tests](verification/test_rcv_obstacle_contacts.log) pass 14 checks, including 10 m/s impacts at 240 and 480 Hz without artificial energy gain. The final [course-cache regression](course-cache-regression.log) adds changed-table, NaN, empty-table and restoration checks to the normal airfield suite: 37 checks pass. The native jump capture was inspected and its log contains no engine errors.

The CLI additionally rejects incomplete routes with a nonzero exit status while retaining their diagnostics; a deliberately one-second circuit run verified that failure path. Runs with changed source inputs also return failure. The [final follow-up receipt](final-checks.json) pins the additional check and test/generator sources. The runtime starts on the aircraft runway as before.

The [terrain optimization report](../RCV-performance/README.md) separates paired sampler measurements from complete Session tick measurements. It verifies unchanged physical outputs while reducing repeated validation/allocation work. Timing was taken on a development workstation with concurrent activity; route timings are diagnostic, not isolated release benchmarks. Rendering is excluded from Session tick cost. The 500 µs complete-tick gate and target-hardware frame pacing remain open.

The faster model still uses point-probed tires, equal drive/brake torque per wheel, parallel front steering and estimated suspension/inertia. Partial-brake yaw, tire enveloping, differentials, thermal/battery behavior, deformation and independent physical calibration remain limitations. Runtime verification protects numerical behavior and integration; it does not validate these estimates against a real monster truck.
