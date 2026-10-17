# TRA-05. Presentation-only four-ship choreography using unmodified production models.
# Run with --path app --script <this file> -- --out-dir=<absolute> [--preview]
# This scene does not create a Simulation or imply interacting multiplayer physics.
extends SceneTree

const Builder = preload("res://render/airplane.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const World = preload("res://render/world/world.gd")
const Conditions = preload("res://render/world/conditions.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const EngineSmoke = preload("res://render/smoke/exhaust.gd")
const PropBlur = preload("res://render/propeller_blur.gd")
const FPS := 60
const FRAMES := 420

var output := ""
var preview := false
var stage: Node3D
var camera: Camera3D
var scene: Dictionary
var actors: Array[Dictionary] = []
var minimum_separation := INF
var minimum_screen_margin := INF
var maximum_model_radius := 0.0
var frame_records: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="):
			output = arg.trim_prefix("--out-dir=")
		if arg == "--preview":
			preview = true
	if output.is_empty():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1920, 1080)
	root.msaa_3d = Viewport.MSAA_4X
	stage = Node3D.new()
	root.add_child(stage)
	Atmosphere.engine_shadows = true
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	if not loaded.ok:
		push_error(str(loaded.errors))
		quit(1)
		return
	var conditions: Dictionary = Conditions.resolve(PackedStringArray(["--time_of_day=afternoon"]))
	scene = World.build(stage, loaded.field, Callable(), conditions)
	camera = Camera3D.new()
	camera.near = 0.1
	camera.far = 10000.0
	camera.fov = 44.0
	camera.current = true
	stage.add_child(camera)
	# A soft filming fill belongs to this disclosed cinematic stage only.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 130, 0)
	fill.light_color = Color("cad9e5")
	fill.light_energy = 0.35
	stage.add_child(fill)
	for i: int in range(4):
		var model: Dictionary = Builder.build("jensen-das-ugly-stik-60")
		if model.is_empty():
			quit(1)
			return
		stage.add_child(model.root)
		var smoke: Node3D = EngineSmoke.new()
		stage.add_child(smoke)
		var anchors: Array = model.get("exhausts", [])
		if not anchors.is_empty():
			smoke.configure(anchors[0])
		var blur: Node3D = PropBlur.attach(model, null, stage)
		if blur != null:
			blur.set_process(false)
		var bounds: AABB = _bounds(model.root, Transform3D.IDENTITY)
		maximum_model_radius = maxf(maximum_model_radius, bounds.size.length() * 0.5)
		actors.append({model = model, smoke = smoke, blur = blur, bounds = bounds})
	await process_frame
	# Warm up real smoke history on the same presentation clock.
	for f: int in range(-120, 0):
		_pose(float(f) / FPS)
		await process_frame
		await RenderingServer.frame_post_draw
	for f: int in range(FRAMES):
		_pose(float(f) / FPS)
		await process_frame
		await RenderingServer.frame_post_draw
		if not preview or f in [0, 120, 239, 330, 419]:
			var err := root.get_texture().get_image().save_png(output.path_join("%05d.png" % f))
			if err != OK:
				push_error("Frame write failed")
				quit(1)
				return
		if f % 60 == 0:
			print("FORMATION_FRAME ", f)
	var manifest := {
		format = "openrc-trailer-formation v1", frames = FRAMES, fps = FPS,
		width = 1920, height = 1080, classification = "cinematic choreography; not gameplay",
		model = "jensen-das-ugly-stik-60", actors = 4,
		minimum_center_separation_m = minimum_separation,
		maximum_model_radius_m = maximum_model_radius,
		minimum_screen_margin_px = minimum_screen_margin,
		engine = Engine.get_version_info().string,
		poses = frame_records
	}
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("FORMATION_OK ", minimum_separation)
	quit()

func _pose(t: float) -> void:
	var split: float = maxf(0.0, t - 4.0)
	var ease: float = smoothstep(0.0, 3.0, split)
	var center := Vector3(8.0 * sin(t * 0.14), 22.0 + 0.7 * t, -65.0 - 18.0 * t)
	var base_yaw: float = -0.06 - 0.06 * sin(t * 0.35)
	var base_bank: float = -0.14 * sin(clampf(t + 1.5, 0.0, 5.5) * PI / 5.5)
	var offsets: Array[Vector3] = [Vector3(0, 1.0, -4.5), Vector3(-4.1, 0, 0), Vector3(4.1, 0, 0), Vector3(0, -1.0, 4.5)]
	var branches: Array[Vector3] = [Vector3(-0.55, 0.9, -0.1), Vector3(-1.0, 0.1, 0), Vector3(1.0, 0.3, 0), Vector3(0.5, -0.6, 0.1)]
	var positions: Array[Vector3] = []
	var record: Dictionary = {time_s = t, positions = [], screen = []}
	for i: int in range(actors.size()):
		var actor: Dictionary = actors[i]
		var p: Vector3 = center + Basis(Vector3.UP, base_yaw) * offsets[i] + branches[i] * split * split * 0.95
		var yaw: float = base_yaw - branches[i].x * ease * 0.32
		var pitch: float = 0.04 + branches[i].y * ease * 0.20
		var bank: float = base_bank + branches[i].x * ease * 0.65
		actor.model.root.position = p
		actor.model.root.basis = Basis.from_euler(Vector3(pitch, yaw, bank))
		actor.model.propeller.rotation.z = t * 210.0
		if actor.blur != null:
			actor.blur.update(9000.0)
		positions.append(p)
		record.positions.append([p.x, p.y, p.z])
	# Track the centroid with a gentle outward move for the break.
	var distance: float = 16.5 + 14.0 * ease
	var eye: Vector3 = center + Vector3(-0.57 * distance, -0.07 * distance, -0.82 * distance)
	camera.look_at_from_position(eye, center + Vector3(0, 0.2 + 2.0 * ease, 0))
	World.update(scene.environment, t + 2.0, Vector3(0.8, 0, 0.1), center, camera)
	for i: int in range(actors.size()):
		var actor: Dictionary = actors[i]
		actor.smoke.advance(t + 2.0, actor.model.root.global_transform, "glow_prop", 9000.0, 2000.0, 12000.0, 0.8, Vector3(0.8, 0, 0.1), 1.0, true, camera.global_position.distance_to(positions[i]))
		var screen: Vector2 = camera.unproject_position(positions[i])
		record.screen.append([screen.x, screen.y])
		if t >= 0.0:
			var box: AABB = actor.bounds
			for k: int in range(8):
				var corner: Vector3 = actor.model.root.global_transform * box.get_endpoint(k)
				var pixel: Vector2 = camera.unproject_position(corner)
				minimum_screen_margin = minf(minimum_screen_margin, minf(minf(pixel.x, 1920.0 - pixel.x), minf(pixel.y, 1080.0 - pixel.y)))
		for j: int in range(i):
			minimum_separation = minf(minimum_separation, positions[i].distance_to(positions[j]))
	if t >= 0.0:
		frame_records.append(record)

func _bounds(node: Node3D, parent_transform: Transform3D) -> AABB:
	var tr: Transform3D = parent_transform * node.transform
	var result := AABB()
	if node is MeshInstance3D and node.visible and node.mesh != null:
		result = tr * node.get_aabb()
	for child: Node in node.get_children():
		if child is Node3D and child.visible:
			var box: AABB = _bounds(child, tr)
			if box.size.length_squared() > 0.0:
				result = box if result.size.length_squared() == 0.0 else result.merge(box)
	return result
