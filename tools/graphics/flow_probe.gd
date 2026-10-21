## VQ-07 / FW-MOON-06d: fixed-clock native World continuity and render-cost diagnostic.
## No aircraft or flight simulation; readbacks occur only after the timing sample.
extends SceneTree

const World := preload("res://render/world/world.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Conditions := preload("res://render/world/conditions.gd")
const High := preload("res://render/high_graphics_profile.gd")

var output := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 1 and args[0].begins_with("--out="):
		output = args[0].trim_prefix("--out=")
	if not output.is_absolute_path() or DirAccess.dir_exists_absolute(output) \
			or FileAccess.file_exists(output) or DisplayServer.get_name() == "headless":
		printerr("flow probe requires a native renderer and --out=<new absolute directory>")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		quit(2)
		return
	_run.call_deferred()

func _run() -> void:
	var loaded := FieldLoader.load_from()
	if not loaded.ok:
		quit(1)
		return
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.render_loop_enabled = false
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var rid := viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var reports := []
	for scenario: String in ["moon", "twilight"]:
		var holder := Node3D.new()
		viewport.add_child(holder)
		var date := "2026-10-25" if scenario == "moon" else "2026-09-26"
		var hour := "21:00" if scenario == "moon" else "19:00"
		var start := 0.0 if scenario == "moon" else 270.0
		var built := World.build(holder, loaded.field, Callable(), Conditions.resolve(
			PackedStringArray(["--date=" + date, "--time=" + hour, "--time_scale=20"])))
		var env: Environment = built.environment
		var mat := env.sky.sky_material as ShaderMaterial
		var stars := holder.get_node("Stars") as Node3D
		var camera := Camera3D.new()
		holder.add_child(camera)
		camera.position = Vector3(0, 1.7, 0)
		camera.far = 21000.0
		camera.fov = 2.0 if scenario == "moon" else 65.0
		camera.current = true
		World.update(env, start)
		var direction: Vector3 = Atmosphere.state.moon_dir if scenario == "moon" else Vector3(0.5, 0.15, -1.0).normalized()
		camera.look_at(camera.position + direction * 1000.0)
		var warm_end := Time.get_ticks_usec() + 10000000
		while Time.get_ticks_usec() < warm_end:
			await process_frame
			RenderingServer.force_draw(false)
		var samples := []
		var previous_moon: Vector3 = mat.get_shader_parameter("moon_dir")
		var previous_stars := stars.basis
		var previous_z := _luminance(mat.get_shader_parameter("zenith_lin"))
		for frame in 481:
			var t := start + float(frame) / 60.0
			var wall_start := Time.get_ticks_usec()
			World.update(env, t)
			await process_frame
			RenderingServer.force_draw(false)
			var wall_ms := float(Time.get_ticks_usec() - wall_start) / 1000.0
			var moon: Vector3 = mat.get_shader_parameter("moon_dir")
			var z := _luminance(mat.get_shader_parameter("zenith_lin"))
			var rotation := (previous_stars.inverse() * stars.basis).get_rotation_quaternion()
			samples.append({clock_s = t, wall_ms = wall_ms,
				render_cpu_ms = RenderingServer.viewport_get_measured_render_time_cpu(rid),
				render_gpu_ms = RenderingServer.viewport_get_measured_render_time_gpu(rid),
				moon_delta_deg = rad_to_deg(previous_moon.angle_to(moon)),
				stars_delta_deg = rad_to_deg(2.0 * asin(minf(Vector3(rotation.x, rotation.y, rotation.z).length(), 1.0))),
				zenith_log_delta = absf(log(maxf(z, 1e-30) / maxf(previous_z, 1e-30)))})
			previous_moon = moon
			previous_stars = stars.basis
			previous_z = z
		var paused_samples := []
		for frame in 120:
			World.update(env, start + 8.0)
			await process_frame
			RenderingServer.force_draw(false)
			paused_samples.append({render_cpu_ms = RenderingServer.viewport_get_measured_render_time_cpu(rid),
				render_gpu_ms = RenderingServer.viewport_get_measured_render_time_gpu(rid)})
		# Replay the same clock for lossless stills around a step, outside timing.
		for frame in [0, 45, 89, 90, 91, 180]:
			World.update(env, start + float(frame) / 60.0)
			for settle in 8:
				await process_frame
				RenderingServer.force_draw(false)
			var picture := viewport.get_texture().get_image()
			if picture.is_empty() or picture.save_png(output.path_join("%s-%03d.png" % [scenario, frame])) != OK:
				quit(1)
				return
		reports.append({scenario = scenario, date = date, hour = hour, start_clock_s = start,
			process_mode = env.sky.process_mode, radiance_size = env.sky.radiance_size,
			reflection_source = env.reflected_light_source, samples = samples, paused_samples = paused_samples})
		holder.free()
		await process_frame
	var report := {format = "openrc-sky-flow-probe v1", engine = Engine.get_version_info(),
		profile = High.describe(), viewport = [1920, 1080], msaa = 4, time_scale = 20,
		warmup_seconds_per_case = 10, fixed_clock_hz = 60, complete = true,
		scope = "offscreen World diagnostic; no aircraft or flight-performance qualification; GPU queries may lag",
		cases = reports}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	viewport.free()
	print("flow probe complete: moon and twilight")
	quit()

func _luminance(value: Vector3) -> float:
	return value.dot(Vector3(0.2126, 0.7152, 0.0722))
