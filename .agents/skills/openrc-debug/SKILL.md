---
name: openrc-debug
description: Launch, inspect and drive the running OpenRC simulator from the shell (no mouse) through its debug bridge — menus by label, keys and shortcuts, controller actions, sticks, pause/step, telemetry, screenshots, live logs, settings, UI crawl — and hunt stutter (frame hitches), leaks (object census, soak), physics bugs (tick watchpoints), script CPU (profiler), UI bugs (seeded monkey) and GDScript compiler warnings. Use when a task needs the real running app rather than a test script.
---

# Drive the running app

The tool and its full command reference live in [tools/debug/README.md](../../../tools/debug/README.md). Read it
before anything beyond the quick start.

```sh
D="python3 tools/debug/debugctl.py"
$D launch                       # isolated profile, 1920x1080 under Xvfb (add --headless: no renderer, lighter)
$D ui                           # what is on screen; press text=<label>, select, set_value, type, close
$D fly aircraft=<catalog-id> start=airborne
$D state                        # route, screens, pose, pause, crash, log counts
$D shortcuts                    # every key; key name=Shift+C; control name=gear_toggle
$D logs --follow                # engine/script errors and state-change events
$D screenshot max_width=960     # then open the printed PNG
$D crawl                        # UI smoke test of every screen
$D stop
```

- Write a repro as a file of these lines and run it with `$D run repro.txt --fail-on-error` (stops at the first
  failure or new engine error; `assert expr=`).
- Stutter: `$D frames` (percentiles, hitches with causes). Leaks: `$D objects baseline=true` … `diff=true`, or
  `$D soak scenario.txt`. Physics bugs: `$D break expr="-s[2] < 1" wait=true`. Script CPU: `launch --script-profile`,
  then `$D profile`. Random UI testing: `$D monkey --seed N --keys`. Compiler warnings:
  `python3 tools/debug/gdscript_warnings.py --files 'area/*.gd'`.
- Discover anything else with `$D methods node=AppRoot`, `$D find name=*Camera*`, `$D get node=... `, then `call`/`set`/`eval`.
- It is software inspection, not flight evidence: exact replays use flight logs (`record action=start`).
- Run one rendered app at a time on the shared VM; always `stop` it.
