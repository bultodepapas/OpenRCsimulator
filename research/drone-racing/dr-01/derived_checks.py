#!/usr/bin/env python3
"""DR-01 derived checks for a typical 5.1-inch tri-blade, 4S racing quad.

Every input below is a typical/estimated value unless its comment names a source. The script exists so the
numbers quoted in docs/research/drone-racing/DR-01/README.md can be regenerated; it measures nothing.
Run: python3 -I research/drone-racing/dr-01/derived_checks.py
"""
import math

RHO = 1.225          # kg/m3, sea level
G = 9.81             # m/s2
DT = 1.0 / 240.0     # s, simulation tick

# Typical race build (estimated): 650 g AUW, 5.1 x 4.3 x 3 prop, 2306 2450 KV, 4S, 14-pole motor
M = 0.650
D = 5.1 * 0.0254
R = D / 2
A = math.pi * R * R
PITCH_IN = 4.3
KV = 2450
BLADES = 3
POLE_PAIRS = 7
RM = 0.06            # ohm, winding equivalent (estimated)
I0 = 1.0             # A, no-load current (estimated)
J_ROTOR = 7e-6       # kg m2, prop ~5e-6 + bell ~2e-6 (estimated)
T_MAX_KGF = 1.5      # typical bench figure for this class at 100 % on 4S (miniquadtestbench-class value)
RPM_MAX = 30000.0
CP_STATIC = 0.05     # estimated power coefficient (Cp/Ct ~ 0.3)
V_BUS = 4 * 3.8      # V under load (estimated)
R_PACK = 0.012       # ohm, 4 x 3 mOhm cells (community figure, estimated)
CDA = 0.012          # m2, frame drag area (estimated)


def main() -> None:
    t_h = M * G / 4
    v_h = math.sqrt(t_h / (2 * RHO * A))
    print(f"R={R*1000:.1f} mm  A={A*1e4:.2f} cm2/rotor  T_hover={t_h:.2f} N/rotor  disc loading={t_h/A:.0f} N/m2  v_h={v_h:.1f} m/s")
    n_max = RPM_MAX / 60
    ct = T_MAX_KGF * G / (RHO * n_max ** 2 * D ** 4)
    n_h = math.sqrt(t_h / (ct * RHO * D ** 4))
    print(f"Ct_static={ct:.3f} (T_max {T_MAX_KGF*G:.1f} N at {RPM_MAX:.0f} rpm)  T/W={4*T_MAX_KGF*G/(M*G):.1f}  hover rpm={n_h*60:.0f} ({n_h*60/RPM_MAX:.2f} of max)")
    for rpm in (n_h * 60, 20000, 30000):
        n = rpm / 60
        print(f"rpm {rpm:6.0f}: blade-pass {n*BLADES:6.0f} Hz, commutation {n*POLE_PAIRS:6.0f} Hz, "
              f"rev/tick {n*DT:.2f}, rev/frame(60 fps) {n/60:.2f}, tip speed {n*2*math.pi*R:.0f} m/s (M {n*2*math.pi*R/343:.2f})")
    r75 = 0.75 * R
    print(f"theta(0.75R)={math.degrees(math.atan(PITCH_IN*0.0254/(2*math.pi*r75))):.1f} deg, "
          f"theta(tip)={math.degrees(math.atan(PITCH_IN*0.0254/(2*math.pi*R))):.1f} deg for {PITCH_IN} in helical pitch")
    v75 = 25000 / 60 * 2 * math.pi * r75
    print(f"Re(0.75R, 25 kRPM, c=14 mm)={RHO*v75*0.014/1.81e-5:.2e}")
    kt = 60 / (2 * math.pi * KV)
    kv_si = KV * 2 * math.pi / 60

    def torque(n: float) -> float:
        return CP_STATIC * RHO * n ** 3 * D ** 5 / (2 * math.pi * n)

    q_h = torque(n_h)
    i_h = q_h / kt + I0
    e_h = n_h * 60 / KV
    print(f"hover: Q={q_h*1e3:.1f} mN m, I={i_h:.1f} A/motor ({4*i_h:.0f} A pack), back-EMF {e_h:.2f} V, duty {(e_h+i_h*RM)/V_BUS:.2f} at {V_BUS:.1f} V")
    q_m = torque(n_max)
    i_m = q_m / kt + I0
    print(f"full: Q={q_m*1e3:.0f} mN m, I={i_m:.0f} A/motor ({4*i_m:.0f} A pack), P_elec {4*i_m*V_BUS:.0f} W, pack sag {4*i_m*R_PACK:.2f} V at {R_PACK*1e3:.0f} mOhm")
    w_h = n_h * 2 * math.pi
    cq = q_h / w_h ** 2
    tau = J_ROTOR / (kt / (kv_si * RM) + 2 * cq * w_h)
    print(f"J={J_ROTOR:.1e} kg m2, cq={cq:.2e} N m s2, motor time constant about hover ~{tau*1e3:.1f} ms (dt/tau={DT/tau:.2f})")
    print("explicit-step ratio dt*kt^2/(Rm*J) (flight_session.gd ELECTRIC_MAX_STEP_RATIO = 0.25):")
    for name, kv, rm, j in (("2306 2450KV Rm 0.06 J 7e-6", 2450, 0.06, 7e-6), ("2306 2450KV Rm 0.04 J 7e-6", 2450, 0.04, 7e-6),
                            ("2207 1750KV Rm 0.09 J 7e-6", 1750, 0.09, 7e-6), ("2306 2450KV Rm 0.06 J 4e-6", 2450, 0.06, 4e-6),
                            ("2306 2450KV Rm 0.06 J 1e-5", 2450, 0.06, 1e-5)):
        k = 60 / (2 * math.pi * kv)
        print(f"  {name}: ratio={DT*k*k/(rm*j):.2f}, tau_em={rm*j/(k*k)*1e3:.1f} ms")
    om_h = n_h * 2 * math.pi
    lam_h = v_h / (om_h * R)
    print(f"lambda_h={lam_h:.3f}; inflow time constant 0.849/(4 lambda Omega)={0.849/(4*lam_h*om_h)*1e3:.2f} ms (quasi-static at dt={DT*1e3:.2f} ms)")
    for z in (0.05, 0.08, 0.15, 0.30):
        print(f"ground effect z={z:.2f} m (z/R={z/R:.2f}): T_IGE/T_OGE={1/(1-(R/(4*z))**2):.2f}")
    print(f"VRS window (Johnson -0.45..-1.5 v_h): {0.45*v_h:.1f}..{1.5*v_h:.1f} m/s descent at low forward speed")
    for v in (10, 25, 44):
        print(f"V={v} m/s: J=V/(nD) at 25 kRPM={v/(25000/60*D):.2f}, mu=V/(Omega R)={v/(25000/60*2*math.pi*R):.2f}, frame drag {0.5*RHO*v*v*CDA:.1f} N ({0.5*RHO*v*v*CDA/(M*G):.2f} g)")
    print(f"one tick at 30 m/s = {30*DT*100:.1f} cm (sub-tick gate-plane interpolation needed for ms timing)")
    l_arm = 0.110 / math.sqrt(2)
    print(f"X-frame lever {l_arm*1e3:.1f} mm; roll moment from +-1.6 N per pair = {2*1.6*l_arm*1e3:.0f} mN m; "
          f"with Ixx 2.5e-3 kg m2: {2*1.6*l_arm/2.5e-3:.0f} rad/s2 ({math.degrees(2*1.6*l_arm/2.5e-3):.0f} deg/s2)")
    for drpm in (3000,):
        h = J_ROTOR * 2 * (drpm / 60 * 2 * math.pi)
        print(f"differential rpm +-{drpm}: net rotor momentum {h*1e3:.2f} mN m s; precession at 1000 deg/s = {h*math.radians(1000)*1e3:.1f} mN m")
    for rpm in (25000, 35000):
        n = rpm / 60
        print(f"audio at {rpm} rpm: shaft {n:.0f} Hz, blade-pass {n*BLADES:.0f} Hz, electrical {n*POLE_PAIRS:.0f} Hz")

    def actual(x: float, c: float, m: float, e: float) -> float:
        return x * c + max(0.0, m - c) * abs(x) * (x ** 5 * e + x * (1 - e))

    def betaflight(x: float, rc: float, sr: float, e: float) -> float:
        rcr = rc + (14.54 * (rc - 2) if rc > 2 else 0.0)
        xe = x * abs(x) ** 3 * e + x * (1 - e)
        return 200 * rcr * xe / max(0.01, min(1.0, 1 - abs(x) * sr))

    print("stick   actual(70/670/0.54)  actual(70/670/0, firmware default)  betaflight(1.0/0.70/0)")
    for x in (0.1, 0.25, 0.5, 0.75, 1.0):
        print(f"{x:4.2f}   {actual(x, 70, 670, 0.54):7.0f} deg/s   {actual(x, 70, 670, 0.0):7.0f} deg/s   {betaflight(x, 1.0, 0.70, 0.0):7.0f} deg/s")
    print(f"prop disc coverage N c/(2 pi r) for c=14 mm: at 0.7R {BLADES*0.014/(2*math.pi*0.7*R)*100:.0f} %, at 0.2R {BLADES*0.014/(2*math.pi*0.2*R)*100:.0f} %")
    print(f"120 deg horizontal FOV at 16:9 -> vertical {2*math.degrees(math.atan(math.tan(math.radians(60))*9/16)):.1f} deg; 137 deg -> {2*math.degrees(math.atan(math.tan(math.radians(68.5))*9/16)):.1f} deg")


if __name__ == "__main__":
    main()
