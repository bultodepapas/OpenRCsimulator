#!/usr/bin/env python3
"""Smoke the exported Linux UI and compare its existing direct-flight CLI routes."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from typing import Any


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
APP = ROOT / "app"
GUI_WORKER = HERE / "export_gui_smoke.py"
DEFAULT_BINARY = ROOT / "dist/linux/openrc-simulator.x86_64"
STIK_DATA = APP / "data/aircraft/jensen_ugly_stik_60.json"
EXTRA_DATA = APP / "data/aircraft/gp_extra_300s_60.json"
FIELD_DATA = APP / "data/fields/default.json"
RUNTIME_SOURCES = [
    APP / "main.gd",
    APP / "app_root.gd",
    APP / "app_state/preferences.gd",
    APP / "sim/flight_session.gd",
    APP / "ui/home.gd",
]
FORMAT = "openrc-ui06c-export-smoke v1"


class SmokeFailure(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def git_text(*args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(ROOT), *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    return result.stdout.strip()


def run_command(
    command: list[str], env: dict[str, str], label: str, log: list[dict[str, Any]], timeout: int = 120
) -> subprocess.CompletedProcess[str]:
    try:
        result = subprocess.run(
            command,
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        output = exc.stdout or ""
        if isinstance(output, bytes):
            output = output.decode("utf-8", errors="replace")
        log.append({"label": label, "command": command, "exit_code": None, "timed_out": True, "output": output})
        raise SmokeFailure(f"{label} timed out after {timeout}s") from exc
    log.append(
        {"label": label, "command": command, "exit_code": result.returncode, "timed_out": False, "output": result.stdout}
    )
    if result.returncode != 0:
        raise SmokeFailure(f"{label} exited {result.returncode}; see the run log")
    return result


def parse_trace(path: Path) -> tuple[dict[str, str], list[str], list[list[str]]]:
    metadata: dict[str, str] = {}
    header: list[str] = []
    rows: list[list[str]] = []
    with path.open(newline="", encoding="utf-8") as source:
        for line in source:
            if line.startswith("# "):
                key, separator, value = line[2:].rstrip("\r\n").partition(": ")
                if separator:
                    metadata[key] = value
                continue
            if not line.strip():
                continue
            cells = next(csv.reader([line]))
            if not header:
                header = cells
            else:
                rows.append(cells)
    if not header or not rows:
        raise SmokeFailure(f"{path} is not a nonempty OpenRC trace")
    return metadata, header, rows


def compare_trace_rows(source_path: Path, export_path: Path) -> dict[str, Any]:
    source_meta, source_header, source_rows = parse_trace(source_path)
    export_meta, export_header, export_rows = parse_trace(export_path)
    if source_header != export_header:
        raise SmokeFailure("source/export trace column headers differ")
    if len(source_rows) != len(export_rows):
        raise SmokeFailure(f"source/export row counts differ: {len(source_rows)} vs {len(export_rows)}")
    if any(len(row) != len(source_header) for row in source_rows + export_rows):
        raise SmokeFailure("source/export trace row width differs from its header")

    max_absolute_difference = 0.0
    numeric_equal_at_csv_precision = True
    exact_serialized_match = source_rows == export_rows
    for row_index, (source_row, export_row) in enumerate(zip(source_rows, export_rows)):
        for column_index, (source_value, export_value) in enumerate(zip(source_row, export_row)):
            try:
                left = float(source_value)
                right = float(export_value)
            except ValueError as exc:
                raise SmokeFailure(f"non-numeric trace value at row {row_index}, column {column_index}") from exc
            difference = abs(left - right)
            max_absolute_difference = max(max_absolute_difference, difference)
            if not math.isclose(left, right, rel_tol=0.0, abs_tol=1.0e-9):
                numeric_equal_at_csv_precision = False
    if not numeric_equal_at_csv_precision:
        raise SmokeFailure(f"source/export numeric traces differ; max absolute difference {max_absolute_difference:.12g}")

    source_rows_bytes = ("\n".join(",".join(row) for row in source_rows) + "\n").encode("utf-8")
    export_rows_bytes = ("\n".join(",".join(row) for row in export_rows) + "\n").encode("utf-8")
    return {
        "sample_rows": len(source_rows),
        "column_count": len(source_header),
        "header_sha256": hashlib.sha256(",".join(source_header).encode("utf-8")).hexdigest(),
        "source_numeric_rows_sha256": hashlib.sha256(source_rows_bytes).hexdigest(),
        "export_numeric_rows_sha256": hashlib.sha256(export_rows_bytes).hexdigest(),
        "exact_serialized_rows_match": exact_serialized_match,
        "numeric_match_at_csv_precision": numeric_equal_at_csv_precision,
        "max_absolute_difference": max_absolute_difference,
        "source_selected_start": source_meta.get("selected_start_choice", ""),
        "export_selected_start": export_meta.get("selected_start_choice", ""),
        "export_launch_choice": export_meta.get("launch_choice", ""),
        "export_aircraft": export_meta.get("aircraft", ""),
    }


def settings_start_choice(path: Path) -> str:
    if not path.is_file():
        return ""
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("start_choice="):
            return line.partition("=")[2].strip().strip('"')
    return ""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=DEFAULT_BINARY, help="exported Linux executable")
    parser.add_argument("--godot", help="pinned Godot executable; defaults to app/get-godot.sh")
    parser.add_argument("--out", type=Path, default=HERE / "evidence", help="evidence output directory")
    parser.add_argument("--taxi-seconds", type=float, default=6.0, help="wall seconds to hold W in the exported manual route")
    parser.add_argument("--trace-seconds", type=float, default=2.0, help="duration for source/export numeric traces")
    parser.add_argument("--skip-capture", action="store_true", help="skip the optional Xvfb scripted capture route")
    args = parser.parse_args()

    binary = args.binary.resolve()
    out = args.out.resolve()
    if not binary.is_file() or not os.access(binary, os.X_OK):
        parser.error(f"exported Linux executable missing or not executable: {binary}")
    if not GUI_WORKER.is_file():
        parser.error(f"exported GUI worker missing: {GUI_WORKER}")
    if args.taxi_seconds <= 0.0 or args.trace_seconds <= 0.0:
        parser.error("taxi and trace durations must be positive")

    if args.godot:
        godot = str(Path(args.godot).resolve())
    else:
        resolver = subprocess.run(
            [str(APP / "get-godot.sh")],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )
        godot = resolver.stdout.strip()
    if not Path(godot).is_file():
        parser.error(f"pinned Godot executable missing: {godot}")

    out.mkdir(parents=True, exist_ok=True)
    aggregate_path = out / "export-smoke.json"
    log_path = out / "export-smoke.log"
    capture_png = out / "scripted-capture.png"
    capture_manifest = out / "scripted-capture.json"
    evidence_names = [
        "manual-launch.json",
        "runway-manual.csv",
        "runway-r-restart.csv",
        "runway-pause-restart.csv",
        "home-airborne.png",
        "home-runway.png",
        "flight-runway.png",
        "flight-taxi.png",
        "flight-pause-restart.png",
        "exported-gui.log",
    ]
    for path in [out / name for name in evidence_names] + [aggregate_path, log_path, capture_png, capture_manifest]:
        path.unlink(missing_ok=True)

    command_log: list[dict[str, Any]] = []
    report: dict[str, Any] = {
        "format": FORMAT,
        "binary": str(binary),
        "binary_sha256": sha256_file(binary),
        "godot_executable": godot,
        "source_data": {
            "stik_path": str(STIK_DATA.relative_to(ROOT)),
            "stik_sha256": sha256_file(STIK_DATA),
            "extra_path": str(EXTRA_DATA.relative_to(ROOT)),
            "extra_sha256": sha256_file(EXTRA_DATA),
            "field_path": str(FIELD_DATA.relative_to(ROOT)),
            "field_sha256": sha256_file(FIELD_DATA),
            "project_sha256": sha256_file(APP / "project.godot"),
        },
        "runtime_source_sha256": {
            str(path.relative_to(ROOT)): sha256_file(path) for path in RUNTIME_SOURCES
        },
        "source_identity": {
            "git_head": git_text("rev-parse", "HEAD"),
            "git_describe": git_text("describe", "--tags", "--always", "--dirty"),
            "dirty_paths": git_text("status", "--short").splitlines(),
        },
        "manual_route": {},
        "cli_routes": {},
        "preference_isolation": {},
        "capture_route": {"status": "skipped"},
        "logs": str(log_path),
    }

    try:
        with tempfile.TemporaryDirectory(prefix="openrc-ui06c-") as temporary:
            temp_root = Path(temporary)
            xdg_data = temp_root / "xdg-data"
            xdg_cache = temp_root / "xdg-cache"
            xdg_data.mkdir(parents=True, exist_ok=True)
            xdg_cache.mkdir(parents=True, exist_ok=True)
            env = os.environ.copy()
            env.update({"XDG_DATA_HOME": str(xdg_data), "XDG_CACHE_HOME": str(xdg_cache), "LP_NUM_THREADS": "4"})
            xvfb = shutil.which("xvfb-run")
            if not xvfb and not env.get("DISPLAY"):
                raise SmokeFailure("the exported interactive route needs Xvfb (xvfb-run) or an existing display")
            settings_path = xdg_data / "godot/app_userdata/OpenRC Simulator/settings.cfg"

            gui_command: list[str] = []
            if xvfb and not env.get("DISPLAY"):
                gui_command.extend([str(xvfb), "-a", "-s", "-screen 0 1280x720x24"])
            gui_command.extend([
                sys.executable,
                str(GUI_WORKER),
                "--binary",
                str(binary),
                "--out",
                str(out),
                "--settings",
                str(settings_path),
                "--taxi-seconds",
                str(args.taxi_seconds),
            ])
            run_command(gui_command, env, "exported Home-to-runway native GUI route", command_log, timeout=300)
            manual_report_path = out / "manual-launch.json"
            if not manual_report_path.is_file():
                raise SmokeFailure("exported GUI worker exited without writing its manual-launch report")
            manual = json.loads(manual_report_path.read_text(encoding="utf-8"))
            if manual.get("format") != "openrc-ui06c-export-gui-smoke v1" or manual.get("passed") is not True:
                raise SmokeFailure("exported GUI route reported a failed check")
            try:
                settings_path.relative_to(xdg_data.resolve())
            except ValueError as exc:
                raise SmokeFailure(f"settings path escaped temporary XDG_DATA_HOME: {settings_path}") from exc
            if not settings_path.is_file() or settings_start_choice(settings_path) != "runway":
                raise SmokeFailure("Home Fly did not persist start_choice=runway under temporary XDG_DATA_HOME")

            # The interactive route writes runway to preferences. Direct CLI routes must ignore them, so keep a
            # runway sentinel and require their traces to report airborne.
            sentinel = (
                '[meta]\nschema=1\n\n[ui]\nlanguage="en"\nfirst_flight_hint_seen=true\n'
                '\n[flight]\naircraft="jensen-das-ugly-stik-60"\nstart_choice="runway"\n'
            ).encode("utf-8")
            settings_path.write_bytes(sentinel)
            sentinel_hash = sha256_file(settings_path)

            route_results: dict[str, Any] = {}
            trace_cases = [
                ("stik", [], "jensen-das-ugly-stik-60", report["source_data"]["stik_sha256"]),
                ("extra", ["--aircraft=gp-extra-300s-60"], "gp-extra-300s-60", report["source_data"]["extra_sha256"]),
            ]
            for case_name, aircraft_args, expected_aircraft, expected_hash in trace_cases:
                source_trace = temp_root / f"source-{case_name}.csv"
                export_trace = temp_root / f"export-{case_name}.csv"
                duration_text = f"{args.trace_seconds:.6g}"
                source_command = [
                    godot, "--headless", "--path", str(APP), "--audio-driver", "Dummy", "--", *aircraft_args,
                    f"--trace={source_trace}", f"--t={duration_text}",
                ]
                export_command = [
                    str(binary), "--headless", "--audio-driver", "Dummy", "--", *aircraft_args,
                    f"--trace={export_trace}", f"--t={duration_text}",
                ]
                before_hash = sha256_file(settings_path)
                run_command(source_command, env, f"source {case_name} trace", command_log)
                source_unchanged = settings_path.read_bytes() == sentinel and sha256_file(settings_path) == before_hash
                if not source_unchanged:
                    raise SmokeFailure(f"source {case_name} trace modified settings.cfg")
                run_command(export_command, env, f"export {case_name} trace", command_log)
                export_unchanged = settings_path.read_bytes() == sentinel and sha256_file(settings_path) == sentinel_hash
                if not export_unchanged:
                    raise SmokeFailure(f"export {case_name} trace modified settings.cfg")
                comparison = compare_trace_rows(source_trace, export_trace)
                source_meta, _, _ = parse_trace(source_trace)
                export_meta, _, _ = parse_trace(export_trace)
                for route_label, route_meta in (("source", source_meta), ("export", export_meta)):
                    if (
                        route_meta.get("selected_start_choice") != "airborne"
                        or route_meta.get("launch_choice") != "airborne"
                    ):
                        raise SmokeFailure(
                            f"{route_label} {case_name} trace followed the saved runway preference instead of the airborne CLI route"
                        )
                if not export_meta.get("aircraft", "").startswith(expected_aircraft):
                    raise SmokeFailure(f"export {case_name} trace selected the wrong aircraft")
                if source_meta.get("launch_choice") != export_meta.get("launch_choice"):
                    raise SmokeFailure(f"source/export {case_name} direct launch metadata differs")
                if source_meta.get("aircraft_input_sha256") != expected_hash or export_meta.get("aircraft_input_sha256") != expected_hash:
                    raise SmokeFailure(f"source/export {case_name} trace does not identify exact aircraft input bytes")
                route_results[case_name] = {
                    **comparison,
                    "source_trace_sha256": sha256_file(source_trace),
                    "export_trace_sha256": sha256_file(export_trace),
                    "settings_unchanged_after_source": source_unchanged,
                    "settings_unchanged_after_export": export_unchanged,
                }

            quick_command = [
                str(binary), "--headless", "--audio-driver", "Dummy", "--quit-after", "10", "--", "--quick-flight",
            ]
            before_quick_hash = sha256_file(settings_path)
            run_command(quick_command, env, "export --quick-flight route", command_log)
            quick_unchanged = settings_path.read_bytes() == sentinel and sha256_file(settings_path) == before_quick_hash
            if not quick_unchanged:
                raise SmokeFailure("export --quick-flight modified settings.cfg")
            route_results["quick_flight"] = {"exit_code": 0, "settings_unchanged": quick_unchanged}

            report["preference_isolation"] = {
                "xdg_data_root": str(xdg_data),
                "xdg_cache_root": str(xdg_cache),
                "settings_path": str(settings_path),
                "manual_route_saved_start_choice": "runway",
                "cli_route_sentinel_sha256": sentinel_hash,
                "cli_route_sentinel_start_choice": "runway",
                "cli_trace_expected_selected_and_launch_start": "airborne",
                "cli_routes_preserved_sentinel": True,
            }
            report["cli_routes"] = route_results

            if args.skip_capture:
                report["capture_route"] = {"status": "skipped", "reason": "--skip-capture"}
            elif not env.get("DISPLAY") and not xvfb:
                report["capture_route"] = {"status": "skipped", "reason": "no display and xvfb-run is unavailable"}
            else:
                capture_command = [
                    str(binary), "--audio-driver", "Dummy", "--", "--scripted", "--capture", "--t=0.25",
                    f"--out={capture_png}",
                ]
                if not env.get("DISPLAY"):
                    capture_command = [str(xvfb), "-a", "-s", "-screen 0 1280x720x24", *capture_command]
                before_capture_hash = sha256_file(settings_path)
                run_command(capture_command, env, "export scripted capture route", command_log, timeout=180)
                if not capture_png.is_file() or not capture_manifest.is_file():
                    raise SmokeFailure("export scripted capture did not write its PNG and manifest")
                capture_data = json.loads(capture_manifest.read_text(encoding="utf-8"))
                capture_unchanged = settings_path.read_bytes() == sentinel and sha256_file(settings_path) == before_capture_hash
                if not capture_unchanged:
                    raise SmokeFailure("export scripted capture modified settings.cfg")
                report["capture_route"] = {
                    "status": "passed",
                    "png": str(capture_png),
                    "png_sha256": sha256_file(capture_png),
                    "manifest": capture_data,
                    "settings_unchanged": capture_unchanged,
                }

            manual_meta = manual.get("manual_trace", {}).get("metadata", {})
            if manual_meta.get("aircraft_input_sha256") != report["source_data"]["stik_sha256"]:
                raise SmokeFailure("manual runway trace does not identify the exact Stik input bytes")
            report["manual_route"] = manual
            report["export_identity"] = {
                "app_build_describe": manual_meta.get("app_build", ""),
                "app_version": manual_meta.get("app_version", ""),
                "binary_sha256": report["binary_sha256"],
                "source_git_head": report["source_identity"]["git_head"],
                "source_git_describe": report["source_identity"]["git_describe"],
                "build_describe_matches_source_git_describe": manual_meta.get("app_build")
                == report["source_identity"]["git_describe"],
                "dirty": str(manual_meta.get("app_build", "")).endswith("-dirty"),
            }
            report["manual_trace"] = manual.get("manual_trace", {})
            report["restart_traces"] = {
                "r": manual.get("r_restart_trace", {}),
                "pause": manual.get("pause_restart_trace", {}),
            }
            report["settings_path"] = str(settings_path)
            report["passed"] = True
            report["finished_utc"] = subprocess.run(
                ["date", "-u", "+%Y-%m-%dT%H:%M:%SZ"], text=True, capture_output=True, check=True
            ).stdout.strip()
    except (SmokeFailure, subprocess.CalledProcessError, OSError, json.JSONDecodeError, KeyError, ValueError) as exc:
        report["passed"] = False
        report["failure"] = str(exc)
    finally:
        log_text = "\n\n".join(
            f"### {entry['label']} (exit={entry['exit_code']})\n$ {' '.join(entry['command'])}\n{entry['output']}"
            for entry in command_log
        )
        log_path.write_text(log_text + ("\n" if log_text else ""), encoding="utf-8")
        aggregate_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(json.dumps(report, indent=2, sort_keys=True))
    if report.get("passed"):
        print(f"UI-06c exported smoke passed; evidence: {aggregate_path}")
        return 0
    print(f"UI-06c exported smoke failed; inspect {log_path} and {aggregate_path}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
