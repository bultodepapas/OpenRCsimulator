## TT-21 / AFC-04: same-host prior-source parity and complete-component screening.
extends SceneTree

const Pilot := preload("res://ai/companions/pilot.gd")
const Details := preload("res://aircraft/timber_visual_details.gd")
const Timber := preload("res://aircraft/timber_model.gd")
const Paint := preload("res://aircraft/procedural_skin.gd")
const Body := preload("res://physics/rigid_body.gd")
const Math3D := preload("res://physics/math3d.gd")
const Field := preload("res://data/field_loader.gd")
var _baseline_pilot: Script
var _baseline_details: Script
var _output := ""
var _baseline_paths: Array[String] = []
var checks := 0
var failed := 0
var report := {timber_us = [], command_us = {}, score_cases = 0}

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		printerr("FAIL ", label)

func _run() -> void:
	var pilot_path := ""
	var timber_path := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--pilot-baseline="):
			pilot_path = argument.trim_prefix("--pilot-baseline=")
		elif argument.begins_with("--timber-baseline="):
			timber_path = argument.trim_prefix("--timber-baseline=")
		elif argument.begins_with("--out="):
			_output = argument.trim_prefix("--out=")
	if _output.is_empty() or FileAccess.file_exists(_output) or DirAccess.dir_exists_absolute(_output) \
			or not FileAccess.file_exists(pilot_path) or not FileAccess.file_exists(timber_path):
		printerr("Supply --pilot-baseline=<prior pilot.gd> --timber-baseline=<prior details.gd> --out=<new JSON file>.")
		quit(2)
		return
	_baseline_pilot = load(pilot_path) as Script
	_baseline_details = load(timber_path) as Script
	if _baseline_pilot == null or not _baseline_pilot.can_instantiate() \
			or _baseline_details == null or not _baseline_details.can_instantiate():
		printerr("Baseline scripts must parse and instantiate against the current dependencies.")
		quit(2)
		return
	_baseline_paths = [pilot_path, timber_path]
	var original_hashes := _source_hashes()
	_score_parity()
	_timber()
	_commands()
	report.engine = Engine.get_version_info().string
	report.paint_identity = Paint.identity(Paint.TIMBER)
	report.source_sha256 = _source_hashes()
	check(report.source_sha256 == original_hashes, "measured sources remain unchanged")
	report.checks = checks
	report.failed = failed
	var output := FileAccess.open(_output, FileAccess.WRITE)
	if output == null:
		printerr("Cannot create output JSON: ", _output)
		quit(2)
		return
	output.store_string(JSON.stringify(report, "  ") + "\n")
	print("QUALIFICATION ", checks, " checks, ", failed, " failed; paint_identity=", report.paint_identity)
	quit(1 if failed else 0)

func _score_parity() -> void:
	var state := Body.make_state(PackedFloat64Array([0, 0, -100]), PackedFloat64Array([15, 0, 0]),
		Math3D.q_from_euler(0, 0, 0), PackedFloat64Array([0, 0, 0]))
	var before = _baseline_pilot.new()
	var after := Pilot.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261109
	for i in 300:
		var speed: float = [0.0, 2.999999999, 3.0, 15.0, 30.0][i % 5]
		var current := rng.randf_range(-0.4363323129985824, 0.4363323129985824)
		var target := rng.randf_range(-0.4363323129985824, 0.4363323129985824)
		if i < 8:
			current = [0.0, -0.0, 0.4363323129985824, -0.4363323129985824, 1e-300, 1e300, NAN, INF][i]
			target = -0.13
		var wind := PackedFloat64Array([rng.randf_range(-2, 2), rng.randf_range(-2, 2), 0])
		before._planning_wind = wind
		after._planning_wind = wind
		var velocity := PackedFloat64Array([speed + wind[0], wind[1], rng.randf_range(-5, 10)])
		var traffic: Array = []
		for j in i % 4:
			traffic.append({id = str(j), is_player = j == 0, position_ned = PackedFloat64Array([
				rng.randf_range(-150, 150), rng.randf_range(-60, 60), rng.randf_range(-140, -50)]),
				velocity_ned = PackedFloat64Array([rng.randf_range(-20, 20), rng.randf_range(-10, 10), rng.randf_range(-5, 5)])})
		var threats: Array[Dictionary] = before._prepare_threats(traffic, velocity)
		var original := var_to_bytes([state, velocity, threats])
		for trace: bool in [false, true]:
			var a: Dictionary = before._score_bank(state, velocity, speed, current, 0, target, 24, threats, trace)
			var b: Dictionary = after._score_bank(state, velocity, speed, current, 0, target, 24, threats, trace)
			check(var_to_bytes(a) == var_to_bytes(b), "score/trace byte parity " + str(i) + "/" + str(trace))
			report.score_cases += 1
		check(var_to_bytes([state, velocity, threats]) == original, "detached score inputs " + str(i))

func _snapshot(root: Node3D) -> PackedByteArray:
	var records: Array = []
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = node.mesh
		if mesh == null: continue
		var surfaces: Array = []
		var raw: Array = mesh.get("_surfaces")
		for i in mesh.get_surface_count():
			var serialized: Dictionary = raw[i].duplicate()
			serialized.erase("material")
			var material: Material = node.get_active_material(i)
			surfaces.append([mesh.surface_get_arrays(i), serialized, mesh.surface_get_format(i),
				mesh.surface_get_name(i), material.resource_name if material != null else ""])
		records.append([str(root.get_path_to(node)), node.transform, surfaces])
	return var_to_bytes(records)

func _timber() -> void:
	var expected := PackedByteArray()
	for group in 5:
		var order: Array = [false, true, true, false] if group % 2 == 0 else [true, false, false, true]
		for candidate: bool in order:
			var script: Script = Details if candidate else _baseline_details
			var model: Dictionary = Timber.build()
			check(not model.is_empty(), "imported Timber builds")
			if model.is_empty(): return
			var root: Node3D = model.root
			var source_before := _snapshot(root)
			var sources: Array = []
			for node: Node in root.find_children("*", "MeshInstance3D", true, false):
				sources.append([node, node.mesh])
			script._paint_repair_cache.clear()
			script._paint_repair_cache_order.clear()
			var start := Time.get_ticks_usec()
			script._repair_painted_surface_poke_through(root)
			var elapsed := Time.get_ticks_usec() - start
			var cold := _snapshot(root)
			if expected.is_empty(): expected = cold
			check(cold == expected, "actual cold repaired arrays/LOD/format/name/transform parity")
			for pair: Array in sources:
				pair[0].mesh = pair[1]
			check(_snapshot(root) == source_before, "source meshes unmodified")
			start = Time.get_ticks_usec()
			script._repair_painted_surface_poke_through(root)
			var warm := Time.get_ticks_usec() - start
			check(_snapshot(root) == expected, "warm cached repaired representation parity")
			report.timber_us.append({group = group, candidate = candidate, cold = elapsed, warm = warm})
			root.free()

func _commands() -> void:
	var field_result: Dictionary = Field.load_from()
	check(field_result.ok, "command field fixture")
	if not field_result.ok: return
	for count in [1, 3]:
		var before = _baseline_pilot.new()
		var after := Pilot.new()
		check(before.configure(0, 1, 20261020, {V = 15.0, throttle = 0.45}, field_result.field), "baseline configure")
		check(after.configure(0, 1, 20261020, {V = 15.0, throttle = 0.45}, field_result.field), "candidate configure")
		var pose: Dictionary = before.initial_pose()
		var state := Body.make_state(PackedFloat64Array([pose.north, pose.east, -pose.height_m]),
			PackedFloat64Array([15, 0, 0]), Math3D.q_from_euler(pose.heading_rad, 0, 0), PackedFloat64Array([0, 0, 0]))
		var snapshot := {state = state, airspeed_m_s = 15.0, wind_ned = PackedFloat64Array([0, 0, 0]),
			ground_clearance_m = 35.0, trim = {V = 15.0, throttle = 0.45}}
		var traffic: Array = []
		for j in count:
			traffic.append({id = str(j), is_player = j == 0, position_ned = PackedFloat64Array([pose.north + 15 + j * 5, pose.east + 5, -pose.height_m]),
				velocity_ned = PackedFloat64Array([0, 0, 0])})
		for i in 300:
			var a: Dictionary = before.command(snapshot, i * 4, traffic)
			var b: Dictionary = after.command(snapshot, i * 4, traffic)
			check(var_to_bytes(a) == var_to_bytes(b) and var_to_bytes(before.snapshot_state()) == var_to_bytes(after.snapshot_state()), "command/latch parity")
		var latch: Dictionary = before.snapshot_state()
		var timings: Array = []
		for group in 5:
			var order: Array = [false, true, true, false] if group % 2 == 0 else [true, false, false, true]
			for candidate: bool in order:
				var pilot = after if candidate else before
				check(pilot.restore_state(latch).ok, "held state restores for timing")
				var start := Time.get_ticks_usec()
				for i in 400:
					pilot.command(snapshot, 1200 + i * 4, traffic)
				timings.append({group = group, candidate = candidate, us_per_command = float(Time.get_ticks_usec() - start) / 400})
		report.command_us[str(count)] = timings


func _source_hashes() -> Dictionary:
	var result := {}
	for path: String in ["res://ai/companions/pilot.gd", "res://aircraft/timber_visual_details.gd",
		"res://ai/companions/circuit_controller.gd", "res://aircraft/timber_model.gd", get_script().resource_path] + _baseline_paths:
		result[path] = FileAccess.get_sha256(path)
	return result
