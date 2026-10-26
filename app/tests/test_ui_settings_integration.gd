# UI-24 integration: Settings opens from Home and Pause, previews remain live until Revert/Keep,
# nested routes restore focus and never release a paused flight. Run headless with --audio-driver Dummy.
extends SceneTree

const UiDriver := preload("res://tests/ui_driver.gd")
const Preferences := preload("res://app_state/preferences.gd")
const DisplayPreferences := preload("res://app_state/display_preferences.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const PREFS := "user://test_ui_settings_integration.cfg"

var _failures := 0
var ui: RefCounted
var app: Node


func _initialize() -> void:
	ui = UiDriver.new(self)
	_run()


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _run() -> void:
	TranslationServer.set_locale("en")
	_clean_preferences()
	var preferences: Dictionary = Preferences.DEFAULTS.duplicate(true)
	preferences.first_flight_hint_seen = true
	_check("isolated preferences prepared", Preferences.save_to(PREFS, preferences) == OK)

	app = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	_check("app opens at Home", app.home != null and app.screens.is_top("home"))
	_check("Home opens without an automatic sound", app.menu_audio.cue_count(&"accept") == 0
		and app.menu_audio.cue_count(&"focus") == 0)

	# Open Settings with a real Enter event on Home's Settings button.
	app.home.settings_button.grab_focus()
	await ui.tap(KEY_ENTER)
	var settings: CanvasLayer = app.screens.get_screen("settings") as CanvasLayer
	await ui.settle()
	_check("Home Settings button opens the Settings screen", settings != null and app.screens.is_top("settings"))
	_check("opening Settings emits one open and no automatic press", app.menu_audio.cue_count(&"open") == 1
		and app.menu_audio.cue_count(&"press") == 0)
	settings._category_buttons[2].grab_focus()
	await ui.tap(KEY_ENTER)
	var home_theme_before_volume: Theme = app.home.theme
	var settings_theme_before_volume: Theme = settings._surface.theme
	settings._volume_slider.grab_focus()
	await ui.tap(KEY_HOME)
	await ui.settle()
	_check("keyboard volume preview mutes the live service without saving", app.menu_audio.get_volume() == 0.0
		and DisplayPreferences.load_from(PREFS + ".display").menu_volume == DisplayPreferences.DEFAULTS.menu_volume)
	_check("volume preview preserves both existing themes", app.home.theme == home_theme_before_volume
		and settings._surface.theme == settings_theme_before_volume)
	home_theme_before_volume = null
	settings_theme_before_volume = null
	settings._revert_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("Revert restores live menu volume", is_equal_approx(app.menu_audio.get_volume(), DisplayPreferences.DEFAULTS.menu_volume))
	_check("reverting previews has cancellation feedback", app.menu_audio.cue_count(&"cancel") == 1)
	# A failed disk transaction must never sound like a successful Keep.
	settings._volume_changed(0.55)
	app.display_preferences.writable = false
	await process_frame
	var rejected_before: int = app.menu_audio.cue_count(&"reject")
	var saved_before: int = app.menu_audio.cue_count(&"saved")
	settings.keep_changes()
	_check("failed Keep sounds an error and leaves the preview unsaved",
		app.menu_audio.cue_count(&"reject") == rejected_before + 1
		and app.menu_audio.cue_count(&"saved") == saved_before and settings._draft != settings._saved)
	app.display_preferences.writable = true
	await process_frame
	settings.keep_changes()
	_check("successful retry sounds saved only after persistence",
		app.menu_audio.cue_count(&"saved") == saved_before + 1
		and is_equal_approx(DisplayPreferences.load_from(PREFS + ".display").menu_volume, 0.55))
	await process_frame
	settings._volume_changed(DisplayPreferences.DEFAULTS.menu_volume)
	settings.keep_changes()
	# AUD-12b: the game volume drives the Master bus live, through the real app presentation path.
	var master_bus: int = AudioServer.get_bus_index(&"Master")
	settings._master_slider.grab_focus()
	await ui.tap(KEY_HOME)
	await ui.settle()
	_check("keyboard game volume preview mutes Master without saving", AudioServer.is_bus_mute(master_bus)
		and DisplayPreferences.load_from(PREFS + ".display").master_volume == DisplayPreferences.DEFAULTS.master_volume)
	settings._revert_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("Revert restores the live Master level", not AudioServer.is_bus_mute(master_bus)
		and AudioServer.get_bus_volume_db(master_bus) == 0.0)
	settings._category_buttons[0].grab_focus()
	await ui.tap(KEY_ENTER)

	# Real keyboard selection reaches the advanced tab and modifies the live renderer.
	settings._category_buttons[3].grab_focus()
	await ui.tap(KEY_ENTER)
	settings._fps_picker.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.tap(KEY_DOWN) # 30 FPS
	await ui.tap(KEY_ENTER)
	_check("advanced FPS selection applies live without saving", Engine.max_fps == 30
		and DisplayPreferences.load_from(PREFS + ".display").max_fps == 0)
	settings._msaa_picker.select(0)
	settings._msaa_picker.item_selected.emit(0)
	_check("MSAA preview changes the flight viewport", root.msaa_3d == Viewport.MSAA_DISABLED)
	settings._revert_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("Revert restores live FPS and MSAA", Engine.max_fps == 0 and root.msaa_3d == Viewport.MSAA_4X)
	settings._category_buttons[0].grab_focus()
	await ui.tap(KEY_ENTER)

	# The 125% selector is driven through its real OptionButton popup. Theme font sizes are resolved on the
	# Home and Settings controls after the root applies its presentation signal.
	var home_font_before: int = app.home.fly_button.get_theme_font_size("font_size", "PrimaryButton")
	var settings_font_before: int = settings._close_button.get_theme_font_size("font_size", "Button")
	settings._scale_picker.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.tap(KEY_DOWN) # 125%
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("125% changes resolved theme font sizes and leaves Settings open",
		app.screens.is_top("settings") and is_equal_approx(UiTheme.text_scale, 1.25)
		and app.home.fly_button.get_theme_font_size("font_size", "PrimaryButton") > home_font_before
		and settings._close_button.get_theme_font_size("font_size", "Button") > settings_font_before,
		"scale=%.2f, Home font=%d->%d, Settings font=%d->%d" % [UiTheme.text_scale, home_font_before,
		app.home.fly_button.get_theme_font_size("font_size", "PrimaryButton"), settings_font_before,
		settings._close_button.get_theme_font_size("font_size", "Button")])
	settings._revert_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("Revert restores the saved font scale and keeps Settings open",
		app.screens.is_top("settings") and is_equal_approx(UiTheme.text_scale, 1.0)
		and app.home.fly_button.get_theme_font_size("font_size", "PrimaryButton") == home_font_before
		and is_equal_approx(DisplayPreferences.load_from(PREFS + ".display").ui_scale, 1.0))

	# Audio/motion changes must not invalidate unrelated visuals, but opacity still does.
	var home_theme_before_motion: Theme = app.home.theme
	settings._motion_toggle.button_pressed = true
	await ui.settle()
	_check("motion policy updates without rebuilding Home's theme", UiTheme.reduced_motion
		and app.home.theme == home_theme_before_motion)
	settings._opaque_toggle.button_pressed = true
	await ui.settle()
	_check("opacity still replaces themes and updates Home scrims", UiTheme.opaque_panels
		and app.home.theme != home_theme_before_motion
		and is_equal_approx(app.home._rail_scrim.texture.gradient.get_color(0).a, 1.0))
	home_theme_before_motion = null
	settings._revert()
	await ui.settle()
	_check("Revert restores translucent scrims and motion policy", not UiTheme.opaque_panels
		and not UiTheme.reduced_motion
		and is_equal_approx(app.home._rail_scrim.texture.gradient.get_color(0).a, 0.92))

	# Choose Spanish through the live language selector; the root persists it immediately and refreshes open screens.
	settings._category_buttons[1].grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	settings._language_picker.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.tap(KEY_DOWN) # Español
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("language selection updates the app and the open Settings screen",
		TranslationServer.get_locale() == "es" and app.preferences.language == "es"
		and settings._window_picker.get_item_text(0) == "En ventana"
		and settings._close_button.text == "Cerrar"
		and settings._status.text == "Cambios revertidos. Se restauraron los ajustes guardados.",
		"locale=%s, close=%s, status=%s, mode=%s" % [TranslationServer.get_locale(), settings._close_button.text,
		settings._status.text, settings._window_picker.get_item_text(0)])

	_check("Settings offers Chinese as its third language", settings._language_picker.item_count == 3
		and settings._language_picker.get_item_text(2) == "简体中文"
		and settings._language_picker.get_item_metadata(2) == "zh_Hans")
	settings._language_picker.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.tap(KEY_DOWN)
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("Chinese selection refreshes open Settings and persists", TranslationServer.get_locale() == "zh_Hans"
		and Preferences.load_from(PREFS).language == "zh_Hans" and settings._close_button.text == "关闭"
		and app.home.language_button.text == "语言：简体中文")
	# Return to Spanish for the existing nested-screen and pause checks.
	settings._language_picker.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.tap(KEY_UP)
	await ui.tap(KEY_ENTER)
	await ui.settle()

	# Controls and Help are nested on the same stack; Esc returns to Settings after either route.
	var controls_button: Button = settings.find_child("Controls", true, false) as Button
	controls_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("Controls opens above Settings", app.screens.is_top("controls") and app.screens.get_screen("settings") == settings)
	await ui.tap(KEY_ESCAPE)
	_check("Esc from Controls returns to Settings", app.screens.is_top("settings")
		and root.gui_get_focus_owner() == controls_button)

	var about_button: Button = settings.find_child("HelpAbout", true, false) as Button
	about_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("Help/About opens above Settings", app.screens.is_top("help") and app.screens.get_screen("settings") == settings)
	await ui.tap(KEY_ESCAPE)
	_check("Esc from Help returns to Settings", app.screens.is_top("settings")
		and root.gui_get_focus_owner() == about_button)

	await ui.tap(KEY_ESCAPE)
	await ui.settle()
	_check("Esc closes Settings, restores Home focus, and keeps language", app.screens.is_top("home")
		and root.gui_get_focus_owner() == app.home.settings_button and TranslationServer.get_locale() == "es")

	# Start a real flight, pause it, then visit Settings and both nested routes. None may release the named menu hold.
	app.home.fly_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	var session: Node = app.flight.session
	await ui.tap(KEY_ESCAPE)
	await ui.settle()
	_check("flight opens Pause and holds the session", app.screens.is_top("pause") and session.holds.has("menu")
		and session.sim.paused)
	var held_tick: int = session.sim.tick
	app.pause_menu.settings_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("Pause Settings keeps the flight paused", app.screens.is_top("settings") and session.holds.has("menu")
		and session.sim.paused)

	settings = app.screens.get_screen("settings") as CanvasLayer
	settings._msaa_picker.select(1)
	settings._msaa_picker.item_selected.emit(1)
	settings.keep_changes()
	await ui.settle()
	_check("kept graphics change preserves the paused flight and tick", root.msaa_3d == Viewport.MSAA_2X
		and session.sim.paused and session.sim.tick == held_tick
		and DisplayPreferences.load_from(PREFS + ".display").msaa_3d == 1)
	settings._restore_graphics_defaults()
	settings.keep_changes()
	settings._category_buttons[1].grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	controls_button = settings.find_child("Controls", true, false) as Button
	controls_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	await _wait(0.2)
	_check("nested Controls keeps ticks held", app.screens.is_top("controls") and session.sim.tick == held_tick
		and session.holds.has("menu") and session.sim.paused)
	await ui.tap(KEY_ESCAPE)

	settings = app.screens.get_screen("settings") as CanvasLayer
	about_button = settings.find_child("HelpAbout", true, false) as Button
	about_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	await _wait(0.2)
	_check("nested Help keeps ticks held", app.screens.is_top("help") and session.sim.tick == held_tick
		and session.holds.has("menu") and session.sim.paused)
	await ui.tap(KEY_ESCAPE)

	await ui.tap(KEY_ESCAPE) # Settings closes to Pause; it must not resume the flight.
	await ui.settle()
	await _wait(0.2)
	_check("closing Settings returns to Pause without resuming or advancing ticks",
		app.screens.is_top("pause") and session.sim.tick == held_tick and session.holds.has("menu") and session.sim.paused)
	var accepted_before: int = app.menu_audio.cue_count(&"resume")
	var backs_before: int = app.menu_audio.cue_count(&"back")
	app.continue_flight()
	await ui.settle()
	_check("Resume emits its own cue and releases only through the explicit action", app.screens.top() == null
		and not session.sim.paused and app.menu_audio.cue_count(&"resume") == accepted_before + 1
		and app.menu_audio.cue_count(&"back") == backs_before)

	await ui.close_app(app)
	_clean_preferences()
	print("all Settings integration checks passed" if _failures == 0 else "%d Settings integration checks failed" % _failures)
	quit(0 if _failures == 0 else 1)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _clean_preferences() -> void:
	for path in [PREFS, PREFS + ".bad", PREFS + ".display", PREFS + ".display.bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
