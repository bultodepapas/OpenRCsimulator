#!/usr/bin/env python3
"""Run local synthetic counterexamples; exit zero means the defects reproduced.

No live receiver, OAuth provider or GitHub API is contacted. Use an output
directory outside the checkout so the real dashboard path guards stay enabled.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    root = here.parents[2]
    output = args.out.resolve()
    if output.is_relative_to(root):
        parser.error("--out must be outside the repository")
    output.mkdir(parents=True, exist_ok=True)
    temporary = output / "temp"
    temporary.mkdir(exist_ok=True)
    env = {**os.environ, "TMPDIR": str(temporary), "TEMP": str(temporary),
           "TMP": str(temporary), "OPENRC_AUDIT_TMP": str(temporary),
           "PYTHONDONTWRITEBYTECODE": "1"}
    probes = ["integral_float_rollup.py", "publisher_race.py", "monitor_warning_probe.py",
              "backup_validation_probe.py", "ga4_credential_permissions_probe.py"]
    results = []
    for name in probes:
        if name == "ga4_credential_permissions_probe.py" and os.name != "posix":
            results.append({"probe": name, "status": "skipped", "reason": "POSIX mode semantics"})
            continue
        process = subprocess.run([sys.executable, str(here / name)], cwd=root, env=env,
                                 text=True, capture_output=True, timeout=40, check=False)
        (output / f"{Path(name).stem}.log").write_text(process.stdout + process.stderr, encoding="utf-8")
        result = {"probe": name, "exit_code": process.returncode,
                  "status": "reproduced" if process.returncode == 0 else "not_reproduced",
                  "stdout": process.stdout, "stderr": process.stderr}
        results.append(result)
        print(f"{name}: {result['status']}", flush=True)
    (output / "results.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    return 0 if all(item["status"] in {"reproduced", "skipped"} for item in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
