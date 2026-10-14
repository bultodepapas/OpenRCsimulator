"""D6e-R1: independent 3-DOF longitudinal check of the standard Ugly Stik, written without the simulator code.

Same global coefficients, ARP transfer, propeller table and rpm-lag law as the aircraft JSON; no downwash lag, servo or lateral
motion. It answers two questions: what steady straight flight exists with the launch elevator fixed (the equilibrium map), and
how the throttle response changes with the propeller table and the static margin.

Usage: python research/flight-dynamics/climb-trim/independent_longitudinal.py
Needs numpy and scipy. The map should match fixed-trim-power-equilibrium.json; the sweeps are counterfactuals, not calibration.
"""
import json
from pathlib import Path

import numpy as np
from scipy.optimize import fsolve

ROOT = Path(__file__).resolve().parents[3]
DATA = json.loads((ROOT / "app/data/aircraft/jensen_ugly_stik_60.json").read_text())
APC = np.array(json.loads((ROOT / "docs/research/flight-dynamics/climb-trim/apc12x6-comparison.json").read_text())["cases"][0]["ct_table"]["value"])
A = {k: v["value"] for k, v in DATA["aero"]["coefficients"].items()}
S = DATA["reference"]["wing_area"]["value"]
C = DATA["reference"]["mean_chord"]["value"]
ARP = np.array(DATA["reference"]["aero_reference_point"]["value"])
CG = np.array(DATA["balance"]["plan_cg"]["value"])
PROP = DATA["propulsion"]
DIAMETER = PROP["propeller"]["diameter"]["value"]
UIUC = np.array(PROP["propeller"]["ct_table"]["value"])
IDLE = PROP["engine"]["idle_rpm"]["value"]
MAX_RPM = PROP["engine"]["max_rpm_static"]["value"]
LAG = PROP["engine"]["lag_time_constant"]["value"]
MASS, JYY, G, RHO = 2.88505829104375, 0.38708561399355, 9.80665, 1.225  # trace metadata of the captured flight


def ct(table, j):
    if j <= table[0, 0]:
        return table[0, 1]
    if j >= table[-1, 0]:
        slope = (table[-1, 1] - table[-2, 1]) / (table[-1, 0] - table[-2, 0])
        return max(-0.1, table[-1, 1] + slope * (j - table[-1, 0]))
    return float(np.interp(j, table[:, 0], table[:, 1]))


def derivative(x, elevator, throttle, arp_x, table):
    u, w, q, theta, _, _, rpm = x
    V, alpha = np.hypot(u, w), np.arctan2(w, u)
    qbar = 0.5 * RHO * V * V
    cl = A["CL0"] + A["CLa"] * alpha + A["CLde"] * elevator
    cd = A["CD0"] + A["k_induced"] * (cl - A["CL_minD"]) ** 2 + abs(A["CDde"] * elevator)
    cm = A["Cm0"] + A["Cma"] * alpha + A["Cmde"] * elevator
    k = 0.25 * RHO * V
    lift, drag = (qbar * cl + k * C * A["CLq"] * q) * S, qbar * cd * S
    fx, fz = -drag * np.cos(alpha) + lift * np.sin(alpha), -drag * np.sin(alpha) - lift * np.cos(alpha)
    my = (qbar * cm + k * C * A["Cmq"] * q) * S * C - (ARP[2] - CG[2]) * fx + (arp_x - CG[0]) * fz
    n = rpm / 60.0
    fx += ct(table, max(u, 0.0) / (n * DIAMETER)) * RHO * n * n * DIAMETER ** 4
    target = IDLE + np.clip(throttle, 0, 1) * (MAX_RPM - IDLE)
    return np.array([fx / MASS - G * np.sin(theta) - q * w, fz / MASS + G * np.cos(theta) + q * u, my / JYY, q,
                     u * np.cos(theta) + w * np.sin(theta), u * np.sin(theta) - w * np.cos(theta), (target - rpm) / LAG])


def trim(V, arp_x, table):
    def residual(z):
        alpha, elevator, throttle = z
        x = np.array([V * np.cos(alpha), V * np.sin(alpha), 0, alpha, 0, 0, IDLE + throttle * (MAX_RPM - IDLE)])
        return derivative(x, elevator, throttle, arp_x, table)[:3]
    return fsolve(residual, [0.07, -0.09, 0.28], xtol=1e-13)


def equilibrium_map(table, label, arp_x=CG[0]):
    alpha0, elevator, level = trim(15.0, arp_x, table)
    print(f"--- {label}: 15 m/s trim alpha={np.degrees(alpha0):.3f} deg, elevator {-np.degrees(elevator):.3f} deg up, level throttle {level * 100:.1f}%")
    guess = [alpha0, 15.0, 0.0]
    for throttle in [0.0, 0.2, level, 0.4, 0.5, 0.6, 0.7, 0.75, 0.8, 0.85, 0.9, 1.0]:
        rpm = IDLE + throttle * (MAX_RPM - IDLE)

        def residual(z):
            alpha, V, gamma = z
            x = np.array([V * np.cos(alpha), V * np.sin(alpha), 0, gamma + alpha, 0, 0, rpm])
            return derivative(x, elevator, throttle, arp_x, table)[:3]
        solution, _, status, _ = fsolve(residual, guess, full_output=True, xtol=1e-12)
        if status == 1 and np.max(np.abs(residual(solution))) < 1e-8 and solution[1] > 0:
            guess = solution
            print(f"throttle {throttle * 100:5.1f}%  alpha {np.degrees(solution[0]):6.3f} deg  V {solution[1]:6.2f} m/s  "
                  f"climb {np.degrees(solution[2]):6.2f} deg  {solution[1] * np.sin(solution[2]):5.2f} m/s")
        else:
            print(f"throttle {throttle * 100:5.1f}%  no steady straight flight with this elevator")


def step(arp_x, table, throttle, seconds=40.0, dt=1 / 240):
    alpha, elevator, level = trim(15.0, arp_x, table)
    x = np.array([15 * np.cos(alpha), 15 * np.sin(alpha), 0, alpha, 0, 300.0, IDLE + level * (MAX_RPM - IDLE)])
    t, inverted, max_q = 0.0, None, 0.0
    while t < seconds:
        command = level if t < 2.0 else throttle
        k1 = derivative(x, elevator, command, arp_x, table)
        k2 = derivative(x + dt / 2 * k1, elevator, command, arp_x, table)
        k3 = derivative(x + dt / 2 * k2, elevator, command, arp_x, table)
        k4 = derivative(x + dt * k3, elevator, command, arp_x, table)
        x, t = x + dt / 6 * (k1 + 2 * k2 + 2 * k3 + k4), t + dt
        max_q = max(max_q, abs(x[2]))
        if inverted is None and np.cos(x[3]) < 0:
            inverted = t
    return level, -np.degrees(elevator), inverted, max_q


if __name__ == "__main__":
    equilibrium_map(UIUC, "current UIUC APC 11x6 table")
    equilibrium_map(APC, "APC 12x6 table, 11149 rpm slice")
    margin = -A["Cma"] / A["CLa"]
    for label, table, target in [("baseline", UIUC, None), ("APC only", APC, None), ("margin 6% only", UIUC, 0.06), ("APC + margin 6%", APC, 0.06)]:
        arp_x = CG[0] if target is None else CG[0] - (margin - target) * C
        for throttle in [0.5, 0.75, 1.0]:
            level, up, inverted, max_q = step(arp_x, table, throttle)
            first = "none" if inverted is None else f"{inverted:.2f} s"
            print(f"{label:16s} step to {throttle * 100:3.0f}%: level throttle {level * 100:4.1f}%, elevator {up:.2f} deg up, "
                  f"first inversion {first}, max q {max_q:.3f} rad/s")
