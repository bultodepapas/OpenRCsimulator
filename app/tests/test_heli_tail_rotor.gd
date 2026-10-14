# HELI-06a: independent analytic anchors, signs, geometry and Python oracle.
extends SceneTree

const Tail = preload("res://physics/rotorcraft/tail_rotor.gd")
const M = preload("res://physics/math3d.gd")
const PARAMS: Dictionary = {
	"rho_kg_m3": 1.225, "main_rotor_radius_m": 0.775, "tail_rotor_radius_m": 0.13,
	"blade_chord_m": 0.029, "rotor_blade_count": 2, "blade_lift_curve_slope_per_rad": 5.0,
	"blade_section_cd0": 0.024, "thrust_coefficient_max": 0.05, "tail_to_main_speed_ratio": 4.66,
	"hub_distance_aft_m": 0.91, "hub_height_above_cg_m": 0.08, "vertical_fin_area_m2": 0.012,
	"trim_collective_rad": 0.1, "wake_efficiency": 0.9, "rotation_sense": 1,
}
var checks: int = 0
var failures: int = 0
var model: Dictionary


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)


func close(label: String, actual: float, expected: float, tolerance: float = 1e-12) -> void:
	check(label, is_finite(actual) and absf(actual - expected) <= tolerance * maxf(1.0, absf(expected)))


func _eval(collective: float = 0.1, omega: float = 167.0, vi: float = 0.0,
		air: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0]),
		rates: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])) -> Dictionary:
	return Tail.evaluate(model, omega, vi, air, rates, collective)


func _initialize() -> void:
	var prepared: Dictionary = Tail.prepare(PARAMS)
	check("source fixture prepares", prepared.ok)
	if not prepared.ok:
		quit(1)
		return
	model = prepared.model
	check("context flat and read-only", model.is_read_only())
	_anchors()
	_signs()
	_geometry()
	_invalid()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--oracle="):
			_oracle(argument.substr(9))
	print("HELI-06a tail rotor: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _anchors() -> void:
	close("source blockage", model.blockage_factor, 1.0 - 0.75 * 0.012 / (PI * 0.13 * 0.13))
	close("source solidity two blades", model.solidity, 2.0 * 0.029 / (PI * 0.13))
	# Construct a known trim lambda independently from the hover quadratic.
	var parameters: Dictionary = PARAMS.duplicate()
	parameters.wake_efficiency = 1.0
	var a_sigma: float = 5.0 * 2.0 * 0.029 / (PI * 0.13)
	parameters.trim_collective_rad = 3.0 * (4.0 * 0.05 * 0.05 / a_sigma + 0.05 / 2.0)
	var anchor_model: Dictionary = Tail.prepare(parameters).model
	var anchor: Dictionary = Tail.evaluate(anchor_model, 167.0, 0.0, M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0), parameters.trim_collective_rad)
	check("constructed hover anchor valid", anchor.ok)
	close("independent trim root lambda", anchor.trim_lambda, 0.05)
	close("momentum hover trim CT", anchor.trim_ct, 2.0 * 0.05 * 0.05)
	close("Eq9 hover normal derivative eta1", anchor.thrust_normal_flow_slope, 2.0 * a_sigma * 0.05 / (16.0 * 0.05 + a_sigma))
	close("Eq10 hover collective derivative eta1", anchor.thrust_collective_slope_per_rad, (8.0 / 3.0) * a_sigma * 0.05 / (16.0 * 0.05 + a_sigma))
	close("literal Eq47 actual pitch no affine intercept", anchor.thrust_coefficient, anchor.thrust_collective_slope_per_rad * parameters.trim_collective_rad)
	check("literal linear model trim CT differs from coefficient root", absf(anchor.thrust_coefficient - anchor.trim_ct) > 1e-5)
	var hover: Dictionary = _eval()
	var tip: float = 4.66 * 167.0 * 0.13
	close("source gear ratio", hover.tail_omega_rad_s, 4.66 * 167.0)
	close("unblocked aerodynamic power balance", hover.torque_nm * hover.tail_omega_rad_s,
		hover.thrust_n / model.blockage_factor * hover.induced_velocity_m_s
		+ 1.225 * PI * 0.13 * 0.13 * tip * tip * 0.13 * (0.024 * model.solidity / 8.0) * hover.tail_omega_rad_s)
	for mu: float in [0.0, 1e-10, 1e-5, 0.01, 0.05, 0.15, 0.5, 1.0]:
		var row: Dictionary = _eval(0.1, 167.0, 0.0, M.v3(mu * tip, 0.0, 0.0))
		check("bounded trim solve valid " + str(mu), row.ok)
		if row.ok:
			var lambda0: float = row.trim_lambda
			var ct_momentum: float = 2.0 * 0.9 * lambda0 * M.sqrt_(mu * mu + lambda0 * lambda0)
			var ct_blade: float = 5.0 * model.solidity / 2.0 * (0.1 * (1.0 / 3.0 + mu * mu / 2.0) - lambda0 / 2.0)
			close("positive trim momentum residual " + str(mu), ct_momentum, ct_blade, 1e-12)
	# Independent central differences of the nonlinear Eqs. 4/5 near the
	# positive trim branch check both derivatives away from hover.
	for mu: float in [0.0, 0.05, 0.15, 0.3]:
		var row: Dictionary = _eval(0.1, 167.0, 0.0, M.v3(mu * tip, 0.0, 0.0))
		var epsilon: float = 1e-6
		var dc_dpitch: float = (_nonlinear_ct(mu, 0.0, 0.1 + epsilon) - _nonlinear_ct(mu, 0.0, 0.1 - epsilon)) / (2.0 * epsilon)
		var dc_dnormal: float = (_nonlinear_ct(mu, epsilon, 0.1) - _nonlinear_ct(mu, -epsilon, 0.1)) / (2.0 * epsilon)
		close("non-hover collective derivative " + str(mu), row.thrust_collective_slope_per_rad, dc_dpitch, 1e-8)
		close("non-hover normal derivative " + str(mu), row.thrust_normal_flow_slope, dc_dnormal, 1e-8)
	var small_parameters: Dictionary = PARAMS.duplicate()
	small_parameters.blade_lift_curve_slope_per_rad = 1e-100
	var small_model: Dictionary = Tail.prepare(small_parameters).model
	for mu: float in [0.0, 0.1, 0.5]:
		var row: Dictionary = Tail.evaluate(small_model, 167.0, 0.0, M.v3(mu * tip, 0.0, 0.0), M.v3(0.0, 0.0, 0.0), 0.1)
		check("scaled trim bracket valid " + str(mu), row.ok)
		if row.ok:
			var ct_momentum: float = 2.0 * 0.9 * row.trim_lambda * M.sqrt_(mu * mu + row.trim_lambda * row.trim_lambda)
			var ct_blade: float = 1e-100 * small_model.solidity / 2.0 * (0.1 * (1.0 / 3.0 + mu * mu / 2.0) - row.trim_lambda / 2.0)
			check("scale-relative trim residual " + str(mu), absf(ct_momentum - ct_blade) / ct_blade < 1e-12)


# Test-only dense bisection, separate from the production trim solver and its
# derivative formulas. These tiny perturbations stay on its positive branch.
func _nonlinear_ct(mu: float, mu_z: float, pitch: float) -> float:
	var lo: float = 0.0
	var hi: float = 1.0
	var k: float = 5.0 * 2.0 * 0.029 / (PI * 0.13) / 2.0
	for _iteration: int in range(80):
		var vi: float = (lo + hi) / 2.0
		var momentum_ct: float = 2.0 * 0.9 * vi * M.sqrt_(mu * mu + (vi - mu_z) * (vi - mu_z))
		var blade_ct: float = k * (pitch * (1.0 / 3.0 + mu * mu / 2.0) + (mu_z - vi) / 2.0)
		if momentum_ct > blade_ct:
			hi = vi
		else:
			lo = vi
	var vi: float = (lo + hi) / 2.0
	return 2.0 * 0.9 * vi * M.sqrt_(mu * mu + (vi - mu_z) * (vi - mu_z))


func _signs() -> void:
	var hover: Dictionary = _eval()
	check("positive actual pitch thrusts left", hover.thrust_n > 0.0 and hover.loads[1] < 0.0)
	close("tail reaction counters main negative yaw", hover.loads[5], 0.91 * hover.thrust_n)
	close("CG arm roll only once", hover.loads[3], -0.08 * hover.thrust_n)
	close("tail torque reaction about +y", hover.loads[4], -hover.torque_nm)
	var negative: Dictionary = _eval(-0.1)
	close("signed pitch reverses force", negative.thrust_n, -hover.thrust_n)
	close("signed pitch reverses induced wake", negative.induced_velocity_m_s, -hover.induced_velocity_m_s)
	close("signed pitch preserves induced/profile torque", negative.torque_nm, hover.torque_nm)
	var positive_flow: Dictionary = _eval(0.1, 167.0, 0.0, M.v3(5.0, 2.0, 0.0))
	var negative_flow: Dictionary = _eval(-0.1, 167.0, 0.0, M.v3(5.0, -2.0, 0.0))
	close("pitch/normal reflection thrust", negative_flow.thrust_n, -positive_flow.thrust_n)
	close("pitch/normal reflection inflow", negative_flow.induced_velocity_m_s, -positive_flow.induced_velocity_m_s)
	close("pitch/normal reflection power", negative_flow.torque_nm, positive_flow.torque_nm)
	var zero_pitch: Dictionary = _eval(0.0, 167.0, 0.0, M.v3(0.0, 2.0, 0.0))
	check("normal right motion creates left damping force", zero_pitch.loads[1] < 0.0)
	var yaw: Dictionary = _eval(0.0, 167.0, 0.0, M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.2))
	check("positive body yaw creates negative yaw damping", yaw.loads[5] < 0.0)
	var parameters: Dictionary = PARAMS.duplicate()
	parameters.rotation_sense = -1
	var reverse: Dictionary = Tail.evaluate(Tail.prepare(parameters).model, 167.0, 0.0, M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0), 0.1)
	close("tail spin sense only changes pitch reaction", reverse.loads[4], -hover.loads[4])
	close("same collective force independent of tail spin sense", reverse.loads[1], hover.loads[1])
	var cap: Dictionary = _eval(1.0)
	var negative_cap: Dictionary = _eval(-1.0)
	check("positive and negative thrust cap reported", cap.thrust_limited and negative_cap.thrust_limited)
	close("positive source cap", cap.thrust_coefficient, 0.05)
	close("negative source cap", negative_cap.thrust_coefficient, -0.05)
	close("blocked force cap known answer", cap.thrust_n,
		model.blockage_factor * 0.05 * 1.225 * PI * 0.13 * 0.13 * (4.66 * 167.0 * 0.13) * (4.66 * 167.0 * 0.13))
	var low_speed: Dictionary = _eval(1.0, 83.5)
	close("drooping head speed quadratic capped authority", low_speed.thrust_n, cap.thrust_n / 4.0)
	var stopped: Dictionary = _eval(0.1, 0.0, 4.2, M.v3(5.0, 2.0, 1.0), M.v3(0.2, 0.3, 0.4))
	check("zero speed inactive azimuth-averaged disc", stopped.ok and not stopped.rotor_active and stopped.advance_ratio == null)
	check("zero speed no load or quasistatic tail wake", stopped.loads == PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]) and stopped.induced_velocity_m_s == 0.0)


func _geometry() -> void:
	var vi: float = 4.2
	var start: float = model.wake_gi * vi
	var end: float = model.wake_gf * vi
	close("wake start", _eval(0.1, 167.0, vi, M.v3(start, 0.0, 0.0)).wake_factor, 0.0)
	close("wake midpoint", _eval(0.1, 167.0, vi, M.v3((start + end) / 2.0, 0.0, 0.0)).wake_factor, 0.75)
	close("wake end", _eval(0.1, 167.0, vi, M.v3(end, 0.0, 0.0)).wake_factor, 1.5)
	close("signed backward speed is outside wake", _eval(0.1, 167.0, vi, M.v3(-10.0, 0.0, 0.0)).wake_factor, 0.0)
	close("main vi equals vertical relative flow disables wake", _eval(0.1, 167.0, vi, M.v3(3.0, 0.0, vi)).wake_factor, 0.0)
	var rates: Dictionary = _eval(0.1, 167.0, 0.0, M.v3(3.0, 2.0, 1.0), M.v3(0.2, -0.3, 0.4))
	close("hub normal point velocity p/r signs", rates.normal_velocity_m_s, 2.0 - 0.91 * 0.4 + 0.08 * 0.2)
	close("hub vertical point velocity q sign", rates.in_plane_velocity_m_s, M.sqrt_(3.0 * 3.0 + (1.0 - 0.91 * 0.3) * (1.0 - 0.91 * 0.3)))


func _invalid() -> void:
	for key: String in PARAMS:
		var missing: Dictionary = PARAMS.duplicate()
		missing.erase(key)
		check("missing config " + key, not Tail.prepare(missing).ok)
		for value: Variant in [NAN, INF, true, "invalid"]:
			var invalid: Dictionary = PARAMS.duplicate()
			invalid[key] = value
			check("bad config " + key, not Tail.prepare(invalid).ok)
	var extra: Dictionary = PARAMS.duplicate()
	extra.extra = 1.0
	check("extra config rejected", not Tail.prepare(extra).ok)
	for key: String in ["rho_kg_m3", "tail_rotor_radius_m", "hub_height_above_cg_m", "trim_collective_rad", "wake_efficiency"]:
		var invalid: Dictionary = PARAMS.duplicate()
		invalid[key] = 0.0
		check("invalid config range " + key, not Tail.prepare(invalid).ok)
	var blocked: Dictionary = PARAMS.duplicate()
	blocked.vertical_fin_area_m2 = 1.0
	check("negative blocked area cannot prepare", not Tail.prepare(blocked).ok)
	var immutable: Dictionary = PARAMS.duplicate()
	var detached: Dictionary = Tail.prepare(immutable).model
	immutable.tail_rotor_radius_m = 9.0
	close("prepared scalar config detached from caller", detached.tail_rotor_radius_m, 0.13)
	check("negative speed rejected", not _eval(0.1, -1.0).ok)
	check("bad finite inputs rejected", not _eval(NAN).ok and not _eval(0.1, INF).ok and not _eval(0.1, 167.0, NAN).ok)
	check("unqualified angle rejected", not _eval(PI).ok)
	check("malformed vector rejected", not _eval(0.1, 167.0, 0.0, PackedFloat64Array([1.0])).ok)
	check("nonfinite vector rejected", not _eval(0.1, 167.0, 0.0, M.v3(0.0, NAN, 0.0)).ok)
	check("mutable context rejected", not Tail.evaluate(model.duplicate(), 167.0, 0.0, M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0), 0.1).ok)
	check("overflow inputs rejected", not _eval(0.1, 1e300).ok and not _eval(0.1, 167.0, 0.0, M.v3(1e300, 0.0, 0.0)).ok)
	var saturated_trim: Dictionary = PARAMS.duplicate()
	saturated_trim.thrust_coefficient_max = 1e-5
	check("saturated trim cannot define local smooth coefficients", not Tail.evaluate(Tail.prepare(saturated_trim).model, 167.0, 0.0, M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0), 0.1).ok)


func _oracle(path: String) -> void:
	var oracle: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check("tail oracle format", oracle is Dictionary and oracle.get("format") == "openrc-tail-rotor-oracle-v1")
	if not oracle is Dictionary or not oracle.has("cases"):
		return
	for row: Dictionary in oracle.cases:
		var parameters: Dictionary = oracle.parameters.duplicate()
		parameters.merge(row.parameter_overrides, true)
		var prepared: Dictionary = Tail.prepare(parameters)
		check("oracle prepares " + row.name, prepared.ok)
		if not prepared.ok:
			continue
		var inputs: Dictionary = row.inputs
		var full: Dictionary = Tail.evaluate(prepared.model, inputs.omega_main_rad_s, inputs.main_induced_velocity_m_s,
			PackedFloat64Array(inputs.cg_air_velocity_body_frd_m_s), PackedFloat64Array(inputs.body_rates_body_frd_rad_s), inputs.tail_collective_rad)
		check("oracle evaluates " + row.name, full.ok)
		if not full.ok:
			continue
		var compact: Dictionary = Tail.evaluate(prepared.model, inputs.omega_main_rad_s, inputs.main_induced_velocity_m_s,
			PackedFloat64Array(inputs.cg_air_velocity_body_frd_m_s), PackedFloat64Array(inputs.body_rates_body_frd_rad_s), inputs.tail_collective_rad, false)
		check("compact payload exact load bytes " + row.name, compact.ok and compact.loads.to_byte_array() == full.loads.to_byte_array())
		for key: String in row.expected:
			check("oracle field exists " + key, full.has(key))
			if not full.has(key):
				continue
			var expected: Variant = row.expected[key]
			if expected == null or typeof(expected) == TYPE_BOOL:
				check("oracle flag " + row.name + " " + key, full[key] == expected)
			elif typeof(expected) == TYPE_ARRAY:
				for index: int in range(expected.size()):
					close("oracle vector " + row.name + " " + key, full[key][index], expected[index], 1e-9)
			else:
				close("oracle scalar " + row.name + " " + key, full[key], expected, 1e-9)
