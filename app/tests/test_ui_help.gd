# UI-04b: Help and about, from Home and from the pause menu, with real key events. Key labels follow the keyboard
# layout (an injected AZERTY / Russian mapping; headless itself has no layout and must give QWERTY names without
# an engine ERROR, which test.sh would catch).
# Run: godot --headless --path . --audio-driver Dummy --script res://tests/test_ui_help.gd
extends SceneTree

const UiDriver := preload("res://tests/ui_driver.gd")
const KeyLabels := preload("res://ui/key_labels.gd")
const KeyCap := preload("res://ui/key_cap.gd")
const Reference := preload("res://ui/controls_reference.gd")
const HelpScreen := preload("res://ui/help_screen.gd")
const Preferences := preload("res://app_state/preferences.gd")
const PREFS := "user://test_ui_help_settings.cfg"

var _failures := 0
var ui: RefCounted


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	ui = UiDriver.new(self)
	_run()


func _caps_text(n: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for cap in [n] + n.find_children("*", "PanelContainer", true, false):
		if cap is PanelContainer and cap.theme_type_variation == "KeyCap":
			var l: Array = cap.find_children("*", "Label", true, false)
			out.append(l[0].text if not l.is_empty() else "<drawn>")
	return out


func _run() -> void:
	# Key labels: the layout's printed character for a physical key, never stored state.
	var azerty := func(k: Key) -> Key: return { KEY_A: KEY_Q, KEY_Q: KEY_A, KEY_W: KEY_Z, KEY_Z: KEY_W }.get(k, k)
	var russian := func(k: Key) -> Key: return { KEY_A: 0x424 as Key, KEY_W: 0x426 as Key }.get(k, k)
	_check("headless (no layout): QWERTY names", [KeyLabels.label(KEY_A), KeyLabels.label(KEY_W), KeyLabels.label(KEY_F3)] == ["A", "W", "F3"])
	_check("AZERTY: physical A, W, Z print Q, Z, W", [KeyLabels.label(KEY_A, azerty), KeyLabels.label(KEY_W, azerty), KeyLabels.label(KEY_Z, azerty)] == ["Q", "Z", "W"])
	_check("Russian: physical A, W print Ф, Ц", [KeyLabels.label(KEY_A, russian), KeyLabels.label(KEY_W, russian)] == ["Ф", "Ц"])
	var arrow_cap := KeyCap.for_key(KEY_LEFT)
	_check("named keys get names, arrows are drawn", KeyLabels.label(KEY_ESCAPE) == "Esc" and _caps_text(arrow_cap) == PackedStringArray(["<drawn>"]))
	arrow_cap.free()
	TranslationServer.set_locale("es")
	_check("named keys are translated", KeyLabels.label(KEY_ENTER) == "Intro" and KeyLabels.label(KEY_UP) == "Flecha arriba")
	TranslationServer.set_locale("en")

	# Help from Home.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	await ui.tap(KEY_DOWN)
	await ui.tap(KEY_RIGHT)
	_check("Home: Help reachable by keyboard", ui.focus_name() == "Help", ui.focus_name())
	await ui.tap(KEY_ENTER)
	var help: CanvasLayer = app.help
	_check("Enter opens Help, focus on Close", help != null and ui.focus_name() == "Close", ui.focus_name())
	var keys := 0
	for table in [Reference.SHORTCUTS, Reference.FLIGHT]:
		for row in table:
			keys += row[0].size()
	_check("Help shows every key of the shared table (%d)" % keys, _caps_text(help).size() == keys, str(_caps_text(help)))
	_check("about: development build, Godot, licence", "development build" in help.about_label.text and "Godot 4.7" in help.about_label.text
		and "MIT" in help.about_label.text, help.about_label.text)
	var scroll: ScrollContainer = help.find_children("*", "ScrollContainer", true, false)[0]
	_check("Help scrolls to keyboard focus", scroll.follow_focus)
	var page: Control = scroll.get_child(0)
	_check("English Help fits without scrolling (%d <= %d px)" % [page.get_combined_minimum_size().y, scroll.custom_minimum_size.y],
		page.get_combined_minimum_size().y <= scroll.custom_minimum_size.y)
	await ui.tap(KEY_ESCAPE)
	_check("Esc closes Help, focus back on Help", app.help == null and ui.focus_name() == "Help", ui.focus_name())
	_check("Esc in Help did not start or quit anything", app.flight == null and app.home != null)

	# Help in Spanish: every translatable text has a translation.
	TranslationServer.set_locale("es")
	app.open_help(null)
	await ui.settle()
	var untranslated := PackedStringArray()
	for c in app.help.find_children("*", "", true, false):
		if (c is Label or c is Button) and c.can_auto_translate() and c.text != "" and c.atr(c.text) == c.text and c.text != "RADIO":
			untranslated.append(c.text)
	_check("Help: every text translated to Spanish", untranslated.is_empty(), str(untranslated))
	_check("about in Spanish", "versión de desarrollo" in app.help.about_label.text, app.help.about_label.text)
	var es_scroll: ScrollContainer = app.help.find_children("*", "ScrollContainer", true, false)[0]
	var es_page: Control = es_scroll.get_child(0)
	_check("Spanish Help fits without scrolling (%d <= %d px)" % [es_page.get_combined_minimum_size().y, es_scroll.custom_minimum_size.y],
		es_page.get_combined_minimum_size().y <= es_scroll.custom_minimum_size.y)
	app.close_help()
	TranslationServer.set_locale("en")
	await ui.settle()

	# Help from the pause menu: keys swallowed, Esc closes Help only.
	app.start_flight()
	await create_timer(0.3).timeout
	var session: Node = app.flight.session
	app.open_pause()
	await ui.settle()
	await ui.tap(KEY_DOWN)
	await ui.tap(KEY_DOWN)
	_check("pause: Help reachable", ui.focus_name() == "Help", ui.focus_name())
	await ui.tap(KEY_ENTER)
	var tick: int = session.sim.tick
	await ui.tap(KEY_R)
	await ui.tap(KEY_T)
	_check("Help over the pause menu swallows flight keys", app.help != null and session.sim.tick == tick and not app.flight.recorder.recording)
	await ui.tap(KEY_ESCAPE)
	_check("Esc closes Help, the pause menu stays", app.help == null and app.pause_menu != null and ui.focus_name() == "Help", ui.focus_name())
	await ui.tap(KEY_ESCAPE)
	_check("Esc again continues the flight", app.pause_menu == null and not session.sim.paused)

	app.queue_free()
	await process_frame

	# First-flight hint: once, three items, no keyboard focus, only flown time counts, remembered.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	app = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	await ui.tap(KEY_ENTER) # Fly
	await ui.settle()
	var hints: Array = app.flight.find_children("FirstFlightHint", "", true, false)
	_check("first flight: the hint shows, three items", hints.size() == 1 and _caps_text(hints[0]).size() == 4 + 2 + 1, str(_caps_text(hints[0]) if not hints.is_empty() else []))
	var hint: CanvasLayer = hints[0]
	_check("the hint takes no keyboard focus", root.gui_get_focus_owner() == null)
	var ev := InputEventKey.new()
	ev.keycode = KEY_RIGHT
	ev.physical_keycode = KEY_RIGHT
	ev.pressed = true
	Input.parse_input_event(ev)
	await create_timer(0.3).timeout
	_check("flight keys fly under the hint", app.flight.session.raw.roll == 1.0)
	ev = ev.duplicate()
	ev.pressed = false
	Input.parse_input_event(ev)
	hint.duration_s = 0.5
	app.open_pause()
	await create_timer(1.0).timeout
	_check("paused time does not use the hint up", hint.visible)
	app.continue_flight()
	await create_timer(0.8).timeout
	_check("after 0.5 s flown it goes and is remembered", not hint.visible and Preferences.load_from(PREFS).first_flight_hint_seen)
	app.open_pause()
	await ui.settle()
	app.end_flight()
	await ui.settle()
	await ui.tap(KEY_ENTER) # Fly again
	await ui.settle()
	_check("next flight: no hint", app.flight.find_children("FirstFlightHint", "", true, false).is_empty())
	app.queue_free()
	await process_frame
	var direct: Node = load("res://app_root.tscn").instantiate()
	direct.user_args = PackedStringArray(["--quick-flight"])
	direct.preferences_path = "user://test_ui_help_never_written.cfg"
	root.add_child(direct)
	await ui.settle()
	_check("direct route: no hint, no settings", direct.flight.find_children("FirstFlightHint", "", true, false).is_empty()
		and not FileAccess.file_exists("user://test_ui_help_never_written.cfg"))
	direct.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("all UI help checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(1 if _failures > 0 else 0)
