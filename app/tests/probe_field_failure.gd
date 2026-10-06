# L5: exercise the real app_root routes against a caller-owned invalid field file.
# Environment: OPENRC_TEST_FIELD_PATH, OPENRC_TEST_MODE=home|flight, optional
# OPENRC_TEST_LANGUAGE=en|es, OPENRC_TEST_EXPECTED_DIAGNOSTIC, OPENRC_TEST_PNG_PATH.
extends SceneTree

const AppScene: PackedScene = preload("res://app_root.tscn")
const Preferences = preload("res://app_state/preferences.gd")

const PREFS_PATH: String = "user://field_failure_probe_%d.cfg"
const FLIGHT_ARGS: PackedStringArray = ["--quick-flight"]


func _initialize() -> void:
	var field_path: String = OS.get_environment("OPENRC_TEST_FIELD_PATH")
	var mode: String = OS.get_environment("OPENRC_TEST_MODE")
	var language: String = OS.get_environment("OPENRC_TEST_LANGUAGE")
	if language.is_empty():
		language = "en"
	if field_path.is_empty() or not ["home", "flight"].has(mode) or not ["en", "es"].has(language):
		_fail("set a field path, mode=home|flight and language=en|es")
		return

	var preferences_path: String = PREFS_PATH % OS.get_process_id()
	var preferences: Dictionary = Preferences.DEFAULTS.duplicate(true)
	preferences["language"] = language
	preferences["first_flight_hint_seen"] = true
	var save_error: Error = Preferences.save_to(preferences_path, preferences)
	if save_error != OK:
		_fail("could not save isolated probe preferences: %s" % error_string(save_error))
		return

	var app: Node = AppScene.instantiate()
	app.set("user_args", FLIGHT_ARGS if mode == "flight" else PackedStringArray())
	app.set("preferences_path", preferences_path)
	app.set("field_path", field_path)
	root.add_child(app)

	if DisplayServer.get_name() == "headless":
		# AppRoot enters the tree after this SceneTree script yields. The real error path must
		# request exit(1); if it returns to normal headless processing, the watchdog exits 3.
		await _headless_watchdog()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(preferences_path))
		return

	if not OS.get_cmdline_user_args().is_empty():
		_fail("interactive probe must run with no OS user arguments")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(preferences_path))
		return
	await process_frame
	await process_frame # deferred focus is applied after the error panel enters the tree
	await RenderingServer.frame_post_draw
	if not _check_expected_route(app, mode, true, language):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(preferences_path))
		quit(3)
		return
	if not _capture_if_requested():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(preferences_path))
		quit(3)
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(preferences_path))
	print("field failure probe passed: mode=%s language=%s" % [mode, language])
	quit(0)


func _check_expected_route(app: Node, mode: String, interactive: bool, language: String) -> bool:
	var ok: bool = true
	var route_parent: Node = null
	if mode == "home":
		var home_scene: Node = app.get("home_scene")
		ok = _check("HomeScene exists", home_scene != null) and ok
		ok = _check("Home controls are withheld", app.get("home") == null and app.get("flight") == null) and ok
		if home_scene != null:
			route_parent = home_scene
			var errors: PackedStringArray = home_scene.get("field_errors")
			var field: Dictionary = home_scene.get("field")
			ok = _check("HomeScene records invalid field errors", not errors.is_empty()) and ok
			ok = _check("HomeScene has no normalized field", field.is_empty()) and ok
			ok = _check("HomeScene has no camera", home_scene.get("camera") == null) and ok
	else:
		var flight: Node = app.get("flight")
		ok = _check("direct flight scene exists", flight != null) and ok
		ok = _check("direct route has no Home scene", app.get("home") == null and app.get("home_scene") == null) and ok
		if flight != null:
			route_parent = flight
			var field: Dictionary = flight.get("field")
			ok = _check("flight has no normalized field", field.is_empty()) and ok
			ok = _check("flight has no session", flight.get("session") == null) and ok
			ok = _check("flight has no camera", flight.get("_camera") == null) and ok

	if route_parent == null:
		return false
	ok = _check("invalid parent processing is disabled",
		not route_parent.is_processing() and not route_parent.is_processing_unhandled_input()) and ok
	ok = _check("no Field renderer node", _count_named(root, "Field") == 0) and ok
	ok = _check("no Camera3D", _count_type(root, "Camera3D") == 0) and ok
	ok = _check("no WorldEnvironment", _count_type(root, "WorldEnvironment") == 0) and ok
	ok = _check("no FlightSession script", _count_script(root, "res://sim/flight_session.gd") == 0) and ok

	var error_layers: Array[Node] = root.find_children("FieldError", "CanvasLayer", true, false)
	if interactive:
		ok = _check("exactly one visible FieldError panel", error_layers.size() == 1) and ok
		if error_layers.size() != 1:
			return false
		var error_layer: Node = error_layers[0]
		ok = _check("FieldError belongs to failed route", error_layer.get_parent() == route_parent) and ok
		var details: TextEdit = error_layer.find_child("Details", true, false) as TextEdit
		var quit_button: Button = error_layer.find_child("Quit", true, false) as Button
		var expected: String = OS.get_environment("OPENRC_TEST_EXPECTED_DIAGNOSTIC")
		ok = _check("diagnostic is shown in Details", details != null and (expected.is_empty() or expected in details.text)) and ok
		ok = _check("Quit button is visible and laid out", quit_button != null and quit_button.is_visible_in_tree()
			and quit_button.size.x > 0.0 and quit_button.size.y > 0.0) and ok
		ok = _check("keyboard focus starts on Quit", quit_button != null and root.get_viewport().gui_get_focus_owner() == quit_button
			and quit_button.has_focus(true)) and ok
		var displayed_language: String = "en" if mode == "flight" else language
		ok = _check("error text follows the selected language",
			_localized_text_is_visible(error_layer, displayed_language)) and ok
	else:
		ok = _check("headless route creates no interactive panel", error_layers.is_empty()) and ok
	return ok


func _localized_text_is_visible(error_layer: Node, language: String) -> bool:
	var quit_button: Button = error_layer.find_child("Quit", true, false) as Button
	var labels: Array[Node] = error_layer.find_children("*", "Label", true, false)
	if labels.size() < 2 or quit_button == null:
		return false
	var translated_title: String = ""
	var translated_explanation: String = ""
	for candidate: Node in labels:
		var label: Label = candidate as Label
		if label.text == "The field could not be loaded.":
			translated_title = label.atr(label.text)
		elif label.text == "Flight is unavailable. Restore the field data and restart the simulator.":
			translated_explanation = label.atr(label.text)
	var translated_quit: String = quit_button.atr(quit_button.text)
	print("field-error translation locale=%s title=%s explanation=%s quit=%s" % [
		TranslationServer.get_locale(), translated_title, translated_explanation, translated_quit,
	])
	if language == "es":
		var spanish: bool = translated_title == "No se pudo cargar el campo." \
			and translated_explanation == "El vuelo no está disponible. Restaura los datos del campo y reinicia el simulador." \
			and translated_quit == "Salir"
		return spanish
	var english: bool = translated_title == "The field could not be loaded." \
		and translated_explanation == "Flight is unavailable. Restore the field data and restart the simulator." \
		and translated_quit == "Quit"
	return english


func _capture_if_requested() -> bool:
	var output_path: String = OS.get_environment("OPENRC_TEST_PNG_PATH")
	if output_path.is_empty():
		return true
	var image: Image = root.get_viewport().get_texture().get_image()
	var save_error: Error = image.save_png(output_path)
	return _check("optional panel PNG saved", save_error == OK and not image.is_empty(),
		"%s (error %d)" % [output_path, save_error])


func _headless_watchdog() -> void:
	await create_timer(3.0).timeout
	printerr("FAIL invalid headless field did not exit through FieldError.report")
	quit(3)


func _count_named(parent: Node, target_name: String) -> int:
	var total: int = 0
	for child: Node in parent.get_children():
		if child.name == target_name:
			total += 1
		total += _count_named(child, target_name)
	return total


func _count_type(parent: Node, type_name: String) -> int:
	var total: int = 0
	for child: Node in parent.get_children():
		if child.is_class(type_name):
			total += 1
		total += _count_type(child, type_name)
	return total


func _count_script(parent: Node, resource_path: String) -> int:
	var total: int = 0
	for child: Node in parent.get_children():
		var script: Script = child.get_script() as Script
		if script != null and script.resource_path == resource_path:
			total += 1
		total += _count_script(child, resource_path)
	return total


func _check(label: String, condition: bool, detail: String = "") -> bool:
	if condition:
		print("ok   ", label)
		return true
	printerr("FAIL %s %s" % [label, detail])
	return false


func _fail(message: String) -> void:
	printerr("FAIL ", message)
	quit(3)
