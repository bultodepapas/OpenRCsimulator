# Agent debug bridge (PT1h-R7)

On an enrolled shared host, [test-queue admission](../testqueue/README.md) owns launch
and teardown. Retain the returned `OPENRC_TESTQUEUE_HANDLE` on CLI commands; MCP
retains its own handle. A port or last-launch pointer alone cannot authorize control.
Managed MCP `sim_launch` returns when the queue accepts the request; if `ready` is
false, use `sim_session_status` to follow it and `sim_stop` to cancel it. Waiting or
disconnecting does not abandon ownership. General debug sessions are exclusive,
including headless ones, because their controls can start profiling or interactive
work. For independent aircraft stills, use the queue's `aircraft-screenshot` preset.
The standalone behavior below applies to unenrolled/private runners.

If a launch reply is lost before a handle arrives, MCP retains the recovery receipt.
Retry the same launch to recover it, inspect it with `sim_session_status`, or cancel
it with `sim_stop`. Status never creates a replacement session; stop also blocks a
delayed original submit. Different launch inputs are refused while unresolved.

Drive a **running** app from the shell, with no mouse and no editor. You can read its state and live log, use every
menu, setting, shortcut and controller action, fly with stick values or drive the RC truck, pause and step exact
physics ticks, sample telemetry, take screenshots, record flight logs and evaluate expressions. For independent
headless checks, agents can use [MCP checked batches](../testqueue/README.md#mcp-checked-batches), and shell users
can use the [checked runner](../godot/README.md). Claude Code and Codex find this tool through the
`openrc-debug` skill; the [tool index](../../docs/tools/README.md) routes every other task.

Contents: [agents and MCP](#agents-and-mcp-pt1h-r11) · [quick start](#quick-start) · [I want to…](#i-want-to) ·
[commands](#commands) ·
[stutter, leaks and bugs](#hunting-stutter-leaks-and-bugs-pt1h-r8) ·
[frame-pacing captures](#frame-pacing-and-stutter-captures-pt1h-r15) ·
[GPU cost and rewind](#gpu-cost-and-rewind-pt1h-r9) ·
[flight gizmos and BugIt](#flight-gizmos-and-bugit-pt1h-r10) · [recipes](#recipes) ·
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
| **See what is on screen and act (agents: start here)** | `$D look`, then `$D press ref=e7` / `$D choose ref=e9 value="1920 × 1080"` / `$D choose field="Text size" value=125%`; or the [MCP server](#agents-and-mcp-pt1h-r11) |
| Pick aircraft, start, landscape, time of day | `$D catalog` (valid ids), `$D setup aircraft=<id> start=airborne time_of_day=sunset`, then `$D fly` |
| Start / stop the app | `$D launch --headless` (no pictures, light) or `$D launch` (1920×1080 on the native display, with Xvfb only on displayless Linux); add `--import` after pulling new assets; `$D status`; `$D stop` (prints `"crash": null, "leaked_objects": 0` on a clean exit) |
| See what is on screen and click it | `$D ui`, `$D press text="Fly"`, `$D select text=Language item="Español"`, `$D close` |
| Open a menu or setting directly | `$D open screen=settings` (no screen: list them) |
| Fly, restart, go back | `$D fly aircraft=<id> start=airborne`, `$D restart`, `$D home` |
| Press keys and controller buttons | `$D shortcuts`, `$D key name=Shift+C`, `$D control name=gear_toggle` |
| Fly with stick values / drive the truck | `$D sticks pitch=0.3 throttle=0.8 for_s=2`, `$D drive throttle=0.6 for_s=1` |
| Read the state / the live log | `$D state`, `$D logs --follow`, `$D logs --summary` |
| Take a picture | `$D screenshot max_width=960 format=jpg` (not under `--headless`) |
| Pause, step, stop at a condition | `$D pause`, `$D step ticks=240`, `$D break expr="-s[2] < 1" wait=true` |
| Record values per tick | `$D watch --every 24 --csv tmp/w.csv h=-s[2]`, `$D record action=start` (flight log) |
| Find a stutter / FPS drop / slow load / hot script | `$D frames watch --out tmp/watch-01` catches intermittent drops, stutters and freezes automatically; `$D frames`; `$D frames --out tmp/stutter-01` saves HTML/CSV/Perfetto; `launch --verbose` + `$D timeline --stutter`; `launch --script-profile` + `$D profile seconds=20` |
| Inspect render costs | `$D render` (raw GPU/CPU observations, draw calls), `$D layers`, `$D ablate`, `$D viewmode name=overdraw` |
| Go back before a crash and try again | `$D rewind arm=true` before flying, then `$D rewind seconds=2` (`attempt=previous` after an auto-restart) |
| See the forces, velocities and wind on the aircraft | `$D gizmos show=all`, then `$D screenshot` |
| File a reproducible bug report / reopen one | `$D bugit --note "…"`; `$D bugitgo <folder>` |
| Find a leak | `$D soak scenario.txt --cycles 5`, `$D objects baseline=true` then `$D objects diff=true` |
| Find UI bugs | `$D crawl`, `$D monkey --steps 300 --seed 1 --keys` |
| Reproduce a bug as a script | write `tmp/repro.txt` (one command per line), `$D run tmp/repro.txt --fail-on-error` |
| Check everything before a commit | `$D smoke` (own session, about 3.5 min) |
| Any property or method | `$D methods node=AppRoot`, `$D get node=… prop=…`, `$D call …`, `$D eval expr="…"` |
| GDScript compiler warnings | `python3 tools/debug/gdscript_warnings.py --files 'area/*.gd'` |

## Agents and MCP (PT1h-R11)

The fastest way for a coding agent to drive the whole simulator: menus, options and flights. Design after
[Playwright MCP](https://playwright.dev/mcp/introduction): read an accessibility-style snapshot, act on its refs,
and read the next snapshot.

**The loop: `look`, then act.**

```text
$ debugctl.py look
# route home · screens ['home', 'settings'] · scope AppRoot/Settings · focus e2
e1            button   "Close"
e2            toggle   "Display" = true  focused
e9            option   "Window resolution" = "Automatic"  [Automatic | 1280 × 720 | … | 1920 × 1080 | …]
e10           option   "Text size" = "100%"  [100% | 125% | 150% | 175% | 200%]
> press ref=<ref> | choose ref=<ref> value=<v> (or field=/text= instead of ref=)
> close  (Esc/Back on the top dialog or menu)
$ debugctl.py choose ref=e9 value="1920 × 1080"      # or: choose field="Window resolution" value=…
$ debugctl.py press text="Keep changes"
```

- **`look`** lists, for every visible control of the top screen or dialog:
  - its **ref**;
  - its **role**: button, toggle, option, slider, number, text, tabs, list or progress;
  - its **name**: the app's accessible name, the one a screen reader announces. That is its `accessibility_name`, or
    the Label that [`ui/accessible_labels.gd`](../../app/ui/accessible_labels.gd) links to it, else the label just
    before it. The OptionButton that shows "Automatic" is therefore named "Window resolution". A symbol-only button
    is named by its tooltip or its parent (`× (Close · Wind)`);
  - its **value** and **options**, and whether it is disabled or focused.

  `look` also gives the route, the screens, a one-line flight summary and **next steps** for this situation.
  `look all=true` lists every layer.
- **Refs** (`e12`) are short, and a control keeps its ref for its lifetime: a ref from an earlier `look` still works
  while that control exists, and a freed one is refused with "run look again". `ref=` and `field=` work in
  `press`, `select`, `choose`, `type`, `focus`, `set_value` and `mouse`. Field names also match `text=`, after
  exact labels.
- **`choose`** is one verb for every widget. It takes an item label (option, tabs, list), on/off (toggle), a
  number (slider, spin box) or text (a text field; submitted unless `submit=false`). The change goes through the
  widget's own signals, as a player's would. A toggle that already has the value is left alone. A button is refused
  with the matching `press`.
- **`catalog`** lists the valid ids, so agents do not guess them: aircraft with the starts each supports,
  landscapes, time-of-day presets, languages, screens, camera views and the current Home selection.
- **`setup aircraft= start= landscape= time_of_day= language=`** changes Home choices.
  - All values are validated first; an invalid one changes nothing.
  - Each value is applied through AppRoot's setters, then read back. `differs` names any choice the app adjusted:
    the Vantage jet has no hand launch, so `start=hand_launch` came back `airborne`.
  - The AppRoot setters alone ignore invalid values silently.
- **`open screen=<…>`** inside a flight opens the pause menu first (the reply says `via: pause`), as a player
  reaches those screens.

**MCP server.** [`mcp_server.py`](mcp_server.py) exposes the simulator as typed tools: `sim_launch`, `sim_look`,
`sim_press`, `sim_choose`, `sim_close`, `sim_open`, `sim_catalog`, `sim_setup`, `sim_fly`, `sim_home`, `sim_state`,
`sim_sticks`, `sim_key`, `sim_screenshot` (an inline JPEG), `sim_bugit`, `sim_stop`, and `sim_command`, which reaches
any other bridge command.

- Actions that refresh the UI return their acknowledgement and a fresh snapshot. If only the refresh fails,
  the tool still succeeds. Its JSON text contains `acknowledged_result`, `failed_stage: "look"`, `detail`
  and `next_action`. Call `sim_look` to refresh after an acknowledged action.
- `sim_fly` with the default `ready=true` confirms the flight is unpaused. If flight creation succeeds and
  screen inspection, closing the launch menu or resuming then fails, the tool returns `isError=true` with
  the creation acknowledgement, failing stage and diagnostic. Use `sim_state` to inspect that flight.
  `ready=false` returns the initial flight state and leaves its launch menu and pause state alone.
- `sim_launch` points that server at its own session.

The same server exposes `sim_test_run` (launch and wait in one call), `sim_test_launch`,
`sim_test_status`, `sim_test_recover`, `sim_test_list` and `sim_fleet` (host availability)
for [automatic checked batches](../testqueue/README.md#mcp-checked-batches). These
use a durable request ID and do not need an interactive `sim_launch` session. Their
status and recovery are separate from interactive session handles and `sim_stop`.

The interactive bridge uses MCP over stdio, the standard library and `debugctl.py`.
Protocol intake and cached batch status can progress during an ordered simulator
call. Clients can supply `params._meta.progressToken` on an interactive tool request,
including `sim_stop`, to receive best-effort queued and executing notifications. The
executing notification marks the start of the tool call. Its final reply reports the
result. A slow reader can miss progress updates. [MCP progress format](https://modelcontextprotocol.io/specification/2025-11-25/basic/utilities/progress)

See the
[queue operating contract](../testqueue/README.md#mcp-checked-batches) for overload,
EOF reply loss, recovery IDs and observation limits.
The checked-batch tools also use the configured [test pool](../testqueue/README.md).

```sh
claude mcp add openrc-sim -- python3 tools/debug/mcp_server.py   # Claude Code; .mcp.json also declares it
# Codex (~/.codex/config.toml):  [mcp_servers.openrc-sim]  command = "python3"  args = ["tools/debug/mcp_server.py"]
```

A whole session, run against the real app on Windows through a stdio client:

1. `sim_launch` (headless) and the snapshot;
2. a refused `sim_press` (`isError`, with the reason);
3. `sim_setup` of the Extra 300S, airborne;
4. `sim_fly`, which ended flying at tick 24;
5. `sim_sticks`, `sim_command frames` and `sim_screenshot` (refused headless, with the reason);
6. `sim_home`, then `sim_stop` (launcher exit 0, 0 leaked objects).

## Quick start

From the repository root, Bash:

```sh
D="python3 tools/debug/debugctl.py"
$D launch                       # Home at 1920x1080 on the display (Xvfb on displayless Linux); prints the run folder
$D launch --mute                # the same without sound (Dummy audio driver); the MCP sim_launch is muted unless sound=true
$D look                         # every visible control: ref, role, name, value, options; next steps
$D fly aircraft=p51d-mustang-120 start=airborne
$D state                        # route, screens, focus; flight tick, pause/holds/crash, pose, commands, log counts,
                                #   physics_backend {backend, requested, kind: native|selected|domain|stale|missing}
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
- On Linux and Windows, `profile/` holds `user://` (preferences, flight logs, caches), so a session does not edit
  the player's settings. `--profile DIR` reuses a profile between launches. `--real-profile` uses the real one:
  Home's Fly then saves the selection like a person would. On macOS, Godot's `~/Library` user directory is not
  redirected by these environment variables; use an isolated project copy for Mac smoke until that path is verified.
  Mac smoke scenarios also assume fresh English preferences; the seeded monkey can persist another language.
  Preserve the isolated research profile and use a fresh one for another full smoke; never reset the player's profile.
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
- To launch a packaged app, set `OPENRC_GODOT` to its executable and use `launch --exported` (for example,
  `OPENRC_GODOT=/path/to/OpenRC.exe $D launch --exported --headless`). The package must use a Godot debug
  template: release templates disable the debug bridge. `--exported` does not accept `--app` or `--import`;
  the executable locates its packaged resources without a project path. A release executable cannot be detected
  before launch: the launcher stops it if the bridge does not answer by `--timeout`.
- `--script-profile` adds `-d --profiling --ignore-error-breaks`, so the engine prints its per-function GDScript
  profile about once a second (read it with `profile`). `--verbose` names each object leaked at exit.
- `stop` reports how the engine ended: `leaked_objects` / `leaked_instances` at exit, and a `crash` with its reason
  and GDScript backtrace, taken from `engine.log` (exit 1 after a crash). `status` shows the same when the app died.
  `launcher_exit_code` is numeric only when the current client owns and reaps the launcher; a separate CLI
  invocation reports null. An empty crash/leak log alone does not prove a zero OS exit status.
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
| Session | `launch`, `status`, `ready`, `stop [--force]`, `ping`, `quit`, `clean [--keep N]` (protects every tracked live run, including concurrent launches) |
| Routes | `fly aircraft=<id> start=<runway\|airborne\|…>` (from Home), `home`, `restart`; truck: `call node=AppRoot method=start_ground_vehicle args=["mt8-bisonte"]`, then `press text=drive` |
| Menus and settings | `look [all=true]`, `choose ref=\|field=\|text= value=`, `catalog`, `setup aircraft= start= landscape= time_of_day= language=`, `open screen=<…>` (no screen lists them), `close` (Esc/Back; never Home itself), `ui [all=true] [labels=true] [text=]`, `press text=\|path= [mode=signal]`, `select text=<OptionButton/TabBar/ItemList name or label> item=<label>\|index=`, `select popup=true item=` for an open PopupMenu, `set_value value=`, `type text= [into=<label or placeholder>] [submit=true]` (a dialog's field has its own focus), `focus`, `prefs` |
| Keys and controller | `shortcuts`; `key name=<C\|Shift+C\|F10\|Escape…> [action=tap\|press\|release] [hold_s=]`; `control [name=<action>] [hold=]` (the same handlers as a bound controller button); `action name=<input action>`; `mouse action=click\|double\|right\|move\|down\|up\|drag\|wheel x= y=` or `text=` |
| Pilot input | `sticks roll= pitch= yaw= throttle= [for_s=]` / `sticks release=true` (fixed wing, helicopter and FPV quad; the quad's throttle is the controller's virtual throttle share of the limited range, and E/M still arm and switch mode); `drive throttle= steering= brake= reverse= [for_s=]` / `drive release=true` (RC truck) |
| Time | `pause`, `resume`, `step ticks=<n>`, `rewind arm=\|list=\|seconds=\|tick= [attempt=] [pause=] [inputs=pilot\|recorded]`, `time_scale value=`, `wait frames=\|seconds=\|until=<expr> [timeout_s=]`, `break expr= [name=] [pause=] [once=] [wait=]` / `break list=true` / `break clear=<name\|all>` |
| Flight debugging | `gizmos [show=] [off=true] [auto_scale=] …`, `checkpoint action=save\|load path=`; client `bugit [--note] [--out]`, `bugitgo DIR [--resume]` |
| Render cost | `render [frames=] [measure=]`, `layers [depth=] [root=]`, `ablate [targets=] [depth=] [frames=] [warmup=] [freeze=]`, `viewmode [name=]` |
| Observe | `state`, `logs [--since N] [--level …] [--follow] [--summary]`, `frames` ([pacing and export options](#frame-pacing-and-stutter-captures-pt1h-r15)), `objects [baseline=] [diff=] [top=]`, `profile [since=] [top=] [sort=self\|total]`, `perf`, `screenshot [path=] [format=png\|jpg] [max_width=]` (JPEG at quality 85 is about 8× smaller for looking), `view [name=]`, `window [size=WxH] [mode=]`, `record action=start\|stop\|mark\|status` |
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

### Completion and recovery contracts

- `step ticks=N` succeeds only when that request reaches its exact target. An early pause, fault, reset,
  replaced simulation or changed stop boundary returns a failure with `progress` (`start_tick`, `target_tick`,
  `tick`; an unavailable current tick is `null`). Timeout or disconnect cancels the owned step and releases its
  stop. A pre-existing `stop_at_tick` is refused. A completed reply retains its own result if another step starts.
- Session claim changes use one persistent OS lock per sessions directory. Do not delete `.claims.lock` while
  clients run; all cooperating clients must use this version. `clean` preserves every live run and defers run
  deletion while a live launch has not published its output directory.
- Scenario, `.cleanup` and soak files are UTF-8. A `monkey` connection failure still writes its attempted-action
  trail and prints its path; exit status 2 distinguishes connection failure from a detected application error (1).
  A disconnected command may have reached the application, so the trail records the attempted action.
- Requests allow at most 1 MiB before the newline, whether delivered whole or in fragments. Numeric strings
  must convert to finite numbers. Queued commands from a peer already reported disconnected are discarded.

### Choosing a diagnostic

Closing the gaps in the [2026-10-24 review](../../docs/research/debug-tooling-gaps-2026-10-24.md):

- **Stutter: `frames`.** Every wall callback interval goes into a 7,200-frame ring. The
  [frame-pacing workflow below](#frame-pacing-and-stutter-captures-pt1h-r15) separates brief relative stutters,
  absolute stalls and sustained target-FPS overruns, with 1%/0.1% lows, raw samples and bounded event evidence.
  Pipeline, memory and scene counters are correlated observations; their freshness does not establish a cause.
- **Simulation watchpoints: `break`.**
  - `break expr="-s[2] < 2" wait=true` checks the expression before every flight tick (inputs: `session`, `sim`,
    `s`, `app`, singletons). It pauses at the exact tick it becomes true, logs a `break` event and returns the state.
  - It fires on each false → true entry. `once=true` removes it after one hit; `pause=false` only logs.
  - A paused flight is re-checked once per new tick, so a tick that pauses itself (a crash, a fault) or a `rewind`
    still triggers it at its own tick.
  - An expression that fails is removed with an event.
- **Errors: `logs --summary` and `run --fail-on-error`.**
  - The summary groups records whose texts differ only in numbers, with counts, first/last sequence and the
    script location.
  - `--fail-on-error` stops a repro script at the first line after which the engine logged an error.
  - A file run by `run` or `smoke` may have a sibling cleanup file: `scenario.txt` uses `scenario.cleanup`.
    After the main script succeeds or fails, every cleanup command is attempted, even if an earlier one fails.
    Cleanup failures are reported and fail the run; an existing main-script failure remains the result. The same
    `--fail-on-error` log checks apply to cleanup. Stdin has no cleanup file, and a cleanup file run directly does
    not execute itself twice. `soak` executes its lines directly and does **not** run sibling cleanup; use it only
    with scripts that restore their own state.
- **Leaks: `objects` and `soak`.**
  - `objects` counts live nodes by class and script (internal children included), and orphan nodes by class, with
    samples. It also reports totals for objects, nodes, resources, orphans and static memory.
  - `baseline=true` saves the counts, and `diff=true` lists what changed since then.
  - `soak scenario.txt --cycles N` runs a script repeatedly. After warm-up it diffs every cycle against the first
    measured one, and reports counters that grow in every cycle and any new errors. It also prints process RSS from
    `/proc` on Linux.
  - The `smoke` fly/Home scenario waits for deferred teardown and sweeps dead weak references from the
    shadow-lighting and cloud-shadow consumer registries before each census. These normally sweep every 64 new
    registrations, which can make a short soak report bounded bookkeeping as growth. Live references and
    zero-tolerance growth checks remain in scope; `soak` itself does not sweep caches. `test_shadow_settings.gd`
    and `test_cloud_shadow_map.gd` check the registries' ordinary bounds.
- **Script CPU: `profile`.**
  - Launch with `--script-profile`. Read `profile seconds=20` (the last 20 s), or `profile since=<log_seq>` with the
    sequence `ping` gave before the action you want to measure. The engine prints a sample about every 1–3 s, so use
    windows of 20 s or more for a stable ranking.
  - Profile lines go to their own ring, so they never evict errors and warnings from `logs`.
  - It aggregates the engine's own profile prints (one frame per second) into functions sorted by self or total
    time per sample, with call counts.
  - Profiling adds overhead, and it attributes GDScript, not rendering.
- **Load phases: `timeline`.** Launch with `--verbose`, act, then run `timeline --hitch`: it keeps only the lines
  printed during the longest retained hitch in the selected frame ring and lists the largest wall-time gaps between them (a resource load
  is a line under `--verbose`), with what had just finished. `--since <seq>` / `--until <seq>` choose any other
  window. The gaps name what finished before the time went, not the work inside it. This is the phase breakdown inside
  one long frame, where the script-profile samples miss it.
  `timeline --stutter` also includes the more sensitive relative-stutter and absolute-stall events. Both selectors
  ask for up to 200 retained details and use the event's log cursors; missing/evicted log lines remain unavailable.
- **One-command regression pass: `smoke`.**
  - It runs its own headless session on its own port: `crawl` from Home, every scenario in
    `tools/debug/scenarios/*.txt` with `--fail-on-error`, a flight and `crawl` from its pause menu, a seeded
    `monkey`, a fly/Home `soak`, and the exit report.
  - Before each scenario and the pause-menu test flight, it returns to a bare Home: it ends flights and the truck,
    closes dialogs and discards unsaved Workshop edits. A failed reset skips that dependent scenario and remains
    a failure in the verdict. It also resets Home after the random walk and soak.
  - It reaps its own launcher, including on macOS, and requires a confirmed zero exit code. Failed shutdown or
    forced cleanup remains a failure; missing exit/leak data stays null in the verdict.
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
    If comparison and refresh use the same path, the verdict still compares against its old keys. Outputs are
    UTF-8 and staged per file; source/project and report/baseline aliases are refused before launching the editor.
    Failed or incomplete scans preserve the baseline; filtered refreshes preserve keys for unselected files.
  - Each scan selects an available ephemeral port (`--port N` overrides it) and verifies that the accepted TCP
    connection belongs to its launched editor before sending source. Windows uses `netstat.exe`, Linux uses
    `/proc`, and macOS uses `/usr/sbin/lsof`; unavailable ownership evidence fails closed. Windows launches the
    editor beside the console wrapper directly so its PID identifies the socket. The editor is monitored during
    collection, missing diagnostics are tool failures (exit 2), and the owned process is stopped and reaped.
    `lsp-identity.json` beside `editor.log` records the executable, project, PID and verified connection on a
    completed collection. [Native follow-up and limits](../../docs/research/release-readiness/PT1h-R14/README.md#native-windows-integration-and-d14-follow-up-2026-11-08).

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

## Frame pacing and stutter captures (PT1h-R15)

Use a rendered 1920×1080 session on the target machine for performance investigation; a headless run checks
software behavior only. Set `OPENRC_DEBUG_BRIDGE` to the port of your owned session as described in
[Quick start](#quick-start). These commands change diagnostics settings, not the simulator's FPS cap or physics.

```sh
# Start a fresh measurement after reaching the flight/scene you want to investigate.
python3 tools/debug/debugctl.py frames target_fps=60 reset=true
# Fly normally; allow several seconds of steady flight and reproduce the problem.
python3 tools/debug/debugctl.py frames --out tmp/stutter-60fps-01
# Optional: inspect log gaps around the worst retained event (launch with --verbose).
python3 tools/debug/debugctl.py timeline --stutter
```

The destination must be new. Configure/reset in a separate command before reproducing the problem;
`frames --out` refuses policy/reset options before contacting the app, protecting the recorded history.
It takes **one bounded snapshot**, then creates `report.html`,
`frames.csv`, `frames.json`, `analysis.json` and `frames.perfetto.json` in the client process. Open the HTML for a timeline,
FPS lows, sustained slowdown episodes, worst frames and retained context. Its logarithmic vertical scale keeps smaller spikes visible beside
long loading stalls; switching it off gives a linear scale. Open the trace in [Perfetto](https://ui.perfetto.dev/)
for frame slices, counters, event markers and a separate over-budget episode track. Trace times use a local origin and do not align independent processes.
The snapshot includes the retained lead-up and recovery already observed; it does not wait for future frames.
At 60 FPS the full ring covers about two minutes; at 120 FPS, about one minute. Capture promptly after a problem.

For a summary without files, use `frames`; `window=600` selects the newest 600 available samples.
`frames samples=true events=200 --json` exposes the versioned `openrc-debug-frames v1` snapshot directly.
The typed MCP tool `sim_frames` exposes the same settings and observations. Empty captures cannot be exported;
wait for a complete interval after reset. Do not poll large raw snapshots every frame.

### Three independent signals

| Signal | Default rule | What it reveals |
| --- | --- | --- |
| Relative stutter | More than 1.5× the preceding median **and** more than 4 ms above it | A 33 ms interruption among 16 ms frames, or a 16.7 ms interruption among 8.3 ms frames |
| Absolute stall | More than 50 ms, independently of the adaptive baseline | Long frames even when the overall workload is already slow |
| Target-budget overrun | More than `1000 / target_fps + budget_tolerance_ms`; tolerance defaults to 0.5 ms | Persistent FPS drops and uneven pacing that a relative detector can adapt to |

Relative detection waits for eight preceding samples. Its upper median uses up to 60 previous samples,
refreshed every 15 frames; each event and raw sample retains the baseline used at that moment. This is a causal
live heuristic, not a reproduction of an offline surrounding-window algorithm or a universal perceptual threshold.
`stutter_factor`, `stutter_min_extra_ms`, `stall_ms`, `target_fps` and `budget_tolerance_ms` are configurable.
`budget_tolerance_ms=0` requests a strict budget comparison, which is sensitive to tiny timing jitter.

The older hitch condition remains `ms > max(hitch_ms, factor × baseline)`, with defaults 50 ms and 3.
Its `hitch` log events and report fields remain available alongside the more sensitive signals. No detector
proves a GPU bottleneck or counts actual dropped display frames.

### Statistics and scope

- FPS is measured frames divided by elapsed wall time. p50/p95/p99/p99.9 use nearest-rank frame-time percentiles.
- `fps_1pct_low` preserves the existing formula: `1000 / mean(slowest max(1, floor(N × .01)) durations in ms)`.
  `fps_01pct_low` uses `.001`. These are tail averages, not reciprocals of p99/p99.9. Reports include tail counts;
  windows below 100/1,000 samples are explicitly short. Even a one-frame tail is weak descriptive evidence.
- Budget reporting includes affected frame count/share, time occupied by slow frames, excess above the ideal
  budget, and the longest consecutive slow run (most frames, then greatest duration on ties).
  The run's frame count and duration describe the same episode. Slow-time share and excess time are different quantities.
- Adjacent-frame-change p95 and standard deviation make alternating fast/slow cadence visible even when a
  median-relative detector has adapted. Percentiles are percentages of samples, not percentages of elapsed time.
- `samples=true` returns chronological packed columns: exact monotonic end/duration microseconds, engine frame,
  physics ticks, baseline, flags, route at interval start, prior recorder cost and optional last-read GPU time.
  `first_sequence` identifies the first row; all rows and event details share one `epoch`/`capture_id`.
- Headless or zero/unavailable GPU readings remain unavailable. Positive readings retain **unverified freshness**.
  `source` reports a random nonsecret `launch_instance` (also in `ping`), `build_source`/`build_describe` and
  `runtime_revision`. A source-tree run reports `runtime_revision: not_observed`; only an exported build's embedded
  commit fills it. A client checkout is not assumed to identify the running app. `request_usec` is the engine clock
  while the request was handled, for later cross-process anchors.
- `since=<frames_total cursor>` returns only rows after a cursor (with `window` as a cap), `epoch=<n>` returns no
  rows when the cursor belongs to another epoch, and `lean=true` returns rows, cursor, identity and exact cumulative
  totals without summary work. `passive=true` keeps a poll from switching on 20 Hz `state` publishing. These exist
  for the [session watch](#automatic-session-watch-pt1h-r15-s2).

### Offline slowdown analysis (PT1h-R15-S3a)

The exporter groups maximal consecutive **recorded** over-budget flags. A stable
30-FPS callback cadence against a 60-FPS target can therefore appear as one long
budget episode even without relative-stutter or absolute-stall details. All rows,
including diagnostic queries and sampled route changes, stay in their original order.

`analysis.json` (`openrc-debug-frame-analysis v1`) adds episode sequence/time ranges,
observed duration, callback FPS, peak interval, sampled route changes and query
counts. It includes affected-frame share, slow-wall-time share, nominal-budget
excess, and IDs for the longest episodes by frame count and duration separately.
An episode's mean callback FPS is `frames / observed_seconds`; slow-time share is
`sum(flagged wall durations) / sum(all selected wall durations)`. Neither is a
presentation metric. Excess subtracts the ideal budget, not the tolerance threshold.

The default descriptive screen is **30 consecutive recorded slow frames**. Override
it locally with `sustained_frames=K` (integer 1–7,200) on an export. It is not sent
to the simulator, changes no flags, and is not a perceptual or fixed-duration rule.
`observed_sustained` means the retained run meets K. `full_episode_sustained` is
true for an observed qualifying run, false for a shorter run with both boundaries
observed, and null for a shorter run with an unobserved boundary. At a window edge,
including sequence 1, onset or recovery is unknown and length is a lower bound.
No result establishes absence of slowdowns outside the selected window.

The exact `wall_usec / 1000 > slow_threshold_ms` cross-check is diagnostic; it does
not rewrite original flags or tighten v1 import compatibility. Disagreements make
policy screening uncertain and total budget excess unavailable. JSON, HTML and
Perfetto retain this warning. The longest K-run screen complements slow-time and
tail statistics: 29 slow frames, one fast frame and another 29 slow frames do not
meet K=30, despite substantial slowdown. Routes describe interval-start samples;
the report does not infer exact transition timestamps or causes.

Rebuild a report from an existing raw snapshot without contacting a running app:

```sh
python3 tools/debug/debugctl.py frames --input tmp/stutter-60fps-01/frames.json --out tmp/stutter-review-02 sustained_frames=30
```

Offline input is UTF-8 JSON, capped at 16 MiB before decoding, then subject to the
existing v1 row/depth/text/continuity limits. Duplicate keys and non-finite numbers
are refused. Window/policy/reset options are refused; the destination must be new.
The input file stays unchanged. Exported `frames.json` preserves its JSON values,
not original whitespace/byte layout; `analysis.frames_json_sha256` binds the newly
written `frames.json` bytes. This hash is not runtime build or launch identity.

[GOD TEST](../godtest/README.md#measurements-and-reports) reduces its own verified
phase stream; native [frame diagnosis](../../docs/tools/graphics.md#frame-diagnosis)
uses fixed-duration `openrc-frametimes` evidence. Their thresholds, phase assignment
and completion contracts differ. Use the [integration map](../../docs/plans/stutter-diagnostics.md#existing-tool-integration)
before combining artifacts. Automatic lead-up/recovery collection is the [session watch](#automatic-session-watch-pt1h-r15-s2).

### Automatic session watch (PT1h-R15-S2)

Use the watch when a drop or stutter is intermittent and you do not know when it will happen. Start it, fly or
use the menus normally, and stop it with Ctrl+C (results are kept) or let `duration_s` end it:

```sh
python3 tools/debug/debugctl.py frames watch --out tmp/watch-01                  # 10 minutes, all triggers
python3 tools/debug/debugctl.py frames watch --out tmp/watch-02 duration_s=1800 target_fps=144 max_incidents=20
python3 tools/debug/debugctl.py frames watch --out tmp/watch-03 triggers=stall,drop,hang lead_frames=1200
```

It never resets or reconfigures the recorder, so another client's capture is undisturbed. Every 0.5 s it reads
only the new rows (`frames since=… lean=true passive=true`; about 0.3 ms of game-thread work for 30 rows on the
reference desktop), checks continuity and evaluates five triggers on the raw intervals:

| Trigger | Rule (defaults) | Catches |
| --- | --- | --- |
| `stall` | Bridge absolute-stall flag (> `stall_ms`, 50 ms) | Long single frames, loading hitches |
| `stutter` | Bridge relative-stutter flag (> 1.5× preceding median and > 4 ms above it) on an interval that also breaks the target budget; `stutter_min_ms=0` captures every flagged spike | Short hitches the eye sees. Uncapped spikes such as 13 ms after 8 ms frames stay counted, not captured |
| `sustained` | `sustained_frames=30` consecutive intervals above `1000/target_fps + tolerance`; re-arms after `rearm_frames=30` in-budget intervals | Running below the target |
| `drop` | Median interval of the last `drop_window_s=1` s is ≥ `drop_fraction=0.25` slower than the median of the preceding `drop_baseline_s=10` s on the same route, and ≥ `drop_min_ms=1` ms slower | FPS drops that stay above the target (140 → 75 FPS) |
| `hang` | A `frames` poll times out after `hang_s=2` s, `ping` answers, and a second ping 0.25 s later shows the same engine frame | Main-thread freezes; when it resumes, the long interval is also a `stall` |

`target_fps` here is the watcher's budget (default: the bridge's current target); it does not change the bridge.
After a start, route change, gap, new segment or a recovered drop, the drop detector ignores `drop_settle_s=2` s
of intervals and needs the 1 s window plus 3 s of baseline: it is blind for about 6 s (`drop_blind_s` in
`watch.json`). A slow gradual decline never triggers it. A refused or closed connection, or a slow poll while the
engine frame keeps advancing (`slow_polls`), is never a freeze. With `triggers=stutter` alone, a stall frame still
reports as a stutter. Triggers are screening rules, not perceptual thresholds or causes.

A trigger opens an **incident** with `lead_frames=600` rows before it; later triggers join it until
`recovery_frames=300` calm rows follow the last one (or `max_incident_frames=3600`). After `max_incidents=10`,
triggers are counted in `triggers_not_captured`. Output, in a new directory:

| File | Content |
| --- | --- |
| `report.html` | FPS per second for each segment with incidents shaded, per-route table (FPS, 1%/0.1% lows, p99, max, over-budget share, stutters, stalls), incident list with links |
| `watch.json` (`openrc-debug-frame-watch v1`) | Policy, identity, outcome, segments, per-route statistics, per-second series, gaps, freezes, incidents, reconciliation with bridge totals |
| `seconds.csv` | Per-second frames, FPS, worst interval, over-budget and stutter/stall counts |
| `incident-NNN/incident.json` (`openrc-debug-frame-incident v1`) | Triggers, lead/recovery coverage and every row of the incident from the polls |
| `incident-NNN/capture/` | One bounded `openrc-debug-frames v1` snapshot (`snapshot_rows=1200`; `0` disables it) exported as the usual `report.html`, `frames.csv`, `frames.json`, `analysis.json`, `frames.perfetto.json`, with the bridge's event context |

Interpretation and limits:

- Statistics are per **segment** (one epoch of one launch) and per **route**; menus, loading and flight are not
  pooled. A reset or policy change by another client starts a new segment that is read from its first row.
- 1%/0.1% lows are exact while the tail fits the 5,000 slowest retained intervals (about 500,000 frames for the 1%
  low); beyond that they are histogram estimates labelled `histogram_approximation`. Percentiles come from a
  histogram with 0.05 ms bins below 50 ms and 1 ms bins to 1 s.
- Whatever ends the watch (duration, Ctrl+C, lost bridge, a protocol error), `watch.json`, `report.html` and
  `seconds.csv` are written with the results so far; `outcome` and `error` say why it stopped. 16 MiB of
  `max_output_bytes` (default 256 MiB) stay reserved for them; incident captures stop before that. A capture of an
  incident longer than `snapshot_rows` holds its newest part (`capture_covers_first_trigger: false`); the
  incident's own rows file is complete.
- Rows recorded between the last poll and an epoch reset or process restart are not observed.
- Rows overwritten before a poll are counted in `gaps`; that segment's counts are lower bounds and its
  reconciliation reports `agrees: null`. Without gaps, watched stutter/stall/hitch counts must equal the bridge's
  cumulative deltas.
- A `hang` duration is a client-side lower bound. The bounded snapshot at incident close costs about 4–9 ms of
  game-thread work for 600–1,200 rows; the interval it perturbs is excluded from triggering
  (`observer_excluded_rows`). Polls still flag the following interval as `diagnostic_query`.
- `--json` prints a one-line machine summary. The watch needs the session's control ownership like any other
  live command; run it from a second shell or in the background while you fly.

### Retention, reset and observer effects

`hitch_total`, `relative_stutter_total`, `stall_total` and `event_total` count since the latest reset/policy change.
Window counts are separate. Each of the legacy-hitch and combined-event detail buffers holds at most 200 records;
their union can retain up to 400 distinct events. Counts of retained, returned, evicted and omitted details use
that union, without double-counting. `events` defaults to 20 and is capped at 200 per buffer.
New non-legacy details are limited to ten per second, with events larger than the previous retained event captured immediately;
new non-legacy log events are limited to one per second. Exact per-frame flags/counts are retained regardless.
Suppressed, evicted, returned and omitted details are reported separately. The HTML/trace still marks detected
frames with no retained detail. Raw frames overwritten by ring rollover cannot be recovered.

**Compatibility corrections:** old `hitch_total` saturated at 200; it is now the cumulative count, with
`hitch_retained` reporting storage. `hitches` and `stutters` now belong to the requested frame window; older session
events do not leak into a short-window report. The legacy aggregate `deltas.pipelines` remains available, while
separate canvas/mesh/surface/draw/specialization deltas distinguish foreground observations from background work.

Options are validated together before any mutation. A detector-policy change automatically starts a fresh epoch,
so one report cannot mix thresholds. Reset clears counters, median, clock, tick accumulator, event history and
monitor/log baselines; the next callback establishes a fresh origin, and the following complete interval is the
first sample. Concurrent clients should check the epoch/capture ID and avoid resetting each other's measurements.

Querying and JSON-encoding a large snapshot still does work on the game thread. The next interval carries flag
16 (`diagnostic_query`); it is preserved rather than silently subtracted. The capture's own final query affects a
later interval outside that snapshot. This flag indicates coincidence, not cause. `observer_mean_usec` and
`observer_max_usec` measure prior recorder work only; they exclude other bridge operations and detailed profiling.
Use script profiling for a targeted follow-up, not every ordinary flight.

Event context includes route transitions, available pause/focus state, physics catch-up, individual pipeline and
memory/object deltas, monitor CPU observations, raw GPU status and nearby log cursors. Godot monitors can lag, so
these observations guide the next experiment. For display pacing or GPU causality, correlate a controlled native
capture with PresentMon/Nsight or the platform profiler. A clean timing trace does not rule out interpolation,
camera or physics/render cadence jitter.

Research, decisions and software verification: [PT1h-R15 evidence](../../docs/research/release-readiness/PT1h-R15/README.md).

### Choose the next investigation

Preserve the five exported files first, then use the observed symptom to choose
one follow-up. Keep scenario, source/build, renderer/driver, cap/VSync/refresh,
output/internal resolution and cold/warm state with the report. A source-tree run
reports `runtime_revision: not_observed`; the checkout used by the client cannot
fill that gap. Capture in your owned session and keep any heavy profiling in a separate run.

| Observation | Next check | Interpretation limit |
| --- | --- | --- |
| Isolated spike or sustained slow frames | Inspect raw intervals, retained event context and `timeline --stutter`; reproduce the same action | A relative detector can adapt to sustained slowdown; retain budget episodes and maxima |
| Suspected script/physics work | Relaunch with `--script-profile`, reproduce, then use `profile`; inspect self and total ownership | Profiling perturbs timing; inclusive parent/child costs cannot be added |
| First-use/selection/Fly delay | Compare the same cold/first-use and warm route; inspect loading/pipeline context | Loading completion does not make scene attachment cheap; a counter change is not a duration |
| Suspected rendering cost | Use existing `render`/`ablate` and the supported engine profiler | Per-viewport GPU values are last readings with unverified freshness; overlapping work is not additive |
| Physics catch-up reported | Compare time-scale/pause state, physics work and render evidence | A rendering stall can also force catch-up; the count alone does not identify the cause |
| Motion looks jerky but callback pacing is stable | Review camera switches, reset/respawn and interpolation with a rendered recording | The frame detector cannot certify visual smoothness or input latency |
| Callback and visible presentation disagree | Optional PresentMon on Windows, MangoHud on Linux, or Instruments for native Metal; see linked applicability research | External clocks/metrics need their own identity and alignment; no automatic import/correlation is implemented |

**Pinned-engine caveats.** In Godot `4.8.beta2.official.cafc17a19`, process/physics
timing monitors publish periodic window maxima. They are not fresh CPU durations
for every observed frame. GLES3 timestamp collection reads older query results;
viewport getters expose stored durations without a source-frame ID. Toggling engine
measurement does not clear those durations. The current probe already guards the
disabled state; keep `unverified_freshness` after re-enabling or on sparse viewports.
Do not assume a fixed delay across OpenGL, Vulkan and Metal. Exact-source evidence
and external-tool constraints are in the [24-investigation follow-up](../../docs/research/release-readiness/PT1h-R15/research-2026-11-19.md).

Launcher-asserted source revisions, MCP access to the watch, loading/camera phase
markers and offline paired-run comparison are **proposed**. Their ownership and
acceptance checks live in the [implementation plan](../../docs/plans/stutter-diagnostics.md).
A permanent main-thread hang may leave only the last received capture and a client
timeout; an unreturned callback cannot supply a completed frame interval.

## GPU cost and rewind (PT1h-R9)

Research and the first Windows measurements: [debug tooling 2026-11-06](../../docs/research/debug-tooling-render-rewind-2026-11-06.md).

### Render cost (PT1h-R9)

These commands need a renderer: launch without `--headless`, on the target display and GPU. Results describe that
machine, renderer and view only.

- **`render [frames=30]`** reports root CPU render time, draw calls per pass, objects, primitives, wall frame time
  and render configuration. GPU timestamps are raw, delayed last readings: freshness and alignment to a sampled or
  presented frame are unverified. Zero, non-finite or absent readings are unavailable. The response's
  `gpu_timing_status` distinguishes unavailable, unverified and mixed readings; it does not establish a GPU/CPU
  bottleneck or budget headroom.
  - `gpu_ms` and `root_gpu_ms` are root-viewport observations (`gpu_ms_scope=root_only_freshness_unverified`).
    `sub_gpu_ms` sums separate last SubViewport readings and is **not** included in `gpu_ms`. A SubViewport may
    not have drawn for the sampled frame, so neither its last reading nor the sum is a per-frame cost.
  - `render measure=false` stops the bridge's own timestamp collection. Measurement is shared per viewport through
    [`render_timing_lease.gd`](../../app/render/render_timing_lease.gd): a `--frame-diagnostics` or GOD TEST
    observer of the same viewport keeps its timing until it stops, and the bridge releases its interest when it
    exits. When positive readings exist, `frames` reports root GPU percentiles as unverified last readings; a
    hitch's GPU reading is context, not a GPU-bound verdict.
  - `--json` retains the bridge's raw values and status fields. Responses from older bridges have unknown timing and
    scope semantics; the client labels them as legacy rather than upgrading them to the current contract.
- **`layers [depth=2] [root=<path>]`** is a census of the 3D scene below the active camera's top Node3D: visible
  geometry instances, MultiMesh instances, shadow casters and lights per node.
- **`ablate`** compares raw observations while switching one scene layer or feature off at a time:
  - It switches one target off, measures, restores it, and moves to the next. Targets are scene-root-relative node
    paths, or flags: `@shadows`, `@fog`, `@glow`, `@msaa`, `@half_res` (3D scale ×0.5: is the frame pixel-bound?),
    `@subviewports`, `@canvas`. `@half_res` is skipped with reason `non_bilinear_reconstruction` when the viewport
    uses a non-bilinear reconstruction mode; if it is the only target the command refuses with that reason.
    It does not replace that mode or silently change the player's settings.
  - Without `targets=`, it measures every flag, every top-level layer, and the children of any layer that holds a
    large share of the geometry. `targets=Field,airplane,@fog` (comma-separated or a JSON list) narrows it.
  - Measurement is interleaved A-B-A: baseline, target off, baseline, next target, …, baseline. Each raw delta is
    compared with the mean of its adjacent baselines. If any contributing phase has unavailable or mixed GPU
    readings, `saved_gpu_ms` and `saved_pct` are `null` and the client shows `n/a`; other observations and counters
    remain available. The timestamps may be stale, so a real-data delta is not proof of a saving, ranking,
    statistical significance, or cancellation of drift. Only synthetic test data can set `significant`; real rows
    report `false` and are not ranked by the unverified delta.
  - `overridden` means the app switched the target back on during its phase (for example a script that sets
    `visible` every frame). That row is not trustworthy.
  - Each phase discards `warmup=10` frames, then keeps `frames=60`. With `freeze=true` the probe attempts to hold the
    simulation, and refuses a hold if the flight's controller (radio or gamepad) is connected or a helicopter mode
    change is pending.
    `freeze=false` explicitly runs without a diagnostic hold. `paused_at_start` records the initial state; `frozen`
    means an owned simulation hold stayed valid. Neither establishes camera or visual stability. Target values are
    captured at phase start and restored only if they still have the probe's off value, preserving intervening
    changes; freed targets cannot be restored. Cleanup is attempted on completion, route change, timeout and
    disconnect. A later pause, focus loss, hold or session change prevents automatic resumption.
  - A target may also affect indirect work: hiding the aircraft can remove its projected-shadow silhouette pass.
    Use an external, synchronized GPU profiler and controlled repeated captures to establish causal costs.
- **`viewmode name=<mode>`** sets the viewport's debug draw. `viewmode` without a name lists the modes. In
  Compatibility, `overdraw` and `unshaded` work. `wireframe` covers only meshes created after it was set, so set it
  on Home and then fly. Most other modes need Forward+ or Mobile. Use `viewmode name=normal` to return.

### Rewind (PT1h-R9)

A ring of exact flight checkpoints for temporal debugging, after the rewindable-replay approach in Mark Wesley's
GDC 2013 talk.

- **`rewind arm=true [every_s=0.25] [keep_s=60]`** stores `FlightSession.checkpoint()` at a tick boundary every
  `every_s` while the flight runs. This is the boundary flight logs replay from. Each checkpoint costs about 0.5–0.6 ms
  on the main thread and 2.7 KB for the Ugly Stik. Arm it before the event you want to revisit.
- **`rewind seconds=2`** or **`rewind tick=<t>`** restores the newest checkpoint at or before that moment, through
  `FlightSession.restore_checkpoint()`:
  - Physics, inputs, weather, failures and contacts return bit-exactly. Two branches from one checkpoint, each
    stepped 480 ticks, gave identical state.
  - The presentation resets as on a restart: camera history, smoke and particles. A running flight log stops, and
    an accident report is archived.
  - The flight stays paused (`pause=false` resumes it).
  - The default `inputs=pilot` hands control back through `FlightSession.hand_control_to_pilot()`: the recorded
    throttle, centred sticks, still paused. `inputs=recorded` keeps the session's replay contract, which holds the
    restored inputs and ignores the pilot.
- **Attempts.** An accepted session reset or external restore starts a new attempt, including equal or increasing
  ticks. Repeated boundaries before another observation coalesce. `attempt=previous`
  (or a number) with `seconds=` counts back from that attempt's last checkpoint, which is the moment before the
  crash. `rewind list=true` shows the attempts.
- **The timeline is cut.** Restoring drops the later checkpoints of that attempt and every later attempt.
- **Retention.** The cadence is rounded to physics ticks. The ring keeps
  `ceil(keep_s * physics_hz / every_ticks) + 1` snapshots, capped at 100,000. The extra endpoint is necessary to
  span the requested duration; the cap can shorten it. Inspect the returned cadence, capacity and attempts.
  A paused flight and an active `step` do not capture: the latter owns a temporary stop boundary that must not
  enter a resumable checkpoint. A long step therefore leaves a history gap.
- **Limits.** It is a debugging tool, not evidence: pilot input after a rewind enters at frame boundaries. Exact,
  shareable replays use [flight logs](../../docs/FLIGHT-LOGGING.md). The checkpoint covers the player's aircraft
  only (no companions fleet). `rewind arm=false` frees the ring.

```sh
# Why did that landing end in a crash? Fly it again from 2 s before, by hand or with sticks.
$D rewind arm=true; $D fly start=runway
# ... fly until the crash (the accident report pauses the flight) ...
$D rewind seconds=2                          # paused, 2 s before; the crash is gone
$D sample exprs={"h":"-s[2]","sink":"s[5]"} every_ticks=24 count=10   # or step and inspect
$D resume; $D sticks pitch=0.4 throttle=1 for_s=1.5

# What costs the GPU in this view?
$D launch; $D fly start=airborne; $D close; $D resume
$D render; $D ablate; $D viewmode name=overdraw; $D screenshot max_width=960; $D viewmode name=normal
```

## Flight gizmos and BugIt (PT1h-R10)

### Flight gizmos (PT1h-R10)

`gizmos show=all` draws flight-model lines on the aircraft, in the style of X-Plane's flight-model display and the
force gizmos of avian_fdm and Unreal's Chaos vehicles. Screenshots then show what the physics is doing. The overlay
is read-only presentation: each frame it converts the session's committed state, loads and air data at the render
boundary (`render/frames.gd`), like the RC truck's contact overlay.

| Layer | Colour | Meaning |
| --- | --- | --- |
| `axes` | red, green, blue | body x forward, y right, z down |
| `velocity` | white | inertial velocity (0.1 m per m/s) |
| `air` | cyan | velocity through the air; its difference from `velocity` is the wind |
| `wind` | blue | wind at the aircraft |
| `forces` | yellow; orange; green; magenta | aerodynamic + propulsive force (1 m = the aircraft's weight); its component along the flight path (thrust − drag); its component across it (lift + side force); gravity |
| `moments` | purple | body moment as an equivalent lever arm, 10 × \|M\| / (m·g) |
| `trail` | white, fading | CG path over the last `trail_s=10` s; a restart or rewind starts a new path |
| `label` | — | V, α, β, load factor, height and tick |

- `show=forces,trail` picks layers. `gizmos off=true` removes the overlay. Settings stay in force across flights
  until `off`.
- The reply's `values` are this frame's numbers: airspeed, α, β, load factor, the forces along and across the
  path, wind speed, height and `arrow_scale`.
- Missing or nonfinite wind reports `wind_mps=null`, with no wind arrow; actual calm remains zero. Unavailable
  air data reports `airspeed_mps`, `alpha_deg`, `beta_deg`, `along_path_n` and `across_path_n` as `null`, omits their
  arrows and labels air data unavailable. Valid total force and gravity remain visible. Invalid poses clear stale
  values, and zero-length arrows create no empty mesh surface. Accepted resets/restores clear the trail.
- Load timing differs from air data: `Simulation.last_loads` is the previous step's RK4 k1 evaluation; air data
  uses the accepted state, and the display uses the current render pose. These are last-step diagnostics, not
  simultaneous endpoint force measurements. The overlay does not reevaluate or change the physics.
- `auto_scale=true` (the default) grows arrows with distance and zoom, so they stay readable from the pilot's
  ground camera (×5.9 at about 150 m). Lengths are then multiplied by `arrow_scale`. The label is not scaled.
  `force_m_per_g=`, `velocity_m_per_mps=`, `moment_gain=`, `trail_s=`, `axis_m=` and `thickness_m=` tune the
  drawing.
- Cost while shown: about 0.3–0.4 ms of main-thread time per frame with a 10 s trail. GL lines are one pixel wide,
  so each arrow is drawn as five parallel copies; the trail is drawn as one.
- Aircraft without the airplane's presentation estimate (`_current_pose`) are drawn at the tick state.
- Not shown: per-surface forces. The kernel exposes only total loads; see the
  [research note](../../docs/research/debug-tooling-render-rewind-2026-11-06.md#next-steps-not-built).

### BugIt and BugItGo (PT1h-R10)

After Unreal's `BugIt`/`BugItGo`: one command files a reproducible report, and another puts any running app back
into that exact flight.

- **`bugit [--note "what went wrong"] [--out DIR]`** writes `tmp/debug-bridge/bugit/<time>/`:
  - `REPORT.md`, a short summary: source revision and changed files, engine, route, flight pose, frame and render
    numbers, the detected GPU with Automatic's graphics choice and calibration, and the grouped errors and warnings;
  - `report.json`, every reading: state, perf, frames, the problems summary, the last 200 log records, render,
    objects, preferences, the `graphics_auto` report, rewind, view, gizmo values and git status;
  - `screenshot.jpg` (rendered sessions only);
  - `checkpoint.json`, the session's exact flight checkpoint (in flight).
  - Nothing is written into the repository.
- **`bugitgo DIR [--resume]`** restores that state:
  - it flies the same aircraft when needed and closes the launch menu;
  - `checkpoint action=load` restores the exact state, paused, with pilot inputs;
  - it sets the recorded camera view.
  - The session refuses a checkpoint whose aircraft data, field or weather differ: the report then names the
    configuration that must match. On Windows, a report taken at tick 799 was restored from Home in 2.6 s, and its
    state hash was identical.
- **`checkpoint action=save|load path=<absolute .json>`** is the bridge command underneath. A relative path is
  refused, because it would land in the Godot project. `save` without a path writes to the run folder.
- Saves write a short-named sibling and compare its exact UTF-8 bytes before publication; `bytes` counts encoded
  bytes. Existing destination symlinks continue to address their targets, and Unix mode bits are preserved.
  Cyclic/unresolvable links are refused. A short write preserves the prior checkpoint. An active step refuses save/load.
  Unix uses same-directory replacement. The pinned engine's Windows rename first removes an existing target,
  so the bridge keeps a verified recovery copy until publication succeeds and attempts rollback on failure.
  A failed rollback reports the recovery path; successful publication with failed backup cleanup returns
  `recovery_copy`. This is not a crash-durability guarantee. Windows rollback still needs native qualification.
- Use `bugit` when a bug shows up during any session, and attach the folder, not a description of how to get there.
  For an exact replay of a whole flight, record a [flight log](../../docs/FLIGHT-LOGGING.md).

```sh
$D gizmos show=all; $D view name=chase; $D screenshot max_width=1280 format=jpg
$D bugit --note "left wing drops at touchdown"   # prints the folder and the bugitgo line
# later, in any running app:
$D bugitgo tmp/debug-bridge/bugit/20261106-093916 --resume
```

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
- **`eval`, `call` and `set` can do anything**, and `screenshot path=` and `record path=` write where you tell them. A relative `path=` resolves against the Godot project (`app/`), which git does not ignore; omit it (shots go to the run folder) or pass an absolute path under `tmp/`.
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

**Bridge test.** `app/tests/test_debug_bridge.gd` runs in `app/test.sh`, with 114 checks. It talks real loopback TCP
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
- PT1h-R9: the rewind ring (a checkpoint every n ticks, `tick=`, the timeline cut, `inputs=pilot|recorded`, a clock
  reset starting a new attempt, `attempt=previous`, refused old ticks); a watchpoint on a tick that pauses itself;
  `render`/`ablate` refused headless; `viewmode` modes; the `layers` census; and the A-B-A ablation against a fake
  probe with linear drift (exact 0.5 ms saving, inert target insignificant, overridden target flagged, everything
  restored, abort restores).
- PT1h-R10: checkpoint files (relative path refused, save then load restores the tick paused with pilot inputs,
  missing file refused); gizmo numbers against hand values (load factor, along-path force, wind, α), lines and
  label drawn, nothing drawn when nothing is shown; the `gizmos` command's refusals and `off`.
- PT1h-R11: `look` fields, roles, values and options, symbol-only buttons named by context, next steps; refs short,
  stable across looks and refused once freed; `choose` for option, toggle (once), text and slider, refusing a
  button and a missing value; field names as `text=`; `setup` refused outside Home; `catalog` ids.
- The test listens on a random free port. With the former fixed port 47911, a concurrent run of the same test by
  another agent on the same Windows machine (two loopback listeners may share a port there) answered some
  requests. That caused the intermittent failures first blamed on load, including `blocked frame` and
  `old snapshot`.

**Additional contract regressions (PT1h-R14).** `test_debug_bridge_contracts.gd` checks framing over loopback TCP,
finite numbers, dropped requests, retained time span and checkpoint output. `test_debug_step.gd` checks job ownership,
completion and cancellation. `test_debug_observers.gd` checks reset boundaries, unavailable data, geometry and log
cursors. Run each through the checked runner, as above; `app/test.sh` discovers them automatically. The
[internal-debug review](../../docs/research/release-readiness/PT1h-R14/README.md) records exact source identities,
fixture boundaries and the separate file-size-limit reproduction. Tests with stand-in sessions do not qualify
full flight, rendering or physical behavior.

**Client tests.** These run in `research/test-tools.sh`, mostly against a fake server. They cover:

- argument and JSON parsing, and quoted values that stay strings;
- the token, exit codes, and the `ui` table with its short paths;
- the remembered session port and token (sent only to that port), and `OPENRC_DEBUG_BRIDGE=1` not being read as a
  port;
- `stop` without a session; `run` stop, `--keep-going`, and failure-safe sibling cleanup;
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

Not run on Windows or macOS for PT1h-R7/R8. PT1h-R9 on Windows 11 (RTX 3090, Godot 4.8 beta2, Compatibility,
1920×1080) is recorded in the [2026-11-06 research note](../../docs/research/debug-tooling-render-rewind-2026-11-06.md).
