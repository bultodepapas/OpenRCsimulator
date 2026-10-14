"""Standalone Gavrilets-style tail-rotor reference kernel.

The source tail section evaluates a local linear thrust law around trim. This
module derives its two slopes from the source momentum/blade-element equations
using an explicit wake-efficiency parameter, then follows the source's
through-origin Eq. 47 law, cap, wake ramp, inflow approximation, and torque
equation. It is a research reference, not a qualified tail-rotor model.

All body vectors use FRD: +x forward, +y right, +z down. Positive collective
produces positive local tail thrust T and body force Fy=-T in the source X-Cell
orientation. The tail rotor shaft reaction torque is about +y and reverses
with `rotation_sense`; the source force and its hub moments do not.
"""

from __future__ import annotations

from math import hypot, isfinite, pi, sqrt
from numbers import Real
from types import MappingProxyType
from typing import Any, Mapping, Sequence


PARAMETER_KEYS = frozenset(
    {
        "rho_kg_m3",
        "main_rotor_radius_m",
        "tail_rotor_radius_m",
        "blade_chord_m",
        "rotor_blade_count",
        "blade_lift_curve_slope_per_rad",
        "blade_section_cd0",
        "thrust_coefficient_max",
        "tail_to_main_speed_ratio",
        "hub_distance_aft_m",
        "hub_height_above_cg_m",
        "vertical_fin_area_m2",
        "trim_collective_rad",
        "wake_efficiency",
        "rotation_sense",
    }
)
LAW = "openrc-xcell-linearized-tail-v1"

INPUT_KEYS = frozenset(
    {
        "omega_main_rad_s",
        "main_induced_velocity_m_s",
        "cg_air_velocity_body_frd_m_s",
        "body_rates_body_frd_rad_s",
        "tail_collective_rad",
    }
)

_DERIVED_PARAMETER_KEYS = frozenset(
    {"solidity", "blockage_factor", "wake_gi", "wake_gf"}
)
_PREPARED_KEYS = PARAMETER_KEYS | _DERIVED_PARAMETER_KEYS | {"law"}
_MAX_ABS_FLOW_RATIO = 1.0e6
_TRIM_BISECTION_STEPS = 80
_ZERO_VECTOR = (0.0, 0.0, 0.0)
_ZERO_LOADS = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0)


def _number(value: Any, name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, Real):
        raise ValueError(f"{name} must be a finite real number")
    result = float(value)
    if not isfinite(result):
        raise ValueError(f"{name} must be a finite real number")
    return result


def _vector(value: Any, name: str) -> tuple[float, float, float]:
    if isinstance(value, (str, bytes)) or not isinstance(value, Sequence):
        raise ValueError(f"{name} must contain exactly three finite numbers")
    if len(value) != 3:
        raise ValueError(f"{name} must contain exactly three finite numbers")
    values = tuple(
        _number(component, f"{name}[{index}]")
        for index, component in enumerate(value)
    )
    return values  # type: ignore[return-value]


def _finite_result(value: float, name: str) -> float:
    if not isfinite(value):
        raise ValueError(f"{name} is not finite")
    return value


def _cross(
    left: tuple[float, float, float], right: tuple[float, float, float]
) -> tuple[float, float, float]:
    return (
        left[1] * right[2] - left[2] * right[1],
        left[2] * right[0] - left[0] * right[2],
        left[0] * right[1] - left[1] * right[0],
    )


def _wake_factor(
    model: Mapping[str, Any],
    main_induced_velocity: float,
    air_velocity: tuple[float, float, float],
) -> float:
    """Apply the source's signed-forward-speed, piecewise-linear wake ramp."""
    forward_air, _, down_air = air_velocity
    denominator = main_induced_velocity - down_air
    if main_induced_velocity <= down_air or denominator <= 0.0:
        return 0.0

    # Since denominator is positive, compare dimensional quantities at the
    # two boundaries before dividing. This avoids overflow near V_i == w_a.
    lower_velocity = model["wake_gi"] * denominator
    upper_velocity = model["wake_gf"] * denominator
    if forward_air <= lower_velocity:
        return 0.0
    if forward_air >= upper_velocity:
        return 1.5

    ratio = forward_air / denominator
    fraction = (ratio - model["wake_gi"]) / (
        model["wake_gf"] - model["wake_gi"]
    )
    return _finite_result(1.5 * fraction, "wake_factor")


def _trim_lambda(model: Mapping[str, Any], advance_ratio: float) -> float:
    """Solve the monotone source trim-inflow residual on a proven bracket.

    For positive trim pitch, F(0)<0 and F(2*delta_trim*A)>0 because the
    blade-element linear term alone equals its forcing at that upper bound.
    Scale the upper bracket with both the linear and quadratic terms, then
    check the final relative residual. A fixed number of bisections on the
    geometry-only bracket cannot resolve very small positive lift slopes.
    """
    sigma = model["solidity"]
    lift = model["blade_lift_curve_slope_per_rad"]
    eta = model["wake_efficiency"]
    trim = model["trim_collective_rad"]
    a = 1.0 / 3.0 + advance_ratio * advance_ratio / 2.0
    target = (lift * sigma / 2.0) * trim * a
    linear = lift * sigma / 4.0

    def residual(value: float) -> float:
        return (
            2.0 * eta * value * hypot(advance_ratio, value)
            + linear * value
            - target
        )

    lo = 0.0
    _finite_result(target, "trim forcing")
    _finite_result(linear, "trim linear slope")
    if target <= 0.0 or linear <= 0.0:
        raise ValueError("trim forcing and linear slope must remain positive")
    hi = min(2.0 * trim * a, target / (linear + 2.0 * eta * advance_ratio),
             sqrt(target / (2.0 * eta)))
    for _ in range(_TRIM_BISECTION_STEPS):
        mid = (lo + hi) / 2.0
        if residual(mid) > 0.0:
            hi = mid
        else:
            lo = mid
    root = _finite_result((lo + hi) / 2.0, "trim_lambda")
    error = _finite_result(residual(root), "trim residual")
    if root <= 0.0 or abs(error) > 1.0e-12 * target:
        raise ValueError("trim root failed the relative residual gate")
    return root


def _trim_slopes(
    model: Mapping[str, Any], advance_ratio: float
) -> tuple[float, float, float, float]:
    """Return lambda_trim, CT_trim, dCT/ddelta, and dCT/dmu_z.

    These are implicit derivatives of the source Eqs. 4-5 at mu_z=0 and the
    configured trim collective. The tail-specific efficiency is not published
    in §4.6; `wake_efficiency` is an explicit inferred transfer parameter.
    """
    sigma = model["solidity"]
    lift = model["blade_lift_curve_slope_per_rad"]
    eta = model["wake_efficiency"]
    trim = model["trim_collective_rad"]
    a = 1.0 / 3.0 + advance_ratio * advance_ratio / 2.0
    lam = _trim_lambda(model, advance_ratio)
    speed = hypot(advance_ratio, lam)
    d = 2.0 * eta * (advance_ratio * advance_ratio + 2.0 * lam * lam) / speed
    e = -2.0 * eta * lam * lam / speed
    denominator = d + lift * sigma / 4.0
    if denominator <= 0.0:
        raise ValueError("trim derivative denominator must be positive")

    trim_ct = (lift * sigma / 2.0) * (trim * a - lam / 2.0)
    if trim_ct <= 0.0:
        raise ValueError("trim collective must produce positive unsaturated trim thrust")
    if trim_ct >= model["thrust_coefficient_max"]:
        raise ValueError("trim thrust coefficient reaches the cap; local slopes are undefined")

    slope_collective = (
        (lift * sigma / 2.0) * a * d / denominator
    )
    slope_normal = (lift * sigma / 4.0) * (d + e) / denominator
    for key, value in (
        ("trim_ct", trim_ct),
        ("thrust_collective_slope_per_rad", slope_collective),
        ("thrust_normal_flow_slope", slope_normal),
    ):
        _finite_result(value, key)
    return lam, trim_ct, slope_collective, slope_normal


def prepare(parameters: Mapping[str, Any]) -> Mapping[str, Any]:
    """Validate all 15 explicit parameters and return a flat read-only model.

    The mapping includes operating density and the inferred tail wake
    efficiency; it does not supply aircraft defaults.
    """
    if not isinstance(parameters, Mapping):
        raise ValueError("parameters must be a mapping")
    supplied = set(parameters)
    if supplied != PARAMETER_KEYS:
        missing = sorted(PARAMETER_KEYS - supplied)
        extra = sorted(supplied - PARAMETER_KEYS)
        details = []
        if missing:
            details.append("missing " + ", ".join(missing))
        if extra:
            details.append("unknown " + ", ".join(str(item) for item in extra))
        raise ValueError("invalid parameters: " + "; ".join(details))

    model: dict[str, Any] = {}
    for key in PARAMETER_KEYS - {"rotor_blade_count", "rotation_sense"}:
        model[key] = _number(parameters[key], key)

    raw_blade_count = _number(parameters["rotor_blade_count"], "rotor_blade_count")
    if raw_blade_count != 2.0:
        raise ValueError("rotor_blade_count must be 2 for the source two-blade tail rotor")
    model["rotor_blade_count"] = int(raw_blade_count)

    raw_sense = _number(parameters["rotation_sense"], "rotation_sense")
    if raw_sense not in (-1.0, 1.0):
        raise ValueError("rotation_sense must be exactly -1 or +1")
    model["rotation_sense"] = int(raw_sense)

    positive = (
        "rho_kg_m3",
        "main_rotor_radius_m",
        "tail_rotor_radius_m",
        "blade_chord_m",
        "blade_lift_curve_slope_per_rad",
        "thrust_coefficient_max",
        "tail_to_main_speed_ratio",
        "hub_distance_aft_m",
        "hub_height_above_cg_m",
        "trim_collective_rad",
        "wake_efficiency",
    )
    for key in positive:
        if model[key] <= 0.0:
            raise ValueError(f"{key} must be positive")
    if model["trim_collective_rad"] > pi / 2.0:
        raise ValueError("trim_collective_rad must not exceed pi/2")
    if model["wake_efficiency"] > 1.0:
        raise ValueError("wake_efficiency must be at most one")
    for key in ("blade_section_cd0", "vertical_fin_area_m2"):
        if model[key] < 0.0:
            raise ValueError(f"{key} must be nonnegative")

    tail_radius = model["tail_rotor_radius_m"]
    solidity = (
        model["rotor_blade_count"]
        * model["blade_chord_m"]
        / (pi * tail_radius)
    )
    if not 0.0 < solidity < 1.0:
        raise ValueError("tail rotor solidity must be in (0, 1)")
    blockage = 1.0 - 0.75 * model["vertical_fin_area_m2"] / (
        pi * tail_radius * tail_radius
    )
    if not 0.0 < blockage <= 1.0:
        raise ValueError("fin blockage factor must be in (0, 1]")
    gi = (
        model["hub_distance_aft_m"]
        - model["main_rotor_radius_m"]
        - tail_radius
    ) / model["hub_height_above_cg_m"]
    gf = (
        model["hub_distance_aft_m"]
        - model["main_rotor_radius_m"]
        + tail_radius
    ) / model["hub_height_above_cg_m"]
    for key, value in (
        ("solidity", solidity),
        ("blockage_factor", blockage),
        ("wake_gi", gi),
        ("wake_gf", gf),
    ):
        model[key] = _finite_result(value, key)
    if gf <= gi:
        raise ValueError("wake ramp requires wake_gf > wake_gi")
    model["law"] = LAW
    return MappingProxyType(model)


def _validated_model(model: Mapping[str, Any]) -> Mapping[str, Any]:
    if not isinstance(model, Mapping) or set(model) != _PREPARED_KEYS:
        raise ValueError("model must be the complete flat mapping returned by prepare")
    fresh = prepare({key: model[key] for key in PARAMETER_KEYS})
    if model["law"] != LAW:
        raise ValueError("model law identifier is invalid")
    for key in _DERIVED_PARAMETER_KEYS:
        if _number(model[key], key) != fresh[key]:
            raise ValueError(f"model derived field {key} does not match its parameters")
    return fresh


def evaluate(model: Mapping[str, Any], inputs: Mapping[str, Any]) -> dict[str, Any]:
    """Evaluate the source local tail law for one stage and return diagnostics."""
    prepared = _validated_model(model)
    if not isinstance(inputs, Mapping) or set(inputs) != INPUT_KEYS:
        raise ValueError("inputs must contain exactly the documented tail state keys")

    omega_main = _number(inputs["omega_main_rad_s"], "omega_main_rad_s")
    main_vi = _number(inputs["main_induced_velocity_m_s"], "main_induced_velocity_m_s")
    air_velocity = _vector(
        inputs["cg_air_velocity_body_frd_m_s"], "cg_air_velocity_body_frd_m_s"
    )
    body_rates = _vector(
        inputs["body_rates_body_frd_rad_s"], "body_rates_body_frd_rad_s"
    )
    collective = _number(inputs["tail_collective_rad"], "tail_collective_rad")
    if omega_main < 0.0:
        raise ValueError("omega_main_rad_s must be nonnegative; use rotation_sense for shaft direction")

    u_air, v_air, w_air = air_velocity
    p, q, r = body_rates
    ltr = prepared["hub_distance_aft_m"]
    htr = prepared["hub_height_above_cg_m"]
    wake = _wake_factor(prepared, main_vi, air_velocity)
    w_tail = w_air + ltr * q - wake * main_vi
    in_plane = hypot(u_air, w_tail)
    normal = v_air - ltr * r + htr * p
    for key, value in (
        ("wake_factor", wake),
        ("in_plane_velocity_m_s", in_plane),
        ("normal_velocity_m_s", normal),
    ):
        _finite_result(value, key)

    speed_ratio = prepared["tail_to_main_speed_ratio"]
    tail_speed_magnitude = speed_ratio * omega_main
    # The native/public omega diagnostic is a speed magnitude. Signed shaft
    # direction is represented separately by rotation_sense on reaction My.
    tail_omega = tail_speed_magnitude
    tip_speed = tail_speed_magnitude * prepared["tail_rotor_radius_m"]
    _finite_result(tail_omega, "tail_omega_rad_s")
    _finite_result(tip_speed, "tip_speed_m_s")

    if omega_main == 0.0:
        force = _ZERO_VECTOR
        moment = _ZERO_VECTOR
        return {
            "tail_omega_rad_s": 0.0,
            "tip_speed_m_s": 0.0,
            "wake_factor": wake,
            "in_plane_velocity_m_s": in_plane,
            "normal_velocity_m_s": normal,
            "advance_ratio": None,
            "normal_flow_ratio": None,
            "trim_lambda": None,
            "trim_ct": None,
            "thrust_collective_slope_per_rad": None,
            "thrust_normal_flow_slope": None,
            "thrust_coefficient_ideal": None,
            "thrust_coefficient": None,
            "torque_coefficient": None,
            "induced_velocity_m_s": 0.0,
            "thrust_n": 0.0,
            "torque_nm": 0.0,
            "blockage_factor": prepared["blockage_factor"],
            "force_body_frd_n": force,
            "moment_body_frd_nm": moment,
            "loads": _ZERO_LOADS,
            "rotor_active": False,
            "thrust_limited": False,
        }
    if tip_speed <= 0.0:
        raise ValueError("tail tip speed must remain positive for active rotor")

    advance_ratio = in_plane / tip_speed
    normal_flow_ratio = normal / tip_speed
    if abs(advance_ratio) > _MAX_ABS_FLOW_RATIO:
        raise ValueError("tail advance ratio exceeds the numerical guard")
    if abs(normal_flow_ratio) > _MAX_ABS_FLOW_RATIO:
        raise ValueError("tail normal flow ratio exceeds the numerical guard")
    if abs(collective) > pi / 2.0:
        raise ValueError("tail_collective_rad must be within [-pi/2, +pi/2]")

    trim_lambda, trim_ct, slope_collective, slope_normal = _trim_slopes(
        prepared, advance_ratio
    )
    a = 1.0 / 3.0 + advance_ratio * advance_ratio / 2.0
    ct_ideal = slope_collective * collective + slope_normal * normal_flow_ratio
    ct = max(
        -prepared["thrust_coefficient_max"],
        min(prepared["thrust_coefficient_max"], ct_ideal),
    )
    thrust_limited = abs(ct_ideal) > prepared["thrust_coefficient_max"]

    # Eq. 50 uses the capped aerodynamic CT, normalized before the geometric
    # blockage factor, and the actual collective pitch (including trim).
    lam = normal_flow_ratio - 2.0 * (
        2.0 * ct / (prepared["blade_lift_curve_slope_per_rad"] * prepared["solidity"])
        - collective * a
    )
    induced_velocity = lam * tip_speed
    area = pi * prepared["tail_rotor_radius_m"] ** 2
    dynamic_scale = prepared["rho_kg_m3"] * tip_speed * tip_speed * area
    thrust = (
        ct
        * prepared["blockage_factor"]
        * dynamic_scale
    )
    cq = ct * (lam - normal_flow_ratio) + (
        prepared["blade_section_cd0"] * prepared["solidity"] / 8.0
    ) * (1.0 + (7.0 / 3.0) * advance_ratio * advance_ratio)
    torque = cq * dynamic_scale * prepared["tail_rotor_radius_m"]

    force = (0.0, -thrust, 0.0)
    hub_arm = (-ltr, 0.0, -htr)
    hub_moment = _cross(hub_arm, force)
    reaction_moment = (0.0, -prepared["rotation_sense"] * torque, 0.0)
    moment = tuple(
        hub_moment[index] + reaction_moment[index] for index in range(3)
    )
    loads = force + moment

    output = {
        "tail_omega_rad_s": tail_omega,
        "tip_speed_m_s": tip_speed,
        "wake_factor": wake,
        "in_plane_velocity_m_s": in_plane,
        "normal_velocity_m_s": normal,
        "advance_ratio": advance_ratio,
        "normal_flow_ratio": normal_flow_ratio,
        "trim_lambda": trim_lambda,
        "trim_ct": trim_ct,
        "thrust_collective_slope_per_rad": slope_collective,
        "thrust_normal_flow_slope": slope_normal,
        "thrust_coefficient_ideal": ct_ideal,
        "thrust_coefficient": ct,
        "torque_coefficient": cq,
        "induced_velocity_m_s": induced_velocity,
        "thrust_n": thrust,
        "torque_nm": torque,
        "blockage_factor": prepared["blockage_factor"],
        "force_body_frd_n": force,
        "moment_body_frd_nm": moment,
        "loads": loads,
        "rotor_active": True,
        "thrust_limited": thrust_limited,
    }
    for key, value in output.items():
        if isinstance(value, float):
            _finite_result(value, key)
        elif isinstance(value, tuple):
            for index, component in enumerate(value):
                _finite_result(component, f"{key}[{index}]")
    return output

