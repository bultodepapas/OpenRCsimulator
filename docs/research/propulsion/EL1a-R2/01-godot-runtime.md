# EL1a-R2 — Godot runtime, precision, and profiling

2026-10-10 · **Status: source and code review complete; recommendations for EL plan integration.** Step prefix: EL.

## 01 — Who owns the 240 Hz clock, and what happens during a hitch?

**Question.** Should electric propulsion add an accumulator, or use Godot's fixed callback, and how do interpolation, pause, catch-up, and input interact?

**Verified finding.** Godot 4.7's [`Node` class](https://docs.godotengine.org/en/4.7/classes/class_node.html) (“Processing,” `process_physics_priority`, `_physics_process`) defines fixed-rate physics callbacks; lower priorities run first. Its [`Engine` class](https://docs.godotengine.org/en/4.7/classes/class_engine.html) (“max_physics_steps_per_frame,” “physics_ticks_per_second,” `get_physics_interpolation_fraction`) caps callbacks per rendered frame. Below the cap's real-time threshold, the simulation falls behind instead of entering unbounded catch-up. This project sets 240 ticks/s and 12 steps/frame: below 20 rendered frames/s it intentionally slows. The API also exposes a fraction for manual interpolation.

**Code seam and plan action.** `Simulation._physics_process()` in `app/sim/simulation.gd` owns stepping; reset derives `dt` from the engine rate and refuses a later rate change. `FlightSession._physics_process()` in `app/sim/flight_session.gd` runs first (priority -1) and samples input before the simulation (priority 0). `main.gd::_current_pose()` uses `Simulation.interpolated()` with the engine fraction; packed-state interpolation is manual, before render conversion. Holds skip sampling, pause skips steps, and resume is explicit. Keep one clock for EL: sample ESC decisions at tick boundaries and integrate motor/shaft state in existing stages. Do not advance physics from `_process` or add an accumulator. `main.gd` also disables accumulated input; radio motion events update its cache before per-tick polling.

**Rejecting test and limit.** Extend `app/tests/run_fixed_step.gd`'s 30/60/144 FPS checkpoint hashes to a synthetic electric setup; assert a paused session's tick and RPM stay fixed. An induced hitch should produce at most 12 callbacks/frame and no fast-forward. This rejects frame-owned stepping or pause leaks, but does not measure real radio latency; below 20 FPS the cap permits slow motion.

## 02 — Which values stay double precision at Godot boundaries?

**Question.** Does type annotation preserve solver precision at Godot vector boundaries, and what precision does the pinned executable use?

**Verified finding.** Godot 4.7's [`float` class](https://docs.godotengine.org/en/4.7/classes/class_float.html) (“Description”) defines GDScript `float` as 64-bit with 14 reliable decimal digits. [`PackedFloat64Array`](https://docs.godotengine.org/en/4.7/classes/class_packedfloat64array.html) (“Description”) stores doubles and is passed by reference; use `duplicate()` for independent mutation. [`Vector3`](https://docs.godotengine.org/en/4.7/classes/class_vector3.html) (“Description”) defaults to 32-bit components unless the engine is rebuilt with `precision=double`; the [large-world guide](https://docs.godotengine.org/en/4.7/tutorials/physics/large_world_coordinates.html) (“Enabling large world coordinates”) describes that rebuild and its `.double` suffix. `app/get-godot.sh` pins `4.7.2-stable`; the installed binary reports `4.7.2.stable.official.ed1daf0bf` and is the standard unsuffixed official x86_64 build.

**Code seam and plan action.** `app/physics/math3d.gd::v3()` and `Simulation.state`, `inputs`, `aux`, and `continuous` in `app/sim/simulation.gd` use `PackedFloat64Array`. `app/test.sh` rejects built-in vector, basis, quaternion, and transform types in `sim/` and `physics/`. `main.gd::_pose_of()` converts a detached state to render `Vector3`/`Basis`. Keep motor math, shaft state, telemetry, and checkpoints in scalar doubles and packed arrays; never round-trip render transforms into flight state, and duplicate arrays before mutation.

**Rejecting test and limit.** Add an EL fixture with a sub-millimeter increment at 10 km; after stepping and checkpointing, packed state and trace must retain it while rendering gets only a converted copy. The float64 guard rejects a vector entering physics. Double precision does not establish aerodynamic calibration or cross-platform bit identity; rendering remains single precision.

## 03 — When does profiling justify native code for electric flight?

**Question.** Which measurements can show the fixed-step budget is exceeded, and what evidence should trigger GDExtension work?

**Verified finding.** Godot 4.7's [CPU optimization guide](https://docs.godotengine.org/en/4.7/tutorials/performance/cpu_optimization.html) (“Profiler,” “Manually timing functions,” “Caches”) recommends profiling hot functions, repeating timings, and accounting for cache effects; waits on engine servers may be omitted. Here, `bench_physics.gd` reports the best of three 2,400-tick runs; `Simulation.step_usec` is an exponential moving average. `main.gd::_log_frame_time()` warms up for one second and reports frame p50/p95/p99, not per-tick quantiles. `app/test.sh` checks only the headless logger plumbing. Fleet tool `bench_regimes.gd` records 16 × 120-tick batches, median/p95, and fingerprints, but no explicit whole-tick warm-up. Gate P is based on the 500 µs/tick target-machine budget.

**Code seam and plan action.** Measure electric-enabled `Simulation.step()` through `FlightSession`, including motor, propeller, shaft coupling, and callbacks. Use Godot's profiler for attribution, then warmed whole-tick batches on the named slowest target. Report median/p95 batch averages with exact state/telemetry fingerprints. Keep the existing [Gate P](../../simulation-state/Gate-P/README.md) and [prepared-model](../../propwash/E0b6p/prepared-model/README.md) experiments as bounded research; electric timings neither replace them nor prove a new native path. Consider native work only if repeated whole-fleet measurements still miss budget after measured GDScript fixes.

**Rejecting test and limit.** Reject a speedup claim if paired fingerprints change unexpectedly, gain is within noise, or evidence uses only components, headless smoke, or best-of timings. Reject a GDExtension trigger without whole-tick target distributions for all aircraft and powered electric regimes, numerical parity, and platform costs. Current benches lack an integrated electric aircraft; existing native evidence covers another workload and does not close Gate P.
