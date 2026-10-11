#!/usr/bin/env python3
"""E5b Linux contact verification; synthetic fixtures, no physical acceptance."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[3]
REL = Path("research/ground-contact/e5b")
GROUND = Path("app/physics/ground_contact.gd")


def identities(paths):
    return {str(p): hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths}


def checked_program(root, godot, output, name, quick=False, expected_marker=None):
    command = [str(godot), "--headless", "--path", str(root / "app"), "--script",
               str(root / REL / "checks.gd"), "--", "--out=" + str(output / (name + ".json"))]
    if quick:
        command.append("--quick")
    result = subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=300,
                            env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))
    log = result.stdout + result.stderr
    (output / (name + ".log")).write_text(log)
    if re.search(r"(?:SCRIPT ERROR:|ERROR:|Parse Error:)", log):
        raise RuntimeError("engine error: " + name)
    summaries = re.findall(r"(\d+) checks, (\d+) failed", log)
    if len(summaries) != 1:
        raise RuntimeError("missing or duplicate completed summary: " + name)
    count, failed = map(int, summaries[0])
    detail = json.loads((output / (name + ".json")).read_text())
    if detail["scope"] != ("static-and-patch" if quick else "full") or (count, failed) != (detail["checks"], detail["failures"]):
        raise RuntimeError("inconsistent report: " + name)
    if count <= 0 or (result.returncode != 0 or failed != 0) and expected_marker is None:
        raise RuntimeError("checks failed: " + name)
    if expected_marker is not None:
        failures = [line for line in log.splitlines() if line.startswith("FAIL ")]
        if result.returncode == 0 or failed == 0 or not any(expected_marker in line for line in failures):
            raise RuntimeError("mutation missed intended assertion: " + name)
    return {"checks": count, "failures": failed, "exit_code": result.returncode,
            "scope": detail["scope"], "expected_failure": expected_marker}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True, help="new output directory")
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--mutations", action="store_true")
    args = parser.parse_args()
    godot = (args.godot or Path(subprocess.check_output([str(ROOT / "app/get-godot.sh")], text=True).strip())).resolve()
    output = args.out.resolve()
    output.mkdir(parents=True, exist_ok=False)
    paths = sorted({Path("app/project.godot"), REL / "checks.gd", REL / "verify.py",
                    Path("app/data/aircraft/gp_extra_300s_60.json"), Path("app/data/aircraft/p51d_mustang_120.json"),
                    *[p.relative_to(ROOT) for folder in ("physics", "sim") for p in (ROOT / "app" / folder).rglob("*.gd")]})
    before = identities(paths)
    results = {"full": checked_program(ROOT, godot, output, "full")}
    if args.mutations:
        with tempfile.TemporaryDirectory(prefix="openrc-e5b-mutations-") as directory:
            clone = Path(directory) / "repo"
            subprocess.run(["git", "clone", "--shared", "--quiet", str(ROOT), str(clone)], check=True)
            # Exercise the exact current inputs even before this step is committed.
            for path in paths:
                (clone / path).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / path, clone / path)
            results["clone_control"] = checked_program(clone, godot, output, "clone-control", quick=True)
            original = (clone / GROUND).read_text()
            mutations = {
                "pitch_arm": ("out[4] += r[2] * fx - r[0] * fz", "out[4] += 0.8 * r[2] * fx - r[0] * fz",
                              "main-only pitch moment follows"),
                "uncapped_drag": ("f_long *= mu_n / f_t", "f_long *= 1.0",
                                  "friction cap below threshold"),
                "ignored_patch": ("c *= surfaces[i + 5]", "c *= 1.0",
                                  "patch lookup scales longitudinal drag"),
                "cg_surface_lookup": ("surface_at(surfaces, s[RB.POS] + north[0] * r[0] + north[1] * r[1] + north[2] * r[2],",
                                      "surface_at(surfaces, s[RB.POS],", "patch lookup scales longitudinal drag"),
            }
            for name, (old, new, marker) in mutations.items():
                expected_count = 2 if name == "ignored_patch" else 1
                if original.count(old) != expected_count:
                    raise RuntimeError("mutation target changed: " + name)
                (clone / GROUND).write_text(original.replace(old, new))
                results[name] = checked_program(clone, godot, output, name, quick=True, expected_marker=marker)
                (clone / GROUND).write_text(original)
    if identities(paths) != before:
        raise RuntimeError("source inputs changed during verification; rerun on stable inputs")
    report = {"ok": True, "physical_acceptance": False, "results": results, "input_sha256": before,
              "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "godot_sha256": hashlib.sha256(godot.read_bytes()).hexdigest()}
    (output / "verification.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
