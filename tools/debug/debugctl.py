#!/usr/bin/env python3
"""Drive a running OpenRC app through its debug bridge (PT1h-R7). Standard library only.

  debugctl.py launch [--headless] [--resolution WxH] [--port N] [--out DIR] [--profile DIR | --real-profile] [-- <app args>]
                                                                           start the app with the bridge; wait until ready
  debugctl.py status | ready [--timeout S] | stop [--force]                session: alive?, wait for it, quit it
  debugctl.py logs [--since N] [--level error,warning] [--follow]          engine/script log and state-change events
  debugctl.py watch [--every TICKS] [--count N] [--csv FILE] name=expr ... live values every n simulation ticks
  debugctl.py run FILE|- [--keep-going]                                    a repro script: one command per line
  debugctl.py crawl [--shots]                                              open/list/close every screen here; report errors
  debugctl.py clean [--keep N]                                             delete old run folders (default keep 3; never a live one)
  debugctl.py repl                                                         interactive prompt (same syntax)
  debugctl.py <command> [key=value ...] [--pretty|--json]                  any bridge command; `help` lists them

Values are JSON when they parse (true, 3, 0.5, [1,2], {"a":"b"}), else strings. One TCP connection per call.
The port comes from OPENRC_DEBUG_BRIDGE, else the last `launch` (tmp/debug-bridge/current.json), else 47870.
OPENRC_GODOT names the engine executable (default: app/get-godot.sh).
Exit status: 0 ok, 1 the bridge refused or an assertion failed, 2 usage or connection error.
Guide: tools/debug/README.md.
"""
from __future__ import annotations

import csv
import datetime
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path

DEFAULT_PORT = 47870
REPO = Path(__file__).resolve().parents[2]
RUNS = REPO / "tmp" / "debug-bridge"
CURRENT = RUNS / "current.json"


class Refused(Exception):
    """The bridge answered ok=false."""


def current_session() -> dict:
    try:
        return json.loads(CURRENT.read_text())
    except (OSError, ValueError):
        return {}


def port() -> int:
    value = os.environ.get("OPENRC_DEBUG_BRIDGE", "")
    if value.isdigit() and int(value) > 1:
        return int(value)
    return int(current_session().get("port", DEFAULT_PORT))


def parse_value(text: str):
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return text


def parse_args(items: list[str]) -> dict:
    args = {}
    for item in items:
        if "=" not in item:
            raise ValueError(f"expected key=value, got '{item}'")
        key, value = item.split("=", 1)
        args[key] = parse_value(value)
    return args


def request(cmd: str, args: dict | None = None, timeout: float = 900.0, to_port: int | None = None) -> dict:
    payload = {"id": 1, "cmd": cmd, **(args or {})}
    token = os.environ.get("OPENRC_DEBUG_TOKEN")
    if token:
        payload["token"] = token
    with socket.create_connection(("127.0.0.1", to_port or port()), timeout=timeout) as conn:
        conn.sendall((json.dumps(payload) + "\n").encode())
        data = b""
        while not data.endswith(b"\n"):
            chunk = conn.recv(65536)
            if not chunk:
                break
            data += chunk
    if not data:
        raise ConnectionError("the bridge closed the connection without a reply")
    return json.loads(data)


def result_of(cmd: str, args: dict | None = None, **kwargs):
    reply = request(cmd, args, **kwargs)
    if not reply.get("ok"):
        raise Refused(reply.get("error", "refused"))
    return reply.get("result")


def wait_ready(timeout: float, process: subprocess.Popen | None = None, to_port: int | None = None) -> dict:
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        if process is not None and process.poll() is not None:
            raise RuntimeError(f"the app exited with status {process.returncode} before the bridge answered")
        try:
            return request("ping", timeout=2.0, to_port=to_port)
        except OSError as error:
            last = error
            time.sleep(0.25)
    raise TimeoutError(f"no bridge on 127.0.0.1:{to_port or port()} after {timeout:.0f} s ({last})")


def port_free(number: int) -> bool:
    with socket.socket() as probe:
        return probe.connect_ex(("127.0.0.1", number)) != 0


def free_port() -> int:
    with socket.create_server(("127.0.0.1", 0)) as server:
        return server.getsockname()[1]


def alive(pid: int | None) -> bool:
    if not pid:
        return False
    if os.name == "nt":  # os.kill(pid, 0) would terminate the process on Windows
        import ctypes
        handle = ctypes.windll.kernel32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
        if not handle:
            return False
        code = ctypes.c_ulong()
        ctypes.windll.kernel32.GetExitCodeProcess(handle, ctypes.byref(code))
        ctypes.windll.kernel32.CloseHandle(handle)
        return code.value == 259  # STILL_ACTIVE
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def godot() -> str:
    if os.environ.get("OPENRC_GODOT"):
        return os.environ["OPENRC_GODOT"]
    return subprocess.run([str(REPO / "app" / "get-godot.sh")], check=True, capture_output=True, text=True).stdout.strip()


def launch(argv: list[str]) -> int:
    app_args: list[str] = []
    if "--" in argv:
        split = argv.index("--")
        argv, app_args = argv[:split], argv[split + 1:]
    headless = "--headless" in argv
    # Rendered sessions open at 1920x1080, the primary display target (AGENTS.md); --resolution 1280x720 is faster.
    options = {"--out": None, "--timeout": "180", "--port": None, "--profile": None, "--resolution": "1920x1080"}
    for i, arg in enumerate(argv):
        if arg in options and i + 1 < len(argv):
            options[arg] = argv[i + 1]
    if options["--port"]:
        chosen = int(options["--port"])
    elif "OPENRC_DEBUG_BRIDGE" in os.environ and os.environ["OPENRC_DEBUG_BRIDGE"].isdigit():
        chosen = int(os.environ["OPENRC_DEBUG_BRIDGE"])
    else:
        chosen = DEFAULT_PORT if port_free(DEFAULT_PORT) else free_port()
    if not port_free(chosen):
        print(f"port {chosen} is in use (another app?): `debugctl.py stop` it or pass --port", file=sys.stderr)
        return 2
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    out = Path(options["--out"]).resolve() if options["--out"] else RUNS / f"{stamp}-{chosen}"
    out.mkdir(parents=True, exist_ok=False)
    command = [godot(), "--path", str(REPO / "app")]
    if headless:
        command += ["--headless", "--audio-driver", "Dummy"]
    else:
        width, _, height = options["--resolution"].lower().partition("x")
        if not (width.isdigit() and height.isdigit()):
            print("--resolution must look like 1920x1080", file=sys.stderr)
            return 2
        command += ["--resolution", f"{width}x{height}"]
        if not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY") and os.name != "nt":
            xvfb = shutil.which("xvfb-run")
            if xvfb is None:
                print("no display and no xvfb-run: use --headless (no screenshots)", file=sys.stderr)
                return 2
            screen = f"{max(int(width), 1920)}x{max(int(height), 1080)}x24"
            command = [xvfb, "-a", "-s", f"-screen 0 {screen}"] + command + ["--audio-driver", "Dummy"]
    if app_args:
        command += ["--"] + app_args
    env = dict(os.environ, OPENRC_DEBUG_BRIDGE=str(chosen), OPENRC_DEBUG_LOG=str(out / "log.jsonl"),
               OPENRC_DEBUG_OUT=str(out))
    profile = None
    if "--real-profile" not in argv:
        # user:// (preferences, flight logs, caches) under the run, so a session never edits the player's settings.
        profile = Path(options["--profile"]).resolve() if options["--profile"] else out / "profile"
        profile.mkdir(parents=True, exist_ok=True)
        env["XDG_DATA_HOME"] = str(profile)  # Linux/BSD
        env["APPDATA"] = str(profile)  # Windows; macOS keeps ~/Library (use --real-profile knowingly there)
    with open(out / "engine.log", "wb") as engine_log:
        process = subprocess.Popen(command, cwd=REPO, env=env, stdout=engine_log, stderr=subprocess.STDOUT,
                                   stdin=subprocess.DEVNULL, start_new_session=True)
    session = {"port": chosen, "launcher_pid": process.pid, "out": str(out), "profile": str(profile) if profile else "real",
               "command": command}
    (out / "launch.json").write_text(json.dumps(session, indent=2) + "\n")
    try:
        ready = wait_ready(float(options["--timeout"]), process, chosen)
    except (RuntimeError, TimeoutError) as error:
        print(f"{error}; see {out / 'engine.log'}", file=sys.stderr)
        return 2
    session["pid"] = ready["result"]["pid"]
    RUNS.mkdir(parents=True, exist_ok=True)
    CURRENT.write_text(json.dumps(session, indent=2) + "\n")
    print(json.dumps({"ok": True, **session, "command": None, **ready["result"]}))
    return 0


def clean(argv: list[str]) -> int:
    keep = int(argv[argv.index("--keep") + 1]) if "--keep" in argv else 3
    live = current_session().get("out") if alive(current_session().get("pid")) else None
    runs = sorted((p for p in RUNS.glob("*") if p.is_dir()), key=lambda p: p.stat().st_mtime, reverse=True)
    removed = 0
    for run in runs[keep:]:
        if str(run) == live or not (run / "launch.json").exists():
            continue  # only folders this tool created, and never the running session's
        shutil.rmtree(run)
        removed += 1
    print(json.dumps({"removed": removed, "kept": len(runs) - removed}))
    return 0


def status() -> int:
    session = current_session()
    report = {"port": port(), "session": session.get("out"), "pid": session.get("pid"),
              "alive": alive(session.get("pid"))}
    try:
        report.update(result_of("ping", timeout=3.0))
        report["bridge"] = True
    except (OSError, Refused):
        report["bridge"] = False
    print(json.dumps(report))
    return 0 if report["bridge"] else 1


def stop(argv: list[str]) -> int:
    session = current_session()
    pid = session.get("pid")
    try:
        result_of("quit", timeout=5.0)
    except (OSError, Refused) as error:
        if "--force" not in argv:
            print(f"debugctl: no bridge answered ({error}); use stop --force to kill the launched process", file=sys.stderr)
            return 2
    deadline = time.monotonic() + 20.0
    while alive(pid) and time.monotonic() < deadline:
        time.sleep(0.2)
    if alive(pid) and "--force" in argv:
        for target in (session.get("launcher_pid"), pid):
            try:
                if hasattr(os, "killpg"):
                    os.killpg(target, signal.SIGKILL)  # the launcher leads the session's process group
                else:
                    subprocess.run(["taskkill", "/F", "/T", "/PID", str(target)], capture_output=True)
            except (OSError, TypeError):
                pass
        time.sleep(0.5)
    if alive(pid):
        print(f"debugctl: pid {pid} still running; use stop --force", file=sys.stderr)
        return 1
    if session and str(session.get("port")) == str(port()):
        CURRENT.unlink(missing_ok=True)
    print(json.dumps({"stopped": True, "pid": pid}))
    return 0


def logs(argv: list[str]) -> int:
    since = 0
    level = None
    follow = "--follow" in argv
    for i, arg in enumerate(argv):
        if arg == "--since":
            since = int(argv[i + 1])
        elif arg == "--level":
            level = argv[i + 1]
    while True:
        args = {"since": since, "limit": 2000}
        if level:
            args["level"] = level
        try:
            result = result_of("logs", args, timeout=10.0)
        except OSError:
            if follow:
                return 0  # the app quit
            raise
        for record in result["records"]:
            print(format_record(record), flush=True)
            since = record["seq"]
        if not follow:
            print(f"# last_seq {result['last_seq']}, dropped {result['dropped']}", file=sys.stderr)
            return 0
        time.sleep(0.25)


def format_record(record: dict) -> str:
    where = f" [{record['script']}]" if "script" in record else ""
    tick = f" @tick {record['detail']['tick']}" if "tick" in record.get("detail", {}) else ""
    return f"{record['seq']:>6} {record['level']:<12} {record['text']}{tick}{where}"


def watch(argv: list[str]) -> int:
    every, count, csv_path = 24, 0, None
    exprs = {}
    i = 0
    while i < len(argv):
        if argv[i] in ("--every", "--count", "--csv"):
            value = argv[i + 1]
            if argv[i] == "--every":
                every = int(value)
            elif argv[i] == "--count":
                count = int(value)
            else:
                csv_path = value
            i += 2
            continue
        name, _, expr = argv[i].partition("=")
        exprs[name] = expr or name
        i += 1
    if not exprs:
        print("watch needs name=expression arguments, e.g. height=-s[2] tick=sim.tick", file=sys.stderr)
        return 2
    sinks = [csv.writer(sys.stdout)]
    handle = open(csv_path, "w", newline="") if csv_path else None
    if handle:
        sinks.append(csv.writer(handle))
    printed, header = 0, False
    try:
        while count == 0 or printed < count:
            chunk = 10 if count == 0 else min(10, count - printed)
            result = result_of("sample", {"exprs": exprs, "every_ticks": every, "count": chunk})
            for sink in sinks:
                if not header:
                    sink.writerow(result["columns"])
                for row in result["rows"]:
                    sink.writerow([json.dumps(v) if isinstance(v, (list, dict)) else v for v in row])
            header = True
            printed += len(result["rows"])
            sys.stdout.flush()
            if handle:
                handle.flush()
    except KeyboardInterrupt:
        pass
    finally:
        if handle:
            handle.close()
    return 0


def split_line(line: str) -> list[str]:
    """Shell-like words, but JSON inside {...} or [...] keeps its quotes: exprs={"h":"-s[2]"} stays valid JSON.
    Quotes outside brackets group words and are removed (expr="a == b"); # starts a comment between words."""
    words: list[str] = []
    word, depth, quote, started, escaped = "", 0, None, False, False
    for ch in line:
        if quote:
            if escaped:
                word, escaped = word + ch, False
            elif ch == "\\":
                escaped = True
                if depth:
                    word += ch
            elif ch == quote:
                quote = None
                if depth:
                    word += ch
            else:
                word += ch
            continue
        if ch in "\"'":
            quote, started = ch, True
            if depth:
                word += ch
            continue
        if ch == "#" and not depth and not started:
            break
        if ch.isspace() and not depth:
            if started:
                words.append(word)
            word, started = "", False
            continue
        if ch in "{[":
            depth += 1
        elif ch in "}]":
            depth = max(0, depth - 1)
        word, started = word + ch, True
    if quote:
        raise ValueError(f"unclosed {quote} quote")
    if started:
        words.append(word)
    return words


def crawl(argv: list[str]) -> int:
    """UI smoke test of the current route: every screen opens, lists its controls and closes back to where it
    started, without new errors. In a flight the second pass starts from the pause menu, as a pilot reaches them."""
    shots = "--shots" in argv
    since = result_of("logs", {"since": 0, "limit": 1})["last_seq"]
    state = result_of("state")
    print(f"# route {state['route']}, screens {state['screens']}")
    names = result_of("open")
    failures, reached = crawl_pass(names, state["screens"], shots, set())
    if state["route"] == "flight" and "pause" in reached:
        result_of("open", {"screen": "pause"})
        paused = result_of("state")["screens"]
        print(f"# from the pause menu, screens {paused}")
        more, _ = crawl_pass([n for n in names if n != "pause"], paused, shots, reached)
        failures += more
        result_of("close")
    records = result_of("logs", {"since": since, "level": "error,script_error,shader_error,warning"})["records"]
    for record in records:
        print(format_record(record))
    errors = sum(1 for r in records if r["level"] != "warning")
    print(f"# {failures} screen failures, {errors} errors, {len(records) - errors} warnings")
    return 1 if failures or errors else 0


def crawl_pass(names: list[str], base: list, shots: bool, skip: set) -> tuple[int, set]:
    failures, reached = 0, set()
    for name in names:
        if name in skip:
            continue
        try:
            result_of("open", {"screen": name})
        except Refused:
            print(f"{name:<15} unavailable here")
            continue
        reached.add(name)
        controls = result_of("ui")["controls"]
        disabled = sum(1 for c in controls if c.get("disabled"))
        shot = result_of("screenshot", {"max_width": 960})["path"] if shots else ""
        status = "ok"
        for _ in range(4):  # nested dialogs close one level at a time
            if result_of("state")["screens"] == base:
                break
            try:
                result_of("close")
            except Refused as error:
                status = f"close refused: {error}"
                break
        after = result_of("state")["screens"]
        if after != base:
            status = f"did not return: screens {after}"
        failures += status != "ok"
        print(f"{name:<15} {status:<10} {len(controls):>3} controls ({disabled} disabled) {shot}")
    return failures, reached


def execute_line(line: str, pretty: bool = False) -> None:
    """One command line as in a run script; raises Refused / OSError / ValueError."""
    words = split_line(line)
    if not words:
        return
    command, rest = words[0], words[1:]
    if command == "sleep":
        time.sleep(float(rest[0]))
        return
    if command == "echo":
        print(" ".join(rest))
        return
    flags = [w for w in rest if w.startswith("--")]
    result = result_of(command, parse_args([w for w in rest if not w.startswith("--")]))
    show(command, result, pretty or "--pretty" in flags, "--json" in flags)


def run_script(argv: list[str]) -> int:
    if not argv:
        print("run needs a file (or - for stdin)", file=sys.stderr)
        return 2
    keep_going = "--keep-going" in argv
    files = [a for a in argv if a != "--keep-going"]
    if len(files) != 1:
        print("run needs exactly one file (or - for stdin)", file=sys.stderr)
        return 2
    source = sys.stdin if files[0] == "-" else open(files[0])
    failures = 0
    with source:
        for number, line in enumerate(source, 1):
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            print(f"> {line.rstrip()}", flush=True)
            try:
                execute_line(line)
            except (Refused, ValueError) as error:
                failures += 1
                print(f"line {number}: {error}", file=sys.stderr)
                if not keep_going:
                    return 1
            except OSError as error:
                print(f"line {number}: connection: {error}", file=sys.stderr)
                return 2
    return 1 if failures else 0


def repl() -> int:
    try:
        import readline  # noqa: F401  (history and line editing where available)
    except ImportError:
        pass
    print(f"debug bridge on 127.0.0.1:{port()}; `help` lists commands, Ctrl-D quits", file=sys.stderr)
    while True:
        try:
            line = input("openrc> ")
        except EOFError:
            print()
            return 0
        except KeyboardInterrupt:
            print()
            continue
        try:
            execute_line(line, pretty=True)
        except (Refused, ValueError) as error:
            print(f"error: {error}", file=sys.stderr)
        except OSError as error:
            print(f"connection: {error}", file=sys.stderr)


def show(command: str, result, pretty: bool, raw_json: bool) -> None:
    if command == "ui" and not raw_json and isinstance(result, dict):
        print_ui(result)
    elif command == "help" and not raw_json and isinstance(result, dict):
        width = max(map(len, result))
        for name, text in result.items():
            print(f"{name:<{width}}  {text}")
    elif command == "shortcuts" and not raw_json and isinstance(result, dict):
        print(f"# {result['vehicle']}: key name=<key> presses one; control name=<action> runs a controller action")
        for title in ("sticks", "shortcuts"):
            for row in result[title]:
                print(f"{' / '.join(row['keys']):<36} {row['action']}")
        print("# controller actions: " + ", ".join(result["controller_actions"]))
        for action, events in result["input_actions"].items():
            print(f"# input action {action}: {', '.join(events)}")
    elif command == "control" and not raw_json and isinstance(result, list):
        for action in result:
            print(f"{action['id']:<20} {action['context']:<7} {action['mode']:<6} {action['label']}")
    elif command == "methods" and not raw_json and isinstance(result, dict):
        print(f"# {result['node']} ({result['script']})")
        print("\n".join(result["methods"]))
    else:
        print(json.dumps(result, indent=1 if pretty else None, ensure_ascii=False))


def print_ui(result: dict) -> None:
    """One line per control: focus mark, type, quoted label, state, path (the value press/focus path= accepts)."""
    print(f"# scope {result['scope'] or '/root'}  focus {result['focus'] or '-'}")
    for item in result["controls"]:
        state = []
        if item.get("disabled"):
            state.append("disabled")
        if "pressed" in item:
            state.append("on" if item["pressed"] else "off")
        if "value" in item:
            state.append(f"value={item['value']:g} [{item['min']:g}..{item['max']:g}]")
        if "items" in item:
            state.append(f"selected={item['selected']} of {item['items']}")
        mark = "*" if item["focused"] else " "
        print(f"{mark} {item['type']:<13} {json.dumps(item['text'], ensure_ascii=False):<34} {' '.join(state):<16} {item['path']}")


def main(argv: list[str]) -> int:
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0 if argv else 2
    command, rest = argv[0], argv[1:]
    try:
        if command == "launch":
            return launch(rest)
        if command == "status":
            return status()
        if command == "clean":
            return clean(rest)
        if command == "stop":
            return stop(rest)
        if command == "logs":
            return logs(rest)
        if command == "watch":
            return watch(rest)
        if command == "run":
            return run_script(rest)
        if command == "repl":
            return repl()
        if command == "crawl":
            return crawl(rest)
        if command == "ready":
            timeout = float(rest[rest.index("--timeout") + 1]) if "--timeout" in rest else 60.0
            print(json.dumps(wait_ready(timeout)["result"]))
            return 0
        flags = [w for w in rest if w in ("--pretty", "--json")]
        result = result_of(command, parse_args([w for w in rest if w not in flags]))
    except Refused as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    except BrokenPipeError:
        raise
    except (OSError, TimeoutError, ValueError) as error:
        print(f"debugctl: {error}", file=sys.stderr)
        return 2
    show(command, result, "--pretty" in flags, "--json" in flags)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except BrokenPipeError:  # e.g. `watch ... | head`: the reader left; that is not an error
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        sys.exit(0)
