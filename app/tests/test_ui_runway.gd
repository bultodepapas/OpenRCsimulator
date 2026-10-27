# UI-06b: the Home runway choice, saved only after Fly succeeds, carried through restart/recovery, and isolated from
# radio navigation. Uses real key and joystick events through tests/ui_driver.gd.
# Run: godot --headless --path . --script res://tests/test_ui_runway.gd
extends SceneTree

const AppRoot := preload("res://app_root.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const Preferences := preload("res://app_state/preferences.gd")
const ControllerService := preload("res://input/controller_service.gd")
const RB := preload("res://physics/rigid_body.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

const PREFS := "user://test_ui_runway_settings.cfg"
const FUTURE_PREFS := "user://test_ui_runway_future.cfg"
const ES_PREFS := "user://test_ui_runway_es.cfg"
const BAD_FIELD := "user://test_ui_runway_bad_field.json"
const ALT_FIELD := "user://test_ui_runway_alternate_field.json"
const RADIO_PROFILES := "user://test_ui_runway_radio.cfg"
const STIK := "jensen-das-ugly-stik-60"
const TIMBER := "turbo-lumber-evolution"
const EXTRA := "gp-extra-300s-60"
const P51 := "p51d-mustang-120"
const AVANTI := "sebart-avanti-s-a200-p100rx"
const AIRBORNE := "airborne"
const RUNWAY := "runway"
const HAND_LAUNCH := "hand_launch"
const X8 := "skywalker-x8"

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
	await _trimmed_airborne_roundtrip()
	await _rejected_launch_and_retry()
	await _future_preferences_save_failure()
	await _alternate_field_and_aircraft_sanitization()
	_cleanup()
	print("all UI runway checks passed" if _failures == 0 else "%d UI runway checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _preferences_cases() -> void:
	_cleanup()
	var p: Dictionary = Preferences.load_from(PREFS)
	_check("no preferences -> runway start", p.start_choice == RUNWAY)

	_check("write old preferences without a start choice", _write_preferences(PREFS, 1, "en", STIK, AIRBORNE, false) == OK)
	p = Preferences.load_from(PREFS)
	_check("old schema-1 preferences without start choice -> current runway default", p.start_choice == RUNWAY)

	for invalid: Variant in ["taxi", 7, true]:
		var cfg: ConfigFile = ConfigFile.new()
		cfg.set_value("meta", "schema", 1)
		cfg.set_value("flight", "aircraft", STIK)
		cfg.set_value("flight", "start_choice", invalid)
		_check("write invalid start preference %s" % str(invalid), cfg.save(PREFS) == OK)
		_check("invalid start preference %s -> runway" % str(invalid), Preferences.load_from(PREFS).start_choice == RUNWAY)

	_check("runway preference is valid for the Stik", _write_preferences(PREFS, 1, "en", STIK, RUNWAY) == OK
		and Preferences.load_from(PREFS).start_choice == RUNWAY)
	_check("runway preference is valid for qualified Lumber", _write_preferences(PREFS, 1, "en", TIMBER, RUNWAY) == OK
		and Preferences.load_from(PREFS).aircraft == TIMBER and Preferences.load_from(PREFS).start_choice == RUNWAY)
	_check("runway preference is valid for qualified Vantage Jet", _write_preferences(PREFS, 1, "en", AVANTI, RUNWAY) == OK
		and Preferences.load_from(PREFS).aircraft == AVANTI and Preferences.load_from(PREFS).start_choice == RUNWAY)
	for id in Catalog.airplane_flyable_ids():
		# X8-07: an airplane without landing gear defaults to the hand launch.
		var default_start: String = RUNWAY if Catalog.runway_supported(id) else HAND_LAUNCH if Catalog.hand_launch_supported(id) else AIRBORNE
		_check("%s defaults to %s with no saved start" % [id, default_start], _write_preferences(PREFS, 1, "en", id, AIRBORNE, false) == OK
			and Preferences.load_from(PREFS).start_choice == default_start)
		_check("%s retains explicit airborne preference" % id, _write_preferences(PREFS, 1, "en", id, AIRBORNE) == OK
			and Preferences.load_from(PREFS).start_choice == AIRBORNE)
	_check("hand-launch preference is valid for the gearless X8", _write_preferences(PREFS, 1, "en", X8, HAND_LAUNCH) == OK
		and Preferences.load_from(PREFS).aircraft == X8 and Preferences.load_from(PREFS).start_choice == HAND_LAUNCH)
	_check("hand-launch preference falls back to the runway default for the Stik", _write_preferences(PREFS, 1, "en", STIK, HAND_LAUNCH) == OK
		and Preferences.load_from(PREFS).start_choice == RUNWAY)
	_check("runway preference falls back to the hand-launch default for the X8", _write_preferences(PREFS, 1, "en", X8, RUNWAY) == OK
		and Preferences.load_from(PREFS).start_choice == HAND_LAUNCH)

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
	_check("Home restores explicit airborne preference", home.get("start_choice") == AIRBORNE and not start_button.disabled)
	_check("Home starts focused on Fly", ui.focus_name() == "Fly", ui.focus_name())

	# The selector sits directly above Fly in the real keyboard path.
	await ui.tap(KEY_UP)
	_check("Up from Fly focuses the start selector", ui.focus_name() == "StartChoice", ui.focus_name())
	await ui.tap(KEY_ENTER)
	_check("a real Enter event selects runway", home.get("start_choice") == RUNWAY)
	_check("runway caption names the 50 % trim (D6e-R4)", home.get("limits_label").text.contains("50% throttle"))
	_check("changing start choice does not save it", FileAccess.get_file_as_string(PREFS) == before_choice)

	# Joypad axes are flight inputs only; they cannot navigate or change Home.
	await ui.joy_axis(JOY_AXIS_LEFT_Y, 1.0)
	_check("radio axis cannot navigate Home or change the start", ui.focus_name() == "StartChoice" and home.get("start_choice") == RUNWAY)
	await ui.joy_axis(JOY_AXIS_LEFT_Y, 0.0)

	# Changing aircraft retains the runway selection throughout the fleet.
	app.call("set_aircraft", EXTRA)
	await ui.settle()
	_check("Extra keeps runway available and selected", home.get("aircraft_id") == EXTRA
		and home.get("start_choice") == RUNWAY and not start_button.disabled)
	_check("aircraft change retains the saved start until Fly", Preferences.load_from(PREFS).start_choice == AIRBORNE)
	app.call("set_aircraft", STIK)
	await ui.settle()
	_check("returning to Stik keeps runway", home.get("start_choice") == RUNWAY and not start_button.disabled)
	var sanitized_settings: String = FileAccess.get_file_as_string(PREFS)

	start_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("runway cycles to the secondary airborne choice", home.get("start_choice") == AIRBORNE)
	_check("airborne caption describes the trimmed level start", home.get("start_button").text == "Start: in the air"
		and home.get("limits_label").text.contains("Trim stays fixed"))
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
	_check("D6e-R4: the Home runway launch carries the 50 % cruise trim", flight.get("trim_throttle") == 0.5
		and session.get("trim_throttle") == 0.5 and absf(float(session.get("start").get("requested_throttle", NAN)) - 0.5) < 1e-12
		and session.get("trims").pitch == session.get("start").pitch_command
		and session.call("trace_meta").get("launch_trim_throttle") == "0.5")
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

	# CR-22a: a real ground crash persists, then R reconstructs the selected runway start.
	var sim: Node = session.get("sim") as Node
	var impact: PackedFloat64Array = sim.get("state").duplicate()
	impact[RB.POS + 2] = 0.1
	sim.set("state", impact)
	sim.set("previous", impact.duplicate())
	await _physics_frames(4)
	_check("ground contact enters the crash hold", not session.get("crash").is_empty())
	await ui.tap(KEY_R)
	await _physics_frames(2)
	_check("crash recovery restarts on runway", session.get("crash").is_empty() and session.get("start_choice") == RUNWAY
			and session.get("start_error") == "" and session.call("trace_meta").get("launch_choice") == RUNWAY)

	# End through the real pause-menu buttons, return to Home, then launch the remembered runway choice again.
	app.call("open_pause")
	await ui.settle()
	for i in 12: # Other menu tracks may add actions; still reach End through real key events.
		if ui.focus_name() == "End":
			break
		if ui.focus_name() == "ExitOptions":
			await ui.tap(KEY_ENTER)
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


func _trimmed_airborne_roundtrip() -> void:
	# D6e-R4: the former explicit "50% throttle" choice is Home's airborne start, and every Home launch is trimmed for it.
	_cleanup()
	TranslationServer.set_locale("en")
	_write_preferences(PREFS, 1, "en", STIK, RUNWAY)
	var app: Node = await _new_app(PREFS)
	var home: Control = app.home
	home.start_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("runway cycles to airborne", home.start_choice == AIRBORNE)
	_check("airborne label explains the fixed 50 % trim", home.start_button.text == "Start: in the air"
		and home.limits_label.text.contains("50% throttle") and home.limits_label.text.contains("Trim stays fixed"))
	await ui.tap(KEY_ENTER)
	_check("the airplane cycle has two choices", home.start_choice == RUNWAY)
	await ui.tap(KEY_ENTER)
	_check("new choice is not saved before Fly", home.start_choice == AIRBORNE and Preferences.load_from(PREFS).start_choice == RUNWAY)
	app.start_flight()
	await ui.settle()
	_check("airborne Home launch succeeds", app.flight != null and app.flight.startup_error.is_empty())
	if app.flight != null:
		var s: Node = app.flight.session
		_check("main installs the 50 % equilibrium before flight", s.start_choice == AIRBORNE and s.trim_throttle == 0.5
			and absf(s.start.throttle - 0.5) < 1e-7 and s.start.V > 15.0 and absf(s.commands.throttle - 0.5) < 1e-7)
		_check("new choice persists after successful Fly", Preferences.load_from(PREFS).start_choice == AIRBORNE)
		_check("trace records the airborne launch and its trim throttle",
			s.trace_meta().selected_start_choice == AIRBORNE and s.trace_meta().launch_choice == "airborne"
			and s.trace_meta().launch_trim_throttle == "0.5")
		await ui.tap(KEY_R)
		_check("restart retains the 50 % trim", s.is_flyable() and absf(s.start.throttle - 0.5) < 1e-7)
		app.open_pause()
		await ui.settle()
		app.end_flight()
		await ui.settle()
		_check("return to Home preserves the airborne choice", app.home.start_choice == AIRBORNE)
		app.set_aircraft(TIMBER)
		await ui.settle()
		_check("changing airplane keeps the airborne choice", app.home.start_choice == AIRBORNE
			and Preferences.load_from(PREFS).start_choice == AIRBORNE)
	await _close_app(app)
	# A settings file from before D6e-R4 may still hold the explicit half-power choice: it is the same launch.
	_cleanup()
	_write_preferences(PREFS, 1, "en", STIK, "airborne_half_power")
	var legacy_app: Node = await _new_app(PREFS)
	_check("a saved half-power preference is shown as the airborne start", legacy_app.home.start_choice == AIRBORNE
		and legacy_app.home.start_button.text == "Start: in the air")
	legacy_app.start_flight()
	await ui.settle()
	if legacy_app.flight != null:
		var legacy_session: Node = legacy_app.flight.session
		_check("the legacy preference flies the trimmed airborne start and is saved as airborne",
			legacy_session.start_choice == AIRBORNE and absf(legacy_session.start.throttle - 0.5) < 1e-7
			and Preferences.load_from(PREFS).start_choice == AIRBORNE)
	else:
		_check("legacy half-power preference launches", false, legacy_app.flight_error if "flight_error" in legacy_app else "")
	await _close_app(legacy_app)


func _fly_with_fake_radio(flight: Node) -> void:
	var session: Node = flight.get("session") as Node
	var app: Node = flight.get_parent()
	var controllers: Node = app.get("controllers") as Node
	controllers.set("store", ControllerService.Store.new(RADIO_PROFILES + ".controllers", RADIO_PROFILES + ".legacy"))
	var info: Dictionary = {"id": UiDriver.FAKE_DEVICE, "guid": "ui-runway-fake", "name": "Fake EdgeTX",
		"vendor_id": 0x1209, "product_id": 0x4f54, "known": false, "kind": "radio",
		"platform": "test", "backend": "ui-driver"}
	controllers.set("enumerate_devices", func() -> Array: return [info.duplicate(true)])
	controllers.call("refresh")
	_check("fake radio is registered without implicit flight selection",
		controllers.get("registry").call("selected_device_id", "flight") == -1)
	_check("fake radio can be explicitly selected for flight", controllers.call("select_devices", UiDriver.FAKE_DEVICE, -1))
	# The fake device has no OS-backed axis state. Keep the real parsed event samples
	# as the reader source so each poll does not overwrite them with zeros.
	session.set("read_axis", func(_device: int, axis: int) -> float:
		return float(session.get("radio").get("axes")[axis]))
	await _physics_frames(4)
	_check("selected fake radio connects while preserving runway launch", session.get("radio").get("connected")
		and session.get("start_choice") == RUNWAY)
	await ui.joy_axis(JOY_AXIS_RIGHT_X, -1.0) # EdgeTX AETR throttle is axis 2.
	await _physics_frames(4)
	_check("fake radio throttle low arms the transmitter", session.get("radio").get("armed"))
	await ui.tap(KEY_P)
	await _physics_frames(4)
	_check("P resumes after the selected radio is armed", not session.get("sim").get("paused")
		and session.get("sim").get("tick") > 0)
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
	_check("keyboard can be explicitly selected after the fake radio flight", controllers.call("select_devices", -1, -1))
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
	await ui.tap(KEY_ENTER) # D6e-R4: the airplane cycle is runway ⇄ in the air
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
		and home.get("start_choice") == AIRBORNE)
	_check("alternate field offers the airborne start only, trimmed like every launch (D6e-R4)",
		home.get("start_button").disabled and home.get("start_button").text == "Start: in the air")
	await _close_app(app)

	_cleanup()
	_check("write runway preference before aircraft sanitization", _write_preferences(PREFS, 1, "en", STIK, RUNWAY) == OK)
	app = await _new_app(PREFS)
	home = app.get("home") as Control
	for aircraft: String in Catalog.airplane_flyable_ids():
		app.call("set_aircraft", aircraft)
		await ui.settle()
		if not Catalog.runway_supported(aircraft):
			# X8-07: a gearless airplane shows the hand launch where others show the runway, and the airborne start second.
			_check("changing to %s shows the hand launch" % aircraft, home.get("aircraft_id") == aircraft
				and home.get("start_choice") == HAND_LAUNCH and not home.get("start_button").disabled
				and home.get("start_button").text == "Start: hand launch" and Preferences.load_from(PREFS).start_choice == HAND_LAUNCH)
			home.get("start_button").grab_focus()
			await ui.tap(KEY_ENTER)
			_check("%s offers airborne as the secondary choice" % aircraft, home.get("start_choice") == AIRBORNE
				and home.get("start_button").text == "Start: in the air")
			await ui.tap(KEY_ENTER)
			_check("%s cycles back to the hand launch" % aircraft, home.get("start_choice") == HAND_LAUNCH)
			app.start_flight()
			_check("%s Home Fly starts by hand at full throttle" % aircraft, app.flight != null
				and app.flight.startup_error.is_empty() and app.flight.session.trace_meta().launch_choice == HAND_LAUNCH
				and app.flight.session.trace_meta().launch_kind == "hand_launch_release"
				and app.flight.session.commands.throttle == 1.0)
			if app.flight != null:
				app.open_pause()
				app.end_flight()
				await ui.settle()
				home = app.home
			continue
		_check("changing to %s keeps runway" % aircraft, home.get("aircraft_id") == aircraft
			and home.get("start_choice") == RUNWAY and not home.get("start_button").disabled
			and Preferences.load_from(PREFS).start_choice == RUNWAY)
		app.start_flight()
		_check("%s Home Fly starts on the runway" % aircraft, app.flight != null
			and app.flight.startup_error.is_empty() and app.flight.session.trace_meta().launch_choice == RUNWAY)
		if app.flight != null:
			var flight_session: Node = app.flight.session
			flight_session.physics_enabled = false
			flight_session.sim.process_mode = Node.PROCESS_MODE_DISABLED
			_check("%s launches at idle with gear supported" % aircraft, flight_session.sim.inputs[3] == 0.0
				and Array(flight_session.gear_compressions(flight_session.sim.state)).max() > 0.0)
			app.open_pause()
			app.end_flight()
			await ui.settle()
			home = app.home
	app.call("set_aircraft", STIK)
	await ui.settle()
	_check("switching back to the Stik keeps runway", home.get("start_choice") == RUNWAY
		and not home.get("start_button").disabled)
	app.call("set_aircraft", P51)
	await ui.settle()
	_check("qualified P-51 enables the runway selector (P51-21)", home.get("aircraft_id") == P51
		and home.get("start_choice") == RUNWAY and not home.get("start_button").disabled)
	app.call("set_aircraft", TIMBER)
	await ui.settle()
	_check("qualified Lumber enables the runway selector", home.get("aircraft_id") == TIMBER
		and home.get("start_choice") == RUNWAY and not home.get("start_button").disabled)
	home.get("start_button").grab_focus()
	await ui.tap(KEY_ENTER)
	_check("Lumber offers airborne as the secondary choice", home.get("start_choice") == AIRBORNE)
	await ui.tap(KEY_ENTER)
	_check("Home can select runway for qualified Lumber", home.get("start_choice") == RUNWAY)
	await _close_app(app)

	_cleanup()
	_check("write qualified Vantage Jet runway preference", _write_preferences(PREFS, 1, "en", AVANTI, RUNWAY) == OK)
	app = await _new_app(PREFS)
	home = app.get("home") as Control
	_check("qualified Vantage Jet enables and restores the runway selector", home.get("aircraft_id") == AVANTI
		and home.get("start_choice") == RUNWAY and not home.get("start_button").disabled)
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
		await ui.close_app(app)


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
	for path in [PREFS, PREFS + ".bad", FUTURE_PREFS, ES_PREFS, BAD_FIELD, ALT_FIELD,
		RADIO_PROFILES, RADIO_PROFILES + ".controllers", RADIO_PROFILES + ".legacy"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
