## DT-11a / FW-24-R1: complete CPU star-field construction, native instance-buffer parity.
extends SceneTree

const Clock := preload("res://render/shader_clock.gd")

var reference: GDScript
var candidate: GDScript
var output := ""
var failed := false
var candidate_first := false


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--reference="): reference = load(arg.trim_prefix("--reference=")) as GDScript
		elif arg.begins_with("--candidate="): candidate = load(arg.trim_prefix("--candidate=")) as GDScript
		elif arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		elif arg == "--candidate-first": candidate_first = true
		else: failed = true
	if failed or reference == null or candidate == null or output.is_empty() or FileAccess.file_exists(output):
		printerr("expected --reference=<source> --candidate=<source> --output=<new file> [--candidate-first]")
		quit(2)
		return
	call_deferred("_run")


func _run() -> void:
	Clock.register()
	if DisplayServer.get_name() == "headless":
		printerr("native renderer required for instance-buffer verification")
		quit(2)
		return
	var first_reference: int
	var first_candidate: int
	if candidate_first:
		first_candidate = _time_build(candidate, 0.0, 40.0)
		first_reference = _time_build(reference, 0.0, 40.0)
	else:
		first_reference = _time_build(reference, 0.0, 40.0)
		first_candidate = _time_build(candidate, 0.0, 40.0)
	var cold_reference: Array[int] = []
	var cold_candidate: Array[int] = []
	for pair: int in 10:
		# Retire the previous private catalogue outside the first-construction timer.
		candidate._placements_for_source('{"format":"openrc-stars v1","rows":[]}', Basis.IDENTITY)
		if pair % 2 == 0:
			cold_reference.append(_time_build(reference, 0.0, 40.0))
			cold_candidate.append(_time_build(candidate, 0.0, 40.0))
		else:
			cold_candidate.append(_time_build(candidate, 0.0, 40.0))
			cold_reference.append(_time_build(reference, 0.0, 40.0))
	var results: Array = []
	for i: int in 8:
		var lst := float(i) * 47.5
		var latitude: float = [-90.0, -40.0, 0.0, 40.0, 90.0][i % 5]
		var a: Array = reference.placements({lst_deg = lst}, latitude)
		var b: Array = candidate.placements({lst_deg = lst}, latitude)
		if var_to_bytes(a) != var_to_bytes(b): failed = true
		var cloud := {seed = 1253 + i, offset = Vector2(float(i) * 0.125, -float(i) * 0.25)}
		var ar: Node3D = reference.build({lst_deg = lst}, latitude, cloud)
		var br: Node3D = candidate.build({lst_deg = lst}, latitude, cloud)
		var am: MultiMesh = ar.get_node("StarField").multimesh
		var bm: MultiMesh = br.get_node("StarField").multimesh
		await process_frame
		var buffers_equal := am.buffer.to_byte_array() == bm.buffer.to_byte_array()
		var materials_equal := _material_bytes(am.mesh.material) == _material_bytes(bm.mesh.material)
		if not buffers_equal or not materials_equal: failed = true
		if am.instance_count != 5080 or bm.instance_count != 5080: failed = true
		var buffer_floats := am.buffer.size()
		if buffer_floats != 101600: failed = true
		var geometry_hash := _hash(am.buffer.to_byte_array())
		ar.free()
		br.free()
		var rtimes: Array[int] = []
		var ctimes: Array[int] = []
		for j: int in 10:
			if j % 2 == 0:
				rtimes.append(_time_build(reference, lst, latitude))
				ctimes.append(_time_build(candidate, lst, latitude))
			else:
				ctimes.append(_time_build(candidate, lst, latitude))
				rtimes.append(_time_build(reference, lst, latitude))
		results.append({lst = lst, latitude = latitude, reference_usec = rtimes, candidate_usec = ctimes,
			placements_equal = var_to_bytes(a) == var_to_bytes(b), buffer_floats = buffer_floats,
			buffer_equal = buffers_equal, material_equal = materials_equal, buffer_sha256 = geometry_hash,
			placements_sha256 = _hash(var_to_bytes(a))})
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		printerr("cannot create report")
		quit(1)
		return
	file.store_string(JSON.stringify({complete = not failed, renderer = DisplayServer.get_name(),
		engine = Engine.get_version_info(), first_reference_usec = first_reference, first_candidate_usec = first_candidate,
		candidate_first = candidate_first, cold_reference_usec = cold_reference, cold_candidate_usec = cold_candidate,
		machine = {processor = OS.get_processor_name(), os = OS.get_name(),
			architecture = Engine.get_architecture_name(), debug_build = OS.is_debug_build()},
		reference_sha256 = FileAccess.get_sha256(reference.resource_path),
		candidate_sha256 = FileAccess.get_sha256(candidate.resource_path),
		catalogue_sha256 = FileAccess.get_sha256("res://data/sky/stars.json"),
		probe_sha256 = FileAccess.get_sha256(get_script().resource_path), results = results}, "\t"))
	file.close()
	print("star build probe ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func _time_build(script: GDScript, lst: float, latitude: float) -> int:
	var started := Time.get_ticks_usec()
	var built: Node3D = script.build({lst_deg = lst}, latitude, {})
	var elapsed := Time.get_ticks_usec() - started
	built.free()
	return elapsed


func _material_bytes(material: ShaderMaterial) -> PackedByteArray:
	var values: Array = []
	for uniform: Dictionary in material.shader.get_shader_uniform_list():
		values.append([uniform.name, material.get_shader_parameter(uniform.name)])
	return var_to_bytes(values)


func _hash(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()
