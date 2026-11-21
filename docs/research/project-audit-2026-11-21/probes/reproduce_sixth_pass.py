#!/usr/bin/env python3
"""Rebuild A36 R6's exact-source, real-dependency research fixture and evidence.

Requires reviewed Git objects and the pinned official Linux Godot executable.
Writes only a new output directory. Two tailless-wake invocations MUST fail the
checked runner with the exact recorded engine diagnostics: they reproduce a
defect, and are never described as clean tests. No production fixes or stubs.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

from sixth_pass_fixtures import create_propeller_inputs, create_tailless_wake_inputs

REVIEWED_COMMIT = "f2d9bf7c0e1fad77158bbadcb99c0c487ddb94ac"
ENGINE_SHA256 = "34d0599a1f17acc76583610969878065d1b1701615af77271e32201351b9c564"
MANIFEST_SHA256 = "9b9257242b8873d0045df0abf41aa13ca62dccc6b0a5a925683869152367b9be"
EXTRA_PATHS = (
    "app/data/batteries/cells/lipo-bak503562-galeotti-v1.json",
    "app/data/batteries/packs/lipo-4s1p-3200-30c-class.json",
    "app/data/batteries/packs/lipo-6s1p-5000-30c-class.json",
    "app/sim/race/gate_crossing.gd",
    "app/sim/race/race_director.gd",
    "app/sim/race/track.gd",
    "app/tests/test_spatial_wind_contract.gd",
    "app/tests/test_spatial_wind_field.gd",
    "app/tests/fixtures/spatial_wind_mode_grid_before.json",
    "app/tests/test_tailless_spatial_wind.gd",
)
PROBES = (
    ("propeller-power", "sixth_pass_propeller_power.gd", "R6 propeller power witness: 0 failures"),
    ("propeller-trim", "sixth_pass_propeller_trim.gd", "R6 natural trim power witness: 0 failures"),
    ("flap-wake", "sixth_pass_flap_wake.gd", "R6 flap wake witness: 0 failures"),
    ("wind-contract", "tests/test_spatial_wind_contract.gd", "spatial wind contract: 176 checks, 0 failed"),
    ("wind-field", "tests/test_spatial_wind_field.gd", "spatial wind field: 155 checks, 0 failed"),
    ("tailless-spatial", "tests/test_tailless_spatial_wind.gd", "tailless spatial wind: 121 checks, 0 failed"),
    ("airship-dynamics", "tests/test_airship_dynamics.gd", "50 checks, 0 failed"),
    ("tailless-admission", "r4_admission.gd", "R4_ADMISSION_COMPLETE PASS"),
    ("tailless-controls", "r4_component_controls.gd", "R4_CONTROLS_COMPLETE PASS"),
    ("tailless-session-control", "r4_session_control.gd", "R4_NO_WAKE_SESSION_COMPLETE PASS"),
)
TRIGGERS = (
    ("tailless-component-trigger", "r4_component_trigger.gd", "R4_TRIGGER_COMPLETE"),
    ("tailless-session-trigger", "r4_session_trigger.gd", "R4_WAKE_SESSION_COMPLETE"),
)
MISSING_HORIZONTAL = "Invalid access to property or key 'horizontal' on a base object of type 'Dictionary'."
OUT_OF_BOUNDS = "Out of bounds get index '0' (on base: 'PackedFloat64Array')"


def missing(key: str) -> str:
    return f"Invalid access to property or key '{key}' on a base object of type 'Dictionary'."


EXPECTED_DIAGNOSTICS = {
    "tailless-component-trigger": [MISSING_HORIZONTAL],
    "tailless-session-trigger": [MISSING_HORIZONTAL, OUT_OF_BOUNDS, missing("loads"),
                                 missing("derivative"), MISSING_HORIZONTAL, OUT_OF_BOUNDS,
                                 missing("loads"), missing("state"), missing("ok"), missing("alpha")],
}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def blob_sha(data: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()


def dump(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n")


def json_rows(log: str, prefix: str) -> list[dict]:
    return [json.loads(line[len(prefix):]) for line in log.splitlines() if line.startswith(prefix)]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    repo, engine, out = args.repo_root.resolve(), args.godot.resolve(), args.out.resolve()
    here = Path(__file__).resolve().parent
    if out.exists():
        parser.error("--out must be a new directory; existing work is never removed")
    if sha256(engine.read_bytes()) != ENGINE_SHA256:
        parser.error("engine does not match the pinned official Linux executable")
    manifest_path = here.parent / "integration-manifest.json"
    if sha256(manifest_path.read_bytes()) != MANIFEST_SHA256:
        parser.error("base dependency manifest differs from the reviewed identity")
    manifest = json.loads(manifest_path.read_bytes())

    def git_file(path: str) -> bytes:
        return subprocess.check_output(["git", "show", REVIEWED_COMMIT + ":" + path], cwd=repo)

    runner = repo / "tools/godot/run_checked.py"
    if runner.read_bytes() != git_file("tools/godot/run_checked.py"):
        raise RuntimeError("checked runner differs from the reviewed source")
    out.mkdir(parents=True)
    project = out / "project"
    project.mkdir()
    sources = []
    for item in manifest["files"]:
        raw = git_file(item["path"])
        if blob_sha(raw) != item["git_blob_sha1"]:
            raise RuntimeError("changed baseline dependency: " + item["path"])
        if item["checkout_bytes"] == "lf_blob_checked_out_as_crlf":
            raw = raw.replace(b"\n", b"\r\n")
        elif item["checkout_bytes"] != "exact":
            raise RuntimeError("unknown checkout-byte policy")
        if sha256(raw) != item["fixture_sha256"] or len(raw) != item["bytes"]:
            raise RuntimeError("fixture byte mismatch: " + item["path"])
        dest = project / Path(item["path"]).relative_to("app")
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(raw)
        sources.append(item)
    known = {item["path"] for item in sources}
    for path in EXTRA_PATHS:
        if path in known:
            continue
        raw = git_file(path)
        dest = project / Path(path).relative_to("app")
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(raw)
        sources.append({"path": path, "bytes": len(raw), "git_blob_sha1": blob_sha(raw),
                        "fixture_sha256": sha256(raw), "checkout_bytes": "exact"})
    settings = manifest["fixture_project_godot"].replace(
        'config/name="A36 full Phoenix readers"', 'config/name="A36 R6 isolated research"')
    (project / "project.godot").write_text(settings)
    for _, filename, _ in PROBES + TRIGGERS:
        if not filename.startswith("tests/"):
            (project / filename).write_bytes((here / filename).read_bytes())
    generated = create_propeller_inputs(project) + create_tailless_wake_inputs(project)
    for name, child in (("XDG_DATA_HOME", "user-data"), ("XDG_CONFIG_HOME", "user-config"),
                        ("XDG_CACHE_HOME", "user-cache")):
        os.environ[name] = str(out / child)
    # Preserve testqueue/pool admission variables. The checked runner owns scheduling.
    sys.dont_write_bytecode = True
    sys.path.insert(0, str(repo))
    from tools.godot.run_checked import run_checked

    probe_names = [filename for _, filename, _ in PROBES + TRIGGERS
                   if not filename.startswith("tests/")]
    probe_names += [Path(__file__).name, "sixth_pass_fixtures.py", "sixth_pass_oracles.py"]
    evidence = {
        "format": "openrc-a36-r6-evidence v1", "reviewed_commit": REVIEWED_COMMIT,
        "engine_sha256": ENGINE_SHA256,
        "engine_version": subprocess.check_output([str(engine), "--version"], text=True).strip(),
        "base_manifest_sha256": MANIFEST_SHA256, "base_dependency_count": len(manifest["files"]),
        "total_dependency_count": len(sources), "extra_dependencies": sources[len(manifest["files"]):],
        "project_godot": settings, "production_stubs": [], "generated_synthetic_inputs": generated,
        "stock_inputs_unchanged": True,
        "probe_sha256": {name: sha256((here / name).read_bytes()) for name in probe_names},
        "checked_runner_sha256": sha256(runner.read_bytes()), "checks": [], "oracles": [], "ok": False,
    }
    output_path = out / "evidence.json"

    def checked(label: str, extra_args: list[str], required: list[str]) -> dict:
        result = run_checked([str(engine), "--headless", "--path", str(project),
                              "--audio-driver", "Dummy"] + extra_args,
                             out / "checks", timeout=90 if label not in EXPECTED_DIAGNOSTICS else 20,
                             warnings_as_errors=True, required=required, label="a36-r6-" + label)
        log = Path(result["log"]).read_text()
        entry = {"label": label, "report": result, "engine_log": log}
        if label in EXPECTED_DIAGNOSTICS:
            expected = EXPECTED_DIAGNOSTICS[label]
            matches = (not result["ok"] and result["reason"] == "engine_error"
                       and result["process_exit"] == 0 and result["exit_code"] == 1
                       and result["counts"] == {"error": len(expected), "warning": 0}
                       and not result["missing_required_text"]
                       and [d["message"] for d in result["diagnostics"]] == expected
                       and "res://physics/slipstream.gd:117" in log)
            entry.update(expected_failure=True, expected_diagnostics=expected,
                         expected_failure_matched=matches)
            accepted = matches
        else:
            accepted = result["ok"] and result["counts"] == {"error": 0, "warning": 0}
            entry["expected_failure"] = False
        evidence["checks"].append(entry)
        dump(output_path, evidence)
        print(label + ": " + result["reason"] + (" (expected)" if label in EXPECTED_DIAGNOSTICS else ""), flush=True)
        if not accepted:
            raise RuntimeError("unexpected checked result; inspect " + str(output_path))
        return entry

    checked("import", ["--editor", "--import"], [])
    by_label = {}
    for label, filename, marker in PROBES + TRIGGERS:
        by_label[label] = checked(label, ["--script", "res://" + filename], [marker])
    admissions = json_rows(by_label["tailless-admission"]["engine_log"], "R4_ADMISSION ")
    assert len(admissions) == 3
    by_file = {row["file"]: row for row in admissions}
    for name in ("r4_no_wake.json", "r4_candidate.json"):
        row = by_file[name]
        assert row["ok"] and row["classified"] and not row["errors"] and not row["warnings"]
        assert "horizontal" not in row["surface_keys"] and "vertical" in row["surface_keys"]
    assert not by_file["r4_electric_wake.json"]["ok"]
    control = json_rows(by_label["tailless-session-control"]["engine_log"], "R4_NO_WAKE_SESSION ")[0]
    refused = json_rows(by_label["tailless-session-trigger"]["engine_log"], "R4_WAKE_SETUP_RETURN ")[0]
    assert control["accepted"] and control["final_tick"] == control["initial_tick"] + 1
    assert not refused["flyable"] and refused["tick"] == 0
    evidence["tailless_scope"] = {"complete_loader_admission": True, "no_wake_control_accepted_tick": True,
                                  "wake_setup_fails": True, "wake_enabled_accepted_tick": False,
                                  "native_or_swirl_execution": False}
    command = [sys.executable, str(here / "sixth_pass_oracles.py"),
               "--flap-log", by_label["flap-wake"]["report"]["log"],
               "--power-log", by_label["propeller-power"]["report"]["log"],
               "--trim-log", by_label["propeller-trim"]["report"]["log"], "--project", str(project)]
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    evidence["oracles"].append({"command": command, "exit_code": result.returncode,
                                "stdout": result.stdout, "stderr": result.stderr})
    dump(output_path, evidence)
    if result.returncode:
        raise RuntimeError("independent oracles failed; inspect " + str(output_path))
    # All 442 source dependencies still match after probes; only labeled new files were synthesized.
    for item in sources:
        assert sha256((project / Path(item["path"]).relative_to("app")).read_bytes()) == item["fixture_sha256"]
    evidence["ok"] = True
    dump(output_path, evidence)
    print("R6_REPRODUCTION_COMPLETE " + str(output_path), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
