#!/usr/bin/env python3
"""D4-R2: verify original false convergence and isolated matrix/overflow defects."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[4]
BASELINE = "0a496184ab0c583d6c67dd211ad076d9ca01ae62"
MUTATIONS = {
    "accept_overflowed_solution": ("if not is_finite(x[i]):", "if false:", "back substitution overflow refused"),
    "ignore_extra_rows": ("a_in.size() != n", "a_in.size() < n", "malformed square matrix"),
    "ignore_extra_columns": ("row.size() != n", "row.size() < n", "malformed square matrix"),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=ROOT/"app")
    parser.add_argument("--test-file", type=Path)
    args = parser.parse_args()
    godot = subprocess.check_output([str(ROOT/"app/get-godot.sh")], text=True, timeout=300).strip()
    test_file = args.test_file or args.app/"tests/test_trim_integrity.gd"
    with tempfile.TemporaryDirectory(prefix="openrc-d4r2-mutations-") as temporary:
        app = Path(temporary)/"app"
        shutil.copytree(args.app, app, ignore=shutil.ignore_patterns(".godot", "captures"))
        shutil.copyfile(test_file, app/"tests/test_trim_integrity.gd")
        trim = app/"physics/trim.gd"
        original = trim.read_text()

        def run(repro=False):
            command = [godot, "--headless", "--path", str(app), "--script", "res://tests/test_trim_integrity.gd"]
            if repro:
                command += ["--", "--repro"]
            result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30)
            if re.search(r"^(?:SCRIPT |SHADER )?ERROR:", result.stdout, re.M):
                raise RuntimeError(result.stdout)
            return result

        control = run()
        if control.returncode != 0:
            raise RuntimeError("positive control failed:\n"+control.stdout)
        evidence = {"positive_control": control.stdout, "mutations": {}}
        baseline = subprocess.check_output(["git", "show", BASELINE+":app/physics/trim.gd"], cwd=ROOT)
        trim.write_bytes(baseline)
        old = run(repro=True)
        if old.returncode != 1 or "FAIL NaN gravity refuses with reason" not in old.stdout or "FAIL NaN linear RHS" not in old.stdout or "FAIL valid baseline control" in old.stdout:
            raise RuntimeError("original defect was not reproduced:\n"+old.stdout)
        evidence["original_defect"] = {"commit": BASELINE, "exit_code": old.returncode, "output": old.stdout}
        for name, (before, after, assertion) in MUTATIONS.items():
            if original.count(before) != 1:
                raise ValueError("mutation target changed: "+name)
            trim.write_text(original.replace(before, after))
            result = run()
            if result.returncode != 1 or "FAIL "+assertion not in result.stdout:
                raise RuntimeError("mutation survived or failed incorrectly: "+name+"\n"+result.stdout)
            evidence["mutations"][name] = {"exit_code": result.returncode, "output": result.stdout}
        print(json.dumps(evidence, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
