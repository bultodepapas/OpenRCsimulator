## TT-21: isolated, paired native renderer observations; no simulation or gameplay.
extends SceneTree

const Timber := preload("res://aircraft/timber_model.gd")
const Details := preload("res://aircraft/timber_visual_details.gd")
const Lighting := preload("res://aircraft/timber_visual_lighting.gd")
const Inspector := preload("res://aircraft/inspect_timber.gd")
const Diagnostics := preload("res://render/frame_diagnostics.gd")

var _out := ""
var _originals: Array[MeshInstance3D] = []
var _batches: Array[MeshInstance3D] = []
var _records: Array[Dictionary] = []
var _diag: RefCounted
var _camera: Camera3D
var _models: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _arg(key: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--" + key + "="):
			return arg.trim_prefix("--" + key + "=")
	return fallback

func _run() -> void:
	_out = _arg("out", "")
	var mode := _arg("mode", "prototype")
	if _out.is_empty() or DirAccess.dir_exists_absolute(_out) or DisplayServer.get_name() == "headless":
		push_error("Native display and fresh --out directory required")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(1280, 720)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#9bcef0")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.82)
	env.ambient_light_energy = 0.55
	var world := WorldEnvironment.new()
	world.environment = env
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.1
	root.add_child(sun)
	_camera = Camera3D.new()
	_camera.near = 0.02
	_camera.far = 400.0
	_camera.current = true
	root.add_child(_camera)
	var repo := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
	var baseline_path := repo.path_join("research/timber/optimization/details_baseline.gd")
	var baseline := GDScript.new()
	baseline.source_code = FileAccess.get_file_as_string(baseline_path)
	if baseline.reload() != OK:
		quit(2)
		return
	var plane: Dictionary = Timber.build()
	baseline.call("apply", plane.root)
	Lighting.apply(plane.root)
	root.add_child(plane.root)
	_models.baseline = plane
	var merge_record := {}
	if mode == "prototype":
		merge_record = _prepare_batches(plane.root)
		_models.candidate = plane
	else:
		var candidate_helper: Script = baseline if mode == "control" else Details
		if _arg("warm", "false") == "true":
			var warmup: Dictionary = Timber.build()
			candidate_helper.call("apply", warmup.root)
			root.add_child(warmup.root)
			for i in 3:
				await process_frame
				await RenderingServer.frame_post_draw
			warmup.root.queue_free()
			await process_frame
		var candidate: Dictionary = Timber.build()
		candidate_helper.call("apply", candidate.root)
		Lighting.apply(candidate.root)
		root.add_child(candidate.root)
		_models.candidate = candidate
	_diag = Diagnostics.new()
	_diag.start(root)
	var selected: Array = Inspector.views("inspection").filter(func(v: Dictionary) -> bool:
		return v.name in ["inspection_gear_front", "inspection_nose_left", "inspection_oblique_front_left", "inspection_oblique_rear_right_full"])
	selected.append(Inspector.views("distance")[0])
	for pair in 3:
		var order := ["baseline", "candidate"] if pair % 2 == 0 else ["candidate", "baseline"]
		for view: Dictionary in selected:
			for variant: String in order:
				await _measure(variant, view, pair, mode)
	var report := {
		format = "openrc-timber-native-render-profile v1", mode = mode,
		baseline_sha256 = FileAccess.get_sha256(baseline_path),
		candidate_sha256 = FileAccess.get_sha256("res://aircraft/timber_visual_details.gd"),
		candidate_uses_baseline_helper = mode == "control",
		candidate_cache_warmed = _arg("warm", "false") == "true",
		lighting_sha256 = FileAccess.get_sha256("res://aircraft/timber_visual_lighting.gd"),
		detail_data_sha256 = FileAccess.get_sha256("res://assets/aircraft/turbo-lumber-evolution/visual-upgrade/visual_detail_data.gd"),
		model_sha256 = FileAccess.get_sha256("res://aircraft/timber_model.gd"),
		asset_sha256 = FileAccess.get_sha256("res://assets/aircraft/turbo-lumber-evolution/timber.glb"),
		probe_sha256 = FileAccess.get_sha256(get_script().resource_path),
		engine = Engine.get_version_info(), diagnostics = _diag.metadata(),
		merge = merge_record, samples = _records,
		method = "Same process, alternating baseline/candidate order, 5 fixed views, 3 pairs, 12 warmup and 24 measured native frames per view; median timings are observations under a shared active desktop, not an FPS guarantee. No scenery, simulation, crash bodies or other aircraft are included.",
		settings = {resolution = [1280,720], sun_rotation_deg = [-50,-35,0], sun_energy = 1.1, ambient_energy = 0.55},
	}
	_diag.stop()
	var file := FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	print("TT-21 native render profile: ", _records.size(), " measurements saved to ", _out)
	quit(0)

func _prepare_batches(aircraft: Node3D) -> Dictionary:
	var old_vertices := 0
	var new_vertices := 0
	var max_position_error := 0.0
	for group: Node3D in aircraft.find_children("TimberHubFasteners", "Node3D", true, false):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var expected := PackedVector3Array()
		var material: Material
		for bolt: MeshInstance3D in group.get_children():
			_originals.append(bolt)
			material = bolt.get_active_material(0)
			surface.append_from(bolt.mesh, 0, bolt.transform)
			var vertices: PackedVector3Array = bolt.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				expected.append(bolt.transform * vertex)
			old_vertices += vertices.size()
		surface.set_material(material)
		var mesh := surface.commit()
		var actual: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		new_vertices += actual.size()
		if expected.size() != actual.size():
			max_position_error = INF
		else:
			for i in actual.size():
				max_position_error = maxf(max_position_error, expected[i].distance_to(actual[i]))
		var batch := MeshInstance3D.new()
		batch.name = "HubFastenersBatched"
		batch.mesh = mesh
		batch.set_meta("crash_no_bounds", true)
		group.add_child(batch)
		_batches.append(batch)
	return {original_instances = _originals.size(), batched_instances = _batches.size(), original_vertices = old_vertices, batched_vertices = new_vertices, max_transformed_vertex_error_m = max_position_error}

func _measure(variant: String, view: Dictionary, pair: int, mode: String) -> void:
	if mode == "prototype":
		for bolt in _originals: bolt.visible = variant == "baseline"
		for batch in _batches: batch.visible = variant == "candidate"
	else:
		_models.baseline.root.visible = variant == "baseline"
		_models.candidate.root.visible = variant == "candidate"
	var plane: Dictionary = _models[variant]
	Timber.apply_controls(plane, view.controls.roll, view.controls.pitch, view.controls.yaw, view.controls.flap)
	plane.propeller.rotation = Vector3.ZERO
	for key in ["left", "right", "tail", "steering"]: plane.gear[key].rotation = Vector3.ZERO
	plane.root.rotation_degrees = view.attitude_deg
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL if view.projection == "ortho" else Camera3D.PROJECTION_PERSPECTIVE
	_camera.size = Inspector.ortho_size_m()
	_camera.fov = view.fov
	_camera.look_at_from_position(view.position, view.target, view.up)
	for i in 12:
		await process_frame
		await RenderingServer.frame_post_draw
	var frames: Array[Dictionary] = []
	for i in 24:
		await process_frame
		await RenderingServer.frame_post_draw
		var sample: Dictionary = _diag.sample()
		sample.visible_draw_calls = root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		sample.visible_primitives = root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
		sample.visible_objects = root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME)
		frames.append(sample)
	var filename := "%s_%s_%d.png" % [view.name, variant, pair]
	root.get_texture().get_image().save_png(_out.path_join(filename))
	_records.append({variant = variant, view = view.name, pair = pair, image = filename, image_sha256 = FileAccess.get_sha256(_out.path_join(filename)), frames = frames})
