# TRA-05. Presentation-only four-ship choreography using unmodified production models.
# Run with --path app --script <this file> -- --out-dir=<absolute> [--preview] [--mix]
# TRA-09 --mix: five distinct airframes with colored show-smoke tints (presentation only).
# TRA-10 --sizes: three Ugly Stiks at the Workshop's 500 %, 100 % and 10 % sizes, flying together at one depth
# so the size difference reads in a single frame (presentation-scaled models, not Workshop flight physics).
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
const MIX_FRAMES := 600
# TRA-09 airshow roster: catalog ID and pump tint. The Vantage Jet keeps its white show smoke.
const MIX_ROSTER: Array[Dictionary] = [
	{id = "p51d-mustang-120", tint = Vector3(0.95, 0.16, 0.12)},
	{id = "gp-extra-300s-60", tint = Vector3(0.18, 0.40, 0.98)},
	{id = "sebart-avanti-s-a200-p100rx", tint = Vector3(0.95, 0.96, 0.97)},
	{id = "f4u-corsair-250", tint = Vector3(1.0, 0.80, 0.10)},
	{id = "jensen-das-ugly-stik-60", tint = Vector3(0.15, 0.85, 0.30)},
]

# TRA-10 size trio: the Workshop presets Giant, Original and Tiny of the same airframe (left to right).
const SIZE_ROSTER: Array[Dictionary] = [
	{id = "jensen-das-ugly-stik-60", scale = 5.0},
	{id = "jensen-das-ugly-stik-60", scale = 1.0},
	{id = "jensen-das-ugly-stik-60", scale = 0.1},
]
const SIZE_FRAMES := 480

var output := ""
var preview := false
var mix := false
var sizes := false
var frames := FRAMES
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
		if arg == "--mix":
			mix = true
			frames = MIX_FRAMES
		if arg == "--sizes":
			sizes = true
			frames = SIZE_FRAMES
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
	var roster: Array[Dictionary] = MIX_ROSTER if mix else (SIZE_ROSTER if sizes else [{id = "jensen-das-ugly-stik-60"},
		{id = "jensen-das-ugly-stik-60"}, {id = "jensen-das-ugly-stik-60"}, {id = "jensen-das-ugly-stik-60"}])
	for entry: Dictionary in roster:
		var model: Dictionary = Builder.build(str(entry.id))
		if model.is_empty():
			quit(1)
			return
		stage.add_child(model.root)
		var smoke: Node3D = EngineSmoke.new()
		stage.add_child(smoke)
		var bounds: AABB = _bounds(model.root, Transform3D.IDENTITY)
		if sizes: # after the unscaled bounds: screen checks apply the root's global (scaled) transform
			model.root.scale = Vector3.ONE * float(entry.scale)
		var anchors: Array = model.get("exhausts", [])
		var anchor: Dictionary = anchors[0] if not anchors.is_empty() else {}
		if mix:
			# Cinematic show-smoke outlet: the model's own exhaust when published, else the tail centerline.
			if not EngineSmoke.valid_anchor(anchor):
				anchor = {position = Vector3(bounds.get_center().x, bounds.get_center().y, bounds.end.z),
					direction = Vector3.BACK, radius_m = 0.02, kind = "glow_prop"}
			anchor = anchor.duplicate()
			anchor.direction = Vector3.BACK
			anchor.pump = true
		if not anchor.is_empty() and not sizes: # smoke volume does not scale, so the size trio flies clean
			smoke.configure(anchor)
		if mix and smoke.pump != null:
			(smoke.pump.process_material as ShaderMaterial).set_shader_parameter("tint", entry.tint)
		var blur: Node3D = PropBlur.attach(model, null, stage)
		if blur != null:
			blur.set_process(false)
		var size_scale: float = float(entry.get("scale", 1.0))
		maximum_model_radius = maxf(maximum_model_radius, bounds.size.length() * 0.5 * size_scale)
		actors.append({model = model, smoke = smoke, blur = blur, bounds = bounds, scale = size_scale})
	await process_frame
	# Warm up real smoke history on the same presentation clock.
	for f: int in range(-120, 0):
		_pose(float(f) / FPS)
		await process_frame
		await RenderingServer.frame_post_draw
	for f: int in range(frames):
		_pose(float(f) / FPS)
		await process_frame
		await RenderingServer.frame_post_draw
		if not preview or f in [0, 120, 239, 330, 419, 540, 599]:
			var err := root.get_texture().get_image().save_png(output.path_join("%05d.png" % f))
			if err != OK:
				push_error("Frame write failed")
				quit(1)
				return
		if f % 60 == 0:
			print("FORMATION_FRAME ", f)
	var manifest := {
		format = "openrc-trailer-formation v1", frames = frames, fps = FPS,
		width = 1920, height = 1080, classification = "cinematic choreography; not gameplay",
		model = ",".join(roster.map(func(e: Dictionary) -> String: return str(e.id))), actors = roster.size(),
		smoke = "colored cinematic show-smoke tints" if mix else ("none" if sizes else "stock Stik pump"),
		scales = roster.map(func(e: Dictionary) -> float: return float(e.get("scale", 1.0))),
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
	if mix:
		_pose_mix(t)
		return
	if sizes:
		_pose_sizes(t)
		return
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
		if actor.model.get("propeller") != null:
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

# Size trio line abreast at one depth (Giant left, Original centre, Tiny right), seen from a low front quarter
# against the sky; the camera then closes on the Original wingtip and the Tiny so the 15 cm model reads beside it.
func _pose_sizes(t: float) -> void:
	var push: float = smoothstep(3.0, 7.2, t)
	var center := Vector3(6.0 * sin(t * 0.12), 18.0 + 0.5 * t, -40.0 - 16.0 * t)
	var base_yaw: float = -0.04 - 0.04 * sin(t * 0.3)
	var heading := Basis(Vector3.UP, base_yaw)
	# Tight wingtip gaps so the sizes compare directly: Giant (7.62 m span) to Original 0.43 m, Original (1.52 m)
	# to Tiny (0.15 m) 0.15 m, almost on its wingtip. The Giant flies 0.8 m higher so the tips never cross.
	var offsets: Array[Vector3] = [Vector3(-5.0, 0.8, 0.0), Vector3(0.0, 0.0, 0.0), Vector3(0.99, 0.08, 0.0)]
	var positions: Array[Vector3] = []
	var record: Dictionary = {time_s = t, positions = [], screen = []}
	for i: int in range(actors.size()):
		var actor: Dictionary = actors[i]
		var bob := Vector3(0, 0.12 * sin(t * 1.1 + i * 1.7), 0)
		var p: Vector3 = center + heading * offsets[i] + bob
		var bank: float = -0.05 * sin(clampf(t, 0.0, 8.0) * PI / 8.0) + 0.03 * sin(t * 0.9 + i)
		actor.model.root.position = p
		actor.model.root.basis = Basis.from_euler(Vector3(0.04, base_yaw, bank)).scaled(Vector3.ONE * float(actor.scale))
		if actor.model.get("propeller") != null:
			actor.model.propeller.rotation.z = t * 210.0
		if actor.blur != null:
			actor.blur.update(9000.0)
		positions.append(p)
		record.positions.append([p.x, p.y, p.z])
	# Framing: the whole trio first, then the Original/Tiny pair.
	# A near-frontal eye keeps all three at one depth, so size reads as size rather than distance.
	var trio: Vector3 = center + heading * Vector3(-3.75, 0.35, 0.0)
	# End between the Original's right wingtip and the Tiny, close enough (1.9 m) for the 15 cm model to read.
	var pair: Vector3 = center + heading * Vector3(0.8, 0.05, 0.0)
	var focus: Vector3 = trio.lerp(pair, push)
	var distance: float = lerpf(17.0, 1.9, push)
	var eye: Vector3 = focus + heading * Vector3(0.12 * distance, -0.07 * distance, -0.99 * distance)
	camera.look_at_from_position(eye, focus)
	World.update(scene.environment, t + 2.0, Vector3(0.8, 0, 0.1), center, camera)
	for i: int in range(actors.size()):
		var screen: Vector2 = camera.unproject_position(positions[i])
		record.screen.append([screen.x, screen.y])
		for j: int in range(i):
			minimum_separation = minf(minimum_separation, positions[i].distance_to(positions[j]))
	if t >= 0.0:
		frame_records.append(record)


# Five-ship arrowhead: low camera ahead of the formation, tilting up as it passes, then a fan-out.
func _pose_mix(t: float) -> void:
	var split: float = maxf(0.0, t - 4.5)
	var ease: float = smoothstep(0.0, 3.0, split)
	var center := Vector3(10.0 * sin(t * 0.12), 26.0 + 0.9 * t, -40.0 - 19.0 * t)
	var base_yaw: float = -0.05 - 0.05 * sin(t * 0.3)
	var base_bank: float = -0.12 * sin(clampf(t + 1.0, 0.0, 5.0) * PI / 5.0)
	var offsets: Array[Vector3] = [Vector3(0, 1.2, -5.5), Vector3(-5.0, 0.4, -1.0), Vector3(5.0, 0.4, -1.0),
		Vector3(-10.0, -0.4, 3.5), Vector3(10.0, -0.4, 3.5)]
	var branches: Array[Vector3] = [Vector3(0.0, 1.2, -0.1), Vector3(-1.0, 0.3, 0.0), Vector3(1.0, 0.3, 0.0),
		Vector3(-0.8, -0.5, 0.1), Vector3(0.8, -0.5, 0.1)]
	var positions: Array[Vector3] = []
	var record: Dictionary = {time_s = t, positions = [], screen = []}
	for i: int in range(actors.size()):
		var actor: Dictionary = actors[i]
		var p: Vector3 = center + Basis(Vector3.UP, base_yaw) * offsets[i] + branches[i] * split * split * 1.1
		var yaw: float = base_yaw - branches[i].x * ease * 0.35
		var pitch: float = 0.04 + branches[i].y * ease * 0.22
		var bank: float = base_bank + branches[i].x * ease * 0.75
		actor.model.root.position = p
		actor.model.root.basis = Basis.from_euler(Vector3(pitch, yaw, bank))
		if actor.model.get("propeller") != null:
			actor.model.propeller.rotation.z = t * 210.0
		if actor.blur != null:
			actor.blur.update(9000.0)
		positions.append(p)
		record.positions.append([p.x, p.y, p.z])
	var distance: float = 23.0 + 14.0 * ease
	var eye: Vector3 = center + Vector3(-0.64 * distance, -0.13 * distance, -0.76 * distance)
	camera.look_at_from_position(eye, center + Vector3(0, 0.5 + 2.5 * ease, 0))
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
