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
	await _all_close_buttons()
	await _fuel()
	await _dialog()
	await _spanish_layout()
	await _controls_guide()
	await _flight_scene()
	await _pause_preview()
	await create_timer(1.0).timeout # allow the final semantic menu cue to finish and release its audio stream
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("overlay manager: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures else 0)


func _settings() -> void:
	_check("defaults: Pilot preset, units by language, Mode 2", Settings.validate(null) == Settings.DEFAULTS)
	_check("pilot preset is flight, transmitter, warnings, wind, guide, battery", Settings.DEFAULTS.visible == ["flight", "transmitter", "warnings", "wind", "controls", "battery"])
	var bad := Settings.validate({ preset = 3, visible = "all", units = "furlongs", stick_mode = 3 })
	_check("wrong types and ranges fall back to defaults", bad == Settings.DEFAULTS, str(bad))
	_check("a named preset defines the visible set", Settings.validate({ preset = "full", visible = ["performance"] }).visible == Settings.PRESETS.full)
	var custom := Settings.validate({ preset = "custom", visible = ["wind", "bogus", "flight", "wind"], units = "imperial", stick_mode = 1 })
	_check("custom keeps its own set, canonical order, no unknowns or duplicates", custom.visible == ["flight", "wind"], str(custom.visible))
	_check("custom keeps units and stick mode", custom.units == "imperial" and custom.stick_mode == 1)
	_check("a float stick mode is not an int", Settings.validate({ stick_mode = 1.0 }).stick_mode == 2)
	_check("default radio appearance is JETI", Settings.DEFAULTS.radio_model == "jeti_ds24_ii")
	_check("Radiolink is accepted; unknown appearance falls back to JETI",
		Settings.validate({ radio_model = "radiolink_t16d" }).radio_model == "radiolink_t16d"
		and Settings.validate({ radio_model = "unknown" }).radio_model == "jeti_ds24_ii")
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
	_check("danger chip text ≥ 4.5:1", UiTheme.contrast(UiTheme.TEXT, UiTheme.DANGER.pressed) >= 4.5, "%.2f" % UiTheme.contrast(UiTheme.TEXT, UiTheme.DANGER.pressed))
	_check("caution chip text ≥ 4.5:1", UiTheme.contrast(UiTheme.PANEL, UiTheme.FOCUS) >= 4.5)


func _preferences() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	_check("no file: default overlays", Preferences.load_from(PREFS).hud == Settings.DEFAULTS)
	var p := Preferences.load_from(PREFS)
	p.hud = { preset = "custom", visible = ["flight", "telemetry"], units = "si", stick_mode = 1, radio_model = "radiolink_t16d" }
	_check("save", Preferences.save_to(PREFS, p) == OK)
	_check("custom overlays and radio appearance round-trip", Preferences.load_from(PREFS).hud == p.hud)
	var cfg := ConfigFile.new()
	cfg.load(PREFS)
	cfg.set_value("hud", "units", 7)
	cfg.set_value("hud", "preset", "everything")
	cfg.set_value("hud", "radio_model", "unknown")
	cfg.save(PREFS)
	var damaged: Dictionary = Preferences.load_from(PREFS).hud
	_check("damaged [hud] values fall back per key", damaged.units == "auto" and damaged.preset == "pilot"
		and damaged.stick_mode == 1 and damaged.radio_model == "jeti_ds24_ii", str(damaged))


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
	_check("nonfinite aircraft hide the fuel reading row", not manager.frames.flight.values.fuel.visible)
	_check("two warning chips", manager.frames.warnings.chips.get_child_count() == 2)
	_check("pilot layout at 1920×1080: no overlap, all on screen", _layout_ok(manager, false, Vector2(1920, 1080)), _rects(manager))
	root.size = Vector2i(1280, 720)
	await process_frame
	_check("pilot layout: no overlap, all on a 1280×720 screen", _layout_ok(manager, false), _rects(manager))
	manager.apply({ preset = "full" }, false)
	manager.update(snap, 1.0)
	await process_frame
	_check("full layout: no overlap, all on screen", _layout_ok(manager, false), _rects(manager))
	manager.set_radio_model("radiolink_t16d")
	await process_frame
	_check("Radiolink choice updates artwork and keeps Full layout clear at 720p",
		manager.frames.transmitter.radio_model == "radiolink_t16d"
		and manager.frames.transmitter.title_label.text.begins_with("RADIOLINK T16D")
		and manager.frames.transmitter.gimbals.custom_minimum_size == Transmitter.RADIOLINK_SIZE
		and _layout_ok(manager, false), _rects(manager))
	manager.set_radio_model("jeti_ds24_ii")
	await process_frame
	_check("JETI remains selectable", manager.frames.transmitter.radio_model == "jeti_ds24_ii"
		and manager.frames.transmitter.gimbals.custom_minimum_size == Transmitter.JETI_SIZE)
	changes.clear()
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
	_check("× makes the set custom and announces it", manager.settings.preset == "custom" and changes.size() == 1 and changes[0].visible == ["flight", "transmitter", "warnings", "controls", "battery"])
	_check("× took no keyboard focus", root.get_viewport().gui_get_focus_owner() == null)
	var ui := UiDriver.new(self)
	await ui.tap(KEY_UP)
	_check("a flight key still arrives after the click", _keys_seen.has(KEY_UP), str(_keys_seen))

	manager.cycle_preset()
	_check("F2 after a custom set: Off", manager.settings.preset == "off" and _shown(manager).is_empty())
	var order: Array = []
	for i in Settings.PRESET_ORDER.size():
		manager.cycle_preset()
		order.append(manager.settings.preset)
	_check("F2 cycles Pilot → Full → Developer → Player → Instruments → Classic cockpit → Navigation → Training → Off",
		order == ["pilot", "full", "developer", "player", "instruments", "cockpit", "navigation", "training", "off"], str(order))
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
	var first_controls := { sticks = {roll = 0.1, pitch = 0.2, yaw = 0.3, throttle = 0.4} }
	var next_controls := { sticks = {roll = -0.4, pitch = -0.3, yaw = -0.2, throttle = 0.1} }
	manager.refresh_sticks(first_controls)
	var first_layout: Array = manager.frames.transmitter.get("_layout").duplicate()
	manager.set_overlay_visible("transmitter", false)
	manager.refresh_sticks(next_controls)
	_check("hidden transmitter retains its last drawing", manager.frames.transmitter.get("_layout") == first_layout)
	manager.set_overlay_visible("transmitter", true)
	manager.refresh_sticks(next_controls)
	_check("revealed transmitter immediately takes current controls", manager.frames.transmitter.get("_layout") == Transmitter.stick_layout(2, next_controls.sticks))
	manager.visible = false
	manager.refresh_sticks(first_controls)
	_check("menu-hidden transmitter skips drawing updates", manager.frames.transmitter.get("_layout") == Transmitter.stick_layout(2, next_controls.sticks))
	manager.visible = true
	manager.refresh_sticks(first_controls)
	_check("closing the menu restores current sticks", manager.frames.transmitter.get("_layout") == first_layout)
	manager.queue_free()
	probe.queue_free()
	await process_frame


## Every actual close target remains reachable with all overlays enabled at the primary resolution.
func _all_close_buttons() -> void:
	root.size = Vector2i(1920, 1080)
	var manager: CanvasLayer = Manager.new({preset = "developer"}, "en")
	root.add_child(manager)
	manager.diagnostics_panel.text = "Diagnostic input values\nChannel data\nStatus"
	manager.performance_label.text = "60 fps"
	var snap := _snapshot(PackedStringArray(["stall"]))
	manager.update(snap, 1.0)
	manager.frames.battery.visible = true # include the conditional panel's actual close target
	await process_frame
	await process_frame
	_check("diagnostics and guide are separate at 1080p", not manager.frames.diagnostics.get_global_rect().intersects(manager.frames.controls.get_global_rect()))
	for id: String in Settings.PRESETS.developer:
		var before: Array = manager.settings.visible.duplicate()
		var button: Button = manager.frames[id].close_button
		_check(id + " close target is on screen", Rect2(Vector2.ZERO, Vector2(1920, 1080)).encloses(button.get_global_rect()))
		for pressed in [true, false]:
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = pressed
			click.position = button.get_global_rect().get_center()
			click.global_position = click.position
			root.push_input(click)
		await process_frame
		before.erase(id)
		_check(id + " real click closes only its panel", not manager.frames[id].visible and manager.settings.visible == before)
		_check(id + " close keeps keyboard focus free", root.gui_get_focus_owner() == null)
		manager.set_overlay_visible(id, true)
		manager.frames.battery.visible = true
		await process_frame
		await process_frame
	manager.queue_free()
	await process_frame
	root.size = Vector2i(1280, 720)
	await process_frame


func _fuel() -> void:
	var manager: CanvasLayer = Manager.new({}, "en")
	root.add_child(manager)
	await process_frame
	var requests: Array = []
	manager.fuel_reserve_warning_requested.connect(func(sample: Dictionary) -> void: requests.append(sample))
	var snap: Dictionary = _snapshot(PackedStringArray())
	snap.mass_sample = _fuel_sample(true, true)
	manager.refresh_numbers(snap)
	_check("initial low-fuel state shows the meter without an audible crossing", manager.frames.flight.values.fuel.visible and requests.is_empty())
	_check("fuel meter reports accepted millilitres and capacity percent",
		manager.frames.flight.values.fuel.text == "1235 mL · 42 %", manager.frames.flight.values.fuel.text)
	_check("reserve provenance is visible in the fuel row tooltip",
		manager.frames.flight.values.fuel.get_parent().get_child(manager.frames.flight.values.fuel.get_index() - 1).tooltip_text
			== "Reserve: 12% (estimated reserve)")
	var above: Dictionary = _snapshot(PackedStringArray())
	above.mass_sample = _fuel_sample(false, false)
	manager.refresh_numbers(above)
	var crossing: Dictionary = _snapshot(PackedStringArray(["fuel_reserve_estimated"]))
	crossing.mass_sample = _fuel_sample(true, true)
	manager.refresh_numbers(crossing)
	_check("crossing estimated reserve requests one warning and shows the chip",
		requests.size() == 1 and requests[0].low_fuel and manager.get("_fuel_warning_player").playing and manager.frames.warnings.visible
		and WarningsBar.text_for(manager.frames.warnings.codes[0]) == "FUEL RESERVE · ESTIMATED")
	manager.refresh_numbers(crossing)
	_check("held-low samples do not repeat the audible warning", requests.size() == 1)
	above.mass_sample = _fuel_sample(false, false) # refuel above the threshold; rearm the next crossing
	manager.refresh_numbers(above)
	manager.refresh_numbers(crossing)
	_check("refuel above reserve rearms one later crossing", requests.size() == 2)
	var paused_high: Dictionary = _snapshot(PackedStringArray())
	paused_high.mass_sample = _fuel_sample(false, false)
	paused_high.paused = true
	manager.refresh_numbers(paused_high)
	var paused_low: Dictionary = _snapshot(PackedStringArray(["fuel_reserve_estimated"]))
	paused_low.mass_sample = _fuel_sample(true, true)
	paused_low.paused = true
	manager.refresh_numbers(paused_low)
	_check("crossing while paused is silent", requests.size() == 2)
	paused_low.paused = false
	manager.refresh_numbers(paused_low)
	_check("unpausing while still below reserve does not replay a missed crossing", requests.size() == 2)
	var invalid: Dictionary = _snapshot(PackedStringArray())
	invalid.mass_sample = { ok = false, finite_fuel = false }
	manager.refresh_numbers(invalid)
	_check("invalid sample hides the fuel row", not manager.frames.flight.values.fuel.visible)
	invalid.mass_sample = _fuel_sample(true, true)
	manager.refresh_numbers(invalid)
	_check("a low sample after a nonfinite interval establishes state without a false crossing", requests.size() == 2)
	invalid.mass_sample = _fuel_sample(false, false)
	manager.refresh_numbers(invalid)
	invalid.mass_sample = _fuel_sample(true, true)
	manager.refresh_numbers(invalid)
	_check("a later crossing after finite-state reinitialization still cues once", requests.size() == 3)
	_check("alert uses existing reject cue on Master and follows global game volume",
		manager.get("_fuel_warning_player").stream == Manager.FUEL_RESERVE_WARNING_STREAM
		and manager.get("_fuel_warning_player").bus == &"Master")
	manager.queue_free()
	await process_frame
	TranslationServer.set_locale("es")
	var spanish: CanvasLayer = Manager.new({}, "es")
	root.add_child(spanish)
	await process_frame
	var localized: Dictionary = _snapshot(PackedStringArray(["fuel_reserve_estimated"]))
	localized.mass_sample = _fuel_sample(true, true)
	spanish.refresh_numbers(localized)
	_check("Spanish fuel label, reserve provenance and warning chip are translated",
		spanish.frames.flight.get("_fuel_name").text == "Combustible"
		and spanish.frames.flight.values.fuel.get_parent().get_child(spanish.frames.flight.values.fuel.get_index() - 1).tooltip_text
			== "Reserva: 12% (reserva estimada)"
		and spanish.frames.warnings.chips.get_child_count() == 1
		and spanish.frames.warnings.chips.get_child(0).get_child(0).text == "RESERVA DE COMBUSTIBLE · ESTIMADA")
	spanish.queue_free()
	TranslationServer.set_locale("en")
	await process_frame


func _fuel_sample(low: bool, estimated: bool) -> Dictionary:
	return { ok = true, finite_fuel = true, volume_ml = 1234.6 if low else 2345.6,
		fill_fraction = 0.42 if low else 0.8, reserve_fraction = 0.12,
		reserve_estimated = estimated, reserve_basis = "estimated reserve" if estimated else "authored reserve",
		low_fuel = low, tick = 1, time_s = 0.01 }


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
	_check("modern, classic, navigation and training widget sections remain separate", dialog._player_grid.get_child_count() == 7
		and dialog._classic_grid.get_child_count() == Settings.CLASSIC_IDS.size()
		and dialog._navigation_grid.get_child_count() == Settings.NAVIGATION_IDS.size()
		and Settings.NAVIGATION_IDS.all(func(id: String) -> bool: return dialog.switches[id].get_parent() == dialog._navigation_grid)
		and dialog._training_grid.get_child_count() == Settings.TRAINING_IDS.size()
		and Settings.TRAINING_IDS.all(func(id: String) -> bool: return dialog.switches[id].get_parent() == dialog._training_grid))
	_check("all player widget switches have measurement and common-use tooltips", _player_tooltips_complete(dialog))
	var help_label: Label = dialog.switches.glide._make_custom_tooltip(dialog.switches.glide.tooltip_text)
	_check("long instrument help wraps inside a bounded tooltip", help_label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART
		and help_label.custom_minimum_size.x <= 520.0 and help_label.text == dialog.switches.glide.tooltip_text)
	_check("tooltip height is known before the popup is positioned", help_label.custom_minimum_size.y > 100.0
		and help_label.custom_minimum_size.y < 672.0)
	help_label.free()
	var scroll: ScrollContainer = dialog.find_child("OverlaysScroll", true, false) as ScrollContainer
	var settings_before_tabs: Dictionary = manager.settings.duplicate(true)
	var pinned_outside_scroll := (
		scroll != null and not scroll.is_ancestor_of(dialog.preset_picker)
		and not scroll.is_ancestor_of(dialog.units_picker) and not scroll.is_ancestor_of(dialog.done_button)
	)
	for tab_index in dialog.tab_bar.tab_count:
		dialog.tab_bar.current_tab = tab_index
		await process_frame
		var active_pages := 0
		for page: VBoxContainer in dialog._pages:
			if page.visible:
				active_pages += 1
		_check("overlay tab shows only its matching page", active_pages == 1 and dialog._pages[tab_index].visible)
		pinned_outside_scroll = (
			pinned_outside_scroll and dialog.preset_picker.is_visible_in_tree()
			and dialog.units_picker.is_visible_in_tree() and dialog.done_button.is_visible_in_tree()
		)
	_check("preset, units, and Done remain visible outside the scrolling page", pinned_outside_scroll)
	_check("changing sections does not change overlay settings", manager.settings == settings_before_tabs, str(manager.settings))
	dialog.tab_bar.current_tab = 2
	await process_frame
	_check("Navigation tab 2 shows navigation and training switches", dialog._pages[2].name == "NavigationPage"
		and dialog._pages[2].visible and Settings.NAVIGATION_IDS.all(
			func(id: String) -> bool: return dialog.switches[id].is_visible_in_tree())
		and Settings.TRAINING_IDS.all(func(id: String) -> bool: return dialog.switches[id].is_visible_in_tree())
		and dialog.training_action.get_parent() == dialog._pages[2]
		and dialog._training_grid.get_index() > dialog._navigation_grid.get_index()
		and not dialog.switches.telemetry.is_visible_in_tree())
	dialog.tab_bar.current_tab = 3
	await process_frame
	_check("Appearance tab 3 shows the appearance controls", dialog._pages[3].name == "AppearancePage"
		and dialog._pages[3].visible and dialog.widget_size_picker.is_visible_in_tree())
	dialog.tab_bar.current_tab = 4
	await process_frame
	_check("Other overlays tab 4 shows diagnostic switches", dialog._pages[4].name == "OtherOverlaysPage"
		and dialog._pages[4].visible and dialog.switches.telemetry.is_visible_in_tree())
	_check("selecting the new and shifted tabs leaves overlay settings unchanged", manager.settings == settings_before_tabs, str(manager.settings))
	var telemetry: CheckBox = dialog.switches.telemetry
	telemetry.grab_focus()
	await process_frame
	_check("visible overlay checkbox can take keyboard focus", root.get_viewport().gui_get_focus_owner() == telemetry)
	dialog.tab_bar.current_tab = 3
	await process_frame
	_check("hiding a focused page returns focus to its tab bar", not telemetry.is_visible_in_tree()
		and root.get_viewport().gui_get_focus_owner() == dialog.tab_bar)
	_check("a hidden overlay checkbox is removed from keyboard focus", telemetry.focus_mode == Control.FOCUS_NONE
		and root.get_viewport().gui_get_focus_owner() == dialog.tab_bar)
	dialog.tab_bar.current_tab = 0
	dialog.switches.speed.button_pressed = true
	_check("modern instrument switch applies from its page", manager.settings.preset == "custom"
		and manager.settings.visible.has("speed"))
	dialog.tab_bar.current_tab = 4
	dialog.switches.speed.button_pressed = false
	_check("hidden modern instrument switch still applies its direct signal", not manager.settings.visible.has("speed"))
	dialog.switches.telemetry.button_pressed = true
	_check("switching Telemetry on gives the Full preset", manager.settings.preset == "full" and dialog.preset_picker.selected == 2)
	dialog.units_picker.item_selected.emit(2)
	dialog.radio_picker.item_selected.emit(1)
	dialog.mode_picker.item_selected.emit(0)
	_check("units, radio and stick mode apply at once", manager.settings.units == "imperial"
		and manager.settings.radio_model == "radiolink_t16d" and manager.settings.stick_mode == 1)
	dialog.preset_picker.item_selected.emit(0)
	_check("choosing Off clears every switch", manager.settings.preset == "off" and not dialog.switches.flight.button_pressed)
	dialog.cockpit_action.pressed.emit()
	_check("Use cockpit layout selects warnings and the five classic instruments",
		manager.settings.preset == "cockpit" and manager.settings.visible == Settings.PRESETS.cockpit
		and Settings.CLASSIC_IDS.all(func(id: String) -> bool: return dialog.switches[id].button_pressed))
	dialog.switches.altimeter.button_pressed = false
	_check("a classic cockpit checkbox changes only its instrument", manager.settings.preset == "custom"
		and not manager.settings.visible.has("altimeter")
		and Settings.CLASSIC_IDS.filter(func(id: String) -> bool: return id != "altimeter").all(
			func(id: String) -> bool: return manager.settings.visible.has(id)))
	dialog.training_action.pressed.emit()
	_check("Use training layout selects the preset and its switches", manager.settings.preset == "training"
		and manager.settings.visible == Settings.PRESETS.training
		and dialog.preset_picker.selected == Settings.PRESET_ORDER.find("training")
		and Settings.TRAINING_IDS.all(func(id: String) -> bool: return dialog.switches[id].button_pressed))
	manager.set_preset("pilot")
	manager.frames.wind.close_button.pressed.emit()
	_check("external close synchronizes the dialog", not dialog.switches.wind.button_pressed and dialog.preset_picker.selected == Settings.PRESET_ORDER.size())
	await UiDriver.new(self).tap(KEY_ESCAPE)
	_check("Esc closes the dialog", closed.size() == 1)
	dialog.queue_free()
	manager.queue_free()
	await process_frame


func _player_tooltips_complete(dialog: CanvasLayer) -> bool:
	if OverlaysDialog.DESCRIPTIONS.size() != Settings.PLAYER_IDS.size():
		return false
	for id: String in Settings.PLAYER_IDS:
		if not OverlaysDialog.DESCRIPTIONS.has(id):
			return false
		var tooltip: String = str(dialog.switches[id].tooltip_text)
		if not tooltip.begins_with(str(OverlaysDialog.DESCRIPTIONS[id])) or not tooltip.contains(str(OverlaysDialog.COMMON_WIDGET_HELP)):
			return false
	return true


func _spanish_layout() -> void:
	TranslationServer.set_locale("es")
	var manager: CanvasLayer = Manager.new({}, "es")
	root.add_child(manager)
	manager.update(_snapshot(PackedStringArray(["failsafe", "safe", "far"])), 1.0)
	await process_frame
	await process_frame
	_check("Spanish: metric by language", manager.frames.flight.values.airspeed.text == "72 km/h")
	_check("Spanish pilot layout with three long warnings: no overlap at 1280×720", _layout_ok(manager, false), _rects(manager))
	var every := PackedStringArray(["failsafe", "safe", "stall", "low", "far", "battery", "fuel_reserve_estimated", "experimental"])
	var calm := _snapshot(every)
	calm.telemetry.wind_up = 0.0
	manager.refresh_numbers(calm)
	await process_frame
	await process_frame
	var wind_calm_up: Vector2 = manager.frames.wind.size
	_check("all eight Spanish warnings wrap inside the bar's width", manager.frames.warnings.chips.size.x <= WarningsBar.MAX_WIDTH + 0.5
		and manager.frames.warnings.chips.size.y > 40.0, str(manager.frames.warnings.chips.size))
	_check("seven warnings still overlap nothing at 1280×720", _layout_ok(manager, false), _rects(manager))
	var gust := _snapshot(every)
	gust.telemetry.wind_up = 1.2
	manager.refresh_numbers(gust)
	await process_frame
	await process_frame
	_check("wind box keeps its size when an updraft line appears", manager.frames.wind.size == wind_calm_up,
		"%s → %s" % [wind_calm_up, manager.frames.wind.size])
	var dialog: CanvasLayer = OverlaysDialog.new(manager)
	root.add_child(dialog)
	await process_frame
	_check("Spanish Flight tools tab is translated without moving its page", dialog.tab_bar.get_tab_title(2) == "Ayudas de vuelo"
		and dialog._pages[2].name == "NavigationPage")
	dialog.queue_free()
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
	_check("guide explains how to bind an available but cleared function", _guide_text(guide).contains("Assign in Controls") and not _guide_text(guide).contains("R1"))
	var radio := Profile.defaults("radio", "jeti_mode2")
	radio.aux = {
		smoke = {type = "switch", buttons = [81, 82, 83], invert = false, label = "Sa"},
		flaps = {type = "switch", buttons = [90, 91, 92], invert = true, label = "Sb"},
		gear = {type = "switch", buttons = [100, 101], invert = false, label = "Sc"},
	}
	var radio_before := radio.duplicate(true)
	context = {connected = true, device_name = "JETI DC/DS Radio", device_info = {kind = "radio"},
		profile = radio, capabilities = {gear = true, smoke = true, flaps = true},
		equipment_state = {gear = "extending", smoke = "on"}}
	guide.refresh(context)
	_check("maintained switch AUX appears as assigned equipment in the guide",
		guide._equipment_labels.has("smoke") and guide._equipment_labels.has("flaps") and guide._equipment_labels.has("gear")
		and not _guide_text(guide).contains("Assign in Controls"))
	_check("guide shows physical switch names and observed indices without gamepad labels",
		_guide_text(guide).contains("Sa") and _guide_text(guide).contains("Sb") and _guide_text(guide).contains("Sc")
		and _guide_text(guide).contains("81") and _guide_text(guide).contains("101")
		and not _guide_text(guide).contains("Circle"))
	_check("switch equipment retains live state and leaves the profile unchanged",
		_guide_text(guide).contains("Extending") and radio == radio_before)
	context.capabilities.gear = false
	guide.refresh(context)
	_check("switch assignment does not enable unsupported aircraft equipment",
		_guide_text(guide).contains("Not available") and not guide._equipment_labels.has("gear"))
	context.erase("capabilities")
	guide.refresh(context)
	_check("guide without capability context still describes maintained switch AUX",
		_guide_text(guide).contains("Sa") and _guide_text(guide).contains("Sb") and _guide_text(guide).contains("Sc"))
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
	await _diagnostics_visibility(flight, overlays)
	saved.clear()
	var ui := UiDriver.new(self)
	_check("Stik flight has the stock smoke profile", flight.get("_profile_smoke") != null and bool(flight.get("_stock_smoke_profile")))
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


func _diagnostics_visibility(flight: Node, overlays: CanvasLayer) -> void:
	var panel: Label = flight.get("_panel")
	var hud: Label = flight.get("_hud")
	overlays.set_preset("pilot")
	panel.text = "hidden input sentinel"
	hud.text = "hidden telemetry sentinel"
	overlays.performance_label.text = "hidden performance sentinel"
	for i in 3:
		await process_frame
	_check("hidden diagnostic labels skip formatting", panel.text == "hidden input sentinel" and hud.text == "hidden telemetry sentinel")
	_check("hidden performance skips percentile formatting", overlays.performance_label.text == "hidden performance sentinel")
	overlays.set_overlay_visible("performance", true)
	await process_frame
	await process_frame
	_check("performance can refresh independently of diagnostics", overlays.performance_label.text.contains("fps") and hud.text == "hidden telemetry sentinel")
	overlays.set_preset("developer")
	await process_frame
	await process_frame
	_check("revealed diagnostics immediately show current data", panel.text.begins_with("channel") and hud.text.begins_with("airspeed"))
	flight.set_overlays_visible(false)
	panel.text = "menu input sentinel"
	hud.text = "menu telemetry sentinel"
	await process_frame
	await process_frame
	_check("menu-hidden diagnostics skip formatting", panel.text == "menu input sentinel" and hud.text == "menu telemetry sentinel")
	flight.set_overlays_visible(true)
	await process_frame
	await process_frame
	_check("closing menu refreshes diagnostics", panel.text.begins_with("channel") and hud.text.begins_with("airspeed"))
	overlays.set_preset("pilot")
	flight._update_hud()
	_check("explicit evidence refresh still writes a hidden HUD", hud.text.begins_with("airspeed"))
	overlays.set_preset("full")


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
	_check("Home flights do not create a camera marker by default", patch == null and not Preferences.load_from(PREFS).latency_marker)
	await ui.tap(KEY_ESCAPE)
	_check("pause hides the overlays", overlays != null and not overlays.visible)
	app.pause_menu.session_options_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("Session options reveals the Flight overlays action",
		app.pause_menu.session_options_container.visible and app.pause_menu.overlays_button.is_visible_in_tree())
	app.pause_menu.overlays_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("the dialog previews the overlays above the pause menu", overlays.visible and overlays.layer > app.pause_menu.layer
		and overlays.layer < app.screens.top().layer, "overlays %d pause %d dialog %d" % [overlays.layer, app.pause_menu.layer, app.screens.top().layer])
	_check("the suspended pause column steps aside during the preview", not app.pause_menu.visible)
	var dialog: CanvasLayer = app.screens.top()
	dialog.latency_switch.button_pressed = true
	patch = app.flight.get_node_or_null("LatencyPatch")
	_check("camera marker can be enabled from the dialog and saved", patch != null and Preferences.load_from(PREFS).latency_marker)
	_check("enabling under a menu does not run hidden sampling", not patch.visible and not patch.is_physics_processing())
	await ui.tap(KEY_ESCAPE)
	_check("closing the dialog hides them again under the pause menu", app.pause_menu != null and not overlays.visible
		and overlays.layer == Manager.FLIGHT_LAYER and app.pause_menu.visible)
	_check("focus returns to the pause menu's Flight overlays button", ui.focus_name() == "Overlays", ui.focus_name())
	await ui.tap(KEY_ESCAPE) # Back first closes Session options.
	_check("Back closes Session options before returning to the flight",
		app.pause_menu != null and not app.pause_menu.session_options_container.visible)
	await ui.tap(KEY_ESCAPE) # Continue
	await ui.settle()
	_check("continue shows them at the flight layer", overlays.visible and overlays.layer == Manager.FLIGHT_LAYER)
	_check("continue shows the enabled camera marker", patch.visible and patch.is_physics_processing())
	patch.close_button.pressed.emit()
	_check("camera close saves opt-out", not patch.visible and not Preferences.load_from(PREFS).latency_marker)
	app.flight.set_overlays_visible(false)
	app.flight.set_overlays_visible(true)
	_check("closed marker stays closed after a menu", not patch.visible and not patch.is_physics_processing())
	await ui.close_app(app)
