## FW-84b production-world electrical storm capture harness.
## Run with the pinned native Compatibility renderer, not --headless. The parse-only path is headless-safe.
extends SceneTree

const WorldBuilder := preload("res://render/world/world.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Frames := preload("res://render/frames.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const Conditions := preload("res://render/world/conditions.gd")
const StormEvents := preload("res://environment/storm_events.gd")
const Lightning := preload("res://render/weather/lightning.gd")
const StormBank := preload("res://render/weather/storm_bank.gd")
const CloudTransport := preload("res://render/weather/cloud_transport.gd")

const VIEW_SIZE := Vector2i(1280, 720)
const SKY_PRESET := "electrical_storm"
const EVENT_SEED := 1253
const TICK_RATE_HZ := 60
const FIELD_LATITUDE_DEG := 4.7
const FIELD_LONGITUDE_DEG := -74.1
const FIELD_UTC_OFFSET_MINUTES := -300
const DAY_DATE := "2026-06-21"
const DUSK_DATE := "2026-06-21"
const DUSK_LOCAL_TIME := "18:25"
# Qualified Bogotá night samples with the full moon high in the sky and a new-moon night.
const FULL_MOON_DATE := "2026-06-29"
const FULL_MOON_LOCAL_TIME := "00:00"
const NEW_MOON_DATE := "2026-06-15"
const NEW_MOON_LOCAL_TIME := "00:00"
const NIGHT_OPTIONS := {"field_lighting": "off", "campfire": false}
const FRAMES_AFTER_SCENE_CHANGE := 8
const CAMERA_FOV_DEG := 50.0
const PRE_OFFSET_S := -0.05
const PEAK_OFFSET_S := 0.0375
const POST_OFFSET_S := 1.0
const SEARCH_SLOTS := 64

var _args: Dictionary = {}
var _viewport: SubViewport
var _field: Dictionary
var _images: Array[Dictionary] = []
var _failures: int = 0


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		_args[pair[0]] = pair[1] if pair.size() > 1 else "on"
	_run.call_deferred()


func _run() -> void:
	if _args.get("parse-only", "off") == "on":
		print("FW-84b electrical bank capture harness parsed")
		quit()
		return
	var output_dir := str(_args.get("out", ""))
	if output_dir.is_empty() or not output_dir.is_absolute_path():
		_fail("--out=<absolute fresh directory> is required")
		quit(1)
		return
	if not _prepare_directory(output_dir):
		quit(1)
		return
	var selected_phase := str(_args.get("only", "all"))
	if not selected_phase in ["all", "day", "dusk", "fullmoon", "newmoon"]:
		_fail("--only must be all, day, dusk, fullmoon, or newmoon")
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
	_viewport.name = "ElectricalBankCaptureViewport"
	_viewport.size = VIEW_SIZE
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	root.add_child(_viewport)

	var event_id := ""
	for phase: Dictionary in _lighting_cases():
		if selected_phase != "all" and str(phase.id) != selected_phase:
			continue
		event_id = await _capture_phase(phase, output_dir, event_id)
		if _failures > 0:
			break
	if _failures == 0:
		_write_manifest(output_dir)
		print("FW-84b electrical bank capture wrote %d images to %s" % [_images.size(), output_dir])
	quit(1 if _failures > 0 else 0)


func _lighting_cases() -> Array[Dictionary]:
	var cases: Array[Dictionary] = []
	for row: Dictionary in [
		{"id": "day", "date": DAY_DATE, "time": "13:00"},
		{"id": "dusk", "date": DUSK_DATE, "time": DUSK_LOCAL_TIME},
		{"id": "fullmoon", "date": FULL_MOON_DATE, "time": FULL_MOON_LOCAL_TIME},
		{"id": "newmoon", "date": NEW_MOON_DATE, "time": NEW_MOON_LOCAL_TIME},
	]:
		var conditions := _conditions(str(row.date), str(row.time))
		if not conditions.is_empty():
			cases.append({
				"id": str(row.id),
				"lighting": {},
				"conditions": conditions,
				"date": str(row.date),
				"local_time": str(row.time),
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


func _capture_phase(phase: Dictionary, output_dir: String, shared_event_id: String) -> String:
	var selection: Dictionary = SkyConfig.for_preset(SKY_PRESET)
	if selection.is_empty():
		_fail("unknown sky preset: " + SKY_PRESET)
		return shared_event_id
	selection.seed = EVENT_SEED
	selection.motion = "still"
	if not Atmosphere.configure_appearance(selection, [0.0, 0.0, 0.0], 0.0):
		_fail("Atmosphere refused the electrical storm appearance")
		return shared_event_id
	var scene_root := Node3D.new()
	scene_root.name = "ElectricalStorm_" + str(phase.id)
	_viewport.add_child(scene_root)
	print("building production World for %s" % str(phase.id))
	var built: Dictionary = WorldBuilder.build(scene_root, _field, Callable(), phase.conditions,
		phase.lighting, NIGHT_OPTIONS)
	phase.world_sky = (built.get("sky", {}) as Dictionary).duplicate(true)
	var environment: Environment = built.get("environment") as Environment
	if environment == null:
		_fail("World.build returned no Environment for " + str(phase.id))
		scene_root.queue_free()
		return shared_event_id
	WorldBuilder.update(environment, 0.0, Vector3.ZERO)
	WorldBuilder.refresh_weather_appearance(environment, 0.0)
	var bank: StormBank = WorldBuilder.storm_bank_node(environment) as StormBank
	if bank == null or not is_instance_valid(bank):
		_fail("World did not return a live production storm bank for " + str(phase.id))
		scene_root.queue_free()
		return shared_event_id
	var bank_state: Dictionary = WorldBuilder.weather_snapshot(environment)
	var target_value: Variant = bank_state.get("target", [])
	if not bank_state.get("enabled", false) or not target_value is Array or target_value.size() != 3:
		_fail("World weather snapshot did not return an enabled bank target for " + str(phase.id))
		scene_root.queue_free()
		return shared_event_id
	var target_world := _as_vector3(target_value)
	var camera := Camera3D.new()
	camera.name = "ElectricalStormCaptureCamera"
	camera.current = true
	camera.far = 45000.0
	camera.fov = CAMERA_FOV_DEG
	scene_root.add_child(camera)
	var eye_down := float(_field.pilot.down) - float(_field.pilot.eye_height)
	camera.position = Frames.ned_to_render([float(_field.pilot.north), float(_field.pilot.east), eye_down])
	camera.look_at(target_world, Vector3.UP)
	var transport: Dictionary = Atmosphere.cloud_transport_checkpoint()
	if not CloudTransport.validate(transport) or str(transport.get("motion", "")) != "still":
		_fail("Atmosphere did not provide a valid Still cloud transport checkpoint")
		scene_root.queue_free()
		return shared_event_id
	var event: Dictionary = _first_cloud_to_ground(bank, transport, camera.global_position)
	if event.is_empty():
		_fail("seed %d has no scheduled cloud-to-ground event in the bounded search" % EVENT_SEED)
		scene_root.queue_free()
		return shared_event_id
	var event_id := str(event.get("event_id", ""))
	if shared_event_id.is_empty():
		shared_event_id = event_id
	elif event_id != shared_event_id:
		_fail("lighting case %s selected event %s; expected shared event %s" % [phase.id, event_id, shared_event_id])
		scene_root.queue_free()
		return shared_event_id
	var start_s := float(event.get("start_time_s", 0.0))
	var exposure := float(environment.tonemap_exposure)
	if not is_finite(exposure) or exposure <= 0.0:
		_fail("World returned invalid actual environment exposure for " + str(phase.id))
		scene_root.queue_free()
		return shared_event_id
	var world_sky: Dictionary = _world_sky(phase)
	print("event %s starts at %.3f s; exposure %.4f; sun %.2f° moon %.2f° (%.1f%%)" % [
		event_id, start_s, exposure,
		float(world_sky.get("sun_elevation_deg", NAN)),
		float(world_sky.get("moon_elevation_deg", NAN)),
		100.0 * float(world_sky.get("moon_illuminated", NAN)),
	])

	for sample: Dictionary in _event_samples(start_s):
		if not await _capture_sample(scene_root, environment, bank, camera, transport, event, phase,
				target_world, sample, "full", exposure, output_dir):
			scene_root.queue_free()
			return shared_event_id
	if str(phase.id) in ["fullmoon", "newmoon"]:
		# The Full peak is already one of the pre/peak/post samples above.
		for flash_mode: String in ["reduced", "off"]:
			if not await _capture_sample(scene_root, environment, bank, camera, transport, event, phase,
					target_world, {"id": "peak", "time_s": start_s + PEAK_OFFSET_S}, flash_mode, exposure, output_dir):
				scene_root.queue_free()
				return shared_event_id
	scene_root.queue_free()
	await process_frame
	return shared_event_id


func _first_cloud_to_ground(bank: StormBank, transport: Dictionary, reference: Vector3) -> Dictionary:
	var schedule := StormEvents.new()
	schedule.configure(_storm_config("full"))
	schedule.set_cell_context(bank.cell_spec(), transport, reference)
	var search_end_tick := int(round(float(SEARCH_SLOTS) * StormEvents.SLOT_SECONDS * float(TICK_RATE_HZ)))
	for event: Dictionary in schedule.events_started_in_window(0, search_end_tick):
		if str(event.get("kind", "")) == "cloud_to_ground":
			return event
	return {}


func _event_samples(start_s: float) -> Array[Dictionary]:
	return [
		{"id": "pre", "time_s": start_s + PRE_OFFSET_S},
		{"id": "peak", "time_s": start_s + PEAK_OFFSET_S},
		{"id": "post", "time_s": start_s + POST_OFFSET_S},
	]


func _capture_sample(scene_root: Node3D, environment: Environment, bank: StormBank, camera: Camera3D,
		transport: Dictionary, event: Dictionary, phase: Dictionary, target_world: Vector3,
		sample: Dictionary, flash_mode: String,
		exposure: float, output_dir: String) -> bool:
	var time_s := float(sample.time_s)
	WorldBuilder.refresh_weather_appearance(environment, time_s)
	var lightning := Lightning.new()
	lightning.name = "ElectricalStormCaptureLightning"
	lightning.set_audio_enabled(false)
	scene_root.add_child(lightning)
	var config := _storm_config(flash_mode)
	lightning.configure(config)
	lightning.bind_storm_bank(bank)
	lightning.set_cell_transport(transport)
	lightning.set_cloud_state(Atmosphere.cloud_state_snapshot())
	lightning.update_at(time_s, camera.global_position, false, exposure)
	var lightning_state: Dictionary = lightning.snapshot()
	var bank_snapshot: Dictionary = bank.snapshot()
	var flash_state: Variant = bank_snapshot.get("flash", {})
	if not flash_state is Dictionary:
		_fail("storm bank returned no flash snapshot for " + str(sample.id))
		lightning.queue_free()
		await process_frame
		return false
	var targeted_peak := str(sample.id) == "peak"
	var visible_mode := flash_mode != "off"
	if targeted_peak and visible_mode:
		if _lightning_event_id(lightning_state) != str(event.event_id) \
				or str(flash_state.get("event_id", "")) != str(event.event_id) \
				or float(flash_state.get("level", 0.0)) <= 0.0:
			_fail("Lightning and production bank did not show the target event in %s/%s" % [phase.id, flash_mode])
			lightning.queue_free()
			await process_frame
			return false
	if (not targeted_peak or not visible_mode) and float(flash_state.get("level", 0.0)) > 0.0:
		_fail("production bank retained a flash outside a visible peak sample (%s/%s/%s)" % [phase.id, sample.id, flash_mode])
		lightning.queue_free()
		await process_frame
		return false
	var case_id := "%s-%s-%s-%s" % [SKY_PRESET, str(phase.id), str(sample.id), flash_mode]
	if not await _draw_frames(case_id):
		lightning.queue_free()
		await process_frame
		return false
	var image: Image = _viewport.get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != VIEW_SIZE:
		_fail("capture did not return a 1280x720 image: " + case_id)
		lightning.queue_free()
		await process_frame
		return false
	var file_name := case_id + ".png"
	var path := output_dir.path_join(file_name)
	if not _save_image(image, path):
		lightning.queue_free()
		await process_frame
		return false
	var image_sha256 := FileAccess.get_sha256(path)
	if image_sha256.length() != 64:
		_fail("could not calculate SHA-256 for " + path)
		lightning.queue_free()
		await process_frame
		return false
	_images.append(_image_manifest(case_id, file_name, phase, sample, flash_mode, time_s, exposure,
			camera.global_position, camera.global_position.distance_to(_as_vector3(event.get("source_world", []))),
		target_world, bank.cell_spec(), event, lightning_state, flash_state, _world_sky(phase), image_sha256))
	print("captured %s" % file_name)
	lightning.reset()
	lightning.queue_free()
	await process_frame
	return true


func _storm_config(flash_mode: String) -> Dictionary:
	return {
		"preset": SKY_PRESET,
		"seed": EVENT_SEED,
		"tick_rate_hz": TICK_RATE_HZ,
		"flashes": flash_mode,
		"thunder_volume": 0.0,
	}


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


func _image_manifest(case_id: String, file_name: String, phase: Dictionary, sample: Dictionary,
		flash_mode: String, time_s: float, exposure: float, camera_world: Vector3, source_range_m: float,
		target_world: Vector3, cell_spec: Dictionary, event: Dictionary, lightning: Dictionary,
		bank_flash: Dictionary, world_sky: Dictionary, image_sha256: String) -> Dictionary:
	var source := _as_vector3(event.get("source_world", []))
	var ground := _as_vector3(event.get("ground_world", []))
	var channel := _as_vector3(event.get("channel_world", []))
	return {
		"id": case_id,
		"file": file_name,
		"sha256": image_sha256,
		"preset": SKY_PRESET,
		"phase": str(phase.id),
		"date": str(phase.date),
		"local_time": str(phase.local_time),
		"sample": str(sample.id),
		"simulation_time_s": time_s,
		"flashes": flash_mode,
		"cloud_transport_motion": "still",
		"environment_exposure": exposure,
		"world_sky": world_sky,
		"event": {
			"event_id": str(event.event_id),
			"kind": str(event.kind),
			"slot_index": int(event.slot_index),
			"start_time_s": float(event.start_time_s),
			"source_world": _vector_array(source),
			"ground_world": _vector_array(ground),
			"channel_world": _vector_array(channel),
		},
		"lightning": {
			"event_id": _lightning_event_id(lightning),
			"level": float(lightning.get("level", 0.0)),
			"mode": str(lightning.get("mode", "")),
			"bank_bound": bool(lightning.get("bank_bound", false)),
			"light_energy": float(lightning.get("light_energy", 0.0)),
			"pending_thunder": int(lightning.get("pending_thunder", 0)),
			"node_count": int(lightning.get("node_count", 0)),
		},
		"bank_flash": {
			"event_id": str(bank_flash.get("event_id", "")),
			"level": float(bank_flash.get("level", 0.0)),
			"source_world": bank_flash.get("source_world", []),
			"radiance": _json_vector_or_scalar(bank_flash.get("radiance", 0.0)),
		},
		"bank_cell": cell_spec.duplicate(true),
		"camera": {
			"position_world": _vector_array(camera_world),
			"target_world": _vector_array(target_world),
			"source_range_m": source_range_m,
			"fov_deg": CAMERA_FOV_DEG,
		},
		"resolution": [VIEW_SIZE.x, VIEW_SIZE.y],
		"msaa": "4x",
	}


func _world_sky(phase: Dictionary) -> Dictionary:
	var sky: Dictionary = phase.get("world_sky", {})
	if sky.is_empty():
		return {}
	return {
		"sun_elevation_deg": float(sky.get("sun_elevation_deg", NAN)),
		"moon_elevation_deg": float(sky.get("moon_elevation_deg", NAN)),
		"moon_illuminated": float(sky.get("moon_illuminated", NAN)),
		"light_source": str(sky.get("light_source", "")),
		"sky_exposure": float(sky.get("exposure", NAN)),
	}


func _write_manifest(output_dir: String) -> void:
	var manifest_path := output_dir.path_join("manifest.json")
	if FileAccess.file_exists(manifest_path):
		_fail("refusing to overwrite gallery manifest: " + manifest_path)
		return
	var manifest := {
		"format": "openrc-fw84b-electrical-bank-capture v1",
		"engine": Engine.get_version_info(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"field": FieldLoader.DEFAULT_PATH,
		"world_builder": "app/render/world/world.gd",
		"storm_bank": "app/render/weather/storm_bank.gd",
		"lightning": "app/render/weather/lightning.gd",
		"seed": EVENT_SEED,
		"cloud_transport_motion": "still",
		"event_kind": "cloud_to_ground",
		"viewport": [VIEW_SIZE.x, VIEW_SIZE.y],
		"msaa": "4x",
		"native_renderer": true,
		"frames_after_scene_change": FRAMES_AFTER_SCENE_CHANGE,
		"aircraft_in_frame": false,
		"aircraft_capture": "production Main capture is recorded separately",
		"images": _images,
	}
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		_fail("could not open manifest for writing")
		return
	file.store_string(JSON.stringify(manifest, "\t"))


func _prepare_directory(path: String) -> bool:
	if DirAccess.dir_exists_absolute(path):
		var entries := DirAccess.get_files_at(path)
		var subdirectories := DirAccess.get_directories_at(path)
		if not entries.is_empty() or not subdirectories.is_empty():
			_fail("refusing non-empty output directory; use a fresh directory: " + path)
			return false
	else:
		var error: Error = DirAccess.make_dir_recursive_absolute(path)
		if error != OK and error != ERR_ALREADY_EXISTS:
			_fail("could not create output directory %s (error %d)" % [path, error])
			return false
	return true


func _as_vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is PackedFloat64Array and value.size() >= 3:
		return Vector3(value[0], value[1], value[2])
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


func _vector_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _json_vector_or_scalar(value: Variant) -> Variant:
	if value is Vector3:
		return _vector_array(value)
	if value is Color:
		return [value.r, value.g, value.b]
	return value


func _lightning_event_id(snapshot: Dictionary) -> String:
	return str(snapshot.get("current_event_id", snapshot.get("event_id", "")))


func _save_image(image: Image, path: String) -> bool:
	if FileAccess.file_exists(path):
		_fail("refusing to overwrite capture: " + path)
		return false
	var error: Error = image.save_png(path)
	if error != OK:
		_fail("could not save %s (error %d)" % [path, error])
		return false
	return true


func _fail(message: String) -> void:
	_failures += 1
	push_error("FW-84b electrical bank capture: " + message)
	printerr("FW-84b electrical bank capture: " + message)
