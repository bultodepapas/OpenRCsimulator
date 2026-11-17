"""Verified, immutable pool collection generations; no workspace deletion.

Directories belong to cooperating processes under one private account. Path
checks reject links/aliases but do not isolate hostile same-account mutations.
"""
from __future__ import annotations

import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import shlex
import stat
import tempfile
import unicodedata

from . import pool_history
from .snapshots import _check_no_links, _relative


MAX_BYTES = 128 * 1024 * 1024
MAX_FILES = 4096
MAX_JSON = 4 * 1024 * 1024
MAX_FAILED_STAGES = 3
FORMAT = "openrc-pool-collection-v1"
_SHA = re.compile(r"[0-9a-f]{64}\Z")
_DEVICES = {"con", "prn", "aux", "nul", "conin$", "conout$"}
_DEVICES.update(prefix + suffix for prefix in ("com", "lpt") for suffix in "123456789¹²³")


class CollectionError(ValueError):
    """Collection failed without replacing a previously published generation."""


def _directory(path, *, create=False):
    path = Path(os.path.abspath(path))
    _check_no_links(path)
    if create:
        missing = [item for item in (path, *path.parents) if not item.exists()]
        path.mkdir(parents=True, exist_ok=True)
        _check_no_links(path)
        for item in missing:
            _sync_directory(item)
            _sync_directory(item.parent)
    if not stat.S_ISDIR(path.lstat().st_mode):
        raise ValueError("collection directory is not a plain directory: " + str(path))
    return path


def _regular(path):
    _check_no_links(path)
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode):
        raise ValueError("collection evidence is not a regular file: " + str(path))
    return info


def _name(value):
    _relative(value)
    for part in PurePosixPath(value).parts:
        # Keep names portable across the Linux, macOS and Windows collectors.
        if (part[-1:] in {".", " "} or part.split(".", 1)[0].rstrip(" .").casefold() in _DEVICES
                or any(ord(c) < 32 or c in '\\:"<>|?*\'`$;&(){}[]!~' for c in part)):
            raise ValueError("unsupported collection artifact path: " + value)
    return value


def _names(values):
    if len(values) > MAX_FILES:
        raise ValueError("Artifact collection exceeds its file-count budget")
    canonical = set()
    spellings = {}
    for value in values:
        _name(value)
        key = unicodedata.normalize("NFC", value).casefold()
        if key in canonical:
            raise ValueError("collection artifact paths alias one another")
        canonical.add(key)
        parts = value.split("/")
        for count in range(1, len(parts) + 1):
            prefix = "/".join(parts[:count])
            folded = unicodedata.normalize("NFC", prefix).casefold()
            if folded in spellings and spellings[folded] != prefix:
                raise ValueError("collection artifact directory spellings alias one another")
            spellings[folded] = prefix
    for key in canonical:
        if any("/".join(key.split("/")[:n]) in canonical for n in range(1, len(key.split("/")))):
            raise ValueError("collection artifact file/directory paths conflict")


def _json(path):
    if _regular(path).st_size > MAX_JSON:
        raise ValueError("collection JSON exceeds its byte budget")
    with path.open("rb") as stream:
        data = stream.read(MAX_JSON + 1)
    if len(data) > MAX_JSON:
        raise ValueError("collection JSON exceeds its byte budget")
    return json.loads(data)


def _same_json(left, right):
    """JSON equality must distinguish booleans from integers and floats."""
    return (json.dumps(left, sort_keys=True, ensure_ascii=True, allow_nan=False)
            == json.dumps(right, sort_keys=True, ensure_ascii=True, allow_nan=False))


def _sync_directory(path):
    # Windows directory durability needs separate native qualification. Never
    # interpret successful rename alone as power-loss durability there.
    if os.name == "posix":
        descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)


def _verify_file(path, expected, *, sync=False):
    info = _regular(path)
    if (not isinstance(expected, dict) or type(expected.get("size")) is not int
            or not 0 <= expected["size"] <= MAX_BYTES
            or not isinstance(expected.get("sha256"), str) or not _SHA.fullmatch(expected["sha256"])):
        raise ValueError("invalid collection artifact metadata")
    if info.st_size != expected["size"]:
        raise ValueError("Collected artifact size/digest mismatch: " + str(path))
    checksum = hashlib.sha256()
    with path.open("r+b" if sync else "rb") as stream:
        remaining = expected["size"]
        while block := stream.read(min(1024 * 1024, remaining + 1)):
            remaining -= len(block)
            if remaining < 0:
                raise ValueError("Collected artifact exceeded its size budget")
            checksum.update(block)
        if remaining or checksum.hexdigest() != expected["sha256"]:
            raise ValueError("Collected artifact digest mismatch: " + str(path))
        if sync:
            os.fsync(stream.fileno())


def _copy_local(source, target, expected):
    _regular(source)
    remaining = expected["size"]
    with source.open("rb") as src, target.open("xb") as dst:
        while block := src.read(min(1024 * 1024, remaining + 1)):
            remaining -= len(block)
            if remaining < 0:
                raise ValueError("local artifact exceeds its declared byte budget")
            dst.write(block)
        dst.flush()
        os.fsync(dst.fileno())
    _verify_file(target, expected)


_REMOTE_COPY = r'''
import os,stat,sys
from pathlib import Path
path=Path(sys.argv[1]); limit=int(sys.argv[2])
if not path.is_absolute() or limit < 0: raise ValueError("invalid artifact request")
for part in reversed((path,*path.parents)):
    info=part.lstat()
    if stat.S_ISLNK(info.st_mode): raise ValueError("linked artifact path")
with path.open("rb") as src:
    info=os.fstat(src.fileno())
    if not stat.S_ISREG(info.st_mode) or info.st_size != limit: raise ValueError("artifact size changed")
    remaining=limit
    while True:
        block=src.read(min(1048576,remaining+1))
        if len(block)>remaining: raise ValueError("artifact grew beyond its declared size")
        if not block: break
        sys.stdout.buffer.write(block); remaining-=len(block)
    if remaining: raise ValueError("artifact was truncated")
sys.stdout.buffer.flush()
'''


def _copy_remote(protocol, host, output, name, target, expected):
    base = PurePosixPath(output)
    if not base.is_absolute() or str(base) != output or ".." in base.parts or "\\" in output:
        raise ValueError("noncanonical remote output path")
    # The remote reader emits at most the declared byte count even if the file
    # grows after status. SSH still trusts the configured cooperating host.
    command = shlex.join([host.get("python", "python3"), "-c", _REMOTE_COPY,
                          str(base / name), str(expected["size"])])
    with target.open("xb") as stream:
        protocol.subprocess.run(["ssh", "-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=10",
                                 host["ssh"], command], stdout=stream, stderr=protocol.subprocess.PIPE,
                                check=True, timeout=120,
                                creationflags=protocol.subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        stream.flush()
        os.fsync(stream.fileno())
    _verify_file(target, expected)


def _declared_artifacts(status, local):
    declared = status.get("artifacts", {})
    if not isinstance(declared, dict):
        raise ValueError("invalid artifact inventory")
    _names(declared)
    if local:
        # The worker's inventory includes private request/control files. A
        # collection is evidence, not a copy of the authority's credentials.
        declared = {name: value for name, value in declared.items()
                    if PurePosixPath(name).parts[0] in {"checks", "imports"}
                    or name in {"worker.log", "verdict.json"}}
    return declared


def _inventory(status, local):
    declared = _declared_artifacts(status, local)
    inventory = {}
    for name, value in declared.items():
        if name.casefold() in {"pool-status.json", "pool-infra-report.json", "collection-manifest.json"}:
            raise ValueError("Remote artifact conflicts with saved pool evidence")
        if local:
            if not isinstance(value, str) or not _SHA.fullmatch(value):
                raise ValueError("invalid local artifact digest")
            source = Path(status["output"]) / name
            size = _regular(source).st_size
            inventory[name] = {"size": size, "sha256": value}
        else:
            if (not isinstance(value, dict) or type(value.get("size")) is not int
                    or not 0 <= value["size"] <= MAX_BYTES
                    or not isinstance(value.get("sha256"), str) or not _SHA.fullmatch(value["sha256"])):
                raise ValueError("invalid remote artifact metadata")
            inventory[name] = {"size": value["size"], "sha256": value["sha256"]}
    if sum(item["size"] for item in inventory.values()) > MAX_BYTES:
        raise ValueError("Artifact collection exceeds 128 MiB budget")
    return inventory


def _report_name(report, field, output, local):
    value = report.get(field)
    if not isinstance(value, str) or not isinstance(output, str):
        raise ValueError("checked evidence omitted its output/report/log path")
    if local:
        # This is a path binding, not a source read. A verified generation must
        # remain usable after the authority has retired its original workspace.
        base, path = Path(output), Path(value)
        if (not base.is_absolute() or not path.is_absolute()
                or str(base) != output or str(path) != value):
            raise ValueError("local checked evidence has a noncanonical path")
        name = path.relative_to(base).as_posix()
    else:
        base, path = PurePosixPath(output), PurePosixPath(value)
        if (not base.is_absolute() or not path.is_absolute()
                or str(base) != output or str(path) != value):
            raise ValueError("remote checked evidence has a noncanonical path")
        name = path.relative_to(base).as_posix()
    return _name(name)


def _selected_report(status, local):
    verdict = (status.get("runner_verdict") or {}) if local else status
    if not isinstance(verdict, dict):
        raise ValueError("invalid runner verdict")
    report = verdict.get("checked")
    if report is not None:
        return "check", report
    imported = verdict.get("import_verdict" if local else "import")
    return ("import", imported) if imported is not None else ("execution", None)


def _checked_evidence(status, local, inventory, stage, receipt):
    kind, report = _selected_report(status, local)
    if report is None:
        if status.get("outcome") not in {"INFRA_FAILED", "CANCELED", "TIMED_OUT", "TEST_FAILED"}:
            raise ValueError("Finished attempt has no checked report; infrastructure evidence retained")
        return kind, None, True
    # The remote supervisor can exhaust the admitted execution budget or lose a
    # runner before a checked report is written. Preserve its raw partial result
    # in pool-status and retain inventoried diagnostics without inventing a test.
    if (not local and isinstance(report, dict) and report.get("ok") is False
            and report.get("complete") is False and report.get("reason") in {"timeout", "runner_exit"}
            and not any(key in report for key in ("format", "report", "log"))
            and status.get("outcome") in {"INFRA_FAILED", "CANCELED", "TIMED_OUT", "TEST_FAILED"}):
        return kind, None, True
    if (not isinstance(report, dict) or report.get("format") != "openrc-godot-check v1"
            or type(report.get("ok")) is not bool or type(report.get("complete")) is not bool):
        raise ValueError("invalid checked report")
    names = {key: _report_name(report, key, status.get("output"), local) for key in ("log", "report")}
    if names["log"] == names["report"] or any(name not in inventory for name in names.values()):
        raise ValueError("checked report/log is missing from the current artifact inventory")
    if inventory[names["log"]]["sha256"] != report.get("log_sha256"):
        raise ValueError("Checked log digest mismatch")
    if not _same_json(_json(stage / "artifacts" / names["report"]), report):
        raise ValueError("Collected report differs from the observed checked verdict")
    options = receipt.get("options", {})
    engine = (status.get("engine") or {}).get("path") if local else (receipt.get("request") or {}).get("engine_path")
    if not isinstance(engine, str):
        raise ValueError("checked report lacks its bound engine identity")
    source = str(Path(status["output"]) / "source" / "app") if local else str(PurePosixPath(status["output"]) / "source/app")
    command = ([engine, "--path", source, "--audio-driver", "Dummy", "--headless"]
               if local and kind == "check" else
               [engine, "--headless", "--path", source, "--audio-driver", "Dummy"])
    command += ["--import"] if kind == "import" else ["--script", options.get("script")]
    required = [] if kind == "import" else options.get("require", [])
    if report.get("command") != command or report.get("required_text") != required:
        raise ValueError("checked report describes a different command or required markers")
    if kind == "check":
        for key in ("max_log_bytes", "warnings_as_errors", "label"):
            if key in options.get("settings", {}) and not _same_json(report.get(key), options["settings"][key]):
                raise ValueError("checked report describes different settings")
    outcome = status.get("outcome")
    if outcome == "PASSED":
        if (kind != "check" or report["complete"] is not True or report["ok"] is not True
                or type(report.get("process_exit")) is not int or report["process_exit"] != 0
                or type(report.get("exit_code")) is not int or report["exit_code"] != 0
                or report.get("missing_required_text") != [] or not isinstance(report.get("counts"), dict)
                or type(report["counts"].get("error")) is not int or report["counts"]["error"] != 0
                or type(report["counts"].get("warning")) is not int
                or report["counts"]["warning"] < 0
                or report.get("warnings_as_errors") is True and report["counts"]["warning"] != 0
                or status.get("cleanup") != "CONFIRMED" or status.get("evidence") != "COMPLETE"):
            raise ValueError("passing pool outcome lacks coherent complete checked evidence")
        from tools.godot.run_checked import inspect_log
        observed = inspect_log(stage / "artifacts" / names["log"], required, max_chars=MAX_BYTES)
        if not _same_json(observed["counts"], report["counts"]) or observed["missing_required_text"]:
            raise ValueError("checked log diagnostics or required markers differ from its passing report")
    if outcome == "TEST_FAILED" and kind == "check" and report["ok"]:
        raise ValueError("failed pool outcome conflicts with a successful checked report")
    diagnostic = (outcome not in {"PASSED", "TEST_FAILED"} or kind != "check" or report["complete"] is not True
                  or status.get("cleanup") != "CONFIRMED" or status.get("evidence") != "COMPLETE")
    return kind, report, diagnostic


def _files(directory):
    result = {}
    total = 0
    def failed(error):
        raise error
    for parent, dirs, files in os.walk(directory, followlinks=False, onerror=failed):
        for name in dirs:
            _directory(Path(parent) / name)
        for name in files:
            path = Path(parent) / name
            relative = path.relative_to(directory).as_posix()
            size = _regular(path).st_size
            total += size
            if size > MAX_BYTES or total > 2 * MAX_BYTES + 8 * MAX_JSON or len(result) >= MAX_FILES + 8:
                raise ValueError("collection generation exceeds its inspection budget")
            checksum = hashlib.sha256()
            with path.open("rb") as stream:
                remaining = size
                while block := stream.read(min(1024 * 1024, remaining + 1)):
                    remaining -= len(block)
                    if remaining < 0:
                        raise ValueError("collection generation changed during inspection")
                    checksum.update(block)
                if remaining:
                    raise ValueError("collection generation changed during inspection")
            result[relative] = {"size": size, "sha256": checksum.hexdigest()}
    return result


def _result(status, identifier, host_id, kind, report, diagnostic, destination, local):
    result = {"pool_job": identifier, "pool_host": host_id, "pool_outcome": status["outcome"],
              "pool_status": str(destination / "pool-status.json"), "diagnostic_only": diagnostic,
              "collection_format": FORMAT}
    if diagnostic:
        name = "pool-infra-report.json"
        result.update(pool_report=str(destination / name), diagnostic_stage=kind)
        if report is not None:
            for field in ("report", "log"):
                relative = _report_name(report, field, status["output"], local)
                result["diagnostic_" + field] = str(destination / "artifacts" / relative)
    else:
        name = "report.json"
        result = {**report, **result, "log": str(destination / "engine.log"), "report": str(destination / name)}
    return name, result


def _reuse(destination, binding, status, identifier, local, receipt):
    _directory(destination)
    manifest = _json(destination / "collection-manifest.json")
    if (not isinstance(manifest, dict) or manifest.get("format") != FORMAT
            or manifest.get("binding_sha256") != binding or not isinstance(manifest.get("files"), dict)
            or manifest.get("result") not in {"report.json", "pool-infra-report.json"}):
        raise ValueError("existing collection has no matching verified manifest")
    actual = _files(destination)
    actual.pop("collection-manifest.json", None)
    if not _same_json(actual, manifest["files"]) or manifest["result"] not in actual:
        raise ValueError("existing collection changed; preserve it and collect to another output root")
    if not _same_json(_json(destination / "pool-status.json"), status):
        raise ValueError("existing collection has a different status observation")
    declared = _declared_artifacts(status, local)
    inventory = {name: manifest["files"]["artifacts/" + name] for name in declared}
    for name, expected in declared.items():
        if not local and (not isinstance(expected, dict) or type(expected.get("size")) is not int):
            raise ValueError("invalid remote artifact metadata")
        expected_digest = expected if local else expected.get("sha256")
        if not isinstance(expected_digest, str) or not _SHA.fullmatch(expected_digest):
            raise ValueError("invalid artifact digest")
        if inventory[name]["sha256"] != expected_digest or not local and inventory[name]["size"] != expected["size"]:
            raise ValueError("existing collection artifact differs from its observed inventory")
    kind, report, diagnostic = _checked_evidence(status, local, inventory, destination, receipt)
    result = _json(destination / manifest["result"])
    name, expected = _result(status, identifier, receipt["host"], kind, report, diagnostic, destination, local)
    expected_files = {"pool-status.json", name, *("artifacts/" + item for item in declared)}
    if report is not None:
        expected_files.add("original-report.json")
        if not _same_json(_json(destination / "original-report.json"), report):
            raise ValueError("existing original report differs from its bound evidence")
    if not diagnostic:
        expected_files.add("engine.log")
        log_name = _report_name(report, "log", status["output"], local)
        if not _same_json(actual.get("engine.log"), inventory[log_name]):
            raise ValueError("existing normalized log differs from its bound evidence")
    if (name != manifest["result"] or set(actual) != expected_files or not isinstance(result, dict)
            or not _same_json({key: value for key, value in result.items() if key != "history_warning"}, expected)
            or "history_warning" in result and (status["outcome"] != "PASSED" or not isinstance(result["history_warning"], str))):
        raise ValueError("existing collection normalized result differs from its evidence")
    # Retry a prior directory-sync failure before returning a visible generation.
    _sync_directory(destination)
    _sync_directory(destination.parent)
    return result


def _receipt_identity(receipt, protocol):
    identity = {key: receipt.get(key) for key in ("request_id", "host", "config_sha256",
                "local_authority_root", "source_digest", "options", "inputs")}
    identity["request_sha256"] = protocol.request_digest(receipt.get("request"))
    return identity


def verify_collection(pool, identifier, result):
    """Revalidate a saved generation locally, without observing or launching a job."""
    from . import pool as protocol
    if not isinstance(identifier, str) or not identifier.isalnum():
        raise ValueError("invalid job id")
    if not isinstance(result, dict) or result.get("collection_format") != FORMAT:
        raise ValueError("collection has no verified generation format")
    value = result.get("pool_status")
    if not isinstance(value, str):
        raise ValueError("collection omitted its saved status path")
    status_path = Path(value)
    if (not status_path.is_absolute() or str(status_path) != value or ".." in status_path.parts
            or status_path.name != "pool-status.json"):
        raise ValueError("collection status path is not canonical")
    destination = status_path.parent
    if not re.fullmatch(r"collection-[0-9a-f]{64}", destination.name):
        raise ValueError("collection generation path is invalid")
    parent = destination.parent
    guard = protocol.acquire_lock(pool.root / (identifier + ".collect.lock"))
    destination_guard = None
    try:
        job_guard = protocol.acquire_lock(pool.root / (identifier + ".lock"))
        try:
            receipt = pool._read_receipt_locked(pool.root / "jobs" / (identifier + ".json"))
            host, _ = pool._destination(receipt)
            request = receipt.get("request")
            if (receipt.get("request_id") != identifier or not isinstance(request, dict)
                    or request.get("request_id") != identifier):
                raise ValueError("collection receipt has a different request identity")
            identity = _receipt_identity(receipt, protocol)
            recovery = bool(receipt.get("invalidated_nonexecution"))
        finally:
            job_guard.close()
        if recovery:
            valid_parent = parent.name == "recovery-1" and parent.parent.name == identifier
        else:
            valid_parent = parent.name == identifier
        if not valid_parent:
            raise ValueError("collection path does not belong to its request")
        _directory(parent)
        lock_path = parent / ".collection.lock"
        if lock_path.exists() or lock_path.is_symlink():
            _regular(lock_path)
        destination_guard = protocol.acquire_lock(lock_path)
        status = _json(status_path)
        if (not isinstance(status, dict) or status.get("state") != "FINISHED"
                or status.get("job") != identifier or status.get("pool_host") != host["id"]
                or status.get("request_id", identifier) != identifier):
            raise ValueError("saved collection status has a different request identity")
        if host.get("local", False):
            pool._verify_local_status(receipt, status)
        else:
            pool._verify_remote_status(receipt, status)
        binding = protocol.request_digest({"identity": identity, "status": status})
        if destination.name != "collection-" + binding:
            raise ValueError("saved collection differs from its bound receipt and status")
        verified = _reuse(destination, binding, status, identifier, host.get("local", False), receipt)
        if not _same_json(verified, result):
            raise ValueError("saved batch collection differs from its verified generation")
        return verified
    finally:
        if destination_guard is not None:
            destination_guard.close()
        guard.close()


def collect(pool, identifier, out_dir=None):
    from . import pool as protocol
    if not isinstance(identifier, str) or not identifier.isalnum():
        raise ValueError("invalid job id")
    guard = protocol.acquire_lock(pool.root / (identifier + ".collect.lock"))
    destination_guard = None
    staging = None
    try:
        job_guard = protocol.acquire_lock(pool.root / (identifier + ".lock"))
        try:
            status = pool._status_locked(identifier)
            if status.get("state") != "FINISHED":
                raise ValueError("Collection requires a confirmed finished attempt")
            receipt = pool._read_receipt_locked(pool.root / "jobs" / (identifier + ".json"))
            host, _ = pool._destination(receipt)
            # Copy the accepted observation while the receipt's lock is held.
            status = json.loads(json.dumps(status, allow_nan=False))
            identity = _receipt_identity(receipt, protocol)
        finally:
            job_guard.close()
        if status.get("outcome") not in {"PASSED", "TEST_FAILED", "INFRA_FAILED", "TIMED_OUT", "CANCELED"}:
            raise ValueError("unrecognized finished pool outcome")
        base = _directory(Path(out_dir).expanduser() if out_dir is not None else pool.root / "results", create=True)
        parent = _directory(base / identifier, create=True)
        if receipt.get("invalidated_nonexecution"):
            parent = _directory(parent / "recovery-1", create=True)
        lock_path = parent / ".collection.lock"
        if lock_path.exists() or lock_path.is_symlink():
            _regular(lock_path)
        destination_guard = protocol.acquire_lock(lock_path)
        binding = protocol.request_digest({"identity": identity, "status": status})
        destination = parent / ("collection-" + binding)
        if destination.exists() or destination.is_symlink():
            return _reuse(destination, binding, status, identifier, host.get("local", False), receipt)
        if sum(1 for _ in parent.glob(".collection-*.pending")) >= MAX_FAILED_STAGES:
            raise CollectionError("retained collection staging budget reached; inspect existing evidence or use another output root")
        staging = Path(tempfile.mkdtemp(prefix=".collection-", suffix=".pending", dir=parent))
        protocol.write_json(staging / "pool-status.json", status)
        _json(staging / "pool-status.json")
        inventory = _inventory(status, host.get("local", False))
        if inventory:
            if host.get("local"):
                _directory(Path(status["output"]))
            for name, metadata in sorted(inventory.items()):
                target = staging / "artifacts" / name
                _directory(target.parent, create=True)
                if host.get("local"):
                    _copy_local(Path(status["output"]) / name, target, metadata)
                else:
                    _copy_remote(protocol, host, status["output"], name, target, metadata)
        kind, report, diagnostic = _checked_evidence(status, host.get("local", False), inventory, staging, receipt)
        result_name, result = _result(status, identifier, host["id"], kind, report, diagnostic,
                                      destination, host.get("local", False))
        if report is not None:
            protocol.write_json(staging / "original-report.json", report)
        if not diagnostic:
            log_name = _report_name(report, "log", status["output"], host.get("local", False))
            _copy_local(staging / "artifacts" / log_name, staging / "engine.log", inventory[log_name])
            if status["outcome"] == "PASSED":
                try:
                    elapsed = report["elapsed_seconds"]
                    if type(elapsed) not in (int, float) or not math.isfinite(elapsed) or elapsed < 0:
                        raise ValueError("invalid elapsed time")
                    history_guard = protocol.Singleton(pool.root / "history.lock")
                    try:
                        path = pool.root / "history.json"
                        history = _json(path) if path.exists() else {}
                        if not isinstance(history, dict):
                            raise ValueError("history must be a mapping")
                        # Keyed by pool job: a retried collection of the same
                        # run cannot add a second sample to the window.
                        pool_history.record(history, host["id"], receipt["options"]["script"], elapsed, identifier)
                        if isinstance(status.get("import"), dict):
                            setup = status["import"].get("elapsed_seconds")
                            if type(setup) not in (int, float) or not math.isfinite(setup) or setup < 0:
                                raise ValueError("invalid import elapsed time")
                            pool_history.record(history, host["id"], pool_history.SETUP_KEY, setup, identifier)
                        protocol.write_json(path, history)
                    finally:
                        history_guard.close()
                except (OSError, ValueError, KeyError, TypeError, RuntimeError) as error:
                    result["history_warning"] = str(error)
        protocol.write_json(staging / result_name, result)
        _json(staging / result_name)
        manifest = {"format": FORMAT, "binding_sha256": binding, "result": result_name, "files": _files(staging),
                    "scope": "declared evidence; local checks/imports/worker log/verdict only; not a complete workspace inventory"}
        protocol.write_json(staging / "collection-manifest.json", manifest)
        _json(staging / "collection-manifest.json")
        for directory, _, _ in os.walk(staging, topdown=False):
            _sync_directory(Path(directory))
        _sync_directory(parent)
        if destination.exists() or destination.is_symlink():
            raise ValueError("collection destination appeared before publication")
        staging.rename(destination)
        _sync_directory(parent)
        staging = None
        return result
    except Exception as error:
        if staging is not None:
            retained = staging if staging.exists() else destination
            raise CollectionError(f"{error}; retained collection evidence: {retained}") from error
        raise
    finally:
        if destination_guard is not None:
            destination_guard.close()
        guard.close()
