## NITRO-04: uncached cruise-trim timing and complete serialized-result parity.
extends SceneTree
const AD := preload("res://physics/aircraft_data.gd")
const Cruise := preload("res://physics/cruise_trim.gd")
const CASES := ["stik_glow_61fx_2t", "stik_glow_55ax_2t", "stik_glow_fs64v_4t",
	"stik_glow_55ax_2t_apc_13x6", "stik_glow_fs64v_4t_apc_13x6", "gp_extra_300s_60"]

func _initialize() -> void:
	var output := ""
	var reference := ""
	var max_ratio := INF
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
		if arg.begins_with("--reference="): reference = arg.trim_prefix("--reference=")
		if arg.begins_with("--max-ratio="): max_ratio = arg.trim_prefix("--max-ratio=").to_float()
	if output.is_empty() or FileAccess.file_exists(output):
		printerr("Provide --out=<new report.json> [--reference=<baseline.json>] [--max-ratio=0.75]")
		quit(1)
		return
	var baseline: Dictionary = {}
	if not reference.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(reference))
		if not parsed is Dictionary:
			printerr("Invalid baseline report")
			quit(1)
			return
		baseline = parsed
	var report := {engine = Engine.get_version_info().string, os = OS.get_name(),
		cpu = OS.get_processor_name(), reference_speed_mps = 15.0, target_throttle = 0.5,
		max_speed_mps = 40.0, cases = {}}
	var failed := false
	for id: String in CASES:
		var loaded: Dictionary = AD.load_file("res://data/aircraft/" + id + ".json")
		if not loaded.ok:
			failed = true
			continue
		var begin := Time.get_ticks_usec()
		var result: Dictionary = Cruise.solve_level_at_throttle(15.0, 0.5, 40.0, loaded.model,
			9.80665, {elevator = deg_to_rad(20.0), aileron = deg_to_rad(20.0), rudder = deg_to_rad(25.0)})
		var elapsed := (Time.get_ticks_usec() - begin) / 1e6
		var bytes := var_to_bytes(result)
		var item := {ok = result.ok, seconds = elapsed, result_hex = bytes.hex_encode()}
		if not baseline.is_empty():
			var previous: Dictionary = baseline.get("cases", {}).get(id, {})
			item.exact = item.result_hex == previous.get("result_hex", "")
			item.time_ratio = elapsed / float(previous.get("seconds", 1e-99))
			failed = failed or not item.exact or item.time_ratio > max_ratio
		report.cases[id] = item
		print("%s ok=%s seconds=%.6f exact=%s ratio=%s" % [id, result.ok, elapsed,
			item.get("exact", "baseline"), item.get("time_ratio", "baseline")])
		failed = failed or not result.ok
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write report: " + output)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	quit(1 if failed else 0)
