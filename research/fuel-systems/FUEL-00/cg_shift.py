"""Fleet fuel/CG audit: CG shift full->empty and declared->empty per aircraft (read-only).

Usage: python3 -I cg_shift.py /home/bulto/OpenRCsimulator
Capacity/density are the values written in each item's own provenance text (see CAP below);
MAC is computed from the reference block (root/tip chord for tapered, mean_chord for rectangular).
"""
import json
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])
AC = ROOT / "app/data/aircraft"

# Capacity (L) and density (kg/L) as declared in each file's provenance text; None = not declared.
CAP = {
    "jensen_ugly_stik_60": (0.300, 0.80, "fuel (half tank)", "'150 ml at ~0.8 g/ml ... half tank' => 0.30 l implied; tank '8-10 oz' (0.237-0.296 l)"),
    "gp_extra_300s_60": (0.355, 0.82, "fuel (half tank)", "'12 oz tank = 355 ml, half at 0.82 g/ml'"),
    "p51d_mustang_120": (1.000, 0.74, "fuel (half tank)", "'fuel tank 1 l', '0.5 l at 0.74 g/ml gasoline'"),
    "sebart_avanti_s_a200": (3.200, 0.80, "kerosene + 5 % oil (declared fuel state)", "'3.2 l x 0.5 x 0.8 kg/l'; smoke 1.3 l not in inventory"),
    "stik_glow_61fx_2t": (0.300, 0.80, "usable glow premix", "same base Stik item; runtime initial fuel = item mass"),
    "stik_glow_55ax_2t": (0.300, 0.80, "usable glow premix", "same"),
    "stik_glow_fs64v_4t": (0.300, 0.80, "usable glow premix", "same"),
    "stik_glow_55ax_2t_apc_13x6": (0.300, 0.80, "usable glow premix", "same"),
    "stik_glow_fs64v_4t_apc_13x6": (0.300, 0.80, "usable glow premix", "same"),
    "synthetic_stik_electric_4s": (0.300, 0.80, "fuel (half tank)", "donor mass, not a fuel system"),
}


def v(q):
    return q["value"] if isinstance(q, dict) else q


def mac_of(ref):
    planform = v(ref["planform"])
    if planform == "tapered" and "root_chord" in ref:
        cr, ct = v(ref["root_chord"]), v(ref["tip_chord"])
        lam = ct / cr
        return 2.0 / 3.0 * cr * (1 + lam + lam * lam) / (1 + lam), "MAC(taper)"
    return v(ref["mean_chord"]), "chord"


def cg(items):
    m = sum(i[0] for i in items)
    return m, [sum(i[0] * i[1][k] for i in items) / m for k in range(3)]


def main():
    rows = []
    for aid, (cap_l, rho, fuel_name, note) in CAP.items():
        d = json.loads((AC / f"{aid}.json").read_text(encoding="utf-8"))
        inv = [(v(i["mass"]), v(i["position"]), i["name"], v(i["size"])) for i in d["inventory"]]
        fuel = [x for x in inv if x[2] == fuel_name]
        assert len(fuel) == 1, (aid, fuel_name)
        mf, pf, _, sf = fuel[0]
        others = [x for x in inv if x[2] != fuel_name]
        mac, mac_kind = mac_of(d["reference"])
        plan = v(d["balance"]["plan_cg"])
        m_decl, cg_decl = cg(inv)
        m_empty, cg_empty = cg(others)
        m_full_fuel = cap_l * rho
        m_full, cg_full = cg(others + [(m_full_fuel, pf, "full", sf)])
        rows.append({
            "id": aid,
            "mac_m": round(mac, 4), "mac_kind": mac_kind,
            "plan_cg_x": plan[0], "inv_cg_x_declared": round(cg_decl[0], 5),
            "tank_x": pf[0], "tank_ahead_of_cg_mm": round((cg_decl[0] - pf[0]) * 1000, 1),
            "tank_ahead_pct_mac": round((cg_decl[0] - pf[0]) / mac * 100, 1),
            "tank_size": sf,
            "fuel_declared_kg": mf, "fuel_full_kg": round(m_full_fuel, 4),
            "declared_fill": round(mf / m_full_fuel, 3),
            "mass_declared": round(m_decl, 4), "mass_empty": round(m_empty, 4), "mass_full": round(m_full, 4),
            "fuel_frac_of_gross_full_pct": round(m_full_fuel / m_full * 100, 2),
            "dCG_full_to_empty_mm": round((cg_empty[0] - cg_full[0]) * 1000, 2),
            "dCG_full_to_empty_pctMAC": round((cg_empty[0] - cg_full[0]) / mac * 100, 2),
            "dCG_decl_to_empty_mm": round((cg_empty[0] - cg_decl[0]) * 1000, 2),
            "dCG_decl_to_empty_pctMAC": round((cg_empty[0] - cg_decl[0]) / mac * 100, 2),
            "dCG_decl_to_full_mm": round((cg_full[0] - cg_decl[0]) * 1000, 2),
            "dCGz_full_to_empty_mm": round((cg_empty[2] - cg_full[2]) * 1000, 2),
            "note": note,
        })
    # Smoke tank (Avanti): 1.3 l of smoke oil at an assumed 0.85 kg/l placed at the kero tank, if it were filled.
    d = json.loads((AC / "sebart_avanti_s_a200.json").read_text(encoding="utf-8"))
    inv = [(v(i["mass"]), v(i["position"]), i["name"]) for i in d["inventory"]]
    m0, c0 = cg(inv)
    pk = [x[1] for x in inv if x[2].startswith("kerosene")][0]
    ms = 1.3 * 0.85
    m1, c1 = cg(inv + [(ms, pk, "smoke")])
    mac, _ = mac_of(d["reference"])
    rows.append({"id": "avanti_smoke_if_full(assumed 0.85 kg/l at kero tank)", "smoke_kg": ms,
                 "dCG_mm": round((c1[0] - c0[0]) * 1000, 2), "dCG_pctMAC": round((c1[0] - c0[0]) / mac * 100, 2)})
    print(json.dumps(rows, indent=1))


if __name__ == "__main__":
    main()
