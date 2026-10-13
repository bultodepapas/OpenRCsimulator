## FW-62-R1: GPU regressions for dusk blocks, top-side leakage, and light sizing under zoom.
## Requires a real renderer. --out=<absolute folder> writes captures and summary.json; exits nonzero on failure.
extends SceneTree

const Builder := preload("res://render/airplane.gd")
const Kit := preload("res://render/world/aircraft_lights.gd")
const Clock := preload("res://render/shader_clock.gd")
const Exposure := preload("res://render/world/exposure.gd")
var _out := ""
var _checks: Array[Dictionary] = []
var _camera: Camera3D
var _environment: Environment
var _sun: DirectionalLight3D
var _strip_override := ""
var _sprite_override := ""

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, ok: bool, detail := "") -> void:
	_checks.append({check = label, ok = ok, detail = detail})
	print("%s %s: %s" % ["ok" if ok else "FAIL", label, detail])

func _grab() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
		if arg.begins_with("--strip-shader="): _strip_override = arg.trim_prefix("--strip-shader=")
		if arg.begins_with("--sprite-shader="): _sprite_override = arg.trim_prefix("--sprite-shader=")
	if _out.is_empty() or not _out.is_absolute_path() or DisplayServer.get_name() == "headless":
		printerr("requires a renderer and --out=<absolute folder>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	Clock.register()
	Clock.update(0.4) # strobes off: compare only steady sources
	Exposure.set_value(0.6)
	root.size = Vector2i(1280, 720)
	root.msaa_3d = Viewport.MSAA_4X
	var world := WorldEnvironment.new()
	_environment = Environment.new()
	world.environment = _environment
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Color("#1d2c3c")
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color.WHITE
	root.add_child(world)
	_sun = DirectionalLight3D.new()
	root.add_child(_sun)
	_sun.rotation_degrees = Vector3(-35, -25, 0)
	_camera = Camera3D.new()
	_camera.near = 0.1
	_camera.far = 21000.0
	root.add_child(_camera)
	_camera.current = true
	await _fleet()
	await _sizes()
	var ok := _checks.all(func(c: Dictionary) -> bool: return c.ok)
	var summary := {format = "openrc-aircraft-lights-capture v1", ok = ok, checks = _checks,
		renderer = {godot = Engine.get_version_info().string, driver = RenderingServer.get_current_rendering_driver_name(),
			method = RenderingServer.get_current_rendering_method(), adapter = RenderingServer.get_video_adapter_name()},
		shader_overrides = {strip = _strip_override, sprite = _sprite_override},
		source_sha256 = {strip = FileAccess.get_sha256(_strip_override if not _strip_override.is_empty() else "res://render/world/led_strip.gdshader"),
			sprite = FileAccess.get_sha256(_sprite_override if not _sprite_override.is_empty() else "res://render/world/light_sprite.gdshader")}}
	var file := FileAccess.open(_out.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "  ") + "\n")
	file.close()
	print("%d GPU checks; %s" % [_checks.size(), "passed" if ok else "FAILED"])
	quit(0 if ok else 1)

func _fleet() -> void:
	for id in [Builder.STIK_ID, Builder.EXTRA_ID, Builder.AVANTI_ID, Builder.P51_ID, Builder.TIMBER_ID]:
		var airplane: Dictionary = Builder.build(id)
		root.add_child(airplane.root)
		var kit := Kit.attach(airplane.root)
		kit.get_node("landing_light").visible = false
		var left: Node3D = kit.get_node("strip_left")
		var right: Node3D = kit.get_node("strip_right")
		if not _strip_override.is_empty():
			for node: MeshInstance3D in [left, right]:
				(node.mesh.surface_get_material(0) as ShaderMaterial).shader = load(_strip_override)
		for exposure in [0.6, 30.0]:
			Exposure.set_value(exposure)
			_environment.tonemap_exposure = exposure
			_environment.ambient_light_energy = 0.4 / exposure
			_sun.light_energy = 0.6 / exposure
			for placement in [Vector2(30, 50), Vector2(200, 6), Vector2(600, 1)]:
				for angle in [-30.0, 30.0]:
					var center := Vector3(0, 0, 0.25)
					_camera.fov = placement.y
					_camera.position = center + Vector3(0.2, sin(deg_to_rad(angle)), -cos(deg_to_rad(angle))).normalized() * placement.x
					_camera.look_at(center)
					left.visible = true
					right.visible = true
					var lit := await _grab()
					left.visible = false
					right.visible = false
					var bare := await _grab()
					var name := "%s-e%s-d%d-f%d-a%d" % [id, str(exposure), int(placement.x), int(placement.y), int(angle)]
					lit.save_png(_out.path_join(name + ".png"))
					bare.save_png(_out.path_join(name + "-no-strips.png"))
					var darkened := 0
					var brightened := 0
					# Central 256-pixel subject region. No text, shadow, or moving environment.
					for y in range(232, 488):
						for x in range(512, 768):
							var a := lit.get_pixel(x, y)
							var b := bare.get_pixel(x, y)
							if minf(a.r - b.r, minf(a.g - b.g, a.b - b.b)) < -2.0 / 255.0:
								darkened += 1
							if maxf(a.r - b.r, maxf(a.g - b.g, a.b - b.b)) > 2.0 / 255.0:
								brightened += 1
					_check(name + " adds light without dark blocks", darkened == 0, "%d darkened pixels" % darkened)
					if angle > 0:
						_check(name + " underside cue hidden from above", lit.get_data() == bare.get_data())
					elif exposure > 1.0:
						_check(name + " underside light remains visible", brightened > 0, "%d brightened pixels" % brightened)
		airplane.root.queue_free()
		await process_frame

func _sizes() -> void:
	Exposure.set_value(1.0)
	_environment.tonemap_exposure = 1.0
	_environment.background_color = Color.BLACK
	var line := PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0)])
	var strip := Kit.strip("probe_strip", line)
	var material := strip.mesh.surface_get_material(0) as ShaderMaterial
	if not _strip_override.is_empty(): material.shader = load(_strip_override)
	material.set_shader_parameter("radiance", 1000.0)
	material.set_shader_parameter("width_m", 0.0001) # unresolved physical width, at every tested projection
	root.add_child(strip)
	var sprite := Kit.sprite("probe_sprite", Color.WHITE, Vector3.ZERO, 0.0001, 1e12)
	if not _sprite_override.is_empty(): (sprite.mesh.material as ShaderMaterial).shader = load(_sprite_override)
	root.add_child(sprite)
	for size in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = size
		for fov in [50.0, 6.0, 1.0]:
			_camera.fov = fov
			_camera.look_at_from_position(Vector3(0, -1000, 0), Vector3.ZERO, Vector3.FORWARD)
			for point in [false, true]:
				strip.visible = not point
				sprite.visible = point
				var image := await _grab()
				var height := _height(image)
				var label := "%s-%dp-f%d" % ["sprite" if point else "strip", size.y, int(fov)]
				image.save_png(_out.path_join(label + ".png"))
				_check(label + " respects pixel size under zoom", height >= 1 and height <= (6 if point else 4), "%d lit rows" % height)
	for aspect in [Camera3D.KEEP_HEIGHT, Camera3D.KEEP_WIDTH]:
		_camera.keep_aspect = aspect
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = 20.0
		for point in [false, true]:
			strip.visible = not point
			sprite.visible = point
			var height := _height(await _grab())
			_check("orthographic aspect %d %s remains pixel-sized" % [aspect, "sprite" if point else "strip"],
				height >= 1 and height <= (6 if point else 4), "%d lit rows" % height)
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	var blocker := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(10, 1, 10)
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color.BLACK
	box.material = black
	blocker.mesh = box
	blocker.position = Vector3(0, -20, 0)
	root.add_child(blocker)
	for point in [false, true]:
		strip.visible = not point
		sprite.visible = point
		_check("opaque foreground hides " + ("sprite" if point else "strip"), _height(await _grab()) == 0)
	blocker.queue_free()
	strip.queue_free()
	sprite.queue_free()
	await process_frame

static func _height(image: Image) -> int:
	var lo := image.get_height()
	var hi := -1
	var center := Vector2i(image.get_width() / 2, image.get_height() / 2)
	for y in range(center.y - 64, center.y + 64):
		for x in range(center.x - 64, center.x + 64):
			var c := image.get_pixel(x, y)
			if maxf(c.r, maxf(c.g, c.b)) > 0.01:
				lo = mini(lo, y)
				hi = maxi(hi, y)
	return maxi(0, hi - lo + 1)
