"""Hands-off (fixed-elevator) windows in UMN Ultra Stick logs: phugoid and drift (read-only).

Run: python3 -I handsoff.py <references/rc-validation-library-2026-10-18 dir>

A window is "hands-off in pitch" when the elevator command (1 s moving average)
stays within a 0.3 deg band for >= 10 s while airborne (IAS > vmin, AGL > 20 m),
under manual control (Thor: mode 1), with throttle above 0.2 and elevator within
3 deg of the flight's median airborne elevator (excludes stall/spin entries).
Windows with mean |bank| > 20 deg are listed separately (circles). Aileron is
reported: "fixed" when its 1 s average stays within a 0.3 deg band. For each window the script prints the
speed, pitch, height and heading excursions and fits
V(t) = a + b t + A exp(sigma t) cos(omega t + phase) to the airspeed.
Fits are listed only when R^2 >= 0.85 and the period is <= 1.5x the window.
"""
import os
import sys

import numpy as np
from scipy.optimize import curve_fit

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import trim_curve as tc

G = 9.80665


def model(t, a, b, A, s, w, p):
    return a + b * t + A * np.exp(s * t) * np.cos(w * t + p)


def windows(d, vmin, tol=0.15, min_len=10.0):
    t = d["t"]
    fs = 1.0 / np.median(np.diff(t))
    n1 = int(round(fs))
    de = tc.movavg(d["de"], n1)
    air0 = (tc.movavg(d["ias"], n1) > vmin) & (d["h"] > 20.0)
    de_med = np.median(d["de"][air0])
    air = air0 & (d["mode"] == 1) & (tc.movavg(d["thr"], n1) > 0.2) & (np.abs(de - de_med) < 3.0)
    out = []
    i = 0
    N = len(t)
    while i < N:
        if not air[i]:
            i += 1
            continue
        j = i
        lo = hi = de[i]
        while j + 1 < N and air[j + 1]:
            lo2, hi2 = min(lo, de[j + 1]), max(hi, de[j + 1])
            if hi2 - lo2 > 2 * tol:
                break
            lo, hi = lo2, hi2
            j += 1
        if (j - i) / fs >= min_len:
            out.append((i, j))
            i = j + 1
        else:
            i += max(1, n1 // 5)
    return out


def analyse(label, d, vmin):
    t = d["t"]
    fs = 1.0 / np.median(np.diff(t))
    n1 = int(round(fs))
    V = tc.movavg(d["ias"], n1)
    th = tc.movavg(d["theta"], n1)
    ph = tc.movavg(d["phi"], n1)
    rows = []
    for i, j in windows(d, vmin):
        sl = slice(i, j)
        tt = t[sl] - t[i]
        dur = tt[-1]
        h = d["h"][sl]
        hdg = None
        r = dict(label=label, t0=t[i], dur=dur, de=np.median(d["de"][sl]), thr=np.mean(d["thr"][sl]),
                 thr_rng=np.ptp(d["thr"][sl]), V=np.mean(V[sl]), dV=np.ptp(V[sl]), dth=np.ptp(th[sl]),
                 dh=h[-1] - h[0], hr=np.ptp(h), phi=np.mean(np.abs(ph[sl])), phimax=np.max(np.abs(ph[sl])),
                 ailfix=np.ptp(tc.movavg(d["ail"], n1)[sl]) < 0.3)
        # fit damped sinusoid to V
        dec = max(1, int(fs / 5))
        x, y = tt[::dec], V[sl][::dec]
        best = None
        for Tg in (6, 9, 12, 16, 20, 25):
            for sg in (-0.1, 0.0, 0.05):
                p0 = [y.mean(), 0.0, (y.max() - y.min()) / 2, sg, 2 * np.pi / Tg, 0.0]
                try:
                    p, _ = curve_fit(model, x, y, p0=p0, maxfev=4000)
                except Exception:
                    continue
                res = y - model(x, *p)
                r2 = 1 - np.sum(res ** 2) / np.sum((y - y.mean()) ** 2)
                if best is None or r2 > best[1]:
                    best = (p, r2)
        if best is not None:
            p, r2 = best
            w = abs(p[4])
            T = 2 * np.pi / w if w > 0 else np.inf
            zeta = -p[3] / np.sqrt(p[3] ** 2 + w ** 2) if w > 0 else np.nan
            r.update(T=T, zeta=zeta, r2=r2, A=abs(p[2]))
        rows.append(r)
    return rows


def main():
    root = sys.argv[1]
    ufd = os.path.join(root, "ugly-stik/university-flight-data")
    cfgd = os.path.join(root, "ugly-stik/baldr-configurations")
    logs = os.path.join(root, "stik-analogues/logs")
    sets = [
        ("Baldr F12", tc.load_baldr, os.path.join(ufd, "baldr-flight-12-2016-11-02.mat"), 12.0),
        ("Baldr F13", tc.load_baldr, os.path.join(ufd, "baldr-flight-13-2016-11-02.mat"), 12.0),
        ("Baldr F14", tc.load_baldr, os.path.join(cfgd, "BALDR_Flight14.mat"), 12.0),
        ("Baldr F15", tc.load_baldr, os.path.join(cfgd, "BALDR_Flight15.mat"), 12.0),
        ("Baldr F16", tc.load_baldr, os.path.join(cfgd, "BALDR_Flight16.mat"), 12.0),
        ("Baldr F17", tc.load_baldr, os.path.join(ufd, "baldr-flight-17-2017-10-05.mat"), 12.0),
        ("Thor F34", lambda p: tc.load_thor(p, 1), os.path.join(logs, "thor-flight-34-2012-03-30.mat"), 9.0),
        ("Thor F44", lambda p: tc.load_thor(p, 1), os.path.join(logs, "thor-flight-44-2012-05-21.mat"), 9.0),
        ("Thor F46", lambda p: tc.load_thor(p, 1), os.path.join(logs, "thor-flight-46-2012-05-21.mat"), 9.0),
        ("Thor F97", lambda p: tc.load_thor(p, 1), os.path.join(ufd, "thor-flight-97-2013-11-05.h5"), 9.0),
        ("Thor F98", lambda p: tc.load_thor(p, 1), os.path.join(ufd, "thor-flight-98-2013-11-05.h5"), 9.0),
        ("Thor F104", lambda p: tc.load_thor(p, 1), os.path.join(ufd, "thor-flight-104-2014-03-08.h5"), 9.0),
    ]
    allrows = []
    print("| Flight | t0 (s) | length (s) | elevator (deg) | throttle (range) | mean IAS (m/s) | IAS swing (m/s) | pitch swing (deg) | height change / range (m) | mean / max bank (deg) | aileron fixed | V fit: period (s), ζ, R² |")
    print("| --- | ---: | ---: | ---: | --- | ---: | ---: | ---: | --- | --- | --- | --- |")
    for label, loader, path, vmin in sets:
        d = loader(path)
        rows = analyse(label, d, vmin)
        for r in rows:
            fit = ""
            if "T" in r and r["r2"] >= 0.85 and r["T"] <= 1.5 * r["dur"]:
                fit = f"{r['T']:.1f}, {r['zeta']:+.2f}, {r['r2']:.2f}"
            print(f"| {r['label']} | {r['t0']:.0f} | {r['dur']:.1f} | {r['de']:+.2f} | {r['thr']:.2f} ({r['thr_rng']:.2f}) | {r['V']:.1f} | {r['dV']:.1f} | {r['dth']:.1f} | {r['dh']:+.0f} / {r['hr']:.0f} | {r['phi']:.0f} / {r['phimax']:.0f} | {'yes' if r['ailfix'] else 'no'} | {fit} |")
            allrows.append(r)
    allrows = [r for r in allrows if r["phi"] <= 20.0]
    print("\nSummary below uses only windows with mean |bank| <= 20 deg.")
    good = [r for r in allrows if "T" in r and r["r2"] >= 0.85 and r["T"] <= 1.5 * r["dur"]]
    print(f"\n{len(allrows)} hands-off windows, {sum(r['dur'] for r in allrows):.0f} s in total; {len(good)} with an acceptable V fit.")
    for ac in ("Baldr", "Thor"):
        g = [r for r in good if r["label"].startswith(ac)]
        a = [r for r in allrows if r["label"].startswith(ac)]
        if a:
            print(f"- {ac}: {len(a)} windows, median length {np.median([r['dur'] for r in a]):.0f} s, median IAS swing {np.median([r['dV'] for r in a]):.1f} m/s, median pitch swing {np.median([r['dth'] for r in a]):.1f} deg, median height range {np.median([r['hr'] for r in a]):.0f} m")
        if g:
            Ts = np.array([r["T"] for r in g]); zs = np.array([r["zeta"] for r in g]); Vs = np.array([r["V"] for r in g])
            print(f"  fitted period median {np.median(Ts):.1f} s (range {Ts.min():.1f}–{Ts.max():.1f}), ζ median {np.median(zs):+.2f} (range {zs.min():+.2f}–{zs.max():+.2f}); Lanchester sqrt(2)·pi·V/g at the median IAS {np.median(Vs):.1f} m/s = {np.sqrt(2)*np.pi*np.median(Vs)/G:.1f} s")


if __name__ == "__main__":
    main()
