"""Dimensional first-order dynamic-inflow approximation.

Johnson's mean-inflow law provides an equilibrium target, not a measured
transient law. This module keeps the lag state dimensional so it remains
defined at zero rotor speed and residual wake can decay after a stop.
"""

from __future__ import annotations

from math import hypot, isfinite
from typing import Any

from johnson_inflow import target as steady_target


_LAG_COEFFICIENT = 0.849
_LAG_DENOMINATOR = 4.0


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


def lag_time_constant(
    radius_m: float,
    effective_speed_mps: float,
    velocity_floor_mps: float,
) -> float:
    """Return dimensional lag time ``0.849 R / (4 max(Veff, Vfloor))``.

    ``effective_speed_mps`` is a nonnegative stage-flow magnitude. The
    positive velocity floor keeps the model finite at zero flow and zero rotor
    speed; it also sets the longest time constant in this approximation.
    """
    radius = _number(radius_m, "radius_m")
    speed = _number(effective_speed_mps, "effective_speed_mps")
    floor = _number(velocity_floor_mps, "velocity_floor_mps")
    if radius <= 0.0:
        raise ValueError("radius_m must be positive")
    if speed < 0.0:
        raise ValueError("effective_speed_mps must be nonnegative")
    if floor <= 0.0:
        raise ValueError("velocity_floor_mps must be positive")
    tau = _LAG_COEFFICIENT * radius / (
        _LAG_DENOMINATOR * max(speed, floor)
    )
    if not isfinite(tau) or tau <= 0.0:
        raise ValueError("tau_s must be finite and positive")
    return tau


def derivative(
    vi_mps: float,
    target_mps: float,
    radius_m: float,
    effective_speed_mps: float,
    velocity_floor_mps: float,
) -> dict[str, Any]:
    """Return ``{ok, rate_mps2, tau_s}`` for a dimensional induced-velocity state.

    The state and target use the same signed wake-axis convention. There is no
    ``omega`` argument: at zero rotor speed the same finite lag law lets a
    residual wake decay toward the current target.
    """
    try:
        vi = _number(vi_mps, "vi_mps")
        target = _number(target_mps, "target_mps")
        tau = lag_time_constant(radius_m, effective_speed_mps, velocity_floor_mps)
        rate = (target - vi) / tau
        if not isfinite(rate):
            raise ValueError("rate_mps2 is not finite")
        return {"ok": True, "rate_mps2": rate, "tau_s": tau}
    except (ValueError, ArithmeticError) as exc:
        return _failed(str(exc))


def evaluate(
    vi_mps: float,
    thrust_n: float,
    density_kg_m3: float,
    radius_m: float,
    climb_mps: float,
    crossflow_mps: float,
    velocity_floor_mps: float,
    height_over_radius: float = -1.0,
    loss: float = 1.0,
    instability: float = 1.0,
) -> dict[str, Any]:
    """Evaluate the steady target and dimensional lag at one RK stage.

    Climb is positive upward, induced velocity is positive down the wake axis
    for positive thrust, and crossflow is a magnitude. The effective flow is
    ``hypot(crossflow, vi + climb)``. This feedback definition follows the
    rotor-relative inflow geometry; the lag coefficient itself remains a
    chosen first-order approximation rather than a Johnson transient law.
    """
    try:
        vi = _number(vi_mps, "vi_mps")
        thrust = _number(thrust_n, "thrust_n")
        density = _number(density_kg_m3, "density_kg_m3")
        radius = _number(radius_m, "radius_m")
        climb = _number(climb_mps, "climb_mps")
        crossflow = _number(crossflow_mps, "crossflow_mps")
        if crossflow < 0.0:
            raise ValueError("crossflow_mps must be a nonnegative magnitude")

        equilibrium = steady_target(
            thrust,
            density,
            radius,
            climb,
            crossflow,
            height_over_radius=height_over_radius,
            loss=loss,
            instability=instability,
        )
        if not equilibrium["ok"]:
            raise ValueError(str(equilibrium.get("error", "steady target failed")))

        effective_speed = hypot(crossflow, vi + climb)
        lag = derivative(
            vi,
            float(equilibrium["velocity"]),
            radius,
            effective_speed,
            velocity_floor_mps,
        )
        if not lag["ok"]:
            raise ValueError(str(lag.get("error", "dynamic inflow derivative failed")))
        return {
            "ok": True,
            "rate_mps2": float(lag["rate_mps2"]),
            "tau_s": float(lag["tau_s"]),
            "target_mps": float(equilibrium["velocity"]),
            "hover_mps": float(equilibrium["hover"]),
            "ground_factor": float(equilibrium["ground_factor"]),
            "effective_speed_mps": effective_speed,
        }
    except (ValueError, ArithmeticError) as exc:
        return _failed(str(exc))

