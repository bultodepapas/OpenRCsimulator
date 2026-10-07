#!/usr/bin/env python3
"""Verify E0b6p's native whole-load kernel in a disposable Godot app copy."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Any


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BENCH_SOURCE = ROOT / "research/propwash/e0b6p/bench_swirl.gd"
ERROR_RE = re.compile(r"(?m)^(?:SCRIPT ERROR:|ERROR:|Parse Error:)")
COMPONENTS = ("state", "aux", "continuous")
REGIMES = ("forward", "stall", "static", "spin", "reverse_fade", "reverse_off")


def _platform_key() -> str:
    if sys.platform.startswith("linux"):
        return "linux"
    if sys.platform == "win32":
        return "windows"
    if sys.platform == "darwin":
        return "macos"
    raise RuntimeError(f"Unsupported host platform: {sys.platform}")


def _resolve_godot(value: str) -> str:
    candidate = Path(value).expanduser()
    if candidate.exists():
        return str(candidate.resolve())
    found = shutil.which(value)
    if found is None:
        raise RuntimeError(f"Godot executable does not exist or is not on PATH: {value}")
    return found


def _copy_project(source: Path, destination: Path) -> None:
    if not source.is_dir():
        raise RuntimeError(f"--project must be an app directory: {source}")
    shutil.copytree(
        source,
        destination,
        ignore=shutil.ignore_patterns(".godot", "captures", ".git", "__pycache__"),
    )


def _install_probe(project: Path, library: Path) -> Path:
    if not library.is_file():
        raise RuntimeError(f"Native library does not exist: {library}")
    probe = project / "tests/e0b6p_native"
    probe.mkdir(parents=True, exist_ok=True)
    for name in ("adapter.gd", "verify.gd", "profile.gd"):
        source = HERE / name
        if not source.is_file():
            raise RuntimeError(f"Required harness file is missing: {source}")
        shutil.copy2(source, probe / name)
    installed_library = probe / library.name
    shutil.copy2(library, installed_library)
    extension = probe / "smooth_wake.gdextension"
    extension.write_text(
        "[configuration]\n"
        'entry_symbol = "openrc_smooth_wake_library_init"\n'
        'compatibility_minimum = "4.7"\n'
        "reloadable = false\n\n"
        "[libraries]\n"
        f'{_platform_key()} = "res://tests/e0b6p_native/{library.name}"\n',
        encoding="utf-8",
    )
    return probe


def _instrument_bench(project: Path) -> Path:
    source = BENCH_SOURCE.read_text(encoding="utf-8")
    start = "func _initialize() -> void:\n\tvar rows: Array = []"
    end = "\tfile.store_string(JSON.stringify({format = \"openrc-e0b6p-swirl-cost v1\", ticks_per_batch = TICKS,\n\t\tcpu = OS.get_processor_name(), godot = Engine.get_version_info().string, rows = rows}, \"\\t\", true, true)+\"\\n\")"
    if source.count(start) != 1 or source.count(end) != 1:
        raise RuntimeError("bench_swirl.gd changed; could not apply the temporary route-count probe")
    source = source.replace(
        "const TICKS: int = 24\n",
        'const TICKS: int = 24\nconst NativeAdapter = preload("res://tests/e0b6p_native/adapter.gd")\n',
        1,
    )
    source = source.replace(start, "func _initialize() -> void:\n\tNativeAdapter.reset_route_counts()\n\tvar rows: Array = []", 1)
    source = source.replace(
        end,
        "\tfile.store_string(JSON.stringify({format = \"openrc-e0b6p-swirl-cost v1\", ticks_per_batch = TICKS,\n"
        "\t\tcpu = OS.get_processor_name(), godot = Engine.get_version_info().string, rows = rows,\n"
        "\t\tnative_route_counts = NativeAdapter.route_counts}, \"\\t\", true, true)+\"\\n\")",
        1,
    )
    destination = project / "tests/e0b6p_native/bench_swirl.gd"
    destination.write_text(source, encoding="utf-8")
    return destination


def _replace_dynamics_slipstream(project: Path, adapter: bool) -> None:
    path = project / "physics/dynamics.gd"
    content = path.read_text(encoding="utf-8")
    original = 'const Slipstream := preload("res://physics/slipstream.gd")'
    replacement = 'const Slipstream := preload("res://tests/e0b6p_native/adapter.gd")'
    if adapter:
        if content.count(original) != 1:
            raise RuntimeError("Dynamics.gd did not contain exactly one original Slipstream preload")
        content = content.replace(original, replacement, 1)
    else:
        if content.count(replacement) != 1:
            raise RuntimeError("Dynamics.gd did not contain exactly one temporary adapter preload")
        content = content.replace(replacement, original, 1)
    path.write_text(content, encoding="utf-8")


def _run_godot(godot: str, project: Path, script: Path, report: Path, *, timeout: int) -> str:
    command = [godot, "--headless", "--path", str(project), "--script", str(script), "--", str(report)]
    result = subprocess.run(command, text=True, capture_output=True, timeout=timeout, check=False)
    combined = result.stdout + result.stderr
    (report.parent / f"{report.stem}.log").write_text(combined, encoding="utf-8")
    if result.returncode != 0 or ERROR_RE.search(combined):
        raise RuntimeError(
            f"Godot script failed ({result.returncode}): {script}\n"
            f"Command: {' '.join(command)}\n{combined}"
        )
    if not report.is_file():
        raise RuntimeError(f"Godot exited without writing its report: {report}\n{combined}")
    return combined


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError(f"Could not read valid JSON report {path}: {error}") from error
    if not isinstance(value, dict):
        raise RuntimeError(f"Expected an object report in {path}")
    return value


def _source_hashes(project: Path) -> dict[str, str]:
    files = list(HERE.glob("*.gd")) + list(HERE.glob("*.py")) + list((HERE / "src").glob("*"))
    files += [BENCH_SOURCE, ROOT / "research/native-slipstream/build.py",
              ROOT / "research/native-slipstream/toolchain-lock.json"]
    result = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
              for path in files if path.is_file()}
    for folder in ("physics", "sim"):
        for path in sorted((project / folder).glob("*.gd")):
            result["app/" + str(path.relative_to(project))] = hashlib.sha256(path.read_bytes()).hexdigest()
    for name in ("tests/test_wash_profile.gd", "tests/test_wash_transport.gd",
                 "tests/fixtures/stik_wash_profile.json", "data/aircraft/jensen_ugly_stik_60.json"):
        result["app/" + name] = hashlib.sha256((project / name).read_bytes()).hexdigest()
    return result


def _assert_finite_number(value: Any, detail: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(float(value)):
        raise RuntimeError(f"Non-finite or non-numeric value at {detail}: {value!r}")
    return float(value)


def compare_trajectories(before: dict[str, Any], after: dict[str, Any]) -> dict[str, Any]:
    if before.get("format") != "openrc-e0b6p-swirl-cost v1" or after.get("format") != "openrc-e0b6p-swirl-cost v1":
        raise RuntimeError("Unexpected E0b6p trajectory report format")
    if len(before.get("rows", [])) != 12 or len(after.get("rows", [])) != 12:
        raise RuntimeError("Expected the E0b6p benchmark's 12 paired regimes")
    expected_roster = [(regime, factor) for regime in REGIMES for factor in (0.0, 0.4)]
    for report in (before, after):
        if [(row.get("regime"), row.get("swirl_factor")) for row in report["rows"]] != expected_roster:
            raise RuntimeError("Expected all six regimes with both zero and nonzero swirl")
    rows: list[dict[str, Any]] = []
    exact_zero_swirl = True
    maximum_ratio = 0.0
    maximum_absolute = 0.0
    absolute_tolerance = 1.0e-10
    relative_tolerance = 1.0e-10
    for old, new in zip(before["rows"], after["rows"], strict=True):
        if (old.get("regime"), old.get("swirl_factor")) != (new.get("regime"), new.get("swirl_factor")):
            raise RuntimeError("Oracle and native trajectory rows do not describe the same regime")
        old_boundaries = old.get("boundaries", [])
        new_boundaries = new.get("boundaries", [])
        if len(old_boundaries) != 240 or len(new_boundaries) != 240:
            raise RuntimeError(f"Expected 240 committed boundaries for {new.get('regime')}")
        worst = {key: 0.0 for key in COMPONENTS}
        exact = True
        worst_ratio = 0.0
        for tick, (old_boundary, new_boundary) in enumerate(zip(old_boundaries, new_boundaries, strict=True)):
            for key in COMPONENTS:
                reference = old_boundary.get(key)
                actual = new_boundary.get(key)
                if not isinstance(reference, list) or not isinstance(actual, list) or len(reference) != len(actual):
                    raise RuntimeError(f"Malformed {key} at {new.get('regime')} tick {tick}")
                expected_length = {"state": 13, "aux": 14, "continuous": 0}[key]
                if len(reference) != expected_length:
                    raise RuntimeError(
                        f"Unexpected {key} length at {new.get('regime')} tick {tick}: "
                        f"expected {expected_length}, got {len(reference)}"
                    )
                for component, (x_value, y_value) in enumerate(zip(reference, actual, strict=True)):
                    x = _assert_finite_number(x_value, f"oracle/{new.get('regime')}/{tick}/{key}/{component}")
                    y = _assert_finite_number(y_value, f"native/{new.get('regime')}/{tick}/{key}/{component}")
                    error = abs(y - x)
                    tolerance = absolute_tolerance + relative_tolerance * abs(x)
                    ratio = error / tolerance
                    worst[key] = max(worst[key], error)
                    worst_ratio = max(worst_ratio, ratio)
                    maximum_ratio = max(maximum_ratio, ratio)
                    maximum_absolute = max(maximum_absolute, error)
                    exact = exact and x == y
        if worst_ratio > 1.0:
            raise RuntimeError(
                f"Trajectory exceeded abs+rel 1e-10 for {new['regime']} swirl={new['swirl_factor']}: "
                f"ratio={worst_ratio:.6g}, errors={worst}"
            )
        if float(new["swirl_factor"]) == 0.0:
            exact_zero_swirl = exact_zero_swirl and exact
        rows.append(
            {
                "regime": new["regime"],
                "swirl_factor": new["swirl_factor"],
                "oracle_median_us": _assert_finite_number(old.get("median_us"), "oracle median"),
                "native_median_us": _assert_finite_number(new.get("median_us"), "native median"),
                "oracle_batches_us": [
                    _assert_finite_number(sample, "oracle batch") for sample in old.get("batches_us", [])
                ],
                "native_batches_us": [
                    _assert_finite_number(sample, "native batch") for sample in new.get("batches_us", [])
                ],
                "speedup": _assert_finite_number(old.get("median_us"), "oracle median")
                / max(_assert_finite_number(new.get("median_us"), "native median"), 0.5),
                "exact_boundaries": exact,
                "max_absolute_boundary_difference": worst,
                "max_tolerance_ratio": worst_ratio,
            }
        )
    return {
        "format": "openrc-e0b6p-native-trajectory-comparison v1",
        "godot": after.get("godot"),
        "cpu": after.get("cpu"),
        "trajectory_ticks": 240,
        "regime_pairs": len(rows),
        "compared_components": ["state", "aux", "continuous"],
        "tolerance": "1e-10 absolute + 1e-10 relative per component",
        "maximum_absolute_difference": maximum_absolute,
        "maximum_tolerance_ratio": maximum_ratio,
        "zero_swirl_exact": exact_zero_swirl,
        "rows": rows,
    }


def _ensure_routes(report: dict[str, Any], label: str, *, require_native: bool) -> None:
    routes = report.get("native_routes", report.get("native_route_counts"))
    if not isinstance(routes, dict):
        raise RuntimeError(f"{label} report has no route counts")
    native = int(routes.get("native", -1))
    kernel_calls = int(routes.get("kernel_calls", -1))
    legacy = int(routes.get("legacy", -1))
    refused = int(routes.get("refused", -1))
    if native < 0 or kernel_calls < 0 or legacy < 0 or refused < 0 or refused != 0:
        raise RuntimeError(f"Invalid {label} adapter route counts: {routes}")
    if require_native and (native == 0 or kernel_calls == 0 or legacy != 0):
        raise RuntimeError("The dynamics trajectory did not route loads through OpenRCSmoothWake")
    if not require_native and (native != 0 or kernel_calls != 0):
        raise RuntimeError(f"The oracle trajectory unexpectedly called the native extension: {routes}")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file_handle:
        for block in iter(lambda: file_handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _source_revision(path: Path) -> str | None:
    result = subprocess.run(
        ["git", "-C", str(path), "rev-parse", "HEAD"],
        text=True,
        capture_output=True,
        check=False,
    )
    return result.stdout.strip() if result.returncode == 0 else None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True, help="explicit stable Godot app directory")
    parser.add_argument("--godot", required=True, help="Godot 4.7 executable")
    parser.add_argument("--library", type=Path, required=True, help="built smooth wake GDExtension library")
    parser.add_argument("--output", type=Path, required=True, help="directory for raw runs and evidence JSON")
    parser.add_argument("--keep-work", action="store_true", help="retain staged app under the output directory")
    parser.add_argument("--verify-only", action="store_true", help="run direct checks and profile, skip trajectories")
    args = parser.parse_args()

    source_project = args.project.expanduser().resolve()
    library = args.library.expanduser().resolve()
    output = args.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    godot = _resolve_godot(args.godot)
    temporary: tempfile.TemporaryDirectory[str] | None = None
    if args.keep_work:
        work_root = Path(tempfile.mkdtemp(prefix="work-", dir=output))
    else:
        temporary = tempfile.TemporaryDirectory(prefix="openrc-e0b6p-native-")
        work_root = Path(temporary.name)
    work_project = work_root / "app"
    evidence: dict[str, Any] = {
        "format": "openrc-e0b6p-native-evidence v1",
        "source_sha256": _source_hashes(source_project),
        "status": "running",
        "project": str(source_project),
        "godot": godot,
        "library": str(library),
        "library_sha256": _sha256(library),
        "source_revision": _source_revision(source_project),
        "host_os": platform.platform(),
        "host_arch": platform.machine(),
        "python": platform.python_version(),
        "output": str(output),
        "verify_only": bool(args.verify_only),
        "keep_work": bool(args.keep_work),
        "work_project": str(work_project) if args.keep_work else None,
        "tolerance": "1e-10 absolute + 1e-10 relative per load/trajectory component",
    }
    evidence_path = output / "evidence.json"
    try:
        _copy_project(source_project, work_project)
        probe = _install_probe(work_project, library)
        benchmark = _instrument_bench(work_project)

        verification_path = output / "verification.json"
        _run_godot(godot, work_project, probe / "verify.gd", verification_path, timeout=180)
        verification = _read_json(verification_path)
        if int(verification.get("failures", 1)) != 0:
            raise RuntimeError(f"Direct native verification reported failures: {verification}")
        if (verification.get("format") != "openrc-e0b6p-native-verification v1"
                or verification.get("random_cases") != 256 or verification.get("compared_loads") != 297):
            raise RuntimeError("Direct verification did not exercise the complete case roster")
        required = ("transported_zero", "transported_nonzero", "rpm_stopped", "reverse_partial",
                    "reverse_cutoff", "zero_swirl", "instantaneous_downwash", "held_downwash",
                    "classic_tail", "free_slope_tail")
        if any(verification.get("coverage", {}).get(key, 0) <= 0 for key in required):
            raise RuntimeError("Direct verification omitted a required branch")
        evidence["verification"] = str(verification_path)
        evidence["verification_checks"] = verification.get("checks")
        evidence["whole_load_comparisons"] = verification.get("compared_loads")
        evidence["verification_routes"] = verification.get("native_routes")

        profile_path = output / "profile.json"
        _run_godot(godot, work_project, probe / "profile.gd", profile_path, timeout=180)
        profile = _read_json(profile_path)
        if profile.get("format") != "openrc-smooth-native-profile v1" or len(profile.get("rows", [])) != 6:
            raise RuntimeError(f"Malformed native profile report: {profile}")
        evidence["profile"] = str(profile_path)

        if not args.verify_only:
            oracle_path = output / "oracle-trajectories.json"
            native_path = output / "native-trajectories.json"
            _run_godot(godot, work_project, benchmark, oracle_path, timeout=600)
            oracle = _read_json(oracle_path)
            _ensure_routes(oracle, "GDScript oracle", require_native=False)
            _replace_dynamics_slipstream(work_project, adapter=True)
            _run_godot(godot, work_project, benchmark, native_path, timeout=600)
            native = _read_json(native_path)
            _ensure_routes(native, "native dynamics", require_native=True)
            comparison = compare_trajectories(oracle, native)
            comparison_path = output / "trajectory-comparison.json"
            comparison_path.write_text(json.dumps(comparison, indent=2, allow_nan=False) + "\n", encoding="utf-8")
            evidence["oracle_trajectories"] = str(oracle_path)
            evidence["native_trajectories"] = str(native_path)
            evidence["trajectory_comparison"] = str(comparison_path)
            evidence["native_dynamics_routes"] = native.get("native_route_counts")
            evidence["zero_swirl_exact"] = comparison.get("zero_swirl_exact")

        evidence["status"] = "pass"
        evidence_path.write_text(json.dumps(evidence, indent=2, allow_nan=False) + "\n", encoding="utf-8")
        print(f"E0b6p native harness passed; evidence: {evidence_path}")
        if args.keep_work:
            print(f"Staged app retained at: {work_project}")
    except Exception as error:  # Preserve a machine-readable failure report alongside the logs.
        evidence["status"] = "fail"
        evidence["error"] = str(error)
        evidence_path.write_text(json.dumps(evidence, indent=2, allow_nan=False) + "\n", encoding="utf-8")
        print(f"E0b6p native harness failed; evidence: {evidence_path}\n{error}", file=sys.stderr)
        raise SystemExit(1) from error
    finally:
        if temporary is not None:
            temporary.cleanup()


if __name__ == "__main__":
    main()
