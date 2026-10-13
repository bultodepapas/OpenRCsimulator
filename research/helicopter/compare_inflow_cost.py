"""HELI-09a: paired, isolated bisection/Newton timing of the same target law.

The reference candidate differs only in the scalar root loop. Both variants
must pass the same independent oracle before timing. Outputs need a fresh path.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import shutil
import statistics
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    godot = args.godot.resolve()
    source = (ROOT / "app/physics/rotorcraft/inflow.gd").read_text(encoding="utf-8")
    begin_anchor = "\tvar v: float = 0.5 * (lo + hi) if lo > 0.0"
    end_anchor = "\tvar den: float = x * x + (z + v) * (z + 2.0 * v)"
    if source.count(begin_anchor) != 1 or source.count(end_anchor) != 1:
        raise RuntimeError("root-loop comparison anchors drifted")
    begin, end = source.index(begin_anchor), source.index(end_anchor)
    bisection = source[:begin] + (
        "\tfor _pass: int in range(ROOT_PASSES):\n"
        "\t\tvar mid: float = 0.5 * (lo + hi)\n"
        "\t\tif _residual(mid, z, x) > 0.0:\n"
        "\t\t\thi = mid\n"
        "\t\telse:\n"
        "\t\t\tlo = mid\n"
        "\tvar v: float = 0.5 * (lo + hi)\n"
    ) + source[end:]
    variants: dict[str, Path] = {}
    for name, code in (("bisection", bisection), ("newton", source)):
        app = out / name / "app"
        for relative in ("physics/math3d.gd", "tests/test_heli_inflow.gd"):
            target = app / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / "app" / relative, target)
        (app / "physics/rotorcraft").mkdir()
        (app / "physics/rotorcraft/inflow.gd").write_text(code, encoding="utf-8")
        shutil.copy2(ROOT / "research/helicopter/bench_inflow.gd", app / "bench.gd")
        (app / "project.godot").write_text("config_version=5\n", encoding="utf-8")
        variants[name] = app

    def run(name: str, script: str, label: str, *extra: str) -> str:
        result = subprocess.run([str(godot), "--headless", "--path", str(variants[name]),
                                 "--audio-driver", "Dummy", "--script", script, *extra],
                                capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=60)
        output = result.stdout + result.stderr
        (out / f"{label}.log").write_text(output, encoding="utf-8")
        if result.returncode != 0 or "ERROR:" in output:
            raise RuntimeError(f"{label} failed; see log")
        return output

    oracle = ROOT / "research/helicopter/reference/oracle.json"
    for name in variants:
        run(name, "res://tests/test_heli_inflow.gd", f"{name}-oracle", "--", f"--oracle={oracle}")
    timings: dict[str, list[dict]] = {name: [] for name in variants}
    # Alternate order to reduce drift; four runs per variant, no parallel timing.
    for index, name in enumerate(("bisection", "newton", "newton", "bisection") * 2):
        output = run(name, "res://bench.gd", f"timing-{index}-{name}")
        record = next(json.loads(line) for line in output.splitlines() if line.startswith('{"cpu"'))
        timings[name].append(record)
    rows = []
    for index, fixture in enumerate(timings["newton"][0]["rows"]):
        values = {name: [r["rows"][index]["median_us_per_call"] for r in runs] for name, runs in timings.items()}
        rows.append({"regime": fixture["regime"],
                     "bisection_median_us": statistics.median(values["bisection"]),
                     "newton_median_us": statistics.median(values["newton"]),
                     "per_run_medians": values})
    report = {"scope": "paired isolated target-law batch means; not whole-tick or target-host acceptance",
              "host": {key: timings["newton"][0][key] for key in ("cpu", "os", "godot")}, "rows": rows}
    (out / "summary.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
