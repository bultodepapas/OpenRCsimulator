extends SceneTree

const Settings := preload("res://render/overlays/overlay_settings.gd")
const Classic := preload("res://render/overlays/classic_instrument.gd")

class CountingManager extends "res://render/overlays/overlay_manager.gd":
	var layout_passes := 0
	func _layout_player_widgets() -> void:
		layout_passes += 1
		super()

var checks := 0
var failures := 0
var writes := 0
var style_changes := 0
var face_draws := 0
var foreground_draws := 0


func _initialize() -> void:
	await process_frame
	root.size = Vector2i(1920, 1080)
	await _test_glass_lifecycle()
	await _measure_glass_creation()
	var manager := CountingManager.new({preset = "instruments", units = "metric"})
	root.add_child(manager)
	for i in 4: await process_frame
	var idle_listeners: int = Settings.PLAYER_IDS.filter(func(id: String) -> bool: return manager.frames[id].is_processing_input()).size()
	print("idle player widget global input listeners=", idle_listeners)
	_check("all 18 idle player widgets skip global input dispatch", idle_listeners == 0)
	manager.settings_changed.connect(func(_settings: Dictionary) -> void: writes += 1)
	for id: String in Settings.PLAYER_IDS:
		manager.frames[id]._style.changed.connect(func() -> void: style_changes += 1)
	manager.layout_passes = 0
	manager._since_text = 0.04
	for i in 100:
		manager.apply(manager.settings.duplicate(true))
		manager.set_units("metric")
	_check("200 identical settings requests produce no save events", writes == 0)
	_check("identical settings do not reflow or change styles", manager.layout_passes == 0 and style_changes == 0)
	_check("identical settings preserve the telemetry cadence", is_equal_approx(manager._since_text, 0.04))
	manager.set_widget_option("widget_opacity", 0.8)
	_check("real opacity change saves exactly once", writes == 1)
	_check("opacity updates every widget backdrop without layout", style_changes == Settings.PLAYER_IDS.size() and manager.layout_passes == 0)
	_check("appearance-only changes preserve telemetry cadence", is_equal_approx(manager._since_text, 0.04))
	style_changes = 0
	manager._save_widget_position("speed", Vector2(0.2, 0.8))
	_check("position change saves and reflows once", writes == 2 and manager.layout_passes == 1)
	_check("position change leaves styles and cadence alone", style_changes == 0 and is_equal_approx(manager._since_text, 0.04))
	_check("new position remains normalized", manager.frames.speed.normalized_position().distance_to(Vector2(0.2, 0.8)) < 0.001)
	manager.set_layout_locked(true)
	_check("lock change saves once without reflow", writes == 3 and manager.layout_passes == 1)
	manager.layout_passes = 0
	for id: String in Settings.PLAYER_IDS: manager.frames[id].resized.emit()
	_check("resize notifications defer the full layout pass", manager.layout_passes == 0 and manager._player_layout_pending)
	await process_frame
	await process_frame
	_check("twelve resize notifications coalesce into one layout pass", manager.layout_passes == 1 and not manager._player_layout_pending)
	var previous_writes := writes
	manager.set_units("imperial")
	_check("unit change refreshes readings immediately and saves once", is_inf(manager._since_text) and writes == previous_writes + 1)
	manager.set_preset("cockpit")
	for i in 3: await process_frame
	var horizon: Control = manager.frames.attitude
	horizon._face.draw.connect(func() -> void: face_draws += 1)
	horizon.graphic.draw.connect(func() -> void: foreground_draws += 1)
	var t := {pitch_deg = 10.0, bank_deg = 30.0}
	horizon.refresh(t, "metric", NAN, {}, {})
	await process_frame
	RenderingServer.force_draw(false)
	_check("static and moving drawing checks are non-vacuous", face_draws > 0 and foreground_draws > 0)
	var prior_face := face_draws
	var prior_foreground := foreground_draws
	t.bank_deg = 31.0
	horizon.refresh(t, "metric", NAN, {}, {})
	await process_frame
	RenderingServer.force_draw(false)
	_check("attitude changes redraw only the moving indication", face_draws == prior_face and foreground_draws > prior_foreground)
	prior_foreground = foreground_draws
	for i in 100: horizon.refresh(t, "metric", NAN, {}, {})
	await process_frame
	RenderingServer.force_draw(false)
	_check("100 paused samples cause no foreground redraw", foreground_draws == prior_foreground and face_draws == prior_face)
	var cached_disc: PackedVector2Array = horizon._horizon_disc.duplicate()
	var same_geometry := true
	for attitude: Vector2 in [Vector2.ZERO, Vector2(90, 0), Vector2(-90, 0), Vector2(0, 180), Vector2(12, -40)]:
		var cached := Classic.ground_polygon(attitude.x, attitude.y, horizon._horizon_disc)
		var fresh := Classic.ground_polygon(attitude.x, attitude.y)
		same_geometry = same_geometry and cached == fresh
	_check("cached horizon geometry matches fresh clipping at edge cases", same_geometry)
	_check("clipping never mutates cached circle points", horizon._horizon_disc == cached_disc and cached_disc.size() == 96)
	manager.set_layout_locked(false)
	manager._save_widget_position("speed", Vector2(0.4, 0.3))
	manager._save_widget_position("height", Vector2(0.6, 0.7))
	var before_reset := manager.settings.duplicate(true)
	var saves_before_reset := writes
	manager.frames.speed.reset_position_requested.emit("speed")
	_check("individual reset saves once and removes only its position", writes == saves_before_reset + 1 and not manager.settings.positions.has("speed") and manager.settings.positions.height == before_reset.positions.height)
	_check("individual reset restores default and preserves appearance/visibility", manager.frames.speed.normalized_position().distance_to(manager.PLAYER_POSITIONS.speed) < 0.001 and manager.settings.visible == before_reset.visible and manager.settings.widget_opacity == before_reset.widget_opacity)
	manager.set_layout_locked(true)
	saves_before_reset = writes
	manager.reset_widget_position("height")
	_check("locked position cannot be reset individually", writes == saves_before_reset and manager.settings.positions.height == before_reset.positions.height)
	manager.queue_free()
	await process_frame
	print("widget efficiency checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _glass_counts(manager: CanvasLayer) -> Array[int]:
	var counts: Array[int] = [0, 0, 0] # materials, ColorRects, underlay nodes
	for id: String in Settings.PLAYER_IDS:
		var widget: Control = manager.frames[id]
		if widget._glass_material != null: counts[0] += 1
		if widget._glass != null:
			counts[1] += 1
			if widget._glass.get_parent() != null: counts[2] += 1
	return counts


func _glass_matches(widget: Control, opacity: float) -> bool:
	var glass: ColorRect = widget._glass
	var material: ShaderMaterial = widget._glass_material
	if glass == null or material == null: return false
	var base: Color = material.get_shader_parameter("base_color")
	var rect: Vector2 = material.get_shader_parameter("rect_size")
	return glass.visible and glass.material == material and is_equal_approx(base.a, opacity) \
		and rect.is_equal_approx(widget.size) and glass.size.is_equal_approx(widget.size)


func _test_glass_lifecycle() -> void:
	for preset: String in ["pilot", "player", "cockpit"]:
		var fresh_manager := CountingManager.new({preset = preset})
		var detached := _glass_counts(fresh_manager)
		_check("detached " + preset + " starts without glass", detached == [0, 0, 0])
		root.add_child(fresh_manager)
		await process_frame
		await process_frame
		var counts := _glass_counts(fresh_manager)
		var expected: int = {pilot = 0, player = 4, cockpit = 5}[preset]
		print("widget glass fresh ", preset, " materials/rects/underlays=", counts, " detached=", detached)
		_check("fresh " + preset + " allocates only shown glass: " + str(counts), counts == [expected, expected, expected])
		fresh_manager.queue_free()
		await process_frame

	var first_host := Node.new()
	var second_host := Node.new()
	root.add_child(first_host)
	root.add_child(second_host)
	# A saved cockpit preset and appearance are applied before entering the tree.
	var manager := CountingManager.new({preset = "cockpit", widget_opacity = 0.8, widget_size = "large", widget_compact = true})
	_check("saved detached preset defers glass", _glass_counts(manager) == [0, 0, 0])
	first_host.add_child(manager)
	await process_frame
	await process_frame
	var saved_ready := Settings.CLASSIC_IDS.all(func(id: String) -> bool: return _glass_matches(manager.frames[id], 0.8))
	_check("saved cockpit restores appearance on first attachment", _glass_counts(manager) == [5, 5, 5] and saved_ready)

	manager.preview(false)
	manager.set_preset("navigation")
	manager.set_widget_option("widget_opacity", 1.0)
	_check("hidden canvas layer defers newly selected glass", _glass_counts(manager) == [5, 5, 5])
	var wind: Control = manager.frames.wind_track
	var first_draw := [0, false, ""]
	wind.draw.connect(func() -> void:
		if first_draw[0] == 0:
			first_draw[1] = _glass_matches(wind, 1.0)
			first_draw[2] = "glass=%s material=%s widget_size=%s" % [wind._glass, wind._glass_material, wind.size]
		first_draw[0] += 1)
	manager.preview(true)
	await process_frame
	RenderingServer.force_draw(false)
	_check("first revealed draw already has current glass: " + str(first_draw), first_draw[0] > 0 and first_draw[1])
	_check("layer reveal creates only the three navigation surfaces", _glass_counts(manager) == [8, 8, 8]
		and Settings.NAVIGATION_IDS.all(func(id: String) -> bool: return _glass_matches(manager.frames[id], 1.0)))

	manager.root.hide()
	manager.set_preset("training")
	manager.set_widget_option("widget_opacity", 0.94)
	_check("hidden Control ancestor defers new surfaces", _glass_counts(manager) == [8, 8, 8])
	manager.root.show()
	await process_frame
	await process_frame
	_check("ancestor reveal creates only selected training surfaces", _glass_counts(manager) == [11, 11, 11]
		and ["maneuver", "glide", "flight_summary"].all(func(id: String) -> bool: return _glass_matches(manager.frames[id], 0.94)))

	first_host.remove_child(manager)
	manager.set_preset("player")
	manager.set_overlay_visible("session_stats", true)
	manager.set_widget_option("widget_opacity", 0.8)
	_check("detached settings do not create more glass", _glass_counts(manager) == [11, 11, 11])
	var speed: Control = manager.frames.speed
	var first_reattached_draw := [0, false]
	speed.draw.connect(func() -> void:
		if first_reattached_draw[0] == 0: first_reattached_draw[1] = _glass_matches(speed, 0.8)
		first_reattached_draw[0] += 1)
	second_host.add_child(manager)
	await process_frame
	RenderingServer.force_draw(false)
	_check("first draw after reparenting has current glass", first_reattached_draw[0] > 0 and first_reattached_draw[1])
	await process_frame
	_check("reparenting restores current settings and selected glass", _glass_counts(manager) == [16, 16, 16]
		and ["speed", "height", "power", "weather", "session_stats"].all(func(id: String) -> bool: return _glass_matches(manager.frames[id], 0.8)))

	var material_ids := {}
	for id: String in Settings.PLAYER_IDS:
		var material: ShaderMaterial = manager.frames[id]._glass_material
		if material != null: material_ids[id] = material.get_instance_id()
	for id: String in Settings.PLAYER_IDS:
		manager.set_overlay_visible(id, true)
		await process_frame
		var material: ShaderMaterial = manager.frames[id]._glass_material
		var within_bound := _glass_counts(manager)[0] <= Settings.PLAYER_IDS.size()
		_check(id + " creates at most one surface and retains prior identity", within_bound and material != null
			and (not material_ids.has(id) or material_ids[id] == material.get_instance_id()))
		if material != null: material_ids[id] = material.get_instance_id()
	_check("visiting all widgets creates exactly 19 independent surfaces", _glass_counts(manager) == [19, 19, 19]
		and material_ids.size() == Settings.PLAYER_IDS.size())
	var distinct := {}
	for value: Variant in material_ids.values(): distinct[value] = true
	_check("every widget owns a distinct material", distinct.size() == Settings.PLAYER_IDS.size())
	for id: String in Settings.PLAYER_IDS:
		manager.set_overlay_visible(id, false)
		manager.set_overlay_visible(id, true)
		await process_frame
		var material: ShaderMaterial = manager.frames[id]._glass_material
		_check(id + " reuses its material after close and reopen", material != null and material_ids.has(id)
			and material_ids[id] == material.get_instance_id())
	for opacity: float in Settings.WIDGET_OPACITY_STEPS:
		manager.set_overlay_visible("speed", false)
		manager.set_widget_option("widget_opacity", opacity)
		manager.set_overlay_visible("speed", true)
		await process_frame
		_check("hidden appearance is restored on reopen " + str(opacity), _glass_matches(manager.frames.speed, opacity)
			and material_ids.get("speed", 0) == manager.frames.speed._glass_material.get_instance_id())
	first_host.queue_free()
	second_host.queue_free()
	await process_frame


func _measure_glass_creation() -> void:
	var construction: Array[int] = []
	var attachment: Array[int] = []
	var first_reveal: Array[int] = []
	var warm_reveal: Array[int] = []
	# These are synchronous wall times only; rendering and the next frame are excluded.
	for trial in 7:
		var start := Time.get_ticks_usec()
		var manager := CountingManager.new({preset = "pilot"})
		construction.append(Time.get_ticks_usec() - start)
		start = Time.get_ticks_usec()
		root.add_child(manager)
		attachment.append(Time.get_ticks_usec() - start)
		await process_frame
		start = Time.get_ticks_usec()
		manager.set_overlay_visible("speed", true)
		first_reveal.append(Time.get_ticks_usec() - start)
		await process_frame
		manager.set_overlay_visible("speed", false)
		start = Time.get_ticks_usec()
		manager.set_overlay_visible("speed", true)
		warm_reveal.append(Time.get_ticks_usec() - start)
		manager.queue_free()
		await process_frame
	for samples: Array in [construction, attachment, first_reveal, warm_reveal]: samples.sort()
	print("widget glass timing display=", DisplayServer.get_name(), " trials=7 median synchronous wall us construction=",
		construction[3], " attachment=", attachment[3], " first_reveal=", first_reveal[3], " warm_reveal=", warm_reveal[3],
		" (excludes frame and GPU time)")


func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)
