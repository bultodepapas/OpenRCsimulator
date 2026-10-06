# 01 — Numerical integration, simulation architecture, determinism and performance

**Status:** research knowledge base, 2026-10-06. **Serves:** ROADMAP rule 7 (budget), M2 (E1–E4 contacts, E3b stiction, E4 circuit golden), M4 (G2 shaft dynamics, G4 fuel), M5 (wind/turbulence, M5-W…), Gate F follow-ups, any future GDExtension port. **Read with:** [ROADMAP](../../../ROADMAP.md), [DECISIONS](../../../DECISIONS.md), [STACK](../../../STACK.md) (escape hatch), [RESEARCH § Simulation timing](../../../RESEARCH.md#simulation-timing-reproducibility-and-useful-observations), [E1 gear](../landing-gear-contact-e1.md), [E2 friction](../ground-friction-e2.md), [flight repair](../flight-repair-implementation.md), [WIND-PLAN](../../WIND-PLAN.md).

## Summary

- **RK4 at 240 Hz is the right integrator for flight.** Same evaluation budget as Euler at 960 Hz but ~100× more accurate on a 2 Hz oscillation (7.9e-6 vs 9.0e-4, derived). JSBSim (AB2/trapezoidal, 120 Hz), CRRCSim (AB2/trapezoidal, 333 Hz), ArduPilot SITL (Euler, 1200 Hz) and PX4 SIH (Euler, 250/400 Hz) all use lower-order schemes at similar or higher rates.
- **The gear rule `ω·dt < 0.1` is 27× inside RK4's stability limit** (|λ|·dt ≤ 2.70 at ζ 0.4). At 0.1 the per-period amplitude error is 5e-6; at 0.3 it is 5e-4. The real numerical problem is the **touchdown force jump** (`c·δ̇` ≠ 0 at δ = 0: 107 N = 3.8 g for the Stik at 2 m/s sink), which drops RK4 to first order and makes golden replays fragile. Fix: Hunt–Crossley damping (force ∝ δ·δ̇).
- **The rule is mass-dependent:** ω = √(Σk/m) = √(g/static sag). At 240 Hz it forces ≥ 17 mm static sag on *any* airplane; a 2.6 kg Stik with today's springs gives ω·dt = 0.102 and would be **refused** by the loader. A stiff giant-scale gear (5 mm sag) needs 443 Hz under the rule; 16 Hz for bare stability.
- **Operator splitting of rpm is first order.** Toy shaft model (I·dω/dt = Q_e − Q_p(J)): split scheme error 9.6e-3 m/s after 3 s at 240 Hz, halving per halving of dt; extended-state RK4 6.2e-11 m/s, ×16 per halving. G2 must put rotor speed **inside** the integrated state. The shaft is not stiff (τ ≈ 0.18 s, λ·dt 0.023).
- **Quaternions:** RK4 + renormalization is enough at 240 Hz (largest per-step correction 6e-14). Lie-group/exponential integrators buy nothing measurable here.
- **Determinism:** GDScript arithmetic is IEEE double, op by op (no FMA fusion across VM ops), so cross-platform differences come from libm (`sin`, `atan2`, `exp`, `pow` → `std::` → glibc / Windows CRT / Apple libm) and C++ helpers compiled with FMA contraction on arm64 (`lerpf`, `wrapf`). Measured: a 1-ulp change in atan2 moves 60 s of stalled flight, a held spin and a glide by ≤ 1.4e-12 m — the current dynamics is not chaotic; tolerance goldens (1e-6 m) have ~6 orders of margin **except across discrete branches** (contact on/off, crash, `blend == 1.0`).
- **Performance today (VM, measured):** 505–560 µs per tick (load-dependent). Breakdown: `_loads` 69 µs × **5** calls (one is redundant), `RB.derivative` 21 µs × 4, validation and allocation the rest. Post-stall `_loads` is 106–112 µs → ~570 µs/tick.
- **Flattening works:** an allocation-free `RB.derivative` is **11× faster (21 → 1.9 µs) and bit-identical** (max diff 0.0). Native C++ (-O2, `-ffp-contract=off`): 0.037 µs, ~570× the current GDScript. Callable overhead is negligible (0.10 µs).
- **Cheap fixes first, then a gated GDExtension spike** with the GDScript code kept as the test oracle. Expected after flattening: ~100–150 µs/tick (estimated), enough headroom for propwash, ground effect and turbulence in GDScript.
- **Architecture:** make the state vector generic (rigid body 13 + continuous extras), classify every state (A: continuous, in RK4; B: discrete, per tick; C: modes/events), and replace the hard-coded aero + propulsion + gear sum with a list of load contributors. Do this before G2 and M5 wind.
- **Latency:** Godot delivers input once per rendered frame; at 60 fps four 240 Hz ticks share one sample. Built-in 3D physics interpolation (Godot ≥ 4.4) does not apply to our custom state; our own lerp/nlerp adds ≈ 1 tick (4.2 ms) of display delay.

## Where the code stands

| Fact | Where |
| --- | --- |
| RK4 on 13 float64 states, quaternion renormalized after every step; `axpy` allocates a new array per stage | [integrator.gd](../../../app/physics/integrator.gd) |
| Fixed tick = `Engine.physics_ticks_per_second` (240), `max_physics_steps_per_frame` 12 (real time down to 20 fps, then slow motion); `physics_jitter_fix` left at default 0.5 | [project.godot](../../../app/project.godot) |
| `step()`: `pre_step(aux)` once → `loads(state)` for the trace → RK4 whose k1 calls `loads(state)` **again** → 5 load evaluations per tick. Time `t` is the same for all four stages | [simulation.gd](../../../app/sim/simulation.gd) |
| Every stage validates state, loads and derivative (`is_finite` loops), and a fault rolls back to the last valid tick | same |
| Aux = [rpm, servo roll, pitch, yaw], advanced by exact first-order lag (rpm) and slew limit (servos), **held constant over RK4 stages**; rotor momentum h = J_p·ω also held | [flight_session.gd](../../../app/sim/flight_session.gd) `_pre_step`, [propulsion.gd](../../../app/physics/propulsion.gd) `rpm_step` |
| Loads = `Dynamics.loads` (air data + aero + propulsion) + `Ground.loads`, hard-coded sum; surface deflections rebuilt from Dictionaries in every stage | `flight_session._loads`, [dynamics.gd](../../../app/physics/dynamics.gd) |
| Rigid-body derivative builds ~20 small `PackedFloat64Array`s per call (`M.v3`, `q_mul`, `cross`…) | [rigid_body.gd](../../../app/physics/rigid_body.gd), [math3d.gd](../../../app/physics/math3d.gd) |
| Aero reads a nested `model` Dictionary (`model.aero.CLa`: 0.22 µs per read); `local_flow_weight` evaluates the 6 wing stations + 2 tails even when the result is 0 | [aero.gd](../../../app/physics/aero.gd) |
| Gear: per-wheel spring-damper `F = max(0, kδ + cδ̇)`, regularized tyre forces; loader enforces `ω·dt < 0.1`, side `λ·dt ≤ 0.5` | [ground_contact.gd](../../../app/physics/ground_contact.gd), [E1](../landing-gear-contact-e1.md), [E2](../ground-friction-e2.md) |
| "All trig through math3d" ([DECISIONS](../../../DECISIONS.md) 2026-10-05) is **no longer true**: direct `sin/cos/atan2/pow/exp` calls in aero (11), propulsion (5), ground_contact (4), air_data (2), and the uncommitted `slipstream.gd` (5) | grep of `app/physics/` |
| Goldens: 4 maneuvers of 2.5–5 s (≤ 1200 ticks), checkpoints every 60 ticks, tolerances 1e-6 m, 1e-6 m/s, 1e-9 (quaternion), 1e-6 rad/s | [golden_flights.gd](../../../app/tests/golden_flights.gd) |
| Render: `interpolated(Engine.get_physics_interpolation_fraction())` lerps position and nlerps attitude between `previous` and `state` | `simulation.gd`, `main.gd` |
| Radio read once per tick with `Input.use_accumulated_input = false` | `main.gd`, `flight_session.gd` |

**Measured tick breakdown** (this VM: i5-10500, shared, load ≈ 3.4; Godot 4.7.2 headless; working tree of 2026-10-06 incl. other tracks' uncommitted edits; scratch copy of `app/`, best of 3 × 20 000 calls):

| Item | µs/call | Calls/tick | µs/tick |
| --- | --- | --- | --- |
| `session._loads`, trimmed (global aero path) | 69.5 | 5 | 347 |
| ↳ `Aero.local_flow_weight` (result 0) | 27.0 | | |
| ↳ `Aero._global_loads` | 12.4 | | |
| ↳ `Air.compute` / `Propulsion.loads` / deflection Dictionaries | 6.6 / 3.9 / 3.3 | | |
| `RB.derivative` | 21.0 | 4 | 84 |
| `RK.axpy` (13 values, allocates) | 1.05 | 3 | 3 |
| `state_is_valid` + finiteness checks | ~0.9 each | ~15 | ~15 |
| **Full `sim.step()`, trimmed** | | | **505–525** (bench: 505–562 by load) |
| `_loads` at α 13°/30° (local path, 5 surfaces) | 106–112 | 5 | ~550 |
| `sim.step()` for 1 s from α 30° | | | **573** |
| `Ground.loads`, 3 wheels touching / in the air | 8.3 / 0.6 | 5 | 41 / 3 |
| Per wing/tail element in `_local_loads` | ~15.6 | | |

Missing: generic state vector, stage time, contact substeps, profiler monitors, a deterministic-math guard, any per-feature cost table.

## Theory and models

### Integrators (linear test equation y′ = λy, z = λ·dt)

| Scheme | Order | Evaluations/step | Stability limit | Users |
| --- | --- | --- | --- | --- |
| Forward Euler | 1 | 1 | |1+z| ≤ 1: unstable for any undamped oscillator | ArduPilot SITL velocity/position (1200 Hz), PX4 SIH velocity/rates |
| Semi-implicit (symplectic) Euler | 1 | 1 | ω·dt < 2 (undamped), bounded energy error | Most game physics engines |
| Adams–Bashforth 2 | 2 | 1 (+history) | real axis λdt < 1; ζ 0.4 ray 0.88; **undamped: grows** 1 + 2.6e-5 per step at ωdt 0.1 (+6 % amplitude per 10 s at 240 Hz) | JSBSim default rates (AB2) + trapezoidal positions; CRRCSim (AB2 + trapezoidal, 333 Hz) |
| Classic RK4 | 4 | 4 | ζ 0 → 2.83; ζ 0.4 → 2.70; real axis 2.785 | **This repo**; YASim uses a 4-stage RK-like scheme |
| RK45 / DOP853 adaptive | 4–8 | 6–12, variable | error-controlled | Offline reference only (SciPy `solve_ivp`, RESEARCH § 7) |
| Implicit / IMEX / Rosenbrock | 1–4 | 1+ linear solves | A-stable (stiff part) | Multibody/robotics; not needed while λ·dt ≤ 0.5 |

Derived (python, scratch): per-step amplitude/phase errors of RK4 at ζ 0.4 — ωdt 0.1: 7.9e-8 / 3.4e-8; 0.4: 9.6e-5 / 1.7e-5; 1.6: 0.11 / 0.09. Per **period**: 0.1 → 5.4e-6; 0.2 → 9.2e-5; 0.3 → 4.9e-4; 0.5 → 4.2e-3.

Why RK4 here: the airframe is smooth between events, the stiffest airborne modes (roll subsidence ~10–20 /s, short period ~10 rad/s for the Stik) sit at λ·dt ≈ 0.05–0.1, and 4th order makes the `h/h/2` convergence test (C4) a sharp bug detector (ratio 16). Variable-step RK45 is unsuitable in real time: variable cost, and its accept/reject branch amplifies 1-ulp platform differences into different step sequences.

### Stiff contacts, discontinuities, event location

- A penalty contact `F = kδ + cδ̇` is a linear oscillator while compressed: λ = ω(−ζ ± i√(1−ζ²)), ω = √(k/m). Accuracy needs |λ|·dt ≲ 0.3 (per-period error < 5e-4); stability needs ≤ 2.7.
- **Order loss:** the force law has a kink (k·δ at δ = 0) and, with `cδ̇`, a jump. A step that contains the event integrates a non-smooth RHS: local error O(dt²) for a jump, O(dt³) for a kink → global first/second order. E2 measured this: ratio 2.0 per halving near the tip speed vs 12.7 away from it.
- **Event location** (find t* where δ = 0, step to it, restart) restores order but costs root finding per contact and makes the step count state-dependent; games avoid it. Cheaper equivalent: make the force law continuous.
- **Hunt–Crossley** (1975): `F = k·δⁿ + c_h·δⁿ·δ̇` (n = 1 here). Damping vanishes at δ = 0, so the force is C⁰ at touchdown, never pulls (with `max(0, …)`), and restitution depends on impact speed (realistic). c_h relates to the restitution coefficient e: c_h ≈ 3k(1−e)/(2v_impact) (Hunt–Crossley approximation; DOI resolved, text not read — verify before use).
- **Substep only the stiff part (multirate):** hold the slow loads (aero, propulsion) at their tick values and integrate rigid body + contact at N substeps. First-order coupling error between slow and fast parts; acceptable on the ground. Simpler variant for this repo: when any contact is within `reach`, run N full RK4 substeps of dt/N with the same inputs (deterministic: N depends only on state and data).
- **Lie vs Strang splitting:** Lie (A then B) is first order; Strang (½A, B, ½A) is second order (Strang 1968). Neither keeps RK4's fourth order. Use splitting only for parts that are genuinely discrete (servo frames, noise sampling) or decoupled (input filters).

### Scratchpad: RK4 stability for the gear

Formulas: ω = √(Σk/m), λ = ω(−ζ ± i√(1−ζ²)), rule ω·dt < 0.1, RK4 limit |λ|·dt ≤ 2.70 (ζ 0.4). Full 3-DOF gear modes from M⁻¹K, M⁻¹C with the loaded Stik data (m 2.885 kg; Jxx 0.1154, Jyy 0.3871 kg·m²; mains 560 N/m, c 18.6 N·s/m at x −0.094 m, y ±0.18 m; nose 440 N/m, c 16.5 at x +0.257 m):

| Mode (Stik, 240 Hz) | ω_n (rad/s) | ζ | |λ|·dt |
| --- | --- | --- | --- |
| Heave (stiffest) | 23.25 | 0.40 | 0.097 |
| Roll on gear | 17.73 | 0.29 | 0.074 |
| Pitch on gear | 10.03 | 0.18 | 0.042 |
| Heave with the brief's 2.6 kg | 24.49 | — | **0.102 → loader refuses** |

Required rates (stiffest mode). Static sag sets ω = √(g/sag) whatever the mass; P-51 values at 18.21 kg (sum of the data's inventory), 3 wheels, ζ 0.4:

| Static sag (mm) | ω (rad/s) | Hz for rule 0.1 | Hz for |λ|dt ≤ 0.3 | Hz for stability | Σk P-51 (N/m) | c per wheel (N·s/m) |
| --- | --- | --- | --- | --- | --- | --- |
| 18 (Stik today) | 23.3 | 233 | 78 | 9 | 9 921 | 113 |
| 10 | 31.3 | 313 | 104 | 12 | 17 858 | 152 |
| 5 | 44.3 | 443 | 148 | 16 | 35 716 | 215 |
| 2 (hard tyre) | 70.0 | 700 | 233 | 26 | 89 290 | 340 |
| 0.5 (hull scrape, E3d) | 140 | 1 400 | 467 | 52 | 357 158 | 680 |

Readings: (1) at 240 Hz a **giant-scale oleo gear with 10–20 mm sag (estimated, unverified) already fits the current rule**, independent of the 18 kg mass; (2) a stiff gear or a hard hull contact needs either |λ|dt ≤ 0.3 (one rule change) or 2–6 contact substeps; (3) stability is never the binding constraint. Touchdown force jump with `cδ̇`: Stik 3 wheels at 2 m/s sink → 107 N in one stage (weight 28 N).

First-order tyre terms (real axis, limit 2.785): side force λ·dt = 0.31, rolling ≤ 98 /s → 0.41 (E2/E3a). Fine.

### Operator splitting of aux states (G2)

Current: rpm and servos advance once per tick (exact), then are frozen across k1…k4. For rpm independent of the airplane state (D5 lag), the error is a half-tick time shift (≈ 2.1 ms vs τ 250 ms). With G2, Q_prop depends on J = V/(nD), so rpm and airspeed are **coupled**; splitting becomes Lie splitting with first-order global error.

Scratch toy model (1-D Stik: m 2.885 kg, I 3.5e-4 kg·m², Ct/Cp linear in J shaped like an APC 12×6 (estimated), throttle step 25 → 100 % at 0.5 s, error at 3 s vs RK4 at 1/15 360 s):

| Tick | Extended-state RK4 |Δu| (m/s) | Lie, Euler rpm | Lie, RK4 rpm with u frozen |
| --- | --- | --- | --- |
| 120 Hz | 1.0e-9 | 1.9e-2 | 8.0e-3 |
| 240 Hz | 6.2e-11 | 9.6e-3 | 4.0e-3 |
| 480 Hz | 3.9e-12 | 4.8e-3 | 2.0e-3 |

Errors are small physically but they turn the convergence test into a first-order test that hides other first-order bugs, and they make `h` vs `h/2` goldens disagree. Shaft τ = 2πI/(∂Q_p/∂n − ∂Q_e/∂n) ≈ 183 ms at 11 000 rpm (λ·dt 0.023): not stiff, costs one more state.

**Extended state vector (recommendation).** State = `[rigid body 13 | class-A extras]`, with a layout table (name, unit, class, tolerance):

| Class | Rule | Examples |
| --- | --- | --- |
| A — continuous, coupled to the airframe | In the RK4 vector; derivative computed in the same evaluation as the loads | rotor speed per rotor (G2), downwash lag (E0a uses `CLadot` later), dynamic-stall lag per strip (M5), wheel spin with brakes (E3+), turbine spool (AV-05), battery SOC + RC polarization (electrics), fuel mass (G4, slow) |
| B — discrete by nature, per tick | `pre_step`, exact discretization, zero-order hold over the stages | servo command frames and slew (real servos get pulses every 7–20 ms), radio sampling, turbulence filters driven by white noise (exact Ornstein–Uhlenbeck/Dryden update; RK4 on a noise-driven SDE is meaningless), RNG |
| C — modes and events | Tick-boundary state machine, never inside a stage | engine running/stopped, crash, gear collapse, stiction anchor per wheel (E3b), flaps/retracts position if discrete |

Notes: electric motor current has τ = L/R ≈ 0.1–1 ms (estimated) → λ·dt > 2.7 at 240 Hz: model current algebraically (quasi-static), keep only ω as a state. Time-dependent inputs inside a stage (gust schedules) need stage time `t + c_i·dt`; today `t` is passed unchanged to all stages — harmless while loads are autonomous.

**Trace/golden evolution:** trace header gains `state_layout` (names + units + class) so columns follow the layout; goldens v2 store the full extended state, per-component tolerances, the recording platform (OS, arch, Godot build, `git describe`) and the margin to the nearest discrete threshold.

### Quaternion integration

- q̇ = ½ q ⊗ (0, ω). RK4 does not preserve |q|; renormalization is a projection method and keeps the order (Hairer–Lubich–Wanner).
- Scratch: ω(t) = (3 sin 2t, 1 + 0.5 cos 3t, 6) rad/s for 60 s. Without renormalization |q|−1 = −6.0e-10 at 240 Hz (−6.2e-7 at 60 Hz); with it, the largest per-step correction is 6e-14 at 240 Hz, shrinking 2⁵ per halving.
- Alternatives: exponential map q ⊗ exp(½ω̄dt) (JSBSim `eBuss1/2`, PX4 SIH axis-angle, ArduPilot DCM rotate + normalize), JSBSim local linearization (Barker), Lie-group RK (Munthe-Kaas 1998, RKMK4 needs dexp⁻¹ corrections). They help at low rates or for long conservative integrations; at 240 Hz with dissipative aero they change nothing measurable. Keep RK4 + normalize; monitor the correction size.
- Energy drift: C3 already shows torque-free energy/momentum conserved to 1e-6 relative over 60 s.

### Determinism

- **Same binary, same CPU:** bit-identical (Dawson). The repo already proves frame-rate independence this way.
- **Across OS/CPU with GDScript:** each VM op is a separate IEEE-754 double operation (SSE2 on x86-64, NEON/FP on arm64), so `+ − × ÷ sqrt` agree. Differences come from (a) `Math::sin/cos/atan2/exp/pow` = thin wrappers over `std::` (Godot `math_funcs.h`) → the platform libm, which glibc says is not correctly rounded (errors "within a few ulp"); (b) C++ helpers like `lerp` (`from + (to − from)·weight`) and `wrapf`, which Clang may contract into FMA on arm64 (Clang default `-ffp-contract=on`; GCC default `fast` in GNU mode); x86-64 baseline has no FMA, so contraction only bites on arm64 (Apple Silicon, Linux arm64). Godot's SConstruct sets no fp-contract flag (fetched). Which toolchain builds official Windows binaries was not verified.
- **Lockstep practice:** Gaffer/Dawson: possible with discipline (strict fp model, no FMA, own transcendental functions); Box2D v3 is cross-platform deterministic with `-ffp-contract=off` and its own `atan2`/sin/cos; Jolt offers a cross-platform deterministic mode. CORE-MATH (MIT) provides correctly rounded double functions — the clean way to get identical `sin/exp/atan2` everywhere in a C++ port.
- **Measured sensitivity** (scratch copy: atan2 output × (1 + 2⁻⁵²), all atan2 calls routed through `M.atan2_`): divergence after 60 s — slow flight 8e-13 m, held spin 4e-13 m (max 1.4e-12), glide 4.5e-13 m; quaternions ≤ 4e-14. The flight model is dissipative (stall and spin are attractors), so 1-ulp differences do not grow exponentially in these regimes. The current tolerances (1e-6 m) hold ~6 orders of margin.
- **The real risk is discrete branches:** `compression > 0`, `f_up <= 0`, crash hull `>= 0`, `blend == 1.0` early exit, `rpm < STOPPED_RPM`, `surface_at` edges. A 1-ulp flip at touchdown with `cδ̇` changes one stage's force by ~107 N → Δv ≈ 107·(dt/6)/2.885 ≈ 0.026 m/s: an E4 circuit golden with a landing could fail across platforms. Hunt–Crossley makes this flip harmless (force ≈ 0 at δ ≈ 0).

## Implementation options and trade-offs

| Topic | Options | Trade-off | Recommendation |
| --- | --- | --- | --- |
| Base integrator | Keep RK4 240 Hz; AB2 at 120–333 Hz; semi-implicit Euler at 1 kHz | AB2 is 4× cheaper per step but grows on undamped modes and needs history (reset/fault rollback complexity); Euler needs ~1 kHz | **Keep RK4 240 Hz** |
| Global tick | 240 / 480 / 1000 Hz | Cost ∝ rate; helps only contacts | Keep 240; substep contacts |
| Gear rule | ω·dt < 0.1 (heave) / eigenvalue |λ|max·dt ≤ 0.3 / substeps | 0.1 is mass-dependent and over-strict; eigenvalue rule covers pitch/roll modes of odd layouts | **Eigenvalue rule ≤ 0.3**, substeps N = ⌈|λ|max·dt/0.3⌉ when in reach |
| Contact law | `kδ + cδ̇` / Hunt–Crossley / event location / implicit contact | HC: continuous, physical restitution, one line | **Hunt–Crossley** (E1b) |
| Static friction (E3b) | Regularized (today), anchor spring per wheel, LCP/PGS like JSBSim (50 PGS iterations, Catto 2005) | Anchor spring = class-C anchor + class-A spring, stays in RK4; PGS needs velocity-level solve between stages | Anchor spring (bounded by the same λ rule) |
| Aux states | Split (today) / extended state | Split = 1st order once coupled | **Extended state from G2 on** |
| Quaternion | RK4+normalize / exp map / RKMK | No measurable gain | Keep |
| Golden policy | Bit-exact everywhere / tolerance / per-platform recordings | Bit-exact breaks on libm and on any port; per-platform files multiply | **Tolerance goldens recorded on one CI reference platform (Linux x86-64) + bit-exact hash only as same-platform diagnostic** |
| Performance | Flatten GDScript / C# / GDExtension C++ | C# blocks web export (RESEARCH: Godot 4 C# cannot export to web); C++ needs a build matrix | **Flatten first; GDExtension behind a gate** |
| Threading | Main thread / separate physics thread / WorkerThreadPool per aircraft | One aircraft's RK4 is sequential; WTP adds sync cost for small tasks (Godot docs) | Main thread; WTP only for N aircraft later |

## Godot / GDScript notes

- **Precision:** GDScript `float` is 64-bit; `Vector3/Basis/Quaternion` are 32-bit unless the engine is built with `precision=double` (SConstruct option, no official builds). Keep the guard.
- **Where time goes (measured):** allocating a 3-vector 0.34 µs; a static call through a preloaded const ~0.1 µs; 3-level Dictionary read 0.22 µs; PackedFloat64Array read 0.084 µs; `sin` 0.063 µs; `Callable.call` 0.10 µs ≈ direct call 0.11 µs. Allocation and call depth dominate, not math or Callables.
- **Typed GDScript** uses optimized opcodes when types are known at compile time (Godot docs). Keep every hot variable typed (`var x: float`, `:=` on typed expressions).
- **Flattening recipe** (proven on `RB.derivative`: 21 → 1.9 µs, bit-identical): unpack the state into local floats, write the result into a caller-owned `PackedFloat64Array` (resize once), inline rotations as matrix rows, no helper returning arrays in the hot path. Keep the same operation order to stay bit-identical (that is what made the diff exactly 0.0).
- **Model pack:** at load, compile the validated `model` Dictionary into one `PackedFloat64Array` plus `const` index names (`A_CLa := 17`); per-surface blocks with a stride (as `ground_surfaces` already does).
- **Profiler:** `Performance.add_custom_monitor("physics/tick_us", callable)` shows in the editor Debugger → Monitors tab. Godot's SConstruct has `profiler=tracy|perfetto|instruments` (custom engine build); Tracy is BSD-3. For GDScript, the built-in profiler plus our bench scripts suffice.
- **Interpolation:** Godot 4.3 added 2D physics interpolation, 4.4 the 3D counterpart (release notes). It interpolates engine nodes' transforms, not our float64 state, so keep `interpolated()`; set nodes' transforms only from `_process`. `Engine.physics_jitter_fix` (default 0.5) shifts ticks against real time to smooth frame jitter; Godot recommends 0 with custom interpolation. `max_physics_steps_per_frame` (default 8; ours 12) caps catch-up: below 240/12 = 20 fps the sim runs in slow motion (no spiral of death; Fiedler clamps frame time at 0.25 s for the same reason).
- **Input sampling:** joystick events are processed once per main-loop iteration; ticks inside one frame read the same `Input.get_joy_axis` value (inference from `main_timer_sync.cpp` and the Input docs; `agile_event_flushing` exists, platform support unverified). At 60 fps that is a 60 Hz staircase over 4 ticks.
- **Latency budget (estimated, to be measured):** USB HID poll 1–8 ms + wait for frame ≤ 16.7 ms + tick boundary ≤ 4.2 ms + render interpolation ≈ 4.2 ms + GPU/vsync 1–2 frames (17–33 ms) + display 5–15 ms ≈ 35–80 ms at 60 Hz. A real airplane chain (TX mixer, RF link, servo frame, servo slew) is also tens of ms; our servo model adds the slew but not the frame delay.
- **GDExtension:** godot-cpp is versioned independently since 10.x; extensions built for an older Godot minor work in newer ones, not vice versa (`api_version=4.x` or a custom `extension_api.json`). Hot reload of extensions in the editor exists since 4.2. Build with SCons per platform (godot-cpp-template ships a CI workflow); macOS universal (arm64 + x86_64); a web build needs a separate wasm compile (STACK). Compile with `-ffp-contract=off` (GCC/Clang) and `/fp:precise` without contraction on MSVC.

## Reusable libraries, tools, code and datasets

| Name | What it gives us | License | Link | How to use here |
| --- | --- | --- | --- | --- |
| JSBSim `FGPropagate`, `FGAccelerations`, `FGFDMExec` | Integrator menu, model order, per-model rates, PGS ground friction | LGPL-2.1 | github.com/JSBSim-Team/jsbsim | Read for design; borrow numbers only (as E2 did); no code copy into MIT |
| CRRCSim `eom01`, `crrc_main` | RC-sim reference: AB2/trapezoidal at dt 0.003 s | GPL-2.0 | sourceforge.net/p/crrcsim | Read only |
| YASim `Integrator.cpp` | RK-like 4 stage + Gram–Schmidt | GPL-2.0 | github.com/FlightGear/flightgear | Read only |
| ArduPilot SITL `SIM_Aircraft` | Euler + DCM normalize at 1200 Hz default | GPL-3.0 | github.com/ArduPilot/ardupilot | Read only; JSON SITL bridge later |
| PX4 SIH | Euler/trapezoidal, axis-angle quaternion, 250/400 Hz; Ct(J)/Cp(J) props | BSD-3 | github.com/PX4/PX4-Autopilot | Design reference |
| Box2D v3 determinism notes | Recipe: no FMA, own trig, CI on x64/ARM | MIT | box2d.org/posts/2024/08/determinism/ | Policy for a C++ port |
| CORE-MATH | Correctly rounded binary64 sin/cos/exp/log/atan… | MIT | core-math.gitlabpages.inria.fr | Deterministic math in a GDExtension |
| Jolt Physics | Cross-platform deterministic mode reference | MIT | github.com/jrouwe/JoltPhysics | Reference only |
| godot-cpp / godot-cpp-template | GDExtension bindings, CI template | MIT (godot-cpp); template unverified | github.com/godotengine/godot-cpp | X-PERF-7 spike |
| godot-benchmarks | Engine benchmark harness incl. GDScript/C#/GDExtension | MIT (unverified) | github.com/godotengine/godot-benchmarks | Method for our own per-feature table |
| Tracy | Frame/zone profiler | BSD-3 | github.com/wolfpld/tracy | Only with a custom engine/GDExtension build |
| SciPy `solve_ivp` (DOP853, Radau) | Offline high-accuracy reference | BSD-3 | docs.scipy.org | Verify RK4 trajectories of new class-A states |

## Parameters and data

| Quantity | Typical value | Unit | Kind | Source |
| --- | --- | --- | --- | --- |
| Physics tick (this repo) | 240 | Hz | manual (decision) | DECISIONS 2026-10-05 |
| JSBSim default dt | 1/120 | s | manual | FGFDMExec.cpp |
| CRRCSim default dt | 0.002777 → rounded 0.003 | s | manual | crrc_main.cpp |
| ArduPilot SITL rate_hz | 1200 | Hz | manual | SIM_Aircraft.h |
| PX4 SIH loop | 250 (real time) / 400 (lockstep) | Hz | manual (as reported by fetch of sih.cpp) | sih.cpp |
| Gazebo example max_step_size | 0.001 | s | manual | Gazebo SDF worlds tutorial |
| RealFlight / aerofly / PicaSim physics rate | — | — | unverified | not found |
| RK4 stability |λ|dt (ζ 0 / 0.4 / real) | 2.83 / 2.70 / 2.785 | — | derived | this doc |
| Stik gear heave ω, ζ | 23.25, 0.40 | rad/s, — | derived from estimated k, c | E1 data |
| Giant-scale gear static sag | 5–20 | mm | estimated (unverified) | — |
| P-51 flight mass | 18.21 | kg | derived (inventory sum) | p51d_mustang_120.json |
| Stik rotor inertia J_p | 3.5e-4 | kg·m² | data | jensen_ugly_stik_60.json |
| P-51 rotor inertia | 1.31e-2 | kg·m² | data (derived) | p51d_mustang_120.json |
| Shaft time constant at full throttle (Stik) | ≈ 0.18 | s | estimated (toy model) | this doc |
| Electric motor L/R | 0.1–1 | ms | estimated | — |
| Servo frame period (analog / digital / bus) | 20 / 3–14 | ms | estimated | — |
| Tick cost now (VM) | 505–562 | µs | measured | bench_physics.gd |
| Budget | 500 | µs/tick | manual | ROADMAP rule 7 |
| Flat vs current `RB.derivative` | 1.9 vs 21–22 | µs | measured | scratch bench |
| Native C++ derivative / RK4 rigid-body step | 0.037 / 0.16 | µs | measured (g++ -O2) | scratch bench |

Estimated per-feature cost (GDScript, current style → flattened; estimated from the measured element cost 15.6 µs and the 11× flattening ratio, to be measured per step):

| Feature | Current style µs/tick | Flattened µs/tick |
| --- | --- | --- |
| +1 wing strip per side (2 elements × 5 evals) | +156 | +15–30 |
| Propwash on tail (E0b, ~4 pieces) | +150–300 | +15–40 |
| Ground effect (factor per lifting surface) | +10 | +2 |
| Dryden turbulence, 6 filters, per tick (class B) | +5 | +1 |
| Wind sampled per surface point (8 points × 5) | +40 | +5 |
| Rotor speed as state (G2) | +2 | +0.5 |
| Contact substeps ×2 on the ground | +250 (whole tick) | +60 |

## Validation

Verification (known answers):
1. RK4 on the linear oscillator at ωdt 0.1/0.3/0.5: per-period amplitude error equals R(z) analysis to 1e-12.
2. Gear eigen-analysis: drop test ring-down frequency and decay equal the M⁻¹K, M⁻¹C eigenvalues (heave 23.25 rad/s, ζ 0.40) within 1 %.
3. Hunt–Crossley: contact force continuous at δ = 0 (|F| < 1e-9 N at δ = 1e-12 m, any δ̇); restitution vs impact speed matches the closed form.
4. G2: `h`/`h/2`/`h/4` on a throttle step → ratio ≈ 16 (today's split scheme gives ≈ 2).
5. Quaternion: max per-tick renormalization correction < 1e-12 on all goldens (diagnostic).
6. Flattened functions: bit-identical to the reference implementation on 10 000 random states (0.0 diff, as measured for `RB.derivative`).
7. GDExtension port: C++ vs GDScript derivative agreement ≤ 1e-14 relative on 10 000 random states; goldens within tolerance.
8. 1-ulp sensitivity test: perturbed atan2 changes every golden by < tolerance/1000.

Independent validation (real RC behaviour): bounce frequency and number of bounces of a dropped Stik (phone video at 240 fps) vs the gear modes; throttle-step rpm trace from an optical tachometer (G2); owner perception of latency (blind A/B with an added 16 ms delay) — the only real "realism" test for timing.

Mutation tests that must fail: substeps disabled for a 5 mm-sag gear (energy gain / instability); rpm moved back to `pre_step` (convergence ratio drops); a direct `sin(` added in `app/physics/` (guard); golden tolerance set to 0 on another platform (CI); `cδ̇` restored instead of Hunt–Crossley (continuity test).

## Pitfalls and risks

1. **Lighter build refused** by the mass-dependent gear rule (2.6 kg Stik: 0.102). Mitigation: eigenvalue rule ≤ 0.3, or derive k from target sag.
2. **Golden fragility at discrete branches** (touchdown, crash, stall blend saturation). Mitigation: Hunt–Crossley; recorder stores margin to thresholds; keep goldens ≥ 1 mm/1e-3 away from them.
3. **First-order coupling hidden by splitting** once rpm depends on airspeed. Mitigation: extended state at G2.
4. **Optimizations that change operation order** break bit-identity and force golden re-records. Mitigation: flatten with identical order, verify 0.0 diff before merging; re-record only on deliberate physics changes.
5. **"All trig in math3d" silently eroded.** Mitigation: test.sh grep guard for bare transcendental calls in `app/physics`, `app/sim`.
6. **Post-stall cost spike** (local path 110 µs/eval) exceeds budget during spins. Mitigation: skip `local_flow_weight` surface loop when the α/β pre-check is far from limits; flatten `_local_loads`.
7. **Redundant k1 evaluation** (14 % of the tick). Mitigation: reuse `current_loads` as the loads of stage 1.
8. **arm64 FMA in engine helpers** (`lerpf`, `wrapf`) gives macOS-ARM vs x86 differences. Mitigation: tolerance goldens; in C++ use `-ffp-contract=off`; avoid `lerpf` in physics (write `a + (b − a)·t` in GDScript, which cannot fuse).
9. **Noise-driven filters inside RK4** (turbulence) would be wrong and non-reproducible. Mitigation: class B, exact discrete update, seeded integer RNG (`randfn` uses transcendental functions — implement Box–Muller through math3d).
10. **Threading the single-aircraft step** adds sync cost and nondeterminism risk. Mitigation: stay on the main thread.
11. **GDExtension maintenance** (3 OS + universal macOS + web). Mitigation: gate on measured need; keep the GDScript implementation as the oracle and fallback.
12. **VM noise** (±10 % measured between runs). Mitigation: per-component microbenchmarks and best-of-N; decide on the owner's hardware (D7 overlay).

## Proposed roadmap steps

| Proposed ID | Step | Proof | Depends on |
| --- | --- | --- | --- |
| X-PERF-1 | Custom monitors `physics/tick_us`, `physics/loads_us`; commit a per-component bench (like the scratch `bench_breakdown`) | Monitors visible; table of µs per component in the commit | — |
| X-PERF-2 | Reuse the tick's `current_loads` as stage-1 loads; build deflections once per tick | Goldens bit-identical; tick −60…70 µs | X-PERF-1 |
| X-PERF-3 | Allocation-free `RB.derivative` and in-place RK4 stages (preallocated k1…k4) | 0.0 diff on 10 000 random states; goldens bit-identical; −80 µs | X-PERF-1 |
| X-PERF-4 | Compile `model` into a flat pack with index constants; flatten `Air`, `_global_loads`, `local_flow_weight` early-out | Goldens bit-identical; tick ≤ 250 µs trimmed | X-PERF-3 |
| X-PERF-5 | Flatten `_local_loads` and `Ground.loads` | Spin tick ≤ 250 µs; goldens bit-identical | X-PERF-4 |
| X-DET-1 | Route every transcendental call in `app/physics`, `app/sim` through math3d; test.sh guard | Guard fails on an injected `sin(`; goldens bit-identical | — |
| X-DET-2 | 1-ulp sensitivity test (perturb `M.atan2_`/`sin_`, replay goldens, require < tol/1000) | Test passes; fails if a golden crosses a branch | X-DET-1 |
| X-NUM-1 | Loader gear rule from the eigenvalues of the gear's M⁻¹K, M⁻¹C, limit |λ|max·dt ≤ 0.3 | Stik unchanged; 2.6 kg variant accepted; ring-down matches eigenvalues ±1 % | — |
| E1b | Hunt–Crossley damping in `ground_contact.gd` (data keeps ζ; c_h derived) | Force continuous at δ = 0; touchdown `h/h/2` ratio ≥ 8 (was ~2); drop test no energy gain | X-NUM-1 |
| X-NUM-2 | Contact substeps N = ⌈|λ|max·dt/0.3⌉ while any contact is within reach | P-51 test gear with 5 mm sag lands without energy gain; air path bit-identical; ground cost measured | E1b |
| X-ARCH-1 | Generic state: `RB.SIZE + extras` with a layout table (name, unit, class, tolerance); trace header `state_layout`; golden v2 reader keeps v1 | Old goldens replay; trace header lists layout | — |
| G2a | Rotor speed as a class-A state; shaft balance I·dω/dt = Q_e − Q_p(J); rotor momentum per stage | Throttle-step convergence ratio ≈ 16; trace | X-ARCH-1 |
| X-ARCH-2 | Load-contributor list (`aero`, `propulsion`, `gear`, `slipstream`): `prepare(model) → pack`, `add_loads(state, ctx, out)` | Goldens bit-identical; adding a no-op contributor changes nothing | X-PERF-4 |
| X-LAT-1 | Measure input timing: per-tick input trace at 30/60/144 fps; try `agile_event_flushing`; record budget | Trace shows sampling staircase; decision recorded | — |
| X-DET-3 | Golden v2 policy: CI reference platform, per-component tolerances, platform stamp, threshold margin | CI fails on a mutated tolerance; macOS/Windows runs reported, not gating | X-ARCH-1, X-DET-2 |
| M5-W-num | Stage time `t + c_i·dt` to loads; turbulence filters as class B with seeded RNG through math3d | Frozen-field test: same seed → identical trace; filter variance matches theory ±5 % | X-ARCH-1, X-ARCH-2 |
| X-ARCH-3 | `Aircraft` instance object (state, aux, pack, contributors) so N aircraft step in one session | Two aircraft: each bit-identical to flying alone | X-ARCH-2 |
| X-PERF-6 (gate) | Decide GDExtension: only if flattened tick > 250 µs with planned M2–M5 features on the owner's slowest machine | Measured table + DECISIONS row | X-PERF-5 |
| X-PERF-7 | GDExtension spike: RB derivative + RK4 in C++ (godot-cpp pinned, `-ffp-contract=off`), GDScript kept as oracle; CI builds Linux/Windows/macOS universal | Derivative agreement ≤ 1e-14 rel. on 10 000 states; goldens within tolerance; per-OS smoke | X-PERF-6 |

## Decisions to take now

1. **State vector is extensible before G2** (X-ARCH-1): class A in RK4, class B per tick, class C events. Retrofitting after G2/M5 means re-recording every golden twice.
2. **Golden policy:** tolerance-based, recorded and gating on one CI reference platform; bit-exact only as a same-binary diagnostic. Survives a C++ port and libm changes.
3. **Keep RK4 at 240 Hz**; replace the heave rule with an eigenvalue rule (≤ 0.3) and handle stiff contacts with substeps, not a global tick increase.
4. **Hunt–Crossley contact damping** for every new contact (gear, hull scrape, stiction anchor).
5. **math3d is the only door to transcendental functions** (guarded), so a deterministic library (CORE-MATH) can be swapped in for multiplayer/replay sharing.
6. **Performance order:** flatten (X-PERF-2…5) before any GDExtension; GDExtension only through the X-PERF-6 gate. Owner input needed: tick cost on the slowest machine (D7 overlay).
7. **Physics stays on the main thread**; threads only for multiple aircraft or asset preparation.
8. Set `physics_jitter_fix = 0`? Recommended by Godot for custom interpolation; needs a frame-pacing check (VQ-01b logger) before changing — owner's call after X-LAT-1.

## Sources

1. JSBSim Team, `src/models/FGPropagate.h` (integrator enum, defaults AB2/trapezoidal), 2026, https://raw.githubusercontent.com/JSBSim-Team/jsbsim/master/src/models/FGPropagate.h — fetched
2. JSBSim Team, `src/models/FGPropagate.cpp` (quaternion integration, Buss/local linearization, normalize), https://raw.githubusercontent.com/JSBSim-Team/jsbsim/master/src/models/FGPropagate.cpp — fetched
3. JSBSim Team, `src/FGFDMExec.cpp` (dT = 1/120, model order, per-model rates), https://raw.githubusercontent.com/JSBSim-Team/jsbsim/master/src/FGFDMExec.cpp — fetched
4. JSBSim Team, `src/models/FGAccelerations.cpp` (friction by Lagrange multipliers, PGS, 50 iterations), https://raw.githubusercontent.com/JSBSim-Team/jsbsim/master/src/models/FGAccelerations.cpp — fetched
5. CRRCSim, `src/crrc_main.cpp` (dt default 0.002777, rounded to ms), https://sourceforge.net/p/crrcsim/code/ci/default/tree/src/crrc_main.cpp — fetched
6. CRRCSim, `src/mod_fdm/eom01/eom01.cpp` (AB2 + trapezoidal, quaternion normalization), https://sourceforge.net/p/crrcsim/code/ci/default/tree/src/mod_fdm/eom01/eom01.cpp — fetched
7. FlightGear, YASim `Integrator.cpp`, https://raw.githubusercontent.com/FlightGear/flightgear/next/src/FDM/YASim/Integrator.cpp — fetched
8. FlightGear, YASim `Model.cpp`, https://raw.githubusercontent.com/FlightGear/flightgear/next/src/FDM/YASim/Model.cpp — fetched
9. ArduPilot, `libraries/SITL/SIM_Aircraft.cpp`, https://raw.githubusercontent.com/ArduPilot/ardupilot/master/libraries/SITL/SIM_Aircraft.cpp — fetched
10. ArduPilot, `libraries/SITL/SIM_Aircraft.h` (rate_hz 1200), https://raw.githubusercontent.com/ArduPilot/ardupilot/master/libraries/SITL/SIM_Aircraft.h — fetched
11. ArduPilot, SITL JSON interface, https://ardupilot.org/dev/docs/sitl-with-JSON.html — fetched
12. PX4, `simulator_sih/sih.cpp`, https://raw.githubusercontent.com/PX4/PX4-Autopilot/main/src/modules/simulation/simulator_sih/sih.cpp — fetched
13. PX4, Simulation-In-Hardware docs, https://docs.px4.io/main/en/sim_sih/ — fetched
14. Open Robotics, Gazebo "SDF worlds" tutorial, https://gazebosim.org/docs/latest/sdf_worlds/ — fetched
15. G. Fiedler, "Fix Your Timestep!", https://gafferongames.com/post/fix_your_timestep/ — fetched
16. G. Fiedler, "Floating Point Determinism", https://gafferongames.com/post/floating_point_determinism/ — fetched
17. B. Dawson, "Floating-Point Determinism", 2013, https://randomascii.wordpress.com/2013/07/16/floating-point-determinism/ — fetched
18. E. Catto, "Determinism" (Box2D v3), 2024, https://box2d.org/posts/2024/08/determinism/ — fetched
19. J. Rouwe, Jolt Physics README, https://raw.githubusercontent.com/jrouwe/JoltPhysics/master/README.md — fetched
20. GNU C Library manual, "Known Maximum Errors in Math Functions", https://sourceware.org/glibc/manual/latest/html_node/Errors-in-Math-Functions.html — fetched
21. CORE-MATH project, https://core-math.gitlabpages.inria.fr/ — fetched
22. LLVM, Clang Users Manual (`-ffp-contract`, `-ffp-model`), https://clang.llvm.org/docs/UsersManual.html — fetched
23. GCC, Optimize Options (`-ffp-contract`), https://gcc.gnu.org/onlinedocs/gcc/Optimize-Options.html — fetched
24. Godot Engine, `core/math/math_funcs.h`, https://raw.githubusercontent.com/godotengine/godot/master/core/math/math_funcs.h — fetched
25. Godot Engine, `SConstruct` (precision, profiler options), https://raw.githubusercontent.com/godotengine/godot/master/SConstruct — fetched
26. Godot Engine, `main/main_timer_sync.cpp`, https://raw.githubusercontent.com/godotengine/godot/master/main/main_timer_sync.cpp — fetched
27. Godot docs, Engine class (jitter fix, max steps, interpolation fraction), https://docs.godotengine.org/en/stable/classes/class_engine.html — fetched
28. Godot docs, Physics interpolation introduction, https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/physics_interpolation_introduction.html — fetched
29. Godot docs, Using physics interpolation, https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/using_physics_interpolation.html — fetched
30. Godot Foundation, Godot 4.4 release page, https://godotengine.org/releases/4.4/ — fetched
31. Godot Foundation, "Godot 4.2 arrives in style" (GDExtension hot reload), https://godotengine.org/article/godot-4-2-arrives-in-style/ — fetched
32. Godot docs, Performance class (`add_custom_monitor`), https://docs.godotengine.org/en/stable/classes/class_performance.html — fetched
33. Godot docs, WorkerThreadPool, https://docs.godotengine.org/en/stable/classes/class_workerthreadpool.html — fetched
34. Godot docs, Static typing in GDScript, https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/static_typing.html — fetched
35. Godot docs, Scripting languages, https://docs.godotengine.org/en/stable/getting_started/step_by_step/scripting_languages.html — fetched
36. Godot docs, About godot-cpp, https://docs.godotengine.org/en/stable/tutorials/scripting/cpp/about_godot_cpp.html — fetched
37. godot-cpp README, https://raw.githubusercontent.com/godotengine/godot-cpp/master/README.md — fetched
38. godot-cpp-template README, https://raw.githubusercontent.com/godotengine/godot-cpp-template/main/README.md — fetched
39. godot-benchmarks README, https://raw.githubusercontent.com/godotengine/godot-benchmarks/main/README.md — fetched
40. Godot docs, Input class (`use_accumulated_input`, buffered events), https://docs.godotengine.org/en/stable/classes/class_input.html — fetched
41. Tracy Profiler LICENSE (BSD-3), https://raw.githubusercontent.com/wolfpld/tracy/master/LICENSE — fetched
42. K. H. Hunt, F. R. E. Crossley, "Coefficient of Restitution Interpreted as Damping in Vibroimpact", J. Appl. Mech. 42(2):440, 1975, https://doi.org/10.1115/1.3423596 — DOI resolved, text not read
43. H. Munthe-Kaas, "Runge-Kutta methods on Lie groups", BIT 38, 1998, https://doi.org/10.1007/BF02510919 — DOI resolved, text not read
44. G. Strang, "On the construction and comparison of difference schemes", SIAM J. Numer. Anal. 5(3), 1968, https://doi.org/10.1137/0705041 — DOI resolved, text not read
45. E. Hairer, C. Lubich, G. Wanner, *Geometric Numerical Integration*, Springer, https://doi.org/10.1007/3-540-30666-8 — DOI resolved, text not read
46. Repo evidence: scratch measurements of 2026-10-06 (tick breakdown, flat derivative, C++ derivative, 1-ulp divergence, RK4/AB2 stability, splitting, quaternion drift), made on a copy of `app/` and python3; not committed. Formulas and numbers are in this document.
