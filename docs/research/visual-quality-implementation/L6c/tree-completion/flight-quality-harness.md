# L6c active-flight and temporal harness

This evidence complements the static readability matrix and the prescribed tree-motion captures. The active-flight runner measures the real scene and simulation through the normal session input path. The temporal runner records short, repeatable camera and control clips. Neither tool decides aircraft readability or owner acceptance.

## Paired active-flight performance

Run the native qualification only after the baseline and candidate have been frozen from the **same app revision**, with tree-only changes isolated between them, and when no other Godot process is active and CPU-heavy work is idle. The CLI requires explicit app paths so the older frozen first-seven-tree and oak copies cannot be compared accidentally.

```powershell
python tools/trees/flight_quality.py `
  --baseline tmp/tree-completion/frozen-natural/baseline/app `
  --candidate tmp/tree-completion/frozen-natural/candidate/app `
  --out docs/research/visual-quality-implementation/L6c/tree-completion/comparison-final/active-flight `
  --pairs 5 --warmup 10 --sample 60 `
  --width 1280 --height 720 --fps 60 `
  --baseline-env OPENRC_TREE_WIND=off `
  --candidate-env OPENRC_TREE_WIND=on
```

Each side runs serially in the order baseline/candidate, candidate/baseline, baseline/candidate, candidate/baseline, baseline/candidate. A run uses the native 60 fps cap with vsync off; calm weather; 2026-10-18 at noon; the Jensen Ugly Stik 60; normal rates; quick airborne startup; the fixed pilot camera at azimuth 0° and elevation 5°; autozoom off; and 4x MSAA. The runner verifies the actual root viewport is 1280×720 and 4x MSAA before it accepts a report.

The probe replaces only `FlightSession.read_raw` with the deterministic neutral input tape for this performance route. It leaves input and physics enabled, does not bypass pause/fault/crash checks, and does not reposition or manually step the aircraft. The route records the active physics tick rate from `Engine.physics_ticks_per_second` (240 Hz in the current app) and hashes the tick-indexed input spec.

The probe invokes the app's `FrameSamples` collector directly, but does not pass the app's `--frametimes` option: the app logger auto-quits at its requested duration. The runner passes `--probe-warmup` and `--probe-sample` to the probe so its 10 s warm-up and 60 s sample stay independent from app CLI parsing. `FrameSamples` records monotonic frame intervals, simulation ticks/time, CPU and physics process time, draw calls, primitives, visible/shadow pass counts, renderer memory, and viewport CPU/GPU render time. Frame percentiles use monotonic wall intervals; Godot process-delta percentiles and elapsed engine time are retained separately. The simulation/wall ratio uses the first-to-last monotonic frame-end timestamps matched to the first-to-last simulation samples, not an FPS cap or render-only estimate. CPU static memory plus video, texture and buffer memory are reported with availability flags. CPU/GPU timers and renderer memory are marked unavailable only when their raw samples are zero. A zero-exit process whose Godot console or engine log contains `ERROR` still fails.

Each `runs/<run-id>/frametimes.json.gz` stores the complete raw report using deterministic gzip; `console.log` and `console.log.engine.log` preserve both log streams. `series.json` stores report hashes, source identities, per-run summaries and five paired comparisons without duplicating the raw sample arrays. Its `frame_report_sha256` fields hash the original uncompressed report content; the [final storage receipt](comparison-final/active-flight/report-storage-receipt.json) binds those hashes to the compressed bytes and gives the restoration paths. The runner requires one deterministic input-tape hash and scenario hash across all ten runs; the scenario covers aircraft, weather, camera and render setup. The comparison includes frame p50/p95/p99/max, simulation/wall ratio, CPU/GPU render p95, memory p95, and visible/shadow draw and primitive p95.

Documented selectors accepted by the harness are `OPENRC_TREE_WIND`, `OPENRC_TREE_CELL_SIZE_M`, and `OPENRC_GRASS_QUALITY`. For a separate combined tree/grass case, pass the same tree selector and explicitly opt the candidate into enhanced grass:

```powershell
  --candidate-env OPENRC_TREE_WIND=on `
  --candidate-env OPENRC_GRASS_QUALITY=enhanced
```

Do not fold that combined result into the tree-only comparison. The final five-pair run on the frozen natural-cluster pair is documented in the [comparison evidence](comparison-final/README.md). It covers 1280×720 only. Temporal clips exist at both 1280×720 and 1920×1080; paired active-flight performance at 1080p is unmeasured.

## Temporal flight clips

```powershell
python tools/trees/temporal_quality.py `
  --app tmp/tree-completion/frozen/candidate/app `
  --out docs/research/visual-quality-implementation/L6c/tree-completion/temporal `
  --raw-avi-out tmp/tree-completion/temporal-raw-avi-final-20261018-r1 `
  --resolutions 720,1080 --fps 24 --frames 120 `
  --env OPENRC_TREE_WIND=on
```

The default set is five routes at both 1280×720 and 1920×1080: `slow-pan`, `pilot-input-pulse`, `pilot-bank-reversal`, `chase-control-pulse`, and `camera-cut`. Each run recorded 120 route samples. Godot's native AVI writer produced 123 movie frames (5.124918 seconds at its 41,666 µs frame duration): one startup frame and two frames while the probe drains audio during shutdown. The manifests keep the 120 route samples separate from the native AVI header's frame count and duration. The verified bundled FFmpeg is discovered automatically and encodes H.264 MP4 review files from those AVI files. Raw AVI remains under the temporary output; clip manifests retain MP4 and AVI hashes, process command, wall-clock run bounds, frozen-app source hash, probe-script hash, probe-report hash, route/input hash, and per-frame trace. The installed encoder's [durable verification receipt](ffmpeg-proof.json) records its source, version, hash and successful MP4 validation.

Every clip uses the normal airborne flight scene, calm weather, noon lighting and normal rates. Control changes enter at tick boundaries using `Engine.physics_ticks_per_second`; camera changes use the production `CameraRig`. The per-frame manifest records monotonic microsecond time, simulation tick/time, camera mode, transform and FOV, and aircraft transform/position. Keep the capture window focused: losing focus invokes the production pause path, and the probe rejects a paused clip instead of unpausing or bypassing holds. Route names describe the controls and camera motion they guarantee. They do not claim an approach through a tree LOD transition or a guaranteed lateral forest traverse. Those prescribed tree/field transitions are captured with the existing [quality capture routes](../../../../../tools/trees/quality_capture.gd) and are reviewed separately. No software-readable verdict is inferred from video or metrics.

The external probe drains audio using the same weak-reference lifecycle check as `research/performance/loading_probe.gd`; after snapshotting the route, it disables the observer, queues the scene for deletion, and waits up to one second for all playback references to be released. The teardown input guard returns neutral controls during that shutdown window, after the captured route is complete; it does not skip simulation state during a clip.

The 2026-10-18 candidate series completed all ten clips with tree wind enabled and default grass. Every report has 120 route samples, 1,190 advancing 240 Hz ticks, no tick stalls, focus retained at completion, no pause/crash/fault, enabled normal input and physics, and zero playback references remaining at exit. The frozen app source fingerprint remained `1300b6a77533315e4f67c0689a3064f7bf6bd8b4792ada6460f968fecef1d1cc`; per-clip report and AVI hashes are in the [series receipt](temporal/series.json) and clip manifests. Human readability review remains separate.

## Development verification recorded here

The external probe parsed against the frozen oak project with Godot 4.7.2 `--headless --check-only`. Six fast Python harness tests pass, covering alternating order, selector validation, `ERROR` detection, monotonic wall-clock endpoints against simulation time, paired metric summaries, and accurate temporal route names. A one-second focused native smoke on the frozen candidate verified that the temporal route advances real ticks (230 ticks and 238 live input reads) without pausing or faulting. The final 120-frame input-pulse smoke also verified clean audio shutdown; an earlier attempt lost focus to another capture window and correctly failed while paused, and an initial teardown attempt rejected Godot `ERROR` logs until the bounded audio drain and post-free input guard were added. No pause bypass is installed.

A single native candidate stability smoke on 2026-10-18 used the same 10 s warm-up and 60 s active-flight sample at 1280×720 on an RTX 3090 / OpenGL 3.3.0. It completed 3,595 frames with a 0.99945 simulation/wall ratio; frame p50/p95/p99 were 16.657/17.793/19.390 ms, and viewport CPU/GPU render p95 were 1.629/1.846 ms. CPU static-memory sampling was added after that run and checked in a separate headless smoke; the final paired runs record it. This single candidate run is a harness stability check, not a baseline comparison or hardware qualification. Its frozen oak build emitted a warning that wind was disabled for the oak material due to its transparency mode; it does not establish a tree-wind effect. The temporary raw run is at `tmp/tree-completion/flight-stability-20261018-r1/`.

Recheck the Python tests and Godot parser after harness edits:

```powershell
python -m py_compile tools/trees/flight_quality.py tools/trees/flight_quality_common.py tools/trees/temporal_quality.py tools/trees/test_flight_quality.py
python -m unittest discover -s tools/trees -p test_flight_quality.py -v
.tools/Godot_v4.7.2-stable_win64.exe --headless --check-only --path <frozen-app> --script C:/DEVELOPMENT/OpenRCsimulator/tools/trees/flight_quality_probe.gd
```
