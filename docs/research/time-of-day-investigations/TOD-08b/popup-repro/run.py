#!/usr/bin/env python3
"""Compare OptionButton popup close in Godot source and Linux release builds under XTest."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
from typing import Any


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[4]
PROJECT_SOURCE = HERE / "project"
DRIVER_SOURCE = REPO / "docs/research/menu-investigations/UI-06c/export_gui_smoke.py"
TITLE = "TOD-08b OptionButton Repro"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_x11_driver() -> Any:
    spec = importlib.util.spec_from_file_location("ui06c_export_gui_smoke", DRIVER_SOURCE)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load native XTest driver at {DRIVER_SOURCE}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.X11


def run_case(
    label: str,
    command: list[str],
    force_native: bool,
    work_dir: Path,
    x11_type: Any,
) -> dict[str, Any]:
    marker = work_dir / f"{label}.marker"
    log_path = work_dir / f"{label}.log"
    user_data = work_dir / f"{label}-data"
    shutil.rmtree(user_data, ignore_errors=True)
    user_data.mkdir(parents=True)
    marker.unlink(missing_ok=True)
    env = os.environ.copy()
    env["XDG_DATA_HOME"] = str(user_data)
    env["XDG_CACHE_HOME"] = str(user_data / "cache")
    env["POPUP_REPRO_FORCE_NATIVE"] = "1" if force_native else "0"
    env["POPUP_REPRO_MARKER"] = str(marker)

    x11 = None
    process = None
    with log_path.open("wb") as log:
        try:
            process = subprocess.Popen(command, cwd=work_dir, env=env, stdout=log, stderr=subprocess.STDOUT)
            x11 = x11_type()
            deadline = time.monotonic() + 20.0
            window = None
            while time.monotonic() < deadline and process.poll() is None:
                window = x11.find_window(TITLE)
                if window and marker.is_file():
                    break
                time.sleep(0.1)
            if not window or not marker.is_file():
                raise TimeoutError(f"{label}: Godot window and ready marker did not appear")
            ready = marker.read_text(encoding="utf-8").strip()
            x11.focus(window[0])
            time.sleep(0.3)
            # Open the OptionButton popup, move to item 1, and select it. This is XTest input,
            # not a scripted call to PopupMenu.popup()/hide().
            x11.tap(x11_type.XK_RETURN, settle_s=0.35)
            popup_deadline = time.monotonic() + 3.0
            while time.monotonic() < popup_deadline:
                if marker.is_file() and "popup_visible=true" in marker.read_text(encoding="utf-8"):
                    break
                time.sleep(0.05)
            marker_lines = marker.read_text(encoding="utf-8").splitlines() if marker.is_file() else []
            popup_observed = "popup_visible=true" in marker_lines
            x11.tap(x11_type.XK_DOWN, settle_s=0.15)
            x11.tap(x11_type.XK_RETURN, settle_s=0.5)
            selection_deadline = time.monotonic() + 3.0
            while time.monotonic() < selection_deadline:
                if marker.is_file() and any(line.startswith("selected=") for line in marker.read_text(encoding="utf-8").splitlines()):
                    break
                time.sleep(0.05)
            marker_lines = marker.read_text(encoding="utf-8").splitlines() if marker.is_file() else []
            selected = next((line for line in marker_lines if line.startswith("selected=")), "")
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5.0)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        finally:
            if process is not None and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5.0)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            if x11 is not None:
                x11.close()

    log_text = log_path.read_text(encoding="utf-8", errors="replace")
    errors = [line for line in log_text.splitlines() if line.startswith("ERROR:")]
    return {
        "label": label,
        "popup_mode": "force_native" if force_native else "embedded default",
        "ready_marker": ready if "ready" in locals() else "",
        "popup_observed_visible": popup_observed if "popup_observed" in locals() else False,
        "selected_marker": selected if "selected" in locals() else "",
        "selected_index_1": selected == "selected=1" if "selected" in locals() else False,
        "engine_error_count": len(errors),
        "engine_errors": errors,
        "log": log_path.name,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, default=REPO / ".tools/Godot_v4.7.2-stable_linux.x86_64")
    parser.add_argument("--work-dir", type=Path, help="preserve the temporary export and logs here")
    args = parser.parse_args()
    engine = args.engine.resolve()
    if not engine.is_file():
        raise FileNotFoundError(f"pinned Godot binary not found: {engine}")
    if not os.environ.get("DISPLAY"):
        raise RuntimeError("run under an X11 display, usually with xvfb-run -a")

    if args.work_dir:
        work_dir = args.work_dir.resolve()
        work_dir.mkdir(parents=True, exist_ok=True)
        keep_work = True
    else:
        work_dir = Path(tempfile.mkdtemp(prefix="tod08b-popup-repro-"))
        keep_work = False
    project = work_dir / "project"
    shutil.copytree(PROJECT_SOURCE, project, dirs_exist_ok=True)
    binary = work_dir / "repro.x86_64"
    export_log = work_dir / "export.log"
    with export_log.open("wb") as log:
        export = subprocess.run(
            [str(engine), "--headless", "--path", str(project), "--export-release", "Linux", str(binary)],
            cwd=work_dir,
            stdout=log,
            stderr=subprocess.STDOUT,
            check=False,
        )
    if export.returncode != 0 or not binary.is_file():
        raise RuntimeError(f"Linux release export failed; inspect {export_log}")

    version = subprocess.run([str(engine), "--version"], capture_output=True, text=True, check=True).stdout.strip()
    x11_type = load_x11_driver()
    source_command = [str(engine), "--path", str(project), "--audio-driver", "Dummy"]
    release_command = [str(binary), "--audio-driver", "Dummy"]
    cases = [
        run_case("source-embedded", source_command, False, work_dir, x11_type),
        run_case("release-embedded", release_command, False, work_dir, x11_type),
        run_case("source-native", source_command, True, work_dir, x11_type),
        run_case("release-native", release_command, True, work_dir, x11_type),
    ]
    report: dict[str, Any] = {
        "format": "openrc-tod08b-optionbutton-popup-repro v1",
        "engine_version": version,
        "engine_binary_sha256": sha256_file(engine),
        "engine_release_binary_sha256": sha256_file(binary),
        "popup_cpp_sha256": sha256_file(HERE / "popup.cpp"),
        "reproducer_script_sha256": sha256_file(HERE / "run.py"),
        "xtest_driver_sha256": sha256_file(DRIVER_SOURCE),
        "display": os.environ["DISPLAY"],
        "input": "XTestFakeKeyEvent from docs/research/menu-investigations/UI-06c/export_gui_smoke.py",
        "sequence": ["Enter opens OptionButton", "Down", "Enter selects item 1"],
        "renderer": next((line for line in (work_dir / "source-embedded.log").read_text(encoding="utf-8", errors="replace").splitlines() if line.startswith("OpenGL API ")), "not reported"),
        "xvfb_screen": "1280x720x24 (use the command in README.md)",
        "cases": cases,
        "passed": all(case["popup_observed_visible"] and case["selected_index_1"] for case in cases)
        and [case["engine_error_count"] for case in cases] == [0, 2, 0, 0],
        "work_dir_preserved": keep_work,
        "temporary_work_dir": str(work_dir),
        "binary_committed": False,
    }
    report_path = work_dir / "report.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))
    if not keep_work:
        shutil.rmtree(work_dir)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
