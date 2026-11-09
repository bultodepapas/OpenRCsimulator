## VQ-04a: independent prior-source collector pair, exact shapes and paired CPU cost.
extends SceneTree

const Airplane := preload("res://render/airplane.gd")
const Projected := preload("res://render/projected_shadow.gd")
const Proxy := preload("res://render/aircraft_shadow_proxy.gd")
const Retraction := preload("res://aircraft/retractable_model.gd")

var _checks := 0
var _failed := 0

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var proxy_path := ""
	var projected_path := ""
	var output_path := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--baseline-proxy="):
			proxy_path = argument.trim_prefix("--baseline-proxy=")
		elif argument.begins_with("--baseline-projected="):
			projected_path = argument.trim_prefix("--baseline-projected=")
		elif argument.begins_with("--out="):
			output_path = argument.trim_prefix("--out=")
	if not FileAccess.file_exists(proxy_path) or not FileAccess.file_exists(projected_path) \
			or not output_path.is_absolute_path() or FileAccess.file_exists(output_path) or DirAccess.dir_exists_absolute(output_path):
		printerr("Supply prior --baseline-proxy and --baseline-projected .gd files and a fresh absolute --out JSON path.")
		quit(2)
		return
	var baseline_projected := load(projected_path) as Script
	# Bind both frozen sources; never compare the old proxy through the new helper.
	var original := FileAccess.get_file_as_string(proxy_path)
	var dependency := 'preload("res://render/projected_shadow.gd")'
	if original.count(dependency) != 1 or baseline_projected == null:
		printerr("Baseline proxy must contain exactly one expected projected-collector preload.")
		quit(2)
		return
	var baseline_proxy := GDScript.new()
	baseline_proxy.source_code = original.replace(dependency, 'preload("' + projected_path.c_escape() + '")')
	if baseline_proxy.reload() != OK:
		quit(2)
		return
	var sources: Array[String] = [proxy_path, projected_path, "res://render/aircraft_shadow_proxy.gd",
		"res://render/projected_shadow.gd", "res://render/airplane.gd", "res://aircraft/retractable_model.gd", get_script().resource_path]
	var hashes := _hashes(sources)
	var aircraft: Dictionary = Airplane.build(Proxy.AIRCRAFT_ID)
	_check(not aircraft.is_empty() and Proxy.source_supported(aircraft.root), "actual stock Corsair source")
	if aircraft.is_empty():
		quit(1)
		return
	var cases: Array = []
	for pose: Array in [["gear_down", 1.0, 0.0], ["takeoff_flaps", 1.0, 10.0],
		["landing_flaps", 1.0, 25.0], ["gear_half", 0.5, 0.0], ["gear_up", 0.0, 0.0]]:
		Retraction.apply(aircraft.gear_retraction, float(pose[1]))
		Airplane.apply_flaps(aircraft, float(pose[2]))
		var old_full: Dictionary = baseline_projected.call("collect", aircraft.root)
		var full: Dictionary = Projected.collect(aircraft.root)
		_check(_shape_bytes(full) == _shape_bytes(old_full), str(pose[0]) + " exact full shape")
		var before: Dictionary = baseline_proxy.call("collect", aircraft.root, Proxy.MAX_LOD_DISTANCE)
		var after: Dictionary = Proxy.collect(aircraft.root, Proxy.MAX_LOD_DISTANCE)
		var expected := _shape_bytes(before)
		_check(_shape_bytes(after) == expected, str(pose[0]) + " exact selected shape")
		_check(after.get("representation") == "imported-lod-proxy", "actual imported LOD selected")
		var trials: Array = []
		for group in 5:
			var order: Array = [false, true, true, false] if group % 2 == 0 else [true, false, false, true]
			for candidate: bool in order:
				var script: Script = Proxy if candidate else baseline_proxy
				var start := Time.get_ticks_usec()
				var shape: Dictionary = script.call("collect", aircraft.root, Proxy.MAX_LOD_DISTANCE)
				var elapsed := Time.get_ticks_usec() - start
				_check(_shape_bytes(shape) == expected, "timed result retains exact shape")
				trials.append({group = group, candidate = candidate, usec = elapsed})
		cases.append({id = pose[0], gear = pose[1], flaps_deg = pose[2],
			triangles = after.triangles, source_triangles = after.source_triangles,
			shape_sha256 = _digest(expected), trials = trials})
	aircraft.root.free()
	_check(hashes == _hashes(sources), "selected sources remain unchanged")
	var report := {format = "openrc-shadow-collection-pair-v1", complete = _failed == 0,
		checks = _checks, failed = _failed, engine = Engine.get_version_info(),
		display = DisplayServer.get_name(), renderer = RenderingServer.get_current_rendering_method(),
		adapter = RenderingServer.get_video_adapter_name(), driver = RenderingServer.get_current_rendering_driver_name(),
		window_size = [root.size.x, root.size.y],
		baseline_bound_source_sha256 = baseline_proxy.source_code.sha256_text(),
		source_sha256 = hashes, cases = cases,
		scope = "Imported warm-process Corsair collector component; rendering, first interactive frame, GPU cost and peak memory unmeasured."}
	var output := FileAccess.open(output_path, FileAccess.WRITE)
	if output == null:
		printerr("Cannot write fresh output JSON")
		quit(2)
		return
	output.store_string(JSON.stringify(report, "  ") + "\n")
	print("SHADOW COLLECTION PAIR ", _checks, " checks, ", _failed, " failed")
	quit(1 if _failed else 0)

func _shape_bytes(shape: Dictionary) -> PackedByteArray:
	if shape.is_empty(): return var_to_bytes({})
	var metadata := shape.duplicate()
	metadata.erase("mesh")
	var mesh: ArrayMesh = shape.mesh
	return var_to_bytes([metadata, mesh.surface_get_arrays(0), mesh.surface_get_format(0)])

func _hashes(paths: Array[String]) -> Dictionary:
	var result := {}
	for path: String in paths:
		result[path] = FileAccess.get_sha256(path)
	return result

func _digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
