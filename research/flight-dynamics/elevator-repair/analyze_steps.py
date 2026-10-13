#!/usr/bin/env python3
"""Reduce the elevator step CSVs (elev_steps.gd) to per-run metrics. Stdlib only.
Usage: python3 -I analyze_steps.py [name-filter]; CSV directory from OPENRC_ELEVATOR_STEPS (default /tmp/openrc-elevator-steps)."""
import csv, glob, math, os, sys

OUT = os.environ.get("OPENRC_ELEVATOR_STEPS", "/tmp/openrc-elevator-steps")
T_STEP, T_RELEASE = 0.5, 2.0


def load(path):
    with open(path) as fh:
        rows = list(csv.DictReader(fh))
    for r in rows:
        for k in r:
            try:
                r[k] = float(r[k])
            except ValueError:
                r[k] = float("nan")
    return rows


def metrics(rows):
    held = [r for r in rows if T_STEP <= r["t"] < T_RELEASE]
    after = [r for r in rows if r["t"] >= T_RELEASE]
    if not held:
        return None
    q0 = rows[0]["q_dps"]
    al0 = rows[0]["alpha_deg"]
    th0 = rows[0]["theta_deg"]
    qs = [r["q_dps"] for r in held]
    sign = 1.0 if (max(qs, key=abs) >= 0) else -1.0
    # first peak of q after the step (sign of the dominant response)
    peak_i = max(range(len(qs)), key=lambda i: sign * qs[i])
    q_peak = qs[peak_i]
    t_peak = held[peak_i]["t"] - T_STEP
    # steady value at the end of the hold (mean of last 0.2 s) for overshoot
    tail = [r["q_dps"] for r in held if r["t"] >= T_RELEASE - 0.2]
    q_end = sum(tail) / len(tail)
    alpha_peak = max(held, key=lambda r: sign * (r["alpha_deg"] - al0))
    theta_change = held[-1]["theta_deg"] - th0
    # count sign reversals of (q - q_end) after the first peak: ringing
    rev = 0
    last = None
    for r in held[peak_i:]:
        s = (r["q_dps"] - q_end) > 0
        if last is not None and s != last:
            rev += 1
        last = s
    p_max = max(abs(r["p_dps"]) for r in rows)
    r_max = max(abs(r["r_dps"]) for r in rows)
    beta_max = max(abs(r["beta_deg"]) for r in rows)
    phi_max = max(abs(r["phi_deg"]) for r in rows)
    blend_max = max(r["blend"] for r in held)
    nz_peak = max(held, key=lambda r: sign * r["nz"])["nz"]
    v_min = min(r["V"] for r in rows)
    v_max = max(r["V"] for r in rows)
    crashed = any(r["crashed"] == 1 for r in rows)
    # recovery after release: time for |q - q0| to fall under 10 deg/s, and residual oscillation
    rec = None
    for r in after:
        if abs(r["q_dps"] - q0) < 10.0:
            rec = r["t"] - T_RELEASE
            break
    q_after_max = max((abs(r["q_dps"]) for r in after), default=float("nan"))
    gyro_max = max(abs(r["My_gyro"]) for r in rows)
    prop_range = (min(r["My_prop"] for r in rows), max(r["My_prop"] for r in rows))
    aero_range = (min(r["My_aero"] for r in rows), max(r["My_aero"] for r in rows))
    return dict(q_peak=q_peak, t_peak=t_peak, q_end=q_end, alpha_peak=alpha_peak["alpha_deg"], t_alpha_peak=alpha_peak["t"] - T_STEP,
                alpha0=al0, theta_change=theta_change, reversals=rev, p_max=p_max, r_max=r_max, beta_max=beta_max, phi_max=phi_max,
                blend_max=blend_max, nz_peak=nz_peak, v_min=v_min, v_max=v_max, crashed=crashed, recovery=rec, q_after_max=q_after_max,
                gyro_max=gyro_max, prop_range=prop_range, aero_range=aero_range, ticks=len(rows), t_last=rows[-1]["t"],
                elev=held[len(held) // 2]["elev_deg"])


def main():
    files = sorted(glob.glob(os.path.join(OUT, "*.csv")))
    sel = sys.argv[1] if len(sys.argv) > 1 else ""
    print("| run | δe° | q peak °/s @s | q end | α peak ° @s (α0) | Δθ° | rev | nz pk | blend max | |p| max | |r| max | |β| max | |φ| max | V min–max | gyro My max | prop My range | recov s | q after max | crash |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for path in files:
        name = os.path.basename(path)[:-4]
        if sel and sel not in name:
            continue
        rows = load(path)
        m = metrics(rows)
        if m is None:
            print(f"| {name} | (no hold rows: {len(rows)} ticks, last t {rows[-1]['t']:.2f}) |")
            continue
        print("| {n} | {elev:+.1f} | {qp:+.0f} @{tp:.2f} | {qe:+.0f} | {ap:+.1f} @{tap:.2f} ({a0:.1f}) | {dth:+.0f} | {rev} | {nz:+.1f} | {bl:.2f} | {p:.0f} | {r:.0f} | {b:.1f} | {phi:.0f} | {vmin:.1f}–{vmax:.1f} | {g:.2f} | {pr0:+.2f}…{pr1:+.2f} | {rec} | {qa:.0f} | {cr} |".format(
            n=name, elev=m["elev"], qp=m["q_peak"], tp=m["t_peak"], qe=m["q_end"], ap=m["alpha_peak"], tap=m["t_alpha_peak"], a0=m["alpha0"],
            dth=m["theta_change"], rev=m["reversals"], nz=m["nz_peak"], bl=m["blend_max"], p=m["p_max"], r=m["r_max"], b=m["beta_max"], phi=m["phi_max"],
            vmin=m["v_min"], vmax=m["v_max"], g=m["gyro_max"], pr0=m["prop_range"][0], pr1=m["prop_range"][1],
            rec=("%.2f" % m["recovery"]) if m["recovery"] is not None else "none", qa=m["q_after_max"], cr="CRASH" if m["crashed"] else ""))


if __name__ == "__main__":
    main()
