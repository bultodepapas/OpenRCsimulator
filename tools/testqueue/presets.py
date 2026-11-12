"""Reviewed entry points; requests cannot choose an arbitrary executable or shell."""
from __future__ import annotations

import math
from pathlib import Path
import re

PRESETS = {"debug-session", "debug-smoke", "checked", "godtest", "suite", "capture", "landscape", "ci"}


def validate(preset: str, options: dict) -> dict:
    if preset not in PRESETS:
        raise ValueError("unsupported preset: " + preset)
    if not isinstance(options, dict) or set(options) - {"argv", "headless", "timeout", "require", "script", "settings"}:
        raise ValueError("unknown preset options")
    result = dict(options)
    argv = result.setdefault("argv", [])
    if not isinstance(argv, list) or any(not isinstance(arg, str) or len(arg) > 4096 or "\0" in arg for arg in argv):
        raise ValueError("argv must be a bounded string list")
    if len(argv) > 128:
        raise ValueError("too many arguments")
    engine_argv = argv[:argv.index("--")] if "--" in argv else argv
    headless = result.setdefault("headless", preset in {"checked", "debug-smoke", "suite", "ci"} or "--headless" in engine_argv)
    if type(headless) is not bool:
        raise ValueError("headless must be boolean")
    # The comprehensive GOD TEST includes rendering. Never infer it is headless.
    if preset in {"capture", "landscape", "godtest"}:
        result["headless"] = False
    if preset in {"suite", "ci"}:
        # Suites include rendered child fixtures, despite most checks being headless.
        result["headless"] = False
    duration = result.setdefault("timeout", 1800 if preset == "debug-session" else 3600)
    if type(duration) not in (int, float) or not math.isfinite(duration) or not 1 <= duration <= 21600:
        raise ValueError("execution timeout must be between 1 and 21600 seconds")
    if preset == "debug-session":
        allowed = {"--headless", "--mute", "--verbose", "--script-profile", "--import"}
        index = 0
        while index < len(argv):
            value = argv[index]
            if value == "--":
                break
            if value == "--resolution":
                index += 1
                if index >= len(argv) or not re.fullmatch(r"[1-9][0-9]{1,4}x[1-9][0-9]{1,4}", argv[index]):
                    raise ValueError("invalid resolution")
            elif value not in allowed:
                raise ValueError("unsupported managed debug option: " + value)
            index += 1
        if headless and "--headless" not in argv:
            result["argv"] = ["--headless", *argv]
    if preset == "checked":
        script = result.get("script", "")
        if not isinstance(script, str) or not re.fullmatch(r"res://(?:tests|tools)/[A-Za-z0-9_./-]+\.gd", script) or ".." in Path(script[6:]).parts:
            raise ValueError("checked requires a res://tests/ or res://tools/ GDScript")
        if argv:
            raise ValueError("checked uses script and require options, not raw engine arguments")
        markers = result.setdefault("require", [])
        if not isinstance(markers, list) or any(not isinstance(marker, str) or not marker or len(marker) > 4096 or "\n" in marker for marker in markers):
            raise ValueError("checked completion markers must be nonempty literals")
        settings = result.setdefault("settings", {})
        if not isinstance(settings, dict) or set(settings) - {"max_log_bytes", "warnings_as_errors", "label"}:
            raise ValueError("unsupported checked settings")
        if ("max_log_bytes" in settings and (type(settings["max_log_bytes"]) is not int or not 1 <= settings["max_log_bytes"] <= 64 * 1024 * 1024)
                or "warnings_as_errors" in settings and type(settings["warnings_as_errors"]) is not bool
                or "label" in settings and (not isinstance(settings["label"], str) or len(settings["label"]) > 128)):
            raise ValueError("invalid checked settings")
    elif set(result) & {"script", "require", "settings"}:
        raise ValueError("script and require are checked-only options")
    if preset == "suite" and argv:
        raise ValueError("suite takes no command arguments; use the existing partition environment")
    if preset == "ci" and argv not in ([], ["quick"], ["full"], ["release"]):
        raise ValueError("ci mode must be quick, full or release")
    if preset == "godtest" and any(arg in {"--godot", "--out", "--snapshot"} or arg.startswith(("--godot=", "--out=", "--snapshot=")) for arg in argv):
        raise ValueError("GOD TEST output, snapshot and engine belong to the worker")
    if preset == "godtest":
        if not argv or argv[0] not in {"run", "all", "memory", "soak", "fleet", "matrix"}:
            raise ValueError("GOD TEST preset requires an execution command")
        if any(arg == "--manifest" or arg.startswith("--manifest=") for arg in argv):
            raise ValueError("external GOD TEST manifests must first be bound into a reviewed preset")
    if preset == "debug-smoke":
        index = 0
        while index < len(argv):
            if argv[index] not in {"--seed", "--steps", "--cycles"} or index + 1 >= len(argv) or not argv[index + 1].isdigit():
                raise ValueError("smoke accepts only integer seed, steps and cycles")
            index += 2
    if preset == "landscape":
        index = 0
        while index < len(engine_argv):
            value = engine_argv[index]
            if value in {"--headless", "--verbose"}:
                index += 1
                continue
            if value not in {"--resolution", "--rendering-driver", "--audio-driver"} or index + 1 >= len(engine_argv):
                raise ValueError("unsupported landscape engine option: " + value)
            selected = engine_argv[index + 1]
            if value == "--resolution" and not re.fullmatch(r"[1-9][0-9]{1,4}x[1-9][0-9]{1,4}", selected):
                raise ValueError("invalid landscape resolution")
            if value == "--rendering-driver" and selected not in {"opengl3", "vulkan", "d3d12", "metal"}:
                raise ValueError("unsupported rendering driver")
            if value == "--audio-driver" and selected != "Dummy":
                raise ValueError("landscape audio driver must be Dummy")
            index += 2
    if preset == "capture":
        if argv and (len(argv) != 2 or argv[0] != "--group" or argv[1] not in {"core", "ui", "quality", "terrain-atmosphere", "ground", "vegetation", "scenario"}):
            raise ValueError("capture accepts only --group; outputs belong to the worker")
    return result


def claims(preset: str, options: dict) -> dict[str, int]:
    return {"cpu": 1, "memory": 1, **({"headless": 1} if options["headless"] else {"rendered": 1})}
