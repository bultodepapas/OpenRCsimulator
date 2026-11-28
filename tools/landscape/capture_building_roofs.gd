## Native field-only roof review. Run with --out=<absolute directory> [--replace] [--normal-footprint=on].
extends SceneTree

const Field := preload("res://render/field.gd")
const Loader := preload("res://data/field_loader.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const Frames := preload("res://render/frames.gd")
const Clock := preload("res://render/shader_clock.gd")

const VIEWS := [
	{name = "club_air", eye = [10.0, 34.0, -27.0], at = [-22.0, 0.0, -2.3], fov = 42.0},
	{name = "pavilion_pilot", eye = [-4.0, 14.0, -1.7], at = [-21.0, -2.0, -2.0], fov = 46.0},
	{name = "pavilion_roof", eye = [-12.0, 14.0, -11.0], at = [-22.0, 0.0, -3.0], fov = 43.0},
	{name = "shed_roof", eye = [-27.0, -21.0, -8.0], at = [-40.5, -33.5, -1.5], fov = 42.0},
	{name = "farm_roofs", eye = [450.0, 160.0, -75.0], at = [610.0, 365.0, -3.0], fov = 55.0},
]

# Each eye sits 2 m along the outward roof normal. The pavilion target is halfway up
# the +Z slate face; the shelter target is on the flat pan between two standing seams.
const NORMAL_VIEWS := [
	{name = "pavilion_normal_footprint", eye = [-24.664696, 0.0, -5.546576], at = [-23.75, 0.0, -3.768], fov = 42.0,
		mesh_node = "Roof_prop_pavilion_00_slate", shader = "res://scenery/building_roofs.gdshader"},
	{name = "pit_normal_footprint", eye = [-18.999007, -30.623684, -5.110074], at = [-18.8, -30.623684, -3.12], fov = 42.0,
		mesh_node = "PitShelter_prop_pit-shelters_00", shader = "res://scenery/pit_shelter_roof.gdshader"},
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := ""
	var replace := false
	var normal_views := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg == "--replace":
			replace = true
		elif arg == "--normal-footprint=on":
			normal_views = true
	if out.is_empty() or (FileAccess.file_exists(out.path_join("capture.json")) and not replace):
		push_error("--out must name a new capture directory unless --replace is set")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	OS.set_environment("OPENRC_SCENERY", "on")
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	OS.set_environment("OPENRC_SCENERY_BIRDS", "off")
	Clock.register()
	Clock.update(0.0)
	RenderingServer.render_loop_enabled = false
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var loaded := Loader.load_from()
	if not loaded.ok:
		push_error(str(loaded.errors))
		quit(1)
		return
	var field := Field.build(loaded.field)
	if field.get_node_or_null("Scenery") == null:
		push_error("Production scenery did not attach; refusing an empty-field capture")
		field.free()
		quit(1)
		return
	viewport.add_child(field)
	var environment := WorldEnvironment.new()
	environment.environment = Atmosphere.environment()
	field.add_child(environment)
	Atmosphere.create_sun(field)
	var camera := Camera3D.new()
	camera.near = 0.03
	camera.far = 21000.0
	camera.current = true
	field.add_child(camera)
	var records := []
	var rid := viewport.get_viewport_rid()
	var views := VIEWS.duplicate()
	if normal_views:
		views.append_array(NORMAL_VIEWS)
	for view: Dictionary in views:
		camera.position = Frames.ned_to_render(view.eye)
		camera.look_at(Frames.ned_to_render(view.at))
		camera.fov = view.fov
		for frame in 30:
			await process_frame
			RenderingServer.force_draw(false)
		var path := out.path_join(str(view.name) + ".png")
		if viewport.get_texture().get_image().save_png(path) != OK:
			push_error("Failed to save " + path)
			quit(1)
			return
		var record := {"view": view.name, "eye_ned": view.eye, "at_ned": view.at,
			"fov": view.fov, "sha256": FileAccess.get_sha256(path),
			"draws": RenderingServer.viewport_get_render_info(rid,
				RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
				RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)}
		if view.has("mesh_node"):
			var footprint := _normal_footprint(field, camera, viewport.size, view)
			if footprint.is_empty():
				push_error("Roof close-up missed its expected material or UV footprint: " + str(view.name))
				quit(1)
				return
			record.normal_footprint = footprint
		records.append(record)
	var report := {"complete": true, "adapter": RenderingServer.get_video_adapter_name(),
		"method": RenderingServer.get_current_rendering_method(), "records": records}
	var file := FileAccess.open(out.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	field.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	quit()


# Sample the actual material UVs at three adjacent pixel centres on the target mesh.
func _normal_footprint(field: Node3D, camera: Camera3D, size: Vector2i, view: Dictionary) -> Dictionary:
	var node := field.find_child(view.mesh_node, true, false) as MeshInstance3D
	if node == null or not node.is_visible_in_tree() or node.mesh == null or node.mesh.get_surface_count() != 1:
		return {}
	var material := node.get_active_material(0) as ShaderMaterial
	if material == null or material.shader == null or material.shader.resource_path != view.shader:
		return {}
	var triangles := node.mesh.generate_triangle_mesh()
	if triangles == null:
		return {}
	var arrays := node.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv := PackedVector2Array()
	var first_distance := 0.0
	for step: Vector2 in [Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN]:
		var pixel := Vector2(size) * 0.5 + Vector2(0.5, 0.5) + step
		var origin := node.to_local(camera.project_ray_origin(pixel))
		var direction := node.global_transform.basis.inverse() * camera.project_ray_normal(pixel)
		var hit := triangles.intersect_ray(origin, direction.normalized())
		if hit.is_empty():
			return {}
		var position: Vector3 = hit.position
		var index := int(hit.face_index) * 3
		var ids := Vector3i(index, index + 1, index + 2)
		if arrays[Mesh.ARRAY_INDEX] != null:
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			ids = Vector3i(indices[ids.x], indices[ids.y], indices[ids.z])
		if view.shader == "res://scenery/building_roofs.gdshader":
			var weights := Geometry3D.get_triangle_barycentric_coords(position, vertices[ids.x], vertices[ids.y], vertices[ids.z])
			var coords: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			uv.append(coords[ids.x] * weights.x + coords[ids.y] * weights.y + coords[ids.z] * weights.z)
		else:
			# The shelter's magenta top faces use shader-projected local X/Z coordinates.
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			if colors[ids.x] != Color.MAGENTA or colors[ids.y] != Color.MAGENTA or colors[ids.z] != Color.MAGENTA:
				return {}
			var value: Variant = material.get_shader_parameter("roof_tile_size_m")
			if value == null:
				value = RenderingServer.shader_get_parameter_default(material.shader.get_rid(), "roof_tile_size_m")
			if not value is Vector2:
				return {}
			var tile: Vector2 = value
			if tile.x <= 0.0 or tile.y <= 0.0:
				return {}
			uv.append(Vector2(position.x, position.z) / tile)
		if step == Vector2.ZERO:
			first_distance = camera.global_position.distance_to(node.to_global(position))
	var determinant := absf((uv[1] - uv[0]).cross(uv[2] - uv[0]))
	if absf(first_distance - 2.0) > 0.01 or determinant <= 0.0 or determinant >= 1e-6:
		return {}
	return {"mesh_node": str(node.name), "shader": material.shader.resource_path, "viewport": [size.x, size.y],
		"center_distance_m": first_distance, "uv_det_abs": determinant}
