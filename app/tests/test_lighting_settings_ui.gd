# FW-RGB-13: Aircraft lights category previews the global lighting policy and keeps reversible Settings semantics.
extends SceneTree

const DisplayPreferences := preload("res://app_state/display_preferences.gd")
const SettingsScreen := preload("res://ui/settings_screen.gd")
const ScreenTheme := preload("res://ui/ui_theme.gd")
const AircraftLightingPolicy := preload("res://render/lighting/lighting_policy.gd")
const AppRootScript := preload("res://app_root.gd")

const PREFS := "user://test_lighting_settings_ui.cfg"
const DISPLAY_PREFS := PREFS + ".display"
const CAPTURE_FILE_NAMES := [
	"aircraft-lights-1080p.png",
	"aircraft-lights-200-percent-focus.png",
]

var _checks := 0
var _failures := 0
var _presentations: Array[Dictionary] = []
var _capture_path := ""
var _lighting_category := -1
var _app: Node
var _settings: CanvasLayer
var _settings_viewport: SubViewport


class QuietAppRoot extends AppRootScript:
	func _ready() -> void:
		pass


func _initialize() -> void:
	await _run()
	await _cleanup()
	print("Aircraft lighting Settings checks=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _run() -> void:
	_clean_preferences()
	_capture_path = _capture_directory()
	_lighting_category = SettingsScreen.CATEGORIES.find("Lighting")
	_check("Aircraft lights category is registered", _lighting_category >= 0)
	_check("capture output guard permits ignored repo tmp/",
		_capture_path_allowed(ProjectSettings.globalize_path("res://../tmp/fw-rgb13-settings-ui")))
	_check("capture output guard rejects tracked repo paths",
		not _capture_path_allowed(ProjectSettings.globalize_path("res://../app/tests")))
	_check("capture output guard permits an external absolute directory",
		_capture_path_allowed(ProjectSettings.globalize_path("user://fw-rgb13-settings-ui")))

	var initial := DisplayPreferences.DEFAULTS.duplicate(true)
	initial.ui_scale = 2.0
	_check("200% display fixture saves", DisplayPreferences.save_to(DISPLAY_PREFS, initial) == OK)

	_settings_viewport = _make_viewport("LightingSettingsTestViewport")
	ScreenTheme.text_scale = 2.0
	_app = QuietAppRoot.new()
	_settings_viewport.add_child(_app)
	await process_frame
	_app.call("_apply_presentation", initial)
	var store := DisplayPreferences.new(DISPLAY_PREFS)
	_check("display preferences load the 200% focused-view fixture", store.config.ui_scale == 2.0)
	_check("AppRoot applies the Standard lighting defaults",
		AircraftLightingPolicy.quality == "standard"
		and not AircraftLightingPolicy.reduced_flashes
		and AircraftLightingPolicy.show_vfx)

	if store == null or _lighting_category < 0:
		return

	if not _capture_path.is_empty():
		await _capture_settings_views(store)

	_settings = SettingsScreen.new(store, "en")
	_settings_viewport.add_child(_settings)
	_settings.presentation_changed.connect(_capture_presentation)
	_settings.presentation_changed.connect(Callable(_app, "_apply_presentation"))
	await process_frame
	await process_frame
	_settings._show_category(_lighting_category)
	await process_frame
	await process_frame

	var selected: int = _settings._lighting_quality_picker.selected
	_check("quality opens at Standard with the default value",
		_settings._draft.aircraft_lighting_quality == "standard"
		and selected >= 0
		and _settings._lighting_quality_picker.get_item_metadata(selected) == "standard"
		and _settings._lighting_quality_picker.get_item_text(selected) == "Standard")
	_check("aircraft lights controls are on the selected category page",
		_settings._pages[_lighting_category].visible
		and _settings._lighting_quality_picker.get_parent().get_parent() == _settings._pages[_lighting_category]
		and _settings._lighting_vfx_toggle.get_parent().get_parent() == _settings._pages[_lighting_category]
		and _settings._lighting_flashes_toggle.get_parent().get_parent() == _settings._pages[_lighting_category])

	await _focus_in_scroll(_settings, _settings._lighting_quality_picker, "quality picker")
	await _focus_in_scroll(_settings, _settings._lighting_vfx_toggle, "show effects toggle")
	await _focus_in_scroll(_settings, _settings._lighting_flashes_toggle, "reduced flashes toggle")

	_choose_metadata(_settings._lighting_quality_picker, "high")
	_settings._lighting_vfx_toggle.button_pressed = false
	_settings._lighting_flashes_toggle.button_pressed = true
	await process_frame
	_check("control changes update the draft and emit full presentation configs",
		_settings._draft.aircraft_lighting_quality == "high"
		and not _settings._draft.aircraft_lighting_show_vfx
		and _settings._draft.aircraft_lighting_reduced_flashes
		and not _presentations.is_empty()
		and _presentations.back().aircraft_lighting_quality == "high"
		and _presentations.back().aircraft_lighting_show_vfx == false
		and _presentations.back().aircraft_lighting_reduced_flashes == true
		and _presentations.back().has("ui_scale"))
	_check("AppRoot applies the live aircraft-lighting policy",
		AircraftLightingPolicy.quality == "high"
		and AircraftLightingPolicy.reduced_flashes
		and not AircraftLightingPolicy.show_vfx
		and not AircraftLightingPolicy.effects_allowed())

	_settings._keep_button.pressed.emit()
	var reloaded := DisplayPreferences.new(DISPLAY_PREFS)
	_check("Keep saves and a new store reloads show-VFX and reduced-flashes choices",
		reloaded.config.aircraft_lighting_quality == "high"
		and reloaded.config.aircraft_lighting_show_vfx == false
		and reloaded.config.aircraft_lighting_reduced_flashes == true)

	_choose_metadata(_settings._lighting_quality_picker, "low")
	_settings._lighting_vfx_toggle.button_pressed = true
	_settings._lighting_flashes_toggle.button_pressed = false
	await process_frame
	_settings._revert_button.pressed.emit()
	await process_frame
	_check("Revert restores the kept values, controls, and live policy",
		_settings._draft.aircraft_lighting_quality == "high"
		and not _settings._lighting_vfx_toggle.button_pressed
		and _settings._lighting_flashes_toggle.button_pressed
		and _settings._lighting_quality_picker.get_item_metadata(_settings._lighting_quality_picker.selected) == "high"
		and AircraftLightingPolicy.quality == "high"
		and not AircraftLightingPolicy.show_vfx
		and AircraftLightingPolicy.reduced_flashes
		and _presentation_matches_saved())

	_settings._lighting_quality_picker.grab_focus()
	var defaults_button := _settings.find_child("AircraftLightingDefaults", true, false) as Button
	_check("Restore lighting defaults control exists", defaults_button != null)
	if defaults_button != null:
		defaults_button.pressed.emit()
	await process_frame
	_check("Restore lighting defaults previews Standard product policy",
		_settings._draft.aircraft_lighting_quality == "standard"
		and _settings._draft.aircraft_lighting_show_vfx
		and not _settings._draft.aircraft_lighting_reduced_flashes
		and AircraftLightingPolicy.quality == "standard"
		and AircraftLightingPolicy.show_vfx
		and not AircraftLightingPolicy.reduced_flashes)

	_choose_metadata(_settings._lighting_quality_picker, "low")
	_settings._lighting_vfx_toggle.button_pressed = false
	await process_frame
	var close_events: Array[bool] = []
	_settings.closed.connect(func() -> void: close_events.append(true))
	_settings._close_button.pressed.emit()
	await process_frame
	_check("Close emits closed, restores the kept presentation, and leaves saved data unchanged",
		close_events.size() == 1
		and _settings._draft.aircraft_lighting_quality == "high"
		and not _settings._draft.aircraft_lighting_show_vfx
		and _settings._draft.aircraft_lighting_reduced_flashes
		and _presentation_matches_saved()
		and DisplayPreferences.load_from(DISPLAY_PREFS).aircraft_lighting_quality == "high"
		and AircraftLightingPolicy.quality == "high"
		and not AircraftLightingPolicy.show_vfx
		and AircraftLightingPolicy.reduced_flashes,
		"closed=%d draft=(%s,%s,%s) latest=%s saved=%s policy=(%s,%s,%s)" % [
		close_events.size(), str(_settings._draft.aircraft_lighting_quality), str(_settings._draft.aircraft_lighting_show_vfx),
		str(_settings._draft.aircraft_lighting_reduced_flashes), str(_presentations.back() if not _presentations.is_empty() else {}),
		str(DisplayPreferences.load_from(DISPLAY_PREFS)), str(AircraftLightingPolicy.quality),
		str(AircraftLightingPolicy.show_vfx), str(AircraftLightingPolicy.reduced_flashes)])


func _capture_settings_views(store: DisplayPreferences) -> void:
	var previous_scale := ScreenTheme.text_scale
	var category_index := _lighting_category

	ScreenTheme.text_scale = 1.0
	var standard_viewport := _make_viewport("LightingSettings1080Capture")
	var standard_screen := SettingsScreen.new(store, "en")
	standard_viewport.add_child(standard_screen)
	standard_screen._show_category(category_index)
	await _settle_render()
	_save_capture(standard_viewport, CAPTURE_FILE_NAMES[0])
	standard_screen.queue_free()
	standard_viewport.queue_free()
	await process_frame

	ScreenTheme.text_scale = 2.0
	var enlarged_viewport := _make_viewport("LightingSettings200Capture")
	var enlarged_screen := SettingsScreen.new(store, "en")
	enlarged_viewport.add_child(enlarged_screen)
	enlarged_screen._show_category(category_index)
	await process_frame
	await process_frame
	await _focus_in_scroll(enlarged_screen, enlarged_screen._lighting_flashes_toggle, "capture focus")
	await _settle_render()
	_save_capture(enlarged_viewport, CAPTURE_FILE_NAMES[1])
	enlarged_screen.queue_free()
	enlarged_viewport.queue_free()
	await process_frame
	ScreenTheme.text_scale = previous_scale


func _focus_in_scroll(screen: CanvasLayer, control: Control, label: String) -> void:
	control.grab_focus()
	await process_frame
	await process_frame
	var scroll := screen.get("_scroll") as ScrollContainer
	var view_rect := scroll.get_global_rect() if scroll != null else Rect2()
	var control_rect := control.get_global_rect()
	var focus_owner := control.get_viewport().gui_get_focus_owner()
	_check("200%% focus reveals the complete %s inside Settings scroll" % label,
		scroll != null and scroll.follow_focus and focus_owner == control and view_rect.encloses(control_rect),
		"scroll=%s control=%s focus=%s" % [str(view_rect), str(control_rect), str(focus_owner)])


func _choose_metadata(picker: OptionButton, value: Variant) -> void:
	for index: int in picker.item_count:
		if picker.get_item_metadata(index) != value:
			continue
		picker.select(index)
		picker.item_selected.emit(index)
		return
	_check("picker offers metadata %s" % str(value), false, "metadata=%s" % str(_picker_metadata(picker)))


func _picker_metadata(picker: OptionButton) -> Array:
	var values: Array = []
	for index: int in picker.item_count:
		values.append(picker.get_item_metadata(index))
	return values


func _presentation_matches_saved() -> bool:
	if _presentations.is_empty():
		return false
	var saved := DisplayPreferences.load_from(DISPLAY_PREFS)
	var latest: Dictionary = _presentations.back()
	return (
		latest.aircraft_lighting_quality == saved.aircraft_lighting_quality
		and latest.aircraft_lighting_show_vfx == saved.aircraft_lighting_show_vfx
		and latest.aircraft_lighting_reduced_flashes == saved.aircraft_lighting_reduced_flashes
	)


func _capture_presentation(config: Dictionary) -> void:
	_presentations.append(config.duplicate(true))


func _make_viewport(viewport_name: String) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = viewport_name
	viewport.size = Vector2i(1920, 1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	return viewport


func _settle_render() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw


func _save_capture(viewport: SubViewport, filename: String) -> void:
	var image: Image = viewport.get_texture().get_image()
	_check("capture %s is 1920x1080" % filename,
		image != null and image.get_width() == 1920 and image.get_height() == 1080,
		"image=%s" % str(image.get_size() if image != null else Vector2i.ZERO))
	if image == null or image.get_width() != 1920 or image.get_height() != 1080:
		return
	var path := _capture_path.path_join(filename)
	_check("capture writes to an allowed output directory", image.save_png(path) == OK, path)


func _capture_directory() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--capture-lighting-settings="):
			continue
		if DisplayServer.get_name() == "headless":
			print("--capture-lighting-settings skipped: headless display")
			return ""
		var path := argument.trim_prefix("--capture-lighting-settings=").strip_edges()
		if not _capture_path_allowed(path):
			_fail("capture requires an absolute directory under ignored repo tmp/ or outside the repository")
			return ""
		var normalized := path.replace("\\", "/").simplify_path()
		for filename: String in CAPTURE_FILE_NAMES:
			if FileAccess.file_exists(normalized.path_join(filename)):
				_fail("capture refuses to overwrite %s" % normalized.path_join(filename))
				return ""
		var error := DirAccess.make_dir_recursive_absolute(normalized)
		if error != OK:
			_fail("could not create capture directory: %s (%s)" % [normalized, error_string(error)])
			return ""
		return normalized
	return ""


static func _capture_path_allowed(path: String) -> bool:
	var normalized := path.replace("\\", "/").simplify_path().to_lower()
	var repository := ProjectSettings.globalize_path("res://../").replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	var inside_repository := normalized == repository or normalized.begins_with(repository + "/")
	var ignored_tmp := repository + "/tmp"
	var inside_ignored_tmp := normalized == ignored_tmp or normalized.begins_with(ignored_tmp + "/")
	return path.is_absolute_path() and (not inside_repository or inside_ignored_tmp)


func _cleanup() -> void:
	ScreenTheme.text_scale = 1.0
	if is_instance_valid(_app):
		_app.call("_apply_presentation", DisplayPreferences.DEFAULTS.duplicate(true))
	if is_instance_valid(_settings):
		_settings.queue_free()
	if is_instance_valid(_settings_viewport):
		_settings_viewport.queue_free()
	if is_instance_valid(_app):
		_app.queue_free()
	await process_frame
	AircraftLightingPolicy.apply(DisplayPreferences.DEFAULTS)
	_clean_preferences()


func _clean_preferences() -> void:
	for path: String in [
		PREFS, PREFS + ".bad", DISPLAY_PREFS, DISPLAY_PREFS + ".bad",
		PREFS + ".controllers", PREFS + ".legacy_rc",
	]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _fail(message: String) -> void:
	_failures += 1
	printerr("FAIL %s" % message)


func _check(label: String, passed: bool, detail := "") -> void:
	_checks += 1
	if passed:
		return
	_failures += 1
	printerr("FAIL %s %s" % [label, detail])
