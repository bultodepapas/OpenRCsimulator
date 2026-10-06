# Transparent, flat-cyan orthographic renders of the P-51D model with the cameras of camera-fit.json, one PNG per view
# at the drawing crop's pixel size, so review.py can lay them over the AN 01-60-3 three-view without resampling.
# Run from the repo root (needs a display, e.g. xvfb-run):
#   godot --path app --rendering-driver opengl3 --audio-driver Dummy \
#     --script res://../research/p51/p51-02/silhouette/render.gd -- --output-dir=/new/dir [--compare-geometry]
extends SceneTree

const P51 := preload("res://aircraft/p51d_model.gd")
const DEFAULT_FIT := "res://../research/p51/p51-02/silhouette/camera-fit.json"


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var output := ""
	var compare := false
	var fit_path := DEFAULT_FIT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output-dir="): output = arg.trim_prefix("--output-dir=")
		if arg == "--compare-geometry": compare = true
		if arg.begins_with("--fit="): fit_path = arg.trim_prefix("--fit=") # e.g. the photo fit in photo/camera-fit.json
	if output.is_empty() or DirAccess.dir_exists_absolute(output):
		push_error("Provide a new --output-dir=PATH"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	var fit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fit_path))
	var geometry_sha := FileAccess.get_sha256("res://../assets/aircraft/p51d-mustang-120/geometry.json")
	if geometry_sha != fit.model_geometry_sha256 and not compare:
		push_error("Geometry changed after the camera fit (pass --compare-geometry to render anyway)"); quit(2); return
	get_root().transparent_bg = true
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	var model := P51.build()
	get_root().add_child(model.root)
	# Flat, unshaded cyan: the silhouette is independent of lighting and the canopy counts as body.
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("18dcea")
	for child in model.root.find_children("*", "MeshInstance3D", true, false):
		child.material_override = mat
	# Propeller blades are not drawn in the comparison (the drawing shows them in other positions).
	model.propeller.visible = false
	var camera := Camera3D.new()
	get_root().add_child(camera)
	camera.current = true
	camera.near = 0.05
	camera.far = 100.0
	var records := []
	for view in fit.views:
		get_root().size = Vector2i(int(view.size_px[0]), int(view.size_px[1]))
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		if view.get("projection", "orthographic") == "perspective":
			camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			camera.fov = view.assumed_vertical_fov_deg
		else:
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = view.orthographic_size_m
		var p: Array = view.camera_position_m
		camera.position = Vector3(p[0], p[1], p[2])
		var c: Array = view.camera_basis_columns
		camera.basis = Basis(Vector3(c[0][0], c[0][1], c[0][2]), Vector3(c[1][0], c[1][1], c[1][2]), Vector3(c[2][0], c[2][1], c[2][2]))
		for frame in 3: await process_frame
		await RenderingServer.frame_post_draw
		var filename: String = view.id + ".png"
		if get_root().get_texture().get_image().save_png(output.path_join(filename)) != OK:
			push_error("Save failed"); quit(1); return
		# Anchor check. Orthographic drawing views: the model landmarks must project onto their picked pixels (1 px).
		# Perspective photo fits: Godot's projection must agree with SciPy's fitted projection (0.5 px); the residual
		# against the picks is the fit's own RMS, recorded in camera-fit.json.
		var perspective: bool = view.get("projection", "orthographic") == "perspective"
		var worst := 0.0
		var projected := {}
		for key in view.anchors:
			var a: Dictionary = view.anchors[key]
			var m: Array = a.model_m
			var px := camera.unproject_position(Vector3(m[0], m[1], m[2]))
			projected[key] = [px.x, px.y]
			var want: Array = a.picked_px
			if perspective:
				for l in view.landmarks:
					if l.key == key: want = l.projected_px
			var dx: float = px.x - float(want[0])
			var dy: float = (px.y - float(want[1])) if want[1] != null else 0.0
			worst = maxf(worst, sqrt(dx * dx + dy * dy))
		records.append({id = view.id, file = filename, sha256 = FileAccess.get_sha256(output.path_join(filename)), anchor_projection_px = projected, anchor_max_error_px = worst})
		if worst > (0.5 if perspective else 1.0):
			push_error("Anchor projection mismatch in %s: %.2f px" % [view.id, worst]); quit(1); return
	var report := FileAccess.open(output.path_join("render-manifest.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({godot = Engine.get_version_info().string, geometry_sha256 = geometry_sha,
		calibration_geometry_sha256 = fit.model_geometry_sha256, comparison_with_frozen_camera = compare,
		fit_sha256 = FileAccess.get_sha256(fit_path), model_sha256 = FileAccess.get_sha256("res://aircraft/p51d_model.gd"),
		visual_revision = model.root.get_meta("visual_revision"), captures = records}, "\t") + "\n")
	print("Aligned transparent captures: %s" % records.size())
	quit()
