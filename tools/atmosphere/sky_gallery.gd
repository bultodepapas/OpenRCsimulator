## FW-79: production-rendered sky gallery. Run without --headless so Compatibility uses the native renderer.
## The fixed SubViewport is independent of window occlusion and writes only to caller-selected paths.
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
const PREVIEW_SIZE := Vector2i(384, 216)
const DAY_IDS := ["classic", "clear", "cirrus", "fair_cumulus", "broken", "overcast", "prestorm", "distant_storm", "electrical_storm"]
const DAY_DATE := "2026-06-21"
const DAY_LOCAL_SECONDS := 13 * 3600
const FIELD_LATITUDE_DEG := 4.7
const FIELD_LONGITUDE_DEG := -74.1
const FIELD_UTC_OFFSET_MINUTES := -300
const MAIN_VIEW := {"id": "cloudscape", "azimuth_deg": 315.0, "elevation_deg": 25.0}
const HORIZON_VIEW := {"id": "horizon", "azimuth_deg": 0.0, "elevation_deg": 8.0}
const LIGHTNING_SCRIPT := "res://render/weather/lightning.gd"
const STORM_EVENTS_SCRIPT := "res://environment/storm_events.gd"

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
		print("FW-79 gallery script parsed")
		quit()
		return
	var output_dir := str(_args.get("out", ""))
	if output_dir.is_empty():
		_fail("--out=<absolute directory> is required")
		quit(1)
		return
	var mode := str(_args.get("mode", "all"))
	if not mode in ["day", "night", "all"]:
		_fail("--mode must be day, night, or all")
		quit(1)
		return
	if not _prepare_directory(output_dir):
		quit(1)
		return
	if _args.get("write-previews", "off") == "on":
		if not _prepare_directory(_preview_directory()):
			quit(1)
			return
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	if not loaded.get("ok", false):
		_fail("default field did not validate: " + "; ".join(loaded.get("errors", [])))
		quit(1)
		return
	_field = loaded.field
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.render_loop_enabled = false
	root.size = VIEW_SIZE
	_viewport = SubViewport.new()
	_viewport.name = "SkyGalleryViewport"
	_viewport.size = VIEW_SIZE
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	root.add_child(_viewport)

	if mode in ["day", "all"]:
		await _capture_day_profiles()
	if mode in ["night", "all"] and _failures == 0:
		await _capture_storm_nights()
	if _failures == 0:
		_write_manifest(output_dir)
		print("FW-79 gallery wrote %d images to %s" % [_images.size(), output_dir])
	quit(1 if _failures > 0 else 0)


func _capture_day_profiles() -> void:
	var raw_lighting := LightingConfig.defaults()
	raw_lighting.mode = "astronomical"
	raw_lighting.date = DAY_DATE
	raw_lighting.local_seconds = DAY_LOCAL_SECONDS
	raw_lighting.utc_offset_minutes = FIELD_UTC_OFFSET_MINUTES
	raw_lighting.latitude_deg = FIELD_LATITUDE_DEG
	raw_lighting.longitude_deg = FIELD_LONGITUDE_DEG
	raw_lighting.location_name = "Bogota field (synthetic)"
	var checked_lighting: Dictionary = LightingConfig.validate(raw_lighting)
	if not checked_lighting.get("ok", false):
		_fail("day lighting config did not validate: " + "; ".join(checked_lighting.errors))
		return
	var snapshot: Dictionary = SnapshotLighting.snapshot(checked_lighting.config)
	var selected_ids: Array = DAY_IDS
	if _args.has("only"):
		var only_id := str(_args.only)
		if not only_id in DAY_IDS:
			_fail("--only must name one catalog preset")
			return
		selected_ids = [only_id]
	for preset_value: Variant in selected_ids:
		var preset_id := str(preset_value)
		var selection: Dictionary = SkyConfig.for_preset(preset_id)
		if selection.is_empty():
			_fail("unknown sky preset in catalog: " + preset_id)
			return
		await _capture_selection("day-" + preset_id, selection, snapshot, {}, "day", "", -1.0, preset_id)
		if _failures > 0:
			return
		if _args.get("horizon", "off") == "on":
			await _capture_view("day-" + preset_id + "-horizon", HORIZON_VIEW, selection, snapshot, {}, "day", "", -1.0, preset_id, false)
			if _failures > 0:
				return


func _capture_storm_nights() -> void:
	var lightning_script: GDScript = load(LIGHTNING_SCRIPT) as GDScript
	var events_script: GDScript = load(STORM_EVENTS_SCRIPT) as GDScript
	if lightning_script == null or events_script == null:
		_fail("storm renderer or event schedule failed to load")
		return
	var selection: Dictionary = SkyConfig.for_preset("electrical_storm")
	selection.seed = 1253
	selection.flashes = "full"
	selection.thunder_volume = 0.0
	var events = events_script.new()
	events.configure(selection)
	var scheduled: Array[Dictionary] = events.events_for_window(0, events.tick_for_time(12.0 * 60.0))
	var selected_event: Dictionary = {}
	for event: Dictionary in scheduled:
		if str(event.get("kind", "")) == "cloud_to_ground":
			selected_event = event
			break
	if selected_event.is_empty() and not scheduled.is_empty():
		selected_event = scheduled[0]
	if selected_event.is_empty():
		_fail("deterministic electrical-storm schedule produced no event in 60 minutes")
		return
	var pulse: Dictionary = selected_event.pulse_envelope[0]
	for candidate: Dictionary in selected_event.pulse_envelope:
		if float(candidate.get("intensity", 0.0)) > float(pulse.get("intensity", 0.0)):
			pulse = candidate
	var tick_s := 1.0 / float(events.tick_rate_hz())
	var event_peak_time := float(selected_event.start_time_s) + float(pulse.offset_s) + 0.30 * float(pulse.duration_s) + tick_s * 0.5
	var quiet_time := float(selected_event.start_time_s) + float(selected_event.duration_s) + 0.5
	var event_id := str(selected_event.event_id)

	for night_case: Dictionary in [
		{"id": "full-moon", "date": "2026-06-29", "time": "00:00"},
		{"id": "new-moon", "date": "2026-06-15", "time": "00:00"},
	]:
		var conditions := _night_conditions(str(night_case.date), str(night_case.time))
		if conditions.is_empty():
			return
		await _capture_selection("electrical-" + str(night_case.id) + "-event-peak", selection, {}, conditions,
			"night", event_id, event_peak_time, "electrical_storm", lightning_script)
		if _failures > 0:
			return
		await _capture_selection("electrical-" + str(night_case.id) + "-quiet", selection, {}, conditions,
			"night", "", quiet_time, "electrical_storm", lightning_script)
		if _failures > 0:
			return
		if _args.get("horizon", "off") == "on":
			await _capture_view("electrical-" + str(night_case.id) + "-event-peak-horizon", HORIZON_VIEW,
				selection, {}, conditions, "night", event_id, event_peak_time, "electrical_storm", false, lightning_script)
			await _capture_view("electrical-" + str(night_case.id) + "-quiet-horizon", HORIZON_VIEW,
				selection, {}, conditions, "night", "", quiet_time, "electrical_storm", false, lightning_script)
			if _failures > 0:
				return


func _night_conditions(date_text: String, time_text: String) -> Dictionary:
	var raw: PackedStringArray = PackedStringArray([
		"--date=" + date_text,
		"--time=" + time_text,
		"--lat=" + str(FIELD_LATITUDE_DEG),
		"--lon=" + str(FIELD_LONGITUDE_DEG),
		"--utc_offset=" + str(float(FIELD_UTC_OFFSET_MINUTES) / 60.0),
	])
	var conditions: Dictionary = Conditions.resolve(raw)
	if not conditions.get("time_of_day", false) or not conditions.has("when"):
		_fail("night conditions failed to resolve for %s %s" % [date_text, time_text])
		return {}
	return conditions


func _capture_selection(case_id: String, selection: Dictionary, lighting: Dictionary, conditions: Dictionary,
		phase: String, event_id: String, clock_s: float, preset_id: String, storm_script: GDScript = null) -> void:
	await _capture_view(case_id, MAIN_VIEW, selection, lighting, conditions, phase, event_id, clock_s, preset_id,
		phase == "day", storm_script)


func _capture_view(case_id: String, view: Dictionary, selection: Dictionary, lighting: Dictionary, conditions: Dictionary,
		phase: String, event_id: String, clock_s: float, preset_id: String, make_preview: bool,
		storm_script: GDScript = null) -> void:
	if not Atmosphere.configure_appearance(selection, [0.0, 0.0, 0.0], 0.0):
		_fail("sky profile refused configuration: " + preset_id)
		return
	var scene_root := Node3D.new()
	scene_root.name = "GalleryScene_" + case_id
	_viewport.add_child(scene_root)
	var night_options := {"field_lighting": "off", "campfire": false}
	print("building world for %s" % case_id)
	var built: Dictionary = WorldBuilder.build(scene_root, _field, Callable(), conditions, lighting, night_options)
	print("world built for %s" % case_id)
	var env: Environment = built.get("environment") as Environment
	if env == null:
		_fail("World.build returned no Environment for " + case_id)
		scene_root.queue_free()
		return
	var camera := Camera3D.new()
	camera.name = "GalleryCamera"
	camera.current = true
	camera.fov = 70.0
	camera.far = 45000.0
	var pilot: Dictionary = _field.get("pilot", {})
	var eye := Frames.ned_to_render([
		float(pilot.get("north", 0.0)),
		float(pilot.get("east", 0.0)),
		-float(pilot.get("eye_height", 1.7)),
	])
	camera.position = eye
	scene_root.add_child(camera)
	var az := deg_to_rad(float(view.azimuth_deg))
	var el := deg_to_rad(float(view.elevation_deg))
	var direction := Frames.ned_to_render([cos(az) * cos(el), sin(az) * cos(el), -sin(el)]).normalized()
	camera.look_at(eye + direction * 1000.0)

	var lightning: Variant = null
	if storm_script != null:
		lightning = storm_script.new()
		lightning.name = "GalleryStorm"
		scene_root.add_child(lightning)
		lightning.configure(selection)
		lightning.set_audio_enabled(false)
		lightning.set_cloud_state(Atmosphere.cloud_state_snapshot())
	WorldBuilder.update(env, clock_s if clock_s >= 0.0 else 0.0, Vector3.ZERO)
	if lightning != null:
		lightning.update_at(maxf(clock_s, 0.0), camera.global_position, false, env.tonemap_exposure)
	if not await _draw_frames(case_id):
		scene_root.queue_free()
		return
	var image: Image = _viewport.get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != VIEW_SIZE:
		_fail("capture did not return a 1280x720 image: " + case_id)
		scene_root.queue_free()
		return
	var output_dir := str(_args.out)
	var file_name := case_id + "-" + str(view.id) + ".png"
	var path := output_dir.path_join(file_name)
	if not _save_image(image, path):
		scene_root.queue_free()
		return
	if make_preview and _args.get("write-previews", "off") == "on":
		if not _save_preview(image, preset_id):
			scene_root.queue_free()
			return
	_images.append(_case_manifest(case_id, file_name, preset_id, phase, view, lighting, conditions, event_id, clock_s, built))
	print("captured %s (%s, %s)" % [file_name, preset_id, phase])
	scene_root.queue_free()
	await process_frame


func _draw_frames(case_id: String) -> bool:
	var frame_count := clampi(int(_args.get("frames", "8")), 2, 60)
	print("drawing %d native frames for %s" % [frame_count, case_id])
	for frame_index: int in frame_count:
		await process_frame
		if frame_index == 0:
			print("first force_draw starting for %s" % case_id)
		RenderingServer.force_draw(false)
		if frame_index == 0:
			print("first force_draw finished for %s" % case_id)
	# `force_draw` is the synchronization point here. Waiting for the regular
	# frame_post_draw signal can stall in a manually-driven offscreen SceneTree.
	print("manual draws finished for %s" % case_id)
	if _viewport.get_texture() == null:
		_fail("SubViewport produced no texture for " + case_id)
		return false
	return true


func _save_image(image: Image, path: String) -> bool:
	if FileAccess.file_exists(path) and _args.get("overwrite", "off") != "on":
		_fail("refusing to overwrite capture: " + path)
		return false
	var error: Error = image.save_png(path)
	if error != OK:
		_fail("could not save %s (error %d)" % [path, error])
		return false
	return true


func _save_preview(source: Image, preset_id: String) -> bool:
	var directory := _preview_directory()
	var path := directory.path_join(preset_id + ".png")
	if FileAccess.file_exists(path) and _args.get("overwrite-previews", "off") != "on":
		_fail("refusing to overwrite preview asset: " + path)
		return false
	var preview := source.duplicate()
	preview.resize(PREVIEW_SIZE.x, PREVIEW_SIZE.y, Image.INTERPOLATE_LANCZOS)
	var error: Error = preview.save_png(path)
	if error != OK:
		_fail("could not save preview %s (error %d)" % [path, error])
		return false
	return true


func _preview_directory() -> String:
	return ProjectSettings.globalize_path("res://assets/sky/weather/previews")


func _prepare_directory(path: String) -> bool:
	var error := DirAccess.make_dir_recursive_absolute(path)
	if error != OK and error != ERR_ALREADY_EXISTS:
		_fail("could not create directory %s (error %d)" % [path, error])
		return false
	return true


func _case_manifest(case_id: String, file_name: String, preset_id: String, phase: String, view: Dictionary,
		lighting: Dictionary, conditions: Dictionary, event_id: String, clock_s: float, built: Dictionary) -> Dictionary:
	var sky: Dictionary = built.get("sky", {})
	var light_meta := {}
	if not lighting.is_empty():
		light_meta = {
			"mode": "astronomical snapshot",
			"date": DAY_DATE,
			"local_seconds": DAY_LOCAL_SECONDS,
			"utc_offset_minutes": FIELD_UTC_OFFSET_MINUTES,
			"latitude_deg": FIELD_LATITUDE_DEG,
			"longitude_deg": FIELD_LONGITUDE_DEG,
			"sun_elevation_deg": float(lighting.get("sun_elevation_deg", NAN)),
		}
	elif conditions.get("time_of_day", false):
		var when: Dictionary = conditions.get("when", {})
		light_meta = {
			"mode": "ephemeris moon-and-sun",
			"date": "%04d-%02d-%02d" % [int(when.get("year", 0)), int(when.get("month", 0)), int(when.get("day", 0))],
			"local_hour": float(when.get("hour", 0.0)),
			"utc_offset_hours": float(when.get("utc_offset_h", 0.0)),
			"latitude_deg": float(when.get("latitude_deg", 0.0)),
			"longitude_deg": float(when.get("longitude_deg", 0.0)),
			"sun_elevation_deg": float(sky.get("sun_elevation_deg", NAN)),
			"moon_elevation_deg": float(sky.get("moon_elevation_deg", NAN)),
			"moon_illuminated_fraction": float(sky.get("moon_illuminated", NAN)),
			"light_source": str(sky.get("light_source", "unknown")),
		}
	return {
		"id": case_id,
		"file": file_name,
		"preset": preset_id,
		"phase": phase,
		"event_id": event_id,
		"clock_s": clock_s,
		"camera": {"azimuth_deg": float(view.azimuth_deg), "elevation_deg": float(view.elevation_deg), "fov_deg": 70.0},
		"lighting": light_meta,
		"resolution": [VIEW_SIZE.x, VIEW_SIZE.y],
		"msaa": "4x",
	}


func _write_manifest(output_dir: String) -> void:
	var manifest_path := output_dir.path_join("manifest.json")
	if FileAccess.file_exists(manifest_path) and _args.get("overwrite", "off") != "on":
		_fail("refusing to overwrite gallery manifest: " + manifest_path)
		return
	var manifest := {
		"format": "openrc-sky-gallery v1",
		"engine": Engine.get_version_info(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"viewport": [VIEW_SIZE.x, VIEW_SIZE.y],
		"msaa": "4x",
		"world_builder": "app/render/world/world.gd",
		"sky_configuration": "Atmosphere.configure_appearance",
		"frames_after_each_scene_change": clampi(int(_args.get("frames", "8")), 4, 60),
		"native_renderer": true,
		"performance_claim": false,
		"images": _images,
	}
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		_fail("could not open gallery manifest for writing")
		return
	file.store_string(JSON.stringify(manifest, "\t"))


func _fail(message: String) -> void:
	_failures += 1
	push_error("FW-79 gallery: " + message)
	printerr("FW-79 gallery: " + message)
