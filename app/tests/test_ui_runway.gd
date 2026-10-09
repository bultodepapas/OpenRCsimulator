# UI-06b: the Home runway choice, saved only after Fly succeeds, carried through restart/recovery, and isolated from
# radio navigation. Uses real key and joystick events through tests/ui_driver.gd.
# Run: godot --headless --path . --script res://tests/test_ui_runway.gd
extends SceneTree

const AppRoot := preload("res://app_root.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const Preferences := preload("res://app_state/preferences.gd")
const RB := preload("res://physics/rigid_body.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

const PREFS := "user://test_ui_runway_settings.cfg"
const FUTURE_PREFS := "user://test_ui_runway_future.cfg"
const ES_PREFS := "user://test_ui_runway_es.cfg"
const BAD_FIELD := "user://test_ui_runway_bad_field.json"
const ALT_FIELD := "user://test_ui_runway_alternate_field.json"
const RADIO_PROFILES := "user://test_ui_runway_radio.cfg"
const STIK := "jensen-das-ugly-stik-60"
const EXTRA := "gp-extra-300s-60"
const P51 := "p51d-mustang-120"
const AVANTI := "sebart-avanti-s-a200-p100rx"
const AIRBORNE := "airborne"
const RUNWAY := "runway"

var _failures: int = 0
var ui: RefCounted


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	ui = UiDriver.new(self)
	_run()


func _run() -> void:
	_preferences_cases()
	await _home_fly_roundtrip_and_radio()
	await _rejected_launch_and_retry()
	await _future_preferences_save_failure()
	await _alternate_field_and_aircraft_sanitization()
	_cleanup()
	print("all UI runway checks passed" if _failures == 0 else "%d UI runway checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _preferences_cases() -> void:
	_cleanup()
	var p: Dictionary = Preferences.load_from(PREFS)
	_check("no preferences -> airborne start", p.start_choice == AIRBORNE)

	_check("write old preferences without a start choice", _write_preferences(PREFS, 1, "en", STIK, AIRBORNE, false) == OK)
	p = Preferences.load_from(PREFS)
	_check("old schema-1 preferences without start choice -> airborne", p.start_choice == AIRBORNE)

	for invalid: Variant in ["taxi", 7, true]:
		var cfg: ConfigFile = ConfigFile.new()
		cfg.set_value("meta", "schema", 1)
		cfg.set_value("flight", "aircraft", STIK)
		cfg.set_value("flight", "start_choice", invalid)
		_check("write invalid start preference %s" % str(invalid), cfg.save(PREFS) == OK)
		_check("invalid start preference %s -> airborne" % str(invalid), Preferences.load_from(PREFS).start_choice == AIRBORNE)

	_check("runway preference is valid for the Stik", _write_preferences(PREFS, 1, "en", STIK, RUNWAY) == OK
		and Preferences.load_from(PREFS).start_choice == RUNWAY)
	_check("runway preference for the Extra is sanitized", _write_preferences(PREFS, 1, "en", EXTRA, RUNWAY) == OK
		and Preferences.load_from(PREFS).start_choice == AIRBORNE)

	var future_text: String = "[meta]\nschema=99\n[ui]\nlanguage=\"es\"\nfirst_flight_hint_seen=true\n[flight]\naircraft=\"%s\"\nstart_choice=\"runway\"\n" % STIK
	_write_text(FUTURE_PREFS, future_text)
	p = Preferences.load_from(FUTURE_PREFS)
	_check("future schema reads a valid runway choice and stays read-only", p.start_choice == RUNWAY and not p.writable, p.note)
	_check("future schema refuses save without changing its bytes", Preferences.save_to(FUTURE_PREFS, p) != OK
		and FileAccess.get_file_as_string(FUTURE_PREFS) == future_text)
	_check("save failure is reported for a path below an existing file",
		Preferences.save_to(PREFS + "/child.cfg", Preferences.DEFAULTS) != OK)


func _home_fly_roundtrip_and_radio() -> void:
	_cleanup()
	TranslationServer.set_locale("en")
	_check("seed preferences with the first-flight hint suppressed", _write_preferences(PREFS, 1, "en", STIK, AIRBORNE) == OK)
	var app: Node = await _new_app(PREFS)
	var home: Control = app.get("home") as Control
	var start_button: Button = home.get("start_button") as Button
	var before_choice: String = FileAccess.get_file_as_string(PREFS)
	_check("Home defaults to air; the Stik can choose runway", home.get("start_choice") == AIRBORNE and not start_button.disabled)
	_check("Home starts focused on Fly", ui.focus_name() == "Fly", ui.focus_name())

	# The selector sits directly above Fly in the real keyboard path.
	await ui.tap(KEY_UP)
	_check("Up from Fly focuses the start selector", ui.focus_name() == "StartChoice", ui.focus_name())
	await ui.tap(KEY_ENTER)
	_check("a real Enter event selects runway", home.get("start_choice") == RUNWAY)
	_check("changing start choice does not save it", FileAccess.get_file_as_string(PREFS) == before_choice)

	# Joypad axes are flight inputs only; they cannot navigate or change Home.
	await ui.joy_axis(JOY_AXIS_LEFT_Y, 1.0)
	_check("radio axis cannot navigate Home or change the start", ui.focus_name() == "StartChoice" and home.get("start_choice") == RUNWAY)
	await ui.joy_axis(JOY_AXIS_LEFT_Y, 0.0)

	# Leaving the supported aircraft sanitizes the visible and stored choice. Returning to the Stik does not resurrect it.
	app.call("set_aircraft", EXTRA)
	await ui.settle()
	_check("Extra disables runway and sanitizes the selected choice", home.get("aircraft_id") == EXTRA
		and home.get("start_choice") == AIRBORNE and start_button.disabled)
	_check("aircraft change persists the sanitized start", Preferences.load_from(PREFS).start_choice == AIRBORNE)
	app.call("set_aircraft", STIK)
	await ui.settle()
	_check("returning to Stik does not restore unsupported runway", home.get("start_choice") == AIRBORNE and not start_button.disabled)
	var sanitized_settings: String = FileAccess.get_file_as_string(PREFS)

	start_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("runway can be selected again on the supported Stik", home.get("start_choice") == RUNWAY)
	_check("selection is still not persisted before Fly", Preferences.load_from(PREFS).start_choice == AIRBORNE
		and FileAccess.get_file_as_string(PREFS) == sanitized_settings)
	await ui.tap(KEY_DOWN)
	_check("Down from the selector returns focus to Fly", ui.focus_name() == "Fly", ui.focus_name())
	await ui.tap(KEY_ENTER)
	await ui.settle()
	var flight: Node = app.get("flight") as Node
	_check("Fly creates one flight and removes Home", flight != null and app.get("home") == null and _sessions(root) == 1)
	if flight == null:
		await _close_app(app)
		return
	_check("Fly saves the selected runway choice", Preferences.load_from(PREFS).start_choice == RUNWAY)
	_check("main and session receive the selected choice", flight.get("start_choice") == RUNWAY
		and flight.get("session").get("start_choice") == RUNWAY)
	var session: Node = flight.get("session") as Node
	_check("runway launch succeeded without fallback", session.get("start_error") == "" and session.call("is_flyable"))
	_check("trace metadata identifies the launch choice", session.call("trace_meta").get("selected_start_choice") == RUNWAY
		and session.call("trace_meta").get("launch_choice") == RUNWAY)

	# R and Pause > Restart both reconstruct the selected runway condition.
	await ui.tap(KEY_R)
	_check("R restarts on runway", session.get("start_choice") == RUNWAY and session.get("start_error") == ""
		and session.call("trace_meta").get("launch_choice") == RUNWAY)
	app.call("open_pause")
	await ui.settle()
	await ui.tap(KEY_DOWN)
	_check("pause navigation reaches Restart", ui.focus_name() == "Restart", ui.focus_name())
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("Pause Restart retains runway", app.get("pause_menu") == null and session.get("start_choice") == RUNWAY
		and not session.get("sim").get("paused"))

	# Trigger a real ground crash, then shorten only its hold to one tick so recovery remains quick and deterministic.
	var sim: Node = session.get("sim") as Node
	var impact: PackedFloat64Array = sim.get("state").duplicate()
	impact[RB.POS + 2] = 0.1
	sim.set("state", impact)
	sim.set("previous", impact.duplicate())
	await _physics_frames(4)
	_check("ground contact enters the crash hold", not session.get("crash").is_empty())
	if not session.get("crash").is_empty():
		var crash: Dictionary = session.get("crash")
		crash.ticks_left = 1
		session.set("crash", crash)
		await _physics_frames(2)
	_check("crash recovery restarts on runway", session.get("crash").is_empty() and session.get("start_choice") == RUNWAY
			and session.get("start_error") == "" and session.call("trace_meta").get("launch_choice") == RUNWAY)

	# End through the real pause-menu buttons, return to Home, then launch the remembered runway choice again.
	app.call("open_pause")
	await ui.settle()
	for i in 3:
		await ui.tap(KEY_DOWN)
	_check("pause navigation reaches End", ui.focus_name() == "End", ui.focus_name())
	await ui.tap(KEY_ENTER)
	await ui.settle()
	home = app.get("home") as Control
	_check("flight -> Home preserves runway and saves no active session", app.get("flight") == null
		and home != null and home.get("start_choice") == RUNWAY and _sessions(root) == 0)
	_check("Home focus returns to Fly", ui.focus_name() == "Fly", ui.focus_name())
	await ui.joy_axis(JOY_AXIS_LEFT_Y, 1.0)
	_check("fake radio still cannot move Home focus or selection", ui.focus_name() == "Fly" and home.get("start_choice") == RUNWAY)
	await ui.joy_axis(JOY_AXIS_LEFT_Y, 0.0)
	await ui.tap(KEY_ENTER)
	await ui.settle()
	flight = app.get("flight") as Node
	_check("Home -> flight again uses runway", flight != null and flight.get("session").get("start_choice") == RUNWAY)
	if flight != null:
		await _fly_with_fake_radio(flight)
		app.call("open_pause")
		await ui.settle()
		app.call("end_flight")
		await ui.settle()
		_check("manual radio flight can end back at Home", app.get("flight") == null and app.get("home") != null)
	await _close_app(app)


func _fly_with_fake_radio(flight: Node) -> void:
	var session: Node = flight.get("session") as Node
	var device_info: Callable = func(_device: int) -> Dictionary:
		return { "guid": "ui-runway-fake", "name": "Fake EdgeTX", "vendor_id": 0x1209, "product_id": 0x4f54 }
	session.set("device_info", device_info)
	session.set("profiles_path", RADIO_PROFILES)
	Input.joy_connection_changed.emit(UiDriver.FAKE_DEVICE, true)
	await _physics_frames(4)
	_check("fake radio connects while preserving runway launch", session.get("radio").get("connected")
		and session.get("start_choice") == RUNWAY)
	await ui.joy_axis(JOY_AXIS_RIGHT_X, -1.0) # EdgeTX AETR throttle is axis 2.
	await _physics_frames(4)
	_check("fake radio throttle low arms the transmitter", session.get("radio").get("armed"))
	await ui.joy_axis(JOY_AXIS_LEFT_X, 0.65) # EdgeTX AETR roll is axis 0.
	await _physics_frames(4)
	var trims: Dictionary = session.get("trims")
	var flown: Dictionary = session.call("flown_commands")
	var expected_roll: float = clampf(0.65 + float(trims.roll), -1.0, 1.0)
	_check("radio roll reaches flight controls with solved trim", is_equal_approx(float(session.get("commands").roll), 0.65)
		and is_equal_approx(float(flown.roll), expected_roll)
		and is_equal_approx(float(session.get("sim").get("inputs")[0]), expected_roll),
		"commands=%s trims=%s flown=%s inputs=%s" % [session.get("commands"), trims, flown, session.get("sim").get("inputs")])
	await ui.joy_axis(JOY_AXIS_RIGHT_X, 1.0)
	await _physics_frames(4)
	_check("radio throttle reaches full power after arming", is_equal_approx(float(session.get("commands").throttle), 1.0))
	await ui.tap(KEY_P)
	await _physics_frames(4)
	_check("P resumes a manually controlled runway flight", not session.get("sim").get("paused")
		and session.get("sim").get("tick") > 0)
	Input.joy_connection_changed.emit(UiDriver.FAKE_DEVICE, false)
	await _physics_frames(2)


func _rejected_launch_and_retry() -> void:
	_cleanup()
	_check("write Spanish airborne preferences", _write_preferences(ES_PREFS, 1, "es", STIK, AIRBORNE) == OK)
	var before: String = FileAccess.get_file_as_string(ES_PREFS)
	_write_text(BAD_FIELD, "not a field file")
	TranslationServer.set_locale("en")
	var app: Node = await _new_app(ES_PREFS)
	var home: Control = app.get("home") as Control
	_check("saved Spanish Home defaults to airborne", TranslationServer.get_locale() == "es" and home.get("start_choice") == AIRBORNE)
	home.get("fly_button").grab_focus()
	await ui.tap(KEY_UP)
	_check("Spanish Home focuses the start selector", ui.focus_name() == "StartChoice", ui.focus_name())
	await ui.tap(KEY_ENTER)
	_check("real Spanish Home event selects runway without saving", home.get("start_choice") == RUNWAY
		and FileAccess.get_file_as_string(ES_PREFS) == before)
	app.set("field_path", BAD_FIELD) # Home was built from the valid default field; only this launch is rejected.
	await ui.tap(KEY_DOWN)
	_check("Down returns focus to Fly after choosing runway", ui.focus_name() == "Fly", ui.focus_name())
	await ui.tap(KEY_ENTER)
	await ui.settle()
	home = app.get("home") as Control
	_check("rejected runway launch leaves Home active and no session behind", app.get("flight") == null
		and home != null and home.is_inside_tree() and _sessions(root) == 0)
	_check("rejection clears Fly latch and keeps Fly usable", not home.get("fly_button").disabled
		and home.get("_fly_sent") == false and ui.focus_name() == "Fly")
	_check("rejection displays a Spanish reason", home.get("note_label").text.begins_with("No se pudo iniciar el vuelo: ")
		and home.get("note_label").visible, home.get("note_label").text)
	_check("rejected start does not save or overwrite the preference file", FileAccess.get_file_as_string(ES_PREFS) == before)

	app.set("field_path", FieldLoader.DEFAULT_PATH)
	home.get("fly_button").grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	var flight: Node = app.get("flight") as Node
	_check("Fly can be retried after rejection", flight != null and app.get("home") == null)
	if flight != null:
		_check("retry starts the selected runway choice", flight.get("session").get("start_choice") == RUNWAY
			and flight.get("session").get("start_error") == "")
		app.call("open_pause")
		await ui.settle()
		app.call("end_flight")
		await ui.settle()
	await _close_app(app)


func _future_preferences_save_failure() -> void:
	_cleanup()
	var future_text: String = "[meta]\nschema=99\n[ui]\nlanguage=\"es\"\nfirst_flight_hint_seen=true\n[flight]\naircraft=\"%s\"\nstart_choice=\"runway\"\n" % STIK
	_write_text(FUTURE_PREFS, future_text)
	var app: Node = await _new_app(FUTURE_PREFS)
	var home: Control = app.get("home") as Control
	_check("future preferences still show valid runway choice", home.get("start_choice") == RUNWAY)
	home.get("fly_button").grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	var flight: Node = app.get("flight") as Node
	_check("future-schema settings do not block the flight", flight != null and flight.get("session").get("start_choice") == RUNWAY)
	if flight != null:
		_check("failed save reason stays on the flight", str(flight.get("_note")).contains("No se pudieron guardar los ajustes"), str(flight.get("_note")))
		app.call("open_pause")
		await ui.settle()
		app.call("end_flight")
		await ui.settle()
		home = app.get("home") as Control
		_check("failed save reason remains visible on returned Home", home.get("note_label").visible
			and "No se pudieron guardar los ajustes" in home.get("note_label").text, home.get("note_label").text)
	_check("future preference bytes are preserved after failed save", FileAccess.get_file_as_string(FUTURE_PREFS) == future_text)
	await _close_app(app)


func _alternate_field_and_aircraft_sanitization() -> void:
	_cleanup()
	var field_text: String = FileAccess.get_file_as_string(FieldLoader.DEFAULT_PATH)
	_write_text(ALT_FIELD, field_text.replace("\"id\": \"default\"", "\"id\": \"alternate\""))
	var loaded: Dictionary = FieldLoader.load_from(ALT_FIELD)
	_check("alternate field fixture is valid", loaded.ok, str(loaded.errors))
	_check("write runway preference for alternate-field probe", _write_preferences(PREFS, 1, "en", STIK, RUNWAY) == OK)
	var app: Node = await _new_app(PREFS, ALT_FIELD)
	var home: Control = app.get("home") as Control
	_check("runway is disabled outside the existing default field", home.get("runway_available") == false
		and home.get("start_button").disabled and home.get("start_choice") == AIRBORNE)
	await _close_app(app)

	_cleanup()
	_check("write runway preference before aircraft sanitization", _write_preferences(PREFS, 1, "en", STIK, RUNWAY) == OK)
	app = await _new_app(PREFS)
	home = app.get("home") as Control
	for unsupported_aircraft: String in [EXTRA, P51, AVANTI]:
		app.call("set_aircraft", unsupported_aircraft)
		await ui.settle()
		_check("changing to %s sanitizes runway" % unsupported_aircraft, home.get("aircraft_id") == unsupported_aircraft
			and home.get("start_choice") == AIRBORNE and home.get("start_button").disabled
			and Preferences.load_from(PREFS).start_choice == AIRBORNE)
	app.call("set_aircraft", STIK)
	await ui.settle()
	_check("switching back to the Stik does not restore runway", home.get("start_choice") == AIRBORNE
		and not home.get("start_button").disabled)
	await _close_app(app)


func _new_app(preferences_path: String, field_path: String = FieldLoader.DEFAULT_PATH) -> Node:
	var app: Node = load("res://app_root.tscn").instantiate()
	app.set("user_args", PackedStringArray())
	app.set("preferences_path", preferences_path)
	app.set("field_path", field_path)
	root.add_child(app)
	await ui.settle()
	return app


func _close_app(app: Node) -> void:
	if app != null and is_instance_valid(app):
		app.queue_free()
	await process_frame
	await process_frame


func _write_preferences(path: String, schema: int, language: String, aircraft: String, start_choice: String,
		include_start: bool = true) -> Error:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("meta", "schema", schema)
	cfg.set_value("ui", "language", language)
	cfg.set_value("ui", "first_flight_hint_seen", true)
	cfg.set_value("flight", "aircraft", aircraft)
	if include_start:
		cfg.set_value("flight", "start_choice", start_choice)
	return cfg.save(path)


func _write_text(path: String, value: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check("open fixture %s" % path, false, error_string(FileAccess.get_open_error()))
		return
	file.store_string(value)
	file.close()


func _physics_frames(count: int) -> void:
	for i in count:
		await physics_frame
	await process_frame
	await process_frame


func _sessions(node: Node) -> int:
	var count: int = 0
	for child: Node in node.find_children("*", "Node", true, false):
		if child.get_script() == preload("res://sim/flight_session.gd"):
			count += 1
	return count


func _cleanup() -> void:
	for path in [PREFS, PREFS + ".bad", FUTURE_PREFS, ES_PREFS, BAD_FIELD, ALT_FIELD, RADIO_PROFILES]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
