#!/usr/bin/env python3
"""EL1e product-path proof for both explicit synthetic electric Stik configurations."""

from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
APP = ROOT / "app"
DEMOS = ("4s", "6s")
FPCS = (30, 60, 144)
ELECTRIC_LAW = "electric-fixed-bus-coupled-stop-v1"
ENGINE_ERROR = re.compile(r"(?m)^(?:SCRIPT |SHADER )?ERROR:")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command: list[str], cwd: Path, log_path: Path, timeout: int = 120) -> str:
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    output = result.stdout + result.stderr
    log_path.write_text(output, encoding="utf-8")
    if result.returncode != 0:
        raise RuntimeError(f"command exited {result.returncode}: {command!r}; see {log_path}")
    if ENGINE_ERROR.search(output):
        raise RuntimeError(f"Godot emitted an engine error: {command!r}; see {log_path}")
    return output


def parse_trace(path: Path) -> tuple[dict[str, str], list[str], list[dict[str, str]]]:
    lines = path.read_text(encoding="utf-8").splitlines()
    metadata: dict[str, str] = {}
    header_index = -1
    for index, line in enumerate(lines):
        if line.startswith("# "):
            body = line[2:]
            if ": " in body:
                key, value = body.split(": ", 1)
                metadata[key] = value
        else:
            header_index = index
            break
    if header_index < 0:
        raise ValueError(f"trace has no CSV header: {path}")
    reader = csv.DictReader(lines[header_index:])
    rows = list(reader)
    return metadata, list(reader.fieldnames or []), rows


def write_summary(path: Path, summary: dict[str, Any]) -> None:
    path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=Path("/tmp/openrc-el-product"),
                        help="directory for logs and the machine-readable result")
    args = parser.parse_args()
    out: Path = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    package_dir = out / "linux-package"
    package_dir.mkdir(parents=True, exist_ok=True)
    summary_path = out / "product-check.json"
    summary: dict[str, Any] = {
        "format": "openrc-el1e-product-proof v1",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "status": "running",
        "engine": "",
        "demos": {},
        "linux_package": {},
    }
    write_summary(summary_path, summary)

    try:
        engine = os.environ.get("OPENRC_TEST_GODOT") or subprocess.check_output(
            [str(ROOT / "app" / "get-godot.sh")], cwd=ROOT, text=True
        ).strip()
        version = run([engine, "--version"], ROOT, out / "engine-version.log", timeout=20).strip()
        summary["engine"] = version
        summary["engine_path"] = engine
        summary["export_template"] = str(Path.home() / ".local/share/godot/export_templates/4.7.2.stable/linux_release.x86_64")
        template = Path(summary["export_template"])
        if not template.is_file():
            raise RuntimeError(f"pinned Linux export template is not already installed: {template}; no download attempted")

        expected_hashes: dict[str, str] = {}
        for demo in DEMOS:
            dataset = APP / "data" / "aircraft" / f"synthetic_stik_electric_{demo}.json"
            expected_hashes[demo] = sha256(dataset)
            result: dict[str, Any] = {
                "dataset": str(dataset.relative_to(ROOT)),
                "dataset_sha256": expected_hashes[demo],
                "main_scene_input": {},
                "fixed_fps": {},
            }
            main_command = [engine, "--headless", "--path", str(APP), "--audio-driver", "Dummy",
                            "--script", "res://tests/test_electric_input.gd", "--", f"--electric-demo={demo}"]
            main_log = out / f"{demo}-main-input.log"
            main_output = run(main_command, ROOT, main_log, timeout=60)
            expected_marker = f"EL1e electric input {demo}:"
            if expected_marker not in main_output or not re.search(
                    rf"(?m)^{re.escape(expected_marker)} 19 checks, 0 failed$", main_output):
                raise RuntimeError(f"main-scene input checks did not complete successfully; see {main_log}")
            result["main_scene_input"] = {
                "command": main_command,
                "log": str(main_log),
                "status": "passed",
                "checks": int(re.search(rf"(?m)^{re.escape(expected_marker)} (\d+) checks, 0 failed$", main_output).group(1)),
            }

            fixed_hashes: dict[str, str] = {}
            for fps in FPCS:
                command = [engine, "--headless", "--path", str(APP), "--audio-driver", "Dummy",
                           "--fixed-fps", str(fps), "--script", "res://tests/run_fixed_step.gd",
                           "--", f"--electric-demo={demo}"]
                log_path = out / f"{demo}-fixed-{fps}.log"
                output = run(command, ROOT, log_path, timeout=60)
                flight_match = re.search(r"(?m)^flight_sha256=([0-9a-f]{64})$", output)
                ticks_match = re.search(r"(?m)^ticks=(\d+) ", output)
                if not flight_match or not ticks_match or ticks_match.group(1) != "480":
                    raise RuntimeError(f"fixed-step runner omitted complete checkpoint at {fps} fps; see {log_path}")
                fixed_hashes[str(fps)] = flight_match.group(1)
                result["fixed_fps"][str(fps)] = {
                    "command": command,
                    "log": str(log_path),
                    "ticks": int(ticks_match.group(1)),
                    "flight_sha256": flight_match.group(1),
                }
            if len(set(fixed_hashes.values())) != 1:
                raise RuntimeError(f"complete flight checkpoint depends on rendering FPS for {demo}: {fixed_hashes}")
            result["flight_sha256_equal_at_30_60_144"] = True
            summary["demos"][demo] = result
            write_summary(summary_path, summary)

        summary["invalid_demo_controls"] = []
        for index, options in enumerate((("--electric-demo=3s",),
                                         ("--electric-demo=4s", "--aircraft=gp-extra-300s-60"),
                                         ("--electric-demo=6s", "--scripted"))):
            refused_trace = out / f"refused-demo-{index}.csv"
            refused_trace.unlink(missing_ok=True)
            command = [engine, "--headless", "--path", str(APP), "--", *options,
                       f"--trace={refused_trace}", "--t=0.2"]
            refused = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=60)
            output = refused.stdout + refused.stderr
            (out / f"refused-demo-{index}.log").write_text(output)
            if refused.returncode == 0 or refused_trace.exists() or "electric demo requires" not in output or ENGINE_ERROR.search(output):
                raise RuntimeError(f"invalid electric demo was not refused cleanly: {options}")
            summary["invalid_demo_controls"].append({"options": list(options), "exit_code": refused.returncode})

        binary = package_dir / "openrc-electric.x86_64"
        export_command = [engine, "--headless", "--path", str(APP), "--export-release", "Linux", str(binary)]
        export_log = out / "linux-export.log"
        export_output = run(export_command, ROOT, export_log, timeout=240)
        if not binary.is_file() or binary.stat().st_size == 0:
            raise RuntimeError(f"Linux export did not produce a binary; see {export_log}")
        package_result: dict[str, Any] = {
            "export_command": export_command,
            "export_log": str(export_log),
            "binary": str(binary),
            "binary_sha256": sha256(binary),
            "binary_size_bytes": binary.stat().st_size,
            "embedded_pck": "preset option binary_format/embed_pck=true",
            "export_output_tail": export_output.splitlines()[-8:],
            "runs_from_empty_cwd": True,
            "traces": {},
        }
        for demo in DEMOS:
            empty_cwd = out / f"empty-cwd-{demo}"
            empty_cwd.mkdir(exist_ok=True)
            if any(empty_cwd.iterdir()):
                raise RuntimeError(f"export smoke working directory is not empty: {empty_cwd}")
            trace = out / f"linux-{demo}.csv"
            command = [str(binary), "--headless", "--", f"--electric-demo={demo}",
                       f"--trace={trace}", "--t=0.2"]
            log_path = out / f"linux-{demo}.log"
            run(command, empty_cwd, log_path, timeout=60)
            if not trace.is_file() or trace.stat().st_size == 0:
                raise RuntimeError(f"exported {demo} build did not write a trace; see {log_path}")
            metadata, columns, rows = parse_trace(trace)
            if metadata.get("format") != "openrc-trace v7":
                raise RuntimeError(f"exported {demo} trace is not v7: {metadata.get('format')!r}")
            if metadata.get("aircraft_input_sha256") != expected_hashes[demo]:
                raise RuntimeError(f"packaged {demo} dataset SHA mismatch: {metadata.get('aircraft_input_sha256')!r}")
            if metadata.get("propulsion_model") != ELECTRIC_LAW:
                raise RuntimeError(f"packaged {demo} trace has wrong propulsion kind: {metadata.get('propulsion_model')!r}")
            if metadata.get("shaft_integrator") != "coupled-rk4":
                raise RuntimeError(f"packaged {demo} trace is missing the coupled electric solver")
            if len(rows) != 49 or [int(float(row["tick"])) for row in rows] != list(range(49)):
                raise RuntimeError(f"packaged {demo} trace did not advance 48 contiguous 240 Hz ticks")
            if not {"drive_duty", "motor_current_a", "drive_bus_current_a"}.issubset(columns):
                raise RuntimeError(f"packaged {demo} trace is missing electrical columns: {columns}")
            package_result["traces"][demo] = {
                "command": command,
                "log": str(log_path),
                "trace": str(trace),
                "format": metadata["format"],
                "aircraft_input_sha256": metadata["aircraft_input_sha256"],
                "propulsion_model": metadata["propulsion_model"],
                "shaft_integrator": metadata["shaft_integrator"],
                "rows": len(rows),
                "first_tick": int(float(rows[0]["tick"])),
                "last_tick": int(float(rows[-1]["tick"])),
                "electrical_columns": [name for name in columns if name in {
                    "drive_duty", "motor_current_a", "drive_bus_current_a"}],
                "empty_cwd": str(empty_cwd),
            }
            write_summary(summary_path, summary)
        summary["linux_package"] = package_result
        summary["status"] = "passed"
        write_summary(summary_path, summary)
        print(json.dumps({"status": summary["status"], "summary": str(summary_path),
                          "binary_sha256": package_result["binary_sha256"],
                          "flight_sha256": {demo: summary["demos"][demo]["fixed_fps"]["30"]["flight_sha256"]
                                            for demo in DEMOS}}, indent=2))
        return 0
    except Exception as error:
        summary["status"] = "failed"
        summary["error"] = str(error)
        write_summary(summary_path, summary)
        print(f"EL1e product check failed: {error}", file=sys.stderr)
        print(f"Machine-readable summary: {summary_path}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
