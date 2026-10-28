# UI-01d: English by default (whatever the OS locale), eight translated languages available, the choice remembered in a versioned
# settings file that automation never reads or writes. Settings files here are test-only paths under user://.
# Run: godot --headless --path . --script res://tests/test_ui_language.gd
extends SceneTree

const Preferences := preload("res://app_state/preferences.gd")
const Home := preload("res://ui/home.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const InterfaceFont := preload("res://i18n/fonts.gd")
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
	await process_frame # Autoloads install bundled fonts before screens enter the tree.
	_font_atlas_isolation()
	_preferences_file()
	await _catalog()
	await _default_and_switch()
	await _direct_route()
	for f in [PREFS, PREFS + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	print("all UI language checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _render_font_chars(font: FontFile, characters: String) -> void:
	for character: String in characters:
		var glyph: int = font.get_glyph_index(26, character.unicode_at(0), 0)
		if glyph > 0:
			font.render_glyph(0, Vector2i(26, 0), glyph)


func _glyph_pixels(font: FontFile, glyph: int) -> PackedByteArray:
	var size := Vector2i(26, 0)
	var texture_index: int = font.get_glyph_texture_idx(0, size, glyph)
	if texture_index < 0:
		return PackedByteArray()
	var atlas: Image = font.get_texture_image(0, size, texture_index)
	return atlas.get_region(Rect2i(font.get_glyph_uv_rect(0, size, glyph))).get_data()


func _font_atlas_isolation() -> void:
	var original: FontFile = ThemeDB.fallback_font
	var size := Vector2i(26, 0)
	_render_font_chars(original, "Use opaque panels")
	var names: FontVariation = InterfaceFont.language_names_font()
	var names_base: FontFile = names.base_font
	_render_font_chars(original, "Settings interface color display background")
	_render_font_chars(names_base, "Русский Français Español Deutsch Polski Português")
	var reference := FontFile.new()
	reference.antialiasing = original.antialiasing
	reference.generate_mipmaps = original.generate_mipmaps
	reference.multichannel_signed_distance_field = original.multichannel_signed_distance_field
	reference.msdf_pixel_range = original.msdf_pixel_range
	reference.msdf_size = original.msdf_size
	reference.fixed_size = original.fixed_size
	reference.force_autohinter = original.force_autohinter
	reference.hinting = original.hinting
	reference.subpixel_positioning = original.subpixel_positioning
	reference.oversampling = original.oversampling
	reference.set_data(original.get_data())
	var mismatches := PackedInt32Array()
	var glyphs: PackedInt32Array = original.get_glyph_list(0, size)
	for glyph: int in glyphs:
		reference.render_glyph(0, size, glyph)
		if _glyph_pixels(original, glyph) != _glyph_pixels(reference, glyph):
			mismatches.append(glyph)
	_check("language-name glyphs cannot corrupt the shared 26px UI atlas", not glyphs.is_empty() and mismatches.is_empty(),
		"glyphs=%d mismatches=%s" % [glyphs.size(), mismatches])
	# Restore clean caches even when the regression is run against the old shallow copy.
	original.remove_size_cache(0, size)
	names_base.remove_size_cache(0, size)


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
	_write("[meta]\nschema=1\n[ui]\nlanguage=\"zz\"\n")
	_check("unsupported language -> English", Preferences.load_from(PREFS).language == "en")
	_write("[meta]\nschema=1\n[ui]\nlanguage=7\n")
	_check("wrong type -> English (ConfigFile keeps the file's type)", Preferences.load_from(PREFS).language == "en")
	_write("this is not [a config file\n")
	p = Preferences.load_from(PREFS)
	_check("unreadable file -> defaults, kept as .bad", p.language == "en" and FileAccess.file_exists(PREFS + ".bad")
		and not FileAccess.file_exists(PREFS) and "kept as" in p.note, p.note)
	_check("preserved unreadable settings allow a new file", p.writable and Preferences.save_to(PREFS, p) == OK)
	_reset()
	var backup := ProjectSettings.globalize_path(PREFS + ".bad")
	_check("create blocked backup directory", DirAccess.make_dir_absolute(backup) == OK)
	var marker := FileAccess.open(backup.path_join("marker"), FileAccess.WRITE)
	marker.store_string("occupied")
	marker.close()
	var broken := "this is not [a config file\n"
	_write(broken)
	p = Preferences.load_from(PREFS)
	_check("failed settings backup protects the original", not p.writable and "will not be overwritten" in p.note
		and FileAccess.get_file_as_string(PREFS) == broken, p.note)
	p.language = "es"
	_check("failed settings backup refuses later saves", Preferences.save_to(PREFS, p) == ERR_FILE_NO_PERMISSION
		and p.language == "es" and FileAccess.get_file_as_string(PREFS) == broken)
	DirAccess.remove_absolute(backup.path_join("marker"))
	DirAccess.remove_absolute(backup)
	_reset()
	var newer := "[meta]\nschema=99\n[ui]\nlanguage=\"es\"\n"
	_write(newer)
	p = Preferences.load_from(PREFS)
	_check("newer schema: valid values read, file marked read-only", p.language == "es" and not p.writable, p.note)
	p.language = "en"
	_check("newer schema: never overwritten", Preferences.save_to(PREFS, p) != OK and FileAccess.get_file_as_string(PREFS) == newer)
	_reset()


func _catalog() -> void:
	var source: Translation = load("res://i18n/es.po")
	var chinese_font: Font = load("res://assets/fonts/NotoSansCJKsc-Regular.otf")
	var japanese_font: Font = load("res://assets/fonts/NotoSansCJKjp-Regular.otf")
	var placeholder := RegEx.new()
	placeholder.compile("%[-+0-9.#]*[sdfxXocgeE]|%%")
	for code: String in Preferences.LANGUAGES:
		_check("language %s has a catalog or is the source" % code, code == "en" or code in TranslationServer.get_loaded_locales())
		if code == "en":
			continue
		var catalog_path: String = "res://i18n/%s.po" % code
		var catalog: Translation = load(catalog_path)
		var missing := PackedStringArray()
		var invalid_formats := PackedStringArray()
		var missing_glyphs := {}
		for message: String in source.get_message_list():
			var translated: String = catalog.get_message(message)
			if translated.is_empty():
				missing.append(message)
			# Check added catalogs; existing Spanish wording is maintained separately.
			if code == "es":
				continue
			var before: Array[String] = []
			var after: Array[String] = []
			for token: RegExMatch in placeholder.search_all(message):
				before.append(token.get_string())
			for token: RegExMatch in placeholder.search_all(translated):
				after.append(token.get_string())
			if before != after:
				invalid_formats.append(message)
			for character: String in translated:
				var point: int = character.unicode_at(0)
				if code == "zh_Hans" and point >= 0x3400 and point <= 0x9fff and not chinese_font.has_char(point):
					missing_glyphs[character] = true
				if code == "ja" and point > 0x7f and not japanese_font.has_char(point):
					missing_glyphs[character] = true
				if code == "ru" and point >= 0x0400 and point <= 0x052f and not ThemeDB.fallback_font.has_char(point):
					missing_glyphs[character] = true
		_check("%s catalog covers all %d source messages" % [code, source.get_message_count()],
			catalog.get_message_count() == source.get_message_count() and missing.is_empty(), str(missing))
		if code != "es":
			_check("%s format arguments remain ordered and intact" % code, invalid_formats.is_empty(), str(invalid_formats))
		if code == "zh_Hans":
			_check("Chinese glyphs are bundled", missing_glyphs.is_empty(), str(missing_glyphs.keys()))
		if code == "ja":
			_check("all Japanese non-ASCII glyphs are bundled", missing_glyphs.is_empty(), str(missing_glyphs.keys()))
		if code == "ru":
			_check("all Russian catalog Cyrillic glyphs use the original font", missing_glyphs.is_empty(), str(missing_glyphs.keys()))
	_check("Latin UI keeps its original fallback metrics", chinese_font not in ThemeDB.fallback_font.fallbacks)
	TranslationServer.set_locale("zh_Hans")
	await process_frame
	_check("Chinese UI includes the bundled fallback", chinese_font in ThemeDB.fallback_font.fallbacks)
	TranslationServer.set_locale("ja")
	await process_frame
	_check("Japanese uses Japanese glyph forms without the Chinese fallback", japanese_font in ThemeDB.fallback_font.fallbacks
		and chinese_font not in ThemeDB.fallback_font.fallbacks)
	TranslationServer.set_locale("zh_Hans")
	await process_frame
	_check("switching back to Chinese removes the Japanese font", chinese_font in ThemeDB.fallback_font.fallbacks
		and japanese_font not in ThemeDB.fallback_font.fallbacks)
	TranslationServer.set_locale("en")
	await process_frame
	_check("returning to English restores the font", chinese_font not in ThemeDB.fallback_font.fallbacks
		and japanese_font not in ThemeDB.fallback_font.fallbacks)
	_check("regional Japanese locales resolve to Japanese", Preferences.Languages.supported_locale("ja_JP") == "ja")
	_check("script-qualified Chinese locale remains Chinese", Preferences.Languages.supported_locale("zh_Hans_CN") == "zh_Hans")
	_check("traditional Chinese is not mislabeled as simplified", Preferences.Languages.supported_locale("zh_Hant_TW") == "en")
	_check("Brazilian Portuguese region is retained", Preferences.Languages.supported_locale("pt-BR") == "pt_BR")
	var portuguese_glyphs := PackedStringArray()
	for character: String in "ÀÁÂÃÇÉÊÍÓÔÕÚÜàáâãçéêíóôõúü":
		if not ThemeDB.fallback_font.has_char(character.unicode_at(0)):
			portuguese_glyphs.append(character)
	_check("Portuguese accents are in the original font", portuguese_glyphs.is_empty(), str(portuguese_glyphs))
	_check("regional German locales resolve to German", Preferences.Languages.supported_locale("de_DE") == "de"
		and Preferences.Languages.supported_locale("de_AT") == "de" and Preferences.Languages.supported_locale("de_CH") == "de")
	var german_glyphs := PackedStringArray()
	for character: String in "ÄÖÜäöüßẞ":
		if not ThemeDB.fallback_font.has_char(character.unicode_at(0)):
			german_glyphs.append(character)
	_check("German umlauts and sharp s are in the original font", german_glyphs.is_empty(), str(german_glyphs))
	_check("regional French locales resolve to French", Preferences.Languages.supported_locale("fr_FR") == "fr"
		and Preferences.Languages.supported_locale("fr_CA") == "fr" and Preferences.Languages.supported_locale("fr_CH") == "fr")
	var french_glyphs := PackedStringArray()
	for character: String in "ÀÂÆÇÉÈÊËÎÏÔŒÙÛÜŸàâæçéèêëîïôœùûüÿ«»’":
		if not ThemeDB.fallback_font.has_char(character.unicode_at(0)):
			french_glyphs.append(character)
	_check("French accents and ligatures are in the original font", french_glyphs.is_empty(), str(french_glyphs))
	_check("regional Italian locales resolve to Italian", Preferences.Languages.supported_locale("it_IT") == "it"
		and Preferences.Languages.supported_locale("it_CH") == "it")
	var italian_glyphs := PackedStringArray()
	for character: String in "ÀÈÉÌÒÙàèéìòù«»’":
		if not ThemeDB.fallback_font.has_char(character.unicode_at(0)):
			italian_glyphs.append(character)
	_check("Italian accented letters are in the original font", italian_glyphs.is_empty(), str(italian_glyphs))
	_check("regional Russian locales resolve to Russian", Preferences.Languages.supported_locale("ru_RU") == "ru"
		and Preferences.Languages.supported_locale("ru_KZ") == "ru")
	var russian_glyphs := PackedStringArray()
	for character: String in "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдеёжзийклмнопрстуфхцчшщъыьэюя№«»—":
		if not ThemeDB.fallback_font.has_char(character.unicode_at(0)):
			russian_glyphs.append(character)
	_check("complete Russian alphabet is in the original font", russian_glyphs.is_empty(), str(russian_glyphs))


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
	_check("third option switches to Chinese immediately", TranslationServer.get_locale() == "zh_Hans"
		and again.home.language_button.text == "语言：简体中文"
		and again.home.fly_button.atr(again.home.fly_button.text) == "开始飞行")
	_check("Chinese choice saved", Preferences.load_from(PREFS).language == "zh_Hans")
	await ui.close_app(again)
	again = _app(PackedStringArray())
	root.add_child(again)
	await ui.settle()
	_check("next start remembers Chinese", TranslationServer.get_locale() == "zh_Hans"
		and again.home.language_button.text == "语言：简体中文")
	again.home.language_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("fourth option switches to Brazilian Portuguese", TranslationServer.get_locale() == "pt_BR"
		and again.home.language_button.text == "Idioma: Português (Brasil)"
		and again.home.fly_button.atr(again.home.fly_button.text) == "VOAR")
	_check("Portuguese choice saved", Preferences.load_from(PREFS).language == "pt_BR")
	_check("Portuguese uses the original Latin font", ThemeDB.fallback_font.fallbacks.is_empty())
	await ui.close_app(again)
	again = _app(PackedStringArray())
	root.add_child(again)
	await ui.settle()
	_check("next start remembers Portuguese", TranslationServer.get_locale() == "pt_BR"
		and again.home.language_button.text == "Idioma: Português (Brasil)")
	again.home.language_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("fifth option switches to German", TranslationServer.get_locale() == "de"
		and again.home.language_button.text == "Sprache: Deutsch"
		and again.home.fly_button.atr(again.home.fly_button.text) == "FLIEGEN")
	_check("German choice saved", Preferences.load_from(PREFS).language == "de")
	_check("German uses the original Latin font", ThemeDB.fallback_font.fallbacks.is_empty())
	await ui.close_app(again)
	again = _app(PackedStringArray())
	root.add_child(again)
	await ui.settle()
	_check("next start remembers German", TranslationServer.get_locale() == "de"
		and again.home.language_button.text == "Sprache: Deutsch")
	again.home.language_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("sixth option switches to French", TranslationServer.get_locale() == "fr"
		and again.home.language_button.text == "Langue : Français"
		and again.home.fly_button.atr(again.home.fly_button.text) == "VOLER")
	_check("French choice saved", Preferences.load_from(PREFS).language == "fr")
	_check("French uses the original Latin font", ThemeDB.fallback_font.fallbacks.is_empty())
	await ui.close_app(again)
	again = _app(PackedStringArray())
	root.add_child(again)
	await ui.settle()
	_check("next start remembers French", TranslationServer.get_locale() == "fr"
		and again.home.language_button.text == "Langue : Français")
	again.home.language_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("seventh option switches to Italian", TranslationServer.get_locale() == "it"
		and again.home.language_button.text == "Lingua: Italiano"
		and again.home.fly_button.atr(again.home.fly_button.text) == "VOLA")
	_check("Italian choice saved", Preferences.load_from(PREFS).language == "it")
	_check("Italian uses the original Latin font", ThemeDB.fallback_font.fallbacks.is_empty())
	await ui.close_app(again)
	again = _app(PackedStringArray())
	root.add_child(again)
	await ui.settle()
	_check("next start remembers Italian", TranslationServer.get_locale() == "it"
		and again.home.language_button.text == "Lingua: Italiano")
	again.home.language_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("eighth option switches to Russian", TranslationServer.get_locale() == "ru"
		and again.home.language_button.text == "Язык: Русский"
		and again.home.fly_button.atr(again.home.fly_button.text) == "ЛЕТЕТЬ")
	_check("Russian choice saved", Preferences.load_from(PREFS).language == "ru")
	_check("Russian uses the original font without a CJK fallback", ThemeDB.fallback_font.fallbacks.is_empty())
	await ui.close_app(again)
	again = _app(PackedStringArray())
	root.add_child(again)
	await ui.settle()
	_check("next start remembers Russian", TranslationServer.get_locale() == "ru"
		and again.home.language_button.text == "Язык: Русский")
	again.home.language_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("ninth option switches to Japanese", TranslationServer.get_locale() == "ja"
		and again.home.language_button.text == "言語：日本語"
		and again.home.fly_button.atr(again.home.fly_button.text) == "飛行開始")
	_check("Japanese choice saved", Preferences.load_from(PREFS).language == "ja")
	await ui.close_app(again)
	again = _app(PackedStringArray())
	root.add_child(again)
	await ui.settle()
	_check("next start remembers Japanese", TranslationServer.get_locale() == "ja"
		and again.home.language_button.text == "言語：日本語")
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
