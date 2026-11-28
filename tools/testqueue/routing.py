"""Reviewed routing registry for checked scripts (TQ-07-D2).

``routing.json`` says, once and in review, which operating systems a checked
script may run on, which completion markers prove it finished and how long it
needs. When an agent omits ``platform`` (and ``require``/``timeout``), the MCP
uses the entry, so a portable script runs on whichever listed OS has a free host
(TQ-07-D3). A script without an entry keeps the caller's OS.

An entry claims only operating systems where the pool recorded a pass. History
may suggest entries (``--suggest``); a person reviews and commits them.

    python tools/testqueue/routing.py --check      # format, scripts exist
    python tools/testqueue/routing.py --suggest    # candidates from the pool's receipts
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import json
import math
from pathlib import Path
import sys

REPO = Path(__file__).resolve().parents[2]
REGISTRY = Path(__file__).resolve().parent / "routing.json"
FORMAT = "openrc-test-routing v1"
OPERATING_SYSTEMS = ("windows", "linux", "darwin")
HOST_OS = {"windows": "windows", "linux": "linux", "primis": "linux", "angel": "darwin", "angela": "darwin"}


def load(path=REGISTRY):
    """Validated entries by script; an unreadable registry is an error, never a silent default."""
    value = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(value, dict) or value.get("format") != FORMAT or not isinstance(value.get("entries"), list):
        raise ValueError(f"routing registry must be {FORMAT} with an entries list")
    entries = {}
    for entry in value["entries"]:
        problems = entry_problems(entry)
        if problems:
            raise ValueError(f"routing entry {entry.get('script') if isinstance(entry, dict) else entry!r}: " + "; ".join(problems))
        if entry["script"] in entries:
            raise ValueError("duplicate routing entry " + entry["script"])
        entries[entry["script"]] = entry
    return entries


def entry_problems(entry):
    problems = []
    if not isinstance(entry, dict) or set(entry) - {"script", "os", "require", "timeout", "evidence"}:
        return ["unknown or missing fields"]
    script = entry.get("script")
    if not isinstance(script, str) or not script.startswith("res://tests/") or not script.endswith(".gd"):
        problems.append("script must be a res://tests/*.gd path")
    systems = entry.get("os")
    if (not isinstance(systems, list) or not systems or len(set(systems)) != len(systems)
            or any(item not in OPERATING_SYSTEMS for item in systems)):
        problems.append("os must list distinct windows/linux/darwin")
    markers = entry.get("require", [])
    if not isinstance(markers, list) or any(not isinstance(item, str) or not item for item in markers):
        problems.append("require must be a list of nonempty strings")
    timeout = entry.get("timeout", 90)
    if type(timeout) not in (int, float) or not math.isfinite(timeout) or not 1 <= timeout <= 21600:
        problems.append("timeout must be 1..21600 seconds")
    if not isinstance(entry.get("evidence"), str) or not entry["evidence"]:
        problems.append("evidence must say why the listed OSes are claimed")
    return problems


def lookup(script, path=REGISTRY):
    try:
        return load(path).get(script)
    except (OSError, ValueError):
        return None  # a broken registry routes nothing; --check reports it


def platform_of(entry):
    systems = sorted(entry["os"])
    return "any" if len(systems) == len(OPERATING_SYSTEMS) else systems[0] if len(systems) == 1 else systems


def check(path=REGISTRY, repo=REPO):
    """CI-friendly: the registry parses and each script exists in the checkout."""
    errors = []
    try:
        entries = load(path)
    except (OSError, ValueError) as error:
        return [str(error)]
    for script in entries:
        if not (Path(repo) / "app" / script[len("res://"):]).is_file():
            errors.append(f"{script}: no such script in app/")
    return errors


def suggest(pool_root):
    """Candidates from the pool's receipts: scripts that passed on two or more OSes."""
    passes, failures = defaultdict(set), defaultdict(set)
    markers, timeouts = defaultdict(Counter), defaultdict(list)
    for path in Path(pool_root, "jobs").glob("*.json"):
        try:
            receipt = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        last, inputs = receipt.get("last_status") or {}, receipt.get("inputs") or {}
        script, system = inputs.get("script"), HOST_OS.get(receipt.get("host"))
        if not script or not system or last.get("state") != "FINISHED":
            continue
        if last.get("outcome") == "PASSED":
            passes[script].add(system)
            markers[script][json.dumps(inputs.get("require") or [])] += 1
            if type(inputs.get("timeout")) in (int, float):
                timeouts[script].append(inputs["timeout"])
        elif last.get("outcome") == "TEST_FAILED":
            failures[script].add(system)
    suggested = []
    for script, systems in sorted(passes.items()):
        if len(systems) < 2:
            continue
        suggested.append({"script": script, "os": sorted(systems),
                          "require": json.loads(markers[script].most_common(1)[0][0]),
                          "timeout": max([90, *timeouts[script]]),
                          "evidence": "pool passes on " + ", ".join(sorted(systems))
                                      + (("; test failures also on " + ", ".join(sorted(failures[script])))
                                         if failures.get(script) else "")})
    return suggested


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--suggest", action="store_true")
    parser.add_argument("--pool-root", type=Path, default=Path("C:/ProgramData/OpenRC/testpool"))
    args = parser.parse_args(argv)
    if args.suggest:
        print(json.dumps(suggest(args.pool_root), indent=2))
        return 0
    errors = check()
    for error in errors:
        print("routing:", error, file=sys.stderr)
    print(f"routing registry: {len(load()) if not errors else 0} entries, {len(errors)} problems")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
