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
| Change shaders, materials, lighting, landscape or scenery and verify it | [graphics](graphics.md#area-capture-checkers) | `"$(app/tests/visual-env.sh)" tools/<area>/check_*.py --app app --godot "$(app/get-godot.sh)" --out tmp/<new>` |
| Run the full visual capture set | [graphics](graphics.md#visual-capture-suite) | `app/capture.sh` |
| Measure frame time or GPU cost | [graphics](graphics.md#frame-diagnosis) | `--frametimes=<json> --frame-diagnostics` |
| Debug any bug | [debugging](debugging.md) | — |
| Debug a flight, force or trace bug | [debugging-physics](debugging-physics.md) | — |
| Debug a rendering or visual bug | [debugging-graphics](debugging-graphics.md) | — |
| Find out why CI failed | [shared](shared.md#ci) | `gh run view <id> --log-failed` |
| Menus and UI | [shared](shared.md#one-godot-script) for `app/tests/test_ui_*.gd`; UI screenshots run inside `app/capture.sh` | — |
| Audio | [tools/audio](../../tools/audio/README.md) | read the requirements caveat in [shared](shared.md#known-broken-or-stale-tools) |
| Aircraft Workshop | [TOOLS → Aircraft Workshop](../TOOLS.md#aircraft-workshop) | — |
| Radio and controller diagnostics | [TOOLS → Radio diagnostics](../TOOLS.md#radio-diagnostics) | — |
| Helicopter, ground vehicle | [HELICOPTER](../HELICOPTER.md), [RC monster truck](../../research/rc-monster-truck/README.md) | — |
| Physical measurement reduction (mass, inertia, thrust, video) | [TOOLS → reducers](../TOOLS.md#aircraft-measurement-reducers) | — |
| Export or release | [TOOLS → Release sequence](../TOOLS.md#release-sequence) | `app/export.sh` |

## Rules for every tool

- Use a new output directory under ignored `tmp/` for every run. Several tools refuse or silently overwrite existing output.
- Read the engine log, not only the exit code. Godot can print `SCRIPT ERROR` and still exit 0; `tools/godot/run_checked.py` catches this.
- A "pending" physical check, a valid flight-test case or a matching capture is software evidence, not physical validation.
- Search with `rg --glob '!app/captures/**' --glob '!tmp/**'`. `app/captures/` holds stale script copies and `docs/research/**/*.json` holds large manifests that match every path.
- A tool marked **unverified** in these docs exists but has not been run on the Linux dev VM; check its own README before you rely on it.
