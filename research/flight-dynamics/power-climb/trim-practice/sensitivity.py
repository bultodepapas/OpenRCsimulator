"""Sensitivity of dδe/dCL to the quasi-steady filter and regressors (read-only).

Run: python3 -I sensitivity.py <references/rc-validation-library-2026-10-18 dir>
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import trim_curve as tc

G = 9.80665


def sel(d, vmin, ac, phi_max, thdot_max, climb_max, mode=None):
    t = d["t"]; fs = 1.0 / np.median(np.diff(t)); n1 = int(round(fs))
    sm = {k: tc.movavg(d[k], n1) for k in ("ias", "phi", "az", "flap", "de", "thr", "theta", "qbar", "climb")}
    thdot = np.gradient(sm["theta"], t); thddot = np.gradient(tc.movavg(thdot, n1), t); dedot = np.gradient(sm["de"], t)
    nz = -sm["az"] / G
    air = (sm["ias"] > vmin) & (d["h"] > 15.0)
    f0 = np.median(d["flap"][air])
    ok = (air & (np.abs(sm["phi"]) < phi_max) & (np.abs(nz - 1) < 0.3) & (np.abs(dedot) < 2.0) & (np.abs(thdot) < thdot_max)
          & (np.abs(thddot) < 4.0) & (np.abs(sm["flap"] - f0) < 1.0) & (sm["qbar"] > 20.0) & (np.abs(sm["climb"]) < climb_max))
    if mode is not None:
        ok &= d["mode"] == mode
    step = max(int(round(fs / 2)), 1)
    i = np.flatnonzero(ok); i = i[i % step == 0]
    CL = ac["mass"] * G * nz[i] / (sm["qbar"][i] * ac["S"])
    qh = np.radians(thdot[i]) * ac["chord"] / (2 * sm["ias"][i])
    return sm["de"][i], CL, qh, sm["thr"][i]


def fit(groups, use_q, use_thr):
    de = np.concatenate([g[0] for g in groups]); CL = np.concatenate([g[1] for g in groups])
    cols = [CL]
    if use_q:
        cols.append(np.concatenate([g[2] for g in groups]))
    if use_thr:
        cols.append(np.concatenate([g[3] for g in groups]))
    for k, g in enumerate(groups):
        cols.append(np.concatenate([np.full(len(h[0]), 1.0 if j == k else 0.0) for j, h in enumerate(groups)]))
    X = np.column_stack(cols)
    c, *_ = np.linalg.lstsq(X, de, rcond=None)
    return c[0], len(de) / 2


root = sys.argv[1]
ufd = os.path.join(root, "ugly-stik/university-flight-data"); cfgd = os.path.join(root, "ugly-stik/baldr-configurations"); logs = os.path.join(root, "stik-analogues/logs")
sets = {
    "Baldr nominal (F12, F14)": [(tc.load_baldr(os.path.join(ufd, "baldr-flight-12-2016-11-02.mat")), 12.0, tc.BALDR, None),
                                 (tc.load_baldr(os.path.join(cfgd, "BALDR_Flight14.mat")), 12.0, tc.BALDR, None)],
    "Baldr F17 aft CG": [(tc.load_baldr(os.path.join(ufd, "baldr-flight-17-2017-10-05.mat")), 12.0, tc.BALDR, None)],
    "Thor 2012 manual": [(tc.load_thor(os.path.join(logs, f), 1), 9.0, tc.THOR, 1) for f in
                         ("thor-flight-34-2012-03-30.mat", "thor-flight-44-2012-05-21.mat", "thor-flight-46-2012-05-21.mat")],
}
variants = [("base: |phi|<15, |thdot|<5, any climb", 15, 5, 99), ("strict: |phi|<10, |thdot|<3", 10, 3, 99),
            ("level only: |climb|<1 m/s", 15, 5, 1.0), ("loose: |phi|<20, |thdot|<8", 20, 8, 99)]
print("| Data set | filter | seconds | dδe/dCL: CL only | + qhat | + qhat + throttle |")
print("| --- | --- | ---: | ---: | ---: | ---: |")
for name, lst in sets.items():
    for vlab, pm, tm, cm in variants:
        groups = [sel(d, v, ac, pm, tm, cm, mo) for d, v, ac, mo in lst]
        groups = [g for g in groups if len(g[0]) >= 10]
        if not groups:
            print(f"| {name} | {vlab} | 0 | – | – | – |")
            continue
        a, n = fit(groups, False, False); b, _ = fit(groups, True, False); c, _ = fit(groups, True, True)
        print(f"| {name} | {vlab} | {n:.0f} | {a:+.2f} | {b:+.2f} | {c:+.2f} |")
