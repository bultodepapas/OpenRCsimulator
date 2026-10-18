## Imported grass material parity and world-space wind fixture. No simulation or authored mesh changes.
extends SceneTree

const Plants := preload("res://scenery/imported_vegetation.gd")
const Clock := preload("res://render/shader_clock.gd")
const IDS := ["grass_common_short", "grass_common_tall", "grass_wispy_tall"]

var args: Dictionary = {}
var viewport: SubViewport
var world: Node3D
var light: DirectionalLight3D
var source: Node3D
var candidate: Node3D
var captures: Array[Dictionary] = []
var out_dir: String


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() > 1 else "on"
	run.call_deferred()


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("material_capture requires a native renderer")
		quit(2)
		return
	out_dir = str(args.get("out", ""))
	if out_dir.is_empty() or DirAccess.dir_exists_absolute(out_dir):
		push_error("--out must name a new directory")
		quit(2)
		return
	var adapter_path := str(args.get("adapter", "res://scenery/imported_grass_material.gd"))
	var adapter: Script = load(adapter_path) as Script
	if adapter == null:
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	Clock.register()
	Clock.update(0.0, Vector3.ZERO)
	RenderingServer.render_loop_enabled = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	world = Node3D.new()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	viewport.add_child(world)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.12, 0.12, 0.12)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.25
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment_node.environment = environment
	world.add_child(environment_node)
	light = DirectionalLight3D.new()
	light.light_energy = 1.0
	world.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.5
	camera.position = Vector3(0.0, 0.85, 3.0)
	world.add_child(camera)
	camera.look_at(Vector3(0.0, 0.1, 0.0))
	camera.current = true
	var batches: Dictionary = {}
	for species: int in IDS.size():
		for yaw: int in 4:
			for size_index: int in 2:
				var origin := Vector3(float(yaw) * 0.55 - 0.825, 0.0, float(species) * -0.55 + float(size_index) * 0.25)
				var transform := Transform3D(Basis(Vector3.UP, yaw * PI * 0.5), origin)
				transform = Plants.fit_to_height(IDS[species], 0.12 if size_index == 0 else 0.25, transform)
				Plants.queue(batches, IDS[species], transform, species * 97 + yaw * 11 + size_index)
	source = Plants.build(batches, false)
	candidate = Plants.build(batches, false)
	adapter.apply(candidate)
	for plants: Node3D in [source, candidate]:
		for batch: MultiMeshInstance3D in plants.get_children():
			batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(plants)
	for rotation: Vector3 in [Vector3(-35.0, -25.0, 0.0), Vector3(-35.0, 155.0, 0.0)]:
		light.rotation_degrees = rotation
		var side := "front" if rotation.y < 0.0 else "back"
		await capture(side + "-source-calm", false, 0.0, Vector3.ZERO)
		await capture(side + "-candidate-calm", true, 0.0, Vector3.ZERO)
		await capture(side + "-candidate-calm-t1", true, 1.0, Vector3.ZERO)
		await capture(side + "-candidate-wind-t0", true, 0.0, Vector3(5.0, 0.0, 0.0))
		await capture(side + "-candidate-wind-t1", true, 1.0, Vector3(5.0, 0.0, 0.0))
		await capture(side + "-candidate-wind-wrap", true, 1024.0, Vector3(5.0, 0.0, 0.0))
		await capture(side + "-candidate-wind-repeat", true, 0.0, Vector3(5.0, 0.0, 0.0))
		await capture(side + "-candidate-wind-reverse", true, 0.0, Vector3(-5.0, 0.0, 0.0))
	var file := FileAccess.open(out_dir.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"format": "openrc-grass-material-capture v1", "engine": Engine.get_version_info(),
		"adapter": adapter_path, "adapter_sha256": FileAccess.get_sha256(adapter_path),
		"renderer": RenderingServer.get_current_rendering_method(),
		"device": RenderingServer.get_video_adapter_name(), "viewport": [1280, 720], "msaa": 4,
		"species": IDS, "yaw_degrees": [0, 90, 180, 270], "heights_m": [0.12, 0.25],
		"captures": captures,
	}, "\t") + "\n")
	file.close()
	world.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	print("GRASS MATERIAL CAPTURE complete: ", out_dir)
	quit(0)


func capture(id: String, use_candidate: bool, time: float, wind: Vector3) -> void:
	source.visible = not use_candidate
	candidate.visible = use_candidate
	Clock.update(time, wind)
	for frame: int in 3:
		await process_frame
		RenderingServer.force_draw(false)
	var image := viewport.get_texture().get_image()
	var path := out_dir.path_join(id + ".png")
	if image.save_png(path) != OK:
		push_error("Cannot write material capture " + path)
		quit(1)
		return
	captures.append({"id": id, "file": id + ".png", "sha256": FileAccess.get_sha256(path),
		"shader_clock": Clock.last_clock, "wind": [wind.x, wind.y, wind.z]})
