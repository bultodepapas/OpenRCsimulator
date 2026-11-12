---
name: openrc-tools
description: Find and run the right OpenRC simulator tool for a task — tests (app/test.sh, one script through the checked runner), headless traces and launch flags, the flight-test battery and flight logs for physics changes, aircraft generators, captures and per-area graphics checkers, frame diagnosis, the running-app debug bridge (menus, state, logs, hitches, leaks, UI fuzzing, smoke), GDScript compiler warnings, CI failures and evidence summaries. Use before writing any ad-hoc test, probe or debug script in this repository.
---

# Which OpenRC tool?

On enrolled shared hosts follow [host admission](../../../tools/testqueue/README.md).
Retain the owning session handle through teardown; a port alone is insufficient.

Start at the task table in [docs/tools/README.md](../../../docs/tools/README.md) and read only the doc its row names.
Every tool's README owns its commands; do not copy them into notes or new scripts.

Most-used commands (repository root, Bash):

| Task | Command |
| --- | --- |
| One test script, failing on engine errors that exit 0 | `python3 tools/godot/run_checked.py --timeout 90 -- "$(app/get-godot.sh)" --headless --path app --script res://tests/test_X.gd` |
| Full local app verification for broad changes or release preparation (40+ min); CI runs it as a required gate | `app/test.sh` (on a stable snapshot when other sessions edit the tree) |
| Headless flight trace | `"$(app/get-godot.sh)" --headless --path app -- --trace=tmp/t.csv --t=3 --aircraft=<id>` |
| Handling change: before/after | `python3 research/flight-test/run.py --out tmp/ft-base --aircraft <id> --only trim_sweep,vmax,roll_rate`, then `compare.py` |
| The running app, any interaction | `python3 tools/debug/debugctl.py launch --headless`, then `ui`, `press text=…`, `state`, `logs --follow` (skill `openrc-debug`) |
| Running-app regression pass | `python3 tools/debug/debugctl.py smoke` |
| GDScript compiler warnings | `python3 tools/debug/gdscript_warnings.py --files 'area/*.gd'` |
| Visual change during development | the affected [area checker or capture](../../../docs/tools/graphics.md#area-capture-checkers); CI runs `app/capture.sh` |

Rules that save hours:

- Use a new output directory under `tmp/` for every run; read the engine log, not only the exit code.
- Follow the [verification scope](../../../docs/tools/shared.md#verification-scope); repeat a check when its inputs change, it fails or evidence remains inconclusive.
- A fresh checkout or copy needs `"$(app/get-godot.sh)" --headless --path <app> --audio-driver Dummy --import` once.
- Other agents may share this machine: one rendered app at a time; never `git stash`; stage only your own paths.
- Known broken tools are listed in [docs/tools/shared.md](../../../docs/tools/shared.md#known-broken-or-stale-tools).
- Software checks are not physical validation; llvmpipe numbers are not target-hardware performance.
