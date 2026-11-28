"""Keep recent checked batches and the local authority alive unattended (TQ-05-F2.1).

One pass:

* resumes, via the idempotent ``pool_mcp.recover``, every MCP request that has
  a frozen manifest, no final result, no live supervisor, is not
  waiting for operator reconciliation and changed within ``--max-age-hours``
  (default 6). A new-format, proved capacity wait can wake a stopped
  observer once an eligible host returns. Older
  ones are reported as stale, never resumed: their queued tests would run days
  old source.
* with ``--serve-engine``, starts ``testctl serve`` when the local authority does
  not answer. A second worker is refused by the machine-wide singleton, so this
  is safe to repeat.

It never submits new work, cancels, reconciles or removes anything.

    python tools/testqueue/watchdog.py --dry-run          # what one pass would do
    python tools/testqueue/watchdog.py --loop --interval 60 --serve-engine .tools/Godot_v4.8-beta2_win64_console.exe
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys
import time

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
from tools.testqueue import pool_mcp
from tools.testqueue.common import Singleton, write_json
from tools.testqueue.pool import Pool, default_config
from tools.testqueue.pool_batch import BATCH_VERSION
from tools.testqueue.pool_policy import plan as plan_placement

FINAL = {"PASSED", "FAILED"}
# ERROR is a supervisor decision with a reason (e.g. changed inputs), not a
# lost process: resuming it would only repeat the error every pass.
SKIP_STATES = {"FINISHED", "ERROR"}
MAX_RESUMES_PER_DAY = 6
SETTLE_BUDGET_SECONDS = 45.0
BOOT_RECOVERY_INTERVAL_SECONDS = 600.0


def _read(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def _last_change(directory: Path) -> float:
    times = []
    for name in ("supervisor.json", "batch.json", "manifest.json"):
        try:
            times.append((directory / name).stat().st_mtime)
        except OSError:
            pass
    return max(times, default=0.0)


def _capacity_waits(batch):
    # Legacy SUBMITTING and v1 WAITING can denote an accepted attempt.
    # Only the planner's explicit no-placement decision can wake an observer.
    if batch.get("version") != BATCH_VERSION:
        return
    for row in batch.get("jobs") or []:
        if not isinstance(row, dict) or not isinstance(row.get("input"), dict):
            continue
        status = row.get("status") or {}
        if not isinstance(status, dict):
            continue
        decision = status.get("decision") or {}
        job = status.get("placement_job")
        if (row.get("phase") == "WAITING" and status.get("state") == "WAITING"
                and isinstance(decision, dict) and decision.get("selected", False) is None
                and decision.get("candidates") and isinstance(job, dict)
                and isinstance(job.get("cache_id"), str) and job["cache_id"]
                and job.get("platform") == row["input"].get("platform") and row.get("request_id")):
            yield row, job


def plan(pool, *, max_age_hours: float, now: float | None = None) -> dict:
    now = time.time() if now is None else now
    resume, stale, unreadable, skipped = [], [], [], 0
    observations, by_source = None, {}
    probe_error = None
    root = pool.root / "mcp"
    for directory in sorted(root.iterdir() if root.is_dir() else []):
        if not directory.is_dir() or not (directory / "manifest.json").exists():
            continue
        batch_path, supervisor_path = directory / "batch.json", directory / "supervisor.json"
        batch = _read(batch_path) if batch_path.exists() else {}
        supervisor = _read(supervisor_path) if supervisor_path.exists() else {}
        if not isinstance(batch, dict) or not isinstance(batch.get("jobs", []), list) or not isinstance(supervisor, dict):
            unreadable.append(directory.name)
            continue
        if batch.get("result") in FINAL or supervisor.get("state") in SKIP_STATES:
            skipped += 1
            continue
        if pool_mcp._active(directory):
            skipped += 1
            continue
        age_hours = (now - _last_change(directory)) / 3600
        entry = {"request_id": directory.name, "supervisor": supervisor.get("state"),
                 "idle_hours": round(age_hours, 1)}
        if age_hours > max_age_hours:
            stale.append(entry)
            continue
        if supervisor.get("state") == "NEEDS_OPERATOR":
            for row, job in _capacity_waits(batch):
                if observations is None:
                    try:
                        observations = pool.probe()  # one fresh inventory per watchdog pass
                    except Exception as error:
                        # The authority restart and ordinary supervisor recovery still run.
                        observations, probe_error = [], str(error)[:200]
                candidates = observations
                if not row["input"].get("host"):
                    source = job["cache_id"]
                    if source not in by_source:
                        by_source[source] = pool._circuit([dict(item) for item in observations], source)
                    candidates = by_source[source]
                bound_host = row["input"].get("host") or row["status"].get("placement_host")
                if bound_host:
                    candidates = [item for item in candidates if item["id"] == bound_host]
                try:
                    selected = plan_placement(job, candidates)["selected"]
                except ValueError:
                    continue  # Unusable cached placement data needs manual observation.
                if selected is not None:
                    entry["capacity_available_for"] = row["request_id"]
                    break
            else:
                skipped += 1
                continue
        resume.append(entry)
    report = {"resume": resume, "stale": stale, "skipped": skipped}
    if unreadable:
        report["unreadable_requests"] = unreadable
    if probe_error is not None:
        report["capacity_probe_error"] = probe_error
    return report


def authority_status(root: Path) -> tuple[str, str | None]:
    from tools.testqueue.common import rpc
    try:
        rpc("hosts", root=root, timeout=5, deadline=time.monotonic() + 5)
        return "answers", None
    except Exception as error:
        detail = str(error)[:200]
    # An unresponsive owner may still be starting, or blocked in storage.
    # A new serve process cannot acquire its persistent singleton.
    try:
        lock = root / "worker.lock"
        if lock.exists():
            Singleton(lock).close()
    except OSError as error:
        return "worker lock unavailable", f"{detail}. {error}"
    return "unavailable", detail


def start_authority(engine: str, log: Path) -> None:
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("ab") as output:
        pool_mcp.spawn_background([sys.executable, str(REPO / "tools/testqueue/testctl.py"), "serve",
                                   "--engine", engine], output)


def run_once(config=None, *, max_age_hours=6.0, dry_run=False, serve_engine=None) -> dict:
    pool = Pool(config or default_config())
    now = time.time()
    report = {"at": now, **plan(pool, max_age_hours=max_age_hours, now=now)}
    previous = _read(pool.root / "watchdog.json") or {}
    # A supervisor that dies right after every start must not be restarted forever.
    history = {key: [stamp for stamp in value if now - stamp < 86400]
               for key, value in (previous.get("resume_history") or {}).items() if isinstance(value, list)}
    results = []
    for entry in report["resume"]:
        if dry_run:
            continue
        identifier = entry["request_id"]
        if len(history.get(identifier, [])) >= MAX_RESUMES_PER_DAY:
            results.append({"request_id": identifier, "resumed": False,
                            "error": f"resumed {MAX_RESUMES_PER_DAY} times in 24 h; left for an operator"})
            continue
        try:
            pool_mcp.recover(identifier, config=config)
            history.setdefault(identifier, []).append(now)
            results.append({"request_id": identifier, "resumed": True})
        except (ValueError, OSError) as error:
            results.append({"request_id": identifier, "resumed": False, "error": str(error)[:200]})
    report["results"] = results
    report["resume_history"] = {key: value for key, value in history.items() if value}
    if not dry_run:
        # TQ-07-A2: receipts that reserve a host with no batch watching them.
        try:
            report["receipts"] = pool.settle_reserving_receipts(SETTLE_BUDGET_SECONDS)
        except Exception as error:  # one bad pass must not stop supervision
            report["receipts"] = {"error": str(error)[:200]}
        # TQ-07-A9f: a remote host that rebooted settles its quarantine without an operator.
        last = previous.get("boot_recovery_at")
        if type(last) not in (int, float) or now - last >= BOOT_RECOVERY_INTERVAL_SECONDS:
            try:
                report["boot_recovery"] = pool.recover_quarantined_hosts()
            except Exception as error:
                report["boot_recovery"] = {"error": str(error)[:200]}
            report["boot_recovery_at"] = now
        else:
            report["boot_recovery_at"] = last
    from tools.testqueue.common import state_root
    report["authority_root"] = str(state_root())
    if serve_engine:
        status, error = authority_status(state_root())
        report["authority"] = status
        if error:
            report["authority_detail"] = error
        if status == "unavailable":
            if dry_run:
                report["authority"] = "would start"
            else:
                try:
                    start_authority(serve_engine, pool.root / "watchdog-serve.log")
                    report["authority"] = "start requested"
                except OSError as error:
                    report.update(authority="start failed", authority_detail=str(error)[:200])
    if not dry_run:
        try:
            write_json(pool.root / "watchdog.json", report)
        except OSError:
            pass
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--config", default=None)
    parser.add_argument("--max-age-hours", type=float, default=6.0)
    parser.add_argument("--serve-engine", default=None, help="start testctl serve with this engine when it does not answer")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--loop", action="store_true")
    parser.add_argument("--interval", type=float, default=60.0)
    args = parser.parse_args(argv)
    if not args.loop:
        print(json.dumps(run_once(args.config, max_age_hours=args.max_age_hours, dry_run=args.dry_run,
                                  serve_engine=args.serve_engine), indent=2))
        return 0
    pool = Pool(args.config or default_config())
    try:
        guard = Singleton(pool.root / "watchdog.lock")
    except OSError:
        print("another watchdog is already running", file=sys.stderr)
        return 0
    try:
        while True:
            try:
                run_once(args.config, max_age_hours=args.max_age_hours, dry_run=args.dry_run,
                         serve_engine=args.serve_engine)
            except Exception as error:  # one bad pass must not end supervision
                print(f"{time.strftime('%Y-%m-%d %H:%M:%S')} watchdog pass failed: {error}", file=sys.stderr, flush=True)
            time.sleep(max(10.0, args.interval))
    finally:
        guard.close()


if __name__ == "__main__":
    raise SystemExit(main())
