extends SceneTree

const Manager := preload("res://render/overlays/overlay_manager.gd")
const Settings := preload("res://render/overlays/overlay_settings.gd")
const Instrument := preload("res://render/overlays/navigation_instrument.gd")
var checks := 0
var failures := 0
var foreground_draws := 0
var face_draws := 0
var chart_draws := 0


func _initialize() -> void:
	TranslationServer.set_locale("en")
	await process_frame
	root.size = Vector2i(1920, 1080)
	var manager := Manager.new({preset = "navigation", units = "metric"}, "en")
	root.add_child(manager)
	await process_frame
	await process_frame
	var radar: Control = manager.frames.pilot_radar
	var wind: Control = manager.frames.wind_track
	var cruise: Control = manager.frames.cruise_efficiency
	manager.refresh_numbers(_snapshot(0.0))
	_check("navigation is opt-in; legacy default preserved", Settings.DEFAULTS.preset == "pilot" and Settings.NAVIGATION_IDS.all(func(id: String) -> bool: return manager.frames[id].visible))
	_check("radar uses horizontal pilot offset, not slant range", radar.value_label.text == "100" and radar.unit_label.text == "m")
	_check("radar separates AGL from horizontal range", radar.right_value.text == "500 m")
	_check("radar keeps aircraft inside scale", radar._range_m > 100.0)
	_check("drift displays wrapped signed angle", wind.value_label.text == "+20")
	_check("wind distinguishes tailwind and wind to right", wind.left_caption.text == "TAILWIND" and wind.right_caption.text == "WIND TO RIGHT")
	_check("electric estimate warms up rather than inventing zero", cruise.value_label.text == "—" and cruise.subtitle.text == "Collecting cruise data")
	for i in range(1, 31): manager.refresh_numbers(_snapshot(i * 0.1))
	_check("electric efficiency from shared voltage/current sensors", cruise.value_label.text == "10.0" and cruise.unit_label.text == "Wh/km")
	manager.set_units("imperial")
	manager.refresh_numbers(_snapshot(3.0))
	_check("imperial energy per mile has correct conversion", cruise.value_label.text == "16.1" and cruise.unit_label.text == "Wh/mi")
	_check("radar imperial distances convert", radar.value_label.text == "328" and radar.unit_label.text == "ft")
	manager.set_units("metric")
	for i in range(7, 180): manager.refresh_numbers(_snapshot(i * 0.5, i * 2.0))
	_check("trail and efficiency graph memory are bounded", radar._trail.size() <= 60 and cruise._trend.size() <= 60)
	_check("efficiency history fills bounded graph", cruise._trend.size() == 60)
	for value: float in [0.0, 80.0, 100.0, 199.0, 500.0, 1e6]:
		_check("radar scale contains offset " + str(value), Instrument.radar_range(value) >= value / 0.8)
	await process_frame
	await process_frame
	radar.graphic.draw.connect(func() -> void: foreground_draws += 1)
	radar._face.draw.connect(func() -> void: face_draws += 1)
	foreground_draws = 0
	face_draws = 0
	for i in 100: manager.refresh_numbers(_snapshot(89.5, 358.0))
	await process_frame
	await process_frame
	_check("paused repeated snapshots do not redraw radar", foreground_draws == 0 and face_draws == 0)
	manager.refresh_numbers(_snapshot(90.0, 360.0))
	await process_frame
	await process_frame
	_check("moving aircraft redraws foreground only", foreground_draws > 0 and face_draws == 0)
	cruise.graphic.draw.connect(func() -> void: chart_draws += 1)
	var updated_footer := _snapshot(90.1, 360.0)
	updated_footer.battery.pack_current_a = 11.0
	manager.refresh_numbers(updated_footer)
	await process_frame
	await process_frame
	_check("power footer updates without rebuilding unchanged trend", cruise.left_value.text == "396 W" and chart_draws == 0)
	for size_name: String in Settings.WIDGET_SIZES:
		manager.set_widget_option("widget_size", size_name)
		for compact: bool in [false, true]:
			manager.set_widget_option("widget_compact", compact)
			await process_frame
			await process_frame
			_check("1080p navigation layout clear: " + size_name + str(compact), _separate(manager))
			_check("compact retains navigation diagrams", radar.graphic.visible and wind.graphic.visible)
	manager.set_widget_option("widget_size", "normal")
	manager.set_widget_option("widget_compact", false)
	for resolution: Vector2i in [Vector2i(2560, 1440), Vector2i(3840, 2160), Vector2i(1280, 720)]:
		root.size = resolution
		await process_frame
		await process_frame
		_check("navigation stays inside viewport: " + str(resolution), Settings.NAVIGATION_IDS.all(func(id: String) -> bool: return Rect2(Vector2.ZERO, Vector2(resolution)).encloses(manager.frames[id].get_global_rect())))
	root.size = Vector2i(1920, 1080)
	await process_frame
	for id: String in Settings.NAVIGATION_IDS:
		var widget: Control = manager.frames[id]
		_check(id + " close does not capture flight focus", widget.close_button.focus_mode == Control.FOCUS_NONE)
		widget.close_button.pressed.emit()
		_check(id + " closes and updates settings", not widget.visible and id not in manager.settings.visible)
		manager.set_overlay_visible(id, true)
		_check(id + " can be restored", widget.visible)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(20, 10)
	radar._handle_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(100, -150)
	radar._handle_input(motion)
	press.pressed = false
	radar._handle_input(press)
	_check("drag stores normalized radar position", manager.settings.get("positions", {}).has("pilot_radar") and radar.normalized_position().y < 1)
	manager.set_layout_locked(true)
	press.pressed = true
	radar._handle_input(press)
	_check("position lock prevents radar drag", not radar.dragging)
	manager.refresh_numbers({telemetry = {time_s = 91.0}})
	_check("missing position shows unavailable", radar.subtitle.text == "Position unavailable" and radar._trail.is_empty())
	_check("missing electric sensor removes stale efficiency", cruise.value_label.text == "—" and cruise.subtitle.text == "Electric power telemetry unavailable" and cruise._trend.is_empty())
	_check("missing track clears drift", wind.value_label.text == "–")
	_check("missing track does not pretend the aircraft is taxiing", wind.subtitle.text == "Ground track unavailable")
	var invalid_speed := _snapshot(91.1)
	invalid_speed.telemetry.erase("ground_speed")
	manager.refresh_numbers(invalid_speed)
	_check("missing ground speed is distinct from warm-up", cruise.subtitle.text == "Ground speed unavailable")
	var invalid_power := _snapshot(91.2)
	invalid_power.battery.erase("bus_voltage_v")
	manager.refresh_numbers(invalid_power)
	_check("invalid sensor channel is distinct from warm-up", cruise.subtitle.text == "Electric power telemetry unavailable")
	manager.set_overlay_visible("cruise_efficiency", false)
	manager.refresh_numbers(_snapshot(92.0))
	_check("closed efficiency stops and resets its sampling", manager.navigation_data._segments.is_empty())
	manager.set_overlay_visible("cruise_efficiency", true)
	manager.refresh_numbers(_snapshot(92.1))
	_check("reopening efficiency starts fresh sampling", cruise.value_label.text == "—")
	manager.reset_flight()
	_check("flight reset clears trail and graph", radar._trail.is_empty() and cruise._trend.is_empty())
	manager.queue_free()
	await process_frame
	print("navigation widgets checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _snapshot(time_s: float, north := 100.0) -> Dictionary:
	return {telemetry = {time_s = time_s, airspeed = 10.0, ground_speed = 10.0, pilot_north_m = north,
		pilot_east_m = 0.0, distance_pilot = 1000000.0, height_agl = 500.0, heading_deg = 350.0,
		ground_course_deg = 10.0, drift_deg = 20.0, headwind_mps = -3.0, crosswind_mps = 2.0},
		battery = {ok = true, battery_kind = "ocv_resistance", bus_voltage_v = 36.0, pack_current_a = 10.0}}


func _separate(manager: CanvasLayer) -> bool:
	var ids: Array = Settings.NAVIGATION_IDS
	var viewport := Rect2(Vector2.ZERO, Vector2(root.size))
	for i in ids.size():
		var rect: Rect2 = manager.frames[ids[i]].get_global_rect()
		if not viewport.encloses(rect): return false
		for j in range(i + 1, ids.size()):
			if rect.intersects(manager.frames[ids[j]].get_global_rect()): return false
	return true


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL navigation widgets: " + label)
