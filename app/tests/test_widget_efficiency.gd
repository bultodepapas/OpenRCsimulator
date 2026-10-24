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


func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)
