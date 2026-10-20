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

After the last sample, the probe frees its scene and observes weak references to the
latest playback of each audio player. It allows up to one second for the mixer to
release them; this teardown is outside all loading timings. The additive `shutdown`
record reports elapsed time, tracked/remaining playbacks and sidecar removal. A timeout
or sidecar removal failure marks the report incomplete and exits nonzero. Failures also
free the owned scene and remove successfully created settings; existing files are never
removed. This distinguishes asynchronous audio retirement from persistent retention;
it is not a general memory/RSS or production quit guarantee.

Run its isolated success/failure/retention and file-preservation checks with:

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
$godot = (Resolve-Path '.tools/Godot_v4.7.2-stable_win64_console.exe').Path
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
succeeds. The existing duration bound remains 300 seconds. Use a fresh frame JSON
path: the underlying frame writer still accepts replacement of an existing path.

The offline diagnosis reuses the native report validator, requires the matching
process log, and reports budget overruns, contiguous bursts, worst-frame indices
and timestamps, accompanying counters, and memory start/end/peak changes. It
preserves errors and warnings with log context. `--budget-ms` is an explicit
investigation threshold, not an automatic performance acceptance gate.

Reducer limits: `--top` defaults to 10 (1–1,000); `--max-input-bytes` defaults to
`64MiB` combined JSON/log input (maximum `1GiB`, plus one overflow-detection byte).
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
