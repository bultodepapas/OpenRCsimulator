"""Read-only fleet measures from the pool's retained records (TQ-07-A0).

Computes, with fixed definitions, the numbers the fleet plan's targets are read
from: how requests ended, which ones needed a person, placement/snapshot/
collection/transfer times, receipts that reserve a host, refusal causes of
waiting rows and how jobs were routed. It opens no network connection and
writes nothing under the pool root.

    python tools/testqueue/fleet_report.py                    # last 7 days, text
    python tools/testqueue/fleet_report.py --days 0 --json r.json   # everything, JSON too

Definitions:
- A request "needs a person" when it has no final result and its supervisor
  stopped in NEEDS_OPERATOR or ERROR, or nothing changed for more than 6 h (the
  watchdog stops resuming it then). The rest without a result are "in flight".
- An executed attempt is a receipt whose last observation is FINISHED with an
  outcome other than NOT_DISPATCHED or CANCELED.
- A transfer is an upload when it took 60 s or more, otherwise a reuse check of
  an archive the host already had.
- A receipt reserves its host in PREPARING, SUBMISSION_UNCONFIRMED or
  NOT_DISPATCHED (the pool's own rule).
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import json
import os
from pathlib import Path
import sys
import time

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))

RESERVING = {"PREPARING", "SUBMISSION_UNCONFIRMED", "NOT_DISPATCHED"}
NOT_EXECUTED = {"NOT_DISPATCHED", "CANCELED"}
UPLOAD_SECONDS = 60.0
STALE_HOURS = 6.0  # the watchdog's resume window


def _last_change(directory, default):
    times = [default]
    for name in ("supervisor.json", "batch.json", "manifest.json"):
        try:
            times.append((Path(directory) / name).stat().st_mtime)
        except OSError:
            pass
    return max(times)


def _read(path):
    try:
        value = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return value if isinstance(value, dict) else None


def _quantiles(values):
    values = sorted(value for value in values if isinstance(value, (int, float)))
    if not values:
        return None
    pick = lambda q: values[min(len(values) - 1, int(q * len(values)))]
    return {"n": len(values), "p50": round(pick(0.5), 1), "p90": round(pick(0.9), 1), "max": round(values[-1], 1)}


def default_root():
    config = os.environ.get("OPENRC_TESTPOOL_CONFIG",
                            str(Path(os.environ.get("PROGRAMDATA", "/var/tmp")) / "OpenRC/testpool/config.json"))
    value = _read(config) or {}
    return Path(value.get("state_root") or Path(config).parent)


def report(root, *, days=7.0, now=None):
    root = Path(root)
    now = time.time() if now is None else now
    since = now - days * 86400 if days else 0.0
    requests = Counter()
    needs_person = Counter()
    in_flight = 0
    results = Counter()
    rows = Counter()
    platforms, pins = Counter(), Counter()
    waiting = Counter()
    stages = defaultdict(list)
    jobs_per_request = []
    for directory in sorted((root / "mcp").glob("*")):
        request = _read(directory / "request.json")
        if not directory.is_dir() or request is None:
            continue
        try:
            stamp = (directory / "request.json").stat().st_mtime
        except OSError:
            continue
        if stamp < since:
            continue
        supervisor = _read(directory / "supervisor.json") or {}
        batch = _read(directory / "batch.json") or {}
        state = supervisor.get("state") or "ACCEPTED"
        result = batch.get("result") or ("NO_BATCH" if not batch else "INCOMPLETE")
        requests[state] += 1
        results[result] += 1
        if result not in {"PASSED", "FAILED"}:
            idle_hours = (now - _last_change(directory, stamp)) / 3600
            if state == "NEEDS_OPERATOR" or state == "ERROR":
                needs_person[(state, str(supervisor.get("detail") or supervisor.get("error") or "")[:60])] += 1
            elif idle_hours > STALE_HOURS:
                needs_person[("STALE", f"{state}, idle over {STALE_HOURS:g} h; the watchdog no longer resumes it")] += 1
            else:
                in_flight += 1
        jobs = request.get("jobs") or []
        jobs_per_request.append(len(jobs))
        for job in jobs:
            platforms[job.get("platform") or "unset"] += 1
            pins["pinned" if job.get("host") else "unpinned"] += 1
        if isinstance(supervisor.get("snapshot_seconds"), (int, float)):
            stages["snapshot"].append(supervisor["snapshot_seconds"])
        for row in batch.get("jobs") or []:
            status = row.get("status") or {}
            phase = row.get("phase")
            rows[phase if phase != "DONE" else "DONE:" + str(status.get("outcome"))] += 1
            for name, value in (row.get("coordinator_seconds") or {}).items():
                stages["coordinator_" + name].append(value)
            if phase in {"WAITING", "RETRY_WAIT"}:
                for candidate in (status.get("decision") or {}).get("candidates") or []:
                    for reason in candidate.get("reasons") or []:
                        waiting[f"{candidate.get('host')}:{str(reason).split(':')[0]}"] += 1
    archives = {}
    for path in (root / "archives").glob("*.tar"):
        try:
            archives[path.stem] = path.stat().st_size
        except OSError:
            pass
    outcomes = Counter()
    reserving = []
    transfers = defaultdict(lambda: {"uploads": [], "reuse": [], "rates": []})
    for path in sorted((root / "jobs").glob("*.json")):
        receipt = _read(path)
        if receipt is None:
            continue
        created = receipt.get("created")
        try:
            modified = path.stat().st_mtime
        except OSError:
            continue
        created = created if isinstance(created, (int, float)) else modified
        host = receipt.get("host")
        if receipt.get("state") in RESERVING:
            reserving.append({"job": path.stem, "host": host, "state": receipt.get("state"),
                              "age_hours": round((now - created) / 3600, 1),
                              "error": str(receipt.get("error") or (receipt.get("last_status") or {}).get("error") or "")[:120]})
        if created < since:
            continue
        last = receipt.get("last_status") or {}
        if last.get("state") == "FINISHED" and last.get("outcome") not in NOT_EXECUTED:
            outcomes[(host, last.get("outcome"))] += 1
        seconds = receipt.get("transfer_seconds")
        if isinstance(seconds, (int, float)):
            entry = transfers[host]
            if seconds >= UPLOAD_SECONDS:
                entry["uploads"].append(seconds)
                size = archives.get(receipt.get("source_digest"))
                if size:
                    entry["rates"].append(size / seconds / 1e6)
            else:
                entry["reuse"].append(seconds)
    executed = sum(outcomes.values())
    infra = sum(count for (_, outcome), count in outcomes.items() if outcome == "INFRA_FAILED")
    total_requests = sum(requests.values())
    return {
        "root": str(root), "window_days": days or None, "generated_at": now,
        "requests": {"total": total_requests, "by_supervisor_state": dict(requests),
                     "by_result": dict(results), "in_flight": in_flight,
                     "needs_person": sum(needs_person.values()),
                     "needs_person_share": round(sum(needs_person.values()) / total_requests, 3) if total_requests else None,
                     "needs_person_causes": {f"{state}: {detail}": count for (state, detail), count in needs_person.most_common(12)},
                     "jobs_per_request": _quantiles(jobs_per_request)},
        "rows": dict(rows),
        "routing": {"platform": dict(platforms), "pinning": dict(pins)},
        "executed_attempts": {"total": executed, "infra_failed": infra,
                              "infra_share": round(infra / executed, 3) if executed else None,
                              "by_host_outcome": {f"{host}:{outcome}": count for (host, outcome), count in sorted(outcomes.items(), key=str)}},
        "stage_seconds": {name: _quantiles(values) for name, values in sorted(stages.items())},
        "transfers": {host: {"uploads": _quantiles(value["uploads"]), "reuse_checks": _quantiles(value["reuse"]),
                             "upload_mb_per_s": _quantiles(value["rates"])}
                      for host, value in sorted(transfers.items(), key=lambda item: str(item[0]))},
        "reserving_receipts": sorted(reserving, key=lambda item: -item["age_hours"]),
        "waiting_refusals": dict(waiting.most_common(20)),
    }


def text(value):
    lines = [f"fleet report: {value['root']} (window: {value['window_days'] or 'all'} days)"]
    requests = value["requests"]
    lines.append(f"requests {requests['total']}: results {requests['by_result']}; in flight {requests['in_flight']}; "
                 f"needs a person {requests['needs_person']} ({requests['needs_person_share']})")
    for cause, count in requests["needs_person_causes"].items():
        lines.append(f"  {count} x {cause}")
    attempts = value["executed_attempts"]
    lines.append(f"executed attempts {attempts['total']}, infrastructure failures {attempts['infra_failed']} "
                 f"({attempts['infra_share']})")
    for name, quantiles in value["stage_seconds"].items():
        lines.append(f"  {name}: {quantiles}")
    for host, entry in value["transfers"].items():
        lines.append(f"  transfer {host}: uploads {entry['uploads']}; reuse {entry['reuse_checks']}; MB/s {entry['upload_mb_per_s']}")
    lines.append(f"routing: {value['routing']}")
    lines.append(f"reserving receipts: {len(value['reserving_receipts'])}")
    for item in value["reserving_receipts"][:15]:
        lines.append(f"  {item['host']} {item['state']} {item['age_hours']} h {item['job'][:12]} {item['error']}")
    if value["waiting_refusals"]:
        lines.append(f"waiting refusals: {value['waiting_refusals']}")
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, help="pool state root (default: from the pool configuration)")
    parser.add_argument("--days", type=float, default=7.0, help="window in days; 0 for everything")
    parser.add_argument("--json", type=Path, help="also write the full report here (never under the pool root)")
    args = parser.parse_args(argv)
    root = (args.root or default_root()).resolve()
    value = report(root, days=args.days)
    if args.json:
        target = args.json.resolve()
        if root in target.parents:
            parser.error("--json must not write under the pool root; this tool is read-only there")
        target.write_text(json.dumps(value, indent=2), encoding="utf-8")
    print(text(value))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
