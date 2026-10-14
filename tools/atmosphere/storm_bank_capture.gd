## FW-83 production-world storm-bank capture harness.
## Run with the pinned native Compatibility renderer, not --headless. It builds the real default field and World.
extends SceneTree

const WorldBuilder := preload("res://render/world/world.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Frames := preload("res://render/frames.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const LightingConfig := preload("res://environment/time_of_day_config.gd")
const SnapshotLighting := preload("res://render/time_of_day_lighting.gd")
const Conditions := preload("res://render/world/conditions.gd")

const VIEW_SIZE := Vector2i(1280, 720)
const NIGHT_OPTIONS := {"field_lighting": "off", "campfire": false}
const SKY_PRESET := "distant_storm"
const DAY_DATE := "2026-06-21"
const DAY_LOCAL_SECONDS := 13 * 3600
const DUSK_DATE := "2026-06-21"
const DUSK_LOCAL_TIME := "18:25"
const FULL_MOON_DATE := "2026-06-29"
const FULL_MOON_LOCAL_TIME := "00:00"
const FIELD_LATITUDE_DEG := 4.7
const FIELD_LONGITUDE_DEG := -74.1
const FIELD_UTC_OFFSET_MINUTES := -300
const PILOT_VIEW := {"id": "pilot", "north_m": 0.0, "east_m": 0.0}
const CROSS_TRACK_DISTANCE_M := 500.0
const CROSS_TRACK_BEARING_DEG := 45.0
const FOVS_DEG := [50.0, 25.0]
const FRAMES_AFTER_SCENE_CHANGE := 8

var _args: Dictionary = {}
var _viewport: SubViewport
var _field: Dictionary
var _images: Array[Dictionary] = []
var _failures := 0


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		_args[pair[0]] = pair[1] if pair.size() > 1 else "on"
	_run.call_deferred()


func _run() -> void:
	if _args.get("parse-only", "off") == "on":
		print("FW-83 storm-bank capture harness parsed")
		quit()
		return
	var output_dir := str(_args.get("out", ""))
	if output_dir.is_empty():
		_fail("--out=<absolute directory> is required")
		quit(1)
		return
	var only_phase := str(_args.get("only", "all"))
	if not only_phase in ["all", "day", "dusk", "fullmoon"]:
		_fail("--only must be all, day, dusk, or fullmoon")
		quit(1)
		return
	var only_view := str(_args.get("view", "all"))
	if not only_view in ["all", "pilot", "cross500"]:
		_fail("--view must be all, pilot, or cross500")
		quit(1)
		return
	if not _prepare_directory(output_dir):
		quit(1)
		return
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	if not loaded.get("ok", false):
		_fail("default production field did not validate: " + "; ".join(loaded.get("errors", [])))
		quit(1)
		return
	_field = loaded.field
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.render_loop_enabled = false
	root.size = VIEW_SIZE
	_viewport = SubViewport.new()
	_viewport.name = "StormBankCaptureViewport"
	_viewport.size = VIEW_SIZE
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	root.add_child(_viewport)

	for phase: Dictionary in _lighting_cases():
		if only_phase != "all" and str(phase.id) != only_phase:
			continue
		await _capture_phase(phase, output_dir)
		if _failures > 0:
			break
	if _failures == 0:
		_write_manifest(output_dir)
		print("FW-83 storm-bank gallery wrote %d images to %s" % [_images.size(), output_dir])
	quit(1 if _failures > 0 else 0)


func _lighting_cases() -> Array[Dictionary]:
	var cases: Array[Dictionary] = []
	var day_raw := LightingConfig.defaults()
	day_raw.mode = "astronomical"
	day_raw.date = DAY_DATE
	day_raw.local_seconds = DAY_LOCAL_SECONDS
	day_raw.utc_offset_minutes = FIELD_UTC_OFFSET_MINUTES
	day_raw.latitude_deg = FIELD_LATITUDE_DEG
	day_raw.longitude_deg = FIELD_LONGITUDE_DEG
	day_raw.location_name = "Bogota field (synthetic)"
	var day_checked: Dictionary = LightingConfig.validate(day_raw)
	if not day_checked.get("ok", false):
		_fail("day lighting config did not validate: " + "; ".join(day_checked.get("errors", [])))
		return cases
	cases.append({
		"id": "day",
		"lighting": SnapshotLighting.snapshot(day_checked.config),
		"conditions": {},
		"date": DAY_DATE,
		"local_time": "13:00",
	})
	var dusk_conditions := _conditions(DUSK_DATE, DUSK_LOCAL_TIME)
	if not dusk_conditions.is_empty():
		cases.append({
			"id": "dusk",
			"lighting": {},
			"conditions": dusk_conditions,
			"date": DUSK_DATE,
			"local_time": DUSK_LOCAL_TIME,
		})
	var moon_conditions := _conditions(FULL_MOON_DATE, FULL_MOON_LOCAL_TIME)
	if not moon_conditions.is_empty():
		cases.append({
			"id": "fullmoon",
			"lighting": {},
			"conditions": moon_conditions,
			"date": FULL_MOON_DATE,
			"local_time": FULL_MOON_LOCAL_TIME,
		})
	return cases


func _conditions(date_text: String, time_text: String) -> Dictionary:
	var raw := PackedStringArray([
		"--date=" + date_text,
		"--time=" + time_text,
		"--lat=" + str(FIELD_LATITUDE_DEG),
		"--lon=" + str(FIELD_LONGITUDE_DEG),
		"--utc_offset=" + str(float(FIELD_UTC_OFFSET_MINUTES) / 60.0),
	])
	var conditions: Dictionary = Conditions.resolve(raw)
	if not conditions.get("time_of_day", false) or not conditions.has("when"):
		_fail("time-of-day conditions failed to resolve for %s %s" % [date_text, time_text])
		return {}
	return conditions


func _capture_phase(phase: Dictionary, output_dir: String) -> void:
	var selection: Dictionary = SkyConfig.for_preset(SKY_PRESET)
	if selection.is_empty():
		_fail("unknown sky preset: " + SKY_PRESET)
		return
	selection.seed = int(_args.get("seed", "1253"))
	if not Atmosphere.configure_appearance(selection, [0.0, 0.0, 0.0], 0.0):
		_fail("Atmosphere refused the distant-storm appearance")
		return
	var scene_root := Node3D.new()
	scene_root.name = "StormBank_" + str(phase.id)
	_viewport.add_child(scene_root)
	print("building production World for %s" % str(phase.id))
	var built: Dictionary = WorldBuilder.build(scene_root, _field, Callable(), phase.conditions, phase.lighting, NIGHT_OPTIONS)
	var environment: Environment = built.get("environment") as Environment
	if environment == null:
		_fail("World.build returned no Environment for " + str(phase.id))
		scene_root.queue_free()
		return
	WorldBuilder.update(environment, 0.0, Vector3.ZERO)
	WorldBuilder.refresh_weather_appearance(environment, 0.0)
	var bank_ref: Variant = environment.get_meta("fw_storm_bank", null)
	var bank: Variant = bank_ref.get_ref() if bank_ref is WeakRef else null
	if not bank is Node3D or not is_instance_valid(bank):
		_fail("World did not retain a live storm-bank node in Environment meta for " + str(phase.id))
		scene_root.queue_free()
		return
	var bank_snapshot: Dictionary = WorldBuilder.weather_snapshot(environment)
	var target_data: Variant = bank_snapshot.get("target", [])
	if not bank_snapshot.get("enabled", false) or not target_data is Array or target_data.size() != 3:
		_fail("World.weather_snapshot returned no enabled formation target for " + str(phase.id))
		scene_root.queue_free()
		return
	var target_world := Vector3(float(target_data[0]), float(target_data[1]), float(target_data[2]))
	var camera := Camera3D.new()
	camera.name = "StormBankCaptureCamera"
	camera.current = true
	camera.far = 45000.0
	scene_root.add_child(camera)
	for view: Dictionary in _camera_positions():
		if str(_args.get("view", "all")) != "all" and str(view.id) != str(_args.view):
			continue
		var view_north := float(_field.pilot.north) + float(view.north_m)
		var view_east := float(_field.pilot.east) + float(view.east_m)
		var eye_down := float(_field.pilot.down) - float(_field.pilot.eye_height)
		camera.position = Frames.ned_to_render([view_north, view_east, eye_down])
		camera.look_at(target_world, Vector3.UP)
		for fov: float in FOVS_DEG:
			camera.fov = fov
			var case_id := "%s-%s-fov%d" % [SKY_PRESET, str(phase.id) + "-" + str(view.id), int(fov)]
			if not await _draw_frames(case_id):
				scene_root.queue_free()
				return
			var image: Image = _viewport.get_texture().get_image()
			if image == null or image.is_empty() or image.get_size() != VIEW_SIZE:
				_fail("capture did not return a 1280x720 image: " + case_id)
				scene_root.queue_free()
				return
			var file_name := case_id + ".png"
			var path := output_dir.path_join(file_name)
			if not _save_image(image, path):
				scene_root.queue_free()
				return
			_images.append(_image_manifest(case_id, file_name, phase, view, fov, camera.global_position, target_world, bank_snapshot))
			print("captured %s" % file_name)
	scene_root.queue_free()
	await process_frame


func _camera_positions() -> Array[Dictionary]:
	var cross_track := deg_to_rad(CROSS_TRACK_BEARING_DEG)
	var shift_north := cos(cross_track) * CROSS_TRACK_DISTANCE_M
	var shift_east := sin(cross_track) * CROSS_TRACK_DISTANCE_M
	return [
		{"id": "pilot", "north_m": float(PILOT_VIEW.north_m), "east_m": float(PILOT_VIEW.east_m)},
		{"id": "cross500", "north_m": shift_north, "east_m": shift_east, "cross_track_m": CROSS_TRACK_DISTANCE_M},
	]


func _draw_frames(case_id: String) -> bool:
	print("drawing %d native frames for %s" % [FRAMES_AFTER_SCENE_CHANGE, case_id])
	for frame_index: int in FRAMES_AFTER_SCENE_CHANGE:
		await process_frame
		if frame_index == 0:
			RenderingServer.force_draw(false)
	if _viewport.get_texture() == null:
		_fail("SubViewport produced no texture for " + case_id)
		return false
	return true


func _image_manifest(case_id: String, file_name: String, phase: Dictionary, view: Dictionary, fov: float,
		camera_world: Vector3, target_world: Vector3, bank: Dictionary) -> Dictionary:
	var camera_north := -camera_world.z
	var camera_east := camera_world.x
	var target_north := -target_world.z
	var target_east := target_world.x
	var delta_north := target_north - camera_north
	var delta_east := target_east - camera_east
	return {
		"id": case_id,
		"file": file_name,
		"preset": SKY_PRESET,
		"phase": str(phase.id),
		"date": str(phase.date),
		"local_time": str(phase.local_time),
		"camera": {
			"id": str(view.id),
			"position_world": [camera_world.x, camera_world.y, camera_world.z],
			"target_world": [target_world.x, target_world.y, target_world.z],
			"bearing_deg": fposmod(rad_to_deg(atan2(delta_east, delta_north)), 360.0),
			"range_m": Vector2(delta_north, delta_east).length(),
			"fov_deg": fov,
		},
		"bank": {
			"enabled": bool(bank.get("enabled", false)),
			"layout_version": int(bank.get("layout_version", 0)),
			"seed": int(bank.get("seed", 0)),
			"world_center": bank.get("center", []),
			"target_world": bank.get("target", []),
			"puff_count": int(bank.get("puff_count", 0)),
			"rain_count": int(bank.get("rain_count", 0)),
			"period_m": float(bank.get("period_m", 0.0)),
		},
		"resolution": [VIEW_SIZE.x, VIEW_SIZE.y],
		"msaa": "4x",
	}


func _save_image(image: Image, path: String) -> bool:
	if FileAccess.file_exists(path) and _args.get("overwrite", "off") != "on":
		_fail("refusing to overwrite capture: " + path)
		return false
	var error: Error = image.save_png(path)
	if error != OK:
		_fail("could not save %s (error %d)" % [path, error])
		return false
	return true


func _write_manifest(output_dir: String) -> void:
	var manifest_path := output_dir.path_join("manifest.json")
	if FileAccess.file_exists(manifest_path) and _args.get("overwrite", "off") != "on":
		_fail("refusing to overwrite gallery manifest: " + manifest_path)
		return
	var manifest := {
		"format": "openrc-fw83-storm-bank-capture v1",
		"engine": Engine.get_version_info(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"field": FieldLoader.DEFAULT_PATH,
		"world_builder": "app/render/world/world.gd",
		"viewport": [VIEW_SIZE.x, VIEW_SIZE.y],
		"msaa": "4x",
		"native_renderer": true,
		"frames_after_scene_change": FRAMES_AFTER_SCENE_CHANGE,
		"images": _images,
	}
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		_fail("could not open manifest for writing")
		return
	file.store_string(JSON.stringify(manifest, "\t"))


func _prepare_directory(path: String) -> bool:
	var error: Error = DirAccess.make_dir_recursive_absolute(path)
	if error != OK and error != ERR_ALREADY_EXISTS:
		_fail("could not create output directory %s (error %d)" % [path, error])
		return false
	return true


func _fail(message: String) -> void:
	_failures += 1
	push_error("FW-83 storm-bank capture: " + message)
	printerr("FW-83 storm-bank capture: " + message)
