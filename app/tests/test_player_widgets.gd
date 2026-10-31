extends SceneTree

const Settings := preload("res://render/overlays/overlay_settings.gd")
const Manager := preload("res://render/overlays/overlay_manager.gd")
const Dialog := preload("res://ui/overlays_dialog.gd")
const Instrument := preload("res://render/overlays/player_instrument.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const DEFAULT_PLAYER_POSITIONS := {
	"speed": Vector2(0, 1), "height": Vector2(1, 1), "power": Vector2(0, 0), "weather": Vector2(1, 0),
	"fuel": Vector2(0, 0.5), "trims": Vector2(0.5, 0.82), "engine": Vector2(1, 0.53),
}
const MODERN_IDS := ["speed", "height", "power", "weather", "fuel", "trims", "engine"]
const CORE_IDS := ["speed", "height", "power", "weather"]

var _checks := 0
var _failures := 0


func _initialize() -> void:
	TranslationServer.set_locale("en")
	await _run()
	print("player widgets checks=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _run() -> void:
	await process_frame
	root.size = Vector2i(1920, 1080)
	await process_frame
	var manager: CanvasLayer = Manager.new({"preset": "player", "units": "metric"}, "en")
	root.add_child(manager)
	await process_frame
	await process_frame
	_test_player_preset(manager)
	_test_glass_surface(manager)
	if DisplayServer.get_name() != "headless":
		await _test_rendered_glass()
	_test_speed_extrema(manager)
	_test_missing_numbers(manager)
	_test_energy(manager)
	await _test_zero_speed_graph(manager)
	await _test_extended_instruments(manager)
	await _test_widget_interaction(manager)
	await _test_responsive_layout(manager)
	await _test_dialog(manager)
	manager.queue_free()
	await process_frame


func _test_player_preset(manager: CanvasLayer) -> void:
	manager.refresh_numbers(_snapshot(1.0, 30.0))
	_check("Player preset shows its four instruments and warnings", manager.settings.preset == "player"
		and manager.settings.visible == Settings.PRESETS.player and manager.frames.warnings.visible
		and CORE_IDS.all(func(id: String) -> bool: return manager.frames[id].visible))
	_check("metric airspeed shows 30 m/s as 108 km/h", manager.frames.speed.value_label.text == "108"
		and manager.frames.speed.unit_label.text == "km/h", "%s %s" % [manager.frames.speed.value_label.text, manager.frames.speed.unit_label.text])


func _test_glass_surface(manager: CanvasLayer) -> void:
	for id: String in Settings.PLAYER_IDS:
		var widget: Control = manager.frames[id]
		var glass: ColorRect = widget._glass
		var material: ShaderMaterial = widget._glass_material
		_check(id + " uses a noninteractive shared crystal underlay", material.shader == Instrument.GLASS
			and glass.material == material and glass.get_parent().show_behind_parent
			and glass.mouse_filter == Control.MOUSE_FILTER_IGNORE and glass.focus_mode == Control.FOCUS_NONE
			and not widget._style.draw_center and not glass.get_parent().is_processing()
			and not glass.get_parent().is_physics_processing())
	_check("chrome uses the shared green while navigation keeps its amber data key",
		Instrument.CHROME_ACCENT == UiTheme.FOCUS and Instrument.ACCENT == Color("f1ca7d")
		and manager.frames.wind_track.graphic.tooltip_text.contains("amber: ground track"))
	_check("each widget owns its glass parameters", manager.frames.speed._glass_material != manager.frames.height._glass_material)
	for opacity: float in Settings.WIDGET_OPACITY_STEPS:
		manager.set_widget_option("widget_opacity", opacity)
		for id: String in Settings.PLAYER_IDS:
			var widget: Control = manager.frames[id]
			var background: Color = widget._glass_material.get_shader_parameter("base_color")
			_check(id + " glass follows opacity " + str(opacity), is_equal_approx(background.a, opacity)
				and background == widget._style.bg_color and widget.modulate.a == 1.0)
	manager.set_widget_option("widget_opacity", 0.94)


func _test_rendered_glass() -> void:
	# One real widget on controlled backgrounds; keep its surface geometry while
	# hiding glyphs so the shader's composited pixels can be sampled directly.
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	var backdrop := ColorRect.new()
	backdrop.color = Color.WHITE
	backdrop.size = Vector2(root.size)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(backdrop)
	var widget := Instrument.new("speed")
	widget.position = Vector2(300, 200)
	widget.size = Vector2(320, 240)
	layer.add_child(widget)
	widget.body.get_parent().hide()
	widget.set_appearance("normal", 0.8, false)
	await process_frame
	await RenderingServer.frame_post_draw
	var origin := Vector2i(widget.global_position)
	var point := origin + Vector2i(160, 140)
	var white_image := root.get_texture().get_image()
	var white_eighty := white_image.get_pixelv(point)
	var worst_contrast := INF
	for x in range(40, 281, 40):
		for y in range(60, 201, 20):
			worst_contrast = minf(worst_contrast, UiTheme.contrast(Instrument.MUTED, white_image.get_pixelv(origin + Vector2i(x, y))))
	backdrop.color = Color.BLACK
	await RenderingServer.frame_post_draw
	var black_eighty := root.get_texture().get_image().get_pixelv(point)
	widget.set_appearance("normal", 1.0, false)
	backdrop.color = Color.WHITE
	await RenderingServer.frame_post_draw
	var opaque_image := root.get_texture().get_image()
	var white_opaque := opaque_image.get_pixelv(point)
	# UV (0.25, 0.05) is on the shader's fixed diagonal reflection, away from
	# the header icon and top-edge strokes; the lower point is outside it.
	var upper := opaque_image.get_pixelv(origin + Vector2i(80, 12))
	var lower := opaque_image.get_pixelv(origin + Vector2i(80, 192))
	backdrop.color = Color.BLACK
	await RenderingServer.frame_post_draw
	var black_opaque := root.get_texture().get_image().get_pixelv(point)
	var samples := "80%% white=%s black=%s; opaque white=%s black=%s" % [white_eighty, black_eighty, white_opaque, black_opaque]
	_check("80% glass transmits the scene without a duplicate fill", white_eighty.r - black_eighty.r > 0.10, samples)
	_check("opaque glass blocks the scene", absf(white_opaque.r - black_opaque.r) < 0.02, samples)
	_check("80% glass supports secondary text over white", worst_contrast >= 4.5, "%.2f" % worst_contrast)
	_check("shared material has a visible static highlight", upper.g > lower.g + 0.01, "%s / %s" % [upper, lower])
	print("rendered HUD glass: ", samples, "; worst contrast=", worst_contrast, "; highlight=", upper, "/", lower)
	layer.queue_free()
	await process_frame


func _test_speed_extrema(manager: CanvasLayer) -> void:
	manager.refresh_numbers(_snapshot(10.0, 30.0))
	_check("speed maximum records 108 km/h", manager.frames.speed.left_value.text == "108 km/h", manager.frames.speed.left_value.text)
	manager.set_overlay_visible("speed", false)
	manager.refresh_numbers(_snapshot(11.0, 20.0))
	_check("hiding Speed does not clear its sampled maximum", is_equal_approx(manager.peak_airspeed, 30.0))
	manager.refresh_numbers(_snapshot(12.0, 35.0))
	manager.set_overlay_visible("speed", true)
	manager.refresh_numbers(_snapshot(12.0, 35.0))
	_check("reopening Speed includes its maximum samples collected while hidden", manager.frames.speed.left_value.text == "126 km/h",
		manager.frames.speed.left_value.text)

	manager.reset_flight()
	manager.refresh_numbers(_snapshot(12.0, 10.0))
	_check("explicit flight reset starts a new maximum", is_equal_approx(manager.peak_airspeed, 10.0)
		and manager.frames.speed.left_value.text == "36 km/h", manager.frames.speed.left_value.text)
	manager.refresh_numbers(_snapshot(3.0, 5.0))
	_check("rewinding telemetry time starts a new maximum", is_equal_approx(manager.peak_airspeed, 5.0)
		and manager.frames.speed.left_value.text == "18 km/h", manager.frames.speed.left_value.text)
	_check("rewind refresh retains the 10 Hz cadence", not manager.tick(0.01) and manager.tick(0.1))


func _test_missing_numbers(manager: CanvasLayer) -> void:
	manager.reset_flight()
	manager.refresh_numbers({"telemetry": {}, "warnings": PackedStringArray()})
	_check("missing telemetry draws dashes for player instrument readings",
		_is_dash(manager.frames.speed.value_label.text) and _is_dash(manager.frames.height.value_label.text)
		and _is_dash(manager.frames.weather.value_label.text) and _is_dash(manager.frames.power.value_label.text))
	_check("missing numeric detail values do not show stale readings",
		_is_dash(manager.frames.speed.left_value.text) and _is_dash(manager.frames.speed.right_value.text)
		and _is_dash(manager.frames.height.left_value.text) and _is_dash(manager.frames.height.right_value.text) and _is_dash(manager.frames.weather.left_value.text)
		and _is_dash(manager.frames.weather.right_value.text) and _is_dash(manager.frames.power.left_value.text)
		and _is_dash(manager.frames.power.right_value.text),
		"speed=%s/%s height=%s/%s weather=%s/%s power=%s/%s" % [manager.frames.speed.left_value.text,
		manager.frames.speed.right_value.text, manager.frames.height.left_value.text, manager.frames.height.right_value.text,
		manager.frames.weather.left_value.text, manager.frames.weather.right_value.text,
		manager.frames.power.left_value.text, manager.frames.power.right_value.text])


func _test_energy(manager: CanvasLayer) -> void:
	var no_energy := _snapshot(4.0, 8.0)
	manager.refresh_numbers(no_energy)
	_check("Power explains when there is no finite battery or fuel", manager.frames.power.subtitle.text == "Energy level unavailable"
		and manager.frames.power.value_label.text == "—"
		and manager.frames.power.unit_label.text.is_empty() and manager.frames.power.left_value.text == "—"
		and manager.frames.power.right_value.text == "—")

	var fuel := _snapshot(5.0, 8.0)
	fuel.mass_sample = {"ok": true, "finite_fuel": true, "fill_fraction": 0.42, "volume_ml": 1234.6, "low_fuel": false}
	manager.refresh_numbers(fuel)
	_check("Power accepts the finite fuel sample", manager.frames.power.value_label.text == "42"
		and manager.frames.power.unit_label.text == "%" and manager.frames.power.left_caption.text == "FUEL"
		and manager.frames.power.left_value.text == "1235 mL", manager.frames.power.left_value.text)

	manager.reset_flight()
	var battery := _snapshot(6.0, 8.0)
	battery.battery = {"ok": true, "battery_kind": "legacy", "time_s": 6.0, "bus_voltage_v": 12.4,
		"pack_current_a": 2.3, "consumed_charge_c": 0.0, "remaining_charge_c": 3600.0}
	manager.refresh_numbers(battery)
	_check("Power prefers a valid radio battery reading", manager.frames.power.value_label.text == "100"
		and manager.frames.power.unit_label.text == "%" and manager.frames.power.left_caption.text == "PACK VOLTAGE"
		and manager.frames.power.left_value.text == "12.4 V", manager.frames.power.left_value.text)


func _test_zero_speed_graph(manager: CanvasLayer) -> void:
	manager.reset_flight()
	for i in 3:
		manager.refresh_numbers(_snapshot(i * 0.1, 0.0))
		await process_frame
		await process_frame
	_check("idle aircraft draws a zero-speed trend without losing samples", manager.frames.speed._samples.size() == 3)
	_check("instrument icons are available offline for every widget", MODERN_IDS.all(func(id: String) -> bool:
		return manager.frames[id]._header_icon.texture != null))


func _test_extended_instruments(manager: CanvasLayer) -> void:
	manager.set_preset("instruments")
	var sample := _snapshot(10.0, 20.0)
	sample.rpm = 9123.0
	sample.telemetry.throttle = 0.42
	sample.telemetry.load_factor = 1.3
	sample.trims = {roll = 0.035, pitch = -0.08, yaw = 0.0}
	sample.mass_sample = {ok = true, finite_fuel = true, fill_fraction = 0.37, volume_ml = 185.0, fuel_remaining_kg = 0.15, low_fuel = false}
	manager.refresh_numbers(sample)
	await process_frame
	await process_frame
	_check("all instruments preset enables seven player widgets", MODERN_IDS.all(func(id: String) -> bool: return manager.frames[id].visible))
	_check("fuel displays accepted tank percentage volume and mass", manager.frames.fuel.value_label.text == "37"
		and manager.frames.fuel.left_value.text == "185 mL" and manager.frames.fuel.right_value.text == "150 g")
	_check("trim display preserves axis signs and fractions of full travel", manager.frames.trims._trim_labels[0].text == "+3.5%"
		and manager.frames.trims._trim_labels[1].text == "-8.0%" and manager.frames.trims._trim_labels[2].text == "0.0%",
		str(manager.frames.trims._trim_labels.map(func(label: Label) -> String: return label.text)))
	_check("engine separates shaft RPM throttle command and airframe load", manager.frames.engine.value_label.text == "9123"
		and manager.frames.engine.left_value.text == "42 %" and manager.frames.engine.right_value.text == "1.3 g")
	sample.mass_sample.low_fuel = true
	sample.mass_sample.reserve_estimated = true
	manager.refresh_numbers(sample)
	_check("estimated reserve is explicit", manager.frames.fuel.subtitle.text == "Estimated reserve · land soon")
	# Actual drawing signals verify cache behavior, rather than only comparing its implementation state.
	var draws := [0]
	manager.frames.fuel.graphic.draw.connect(func() -> void: draws[0] += 1)
	await process_frame
	await process_frame
	var before: int = draws[0]
	_check("fuel drawing callback is exercised before testing redraw suppression", before > 0)
	for i in 5:
		sample.telemetry.time_s += 0.1
		manager.refresh_numbers(sample)
		await process_frame
	_check("unchanged fuel does not redraw when unrelated flight time changes", draws[0] == before)
	sample.mass_sample.fill_fraction = 0.35
	manager.refresh_numbers(sample)
	await process_frame
	await process_frame
	_check("changed fuel invalidates its cached display", manager.frames.fuel.value_label.text == "35")
	manager.set_overlay_visible("fuel", false)
	sample.mass_sample.fill_fraction = 0.30
	manager.refresh_numbers(sample)
	_check("hidden fuel skips display work", manager.frames.fuel.value_label.text == "35")
	manager.set_overlay_visible("fuel", true)
	manager.refresh_numbers(sample)
	_check("reopened fuel refreshes to the current sample", manager.frames.fuel.value_label.text == "30")
	manager.refresh_numbers(_snapshot(11, 20))
	_check("missing extended data clears stale fuel trims and RPM", _is_dash(manager.frames.fuel.value_label.text)
		and _is_dash(manager.frames.engine.value_label.text) and manager.frames.trims._trim_labels.all(func(label: Label) -> bool: return _is_dash(label.text)))
	manager.reset_flight()
	for i in 150:
		manager.refresh_numbers(_snapshot(i * 0.1, float(i)))
	var speed: Control = manager.frames.speed
	_check("speed history retains exactly the latest 120 samples", speed._samples.size() == 120
		and speed._samples[speed._sample_head] == 30.0 and speed._samples[(speed._sample_head + 119) % 120] == 149.0)
	var key: Array = speed._view_key.duplicate(true)
	manager.refresh_numbers(_snapshot(14.9, 149.0))
	_check("paused sample is not appended twice", speed._samples.size() == 120 and speed._view_key == key)
	manager.set_overlay_visible("speed", false)
	manager.set_overlay_visible("speed", true)
	manager.refresh_numbers(_snapshot(14.9, 149.0))
	_check("reopening while paused plots the current speed immediately", speed._samples.size() == 1 and speed._samples[0] == 149.0)
	manager.reset_widget_positions()
	await process_frame
	await process_frame
	_check("seven normal instruments do not overlap at 1080p", _widgets_separate(manager), _widget_rects(manager))
	_check("default trims leave room for bottom-centre flight notices", manager.frames.trims.get_global_rect().end.y < 980)
	var normal_height: float = manager.frames.speed.size.y
	manager.set_widget_option("widget_compact", true)
	await process_frame
	await process_frame
	await process_frame
	_check("compact mode reduces height and keeps data and trim bars", manager.frames.speed.size.y < normal_height
		and not manager.frames.speed.graphic.visible and manager.frames.speed.left_value.is_visible_in_tree()
		and manager.frames.trims._trim_tracks[0].is_visible_in_tree(), "%s -> %s" % [normal_height, manager.frames.speed.size.y])
	_check("glass follows compact widget resizing", manager.frames.speed._glass.size.is_equal_approx(manager.frames.speed.size)
		and manager.frames.speed._glass_material.get_shader_parameter("rect_size").is_equal_approx(manager.frames.speed.size))
	manager.set_widget_option("widget_opacity", 0.8)
	_check("opacity adjusts only the backdrop", is_equal_approx(manager.frames.speed._style.bg_color.a, 0.8)
		and manager.frames.speed.modulate.a == 1.0)
	manager.set_widget_option("widget_size", "large")
	await process_frame
	await process_frame
	_check("large instruments stay on screen", manager.frames.speed.scale == Vector2(1.2, 1.2)
		and _widgets_in_bounds(manager, Vector2i(1920, 1080)))
	var instrument_font: Font = manager.frames.speed.value_label.get_theme_font("font")
	_check("scaled readings use an isolated shared MSDF font", instrument_font is FontFile
		and instrument_font.multichannel_signed_distance_field and instrument_font != ThemeDB.fallback_font
		and instrument_font == manager.frames.fuel.value_label.get_theme_font("font"))
	await _drag_header(manager.frames.speed, Vector2(100, -80))
	_check("scaled dragging retains normalized positions", _saved_positions_match(manager))
	manager.set_widget_option("widget_size", "normal")
	manager.set_widget_option("widget_compact", false)
	manager.set_widget_option("widget_opacity", 0.94)
	manager.reset_widget_positions()
	await process_frame
	await process_frame


func _widgets_separate(manager: CanvasLayer) -> bool:
	for i in MODERN_IDS.size():
		for j in range(i + 1, MODERN_IDS.size()):
			if manager.frames[MODERN_IDS[i]].get_global_rect().intersects(manager.frames[MODERN_IDS[j]].get_global_rect()):
				return false
	return true


func _test_widget_interaction(manager: CanvasLayer) -> void:
	var widget: Control = manager.frames.speed
	var old_position: Vector2 = widget.position
	var start: Vector2 = widget.handle.get_global_rect().get_center()
	var moved: Array = []
	widget.moved.connect(func(id: String, normalized: Vector2) -> void: moved.append([id, normalized]))
	_check("Speed header is a reachable drag handle", widget.handle.get_global_rect().has_point(start))
	await _drag_header(widget, Vector2(280, -220))
	var saved: Dictionary = manager.settings.get("positions", {})
	_check("a real header drag saves a normalized position", saved.has("speed")
		and saved.speed.size() == 2 and saved.speed[0] >= 0.0 and saved.speed[0] <= 1.0
		and saved.speed[1] >= 0.0 and saved.speed[1] <= 1.0 and widget.position != old_position,
		"%s → %s; moved=%s; handle=%s" % [old_position, widget.position, moved, widget.handle.get_global_rect()])
	if saved.has("speed"):
		var persisted: Vector2 = Vector2(saved.speed[0], saved.speed[1])
		_check("saved coordinates match the dragged widget's normalized location",
			(widget.normalized_position() - persisted).length() < 0.01)

	for id: String in MODERN_IDS:
		var frame: Control = manager.frames[id]
		var close_position: Vector2 = frame.close_button.get_global_rect().get_center()
		_click(close_position)
		await process_frame
		_check("%s closes without taking focus" % id, not frame.visible and not manager.is_overlay_visible(id)
			and root.get_viewport().gui_get_focus_owner() == null)
		manager.set_overlay_visible(id, true)
		manager.refresh_numbers(_snapshot(12.0, 15.0))
		await process_frame
		_check("%s reopens with focus still available to flight" % id, frame.visible
			and manager.is_overlay_visible(id) and root.get_viewport().gui_get_focus_owner() == null)

	var saved_before_lock: Dictionary = manager.settings.get("positions", {}).duplicate(true)
	var position_before_lock: Vector2 = manager.frames.speed.position
	manager.set_layout_locked(true)
	await _drag_header(manager.frames.speed, Vector2(-180, 140))
	_check("locked widgets do not move or overwrite saved coordinates", manager.settings.layout_locked
		and manager.frames.speed.layout_locked and manager.frames.speed.position == position_before_lock
		and manager.settings.positions == saved_before_lock)
	manager.set_layout_locked(false)


func _test_responsive_layout(manager: CanvasLayer) -> void:
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160), Vector2i(1280, 720)]:
		root.size = size
		await process_frame
		await process_frame
		_check("player widgets stay within %dx%d" % [size.x, size.y], _widgets_in_bounds(manager, size), _widget_rects(manager))
		_check("responsive resize retains normalized saved positions at %dx%d" % [size.x, size.y],
			_saved_positions_match(manager), _widget_rects(manager))
	manager.reset_widget_positions()
	manager.set_widget_option("widget_compact", true)
	await process_frame
	await process_frame
	await process_frame
	_check("compact default arrangement fits all seven without overlap at 720p", _widgets_separate(manager), _widget_rects(manager))
	manager.set_widget_option("widget_compact", false)


func _test_dialog(manager: CanvasLayer) -> void:
	var dialog: CanvasLayer = Dialog.new(manager)
	root.add_child(dialog)
	await process_frame
	manager.set_preset("full")
	var player_action := dialog.find_child("PlayerLayout", true, false) as Button
	_check("overlays dialog exposes Use player layout", player_action != null)
	if player_action == null:
		dialog.queue_free()
		return
	player_action.pressed.emit()
	_check("Use player layout selects the Player preset", manager.settings.preset == "player"
		and dialog.preset_picker.selected == Settings.PRESET_ORDER.find("player")
		and CORE_IDS.all(func(id: String) -> bool: return dialog.switches[id].button_pressed))

	var weather: CheckBox = dialog.switches.weather
	weather.set_pressed_no_signal(false)
	weather.toggled.emit(false)
	_check("player instrument switches update the manager and preset selection", not manager.is_overlay_visible("weather")
		and not dialog.switches.weather.button_pressed and dialog.preset_picker.selected == Settings.PRESET_ORDER.size())
	player_action.pressed.emit()
	_check("Use player layout restores all four player instruments", manager.settings.preset == "player"
		and CORE_IDS.all(func(id: String) -> bool: return manager.is_overlay_visible(id)))
	dialog.widget_size_picker.item_selected.emit(Settings.WIDGET_SIZES.find("large"))
	_check("size picker updates runtime and stays synchronized", manager.frames.speed.scale == Vector2(1.2, 1.2)
		and dialog.widget_size_picker.selected == Settings.WIDGET_SIZES.find("large"))
	dialog.widget_background_picker.item_selected.emit(2)
	_check("background picker updates runtime without fading text", manager.frames.speed._style.bg_color.a == 1.0
		and dialog.widget_background_picker.selected == 2)
	dialog.compact_switch.toggled.emit(true)
	_check("compact control updates widgets and reflects saved choice", not manager.frames.speed.graphic.visible and dialog.compact_switch.button_pressed)
	dialog.widget_size_picker.item_selected.emit(Settings.WIDGET_SIZES.find("normal"))
	dialog.compact_switch.toggled.emit(false)
	dialog.widget_background_picker.item_selected.emit(1)

	var lock: CheckBox = dialog.lock_switch
	lock.set_pressed_no_signal(true)
	lock.toggled.emit(true)
	_check("dialog lock switch updates widget lock state", manager.settings.get("layout_locked", false)
		and MODERN_IDS.all(func(id: String) -> bool: return manager.frames[id].layout_locked))
	lock.set_pressed_no_signal(false)
	lock.toggled.emit(false)
	_check("dialog unlock switch releases the layout", not manager.settings.get("layout_locked", false))

	var reset := dialog.find_child("ResetWidgetPositions", true, false) as Button
	_check("overlays dialog exposes reset positions", reset != null)
	if reset != null:
		reset.pressed.emit()
		_check("reset positions clears saved layout and restores the four defaults",
			not manager.settings.has("positions") and _default_positions_match(manager))
	dialog.queue_free()
	await process_frame


func _drag_header(widget: Control, delta: Vector2) -> void:
	var start: Vector2 = widget.handle.get_global_rect().get_center()
	_push_button(start, true)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = start + delta
	motion.global_position = start + delta
	motion.relative = delta
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(motion)
	await process_frame
	await process_frame
	_push_button(start + delta, false)
	await process_frame


func _push_button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = point
	event.global_position = point
	Input.parse_input_event(event)


func _click(point: Vector2) -> void:
	_push_button(point, true)
	_push_button(point, false)


func _snapshot(time_s: float, airspeed: float) -> Dictionary:
	return {
		"telemetry": {"time_s": time_s, "airspeed": airspeed, "ground_speed": airspeed - 2.0,
			"height_agl": 30.0, "vertical_speed": -0.5, "wind_speed": 4.0, "wind_from_deg": 270.0, "wind_up": 0.0},
		"warnings": PackedStringArray(["stall"]),
	}


func _widgets_in_bounds(manager: CanvasLayer, size: Vector2i) -> bool:
	var screen := Rect2(Vector2.ZERO, Vector2(size))
	for id: String in MODERN_IDS:
		var rect: Rect2 = manager.frames[id].get_global_rect()
		if not screen.encloses(rect) or rect.position.x < 11.0 or rect.position.y < 11.0:
			return false
	return true


func _saved_positions_match(manager: CanvasLayer) -> bool:
	var saved: Dictionary = manager.settings.get("positions", {})
	for id: String in MODERN_IDS:
		var expected: Vector2 = DEFAULT_PLAYER_POSITIONS[id]
		if saved.has(id):
			expected = Vector2(saved[id][0], saved[id][1])
		if (manager.frames[id].normalized_position() - expected).length() >= 0.01:
			return false
	return true


func _default_positions_match(manager: CanvasLayer) -> bool:
	for id: String in MODERN_IDS:
		if (manager.frames[id].normalized_position() - DEFAULT_PLAYER_POSITIONS[id]).length() >= 0.01:
			return false
	return true


func _widget_rects(manager: CanvasLayer) -> String:
	var parts := PackedStringArray()
	for id: String in MODERN_IDS:
		parts.append("%s %s" % [id, manager.frames[id].get_global_rect()])
	return "; ".join(parts)


func _is_dash(value: String) -> bool:
	return value.begins_with("–") or value.begins_with("—")


func _check(label: String, passed: bool, detail := "") -> void:
	_checks += 1
	if passed:
		return
	_failures += 1
	push_error("player widgets: %s %s" % [label, detail])
