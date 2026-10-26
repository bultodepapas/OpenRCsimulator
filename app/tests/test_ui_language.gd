# UI-01d: English by default (whatever the OS locale), Spanish available, the choice remembered in a versioned
# settings file that automation never reads or writes. Settings files here are test-only paths under user://.
# Run: godot --headless --path . --script res://tests/test_ui_language.gd
extends SceneTree

const Preferences := preload("res://app_state/preferences.gd")
const Home := preload("res://ui/home.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const PREFS := "user://test_ui_language_settings.cfg"

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


func _run() -> void:
	_preferences_file()
	_catalog()
	await _default_and_switch()
	await _direct_route()
	for f in [PREFS, PREFS + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	print("all UI language checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _write(text: String) -> void:
	var f := FileAccess.open(PREFS, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _reset() -> void:
	for f in [PREFS, PREFS + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func _preferences_file() -> void:
	_reset()
	var p := Preferences.load_from(PREFS)
	_check("no file -> English, writable", p.language == "en" and p.writable and p.note == "")
	p.language = "es"
	_check("save", Preferences.save_to(PREFS, p) == OK)
	_check("load what was saved", Preferences.load_from(PREFS).language == "es")
	p.latency_marker = false
	_check("diagnostic marker opt-out persists", Preferences.save_to(PREFS, p) == OK
		and not Preferences.load_from(PREFS).latency_marker)
	p.latency_marker = "off"
	_check("diagnostic preference rejects the wrong type", Preferences.save_to(PREFS, p) == ERR_INVALID_DATA)
	_write("[meta]\nschema=1\n[ui]\nlanguage=\"fr\"\n")
	_check("unsupported language -> English", Preferences.load_from(PREFS).language == "en")
	_write("[meta]\nschema=1\n[ui]\nlanguage=7\n")
	_check("wrong type -> English (ConfigFile keeps the file's type)", Preferences.load_from(PREFS).language == "en")
	_write("this is not [a config file\n")
	p = Preferences.load_from(PREFS)
	_check("unreadable file -> defaults, kept as .bad", p.language == "en" and FileAccess.file_exists(PREFS + ".bad")
		and not FileAccess.file_exists(PREFS) and "kept as" in p.note, p.note)
	_reset()
	var newer := "[meta]\nschema=99\n[ui]\nlanguage=\"es\"\n"
	_write(newer)
	p = Preferences.load_from(PREFS)
	_check("newer schema: valid values read, file marked read-only", p.language == "es" and not p.writable, p.note)
	p.language = "en"
	_check("newer schema: never overwritten", Preferences.save_to(PREFS, p) != OK and FileAccess.get_file_as_string(PREFS) == newer)
	_reset()


func _catalog() -> void:
	var es: Translation = load("res://i18n/es.po")
	var empty := PackedStringArray()
	for m in es.get_message_list():
		if es.get_message(m) == "":
			empty.append(m)
	_check("Spanish catalog: %d texts, none untranslated" % es.get_message_count(), es.get_message_count() >= 10 and empty.is_empty(), str(empty))
	for code in Preferences.LANGUAGES:
		_check("language %s has a catalog or is the source" % code, code == "en" or code in TranslationServer.get_loaded_locales())


func _default_and_switch() -> void:
	TranslationServer.set_locale("es_ES") # what the engine picks by itself on a Spanish OS
	var app := _app(PackedStringArray())
	root.add_child(app)
	await ui.settle()
	var home: Control = app.home
	_check("English by default, even on a Spanish OS", TranslationServer.get_locale() == "en" and home.fly_button.atr(home.fly_button.text) == "FLY",
		TranslationServer.get_locale())
	_check("language button names the language in itself", home.language_button.text == "Language: English", home.language_button.text)

	home.language_button.grab_focus()
	_check("language control can receive keyboard focus", ui.focus_name() == "Language", ui.focus_name())
	await ui.tap(KEY_ENTER)
	_check("Enter on Language -> Spanish at once", TranslationServer.get_locale() == "es" and home.fly_button.atr(home.fly_button.text) == "VOLAR")
	_check("dynamic texts rebuilt in Spanish", home.language_button.text == "Idioma: Español" and home.control_label.text == "Control de vuelo: teclado",
		"%s | %s" % [home.language_button.text, home.control_label.text])
	_check("AUX profile errors translate", TranslationServer.translate("Could not save the updated controller profile; the existing profile is unchanged.") == "No se pudo guardar el perfil de control actualizado; el perfil existente no cambió." and TranslationServer.translate("The current controller profile could not be updated.") == "No se pudo actualizar el perfil de control actual.")
	_check("focus stays on Language", ui.focus_name() == "Language", ui.focus_name())
	var companion_summary := "Compañeros de vuelo: Ninguno · 1"
	_check("Home companion summary and detail translate", home.companions_button.text == companion_summary
		and home.companions_button.tooltip_text.begins_with("Compañeros de vuelo: Ninguno · 1 compañeros · semilla 1"),
		"%s | %s" % [home.companions_button.text, home.companions_button.tooltip_text])
	var untranslated := PackedStringArray()
	var spanish_values := {}
	var spanish_catalog: Translation = load("res://i18n/es.po")
	for source in spanish_catalog.get_message_list():
		spanish_values[spanish_catalog.get_message(source)] = true
	spanish_values[companion_summary] = true # Dynamic text was checked against its Spanish template above.
	var aircraft_history := "Historial · 0 h 00 min en el aire · 0 completados · 0 choques"
	var pilot_history := "Total del piloto · 0 h 00 min en el aire · 0 completados · mejor racha 0"
	_check("Home empty history summaries translate", home._statistics_aircraft_summary.text == aircraft_history
		and home._statistics_pilot_summary.text == pilot_history)
	spanish_values[aircraft_history] = true
	spanish_values[pilot_history] = true
	for c in home.find_children("*", "", true, false):
		if (c is Label or c is Button) and c.can_auto_translate() and c.text != "" \
			and c.atr(c.text) == c.text and not spanish_values.has(c.text):
			untranslated.append(c.text)
	_check("every Home text resolves from English or matches an explicit Spanish translation", untranslated.is_empty(), str(untranslated))
	_check("choice saved", Preferences.load_from(PREFS).language == "es")
	await ui.close_app(app)

	var again := _app(PackedStringArray())
	root.add_child(again)
	await ui.settle()
	_check("next start remembers Spanish", TranslationServer.get_locale() == "es" and again.home.language_button.text == "Idioma: Español")
	again.home.language_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("and cycles back to English", TranslationServer.get_locale() == "en" and Preferences.load_from(PREFS).language == "en")
	await ui.close_app(again)


func _direct_route() -> void:
	_reset()
	TranslationServer.set_locale("es_ES")
	var app := _app(PackedStringArray(["--quick-flight"]))
	root.add_child(app)
	await ui.settle()
	_check("direct flight: English, no settings file created", TranslationServer.get_locale() == "en" and not FileAccess.file_exists(PREFS)
		and app.flight != null and app.home == null)
	await ui.close_app(app)
	_write("[meta]\nschema=1\n[ui]\nlanguage=\"es\"\n")
	var before := FileAccess.get_file_as_string(PREFS)
	# A live quick flight verifies the direct route does not read or rewrite saved UI preferences.
	app = _app(PackedStringArray(["--quick-flight"]))
	root.add_child(app)
	await ui.settle()
	_check("direct flight ignores a saved Spanish preference and leaves the file alone",
		TranslationServer.get_locale() == "en" and FileAccess.get_file_as_string(PREFS) == before)
	await ui.close_app(app)


func _app(args: PackedStringArray) -> Node:
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = args
	app.preferences_path = PREFS
	return app
