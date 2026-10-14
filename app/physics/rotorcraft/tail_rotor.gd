# HELI-06a: Gavrilets et al. §§4.6/5 locally linearized X-Cell tail.
# Actual collective includes its trim offset. Body vectors use float64 FRD.
extends RefCounted

const M = preload("res://physics/math3d.gd")
const LAW: String = "openrc-xcell-linearized-tail-v1"
const PARAMETER_KEYS: Array = [
	"rho_kg_m3", "main_rotor_radius_m", "tail_rotor_radius_m", "blade_chord_m", "rotor_blade_count",
	"blade_lift_curve_slope_per_rad", "blade_section_cd0", "thrust_coefficient_max", "tail_to_main_speed_ratio",
	"hub_distance_aft_m", "hub_height_above_cg_m", "vertical_fin_area_m2", "trim_collective_rad",
	"wake_efficiency", "rotation_sense",
]
const PREPARED_KEYS: Array = PARAMETER_KEYS + ["law", "solidity", "blockage_factor", "wake_gi", "wake_gf"]


static func prepare(parameters: Dictionary) -> Dictionary:
	if parameters.size() != PARAMETER_KEYS.size() or not parameters.has_all(PARAMETER_KEYS):
		return {"ok": false}
	var model: Dictionary = {"law": LAW}
	for key: String in PARAMETER_KEYS:
		if not _number(parameters[key]):
			return {"ok": false}
		model[key] = float(parameters[key])
	for key: String in ["rho_kg_m3", "main_rotor_radius_m", "tail_rotor_radius_m", "blade_chord_m",
		"blade_lift_curve_slope_per_rad", "thrust_coefficient_max", "tail_to_main_speed_ratio",
		"hub_distance_aft_m", "hub_height_above_cg_m", "trim_collective_rad", "wake_efficiency"]:
		if model[key] <= 0.0:
			return {"ok": false}
	if model.rotor_blade_count != 2.0 or absf(model.rotation_sense) != 1.0 or model.wake_efficiency > 1.0 \
		or model.trim_collective_rad > PI / 2.0 or model.blade_section_cd0 < 0.0 or model.vertical_fin_area_m2 < 0.0:
		return {"ok": false}
	model.solidity = 2.0 * model.blade_chord_m / (PI * model.tail_rotor_radius_m)
	model.blockage_factor = 1.0 - 0.75 * model.vertical_fin_area_m2 / (PI * model.tail_rotor_radius_m * model.tail_rotor_radius_m)
	model.wake_gi = (model.hub_distance_aft_m - model.main_rotor_radius_m - model.tail_rotor_radius_m) / model.hub_height_above_cg_m
	model.wake_gf = (model.hub_distance_aft_m - model.main_rotor_radius_m + model.tail_rotor_radius_m) / model.hub_height_above_cg_m
	if model.solidity <= 0.0 or model.solidity >= 1.0 or model.blockage_factor <= 0.0 \
		or model.blockage_factor > 1.0 or model.wake_gf <= model.wake_gi:
		return {"ok": false}
	for value: Variant in model.values():
		if typeof(value) != TYPE_STRING and not is_finite(value):
			return {"ok": false}
	model.make_read_only()
	return {"ok": true, "model": model}


# Wake/velocity expressions are literal source geometry, not a general inverted
# wake model. Relative air velocity is evaluated at CG; source omits -h*q in u.
static func evaluate(model: Dictionary, omega_main: float, main_vi: float,
		cg_air_velocity: PackedFloat64Array, body_rates: PackedFloat64Array,
		collective: float, diagnostics: bool = true) -> Dictionary:
	if not _prepared(model):
		return {"ok": false}
	return _evaluate_prepared(model, omega_main, main_vi, cg_air_velocity, body_rates, collective, diagnostics)


# Internal stage entry after its immutable stage context was prepared.
static func _evaluate_prepared(model: Dictionary, omega_main: float, main_vi: float,
		cg_air_velocity: PackedFloat64Array, body_rates: PackedFloat64Array,
		collective: float, diagnostics: bool = true) -> Dictionary:
	if not _vector(cg_air_velocity) or not _vector(body_rates) \
		or not _finite([omega_main, main_vi, collective]) or omega_main < 0.0 or absf(collective) > PI / 2.0:
		return {"ok": false}
	var u: float = cg_air_velocity[0]
	var v: float = cg_air_velocity[1]
	var w: float = cg_air_velocity[2]
	var wake: float = 0.0
	if main_vi > w:
		var tangent: float = u / (main_vi - w)
		wake = 1.5 * clampf((tangent - model.wake_gi) / (model.wake_gf - model.wake_gi), 0.0, 1.0)
	var w_tail: float = w + model.hub_distance_aft_m * body_rates[1] - wake * main_vi
	var normal: float = v - model.hub_distance_aft_m * body_rates[2] + model.hub_height_above_cg_m * body_rates[0]
	var in_plane: float = M.sqrt_(u * u + w_tail * w_tail)
	var omega: float = model.tail_to_main_speed_ratio * omega_main
	var tip: float = omega * model.tail_rotor_radius_m
	if not _finite([wake, normal, in_plane, omega, tip]):
		return {"ok": false}
	if omega_main == 0.0:
		var stopped: Dictionary = {"ok": true, "rotor_active": false, "thrust_n": 0.0, "torque_nm": 0.0,
			"induced_velocity_m_s": 0.0, "wake_factor": wake, "thrust_limited": false, "loads": PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])}
		if diagnostics:
			stopped.merge({"tail_omega_rad_s": 0.0, "tip_speed_m_s": 0.0, "wake_factor": wake,
				"in_plane_velocity_m_s": in_plane, "normal_velocity_m_s": normal, "advance_ratio": null,
				"normal_flow_ratio": null, "trim_lambda": null, "trim_ct": null,
				"thrust_collective_slope_per_rad": null, "thrust_normal_flow_slope": null,
				"thrust_coefficient_ideal": null, "thrust_coefficient": null, "torque_coefficient": null,
				"blockage_factor": model.blockage_factor, "force_body_frd_n": M.v3(0.0, 0.0, 0.0),
				"moment_body_frd_nm": M.v3(0.0, 0.0, 0.0)})
		return stopped
	if tip <= 0.0:
		return {"ok": false}
	var mu: float = in_plane / tip
	var mu_z: float = normal / tip
	if not _finite([mu, mu_z]) or mu > 1e6 or absf(mu_z) > 1e6:
		return {"ok": false}
	var a_sigma: float = model.blade_lift_curve_slope_per_rad * model.solidity
	var k: float = a_sigma / 2.0
	var pitch_factor: float = 1.0 / 3.0 + mu * mu / 2.0
	var trim: Dictionary = _trim(mu, k, pitch_factor, model.trim_collective_rad, model.wake_efficiency)
	if not trim.ok or trim.ct >= model.thrust_coefficient_max:
		# A saturated trim cannot define the smooth local derivatives below.
		return {"ok": false}
	var s: float = M.sqrt_(mu * mu + trim.lambda0 * trim.lambda0)
	var momentum_slope: float = 2.0 * model.wake_efficiency * (mu * mu + 2.0 * trim.lambda0 * trim.lambda0) / s
	var slope_collective: float = k * pitch_factor * momentum_slope / (momentum_slope + k / 2.0)
	var slope_normal: float = k / 2.0 * (2.0 * model.wake_efficiency * s) / (momentum_slope + k / 2.0)
	# Eq. 47 is homogeneous in actual collective and normal flow; it does not
	# include an affine intercept that makes its trim thrust equal the root CT.
	var ct_ideal: float = slope_collective * collective + slope_normal * mu_z
	var ct: float = clampf(ct_ideal, -model.thrust_coefficient_max, model.thrust_coefficient_max)
	var scale: float = model.rho_kg_m3 * tip * tip * PI * model.tail_rotor_radius_m * model.tail_rotor_radius_m
	var thrust: float = model.blockage_factor * scale * ct
	# Eq. 50 reconstructs inflow from unblocked aerodynamic CT, after its cap.
	var lambda0: float = mu_z - 2.0 * (2.0 * ct / a_sigma - collective * pitch_factor)
	var vi: float = lambda0 * tip
	var cq: float = ct * (lambda0 - mu_z) + model.blade_section_cd0 * model.solidity / 8.0 * (1.0 + 7.0 * mu * mu / 3.0)
	var torque: float = scale * model.tail_rotor_radius_m * cq
	var fy: float = -thrust
	var mx: float = model.hub_height_above_cg_m * fy
	var my: float = -model.rotation_sense * torque
	var mz: float = -model.hub_distance_aft_m * fy
	if not _finite([slope_collective, slope_normal, ct_ideal, ct, scale, thrust, vi, cq, torque, mx, my, mz]):
		return {"ok": false}
	var result: Dictionary = {"ok": true, "rotor_active": true, "thrust_n": thrust, "torque_nm": torque,
		"induced_velocity_m_s": vi, "wake_factor": wake, "thrust_limited": ct != ct_ideal,
		"loads": PackedFloat64Array([0.0, fy, 0.0, mx, my, mz])}
	if diagnostics:
		result.merge({"tail_omega_rad_s": omega, "tip_speed_m_s": tip, "wake_factor": wake,
			"in_plane_velocity_m_s": in_plane, "normal_velocity_m_s": normal, "advance_ratio": mu,
			"normal_flow_ratio": mu_z, "trim_lambda": trim.lambda0, "trim_ct": trim.ct,
			"thrust_collective_slope_per_rad": slope_collective, "thrust_normal_flow_slope": slope_normal,
			"thrust_coefficient_ideal": ct_ideal, "thrust_coefficient": ct, "torque_coefficient": cq,
			"blockage_factor": model.blockage_factor, "force_body_frd_n": M.v3(0.0, fy, 0.0),
			"moment_body_frd_nm": M.v3(mx, my, mz)})
	return result


# Only the positive, zero-normal-flow trim is solved. Its residual is monotone,
# so a safeguarded Newton solve has a unique root and a bounded fallback. This
# does not solve nonlinear tail inflow in VRS or qualify quasi-static dynamics.
static func _trim(mu: float, k: float, pitch_factor: float, collective: float, eta: float) -> Dictionary:
	var drive: float = k * collective * pitch_factor
	var b: float = k / 2.0
	if not _finite([drive, b]) or drive <= 0.0 or b <= 0.0:
		return {"ok": false}
	var lo: float = 0.0
	var hi: float = minf(drive / (b + 2.0 * eta * mu), M.sqrt_(drive / (2.0 * eta)))
	var root: float = hi * 0.5
	if mu == 0.0:
		root = 2.0 * drive / (b + M.sqrt_(b * b + 8.0 * eta * drive))
	else:
		for iteration: int in range(60):
			var s: float = M.sqrt_(mu * mu + root * root)
			var residual: float = root * (b + 2.0 * eta * s) - drive
			if absf(residual) <= 1e-13 * drive:
				break
			if residual > 0.0:
				hi = root
			else:
				lo = root
			var derivative: float = b + 2.0 * eta * (mu * mu + 2.0 * root * root) / s
			var proposal: float = root - residual / derivative
			root = proposal if iteration < 12 and proposal > lo and proposal < hi else (lo + hi) / 2.0
	var s: float = M.sqrt_(mu * mu + root * root)
	var ct: float = 2.0 * eta * root * s
	var residual: float = root * (b + 2.0 * eta * s) - drive
	if not _finite([root, ct, residual]) or root <= 0.0 or absf(residual) > 1e-12 * drive:
		return {"ok": false}
	return {"ok": true, "lambda0": root, "ct": ct}


static func _number(value: Variant) -> bool:
	return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value))


static func _finite(values: Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true


static func _vector(value: PackedFloat64Array) -> bool:
	return value.size() == 3 and _finite(Array(value))


static func _prepared(model: Dictionary) -> bool:
	if not _prepared_header(model):
		return false
	var numbers: Array = model.values()
	numbers.erase(LAW)
	for value: Variant in numbers:
		if typeof(value) != TYPE_FLOAT or not is_finite(value):
			return false
	return model.rho_kg_m3 > 0.0 and model.main_rotor_radius_m > 0.0 and model.tail_rotor_radius_m > 0.0 \
		and model.blade_chord_m > 0.0 and model.tail_to_main_speed_ratio > 0.0 \
		and model.hub_distance_aft_m > 0.0 and model.hub_height_above_cg_m > 0.0 \
		and model.blade_section_cd0 >= 0.0 and model.vertical_fin_area_m2 >= 0.0 \
		and model.blade_lift_curve_slope_per_rad > 0.0 and model.thrust_coefficient_max > 0.0 \
		and model.solidity > 0.0 and model.solidity < 1.0 and model.blockage_factor > 0.0 and model.blockage_factor <= 1.0 \
		and model.wake_efficiency > 0.0 and model.wake_efficiency <= 1.0 and model.wake_gf > model.wake_gi \
		and model.trim_collective_rad > 0.0 and model.trim_collective_rad <= PI / 2.0 \
		and model.rotor_blade_count == 2.0 and absf(model.rotation_sense) == 1.0


static func _prepared_header(model: Dictionary) -> bool:
	return model.is_read_only() and model.get("law") == LAW and model.size() == PREPARED_KEYS.size() \
		and model.has_all(PREPARED_KEYS)
