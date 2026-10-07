# 01 — Numerical integration, simulation architecture, determinism and performance

**Status:** research knowledge base, initially measured 2026-10-06; current-state notes reconciled against the project audit dated 2026-10-06. **Serves:** ROADMAP rule 7 (budget), M2 (E1–E4 contacts, E3b stiction, E4 circuit golden), M4 (G2 shaft dynamics, G4 fuel), M5 (wind/turbulence, M5-W…), Gate F follow-ups, any future GDExtension port. **Read with:** [ROADMAP](../../../ROADMAP.md), [DECISIONS](../../../DECISIONS.md), [STACK](../../../STACK.md) (escape hatch), [RESEARCH § Simulation timing](../../../RESEARCH.md#simulation-timing-reproducibility-and-useful-observations), [E1 gear](../landing-gear-contact-e1.md), [E2 friction](../ground-friction-e2.md), [flight repair](../flight-repair-implementation.md), [WIND-PLAN](../../WIND-PLAN.md).

## Summary

- **RK4 at 240 Hz is the right integrator for flight.** Same evaluation budget as Euler at 960 Hz but ~100× more accurate on a 2 Hz oscillation (7.9e-6 vs 9.0e-4, derived). JSBSim (AB2/trapezoidal, 120 Hz), CRRCSim (AB2/trapezoidal, 333 Hz), ArduPilot SITL (Euler, 1200 Hz) and PX4 SIH (Euler, 250/400 Hz) all use lower-order schemes at similar or higher rates.
- **Contact onset needs an evidence-led law, not a solver slogan.** The original calculation found a touchdown force jump from `c·δ̇` at δ = 0 (107 N = 3.8 g for the Stik at 2 m/s sink). E1b now asks for a continuous onset law selected by energy and refinement evidence (Hunt–Crossley and ramped damping remain candidates); switching contacts can still lower global order, so require fourth-order convergence only on smooth intervals.
- **The rule is mass-dependent:** ω = √(Σk/m) = √(g/static sag). At 240 Hz it forces ≥ 17 mm static sag on *any* airplane; a 2.6 kg Stik with today's springs gives ω·dt = 0.102 and would be **refused** by the loader. A stiff giant-scale gear (5 mm sag) needs 443 Hz under the rule; 16 Hz for bare stability.
- **The RK4 claim applies to the rigid-body kernel with frozen auxiliaries.** The original toy shaft comparison found O(dt) splitting error versus fourth-order extended-state RK4. The independent P-51 full-session throttle-step probe also converged at first order, while body-only refinement remained fourth order ([audit T1](../project-audit-2026-10-06/physics.md#t1--the-full-flight-session-is-split-order-time-dependent-rk-stage-loads-are-not-wired-through)). H8 should establish the minimum state contract before anchors or coupled shaft work; G2 should integrate coupled rotor speed through RK stages and test the full session.
- **Quaternions:** RK4 + renormalization is enough at 240 Hz (largest per-step correction 6e-14). Lie-group/exponential integrators buy nothing measurable here.
- **Determinism:** GDScript arithmetic is IEEE double, op by op (no FMA fusion across VM ops), so cross-platform differences come from libm (`sin`, `atan2`, `exp`, `pow` → `std::` → glibc / Windows CRT / Apple libm) and C++ helpers compiled with FMA contraction on arm64 (`lerpf`, `wrapf`). Measured: a 1-ulp change in atan2 moves 60 s of stalled flight, a held spin and a glide by ≤ 1.4e-12 m — the current dynamics is not chaotic; tolerance goldens (1e-6 m) have ~6 orders of margin **except across discrete branches** (contact on/off, crash, `blend == 1.0`).
- **Audit performance reference (exploratory):** on a shared Linux host under concurrent audit load and with a pre-existing renderer, best of three runs measured Stik 408/370, Extra 448/457, P-51 1,256/1,187 and Avanti 412/404 µs/tick (trimmed / α=15°). This is not a controlled regression comparison or a target-machine certificate; the P-51 cost makes one-aircraft headroom claims insufficient. See the full [audit context and evidence](../project-audit-2026-10-06/README.md#verified-lead-findings).
- **H1–H3 are complete:** H1 adds per-component measurements to the physics bench; H2 reuses stage-1 loads and caches deflections (four rather than five load evaluations per tick); H3 replaces the vector-heavy rigid-body derivative with a scalar implementation using one result allocation. The derivative remains byte-identical in 10,000 seeded cases and measured 21.2 → 2.8 µs/call on the development VM. The scratch C++ comparison used the pre-H3 GDScript cost and is not a current speedup ratio.
- **Performance:** preserve GDScript until representative all-aircraft, all-regime measurements on the owner’s slowest supported machine show a need. The all-aircraft audit figures above are exploratory and under contention; the single-model component profile below is an older diagnostic snapshot. H4/H5 profile and optimize measured hot paths; Gate P uses 500 µs/tick or a documented near-term reserve, not a 250 µs migration threshold.
- **Architecture:** before E3b anchors or coupled G2 shaft work, H8 should define only the state semantics those consumers need: continuous state in RK4, sampled state advanced per tick and held over stages, discrete modes at tick boundaries, per-stage time, trace/reset behavior and fault rollback. Do not require a general state/plugin registry or load-contributor framework for this step.
- **Latency:** Godot delivers input once per rendered frame; at 60 fps four 240 Hz ticks share one sample. Built-in 3D physics interpolation (Godot ≥ 4.4) does not apply to our custom state; our own lerp/nlerp adds ≈ 1 tick (4.2 ms) of display delay.

## Where the code stands

| Fact | Where |
| --- | --- |
| RK4 on 13 float64 states, quaternion renormalized after every step; `axpy` allocates a new array per stage | [integrator.gd](../../../app/physics/integrator.gd) |
| Fixed tick = `Engine.physics_ticks_per_second` (240), `max_physics_steps_per_frame` 12 (real time down to 20 fps, then slow motion); `physics_jitter_fix` left at default 0.5 | [project.godot](../../../app/project.godot) |
| `step()`: `pre_step(aux)` once → `loads(state)` reused for trace and RK4 k1 → 4 load evaluations per tick. H8a supplies stage times `t`, `t + dt/2`, `t + dt/2`, `t + dt` while retaining the cached k1 evaluation | [simulation.gd](../../../app/sim/simulation.gd) |
| Every stage validates state, loads and derivative (`is_finite` loops), and a fault rolls back to the last valid tick | same |
| Aux = [rpm, servo roll, pitch, yaw], advanced once per tick by lag/shaft/turbine rules and servo slew, then **frozen over RK4 stages**; rotor momentum h is frozen too. This makes the current P-51 coupled shaft/session path first order even though the rigid-body kernel is RK4 | [flight_session.gd](../../../app/sim/flight_session.gd) `_pre_step`, [propulsion.gd](../../../app/physics/propulsion.gd), [turbine.gd](../../../app/physics/turbine.gd) |
| Loads = `Dynamics.loads` (air data + aero + propulsion) + `Ground.loads`, hard-coded sum; surface deflections cached by sampled servo positions (H2) | `flight_session._loads`, [dynamics.gd](../../../app/physics/dynamics.gd) |
| H3's rigid-body derivative preserves operation order in scalar arithmetic and returns one `PackedFloat64Array`; RK4 stage allocation remains for later profiling | [rigid_body.gd](../../../app/physics/rigid_body.gd), [math3d.gd](../../../app/physics/math3d.gd) |
| Aero reads a nested `model` Dictionary (`model.aero.CLa`: 0.22 µs per read); `local_flow_weight` evaluates the 6 wing stations + 2 tails even when the result is 0 | [aero.gd](../../../app/physics/aero.gd) |
| Gear: per-wheel spring-damper `F = max(0, kδ + cδ̇)`, regularized tyre forces; loader enforces `ω·dt < 0.1`, side `λ·dt ≤ 0.5` | [ground_contact.gd](../../../app/physics/ground_contact.gd), [E1](../landing-gear-contact-e1.md), [E2](../ground-friction-e2.md) |
| "All trig through math3d" ([DECISIONS](../../../DECISIONS.md) 2026-10-05) is **no longer true**: direct transcendental calls remain in aero, propulsion, ground contact, air data and the committed `slipstream.gd` | grep of `app/physics/` |
| Goldens: 4 maneuvers of 2.5–5 s (≤ 1200 ticks), checkpoints every 60 ticks, tolerances 1e-6 m, 1e-6 m/s, 1e-9 (quaternion), 1e-6 rad/s | [golden_flights.gd](../../../app/tests/golden_flights.gd) |
| Render: `interpolated(Engine.get_physics_interpolation_fraction())` lerps position and nlerps attitude between `previous` and `state` | `simulation.gd`, `main.gd` |
| Radio read once per tick with `Input.use_accumulated_input = false` | `main.gd`, `flight_session.gd` |

**Historical single-model component profile** (i5-10500 shared VM; Godot 4.7.2 headless; 2026-10-06 scratch copy included other tracks' then-uncommitted edits; best of 3 × 20,000 calls). Keep as diagnostic evidence only; the current performance reference is the four-aircraft audit table above.

| Item | µs/call | Calls/tick | µs/tick |
| --- | --- | --- | --- |
| `session._loads`, trimmed (global aero path) | 69.5 | 5 | 347 |
| ↳ `Aero.local_flow_weight` (result 0) | 27.0 | | |
| ↳ `Aero._global_loads` | 12.4 | | |
| ↳ `Air.compute` / `Propulsion.loads` / deflection Dictionaries | 6.6 / 3.9 / 3.3 | | |
| `RB.derivative` | 21.0 | 4 | 84 |
| `RK.axpy` (13 values, allocates) | 1.05 | 3 | 3 |
| `state_is_valid` + finiteness checks | ~0.9 each | ~15 | ~15 |
| **Full `sim.step()`, trimmed** | | | **505–525** (bench: 505–562 by load; historical snapshot) |
| `_loads` at α 13°/30° (local path, 5 surfaces) | 106–112 | 5 | ~550 |
| `sim.step()` for 1 s from α 30° | | | **573** |
| `Ground.loads`, 3 wheels touching / in the air | 8.3 / 0.6 | 5 | 41 / 3 |
| Per wing/tail element in `_local_loads` | ~15.6 | | |

Remaining Phase H work includes H4/H5 profiling-led optimization, H6/H7 deterministic-math checks, H8's bounded state/time/rollback contract, H9 tolerance-golden policy, and H11 contact stability/accuracy policy. H1–H3's cost bench, redundant-load removal, and scalar derivative are complete; use ROADMAP for active steps and gates.

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

Current: rpm and servos advance once per tick, then are frozen across k1…k4. The rigid-body kernel therefore remains RK4 for this frozen-auxiliary RHS. Once shaft rpm depends on airspeed through `J = V/(nD)`, the full session is coupled and the split update is only first order. The audit's isolated P-51 throttle-step probe measured adjacent-resolution RPM differences of 1.516, 0.756, 0.378 and 0.189 rpm from 240 through 3840 Hz, with the same halving trend in combined state/aux differences ([probe and output](../project-audit-2026-10-06/evidence/p51-step-halving.gd), [log](../project-audit-2026-10-06/evidence/p51-step-halving.txt)). This confirms an integration-order issue; it does not establish that the 240 Hz error is large enough to require an emergency rewrite.

Scratch toy model (1-D Stik: m 2.885 kg, I 3.5e-4 kg·m², Ct/Cp linear in J shaped like an APC 12×6 (estimated), throttle step 25 → 100 % at 0.5 s, error at 3 s vs RK4 at 1/15 360 s):

| Tick | Extended-state RK4 |Δu| (m/s) | Lie, Euler rpm | Lie, RK4 rpm with u frozen |
| --- | --- | --- | --- |
| 120 Hz | 1.0e-9 | 1.9e-2 | 8.0e-3 |
| 240 Hz | 6.2e-11 | 9.6e-3 | 4.0e-3 |
| 480 Hz | 3.9e-12 | 4.8e-3 | 2.0e-3 |

Errors are small physically but they turn the convergence test into a first-order test that hides other first-order bugs, and they make `h` vs `h/2` goldens disagree. Shaft τ = 2πI/(∂Q_p/∂n − ∂Q_e/∂n) ≈ 183 ms at 11 000 rpm (λ·dt 0.023): not stiff, costs one more state.

**Minimal H8 state contract (recommendation).** Extend the current state only for actual near-term consumers. Record each value's name, unit, class and tolerance; define initialization/reset, trace/checkpoint layout and fault rollback before adding wheel anchors or further coupled shaft dynamics.

| Class | Rule | Examples |
| --- | --- | --- |
| Continuous | In the RK4 state when coupled to rigid-body loads; evaluate derivatives and loads at the same stage | coupled rotor speed (G2); add other continuous states only when a feature needs them |
| Sampled | Advance at the tick/sample boundary and hold explicitly over stages, or evaluate a prescribed input at RK stage time | radio/input samples, servo command frames, seeded turbulence filters |
| Discrete | Tick-boundary state machine with explicit transition and rollback rules | engine running/stopped, crash, gear collapse and wheel-anchor mode |

Notes: electric motor current has τ = L/R ≈ 0.1–1 ms (estimated), so model current algebraically unless a future electrical transient requires otherwise. Time-dependent inputs inside a stage (gust schedules) need stage time `t + c_i·dt`; [H8a](../simulation-state/H8a/README.md) now supplies those times and verifies a coupled analytic solution. Current aircraft loads remain autonomous; shaft coupling and full checkpoint/rollback semantics are still open.

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
- **The real risk is discrete branches:** `compression > 0`, `f_up <= 0`, crash hull `>= 0`, `blend == 1.0` early exit, `rpm < STOPPED_RPM`, `surface_at` edges. A 1-ulp flip at touchdown with `cδ̇` changes one stage's force by ~107 N → Δv ≈ 107·(dt/6)/2.885 ≈ 0.026 m/s: an E4 circuit golden with a landing could fail across platforms. E1b should select a continuous onset law; switching may still reduce global order.

## Implementation options and trade-offs

| Topic | Options | Trade-off | Recommendation |
| --- | --- | --- | --- |
| Base integrator | Keep RK4 240 Hz; AB2 at 120–333 Hz; semi-implicit Euler at 1 kHz | AB2 is 4× cheaper per step but grows on undamped modes and needs history (reset/fault rollback complexity); Euler needs ~1 kHz | **Keep RK4 240 Hz** |
| Global tick | 240 / 480 / 1000 Hz | Cost ∝ rate; helps only contacts | Keep 240; substep contacts |
| Gear/contact policy | Current heuristic / coupled-mode bound / contact substeps | A scalar cutoff alone does not establish accuracy through switching; use H11 ring-down, no-energy-gain and refinement evidence | **H11 derives supported policy; no universal 0.3 bound preselected** |
| Contact law | `kδ + cδ̇` / ramped damping / Hunt–Crossley / event location | Select by energy and refinement evidence; contact switching may reduce global order | **E1b evidence-led choice** |
| Static friction (E3b) | Regularized (today), anchor spring per wheel, LCP/PGS like JSBSim (50 PGS iterations, Catto 2005) | Anchors require H8 state ownership; contact policy and thresholds need separate evidence | Anchor candidate after H8; calibrate static resistance separately |
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
| godot-cpp / godot-cpp-template | GDExtension bindings, CI template | MIT (godot-cpp); template unverified | github.com/godotengine/godot-cpp | Conditional Gate P follow-up only |
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
| Historical single-model tick cost (VM) | 505–562 | µs | measured, 2026-10-06 scratch baseline | bench_physics.gd |
| Budget | 500 | µs/tick | manual | ROADMAP rule 7 |
| Flat vs current `RB.derivative` | 1.9 vs 21–22 | µs | measured | scratch bench |
| Native C++ derivative / RK4 rigid-body step | 0.037 / 0.16 | µs | measured (g++ -O2) | scratch bench |

Historical per-feature estimates (GDScript, current style → flattened; estimated from the then-measured element cost 15.6 µs and 11× derivative flattening ratio; these are hypotheses, not current all-aircraft measurements):

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
3. E1b candidate-law validation: continuous force at δ = 0 and no energy gain; compare h/h₂ through touchdown and report smooth-interval order separately.
4. G2: `h`/`h/2`/`h/4` on a throttle step → ratio ≈ 16 (today's split scheme gives ≈ 2).
5. Quaternion: max per-tick renormalization correction < 1e-12 on all goldens (diagnostic).
6. Flattened functions: bit-identical to the reference implementation on 10 000 random states (0.0 diff, as measured for `RB.derivative`).
7. GDExtension port: C++ vs GDScript derivative agreement ≤ 1e-14 relative on 10 000 random states; goldens within tolerance.
8. 1-ulp sensitivity test: perturbed atan2 changes every golden by < tolerance/1000.

Independent validation (real RC behaviour): bounce frequency and number of bounces of a dropped Stik (phone video at 240 fps) vs the gear modes; throttle-step rpm trace from an optical tachometer (G2); owner perception of latency (blind A/B with an added 16 ms delay) — the only real "realism" test for timing.

Proposed mutation checks: test any H11-selected contact bound/substep policy; move shaft rpm back to `pre_step` (full-session convergence degrades); inject a direct `sin(` (H6 guard); exceed an accepted cross-platform golden tolerance; restore a discontinuous damping law after E1b.

## Pitfalls and risks

1. **Historical lighter-build concern:** the 2.6 kg estimate exceeded the old ω·dt < 0.1 heuristic (0.102). H11 now owns the contact policy; assess representative coupled modes and refinement before changing the loader rule.
2. **Golden fragility at discrete branches** (touchdown, crash, stall blend saturation). E1b selects a continuous onset law from energy/refinement evidence; preserve threshold-margin diagnostics and rollback/replay checks.
3. **First-order coupling hidden by splitting** once rpm depends on airspeed. Mitigation: extended state at G2.
4. **Optimizations that change operation order** break bit-identity and force golden re-records. Mitigation: flatten with identical order, verify 0.0 diff before merging; re-record only on deliberate physics changes.
5. **"All trig in math3d" silently eroded.** Mitigation: test.sh grep guard for bare transcendental calls in `app/physics`, `app/sim`.
6. **Post-stall cost spike** (local path 110 µs/eval in the historical profile) may exceed budget during spins. H1 now measures stalled states; H4/H5 decide whether skipping `local_flow_weight` work or flattening `_local_loads` is justified.
7. **Redundant k1 evaluation** (14 % of the tick). Resolved by H2: reuse stage-1 loads and cache deflections.
8. **arm64 FMA in engine helpers** (`lerpf`, `wrapf`) gives macOS-ARM vs x86 differences. Mitigation: tolerance goldens; in C++ use `-ffp-contract=off`; avoid `lerpf` in physics (write `a + (b − a)·t` in GDScript, which cannot fuse).
9. **Noise-driven filters inside RK4** (turbulence) would be wrong and non-reproducible. Mitigation: class B, exact discrete update, seeded integer RNG (`randfn` uses transcendental functions — implement Box–Muller through math3d).
10. **Threading the single-aircraft step** adds sync cost and nondeterminism risk. Mitigation: stay on the main thread.
11. **GDExtension maintenance** (3 OS + universal macOS + web). Gate P uses the 500 µs/tick budget or documented near-term reserve on the owner’s slowest supported machine; retain GDScript as oracle/fallback.
12. **VM noise** (±10 % measured between runs). Mitigation: per-component microbenchmarks and best-of-N; decide on the owner's hardware (D7 overlay).

## Research proposals reconciled to the current roadmap

The original X-prefixed proposals below are superseded. ROADMAP owns active IDs, sequencing and acceptance criteria; the mapping here preserves useful evidence without retaining old performance gates or implementation mandates.

| Proposed ID | Step | Proof | Depends on |
| --- | --- | --- | --- |
| H1–H3 ✅ | Per-component bench; reuse stage-1 loads/cache deflections; scalar rigid-body derivative | Completed with component timings, 4 loads/tick, and byte-identical derivative checks; see ROADMAP Phase H | — |
| H4–H5 | Profile all active aircraft and optimize hot aero/local/ground paths only where measured | Same-host per-aircraft and per-regime before/after evidence; preserve same-machine trajectories; no fixed 250 µs target | H1–H3 |
| H6 | Route every transcendental call in `physics/` and `sim/` through math3d; guard in `test.sh` | Guard fails on an injected `sin(`; goldens bit-identical | — |
| H7 | 1-ulp sensitivity test (perturb `atan2_`/`sin_`, replay the goldens) | Air goldens stay below tolerance/1000; test detects a golden crossing a branch | H6 |
| H11 | Establish contact stability/accuracy policy from coupled contact modes; consider substeps only outside supported 240 Hz range | Ring-down, no-energy-gain and h/h₂ refinement over representative masses/stiffnesses; scalar eigenvalue heuristic alone does not justify a policy switch | H1–H3 |
| E1b | Select continuous touchdown damping/contact onset (for example ramped damping or Hunt–Crossley) from energy/refinement evidence | No force jump or energy gain; h/h₂ touchdown/rollout errors against a declared budget; fourth order only on smooth intervals | H11 |
| H8 | Minimal bounded state contract for continuous/sampled/discrete values, stage time, tick-boundary transitions, reset, rollback and checkpoint/replay | See ROADMAP H8; precedes E3b1 anchors and G2a coupled shaft work | — |
| G2a | After H8, migrate optional shaft speed into coupled RK4 loads and rotor momentum | Full-session h/h₂/h₄ convergence, actual 240 Hz error, trace records rpm; aircraft without shaft data unchanged | H8 |
| H10 (conditional) | Extract a load-contributor interface only for a demonstrated consumer/coupling problem | Name the duplication or coupling removed; trajectories unchanged and overhead measured | Concrete use case |
| Gate P | Consider GDExtension only after H4/H5 and target-machine measurements show the 500 µs/tick budget or documented near-term reserve cannot be met | All active aircraft and required regimes measured on owner’s slowest supported machine; preserve GDScript oracle | H4–H5 |
| H9 | Extend tolerance-golden policy with per-component scales and platform/build stamps | Mutation beyond accepted tolerance fails; CI reference platform and non-gating platform results are explicit | H8 |
| M5 wind | Use H8 stage time for time-varying wind and explicit sample boundaries for seeded stochastic filters | Same seed gives identical trace; filter variance matches theory within a declared band | H8 |
| Gate P follow-up (conditional) | If Gate P shows a target-machine shortfall, spike only the measured hot path in a pinned GDExtension while keeping GDScript as oracle | Numerical agreement, trajectory tolerance, per-OS smoke and measured improvement | Gate P decision |

## Decisions to take now

1. **Settle minimal state semantics before E3b anchors and further coupled G2 shaft work** (H8): distinguish continuous RK4 state, sampled per-tick inputs and discrete modes; include stage time, trace/reset behavior and fault rollback. Do not build a general registry without a consumer.
2. **Golden policy:** tolerance-based, recorded and gating on one CI reference platform; bit-exact only as a same-binary diagnostic. Survives a C++ port and libm changes.
3. **Keep RK4 at 240 Hz** for the current airborne kernel; H11 derives supported contact bounds from coupled modes and refinement rather than adopting a universal scalar cutoff.
4. **Choose contact onset through E1b evidence.** Hunt–Crossley is one candidate; do not assume contact switching preserves fourth-order convergence.
5. **math3d is the only door to transcendental functions** (guarded), so a deterministic library (CORE-MATH) can be swapped in for multiplayer/replay sharing.
6. **Performance order:** H1–H3 are complete; H4/H5 optimize measured hot paths. Gate P uses 500 µs/tick or a documented near-term reserve on the owner’s slowest machine; 250 µs is not an automatic migration trigger.
7. **Physics stays on the main thread**; threads only for multiple aircraft or asset preparation.
8. Revisit `physics_jitter_fix = 0` only after a frame-pacing measurement with custom interpolation (VQ-01b); do not change it based on the historical recommendation alone.

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
