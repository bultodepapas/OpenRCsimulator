# HELI-06b: source-form magnitudes, corrected signs and independent work tests.
extends SceneTree

const Airframe = preload("res://physics/rotorcraft/airframe.gd")
const M = preload("res://physics/math3d.gd")
const PARAMS: Dictionary = {
	"rho_kg_m3": 1.225, "fuselage_drag_area_body_m2": [0.1, 0.22, 0.15], "fuselage_cp_body_frd_m": [0.0, 0.0, 0.0],
	"vertical_fin_area_m2": 0.012, "vertical_fin_lift_curve_slope_per_rad": 2.0, "vertical_fin_cp_body_frd_m": [-0.91, 0.0, -0.08],
	"horizontal_tail_area_m2": 0.01, "horizontal_tail_lift_curve_slope_per_rad": 3.0, "horizontal_tail_cp_body_frd_m": [-0.71, 0.0, 0.0],
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


func _eval(air: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0]),
		rates: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0]),
		fus_wake: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0]),
		fin_wake: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0]),
		tail_wake: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])) -> Dictionary:
	return Airframe.evaluate(model, air, rates, fus_wake, fin_wake, tail_wake)


func _initialize() -> void:
	var prepared: Dictionary = Airframe.prepare(PARAMS)
	check("explicit fixture prepares", prepared.ok)
	if not prepared.ok:
		quit(1)
		return
	model = prepared.model
	check("flat read-only context", model.is_read_only() and model.size() == 18)
	_anchors()
	_work_and_signs()
	_invalid()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--oracle="):
			_oracle(argument.substr(9))
	print("HELI-06b airframe: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _anchors() -> void:
	var parameters: Dictionary = PARAMS.duplicate(true)
	parameters.rho_kg_m3 = 2.0
	var original: Dictionary = model
	model = Airframe.prepare(parameters).model
	var rest: Dictionary = _eval()
	check("no air or wake gives exact zero loads", rest.ok and rest.loads == PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]))
	var drag: Dictionary = _eval(M.v3(3.0, 4.0, 0.0))
	close("norm-coupled fuselage drag X", drag.fuselage_loads[0], -1.5)
	close("norm-coupled fuselage drag Y", drag.fuselage_loads[1], -4.4)
	var flow: Dictionary = _eval(M.v3(10.0, 1.0, 1.0))
	close("fin source-form ideal magnitude", flow.vertical_fin_force_ideal_n, -0.012 * (2.0 * M.sqrt_(101.0) + 1.0))
	close("horizontal source-form magnitude with passive sign", flow.horizontal_tail_force_n, -0.31)
	var cap: Dictionary = _eval(M.v3(10.0, 10.0, 10.0))
	check("both normal-force caps engage", cap.vertical_fin_limited and cap.horizontal_tail_limited)
	close("fin cap includes all three local flow components", cap.vertical_fin_force_n, -0.012 * 300.0)
	close("horizontal cap retains source longitudinal/vertical plane", cap.horizontal_tail_force_n, -0.01 * 200.0)
	var reverse: Dictionary = _eval(M.v3(-10.0, -1.0, -1.0))
	close("rearward flow horizontal sign remains passive", reverse.horizontal_tail_force_n, 0.31)
	close("flow reflection fin force", reverse.vertical_fin_force_n, -flow.vertical_fin_force_n)
	var pure_side: Dictionary = _eval(M.v3(0.0, 3.0, 0.0))
	close("horizontal tail ignores lateral-only flow in this law", pure_side.horizontal_tail_force_n, 0.0)
	var yaw: Dictionary = _eval(M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.3))
	close("finite fin lateral point velocity at pure yaw", yaw.vertical_fin_relative_air_m_s[1], -0.91 * 0.3)
	check("positive yaw creates negative yaw moment", yaw.vertical_fin_loads[5] < 0.0)
	var pitch: Dictionary = _eval(M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.3, 0.0))
	close("finite tail vertical point velocity at pure pitch", pitch.horizontal_tail_relative_air_m_s[2], 0.71 * 0.3)
	check("positive pitch creates negative pitch moment", pitch.horizontal_tail_loads[4] < 0.0)
	model = original
	var hover_wake: Dictionary = _eval(M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 4.2))
	close("downward rotor air produces downward fuselage download", hover_wake.fuselage_loads[2], 0.5 * 1.225 * 0.15 * 4.2 * 4.2)
	close("stationary body has no mechanical air work", hover_wake.body_air_power_w, 0.0)
	check("wake energy is dissipated relative to moving air", hover_wake.relative_power_w < 0.0 and hover_wake.wake_power_w > 0.0)
	var moving_wake: Dictionary = _eval(M.v3(0.0, 0.0, 1.0), M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 3.0))
	check("moving air may do positive work on body", moving_wake.fuselage_body_air_power_w > 0.0)
	close("local mechanical work split", moving_wake.body_air_power_w, moving_wake.relative_power_w + moving_wake.wake_power_w)


func _work_and_signs() -> void:
	var parameters: Dictionary = PARAMS.duplicate(true)
	parameters.fuselage_cp_body_frd_m = [0.5, -0.4, 0.3]
	parameters.vertical_fin_cp_body_frd_m = [-0.8, 0.2, -0.1]
	parameters.horizontal_tail_cp_body_frd_m = [-0.7, -0.15, -0.2]
	var shifted: Dictionary = Airframe.prepare(parameters).model
	var index: int = 0
	for x: float in [-12.0, -1.0, 0.0, 3.0, 17.0]:
		for y: float in [-5.0, 0.0, 4.0]:
			for z: float in [-8.0, 0.0, 6.0]:
				index += 1
				var air: PackedFloat64Array = M.v3(x, y, z)
				var rates: PackedFloat64Array = M.v3(0.3, -0.4, 0.6)
				var fus_wake: PackedFloat64Array = M.v3(0.5, -0.25, 3.0)
				var fin_wake: PackedFloat64Array = M.v3(-0.2, 1.1, 2.0)
				var tail_wake: PackedFloat64Array = M.v3(0.1, 0.4, -1.0)
				var full: Dictionary = Airframe.evaluate(shifted, air, rates, fus_wake, fin_wake, tail_wake)
				check("offset/wake sample valid " + str(index), full.ok)
				if not full.ok:
					continue
				var compact: Dictionary = Airframe.evaluate(shifted, air, rates, fus_wake, fin_wake, tail_wake, false)
				check("compact physical load bytes " + str(index), compact.ok and full.loads.to_byte_array() == compact.loads.to_byte_array())
				check("all local relative powers dissipate " + str(index), full.fuselage_relative_power_w <= 0.0 and full.vertical_fin_relative_power_w <= 0.0 and full.horizontal_tail_relative_power_w <= 0.0)
				close("sum work closure " + str(index), full.body_air_power_w, full.relative_power_w + full.wake_power_w)
				close("compact relative work " + str(index), compact.relative_power_w, full.relative_power_w)
				var cg_work: float = full.loads[0] * x + full.loads[1] * y + full.loads[2] * z
				var rotational_work: float = full.loads[3] * rates[0] + full.loads[4] * rates[1] + full.loads[5] * rates[2]
				close("point-force vs CG-wrench work " + str(index), full.body_air_power_w, cg_work + rotational_work)
				for prefix: String in ["fuselage", "vertical_fin", "horizontal_tail"]:
					var force: PackedFloat64Array = full[prefix + "_force_body_frd_n"]
					var arm: PackedFloat64Array = PackedFloat64Array(parameters[prefix + "_cp_body_frd_m"])
					var expected_moment: PackedFloat64Array = M.cross(arm, force)
					var actual: PackedFloat64Array = full[prefix + "_moment_body_frd_nm"]
					for i: int in range(3):
						close("single offset moment " + prefix + " " + str(index), actual[i], expected_moment[i])
	var symmetric: Dictionary = _eval(M.v3(2.0, -3.0, 1.0), M.v3(0.2, -0.4, 0.6))
	var reflected: Dictionary = _eval(M.v3(-2.0, 3.0, -1.0), M.v3(-0.2, 0.4, -0.6))
	for i: int in range(6):
		close("velocity/rate reflection loads " + str(i), reflected.loads[i], -symmetric.loads[i])
	close("reflection dissipates equal energy", reflected.relative_power_w, symmetric.relative_power_w)
	var tiny: Dictionary = _eval(M.v3(1e-100, -1e-100, 1e-100))
	check("zero-speed limit remains finite", tiny.ok and tiny.relative_power_w <= 0.0)


func _invalid() -> void:
	for key: String in PARAMS:
		var missing: Dictionary = PARAMS.duplicate(true)
		missing.erase(key)
		check("missing config " + key, not Airframe.prepare(missing).ok)
	var extra: Dictionary = PARAMS.duplicate(true)
	extra.extra = 1.0
	check("extra config refused", not Airframe.prepare(extra).ok)
	for key: String in ["rho_kg_m3", "vertical_fin_area_m2", "vertical_fin_lift_curve_slope_per_rad", "horizontal_tail_area_m2", "horizontal_tail_lift_curve_slope_per_rad"]:
		for value: Variant in [true, "wrong", NAN, INF, -1.0]:
			var invalid: Dictionary = PARAMS.duplicate(true)
			invalid[key] = value
			check("bad scalar config " + key, not Airframe.prepare(invalid).ok)
	for key: String in ["fuselage_drag_area_body_m2", "fuselage_cp_body_frd_m", "vertical_fin_cp_body_frd_m", "horizontal_tail_cp_body_frd_m"]:
		for value: Variant in [[1.0], [0.0, INF, 0.0], [0.0, true, 0.0], "wrong"]:
			var invalid: Dictionary = PARAMS.duplicate(true)
			invalid[key] = value
			check("bad vector config " + key, not Airframe.prepare(invalid).ok)
	var negative_area: Dictionary = PARAMS.duplicate(true)
	negative_area.fuselage_drag_area_body_m2 = [0.1, -0.2, 0.1]
	check("negative area refused", not Airframe.prepare(negative_area).ok)
	var no_density: Dictionary = PARAMS.duplicate(true)
	no_density.rho_kg_m3 = 0.0
	check("zero density refused", not Airframe.prepare(no_density).ok)
	var detached: Dictionary = PARAMS.duplicate(true)
	var copy: Dictionary = Airframe.prepare(detached).model
	detached.fuselage_cp_body_frd_m[0] = 9.0
	detached.fuselage_drag_area_body_m2[0] = 9.0
	close("arm input detached", copy.fuselage_x_m, 0.0)
	close("area input detached", copy.fuselage_area_x_m2, 0.1)
	var zeros: PackedFloat64Array = M.v3(0.0, 0.0, 0.0)
	check("mutable context refused", not Airframe.evaluate(model.duplicate(), zeros, zeros, zeros, zeros, zeros).ok)
	check("malformed input refused", not _eval(PackedFloat64Array([0.0])).ok)
	check("nonfinite wake refused", not _eval(zeros, zeros, M.v3(0.0, NAN, 0.0)).ok)
	check("nonfinite rates refused", not _eval(zeros, M.v3(0.0, INF, 0.0)).ok)
	check("overflow flow refused", not _eval(M.v3(1e300, 0.0, 0.0)).ok)
	check("overflow wake refused", not _eval(zeros, zeros, M.v3(0.0, 0.0, 1e300)).ok)
	var overflow_arm: Dictionary = PARAMS.duplicate(true)
	overflow_arm.vertical_fin_cp_body_frd_m = [1e300, 0.0, 0.0]
	var large_arm_model: Dictionary = Airframe.prepare(overflow_arm).model
	check("overflow point-velocity product refused", not Airframe.evaluate(large_arm_model, zeros, M.v3(0.0, 1e300, 0.0), zeros, zeros, zeros).ok)
	var disabled: Dictionary = PARAMS.duplicate(true)
	disabled.fuselage_drag_area_body_m2 = [0.0, 0.0, 0.0]
	disabled.vertical_fin_area_m2 = 0.0
	disabled.horizontal_tail_area_m2 = 0.0
	var zero_model: Dictionary = Airframe.prepare(disabled).model
	var zero_loads: Dictionary = Airframe.evaluate(zero_model, M.v3(3.0, 2.0, 1.0), zeros, zeros, zeros, zeros)
	check("zero-area modules produce zero loads", zero_loads.ok and zero_loads.loads == PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]))


func _oracle(path: String) -> void:
	var oracle: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check("airframe oracle format", oracle is Dictionary and oracle.get("format") == "openrc-airframe-oracle-v1")
	if not oracle is Dictionary or not oracle.has("cases"):
		return
	for row: Dictionary in oracle.cases:
		var parameters: Dictionary = row.get("parameters", oracle.get("parameters", {})).duplicate(true)
		parameters.merge(row.get("parameter_overrides", {}), true)
		var prepared: Dictionary = Airframe.prepare(parameters)
		check("oracle prepares " + row.name, prepared.ok)
		if not prepared.ok:
			continue
		var inputs: Dictionary = row.inputs
		var full: Dictionary = Airframe.evaluate(prepared.model,
			PackedFloat64Array(inputs.cg_air_velocity_body_frd_m_s), PackedFloat64Array(inputs.body_rates_body_frd_rad_s),
			PackedFloat64Array(inputs.fuselage_wake_velocity_body_frd_m_s), PackedFloat64Array(inputs.vertical_fin_wake_velocity_body_frd_m_s),
			PackedFloat64Array(inputs.horizontal_tail_wake_velocity_body_frd_m_s))
		check("oracle evaluates " + row.name, full.ok)
		if not full.ok:
			continue
		check("full output schema matches independent oracle " + row.name, full.size() == row.expected.size() + 1)
		for key: String in row.expected:
			check("oracle field " + key, full.has(key))
			if not full.has(key):
				continue
			var expected: Variant = row.expected[key]
			if expected is Array:
				for i: int in range(expected.size()):
					close("oracle vector " + row.name + " " + key, full[key][i], expected[i], 1e-9)
			elif typeof(expected) == TYPE_BOOL:
				check("oracle flag " + row.name + " " + key, full[key] == expected)
			else:
				close("oracle scalar " + row.name + " " + key, full[key], expected, 1e-9)
