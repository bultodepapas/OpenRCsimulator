"""Fleet neutral-point check (research only, 2026-10-19).

Applies the D6e-R1 geometric neutral-point estimate (research/flight-dynamics/climb-trim/derive_pitch_reference.py:
Helmbold slopes, tail dynamic-pressure ratio 0.9, Raymer eq. 16.25 fuselage term with K_fus 0.008/deg) to the five
catalog airframes and compares it with the neutral point their pitch data imply.

Frames: every quantity is in the aircraft JSON's le frame, x in metres aft of that file's le-frame origin (the wing
root leading edge; see each file's frames.le_frame). Angles in radians; slopes per radian.

Data margin:       SM_data = -Cma/CLa + (x_arp - x_cg)/c_ref,   x_np_data = x_arp - Cma/CLa * c_ref
Geometric NP:      x_ac_wb = x_ac_w - dx_f,   dx_f = Cma_f / CLa_w * mac,   Cma_f = K_f W^2 L / (mac S) * 180/pi
                   CLa_geo = CLa_w + a_t Sh/S,   a_t = horizontal.lift_slope = a_h eta_h (1 - deps/dalpha)
                   x_np_geo = x_ac_wb + a_t (Sh/S) (x_h - x_ac_wb) / CLa_geo
Reads only; writes nothing. Usage: python3 research/flight-dynamics/power-climb/fleet_neutral_point.py
"""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
K_F = 0.008      # Raymer Fig. 16.14 value the fleet generators use near 31-36 % body length (per deg)
ETA_H = 0.9      # tail dynamic-pressure ratio (fleet generators)
KAPPA = 0.9      # section slope / 2 pi (D6e-R1 and EX/TT generators)


def val(node):
    return node["value"]


def helmbold(aspect, kappa=KAPPA):
    return 2 * math.pi * aspect / (2 + math.sqrt((aspect / kappa) ** 2 + 4))


def load(name):
    return json.loads((ROOT / "app/data/aircraft" / name).read_text(encoding="utf-8"))


def geo(folder):
    return json.loads((ROOT / "assets/aircraft" / folder / "geometry.json").read_text(encoding="utf-8"))


def inventory_cg(data):
    inv = data["inventory"]
    mass = sum(val(i["mass"]) for i in inv)
    return sum(val(i["mass"]) * val(i["position"])[0] for i in inv) / mass, mass


def trapezoid_mac(cr, ct, semi, le_root, le_tip):
    lam = ct / cr
    mac = 2 / 3 * cr * (1 + lam + lam * lam) / (1 + lam)
    y_mac = semi / 3 * (1 + 2 * lam) / (1 + lam)
    return mac, le_root + (le_tip - le_root) * y_mac / semi


def avanti_mac(g):
    """Replicates research/avanti-s/av06/derive_physics.py strips()/planform(): area-weighted MAC LE."""
    rows = g["wing"]["stations"]
    rows = ([[0.0] + list(rows[0][1:])] if rows[0][0] > 0 else []) + [list(r) for r in rows]
    area = c2 = cle = 0.0
    n = 60
    for a, b in zip(rows, rows[1:]):
        for k in range(n):
            t = (k + 0.5) / n
            lez = a[1] + (b[1] - a[1]) * t
            c = (a[2] - a[1]) + ((b[2] - b[1]) - (a[2] - a[1])) * t
            dy = (b[0] - a[0]) / n
            area += c * dy
            c2 += c * c * dy
            cle += c * lez * dy
    return c2 / area, cle / area


def airframes():
    out = []
    # Ugly Stik (rectangular; frame origin = wing LE at the centreline). Fuselage as derive_pitch_reference.py.
    d, g = load("jensen_ugly_stik_60.json"), geo("ugly-stik-60")
    hull = dict(zip(d["crash_hull_components"], val(d["crash_hull"])))
    c = val(d["reference"]["mean_chord"])
    out.append(dict(name="Ugly Stik 60", data=d, mac=c, x_ac_w=0.25 * c, nose=hull["spinner"][0], bh=g["tail"]["span"],
                    W=2 * max(s[1] for s in g["fuselage_stations"]), L=hull["tail_end"][0] - hull["spinner"][0],
                    fus_src="crash hull spinner->tail_end; 2 x max half-width of geometry.json fuselage_stations"))
    # Timber (rectangular, measured chord 0.212854 m; D0 = root LE). ARP = generator's 25 % chord.
    d, g = load("turbo_lumber_evolution.json"), geo("turbo-lumber-evolution")
    mac = val(g["wing"]["mac"])
    nose = g["landmarks"]["nose_spinner_tip"]["measured"][2]
    out.append(dict(name="Timber", data=d, mac=mac, x_ac_w=val(g["wing"]["le_z"]) + 0.25 * mac, nose=nose, bh=val(g["tail"]["span"]),
                    W=2 * max(s[1] for s in g["fuselage"]["stations"]), L=val(g["fuselage"]["aft_end_z"]) - nose,
                    fus_src="spinner tip -> fuselage.aft_end_z; 2 x max fuselage half-width (cowl)"))
    # Extra 300S (trapezoid; le frame = model z - le_z_root).
    d, g = load("gp_extra_300s_60.json"), geo("extra-300s-60")
    w = g["wing"]
    le0 = w["le_z_root"]
    mac, mac_le = trapezoid_mac(w["root_chord"], w["tip_chord"], w["span"] / 2, w["le_z_root"], w["le_z_tip"])
    st = g["fuselage_stations"]
    out.append(dict(name="Extra 300S", data=d, mac=mac, x_ac_w=mac_le - le0 + 0.25 * mac, nose=g["spinner"]["tip_z"] - le0,
                    bh=2 * g["tail"]["stab_half_span"],
                    W=2 * max(r[1] for r in st), L=st[-1][0] - g["spinner"]["tip_z"],
                    fus_src="spinner tip -> last station (tail post); 2 x max half-width (generator's own)"))
    # Avanti S (polyline planform with 15 deg quarter-chord sweep; le frame = model z).
    d, g = load("sebart_avanti_s_a200.json"), geo("avanti-s-a200")
    mac, mac_le = avanti_mac(g)
    fs = g["fuselage_stations"]
    out.append(dict(name="Avanti S", data=d, mac=mac, x_ac_w=mac_le + 0.25 * mac, nose=fs[0][0], bh=2 * g["tail"]["stations"][-1][0],
                    W=2 * max(r[1] for r in fs), L=fs[-1][0] - fs[0][0],
                    fus_src="nose -> tail cone stations; 2 x max half-width (generator's own)"))
    # P-51D (trapezoid; le frame = model z, root LE at 0).
    d, g = load("p51d_mustang_120.json"), geo("p51d-mustang-120")
    w = g["wing"]
    mac, mac_le = trapezoid_mac(w["root_chord"], w["tip_chord"], w["span"] / 2, w["le_z_root"], w["le_z_tip"])
    st = g["fuselage_stations"]
    out.append(dict(name="P-51D", data=d, mac=mac, x_ac_w=mac_le - w["le_z_root"] + 0.25 * mac, nose=g["spinner"]["tip_z"],
                    bh=2 * g["tail"]["stab_half_span"],
                    W=2 * max(r[1] for r in st), L=st[-1][0] - g["spinner"]["tip_z"],
                    fus_src="spinner tip -> tail post station; 2 x max half-width (generator's own; belly scoop excluded)"))
    return out


def geometric_np(a, k_f=K_F, cla_w=None, x_ac_w=None, tail_slope=None):
    d = a["data"]
    ref, h = d["reference"], d["aero"]["surfaces"]["horizontal"]
    S, b = val(ref["wing_area"]), val(ref["wing_span"])
    Sh, x_h = val(h["area"]), val(h["position"])[0]
    a_t = val(h["lift_slope"]) if tail_slope is None else tail_slope
    cla_w = helmbold(b * b / S) if cla_w is None else cla_w
    x_ac_w = a["x_ac_w"] if x_ac_w is None else x_ac_w
    mac = a["mac"]
    cma_f = k_f * a["W"] ** 2 * a["L"] / (mac * S) * 180 / math.pi
    dx_f = cma_f / cla_w * mac
    x_ac = x_ac_w - dx_f
    cla = cla_w + a_t * Sh / S
    return dict(x_np=x_ac + a_t * Sh / S * (x_h - x_ac) / cla, x_ac=x_ac, dx_f=dx_f, cma_f=cma_f, cla=cla, cla_w=cla_w,
                tail_arm=x_h - x_ac, Vh=Sh * (x_h - a["x_ac_w"]) / (S * mac))


def main():
    rows = []
    for a in airframes():
        d = a["data"]
        ref, co, h = d["reference"], d["aero"]["coefficients"], d["aero"]["surfaces"]["horizontal"]
        S, b, c = val(ref["wing_area"]), val(ref["wing_span"]), val(ref["mean_chord"])
        cla, cma, cmq = val(co["CLa"]), val(co["Cma"]), val(co["Cmq"])
        x_arp = val(ref["aero_reference_point"])[0]
        x_cg, mass = inventory_cg(d)
        x_plan = val(d["balance"]["plan_cg"])[0]
        np_data = x_arp - cma / cla * c
        g0 = geometric_np(a)
        Sh = val(h["area"])
        a_t = val(h["lift_slope"])
        deps = val(h["downwash_gradient"])
        cla_w_file = cla - a_t * Sh / S
        r = dict(
            name=a["name"], c=c, mac=a["mac"], S=S, b=b, AR=b * b / S, Sh=Sh, x_h=val(h["position"])[0], a_t=a_t, deps=deps,
            a_h_free=a_t / (ETA_H * (1 - deps)), CLa=cla, Cma=cma, Cmq=cmq, x_arp=x_arp, x_cg=x_cg, x_plan=x_plan,
            mass=mass, np_data=np_data, sm_data=(np_data - x_cg) / c, sm_data_plan=(np_data - x_plan) / c,
            x_ac_w=a["x_ac_w"], W=a["W"], L=a["L"], qc_frac=(a["x_ac_w"] - a["nose"]) / a["L"], fus_src=a["fus_src"],
            cla_w=g0["cla_w"], cla_w_file=cla_w_file, cla_geo=g0["cla"], cma_f=g0["cma_f"], dx_f=g0["dx_f"],
            x_ac=g0["x_ac"], Vh=g0["Vh"], np_geo=g0["x_np"], sm_geo=(g0["x_np"] - x_cg) / c,
            sm_geo_plan=(g0["x_np"] - x_plan) / c,
            np_nofus=geometric_np(a, k_f=0.0)["x_np"],
            np_k_lo=geometric_np(a, k_f=0.7 * K_F)["x_np"], np_k_hi=geometric_np(a, k_f=1.3 * K_F)["x_np"],
            np_filecla=geometric_np(a, cla_w=cla_w_file)["x_np"],
            np_naive=geometric_np(a, x_ac_w=0.25 * c)["x_np"],
            np_helm_tail=geometric_np(a, tail_slope=helmbold(a["bh"] ** 2 / Sh) * ETA_H * (1 - deps))["x_np"],
            a_t_helm=helmbold(a["bh"] ** 2 / Sh) * ETA_H * (1 - deps),
            mac_le=a["x_ac_w"] - 0.25 * a["mac"], CLq=val(co["CLq"]),
            cmq_src=co["Cmq"]["source"][:160],
        )
        r["cmq_cg_eff"] = cmq + r["CLq"] * (x_cg - x_arp) / c
        r["sm_geo_helm"] = (r["np_helm_tail"] - x_cg) / c
        r["d_np"] = r["np_data"] - r["np_geo"]
        rows.append(r)
    return rows


def tables(rows):
    """Markdown tables for docs/research/flight-dynamics/power-climb-2026-10-19/neutral-point-check.md (positions in m, le frame; margins in % of c_ref)."""
    pct = lambda x: f"{100 * x:+.1f}"
    out = ["| Aircraft | c_ref (m) | CLa (1/rad) | Cma (1/rad) | Cmq (1/rad) | x_arp (m) | x_cg loader, wet (m) | x_plan_cg, dry (m) "
           "| NP data (m) | SM data wet / dry (% c_ref) | NP geo (m) | SM geo wet / dry (% c_ref) | NP data - geo |",
           "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for r in rows:
        c = r["c"]
        out.append(f"| {r['name']} | {c:.4f} | {r['CLa']:.3f} | {r['Cma']:.3f} | {r['Cmq']:.3f} | {r['x_arp']:.4f} | {r['x_cg']:.4f} | "
                   f"{r['x_plan']:.4f} | {r['np_data']:.4f} | {pct(r['sm_data'])} / {pct(r['sm_data_plan'])} | {r['np_geo']:.4f} | "
                   f"{pct(r['sm_geo'])} / {pct(r['sm_geo_plan'])} | {1000 * r['d_np']:+.1f} mm ({pct(r['d_np'] / c)} % c) |")
    out += ["", "| Aircraft | S (m2) | b (m) | AR | MAC (m) | MAC LE (m) | x_ac wing (m) | CLa_w Helmbold / file (1/rad) | Sh (m2) | x_h (m) "
            "| a_t file (1/rad) | a_h free implied (1/rad) | deps/dalpha | V_h | W x L (m) | root c/4 at % body | Cma_f (1/rad, MAC) "
            "| dx_f (mm) | x_ac wing-body (m) | CLa geo (1/rad) |",
            "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for r in rows:
        out.append(f"| {r['name']} | {r['S']:.4f} | {r['b']:.4f} | {r['AR']:.2f} | {r['mac']:.4f} | {r['mac_le']:.4f} | {r['x_ac_w']:.4f} | "
                   f"{r['cla_w']:.3f} / {r['cla_w_file']:.3f} | {r['Sh']:.4f} | {r['x_h']:.4f} | {r['a_t']:.3f} | {r['a_h_free']:.2f} | "
                   f"{r['deps']:.3f} | {r['Vh']:.3f} | {r['W']:.3f} x {r['L']:.3f} | {100 * r['qc_frac']:.0f} | {r['cma_f']:.3f} | "
                   f"{1000 * r['dx_f']:.1f} | {r['x_ac']:.4f} | {r['cla_geo']:.3f} |")
    out += ["", "| Aircraft | NP geo, no fuselage | K_f x0.7 / x1.3 | wing CLa from file | Helmbold tail slope (a_t) "
            "| wing ac at 0.25 c_ref from origin | NP data / geo (% MAC) | CLq | Cmq about CG in oracle |",
            "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for r in rows:
        c, mac, le = r["c"], r["mac"], r["mac_le"]
        out.append(f"| {r['name']} | {r['np_nofus']:.4f} | {r['np_k_lo']:.4f} / {r['np_k_hi']:.4f} | {r['np_filecla']:.4f} | "
                   f"{r['np_helm_tail']:.4f} ({r['a_t_helm']:.3f}) | {r['np_naive']:.4f} | "
                   f"{100 * (r['np_data'] - le) / mac:.1f} / {100 * (r['np_geo'] - le) / mac:.1f} | {r['CLq']:.3f} | {r['cmq_cg_eff']:.3f} |")
    return "\n".join(out)


if __name__ == "__main__":
    rows = main()
    for r in rows:
        print(f"== {r['name']}")
        for k, v in r.items():
            if k != "name":
                print(f"   {k:14s} {v:.6g}" if isinstance(v, float) else f"   {k:14s} {v}")
    print()
    print(tables(rows))
