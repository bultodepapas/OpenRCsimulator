# Agent debug bridge (PT1h-R7)

Drive a **running** app from the shell: read its state and live log, navigate menus by label, press keys, fly with
stick values, pause and step exact physics ticks, take screenshots and evaluate expressions. No mouse, no editor.
For batch checks of one script use the [checked runner](../godot/README.md) instead.

## Quick start

From the repository root, Bash:

```sh
D="python3 tools/debug/debugctl.py"
$D launch                      # Home under Xvfb (or your display); prints the run folder and pid
$D ui                          # visible controls of the top screen; * marks keyboard focus
$D press text=Fly              # like Enter on that button
$D wait 'until=flight != null and flight.session != null' timeout_s=150
$D state                       # route, screens, focus; flight tick, pause/holds/crash, pose, commands
$D sticks pitch=0.3 throttle=0.8 for_s=2
$D screenshot max_width=960    # prints the PNG path; open it with an image viewer or the Read tool
$D logs --level error,warning,script_error
$D stop
```

`launch -- --quick-flight` (any arguments after `--`) takes the direct flight route instead of Home, as
`--path app -- <args>` always does. `launch --headless` runs without a renderer: everything except screenshots works
and it is lighter. Each launch writes `tmp/debug-bridge/<time>/` with `engine.log` (stdout/stderr), `log.jsonl` (one
flushed record per line: `tail -f` works) and `launch.json`. Run one full-world app at a time on the shared VM
(about 2–3 GB RSS).

## Commands

`$D help` prints the live list. Arguments are `key=value`; values are JSON when they parse (`true`, `0.4`), otherwise
strings. Output is compact JSON (`--pretty` indents; `ui` prints a table, `--json` gives its JSON). Exit status: 0 ok,
1 the bridge refused (message on stderr), 2 usage or connection error.

| Command | Use |
| --- | --- |
| `state`, `ping` | Snapshot; liveness. Flight pose is NED metres, body velocity, Euler degrees (roll, pitch, heading) and body rates. |
| `logs since=<seq> level=<list>` / `logs --follow` | Engine and script records after a cursor (`info`, `stderr`, `warning`, `error`, `script_error`, `shader_error`), with the GDScript location of `push_error`/`push_warning`. The ring holds 4,000 records. |
| `ui [all=true] [labels=true] [text=<s>]` | Buttons, edits, ranges, lists and tabs of the top menu screen (`all` = whole tree). |
| `press text=<label>\|path=<node> [mode=signal]` | Focus plus `ui_accept`, as the keyboard does; `mode=signal` emits `pressed` for unfocusable buttons. Exact label first, then a unique substring. |
| `focus`, `type text=<s> [submit=true]`, `select index=<i>`, `set_value value=<v>` | Focus, LineEdit/TextEdit text, OptionButton/ItemList choice, slider/spin value. |
| `key name=<W\|Escape\|F2\|Up…> [action=tap\|press\|release] [hold_s=<s>]`, `action name=<input action>` | Real input events: menus, shortcuts and the flight keys (`press` holds until `release`). |
| `sticks roll= pitch= yaw= throttle= [for_s=<s>]`, `sticks release=true` | Replace the keyboard sample: roll/pitch/yaw −1…1 (pitch + is stick back, nose up), throttle is a 0…1 target reached at the keyboard throttle rate. `for_s` counts simulation time. A connected radio/gamepad still flies instead. |
| `pause`, `resume`, `step ticks=<n>` | Freeze the simulation; the pilot's continue (refused, with the reason, during menus, crash or calibration); advance a paused flight exactly n ticks. |
| `time_scale value=<x>`, `wait frames=\|seconds=\|until=<expr>` | Engine time scale; wait for frames, wall seconds or an expression. |
| `screenshot [path=<png>] [max_width=<px>]` | Viewport after the next drawn frame. Default path under the app's `user://debug_bridge/`. |
| `eval expr=<expression> [node=<path>]`, `nodes path=<node> depth=<n>` | Godot [Expression](https://docs.godotengine.org/en/stable/classes/class_expression.html) on AppRoot (inputs `app`, `tree`, `bridge`; e.g. `flight.session.sim.tick`, `flight._rig.set_view("chase")`); scene outline. |
| `quit code=<n>` (`stop`) | Quit after replying. |

## How it works and limits

`OPENRC_DEBUG_BRIDGE=1` (or a port; default 47870) makes `AppRoot` add `app/debug/debug_bridge.gd`. It listens only
on `127.0.0.1`, reads one JSON object per line and answers one line (`{"id","ok","result"|"error"}`); `debugctl.py`
opens one connection per command and needs only the Python standard library. `OPENRC_DEBUG_TOKEN` requires a matching
`token` field; `OPENRC_DEBUG_LOG` names the JSONL log. Release export templates never open the socket
(`OS.is_debug_build()`). A [Logger](https://docs.godotengine.org/en/stable/classes/class_logger.html)
(`app/debug/debug_log.gd`) records every message.
The bridge runs while the tree is paused and never changes the launch route or project settings.

- **It is not evidence of flight behaviour.** Sticks and keys enter at frame boundaries; use a
  [flight log](../../docs/FLIGHT-LOGGING.md) for exact replays. `step` is exact in ticks but bypasses the session's
  resume checks (menus, crash), and stepping forces the simulation's `stop_at_tick`.
- **The Home route uses the player's real `user://` preferences**: pressing Fly saves the selection like a person would.
- **llvmpipe is slow** (about 2 fps at 1280×720 on the dev VM, the simulation then runs at a fraction of real time).
  Wait on simulation state (`until=flight.session.sim.tick > 2400`) rather than wall seconds.
- `eval` can call any method; it is a debugging tool for your own machine, like the Godot editor's remote tree.
- The Home and pause menus are reachable; dialogs built outside the screen stack need `ui all=true`.

## Choice of design

No free tool fit a standalone Godot 4.7 game without the editor (research 2026-10-24):
[godot-mcp-runtime](https://github.com/Erodenn/godot-mcp-runtime) (MIT) is closest but rewrites `project.godot` and
needs Node; [satelliteoflove/godot-mcp](https://github.com/satelliteoflove/godot-mcp) needs the editor;
[Coding-Solo/godot-mcp](https://github.com/Coding-Solo/godot-mcp) only launches and captures output;
[LimboConsole](https://github.com/limbonaut/limbo_console) and similar are in-game UIs without remote access;
GdUnit4's scene runner is test-time only. The bridge follows godot-mcp-runtime's pattern (loopback TCP, token,
`PROCESS_MODE_ALWAYS`) in about 860 lines of GDScript and a 210-line client. Decision: [DECISIONS](../../docs/DECISIONS.md).

## Verification

```sh
python3 tools/godot/run_checked.py --timeout 90 --require-text 'all debug bridge checks passed' -- \
  "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy --script res://tests/test_debug_bridge.gd
python3 -m unittest discover -s tools/debug -p 'test_*.py'
```

`app/tests/test_debug_bridge.gd` (in `app/test.sh`) talks real loopback TCP to the bridge on a stand-in AppRoot:
protocol errors, token, log capture with script location, eval, UI listing/press/disabled/set_value, the sticks
override surviving a re-installed keyboard reader and its release, exact step, resume refusal under a hold, and wait
timeouts. The client tests (in `research/test-tools.sh`) use a fake server. Verified 2026-10-24 on the Linux dev VM,
Godot 4.7.2: 25/25 checks five times in a row; deliberate mutations on a disposable copy (no reader re-assert, step
off by one, token ignored, release no-op) each failed exactly their check. Real app under Xvfb/llvmpipe: Home → `press
text=Fly` → flight; `sticks` raised the HUD throttle to 42 %; `pause`/`step ticks=240` advanced 852 → 1092;
Escape → pause menu table → `press text=Resume`; screenshot 960×540; `logs` and `log.jsonl` carried a script error
with its location; the `--quick-flight` route behaved the same. Not run on Windows or macOS.
