# UI-35 (UI-30 audit VC-1, VC-3, VC-5, SP-3, SC-5, AL-3, AL-4): dialogs share one state language and keep drafts safe.
# Real key events on the production shell with isolated preferences.
# Run: godot --headless --path . --audio-driver Dummy --script res://tests/test_ui_modal_consistency.gd
extends SceneTree

const UiDriver := preload("res://tests/ui_driver.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const NaturalRandomScreen := preload("res://ui/natural_random_screen.gd")
const PREFS := "user://test_ui_modal_consistency.cfg"

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
	await _run()
	print("UI modal consistency: %d failed" % _failures)
	quit(1 if _failures else 0)


func _run() -> void:
	TranslationServer.set_locale("en")
	# --- VC-3: one toggle language, a visible slider focus and themed scrollbars.
	var theme: Theme = UiTheme.build()
	_check("switches and check boxes have themed icons", theme.has_icon("checked", "CheckButton")
		and theme.has_icon("unchecked_disabled", "CheckButton") and theme.has_icon("checked", "CheckBox")
		and theme.has_icon("unchecked", "CheckBox"))
	_check("sliders show the shared focus outline", theme.get_stylebox("focus", "HSlider") == theme.get_stylebox("focus", "Button"))
	var grabber := theme.get_stylebox("grabber_pressed", "VScrollBar") as StyleBoxFlat
	_check("scrollbars use the theme accent", grabber != null and grabber.bg_color == UiTheme.FOCUS)

	# --- VC-5: one error colour.
	var briefing := NaturalRandomScreen.new()
	_check("Natural Random errors use the error style", briefing.error_label.theme_type_variation == "ErrorLabel")
	briefing.free()

	for suffix in ["", ".display", ".controllers", ".controllers.rollback", ".legacy_rc"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS + suffix))
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	root.size = Vector2i(1920, 1080)
	for frame in 4: await process_frame

	# --- AL-4: Settings opens on its first category.
	app.open_settings(app.home.settings_button)
	await ui.settle()
	var settings: Node = app.screens.top()
	_check("Settings starts on its first category", app.screens.is_top("settings")
		and root.gui_get_focus_owner() == settings._category_buttons[0], ui.focus_name())
	await ui.tap(KEY_ESCAPE)
	await ui.settle()

	# --- VC-1, VC-5, SP-3: Conditions commits with the primary action, shows errors as errors and uses its height.
	app.open_weather(app.home.weather_button)
	for frame in 6: await process_frame
	var dialog: CanvasLayer = app.weather_dialog
	_check("Conditions Apply is the primary action", dialog != null and dialog.apply_button.theme_type_variation == "PrimaryButton")
	_check("Conditions errors use the error style", dialog != null and dialog.error_label.theme_type_variation == "ErrorLabel")
	_check("the wind page fits at 1080p without scrolling", dialog != null and not dialog.tab_scroll.get_v_scroll_bar().visible,
		"body=%s page=%s" % [dialog.tab_scroll.size, dialog.tab_scroll.get_child(0).get_combined_minimum_size()] if dialog != null else "")

	# --- SC-5: Escape while typing ends the edit; only the next Escape cancels the dialog.
	var field: LineEdit = null
	if dialog != null:
		for candidate: LineEdit in dialog.find_children("*", "LineEdit", true, false):
			if candidate.is_visible_in_tree() and candidate.editable:
				field = candidate
				break
	_check("Conditions has a visible numeric field", field != null)
	if field != null:
		field.grab_focus()
		field.edit()
		await ui.tap(KEY_ESCAPE)
		await ui.settle()
		_check("Escape in an editing field keeps the dialog open", app.screens.is_top("weather") and not field.is_editing())
		await ui.tap(KEY_ESCAPE)
		await ui.settle()
		_check("the next Escape cancels the dialog", app.screens.is_top("home"))
	app.queue_free()
	await ui.settle()
	for suffix in ["", ".display", ".controllers", ".controllers.rollback", ".legacy_rc"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS + suffix))
