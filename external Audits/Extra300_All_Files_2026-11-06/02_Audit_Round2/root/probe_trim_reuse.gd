## Isolated audit: full result parity, rejected inputs, and exact work counts.
extends SceneTree

const AD = preload("res://physics/aircraft_data.gd")
const MassInventory = preload("res://physics/mass_inventory.gd")
const WindField = preload("res://physics/wind_field.gd")
const WindConfig = preload("res://physics/wind_config.gd")
const Base = preload("res://physics/trim.gd")
const Candidate = preload("res://physics/audit_trim_candidate.gd")
const CountBase = preload("res://physics/audit_trim_counted_baseline.gd")
const CountCandidate = preload("res://physics/audit_trim_counted_candidate.gd")
const CruiseBase = preload("res://physics/cruise_trim.gd")
const CruiseCandidate = preload("res://physics/audit_cruise_candidate.gd")
const CruiseCountBase = preload("res://physics/audit_cruise_counted_baseline.gd")
const CruiseCountCandidate = preload("res://physics/audit_cruise_counted_candidate.gd")
const EXTRA = "res://data/aircraft/gp_extra_300s_60.json"
const G: float = 9.80665
var checks: int = 0
var failures: int = 0
var rows: Array = []
var work: Array = []

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)

func digest(value: Variant) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes(value))
	return ctx.finish().hex_encode()

func frozen_inventory(source: Dictionary, fill: float) -> Dictionary:
	var model: Dictionary = source.duplicate(true)
	var glow: Dictionary = model.propulsion.glow
	var properties: Dictionary = MassInventory.evaluate_reference(glow.mass_reference,
		PackedFloat64Array([float(glow.capacity_fuel_kg) * fill]))
	check("valid frozen launch inventory", properties.get("ok", false))
	model.mass_kg = properties.mass_kg
	model.inertia = properties.inertia
	model.trim_mass_properties = properties
	return model

func compare(label: String, model: Dictionary, mode: String, speed: float,
		rho: float = 1.225, charge: float = 1.0, initial: PackedFloat64Array = PackedFloat64Array()) -> void:
	var before: PackedByteArray = var_to_bytes(model)
	var a: Dictionary = Base.solve(mode, speed, model, G, model.controls.throw_rad, rho, charge, initial)
	var b: Dictionary = Candidate.solve(mode, speed, model, G, model.controls.throw_rad, rho, charge, initial)
	check(label + " byte-identical complete result", var_to_bytes(a) == var_to_bytes(b))
	check(label + " input model unchanged", var_to_bytes(model) == before)
	rows.append({label = label, ok = a.ok, message = a.message, iterations = a.iterations,
		throttle = a.throttle if is_finite(a.throttle) else null,
		rpm = a.rpm if is_finite(a.rpm) else null,
		result_sha256 = digest(a), exact = var_to_bytes(a) == var_to_bytes(b)})

func compare_cruise(label: String, model: Dictionary, rho: float, charge: float, target: float) -> void:
	var before: PackedByteArray = var_to_bytes(model)
	var speed: float = model.start_speed
	var a: Dictionary = CruiseBase.solve_level_at_throttle(speed, target, 2.5 * speed,
		model, G, model.controls.throw_rad, rho, charge)
	var b: Dictionary = CruiseCandidate.solve_level_at_throttle(speed, target, 2.5 * speed,
		model, G, model.controls.throw_rad, rho, charge)
	check(label + " byte-identical complete cruise result", var_to_bytes(a) == var_to_bytes(b))
	check(label + " input model unchanged", var_to_bytes(model) == before)
	rows.append({label = label, ok = a.ok, message = a.message, iterations = a.iterations,
		search_iterations = a.search_iterations, V = a.V,
		throttle = a.throttle if is_finite(a.throttle) else null,
		rpm = a.rpm if is_finite(a.rpm) else null,
		result_sha256 = digest(a), exact = var_to_bytes(a) == var_to_bytes(b)})

func counted(label: String, model: Dictionary, mode: String, speed: float, cruise: bool = false) -> void:
	CountBase.audit_rpm_calls = 0
	CountBase.audit_result_calls = 0
	CountCandidate.audit_rpm_calls = 0
	CountCandidate.audit_result_calls = 0
	var a: Dictionary
	var b: Dictionary
	if cruise:
		a = CruiseCountBase.solve_level_at_throttle(speed, 0.5, 2.5 * speed, model, G, model.controls.throw_rad)
		b = CruiseCountCandidate.solve_level_at_throttle(speed, 0.5, 2.5 * speed, model, G, model.controls.throw_rad)
	else:
		a = CountBase.solve(mode, speed, model, G, model.controls.throw_rad)
		b = CountCandidate.solve(mode, speed, model, G, model.controls.throw_rad)
	check(label + " counted variants have exact results", var_to_bytes(a) == var_to_bytes(b))
	check(label + " same finalization count", CountBase.audit_result_calls == CountCandidate.audit_result_calls)
	var expected: int = 2 * CountBase.audit_result_calls if mode == "level" else 0
	check(label + " exactly two RPM solves removed per level-glow finalization",
		CountBase.audit_rpm_calls - CountCandidate.audit_rpm_calls == expected)
	work.append({label = label, ok = a.ok, baseline_rpm_solves = CountBase.audit_rpm_calls,
		candidate_rpm_solves = CountCandidate.audit_rpm_calls, finalizations = CountBase.audit_result_calls,
		removed = expected, exact = var_to_bytes(a) == var_to_bytes(b)})

func _initialize() -> void:
	var loaded: Dictionary = AD.load_file(EXTRA)
	check("stock Extra loads", loaded.get("ok", false))
	if not loaded.get("ok", false):
		quit(1)
		return
	var source: Dictionary = loaded.model
	var hot: Variant = WindField.build(WindConfig.preset("hot-high")).field
	var conditions: Array = [{name = "reference", rho = 1.225, charge = 1.0},
		{name = "hot-high", rho = hot.air_density(-30.0), charge = hot.engine_charge_ratio(-30.0)}]
	for fill in [1.0, 0.1]:
		var model: Dictionary = frozen_inventory(source, fill)
		for condition in conditions:
			for speed in [17.0, 22.0, 30.0]:
				compare("Extra fill=%s %s level V=%s" % [fill, condition.name, speed],
					model, "level", speed, condition.rho, condition.charge)
			compare_cruise("Extra fill=%s %s half-power launch" % [fill, condition.name],
				model, condition.rho, condition.charge, 0.5)
		compare("Extra fill=%s stopped-engine glide" % fill, model, "glide", 22.0)
		var excessive_idle: Dictionary = model.duplicate(true)
		excessive_idle.propulsion.glow.throttle_idle_offset = 0.3
		compare("Extra fill=%s excessive-idle refusal" % fill, excessive_idle, "level", 17.0)
	var wet: Dictionary = frozen_inventory(source, 1.0)
	for seed in [0.4, 0.75, 0.95]:
		compare("Extra explicit warm start=%s" % seed, wet, "level", 22.0, 1.225, 1.0,
			PackedFloat64Array([0.05, -0.05, seed, 0.0, 0.0, 0.0]))
	for bad_speed in [0.0, -1.0, NAN, INF]:
		compare("Extra invalid speed=%s" % bad_speed, wet, "level", bad_speed)
	compare("Extra unsupported mode", wet, "hover", 22.0)
	for name in ["jensen_ugly_stik_60", "synthetic_stik_electric_4s", "stik_glow_fs64v_4t"]:
		var other: Dictionary = AD.load_file("res://data/aircraft/" + name + ".json")
		check(name + " guard fixture loads", other.get("ok", false))
		if other.get("ok", false):
			compare(name + " level control", other.model, "level", 15.0)
			compare(name + " glide control", other.model, "glide", 15.0)
	counted("Extra reference level V=22", wet, "level", 22.0)
	counted("Extra half-power cruise", wet, "level", wet.start_speed, true)
	counted("Extra stopped-engine glide", wet, "glide", 22.0)
	var refused: Dictionary = wet.duplicate(true)
	refused.propulsion.glow.throttle_idle_offset = 0.3
	counted("Extra bounded excessive-idle refusal", refused, "level", 17.0)
	var report: Dictionary = {source_commit = "8e5f2f0ba6aacd44efa1c4ac48c4023f181c47bd",
		checks = checks, failures = failures, conditions = conditions, rows = rows, work = work}
	var output: String = OS.get_environment("EXTRA_TRIM_REPORT")
	if output.is_empty():
		printerr("EXTRA_TRIM_REPORT must name a scratch output path")
		quit(2)
		return
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("EXTRA_TRIM_REUSE: %d checks, %d failed; %d complete-result pairs" % [checks, failures, rows.size()])
	print("WORK_COUNTS ", JSON.stringify(work))
	quit(1 if failures else 0)
