"""Record completed parse/unit scripts without treating a report count as coverage.

The shell supplies the same NUL-delimited roster it executes. A receipt is created
only after every selected invocation succeeds and the roster and its bytes still
match the starting snapshot. It identifies these scripts and the runner, not all
their transitive inputs or the heterogeneous integration runtime checks.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def names(path: Path) -> list[str]:
    raw = path.read_bytes()
    if raw and not raw.endswith(b"\0"):
        raise ValueError("roster is not NUL terminated")
    result = [entry.decode("utf-8").removeprefix("./") for entry in raw.split(b"\0") if entry]
    if not result or len(result) != len(set(result)):
        raise ValueError("empty or duplicate roster")
    for entry in result:
        candidate = Path(entry)
        if candidate.is_absolute() or ".." in candidate.parts or candidate.suffix != ".gd":
            raise ValueError(f"invalid script path: {entry!r}")
    return result


def commit(root: Path) -> str | None:
    result = subprocess.run(["git", "-C", str(root), "rev-parse", "--verify", "HEAD"],
                            capture_output=True, text=True, check=False)
    return result.stdout.strip() if result.returncode == 0 else None


def digest(root: Path, scripts: list[str]) -> str:
    value = hashlib.sha256()
    for name in ["test.sh", *scripts]:
        data = (root / name).read_bytes()
        encoded = name.encode("utf-8")
        value.update(len(encoded).to_bytes(8, "big"))
        value.update(encoded)
        value.update(len(data).to_bytes(8, "big"))
        value.update(data)
    return value.hexdigest()


def begin(args: argparse.Namespace) -> None:
    if args.receipt.exists() or args.receipt.is_symlink():
        raise ValueError(f"receipt already exists; use a fresh output collection: {args.receipt}")
    roster = names(args.roster)
    expected = roster if args.phase == "parse" else roster[args.shard::args.shards]
    if not expected:
        raise ValueError("empty selected script roster")
    state = {"format": "openrc-phase-roster v1", "phase": args.phase,
             "source_commit": commit(args.app), "roster_source_sha256": digest(args.app, roster),
             "shard": args.shard, "shards": args.shards, "expected": expected,
             "full_roster": roster}
    args.state.write_text(json.dumps(state), encoding="utf-8")


def finish(args: argparse.Namespace) -> None:
    state = json.loads(args.state.read_text(encoding="utf-8"))
    roster, completed = names(args.roster), names(args.completed)
    if (roster != state["full_roster"] or completed != state["expected"]
            or digest(args.app, roster) != state["roster_source_sha256"]
            or commit(args.app) != state["source_commit"]):
        raise ValueError("phase roster, completed scripts, commit or source bytes changed")
    del state["full_roster"]
    state.update(completed=completed, complete=True)
    with args.receipt.open("x", encoding="utf-8") as output:
        json.dump(state, output, indent=2, sort_keys=True)
        output.write("\n")
    print(f"== {state['phase']} roster receipt: {args.receipt}")


def checkout_roster(app: Path, phase: str) -> list[str]:
    # Use the same shell glob and find as app/test.sh; parse paths use byte order.
    script = ("find . -name '*.gd' -not -path './.godot/*' "
              "-not -path './captures/*' -print0" if phase == "parse" else
              "for f in tests/test_*.gd; do printf '%s\\0' \"$f\"; done")
    result = subprocess.run(["bash", "-o", "pipefail", "-c", script], cwd=app,
                            capture_output=True, check=True)
    entries = [entry for entry in result.stdout.split(b"\0") if entry]
    if phase == "parse":
        entries.sort()
    return [entry.decode("utf-8").removeprefix("./") for entry in entries]


def validate_ci(app: Path, directory: Path) -> None:
    """Validate the eight unit shards and complete parse against this checkout."""
    head = commit(app)
    if not head:
        raise ValueError("checkout has no source commit")
    paths = list(directory.rglob("roster-*.json"))
    if len(paths) != 9:
        raise ValueError("expected exactly one parse and eight distinct unit roster receipts")
    receipts = {}
    keys = {"format", "phase", "source_commit", "roster_source_sha256", "shard", "shards",
            "expected", "completed", "complete"}
    for path in paths:
        if path.is_symlink() or path.stat().st_size > 4 * 1024 * 1024:
            raise ValueError(f"invalid roster receipt: {path}")
        item = json.loads(path.read_text(encoding="utf-8"))
        if (not isinstance(item, dict) or set(item) != keys or item["phase"] not in ("parse", "units")
                or type(item["shard"]) is not int):
            raise ValueError(f"invalid roster receipt: {path}")
        identity = (item["phase"], item["shard"])
        if identity in receipts:
            raise ValueError(f"duplicate roster receipt: {identity}")
        receipts[identity] = item
    parse = checkout_roster(app, "parse")
    units = checkout_roster(app, "units")
    if not parse or not units or len(set(parse)) != len(parse) or len(set(units)) != len(units):
        raise ValueError("checkout script roster is empty or duplicated")
    for phase, roster, count in (("parse", parse, 1), ("units", units, 8)):
        source_hash = digest(app, roster)
        for shard in range(count):
            identity = (phase, shard)
            item = receipts.get(identity)
            expected = roster if phase == "parse" else roster[shard::count]
            if (not isinstance(item, dict) or set(item) != keys or not expected
                    or item["format"] != "openrc-phase-roster v1" or item["phase"] != phase
                    or item["source_commit"] != head or item["roster_source_sha256"] != source_hash
                    or type(item["shard"]) is not int or item["shard"] != shard
                    or type(item["shards"]) is not int or item["shards"] != count
                    or item["expected"] != expected or item["completed"] != expected
                    or item["complete"] is not True):
                raise ValueError(f"incomplete or mismatched roster receipt: {identity}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    start = sub.add_parser("begin")
    start.add_argument("app", type=Path)
    start.add_argument("phase", choices=("parse", "units"))
    start.add_argument("roster", type=Path)
    start.add_argument("state", type=Path)
    start.add_argument("receipt", type=Path)
    start.add_argument("shard", type=int)
    start.add_argument("shards", type=int)
    end = sub.add_parser("finish")
    end.add_argument("app", type=Path)
    end.add_argument("roster", type=Path)
    end.add_argument("completed", type=Path)
    end.add_argument("state", type=Path)
    end.add_argument("receipt", type=Path)
    verify = sub.add_parser("verify-ci")
    verify.add_argument("--app", type=Path, required=True)
    verify.add_argument("--directory", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == "begin":
            if args.shards < 1 or args.shard < 0 or args.shard >= args.shards:
                raise ValueError("invalid shard")
            begin(args)
        elif args.command == "finish":
            finish(args)
        else:
            validate_ci(args.app, args.directory)
            print("Complete parse and eight unit shard rosters match this checkout.")
    except (OSError, UnicodeError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"phase roster refused: {error}\n")


if __name__ == "__main__":
    main()
