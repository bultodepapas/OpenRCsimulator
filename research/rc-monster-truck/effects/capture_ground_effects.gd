## Native Compatibility captures of the production effects component on the bundled MT8 model.
## Dust telemetry here is an explicitly staged visual fixture, not a driving result.
extends SceneTree

const Model := preload("res://vehicles/ground/mt8_model.gd")
const Effects := preload("res://vehicles/ground/ground_effects.gd")
const MODEL_SOURCE := "res://assets/vehicles/mt8-bisonte/MT8_Bisonte.glb"
const SMOKE_SOURCE := "res://assets/crash/smoke.png"
const CAPTURE_DIR := "res://../docs/research/rc-monster-truck/RCV-effects"
const EVIDENCE_DIR := "res://../research/rc-monster-truck/effects"
const VIEW_SIZE := Vector2i(1280, 720)

var _fixture_surface := "loose_gravel"
var _visual: Dictionary
var _effects: Node
var _camera: Camera3D
var _key: DirectionalLight3D
var _fill: DirectionalLight3D
var _environment: Environment
var _captures: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("A native Compatibility renderer is required")
		return
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		_fail("Capture must use the Compatibility renderer")
		return
	root.size = VIEW_SIZE
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.borderless = true
	root.position = Vector2i(-3000, -3000)
	var output := ProjectSettings.globalize_path(CAPTURE_DIR)
	var evidence := ProjectSettings.globalize_path(EVIDENCE_DIR)
	if DirAccess.make_dir_recursive_absolute(output) != OK or DirAccess.make_dir_recursive_absolute(evidence) != OK:
		_fail("Cannot create the capture output directories")
		return

	var world := Node3D.new()
	world.name = "GroundEffectsCaptureFixture"
	root.add_child(world)
	_setup_stage(world)
	_visual = Model.build()
	if not bool(_visual.get("ok", false)):
		_fail("Bundled MT8 failed to build: " + str(_visual.get("error", "unknown error")))
		return
	world.add_child(_visual.root)
	await process_frame # Let MT8_Rig._ready() bind the imported nodes and apply its rest pose.
	_place_tires_on_ground()
	_visual.root.call("set_steer", deg_to_rad(8.0))
	for corner in ["FL", "FR", "RL", "RR"]:
		_visual.root.call("set_spin", corner, deg_to_rad(-5.0))
	_effects = Effects.new()
	_effects.name = "GroundEffects"
	if not _effects.prepare(_visual, world):
		_fail("Ground effects failed to prepare on Model.build() bindings")
		return
	await process_frame

	await _capture_day_dust(output)
	_effects.reset()
	await _capture_night_headlights(output)
	await _capture_night_rear_lamps(output)
	var captures_ok := _captures.size() == 3
	for capture in _captures:
		captures_ok = captures_ok and bool(capture.get("ok", false))
	var manifest := {
		"format": "rcv-ground-effects-native-capture v2",
		"ok": captures_ok,
		"fixture_note": "Dust telemetry is staged for visual review only; this capture does not show driving or validate vehicle behavior.",
		"capture_command": "Godot_v4.7.2-stable_win64.exe --rendering-method gl_compatibility --audio-driver Dummy --path app --script res://../research/rc-monster-truck/effects/capture_ground_effects.gd",
		"model_builder": "res://vehicles/ground/mt8_model.gd Model.build()",
		"rig_pose": "imported MT8 rig initialized in rest pose, grounded by its measured wheel bounds, then 8-degree steer and small wheel spin through rig setters",
		"renderer": {
			"godot": Engine.get_version_info().string,
			"method": RenderingServer.get_current_rendering_method(),
			"driver": RenderingServer.get_current_rendering_driver_name(),
			"adapter": RenderingServer.get_video_adapter_name(),
			"requested_window_size": [VIEW_SIZE.x, VIEW_SIZE.y],
		},
		"source_sha256": {
			"mt8_glb": FileAccess.get_sha256(MODEL_SOURCE),
			"smoke_png": FileAccess.get_sha256(SMOKE_SOURCE),
			"ground_effects_gd": FileAccess.get_sha256("res://vehicles/ground/ground_effects.gd"),
			"ground_grime_overlay_gdshader": FileAccess.get_sha256("res://vehicles/ground/ground_grime_overlay.gdshader"),
			"capture_script": FileAccess.get_sha256("res://../research/rc-monster-truck/effects/capture_ground_effects.gd"),
		},
		"captures": _captures,
	}
	var manifest_path := evidence.path_join("native-capture.json")
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		_fail("Cannot write capture manifest: " + manifest_path)
		return
	file.store_string(JSON.stringify(manifest, "\t", true, true) + "\n")
	file.close()
	print(JSON.stringify(manifest))
	world.queue_free()
	await process_frame
	quit(0 if bool(manifest.ok) else 1)


func _setup_stage(world: Node3D) -> void:
	var world_environment := WorldEnvironment.new()
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Color("b8c5ca")
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color("e4e4d8")
	_environment.ambient_light_energy = 0.58
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = _environment
	world.add_child(world_environment)

	_key = DirectionalLight3D.new()
	_key.name = "CaptureSun"
	_key.rotation_degrees = Vector3(-43.0, -34.0, 0.0)
	_key.light_color = Color("fff0d6")
	_key.light_energy = 1.1
	_key.shadow_enabled = true
	world.add_child(_key)
	_fill = DirectionalLight3D.new()
	_fill.name = "CaptureFill"
	_fill.rotation_degrees = Vector3(-24.0, 132.0, 0.0)
	_fill.light_color = Color("d9e7f0")
	_fill.light_energy = 0.34
	world.add_child(_fill)

	var floor := MeshInstance3D.new()
	floor.name = "NeutralGravelStage"
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(6.0, 6.0)
	floor.mesh = floor_mesh
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("443f34")
	floor_material.roughness = 0.96
	floor.material_override = floor_material
	world.add_child(floor)

	_camera = Camera3D.new()
	_camera.name = "CloseUpCaptureCamera"
	_camera.fov = 34.0
	_camera.near = 0.01
	_camera.far = 25.0
	world.add_child(_camera)
	_camera.current = true


func _place_tires_on_ground() -> void:
	var lowest := INF
	for corner in ["FL", "FR", "RL", "RR"]:
		var wheel := _visual.nodes[corner + "_WheelMesh"] as MeshInstance3D
		var bounds := wheel.get_aabb()
		for ix in 2:
			for iy in 2:
				for iz in 2:
					var point := bounds.position + Vector3(bounds.size.x * ix, bounds.size.y * iy, bounds.size.z * iz)
					lowest = minf(lowest, wheel.to_global(point).y)
	_visual.root.position.y -= lowest


func _capture_day_dust(output: String) -> void:
	_fixture_surface = "loose_gravel"
	_set_camera_pose(Vector3(-0.66, 0.28, -0.61))
	_set_day()
	var telemetry := _dust_fixture()
	for frame in 150:
		_effects.update_render(0.1, telemetry, {"brake": 0.0, "reverse": false}, Callable(self, "_sample_road"), false, 0.0)
		await process_frame
	var shot := await _save_capture(output, "effects-day-dust.png", "day-dust-fixture")
	shot["fixture_telemetry"] = {"surface_id": _fixture_surface, "speed_m_per_s": 5.2, "wheel_in_contact": [1, 1, 1, 1], "wheel_slip_speed_m_per_s": [1.6, 1.6, 1.6, 1.6]}
	shot["visual_fixture_only"] = true
	_captures.append(shot)


func _capture_night_headlights(output: String) -> void:
	_set_night()
	_set_camera_pose(Vector3(-0.10, 0.30, -1.22))
	_effects.update_render(0.0, {}, {"brake": 0.0, "reverse": false}, Callable(), false, 1.0)
	for _frame in 5:
		await process_frame
	var shot := await _save_capture(output, "effects-night-headlights.png", "night-front-headlights")
	shot["visual_fixture_only"] = true
	_captures.append(shot)


func _capture_night_rear_lamps(output: String) -> void:
	_set_camera_pose(Vector3(0.11, 0.30, 1.22))
	_effects.update_render(0.0, {}, {"brake": 1.0, "reverse": true}, Callable(), false, 1.0)
	for _frame in 5:
		await process_frame
	var shot := await _save_capture(output, "effects-night-rear-lamps.png", "night-rear-brake-reverse")
	shot["control_fixture"] = {"brake": 1.0, "reverse": true, "headlights_enabled": true}
	shot["visual_fixture_only"] = true
	_captures.append(shot)


func _set_day() -> void:
	_environment.background_color = Color("b8c5ca")
	_environment.ambient_light_energy = 0.58
	_key.light_energy = 1.1
	_fill.light_energy = 0.34


func _set_night() -> void:
	_environment.background_color = Color("080f1b")
	_environment.ambient_light_color = Color("223048")
	_environment.ambient_light_energy = 0.28
	_key.light_energy = 0.0
	_fill.light_energy = 0.04


func _set_camera_pose(offset: Vector3) -> void:
	var target := Vector3(0.0, _visual.root.position.y + 0.11, 0.0)
	_camera.position = target + offset
	_camera.look_at(target, Vector3.UP)


func _dust_fixture() -> Dictionary:
	return {
		"wheel_in_contact": PackedByteArray([1, 1, 1, 1]),
		"wheel_slip_speed_m_per_s": PackedFloat64Array([1.6, 1.6, 1.6, 1.6]),
		"speed_m_per_s": 5.2,
	}


func _sample_road(_north: float, _east: float) -> Dictionary:
	return {"surface_id": _fixture_surface, "height_m": 0.0}


func _save_capture(output: String, filename: String, label: String) -> Dictionary:
	for _frame in 3:
		await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := output.path_join(filename)
	var error := image.save_png(path)
	var result := {
		"label": label,
		"path": ProjectSettings.localize_path(path),
		"ok": error == OK and not image.is_empty(),
		"size": [image.get_width(), image.get_height()],
		"effects": _effects.diagnostic_snapshot(),
	}
	print("ground effects capture %s: %s %s" % [label, result.ok, JSON.stringify(result.effects)])
	return result


func _fail(message: String) -> void:
	printerr("RCV ground effects capture failed: " + message)
	quit(1)
