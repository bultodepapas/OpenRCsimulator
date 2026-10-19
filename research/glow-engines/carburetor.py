"""NITRO-06: Python mirror of app/physics/glow/carburetor.gd, the glow carburettor as a flow restriction.

The transmitter throttle positions a barrel whose open area admits air through a nozzle. At a small opening the
nozzle chokes, so the air mass flow is fixed by the opening alone and the charge per cycle falls as 1/rpm; at a large
opening the engine's own breathing sets the flow. The mean-cycle kernels take ``admission``, the charge per cycle
relative to the wide-open throttle at the same rpm.

Nozzle flow (Heywood, Internal Combustion Engine Fundamentals, 1988, section 7.6.2, eqs. 7.26-7.28), with r the
manifold-to-ambient pressure ratio: m = Cd*A*p0/sqrt(R*T0)*Psi(r), Psi = r**(1/g)*sqrt(2g/(g-1)*(1-r**((g-1)/g)))
above the critical ratio r_c = (2/(g+1))**(g/(g-1)) and the constant Psi_c = sqrt(g)*(2/(g+1))**((g+1)/(2(g-1)))
below it. The isothermal manifold demand r*rho0*V_d*eta_b*n/(60*revs) balances the nozzle: r*x = a*g(r) with
x = demand/capacity and a the open-area fraction, so r depends on y = a/x alone. Admission = r(a, n)/r(1, n).
Barrel geometry: the lens common to two equal circles offset by u = d/(2R), slid linearly from the idle stop.
"""
from __future__ import annotations

import math

GAMMA = 1.4
R_AIR = 287.05
T_REFERENCE_K = 288.15
CRITICAL_RATIO = (2.0 / (GAMMA + 1.0)) ** (GAMMA / (GAMMA - 1.0))
PSI_CHOKED = math.sqrt(GAMMA) * (2.0 / (GAMMA + 1.0)) ** ((GAMMA + 1.0) / (2.0 * (GAMMA - 1.0)))
ROOT_ITERATIONS = 64
LENS_ITERATIONS = 64


def flow_function(r: float) -> float:
    """Normalised nozzle flow g(r) = Psi(r)/Psi_c: 1 when choked, 0 at r = 1."""
    if not math.isfinite(r) or r <= CRITICAL_RATIO:
        return 1.0
    if r >= 1.0:
        return 0.0
    k = (GAMMA - 1.0) / GAMMA
    inner = 2.0 * GAMMA / (GAMMA - 1.0) * (1.0 - r ** k)
    return r ** (1.0 / GAMMA) * math.sqrt(max(inner, 0.0)) / PSI_CHOKED


def charge_ratio(y: float) -> float:
    """Manifold pressure ratio for y = a/x: y when choked, else the root of r = y*g(r) in (r_c, 1)."""
    if not math.isfinite(y) or y < 0.0:
        return math.nan
    if y <= CRITICAL_RATIO:
        return y
    lo, hi = CRITICAL_RATIO, 1.0
    for _ in range(ROOT_ITERATIONS):
        mid = 0.5 * (lo + hi)
        if mid - y * flow_function(mid) > 0.0:
            hi = mid
        else:
            lo = mid
    return 0.5 * (lo + hi)


def demand_ratio_for_charge(r: float) -> float:
    """Inverse of charge_ratio: the y that produces the pressure ratio r (r/g(r))."""
    if not math.isfinite(r) or r <= 0.0 or r >= 1.0:
        return math.nan
    return r / flow_function(r)


def lens_fraction(u: float) -> float:
    """Open-area fraction of two equal circles offset by u = d/(2R)."""
    if not math.isfinite(u):
        return math.nan
    if u <= 0.0:
        return 1.0
    if u >= 1.0:
        return 0.0
    return 2.0 / math.pi * (math.acos(u) - u * math.sqrt(1.0 - u * u))


def idle_offset(idle_opening: float) -> float:
    """Offset at which the lens equals the idle opening."""
    if not math.isfinite(idle_opening) or idle_opening <= 0.0 or idle_opening >= 1.0:
        return math.nan
    lo, hi = 0.0, 1.0
    for _ in range(LENS_ITERATIONS):
        mid = 0.5 * (lo + hi)
        if lens_fraction(mid) > idle_opening:
            lo = mid
        else:
            hi = mid
    return 0.5 * (lo + hi)


def opening(servo: float, idle_offset_u: float, travel_exponent: float = 1.0) -> float:
    """Open-area fraction for a servo fraction in [0, 1] along u = u_idle*(1 - servo)**travel_exponent."""
    if not math.isfinite(servo) or not math.isfinite(idle_offset_u) or idle_offset_u < 0.0 or idle_offset_u > 1.0 \
            or not math.isfinite(travel_exponent) or travel_exponent <= 0.0:
        return math.nan
    closed = 1.0 - min(max(servo, 0.0), 1.0)
    return lens_fraction(idle_offset_u * (closed ** travel_exponent if closed > 0.0 else 0.0))


def capacity_m3_s(effective_area_m2: float) -> float:
    """Choked volumetric capacity of the fully open path (ambient-density m3/s)."""
    if not math.isfinite(effective_area_m2) or effective_area_m2 <= 0.0:
        return math.nan
    return effective_area_m2 * PSI_CHOKED * math.sqrt(R_AIR * T_REFERENCE_K)


def effective_area_for_capacity(capacity: float) -> float:
    return capacity / (PSI_CHOKED * math.sqrt(R_AIR * T_REFERENCE_K))


def demand_m3_s(rpm: float, breathing: float, displacement_m3: float, cycle_revolutions: float) -> float:
    """Wide-open volumetric demand (ambient-density m3/s)."""
    values = (rpm, breathing, displacement_m3, cycle_revolutions)
    if not all(math.isfinite(v) for v in values) or rpm < 0.0 or breathing < 0.0 or displacement_m3 <= 0.0 \
            or cycle_revolutions <= 0.0:
        return math.nan
    return displacement_m3 * breathing * rpm / (60.0 * cycle_revolutions)


def admission(open_fraction: float, rpm: float, breathing: float, displacement_m3: float,
              cycle_revolutions: float, capacity: float) -> float:
    """Charge per cycle relative to the wide-open throttle at the same speed."""
    if not math.isfinite(open_fraction) or open_fraction <= 0.0 or open_fraction > 1.0 \
            or not math.isfinite(capacity) or capacity <= 0.0:
        return math.nan
    demand = demand_m3_s(rpm, breathing, displacement_m3, cycle_revolutions)
    if not math.isfinite(demand):
        return math.nan
    if demand <= 0.0:
        return 1.0
    x = demand / capacity
    restricted = charge_ratio(open_fraction / x)
    wide_open = charge_ratio(1.0 / x)
    if not math.isfinite(restricted) or not math.isfinite(wide_open) or wide_open <= 0.0:
        return math.nan
    return min(restricted / wide_open, 1.0)


def sample_table(table: list, query: float) -> float:
    """Piecewise-linear [[x, y], ...] table as the glow profiles store it (clamped outside)."""
    pairs = [(float(x), float(y)) for x, y in table]
    if query <= pairs[0][0]:
        return pairs[0][1]
    for (x0, y0), (x1, y1) in zip(pairs, pairs[1:]):
        if query <= x1:
            return y0 + (y1 - y0) * (query - x0) / (x1 - x0)
    return pairs[-1][1]
