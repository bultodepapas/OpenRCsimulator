"""Independent, standard-library reference for Johnson's steady mean inflow law.

Velocities passed to normalized() are scaled by hover induced velocity. The
function returns induced velocity divided by that scale, positive downward.
"""

from __future__ import annotations

from math import hypot, isfinite, sqrt
from typing import Any


# NASA/TP-2005-213477, Table 4. Velocities are normalized by v_h.
_A = -1.5
_B = -2.1
_C = 0.75
_D = -0.2
_N = -0.45
_N_TOTAL = 0.85
_X = -1.5
_X_TOTAL = 1.25
_E = -2.0
_M = 0.95

# Hayden's constants as reproduced in Khromov and Rand, ICAS 2008, Eq. (1.4).
_HAYDEN_ASYMPTOTE = 0.9926
_HAYDEN_QUADRATIC = 0.03794
_GROUND_HEIGHT_FLOOR = 0.5


def _number(value: Any, name: str) -> float:
    if isinstance(value, bool):
        raise ValueError(f"{name} must be a finite number")
    try:
        result = float(value)
    except (TypeError, ValueError, OverflowError) as exc:
        raise ValueError(f"{name} must be a finite number") from exc
    if not isfinite(result):
        raise ValueError(f"{name} must be a finite number")
    return result


def _failed(message: str) -> dict[str, Any]:
    return {"ok": False, "error": message}


def _momentum_residual(v: float, z: float, x: float) -> float:
    """Residual of v*sqrt(x*x + (z+v)*(z+v)) = 1."""
    return v * hypot(x, z + v) - 1.0


def _bisect_momentum_root(lo: float, hi: float, z: float, x: float) -> float:
    flo = _momentum_residual(lo, z, x)
    fhi = _momentum_residual(hi, z, x)
    if flo == 0.0:
        return lo
    if fhi == 0.0:
        return hi
    if (flo < 0.0) == (fhi < 0.0):
        raise ArithmeticError("momentum root was not bracketed")

    for _ in range(96):
        mid = lo + (hi - lo) * 0.5
        if mid == lo or mid == hi:
            break
        fm = _momentum_residual(mid, z, x)
        if abs(fm) <= 2.0e-15:
            return mid
        if (flo < 0.0) != (fm < 0.0):
            hi, fhi = mid, fm
        else:
            lo, flo = mid, fm
    return lo + (hi - lo) * 0.5


def momentum_roots(vz: float, vx: float) -> tuple[float, ...]:
    """Return all positive roots of the scalar momentum relation, in order.

    Splitting the search at every positive stationary point makes the root
    selection explicit in descent, where the relation can have three roots.
    A zero-crossflow cusp at z+v=0 is also a segment boundary.
    """
    z = _number(vz, "vz")
    x = abs(_number(vx, "vx"))
    upper = max(1.0, -z + 1.0)
    breaks = [0.0, upper]

    # d/dv of the unsquared momentum relation vanishes when
    # 2v^2 + 3zv + z^2 + x^2 = 0. This scaled discriminant avoids z*z overflow.
    az = abs(z)
    if z < 0.0 and az > 0.0 and x <= az / sqrt(8.0):
        discriminant_root = az * sqrt(max(0.0, 1.0 - 8.0 * (x / az) ** 2))
        center = -0.75 * z
        spread = 0.25 * discriminant_root
        for point in (center - spread, center + spread):
            if 0.0 < point < upper:
                breaks.append(point)

    if x == 0.0 and z < 0.0:
        cusp = -z
        if 0.0 < cusp < upper:
            breaks.append(cusp)

    breaks.sort()
    unique_breaks: list[float] = []
    for point in breaks:
        if not unique_breaks or abs(point - unique_breaks[-1]) > (
            2.0e-14 * max(1.0, abs(point), abs(unique_breaks[-1]))
        ):
            unique_breaks.append(point)

    roots: list[float] = []
    for point in unique_breaks:
        if point > 0.0 and abs(_momentum_residual(point, z, x)) <= 2.0e-13:
            roots.append(point)

    for lo, hi in zip(unique_breaks, unique_breaks[1:]):
        flo = _momentum_residual(lo, z, x)
        fhi = _momentum_residual(hi, z, x)
        if flo == 0.0 or fhi == 0.0:
            continue
        if (flo < 0.0) != (fhi < 0.0):
            roots.append(_bisect_momentum_root(lo, hi, z, x))

    roots.sort()
    unique_roots: list[float] = []
    for root in roots:
        if not unique_roots or abs(root - unique_roots[-1]) > (
            2.0e-11 * max(1.0, abs(root), abs(unique_roots[-1]))
        ):
            unique_roots.append(root)
    return tuple(unique_roots)


def _momentum_velocity(z: float, x: float, branch: str = "low") -> float:
    roots = momentum_roots(z, x)
    if not roots:
        raise ArithmeticError("no positive momentum-theory root")
    if branch == "high":
        return roots[-1]
    if branch == "low":
        return roots[0]
    if branch == "auto":
        # Outside the repaired baseline interval, the descent-side momentum
        # curve follows its windmill-brake branch whenever multiple roots exist.
        return roots[0]
    raise ValueError(f"unknown momentum branch: {branch}")


def _momentum_slope(z: float, x: float, v: float) -> float:
    denominator = x * x + (z + v) * (z + 2.0 * v)
    if abs(denominator) <= 1.0e-14:
        raise ArithmeticError("momentum-theory slope is singular at a fold")
    return -v * (z + v) / denominator


def _baseline(z: float, x: float) -> tuple[float, float]:
    """Return baseline induced velocity and its z slope."""
    if z < 0.0 and x < _C:
        ratio = x / _C
        z_a = _A + 0.2 * ratio * ratio
        z_b = _B + 0.2 * ratio * ratio
        if ratio > 0.5:
            z_b += 0.7 * (z_a - z_b) * (2.0 * ratio - 1.0) ** 3

        if z_b < z < z_a:
            v_a = _momentum_velocity(z_a, x, "high")
            slope_a = _momentum_slope(z_a, x, v_a)
            v_b = _momentum_velocity(z_b, x, "low")

            # Write p(z)=z*q(z), enforcing the published zero constant term.
            q_a = v_a / z_a
            q_slope_a = (slope_a - q_a) / z_a
            q_b = v_b / z_b
            curvature = (q_b - q_a - q_slope_a * (z_b - z_a)) / (
                (z_b - z_a) ** 2
            )
            offset = z - z_a
            q = q_a + q_slope_a * offset + curvature * offset * offset
            q_slope = q_slope_a + 2.0 * curvature * offset
            return z * q, q + z * q_slope

        branch = "high" if z >= z_a else "low"
        value = _momentum_velocity(z, x, branch)
        return value, _momentum_slope(z, x, value)

    value = _momentum_velocity(z, x, "auto")
    return value, _momentum_slope(z, x, value)


def _hermite(
    z0: float, y0: float, slope0: float,
    z1: float, y1: float, slope1: float,
    z: float,
) -> float:
    width = z1 - z0
    if width == 0.0:
        return y0
    t = (z - z0) / width
    t2 = t * t
    t3 = t2 * t
    return (
        (2.0 * t3 - 3.0 * t2 + 1.0) * y0
        + (t3 - 2.0 * t2 + t) * width * slope0
        + (-2.0 * t3 + 3.0 * t2) * y1
        + (t3 - t2) * width * slope1
    )


def _zero_intercept_cubic(
    z_anchor: float,
    value_anchor: float,
    slope_anchor: float,
    z_end: float,
    value_end: float,
    z: float,
) -> float:
    """Cubic p(z)=b*z+c*z^2+d*z^3 with one value/slope and an end value."""
    q_anchor = value_anchor / z_anchor
    q_slope_anchor = (slope_anchor - q_anchor) / z_anchor
    q_end = value_end / z_end
    curvature = (q_end - q_anchor - q_slope_anchor * (z_end - z_anchor)) / (
        (z_end - z_anchor) ** 2
    )
    offset = z - z_anchor
    q = q_anchor + q_slope_anchor * offset + curvature * offset * offset
    return z * q


def _vrs_increment(z: float, x: float) -> float:
    if z >= 0.0 or x >= _M:
        return 0.0

    x_ratio = x / _M
    radial = max(0.0, 1.0 - x_ratio * x_ratio)
    half_sum = 0.5 * (_N + _X)
    half_difference = 0.5 * (_N - _X)
    z_n = half_sum + half_difference * radial**0.2
    z_x = half_sum - half_difference * radial**1.5
    z_e = _E + (z_x - _X)
    z_d = _D

    if not (z_e < z < z_d):
        return 0.0

    # The endpoint values use momentum-theory velocities at the nominal N and
    # X stations, as the Table 3 expressions specify, even when the stations
    # have shifted with crossflow.
    scale = sqrt(max(0.0, 1.0 - x_ratio**6))
    v_n_momentum = _momentum_velocity(_N, x, "high")
    v_x_momentum = _momentum_velocity(_X, x, "high")
    delta_n = (_N_TOTAL - (_N + v_n_momentum)) * scale
    delta_x = (_X_TOTAL - (_X + v_x_momentum)) * scale

    _, base_slope_n = _baseline(z_n, x)
    _, base_slope_x = _baseline(z_x, x)
    delta_slope_n = -(1.0 + base_slope_n)
    delta_slope_x = -(1.0 + base_slope_x)

    if z >= z_n:
        return _hermite(z_d, 0.0, 0.0, z_n, delta_n, delta_slope_n, z)
    if z >= z_x:
        return _hermite(
            z_n, delta_n, delta_slope_n,
            z_x, delta_x, delta_slope_x,
            z,
        )

    # Table 3 prints D as the far endpoint of this E<z<X segment. D is outside
    # that interval, so this reference interprets that endpoint as E. The text
    # also specifies a zero constant coefficient rather than an E-end slope.
    return _zero_intercept_cubic(
        z_x, delta_x, delta_slope_x, z_e, 0.0, z
    )


def normalized(
    vz: float,
    vx: float,
    instability: float = 1.0,
    loss: float = 1.0,
) -> dict[str, Any]:
    """Return Johnson's steady induced velocity ratio v/v_h.

    vz is positive in climb; vx is a crossflow magnitude. instability is
    Johnson's VRS suppression parameter f in [0,1]. loss is κ, the multiplier
    on the resulting induced velocity.
    """
    try:
        z = _number(vz, "vz")
        x = abs(_number(vx, "vx"))
        f = _number(instability, "instability")
        kappa = _number(loss, "loss")
        if not 0.0 <= f <= 1.0:
            raise ValueError("instability must be in [0, 1]")
        if kappa <= 0.0:
            raise ValueError("loss must be positive")

        baseline, _ = _baseline(z, x)
        increment = _vrs_increment(z, x)
        ratio = kappa * (baseline + f * increment)
        if not isfinite(ratio):
            raise ValueError("normalized result is not finite")
        return {"ok": True, "ratio": ratio}
    except (ValueError, ArithmeticError) as exc:
        return _failed(str(exc))


def hayden_ground_factor(height_over_radius: float) -> float:
    """Hayden induced-inflow factor, unity at infinity, floored at h/R=0.5.

    ICAS 2008 reproduces k_G=0.9926+0.03794*(2R/z)^2 and applies 1/k_G to
    the induced-power term. Dividing by its far-field value 0.9926 makes the
    applied inflow multiplier exactly one at infinite clearance.
    """
    height = _number(height_over_radius, "height_over_radius")
    if height < 0.0:
        raise ValueError("height_over_radius must be nonnegative")
    h = max(_GROUND_HEIGHT_FLOOR, height)
    raw_k = _HAYDEN_ASYMPTOTE + _HAYDEN_QUADRATIC * (2.0 / h) ** 2
    return _HAYDEN_ASYMPTOTE / raw_k


def target(
    thrust: float,
    density: float,
    radius: float,
    climb: float,
    crossflow: float,
    height_over_radius: float = -1.0,
    loss: float = 1.0,
    instability: float = 1.0,
) -> dict[str, Any]:
    """Dimensional signed-thrust target, with caller-gated Hayden effect.

    climb is positive upward. The signed-thrust extension reflects Johnson's
    positive-thrust curve about the thrust axis. The hover scale is
    sqrt(abs(T)/(2*rho*pi*R^2)); returned velocity is positive downward for
    positive thrust. A height of -1 disables ground effect. A nonnegative
    height enables Hayden's correction for either thrust sign; the caller must
    pass it only when the downstream wake geometry meets the ground.
    """
    try:
        t = _number(thrust, "thrust")
        rho = _number(density, "density")
        r = _number(radius, "radius")
        w = _number(climb, "climb")
        u = abs(_number(crossflow, "crossflow"))
        height = _number(height_over_radius, "height_over_radius")
        if rho <= 0.0 or r <= 0.0:
            raise ValueError("density and radius must be positive")
        if height != -1.0 and height < 0.0:
            raise ValueError("height_over_radius must be -1 or nonnegative")

        if t == 0.0:
            return {
                "ok": True,
                "velocity": 0.0,
                "hover": 0.0,
                "ground_factor": 1.0,
            }

        direction = 1.0 if t > 0.0 else -1.0
        hover = sqrt(abs(t) / (2.0 * rho * 3.141592653589793 * r * r))
        if not isfinite(hover) or hover <= 0.0:
            raise ValueError("hover velocity scale is not finite and positive")

        ground_factor = 1.0
        if height >= 0.0:
            ground_factor = hayden_ground_factor(height)

        result = normalized(
            direction * w / hover,
            u / hover,
            instability=instability,
            loss=loss,
        )
        if not result["ok"]:
            return result
        velocity = direction * hover * float(result["ratio"]) * ground_factor
        if not isfinite(velocity):
            raise ValueError("dimensional result is not finite")
        return {
            "ok": True,
            "velocity": velocity,
            "hover": hover,
            "ground_factor": ground_factor,
        }
    except (ValueError, ArithmeticError) as exc:
        return _failed(str(exc))
