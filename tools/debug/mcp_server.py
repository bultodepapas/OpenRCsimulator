#!/usr/bin/env python3
"""MCP server for the OpenRC simulator (PT1h-R11): coding agents drive the running app through typed tools.

Model Context Protocol over stdio (newline-delimited JSON-RPC 2.0), standard library only, on top of debugctl.py and
the debug bridge. Design after Playwright MCP: `sim_look` returns an accessibility-style snapshot whose refs (e12) the
action tools take, and every action answers with the fresh snapshot, so an agent rarely needs a second call.

Register (Claude Code):  claude mcp add openrc-sim -- python3 tools/debug/mcp_server.py
The repository's .mcp.json declares it too. Guide: tools/debug/README.md#agents-and-mcp-pt1h-r11.
stdout carries only protocol messages; everything debugctl prints is captured into the tool result.
"""
from __future__ import annotations

import base64
import contextlib
import io
import json
import math
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import debugctl  # noqa: E402

SERVER = {"name": "openrc-sim", "version": "1.0.0"}
PROTOCOLS = ("2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05")
INSTRUCTIONS = (
    "Drives the running OpenRC RC-flight simulator. Start with sim_launch (unless one is running), then sim_look: "
    "it lists every visible control with a ref, its role, name, value and options, plus suggested next steps. Act "
    "with sim_press / sim_choose (by ref from the latest look, or by field/text), sim_close, sim_open, sim_setup + "
    "sim_fly, sim_sticks, sim_key. Each action returns the new snapshot. sim_catalog lists valid ids. "
    "sim_command reaches any other bridge command (help lists them). Stop the app with sim_stop when done.")

LOOKUP = {"ref": {"type": "string", "description": "control ref from the latest sim_look, e.g. e12"},
          "field": {"type": "string", "description": "a field's name as sim_look shows it, e.g. Window resolution"},
          "text": {"type": "string", "description": "a visible label, e.g. FLY"}}


def _schema(properties: dict | None = None, required: list[str] | None = None) -> dict:
    schema = {"type": "object", "properties": properties or {}, "additionalProperties": False}
    if required:
        schema["required"] = required
    return schema


TOOLS = [
    {"name": "sim_launch", "description": "Start the simulator with its debug bridge (Home screen). headless=true is "
     "light and has no pictures; the default renders 1920x1080 for screenshots.",
     "inputSchema": _schema({"headless": {"type": "boolean"}, "resolution": {"type": "string", "description": "WxH"}})},
    {"name": "sim_stop", "description": "Quit the simulator this server launched (or the session it targets).",
     "inputSchema": _schema()},
    {"name": "sim_look", "description": "What is on screen now: route, screens, flight summary, every visible control "
     "as ref/role/name/value/options, and next steps. Refs stay valid while their control exists.",
     "inputSchema": _schema({"all": {"type": "boolean", "description": "every control, not only the top screen"}})},
    {"name": "sim_press", "description": "Activate a button (or toggle) like Enter on it. Returns the new snapshot.",
     "inputSchema": _schema(LOOKUP)},
    {"name": "sim_choose", "description": "Set any widget: an option or tab by item label, a toggle on/off, a slider "
     "or number, a text field. Returns the new snapshot.",
     "inputSchema": _schema({**LOOKUP, "value": {"type": ["string", "number", "boolean"]}}, ["value"])},
    {"name": "sim_close", "description": "Close the top dialog or menu (Esc/Back).", "inputSchema": _schema()},
    {"name": "sim_open", "description": "Open a screen directly: pause, settings, controls, help, weather, "
     "time_of_day, overlays, failures, companions, natural_random, workshop.",
     "inputSchema": _schema({"screen": {"type": "string"}}, ["screen"])},
    {"name": "sim_catalog", "description": "Valid ids: aircraft (with starts), landscapes, time_of_day presets, "
     "languages, screens, camera views, and the current Home selection.", "inputSchema": _schema()},
    {"name": "sim_setup", "description": "On Home: choose aircraft, start, landscape, time of day, language; each "
     "value is validated and read back.",
     "inputSchema": _schema({"aircraft": {"type": "string"}, "start": {"type": "string", "enum": ["runway", "airborne", "hand_launch"]},
                             "landscape": {"type": "string"}, "time_of_day": {"type": "string"}, "language": {"type": "string"}})},
    {"name": "sim_fly", "description": "From Home: start a flight (optionally choosing aircraft and start) and, with "
     "ready=true (default), close the launch menu and resume so the aircraft flies.",
     "inputSchema": _schema({"aircraft": {"type": "string"}, "start": {"type": "string"}, "ready": {"type": "boolean"}})},
    {"name": "sim_home", "description": "End the activity and return to Home.", "inputSchema": _schema()},
    {"name": "sim_state", "description": "Full state: route, screens, focus, flight pose, commands, pause and crash.",
     "inputSchema": _schema()},
    {"name": "sim_sticks", "description": "Fly with stick values: roll/pitch/yaw -1..1 (pitch + = nose up), throttle "
     "0..1, for for_s simulated seconds; release=true hands back to the keyboard.",
     "inputSchema": _schema({"roll": {"type": "number"}, "pitch": {"type": "number"}, "yaw": {"type": "number"},
                             "throttle": {"type": "number"}, "for_s": {"type": "number"}, "release": {"type": "boolean"}})},
    {"name": "sim_key", "description": "Press a key or shortcut (W, Escape, F2, Shift+C ...); sim_command shortcuts lists them.",
     "inputSchema": _schema({"name": {"type": "string"}, "hold_s": {"type": "number"}}, ["name"])},
    {"name": "sim_screenshot", "description": "A JPEG of the window (rendered sessions only).",
     "inputSchema": _schema({"max_width": {"type": "integer", "description": "default 1280"}})},
    {"name": "sim_bugit", "description": "File a reproducible bug report folder (state, logs, render numbers, "
     "screenshot, exact flight checkpoint).", "inputSchema": _schema({"note": {"type": "string"}})},
    {"name": "sim_command", "description": "Any debug bridge command by name with its arguments (help lists them: "
     "frames, render, ablate, rewind, gizmos, break, sample, eval, ...).",
     "inputSchema": _schema({"command": {"type": "string"}, "args": {"type": "object"}}, ["command"])},
]
TOOL_BY_NAME = {tool["name"]: tool for tool in TOOLS}


class ToolError(Exception):
    pass


def _check_arguments(tool: dict, args: dict) -> None:
    """Enforce the flat type/required/enum contracts declared by this server."""
    schema = tool["inputSchema"]
    properties = schema["properties"]
    missing = set(schema.get("required", ())) - args.keys()
    if missing:
        raise ToolError("missing required arguments: " + ", ".join(sorted(missing)))
    unexpected = args.keys() - properties.keys()
    if unexpected:
        raise ToolError("unknown arguments: " + ", ".join(sorted(unexpected)))
    for key, value in args.items():
        declaration = properties[key]
        expected = declaration["type"]
        choices = expected if isinstance(expected, list) else [expected]
        matches = {
            "string": isinstance(value, str),
            "boolean": type(value) is bool,
            "object": isinstance(value, dict),
            "number": type(value) is int or (type(value) is float and math.isfinite(value)),
            "integer": type(value) is int or (type(value) is float and math.isfinite(value) and value.is_integer()),
        }
        if not any(matches[choice] for choice in choices):
            raise ToolError(f"{key} must be " + " or ".join(choices))
        if "enum" in declaration and value not in declaration["enum"]:
            raise ToolError(f"{key} must be one of: " + ", ".join(map(str, declaration["enum"])))


def _bridge(command: str, args: dict | None = None, timeout: float = 600.0):
    try:
        return debugctl.result_of(command, args or {}, timeout=timeout)
    except debugctl.Refused as error:
        raise ToolError(f"{command} refused: {error}") from None
    except (OSError, TimeoutError) as error:
        raise ToolError(f"no simulator answers ({error}); call sim_launch first") from None


def _look_text() -> str:
    return debugctl.format_look(_bridge("look"))


def _lookup(args: dict) -> dict:
    picked = {key: args[key] for key in ("ref", "field", "text") if key in args}
    if not picked:
        raise ToolError("name the control: ref (from sim_look), field or text")
    return picked


def _captured(function, argv: list[str]) -> tuple[int, str]:
    out = io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
        status = function(argv)
    return status, out.getvalue()


def _then_look(summary) -> list[dict]:
    head = summary if isinstance(summary, str) else json.dumps(summary, ensure_ascii=False)
    return [_text(head + "\n\n" + _look_text())]


def _text(text: str) -> dict:
    return {"type": "text", "text": text}


def call_tool(name: str, args: dict) -> list[dict]:
    if name == "sim_launch":
        argv = ["--headless"] if args.get("headless") else []
        if args.get("resolution"):
            argv += ["--resolution", str(args["resolution"])]
        status, printed = _captured(debugctl.launch, argv)
        if status != 0:
            raise ToolError("launch failed: " + printed[-2000:])
        for line in printed.splitlines():
            with contextlib.suppress(ValueError):
                launched = json.loads(line)
                if isinstance(launched, dict) and "port" in launched:
                    os.environ["OPENRC_DEBUG_BRIDGE"] = str(launched["port"])  # this server's own session
        return _then_look(printed.strip().splitlines()[-1] if printed.strip() else "launched")
    if name == "sim_stop":
        status, printed = _captured(debugctl.stop, [])
        if status != 0:
            raise ToolError(f"stop failed (exit {status}): " + printed.strip()[-2000:])
        return [_text(printed.strip() or f"stop exited {status}")]
    if name == "sim_look":
        return [_text(debugctl.format_look(_bridge("look", {"all": bool(args.get("all"))})))]
    if name == "sim_press":
        return _then_look(_bridge("press", _lookup(args)))
    if name == "sim_choose":
        return _then_look(_bridge("choose", {**_lookup(args), "value": args["value"]}))
    if name == "sim_close":
        return _then_look(_bridge("close"))
    if name == "sim_open":
        return _then_look(_bridge("open", {"screen": args["screen"]}))
    if name == "sim_catalog":
        return [_text(json.dumps(_bridge("catalog"), ensure_ascii=False))]
    if name == "sim_setup":
        return _then_look(_bridge("setup", {k: v for k, v in args.items() if v is not None}))
    if name == "sim_fly":
        flown = _bridge("fly", {k: args[k] for k in ("aircraft", "start") if args.get(k)}, timeout=300.0)
        if args.get("ready", True):
            for _ in range(3):  # the launch review / pause menu holds a new flight
                if not [s for s in _bridge("state", {"fresh": True}).get("screens", []) if s != "home"]:
                    break
                with contextlib.suppress(ToolError):
                    _bridge("close")
            with contextlib.suppress(ToolError):
                flown = _bridge("resume")
        return _then_look(flown)
    if name == "sim_home":
        return _then_look(_bridge("home", timeout=120.0))
    if name == "sim_state":
        return [_text(json.dumps(_bridge("state", {"fresh": True}), ensure_ascii=False))]
    if name == "sim_sticks":
        return [_text(json.dumps(_bridge("sticks", {k: v for k, v in args.items() if v is not None})))]
    if name == "sim_key":
        return _then_look(_bridge("key", {k: v for k, v in args.items() if v is not None}))
    if name == "sim_screenshot":
        folder = debugctl.RUNS / "mcp"
        folder.mkdir(parents=True, exist_ok=True)
        path = folder / f"shot-{time.strftime('%Y%m%d-%H%M%S')}-{os.getpid()}.jpg"
        shot = _bridge("screenshot", {"path": str(path), "format": "jpg", "max_width": int(args.get("max_width", 1280))})
        data = Path(shot["path"]).read_bytes()
        return [{"type": "image", "data": base64.b64encode(data).decode("ascii"), "mimeType": "image/jpeg"},
                _text(f"{shot['path']} ({shot.get('width')}x{shot.get('height')})")]
    if name == "sim_bugit":
        argv = ["--note", str(args["note"])] if args.get("note") else []
        status, printed = _captured(debugctl.bugit, argv)
        if status != 0:
            raise ToolError(printed[-2000:])
        return [_text(printed.strip())]
    if name == "sim_command":
        result = _bridge(str(args["command"]), args.get("args") or {})
        if args["command"] == "look":
            return [_text(debugctl.format_look(result))]
        return [_text(json.dumps(result, ensure_ascii=False, default=str))]
    raise KeyError(name)


def _rpc_error(message_id: str | int | None, code: int, detail: str) -> dict:
    return {"jsonrpc": "2.0", "id": message_id, "error": {"code": code, "message": detail}}


def handle(message: object) -> dict | None:
    """One JSON-RPC message in, the reply out (None for notifications)."""
    if not isinstance(message, dict):
        return _rpc_error(None, -32600, "request must be an object")
    message_id = message.get("id")
    valid_id = type(message_id) in (str, int)  # MCP excludes null, bool and fractional IDs.
    if message.get("jsonrpc") != "2.0" or not isinstance(message.get("method"), str):
        return _rpc_error(message_id if valid_id else None, -32600, "invalid JSON-RPC request")
    if "id" in message and not valid_id:
        return _rpc_error(None, -32600, "request id must be a string or integer")
    method = message.get("method")
    if "id" not in message:
        return None  # notifications/initialized, cancellations: nothing to answer
    reply = {"jsonrpc": "2.0", "id": message["id"]}
    params = message.get("params", {})
    if not isinstance(params, dict):
        return _rpc_error(message_id, -32602, "params must be an object")
    if method == "initialize":
        asked = params.get("protocolVersion")
        reply["result"] = {"protocolVersion": asked if asked in PROTOCOLS else PROTOCOLS[0],
                           "capabilities": {"tools": {"listChanged": False}}, "serverInfo": SERVER,
                           "instructions": INSTRUCTIONS}
    elif method == "ping":
        reply["result"] = {}
    elif method == "tools/list":
        reply["result"] = {"tools": TOOLS}
    elif method == "tools/call":
        name = params.get("name", "")
        if not isinstance(name, str):
            return _rpc_error(message_id, -32602, "tool name must be a string")
        if name not in TOOL_BY_NAME:
            reply["error"] = {"code": -32602, "message": f"unknown tool {name}"}
            return reply
        arguments = params.get("arguments", {})
        if not isinstance(arguments, dict):
            return _rpc_error(message_id, -32602, "tool arguments must be an object")
        try:
            _check_arguments(TOOL_BY_NAME[name], arguments)
            reply["result"] = {"content": call_tool(name, arguments), "isError": False}
        except ToolError as error:
            reply["result"] = {"content": [_text(str(error))], "isError": True}
        except Exception as error:  # a tool bug must not end the server
            reply["result"] = {"content": [_text(f"{type(error).__name__}: {error}")], "isError": True}
    else:
        reply["error"] = {"code": -32601, "message": f"method not found: {method}"}
    return reply


def serve(stdin=sys.stdin, stdout=sys.stdout) -> None:
    for line in stdin:
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except (ValueError, RecursionError):
            stdout.write(json.dumps({"jsonrpc": "2.0", "id": None,
                                     "error": {"code": -32700, "message": "parse error"}}) + "\n")
            stdout.flush()
            continue
        reply = handle(message)
        if reply is not None:
            # JSON escaping also keeps an accepted escaped surrogate from
            # raising UnicodeEncodeError on the strict UTF-8 stdio stream.
            stdout.write(json.dumps(reply, ensure_ascii=True) + "\n")
            stdout.flush()


if __name__ == "__main__":
    # MCP messages are UTF-8; a Windows console default (cp1252) cannot encode labels such as "1920 × 1080".
    sys.stdin.reconfigure(encoding="utf-8")
    sys.stdout.reconfigure(encoding="utf-8")
    serve()
