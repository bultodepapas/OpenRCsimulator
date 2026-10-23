## Fixed native views of the Club lake bank without loading an aircraft session.
extends SceneTree

const Field := preload("res://render/field.gd")
const Loader := preload("res://data/field_loader.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const Frames := preload("res://render/frames.gd")
const Clock := preload("res://render/shader_clock.gd")

const VIEWS := [
	{"name": "lake_shore", "eye": [78.0, 113.0, -1.5], "at": [112.0, 130.0, 0.45], "fov": 58.0},
	{"name": "bank_detail", "eye": [76.0, 110.0, -1.6], "at": [79.0, 112.0, 0.2], "fov": 48.0},
	{"name": "lake_overview", "eye": [45.0, 50.0, -45.0], "at": [110.0, 125.0, 0.45], "fov": 55.0},
	{"name": "lily_detail", "eye": [77.0, 121.0, -3.5], "at": [87.0, 129.0, 0.45], "fov": 55.0},
	{"name": "lily_wave_3s", "eye": [77.0, 121.0, -3.5], "at": [87.0, 129.0, 0.45], "fov": 55.0, "clock_s": 3.0},
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := ""
	var replace := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg == "--replace":
			replace = true
	if out.is_empty() or (FileAccess.file_exists(out.path_join("capture.json")) and not replace):
		push_error("--out must name a directory without an existing capture.json unless --replace is set")
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
	viewport.size = Vector2i(1920, 1080)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var loaded := Loader.load_from()
	if not loaded.ok:
		push_error(str(loaded.errors))
		quit(1)
		return
	var field := Field.build(loaded.field)
	if not field.has_node("Lake/Basin"):
		push_error("Club field has no rendered lake basin")
		quit(1)
		return
	var bank_material := (field.get_node("Lake/Basin") as MeshInstance3D).material_override as ShaderMaterial
	if bank_material == null or not bank_material.get_shader_parameter("rc_dirt_albedo") is Texture2D \
			or not bank_material.get_shader_parameter("rc_dirt_normal") is Texture2D \
			or not bank_material.get_shader_parameter("rc_dirt_roughness") is Texture2D \
			or not bank_material.get_shader_parameter("rc_grass_albedo") is Texture2D \
			or not bank_material.get_shader_parameter("rc_grass_normal") is Texture2D \
			or not bank_material.get_shader_parameter("rc_grass_roughness") is Texture2D \
			or not bank_material.get_shader_parameter("turf_detail") is Texture2D \
			or bank_material.get_shader_parameter("grass_photo_enabled") != true \
			or float(bank_material.get_shader_parameter("turf_detail_strength")) <= 0.0:
		push_error("Club lake bank is missing the field grass or soil textures")
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
	for view: Dictionary in VIEWS:
		Clock.update(float(view.get("clock_s", 0.0)))
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
		records.append({"view": view.name, "eye_ned": view.eye, "at_ned": view.at,
			"clock_s": float(view.get("clock_s", 0.0)),
			"fov": view.fov, "sha256": FileAccess.get_sha256(path),
			"draws": RenderingServer.viewport_get_render_info(rid,
				RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
				RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)})
	var report := {"complete": true, "adapter": RenderingServer.get_video_adapter_name(),
		"viewport": [1920,1080], "lily_shader_sha256": FileAccess.get_sha256("res://render/lake/lily_pad.gdshader"), "method": RenderingServer.get_current_rendering_method(), "records": records,
		"bank_shader_sha256": FileAccess.get_sha256("res://render/lake/bank.gdshader"),
		"bank_builder_sha256": FileAccess.get_sha256("res://render/lake/lake_terrain.gd")}
	var file := FileAccess.open(out.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	field.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	print("lily capture complete")
	quit()
