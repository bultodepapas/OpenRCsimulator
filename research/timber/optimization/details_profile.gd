extends SceneTree

const Timber := preload("res://aircraft/timber_model.gd")
const CurrentDetails := preload("res://aircraft/timber_visual_details.gd")
const ImportedModel := preload("res://aircraft/imported_model.gd")
const PHASE_METHODS := [
	"_repair_painted_surface_poke_through",
	"_apply_material_finishes",
	"_add_fuselage_markings",
	"_add_gear_springs",
	"_add_hub_fasteners",
	"_add_fracture_reveals",
]

var _errors: Array[String] = []
var _last_triangle_summary: Dictionary = {}
var _last_render_summary: Dictionary = {}
var _native_renderer := false
var _native_roots: Array[Node3D] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_native_renderer = DisplayServer.get_name() != "headless"
	if _native_renderer:
		_setup_native_probe_scene()
	var repo_root := ProjectSettings.globalize_path("res://project.godot").get_base_dir().get_base_dir()
	var baseline_path := repo_root.path_join("research/timber/optimization/details_baseline.gd")
	if not FileAccess.file_exists(baseline_path):
		printerr("Missing preserved baseline source: ", baseline_path)
		quit(2)
		return
	var baseline_script := GDScript.new()
	baseline_script.source_code = FileAccess.get_file_as_string(baseline_path)
	var load_error := baseline_script.reload()
	if load_error != OK:
		printerr("Could not compile baseline helper: ", load_error)
		quit(2)
		return
	var cache_profile: Dictionary = await _measure_cold_warm_and_bounds(baseline_script, repo_root.path_join("app/aircraft/timber_visual_details.gd"))
	var helpers: Dictionary = {baseline = baseline_script, candidate = CurrentDetails}
	var warmup: Array = []
	for variant: String in ["baseline", "candidate"]:
		warmup.append(_measure_variant(variant, helpers[variant]))
	var pair_count := 5
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--pairs="):
			pair_count = maxi(2, int(arg.trim_prefix("--pairs=")))
	var paired: Array[Dictionary] = []
	for pair_index in pair_count:
		var order: Array[String] = []
		if pair_index % 2 == 0:
			order = ["baseline", "candidate"]
		else:
			order = ["candidate", "baseline"]
		var measured: Dictionary = {}
		for variant: String in order:
			measured[variant] = _measure_variant(variant, helpers[variant])
		var pair_match: bool = measured.baseline.get("render_signature_sha256", "") == measured.candidate.get("render_signature_sha256", "")
		if not pair_match:
			_errors.append("pair %d: baseline and candidate render signatures differ" % pair_index)
		paired.append({order = order, measurements = measured, render_signatures_match = pair_match})
	var report := {
		schema = "openrc-timber-details-profile v2",
		baseline_source = "research/timber/optimization/details_baseline.gd",
		baseline_source_sha256 = FileAccess.get_sha256(baseline_path),
		candidate_source = "app/aircraft/timber_visual_details.gd",
		candidate_source_sha256 = FileAccess.get_sha256("res://aircraft/timber_visual_details.gd"),
		measurement = "Synchronous CPU construction time; model build is timed separately from VisualDetails.apply, whose timer stops before any native frame flush. The native mode mounts and flushes models only for exact post-render signature comparison; this is not frame time or FPS.",
		cold_warm_and_cache_bounds = cache_profile,
		warmup = warmup,
		paired_alternating_runs = paired,
		failures = _errors,
	}
	var json := JSON.stringify(report, "\t") + "\n"
	var output_path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output_path = arg.trim_prefix("--out=")
	if not output_path.is_empty():
		var absolute_output := output_path if output_path.is_absolute_path() else repo_root.path_join(output_path)
		DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
		var output := FileAccess.open(absolute_output, FileAccess.WRITE)
		if output == null:
			printerr("Could not write profile: ", absolute_output)
			quit(2)
			return
		output.store_string(json)
	if _native_renderer:
		await _release_native_probe_scene()
	print("Timber detail profile: %d alternating pairs; %d failures" % [paired.size(), _errors.size()])
	quit(1 if not _errors.is_empty() else 0)


func _setup_native_probe_scene() -> void:
	root.size = Vector2i(1280, 720)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#9bcef0")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.78, 0.82)
	environment.ambient_light_energy = 0.55
	var world := WorldEnvironment.new()
	world.environment = environment
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_energy = 1.1
	root.add_child(sun)
	var camera := Camera3D.new()
	camera.current = true
	camera.near = 0.02
	camera.far = 400.0
	camera.position = Vector3(1.8, 1.0, 1.8)
	camera.look_at_from_position(camera.position, Vector3.ZERO, Vector3.UP)
	root.add_child(camera)


func _native_mount_and_flush(model_root: Node3D) -> void:
	if not _native_renderer or model_root == null:
		return
	for prior_root: Node3D in _native_roots:
		prior_root.visible = false
	model_root.visible = true
	root.add_child(model_root)
	_native_roots.append(model_root)
	await process_frame
	await RenderingServer.frame_post_draw


func _release_native_probe_scene() -> void:
	for model_root: Node3D in _native_roots:
		if is_instance_valid(model_root):
			model_root.visible = false
			model_root.queue_free()
	_native_roots.clear()
	await process_frame
	await RenderingServer.frame_post_draw


func _measure_cold_warm_and_bounds(baseline_helper: Script, candidate_path: String) -> Dictionary:
	var candidate_helper := GDScript.new()
	candidate_helper.source_code = FileAccess.get_file_as_string(candidate_path) + _cache_probe_source()
	var compile_error := candidate_helper.reload()
	if compile_error != OK:
		_errors.append("isolated candidate helper failed to compile: %d" % compile_error)
		return {compile_error = compile_error}
	var baseline_sample: Dictionary = await _measure_full_apply(baseline_helper)
	var candidate_cold: Dictionary = await _measure_full_apply(candidate_helper, true)
	var candidate_warm: Dictionary = await _measure_full_apply(candidate_helper, true)
	var cold_match: bool = baseline_sample.signature == candidate_cold.signature
	var warm_match: bool = baseline_sample.signature == candidate_warm.signature
	var warm_pair_match: bool = candidate_cold.signature == candidate_warm.signature
	if not cold_match:
		_errors.append("isolated cold candidate result differs from baseline")
	if not warm_match:
		_errors.append("isolated warm candidate result differs from baseline")
	if not warm_pair_match:
		_errors.append("isolated cold and warm candidate results differ")
	var cache_before_change: Dictionary = candidate_helper.call("_optimization_cache_snapshot")
	var transformed_baseline: Dictionary = await _measure_repair_with_cowl_offset(baseline_helper, 0.000137, true)
	var transformed_candidate: Dictionary = await _measure_repair_with_cowl_offset(candidate_helper, 0.000137, true)
	var changed_input_match: bool = transformed_baseline.signature == transformed_candidate.signature
	var cache_after_change: Dictionary = candidate_helper.call("_optimization_cache_snapshot")
	_hide_or_discard(transformed_baseline.root)
	_hide_or_discard(transformed_candidate.root)
	if not changed_input_match:
		_errors.append("candidate cache-miss output differs from baseline after host transform changed")
	var expected_entry_growth := int(cache_after_change.get("paint_repair_entries", 0)) > int(cache_before_change.get("paint_repair_entries", 0))
	if not expected_entry_growth:
		_errors.append("changed host transform did not add a distinct paint-cache entry")
	var capacity := int(cache_after_change.get("paint_repair_capacity", 0))
	for variant_index in range(capacity + 2):
		var offset := 0.0002 + float(variant_index) * 0.000013
		var eviction_sample: Dictionary = await _measure_repair_with_cowl_offset(candidate_helper, offset, false)
		if eviction_sample.root != null:
			_discard_root(eviction_sample.root)
	var cache_after_eviction: Dictionary = candidate_helper.call("_optimization_cache_snapshot")
	var bounded_after_eviction := int(cache_after_eviction.get("paint_repair_entries", 0)) <= capacity
	if not bounded_after_eviction:
		_errors.append("paint repair cache exceeded its declared capacity")
	var eviction_observed := int(cache_after_eviction.get("paint_repair_entries", 0)) == capacity and int(cache_before_change.get("paint_repair_entries", 0)) + capacity + 2 > capacity
	return {
		"native_renderer": DisplayServer.get_name(),
		"project_rendering_method": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown")),
		"baseline_full_apply_usec": baseline_sample.apply_usec,
		"candidate_cold_first_full_apply_usec": candidate_cold.apply_usec,
		"candidate_warm_new_model_full_apply_usec": candidate_warm.apply_usec,
		"model_build_usec": {
			"baseline": baseline_sample.build_usec,
			"candidate_cold": candidate_cold.build_usec,
			"candidate_warm": candidate_warm.build_usec,
		},
		"cold_result_matches_baseline": cold_match,
		"warm_result_matches_baseline": warm_match,
		"cold_and_warm_result_match": warm_pair_match,
		"candidate_cold_cache_after_apply": candidate_cold.cache_snapshot,
		"candidate_warm_cache_after_apply": candidate_warm.cache_snapshot,
		"changed_transform_cache_invalidation": {
			"input_offset_m": 0.000137,
			"baseline_result_matches_candidate": changed_input_match,
			"cache_before": cache_before_change,
			"cache_after": cache_after_change,
			"entry_growth_observed": expected_entry_growth,
		},
		"bounded_eviction_check": {
			"unique_transform_variants_added": capacity + 2,
			"capacity": capacity,
			"cache_after": cache_after_eviction,
			"bounded": bounded_after_eviction,
			"at_capacity_after_eviction_pressure": eviction_observed,
		},
	}


func _cache_probe_source() -> String:
	return "\nstatic func _optimization_cache_snapshot() -> Dictionary:\n" \
		+ "\tvar packed_surface_array_bytes := 0\n" \
		+ "\tvar cached_surface_count := 0\n" \
		+ "\tfor cached_value: Variant in _paint_repair_cache.values():\n" \
		+ "\t\tif not cached_value is Dictionary or not (cached_value as Dictionary).has(\"template\"):\n" \
		+ "\t\t\tcontinue\n" \
		+ "\t\tvar template: Dictionary = (cached_value as Dictionary).template\n" \
		+ "\t\tfor surface: Dictionary in template.get(\"surfaces\", []):\n" \
		+ "\t\t\tcached_surface_count += 1\n" \
		+ "\t\t\tvar arrays: Array = surface.arrays\n" \
		+ "\t\t\tfor channel in Mesh.ARRAY_MAX:\n" \
		+ "\t\t\t\tvar value: Variant = arrays[channel]\n" \
		+ "\t\t\t\tif value != null:\n" \
		+ "\t\t\t\t\tpacked_surface_array_bytes += _packed_array_bytes(value).size()\n" \
		+ "\treturn {\"paint_repair_entries\": _paint_repair_cache.size(), \"paint_repair_capacity\": PAINT_REPAIR_CACHE_CAPACITY, \"paint_repair_cached_surfaces\": cached_surface_count, \"paint_repair_logical_packed_surface_array_bytes_upper_bound\": packed_surface_array_bytes, \"fuselage_sample_entries\": _fuselage_sample_cache.size(), \"fuselage_sample_capacity\": FUSELAGE_SAMPLE_CACHE_CAPACITY}\n"


func _measure_full_apply(helper: Script, capture_cache: bool = false) -> Dictionary:
	var build_started := Time.get_ticks_usec()
	var model: Dictionary = Timber.build()
	var build_usec := Time.get_ticks_usec() - build_started
	var root := _attach_model(model)
	if root == null:
		_errors.append("cold/warm profile model failed to build")
		return {invalid = true, build_usec = build_usec, apply_usec = -1, signature = ""}
	var apply_started := Time.get_ticks_usec()
	helper.call("apply", root)
	var apply_usec := Time.get_ticks_usec() - apply_started
	await _native_mount_and_flush(root)
	var signature := _render_signature(root)
	var render_summary := _last_render_summary.duplicate(true)
	var cache_snapshot: Dictionary = helper.call("_optimization_cache_snapshot") if capture_cache else {}
	if not _native_renderer:
		_discard_root(root)
	return {build_usec = build_usec, apply_usec = apply_usec, signature = signature, render_summary = render_summary, cache_snapshot = cache_snapshot}


func _measure_repair_with_cowl_offset(helper: Script, offset: float, mount_native: bool) -> Dictionary:
	var model: Dictionary = Timber.build()
	var root := _attach_model(model)
	if root == null:
		_errors.append("cache-input fixture model failed to build")
		return {root = null, signature = ""}
	var cowl := root.find_child("cowl", true, false) as Node3D
	if cowl == null:
		_errors.append("cache-input fixture could not find cowl")
	else:
		cowl.position.x += offset
	helper.call("_repair_painted_surface_poke_through", root)
	if mount_native:
		await _native_mount_and_flush(root)
	var signature := _render_signature(root)
	if not mount_native or not _native_renderer:
		return {root = root, signature = signature}
	return {root = root, signature = signature}


func _measure_variant(variant: String, helper: Script) -> Dictionary:
	var phase_build_started := Time.get_ticks_usec()
	var phase_model: Dictionary = Timber.build()
	var phase_build_usec := Time.get_ticks_usec() - phase_build_started
	var phase_root := _attach_model(phase_model)
	if phase_root == null:
		_errors.append(variant + ": phase-profile model failed to build")
		return {variant = variant, invalid = true}
	var phases: Dictionary = {}
	for method_name: String in PHASE_METHODS:
		var started := Time.get_ticks_usec()
		helper.call(method_name, phase_root)
		phases[method_name.trim_prefix("_")] = Time.get_ticks_usec() - started
	var phase_sum_usec := 0
	for elapsed: int in phases.values():
		phase_sum_usec += elapsed
	var phase_signature := _render_signature(phase_root)
	var phase_triangle_summary := _last_triangle_summary.duplicate(true)
	var phase_render_summary := _last_render_summary.duplicate(true)
	var phase_debug := _render_debug_map(phase_root)
	_discard_root(phase_root)

	var apply_build_started := Time.get_ticks_usec()
	var apply_model: Dictionary = Timber.build()
	var apply_build_usec := Time.get_ticks_usec() - apply_build_started
	var apply_root := _attach_model(apply_model)
	if apply_root == null:
		_errors.append(variant + ": full-apply model failed to build")
		return {variant = variant, invalid = true}
	var apply_started := Time.get_ticks_usec()
	helper.call("apply", apply_root)
	var apply_usec := Time.get_ticks_usec() - apply_started
	var apply_signature := _render_signature(apply_root)
	var apply_triangle_summary := _last_triangle_summary.duplicate(true)
	var apply_render_summary := _last_render_summary.duplicate(true)
	var apply_debug := _render_debug_map(apply_root)
	var repeat_started := Time.get_ticks_usec()
	helper.call("apply", apply_root)
	var repeat_apply_usec := Time.get_ticks_usec() - repeat_started
	var repeat_signature := _render_signature(apply_root)
	var signature_match := phase_signature == apply_signature
	var repeat_match := apply_signature == repeat_signature
	if not signature_match:
		_errors.append(variant + ": ordered phase output differs from apply() output")
	if not repeat_match:
		_errors.append(variant + ": repeated apply changed the render signature")
	_discard_root(apply_root)
	return {
		variant = variant,
		phase_model_build_usec = phase_build_usec,
		phase_usec = phases,
		phase_sum_usec = phase_sum_usec,
		full_apply_model_build_usec = apply_build_usec,
		full_apply_usec = apply_usec,
		repeat_apply_usec = repeat_apply_usec,
		phase_and_full_output_match = signature_match,
		repeat_output_match = repeat_match,
		render_signature_sha256 = phase_signature,
		phase_render_summary = phase_render_summary,
		apply_render_summary = apply_render_summary,
		phase_triangle_summary = phase_triangle_summary,
		apply_triangle_summary = apply_triangle_summary,
		phase_apply_debug_diff = _debug_map_differences(phase_debug, apply_debug) if not signature_match else [],
	}


func _attach_model(model: Dictionary) -> Node3D:
	var model_root := model.get("root") as Node3D
	return model_root


func _discard_root(model_root: Node3D) -> void:
	for node: Node in model_root.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).mesh = null
	for node: Node in model_root.find_children("*", "Label3D", true, false):
		(node as Label3D).text = ""
	model_root.free()


func _hide_or_discard(model_root: Node3D) -> void:
	if model_root == null:
		return
	if _native_renderer:
		model_root.visible = false
	else:
		_discard_root(model_root)


func _render_signature(root: Node3D) -> String:
	var ordinary_meshes: Array[Dictionary] = []
	var batched_fasteners: Dictionary = {}
	var ordinary_surface_count := 0
	var ordinary_vertex_count := 0
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		var instance_state := {
			"visible": instance.visible,
			"cast_shadow": instance.cast_shadow,
			"material_override": _material_signature(instance.material_override),
		}
		var batch_group := _fastener_group(instance)
		if batch_group != null:
			var group_path := str(root.get_path_to(batch_group))
			var group_to_mesh := ImportedModel.relative(batch_group, instance)
			var batch: Dictionary = batched_fasteners.get(group_path, {
				"group_transform": _transform_signature(ImportedModel.relative(root, batch_group)),
				"group_visible": batch_group.visible,
				"group_state": _node_state(batch_group),
				"triangles": [],
			})
			var batch_triangles: Array = batch.triangles
			for surface_index in instance.mesh.get_surface_count():
				var surface_arrays := instance.mesh.surface_get_arrays(surface_index)
				var vertices: PackedVector3Array = surface_arrays[Mesh.ARRAY_VERTEX]
				var indices := _triangle_indices(surface_arrays, vertices.size())
				var material_sha := _json_sha256(_material_signature(_active_material(instance, surface_index)))
				var primitive_type := _surface_primitive_type(instance.mesh, surface_index)
				if primitive_type != Mesh.PRIMITIVE_TRIANGLES:
					batch_triangles.append(JSON.stringify({
						"primitive": primitive_type,
						"arrays_sha256": _surface_arrays_sha256(surface_arrays),
						"material": material_sha,
						"state": instance_state,
						"transform": _transform_signature(group_to_mesh),
					}))
					continue
				for triangle_index in range(indices.size() / 3):
					var corners: Array[String] = []
					for vertex_index: int in [indices[triangle_index * 3], indices[triangle_index * 3 + 1], indices[triangle_index * 3 + 2]]:
						corners.append(_vector_payload(group_to_mesh * vertices[vertex_index]))
					batch_triangles.append(JSON.stringify({
						"corners": _canonical_winding_triangle(corners),
						"material": material_sha,
						"visible": instance.visible,
						"cast_shadow": instance.cast_shadow,
					}))
			batch.triangles = batch_triangles
			batched_fasteners[group_path] = batch
			continue
		var mesh_record := {
			"path": str(root.get_path_to(instance)),
			"state": instance_state,
			"transform": _transform_signature(ImportedModel.relative(root, instance)),
			"mesh_resource_name": instance.mesh.resource_name,
			"surfaces": [],
		}
		var surfaces: Array = mesh_record.surfaces
		for surface_index in instance.mesh.get_surface_count():
			var surface_arrays := instance.mesh.surface_get_arrays(surface_index)
			var surface_vertices: PackedVector3Array = surface_arrays[Mesh.ARRAY_VERTEX]
			ordinary_surface_count += 1
			ordinary_vertex_count += surface_vertices.size()
			surfaces.append({
				"primitive": _surface_primitive_type(instance.mesh, surface_index),
				"arrays_sha256": _surface_arrays_sha256(surface_arrays),
				"material": _material_signature(_active_material(instance, surface_index)),
				"vertex_count": surface_vertices.size(),
			})
		ordinary_meshes.append(mesh_record)
	var labels: Array[Dictionary] = []
	for node: Node in root.find_children("*", "Label3D", true, false):
		var label := node as Label3D
		labels.append({
			path = str(root.get_path_to(label)),
			text = label.text,
			transform = _transform_signature(label.transform),
			visible = label.visible,
			modulate = str(label.modulate),
			outline_size = label.outline_size,
			material = _material_signature(label.material_override),
		})
	ordinary_meshes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return JSON.stringify(a) < JSON.stringify(b)
	)
	var batch_summary: Dictionary = {}
	for group_path: String in batched_fasteners:
		var batch: Dictionary = batched_fasteners[group_path]
		var batch_triangles: Array = batch.triangles
		batch_triangles.sort()
		batch.triangle_count = batch_triangles.size()
		batch.sha256 = _string_array_sha256(batch_triangles)
		batch_summary[group_path] = batch
	_last_triangle_summary = batch_summary
	var batched_triangle_count := 0
	for batch: Dictionary in batch_summary.values():
		batched_triangle_count += int(batch.triangle_count)
	_last_render_summary = {
		"unchanged_mesh_instances": ordinary_meshes.size(),
		"unchanged_mesh_surfaces": ordinary_surface_count,
		"unchanged_mesh_vertices": ordinary_vertex_count,
		"batched_fastener_groups": batch_summary.size(),
		"batched_fastener_triangles": batched_triangle_count,
		"labels": labels.size(),
	}
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify({ordinary_meshes = ordinary_meshes, batched_fasteners = batch_summary, labels = labels}).to_utf8_buffer())
	return context.finish().hex_encode()


func _fastener_group(instance: MeshInstance3D) -> Node3D:
	var cursor := instance.get_parent()
	while cursor != null:
		if cursor.name == "TimberHubFasteners":
			return cursor as Node3D
		cursor = cursor.get_parent()
	return null


func _node_state(node: Node3D) -> Dictionary:
	return {"visible": node.visible, "transform": _transform_signature(node.transform)}


func _active_material(instance: MeshInstance3D, surface_index: int) -> Material:
	var material: Material = instance.material_override
	if material == null:
		material = instance.get_surface_override_material(surface_index)
	if material == null:
		material = instance.mesh.surface_get_material(surface_index)
	return material


func _surface_primitive_type(mesh: Mesh, surface_index: int) -> int:
	if mesh is ArrayMesh:
		return (mesh as ArrayMesh).surface_get_primitive_type(surface_index)
	return Mesh.PRIMITIVE_TRIANGLES


func _render_debug_map(root: Node3D) -> Dictionary:
	var result: Dictionary = {}
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		var surfaces: Array[Dictionary] = []
		for surface_index in instance.mesh.get_surface_count():
			var material: Material = instance.material_override
			if material == null:
				material = instance.get_surface_override_material(surface_index)
			if material == null:
				material = instance.mesh.surface_get_material(surface_index)
			surfaces.append({
				"arrays": _surface_arrays_sha256(instance.mesh.surface_get_arrays(surface_index)),
				"material": _json_sha256(_material_signature(material)),
			})
		result[str(root.get_path_to(instance))] = {
			"transform": _transform_signature(ImportedModel.relative(root, instance)),
			"visible": instance.visible,
			"cast_shadow": instance.cast_shadow,
			"surfaces": surfaces,
		}
	return result


func _debug_map_differences(left: Dictionary, right: Dictionary) -> Array[Dictionary]:
	var paths: Dictionary = {}
	for key: String in left.keys():
		paths[key] = true
	for key: String in right.keys():
		paths[key] = true
	var differences: Array[Dictionary] = []
	for key: String in paths:
		var left_record: Dictionary = left.get(key, {})
		var right_record: Dictionary = right.get(key, {})
		if JSON.stringify(left_record) == JSON.stringify(right_record):
			continue
		var surface_differences: Array[Dictionary] = []
		var left_surfaces: Array = left_record.get("surfaces", [])
		var right_surfaces: Array = right_record.get("surfaces", [])
		for surface_index in maxi(left_surfaces.size(), right_surfaces.size()):
			var left_surface: Dictionary = left_surfaces[surface_index] if surface_index < left_surfaces.size() else {}
			var right_surface: Dictionary = right_surfaces[surface_index] if surface_index < right_surfaces.size() else {}
			if JSON.stringify(left_surface) != JSON.stringify(right_surface):
				surface_differences.append({index = surface_index, left = left_surface, right = right_surface})
		differences.append({
			path = key,
			left_transform = left_record.get("transform", ""),
			right_transform = right_record.get("transform", ""),
			left_surface_count = left_surfaces.size(),
			right_surface_count = right_surfaces.size(),
			surfaces = surface_differences,
		})
	return differences


func _triangle_indices(arrays: Array, vertex_count: int) -> PackedInt32Array:
	var source_indices: Variant = arrays[Mesh.ARRAY_INDEX]
	if source_indices is PackedInt32Array and not (source_indices as PackedInt32Array).is_empty():
		return source_indices as PackedInt32Array
	var indices := PackedInt32Array()
	indices.resize(vertex_count)
	for index in vertex_count:
		indices[index] = index
	return indices


func _canonical_winding_triangle(corners: Array[String]) -> String:
	var best := corners[0] + ";" + corners[1] + ";" + corners[2]
	for offset in [1, 2]:
		var candidate := corners[offset] + ";" + corners[(offset + 1) % 3] + ";" + corners[(offset + 2) % 3]
		if candidate < best:
			best = candidate
	return best


func _vector_payload(value: Vector3) -> String:
	return PackedFloat32Array([value.x, value.y, value.z]).to_byte_array().hex_encode()


func _json_sha256(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(value).to_utf8_buffer())
	return context.finish().hex_encode()


func _string_array_sha256(values: Array) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for value in values:
		context.update(String(value).to_utf8_buffer())
		context.update(PackedByteArray([0]))
	return context.finish().hex_encode()


func _surface_arrays_sha256(arrays: Array) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for channel in Mesh.ARRAY_MAX:
		var value: Variant = arrays[channel]
		context.update(PackedInt32Array([channel]).to_byte_array())
		if value == null:
			context.update(PackedByteArray([0]))
			continue
		context.update(PackedByteArray([1]))
		context.update(_packed_array_bytes(value))
	return context.finish().hex_encode()


func _packed_array_bytes(value: Variant) -> PackedByteArray:
	if value is PackedByteArray:
		return value as PackedByteArray
	if value is PackedInt32Array:
		return (value as PackedInt32Array).to_byte_array()
	if value is PackedInt64Array:
		return (value as PackedInt64Array).to_byte_array()
	if value is PackedFloat32Array:
		return (value as PackedFloat32Array).to_byte_array()
	if value is PackedFloat64Array:
		return (value as PackedFloat64Array).to_byte_array()
	if value is PackedVector2Array:
		return (value as PackedVector2Array).to_byte_array()
	if value is PackedVector3Array:
		return (value as PackedVector3Array).to_byte_array()
	if value is PackedVector4Array:
		return (value as PackedVector4Array).to_byte_array()
	if value is PackedColorArray:
		return (value as PackedColorArray).to_byte_array()
	if value is Array:
		return JSON.stringify(value).to_utf8_buffer()
	return str(value).to_utf8_buffer()


func _material_signature(material: Material) -> Dictionary:
	if material == null:
		return {}
	var properties: Dictionary = {}
	for property: Dictionary in material.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var property_name := String(property.name)
		var value: Variant = material.get(property_name)
		if value is Resource:
			var resource := value as Resource
			properties[property_name] = {
				"class": resource.get_class(),
				"name": resource.resource_name,
				"path": resource.resource_path,
			}
		else:
			properties[property_name] = str(value) if typeof(value) in [TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_COLOR, TYPE_BASIS, TYPE_TRANSFORM3D] else value
	return {"class": material.get_class(), "name": material.resource_name, "properties": properties}


func _transform_signature(transform: Transform3D) -> String:
	var basis := transform.basis
	var values := PackedFloat32Array([
		basis.x.x, basis.x.y, basis.x.z,
		basis.y.x, basis.y.y, basis.y.z,
		basis.z.x, basis.z.y, basis.z.z,
		transform.origin.x, transform.origin.y, transform.origin.z,
	])
	return values.to_byte_array().hex_encode()
