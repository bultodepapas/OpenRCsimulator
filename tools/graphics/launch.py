#!/usr/bin/env python3
"""Launch OpenRC with an explicit, temporary graphics profile.

Usage:
    python tools/graphics/launch.py [launcher options] [Godot engine options] -- [OpenRC user args]

Launcher options are --godot, --executable, --profile, --resolution, and --dry-run.
Engine options before `--` are forwarded before Godot's user-argument separator;
arguments after `--` are forwarded after it. The selected profile is never saved.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Mapping, Optional, Sequence


PROFILE_ENV = "OPENRC_GRAPHICS_PROFILE"
PINNED_WINDOWS_GODOT = "Godot_v4.8-beta1_win64_console.exe"
PINNED_LINUX_GODOT = "Godot_v4.8-beta1_linux.x86_64"
APP_DIR = Path(__file__).resolve().parents[2] / "app"
REPO_ROOT = APP_DIR.parent

# These options would override the renderer, executable project, or reported
# profile selected by this launcher. The platform rendering driver stays on
# Godot's automatic choice.
_CONTROLLED_OPTIONS = {
    "--path",
    "--rendering-method",
    "--rendering-driver",
    "--profile",
}


class LaunchError(ValueError):
    """A user-facing launch configuration error."""


def _parse_resolution(value: str) -> str:
    match = re.fullmatch(r"(\d+)[xX](\d+)", value)
    if match is None:
        raise argparse.ArgumentTypeError("resolution must use WIDTHxHEIGHT, for example 1920x1080")
    width, height = (int(part) for part in match.groups())
    if width <= 0 or height <= 0:
        raise argparse.ArgumentTypeError("resolution dimensions must be positive")
    return f"{width}x{height}"


def _make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Run OpenRC with a temporary Compatibility or Forward+ graphics profile.",
        epilog=(
            "Place Godot engine options before `--` and OpenRC user arguments after it. "
            "For example: --profile high --verbose -- --landscape=green_paradise."
        ),
    )
    target = parser.add_mutually_exclusive_group()
    target.add_argument("--godot", metavar="PATH", help="Godot executable path or command name")
    target.add_argument("--executable", metavar="PATH", help="packaged OpenRC executable; omits --path")
    parser.add_argument("--profile", choices=("standard", "high"), default="standard")
    parser.add_argument("--resolution", type=_parse_resolution, help="temporary window size, WIDTHxHEIGHT")
    parser.add_argument("--dry-run", action="store_true", help="print exact argv and environment override as JSON")
    return parser


def _split_user_args(argv: Sequence[str]) -> tuple[list[str], list[str]]:
    """Split launcher/engine options from OpenRC user args at the first `--`."""
    try:
        separator = argv.index("--")
    except ValueError:
        return list(argv), []
    return list(argv[:separator]), list(argv[separator + 1 :])


def _option_name(argument: str) -> str:
    return argument.split("=", 1)[0] if argument.startswith("--") else argument


def _validate_forwarded_args(engine_args: Sequence[str], user_args: Sequence[str]) -> None:
    for argument in (*engine_args, *user_args):
        name = _option_name(argument)
        if name in _CONTROLLED_OPTIONS:
            raise LaunchError(
                f"{name} is controlled by this launcher; remove it from forwarded arguments"
            )


def _option_count(argv: Sequence[str], option: str) -> int:
    return sum(argument == option or argument.startswith(option + "=") for argument in argv)


def _resolve_executable(
    value: str,
    *,
    cwd: Path,
    require_exists: bool,
) -> str:
    """Resolve a path or PATH command to an absolute executable path."""
    if not value.strip():
        raise LaunchError("executable path cannot be empty")

    candidate = Path(value).expanduser()
    if not candidate.is_absolute() and len(candidate.parts) == 1:
        located = shutil.which(value)
        if located:
            candidate = Path(located)
    if not candidate.is_absolute():
        candidate = cwd / candidate
    resolved = candidate.resolve(strict=False)

    if require_exists:
        if not resolved.is_file():
            raise LaunchError(f"executable was not found: {resolved}")
        if os.name != "nt" and not os.access(resolved, os.X_OK):
            raise LaunchError(f"file is not executable: {resolved}")
    return str(resolved)


def _discover_godot(
    explicit_path: Optional[str],
    *,
    environ: Mapping[str, str],
    repo_root: Path,
    cwd: Path,
    require_exists: bool,
) -> str:
    if explicit_path is not None:
        return _resolve_executable(explicit_path, cwd=cwd, require_exists=require_exists)

    configured = environ.get("GODOT", "").strip()
    if configured:
        return _resolve_executable(configured, cwd=cwd, require_exists=require_exists)

    pinned_name = {"win32": PINNED_WINDOWS_GODOT, "linux": PINNED_LINUX_GODOT}.get(sys.platform)
    if pinned_name is not None:
        pinned = repo_root / ".tools" / pinned_name
        if pinned.is_file():
            return _resolve_executable(str(pinned), cwd=cwd, require_exists=require_exists)

    for command in ("godot", "godot4"):
        located = shutil.which(command)
        if located:
            return _resolve_executable(located, cwd=cwd, require_exists=require_exists)

    raise LaunchError(
        "Godot was not found; pass --godot PATH, set GODOT, or install the pinned engine under .tools/"
    )


def _environment_override(profile: str) -> dict[str, Optional[str]]:
    if profile == "high":
        return {PROFILE_ENV: "high"}
    return {PROFILE_ENV: None}


def _child_environment(
    inherited: Mapping[str, str], override: Mapping[str, Optional[str]]
) -> dict[str, str]:
    child = dict(inherited)
    for key, value in override.items():
        if value is None:
            child.pop(key, None)
        else:
            child[key] = value
    return child


def _build_command(
    executable: str,
    *,
    packaged: bool,
    profile: str,
    resolution: Optional[str],
    engine_args: Sequence[str],
    user_args: Sequence[str],
    app_dir: Path = APP_DIR,
) -> list[str]:
    if profile not in ("standard", "high"):
        raise LaunchError(f"unsupported profile: {profile}")
    renderer = "forward_plus" if profile == "high" else "gl_compatibility"
    command = [executable]
    if not packaged:
        command.extend(("--path", str(app_dir.resolve())))
    command.extend(("--rendering-method", renderer))
    if resolution is not None:
        command.extend(("--resolution", resolution))
    command.extend(engine_args)
    if user_args:
        command.append("--")
        command.extend(user_args)
    return command


def _main(argv: Optional[Sequence[str]] = None) -> int:
    raw_argv = list(sys.argv[1:] if argv is None else argv)
    launcher_and_engine_args, user_args = _split_user_args(raw_argv)
    parser = _make_parser()

    if _option_count(launcher_and_engine_args, "--profile") > 1:
        parser.error("--profile may be specified only once")

    options, engine_args = parser.parse_known_args(launcher_and_engine_args)
    try:
        _validate_forwarded_args(engine_args, user_args)
        cwd = Path.cwd().resolve()
        if options.executable is not None:
            executable = _resolve_executable(
                options.executable,
                cwd=cwd,
                require_exists=not options.dry_run,
            )
            packaged = True
        else:
            executable = _discover_godot(
                options.godot,
                environ=os.environ,
                repo_root=REPO_ROOT,
                cwd=cwd,
                require_exists=not options.dry_run,
            )
            packaged = False
        command = _build_command(
            executable,
            packaged=packaged,
            profile=options.profile,
            resolution=options.resolution,
            engine_args=engine_args,
            user_args=user_args,
        )
    except LaunchError as error:
        parser.error(str(error))

    env_override = _environment_override(options.profile)
    if options.dry_run:
        print(
            json.dumps(
                {"argv": command, "env_override": env_override},
                indent=2,
                ensure_ascii=False,
            )
        )
        return 0

    child_env = _child_environment(os.environ, env_override)
    try:
        completed = subprocess.run(command, env=child_env, check=False)
    except OSError as error:
        print(f"Could not start {executable}: {error}", file=sys.stderr)
        return 127
    return int(completed.returncode)


def main(argv: Optional[Sequence[str]] = None) -> int:
    """CLI entry point, also callable with an explicit argument vector in tests."""
    return _main(argv)


if __name__ == "__main__":
    raise SystemExit(main())
