---
name: openrc-tools
description: Find and run the right OpenRC simulator tool for a task — tests (app/test.sh, one script through the checked runner), headless traces and launch flags, the flight-test battery and flight logs for physics changes, aircraft generators, captures and per-area graphics checkers, frame diagnosis, the running-app debug bridge (menus, state, logs, hitches, leaks, UI fuzzing, smoke), GDScript compiler warnings, CI failures and evidence summaries. Use before writing any ad-hoc test, probe or debug script in this repository.
---

# Which OpenRC tool?

On enrolled shared hosts follow [host admission](../../../tools/testqueue/README.md).
Retain the owning session handle through teardown; a port alone is insufficient.

Start at the task table in [docs/tools/README.md](../../../docs/tools/README.md) and read only the doc its row names.
Every tool's README owns its commands; do not copy them into notes or new scripts.

For compatible independent headless GDScript checks, use `sim_test_run` by default: it launches
and waits (`wait_s`, default 60) for the compact result in one call; repeat it with the returned
`request_id` while tests still run. `sim_fleet` shows which hosts are online, idle or busy and why.
For long detached batches use `sim_test_launch` with a stable client-chosen `request_id`.
Both take a `jobs` array; each job requires `script`
and accepts `require` (literal completion markers), `timeout`, `platform` and `host`.
Optional `source` selects another checkout.
`platform` defaults to the caller's OS; use `any` only for a reviewed portable check.
The launch is nonblocking and its detached supervisor survives the client. Keep the
candidate stable until `sim_test_status(request_id)` reports `source_frozen: true`.
Status shows cached progress and automatically collected artifacts; inspect the final
outcomes and evidence, since an accepted ticket is not a pass.
`sim_test_recover(request_id)` resumes the same snapshot, IDs and hosts without rerunning
failed or uncertain attempts. If MCP is unavailable, use `testctl.py pool run` from the
[test pool guide](../../../tools/testqueue/README.md) and set `--platform` to the required
OS unless portability is established: the CLI's default is `any`.
Graphics, benchmarks, composite suites and interactive sessions use their existing tools.

Most-used commands (repository root, Bash):

| Task | Command |
| --- | --- |
| Independent headless tests | `sim_test_run` with one job per script (or `sim_test_launch` + `sim_test_status`); `sim_fleet` for hosts |
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
