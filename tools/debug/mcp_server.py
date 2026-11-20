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
import queue
import sys
import threading
import time
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import debugctl  # noqa: E402

SERVER = {"name": "openrc-sim", "version": "1.2.0"}
PROTOCOLS = ("2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05")
INSTRUCTIONS = (
    "Drives the running OpenRC RC-flight simulator. Start with sim_launch (unless one is running), then sim_look: "
    "it lists every visible control with a ref, its role, name, value and options, plus suggested next steps. Act "
    "with sim_press / sim_choose (by ref from the latest look, or by field/text), sim_close, sim_open, sim_setup + "
    "sim_fly, sim_sticks, sim_key. Each action returns the new snapshot. sim_catalog lists valid ids. "
    "sim_command reaches any other bridge command (help lists them). Stop the app with sim_stop when done.")
INSTRUCTIONS += (" On an enrolled shared host, launch and control use the host test queue. This server retains "
                 "its own session handle; a fresh client must launch its own session or explicitly provide "
                 "OPENRC_TESTQUEUE_HANDLE. A bridge port alone is not ownership. A queued launch stays owned: "
                 "use sim_session_status to check readiness and sim_stop to cancel it.")

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
     "light and has no pictures; the default renders 1920x1080 for screenshots. Sessions are silent unless "
     "sound=true.",
     "inputSchema": _schema({"headless": {"type": "boolean"}, "resolution": {"type": "string", "description": "WxH"},
                             "sound": {"type": "boolean", "description": "play audio (default: muted)"}})},
    {"name": "sim_stop", "description": "Quit the simulator this server launched (or the session it targets).",
     "inputSchema": _schema()},
    {"name": "sim_session_status", "description": "Check the status of this server's admitted shared-host "
     "session, including a queued launch. The returned handle can recover ownership in another client.",
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
    {"name": "sim_frames", "description": "Frame pacing and stutter diagnostics: 1%/0.1% lows, frame-time tails, "
     "target-FPS budget overruns, slow runs and bounded event evidence. Changing thresholds or reset=true starts "
     "a fresh epoch. samples=true adds up to 7200 chronological samples; prefer ordinary summaries while flying. "
     "Wall intervals are not display presentation; GPU readings and counter changes do not prove causes.",
     "inputSchema": _schema({"window": {"type": "integer"}, "events": {"type": "integer"},
                             "target_fps": {"type": "number"}, "budget_tolerance_ms": {"type": "number"},
                             "stutter_factor": {"type": "number"}, "stutter_min_extra_ms": {"type": "number"},
                             "stall_ms": {"type": "number"}, "hitch_ms": {"type": "number"},
                             "factor": {"type": "number"}, "reset": {"type": "boolean"},
                             "samples": {"type": "boolean"}})},
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
TOOLS += [
    {"name": "sim_test_launch", "description": "Start independent headless checked tests in the shared Windows/Mac/Linux pool. "
     "Returns a durable ticket immediately; source freezing, placement and verified artifact collection run in a detached supervisor. "
     "Reuse your stable request_id after a lost reply. Platform defaults to caller OS; choose any only for portable tests. "
     "A job with rendering_driver (vulkan|opengl3) renders on a real GPU host (sim_fleet capability 'graphics'; "
     "Linux Intel UHD 630 on 'primis') at 1920x1080 under headless Wayland and fails unless that GPU was used. "
     "Use existing native tools for performance and composite suites.",
     "inputSchema": _schema({"request_id": {"type": "string"}, "source": {"type": "string"},
         "jobs": {"type": "array", "minItems": 1, "maxItems": 64, "items": _schema({
             "script": {"type": "string"}, "platform": {"type": "string", "enum": ["any", "windows", "linux", "darwin"]},
             "require": {"type": "array", "items": {"type": "string"}}, "timeout": {"type": "number"},
             "host": {"type": "string"},
             "rendering_driver": {"type": "string", "enum": ["vulkan", "opengl3"]}}, ["script"])}}, ["request_id", "jobs"])},
    {"name": "sim_test_run", "description": "The usual way to run checked tests: launch them and wait up to wait_s "
     "(default 60, max 300) for the result in one call. Returns the compact status: per test outcome, host, seconds, "
     "failing log lines, or a typed waiting reason. If still running, call it again with the returned request_id "
     "(or sim_test_status). request_id is optional; omit it for a new run. Waiting never cancels the tests. "
     "Platform defaults to caller OS; choose any only for portable tests. Add rendering_driver (vulkan|opengl3) "
     "with platform linux to render on the real GPU lane (host primis) instead of headless.",
     "inputSchema": _schema({"request_id": {"type": "string"}, "source": {"type": "string"},
         "wait_s": {"type": "number"},
         "jobs": {"type": "array", "minItems": 1, "maxItems": 64, "items": _schema({
             "script": {"type": "string"}, "platform": {"type": "string", "enum": ["any", "windows", "linux", "darwin"]},
             "require": {"type": "array", "items": {"type": "string"}}, "timeout": {"type": "number"},
             "host": {"type": "string"},
             "rendering_driver": {"type": "string", "enum": ["vulkan", "opengl3"]}}, ["script"])}}, ["jobs"])},
    {"name": "sim_test_status", "description": "Read cached test-pool progress. Default detail=summary: summary "
     "(counts, next_action, waiting codes), then one line per test with outcome, host, seconds, failing log lines "
     "or a typed waiting reason and the alternative. detail=full adds the authoritative rows. No SSH or waiting. "
     "Only result PASSED with verified evidence qualifies a batch.",
     "inputSchema": _schema({"request_id": {"type": "string"},
                             "detail": {"type": "string", "enum": ["summary", "full"]}}, ["request_id"])},
    {"name": "sim_fleet", "description": "Which test hosts are online, idle or busy (typed cause), their disk/RAM/"
     "load, active pool jobs, and every Godot process on this machine (unmanaged ones block the local host). Cached "
     "about 15 s; refresh=true probes now (a few seconds).",
     "inputSchema": _schema({"refresh": {"type": "boolean"}})},
    {"name": "sim_test_list", "description": "Recent test requests with one-line results, newest first, so a new "
     "session can find its earlier work.", "inputSchema": _schema({"limit": {"type": "integer"}})},
    {"name": "sim_test_recover", "description": "Resume a stopped test supervisor using the same frozen snapshot and job IDs/hosts. "
     "Does not rerun failed tests or cancel remote jobs. Returns immediately; inspect sim_test_status.",
     "inputSchema": _schema({"request_id": {"type": "string"}}, ["request_id"])},
]
INSTRUCTIONS += (" For independent checked headless regression tests call sim_test_run with jobs: it launches and "
                 "waits for the compact result in one call (repeat it with the returned request_id while still running). "
                 "sim_fleet shows which hosts are online/idle and why others are busy; sim_test_list finds earlier requests. "
                 "sim_test_launch (stable caller-generated request_id) + sim_test_status remain for detached batches. "
                 "Compatible tests are placed automatically across the configured pool. "
                 "Declare platform=any only for portable checks; otherwise keep native coverage. Evidence is collected automatically. "
                 "Use sim_test_recover on a stopped supervisor, preserving the same request. For a Linux real-GPU rendering check "
                 "add rendering_driver (vulkan or opengl3) with platform linux; it runs on a host with the graphics capability. "
                 "Performance checks keep their native workflows.")
INSTRUCTIONS += (" Protocol requests and cached sim_test_status can be serviced during a long tool call. Simulator "
                 "tools, including sim_stop, execute in order: a stop can wait behind an earlier tool. A busy error "
                 "means the request was not accepted. Request cancellation notifications are ignored and do not "
                 "cancel accepted work. sim_stop requests owned simulator-session cancellation in its normal order. "
                 "Use a new JSON-RPC id for each request; reuse a durable test request_id only to recover that work. "
                 "On input EOF, accepted calls finish, then reply delivery gets at most 0.5 seconds to drain. "
                 "A slow reader may lose replies, including partial replies, even if the queue never fills. If the "
                 "reply queue fills, delivery is abandoned, but accepted calls still run. Recover durable work by "
                 "its original request identity or retained session handle.")
TOOL_BY_NAME = {tool["name"]: tool for tool in TOOLS}

# Limits apply independently to the ordered tool lane, cached-status lane and
# outgoing replies. A blocked filesystem or client can apply backpressure, but
# cannot create an unbounded number of workers or queued messages.
TOOL_QUEUE_LIMIT = 32
STATUS_QUEUE_LIMIT = 8
TEST_QUEUE_LIMIT = 16
# Test-pool calls touch only durable receipts (no process-global stdout or
# environment), so they get their own lane and never wait behind a long
# simulator call. Four workers let waiting sim_test_run calls coexist with launches.
TEST_LANE = {"sim_test_launch", "sim_test_recover", "sim_test_run", "sim_fleet", "sim_test_list"}
TEST_WORKERS = 4
OUTPUT_QUEUE_LIMIT = 64
MAX_INPUT_CHARS = 1024 * 1024
OUTPUT_ENQUEUE_SECONDS = 0.2
OUTPUT_DRAIN_SECONDS = 0.5


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
            "array": isinstance(value, list),
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
    if name.startswith("sim_test_") or name == "sim_fleet":
        from tools.testqueue import pool_mcp
        action = {"sim_test_launch": pool_mcp.launch, "sim_test_status": pool_mcp.status,
                  "sim_test_recover": pool_mcp.recover, "sim_test_run": pool_mcp.run,
                  "sim_fleet": pool_mcp.fleet, "sim_test_list": pool_mcp.list_requests}[name]
        try:
            return [_text(json.dumps(action(**args), ensure_ascii=False, default=str))]
        except ValueError as error:
            raise ToolError(str(error)) from None
    if name == "sim_launch":
        argv = ["--headless"] if args.get("headless") else []
        if args.get("resolution"):
            argv += ["--resolution", str(args["resolution"])]
        if not args.get("sound"):
            argv += ["--mute"]  # agent-driven sessions run on someone's desk: silent unless asked
        engine_argv = argv[:argv.index("--")] if "--" in argv else argv
        if debugctl.admission.enabled() and not debugctl.admission.inherited(
                "headless" if "--headless" in engine_argv else "rendered"):
            from tools.testqueue.integration import open_debug
            # The stdio server handles one message at a time. Return after
            # acceptance so status and cancellation can be requested promptly.
            launch = lambda values: open_debug(values, debugctl.REPO, wait_timeout=0)
        else:
            launch = debugctl.launch
        before = os.environ.get("OPENRC_TESTQUEUE_HANDLE")
        try:
            status, printed = _captured(launch, argv)
        except Exception as error:
            receipt = os.environ.get("OPENRC_TESTQUEUE_SUBMISSION")
            if receipt:
                raise ToolError(f"launch submission is unresolved ({error}); recovery receipt: {receipt}. "
                                "Use sim_session_status, retry the same sim_launch, or sim_stop; "
                                "this server retains the original request identity") from None
            handle = os.environ.get("OPENRC_TESTQUEUE_HANDLE")
            if handle and handle != before:
                raise ToolError(f"launch was accepted but status is unavailable ({error}); "
                                f"use sim_session_status or sim_stop with handle {handle}") from None
            raise
        if status != 0:
            raise ToolError("launch failed: " + printed[-2000:])
        launched = None
        for line in printed.splitlines():
            with contextlib.suppress(ValueError):
                parsed = json.loads(line)
                if isinstance(parsed, dict):
                    launched = parsed
                    if "port" in parsed:
                        os.environ["OPENRC_DEBUG_BRIDGE"] = str(parsed["port"])  # this server's own session
        if launched and "job" in launched and "port" not in launched:
            return [_text(json.dumps(launched, ensure_ascii=False))]
        return _then_look(printed.strip().splitlines()[-1] if printed.strip() else "launched")
    if name == "sim_stop":
        status, printed = _captured(debugctl.stop, [])
        if status != 0:
            raise ToolError(f"stop failed (exit {status}): " + printed.strip()[-2000:])
        return [_text(printed.strip() or f"stop exited {status}")]
    if name == "sim_session_status":
        from tools.testqueue.integration import debug_status
        return [_text(json.dumps(debug_status(), ensure_ascii=False))]
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
    if name == "sim_frames":
        return [_text(json.dumps(_bridge("frames", args), ensure_ascii=False))]
    if name == "sim_sticks":
        return [_text(json.dumps(_bridge("sticks", {k: v for k, v in args.items() if v is not None})))]
    if name == "sim_key":
        return _then_look(_bridge("key", {k: v for k, v in args.items() if v is not None}))
    if name == "sim_screenshot":
        folder = debugctl.RUNS / "mcp"
        folder.mkdir(parents=True, exist_ok=True)
        path = folder / f"shot-{time.strftime('%Y%m%d-%H%M%S')}-{os.getpid()}-{uuid.uuid4().hex}.jpg"
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


def _prepare(message: object) -> tuple[dict | None, tuple[str, dict] | None]:
    """Validate without executing a tool; return a reply and an optional invocation."""
    if not isinstance(message, dict):
        return _rpc_error(None, -32600, "request must be an object"), None
    message_id = message.get("id")
    valid_id = type(message_id) in (str, int)  # MCP excludes null, bool and fractional IDs.
    if message.get("jsonrpc") != "2.0" or not isinstance(message.get("method"), str):
        return _rpc_error(message_id if valid_id else None, -32600, "invalid JSON-RPC request"), None
    if "id" in message and not valid_id:
        return _rpc_error(None, -32600, "request id must be a string or integer"), None
    method = message.get("method")
    if "id" not in message:
        return None, None  # Notifications do not invoke a tool or cancel owned work.
    reply = {"jsonrpc": "2.0", "id": message["id"]}
    params = message.get("params", {})
    if not isinstance(params, dict):
        return _rpc_error(message_id, -32602, "params must be an object"), None
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
            return _rpc_error(message_id, -32602, "tool name must be a string"), None
        if name not in TOOL_BY_NAME:
            reply["error"] = {"code": -32602, "message": f"unknown tool {name}"}
            return reply, None
        arguments = params.get("arguments", {})
        if not isinstance(arguments, dict):
            return _rpc_error(message_id, -32602, "tool arguments must be an object"), None
        try:
            _check_arguments(TOOL_BY_NAME[name], arguments)
        except ToolError as error:
            reply["result"] = {"content": [_text(str(error))], "isError": True}
            return reply, None
        return reply, (name, arguments)
    else:
        reply["error"] = {"code": -32601, "message": f"method not found: {method}"}
    return reply, None


def _invoke(reply: dict, invocation: tuple[str, dict]) -> dict:
    try:
        reply["result"] = {"content": call_tool(*invocation), "isError": False}
    except ToolError as error:
        reply["result"] = {"content": [_text(str(error))], "isError": True}
    except Exception as error:  # a tool bug must not end the server
        reply["result"] = {"content": [_text(f"{type(error).__name__}: {error}")], "isError": True}
    return reply


def handle(message: object) -> dict | None:
    """One JSON-RPC message in, the reply out (None for notifications)."""
    reply, invocation = _prepare(message)
    return _invoke(reply, invocation) if invocation is not None else reply


def _input_lines(stdin):
    """Read bounded chunks and discard an oversized line before continuing."""
    if not hasattr(stdin, "readline"):
        # Also support callers that supply an iterable instead of a text stream.
        for line in stdin:
            yield line if len(line) <= MAX_INPUT_CHARS else None
        return
    while True:
        line = stdin.readline(MAX_INPUT_CHARS + 1)
        if not line:
            return
        if len(line) > MAX_INPUT_CHARS:
            while line and not line.endswith("\n"):
                line = stdin.readline(MAX_INPUT_CHARS + 1)
            yield None
        else:
            yield line


def serve(stdin=sys.stdin, stdout=sys.stdout) -> None:
    """Read requests independently of ordered tools; drain accepted work on EOF.

    Only cached sim_test_status uses the separate status lane. Other tools stay
    in one FIFO because session environment and _captured() are process-global.
    The explicit stdout reference is never replaced by a tool's redirection.
    Once accepted calls finish, pending reply delivery has a bounded drain time;
    a slow or disconnected reader can lose complete or partial replies.
    """
    ordered = queue.Queue(TOOL_QUEUE_LIMIT)
    status = queue.Queue(STATUS_QUEUE_LIMIT)
    tests = queue.Queue(TEST_QUEUE_LIMIT)
    outgoing = queue.Queue(OUTPUT_QUEUE_LIMIT)
    finished = object()
    disconnected = threading.Event()
    id_lock = threading.Lock()
    in_flight = set()

    # Bypass the TextIOWrapper for real stdio: a blocked pipe write must not
    # hold its buffered-I/O lock during Python interpreter shutdown.
    try:
        output_fd = stdout.fileno()
    except (AttributeError, OSError, ValueError):
        output_fd = None

    def release_id(tracked_id):
        if tracked_id is not None:
            with id_lock:
                in_flight.discard(tracked_id)

    def abandon_output():
        # Atomic with the final admission decision; never held across I/O.
        with id_lock:
            disconnected.set()

    def publish(reply, tracked_id):
        if disconnected.is_set():
            release_id(tracked_id)
            return
        try:
            outgoing.put((reply, tracked_id), timeout=OUTPUT_ENQUEUE_SECONDS)
        except queue.Full:
            # An unavailable observer cannot stop already accepted side effects.
            # No further input is accepted after delivery is abandoned.
            abandon_output()
            release_id(tracked_id)

    def write_line(data):
        if output_fd is None:
            stdout.write(data)
            if not disconnected.is_set():
                stdout.flush()
            return
        remaining = memoryview(data.encode("ascii"))
        while remaining and not disconnected.is_set():
            count = os.write(output_fd, remaining)
            if count <= 0:
                raise BrokenPipeError("protocol output closed")
            remaining = remaining[count:]

    def write_replies():
        while True:
            item = outgoing.get()
            if item is finished:
                return
            reply, tracked_id = item
            try:
                if not disconnected.is_set():
                    try:
                        # Escaping also permits surrogate IDs on strict UTF-8 streams.
                        data = json.dumps(reply, ensure_ascii=True) + "\n"
                    except (TypeError, ValueError, RecursionError):
                        data = json.dumps(_rpc_error(reply.get("id"), -32603, "invalid tool response")) + "\n"
                    write_line(data)
            except (OSError, ValueError, UnicodeError):
                # The observer is gone. Accepted work still drains; no retries
                # or traceback may be written into the protocol stream.
                abandon_output()
                with contextlib.suppress(OSError, ValueError):
                    stdout.close()
            finally:
                release_id(tracked_id)

    def run_tools(work):
        while True:
            item = work.get()
            if item is finished:
                return
            reply, invocation, tracked_id = item
            try:
                response = _invoke(reply, invocation)
            except BaseException:
                # Even a tool raising SystemExit must not strand later accepted work.
                response = _rpc_error(reply["id"], -32603, "tool execution interrupted")
            publish(response, tracked_id)

    writer = threading.Thread(target=write_replies, name="mcp-writer", daemon=True)
    workers = [threading.Thread(target=run_tools, args=(work,), name=name)
               for work, name in ((ordered, "mcp-tools"), (status, "mcp-status"),
                                  *((tests, f"mcp-tests-{index}") for index in range(TEST_WORKERS)))]
    writer.start()
    for worker in workers:
        worker.start()
    try:
        for line in _input_lines(stdin):
            if disconnected.is_set():
                break
            if line is None:
                publish(_rpc_error(None, -32600, "request exceeds input limit"), None)
                continue
            line = line.strip()
            if not line:
                continue
            try:
                message = json.loads(line)
            except (ValueError, RecursionError):
                publish(_rpc_error(None, -32700, "parse error"), None)
                continue
            reply, invocation = _prepare(message)
            if reply is None:
                continue
            tracked_id = reply.get("id")
            duplicate = False
            busy = False
            # Output abandonment and enqueue share this short critical section:
            # a request is either admitted before abandonment, or not admitted.
            # Publishing a refusal and all output I/O happen after it is released.
            with id_lock:
                if disconnected.is_set():
                    break
                if tracked_id is not None:
                    duplicate = tracked_id in in_flight
                    if not duplicate:
                        in_flight.add(tracked_id)
                if not duplicate and invocation is not None:
                    work = (status if invocation[0] == "sim_test_status"
                            else tests if invocation[0] in TEST_LANE else ordered)
                    try:
                        work.put_nowait((reply, invocation, tracked_id))
                    except queue.Full:
                        busy = True
            if duplicate:
                error = _rpc_error(None, -32600, "request id is already in flight; duplicate not accepted")
                error["error"]["data"] = {"requestId": tracked_id}
                publish(error, None)
                continue
            if invocation is None:
                publish(reply, tracked_id)
                continue
            if busy:
                publish(_rpc_error(tracked_id, -32000, "server busy; request not accepted, retry"), tracked_id)
    finally:
        # Waiting is deliberate: EOF or an abandoned observer is not permission
        # to kill a call or silently discard an action already accepted above.
        ordered.put(finished)
        status.put(finished)
        for _ in range(TEST_WORKERS):
            tests.put(finished)
        for worker in workers:
            worker.join()
        deadline = time.monotonic() + OUTPUT_DRAIN_SECONDS
        try:
            outgoing.put(finished, timeout=max(0, deadline - time.monotonic()))
        except queue.Full:
            abandon_output()
        writer.join(max(0, deadline - time.monotonic()))
        if writer.is_alive():
            abandon_output()
            # A blocked write may eventually return. Discard remaining replies
            # and leave a sentinel so its one daemon writer can then exit.
            while True:
                try:
                    item = outgoing.get_nowait()
                except queue.Empty:
                    break
                if item is not finished:
                    release_id(item[1])
            outgoing.put_nowait(finished)


if __name__ == "__main__":
    # MCP messages are UTF-8; a Windows console default (cp1252) cannot encode labels such as "1920 × 1080".
    sys.stdin.reconfigure(encoding="utf-8")
    sys.stdout.reconfigure(encoding="utf-8")
    serve()
