"""Passive, local-flow airframe reference for a rotorcraft.

This standalone kernel evaluates a diagonal fuselage drag area, a vertical-fin
side force, and a horizontal-tail vertical force. It deliberately does not
close rotor wakes or supply aircraft defaults. Each component receives an
explicit local air-velocity increment from its caller. The passive force laws
in this module are a documented extension of Gavrilets et al., not a literal
transcription of every sign in §§4.3–4.5.

All body vectors use FRD: +x forward, +y right, +z down. Components are located
relative to the center of gravity. Point velocity includes the full
body-rate cross product, and each component moment is r × F.
"""

from __future__ import annotations

from math import copysign, fsum, hypot, isfinite
from numbers import Real
from types import MappingProxyType
from typing import Any, Mapping, Sequence


LAW = "openrc-passive-rotorcraft-airframe-v1"

PARAMETER_KEYS = frozenset(
    {
        "rho_kg_m3",
        "fuselage_drag_area_body_m2",
        "fuselage_cp_body_frd_m",
        "vertical_fin_area_m2",
        "vertical_fin_lift_curve_slope_per_rad",
        "vertical_fin_cp_body_frd_m",
        "horizontal_tail_area_m2",
        "horizontal_tail_lift_curve_slope_per_rad",
        "horizontal_tail_cp_body_frd_m",
    }
)

INPUT_KEYS = frozenset(
    {
        "cg_air_velocity_body_frd_m_s",
        "body_rates_body_frd_rad_s",
        "fuselage_wake_velocity_body_frd_m_s",
        "vertical_fin_wake_velocity_body_frd_m_s",
        "horizontal_tail_wake_velocity_body_frd_m_s",
    }
)

_PREPARED_KEYS = PARAMETER_KEYS | {"law"}
_ZERO_VECTOR = (0.0, 0.0, 0.0)


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
    return tuple(
        _number(component, f"{name}[{index}]") for index, component in enumerate(value)
    )  # type: ignore[return-value]


def _finite_result(value: float, name: str) -> float:
    if not isfinite(value):
        raise ValueError(f"{name} is not finite")
    return value


def _checked_vector(
    value: tuple[float, float, float], name: str
) -> tuple[float, float, float]:
    return tuple(
        _finite_result(component, f"{name}[{index}]")
        for index, component in enumerate(value)
    )  # type: ignore[return-value]


def _add(
    left: tuple[float, float, float], right: tuple[float, float, float]
) -> tuple[float, float, float]:
    return tuple(left[index] + right[index] for index in range(3))  # type: ignore[return-value]


def _subtract(
    left: tuple[float, float, float], right: tuple[float, float, float]
) -> tuple[float, float, float]:
    return tuple(left[index] - right[index] for index in range(3))  # type: ignore[return-value]


def _scale(
    vector: tuple[float, float, float], scalar: float
) -> tuple[float, float, float]:
    return tuple(component * scalar for component in vector)  # type: ignore[return-value]


def _cross(
    left: tuple[float, float, float], right: tuple[float, float, float]
) -> tuple[float, float, float]:
    return (
        left[1] * right[2] - left[2] * right[1],
        left[2] * right[0] - left[0] * right[2],
        left[0] * right[1] - left[1] * right[0],
    )


def _dot(
    left: tuple[float, float, float], right: tuple[float, float, float]
) -> float:
    return fsum(left[index] * right[index] for index in range(3))


def prepare(parameters: Mapping[str, Any]) -> Mapping[str, Any]:
    """Validate the complete parameter mapping and freeze a flat model.

    Density, geometry, projected areas, and lift slopes are all explicit.
    No aircraft-specific parameter or geometry defaults are supplied.
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

    model: dict[str, Any] = {
        "rho_kg_m3": _number(parameters["rho_kg_m3"], "rho_kg_m3"),
        "fuselage_drag_area_body_m2": _vector(
            parameters["fuselage_drag_area_body_m2"],
            "fuselage_drag_area_body_m2",
        ),
        "fuselage_cp_body_frd_m": _vector(
            parameters["fuselage_cp_body_frd_m"], "fuselage_cp_body_frd_m"
        ),
        "vertical_fin_area_m2": _number(
            parameters["vertical_fin_area_m2"], "vertical_fin_area_m2"
        ),
        "vertical_fin_lift_curve_slope_per_rad": _number(
            parameters["vertical_fin_lift_curve_slope_per_rad"],
            "vertical_fin_lift_curve_slope_per_rad",
        ),
        "vertical_fin_cp_body_frd_m": _vector(
            parameters["vertical_fin_cp_body_frd_m"], "vertical_fin_cp_body_frd_m"
        ),
        "horizontal_tail_area_m2": _number(
            parameters["horizontal_tail_area_m2"], "horizontal_tail_area_m2"
        ),
        "horizontal_tail_lift_curve_slope_per_rad": _number(
            parameters["horizontal_tail_lift_curve_slope_per_rad"],
            "horizontal_tail_lift_curve_slope_per_rad",
        ),
        "horizontal_tail_cp_body_frd_m": _vector(
            parameters["horizontal_tail_cp_body_frd_m"],
            "horizontal_tail_cp_body_frd_m",
        ),
    }

    if model["rho_kg_m3"] <= 0.0:
        raise ValueError("rho_kg_m3 must be positive")
    if any(area < 0.0 for area in model["fuselage_drag_area_body_m2"]):
        raise ValueError("fuselage drag areas must be nonnegative")
    for key in (
        "vertical_fin_area_m2",
        "vertical_fin_lift_curve_slope_per_rad",
        "horizontal_tail_area_m2",
        "horizontal_tail_lift_curve_slope_per_rad",
    ):
        if model[key] < 0.0:
            raise ValueError(f"{key} must be nonnegative")

    model["law"] = LAW
    return MappingProxyType(model)


def _validated_model(model: Mapping[str, Any]) -> Mapping[str, Any]:
    if not isinstance(model, MappingProxyType) or set(model) != _PREPARED_KEYS:
        raise ValueError("model must be the complete read-only mapping returned by prepare")
    fresh = prepare({key: model[key] for key in PARAMETER_KEYS})
    if model["law"] != LAW:
        raise ValueError("model law identifier is invalid")
    return fresh


def _cap_signed_force(ideal: float, cap: float, name: str) -> tuple[float, bool]:
    _finite_result(ideal, f"{name} ideal force")
    _finite_result(cap, f"{name} force cap")
    return copysign(min(abs(ideal), cap), ideal), abs(ideal) > cap


def _surface_force(
    *,
    kind: str,
    rho: float,
    area: float,
    lift_slope: float,
    relative_air: tuple[float, float, float],
) -> tuple[tuple[float, float, float], float, float, bool]:
    """Return force, source-shaped ideal scalar, actual scalar, and cap flag."""
    ux, uy, uz = relative_air
    dynamic_factor = 0.5 * rho * area

    if kind == "vertical_fin":
        inplane_speed = hypot(ux, uz)
        speed_squared = _finite_result(
            _dot(relative_air, relative_air), f"{kind} speed squared"
        )
        ideal = -dynamic_factor * (
            lift_slope * inplane_speed + abs(uy)
        ) * uy
        cap = dynamic_factor * speed_squared
        actual, limited = _cap_signed_force(ideal, cap, kind)
        return (0.0, actual, 0.0), ideal, actual, limited

    if kind == "horizontal_tail":
        ideal = -dynamic_factor * (
            lift_slope * abs(ux) + abs(uz)
        ) * uz
        cap = dynamic_factor * _finite_result(ux * ux + uz * uz, f"{kind} cap speed squared")
        actual, limited = _cap_signed_force(ideal, cap, kind)
        return (0.0, 0.0, actual), ideal, actual, limited

    raise ValueError(f"unsupported surface kind: {kind}")


def _component_result(
    *,
    prefix: str,
    force: tuple[float, float, float],
    arm: tuple[float, float, float],
    point_velocity: tuple[float, float, float],
    relative_air: tuple[float, float, float],
    wake_velocity: tuple[float, float, float],
) -> dict[str, Any]:
    force = _checked_vector(force, f"{prefix} force")
    moment = _checked_vector(_cross(arm, force), f"{prefix} moment")
    loads = force + moment
    relative_power = _finite_result(_dot(force, relative_air), f"{prefix} relative power")
    body_air_power = _finite_result(_dot(force, point_velocity), f"{prefix} body-air power")
    wake_power = _finite_result(_dot(force, wake_velocity), f"{prefix} wake power")
    return {
        f"{prefix}_relative_air_m_s": relative_air,
        f"{prefix}_force_body_frd_n": force,
        f"{prefix}_moment_body_frd_nm": moment,
        f"{prefix}_relative_power_w": relative_power,
        f"{prefix}_body_air_power_w": body_air_power,
        f"{prefix}_wake_power_w": wake_power,
        f"{prefix}_loads": loads,
    }


def evaluate(model: Mapping[str, Any], inputs: Mapping[str, Any]) -> dict[str, Any]:
    """Evaluate passive local airframe loads for one rigid-body state.

    Input wake vectors are air-velocity increments in body FRD. The local
    component velocity relative to that air is
    ``cg_air_velocity + body_rates × cp − wake_velocity``.
    """
    prepared = _validated_model(model)
    if not isinstance(inputs, Mapping) or set(inputs) != INPUT_KEYS:
        raise ValueError("inputs must contain exactly the documented airframe state keys")

    cg_air = _vector(
        inputs["cg_air_velocity_body_frd_m_s"], "cg_air_velocity_body_frd_m_s"
    )
    rates = _vector(
        inputs["body_rates_body_frd_rad_s"], "body_rates_body_frd_rad_s"
    )
    wakes = {
        "fuselage": _vector(
            inputs["fuselage_wake_velocity_body_frd_m_s"],
            "fuselage_wake_velocity_body_frd_m_s",
        ),
        "vertical_fin": _vector(
            inputs["vertical_fin_wake_velocity_body_frd_m_s"],
            "vertical_fin_wake_velocity_body_frd_m_s",
        ),
        "horizontal_tail": _vector(
            inputs["horizontal_tail_wake_velocity_body_frd_m_s"],
            "horizontal_tail_wake_velocity_body_frd_m_s",
        ),
    }

    arms = {
        "fuselage": prepared["fuselage_cp_body_frd_m"],
        "vertical_fin": prepared["vertical_fin_cp_body_frd_m"],
        "horizontal_tail": prepared["horizontal_tail_cp_body_frd_m"],
    }
    results: dict[str, dict[str, Any]] = {}
    for prefix in ("fuselage", "vertical_fin", "horizontal_tail"):
        point_velocity = _checked_vector(
            _add(cg_air, _cross(rates, arms[prefix])),
            f"{prefix} point velocity",
        )
        relative_air = _checked_vector(
            _subtract(point_velocity, wakes[prefix]),
            f"{prefix} relative air velocity",
        )
        if prefix == "fuselage":
            speed = _finite_result(hypot(*relative_air), "fuselage relative speed")
            force = tuple(
                -0.5
                * prepared["rho_kg_m3"]
                * prepared["fuselage_drag_area_body_m2"][axis]
                * relative_air[axis]
                * speed
                for axis in range(3)
            )
            results[prefix] = _component_result(
                prefix=prefix,
                force=force,  # type: ignore[arg-type]
                arm=arms[prefix],
                point_velocity=point_velocity,
                relative_air=relative_air,
                wake_velocity=wakes[prefix],
            )
        elif prefix == "vertical_fin":
            force, ideal, actual, limited = _surface_force(
                kind=prefix,
                rho=prepared["rho_kg_m3"],
                area=prepared["vertical_fin_area_m2"],
                lift_slope=prepared["vertical_fin_lift_curve_slope_per_rad"],
                relative_air=relative_air,
            )
            results[prefix] = _component_result(
                prefix=prefix,
                force=force,
                arm=arms[prefix],
                point_velocity=point_velocity,
                relative_air=relative_air,
                wake_velocity=wakes[prefix],
            )
            results[prefix]["vertical_fin_force_ideal_n"] = _finite_result(
                ideal, "vertical_fin_force_ideal_n"
            )
            results[prefix]["vertical_fin_force_n"] = _finite_result(
                actual, "vertical_fin_force_n"
            )
            results[prefix]["vertical_fin_limited"] = limited
        else:
            force, ideal, actual, limited = _surface_force(
                kind=prefix,
                rho=prepared["rho_kg_m3"],
                area=prepared["horizontal_tail_area_m2"],
                lift_slope=prepared["horizontal_tail_lift_curve_slope_per_rad"],
                relative_air=relative_air,
            )
            results[prefix] = _component_result(
                prefix=prefix,
                force=force,
                arm=arms[prefix],
                point_velocity=point_velocity,
                relative_air=relative_air,
                wake_velocity=wakes[prefix],
            )
            results[prefix]["horizontal_tail_force_ideal_n"] = _finite_result(
                ideal, "horizontal_tail_force_ideal_n"
            )
            results[prefix]["horizontal_tail_force_n"] = _finite_result(
                actual, "horizontal_tail_force_n"
            )
            results[prefix]["horizontal_tail_limited"] = limited

    output: dict[str, Any] = {}
    component_fields = (
        "relative_air_m_s",
        "force_body_frd_n",
        "moment_body_frd_nm",
        "relative_power_w",
        "body_air_power_w",
        "wake_power_w",
    )
    for prefix, values in results.items():
        for field in component_fields:
            output[f"{prefix}_{field}"] = values[f"{prefix}_{field}"]
        output[f"{prefix}_loads"] = values[f"{prefix}_loads"]
        for field in (
            "vertical_fin_force_ideal_n",
            "vertical_fin_force_n",
            "vertical_fin_limited",
            "horizontal_tail_force_ideal_n",
            "horizontal_tail_force_n",
            "horizontal_tail_limited",
        ):
            if field in values:
                output[field] = values[field]

    component_loads = [results[prefix][f"{prefix}_loads"] for prefix in results]
    loads = tuple(
        _finite_result(fsum(component[index] for component in component_loads), f"loads[{index}]")
        for index in range(6)
    )
    output["fuselage_loads"] = results["fuselage"]["fuselage_loads"]
    output["vertical_fin_loads"] = results["vertical_fin"]["vertical_fin_loads"]
    output["horizontal_tail_loads"] = results["horizontal_tail"]["horizontal_tail_loads"]
    output["loads"] = loads
    for field in ("relative_power_w", "body_air_power_w", "wake_power_w"):
        output[field] = _finite_result(
            fsum(results[prefix][f"{prefix}_{field}"] for prefix in results), field
        )
    return output
