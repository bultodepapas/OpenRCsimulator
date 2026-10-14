# FL-01 — Fixed-Wing Flight Logging Research

**Date:** 2026-10-14  
**Status:** Dated design research followed by the FL-02…04 implementation and software checks below. No physical validation is claimed. The [manual](../../../FLIGHT-LOGGING.md) owns current commands and limitations.

## Finding

The fixed-wing runtime already has a tick recorder, a versioned CSV trace, detailed trace metadata, and exact simulation/session checkpoints. Treat these as the foundation. Keep the CSV as an analysis artifact and use a separately versioned input/event stream plus checkpoint snapshots when a flight must be replayed exactly. A CSV trace is not itself an exact replay file: it rounds numeric cells to nine decimal places and omits some internal state that the checkpoint preserves.

Use the free external [PlotJuggler](https://github.com/PlotJuggler/PlotJuggler) application for plots and run comparisons. Do not build a second plotting interface into the simulator. Keep any app-owned export small and conventional so it can feed an existing viewer.

## Existing runtime behavior

The main implementation is in [`recorder.gd`](../../../../app/sim/recorder.gd), [`trace.gd`](../../../../app/sim/trace.gd), [`flight_session.gd`](../../../../app/sim/flight_session.gd), and [`simulation.gd`](../../../../app/sim/simulation.gd). The current [stack guide](../../../../STACK.md) also states that fixed-wing input is sampled before each simulation tick and that CSV traces are diagnostics while checkpoints carry replay state.

`Simulation` emits a sample at tick zero after reset and again after each accepted 240 Hz step. `FlightSession` updates `sim.inputs` before the step. For a sample at tick `k > 0`, `state`, `aux`, `tick`, and `t_s` are the accepted post-step boundary, while the recorded command vector drove the just-completed interval from `k-1` to `k`. The force/moment row is the RK4 first-stage load: it uses the previous body state and auxiliary values after the tick-boundary actuator update, before RK integration. Weather traces carry `loads_t_s` to show that earlier load time explicitly. The row therefore combines channels with different sampling times; analysis and replay must use each channel's documented timing rather than treating every cell as a simultaneous observation.

The live input path conditions controller or keyboard input, rate-limits the command state, and assigns the resulting four- or six-value vector to `sim.inputs`. `_pre_step` then advances actuators and propulsion state once before RK4; engine-running state and other discrete modes are owned by the session. For replay, the authoritative command is the exact vector consumed at the simulation boundary. Raw device axes are useful for explaining controller behavior, but they are not a substitute for that command vector.

The trace records body position, velocity, attitude, rates, loads, commands, RPM, actual servo positions, and capability-specific channels such as weather, atmosphere, electric or glow state, and retractable gear. It also records units in column names and versioned metadata. `Recorder` accumulates rows in memory and writes one CSV on stop. `Trace.save()` checks whether `FileAccess.open()` succeeds, writes the complete text, closes the file, and returns; it does not stream rows, periodically flush a live trace, or inspect a post-write error. The CSV formatter uses `%.9f`, so it is appropriate for plotting and diagnostics, not bit-preserving float64 replay.

`Simulation.checkpoint()` snapshots the tick, fixed timestep, body and previous state, auxiliary and continuous state, inputs, discrete modes, loads, and solver configuration. `FlightSession.checkpoint()` wraps this with an SHA-256 owner-configuration identity and applicable environment, terrain, contact, damage, and failure state. Restore rejects incompatible layouts and configurations. The trace header already records engine version, aircraft source-byte and semantic hashes, solver/model laws, start conditions, state and auxiliary layouts, and application build description. For development runs, however, the app build field is currently `development`; it does not identify the exact source commit or dirty state. Add that identity if the project needs historical replay claims.

## Minimal design recommendations

1. **Keep one simulation clock.** Store an integer tick and the exact fixed `dt`; derive simulation time as `tick * dt`. Keep wall-clock UTC as run metadata only. Reject or mark missing, repeated, out-of-order, or non-finite samples. Rendering frames and wall-clock timestamps must not drive replay.

2. **Make the command interval explicit.** Preserve the exact float64 command values used by the solver, their input layout, and the tick interval they affect. Keep raw device values and post-conditioning commands as optional diagnostic channels. Give state, loads, and event channels an explicit timing contract in metadata or column names. In particular, never make a user infer whether tick `k` commands affect the interval ending at `k` or starting at `k`.

3. **Separate diagnostics from replay authority.** Keep the human-readable CSV for state, actuator response, forces/moments, propulsion, and environment trends. Preserve full float64 inputs and checkpoints in a versioned binary or round-trip-safe representation. Do not use the current nine-decimal CSV as the only replay input. The existing `var_to_bytes()` checkpoint path is intended to preserve Variant float64 bits; retain a schema/version and compatibility check around it.

4. **Record accepted discrete events and active modes.** An input tape alone cannot reproduce a flight if the owner changes state outside the stick vector. Record events with a tick, sequence number, kind, and payload for engine start/stop, mixture changes, failure triggers and phases, gear targets, reset/reload, crash/contact outcomes, and weather/random-state changes. Include active mode and random generator state in checkpoints. A reset or configuration change should start a new replay segment or be an explicit event; a gap must never silently look like continuous flight.

5. **Identify both physical sources and software.** Retain the existing checkpoint configuration hash, aircraft input-byte hash and semantic hash. Also pin the exact application commit, dirty state, engine version, trace/checkpoint schema, timestep, solver/integrator law, aircraft/state/input layouts, initial checkpoint, environment/terrain identity, and random seeds. Mark replay as unavailable or non-exact when a required identity is missing. For A/B experiments, hold checkpoint, aircraft/environment configuration, input tape, seeds, tick rate, and event sequence constant; record the two code identities as the intended comparison variable.

6. **Bound I/O risk and expose failures.** Godot's `FileAccess` supports `user://` files, reports open and operation errors, and can flush buffered data before normal close. The current save-at-stop approach can lose the whole in-memory recording if the process terminates unexpectedly. A small batch writer with a chosen flush interval can reduce that loss window; choose the interval using measurements on target platforms and keep file work out of repeated solver-stage callbacks. Report open/write/flush failures and the last committed tick. Do not silently truncate or overwrite an earlier flight.

7. **Keep full-rate channels useful.** Log the inputs and committed physical state once per accepted tick, along with internal states needed to explain changes such as servo positions, propulsion state, and force/moment loads. Add detailed RK-stage probes only as an opt-in diagnostic mode. Summary statistics or low-rate visual channels can be derived later; they must not replace the full-rate command tape used for replay.

## Viewer and A/B workflow

PlotJuggler 4 is open source under MPL-2.0, reads CSV and PX4 ULog, can load multiple datasets, align timelines, overlay signals, transform data, and save layouts. The [official GitHub release](https://github.com/PlotJuggler/PlotJuggler/releases/latest) provides the downloadable application; the [official CSV loader](https://github.com/PlotJuggler/pj-official-plugins/tree/main/data_load_csv) documents delimiter detection and selectable timestamp columns. Keep PlotJuggler external rather than bundling it or duplicating its plotting UI.

The current OpenRC trace writes `#` metadata lines before its CSV header. The PlotJuggler CSV-loader documentation does not confirm how that prelude is handled. Before publishing a manual workflow, verify the actual saved file with the selected release and record the version. If the prelude prevents import, preserve the authoritative trace and produce a plot-ready export or a documented import path that retains access to the metadata.

For comparison, load the baseline and candidate from the same initial checkpoint and exact input/event sequence, set the horizontal axis to simulation seconds or ticks, and overlay the same channels. Compare time histories and derived differences for attitude, rates, airspeed, actuator positions, loads, and propulsion outputs. Align by tick when timestep and segment start are identical. When they are not, use an explicitly documented time mapping and keep discontinuities visible. Save a reusable viewer layout with the investigation evidence; do not present a visual overlay as proof that the underlying models are physically correct.

## PX4 and community precedents

PX4's primary [ULog format specification](https://docs.px4.io/main/en/dev_log/ulog_file_format) is a useful reference for self-describing channel schemas, timestamps, software/parameter metadata, and explicit dropout markers. PX4's [logging guide](https://docs.px4.io/main/en/dev_log/logging) also shows why rates and buffering need to be controlled when storage stalls can cause dropouts. These are design precedents; this simulator does not need to adopt the ULog binary format or claim compatibility with PX4/ArduPilot black-box logs. Versioned CSV plus the existing exact checkpoint path is smaller and directly usable in PlotJuggler.

Two first-hand Reddit discussions suggest useful analysis questions, not engineering evidence. In [a small flight-logger thread](https://www.reddit.com/r/RCPlanes/comments/1qsifnp/ive_been_working_on_a_tiny_flight_logger/), a commenter proposes comparing receiver commands with servo outputs and looking for travel saturation alongside speed and attitude. In [a current-draw thread](https://www.reddit.com/r/RCPlanes/comments/1bf8lfv/help_how_do_i_measure_amp_draw_over_time_of_an_rc/), RC pilots suggest logging voltage/current or consumed capacity and comparing flights at similar speeds and distances. These support keeping requested input separate from actual actuator response and retaining available electrical energy channels; they do not validate this simulator's models.

## Limits

A replay can show that the same recorded commands, event sequence, checkpoint, configuration, and code build reproduce software behavior within a stated platform/version scope. It does not show that the flight model matches a real aircraft. Physical validation still requires suitable measurements, instrument and model provenance, uncertainty bounds, and independent flight or bench evidence. Godot warns that its built-in physics engines are not deterministic in general; OpenRC uses its own fixed-step float64 solver, so replay claims should be established against that implementation and must not be generalized across builds or platforms without evidence.

## Implemented slice and verification (FL-02…04)

Implementation reuses session checkpoints, accepted aircraft snapshots and the
existing fixed-step solver. `.orfl` is a bounded, checksummed stream of native
float64/int64 samples and sparse interventions. F10/F11 and a CLI launcher expose
it; a strict offline reader exports conventional CSV or re-simulates recorded
inputs. A separate explicit candidate route reports changed source identities and
the open-loop assumption. Free PlotJuggler is the external plotting option; no
viewer dependency or alternative simulator was introduced.

Evidence retained from native Windows, official Godot 4.7.2, 2026-10-14:

| Check | Result / evidence |
| --- | --- |
| New flight-log suite | **3,247 checks, 0 failures**, [raw log](checks/flight-log.log), [fleet sizes/timing](fleet-verification.json). Five fixed-wing families plus glow; input changes, turbulent RNG, gear/brakes, cut, mid-flight starts, reset, write failure, event-only capacity limit and corrupt/truncated packets. Every observed physics array matches the unrecorded run. |
| CLI export and exact replay | Six files × 261 rows; all exported/replayed CSV pairs byte-identical and numerical comparisons zero. [CLI summary](cli-smoke.json). |
| Recovery | A truncated footer is refused by strict paths; explicit recovery retains 261 verified prefix rows with `complete=false`. This tests retained blocks, not recovery of an unwritten buffer. |
| Candidate sensitivity | Disposable glow servo full-throw time changed from 0.14 s to 0.18 s. Same-current-solver A/A and A/B use identical command tapes; first difference tick 1. Maximum component rate difference 0.050565 rad/s, attitude difference 0.0019734 rad, position component difference 0.0048458 m. [Comparison](candidate-comparison.json). This is a synthetic sensitivity check, not a realism recommendation. |
| Native production UI | F10 start/stop, F11 marker, live accepted ticks, field/scenery checkpoint preparation, restart and scene close: 0 failures. [Log](checks/native-ui.log), [capture](recording-ui.png). Compatibility renderer, NVIDIA RTX 3090. |
| Python tool suite | **14 tests passed**, including malformed/truncated data, alignment and command mismatch, quaternion sign/small-angle behavior, output paths with spaces, incomplete reports and engine errors despite exit 0. [Log](checks/python.log). |
| Existing focused regressions | Simulation, checkpoint, checkpoint-integrity, replay-integrity, trace, metadata and controls-reference checks passed. [Logs](checks/). The old Avanti metadata assertion expected v2; it now recognizes its existing retractable-gear v8 contract. No production physics or golden flights were retuned. |

The tree had concurrent source edits. The six exact CLI checks ran against the
recorded fingerprint `6e83a86d29226afc68d5c0fb83dee1b4e074125d576f8939e0e02832f1def330`.
The later candidate pair both ran with
`f97ab182fddeedae36bb3cda9b8a3301554cfb6f8255b48ba95132d16a032a12`.
Both candidate reports disclose `solver_changed=true` relative to the earlier
recording. Their A/A-versus-baseline values happened to match, but that result is
not same-source qualification. The reported A/B comparison uses the two runs with
the identical current fingerprint. Original local paths and artifact hashes remain
in the summary as provenance, not portable document links.

At 260 ticks the files were 200–266 kB including the one-time model/checkpoint
context. Observer time was about 7–10 ms in the first run and 10–13 ms in the retained
fleet run. Buffers peaked at 199 rows because the deliberate pause flushed the
partial block. These short runs include synchronous serialization/flush and other
local work; they are not isolated throughput, percentile latency, slow-disk,
long-duration or target-machine acceptance. The code bounds samples to 240 and
events to 240 regardless of elapsed flight length.

Only focused regressions and editor import were run, not the entire cross-platform
CI/export matrix. PlotJuggler native import, exported-package logging qualification,
3D playback and physical/pilot acceptance remain outside this evidence.

## References

Primary documentation and project sources checked on 2026-10-14:

- [Godot FileAccess](https://docs.godotengine.org/en/stable/classes/class_fileaccess.html) and [runtime file saving](https://docs.godotengine.org/en/stable/tutorials/io/runtime_file_loading_and_saving.html): open/write/close, operation errors, user-data files, and periodic flush behavior.
- [Godot physics introduction](https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html): fixed physics callback timing and the general determinism limitation for built-in physics.
- [PlotJuggler project and license](https://github.com/PlotJuggler/PlotJuggler), [CSV loader](https://github.com/PlotJuggler/pj-official-plugins/tree/main/data_load_csv), and [releases](https://github.com/PlotJuggler/PlotJuggler/releases/latest).
- [PX4 ULog format](https://docs.px4.io/main/en/dev_log/ulog_file_format) and [PX4 logging guide](https://docs.px4.io/main/en/dev_log/logging).
- [r/RCPlanes logger discussion](https://www.reddit.com/r/RCPlanes/comments/1qsifnp/ive_been_working_on_a_tiny_flight_logger/) and [r/RCPlanes energy logging discussion](https://www.reddit.com/r/RCPlanes/comments/1bf8lfv/help_how_do_i_measure_amp_draw_over_time_of_an_rc/). Community comments are inspiration only.
