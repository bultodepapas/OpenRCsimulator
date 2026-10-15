"""Re-run the preserved independent Jacobian/SciPy method in an identified app copy."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

import numpy as np
import scipy

from run_fixture_checks import identity

ROOT = Path(__file__).resolve().parents[3]
METHOD_DIR = ROOT / "docs/research/physics-audit-2026-10-14/remediation/R02-modes"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    app, godot, out = args.app.resolve(), args.godot.resolve(), args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    if np.__version__ != "2.4.6" or scipy.__version__ != "1.17.1":
        raise RuntimeError("This reference uses the recorded NumPy 2.4.6 / SciPy 1.17.1 toolchain")
    module_path = METHOD_DIR / "mode_reference.py"
    spec = importlib.util.spec_from_file_location("preserved_mode_method", module_path)
    method = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(method)
    probe = METHOD_DIR / "manual_mode_probe.gd"
    before = identity(app)
    command = [str(godot), "--headless", "--path", str(app), "--audio-driver", "Dummy",
               "--script", str(probe)]
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, timeout=60)
    (out / "probe.log").write_text(result.stdout, encoding="utf-8")
    errors = [line for line in result.stdout.splitlines()
              if line.startswith(("ERROR:", "SCRIPT ERROR:", "FAIL"))]
    records = []
    for line in result.stdout.splitlines():
        if not line.startswith("MODE_REF_JSON="):
            continue
        row = json.loads(line.partition("=")[2])
        metrics = {}
        for step in method.STEP_KEYS:
            matrix = np.asarray(row["jacobians"][step], dtype=np.float64)
            if matrix.shape != (9, 9) or not np.isfinite(matrix).all():
                raise ValueError("Probe returned an invalid independent Jacobian")
            metrics[step] = method._metrics(matrix, row["speed_mps"], row["wake_length_m"])
        manual = np.asarray(row["jacobians"]["1.0e-06"])
        production = np.asarray(row["production_jacobian"])
        row["manual_vs_production_jacobian_inf_norm"] = float(np.linalg.norm(manual - production, ord=np.inf))
        row["independent_metrics"] = metrics
        row["metric_deltas_from_production"] = {
            key: metrics["1.0e-06"][key] - value for key, value in row["production_modes"].items()
            if key in metrics["1.0e-06"] and isinstance(value, (int, float))}
        records.append(row)
    after = identity(app)
    drift = [p for p in sorted(before.keys() | after.keys()) if before.get(p) != after.get(p)]
    ok = result.returncode == 0 and not errors and not drift and len(records) == 3
    if ok:
        ok = all(r["manual_vs_production_jacobian_inf_norm"] < 1e-9
                 and max(map(abs, r["metric_deltas_from_production"].values())) < 1e-9 for r in records)
    report = {"ok": ok, "command": command, "exit_code": result.returncode, "engine_errors": errors,
              "source_before": before, "source_after": after, "source_drift": drift,
              "probe_sha256": sha(probe), "method_sha256": sha(module_path),
              "runner_sha256": sha(Path(__file__)), "godot_sha256": sha(godot),
              "numpy_version": np.__version__, "scipy_version": scipy.__version__, "records": records}
    (out / "mode-reference.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"ok": ok, "source_drift": drift, "cases": [
        {"speed_mps": r["speed_mps"], "spiral_1_s": r["independent_metrics"]["1.0e-06"]["spiral_eigenvalue_1_s"],
         "manual_vs_production_jacobian_inf_norm": r["manual_vs_production_jacobian_inf_norm"]} for r in records]}))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
