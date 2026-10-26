extends SceneTree
## FW-RGB-05: authored paths carry arc length, independent of canonical aircraft axes.
const Lights := preload("res://render/world/aircraft_lights.gd")
const Rig := preload("res://render/lighting/aircraft_lighting_rig_3d.gd")
const Profile := preload("res://render/lighting/lighting_profile.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	ShaderClock.register()
	# Unequal segments double back in X; projection and station-index spacing are both wrong.
	var line := PackedVector3Array([Vector3.ZERO, Vector3(0, 1, 0), Vector3(2, 1, 0), Vector3(1, 1, 0)])
	var ribbon := Lights.strip("strip_left", line, Color.WHITE, Vector3.BACK, true)
	var arrays := ribbon.mesh.surface_get_arrays(0)
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var expected := [0.0, 0.25, 0.75, 1.0]
	var correct := uv.size() == 18
	for segment in 3:
		for corner in 6:
			var end := corner in [1, 2, 4]
			correct = correct and is_equal_approx(uv[segment * 6 + corner].y, expected[segment + (1 if end else 0)])
	check("unequal, returning path uses continuous arc length at every triangle corner", correct)
	check("authored ribbon declares path coordinates", ribbon.get_meta("lighting_path_uv", false))
	ribbon.free()
	var legacy := Lights.strip("strip_left", line)
	var legacy_uv: PackedVector2Array = legacy.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	check("fitted ribbon retains legacy projection and zero UV.y", not legacy.has_meta("lighting_path_uv")
		and Array(legacy_uv).all(func(p: Vector2) -> bool: return is_zero_approx(p.y)))
	legacy.free()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var aircraft := Node3D.new()
	viewport.add_child(aircraft)
	var body := MeshInstance3D.new()
	body.mesh = BoxMesh.new()
	body.mesh.size = Vector3(2, 0.1, 1)
	aircraft.add_child(body)
	aircraft.set_meta("lighting_layout", {"version": 1, "anchors": [], "strips": [{
		"id": "strip_left", "node_path": ".", "points_m": [[0, -1, 0], [0, 0, 0], [1, 0, 0], [1, 1, 0]],
		"face": [0, 0, 1], "width_m": 0.04}]})
	var profile := Profile.preset("custom")
	for zone: Dictionary in profile.zones:
		zone.enabled = zone.id == "strip_left"
		if zone.enabled:
			zone.pattern.id = "segments"
			zone.pattern.palette = ["#FF0000", "#00FF00", "#0000FF"]
			zone.pattern.segments = 3
			zone.pattern.floor = 1.0
	var rig := Rig.new()
	viewport.add_child(rig)
	check("authored RGB fixture configures", rig.configure(aircraft, profile).ok)
	body.visible = false
	var strip := rig.get_kit().get_node("strip_left") as MeshInstance3D
	var material := strip.get_surface_override_material(0) as ShaderMaterial
	check("rig selects path coordinates for authored strips", material.get_shader_parameter("use_path_uv") == true)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.0
	camera.position = Vector3(0.5, 0, 5)
	camera.current = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	viewport.add_child(environment)
	rig.advance(0.0, {"exposure": 1.0, "effects_allowed": false})
	if DisplayServer.get_name() != "headless":
		# Actual fragment output, not a shader-source assertion or duplicated sampling formula.
		var probes := [Vector3(0, -0.5, 0), Vector3(0.5, 0, 0), Vector3(1, 0.5, 0)]
		material.set_shader_parameter("use_path_uv", false)
		var before := await _render(viewport)
		check("native axis-projection baseline reproduces the off-axis path defect", not _colors_match(before, camera, aircraft, probes, [0, 1, 2]))
		material.set_shader_parameter("use_path_uv", true)
		var after := await _render(viewport)
		check("native 1080p forward path is red, green, blue across all turns", _colors_match(after, camera, aircraft, probes, [0, 1, 2]))
		_save(after, "forward")
		material.set_shader_parameter("pattern_extras", Vector4(3, 1, 0, 0))
		var reversed := await _render(viewport)
		check("native reverse traverses the same path in the opposite direction", _colors_match(reversed, camera, aircraft, probes, [2, 1, 0]))
		aircraft.rotation.z = 0.2
		aircraft.scale = Vector3(0.8, 1.1, 0.7)
		var moved := await _render(viewport)
		check("native rotated and scaled host preserves LED station colors", _colors_match(moved, camera, aircraft, probes, [2, 1, 0]))
		_save(moved, "transformed-reverse")
	else:
		print("Native pixel checks skipped: headless renderer; run without --headless for 1080p shader evidence.")
	rig.dispose()
	viewport.free()
	await process_frame
	print("Lighting paths: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _render(viewport: SubViewport) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func _colors_match(image: Image, camera: Camera3D, aircraft: Node3D, points: Array, channels: Array) -> bool:
	for i in points.size():
		var pixel := Vector2i(camera.unproject_position(aircraft.to_global(points[i])))
		var c := image.get_pixelv(pixel)
		var rgb := [c.r, c.g, c.b]
		if rgb[channels[i]] < 0.08 or rgb[(channels[i] + 1) % 3] > 0.03 or rgb[(channels[i] + 2) % 3] > 0.03:
			print("pixel ", pixel, " expected channel ", channels[i], " got ", c)
			return false
	return true

func _save(image: Image, label: String) -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-rgb-path="):
			var directory := arg.trim_prefix("--capture-rgb-path=")
			DirAccess.make_dir_recursive_absolute(directory)
			check("save " + label, image.save_png(directory.path_join(label + ".png")) == OK)

func check(label: String, ok: bool) -> void:
	checks += 1
	print(("ok   " if ok else "FAIL ") + label)
	if not ok: failures += 1
