# Session performance evidence tools

VQ-01c CPU attribution and native-frame reduction; VQ-02a read-only import inventory.
The [implementation plan](../../docs/plans/global-performance-visual-quality.md) owns order and gates.
These tools do not change aircraft data, simulation, graphics settings or user preferences.

## Home/Fly loading and lake geometry

`loading_probe.gd` uses the real Home Fly signal and End flight route, private settings
beside its output, and the first `frame_post_draw` after each transition. Use a native
renderer; headless execution is rejected. It preserves normal callbacks and focus
safety, records pause/tick state, and never forces a pose or advances physics manually.

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --path app --audio-driver Dummy `
  --resolution 1280x720 --max-fps 60 `
  --script "$PWD/research/performance/loading_probe.gd" -- `
  --output="$PWD/tmp/loading-new.json" --cycles=3
```

Create the parent directory first; output and its `.settings.cfg` sidecar must not exist.
Optional `--aircraft=<id>` selects a flyable fixed-wing aircraft. Cycles are bounded to
1–50. Keep logs and inspect errors even on exit zero. Apply an external timeout for
unattended runs. A fresh process is not a cold OS/import/shader cache. Engine elapsed
time excludes parent-process launch overhead; synchronous build and first draw are
separate measurements. Three cycles do not establish the DT-12 soak or package gate.

`lake_geometry_probe.gd` compares the current lake renderer against an explicit prior
`lake_terrain.gd` source. Extract that file from the recorded pre-change revision outside
`app/`, preserve its `res://` dependencies, then run:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy `
  --script "$PWD/research/performance/lake_geometry_probe.gd" -- `
  --reference="$PWD/tmp/lake_terrain_reference.gd" --output="$PWD/tmp/lake-parity-new.json"
```

The probe hashes both sources and all returned geometry arrays, water placement/bounds
and triangle metadata. Eight alternating serial comparisons cover cold/warm default,
changed water level, bed, shoreline, bank and ground surface data. Changed lake inputs
deliberately retain their identity label to exercise content-based invalidation. Optional
`--candidate=<path>` checks a draft before integration. Timing covers CPU construction,
not render throughput; reject any mismatch or engine error. Retained results and the
bounded production cache contract live in [DT-11a evidence](../../docs/research/visual-quality-implementation/VQ-01c/loading/README.md).

## Complete callback CPU probe

From the repository root, after importing the app with the pinned Godot build:

```powershell
python research/performance/session_baseline.py `
  --godot .tools/Godot_v4.7.2-stable_win64_console.exe `
  --out tmp/session-baseline-new --case trim
```

On Linux/macOS, pass the matching native Godot executable. Output must be new or empty.
Run alone on an idle host. The default is three alternating observer-on/off pairs for
Stik, P-51 and electric Timber, each with 2,400 warmup and 14,400 measured ticks.
This is **10 + 60 seconds of simulated time**, not the 10 + 60 wall-second native-render
qualification protocol. Neither the uncapped CPU loop nor a headless driver measures
GPU performance, display latency or a pilot circuit.

Omitting `--case` runs `trim`. Other explicitly selected fixtures are:

| Case | Workload and limitation |
| --- | --- |
| `trim` | Default trimmed flight, neutral raw stick demand; no autopilot or circuit |
| `maneuver` | Repeated bounded roll/pitch pulses through the real input-shaping path; synthetic workload, not high-load handling acceptance |
| `runway` | Supported runway start, throttle held at idle; wheel/contact cost, not a takeoff or landing |
| `lake` | Trimmed airborne start at NED `[110, 125, -10]`; an evolving trajectory, not a constant over-lake fixture |

`--aircraft=<catalog-id>` and `--case=<case>` can be repeated or comma-separated.
`--warmup-ticks=24 --sample-ticks=240 --repeats=1` is a smoke test only.
The fixed-wing probe rejects rotorcraft and unsupported runway starts (including the
current P-51 runway route). Failed cases
stay in the report; do not shorten a failing workload merely to claim it passed.

The detached session loads the production field, lake and scenery collision inventory.
It calls `FlightSession._physics_process(dt)` then `Simulation._physics_process(dt)`
exactly once per tick. This preserves the real input shaping, session checks, paused
guard, integrator, post-step collision and accepted-step callbacks without adding a
second physics implementation. No session enters the scene tree, so OS devices,
focus notifications and engine scheduling cannot change the declared input sequence.

`openrc-session-cost v1` records:

- Raw integer microseconds per tick, partitioned into the session/input callback and
  the simulation callback. The former includes session contact/health work, not just
  keyboard input. The simulation callback includes collision and synchronous signals.
- Setup phases for data loading, collision construction, aircraft preparation and
  environment/reset. These exclude rendering and **are not Home/Fly loading times**.
- Exact requested/completed tick counts, one input read per accepted tick, world
  identities, engine/CPU identity and failure reason.
- A SHA-256 fingerprint of numeric body/auxiliary/continuous state, effective inputs,
  loads and modes at the sample start and every accepted sample boundary. This is
  not complete checkpoint/event equality or independent physical validation.

Clock reads bracket only the two callbacks. Array retention, guards and fingerprints
are outside each per-tick interval but inside `measured_wall_usec`. Observer-off uses
the same trajectory, guards and fingerprints with no per-tick clocks/arrays. Paired
total-loop differences estimate incremental instrumentation cost and host variation;
they are not a claim of exact observer overhead or a speedup. Negative differences
remain visible. Do not subtract a noisy overhead estimate from individual ticks.

The runner retains raw reports/logs, command lines, engine hash, Git commit/status and
dirty/untracked code hashes. It rejects nonzero exit, engine errors even with exit zero,
timeouts, incomplete ticks, malformed samples and mismatched pair identities. It uses
nearest-rank percentiles and keeps aircraft/case distributions separate. Stop on faults;
never bypass a pause/crash, weaken numerical guards or re-record goldens to finish a run.

## Native frame evidence

Use the existing app logger, with one foreground flight at a time:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --path app `
  --audio-driver Dummy --resolution 1280x720 --max-fps 60 -- `
  --frametimes=C:/absolute/new/run-1.json --warmup=10 --t=60
```

Retain combined stdout/stderr as `run-1.log`, repeat with new filenames, and record
display refresh, VSync, power plan, driver and source/package identity. Dummy audio
excludes output-device acceptance. A process-cold launch says nothing about GPU cache
temperature. Focus loss must keep its normal pause behavior; never suppress it to
obtain a passing number. `complete=true` in the frame logger means collection completed,
not that the aircraft advanced throughout the sample or the process exited cleanly.

Native reductions use first-to-last sampled frame endpoints for simulation/wall ratio,
excluding the first sampled interval from both sides. A paused/scripted/disabled/faulted
run or an engine-error log cannot qualify active flight. Pacing and active-flight validity
are separate results. No native reduction closes hardware, pilot or physical gates.

## Verification

```powershell
python -m unittest discover -s research/performance -p "test_*.py"
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app `
  --check-only --script ../research/performance/session_probe.gd
```

The probe stays outside `app/` and must be parsed/run explicitly. The Python reducers
belong to `research/test-tools.sh`; they do not require Godot or external dependencies.
Actual probe smoke/failure campaigns complement reducer tests; mock reports alone do
not verify production callback coverage. Dated results belong in
[VQ-01c evidence](../../docs/research/visual-quality-implementation/VQ-01c/README.md).

Run the real guard verification with a fresh output directory:

```powershell
python research/performance/verify_session_probe.py `
  --godot .tools/Godot_v4.7.2-stable_win64_console.exe --out tmp/probe-guards-new
python research/performance/native_summary.py `
  --input tmp/native-runs --out tmp/native-summary-new.json
python research/performance/texture_inventory.py `
  --app app --out tmp/texture-inventory-new.json
```

Guard verification mutates disposable script copies outside `app/`: paused simulation,
missing input sampling, an exact stop boundary and an observer that changes controls.
Expected rejection is a passing guard check, never a successful performance sample.
The import inventory reads PNG/JPEG headers and text metadata, records GLB JSON image
counts and leaves embedded pixel payloads uninspected. It cannot resolve runtime-built
material bindings or determine resident VRAM. Multiple shader assignments in one
resource file produce unknown shader context rather than a guessed binding. No review
candidate means these checks found none; it does not establish that all assets are correct.
