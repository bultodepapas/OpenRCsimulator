# UI-24 / VQ-06b: real settings transaction, native resolution recovery and EN/ES layout.
# Native optional captures: -- --graphics-captures=<new directory>
extends SceneTree

const UiDriver := preload("res://tests/ui_driver.gd")
const DisplayPreferences := preload("res://app_state/display_preferences.gd")
const Reconstruction := preload("res://render/reconstruction.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const PREFS := "user://test_advanced_graphics_settings.cfg"
var failures := 0
var checks := 0
var captures := ""
var ui: RefCounted

func _initialize() -> void:
	ui = UiDriver.new(self)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--graphics-captures="):
			captures = arg.trim_prefix("--graphics-captures=")
	_run.call_deferred()

func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)
	else:
		print("ok   ", label)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		root.size = Vector2i(1280, 720)
	_clean()
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	if DisplayServer.get_name() != "headless":
		root.position = Vector2i(55, 85)
	app.open_settings()
	await ui.settle()
	var settings: CanvasLayer = app.screens.get_screen("settings")
	var initial_size := root.size
	var initial_position := root.position
	settings._resolution_picker.select(1)
	settings._resolution_picker.item_selected.emit(1)
	await ui.settle()
	_check("resolution starts recovery and is not saved", settings._trial_deadline_msec > Time.get_ticks_msec()
		and DisplayPreferences.load_from(PREFS + ".display").window_resolution == "auto")
	if DisplayServer.get_name() != "headless":
		_check("native resolution preview fits the desktop", root.mode == Window.MODE_WINDOWED
			and root.size.x <= 1280 and root.size.y <= 720)
	settings._resolution_picker.select(0)
	settings._resolution_picker.item_selected.emit(0)
	await ui.settle()
	if DisplayServer.get_name() != "headless":
		_check("selecting the saved option restores geometry before cancelling recovery", root.size == initial_size
			and root.position == initial_position and settings._trial_deadline_msec == 0)
	settings._resolution_picker.select(1)
	settings._resolution_picker.item_selected.emit(1)
	await ui.settle()
	settings._revert()
	await ui.settle()
	if DisplayServer.get_name() != "headless":
		_check("Revert restores automatic window dimensions", root.size == initial_size and root.position == initial_position)
	settings._window_mode_selected(1)
	await ui.settle()
	_check("fullscreen locks the window-size selector", settings._resolution_picker.disabled)
	if DisplayServer.get_name() != "headless":
		_check("native fullscreen is requested", root.mode == Window.MODE_FULLSCREEN)
	settings._trial_deadline_msec = Time.get_ticks_msec() - 1
	settings._process(0.0)
	await ui.settle()
	_check("fullscreen timeout restores the saved draft", settings._draft.window_mode == "windowed"
		and not settings._resolution_picker.disabled)
	if DisplayServer.get_name() != "headless":
		_check("fullscreen timeout restores native mode and size", root.mode == Window.MODE_WINDOWED and root.size == initial_size and root.position == initial_position)
	settings._vsync_picker.select(1)
	settings._vsync_picker.item_selected.emit(1)
	await ui.settle()
	if DisplayServer.get_name() != "headless":
		print("requested VSync off; platform effective mode: ", DisplayServer.window_get_vsync_mode())
		_check("effective VSync is visible to the player", settings._graphics_info.text.ends_with(tr("On"))
			or settings._graphics_info.text.ends_with(tr("Off")))
	settings._msaa_picker.select(3)
	settings._msaa_picker.item_selected.emit(3)
	_check("8x MSAA reaches the real viewport", root.msaa_3d == Viewport.MSAA_8X)
	_check("FSR2 availability follows native High", settings._reconstruction_picker.disabled == not Reconstruction.available())
	settings._reconstruction_picker.select(2)
	settings._reconstruction_picker.item_selected.emit(2)
	_check("reconstruction preview starts recovery without saving", settings._trial_deadline_msec > Time.get_ticks_msec()
		and DisplayPreferences.load_from(PREFS + ".display").reconstruction == "native")
	_check("FSR2 activates only in High and preserves saved MSAA choice", settings._draft.msaa_3d == 3
		and root.scaling_3d_mode == (Viewport.SCALING_3D_MODE_FSR2 if Reconstruction.available() else Viewport.SCALING_3D_MODE_BILINEAR)
		and root.msaa_3d == (Viewport.MSAA_DISABLED if Reconstruction.available() else Viewport.MSAA_8X))
	settings._trial_deadline_msec = Time.get_ticks_msec() - 1
	settings._process(0.0)
	_check("FSR2 timeout restores native resolution and saved MSAA", root.scaling_3d_scale == 1.0
		and root.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR and root.msaa_3d == Viewport.MSAA_4X)
	settings._vsync_picker.select(1)
	settings._vsync_picker.item_selected.emit(1)
	settings._msaa_picker.select(3)
	settings._msaa_picker.item_selected.emit(3)
	app.display_preferences.writable = false
	settings.keep_changes()
	_check("failed Keep preserves recovery and saved values", settings._trial_deadline_msec > Time.get_ticks_msec()
		and DisplayPreferences.load_from(PREFS + ".display").msaa_3d == 2)
	app.display_preferences.writable = true
	settings.keep_changes()
	settings.close()
	await ui.settle()
	app.open_settings()
	await ui.settle()
	settings = app.screens.get_screen("settings")
	_check("reopened settings keep accepted graphics values", settings._draft.msaa_3d == 3
		and settings._draft.vsync_mode == "disabled" and settings._trial_deadline_msec == 0)
	# A kept resolution becomes the next rollback checkpoint, including position.
	settings._resolution_picker.select(1)
	settings._resolution_picker.item_selected.emit(1)
	await ui.settle()
	settings.keep_changes()
	var kept_size := root.size
	var kept_position := root.position
	settings._resolution_picker.select(3)
	settings._resolution_picker.item_selected.emit(3)
	await ui.settle()
	settings._revert()
	await ui.settle()
	_check("Keep updates the geometry rollback checkpoint", root.size == kept_size and root.position == kept_position)
	settings._restore_graphics_defaults()
	settings.keep_changes()
	_check("restore defaults resets renderer and persistence", root.msaa_3d == Viewport.MSAA_4X
		and Engine.max_fps == 0 and DisplayPreferences.load_from(PREFS + ".display").vsync_mode == "enabled")
	if DisplayServer.get_name() != "headless":
		settings.close()
		await ui.settle()
		var normal_size := root.size
		var normal_position := root.position
		root.mode = Window.MODE_MAXIMIZED
		await create_timer(0.2).timeout
		app.open_settings()
		await ui.settle()
		settings = app.screens.get_screen("settings")
		settings._resolution_picker.select(3)
		settings._resolution_picker.item_selected.emit(3)
		await ui.settle()
		settings._revert()
		await ui.settle()
		_check("Revert restores a maximized window", root.mode == Window.MODE_MAXIMIZED)
		root.mode = Window.MODE_WINDOWED
		await create_timer(0.2).timeout
		_check("Restore Down retains the pre-preview normal rectangle", root.size == normal_size and root.position == normal_position)
		settings.close()
		await ui.settle()
		root.mode = Window.MODE_WINDOWED
		root.size = initial_size
		root.position = initial_position
		await ui.settle()
		app.open_settings()
		await ui.settle()
		settings = app.screens.get_screen("settings")
	if DisplayServer.get_name() != "headless":
		settings.close()
		await ui.settle()
		root.size = Vector2i(1100, 680)
		await ui.settle()
		app.open_settings()
		await ui.settle()
		settings = app.screens.get_screen("settings")
		settings._resolution_picker.select(0)
		settings._resolution_picker.item_selected.emit(0)
		await ui.settle()
		_check("Automatic preserves the manually resized window at transaction start", root.size == Vector2i(1100, 680))
		settings._revert()
		settings.close()
		await ui.settle()
		root.size = initial_size
		await ui.settle()
		app.open_settings()
		await ui.settle()
		settings = app.screens.get_screen("settings")
	for language: String in ["en", "es"]:
		app.set_language(language)
		for scale: float in [1.0, 2.0]:
			settings._draft.ui_scale = scale
			settings._on_presentation_option_changed()
			for category: int in [0, 3]:
				settings._show_category(category)
				await ui.settle()
				var bounds: Rect2 = settings._surface.get_global_rect()
				_check("%s %.0f%% category %d stays on screen" % [language, scale * 100, category],
					bounds.encloses(settings._layout_panel.get_global_rect())
					and bounds.encloses(settings._keep_button.get_global_rect()))
				for button: Button in settings._category_buttons:
					if button.is_visible_in_tree():
						_check("category button remains inside panel", settings._layout_panel.get_global_rect().encloses(button.get_global_rect()))
				if settings._category_picker.visible:
					_check("compact category selector stays on screen", bounds.encloses(settings._category_picker.get_global_rect()))
				_check("settings body remains usable", settings._scroll.size.y >= 60)
				if not captures.is_empty() and DisplayServer.get_name() != "headless":
					DirAccess.make_dir_recursive_absolute(captures)
					await RenderingServer.frame_post_draw
					_check("native capture saved", root.get_texture().get_image().save_png(captures.path_join("%s-%d-%d.png" % [language, int(scale * 100), category])) == OK)
	settings._revert()
	settings._fps_picker.select(2)
	settings._fps_picker.item_selected.emit(2)
	settings._msaa_picker.select(1)
	settings._msaa_picker.item_selected.emit(1)
	settings.keep_changes()
	settings.close()
	await ui.settle()
	await ui.close_app(app)
	# Recreate the actual shell with the same isolated store, not just a new settings dialog.
	app = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	_check("shell relaunch applies kept FPS and MSAA", Engine.max_fps == 60 and root.msaa_3d == Viewport.MSAA_2X)
	app.open_settings()
	await ui.settle()
	settings = app.screens.get_screen("settings")
	settings._reconstruction_picker.select(2)
	settings._reconstruction_picker.item_selected.emit(2)
	settings.keep_changes()
	settings.close()
	await ui.settle()
	_check("kept FSR2 preserves native MSAA preference", DisplayPreferences.load_from(PREFS + ".display").reconstruction == "fsr2_quality"
		and DisplayPreferences.load_from(PREFS + ".display").msaa_3d == 1)
	await ui.close_app(app)
	app = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	_check("shell relaunch applies FSR2 or safe native fallback", root.scaling_3d_mode ==
		(Viewport.SCALING_3D_MODE_FSR2 if Reconstruction.available() else Viewport.SCALING_3D_MODE_BILINEAR))
	await ui.close_app(app)
	Engine.max_fps = 0
	root.msaa_3d = Viewport.MSAA_4X
	UiTheme.text_scale = 1.0
	TranslationServer.set_locale("en")
	_clean()
	print("advanced graphics: %d checks, %d failed" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _clean() -> void:
	for suffix: String in ["", ".bad", ".display", ".display.bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS + suffix))
