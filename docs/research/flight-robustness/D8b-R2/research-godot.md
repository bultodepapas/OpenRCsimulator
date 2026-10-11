# D8b-R2 — Godot runtime and display investigations

2026-10-11 · **Status: six official-documentation investigations complete; no new runtime or physical-keyboard experiment.**

Step ID: D8b-R2 (G01–G06). This supplements the [Ugly Stik pull-up plan](../../../UGLY-STIK-PULLUP-PLAN.md) and the [D8b-R2 evidence report](README.md). It checks whether Godot’s numeric, scheduling, input, display, replay, or profiling seams could change the interpretation of the high-speed keyboard pull-up. Sources are linked inline; no third-party code, images, or datasets are reproduced.

## G01 — Simulation precision and the render boundary

**Question.** Could Godot’s default single-precision 3D types be causing the simulated roll departure?

Godot documents GDScript `float` as 64-bit, while `Vector3` is normally 32-bit unless the engine is built with `precision=double`; `PackedFloat64Array` stores 64-bit values ([float](https://docs.godotengine.org/en/4.7/classes/class_float.html), [Vector3](https://docs.godotengine.org/en/4.7/classes/class_vector3.html), [PackedFloat64Array](https://docs.godotengine.org/en/4.7/classes/class_packedfloat64array.html)). The large-world guide explains the same split and notes that rendering ultimately uses a precision strategy distinct from script scalar math ([Large world coordinates](https://docs.godotengine.org/en/4.7/tutorials/physics/large_world_coordinates.html)).

**Local fit.** The app’s simulation state and integrator use packed scalar arrays and custom float64 math; `app/test.sh` guards that simulation code against `Vector3`, `Basis`, and related transform types. The pose path in [main.gd](../../../../app/main.gd) interpolates the simulation state, then converts it into render axes and a scene transform. The renderer does not feed that transform back into the flight integrator. The reported peak body-rate and trajectory values are computed from simulation state, so render-side float32 conversion cannot create those recorded values. It can affect a screenshot or a visual impression.

**Plan change.** Keep D8b-R2 acceptance metrics in the packed state: body rates, quaternion, air-relative state, and NED position. If a capture looks inconsistent, compare its rendered pose against the same tick’s state before changing physics or raising precision.

**Limit.** This rules out the render conversion as the source of the recorded physics departure by architecture; it does not prove every simulation expression is free of numerical error. The existing 240/480/960 Hz result is a timestep comparison, not a cross-platform precision study.

## G02 — Fixed-tick input and integration ordering

**Question.** Can a render-frame ordering or scheduler mismatch explain the maneuver?

Godot calls `_physics_process()` at a fixed rate, while `_process()` runs on rendered frames; physics callback order is controlled by `process_physics_priority` ([Node](https://docs.godotengine.org/en/4.7/classes/class_node.html)). The project setting controls both the fixed rate and the maximum physics steps allowed per rendered frame; if the app cannot keep up, Godot may slow simulated time rather than exceed that cap ([ProjectSettings](https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html)). `Engine.get_physics_interpolation_fraction()` is a render-time fraction between ticks, not another integration step ([Engine](https://docs.godotengine.org/en/4.7/classes/class_engine.html), [physics interpolation introduction](https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/physics_interpolation_introduction.html)).

**Local fit.** [project.godot](../../../../app/project.godot) pins 240 Hz and 12 catch-up steps per frame. [flight_session.gd](../../../../app/sim/flight_session.gd) runs first (priority −1): it samples `read_raw`, applies `Commands.step_commands` using `sim.dt()`, and commits the resulting per-tick `sim.inputs`. Its child [simulation.gd](../../../../app/sim/simulation.gd) then advances auxiliary servo/engine state before evaluating loads and the RK4 step. [main.gd](../../../../app/main.gd) renders later from an interpolated state. At 240 Hz the command ramp advances by 1/240 second per tick; the configured four command units/second reaches full travel in 0.25 seconds. The plan’s reported near-identical maxima at 240, 480, and 960 Hz already argue against a timestep-size artifact in this controlled case.

**Plan change.** In D8b-R2b, preserve one explicit tick ID for raw sample, shaped command, servo state, RK stage/load sample, and accepted state. The trace header already documents the important `state_timing` and `loads` convention; make telemetry obey that convention rather than joining rows by wall-clock time. Keep the planned fixed-rate refinement and do not raise production tick rate as a symptom fix.

**Limit.** The engine’s catch-up cap affects real-time responsiveness under a slow renderer. The existing controlled maxima are measured by simulation tick, so they do not establish how promptly the owner’s window or keyboard responded in real time.

## G03 — Physical-key polling, key chords, and input mapping

**Question.** Does a real keyboard introduce a command different from the injected Down-arrow input?

Godot’s `Input.is_physical_key_pressed()` queries the physical key location; the manual warns that keyboard ghosting can make it return false for a pressed key ([Input](https://docs.godotengine.org/en/4.7/classes/class_input.html), [input examples](https://docs.godotengine.org/en/4.7/tutorials/inputs/input_examples.html)). Input accumulation describes OS input *events* being merged and emitted at frame end; that is separate from polling the current held-key state. Godot’s InputMap provides named actions, but it does not remap code that directly checks physical keys ([InputMap](https://docs.godotengine.org/en/4.7/classes/class_inputmap.html)).

**Local fit.** [keyboard.gd](../../../../app/input/keyboard.gd) subtracts physical pressed states to produce raw −1/0/+1 axes: Down means nose-up pitch; arrows command roll; A/D yaw; S/W throttle. [commands.gd](../../../../app/input/commands.gd) rate-limits those raw values at each physics tick. This path polls held state, not press/release edges or action strength. The pull-up report’s “keyboard” case injects raw targets through that shaping route without OS keyboard delivery. A separate [fixed-step helper](../../../../app/tests/run_fixed_step.gd) injects `InputEventKey` events through Godot’s API; it also cannot reproduce a keyboard’s hardware rollover or ghosting.

**Plan change.** Keep the diagnosis’s wording “Down-arrow-equivalent target” for the synthetic run. In D8b-R2b add the actual raw axis booleans/values to each tick row. For a native owner run, record the keyboard model and test Down alone plus the actual simultaneous throttle/steering chord used. The one-key full-elevator reproduction is not evidence that ghosting caused the departure; this check closes a separate uncertainty about real input delivery.

**Limit.** No OS keyboard, particular keyboard matrix, keyboard layout, or ghosting behavior was exercised here. Godot’s documentation establishes a possible hardware limitation, not that it occurred in the reported event.

## G04 — Attitude interpolation near vertical flight

**Question.** Could interpolation or an Euler display convention make the airplane look as if it departed when its simulated path did not?

Godot’s quaternion API requires normalized inputs for `slerp`; `Basis` also supports spherical rotation interpolation ([Quaternion](https://docs.godotengine.org/en/4.7/classes/class_quaternion.html), [Basis](https://docs.godotengine.org/en/4.7/classes/class_basis.html)). Godot’s interpolation and jitter guidance separates fixed-tick state from the pose shown between ticks and notes that interpolation can add a presentation delay ([interpolation quick start](https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/physics_interpolation_quick_start_guide.html), [jitter, stutter, and input lag](https://docs.godotengine.org/en/4.7/tutorials/rendering/jitter_stutter.html)).

**Local fit.** This app uses a custom packed-quaternion interpolation: it flips the endpoint sign for the shortest quaternion path, linearly blends components, normalizes, and takes angular rates from the current tick. `main.gd` uses the engine interpolation fraction and converts that pose to a render `Basis`. At the reported 375.5°/s peak and 240 Hz, the attitude changes about 1.56° per tick; that is a small display interval, not a many-revolutions-per-sample ambiguity. Near vertical, Euler-derived heading/roll can still be an awkward diagnostic, but the plan’s body roll rate and cross-track displacement come from physical state, and the latter uses the initial horizontal heading reference.

**Plan change.** Retain quaternion, `p/q/r`, and NED velocity/position as authoritative maneuver evidence. If a visual disagreement remains, compare the saved tick pose with the interpolated render pose and use the same fixed camera for before/after captures. Do not infer the departure from a near-vertical Euler angle alone.

**Limit.** No new capture or conversion-error measurement was run. The small per-tick rotation is an inference from the plan’s reported peak rate and configured tick rate.

## G05 — Replay determinism, checkpoints, and source identity

**Question.** What does a repeatable trace or checkpoint actually guarantee?

Godot documents seeded `RandomNumberGenerator` instances as reproducible for a saved seed/state, but explicitly marks the underlying algorithm as an implementation detail ([RandomNumberGenerator](https://docs.godotengine.org/en/4.7/classes/class_randomnumbergenerator.html)). That supports same-build replay, not an assumption that a random sequence remains identical across engine revisions.

**Local fit.** The simulation checkpoint stores tick-boundary state, previous state, auxiliary state, inputs, modes, loads, timestep, and mass properties; its code comment says native byte serialization preserves float64 bits. `FlightSession` adds a hash of the aircraft model, ground data, and applicable weather configuration. The flight trace records the Godot version and exact aircraft-input file hash, while the D8b-R2 manifest records the baseline commit, engine identity, and source hashes. The existing fixed-frame regression compares hashes at 30/60/144 rendered fps on the same pinned engine; it is frame-rate independence evidence, not universal cross-OS or cross-engine determinism.

The trace header currently writes `app_build` and `app_version`, not the full `BuildInfo` commit and dirty flag. For long-lived diagnostic evidence, add those two fields plus the research driver/test harness hash to the D8b-R2 manifest or trace metadata. Keep the exact aircraft input hash and engine commit beside them. The current event-trace reproduction, physics checkpoint, and source manifest prove different boundaries and should remain identified separately.

**Limit.** The D8b-R2 controlled cases use calm air, so random turbulence is not a cause in those results. A checkpoint is a physics replay boundary downstream of live key conditioning; restoring it does not reproduce what the OS or keyboard delivered.

## G06 — Headless proof, native-window proof, and profiling

**Question.** Which parts of the flight can be validated headlessly, and which require a real window and keyboard?

Godot’s command-line guide supports `--headless` for automation without spawning a window ([command-line tutorial](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html)). Its `Performance.TIME_PHYSICS_PROCESS` monitor measures the time for a physics frame ([Performance](https://docs.godotengine.org/en/4.7/classes/class_performance.html)). The standard profiler covers script/physics work; Godot warns that the Visual Profiler measures rendering work and excludes script and physics time ([debugger and profiler panel](https://docs.godotengine.org/en/4.7/tutorials/scripting/debug/debugger_panel.html), [C++ profilers](https://docs.godotengine.org/en/4.7/engine_details/development/profiling/index.html)).

**Local fit.** Headless deterministic traces are appropriate for replaying the same raw sample schedule, collecting per-tick aerodynamic causes, checkpoint hashes, and physics cost. The existing fixed-step helper runs the main scene with injected key events across render rates. Neither route exercises a physical keyboard’s switch matrix, native focus/OS delivery, or the owner’s perceived attitude in the actual window. The app already has frame-time reporting and simulation step timing; these can separate an overloaded tick budget from a changed per-tick flight response.

**Plan change.** State acceptance in two lanes: headless replay establishes tick-by-tick physics and command causality; a visible native run establishes physical-key delivery, real-time feel, and display interpretation. If a native run differs, compare its recorded raw samples first, then tick-state hashes, then rendered poses. Profile before changing performance settings, and treat a slow-motion/catch-up condition as timing evidence rather than proof of a different aerodynamic law.

**Limit.** No headless benchmark or native-window run was performed for this report. A profiler can identify missed real-time budgets; it cannot validate an aerodynamic coefficient or prove that the aircraft’s response matches the real Ugly Stik.

## Version scope

The baseline in the owning plan is Godot `4.7.2.stable.official.ed1daf0bf`, installed from the repository’s SHA-512-pinned download. The official links above target the Godot **4.7 manual/API series**, not a patch-specific 4.7.2 source audit. They support API behavior and terminology for this investigation; exact runtime claims remain tied to the pinned binary and local code. No code or physics was changed, and no new experiment is claimed.
