# GP-09a: fixed-axis body/wheel reference

2026-10-25 software evidence. This slice adds a pure float64 coupled-rotation helper and tests it through the existing `Simulation`/`VehicleModel` joint-stage contract. **It does not migrate stock flight sessions or claim a runtime flight fix or physical validation.** The existing tire/contact law remains unchanged.

## Source and run identity

The checked run used an isolated worktree based on `cb2924b3676b72ee49497c92fe742b0b1dcd2d9c`, with these candidate sources:

| Source | SHA-256 |
| --- | --- |
| [wheel_coupling.gd](../../../../app/physics/wheel_coupling.gd) | `2cea4e934cbbd6d54a0c2526891070b063f1fead9f97b418099656d5ae26351c` |
| [test_wheel_coupling.gd](../../../../app/tests/test_wheel_coupling.gd) | `c29f6a81beb6beec9711780d008f0ee784c67ba0fbba57d1d8154d2ef98497ad` |

Engine: native Windows Godot `4.8.beta1.official.4d10419ca`, headless, Dummy audio. The run began at `2026-10-25T23:10:33.423918+00:00`; [checked report](checks/wheel-coupling/report.json) and [engine log](checks/wheel-coupling/engine.log) are retained byte-for-byte. The report records its original worktree paths; they are historical identity, not links required to read this evidence. Result: **84 checks, 0 failed; complete=true, ok=true; no engine errors or warnings.** The report's elapsed time is process duration, not a physics performance benchmark.

## Convention and API

The law identity is `fixed-axis-relative-rim-coupling-v1`. Each fixed unit body axle is `a_i`; positive relative rim state is `u_i=R_i sigma_i` in m/s. The locked CG inertia tensor `I` includes each wheel's axial inertia `J_i` exactly once. Translational wheel mass remains in the existing body inventory.

```text
T_rot = 1/2 omega^T I omega
        + sum[(J_i/R_i) u_i (a_i.omega) + 1/2 (J_i/R_i^2) u_i^2]
B_i = (J_i/R_i) a_i; D_ii = J_i/R_i^2
h_body = I omega + sum[B_i u_i]
[I B; B^T D] [alpha; u_dot] = [M_external,CM - omega x h_body; axle_torque_i/R_i]
```

`prepare(locked_inertia6, radii, inertias, axes_body)` returns a successful prepared factor or `{ok=false,error}`. The inertia uses the existing symmetric six-entry matrix convention; axle components are packed three per wheel. The helper constructs the symmetric matrix and diagonal local block itself, validates finite positive parameters/unit axes, and checks both the full matrix and residual `I-sum(J_i a_i a_i^T)` for positive definiteness. It reuses [generalized_coordinates.gd](../../../../app/physics/generalized_coordinates.gd), including its structured factor/solve. The public API cannot supply unsupported off-diagonal local couplings.

`evaluate(prepared, omega3, rims, moment_external_cm3, axle_torques, h_other=empty)` returns `{ok,angular_acceleration,derivative}` or `{ok=false,error}`. Pass an unchanged successful `prepare` result. The caller supplies the total external moment at CG without the old additive spin reaction. Axle torque is positive about the stored axis and includes external axle torque minus internal brake torque. Internal brake torque enters only the relative-coordinate row; its carrier reaction emerges from the solve. The optional separately owned prescribed/sampled prop momentum contributes to gyroscopic transport. It is not a substitute for a simultaneously coupled dynamic shaft.

The tested `h_other` case is constant in body components. If a caller prescribes a changing momentum, its separate qualified law must supply the `-d(h_other)/dt_body` exchange in the body right-hand side and account for actuator work; this helper neither computes that derivative nor proves that extended system's energy balance. Do not feed a dynamically evolving prop shaft into this optional argument and claim it is jointly coupled.

## Executed evidence

The regression executes the existing `GroundWheels.evaluate` at a flat, zero-slip contact, then passes its loads to `RigidBody.derivative` with an added pure carrier moment. It reproduces the [masterplan counterexample](../../../advanced-ground-flight-physics-masterplan.md#44-wheel-rotation-inertia-and-generalized-energy): `a=-y`, `I_yy=1`, `J=0.1 kg m^2`, `R=0.2 m`, `q=1 rad/s`, `u=3 m/s`, `M_y=-1 N m`. The declared residual carrier inertia is `0.9 kg m^2`.

| Instantaneous quantity | Existing source | Coupled reference |
| --- | --- | --- |
| Pitch acceleration, rad/s² | `-1` | `-1/0.9` |
| Relative rim acceleration, m/s² | `0` | `0.2 alpha_y` |
| Cross-term kinetic-energy rate, W | `+0.5` | `-1` within `1e-14 W` assertion |
| Applied external power, W | `-1` | `-1` |
| Unexplained power residual, W | **`+1.5`** | Below the stated assertion tolerance |

This is an instantaneous synthetic source test under the explicitly declared once-included inertia convention. It is not evidence that a particular stock aircraft has that inertia partition or that the fixture is a sustained no-slip trajectory.

Additional checks cover nonparallel arbitrary unit axles, off-diagonal locked inertia, body transport/gyroscopic terms, relative-spin brake work, an initially zero relative rim, separately prescribed prop momentum, invalid dimensions/nonfinite parameters and impossible inertia splits. Independent scalar energy uses residual carrier energy plus each rotor's absolute-spin energy, rather than reusing the production mass matrix. Across 20 arbitrary-axis cases, the largest central finite-difference power residual was `2.5962e-10 W` (gate `<1e-8 W`); angular momentum equation and internal-brake power residual gates were `<1e-13 N m` and `<1e-13 W`. Forward/reverse flat no-camber cases pair the unchanged finite-slope tire force with its axle torque, checking virtual work and nonpositive tire/rolling/brake power without the old spin patch.

A synthetic `VehicleModel` integrates body, two fixed-axis rims and accumulated brake heat through the production `Simulation` joint-stage RK4 path for two seconds. It uses neither a dynamic prop shaft nor moving geometry. All six runs completed without a fault, conserved world angular momentum, closed cross-term energy plus brake heat, kept heat monotonic and reproduced the next eight ticks byte-for-byte after checkpoint restore. Increasing the tick rate reduced the measured conservation errors:

| Brake | Rate, Hz | Maximum energy + heat error, J | Maximum world momentum component error, N m s |
| --- | ---: | ---: | ---: |
| Off | 120 | `4.05e-12` | `9.463e-11` |
| Off | 240 | `2.5e-13` | `5.93e-12` |
| Off | 480 | `7e-14` | `3.7e-13` |
| On, airborne | 120 | `5.01e-12` | `6.309e-11` |
| On, airborne | 240 | `3.1e-13` | `3.94e-12` |
| On, airborne | 480 | `2e-14` | `2.4e-13` |

Values reproduce the retained log's printed precision. The integration gates are `<1e-8` in the respective units; the refinement check requires decreasing error and does not assert exact fourth-order ratios at roundoff scale.

## Reproduce and limits

From the repository containing the candidate sources, import once if its resource cache is fresh, following the [checked Godot runner guide](../../../../tools/godot/README.md). Then run in PowerShell:

```powershell
$gp09Godot = (Resolve-Path '.tools/Godot_v4.8-beta1_win64_console.exe').Path
python tools/godot/run_checked.py --out-dir tmp/gp09-checks --label wheel-coupling --timeout 60 --require-text '84 checks, 0 failed' -- $gp09Godot --headless --path app --audio-driver Dummy --script res://tests/test_wheel_coupling.gd
python tools/godot/summarize.py docs/research/ground-physics/GP-09/checks
```

The second command verifies the retained report/log collection independently of the original absolute paths.

Excluded: moving steering/retract axes or hubs and their affine momentum/bias/actuator work; coupled suspension/caster coordinates; finite-resource inventory/CG migration; simultaneous dynamic engine/prop-shaft coupling; full cambered circular-wheel geometry; new traction coefficients; stock-fleet inertia ownership and session migration; measured RC hardware behavior, rendered/audio acceptance and performance qualification. No default law, historical replay or live flight-session behavior changes in GP-09a. Those exclusions remain gates before enabling a combined flight law.

## GP-09b/c: prescribed carriers and a common rotor system

Continuation, 2026-10-25/26: [RotorCoupling](../../../../app/physics/rotor_coupling.gd) now contains a common `3+N` angular system; [WheelCoupling](../../../../app/physics/wheel_coupling.gd)'s transport path only converts rim units around it. The historical fixed-axis helper and single-shaft `response` remain unchanged. This extension does not yet migrate stock sessions.

For rotor `i`, intrinsic inertia is `C_i=K_i*Id+(J_i-K_i)*a_i*a_i^T`, absolute angular velocity is `Omega_i=omega+nu_i+sigma_i*a_i`, and `a_dot_i=nu_i x a_i`. The fixed-body remainder is the declared locked reference tensor minus the reference rotor tensors. Live fuel changes sample that same reference tensor convention. Full angular momentum, `C_dot` transport, carrier acceleration, local axial equations and signed actuator work enter one solve. Hubs remain fixed; mechanism carriers are ideal/massless. This does not establish translating-hub or moving-gear-assembly dynamics.

`prepare_system` requires explicit estimated aggregate provenance and physically realizable tensor reservations. `evaluate_system` accepts all wheel/shaft relative speeds in rad/s, carrier rates/accelerations, the total external CG moment, each rotor's external couple and internal spin torque. Internal brakes enter only the relative-coordinate row. External rotor couples appear in total external moment once. Finite static-hold demands are recovered after every other rotor participates; insufficient capacity is explicit failure, not an infinite clamp.

`project_relative_speeds` performs a mass-metric impulse projection over explicitly requested spin constraints. It changes body and unconstrained rotor speeds consistently. With prescribed carrier motion, kinetic energy can increase only with the corresponding signed actuator impulse work; the projection still records nonnegative dissipation. A bounded static force hold is not automatically an unlimited impulse lock.

[Transport tests](../../../../app/tests/test_wheel_coupling_transport.gd) pass 124 checks; [common-system tests](../../../../app/tests/test_rotor_system.gd) pass 60, alongside the 84 original fixed-axis checks. Independent finite-difference energy/momentum and dense KKT references cover nonparallel axes, prescribed motion, simultaneous wheels/shaft, hold capacity/release, projection work and nonphysical tensor rejection. The shared [GP-11 integration record](../GP-11/README.md) owns subsequent source-isolated composition and rollout limits.
