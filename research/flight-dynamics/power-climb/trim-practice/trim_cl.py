"""Elevator-to-trim versus lift coefficient from quasi-steady samples (read-only analysis).

Run: python3 -I trim_cl.py <references/rc-validation-library-2026-10-18 dir>

Why: the UMN Ultra Stick logs contain almost no steady, level, constant-speed
flight (race-track patterns, turns every ~15 s, hands-off phugoids). Trim is a
pitch-moment balance, so quasi-steady samples at any flight-path angle can be
used if CL is computed from the measured load factor: CL = m n_z g / (q S).
The level-flight trim curve follows by mapping CL to V_level = sqrt(2 m g / (rho0 S CL))
(rho0 = 1.225; the pitot speed is an indicated/equivalent airspeed).

Sample selection (1 s moving averages, decimated to 2 Hz to limit autocorrelation):
airborne (IAS > vmin, AGL > 15 m), |phi| < 15 deg, |n_z - 1| < 0.3, slow
elevator motion |d(de)/dt| < 2 deg/s, |dtheta/dt| < 5 deg/s, |d2theta/dt2| < 4 deg/s^2,
flap command at the flight median.
Regression: de = c0 + c1 CL + c2 qhat + c3 throttle, qhat = (dtheta/dt) c / (2V).
Elevator sign as logged (negative = trailing edge up).
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import trim_curve as tc  # loaders and helpers (same directory)

G = 9.80665
RHO0 = 1.225


def samples(d, vmin, ac, use_mode=None):
    t = d["t"]
    fs = 1.0 / np.median(np.diff(t))
    n1 = int(round(fs))
    sm = {k: tc.movavg(d[k], n1) for k in ("ias", "phi", "az", "flap", "de", "thr", "theta", "qbar", "climb")}
    thdot = np.gradient(sm["theta"], t)
    thddot = np.gradient(tc.movavg(thdot, n1), t)
    dedot = np.gradient(sm["de"], t)
    nz = -sm["az"] / G
    air = (sm["ias"] > vmin) & (d["h"] > 15.0)
    flap0 = np.median(d["flap"][air]) if air.any() else 0.0
    ok = (air & (np.abs(sm["phi"]) < 15.0) & (np.abs(nz - 1.0) < 0.3) & (np.abs(dedot) < 2.0)
          & (np.abs(thdot) < 5.0) & (np.abs(thddot) < 4.0) & (np.abs(sm["flap"] - flap0) < 1.0)
          & (sm["qbar"] > 20.0))
    if use_mode is not None:
        ok &= d["mode"] == use_mode
    step = max(int(round(fs / 2.0)), 1)
    idx = np.flatnonzero(ok)
    idx = idx[(idx % step) == 0]
    CL = ac["mass"] * G * nz[idx] / (sm["qbar"][idx] * ac["S"])
    qhat = np.radians(thdot[idx]) * ac["chord"] / (2.0 * sm["ias"][idx])
    return dict(de=sm["de"][idx], CL=CL, qhat=qhat, thr=sm["thr"][idx], V=sm["ias"][idx],
                climb=sm["climb"][idx], n=len(idx), secs=len(idx) / 2.0)


def fit(s):
    X = np.c_[np.ones(s["n"]), s["CL"], s["qhat"], s["thr"]]
    coef, res, *_ = np.linalg.lstsq(X, s["de"], rcond=None)
    r = s["de"] - X @ coef
    dof = max(s["n"] - 4, 1)
    cov = np.linalg.inv(X.T @ X) * (r @ r) / dof
    # effective sample size: 2 Hz samples are autocorrelated; inflate SE by sqrt(4) (assume ~2 s decorrelation)
    se = np.sqrt(np.diag(cov)) * 2.0
    return coef, se, np.sqrt(np.mean(r * r))


def table(label, s, ac, coef, binw=2.0):
    Vl = np.sqrt(2 * ac["mass"] * G / (RHO0 * ac["S"] * np.clip(s["CL"], 0.05, None)))
    print(f"\n#### {label}: elevator by level-flight-equivalent speed\n")
    print("| V_level bin (m/s) | samples (2 Hz) | CL | mean elevator (deg) | elevator corrected to q = 0 (deg) | throttle | actual IAS (m/s) | climb (m/s) |")
    print("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    lo = np.floor(np.percentile(Vl, 1) / binw) * binw
    hi = np.percentile(Vl, 99)
    rows = []
    while lo < hi:
        m = (Vl >= lo) & (Vl < lo + binw)
        if m.sum() >= 6:
            dec = s["de"][m] - coef[2] * s["qhat"][m]
            print(f"| {lo:.0f}–{lo+binw:.0f} | {m.sum()} | {np.mean(s['CL'][m]):.2f} | {np.mean(s['de'][m]):+.2f} | {np.mean(dec):+.2f} | {np.mean(s['thr'][m]):.2f} | {np.mean(s['V'][m]):.1f} | {np.mean(s['climb'][m]):+.1f} |")
            rows.append((lo + binw / 2, np.mean(dec), m.sum()))
        lo += binw
    return rows


def main():
    root = sys.argv[1]
    ufd = os.path.join(root, "ugly-stik/university-flight-data")
    cfgd = os.path.join(root, "ugly-stik/baldr-configurations")
    logs = os.path.join(root, "stik-analogues/logs")
    sets = [
        ("Baldr F12 cfg N", tc.load_baldr, os.path.join(ufd, "baldr-flight-12-2016-11-02.mat"), tc.BALDR, 12.0, None, "N"),
        ("Baldr F13 cfg N", tc.load_baldr, os.path.join(ufd, "baldr-flight-13-2016-11-02.mat"), tc.BALDR, 12.0, None, "N"),
        ("Baldr F14 cfg N", tc.load_baldr, os.path.join(cfgd, "BALDR_Flight14.mat"), tc.BALDR, 12.0, None, "N"),
        ("Baldr F15 cfg A (aft CG)", tc.load_baldr, os.path.join(cfgd, "BALDR_Flight15.mat"), tc.BALDR, 12.0, None, "aft"),
        ("Baldr F16 cfg B (+Ixx)", tc.load_baldr, os.path.join(cfgd, "BALDR_Flight16.mat"), tc.BALDR, 12.0, None, "B"),
        ("Baldr F17 cfg C (aft CG, +Ixx)", tc.load_baldr, os.path.join(ufd, "baldr-flight-17-2017-10-05.mat"), tc.BALDR, 12.0, None, "aft"),
        ("Thor F34 manual", lambda p: tc.load_thor(p, 1), os.path.join(logs, "thor-flight-34-2012-03-30.mat"), tc.THOR, 9.0, 1, "T12"),
        ("Thor F44 manual", lambda p: tc.load_thor(p, 1), os.path.join(logs, "thor-flight-44-2012-05-21.mat"), tc.THOR, 9.0, 1, "T12"),
        ("Thor F46 manual", lambda p: tc.load_thor(p, 1), os.path.join(logs, "thor-flight-46-2012-05-21.mat"), tc.THOR, 9.0, 1, "T12"),
        ("Thor F97 manual", lambda p: tc.load_thor(p, 1), os.path.join(ufd, "thor-flight-97-2013-11-05.h5"), tc.THOR, 9.0, 1, "T13"),
        ("Thor F98 manual", lambda p: tc.load_thor(p, 1), os.path.join(ufd, "thor-flight-98-2013-11-05.h5"), tc.THOR, 9.0, 1, "T13"),
        ("Thor F104 manual", lambda p: tc.load_thor(p, 1), os.path.join(ufd, "thor-flight-104-2014-03-08.h5"), tc.THOR, 9.0, 1, "T13"),
    ]
    pools = {}
    print("## Per-flight regression de = c0 + c1·CL + c2·qhat + c3·throttle\n")
    print("| Flight | quasi-steady s | CL range (p5–p95) | c1 = dδe/dCL (deg) | c2 (deg per unit qhat) | c3 (deg per unit stick) | rms (deg) | δe at level 1.6 Vs-equivalent? |")
    print("| --- | ---: | --- | ---: | ---: | ---: | ---: | --- |")
    per = {}
    for label, loader, path, ac, vmin, mode, pool in sets:
        d = loader(path)
        s = samples(d, vmin, ac, mode)
        per[label] = (s, ac)
        pools.setdefault(pool, []).append(s)
        if s["n"] < 20:
            print(f"| {label} | {s['secs']:.0f} | – | too few | | | | |")
            continue
        coef, se, rms = fit(s)
        print(f"| {label} | {s['secs']:.0f} | {np.percentile(s['CL'],5):.2f}–{np.percentile(s['CL'],95):.2f} | {coef[1]:+.2f} ± {se[1]:.2f} | {coef[2]:+.0f} ± {se[2]:.0f} | {coef[3]:+.2f} ± {se[3]:.2f} | {rms:.2f} | |")
    print("\n(± = 1σ with standard errors inflated ×2 for 2 Hz autocorrelation; an indication only.)")
    acs = {"N": tc.BALDR, "aft": tc.BALDR, "B": tc.BALDR, "T12": tc.THOR, "T13": tc.THOR}
    names = {"N": "Baldr nominal CG (F12–F14)", "aft": "Baldr aft CG (F15, F17)", "B": "Baldr +Ixx (F16)",
             "T12": "Thor 2012 (F34, F44, F46; manual)", "T13": "Thor 2013–14 (F97, F98, F104; manual)"}
    print("\n## Pooled fits and level-flight trim curves\n")
    summary = []
    for k, lst in pools.items():
        s = {f: np.concatenate([x[f] for x in lst]) for f in ("de", "CL", "qhat", "thr", "V", "climb")}
        s["n"] = len(s["de"]); s["secs"] = s["n"] / 2.0
        # flight-specific offsets: elevator zero/trim may differ between flights; add per-flight dummies
        offs = np.concatenate([np.full(x["n"], i) for i, x in enumerate(lst)])
        cols = [s["CL"], s["qhat"], s["thr"]] + [(offs == i).astype(float) for i in range(len(lst))]
        X = np.column_stack(cols)
        coef, *_ = np.linalg.lstsq(X, s["de"], rcond=None)
        r = s["de"] - X @ coef
        cov = np.linalg.inv(X.T @ X) * (r @ r) / max(s["n"] - X.shape[1], 1)
        se = np.sqrt(np.diag(cov)) * 2.0
        ac = acs[k]
        print(f"\n### {names[k]}\n")
        print(f"{s['secs']:.0f} s of quasi-steady samples. Fit with per-flight offsets: dδe/dCL = {coef[0]:+.2f} ± {se[0]:.2f} deg, qhat term {coef[1]:+.0f} ± {se[1]:.0f} deg, throttle term {coef[2]:+.2f} ± {se[2]:.2f} deg per unit stick; rms {np.sqrt(np.mean(r*r)):.2f} deg.")
        c4 = np.r_[np.mean(coef[3:]), coef[0], coef[1], coef[2]]
        rows = table(names[k], s, ac, c4)
        # implied level-flight slope dδe/dV at a few speeds: dδe/dV = -2 CL / V * dδe/dCL
        for V in ((18.0, 23.0, 28.0) if ac is tc.BALDR else (13.0, 17.0, 21.0)):
            CL = 2 * ac["mass"] * G / (RHO0 * ac["S"] * V * V)
            print(f"- at V = {V:.0f} m/s: CL = {CL:.2f}, dδe/dV = {-2*CL/V*coef[0]:+.3f} deg/(m/s) (CL term only)")
        summary.append((names[k], s["secs"], coef[0], se[0], coef[2], se[2]))
    print("\n## Summary\n")
    print("| Data set | quasi-steady s | dδe/dCL (deg) | throttle term (deg per unit stick) |")
    print("| --- | ---: | ---: | ---: |")
    for nm, secs, c1, s1, c3, s3 in summary:
        print(f"| {nm} | {secs:.0f} | {c1:+.2f} ± {s1:.2f} | {c3:+.2f} ± {s3:.2f} |")


if __name__ == "__main__":
    main()
