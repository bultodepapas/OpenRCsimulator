#!/usr/bin/env python3
"""Plot the captured FS-64V spectra; no simulator execution or mode assignment."""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", type=Path)
parser.add_argument("destination", type=Path)
args = parser.parse_args()
data = json.loads(args.source.read_text())
rows = sorted((row for row in data["cases"] if row["aircraft"] == "fs64v"
               and not row["diagnostic_instantaneous_downwash"]), key=lambda row: row["speed_mps"])
speed = [row["speed_mps"] for row in rows]
full = [row["full_slowest_real"]["real"] for row in rows]
block = [row["lateral_slowest_real"]["real"] for row in rows]
plt.rcParams.update({"font.size": 11, "svg.hashsalt": "openrc-ugly-followup-01"})
fig, axis = plt.subplots(figsize=(9, 5.2), layout="constrained")
axis.plot(speed, full, "o-", color="#9c3b13", label="Full matrix: largest real eigenvalue")
axis.plot(speed, block, "s-", color="#17658b", label="Lateral block: largest real eigenvalue")
axis.axhline(0, color="#475569", linewidth=1, linestyle="--")
axis.set(xlabel="Reference trim speed (m/s)", ylabel="Real eigenvalue (1/s)",
         title="FS-64V: the diagonal block omits a growing coupled mode")
axis.grid(alpha=0.2)
axis.legend(loc="center right", frameon=True)
axis.annotate("20 m/s: +0.05705 /s", xy=(20, full[speed.index(20.0)]),
              xytext=(16, 0.079), arrowprops={"arrowstyle": "-", "color": "#9c3b13"}, color="#9c3b13")
axis.set_ylim(-0.063, 0.094)
fig.text(0.02, -0.045,
         "Captured simulator Jacobians; frozen controls/RPM, fixed reference mass and sea-level air.\n"
         "The two roots are selected separately, not identified as the same physical mode. No nonlinear or physical flight claim.",
         fontsize=9, color="#334155")
args.destination.parent.mkdir(parents=True, exist_ok=True)
metadata = {"Date": None} if args.destination.suffix.lower() == ".svg" else None
fig.savefig(args.destination, bbox_inches="tight", metadata=metadata)
plt.close(fig)
print(args.destination)
