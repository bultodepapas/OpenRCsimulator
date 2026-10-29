extends SceneTree

const UiDriver := preload("res://tests/ui_driver.gd")
const AppRoot := preload("res://app_root.gd")
const Preferences := preload("res://app_state/preferences.gd")
const DisplayPreferences := preload("res://app_state/display_preferences.gd")
const HighGraphics := preload("res://render/high_graphics_profile.gd")
const UiTheme := preload("res://ui/ui_theme.gd")

const PREFS := "user://test high graphics restart settings.cfg"

var _checks := 0
var _failures := 0
var _ui: RefCounted
var _app: Node
var _settings: CanvasLayer
var _restart_calls: Array[String] = []
var _restart_observation: Dictionary = {}
var _capture_directory := ""
var _capture_enabled := false


func _initialize() -> void:
	var saved_locale := TranslationServer.get_locale()
	var saved_max_fps: int = Engine.max_fps
	var saved_msaa: Viewport.MSAA = root.msaa_3d
	var saved_text_scale: float = UiTheme.text_scale
	var saved_compact_layout: bool = UiTheme.compact_layout
	_ui = UiDriver.new(self)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--restart-captures="):
			_capture_directory = argument.trim_prefix("--restart-captures=")
	if DisplayServer.get_name() == "headless":
		root.size = Vector2i(1280, 720)
	_prepare_capture_directory()
	await _run_restart_checks()
	await _cleanup_app()
	TranslationServer.set_locale(saved_locale)
	Engine.max_fps = saved_max_fps
	root.msaa_3d = saved_msaa
	UiTheme.text_scale = saved_text_scale
	UiTheme.compact_layout = saved_compact_layout
	_clean_preferences()
	print("high graphics restart: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _prepare_capture_directory() -> void:
	if _capture_directory.is_empty():
		return
	if DisplayServer.get_name() == "headless":
		_check("restart captures require a native display", false)
		return
	if DirAccess.dir_exists_absolute(_capture_directory):
		_check("restart capture output is a new directory", false, _capture_directory)
		return
	var error := DirAccess.make_dir_recursive_absolute(_capture_directory)
	_capture_enabled = error == OK
	_check("restart capture output directory created", _capture_enabled, "error %d" % error)


func _run_restart_checks() -> void:
	_clean_preferences()
	var saved_preferences: Dictionary = Preferences.DEFAULTS.duplicate(true)
	saved_preferences.first_flight_hint_seen = true
	_check("isolated Home preferences prepared", Preferences.save_to(PREFS, saved_preferences) == OK)
	var saved_display: Dictionary = DisplayPreferences.DEFAULTS.duplicate(true)
	saved_display.max_fps = 60
	_check("isolated display preferences prepared", DisplayPreferences.save_to(PREFS + ".display", saved_display) == OK)
	var general_file_before := FileAccess.get_file_as_string(PREFS)
	var display_file_before := FileAccess.get_file_as_string(PREFS + ".display")
	var expected_profile := "standard" if HighGraphics.active() else "high"

	_app = load("res://app_root.tscn").instantiate()
	_app.user_args = PackedStringArray()
	_app.preferences_path = PREFS
	_app.graphics_restart = Callable(self, "_record_restart")
	root.add_child(_app)
	await _ui.settle()
	_check("real app opens on Home without technical arguments", _app.home != null and _app.has_home
		and _app.screens.is_top("home") and _app.user_args.is_empty()
		and not AppRoot.wants_direct_flight(_app.user_args))
	_check("normal Home allows a graphics restart", _app._can_restart_graphics())

	_app.home.settings_button.grab_focus()
	await _ui.tap(KEY_ENTER)
	_settings = _app.screens.get_screen("settings") as CanvasLayer
	await _ui.settle()
	_check("Home opens the real Settings screen", _settings != null and _app.screens.is_top("settings"))
	_settings._show_category(3)
	await _ui.settle()
	_check("graphics restart button is enabled from Home", not _settings._graphics_restart_button.disabled)
	await _check_restart_labels_and_capture(expected_profile)

	# A live display preview is pending when the restart button is pressed.
	_settings._fps_picker.select(1)
	_settings._fps_picker.item_selected.emit(1) # 30 FPS; saved preference is 60 FPS.
	await _ui.settle()
	_check("FPS preview is active and remains unsaved", Engine.max_fps == 30
		and _settings._trial_deadline_msec > Time.get_ticks_msec()
		and _app.display_preferences.config == saved_display)
	_restart_calls.clear()
	_restart_observation.clear()
	_settings._graphics_restart_button.grab_focus()
	await _ui.settle()
	await _ui.tap(KEY_ENTER) # focused GraphicsRestart button; its handler reverts before emitting.
	_check("restart callback receives the active profile target", _restart_calls == [expected_profile])
	_check("pending display preview is reverted before callback",
		_restart_observation.get("draft", {}) == _restart_observation.get("saved", {})
		and int(_restart_observation.get("trial_deadline", -1)) == 0
		and int(_restart_observation.get("engine_max_fps", -1)) == int(saved_display.max_fps))
	_check("restart callback sees persisted preferences unchanged",
		_restart_observation.get("general_file", "") == general_file_before
		and _restart_observation.get("display_file", "") == display_file_before
		and _restart_observation.get("display_config", {}) == saved_display)
	_check("restart request does not change saved settings on disk",
		FileAccess.get_file_as_string(PREFS) == general_file_before
		and FileAccess.get_file_as_string(PREFS + ".display") == display_file_before)

	_settings.close()
	await _ui.settle()
	_check("restarting test callback leaves the app open at Home", _app.screens.is_top("home")
		and _app.flight == null and _restart_calls.size() == 1)
	_test_invalid_profile_refused(expected_profile)
	_test_home_guards_refused(expected_profile)
	_test_restart_arguments(expected_profile)
	await _test_pause_settings_disabled(expected_profile)


func _check_restart_labels_and_capture(profile: String) -> void:
	var is_high_active := profile == "standard"
	var english_label := "Restart in Standard" if is_high_active else "Enable High (restart)"
	var spanish_label := "Reiniciar en Estándar" if is_high_active else "Activar Alta gama (reinicia)"
	for language: String in ["en", "es"]:
		TranslationServer.set_locale(language)
		_settings._notification(NOTIFICATION_TRANSLATION_CHANGED)
		await _ui.settle()
		var expected := english_label if language == "en" else spanish_label
		_check("%s graphics restart label is localized" % language,
			_settings._graphics_restart_button.text == expected, _settings._graphics_restart_button.text)
		await _capture_restart_label(language)
	TranslationServer.set_locale("en")
	_settings._notification(NOTIFICATION_TRANSLATION_CHANGED)
	await _ui.settle()


func _capture_restart_label(language: String) -> void:
	if not _capture_enabled or DisplayServer.get_name() == "headless":
		return
	_settings._scroll.scroll_vertical = _settings._scroll.get_v_scroll_bar().max_value
	await _ui.settle()
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := _capture_directory.path_join("graphics-restart-%s.png" % language)
	_check("%s native settings capture saved" % language, image != null and image.save_png(path) == OK, path)


func _test_invalid_profile_refused(expected_profile: String) -> void:
	var count_before := _restart_calls.size()
	_app._request_graphics_restart("ultra")
	_check("invalid graphics profile is refused", _restart_calls.size() == count_before)
	_app._request_graphics_restart(expected_profile)
	_check("valid Home request reaches injected callback", _restart_calls.size() == count_before + 1
		and _restart_calls.back() == expected_profile)


func _test_home_guards_refused(profile: String) -> void:
	var count_before := _restart_calls.size()
	var fake_flight := Node.new()
	_app.flight = fake_flight
	_check("flight blocks graphics restart", not _app._can_restart_graphics())
	_app._request_graphics_restart(profile)
	_check("flight guard refuses injected callback", _restart_calls.size() == count_before)
	_app.flight = null
	fake_flight.free()

	var fake_ground := Node3D.new()
	_app.ground_vehicle = fake_ground
	_check("ground activity blocks graphics restart", not _app._can_restart_graphics())
	_app._request_graphics_restart(profile)
	_check("ground guard refuses injected callback", _restart_calls.size() == count_before)
	_app.ground_vehicle = null
	fake_ground.free()

	_app._workshop_screens.append({"id": "workshop"})
	_check("Workshop draft blocks graphics restart", not _app._can_restart_graphics())
	_app._request_graphics_restart(profile)
	_check("Workshop guard refuses injected callback", _restart_calls.size() == count_before)
	_app._workshop_screens.clear()

	_app._exit_request_active = true
	_check("exit transaction blocks graphics restart", not _app._can_restart_graphics())
	_app._request_graphics_restart(profile)
	_check("exit guard refuses injected callback", _restart_calls.size() == count_before)
	_app._exit_request_active = false

	_app.has_home = false
	_check("direct route without Home blocks graphics restart", not _app._can_restart_graphics())
	_app._request_graphics_restart(profile)
	_check("no-Home guard refuses injected callback", _restart_calls.size() == count_before)
	_app.has_home = true
	_check("Home guard restores restart availability", _app._can_restart_graphics())


func _test_restart_arguments(active_target: String) -> void:
	var spaced_project := "C:/Program Files/OpenRC Simulator/build copy/app"
	for profile: String in ["standard", "high"]:
		var renderer := "forward_plus" if profile == "high" else "gl_compatibility"
		var packaged := HighGraphics.restart_arguments(profile, false, spaced_project)
		var editor := HighGraphics.restart_arguments(profile, true, spaced_project)
		_check("packaged %s restart selects its renderer" % profile,
			packaged == PackedStringArray(["--rendering-method", renderer]))
		_check("editor %s restart preserves a spaced project path as one argument" % profile,
			editor == PackedStringArray(["--path", spaced_project, "--rendering-method", renderer]))
		var has_technical_arg := false
		for argument: String in packaged + editor:
			if argument in ["--", "--script", "--trace", "--capture", "--quick-flight", "--aircraft"]:
				has_technical_arg = true
		_check("%s restart args contain no technical route arguments" % profile, not has_technical_arg)
	_check("unsupported restart profile has no arguments",
		HighGraphics.restart_arguments("ultra", true, spaced_project).is_empty())
	_check("restart preserves Home route rather than a direct technical route",
		AppRoot.wants_direct_flight(PackedStringArray()) == false and _app.user_args.is_empty())
	_check("requested app target is valid", active_target in ["standard", "high"])


func _test_pause_settings_disabled(profile: String) -> void:
	_app.home.fly_button.grab_focus()
	await _ui.tap(KEY_ENTER)
	await _ui.settle()
	_check("Home starts a real flight for the pause guard", _app.flight != null)
	var calls_before := _restart_calls.size()
	_app._request_graphics_restart(profile)
	_check("real flight refuses graphics restart", _restart_calls.size() == calls_before)
	await _ui.tap(KEY_ESCAPE)
	await _ui.settle()
	_check("real flight opens Pause", _app.screens.is_top("pause") and _app.flight != null)
	_app.pause_menu.settings_button.grab_focus()
	await _ui.tap(KEY_ENTER)
	await _ui.settle()
	_settings = _app.screens.get_screen("settings") as CanvasLayer
	_settings._show_category(3)
	await _ui.settle()
	_check("Settings opened from Pause disables graphics restart", _settings._graphics_restart_button.disabled)
	_check("Pause restart tooltip explains the Home requirement",
		_settings._graphics_restart_button.tooltip_text == "End your flight and return Home to change graphics mode.")
	_settings.close()
	await _ui.settle()
	_app.end_flight()
	await _ui.settle()
	_check("ending the test flight returns safely to Home", _app.flight == null and _app.screens.is_top("home"))


func _record_restart(profile: String) -> void:
	_restart_calls.append(profile)
	if _settings == null or _app == null:
		return
	_restart_observation = {
		"profile": profile,
		"saved": _settings._saved.duplicate(true),
		"draft": _settings._draft.duplicate(true),
		"trial_deadline": _settings._trial_deadline_msec,
		"engine_max_fps": Engine.max_fps,
		"display_config": _app.display_preferences.config.duplicate(true),
		"general_file": FileAccess.get_file_as_string(PREFS),
		"display_file": FileAccess.get_file_as_string(PREFS + ".display"),
	}


func _cleanup_app() -> void:
	if _app != null and is_instance_valid(_app):
		if _app.flight != null and _app.has_home and _app.screens.is_top("pause"):
			_app.end_flight()
			await _ui.settle()
		await _ui.close_app(_app)
	_app = null


func _clean_preferences() -> void:
	for suffix: String in ["", ".bad", ".display", ".display.bad", ".controllers", ".legacy_rc"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS + suffix))


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
