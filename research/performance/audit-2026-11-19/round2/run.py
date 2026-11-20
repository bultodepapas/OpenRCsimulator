#!/usr/bin/env python3
"""Reproduce round-two audit observations in disposable, source-checked fixtures.

Success means the documented baseline behavior was observed. It does not mean
the defects are repaired, a renderer was exercised, or performance improved.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]


def digest(path: Path, algorithm: str = "sha256") -> str:
    h = hashlib.new(algorithm)
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def one_json(log: Path, prefix: str) -> dict | list:
    rows = [line[len(prefix):] for line in log.read_text().splitlines() if line.startswith(prefix)]
    if len(rows) != 1:
        raise RuntimeError(f"Expected exactly one {prefix!r} observation in {log}")
    return json.loads(rows[0])


def extracted_layout(source: str) -> str:
    out = ("# Fixture-only extraction from app/render/lake/lake_plants.gd; selected functions are unchanged.\n"
           "extends RefCounted\n")
    for name in ("Surface", "SEED", "LILY_ANCHORS", "REED_ANCHORS"):
        match = re.search(rf"^const {name} := .*$", source, re.M)
        if not match:
            raise RuntimeError(f"Missing original layout constant {name}")
        out += match.group(0) + "\n"
    out += "\n"
    for name in ("layout", "_anchor", "_too_close"):
        match = re.search(rf"^static func {name}\(.*?(?=^static func |\Z)", source, re.M | re.S)
        if not match:
            raise RuntimeError(f"Missing original layout function {name}")
        out += match.group(0).rstrip() + "\n\n"
    return out.rstrip("\n") + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True, help="New directory; existing output is refused")
    args = parser.parse_args()
    engine = args.godot.resolve()
    out = args.out.resolve()
    manifest = json.loads((HERE / "fixture_sources.json").read_text())
    if not engine.is_file() or digest(engine, "sha512") != manifest["engine_sha512"]:
        raise RuntimeError("Engine does not match the pinned official Linux x86_64 binary; no launch")
    for name, sha in manifest["files"].items():
        if not (REPO / name).is_file() or digest(REPO / name) != sha:
            raise RuntimeError(f"Baseline source differs: {name}")
    for name, sha in manifest["stub_sha256"].items():
        if digest(HERE / "stubs" / name) != sha:
            raise RuntimeError(f"Disclosed fixture stub differs: {name}")
    layout = extracted_layout((REPO / "app/render/lake/lake_plants.gd").read_text())
    if layout != (HERE / "plant_layout_extracted.gd").read_text() or \
            hashlib.sha256(layout.encode()).hexdigest() != manifest["extracted_layout_sha256"]:
        raise RuntimeError("The extracted lake placement functions differ from the pinned source")
    out.mkdir(parents=True, exist_ok=False)
    fixtures: dict[str, Path] = {}
    environments: dict[str, dict[str, str]] = {}
    for group, settings in manifest["groups"].items():
        fixture = out / group
        fixture.mkdir()
        fixtures[group] = fixture
        for name in settings["files"]:
            target = fixture / Path(name).relative_to("app")
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(REPO / name, target)
        for name in settings["stubs"]:
            target = fixture / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(HERE / "stubs" / name, target)
        (fixture / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="OpenRC-Audit-Round2-' + group + '"\n'
            '[physics]\ncommon/physics_ticks_per_second=240\n'
            '[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
        environment = os.environ.copy()
        for variable, leaf in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
            environment[variable] = str(out / "xdg" / group / leaf)
        environments[group] = environment
    # The fingerprint scanner expects all three directories. Only the copied
    # dependency closure exists here, so its digest is a fixture identity.
    for name in ("physics", "sim", "failures"):
        (fixtures["core"] / name).mkdir(exist_ok=True)
    for name in ("replay_probe.gd", "input_probe.gd", "angle_probe.gd", "angle_half_turn_probe.gd", "lake_wave_probe.gd", "plant_layout_extracted.gd",
                 "custom_wave_probe.gd", "terrain_component_probe.gd", "terrain_session_probe.gd"):
        shutil.copyfile(HERE / name, fixtures["core"] / name)
    shutil.copyfile(HERE / "settings_probe.gd", fixtures["settings"] / "settings_probe.gd")
    runs: list[dict] = []

    def checked(group: str, label: str, script: str = "", marker: str = "", extra: list[str] | None = None) -> Path:
        command = [sys.executable, str(REPO / "tools/godot/run_checked.py"),
                   "--label", label, "--out-dir", str(out / "runs"), "--timeout", "60"]
        if marker:
            command += ["--require-text", marker]
        command += ["--", str(engine), "--headless", "--audio-driver", "Dummy", "--path", str(fixtures[group])]
        command += ["--script", "res://" + script] if script else ["--editor", "--import"]
        if extra:
            command += ["--", *extra]
        process = subprocess.run(command, cwd=REPO, env=environments[group], capture_output=True, text=True, check=False)
        paths = [p for p in (out / "runs").glob(label + "-*/report.json")
                 if json.loads(p.read_text()).get("label") == label]
        if len(paths) != 1:
            raise RuntimeError(f"Missing or ambiguous checked receipt for {label}: {process.stdout[-2000:]} {process.stderr[-2000:]}")
        path = paths[0]
        receipt = json.loads(path.read_text())
        log = path.parent / "engine.log"
        if digest(log) != receipt["log_sha256"]:
            raise RuntimeError(f"Checked log hash mismatch for {label}")
        runs.append({"label": label, "group": group, "report": str(path.relative_to(out)),
                     "log": str(log.relative_to(out)), "receipt": receipt})
        print(f"{label}: {receipt['reason']} (errors={receipt['counts']['error']}, warnings={receipt['counts']['warning']})", flush=True)
        if process.returncode or not receipt.get("ok"):
            raise RuntimeError(f"Checked run failed: {path}\n{process.stdout[-4000:]}\n{process.stderr[-4000:]}")
        return log

    checked("core", "r2-core-import")
    checked("settings", "r2-settings-import")
    settings_log = checked("settings", "r2-settings", "settings_probe.gd", "PROBE_COMPLETE failures=0")
    angle_log = checked("core", "r2-angle", "angle_probe.gd", "angle discontinuity reproduced")
    half_turn_log = checked("core", "r2-angle-half-turn", "angle_half_turn_probe.gd", "half-turn representation dependence reproduced")
    input_log = checked("core", "r2-input", "input_probe.gd", "INPUT_PROBE_COMPLETE expected_observation=true")
    lake_log = checked("core", "r2-lake", "lake_wave_probe.gd", "PROBE_COMPLETE result=PASS pads=105 flowers=14")
    custom_wave_log = checked("core", "r2-custom-waves", "custom_wave_probe.gd", "PROBE_COMPLETE result=PASS")
    terrain_component_log = checked("core", "r2-terrain-component", "terrain_component_probe.gd", "terrain early-out reproduced")
    terrain_session_log = checked("core", "r2-terrain-session", "terrain_session_probe.gd", "session terrain early-out reproduced")
    replay_log = checked("core", "r2-replay-control", "replay_probe.gd", "REPLAY_PROBE_COMPLETE expected_observation=true")
    original = fixtures["core"] / "physics/math3d.gd"
    original_bytes = original.read_bytes()
    original_sha = digest(original)
    changed_bytes = original_bytes + b"\n# Audit-only comment in this disposable fixture; numerical implementation unchanged.\n"
    original.write_bytes(changed_bytes)
    changed_sha = digest(original)
    try:
        changed_log = checked("core", "r2-replay-source-change", "replay_probe.gd",
                              "REPLAY_PROBE_COMPLETE expected_observation=true", ["--verify-changed-source"])
    finally:
        original.write_bytes(original_bytes)
    angle_paths = list((out / "xdg" / "core" / "data").rglob("angle_evidence.json"))
    if len(angle_paths) != 1:
        raise RuntimeError("Expected exactly one angle evidence file in the isolated user directory")
    angle = json.loads(angle_paths[0].read_text())
    settings = []
    for line in settings_log.read_text().splitlines():
        if line.startswith("PROBE "):
            _, name, status, payload = line.split(" ", 3)
            settings.append({"case": name, "status": status, "observation": json.loads(payload)})
    lake = []
    for line in lake_log.read_text().splitlines():
        if line.startswith("CASE "):
            _, name, payload = line.split(" ", 2)
            lake.append({"case": name, **json.loads(payload)})
    control = one_json(replay_log, "REPLAY_JSON ")
    changed = one_json(changed_log, "REPLAY_JSON ")
    inputs = one_json(input_log, "INPUT_JSON ")
    half_turn = one_json(half_turn_log, "HALF_TURN_CASES ")
    custom_waves = []
    for line in custom_wave_log.read_text().splitlines():
        if line.startswith("CASE "):
            _, name, payload = line.split(" ", 2)
            custom_waves.append({"case": name, **json.loads(payload)})
    terrain_component = one_json(terrain_component_log, "TERRAIN_CASES ")
    terrain_session = one_json(terrain_session_log, "SESSION_TERRAIN_CASES ")
    expected = {
        "settings_six_cases_and_three_seeds": len(settings) == 9 and all(x["status"] == "PASS" for x in settings),
        "angle_banked_discontinuity_and_zero_bank_controls": len(angle["cases"]) == 6
            and all(x["orientation_distance_rad"] < 2.01e-8 for x in angle["cases"])
            and all(x["raw_roll_jump"] < 1e-6 if x["roll"] == 0 else x["raw_roll_jump"] > 1.0 for x in angle["cases"]),
        "angle_half_turn_sign_dependence_and_nearby_control": len(half_turn) == 4
            and half_turn[0]["rotated_up"] == half_turn[1]["rotated_up"]
            and half_turn[0]["target"][0] == -half_turn[1]["target"][0]
            and half_turn[0]["target"][0] != 0 and half_turn[2]["target"] == half_turn[3]["target"],
        "button_callback_count": len(inputs["rows"]) == 2 and all(x["buttons"] == 30720 and x["axes"] == 2400 for x in inputs["rows"]),
        "wave_transform_difference": len(lake) == 2 and all(x["result"] == "PASS" and abs(x["formula_m"]) > 0.0005 for x in lake),
        "custom_lake_fade_and_clock": len(custom_waves) == 2 and all(x["result"] == "PASS" for x in custom_waves),
        "terrain_component_counterexample_and_control": len(terrain_component) == 2
            and terrain_component[0]["force"] != [0, 0, 0] and terrain_component[0]["strict_crash_reason"] == "Propeller strike"
            and terrain_component[1]["force"] == [0, 0, 0] and terrain_component[1]["strict_crash_reason"] == ""
            and all(x["max_point_depth_m"] > 0 and x["rotor_witnesses"] for x in terrain_component),
        "terrain_actual_session_accepts_one_tick": len(terrain_session) == 2
            and all(x["prepared"] and x["resumed"] and x["advanced"] and x["tick"] == 1 and x["point_depth_m"] > 0.27
                    and x["rotor_hits"] == [0, 1] and x["contact_force"] == [0, 0, 0] and x["substeps"] == 1
                    and not x["crash"] and x["fault"] == "" and x["post_health"] == [1, 1, 1, 1] for x in terrain_session),
        "valid_recording_same_source_control": control["report"]["ok"] and control["report"]["exact"] and not control["report"]["solver_changed"],
        "changed_source_still_exact": changed["report"]["ok"] and changed["report"]["exact"] and changed["report"]["solver_changed"],
        "recording_bytes_unchanged": control["original_recording_sha256"] == changed["original_recording_sha256"],
        "four_parsed_metadata_cases_still_exact": len(control["parsed_record_metadata_cases"]) == 4
            and all(x["report"]["ok"] and x["report"]["exact"] for x in control["parsed_record_metadata_cases"]),
        "fixture_source_restored": digest(original) == original_sha,
    }
    # Check the original checkout again. The comment experiment affected only
    # one disposable copy; all pinned source inputs must still match.
    for name, sha in manifest["files"].items():
        if digest(REPO / name) != sha:
            raise RuntimeError(f"Source changed during collection: {name}")
    if digest(engine, "sha512") != manifest["engine_sha512"]:
        raise RuntimeError("Engine changed during collection")
    assets = {str(p.relative_to(HERE)): digest(p) for p in HERE.rglob("*") if p.is_file() and "__pycache__" not in p.parts}
    result = {
        "format": "openrc-performance-audit-round2-results-v1",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "runtime_base": manifest["runtime_base"], "engine_version": manifest["engine_version"],
        "engine_sha512": manifest["engine_sha512"], "fixture_source_hashes": manifest["files"],
        "reproduction_asset_hashes": assets, "local_test_pool_configured": bool(os.environ.get("OPENRC_TESTPOOL_CONFIG")),
        "scope": "Headless component/settings observations and scalar transform math; no GPU, native backend, timing or full-flight qualification",
        "fixture_substitutions": {"collision": "Two assertion stubs; terrain-only airship/drone sessions install no scenery obstacle inventory; neither stub executes",
            "settings": "Only the player-preferences DEFAULT_PATH constant is supplied; UI fonts use ThemeDB.fallback_font",
            "lake": "Unchanged layout/anchor/spacing source blocks extracted; scalar math plus Transform3D, no shader execution",
            "source_change": {"fixture_path": "core/physics/math3d.gd", "before_sha256": original_sha,
                "after_sha256": changed_sha, "description": "Comment appended between fresh processes; original recording bytes retained; fixture source restored"}},
        "runs": runs,
        "observations": {"settings": settings, "angle": angle, "angle_half_turn": half_turn, "input": inputs, "lake": lake,
                         "custom_waves": custom_waves, "terrain_component": terrain_component, "terrain_session": terrain_session,
                         "replay_control": control, "replay_changed_source": changed},
        "expected_baseline_observations": expected,
        "baseline_observations_reproduced": all(expected.values()),
    }
    target = out / "audit_results.json"
    target.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    print(f"Baseline observations reproduced: {result['baseline_observations_reproduced']}")
    print(f"Evidence: {target}")
    return 0 if result["baseline_observations_reproduced"] else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Round-two reproduction stopped: {error}", file=sys.stderr)
        sys.exit(1)
