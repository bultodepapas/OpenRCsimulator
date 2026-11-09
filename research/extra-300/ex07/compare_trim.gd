## E300-07: compare one historical Trim owner with current dependencies and optional warm paired timing.
## --baseline=<old trim.gd> --out=<new JSON path> [--timing-pairs=12]
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Mass := preload("res://physics/mass_inventory.gd")
const Wind := preload("res://physics/wind_field.gd")
const Config := preload("res://physics/wind_config.gd")
const G := 9.80665
var baseline_path := ""
var output_path := ""
var timing_pairs := 0
var failures := 0
var rows: Array = []


func variant(source: String, instrument: bool) -> GDScript:
	var script := GDScript.new()
	if instrument:
		source = source.replace("extends RefCounted", "extends RefCounted\nstatic var rpm_calls := 0")
		var marker := "\n\treturn Propulsion.steady_rpm(throttle, u, model.propulsion, rho, engine_charge_ratio)"
		if source.count(marker) != 1:
			printerr("expected exactly one steady-RPM instrumentation site")
			quit(1)
			return null
		source = source.replace(marker, "\n\trpm_calls += 1" + marker)
	script.source_code = source
	var error := script.reload()
	if error != OK:
		printerr("cannot compile Trim variant: ", error)
		quit(1)
		return null
	return script


func compare_case(label: String, baseline: GDScript, candidate: GDScript, model: Dictionary,
		mode := "level", speed := 22.0, rho := 1.225, charge := 1.0,
		initial := PackedFloat64Array(), throws_override := {}) -> Dictionary:
	var before := var_to_bytes(model)
	var throws: Dictionary = model.controls.throw_rad if throws_override.is_empty() else throws_override
	baseline.rpm_calls = 0
	candidate.rpm_calls = 0
	var old: Dictionary = baseline.solve(mode, speed, model, G, throws, rho, charge, initial)
	var new: Dictionary = candidate.solve(mode, speed, model, G, throws, rho, charge, initial)
	var equal: bool = var_to_bytes(old) == var_to_bytes(new)
	var unchanged: bool = before == var_to_bytes(model)
	if not equal or not unchanged:
		failures += 1
		printerr("FAIL ", label)
	rows.append({"case":label, "equal_bytes":equal, "model_unchanged":unchanged,
		"accepted":new.ok, "message":new.message, "iterations":new.iterations,
		"old_rpm_calls":baseline.rpm_calls, "new_rpm_calls":candidate.rpm_calls,
		"model_sha256":sha(before), "result_sha256":sha(var_to_bytes(new))})
	return new


func sha(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--baseline="):
			baseline_path = arg.trim_prefix("--baseline=")
		elif arg.begins_with("--out="):
			output_path = arg.trim_prefix("--out=")
		elif arg.begins_with("--timing-pairs="):
			var value := arg.trim_prefix("--timing-pairs=")
			if not value.is_valid_int():
				printerr("timing-pairs must be an integer")
				quit(1)
				return
			timing_pairs = int(value)
		else:
			printerr("unknown option: ", arg)
			quit(1)
			return
	baseline_path = ProjectSettings.localize_path(baseline_path.replace("\\", "/"))
	if not baseline_path.begins_with("res://") or not FileAccess.file_exists(baseline_path) or output_path.is_empty() or FileAccess.file_exists(output_path) or FileAccess.file_exists(output_path + ".partial") or timing_pairs < 0 or timing_pairs > 100:
		printerr("provide an existing project-local --baseline, a new --out and 0..100 timing pairs")
		quit(1)
		return
	var old_source := FileAccess.get_file_as_string(baseline_path)
	var new_source := FileAccess.get_file_as_string("res://physics/trim.gd")
	var old := variant(old_source, true)
	var new := variant(new_source, true)
	if old == null or new == null:
		return
	var extra: Dictionary = AD.load_file("res://data/aircraft/gp_extra_300s_60.json").model
	var hot: Variant = Wind.build(Config.preset("hot-high")).field
	for fill in [1.0, 0.1]:
		var model: Dictionary = extra.duplicate(true)
		var glow: Dictionary = model.propulsion.glow
		var properties: Dictionary = Mass.evaluate_reference(glow.mass_reference,
			PackedFloat64Array([float(glow.capacity_fuel_kg) * fill]))
		model.mass_kg = properties.mass_kg
		model.inertia = properties.inertia
		model.trim_mass_properties = properties
		for weather in ["reference", "hot-high"]:
			var rho: float = 1.225 if weather == "reference" else hot.air_density(-30.0)
			var charge: float = 1.0 if weather == "reference" else hot.engine_charge_ratio(-30.0)
			for speed in [17.0, 22.0, 30.0]:
				var label := "%s-fuel-%s-speed-%s" % [weather,fill,speed]
				var result := compare_case(label, old, new, model, "level", speed, rho, charge)
				if result.ok:
					var x := PackedFloat64Array([result.alpha,result.elevator,result.throttle,
						result.beta,result.aileron,result.rudder])
					compare_case(label + "-warm", old, new, model, "level", speed, rho, charge, x)
		compare_case("glide-fuel-%s" % fill, old, new, model, "glide")
	var stalled: Dictionary = extra.duplicate(true)
	stalled.propulsion.glow.throttle_idle_offset = 0.3
	compare_case("stalled", old, new, stalled, "level", 17.0)
	var limits: Dictionary = extra.controls.throw_rad.duplicate()
	limits.elevator = 1e-6
	compare_case("throw-limit", old, new, extra, "level", 22.0, 1.225, 1.0, PackedFloat64Array(), limits)
	compare_case("slow-refusal", old, new, extra, "level", 2.0)
	compare_case("invalid-mode", old, new, extra, "hover")
	compare_case("invalid-speed", old, new, extra, "level", NAN)
	var legacy: Dictionary = AD.load_file("res://data/aircraft/jensen_ugly_stik_60.json").model
	compare_case("legacy-level", old, new, legacy, "level", 15.0)
	compare_case("legacy-glide", old, new, legacy, "glide", 15.0)
	for path in ["res://data/aircraft/battery/turbo_lumber_evolution_4s_pack.json",
			"res://data/aircraft/stik_glow_fs64v_4t.json"]:
		var model: Dictionary = AD.load_file(path).model
		compare_case(path.get_file() + "-level", old, new, model, "level", float(model.start_speed))
		compare_case(path.get_file() + "-glide", old, new, model, "glide", float(model.start_speed))
	# A higher-level consumer uses the original cruise algorithm with each Trim owner.
	var cruise_source := FileAccess.get_file_as_string("res://physics/cruise_trim.gd").replace("class_name CruiseTrim", "")
	var old_cruise := GDScript.new()
	old_cruise.source_code = cruise_source.replace("res://physics/trim.gd", baseline_path)
	var old_cruise_error := old_cruise.reload()
	var new_cruise := GDScript.new()
	new_cruise.source_code = cruise_source
	var new_cruise_error := new_cruise.reload()
	if old_cruise_error != OK or new_cruise_error != OK:
		printerr("cannot compile cruise variants: ", old_cruise_error, ", ", new_cruise_error)
		quit(1)
		return
	var old_result: Dictionary = old_cruise.solve_level_at_throttle(22.0, 0.5, 60.0, extra, G, extra.controls.throw_rad)
	var new_result: Dictionary = new_cruise.solve_level_at_throttle(22.0, 0.5, 60.0, extra, G, extra.controls.throw_rad)
	var cruise_equal := var_to_bytes(old_result) == var_to_bytes(new_result)
	if not cruise_equal:
		failures += 1
	rows.append({"case":"Extra-half-power-cruise", "equal_bytes":cruise_equal,
		"accepted":new_result.ok, "result_sha256":sha(var_to_bytes(new_result))})
	var timings: Array = []
	if timing_pairs > 0:
		var old_plain := variant(old_source, false)
		var new_plain := variant(new_source, false)
		if old_plain == null or new_plain == null:
			return
		for workload in ["level", "cruise"]:
			var owners: Array = [old_plain, new_plain] if workload == "level" else [old_cruise, new_cruise]
			for pair in range(-2, timing_pairs):
				var times := [0, 0]
				var results: Array = [{}, {}]
				for index in ([0, 1] if pair % 2 == 0 else [1, 0]):
					var start := Time.get_ticks_usec()
					results[index] = owners[index].solve("level", 22.0, extra, G, extra.controls.throw_rad) if workload == "level" else owners[index].solve_level_at_throttle(22.0, 0.5, 60.0, extra, G, extra.controls.throw_rad)
					times[index] = Time.get_ticks_usec() - start
				var equal := var_to_bytes(results[0]) == var_to_bytes(results[1])
				if not equal:
					failures += 1
				if pair >= 0:
					timings.append({"workload":workload, "pair":pair, "first":0 if pair % 2 == 0 else 1,
						"baseline_usec":times[0], "candidate_usec":times[1], "equal_bytes":equal})
	var report := {"engine":Engine.get_version_info(), "baseline_sha256":sha(old_source.to_utf8_buffer()),
		"candidate_sha256":sha(new_source.to_utf8_buffer()), "cases":rows,
		"timings":timings, "timing_scope":"warm uncached solver only; two warmup pairs per workload; host contention is not controlled by this tool",
		"cruise_source_sha256":sha(cruise_source.to_utf8_buffer()), "failures":failures, "complete":true}
	var partial_path := output_path + ".partial"
	var file := FileAccess.open(partial_path, FileAccess.WRITE)
	if file == null:
		printerr("cannot write output: ", FileAccess.get_open_error())
		quit(1)
		return
	var stored := file.store_string(JSON.stringify(report, "\t") + "\n")
	file.flush()
	var write_error := file.get_error()
	file.close()
	if not stored or write_error != OK:
		printerr("cannot finish output: ", write_error)
		quit(1)
		return
	if FileAccess.file_exists(output_path) or DirAccess.rename_absolute(ProjectSettings.globalize_path(partial_path), ProjectSettings.globalize_path(output_path)) != OK:
		printerr("cannot publish output; partial receipt retained")
		quit(1)
		return
	print("E300-07 comparison: %d cases, %d failed" % [rows.size(), failures])
	quit(1 if failures else 0)
