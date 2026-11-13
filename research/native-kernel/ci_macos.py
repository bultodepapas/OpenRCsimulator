#!/usr/bin/env python3
"""Run the existing fixed-wing Mac correctness gates in an isolated CI workspace.

This is not fleet, automatic-admission, performance or distribution evidence.
Each tool retains its own reports and enforces its existing identity checks.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
EXCLUDED = {"helicopter", "helicopter_stage"}


def oracle_commands(builder: object) -> list[tuple[str, str, list[str]]]:
    """Use the installer's actual roster and the shared declared oracle arguments."""
    roster = builder.verification_roster()
    scripts, arguments = builder.nk.ORACLE_SCRIPTS, builder.nk.ORACLE_ARGUMENTS
    expected = set(scripts) - EXCLUDED
    if (set(scripts) != set(arguments) or set(roster) != expected | {"base_oracle"}
            or not EXCLUDED <= set(scripts)):
        raise ValueError("Mac installation roster and declared oracle commands differ")
    commands = [("base_oracle", "oracle.gd", ["--states", "12000", "--variant-states", "1500"])]
    commands.extend((key, scripts[key], shlex.split(arguments[key])) for key in roster if key != "base_oracle")
    return commands


def guard_check_count(log: str) -> int:
    """Require the real extension test's complete marker and its retained controls."""
    matches = re.findall(r"(?m)^MACOS_DOMAIN_GUARD verdict=pass checks=(\d+)\s*$", log)
    if len(matches) != 1 or int(matches[0]) < 72:
        raise ValueError("Packed domain-guard test did not complete at least 72 checks")
    return int(matches[0])


def run(command: list[str], label: str, logs: Path, env: dict[str, str]) -> None:
    print(f"\n== {label}: {shlex.join(command)}", flush=True)
    log = logs / f"{label}.log"
    with log.open("x", encoding="utf-8") as stream:
        completed = subprocess.run(command, cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT)
    print(log.read_text(encoding="utf-8", errors="replace"), end="", flush=True)
    completed.check_returncode()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path, help="new directory below this checkout's tmp/")
    parser.add_argument("--jobs", type=int, default=2)
    args = parser.parse_args()
    raw_out = args.out.expanduser()
    if raw_out.exists() or raw_out.is_symlink():
        parser.error("--out must not already exist")
    out = raw_out.resolve()
    tmp = (ROOT / "tmp").resolve()
    if out == tmp or not out.is_relative_to(tmp) or args.jobs < 1:
        parser.error("--out must be below tmp/ and --jobs must be positive")
    godot = args.godot.expanduser().resolve()
    if not godot.is_file():
        parser.error("--godot must name the pinned executable")
    out.mkdir(parents=True, exist_ok=False)
    logs = out / "logs"
    logs.mkdir()
    build_root = out / "build"
    env = dict(os.environ, OPENRC_NK_TOOL_ROOT=str(build_root), PYTHONDONTWRITEBYTECODE="1")
    # The Python builder reads OPENRC_NK_TOOL_ROOT when imported.
    os.environ["OPENRC_NK_TOOL_ROOT"] = str(build_root)
    spec = importlib.util.spec_from_file_location("openrc_ci_macos_builder", HERE / "build_macos.py")
    if spec is None or spec.loader is None:
        raise RuntimeError("Cannot load the Mac builder")
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    roster = oracle_commands(builder)
    python = sys.executable
    builder_path = str(HERE / "build_macos.py")
    runner = str(HERE / "run.py")
    checked = str(ROOT / "tools/godot/run_checked.py")
    prepare = str(ROOT / "tools/graphics/prepare_research.py")
    before = out / "before"
    after = out / "after"
    checks = out / "checks"

    def execute(label: str, *command: str) -> None:
        run(list(command), label, logs, env)

    def import_project(label: str, project: Path) -> None:
        execute(label, python, checked, "--out-dir", str(checks), "--label", label, "--timeout", "600", "--",
                str(godot), "--headless", "--path", str(project), "--audio-driver", "Dummy", "--import")

    try:
        execute("prepare-before", python, prepare, "--dest", str(before), "--copy-mode", "clone")
        before_app = before / "app"
        import_project("import-before", before_app)
        for mutant in (False, True):
            command = [python, builder_path, "--godot", str(godot), "--tool-root", str(build_root),
                       "--jobs", str(args.jobs)]
            if mutant:
                command.append("--mutant")
            run(command, "build-mutant" if mutant else "build-candidate", logs, env)

        for key, script, options in roster:
            execute("oracle-" + key.replace("_", "-"), python, runner, "--godot", str(godot), "--project",
                    str(before_app), "--experimental-native-macos", "--script", script, *options)

        execute("fpcr-control", python, str(HERE / "fpcr_control_probe.py"), "--tool-root", str(build_root),
                "--godot", str(godot), "--project", str(before_app), "--out", str(out / "fpcr"))

        guard_checks = out / "guard-check"
        execute("domain-guard", python, checked, "--out-dir", str(guard_checks), "--label", "domain-guard",
                "--timeout", "600", "--require-text", "MACOS_DOMAIN_GUARD verdict=pass checks=", "--",
                str(godot), "--headless", "--path", str(before_app), "--audio-driver", "Dummy", "--script",
                str(HERE / "test_macos_domain_guard.gd"), "--",
                "--extension=" + str(build_root / "openrc_native_kernel.gdextension"))
        reports = list(guard_checks.glob("*/report.json"))
        if len(reports) != 1:
            raise ValueError("Expected exactly one checked packed-guard report")
        report = json.loads(reports[0].read_text(encoding="utf-8"))
        count = guard_check_count(Path(report["log"]).read_text(encoding="utf-8", errors="replace"))
        print(f"Packed domain guard: {count} checks", flush=True)

        execute("install", python, builder_path, "--godot", str(godot), "--tool-root", str(build_root),
                "--install-app")
        # Installer outputs change the canonical app. A previously prepared copy
        # remains frozen; a fresh verified copy is required to execute that install.
        execute("prepare-after", python, prepare, "--dest", str(after), "--copy-mode", "clone")
        after_app = after / "app"
        import_project("import-after", after_app)
        for mode, marker in (("stage", "NK3_NATIVE_STAGE_NATIVE"),
                             ("lifecycle", "NK3_NATIVE_SESSION_NATIVE"),
                             ("replay", "NK3_NATIVE_REPLAY_NATIVE")):
            label = "installed-" + mode
            execute(label, python, checked, "--out-dir", str(checks), "--label", label, "--timeout", "1800",
                    "--require-text", "NATIVE_QUALIFICATION preloaded=false", "--require-text",
                    marker + " verdict=pass", "--require-text", f"NATIVE_QUALIFICATION mode={mode} verdict=pass",
                    "--", str(godot), "--headless", "--path", str(after_app), "--audio-driver", "Dummy", "--",
                    "--quick-flight", "--native-qualification=" + mode, "--experimental-native-macos=true")
    except (OSError, ValueError, KeyError, json.JSONDecodeError, subprocess.SubprocessError) as error:
        print(f"Mac native CI failed; partial evidence retained in {out}: {error}", file=sys.stderr)
        return 1
    print("Mac native CI correctness gates passed; automatic admission, fleet, performance and distribution remain separate.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
