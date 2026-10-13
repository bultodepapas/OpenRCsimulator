# HELI-05: two-blade, untwisted X-Cell rotor; Gavrilets et al. §4.1.
# Loads are FRD about the supplied CG-relative hub arm. State is float64.
extends RefCounted

const M = preload("res://physics/math3d.gd")
const LAW: String = "openrc-xcell-main-rotor-v1"
const PARAMETER_KEYS: Array = [
	"rho_kg_m3", "rotor_radius_m", "blade_chord_m", "rotor_blade_count",
	"blade_lift_curve_slope_per_rad", "blade_section_cd0", "thrust_coefficient_max",
	"blade_flapping_inertia_kg_m2", "gamma_flybar", "flapback_k_mu", "omega_nominal_rad_s",
	"cyclic_longitudinal_gain_nominal_rad_per_rad", "cyclic_lateral_gain_nominal_rad_per_rad",
	"hub_spring_stiffness_nm_per_rad", "hub_position_body_frd_m", "rotation_sense",
]


# Operating density is explicit in this standalone context. The future weather
# boundary must prepare a new context when density changes. No aircraft defaults.
static func prepare(parameters: Dictionary) -> Dictionary:
	if parameters.size() != PARAMETER_KEYS.size():
		return {"ok": false}
	for key: String in PARAMETER_KEYS:
		if not parameters.has(key):
			return {"ok": false}
	var model: Dictionary = {"law": LAW}
	for key: String in PARAMETER_KEYS:
		if key == "hub_position_body_frd_m":
			continue
		if not _number(parameters[key]):
			return {"ok": false}
		model[key] = float(parameters[key])
	for key: String in ["rho_kg_m3", "rotor_radius_m", "blade_chord_m", "blade_lift_curve_slope_per_rad",
		"thrust_coefficient_max", "blade_flapping_inertia_kg_m2", "gamma_flybar", "omega_nominal_rad_s"]:
		if model[key] <= 0.0:
			return {"ok": false}
	for key: String in ["blade_section_cd0", "flapback_k_mu", "cyclic_longitudinal_gain_nominal_rad_per_rad",
		"cyclic_lateral_gain_nominal_rad_per_rad", "hub_spring_stiffness_nm_per_rad"]:
		if model[key] < 0.0:
			return {"ok": false}
	if model.rotor_blade_count != 2.0 or absf(model.rotation_sense) != 1.0:
		return {"ok": false}
	var arm: Variant = parameters.hub_position_body_frd_m
	if typeof(arm) != TYPE_ARRAY and typeof(arm) != TYPE_PACKED_FLOAT64_ARRAY:
		return {"ok": false}
	if arm.size() != 3:
		return {"ok": false}
	for i: int in range(3):
		if not _number(arm[i]):
			return {"ok": false}
	model.hub_x_m = float(arm[0])
	model.hub_y_m = float(arm[1])
	model.hub_z_m = float(arm[2])
	var radius: float = model.rotor_radius_m
	model.solidity = model.rotor_blade_count * model.blade_chord_m / (PI * radius)
	model.lock_number = model.rho_kg_m3 * model.blade_chord_m * model.blade_lift_curve_slope_per_rad \
		* radius * radius * radius * radius / model.blade_flapping_inertia_kg_m2
	model.bare_flap_time_constant_nominal_s = 16.0 / (model.lock_number * model.omega_nominal_rad_s)
	if model.solidity <= 0.0 or model.solidity >= 1.0 or model.lock_number <= 0.0 \
		or model.bare_flap_time_constant_nominal_s <= 0.0:
		return {"ok": false}
	for value: Variant in model.values():
		if typeof(value) != TYPE_STRING and not is_finite(value):
			return {"ok": false}
	model.make_read_only() # Flat scalar context: no nested mutable configuration.
	return {"ok": true, "model": model}


# Positive cyclic_forward tips the disc forward (negative a1). Positive
# cyclic_right gives positive b1. omega is relative shaft speed in rad/s.
static func evaluate(model: Dictionary, omega: float, induced_velocity: float,
		hub_air_velocity: PackedFloat64Array, body_rates: PackedFloat64Array,
		collective_75: float, cyclic_forward: float, cyclic_right: float,
		a1: float, b1: float) -> Dictionary:
	if not _prepared(model) \
		or not _vector(hub_air_velocity) or not _vector(body_rates) \
		or not _finite([omega, induced_velocity, collective_75, cyclic_forward, cyclic_right, a1, b1]) or omega < 0.0:
		return {"ok": false}
	for angle: float in [collective_75, cyclic_forward, cyclic_right, a1, b1]:
		if absf(angle) > PI / 2.0:
			return {"ok": false}
	if omega == 0.0:
		# Inactive azimuth-averaged disc; parked individual-blade mechanics are
		# outside this law. No fictitious isotropic hub spring at zero rpm.
		return {"ok": true, "rotor_active": false, "theta0_rad": collective_75, "solidity": model.solidity,
			"lambda0": null, "induced_velocity_m_s": null, "mu_x": null, "mu_y": null, "mu_z": null, "mu": null,
			"within_identified_advance_ratio": false, "within_small_flap_angle_range": absf(a1) < PI / 18.0 and absf(b1) < PI / 18.0,
			"lock_number": model.lock_number, "bare_flap_time_constant_nominal_s": model.bare_flap_time_constant_nominal_s,
			"thrust_coefficient_ideal": null, "thrust_coefficient": null, "thrust_n": 0.0,
			"torque_coefficient": null, "torque_nm": 0.0,
			"thrust_normal_body_frd": M.v3(0.0, 0.0, 0.0),
			"force_body_frd_n": M.v3(0.0, 0.0, 0.0), "moment_body_frd_nm": M.v3(0.0, 0.0, 0.0),
			"hub_arm_moment_body_frd_nm": M.v3(0.0, 0.0, 0.0), "flap_spring_moment_body_frd_nm": M.v3(0.0, 0.0, 0.0),
			"reaction_torque_moment_body_frd_nm": M.v3(0.0, 0.0, 0.0), "effective_flap_time_constant_s": null,
			"flap_rate_a1_rad_s": 0.0, "flap_rate_b1_rad_s": 0.0,
			"loads": PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]), "flap_rate": PackedFloat64Array([0.0, 0.0])}
	var radius: float = model.rotor_radius_m
	var tip: float = omega * radius
	if not is_finite(tip) or tip <= 0.0:
		return {"ok": false}
	var mu_x: float = hub_air_velocity[0] / tip
	var mu_y: float = hub_air_velocity[1] / tip
	var mu_z: float = hub_air_velocity[2] / tip
	var lambda0: float = induced_velocity / tip
	var mu2: float = mu_x * mu_x + mu_y * mu_y
	if not _finite([mu_x, mu_y, mu_z, lambda0, mu2]) or mu2 >= 2.0:
		return {"ok": false} # Eq. 27's algebraic domain, not an identified envelope.
	var mu: float = M.sqrt_(mu2)
	var a_sigma: float = model.blade_lift_curve_slope_per_rad * model.solidity
	var ct_ideal: float = 0.5 * a_sigma * (collective_75 * (1.0 / 3.0 + 0.5 * mu2) + 0.5 * (mu_z - lambda0))
	var ct: float = clampf(ct_ideal, -model.thrust_coefficient_max, model.thrust_coefficient_max)
	var scale: float = model.rho_kg_m3 * PI * radius * radius * tip * tip
	var thrust: float = ct * scale
	var cq: float = ct * (lambda0 - mu_z) + model.blade_section_cd0 * model.solidity / 8.0 * (1.0 + (7.0 / 3.0) * mu2)
	var torque: float = cq * scale * radius
	var normal: PackedFloat64Array = M.v3(-M.sin_(a1), M.sin_(b1), -M.cos_(a1) * M.cos_(b1))
	normal = M.scale(normal, 1.0 / M.norm(normal)) # Explicit geometric extension of paper's small-angle moments.
	var force: PackedFloat64Array = M.scale(normal, thrust)
	var arm_moment: PackedFloat64Array = M.cross(M.v3(model.hub_x_m, model.hub_y_m, model.hub_z_m), force)
	var spring: PackedFloat64Array = M.v3(model.hub_spring_stiffness_nm_per_rad * b1, model.hub_spring_stiffness_nm_per_rad * a1, 0.0)
	var reaction: PackedFloat64Array = M.v3(0.0, 0.0, -model.rotation_sense * torque)
	var moment: PackedFloat64Array = M.add(M.add(arm_moment, spring), reaction)
	var tau: float = 16.0 / (model.gamma_flybar * omega)
	var speed_ratio: float = omega / model.omega_nominal_rad_s
	var gain_scale: float = speed_ratio * speed_ratio
	var flapback: float = 2.0 * model.flapback_k_mu * (4.0 * collective_75 / 3.0 - lambda0)
	# Paper defines nonnegative total mu but adds sign(mu) for backward flight.
	# sign(mu_x) is the explicit inferred backward-flight convention.
	var axial_flap: float = model.flapback_k_mu * 16.0 * mu2 \
		/ ((1.0 - 0.5 * mu2) * (8.0 * mu + a_sigma)) * signf(mu_x)
	var a_rate: float = -body_rates[1] + (-a1 + flapback * mu_x + axial_flap * mu_z \
		- model.cyclic_longitudinal_gain_nominal_rad_per_rad * gain_scale * cyclic_forward) / tau
	# Eqs. 17 and 26 together give PLUS flapback*mu_y (the initial plan had minus).
	var b_rate: float = -body_rates[0] + (-b1 + flapback * mu_y \
		+ model.cyclic_lateral_gain_nominal_rad_per_rad * gain_scale * cyclic_right) / tau
	if not _finite([ct_ideal, ct, thrust, cq, torque, tau, a_rate, b_rate]) or tau <= 0.0 \
		or not _vector(force) or not _vector(moment):
		return {"ok": false}
	return {"ok": true, "rotor_active": true, "theta0_rad": collective_75, "solidity": model.solidity,
		"lambda0": lambda0, "induced_velocity_m_s": induced_velocity, "mu_x": mu_x, "mu_y": mu_y,
		"mu_z": mu_z, "mu": mu, "within_identified_advance_ratio": mu < 0.15,
		"within_small_flap_angle_range": absf(a1) < PI / 18.0 and absf(b1) < PI / 18.0,
		"lock_number": model.lock_number, "bare_flap_time_constant_nominal_s": model.bare_flap_time_constant_nominal_s,
		"thrust_coefficient_ideal": ct_ideal, "thrust_coefficient": ct, "thrust_n": thrust,
		"torque_coefficient": cq, "torque_nm": torque, "thrust_normal_body_frd": normal,
		"force_body_frd_n": force, "moment_body_frd_nm": moment, "hub_arm_moment_body_frd_nm": arm_moment,
		"flap_spring_moment_body_frd_nm": spring, "reaction_torque_moment_body_frd_nm": reaction,
		"effective_flap_time_constant_s": tau, "flap_rate_a1_rad_s": a_rate, "flap_rate_b1_rad_s": b_rate,
		"loads": PackedFloat64Array([force[0], force[1], force[2], moment[0], moment[1], moment[2]]),
		"flap_rate": PackedFloat64Array([a_rate, b_rate])}


static func _vector(value: PackedFloat64Array) -> bool:
	if value.size() != 3:
		return false
	for entry: float in value:
		if not is_finite(entry):
			return false
	return true


static func _finite(values: Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true


static func _number(value: Variant) -> bool:
	return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value))


# Cheap structural/numeric guard for the immutable owner-prepared context.
# Coupled derived-value identity is established by prepare, not a file reader here.
static func _prepared(model: Dictionary) -> bool:
	if not model.is_read_only() or model.get("law") != LAW or model.size() != 22:
		return false
	for key: String in PARAMETER_KEYS:
		if key != "hub_position_body_frd_m" and (not model.has(key) or not _number(model[key])):
			return false
	for key: String in ["hub_x_m", "hub_y_m", "hub_z_m", "solidity", "lock_number", "bare_flap_time_constant_nominal_s"]:
		if not model.has(key) or not _number(model[key]):
			return false
	return model.rho_kg_m3 > 0.0 and model.rotor_radius_m > 0.0 and model.gamma_flybar > 0.0 \
		and model.omega_nominal_rad_s > 0.0 and model.blade_lift_curve_slope_per_rad > 0.0 \
		and model.thrust_coefficient_max > 0.0 and model.solidity > 0.0 and model.solidity < 1.0 \
		and model.rotor_blade_count == 2.0 and absf(model.rotation_sense) == 1.0
