# Tool index

Choose a tool before writing ad-hoc test or debug code. Read the linked contract for its inputs, outputs and side effects. Commands below assume the repository root and Bash; native Windows uses `python`. [Setup and releases](../TOOLS.md) · [Architecture](../STACK.md).

## Route by task

| Task | Entry point / contract |
| --- | --- |
| Full app checks or a CI partition | `app/test.sh`; [suite and snapshot rules](shared.md#full-app-suite). |
| One Godot test, probe or parse check | [Checked runner](shared.md#one-godot-script); catches errors even when Godot exits zero. |
| Direct flight, weather or headless trace | [Launch flags](shared.md#launch-flags) and [trace validation](physics.md#headless-trace-checks). |
| Aircraft handling comparison | [Flight-test battery](physics.md#flight-test-battery); match baseline/candidate aircraft and case sets. |
| Aircraft data or generated assets | [Source pipelines](physics.md#aircraft-data-and-generators); edit the owner, regenerate, then `--check`. |
| Flight feel, exact replay or candidate replay | [Flight logs](../FLIGHT-LOGGING.md); preserve a baseline and the same input tape. |
| Native flight backend development | [NK-3 C++ tools](../../research/native-kernel/README.md#c-development-tools-nk-3): sanitizers, symbols, exactness and timing. |
| Rendering, materials, lighting or scenery | [Area checkers](graphics.md#area-capture-checkers); full suite: `app/capture.sh`. |
| Frame time or GPU cost | [Frame diagnosis](graphics.md#frame-diagnosis); use the target display/GPU and record actual pixels. |
| High profile or Windows NVIDIA package | [Graphics modes](../../tools/graphics/README.md); [NVIDIA build/launch](../../tools/graphics/native/README.md). |
| Running-app UI, keys, sticks, state, logs or screenshots | `python3 tools/debug/debugctl.py launch`; [debug bridge](../../tools/debug/README.md#quick-start). Add `--headless` when rendering is unnecessary. |
| Running-app regression pass | `python3 tools/debug/debugctl.py smoke`; [scenarios and limits](../../tools/debug/README.md#hunting-stutter-leaks-and-bugs-pt1h-r8). |
| Stutter, script CPU, leaks, watchpoints or UI fuzzing | [Debug bridge diagnostics](../../tools/debug/README.md#hunting-stutter-leaks-and-bugs-pt1h-r8): `frames`, `timeline`, `profile`, `objects`, `soak`, `break`, `monkey`. |
| GDScript compiler warnings | `python3 tools/debug/gdscript_warnings.py --files 'area/*.gd'`; [warning baseline](../../tools/debug/README.md#hunting-stutter-leaks-and-bugs-pt1h-r8). |
| Crash, exit leaks, process RAM or disk use | [Incident bundles](../../tools/godot/README.md#incident-bundles-and-perfetto-timelines-pt1h-r5), [resource tools](../../tools/godot/README.md#process-ram-io-and-storage-pt1h-r4). |
| Bug investigation | [General playbook](debugging.md), [physics](debugging-physics.md), [graphics](debugging-graphics.md). |
| CI failure or evidence summary | [CI](shared.md#ci); [checked-log summary/JUnit](shared.md#evidence-summary). |
| Aircraft Workshop | [Generation, tests, captures and analysis](../TOOLS.md#aircraft-workshop). |
| Player skin template and texture-only export | [Skin toolkit](../../tools/skins/README.md); [player tutorial](../AIRCRAFT-SKINS.md). |
| Radio/controller diagnostics | [Device report, calibration and latency](../TOOLS.md#radio-diagnostics). |
| Helicopter or ground vehicle | [Helicopter guide](../HELICOPTER.md), [ground-vehicle tools](../../research/rc-monster-truck/README.md). |
| Physical measurements | [Mass, inertia, thrust and video reducers](../TOOLS.md#aircraft-measurement-reducers). |
| Audio | [Audio tool contracts and dependencies](../../tools/audio/README.md). |
| Blender scene inspection or authoring | [Blender bridge and setup](../../tools/blender/README.md); apply `openrc-blender` first. |
| Startup or public logos | [Startup source](../../app/assets/branding/README.md), [public identity](../../site/BRANDS.md#openrc-identity); use their generator `--check` first. |
| Website languages and metadata | [Website workflow](../../site/README.md#search-metadata-and-static-languages-web-0811). |
| Export or release | [Release sequence](../TOOLS.md#release-sequence); `app/export.sh` recreates `dist/`. |

## Rules for every tool

- [Import the pinned engine's resources](shared.md#engine) before standalone scripts in a fresh checkout or copy.
- Use a fresh ignored output directory for each run. Read the contract before invoking generators, `--accept`, exports or cleanup; do not assume `--help` is harmless for legacy scripts.
- Read the checked verdict and logs, not only the exit code. Verify requested cases and completion; [known caveats](shared.md#known-broken-or-stale-tools) identify partial-result and overwrite risks.
- Keep long runs on the exact source snapshot being reviewed. Coordinate one rendered app at a time and pass your debug session's port on subsequent commands: `OPENRC_DEBUG_BRIDGE=<port> python3 tools/debug/debugctl.py …`.
- Report the platform, renderer, actual resolution and evidence limits. Pending physics checks, matching images and software-only timing do not establish physical or target-hardware acceptance.
- Follow [AGENTS](../../AGENTS.md#discover-code) for code discovery. Agent skills `openrc-tools` and `openrc-debug` route to these guides.
