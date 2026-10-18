"""AUD-12: fleet loudness table from source-level bench sweeps.

Usage: python3 tools/audio/fleet_loudness.py <prefix> [<prefix> ...] [--reference=<aircraft id>] [--out=table.json]
Each <prefix> is a `bench.sh ... sweep --engine-only --audio-delay=off --audio-absorption=off` capture.
For the `full` and `idle` stages it reports the ungated K-weighted level normalised to 100 m by inverse
distance (the D4 method), relative to the reference aircraft. A stage containing crash or paused frames
is reported as invalid instead of measured. Mixer diagnostics, not calibrated acoustics.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bench_analyze  # noqa: E402


def stage_level(report: dict, analysis: dict, stage: str) -> dict:
    seg = next((s for s in analysis["segments"] if s["stage"] == stage), None)
    if seg is None:
        return {"valid": False, "reason": "stage missing"}
    cols = {name: i for i, name in enumerate(report["columns"])}
    f0, f1 = int(round(seg["t0"] * report["fps"])), int(round(seg["t1"] * report["fps"]))
    rows = report["rows"][f0:f1]
    if any(r[cols["crash"]] for r in rows):
        return {"valid": False, "reason": "crashed during the stage"}
    if any(r[cols["paused"]] for r in rows):
        return {"valid": False, "reason": "paused during the stage"}
    at_100 = seg["k_level_db"] + 20.0 * math.log10(seg["distance_m"] / 100.0)
    return {"valid": True, "k_at_100m_db": round(at_100, 1), "k_db": seg["k_level_db"],
            "distance_m": round(seg["distance_m"], 1), "rpm": round(seg["rpm"]), "centroid_hz": seg["centroid_hz"]}


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    options = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
    reference = options.get("reference", "jensen-das-ugly-stik-60")
    table = []
    for prefix in map(Path, args):
        report = json.loads(prefix.with_suffix(".json").read_text())
        flags = report.get("arguments", {})
        source_level = flags.get("engine-only") and flags.get("audio-delay") == "off" and flags.get("audio-absorption") == "off"
        analysis = bench_analyze.analyze(prefix)
        table.append({"aircraft": report["aircraft"], "source_level": bool(source_level),
                      "full": stage_level(report, analysis, "full"), "idle": stage_level(report, analysis, "idle")})
    ref = next((t for t in table if t["aircraft"] == reference), None)
    ref_full = ref["full"].get("k_at_100m_db") if ref and ref["full"]["valid"] else None
    print(f"{'aircraft':32s} {'full @100 m':>12s} {'vs ref':>7s} {'idle @100 m':>12s} {'vs ref full':>12s}  notes")
    for t in table:
        cells = []
        for stage in ("full", "idle"):
            s = t[stage]
            if s["valid"]:
                rel = f"{s['k_at_100m_db'] - ref_full:+.1f}" if ref_full is not None else "n/a"
                cells += [f"{s['k_at_100m_db']:.1f} dB", rel]
            else:
                cells += ["invalid", "—"]
        notes = "; ".join(f"{st}: {t[st]['reason']}" for st in ("full", "idle") if not t[st]["valid"])
        if not t["source_level"]:
            notes = (notes + "; " if notes else "") + "not a source-level capture"
        print(f"{t['aircraft']:32s} {cells[0]:>12s} {cells[1]:>7s} {cells[2]:>12s} {cells[3]:>12s}  {notes}")
    if "out" in options:
        Path(options["out"]).write_text(json.dumps({"reference": reference, "rows": table}, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
