#!/usr/bin/env python3
"""Run VAL-4 and prove its named mutations fail, only in disposable app copies."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
GROUPS = {"mirror", "froude", "energy", "integrity", "coverage"}
# Source edits, not altered expected answers; anchors must match exactly once.
MUTATIONS = {
    "left_aileron_yaw_sign": (
        "mirror", "app/physics/aero.gd",
        "var co_yaw: float = a.Cnb * beta_eff + a.Cnda_right * dar + a.Cnda_left * dal + a.Cndr * dr",
        "var co_yaw: float = a.Cnb * beta_eff + a.Cnda_right * dar - a.Cnda_left * dal + a.Cndr * dr"),
    "fixed_strip_offset": (
        "froude", "app/physics/aero.gd",
        "var ys: PackedFloat64Array = env.station_ys\n\tvar stations := ys.size()\n\tvar station_area: float = ref.S / stations",
        "var ys: PackedFloat64Array = env.station_ys.duplicate()\n\tfor station_index: int in ys.size():\n\t\tys[station_index] += 0.03 * signf(ys[station_index])\n\tvar stations := ys.size()\n\tvar station_area: float = ref.S / stations"),
    "wing_drag_adds_energy": (
        "energy", "app/physics/aero.gd",
        # Small anti-drag exposes positive work without turning the probe into a numeric blow-up.
        "var drag_q := -0.5*rho", "var drag_q := 0.05*rho"),
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def inventory():
    paths = {ROOT/"app/project.godot", ROOT/"app/get-godot.sh"}
    for folder in ("app/physics", "app/sim", "app/input"):
        paths.update((ROOT/folder).rglob("*.gd"))
    paths.update((ROOT/"app/data/aircraft").glob("*.json"))
    paths.update(HERE.glob("*.gd"))
    paths.update(HERE.glob("*.py"))
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}


def load_report(path):
    def invalid(value):
        raise ValueError(f"nonfinite JSON constant: {value}")
    report = json.loads(path.read_text(encoding="utf-8"), parse_constant=invalid)
    require(report.get("format") == "openrc-metamorphic v1", "wrong report format")
    require(report.get("flights") == 56 and report.get("ticks_per_flight") == 240, "incomplete flight roster")
    require(set(report["groups"]) == GROUPS, "missing/unknown check group")
    require(all(row["checks"] > 0 for row in report["groups"].values()), "empty check group")
    require(report["groups"]["energy"]["checks"] == 7680, "incomplete energy ticks")
    require(report["failures"] == sum(row["failures"] for row in report["groups"].values()), "inconsistent failure count")
    return report


def run_engine(engine, app, script, output, expected_group=None):
    # A zero exit is insufficient: GDScript load/runtime errors can still exit zero.
    command = [engine, "--headless", "--path", str(app), "--script", str(script), "--", str(output)]
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=90)
    require(not re.search(r"^(?:SCRIPT |SHADER )?ERROR:|^WARNING:", result.stdout, re.M), "engine diagnostics:\n"+result.stdout[:4000])
    require(output.exists(), "engine produced no report:\n"+result.stdout[:4000])
    report = load_report(output)
    if expected_group is None:
        require(result.returncode == 0 and report["failures"] == 0, "baseline failed:\n"+result.stdout[:4000])
    else:
        require(result.returncode == 1 and report["groups"][expected_group]["failures"] > 0,
                f"mutation survived or failed for the wrong reason ({expected_group}):\n"+result.stdout[:4000])
        require(report["groups"]["integrity"]["failures"] == 0 and report["groups"]["coverage"]["failures"] == 0,
                f"mutation ({expected_group}) invalidated the fixture: {report['groups']}")
    return report


def atomic_json(path, document):
    payload = json.dumps(document, indent=2, sort_keys=True, allow_nan=False)+"\n"
    name = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, delete=False) as file:
            name = Path(file.name)
            file.write(payload)
            file.flush()
            os.fsync(file.fileno())
        os.replace(name, path)
    finally:
        if name is not None:
            name.unlink(missing_ok=True)


def verify():
    before = inventory()
    engine = subprocess.check_output([str(ROOT/"app/get-godot.sh")], text=True, timeout=300).strip()
    with tempfile.TemporaryDirectory(prefix="openrc-val4-") as temp:
        temp = Path(temp)
        baseline = run_engine(engine, ROOT/"app", HERE/"checks.gd", temp/"baseline.json")
        copy = temp/"copy"
        shutil.copytree(ROOT/"app", copy/"app", ignore=shutil.ignore_patterns(".godot", "captures", "__pycache__"))
        script = copy/"checks.gd"
        shutil.copy2(HERE/"checks.gd", script)
        require(inventory() == before, "source changed during copy; retry on a stable snapshot")
        control = run_engine(engine, copy/"app", script, temp/"control.json")
        require(control == baseline, "isolated control does not match the live baseline")
        mutations = {}
        for name, (group, relative, old, new) in MUTATIONS.items():
            path = copy/relative
            original = path.read_text(encoding="utf-8")
            require(original.count(old) == 1, f"mutation anchor changed: {name}")
            try:
                path.write_text(original.replace(old, new), encoding="utf-8")
                mutations[name] = {"expected_group": group, "file": relative, "old": old, "new": new,
                                   "report": run_engine(engine, copy/"app", script, temp/(name+".json"), group)}
            finally:
                path.write_text(original, encoding="utf-8")
        require(inventory() == before, "source changed during verification; previous report preserved")
        return {"format": "openrc-metamorphic-proof v1", "input_sha256": before, "baseline": baseline,
                "isolated_control_identical": True, "mutations": mutations, "source_files_unchanged": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="save full evidence only after all checks and mutations pass")
    args = parser.parse_args()
    try:
        report = verify()
        if args.output:
            atomic_json(args.output, report)
        print(f"VAL-4 PASS: {report['baseline']['flights']} flights; 3/3 mutations rejected; source files unchanged")
        for group, row in report["baseline"]["groups"].items():
            print(f"  {group}: {row['checks']} checks, maximum error {row['max_error']:.6g}, limit {row['limit']:.6g}")
        return 0
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(f"VAL-4: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
