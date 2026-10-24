extends SceneTree

const PlayerInstrument := preload("res://render/overlays/player_instrument.gd")

var _checks := 0
var _failures := 0
var _stage: Control


func _initialize() -> void:
	TranslationServer.set_locale("en")
	await _run()
	print("widget redraw checks=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _run() -> void:
	await process_frame
	root.size = Vector2i(1920, 1080)
	_stage = Control.new()
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_stage)
	await process_frame
	await process_frame

	var engine: PlayerInstrument = _widget("engine", Vector2(20, 20))
	var engine_draws := [0]
	engine.graphic.draw.connect(func() -> void: engine_draws[0] += 1)
	engine.refresh(_telemetry(1.0, 10.0, 0.2), "metric", 0.0, {}, {}, {}, 1000.0)
	await _settle()
	var baseline: int = engine_draws[0]
	var engine_footer := _telemetry(1.1, 10.0, 0.2)
	engine_footer.load_factor = 1.4
	engine.refresh(engine_footer, "metric", 0.0, {}, {}, {}, 1300.0)
	await _settle()
	_check("engine RPM and load update the footer without redrawing its unchanged throttle bar", engine_draws[0] == baseline)
	engine.refresh(_telemetry(1.2, 10.0, 0.27), "metric", 0.0, {}, {}, {}, 1300.0)
	await _settle()
	_check("engine throttle change redraws its bar once", engine_draws[0] == baseline + 1, str(engine_draws))

	var power: PlayerInstrument = _widget("power", Vector2(330, 20))
	var power_draws := [0]
	power.graphic.draw.connect(func() -> void: power_draws[0] += 1)
	var battery := {"valid": true, "remaining_pct": 70.0, "pack_voltage_v": 12.0, "current_a": 2.0, "alarms": []}
	power.refresh(_telemetry(1.0, 10.0), "metric", 0.0, battery, {})
	await _settle()
	baseline = power_draws[0]
	var changed_footer := battery.duplicate(true)
	changed_footer.pack_voltage_v = 12.5
	changed_footer.current_a = 4.0
	power.refresh(_telemetry(1.1, 10.0), "metric", 0.0, changed_footer, {})
	await _settle()
	_check("battery voltage and current update without redrawing the unchanged level bar", power_draws[0] == baseline)
	changed_footer.remaining_pct = 72.0
	power.refresh(_telemetry(1.2, 10.0), "metric", 0.0, changed_footer, {})
	await _settle()
	_check("battery fraction change redraws the level bar once", power_draws[0] == baseline + 1, str(power_draws))

	var fuel: PlayerInstrument = _widget("fuel", Vector2(640, 20))
	var fuel_draws := [0]
	fuel.graphic.draw.connect(func() -> void: fuel_draws[0] += 1)
	var fuel_sample := {"ok": true, "finite_fuel": true, "fill_fraction": 0.4, "volume_ml": 300.0,
		"fuel_remaining_kg": 0.3, "low_fuel": false}
	fuel.refresh(_telemetry(1.0, 10.0), "metric", 0.0, {}, fuel_sample)
	await _settle()
	baseline = fuel_draws[0]
	var fuel_footer := fuel_sample.duplicate(true)
	fuel_footer.volume_ml = 290.0
	fuel_footer.fuel_remaining_kg = 0.29
	fuel.refresh(_telemetry(1.1, 10.0), "metric", 0.0, {}, fuel_footer)
	await _settle()
	_check("fuel volume and mass update without redrawing an unchanged fill bar", fuel_draws[0] == baseline)

	var weather: PlayerInstrument = _widget("weather", Vector2(950, 20))
	var weather_draws := [0]
	weather.graphic.draw.connect(func() -> void: weather_draws[0] += 1)
	var wind := _telemetry(1.0, 10.0)
	wind.wind_speed = 4.0
	wind.wind_from_deg = 90.0
	wind.wind_up = 0.0
	weather.refresh(wind, "metric", 0.0, {}, {})
	await _settle()
	baseline = weather_draws[0]
	var wind_footer := wind.duplicate(true)
	wind_footer.wind_speed = 8.0
	wind_footer.wind_up = 1.0
	weather.refresh(wind_footer, "metric", 0.0, {}, {})
	await _settle()
	_check("wind speed and vertical wind update without redrawing the fixed direction graphic", weather_draws[0] == baseline)
	wind_footer.wind_from_deg = 135.0
	weather.refresh(wind_footer, "metric", 0.0, {}, {})
	await _settle()
	_check("wind bearing change redraws the direction graphic once", weather_draws[0] == baseline + 1, str(weather_draws))

	var height: PlayerInstrument = _widget("height", Vector2(20, 250))
	var height_draws := [0]
	height.graphic.draw.connect(func() -> void: height_draws[0] += 1)
	var level_sample := _telemetry(1.1, 10.0)
	level_sample.vertical_speed = 0.0
	height.refresh(level_sample, "metric", 0.0, {}, {})
	await _settle()
	baseline = height_draws[0]
	var height_key: Array = height._view_key.duplicate(true)
	var paused_height := _telemetry(1.8, 10.0)
	paused_height.vertical_speed = 0.0
	height.refresh(paused_height, "metric", 0.0, {}, {})
	await _settle()
	_check("height key and graphic stay stable for a subsecond clock change", height._view_key == height_key and height_draws[0] == baseline)
	height.refresh(_telemetry(2.0, 10.0, -0.4), "metric", 0.0, {}, {})
	await _settle()
	_check("height redraws when its climb/sink symbol changes", height_draws[0] == baseline + 1, str(height_draws))

	var speed: PlayerInstrument = _widget("speed", Vector2(330, 250))
	var speed_draws := [0]
	speed.graphic.draw.connect(func() -> void: speed_draws[0] += 1)
	var speed_sample := _telemetry(5.0, 12.0)
	speed.refresh(speed_sample, "metric", 12.0, {}, {})
	await _settle()
	baseline = speed_draws[0]
	var sample_count: int = speed._samples.size()
	speed.refresh(speed_sample.duplicate(true), "metric", 12.0, {}, {})
	await _settle()
	_check("paused speed snapshot neither appends a sample nor redraws", speed._samples.size() == sample_count and speed_draws[0] == baseline)

	var trims: PlayerInstrument = _widget("trims", Vector2(640, 250))
	var trim_draws := [[0], [0], [0]]
	for axis in 3:
		trims._trim_tracks[axis].draw.connect(_increment_trim_draw.bind(trim_draws, axis))
	var trim_values := {"roll": 0.1, "pitch": -0.1, "yaw": 0.0}
	trims.refresh(_telemetry(1.0, 10.0), "metric", 0.0, {}, {}, trim_values)
	await _settle()
	var trim_baseline := [trim_draws[0][0], trim_draws[1][0], trim_draws[2][0]]
	trim_values.roll = 0.2
	trims.refresh(_telemetry(1.1, 10.0), "metric", 0.0, {}, {}, trim_values)
	await _settle()
	_check("one changed trim redraws only its own track", trim_draws[0][0] == trim_baseline[0] + 1
		and trim_draws[1][0] == trim_baseline[1] and trim_draws[2][0] == trim_baseline[2], str(trim_draws))
	trim_baseline = [trim_draws[0][0], trim_draws[1][0], trim_draws[2][0]]
	trims.refresh(_telemetry(1.1, 10.0), "metric", 0.0, {}, {}, trim_values.duplicate(true))
	await _settle()
	_check("unchanged paused trim snapshot does not redraw tracks", trim_draws[0][0] == trim_baseline[0]
		and trim_draws[1][0] == trim_baseline[1] and trim_draws[2][0] == trim_baseline[2])

	var hidden_draws: int = engine_draws[0]
	engine.set_appearance("normal", 0.94, true)
	engine.refresh(_telemetry(1.3, 10.0, 0.31), "metric", 0.0, {}, {}, {}, 1300.0)
	await _settle()
	_check("compact mode keeps the instrument graph hidden without drawing", not engine.graphic.visible and engine_draws[0] == hidden_draws)
	engine.set_appearance("normal", 0.94, false)
	await _settle()
	_check("restoring full density redraws the graph with the latest hidden-state value", engine.graphic.visible and engine_draws[0] > hidden_draws)

	var moved := []
	var restored := []
	speed.moved.connect(func(_id: String, _point: Vector2) -> void: moved.append(true))
	speed.reset_position_requested.connect(func(id: String) -> void: restored.append(id))
	_check("widget tooltips identify drag, reset and close actions", speed.handle.tooltip_text.contains("double-click")
		and speed.close_button.tooltip_text.contains(speed.title_label.text))
	var header_point: Vector2 = speed.handle.get_global_rect().get_center()
	var position_before_drag: Vector2 = speed.position
	_push_header(speed, header_point, true)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = header_point + Vector2(18, 0)
	motion.global_position = header_point + Vector2(18, 0)
	motion.relative = Vector2(18, 0)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(motion)
	await process_frame
	var drag_started := speed.dragging and speed.is_processing_input() and not speed.position.is_equal_approx(position_before_drag)
	var moved_point: Vector2 = speed.handle.get_global_rect().get_center()
	_push_header(speed, moved_point, true, true)
	await process_frame
	_push_header(speed, moved_point, false)
	await process_frame
	_check("unlocked header double-click requests one position restore and cancels drag without a move save",
		drag_started and restored == ["speed"] and moved.is_empty() and not speed.dragging and not speed.is_processing_input(), "%s %s" % [restored, moved])
	speed.set_locked(true)
	_push_header(speed, speed.handle.get_global_rect().get_center(), true, true)
	await process_frame
	_check("locked header double-click cannot request a position restore", restored == ["speed"] and not speed.dragging)

	for node in [engine, power, fuel, weather, height, speed, trims]:
		node.queue_free()
	await process_frame


func _widget(instrument_id: String, at: Vector2) -> PlayerInstrument:
	var widget: PlayerInstrument = PlayerInstrument.new(instrument_id)
	widget.position = at
	_stage.add_child(widget)
	return widget


func _increment_trim_draw(counts: Array, axis: int) -> void:
	counts[axis][0] += 1


func _telemetry(time_s: float, airspeed: float, throttle := NAN) -> Dictionary:
	return {"time_s": time_s, "airspeed": airspeed, "ground_speed": airspeed - 1.0,
		"height_agl": 40.0, "distance_pilot": 100.0, "vertical_speed": -0.5,
		"throttle": throttle, "load_factor": 1.0}


func _push_header(widget: Control, point: Vector2, pressed: bool, double_click := false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.double_click = double_click
	event.position = point
	event.global_position = point
	Input.parse_input_event(event)


func _settle() -> void:
	await process_frame
	await process_frame


func _check(label: String, passed: bool, detail := "") -> void:
	_checks += 1
	if passed:
		return
	_failures += 1
	push_error("widget redraws: %s %s" % [label, detail])
