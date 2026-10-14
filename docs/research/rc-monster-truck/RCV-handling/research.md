# RCV handling and braking research — 2026-10-14

This report separates a contact-solver symmetry defect from the truck's response to a small lateral disturbance during braking. The experiments support a front-biased mechanical brake allocation for the estimated Bisonte model, but they do not physically validate that truck's tires or brake hardware.

## Reproducible setup

The vehicle descriptor is `drive-baseline-vehicle.json`, identity SHA-256 `732ad4197a60b111610e7eadf169e4718a68bdf85799f7cff4350eb4df698a0c`. The frozen GDScript reference source is `research/rc-monster-truck/handling_probe/baseline_sources/app/physics/ground_vehicle/vehicle_dynamics.gd`, SHA-256 `e3b8f6efde820dc0769b9556dacd0cae1338e71a3128f4829acf37f394e4dc79`.

Each variant cloned the frozen source in memory and called the clone's `_evaluate` directly during manual RK4 integration at 240 Hz. The live `Vehicle.initialize` function only built a level spawn state; no native evaluator was used for variant evaluation. The fixture had a flat surface, friction coefficient 0.85, zero steering, four matched wheel speeds and full brake input. Most solver and allocation cases started at 9.887221 m/s and ran to a 0.1 m/s stop threshold or 1.8 seconds; the final brake-envelope sweep started at 11.87 m/s and used a 3-second limit. Perturbations added body lateral speed of ±0.05 m/s. No ABS, steering correction or heading assist was active.

The runners and probe scripts are under [`research/rc-monster-truck/handling-r2`](../../../../research/rc-monster-truck/handling-r2/). Structured outputs are linked with each result below. The earlier brake audit remains at [`RCV-drive/braking-audit/findings.md`](../RCV-drive/braking-audit/findings.md).

## Solver symmetry and finite disturbances

An exactly straight, left-right symmetric state must have zero yaw acceleration. With equal 1.2 N·m brake torque per wheel, the frozen reference solver at six PGS sweeps instead produced 1.00693 rad/s² of yaw acceleration. Raising the sweep cap reduced that to −6.19×10⁻⁷ rad/s² at 24 sweeps and numerical zero by 64. The mobility-metric projection reduced the six-sweep error to 0.10008 rad/s² and also converged to numerical zero by 24. This establishes a finite-sweep numerical symmetry error; it is not a brake-bias problem. See [`solver-convergence-probe.json`](solver-convergence-probe.json).

One-state convergence alone was insufficient. Over the 1.8-second straight-braking trajectory, the reference radial clamp at 24 sweeps yawed 119.59°, while 48 sweeps reduced that to 1.07°. The mobility-metric candidate at 24 sweeps yawed 138.55°; cap 32 with adaptive 1e-6 N / N·m tolerances still yawed 107.29°. At 64 or more sweeps, the exactly symmetric starts stayed close to straight: reference64 peaked at 0.0355°, metric64 at 0.206°, and metric128/256 at 0.0434°. See [`solver-trajectory-probe.json`](solver-trajectory-probe.json) and [`solver-trajectory-probe2.json`](solver-trajectory-probe2.json).

Small lateral seeds behave differently from the exact symmetric start. At ±0.05 m/s, reference64 spun to about 175.11° yaw; the metric solver at caps 64, 128 and 256 spun to about 179.82°, with 5.5515 m/s peak lateral speed. Positive and negative seeds produced nearly mirrored states. The 128- and 256-cap metric trajectories agree to the reported precision, which makes a real rear-axle lock/oversteer mode plausible; however, the strict adaptive solver reached the sweep cap in these runs. This is repeatability across doubled caps, not proof that every contact solve met its residual tolerance. See [`solver-trajectory-probe2.json`](solver-trajectory-probe2.json), [`solver-trajectory-probe3.json`](solver-trajectory-probe3.json) and [`solver-trajectory-probe4.json`](solver-trajectory-probe4.json).

The frozen source's reported slip angle divides lateral patch velocity residual by longitudinal patch velocity residual. That denominator is not hub rolling speed, so the trace is unreliable near wheel lock. I used yaw, acceleration, contact force and wheel-load results for this diagnosis; fix the telemetry before using slip-angle plots to tune the tire model.

The measured load shift is consistent with the rear-lock explanation: at 0.1 s in the perturbed equal-brake run, the two rear normal loads were 1.61 N and 3.44 N while their lateral forces were close to zero; the front loads were 22.6 N and 24.0 N. Under braking, forward load transfer reduces the rear tires' available combined force. Equal wheel torque can then ask the lightly loaded rear tires for more longitudinal force than their road contact can support, leaving little lateral authority. The SAE study describes axle-lock sequence as a stability factor and reports that higher front brake proportioning reduced rear-lock propensity in its measured vehicle sample; NHTSA's FMVSS 135 test procedure likewise requires the front axle to lock before or simultaneously with the rear axle in the specified wheel-lock-sequence test. These are general vehicle references, not measurements of this RC truck.

## Fixed axle allocation experiment

At the same total brake torque (4.8 N·m), changing the clone from 25/25/25/25% per-wheel torque to an estimated front/rear axle split kept both signs of the 0.05 m/s disturbance bounded:

| Front/rear mechanical torque share | Peak yaw, ±0.05 m/s seed | Peak lateral speed |
| --- | ---: | ---: |
| 80/20 | about 1.5065° | 0.05 m/s |
| 85/15 | about 0.5093° | 0.05 m/s |

For 85/15, cap128 and cap256 gave almost identical results. The exact symmetric runs stayed near zero yaw. All these cases used the metric projection with adaptive 1e-6 N / N·m tolerances; peak sweep counts still reached the cap at least once. See [`brake-bias-probe.json`](brake-bias-probe.json) and [`brake-bias-hard-probe.json`](brake-bias-hard-probe.json).

This is a simple mechanical axle allocation, not a stability assist: it changes each axle's available brake torque while preserving total torque and never uses yaw or lateral velocity to steer the truck. An 85% front share is within the 75–85% range reported in the SAE paper's post-1980 passenger-car sample, and the paper says light trucks of that period also tended toward more front proportioning. That makes 85/15 a defensible estimated starting value for a high-CG truck whose rear axle unloads sharply under braking. It is not evidence that the original Bisonte hardware uses that split. Keep the allocation explicit and source-tagged in vehicle data; retain the legacy 50/50 default for existing descriptors until their mechanical brake layout is known.

## High-speed brake envelope

A final cap128 sweep tested mean per-wheel brake torques of 1.20, 1.35, 1.50 and 1.65 N·m at 11.87 m/s, with an 85/15 front/rear mechanical allocation and a +0.05 m/s lateral seed. Each case used the metric projection and adaptive 1e-6 N / N·m tolerances. Full-body tilt is the angle between the truck's up axis and world up, so it also detects rollovers that pitch-only reporting can miss.

| Mean torque per wheel | Total torque | Stop time | Peak body tilt | Peak yaw | Rear load at sampled times |
| ---: | ---: | ---: | ---: | ---: | --- |
| 1.20 N·m | 4.8 N·m | 1.583 s | 3.775° | 0.422° | both rear loads zero at 0.1 s; positive by 0.2 s |
| 1.35 N·m | 5.4 N·m | 1.583 s | 4.455° | 0.745° | both zero at 0.1–0.2 s; positive by 0.4 s |
| 1.50 N·m | 6.0 N·m | 1.583 s | 6.468° | 0.923° | both zero at 0.1–0.4 s; positive by 0.6 s |
| 1.65 N·m | 6.6 N·m | 1.583 s | 13.280° | 0.822° | both zero at 0.1–0.8 s; positive by 1.0 s |

All four reached the stop threshold without tumbling in this run. The strongest tested stop was 1.65 N·m per wheel (2.805 N·m at each front wheel, 0.495 N·m at each rear wheel), but it produced the largest tilt and about 0.8 seconds of sampled rear-axle lift. That is an upright stop, not a validated or recommended setting. The 1.20 N·m case was the least disruptive in this sweep. Every case reached the 128-sweep cap at least once, so these values are provisional and do not establish a converged high-speed response. See [`brake-tune-probe.json`](../../../../research/rc-monster-truck/handling-r2/brake-tune-probe.json).

## Extreme-brake pitch-over limit

The 85/15 allocation is not safe at every torque. At 11.87 m/s with a mean 2.0 N·m per wheel (8.0 N·m total; 3.4 N·m at each front wheel and 0.6 N·m at each rear wheel), the clone pitched nose-down to 89.9° by 0.6 s, all four tire loads reached zero, the body tumbled through an inverted attitude, and the run did not reach the 0.1 m/s stop threshold within 1.8 s. This occurred from both the exact and perturbed starts. Do not ship that brake level as a harder-stop tune; the high-CG pitch and airborne response needs separate calibration. At 1.2 N·m mean per wheel and the baseline speed, 85/15 stopped in about 1.321 s with a 3.77° nose-down maximum and about 0.509° peak yaw for the perturbed start.

## Solver interpretation and next step

The tangent contact update uses a local mobility matrix `W = J M⁻¹ Jᵀ`. Solving the unconstrained update and then radially clamping the resulting force in Euclidean coordinates is not the constrained minimizer when longitudinal and lateral mobility differ. For a circular Coulomb bound `||f|| ≤ μN`, the local quadratic minimizer satisfies `(W + λI) f = b`, where `b = W f_free`, `λ ≥ 0`, and `λ` is chosen so the force lies on the circle when needed. This is a solver correction, separate from axle brake allocation; neither correction alone cures the equal-brake perturbed trajectory in these experiments.

Keep both concepts explicit: converge the contact solve enough that exact symmetry and small perturbations are repeatable, then use a source-tagged front axle share for the estimated brake hardware. The circle bound is still only a simplified combined-slip tire model. SAE combined-slip work describes force direction changes from anisotropic slip stiffness, while Brach and Brach show that the ideal force circle/ellipse is only a limited approximation and that actual force limits depend on slip angle and traction slip. RC tire force curves, wheelbase/CG measurement, brake distribution and pitch-over tests remain open physical-validation work.

## Primary references

- Shadle, Emery and Brewer, [“Vehicle Braking, Stability and Control,” SAE 830562](https://saemobilus.sae.org/papers/vehicle-braking-stability-control-830562), 1983. Reports rear-axle lockup as a stability concern and summarizes front brake proportioning in its measured vehicle sample.
- NHTSA, [FMVSS 135 test procedure TP-135-01](https://www.nhtsa.gov/sites/nhtsa.dot.gov/files/tp-135-01.pdf), wheel-lock sequence test. The specified test requires front-axle lock before or simultaneous with rear-axle lock.
- Xu and Guo, [“Modeling Combined Braking and Cornering Forces Based on Pure Slip Measurements,” SAE 2012-01-1924](https://saemobilus.sae.org/articles/modeling-combined-braking-cornering-forces-based-pure-slip-measurements-2012-01-1924), 2012. Discusses anisotropic slip stiffness and a friction ellipse for combined braking and cornering.
- Brach and Brach, [“The Tire-Force Ellipse (Friction Ellipse) and Tire Characteristics,” SAE 2011-01-0094](https://www.brachengineering.com/content/publications/SAE-2011-01-0094-Brach-Engineering.pdf), 2011. Explains why an idealized force circle or ellipse is a simplified combined-tire model rather than a quantitative tire law.
