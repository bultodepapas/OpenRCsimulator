extends SceneTree

const Manager := preload("res://render/overlays/overlay_manager.gd")
const Settings := preload("res://render/overlays/overlay_settings.gd")
const Dialog := preload("res://ui/overlays_dialog.gd")
var checks := 0
var failures := 0
var face_draws := 0
var foreground_draws := 0


func _initialize() -> void:
	TranslationServer.set_locale("en")
	await process_frame
	root.size = Vector2i(1920, 1080)
	var manager := Manager.new({preset = "training", units = "metric"}, "en")
	root.add_child(manager)
	await process_frame
	await process_frame
	var maneuver: Control = manager.frames.maneuver
	var glide: Control = manager.frames.glide
	var summary: Control = manager.frames.flight_summary
	manager.refresh_numbers(_snapshot(0.0))
	_check("training is opt-in and exactly three instruments", Settings.DEFAULTS.preset == "pilot" and manager.settings.visible.size() == 4 and Settings.TRAINING_IDS.filter(func(id: String) -> bool: return id != "session_stats").all(func(id: String) -> bool: return manager.frames[id].visible) and not manager.frames.session_stats.visible)
	_check("signed body load has explicit g units", maneuver.value_label.text == "+1.0" and maneuver.unit_label.text == "g")
	_check("maneuver shows bank and alpha", maneuver.subtitle.text.contains("Bank +10°") and maneuver.subtitle.text.contains("AoA +4.0°"))
	_check("glide distinguishes ground ratio and sink", glide.value_label.text == "-2.0" and glide.unit_label.text == "m/s" and glide.left_value.text == "10.0 : 1")
	_check("flight timer starts at zero", summary.value_label.text == "0:00")
	manager.set_overlay_visible("maneuver", false)
	manager.set_overlay_visible("flight_summary", false)
	for i in range(1, 101):
		var snap := _snapshot(i * 0.1)
		snap.telemetry.load_factor = -2.0 if i == 20 else 4.0
		snap.telemetry.airspeed = 40.0 if i == 60 else 30.0
		snap.telemetry.height_agl = 100.0 if i == 80 else 60.0
		manager.refresh_numbers(snap)
	manager.set_overlay_visible("maneuver", true)
	manager.set_overlay_visible("flight_summary", true)
	manager.refresh_numbers(_snapshot(10.0))
	_check("G extrema continue while widget closed", maneuver.left_value.text == "-2.0 g" and maneuver.right_value.text == "+4.0 g")
	_check("summary retains airspeed maximum while closed", summary.left_value.text == "144 km/h")
	_check("summary retains max AGL while closed", summary.right_value.text == "100 m")
	_check("ground distance is integrated even with summary closed", summary._distance_text == "200 m")
	_check("timer uses simulation time", summary.value_label.text == "0:10")
	manager.hide()
	manager.refresh_numbers(_snapshot(10.0))
	manager.show()
	manager.refresh_numbers(_snapshot(10.0))
	_check("pause/menu retains flight statistics", summary._distance_text == "200 m" and maneuver.right_value.text == "+4.0 g")
	manager.set_units("imperial")
	manager.refresh_numbers(_snapshot(10.0))
	_check("imperial vario uses feet per minute", glide.value_label.text == "-390" and glide.unit_label.text == "ft/min")
	_check("summary imperial distance and speed convert", summary._distance_text == "656 ft" and summary.left_value.text == "89 mph")
	_check("glide ratio is unit independent", glide.left_value.text == "10.0 : 1")
	manager.set_units("metric")
	for status: String in ["powered", "turning", "slow", "not_descending", "unavailable"]:
		var telemetry: Dictionary = _snapshot(10.1).telemetry
		match status:
			"powered": telemetry.throttle = 0.5
			"turning": telemetry.bank_deg = 50.0
			"slow": telemetry.ground_speed = 2.0
			"not_descending": telemetry.vertical_speed = 0.0
			_: telemetry.erase("ground_speed")
		glide.refresh_training(telemetry, "metric", NAN, {})
		_check("glide guard suppresses ratio: " + status, glide.left_value.text == "— : 1")
	manager.refresh_numbers(_snapshot(10.2))
	var gap := _snapshot(12.0)
	manager.refresh_numbers(gap)
	_check("lost intervals are marked rather than invented", summary._distance_text.ends_with(" *") and summary.subtitle.text == "* Distance excludes missing samples")
	var excess := _snapshot(12.1)
	excess.telemetry.load_factor = 12.0
	manager.refresh_numbers(excess)
	_check("over-range load retains numeric value and flags clipped scale", maneuver.value_label.text == "+12.0" and maneuver.subtitle.text.begins_with("Scale exceeded"))
	for i in range(25, 200): manager.refresh_numbers(_snapshot(i * 0.5))
	_check("glide history is bounded to sixty points", glide._sink_history.size() == 60)
	await process_frame
	RenderingServer.force_draw(false)
	maneuver._face.draw.connect(func() -> void: face_draws += 1)
	maneuver.graphic.draw.connect(func() -> void: foreground_draws += 1)
	for i in 100: manager.refresh_numbers(_snapshot(99.5))
	await process_frame
	RenderingServer.force_draw(false)
	_check("paused snapshots avoid foreground and face redraws", face_draws == 0 and foreground_draws == 0)
	var changed := _snapshot(99.6)
	changed.telemetry.load_factor = 2.0
	manager.refresh_numbers(changed)
	await process_frame
	RenderingServer.force_draw(false)
	_check("load change redraws needle without rebuilding face", foreground_draws > 0 and face_draws == 0)
	for size_name: String in Settings.WIDGET_SIZES:
		manager.set_widget_option("widget_size", size_name)
		for compact: bool in [false, true]:
			manager.set_widget_option("widget_compact", compact)
			await process_frame
			await process_frame
			_check("training fits at 1080p: " + size_name + str(compact), _separate(manager))
			_check("compact retains diagrams and summary", maneuver.graphic.visible and glide.graphic.visible and summary.graphic.visible)
	manager.set_widget_option("widget_size", "normal")
	manager.set_widget_option("widget_compact", false)
	for resolution: Vector2i in [Vector2i(2560, 1440), Vector2i(3840, 2160), Vector2i(1280, 720)]:
		root.size = resolution
		await process_frame
		await process_frame
		_check("training remains in viewport: " + str(resolution), Settings.TRAINING_IDS.all(func(id: String) -> bool: return Rect2(Vector2.ZERO, Vector2(resolution)).encloses(manager.frames[id].get_global_rect())))
	root.size = Vector2i(1920, 1080)
	await process_frame
	for id: String in Settings.TRAINING_IDS:
		var widget: Control = manager.frames[id]
		_check(id + " X cannot steal flight keyboard focus", widget.close_button.focus_mode == Control.FOCUS_NONE)
		widget.close_button.pressed.emit()
		_check(id + " closes individually and persists visibility", not widget.visible and id not in manager.settings.visible)
		manager.set_overlay_visible(id, true)
		_check(id + " can be restored", widget.visible)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(20, 10)
	maneuver._handle_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(70, -130)
	maneuver._handle_input(motion)
	press.pressed = false
	maneuver._handle_input(press)
	_check("drag saves normalized maneuver position", manager.settings.get("positions", {}).has("maneuver") and maneuver.normalized_position().y < 1)
	manager.set_layout_locked(true)
	press.pressed = true
	maneuver._handle_input(press)
	_check("lock prevents drag", not maneuver.dragging)
	manager.refresh_numbers({telemetry = {time_s = 100.0}})
	_check("missing load displays unavailable", maneuver.value_label.text == "—")
	_check("missing sink clears plot and ratio", glide._sink_history.is_empty() and glide.left_value.text == "— : 1")
	manager.reset_flight()
	manager.refresh_numbers(_snapshot(0.0))
	_check("explicit restart clears previous distance and extrema", summary._distance_text == "0.0 m" and maneuver.left_value.text == "+1.0 g" and maneuver.right_value.text == "+1.0 g")
	TranslationServer.set_locale("es")
	manager.refresh_numbers(_snapshot(0.0))
	_check("Spanish glide caption resolves", glide.left_caption.text != "GROUND GLIDE")
	var dialog := Dialog.new(manager)
	root.add_child(dialog)
	dialog.tab_bar.current_tab = 2
	await process_frame
	await process_frame
	_check("all seven Spanish navigation/training switches fit the 1080p page", (Settings.NAVIGATION_IDS + Settings.TRAINING_IDS).all(func(id: String) -> bool: return dialog._scroll.get_global_rect().encloses(dialog.switches[id].get_global_rect())))
	root.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	_check("720p keeps Done and preset outside scrolling page", Rect2(0, 0, 1280, 720).encloses(dialog.done_button.get_global_rect()) and not dialog._scroll.is_ancestor_of(dialog.preset_picker))
	dialog.queue_free()
	manager.queue_free()
	await process_frame
	print("training widgets checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _snapshot(time_s: float) -> Dictionary:
	return {telemetry = {time_s = time_s, airspeed = 30.0, ground_speed = 20.0, height_agl = 50.0,
		load_factor = 1.0, bank_deg = 10.0, alpha_deg = 4.0, vertical_speed = -2.0, throttle = 0.0}}


func _separate(manager: CanvasLayer) -> bool:
	for i in Settings.TRAINING_IDS.size():
		var rect: Rect2 = manager.frames[Settings.TRAINING_IDS[i]].get_global_rect()
		if not Rect2(Vector2.ZERO, Vector2(root.size)).encloses(rect): return false
		for j in range(i + 1, Settings.TRAINING_IDS.size()):
			if rect.intersects(manager.frames[Settings.TRAINING_IDS[j]].get_global_rect()): return false
	return true


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL training widgets: " + label)
