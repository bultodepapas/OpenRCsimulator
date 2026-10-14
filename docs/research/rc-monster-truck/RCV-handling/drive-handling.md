# RCV supported-start handling comparison

Date: 2026-10-14. These bounded simulations compare the frozen Bisonte MT8 estimate with the current 5.2 Nm candidate on a controlled flat fixture, then check the candidate on the production airfield runway and fast circuit. They are software experiments, not physical validation.

## Vehicle and solver identities

The baseline descriptor uses 4.2 Nm per wheel, a 100 rad/s torque-fade endpoint, 2.0 Nm per-wheel braking split equally, and 0.095 m CG height above the chassis datum. Descriptor SHA-256: `732ad4197a60b111610e7eadf169e4718a68bdf85799f7cff4350eb4df698a0c`. Frozen dynamics SHA-256: `e3b8f6efde820dc0769b9556dacd0cae1338e71a3128f4829acf37f394e4dc79`. Frozen native Windows DLL: `2958c34163a8c13d5d5fc675806bd6b45750eb8f435708c1ba4d4b67ade8789e`; native source: `451a76a00ac0e7d4513390d405e45eb55c6cb9b387ed21e55035d09ab7ef697f`; toolchain: `2051a079931113cbf72767863a0159fb69319631343022d647e1031fd301453a`.

The current generated candidate uses 5.2 Nm per wheel, a 120 rad/s torque-fade endpoint, a 1.35 Nm nominal brake budget split 85% front / 15% rear, and 0.065 m CG height. Its linear four-wheel torque-speed curve implies 624 W peak mechanical power, versus 420 W for the baseline (48.6% more); this is a model-curve estimate, not a battery or continuous-power rating. Candidate descriptor SHA-256: `425f2a3fe810f82d609ad2b9dd9618b9fb45bcd813df57873cd8bc8759a750a5`. Dynamics SHA-256: `957b3398d114ae57c71c455c1f1054f9b4646a793712d6e9f719aeef5d6a1a22`. Native Windows DLL: `adafd1f9682dff147e538fdb7686329c009edf255c639789ac28dc403bc6e65c`; native source: `e2ae0a5ffebc8d81636302d66238348035ee92bf51d2f40965db7053bb251541`; toolchain: `78bdd21d315683b45eee37c24b84716430cdba2a9b24066f59a68df476585b4d`. Each receipt pins the complete selected-source manifest and checks that inputs did not change during the run.

The baseline runs use the isolated [frozen Godot project](../../../../research/rc-monster-truck/handling_probe/baseline_sources/app/project.godot), with its retained descriptor, dynamics, extension, receipt, and DLL. The current runs use the active application project. The active DLL was never replaced to run the baseline.

## Supported-start protocol

For each material, `VehicleDynamics.initialize` places the vehicle in static support at north/east 100 m and heading 0. The probe then seeds body-forward velocity (10.0 or 11.87 m/s), 0.02 m/s body-lateral velocity, and four pure-rolling wheel speeds once. It makes no later state edits; every subsequent sample advances through `VehicleDynamics.step` at 240 Hz. All 30 cases reported four wheel contacts, zero hull contacts, and no airborne flag at the initial sample. Baseline support height was 0.204842 m; candidate support height was 0.174842 m, as expected from the different CG. The same velocity, pose recipe, wheel-spin initialization, material values, and control tapes were used; the full initial state hashes differ because the vehicle descriptors differ.

Braking cases use no throttle or steering. Brake input 1.0 or 0.6 starts at tick zero and is held until speed is at most 0.1 m/s. The 10 m/s suite also runs a steering-only countersteer tape: neutral through 0.25 s, +0.75 steering through 0.75 s, −0.75 through 1.25 s, then neutral through 4 s. Recovery is the first time after neutral when body slip is at most 5° and valid heading rate at most 0.15 rad/s for 0.25 s continuously.

Stop distance is the planar straight-line displacement from brake start to the first sample at or below 0.1 m/s. It is distinct from integrated path length, which the receipts report separately and which can be longer when the truck skids.

The flat comparison fixture holds synthetic practice-course estimates uniformly: asphalt μ=0.85 / rolling multiplier=0.025, gravel μ=0.65 / 0.055, and grass μ=0.50 / 0.08. The model rolling-resistance coefficient is 0.035, and the kernel multiplies it by the surface value; effective Crr is therefore 0.000875, 0.001925, and 0.0028. These values are not measured surface drag. The actual runway and circuit checks below use the production course and material pipeline.

## Supported braking results

All four matched receipts completed: nine cases each for 10 m/s and six braking cases each for 11.87 m/s. All 30 cases had finite state and telemetry, valid initial support, four contacts, and no inversion, hull contact, or airborne tick. Heading rate is counted only while tilt is at most 60°; body-slip angle is omitted below 0.5 m/s planar speed. The partial-brake baseline reaches near-180° velocity reversal on asphalt and gravel; that angle denotes a skid reversal, not an Euler-yaw singularity.

| Entry speed | Surface | Full-brake planar stop displacement, baseline → candidate (m) | 0.6-brake planar stop displacement, baseline → candidate (m) | 0.6-brake peak absolute yaw rate, baseline → candidate (rad/s) | Peak lateral speed, baseline → candidate (m/s) |
| --- | --- | ---: | ---: | ---: | ---: |
| 10.0 m/s | Asphalt | 7.028 → 6.857 | 8.516 → 9.432 | 3.376 → 0.006 | 4.919 → 0.020 |
| 10.0 m/s | Grass | 11.653 → 11.600 | 11.927 → 13.778 | 0.340 → 0.017 | 0.644 → 0.020 |
| 10.0 m/s | Gravel | 8.977 → 9.144 | 10.041 → 10.578 | 2.128 → 0.014 | 3.919 → 0.020 |
| 11.87 m/s | Asphalt | 10.463 → 9.654 | 12.021 → 13.288 | 3.536 → 0.006 | 7.299 → 0.020 |
| 11.87 m/s | Grass | 16.440 → 16.342 | 18.951 → 19.412 | 0.884 → 0.015 | 3.097 → 0.020 |
| 11.87 m/s | Gravel | 12.716 → 12.880 | 14.324 → 14.903 | 2.330 → 0.013 | 6.212 → 0.020 |

The candidate’s 85/15 split and updated solver/model leave no large partial-brake yaw or lateral skid in these tapes. Its lower 1.35 Nm nominal brake budget trades that control for longer 0.6-input stops on all three surfaces at both speeds. Full-stop distances change only slightly: the candidate is shorter on asphalt and grass, and 0.16–0.17 m longer on gravel. Candidate peak tilt stayed below 3.5° in these stop cases; the baseline stayed below 6.4°. The formerly reported 178.69° tilt at 11.87 m/s came from the old drop-start experiment described below; the supported 11.87 m/s baseline asphalt full stop peaks at 6.35° with no inversion.

Energy and state checks: all cases remained finite; maximum recorded energy gain above each case’s own initial total energy was 0 J. Braking runs lost about 306 J at 10 m/s and 431 J at 11.87 m/s. Steering-only runs also lost energy, with no positive drift. This is a numerical consistency check, not validation of the model’s mass or tire parameters.

The 10 m/s steering-only tape recovered 0.254 s after neutral on baseline asphalt, grass, and gravel. Candidate recovery was 0.254 s on asphalt and 0.250 s on grass and gravel. Peak yaw rate and body-slip angle were close between solvers (baseline → candidate: asphalt 0.858 → 0.843 rad/s and 1.17° → 1.15°; grass 0.495 → 0.476 and 0.65° → 0.64°; gravel 0.645 → 0.629 and 0.86° → 0.84°). The steering-only cases therefore show no material loss of recovery with the higher-power candidate.

The [comparison plot](drive-supported-handling-comparison.png) is generated from the hash-verified compressed traces. Receipts and traces: [baseline 10 m/s](drive-supported-baseline-10mps.json) / [CSV](drive-supported-baseline-10mps.csv.gz) / [log](drive-supported-baseline-10mps.log); [candidate 10 m/s](drive-supported-candidate-10mps.json) / [CSV](drive-supported-candidate-10mps.csv.gz) / [log](drive-supported-candidate-10mps.log); [baseline 11.87 m/s](drive-supported-baseline-brake-11_87mps.json) / [CSV](drive-supported-baseline-brake-11_87mps.csv.gz) / [log](drive-supported-baseline-brake-11_87mps.log); [candidate 11.87 m/s](drive-supported-candidate-brake-11_87mps.json) / [CSV](drive-supported-candidate-brake-11_87mps.csv.gz) / [log](drive-supported-candidate-brake-11_87mps.log).

## Production-course route checks

The candidate runway run accelerated for 3 s to 11.680 m/s and stopped in 1.958 s over 11.466 m with the route driver's 0.35 brake-input limit. It completed 1,190 ticks (4.958 s simulated), reached 6.28° maximum tilt, and recorded zero airborne ticks, rollover ticks, hull contacts, and wall contacts. This is a route-level controlled stop, not a full-brake fixture test or a same-tape comparison with the older baseline runway receipt.

The fast controller completed one 85.699 m circuit in 5,393 ticks / 22.471 s, with a 5.974 m/s peak speed. It returned to the start, covered all track features, and finished with a 0.490 m cross-track error; maximum route error was 1.117 m. Maximum tilt was 38.36°, with no airborne, rollover, hull, or wall contacts. The [runway receipt](drive-final-cg065-runway.json) / [trace](drive-final-cg065-runway.csv.gz) and [fast-circuit receipt](drive-final-cg065-fast-circuit.json) / [trace](drive-final-cg065-fast-circuit.csv.gz) pin the current vehicle and native identities.

The route runner’s `session_tick_cost_us` times one `_session.tick_once` call, including the session step and road sampling but excluding the outer controller and recording loop. The runway p50 / p95 / max was 3,022 / 3,634 / 4,835 μs; the circuit was 3,204 / 4,573 / 11,403 μs. Other verification may share the host, so these figures are noisy per-call timing, not end-to-end application latency.

## Earlier drop-start traces

The initial v2 traces constructed the vehicle at `vehicle_up_m=0.5` instead of using static support. Their first sample was airborne, and they include a fall and landing before braking; they are not supported rolling hard stops. Keep them as exploratory landing-brake evidence only. In particular, the old 11.87 m/s asphalt full-brake pitch-over was a landing/contact transient, not the supported stop above. The later 5.2 Nm / 1.35 Nm candidate runs also used the old unsupported start and the prior 0.095 m CG descriptor, so their numeric tables do not describe the final candidate. Those runs remain in the JSON receipts: [old baseline 10 m/s](drive-baseline-handling-10mps-v2.json), [old baseline 11.87 m/s](drive-baseline-brake-11_87mps-v2.json), [earlier candidate 10 m/s](drive-candidate-final2-handling-10mps.json), and [earlier candidate 11.87 m/s](drive-candidate-final2-brake-11_87mps.json). Their retained CSVs are gzip-compressed; consult their receipts for storage paths and original CSV hashes.

## Reproduction

Use a fresh output name for each run. Baseline selection uses the isolated frozen project and saved native DLL; current selection uses the active app project and current generated descriptor.

```powershell
python -B research/rc-monster-truck/handling_probe/run_handling.py --solver baseline --scenario all --speed 10.0 --output docs/research/rc-monster-truck/RCV-handling/drive-replay-baseline-10mps.csv
python -B research/rc-monster-truck/handling_probe/run_handling.py --solver baseline --scenario brake --speed 11.87 --output docs/research/rc-monster-truck/RCV-handling/drive-replay-baseline-11_87mps.csv
python -B research/rc-monster-truck/handling_probe/run_handling.py --solver current --scenario all --speed 10.0 --vehicle app/data/vehicles/ground/mt8_bisonte.json --output docs/research/rc-monster-truck/RCV-handling/drive-replay-candidate-10mps.csv
python -B research/rc-monster-truck/handling_probe/run_handling.py --solver current --scenario brake --speed 11.87 --vehicle app/data/vehicles/ground/mt8_bisonte.json --output docs/research/rc-monster-truck/RCV-handling/drive-replay-candidate-11_87mps.csv
python -B research/rc-monster-truck/driving/run_drive.py --scenario runway --pace fast --output docs/research/rc-monster-truck/RCV-handling/drive-replay-runway.csv
python -B research/rc-monster-truck/driving/run_drive.py --scenario circuit --pace fast --output docs/research/rc-monster-truck/RCV-handling/drive-replay-circuit.csv
```
