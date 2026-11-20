"""Scratch: rerun the matrix static rows with the installed native kernel (ids prefixed nk-) and compare."""
import json
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_matrix as matrix  # noqa: E402

IDS = ["static-compat", "static-fp-vk", "static-fp-d3d12", "static-mobile-vk", "static-mobile-d3d12",
       "static-res2160-compat", "static-res2160-fp-vk"]
specs = {row["id"]: row for row in matrix.ROWS}
summary_path = matrix.EVIDENCE / "summary.json"
results = json.loads(summary_path.read_text())


def physics(rid):
    raw = json.loads((matrix.RAW / f"{rid}.json").read_text())
    steps = [float(v) for v in raw["raw_metrics"].get("physics_step_usec", []) if float(v) > 0]
    return statistics.median(steps) if steps else None, raw.get("backend")


for rid in IDS:
    spec = dict(specs[rid], id="nk-" + rid)
    result = matrix.run(spec)
    results[spec["id"]] = result
    summary_path.write_text(json.dumps(results, indent=1), encoding="utf-8")
    old_step, old_backend = physics(rid)
    new_step, new_backend = physics("nk-" + rid)
    print(f"{rid}: wall p50 {results[rid]['wall_p50']:.2f} -> {result.get('wall_p50') or float('nan'):.2f} ms, "
          f"p99 {results[rid]['wall_p99']:.2f} -> {result.get('wall_p99') or float('nan'):.2f}; "
          f"physics_step median {old_step} -> {new_step} usec; backend {old_backend} -> {new_backend}; "
          f"valid {result.get('diagnosis_valid')} exit {result.get('exit')}", flush=True)
matrix.main.__globals__["ROWS"] = []  # no further runs; only rewrite the CSV from the summary
sys.argv = [sys.argv[0], "__none__"]
matrix.main()
