"""Standalone, source-faithful X-Cell main-rotor load reference.

This is a pure numerical kernel for an azimuth-averaged, no-twist rotor. It
implements the Gavrilets–Mettler–Feron thrust, profile/power torque and
first-order lumped flapping equations, with an explicitly chosen geometric
thrust-normal extension for finite tip-path-plane angles. It is a research
reference, not a qualified helicopter model.

All body vectors use FRD: +x forward, +y right, +z down. Positive thrust acts
along the upward rotor normal. Positive a1 is aft and positive b1 is right.
The caller supplies induced velocity as a dimensional value by default; the
alternate `lambda0` input path is explicit and never inferred.
"""

from __future__ import annotations

from math import cos, hypot, isfinite, pi, sin, sqrt
from numbers import Real
from types import MappingProxyType
from typing import Any, Mapping, Sequence


PARAMETER_KEYS = frozenset(
    {
        "rho_kg_m3",
        "rotor_radius_m",
        "blade_chord_m",
        "rotor_blade_count",
        "blade_lift_curve_slope_per_rad",
        "blade_section_cd0",
        "thrust_coefficient_max",
        "blade_flapping_inertia_kg_m2",
        "gamma_flybar",
        "flapback_k_mu",
        "omega_nominal_rad_s",
        "cyclic_longitudinal_gain_nominal_rad_per_rad",
        "cyclic_lateral_gain_nominal_rad_per_rad",
        "hub_spring_stiffness_nm_per_rad",
        "hub_position_body_frd_m",
        "rotation_sense",
    }
)

_COMMON_INPUT_KEYS = frozenset(
    {
        "omega_rad_s",
        "hub_velocity_relative_to_air_body_frd_m_s",
        "body_rates_body_frd_rad_s",
        "collective_pitch_75_rad",
        "cyclic_forward_rad",
        "cyclic_right_rad",
        "a1_rad",
        "b1_rad",
    }
)
_VI_INPUT_KEYS = _COMMON_INPUT_KEYS | {"induced_velocity_m_s"}
_LAMBDA_INPUT_KEYS = _COMMON_INPUT_KEYS | {"lambda0"}
_DERIVED_PARAMETER_KEYS = frozenset(
    {"solidity", "lock_number", "bare_flap_time_constant_nominal_s"}
)
_PREPARED_KEYS = PARAMETER_KEYS | _DERIVED_PARAMETER_KEYS
_SMALL_FLAP_LIMIT_RAD = 10.0 * pi / 180.0
_IDENTIFIED_MU_LIMIT = 0.15
_INPUT_ANGLE_LIMIT_RAD = pi / 2.0


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


def prepare(parameters: Mapping[str, Any]) -> Mapping[str, Any]:
    """Validate the complete parameter profile and return a flat read-only model.

    No parameter has a default. Density is an explicit operating-context
    parameter; it is not an authored-aircraft default.
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
    for key in PARAMETER_KEYS - {"hub_position_body_frd_m", "rotor_blade_count", "rotation_sense"}:
        model[key] = _number(parameters[key], key)
    model["hub_position_body_frd_m"] = _vector(
        parameters["hub_position_body_frd_m"], "hub_position_body_frd_m"
    )

    raw_blade_count = parameters["rotor_blade_count"]
    blade_count = _number(raw_blade_count, "rotor_blade_count")
    if blade_count <= 0.0 or not blade_count.is_integer():
        raise ValueError("rotor_blade_count must be a positive integer")
    model["rotor_blade_count"] = int(blade_count)

    raw_sense = _number(parameters["rotation_sense"], "rotation_sense")
    if raw_sense not in (-1.0, 1.0):
        raise ValueError("rotation_sense must be exactly -1 or +1")
    model["rotation_sense"] = int(raw_sense)

    positive = (
        "rho_kg_m3",
        "rotor_radius_m",
        "blade_chord_m",
        "blade_lift_curve_slope_per_rad",
        "thrust_coefficient_max",
        "blade_flapping_inertia_kg_m2",
        "gamma_flybar",
        "omega_nominal_rad_s",
    )
    for key in positive:
        if model[key] <= 0.0:
            raise ValueError(f"{key} must be positive")
    nonnegative = (
        "blade_section_cd0",
        "flapback_k_mu",
        "cyclic_longitudinal_gain_nominal_rad_per_rad",
        "cyclic_lateral_gain_nominal_rad_per_rad",
        "hub_spring_stiffness_nm_per_rad",
    )
    for key in nonnegative:
        if model[key] < 0.0:
            raise ValueError(f"{key} must be nonnegative")

    radius = model["rotor_radius_m"]
    chord = model["blade_chord_m"]
    solidity = model["rotor_blade_count"] * chord / (pi * radius)
    lock_number = (
        model["rho_kg_m3"]
        * chord
        * model["blade_lift_curve_slope_per_rad"]
        * radius**4
        / model["blade_flapping_inertia_kg_m2"]
    )
    bare_tau = 16.0 / (lock_number * model["omega_nominal_rad_s"])
    model["solidity"] = _finite_result(solidity, "solidity")
    model["lock_number"] = _finite_result(lock_number, "lock_number")
    model["bare_flap_time_constant_nominal_s"] = _finite_result(
        bare_tau, "bare_flap_time_constant_nominal_s"
    )
    return MappingProxyType(model)


def _validated_model(model: Mapping[str, Any]) -> Mapping[str, Any]:
    if not isinstance(model, Mapping) or set(model) != _PREPARED_KEYS:
        raise ValueError("model must be the complete flat mapping returned by prepare")
    raw_parameters = {key: model[key] for key in PARAMETER_KEYS}
    fresh = prepare(raw_parameters)
    for key in _DERIVED_PARAMETER_KEYS:
        if _number(model[key], key) != fresh[key]:
            raise ValueError(f"model derived field {key} does not match its parameters")
    return fresh


def _evaluate_resolved_inflow(
    model: Mapping[str, Any], inputs: Mapping[str, Any], inflow_kind: str, inflow_value: Any
) -> dict[str, Any]:
    omega = _number(inputs["omega_rad_s"], "omega_rad_s")
    if omega < 0.0:
        raise ValueError("omega_rad_s must be nonnegative; rotation sense is a parameter")
    vi_or_ratio = _number(inflow_value, inflow_kind)
    hub_velocity = _vector(
        inputs["hub_velocity_relative_to_air_body_frd_m_s"],
        "hub_velocity_relative_to_air_body_frd_m_s",
    )
    body_rates = _vector(inputs["body_rates_body_frd_rad_s"], "body_rates_body_frd_rad_s")
    theta0 = _number(inputs["collective_pitch_75_rad"], "collective_pitch_75_rad")
    cyclic_forward = _number(inputs["cyclic_forward_rad"], "cyclic_forward_rad")
    cyclic_right = _number(inputs["cyclic_right_rad"], "cyclic_right_rad")
    a1 = _number(inputs["a1_rad"], "a1_rad")
    b1 = _number(inputs["b1_rad"], "b1_rad")
    for name, angle in (
        ("collective_pitch_75_rad", theta0),
        ("cyclic_forward_rad", cyclic_forward),
        ("cyclic_right_rad", cyclic_right),
        ("a1_rad", a1),
        ("b1_rad", b1),
    ):
        if abs(angle) > _INPUT_ANGLE_LIMIT_RAD:
            raise ValueError(f"{name} must be within [-pi/2, +pi/2]")

    # Stopped-disk closure: this reference omits parked-blade mechanics. In
    # particular, do not convert lambda to vi (or vi to lambda) at Omega=0.
    if omega == 0.0:
        zeros = (0.0, 0.0, 0.0)
        return {
            "rotor_active": False,
            "theta0_rad": theta0,
            "solidity": model["solidity"],
            "lambda0": None,
            "induced_velocity_m_s": None,
            "inflow_input_kind": inflow_kind,
            "inflow_input_value": vi_or_ratio,
            "mu_x": None,
            "mu_y": None,
            "mu_z": None,
            "mu": None,
            "within_identified_advance_ratio": False,
            "within_small_flap_angle_range": abs(a1) < _SMALL_FLAP_LIMIT_RAD
            and abs(b1) < _SMALL_FLAP_LIMIT_RAD,
            "lock_number": model["lock_number"],
            "bare_flap_time_constant_nominal_s": model[
                "bare_flap_time_constant_nominal_s"
            ],
            "thrust_coefficient_ideal": None,
            "thrust_coefficient": None,
            "thrust_n": 0.0,
            "torque_coefficient": None,
            "torque_nm": 0.0,
            "thrust_normal_body_frd": zeros,
            "force_body_frd_n": zeros,
            "hub_arm_moment_body_frd_nm": zeros,
            "flap_spring_moment_body_frd_nm": zeros,
            "reaction_torque_moment_body_frd_nm": zeros,
            "moment_body_frd_nm": zeros,
            "effective_flap_time_constant_s": None,
            "flap_rate_a1_rad_s": 0.0,
            "flap_rate_b1_rad_s": 0.0,
        }

    radius = model["rotor_radius_m"]
    omega_radius = _finite_result(omega * radius, "omega_rad_s * rotor_radius_m")
    if omega_radius <= 0.0:
        raise ValueError("omega_rad_s * rotor_radius_m must remain positive")
    if inflow_kind == "induced_velocity_m_s":
        vi = vi_or_ratio
        lambda0 = vi / omega_radius
    else:
        lambda0 = vi_or_ratio
        vi = lambda0 * omega_radius

    mu_x = hub_velocity[0] / omega_radius
    mu_y = hub_velocity[1] / omega_radius
    mu_z = hub_velocity[2] / omega_radius
    mu = hypot(mu_x, mu_y)
    for key, value in (
        ("lambda0", lambda0),
        ("induced_velocity_m_s", vi),
        ("mu_x", mu_x),
        ("mu_y", mu_y),
        ("mu_z", mu_z),
        ("mu", mu),
    ):
        _finite_result(value, key)

    # Eq. 27 has a singularity at mu=sqrt(2). Values beyond it are outside
    # the real-valued algebraic domain; values above 0.15 but below sqrt(2)
    # remain algebraic extensions and are flagged outside the paper's range.
    denominator_factor = 1.0 - mu * mu / 2.0
    if denominator_factor <= 0.0:
        raise ValueError("advance_ratio_mu is outside the Eq. 27 algebraic domain")

    sigma = model["solidity"]
    lift_slope = model["blade_lift_curve_slope_per_rad"]
    ct_ideal = (lift_slope * sigma / 2.0) * (
        theta0 * (1.0 / 3.0 + mu * mu / 2.0) + (mu_z - lambda0) / 2.0
    )
    ct = max(-model["thrust_coefficient_max"], min(model["thrust_coefficient_max"], ct_ideal))

    rotor_speed_sq = omega_radius * omega_radius
    disk_area = pi * radius * radius
    thrust = ct * model["rho_kg_m3"] * rotor_speed_sq * disk_area
    cq = ct * (lambda0 - mu_z) + (model["blade_section_cd0"] * sigma / 8.0) * (
        1.0 + (7.0 / 3.0) * mu * mu
    )
    torque = cq * model["rho_kg_m3"] * rotor_speed_sq * disk_area * radius

    # The paper's equations are linear in small a1/b1. This normalized exact
    # normal is the root-selected geometric extension for the resultant force.
    normal_raw = (-sin(a1), sin(b1), -cos(a1) * cos(b1))
    normal_length = sqrt(sum(component * component for component in normal_raw))
    normal = tuple(component / normal_length for component in normal_raw)
    force = tuple(thrust * component for component in normal)
    hub_arm_moment = _cross(model["hub_position_body_frd_m"], force)
    spring_moment = (
        model["hub_spring_stiffness_nm_per_rad"] * b1,
        model["hub_spring_stiffness_nm_per_rad"] * a1,
        0.0,
    )
    reaction_moment = (0.0, 0.0, -model["rotation_sense"] * torque)
    moment = tuple(
        hub_arm_moment[index] + spring_moment[index] + reaction_moment[index]
        for index in range(3)
    )

    # Source Eqs. 17–18. Eq. 26 gives db1/dmuv=-da1/dmux, so the
    # substituted lateral-flow term in dot(b1) has a plus sign. Eq. 27 uses
    # total in-plane mu; sign(u) is an explicit backward-flow interpretation.
    d_a1_d_mu_x = 2.0 * model["flapback_k_mu"] * (4.0 * theta0 / 3.0 - lambda0)
    sign_u = 1.0 if hub_velocity[0] > 0.0 else (-1.0 if hub_velocity[0] < 0.0 else 0.0)
    d_a1_d_mu_z = (
        model["flapback_k_mu"]
        * 16.0
        * mu
        * mu
        / (denominator_factor * (8.0 * mu + lift_slope * sigma))
        * sign_u
    )
    tau = 16.0 / (model["gamma_flybar"] * omega)
    gain_scale = (omega / model["omega_nominal_rad_s"]) ** 2
    gain_lon = model["cyclic_longitudinal_gain_nominal_rad_per_rad"] * gain_scale
    gain_lat = model["cyclic_lateral_gain_nominal_rad_per_rad"] * gain_scale
    # API forward cyclic positive is mapped to negative paper longitude input;
    # right cyclic positive maps directly to positive b1.
    delta_lon_paper = -cyclic_forward
    flap_rate_a1 = (
        -body_rates[1]
        + (
            -a1
            + d_a1_d_mu_x * mu_x
            + d_a1_d_mu_z * mu_z
            + gain_lon * delta_lon_paper
        ) / tau
    )
    flap_rate_b1 = (
        -body_rates[0]
        + (
            -b1
            + d_a1_d_mu_x * mu_y
            + gain_lat * cyclic_right
        ) / tau
    )

    scalar_results = {
        "lambda0": lambda0,
        "induced_velocity_m_s": vi,
        "mu_x": mu_x,
        "mu_y": mu_y,
        "mu_z": mu_z,
        "mu": mu,
        "thrust_coefficient_ideal": ct_ideal,
        "thrust_coefficient": ct,
        "thrust_n": thrust,
        "torque_coefficient": cq,
        "torque_nm": torque,
        "effective_flap_time_constant_s": tau,
        "flap_rate_a1_rad_s": flap_rate_a1,
        "flap_rate_b1_rad_s": flap_rate_b1,
    }
    for key, value in scalar_results.items():
        _finite_result(value, key)
    for name, vector in (
        ("thrust_normal_body_frd", normal),
        ("force_body_frd_n", force),
        ("hub_arm_moment_body_frd_nm", hub_arm_moment),
        ("flap_spring_moment_body_frd_nm", spring_moment),
        ("reaction_torque_moment_body_frd_nm", reaction_moment),
        ("moment_body_frd_nm", moment),
    ):
        for index, value in enumerate(vector):
            _finite_result(value, f"{name}[{index}]")

    return {
        "rotor_active": True,
        "theta0_rad": theta0,
        "solidity": sigma,
        "lambda0": lambda0,
        "induced_velocity_m_s": vi,
        "inflow_input_kind": inflow_kind,
        "inflow_input_value": vi_or_ratio,
        "mu_x": mu_x,
        "mu_y": mu_y,
        "mu_z": mu_z,
        "mu": mu,
        "within_identified_advance_ratio": mu < _IDENTIFIED_MU_LIMIT,
        "within_small_flap_angle_range": abs(a1) < _SMALL_FLAP_LIMIT_RAD
        and abs(b1) < _SMALL_FLAP_LIMIT_RAD,
        "lock_number": model["lock_number"],
        "bare_flap_time_constant_nominal_s": model[
            "bare_flap_time_constant_nominal_s"
        ],
        "thrust_coefficient_ideal": ct_ideal,
        "thrust_coefficient": ct,
        "thrust_n": thrust,
        "torque_coefficient": cq,
        "torque_nm": torque,
        "thrust_normal_body_frd": normal,
        "force_body_frd_n": force,
        "hub_arm_moment_body_frd_nm": hub_arm_moment,
        "flap_spring_moment_body_frd_nm": spring_moment,
        "reaction_torque_moment_body_frd_nm": reaction_moment,
        "moment_body_frd_nm": moment,
        "effective_flap_time_constant_s": tau,
        "flap_rate_a1_rad_s": flap_rate_a1,
        "flap_rate_b1_rad_s": flap_rate_b1,
    }


def evaluate(model: Mapping[str, Any], inputs: Mapping[str, Any]) -> dict[str, Any]:
    """Evaluate loads and first-order flap rates from a named input mapping.

    Inputs must contain exactly the common fields plus either
    `induced_velocity_m_s` or the explicitly nondimensional `lambda0`; the two
    forms cannot be mixed. At a stopped rotor, no conversion between them is
    attempted.
    """
    prepared = _validated_model(model)
    if not isinstance(inputs, Mapping):
        raise ValueError("inputs must be a mapping")
    keys = set(inputs)
    if keys == _VI_INPUT_KEYS:
        kind, value = "induced_velocity_m_s", inputs["induced_velocity_m_s"]
    elif keys == _LAMBDA_INPUT_KEYS:
        kind, value = "lambda0", inputs["lambda0"]
    else:
        missing_common = sorted(_COMMON_INPUT_KEYS - keys)
        allowed = _COMMON_INPUT_KEYS | {"induced_velocity_m_s", "lambda0"}
        extra = sorted(keys - allowed)
        details = []
        if missing_common:
            details.append("missing " + ", ".join(missing_common))
        if extra:
            details.append("unknown " + ", ".join(str(item) for item in extra))
        if "induced_velocity_m_s" in keys and "lambda0" in keys:
            details.append("provide exactly one of induced_velocity_m_s or lambda0")
        elif "induced_velocity_m_s" not in keys and "lambda0" not in keys:
            details.append("provide exactly one of induced_velocity_m_s or lambda0")
        raise ValueError("invalid inputs: " + "; ".join(details))
    return _evaluate_resolved_inflow(prepared, inputs, kind, value)

