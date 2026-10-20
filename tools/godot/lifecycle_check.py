"""Run and evaluate a bounded, fresh-process Godot lifecycle probe."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
from typing import Any, Callable

try:
    from .run_checked import ANSI, run_checked
except ImportError:  # direct script execution
    from run_checked import ANSI, run_checked


FORMAT = "openrc-lifecycle-probe v1"
SUMMARY_FORMAT = "openrc-godot-lifecycle-check v1"
MAX_REPORT_BYTES = 4 * 1024 * 1024
MAX_SOURCE_BYTES = 4 * 1024 * 1024
MAX_ENGINE_LOG_BYTES = 8 * 1024 * 1024
MAX_DETAILS = 20
MAX_WARNING_DETAILS = 10
MAX_INT = (1 << 63) - 1
MIB = 1024 * 1024
ROOT = Path(__file__).resolve().parents[2]
APP_DIR = ROOT / "app"
PROBE_SCRIPT = Path(__file__).with_name("lifecycle_probe.gd").resolve()
DEFAULT_OUT = ROOT / "tmp" / "godot-lifecycle"
WARNING_LINE = re.compile(r"^WARNING:\s*(.*)$")
SHUTDOWN_LEAK_WARNING = re.compile(r"(?:ObjectDB.*leak|resources.*in use at exit)", re.IGNORECASE)

CONFIG_KEYS = {"scenario", "cycles", "warmup_cycles", "settle_frames", "dwell_seconds"}
SAMPLE_KEYS = {
    "phase", "cycle", "monotonic_usec", "node_count", "orphan_node_count",
    "object_count", "resource_count", "static_memory_bytes",
    "retired_objects_checked", "retired_objects_alive", "orphan_details",
    "orphan_details_truncated", "sample_overhead_usec",
}
IDENTITY_KEYS = {"label", "id", "class", "script"}
TOP_KEYS = {
    "format", "capture_id", "complete", "failure", "config", "debug_build",
    "samples", "cleanup", "total_retired_alive",
}
TOP_OPTIONAL_KEYS = {"godot", "scope"}


def _strict_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def _reject_json_constant(value: str) -> None:
    raise ValueError(f"non-finite JSON number is forbidden: {value}")


def _finite_json_float(value: str) -> float:
    result = float(value)
    if not math.isfinite(result):
        raise ValueError(f"non-finite JSON number is forbidden: {value[:64]}")
    return result


def _read_regular_file(path: Path, maximum_bytes: int, label: str) -> bytes:
    metadata = path.stat()
    if not stat.S_ISREG(metadata.st_mode):
        raise ValueError(f"{label} is not a regular file")
    if metadata.st_size > maximum_bytes:
        raise ValueError(f"{label} exceeds {maximum_bytes} bytes")
    with path.open("rb") as stream:
        data = stream.read(maximum_bytes + 1)
    if len(data) > maximum_bytes:
        raise ValueError(f"{label} exceeds {maximum_bytes} bytes")
    return data


class ReportLoadError(ValueError):
    def __init__(self, message: str, raw_sha256: str | None = None):
        super().__init__(message)
        self.raw_sha256 = raw_sha256


def load_report_with_digest(path: Path) -> tuple[dict[str, Any], str]:
    """Load bounded JSON, rejecting duplicate keys and every non-finite float."""
    data = _read_regular_file(path, MAX_REPORT_BYTES, "lifecycle report")
    digest = hashlib.sha256(data).hexdigest()
    try:
        value = json.loads(data.decode("utf-8"), object_pairs_hook=_strict_object,
                           parse_constant=_reject_json_constant, parse_float=_finite_json_float)
    except (UnicodeDecodeError, ValueError, OverflowError, RecursionError) as error:
        raise ReportLoadError(f"invalid lifecycle JSON: {error}", digest) from error
    if not isinstance(value, dict):
        raise ReportLoadError("lifecycle report root must be an object", digest)
    return value, digest


def load_report(path: Path) -> dict[str, Any]:
    """Read a bounded lifecycle report. The digest variant is used by the CLI."""
    return load_report_with_digest(path)[0]


def _is_int(value: Any) -> bool:
    return type(value) is int and 0 <= value <= MAX_INT


def _is_text(value: Any, *, maximum: int = 512, allow_empty: bool = False) -> bool:
    return (isinstance(value, str) and len(value) <= maximum
            and (allow_empty or bool(value)) and "\x00" not in value)


def _check_keys(value: Any, expected: set[str], where: str, errors: list[str]) -> bool:
    if not isinstance(value, dict):
        errors.append(f"{where} must be an object")
        return False
    missing = expected - value.keys()
    extra = value.keys() - expected
    if missing:
        errors.append(f"{where} missing keys: {', '.join(sorted(missing))}")
    if extra:
        errors.append(f"{where} has unexpected keys: {', '.join(sorted(extra))}")
    return not missing and not extra


def _validate_config(config: Any, where: str, errors: list[str]) -> bool:
    if not _check_keys(config, CONFIG_KEYS, where, errors):
        return False
    valid = True
    if config["scenario"] not in ("flight", "workshop", "both"):
        errors.append(f"{where}.scenario is invalid")
        valid = False
    bounds = {
        "cycles": (2, 30),
        "warmup_cycles": (1, 5),
        "settle_frames": (3, 300),
    }
    for key, (low, high) in bounds.items():
        value = config[key]
        if type(value) is not int or not low <= value <= high:
            errors.append(f"{where}.{key} must be an integer from {low} through {high}")
            valid = False
    dwell = config["dwell_seconds"]
    if (type(dwell) not in (int, float) or not 0 <= dwell <= 10
            or not math.isfinite(dwell)):
        errors.append(f"{where}.dwell_seconds must be finite and between 0 and 10")
        valid = False
    return valid


def _validate_identity_list(value: Any, where: str, errors: list[str]) -> bool:
    if not isinstance(value, list):
        errors.append(f"{where} must be an array")
        return False
    if len(value) > MAX_DETAILS:
        errors.append(f"{where} exceeds the {MAX_DETAILS}-item detail limit")
        return False
    valid = True
    for index, item in enumerate(value):
        item_where = f"{where}[{index}]"
        if not _check_keys(item, IDENTITY_KEYS, item_where, errors):
            valid = False
            continue
        for key in IDENTITY_KEYS:
            if not _is_text(item[key], maximum=1024, allow_empty=(key == "script")):
                errors.append(f"{item_where}.{key} must be bounded text")
                valid = False
    return valid


def _validate_report(
    report: Any, expected_capture_id: Any, expected_config: Any,
) -> tuple[list[str], list[dict[str, Any]]]:
    errors: list[str] = []
    samples: list[dict[str, Any]] = []
    if not isinstance(report, dict):
        errors.append("report must be an object")
        return errors, samples
    missing = TOP_KEYS - report.keys()
    extra = report.keys() - (TOP_KEYS | TOP_OPTIONAL_KEYS)
    if missing:
        errors.append(f"report missing keys: {', '.join(sorted(missing))}")
    if extra:
        errors.append(f"report has unexpected keys: {', '.join(sorted(extra))}")
    if missing or extra:
        return errors, samples

    if report["format"] != FORMAT:
        errors.append(f"report.format must be {FORMAT!r}")
    capture_id = report["capture_id"]
    if not _is_text(capture_id, maximum=128):
        errors.append("report.capture_id must be bounded nonempty text")
    if not _is_text(expected_capture_id, maximum=128) or capture_id != expected_capture_id:
        errors.append("report.capture_id does not match the runner capture id")

    if type(report["complete"]) is not bool:
        errors.append("report.complete must be a boolean")
        complete = False
    else:
        complete = report["complete"]
    if not _is_text(report["failure"], maximum=4096, allow_empty=True):
        errors.append("report.failure must be bounded text")
    elif complete and report["failure"]:
        errors.append("complete report cannot contain a failure reason")

    config_valid = _validate_config(report["config"], "report.config", errors)
    expected_valid = _validate_config(expected_config, "expected_config", errors)
    if config_valid and expected_valid and report["config"] != expected_config:
        errors.append("report.config does not match the requested configuration")

    if type(report["debug_build"]) is not bool:
        errors.append("report.debug_build must be a boolean")
    if "godot" in report and not _is_text(report["godot"], maximum=128):
        errors.append("report.godot must be bounded nonempty text")
    if "scope" in report and not _is_text(report["scope"], maximum=1024):
        errors.append("report.scope must be bounded nonempty text")

    cleanup = report["cleanup"]
    if _check_keys(cleanup, {"retired_objects_checked", "retired_objects_alive", "complete"},
                   "report.cleanup", errors):
        if not _is_int(cleanup["retired_objects_checked"]):
            errors.append("report.cleanup.retired_objects_checked must be a nonnegative integer")
        _validate_identity_list(cleanup["retired_objects_alive"],
                                "report.cleanup.retired_objects_alive", errors)
        if type(cleanup["complete"]) is not bool:
            errors.append("report.cleanup.complete must be a boolean")

    if not _is_int(report["total_retired_alive"]):
        errors.append("report.total_retired_alive must be a nonnegative integer")

    raw_samples = report["samples"]
    if not isinstance(raw_samples, list):
        errors.append("report.samples must be an array")
        return errors, samples
    expected_cycles = report["config"].get("cycles") if isinstance(report["config"], dict) else None
    if type(expected_cycles) is int and 2 <= expected_cycles <= 30:
        maximum = expected_cycles + 1
        if len(raw_samples) > maximum:
            errors.append(f"report.samples exceeds the {maximum}-sample bound")
        if complete and len(raw_samples) != maximum:
            errors.append(f"complete report.samples must contain exactly {maximum} samples")
        if not complete and len(raw_samples) > maximum:
            errors.append("incomplete report.samples exceeds the requested cycle prefix")
    elif len(raw_samples) > 31:
        errors.append("report.samples exceeds the 31-sample bound")

    previous_usec: int | None = None
    for index, sample in enumerate(raw_samples[:31]):
        where = f"report.samples[{index}]"
        if not _check_keys(sample, SAMPLE_KEYS, where, errors):
            continue
        valid = True
        phase = "home_baseline" if index == 0 else "home_settled"
        if sample["phase"] != phase:
            errors.append(f"{where}.phase must be {phase!r}")
            valid = False
        if type(sample["cycle"]) is not int or sample["cycle"] != index:
            errors.append(f"{where}.cycle must equal {index}")
            valid = False
        for key in ("monotonic_usec", "node_count", "orphan_node_count", "object_count",
                    "resource_count", "static_memory_bytes", "retired_objects_checked",
                    "sample_overhead_usec"):
            if not _is_int(sample[key]):
                errors.append(f"{where}.{key} must be a nonnegative bounded integer")
                valid = False
        # OBJECT_NODE_COUNT covers the scene tree; orphans are a separate pool
        # and can legitimately outnumber the nodes still attached to the tree.
        if _is_int(sample["monotonic_usec"]):
            if previous_usec is not None and sample["monotonic_usec"] <= previous_usec:
                errors.append(f"{where}.monotonic_usec must increase strictly")
                valid = False
            previous_usec = sample["monotonic_usec"]
        _validate_identity_list(sample["retired_objects_alive"],
                                f"{where}.retired_objects_alive", errors)
        _validate_identity_list(sample["orphan_details"], f"{where}.orphan_details", errors)
        if type(sample["orphan_details_truncated"]) is not bool:
            errors.append(f"{where}.orphan_details_truncated must be a boolean")
            valid = False
        if valid:
            samples.append(sample)

    if complete and len(samples) != (expected_cycles + 1 if type(expected_cycles) is int else -1):
        # The earlier field checks may have dropped a malformed sample.
        if "complete report.samples" not in " ".join(errors):
            errors.append("complete report contains an invalid sample")
    if isinstance(cleanup, dict) and type(cleanup.get("complete")) is bool:
        if complete and not cleanup["complete"]:
            errors.append("complete report requires complete cleanup")
    if _is_int(report["total_retired_alive"]):
        detail_count = 0
        if isinstance(cleanup, dict) and isinstance(cleanup.get("retired_objects_alive"), list):
            detail_count += len(cleanup["retired_objects_alive"])
        for sample in raw_samples[:31]:
            if isinstance(sample, dict) and isinstance(sample.get("retired_objects_alive"), list):
                detail_count += len(sample["retired_objects_alive"])
        if report["total_retired_alive"] < detail_count:
            errors.append("report.total_retired_alive is smaller than retained alive-object details")
    return errors, samples


def analyze_report(
    report: Any,
    expected_capture_id: Any,
    expected_config: Any,
    *,
    max_node_growth: int = 0,
    max_orphan_growth: int = 0,
    max_static_growth_mib: float | None = None,
) -> dict[str, Any]:
    """Validate a probe report and apply the explicit lifecycle gates.

    Counts and static-memory measurements are diagnostic signals. Passing these
    gates does not establish that the process is leak-free.
    """
    limit_errors: list[str] = []
    if type(max_node_growth) is not int or not 0 <= max_node_growth <= 10_000:
        limit_errors.append("max_node_growth must be an integer from 0 through 10000")
    if type(max_orphan_growth) is not int or not 0 <= max_orphan_growth <= 10_000:
        limit_errors.append("max_orphan_growth must be an integer from 0 through 10000")
    if max_static_growth_mib is not None and (
            type(max_static_growth_mib) not in (int, float)
            or not 0 <= max_static_growth_mib <= 4096
            or not math.isfinite(max_static_growth_mib)):
        limit_errors.append("max_static_growth_mib must be finite and from 0 through 4096")
    schema_errors, samples = _validate_report(report, expected_capture_id, expected_config)
    findings = [f"invalid_report: {error}" for error in limit_errors + schema_errors]
    valid = not findings
    complete = bool(valid and report["complete"] and report["cleanup"]["complete"])
    metrics: dict[str, Any] = {}

    if valid and samples:
        baseline = samples[0]
        settled = samples[1:]
        node_deltas = [sample["node_count"] - baseline["node_count"] for sample in settled]
        orphan_deltas = [sample["orphan_node_count"] - baseline["orphan_node_count"] for sample in settled]
        object_deltas = [sample["object_count"] - baseline["object_count"] for sample in settled]
        resource_deltas = [sample["resource_count"] - baseline["resource_count"] for sample in settled]
        static_deltas = [sample["static_memory_bytes"] - baseline["static_memory_bytes"] for sample in settled]
        max_node_delta = max([0, *node_deltas])
        max_orphan_delta = max([0, *orphan_deltas])
        max_static_delta = max([0, *static_deltas])
        metrics = {
            "baseline_cycle": baseline["cycle"],
            "settled_sample_count": len(settled),
            "max_node_growth": max_node_delta,
            "max_orphan_growth": max_orphan_delta,
            "max_object_growth": max([0, *object_deltas]),
            "max_resource_growth": max([0, *resource_deltas]),
            "max_static_memory_growth_bytes": max_static_delta,
            "max_static_memory_growth_mib": max_static_delta / MIB,
            "static_memory_gate_enabled": max_static_growth_mib is not None,
        }
        if report["total_retired_alive"] > 0:
            findings.append("retired_objects_alive: probe reported one or more retained retired objects")
        if report["cleanup"]["retired_objects_alive"]:
            if not any(item.startswith("retired_objects_alive:") for item in findings):
                findings.append("retired_objects_alive: cleanup retained retired object details")
        if max_node_delta > max_node_growth:
            findings.append(
                f"node_growth: settled node count rose by {max_node_delta} from baseline "
                f"(limit {max_node_growth})")
        if max_orphan_delta > max_orphan_growth:
            findings.append(
                f"orphan_growth: settled orphan count rose by {max_orphan_delta} from baseline "
                f"(limit {max_orphan_growth})")
        if max_static_growth_mib is not None and max_static_delta / MIB > max_static_growth_mib:
            findings.append(
                f"static_memory_growth: settled static memory rose by {max_static_delta / MIB:.6g} MiB "
                f"from baseline (limit {max_static_growth_mib:.6g} MiB)")
        if not report["complete"]:
            failure = report["failure"] or "report is incomplete without a failure reason"
            findings.append(f"probe_incomplete: {failure}")
        if not report["cleanup"]["complete"]:
            findings.append("cleanup_incomplete: probe did not complete final cleanup checks")
        if not report["debug_build"]:
            findings.append("debug_build_required: orphan and static-memory checks require a debug build")
    elif valid:
        findings.append("probe_incomplete: no lifecycle samples were captured")
        if not report["debug_build"]:
            findings.append("debug_build_required: orphan and static-memory checks require a debug build")

    return {
        "complete": complete,
        "ok": complete and not findings,
        "findings": findings,
        "metrics": metrics,
        "interpretation": "Object, resource, and static-memory trends are diagnostic signals; passing is not proof of no leak.",
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path, help="path to the direct Godot executable")
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT,
                        help=f"parent directory for unique run folders (default: {DEFAULT_OUT})")
    parser.add_argument("--scenario", choices=("flight", "workshop", "both"), default="both")
    parser.add_argument("--cycles", type=int, default=3)
    parser.add_argument("--warmup-cycles", type=int, default=1)
    parser.add_argument("--settle-frames", type=int, default=8)
    parser.add_argument("--dwell-seconds", type=float, default=0.25)
    parser.add_argument("--timeout", type=float, default=300, help="engine deadline in seconds (0–3600]")
    parser.add_argument("--max-node-growth", type=int, default=0)
    parser.add_argument("--max-orphan-growth", type=int, default=0)
    parser.add_argument("--max-static-growth-mib", type=float, default=None,
                        help="optional settled static-memory growth limit in MiB")
    parser.add_argument("--resources", action="store_true",
                        help="also capture bounded process resources through run_checked and psutil")
    return parser


def _validate_args(args: argparse.Namespace) -> tuple[Path, dict[str, Any]]:
    ranges = (
        ("cycles", args.cycles, 2, 30),
        ("warmup-cycles", args.warmup_cycles, 1, 5),
        ("settle-frames", args.settle_frames, 3, 300),
        ("max-node-growth", args.max_node_growth, 0, 10_000),
        ("max-orphan-growth", args.max_orphan_growth, 0, 10_000),
    )
    for name, value, low, high in ranges:
        if type(value) is not int or not low <= value <= high:
            raise ValueError(f"--{name} must be an integer from {low} through {high}")
    if (type(args.dwell_seconds) not in (int, float) or not 0 <= args.dwell_seconds <= 10
            or not math.isfinite(args.dwell_seconds)):
        raise ValueError("--dwell-seconds must be finite and between 0 and 10")
    if type(args.timeout) not in (int, float) or not math.isfinite(args.timeout) \
            or not 0 < args.timeout <= 3600:
        raise ValueError("--timeout must be finite, greater than 0 and at most 3600 seconds")
    if args.max_static_growth_mib is not None and (
            type(args.max_static_growth_mib) not in (int, float)
            or not 0 <= args.max_static_growth_mib <= 4096
            or not math.isfinite(args.max_static_growth_mib)):
        raise ValueError("--max-static-growth-mib must be finite and from 0 through 4096")

    try:
        godot = args.godot.expanduser().resolve(strict=True)
    except OSError as error:
        raise ValueError(f"--godot does not exist: {args.godot}") from error
    if not godot.is_file():
        raise ValueError(f"--godot must name an executable file: {godot}")
    if godot.name.lower().endswith("_console.exe"):
        raise ValueError("--godot must be the direct executable, not the _console.exe launcher")
    if not os.access(godot, os.X_OK) and os.name != "nt":
        raise ValueError(f"--godot is not executable: {godot}")
    if not PROBE_SCRIPT.is_file():
        raise ValueError(f"lifecycle probe script is missing: {PROBE_SCRIPT}")
    config = {
        "scenario": args.scenario,
        "cycles": args.cycles,
        "warmup_cycles": args.warmup_cycles,
        "settle_frames": args.settle_frames,
        "dwell_seconds": args.dwell_seconds,
    }
    return godot, config


def _write_summary(path: Path, summary: dict[str, Any]) -> None:
    payload = (json.dumps(summary, indent=2, ensure_ascii=True, allow_nan=False) + "\n").encode("utf-8")
    if len(payload) > MAX_REPORT_BYTES:
        raise ValueError("lifecycle summary exceeds 4 MiB")
    created = False
    try:
        with path.open("xb") as stream:
            created = True
            stream.write(payload)
            stream.flush()
    except BaseException:
        if created:
            try:
                path.unlink()
            except OSError:
                pass
        raise


def _sha256_file(path: Path, *, maximum_bytes: int, label: str) -> str:
    data = _read_regular_file(path, maximum_bytes, label)
    return hashlib.sha256(data).hexdigest()


def scan_engine_log(path: Any) -> dict[str, Any]:
    """Count every anchored warning and retain at most ten warning details.

    Shutdown ObjectDB/resource warnings receive a retained detail slot even when
    ordinary warnings appeared earlier in the bounded log.
    """
    try:
        if not isinstance(path, (str, os.PathLike)) or not path:
            raise ValueError("runner did not provide an engine log path")
        data = _read_regular_file(Path(path), MAX_ENGINE_LOG_BYTES, "engine log")
    except (OSError, ValueError) as error:
        return {
            "complete": False,
            "error": f"{type(error).__name__}: {error}"[:2048],
            "engine_warning_count": None,
            "shutdown_leak_warning_count": None,
            "warning_details": [],
            "warning_details_truncated": None,
        }

    warning_count = 0
    shutdown_count = 0
    details: list[dict[str, Any]] = []
    for line_number, raw_line in enumerate(io.StringIO(data.decode("utf-8", errors="replace")), start=1):
        clean = ANSI.sub("", raw_line).rstrip("\r\n")
        match = WARNING_LINE.match(clean)
        if not match:
            continue
        warning_count += 1
        message = match.group(1).strip()
        shutdown_warning = bool(SHUTDOWN_LEAK_WARNING.search(message))
        if shutdown_warning:
            shutdown_count += 1
        detail = {
            "line": line_number,
            "message": message[:1000],
            "shutdown_leak_warning": shutdown_warning,
        }
        if len(details) < MAX_WARNING_DETAILS:
            details.append(detail)
        elif shutdown_warning:
            replacement = next((
                index for index in range(len(details) - 1, -1, -1)
                if not details[index]["shutdown_leak_warning"]
            ), None)
            if replacement is not None:
                details[replacement] = detail

    return {
        "complete": True,
        "error": "",
        "engine_warning_count": warning_count,
        "shutdown_leak_warning_count": shutdown_count,
        "warning_details": details,
        "warning_details_truncated": warning_count > len(details),
    }


def run_lifecycle(args: argparse.Namespace, runner: Callable[..., dict[str, Any]] = run_checked) -> tuple[int, dict[str, Any] | None]:
    """Execute one fresh lifecycle run and retain its raw probe and summary files."""
    try:
        godot, config = _validate_args(args)
        source_hashes = {
            "lifecycle_check.py": _sha256_file(
                Path(__file__).resolve(), maximum_bytes=MAX_SOURCE_BYTES, label="lifecycle checker source"),
            "lifecycle_probe.gd": _sha256_file(
                PROBE_SCRIPT, maximum_bytes=MAX_SOURCE_BYTES, label="lifecycle probe source"),
        }
        out_dir = args.out_dir.expanduser().resolve()
        out_dir.mkdir(parents=True, exist_ok=True)
        run_dir = Path(tempfile.mkdtemp(prefix="run-", dir=out_dir))
        probe_dir = run_dir / "probe"
        # Fail before starting Godot if the summary cannot be written here.
        preflight = run_dir / ".write-check"
        with preflight.open("xb"):
            pass
        preflight.unlink()
    except (OSError, ValueError) as error:
        print(f"Lifecycle check configuration/output error: {error}", file=sys.stderr)
        return 2, None

    command = [
        str(godot), "--headless", "--path", str(APP_DIR), "--audio-driver", "Dummy",
        "--max-fps", "60", "--script", str(PROBE_SCRIPT), "--",
        f"--out-dir={probe_dir.resolve()}", f"--scenario={config['scenario']}",
        f"--cycles={config['cycles']}", f"--warmup-cycles={config['warmup_cycles']}",
        f"--settle-frames={config['settle_frames']}",
        f"--dwell-seconds={config['dwell_seconds']!r}",
    ]
    try:
        engine = runner(command, out_dir=run_dir / "checked", timeout=args.timeout,
                        label="godot-lifecycle", resources=args.resources)
    except (OSError, ValueError) as error:
        print(f"Lifecycle check configuration/output error: {error}", file=sys.stderr)
        return 2, None

    raw_path = probe_dir / "lifecycle.json"
    report: dict[str, Any] | None = None
    analysis: dict[str, Any]
    raw_report_sha256: str | None = None
    try:
        report, raw_report_sha256 = load_report_with_digest(raw_path)
        analysis = analyze_report(
            report, engine.get("capture_id"), config,
            max_node_growth=args.max_node_growth,
            max_orphan_growth=args.max_orphan_growth,
            max_static_growth_mib=args.max_static_growth_mib,
        )
    except ReportLoadError as error:
        raw_report_sha256 = error.raw_sha256
        analysis = {
            "complete": False,
            "ok": False,
            "findings": [f"invalid_report: {error}"],
            "metrics": {},
            "interpretation": "Object, resource, and static-memory trends are diagnostic signals; passing is not proof of no leak.",
        }
    except (OSError, ValueError) as error:
        analysis = {
            "complete": False,
            "ok": False,
            "findings": [f"invalid_report: {error}"],
            "metrics": {},
            "interpretation": "Object, resource, and static-memory trends are diagnostic signals; passing is not proof of no leak.",
        }

    log_scan = scan_engine_log(engine.get("log"))
    findings = list(analysis["findings"])
    if not engine.get("ok", False):
        reason = engine.get("reason", "unknown")
        findings.append(f"engine_check_failed: run_checked returned {reason}")
    if not log_scan["complete"]:
        findings.append(f"engine_log_scan_incomplete: {log_scan['error']}")
    elif log_scan["shutdown_leak_warning_count"]:
        findings.append(
            "shutdown_leak_warning: engine log contains "
            f"{log_scan['shutdown_leak_warning_count']} ObjectDB/resource shutdown leak warning(s)")
    complete = bool(engine.get("complete", False) and analysis["complete"] and log_scan["complete"])
    summary = {
        "format": SUMMARY_FORMAT,
        "complete": complete,
        "ok": bool(complete and analysis["ok"] and engine.get("ok", False) and not findings),
        "findings": findings,
        "capture_id": engine.get("capture_id"),
        "config": config,
        "counts": {
            "engine_warning_count": log_scan["engine_warning_count"],
            "shutdown_leak_warning_count": log_scan["shutdown_leak_warning_count"],
        },
        "engine_warning_count": log_scan["engine_warning_count"],
        "engine_warning_details": log_scan["warning_details"],
        "engine_warning_details_truncated": log_scan["warning_details_truncated"],
        "shutdown_leak_warning_count": log_scan["shutdown_leak_warning_count"],
        "thresholds": {
            "max_node_growth": args.max_node_growth,
            "max_orphan_growth": args.max_orphan_growth,
            "max_static_growth_mib": args.max_static_growth_mib,
        },
        "metrics": analysis["metrics"],
        "interpretation": analysis["interpretation"],
        "engine": {
            "ok": bool(engine.get("ok", False)),
            "complete": bool(engine.get("complete", False)),
            "reason": engine.get("reason"),
            "process_exit": engine.get("process_exit"),
            "report": _relative_path(run_dir, engine.get("report")),
            "log": _relative_path(run_dir, engine.get("log")),
            "log_scan_complete": log_scan["complete"],
            "log_scan_error": log_scan["error"] or None,
        },
        "raw_samples": _relative_path(run_dir, raw_path) if raw_path.is_file() else None,
        "provenance": {
            "source_sha256": source_hashes,
            "raw_report_sha256": raw_report_sha256,
        },
    }
    try:
        _write_summary(run_dir / "summary.json", summary)
    except (OSError, ValueError) as error:
        print(f"Lifecycle check configuration/output error: {error}", file=sys.stderr)
        return 2, summary

    status = "passed" if summary["ok"] else "failed"
    print(f"Lifecycle check {status}; summary: {run_dir / 'summary.json'}")
    for finding in findings:
        print(f"  {finding}", file=sys.stderr)
    return (0 if summary["ok"] else 1), summary


def _relative_path(root: Path, value: Any) -> str | None:
    if not isinstance(value, (str, os.PathLike)) or not value:
        return None
    try:
        path = Path(value).resolve()
        return path.relative_to(root.resolve()).as_posix()
    except (OSError, RuntimeError, ValueError):
        return str(value)[:2048]


def main(argv: list[str] | None = None, *, runner: Callable[..., dict[str, Any]] = run_checked) -> int:
    parser = _parser()
    args = parser.parse_args(argv)
    code, _ = run_lifecycle(args, runner=runner)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
