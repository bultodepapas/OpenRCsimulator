# M5-W03b: rendered Home, flight-condition modal, and windy-flight HUD evidence.
# Run from the repository root with the pinned Godot under Xvfb; see the evidence README.
extends SceneTree

const Preferences := preload("res://app_state/preferences.gd")
const WindConfig := preload("res://physics/wind_config.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const PREFS_PATH := "user://m5_w03b_capture_settings.cfg"
const CAPTURE_TIME_S: float = 4.0
const SOURCE_FILES := [
	"res://app_root.gd", "res://app_state/preferences.gd", "res://ui/home.gd", "res://ui/weather_dialog.gd",
	"res://main.gd", "res://render/hud.gd", "res://physics/wind_config.gd", "res://physics/wind_field.gd",
	"res://sim/flight_session.gd", "res://i18n/es.po",
]


func _initialize() -> void:
	_run()


func _run() -> void:
	var options: Dictionary = _arguments()
	var screen: String = str(options.get("screen", "home"))
	var language: String = str(options.get("lang", "en"))
	var preset: String = str(options.get("preset", "calm"))
	var width: int = int(options.get("width", "1280"))
	var height: int = int(options.get("height", "720"))
	var out_path: String = str(options.get("out", ""))
	if screen not in ["home", "modal", "flight"] or language not in ["en", "es"]:
		_fail("Expected --screen=home|modal|flight and --lang=en|es")
		return
	if preset not in ["calm", "steady", "crosswind", "gusty", "updraft"]:
		_fail("Unknown weather preset '%s'" % preset)
		return
	if width < 640 or height < 480 or out_path.is_empty():
		_fail("Expected --out=<absolute PNG path> and a viewport at least 640x480")
		return
	DirAccess.remove_absolute(out_path)
	DirAccess.remove_absolute(out_path.get_basename() + ".json")
	var source_hashes: Dictionary = _source_hashes()

	var requested_size: Vector2i = Vector2i(width, height)
	root.size = requested_size
	DisplayServer.window_set_size(requested_size)
	await process_frame
	TranslationServer.set_locale(language)

	var weather: Dictionary = WindConfig.preset(preset)
	var preferences: Dictionary = Preferences.DEFAULTS.duplicate(true)
	preferences.language = language
	preferences.first_flight_hint_seen = true
	preferences.weather_config = weather.duplicate(true)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS_PATH))
	var save_error: Error = Preferences.save_to(PREFS_PATH, preferences)
	if save_error != OK:
		_fail("Could not write isolated capture preferences: error %d" % save_error)
		return

	var app: Node = load("res://app_root.tscn").instantiate()
	app.set("user_args", PackedStringArray())
	app.set("preferences_path", PREFS_PATH)
	root.add_child(app)
	await process_frame
	await process_frame
	var home: Control = app.get("home") as Control
	if home == null:
		_fail("Interactive app did not present Home")
		await _cleanup(app)
		return

	var target: Node
	var dialog: CanvasLayer = null
	var flight: Node = null
	var flight_evidence: Dictionary = {}
	var selected_preset: String = ""
	if screen == "home":
		target = home
	elif screen == "modal":
		app.call("open_weather", home.get("weather_button"))
		await process_frame
		await process_frame
		dialog = app.get("weather_dialog") as CanvasLayer
		if dialog == null:
			_fail("Home did not open the weather dialog")
			await _cleanup(app)
			return
		if preset != "calm":
			var preset_index: int = _preset_index(preset)
			dialog.call("_on_preset_selected", preset_index)
		selected_preset = preset
		target = dialog.get_node("Modal")
	else:
		app.call("start_flight")
		flight = app.get("flight") as Node
		if flight == null or flight.get_script() == null:
			_fail("Home did not create the flight scene")
			await _cleanup(app)
			return
		var session: Node = flight.get("session") as Node
		var sim: Node = session.get("sim") as Node
		flight.set("_show_perf", false)
		session.set("input_enabled", false)
		flight.set_process(false)
		sim.set_process_mode(Node.PROCESS_MODE_DISABLED)
		var ticks: int = roundi(CAPTURE_TIME_S / float(sim.call("dt")))
		for tick_index: int in range(ticks):
			sim.call("step")
		flight.call("_process", 0.0)
		flight.call("_update_hud")
		var hud: Label = flight.get("_hud") as Label
		var ground_speed_token: String = "ground speed" if language == "en" else "vel. suelo"
		var wind_token: String = "wind" if language == "en" else "viento"
		if hud == null or not hud.text.contains("airspeed") or not hud.text.contains(ground_speed_token) or not hud.text.contains(wind_token):
			_fail("Windy flight HUD is missing airspeed, ground speed, or wind: %s" % ("no HUD" if hud == null else hud.text))
			await _cleanup(app)
			return
		if bool(session.call("weather_is_calm")):
			_fail("Flight capture unexpectedly has calm weather")
			await _cleanup(app)
			return
		var state: PackedFloat64Array = sim.get("state")
		var air: Dictionary = session.call("air_data", state)
		var ground_speed: float = _ground_speed_ned(state)
		var wind_at_time: PackedFloat64Array = session.call("wind_at", float(sim.call("time")))
		flight_evidence = {
			"simulation_time_s": float(sim.call("time")),
			"ticks": int(sim.get("tick")),
			"tas_mps": float(air.get("V", NAN)),
			"ground_speed_mps": ground_speed,
			"wind_ned_mps": Array(wind_at_time),
			"hud_text": hud.text,
			"weather_config": session.call("weather_configuration"),
		}
		target = flight

	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var viewport: Viewport = root.get_viewport()
	var actual_size: Vector2i = viewport.get_visible_rect().size
	if actual_size != requested_size:
		_fail("Requested viewport %s but rendered viewport is %s" % [requested_size, actual_size])
		await _cleanup(app)
		return

	var layout: Dictionary = _layout_report(target, Rect2(Vector2.ZERO, Vector2(actual_size)))
	var image: Image = viewport.get_texture().get_image()
	var image_check: Dictionary = _check_image(image)
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var image_error: Error = image.save_png(out_path)
	if image_error != OK:
		_fail("Could not save screenshot %s: error %d" % [out_path, image_error])
		await _cleanup(app)
		return

	var manifest: Dictionary = {
		"format": "openrc-wind-ui-capture v1",
		"producer": "research/wind/M5-W03b/capture.gd",
		"image": out_path.get_file(),
		"sha256": FileAccess.get_sha256(out_path),
		"size": [image.get_width(), image.get_height()],
		"screen": screen,
		"language": language,
		"weather_preset": preset,
		"selected_dialog_preset": selected_preset,
		"weather_config": weather,
		"source_sha256": source_hashes,
		"layout": layout,
		"image_check": image_check,
		"flight": flight_evidence,
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
	}
	var manifest_path: String = out_path.get_basename() + ".json"
	var manifest_file: FileAccess = FileAccess.open(manifest_path, FileAccess.WRITE)
	if manifest_file == null:
		_fail("Cannot write capture manifest %s" % manifest_path)
		await _cleanup(app)
		return
	manifest_file.store_string(JSON.stringify(manifest, "  ", true) + "\n")
	manifest_file.flush()
	var manifest_error: Error = manifest_file.get_error()
	manifest_file.close()
	print("saved %s (%dx%d) screen=%s language=%s controls=%d zero=%d offscreen=%d overlaps=%d nonuniform_samples=%d" % [
		out_path, image.get_width(), image.get_height(), screen, language,
		int(layout.control_count), int(layout.zero_size_count), int(layout.offscreen_count),
		int(layout.container_overlap_count), int(image_check.nonuniform_samples),
	])
	await _cleanup(app)
	quit(1 if manifest_error != OK or not bool(layout.ok) or not bool(image_check.not_blank) else 0)


func _arguments() -> Dictionary:
	var out: Dictionary = {}
	for argument: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		if parts.size() == 2:
			out[parts[0]] = parts[1]
	return out


func _preset_index(preset: String) -> int:
	var index_by_id: Dictionary = {"calm": 1, "steady": 2, "crosswind": 3, "gusty": 4, "updraft": 5}
	return int(index_by_id[preset])


func _layout_report(target: Node, viewport_rect: Rect2) -> Dictionary:
	var controls: Array[Dictionary] = []
	var findings: Array[Dictionary] = []
	_collect_controls(target, viewport_rect, controls, findings)
	var container_overlaps: Array[Dictionary] = []
	_collect_container_overlaps(target, container_overlaps)
	for overlap: Dictionary in container_overlaps:
		findings.append({"kind": "overlap", "parent": overlap.parent, "first": overlap.first, "second": overlap.second})
	return {
		"target": str(target.name),
		"control_count": controls.size(),
		"zero_size_count": findings.filter(func(finding: Dictionary) -> bool: return finding.kind == "zero_size").size(),
		"offscreen_count": findings.filter(func(finding: Dictionary) -> bool: return finding.kind == "offscreen").size(),
		"container_overlap_count": container_overlaps.size(),
		"controls": controls,
		"findings": findings,
		"ok": findings.is_empty(),
	}


func _collect_controls(node: Node, viewport_rect: Rect2, controls: Array[Dictionary], findings: Array[Dictionary]) -> void:
	if node is Control:
		var control: Control = node as Control
		if control.is_visible_in_tree():
			var rect: Rect2 = control.get_global_rect()
			controls.append({
				"name": str(control.name),
				"class": control.get_class(),
				"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
			})
			if rect.size.x <= 0.0 or rect.size.y <= 0.0:
				findings.append({"kind": "zero_size", "control": str(control.get_path()), "rect": rect})
			elif not viewport_rect.encloses(rect):
				findings.append({"kind": "offscreen", "control": str(control.get_path()), "rect": rect, "viewport": viewport_rect})
	for child: Node in node.get_children():
		_collect_controls(child, viewport_rect, controls, findings)


func _collect_container_overlaps(node: Node, overlaps: Array[Dictionary]) -> void:
	if node is Container:
		var container: Container = node as Container
		var visible_controls: Array[Control] = []
		for child: Node in container.get_children():
			if child is Control and (child as Control).is_visible_in_tree():
				visible_controls.append(child as Control)
		for first_index: int in range(visible_controls.size()):
			for second_index: int in range(first_index + 1, visible_controls.size()):
				var first: Control = visible_controls[first_index]
				var second: Control = visible_controls[second_index]
				if first.get_global_rect().intersects(second.get_global_rect()):
					overlaps.append({"parent": str(container.get_path()), "first": str(first.get_path()), "second": str(second.get_path())})
	for child: Node in node.get_children():
		_collect_container_overlaps(child, overlaps)


func _check_image(image: Image) -> Dictionary:
	var palette: Dictionary = {}
	var different_from_corner: int = 0
	var corner: Color = image.get_pixel(0, 0)
	var samples: int = 0
	for y: int in range(0, image.get_height(), 2):
		for x: int in range(0, image.get_width(), 2):
			var color: Color = image.get_pixel(x, y)
			palette[color.to_rgba32()] = true
			samples += 1
			if color.to_rgba32() != corner.to_rgba32():
				different_from_corner += 1
	return {
		"sample_stride_px": 2,
		"samples": samples,
		"unique_colors": palette.size(),
		"nonuniform_samples": different_from_corner,
		"not_blank": palette.size() >= 32 and different_from_corner >= 1000,
	}


func _ground_speed_ned(state: PackedFloat64Array) -> float:
	var attitude: PackedFloat64Array = M.quat(state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3])
	var velocity_ned: PackedFloat64Array = M.q_rotate(attitude, M.v3(state[RB.VEL], state[RB.VEL + 1], state[RB.VEL + 2]))
	return M.sqrt_(velocity_ned[0] * velocity_ned[0] + velocity_ned[1] * velocity_ned[1])


func _source_hashes() -> Dictionary:
	var hashes: Dictionary = {}
	for path: String in SOURCE_FILES:
		hashes[path.trim_prefix("res://")] = FileAccess.get_sha256(ProjectSettings.globalize_path(path))
	return hashes


func _cleanup(app: Node) -> void:
	var flight: Node = app.get("flight") as Node
	if flight != null:
		var engine_audio: AudioStreamPlayer3D = flight.get("_engine_audio") as AudioStreamPlayer3D
		if engine_audio != null:
			engine_audio.stop()
	if app.get_parent() == root:
		root.remove_child(app)
	app.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS_PATH))
	for frame_index: int in range(3):
		await process_frame


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
