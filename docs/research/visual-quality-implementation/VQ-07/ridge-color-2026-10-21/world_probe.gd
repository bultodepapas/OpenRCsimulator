## Native production-World ridge comparison. No aircraft physics or performance claim.
## -- <new absolute output directory> <absolute baseline ridge shader path>
extends SceneTree

const World := preload("res://render/world/world.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Conditions := preload("res://render/world/conditions.gd")
const High := preload("res://render/high_graphics_profile.gd")
const Candidate := preload("res://render/landscape_upgrade/ridge_haze.gdshader")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or not args[0].is_absolute_path() or not FileAccess.file_exists(args[1]) \
			or DirAccess.dir_exists_absolute(args[0]) or DisplayServer.get_name() == "headless":
		printerr("ridge World probe requires native display, new absolute output dir and baseline shader")
		quit(2)
		return
	var output := args[0]
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		quit(2)
		return
	var baseline := Shader.new()
	baseline.code = FileAccess.get_file_as_string(args[1])
	var loaded := FieldLoader.load_from()
	if not loaded.ok:
		quit(1)
		return
	OS.set_environment("OPENRC_SCENERY", "on")
	OS.set_environment("OPENRC_SCENERY_QUALITY", "high")
	OS.set_environment("OPENRC_SCENERY_FILE", "")
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	OS.set_environment("OPENRC_LAKE", "on")
	Atmosphere.engine_shadows = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.render_loop_enabled = false
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var reports := []
	for hour: String in ["15:00", "19:30", "21:00"]:
		for variant: String in ["before", "after"]:
			var holder := Node3D.new()
			viewport.add_child(holder)
			var built := World.build(holder, loaded.field, Callable(), Conditions.resolve(
				PackedStringArray(["--date=2026-09-26", "--time=" + hour, "--time_scale=20"])))
			var ridge: Node3D = built.field.get_node("DistantRidges")
			var material: ShaderMaterial = ridge.get_meta("lighting_material")
			var parameters := {}
			for uniform: Dictionary in material.shader.get_shader_uniform_list():
				parameters[uniform.name] = material.get_shader_parameter(uniform.name)
			material.shader = baseline if variant == "before" else Candidate
			for key: StringName in parameters:
				material.set_shader_parameter(key, parameters[key])
			var camera := Camera3D.new()
			camera.fov = 50.0
			camera.far = 21000.0
			camera.current = true
			holder.add_child(camera)
			for frame in [0, 60]:
				var t := float(frame) / 60.0
				World.update(built.environment, t)
				for view: String in ["lake", "pilot"]:
					camera.position = Vector3(90.0 + t * 2.0, 5.0, -80.0) if view == "lake" else Vector3(t * 2.0, 1.7, 0.0)
					camera.look_at(Vector3(125.0, 0.0, -110.0) if view == "lake" else Vector3(28.0, 7.3, -28.0))
					for settle in 90:
						await process_frame
						RenderingServer.force_draw(false)
					var name := "%s-%s-%s-%03d.png" % [hour.replace(":", ""), variant, view, frame]
					if viewport.get_texture().get_image().save_png(output.path_join(name)) != OK:
						quit(1)
						return
					reports.append({image = name, hour = hour, variant = variant, view = view, clock_s = t,
						camera = camera.position, target = Vector3(125.0, 0.0, -110.0) if view == "lake" else Vector3(28.0, 7.3, -28.0),
						world_state = World.visual_state(), sky_process_mode = built.environment.sky.process_mode})
			holder.free()
			await process_frame
	var report := {format = "openrc-ridge-world-probe v1", engine = Engine.get_version_info(),
		profile = High.describe(), viewport = [1920, 1080], msaa = 4, date = "2026-09-26", time_scale = 20,
		baseline_shader_sha256 = FileAccess.get_sha256(args[1]), candidate_shader_sha256 = Candidate.code.sha256_text(),
		complete = true, scope = "settled World samples; no continuous motion or flight qualification", cases = reports}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	viewport.free()
	print("ridge World probe complete: 24 day/twilight/night samples")
	quit()
