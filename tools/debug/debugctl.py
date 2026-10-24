#!/usr/bin/env python3
"""Drive a running OpenRC app through its debug bridge (PT1h-R7/R8). Standard library only.
Guide: tools/debug/README.md (the "I want to..." table). Task index for every other tool: docs/tools/README.md.

Session
  launch [--headless] [--resolution WxH] [--port N] [--app DIR] [--script-profile] [--verbose]
         [--profile DIR | --real-profile] [--import] [-- <app args>]
                                                            start the app; prints its port (isolated user:// profile);
                                                            --import first refreshes the import cache (new assets)
  status | ready [--timeout S] | stop [--force]            alive? / wait for it / quit it (prints crash + exit leaks)
  clean [--keep N]                                          delete old run folders (never a live session)
Drive the app (any bridge command; `help` asks the app for its list)
  ui | press text="Fly" | select text=X item="Y" | open screen=settings | close | type text=… into=…
  fly aircraft=<id> start=airborne | home | restart | key name=Shift+C | control name=gear_toggle
  sticks pitch=0.3 throttle=0.8 for_s=2 | drive throttle=0.6 for_s=1 | pause | step ticks=240
Observe and hunt bugs
  state | logs [--since N] [--level …] [--follow] [--summary] | frames | objects [baseline|diff=true]
  break expr="-s[2] < 1" wait=true | profile (launch --script-profile) | screenshot max_width=960 format=jpg
  watch [--every TICKS] [--count N] [--csv FILE] name=expr …   live values every n simulation ticks
  timeline [--hitch] [--since N] [--until N] [--top N]         where a long frame's time went (launch --verbose)
Scripts and checks
  run FILE|- [--keep-going] [--fail-on-error]                  a repro script, one command per line
  crawl [--shots]                                              open/list/close every screen; report errors
  soak FILE [--cycles N] [--warmup N] [--tolerance N]          repeat a scenario; report what keeps growing
  monkey [--steps N] [--seed S] [--keys] [--out FILE]          seeded random UI walk; a failure leaves a repro script
  smoke [--seed S] [--steps N] [--cycles N] [--app DIR]        own headless session: everything above, one verdict
  repl                                                         interactive prompt (same syntax as run scripts)

Values are JSON when they parse (true, 3, 0.5, [1,2], {"a":"b"}), else strings; quoted values stay strings.
Output flags: --pretty, --json, --paths. Exit status: 0 ok, 1 refused or a check failed, 2 usage or connection error.
Port: OPENRC_DEBUG_BRIDGE, else the last launch on this machine (another agent's, if one launched after you: set
OPENRC_DEBUG_BRIDGE=<your port> on every command when sharing the machine). OPENRC_GODOT overrides the engine.
"""
from __future__ import annotations

import contextlib
import csv
import datetime
import io
import json
import os
import random
import re
import secrets
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
CURRENT = RUNS / "current.json"  # the last launch on this machine (any agent): the default target
SESSIONS = RUNS / "sessions"  # one 0600 file per live session, by port, holding its token and process ids


class Refused(Exception):
    """The bridge answered ok=false."""


def session_for(port_number: int) -> dict:
    try:
        return json.loads((SESSIONS / f"{port_number}.json").read_text())
    except (OSError, ValueError):
        return {}


def current_session() -> dict:
    """The session the commands address: OPENRC_DEBUG_BRIDGE's port, else the last launch."""
    explicit = env_port()
    if explicit is not None:
        return session_for(explicit)
    pointer = current_pointer()
    return session_for(int(pointer["port"])) or pointer if pointer.get("port") else {}


def current_pointer() -> dict:
    try:
        return json.loads(CURRENT.read_text())
    except (OSError, ValueError):
        return {}


def env_port() -> int | None:
    """OPENRC_DEBUG_BRIDGE as a port; 1/on/true only enable the bridge (as in the engine) and name no port."""
    value = os.environ.get("OPENRC_DEBUG_BRIDGE", "")
    return int(value) if value.isdigit() and int(value) > 1 else None


def port() -> int:
    return env_port() or int(current_pointer().get("port", DEFAULT_PORT))


def token(port_number: int | None = None) -> str:
    """OPENRC_DEBUG_TOKEN, else the secret of the session on that port (by default the addressed one). Never the
    last launch's: another agent's concurrent launch may have replaced it."""
    if os.environ.get("OPENRC_DEBUG_TOKEN"):
        return os.environ["OPENRC_DEBUG_TOKEN"]
    target = port_number or port()
    session = session_for(target) or current_pointer()
    return session.get("token", "") if int(session.get("port", 0)) == target else ""


def parse_value(text: str):
    if len(text) >= 2 and text[0] == text[-1] and text[0] in "\"'":
        if text[0] == '"':
            try:
                decoded = json.loads(text)  # "\n", "\u00d7" and \" escapes, as json.dumps writes them
                if isinstance(decoded, str):
                    return decoded
            except json.JSONDecodeError:
                pass
        return text[1:-1]  # quoted in a script: always a string ("2" names the key, not the number)
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
    secret = token(to_port)
    if secret:
        payload["token"] = secret
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


class PortTaken(RuntimeError):
    """The launched engine could not listen: another process holds (or is still releasing) the port."""


def wait_ready(timeout: float, process: subprocess.Popen | None = None, to_port: int | None = None,
               log: Path | None = None) -> dict:
    """Ping until the bridge answers. With `process`, the answer must come from that launch: a bridge of another
    app on the same port (with another token) is refused instead of being mistaken for ours."""
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        if process is not None and process.poll() is not None:
            raise RuntimeError(f"the app exited with status {process.returncode} before the bridge answered")
        if log is not None and "debug bridge: cannot listen" in log.read_text(errors="replace"):
            raise PortTaken(f"port {to_port} is taken")
        try:
            reply = request("ping", timeout=2.0, to_port=to_port)
        except OSError as error:
            last = error
            time.sleep(0.25)
            continue
        if not reply.get("ok"):
            raise RuntimeError(f"another bridge answered on port {to_port}: {reply.get('error')}")
        if process is not None and hasattr(os, "getpgid"):
            try:
                ours = os.getpgid(reply["result"]["pid"]) == process.pid  # the launcher leads its process group
            except OSError:
                ours = False
            if not ours:
                raise RuntimeError(f"pid {reply['result']['pid']} answered on port {to_port}, not the launched app")
        return reply
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
    try:  # an exited child that its parent (e.g. this process, under smoke) has not reaped yet is a zombie: gone
        return Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[0] != "Z"
    except (OSError, IndexError):
        return True


def godot() -> str:
    if os.environ.get("OPENRC_GODOT"):
        return os.environ["OPENRC_GODOT"]
    if os.name == "nt":
        raise ValueError("set OPENRC_GODOT to the Godot 4.7.2 executable (app/get-godot.sh is a Bash script)")
    return subprocess.run([str(REPO / "app" / "get-godot.sh")], check=True, capture_output=True, text=True).stdout.strip()


def launch(argv: list[str]) -> int:
    app_args: list[str] = []
    if "--" in argv:
        split = argv.index("--")
        argv, app_args = argv[:split], argv[split + 1:]
    headless = "--headless" in argv
    # Rendered sessions open at 1920x1080, the primary display target (AGENTS.md); --resolution 1280x720 is faster.
    options = {"--out": None, "--timeout": "180", "--port": None, "--profile": None, "--resolution": "1920x1080",
               "--app": str(REPO / "app")}
    for i, arg in enumerate(argv):
        if arg in options and i + 1 < len(argv):
            options[arg] = argv[i + 1]
    explicit_port = int(options["--port"]) if options["--port"] else env_port()
    chosen = reserve_port(explicit_port)
    if chosen is None:
        print(f"port {explicit_port} is in use or has a live session: stop it or pass another --port", file=sys.stderr)
        return 2
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    out = Path(options["--out"]).resolve() if options["--out"] else RUNS / f"{stamp}-{chosen}"
    if not options["--out"]:
        suffix = 1
        while out.exists():  # two launches in the same second
            suffix += 1
            out = RUNS / f"{stamp}-{chosen}-{suffix}"
    out.mkdir(parents=True, exist_ok=False)
    # --app runs a candidate copy (it needs the import cache and the sibling folders, as app/ has them).
    command = [godot(), "--path", str(Path(options["--app"]).resolve())]
    if "--import" in argv:  # assets pulled since the last import load as "Unable to open file: …ctex"
        imported = subprocess.run([command[0], "--headless", "--path", command[2], "--audio-driver", "Dummy", "--import"],
                                  capture_output=True, text=True, timeout=1800)
        if imported.returncode != 0:
            print("import failed:\n" + imported.stdout[-2000:], file=sys.stderr)
            return 2
    if "--script-profile" in argv:
        # The local debugger prints a per-function GDScript profile about once a second; `profile` parses it.
        command += ["-d", "--profiling", "--ignore-error-breaks"]
    if "--verbose" in argv:
        command += ["--verbose"]  # names each ObjectDB instance leaked at exit (stop reports them)
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
    # A fresh secret per session: other local users and web pages (which can POST to 127.0.0.1) cannot drive it.
    secret = os.environ.get("OPENRC_DEBUG_TOKEN") or secrets.token_hex(16)
    env = dict(os.environ, OPENRC_DEBUG_BRIDGE=str(chosen), OPENRC_DEBUG_LOG=str(out / "log.jsonl"),
               OPENRC_DEBUG_OUT=str(out), OPENRC_DEBUG_TOKEN=secret)
    profile = None
    if "--real-profile" not in argv:
        # user:// (preferences, flight logs, caches) under the run, so a session never edits the player's settings.
        profile = Path(options["--profile"]).resolve() if options["--profile"] else out / "profile"
        profile.mkdir(parents=True, exist_ok=True)
        env["XDG_DATA_HOME"] = str(profile)  # Linux/BSD
        env["APPDATA"] = str(profile)  # Windows; macOS keeps ~/Library (use --real-profile knowingly there)
    for attempt in range(2):
        env["OPENRC_DEBUG_BRIDGE"] = str(chosen)
        with open(out / "engine.log", "wb") as engine_log:
            process = subprocess.Popen(command, cwd=REPO, env=env, stdout=engine_log, stderr=subprocess.STDOUT,
                                       stdin=subprocess.DEVNULL, start_new_session=True)
        session = {"port": chosen, "launcher_pid": process.pid, "out": str(out),
                   "profile": str(profile) if profile else "real", "command": command, "attempt": attempt + 1}
        (out / "launch.json").write_text(json.dumps(session, indent=2) + "\n")
        session["token"] = secret
        write_private(SESSIONS / f"{chosen}.json", session)  # before waiting: status/stop --force can find it
        write_private(CURRENT, session)
        try:
            ready = wait_ready(float(options["--timeout"]), process, chosen, out / "engine.log")
            break
        except PortTaken:
            kill_group(process.pid)
            forget_session(chosen, process.pid)
            if explicit_port or attempt == 1:
                print(f"port {chosen} is taken; the launched app was stopped (pass another --port)", file=sys.stderr)
                return 2
            chosen = reserve_port(None)  # the default port was still being released: retry once elsewhere
        except (RuntimeError, TimeoutError, KeyboardInterrupt) as error:
            kill_group(process.pid)  # never leave a 2-3 GB engine behind
            forget_session(chosen, process.pid)
            print(f"{error or 'interrupted'}; the launched app was stopped; see {out / 'engine.log'}", file=sys.stderr)
            tail(out / "engine.log")
            return 2
    session["pid"] = ready["result"]["pid"]
    write_private(SESSIONS / f"{chosen}.json", session)
    write_private(CURRENT, session)
    shown = {k: v for k, v in session.items() if k not in ("command", "token")}
    shown["use"] = f"OPENRC_DEBUG_BRIDGE={chosen} python3 tools/debug/debugctl.py <command>"
    print(json.dumps({"ok": True, **shown, **ready["result"]}))
    return 0


def reserve_port(explicit: int | None) -> int | None:
    """Claim a port for a new session with an exclusive file create, so two agents launching at the same moment
    never share one. A stale claim (its processes are gone) is taken over."""
    SESSIONS.mkdir(parents=True, exist_ok=True)
    candidates = [explicit] if explicit else [DEFAULT_PORT] + [free_port() for _ in range(5)]
    for candidate in candidates:
        claim = SESSIONS / f"{candidate}.json"
        holder = session_for(candidate)
        if holder and (alive(holder.get("pid")) or alive(holder.get("launcher_pid"))):
            continue
        claim.unlink(missing_ok=True)
        try:
            descriptor = os.open(claim, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError:
            continue  # another agent claimed it a moment ago
        with os.fdopen(descriptor, "w") as handle:
            handle.write(json.dumps({"port": candidate, "launcher_pid": os.getpid(), "claimed": True}) + "\n")
        if port_free(candidate):
            return candidate
        claim.unlink(missing_ok=True)  # something else listens there
    return None


def live_sessions() -> list[int]:
    ports = []
    for claim in sorted(SESSIONS.glob("*.json")) if SESSIONS.exists() else []:
        holder = session_for(int(claim.stem)) if claim.stem.isdigit() else {}
        if holder.get("pid") and alive(holder.get("pid")):
            ports.append(int(claim.stem))
    return ports


def ambiguous_target() -> list[int]:
    """Several live sessions and no OPENRC_DEBUG_BRIDGE: the last launch may belong to another agent."""
    if env_port() is not None:
        return []
    live = live_sessions()
    return live if len(live) > 1 else []


def refuse_ambiguous() -> bool:
    others = ambiguous_target()
    if others:
        print(f"debugctl: {len(others)} live sessions on ports {others}: set OPENRC_DEBUG_BRIDGE=<your port>",
              file=sys.stderr)
    return bool(others)


def forget_session(port_number: int, launcher_pid: int | None = None) -> None:
    """Remove a session's files, only if they still describe that launch (another agent may own the port now)."""
    claim = SESSIONS / f"{port_number}.json"
    holder = session_for(port_number)
    if launcher_pid is None or holder.get("launcher_pid") in (launcher_pid, None):
        claim.unlink(missing_ok=True)
    pointer = current_pointer()
    if pointer.get("port") == port_number and (launcher_pid is None or pointer.get("launcher_pid") == launcher_pid):
        CURRENT.unlink(missing_ok=True)


def write_private(path: Path, value: dict) -> None:
    """The session file holds the token: readable by this user only."""
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w") as handle:
        handle.write(json.dumps(value, indent=2) + "\n")
    if os.name != "nt":
        os.chmod(path, 0o600)


def kill_group(pid: int | None) -> None:
    """Kill a process this tool launched, with its children (xvfb-run, Xvfb, Godot)."""
    if not pid:
        return
    try:
        if hasattr(os, "killpg"):
            os.killpg(pid, signal.SIGKILL)  # the launcher leads its own session/process group
        else:
            subprocess.run(["taskkill", "/F", "/T", "/PID", str(pid)], capture_output=True)
    except OSError:
        pass


def tail(path: Path, lines: int = 15) -> None:
    try:
        text = path.read_text(errors="replace").splitlines()[-lines:]
    except OSError:
        return
    for line in text:
        print(f"  | {line}", file=sys.stderr)


def clean(argv: list[str]) -> int:
    keep = int(argv[argv.index("--keep") + 1]) if "--keep" in argv else 3
    live = current_session().get("out") if alive(current_session().get("pid")) else None
    runs = sorted((p for p in RUNS.glob("*") if p.is_dir() and p != SESSIONS), key=lambda p: p.stat().st_mtime, reverse=True)
    removed = 0
    for run in runs[keep:]:
        if str(run) == live or not (run / "launch.json").exists():
            continue  # only folders this tool created, and never the running session's
        shutil.rmtree(run)
        removed += 1
    stale = 0
    for claim in SESSIONS.glob("*.json") if SESSIONS.exists() else []:
        holder = session_for(int(claim.stem)) if claim.stem.isdigit() else {}
        if not (alive(holder.get("pid")) or alive(holder.get("launcher_pid"))):
            claim.unlink(missing_ok=True)
            stale += 1
    print(json.dumps({"removed": removed, "kept": len(runs) - removed, "stale_sessions": stale}))
    return 0


def status() -> int:
    if refuse_ambiguous():
        return 2
    session = current_session()
    report = {"port": port(), "session": session.get("out"), "pid": session.get("pid"),
              "alive": alive(session.get("pid"))}
    try:
        report.update(result_of("ping", timeout=3.0))
        report["bridge"] = True
    except (OSError, Refused):
        report["bridge"] = False
    print(json.dumps(report))
    if not report["bridge"] and session.get("out"):
        ended = exit_report(Path(session["out"]) / "engine.log")
        if ended:
            print(json.dumps({"engine_exit": ended}, indent=1))
        print(f"no bridge; last lines of {session['out']}/engine.log:", file=sys.stderr)
        tail(Path(session["out"]) / "engine.log")
    return 0 if report["bridge"] else 1


def stop(argv: list[str]) -> int:
    others = ambiguous_target()
    if others:
        print(f"debugctl: {len(others)} live sessions (ports {others}); stop yours with OPENRC_DEBUG_BRIDGE=<port>",
              file=sys.stderr)
        return 2
    session = current_session()
    pid = session.get("pid") or session.get("launcher_pid")
    if not pid and env_port() is None:
        print("debugctl: no launched session to stop (tmp/debug-bridge/current.json is missing)", file=sys.stderr)
        return 1
    try:
        result_of("quit", timeout=5.0)
    except (OSError, Refused) as error:
        if "--force" not in argv:
            print(f"debugctl: no bridge answered ({error}); use stop --force to kill the launched process", file=sys.stderr)
            return 2
    deadline = time.monotonic() + 60.0  # saving an active trace or flight log can take a while
    while alive(pid) and time.monotonic() < deadline:
        time.sleep(0.2)
    if alive(pid) and "--force" in argv:
        kill_group(session.get("launcher_pid"))
        time.sleep(0.5)
    if alive(pid):
        print(f"debugctl: pid {pid} still running; use stop --force", file=sys.stderr)
        return 1
    if session:
        forget_session(int(session.get("port", port())), session.get("launcher_pid"))
    report = exit_report(Path(session["out"]) / "engine.log") if session.get("out") else {}
    print(json.dumps({"stopped": True, "pid": pid, **report}))  # crash null and leaked_objects 0 mean a clean exit
    return 1 if report.get("crash") else 0


def exit_report(path: Path) -> dict:
    """What the engine said when it ended: leaked objects/resources at exit, and a crash with its script stack."""
    try:
        text = path.read_text(errors="replace")
    except OSError:
        return {}
    report: dict = {"crash": None, "leaked_objects": 0}
    leaked = re.search(r"(\d+) ObjectDB instances? (?:were|was) leaked at exit", text)
    if leaked:
        report["leaked_objects"] = int(leaked.group(1))
        instances = re.findall(r"Leaked instance: ([^\n]+)", text)
        if instances:
            report["leaked_instances"] = instances[:30]
    resources = re.search(r"(\d+) resources? still in use at exit", text)
    if resources:
        report["resources_in_use_at_exit"] = int(resources.group(1))
    crash = re.search(r"handle_crash: (.+)", text)
    if crash:
        script = re.search(r"END OF C\+\+ BACKTRACE --\s*=+\s*GDScript backtrace[^\n]*\n(.*?)-- END OF GDSCRIPT", text, re.S)
        before = text[:crash.start()].strip().splitlines()[-6:]
        report["crash"] = {"reason": crash.group(1).strip(), "last_lines": before,
                           "gdscript_backtrace": [l.strip() for l in script.group(1).splitlines() if l.strip()] if script else []}
    return report


def logs(argv: list[str]) -> int:
    if refuse_ambiguous():
        return 2
    since = 0
    level = None
    follow = "--follow" in argv
    for i, arg in enumerate(argv):
        if arg == "--since":
            since = int(argv[i + 1])
        elif arg == "--level":
            level = argv[i + 1]
    if "--summary" in argv:
        args = {"since": since, "summary": True}
        if level:
            args["level"] = level
        result = result_of("logs", args, timeout=10.0)
        for group in result["groups"]:
            where = f" [{group['script']}]" if group["script"] else ""
            print(f"{group['count']:>6}x {group['level']:<12} {group['text']}{where}  (seq {group['first_seq']}…{group['last_seq']})")
        print(f"# {len(result['groups'])} distinct messages up to seq {result['last_seq']}", file=sys.stderr)
        return 0
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


def timeline(argv: list[str]) -> int:
    """Phase attribution inside long frames: the largest wall-time gaps between consecutive log lines, with the line
    before (what had just finished) and after. Launch with --verbose for one line per resource load."""
    if refuse_ambiguous():
        return 2
    option = lambda name, default: int(argv[argv.index(name) + 1]) if name in argv else default  # noqa: E731
    records = [r for r in result_of("logs", {"since": option("--since", 0), "limit": 2000})["records"]
               if r["level"] != "event" and r["seq"] <= option("--until", 1 << 62)]
    if "--hitch" in argv:  # only the lines printed during the longest recorded hitch frame
        hitches = result_of("frames")["hitches"]
        if not hitches:
            print("no hitch recorded yet (frames lists them)", file=sys.stderr)
            return 1
        longest = max(hitches, key=lambda h: h["ms"])
        records = [r for r in records if longest["frame"] - 1 <= r["frame"] <= longest["frame"]]
        print(f"# hitch at frame {longest['frame']}: {longest['ms']} ms; {', '.join(longest['causes']) or 'no counter changed'}")
    if len(records) < 2:
        print("timeline needs at least two log lines after the cursor (launch --verbose for resource loads)", file=sys.stderr)
        return 1
    gaps = sorted(((b["time_ms"] - a["time_ms"], a, b) for a, b in zip(records, records[1:])), key=lambda g: -g[0])
    span = records[-1]["time_ms"] - records[0]["time_ms"]
    print(f"# {len(records)} lines over {span} ms (frames {records[0]['frame']}..{records[-1]['frame']}); largest gaps:")
    for gap, before, after in gaps[:option("--top", 12)]:
        print(f"{gap:>7} ms  {gap * 100 / max(span, 1):4.1f} %  after: {before['text'][:100]}")
        print(f"{'':>17}  next:  {after['text'][:100]}")
    return 0


def format_record(record: dict) -> str:
    where = f" [{record['script']}]" if "script" in record else ""
    tick = f" @tick {record['detail']['tick']}" if "tick" in record.get("detail", {}) else ""
    return f"{record['seq']:>6} {record['level']:<12} {record['text']}{tick}{where}"


def watch(argv: list[str]) -> int:
    if refuse_ambiguous():
        return 2
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
    Quotes outside brackets group words and are kept around the value (name="2" stays the string "2"; parse_value
    removes them); # starts a comment between words."""
    words: list[str] = []
    word, depth, quote, started, escaped = "", 0, None, False, False
    for ch in line:
        if quote:
            if escaped:
                word, escaped = word + ch, False
            elif ch == "\\":
                escaped = True
                word += ch  # kept: parse_value decodes JSON escapes in double quotes
            elif ch == quote:
                quote = None
                word += ch
            else:
                word += ch
            continue
        if ch in "\"'":
            quote, started = ch, True
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
    if refuse_ambiguous():
        return 2
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
        if len(rest) != 1:
            raise ValueError("sleep needs one number of seconds")
        time.sleep(float(rest[0]))
        return
    if command == "echo":
        print(" ".join(parse_value(w) if isinstance(parse_value(w), str) else w for w in rest))
        return
    display = ("--pretty", "--json", "--paths")
    flags = [w for w in rest if w in display]
    # Other --name flags become name=true, so `logs --summary` in a script means what it means on the command line.
    args = parse_args([w for w in rest if not w.startswith("--")] + [w[2:] + "=true" for w in rest
                                                                     if w.startswith("--") and w not in display])
    result = result_of(command, args)
    show(command, result, pretty or "--pretty" in flags, "--json" in flags, "--paths" in flags)


def run_script(argv: list[str]) -> int:
    if refuse_ambiguous():
        return 2
    if not argv:
        print("run needs a file (or - for stdin)", file=sys.stderr)
        return 2
    keep_going = "--keep-going" in argv
    fail_on_error = "--fail-on-error" in argv
    files = [a for a in argv if a not in ("--keep-going", "--fail-on-error")]
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
                seq = result_of("ping")["log_seq"] if fail_on_error else 0
                execute_line(line)
                if fail_on_error:
                    new = new_errors(seq)
                    if new:
                        raise Refused("new engine errors: " + " | ".join(format_record(r) for r in new[:5]))
            except (Refused, ValueError) as error:
                failures += 1
                print(f"line {number}: {error}", file=sys.stderr)
                if not keep_going:
                    return 1
            except OSError as error:
                print(f"line {number}: connection: {error}", file=sys.stderr)
                return 2
    return 1 if failures else 0


def new_errors(since: int) -> list:
    return result_of("logs", {"since": since, "level": "error,script_error,shader_error", "limit": 50})["records"]


def soak(argv: list[str]) -> int:
    """Repeat a scenario script; after a warm-up, every cycle is compared with the first measured baseline. A class
    or total that grows in every cycle is reported with its growth per cycle (a leak suspect, not a proof)."""
    if refuse_ambiguous():
        return 2
    files = [a for a in argv if not a.startswith("--") and not a.isdigit()]
    if len(files) != 1:
        print("soak needs one scenario script", file=sys.stderr)
        return 2
    option = lambda name, default: int(argv[argv.index(name) + 1]) if name in argv else default  # noqa: E731
    cycles, warmup, tolerance = option("--cycles", 5), option("--warmup", 1), option("--tolerance", 0)
    lines = [l for l in Path(files[0]).read_text().splitlines() if l.strip() and not l.lstrip().startswith("#")]
    since = result_of("ping")["log_seq"]
    history: list[dict] = []
    for cycle in range(warmup + cycles):
        for line in lines:
            execute_quiet(line)
        result_of("wait", {"frames": 5})
        measured = cycle >= warmup
        census = result_of("objects", {"baseline": cycle == warmup, "diff": cycle > warmup, "top": 400})
        rss = rss_mib(current_session().get("pid"))
        label = "warm-up" if not measured else ("baseline" if cycle == warmup else f"cycle {cycle - warmup}")
        totals = census["totals"]
        print(f"{label:<9} nodes {totals['nodes']:>7.0f}  orphans {totals['orphans']:>5.0f}  resources {totals['resources']:>6.0f}  "
              f"static {totals['static_memory_mib']:>8.1f} MiB  rss {rss if rss is not None else '?':>7} MiB", flush=True)
        if cycle > warmup:
            diff = census["diff"]
            history.append({"totals": dict(diff["totals"]), "classes": dict(diff["classes"]), "orphans": dict(diff["orphans"])})
    suspects = []
    if len(history) >= 2:
        for section in ("totals", "classes", "orphans"):
            keys = set().union(*(h[section] for h in history))
            for key in sorted(keys):
                series = [h[section].get(key, 0) for h in history]
                if all(b > a for a, b in zip(series, series[1:])) and series[-1] > tolerance and key != "static_memory_mib":
                    suspects.append(f"{section}: {key} +{series[-1]:g} after {len(series)} cycles ({series})")
    errors = new_errors(since)
    for line in suspects:
        print("GROWS " + line)
    for record in errors[:10]:
        print("ERROR " + format_record(record))
    print(f"# {len(suspects)} growing counters, {len(errors)} errors: baseline + {max(cycles - 1, 0)} compared cycles "
          f"(after {warmup} warm-up)")
    return 1 if suspects or errors else 0


def rss_mib(pid) -> float | None:
    try:
        for line in Path(f"/proc/{pid}/status").read_text().splitlines():
            if line.startswith("VmRSS:"):
                return round(int(line.split()[1]) / 1024, 1)
    except (OSError, ValueError, TypeError):
        return None
    return None


# Leaving the app or the machine is out of bounds; "Exit options" and "Return to Home" are fair game.
MONKEY_AVOID = re.compile(r"\bquit\b|\bsalir\b|desktop|escritorio|download|descargar|website|github|browser|navegador|"
                          r"open folder|report a bug|delete|borrar|uninstall", re.IGNORECASE)


def monkey_allowed(control: dict) -> bool:
    return (not control.get("disabled") and control["type"] not in ("LineEdit", "TextEdit")
            and not MONKEY_AVOID.search(control["text"]) and control["path"].rsplit("/", 1)[-1] != "Quit")


def monkey(argv: list[str]) -> int:
    """Seeded random walk over what is on screen. Every step is written as a `run` line; a step that logs a new
    error, or an app that stops answering, ends the walk and leaves the trail as a repro script."""
    if refuse_ambiguous():
        return 2
    option = lambda name, default: argv[argv.index(name) + 1] if name in argv else default  # noqa: E731
    steps, seed = int(option("--steps", 200)), int(option("--seed", random.randrange(1 << 30)))
    out = Path(option("--out", str(RUNS / f"monkey-{seed}.txt")))
    rng = random.Random(seed)
    keys = []
    if "--keys" in argv:
        table = result_of("shortcuts")
        keys = [k for row in table["shortcuts"] for k in row["keys"] if k not in ("Escape", "F10")]
    trail = [f"# debugctl.py monkey --seed {seed}: replay with debugctl.py run {out.name}"]
    since = result_of("ping")["log_seq"]
    started_at: list[tuple[int, str]] = []  # (frame when the action was sent, action)
    visited: set[str] = set()
    route = result_of("ping")["route"]
    failure = None
    for step in range(steps):
        listing = result_of("ui")
        controls = [c for c in listing["controls"] if monkey_allowed(c)]
        visited.add(f"{route}:{short_path(listing['scope'] or '/root', '')}")
        line = monkey_action(rng, controls, keys)
        trail.append(line)
        ping = result_of("ping")
        started_at.append((ping["frame"], line))
        route = ping["route"]
        try:
            execute_quiet(line)
        except (Refused, ValueError) as error:
            # A refused action changed nothing: comment it out so a replay follows the same path.
            trail[-1] = f"# refused: {trail[-1]}  ({error})"
        except OSError as error:
            failure = f"step {step + 1}: the app stopped answering ({error})"
            break
        errors = new_errors(since)
        if errors:
            failure = f"step {step + 1}: new errors: " + " | ".join(format_record(r) for r in errors[:3])
            break
    slow = slow_actions(started_at)
    for action, frames_ms in slow.items():
        trail.append(f"# slow: {action} -> {', '.join(f'{ms:.0f} ms' for ms in frames_ms)}")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(trail) + "\n", encoding="utf-8")
    for action, frames_ms in sorted(slow.items(), key=lambda item: -max(item[1]))[:10]:
        print(f"slow after {action}: {', '.join(f'{ms:.0f} ms' for ms in frames_ms)}")
    print(json.dumps({"seed": seed, "steps": len([l for l in trail if not l.startswith("#")]),
                      "refused": len([l for l in trail if l.startswith("# refused")]), "failure": failure,
                      "visited": sorted(visited),
                      "route": result_of("state")["route"] if failure is None or "answering" not in failure else None,
                      "trail": str(out)}))
    return 1 if failure else 0


def monkey_action(rng: random.Random, controls: list, keys: list) -> str:
    roll = rng.random()
    if roll < 0.12 or not controls:
        return "close" if roll < 0.08 or not keys else key_line(rng.choice(keys))
    if keys and roll < 0.25:
        return key_line(rng.choice(keys))
    control = rng.choice(controls)
    labels = [c["text"] for c in controls]
    # Literal UTF-8 (×, ·, ñ): a JSON \\u escape would not survive the run-script reader.
    target = (f"text={json.dumps(control['text'], ensure_ascii=False)}" if labels.count(control["text"]) == 1
              else f"path={json.dumps(control['path'], ensure_ascii=False)}")
    if "items" in control and control["items"]:
        return f"select {target} index={rng.randrange(len(control['items']))}"
    if "value" in control:
        value = control["min"] + rng.random() * (control["max"] - control["min"])
        return f"set_value {target} value={value:.3f}"
    return f"press {target}"


def slow_actions(started_at: list[tuple[int, str]]) -> dict:
    """Attribute each recorded hitch to the last action sent at or before its frame."""
    slow: dict = {}
    if not started_at:
        return slow
    for hitch in result_of("frames")["hitches"]:
        earlier = [line for frame, line in started_at if frame <= hitch["frame"]]
        if earlier and hitch["frame"] >= started_at[0][0]:
            slow.setdefault(earlier[-1], []).append(hitch["ms"])
    return slow


SCENARIOS = Path(__file__).resolve().parent / "scenarios"


def smoke(argv: list[str]) -> int:
    """A self-contained regression pass in its own headless session (own port; other agents are untouched)."""
    option = lambda name, default: argv[argv.index(name) + 1] if name in argv else default  # noqa: E731
    seed, steps, cycles = option("--seed", "20261024"), option("--steps", "150"), option("--cycles", "3")
    launch_args = ["--headless", "--timeout", "300"] + (["--app", option("--app", "")] if "--app" in argv else [])
    capture = io.StringIO()
    with contextlib.redirect_stdout(capture):
        status = launch(launch_args)
    if status != 0:
        print("smoke: launch failed", file=sys.stderr)
        return 2
    session = json.loads(capture.getvalue().strip().splitlines()[-1])
    os.environ["OPENRC_DEBUG_BRIDGE"] = str(session["port"])
    results: list[tuple[str, int]] = []

    def step(name: str, function, args: list[str]) -> None:
        print(f"== {name}", flush=True)
        try:
            code = function(args)
        except (Refused, OSError, ValueError) as error:
            print(f"   {error}")
            code = 1
        results.append((name, code))

    try:
        step("crawl from Home", crawl, [])
        for scenario in sorted(SCENARIOS.glob("*.txt")):
            step(f"scenario {scenario.stem}", run_script, [str(scenario), "--fail-on-error"])
        step("fly", lambda _: run_lines(["fly start=airborne", "wait frames=10"]), [])
        step("crawl from the pause menu", crawl, [])
        step("back to Home", lambda _: run_lines(["home"]), [])
        step(f"monkey seed {seed}", monkey, ["--steps", steps, "--seed", seed, "--keys"])
        step("back to Home", home_reset, [])
        soak_file = Path(session["out"]) / "smoke-soak.txt"
        soak_file.write_text("fly start=airborne\nwait frames=30\nhome\n")
        step(f"soak fly/Home x{cycles}", soak, [str(soak_file), "--cycles", cycles, "--warmup", "1"])
        hitches = result_of("frames")["hitch_total"]
        home_reset()
    finally:
        capture = io.StringIO()
        with contextlib.redirect_stdout(capture):
            if stop([]) != 0 and alive(session.get("launcher_pid")):
                stop(["--force"])  # this smoke's own session only
        ended = json.loads(capture.getvalue().strip().splitlines()[-1]) if capture.getvalue().strip() else {}
    if ended.get("crash"):
        results.append(("engine exit (crash)", 1))
    failed = [name for name, code in results if code != 0]
    print(json.dumps({"ok": not failed, "failed": failed, "steps": len(results), "hitches": hitches,
                      "leaked_objects_at_exit": ended.get("leaked_objects", 0), "out": session["out"]}))
    return 1 if failed else 0


def home_reset(_args: list[str] | None = None) -> int:
    """Back to a bare Home from wherever a step left the app: end flights and the truck, close dialogs and menus,
    and discard unsaved Workshop edits."""
    for _ in range(12):
        state = result_of("state")
        if state["route"] == "flight":
            attempt = ["home"]
        elif state["route"] == "ground_vehicle":
            attempt = ["call node=AppRoot method=end_ground_vehicle"]
        elif state["screens"] != ["home"] or result_of("ui").get("window"):
            attempt = ["close"]
        else:
            return 0
        try:
            run_lines(attempt)
        except Refused:
            try:
                run_lines(['press text="Discard changes"'])
            except Refused:
                pass
        result_of("wait", {"frames": 3})
    print("   could not return to Home: " + json.dumps(result_of("state")["screens"]))
    return 1


def run_lines(lines: list[str]) -> int:
    for line in lines:
        execute_quiet(line)
    return 0


def key_line(name: str) -> str:
    return f"key name={json.dumps(name, ensure_ascii=False)}"  # "Kp Enter" has a space


def execute_quiet(line: str) -> None:
    words = split_line(line)
    result_of(words[0], parse_args(words[1:]))


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


def show(command: str, result, pretty: bool, raw_json: bool, full_paths: bool = False) -> None:
    if command == "ui" and not raw_json and isinstance(result, dict):
        print_ui(result, full_paths)
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
    elif command == "frames" and not raw_json and isinstance(result, dict) and "p50_ms" in result:
        print(f"{result['frames']} frames: mean {result['mean_ms']} ms, p50 {result['p50_ms']}, p95 {result['p95_ms']}, "
              f"p99 {result['p99_ms']}, max {result['max_ms']} ms; {result['fps_mean']} fps, 1 % low {result['fps_1pct_low']} fps; "
              f"physics catch-up frames {result['physics_catch_up_frames']}; hitches {result['hitch_total']} "
              f"(> max({result['hitch_ms']} ms, {result['factor']}x typical {result['typical_ms']} ms))")
        for hitch in result["hitches"]:
            causes = ", ".join(hitch["causes"]) or "no counter changed"
            print(f"  frame {hitch['frame']}: {hitch['ms']} ms, {hitch['physics_ticks']} ticks; {causes}; deltas {hitch['deltas']}")
            for text in hitch["log"][:3]:
                print(f"      log: {text}")
    elif command == "objects" and not raw_json and isinstance(result, dict):
        print("totals " + ", ".join(f"{k} {v:g}" for k, v in result["totals"].items()))
        for title in ("diff",):
            for section, rows in result.get(title, {}).items():
                for key, change in rows:
                    print(f"  diff {section:<8} {change:+g}  {key}")
        print("classes: " + ", ".join(f"{k} {v}" for k, v in result["classes"][:15]))
        if result["orphans"]:
            print("orphans: " + ", ".join(f"{k} {v}" for k, v in result["orphans"]))
    elif command == "profile" and not raw_json and isinstance(result, dict):
        print(f"# {result['samples']} samples: frame {result['frame_ms_per_sample']} ms, script {result['script_ms_per_sample']} ms per sample")
        for row in result["functions"]:
            print(f"{row['self_ms_per_sample']:>9.3f} self {row['total_ms_per_sample']:>9.3f} total ms  {row['calls']:>8} calls  {row['function']}")
    elif command == "logs" and not raw_json and isinstance(result, dict) and "groups" in result:
        for group in result["groups"]:
            where = f" [{group['script']}]" if group["script"] else ""
            print(f"{group['count']:>6}x {group['level']:<12} {group['text']}{where}")
    elif command == "methods" and not raw_json and isinstance(result, dict):
        print(f"# {result['node']} ({result['script']})")
        print("\n".join(result["methods"]))
    else:
        print(json.dumps(result, indent=1 if pretty else None, ensure_ascii=False))


def short_path(path: str, scope: str) -> str:
    """The path below the scope, generated @Type@123 segments elided: readable and cheap; --paths prints it whole."""
    if scope and path.startswith(scope + "/"):
        path = path[len(scope) + 1:]
    parts = [p for p in path.split("/") if not (p.startswith("@") and p.count("@") >= 2)]
    return "/".join(parts[-3:]) if len(parts) > 3 else "/".join(parts)


def print_ui(result: dict, full_paths: bool = False) -> None:
    """One line per control: focus mark, type, quoted label, state, path. Labels are what press text= takes."""
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
        shown = item["path"] if full_paths else short_path(item["path"], result["scope"])
        print(f"{mark} {item['type']:<13} {json.dumps(item['text'], ensure_ascii=False):<34} {' '.join(state):<16} {shown}")


def main(argv: list[str]) -> int:
    if not argv or "-h" in argv or "--help" in argv:  # never contacts an app, whatever comes before it
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
        if command == "timeline":
            return timeline(rest)
        if command == "run":
            return run_script(rest)
        if command == "repl":
            return repl()
        if command == "crawl":
            return crawl(rest)
        if command == "soak":
            return soak(rest)
        if command == "monkey":
            return monkey(rest)
        if command == "smoke":
            return smoke(rest)
        if command == "ready":
            timeout = float(rest[rest.index("--timeout") + 1]) if "--timeout" in rest else 60.0
            print(json.dumps(wait_ready(timeout)["result"]))
            return 0
        others = ambiguous_target()
        if others:
            print(f"debugctl: {len(others)} live sessions on ports {others}: which one is yours? Repeat with "
                  f"OPENRC_DEBUG_BRIDGE=<port> {Path(sys.argv[0]).name} {command} …", file=sys.stderr)
            return 2
        flags = [w for w in rest if w in ("--pretty", "--json", "--paths")]
        result = result_of(command, parse_args([w for w in rest if w not in flags]))
    except Refused as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    except BrokenPipeError:
        raise
    except (OSError, TimeoutError, ValueError) as error:
        print(f"debugctl: {error}", file=sys.stderr)
        return 2
    show(command, result, "--pretty" in flags, "--json" in flags, "--paths" in flags)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except BrokenPipeError:  # e.g. `watch ... | head`: the reader left; that is not an error
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        sys.exit(0)
