# HELI-05: independent source/math anchors plus generated Python oracle.
extends SceneTree

const Rotor = preload("res://physics/rotorcraft/main_rotor.gd")
const M = preload("res://physics/math3d.gd")
const PARAMS: Dictionary = {
	"rho_kg_m3": 1.225, "rotor_radius_m": 0.775, "blade_chord_m": 0.058, "rotor_blade_count": 2,
	"blade_lift_curve_slope_per_rad": 5.5, "blade_section_cd0": 0.024, "thrust_coefficient_max": 0.0055,
	"blade_flapping_inertia_kg_m2": 0.038, "gamma_flybar": 0.8, "flapback_k_mu": 0.2,
	"omega_nominal_rad_s": 167.0, "cyclic_longitudinal_gain_nominal_rad_per_rad": 4.2,
	"cyclic_lateral_gain_nominal_rad_per_rad": 4.2, "hub_spring_stiffness_nm_per_rad": 54.0,
	"hub_position_body_frd_m": [0.0, 0.0, -0.235], "rotation_sense": 1,
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


func _evaluate(omega: float = 167.0, vi: float = 4.2, velocity: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0]),
		rates: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0]), collective: float = 0.09624751257538011,
		forward: float = 0.0, right: float = 0.0, a1: float = 0.0, b1: float = 0.0) -> Dictionary:
	return Rotor.evaluate(model, omega, vi, velocity, rates, collective, forward, right, a1, b1)


func _initialize() -> void:
	var prepared: Dictionary = Rotor.prepare(PARAMS)
	check("source fixture prepares", prepared.ok)
	if not prepared.ok:
		quit(1)
		return
	model = prepared.model
	check("prepared context is immutable and flat", model.is_read_only() and not model.has("hub_position_body_frd_m"))
	_anchors()
	_signs_and_loads()
	_invalid()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--oracle="):
			_oracle(argument.substr(9))
	print("HELI-05 main rotor: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _anchors() -> void:
	close("Table 1 blade Lock number", model.lock_number, 3.709795628854648, 1e-12)
	close("bare first-order flap diagnostic", model.bare_flap_time_constant_nominal_s, 0.025825784711, 1e-11)
	var hover: Dictionary = _evaluate()
	check("analytic weight-matched main thrust evaluates", hover.ok)
	close("hover main thrust equals 8.2kg weight at source g9.81", hover.thrust_n, 8.2 * 9.81)
	close("vertical force equals negative thrust in FRD", hover.force_body_frd_n[2], -hover.thrust_n)
	close("flybar effective lag is distinct from bare rotor", hover.effective_flap_time_constant_s, 16.0 / (0.8 * 167.0))
	close("induced plus profile power balance", hover.torque_nm * 167.0,
		hover.thrust_n * 4.2 + 1.225 * PI * 0.775 * 0.775 * 0.775 * (167.0 * 0.775) * (167.0 * 0.775) * (0.024 * model.solidity / 8.0) * 167.0)
	var step: Dictionary = _evaluate(167.0, 4.2, M.v3(0.0, 0.0, 0.0), M.v3(0.2, -0.3, 0.4))
	# Body rate is already rad/s, outside the angle/tau bracket in Eqs. 17/18.
	close("pitch rate lag has correct dimensions", step.flap_rate_a1_rad_s, 0.3)
	close("roll rate lag has correct dimensions", step.flap_rate_b1_rad_s, -0.2)
	var twice: Dictionary = _evaluate(334.0, 4.2, M.v3(0.0, 0.0, 0.0), M.v3(0.2, -0.3, 0.4))
	close("body pitch rate term independent of head speed", twice.flap_rate_a1_rad_s, 0.3)
	var up: Dictionary = _evaluate(167.0, 0.0, M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0), 1.0)
	var down: Dictionary = _evaluate(167.0, 0.0, M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0), -1.0)
	close("source hard positive saturation", up.thrust_coefficient, 0.0055)
	close("source hard negative saturation", down.thrust_coefficient, -0.0055)
	var stopped: Dictionary = _evaluate(0.0, 3.0, M.v3(5.0, 2.0, -1.0), M.v3(0.2, 0.3, 0.4), 0.1, 0.01, 0.02, 0.03, 0.04)
	check("stopped rotor returns finite inactive physical payload", stopped.ok and not stopped.rotor_active and stopped.lambda0 == null)
	check("stopped disc has no aero/spring load or flap response", stopped.loads == PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]) and stopped.flap_rate == PackedFloat64Array([0.0, 0.0]))


func _signs_and_loads() -> void:
	var zero: PackedFloat64Array = M.v3(0.0, 0.0, 0.0)
	var cyclic: Dictionary = _evaluate(167.0, 4.2, zero, zero, 0.1, 0.01, 0.02)
	check("forward/right cyclic give forward/right disc response", cyclic.flap_rate_a1_rad_s < 0.0 and cyclic.flap_rate_b1_rad_s > 0.0)
	var steady: Dictionary = _evaluate(167.0, 4.2, zero, zero, 0.1, 0.01, 0.02, -4.2 * 0.01, 4.2 * 0.02)
	close("steady forward flap target", steady.flap_rate_a1_rad_s, 0.0)
	close("steady right flap target", steady.flap_rate_b1_rad_s, 0.0)
	var tilt: float = 2.0 * PI / 180.0
	var tilted: Dictionary = _evaluate(167.0, 4.2, zero, zero, 0.1, 0.0, 0.0, tilt, tilt)
	close("TPP normal has unit length", M.norm(tilted.thrust_normal_body_frd), 1.0)
	close("thrust magnitude preserved by exact geometric normal", M.norm(tilted.force_body_frd_n), absf(tilted.thrust_n))
	check("aft tilt pitches up; right tilt rolls right", tilted.moment_body_frd_nm[1] > 0.0 and tilted.moment_body_frd_nm[0] > 0.0)
	check("small-angle source hub moment not counted twice",
		absf(tilted.moment_body_frd_nm[1] - (54.0 + tilted.thrust_n * 0.235) * tilt) / absf(tilted.moment_body_frd_nm[1]) < 0.01)
	close("shaft reaction yaw sign", tilted.moment_body_frd_nm[2], -tilted.torque_nm)
	var reversed_params: Dictionary = PARAMS.duplicate(true)
	reversed_params.rotation_sense = -1
	var reversed_model: Dictionary = Rotor.prepare(reversed_params).model
	var reverse_spin: Dictionary = Rotor.evaluate(reversed_model, 167.0, 4.2, zero, zero, 0.1, 0.0, 0.0, tilt, tilt)
	close("reversed spin only reverses torque reaction", reverse_spin.moment_body_frd_nm[2], tilted.torque_nm)
	var positive: Dictionary = _evaluate(167.0, 4.2, zero, zero, 0.1)
	var negative: Dictionary = _evaluate(167.0, -4.2, zero, zero, -0.1)
	close("signed collective/inflow reflects thrust", negative.thrust_n, -positive.thrust_n)
	close("profile drag and induced product retain torque under reflection", negative.torque_nm, positive.torque_nm)
	var lateral: Dictionary = _evaluate(167.0, 4.2, M.v3(0.0, 3.0, 0.0), zero, 0.1)
	check("literal source Eqs17/26 lateral term positive", lateral.flap_rate_b1_rad_s > 0.0)
	var outside: Dictionary = _evaluate(167.0, 4.2, M.v3(25.0, 0.0, 0.0))
	check("algebraic loads beyond identified mu flagged", outside.ok and not outside.within_identified_advance_ratio)
	var copy_params: Dictionary = PARAMS.duplicate(true)
	var copied: Dictionary = Rotor.prepare(copy_params).model
	copy_params.hub_position_body_frd_m[2] = -99.0
	copy_params.blade_section_cd0 = 99.0
	close("prepared arm detached from input edits", copied.hub_z_m, -0.235)
	close("prepared coefficients detached from input edits", copied.blade_section_cd0, 0.024)


func _invalid() -> void:
	for key: String in PARAMS.keys():
		var missing: Dictionary = PARAMS.duplicate(true)
		missing.erase(key)
		check("missing source parameter refused " + key, not Rotor.prepare(missing).ok)
	var extra: Dictionary = PARAMS.duplicate(true)
	extra.unknown = 1.0
	check("unknown parameter refused", not Rotor.prepare(extra).ok)
	for bad: Variant in [NAN, INF, -INF, "1.225", true, -1.0, 0.0]:
		var broken: Dictionary = PARAMS.duplicate(true)
		broken.rho_kg_m3 = bad
		check("invalid source density refused", not Rotor.prepare(broken).ok)
	check("unprepared raw context refused", not Rotor.evaluate(PARAMS, 167.0, 4.2, M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0), 0.1, 0.0, 0.0, 0.0, 0.0).ok)
	var malformed: Dictionary = {"law": Rotor.LAW}
	malformed.make_read_only()
	check("readonly but incomplete context refused safely", not Rotor.evaluate(malformed, 167.0, 4.2, M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0), 0.1, 0.0, 0.0, 0.0, 0.0).ok)
	for replacement: Variant in [NAN, "1.225", Rotor.LAW]:
		var bad_context: Dictionary = model.duplicate()
		bad_context.rho_kg_m3 = replacement
		bad_context.make_read_only()
		check("readonly malformed numeric field refused safely", not Rotor.evaluate(bad_context, 167.0, 4.2, M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0), 0.1, 0.0, 0.0, 0.0, 0.0).ok)
	check("negative rotor speed refused", not _evaluate(-1.0).ok)
	check("invalid physical vector shape refused", not _evaluate(167.0, 4.2, PackedFloat64Array()).ok)
	check("nonfinite state refused", not _evaluate(167.0, NAN).ok)
	check("angles beyond explicit algebraic domain refused", not _evaluate(167.0, 4.2, M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0), PI).ok)
	check("singular flapback domain refused", not _evaluate(167.0, 4.2, M.v3(200.0, 0.0, 0.0)).ok)


func _oracle(path: String) -> void:
	var json: JSON = JSON.new()
	check("main rotor oracle parses", json.parse(FileAccess.get_file_as_string(path)) == OK)
	if typeof(json.data) != TYPE_DICTIONARY:
		check("main rotor oracle object", false)
		return
	check("main rotor oracle format", json.data.get("format") == "openrc-main-rotor-oracle-v1")
	var prepared: Dictionary = Rotor.prepare(json.data.parameters)
	check("independent source profile prepares", prepared.ok)
	if not prepared.ok:
		return
	for row: Dictionary in json.data.cases:
		var inputs: Dictionary = row.inputs
		var result: Dictionary = Rotor.evaluate(prepared.model, inputs.omega_rad_s, inputs.induced_velocity_m_s,
			PackedFloat64Array(inputs.hub_velocity_relative_to_air_body_frd_m_s), PackedFloat64Array(inputs.body_rates_body_frd_rad_s),
			inputs.collective_pitch_75_rad, inputs.cyclic_forward_rad, inputs.cyclic_right_rad, inputs.a1_rad, inputs.b1_rad)
		check("independent main-rotor oracle valid " + row.name, result.ok)
		if not result.ok:
			continue
		var compact: Dictionary = Rotor.evaluate(prepared.model, inputs.omega_rad_s, inputs.induced_velocity_m_s,
			PackedFloat64Array(inputs.hub_velocity_relative_to_air_body_frd_m_s), PackedFloat64Array(inputs.body_rates_body_frd_rad_s),
			inputs.collective_pitch_75_rad, inputs.cyclic_forward_rad, inputs.cyclic_right_rad, inputs.a1_rad, inputs.b1_rad, false)
		check("compact oracle payload valid " + row.name, compact.ok)
		if compact.ok:
			check("compact loads preserve exact bytes " + row.name, compact.loads.to_byte_array() == result.loads.to_byte_array())
			check("compact flap rates preserve exact bytes " + row.name, compact.flap_rate.to_byte_array() == result.flap_rate.to_byte_array())
		for key: String in row.expected:
			# Input-kind/value tags belong to the Python ratio compatibility path;
			# production kernel accepts only dimensional induced velocity.
			if key == "inflow_input_kind" or key == "inflow_input_value":
				continue
			check("oracle field exists " + key, result.has(key))
			if not result.has(key):
				continue
			var expected: Variant = row.expected[key]
			if expected == null or typeof(expected) == TYPE_BOOL:
				check("oracle metadata " + row.name + " " + key, result[key] == expected)
			elif typeof(expected) == TYPE_ARRAY:
				for i: int in range(expected.size()):
					close("oracle vector " + row.name + " " + key, result[key][i], expected[i], 1e-9)
			else:
				close("oracle scalar " + row.name + " " + key, result[key], expected, 1e-9)
