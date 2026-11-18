"""Command line: serve, purge, rollup, report, publish. Messages are fixed categories only."""
from __future__ import annotations

import argparse
from datetime import datetime, timedelta, timezone
import json
import logging
import os
import sys
import time

from .config import Config
from .contract import ContractError, load_contracts
from .publisher import GitHub, publish
from .report import material
from .rollup import eligibility_window, run_rollup
from .storage import RAW_TTL, AggStore, RawStore, StorageUnavailable


def _parser():
    parser = argparse.ArgumentParser(prog="openrc_telemetry", description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    serve = sub.add_parser("serve", help="run the ingress service")
    serve.add_argument("--host", default="127.0.0.1")
    serve.add_argument("--port", type=int, default=8787)
    sub.add_parser("purge", help="delete raw rows older than 48 h and aggregates older than 180 days")
    rollup = sub.add_parser("rollup", help="roll up one closed UTC day")
    rollup.add_argument("--day", required=True, help="YYYY-MM-DD, or 'yesterday'")
    report = sub.add_parser("report", help="render the deterministic weekly report")
    report.add_argument("--week", required=True, help="YYYY-Www")
    report.add_argument("--release", required=True)
    report.add_argument("--format", choices=("markdown", "json"), default="markdown")
    pub = sub.add_parser("publish", help="reconcile-then-create the weekly GitHub issue")
    pub.add_argument("--week", required=True)
    pub.add_argument("--release", required=True)
    pub.add_argument("--repo", required=True, help="owner/name")
    pub.add_argument("--approved-digest", required=True)
    group = pub.add_mutually_exclusive_group()
    group.add_argument("--dry-run", action="store_true", help="default: print only")
    group.add_argument("--execute", action="store_true", help="perform the remote write")
    return parser


def purge_margin_s(config):
    """How much earlier than 48 h serve's own purge cuts: with one purge per interval, no raw row outlives 48 h."""
    return int(config.purge_interval_s) + 60


def purge_once(config, now, raw=None, agg=None, margin_s=0):
    raw = raw or RawStore(config.raw_path, config.max_raw_bytes)
    agg = agg or AggStore(config.aggregates_path)
    return {**raw.purge(now, RAW_TTL - margin_s), **agg.purge(now)}


def _purge_loop(config, raw, agg, stop):
    """Background retention inside serve; an external hourly purge remains a second line of defence."""
    while not stop.wait(config.purge_interval_s):
        try:
            purge_once(config, time.time(), raw, agg, purge_margin_s(config))
        except StorageUnavailable:
            logging.getLogger("openrc_telemetry").warning("purge category=storage_unavailable")


def _serve(config, args):
    import threading
    import uvicorn
    from .ingress import create_app
    if not config.releases:
        print("warning: OPENRC_TELEMETRY_RELEASES is empty; every batch will be rejected (422)", file=sys.stderr)
    app = create_app(config)
    stop = threading.Event()
    purge_once(config, time.time(), app.state.raw, app.state.aggregates, purge_margin_s(config))
    threading.Thread(target=_purge_loop, args=(config, app.state.raw, app.state.aggregates, stop),
                     name="telemetry-purge", daemon=True).start()
    try:
        # Access logs would record addresses and paths; proxy headers are handled by the app itself. Concurrency is
        # bounded so slow request bodies cannot hold unlimited sockets (the TLS proxy also bounds body read time).
        uvicorn.run(app, host=args.host, port=args.port, access_log=False, log_level="warning",
                    server_header=False, proxy_headers=False, timeout_keep_alive=5, limit_concurrency=200)
    finally:
        stop.set()
    return 0


def _purge(config):
    result = purge_once(config, time.time())
    print(json.dumps(result, sort_keys=True))
    if result["checkpoint_busy"]:
        print("warning: WAL checkpoint was blocked by a reader; rerun purge", file=sys.stderr)
        return 1
    return 0


def _rollup(config, args):
    now = time.time()
    day = args.day
    if day == "yesterday":
        day = (datetime.fromtimestamp(now, tz=timezone.utc).date() - timedelta(days=1)).isoformat()
    contracts = load_contracts(config.schema_dir)
    raw, agg = RawStore(config.raw_path, config.max_raw_bytes), AggStore(config.aggregates_path)
    try:
        results = run_rollup(contracts, raw, agg, day, now, config.releases)
    except ContractError as error:
        if str(error) == "day_not_eligible":
            try:
                start, end = eligibility_window(day)
                print(f"refused: {day} can be rolled up from {start.isoformat()} until {end.isoformat()} only",
                      file=sys.stderr)
            except ContractError:
                print("refused: day must be YYYY-MM-DD", file=sys.stderr)
        else:
            print(f"refused: {error}", file=sys.stderr)
        return 2
    for release, table, status in results:
        print(f"{day} {release} {table}: {status}")
    return 0


def _report(config, args):
    contracts = load_contracts(config.schema_dir)
    agg = AggStore(config.aggregates_path)
    title, body, digest = material(contracts, agg, args.week, args.release)
    if args.format == "json":
        print(json.dumps({"title": title, "body": body, "digest": digest}, ensure_ascii=False, indent=2))
    else:
        sys.stdout.write(body)
        print(f"title: {title}", file=sys.stderr)
        print(f"digest: {digest}", file=sys.stderr)
    return 0


def _publish(config, args):
    contracts = load_contracts(config.schema_dir)
    agg = AggStore(config.aggregates_path)
    token = os.environ.get("GITHUB_TOKEN", "")
    github = GitHub(config.github_api, token) if (args.execute and token) else None
    result = publish(agg, contracts, week=args.week, release=args.release, repository=args.repo,
                     approved_digest=args.approved_digest, execute=args.execute, now=time.time(),
                     releases=config.releases, bot_author=config.bot_author, label=config.issue_label,
                     github=github)
    print(f"{result.outcome}: {result.message}")
    return result.exit_code


def main(argv=None):
    args = _parser().parse_args(argv)
    config = Config.from_env()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s", stream=sys.stderr)
    try:
        if args.command == "serve":
            return _serve(config, args)
        if args.command == "purge":
            return _purge(config)
        if args.command == "rollup":
            return _rollup(config, args)
        if args.command == "report":
            return _report(config, args)
        return _publish(config, args)
    except ContractError as error:
        print(f"refused: {error}", file=sys.stderr)
        return 2
    except StorageUnavailable:
        print("error: storage unavailable", file=sys.stderr)
        return 1
