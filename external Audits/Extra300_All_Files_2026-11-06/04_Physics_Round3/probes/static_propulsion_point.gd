extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const OP := preload("res://physics/glow/operating_point.gd")
const Prop := preload("res://physics/glow/propeller.gd")
var checks := 0
var failures := 0

func check(label: String, condition: bool) -> bool:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label)
	return condition

func _initialize() -> void:
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): path = arg.substr(6)
	if path.is_empty():
		quit(2)
		return
	var loaded: Dictionary = AD.load_file("res://data/aircraft/gp_extra_300s_60.json")
	if not check("stock Extra loads", loaded.get("ok", false)):
		quit(1)
		return
	var prop: Dictionary = loaded.model.propulsion
	var solved: Dictionary = OP.solve(prop, 1.0, 0.0, 1.225, 1.225)
	if not check("restoring root found", solved.get("ok", false)):
		quit(1)
		return
	var rpm: float = solved.rpm
	var residual: float = OP.residual(prop, rpm, 1.0, 0.0, 1.225, 1.225)
	check("shaft balance", absf(residual) <= 1e-10)
	check("restoring root", OP.residual(prop, rpm - 0.001, 1.0, 0.0, 1.225, 1.225) > 0.0 and OP.residual(prop, rpm + 0.001, 1.0, 0.0, 1.225, 1.225) < 0.0)
	var points: Array = []
	for speed in [rpm, 9900.0, 11750.0, 13000.0]:
		var engine: Dictionary = OP.source(prop, speed, 1.0, 1.225)
		var load: Dictionary = Prop.evaluate(speed, 0.0, 1.225, prop.glow.propeller)
		check("finite point " + str(speed), engine.get("ok", false) and load.get("ok", false) and is_finite(engine.get("shaft_torque_nm", NAN)) and is_finite(load.get("torque_nm", NAN)))
		points.append({rpm = speed, engine_shaft_torque_nm = engine.shaft_torque_nm,
			engine_power_w = engine.brake_power_w, propeller_torque_nm = load.torque_nm,
			propeller_thrust_n = load.thrust_n, residual_nm = engine.shaft_torque_nm - load.torque_nm})
	var report := {source_commit = "2e2e3492e67d30635cc4e727025581e2848cdf2e", checks = checks, failures = failures,
		engine = Engine.get_version_info().string, interpretation = "Algebraic nominal-mixture fully-firing shaft balance; not an integrated thermal/fuel equilibrium or matched physical bench experiment.",
		inputs = {throttle = 1.0, axial_inflow_mps = 0.0, total_density_kg_m3 = 1.225, dry_density_kg_m3 = 1.225},
		roots_rpm = Array(solved.roots), selected_rpm = rpm, root_residual_nm = residual, points = points}
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t", true, true))
	file.close()
	print("STATIC_EXTRA_POINT_COMPLETE checks=", checks, " failures=", failures, " rpm=", rpm)
	quit(1 if failures else 0)
