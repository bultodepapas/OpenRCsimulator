# UI-24 / VQ-06b: real settings transaction, native resolution recovery and EN/ES layout.
# Native optional captures: -- --graphics-captures=<new directory>
extends SceneTree

const UiDriver := preload("res://tests/ui_driver.gd")
const DisplayPreferences := preload("res://app_state/display_preferences.gd")
const Reconstruction := preload("res://render/reconstruction.gd")
const NvidiaReflex := preload("res://render/nvidia_reflex.gd")
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
	var reflex_status := NvidiaReflex.describe(str(settings._draft.nvidia_reflex))
	_check("Reflex default remains selected even when unsupported",
		settings._reflex_picker.get_item_metadata(settings._reflex_picker.selected) == "on")
	for index: int in settings._reflex_picker.item_count:
		var mode := str(settings._reflex_picker.get_item_metadata(index))
		_check("Reflex option follows reported capability: " + mode,
			settings._reflex_picker.is_item_disabled(index) == not NvidiaReflex.option_status(mode, reflex_status).available)
	settings._reflex_picker.select(0)
	settings._reflex_picker.item_selected.emit(0)
	_check("Reflex preview starts recovery and leaves saved On untouched", settings._draft.nvidia_reflex == "off"
		and settings._trial_deadline_msec > Time.get_ticks_msec()
		and DisplayPreferences.load_from(PREFS + ".display").nvidia_reflex == "on"
		and Reconstruction.describe(root).nvidia_reflex.requested == "off")
	settings._revert()
	_check("Reflex revert restores the prior request", settings._draft.nvidia_reflex == "on"
		and Reconstruction.describe(root).nvidia_reflex.requested == "on")
	settings._reflex_picker.select(0)
	settings._reflex_picker.item_selected.emit(0)
	settings.keep_changes()
	_check("Keep saves the Reflex request", DisplayPreferences.load_from(PREFS + ".display").nvidia_reflex == "off")
	settings._restore_graphics_defaults()
	settings.keep_changes()
	_check("graphics defaults restore Reflex On", DisplayPreferences.load_from(PREFS + ".display").nvidia_reflex == "on")
	settings._vsync_picker.select(1)
	settings._vsync_picker.item_selected.emit(1)
	await ui.settle()
	if DisplayServer.get_name() != "headless":
		print("requested VSync off; platform effective mode: ", DisplayServer.window_get_vsync_mode())
		var effective_vsync := tr("On") if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED else tr("Off")
		_check("effective VSync is visible to the player", settings._graphics_info.text.contains(
			tr("Output: %d × %d · VSync: %s") % [root.size.x, root.size.y, effective_vsync]))
	settings._msaa_picker.select(3)
	settings._msaa_picker.item_selected.emit(3)
	_check("8x MSAA reaches the real viewport", root.msaa_3d == Viewport.MSAA_8X)
	var reconstruction_caps := Reconstruction.runtime_capabilities()
	_check("reconstruction menu follows active High renderer", settings._reconstruction_picker.disabled == not reconstruction_caps.high)
	_check("1080p help compares Quality and Performance input sizes",
		settings._reconstruction_picker.tooltip_text.contains("1280 × 720")
		and settings._reconstruction_picker.tooltip_text.contains("960 × 540")
		and settings._reconstruction_picker.tooltip_text.contains("Quality keeps more input detail"))
	for index: int in settings._reconstruction_picker.item_count:
		var mode := str(settings._reconstruction_picker.get_item_metadata(index))
		var option := Reconstruction.option_status(mode, reconstruction_caps)
		_check("reconstruction option availability is provider-specific: " + mode,
			settings._reconstruction_picker.is_item_disabled(index) == not bool(option.available))
	var saved_reconstruction := str(settings._draft.reconstruction)
	settings._draft.reconstruction = "native"
	settings._sync_controls()
	_check("Native disables FSR sharpness and explains the saved value",
		not settings._fsr2_sharpness_slider.editable
		and settings._fsr2_sharpness_slider.focus_mode == Control.FOCUS_NONE
		and settings._fsr2_sharpness_slider.tooltip_text.contains("does not use FSR sharpness")
		and settings._fsr2_sharpness_slider.tooltip_text.contains("saved value is kept"))
	settings._draft.reconstruction = "dlss_quality"
	settings._on_graphics_option_changed()
	settings._refresh_graphics_info()
	var dlss_policy := Reconstruction.resolve("dlss_quality", reconstruction_caps)
	_check("DLSS preference remains selected regardless of availability",
		settings._reconstruction_picker.get_item_metadata(settings._reconstruction_picker.selected) == "dlss_quality")
	_check("DLSS sharpness slider stays disabled and explains its saved FSR value",
		not settings._fsr2_sharpness_slider.editable
		and settings._fsr2_sharpness_slider.focus_mode == Control.FOCUS_NONE
		and settings._fsr2_sharpness_slider.tooltip_text.contains(
			"inactive while Native is active" if dlss_policy.fallback else "DLSS controls its own reconstruction sharpness")
		and settings._fsr2_sharpness_slider.tooltip_text.contains("FSR2 or FSR3"))
	var current_output := settings.get_viewport().get_visible_rect().size
	var expected_dimensions := "%d × %d" % [roundi(current_output.x), roundi(current_output.y)]
	_check("graphics status shows requested and effective providers",
		settings._graphics_info.text.contains(tr("Reconstruction: Requested %s → Active %s")
			% [tr("DLSS · Quality"), tr("Native") if dlss_policy.fallback else tr("DLSS · Quality")]))
	_check("graphics status shows the current 3D input and output sizes",
		settings._graphics_info.text.contains(expected_dimensions))
	_check("unsupported provider explanation names the actual graphics limitation in player language",
		settings._reconstruction_unavailable_text("fsr3", "fsr3_support_missing").contains("game build")
		and not settings._reconstruction_unavailable_text("fsr3", "fsr3_support_missing").contains("native extension"))
	_check("FSR3 runtime rollback is described as a runtime failure",
		settings._reconstruction_unavailable_text("fsr3", "fsr3_runtime_failure").contains("could not continue")
		and not settings._reconstruction_unavailable_text("fsr3", "fsr3_runtime_failure").contains("does not report"))
	# Exercise a real viewport fallback receipt even on a DLSS-capable test device.
	var unavailable_caps := reconstruction_caps.duplicate(true)
	unavailable_caps.dlss = false
	Reconstruction.apply(root, settings._draft, unavailable_caps)
	settings._refresh_graphics_info()
	_check("fallback status says Native is active and the saved request is kept",
		settings._graphics_info.text.contains("Native rendering is active")
		and settings._graphics_info.text.contains("saved choice"))
	settings._draft.reconstruction = saved_reconstruction
	Reconstruction.apply(root, settings._draft)
	settings._sync_controls()
	settings._reconstruction_picker.select(3)
	settings._reconstruction_picker.item_selected.emit(3)
	settings._fsr2_sharpness_slider.value = 0.35
	_check("sharpening preview reaches viewport without saving", is_equal_approx(root.fsr_sharpness, 1.3)
		and DisplayPreferences.load_from(PREFS + ".display").fsr2_sharpness == 0.9)
	var fsr2_policy := Reconstruction.resolve("fsr2_quality", reconstruction_caps)
	_check("sharpening UI follows the effective FSR provider", settings._fsr2_sharpness_slider.editable
		== (reconstruction_caps.high and fsr2_policy.provider in ["fsr2", "fsr3"]))
	settings._fsr2_sharpness_slider.drag_started.emit()
	settings._fsr2_sharpness_slider.value = 0.5
	settings._fsr2_sharpness_slider.value = 0.6
	_check("drag updates its label without reconfiguring the renderer", is_equal_approx(root.fsr_sharpness, 1.3)
		and settings._fsr2_sharpness_value.text == "60 %")
	settings._fsr2_sharpness_slider.drag_ended.emit(true)
	_check("release applies the final sharpening preview", is_equal_approx(root.fsr_sharpness, 0.8))
	_check("reconstruction preview starts recovery without saving", settings._trial_deadline_msec > Time.get_ticks_msec()
		and DisplayPreferences.load_from(PREFS + ".display").reconstruction == "native")
	_check("FSR2 activates only when its provider is available and preserves saved MSAA choice", settings._draft.msaa_3d == 3
		and root.scaling_3d_mode == int(fsr2_policy.scaling_3d_mode)
		and root.msaa_3d == (Viewport.MSAA_DISABLED if fsr2_policy.temporal else Viewport.MSAA_8X))
	settings._trial_deadline_msec = Time.get_ticks_msec() - 1
	settings._process(0.0)
	_check("FSR2 timeout restores native resolution and saved MSAA", root.scaling_3d_scale == 1.0
		and root.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR and root.msaa_3d == Viewport.MSAA_4X)
	_check("timeout restores sharpening and disables slider", is_equal_approx(root.fsr_sharpness, 0.2)
		and not settings._fsr2_sharpness_slider.editable)
	for index: int in settings._reconstruction_picker.item_count:
		settings._reconstruction_picker.select(index)
		settings._reconstruction_picker.item_selected.emit(index)
		await ui.settle()
		var mode: String = settings._reconstruction_picker.get_item_metadata(index)
		_check("live reconstruction switch: " + mode, is_equal_approx(root.scaling_3d_scale,
			Reconstruction.resolve(mode, Reconstruction.runtime_capabilities()).scale))
	settings._revert()
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
				if category == 3:
					settings._reconstruction_picker.select(2) # Custom 85% candidate, including captures.
					settings._reconstruction_picker.item_selected.emit(2)
					settings._fsr2_sharpness_slider.value = 0.35
					await ui.settle()
					_check("sharpening slider has usable width", settings._fsr2_sharpness_slider.size.x >= 100.0)
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
	settings._reconstruction_picker.select(3)
	settings._reconstruction_picker.item_selected.emit(3)
	settings._fsr2_sharpness_slider.value = 0.0
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
		int(Reconstruction.resolve("fsr2_quality", Reconstruction.runtime_capabilities()).scaling_3d_mode))
	_check("shell relaunch preserves disabled sharpening", root.fsr_sharpness == 2.0
		and DisplayPreferences.load_from(PREFS + ".display").fsr2_sharpness == 0.0)
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
