## L15c-F07: flag preference resolution, persistence and the Graphics selector.
extends SceneTree

const FlagQuality := preload("res://render/flag_quality.gd")
const DisplayPreferences := preload("res://app_state/display_preferences.gd")
const SettingsScreen := preload("res://ui/settings_screen.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const PREFS := "user://test_flag_quality_display.cfg"

var _failures := 0
var _preview := {}


func _initialize() -> void:
	await _run()
	_clean()
	print("flag quality tests passed" if _failures == 0 else "%d flag quality test(s) failed" % _failures)
	quit(0 if _failures == 0 else 1)


func _run() -> void:
	_clean()
	_test_resolution()
	_test_profiles()
	_test_persistence()
	await _test_settings()
	FlagQuality.set_preference("auto")
	FlagQuality._reset_override_for_tests()


func _test_resolution() -> void:
	_check("settings and quality agree on choices and default", DisplayPreferences.FLAG_ANIMATIONS == FlagQuality.PREFERENCES
		and DisplayPreferences.DEFAULTS.flag_animation == "auto")
	var no_args := PackedStringArray()
	_check("saved choice is used without overrides", FlagQuality.resolve_preference(no_args, "", "basic") == "basic")
	_check("environment precedes saved", FlagQuality.resolve_preference(no_args, " DETAILED ", "static") == "detailed")
	var args := PackedStringArray(["--other=x", "--flag_animation=basic", "--flag_animation=static"])
	_check("last CLI choice precedes environment and saved", FlagQuality.resolve_preference(args, "detailed", "basic") == "static")
	FlagQuality._warned.clear()
	_check("unknown CLI falls back to Auto without exposing a lower-priority value",
		FlagQuality.resolve_preference(PackedStringArray(["--flag_animation=wrong"]), "static", "basic") == "auto")
	_check("unknown value warns only once", FlagQuality.resolve_preference(no_args, "WRONG", "basic") == "auto"
		and FlagQuality._warned.size() == 1)
	_check("empty explicit CLI also falls back to Auto", FlagQuality.resolve_preference(
		PackedStringArray(["--flag_animation="]), "detailed", "basic") == "auto")
	_check("invalid saved value falls back to Auto", FlagQuality.resolve_preference(no_args, "", "wrong") == "auto")

	var previous_environment := OS.get_environment(FlagQuality.ENVIRONMENT_KEY)
	OS.set_environment(FlagQuality.ENVIRONMENT_KEY, "detailed")
	FlagQuality._reset_override_for_tests()
	FlagQuality.set_preference("auto")
	_check("runtime reads its environment on first resolution", FlagQuality.level("low") == "detailed")
	OS.set_environment(FlagQuality.ENVIRONMENT_KEY, "static")
	_check("runtime does not rescan the environment on each resolution", FlagQuality.level("low") == "detailed")
	FlagQuality._reset_override_for_tests()
	_check("a fresh source snapshot reads the new environment", FlagQuality.level("low") == "static")
	OS.set_environment(FlagQuality.ENVIRONMENT_KEY, previous_environment)
	FlagQuality._set_override_for_tests(no_args, "")


func _test_profiles() -> void:
	FlagQuality.set_preference("auto")
	var expected := {
		"low": {mode = "basic", grid_x = 8, grid_y = 4, material_tier = "low"},
		"medium": {mode = "detailed", grid_x = 16, grid_y = 8, material_tier = "medium"},
		"high": {mode = "detailed", grid_x = 32, grid_y = 16, material_tier = "high"},
		"extreme": {mode = "detailed", grid_x = 32, grid_y = 16, material_tier = "high"},
	}
	for detail: String in expected:
		_check("Auto follows %s scene detail" % detail, FlagQuality.profile(detail) == expected[detail])
	for mode: String in ["static", "basic"]:
		FlagQuality.set_preference(mode)
		for detail: String in expected:
			_check("%s keeps the cheap grid at %s" % [mode, detail], FlagQuality.profile(detail) == {
				mode = mode, grid_x = 8, grid_y = 4, material_tier = "low"})
	var before: int = FlagQuality.revision
	FlagQuality.set_preference("detailed")
	_check("preference change advances revision", FlagQuality.revision == before + 1)
	FlagQuality.set_preference("detailed")
	_check("unchanged preference does not advance revision", FlagQuality.revision == before + 1)
	_check("explicit Detailed on Low uses Medium", FlagQuality.profile("low") == expected.medium)
	_check("explicit Detailed survives a later scene change", FlagQuality.profile("high") == expected.high)
	var writable_copy: Dictionary = FlagQuality.profile("high")
	writable_copy.grid_x = 1
	_check("a consumer cannot mutate a later profile", FlagQuality.profile("high").grid_x == 32)
	FlagQuality._set_override_for_tests(PackedStringArray(["--flag_animation=static"]), "basic")
	FlagQuality.set_preference("detailed")
	_check("CLI remains authoritative after saved preference changes", FlagQuality.level("high") == "static")
	FlagQuality._set_override_for_tests(PackedStringArray(), "")


func _test_persistence() -> void:
	var candidate: Dictionary = DisplayPreferences.DEFAULTS.duplicate(true)
	candidate.flag_animation = "detailed"
	candidate.scene_detail = "high"
	candidate.birds = "few"
	_check("flag preference round-trips through display.cfg", DisplayPreferences.save_to(PREFS, candidate) == OK
		and DisplayPreferences.load_from(PREFS).flag_animation == "detailed")
	candidate.flag_animation = "many"
	_check("invalid values are rejected on save", not DisplayPreferences.validate(candidate).ok
		and DisplayPreferences.save_to(PREFS, candidate) == ERR_INVALID_DATA
		and DisplayPreferences.load_from(PREFS).flag_animation == "detailed")
	candidate.flag_animation = 4
	_check("invalid types are rejected on save", not DisplayPreferences.validate(candidate).ok)

	var older: Dictionary = DisplayPreferences.DEFAULTS.duplicate(true)
	older.erase("flag_animation")
	var checked: Dictionary = DisplayPreferences.validate(older)
	_check("old dictionaries migrate to Auto", checked.ok and checked.config.flag_animation == "auto")
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "schema", DisplayPreferences.SCHEMA)
	cfg.set_value("graphics", "scene_detail", "extreme")
	cfg.set_value("graphics", "birds", "few")
	_check("legacy config fixture writes", cfg.save(PREFS) == OK)
	var loaded: Dictionary = DisplayPreferences.load_from(PREFS)
	_check("missing key migrates without losing other settings", loaded.flag_animation == "auto"
		and loaded.scene_detail == "extreme" and loaded.birds == "few" and loaded.note == "")
	cfg.set_value("graphics", "flag_animation", 4)
	_check("malformed config fixture writes", cfg.save(PREFS) == OK)
	loaded = DisplayPreferences.load_from(PREFS)
	_check("bad flag value alone falls back while siblings survive", loaded.flag_animation == "auto"
		and loaded.scene_detail == "extreme" and loaded.birds == "few" and not loaded.note.is_empty())


func _test_settings() -> void:
	_clean()
	var previous_locale := TranslationServer.get_locale()
	var previous_scale := UiTheme.text_scale
	UiTheme.text_scale = 1.0
	TranslationServer.set_locale("en")
	var store := DisplayPreferences.new(PREFS)
	var settings := SettingsScreen.new(store, "en")
	settings.presentation_changed.connect(func(config: Dictionary) -> void: _preview = config)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	root.add_child(viewport)
	viewport.add_child(settings)
	settings._surface.theme = UiTheme.build()
	for frame: int in 6:
		await process_frame
	settings._show_category(3)
	for frame: int in 6:
		await process_frame
	var picker: OptionButton = settings.find_child("FlagAnimation", true, false)
	_check("Graphics has a four-choice accessible selector", picker != null and picker.is_visible_in_tree()
		and picker.item_count == 4 and picker.get_item_metadata(picker.selected) == "auto"
		and picker.accessibility_name == "Flag animation")
	if picker != null:
		picker.grab_focus()
		for frame: int in 4:
			await process_frame
		var picker_rect := picker.get_global_rect()
		var scroll_rect: Rect2 = settings._scroll.get_global_rect()
		var in_scroll: bool = picker_rect.position.x >= scroll_rect.position.x and picker_rect.end.x <= scroll_rect.end.x \
			and picker_rect.position.y >= scroll_rect.position.y and picker_rect.end.y <= scroll_rect.end.y
		if not in_scroll:
			print("1080p picker=%s scroll=%s value=%s focus=%s" % [picker_rect, scroll_rect,
				settings._scroll.scroll_vertical, viewport.gui_get_focus_owner()])
		_check("focused flag control is visible in the 1080p Graphics scroll area", in_scroll)
		picker.select(2)
		picker.item_selected.emit(2)
		_check("Basic previews through the presentation signal without a display trial", _preview.flag_animation == "basic"
			and settings._draft.flag_animation == "basic" and settings._trial_deadline_msec == 0)
		settings._revert()
		_check("Revert restores Auto in the signal and selector", _preview.flag_animation == "auto"
			and picker.get_item_metadata(picker.selected) == "auto")
		picker.select(3)
		picker.item_selected.emit(3)
		settings.keep_changes()
		_check("Keep persists Detailed", DisplayPreferences.load_from(PREFS).flag_animation == "detailed")
		settings._scene_detail_picker.select(1)
		settings._scene_detail_picker.item_selected.emit(1)
		_check("changing scene detail retains the chosen flag mode", settings._draft.flag_animation == "detailed"
			and _preview.flag_animation == "detailed")
		settings._restore_graphics_defaults()
		_check("graphics defaults restore Auto", settings._draft.flag_animation == "auto")
		settings._revert()
		_check("Revert after defaults restores saved Detailed", settings._draft.flag_animation == "detailed"
			and _preview.flag_animation == "detailed")
		_test_locales(settings, picker)
	settings.queue_free()
	await process_frame
	viewport.free()
	UiTheme.text_scale = previous_scale
	TranslationServer.set_locale(previous_locale)


func _test_locales(settings: CanvasLayer, picker: OptionButton) -> void:
	var previous_locale := TranslationServer.get_locale()
	var labels := {
		"en": ["Flag animation", "Static", "Basic", "Detailed"],
		"es": ["Animación de la bandera", "Estática", "Básica", "Detallada"],
		"zh_Hans": ["旗帜动画", "静态", "基础", "详细"],
		"pt_BR": ["Animação da bandeira", "Estática", "Básica", "Detalhada"],
		"de": ["Flaggenanimation", "Statisch", "Einfach", "Detailliert"],
		"fr": ["Animation du drapeau", "Statique", "Simple", "Détaillée"],
		"it": ["Animazione della bandiera", "Statica", "Base", "Dettagliata"],
		"ru": ["Анимация флага", "Статичная", "Базовая", "Подробная"],
		"ja": ["旗のアニメーション", "静止", "簡易", "詳細"],
	}
	for locale: String in labels:
		TranslationServer.set_locale(locale)
		settings._refresh_translated_text()
		var expected: Array = labels[locale]
		_check("%s updates open selector translations" % locale, picker.accessibility_name == expected[0]
			and picker.get_item_text(1) == expected[1] and picker.get_item_text(2) == expected[2]
			and picker.get_item_text(3) == expected[3] and picker.get_item_metadata(picker.selected) == "detailed")
	TranslationServer.set_locale(previous_locale)


func _clean() -> void:
	for path: String in [PREFS, PREFS + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(label: String, condition: bool) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + label)
