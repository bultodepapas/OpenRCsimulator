#!/usr/bin/env python3
"""GP-07c: coefficient of restitution of one soft hull contact (physics/hull_contact.gd) as integrated in flight.

One point of normal effective mass m_n meets flat ground. Its spring and damper are sized on the point's smallest
effective mass over 26 body directions (m_min ≤ m_n): k = m_min·ω², c = 2ζ·m_min·ω, with the damping ramped in over
the first DAMPING_ONSET_M of compression and the force clamped at zero (a damper never pulls). Integrated with
classical RK4 at 240 Hz like the session. e = rebound speed / impact speed.

The clamp ends the contact while the damper still brakes the rebound, so e is far above the linear spring-damper value
exp(−ζπ/√(1−ζ²)) (0.046 at ζ 0.7); the ramp makes small touches livelier. Run: python3 restitution_probe.py
"""
import math

OMEGA = 60.0
ZETA = 0.7
ONSET_M = 0.004
DT = 1.0 / 240.0


def restitution(v_in, mass_ratio):
    """mass_ratio = m_min / m_n (≤ 1)."""
    m_min, m_n = 1.0, 1.0 / mass_ratio
    k, c = m_min * OMEGA ** 2, 2.0 * ZETA * m_min * OMEGA

    def accel(x, u):
        if x <= 0.0:
            return 0.0
        return -max(0.0, k * x + c * min(x / ONSET_M, 1.0) * u) / m_n

    x, u, t = -1e-9, v_in, 0.0
    while t < 2.0:
        k1 = (u, accel(x, u))
        k2 = (u + DT / 2 * k1[1], accel(x + DT / 2 * k1[0], u + DT / 2 * k1[1]))
        k3 = (u + DT / 2 * k2[1], accel(x + DT / 2 * k2[0], u + DT / 2 * k2[1]))
        k4 = (u + DT * k3[1], accel(x + DT * k3[0], u + DT * k3[1]))
        x += DT / 6 * (k1[0] + 2 * k2[0] + 2 * k3[0] + k4[0])
        u += DT / 6 * (k1[1] + 2 * k2[1] + 2 * k3[1] + k4[1])
        t += DT
        if x < 0.0 and u < 0.0:
            return -u / v_in
    return 0.0


def main():
    speeds = (0.1, 0.3, 1.0, 2.0, 4.0, 8.0)
    print("impact speed (m/s):        " + "  ".join("%5.1f" % v for v in speeds))
    for ratio, label in ((1.0, "m_n = m_min (wing tip)"), (0.5, "m_n = 2 m_min"), (0.2, "m_n = 5 m_min (near CG)")):
        print("%-27s" % label + "  ".join("%5.2f" % restitution(v, ratio) for v in speeds))
    print("linear spring-damper, zeta %.1f, no clamp: %.3f" % (ZETA, math.exp(-ZETA * math.pi / math.sqrt(1 - ZETA ** 2))))


if __name__ == "__main__":
    main()
