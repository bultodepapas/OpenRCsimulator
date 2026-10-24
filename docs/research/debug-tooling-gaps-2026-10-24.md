# Debug tooling gaps — 2026-10-24

Scope: what an AI developer still lacks for finding stutter, resource growth and bugs in the running app, after the
PT1h-R1…R7 tools. This is dated research. The tool guides own current usage: [checked runner and lifecycle
tools](../../tools/godot/README.md), [debug bridge](../../tools/debug/README.md), [performance
tools](../../research/performance/README.md), [flight logging](../FLIGHT-LOGGING.md) and the [flight-test
battery](../../research/flight-test/README.md). The earlier [20-source investigation](debugging-tools-2026-10-19.md)
covered log reliability, JUnit and evidence integrity; it is not repeated here.

## What exists

| Question | Tool today | Limit for an agent |
| --- | --- | --- |
| Did Godot print an error a test ignored? | `run_checked.py`, `summarize.py` (JUnit) | Batch only; one command per run. |
| What does the running app do now? | Debug bridge: state, logs, events, UI, input, step, sample, perf | `perf` is one instant; no frame history, no per-class objects, no script timings. |
| Where do frames go in a capture? | `--frametimes --frame-diagnostics` + `frame_diagnose.py`; `perfetto_export.py` | Scripted or direct-flight captures only; no pipeline-compilation counters; cause of a hitch is context, not attribution. |
| How long do Home → Fly and back take? | `research/performance/loading_probe.gd` | Native renderer only; totals, not phases. |
| Do repeated routes leak? | `lifecycle_check.py` (Home ↔ flight, Workshop) | Fixed routes; node/orphan totals, not which class grows. |
| Process RAM, I/O, disk? | `run_checked.py --resources`, `storage_audit.py` | Outside the engine; cannot attribute. |
| Did a physics change alter flight? | Flight log record/replay/compare; flight-test battery | Exact and strong; not a live breakpoint. |
| Did a picture change? | `app/capture.sh`, area checkers | Fixed cases. |
| Is the UI reachable and error-free? | Bridge `crawl` | Opens/closes screens; does not exercise controls inside them. |

Not present at all: a script (GDScript) profiler usable without the editor, a static analyser or warning policy
(`project.godot` sets no `debug/gdscript/warnings/*`; no gdlint), randomized UI/input testing, simulation
breakpoints, log de-duplication, and native crash backtraces.

## Evidence gathered for this review

Pinned engine 4.7.2, probe outside `app/` (`ClassDB` queries, `--help`):

- `Performance` has `PIPELINE_COMPILATIONS_{CANVAS,MESH,SURFACE,DRAW,SPECIALIZATION}`, `TIME_NAVIGATION_PROCESS`,
  `PHYSICS_3D_*`, `OBJECT_ORPHAN_NODE_COUNT`, `MEMORY_STATIC_MAX` and `Performance.add_custom_monitor`.
  `app/render/frame_diagnostics.gd` reads render times, memory, resources and orphans, but no pipeline counters.
- `EngineProfiler` (virtuals `_toggle`, `_add_frame`, `_tick`), `EngineDebugger.register_profiler` /
  `profiler_enable`, `Node.get_orphan_node_ids`, `OS.get_static_memory_peak_usage`, `OS.get_memory_info` and
  `RenderingServer.get_rendering_info` exist. `EngineDebugger.is_active()` is false without a remote debugger, so the
  built-in script profiler only reports to a `--remote-debug` peer.
- The bridge's `eval` could not reach engine singletons (`Performance`, `OS`, `RenderingServer`): Godot's
  `Expression` only sees its inputs and base object. Fixed in this review by passing every singleton as an input;
  orphan IDs are reachable through `ClassDB.class_call_static("Node", "get_orphan_node_ids")`. After a flight build
  on the VM: 0 orphan nodes, static memory peak 307 MB.
- Runtime flags: `--profiling`, `--remote-debug <uri>`, `--gpu-profile`, `--gpu-validation`, `--frame-delay <ms>`,
  `--fixed-fps`, `--time-scale`, `--print-fps`, `--debug-stringnames`, `--write-movie`. `--benchmark` and
  `--benchmark-file` are editor-only.

Outside-in frame timing through the bridge's network thread (poll `ping` every 3 ms; the frame counter's progress
over wall time gives each frame's duration, with no code in the game loop). Headless, Linux dev VM, Stik:

| Transition | Longest frame | Notes |
| --- | --- | --- |
| Home → Fly (airborne) | about 6.7 s (one frame) | The whole flight is built inside one frame: the app is frozen with no progress feedback. Home also produces no frames while idle (low-processor mode), so the first frame number spans the idle time. |
| Flight → Home | 1.09 s (one frame) | Same pattern. |
| Steady flight | median 8.6 ms, max 19.9 ms | Headless; no rendering cost. |

Loading time itself is a known, measured topic ([loading probe](../../research/performance/README.md#homefly-loading-and-lake-geometry));
the tooling gap is that nothing attributes a long frame to its phases or causes while an agent watches.

## Gaps and proposals

Ranked by value for stutter, leak and bug hunting against effort. S: about a day; M: a few days; L: a week or a
spike first. Each proposal names what it reuses, so nothing free is rebuilt.

| # | Proposal | Finds | Effort | Builds on |
| --- | --- | --- | --- | --- |
| 1 | **Hitch recorder** in the bridge: per-frame ring (wall time, physics ticks run, pipeline compilations, process/physics time, object/orphan/static-memory deltas); `frames` command with p50/p95/p99/max and 1 % lows; a `hitch` log event with the deltas when a frame exceeds a threshold. | Stutter, and whether it coincides with shader/pipeline compilation, physics catch-up (several ticks in one frame), allocation bursts or scene loading | S | `Performance` monitors, bridge events, `frame_diagnose.py` vocabulary |
| 2 | **Simulation watchpoints**: `break expr=… [every_tick]` evaluated before each tick; when true, pause at that exact tick, log an event, keep the state for `state`/`sample`. | Physics bugs at the moment they happen (NaN, ground penetration, attitude flips, fault precursors) | S | Bridge `_physics_process` at priority -10, `Simulation.set_paused` |
| 3 | **Error triage**: `logs summary` grouping by message signature (numbers stripped) with counts, first/last frame and script location; `run --fail-on-error` stopping a repro script at the first new error. | Error spam, the first error in a cascade, silent regressions in scripts | S | Debug log ring, `run` |
| 4 | **Leak hunter**: `objects` (live nodes by class and script, orphan nodes with class/name/script, resource count), `objects baseline` / `objects diff`; client `soak run repro.txt --cycles N` sampling objects, memory and RSS per cycle and reporting monotonic growth. | Which class leaks, for any scenario, not only Home ↔ flight | M | `Node.get_orphan_node_ids`, `lifecycle_check.py` growth rules, `resource_samples.py` |
| 5 | **UI monkey**: seeded random walk over visible controls and keys (press, select, set_value, Esc), checking after each step that the app answers and logged no new error; on failure write the seed and the action trail as a replayable `run` script. | Crashes and error paths no test covers; stuck or unreachable screens | M | Bridge `ui`, `press`, `select`, `crawl`, `run` |
| 6 | **Script profiler without the editor**: a small local debug server for `--remote-debug tcp://127.0.0.1:<port> --profiling` that decodes the engine's profiler frames and prints top functions by self/total time for a window. Spike first: confirm the engine sends script frames without an editor handshake. | Which GDScript functions cost the frame (the attribution `perf` cannot give) | L | Godot's own profiler data; protocol decoders in the MIT [godot-vscode-plugin](https://github.com/godotengine/godot-vscode-plugin) as reference |
| 7 | **Static analysis baseline**: pinned gdtoolkit (gdlint) and/or a probe that loads every script with selected GDScript warnings enabled; a committed baseline so only new findings fail. | Unused variables, shadowing, unsafe calls, unreachable code before they become bugs | M | gdtoolkit (free), Godot warning settings |
| 8 | **Native crash backtraces**: `debugctl launch --gdb` (batch gdb) or the engine's crash handler output collected into the incident bundle, with the pinned build's symbols if published. | Engine/driver crashes that leave only "Segmentation fault" | S–M | `incident_bundle.py`, gdb |
| 9 | **Loading phase markers**: time World/flight build phases inside the one long frame, reported by the hitch event. | Which part of the 6.7 s start dominates | S | Existing loading probe and build functions |

Not proposed: a new in-game overlay (free [Godot Debug Menu](https://github.com/godot-extended-libraries/godot-debug-menu)
exists and the HUD already has developer overlays), a plotting package (Perfetto and CSV tools exist), or GPU
capture on the VM (llvmpipe/Compatibility; RenderDoc and `--gpu-validation` belong to native Forward+ sessions).

## Implemented (PT1h-R8, same day)

| # | Delivered as | Real-app evidence (Linux VM, headless unless noted) |
| --- | --- | --- |
| 1 | Bridge `frames`, `hitch` log events with counter deltas and causes | Home → Fly: one 3,559 ms frame, "scene/resource construction" (+1,482 objects, +499 nodes, +140 resources, +64 MiB) and physics catch-up (12 ticks); flight → Home 1,183 ms. Steady flight p50 6.9 ms. |
| 2 | Bridge `break` (edge-triggered, before each tick, pause/once/wait) | `break expr="sim.time() > 3.0"` paused the Stik at tick 735 (3.0625 s), exactly. |
| 3 | `logs --summary` (bridge `summary=true`), `run --fail-on-error` | Monkey and soak runs below: 0 grouped errors. |
| 4 | Bridge `objects` (class/script census, orphans, baseline/diff); client `soak` | Fly/Home soak, 4 measured cycles: nodes 800, orphans 0, resources 901 in every cycle; 0 growing counters. |
| 5 | Client `monkey` (seeded, replayable trail, hitch attribution) | 250 steps with keys, seed 11: no errors; slow actions were F5 (aircraft data reload, 58–86 ms) and R (restart, about 55 ms). Two client bugs found by it (escaped labels, unquoted key names) were fixed. |
| 6 | `launch --script-profile` + bridge `profile` | The engine's local debugger (`-d --profiling --ignore-error-breaks`) prints per-function GDScript timings; no protocol server was needed. Flight: `glow_voice._exhaust_wave` (989 calls per frame) and `skyline._edge` (1,800 calls) lead self time. |
| 7 | `gdscript_warnings.py`: the engine's own diagnostics through the headless editor's language server, with a line-independent baseline | gdlint 4.5.0 evaluated and rejected (see the [guide](../../tools/debug/README.md#hunting-stutter-leaks-and-bugs-pt1h-r8)). Full pass: 1,239 scripts, 0 errors, 1,160 warnings baselined; reviewed bug-shaped codes were false positives. The debug bridge and its test were brought to 0 warnings. |
| 8 | `stop`/`status` exit report: crash reason, GDScript backtrace, objects leaked at exit; `launch --verbose` | Verified on `OS.crash` and deliberate leak fixtures (formats in the client test). |
| 9 | Not implemented separately | The hitch event's log lines and counter deltas already locate the long frame; phase timing inside it still needs code in the build functions. |

Also fixed during the review: `eval` could not reach engine singletons; `launch` could talk to another app's bridge
when the port was still being released.

## Bug hunt with the new tools (same day)

The findings, and what was done about each:

| Finding | Tool | Action |
| --- | --- | --- |
| A keyboard Accept on the Workshop's "Discard changes" closed the Workshop while the dialog was still dispatching the event: `Condition "!is_inside_tree()"` in `_push_unhandled_input_internal`, and 4 objects leaked at exit. A mouse-style press was clean. | `monkey --seed 5`, replayed with `run --fail-on-error`, then minimized | Fixed in `app/ui/workshop.gd`: Save and Discard mark the event as handled in the dialog before closing. A copy of the old file (`launch --app`) reproduces the error; the fixed tree does not. The Workshop UI, quit, recovery and pause tests pass. Regression scenario: `tools/debug/scenarios/workshop_discard_keyboard.txt`. |
| Quitting during startup sometimes leaks `AudioStreamMP3` and `AudioStreamPlaybackMP3` (the lake ambience in `render/lake/water_effects.gd`); 1 of 4 immediate quits. | `stop` exit report, `launch --verbose` | Reported to the lake/audio owners; an exit-time leak only. |
| Home → Fly takes 3.25–3.7 s in one frame. The largest gaps follow the smoke `process.gdshader` load (712 ms), `main.tscn` (524 ms), `profile_process.gdshader` (407 ms), the aircraft data check (324 ms), tree setup (311 ms) and the `main.gd` load (289 ms). | `frames`, `timeline` with `--verbose` | Input for a loading screen or a staged build (UI/VQ owners). The 1 s script-profile samples miss this frame; `timeline` does not. |
| Restart (R) costs 120–145 ms and the aircraft data reload (F5) 58–86 ms in one frame. | `monkey --keys` hitch attribution | Expected heavy actions; recorded as a baseline. |
| A `scenery.gd` "Nonexistent function 'handles'" error appeared once. | `run --fail-on-error` | Transient: another session was editing `population.gd`. It did not reproduce on the next tree. |
| Two agents launching within 2 s shared port 47870 and `current.json`. | Concurrent `launch` | Fixed in the client: per-port session files claimed atomically, tokens resolved by port, `stop` refuses ambiguous targets. |

`smoke` (12 steps: crawl ×2, 5 scenarios, monkey, soak) passes on the fixed tree in about 3.5 minutes.

## Recommended order

1, 2 and 3 first: each is small, uses only verified 4.7.2 APIs, adds microseconds per frame, and turns the bridge
into a stutter and bug detector during any agent session. Then 4 and 5, which reuse them (hitch and error events
become soak and monkey verdicts). 6 needs a protocol spike before it is planned. 7 and 8 are independent and can go
to CI.

Uncertainties: the outside-in timing has 3–5 ms resolution and includes the poller's own scheduling; it measures
headless frames, not rendered ones. On the VM's Compatibility renderer all five pipeline counters stayed 0 through
Home and a full flight build (rendered under Xvfb, 1280×720); they matter for Forward+ (High graphics) on real GPUs,
which this review did not run.
