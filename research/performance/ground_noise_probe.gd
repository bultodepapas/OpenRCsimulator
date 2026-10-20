## DT-11a: complete ground-image/cold-material timing with exact native image/mip parity.
extends SceneTree

const Clock := preload("res://render/shader_clock.gd")
const SEEDS := [1253, 1254, 0, -1, 2147483647]

var reference: GDScript
var candidate: GDScript
var output := ""
var candidate_first := false
var failed := false


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
		printerr("native renderer required for uploaded texture/mip parity")
		quit(2)
		return
	_run.call_deferred()


func _run() -> void:
	Clock.register()
	# The default material route is the production baseline; do not inherit a host quality override.
	var previous_quality := OS.get_environment("OPENRC_GRASS_QUALITY")
	OS.set_environment("OPENRC_GRASS_QUALITY", "")
	var images: Array = []
	for seed: int in SEEDS:
		var item := {seed = seed, reference_usec = [], candidate_usec = [], pairs = []}
		for pair: int in 4:
			var made: Dictionary = {}
			for script: GDScript in _order(pair):
				var started := Time.get_ticks_usec()
				var img: Image = script.grass_image(seed)
				var elapsed := Time.get_ticks_usec() - started
				var key := "reference" if script == reference else "candidate"
				made[key] = img
				item[key + "_usec"].append(elapsed)
			var a := _image_state(made.reference)
			var b := _image_state(made.candidate)
			var equal := a == b
			var independent: bool = made.reference != made.candidate
			if not equal or not independent: failed = true
			item.pairs.append({equal = equal, independent = independent, image = a})
		images.append(item)
	var cold := {reference_usec = [], candidate_usec = [], pairs = []}
	for pair: int in 6:
		var made: Dictionary = {}
		for script: GDScript in _order(pair):
			# Retire the existing fixed-default bytes outside the timer. No OS/import/driver caches are cleared.
			script._default_grass_bytes = PackedByteArray()
			var started := Time.get_ticks_usec()
			var material: ShaderMaterial = script.grass_material()
			var elapsed := Time.get_ticks_usec() - started
			var key := "reference" if script == reference else "candidate"
			made[key] = material
			cold[key + "_usec"].append(elapsed)
			if script._default_grass_bytes.size() != 262143: failed = true
		await process_frame
		var a := _material_state(made.reference)
		var b := _material_state(made.candidate)
		var equal := var_to_bytes(a) == var_to_bytes(b)
		var independent: bool = made.reference != made.candidate and made.reference.get_shader_parameter("grass") != made.candidate.get_shader_parameter("grass")
		if not equal or not independent: failed = true
		cold.pairs.append({equal = equal, independent = independent, material_sha256 = _hash(var_to_bytes(a))})
	var warm := {reference_usec = [], candidate_usec = []}
	for pair: int in 10:
		for script: GDScript in _order(pair):
			var started := Time.get_ticks_usec()
			var material: ShaderMaterial = script.grass_material()
			var elapsed := Time.get_ticks_usec() - started
			warm["reference_usec" if script == reference else "candidate_usec"].append(elapsed)
			if material == null: failed = true
	OS.set_environment("OPENRC_GRASS_QUALITY", previous_quality)
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
		probe_sha256 = FileAccess.get_sha256(get_script().resource_path),
		spec_sha256 = FileAccess.get_sha256("res://spec.gd"),
		images = images, cold_material = cold, warm_material_control = warm}, "\t"))
	file.close()
	print("ground noise probe ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func _image_state(img: Image) -> Dictionary:
	if img == null:
		failed = true
		return {}
	if img.get_width() != 256 or img.get_height() != 256 or img.get_format() != Image.FORMAT_RGB8 \
		or not img.has_mipmaps() or img.get_mipmap_count() != 8 or img.get_data_size() != 262143:
		failed = true
	return {width = img.get_width(), height = img.get_height(), format = img.get_format(),
		mips = img.get_mipmap_count(), bytes = img.get_data_size(), sha256 = _hash(img.get_data())}


func _material_state(material: ShaderMaterial) -> Array:
	var values: Array = [material.shader.resource_path]
	for uniform: Dictionary in material.shader.get_shader_uniform_list():
		var value: Variant = material.get_shader_parameter(uniform.name)
		if value is Texture2D:
			value = _image_state(value.get_image()) if str(uniform.name) == "grass" else [value.get_class(), value.resource_path]
		values.append([uniform.name, value])
	return values


func _order(pair: int) -> Array[GDScript]:
	return [candidate, reference] if (pair % 2 == 0) == candidate_first else [reference, candidate]


func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
