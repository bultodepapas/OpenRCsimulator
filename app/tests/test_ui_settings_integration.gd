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

	# Open Settings with a real Enter event on Home's Settings button.
	app.home.settings_button.grab_focus()
	await ui.tap(KEY_ENTER)
	var settings: CanvasLayer = app.screens.get_screen("settings") as CanvasLayer
	await ui.settle()
	_check("Home Settings button opens the Settings screen", settings != null and app.screens.is_top("settings"))

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

	# Choose Spanish through the live language selector; the root persists it immediately and refreshes open screens.
	settings._language_picker.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.tap(KEY_DOWN) # Español
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("language selection updates the app and the open Settings screen",
		TranslationServer.get_locale() == "es" and app.preferences.language == "es"
		and settings._close_button.text == "Cerrar" and settings._window_picker.get_item_text(0) != "Windowed",
		"locale=%s, close=%s, mode=%s" % [TranslationServer.get_locale(), settings._close_button.text,
		settings._window_picker.get_item_text(0)])

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

	app.queue_free()
	await ui.settle()
	_clean_preferences()
	print("all Settings integration checks passed" if _failures == 0 else "%d Settings integration checks failed" % _failures)
	quit(0 if _failures == 0 else 1)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _clean_preferences() -> void:
	for path in [PREFS, PREFS + ".bad", PREFS + ".display", PREFS + ".display.bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
