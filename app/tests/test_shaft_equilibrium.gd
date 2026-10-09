# G2-R1: bracketed shaft equilibria, finite refusal and downstream trim rejection.
extends SceneTree

const P := preload("res://physics/propulsion.gd")
const AD := preload("res://physics/aircraft_data.gd")
const GroundStart := preload("res://physics/ground_start.gd")
const Trim := preload("res://physics/trim.gd")
var checks := 0
var failures := 0


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)


# Full-throttle engine torque is exactly 1 N m; constant Cp yields an analytic root.
func fixture() -> Dictionary:
	return { diameter = 1.0, cp = PackedFloat64Array([0.0, 0.01, 1.0, 0.01]),
		shaft = { power_curve = PackedFloat64Array([100.0, 100.0 * TAU / 60.0,
			10000.0, 10000.0 * TAU / 60.0]), friction = PackedFloat64Array([0.0, 0.0]),
			idle_power = 0.5, peak_indicated_power = 2000.0 } }


func _initialize() -> void:
	var prop := fixture()
	var before := var_to_bytes(prop)
	for rho in [0.5, 1.0, 2.0]:
		for u in [-20.0, 0.0, 30.0]:
			var rpm := P.steady_rpm(1.0, u, prop, rho)
			check("analytic constant-torque root", absf(rpm - 60.0 * sqrt(TAU / (0.01 * rho))) < 1e-9)
			check("equilibrium torque residual", absf(P.engine_torque(rpm, 1.0, prop) - P.prop_torque(rpm, u, prop, rho)) < 1e-10)
	check("solver does not mutate model", before == var_to_bytes(prop))
	var upper := fixture()
	upper.cp = PackedFloat64Array([0.0, 1e-6, 1.0, 1e-6])
	check("positive torque at both endpoints refused", is_nan(P.steady_rpm(1.0, 0.0, upper, 1.0)))
	var lower := fixture()
	lower.shaft.idle_power = 0.0
	lower.shaft.friction = PackedFloat64Array([0.2, 0.0])
	check("negative torque at both endpoints refused", is_nan(P.steady_rpm(0.0, 0.0, lower, 1.0)))
	for bad in [NAN, INF, -INF]:
		check("nonfinite throttle refused", is_nan(P.steady_rpm(bad, 0.0, prop, 1.0)))
		check("nonfinite inflow refused", is_nan(P.steady_rpm(1.0, bad, prop, 1.0)))
		check("nonfinite density refused", is_nan(P.steady_rpm(1.0, 0.0, prop, bad)))
	check("negative density refused", is_nan(P.steady_rpm(1.0, 0.0, prop, -1.0)))
	var overflow := fixture()
	overflow.shaft.power_curve = PackedFloat64Array([100.0, 100.0, 1e308, 200.0])
	check("overflowing bracket refused", is_nan(P.steady_rpm(1.0, 0.0, overflow, 1.0)))
	overflow = fixture()
	overflow.diameter = 1e70
	check("overflowing torque refused", is_nan(P.steady_rpm(1.0, 0.0, overflow, 1.0)))
	var invalid_bracket := fixture()
	invalid_bracket.shaft.power_curve = PackedFloat64Array([0.1, 1.0, 0.2, 2.0])
	check("reversed RPM bracket refused", is_nan(P.steady_rpm(1.0, 0.0, invalid_bracket, 1.0)))
	# Exact endpoint roots: zero air density and zero source torque make every RPM balanced.
	var endpoint := fixture()
	endpoint.shaft.idle_power = 0.0
	check("exact lower endpoint root accepted", P.steady_rpm(0.0, 0.0, endpoint, 0.0) == P.STOPPED_RPM)
	# A zero brake-power extrapolation at the ceiling gives an exact upper endpoint root in vacuum.
	endpoint.shaft.power_curve = PackedFloat64Array([100.0, 100.0, 1000.0, 1.0])
	check("exact upper endpoint root accepted", P.steady_rpm(1.0, 0.0, endpoint, 0.0) == 1600.0)
	for bad in [NAN, INF, -INF]:
		var poisoned := fixture()
		poisoned.shaft.friction[0] = bad
		check("nonfinite evaluated torque refused", is_nan(P.steady_rpm(1.0, 0.0, poisoned, 1.0)))
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/p51d_mustang_120.json"))
	raw.propulsion.engine.shaft.power_curve.value = [[1000.0, 1000.0], [2000.0, 2000.0]]
	raw.propulsion.engine.shaft.friction_torque.value = [0.0, 0.0]
	raw.propulsion.propeller.cp_table.value = [[0.0, 0.0001], [0.5, 0.0001]]
	var accepted := AD.validate_and_derive(raw)
	check("unbracketed reproducer passes full data loader", accepted.ok)
	var accepted_prop: Dictionary = accepted.model.propulsion
	check("loader-valid unbracketed equilibrium refused", is_nan(P.steady_rpm(1.0, 0.0, accepted_prop, 1.225)))
	raw.propulsion.engine.shaft.power_curve.value = [[1000.0, 1000.0], [1.2e308, 2000.0]]
	accepted = AD.validate_and_derive(raw)
	check("overflow reproducer passes full data loader", accepted.ok)
	check("loader-valid bracket overflow refused", is_nan(P.steady_rpm(1.0, 0.0, accepted.model.propulsion, 1.225)))
	var data := AD.load_file("res://data/aircraft/p51d_mustang_120.json")
	check("P-51 data loads", data.ok)
	var model: Dictionary = data.model
	# Eliminate any root in the supported bracket while retaining the model's normal load path.
	model.propulsion.cp = PackedFloat64Array([0.0, 1e-9, 1.0, 1e-9])
	model.propulsion.cp_min = 0.0
	model.propulsion.shaft.friction = PackedFloat64Array([0.0, 0.0])
	model.propulsion.shaft.power_curve = PackedFloat64Array([100.0, 1e6, 10000.0, 1e6])
	var trimmed := Trim.solve("level", 27.0, model, 9.80665, model.controls.throw_rad)
	check("trim refuses unbalanced shaft", not trimmed.ok and "nonfinite" in trimmed.message)
	var failed_rpm := P.steady_rpm(1.0, 0.0, upper, 1.0)
	var runway := GroundStart.solve(model, PackedFloat64Array(), 0.0, 0.0, 0.0,
		{ elevator = 0.0, aileron_left = 0.0, aileron_right = 0.0, rudder = 0.0 }, 0.0, failed_rpm, 1.225, 9.80665)
	check("runway solver refuses failed RPM before evaluating loads", not runway.ok and runway.message == "runway start needs finite position, heading, controls, rpm, density and gravity")
	print("G2-R1: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
