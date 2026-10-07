# H8a — RK stage time and state inventory

2026-10-06 · **Status: H8a complete; H8 remains open.** Main-line substep of [H8](../../../../ROADMAP.md). This is numerical verification, not flight validation.

## Bounded change

The simulation previously supplied the tick-start time to every load evaluation. `rk4_step_at(state, t, dt, f, k1_given)` now evaluates `f(state, stage_time)` at `t`, `t + dt/2`, `t + dt/2`, `t + dt`. Its cached first derivative must belong to the same starting state, time and frozen inputs. The existing autonomous `rk4_step` API remains available; both use the same final weighted sum and quaternion normalization.

`Simulation.step()` supplies stage time to its load callback and retains four load evaluations per successful tick. Its once-per-tick auxiliaries and rotor momentum remain frozen. The trace still stores the starting load evaluation; CSV v3 needs no layout change. Current aircraft loads ignore time, so their numerical trajectories must remain unchanged. This does not fix the P-51's first-order split shaft coupling; that remains G2a.

## State inventory for the next H8 slice

| Class | Current owner / values | Checkpoint or replay obligation |
| --- | --- | --- |
| Continuous | `Simulation.state`: NED position (m), body velocity (m/s), body-to-NED quaternion (unitless), body rates (rad/s) | Restore all 13 float64 values at a committed tick boundary |
| Sampled / split numerical state | `Simulation.aux`: shaft or turbine RPM, three servo positions (normalized command units) | Restore all four; advance once per tick with explicit hold over stages until a deliberate coupled-model migration |
| Sampled input | `Simulation.inputs`: roll, pitch, yaw, throttle after shaping and trims | Replay these tick samples; bypass live keyboard/radio conditioning |
| Discrete flight mode | `FlightSession.engine_running` | Restore alongside auxiliaries before evaluating loads |
| Clock and continuity | `Simulation.tick`, `previous`, `last_loads` | Restore tick; preserve interpolation, crash sink reporting and recorder continuity |
| Configuration | Aircraft model, mass, inertia, gravity, tick rate, ground surfaces | Reject incompatible checkpoint restoration; identify actual resolved configuration, not only aircraft name |
| Session lifecycle | Crash countdown, pause/fault state, holds, stop-at-tick | Specify a separate session-resume boundary; a physics replay need not reproduce menu or calibration behavior |
| Upstream input conditioning | Keyboard command accumulator; radio armed state, axes and throttle accumulator; raw input | Required for live-session resumption, excluded from replay using recorded post-shaping inputs |
| Derived / diagnostic | Inertia inverse, deflection cache, timing overlay | Recompute caches; do not feed wall-clock timings into dynamics |

The current fault snapshot restores body state, previous state, aux, inputs and loads. Tick is not copied, though ordinary failures occur before its increment. Discrete mode, configuration and upstream input conditioning are outside that snapshot. Reset rebuilds commands, engine mode, inputs and auxiliaries; it preserves field selection and stop-at-tick. These semantics need explicit tests before H8 can close.

Existing goldens replay from a reconstructed trimmed start with per-tick inputs and body checkpoints. They do not restore arbitrary mid-flight auxiliary or discrete state. CSV v3 has rounded numeric rows and descriptive ground metadata; it is not an exact checkpoint container.

Next H8 work: implement a bounded checkpoint and atomic tick commit/rollback across the named physics state, verify reset/reload and failure injection, and prove replay from a nontrivial auxiliary/discrete checkpoint. Define component tolerances and platform/build stamps under H9. Add wheel-anchor fields only with their E3b1 consumer; do not introduce a generic state registry or aircraft schema v2.

## Verification method

`app/tests/test_rk_stage_time.gd` exercises both the kernel and real Simulation. The independent exact solution is the unit-mass coupled system `x′ = v`, `v′ = x + t`, `x(0) = v(0) = 0`: `x(t) = sinh(t) − t`, `v(t) = cosh(t) − 1`. Differentiation verifies both equations and initial conditions. Refinement at 4/8/16 Hz must approach fourth order; the 240 Hz absolute error must stay below 1e-10 in the maximum position/velocity component. This tolerance is a numerical regression threshold for the analytic fixture, not an aircraft fidelity tolerance.

Additional checks cover cached/uncached stage times, a nonzero tick-start time, once-per-tick aux updates, trace load timing, autonomous arithmetic equivalence, and injected nonfinite loads at each later stage. Failure must restore the existing state snapshot, keep the tick unchanged, pause and emit no completed-step sample.

Reproduce with:

```sh
$(app/get-godot.sh) --headless --path app --script res://tests/test_rk_stage_time.gd
app/test.sh
```

## Results

[Machine-readable evidence](verification.json), [22-check run](targeted.log), and [isolated frozen-time mutation](frozen-time-mutation.log):

- Coupled analytic errors at 4/8/16 Hz: `4.3324e-5`, `2.9074e-6`, `1.8870e-7`; refinement ratios `14.90`, `15.41`. At 240 Hz: `3.8654e-12`.
- Reintroducing frozen stage time fails the timing, order and production-step accuracy checks. Its refinement ratios are `1.98`, `1.99`, with 240 Hz error `2.4476e-3`.
- Three-second numeric CSV output (721 samples each) is byte-identical before/after for Stik, Extra, P-51 and Avanti. This compares rounded trace rows on one machine, not a portable exact-replay guarantee. No goldens were re-recorded.
- Full `app/test.sh` passes: 62 GDScript test programs, aircraft contracts, 11 trace-process tests, real-app trimmed flights and 30/60/144 fps replay. The frame-rate state hash is unchanged from the pre-change baseline.
- Static lint and engine resource validation report zero errors and no new diagnostics. Their existing warning totals remain 11 and 134 respectively. Scene smoke/fuzz passes all three scenes with zero errors/findings; it reports 174 warnings across scene loads. Node configuration and physics-layer checks report no findings. These checks do not certify a warning-free repository.

Exploratory cost in µs/tick, best of three 2,400-tick runs with the existing `bench_physics.gd`:

| Aircraft | Trim before → after | Stall-start before → after |
| --- | --- | --- |
| Stik | 364.9 → 363.8 | 427.0 → 394.8 |
| Extra | 383.3 → 399.3 | 378.4 → 370.0 |
| P-51 | 1138.2 → 1103.3 | 1120.3 → 1088.5 |
| Avanti | 434.8 → 405.5 | 415.4 → 401.2 |

Use `$(app/get-godot.sh) --headless --path app --script res://tests/bench_physics.gd -- --aircraft=<catalog-id>` to repeat. The runs shared the development host with tests and a pre-existing renderer. Run order differed; these are noisy cost observations, not evidence of a speedup or a target-hardware budget pass. The JSON records the actual before/after values, platform, engine and source hashes.

## Sources and limits

Repository sources: [integrator](../../../../app/physics/integrator.gd), [simulation](../../../../app/sim/simulation.gd), [flight session](../../../../app/sim/flight_session.gd), [radio](../../../../app/input/rc_input.gd), [goldens](../../../../app/tests/golden_flights.gd), [trace](../../../../app/sim/trace.gd), [numerics investigation](../../roadmap-investigations/01-numerics-architecture-performance.md). Inventory independently reviewed by a read-only Luna Max sub-agent. Original derivation and test fixtures use the repository's MIT license; no external material copied. Owner radio, GPU and flight-validation gates remain open.

Ready-to-paste commit message:

```text
H8a: evaluate loads at RK4 stage times

Proof: app/test.sh; 22 stage-time checks; frozen-time mutation rejected;
four unchanged aircraft traces; three scene smoke tests.
```
