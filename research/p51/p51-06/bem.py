"""P51-06: blade-element/momentum propeller model shared by derive_physics.py and the Mejzlik calibration.

Induced-velocity form (stable at zero airspeed), Prandtl tip loss, geometric-pitch twist, generic section. Two
calibration factors (P51-06): pitch_factor scales the geometric pitch (gas-propeller nominal pitch understates the
blade's aerodynamic pitch), chord_factor scales the planform; fitted to Mejzlik's 26x12 2- and 3-blade tables by
fit_mejzlik.py.
"""
import math

RHO = 1.225


def bem_tables(diameter, pitch, blades, planform, n_rps=100.0, pitch_factor=1.0, chord_factor=1.0, j_max=2.0):
    """Ct(J), Cp(J) by blade-element/momentum theory in induced-velocity form (stable at zero airspeed), Prandtl tip
    loss, geometric-pitch twist. Generic section: a0 = 0.9 x 2 pi, zero-lift angle -3 deg, Cl capped at +-1.2,
    Cd = 0.012 + 0.025 Cl^2. Returns [[J, Ct], ...], [[J, Cp], ...] from J = 0 into the windmilling branch (Ct < -0.06), so the
    simulation interpolates rather than extrapolates at high J and low rpm."""
    R = diameter / 2
    a0, alpha_zl, cl_max, cl_min_wm, cd0, k_cd = 2 * math.pi * 0.9, math.radians(-3.0), 1.2, 0.8, 0.012, 0.025
    table = lambda rows, x: next((r0[1] + (r1[1] - r0[1]) * (x - r0[0]) / (r1[0] - r0[0]) for r0, r1 in zip(rows, rows[1:]) if r0[0] <= x <= r1[0]), rows[-1][1])
    omega = 2 * math.pi * n_rps
    ct_rows, cp_rows = [], []
    J = 0.0
    while True:
        Vinf = J * n_rps * diameter
        thrust = torque = 0.0
        n_el = 40
        for i in range(n_el):
            x = 0.2 + 0.8 * (i + 0.5) / n_el
            r = x * R
            dr = 0.8 * R / n_el
            c = table(planform, x) * R * chord_factor
            beta = math.atan(pitch * pitch_factor / (2 * math.pi * r))
            wa = 0.1 * omega * r  # induced axial velocity, first guess
            wt = 0.0  # induced swirl
            for _ in range(300):
                Va = Vinf + wa
                Vt = omega * r - wt
                phi = math.atan2(Va, Vt)
                alpha = beta - phi
                cl = max(-cl_min_wm, min(cl_max, a0 * (alpha - alpha_zl)))  # windmilling: the section stalls near -8 deg
                cd = cd0 + k_cd * cl * cl + (0.02 * (alpha_zl - alpha) / 0.1 if alpha < alpha_zl - 0.14 else 0.0)  # post-stall drag rise
                W2 = Va * Va + Vt * Vt
                cn = cl * math.cos(phi) - cd * math.sin(phi)
                ctan = cl * math.sin(phi) + cd * math.cos(phi)
                dT = 0.5 * RHO * W2 * c * cn * blades  # per unit radius
                dQr = 0.5 * RHO * W2 * c * ctan * blades  # torque per unit radius / r
                f = blades / 2 * (R - r) / max(r * abs(math.sin(phi)), 1e-6)
                F = max(2 / math.pi * math.acos(min(1.0, math.exp(-f))), 0.05)
                # Momentum: dT = 4 pi r F rho (Vinf + wa) wa; dQ/r = 4 pi r F rho (Vinf + wa) wt * r
                disc = Vinf * Vinf + max(dT, 0.0) / (math.pi * r * F * RHO)
                wa_new = (-Vinf + math.sqrt(disc)) / 2 if dT > 0 else 0.0
                wt_new = dQr / (4 * math.pi * r * F * RHO * max(Vinf + wa_new, 1e-3)) if dQr > 0 else 0.0
                if abs(wa_new - wa) < 1e-5 and abs(wt_new - wt) < 1e-5:
                    wa, wt = wa_new, wt_new
                    break
                wa += 0.3 * (wa_new - wa)
                wt += 0.3 * (wt_new - wt)
            thrust += dT * dr
            torque += dQr * r * dr
        Ct = thrust / (RHO * n_rps ** 2 * diameter ** 4)
        Cp = torque * omega / (RHO * n_rps ** 3 * diameter ** 5)
        ct_rows.append([round(J, 3), round(Ct, 5)])
        cp_rows.append([round(J, 3), round(Cp, 5)])
        # Into the windmilling branch (Cp < 0: the air drives the propeller), so the shaft model finds the idle
        # glide's rpm inside the table rather than by extrapolation.
        if (Cp < -0.04 and Ct < -0.1) or J > j_max - 1e-9:
            break
        J += 0.05
    return ct_rows, cp_rows


