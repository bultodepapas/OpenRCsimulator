extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _hash(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value))
	return context.finish().hex_encode()

func _geometry(node: Node) -> Array:
	var rows: Array = []
	var row: Array = [node.get_class(), str(node.name).get_slice("@", 0)]
	if node is Node3D:
		row.append(node.transform)
	if node is MeshInstance3D and node.mesh != null:
		row.append(_mesh(node.mesh))
	if node is MultiMeshInstance3D and node.multimesh != null:
		var mm: MultiMesh = node.multimesh
		row.append([mm.buffer, mm.instance_count, mm.visible_instance_count, mm.custom_aabb, _mesh(mm.mesh)])
	rows.append(row)
	for child: Node in node.get_children():
		rows.append(_geometry(child))
	return rows

func _mesh(mesh: Mesh) -> Array:
	if mesh == null:
		return []
	var values: Array = [mesh.get_aabb(), mesh.get_surface_count()]
	for index in mesh.get_surface_count():
		values.append(_hash(mesh.surface_get_arrays(index)))
		if mesh is ArrayMesh:
			values.append(mesh.surface_get_primitive_type(index))
	return values

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	var directory: String = get_script().resource_path.get_base_dir()
	var output := ""
	var reverse := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg == "--reverse": reverse = true
	if output.is_empty() or FileAccess.file_exists(output):
		quit(2)
		return
	var clock: Script = load("res://render/shader_clock.gd")
	clock.register()
	var loader: Script = load("res://data/field_loader.gd")
	var field: Dictionary = loader.load_from().field
	var original := var_to_bytes(field)
	var scripts := {reference = load(directory.path_join("field_reference.gd")), candidate = load(directory.path_join("field_candidate.gd"))}
	var samples: Array = []
	var failures: Array = []
	for pair in 6:
		var order: Array = ["reference", "candidate"]
		if (pair % 2 == 0) == reverse: order.reverse()
		var fingerprints := {}
		for variant: String in order:
			var begin := Time.get_ticks_usec()
			var built: Node3D = scripts[variant].build(field)
			var elapsed := Time.get_ticks_usec() - begin
			var scenery: Dictionary = built.get_node("Scenery").get_meta("stats")
			samples.append({pair = pair, variant = variant, usec = elapsed, scenery_ms = scenery.build_ms, patches_ms = scenery.timing_ms.patch})
			fingerprints[variant] = _hash(_geometry(built))
			built.free()
		if fingerprints.reference != fingerprints.candidate:
			failures.append({pair = pair, hashes = fingerprints})
		await process_frame
		await process_frame
	if original != var_to_bytes(field): failures.append("mutated input")
	var ground: Script = load(directory.path_join("ground_candidate.gd"))
	var report := {complete = failures.is_empty(), samples = samples, failures = failures, exact_pairs = 6,
		cache_entries = ground._patch_cache.size(), cache_bytes = ground._patch_cache_bytes,
		engine = Engine.get_version_info(), adapter = RenderingServer.get_video_adapter_name(),
		scope = "native complete detached default field CPU construction; all node transforms, mesh arrays/bounds and MultiMesh buffers; not first draw or FPS"}
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("field comparison pairs=6 failures=", failures, " cache_bytes=", ground._patch_cache_bytes)
	quit(0 if failures.is_empty() else 1)
