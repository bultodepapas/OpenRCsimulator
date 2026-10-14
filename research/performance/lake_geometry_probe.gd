# DT-11a: compare an explicit prior source with the current render-only builder.
# Reference must be an unmodified lake_terrain.gd extracted from the recorded revision.
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var reference_path := ""
	var candidate_path := "res://render/lake/lake_terrain.gd"
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--reference="):
			reference_path = arg.trim_prefix("--reference=")
		elif arg.begins_with("--candidate="):
			candidate_path = arg.trim_prefix("--candidate=")
		elif arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
		else:
			push_error("Unknown option: " + arg)
			quit(1)
			return
	if reference_path.is_empty() or output.is_empty() or FileAccess.file_exists(output):
		push_error("Provide --reference and a new --output")
		quit(1)
		return
	var reference: Script = load(reference_path)
	var candidate: Script = load(candidate_path)
	var loader: Script = load("res://data/lake_loader.gd")
	var field_loader: Script = load("res://data/field_loader.gd")
	var surfaces_script: Script = load("res://physics/ground_surfaces.gd")
	var ground: Script = load("res://render/ground.gd")
	var lake: Dictionary = loader.load_from().lake
	var surfaces: PackedFloat64Array = surfaces_script.build(
		surfaces_script.load_table().table, field_loader.load_from().field).rects
	var material: ShaderMaterial = ground.grass_material({})
	var samples: Array[Dictionary] = []
	var equal := true
	for index in 8:
		var selected: Dictionary = lake.duplicate(true)
		var selected_surfaces := surfaces.duplicate()
		var label := "default-%d" % index
		if index == 3:
			label = "water-level-same-identity"
			selected.water_level_down_m += 0.01
		elif index == 4:
			label = "bed-profile-same-identity"
			selected.bed_profile[-1].depth_m += 0.1
		elif index == 5:
			label = "shoreline-same-identity"
			selected.shoreline_ne_m[0] += 0.1
		elif index == 6:
			label = "bank-same-identity"
			selected.bank_ne_m[0] += 0.1
		elif index == 7:
			label = "flat-ground-table"
			selected_surfaces = PackedFloat64Array()
		var pair := {"case": label, "input_sha256": _hash([selected, selected_surfaces])}
		var order: Array = [["reference", reference], ["candidate", candidate]]
		if index % 2 == 1:
			order.reverse()
		for entry: Array in order:
			var begin := Time.get_ticks_usec()
			var node: Node3D = entry[1].build(selected, material, selected_surfaces)
			var elapsed := Time.get_ticks_usec() - begin
			var basin: MeshInstance3D = node.get_node("Basin")
			var water: MeshInstance3D = node.get_node("Water")
			var geometry := [basin.mesh.surface_get_arrays(0), water.mesh.surface_get_arrays(0),
				water.position, water.custom_aabb, node.get_meta("triangles")]
			pair[entry[0]] = {"build_usec": elapsed, "geometry_sha256": _hash(geometry),
				"geometry_bytes": var_to_bytes(geometry).size()}
			node.free()
		pair["equal"] = pair.reference.geometry_sha256 == pair.candidate.geometry_sha256
		equal = equal and pair.equal
		samples.append(pair)
		print(label, ": reference=", pair.reference.build_usec, " candidate=", pair.candidate.build_usec, " equal=", pair.equal)
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot create output")
		quit(1)
		return
	file.store_string(JSON.stringify({"format": "openrc-lake-geometry v1", "complete": true,
		"equal": equal, "engine": Engine.get_version_info(),
		"reference_sha256": FileAccess.get_sha256(reference_path),
		"candidate_sha256": FileAccess.get_sha256(candidate_path), "samples": samples,
		"scope": "serial alternating builder calls; first candidate cold, following unchanged inputs warm; headless CPU construction, not GPU qualification"}, "\t") + "\n")
	file.close()
	quit(0 if equal else 1)


func _hash(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value))
	return context.finish().hex_encode()
