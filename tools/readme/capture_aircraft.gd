# Documentation-only studio renders of the current catalog models.
# Run with the pinned engine, --path app --script <absolute path to this file>, under Xvfb.
# -- --out-dir=/tmp/openrc-readme-render
extends SceneTree

const Builder = preload("res://render/airplane.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
const FRAME_COUNT: int = 72
const STILL_SIZE: Vector2i = Vector2i(960, 540)
const TOUR_SIZE: Vector2i = Vector2i(800, 450)
const BACKGROUND: Color = Color("111820")

const TOUR_IDS = ["sebart-avanti-s-a200-p100rx", "xcell-60-research", "mt8-bisonte", "monster-car-2", "jensen-das-ugly-stik-60", "gp-extra-300s-60", "p51d-mustang-120", "turbo-lumber-evolution"]
const MT8 = preload("res://vehicles/ground/mt8_model.gd")
const Monster = preload("res://vehicles/ground/monster_car_2_model.gd")

var output: String = ""
var world: Node3D
var camera: Camera3D
var title: Label
var status: Label

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="):
			output = arg.trim_prefix("--out-dir=")
	if output.is_empty() or DirAccess.make_dir_recursive_absolute(output.path_join("frames")) != OK:
		push_error("Provide a writable --out-dir")
		quit(1)
		return
	root.size = STILL_SIZE
	world = Node3D.new()
	root.add_child(world)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c8c8c8")
	environment.ambient_light_energy = 0.45
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	environment_node.environment = environment
	world.add_child(environment_node)
	_add_light(Vector3(-47, -32, -9), 0.90)
	_add_light(Vector3(-24, 145, 12), 0.38)
	_add_light(Vector3(48, -28, 0), 0.40)
	camera = Camera3D.new()
	camera.fov = 38.0
	camera.current = true
	world.add_child(camera)
	var canvas: CanvasLayer = CanvasLayer.new()
	root.add_child(canvas)
	title = Label.new()
	status = Label.new()
	canvas.add_child(title)
	canvas.add_child(status)
	var manifest: Array[Dictionary] = []
	var global_frame: int = 0
	for id: String in TOUR_IDS:
		var entry: Dictionary = Catalog.entry(id)
		var model: Dictionary
		if id in ["mt8-bisonte", "monster-car-2"]:
			entry = {"id": id, "name": "Bisonte MT8" if id == "mt8-bisonte" else "MONSTER CAR 2", "status": "experimental"}
			model = MT8.build() if id == "mt8-bisonte" else Monster.build()
		else:
			model = Builder.build(id)
		if not model.get("root") is Node3D:
			push_error("Cannot build tour vehicle: " + id)
			quit(1)
			return
		var airplane: Node3D = model.root
		world.add_child(airplane)
		var bounds: AABB = _bounds(airplane, Transform3D.IDENTITY)
		var center: Vector3 = bounds.get_center()
		var extent: float = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
		title.visible = false
		status.visible = false
		root.size = STILL_SIZE
		_aim(center, extent, -42.0)
		await _save(output.path_join("%s.png" % entry.id))
		root.size = TOUR_SIZE
		title.text = entry.name
		title.position = Vector2(22, 17)
		title.add_theme_font_size_override("font_size", 26)
		title.add_theme_color_override("font_color", Color("f3f6f8"))
		status.text = {"flyable": "FLYABLE · flight model under evaluation", "experimental": "EXPERIMENTAL · physical validation pending", "preview": "VISUAL PREVIEW · Fly disabled"}[entry.status]
		status.position = Vector2(22, 53)
		status.add_theme_font_size_override("font_size", 15)
		status.add_theme_color_override("font_color", Color("a9bac9"))
		title.visible = true
		status.visible = true
		for frame: int in range(FRAME_COUNT):
			var angle: float = -42.0 + 360.0 * float(frame) / float(FRAME_COUNT)
			_aim(center, extent, angle)
			await _save(output.path_join("frames/%03d.png" % global_frame))
			global_frame += 1
		manifest.append({"id": entry.id, "name": entry.name, "status": entry.status,
			"bounds": {"position": [bounds.position.x, bounds.position.y, bounds.position.z],
				"size": [bounds.size.x, bounds.size.y, bounds.size.z]},
			"still": "%s.png" % entry.id, "frames": FRAME_COUNT})
		airplane.queue_free()
		await process_frame
	var file: FileAccess = FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write render manifest")
		quit(1)
		return
	file.store_string(JSON.stringify({"format": "openrc-readme-renders v1", "engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(), "source_commit": OS.get_environment("OPENRC_DOCS_COMMIT"),
		"purpose": "Studio model presentation; not gameplay or flight validation", "background": "#111820",
		"stills_size": [960, 540], "tour_size": [800, 450], "frame_count": global_frame, "vehicles": manifest}, "\t") + "\n")
	file.close()
	print("README_RENDER_OK: %d vehicles, %d animation frames" % [manifest.size(), global_frame])
	quit(0)

func _add_light(angles: Vector3, energy: float) -> void:
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = angles
	light.light_energy = energy
	world.add_child(light)

func _bounds(node: Node3D, parent_transform: Transform3D) -> AABB:
	var transform: Transform3D = parent_transform * node.transform
	var result: AABB = AABB()
	if node is MeshInstance3D and node.visible and node.mesh != null:
		result = transform * node.get_aabb()
	for child: Node in node.get_children():
		if child is Node3D and child.visible:
			var child_bounds: AABB = _bounds(child, transform)
			if child_bounds.size.length_squared() > 0.0:
				result = child_bounds if result.size.length_squared() == 0.0 else result.merge(child_bounds)
	return result

func _aim(center: Vector3, extent: float, azimuth: float) -> void:
	var az: float = deg_to_rad(azimuth)
	var elevation: float = deg_to_rad(22.0)
	var offset: Vector3 = extent * 1.70 * Vector3(sin(az) * cos(elevation), sin(elevation), -cos(az) * cos(elevation))
	camera.look_at_from_position(center + offset, center)

func _save(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Cannot save %s: %s" % [path, error_string(error)])
		quit(1)
