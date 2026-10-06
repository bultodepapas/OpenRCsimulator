# Isolated asset experiment, never loaded by the simulator.
extends SceneTree

const NAMES := ["tree_default", "tree_oak", "tree_pineTallA"]
var scene: Node3D
var models: Node3D
var camera: Camera3D
var results: Array[Dictionary] = []
var meshes: Array[Mesh] = []
var mesh_transforms: Array[Transform3D] = []
var out_dir := ""
var failed := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	call_deferred("run_probe")

func first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := first_mesh(child)
		if found != null:
			return found
	return null

func mesh_details(mesh: Mesh) -> Dictionary:
	var triangles := 0
	var materials: Array[Dictionary] = []
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		triangles += a[Mesh.ARRAY_INDEX].size() / 3 if a[Mesh.ARRAY_INDEX].size() > 0 else a[Mesh.ARRAY_VERTEX].size() / 3
		var m := mesh.surface_get_material(s) as StandardMaterial3D
		materials.append({"name": m.resource_name, "shading_mode": m.shading_mode, "albedo": str(m.albedo_color), "metallic": m.metallic, "roughness": m.roughness})
	return {"triangles": triangles, "surfaces": mesh.get_surface_count(), "aabb": str(mesh.get_aabb()), "materials": materials}

# This adapter only supports these opaque, untextured, static meshes (translation retained).
# It is not a general optimizer and must not be used on an articulated aircraft.
func merged_colors(mesh: Mesh, natural: bool = false) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var m := mesh.surface_get_material(s) as StandardMaterial3D
		assert(m.albedo_texture == null and m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED)
		var offset := vertices.size()
		vertices.append_array(a[Mesh.ARRAY_VERTEX])
		normals.append_array(a[Mesh.ARRAY_NORMAL])
		var color := m.albedo_color
		if natural:
			color = Color("66824b") if m.resource_name.begins_with("leafs") else Color("68513c")
		for _v in a[Mesh.ARRAY_VERTEX].size():
			# Match the imported albedo in Compatibility; SRGB vertex flag has no effect here.
			# Forward+/Mobile need their own color-space A/B before sharing this adapter.
			colors.append(color)
		for index in a[Mesh.ARRAY_INDEX]:
			indices.append(index + offset)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var merged := ArrayMesh.new()
	merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = (mesh.surface_get_material(0) as StandardMaterial3D).shading_mode
	material.metallic = 0.0 if natural else (mesh.surface_get_material(0) as StandardMaterial3D).metallic
	material.roughness = (mesh.surface_get_material(0) as StandardMaterial3D).roughness
	merged.surface_set_material(0, material)
	return merged

func reset_models() -> void:
	if models != null:
		models.free()
	models = Node3D.new()
	scene.add_child(models)

func capture(label: String, details: Dictionary = {}) -> void:
	for _frame in 6:
		await process_frame
		await RenderingServer.frame_post_draw
	var path := out_dir.path_join(label + ".png")
	var error := root.get_texture().get_image().save_png(path)
	failed = failed or error != OK
	details.merge({"case": label, "png_sha256": FileAccess.get_sha256(path), "save_error": error,
		"draw_calls": root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"primitives": root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)})
	results.append(details)
	print(JSON.stringify(details))

func run_probe() -> void:
	assert(not out_dir.is_empty())
	DirAccess.make_dir_recursive_absolute(out_dir)
	scene = Node3D.new()
	root.add_child(scene)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.4
	camera.position = Vector3(0, 2.7, 9)
	scene.add_child(camera)
	camera.look_at(Vector3(0, 0.95, 0))
	camera.current = true
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.58, 0.7, 0.82)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.5
	scene.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -25, 0)
	sun.shadow_enabled = false
	scene.add_child(sun)
	for variant in ["source", "optimized"]:
		reset_models()
		var stats: Array[Dictionary] = []
		for i in NAMES.size():
			var packed := load("res://%s/%s.glb" % [variant, NAMES[i]]) as PackedScene
			assert(packed != null)
			var instance := packed.instantiate() as Node3D
			models.add_child(instance)
			var mesh_node := first_mesh(instance)
			assert(mesh_node != null)
			# No rotation/scale in the selected source hierarchy; retain its root offset.
			assert(mesh_node.global_basis.is_equal_approx(Basis.IDENTITY))
			var original_transform := mesh_node.global_transform
			instance.position.x = (i - 1) * 2.0
			stats.append(mesh_details(mesh_node.mesh))
			if variant == "optimized":
				meshes.append(mesh_node.mesh)
				mesh_transforms.append(original_transform)
		await capture(variant, {"meshes": stats})
	reset_models()
	for i in meshes.size():
		var node := MeshInstance3D.new()
		node.mesh = merged_colors(meshes[i])
		node.transform = mesh_transforms[i]
		node.position.x += (i - 1) * 2.0
		models.add_child(node)
	await capture("merged-colors")
	for i in meshes.size():
		models.get_child(i).mesh = merged_colors(meshes[i], true)
	await capture("adapted-palette")
	# Draw-call stress fixture: all 8 groups × 3 species are visible; no terrain/shadows.
	# It is not the field distribution, a culling test, or an FPS benchmark.
	camera.size = 24
	camera.position = Vector3(0, 30, 38)
	camera.look_at(Vector3(0, 0, 0))
	for merge in [false, true]:
		reset_models()
		for group in 8:
			for species in 3:
				var node := MultiMeshInstance3D.new()
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = merged_colors(meshes[species]) if merge else meshes[species]
				mm.instance_count = 20
				for i in 20:
					var p := Vector3((group - 3.5) * 4.4 + (i % 4) * 0.65, 0, (species - 1) * 6.0 + (i / 4) * 0.7)
					mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, p) * mesh_transforms[species])
				node.multimesh = mm
				models.add_child(node)
		await capture("multimesh-merged" if merge else "multimesh-source", {"instances": 480, "groups": 24})
	var file := FileAccess.open(out_dir.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine": Engine.get_version_info(), "renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(), "resolution": [960, 540], "performance_benchmark": false,
		"results": results}, "  ") + "\n")
	file.close()
	quit(1 if failed else 0)
