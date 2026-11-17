"""Retain and independently verify the registered Windows servo-arrival campaign.

Consumes a checked-pool batch and its frozen snapshot. A partial collection never
establishes the 68-cell gate. Native Mac collection retains its separate SSH path.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import struct
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools/flight_log"))
import flight_log

LAW = "normalized-slew-arrivals-v1"
PROTOCOL = "joint-interval-local-v1"
CAMPAIGN = "ac12-normalized-slew-arrivals-local-v1-20261116"
CASE_MAP_CAMPAIGN = "ac12-normalized-slew-arrivals-v1-20261116"
LEGACY_MAP_SHA256 = "5ee4b31e617ba4fb35cefa41eed03a256fb9631e624717c9ff92cef3933a2f9a"
CASE_MAP_SHA256 = "f1217baebde255a9b5d9516a1e70b9118ce048643a24639b7e0a73d3ce9edc86"
SNAPSHOT_MANIFEST_SHA256 = "0b5f1cd35e64307b1285774665a09e57322f948b2b9b6c1ef6a4e1f2362c6258"
HISTORICAL_INPUTS = {
    "res://tools/ac12/variants.gd": "be780aa316d9a1799983f53ee3f577846b88d3f29f43faeef697f900a5361cd5",
    "res://data/creator/airframe-conventional-trainer-estimated-v1.json": "00cd592b2e53bd06f544f996bf1845023017f9ed7761c36529be2c92a2113887",
    "res://data/creator/power-electric-4s-800kv-apc12x6-estimated-v1.json": "8037b63011d6899964fa9ac582fb46b14ea95c22e20bf947365d5e9eeec9bfb7",
}
TAPES = ("pitch_doublet", "roll_doublet", "rudder_kick", "throttle_step")
CELLS = {f"C{n:02d}-{tape}" for n in range(1, 18) for tape in TAPES}
TOLERANCES = dict(position_m=.10, attitude_deg=.5, rates_dps=2., airspeed_mps=.05,
                  rotor_rpm=20., current_a=.2, charge_fraction=.002)
FLOORS = dict(position_m=1e-7, attitude_deg=1e-7, rates_dps=1e-6, airspeed_mps=1e-8,
              rotor_rpm=1e-5, current_a=1e-7, charge_fraction=1e-10)
ENGINE_HASHES = {
    "1a470886fc810b81a61e01bad7678e38989f1c94cf8e9733bfd1026224b3f42b",
    "9d735a72c1a06bf42379829257b0bf966a6cf0ea507c6d8efa051bcfc8faccf2",
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def sha(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(value, dict), f"expected object: {path}")
    return value


def differences(left: list[tuple], right: list[tuple]) -> dict[str, float]:
    require(len(left) == len(right) == 1440, "incomplete sample rows")
    result = dict.fromkeys(TOLERANCES, 0.0)
    for a, b in zip(left, right, strict=True):
        result["position_m"] = max(result["position_m"], math.dist(a[:3], b[:3]))
        result["rates_dps"] = max(result["rates_dps"], math.degrees(math.dist(a[10:13], b[10:13])))
        # Independent normalized quaternion chord angle, stable near equal attitudes.
        qa = [v / math.hypot(*a[6:10]) for v in a[6:10]]
        qb = [v / math.hypot(*b[6:10]) for v in b[6:10]]
        sign = 1 if sum(x * y for x, y in zip(qa, qb)) >= 0 else -1
        angle = 4 * math.atan2(math.hypot(*(x - sign*y for x, y in zip(qa, qb))),
                               math.hypot(*(x + sign*y for x, y in zip(qa, qb))))
        result["attitude_deg"] = max(result["attitude_deg"], math.degrees(angle))
        for key, index in (("airspeed_mps", 13), ("rotor_rpm", 14), ("current_a", 15)):
            result[key] = max(result[key], abs(a[index] - b[index]))
    result["charge_fraction"] = abs(left[-1][16] - right[-1][16]) / max(abs(right[-1][16]), 1e-9)
    require(all(math.isfinite(v) for v in result.values()), "nonfinite recomputed metric")
    return result


def checked_receipt(row: dict, manifest: dict) -> tuple[str, str]:
    checked = row.get("collection", {})
    require(checked.get("complete") is True and checked.get("pool_outcome") == "PASSED"
            and checked.get("ok") is True and checked.get("counts") == {"error": 0, "warning": 0},
            "missing complete checked pass")
    checked_path = Path(checked["report"])
    require(read(checked_path) == checked, "collected report differs from batch receipt")
    original_path = checked_path.parent / "original-report.json"
    original = read(original_path)
    status = row["status"]
    require(original == status.get("runner_verdict", {}).get("checked"), "native checked receipt disagrees")
    require(checked.get("pool_job") == status.get("job") == status.get("request_id") == row["request_id"],
            "checked attempt IDs disagree")
    require(original.get("ok") is True and original.get("complete") is True
            and original.get("counts") == {"error": 0, "warning": 0}, "native checked pass missing")
    command = original.get("command", [])
    require(command.count("--script") == 1 and command[command.index("--script")+1] == row["input"]["script"],
            "checked command and requested selector disagree")
    require(command == checked.get("command"), "collected command differs from native receipt")
    require(status.get("cleanup") == "CONFIRMED" and status.get("evidence") == "COMPLETE",
            "unfinished cleanup/evidence")
    attempt = Path(status["output"]).resolve()
    require(command.count("--path") == 1
            and Path(command[command.index("--path")+1]).resolve() == attempt / "source/app"
            and Path(original["cwd"]).resolve() == attempt / "source", "checked project/cwd differs from isolated attempt")
    native_report = Path(original["report"])
    require(read(native_report) == original, "native report contents differ from the normalized pool copy")
    raw_copy = checked_path.parent / "native-report.json"
    if raw_copy.exists():
        require(sha(raw_copy) == sha(native_report), "retained native report differs")
    else:
        shutil.copy2(native_report, raw_copy)
    for source, retained in ((original["log"], Path(checked["log"])), (original["report"], raw_copy)):
        relative = Path(source).resolve().relative_to(attempt).as_posix()
        require(sha(retained) == status["artifacts"].get(relative), "checked artifact differs from attempt inventory")
    require(sha(Path(checked["log"])) == original["log_sha256"] == checked["log_sha256"], "checked log was replaced")
    attempt_manifest = attempt / "manifest.json"
    require(sha(attempt_manifest) == status["artifacts"].get("manifest.json") and read(attempt_manifest) == manifest,
            "attempt used a different frozen input manifest")
    return Path(checked["log"]).read_text(encoding="utf-8"), sha(checked_path)


def retain(row: dict, folder: Path, report_path: str, emitted_sha: str) -> dict:
    status = row["status"]
    source = Path(report_path.strip()).resolve().parent
    require(source.is_relative_to(Path(status["output"]).resolve() / "profile"),
            "audit output is outside the owned attempt profile")
    files = {p.name: sha(p) for p in source.iterdir() if p.is_file()}
    require(files.get("audit.json") == emitted_sha, "audit hash differs from checked log")
    expected = {"audit.json", "definition.json", "aircraft-record.json", "baseline-240.orfl",
                "baseline.csv", "baseline-replay.json", "samples-240-0.f64le", "samples-480-1.f64le", "samples-960-2.f64le"}
    require(expected <= set(files), "current attempt is missing required scientific artifacts")
    folder.mkdir(parents=True, exist_ok=True)
    for name, digest in files.items():
        target = folder / name
        if target.exists():
            require(sha(target) == digest, f"refusing to overwrite different retained artifact: {target}")
        else:
            shutil.copy2(source / name, target)
        require(sha(target) == digest, f"retained artifact mismatch: {name}")
    require(files == {p.name: sha(p) for p in source.iterdir() if p.is_file()}, "source artifacts changed during retention")
    (folder / "retrieval-sha256.json").write_text(json.dumps(files, indent=2), encoding="utf-8")
    return read(folder / "audit.json")


def gate(key: str, e1: float, e2: float) -> tuple[bool, bool, float, bool]:
    floor = e1 <= FLOORS[key]
    ratio = 0.0 if floor else e2/e1
    converges = floor or ratio <= .75
    error = e1 if floor else (e1/(1-ratio) if ratio < 1 else math.inf)
    return floor, converges, error, converges and error <= TOLERANCES[key]


def unambiguous_gate(key: str, reported: tuple[float, float], independent: tuple[float, float]) -> bool:
    expected = gate(key, *reported)
    actual = gate(key, *independent)
    require(expected[:2] == actual[:2] and expected[3] == actual[3], f"independent admission differs: {key}")
    bounds = []
    for a, b in zip(reported, independent, strict=True):
        epsilon = max(1e-9 if key == "attitude_deg" else 1e-11, 1e-10*max(abs(a), abs(b)))
        bounds.append((max(0., min(a, b)-epsilon), max(a, b)+epsilon))
    (lo1, hi1), (lo2, hi2) = bounds
    require(not (lo1 <= FLOORS[key] < hi1), f"ambiguous floor comparison: {key}")
    if expected[0]:
        require(not (lo1 <= TOLERANCES[key] < hi1), f"ambiguous tolerance comparison: {key}")
    else:
        low_ratio, high_ratio = lo2/hi1, hi2/lo1
        require(not (low_ratio <= .75 < high_ratio), f"ambiguous convergence ratio: {key}")
        low_error = lo1/(1-low_ratio) if low_ratio < 1 else math.inf
        high_error = hi1/(1-high_ratio) if high_ratio < 1 else math.inf
        require(not (low_error <= TOLERANCES[key] < high_error), f"ambiguous tolerance comparison: {key}")
    return expected[3]


def verify_csv(path: Path, samples: list[tuple], replay: dict, initial_frame: dict) -> None:
    flight_log._check_exported_csv(path, replay)
    fields = ("north_m", "east_m", "down_m", "u_mps", "v_mps", "w_mps", "qw", "qx", "qy", "qz",
              "p_radps", "q_radps", "r_radps", "tas_mps", "engine_rpm")
    with path.open(encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream)
        rows = list(reader)
    require(len(rows) == 1441, "CSV does not contain the full baseline")
    for tick, row in enumerate(rows):
        require(float(row["tick"]) == tick and abs(float(row["t_s"])-tick/240.) <= 1e-10, "CSV clock/ticks are incomplete")
        require(all(math.isfinite(float(value)) for value in row.values()), "CSV has nonfinite values")
        if tick:
            for key, expected in zip(fields, samples[tick-1][:15], strict=True):
                require(struct.pack("<d", float(row[key])) == struct.pack("<d", expected), f"CSV/sample bit disagreement: {key}")
    first = rows[0]
    groups = ((fields[:13], initial_frame["body_hex"]),
              (("cmd_roll", "cmd_pitch", "cmd_yaw", "cmd_throttle"), initial_frame["inputs_hex"]),
              (("engine_rpm", "srv_roll", "srv_pitch", "srv_yaw", *[f"aux_{i}" for i in range(4, len(initial_frame["aux_hex"]))]), initial_frame["aux_hex"]),
              (tuple(f"continuous_{i}" for i in range(len(initial_frame["continuous_hex"]))), initial_frame["continuous_hex"]),
              (("mass_kg",), initial_frame["mass_hex"]))
    for columns, values in groups:
        for column, encoded in zip(columns, values, strict=True):
            require(len(bytes.fromhex(encoded)) == 8 and struct.pack("<d", float(first[column])) == bytes.fromhex(encoded),
                    f"CSV initial-frame bit disagreement: {column}")
    for index, encoded in enumerate(initial_frame["modes_hex"]):
        require(int(first[f"mode_{index}"]) == struct.unpack("<q", bytes.fromhex(encoded))[0], "CSV initial mode disagreement")


def verify(folder: Path, audit: dict, manifest: dict, cell: str, row: dict, case_map: dict) -> dict:
    require(audit.get("complete") is True and audit.get("flight_qualified") is False
            and audit.get("legacy_interpretable") is True, "incomplete/uninterpretable audit")
    spec = audit["specification"]
    require(f"{spec['case_id']}-{spec['tape']}" == cell and spec["calibrate"] is False,
            "cell mismatch or calibration substituted for fixed campaign")
    context = audit["context"]
    require(context.get("campaign_id") == CAMPAIGN and context.get("servo_integration_law") == LAW
            and context.get("servo_interval_protocol") == PROTOCOL, "wrong campaign/law/protocol")
    require(context["engine"] == "4.8-beta2 (official)" and context["os"] == "Windows"
            and context["engine_sha256"] in ENGINE_HASHES, "unregistered engine/platform")
    require(row["status"]["engine"]["version"] == "4.8.beta2.official.cafc17a19"
            and context["engine_sha256"] in row["status"]["engine"]["binaries_sha256"].values(), "audit/native engine disagreement")
    require(context["legacy_tolerances"] == TOLERANCES and context["legacy_floors"] == FLOORS
            and context["legacy_max_ratio"] == .75, "acceptance rule changed")
    require(audit["sample_hz"] == 240 and audit["duration_s"] == 6., "measurement grid changed")
    expected_sources = {"res://project.godot"}
    for name in manifest["files"]:
        relative = Path(name)
        if name.startswith("app/") and relative.suffix in (".gd", ".json") and not any(p.startswith(".") for p in relative.parts):
            expected_sources.add("res://"+name.removeprefix("app/"))
    expected_sources.update(("campaign.gd", "variants.gd", "refinement_audit.gd", "servo_arrival_campaign.gd"))
    require(set(context["sources"]) == expected_sources, "source closure is incomplete or contains unregistered files")
    for name, digest in context["sources"].items():
        path = "app/" + name[6:] if name.startswith("res://") else "app/tools/ac12/" + name
        require(manifest["files"].get(path, {}).get("sha256") == digest, f"source differs from frozen snapshot: {name}")
    for name, field in (("definition.json", "definition_sha256"), ("aircraft-record.json", "record_sha256")):
        require(sha(folder / name) == audit[field], f"authored identity mismatch: {name}")
    definition, record = read(folder / "definition.json"), read(folder / "aircraft-record.json")
    expected_case = case_map["cases"][spec["case_id"]]
    require(audit["definition_sha256"] == expected_case["definition_sha256"]
            and audit["record_sha256"] == expected_case["record_sha256"], "registered historical case identity changed")
    require(definition.get("format") == "openrc-creator-definition v4" and definition.get("servo_integration") == LAW
            and record.get("controls", {}).get("servo_integration") == LAW, "physical law not explicitly selected")
    runs = audit["runs"]
    require([r["rate_hz"] for r in runs] == [240, 480, 960], "missing/extra rates")
    samples = {}
    for index, run in enumerate(runs):
        require(run["ok"] is True and not run["fault"] and run["final_tick"] == 6*run["rate_hz"]
                and run["shaft_integrator"] == "coupled-rk4", "incomplete flight")
        require(run["run_index"] == index and run["samples_file"] == f"samples-{run['rate_hz']}-{index}.f64le", "sample file/index was reused or substituted")
        path = folder / run["samples_file"]
        require(path.parent == folder and sha(path) == run["samples_sha256"], "sample identity mismatch")
        data = path.read_bytes()
        require(len(data) == 1440*17*8, "sample byte count mismatch")
        values = list(struct.iter_unpack("<17d", data))
        require(all(math.isfinite(v) for sample in values for v in sample), "nonfinite samples")
        samples[run["rate_hz"]] = values
    require(not audit["repeats"] and len(audit["pairs"]) == 2, "fixed campaign pair layout changed")
    for key in ("initial_sha256", "environment_sha256", "edges_sha256"):
        require(all(isinstance(r.get(key), str) and re.fullmatch(r"[0-9a-f]{64}", r[key]) for r in runs)
                and len({r[key] for r in runs}) == 1, f"run contexts disagree: {key}")
    require(all(r["initial_frame"] == runs[0]["initial_frame"] for r in runs), "initial frame bits disagree")
    edges = [[(struct.pack("<d", e["time_s"]), e["inputs_hex"]) for e in r["edges"]] for r in runs]
    require(edges[0] == edges[1] == edges[2], "canonical command edges disagree")
    independent_pairs = []
    for pair, rates in zip(audit["pairs"], ((240, 480), (480, 960)), strict=True):
        require((pair["coarse_hz"], pair["fine_hz"]) == rates
                and all(pair[k] is True for k in ("initial_equal", "context_equal", "commands_equal")),
                "incomparable initial frame, environment or commands")
        independent = differences(samples[rates[0]], samples[rates[1]])
        independent_pairs.append(independent)
        require(set(pair["differences"]) == set(TOLERANCES), "metric inventory changed")
        for key, value in independent.items():
            require(type(pair["differences"][key]) in (int, float) and math.isfinite(pair["differences"][key])
                    and pair["differences"][key] >= 0, f"invalid reported metric: {key}")
            require(math.isclose(value, pair["differences"][key], rel_tol=1e-10,
                                 abs_tol=1e-9 if key == "attitude_deg" else 1e-11), f"independent metric mismatch: {key}")
    baseline = runs[0]["baseline_replay"]
    replay = flight_log._check_godot_report(folder / "baseline-replay.json")
    for field, name in (("report_sha256", "baseline-replay.json"), ("log_sha256", "baseline-240.orfl"), ("csv_sha256", "baseline.csv")):
        require(sha(folder / name) == baseline[field], f"baseline artifact mismatch: {name}")
    expected = dict(status="ok", complete=True, solver_changed=False, mode="exact", first_tick=0, final_tick=1440, rows=1441)
    require(all(type(replay.get(k)) is type(v) and replay[k] == v for k, v in expected.items()), "not a complete exact baseline replay")
    require(replay["source_sha256"] == baseline["log_sha256"]
            and replay["baseline_solver_sha256"] == replay["current_solver_sha256"] == context["solver_sha256"], "baseline solver/source identity mismatch")
    require(replay.get("baseline_solver_identity_kind") == replay.get("current_solver_identity_kind") == "source-tree-v1",
            "scientific source replay identity changed")
    verify_csv(folder / "baseline.csv", samples[240], replay, runs[0]["initial_frame"])
    group = replay.get("servo_integration", {})
    require(group.get("checkpoint_migration") == "none" and group.get("recorded") == group.get("replay")
            and group.get("recorded", {}).get("law") == LAW
            and group.get("recorded", {}).get("protocol") == PROTOCOL, "baseline replay did not verify the selected law")
    verdict = audit["legacy_rule"]
    require(not verdict["faults"] and set(verdict["metrics"]) == set(TOLERANCES), "missing verdict metrics")
    passed = True
    for key, metric in verdict["metrics"].items():
        e1, e2 = (p["differences"][key] for p in audit["pairs"])
        require(metric["e_240_480"] == e1 and metric["e_480_960"] == e2 and metric["tolerance"] == TOLERANCES[key], "legacy verdict used different inputs")
        accepted = unambiguous_gate(key, (e1, e2), tuple(p[key] for p in independent_pairs))
        require(type(metric["pass"]) is bool and metric["pass"] == accepted, "legacy verdict differs from registered rule")
        passed = passed and accepted
    require(type(verdict["pass"]) is bool and verdict["pass"] == passed, "aggregate cell verdict mismatch")
    return dict(pass_=passed, audit_sha256=sha(folder / "audit.json"), source_context=context,
                failed_metrics=[k for k, v in verdict["metrics"].items() if not v["pass"]])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("batch", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--partial", action="store_true")
    parser.add_argument("--additional-batch", type=Path, action="append", default=[])
    parser.add_argument("--case-map", type=Path, required=True)
    parser.add_argument("--case-map-sha256", required=True)
    parser.add_argument("--legacy-case-map", type=Path, required=True)
    args = parser.parse_args()
    batch = read(args.batch)
    manifest_path = Path(batch["snapshot"]) / "manifest.json"
    require(sha(manifest_path) == batch["snapshot_manifest_sha256"] == SNAPSHOT_MANIFEST_SHA256, "frozen manifest changed")
    manifest = read(manifest_path)
    require(args.case_map_sha256 == sha(args.case_map) == CASE_MAP_SHA256
            and manifest["files"].get("app/tools/ac12_inputs/servo-cases.json", {}).get("sha256") == CASE_MAP_SHA256,
            "preregistered case map changed")
    case_map = read(args.case_map)
    legacy_map = read(args.legacy_case_map)
    case_ids = {f"C{n:02d}" for n in range(1, 18)}
    require(case_map.get("format") == "openrc-ac12-servo-case-map v1"
            and case_map.get("campaign_id") == CASE_MAP_CAMPAIGN and case_map.get("servo_integration_law") == LAW
            and set(case_map["cases"]) == case_ids and set(legacy_map["cases"]) == case_ids,
            "invalid registered case inventory")
    require(legacy_map.get("format") == "openrc-ac12-legacy-case-map v1"
            and case_map.get("legacy_case_map_sha256") == sha(args.legacy_case_map) == LEGACY_MAP_SHA256
            and manifest["files"].get("app/tools/ac12_inputs/legacy-cases.json", {}).get("sha256") == LEGACY_MAP_SHA256,
            "historical case map changed")
    require(legacy_map["source_hashes"]["res://tools/ac12/campaign.gd"]
            == "20acca0973e6c7285ad8f7c4cf5cdd1564f798f5a60887036d22f73e99ecaaf8", "historical case recipe changed")
    for case in case_ids:
        for kind in ("definition", "record"):
            require(case_map["cases"][case][f"legacy_{kind}_sha256"] == legacy_map["cases"][case][f"{kind}_sha256"],
                    "legacy case identity changed")
    for name, digest in case_map["source_hashes"].items():
        require(name.startswith("res://") and manifest["files"].get("app/"+name[6:], {}).get("sha256") == digest,
                "case map producer used different source inputs")
    require(all(case_map["source_hashes"].get(name) == digest for name, digest in HISTORICAL_INPUTS.items()),
            "registered variants or physical packages changed")
    results = {}
    jobs = []
    batch_hashes = {}
    for path in [args.batch, *args.additional_batch]:
        current = read(path)
        require(current["snapshot"] == batch["snapshot"] and current["snapshot_manifest_sha256"] == batch["snapshot_manifest_sha256"],
                "batches used different frozen inputs")
        batch_hashes[str(path.resolve())] = sha(path)
        jobs.extend(current["jobs"])
    for row in jobs:
        require(row["input"]["platform"] == "windows", "this collector requires a native Windows batch")
        stem = Path(row["input"]["script"]).stem
        composite = stem == "servo_arrival_campaign_all"
        require(composite or re.fullmatch(r"C\d\d_(?:pitch_doublet|roll_doublet|rudder_kick|throttle_step)", stem) is not None,
                "unknown campaign selector")
        log, checked_hash = checked_receipt(row, manifest)
        paths = re.findall(r"^AC12 audit report: (.+)$", log, re.MULTILINE)
        emitted = re.findall(r"^AC12 audit SHA256: ([0-9a-f]{64})$", log, re.MULTILINE)
        require(len(paths) == len(emitted) == (68 if composite else 1), "missing/ambiguous audit receipt")
        expected_cells = [f"C{n:02d}-{t}" for n in range(1, 18) for t in TAPES] if composite else [stem.replace("_", "-", 1)]
        for report_path, digest, cell in zip(paths, emitted, expected_cells, strict=True):
            require(cell in CELLS and cell not in results, "duplicate/unregistered campaign cell")
            folder = args.out / cell
            audit = retain(row, folder, report_path, digest)
            result = verify(folder, audit, manifest, cell, row, case_map)
            selector = "app/" + row["input"]["script"].removeprefix("res://")
            require(audit["context"]["entrypoint_sha256"] == manifest["files"][selector]["sha256"],
                    "audit entrypoint differs from checked selector")
            result.update(job=row["request_id"], checked_report_sha256=checked_hash)
            results[cell] = result
    identities = {(r["source_context"]["engine_sha256"], r["source_context"]["solver_sha256"],
                   json.dumps(r["source_context"]["sources"], sort_keys=True)) for r in results.values()}
    require(len(identities) == 1, "cells used different source closures or engine binaries")
    complete = set(results) == CELLS
    summary = dict(campaign_id=CAMPAIGN, snapshot_manifest_sha256=sha(manifest_path),
                   complete=complete, partial=args.partial, flight_qualified=False,
                   numerical_campaign_pass=complete and not args.partial and all(r["pass_"] for r in results.values()),
                   missing_cells=sorted(CELLS-set(results)), cells=results,
                   checked_batches=batch_hashes,
                   case_map_sha256=sha(args.case_map), legacy_case_map_sha256=sha(args.legacy_case_map),
                   replay_validator_sha256=sha(Path(flight_log.__file__)),
                   verifier_sha256=sha(Path(__file__)))
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "verification.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps({k: summary[k] for k in ("complete", "partial", "numerical_campaign_pass", "missing_cells")}, indent=2))
    return 0 if (complete or args.partial) and all(r["pass_"] for r in results.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
