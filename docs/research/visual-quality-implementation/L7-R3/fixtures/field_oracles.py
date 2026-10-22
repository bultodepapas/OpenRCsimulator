"""L7-R3 oracles for a candidate default field: scenery layout and countryside asserts/outputs.
Usage: python3 field_oracles.py <candidate default.json>"""
import importlib.util, json, math, shutil, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[5]  # repository root
cand = Path(sys.argv[1])
def load(name, rel):
    spec = importlib.util.spec_from_file_location(name, ROOT / rel); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
sc = load("scenery_place", "tools/scenery/place.py"); sc.FIELD = cand
data, report, _ = sc.build()
print("scenery layout unchanged:", sc.dumps(data) == sc.OUT.read_text())
for name, az, sky, height, dist in report:
    top = math.degrees(math.atan2(height - sc.EYE_M, dist))
    print(f"  {name:14s} az {az:6.1f} skyline {sky:5.2f} top {top:5.2f} {'VISIBLE' if top > sky else 'hidden'}")
tmp = ROOT / "tmp/grove-oracle"; tmp.mkdir(parents=True, exist_ok=True); shutil.copy(cand, tmp / "default.json")
cs = load("bake_countryside", "tools/scenery/bake_countryside.py"); cs.FIELD = tmp / "default.json"
committed = json.loads((ROOT / "app/data/scenery/countryside.json").read_text())
try:
    out = json.loads(cs.generate())
    print("countryside:", {k: ("unchanged" if out[k] == committed[k] else "changed") for k in ("parcels", "roads", "triangles")}, "parcels", len(committed["parcels"]), "->", len(out["parcels"]))
except AssertionError as exc:
    print("countryside assertion:", exc)
shutil.rmtree(tmp)
