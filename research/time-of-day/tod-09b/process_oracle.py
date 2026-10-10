#!/usr/bin/env python3
"""Run exact TOD-09b lighting comparisons across independent Godot processes."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
APP = ROOT / "app"
GDSCRIPT = HERE / "process_oracle.gd"
CASE_IDS = [
    "00-legacy",
    "noon",
    "night",
    "dawn",
    "sunrise-60",
    "sunset-60",
    "sunrise+0",
    "sunset+0",
    "sunrise+60",
    "sunset+60",
    "99-legacy-again",
]
EXPECTED_CASES = set(CASE_IDS)
ERROR_LINE = re.compile(r"^\s*(?:(?:SCRIPT|SHADER)\s+)?ERROR:", re.IGNORECASE)
WARNING_LINE = re.compile(r"^\s*(?:(?:SCRIPT|SHADER)\s+)?WARNING:", re.IGNORECASE)


class OracleFailure(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def run_capture(command: list[str], env: dict[str, str], timeout_s: int) -> tuple[int, str, float]:
    started = time.monotonic()
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=env,
        start_new_session=True,
    )
    try:
        output, _ = process.communicate(timeout=timeout_s)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        output, _ = process.communicate()
        elapsed = time.monotonic() - started
        raise OracleFailure(f"process exceeded {timeout_s}s timeout after {elapsed:.1f}s\n{output[-4000:]}")
    return int(process.returncode), output, time.monotonic() - started


def error_lines(log: str) -> list[str]:
    return [line for line in log.splitlines() if ERROR_LINE.match(line)]


def warning_lines(log: str) -> list[str]:
    return [line for line in log.splitlines() if WARNING_LINE.match(line)]


def digest_sources() -> dict[str, str]:
    paths = [
        "app/main.gd",
        "app/render/field.gd",
        "app/render/atmosphere.gd",
        "app/render/time_of_day_lighting.gd",
        "app/render/shader_clock.gd",
        "app/render/ground.gdshader",
        "app/render/near_grass.gd",
        "app/render/near_grass.gdshader",
        "app/render/frames.gd",
        "app/render/shadow.gd",
        "app/scenery/scenery.gd",
        "app/scenery/ground_features.gd",
        "app/sim/flight_session.gd",
        "app/sim/simulation.gd",
        "app/data/fields/default.json",
        "app/data/scenery/default.json",
        "app/data/aircraft/ugly_stik_60.json",
        "research/time-of-day/tod-09b/process_oracle.gd",
        "research/time-of-day/tod-09b/process_oracle.py",
    ]
    result: dict[str, str] = {}
    for relative in paths:
        path = ROOT / relative
        if path.is_file():
            result[relative] = sha256_file(path)
        else:
            result[relative] = "missing"
    for path in sorted((APP / "data/scenery/models").glob("*.json")):
        result[path.relative_to(ROOT).as_posix()] = sha256_file(path)
    return result


def git_value(*arguments: str) -> str:
    completed = subprocess.run(
        ["git", "-C", str(ROOT), *arguments],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    return completed.stdout.strip() if completed.returncode == 0 else "unavailable"


def load_report(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise OracleFailure(f"Godot did not produce {path}")
    try:
        report = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise OracleFailure(f"Could not read {path}: {error}") from error
    if not report.get("ok", False):
        raise OracleFailure(f"Godot report was not ok: {path}")
    return report


def raw_equal(left: Path, right: Path, width: int, height: int) -> dict[str, Any]:
    left_bytes = left.read_bytes()
    right_bytes = right.read_bytes()
    equal = left_bytes == right_bytes
    first_difference: dict[str, int] | None = None
    if not equal:
        offset = next(
            (index for index, (a, b) in enumerate(zip(left_bytes, right_bytes)) if a != b),
            min(len(left_bytes), len(right_bytes)),
        )
        pixel_index = offset // 4
        first_difference = {
            "byte_offset": offset,
            "channel": offset % 4,
            "x": pixel_index % width if width else 0,
            "y": pixel_index // width if width else 0,
        }
    return {
        "exact_pixels": equal,
        "left_bytes": len(left_bytes),
        "right_bytes": len(right_bytes),
        "first_difference": first_difference,
    }


def _case_row(report: dict[str, Any], expected_id: str) -> dict[str, Any]:
    rows = report.get("captures", [])
    matching = [row for row in rows if row.get("id") == expected_id]
    if len(matching) != 1:
        raise OracleFailure(f"Expected exactly one {expected_id} capture in {report.get('role')} report")
    return matching[0]


class ProcessOracle:
    def __init__(self, args: argparse.Namespace, godot: str, output: Path):
        self.args = args
        self.godot = godot
        self.output = output
        self.process_records: list[dict[str, Any]] = []
        self.total_elapsed = 0.0
        self.env = os.environ.copy()
        self.env["LP_NUM_THREADS"] = "1"
        self.env["OPENRC_SCENERY_AUDIO"] = "off"
        self.env["OPENRC_SCENERY_BIRDS"] = "off"
        self.env.pop("OPENRC_SCENERY", None)

    def invoke(
        self,
        role: str,
        scenery: str,
        target: Path,
        case_index: int | None = None,
        mutation: str = "",
    ) -> dict[str, Any]:
        target.mkdir(parents=True, exist_ok=True)
        command = [
            self.args.xvfb_run,
            "-a",
            "-s",
            "-screen 0 1280x720x24",
            self.godot,
            "--path",
            str(APP),
            "--rendering-driver",
            "opengl3",
            "--audio-driver",
            "Dummy",
            "--script",
            str(GDSCRIPT),
            "--",
            f"--scenery={scenery}",
            f"--oracle-role={role}",
            f"--oracle-out={target}",
        ]
        if case_index is not None:
            command.append(f"--oracle-case-index={case_index}")
        if mutation:
            command.append(f"--oracle-mutation={mutation}")
        returncode, log, elapsed = run_capture(command, self.env, self.args.timeout_seconds)
        self.total_elapsed += elapsed
        log_path = target / "godot.log"
        log_path.write_text(log, encoding="utf-8")
        errors = error_lines(log)
        warnings = warning_lines(log)
        record = {
            "role": role,
            "scenery": scenery,
            "case_index": case_index,
            "mutation": mutation,
            "exit_code": returncode,
            "elapsed_s": round(elapsed, 3),
            "log": str(log_path),
            "command": command,
            "errors": errors,
            "warnings": warnings,
        }
        self.process_records.append(record)
        if returncode != 0:
            raise OracleFailure(f"Godot process failed ({returncode}); see {log_path}\n{log[-4000:]}")
        if errors:
            raise OracleFailure(f"Engine errors in {log_path}: " + " | ".join(errors))
        return load_report(target / "report.json")

    def compare_pair(
        self,
        in_place: dict[str, Any],
        fresh: dict[str, Any],
        case_id: str,
        width: int,
        height: int,
        require_pixels: bool = True,
    ) -> dict[str, Any]:
        left = _case_row(in_place, case_id)
        right = _case_row(fresh, case_id)
        image = raw_equal(Path(left["image_rgba_path"]), Path(right["image_rgba_path"]), width, height)
        metadata_fields = [
            ("lighting_config", left.get("lighting_config"), right.get("lighting_config")),
            ("lighting_snapshot", left.get("lighting_snapshot"), right.get("lighting_snapshot")),
            ("lighting_context", left.get("lighting_context"), right.get("lighting_context")),
            ("state_sha256", left.get("state_sha256"), right.get("state_sha256")),
            ("aircraft_transform_sha256", left.get("aircraft_transform_sha256"), right.get("aircraft_transform_sha256")),
            ("image_size", left.get("image_size"), right.get("image_size")),
        ]
        metadata = {name: a == b for name, a, b in metadata_fields}
        all_invariants = all(
            bool(row.get(key, False))
            for row in (left, right)
            for key in (
                "config_valid",
                "config_matches",
                "lighting_snapshot_matches",
                "lighting_context_matches",
                "state_unchanged",
                "aircraft_transform_stable",
                "capture_stable",
                "save_ok",
            )
        ) and all(
            int(row.get(key, -1)) == 0
            for row in (left, right)
            for key in ("tick_before_first_await", "tick_after_capture")
        )
        exact_metadata = all(metadata.values())
        ok = all_invariants and exact_metadata and (image["exact_pixels"] if require_pixels else True)
        return {
            "id": case_id,
            "ok": ok,
            "invariants_ok": all_invariants,
            "metadata_equal": metadata,
            "pixels": image,
            "in_place_image_sha256": left.get("image_rgba_sha256"),
            "fresh_image_sha256": right.get("image_rgba_sha256"),
            "in_place_log": next(
                (record["log"] for record in self.process_records if record.get("role") == "in-place" and record.get("scenery") == in_place.get("scenery_argument")),
                None,
            ),
        }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("/tmp/tod09b-process-matrix"))
    parser.add_argument("--scenery", choices=("both", "off", "on"), default="both")
    parser.add_argument("--timeout-seconds", type=int, default=90)
    parser.add_argument("--mutation-control", action="store_true", help="run a noon stale-Environment negative control")
    parser.add_argument("--xvfb-run", default=shutil.which("xvfb-run") or "xvfb-run")
    parser.add_argument("--godot", type=Path, help="use this Godot binary instead of app/get-godot.sh")
    return parser.parse_args()


def godot_binary(args: argparse.Namespace) -> str:
    if args.godot:
        return str(args.godot.resolve())
    result = subprocess.run(
        [str(APP / "get-godot.sh")],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        cwd=ROOT,
    )
    if result.returncode != 0:
        raise OracleFailure(f"Could not resolve pinned Godot binary:\n{result.stdout}")
    binary = result.stdout.strip().splitlines()[-1]
    if not Path(binary).is_file():
        raise OracleFailure(f"Pinned Godot binary not found: {binary}")
    return binary


def run_matrix(oracle: ProcessOracle, scenery_modes: list[str]) -> dict[str, Any]:
    mode_reports: list[dict[str, Any]] = []
    for scenery in scenery_modes:
        mode_dir = oracle.output / f"scenery-{scenery}"
        in_place = oracle.invoke("in-place", scenery, mode_dir / "in-place")
        rows = in_place.get("captures", [])
        ids = [str(row.get("id", "")) for row in rows]
        if len(ids) != 11 or set(ids) != EXPECTED_CASES or len(set(ids)) != len(ids):
            raise OracleFailure(f"The in-place {scenery} run did not report the expected 11 cases: {ids}")
        width, height = in_place.get("resolution", [960, 540])
        pair_results: list[dict[str, Any]] = []
        for index, case_id in enumerate(ids):
            fresh = oracle.invoke("fresh", scenery, mode_dir / "fresh" / case_id, case_index=index)
            if len(fresh.get("captures", [])) != 1:
                raise OracleFailure(f"Fresh process for {case_id} produced an unexpected capture count")
            pair_results.append(oracle.compare_pair(in_place, fresh, case_id, int(width), int(height)))
        mode_reports.append({
            "scenery": scenery,
            "renderer": in_place.get("renderer"),
            "adapter": in_place.get("adapter"),
            "capture_count": len(pair_results),
            "in_place_report": str(mode_dir / "in-place" / "report.json"),
            "pairs": pair_results,
            "ok": all(pair["ok"] for pair in pair_results),
        })
    return {"modes": mode_reports, "ok": all(mode["ok"] for mode in mode_reports)}


def run_mutation_control(oracle: ProcessOracle) -> dict[str, Any]:
    mode_dir = oracle.output / "mutation-control-scenery-off"
    in_place = oracle.invoke(
        "in-place",
        "off",
        mode_dir / "in-place-mutated",
        case_index=1,
        mutation="stale-environment",
    )
    fresh = oracle.invoke("fresh", "off", mode_dir / "fresh-noon", case_index=1)
    width, height = in_place.get("resolution", [960, 540])
    pair = oracle.compare_pair(in_place, fresh, "noon", int(width), int(height), require_pixels=False)
    difference_detected = not bool(pair["pixels"]["exact_pixels"])
    pair["expected_pixel_difference_detected"] = difference_detected
    pair["ok"] = bool(pair["invariants_ok"]) and all(pair["metadata_equal"].values()) and difference_detected
    return {
        "mutation": "stale-environment after production Apply",
        "scope": "scratch oracle only; production files are not mutated",
        "pair": pair,
        "ok": pair["ok"],
    }


def main() -> int:
    args = parse_args()
    output = args.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    godot = godot_binary(args)
    version_result = subprocess.run(
        [godot, "--version"], check=False, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    if version_result.returncode != 0:
        raise OracleFailure(f"Godot --version failed: {version_result.stdout}")
    oracle = ProcessOracle(args, godot, output)
    scenery_modes = ["off", "on"] if args.scenery == "both" else [args.scenery]
    report: dict[str, Any] = {
        "format": "tod09b-independent-process-matrix v1",
        "output": str(output),
        "godot_binary": godot,
        "godot_version": version_result.stdout.strip(),
        "git_revision": git_value("describe", "--always", "--dirty"),
        "git_head": git_value("rev-parse", "HEAD"),
        "git_status": git_value("status", "--short"),
        "scenery_modes_requested": scenery_modes,
        "resolution": [960, 540],
        "comparison": "exact byte equality of Image.get_data() RGBA buffers; no tolerance",
        "clock_policy": "freeze sim and presentation at tick zero before first await in each process",
        "audio_policy": "Godot Dummy driver; OPENRC_SCENERY_AUDIO=off; engine stream stopped and detached",
        "source_sha256": digest_sources(),
        "matrix": None,
        "mutation_control": None,
        "processes": oracle.process_records,
        "warnings": [],
        "elapsed_s": None,
        "ok": False,
    }
    try:
        matrix = run_matrix(oracle, scenery_modes)
        report["matrix"] = matrix
        mutation: dict[str, Any] | None = None
        if args.mutation_control:
            mutation = run_mutation_control(oracle)
            report["mutation_control"] = mutation
        report["processes"] = oracle.process_records
        report["warnings"] = [
            {"log": item["log"], "warnings": item["warnings"]}
            for item in oracle.process_records
            if item["warnings"]
        ]
        report["elapsed_s"] = round(oracle.total_elapsed, 3)
        report["ok"] = bool(matrix["ok"]) and (bool(mutation["ok"]) if mutation is not None else True)
    except (OracleFailure, OSError, KeyError, ValueError) as error:
        report["failure"] = str(error)
        report["processes"] = oracle.process_records
        report["warnings"] = [
            {"log": item["log"], "warnings": item["warnings"]}
            for item in oracle.process_records
            if item["warnings"]
        ]
        report["elapsed_s"] = round(oracle.total_elapsed, 3)
        report["ok"] = False
    report_path = output / "report.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({
        "ok": report["ok"],
        "report": str(report_path),
        "elapsed_s": report["elapsed_s"],
        "failure": report.get("failure"),
        "pairs": sum(len(mode.get("pairs", [])) for mode in (report.get("matrix") or {}).get("modes", [])),
    }, indent=2))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except OracleFailure as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
