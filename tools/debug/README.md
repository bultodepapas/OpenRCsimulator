# Agent debug bridge (PT1h-R7)

Drive a **running** app from the shell, with no mouse and no editor. You can read its state and live log, use every
menu, setting, shortcut and controller action, fly with stick values or drive the RC truck, pause and step exact
physics ticks, sample telemetry, take screenshots, record flight logs and evaluate expressions. For batch checks of
one script, use the [checked runner](../godot/README.md) instead. Claude Code and Codex find this tool through the
`openrc-debug` skill.

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
- The port comes from `OPENRC_DEBUG_BRIDGE`, else the last launch (`tmp/debug-bridge/current.json`), else 47870.
  A busy 47870 makes `launch` pick a free port. `status` tells whether the app is alive. `stop` waits for the process
  to exit; `stop --force` kills it.
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
| Menus and settings | `open screen=<…>` (no screen lists them), `close` (Esc/Back; never Home itself), `ui [all=true] [labels=true] [text=]`, `press text=\|path= [mode=signal]`, `select text=<OptionButton/TabBar/ItemList name or label> item=<label>\|index=`, `select popup=true item=` for an open PopupMenu, `set_value value=`, `type text= [submit=true]`, `focus`, `prefs` |
| Keys and controller | `shortcuts`; `key name=<C\|Shift+C\|F10\|Escape…> [action=tap\|press\|release] [hold_s=]`; `control [name=<action>] [hold=]` (the same handlers as a bound controller button); `action name=<input action>`; `mouse action=click\|double\|right\|move\|down\|up\|drag\|wheel x= y=` or `text=` |
| Pilot input | `sticks roll= pitch= yaw= throttle= [for_s=]` / `sticks release=true` (fixed wing and helicopter); `drive throttle= steering= brake= reverse= [for_s=]` / `drive release=true` (RC truck) |
| Time | `pause`, `resume`, `step ticks=<n>`, `time_scale value=`, `wait frames=\|seconds=\|until=<expr> [timeout_s=]` |
| Observe | `state`, `logs [--since N] [--level …] [--follow]`, `perf`, `screenshot [path=] [format=png\|jpg] [max_width=]` (JPEG at quality 85 is about 8× smaller for looking), `view [name=]`, `window [size=WxH] [mode=]`, `record action=start\|stop\|mark\|status` |
| Telemetry | `sample exprs={"h":"-s[2]"} every_ticks= count=` (rows per simulation tick); client `watch [--every N] [--count N] [--csv FILE] h=-s[2] …` streams CSV |
| Introspection | `methods node=<path>`, `find name=<glob> type=<class>`, `get node= [prop=]`, `set node= prop= value=`, `call node= method= args=[…]`, `eval expr= [node=]`, `assert expr= [message=]`, `nodes path= depth=` |
| Scripts | `run FILE\|- [--keep-going]`, `repl`, `crawl [--shots]` |

Notes on the commands:

- **Labels.** `press`, `select` and the other label lookups try, in order: the exact label, the label without its key
  hint (`DRIVE · Enter`), the node name, a label prefix, then a substring. A tie is refused and the candidate paths
  are listed. Generated paths (`@VBoxContainer@95`) change between runs, so scripts should use labels.
- **Expressions.** Expressions are Godot [Expression](https://docs.godotengine.org/en/stable/classes/class_expression.html)s.
  - `eval`, `assert` and `wait` run on AppRoot, with the inputs `app`, `tree` and `bridge`. Examples:
    `flight.session.sim.tick` and `flight._rig.set_view("chase")`.
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

## Recipes

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

**Bridge test.** `app/tests/test_debug_bridge.gd` runs in `app/test.sh`, with 58 checks. It talks real loopback TCP
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
- `wait` timeouts reporting the last value.

**Client tests.** These run in `research/test-tools.sh`, with 15 tests against a fake server. They cover argument and
JSON parsing, the token, exit codes, the `ui` table and its short paths, the remembered session port and token (sent
only to that port), `OPENRC_DEBUG_BRIDGE=1` not being read as a port, `stop` without a session, `run` stop and
`--keep-going`, `watch` CSV chunks, `crawl` passes and failures, and `clean`.

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
