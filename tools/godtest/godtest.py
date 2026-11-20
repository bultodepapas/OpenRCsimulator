#!/usr/bin/env python3
"""Run the actual OpenRC application through a versioned, bounded benchmark."""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import sys
import time
import uuid

import catalog
from analysis import compare, report
from runner import ROOT, run, write_json, read_json, check_frozen, file_hash
import runner


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    sub = result.add_subparsers(dest="command", required=True)
    sub.add_parser("list")
    for name in ("run", "all", "memory", "soak", "fleet", "matrix", "performance-tour"):
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
        command.add_argument("--rendering-method", choices=("auto", "forward_plus", "mobile", "gl_compatibility"))
        command.add_argument("--rendering-driver", choices=("auto", "vulkan", "metal", "d3d12", "opengl3"))
        command.add_argument("--window-mode", choices=("windowed", "borderless"))
        command.add_argument("--max-fps", type=int, choices=(0, 30, 60, 90, 120, 144, 165, 240))
        command.add_argument("--vsync-mode", choices=("enabled", "disabled"))
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


ORCHESTRATOR_INPUTS = ("godtest.py", "catalog.py", "analysis.py", "tour_report.py", "runner.py",
                       "frame_monitor.py", "hardware.py", "isolation.py")
OBSERVER_PATHS = tuple("tools/godtest/" + name for name in ORCHESTRATOR_INPUTS) + (
    "tools/godot/resource_samples.py", "tools/debug/frame_watch.py",
    "tools/debug/frame_capture.py", "tools/debug/debugctl.py", "tools/testqueue/processes.py")


def _observer_sources() -> dict:
    return {name: file_hash(ROOT / name) for name in OBSERVER_PATHS}


def _tour_success(result: dict) -> bool:
    cases = result.get("cases", [])
    return (bool(cases) and result.get("data") == "valid" and result.get("coverage") == "complete" and
            all(not case.get("rendered") or case.get("monitoring", {}).get("complete") is True for case in cases) and
            (not any(case.get("rendered") for case in cases) or result.get("performance") == "screen_only"))


def _case_success(result: dict) -> bool:
    monitoring = result.get("monitoring", {})
    return (result.get("data") == "valid" and result.get("coverage") == "complete" and
            (not result.get("rendered") or not monitoring.get("required") or monitoring.get("complete") is True))


def _pending_case(directory: Path, index: int, manifest: dict, *, state: str = "pending", attempts=None) -> dict:
    result = {"run_dir": str(directory / f"{index + 1:03d}-{manifest['id']}"),
              "scenario": manifest["id"], "aircraft": manifest["aircraft"], "state": state}
    if attempts:
        result["attempts"] = attempts
    return result


def _valid_host_identity(value: object) -> bool:
    if not isinstance(value, dict) or value.get("format") != "openrc-godtest-host-v1":
        return False
    for key in ("host_sha256", "boot_sha256"):
        digest = value.get(key)
        if not isinstance(digest, str) or len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
            return False
    return isinstance(value.get("scope"), str) and bool(value["scope"])


def _verified_retry_identity(path: Path, manifest: dict, observers: dict, current_host: dict) -> tuple[dict, str, dict]:
    """Admit only a stopped, source-bound attempt with the same observers and engine."""
    launch_receipt = path / "bridge/launch.json"
    execution_path = path / "execution.json"
    if not execution_path.is_file():
        handle = launch_receipt if launch_receipt.exists() else path
        raise ValueError(f"original attempt ownership/shutdown is unknown; reconcile the original handle before retrying: {handle}")
    execution = read_json(execution_path)
    original_host = execution.get("host_identity")
    if not _valid_host_identity(original_host) or original_host != current_host:
        raise ValueError(f"original host or boot identity is missing or differs; retry on the matching host and boot: {path}")
    launched = execution.get("launch", {})
    if launch_receipt.exists() or launched:
        shutdown = execution.get("shutdown", {})
        if not isinstance(launched, dict) or not isinstance(shutdown, dict) or shutdown.get("stopped") is not True:
            raise ValueError(f"original launched process has no verified shutdown; reconcile its original handle: {launch_receipt}")
        pid = launched.get("pid")
        if type(pid) is not int or shutdown.get("pid") != pid:
            raise ValueError(f"original launch and shutdown identities differ; reconcile its original handle: {launch_receipt}")
        if launch_receipt.exists():
            receipt = read_json(launch_receipt)
            if receipt.get("launcher_pid") != launched.get("launcher_pid") or receipt.get("port") != launched.get("port"):
                raise ValueError(f"original launcher identity differs; reconcile its original handle: {launch_receipt}")
    elif execution.get("state") not in ("failed", "timeout"):
        raise ValueError(f"original process ownership is unknown; reconcile the attempt before retrying: {path}")
    requested = read_json(path / "manifest.requested.json", 65536)
    resolved = read_json(path / "manifest.resolved.json", 65536)
    excluded = {"output_dir", "isolated_user_dir", "isolated_project_name"}
    if requested != manifest or {key: value for key, value in resolved.items() if key not in excluded} != manifest or Path(resolved.get("output_dir", "")).resolve() != path:
        raise ValueError(f"original attempt does not match its planned manifest: {path}")
    snapshot = read_json(path / "snapshot.json")
    for section, digest_name in (("files", "source_digest"), ("imports", "imported_digest")):
        values = snapshot.get(section)
        if not isinstance(values, dict) or not values or snapshot.get(digest_name) != hashlib.sha256(json.dumps(values, sort_keys=True).encode()).hexdigest():
            raise ValueError(f"original frozen {section} identity is unavailable: {path}")
    if check_frozen(snapshot):
        raise ValueError(f"original frozen source or imports changed: {path}")
    if execution.get("resource_sampling") is not True or execution.get("gpu_sampling") is not True:
        raise ValueError(f"original resource monitoring identity is incomplete: {path}")
    if (execution.get("resource_sampler_source_sha256") != observers["tools/godot/resource_samples.py"]
            or execution.get("resource_sampler_source_changed") is not False):
        raise ValueError(f"original CPU sampler source differs, changed or is unknown: {path}")
    orchestrator = execution.get("orchestrator_sources", {})
    if not isinstance(orchestrator, dict):
        raise ValueError(f"original orchestrator identity is invalid: {path}")
    for name in ORCHESTRATOR_INPUTS:
        if orchestrator.get(name) != observers["tools/godtest/" + name]:
            raise ValueError(f"original observer source differs or is unknown ({name}): {path}")
    watch_sources = execution.get("frame_watch", {}).get("source_sha256")
    if watch_sources is not None and (not isinstance(watch_sources, dict) or any(observers.get(key) != value for key, value in watch_sources.items())):
        raise ValueError(f"original frame-watch observer source differs: {path}")
    engines = execution.get("engine_files")
    if not isinstance(engines, dict) or not engines:
        raise ValueError(f"original engine identity is unavailable: {path}")
    for name, digest in engines.items():
        candidate = Path(name)
        if not candidate.is_absolute() or not candidate.is_file() or not isinstance(digest, str) or file_hash(candidate) != digest:
            raise ValueError(f"original engine executable is missing or changed: {name}")
    # The runner records the selected engine first, even when the bridge command
    # is wrapped by xvfb-run or a Windows console binary has a sibling GUI binary.
    engine = next(iter(engines))
    command = execution.get("command", [])
    if launched and (not isinstance(command, list) or not any(os.path.normcase(str(Path(str(arg)).resolve())) == os.path.normcase(str(Path(engine).resolve())) for arg in command)):
        raise ValueError(f"original engine does not match the launched command: {path}")
    return snapshot, engine, engines


def _resume_tour(args, previous: dict) -> int:
    from tour_report import _case_path, _planned, report_tour
    source = args.suite.resolve()
    problems = []
    planned = _planned(previous, problems)
    entries = previous.get("cases")
    if previous.get("format") != "openrc-godtest-suite-v1" or problems or not planned or not isinstance(entries, list) or len(entries) > len(planned):
        raise ValueError("resume requires a valid retained tour plan: " + "; ".join(problems))
    destination = args.out.resolve()
    destination.mkdir(parents=True, exist_ok=False)
    observers = previous.get("observer_sources")
    metadata = {"format": "openrc-godtest-suite-v1", "suite": "performance-tour-v1",
                "planned_cases": planned, "source_suite": str(source), "observer_sources": observers}
    # Retain every prior slot immediately, even if preflight or an early retry
    # fails. Same-slot source_suite provenance lets a later resume recover them.
    outcomes = [copy.deepcopy(entries[i]) if i < len(entries) else _pending_case(destination, i, item)
                for i, item in enumerate(planned)]

    def save(complete=False, error=None):
        value = {**metadata, "complete": complete, "cases": outcomes}
        if error: value["resume_error"] = error
        write_json(destination / "suite.json", value)

    save()
    try:
        if not isinstance(observers, dict) or observers != _observer_sources():
            raise ValueError("original resource/frame observer identity is missing or changed; a matching retained campaign is required")
        current_host = runner.campaign_host_identity()
        if not _valid_host_identity(current_host):
            raise ValueError("current host or boot identity is unavailable; refusing to resume")
        admitted, shared, engine, engines = [], None, None, None
        for index, manifest in enumerate(planned):
            entry = entries[index] if index < len(entries) else None
            if entry is not None and not isinstance(entry, dict):
                raise ValueError(f"invalid retained case slot {index + 1}")
            original = (_case_path(source, previous, index, planned, entry, {source}) if entry else
                        source / f"{index + 1:03d}-{manifest['id']}")
            if not original.exists():
                if entry and entry.get("state") == "starting":
                    raise ValueError(f"original attempt owner is unknown; reconcile the starting slot before retrying: {original}")
                if entry and entry.get("state") not in ("pending", None):
                    raise ValueError(f"retained case directory is missing: {original}")
                admitted.append((entry, None, None))
                continue
            snapshot, candidate_engine, candidate_engines = _verified_retry_identity(original, manifest, observers, current_host)
            if shared is None:
                shared, engine, engines = snapshot, candidate_engine, candidate_engines
            elif (snapshot["source_digest"], snapshot["imported_digest"], candidate_engine, candidate_engines) != (shared["source_digest"], shared["imported_digest"], engine, engines):
                raise ValueError(f"retained attempts do not share the same frozen source and engine: {original}")
            try:
                reduced = report(original, write=False)
            except (OSError, ValueError, TypeError, KeyError, AttributeError):
                reduced = None
            if reduced and (reduced.get("scenario") != manifest["id"] or reduced.get("aircraft") != manifest["aircraft"]):
                raise ValueError(f"retained case report differs from its planned aircraft: {original}")
            admitted.append((entry, original, reduced))
        if shared is None or engine is None:
            raise ValueError("no retained stopped attempt establishes both frozen source and matching engine identity; start a fresh campaign")
        for index, manifest in enumerate(planned):
            entry, original, reduced = admitted[index]
            attempts = list(entry.get("attempts", [])) if entry else []
            # External completed references must already occupy the same slot in
            # the source suite so the report can verify the provenance chain.
            if entry and reduced and _case_success(reduced):
                outcomes[index] = {key: reduced[key] for key in ("run_dir", "scenario", "aircraft", "execution", "data", "coverage", "flight", "performance", "issues")}
                outcomes[index].update(reused=True, attempts=attempts)
                save()
                continue
            if original is not None:
                attempt = {"run_dir": str(original)}
                if reduced:
                    attempt.update({key: reduced.get(key) for key in ("execution", "data", "coverage", "flight", "issues")})
                attempts.append(attempt)
            outcomes[index] = _pending_case(destination, index, manifest, state="starting", attempts=attempts)
            save()
            output = Path(outcomes[index]["run_dir"])
            print(f"Retrying or starting {index + 1}/{len(planned)}: {manifest['id']}", flush=True)
            path, _ = run(manifest, output, godot=engine, resources=True, snapshot=shared)
            current = report(path)
            outcomes[index] = {key: current[key] for key in ("run_dir", "scenario", "aircraft", "execution", "data", "coverage", "flight", "performance", "issues")}
            outcomes[index]["attempts"] = attempts
            save()
        save(complete=True)
        result = report_tour(destination)
        print(json.dumps({"suite": str(destination), "data": result["data"], "coverage": result["coverage"], "performance": result["performance"], "issues": result["issues"]}, indent=2))
        return 0 if _tour_success(result) else 1
    except BaseException as error:
        save(error=f"{type(error).__name__}: {error}")
        raise


def resume_suite(args) -> int:
    previous = read_json(args.suite.resolve() / "suite.json")
    if previous.get("suite") == "performance-tour-v1":
        return _resume_tour(args, previous)
    if previous.get("format") != "openrc-godtest-suite-v1" or not isinstance(previous.get("cases"), list) or not previous["cases"]:
        raise ValueError("resume requires a retained versioned suite index")
    destination = args.out.resolve()
    destination.mkdir(parents=True, exist_ok=False)
    outcomes = []
    metadata = {key: previous[key] for key in ("suite", "planned_cases") if key in previous}
    for index, entry in enumerate(previous["cases"]):
        original = Path(entry["run_dir"]).resolve()
        prior = report(original, write=False)
        attempts = list(entry.get("attempts", []))
        if prior["data"] == "valid" and prior["coverage"] == "complete":
            outcomes.append(dict(entry, reused=True))
            print(f"Keeping valid case: {prior['scenario']}", flush=True)
            continue
        manifest = read_json(original / "manifest.resolved.json", 65536)
        for key in ("output_dir", "isolated_user_dir", "isolated_project_name"):
            manifest.pop(key, None)
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
        outcome = {key: current[key] for key in ("run_dir", "scenario", "aircraft", "execution", "data", "coverage", "flight", "performance", "issues")}
        outcome["attempts"] = attempts
        outcomes.append(outcome)
        # Publish partial progress so an interrupted retry campaign is itself resumable.
        write_json(destination / "suite.json", {"format": "openrc-godtest-suite-v1", **metadata, "complete": False, "source_suite": str(args.suite.resolve()), "cases": outcomes + previous["cases"][index+1:]})
    write_json(destination / "suite.json", {"format": "openrc-godtest-suite-v1", **metadata, "complete": True, "source_suite": str(args.suite.resolve()), "cases": outcomes})
    print(json.dumps({"suite": str(destination), "cases": outcomes}, indent=2))
    return 0 if all(item["data"] == "valid" and item["coverage"] == "complete" for item in outcomes) else 1


def plan(args) -> list[dict]:
    overrides = {key: getattr(args, key) for key in ("aircraft", "time", "weather", "sky", "start", "landscape", "scene_detail", "camera", "entry", "seed", "cycles", "sample_s", "timeout_s", "phase_timeout_s", "headless", "rendering_method", "rendering_driver", "window_mode", "max_fps", "vsync_mode") if getattr(args, key) is not None}
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
    if args.command == "performance-tour" and args.phase:
        raise ValueError("performance-tour requires every circuit/menu phase; use run runway-menus --phase for diagnosis")
    if args.manifest:
        if args.command != "run": raise ValueError("--manifest belongs to run")
        item = catalog.load(args.manifest)
        item.update(overrides)
        cases = [item]
    elif args.command == "performance-tour":
        cases = catalog.performance_tour(overrides)
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
            print(json.dumps({"suite": "all-v1", "all": catalog.ALL_V1, "performance-tour-v1": list(catalog.TOUR_AIRCRAFT), "scenarios": catalog.SCENARIOS, "aircraft": catalog.AIRCRAFT, "limitations": ["experimental pilot; only stock Stik has a full landing profile", "source/debug only; native hardware qualification remains separate", "whole-flight comparison requires geometric qualification"]}, indent=2))
            return 0
        if args.command == "report":
            if (args.directory / "suite.json").is_file():
                suite = read_json(args.directory / "suite.json")
                if suite.get("suite") != "performance-tour-v1":
                    results = [report(Path(entry["run_dir"])) for entry in suite.get("cases", [])]
                    print(json.dumps({"suite": suite.get("suite"), "complete": suite.get("complete"), "cases": results}, indent=2))
                    return 0 if results and suite.get("complete") is True and all(item["data"] == "valid" and item["coverage"] == "complete" for item in results) else 1
                from tour_report import report_tour
                result = report_tour(args.directory)
                print(json.dumps({key: result[key] for key in ("run_dir", "suite", "data", "coverage", "performance", "issues")}, indent=2))
                return 0 if _tour_success(result) else 1
            result = report(args.directory)
            print(json.dumps({key: result[key] for key in ("run_dir", "execution", "data", "coverage", "flight", "performance", "issues")}, indent=2))
            return 0 if _case_success(result) else 1
        if args.command == "compare":
            result = compare(args.baseline, args.candidate, args.phase)
            if args.out:
                if args.out.exists(): raise ValueError("comparison output must be fresh")
                write_json(args.out, result)
            print(json.dumps(result, indent=2))
            return 0 if result["eligible"] else 1
        if args.command == "resume":
            sys.path.insert(0, str(ROOT))
            from tools.testqueue.common import enabled, inherited
            if enabled() and not inherited("rendered"):
                raise ValueError("resume is unsupported as a standalone command on an enrolled host; a source-bound resume adapter is not available")
            return resume_suite(args)
        cases = plan(args)
        if args.dry_run:
            print(json.dumps({"suite": "performance-tour-v1" if args.command == "performance-tour" else "all-v1" if args.command == "all" else args.command, "cases": cases, "max_wall_seconds": sum(item["timeout_s"]+80 for item in cases), "case_count": len(cases), "note": "bounds, not measured duration; fleet profiles and hardware gates remain explicit"}, indent=2))
            return 0
        sys.path.insert(0, str(ROOT))
        from tools.testqueue.common import enabled, inherited
        if enabled() and not inherited("rendered"):
            from tools.testqueue.integration import run as admitted_run
            return admitted_run("godtest", list(argv if argv is not None else sys.argv[1:]), ROOT)
        suite_dir = None
        if len(cases) > 1:
            suite_dir = (args.out or ROOT / "tmp/godtest" / f"suite-{args.command}-{time.strftime('%Y%m%d-%H%M%S')}-{uuid.uuid4().hex[:8]}").resolve()
            suite_dir.mkdir(parents=True, exist_ok=False)
        tour = args.command == "performance-tour"
        outcomes = [_pending_case(suite_dir, index, item) for index, item in enumerate(cases)] if tour else []
        suite_metadata = {"format": "openrc-godtest-suite-v1", "suite": "performance-tour-v1" if args.command == "performance-tour" else args.command, "planned_cases": cases}
        if tour:
            suite_metadata["observer_sources"] = _observer_sources()
        if suite_dir:
            write_json(suite_dir / "suite.json", {**suite_metadata, "complete": False, "cases": outcomes})
        shared_snapshot = read_json(args.snapshot) if args.snapshot else None
        for index, manifest in enumerate(cases):
            print(f"GOD TEST {index+1}/{len(cases)}: {manifest['id']}", flush=True)
            output = (suite_dir / f"{index+1:03d}-{manifest['id']}") if suite_dir else args.out
            if tour:
                outcomes[index]["state"] = "starting"
                write_json(suite_dir / "suite.json", {**suite_metadata, "complete": False, "cases": outcomes})
            try:
                path, execution = run(manifest, output, godot=args.godot, resources=args.resources, snapshot=shared_snapshot)
                if len(cases) > 1 and shared_snapshot is None:
                    shared_snapshot = read_json(path / "snapshot.json")
                result = report(path)
            except BaseException as error:
                if tour:
                    outcomes[index]["error"] = f"{type(error).__name__}: {error}"
                    write_json(suite_dir / "suite.json", {**suite_metadata, "complete": False, "cases": outcomes})
                raise
            item = {key: result[key] for key in ("run_dir", "scenario", "aircraft", "execution", "data", "coverage", "flight", "performance", "issues")}
            if tour: outcomes[index] = item
            else: outcomes.append(item)
            print(json.dumps(item, indent=2), flush=True)
            if suite_dir:
                write_json(suite_dir / "suite.json", {**suite_metadata, "complete": index + 1 == len(cases), "cases": outcomes})
        if suite_dir and args.command == "performance-tour":
            from tour_report import report_tour
            summary = report_tour(suite_dir)
            print(json.dumps({"report": str(suite_dir / "report.html"), "data": summary["data"], "coverage": summary["coverage"], "performance": summary["performance"], "issues": summary["issues"]}, indent=2))
            return 0 if _tour_success(summary) else 1
        return 0 if all(_case_success(report(Path(item["run_dir"]), write=False)) for item in outcomes) else 1
    except KeyboardInterrupt:
        print("godtest: interrupted; owned launch cleanup attempted; no subsequent suite cases started", file=sys.stderr)
        return 130
    except (OSError, ValueError, RuntimeError, KeyError, TypeError) as error:
        print(f"godtest: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
