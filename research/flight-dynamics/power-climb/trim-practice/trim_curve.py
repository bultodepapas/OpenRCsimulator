"""Level-flight elevator trim curve from UMN Ultra Stick logs (read-only analysis).

Run: python3 -I trim_curve.py <references/rc-validation-library-2026-10-18 dir>
Inputs are untrusted data files; they are only parsed with scipy.io / h5py.
Outputs: printed tables (markdown) and segments CSV in this script's directory.

Method
- Quasi-steady (pitch-moment equilibrium), near-wings-level chunks: 1 s moving averages; airborne
  (IAS > vmin, baro AGL > 15 m); |phi| < 15 deg; |dtheta/dt| < 3 deg/s and
  |dphi/dt| < 10 deg/s (EKF attitude; Baldr gyros carry uncorrected bias);
  |climb| < 2.5 m/s; |dV/dt| < 0.8 m/s^2 (2 s smoothing); |n_z - 1| < 0.25;
  flap command within 1 deg of the flight median (the Baldr flap channel holds
  a constant per-flight offset); elevator 1 s rolling std < 0.8 deg (excludes
  doublets/sweeps); runs >= 2 s, split into <= 4 s chunks.
- Elevator: Baldr = mean of left/right actuator command (deg). Thor manual
  (mode 1) = de_in (pilot command, rad -> deg); Thor computer (mode 2) = de.
  Sign as logged: negative = trailing edge up (Dorobantu: M_de < 0).
- CL = m n_z g / (q S) with measured n_z = -a_z/g and pitot dynamic pressure q.
- Climb is allowed (|climb| < 2.5 m/s): trim is a moment balance; climb and
  throttle are reported per bin and a regression on CL and throttle is printed.
"""
import csv
import os
import sys

import numpy as np

sys.path.insert(0, "/tmp/rc-h5py")  # h5py installed by an earlier session (pip --target)

G = 9.80665
# Quasi-steady filter limits (module-level so a variant can be re-run); see docstring.
PHI_MAX, THDOT_MAX, CLIMB_MAX, DVDT_MAX = 15.0, 3.0, 2.5, 0.8
HERE = os.path.dirname(os.path.abspath(__file__))

BALDR = dict(mass=7.41, S=0.77, chord=0.43, name="Baldr (Ultra Stick 120, electric)")
THOR = dict(mass=1.90, S=0.32, chord=0.30, name="Thor (Ultra Stick 25e, electric)")


def movavg(x, n):
    n = max(int(n), 1)
    k = np.ones(n) / n
    return np.convolve(x, k, mode="same")


def rollstd(x, n):
    m = movavg(x, n)
    m2 = movavg(x * x, n)
    return np.sqrt(np.maximum(m2 - m * m, 0.0))


def load_baldr(path):
    import scipy.io as sio
    m = sio.loadmat(path, squeeze_me=True, struct_as_record=False)
    d = m["dtc"]
    a, s = d.actuator, d.surface
    out = dict(
        t=np.asarray(d.time, float),
        ias=np.asarray(d.air.pitot.airspeed, float),
        qbar=np.asarray(d.air.pitot.dynpress, float),
        h=np.asarray(d.air.pitot.alt_baro, float),
        phi=np.asarray(d.ekf.phi, float),
        theta=np.asarray(d.ekf.theta, float),
        climb=-np.asarray(d.ekf.Vd, float),
        p=np.asarray(d.imu.p, float), q=np.asarray(d.imu.q, float), r=np.asarray(d.imu.r, float),
        az=np.asarray(d.imu.az, float),
        de=0.5 * (np.asarray(a.l_elevator, float) + np.asarray(a.r_elevator, float)),
        de_surf_l=np.asarray(s.l_elevator, float),
        thr=np.asarray(d.pilot.throttle, float),
        flap=0.5 * (np.asarray(a.l_flap, float) + np.asarray(a.r_flap, float)),
        alpha=np.full(np.asarray(d.time).shape, np.nan),
        ail=0.5 * (np.asarray(a.l_aileron, float) - np.asarray(a.r_aileron, float)),
    )
    out["mode"] = np.ones_like(out["t"])
    return out


def load_thor(path, use_mode):
    if path.endswith(".h5"):
        import h5py
        f = h5py.File(path, "r")
        raw = {k: np.asarray(f[k][()], float).ravel() for k in f.keys()
               if isinstance(f[k], h5py.Dataset) and f[k].dtype.kind in "fiu"}
    else:
        import scipy.io as sio
        m = sio.loadmat(path, squeeze_me=True)
        raw = {k: np.asarray(v, float).ravel() for k, v in m.items()
               if not k.startswith("__") and isinstance(v, np.ndarray) and v.dtype.kind in "fiu"}
    th = raw["theta"] if "theta" in raw else raw["the"]
    de = raw["de_in"] if use_mode == 1 else raw["de"]
    out = dict(
        t=raw["time"], ias=raw["ias"], qbar=raw["Pd"] * 1000.0, h=raw["h"],
        phi=np.degrees(raw["phi"]), theta=np.degrees(th), climb=-raw["navvd"],
        p=raw["p"], q=raw["q"] - raw.get("q_bias", 0.0), r=raw["r"], az=raw["az"],
        de=np.degrees(de), de_surf_l=np.full(raw["time"].shape, np.nan),
        thr=raw["dthr_in"], flap=np.degrees(0.5 * (raw["df_l"] + raw["df_r"])),
        alpha=np.degrees(raw["aoa"]), mode=raw["mode"],
        ail=np.degrees(0.5 * ((raw["da_l_in"] - raw["da_r_in"]) if use_mode == 1 else (raw["da_l"] - raw["da_r"]))),
    )
    return out


def segments(d, vmin, use_mode=None, min_len=2.0, chunk=4.0):
    t = d["t"]
    fs = 1.0 / np.median(np.diff(t))
    n1 = int(round(fs))
    sm = {k: movavg(d[k], n1) for k in ("ias", "phi", "climb", "az", "flap", "de", "thr", "theta", "qbar")}
    # Euler-angle rates from the EKF attitude (gyro channels carry uncorrected bias in the Baldr export)
    thdot = np.gradient(movavg(d["theta"], n1), t)
    phdot = np.gradient(movavg(d["phi"], n1), t)
    v2 = movavg(d["ias"], 2 * n1)
    dvdt = np.gradient(v2, t)
    destd = rollstd(d["de"], n1)
    air = (sm["ias"] > vmin) & (d["h"] > 15.0)
    flap0 = np.median(d["flap"][air]) if air.any() else 0.0
    ok = (air & (np.abs(sm["phi"]) < PHI_MAX) & (np.abs(thdot) < THDOT_MAX) & (np.abs(phdot) < 10.0)
          & (np.abs(sm["climb"]) < CLIMB_MAX) & (np.abs(dvdt) < DVDT_MAX)
          & (np.abs(-sm["az"] / G - 1.0) < 0.25) & (np.abs(sm["flap"] - flap0) < 1.0) & (destd < 0.8))
    if use_mode is not None:
        ok &= d["mode"] == use_mode
    segs = []
    idx = np.flatnonzero(np.diff(np.r_[0, ok.astype(int), 0]))
    for a, b in zip(idx[::2], idx[1::2]):
        dur = (b - a) / fs
        if dur < min_len:
            continue
        nchunks = max(1, int(np.floor(dur / chunk)))
        edges = np.linspace(a, b, nchunks + 1).astype(int)
        for c0, c1 in zip(edges[:-1], edges[1:]):
            sl = slice(c0, c1)
            segs.append(dict(
                t0=t[c0], dur=(c1 - c0) / fs, V=np.mean(d["ias"][sl]), qbar=np.mean(d["qbar"][sl]),
                de=np.mean(d["de"][sl]), de_surf=np.nanmean(d["de_surf_l"][sl]) if np.isfinite(d["de_surf_l"][sl]).any() else np.nan,
                thr=np.mean(d["thr"][sl]), theta=np.mean(d["theta"][sl]), climb=np.mean(d["climb"][sl]),
                nz=np.mean(-d["az"][sl]) / G, alpha=np.nanmean(d["alpha"][sl]) if np.isfinite(d["alpha"][sl]).any() else np.nan,
                flap=flap0,
            ))
    return segs


def wls(x, y, w):
    """Weighted least squares y = a + b x; returns a, b, se_b (segment-level residual scatter)."""
    x, y, w = map(np.asarray, (x, y, w))
    W = w / w.sum()
    xm, ym = np.sum(W * x), np.sum(W * y)
    sxx = np.sum(W * (x - xm) ** 2)
    b = np.sum(W * (x - xm) * (y - ym)) / sxx
    a = ym - b * xm
    res = y - a - b * x
    n = len(x)
    s2 = np.sum(W * res ** 2) * n / max(n - 2, 1)
    se_b = np.sqrt(s2 / (sxx * n)) if n > 2 else np.nan
    return a, b, se_b, np.sqrt(np.sum(W * res ** 2))


def report(label, segs, ac, binw=2.0):
    if len(segs) < 3:
        print(f"\n### {label}: only {len(segs)} steady chunks, skipped\n")
        return None
    V = np.array([s["V"] for s in segs]); de = np.array([s["de"] for s in segs]); w = np.array([s["dur"] for s in segs])
    CL = np.array([ac["mass"] * G * s["nz"] / (s["qbar"] * ac["S"]) for s in segs])
    print(f"\n### {label}\n")
    print(f"{len(segs)} steady chunks, {w.sum():.0f} s total, IAS {V.min():.1f}–{V.max():.1f} m/s\n")
    print("| IAS bin (m/s) | chunks | time (s) | mean elevator (deg) | spread of chunk means (deg) | CL (m = %.2f kg) | throttle | pitch (deg) | climb (m/s) |" % ac["mass"])
    print("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    lo = np.floor(V.min() / binw) * binw
    while lo < V.max():
        s = (V >= lo) & (V < lo + binw)
        if s.any():
            ww = w[s]
            f = lambda k: np.average(np.array([g[k] for g, m in zip(segs, s) if m]), weights=ww)
            print(f"| {lo:.0f}–{lo+binw:.0f} | {s.sum()} | {ww.sum():.0f} | {np.average(de[s], weights=ww):+.2f} | {np.std(de[s]):.2f} | {np.average(CL[s], weights=ww):.2f} | {f('thr'):.2f} | {f('theta'):+.1f} | {f('climb'):+.2f} |")
        lo += binw
    a, b, se, rms = wls(V, de, w)
    a2, b2, se2, rms2 = wls(CL, de, w)
    Vm = np.average(V, weights=w); CLm = np.average(CL, weights=w)
    slope_from_cl = -2.0 * CLm / Vm * b2
    thr = np.array([s["thr"] for s in segs])
    X = np.c_[np.ones_like(CL), CL, thr] * np.sqrt(w)[:, None]
    coef, *_ = np.linalg.lstsq(X, de * np.sqrt(w), rcond=None)
    print(f"\nRegression de = c0 + c1·CL + c2·throttle: c1 = {coef[1]:+.2f} deg/CL, c2 = {coef[2]:+.2f} deg per unit stick (throttle spread {thr.min():.2f}–{thr.max():.2f})")
    print(f"Linear fit de = a + b·V: b = {b:+.3f} ± {se:.3f} deg/(m/s) (1σ, chunk scatter), residual rms {rms:.2f} deg")
    print(f"Fit de = a + k·CL: k = dδe/dCL = {b2:+.2f} ± {se2:.2f} deg per unit CL (rms {rms2:.2f}); at V = {Vm:.1f} m/s, CL = {CLm:.2f}: dδe/dV = {slope_from_cl:+.3f} deg/(m/s)")
    return dict(label=label, n=len(segs), T=w.sum(), Vmin=V.min(), Vmax=V.max(), b=b, se=se, k=b2, sek=se2, Vm=Vm, CLm=CLm, dVcl=slope_from_cl)


def main():
    root = sys.argv[1]
    ufd = os.path.join(root, "ugly-stik/university-flight-data")
    cfg = os.path.join(root, "ugly-stik/baldr-configurations")
    logs = os.path.join(root, "stik-analogues/logs")
    allsegs = []
    summary = []
    baldr = [
        ("Baldr F12 (cfg N, 2016-11-02)", os.path.join(ufd, "baldr-flight-12-2016-11-02.mat")),
        ("Baldr F13 (cfg N, 2016-11-02)", os.path.join(ufd, "baldr-flight-13-2016-11-02.mat")),
        ("Baldr F14 (cfg N, 2017-09-29)", os.path.join(cfg, "BALDR_Flight14.mat")),
        ("Baldr F15 (cfg A aft CG, 2017)", os.path.join(cfg, "BALDR_Flight15.mat")),
        ("Baldr F16 (cfg B +Ixx, 2017)", os.path.join(cfg, "BALDR_Flight16.mat")),
        ("Baldr F17 (cfg C aft CG +Ixx, 2017-10-05)", os.path.join(ufd, "baldr-flight-17-2017-10-05.mat")),
    ]
    pooled = {"N": [], "aft": []}
    for label, path in baldr:
        d = load_baldr(path)
        air = (d["ias"] > 10) & (d["h"] > 15)
        fl = np.mean(np.abs(d["flap"][air]) > 2.0) if air.any() else np.nan
        print(f"\n[{label}] airborne {air.sum()/100:.0f} s, flap > 2 deg for {100*fl:.0f} % of it; airborne median elevator cmd {np.median(d['de'][air]):+.2f} deg, surface-L {np.median(d['de_surf_l'][air]):+.2f} deg")
        segs = segments(d, vmin=12.0)
        for s in segs:
            s["flight"] = label
        allsegs += segs
        r = report(label, segs, BALDR)
        if r:
            summary.append(r)
        if "cfg N" in label:
            pooled["N"] += segs
        elif "aft" in label:
            pooled["aft"] += segs
    for k, lab in (("N", "Baldr pooled, nominal CG (F12–F14)"), ("aft", "Baldr pooled, aft CG (F15, F17)")):
        r = report(lab, pooled[k], BALDR)
        if r:
            summary.append(r)
    thor = [
        ("Thor F34 (2012-03-30)", os.path.join(logs, "thor-flight-34-2012-03-30.mat")),
        ("Thor F44 (2012-05-21)", os.path.join(logs, "thor-flight-44-2012-05-21.mat")),
        ("Thor F46 (2012-05-21)", os.path.join(logs, "thor-flight-46-2012-05-21.mat")),
        ("Thor F97 (2013-11-05)", os.path.join(ufd, "thor-flight-97-2013-11-05.h5")),
        ("Thor F98 (2013-11-05)", os.path.join(ufd, "thor-flight-98-2013-11-05.h5")),
        ("Thor F104 (2014-03-08)", os.path.join(ufd, "thor-flight-104-2014-03-08.h5")),
    ]
    for mode, tag in ((1, "manual, de_in"), (2, "computer, de")):
        for label, path in thor:
            d = load_thor(path, mode)
            segs = segments(d, vmin=9.0, use_mode=mode)
            for s in segs:
                s["flight"] = f"{label} {tag}"
            allsegs += segs
            r = report(f"{label} {tag}", segs, THOR)
            if r:
                summary.append(r)
    print("\n## Summary of slopes\n")
    print("| Data set | chunks | time (s) | IAS range (m/s) | dδe/dV linear (deg per m/s) | dδe/dCL (deg per CL) | dδe/dV from CL fit at mean V |")
    print("| --- | ---: | ---: | --- | ---: | ---: | ---: |")
    for r in summary:
        print(f"| {r['label']} | {r['n']} | {r['T']:.0f} | {r['Vmin']:.1f}–{r['Vmax']:.1f} | {r['b']:+.3f} ± {r['se']:.3f} | {r['k']:+.1f} ± {r['sek']:.1f} | {r['dVcl']:+.3f} at {r['Vm']:.1f} m/s |")
    out = os.path.join(HERE, "trim_curve_segments.csv")
    keys = ["flight", "t0", "dur", "V", "qbar", "de", "de_surf", "thr", "theta", "climb", "nz", "alpha", "flap"]
    with open(out, "w", newline="") as fh:
        wr = csv.DictWriter(fh, fieldnames=keys)
        wr.writeheader()
        for s in allsegs:
            wr.writerow({k: (f"{s[k]:.4f}" if isinstance(s[k], float) else s[k]) for k in keys})
    print(f"\nsegments CSV: {out}")


if __name__ == "__main__":
    main()
