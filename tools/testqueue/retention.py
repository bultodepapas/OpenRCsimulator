"""Reclaim redundant queue inputs with an explicit reference check (TQ-05-F0.1).

Dry run by default. It lists what it would remove and why everything else is kept.

    python tools/testqueue/retention.py                  # dry run, summary
    python tools/testqueue/retention.py --details        # every candidate and hold
    python tools/testqueue/retention.py --execute        # journal, re-check, remove

Removed only when nothing that is still running, queued, unresolved or
recoverable refers to it, and only after ``--min-age-hours`` (default 24):

* ``attempt-source``: the writable ``source`` copy of a finished local
  ``checked`` or ``debug-session`` attempt. It covers every terminal outcome
  except ``UNKNOWN``, and only when the attempt holds no claim. Those presets
  keep their evidence outside ``source`` (``checks/``, ``imports/``, ``debug/``,
  ``worker.log`` and ``verdict.json`` stay). Other presets can keep evidence
  inside ``source`` and are never touched.
* ``local-snapshot``: a frozen input under the local authority's
  ``snapshots/``. It is held while a job that is not finished, or a submission
  that is still unresolved, names it.
* ``pool-snapshot``: a frozen pool input. It is held while any pool receipt
  that is not terminal, any batch or MCP request without a final ``PASSED``
  or ``FAILED``, or any unfinished local job names it.
* ``pool-archive``: a content-addressed transfer archive. It is held while a
  non-terminal pool receipt uses its source digest. It is removed under the
  same lock the archive builder takes, and can be rebuilt from a retained
  snapshot.

Never removed: job/attempt records, receipts, verdicts, logs, reports,
collected results, ``*.pending`` files and anything named by ``UNKNOWN`` or
quarantined work. The queue database is opened read-only. Deletion never
follows a link or reparse point. Execution first writes its plan to
``<pool root>/retention/``, recomputes references and then removes only
candidates that are still eligible.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sqlite3
import sys
import time

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
from tools.testqueue.common import state_root, write_json
from tools.testqueue.local_gc import _is_link, safe_remove_tree

SOURCE_PRESETS = {"checked", "debug-session"}
FINAL_BATCH = {"PASSED", "FAILED"}
DEFAULT_POOL_CONFIG = Path("C:/ProgramData/OpenRC/testpool/config.json")


def _read(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def _key(path) -> str:
    return os.path.normcase(os.path.normpath(str(path)))


def _age_hours(path: Path, now: float) -> float:
    try:
        return (now - os.lstat(path).st_mtime) / 3600
    except OSError:
        return 0.0


def tree_bytes(path: Path) -> int:
    total, stack = 0, [path]
    while stack:
        current = stack.pop()
        try:
            with os.scandir(current) as entries:
                for entry in entries:
                    try:
                        info = entry.stat(follow_symlinks=False)
                    except OSError:
                        continue
                    if _is_link(info):
                        continue
                    if entry.is_dir(follow_symlinks=False):
                        stack.append(entry.path)
                    else:
                        total += info.st_size
        except OSError:
            continue
    return total


def _size(path: Path) -> int:
    try:
        info = os.lstat(path)
    except OSError:
        return 0
    return tree_bytes(path) if os.path.isdir(path) and not _is_link(info) else info.st_size


class References:
    """What still needs each input, gathered from durable records only."""

    def __init__(self, queue_root: Path, pool_root: Path | None):
        self.queue_root, self.pool_root = queue_root, pool_root
        self.held: dict[str, str] = {}          # normalized snapshot path -> reason
        self.held_digests: dict[str, str] = {}  # archive source digest -> reason
        self.attempts: list[dict] = []
        self._local()
        if pool_root is not None:
            self._pool()

    def hold(self, path, reason):
        if path:
            self.held.setdefault(_key(path), reason)

    def _local(self):
        database = self.queue_root / "queue.sqlite3"
        if not database.exists():
            return
        connection = sqlite3.connect(f"file:{database.as_posix()}?mode=ro", uri=True)
        try:
            claimed = {row[0] for row in connection.execute("SELECT attempt FROM claims")}
            jobs = connection.execute("SELECT id, request_id, payload, state FROM jobs").fetchall()
            attempts = connection.execute("SELECT id, job, state, data FROM attempts").fetchall()
            canceled = {row[0] for row in connection.execute("SELECT request_id FROM canceled_submissions")}
        finally:
            connection.close()
        payloads, job_state, known_requests = {}, {}, set()
        for job, request_id, payload, state in jobs:
            known_requests.add(request_id)
            job_state[job] = state
            try:
                payloads[job] = json.loads(payload)
            except ValueError:
                payloads[job] = {}
            if state != "FINISHED":
                self.hold(payloads[job].get("snapshot"), f"local job {job} is {state}")
        for attempt, job, state, data in attempts:
            try:
                record = json.loads(data)
            except ValueError:
                record = {}
            preset = payloads.get(job, {}).get("preset")
            if state != "FINISHED" or attempt in claimed:
                self.hold(payloads.get(job, {}).get("snapshot"), f"local attempt {attempt} is {state}")
            self.attempts.append({"attempt": attempt, "job": job, "state": state, "job_state": job_state.get(job),
                                  "preset": preset, "outcome": record.get("outcome"),
                                  "claimed": attempt in claimed})
        for path in sorted((self.queue_root / "submissions").glob("*.json")):
            receipt = _read(path) or {}
            request_id = receipt.get("request_id")
            if request_id and request_id not in known_requests and request_id not in canceled:
                self.hold(receipt.get("snapshot"), f"submission {request_id} is unresolved")

    def _pool(self):
        root = self.pool_root
        for path in sorted((root / "jobs").glob("*.json")):
            receipt = _read(path)
            if receipt is None:
                # An unreadable receipt could name anything: keep every pool input.
                self.hold_all = f"unreadable pool receipt {path.name}"
                continue
            last = receipt.get("last_status") or {}
            terminal = last.get("state") == "FINISHED" or receipt.get("state") == "REJECTED"
            if not terminal:
                reason = f"pool job {path.stem} is {receipt.get('state')}/{last.get('state')}"
                self.hold(receipt.get("snapshot"), reason)
                if receipt.get("source_digest"):
                    self.held_digests.setdefault(receipt["source_digest"], reason)
        for path in sorted((root / "batches").glob("*.json")):
            if path.name.endswith("-state.json"):
                continue
            state = _read(path.with_name(path.stem + "-state.json")) or {}
            manifest = _read(path) or {}
            if state.get("result") not in FINAL_BATCH:
                self.hold(manifest.get("snapshot") or state.get("snapshot"),
                          f"batch {path.stem} is {state.get('result', 'INCOMPLETE')}")
        for directory in sorted((root / "mcp").glob("*")):
            manifest = _read(directory / "manifest.json")
            if manifest is None:
                continue
            batch = _read(directory / "batch.json") or {}
            if batch.get("result") not in FINAL_BATCH:
                self.hold(manifest.get("snapshot"), f"MCP request {directory.name} is {batch.get('result', 'INCOMPLETE')}")

    hold_all = ""


def plan(queue_root: Path, pool_root: Path | None, min_age_hours: float, now: float | None = None,
         sizes: bool = True) -> dict:
    now = time.time() if now is None else now
    refs = References(queue_root, pool_root)
    candidates, holds = [], []

    def consider(kind, path: Path, reason: str | None):
        entry = {"kind": kind, "path": str(path)}
        if reason is None and _age_hours(path, now) < min_age_hours:
            reason = f"younger than {min_age_hours:g} h"
        if sizes:
            entry["bytes"] = _size(path)
        (holds if reason else candidates).append({**entry, **({"reason": reason} if reason else {})})

    for attempt in refs.attempts:
        source = queue_root / "attempts" / attempt["attempt"] / "source"
        if not (source.exists() or source.is_symlink()):
            continue
        reason = None
        if attempt["preset"] not in SOURCE_PRESETS:
            reason = f"preset {attempt['preset']} may keep evidence in source"
        elif attempt["state"] != "FINISHED" or attempt["job_state"] != "FINISHED":
            reason = f"attempt is {attempt['state']}"
        elif attempt["claimed"]:
            reason = "attempt still holds a claim"
        elif attempt["outcome"] in (None, "UNKNOWN"):
            reason = "outcome is not final"
        consider("attempt-source", source, reason)

    def snapshot_dirs(parent: Path, kind: str):
        if not parent.is_dir():
            return
        for entry in sorted(parent.iterdir()):
            if entry.is_dir() and not _is_link(os.lstat(entry)):
                reason = refs.hold_all if kind == "pool-snapshot" and refs.hold_all else refs.held.get(_key(entry))
                consider(kind, entry, reason)

    snapshot_dirs(queue_root / "snapshots", "local-snapshot")
    if pool_root is not None:
        snapshot_dirs(pool_root / "snapshots", "pool-snapshot")
        archives = pool_root / "archives"
        if archives.is_dir():
            for entry in sorted(archives.glob("*.tar")):
                reason = refs.hold_all or refs.held_digests.get(entry.stem)
                consider("pool-archive", entry, reason)

    summary = {}
    for group, rows in (("reclaim", candidates), ("hold", holds)):
        for row in rows:
            item = summary.setdefault(row["kind"], {"reclaim": 0, "reclaim_bytes": 0, "hold": 0, "hold_bytes": 0})
            item[group] += 1
            item[group + "_bytes"] += row.get("bytes", 0)
    reasons: dict[str, dict] = {}
    for row in holds:
        label = row["reason"].split(" ")[0] if row["reason"].startswith("younger") else row["reason"]
        bucket = reasons.setdefault(label, {"count": 0, "bytes": 0})
        bucket["count"] += 1
        bucket["bytes"] += row.get("bytes", 0)
    return {"queue_root": str(queue_root), "pool_root": str(pool_root) if pool_root else None,
            "min_age_hours": min_age_hours, "summary": summary,
            "largest_holds": sorted(({"reason": k, **v} for k, v in reasons.items()),
                                    key=lambda item: -item["bytes"])[:15],
            "candidates": candidates, "holds": holds}


def execute(report: dict, queue_root: Path, pool_root: Path | None, min_age_hours: float) -> dict:
    journal_dir = (pool_root or queue_root) / "retention"
    journal_dir.mkdir(exist_ok=True)
    journal = journal_dir / time.strftime("retention-%Y%m%d-%H%M%S.json")
    write_json(journal, {"state": "PLANNED", "candidates": report["candidates"]})
    # Recompute immediately before removal: work submitted since the dry run
    # can only add references, never remove the need for a held input.
    fresh = {row["path"] for row in plan(queue_root, pool_root, min_age_hours, sizes=False)["candidates"]}
    removed, skipped, errors = 0, [], []
    for row in report["candidates"]:
        path = Path(row["path"])
        if row["path"] not in fresh:
            skipped.append(row["path"])
            continue
        guard = None
        try:
            if row["kind"] == "pool-archive":
                from tools.testqueue.pool import acquire_lock
                guard = acquire_lock(path.with_suffix(".lock"))
            removed += safe_remove_tree(path)
        except OSError as error:
            errors.append({"path": row["path"], "error": str(error)[:200]})
        finally:
            if guard is not None:
                guard.close()
    result = {"state": "DONE", "logical_bytes_removed": removed, "skipped_now_referenced": skipped,
              "errors": errors, "journal": str(journal)}
    write_json(journal, {**result, "candidates": report["candidates"]})
    return result


def _pool_root(config: Path | None) -> Path | None:
    config = config or (Path(os.environ["OPENRC_TESTPOOL_CONFIG"]) if os.environ.get("OPENRC_TESTPOOL_CONFIG")
                        else DEFAULT_POOL_CONFIG)
    data = _read(config) if config.exists() else None
    return Path(data["state_root"]) if data and data.get("state_root") else None


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--queue-root", type=Path, default=None)
    parser.add_argument("--pool-config", type=Path, default=None)
    parser.add_argument("--no-pool", action="store_true", help="local authority only")
    parser.add_argument("--min-age-hours", type=float, default=24.0)
    parser.add_argument("--details", action="store_true", help="list every candidate and hold")
    parser.add_argument("--execute", action="store_true")
    args = parser.parse_args(argv)
    if args.min_age_hours < 1:
        parser.error("--min-age-hours must be at least 1")
    queue_root = (args.queue_root or state_root()).resolve()
    pool_root = None if args.no_pool else _pool_root(args.pool_config)
    report = plan(queue_root, pool_root, args.min_age_hours)
    output = {key: value for key, value in report.items() if args.details or key not in {"candidates", "holds"}}
    output["reclaim_gb"] = round(sum(row.get("bytes", 0) for row in report["candidates"]) / 1e9, 2)
    output["execute"] = args.execute
    if args.execute:
        output["result"] = execute(report, queue_root, pool_root, args.min_age_hours)
    print(json.dumps(output, indent=2))
    return 0 if not output.get("result", {}).get("errors") else 1


if __name__ == "__main__":
    raise SystemExit(main())
