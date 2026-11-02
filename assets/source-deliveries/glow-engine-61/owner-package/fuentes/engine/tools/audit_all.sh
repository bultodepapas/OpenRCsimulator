#!/usr/bin/env bash
# One-command audit of a built SE model against the owner's photos:
#   photo cameras -> per-view Cycles renders + zone outlines (mm) -> colour (Lab) per zone -> mesh health
# usage: tools/audit_all.sh MODEL.blend OUTDIR [samples] [pct]
set -u
E=/home/claude/engine
B="python3 /home/claude/tools/blender"
M=$1; O=$2; SMP=${3:-24}; PCT=${4:-50}
mkdir -p "$O"
$B -b "$M" --python $E/tools/add_photo_cams.py -- --save "$O/model_photo_cams.blend" > "$O/log.txt" 2>&1
$B -b "$O/model_photo_cams.blend" --python $E/tools/audit_views.py -- --out "$O" --views A Ac B B2 D E T \
   --samples "$SMP" --pct "$PCT" >> "$O/log.txt" 2>&1
python3 $E/tools/color_check.py "$O" A Ac B B2 D E T > "$O/color.txt" 2>&1
$B -b "$M" --python $E/tools/mesh_defects.py -- --out "$O/mesh_defects.json" >> "$O/log.txt" 2>&1
python3 - "$O" <<'EOF'
import json, sys
import numpy as np
O = sys.argv[1]
m = json.load(open(f"{O}/metrics.json"))
m = m.get("metrics", m)
c = json.load(open(f"{O}/color.json"))
zones = ["head", "cyl", "case", "drive", "carb", "muf"]
rows = {}
for z in zones:
    med = [v[z]["median_mm"] for v in m.values() if z in v]
    p90 = [v[z]["p90_mm"] for v in m.values() if z in v]
    de = [v[z]["dE"] for v in c.values() if z in v]
    dl = [v[z]["dL"] for v in c.values() if z in v]
    rows[z] = {"median_mm": round(float(np.mean(med)), 2) if med else None, "p90_mm": round(float(np.mean(p90)), 2) if p90 else None,
               "dE": round(float(np.mean(de)), 1) if de else None, "dL": round(float(np.mean(dl)), 1) if dl else None}
d = json.load(open(f"{O}/mesh_defects.json"))
summary = {"zones": rows, "mesh_defects": d or "none"}
json.dump(summary, open(f"{O}/summary.json", "w"), indent=1)
print(json.dumps(summary, indent=1))
EOF
