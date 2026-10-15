# HUD-02…07/11: flight overlays. Settings validation and presets; a real mouse click on an X hides only that overlay
# and leaves the flight keys working; warnings; the transmitter layout; no overlap at 1280×720; contrast; the
# [hud] preferences round trip; and a real flight scene with overlays on (Home route), keys F2 and F3.
# Run: godot --headless --path . --script res://tests/test_overlay_manager.gd
extends SceneTree

const Settings := preload("res://render/overlays/overlay_settings.gd")
const Manager := preload("res://render/overlays/overlay_manager.gd")
const Transmitter := preload("res://render/overlays/transmitter.gd")
const FlightData := preload("res://render/overlays/flight_data.gd")
const Frame := preload("res://render/overlays/overlay_frame.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const Preferences := preload("res://app_state/preferences.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const OverlaysDialog := preload("res://ui/overlays_dialog.gd")
const WarningsBar := preload("res://render/overlays/warnings_bar.gd")
const Guide := preload("res://render/overlays/controls_guide.gd")
const Profile := preload("res://input/controller_profile.gd")
const PREFS := "user://test_overlay_settings.cfg"

var _failures := 0
var _count := 0
var _keys_seen: Array = []


class KeyProbe extends Node:
	var seen: Array
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed:
			seen.append(event.physical_keycode)


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	TranslationServer.set_locale("en")
	_run()


func _run() -> void:
	_settings()
	_transmitter()
	_contrast()
	_preferences()
	await _manager()
	await _dialog()
	await _spanish_layout()
	await _controls_guide()
	await _flight_scene()
	await _pause_preview()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("overlay manager: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures else 0)


func _settings() -> void:
	_check("defaults: Pilot preset, units by language, Mode 2", Settings.validate(null) == Settings.DEFAULTS)
	_check("pilot preset is flight, transmitter, warnings, wind", Settings.DEFAULTS.visible == ["flight", "transmitter", "warnings", "wind", "controls"])
	var bad := Settings.validate({ preset = 3, visible = "all", units = "furlongs", stick_mode = 3 })
	_check("wrong types and ranges fall back to defaults", bad == Settings.DEFAULTS, str(bad))
	_check("a named preset defines the visible set", Settings.validate({ preset = "full", visible = ["performance"] }).visible == Settings.PRESETS.full)
	var custom := Settings.validate({ preset = "custom", visible = ["wind", "bogus", "flight", "wind"], units = "imperial", stick_mode = 1 })
	_check("custom keeps its own set, canonical order, no unknowns or duplicates", custom.visible == ["flight", "wind"], str(custom.visible))
	_check("custom keeps units and stick mode", custom.units == "imperial" and custom.stick_mode == 1)
	_check("a float stick mode is not an int", Settings.validate({ stick_mode = 1.0 }).stick_mode == 2)
	_check("preset_for recognises every preset", Settings.PRESET_ORDER.all(func(p: String) -> bool: return Settings.preset_for(Settings.PRESETS[p]) == p))
	_check("preset_for: any other set is custom", Settings.preset_for(["flight"]) == "custom")
	_check("flight clock m:ss and h:mm:ss", FlightData.clock(75.9) == "1:15" and FlightData.clock(3725.0) == "1:02:05" and FlightData.clock(-3.0) == "0:00")


func _transmitter() -> void:
	var sticks := { roll = 0.5, pitch = 1.0, yaw = -0.25, throttle = 1.0 }
	var m2: Array = Transmitter.stick_layout(2, sticks)
	_check("Mode 2: left = rudder + throttle (full throttle at the top)", m2[0] == Vector2(-0.25, -1.0), str(m2[0]))
	_check("Mode 2: right = aileron + elevator (stick back sits low)", m2[1] == Vector2(0.5, 1.0), str(m2[1]))
	var m1: Array = Transmitter.stick_layout(1, sticks)
	_check("Mode 1 swaps elevator and throttle", m1[0] == Vector2(-0.25, 1.0) and m1[1] == Vector2(0.5, -1.0), str(m1))
	_check("idle throttle sits at the bottom", (Transmitter.stick_layout(2, { roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0 })[0] as Vector2).y == 1.0)
	_check("sticks clamp to the gimbal", Transmitter.stick_layout(2, { roll = 3.0, pitch = -3.0, yaw = 0.0, throttle = 2.0 }) == [Vector2(0.0, -1.0), Vector2(1.0, -1.0)])
	var trims: Array = Transmitter.trim_layout(2, { roll = 0.1, pitch = -0.05, yaw = 0.02 })
	_check("Mode 2 trims: rudder left, aileron and elevator right", trims == [Vector2(0.02, 0.0), Vector2(0.1, -0.05)], str(trims))
	_check("Mode 1 trims: elevator moves left", Transmitter.trim_layout(1, { roll = 0.1, pitch = -0.05, yaw = 0.02 }) == [Vector2(0.02, -0.05), Vector2(0.1, 0.0)])


func _contrast() -> void:
	var backplate := Color(UiTheme.PANEL, Frame.BACKPLATE_ALPHA)
	_check("secondary text ≥ 4.5:1 on the backplate over any sky", UiTheme.contrast(UiTheme.TEXT_2, backplate) >= 4.5, "%.2f" % UiTheme.contrast(UiTheme.TEXT_2, backplate))
	_check("values ≥ 4.5:1 on the backplate over any sky", UiTheme.contrast(UiTheme.TEXT, backplate) >= 4.5)
	_check("danger chip text ≥ 4.5:1", UiTheme.contrast(UiTheme.TEXT, UiTheme.PRIMARY.pressed) >= 4.5, "%.2f" % UiTheme.contrast(UiTheme.TEXT, UiTheme.PRIMARY.pressed))
	_check("caution chip text ≥ 4.5:1", UiTheme.contrast(UiTheme.PANEL, UiTheme.FOCUS) >= 4.5)


func _preferences() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	_check("no file: default overlays", Preferences.load_from(PREFS).hud == Settings.DEFAULTS)
	var p := Preferences.load_from(PREFS)
	p.hud = { preset = "custom", visible = ["flight", "telemetry"], units = "si", stick_mode = 1 }
	_check("save", Preferences.save_to(PREFS, p) == OK)
	_check("custom overlays round-trip", Preferences.load_from(PREFS).hud == { preset = "custom", visible = ["flight", "telemetry"], units = "si", stick_mode = 1 })
	var cfg := ConfigFile.new()
	cfg.load(PREFS)
	cfg.set_value("hud", "units", 7)
	cfg.set_value("hud", "preset", "everything")
	cfg.save(PREFS)
	var damaged: Dictionary = Preferences.load_from(PREFS).hud
	_check("damaged [hud] values fall back per key", damaged.units == "auto" and damaged.preset == "pilot" and damaged.stick_mode == 1, str(damaged))


func _manager() -> void:
	# The headless display server sets its window to 64×64 on the first frame, over any earlier size: resize after it.
	await process_frame
	root.size = Vector2i(1920, 1080)
	await process_frame
	var manager: CanvasLayer = Manager.new({}, "en")
	root.add_child(manager)
	var changes: Array = []
	manager.settings_changed.connect(func(s: Dictionary) -> void: changes.append(s))
	var probe := KeyProbe.new()
	probe.seen = _keys_seen
	root.add_child(probe)
	var snap := _snapshot(PackedStringArray(["stall", "far"]))
	manager.update(snap, 1.0)
	await process_frame
	await process_frame
	_check("Pilot preset shows its five overlays", _shown(manager) == ["flight", "transmitter", "warnings", "wind", "controls"], str(_shown(manager)))
	_check("imperial for English: 20 m/s = 45 mph", manager.frames.flight.values.airspeed.text == "45 mph", manager.frames.flight.values.airspeed.text)
	_check("height above ground in ft", manager.frames.flight.values.height.text == "98 ft", manager.frames.flight.values.height.text)
	_check("two warning chips", manager.frames.warnings.chips.get_child_count() == 2)
	_check("pilot layout at 1920×1080: no overlap, all on screen", _layout_ok(manager, false, Vector2(1920, 1080)), _rects(manager))
	root.size = Vector2i(1280, 720)
	await process_frame
	_check("pilot layout: no overlap, all on a 1280×720 screen", _layout_ok(manager, false), _rects(manager))
	manager.apply({ preset = "full" }, false)
	manager.update(snap, 1.0)
	await process_frame
	_check("full layout: no overlap, all on screen", _layout_ok(manager, false), _rects(manager))
	manager.apply({ preset = "developer" }, false)
	var typical := PackedStringArray()
	for i in 14: # today's input panel plus status: about 14 lines of up to ~60 characters
		typical.append("channel %02d  +0.00   +0.00   R ail +0.0°   status text ......" % i)
	manager.diagnostics_panel.text = "\n".join(typical)
	manager.diagnostics_hud.text = "airspeed  20.0 m/s   altitude  30.0 m   AoA +4.0°   throttle 60%"
	manager.performance_label.text = " 60 fps   frame p95  16.7 ms   physics  300 µs/tick"
	manager.update(snap, 1.0)
	await process_frame
	_check("developer layout: every overlay on screen", _layout_ok(manager, true), _rects(manager))
	manager.apply({ preset = "pilot" }, false)
	await process_frame
	await process_frame

	# A real mouse click on the wind overlay's ×.
	var button: Button = manager.frames.wind.close_button
	var centre := button.get_global_rect().get_center()
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = centre
		click.global_position = centre
		root.get_viewport().push_input(click)
	await process_frame
	_check("× hides only that overlay", _shown(manager) == ["flight", "transmitter", "warnings", "controls"], str(_shown(manager)))
	_check("× makes the set custom and announces it", manager.settings.preset == "custom" and changes.size() == 1 and changes[0].visible == ["flight", "transmitter", "warnings", "controls"])
	_check("× took no keyboard focus", root.get_viewport().gui_get_focus_owner() == null)
	var ui := UiDriver.new(self)
	await ui.tap(KEY_UP)
	_check("a flight key still arrives after the click", _keys_seen.has(KEY_UP), str(_keys_seen))

	manager.cycle_preset()
	_check("F2 after a custom set: Off", manager.settings.preset == "off" and _shown(manager).is_empty())
	var order: Array = []
	for i in 4:
		manager.cycle_preset()
		order.append(manager.settings.preset)
	_check("F2 cycles Pilot → Full → Developer → Off", order == ["pilot", "full", "developer", "off"], str(order))
	manager.set_preset("pilot")
	manager.toggle_developer()
	_check("F3 adds diagnostics and performance", manager.is_overlay_visible("diagnostics") and manager.is_overlay_visible("performance") and manager.settings.preset == "custom")
	manager.toggle_developer()
	_check("F3 again removes both and finds Pilot again", manager.settings.preset == "pilot")
	manager.set_overlay_visible("warnings", false)
	manager.update(snap, 1.0)
	_check("closed warnings stay hidden while warnings exist", not manager.frames.warnings.visible)
	manager.set_overlay_visible("warnings", true)
	manager.update(_snapshot(PackedStringArray()), 1.0)
	_check("open warnings hide when there is nothing to say", not manager.frames.warnings.visible)
	manager.set_units("metric")
	manager.update(snap, 1.0)
	_check("metric: 72 km/h, 30 m", manager.frames.flight.values.airspeed.text == "72 km/h" and manager.frames.flight.values.height.text == "30 m")
	manager.update({}, 1.0)
	_check("no flight: placeholders, not stale numbers", manager.frames.flight.values.airspeed.text == "–")
	manager.queue_free()
	probe.queue_free()
	await process_frame


func _dialog() -> void:
	var manager: CanvasLayer = Manager.new({}, "en")
	root.add_child(manager)
	var dialog: CanvasLayer = OverlaysDialog.new(manager)
	var closed: Array = []
	dialog.closed.connect(func() -> void: closed.append(true))
	root.add_child(dialog)
	await process_frame
	_check("dialog shows the Pilot preset and its switches", dialog.preset_picker.selected == 1
		and Settings.IDS.all(func(id: String) -> bool: return dialog.switches[id].button_pressed == Settings.PRESETS.pilot.has(id)))
	dialog.switches.telemetry.button_pressed = true
	_check("switching Telemetry on gives the Full preset", manager.settings.preset == "full" and dialog.preset_picker.selected == 2)
	dialog.units_picker.item_selected.emit(2)
	dialog.mode_picker.item_selected.emit(0)
	_check("units and stick mode apply at once", manager.settings.units == "imperial" and manager.settings.stick_mode == 1)
	dialog.preset_picker.item_selected.emit(0)
	_check("choosing Off clears every switch", manager.settings.preset == "off" and not dialog.switches.flight.button_pressed)
	await UiDriver.new(self).tap(KEY_ESCAPE)
	_check("Esc closes the dialog", closed.size() == 1)
	dialog.queue_free()
	manager.queue_free()
	await process_frame


func _spanish_layout() -> void:
	TranslationServer.set_locale("es")
	var manager: CanvasLayer = Manager.new({}, "es")
	root.add_child(manager)
	manager.update(_snapshot(PackedStringArray(["failsafe", "safe", "far"])), 1.0)
	await process_frame
	await process_frame
	_check("Spanish: metric by language", manager.frames.flight.values.airspeed.text == "72 km/h")
	_check("Spanish pilot layout with three long warnings: no overlap at 1280×720", _layout_ok(manager, false), _rects(manager))
	var every := PackedStringArray(["failsafe", "safe", "stall", "low", "far", "battery", "experimental"])
	var calm := _snapshot(every)
	calm.telemetry.wind_up = 0.0
	manager.refresh_numbers(calm)
	await process_frame
	await process_frame
	var wind_calm_up: Vector2 = manager.frames.wind.size
	_check("all seven Spanish warnings wrap inside the bar's width", manager.frames.warnings.chips.size.x <= WarningsBar.MAX_WIDTH + 0.5
		and manager.frames.warnings.chips.size.y > 40.0, str(manager.frames.warnings.chips.size))
	_check("seven warnings still overlap nothing at 1280×720", _layout_ok(manager, false), _rects(manager))
	var gust := _snapshot(every)
	gust.telemetry.wind_up = 1.2
	manager.refresh_numbers(gust)
	await process_frame
	await process_frame
	_check("wind box keeps its size when an updraft line appears", manager.frames.wind.size == wind_calm_up,
		"%s → %s" % [wind_calm_up, manager.frames.wind.size])
	manager.queue_free()
	TranslationServer.set_locale("en")
	await process_frame


func _controls_guide() -> void:
	var manager: CanvasLayer = Manager.new({}, "en")
	root.add_child(manager)
	await process_frame
	var guide: Control = manager.frames.controls
	_check("guide opens by default with keyboard commands", guide.visible and _guide_text(guide).contains("Roll") and _guide_text(guide).contains("W / S"))
	_check("guide lists every shared keyboard shortcut", Guide.Reference.SHORTCUTS.all(func(row: Array) -> bool: return _guide_text(guide).contains(tr(row[1]))))
	var profile: Dictionary = Profile.defaults("gamepad", "mode1")
	profile.presentation.glyph_family = "playstation"
	profile.actions.camera_cycle = { type = "button", button = JOY_BUTTON_RIGHT_SHOULDER }
	var context := { connected = true, device_name = "DualSense", device_info = {name = "DualSense"}, profile = profile }
	guide.refresh(context)
	await process_frame
	_check("selected gamepad automatically opens its guide", guide.controller_button.button_pressed and guide.source_label.text == "DualSense")
	_check("controller guide reflects a remapped camera button", _guide_text(guide).contains("R1") and not _guide_text(guide).contains("Triangle"))
	_check("Mode 1 shows the actual pitch axis", Guide.axis_text(profile.pitch, true, "playstation", {}) == "Left stick ↕")
	_check("Mode 1 shows the actual throttle axis", Guide.axis_text(profile.throttle, true, "playstation", {}) == "Right stick ↕")
	_check("rate throttle explains its hold behavior", _guide_text(guide).contains("Throttle holds when you release the stick."))
	guide.keyboard_button.pressed.emit()
	guide.refresh(context)
	_check("refresh preserves a manual keyboard-tab choice", guide.keyboard_button.button_pressed and _guide_text(guide).contains("Flight axes use the selected controller."))
	profile.actions.camera_cycle = { type = "unbound" }
	guide.refresh(context)
	guide.controller_button.pressed.emit()
	_check("unbound camera action is not advertised", not _guide_text(guide).contains("Cycle camera"))
	profile = Profile.defaults("gamepad", "trigger_absolute")
	context.profile = profile
	guide.refresh(context)
	_check("absolute trigger has its own instructions", _guide_text(guide).contains("Release the trigger for idle throttle.") and _guide_text(guide).contains("R2"))
	context.capabilities = {gear = true, smoke = false, flaps = false}
	guide.refresh(context)
	_check("unavailable equipment is reported honestly", _guide_text(guide).contains("Circle") and _guide_text(guide).contains("Not available") and not _guide_text(guide).contains("Not simulated") and not _guide_text(guide).contains("R1"))
	profile.actions.flaps_cycle = {type = "button", button = JOY_BUTTON_Y}
	context.profile = profile
	context.capabilities = {gear = true, smoke = false, flaps = true}
	context.equipment_state = {flaps = {requested = 0.4, actual = 0.1, angle_deg = 5.0, target_deg = 20.0, moving = true, overspeed = true}}
	guide.refresh(context)
	_check("available flaps show requested and actual state with motion and overspeed", _guide_text(guide).contains("Requested 40% · actual 5.0°") and _guide_text(guide).contains("Moving") and _guide_text(guide).contains("Overspeed advisory"))
	await process_frame
	guide.scroll.scroll_vertical = 100
	var scroll_before: int = guide.scroll.scroll_vertical
	context.equipment_state = {gear = "extending", smoke = "off"}
	guide.refresh(context)
	_check("live gear status updates without resetting the reader's scroll", _guide_text(guide).contains("Extending") and guide.scroll.scroll_vertical == scroll_before)
	context.capabilities = {gear = false, smoke = true, flaps = false}
	guide.refresh(context)
	_check("aircraft switch updates equipment prompts", _guide_text(guide).contains("R1") and not _guide_text(guide).contains("Circle"))
	profile.actions.smoke_toggle = {type = "unbound"}
	guide.refresh(context)
	_check("guide explains how to bind an available but cleared function", _guide_text(guide).contains("Assign in Controller settings") and not _guide_text(guide).contains("R1"))
	guide.refresh({})
	_check("disconnect returns to keyboard and disables stale device tab", guide.keyboard_button.button_pressed and guide.controller_button.disabled)
	var ui := UiDriver.new(self)
	await process_frame
	var centre: Vector2 = guide.close_button.get_global_rect().get_center()
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = centre
		click.global_position = centre
		root.get_viewport().push_input(click)
	_check("guide close preserves other overlays and takes no focus", not manager.is_overlay_visible("controls") and manager.is_overlay_visible("flight") and root.gui_get_focus_owner() == null)
	manager.set_preset("pilot")
	_check("Pilot preset reopens the guide", guide.visible)
	manager.queue_free()
	await ui.settle()


func _guide_text(guide: Control) -> String:
	var parts := PackedStringArray()
	for label: Node in guide.find_children("*", "Label", true, false):
		parts.append(label.text)
	return "\n".join(parts)


func _flight_scene() -> void:
	var flight: Node = load("res://main.tscn").instantiate()
	flight.overlays_enabled = true
	flight.overlay_settings = { preset = "full", units = "metric" }
	var saved: Array = []
	flight.overlay_settings_changed.connect(func(s: Dictionary) -> void: saved.append(s))
	root.add_child(flight)
	for i in 12:
		await process_frame
	var overlays: CanvasLayer = flight.get("_overlays")
	_check("Home route builds the overlays", overlays != null and overlays.settings.preset == "full")
	if overlays == null:
		flight.queue_free()
		return
	_check("live flight data from the session", overlays.frames.flight.values.airspeed.text.ends_with("km/h") and overlays.frames.flight.values.airspeed.text != "– km/h",
		overlays.frames.flight.values.airspeed.text)
	_check("live telemetry from the session", overlays.frames.telemetry.values.load.text.ends_with(" g"), overlays.frames.telemetry.values.load.text)
	_check("legacy diagnostics still written (capture evidence reads _hud)", (flight.get("_hud") as Label).text.begins_with("airspeed"), (flight.get("_hud") as Label).text)
	_check("transmitter footer names the keyboard", overlays.frames.transmitter.footer.text.begins_with("Keyboard"), overlays.frames.transmitter.footer.text)
	var ui := UiDriver.new(self)
	_check("Stik flight has the smoke installation", flight.get("_smoke") != null)
	var pump_before: bool = flight.get("_smoke_key_on")
	await ui.tap(KEY_F2)
	_check("F2 in flight: Full → Developer, saved", overlays.settings.preset == "developer" and saved.size() == 1)
	_check("F2 leaves the smoke pump unchanged", flight.get("_smoke_key_on") == pump_before)
	await ui.tap(KEY_H)
	_check("H toggles the Stik smoke pump without changing overlays", flight.get("_smoke_key_on") != pump_before
		and overlays.settings.preset == "developer" and saved.size() == 1)
	await ui.tap(KEY_F3)
	_check("F3 in flight hides the developer overlays", not overlays.is_overlay_visible("diagnostics") and overlays.settings.preset == "full")
	flight.set_overlays_visible(false)
	_check("a menu hides the overlays", not overlays.visible)
	flight.set_overlays_visible(true)
	_check("closing it shows them again", overlays.visible)
	flight.queue_free()
	await process_frame


func _snapshot(codes: PackedStringArray) -> Dictionary:
	return {
		telemetry = { airspeed = 20.0, ground_speed = 18.0, vertical_speed = -1.0, height_datum = 30.0, height_agl = 30.0,
			distance_pilot = 90.0, alpha_deg = 4.0, beta_deg = 0.0, heading_deg = 90.0, pitch_deg = 2.0, bank_deg = -10.0,
			load_factor = 1.1, throttle = 0.6, time_s = 65.0, wind_speed = 4.0, wind_up = 0.0, wind_from_deg = 270.0 },
		warnings = codes, view_heading_deg = 0.0, rpm = 9000.0,
		sticks = { roll = 0.2, pitch = -0.1, yaw = 0.0, throttle = 0.6 }, trims = { roll = 0.0, pitch = 0.02, yaw = 0.0 },
		radio_status = "Keyboard · Rates: full",
	}


func _shown(manager: CanvasLayer) -> Array:
	return Settings.IDS.filter(func(id: String) -> bool: return manager.frames[id].visible)


func _rects(manager: CanvasLayer) -> String:
	var parts := PackedStringArray()
	for id: String in _shown(manager):
		parts.append("%s %s" % [id, manager.frames[id].get_global_rect()])
	return "; ".join(parts)


## Every shown overlay inside the screen (1280×720 unless given); unless `overlap_allowed`, no two overlap.
func _layout_ok(manager: CanvasLayer, overlap_allowed: bool, size := Vector2(1280, 720)) -> bool:
	var screen := Rect2(Vector2.ZERO, size)
	var rects: Array = _shown(manager).map(func(id: String) -> Rect2: return manager.frames[id].get_global_rect())
	for i in rects.size():
		if not screen.encloses(rects[i]) or rects[i].size.x <= 0.0:
			return false
		if not overlap_allowed:
			for j in range(i + 1, rects.size()):
				if rects[i].intersects(rects[j]):
					return false
	return true


## Home → Fly → Pause → Flight overlays: the overlays preview above the pause menu, and hide again on close.
func _pause_preview() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	var ui := UiDriver.new(self)
	await ui.settle()
	await ui.tap(KEY_ENTER) # Fly
	await create_timer(0.4).timeout
	var overlays: CanvasLayer = app.flight.get("_overlays")
	var hints: Array[Node] = app.flight.find_children("FirstFlightHint", "", true, false)
	_check("a first Home flight shows the first-flight hint", hints.size() == 1)
	if hints.size() == 1:
		var card: Rect2 = (hints[0].find_child("Card", true, false) as Control).get_global_rect()
		var clear := Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(card)
		for id: String in _shown(overlays):
			clear = clear and not card.intersects(overlays.frames[id].get_global_rect())
		_check("the first-flight hint overlaps no Pilot overlay at 1280×720", clear, "hint %s; %s" % [card, _rects(overlays)])
	var patch: Node = app.flight.get_node_or_null("LatencyPatch")
	_check("Home flights show the default latency marker", patch != null)
	if patch != null:
		var area: Rect2 = (patch.get_child(0) as Control).get_global_rect()
		var marker_clear := Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(area)
		for id: String in _shown(overlays):
			marker_clear = marker_clear and not area.intersects(overlays.frames[id].get_global_rect())
		_check("the latency marker overlaps no Pilot overlay at 1280×720", marker_clear, "marker %s; %s" % [area, _rects(overlays)])
	await ui.tap(KEY_ESCAPE)
	_check("pause hides the overlays", overlays != null and not overlays.visible)
	app.open_overlays()
	await ui.settle()
	_check("the dialog previews the overlays above the pause menu", overlays.visible and overlays.layer > app.pause_menu.layer
		and overlays.layer < app.screens.top().layer, "overlays %d pause %d dialog %d" % [overlays.layer, app.pause_menu.layer, app.screens.top().layer])
	_check("the suspended pause column steps aside during the preview", not app.pause_menu.visible)
	await ui.tap(KEY_ESCAPE)
	_check("closing the dialog hides them again under the pause menu", app.pause_menu != null and not overlays.visible
		and overlays.layer == Manager.FLIGHT_LAYER and app.pause_menu.visible)
	_check("focus returns to the pause menu's Flight overlays button", ui.focus_name() == "Overlays", ui.focus_name())
	await ui.tap(KEY_ESCAPE) # Continue
	await ui.settle()
	_check("continue shows them at the flight layer", overlays.visible and overlays.layer == Manager.FLIGHT_LAYER)
	app.queue_free()
	await process_frame
