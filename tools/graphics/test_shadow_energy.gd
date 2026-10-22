## VQ-07: enabling shadow maps must not dim an unoccluded Forward+ surface.
## Uses the production sun adapter, with ambient/reflections/fog isolated.
extends SceneTree

const Atmosphere := preload("res://render/atmosphere.gd")
const High := preload("res://render/high_graphics_profile.gd")
var output := ""
var capture_only := false

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
		elif argument == "--capture-only":
			capture_only = true
		else:
			quit(2)
			return
	if DisplayServer.get_name() == "headless" or not output.is_absolute_path() \
			or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output):
		printerr("shadow energy test requires native rendering and --out=<new absolute directory>")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		quit(2)
		return
	_run.call_deferred()

func _run() -> void:
	RenderingServer.render_loop_enabled = false
	var viewport := SubViewport.new()
	viewport.size = Vector2i(512, 256)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var holder := WorldEnvironment.new()
	holder.environment = environment
	world.add_child(holder)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.0
	camera.position = Vector3(0, 6, 0)
	world.add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	camera.current = true
	var positions := [Vector3(-2, 0, 0), Vector3(0, 0, 0), Vector3(2, 0, 0)]
	for index in positions.size():
		var plane := MeshInstance3D.new()
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(1.5, 1.5)
		plane.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = [Color(0.3, 0.3, 0.3), Color(0.6, 0.3, 0.15), Color(0.7, 0.7, 0.7)][index]
		material.roughness = 1.0
		material.metallic_specular = 0.0
		plane.material_override = material
		plane.position = positions[index]
		world.add_child(plane)
	Atmosphere.state = {}
	var sun := Atmosphere.create_sun(world)
	var samples := []
	for enabled: bool in [false, true]:
		Atmosphere.engine_shadows = enabled
		Atmosphere.update_sun(sun)
		for frame in 12:
			await process_frame
			RenderingServer.force_draw(false)
		var picture := viewport.get_texture().get_image()
		if picture.is_empty() or picture.save_png(output.path_join("on.png" if enabled else "off.png")) != OK:
			quit(1)
			return
		var colors := []
		for position: Vector3 in positions:
			var point := camera.unproject_position(position)
			var color := picture.get_pixel(roundi(point.x), roundi(point.y))
			colors.append([color.r, color.g, color.b])
		samples.append({shadows = sun.shadow_enabled, energy = sun.light_energy, colors = colors})
	var max_delta := 0.0
	var resolved := true
	for index in positions.size():
		for channel in 3:
			var off := float(samples[0].colors[index][channel])
			var on := float(samples[1].colors[index][channel])
			resolved = resolved and off > 0.03 and off < 0.95 and on > 0.03 and on < 0.95
			max_delta = maxf(max_delta, absf(on - off))
	var forward := RenderingServer.get_current_rendering_method() == "forward_plus"
	var passed: bool = resolved and not samples[0].shadows and samples[1].shadows \
		and (not forward or max_delta <= 2.0 / 255.0)
	var report := {complete = true, passed = passed, capture_only = capture_only,
		engine = Engine.get_version_info(), profile = High.describe(), viewport = [512, 256],
		samples = samples, max_channel_delta = max_delta, tolerance = 2.0 / 255.0,
		resolved = resolved, performance_claim = false}
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	viewport.free()
	await process_frame
	print("shadow energy GPU comparison: ", JSON.stringify(report))
	quit(0 if passed or capture_only else 1)
