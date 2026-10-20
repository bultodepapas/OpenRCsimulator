#!/usr/bin/env python3
"""Package a bounded, read-only snapshot of one Godot diagnostic incident."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import zipfile


REPO_ROOT = Path(__file__).resolve().parents[2]
GODOT_TOOLS = REPO_ROOT / "tools" / "godot"
for _import_path in (str(REPO_ROOT), str(GODOT_TOOLS)):
    if _import_path not in sys.path:
        sys.path.insert(0, _import_path)

from summarize import read_run
from research.performance.native_summary import validate_native_report


FORMAT = "openrc-incident-bundle v1"
DEFAULT_MAX_INPUT_BYTES = 64 * 1024 * 1024
MAX_INPUT_BYTES = 256 * 1024 * 1024
DEFAULT_MAX_TOTAL_BYTES = 256 * 1024 * 1024
MAX_TOTAL_BYTES = 1024 * 1024 * 1024
MAX_NOTE_CHARS = 4096
MAX_REPORT_BYTES = 256 * 1024
MAX_RESOURCE_JSON_BYTES = 16 * 1024 * 1024
MAX_FRAME_VALIDATION_ERRORS = 100
MAX_ISSUES = 100
MAX_ISSUE_TEXT = 1000
READ_CHUNK_BYTES = 64 * 1024
REPARSE_POINT_FLAG = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x0400)


class BundleConfigurationError(ValueError):
    """Invalid run directory or command-line configuration."""


class SnapshotFailure(Exception):
    """An input could not be captured as a stable bounded regular file."""

    def __init__(self, code: str, message: str, *, bytes_read: int = 0,
                 source_size_bytes: int | None = None):
        super().__init__(message)
        self.code = code
        self.bytes_read = bytes_read
        self.source_size_bytes = source_size_bytes


class OutputFailure(OSError):
    """The new ZIP could not be published."""


def _reject_json_constant(value: str) -> None:
    raise ValueError(f"non-finite JSON value {value} is forbidden")


def _reject_duplicate_pairs(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key {key!r} is forbidden")
        result[key] = value
    return result


def _parse_json_object(data: bytes) -> tuple[dict | None, str | None]:
    try:
        value = json.loads(data, parse_constant=_reject_json_constant,
                           object_pairs_hook=_reject_duplicate_pairs)
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError, TypeError,
            RecursionError, OverflowError) as error:
        return None, f"{type(error).__name__}: {error}"[:MAX_ISSUE_TEXT]
    if not isinstance(value, dict):
        return None, "JSON root must be an object"
    return value, None


def _is_reparse_point(info: os.stat_result) -> bool:
    return bool(getattr(info, "st_file_attributes", 0) & REPARSE_POINT_FLAG)


def _signature(info: os.stat_result) -> tuple:
    return (info.st_dev, info.st_ino, info.st_mode, info.st_size,
            getattr(info, "st_mtime_ns", int(info.st_mtime * 1_000_000_000)),
            getattr(info, "st_ctime_ns", int(info.st_ctime * 1_000_000_000)),
            getattr(info, "st_file_attributes", 0))


def _file_identity(info: os.stat_result) -> tuple[int, int]:
    return info.st_dev, info.st_ino


def _reject_link_components(path: Path) -> Path:
    """Return an absolute path, refusing symlinks/junctions in any component."""
    absolute = Path(os.path.abspath(os.fspath(path)))
    current = Path(absolute.anchor)
    for component in absolute.parts[1:]:
        current = current / component
        try:
            info = os.lstat(current)
        except FileNotFoundError:
            break
        except OSError as error:
            raise SnapshotFailure("source_unreadable", f"cannot inspect source path: {error}") from error
        if stat.S_ISLNK(info.st_mode) or _is_reparse_point(info):
            raise SnapshotFailure("linked_source", "symlink/junction/reparse paths are not followed")
    return absolute


def _validate_run_directory(path: Path) -> Path:
    try:
        absolute = _reject_link_components(path)
        info = os.lstat(absolute)
    except SnapshotFailure as error:
        raise BundleConfigurationError(f"run directory is unavailable: {error}") from error
    except OSError as error:
        raise BundleConfigurationError(f"run directory is unavailable: {error}") from error
    if stat.S_ISLNK(info.st_mode) or _is_reparse_point(info):
        raise BundleConfigurationError("run directory cannot be a symlink or junction")
    if not stat.S_ISDIR(info.st_mode):
        raise BundleConfigurationError("RUN_DIR must be an existing directory")
    return absolute


def validate_limits(max_input_bytes: int, max_total_bytes: int, note: str) -> None:
    if type(max_input_bytes) is not int or not 1 <= max_input_bytes <= MAX_INPUT_BYTES:
        raise BundleConfigurationError(
            f"--max-input-bytes must be an integer from 1 to {MAX_INPUT_BYTES}")
    if type(max_total_bytes) is not int or not 1 <= max_total_bytes <= MAX_TOTAL_BYTES:
        raise BundleConfigurationError(
            f"--max-total-bytes must be an integer from 1 to {MAX_TOTAL_BYTES}")
    if max_input_bytes > max_total_bytes:
        raise BundleConfigurationError("--max-input-bytes cannot exceed --max-total-bytes")
    if not isinstance(note, str) or len(note) > MAX_NOTE_CHARS:
        raise BundleConfigurationError(f"--note must be at most {MAX_NOTE_CHARS} characters")


def _snapshot_file(path: Path, *, max_file_bytes: int, remaining_total_bytes: int) -> tuple[bytes, int]:
    """Read one regular-file snapshot and verify descriptor/path metadata stayed stable."""
    absolute = _reject_link_components(path)
    try:
        before_path = os.lstat(absolute)
    except FileNotFoundError as error:
        raise SnapshotFailure("missing", "source file is missing") from error
    except OSError as error:
        raise SnapshotFailure("source_unreadable", f"cannot stat source file: {error}") from error
    if stat.S_ISLNK(before_path.st_mode) or _is_reparse_point(before_path):
        raise SnapshotFailure("linked_source", "symlink/junction/reparse files are not followed")
    if not stat.S_ISREG(before_path.st_mode):
        raise SnapshotFailure("non_regular_source", "source is not a regular file")
    source_size = before_path.st_size
    permitted = min(max_file_bytes, remaining_total_bytes)
    if source_size < 0:
        raise SnapshotFailure("invalid_size", "source has a negative size", source_size_bytes=source_size)
    if source_size > max_file_bytes:
        raise SnapshotFailure("file_size_limit", "source exceeds --max-input-bytes",
                              source_size_bytes=source_size)
    if source_size > remaining_total_bytes:
        raise SnapshotFailure("total_size_limit", "source exceeds the remaining --max-total-bytes budget",
                              source_size_bytes=source_size)

    descriptor = None
    read_bytes = 0
    data = bytearray()
    try:
        flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0)
        descriptor = os.open(absolute, flags)
        before_fd = os.fstat(descriptor)
        if (not stat.S_ISREG(before_fd.st_mode) or _is_reparse_point(before_fd)
                or _signature(before_fd) != _signature(before_path)):
            raise SnapshotFailure("source_changed", "source changed while it was being opened",
                                  source_size_bytes=source_size)
        if before_fd.st_size > permitted:
            code = "file_size_limit" if before_fd.st_size > max_file_bytes else "total_size_limit"
            raise SnapshotFailure(code, "source exceeds the available input budget",
                                  source_size_bytes=before_fd.st_size)

        remaining = before_fd.st_size
        while remaining:
            block = os.read(descriptor, min(READ_CHUNK_BYTES, remaining))
            if not block:
                raise SnapshotFailure("source_changed", "source ended before its recorded size",
                                      bytes_read=read_bytes, source_size_bytes=source_size)
            data.extend(block)
            read_bytes += len(block)
            remaining -= len(block)

        after_fd = os.fstat(descriptor)
        after_path = os.lstat(absolute)
        if (not stat.S_ISREG(after_path.st_mode) or _is_reparse_point(after_path)
                or _signature(before_fd) != _signature(after_fd)
                or _signature(before_fd) != _signature(after_path)
                or len(data) != before_fd.st_size):
            raise SnapshotFailure("source_changed", "source metadata changed while being captured",
                                  bytes_read=read_bytes, source_size_bytes=source_size)
        return bytes(data), read_bytes
    except SnapshotFailure:
        raise
    except FileNotFoundError as error:
        raise SnapshotFailure("missing", "source disappeared while being captured",
                              bytes_read=read_bytes, source_size_bytes=source_size) from error
    except OSError as error:
        raise SnapshotFailure("source_unreadable", f"source read failed: {error}",
                              bytes_read=read_bytes, source_size_bytes=source_size) from error
    finally:
        if descriptor is not None:
            os.close(descriptor)


def _attachment(role: str, archive_path: str, source: str, *, source_name: str | None = None) -> dict:
    return {
        "role": role,
        "archive_path": archive_path,
        "source": source,
        "source_name": source_name,
        "included": False,
        "status": "not_read",
        "bytes": None,
        "sha256": None,
        "validation": None,
    }


def _add_issue(issues: list[dict], omitted: list[int], *, code: str, message: str,
               attachment: str | None = None, severity: str = "error") -> None:
    if len(issues) >= MAX_ISSUES:
        omitted[0] += 1
        return
    issues.append({"code": code[:100], "severity": severity,
                   "attachment": attachment, "message": message[:MAX_ISSUE_TEXT]})


def _capture_id(report: dict | None) -> str | None:
    if report is None:
        return None
    value = report.get("capture_id")
    return value if isinstance(value, str) and 0 < len(value) <= 256 else None


def _manifest_integer(value: object) -> int | None:
    return value if type(value) is int else None


def _manifest_text(value: object, limit: int = 256) -> str | None:
    return value[:limit] if isinstance(value, str) else None


def _validate_resource_receipt(resource_report: dict, run_report: dict,
                               aggregate_receipt: dict) -> list[str]:
    errors: list[str] = []
    if resource_report.get("format") != "openrc-resource-samples v1":
        errors.append("unsupported resource report format")
    invocation = resource_report.get("invocation")
    if not isinstance(invocation, dict):
        errors.append("resource invocation metadata is missing")
        invocation = {}
    for field in ("command", "cwd", "started_utc", "log_sha256"):
        expected = run_report.get(field)
        if field not in invocation or invocation.get(field) != expected:
            errors.append(f"resource invocation {field} does not match report.json")
    samples = resource_report.get("samples")
    if not isinstance(samples, list):
        errors.append("resource samples must be an array")
    elif len(samples) > 10000:
        errors.append("resource samples exceed the 10000-sample cap")
    sample_count = resource_report.get("sample_count")
    if type(sample_count) is not int or not 0 <= sample_count <= 10000:
        errors.append("resource sample_count must be an integer from 0 to 10000")
    elif isinstance(samples, list) and sample_count != len(samples):
        errors.append("resource sample_count does not match the samples array length")
    coverage = resource_report.get("coverage")
    if not isinstance(coverage, str) or coverage not in {"sampled", "partial", "capped", "no_samples"}:
        errors.append("resource coverage is missing or unsupported")
    measurement_status = resource_report.get("measurement_status")
    if (not isinstance(measurement_status, str)
            or measurement_status not in {"ok", "partial", "unavailable"}):
        errors.append("resource measurement_status is missing or unsupported")
    if coverage == "sampled" and sample_count == 0:
        errors.append("sampled resource coverage must contain at least one sample")
    for field in ("coverage", "sample_count", "measurement_status"):
        if field in aggregate_receipt and resource_report.get(field) != aggregate_receipt.get(field):
            errors.append(f"resource {field} does not match report.json receipt")

    run_capture_id = _capture_id(run_report)
    resource_capture_id = resource_report.get("capture_id")
    invocation_capture_id = invocation.get("capture_id")
    for label, value in (("resource report", resource_capture_id),
                         ("resource invocation", invocation_capture_id)):
        if value is not None and (not isinstance(value, str) or not value or len(value) > 256):
            errors.append(f"{label} capture_id is invalid")
    if resource_capture_id is not None and invocation_capture_id is not None:
        if resource_capture_id != invocation_capture_id:
            errors.append("resource report and invocation capture_id disagree")
    if run_capture_id is not None:
        if resource_capture_id != run_capture_id:
            errors.append("resource report capture_id is missing or does not match report.json")
        if invocation_capture_id != run_capture_id:
            errors.append("resource invocation capture_id is missing or does not match report.json")
    return errors


def _validate_frames(frame_report: dict, run_capture_id: str | None) -> tuple[list[str], str]:
    errors, _derived = validate_native_report(frame_report)
    bounded_errors = [str(error)[:MAX_ISSUE_TEXT] for error in errors[:MAX_FRAME_VALIDATION_ERRORS]]
    if len(errors) > MAX_FRAME_VALIDATION_ERRORS:
        bounded_errors.append(f"{len(errors) - MAX_FRAME_VALIDATION_ERRORS} additional validation errors omitted")
    frame_capture_id = frame_report.get("capture_id")
    if "capture_id" in frame_report and not isinstance(frame_capture_id, str):
        bounded_errors.append("capture_id must be a string when present")
    elif isinstance(frame_capture_id, str) and len(frame_capture_id) > 256:
        bounded_errors.append("capture_id must be at most 256 characters")
    elif run_capture_id is not None:
        if not frame_capture_id:
            bounded_errors.append("frame report capture_id is missing; association cannot be verified")
        elif frame_capture_id != run_capture_id:
            bounded_errors.append("frame report capture_id does not match report.json")
    return bounded_errors, frame_capture_id if isinstance(frame_capture_id, str) else ""


def _write_bundle(path: Path, manifest: dict, attachments: list[tuple[str, bytes]]) -> None:
    """Create one exclusive ZIP and remove only our partial output on failure."""
    output = Path(path)
    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor_identity = None
    created = False
    try:
        with output.open("xb") as stream:
            created = True
            descriptor_identity = _file_identity(os.fstat(stream.fileno()))
            with zipfile.ZipFile(stream, mode="w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
                manifest_bytes = (json.dumps(manifest, ensure_ascii=True, indent=2,
                                             sort_keys=True, allow_nan=False) + "\n").encode("utf-8")
                archive.writestr("manifest.json", manifest_bytes)
                for archive_path, content in attachments:
                    archive.writestr(archive_path, content)
            stream.flush()
    except FileExistsError:
        raise
    except Exception as error:
        if created and descriptor_identity is not None:
            try:
                current = os.lstat(output)
                if _file_identity(current) == descriptor_identity:
                    output.unlink()
            except OSError:
                pass
        raise OutputFailure(f"could not write incident ZIP: {type(error).__name__}: {error}") from error


def create_bundle(run_dir: Path, output_path: Path, *, frames_path: Path | None = None,
                  flight_log_path: Path | None = None, note: str = "",
                  max_input_bytes: int = DEFAULT_MAX_INPUT_BYTES,
                  max_total_bytes: int = DEFAULT_MAX_TOTAL_BYTES) -> dict:
    validate_limits(max_input_bytes, max_total_bytes, note)
    root = _validate_run_directory(Path(run_dir))
    if Path(output_path).suffix.lower() != ".zip":
        raise BundleConfigurationError("--out must have a .zip extension")
    if flight_log_path is not None and Path(flight_log_path).suffix.lower() != ".orfl":
        raise BundleConfigurationError("--flight-log must name a .orfl file")

    issues: list[dict] = []
    omitted_issues = [0]
    partial = [False]
    captured: dict[str, bytes] = {}
    attachments: list[dict] = []
    zip_attachments: list[tuple[str, bytes]] = []
    consumed_bytes = 0

    def issue(code: str, message: str, attachment_name: str | None = None, *, incomplete: bool = True) -> None:
        _add_issue(issues, omitted_issues, code=code, message=message,
                   attachment=attachment_name)
        if incomplete:
            partial[0] = True

    def snapshot(entry: dict, source_path: Path) -> bytes | None:
        nonlocal consumed_bytes
        try:
            data, read_bytes = _snapshot_file(
                source_path,
                max_file_bytes=max_input_bytes,
                remaining_total_bytes=max_total_bytes - consumed_bytes,
            )
        except SnapshotFailure as error:
            consumed_bytes += error.bytes_read
            entry["status"] = error.code
            entry["source_size_bytes"] = error.source_size_bytes
            issue(error.code, str(error), entry["archive_path"])
            return None
        consumed_bytes += read_bytes
        entry.update(included=True, status="attached", bytes=len(data),
                     sha256=hashlib.sha256(data).hexdigest())
        captured[entry["archive_path"]] = data
        zip_attachments.append((entry["archive_path"], data))
        return data

    report_entry = _attachment("run_report", "report.json", "run directory/report.json")
    attachments.append(report_entry)
    report_bytes = snapshot(report_entry, root / "report.json")
    log_entry = _attachment("engine_log", "engine.log", "run directory/engine.log")
    attachments.append(log_entry)
    log_bytes = snapshot(log_entry, root / "engine.log")

    run_report = None
    report_parse_error = None
    if report_bytes is not None:
        if len(report_bytes) > MAX_REPORT_BYTES:
            report_parse_error = f"report exceeds the {MAX_REPORT_BYTES}-byte receipt parsing limit"
        else:
            run_report, report_parse_error = _parse_json_object(report_bytes)
        if report_parse_error:
            report_entry["validation"] = "invalid_json"
            issue("report_json_invalid", report_parse_error, "report.json")

    run_evidence = {"evidence_valid": False, "ok": False, "reason": "invalid_report",
                    "detail": "report.json or engine.log is missing or invalid"}
    temporary_error = None
    try:
        with tempfile.TemporaryDirectory(prefix="openrc-incident-run-") as temporary:
            snapshot_dir = Path(temporary)
            if report_bytes is not None:
                (snapshot_dir / "report.json").write_bytes(report_bytes)
            if log_bytes is not None:
                (snapshot_dir / "engine.log").write_bytes(log_bytes)
            checked = read_run(snapshot_dir, max_log_bytes=max_input_bytes)
            evidence_valid = (checked.get("reason") != "invalid_report"
                              and report_parse_error is None and run_report is not None)
            run_evidence = {
                "evidence_valid": evidence_valid,
                "ok": bool(checked.get("ok")) if evidence_valid else False,
                "reason": checked.get("reason", "invalid_report"),
                "detail": str(checked.get("detail", ""))[:2000],
            }
    except (OSError, ValueError, TypeError, RuntimeError, RecursionError, OverflowError) as error:
        temporary_error = f"{type(error).__name__}: {error}"[:MAX_ISSUE_TEXT]
        run_evidence["detail"] = temporary_error

    if not run_evidence["evidence_valid"]:
        issue("run_evidence_invalid", run_evidence["detail"] or "run report and log did not validate",
              "report.json/engine.log")
    if run_report is not None:
        process_exit = run_report.get("process_exit")
        if process_exit is not None and type(process_exit) is not int:
            issue("run_process_exit_invalid", "report.json process_exit must be an integer or null",
                  "report.json")
            run_evidence.update(evidence_valid=False, ok=False, reason="invalid_report")
    for entry in (report_entry, log_entry):
        entry["validation"] = "run_receipt_valid" if run_evidence["evidence_valid"] else "not_verified"

    capture_id = _capture_id(run_report)
    if run_report is not None and "capture_id" in run_report and capture_id is None:
        issue("run_capture_id_invalid", "report.json capture_id is not a bounded non-empty string", "report.json")

    resource_entry = None
    resource_report = None
    resource_capture = None
    if run_report is not None and "resources" in run_report:
        receipt = run_report.get("resources")
        resource_entry = _attachment("resource_report", "resources.json", "run directory/resources.json")
        attachments.append(resource_entry)
        if not isinstance(receipt, dict):
            resource_entry["status"] = "invalid_receipt"
            issue("resource_receipt_invalid", "report.json resources receipt must be an object", "resources.json")
        elif "published" not in receipt or type(receipt.get("published")) is not bool:
            resource_entry["status"] = "invalid_receipt"
            issue("resource_receipt_invalid", "resource receipt published field must be a boolean",
                  "resources.json")
        elif receipt.get("published") is False:
            resource_entry["status"] = "not_published"
            issue("resource_not_published", str(receipt.get("error", "resource receipt says no file was published")),
                  "resources.json")
        elif receipt.get("file") is None:
            resource_entry["status"] = "invalid_receipt"
            issue("resource_receipt_invalid", "published resource receipt has no local filename", "resources.json")
        elif receipt.get("file") != "resources.json":
            resource_entry["status"] = "unsafe_receipt_path"
            issue("resource_path_rejected", "only the literal local filename 'resources.json' is accepted",
                  "resources.json")
        else:
            resource_bytes = snapshot(resource_entry, root / "resources.json")
            if resource_bytes is not None:
                resource_receipt_valid = True
                expected_bytes = receipt.get("bytes")
                expected_hash = receipt.get("sha256")
                if type(expected_bytes) is not int or expected_bytes != len(resource_bytes):
                    resource_receipt_valid = False
                    issue("resource_size_mismatch", "resource report bytes do not match report.json receipt",
                          "resources.json")
                if (not isinstance(expected_hash, str) or len(expected_hash) != 64
                        or any(char not in "0123456789abcdef" for char in expected_hash)
                        or expected_hash != resource_entry["sha256"]):
                    resource_receipt_valid = False
                    issue("resource_hash_mismatch", "resource report hash does not match report.json receipt",
                          "resources.json")
                if len(resource_bytes) > MAX_RESOURCE_JSON_BYTES:
                    resource_receipt_valid = False
                    issue("resource_json_too_large", "resource JSON exceeds its parsing limit", "resources.json")
                else:
                    resource_report, parse_error = _parse_json_object(resource_bytes)
                    if parse_error:
                        resource_receipt_valid = False
                        resource_entry["validation"] = "invalid_json"
                        issue("resource_json_invalid", parse_error, "resources.json")
                    else:
                        resource_errors = _validate_resource_receipt(resource_report, run_report, receipt)
                        if resource_errors:
                            resource_receipt_valid = False
                        for error in resource_errors[:MAX_FRAME_VALIDATION_ERRORS]:
                            issue("resource_receipt_mismatch", error, "resources.json")
                        if len(resource_errors) > MAX_FRAME_VALIDATION_ERRORS:
                            issue("resource_validation_truncated",
                                  f"{len(resource_errors) - MAX_FRAME_VALIDATION_ERRORS} additional errors omitted",
                                  "resources.json")
                        resource_capture = resource_report.get("capture_id")
                        resource_entry["validation"] = (
                            "receipt_and_invocation_integrity_only" if resource_receipt_valid else "invalid_receipt")
                        resource_entry["measurement_values_validated"] = False
                        resource_entry["measurement_coverage"] = _manifest_text(resource_report.get("coverage"))
                        resource_entry["measurement_status"] = _manifest_text(resource_report.get("measurement_status"))
                        if (resource_report.get("coverage") != "sampled"
                                or resource_report.get("measurement_status") != "ok"):
                            issue("resource_measurement_incomplete",
                                  "resource samples are partial, capped, absent or otherwise unavailable",
                                  "resources.json")
            else:
                resource_entry["validation"] = "not_verified"

    frame_capture = None
    if frames_path is not None:
        frame_entry = _attachment("frame_report", "frames.json", "explicit --frames input",
                                  source_name=Path(frames_path).name)
        attachments.append(frame_entry)
        frame_bytes = snapshot(frame_entry, Path(frames_path))
        if frame_bytes is not None:
            frame_report, parse_error = _parse_json_object(frame_bytes)
            if parse_error:
                frame_entry["validation"] = "invalid_json"
                issue("frame_json_invalid", parse_error, "frames.json")
            else:
                try:
                    frame_errors, frame_capture = _validate_frames(frame_report, capture_id)
                except (ValueError, TypeError, RecursionError, OverflowError, RuntimeError) as error:
                    frame_errors = [f"native frame validation failed: {type(error).__name__}: {error}"]
                    frame_capture = frame_report.get("capture_id") if isinstance(frame_report.get("capture_id"), str) else ""
                frame_entry["validation"] = "valid" if not frame_errors else "invalid"
                frame_entry["validation_errors"] = frame_errors[:MAX_FRAME_VALIDATION_ERRORS]
                if frame_errors:
                    for error in frame_errors[:MAX_FRAME_VALIDATION_ERRORS]:
                        issue("frame_report_invalid", error, "frames.json")
                    if len(frame_errors) > MAX_FRAME_VALIDATION_ERRORS:
                        issue("frame_validation_truncated",
                              f"{len(frame_errors) - MAX_FRAME_VALIDATION_ERRORS} additional errors omitted",
                              "frames.json")

    if flight_log_path is not None:
        flight_entry = _attachment("flight_log", "flight-log.orfl",
                                   "explicit --flight-log input", source_name=Path(flight_log_path).name)
        attachments.append(flight_entry)
        flight_bytes = snapshot(flight_entry, Path(flight_log_path))
        if flight_bytes is not None:
            flight_entry["validation"] = "caller_supplied_unverified"

    identity_status = "verified"
    if run_report is not None and "capture_id" in run_report and capture_id is None:
        identity_status = "invalid"
    elif capture_id is None:
        identity_status = "unverified_legacy"
    else:
        if resource_entry is not None and resource_entry.get("included"):
            if (resource_report is None or resource_report.get("capture_id") != capture_id
                    or not isinstance(resource_report.get("invocation"), dict)
                    or resource_report["invocation"].get("capture_id") != capture_id):
                identity_status = "mismatch_or_unverified"
        if frames_path is not None and frame_capture != capture_id:
            identity_status = "mismatch_or_unverified"
    if identity_status == "verified" and not run_evidence["evidence_valid"]:
        identity_status = "unverified_evidence_invalid"
    if identity_status in {"mismatch_or_unverified", "invalid"}:
        issue("capture_id_mismatch", "one or more attachments cannot be tied to report.json capture_id",
              "capture_id")

    run_ok = bool(run_evidence["evidence_valid"] and run_evidence["ok"])
    manifest = {
        "format": FORMAT,
        "version": 1,
        "created_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "bundle_complete": not partial[0],
        "bundle_status": "complete" if not partial[0] else "partial",
        "run_ok": run_ok,
        "run": {
            **run_evidence,
            "declared_reason": _manifest_text(run_report.get("reason")) if run_report else None,
            "process_exit": _manifest_integer(run_report.get("process_exit")) if run_report else None,
            "capture_id": capture_id,
            "capture_identity": identity_status,
        },
        "source_metadata": {
            "run_directory_name": root.name,
            "resources_declared": resource_entry is not None,
            "frame_report_supplied": frames_path is not None,
            "flight_log_supplied": flight_log_path is not None,
            "note": note,
        },
        "input_budget": {
            "max_input_bytes": max_input_bytes,
            "max_total_bytes": max_total_bytes,
            "bytes_read": consumed_bytes,
        },
        "attachments": attachments,
        "issues": issues,
        "issues_omitted": omitted_issues[0],
        "claims": {
            "orfl_replay_validated": False,
            "hardware_approval": False,
        },
    }
    _write_bundle(Path(output_path), manifest, zip_attachments)
    return manifest


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_dir", type=Path, help="one checked Godot run directory")
    parser.add_argument("--out", type=Path, required=True, help="new .zip path; existing files are never replaced")
    parser.add_argument("--frames", type=Path, help="explicit native frame report to attach and validate")
    parser.add_argument("--flight-log", type=Path, help="explicit .orfl to attach as unverified caller input")
    parser.add_argument("--note", default="", help=f"optional incident note (at most {MAX_NOTE_CHARS} characters)")
    parser.add_argument("--max-input-bytes", type=int, default=DEFAULT_MAX_INPUT_BYTES,
                        help=f"maximum bytes per input file (1..{MAX_INPUT_BYTES}; default 64 MiB)")
    parser.add_argument("--max-total-bytes", type=int, default=DEFAULT_MAX_TOTAL_BYTES,
                        help=f"combined input-byte budget (1..{MAX_TOTAL_BYTES}; default 256 MiB)")
    return parser


def main(argv: list[str] | None = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(errors="replace")
        except (AttributeError, OSError, ValueError):
            pass
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        manifest = create_bundle(
            args.run_dir, args.out, frames_path=args.frames, flight_log_path=args.flight_log,
            note=args.note, max_input_bytes=args.max_input_bytes,
            max_total_bytes=args.max_total_bytes)
    except (BundleConfigurationError, OutputFailure, OSError, ValueError, TypeError,
            RuntimeError, RecursionError, OverflowError, zipfile.LargeZipFile) as error:
        print(f"incident bundle failed: {error}", file=sys.stderr)
        return 2

    included = sum(1 for attachment in manifest["attachments"] if attachment["included"])
    print(f"incident bundle: {manifest['bundle_status']}; run {'passed' if manifest['run_ok'] else 'failed or invalid'}; "
          f"{included} attachments; output {args.out}")
    for issue in manifest["issues"][:5]:
        print(f"  {issue['code']}: {issue['message']}", file=sys.stderr)
    if manifest["issues_omitted"]:
        print(f"  {manifest['issues_omitted']} additional issues omitted", file=sys.stderr)
    return 0 if manifest["bundle_complete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
