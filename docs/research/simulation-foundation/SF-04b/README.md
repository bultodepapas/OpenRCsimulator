# SF-04b — Settle the kernel's event locators with refinement evidence

2026-10-18 · **Status: delivered, byte-identical: 24/24 fleet fingerprints match HEAD; the new 51-check refinement test passes and catches both deliberate mutations; 33 focused kernel, event, electric, glow, helicopter, replay, golden and session programs pass.** Last step of the [simulation foundation plan](../README.md).

## Question

SF-04 left one follow-up: move the rotorcraft, battery and glow locators onto the kernel locator (`app/physics/event_step.gd`), with `h`/`h/2` refinement evidence, because unifying them would change trajectories.

## What the code does (2026-10-18)

| Route | Tick owner | Boundary handling |
| --- | --- | --- |
| Fixed-bus electric (Timber) | kernel | Declared `rotor_stop` event, located by `event_step.gd` |
| Finite-battery electric (synthetic fixtures; no catalog airplane) | `FlightSession._electric_step` | `electric_battery_step.gd`: rotor stop through `electric_stop.gd`, a wrapper of `event_step.gd`; battery exhaustion bracketed with the same `event_bracket.gd` proposer |
| Glow (three Stik variants) | `GlowFlight.step` policy | The same battery composition with the tank as the second boundary, then the lifecycle transition |
| Helicopter | `simulation_step_adapter.gd` policy | Own guarded RK4 approach and explicit-midpoint terminal bisection |
| RC ground vehicle | `VehicleDynamics.tick_policy` | No event; its own substeps |

The battery and glow routes therefore already use the kernel locator for their rotor stop. Only the helicopter has separate numerics, and the reason is a domain difference rather than history:

- `event_step.gd` evaluates RK stages beyond the boundary while it brackets a crossing (5–8 per stop in the test below). It requires a law that continues smoothly there; the electric shaft does.
- The rotorcraft law refuses Ω < 0 (`flight_dynamics.gd`, fault `rotor_zero_speed_event`), and the kernel faults the whole tick on a refused stage. The adapter checks every stage before it calls the law and never evaluates Ω < 0.

A second finding: the kernel computed SF-05 contact substeps for every model but ignored them silently when a step policy owned the tick. No airplane is affected today (every policy airplane derives one gear substep), but a stiffer gear on a glow airplane would have integrated its contact over the full tick, outside the loader's ω·dt < 0.1 rule, without any signal.

## Options evaluated

| Option | Result |
| --- | --- |
| Port the helicopter onto `event_step.gd` | Rejected: every rotor stop faults, demonstrated by the test (a far-side-refusing law behind the shared locator faults the stop tick and rolls back). It would need an invented negative-speed rotor law. |
| Add a guarded mode to `event_step.gd` and move the adapter's algorithm into it | Rejected: no accuracy gain (both are fourth order and agree to 1.7e-11 s), a second algorithm inside the shared locator, and changed helicopter trajectories for the historical trainer route. |
| Split step policies into substeps like the kernel's own RK4 | Rejected: the glow policy accounts lifecycle work per tick, so splitting it changes behaviour. |
| Close by documentation only | Rejected: leaves HELI-17b's refinement qualification and the silent substep gap open. |
| **Keep both numerics byte-identical, state the contract, qualify both locators and refuse unsplit stiff policy ticks** | **Adopted** ([DECISIONS](../../../DECISIONS.md)). |

## Change

| File | Change |
| --- | --- |
| [`app/sim/simulation.gd`](../../../../app/sim/simulation.gd) | A tick whose model has a step policy and asks for more than one contact substep is refused with "the step policy owns the tick and cannot honour N contact substeps" and rolls back like any rejection. |
| [`app/sim/vehicle_model.gd`](../../../../app/sim/vehicle_model.gd), [`app/physics/event_step.gd`](../../../../app/physics/event_step.gd), [`app/physics/rotorcraft/simulation_step_adapter.gd`](../../../../app/physics/rotorcraft/simulation_step_adapter.gd) | Contract comments: declared events need a continuation beyond the boundary; a law that refuses it uses a domain-guarded policy; policies are never split. No code change. |
| [`app/tests/test_sf_event_refinement.gd`](../../../../app/tests/test_sf_event_refinement.gd) (new) | 51 checks through the real `Simulation` transaction (below). |
| [STACK](../../../STACK.md#boundaries-and-data-flow) | The two locator classes, the policy rule and the native-backend policy as current guidance. |

## Proof

Known answer: Ω' = −A − B·Ω with A = 300 rad/s², B = 8 s⁻¹ and Ω0 = 20 rad/s stops at t* = ln(1 + B·Ω0/A)/B = 0.0534305 s; a unit-inertia roll rate driven by p' = 0.05·Ω reaches the closed-form integral at t* and then holds.

| Rate | `event_step` stop-time error | Adapter stop-time error | Roll-rate error (both) | Stages beyond zero (`event_step` / adapter) |
| --- | --- | --- | --- | --- |
| 240 Hz | 5.46e-10 s | 5.29e-10 s | ≈ 1.0e-9 rad/s | 6 / 0 |
| 480 Hz | 3.41e-11 s | 3.37e-11 s | ≈ 6.4e-11 rad/s | 6 / 0 |
| 960 Hz | 2.15e-12 s | 1.93e-12 s | 4.0e-12 rad/s | 8 / 0 |

| Check | Result | Record |
| --- | --- | --- |
| Order of both locators | Error ratio per halving 15.6–17.4 (fourth order is 16; the test requires ≥ 12, above third order's 8) | [test log](results/refinement-test.log) |
| Agreement of the two independent locators | 1.66e-11 s worst case across the three rates | [test log](results/refinement-test.log) |
| No chatter, restart, replay | One stop and Ω exactly 0 for 0.9 s at rest; restart from rest without an event within the RK4 truncation bound of the analytic speed; checkpoint replay reproduces bytes and event | [test log](results/refinement-test.log) |
| Domain contract | A far-side-refusing law behind `event_step.gd` faults the stop tick and rolls back; the adapter flies the same law with zero far-side stages | [test log](results/refinement-test.log) |
| Policy substep guard | Two substeps under a policy: tick refused and rolled back; one substep: accepted. All three catalog policy airplanes (glow Stiks) derive one gear substep | [test log](results/refinement-test.log) |
| Mutations on disposable copies | Guard deleted: 2 checks fail. Adapter integrator degraded to explicit midpoint: 6 checks fail, error ratios fall to 3.9–4.0 (second order) | [mutations](results/mutations.txt) |
| Fleet fingerprints, HEAD copy (`git archive`) versus this tree | **24/24 identical** (eight airplanes plain and cut, two synthetic electric fixtures plain and cut, three helicopter runs, the RC ground vehicle); the Ventage Jet cut fault is pre-existing and identical | [comparison](results/fingerprint-comparison.txt), [HEAD](results/fingerprints-head.json), [SF-04b](results/fingerprints-sf04b.json) |
| Focused programs on this tree | 33/33 exit 0, including EL2a-P2 localization (2,946 checks), glow oracle (723), golden flights (4), checkpoint/replay integrity, helicopter sessions and startup kernel, RCV session, all `test_sf_*` | [summary](results/focused-tests.txt) |
| Static checks | float64 guard, H6 transcendental routing and `--check-only` parse of every edited script | — |

## Limits

- Both locators are fourth order only where RK4 is stable. A law stiffer than RK4's stability limit (B·dt ≈ 8 was probed) drives either one to rest without a true finite stop; the loader's ω·dt rules and SF-05 substeps exist to keep data out of that regime.
- The helicopter result covers the adapter's numerics with an analytic shaft law. Rotor physics, freewheel/autorotation and the HX-700 laboratory candidate remain with the [helicopter plan](../../../plans/helicopter.md); HELI-17b's physical acceptance is not implied.
- The policy substep guard fails a tick at runtime. Data that would trigger it is caught earlier by the fleet inventory check in the test.
- No physical validation is implied.

Commit message: `SF-04b: keep two qualified event locators, refuse unsplit stiff policy ticks; 51-check refinement test (4th order, locators agree to 1.7e-11 s, 2 mutations caught), 24/24 fleet fingerprints identical, 33 focused programs pass; close the simulation foundation plan`
