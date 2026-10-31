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
import sys


FORMAT = "openrc-phase-roster v2"
PARSE_COVERAGE = ("full", "excluding-units")


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
    inputs = [("app/test.sh", root / "test.sh"), ("app/get-godot.sh", root / "get-godot.sh"),
              ("tools/ci/phase_roster.py", root.parent / "tools/ci/phase_roster.py"),
              ("tools/godot/run_checked.py", root.parent / "tools/godot/run_checked.py")]
    if "tests/test_fixed_gear_brake_input.gd" in scripts:
        inputs.append(("tools/godot/fixed_brake_legacy.py", root.parent / "tools/godot/fixed_brake_legacy.py"))
    inputs.extend(("app/" + name, root / name) for name in scripts)
    for name, path in inputs:
        data = path.read_bytes()
        encoded = name.encode("utf-8")
        value.update(len(encoded).to_bytes(8, "big"))
        value.update(encoded)
        value.update(len(data).to_bytes(8, "big"))
        value.update(data)
    return value.hexdigest()


def shard_selection(roster: list[str], phase: str, shard: int, shards: int) -> list[str]:
    if (type(shard) is not int or type(shards) is not int or shards < 1
            or shard < 0 or shard >= shards
            or phase == "parse" and (shard != 0 or shards != 1)):
        raise ValueError("invalid shard")
    return roster if phase == "parse" else roster[shard::shards]


def begin(args: argparse.Namespace) -> None:
    if args.receipt.exists() or args.receipt.is_symlink():
        raise ValueError(f"receipt already exists; use a fresh output collection: {args.receipt}")
    roster = names(args.roster)
    full_roster, selected = checkout_selection(args.app, args.phase, args.coverage)
    if roster != selected:
        raise ValueError("selected roster does not match checkout and coverage mode")
    expected = shard_selection(roster, args.phase, args.shard, args.shards)
    if not expected:
        raise ValueError("empty selected script roster")
    state = {"format": FORMAT, "phase": args.phase, "coverage": args.coverage,
             "source_commit": commit(args.app), "roster_source_sha256": digest(args.app, full_roster),
             "shard": args.shard, "shards": args.shards, "expected": expected,
             "full_roster": full_roster, "selected_roster": selected}
    args.state.write_text(json.dumps(state), encoding="utf-8")


def finish(args: argparse.Namespace) -> None:
    state = json.loads(args.state.read_text(encoding="utf-8"))
    roster, completed = names(args.roster), names(args.completed)
    if state["format"] != FORMAT or args.coverage != state["coverage"]:
        raise ValueError("phase receipt format or coverage mode changed")
    full_roster, selected = checkout_selection(args.app, state["phase"], args.coverage)
    expected = shard_selection(selected, state["phase"], state["shard"], state["shards"])
    if (full_roster != state["full_roster"] or selected != state["selected_roster"]
            or not expected or roster != selected or state["expected"] != expected or completed != expected
            or digest(args.app, full_roster) != state["roster_source_sha256"]
            or commit(args.app) != state["source_commit"]):
        raise ValueError("phase roster, completed scripts, commit or source bytes changed")
    del state["full_roster"]
    del state["selected_roster"]
    state.update(completed=completed, complete=True)
    with args.receipt.open("x", encoding="utf-8") as output:
        json.dump(state, output, indent=2, sort_keys=True)
        output.write("\n")
    print(f"== {state['phase']} roster receipt: {args.receipt}")


def checkout_roster(app: Path, phase: str) -> list[str]:
    # The runner and verifier both consume this find/glob; parse paths use byte order.
    script = ("find . -name '*.gd' -not -path './.godot/*' "
              "-not -path './captures/*' -print0" if phase == "parse" else
              "shopt -s nullglob; for f in tests/test_*.gd; do printf '%s\\0' \"$f\"; done")
    result = subprocess.run(["bash", "-o", "pipefail", "-c", script], cwd=app,
                            capture_output=True, check=True)
    entries = [entry for entry in result.stdout.split(b"\0") if entry]
    if phase == "parse":
        entries.sort()
    return [entry.decode("utf-8").removeprefix("./") for entry in entries]


def checkout_selection(app: Path, phase: str, coverage: str) -> tuple[list[str], list[str]]:
    if (phase == "parse" and coverage not in PARSE_COVERAGE
            or phase == "units" and coverage != "units"
            or phase not in ("parse", "units")):
        raise ValueError("invalid phase coverage mode")
    full = checkout_roster(app, phase)
    if not full or len(full) != len(set(full)):
        raise ValueError("checkout script roster is empty or duplicated")
    if coverage != "excluding-units":
        return full, full
    units = checkout_roster(app, "units")
    if not units or len(units) != len(set(units)) or not set(units) <= set(full):
        raise ValueError("unit roster is empty, duplicated or outside parse coverage")
    excluded = set(units)
    return full, [name for name in full if name not in excluded]


def validate_ci(app: Path, directory: Path) -> None:
    """Validate the parse and eight unit shards as one complete checkout coverage."""
    head = commit(app)
    if not head:
        raise ValueError("checkout has no source commit")
    paths = list(directory.rglob("roster-*.json"))
    if len(paths) != 9:
        raise ValueError("expected exactly one parse and eight distinct unit roster receipts")
    receipts = {}
    keys = {"format", "phase", "coverage", "source_commit", "roster_source_sha256", "shard", "shards",
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
    if (not parse or not units or len(set(parse)) != len(parse) or len(set(units)) != len(units)
            or not set(units) <= set(parse)):
        raise ValueError("checkout script roster is empty or duplicated")
    completed_units = []
    parsed = []
    unit_set = set(units)
    for phase, roster, count in (("parse", parse, 1), ("units", units, 8)):
        source_hash = digest(app, roster)
        for shard in range(count):
            identity = (phase, shard)
            item = receipts.get(identity)
            coverage = item.get("coverage") if isinstance(item, dict) else None
            if phase == "parse" and coverage == "excluding-units":
                expected = [name for name in parse if name not in unit_set]
            else:
                expected = roster if phase == "parse" else roster[shard::count]
            if (not isinstance(item, dict) or set(item) != keys or not expected
                    or item["format"] != FORMAT or item["phase"] != phase
                    or (coverage not in PARSE_COVERAGE if phase == "parse" else coverage != "units")
                    or item["source_commit"] != head or item["roster_source_sha256"] != source_hash
                    or type(item["shard"]) is not int or item["shard"] != shard
                    or type(item["shards"]) is not int or item["shards"] != count
                    or item["expected"] != expected or item["completed"] != expected
                    or item["complete"] is not True):
                raise ValueError(f"incomplete or mismatched roster receipt: {identity}")
            if phase == "parse":
                parsed.extend(expected)
            else:
                completed_units.extend(expected)
    if (len(completed_units) != len(units) or set(completed_units) != unit_set
            or set(parsed) | set(completed_units) != set(parse)):
        raise ValueError("parse and unit receipts do not cover the checkout exactly")


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
    start.add_argument("coverage", choices=(*PARSE_COVERAGE, "units"))
    end = sub.add_parser("finish")
    end.add_argument("app", type=Path)
    end.add_argument("roster", type=Path)
    end.add_argument("completed", type=Path)
    end.add_argument("state", type=Path)
    end.add_argument("receipt", type=Path)
    end.add_argument("coverage", choices=(*PARSE_COVERAGE, "units"))
    collect = sub.add_parser("collect")
    collect.add_argument("app", type=Path)
    collect.add_argument("phase", choices=("parse", "units"))
    collect.add_argument("coverage", choices=(*PARSE_COVERAGE, "units"))
    verify = sub.add_parser("verify-ci")
    verify.add_argument("--app", type=Path, required=True)
    verify.add_argument("--directory", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == "begin":
            begin(args)
        elif args.command == "finish":
            finish(args)
        elif args.command == "collect":
            _, selected = checkout_selection(args.app, args.phase, args.coverage)
            sys.stdout.buffer.write(b"".join(name.encode("utf-8") + b"\0" for name in selected))
        else:
            validate_ci(args.app, args.directory)
            print("Parse and eight unit shard rosters cover this checkout.")
    except (OSError, UnicodeError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"phase roster refused: {error}\n")


if __name__ == "__main__":
    main()
