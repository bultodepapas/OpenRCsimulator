extends SceneTree

## Isolated, reproducible model/readability capture harness.

const AirplaneBuilder := preload("res://render/airplane.gd")
const Commands := preload("res://input/commands.gd")
const GeneratedGeometry := preload("res://aircraft/ugly_stik_geometry.gd")
const DEFAULT_IMAGE_SIZE := Vector2i(1280, 720)
const SHOWCASE_IMAGE_SIZE := Vector2i(2560, 1440)
var _image_size := DEFAULT_IMAGE_SIZE
const FLIGHT_FOV_DEG := 50.0
const FLIGHT_DISTANCES_M := [20.0, 50.0, 100.0]
const MOTION_SAMPLE_DT_S := 1.0 / 60.0
const PERF_WARMUP_FRAMES := 2
const PERF_SAMPLE_FRAMES := 3
const MODEL_HEIGHT_M := 5.0
const PILOT_EYE_HEIGHT_M := 1.6
const GROUND_Y_M := 0.0
const SKY_COLOR := Color("#9bcef0")
const ATTITUDE_CASES := [
	{
		"id": "P01",
		"blind_code": "K7",
		"title": "Lower wing face",
		"rotation_degrees": Vector3.ZERO,
		"surface": "underside",
		"bank": "level",
		"direction": "away",
	},
	{
		"id": "P02",
		"blind_code": "M2",
		"title": "Upper wing face",
		"rotation_degrees": Vector3(0.0, 0.0, 180.0),
		"surface": "upper side",
		"bank": "level",
		"direction": "away",
	},
	{
		"id": "P03",
		"blind_code": "R5",
		"title": "Left bank",
		"rotation_degrees": Vector3(0.0, 0.0, 35.0),
		"surface": "underside",
		"bank": "left",
		"direction": "away",
	},
	{
		"id": "P04",
		"blind_code": "A9",
		"title": "Right bank",
		"rotation_degrees": Vector3(0.0, 0.0, -35.0),
		"surface": "underside",
		"bank": "right",
		"direction": "away",
	},
	{
		"id": "P05",
		"blind_code": "C3",
		"title": "Nose toward pilot",
		"rotation_degrees": Vector3(0.0, 180.0, 0.0),
		"surface": "underside",
		"bank": "level",
		"direction": "toward",
	},
	{
		"id": "P06",
		"blind_code": "T8",
		"title": "Upper wing face, nose toward pilot",
		"rotation_degrees": Vector3(0.0, 180.0, 180.0),
		"surface": "upper side",
		"bank": "level",
		"direction": "toward",
	},
]

var _world_root: Node3D
var _airplane: Dictionary
var _camera: Camera3D
var _ground: MeshInstance3D
var _caption_title: Label
var _caption_detail: Label
var _environment: Environment
var _out_dir := ""
var _records: Array[Dictionary] = []
var _initial_mesh_visibility: Dictionary = {}
var _run_started_usec := 0
var _geometry_data: Dictionary = {}
var _suite := "inspection"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_run_started_usec = Time.get_ticks_usec()
	_out_dir = _output_directory()
	if _out_dir.is_empty():
		quit(2)
		return
	_suite = _capture_suite()
	if _suite.is_empty():
		quit(2)
		return
	var mkdir_error := DirAccess.make_dir_recursive_absolute(_out_dir)
	if mkdir_error != OK:
		push_error("Could not create output directory %s (Error %d)" % [_out_dir, mkdir_error])
		quit(1)
		return
	_image_size = SHOWCASE_IMAGE_SIZE if _suite == "showcase" else DEFAULT_IMAGE_SIZE
	get_root().size = _image_size
	get_root().title = "Ugly Stik model %s inspection" % _suite
	_geometry_data = _load_geometry_data()
	if _geometry_data.is_empty():
		push_error("Could not read geometry source JSON")
		quit(1)
		return

	_world_root = Node3D.new()
	_world_root.name = "InspectionWorld"
	get_root().add_child(_world_root)
	_add_lighting()
	_add_airplane()
	if not _airplane.has("root") or not (_airplane.root is Node3D):
		push_error("Cannot capture because the airplane builder did not return a root Node3D")
		quit(1)
		return
	_airplane.root.set_meta("visual_revision", "jensen-61-classic-red-v4")
	_airplane.root.set_meta("appearance_data_path", "res://../assets/aircraft/ugly-stik-60/appearance.json")
	_airplane.root.set_meta("appearance_generated_script", "res://aircraft/ugly_stik_appearance.gd")
	_airplane.root.set_meta("livery_source_path", "res://aircraft/livery.svg")
	_airplane.root.set_meta("appearance_atlas_runtime_path", "runtime://ImageTexture from ugly_stik_appearance.gd::SVG_SOURCE via ugly_stik_finish.gd::atlas")
	_snapshot_mesh_visibility()
	_add_camera()
	_add_ground()
	_add_caption()

	await process_frame
	await RenderingServer.frame_post_draw
	for capture in _capture_definitions():
		_apply_capture(capture)
		var frame_samples: Array[float] = await _settle_and_sample_frames()
		var image := get_root().get_texture().get_image()
		var output_path := _out_dir.path_join(String(capture.filename))
		var error := image.save_png(output_path)
		if error != OK:
			push_error("Could not write capture %s (Error %d)" % [output_path, error])
			quit(1)
			return
		var record := _capture_record(capture, output_path)
		record["frame_elapsed_samples_ms"] = frame_samples
		record["render_counters"] = _render_counters()
		record["png_sha256"] = _sha256_file(output_path)
		if not bool(capture.get("expected_crop", false)) and not bool(record.geometry_vertices_inside_viewport):
			push_error("Model geometry is cropped in capture %s; inspect its manifest crop check" % capture.filename)
			quit(1)
			return
		_records.append(record)
		print("Captured %s" % output_path)

	_write_manifest()
	quit(0)


func _output_directory() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			var output_path := ProjectSettings.globalize_path(argument.trim_prefix("--output-dir=")).simplify_path()
			for historical_dir in [
				ProjectSettings.globalize_path("res://../research/ugly-stik/model-v1").simplify_path(),
				ProjectSettings.globalize_path("res://../research/ugly-stik/model-v2").simplify_path(),
				ProjectSettings.globalize_path("res://../research/ugly-stik/model-v3").simplify_path(),
			]:
				if output_path == historical_dir or output_path.begins_with(historical_dir + "/"):
					push_error("Refusing to write current-model captures into historical evidence: %s" % output_path)
					return ""
			return output_path
	push_error("Capture needs --output-dir=<directory>")
	return ""


func _capture_suite() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--suite="):
			var requested_suite := argument.trim_prefix("--suite=")
			if requested_suite in ["inspection", "readability36", "details", "motion", "beauty", "showcase"]:
				return requested_suite
			push_error("Unknown capture suite '%s'; expected inspection, readability36, details, motion, beauty, or showcase" % requested_suite)
			return ""
	return "inspection"


func _load_geometry_data() -> Dictionary:
	return GeneratedGeometry.DATA


func _add_lighting() -> void:
	var environment_node := WorldEnvironment.new()
	_environment = Environment.new()
	var dark_studio := _suite in ["inspection", "details", "motion", "beauty", "showcase"]
	var neutral_studio := _suite in ["details", "motion", "beauty", "showcase"]
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Color("#111820") if dark_studio else SKY_COLOR
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color("#c8c8c8") if neutral_studio else (Color("#b8c3d1") if dark_studio else Color("#c5d3df"))
	_environment.ambient_light_energy = 0.45 if _suite == "showcase" else (0.30 if neutral_studio else (0.55 if dark_studio else 0.7))
	environment_node.environment = _environment
	_world_root.add_child(environment_node)

	var key_light := DirectionalLight3D.new()
	key_light.name = "KeyLight"
	key_light.rotation_degrees = Vector3(-47.0, -32.0, -9.0)
	key_light.light_color = Color.WHITE if _suite in ["details", "motion", "beauty", "showcase"] else Color("#fff3e1")
	key_light.light_energy = 0.90 if neutral_studio else 1.45
	key_light.shadow_enabled = true
	_world_root.add_child(key_light)

	if _suite in ["inspection", "details", "motion", "beauty", "showcase"]:
		var fill_light := DirectionalLight3D.new()
		fill_light.name = "FillLight"
		fill_light.rotation_degrees = Vector3(-24.0, 145.0, 12.0)
		fill_light.light_color = Color("#ffffff") if neutral_studio else Color("#c9d9ff")
		fill_light.light_energy = 0.38 if _suite == "showcase" else (0.16 if neutral_studio else 0.35)
		_world_root.add_child(fill_light)

	var underside_fill := DirectionalLight3D.new()
	underside_fill.name = "UndersideFill"
	underside_fill.rotation_degrees = Vector3(48.0, -28.0, 0.0)
	underside_fill.light_color = Color("#e0e0e0") if neutral_studio else Color("#becbe0")
	underside_fill.light_energy = 0.40 if _suite == "showcase" else (0.25 if neutral_studio else 0.7)
	_world_root.add_child(underside_fill)


func _lighting_information() -> Dictionary:
	var dark_studio := _suite in ["inspection", "details", "motion", "beauty", "showcase"]
	var neutral_key := _suite in ["details", "motion", "beauty", "showcase"]
	var ambient_color := "#c8c8c8" if neutral_key else ("#b8c3d1" if dark_studio else "#c5d3df")
	var underside_color := "#e0e0e0" if neutral_key else "#becbe0"
	var fill_color := "#ffffff" if neutral_key else "#c9d9ff"
	var lights: Array[Dictionary] = [
		{"name": "KeyLight", "rotation_degrees": [-47.0, -32.0, -9.0], "color_srgb_hex": "#ffffff" if neutral_key else "#fff3e1", "energy": 0.90 if neutral_key else 1.45, "shadows": true},
		{"name": "UndersideFill", "rotation_degrees": [48.0, -28.0, 0.0], "color_srgb_hex": underside_color, "energy": 0.40 if _suite == "showcase" else (0.25 if neutral_key else 0.7), "shadows": false},
	]
	if dark_studio:
		lights.insert(1, {"name": "FillLight", "rotation_degrees": [-24.0, 145.0, 12.0], "color_srgb_hex": fill_color, "energy": 0.38 if _suite == "showcase" else (0.16 if neutral_key else 0.35), "shadows": false})
	return {
		"environment_background": "solid color",
		"background_color_srgb_hex": "#111820" if dark_studio else "#9bcef0",
		"ambient_source": "color",
		"ambient_color_srgb_hex": ambient_color,
		"ambient_energy": 0.45 if _suite == "showcase" else (0.30 if neutral_key else (0.55 if dark_studio else 0.7)),
		"neutral_key_light": neutral_key,
		"directional_lights": lights,
	}


func _add_airplane() -> void:
	_airplane = AirplaneBuilder.build()
	for required_key in ["root", "propeller", "hinges"]:
		if not _airplane.has(required_key):
			push_error("Airplane builder is missing dictionary key '%s'" % required_key)
			quit(1)
			return
	if not (_airplane.root is Node3D and _airplane.propeller is Node3D and _airplane.hinges is Dictionary):
		push_error("Airplane builder returned an invalid root, propeller, or hinges value")
		quit(1)
		return
	for hinge_name in ["aileron_left", "aileron_right", "elevator", "rudder"]:
		if not _airplane.hinges.has(hinge_name) or not (_airplane.hinges[hinge_name] is Node3D):
			push_error("Airplane builder is missing Node3D hinge '%s'" % hinge_name)
			quit(1)
			return
	_world_root.add_child(_airplane.root)


func _add_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "InspectionCamera"
	_camera.current = true
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.near = 0.02
	_camera.far = 500.0
	_world_root.add_child(_camera)


func _add_ground() -> void:
	_ground = MeshInstance3D.new()
	_ground.name = "GroundReference"
	var plane := PlaneMesh.new()
	plane.orientation = PlaneMesh.FACE_Y
	plane.size = Vector2(1000.0, 1000.0)
	_ground.mesh = plane
	_ground.position.y = GROUND_Y_M
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("#58654f")
	_ground.material_override = material
	_world_root.add_child(_ground)


func _add_caption() -> void:
	var caption_scale := float(_image_size.y) / DEFAULT_IMAGE_SIZE.y
	var layer := CanvasLayer.new()
	layer.name = "Caption"
	get_root().add_child(layer)

	_caption_title = Label.new()
	_caption_title.position = Vector2(22.0, 18.0) * caption_scale
	_caption_title.add_theme_font_size_override("font_size", int(21 * caption_scale))
	_caption_title.add_theme_color_override("font_color", Color("#ffffff"))
	_caption_title.add_theme_color_override("font_shadow_color", Color("#101820"))
	_caption_title.add_theme_constant_override("shadow_offset_x", 2)
	_caption_title.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(_caption_title)

	_caption_detail = Label.new()
	_caption_detail.position = Vector2(22.0, 49.0) * caption_scale
	_caption_detail.add_theme_font_size_override("font_size", int(14 * caption_scale))
	_caption_detail.add_theme_color_override("font_color", Color("#f0f3f5"))
	_caption_detail.add_theme_color_override("font_shadow_color", Color("#101820"))
	_caption_detail.add_theme_constant_override("shadow_offset_x", 1)
	_caption_detail.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(_caption_detail)


func _neutral_capture_commands() -> Dictionary:
	var neutral: Dictionary = Commands.neutral_commands()
	return {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": float(neutral.throttle)}


func _capture_definitions() -> Array[Dictionary]:
	match _suite:
		"readability36":
			return _readability_capture_definitions()
		"details":
			return _details_capture_definitions()
		"motion":
			return _motion_capture_definitions()
		"beauty":
			return _beauty_capture_definitions()
		"showcase":
			return _showcase_capture_definitions()
		_:
			return _inspection_capture_definitions()


func _settle_and_sample_frames() -> Array[float]:
	for _warmup in PERF_WARMUP_FRAMES:
		await process_frame
		await RenderingServer.frame_post_draw
	var samples: Array[float] = []
	for _sample in PERF_SAMPLE_FRAMES:
		var started_usec := Time.get_ticks_usec()
		await process_frame
		await RenderingServer.frame_post_draw
		samples.append(float(Time.get_ticks_usec() - started_usec) / 1000.0)
	return samples


func _macro_capture(filename: String, case_id: String, title: String, detail: String, camera_position: Vector3, camera_target: Vector3, fov_deg := 34.0, hidden_rules: Array[String] = []) -> Dictionary:
	return {
		"filename": filename,
		"case_id": case_id,
		"title": title,
		"detail": detail,
		"projection": Camera3D.PROJECTION_PERSPECTIVE,
		"fov_vertical_deg": fov_deg,
		"size": 1.0,
		"camera_position": camera_position,
		"camera_target": camera_target,
		"camera_up": Vector3.UP,
		"model_position": Vector3.ZERO,
		"model_rotation_degrees": Vector3.ZERO,
		"pose_name": "neutral",
		"commands": _neutral_capture_commands(),
		"background": "inspection",
		"expected_crop": true,
		"expected_crop_reason": "Close inspection intentionally frames one assembly; the rest of the airplane may leave the viewport.",
		"hidden_mesh_name_rules": hidden_rules,
	}


func _details_capture_definitions() -> Array[Dictionary]:
	var captures: Array[Dictionary] = [
		_macro_capture("engine-left.png", "engine-left", "MOTOR · LADO IZQUIERDO", "Primer plano del costado izquierdo · luz neutra · recorte de inspección", Vector3(-0.24, 0.015, -0.315), Vector3(0.0, 0.005, -0.315)),
		_macro_capture("engine-right.png", "engine-right", "MOTOR · LADO DERECHO", "Primer plano del costado derecho y silenciador · luz neutra", Vector3(0.24, 0.015, -0.315), Vector3(0.0, 0.005, -0.315)),
		_macro_capture("engine-front.png", "engine-front", "MOTOR · FRENTE", "Vista desde el eje de hélice; se ocultan solo las mallas de hélice para inspeccionar el motor", Vector3(0.0, 0.01, -0.64), Vector3(0.0, 0.005, -0.315), 32.0, ["propeller_*"]),
		_macro_capture("wing-root.png", "wing-root", "RAÍZ ALAR · RETENCIÓN", "Unión central, bandas y recubrimiento · posición real del montaje", Vector3(0.27, 0.33, 0.25), Vector3(0.0, 0.055, 0.025), 36.0),
		_macro_capture("gear-main.png", "gear-main", "TREN PRINCIPAL", "Macrofotografía del tren principal, anclaje y rueda", Vector3(0.36, -0.06, 0.36), Vector3(0.0, -0.17, 0.10), 34.0),
		_macro_capture("gear-nose.png", "gear-nose", "TREN DE MORRO", "Macrofotografía de rueda, horquilla y dirección", Vector3(0.22, -0.09, -0.40), Vector3(0.0, -0.17, -0.25), 34.0),
		_macro_capture("tail-controls.png", "tail-controls", "COLA · CUERNOS Y MANDOS", "Vista cercana de elevador, timón, cuernos y transmisiones", Vector3(0.24, 0.20, 0.63), Vector3(0.0, 0.025, 0.79), 35.0),
		_macro_capture("elevator-linkage.png", "elevator-linkage", "ELEVADOR · TRANSMISIÓN INFERIOR", "Cuerno, varilla y guía · vista inferior con superficies montadas", Vector3(-0.18, -0.22, 0.65), Vector3(-0.035, -0.014, 0.79), 38.0),
		_macro_capture("aileron-linkage.png", "aileron-linkage", "ALERÓN · TRANSMISIÓN EXTERIOR", "Cuerno y varilla bajo el ala montada", Vector3(0.28, -0.15, 0.24), Vector3(0.185, 0.025, 0.11), 38.0),
		_macro_capture("maintenance.png", "maintenance", "MANTENIMIENTO · EQUIPO INTERNO", "Se ocultan mallas de fuselaje y ala; el equipo conserva sus transformaciones de montaje", Vector3(0.40, 0.45, 0.32), Vector3(0.0, 0.005, 0.06), 46.0, ["fuselage", "wing_left_*", "wing_right_*", "fixed_te_*", "aileron_left", "aileron_right"]),
		_macro_capture("maintenance-servos.png", "maintenance-servos", "SERVOS · INSTALACIÓN", "Carcasas, soportes y brazos en su posición montada · piel oculta", Vector3(0.16, 0.18, 0.21), Vector3(0.0, -0.015, 0.045), 38.0, ["fuselage", "wing_left_*", "wing_right_*", "fixed_te_*", "aileron_left", "aileron_right"]),
		_macro_capture("maintenance-wing.png", "maintenance-wing", "ALERÓN · SERVO Y REENVÍO", "Vista inferior de transmisión de raíz · montaje real con piel oculta", Vector3(0.18, -0.18, 0.19), Vector3(0.12, 0.025, 0.04), 38.0, ["fuselage", "wing_left_*", "wing_right_*", "fixed_te_*", "aileron_left", "aileron_right"]),
	]
	for capture in captures:
		capture["maintenance_view"] = String(capture.case_id).begins_with("maintenance")
	return captures


func _motion_capture_definitions() -> Array[Dictionary]:
	var captures: Array[Dictionary] = []
	var neutral := _neutral_capture_commands()
	var pose_specs: Array[Dictionary] = [
		{"id": "neutral", "roll": 0.0, "pitch": 0.0, "yaw": 0.0},
		{"id": "roll-left-full", "roll": -0.8, "pitch": 0.0, "yaw": 0.0},
		{"id": "roll-left-half", "roll": -0.4, "pitch": 0.0, "yaw": 0.0},
		{"id": "roll-right-half", "roll": 0.4, "pitch": 0.0, "yaw": 0.0},
		{"id": "roll-right-full", "roll": 0.8, "pitch": 0.0, "yaw": 0.0},
		{"id": "pitch-down-full", "roll": 0.0, "pitch": -0.8, "yaw": 0.0},
		{"id": "pitch-down-half", "roll": 0.0, "pitch": -0.4, "yaw": 0.0},
		{"id": "pitch-up-half", "roll": 0.0, "pitch": 0.4, "yaw": 0.0},
		{"id": "pitch-up-full", "roll": 0.0, "pitch": 0.8, "yaw": 0.0},
		{"id": "yaw-left-full", "roll": 0.0, "pitch": 0.0, "yaw": -0.8},
		{"id": "yaw-right-full", "roll": 0.0, "pitch": 0.0, "yaw": 0.8},
		{"id": "combined", "roll": 0.45, "pitch": -0.35, "yaw": 0.3},
	]
	for index in pose_specs.size():
		var spec: Dictionary = pose_specs[index]
		var commands := neutral.duplicate()
		commands.roll = float(spec.roll)
		commands.pitch = float(spec.pitch)
		commands.yaw = float(spec.yaw)
		captures.append({
			"filename": "controls-%02d-%s.png" % [index + 1, spec.id],
			"case_id": "controls-%02d-%s" % [index + 1, spec.id],
			"title": "MANDOS · %02d/12 · %s" % [index + 1, String(spec.id).to_upper()],
			"detail": "Pose directa reproducible · Δt fijo %.5f s · no usa tiempo real" % MOTION_SAMPLE_DT_S,
			"projection": Camera3D.PROJECTION_ORTHOGONAL,
			"size": 1.78,
			"camera_position": Vector3(1.9, 1.35, 1.65),
			"camera_target": Vector3(0.0, 0.0, 0.10),
			"camera_up": Vector3.UP,
			"model_position": Vector3.ZERO,
			"model_rotation_degrees": Vector3.ZERO,
			"pose_name": String(spec.id),
			"commands": commands,
			"background": "inspection",
			"motion_kind": "control_pose",
			"motion_sample_index": index,
			"motion_time_s": float(index) * MOTION_SAMPLE_DT_S,
			"fixed_timestep_s": MOTION_SAMPLE_DT_S,
			"expected_crop": false,
		})
	for index in pose_specs.size():
		var opened: Dictionary = captures[index].duplicate(true)
		opened.filename = "maintenance-%02d-%s.png" % [index + 1, pose_specs[index].id]
		opened.case_id = "maintenance-%02d-%s" % [index + 1, pose_specs[index].id]
		opened.title = "MANDOS ABIERTOS · %02d/12" % (index + 1)
		opened.maintenance_view = true
		opened.hidden_mesh_name_rules = ["fuselage", "wing_left_*", "wing_right_*", "fixed_te_*", "aileron_left", "aileron_right"]
		opened.projection = Camera3D.PROJECTION_PERSPECTIVE
		opened.fov_vertical_deg = 40.0
		opened.camera_position = Vector3(0.25, 0.28, 0.25)
		opened.camera_target = Vector3(0.0, 0.01, 0.06)
		opened.expected_crop = true
		opened.expected_crop_reason = "Close maintenance view of servo arms and root transmission."
		opened.motion_kind = "maintenance_control_pose"
		captures.append(opened)
	var sweep_target := Vector3(0.45, 0.09, 0.02)
	for index in 12:
		var fraction := float(index) / 11.0
		var offset_x := lerpf(-0.03, 0.03, fraction)
		captures.append({
			"filename": "camera-sweep-%02d.png" % (index + 1),
			"case_id": "camera-sweep-%02d" % (index + 1),
			"title": "DESPLAZAMIENTO DE CÁMARA · %02d/12" % (index + 1),
			"detail": "Recubrimiento cercano · cámara se traslada 60 mm en 12 muestras · Δt fijo %.5f s" % MOTION_SAMPLE_DT_S,
			"projection": Camera3D.PROJECTION_PERSPECTIVE,
			"fov_vertical_deg": 30.0,
			"size": 1.0,
			"camera_position": Vector3(0.45 + offset_x, 0.30, 0.30),
			"camera_target": sweep_target,
			"camera_up": Vector3.UP,
			"model_position": Vector3.ZERO,
			"model_rotation_degrees": Vector3.ZERO,
			"pose_name": "neutral",
			"commands": neutral.duplicate(),
			"background": "inspection",
			"motion_kind": "camera_sweep",
			"motion_sample_index": index,
			"motion_time_s": float(index) * MOTION_SAMPLE_DT_S,
			"fixed_timestep_s": MOTION_SAMPLE_DT_S,
			"camera_offset_x_m": offset_x,
			"expected_crop": true,
			"expected_crop_reason": "Close surface-detail sweep; the remainder of the airplane is intentionally outside frame.",
		})
	return captures


# US-V07: an automatic high-resolution tour; legacy comparison cameras stay fixed.
func _showcase_capture_definitions() -> Array[Dictionary]:
	var captures: Array[Dictionary] = []
	var target := Vector3(0, 0, 0.19)
	var angles := [
		["front-left", "TRES CUARTOS · FRENTE IZQUIERDO", Vector3(-1.55, 0.9, -1.55)],
		["front-right", "TRES CUARTOS · FRENTE DERECHO", Vector3(1.55, 0.8, -1.55)],
		["rear-left", "TRES CUARTOS · COLA IZQUIERDA", Vector3(-1.55, 1.08, 1.9)],
		["rear-right", "TRES CUARTOS · COLA DERECHA", Vector3(1.55, 0.75, 1.9)],
		["underside", "INTRADÓS · TREN Y TRANSMISIONES", Vector3(1.30, -1.15, -1.4)],
		["overhead", "PLANTA · DECORACIÓN Y MONTAJE", Vector3(0, 2.35, 0.19)],
		["nose-level", "FRENTE · DIEDRO Y TREN", Vector3(0, 0.10, -2.35)],
		["tail-level", "COLA · EMPENAJE Y MANDOS", Vector3(0.95, 0.32, 2.40)],
	]
	for angle in angles:
		var capture := _macro_capture("aircraft-" + angle[0] + ".png", "aircraft-" + angle[0], angle[1], "Avión completo · modelo real de Godot · 2560 × 1440", angle[2], target, 43.0 if angle[0] == "overhead" else 34.0)
		capture["category"] = "General"
		capture["expected_crop"] = false
		capture["expected_crop_reason"] = ""
		if angle[0] == "overhead": capture["camera_up"] = Vector3.FORWARD
		captures.append(capture)

	# Keep the twelve installed-equipment views, now rendered at twice the width/height.
	for capture in _details_capture_definitions():
		var id: String = capture.case_id
		capture["category"] = "Motor" if id.begins_with("engine") else ("Servos" if id.begins_with("maintenance") else ("Mandos" if id.contains("linkage") or id == "tail-controls" else "Montaje"))
		if id == "gear-main":
			capture["camera_position"] = Vector3(0.44, -0.14, 0.36)
			capture["camera_target"] = Vector3(0.08, -0.16, 0.10)
			capture["fov_vertical_deg"] = 44.0
		captures.append(capture)

	# Camera offsets are artistic inspection choices relative to the actual engine datum.
	var equipment: Dictionary = GeneratedGeometry.DATA.equipment
	var center := Vector3(0, float(equipment.shaft_y), (float(equipment.firewall_z) + float(equipment.prop_z)) * 0.5)
	var engine_angles := [
		["engine-three-quarter-right", "MOTOR · TRES CUARTOS DERECHO", "Culata, carburador y escape montados", Vector3(0.19, 0.12, -0.19), Vector3(0.015, 0.01, 0.005), 31.0],
		["engine-three-quarter-left", "MOTOR · TRES CUARTOS IZQUIERDO", "Cárter, aletas y bancada · instalación completa", Vector3(-0.18, 0.10, -0.17), Vector3(0.0, 0.01, 0.005), 31.0],
		["engine-overhead", "MOTOR · VISTA SUPERIOR", "Culata dorada, bujía y circuitos visibles", Vector3(0.025, 0.24, -0.04), Vector3(0.02, 0.0, 0.005), 32.0],
		["engine-head", "CULATA · BUJÍA Y ALETAS", "Primer plano de la corona y refrigeración", Vector3(-0.09, 0.13, -0.09), Vector3(0, 0.032, 0.01), 27.0],
		["engine-carburetor", "CARBURADOR · ADMISIÓN Y BRAZO", "Hélice oculta para inspeccionar la garganta y su mando", Vector3(0.10, 0.10, -0.14), Vector3(0.005, 0.022, -0.023), 26.0],
		["engine-exhaust", "ESCAPE · NERVADURAS Y RACOR", "Costado exterior del silenciador y conexión de presión", Vector3(0.22, 0.065, 0.07), Vector3(0.046, 0, 0.015), 27.0],
		["engine-outlet", "ESCAPE · BOQUILLA Y CONO", "Vista posterior oblicua de la salida hueca", Vector3(0.17, -0.07, 0.14), Vector3(0.06, -0.015, 0.033), 25.0],
		["engine-mount", "MOTOR · BANCADA Y ALIMENTACIÓN", "Vista inferior de apoyos, fijaciones y manguera de combustible", Vector3(-0.14, -0.15, -0.065), Vector3(0.0, -0.01, 0.015), 34.0],
	]
	for angle in engine_angles:
		var hidden: Array[String] = []
		if angle[0] == "engine-carburetor": hidden.append("propeller_*")
		var capture := _macro_capture(angle[0] + ".png", angle[0], angle[1], angle[2], center + angle[3], center + angle[4], angle[5], hidden)
		capture["category"] = "Motor"
		captures.append(capture)
	return captures


func _beauty_capture_definitions() -> Array[Dictionary]:
	var neutral := _neutral_capture_commands()
	var captures: Array[Dictionary] = [
		{
			"filename": "beauty-a-dark.png", "case_id": "beauty-a-dark", "title": "JENSEN UGLY STIK · ESTUDIO",
			"detail": "Tres cuartos trasero · fondo oscuro · luz neutra", "projection": Camera3D.PROJECTION_PERSPECTIVE,
			"fov_vertical_deg": 42.0, "size": 1.0, "camera_position": Vector3(-1.55, 1.08, 1.72),
			"camera_target": Vector3(0.0, 0.0, 0.10), "camera_up": Vector3.UP,
			"model_position": Vector3.ZERO, "model_rotation_degrees": Vector3.ZERO, "pose_name": "neutral",
			"commands": neutral.duplicate(), "background": "dark", "background_color": Color("#111820"),
			"expected_crop": false,
		},
		{
			"filename": "beauty-b-sky.png", "case_id": "beauty-b-sky", "title": "JENSEN UGLY STIK · EN VUELO",
			"detail": "Tres cuartos trasero · cielo azul · luz neutra", "projection": Camera3D.PROJECTION_PERSPECTIVE,
			"fov_vertical_deg": 44.0, "size": 1.0, "camera_position": Vector3(1.50, 0.92, 1.82),
			"camera_target": Vector3(0.0, 0.0, 0.10), "camera_up": Vector3.UP,
			"model_position": Vector3.ZERO, "model_rotation_degrees": Vector3.ZERO, "pose_name": "neutral",
			"commands": neutral.duplicate(), "background": "sky", "background_color": SKY_COLOR,
			"expected_crop": false,
		},
	]
	return captures


func _inspection_capture_definitions() -> Array[Dictionary]:
	var neutral := _neutral_capture_commands()
	var deflected: Dictionary = neutral.duplicate()
	deflected.roll = 0.75
	deflected.pitch = 0.75
	deflected.yaw = 0.75
	var views: Array[Dictionary] = [
		{
			"filename": "top.png", "case_id": "top", "title": "PLANTA · NEUTRO",
			"detail": "Ortográfica superior · coordenadas de modelo en metros · Jensen Ugly Stik 60 / .61",
			"projection": Camera3D.PROJECTION_ORTHOGONAL, "size": 1.90,
			"camera_position": Vector3(0.0, 5.0, 0.0), "camera_target": Vector3.ZERO,
			"camera_up": Vector3(0.0, 0.0, -1.0), "pose_name": "neutral",
			"commands": neutral.duplicate(),
		},
		{
			"filename": "bottom.png", "case_id": "bottom", "title": "INTRADÓS · NEUTRO",
			"detail": "Ortográfica inferior · misma geometría y encuadre que la planta",
			"projection": Camera3D.PROJECTION_ORTHOGONAL, "size": 1.90,
			"camera_position": Vector3(0.0, -5.0, 0.0), "camera_target": Vector3.ZERO,
			"camera_up": Vector3(0.0, 0.0, -1.0), "pose_name": "neutral",
			"commands": neutral.duplicate(),
		},
		{
			"filename": "side.png", "case_id": "side", "title": "PERFIL · NEUTRO",
			"detail": "Ortográfica desde el costado derecho · morro hacia la derecha de imagen",
			"projection": Camera3D.PROJECTION_ORTHOGONAL, "size": 1.05,
			"camera_position": Vector3(4.0, 0.0, 0.0), "camera_target": Vector3.ZERO,
			"camera_up": Vector3.UP, "pose_name": "neutral",
			"commands": neutral.duplicate(),
		},
		{
			"filename": "front.png", "case_id": "front", "title": "FRENTE · NEUTRO",
			"detail": "Ortográfica · desde el morro · envergadura horizontal",
			"projection": Camera3D.PROJECTION_ORTHOGONAL, "size": 0.92,
			"camera_position": Vector3(0.0, 0.0, -4.0), "camera_target": Vector3.ZERO,
			"camera_up": Vector3.UP, "pose_name": "neutral",
			"commands": neutral.duplicate(),
		},
		{
			"filename": "three-quarter-neutral.png", "case_id": "three-quarter-neutral", "title": "TRES CUARTOS · NEUTRO",
			"detail": "Perspectiva de inspección · sin deflexiones de mandos",
			"projection": Camera3D.PROJECTION_PERSPECTIVE, "fov_vertical_deg": 38.0, "size": 1.0,
			"camera_position": Vector3(-1.29, 0.99, 1.65), "camera_target": Vector3.ZERO,
			"camera_up": Vector3.UP, "pose_name": "neutral",
			"commands": neutral.duplicate(),
		},
		{
			"filename": "three-quarter-deflected.png", "case_id": "three-quarter-deflected", "title": "TRES CUARTOS · MANDOS DESVIADOS",
			"detail": "Pose demostrativa fija · alerones, elevador y timón articulados",
			"projection": Camera3D.PROJECTION_PERSPECTIVE, "fov_vertical_deg": 38.0, "size": 1.0,
			"camera_position": Vector3(-1.29, 0.99, 1.65), "camera_target": Vector3.ZERO,
			"camera_up": Vector3.UP, "pose_name": "deflected",
			"commands": deflected,
		},
	]
	for distance in FLIGHT_DISTANCES_M:
		views.append({
			"filename": "flight-%dm.png" % int(distance),
			"case_id": "flight-%dm" % int(distance),
			"title": "LECTURA EN VUELO · %d m" % int(distance),
			"detail": "1280×720 · FOV vertical 50° · KEEP_HEIGHT · geometría idéntica",
			"projection": Camera3D.PROJECTION_PERSPECTIVE, "fov_vertical_deg": FLIGHT_FOV_DEG, "size": 1.0,
			"camera_position": Vector3(0.0, 0.0, distance), "camera_target": Vector3.ZERO,
			"camera_up": Vector3.UP, "pose_name": "neutral",
			"commands": neutral.duplicate(), "distance_m": distance,
		})
	for capture in views:
		capture["model_position"] = Vector3.ZERO
		capture["model_rotation_degrees"] = Vector3.ZERO
		capture["background"] = "inspection"
	return views


func _readability_capture_definitions() -> Array[Dictionary]:
	var captures: Array[Dictionary] = []
	for distance in FLIGHT_DISTANCES_M:
		for background_name in ["sky", "ground"]:
			for attitude in ATTITUDE_CASES:
				var blind_code := String(attitude.blind_code)
				captures.append({
					"filename": "d%03dm-%s-%s.png" % [int(distance), background_name, blind_code.to_lower()],
					"case_id": "D%03d-%s-%s" % [int(distance), background_name.to_upper(), blind_code],
					"condition": "%d m · %s" % [int(distance), "sky" if background_name == "sky" else "ground"],
					"title": "D%03d-%s-%s" % [int(distance), background_name.to_upper(), blind_code],
					"detail": "%d m · %s · neutral control hinges" % [int(distance), background_name],
					"distance_m": distance,
					"background": background_name,
					"attitude_id": attitude.id,
					"attitude_title": attitude.title,
					"projection": Camera3D.PROJECTION_PERSPECTIVE,
					"fov_vertical_deg": FLIGHT_FOV_DEG,
					"size": 1.0,
					"model_position": Vector3(0.0, MODEL_HEIGHT_M, 0.0),
					"model_rotation_degrees": attitude.rotation_degrees,
					"camera_position": Vector3(0.0, PILOT_EYE_HEIGHT_M, distance),
					"camera_target": Vector3(0.0, MODEL_HEIGHT_M, 0.0),
					"camera_up": Vector3.UP,
					"pose_name": "neutral_hinges",
					"commands": _neutral_capture_commands(),
					"reference_answer": {"surface": attitude.surface, "bank": attitude.bank, "direction": attitude.direction},
				})
	return captures


func _apply_capture(capture: Dictionary) -> void:
	_restore_mesh_visibility()
	AirplaneBuilder.set_maintenance(_airplane, bool(capture.get("maintenance_view", false)))
	var hidden_rules: Array = capture.get("hidden_mesh_name_rules", [])
	for instance in _all_mesh_instances():
		for rule in hidden_rules:
			if _mesh_name_matches_rule(instance.name.to_lower(), String(rule).to_lower()):
				instance.visible = false
				break
	_airplane.root.position = capture.model_position
	_airplane.root.rotation_degrees = capture.model_rotation_degrees
	var commands: Dictionary = capture.commands
	AirplaneBuilder.apply_surfaces(_airplane, Commands.hinge_rotations(commands))
	_ground.visible = String(capture.background) == "ground"
	if capture.has("background_color"):
		_environment.background_color = capture.background_color
	elif String(capture.background) == "dark" or String(capture.background) == "inspection":
		_environment.background_color = Color("#111820")
	elif String(capture.background) == "sky":
		_environment.background_color = SKY_COLOR
	_camera.projection = int(capture.projection)
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.fov = float(capture.get("fov_vertical_deg", FLIGHT_FOV_DEG))
	_camera.size = float(capture.get("size", 1.0))
	_camera.position = capture.camera_position
	_camera.look_at(capture.camera_target, capture.camera_up)
	_camera.force_update_transform()
	_caption_title.text = String(capture.get("title", capture.get("case_id", "")))
	_caption_detail.text = String(capture.get("detail", ""))


func _capture_record(capture: Dictionary, output_path: String) -> Dictionary:
	var camera_position: Vector3 = _camera.global_position
	var camera_target: Vector3 = capture.camera_target
	var camera_up := _camera.global_transform.basis.y.normalized()
	var actual_range := camera_position.distance_to(camera_target)
	var is_perspective := int(capture.projection) == Camera3D.PROJECTION_PERSPECTIVE
	var fov_vertical_deg := float(capture.get("fov_vertical_deg", 0.0))
	var vertical_fov := deg_to_rad(fov_vertical_deg)
	var visible_vertical := 2.0 * actual_range * tan(vertical_fov / 2.0) if is_perspective else _camera.size
	var bounds := _model_bounds()
	var crop_check := _camera_bounds_check()
	var actual_commands: Dictionary = capture.commands
	var record := {
		"suite": _suite,
		"case_id": capture.case_id,
		"file": output_path.get_file(),
		"category": capture.get("category", "General"),
		"detail": capture.get("detail", ""),
		"condition": capture.get("condition", capture.get("title", "")),
		"range_slant_m": actual_range,
		"background": capture.background,
		"attitude_id": capture.get("attitude_id", ""),
		"attitude_title": capture.get("attitude_title", ""),
		"pose": capture.pose_name,
		"commands": actual_commands,
		"visual_revision": String(_airplane.root.get_meta("visual_revision", "unknown")),
		"appearance_atlas_runtime_path": String(_airplane.root.get_meta("appearance_atlas_runtime_path", "unknown")),
		"root_pose": {
			"position_m": _vector_array(capture.model_position),
			"rotation_degrees": _vector_array(capture.model_rotation_degrees),
		},
		"camera": {
			"position_world_m": _vector_array(camera_position),
			"target_world_m": _vector_array(camera_target),
			"requested_up_world": _vector_array(capture.camera_up),
			"result_up_world": _vector_array(camera_up),
			"projection": "perspective" if is_perspective else "orthographic",
			"fov_vertical_deg": fov_vertical_deg if is_perspective else null,
			"size": _camera.size,
			"keep_aspect": "KEEP_HEIGHT",
			"viewport_px": [_image_size.x, _image_size.y],
			"aspect_ratio": float(_image_size.x) / float(_image_size.y),
			"near_m": _camera.near,
			"far_m": _camera.far,
			"visible_vertical_m_at_target": visible_vertical,
		},
		"render": _render_information(),
		"model_bounds_m": bounds,
		"geometry_vertices_inside_viewport": bool(crop_check.inside_viewport),
		"expected_crop": bool(capture.get("expected_crop", false)),
		"expected_crop_reason": String(capture.get("expected_crop_reason", "")),
		"crop_check_required": not bool(capture.get("expected_crop", false)),
		"actual_visible_geometry_crop_detected": not bool(crop_check.inside_viewport),
		"temporarily_hidden_mesh_name_rules": capture.get("hidden_mesh_name_rules", []),
		"maintenance_view": bool(capture.get("maintenance_view", false)),
		"component_transforms_unchanged": bool(capture.get("maintenance_view", false)),
		"projected_geometry_bounds_px": crop_check.bounds_px,
		"projected_geometry_margins_px": crop_check.margins_px,
		"mesh_instances": _mesh_instances().size(),
		"triangle_count": _triangle_count(),
		"material_count": _material_count(),
		"ground_plane": {
			"visible": String(capture.background) == "ground",
			"center_y_m": GROUND_Y_M,
			"color_srgb_hex": "#58654f",
			"material_shading": "unshaded",
			"plane_size_m": [1000.0, 1000.0],
		},
		"reference_answer": capture.get("reference_answer", {}),
	}
	if capture.has("distance_m"):
		record["distance_m"] = float(capture.distance_m)
	for key in ["motion_kind", "motion_sample_index", "motion_time_s", "fixed_timestep_s", "camera_offset_x_m"]:
		if capture.has(key):
			record[key] = capture[key]
	return record


func _render_information() -> Dictionary:
	var adapter_name := RenderingServer.get_video_adapter_name()
	var adapter_vendor := RenderingServer.get_video_adapter_vendor()
	var software_adapter := (adapter_name + " " + adapter_vendor).to_lower().contains("llvmpipe") or (adapter_name + " " + adapter_vendor).to_lower().contains("lavapipe")
	return {
		"godot_version": Engine.get_version_info(),
		"os_name": OS.get_name(),
		"rendering_method": String(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
		"requested_rendering_driver": OS.get_environment("OPENRC_CAPTURE_RENDER_DRIVER"),
		"display_driver": DisplayServer.get_name(),
		"video_adapter_name": adapter_name,
		"video_adapter_vendor": adapter_vendor,
		"anti_aliasing_msaa_3d": int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d")),
		"viewport_width_px": _image_size.x,
		"viewport_height_px": _image_size.y,
		"caption_layer": "CanvasLayer",
		"performance_classification": "software_renderer_no_hardware_benchmark" if software_adapter else "single_run_diagnostic_no_hardware_benchmark",
		"hardware_benchmark": false,
		"frame_elapsed_sample_method": "host wall time around process_frame through frame_post_draw; diagnostic only, not GPU time",
	}


func _model_bounds() -> Dictionary:
	var min_corner := Vector3(INF, INF, INF)
	var max_corner := Vector3(-INF, -INF, -INF)
	for instance in _mesh_instances():
		if instance.mesh == null:
			continue
		var aabb := instance.get_aabb()
		for x in [aabb.position.x, aabb.end.x]:
			for y in [aabb.position.y, aabb.end.y]:
				for z in [aabb.position.z, aabb.end.z]:
					var world_point := instance.global_transform * Vector3(x, y, z)
					var point: Vector3 = _airplane.root.to_local(world_point)
					min_corner = min_corner.min(point)
					max_corner = max_corner.max(point)
	return {
		"min": _vector_array(min_corner),
		"max": _vector_array(max_corner),
		"extent": _vector_array(max_corner - min_corner),
	}


func _camera_bounds_check() -> Dictionary:
	var min_screen := Vector2(INF, INF)
	var max_screen := Vector2(-INF, -INF)
	var behind_camera := false
	var vertex_count := 0
	for instance in _mesh_instances():
		if instance.mesh == null:
			continue
		for surface_index in range(instance.mesh.get_surface_count()):
			var arrays := instance.mesh.surface_get_arrays(surface_index)
			var vertex_data: Variant = arrays[Mesh.ARRAY_VERTEX]
			if not vertex_data is PackedVector3Array:
				continue
			for local_point in vertex_data:
				var world_point: Vector3 = instance.global_transform * local_point
				if _camera.is_position_behind(world_point):
					behind_camera = true
					continue
				var screen_point: Vector2 = _camera.unproject_position(world_point)
				min_screen = min_screen.min(screen_point)
				max_screen = max_screen.max(screen_point)
				vertex_count += 1
	var margins := Vector4(min_screen.x, min_screen.y, float(_image_size.x) - max_screen.x, float(_image_size.y) - max_screen.y)
	var inside := vertex_count > 0 and not behind_camera and margins.x >= 0.0 and margins.y >= 0.0 and margins.z >= 0.0 and margins.w >= 0.0
	return {
		"inside_viewport": inside,
		"vertex_count": vertex_count,
		"bounds_px": {"min": [min_screen.x, min_screen.y], "max": [max_screen.x, max_screen.y]},
		"margins_px": {"left": margins.x, "top": margins.y, "right": margins.z, "bottom": margins.w},
		"behind_camera": behind_camera,
	}


func _mesh_instances() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child in _all_mesh_instances():
		if child.is_visible_in_tree():
			result.append(child)
	return result


func _all_mesh_instances() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child in _airplane.root.find_children("*", "MeshInstance3D", true, false):
		result.append(child as MeshInstance3D)
	return result


func _snapshot_mesh_visibility() -> void:
	_initial_mesh_visibility.clear()
	for instance in _all_mesh_instances():
		_initial_mesh_visibility[instance] = instance.visible


func _restore_mesh_visibility() -> void:
	for instance in _initial_mesh_visibility:
		if is_instance_valid(instance):
			instance.visible = bool(_initial_mesh_visibility[instance])


func _mesh_name_matches_rule(node_name: String, rule: String) -> bool:
	return node_name.match(rule)


func _render_counters() -> Dictionary:
	return {
		"draw_calls_in_frame": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives_in_frame": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"video_memory_bytes": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
		"texture_memory_bytes": int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)),
		"buffer_memory_bytes": int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)),
		"scope": "whole rendered frame including model, captions, lighting, and optional ground plane",
	}


func _triangle_count() -> int:
	var total := 0
	for instance in _mesh_instances():
		if instance.mesh == null:
			continue
		for surface_index in range(instance.mesh.get_surface_count()):
			var arrays := instance.mesh.surface_get_arrays(surface_index)
			var index_data: Variant = arrays[Mesh.ARRAY_INDEX]
			if index_data is PackedInt32Array and not index_data.is_empty():
				total += int(index_data.size() / 3)
			else:
				var vertex_data: Variant = arrays[Mesh.ARRAY_VERTEX]
				if vertex_data is PackedVector3Array:
					total += int(vertex_data.size() / 3)
	return total


func _material_count() -> int:
	var materials: Dictionary = {}
	for instance in _mesh_instances():
		if instance.material_override != null:
			materials[instance.material_override.get_instance_id()] = true
		elif instance.mesh != null:
			for surface_index in range(instance.mesh.get_surface_count()):
				var material := instance.mesh.surface_get_material(surface_index)
				if material != null:
					materials[material.get_instance_id()] = true
	return materials.size()


func _vector_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _sha256_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(file.get_buffer(file.get_length()))
	return context.finish().hex_encode()


func _source_manifest() -> Dictionary:
	var paths := {
		"geometry_json": "res://../assets/aircraft/ugly-stik-60/geometry.json",
		"generated_geometry_gd": "res://aircraft/ugly_stik_geometry.gd",
		"model_builder_gd": "res://aircraft/ugly_stik_model.gd",
		"visual_finish_gd": "res://aircraft/ugly_stik_finish.gd",
		"generated_appearance_gd": "res://aircraft/ugly_stik_appearance.gd",
		"visual_equipment_gd": "res://aircraft/ugly_stik_equipment.gd",
		"visual_controls_gd": "res://aircraft/ugly_stik_controls.gd",
		"livery_svg": "res://aircraft/livery.svg",
		"appearance_json": "res://../assets/aircraft/ugly-stik-60/appearance.json",
		"render_adapter_gd": "res://render/airplane.gd",
		"capture_harness_gd": "res://aircraft/inspect_model.gd",
		"capture_orchestration_sh": "res://../research/ugly-stik/model-v3/capture.sh",
		"review_kit_py": "res://../research/ugly-stik/model-v3/make_review_kit.py",
	}
	var hashes: Dictionary = {}
	for key in paths:
		var path := ProjectSettings.globalize_path(String(paths[key]))
		var digest := _sha256_file(path)
		hashes[key] = {"path_from_app": String(paths[key]), "present": not digest.is_empty(), "sha256": digest}
	var source_id := ""
	var source_path: String = ProjectSettings.globalize_path(String(paths.geometry_json))
	if FileAccess.file_exists(source_path):
		var source_file := FileAccess.open(source_path, FileAccess.READ)
		if source_file != null:
			var parsed: Variant = JSON.parse_string(source_file.get_as_text())
			if parsed is Dictionary:
				source_id = String(parsed.get("id", ""))
	var compiled_id := String(_geometry_data.get("id", "unknown"))
	return {
		"geometry_id": compiled_id,
		"visual_revision": String(_airplane.root.get_meta("visual_revision", "unknown")),
		"appearance_atlas_runtime_path": String(_airplane.root.get_meta("appearance_atlas_runtime_path", "unknown")),
		"appearance_source_paths": {
			"appearance_json": "res://../assets/aircraft/ugly-stik-60/appearance.json",
			"generated_appearance_gd": "res://aircraft/ugly_stik_appearance.gd",
			"livery_svg": "res://aircraft/livery.svg",
		},
		"geometry_revision_note": "Geometry.id remains the v3 source identity; v4 changes are visual and do not rename geometry.",
		"source_sha256": String(hashes.geometry_json.sha256),
		"geometry_json_present": not String(hashes.geometry_json.sha256).is_empty(),
		"geometry_json_id": source_id,
		"geometry_json_id_matches_compiled": source_id.is_empty() or source_id == compiled_id,
		"compiled_geometry_sha256": String(hashes.generated_geometry_gd.sha256),
		"files": hashes,
	}


func _capture_design() -> Dictionary:
	var design := {
		"suite": _suite,
		"resolution_px": [_image_size.x, _image_size.y],
		"keep_aspect": "KEEP_HEIGHT",
		"lighting": _lighting_information(),
		"warmup_frames_before_samples": PERF_WARMUP_FRAMES,
		"frame_elapsed_samples_per_capture": PERF_SAMPLE_FRAMES,
		"frame_elapsed_scope": "Host-side wall interval through frame_post_draw; reported as a diagnostic, not a GPU benchmark.",
	}
	if _suite == "inspection":
		design["compatibility_note"] = "Nine original fixed views and filenames retained; framing updates are listed explicitly."
		design["camera_framing_revision"] = {
			"comparison_baseline": "model-v2 camera sizes",
			"changes": {"top": {"old_size_m": 1.58, "new_size_m": 1.90}, "bottom": {"old_size_m": 1.58, "new_size_m": 1.90}, "side": {"old_size_m": 0.92, "new_size_m": 1.05}},
			"reason": "Keep the measured aft tail/elevator extent inside the frame.",
			"target_and_camera_positions_changed": false,
			"pixel_identical_to_model_v2": false,
		}
		design["view_names"] = ["top", "bottom", "side", "front", "three-quarter-neutral", "three-quarter-deflected", "flight-20m", "flight-50m", "flight-100m"]
	elif _suite == "readability36":
		design["distances_m"] = FLIGHT_DISTANCES_M
		design["backgrounds"] = ["sky", "ground"]
		design["attitude_cases"] = ATTITUDE_CASES
		design["blind_id_assignment"] = "Fixed opaque code per attitude, permuted independently of answer labels; stable across runs."
		design["hinges"] = "Neutral for every image; roll/pitch/yaw commands are 0.0."
		design["model_height_m"] = MODEL_HEIGHT_M
		design["pilot_eye_height_m"] = PILOT_EYE_HEIGHT_M
		design["ground_height_m"] = GROUND_Y_M
		design["direction_prompt"] = "Nose toward/away is a static heading cue, not measured motion."
	elif _suite == "details":
		design["view_names"] = ["engine-left", "engine-right", "engine-front", "wing-root", "gear-main", "gear-nose", "tail-controls", "elevator-linkage", "aileron-linkage", "maintenance", "maintenance-servos", "maintenance-wing"]
		design["macro_crop_policy"] = "All detail views declare expected_crop=true; model bounds and visible-mesh crop result remain in each capture record."
		design["maintenance_visibility_rules"] = ["fuselage", "wing_left_*", "wing_right_*", "fixed_te_*", "aileron_left", "aileron_right"]
		design["maintenance_transform_policy"] = "Only MeshInstance3D.visible changes; component transforms and their actual model positions are left untouched and mesh visibility is restored before each capture."
		design["neutral_key_light"] = true
	elif _suite == "motion":
		design["control_pose_count"] = 12
		design["maintenance_control_pose_count"] = 12
		design["camera_displacement_sample_count"] = 12
		design["fixed_timestep_s"] = MOTION_SAMPLE_DT_S
		design["motion_policy"] = "Each pose is applied directly from a fixed command sample; there is no real-time animation or simulation clock."
		design["camera_sweep_total_translation_m"] = 0.06
		design["expected_crop_policy"] = "Control poses show the complete airplane; close material sweep frames explicitly declare expected_crop=true."
		design["neutral_key_light"] = true
	elif _suite == "showcase":
		design["purpose"] = "High-resolution model tour, engine macros and installed control details."
		design["macro_crop_policy"] = "Closeups crop surrounding aircraft; full-aircraft views require every visible vertex in frame."
		design["maintenance_transform_policy"] = "Only skin visibility changes; equipment stays in its installed position."
		design["view_names"] = []
		for capture in _showcase_capture_definitions():
			design["view_names"].append(capture.case_id)
	elif _suite == "beauty":
		design["view_names"] = ["beauty-a-dark", "beauty-b-sky"]
		design["backgrounds"] = {"beauty-a-dark": "#111820", "beauty-b-sky": "#9bcef0"}
		design["neutral_key_light"] = true
	return design


func _write_manifest() -> void:
	var manifest := {
		"schema": "openrc-model-capture-v4",
		"visual_revision": String(_airplane.root.get_meta("visual_revision", "unknown")),
		"appearance_atlas_runtime_path": String(_airplane.root.get_meta("appearance_atlas_runtime_path", "unknown")),
		"appearance_source_paths": {
			"appearance_json": String(_airplane.root.get_meta("appearance_data_path", "")),
			"generated_appearance_gd": String(_airplane.root.get_meta("appearance_generated_script", "")),
			"livery_svg": String(_airplane.root.get_meta("livery_source_path", "")),
		},
		"created_utc_unix": int(Time.get_unix_time_from_system()),
		"model": "Jensen Ugly Stik 60 / nitro .61",
		"capture_suite": _suite,
		"geometry": _source_manifest(),
		"builder": "res://render/airplane.gd",
		"builder_contract": ["root", "propeller", "hinges"],
		"axes": {"forward": "-Z", "right": "+X", "up": "+Y"},
		"capture_design": _capture_design(),
		"resolution_px": [_image_size.x, _image_size.y],
		"renderer": _render_information(),
		"captures": _records,
		"capture_count": _records.size(),
		"total_elapsed_ms": float(Time.get_ticks_usec() - _run_started_usec) / 1000.0,
	}
	var output_path := _out_dir.path_join("manifest.json")
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not open output manifest in %s" % _out_dir)
		quit(1)
		return
	file.store_string(JSON.stringify(manifest, "\t") + "\n")
	print("Wrote %s" % output_path)
