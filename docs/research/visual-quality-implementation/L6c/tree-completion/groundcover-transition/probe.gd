extends SceneTree

const Candidate = preload("res://scenery/woodland_edge_habitat.gd")
const Field = preload("res://data/field_loader.gd")
const Scenery = preload("res://scenery/scenery_loader.gd")
const Lake = preload("res://data/lake_loader.gd")
const Surfaces = preload("res://physics/ground_surfaces.gd")
const Terrain = preload("res://physics/ground_terrain.gd")
const Clock = preload("res://render/shader_clock.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	Clock.register()
	var options: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2: options[pair[0]] = pair[1]
	var reference: Script = load(options.reference)
	var field: Dictionary = Field.load_from().field
	var scenery: Dictionary = Scenery.load_from(Scenery.DEFAULT_PATH, field).scenery
	var lake: Dictionary = Lake.load_from().lake
	var surfaces: PackedFloat64Array = Surfaces.build(Surfaces.load_table().table, field).rects
	var report := {adapter = RenderingServer.get_video_adapter_name(), engine = Engine.get_version_info(),
		scope = "Native CPU build calls only; not frame time. Shared dependencies warm within each process.",
		first_calls_us = {}, samples_us = {}, failures = failures}
	var order: Array = [reference, Candidate] if options.get("first", "reference") == "reference" else [Candidate, reference]
	for implementation in order:
		var start := Time.get_ticks_usec()
		var built: Node3D = implementation.build(field, scenery, "high", lake)
		report.first_calls_us["reference" if implementation == reference else "candidate"] = Time.get_ticks_usec() - start
		built.free()
	for quality: String in ["low", "balanced", "high"]:
		var samples := {reference = [], candidate = []}
		for iteration in 9:
			var pair: Array = [reference, Candidate] if iteration % 2 == 0 else [Candidate, reference]
			for implementation in pair:
				var start := Time.get_ticks_usec()
				var built: Node3D = implementation.build(field, scenery, quality, lake)
				samples["reference" if implementation == reference else "candidate"].append(Time.get_ticks_usec() - start)
				built.free()
		report.samples_us[quality] = samples
	var built := Candidate.build(field, scenery, "high", lake)
	var plants: Array = built.get_meta("plants")
	var checked_cards := 0
	for child: Node in built.get_children():
		if not child is MultiMeshInstance3D: continue
		var batch := child as MultiMeshInstance3D
		var patch_id := str(batch.name).trim_suffix("_Shrubs")
		var records: Array = plants.filter(func(p: Dictionary) -> bool: return p.patch == patch_id)
		check(records.size() == batch.multimesh.instance_count, "instance records")
		for index in records.size():
			var plant: Dictionary = records[index]
			var transform := batch.multimesh.get_instance_transform(index)
			var ground := Terrain.sample_validated(plant.north, plant.east, surfaces, lake)
			check(absf(transform.origin.y - ground[0] - float(plant.height_m) * 0.5) < 0.0001, "card ground contact")
			var selector := batch.multimesh.get_instance_custom_data(index).g
			check(int(round(selector)) == Candidate.SPECIES.find(plant.asset_id), "GPU source selector")
			var radius := batch.multimesh.mesh.get_aabb().size.length() * transform.basis.get_scale().x * 0.5
			var sphere := AABB(transform.origin - Vector3.ONE * radius, Vector3.ONE * radius * 2.0)
			check(batch.multimesh.custom_aabb.grow(0.0001).encloses(sphere), "billboard bounds")
			checked_cards += 1
	var floor_node: MeshInstance3D = built.get_node("WoodlandLitter")
	var arrays := floor_node.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for vertex in vertices:
		var ground := Terrain.sample_validated(-vertex.z, vertex.x, surfaces, lake)
		check(absf(vertex.y - ground[0] - 0.02) < 0.0001, "litter terrain contact")
	var index_data: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in range(0, index_data.size(), 3):
		var a: Vector3 = vertices[index_data[i]]
		var b: Vector3 = vertices[index_data[i + 1]]
		var c: Vector3 = vertices[index_data[i + 2]]
		check((b - a).cross(c - a).y < 0.0, "litter clockwise front face")
	var texture: Texture2D = floor_node.material_override.get_shader_parameter("litter_albedo")
	report.litter_texture = {width = texture.get_width(), height = texture.get_height(), bytes_with_mips = texture.get_image().get_data().size(), has_mips = texture.get_image().has_mipmaps()}
	report.checked_cards = checked_cards
	report.checked_floor_vertices = vertices.size()
	report.triangles = built.get_meta("triangles")
	report.batches = built.get_meta("batches")
	report.source_sha256 = {}
	for path: String in ["res://scenery/woodland_edge_habitat.gd", "res://scenery/woodland_cards.gdshader", "res://scenery/woodland_floor.gdshader", Candidate.DATA_PATH]:
		report.source_sha256[path] = FileAccess.get_sha256(path)
	built.free()
	report.complete = failures.is_empty()
	var file := FileAccess.open(options.output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("WOODLAND REFINEMENT PROBE ", report.complete, ": ", failures)
	quit(0 if failures.is_empty() else 1)
