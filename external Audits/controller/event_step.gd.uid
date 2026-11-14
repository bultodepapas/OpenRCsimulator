#!/usr/bin/env python3
"""Reproduce the scheduled two-writer profile-store interleaving.

The GDScript fixture and checked runner perform the checks. This launcher only
coordinates the two post-read barriers and retains the separate final read.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys
import time


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot-bin", default=os.environ.get("GODOT_BIN"),
                        help="Godot executable; defaults to GODOT_BIN")
    parser.add_argument("--checked-runner", default=os.environ.get("CHECKED_RUNNER"),
                        help="path to run_checked.py; defaults to CHECKED_RUNNER")
    args = parser.parse_args()
    if not args.godot_bin:
        parser.error("supply --godot-bin or GODOT_BIN")
    if not args.checked_runner:
        parser.error("supply --checked-runner or CHECKED_RUNNER")

    base = Path(__file__).resolve().parent
    engine = Path(args.godot_bin).expanduser().resolve()
    runner = Path(args.checked_runner).expanduser().resolve()
    project = base / "repro"
    if not engine.is_file():
        parser.error(f"Godot executable not found: {engine}")
    if not runner.is_file():
        parser.error(f"checked runner not found: {runner}")
    if not (project / "project.godot").is_file():
        parser.error(f"disposable project not found: {project}")

    sync = base / ("race-portable-" + str(time.time_ns()))
    sync.mkdir()
    env = os.environ.copy()
    env.update({
        "AUDIT_SYNC": str(sync),
        "AUDIT_STORE": str(sync / "profiles.cfg"),
        "XDG_DATA_HOME": str(sync / "userdata"),
        "XDG_CONFIG_HOME": str(sync / "config"),
    })

    def command(label: str, script: str, marker: str) -> list[str]:
        return [
            sys.executable, str(runner), "--label", label,
            "--out-dir", str(base / "checks"), "--timeout", "30",
            "--require-text", marker, "--", str(engine), "--headless",
            "--path", str(project), "--audio-driver", "Dummy",
            "--script", "res://" + script,
        ]

    processes: list[subprocess.Popen[str]] = []
    try:
        for name in ("A", "B"):
            writer_env = env.copy()
            writer_env["AUDIT_WRITER"] = name
            processes.append(subprocess.Popen(
                command("race-portable-writer-" + name, "concurrent_writer.gd",
                        "WRITER_DONE name=" + name + " ok=true"),
                cwd=base, env=writer_env, stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, text=True,
            ))

        # Both real saves must have read the same prior store before either
        # enters the unmodified transaction; then publish A, followed by B.
        deadline = time.monotonic() + 20
        while not all((sync / (name + ".ready")).exists() for name in ("A", "B")):
            if time.monotonic() > deadline or any(p.poll() is not None for p in processes):
                raise RuntimeError("a writer did not reach the read barrier")
            time.sleep(0.01)

        for index, name in enumerate(("A", "B")):
            (sync / (name + ".release")).write_text("release", encoding="utf-8")
            output, _ = processes[index].communicate(timeout=20)
            print(output, end="")
            if processes[index].returncode:
                raise RuntimeError(name + " writer failed; inspect its checked-runner report")

        result = subprocess.run(
            command("race-portable-final-store", "inspect_store.gd",
                    'FINAL_STORE names=["Writer B"] ok=true'),
            cwd=base, env=env, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, timeout=30, check=False,
        )
        print(result.stdout, end="")
        if result.returncode:
            raise RuntimeError("final store was not exactly B; inspect the checked-runner report")
        print("RACE_PROBE_COMPLETE sync=" + str(sync))
        return 0
    finally:
        for process in processes:
            if process.poll() is None:
                process.kill()
                process.wait()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"race probe failed: {error}", file=sys.stderr)
        raise SystemExit(1)
