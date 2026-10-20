"""Static margin and phugoid from published Ultra Stick linear models (no data files read).

Run: python3 -I model_check.py
Sources (numbers typed from the PDFs):
- Thor / Ultra Stick 25e: Dorobantu 2013 PhD (UMN), eq. 3.25 identified Alon/Blon,
  Table 2.1 (m 1.90 kg, S 0.32 m^2, c 0.30 m), Table 3.1 (Iy 0.144 kg m^2);
  trim 19 m/s (Dorobantu et al. 2012 sec. IV). States [u w q theta], SI, rad.
- Ultra Stick 120 "Ibis": Lie 2014 PhD (UMN) Appendix D: m 8.338 kg, S 0.7692 m^2,
  c 0.4336 m, Iyy 1.0095 kg m^2, trim V 19.20 m/s, alpha 4.47 deg, theta 5.47 deg,
  delta_e -4.37 deg; Table D.2 derivatives (A-matrix entries).
Measured trim-curve slopes dδe/dCL come from trim_cl.py (Baldr = another Ultra Stick 120).
"""
import numpy as np

RHO = 1.225
G = 9.80665


def analyse(name, A, B, m, S, c, Iy, U, measured):
    qbar = 0.5 * RHO * U * U
    Xu, Xw, Xq, Xth = A[0]
    Zu, Zw, Zq, Zth = A[1]
    Mu, Mw, Mq, _ = A[2]
    Xde, Zde, Mde = B[0], B[1], B[2]
    Cmde = Mde * Iy / (qbar * S * c)
    Cma = Mw * Iy * U / (qbar * S * c)
    CLa_plus_CD = -Zw * m * U / (qbar * S)
    SM = -Cma / CLa_plus_CD
    CLtrim = m * G / (qbar * S)
    ev = np.linalg.eigvals(np.array(A, float))
    print(f"\n## {name}\n")
    print(f"q = {qbar:.1f} Pa, CL_trim = {CLtrim:.3f}")
    print(f"Cm_de = {Cmde:+.3f} /rad, Cm_alpha = {Cma:+.3f} /rad, CL_alpha(+CD) = {CLa_plus_CD:.2f} /rad, static margin from model = {100*SM:.1f} % MAC")
    for e in ev:
        if abs(e.imag) > 1e-6 and e.imag > 0:
            wn = abs(e); z = -e.real / wn
            print(f"  mode: wn {wn:.3f} rad/s, zeta {z:.3f}, period {2*np.pi/e.imag:.1f} s")
        elif abs(e.imag) <= 1e-6:
            print(f"  real pole {e.real:+.3f} 1/s")
    # level-flight elevator gradient: unknowns dw, dde for du = 1, level => dtheta = dw/U, q = 0; thrust balances X.
    # Z: Zu du + Zw dw + Zth dtheta + Zde dde = 0 ; M: Mu du + Mw dw + Mde dde = 0
    Mx = np.array([[Zw + Zth / U, Zde], [Mw, Mde]])
    rhs = -np.array([Zu, Mu])
    dw, dde = np.linalg.solve(Mx, rhs)
    print(f"Level-flight trim gradient from the linear model: dδe/dV = {np.degrees(dde):+.3f} deg/(m/s), dα/dV = {np.degrees(dw/U):+.3f} deg/(m/s)")
    # same without Mu (pure static-stability part)
    dw0, dde0 = np.linalg.solve(Mx, -np.array([Zu, 0.0]))
    print(f"  without Mu (speed-moment term): dδe/dV = {np.degrees(dde0):+.3f} deg/(m/s)")
    print(f"  CL-only estimate SM/Cm_de * dCL/dV = {np.degrees(SM / Cmde * (-2 * CLtrim / U)):+.3f} deg/(m/s)")
    for lab, k in measured:
        sm = Cmde * np.radians(k)
        print(f"Measured {lab}: dδe/dCL = {k:+.2f} deg -> static margin ≈ Cm_de·dδe/dCL = {100*sm:.1f} % MAC (using this model's Cm_de)")


A_thor = [[-0.38, 0.60, -0.36, -9.80], [-0.98, -10.65, 16.74, -0.21], [0.18, -5.39, -16.55, 0.0], [0, 0, 1, 0]]
B_thor = [-0.36, -3.621, -141.57]
analyse("Thor (Ultra Stick 25e), Dorobantu identified model, 19 m/s", A_thor, B_thor, 1.90, 0.32, 0.30, 0.144, 19.0,
        [("Thor 2012 manual flights", -6.73)])
A_base = [[-0.38, 0.60, -0.36, -9.80], [-0.98, -7.81, 15.32, -0.21], [0.18, -8.31, -35.21, 0.0], [0, 0, 1, 0]]
B_base = [-0.36, -3.62, -106.32]
analyse("Thor baseline (pre-identification) model", A_base, B_base, 1.90, 0.32, 0.30, 0.144, 19.0, [])
A_ibis = [[-0.437, -0.621, 6.777, -9.765], [-0.605, -4.236, 18.149, -0.940], [-0.112, -2.008, -3.535, 0.0], [0, 0, 1, 0]]
B_ibis = [13.444, 1.077, -37.329]
analyse("Ultra Stick 120 'Ibis', Lie Appendix D model, 19.2 m/s", A_ibis, B_ibis, 8.338, 0.7692, 0.4336, 1.0095, 19.2,
        [("Baldr nominal CG (F12, F14)", -9.79), ("Baldr F17 aft CG", -6.17)])
