"""Durable, nonblocking MCP facade for the checked-test pool."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import time

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
from tools.testqueue.common import Singleton, write_json
from tools.testqueue.pool import Pool, default_config, digest
from tools.testqueue.pool_batch import run_batch
from tools.testqueue.presets import validate, scheduling


def _read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def _directory(pool, request_id):
    if not isinstance(request_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", request_id):
        raise ValueError("request_id must be 1-80 letters, digits, underscores or hyphens")
    return pool.root / "mcp" / request_id


def _jobs(jobs):
    if not isinstance(jobs, list) or not 1 <= len(jobs) <= 64:
        raise ValueError("jobs must contain 1-64 independent checked tests")
    result = []
    for job in jobs:
        if not isinstance(job, dict) or set(job) - {"script", "platform", "require", "timeout", "host"}:
            raise ValueError("invalid job fields")
        target = job.get("platform", platform.system().lower())
        if target not in {"windows", "linux", "darwin", "any"}:
            raise ValueError("invalid platform")
        options = validate("checked", {"script": job.get("script"), "require": job.get("require", []),
                                      "timeout": job.get("timeout", 90), "headless": True})
        if scheduling("checked", options)["workload"] == "performance":
            raise ValueError("performance tests require a dedicated same-host campaign")
        item = {"script": options["script"], "require": options["require"],
                "timeout": options["timeout"], "platform": target}
        if "host" in job:
            if not isinstance(job["host"], str) or not job["host"]:
                raise ValueError("host must be a nonempty ID")
            item["host"] = job["host"]
        result.append(item)
    return result


def _start(directory):
    with (directory / "supervisor.log").open("ab") as output:
        options = {"stdin": subprocess.DEVNULL, "stdout": output, "stderr": output,
                   "cwd": str(REPO), "close_fds": True}
        if os.name == "nt":
            options["creationflags"] = subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW
        else:
            options["start_new_session"] = True
        subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "--worker", str(directory)], **options)


def _active(directory):
    if not (directory / "worker.lock").exists():
        return False
    try:
        lock = Singleton(directory / "worker.lock")
    except OSError:
        return True
    lock.close()
    return False


def launch(request_id, jobs, source=None, *, config=None):
    pool = Pool(config or default_config())
    directory = _directory(pool, request_id)
    source = Path(source or REPO).resolve()
    if not (source / "app" / "project.godot").is_file():
        raise ValueError("source must be an OpenRC checkout with app/project.godot")
    request = {"request_id": request_id, "jobs": _jobs(jobs), "source": str(source),
               "config": str(pool.config_path), "config_sha256": digest(pool.config_path)}
    guard = Singleton(directory / "request.lock")
    try:
        path = directory / "request.json"
        if path.exists():
            if _read(path) != request:
                raise ValueError("request_id already binds different inputs; use the original request")
        else:
            write_json(path, request)
        if not (directory / "supervisor.json").exists():
            write_json(directory / "supervisor.json", {"state": "ACCEPTED", "updated_at": time.time()})
        # A lost reply or failed Popen may leave only the durable request. Safe
        # duplicate children are excluded by worker.lock before freezing bytes.
        if _read(directory / "supervisor.json").get("state") == "ACCEPTED" and not _active(directory):
            _start(directory)
    finally:
        guard.close()
    return status(request_id, config=config)


def status(request_id, *, config=None):
    """Read receipts only. No network, snapshots, launches or collection."""
    pool = Pool(config or default_config())
    directory = _directory(pool, request_id)
    request = _read(directory / "request.json")
    result = {"request_id": request_id, "receipt": str(directory),
              "supervisor": _read(directory / "supervisor.json") if (directory / "supervisor.json").exists() else {"state": "ACCEPTED"},
              "source": request["source"], "source_frozen": (directory / "manifest.json").exists()}
    result["supervisor_active"] = _active(directory)
    if (directory / "batch.json").exists():
        batch = _read(directory / "batch.json")
        result.update(result=batch.get("result", "INCOMPLETE"), snapshot=batch["snapshot"], jobs=batch["jobs"])
    return result


def recover(request_id, *, config=None):
    pool = Pool(config or default_config())
    directory = _directory(pool, request_id)
    request = _read(directory / "request.json")
    if digest(pool.config_path) != request["config_sha256"]:
        raise ValueError("pool configuration changed; restore the original configuration before recovery")
    if (directory / "batch.json").exists() and _read(directory / "batch.json").get("result") in {"PASSED", "FAILED"}:
        return status(request_id, config=config)
    _start(directory)  # worker.lock excludes concurrent supervisors
    return status(request_id, config=config)


def supervise(directory):
    directory = Path(directory).resolve()
    try:
        guard = Singleton(directory / "worker.lock")
    except OSError:
        return
    state_path = directory / "supervisor.json"
    def update(state, **extra):
        write_json(state_path, {"state": state, "updated_at": time.time(), **extra})
    try:
        request = _read(directory / "request.json")
        if digest(request["config"]) != request["config_sha256"]:
            raise ValueError("pool configuration changed; restore it before recovery")
        pool = Pool(request["config"])
        manifest = directory / "manifest.json"
        if not manifest.exists():
            previous = _read(state_path) if state_path.exists() else {}
            if previous.get("state") != "ACCEPTED":
                raise ValueError("snapshot preparation was interrupted; no tests dispatched; use a new request_id for current source")
            update("SNAPSHOTTING")
            snapshot = pool.snapshot(Path(request["source"]))
            write_json(manifest, {"snapshot": str(snapshot), "jobs": request["jobs"]})
        deadline = time.monotonic() + 3600
        while time.monotonic() < deadline:
            update("RUNNING")
            batch_path = directory / "batch.json"
            if batch_path.exists():
                for row in _read(batch_path)["jobs"]:
                    if row["phase"] == "BLOCKED" and (pool.root / "jobs" / (row["request_id"] + ".json")).exists():
                        try:
                            pool.recover(row["request_id"])
                        except (OSError, RuntimeError, ValueError, subprocess.SubprocessError):
                            pass  # retry only this exact receipt on the next observation
            batch = run_batch(pool, request["config"], manifest, batch_path,
                              timeout=min(30, max(0.1, deadline - time.monotonic())))
            if batch["result"] in {"PASSED", "FAILED"}:
                update("FINISHED", result=batch["result"])
                return
            update("WAITING", result="INCOMPLETE")
            time.sleep(5)
        update("INCOMPLETE", detail="Supervisor observation deadline reached; recover the same request to continue. Remote jobs are not cancelled.")
    except Exception as error:
        update("ERROR", error=str(error))
    finally:
        guard.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--worker", required=True)
    supervise(parser.parse_args().worker)
