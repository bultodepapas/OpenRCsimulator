extends SceneTree

const Classic := preload("res://render/overlays/classic_instrument.gd")
const Manager := preload("res://render/overlays/overlay_manager.gd")
const Settings := preload("res://render/overlays/overlay_settings.gd")
var checks := 0
var failures := 0
var draws := 0


func _initialize() -> void:
	TranslationServer.set_locale("en")
	await process_frame
	root.size = Vector2i(1920, 1080)
	if DisplayServer.get_name() != "headless": RenderingServer.set_default_clear_color(Color("e4edf2"))
	var manager := Manager.new({preset = "cockpit", units = "metric"}, "en")
	root.add_child(manager)
	await process_frame
	await process_frame
	_check("cockpit is opt-in and contains exactly five classic instruments", Settings.DEFAULTS.preset == "pilot" and manager.settings.visible.size() == 6 and Settings.CLASSIC_IDS.all(func(id: String) -> bool: return manager.frames[id].visible))
	_check("classic face and bezels use neutral graphite", _neutral(Classic.DIAL) and _neutral(Classic.BEZEL_OUTER)
		and _neutral(Classic.BEZEL_INNER) and _neutral(Classic.BEZEL_HIGHLIGHT))
	_check("horizon retains distinct sky and earth colors", Classic.SKY == Color("35789e") and Classic.EARTH == Color("78513b"))
	_check("classic widgets share the glass exterior and retain amber indications", Settings.CLASSIC_IDS.all(
		func(id: String) -> bool: return manager.frames[id]._glass_material.shader == Classic.GLASS)
		and Classic.ACCENT == Color("f1ca7d"))
	var t := {airspeed = 30.0, pitch_deg = 10.0, bank_deg = 30.0, height_datum = 1234.0, height_agl = 200.0, heading_deg = 359.8, vertical_speed = -2.0}
	for id: String in Settings.CLASSIC_IDS:
		manager.frames[id].refresh(t, "metric", 40.0, {}, {})
	if DisplayServer.get_name() != "headless":
		await process_frame
		RenderingServer.force_draw(false)
		_check("classic dial has a transparent side gap while header and face remain drawn", _visible_dial_gap(manager))
	_check("TAS converts to km/h and keeps flight maximum", manager.frames.airspeed_dial.left_value.text == "108 km/h" and manager.frames.airspeed_dial.right_value.text == "144 km/h")
	_check("altimeter distinguishes datum from terrain", manager.frames.altimeter.left_value.text == "1234 m" and manager.frames.altimeter.right_value.text == "200 m")
	_check("heading rounds through north without displaying 360", manager.frames.heading.subtitle.text.begins_with("0°"))
	_check("vertical speed keeps sink sign", manager.frames.variometer.left_value.text == "-2.0 m/s")
	_check("nose up lowers horizon", Classic.horizon_point(Vector2.ZERO, 10, 0).is_equal_approx(Vector2(0, 20)))
	_check("right bank rotates horizon counterclockwise", Classic.horizon_point(Vector2(40, 0), 0, 30).y < 0)
	var level := Classic.ground_polygon(0, 0)
	_check("level earth contains lower disc only", Geometry2D.is_point_in_polygon(Vector2(0, 50), level) and not Geometry2D.is_point_in_polygon(Vector2(0, -50), level))
	var inverted := Classic.ground_polygon(0, 180)
	_check("inverted earth is above the aircraft", Geometry2D.is_point_in_polygon(Vector2(0, -50), inverted) and not Geometry2D.is_point_in_polygon(Vector2(0, 50), inverted))
	_check("vertical climb is all sky", Classic.ground_polygon(90, 0).is_empty())
	_check("vertical dive is all ground", Geometry2D.is_point_in_polygon(Vector2(0, -80), Classic.ground_polygon(-90, 0)))
	var angles := Classic.altimeter_angles(250.0)
	_check("250 units gives east hundreds hand, slow thousands hand", is_zero_approx(angles.x) and is_equal_approx(angles.y, -PI * 0.45))
	_check("negative altitude uses continuous modular hands", is_equal_approx(Classic.altimeter_angles(-250).x, PI))
	# Force actual draw callbacks: catches polygon/primitive failures, including extreme pitch and missing samples.
	manager.frames.attitude.graphic.draw.connect(func() -> void: draws += 1)
	for attitude: Vector2 in [Vector2.ZERO, Vector2(90, 0), Vector2(-90, 0), Vector2(0, 180), Vector2(30, -60)]:
		t.pitch_deg = attitude.x
		t.bank_deg = attitude.y
		manager.frames.attitude.refresh(t, "metric", 40, {}, {})
		await process_frame
		RenderingServer.force_draw(false)
	_check("extreme attitude frames really rendered", draws >= 5)
	var prior := draws
	t.time_s = 99.0
	manager.frames.attitude.refresh(t, "metric", 99, {}, {})
	await process_frame
	RenderingServer.force_draw(false)
	_check("unrelated or paused data does not redraw attitude", draws == prior)
	for id: String in Settings.CLASSIC_IDS:
		manager.frames[id].refresh({}, "metric", NAN, {}, {})
		_check(id + " missing data suppresses needle/horizon", not manager.frames[id]._available)
		manager.frames[id].refresh(t, "imperial", 40, {}, {})
	_check("imperial altitude uses feet", manager.frames.altimeter.left_value.text.ends_with(" ft"))
	_check("imperial VSI uses ft/min and its matching scale", manager.frames.variometer._maximum == 2000 and manager.frames.variometer.left_value.text.ends_with(" ft/min"))
	t.airspeed = 100.0
	t.vertical_speed = 50.0
	manager.frames.airspeed_dial.refresh(t, "si", 100, {}, {})
	manager.frames.variometer.refresh(t, "si", 100, {}, {})
	_check("over-range TAS preserves numeric value and labels clipped needle", manager.frames.airspeed_dial._over_range and manager.frames.airspeed_dial.subtitle.text.contains("Scale exceeded") and manager.frames.airspeed_dial.left_value.text == "100.0 m/s")
	_check("over-range VSI preserves numeric value and labels clipped needle", manager.frames.variometer._over_range and manager.frames.variometer.left_value.text == "+50.0 m/s")
	for size_name: String in Settings.WIDGET_SIZES:
		manager.set_widget_option("widget_size", size_name)
		for compact: bool in [false, true]:
			manager.set_widget_option("widget_compact", compact)
			await process_frame
			await process_frame
			_check("five dials fit without overlap at 1080p: " + size_name + str(compact), _separate(manager))
			_check("compact keeps the horizon visible", manager.frames.attitude.graphic.visible)
			_check("classic header and footer stay bounded: " + size_name + str(compact), _bounded_classic_surfaces(manager))
	manager.set_widget_option("widget_size", "normal")
	manager.set_widget_option("widget_compact", false)
	for resolution: Vector2i in [Vector2i(2560, 1440), Vector2i(3840, 2160), Vector2i(1280, 720)]:
		root.size = resolution
		await process_frame
		await process_frame
		_check("classic close targets remain in bounds: " + str(resolution), Settings.CLASSIC_IDS.all(func(id: String) -> bool: return Rect2(Vector2.ZERO, Vector2(resolution)).encloses(manager.frames[id].get_global_rect())))
	root.size = Vector2i(1920, 1080)
	await process_frame
	for id: String in Settings.CLASSIC_IDS:
		var widget: Control = manager.frames[id]
		_check(id + " X never captures flight keyboard focus", widget.close_button.focus_mode == Control.FOCUS_NONE)
		widget.close_button.pressed.emit()
		_check(id + " closes individually", not widget.visible and id not in manager.settings.visible)
		manager.set_overlay_visible(id, true)
		_check(id + " reopens individually", widget.visible)
	var horizon: Control = manager.frames.attitude
	TranslationServer.set_locale("de")
	manager.set_widget_option("widget_size", "small")
	manager.set_widget_option("widget_compact", true)
	horizon.refresh({}, "metric", 40, {}, {})
	for i in 4: await process_frame
	var missing_height: float = horizon.size.y
	horizon.refresh({pitch_deg = 2.0, bank_deg = 34.0}, "metric", 40, {}, {})
	for i in 4: await process_frame
	RenderingServer.force_draw(false)
	var attitude_readout: Label = horizon.subtitle
	_check("German compact attitude shows both values on two visible lines", attitude_readout.text.contains("Nicklage der Nase\u00a0+2°")
		and attitude_readout.text.contains("Querneigung\u00a0+34°") and attitude_readout.get_line_count() == 2
		and attitude_readout.get_visible_line_count() == 2 and attitude_readout.size.y >= attitude_readout.get_combined_minimum_size().y)
	_check("wrapped attitude expands within the cockpit layout", horizon.size.y > missing_height and _separate(manager))
	TranslationServer.set_locale("en")
	horizon.refresh({pitch_deg = 2.0, bank_deg = 34.0}, "metric", 40, {}, {})
	for i in 4: await process_frame
	_check("short English compact attitude stays on one visible line", attitude_readout.get_line_count() == 1
		and attitude_readout.get_visible_line_count() == 1)
	TranslationServer.set_locale("de")
	horizon.refresh({}, "metric", 40, {}, {})
	for i in 4: await process_frame
	_check("attitude shrinks again when its readout returns to one line", horizon.size.y < missing_height + 1.0)
	manager.frames.airspeed_dial.refresh({airspeed = 100.0}, "si", 100, {}, {})
	manager.frames.variometer.refresh({vertical_speed = 50.0}, "si", 40, {}, {})
	for i in 4: await process_frame
	for id: String in ["airspeed_dial", "variometer"]:
		var overrange_readout: Label = manager.frames[id].subtitle
		_check("German compact " + id + " keeps units and scale warning visible", overrange_readout.text.contains("m/s")
			and overrange_readout.text.contains("Skalenbereich überschritten") and overrange_readout.get_line_count() <= 2
			and overrange_readout.get_visible_line_count() == overrange_readout.get_line_count()
			and overrange_readout.size.y >= overrange_readout.get_combined_minimum_size().y)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(20, 10)
	horizon._handle_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(60, -150)
	horizon._handle_input(motion)
	press.pressed = false
	horizon._handle_input(press)
	_check("classic drag persists bounded normalized position", manager.settings.get("positions", {}).has("attitude") and horizon.normalized_position().y < 1.0)
	manager.set_layout_locked(true)
	press.pressed = true
	horizon._handle_input(press)
	_check("classic layout lock prevents drag", not horizon.dragging)
	TranslationServer.set_locale("es")
	horizon.refresh(t, "metric", 40, {}, {})
	manager.frames.variometer.refresh(t, "metric", 40, {}, {})
	_check("Spanish attitude means cabeceo, not the elevator control", horizon.left_caption.text == "Cabeceo")
	_check("Spanish dial range is translated", manager.frames.variometer.right_caption.text == "Escala")
	manager.queue_free()
	await process_frame
	print("classic instruments checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _separate(manager: CanvasLayer) -> bool:
	for i in Settings.CLASSIC_IDS.size():
		var box: Rect2 = manager.frames[Settings.CLASSIC_IDS[i]].get_global_rect()
		if not Rect2(0, 0, 1920, 1080).encloses(box): return false
		for j in range(i + 1, Settings.CLASSIC_IDS.size()):
			if box.intersects(manager.frames[Settings.CLASSIC_IDS[j]].get_global_rect()): return false
	return true


func _visible_dial_gap(manager: CanvasLayer) -> bool:
	var captured: Image = root.get_texture().get_image()
	if captured == null or captured.is_empty(): return false
	var widget: Control = manager.frames.airspeed_dial
	var graphic_at: Vector2 = widget.get_global_transform().affine_inverse() * widget.graphic.get_global_transform().origin
	var graphic_mid: float = graphic_at.y + widget.graphic.size.y * 0.5
	var to_view := widget.get_global_transform()
	var header_origin: Vector2 = widget.get_global_transform().affine_inverse() * widget._glass.get_global_transform().origin
	var header_sample: Vector2 = header_origin + Vector2(widget._glass.size.x * 0.5, 3)
	var samples: Array[Vector2i] = [Vector2i(2, 2), Vector2i((to_view * Vector2(3, graphic_mid)).round()),
		Vector2i((to_view * header_sample).round()),
		Vector2i((to_view * Vector2(widget.size.x * 0.5, graphic_mid)).round())]
	var bounds := Rect2i(Vector2i.ZERO, captured.get_size())
	if not samples.all(func(point: Vector2i) -> bool: return bounds.has_point(point)): return false
	var background := captured.get_pixelv(samples[0])
	var gap := captured.get_pixelv(samples[1])
	var header := captured.get_pixelv(samples[2])
	var dial := captured.get_pixelv(samples[3])
	var ok := _color_distance(background, gap) < 0.03 and _color_distance(background, header) > 0.3 and _color_distance(background, dial) > 0.3
	if not ok: print("classic pixel samples background/gap/header/dial=", [background, gap, header, dial], " at ", samples)
	return ok


func _color_distance(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


func _bounded_classic_surfaces(manager: CanvasLayer) -> bool:
	for id: String in Settings.CLASSIC_IDS:
		var widget: Control = manager.frames[id]
		if widget._glass == null: return false
		var local_from_global := widget.get_global_transform().affine_inverse()
		var handle_at: Vector2 = local_from_global * widget.handle.get_global_transform().origin
		var graphic_at: Vector2 = local_from_global * widget.graphic.get_global_transform().origin
		var subtitle_at: Vector2 = local_from_global * widget.subtitle.get_global_transform().origin
		var header := Rect2(local_from_global * widget._glass.get_global_transform().origin, widget._glass.size)
		if widget.handle.get_parent() != widget.body or widget.handle.get_index() <= widget.graphic.get_index() \
			or widget.handle.get_index() >= widget.subtitle.get_index(): return false
		if not header.grow(0.01).encloses(Rect2(handle_at, widget.handle.size)) \
			or header.position.y < graphic_at.y + widget.graphic.size.y - 0.01 or header.end.y > subtitle_at.y + 0.01:
			print("classic header bounds ", id, " header=", header, " handle=", Rect2(handle_at, widget.handle.size), " graphic=", graphic_at, " subtitle=", subtitle_at)
			return false
		if not is_equal_approx(header.size.x, widget.size.x) or header.size.y > widget.handle.size.y + 4.01:
			print("classic header size ", id, " header=", header, " widget=", widget.size)
			return false
		if widget._footer.visible:
			var footer_at: Vector2 = local_from_global * widget._footer.get_global_transform().origin
			var footer_box := Rect2(footer_at - Vector2(8, 5), widget._footer.size + Vector2(16, 10))
			if not Rect2(Vector2.ZERO, widget.size).grow(0.01).encloses(footer_box) or widget._footer_style.bg_color.a < 0.84:
				print("classic footer bounds ", id, " footer=", footer_box, " widget=", widget.size, " alpha=", widget._footer_style.bg_color.a)
				return false
	return true


func _neutral(color: Color) -> bool:
	return is_equal_approx(color.r, color.g) and is_equal_approx(color.g, color.b)


func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)
