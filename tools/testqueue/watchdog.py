"""Keep recent checked batches and the local authority alive unattended (TQ-05-F2.1).

One pass:

* resumes, via the idempotent ``pool_mcp.recover``, every MCP request that has
  a frozen manifest, no final result, no live supervisor, is not
  ``NEEDS_OPERATOR`` and changed within ``--max-age-hours`` (default 24). Older
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

FINAL = {"PASSED", "FAILED"}
# ERROR is a supervisor decision with a reason (e.g. changed inputs), not a
# lost process: resuming it would only repeat the error every pass.
SKIP_STATES = {"NEEDS_OPERATOR", "FINISHED", "ERROR"}
MAX_RESUMES_PER_DAY = 6


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


def plan(pool, *, max_age_hours: float, now: float | None = None) -> dict:
    now = time.time() if now is None else now
    resume, stale, skipped = [], [], 0
    root = pool.root / "mcp"
    for directory in sorted(root.iterdir() if root.is_dir() else []):
        if not directory.is_dir() or not (directory / "manifest.json").exists():
            continue
        batch = _read(directory / "batch.json") or {}
        supervisor = _read(directory / "supervisor.json") or {}
        if batch.get("result") in FINAL or supervisor.get("state") in SKIP_STATES:
            skipped += 1
            continue
        if pool_mcp._active(directory):
            skipped += 1
            continue
        age_hours = (now - _last_change(directory)) / 3600
        entry = {"request_id": directory.name, "supervisor": supervisor.get("state"),
                 "idle_hours": round(age_hours, 1)}
        (resume if age_hours <= max_age_hours else stale).append(entry)
    return {"resume": resume, "stale": stale, "skipped": skipped}


def authority_answers() -> bool:
    from tools.testqueue.common import rpc
    try:
        rpc("hosts", timeout=5)
        return True
    except Exception:
        return False


def start_authority(engine: str, log: Path) -> None:
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("ab") as output:
        pool_mcp.spawn_background([sys.executable, str(REPO / "tools/testqueue/testctl.py"), "serve",
                                   "--engine", engine], output)


def run_once(config=None, *, max_age_hours=24.0, dry_run=False, serve_engine=None) -> dict:
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
    if serve_engine:
        answers = authority_answers()
        report["authority"] = "answers" if answers else ("would start" if dry_run else "started")
        if not answers and not dry_run:
            start_authority(serve_engine, pool.root / "watchdog-serve.log")
    if not dry_run:
        try:
            write_json(pool.root / "watchdog.json", report)
        except OSError:
            pass
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--config", default=None)
    parser.add_argument("--max-age-hours", type=float, default=24.0)
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
