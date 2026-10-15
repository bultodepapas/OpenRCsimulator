# Simulation foundation plan

2026-10-15 · Revision 2 · **Status: active. SF-00…02 delivered 2026-10-15 ([evidence](../research/simulation-foundation/SF-01/README.md)); SF-03 delivered 2026-10-15 ([evidence](../research/simulation-foundation/SF-03/README.md)); SF-04 delivered 2026-10-15 ([evidence](../research/simulation-foundation/SF-04/README.md)); SF-05…09 pending. The owner adopted D1–D6 as recommended ("proceed with the implementation", 2026-10-15).** Owner: physics and simulation track ([ROADMAP](../../ROADMAP.md)). Proposed prefix: `SF-`. Proposed owned paths: `app/sim/simulation.gd`, a new `app/sim/vehicle_model.gd` contract, `app/physics/integrator.gd`, `app/physics/rigid_body.gd`, `app/physics/math3d.gd`, shared event/contact/environment kernels, `app/tests/test_sf_*.gd`, `docs/research/simulation-foundation/`. Sessions, aircraft laws, vehicle data and presentation stay with their owners.

This plan answers the owner's 2026-10-15 charter: one simulation foundation for aircraft first, then helicopters, boats, cars and other vehicles, with realism, accuracy, robustness and performance as architectural principles rather than later features. Section 2 records what the foundation already is, section 3 where it falls short of the charter, sections 4–5 the target and the bounded steps.

## 1. Charter and reconciliation

Condensed from the owner's statement:

1. The engine is a long-term platform, not a physics module per aircraft. Aircraft flight dynamics come first.
2. Realism, numerical accuracy, robustness and computational efficiency are architectural principles.
3. Every architectural decision must leave the foundation stronger, more modular and more extensible for vehicle types that do not exist yet.

Reconciliation with the standing [AGENTS](../../AGENTS.md) rule "robust physics and evidence over feature breadth": breadth of *vehicle types* enters only through the shared kernel and contracts below. A new vehicle never widens the kernel without a byte-identical proof for the vehicles already on it, and every vehicle keeps its own physical-validation gates. Platform breadth and product breadth remain different things.

Ready-to-paste [DECISIONS](../../DECISIONS.md) row for SF-00:

```text
| 2026-10-15 | **Simulation foundation charter: one float64 kernel and shared vehicle/environment contracts serve every vehicle type; aircraft first.** Realism, accuracy, robustness and performance are architectural principles. Vehicle breadth enters only through the shared kernel with byte-identical proofs for existing vehicles. | Owner statement 2026-10-15; three sessions already duplicate tick/checkpoint logic and H10's reopen condition is met by named consumers. [Plan](docs/plans/simulation-foundation.md) | Proposed | A named vehicle cannot express its model through the contract, or the kernel's cost on the target exceeds the budget. |
```

## 2. What the foundation already is (assessed 2026-10-15)

| Principle | Current mechanism | Evidence |
| --- | --- | --- |
| Numerical accuracy | 13-value float64 rigid body (NED/FRD, quaternion), classic RK4 at 240 Hz with stage time, renormalized attitude, scalar derivative bit-identical to its vector reference; all transcendental calls through one module | [rigid_body.gd](../../app/physics/rigid_body.gd), [integrator.gd](../../app/physics/integrator.gd), [math3d.gd](../../app/physics/math3d.gd), [test_rigid_body.gd](../../app/tests/test_rigid_body.gd), [numerics knowledge base](../research/roadmap-investigations/01-numerics-architecture-performance.md) |
| Robustness | Bounded state contract: continuous body, coupled continuous blocks, sampled `aux` frozen over stages, discrete `modes`, exact float64 checkpoints, sticky fault with rollback to the last valid tick; `test.sh` refuses 32-bit types in `sim/` and `physics/` | [H8 contract](../research/simulation-state/H8/README.md), [simulation.gd](../../app/sim/simulation.gd), [test.sh](../../app/test.sh) |
| Verification | 504 GDScript test/bench programs (about 95 k lines against 37 k lines of `sim/`+`physics/`), known-answer integrator tests, `h`/`h/2` refinement, golden flights, byte-exact oracles frozen from named commits, mutation checks on scratch copies, independent Python/SciPy oracles, exact replay fingerprints | [tests](../../app/tests/), [H15](../research/simulation-state/H15/README.md), [helicopter references](../../research/helicopter/reference/) |
| Data integrity | `openrc-aircraft v2`: every quantity `{value, unit, kind, source}`, explicit capabilities registry, derived mass/CG/inertia, invalid data cannot fly, generated data only through pipelines | [AIRCRAFT_CONTRACT](../../AIRCRAFT_CONTRACT.md), [aircraft_modules.gd](../../app/physics/aircraft_modules.gd) |
| Performance discipline | 500 µs/tick budget, measurement before tuning, per-aircraft/regime p50 and batch p95, a byte-identical native experiment | [H15](../research/simulation-state/H15/README.md), [Gate P](../research/simulation-state/Gate-P/README.md) |
| Vehicle reach | Fixed wing (glow, electric, turbine), helicopter (19 coupled states through the shared kernel, event-located rotor stop), ground vehicle (31 states, 14 generalized coordinates, projected Gauss–Seidel friction, pinned C++ evaluator), lake/water contact | [flight_dynamics.gd](../../app/physics/rotorcraft/flight_dynamics.gd), [vehicle_dynamics.gd](../../app/physics/ground_vehicle/vehicle_dynamics.gd), [RCV-28](../../DECISIONS.md) |

Current fleet cost after H15 (development host, noisy): Ugly Stik 218–236 µs/tick in trim and stall, P-51 444–476 median with batch p95 at 519–536 µs. The 2026-10-14 R02 section-plane law was measured above 500 µs under a concurrent job; target-machine acceptance remains open ([remediation](../research/physics-audit-2026-10-14/remediation/README.md)).

## 3. Gaps against the charter

| ID | Gap | Facts | Consequence for new vehicles |
| --- | --- | --- | --- |
| G1 | One kernel, three tick owners | `Simulation` (567 lines) exposes eleven optional Callables and hard-codes `input_size in [4, 6]`. `FlightSession` (3,624 lines) and `HelicopterFlightSession` (678) use it; the truck `session.gd` (1,886) reimplements the tick loop, RK4, checkpoint, fault handling and recording. Three checkpoint formats exist. [H10](../research/simulation-state/H10/README.md) declined a contributor interface because no consumer was blocked; the truck then bypassed the kernel and the helicopter needed `continuous_evaluate`/`continuous_step` grafted on. | Every new vehicle re-decides what a tick, a checkpoint and a fault are. H10's reopen condition ("a real second implementation cannot express its loads without duplicating assembly") is now met by two shipped vehicles. |
| G2 | One rigid body; internal degrees of freedom are bespoke | The truck's hubs and wheel rotors use a hand-derived coupled mass matrix with Coriolis terms inside a 2,313-line evaluator. The helicopter appends scalar states. No shared generalized-coordinate assembly or constraint solver exists; the 2026-10-05 decision rejects general physics libraries. | Boats (outboard/rudder pivots), flapping rotors, articulated gear and towed loads each rewrite the assembly. |
| G3 | Mixed integration order and ad hoc events | Legacy sessions freeze engine rpm and servos over RK stages: the coupled shaft is first order unless G2a/G2b is enabled, and promotion is still open. Events are solved three different ways: rotor stop ([step adapter](../../app/physics/rotorcraft/simulation_step_adapter.gd)), electric stop ([EL1d policy](../../app/physics/electric_stop.gd), [bracket](../../app/physics/event_bracket.gd)) and hull crossing ([pose interpolation](../../app/physics/hull_crossing.gd)). | A vehicle with its own events (water entry, gear strike, motor cut) invents a fourth policy and its own order proof. |
| G4 | Contact stiffness ceiling | The loader enforces ω·dt < 0.1 per contact, so static sag must exceed about 17 mm at 240 Hz; the [numerics knowledge base](../research/roadmap-investigations/01-numerics-architecture-performance.md#stiff-contacts-discontinuities-event-location) shows a 5 mm giant-scale gear needs 443 Hz and a hull scrape 1,400 Hz under that rule. | Cars with stiff tyres, boats slamming and drone crashes cannot be represented at the fixed tick. |
| G5 | Law properties are found by audit, not by harness | The 2026-10-14 audit proved a 164 N / 257 N side-force jump at pure spanwise flow, a turbine inlet switch and a runway reset that failed at exactly perpendicular crosswind; R02–R04 repaired them. Continuity, passivity and invariance checks exist per law ([regime consistency](../../app/tests/test_regime_consistency.gd), [pull-up invariants](../../app/tests/test_pullup_invariants.gd), wind Galilean tests) but not as one reusable harness. | A new hull, tyre or rotor law ships without the checks that already caught three defects. |
| G6 | Environment is wired per session | Wind, atmosphere column, terrain, surfaces, lake and scenery collision are composed inside `FlightSession`; the helicopter wires a subset; the truck has its own `vehicle_environment.gd` and course height fields. Stage-position sampling (R09) exists only on the fixed-wing path. | Boats need water height/velocity, cars need terrain and surfaces, drones need wind; each would re-wire the same sources. |
| G7 | Headroom lives in GDScript; native paths are per experiment | Each physics improvement spends the budget (R02 law, finite fuel, ground effect). The truck ships a pinned C++ evaluator with ABI version, build receipt and backend identity in checkpoints ([RCV-28](../../DECISIONS.md)); the fixed-wing [Gate P](../research/simulation-state/Gate-P/README.md) experiment proved byte-identical results but was not adopted. | Multiple vehicles in one scene, or richer laws, will not fit 500 µs in GDScript; without a policy each track re-derives the native route. |
| G8 | Verification is rigorous; physical validation is thin | Every aircraft is estimate-labelled; the [VAL-3 dashboard](../../research/validation/dashboard.md) shows roll decay 2.07× and Dutch-roll frequency 1.25× outside the comparison bands; VAL-5…8 field measurements and Gate 2 are open since 2026-10-05. | The charter's "rigorous validation" cannot be closed by architecture. It needs the owner's field kit; this plan must not imply otherwise. |
| G9 | Determinism is tolerance-based | Cross-platform differences come from libm; replays compare within tolerance (decision 2026-10-05). | Acceptable for single-player replay. Multiplayer or shared replays would need deterministic math; not a current gap. |

## 4. Target architecture

```text
Session (product: input, holds, scenarios, failures, recording)   one per activity, thin
   │ owns configuration and callbacks, never the tick
Simulation kernel (one): tick transaction, RK4 with stage time, events, checkpoint, fault rollback
   │ steps exactly one VehicleModel against one Environment
VehicleModel contract          Environment contract            Backend policy
  layout: body + named blocks    air(pos, t)   ground(n, e)      reference GDScript evaluator
  stage(state, inputs, env, t)   water(n, e, t)  gravity         optional pinned native evaluator
  pre_tick / post_tick / events  pure, deterministic,            same ABI, identity in checkpoints,
  identity                       stage-position sampled          byte-identical oracle
```

Vocabulary used by the steps:

- **Kernel**: `Simulation`. One tick transaction for every vehicle: validate, `pre_tick`, stage evaluations, event policy, `post_tick`, commit, emit. It never knows what a wing or a tyre is.
- **VehicleModel**: a validated RefCounted supplied at session setup. `layout()` declares the body-first float64 state, named continuous blocks, sampled `aux`, `modes` and input size. `stage(state, inputs, env, t)` returns `{loads, block_derivatives, rotor_momentum, body_derivative?}` as the joint callback does today. `pre_tick` and `post_tick` keep the H8 sampled/discrete rules. `events()` declares residual functions the kernel locates. `identity()` pins law versions into checkpoints. GDScript has no interfaces, so the shape is validated once at setup, as `rotorcraft/flight_dynamics.gd` does with `prepare`.
- **Environment**: pure, deterministic queries sampled at stage position and time. Providers are the existing wind field, atmosphere column, terrain, surfaces, lake and course height fields.
- **Backend**: a VehicleModel may delegate `stage` to a pinned native evaluator with the same ABI; the reference GDScript path stays authoritative and selectable.

What this deliberately is not: a general multibody or constraint solver, a component/plugin registry, a merge of the three product sessions, or a dependency upgrade.

## 5. Steps

Each step is one reviewable change with its proof. Numerical results of existing vehicles must stay byte-identical through SF-01…03 and SF-07; only SF-04/05 may change trajectories, with refinement evidence.

| ID | Work | Proof / status |
| --- | --- | --- |
| SF-00 | Record the charter (section 1) in DECISIONS, register the `SF-` prefix and owned paths in the [documentation map](../README.md), reconcile the AGENTS feature-breadth rule in one sentence | Delivered 2026-10-15: DECISIONS row, AGENTS sentence and kernel rule, STACK boundary, registry row |
| SF-01 | Define `VehicleModel` and wrap the existing fixed-wing closures in an adapter; the kernel reads layout from the model and drops `input_size in [4, 6]` and the eleven-Callable configuration | Delivered 2026-10-15: `app/sim/vehicle_model.gd`, kernel reads only `model`, FlightSession installs its model; every flyable airplane fingerprints byte-identical over 960 ticks, goldens/checkpoint/replay suites unchanged, 27-check contract test ([evidence](../research/simulation-foundation/SF-01/README.md)). The pre-SF-01 callback properties remain as forwarding aliases until SF-03 migrates the 27 direct-configuration tests |
| SF-02 | Move the helicopter onto the contract (it already supplies the joint stage and a step policy) | Delivered 2026-10-15: rotorcraft model with declared layout (1 sampled rpm, 6 coupled states); 1200-tick scripted hover/control fingerprint byte-identical; helicopter session suites pass ([evidence](../research/simulation-foundation/SF-01/README.md)) |
| SF-03 | Move the ground-vehicle session onto the kernel transaction (clock, checkpoint, fault, `stepped`), keeping `vehicle_dynamics.gd` and its native backend as the model; delete the duplicated RK4/checkpoint/fault code | Delivered 2026-10-15: the session owns a `Simulation` with the truck's `VehicleModel` (18 declared coupled values, `tick_policy` step policy); the private RK4 is deleted and `VehicleDynamics.step` runs the same policy; the JSON checkpoint format is unchanged and restores through the kernel; 11/11 fleet fingerprints identical, 23-check kernel test ([evidence](../research/simulation-foundation/SF-03/README.md)). Follow-up kept open: migrate the 27 field-by-field kernel tests and delete the compatibility properties |
| SF-04 | One event protocol in the kernel: a model declares a boundary (continuous index held at or above zero, transition at the crossing) and the kernel locates it with `physics/event_step.gd` (RK4 trials, `event_bracket.gd` secant/bisection to 1e-12 of local tick time, transition, remainder); any step policy reports its located events as `{state, events}`; the kernel validates them against the tick window, records `last_events` and emits `events_located` | Delivered 2026-10-15: the locator is the EL1d algorithm moved verbatim (`electric_stop.gd` is its wrapper), so every trajectory stays byte-identical; the fixed-bus electric route declares its rotor stop instead of owning a policy; the battery composition, the glow step and the rotorcraft stop predictor keep their policies and report events; 38-check protocol test ([evidence](../research/simulation-foundation/SF-04/README.md)). Scope corrections: the rotorcraft locator keeps its own explicit-midpoint predictor because migrating it changes trajectories and needs HELI refinement evidence (SF-04b, with the `h`/`h/2` order proof); hull crossing is a post-tick pose estimate for crash detection, not an integration event, so it stays an observer |
| SF-05 | Stiff-contact substepping: when any contact is within reach, hold slow loads and substep body plus contact N times with N a deterministic function of state and data; relax the loader rule to \|λ\|·dt ≤ 0.3 per substep | Touchdown refinement on the E1b fixtures; contact never adds energy; airborne goldens unchanged (a contact above ground adds exactly 0.0); ground fixtures within budget |
| SF-06 | Law property harness `app/tests/law_properties.gd`: Cartesian-approach continuity sweeps (the audit F01 probe), zero load at rest, finite load at zero speed, passivity, Galilean invariance, mirror symmetry, finite-difference versus analytic derivatives where available; every load law registers | Runs in `test.sh`; each law passes or is listed with an open ID (for example P51-22) |
| SF-07 | `Environment` contract with stage-position sampling for all three vehicles; wind, atmosphere column, terrain, surfaces, lake and course fields become providers | Uniform-field metamorphic tests on all three vehicles; fingerprints unchanged under the reference field |
| SF-08 | Backend policy: generalize RCV-28's dual-backend scheme (ABI version, build receipt, identity in checkpoints, byte-identical oracle, reference fallback) into a documented pattern; port the fixed-wing stage evaluator only after SF-01 and only on target-machine evidence | Gate P method: fingerprints plus fleet p50/p95 from the owner's host; Windows/macOS builds (owner D5) |
| SF-09 | Generalized-coordinate kernel: extract the truck's mass-matrix/Coriolis assembly and pivoted solve into a shared float64 routine for "base body + internal DOF"; evaluate a double-precision Jolt build or a float64 Featherstone port before writing any constraint solver | Truck results byte-identical; known-answer two-body test (cart–pendulum energy and analytic frequency) |

Order: SF-00 → SF-01 → SF-02 → SF-03, then SF-06 in parallel with SF-04 → SF-05 → SF-07 → SF-09; SF-08 when target measurements require it. The coupled-shaft default promotion stays with G2 and is a prerequisite for calling the fixed-wing path fourth order.

First new consumers after SF-03: the multirotor ([drone plan](drone-racing.md)) as a single rigid body with four continuous rotor states exercises SF-01/04/07 at the lowest validation cost; a boat follows with the water query of SF-07, a hydrostatic/hydrodynamic hull law run through SF-06 and, if an outboard pivot is modelled, SF-09.

## 6. Owner decisions

Adopted 2026-10-15 as recommended (owner: "proceed with the implementation").

| ID | Decision | Recommendation |
| --- | --- | --- |
| D1 | Adopt the charter and its reconciliation with the feature-breadth rule | Adopt; record the SF-00 row |
| D2 | Register `SF-` under the physics track with the owned paths above | Register; keep sessions and laws with their owners |
| D3 | Reopen H10 on the named consumers (truck, helicopter, multirotor) and schedule SF-01…03 | Yes, in a quiet window with one integrator for `simulation.gd`/`flight_session.gd` (78 commits since 2026-10-01) |
| D4 | Multibody scope | No general constraint solver now; SF-09 extraction only, gated on a closed-loop consumer |
| D5 | Native backend for the flight kernel | Policy now (SF-08), port only after SF-01 and target-host measurements; owner builds Windows/macOS |
| D6 | First new vehicle to consume the contract | Multirotor before boats |

## 7. Risks and rules

- **Interface for its own sake.** H10's warning stands: each extraction must delete duplicated code and stay byte-identical, or it is rejected.
- **Contended files.** `flight_session.gd` and `main.gd` each took about 80 commits since 2026-10-01; SF-01…03 need a quiet window, `git status` before every edit and one integrator at a time.
- **Dispatch cost.** GDScript `Callable` dispatch is about 1 µs; the kernel already pays it. Measure with the H15 method; the 500 µs budget is unchanged.
- **Validation.** This plan improves verification and structure. Physical validity still needs VAL-5…8 and Gate 2; software proofs cannot close them.
- **Drafts.** Keep new kernel files outside `app/` until they parse; `test.sh` parses every script and refuses 32-bit types in `sim/` and `physics/`.

## 8. Sources

[Numerics knowledge base](../research/roadmap-investigations/01-numerics-architecture-performance.md), [H8](../research/simulation-state/H8/README.md), [H10](../research/simulation-state/H10/README.md), [H15](../research/simulation-state/H15/README.md), [Gate P](../research/simulation-state/Gate-P/README.md), [physics audit 2026-10-14](../research/physics-audit-2026-10-14/README.md) and its [remediation](../research/physics-audit-2026-10-14/remediation/README.md), [helicopter plan](helicopter.md), [drone plan](drone-racing.md), [RC vehicle plan](rc-monster-truck.md), [VAL-3 dashboard](../../research/validation/dashboard.md), [DECISIONS](../../DECISIONS.md), [LEARNINGS](../../LEARNINGS.md).
