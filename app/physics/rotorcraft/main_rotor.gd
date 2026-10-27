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
const PREPARED_KEYS: Array = [
	"law", "rho_kg_m3", "rotor_radius_m", "blade_chord_m", "rotor_blade_count",
	"blade_lift_curve_slope_per_rad", "blade_section_cd0", "thrust_coefficient_max",
	"blade_flapping_inertia_kg_m2", "gamma_flybar", "flapback_k_mu", "omega_nominal_rad_s",
	"cyclic_longitudinal_gain_nominal_rad_per_rad", "cyclic_lateral_gain_nominal_rad_per_rad",
	"hub_spring_stiffness_nm_per_rad", "rotation_sense", "hub_x_m", "hub_y_m", "hub_z_m",
	"solidity", "lock_number", "bare_flap_time_constant_nominal_s",
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
		a1: float, b1: float, diagnostics: bool = true) -> Dictionary:
	if not _prepared(model):
		return {"ok": false}
	return _evaluate_prepared(model, omega, induced_velocity, hub_air_velocity, body_rates,
		collective_75, cyclic_forward, cyclic_right, a1, b1, diagnostics)


# Internal stage entry. Its caller has already validated and frozen the complete
# model context; dynamic inputs and computed outputs are still checked below.
static func _evaluate_prepared(model: Dictionary, omega: float, induced_velocity: float,
		hub_air_velocity: PackedFloat64Array, body_rates: PackedFloat64Array,
		collective_75: float, cyclic_forward: float, cyclic_right: float,
		a1: float, b1: float, diagnostics: bool = true) -> Dictionary:
	if not _vector(hub_air_velocity) or not _vector(body_rates) \
		or not _finite([omega, induced_velocity, collective_75, cyclic_forward, cyclic_right, a1, b1]) or omega < 0.0:
		return {"ok": false}
	for angle: float in [collective_75, cyclic_forward, cyclic_right, a1, b1]:
		if absf(angle) > PI / 2.0:
			return {"ok": false}
	if omega == 0.0:
		if not diagnostics:
			return {"ok": true, "rotor_active": false, "thrust_n": 0.0, "torque_nm": 0.0,
				"within_identified_advance_ratio": false,
				"within_small_flap_angle_range": absf(a1) < PI / 18.0 and absf(b1) < PI / 18.0,
				"flap_rate_a1_rad_s": 0.0, "flap_rate_b1_rad_s": 0.0,
				"loads": PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]), "flap_rate": PackedFloat64Array([0.0, 0.0])}
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
	# The azimuth-averaged source law divides by tip speed and is not a stopped
	# blade model. Below its low-advance-ratio transition, use an explicitly
	# estimated, bounded rotor-plane drag and collective thrust that decay
	# continuously with shaft speed. Parked-blade orientation and windmill energy
	# capture remain outside this approximation.
	var crossflow: float = sqrt(hub_air_velocity[0] * hub_air_velocity[0]
		+ hub_air_velocity[1] * hub_air_velocity[1])
	var transition: PackedFloat64Array = low_rpm_transition(model, crossflow)
	var low_result: Dictionary = {}
	var low_weight: float = 0.0
	if omega < transition[1]:
		low_result = _evaluate_low_rpm(model, omega, induced_velocity, hub_air_velocity,
			body_rates, collective_75, cyclic_forward, cyclic_right, a1, b1, transition[0], crossflow)
		if not low_result.get("ok", false):
			return low_result
		if omega <= transition[0]:
			return low_result
		var blend: float = (omega - transition[0]) / (transition[1] - transition[0])
		blend = clampf(blend, 0.0, 1.0)
		low_weight = 1.0 - blend * blend * (3.0 - 2.0 * blend)
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
	var mu: float = sqrt(mu2)
	var a_sigma: float = model.blade_lift_curve_slope_per_rad * model.solidity
	var ct_ideal: float = 0.5 * a_sigma * (collective_75 * (1.0 / 3.0 + 0.5 * mu2) + 0.5 * (mu_z - lambda0))
	var ct: float = clampf(ct_ideal, -model.thrust_coefficient_max, model.thrust_coefficient_max)
	var scale: float = model.rho_kg_m3 * PI * radius * radius * tip * tip
	var thrust: float = ct * scale
	var cq: float = ct * (lambda0 - mu_z) + model.blade_section_cd0 * model.solidity / 8.0 * (1.0 + (7.0 / 3.0) * mu2)
	var torque: float = cq * scale * radius
	var nx: float = -M.sin_(a1)
	var ny: float = M.sin_(b1)
	var nz: float = -M.cos_(a1) * M.cos_(b1)
	var inverse_length: float = 1.0 / sqrt(nx * nx + ny * ny + nz * nz)
	nx *= inverse_length
	ny *= inverse_length
	nz *= inverse_length
	var fx: float = nx * thrust
	var fy: float = ny * thrust
	var fz: float = nz * thrust
	var arm_x: float = model.hub_y_m * fz - model.hub_z_m * fy
	var arm_y: float = model.hub_z_m * fx - model.hub_x_m * fz
	var arm_z: float = model.hub_x_m * fy - model.hub_y_m * fx
	var spring_x: float = model.hub_spring_stiffness_nm_per_rad * b1
	var spring_y: float = model.hub_spring_stiffness_nm_per_rad * a1
	var reaction_z: float = -model.rotation_sense * torque
	var mx: float = arm_x + spring_x
	var my: float = arm_y + spring_y
	var mz: float = arm_z + reaction_z
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
	if not _finite([ct_ideal, ct, thrust, cq, torque, tau, a_rate, b_rate, fx, fy, fz, mx, my, mz]) or tau <= 0.0:
		return {"ok": false}
	var loads: PackedFloat64Array = PackedFloat64Array([fx, fy, fz, mx, my, mz])
	var flap_rate: PackedFloat64Array = PackedFloat64Array([a_rate, b_rate])
	if not diagnostics:
		var compact: Dictionary = {"ok": true, "rotor_active": true, "thrust_n": thrust, "torque_nm": torque,
			"within_identified_advance_ratio": mu < 0.15,
			"within_small_flap_angle_range": absf(a1) < PI / 18.0 and absf(b1) < PI / 18.0,
			"flap_rate_a1_rad_s": a_rate, "flap_rate_b1_rad_s": b_rate,
			"loads": loads, "flap_rate": flap_rate}
		return _blend_low_rpm(low_result, compact, low_weight)
	var full: Dictionary = {"ok": true, "rotor_active": true, "theta0_rad": collective_75, "solidity": model.solidity,
		"lambda0": lambda0, "induced_velocity_m_s": induced_velocity, "mu_x": mu_x, "mu_y": mu_y,
		"mu_z": mu_z, "mu": mu, "within_identified_advance_ratio": mu < 0.15,
		"within_small_flap_angle_range": absf(a1) < PI / 18.0 and absf(b1) < PI / 18.0,
		"lock_number": model.lock_number, "bare_flap_time_constant_nominal_s": model.bare_flap_time_constant_nominal_s,
		"thrust_coefficient_ideal": ct_ideal, "thrust_coefficient": ct, "thrust_n": thrust,
		"torque_coefficient": cq, "torque_nm": torque, "thrust_normal_body_frd": M.v3(nx, ny, nz),
		"force_body_frd_n": M.v3(fx, fy, fz), "moment_body_frd_nm": M.v3(mx, my, mz), "hub_arm_moment_body_frd_nm": M.v3(arm_x, arm_y, arm_z),
		"flap_spring_moment_body_frd_nm": M.v3(spring_x, spring_y, 0.0), "reaction_torque_moment_body_frd_nm": M.v3(0.0, 0.0, reaction_z),
		"effective_flap_time_constant_s": tau, "flap_rate_a1_rad_s": a_rate, "flap_rate_b1_rad_s": b_rate,
		"loads": loads, "flap_rate": flap_rate}
	return _blend_low_rpm(low_result, full, low_weight)


## The upper endpoint corresponds to μ=0.15 until the 20%-nominal-speed cap
## is reached. Above that crossflow, the estimated/legacy blend ends at the cap;
## the legacy algebra domain remains authoritative and identified μ is false.
## With no crossflow, retain a short startup band at 4–8% nominal RPM.
static func low_rpm_transition(model: Dictionary, crossflow_m_s: float) -> PackedFloat64Array:
	var upper: float = maxf(0.08 * model.omega_nominal_rad_s,
		crossflow_m_s / (0.15 * model.rotor_radius_m))
	upper = minf(0.20 * model.omega_nominal_rad_s, upper)
	return PackedFloat64Array([0.5 * upper, upper])


static func low_rpm_estimate_active(model: Dictionary, omega: float,
		hub_air_velocity: PackedFloat64Array) -> bool:
	if omega <= 0.0 or hub_air_velocity.size() != 3:
		return omega == 0.0
	var crossflow: float = sqrt(hub_air_velocity[0] * hub_air_velocity[0]
		+ hub_air_velocity[1] * hub_air_velocity[1])
	return omega <= low_rpm_transition(model, crossflow)[0]


static func _evaluate_low_rpm(model: Dictionary, omega: float, induced_velocity: float,
		hub_air_velocity: PackedFloat64Array, body_rates: PackedFloat64Array,
		collective_75: float, cyclic_forward: float, cyclic_right: float,
		a1: float, b1: float, lower_transition: float, crossflow: float) -> Dictionary:
	var radius: float = model.rotor_radius_m
	var tip: float = omega * radius
	var disk_area: float = PI * radius * radius
	var activity: float = 1.0
	if crossflow > 0.0:
		activity = tip * tip / (tip * tip + crossflow * crossflow)
	var angle_activity: float = omega * omega / (omega * omega + lower_transition * lower_transition)
	var a_sigma: float = model.blade_lift_curve_slope_per_rad * model.solidity
	var ct: float = clampf(a_sigma * collective_75 / 6.0,
		-model.thrust_coefficient_max, model.thrust_coefficient_max)
	var scale: float = model.rho_kg_m3 * disk_area * tip * tip
	var thrust: float = ct * scale * activity
	var profile_cq: float = model.blade_section_cd0 * model.solidity / 8.0
	var profile_torque: float = profile_cq * scale * radius * activity
	var induced_torque: float = absf(ct) * absf(induced_velocity) \
		* model.rho_kg_m3 * disk_area * tip * radius * activity
	var torque: float = profile_torque + induced_torque
	var nx: float = -M.sin_(a1)
	var ny: float = M.sin_(b1)
	var nz: float = -M.cos_(a1) * M.cos_(b1)
	var inverse_length: float = 1.0 / sqrt(nx * nx + ny * ny + nz * nz)
	nx *= inverse_length
	ny *= inverse_length
	nz *= inverse_length
	var q: float = 0.5 * model.rho_kg_m3 * crossflow * crossflow
	var drag: float = q * model.solidity * disk_area * model.blade_section_cd0 * activity
	var fx: float = nx * thrust
	var fy: float = ny * thrust
	var fz: float = nz * thrust
	if crossflow > 0.0:
		fx -= drag * hub_air_velocity[0] / crossflow
		fy -= drag * hub_air_velocity[1] / crossflow
	var arm_x: float = model.hub_y_m * fz - model.hub_z_m * fy
	var arm_y: float = model.hub_z_m * fx - model.hub_x_m * fz
	var arm_z: float = model.hub_x_m * fy - model.hub_y_m * fx
	var spring_x: float = model.hub_spring_stiffness_nm_per_rad * b1 * angle_activity
	var spring_y: float = model.hub_spring_stiffness_nm_per_rad * a1 * angle_activity
	var reaction_z: float = -model.rotation_sense * torque
	var mx: float = arm_x + spring_x
	var my: float = arm_y + spring_y
	var mz: float = arm_z + reaction_z
	var loads: PackedFloat64Array = PackedFloat64Array([fx, fy, fz, mx, my, mz])
	var tau_rate: float = model.gamma_flybar * omega / 16.0
	var speed_ratio: float = omega / model.omega_nominal_rad_s
	var gain_scale: float = speed_ratio * speed_ratio
	var a_rate: float = angle_activity * (-body_rates[1]
		+ (-a1 - model.cyclic_longitudinal_gain_nominal_rad_per_rad * gain_scale * cyclic_forward) * tau_rate)
	var b_rate: float = angle_activity * (-body_rates[0]
		+ (-b1 + model.cyclic_lateral_gain_nominal_rad_per_rad * gain_scale * cyclic_right) * tau_rate)
	var flap_rate: PackedFloat64Array = PackedFloat64Array([a_rate, b_rate])
	if not _finite([activity, angle_activity, ct, scale, thrust, torque, drag, fx, fy, fz,
		mx, my, mz, a_rate, b_rate, induced_velocity]):
		return {"ok": false, "message": "estimated low-RPM rotor law produced a nonfinite value"}
	return {"ok": true, "rotor_active": true, "thrust_n": thrust, "torque_nm": torque,
		"within_identified_advance_ratio": false,
		"within_small_flap_angle_range": absf(a1) < PI / 18.0 and absf(b1) < PI / 18.0,
		"flap_rate_a1_rad_s": a_rate, "flap_rate_b1_rad_s": b_rate,
		"loads": loads, "flap_rate": flap_rate,
		"estimated_regime": "bounded_low_rpm_startup",
		"estimated_low_rpm_weight": 1.0,
		"low_rpm_activity": activity, "thrust_coefficient_estimate": ct,
		"profile_torque_nm": profile_torque, "induced_torque_estimate_nm": induced_torque}


static func _blend_low_rpm(low: Dictionary, standard: Dictionary, low_weight: float) -> Dictionary:
	if low_weight <= 0.0:
		return standard
	var result: Dictionary = standard.duplicate()
	for key: String in ["thrust_n", "torque_nm", "flap_rate_a1_rad_s", "flap_rate_b1_rad_s"]:
		result[key] = lerpf(float(standard[key]), float(low[key]), low_weight)
	for key: String in ["loads", "flap_rate"]:
		var values: PackedFloat64Array = standard[key].duplicate()
		for index: int in range(values.size()):
			values[index] = lerpf(values[index], low[key][index], low_weight)
		result[key] = values
	var blended_loads: PackedFloat64Array = result.loads
	result["force_body_frd_n"] = M.v3(blended_loads[0], blended_loads[1], blended_loads[2])
	result["moment_body_frd_nm"] = M.v3(blended_loads[3], blended_loads[4], blended_loads[5])
	# These describe the legacy end-member, not the weighted physical output.
	# Its scalar coefficient/decomposition cannot be inferred from the bounded
	# startup estimate, which includes separate drag and activity terms.
	for key: String in ["lambda0", "thrust_coefficient_ideal", "thrust_coefficient",
		"torque_coefficient", "thrust_normal_body_frd", "hub_arm_moment_body_frd_nm",
		"flap_spring_moment_body_frd_nm", "reaction_torque_moment_body_frd_nm",
		"effective_flap_time_constant_s"]:
		if result.has(key):
			result[key] = null
	result["estimated_regime"] = "blended_low_rpm_startup"
	result["estimated_low_rpm_weight"] = low_weight
	result["within_identified_advance_ratio"] = false
	return result


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
	if not _prepared_header(model):
		return false
	# prepare converts every numeric field to float. Batch the native dictionary
	# read and inline finite/type checks rather than 21 script dispatches.
	var numbers: Array = model.values()
	numbers.erase(LAW)
	for value: Variant in numbers:
		if typeof(value) != TYPE_FLOAT or not is_finite(value):
			return false
	return model.rho_kg_m3 > 0.0 and model.rotor_radius_m > 0.0 and model.gamma_flybar > 0.0 \
		and model.omega_nominal_rad_s > 0.0 and model.blade_lift_curve_slope_per_rad > 0.0 \
		and model.thrust_coefficient_max > 0.0 and model.solidity > 0.0 and model.solidity < 1.0 \
		and model.rotor_blade_count == 2.0 and absf(model.rotation_sense) == 1.0


static func _prepared_header(model: Dictionary) -> bool:
	return model.is_read_only() and model.get("law") == LAW and model.size() == PREPARED_KEYS.size() \
		and model.has_all(PREPARED_KEYS)
