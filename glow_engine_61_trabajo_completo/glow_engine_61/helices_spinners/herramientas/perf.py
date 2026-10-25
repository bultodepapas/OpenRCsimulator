"""Static operating point of the APC Sport props on the O.S. 61SF from APC's own performance files (PER3_*.dat):
Ct, Cp at V = 0 per RPM block; engine torque taken constant near full throttle and calibrated on the
reported 11x7 static rpm (10 600 rpm with the stock muffler, RCU); each prop then turns where its torque
matches. python3 perf.py out.json"""
import json, math, re, sys
D = "/home/claude/props/ext/apc_props/perf_data/PERFILES2"
RHO = 1.225


def static_table(name):
    txt = open(f"{D}/PER3_{name}.dat", encoding="latin1").read()
    out = {}
    for blk in re.split(r"PROP RPM =", txt)[1:]:
        rpm = int(blk.split()[0])
        for line in blk.splitlines():
            p = line.split()
            if len(p) >= 15 and p[0] == "0.00":
                out[rpm] = dict(ct=float(p[3]), cp=float(p[4]), hp=float(p[5]), thrust_lbf=float(p[7]),
                                thrust_n=float(p[10]), torque_nm=float(p[9]))
                break
    return out


def at(tab, rpm, key):
    ks = sorted(tab)
    for a, b in zip(ks, ks[1:]):
        if a <= rpm <= b:
            t = (rpm - a) / (b - a)
            return tab[a][key] + t * (tab[b][key] - tab[a][key])
    return tab[ks[-1]][key]


PROPS = {"APC_11x7": ("11x7", 11.0), "APC_11x8": ("11x8", 11.0), "APC_12x6": ("12x6", 12.0),
         "APC_12x7": ("12x7", 12.0), "APC_12.5x6": ("125x6", 12.5)}
T = {k: static_table(v[0]) for k, v in PROPS.items()}
q_ref = at(T["APC_11x7"], 10600, "torque_nm")
res = {"engine_torque_nm": round(q_ref, 3), "calibration": "APC 11x7 = 10600 rpm (RCU, silenciador estándar)"}
for k, tab in T.items():
    lo, hi = 6000, 16000
    for _ in range(50):
        mid = (lo + hi) / 2
        lo, hi = (mid, hi) if at(tab, mid, "torque_nm") < q_ref else (lo, mid)
    n = (lo + hi) / 2
    res[k] = dict(rpm=int(round(n, -1)), thrust_n=round(at(tab, n, "thrust_n"), 1),
                  thrust_kgf=round(at(tab, n, "thrust_n") / 9.80665, 2), power_hp=round(at(tab, n, "hp"), 2),
                  tip_mach=round(math.pi * PROPS[k][1] * 0.0254 * n / 60 / 340.3, 2))
json.dump(res, open(sys.argv[1], "w"), indent=1)
print(json.dumps(res, indent=1))
