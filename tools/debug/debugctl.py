#!/usr/bin/env python3
"""Drive a running OpenRC app through its debug bridge (PT1h-R7). Standard library only.

  debugctl.py launch [--headless] [--out DIR] [-- <app user args>]   start the app with the bridge, wait until ready
  debugctl.py ready [--timeout S]                                    wait until the bridge answers
  debugctl.py logs [--since N] [--level error,warning] [--follow]    print engine/script log records
  debugctl.py stop                                                   ask the app to quit
  debugctl.py <command> [key=value ...]                              any bridge command; `help` lists them

Values are parsed as JSON when possible (true, 3, 0.5, "x"), else kept as strings. One TCP connection per call.
Exit status: 0 ok, 1 the bridge answered ok=false, 2 usage or connection error. Guide: tools/debug/README.md.
"""
from __future__ import annotations

import datetime
import json
import os
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path

DEFAULT_PORT = 47870
REPO = Path(__file__).resolve().parents[2]


def port() -> int:
    value = os.environ.get("OPENRC_DEBUG_BRIDGE", "")
    return int(value) if value.isdigit() and int(value) > 1 else DEFAULT_PORT


def parse_value(text: str):
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return text


def request(cmd: str, args: dict | None = None, timeout: float = 120.0) -> dict:
    payload = {"id": 1, "cmd": cmd, **(args or {})}
    token = os.environ.get("OPENRC_DEBUG_TOKEN")
    if token:
        payload["token"] = token
    with socket.create_connection(("127.0.0.1", port()), timeout=timeout) as conn:
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


def wait_ready(timeout: float, process: subprocess.Popen | None = None) -> dict:
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        if process is not None and process.poll() is not None:
            raise RuntimeError(f"the app exited with status {process.returncode} before the bridge answered")
        try:
            return request("ping", timeout=2.0)
        except OSError as error:
            last = error
            time.sleep(0.25)
    raise TimeoutError(f"no bridge on 127.0.0.1:{port()} after {timeout:.0f} s ({last})")


def godot() -> str:
    return subprocess.run([str(REPO / "app" / "get-godot.sh")], check=True, capture_output=True, text=True).stdout.strip()


def launch(argv: list[str]) -> int:
    headless = "--headless" in argv
    out = None
    timeout = 120.0
    app_args: list[str] = []
    if "--" in argv:
        split = argv.index("--")
        argv, app_args = argv[:split], argv[split + 1:]
    for i, arg in enumerate(argv):
        if arg == "--out":
            out = Path(argv[i + 1])
        elif arg == "--timeout":
            timeout = float(argv[i + 1])
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    out = (out or REPO / "tmp" / "debug-bridge" / stamp).resolve()
    out.mkdir(parents=True, exist_ok=False)
    try:
        request("ping", timeout=1.0)
        print(f"a bridge already answers on port {port()}; stop it or set OPENRC_DEBUG_BRIDGE=<other port>", file=sys.stderr)
        return 2
    except OSError:
        pass
    command = [godot(), "--path", str(REPO / "app")]
    if headless:
        command += ["--headless", "--audio-driver", "Dummy"]
    elif not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY") and os.name != "nt":
        xvfb = shutil.which("xvfb-run")
        if xvfb is None:
            print("no display and no xvfb-run: use --headless (no screenshots)", file=sys.stderr)
            return 2
        command = [xvfb, "-a", "-s", "-screen 0 1920x1080x24"] + command + ["--audio-driver", "Dummy"]
    if app_args:
        command += ["--"] + app_args
    env = dict(os.environ, OPENRC_DEBUG_BRIDGE=str(port()), OPENRC_DEBUG_LOG=str(out / "log.jsonl"))
    with open(out / "engine.log", "wb") as engine_log:
        process = subprocess.Popen(command, cwd=REPO, env=env, stdout=engine_log, stderr=subprocess.STDOUT,
                                   stdin=subprocess.DEVNULL, start_new_session=True)
    (out / "launch.json").write_text(json.dumps({"pid": process.pid, "port": port(), "command": command}, indent=2) + "\n")
    try:
        ready = wait_ready(timeout, process)
    except (RuntimeError, TimeoutError) as error:
        print(f"{error}; see {out / 'engine.log'}", file=sys.stderr)
        return 2
    print(json.dumps({"ok": True, "out": str(out), "launcher_pid": process.pid, "port": port(), **ready["result"]}))
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
            reply = request("logs", args, timeout=10.0)
        except OSError:
            if follow:
                return 0  # the app quit
            raise
        for record in reply["result"]["records"]:
            where = f" [{record['script']}]" if "script" in record else ""
            print(f"{record['seq']:>6} {record['level']:<12} {record['text']}{where}", flush=True)
            since = record["seq"]
        if not follow:
            print(f"# last_seq {reply['result']['last_seq']}, dropped {reply['result']['dropped']}", file=sys.stderr)
            return 0
        time.sleep(0.25)


def main(argv: list[str]) -> int:
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0 if argv else 2
    command, rest = argv[0], argv[1:]
    try:
        if command == "launch":
            return launch(rest)
        if command == "logs":
            return logs(rest)
        if command == "ready":
            timeout = float(rest[rest.index("--timeout") + 1]) if "--timeout" in rest else 60.0
            print(json.dumps(wait_ready(timeout)["result"]))
            return 0
        if command == "stop":
            command = "quit"
        pretty = "--pretty" in rest
        raw_json = "--json" in rest
        rest = [item for item in rest if item not in ("--pretty", "--json")]
        args = {}
        for item in rest:
            if "=" not in item:
                print(f"expected key=value, got '{item}'", file=sys.stderr)
                return 2
            key, value = item.split("=", 1)
            args[key] = parse_value(value)
        reply = request(command, args)
    except (OSError, TimeoutError, ValueError) as error:
        print(f"debugctl: {error}", file=sys.stderr)
        return 2
    if not reply.get("ok"):
        print(f"error: {reply.get('error')}", file=sys.stderr)
        return 1
    result = reply.get("result")
    if command == "ui" and not raw_json and isinstance(result, dict):
        print_ui(result)
    else:
        print(json.dumps(result, indent=1 if pretty else None, ensure_ascii=False))
    return 0


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


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
