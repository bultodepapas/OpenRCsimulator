---
name: openrc-debug
description: Launch, inspect and drive the running OpenRC simulator from the shell (no mouse) through its debug bridge or its MCP server (sim_* tools) — look (every control with a ref, name, value and options), choose any option by its field name, catalog/setup for aircraft, start, landscape and time of day, menus by label, keys and shortcuts, controller actions, sticks, pause/step, telemetry, screenshots, live logs, settings, UI crawl — and hunt stutter (frame hitches), leaks (object census, soak), physics bugs (tick watchpoints, rewind to before a crash, force/velocity/wind gizmos), reproducible bug reports (bugit/bugitgo), render diagnostics (GPU observations, ablation, overdraw view), script CPU (profiler), UI bugs (seeded monkey) and GDScript compiler warnings. Use when a task needs the real running app rather than a test script.
---

# Drive the running app

The tool and its full command reference live in [tools/debug/README.md](../../../tools/debug/README.md): start at
its "I want to…" table. `python3 tools/debug/debugctl.py --help` lists the client commands offline. For any other
task (tests, traces, flight-test battery, captures) use the `openrc-tools` skill.

```sh
D="python3 tools/debug/debugctl.py"
$D launch --headless            # prints its port; plain `launch` renders 1920x1080 under Xvfb (for screenshots)
export OPENRC_DEBUG_BRIDGE=<port> # in the same shell command as the calls below when other agents share the machine
$D look                         # START HERE: every control as ref/role/name/value/options, plus next steps
$D choose field="Text size" value=125%   # or ref=e9; one verb for options, toggles, sliders, text
$D catalog; $D setup aircraft=<id> start=airborne time_of_day=sunset   # validated, read back
$D fly aircraft=<catalog-id> start=airborne
$D state                        # route, screens, pose, pause, crash, log counts
$D shortcuts                    # every key; key name=Shift+C; control name=gear_toggle
$D logs --follow                # engine/script errors and state-change events
$D screenshot max_width=960     # then open the printed PNG
$D crawl                        # UI smoke test of every screen
$D stop
```

- MCP: `python3 tools/debug/mcp_server.py` (declared in `.mcp.json`) gives the same as typed `sim_*` tools;
  each action returns the new snapshot, and `sim_fly` leaves the aircraft flying.
- Write a repro as a file of these lines and run it with `$D run repro.txt --fail-on-error` (stops at the first
  failure or new engine error; `assert expr=`).
- Stutter: `$D frames` (percentiles, hitches with causes). Leaks: `$D objects baseline=true` … `diff=true`, or
  `$D soak scenario.txt`. Physics bugs: `$D break expr="-s[2] < 1" wait=true`. Script CPU: `launch --script-profile`,
  then `$D profile seconds=20`. Render diagnostics (rendered launch, not `--headless`): `$D render` (raw root GPU
  readings with unverified freshness, CPU time and draw counters), `$D ablate` (unverified timing deltas),
  `$D viewmode name=overdraw`. Zero GPU readings are unavailable; separate SubViewport last readings may be stale
  and are not included in the root reading. Go back in flight time:
  `$D rewind arm=true` before flying, `$D rewind seconds=2` after the event. See the physics: `$D gizmos show=all`.
  File a bug with its exact flight state: `$D bugit --note "…"`; reopen it with `$D bugitgo <folder>`. A long load frame: `launch --verbose`, then `$D timeline --hitch`. Random UI testing: `$D monkey --seed N --keys`. Compiler warnings:
  `python3 tools/debug/gdscript_warnings.py --files 'area/*.gd'`.
- Discover anything else with `$D methods node=AppRoot`, `$D find name=*Camera*`, `$D get node=... `, then `call`/`set`/`eval`.
- It is software inspection, not flight evidence: exact replays use flight logs (`record action=start`).
- Regression pass in one command: `$D smoke` (own headless session; add a `tools/debug/scenarios/*.txt` file when
  existing checks cannot reproduce an important flow regression). Load phases inside one long frame: `launch --verbose`, then `$D timeline --since <seq>`.
- Other agents may share this machine: put `OPENRC_DEBUG_BRIDGE=<your port>` on every command after `launch`.
- Run one rendered app at a time on the shared VM; always `stop` it.
