# Run with --path research/avanti-s/av02 --script ../alignment/render.gd.
extends SceneTree

const Model := preload("res://model.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output-dir="): output = arg.trim_prefix("--output-dir=")
	if output.is_empty() or DirAccess.dir_exists_absolute(output):
		push_error("Provide a new --output-dir=PATH"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	var fit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../alignment/camera-fit.json"))
	var picks: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../alignment/picks.json"))
	if FileAccess.get_sha256("res://geometry.json") != fit.model_geometry_sha256:
		push_error("Geometry changed after camera fit"); quit(2); return
	get_root().transparent_bg = true
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	var model := Model.build()
	get_root().add_child(model.root)
	# Flat cyan helps separate silhouettes from the photo, independent of scene lighting.
	for child in model.root.find_children("*", "MeshInstance3D", true, false):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color("18dcea")
		child.material_override = mat
	var camera := Camera3D.new()
	get_root().add_child(camera)
	camera.current = true
	var records := []
	for view in fit.views:
		get_root().size = Vector2i(view.size_px[0], view.size_px[1])
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		camera.fov = view.assumed_vertical_fov_deg
		camera.position = Model.point(view.camera_position_m)
		var columns: Array = view.camera_basis_columns
		camera.basis = Basis(Model.point(columns[0]), Model.point(columns[1]), Model.point(columns[2]))
		for frame in 3: await process_frame
		await RenderingServer.frame_post_draw
		var filename: String = view.id + ".png"
		var error := get_root().get_texture().get_image().save_png(output.path_join(filename))
		if error != OK: push_error("Save failed"); quit(1); return
		var projected := {}
		var max_error := 0.0
		for landmark in view.landmarks:
			var actual := camera.unproject_position(Model.point(picks.landmarks_m[landmark.key]))
			var expected := Vector2(landmark.projected_px[0], landmark.projected_px[1])
			max_error = maxf(max_error, actual.distance_to(expected))
			projected[landmark.key] = [actual.x, actual.y]
		records.append({id = view.id, file = filename, sha256 = FileAccess.get_sha256(output.path_join(filename)),
			godot_projection_px = projected, scipy_projection_max_delta_px = max_error})
		if max_error > .05: push_error("Projection conversion mismatch: %s" % max_error); quit(1); return
	var report := FileAccess.open(output.path_join("render-manifest.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({godot = Engine.get_version_info().string,
		fit_sha256 = FileAccess.get_sha256("res://../alignment/camera-fit.json"),
		model_sha256 = FileAccess.get_sha256("res://model.gd"), captures = records}, "\t") + "\n")
	print("Aligned transparent captures: %s" % records.size())
	quit()
