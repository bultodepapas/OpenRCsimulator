# Tool index

Find the tool for your task here before you write ad-hoc test or debug code. Read only the doc your task row names. Run commands from the repository root in Bash. Human setup and the release sequence live in [TOOLS](../TOOLS.md).

## Route by task

| Task | Read | First command |
| --- | --- | --- |
| Run the tests, or check a change before commit | [shared](shared.md#full-app-suite) | `app/test.sh` |
| Run or write one test script | [shared](shared.md#one-godot-script) | `python3 tools/godot/run_checked.py --timeout 90 -- "$(app/get-godot.sh)" --headless --path app --script res://tests/test_X.gd` |
| Launch the app with flags, or write a headless trace | [shared](shared.md#launch-flags) | `"$(app/get-godot.sh)" --headless --path app -- --trace=tmp/t.csv --t=3` |
| Change aircraft handling (roll rate, throws, aero data) and validate it | [physics](physics.md#flight-test-battery) | `python3 research/flight-test/run.py --out tmp/ft-base --aircraft <id> --only trim_sweep,stall_power_off,vmax,roll_rate` |
| Edit an aircraft JSON or other generated data | [physics](physics.md#aircraft-data-and-generators) | run the owning generator's `--check` |
| Compare flight feel before and after a physics change | [physics](physics.md#flight-log-and-replay) | `python3 tools/flight_log/flight_log.py --help` |
| Develop or diagnose the NK-3 C++ port (ASan/UBSan, compilation database, profiling symbols, exactness/timing) | [Native kernel tools](../../research/native-kernel/README.md#c-development-tools-nk-3) | `python3 research/native-kernel/devtools.py --help` |
| Change shaders, materials, lighting, landscape or scenery and verify it | [graphics](graphics.md#area-capture-checkers) | `"$(app/tests/visual-env.sh)" tools/<area>/check_*.py --app app --godot "$(app/get-godot.sh)" --out tmp/<new>` |
| Run the full visual capture set | [graphics](graphics.md#visual-capture-suite) | `app/capture.sh` |
| Measure frame time or GPU cost | [graphics](graphics.md#frame-diagnosis) | `--frametimes=<json> --frame-diagnostics` |
| Drive or inspect the running app: menus, settings, keys, controller actions, sticks, state, live log, screenshots | [debug bridge](../../tools/debug/README.md#quick-start) | `python3 tools/debug/debugctl.py launch --headless` (plain `launch` for 1080p pictures), then `ui`, `press text=Fly`, `state`, `logs --follow` |
| Check the running app before a commit (UI crawl, flow scenarios, random UI walk, leak soak, crash report) | [debug bridge → smoke](../../tools/debug/README.md#hunting-stutter-leaks-and-bugs-pt1h-r8) | `python3 tools/debug/debugctl.py smoke` (about 3.5 min) |
| Find a stutter, a slow action or a long loading frame | [debug bridge → stutter](../../tools/debug/README.md#hunting-stutter-leaks-and-bugs-pt1h-r8) | `frames`; phases inside one frame: `launch --verbose`, then `timeline --hitch`; script CPU: `launch --script-profile`, then `profile seconds=20` |
| Find a leak or growth over repeated actions | [debug bridge → leaks](../../tools/debug/README.md#hunting-stutter-leaks-and-bugs-pt1h-r8), [lifecycle check](../../tools/godot/README.md#repeated-scene-lifecycle-checks-pt1h-r6) | `soak scenario.txt --cycles 5`; `objects baseline=true` … `objects diff=true` |
| Stop a flight at the tick something goes wrong | [debug bridge → watchpoints](../../tools/debug/README.md#hunting-stutter-leaks-and-bugs-pt1h-r8) | `break expr="-s[2] < 1" wait=true` |
| Find UI bugs nobody scripted | [debug bridge → monkey](../../tools/debug/README.md#hunting-stutter-leaks-and-bugs-pt1h-r8) | `monkey --steps 300 --seed 1 --keys` (a failure leaves a replayable script) |
| Check GDScript compiler warnings | [debug bridge → warnings](../../tools/debug/README.md#hunting-stutter-leaks-and-bugs-pt1h-r8) | `python3 tools/debug/gdscript_warnings.py --files 'area/*.gd'` |
| A crash or objects leaked at exit | [debug bridge launch options](../../tools/debug/README.md#quick-start), [incident bundles](../../tools/godot/README.md#incident-bundles-and-perfetto-timelines-pt1h-r5) | `debugctl.py stop` / `status` print the crash reason, GDScript backtrace and leaks |
| Debug any bug | [debugging](debugging.md) | — |
| Debug a flight, force or trace bug | [debugging-physics](debugging-physics.md) | — |
| Debug a rendering or visual bug | [debugging-graphics](debugging-graphics.md) | — |
| Find out why CI failed | [shared](shared.md#ci) | `gh run view <id> --log-failed` |
| Menus and UI | [shared](shared.md#one-godot-script) for `app/tests/test_ui_*.gd`; UI screenshots run inside `app/capture.sh` | — |
| Regenerate the official startup logo segments | [Branding source](../../app/assets/branding/README.md) | `python tools/branding/build_logo.py --check` |
| Build/check website languages and search metadata | [Website guide](../../site/README.md#search-metadata-and-static-languages-web-0811) | `python3 site/build_locales.py --check` then `python3 site/test_locales.py` |
| Regenerate website, README and sharing logos | [Public identity](../../site/BRANDS.md#openrc-identity) | `python tools/branding/build_public.py --check` |
| Audio | [tools/audio](../../tools/audio/README.md) | read the requirements caveat in [shared](shared.md#known-broken-or-stale-tools) |
| Inspect or drive Blender from an agent (scene queries, Python, renders, API and manual search) | [tools/blender](../../tools/blender/README.md) | `tools/blender/mcp-setup.sh`, then `tools/blender/mcp-bridge.sh <file.blend>` |
| Aircraft Workshop | [TOOLS → Aircraft Workshop](../TOOLS.md#aircraft-workshop) | — |
| Radio and controller diagnostics | [TOOLS → Radio diagnostics](../TOOLS.md#radio-diagnostics) | — |
| Helicopter, ground vehicle | [HELICOPTER](../HELICOPTER.md), [RC monster truck](../../research/rc-monster-truck/README.md) | — |
| Physical measurement reduction (mass, inertia, thrust, video) | [TOOLS → reducers](../TOOLS.md#aircraft-measurement-reducers) | — |
| Export or release | [TOOLS → Release sequence](../TOOLS.md#release-sequence) | `app/export.sh` |

## Rules for every tool

- In a fresh checkout, worktree or app copy, import once before running any Godot tool: `"$(app/get-godot.sh)" --headless --path <app-dir> --audio-driver Dummy --import` (the form `app/test.sh` uses). Without the import cache, scripts fail with missing `.godot/imported` resources. Pass `--godot "$(app/get-godot.sh)"` to Python runners that accept it.
- Use a new output directory under ignored `tmp/` for every run. Several tools refuse or silently overwrite existing output.
- Read the engine log, not only the exit code. Godot can print `SCRIPT ERROR` and still exit 0; `tools/godot/run_checked.py` catches this.
- A "pending" physical check, a valid flight-test case or a matching capture is software evidence, not physical validation.
- Search with `rg --glob '!app/captures/**' --glob '!tmp/**'`. `app/captures/` holds stale script copies and `docs/research/**/*.json` holds large manifests that match every path.
- A tool marked **unverified** in these docs exists but has not been run on the Linux dev VM; check its own README before you rely on it.
- Other agents may work on this machine at the same time. Run at most one rendered app; give every debug-bridge
  command after `launch` your session's port: `OPENRC_DEBUG_BRIDGE=<port> python3 tools/debug/debugctl.py …`.
- Agent skills route here: `openrc-tools` (this index) and `openrc-debug` (the running app).
