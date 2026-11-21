#!/usr/bin/env python3
"""Reconstruct and check A36 R5's isolated, real-dependency research fixture.

Needs Python 3, a checkout containing REVIEWED_COMMIT's Git objects and the exact
official Linux x86-64 Godot executable below. No downloads, production edits,
native execution, flight recording or physical calibration are performed here.
The output directory must not exist. Diagnostics and the independent oracles
are gates: a zero Godot process exit alone is insufficient.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

REVIEWED_COMMIT = "136b32e585dc84293b81fc036a81530a04da5397"
ENGINE_SHA256 = "34d0599a1f17acc76583610969878065d1b1701615af77271e32201351b9c564"
EXTRA_PATHS = (
    "app/data/batteries/cells/lipo-bak503562-galeotti-v1.json",
    "app/data/batteries/packs/lipo-4s1p-3200-30c-class.json",
    "app/sim/race/gate_crossing.gd",
    "app/sim/race/race_director.gd",
    "app/sim/race/track.gd",
    "app/tests/test_race_gate_crossing.gd",
    "app/tests/test_race_director.gd",
)
PROBES = (
    ("helicopter", "fifth_pass_helicopter_trim.gd", "SESSION_PROBE_COMPLETE"),
    ("race", "fifth_pass_race_curve.gd", "R5 race witness: 0 failures"),
    ("thermal", "fifth_pass_thermal_stiffness.gd", "R5 thermal witness: 0 failures"),
    ("ground-effect", "fifth_pass_ground_effect.gd", "PROBE_COMPLETE"),
    ("race-gate-existing", "tests/test_race_gate_crossing.gd", "19 checks, 0 failed"),
    ("race-director-existing", "tests/test_race_director.gd", "33 checks, 0 failed"),
)
SYNTHETIC = "A36 R5 synthetic domain/stiffness witness, not a physical pack calibration"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def blob_sha(data: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()


def dump(path: Path, value: object) -> bytes:
    data = (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode()
    path.write_bytes(data)
    return data


def mutate_battery(project: Path) -> list[dict]:
    """Construct numerical-domain data; keep geometry and total inventory fixed."""
    cell_path = project / "data/batteries/cells/lipo-bak503562-galeotti-v1.json"
    pack_path = project / "data/batteries/packs/lipo-4s1p-3200-30c-class.json"
    aircraft_path = project / "data/aircraft/battery/turbo_lumber_evolution_4s_pack.json"
    paths = (cell_path, pack_path, aircraft_path)
    before = {p: sha256(p.read_bytes()) for p in paths}
    cell, pack, aircraft = [json.loads(p.read_bytes()) for p in paths]

    def quantity(q: dict, value: object) -> None:
        q.update(value=value, kind="estimated", source=SYNTHETIC)

    quantity(cell["specific_heat_j_per_kg_k"], 100.0)
    tables = [cell["ocv_v"], cell["r0_ohm"]]
    for branch in cell["rc_branches"]:
        tables.extend((branch["r_ohm"], branch["tau_s"]))
    for table in tables:
        rows = table["value"]
        quantity(table, [copy.deepcopy(rows[-1]) for _ in rows])
    pack["cell_template"]["sha256"] = sha256(dump(cell_path, cell))
    quantity(pack["mass_kg"], 0.01)
    quantity(pack["heat_transfer"]["still_air_w_per_k"], 1000.0)
    quantity(pack["heat_transfer"]["forced_w_per_k_per_sqrt_mps"], 0.0)
    aircraft["propulsion"]["battery"]["pack"]["sha256"] = sha256(dump(pack_path, pack))
    quantity(aircraft["propulsion"]["battery"]["auxiliary_current_a"], 0.0)
    mount_id = aircraft["propulsion"]["battery"]["mount_inventory_id"]
    mount = next(item for item in aircraft["inventory"] if item["id"] == mount_id)
    ballast = copy.deepcopy(mount)
    ballast.update(id="a36_r5_inert_ballast",
                   name="synthetic inert ballast preserving aircraft mass/CG/inertia")
    ballast.pop("energy_source", None)
    quantity(ballast["mass"], round(float(mount["mass"]["value"]) - 0.01, 12))
    quantity(mount["mass"], 0.01)
    aircraft["inventory"].append(ballast)
    dump(aircraft_path, aircraft)
    return [{"path": str(p.relative_to(project)), "before_sha256": before[p],
             "after_sha256": sha256(p.read_bytes())} for p in paths]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", required=True, type=Path)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    repo, engine, out = args.repo_root.resolve(), args.godot.resolve(), args.out.resolve()
    here = Path(__file__).resolve().parent
    if out.exists():
        parser.error("--out must be a new directory; existing work is never removed")
    if sha256(engine.read_bytes()) != ENGINE_SHA256:
        parser.error("engine does not match the pinned official Linux executable")
    manifest_path = here.parent / "integration-manifest.json"
    manifest = json.loads(manifest_path.read_bytes())
    out.mkdir(parents=True)
    project = out / "project"
    project.mkdir()

    def git_file(path: str) -> bytes:
        return subprocess.check_output(
            ["git", "show", REVIEWED_COMMIT + ":" + path], cwd=repo)

    source_records = []
    for item in manifest["files"]:
        raw = git_file(item["path"])
        if blob_sha(raw) != item["git_blob_sha1"]:
            raise RuntimeError("changed baseline dependency: " + item["path"])
        mode = item["checkout_bytes"]
        if mode == "lf_blob_checked_out_as_crlf":
            raw = raw.replace(b"\n", b"\r\n")
        elif mode != "exact":
            raise RuntimeError("unknown checkout-byte policy: " + mode)
        if len(raw) != item["bytes"] or sha256(raw) != item["fixture_sha256"]:
            raise RuntimeError("fixture byte mismatch: " + item["path"])
        dest = project / Path(item["path"]).relative_to("app")
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(raw)
        source_records.append(item)
    known = {item["path"] for item in source_records}
    for path in EXTRA_PATHS:
        if path in known:
            continue
        raw = git_file(path)
        dest = project / Path(path).relative_to("app")
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(raw)
        source_records.append({"path": path, "bytes": len(raw),
                               "git_blob_sha1": blob_sha(raw),
                               "fixture_sha256": sha256(raw), "checkout_bytes": "exact"})

    project_settings = manifest["fixture_project_godot"].replace(
        'config/name="A36 full Phoenix readers"', 'config/name="A36 R5 isolated research"')
    (project / "project.godot").write_text(project_settings)
    for _, filename, _ in PROBES:
        if not filename.startswith("tests/"):
            (project / filename).write_bytes((here / filename).read_bytes())
    mutations = mutate_battery(project)
    # Isolate user data/config/cache. Preserve testqueue/pool admission variables:
    # the checked runner continues to own any host scheduling requirements.
    for name, child in (("XDG_DATA_HOME", "user-data"), ("XDG_CONFIG_HOME", "user-config"),
                        ("XDG_CACHE_HOME", "user-cache")):
        os.environ[name] = str(out / child)
    sys.path.insert(0, str(repo))
    from tools.godot.run_checked import run_checked

    runner = repo / "tools/godot/run_checked.py"
    if runner.read_bytes() != git_file("tools/godot/run_checked.py"):
        raise RuntimeError("checked runner differs from the reviewed source")
    evidence = {
        "format": "openrc-a36-r5-evidence v1",
        "reviewed_commit": REVIEWED_COMMIT,
        "engine_sha256": ENGINE_SHA256,
        "engine_version": subprocess.check_output([str(engine), "--version"], text=True).strip(),
        "base_manifest_sha256": sha256(manifest_path.read_bytes()),
        "base_dependency_count": len(manifest["files"]),
        "total_dependency_count": len(source_records),
        "extra_dependencies": source_records[len(manifest["files"]):],
        "project_godot": project_settings,
        "generated_data_mutations": mutations,
        "mutation_scope": SYNTHETIC + "; warm temperature rows, auxiliary 0/0.3 A, same-location inert ballast",
        "production_stubs": [],
        "probe_sha256": {p.name: sha256(p.read_bytes()) for p in sorted(here.glob("*fifth_pass*.py"))},
        "checked_runner_sha256": sha256(runner.read_bytes()),
        "checks": [], "oracles": [], "ok": False,
    }
    evidence["probe_sha256"].update({p.name: sha256(p.read_bytes())
                                      for p in sorted(here.glob("fifth_pass_*.gd"))})
    output_path = out / "evidence.json"

    def checked(label: str, extra_args: list[str], required: list[str]) -> dict:
        result = run_checked(
            [str(engine), "--headless", "--path", str(project), "--audio-driver", "Dummy"] + extra_args,
            out / "checks", timeout=90, warnings_as_errors=True,
            required=required, label="a36-r5-reproduce-" + label)
        log = Path(result["log"]).read_text()
        record = {"label": label, "report": result, "engine_log": log}
        evidence["checks"].append(record)
        dump(output_path, evidence)
        print(label + ": " + result["reason"], flush=True)
        if not result["ok"]:
            raise RuntimeError("checked Godot failure; inspect " + str(output_path))
        return record

    checked("import", ["--editor", "--import"], [])
    by_label = {}
    for label, filename, marker in PROBES:
        by_label[label] = checked(label, ["--script", "res://" + filename], [marker])
    oracle_commands = [
        ("servo", ["fifth_pass_servo_oracle.py", by_label["helicopter"]["report"]["log"],
                    str(project / "data/aircraft/xcell_60_research.json")]),
        ("ground-effect", ["fifth_pass_ground_effect_oracle.py", by_label["ground-effect"]["report"]["log"]]),
        ("numerical", ["fifth_pass_numerical_oracle.py", by_label["race"]["report"]["log"],
                        by_label["thermal"]["report"]["log"]]),
    ]
    for label, arguments in oracle_commands:
        command = [sys.executable, str(here / arguments[0])] + arguments[1:]
        result = subprocess.run(command, text=True, capture_output=True, check=False)
        evidence["oracles"].append({"label": label, "command": command,
                                    "exit_code": result.returncode,
                                    "stdout": result.stdout, "stderr": result.stderr})
        dump(output_path, evidence)
        if result.returncode:
            raise RuntimeError("independent oracle failed; inspect " + str(output_path))
        print(label + " oracle: passed", flush=True)
    # The thermal probe also creates one explicitly declared auxiliary-load variant.
    generated = project / "thermal_positive_heat_aircraft.json"
    evidence["runtime_generated_data"] = {"path": generated.name,
                                          "sha256": sha256(generated.read_bytes())}
    evidence["ok"] = True
    dump(output_path, evidence)
    print("R5_REPRODUCTION_COMPLETE " + str(output_path), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
