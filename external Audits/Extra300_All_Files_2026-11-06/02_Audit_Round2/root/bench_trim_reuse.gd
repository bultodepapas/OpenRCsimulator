## Uninstrumented paired CPU benchmark. Run with other audit jobs paused.
extends SceneTree
const AD = preload("res://physics/aircraft_data.gd")
const MI = preload("res://physics/mass_inventory.gd")
const Base = preload("res://physics/trim.gd")
const Candidate = preload("res://physics/audit_trim_candidate.gd")
const CruiseBase = preload("res://physics/cruise_trim.gd")
const CruiseCandidate = preload("res://physics/audit_cruise_candidate.gd")
const G: float = 9.80665
const PAIRS: int = 24
const WARMUP_PAIRS: int = 2
var failures: int = 0

func run_one(candidate: bool, kind: String, model: Dictionary) -> Dictionary:
	var result: Dictionary
	var begin: int = Time.get_ticks_usec()
	if kind == "level_22":
		result = Candidate.solve("level", 22.0, model, G, model.controls.throw_rad) if candidate \
			else Base.solve("level", 22.0, model, G, model.controls.throw_rad)
	else:
		var speed: float = model.start_speed
		result = CruiseCandidate.solve_level_at_throttle(speed, 0.5, 2.5 * speed, model, G, model.controls.throw_rad) if candidate \
			else CruiseBase.solve_level_at_throttle(speed, 0.5, 2.5 * speed, model, G, model.controls.throw_rad)
	var elapsed: int = Time.get_ticks_usec() - begin
	return {elapsed_us = elapsed, result = result}

func _initialize() -> void:
	var loaded: Dictionary = AD.load_file("res://data/aircraft/gp_extra_300s_60.json")
	if not loaded.get("ok", false):
		printerr("Extra load failed")
		quit(1)
		return
	var model: Dictionary = loaded.model.duplicate(true)
	var properties: Dictionary = MI.evaluate_reference(model.propulsion.glow.mass_reference,
		PackedFloat64Array([float(model.propulsion.glow.capacity_fuel_kg)]))
	model.mass_kg = properties.mass_kg
	model.inertia = properties.inertia
	model.trim_mass_properties = properties
	var rows: Array = []
	for kind in ["level_22", "half_power_cruise"]:
		for index in range(-WARMUP_PAIRS, PAIRS):
			var a: Dictionary
			var b: Dictionary
			var order: String = "AB" if index % 2 == 0 else "BA"
			if order == "AB":
				a = run_one(false, kind, model)
				b = run_one(true, kind, model)
			else:
				b = run_one(true, kind, model)
				a = run_one(false, kind, model)
			var exact: bool = var_to_bytes(a.result) == var_to_bytes(b.result)
			if not exact or not a.result.ok or not b.result.ok:
				failures += 1
				printerr("FAIL benchmark result ", kind, " ", index)
			if index >= 0:
				rows.append({kind = kind, pair = index, order = order,
					baseline_us = a.elapsed_us, candidate_us = b.elapsed_us, exact = exact})
	var report := {source_commit = "8e5f2f0ba6aacd44efa1c4ac48c4023f181c47bd",
		engine = Engine.get_version_info(), platform = OS.get_name(), cpu = OS.get_processor_name(),
		precision = "GDScript float64", renderer = "headless", rho_kg_m3 = 1.225,
		charge_ratio = 1.0, fuel_fill = 1.0, pairs_per_case = PAIRS,
		warmup_pairs_per_case = WARMUP_PAIRS, failures = failures, rows = rows,
		limits = "Warm solver CPU only, no launch cache, import, full UI, native backend, frame or GPU timing."}
	var output: String = OS.get_environment("EXTRA_TRIM_BENCH_REPORT")
	if output.is_empty():
		printerr("EXTRA_TRIM_BENCH_REPORT is required")
		quit(2)
		return
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("EXTRA_TRIM_BENCH: %d pairs, %d failed" % [rows.size(), failures])
	quit(1 if failures else 0)
