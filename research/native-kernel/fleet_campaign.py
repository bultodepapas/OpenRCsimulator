#!/usr/bin/env python3
"""Run and validate the full native fleet as independently checked per-aircraft shards.

The campaign is software-equivalence evidence, not physical validation or a performance test.
It uses the installed verified library and fails if any source, binary or engine changes.
"""
from __future__ import annotations

import argparse
import asyncio
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
from typing import Any

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RUNNER = HERE / "run.py"
FLEET = HERE / "fleet.gd"
CHECKED = ROOT / "tools/godot/run_checked.py"
DESCRIPTOR = ROOT / "app/native/kernel/openrc_native_kernel.gdextension"
RECEIPT = ROOT / "app/native/kernel/build-receipt.json"
MIN_WARMUP = 600
MIN_SAMPLES = 2400
MAX_JOBS = 4
KEY_FIELDS = ("aircraft", "vehicle", "battery", "case", "weather", "soft_hull")
HEX64 = re.compile(r"[0-9a-f]{64}\Z")


class CampaignError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise CampaignError(message)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def load_runner() -> Any:
    spec = importlib.util.spec_from_file_location("nk3_campaign_runner", RUNNER)
    if spec is None or spec.loader is None:
        raise CampaignError("cannot load the native oracle runner")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_build() -> Any:
    spec = importlib.util.spec_from_file_location("nk3_campaign_build", HERE / "build.py")
    if spec is None or spec.loader is None:
        raise CampaignError("cannot load the native build identity")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def snapshot() -> dict[str, Any]:
    """Pin the installed binary, source roster and declaration before and after all work."""
    runner = load_runner()
    build = load_build()
    receipt_data = json.loads(RECEIPT.read_text(encoding="utf-8"))
    receipt = receipt_data["platforms"]["linux"]
    binary = runner.selected_binary(DESCRIPTOR)
    require(binary.is_relative_to((ROOT / "app/native/kernel").resolve()), "installed binary path is invalid")
    references = {name: sha256(ROOT / name) for name in runner.reference_source_paths()}
    binary_hash = sha256(binary)
    require(receipt.get("mutant", False) is False and receipt.get("abi_version") == 2
            and receipt.get("backend") == "native" and receipt.get("platform") == "linux"
            and receipt.get("architecture") == "x86_64"
            and "-DNK_MUTATION=1" not in receipt.get("cxxflags_appended", []),
            "installed receipt is not a normal ABI 2 build")
    require(receipt.get("binary_sha256") == binary_hash, "installed binary differs from its receipt")
    require(receipt.get("reference_sources_sha256", receipt.get("mirrored_sources")) == references,
            "current reference sources differ from the installed receipt")
    require(receipt.get("builder_sha256") == sha256(HERE / "build.py"),
            "current builder differs from the installed receipt")
    engine_hash = sha256(runner.GODOT)
    require(receipt.get("engine_sha256") == engine_hash, "engine differs from the installed receipt")
    require(receipt.get("source_sha256") == build.source_digest()
            and receipt.get("lock_sha256") == sha256(build.locked.LOCK_PATH),
            "native source or toolchain lock differs from the installed receipt")
    return {
        "binary_sha256": binary_hash,
        "engine_sha256": engine_hash,
        "descriptor_sha256": sha256(DESCRIPTOR),
        "receipt_sha256": sha256(RECEIPT),
        "receipt": receipt,
        "reference_sources": references,
        "fleet_sha256": sha256(FLEET),
        "campaign_sha256": sha256(Path(__file__).resolve()),
    }


def write_manifest_script(path: Path, output: Path) -> None:
    # Query the actual declaration, including its explicit expected-refusal rows.
    # Do not reconstruct the catalog or preset matrix in Python.
    source = '''extends SceneTree

func _initialize() -> void:
    var script: Script = load(FLEET_PATH)
    if script == null:
        printerr("fleet declaration could not be loaded")
        quit(1)
        return
    var fleet: SceneTree = script.new()
    var rows: Array = fleet._fleet_declared_rows()
    var ids: Array[String] = []
    for row: Dictionary in rows:
        if str(row.aircraft) not in ids:
            ids.append(str(row.aircraft))
        if row.get("expected", "flight") == "reference-refusal":
            var reason := ""
            if row.vehicle == "rotorcraft" and row.case == "airborne":
                reason = "reset failed: Helicopter start refused: " + script.HELICOPTER_TRIM_REFUSAL
            elif row.vehicle == "rotorcraft" and row.case == "ground":
                reason = "reset failed: Ground trainer control reference refused: " + script.HELICOPTER_TRIM_REFUSAL
            elif row.vehicle == "fixed-wing":
                reason = script.STIK_RUNWAY_REFUSAL
            if reason.is_empty() or not script._fleet_expected_refusal(row,
                    {ok = false, phase = "reset", reason = reason}):
                printerr("refusal declaration lacks an exact source reason")
                fleet.free()
                quit(1)
                return
            row.expected_refusal_reason = reason
    var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
    if file == null:
        printerr("cannot write fleet manifest")
        fleet.free()
        quit(1)
        return
    file.store_string(JSON.stringify({format = "openrc-nk3-fleet-manifest v1", aircraft = ids, rows = rows}))
    file.close()
    fleet.free()
    print("NK3_FLEET_MANIFEST verdict=pass rows=", rows.size())
    quit()
'''
    path.write_text(source.replace("FLEET_PATH", json.dumps(str(FLEET)))
                    .replace("OUTPUT_PATH", json.dumps(str(output))), encoding="utf-8")


def make_manifest(out: Path) -> dict[str, Any]:
    script = out / "manifest.gd"
    output = out / "manifest.json"
    write_manifest_script(script, output)
    script_hash = sha256(script)
    runner = load_runner()
    command = [sys.executable, str(CHECKED), "--out-dir", str(out / "manifest-checks"),
               "--label", "nk3-fleet-manifest", "--timeout", "120",
               "--require-text", "NK3_FLEET_MANIFEST verdict=pass", "--",
               str(runner.GODOT), "--headless", "--path", str(ROOT / "app"), "--script", str(script)]
    completed = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, check=False)
    (out / "manifest-run.log").write_text(completed.stdout, encoding="utf-8")
    reports = list((out / "manifest-checks").glob("*/report.json"))
    require(completed.returncode == 0 and output.is_file() and len(reports) == 1 and sha256(script) == script_hash,
            "checked fleet manifest generation failed or its script changed")
    checked = json.loads(reports[0].read_text(encoding="utf-8"))
    log = Path(checked.get("log", ""))
    require(checked.get("ok") is True and checked.get("complete") is True and checked.get("reason") == "passed"
            and type(checked.get("process_exit")) is int and checked["process_exit"] == 0
            and type(checked.get("counts", {}).get("error")) is int and checked["counts"]["error"] == 0
            and checked.get("missing_required_text") == [] and log.is_file()
            and sha256(log) == checked.get("log_sha256"), "manifest checked-run evidence is invalid")
    return json.loads(output.read_text(encoding="utf-8"))


def positive_int(value: Any, minimum: int = 1) -> bool:
    return type(value) is int and value >= minimum


def hash_string(value: Any) -> bool:
    return isinstance(value, str) and HEX64.fullmatch(value) is not None


def row_key(row: dict[str, Any]) -> tuple[Any, ...]:
    require(isinstance(row, dict), "fleet row is not a dictionary")
    for key in KEY_FIELDS[:-1]:
        require(isinstance(row.get(key), str) and bool(row[key]), f"invalid fleet row field {key}")
    require(row["vehicle"] in ("fixed-wing", "rotorcraft"), "invalid vehicle family")
    require((row["vehicle"] == "fixed-wing" and type(row.get("soft_hull")) is bool)
            or (row["vehicle"] == "rotorcraft" and "soft_hull" in row and row["soft_hull"] is None),
            "invalid contact selection")
    require(type(row.get("default_battery")) is bool, "missing default battery selection")
    return tuple(row[key] for key in KEY_FIELDS)


def manifest_index(manifest: dict[str, Any]) -> tuple[dict[tuple[Any, ...], dict[str, Any]], list[str]]:
    require(isinstance(manifest, dict) and manifest.get("format") == "openrc-nk3-fleet-manifest v1",
            "invalid fleet manifest format")
    rows, aircraft = manifest.get("rows"), manifest.get("aircraft")
    require(isinstance(rows, list) and rows, "empty fleet manifest")
    require(isinstance(aircraft, list) and aircraft and all(isinstance(x, str) and x for x in aircraft)
            and len(set(aircraft)) == len(aircraft), "invalid manifest aircraft list")
    index: dict[tuple[Any, ...], dict[str, Any]] = {}
    encountered: list[str] = []
    for row in rows:
        key = row_key(row)
        require(key not in index, "duplicate manifest row")
        expected = row.get("expected", "flight")
        require(expected in ("flight", "reference-refusal"), "invalid manifest expectation")
        if expected == "reference-refusal":
            require(isinstance(row.get("expected_refusal_reason"), str) and bool(row["expected_refusal_reason"]),
                    "expected refusal has no exact reason")
        else:
            require("expected_refusal_reason" not in row, "flight row has a refusal reason")
        index[key] = row
        if row["aircraft"] not in encountered:
            encountered.append(row["aircraft"])
    require(aircraft == encountered, "manifest aircraft list does not match rows")
    return index, aircraft


def validate_components(report: dict[str, Any], flights: int, refusals: int) -> None:
    components = report.get("components")
    require(isinstance(components, dict) and components, "missing oracle comparisons")
    count = 0
    for name, component in components.items():
        require(isinstance(component, dict) and positive_int(component.get("count"))
                and type(component.get("identical")) is int and component["identical"] == component["count"],
                f"non-identical or incomplete oracle comparison {name}")
        count += component["count"]
    require(report.get("total") == {"compared": count, "identical": count, "mismatched": 0},
            "oracle comparison totals differ")
    for name, expected in (("fleet_pair", flights), ("fleet_reference_refusal", refusals)):
        require(components.get(name, {}).get("count", 0) == expected, f"wrong {name} comparison count")


def validate_flight(row: dict[str, Any], warmup: int, samples: int, guard: dict[str, Any]) -> None:
    ticks = warmup + samples
    require(row.get("status") == "pass" and row.get("reason") == ""
            and row.get("fingerprint_equal") is True, "flight row did not pass")
    reference, native = row.get("reference"), row.get("native")
    require(isinstance(reference, dict) and isinstance(native, dict), "missing flight backend results")
    for run, requested in ((reference, "gdscript_reference"), (native, "native")):
        identity, end = run.get("identity"), run.get("end")
        require(run.get("complete") is True and run.get("requested") == requested
                and run.get("actual") == requested and isinstance(identity, dict)
                and identity.get("backend") == requested and run.get("error") == ""
                and run.get("reason") == "", f"{requested} did not complete using its requested backend")
        require(type(run.get("warmup_completed")) is int and run["warmup_completed"] == warmup
                and type(run.get("samples_completed")) is int and run["samples_completed"] == samples
                and type(run.get("fingerprint_boundaries")) is int and run["fingerprint_boundaries"] == ticks + 1,
                f"{requested} has incomplete ticks")
        require(isinstance(end, dict) and type(end.get("tick")) is int and end["tick"] == ticks
                and end.get("fault") == "" and end.get("crashed") is False and end.get("paused") is False
                and end.get("held") is False, f"{requested} ended unhealthy")
        require(hash_string(run.get("fingerprint")) and hash_string(run.get("aircraft_sha256")),
                f"{requested} lacks typed-state or aircraft identity")
    require(reference["fingerprint"] == native["fingerprint"]
            and reference["aircraft_sha256"] == native["aircraft_sha256"], "backend flight identities differ")
    require(native["identity"].get("abi_version") == 2
            and native["identity"].get("binary_sha256") == guard["binary_sha256"]
            and native["identity"].get("source_sha256") == guard["receipt"].get("source_sha256")
            and native["identity"].get("lock_sha256") == guard["receipt"].get("lock_sha256"),
            "native flight identity differs from the installed receipt")
    require(native.get("native_covered_every_tick") is True
            and positive_int(native.get("context_calls"), ticks)
            and positive_int(native.get("stage_calls"), 4 * ticks)
            and native.get("stage_in_use") in ("stage", "body_loads"), "native tick coverage is incomplete")
    replay = min(8, ticks) if row["vehicle"] == "rotorcraft" else 0
    for run in (reference, native):
        require(type(run.get("replay_requested")) is int and run["replay_requested"] == replay,
                "wrong checkpoint replay length")
        if replay:
            require(run.get("replay_ok") is True and type(run.get("replay_completed")) is int
                    and run["replay_completed"] == replay, "checkpoint replay was incomplete")
    if replay:
        require(native.get("replay_native_covered") is True, "native checkpoint replay lacks coverage")


def validate_refusal(row: dict[str, Any], expected: dict[str, Any]) -> None:
    require(row.get("status") == "reference-refused" and row.get("fingerprint_equal") is False
            and row.get("reason") == expected["expected_refusal_reason"], "unexpected refusal status or reason")
    for name, requested in (("reference", "gdscript_reference"), ("native", "native")):
        run = row.get(name)
        require(isinstance(run, dict) and run.get("complete") is False and run.get("requested") == requested
                and run.get("phase") == "reset" and run.get("error") == expected["expected_refusal_reason"],
                f"{requested} did not produce the exact expected reset refusal")


def validate_reports(manifest: dict[str, Any], reports: dict[str, dict[str, Any]], guard: dict[str, Any],
                     warmup: int, samples: int) -> dict[str, int]:
    """Reject incomplete or inconsistent shards; callers must also verify files and snapshots."""
    require(positive_int(warmup) and positive_int(samples), "durations must be positive integers")
    expected, aircraft = manifest_index(manifest)
    require(isinstance(reports, dict) and set(reports) == set(aircraft), "missing or unexpected aircraft shard")
    seen: set[tuple[Any, ...]] = set()
    totals = {"declared": len(expected), "flight_passed": 0, "reference_refused": 0}
    baseline: dict[str, Any] | None = None
    for aircraft_id in aircraft:
        report = reports[aircraft_id]
        require(isinstance(report, dict) and report.get("format") == "openrc-nk3-fleet v2"
                and report.get("run_valid") is True and report.get("verdict") == "pass"
                and report.get("failures") == [] and report.get("self_test", {}).get("passed") is True,
                f"{aircraft_id}: oracle did not pass")
        checked = report.get("checked_run")
        require(isinstance(checked, dict) and checked.get("ok") is True and checked.get("complete") is True
                and checked.get("reason") == "passed" and type(checked.get("process_exit")) is int
                and checked["process_exit"] == 0 and type(checked.get("counts", {}).get("error")) is int
                and checked["counts"]["error"] == 0
                and checked.get("missing_required_text") == []
                and "NK3_ORACLE verdict=pass" in checked.get("required_text", []),
                f"{aircraft_id}: checked execution is incomplete")
        command = checked.get("command")
        require(isinstance(command, list) and all(isinstance(arg, str) for arg in command)
                and command.count("--extension=res://native/kernel/openrc_native_kernel.gdextension") == 1
                and command.count(f"--aircraft={aircraft_id}") == 1
                and command.count(f"--warmup={warmup}") == 1 and command.count(f"--samples={samples}") == 1
                and not any(arg.startswith("--weather=") or arg.startswith("--soft-hull=") for arg in command),
                f"{aircraft_id}: checked command was not the expected full shard")
        require(report.get("library", {}).get("ok") is True and report["library"].get("reason") == ""
                and report.get("identity", {}).get("backend") == "native"
                and report["identity"].get("abi_version") == 2, f"{aircraft_id}: native ABI 2 unavailable")
        require(report.get("build_receipt") == guard["receipt"]
                and report.get("binary_sha256_before") == guard["binary_sha256"]
                and report.get("binary_sha256_after") == guard["binary_sha256"]
                and report.get("engine_sha256_before") == guard["engine_sha256"]
                and report.get("engine_sha256_after") == guard["engine_sha256"]
                and report.get("reference_sources_before") == guard["reference_sources"]
                and report.get("reference_sources_after") == guard["reference_sources"],
                f"{aircraft_id}: source, binary or engine identity differs")
        sources, harness = report.get("sources"), report.get("harness_sources")
        required_harness = {"research/native-kernel/fleet.gd", "research/native-kernel/oracle.gd",
                            "research/native-kernel/trajectory.gd", "research/native-kernel/run.py",
                            "research/native-kernel/build.py", "tools/godot/run_checked.py",
                            "app/sim/native_stage.gd"}
        require(isinstance(sources, dict) and sources and report.get("sources_after") == sources
                and isinstance(harness, dict) and harness
                and required_harness.issubset(harness)
                and harness.get("research/native-kernel/fleet.gd") == guard["fleet_sha256"],
                f"{aircraft_id}: harness or source identity differs")
        current = {name: report.get(name) for name in ("engine", "seed", "identity", "law_identity", "sources", "harness_sources")}
        if baseline is None:
            baseline = current
        else:
            require(current == baseline, f"{aircraft_id}: shard identities differ")
        scope, rows = report.get("fleet_scope"), report.get("fleet")
        shard_keys = {key for key in expected if key[0] == aircraft_id}
        require(isinstance(scope, dict) and scope.get("scope") == "scoped"
                and scope.get("filters") == {"aircraft": aircraft_id, "weather": "", "soft_hull": ""}
                and scope.get("declared_aircraft") == aircraft and type(scope.get("declared_rows")) is int
                and scope["declared_rows"] == len(expected) and type(scope.get("selected_rows")) is int
                and scope["selected_rows"] == len(shard_keys) and scope.get("matrix_complete") is False
                and type(scope.get("warmup_requested")) is int and scope["warmup_requested"] == warmup
                and type(scope.get("samples_requested")) is int and scope["samples_requested"] == samples
                and type(scope.get("failed")) is int and scope["failed"] == 0
                and isinstance(rows, list) and len(rows) == len(shard_keys),
                f"{aircraft_id}: shard scope is incomplete or incorrect")
        flights = refusals = 0
        local: set[tuple[Any, ...]] = set()
        for row in rows:
            key = row_key(row)
            require(key in shard_keys and key not in local and key not in seen,
                    f"{aircraft_id}: duplicate or unexpected fleet row")
            declared = expected[key]
            require(row["default_battery"] == declared["default_battery"]
                    and row.get("expected", "flight") == declared.get("expected", "flight"),
                    f"{aircraft_id}: declared row metadata differs")
            if declared.get("expected", "flight") == "reference-refusal":
                validate_refusal(row, declared)
                refusals += 1
            else:
                validate_flight(row, warmup, samples, guard)
                flights += 1
            local.add(key)
            seen.add(key)
        require(local == shard_keys and type(scope.get("flight_passed")) is int and scope["flight_passed"] == flights
                and type(scope.get("reference_refused")) is int and scope["reference_refused"] == refusals,
                f"{aircraft_id}: incomplete row totals")
        validate_components(report, flights, refusals)
        totals["flight_passed"] += flights
        totals["reference_refused"] += refusals
    require(seen == set(expected), "aggregate does not cover the exact declared fleet")
    return totals


def validate_live_sources(report: dict[str, Any]) -> None:
    """Check every captured source path, not just agreement between report files."""
    for prefix, mapping in (("res://", report["sources"]), ("", report["harness_sources"])):
        for name, expected in mapping.items():
            require(isinstance(name, str) and name.startswith(prefix) and hash_string(expected), "invalid source entry")
            base = ROOT / "app" if prefix else ROOT
            path = (base / name.removeprefix(prefix)).resolve()
            require(path.is_relative_to(base.resolve()) and path.is_file() and sha256(path) == expected,
                    f"captured source no longer matches: {name}")


async def run_shard(aircraft: str, out: Path, semaphore: asyncio.Semaphore, warmup: int, samples: int,
                    timeout: int) -> tuple[str, Path]:
    async with semaphore:
        log_path = out / f"{aircraft}.log"
        command = [sys.executable, str(RUNNER), "--app-library", "--script", "fleet.gd",
                   "--option", f"aircraft={aircraft}", "--option", f"warmup={warmup}",
                   "--option", f"samples={samples}", "--timeout", str(timeout)]
        print(f"Starting fleet shard: {aircraft}", flush=True)
        with log_path.open("wb") as log:
            proc = await asyncio.create_subprocess_exec(*command, cwd=ROOT, stdout=log,
                                                        stderr=subprocess.STDOUT, start_new_session=True)
            try:
                code = await proc.wait()
            except asyncio.CancelledError:
                try:
                    # run_checked catches SIGINT and cleans its separately grouped Godot child.
                    os.killpg(proc.pid, signal.SIGINT)
                except ProcessLookupError:
                    pass
                try:
                    await asyncio.wait_for(proc.wait(), timeout=15)
                except asyncio.TimeoutError:
                    try:
                        os.killpg(proc.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    await proc.wait()
                raise
        text = log_path.read_text(encoding="utf-8", errors="replace")
        matches = re.findall(r"^verdict=(?:pass|fail) .* results=(\S+)$", text, flags=re.MULTILINE)
        require(code == 0 and len(matches) == 1, f"{aircraft}: shard failed; see {log_path}")
        result_path = (ROOT / matches[0]).resolve()
        require(result_path.is_relative_to((ROOT / "tmp/native-kernel").resolve()) and result_path.is_file(),
                f"{aircraft}: result path is invalid")
        print(f"Completed fleet shard: {aircraft}", flush=True)
        return aircraft, result_path


async def wait_reused_report(aircraft: str, path: Path, timeout: int) -> tuple[str, Path]:
    """Wait for run.py's final checked metadata; the Godot report is written before it."""
    deadline = asyncio.get_running_loop().time() + timeout
    print(f"Waiting for reused fleet shard: {aircraft}", flush=True)
    while asyncio.get_running_loop().time() < deadline:
        if path.is_file():
            try:
                result = json.loads(path.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, OSError):
                result = None  # run.py may be writing its final enriched report
            if isinstance(result, dict) and "run_valid" in result:
                require(result.get("run_valid") is True and result.get("verdict") == "pass",
                        f"{aircraft}: reused shard did not complete successfully: {path}")
                print(f"Collected reused fleet shard: {aircraft}", flush=True)
                return aircraft, path
        await asyncio.sleep(2)
    raise CampaignError(f"{aircraft}: timed out waiting for reused shard: {path}")


def drift_reason(guard: dict[str, Any]) -> str:
    """Explain changes even when snapshot rejects an installed receipt as stale."""
    try:
        current = snapshot()
    except (CampaignError, OSError, ValueError, KeyError, TypeError) as error:
        changed = []
        for name, digest in guard.get("reference_sources", {}).items():
            path = ROOT / name
            try:
                if not path.is_file() or sha256(path) != digest:
                    changed.append(name)
            except OSError:
                changed.append(name)
        detail = f"; changed mirrored sources: {', '.join(changed[:8])}" if changed else ""
        return f"frozen source/binary/engine snapshot is invalid: {error}{detail}"
    changed_fields = [name for name in guard if current.get(name) != guard[name]]
    if set(current) != set(guard):
        changed_fields.append("snapshot fields")
    return "frozen source/binary/engine snapshot changed: " + ", ".join(changed_fields) if changed_fields else ""


async def monitor_snapshot(guard: dict[str, Any], interval: float = 5.0) -> None:
    while True:
        await asyncio.sleep(interval)
        reason = drift_reason(guard)
        if reason:
            raise CampaignError(reason)


async def run_shards(aircraft: list[str], out: Path, jobs: int, warmup: int, samples: int,
                     timeout: int, reused: dict[str, Path] | None = None,
                     guard: dict[str, Any] | None = None, monitor_interval: float = 5.0) -> dict[str, Path]:
    semaphore = asyncio.Semaphore(jobs)
    reused = reused or {}
    tasks = [asyncio.create_task(wait_reused_report(name, reused[name], timeout) if name in reused
                                 else run_shard(name, out, semaphore, warmup, samples, timeout))
             for name in aircraft]
    collected = asyncio.gather(*tasks)
    monitor = asyncio.create_task(monitor_snapshot(guard, monitor_interval)) if guard is not None else None
    try:
        if monitor is not None:
            finished, _pending = await asyncio.wait((collected, monitor), return_when=asyncio.FIRST_COMPLETED)
            if monitor in finished:
                await monitor
        return dict(await collected)
    except BaseException:
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        await asyncio.gather(collected, return_exceptions=True)
        raise
    finally:
        if monitor is not None:
            monitor.cancel()
            await asyncio.gather(monitor, return_exceptions=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True, help="new evidence directory")
    parser.add_argument("--jobs", type=int, default=3, help="concurrent aircraft processes (1–4)")
    parser.add_argument("--warmup", type=int, default=MIN_WARMUP)
    parser.add_argument("--samples", type=int, default=MIN_SAMPLES)
    parser.add_argument("--timeout", type=int, default=21600, help="per-shard checked timeout in seconds")
    parser.add_argument("--reuse-report", action="append", default=[], metavar="AIRCRAFT=REPORT",
                        help="reuse a current full-aircraft run.py report, waiting if it is still running")
    args = parser.parse_args()
    if not 1 <= args.jobs <= MAX_JOBS or args.warmup < MIN_WARMUP or args.samples < MIN_SAMPLES or args.timeout <= 0:
        parser.error("jobs must be 1–4, warmup >= 600, samples >= 2400, and timeout positive")
    out = args.out.resolve()
    try:
        require(out.is_relative_to((ROOT / "tmp").resolve()), "evidence directory must be under tmp/")
        out.mkdir(parents=True, exist_ok=False)
        guard = snapshot()
        manifest = make_manifest(out)
        expected, aircraft = manifest_index(manifest)
        reused: dict[str, Path] = {}
        for item in args.reuse_report:
            name, separator, value = item.partition("=")
            require(bool(separator) and name in aircraft and name not in reused and bool(value),
                    "invalid or duplicate reused aircraft report")
            path = Path(value).resolve()
            require(path.is_relative_to((ROOT / "tmp/native-kernel").resolve()) and path.name.startswith("fleet-")
                    and path.suffix == ".json", "reused report must be a native-kernel fleet JSON")
            reused[name] = path
        manifest_hash = sha256(out / "manifest.json")
        manifest_script_hash = sha256(out / "manifest.gd")
        require(snapshot() == guard, "source, binary or engine changed during manifest generation")
        print(f"Declared fleet: {len(expected)} rows across {len(aircraft)} aircraft", flush=True)
        paths = asyncio.run(run_shards(aircraft, out, args.jobs, args.warmup, args.samples, args.timeout, reused, guard))
        report_hashes = {name: sha256(path) for name, path in paths.items()}
        reports = {name: json.loads(path.read_text(encoding="utf-8")) for name, path in paths.items()}
        totals = validate_reports(manifest, reports, guard, args.warmup, args.samples)
        for report in reports.values():
            validate_live_sources(report)
            checked = report["checked_run"]
            log = Path(checked["log"])
            require(log.is_file() and hash_string(checked.get("log_sha256"))
                    and sha256(log) == checked["log_sha256"]
                    and "NK3_ORACLE verdict=pass" in log.read_text(encoding="utf-8", errors="replace"),
                    "checked engine log is missing or changed")
        require(sha256(out / "manifest.json") == manifest_hash and sha256(out / "manifest.gd") == manifest_script_hash
                and all(sha256(paths[name]) == report_hashes[name] for name in aircraft),
                "manifest or report changed during validation")
        require(snapshot() == guard, "source, binary or engine changed during the campaign")
        result = {"format": "openrc-nk3-fleet-campaign v1", "verdict": "pass",
                  "scope": "full-declared-matrix", "warmup": args.warmup, "samples": args.samples,
                  "manifest_sha256": manifest_hash,
                  "manifest_script_sha256": manifest_script_hash, "guard": guard, "totals": totals,
                  "reports": {name: {"path": str(paths[name]), "sha256": report_hashes[name]}
                              for name in aircraft}}
        (out / "campaign.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"NK3_FLEET_CAMPAIGN verdict=pass rows={totals['declared']} flights={totals['flight_passed']} "
              f"reference_refused={totals['reference_refused']} evidence={out / 'campaign.json'}", flush=True)
        return 0
    except (CampaignError, OSError, ValueError, KeyError, TypeError) as error:
        print(f"NK3_FLEET_CAMPAIGN verdict=fail reason={error}", file=sys.stderr, flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
