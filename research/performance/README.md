# Session performance evidence tools

VQ-01c CPU attribution and native-frame reduction; VQ-02a read-only import inventory.
The [implementation plan](../../docs/plans/global-performance-visual-quality.md) owns order and gates.
These tools do not change aircraft data, simulation, graphics settings or user preferences.

`field_validation_probe.gd` compares complete field validation and file loading
with explicit source/data snapshots and a no-tree control. Its [DT-11a / L6b report](../../docs/research/visual-quality-implementation/VQ-01c/loading/field-validation/README.md)
retains normalized-data/diagnostic parity, paired CPU batches, immutable-input
guards and regression results. It runs headless and does not measure full startup or FPS.

`ground_noise_probe.gd` compares complete seeded image generation and cache-empty
ground-material creation with an explicit reference source. Its [DT-11a report](../../docs/research/visual-quality-implementation/VQ-01c/loading/ground-image/noise/README.md)
retains exact native image/mip/material checks, paired timings and a separate warm
control. It requires a native renderer and measures CPU construction/submission,
not GPU completion, full loading or FPS.

`grass_validation_probe.gd` compares complete grass validation and direct grass
construction against an explicit reference source. Its [DT-11a / L11a report](../../docs/research/visual-quality-implementation/VQ-01c/loading/grass-validation/README.md)
retains native buffer/mesh/material parity, malformed-input comparisons, paired
timings and existing native test diagnostics. It requires a native renderer and
does not measure full default-world loading or FPS.

`stars_build_probe.gd` compares complete star-field construction with an explicit
reference source. Its [DT-11a / FW-24-R1 report and command](../../docs/research/visual-quality-implementation/VQ-01c/loading/stars/README.md)
cover native placement/buffer/material parity, warm and cache-empty timings, and
separate startup/full-loading limits. It requires a native renderer.

`scenery_empty_probe.gd` compares complete scenery-contact queries against an explicit
reference source, including occupied bins with an empty hull envelope and real-hit
controls. [LU-10-R1 evidence and commands](../../docs/research/landscape-upgrade/LU-10-R1/README.md)
define its paired batches, exact-parity checks and separate full-session limits.

`woodland_build_probe.gd` compares the current woodland builder with an explicit reference
using native-renderer scene snapshots and alternating construction timings. Its
[measurement report and commands](../../docs/research/visual-quality-implementation/L6c/tree-completion/optimization/woodland/README.md)
define the retained baseline, quality tiers, resource-ownership checks and timing limits.

## Home/Fly loading and lake geometry

`loading_probe.gd` uses the real Home Fly signal and End flight route, private settings
beside its output, and the first `frame_post_draw` after each transition. Use a native
renderer; headless execution is rejected. It preserves normal callbacks and focus
safety, records pause/tick state, and never forces a pose or advances physics manually.

```powershell
& .tools/Godot_v4.8-beta1_win64_console.exe --path app --audio-driver Dummy `
  --resolution 1920x1080 --windowed `
  --script "$PWD/research/performance/loading_probe.gd" -- `
  --output="$PWD/tmp/loading-new.json" --cycles=3
```

Create the parent directory first; output and its `.settings.cfg` sidecar must not exist.
Verify the recorded `viewport_size`: fullscreen can use the desktop's resolution despite
`--resolution`, so a 4K desktop does not establish a 1080p sample.
Optional `--aircraft=<id>` selects a flyable fixed-wing aircraft. `--start=airborne|runway`
selects its start (default `airborne`).
`--input=auto|keyboard` keeps automatic device selection by default or explicitly
selects keyboard flight/menu controls through the ordinary controller service in
the private profile. Use the same mode for both roles; a paused first draw does not
establish interactive readiness.
`--dwell-ms=0..30000` waits after each Home draw before pressing Fly. `--prefetch=off|scene|trim|scene_trim`
selects the preparation experiment (default `off`); `--prefetch-delay-ms=0..10000`
sets its stable-selection delay (default 350 ms). Non-off modes require an app that
implements preparation. Compare identical dwell and delay settings across roles.
`--observe-camera` adds bounded per-draw camera/aircraft placement and loading-cover observations,
waits 12 extra frames after handoff, and saves the first and tenth uncovered frames beside the JSON.
Use an ignored `tmp/` output path. Readbacks can stall rendering; these runs diagnose first reveal
and must not be mixed with timing acceptance samples. The option never bypasses focus safety.
Cycles are bounded to 1–50. Keep logs and inspect errors even on exit zero. Apply an external timeout for
unattended runs. A fresh process is not a cold OS/import/shader cache. Engine elapsed
time excludes parent-process launch overhead. `fly_sync_usec` measures only dispatch
of `pressed.emit()`; Home now acknowledges Fly before its deferred handoff.
`fly_ready_usec` includes that handoff and validated flight creation, while
`fly_first_draw_usec` additionally waits for post-draw. `home_to_ready_usec` includes
dwell; `home_dwell` records actual elapsed time and frame intervals. Preparation
snapshots and static engine allocation counts before/after dwell are additive fields;
static allocation is not process RSS or VRAM. The probe allows at most 7,200 process
frames and 60 seconds for the handoff and rejects cancellation, retry-ready rejection,
startup errors and unflyable sessions. An external timeout bounds blocking construction.
A paused first draw is not interactive readiness. Three cycles do not establish the
DT-12 soak or package gate.

`trim_cache_before_fly` / `trim_cache_after_fly` expose worker starts, adoption and cache
ownership. When Main supports overlapping preparation, `startup_preparation` records
acquisition, world construction and post-world setup durations plus worker counts.
`finish_setup_usec` includes any remaining wait, final validation and initial reset;
it is not pure worker time. Timings overlap and must not be added as independent costs.

After the last sample, the probe stops and awaits any Home preparation before freeing
its scene, then observes weak references to the
latest playback of each audio player. It allows up to one second for the mixer to
release them; this teardown is outside all loading timings. The additive `shutdown`
record reports audio elapsed time, tracked/remaining playbacks, preparation drainage and sidecar removal. A timeout
or sidecar removal failure marks the report incomplete and exits nonzero. Failures also
free the owned scene and remove successfully created settings; existing files are never
removed. This distinguishes asynchronous audio retirement from persistent retention;
it is not a general memory/RSS or production quit guarantee.

Run its isolated handoff, success/failure/retention and file-preservation checks with:

```powershell
python research/performance/test_loading_probe.py --godot .tools/Godot_v4.7.2-stable_win64_console.exe
```

[Audio retirement evidence](../../docs/research/visual-quality-implementation/VQ-01c/loading/audio/README.md)
records the reproduction, external Godot finding and packaged lifecycle run.

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
  --godot .tools/Godot_v4.8-beta1_win64_console.exe `
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

`openrc-session-cost v2` records:

- Raw integer microseconds per tick, partitioned into the session/input callback and
  the simulation callback. The former includes session contact/health work, not just
  keyboard input. The simulation callback includes collision and synchronous signals.
- Setup phases for data loading, collision construction, aircraft preparation and
  environment/reset. These exclude rendering and **are not Home/Fly loading times**.
- Exact requested/completed tick counts, one input read per accepted tick, world
  identities, engine/CPU identity and failure reason.
- The requested and installed backend, solver and aircraft hashes, and a SHA-256
  fingerprint of the typed, length-delimited body/previous/auxiliary/continuous
  arrays, effective inputs, loads and modes at the initial boundary and every
  warmup and sample tick. This is not complete checkpoint/event equality or
  independent physical validation. Historical v1 reports remain readable but
  cannot be used for backend comparisons.

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

### Production native/reference and native build comparisons (NK-3)

Install a verified native stage using the [NK-3 build procedure](../native-kernel/README.md#optional-normal-flight-backend).
The current production route supports the stock Ugly Stik on Linux x86_64. Use a fresh
output directory, the pinned executable, and a quiet host:

```sh
python3 research/performance/session_baseline.py --godot "$(app/get-godot.sh)" \
  --out tmp/nk3-before --aircraft jensen-das-ugly-stik-60 --case trim,maneuver,runway \
  --warmup-ticks 600 --sample-ticks 2400 --repeats 3 --compare-backends
```

The runner alternates the reference/native order and collects per-callback stopwatch
samples for both. Each session selects the backend before setup. A native run fails if
the installed backend falls back, changes, or its stage/context counters do not cover
every warmup and sample tick. Each pair requires equal fingerprints, complete ticks,
input counts, solver/aircraft/world and machine identities. Native binary and C++ source
hashes must match the installed receipt and current sources; application code/text data,
probe and engine identities must remain unchanged during the campaign. Fingerprint and
backend/counter checks run outside each stopwatch and can perturb subsequent samples.

For an actual Linux package, add `--release-executable` and set `--godot` to its exported executable.
The runner uses the fixed embedded probe through the ordinary application entry point, checks the executable
and sibling-library hashes before/after each run, and requires a package identity and completion marker.
It never substitutes a different main scene or a diagnostic executable. Keep the source probe identical to the
embedded one. See [package commands and qualification](../native-kernel/README.md#linux-release-packages).

The guard verifier defaults to reference-only and also runs on systems without the
optional library. On Linux, after installing a verified native library, include native
fallback and tick-coverage checks using a new output directory:

```sh
python3 research/performance/verify_session_probe.py --godot "$(app/get-godot.sh)" \
  --out tmp/nk3-probe-guards --native-guards
```

The native checks require the staged library and reuse the imported asset cache; their
absent and stale library cases use disposable project metadata and copies of the native
receipt/library. They never mutate the installed files.

To compare two verified native builds, retain the first campaign and its raw reports,
build and install the candidate, then repeat the command with a new output directory.
Compare the two completed campaign reports:

```sh
python3 research/performance/session_baseline.py --compare-campaigns \
  tmp/nk3-before/session_baseline.json tmp/nk3-after/session_baseline.json --out tmp/nk3-comparison
```

The comparison reopens and hashes raw reports, validates each pair, and rejects changes
to the reference trajectory, workload, application sources, engine, probe, machine or
native ABI/lock. Only native source and binary identities may differ. Campaigns occur
in separate blocks, so drift and other host activity can bias before/after results;
neither this test nor a headless result qualifies 1080p rendering or physical realism.
`--physics-backend=native` instead runs the normal observer-on/off study with native;
the default remains `gdscript_reference`.

### FlightAudio sound-speed accessor microprobe

`sound_speed_probe.gd` instantiates and freezes the production `main.tscn` flight scene for Stik,
Extra and P-51, checks exact equality between the full audio snapshot and the direct
sound-speed accessor at each accepted atmosphere, then times nine alternating batches
of 150 calls per method. Its JSON retains every batch, engine version, and SHA-256
identities for the probe and relevant source files. It records the display server and
scopes timings to these per-call CPU methods on a frozen real scene; it does not measure
full callback or native-frame cost. Nine batches support a median screen, not a stable
tail percentile.

```powershell
$Probe = (Resolve-Path research/performance/sound_speed_probe.gd).Path
$Out = Join-Path $PWD 'tmp/engineering-perf/cpu/sound-speed-new.json'
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy `
  --path app --script $Probe -- "--output=$Out"
```

The output parent must exist and the destination must be new.
[Dated CPU batches, native comparison and verification limits](../../docs/research/visual-quality-implementation/VQ-01c/game-engineering-2026-10-24/README.md).

## Native frame evidence

For neutral keyboard collection with a connected radio, explicitly select the
keyboard through `ControllerService` before attaching the normal session. The
[retained lake bootstrap](../../docs/research/visual-quality-implementation/VQ-07/planar-lake-2026-10-22/README.md#native-keyboard-cost-screen-2026-10-22)
demonstrates this without changing saved preferences or bypassing focus-loss
pause. Such a workload does not establish pilot-flight acceptance. Reject paused
runs and overlapping GPU processes; keep exclusions and minimum-run gates visible.

Frame reports also record `session_at_report`: the session's display
`pause_reason`, active hold names, crash-presence flag and window focus at the end
of collection. A hold may have an empty reason; a focus-triggered simulation pause
may have no session reason. These fields do not establish pause history or prove
which event caused a pause. The reducer retains and type-checks this optional
context; older reports show `null`. Eligibility still uses the existing paused,
fault, input and raw tick/time gates. [Producer checks and limits](../../docs/research/visual-quality-implementation/VQ-07/planar-lake-2026-10-22/README.md#engine-lifetime-attribution-and-session-context-2026-10-22).

### CPU, GPU and memory diagnosis

For OS process RAM, system memory pressure, process I/O and project disk usage,
use the [resource and storage tools](../../tools/godot/README.md#process-ram-io-and-storage-pt1h-r4).
These complement the engine allocation counters below.

Add `--frame-diagnostics` after Godot's `--` to the existing `--frametimes` command
to retain root-viewport render CPU/GPU timings, global render setup CPU time,
Godot-tracked memory/resource/orphan-node counters and observer polling cost.
The mode is off by default and does not modify simulation state. Example from
the repository root, with a new output directory and the Windows console engine:

```powershell
$run = Join-Path $PWD ('tmp/frame-diagnostics-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $run | Out-Null
$godot = (Resolve-Path '.tools/Godot_v4.8-beta1_win64_console.exe').Path
python tools/godot/run_checked.py --out-dir "$run/checks" --timeout 100 -- $godot --path app --audio-driver Dummy --resolution 1280x720 --max-fps 60 -- --scripted --frametimes="$run/run-1.json" --warmup=10 --t=60 --frame-diagnostics --frametimes-max-frames=60000
$captureExit = $LASTEXITCODE
$log = (Get-ChildItem "$run/checks" -Directory | Select-Object -First 1).FullName + '/engine.log'
python research/performance/frame_diagnose.py --report "$run/run-1.json" --log $log --out "$run/diagnosis.json" --budget-ms 16.667 --top 10
if ($captureExit -ne 0 -or $LASTEXITCODE -ne 0) { throw "Capture or diagnosis failed; retained evidence: $run" }
```

`--scripted` is a repeatable rendering workload, not active flight or an exact
physics replay. Omit it to investigate a controlled physical flight. Use the
matching native engine on Linux/macOS. Headless runs retain counters but explicitly
report render timing unavailable. macOS Compatibility timing is conservatively
disabled. Observer timing is disabled when collection ends or the scene exits;
do not run this observer together with another owner of viewport timing.

`--frametimes-max-frames` bounds retained samples: default 60,000, range 1–120,000.
It requires `--frametimes`, as does `--frame-diagnostics`. Warm-up frames do not
consume the limit. Hitting the limit writes an incomplete prefix and exits nonzero;
shorten `--t` or choose a larger limit. Exact completion on the last allowed frame
succeeds. This default v2 mode has a 300-second duration bound. Use a fresh frame
JSON path: the legacy v2 writer still accepts replacement of an existing path.

### Long continuous captures (DT-MAC-02b)

Add the bare `--frametimes-stream` flag to opt into `openrc-frametimes v3` and
`<report>.frames.jsonl`. The report and sidecar must both be new; the v3 writer
checks the report path again at finalization. Use a unique output directory owned
by one writer. The existence check followed by file creation is not an atomic
no-overwrite guarantee against a noncooperating concurrent writer, including for
the sidecar. Warm-up is
0–3,600 seconds; sample duration is greater than zero and at most 3,600 seconds.
The stream defaults to 500,000 sampled frames; `--frametimes-max-frames` can set
1–1,000,000. Its sidecar has a 256 MiB hard cap and holds at most 512 frames per
chunk. The collector retains two bounded float64 timing series for exact reported
percentiles, with at most 64 numeric metrics and 128 characters per metric name;
the report does not embed the full per-frame arrays. Warm-up frames do not consume
the frame limit. Default v2 options and short-report fields are unchanged.

For example, after installing and identifying the matching native Mac editor,
use a new empty output directory and the repository's checked runner:

```sh
run="$PWD/tmp/long-frame-example"
mkdir "$run"
godot="/absolute/path/to/Godot.app/Contents/MacOS/Godot"
python3 tools/godot/run_checked.py --out-dir "$run/checks" --timeout 2100 -- "$godot" --path app --audio-driver Dummy --resolution 1920x1080 --max-fps 60 -- --frametimes="$run/run-1.json" --frametimes-stream --warmup=10 --t=1800 --frame-diagnostics
capture_status=$?
cp "$run"/checks/*/engine.log "$run/run-1.log"
python3 research/performance/frame_diagnose.py --report "$run/run-1.json" --log "$run/run-1.log" --out "$run/diagnosis.json" --max-input-bytes 320MiB --budget-ms 33.3
python3 research/performance/native_summary.py --input "$run" --out "$run/summary.json"
```

Retain `capture_status` and the checked runner's report. The summary defaults to
three individually eligible runs, so one valid run does not pass its campaign
gate. The command is a direct flight route and bypasses normal Home preference
selection; record effective settings and test the actual Home-to-flight product
path separately. Dummy audio does not qualify audio output. A requested 1080p
window does not prove 1080p drawable pixels on a Retina display. Mac launch,
rendering, performance, thermal and packaging remain unverified by these changes.

Chunks carry sequence and frame offsets, monotonic wall intervals/endpoints,
engine deltas and all recorded metrics. Completion writes a trailer; the report
records the sidecar byte count, SHA-256, chunk/frame counts and first/last
metric endpoints. `native_summary.py` and `frame_diagnose.py` validate the sidecar,
continuity, schema, hash and completion before using it. Other report consumers
and trailer workflows are not qualified for v3. A clean early exit, frame cap, byte cap or write
failure is incomplete; an abrupt termination can leave only a prefix without a
trailer or report. Do not treat a recovered prefix as a completed soak. The hash
detects accidental changes, not who produced the files.

Chunk serialization, synchronous write/flush and hashing occur on the app thread.
The report's `stream.write_calls`, `write_total_usec`, `write_max_usec` and
`write_timing_scope` describe that work, not all per-frame observer cost or a
physical storage measurement. `rejected_frames` and `unstored_frames` identify
known loss; a complete report requires zero of each. Compare otherwise matched
observer-on/off runs before drawing performance conclusions. `observer_poll_usec`
only measures diagnostic polling, separately from chunk writes.

`frame_diagnose.py` applies its existing `--max-input-bytes` limit to report,
sidecar and log together. Its default is 64 MiB; larger captures need an explicit
limit, up to 1 GiB. The shared stream reader separately limits retained numeric
arrays to 128 MiB and rejects oversized inputs rather than dropping data. The
native summary reads stream chunks under the same stream caps. Historic v2 reports
remain readable without a sidecar.

The offline diagnosis reuses the native report validator, requires the matching
process log, and reports budget overruns, contiguous bursts, worst-frame indices
and timestamps, accompanying counters, and memory start/end/peak changes. It
preserves errors and warnings with log context. `--budget-ms` is an explicit
investigation threshold, not an automatic performance acceptance gate.

Reducer limits: `--top` defaults to 10 (1–1,000); `--max-input-bytes` defaults to
`64MiB` combined report/sidecar/log input (maximum `1GiB`, plus one overflow-detection byte).
It refuses an existing diagnosis destination. Exit 0 means valid source data,
1 means invalid/missing/incomplete data, engine errors or invalid observer readings,
and 2 means invalid options or output failure. Warnings remain visible without
failing. Budget overruns are observations even with exit 0. The caller must supply
the matching log; hashes identify those files but do not prove their association
or process exit status. Preserve the checked runner's exit status separately.

Interpretation matters:

- Render CPU time excludes scripts and physics; global setup time is separate.
  Root-viewport GPU time excludes other viewports. These channels must not be
  summed with wall-frame or broad process CPU time.
- Render timer queries refer to previously available rendering work; GPU results
  may lag. Same-index counters are context, not proof of a hitch's cause. Zero GPU
  readings mean unavailable-or-zero, never a demonstrated free GPU frame.
- Memory figures are engine-tracked allocations/estimates, not process RSS or
  available VRAM. Growth and orphan counts suggest a repeatable lifecycle probe;
  they do not establish a leak.
- `observer_poll_usec` measures diagnostic polling/merge work only. It excludes
  retention, report writing and driver instrumentation cost. Measure performance
  separately with the observer off before accepting an optimization.

For deep attribution, use Godot's existing [Profiler and Visual Profiler](https://docs.godotengine.org/en/stable/tutorials/scripting/debug/debugger_panel.html),
or its `--gpu-profile` engine flag (before `--`, confirmed in the pinned engine's
`--help`). Keep GPU/API validation in a separate debugging session. The
[RenderingServer timing reference](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-viewport-get-measured-render-time-gpu)
and [Performance monitors](https://docs.godotengine.org/en/stable/classes/class_performance.html)
define measurement scope and platform/build limitations. No new profiler or
plotting dependency is required.

### Capture without the additional observer

Use the existing app logger, with one foreground flight at a time:

```powershell
& .tools/Godot_v4.8-beta1_win64_console.exe --path app `
  --audio-driver Dummy --resolution 1280x720 --max-fps 0 -- `
  --frametimes=C:/absolute/new/run-1.json --warmup=10 --t=60
```

This control uses the shipped uncapped engine setting with normal VSync. Retain
`--max-fps 60` as a separately labelled capped comparison when reproducing earlier
campaigns; never pool the two. The [2026-10-21 release comparison](../../docs/research/visual-quality-implementation/VQ-01c/pacing-2026-10-21/README.md)
shows why the distinction matters on this host. The diagnostic example above
deliberately uses the historical capped condition.

New frame reports record `max_fps`, `vsync_mode`, display server, screen index and
reported refresh rate at collection end. These are settings/observations, not
continuous configuration tracking or physical-display qualification. A headless
VSync enum does not imply presentation; its screen/refresh values are -1.
The reducer rejects mixed caps/modes, mixed known/unknown configuration and
partially specified configuration at campaign level. Historical reports lacking
both fields retain numeric compatibility with `pacing_configuration_complete=false`;
unknown never means uncapped. Keep their checked command lines as separate evidence.

Frame reports and capture sidecars also record `render_settings.lake_reflections`:
normalized environment request, installed `mode` (`absent`, `probe`, `planar`),
`planar_active_at_report` and `capture_size_at_report`. The installed path comes
from the scene; requesting planar in Standard still reports `probe`. Activity
and size are end snapshots, not continuous visibility/cost measurements. A
temporarily inactive planar helper remains installed in `planar` mode.
The reducer rejects malformed descriptors, mixed installed modes and mixed
known/missing modes within a campaign. All-historical missing modes retain
numeric compatibility with `lake_reflection_configuration_complete=false`;
unknown does not mean probe or qualify a reflection configuration. Equal modes
alone do not establish equal workloads. [Reproduction and native checks](../../docs/research/visual-quality-implementation/VQ-07/planar-lake-2026-10-22/README.md#reflection-measurement-identity-2026-10-22)
retain the mixed-mode failure and correction.

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
& .tools/Godot_v4.8-beta1_win64_console.exe --headless --path app `
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
  --godot .tools/Godot_v4.8-beta1_win64_console.exe --out tmp/probe-guards-new
python research/performance/native_summary.py `
  --input tmp/native-runs --out tmp/native-summary-new.json
python research/performance/texture_inventory.py `
  --app app --out tmp/texture-inventory-new.json
```

Guard verification mutates disposable script copies outside `app/`: paused simulation,
missing input sampling, an exact stop boundary and an observer that changes controls.
Expected rejection is a passing guard check, never a successful performance sample.
The import inventory reads PNG/JPEG headers and text metadata, validates GLB chunk and
bufferView boundaries, and inspects embedded PNG/JPEG headers with streamed SHA-256.
Exact glTF core material references describe channel/color semantics; reuse ambiguity
is retained. External/data URIs and unsupported formats remain explicit gaps. Hashing
is capped at 512 MiB per image and per GLB; JPEG header scans are capped at 4 MiB.
It does not decode pixels, resolve runtime-built bindings or determine resident VRAM.
Multiple shader assignments in one
resource file produce unknown shader context rather than a guessed binding. No review
candidate means these checks found none; it does not establish that all assets are correct.

### Runtime texture inventory (VQ-02a)

Run `texture_runtime_probe.gd` with the pinned native renderer against a separate,
imported snapshot. Keep its sibling `texture_runtime_inventory.gd` beside it. Use a
pristine extraction for the static inventory: the editor import normalizes sidecars
and can extract embedded images. Record both identities, as in the
[VQ-02a evidence](../../docs/research/visual-quality-implementation/VQ-02a/README.md).

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --path <snapshot-app> --audio-driver Dummy --script C:/DEVELOPMENT/OpenRCsimulator/research/performance/texture_runtime_probe.gd -- --output=C:/path/to/new-inventory.json --source-commit=<40-character-commit>
& .tools/Godot_v4.7.2-stable_win64_console.exe --path <snapshot-app> --audio-driver Dummy --script C:/DEVELOPMENT/OpenRCsimulator/research/performance/test_texture_runtime_inventory.gd
python -m unittest research.performance.test_texture_inventory -v
```

The probe builds the default fixed-day world and the catalog's fixed-wing visual
families off-tree. It starts no flight or node processing. It follows assigned stored
resources, mesh surface materials, MultiMesh resources, overrides, overlays, next
passes and scalar shader sampler defaults. Resource IDs are case-local; consumer
edges resolve through `resource_links`. Hidden, disabled and overridden assignments
are included: this is not an effective draw list. Resolved scenery options are recorded.

Texture records contain dimensions and, when available, the returned Image format,
compression flag, mip count, byte size and hash. These CPU image bytes are **not VRAM**
and must not be summed as resident memory. Viewport readback is excluded. Shader filter
hints remain in the static inventory; BaseMaterial3D filter/channel enums are recorded.
Home/UI, aircraft night kits, conditional weather, flight-only effects, rotorcraft/ground vehicles,
sampler arrays/global textures and deep containers remain outside this bounded probe.
Persistent campfire and club-lighting assignments are included even when disabled.
The observer reads one complete image at a time without a per-image allocation cap;
review asset sizes before extending the scene scope. The supplied commit is a provenance
label, not a verified checkout identity; retain separate archive/import hashes.

The fixture checks shared identity, MultiMesh and material overrides, shader defaults,
mip byte counts, repeated-scan equality and unchanged assignments. Both probes refuse
existing output files; the runtime probe rejects headless rendering. Capture stdout
**and stderr through process exit**: the current world probe reports two GL texture
teardown warnings even though it writes a repeatable inventory and exits zero.

### Moving visibility reference (VQ-01d / CAM-22)

`visibility_capture.gd` reuses the existing aircraft/field builders, CG conversion
and pilot CameraRig in an isolated native Compatibility SubViewport, 1280×720,
4× MSAA. It samples prescribed render poses at 30 Hz along a 100 m arc; it does not
run flight physics. Shader time is zero, node processing is disabled, and there is
no aircraft shadow, moving propeller, HUD or night kit. Background names select
historical L6c elevations; they do not certify the current background's pixels.

```powershell
python research/performance/run_visibility_capture.py --godot .tools/Godot_v4.7.2-stable_win64.exe --app <imported-snapshot-app> --out tmp/visibility-new --source-commit <archived-40-character-commit> --background trees --pose knife_left --autozoom on --frames 60
python research/performance/visibility_pack.py --input tmp/visibility-new/capture --out tmp/visibility-package-new --frame-count 60
python -m unittest research.performance.test_visibility_pack -v
```

Use the actual Windows engine executable so the runner waits through process exit.
The runner minimizes its window; explicit off-screen draws continue. It retains
complete logs and requires exit zero, no engine error/warning, a completion marker
and a valid capture. A zero-exit partial run is rejected. All destinations must be
new. Keep the archive, import normalization and tool hashes with accepted results;
the source-commit option is a caller label, not automatic Git verification.

Options: six existing poses (`level`, `inverted`, `knife_left`, `knife_right`,
`climb`, `dive`), four requested backgrounds (`sky`, `horizon`, `trees`, `ground`),
fixed-wing family ID, autozoom on/off and 2–600 frames (default 90). Frame count
changes traversal duration across the same arc. Manual zoom stays 1. Every frame
records timestamp, NED target, prescribed Euler angles, camera transform/FOV,
face-on reference span, CG screen location, projected AABB and PNG hash.
These geometric quantities do not measure pixel contrast or visible pixel area.

The validator checks path containment, PNG hash/dimensions, exact frame order/time,
finite and bounded projection data, and actual pixel change. Packaging uses the
existing pinned Pillow **12.3.0** visual environment and preserves original pixels
in APNG, with 33/34 ms durations summing to the exact requested 30 Hz clip length.
It decodes and compares every frame and duration, including repeated adjacent
frames. This verifies the file, not a browser/display's presentation timing.
The packager holds the clip's decoded frames in memory; use bounded case sizes.

[VQ-01d evidence and numbered review clips](../../docs/research/visual-quality-implementation/VQ-01d/README.md)
retain the initial four-clip subset, repeat/minimization parity, guards and a
rejected partial collection. Human orientation, controlled reaction time, other
aircraft/views/weather and the full acceptance matrix remain open.

## Lake validation reuse (LU-25-R1)

`lake_validation_benchmark.py` creates a disposable imported app copy and compares
the original structural guard with bounded successful-definition reuse through
two production sessions. It alternates 120-tick batches, compares complete
checkpoints and hashes every measured numeric state. No benchmark switch is
installed in the production application.

```powershell
python research/performance/lake_validation_benchmark.py --godot .tools/Godot_v4.7.2-stable_win64.exe --work tmp/lake-validation-new
```

Use a new work directory on the repository volume; assets/imports are hard-linked
as read-only inputs. Do not import the disposable copy. Run timing alone on the
host when possible. Defaults are 2,400 warmup and 14,400 sample ticks; `--aircraft`
and `--case` select the workload. The native Windows executable is required so a
timeout owns the engine rather than its console launcher.

[Measured results, retained unfavorable runs and regression limits](../../docs/research/landscape-upgrade/LU-25-R1/README.md)
describe the CPU-only scope. The runner rejects engine errors, incomplete runs,
sample-count discrepancies and unequal trajectories.

## Ground-stage layout queries (H16)

`session_pair_probe.gd` compares two complete flight-session implementations through
production input and simulation callbacks. It alternates 120-tick batches, hashes
all measured numeric states and compares complete checkpoints after every batch.
For the H16 method change, the original-method oracle can be compared with the
current session:

```powershell
$probe = (Resolve-Path research/performance/session_pair_probe.gd).Path
.tools/Godot_v4.7.2-stable_win64.exe --headless --path app --audio-driver Dummy --script $probe -- --reference=res://tests/ground_stage_reference.gd --candidate=res://sim/flight_session.gd --aircraft=jensen-das-ugly-stik-60 --case=trim --warmup=2400 --samples=14400 --output="$PWD/tmp/h16-pair-new.json"
```

Use a new output file. Run timing alone when possible and retain stdout/stderr
through native engine exit; reject nonzero exit, engine errors, incomplete results
or unequal fingerprints. The probe does not enforce CPU affinity; the retained
Windows campaign runner did. The current-dependency oracle command is a repeatable
method comparison, not a recreation of the dated working tree. Defaults measure
10 warmup + 60 sampled simulation seconds. The result is CPU callback cost, with
rendering and GPU work excluded.

`--battery=ideal|pack` selects the catalog data explicitly (default `ideal`, preserving
the original probe). Unsupported aircraft/mode combinations are refused before setup.
Reports include the selected mode, data path/hash and actual dynamic/pack flags; use
`--aircraft=turbo-lumber-evolution --battery=pack` for the finite ECM battery route.

[H16 results, complete before/after scripts, commands and regression evidence](../../docs/research/simulation-state/H16/README.md)
retain all three airborne repeats per aircraft and the flat runway result.

## Contact-only lake bounds (LU-25-R2)

The same complete-session probe measures conservative lake bounds rejection at
the ground-terrain and prop-disc callers. The [LU-25-R2 record](../../docs/research/landscape-upgrade/LU-25-R2/README.md)
retains the recoverable baseline commit, candidate dependency generator, exact
commands, three runway repeats, airborne controls, unfavorable component timings
and boundary/oracle regressions. Follow its reproduction steps for a frozen
before/after comparison; the H16 oracle above isolates a different change.

## Ground-patch construction cache (DT-11a)

The [plank-color follow-up](../../docs/research/visual-quality-implementation/VQ-01c/loading/timber-colors/README.md)
retains original/candidate dependency snapshots, paired field/prefab probes and a
scalar color oracle. It reuses shared vertex samples within each plank and records
the rejected generic MeshKit experiments. No persistent cache is introduced.

The [botanical spacing follow-up](../../docs/research/visual-quality-implementation/VQ-01c/loading/botanical-spacing/README.md)
retains a separate field/metadata comparison and traced layout probe for moving
cheap spacing rejection ahead of shoreline sampling. Its report includes original
scripts, reconstruction commands, unfavorable whole-field results and the repaired
habitat regression. It introduces no additional cache.

`ground_patch_cache/prepare.py --work <new-directory> --reference <original-ground_features.gd>`
copies the current field/scenery callers outside `app/` and redirects only their
ground-patch dependency. Run the emitted `field_compare.gd` with the native engine,
`--path app --script <absolute-probe> -- --output=<new.json>`; `--reverse` changes
the initial order. It checks six whole-field geometry pairs, input immutability
and cache retention. Pair zero includes first-use caches and is excluded from warm
medians. Run serially and retain checked logs. This measures detached construction;
use `loading_probe.gd` separately for the real Home/Fly route.

[Dated measurements, exact baseline, commands and limitations](../../docs/research/visual-quality-implementation/VQ-01c/loading/ground-patch-cache/README.md).
The permanent regression is `res://tests/test_ground_patch_cache.gd`.

## Segmented slipstream invariants (H17)

[H17](../../docs/research/simulation-state/H17/README.md) uses the same full-session
probe to compare local geometry/interval reuse in segmented slipstream evaluation.
It retains three P-51 trim repeats, a maneuver case, an unchanged Stik control,
component measurements and exact parity tests. Its frozen baseline includes
LU-25-R2 and H16. Follow the report's candidate generator and campaign commands;
the original-method regression fixture checks the changed law directly.

## Glow feed-target reuse (VQ-01c)

`glow_feed_reuse_probe.gd` loads original and candidate Glow flight scripts,
compares full outputs and input immutability across four aircraft, then alternates
nine timing batches. It rejects an existing output file. Export the before source
from commit `044e2590` with a UTF-8 writer; use absolute paths for both scripts.

```powershell
$probe = (Resolve-Path research/performance/glow_feed_reuse_probe.gd).Path
.tools/Godot_v4.7.2-stable_win64.exe --headless --audio-driver Dummy --path app --script $probe -- --reference=D:/evidence/glow_before.gd --candidate=$PWD/app/physics/glow/flight.gd --output=D:/evidence/glow-result.json
```

Wrap execution with `tools/godot/run_checked.py` to retain errors and exit status.
`--correctness-only` skips timings. Timing measures these method calls, not FPS;
run it alone for timing comparisons. [Dated evidence and limits](../../docs/research/visual-quality-implementation/VQ-01c/game-engineering-2026-10-24/helpers.md).

## Whole-app tick CPU (VQ-01c)

`app_cpu_per_sim.py` launches one headless debug-bridge session, flies a scripted
Stik case (`airborne` climb or `runway` taxi) and reports main-thread and whole-process
CPU per simulated second. Unlike the session probes, this includes every accepted-tick
observer (audio, statistics, crash presentation, windsock, people) that `Simulation.step_usec`
excludes. Through the bridge it caps frames at 30, because uncapped headless frames
absorb saved time. It also halves `Engine.time_scale`: ticks still arrive at 240 per
wall second, but delta-driven presentation work shrinks, so a slow host's main thread
stops saturating. The workload is therefore not normal play; compare roles only under
identical settings.

```sh
python3 research/performance/app_cpu_per_sim.py <label> airborne 10 40
```

`OPENRC_DETACH_PRESENTATION=1` disconnects the six presentation observers from
`Simulation.stepped` after the flight starts, keeping the session's contact commit and
the recorder, and refuses an unexpected connection set. Use it only to measure what the
observers cost; audio, statistics and crash presentation stop working in that session.

Run one session at a time on an idle host and alternate baseline/candidate runs.
Swapping scripts in a shared working tree is unsafe while others commit: restore the
candidate on disk as soon as the flight has loaded its scripts. The numbers are dev-VM
CPU attribution, not FPS, GPU or target-hardware qualification.
[Tick attribution and paired results](../../docs/research/visual-quality-implementation/VQ-01c/tick-observers-2026-10-27/README.md).

## Lake polygon edge walk (LU-25-R3)

`lake_polygon_pair.gd` compares an explicit prior `lake_surface.gd` with the working
tree on the default lake: 7,001 points (grid, vertices, edge midpoints, edge offsets
from 1e-9 to 0.03 m, seeded random) through the polygon helpers and the full terrain,
covered and shore-distance queries, bytewise. It then alternates 12 timing rounds of
`sample_terrain_validated` over the points inside the expanded bank box.

```sh
mkdir -p tmp/lu25r3 && git show f9e6dbe8d:app/physics/lake_surface.gd > tmp/lu25r3/lake_surface_ref.gd
python3 tools/godot/run_checked.py --timeout 600 -- "$(app/get-godot.sh)" --headless --path app \
  --script "$PWD/research/performance/lake_polygon_pair.gd" -- --reference="$PWD/tmp/lu25r3/lake_surface_ref.gd"
```

Any `PARITY mismatches` other than 0 rejects the candidate. [LU-25-R3 evidence](../../docs/research/landscape-upgrade/LU-25-R3/README.md).

## Hull-scrape observation key (GP-19e)

`hull_scrape_pair.gd` runs a prior and the current `flight_session.gd` side by side on
the hull-scrape test's sliding wingtip contact, for the electric and glow Stik, calling
`hull_scrape_observation()` one to three times per tick with a pause toggle. It
compares every packet and the final state bytewise, mutates returned rows to check
detachment, checks the memoized `HullContact.law()` against the prior formatter and
times the first call per tick.

```sh
mkdir -p tmp/gp19e && git show f9e6dbe8d:app/sim/flight_session.gd > tmp/gp19e/flight_session_ref.gd
git show f9e6dbe8d:app/physics/hull_contact.gd > tmp/gp19e/hull_contact_ref.gd
python3 tools/godot/run_checked.py --timeout 900 -- "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy \
  --script "$PWD/research/performance/hull_scrape_pair.gd" -- \
  --reference="$PWD/tmp/gp19e/flight_session_ref.gd" --hull-reference="$PWD/tmp/gp19e/hull_contact_ref.gd"
```

[GP-19e evidence](../../docs/research/ground-physics/GP-19/evidence/scrape-observation-cost/README.md).

## Hull lake bounds rejection (LU-25-R4)

`hull_lake_pair.gd` compares an explicit prior `hull_contact.gd` with the working tree on
the default Stik prepared hull and lake: 2,081 near-ground states (a grid across the bank
bounds ± 40 m and 400 around the runway, quaternion length 0.9–1.1) through `loads`
without and with both diagnostic collectors, and `terminal`, bytewise. It then times
`loads` on the runway states.

```sh
mkdir -p tmp/lu25r4 && git show d434865f2:app/physics/hull_contact.gd > tmp/lu25r4/hull_contact_ref.gd
python3 tools/godot/run_checked.py --timeout 1400 -- "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy \
  --script "$PWD/research/performance/hull_lake_pair.gd" -- --reference="$PWD/tmp/lu25r4/hull_contact_ref.gd"
```

The near-lake states sample the lake at every point, so a run takes several minutes.
Session-level pairs use `session_probe.gd --case=runway`. [LU-25-R4 evidence](../../docs/research/landscape-upgrade/LU-25-R4/README.md).

## Carburettor root solve (NITRO-06-R1)

`carburetor_pair.gd` compares an explicit prior `app/physics/glow/carburetor.gd` with the
working tree: `charge_ratio` over 506,348 demand ratios including edge values, and
`admission` over 60,802 opening/speed/capacity combinations, bytewise; then it times
20,000 interior solves.

```sh
mkdir -p tmp/nitro06r1 && git show b6e3fe7d4:app/physics/glow/carburetor.gd > tmp/nitro06r1/carburetor_ref.gd
python3 tools/godot/run_checked.py --timeout 1100 -- "$(app/get-godot.sh)" --headless --path app \
  --script "$PWD/research/performance/carburetor_pair.gd" -- --reference="$PWD/tmp/nitro06r1/carburetor_ref.gd"
```

It also replays the sweep as (a, b, a, b) pairs and runs five concurrent callers through
the root memo (NITRO-06-R2), comparing every root with the reference.
[NITRO-06-R1 evidence](../../docs/research/glow-engines/NITRO-06-R1/README.md),
[NITRO-06-R2 evidence](../../docs/research/glow-engines/NITRO-06-R2/README.md).
For NITRO-06-R3's closed-form root, pass `--max-ulp=32`: positive roots and admissions are
then compared by ulp distance (worst reported), everything else stays bytewise, and the memo
concurrency check is skipped because the solve keeps no shared state.
[NITRO-06-R3 evidence](../../docs/research/glow-engines/NITRO-06-R3/README.md).

## Ground-audio unloaded rows (GP-19f)

`ground_audio_far_pair.gd` flies three real descents to touchdown and feeds an explicit prior
`app/audio/ground_audio_model.gd` and the working tree into two accepted `GroundAudio`
observers per tick. Near-ground rows must be bytewise equal and the captured touchdown cues
identical; far rows must be unloaded.

```sh
mkdir -p tmp/gp19f && git show b6e3fe7d4:app/audio/ground_audio_model.gd > tmp/gp19f/ground_audio_model_ref.gd
python3 tools/godot/run_checked.py --timeout 1400 -- "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy \
  --script "$PWD/research/performance/ground_audio_far_pair.gd" -- --reference="$PWD/tmp/gp19f/ground_audio_model_ref.gd"
```

[GP-19f evidence](../../docs/research/ground-physics/GP-19/evidence/unloaded-rows/README.md).

## Statistics observer cost (UI-FS-08-R1)

`statistics_sample_pair.gd` compares an explicit prior `fixed_wing_adapter.gd` with the
working tree on one real session (two descents to touchdown and a runway idle), bytewise per
sample. `statistics_detector_pair.gd` feeds identical real samples to a prior and the
current `detector.gd` and compares returned events and complete snapshots after every tick.

```sh
mkdir -p tmp/uifs08r1 && git show b6e3fe7d4:app/statistics/fixed_wing_adapter.gd > tmp/uifs08r1/adapter_ref.gd \
  && git show b6e3fe7d4:app/statistics/detector.gd > tmp/uifs08r1/detector_ref.gd
python3 tools/godot/run_checked.py --timeout 1400 -- "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy \
  --script "$PWD/research/performance/statistics_sample_pair.gd" -- --reference="$PWD/tmp/uifs08r1/adapter_ref.gd"
python3 tools/godot/run_checked.py --timeout 1400 -- "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy \
  --script "$PWD/research/performance/statistics_detector_pair.gd" -- --reference="$PWD/tmp/uifs08r1/detector_ref.gd"
```

[UI-FS-08-R1 evidence](../../docs/research/flight-statistics/UI-FS-08-R1/README.md).

## Lake collision early rejection (LU-25-R6)

`lake_collision_pair.gd` compares an explicit prior `app/sim/lake_collision.gd` with the
working tree over 5,844 tick pairs around and far from the default lake, comparing events by
content (nested records included), then times distant airborne ticks.

```sh
mkdir -p tmp/lu25r6 && git show b6e3fe7d4:app/sim/lake_collision.gd > tmp/lu25r6/lake_collision_ref.gd
python3 tools/godot/run_checked.py --timeout 1400 -- "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy \
  --script "$PWD/research/performance/lake_collision_pair.gd" -- --reference="$PWD/tmp/lu25r6/lake_collision_ref.gd"
```

[LU-25-R6 evidence](../../docs/research/landscape-upgrade/LU-25-R6/README.md).

## Lake bank bounds memo (LU-25-R7)

`lake_aabb_pair.gd` compares an explicit prior `app/physics/lake_surface.gd` with the working
tree over a seeded interleaving of polygons chosen to exercise the bounds memo: equal and
±0-different copies, NaN, empty and one-vertex polygons, and one array edited in place between
calls, with points exactly on each bound ± margin and its neighbouring doubles. It then runs
the covered-terrain and shore-distance queries through the default lake. Any mismatch fails.

```sh
mkdir -p tmp/lu25r7 && git show d434865f2:app/physics/lake_surface.gd > tmp/lu25r7/lake_surface_ref.gd
python3 tools/godot/run_checked.py --timeout 800 -- "$(app/get-godot.sh)" --headless --path app \
  --script "$PWD/research/performance/lake_aabb_pair.gd" -- --reference="$PWD/tmp/lu25r7/lake_surface_ref.gd"
```

[LU-25-R7 evidence](../../docs/research/landscape-upgrade/LU-25-R7/README.md).

## Terrain sampler (GP-19g)

`terrain_pair.gd` compares an explicit prior `app/physics/ground_terrain.gd` with the working
tree: the table guard, `max_height` and every terrain sampler over tables that interleave the
default field's table with ±0, NaN, invalid, empty and edited-in-place variants (with and
without the default lake), plus 200,000 raw microrelief samples. It then times the table guard
with one runway sample. Any mismatch fails.

```sh
mkdir -p tmp/gp19g && git show df4e1ca5c:app/physics/ground_terrain.gd > tmp/gp19g/ground_terrain_ref.gd
python3 tools/godot/run_checked.py --timeout 1100 -- "$(app/get-godot.sh)" --headless --path app \
  --script "$PWD/research/performance/terrain_pair.gd" -- --reference="$PWD/tmp/gp19g/ground_terrain_ref.gd"
```

[GP-19g evidence](../../docs/research/ground-physics/GP-19/evidence/surface-table-check/README.md).

## Aero oracle reuse (H18)

`aero_pair.gd` compares an explicit prior `app/physics/aero.gd` with the working tree through
`Aero.loads`, `_wing_flow`, `wing_wake_velocity` and `local_flow_weight`, bytewise, for seven
catalog aircraft (electric and glow Stik, Extra, P-51, X8, Avanti, Timber). Each gets
`--states` random states (default 3,000): half within 3 m of the ground, random attitude,
velocity, rates, servo and flap positions, and a downwash-lag value where the aircraft has
that state. Any mismatch fails.

```sh
mkdir -p tmp/h18 && git show df4e1ca5c:app/physics/aero.gd > tmp/h18/aero_ref.gd
python3 tools/godot/run_checked.py --timeout 1700 -- "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy \
  --script "$PWD/research/performance/aero_pair.gd" -- --reference="$PWD/tmp/h18/aero_ref.gd"
```

[H18 evidence](../../docs/research/simulation-state/H18/README.md).

## Release-template session probe (VQ-01c / NK-0)

Export templates ignore `--path` and `--script`. `release_session_probe/build.sh` exports a
hard-linked snapshot of `app/` with `session_probe.gd` and a wrapper main scene, so the probe
runs inside an official release template; the shared `app/` is never written and the snapshot
is removed on exit. Install the matching template first (`linux_release.x86_64` and
`version.txt` from the official `Godot_v4.8-beta1_export_templates.tpz`, checked against the
release's `SHA512-SUMS.txt`, into `~/.local/share/godot/export_templates/4.8.beta1/`). The
binary is about 1.5 GB.

```sh
research/performance/release_session_probe/build.sh tmp/release-run/probe.x86_64
tmp/release-run/probe.x86_64 --headless --audio-driver Dummy -- \
  --aircraft=jensen-das-ugly-stik-60 --case=trim --output="$PWD/tmp/release-run/trim.json"
```

The wrapper prints `RELEASE_SESSION_PROBE complete debug=false release=true` and exits with the
probe's status. [Release tick evidence](../../docs/research/visual-quality-implementation/VQ-01c/release-tick-2026-10-27/README.md).

## Observer cadence (VQ-01c-R1)

The windsock/people, profile-smoke, ground-gear and flight-audio observers on `Simulation.stepped`
run once per rendered frame ([`presentation_cadence.gd`](../../app/render/presentation_cadence.gd);
`--presentation-cadence=<0..4>` after `--` or `OPENRC_PRESENTATION_CADENCE`; 0 is per tick).

`observer_cadence_pair.gd` flies four real Stik descents with aileron pulses. One `FlightAudio` rig per
cadence observes the same session (per tick; 1–4 frames at 60 fps; one frame at 30 and 144 fps) while a
rig-free session steps in lockstep. It reports observation counts, touchdown cues and servo transitions
per rig, and fails on a physics difference or a touchdown cue that differs from per tick.

```sh
python3 tools/godot/run_checked.py --timeout 2400 -- "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy \
  --script "$PWD/research/performance/observer_cadence_pair.gd"
```

`observer_cadence_bench.py` alternates `app_cpu_per_sim.py` runs of a baseline app copy and a candidate
app copy at each cadence, rotating the order every pair, and appends JSON lines. Freeze both copies
first (scripts copied, not hard-linked), so later edits cannot reach a run.

```sh
python3 research/performance/observer_cadence_bench.py tmp/ab-snap-<base>/app tmp/ab-snap-<cand>/app \
  tmp/cadence-airborne.jsonl airborne 3 1,2,3,4
```

[Observer cadence evidence](../../docs/research/visual-quality-implementation/VQ-01c/observer-cadence-2026-10-27/README.md).
