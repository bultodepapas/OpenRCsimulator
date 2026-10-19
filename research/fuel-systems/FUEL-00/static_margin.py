"""FUEL-00 audit: CG and static margin at full, declared and empty fuel from cg_shift.out.json.

Usage: python3 -I static_margin.py <repo root>
Neutral points are the repository's own estimates, not measurements:
  Stik 43.5 % c (docs/research/flight-dynamics/climb-trim/README.md, derive_pitch_reference.py);
  Ventage Jet: manual aft CG 260 mm taken as 3 % MAC stable (research/avanti-s/av06/inputs.json);
  P-51: 34.2 % MAC (research/p51/p51-05/derivation.md), plan CG 27 % MAC;
  Extra 300S: 42.5 % MAC, loaded half-tank CG 27.98 % MAC (research/extra-300/ex05/derivation.md).
Ventage Jet positions are from the root leading edge, so only mm and margin are meaningful there.
"""
import json
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])
rows = json.loads((ROOT / "research/fuel-systems/FUEL-00/cg_shift.out.json").read_text(encoding="utf-8"))

STIK_NP = 0.435 * 0.3048
AVANTI_NP = 0.260 + 0.03 * 0.3622
MAC_REFERRED = {"p51d_mustang_120": (34.2, 27.0), "gp_extra_300s_60": (42.5, 27.98)}

for r in rows:
    if "plan_cg_x" not in r:
        continue
    aid, mac = r["id"], r["mac_m"]
    decl = r["inv_cg_x_declared"]
    empty = decl + r["dCG_decl_to_empty_mm"] / 1000.0
    full = decl + r["dCG_decl_to_full_mm"] / 1000.0
    if aid in MAC_REFERRED:
        np_pct, plan_pct = MAC_REFERRED[aid]
        pct = [plan_pct + (x - decl) / mac * 100.0 for x in (full, decl, empty)]
        sm = [np_pct - p for p in pct]
    else:
        np_x = AVANTI_NP if aid == "sebart_avanti_s_a200" else STIK_NP
        pct = [x / mac * 100.0 for x in (full, decl, empty)]
        sm = [(np_x - x) / mac * 100.0 for x in (full, decl, empty)]
    print("%-30s CG mm full %6.1f decl %6.1f empty %6.1f | CG %%MAC %5.1f %5.1f %5.1f | SM %%MAC %4.1f %4.1f %4.1f"
          % (aid, full * 1000, decl * 1000, empty * 1000, *pct, *sm))
