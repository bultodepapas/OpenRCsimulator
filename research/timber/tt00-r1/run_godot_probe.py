#!/usr/bin/env python3
"""Import and render the Timber r1 GLBs in a disposable Godot project under /tmp."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from typing import Any


REPO = Path(__file__).resolve().parents[3]
PACKAGE = REPO / "Timber turbo evolution/turbo_timber_evolution/r1"
PROBE = Path(__file__).resolve().with_name("godot_probe.gd")
DEFAULT_GODOT = REPO / ".tools/Godot_v4.7.2-stable_linux.x86_64"
DEFAULT_OUTPUT = REPO / "docs/research/timber-integration/TT-00-R1"
OUTPUT_NAMES = (
    "godot-report.json",
    "import.log",
    "run.log",
    "neutral.png",
    "articulated.png",
    "runner-status.json",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run_logged(command: list[str], log_path: Path, timeout_s: int, env: dict[str, str]) -> int:
    try:
        result = subprocess.run(
            command,
            cwd=REPO,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout_s,
            check=False,
        )
        log_path.write_text(result.stdout, encoding="utf-8")
        return result.returncode
    except subprocess.TimeoutExpired as error:
        output = error.stdout or ""
        if isinstance(output, bytes):
            output = output.decode("utf-8", errors="replace")
        log_path.write_text(str(output) + f"\nPROBE TIMEOUT after {timeout_s}s\n", encoding="utf-8")
        return 124


def project_settings() -> str:
    return '''config_version=5

[application]
config/name="OpenRC Timber r1 Import Probe"

[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/size/window_width_override=1280
window/size/window_height_override=720

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
'''


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=DEFAULT_GODOT, help="Godot 4.7.2 executable")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT, help="Evidence directory")
    parser.add_argument("--timeout", type=int, default=90, help="Timeout per Godot invocation in seconds")
    args = parser.parse_args()

    godot = args.godot.expanduser().resolve()
    output = args.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    for name in OUTPUT_NAMES:
        stale = output / name
        if stale.exists():
            stale.unlink()

    required = [godot, PROBE, PACKAGE / "metadata.json", PACKAGE / "export/aircraft.glb", PACKAGE / "export/aircraft_demo.glb"]
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise SystemExit("Missing required probe inputs:\n" + "\n".join(missing))
    if not shutil.which("xvfb-run"):
        raise SystemExit("xvfb-run is required for the Compatibility render capture")

    status: dict[str, Any] = {
        "step": "TT-00-R1",
        "godot_executable": str(godot),
        "godot_binary_sha256": sha256(godot),
        "renderer_requested": "gl_compatibility",
        "rendering_mode": "xvfb-run with LIBGL_ALWAYS_SOFTWARE=1",
        "temporary_project_parent": "/tmp",
        "package_inputs": {
            "aircraft.glb_sha256": sha256(PACKAGE / "export/aircraft.glb"),
            "aircraft_demo.glb_sha256": sha256(PACKAGE / "export/aircraft_demo.glb"),
        },
    }
    env = os.environ.copy()
    env["LIBGL_ALWAYS_SOFTWARE"] = "1"
    env["GALLIUM_DRIVER"] = "llvmpipe"

    with tempfile.TemporaryDirectory(prefix="openrc-tt00-r1-", dir="/tmp") as temporary:
        project = Path(temporary)
        assets = project / "assets"
        probe_output = project / "probe-output"
        assets.mkdir()
        probe_output.mkdir()
        (project / "project.godot").write_text(project_settings(), encoding="utf-8")
        shutil.copy2(PACKAGE / "export/aircraft.glb", assets / "aircraft.glb")
        shutil.copy2(PACKAGE / "export/aircraft_demo.glb", assets / "aircraft_demo.glb")
        shutil.copy2(PACKAGE / "metadata.json", assets / "metadata.json")
        shutil.copy2(PROBE, project / "godot_probe.gd")

        import_command = [str(godot), "--headless", "--editor", "--path", str(project), "--import", "--quit"]
        import_code = run_logged(import_command, output / "import.log", args.timeout, env)
        status["import_exit_code"] = import_code

        run_command = [
            "xvfb-run",
            "-a",
            "-s",
            "-screen 0 1280x720x24",
            str(godot),
            "--path",
            str(project),
            "--script",
            "res://godot_probe.gd",
        ]
        run_code = 125
        if import_code == 0:
            run_code = run_logged(run_command, output / "run.log", args.timeout, env)
        else:
            (output / "run.log").write_text("Runtime probe skipped because GLB import failed.\n", encoding="utf-8")
        status["run_exit_code"] = run_code
        report_source = probe_output / "godot-report.json"
        if report_source.is_file():
            shutil.copy2(report_source, output / "godot-report.json")
        for image_name in ("neutral.png", "articulated.png"):
            image_source = probe_output / image_name
            if image_source.is_file():
                shutil.copy2(image_source, output / image_name)

    report_path = output / "godot-report.json"
    report: dict[str, Any] = {}
    if report_path.is_file():
        report = json.loads(report_path.read_text(encoding="utf-8"))
    status["report_all_checks_pass"] = report.get("all_checks_pass", False)
    status["checks"] = report.get("checks", {})
    status["evidence_files"] = {name: (output / name).is_file() for name in OUTPUT_NAMES if name != "runner-status.json"}
    status["ok"] = (
        status["import_exit_code"] == 0
        and status["run_exit_code"] == 0
        and status["report_all_checks_pass"]
        and status["evidence_files"].get("neutral.png", False)
        and status["evidence_files"].get("articulated.png", False)
    )
    (output / "runner-status.json").write_text(json.dumps(status, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(status, indent=2))
    return 0 if status["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
