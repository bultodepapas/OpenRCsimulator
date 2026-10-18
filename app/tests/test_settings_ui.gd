# UI-24: display preferences validation, independent persistence and Settings preview recovery.
# Run: godot --headless --path . --script res://tests/test_settings_ui.gd
extends SceneTree

const DisplayPreferences := preload("res://app_state/display_preferences.gd")
const SettingsScreen := preload("res://ui/settings_screen.gd")
const ScreenTheme := preload("res://ui/ui_theme.gd")
const AppRoot := preload("res://app_root.gd")
const PREFS := "user://test_settings_ui_display.cfg"

var _failures := 0
var _presentations: Array[Dictionary] = []
var _languages: Array[String] = []
var _routes: Array[String] = []


func _initialize() -> void:
	await _run()
	print("all Settings checks passed" if _failures == 0 else "%d Settings checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _run() -> void:
	_clean()
	var test_viewport := SubViewport.new()
	test_viewport.size = Vector2i(1920, 1080) # reference logical canvas used at native 1080p and fullscreen 4K
	test_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(test_viewport)
	await process_frame
	var store := DisplayPreferences.new(PREFS)
	_check("fresh display settings use validated defaults", store.config == DisplayPreferences.DEFAULTS and store.writable)
	var legacy := DisplayPreferences.DEFAULTS.duplicate(true)
	legacy.erase("menu_volume")
	_check("legacy display settings receive the default menu volume", DisplayPreferences.validate(legacy).ok
		and DisplayPreferences.validate(legacy).config.menu_volume == DisplayPreferences.DEFAULTS.menu_volume)
	for invalid_volume: Variant in [-0.1, 1.1, NAN, INF, "quiet"]:
		var invalid_audio := DisplayPreferences.DEFAULTS.duplicate(true)
		invalid_audio.menu_volume = invalid_volume
		_check("invalid menu volume rejected: %s" % str(invalid_volume), not DisplayPreferences.validate(invalid_audio).ok)
		var invalid_master := DisplayPreferences.DEFAULTS.duplicate(true)
		invalid_master.master_volume = invalid_volume
		_check("invalid game volume rejected: %s" % str(invalid_volume), not DisplayPreferences.validate(invalid_master).ok)
	var legacy_master := DisplayPreferences.DEFAULTS.duplicate(true)
	legacy_master.erase("master_volume")
	legacy_master.erase("menu_volume")
	_check("older display settings receive the full game volume", DisplayPreferences.validate(legacy_master).ok
		and DisplayPreferences.validate(legacy_master).config.master_volume == 1.0)

	var candidate := DisplayPreferences.DEFAULTS.duplicate(true)
	candidate.window_mode = "borderless"
	candidate.ui_scale = 1.75
	candidate.opaque_panels = true
	_check("valid range and window mode accepted", DisplayPreferences.validate(candidate).ok)
	var malformed := candidate.duplicate(true)
	malformed.ui_scale = 0.99
	_check("scale below 100% rejected", not DisplayPreferences.validate(malformed).ok)
	malformed = candidate.duplicate(true)
	malformed.ui_scale = 2.05
	_check("scale outside the 5% steps rejected", not DisplayPreferences.validate(malformed).ok)
	malformed = candidate.duplicate(true)
	malformed.window_mode = "exclusive"
	_check("unknown window mode rejected", not DisplayPreferences.validate(malformed).ok)
	malformed = candidate.duplicate(true)
	malformed.reduced_motion = "yes"
	_check("wrong accessibility value type rejected", not DisplayPreferences.validate(malformed).ok)
	_check("invalid settings cannot be saved", DisplayPreferences.save_to(PREFS, malformed) == ERR_INVALID_DATA
		and not FileAccess.file_exists(PREFS))

	_check("valid settings save", store.save(candidate) == OK)
	var reloaded := DisplayPreferences.load_from(PREFS)
	_check("display preferences round-trip", reloaded.window_mode == "borderless"
		and is_equal_approx(reloaded.ui_scale, 1.75) and reloaded.opaque_panels and not reloaded.reduced_motion)
	var relaunched_store := DisplayPreferences.new(PREFS)
	_check("new store instance reloads saved values", relaunched_store.config.window_mode == "borderless"
		and is_equal_approx(relaunched_store.config.ui_scale, 1.75))
	var newer_contents := "[meta]\nschema=99\n[display]\nwindow_mode=\"windowed\"\n"
	_write(newer_contents)
	var newer := DisplayPreferences.load_from(PREFS)
	_check("newer settings file is read-only", not newer.writable and newer.window_mode == "windowed")
	_check("newer settings are never overwritten", DisplayPreferences.save_to(PREFS, candidate) == ERR_FILE_NO_PERMISSION
		and FileAccess.get_file_as_string(PREFS) == newer_contents)
	_clean()
	_write("not a valid ConfigFile")
	var broken := DisplayPreferences.load_from(PREFS)
	_check("unreadable settings are preserved for recovery", broken.window_mode == "windowed"
		and FileAccess.file_exists(PREFS + ".bad") and not FileAccess.file_exists(PREFS))
	_clean()
	store = DisplayPreferences.new(PREFS)

	var default_settings := SettingsScreen.new(store, "en")
	test_viewport.add_child(default_settings)
	await process_frame
	await process_frame
	_check("default 1080p/4K Settings Display page fits without scrolling",
		not default_settings._scroll.get_v_scroll_bar().visible,
		"scrollbar=%s viewport=%s surface=%s page=%s panel=%s" % [
		str(default_settings._scroll.get_v_scroll_bar().visible), str(test_viewport.size),
		str(default_settings._surface.size),
		str(default_settings._scroll.get_child(0).size), str(default_settings._layout_panel.size)])
	_check("default Settings workspace is bounded on a wide viewport",
		default_settings._layout_panel.size.x <= 800.0)
	for category: int in 3:
		default_settings._show_category(category)
		await process_frame
		await process_frame
		_check("default Settings category %d fits without scrolling" % category,
			not default_settings._scroll.get_v_scroll_bar().visible)
	default_settings._volume_changed(0.0)
	_check("muted preview disables Test sound", default_settings._test_sound_button.disabled
		and default_settings._volume_value.text == tr("Muted"))
	default_settings.keep_changes()
	_check("Keep persists menu mute", DisplayPreferences.load_from(PREFS).menu_volume == 0.0)
	default_settings._volume_changed(0.75)
	default_settings._revert()
	_check("Revert restores the kept volume and slider", default_settings._draft.menu_volume == 0.0
		and default_settings._volume_slider.value == 0.0 and default_settings._test_sound_button.disabled)
	default_settings._volume_changed(0.75)
	default_settings.close()
	_check("Close restores the kept volume", default_settings._draft.menu_volume == 0.0
		and DisplayPreferences.load_from(PREFS).menu_volume == 0.0)
	# AUD-12b: game volume follows the same preview, Keep, Revert and Close contract.
	_presentations.clear()
	default_settings.presentation_changed.connect(_capture_presentation)
	default_settings._master_volume_changed(0.5)
	_check("game volume previews through the presentation signal", not _presentations.is_empty()
		and float(_presentations.back().master_volume) == 0.5 and default_settings._master_value.text == "50%")
	default_settings.keep_changes()
	_check("Keep persists the game volume", DisplayPreferences.load_from(PREFS).master_volume == 0.5)
	default_settings._master_volume_changed(0.0)
	_check("zero game volume reads Muted", default_settings._master_value.text == tr("Muted"))
	default_settings._revert()
	_check("Revert restores the kept game volume and slider", default_settings._draft.master_volume == 0.5
		and default_settings._master_slider.value == 0.5)
	default_settings._master_volume_changed(0.2)
	default_settings.close()
	_check("Close restores the kept game volume", float(_presentations.back().master_volume) == 0.5
		and DisplayPreferences.load_from(PREFS).master_volume == 0.5)
	var master_bus: int = AudioServer.get_bus_index(&"Master")
	AppRoot.apply_master_volume(0.5)
	var half_db: float = AudioServer.get_bus_volume_db(master_bus)
	var half_muted: bool = AudioServer.is_bus_mute(master_bus)
	AppRoot.apply_master_volume(0.0)
	var zero_muted: bool = AudioServer.is_bus_mute(master_bus)
	AppRoot.apply_master_volume(1.0)
	_check("game volume drives the Master bus: 50 % = -6.02 dB, 0 mutes, 100 % restores 0 dB",
		absf(half_db - linear_to_db(0.5)) < 1e-4 and not half_muted and zero_muted
		and AudioServer.get_bus_volume_db(master_bus) == 0.0 and not AudioServer.is_bus_mute(master_bus))
	default_settings.queue_free()
	await process_frame

	ScreenTheme.text_scale = 2.0
	var settings := SettingsScreen.new(store, "en")
	settings.presentation_changed.connect(_capture_presentation)
	settings.language_changed.connect(_capture_language)
	settings.route_requested.connect(_capture_route)
	_check("Close receives initial keyboard focus", settings._close_button.focus_mode == Control.FOCUS_ALL)
	var all_rows_stack := true
	for row: BoxContainer in settings._rows:
		all_rows_stack = all_rows_stack and row.vertical
	_check("200% text stacks settings rows", all_rows_stack and not settings._rows.is_empty())
	test_viewport.add_child(settings)
	await process_frame
	await process_frame
	var panel_rect := settings._layout_panel.get_global_rect()
	_check("200% Settings scrolls only its body and pins title and Keep/Revert",
		settings._scroll.get_v_scroll_bar().visible
		and panel_rect.encloses(settings._close_button.get_global_rect())
		and panel_rect.encloses(settings._keep_button.get_global_rect())
		and panel_rect.encloses(settings._revert_button.get_global_rect()),
		"scrollbar=%s panel=%s close=%s keep=%s revert=%s" % [str(settings._scroll.get_v_scroll_bar().visible),
		str(panel_rect), str(settings._close_button.get_global_rect()), str(settings._keep_button.get_global_rect()),
		str(settings._revert_button.get_global_rect())])
	settings._show_category(1)
	await process_frame
	settings._language_picker.grab_focus()
	await process_frame
	await process_frame
	_check("200% focus scrolls the complete language selector into view", settings._scroll.get_global_rect().encloses(settings._language_picker.get_global_rect()))
	settings._show_category(0)
	settings._window_mode_selected(1)
	_check("window change starts a 15-second trial", settings._trial_deadline_msec - Time.get_ticks_msec() > 14500
		and settings._trial_deadline_msec - Time.get_ticks_msec() <= 15000)
	settings._trial_deadline_msec = Time.get_ticks_msec() - 1
	settings._process(0.0)
	_check("expired preview emits the saved display configuration", not _presentations.is_empty()
		and _presentations.back() == store.config)
	_check("expired preview does not persist the tested window mode", DisplayPreferences.load_from(PREFS).window_mode == "windowed")

	settings._language_selected(1)
	_check("language applies immediately through the host signal", _languages == ["es"])
	settings._notification(NOTIFICATION_TRANSLATION_CHANGED)
	_check("locale refresh rebuilds status and window picker labels", settings._window_picker.get_item_text(0) == tr("Windowed")
		and settings._status.text != "")
	var controls: Button = settings.find_child("Controls", true, false) as Button
	var about: Button = settings.find_child("HelpAbout", true, false) as Button
	controls.pressed.emit()
	about.pressed.emit()
	_check("Controls and Help/About expose host routes", _routes == ["controls", "about"])

	settings._scale_selected(4)
	settings.keep_changes()
	_check("Keep persists accessibility and scale changes", is_equal_approx(DisplayPreferences.load_from(PREFS).ui_scale, 2.0))
	settings._opaque_toggled(true)
	settings._window_mode_selected(1)
	settings.close()
	_check("Back/close restores the last kept display configuration", _presentations.back() == store.config
		and DisplayPreferences.load_from(PREFS).window_mode == "windowed"
		and not DisplayPreferences.load_from(PREFS).opaque_panels)
	settings.queue_free()
	test_viewport.queue_free()
	await process_frame
	ScreenTheme.text_scale = 1.0
	_clean()


func _write(contents: String) -> void:
	var file := FileAccess.open(PREFS, FileAccess.WRITE)
	file.store_string(contents)
	file.close()


func _clean() -> void:
	for candidate in [PREFS, PREFS + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))


func _capture_presentation(config: Dictionary) -> void:
	_presentations.append(config.duplicate(true))


func _capture_language(language: String) -> void:
	_languages.append(language)


func _capture_route(route: String, _from: Control) -> void:
	_routes.append(route)


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
