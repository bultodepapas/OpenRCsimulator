# Agent debug bridge (PT1h-R7)

Drive a **running** app from the shell, with no mouse and no editor. You can read its state and live log, use every
menu, setting, shortcut and controller action, fly with stick values or drive the RC truck, pause and step exact
physics ticks, sample telemetry, take screenshots, record flight logs and evaluate expressions. For batch checks of
one script, use the [checked runner](../godot/README.md) instead. Claude Code and Codex find this tool through the
`openrc-debug` skill; the [tool index](../../docs/tools/README.md) routes every other task.

Contents: [quick start](#quick-start) · [I want to…](#i-want-to) · [commands](#commands) ·
[stutter, leaks and bugs](#hunting-stutter-leaks-and-bugs-pt1h-r8) · [recipes](#recipes) ·
[how it works and limits](#how-it-works-and-limits) · [performance](#performance) · [verification](#verification).
`python3 tools/debug/debugctl.py --help` prints the client's commands; `debugctl.py help` asks a running app for its
own list.

## I want to…

`D="python3 tools/debug/debugctl.py"`. `launch` prints its port and a ready-made prefix (`"use"`); when other agents
share the machine, put `OPENRC_DEBUG_BRIDGE=<port>` on every command (or `export` it in the same shell command).
Commands without it refuse to guess when several sessions are live. Labels match case-insensitively (`text=Fly`
finds "FLY"); `fly` without `aircraft=` flies Home's selection, the Ugly Stik in a fresh profile.

| Task | Commands |
| --- | --- |
| Start / stop the app | `$D launch --headless` (no pictures, light) or `$D launch` (1920×1080 under Xvfb); add `--import` after pulling new assets; `$D status`; `$D stop` (prints `"crash": null, "leaked_objects": 0` on a clean exit) |
| See what is on screen and click it | `$D ui`, `$D press text="Fly"`, `$D select text=Language item="Español"`, `$D close` |
| Open a menu or setting directly | `$D open screen=settings` (no screen: list them) |
| Fly, restart, go back | `$D fly aircraft=<id> start=airborne`, `$D restart`, `$D home` |
| Press keys and controller buttons | `$D shortcuts`, `$D key name=Shift+C`, `$D control name=gear_toggle` |
| Fly with stick values / drive the truck | `$D sticks pitch=0.3 throttle=0.8 for_s=2`, `$D drive throttle=0.6 for_s=1` |
| Read the state / the live log | `$D state`, `$D logs --follow`, `$D logs --summary` |
| Take a picture | `$D screenshot max_width=960 format=jpg` (not under `--headless`) |
| Pause, step, stop at a condition | `$D pause`, `$D step ticks=240`, `$D break expr="-s[2] < 1" wait=true` |
| Record values per tick | `$D watch --every 24 --csv tmp/w.csv h=-s[2]`, `$D record action=start` (flight log) |
| Find a stutter / slow load / hot script | `$D frames`; `launch --verbose` + `$D timeline --hitch`; `launch --script-profile` + `$D profile seconds=20` |
| Find a leak | `$D soak scenario.txt --cycles 5`, `$D objects baseline=true` then `$D objects diff=true` |
| Find UI bugs | `$D crawl`, `$D monkey --steps 300 --seed 1 --keys` |
| Reproduce a bug as a script | write `tmp/repro.txt` (one command per line), `$D run tmp/repro.txt --fail-on-error` |
| Check everything before a commit | `$D smoke` (own session, about 3.5 min) |
| Any property or method | `$D methods node=AppRoot`, `$D get node=… prop=…`, `$D call …`, `$D eval expr="…"` |
| GDScript compiler warnings | `python3 tools/debug/gdscript_warnings.py --files 'area/*.gd'` |

## Quick start

From the repository root, Bash:

```sh
D="python3 tools/debug/debugctl.py"
$D launch                       # Home at 1920x1080 under Xvfb (or your display), isolated profile; prints the run folder
$D ui                           # controls of the top dialog/menu; * marks keyboard focus
$D fly aircraft=p51d-mustang-120 start=airborne
$D state                        # route, screens, focus; flight tick, pause/holds/crash, pose, commands, log counts
$D shortcuts                    # every key and controller action for this vehicle
$D control name=gear_toggle     # what a bound controller button does
$D sticks pitch=0.3 throttle=0.8 for_s=2
$D screenshot max_width=960     # prints the PNG path; open it with an image viewer or the Read tool
$D logs --follow                # errors, warnings, prints and state-change events as they happen
$D home
$D stop
```

Launch options:

- `launch -- --quick-flight` takes the direct flight route instead of Home, as `--path app -- <args>` always does.
  Any arguments after `--` are passed to the app.
- `launch --headless` runs without a renderer. Everything except screenshots works, and it is much lighter.
- `--resolution 1280x720` is faster on llvmpipe. 1920×1080 is the default because it is the
  [primary target](../../AGENTS.md#display-resolution-priorities).
- Each launch writes `tmp/debug-bridge/<time>-<port>/` with:
  - `engine.log` (stdout and stderr);
  - `log.jsonl` (one flushed record per line, so `tail -f` works);
  - `shots/`, `launch.json` and `profile/`.
- `profile/` holds `user://` (preferences, flight logs, caches), so a session never edits the player's settings.
  `--profile DIR` reuses a profile between launches. `--real-profile` uses the real one: Home's Fly then saves the
  selection like a person would.
- **Several agents on one machine.**
  - Each launch claims its own port atomically, in `tmp/debug-bridge/sessions/<port>.json` (0600, with its token),
    and skips ports held by a live session.
  - Commands address `OPENRC_DEBUG_BRIDGE`'s port, else the last launch on the machine. That may be another agent's,
    so when you share the machine, put `OPENRC_DEBUG_BRIDGE=<your port>` on every command.
  - `stop` refuses to guess when several sessions are live, and other commands warn.
  - `status` tells whether the app is alive. `stop` waits up to 60 s for the process to exit; `stop --force` kills
    the process group it launched.
- `--app DIR` runs a candidate copy (with its import cache and the sibling folders linked beside it), for
  before/after comparisons without touching the shared tree.
- `--script-profile` adds `-d --profiling --ignore-error-breaks`, so the engine prints its per-function GDScript
  profile about once a second (read it with `profile`). `--verbose` names each object leaked at exit.
- `stop` reports how the engine ended: `leaked_objects` / `leaked_instances` at exit, and a `crash` with its reason
  and GDScript backtrace, taken from `engine.log` (exit 1 after a crash). `status` shows the same when the app died.
- If the engine cannot listen (the port is still being released), `launch` retries once on a free port. It accepts
  an answer only from its own process group, and it stops what it launched whenever it fails.
- Run one rendered app at a time on the shared VM (about 2–3 GB RSS).

## Commands

`$D help` prints the live list. Arguments are `key=value`. Values are JSON when they parse (`true`, `0.4`, `[1,2]`,
`{"a":"b"}`), otherwise strings. Output is compact JSON; `--pretty` indents and `--json` forces JSON. `ui`, `help`,
`shortcuts`, `control` and `methods` print readable tables. `ui` shows each path below its scope, without generated
`@Type@123` segments; `--paths` prints full paths. Exit status: 0 ok, 1 refused (the reason is on stderr),
2 usage or connection error.

| Area | Commands |
| --- | --- |
| Session | `launch`, `status`, `ready`, `stop [--force]`, `ping`, `quit`, `clean [--keep N]` (old run folders hold about 11 MB of shader cache each; never removes the live one) |
| Routes | `fly aircraft=<id> start=<runway\|airborne\|…>` (from Home), `home`, `restart`; truck: `call node=AppRoot method=start_ground_vehicle args=["mt8-bisonte"]`, then `press text=drive` |
| Menus and settings | `open screen=<…>` (no screen lists them), `close` (Esc/Back; never Home itself), `ui [all=true] [labels=true] [text=]`, `press text=\|path= [mode=signal]`, `select text=<OptionButton/TabBar/ItemList name or label> item=<label>\|index=`, `select popup=true item=` for an open PopupMenu, `set_value value=`, `type text= [into=<label or placeholder>] [submit=true]` (a dialog's field has its own focus), `focus`, `prefs` |
| Keys and controller | `shortcuts`; `key name=<C\|Shift+C\|F10\|Escape…> [action=tap\|press\|release] [hold_s=]`; `control [name=<action>] [hold=]` (the same handlers as a bound controller button); `action name=<input action>`; `mouse action=click\|double\|right\|move\|down\|up\|drag\|wheel x= y=` or `text=` |
| Pilot input | `sticks roll= pitch= yaw= throttle= [for_s=]` / `sticks release=true` (fixed wing and helicopter); `drive throttle= steering= brake= reverse= [for_s=]` / `drive release=true` (RC truck) |
| Time | `pause`, `resume`, `step ticks=<n>`, `time_scale value=`, `wait frames=\|seconds=\|until=<expr> [timeout_s=]`, `break expr= [name=] [pause=] [once=] [wait=]` / `break list=true` / `break clear=<name\|all>` |
| Observe | `state`, `logs [--since N] [--level …] [--follow] [--summary]`, `frames [window=] [hitch_ms=] [factor=] [reset=]`, `objects [baseline=] [diff=] [top=]`, `profile [since=] [top=] [sort=self\|total]`, `perf`, `screenshot [path=] [format=png\|jpg] [max_width=]` (JPEG at quality 85 is about 8× smaller for looking), `view [name=]`, `window [size=WxH] [mode=]`, `record action=start\|stop\|mark\|status` |
| Telemetry | `sample exprs={"h":"-s[2]"} every_ticks= count=` (rows per simulation tick); client `watch [--every N] [--count N] [--csv FILE] h=-s[2] …` streams CSV |
| Introspection | `methods node=<path>`, `find name=<glob> type=<class>`, `get node= [prop=]`, `set node= prop= value=`, `call node= method= args=[…]`, `eval expr= [node=]`, `assert expr= [message=]`, `nodes path= depth=` |
| Scripts | `smoke [--seed S] [--steps N] [--cycles N] [--app DIR]`, `run FILE\|- [--keep-going] [--fail-on-error]`, `repl`, `crawl [--shots]`, `timeline [--since N] [--top N]`, `soak FILE [--cycles N] [--warmup N] [--tolerance N]`, `monkey [--steps N] [--seed S] [--keys] [--out FILE]` |

Notes on the commands:

- **Labels.** `press`, `select` and the other label lookups try, in order: the exact label, the label without its key
  hint (`DRIVE · Enter`), the node name, a label prefix, then a substring. A tie is refused and the candidate paths
  are listed. Generated paths (`@VBoxContainer@95`) change between runs, so scripts should use labels.
- **Expressions.** Expressions are Godot [Expression](https://docs.godotengine.org/en/stable/classes/class_expression.html)s.
  - `eval`, `assert` and `wait` run on AppRoot, with the inputs `app`, `tree` and `bridge` and every engine singleton
    by name (Expression cannot reach singletons by itself). Examples: `flight.session.sim.tick`,
    `flight._rig.set_view("chase")`, `Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)` and
    `ClassDB.class_call_static("Node", "get_orphan_node_ids")`.
  - `sample` adds `session`, `sim` and `s` (= `sim.state`: NED position [0..2], body velocity [3..5], quaternion
    [6..9], body rates [10..12]).
- **Pose.** `state` reports the pose in NED metres, plus Euler degrees and body rates.
- **Sticks.** roll, pitch and yaw take −1…1; pitch + is stick back (nose up). throttle is a 0…1 target, reached at the
  keyboard throttle rate. `for_s` counts simulation time. A connected radio or gamepad flies instead. Sticks stay
  until `release=true`, `for_s` or the end of the flight, including across a crash restart.
- **UI scope.** `ui` and the label lookups look at the top dialog or popup, else the top menu screen, else the layer
  holding keyboard focus (an accident report, the truck garage), else everything. `all=true` lists everything,
  including HUD overlay buttons.
- **Events.** The log records `event`s for changes of route, screens, pause, crash, fault and pause reason, with
  their tick.

## Hunting stutter, leaks and bugs (PT1h-R8)

Closing the gaps in the [2026-10-24 review](../../docs/research/debug-tooling-gaps-2026-10-24.md):

- **Stutter: `frames`.**
  - Every frame's wall time goes into a 7,200-frame ring, with the physics ticks the frame ran.
  - `frames` gives the mean, p50/p95/p99, max, mean fps, 1 % low fps and the frames that hit the
    `max_physics_steps_per_frame` limit.
  - A frame longer than `max(hitch_ms, factor × median of the last 60)` (defaults 50 ms and 3) becomes a
    `hitch` log event. The event carries what changed during that frame (pipeline compilations, objects, nodes,
    resources, orphans, static memory), the physics ticks, the route, and the log lines printed in it. It also names
    likely causes: pipeline/shader compilation, physics catch-up, scene/resource construction.
  - Example: Home → Fly is one 3.6 s frame, with "scene/resource construction (+1,482 objects, +64 MiB)".
- **Simulation watchpoints: `break`.**
  - `break expr="-s[2] < 2" wait=true` checks the expression before every flight tick (inputs: `session`, `sim`,
    `s`, `app`, singletons). It pauses at the exact tick it becomes true, logs a `break` event and returns the state.
  - It fires on each false → true entry. `once=true` removes it after one hit; `pause=false` only logs.
  - An expression that fails is removed with an event.
- **Errors: `logs --summary` and `run --fail-on-error`.**
  - The summary groups records whose texts differ only in numbers, with counts, first/last sequence and the
    script location.
  - `--fail-on-error` stops a repro script at the first line after which the engine logged an error.
- **Leaks: `objects` and `soak`.**
  - `objects` counts live nodes by class and script (internal children included), and orphan nodes by class, with
    samples. It also reports totals for objects, nodes, resources, orphans and static memory.
  - `baseline=true` saves the counts, and `diff=true` lists what changed since then.
  - `soak scenario.txt --cycles N` runs a script repeatedly. After warm-up it diffs every cycle against the first
    measured one, and reports counters that grow in every cycle and any new errors. It also prints process RSS from
    `/proc` on Linux.
- **Script CPU: `profile`.**
  - Launch with `--script-profile`. Read `profile seconds=20` (the last 20 s), or `profile since=<log_seq>` with the
    sequence `ping` gave before the action you want to measure. The engine prints a sample about every 1–3 s, so use
    windows of 20 s or more for a stable ranking.
  - Profile lines go to their own ring, so they never evict errors and warnings from `logs`.
  - It aggregates the engine's own profile prints (one frame per second) into functions sorted by self or total
    time per sample, with call counts.
  - Profiling adds overhead, and it attributes GDScript, not rendering.
- **Load phases: `timeline`.** Launch with `--verbose`, act, then run `timeline --hitch`: it keeps only the lines
  printed during the longest recorded hitch frame and lists the largest wall-time gaps between them (a resource load
  is a line under `--verbose`), with what had just finished. `--since <seq>` / `--until <seq>` choose any other
  window. The gaps name what finished before the time went, not the work inside it. This is the phase breakdown inside
  one long frame, where the script-profile samples miss it.
- **One-command regression pass: `smoke`.**
  - It runs its own headless session on its own port: `crawl` from Home, every scenario in
    `tools/debug/scenarios/*.txt` with `--fail-on-error`, a flight and `crawl` from its pause menu, a seeded
    `monkey`, a fly/Home `soak`, and the exit report.
  - Between steps it returns to a bare Home: it ends flights and the truck, closes dialogs and discards unsaved
    Workshop edits.
  - It prints one JSON verdict and exits 1 when any step failed or the engine crashed. It takes about 3.5 minutes
    on the VM.
  - Add a scenario file for every UI or flow bug you fix. Each must start and end at Home.
- **Random UI testing: `monkey`.**
  - It runs a seeded walk over the visible controls: presses, selects, slider values, close, and with `--keys` the
    vehicle's shortcuts.
  - It avoids labels that quit, delete or open a browser.
  - It stops at the first new engine error, or when the app stops answering. The trail is written as a replayable
    `run` script (`tmp/debug-bridge/monkey-<seed>.txt`), with the hitches attributed to the action before them
    ("slow after key F5: 73 ms…").
  - Refused actions are commented out of the trail, so a replay follows the same path. The verdict lists the
    route/screen pairs the walk `visited`.
- **Compiler warnings: `gdscript_warnings.py`.**
  - It opens every script in the pinned editor's language server, headless and on a snapshot of `app/` (the
    shared tree is never opened by an editor), and collects the engine's own errors and warnings with the project's
    settings.
  - `--baseline tools/debug/gdscript_warnings_baseline.json` fails only on warnings that are not in the baseline.
    The baseline is keyed by file, code and message, without line numbers.
  - `--write-baseline` refreshes the baseline after a reviewed change. `--files 'debug/*.gd'` narrows the run.

```sh
python3 tools/debug/gdscript_warnings.py --files 'debug/*.gd'          # one area, ~30 s
python3 tools/debug/gdscript_warnings.py --baseline tools/debug/gdscript_warnings_baseline.json
```

The first full pass took 672 s on the VM: 1,239 scripts, 0 errors, and 1,160 warnings, now the baseline. By code:

| Warnings | Code |
| --- | --- |
| 321 | `SHADOWED_GLOBAL_IDENTIFIER` |
| 245 | `SHADOWED_VARIABLE_BASE_CLASS` |
| 215 | `INTEGER_DIVISION` |
| 108 | `CONFUSABLE_LOCAL_DECLARATION` |
| 73 | `UNUSED_VARIABLE` |
| 58 | `INCOMPATIBLE_TERNARY` |
| 52 | `UNUSED_PARAMETER` |
| 43 | `SHADOWED_VARIABLE` |
| 63 | others |

The rarer, bug-shaped codes were reviewed:

- In production code, `UNASSIGNED_VARIABLE` (`rc_ground_material.gd`) and `CONFUSABLE_LOCAL_USAGE` (`app_root.gd`)
  are false positives. A typed object variable starts as null, and the shadowed property is not read afterwards.
- The test-only `INT_AS_ENUM_WITHOUT_MATCH` values are deliberate out-of-range inputs.
- No existing warning was fixed in bulk. Owners can work down the baseline.

The gate was checked both ways: a pass over 5 files against the baseline reports 0 new warnings, and removing one
key from a copy of the baseline makes the matching warning new (exit 1).

[gdlint](https://pypi.org/project/gdtoolkit/) 4.5.0 was evaluated and not adopted:

- On 1,239 scripts it reported 29,317 items. 27,817 were line length and 1,094 definition order.
- Its 3 "comparison with itself" findings were intentional determinism checks.
- It could not parse 9 files.

The engine's own warnings are the better signal.

## Recipes

These assume one session. When other agents share the machine, start each shell command with
`export OPENRC_DEBUG_BRIDGE=<your port>` (from `launch`'s output).

```sh
# Reproduce a bug as a script; it stops at the first failed command or assertion.
cat > tmp/repro.txt <<'EOF'
fly aircraft=gp-extra-300s-60 start=airborne
control name=camera_chase
sticks roll=1 for_s=0.5
wait until="flight.session.sim.tick > 480" timeout_s=300
assert expr="not flight.session.crash" message="still flying after the roll"
screenshot max_width=960
EOF
$D run tmp/repro.txt

# Telemetry while flying (CSV): height, ground speed, roll rate in deg/s.
$D watch --every 24 --count 50 --csv tmp/climb.csv h=-s[2] v="sqrt(s[3]*s[3]+s[4]*s[4]+s[5]*s[5])" p="rad_to_deg(s[10])"

# UI smoke test: every screen reachable here opens, lists its controls and closes back, with no new errors.
$D crawl --shots                     # from Home; after `fly`, it also crawls the pause menu's screens

# Change a setting the way a player does.
$D open screen=settings; $D ui; $D select text=WindowResolution item="1920 × 1080"; $D press text="Keep changes"

# Exact ticks around an event.
$D pause; $D step ticks=240; $D state

# Where does a stutter come from, and what costs script time?
$D launch --headless --script-profile          # note its port, then in each later shell command:
export OPENRC_DEBUG_BRIDGE=<port>
$D fly start=airborne; $D frames; $D wait seconds=25; $D profile seconds=20 top=15

# Stop at the tick something goes wrong.
$D break name=ground expr="-s[2] < 0.5" wait=true timeout_s=600; $D state; $D sample exprs={"h":"-s[2]"} count=1

# Leak check of any scenario, and a random UI walk.
printf 'fly start=airborne\nwait frames=30\nhome\n' > tmp/cycle.txt; $D soak tmp/cycle.txt --cycles 5
$D monkey --steps 300 --seed 42 --keys

# Discover and call anything.
$D methods node=AppRoot              # set_language(code), set_landscape(id), set_time_of_day(preset), …
$D call node=AppRoot method=set_landscape 'args=["green_paradise"]'
```

## How it works and limits

- **Activation.** `OPENRC_DEBUG_BRIDGE=1` (or a port; default 47870) makes `AppRoot` add
  `app/debug/debug_bridge.gd`. It listens only on `127.0.0.1`. Release export templates never open the socket
  (`OS.is_debug_build()`).
- **Protocol.** The bridge reads one JSON object per line and answers with one line (`{"id","ok","result"|"error"}`).
  `debugctl.py` opens one connection per command and needs only the Python standard library.
- **Invalid lines.** A line that is not such an object, or has a wrong token, gets one error and the connection
  closes. A web page can POST to `127.0.0.1`, and its HTTP request line closes the connection before the body could
  run.
- **Threads.**
  - A network thread owns the sockets and the JSONL file. It answers `help`, `ping`, `logs` and `state` at once, even
    while a slow frame renders.
  - `state` then comes from a snapshot published at most every 50 ms while a client is active. The snapshot is at most
    100 ms or one frame old, and the reply carries `snapshot_age_ms`. Every command reply invalidates the snapshot,
    so a `state` read after a command always sees that command's effect. Add `fresh=true` to read it on the main
    thread.
  - Every other command runs on the main thread at the start of the next frame. Replies are sent without blocking, so
    a client that stops reading cannot stall the game.
  - Screenshots are read back on the main thread, then scaled and encoded on a worker, which also sends the reply.
- **Environment variables.**
  - `OPENRC_DEBUG_TOKEN` requires a matching `token` field, compared in constant time. `launch` generates a fresh
    token per session and keeps it in `tmp/debug-bridge/current.json` (mode 0600), and the client sends it for that
    port.
  - `OPENRC_DEBUG_LOG` names the JSONL log.
  - `OPENRC_DEBUG_OUT` is the screenshot folder.
  - `OPENRC_GODOT` overrides the engine executable.
- **Logging.** A [Logger](https://docs.godotengine.org/en/stable/classes/class_logger.html)
  (`app/debug/debug_log.gd`) records every message.
- **Scope.** The bridge keeps running while the tree is paused. It never changes the launch route or project
  settings.

Limits:

- **It is not evidence of flight behaviour.** Sticks, keys and controller actions enter at frame boundaries. Use a
  [flight log](../../docs/FLIGHT-LOGGING.md) for exact replays. `step` is exact in ticks but bypasses the session's
  resume checks.
- **llvmpipe is slow.** It runs at about 1–2 fps at 1080p on the dev VM, and the simulation then runs at a fraction
  of real time (`state` → `realtime_factor`). Wait on simulation state (`until=flight.session.sim.tick > 2400`), not
  wall seconds.
- **Window resizes under Xvfb.** `window size=` resizes the OS window, but under Xvfb (no window manager) the
  viewport keeps its launch size and `window` says so. Use `launch --resolution`.
- **Coordinates.** A headless `--script` root window is 64×64, so mouse events outside it are ignored. `mouse`
  coordinates are window pixels (as in screenshots).
- **Some inputs cannot be emulated.** Radio and gamepad axes are not emulated: `sticks` replaces the keyboard sample,
  and `control` runs the same handlers a bound controller button runs. `pause`, `step` and `sticks` apply to flights;
  the truck has `drive` and its own garage pause.
- **`eval`, `call` and `set` can do anything**, and `screenshot path=` and `record path=` write where you tell them.
  They are debugging tools for your own machine, like the editor's remote tree, behind the per-session token.

## Performance

Measured on the Linux dev VM, 2026-10-24, with the median of 5 calls. The rendered runs used Xvfb, llvmpipe, Home at
1920×1080 and about 0.8 fps.

| Command | Before the network thread | After |
| --- | --- | --- |
| `ping`, `state`, `logs` | 1.1–1.2 s (one rendered frame) | 3–5 ms |
| `ui` | 1.2 s | 1.2 s (the next frame) |
| `key`, `wait frames=1` | not measured | 2.3–2.4 s (the next frame plus one settle frame) |
| `open` | 5.0 s | 2.4 s (one settle frame instead of three) |
| `screenshot` (960 px) | 2.8 s | 2.3–2.4 s (the encoder replies; the frame no longer stalls on PNG or JPEG work) |

Headless, every command takes about 7 ms. The bridge's own main-thread cost (`perf` → `bridge_usec`) was measured in
a headless flight at about 140 fps:

- 40 µs per frame with no client;
- 58 µs per frame while a client is active (226 µs before the 50 ms snapshot rate limit).

On a slow renderer, any command that touches the scene waits for frames. Use `--headless` whenever you do not need
pictures.

## Choice of design

No free tool fit a standalone Godot 4.7 game without the editor (research 2026-10-24):

- [godot-mcp-runtime](https://github.com/Erodenn/godot-mcp-runtime) (MIT) is the closest. It rewrites
  `project.godot` while it runs and needs Node.
- [satelliteoflove/godot-mcp](https://github.com/satelliteoflove/godot-mcp) needs the editor.
- [Coding-Solo/godot-mcp](https://github.com/Coding-Solo/godot-mcp) only launches the game and captures its output.
- [LimboConsole](https://github.com/limbonaut/limbo_console) and similar consoles are in-game UIs without remote
  access.
- GdUnit4's scene runner works only inside tests.

The bridge follows godot-mcp-runtime's pattern (loopback TCP, token, `PROCESS_MODE_ALWAYS`). It reads the existing
seams instead of adding hooks:

- the session keyboard reader, for sticks;
- the truck's `scripted_controls`;
- `ControlsReference`, the tested keyboard table;
- `ControllerActions`;
- the AppRoot screen openers;
- `Simulation.stop_at_tick`;
- the flight log.

Decision: [DECISIONS](../../docs/DECISIONS.md).

## Verification

```sh
python3 tools/godot/run_checked.py --timeout 90 --require-text 'all debug bridge checks passed' -- \
  "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy --script res://tests/test_debug_bridge.gd
python3 -m unittest discover -s tools/debug -p 'test_*.py'
```

**Bridge test.** `app/tests/test_debug_bridge.gd` runs in `app/test.sh`, with 69 checks. It talks real loopback TCP
to the bridge on a stand-in AppRoot. It covers:

- protocol errors and the token;
- log capture and state-change events;
- `eval`, `assert`, `find`, `get`, `set` and `call`;
- UI listing and `press`, including tiered labels and disabled buttons;
- `select` by item on an OptionButton, TabBar and PopupMenu;
- dialogs: OK and close/cancel through internal buttons;
- mouse clicks and key modifiers;
- `methods`, `shortcuts` and controller actions;
- the sticks override and its release;
- exact `step`, `resume` under a hold, and `wait` timeouts;
- `sample` rows and errors, and `perf`;
- the network thread answering `ping`, `state` and `logs` while the main thread is blocked for 800 ms;
- an old snapshot never served, and a `state` read right after a command showing that command's effect;
- an HTTP POST answered once and closed without running its body;
- bad stick values refused before anything is installed;
- `release=1` read as true;
- `set` on an unknown property and non-numeric arguments refused;
- `wait` timeouts reporting the last value;
- engine singletons in `eval` and a numeric key name;
- PT1h-R8 tools: a 150 ms frame becomes a `hitch` event and `frames` reports percentiles; a watchpoint pauses at the
  exact tick and `once` removes it; `logs` summary groups messages differing only in numbers; `objects diff` names 5
  new orphan `Node`s; `profile` parses the engine's profile format, and 5,000 profile lines evict no warning from
  the main log.

**Client tests.** These run in `research/test-tools.sh`, with 25 tests, mostly against a fake server. They cover:

- argument and JSON parsing, and quoted values that stay strings;
- the token, exit codes, and the `ui` table with its short paths;
- the remembered session port and token (sent only to that port), and `OPENRC_DEBUG_BRIDGE=1` not being read as a
  port;
- `stop` without a session, and `run` stop and `--keep-going`;
- `watch` CSV chunks, `crawl` passes and failures, and `clean`;
- the crash and leak exit report, using the engine's real output format;
- hitch attribution to the action before it, and seed-reproducible monkey actions;
- `gdscript_warnings.py` script selection and line-independent baseline keys;
- exclusive port claims with stale takeover, per-port tokens, `stop` refusing ambiguous targets, and zombie children
  counted as gone.

**Mutations.** On 2026-10-24, deliberate mutations on a disposable copy each failed exactly their check: no reader
re-assert, step off by one, token ignored, release no-op, no network-thread fast path, a stale snapshot accepted, no
snapshot invalidation on replies, and the log ring read from one sequence too late.

**Independent review.** A read-only review on 2026-10-24 found 11 issues, all fixed and covered above:

- browser POST injection;
- blocking sends;
- launch on the wrong port and orphaned engines;
- a per-frame log scan;
- numeric booleans;
- timed-out sample jobs;
- silent `call`/`set` failures;
- partial side effects;
- step and drive ending at frame boundaries;
- the truck's pause;
- several small items.

**Real app on the Linux dev VM** (Godot 4.7.2, Xvfb/llvmpipe and headless), 2026-10-24:

- Home → Settings listed and closed. `fly` started the P-51 airborne.
- `control name=gear_toggle` flipped the gear request. `control name=camera_chase` and `key name=Shift+C` changed
  views.
- `sample` and `record` (start, mark, stop) worked, and so did the wheel and the screenshot. `home` returned.
- The helicopter accepted arm and collective input. The MT8 drove 14 m with `drive` after `press text=drive`.
- `crawl`: 8 screens from Home and 8 from the flight's pause menu, with 0 failures and 0 errors. This held again
  after the network thread, once replies invalidated the snapshot: the first threaded build served a pre-`close`
  state, and `crawl` caught it.
- A nose-down dive crashed at tick 495 with `crashed`/`pause_reason` events. `ui` then showed only the accident
  report, and `press text="Restart flight"` restarted the flight.
- `set_landscape` switched Home to Green paradise. A settings resolution choice enabled Revert and Keep.
- `launch` at 1920×1080 gave 1920×1080 screenshots.

Not run on Windows or macOS.
