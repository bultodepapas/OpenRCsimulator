# DR-04a…06a — Multirotor foundation slice: the plant on the shared kernel

2026-10-15 · **Status: research-grade kernels only; no session, catalog or presentation route. The quad plant runs on the shared `Simulation` kernel through the `VehicleModel` contract and passes its known answers and sign contracts (15 checks).** The first new consumer of the simulation foundation ([plan](../../../plans/simulation-foundation.md), owner decision D6: multirotor before boats), delivered as the base rung of the drone plan's fidelity ladder ([drone plan §4.1](../../../plans/drone-racing.md)). Nothing here is validated against flight data.

## What exists

| File | Content | Ladder rung |
| --- | --- | --- |
| [`app/physics/multirotor/rotor.gd`](../../../../app/physics/multirotor/rotor.gd) | Per-rotor quadratic thrust and torque at the static bench point, the control literature's linear rotor drag as the in-plane force, the reaction torque with the sign of −spin about the thrust axis, and the inertial reaction of rotor acceleration (§4.6); hover speed closed form (§4.11) | "quadratic fit" of the NeuroBEM table; DR-04 proper adds blade elements on the shared HELI-04 inflow |
| [`app/physics/multirotor/powertrain.gd`](../../../../app/physics/multirotor/powertrain.gd) | First-order motor per rotor with the measured time constant, ESC idle floor and output limit | DR-05 adds back-EMF, pack voltage, the synchronous ESC and the battery |
| [`app/physics/multirotor/airframe.gd`](../../../../app/physics/multirotor/airframe.gd) | Three-axis quadratic drag (§4.5) | as planned |
| [`app/physics/multirotor/plant.gd`](../../../../app/physics/multirotor/plant.gd) | The `VehicleModel`: 13-value body, four rotor speeds as continuous state, four sampled duties in aux, four duty inputs; joint stage with loads, derivatives and the N-rotor spinning momentum; wind and density from the environment contract; the estimated research-quad fixture with its provenance | the flight controller (§4.7) is DR-07; until then the plant is driven by duties |
| [`app/tests/test_dr_multirotor_kernel.gd`](../../../../app/tests/test_dr_multirotor_kernel.gd) | 15 checks, below | |

Fixture (`Plant.research_quad()`): mass 0.752 kg and 33 N maximum static thrust are measured on the identified ETH/UZH research quad ([DR-01 §1.3–1.4](../DR-01/README.md)); the motor time constant 39.1 ms is measured (Agilicious); the full-duty speed, inertia, geometry, torque-to-thrust ratio, rotor-drag constant, rotor inertia, idle duty and drag areas are estimates with their derivation noted in the source. The quad-X numbering and spin senses follow the Betaflight convention the plan fixes in §4.2.

## Proof

| Check | Result |
| --- | --- |
| Contract | The plant installs on the kernel and resets at hover; layout 4 inputs, 4 sampled duties, 4 rotor speeds, no modes, no events |
| Hover (§4.11) | Four quadratic thrusts carry the weight at the closed-form speed; one second of hover holds altitude within 1 mm with zero rates; rotor speeds hold under the lag law; the spinning momentum of matched pairs cancels |
| Signs (§4.2) | Raising rotors 1 and 2 rolls left with no pitch; raising 2 and 4 pitches up with no roll; speeding the counter-clockwise pair 2 and 3 yaws clockwise with no roll or pitch |
| Inertial yaw (§4.6) | After one tick of a counter-clockwise speed-up the body yaws more clockwise with rotor inertia than without, and without it still yaws clockwise from the aerodynamic torque |
| Passivity | Rotor drag never does positive in-plane work over 200 random states |
| Environment (SF-07) | Flying with a 4 m/s wind through the contract gives the still-air loads exactly |
| Replay | Two kernels replay the same bytes; the kernel checkpoint restores |

[log](results/kernel-test.log).

## Limits and next

- Quadratic thrust ignores axial and in-plane flow; DR-04 proper (blade elements on the HELI-04 inflow, H-force and hub moment) is where speed-dependent behaviour enters.
- First-order motors hide the pack: DR-05 brings the EL battery kernels and the synchronous ESC (decision D8).
- No flight controller: DR-07 implements the discrete rate loop, modes and the quad-X mixer from the published documentation; the plant's duty inputs become the mixer's outputs.
- No legs, pad start, prop strike, data format (`openrc-multirotor v1`, DR-10), session seam or presentation. The drone plan's owner decisions D1–D14 stand as recorded there.

Commit message: `DR-04a…06a: multirotor plant on the shared kernel (quadratic rotors, first-order motors, airframe drag, N-rotor momentum); hover, sign, inertial-yaw, passivity, Galilean and replay checks`
