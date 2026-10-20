## DT-11a / L11a: complete grass validation/build timing and native output parity.
extends SceneTree

const Clock := preload("res://render/shader_clock.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Ground := preload("res://render/ground.gd")
const GrassMask := preload("res://render/landscape_upgrade/scenery_grass_mask.gd")
const DATA_PATH := "res://data/fields/grass.json"

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
	if DisplayServer.get_name() == "headless":
		printerr("native renderer required for nonempty instance-buffer verification")
		quit(2)
		return
	call_deferred("_run")


func _run() -> void:
	Clock.register()
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	var source_bytes := var_to_bytes(raw)
	var validation_cases := _validation_cases(raw)
	var validation_times := {reference_usec = [], candidate_usec = []}
	for pair: int in 8:
		for script: GDScript in _order(pair):
			var started := Time.get_ticks_usec()
			var rows: Array = script.validated_rows(raw)
			var elapsed := Time.get_ticks_usec() - started
			if rows.size() != 6000 or not is_same(rows, raw.rows): failed = true
			validation_times["reference_usec" if script == reference else "candidate_usec"].append(elapsed)
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	if not loaded.get("ok", false):
		printerr("default field failed validation")
		quit(1)
		return
	var field: Dictionary = loaded.field
	var translated: Dictionary = field.duplicate(true)
	translated.pilot.north += 8.0
	translated.pilot.east -= 6.0
	var n := float(field.pilot.north)
	var e := float(field.pilot.east)
	var masks := GrassMask.footprints({groups = [{id = "probe-gravel", type = "patch", surface = "gravel",
		points = [[n - 25.0, e - 20.0], [n + 25.0, e - 20.0], [n + 25.0, e + 20.0], [n - 25.0, e + 20.0]]}]})
	var ground: ShaderMaterial = Ground.grass_material()
	var builds: Array = []
	for fixture: Dictionary in [{id = "default-direct", field = field, masks = []},
		{id = "translated-pilot", field = translated, masks = []},
		{id = "gravel-mask", field = field, masks = masks}]:
		var item := {id = fixture.id, reference_usec = [], candidate_usec = [], pairs = []}
		var ar: Array = reference.clipped_chunks(fixture.field, raw.rows, fixture.masks)
		var br: Array = candidate.clipped_chunks(fixture.field, raw.rows, fixture.masks)
		if var_to_bytes(ar) != var_to_bytes(br): failed = true
		item["placements_sha256"] = _hash(var_to_bytes(ar))
		for pair: int in 6:
			var nodes: Dictionary = {}
			for script: GDScript in _order(pair):
				var started := Time.get_ticks_usec()
				var built: Node3D = script.build(fixture.field, ground, fixture.masks)
				var elapsed := Time.get_ticks_usec() - started
				var key := "reference" if script == reference else "candidate"
				item[key + "_usec"].append(elapsed)
				nodes[key] = built
			await process_frame
			var a := _snapshot(nodes.reference)
			var b := _snapshot(nodes.candidate)
			var equal := var_to_bytes(a) == var_to_bytes(b)
			var independent := _independent(nodes.reference, nodes.candidate)
			if not equal or not independent: failed = true
			item.pairs.append({equal = equal, independent = independent, clumps = a.clumps,
				buffer_floats = a.buffer_floats, state_sha256 = _hash(var_to_bytes(a))})
			nodes.reference.free()
			nodes.candidate.free()
		builds.append(item)
	if var_to_bytes(raw) != source_bytes: failed = true
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		printerr("cannot create report")
		quit(1)
		return
	file.store_string(JSON.stringify({complete = not failed, engine = Engine.get_version_info(),
		renderer = DisplayServer.get_name(), candidate_first = candidate_first,
		machine = {processor = OS.get_processor_name(), os = OS.get_name(),
			architecture = Engine.get_architecture_name(), debug_build = OS.is_debug_build()},
		reference_sha256 = FileAccess.get_sha256(reference.resource_path),
		candidate_sha256 = FileAccess.get_sha256(candidate.resource_path),
		data_sha256 = FileAccess.get_sha256(DATA_PATH),
		field_sha256 = FileAccess.get_sha256(FieldLoader.DEFAULT_PATH),
		probe_sha256 = FileAccess.get_sha256(get_script().resource_path),
		source_unchanged = var_to_bytes(raw) == source_bytes,
		validation_cases = validation_cases, validation_times = validation_times, builds = builds}, "\t"))
	file.close()
	print("grass validation/build probe ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func _validation_cases(raw: Dictionary) -> Array:
	var cases: Array = [{id = "committed", data = raw, accepted = true}]
	var mixed := raw.duplicate(true)
	for i: int in 4: mixed.rows[0][i] = int(mixed.rows[0][i]) if i % 2 == 0 else float(mixed.rows[0][i])
	cases.append({id = "mixed-numeric-types", data = mixed, accepted = true})
	var reversed := raw.duplicate(true)
	reversed.rows.reverse()
	reversed.rows_sha256 = _digest(reversed.rows)
	cases.append({id = "reversed-rehashed", data = reversed, accepted = true})
	var bad_hash := raw.duplicate(true)
	bad_hash.rows_sha256 = "invalid"
	cases.append({id = "bad-digest", data = bad_hash, accepted = false})
	var tail := raw.duplicate(true)
	tail.rows[-1][2] = float(tail.rows[-1][2]) + 0.5
	cases.append({id = "fractional-tail-unchanged-digest", data = tail, accepted = false})
	var malformed := raw.duplicate(true)
	malformed.rows[-1] = [1, 2, 3]
	cases.append({id = "malformed-tail", data = malformed, accepted = false})
	var duplicate := raw.duplicate(true)
	duplicate.rows[-1][0] = duplicate.rows[0][0]
	duplicate.rows[-1][1] = duplicate.rows[0][1]
	duplicate.rows_sha256 = _digest(duplicate.rows)
	cases.append({id = "duplicate-rehashed", data = duplicate, accepted = false})
	var outside := raw.duplicate(true)
	outside.rows[-1][0] = 30000
	outside.rows[-1][1] = 1
	outside.rows_sha256 = _digest(outside.rows)
	cases.append({id = "outside-disk-rehashed", data = outside, accepted = false})
	var nonfinite := raw.duplicate(true)
	nonfinite.rows[-1][3] = NAN
	cases.append({id = "nan-tail", data = nonfinite, accepted = false})
	var results: Array = []
	for item: Dictionary in cases:
		var before := var_to_bytes(item.data)
		var a: Array = reference.validated_rows(item.data)
		var b: Array = candidate.validated_rows(item.data)
		var equal := var_to_bytes(a) == var_to_bytes(b)
		var expected := (a.size() == 6000 and is_same(a, item.data.rows) and is_same(b, item.data.rows)) if item.accepted else (a.is_empty() and b.is_empty())
		var unchanged := before == var_to_bytes(item.data)
		if not equal or not expected or not unchanged: failed = true
		results.append({id = item.id, equal = equal, expected = expected, source_unchanged = unchanged,
			rows = a.size(), rows_sha256 = _hash(var_to_bytes(a))})
	return results


func _snapshot(built: Node3D) -> Dictionary:
	var chunks: Array = []
	var buffer_floats := 0
	for child: MultiMeshInstance3D in built.get_children():
		var mm := child.multimesh
		var buffer := mm.buffer
		if buffer.size() != mm.instance_count * 12 or buffer.is_empty(): failed = true
		buffer_floats += buffer.size()
		chunks.append([child.name, child.transform, child.cast_shadow, child.custom_aabb,
			mm.transform_format, mm.use_colors, mm.use_custom_data, mm.instance_count,
			mm.visible_instance_count, buffer, mm.mesh.surface_get_primitive_type(0),
			mm.mesh.surface_get_arrays(0), _material_values(mm.mesh.surface_get_material(0))])
	if chunks.is_empty() or buffer_floats != int(built.get_meta("clumps")) * 12: failed = true
	return {name = built.name, clumps = built.get_meta("clumps"), buffer_floats = buffer_floats,
		material = _material_values(built.get_meta("lighting_material")), chunks = chunks}


func _independent(a: Node3D, b: Node3D) -> bool:
	if a == b or a.get_meta("lighting_material") == b.get_meta("lighting_material"): return false
	for i: int in mini(a.get_child_count(), b.get_child_count()):
		var am: MultiMesh = a.get_child(i).multimesh
		var bm: MultiMesh = b.get_child(i).multimesh
		if am == bm or am.mesh == bm.mesh or am.mesh.surface_get_material(0) == bm.mesh.surface_get_material(0): return false
	return true


func _material_values(material: ShaderMaterial) -> Array:
	var values: Array = [material.shader.resource_path]
	for uniform: Dictionary in material.shader.get_shader_uniform_list():
		values.append([uniform.name, material.get_shader_parameter(uniform.name)])
	return values


func _order(pair: int) -> Array[GDScript]:
	return [candidate, reference] if (pair % 2 == 0) == candidate_first else [reference, candidate]


## Independent original concatenation oracle, including order and the trailing newline.
func _digest(rows: Array) -> String:
	var canonical := ""
	for row: Array in rows:
		canonical += "%d,%d,%d,%d\n" % [int(row[0]), int(row[1]), int(row[2]), int(row[3])]
	return canonical.sha256_text()


func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
