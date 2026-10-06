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

	await ui.tap(KEY_DOWN)
	await ui.tap(KEY_ENTER)
	_check("Enter on Language -> Spanish at once", TranslationServer.get_locale() == "es" and home.fly_button.atr(home.fly_button.text) == "VOLAR")
	_check("dynamic texts rebuilt in Spanish", home.language_button.text == "Idioma: Español" and home.control_label.text.begins_with("Control: teclado"),
		"%s | %s" % [home.language_button.text, home.control_label.text])
	_check("focus stays on Language", ui.focus_name() == "Language", ui.focus_name())
	var untranslated := PackedStringArray()
	for c in home.find_children("*", "", true, false):
		if (c is Label or c is Button) and c.can_auto_translate() and c.text != "" and c.atr(c.text) == c.text:
			untranslated.append(c.text)
	_check("every translatable Home text has a Spanish translation", untranslated.is_empty(), str(untranslated))
	_check("choice saved", Preferences.load_from(PREFS).language == "es")
	app.free()

	var again := _app(PackedStringArray())
	root.add_child(again)
	await ui.settle()
	_check("next start remembers Spanish", TranslationServer.get_locale() == "es" and again.home.language_button.text == "Idioma: Español")
	await ui.tap(KEY_DOWN)
	await ui.tap(KEY_ENTER)
	_check("and cycles back to English", TranslationServer.get_locale() == "en" and Preferences.load_from(PREFS).language == "en")
	again.free()


func _direct_route() -> void:
	_reset()
	TranslationServer.set_locale("es_ES")
	var app := _app(PackedStringArray(["--quick-flight"]))
	root.add_child(app)
	await ui.settle()
	_check("direct flight: English, no settings file created", TranslationServer.get_locale() == "en" and not FileAccess.file_exists(PREFS)
		and app.flight != null and app.home == null)
	app.free()
	_write("[meta]\nschema=1\n[ui]\nlanguage=\"es\"\n")
	var before := FileAccess.get_file_as_string(PREFS)
	# Route only: main.gd reads the real command line (none here), so this flight runs live, not a trace.
	app = _app(PackedStringArray(["--trace=/dev/null", "--t=0"]))
	root.add_child(app)
	await ui.settle()
	_check("direct flight ignores a saved Spanish preference and leaves the file alone",
		TranslationServer.get_locale() == "en" and FileAccess.get_file_as_string(PREFS) == before)
	app.free()


func _app(args: PackedStringArray) -> Node:
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = args
	app.preferences_path = PREFS
	return app
