"""F4U-18: combine visibility_r59.py runs into per-object, per-collection and per-g1-part visibility.

A triangle counts as visible when, in any pose, a ray hit it or a triangle in the same 4 cm full-size cell
(visibility_r59.py explains why); exact hits are kept as hit_tris. Screen coverage is the largest 1080p pixel count an
object reached in one view of its class (close 1.5 m, hero 4 m). With the author's export-map.json each R59 object
is attributed to the g1 part it was reduced into, or to "(not in g1)".

    python research/f4u-corsair/F4U-18/visibility_merge.py RUN_DIR OUT.json [EXPORT_MAP.json] [--csv OUT.csv]
"""
import csv, json, sys
from pathlib import Path
import numpy as np

run = Path(sys.argv[1])
out = Path(sys.argv[2])
export_map = Path(sys.argv[3]) if len(sys.argv) > 3 and not sys.argv[3].startswith("--") else None
poses = sorted(p.stem for p in run.glob("*.npz"))
meta = {p: json.loads((run / f"{p}.json").read_text(encoding="utf-8")) for p in poses}
names = [o["name"] for o in meta[poses[0]]["objects"]]
collections = [o["collection"] for o in meta[poses[0]]["objects"]]
hit = None
max_close = max_hero = None
seen_in = {}
for p in poses:
    data = np.load(run / f"{p}.npz")
    if hit is None:
        owner, area = data["owner"], data["area"].astype(np.float64)
        hit = np.zeros(len(owner), dtype=bool)
        cell = np.zeros(len(owner), dtype=bool)
        max_close = np.zeros(len(names), dtype=np.int64)
        max_hero = np.zeros(len(names), dtype=np.int64)
    assert np.array_equal(owner, data["owner"]) and [o["name"] for o in meta[p]["objects"]] == names
    seen_in[p] = np.bincount(owner, weights=data["hit"], minlength=len(names)) > 0
    hit |= data["hit"]
    cell |= data["cell_hit"]
    max_close = np.maximum(max_close, data["max_px_close"])
    max_hero = np.maximum(max_hero, data["max_px_hero"])
tris = np.bincount(owner, minlength=len(names))
visible = np.bincount(owner, weights=hit, minlength=len(names)).astype(np.int64)
area_total = np.bincount(owner, weights=area, minlength=len(names))
area_visible = np.bincount(owner, weights=area * cell, minlength=len(names))
cell_tris = np.bincount(owner, weights=cell, minlength=len(names)).astype(np.int64)

part_of = {}
if export_map:
    for entry in json.loads(export_map.read_text(encoding="utf-8"))["objects"]:
        if entry.get("status") == "simplified":
            part_of[entry["source"]] = entry["target"]
rows = []
for i, name in enumerate(names):
    rows.append({"name": name, "collection": collections[i], "g1_part": part_of.get(name, "(not in g1)"),
                 "tris": int(tris[i]), "hit_tris": int(visible[i]), "visible_tris": int(cell_tris[i]),
                 "visible_area_share": round(float(area_visible[i] / area_total[i]), 3) if area_total[i] else 0.0,
                 "max_px_close": int(max_close[i]), "max_px_hero": int(max_hero[i]),
                 "poses": [p for p in poses if seen_in[p][i]]})


def group(key):
    acc = {}
    for r, a, av in zip(rows, area_total, area_visible):
        g = acc.setdefault(key(r), {"objects": 0, "tris": 0, "visible_tris": 0, "area": 0.0, "visible_area": 0.0,
                                    "never_seen_objects": 0, "max_px_close_sum": 0, "max_px_close_largest": 0})
        g["objects"] += 1
        g["tris"] += r["tris"]
        g["visible_tris"] += r["visible_tris"]
        g["area"] += float(a)
        g["visible_area"] += float(av)
        g["never_seen_objects"] += r["hit_tris"] == 0
        g["max_px_close_sum"] += r["max_px_close"]
        g["max_px_close_largest"] = max(g["max_px_close_largest"], r["max_px_close"])
    for g in acc.values():
        g["visible_tri_share"] = round(g["visible_tris"] / g["tris"], 3) if g["tris"] else 0.0
        g["visible_area_share"] = round(g["visible_area"] / g["area"], 3) if g["area"] else 0.0
        g["area"] = round(g["area"], 3)
        g["visible_area"] = round(g["visible_area"], 3)
    return dict(sorted(acc.items(), key=lambda kv: -kv[1]["tris"]))


result = {"poses": {p: {k: meta[p][k] for k in ("views", "rays", "seconds", "spec")} for p in poses},
          "classes": meta[poses[0]]["classes"], "tris": int(tris.sum()), "hit_tris": int(visible.sum()),
          "visible_tris": int(cell_tris.sum()), "never_seen_objects": int((visible == 0).sum()), "objects": len(names),
          "by_collection": group(lambda r: r["collection"]), "by_g1_part": group(lambda r: r["g1_part"]),
          "rows": rows}
out.write_text(json.dumps(result, indent=1, ensure_ascii=False), encoding="utf-8")
if "--csv" in sys.argv:
    with open(sys.argv[sys.argv.index("--csv") + 1], "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["name", "collection", "g1_part", "tris", "visible_tris", "visible_area_share",
                         "max_px_close_1080p", "max_px_hero_1080p", "poses_seen"])
        for r in sorted(rows, key=lambda r: -r["tris"]):
            writer.writerow([r["name"], r["collection"], r["g1_part"], r["tris"], r["visible_tris"],
                             r["visible_area_share"], r["max_px_close"], r["max_px_hero"], " ".join(r["poses"])])
print(f"{result['visible_tris']:,} of {result['tris']:,} triangles visible "
      f"({result['visible_tris'] / result['tris']:.1%}); {result['never_seen_objects']} of {len(names)} objects never seen")
for key, g in list(result["by_collection"].items()):
    print(f"{g['tris']:>9,} {g['visible_tri_share']:6.1%} tri {g['visible_area_share']:6.1%} area "
          f"{g['max_px_close_largest']:>9,} px  {key}")
