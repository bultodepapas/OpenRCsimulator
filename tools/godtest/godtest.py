#!/usr/bin/env python3
"""Run the actual OpenRC application through a versioned, bounded benchmark."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import sys
import time
import uuid

import catalog
from analysis import compare, report
from runner import ROOT, run, write_json, read_json


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    sub = result.add_subparsers(dest="command", required=True)
    sub.add_parser("list")
    for name in ("run", "all", "memory", "soak", "fleet", "matrix"):
        command = sub.add_parser(name)
        if name == "run": command.add_argument("scenario", choices=sorted(catalog.SCENARIOS))
        command.add_argument("--manifest", type=Path)
        command.add_argument("--dry-run", action="store_true")
        command.add_argument("--headless", action="store_true", default=None)
        command.add_argument("--aircraft", choices=catalog.AIRCRAFT)
        command.add_argument("--time", choices=sorted(catalog.TIMES))
        command.add_argument("--weather", choices=sorted(catalog.WEATHER))
        command.add_argument("--sky", choices=sorted(catalog.SKIES))
        command.add_argument("--start", choices=("runway", "airborne", "hand_launch"))
        command.add_argument("--landscape", choices=("club_field", "green_paradise"))
        command.add_argument("--resolution", default=None, help="1920x1080 is primary")
        command.add_argument("--scene-detail", choices=("low", "medium", "high", "extreme"))
        command.add_argument("--camera", choices=("pilot", "chase", "flyby", "orbit", "closeup"))
        command.add_argument("--phase", choices=sorted(catalog.PHASES))
        command.add_argument("--entry", choices=("continuous", "isolated"))
        command.add_argument("--seed", type=int)
        command.add_argument("--cycles", type=int)
        command.add_argument("--sample-s", type=float)
        command.add_argument("--minutes", type=float)
        command.add_argument("--timeout-s", type=float)
        command.add_argument("--phase-timeout-s", type=float)
        command.add_argument("--repeats", type=int, default=1)
        command.add_argument("--resources", action="store_true")
        command.add_argument("--godot", help="native editor/debug executable")
        command.add_argument("--snapshot", type=Path, help="reuse a verified prior snapshot.json instead of copying another project")
        command.add_argument("--out", type=Path, help="fresh run directory; suite creates numbered children")
    command = sub.add_parser("report")
    command.add_argument("directory", type=Path)
    command = sub.add_parser("compare")
    command.add_argument("--baseline", type=Path, required=True)
    command.add_argument("--candidate", type=Path, required=True)
    command.add_argument("--phase", choices=sorted(catalog.PHASES))
    command.add_argument("--out", type=Path)
    command = sub.add_parser("resume", help="retry failed cases of a retained suite, keeping earlier attempts")
    command.add_argument("suite", type=Path)
    command.add_argument("--out", type=Path, required=True)
    return result


def resume_suite(args) -> int:
    previous = read_json(args.suite.resolve() / "suite.json")
    if previous.get("format") != "openrc-godtest-suite-v1" or not isinstance(previous.get("cases"), list) or not previous["cases"]:
        raise ValueError("resume requires a retained versioned suite index")
    destination = args.out.resolve()
    destination.mkdir(parents=True, exist_ok=False)
    outcomes = []
    for index, entry in enumerate(previous["cases"]):
        original = Path(entry["run_dir"]).resolve()
        prior = report(original, write=False)
        attempts = list(entry.get("attempts", []))
        if prior["data"] == "valid" and prior["coverage"] == "complete":
            outcomes.append(dict(entry, reused=True))
            print(f"Keeping valid case: {prior['scenario']}", flush=True)
            continue
        manifest = read_json(original / "manifest.resolved.json", 65536)
        manifest.pop("output_dir", None)
        catalog.validate(manifest)
        if manifest["id"] != entry["scenario"]:
            raise ValueError("suite entry differs from its requested scenario")
        execution = read_json(original / "execution.json")
        command = execution.get("command", [])
        if not command or not Path(command[0]).is_file():
            raise ValueError("matching prior engine executable is unavailable")
        snapshot = read_json(original / "snapshot.json")
        print(f"Retrying {index+1}/{len(previous['cases'])}: {manifest['id']}", flush=True)
        output = destination / f"{index+1:03d}-{manifest['id']}"
        path, _ = run(manifest, output, godot=command[0], resources=bool(execution.get("resource_sampling", (original / "resources.json").exists())), snapshot=snapshot)
        current = report(path)
        attempts.append({key: entry.get(key) for key in ("run_dir", "execution", "data", "coverage", "flight", "issues")})
        outcome = {key: current[key] for key in ("run_dir", "scenario", "execution", "data", "coverage", "flight", "performance", "issues")}
        outcome["attempts"] = attempts
        outcomes.append(outcome)
        # Publish partial progress so an interrupted retry campaign is itself resumable.
        write_json(destination / "suite.json", {"format": "openrc-godtest-suite-v1", "complete": False, "source_suite": str(args.suite.resolve()), "cases": outcomes + previous["cases"][index+1:]})
    write_json(destination / "suite.json", {"format": "openrc-godtest-suite-v1", "complete": True, "source_suite": str(args.suite.resolve()), "cases": outcomes})
    print(json.dumps({"suite": str(destination), "cases": outcomes}, indent=2))
    return 0 if all(item["data"] == "valid" and item["coverage"] == "complete" for item in outcomes) else 1


def plan(args) -> list[dict]:
    overrides = {key: getattr(args, key) for key in ("aircraft", "time", "weather", "sky", "start", "landscape", "scene_detail", "camera", "entry", "seed", "cycles", "sample_s", "timeout_s", "phase_timeout_s", "headless") if getattr(args, key) is not None}
    if args.resolution:
        try:
            overrides["resolution"] = [int(n) for n in args.resolution.lower().split("x")]
        except ValueError as error:
            raise ValueError("resolution must look like 1920x1080") from error
    if args.minutes is not None:
        if args.command != "soak": raise ValueError("--minutes belongs to soak")
        overrides.update(sample_s=args.minutes*60, timeout_s=args.minutes*60+300, phase_timeout_s=args.minutes*60+120)
    if args.phase and args.entry == "isolated":
        overrides["phases"] = [args.phase]
        if args.phase not in ("startup", "home", "selection", "loading"):
            overrides["start"] = "airborne"
    if args.manifest:
        if args.command != "run": raise ValueError("--manifest belongs to run")
        item = catalog.load(args.manifest)
        item.update(overrides)
        cases = [item]
    elif args.command == "matrix":
        cases = catalog.matrix(overrides)
    elif args.command == "fleet":
        cases = []
        for aircraft in catalog.AIRCRAFT:
            item = catalog.scenario("jet-circuit", {**overrides, "aircraft": aircraft})
            item["id"] = f"fleet-{aircraft}"
            cases.append(item)
    else:
        names = catalog.ALL_V1 if args.command == "all" else [args.scenario if args.command == "run" else args.command]
        cases = [catalog.scenario(name, overrides) for name in names]
    if args.phase:
        for item in cases:
            if args.entry == "isolated":
                item["phases"] = [args.phase]
                if args.phase not in ("startup", "home", "selection", "loading"): item["start"] = "airborne"
            elif args.phase in item["phases"]:
                item["phases"] = item["phases"][:item["phases"].index(args.phase)+1] + ["home", "shutdown"]
            else:
                raise ValueError(f"phase {args.phase} is not on scenario {item['id']}")
    if not 1 <= args.repeats <= 20: raise ValueError("repeats must be in 1..20")
    expanded = [dict(item) for _ in range(args.repeats) for item in cases]
    for item in expanded: catalog.validate(item)
    return expanded


def main(argv=None) -> int:
    args = parser().parse_args(argv)
    try:
        if args.command == "list":
            print(json.dumps({"suite": "all-v1", "all": catalog.ALL_V1, "scenarios": catalog.SCENARIOS, "aircraft": catalog.AIRCRAFT, "limitations": ["experimental pilot; only stock Stik has a full landing profile", "release/Mac adapters pending", "whole-flight comparison requires geometric qualification"]}, indent=2))
            return 0
        if args.command == "report":
            result = report(args.directory)
            print(json.dumps({key: result[key] for key in ("run_dir", "execution", "data", "coverage", "flight", "performance", "issues")}, indent=2))
            return 0 if result["data"] == "valid" and result["coverage"] == "complete" else 1
        if args.command == "compare":
            result = compare(args.baseline, args.candidate, args.phase)
            if args.out:
                if args.out.exists(): raise ValueError("comparison output must be fresh")
                write_json(args.out, result)
            print(json.dumps(result, indent=2))
            return 0 if result["eligible"] else 1
        if args.command == "resume":
            return resume_suite(args)
        cases = plan(args)
        if args.dry_run:
            print(json.dumps({"suite": "all-v1" if args.command == "all" else args.command, "cases": cases, "max_wall_seconds": sum(item["timeout_s"]+80 for item in cases), "case_count": len(cases), "note": "bounds, not measured duration; fleet profiles and hardware gates remain explicit"}, indent=2))
            return 0
        suite_dir = None
        if len(cases) > 1:
            suite_dir = (args.out or ROOT / "tmp/godtest" / f"suite-{args.command}-{time.strftime('%Y%m%d-%H%M%S')}-{uuid.uuid4().hex[:8]}").resolve()
            suite_dir.mkdir(parents=True, exist_ok=False)
        outcomes = []
        shared_snapshot = read_json(args.snapshot) if args.snapshot else None
        for index, manifest in enumerate(cases):
            print(f"GOD TEST {index+1}/{len(cases)}: {manifest['id']}", flush=True)
            output = (suite_dir / f"{index+1:03d}-{manifest['id']}") if suite_dir else args.out
            path, execution = run(manifest, output, godot=args.godot, resources=args.resources, snapshot=shared_snapshot)
            if len(cases) > 1 and shared_snapshot is None:
                shared_snapshot = read_json(path / "snapshot.json")
            result = report(path)
            outcomes.append({key: result[key] for key in ("run_dir", "scenario", "execution", "data", "coverage", "flight", "performance", "issues")})
            print(json.dumps(outcomes[-1], indent=2), flush=True)
        if suite_dir:
            write_json(suite_dir / "suite.json", {"format": "openrc-godtest-suite-v1", "complete": len(outcomes) == len(cases), "cases": outcomes})
        return 0 if all(item["data"] == "valid" and item["coverage"] == "complete" for item in outcomes) else 1
    except KeyboardInterrupt:
        print("godtest: interrupted; owned launch cleanup attempted; no subsequent suite cases started", file=sys.stderr)
        return 130
    except (OSError, ValueError, RuntimeError, KeyError, TypeError) as error:
        print(f"godtest: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
