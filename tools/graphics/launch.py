#!/usr/bin/env python3
"""Launch OpenRC with an explicit, temporary graphics profile.

Usage:
    python tools/graphics/launch.py [launcher options] [Godot engine options] -- [OpenRC user args]

Launcher options are --godot, --executable, --profile, --resolution, and --dry-run.
The separate --research-* mode requires a prepared, isolated project copy.
Engine options before `--` are forwarded before Godot's user-argument separator;
arguments after `--` are forwarded after it. The selected profile is never saved.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Mapping, Optional, Sequence


PROFILE_ENV = "OPENRC_GRAPHICS_PROFILE"
RESEARCH_ENV = "OPENRC_GRAPHICS_RESEARCH"
RECONSTRUCTION_ENV = "OPENRC_RECONSTRUCTION"
METALFX_TRIAL_ENV = "OPENRC_METALFX_TRIAL"
PINNED_WINDOWS_GODOT = "Godot_v4.8-beta1_win64_console.exe"
PINNED_LINUX_GODOT = "Godot_v4.8-beta1_linux.x86_64"
APP_DIR = Path(__file__).resolve().parents[2] / "app"
REPO_ROOT = APP_DIR.parent

# These options would override the renderer, executable project, or reported
# profile. Ordinary launches leave the driver on Godot's automatic choice.
_CONTROLLED_OPTIONS = {
    "--path",
    "--rendering-method",
    "--rendering-driver",
    "--profile",
    "--research-project",
    "--research-method",
    "--research-driver",
    "--research-reconstruction",
}
_RESEARCH_CONTROLLED_OPTIONS = {
    "--main-pack", "--display-driver", "--headless", "--editor", "-e",
    "--project-manager", "-p", "--import", "--export-release", "--export-debug",
    "--export-pack", "--export-patch", "--resolution",
}
_RESEARCH_PAIRS = {
    ("gl_compatibility", "opengl3"),
    ("mobile", "metal"), ("forward_plus", "metal"),
    ("mobile", "vulkan"), ("forward_plus", "vulkan"),
}
_RESEARCH_RECONSTRUCTION = (
    "native", "metalfx_spatial_85", "metalfx_spatial_quality",
    "metalfx_temporal_native", "metalfx_temporal_85", "metalfx_temporal_quality",
)
_RESEARCH_PROJECT_NAME = re.compile(r"OpenRC-Research-[0-9a-f]{32}\Z")


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
    parser.add_argument("--research-project", metavar="PATH", help=(
        "isolated app copy with a unique OpenRC-Research-<32 lowercase hex> project name, "
        "separate .godot cache, sibling assets/ and multi-bounce occlusion disabled"))
    parser.add_argument("--research-method", choices=("gl_compatibility", "mobile", "forward_plus"),
                        help="renderer method for the isolated technical comparison")
    parser.add_argument("--research-driver", choices=("opengl3", "metal", "vulkan"),
                        help="driver paired with the selected research method")
    parser.add_argument("--research-reconstruction", choices=_RESEARCH_RECONSTRUCTION,
                        help="explicit MetalFX trial; default Native, no saved preference")
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


def _validate_forwarded_args(engine_args: Sequence[str], user_args: Sequence[str], *, research: bool = False) -> None:
    for argument in (*engine_args, *user_args):
        name = _option_name(argument)
        controlled = _CONTROLLED_OPTIONS | (_RESEARCH_CONTROLLED_OPTIONS if research else set())
        abbreviation = research and name.startswith("--") and any(
            option.startswith(name) for option in controlled if option.startswith("--"))
        if name in controlled or abbreviation or (research and name.startswith("--research-")):
            raise LaunchError(
                f"{name} is controlled by this launcher; remove it from forwarded arguments"
            )


def _option_count(argv: Sequence[str], option: str) -> int:
    return sum(argument == option or argument.startswith(option + "=") for argument in argv)


def _research_project_settings(project: Path) -> tuple[dict[str, str], str]:
    """Read the few startup settings that protect a disposable research copy.

    Feature-tagged alternatives are refused: otherwise they could override the
    checked name, cache directory, or common-effects setting on the actual host.
    """
    watched = {
        "application/config/name", "application/config/use_custom_user_dir",
        "application/config/project_settings_override", "application/config/use_hidden_project_data_directory",
        "rendering/lights_and_shadows/multi_bounce_occlusion/enabled",
    }
    settings: dict[str, str] = {}
    section = ""
    try:
        project_bytes = (project / "project.godot").read_bytes()
        lines = project_bytes.decode("utf-8-sig").splitlines()
    except (OSError, UnicodeError) as error:
        raise LaunchError(f"cannot read research project.godot: {error}") from error
    for line in lines:
        value = line.strip()
        if not value or value.startswith((";", "#")):
            continue
        match = re.fullmatch(r"\[([^\]]+)\]", value)
        if match:
            section = match.group(1).strip()
            continue
        if "=" not in value:
            continue
        key, raw = value.split("=", 1)
        full = f"{section}/{key.strip()}"
        for target in watched:
            if full.startswith(target + "."):
                raise LaunchError(f"research project has a feature override for {target}")
        if full in watched:
            if full in settings:
                raise LaunchError(f"research project repeats {full}")
            settings[full] = raw.strip()
    return settings, hashlib.sha256(project_bytes).hexdigest()


def _research_project(value: str, *, cwd: Path) -> dict[str, str]:
    """Validate isolation before launching; never modify the supplied copy."""
    project = Path(value).expanduser()
    if not project.is_absolute():
        project = cwd / project
    project = project.resolve()
    live_app = APP_DIR.resolve()
    if project == live_app or live_app in project.parents:
        raise LaunchError("research project must be a separate app copy, not the live app")
    if not project.is_dir() or not (project / "project.godot").is_file():
        raise LaunchError("research project must be an existing app copy containing project.godot")
    if os.path.samefile(project / "project.godot", live_app / "project.godot"):
        raise LaunchError("research project.godot must not be the live project's file")
    if any((project / name).exists() or (project / name).is_symlink()
           for name in ("override.cfg", "project.binary")):
        raise LaunchError("research project cannot contain override.cfg or project.binary")
    cache = project / ".godot"
    if cache.is_symlink() and not cache.exists():
        raise LaunchError("research .godot cache is a broken link")
    cache_is_junction = hasattr(cache, "is_junction") and cache.is_junction()
    if cache.exists() and (cache.is_symlink() or cache_is_junction or not cache.is_dir() or project not in cache.resolve().parents):
        raise LaunchError("research .godot cache must remain inside the isolated app copy")
    if cache.exists():
        def fail_scan(error: OSError) -> None:
            raise LaunchError(f"cannot inspect research .godot cache: {error}") from error
        for directory, dirs, files in os.walk(cache, followlinks=False, onerror=fail_scan):
            for name in (*dirs, *files):
                item = Path(directory) / name
                if item.is_symlink() or (hasattr(item, "is_junction") and item.is_junction()):
                    raise LaunchError("research .godot cache cannot contain links to another cache")
    if not (project.parent / "assets").is_dir():
        raise LaunchError("research copy needs its sibling assets/ directory")
    profile = project / "render" / "high_graphics_profile.gd"
    live_profile = live_app / "render" / "high_graphics_profile.gd"
    try:
        if not profile.is_file() or project not in profile.resolve().parents:
            raise LaunchError("research copy needs its own render/high_graphics_profile.gd")
        profile_bytes = profile.read_bytes()
        if profile_bytes != live_profile.read_bytes():
            raise LaunchError("research profile differs from the launcher source; refresh the isolated copy")
    except OSError as error:
        raise LaunchError(f"cannot verify the research profile: {error}") from error
    settings, project_sha256 = _research_project_settings(project)
    name_value = settings.get("application/config/name", "")
    match = re.fullmatch(r'"(OpenRC-Research-[0-9a-f]{32})"', name_value)
    if not match or not _RESEARCH_PROJECT_NAME.fullmatch(match.group(1)):
        raise LaunchError("research project name must be OpenRC-Research- followed by 32 lowercase hex digits")
    if settings.get("application/config/use_custom_user_dir", "false") != "false":
        raise LaunchError("research project must use the unique project-name user directory")
    if settings.get("application/config/project_settings_override", '""') != '""':
        raise LaunchError("research project cannot use a project settings override")
    if settings.get("application/config/use_hidden_project_data_directory", "true") != "true":
        raise LaunchError("research project must use its separate .godot cache")
    if settings.get("rendering/lights_and_shadows/multi_bounce_occlusion/enabled") != "false":
        raise LaunchError("research project must disable startup multi-bounce occlusion")
    try:
        current_project_sha256 = hashlib.sha256((project / "project.godot").read_bytes()).hexdigest()
    except OSError as error:
        raise LaunchError(f"cannot recheck the research project: {error}") from error
    if current_project_sha256 != project_sha256:
        raise LaunchError("research project settings changed during validation; retry with a frozen copy")
    return {"path": str(project), "project_name": match.group(1),
            "project_sha256": project_sha256,
            "profile_sha256": hashlib.sha256(profile_bytes).hexdigest()}


def _research_environment(method: str, driver: str, reconstruction: str,
                          project: Mapping[str, str]) -> dict[str, Optional[str]]:
    if (method, driver) not in _RESEARCH_PAIRS:
        raise LaunchError(f"unsupported research method/driver pair: {method}/{driver}")
    if reconstruction not in _RESEARCH_RECONSTRUCTION:
        raise LaunchError(f"unsupported research reconstruction: {reconstruction}")
    if reconstruction != "native" and (driver != "metal" or method == "gl_compatibility"):
        raise LaunchError("MetalFX research requires a native Metal renderer")
    if reconstruction.startswith("metalfx_temporal") and method != "forward_plus":
        raise LaunchError("MetalFX Temporal research requires Forward+")
    identity = {"requested_method": method, "requested_driver": driver,
                "requested_effects": "common", "requested_reconstruction": reconstruction,
                "project_name": project["project_name"], "project_sha256": project["project_sha256"],
                "profile_sha256": project["profile_sha256"]}
    return {PROFILE_ENV: "standard", RESEARCH_ENV: json.dumps(identity, sort_keys=True),
            RECONSTRUCTION_ENV: reconstruction,
            METALFX_TRIAL_ENV: "1" if reconstruction != "native" else None,
            "OPENRC_CONTACT_SHADOWS": "off", "OPENRC_LAKE_REFLECTIONS": "off"}


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
    research_method: Optional[str] = None,
    research_driver: Optional[str] = None,
) -> list[str]:
    if profile not in ("standard", "high"):
        raise LaunchError(f"unsupported profile: {profile}")
    if (research_method is None) != (research_driver is None):
        raise LaunchError("research method and driver must be supplied together")
    if research_method is not None and profile != "standard":
        raise LaunchError("research mode requires the common Standard effects profile")
    if research_method is not None and (research_method, research_driver) not in _RESEARCH_PAIRS:
        raise LaunchError(f"unsupported research method/driver pair: {research_method}/{research_driver}")
    if packaged and research_method is not None:
        raise LaunchError("research mode requires an isolated project, not a packaged executable")
    renderer = research_method if research_method is not None else ("forward_plus" if profile == "high" else "gl_compatibility")
    command = [executable]
    if not packaged:
        command.extend(("--path", str(app_dir.resolve())))
    command.extend(("--rendering-method", renderer))
    if research_driver is not None:
        command.extend(("--rendering-driver", research_driver))
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
    # Keep ordinary launcher parsing unchanged; research must use exact names.
    if any(_option_name(argument).startswith("--research-") for argument in launcher_and_engine_args):
        parser.allow_abbrev = False

    for option in ("--profile", "--research-project", "--research-method", "--research-driver",
                   "--research-reconstruction"):
        if _option_count(launcher_and_engine_args, option) > 1:
            parser.error(f"{option} may be specified only once")

    options, engine_args = parser.parse_known_args(launcher_and_engine_args)
    try:
        research = any(value is not None for value in (
            options.research_project, options.research_method, options.research_driver,
            options.research_reconstruction))
        _validate_forwarded_args(engine_args, user_args, research=research)
        cwd = Path.cwd().resolve()
        project: Optional[dict[str, str]] = None
        if research:
            if not all((options.research_project, options.research_method, options.research_driver)):
                raise LaunchError("research mode requires --research-project, --research-method and --research-driver")
            if options.executable is not None or _option_count(launcher_and_engine_args, "--profile"):
                raise LaunchError("research mode cannot be combined with --executable or --profile")
            if _option_count(launcher_and_engine_args, "--godot") > 1:
                raise LaunchError("--godot may be specified only once in research mode")
            if _option_count(launcher_and_engine_args, "--resolution") > 1:
                raise LaunchError("--resolution may be specified only once in research mode")
            reconstruction = options.research_reconstruction or "native"
            if reconstruction != "native" and (not user_args or any(
                    _option_name(argument) in ("--input-report", "--vehicle") for argument in user_args)):
                raise LaunchError("MetalFX research requires direct fixed-wing flight/capture arguments after --")
            project = _research_project(options.research_project, cwd=cwd)
            env_override = _research_environment(options.research_method, options.research_driver,
                                                  reconstruction, project)
        else:
            env_override = _environment_override(options.profile)
            if RESEARCH_ENV in os.environ:
                env_override[RESEARCH_ENV] = None
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
            app_dir=Path(project["path"]) if project is not None else APP_DIR,
            research_method=options.research_method if research else None,
            research_driver=options.research_driver if research else None,
        )
    except LaunchError as error:
        parser.error(str(error))

    if options.dry_run:
        plan = {"argv": command, "env_override": env_override}
        if project is not None:
            plan["research_project"] = project
        print(json.dumps(plan, indent=2, ensure_ascii=False))
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
