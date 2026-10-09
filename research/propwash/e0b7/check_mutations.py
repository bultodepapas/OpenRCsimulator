#!/usr/bin/env python3
"""Run deliberate E0b7 faults only in disposable copies; preserve the working tree."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


HERE = Path(__file__).resolve().parent
MUTATIONS = {
    "subtract_bound": ('b = last["bound"] + first["bound"]', 'b = last["bound"] - first["bound"]'),
    "ignore_clearance_error": ('s["nose_clearance"]["value"] - s["nose_clearance"]["bound"] > 0',
                               's["nose_clearance"]["value"] > 0'),
    "allow_split_leakage": ('identity not in partition or partition[identity] == role', 'True'),
    "ignore_source_hash": ('actual == digest, "source SHA-256 mismatch: "', 'True, "source SHA-256 mismatch: "'),
}


def main():
    results = {}
    original = (HERE / "reduce.py").read_text()
    with tempfile.TemporaryDirectory(prefix="openrc-e0b7-mutations-") as directory:
        root = Path(directory)
        for filename in ("test_reduce.py", "example.synthetic.json"):
            shutil.copy2(HERE / filename, root / filename)
        for name in ("control", *MUTATIONS):
            source = original
            if name != "control":
                before, after = MUTATIONS[name]
                if original.count(before) != 1:
                    raise ValueError("mutation target is not unique: " + name)
                source = original.replace(before, after)
            (root / "reduce.py").write_text(source)
            # Disable bytecode so close-in-time rewrites cannot reuse a cached mutant.
            result = subprocess.run([sys.executable, "-B", str(root / "test_reduce.py")],
                                    capture_output=True, text=True, timeout=60)
            expected = (result.returncode == 0 and "\nOK\n" in result.stderr) if name == "control" else (
                result.returncode != 0 and "FAIL:" in result.stderr and "\nERROR:" not in result.stderr)
            results[name] = {"exit_code": result.returncode, "expected_result": expected,
                             "test_log": result.stderr}
    print(json.dumps(results, indent=2, sort_keys=True))
    return 0 if all(r["expected_result"] for r in results.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
