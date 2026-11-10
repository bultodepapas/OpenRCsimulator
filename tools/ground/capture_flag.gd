## L15c: isolated production flag/mast, matched wind tape and native 1080p views.
## Readback captures are visual evidence, never whole-flight performance evidence.
extends SceneTree

const Prefabs = preload("res://scenery/prefabs.gd")
const MeshKit = preload("res://scenery/mesh_kit.gd")
const Clock = preload("res://render/shader_clock.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := ""
	var legacy := ""
	var frames := 0
	var mode := "detailed"
	var locale := "en"
	var landscape := false
	var distance := 3.8
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): out = argument.trim_prefix("--out=")
		elif argument.begins_with("--legacy="): legacy = argument.trim_prefix("--legacy=")
		elif argument.begins_with("--frames="): frames = int(argument.trim_prefix("--frames="))
		elif argument.begins_with("--flag_animation="): mode = argument.trim_prefix("--flag_animation=")
		elif argument == "--landscape": landscape = true
		elif argument.begins_with("--distance="): distance = clampf(float(argument.trim_prefix("--distance=")),2.0,200.0)
		elif argument.begins_with("--locale="): locale = argument.trim_prefix("--locale=")
	if out.is_empty() or DirAccess.dir_exists_absolute(out) or DisplayServer.get_name() == "headless":
		push_error("Flag capture requires a native renderer and a fresh --out directory")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	TranslationServer.set_locale(locale)
	Clock.register()
	Clock.update(0.0)
	RenderingServer.render_loop_enabled = false
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.32, 0.48, 0.64)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.77, 0.83, 0.94)
	environment.environment.ambient_light_energy = 0.65
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 1.0
	world.add_child(sun)
	var flag: MeshInstance3D
	if landscape:
		var field_builder: Script = load("res://render/field.gd")
		var loader: Script = load("res://data/field_loader.gd")
		var atmosphere: Script = load("res://render/atmosphere.gd")
		var loaded: Dictionary = loader.load_from()
		var field_node: Node3D = field_builder.build(loaded.field)
		world.add_child(field_node)
		flag = field_node.get_node("Scenery/Motion").get_children().filter(func(node: Node): return node.name.begins_with("flag_"))[0]
		environment.environment = atmosphere.environment()
		sun.free()
		atmosphere.create_sun(world)
	else:
		var builder: Script = Prefabs
		if not legacy.is_empty():
			var source := GDScript.new()
			source.source_code = FileAccess.get_file_as_string(legacy.path_join("prefabs.gd.txt"))
			if source.reload() != OK:
				quit(1)
				return
			builder = source
		var kit := MeshKit.new()
		var parts: Array = builder.build("flagpole", kit, 123, "summer")
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = 0.85
		var mast := MeshInstance3D.new()
		mast.mesh = kit.to_mesh(material)
		world.add_child(mast)
		if not legacy.is_empty():
			flag = MeshInstance3D.new()
			var shader := Shader.new()
			shader.code = FileAccess.get_file_as_string(legacy.path_join("motion.gdshader.txt"))
			var fabric := ShaderMaterial.new()
			fabric.shader = shader
			fabric.set_shader_parameter("mode", 1)
			fabric.set_shader_parameter("phase", 0.25)
			flag.mesh = parts[0].kit.to_mesh(fabric)
			flag.position = parts[0].pivot
			flag.custom_aabb = flag.mesh.get_aabb().grow(2.0)
		else:
			var renderer: Script = load("res://render/flag.gd")
			flag = renderer.build(parts[0], Transform3D.IDENTITY, 123)
		world.add_child(flag)
	# Wait for the bounded asynchronous country resource request, if any.
	for frame in 30:
		await process_frame
		RenderingServer.force_draw(false)
	var camera := Camera3D.new()
	camera.near = 0.03
	camera.current = true
	world.add_child(camera)
	var cases := [
		["calm", Vector3.ZERO], ["light", Vector3(2,0,0)],
		["strong", Vector3(8,0,0)], ["reverse", Vector3(-8,0,0)],
		["cross", Vector3(0,0,8)]]
	var records: Array = []
	for item in cases:
		var wind: Vector3 = flag.global_basis * item[1]
		if legacy.is_empty(): flag.reset_wind(0.0, [0.0,0.0,0.0])
		for tick in 600:
			var t := (tick + 1) / 120.0
			Clock.update(t, wind)
			if legacy.is_empty(): flag.advance_wind(t, [-wind.z, wind.x, -wind.y])
		if legacy.is_empty(): flag.publish()
		for side in [1.0, -1.0]:
			camera.global_position = flag.global_transform * Vector3(0.54, -0.7, side * distance)
			camera.look_at(flag.global_transform * Vector3(0.59,-0.75,0))
			camera.fov = 43.0
			for frame in 8:
				await process_frame
				RenderingServer.force_draw(false)
			var name := "%s-%s" % [item[0], "front" if side > 0 else "rear"]
			var path := out.path_join(name + ".png")
			if viewport.get_texture().get_image().save_png(path) != OK:
				quit(1)
				return
			records.append({name = name, sha256 = FileAccess.get_sha256(path), wind = [wind.x,wind.y,wind.z]})
	if frames > 0:
		camera.global_position = flag.global_transform * Vector3(0.44,-0.65,4.0)
		camera.look_at(flag.global_transform * Vector3(0.59,-0.8,0))
		if legacy.is_empty(): flag.reset_wind(0.0, [0.0, 0.0, 0.0])
		for frame in mini(frames, 600):
			var t := float(frame) / 30.0
			var angle := smoothstep(2.0, 4.0, t) * PI
			var speed := 4.0 + 3.0 * sin(t * 0.7)
			var wind := flag.global_basis * Vector3(cos(angle), 0, sin(angle)) * speed
			Clock.update(t, wind)
			if legacy.is_empty():
				flag.advance_wind(t, [-wind.z,wind.x,-wind.y])
				flag.publish()
			await process_frame
			RenderingServer.force_draw(false)
			viewport.get_texture().get_image().save_png(out.path_join("motion-%04d.png" % frame))
	var report := {complete = true, engine = Engine.get_version_info(),
		adapter = RenderingServer.get_video_adapter_name(), renderer = RenderingServer.get_current_rendering_method(),
		resolution = [1920,1080], landscape = landscape, distance_m = distance, legacy = legacy, mode = mode, locale = locale, records = records,
			motion_frames = mini(frames,600), triangles = (flag.mesh.surface_get_array_index_len(0) if flag.mesh.surface_get_array_index_len(0) > 0 else flag.mesh.surface_get_array_len(0)) / 3,
		capture_sha256 = FileAccess.get_sha256(get_script().resource_path)}
	if not legacy.is_empty():
		report["legacy_prefab_sha256"] = FileAccess.get_sha256(legacy.path_join("prefabs.gd.txt"))
		report["legacy_shader_sha256"] = FileAccess.get_sha256(legacy.path_join("motion.gdshader.txt"))
	else:
		report["flag"] = flag.diagnostics()
		report["sources"] = {}
		for source in ["res://render/flag.gd","res://render/flag_motion.gd","res://render/flag.gdshader","res://render/field.gd"]:
			report.sources[source] = FileAccess.get_sha256(source)
	var file := FileAccess.open(out.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	world.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	print("FLAG CAPTURE COMPLETE: ", out)
	quit()
