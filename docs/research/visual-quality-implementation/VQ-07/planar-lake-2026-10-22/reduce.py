"""Reduce retained observations; requires the existing NumPy/Pillow tools."""
from pathlib import Path
import json
import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
for mode in ("high-control", "high-planar"):
    report = json.loads((HERE / mode / "report.json").read_text())
    assert report["complete"]
    wall = [row["wall_ms"] for row in report["timing"]["samples_wall_cpu_gpu_ms"]]
    print(mode, len(wall), "wall p50/p95/p99 ms:", np.percentile(wall, [50, 95, 99]))
for mode, previous in (("high-control", "high-jet"), ("standard-gate", "standard-jet")):
    a = np.asarray(Image.open(HERE / mode / "edited.png")).astype(int)
    b = np.asarray(Image.open(HERE.parent / "lake-refresh-2026-10-22" / previous / "edited.png")).astype(int)
    delta = np.abs(a - b)
    print(mode, "changed pixels:", np.any(delta, axis=2).sum(), "maximum /255:", delta.max())
