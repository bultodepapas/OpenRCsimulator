extends SceneTree

const CompanionsDialog := preload("res://ui/companions_dialog.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const UiInput := preload("res://ui/ui_input.gd")
const NO_WRITE_PATH := "user://test_companions_dialog_preferences.cfg"
const DEFAULT_CONFIG := {"enabled": true, "count": 3, "seed": 1234567890,
	"engine_volume": 1.0, "show_labels": false, "label_distance_m": 250.0}

var _failures := 0
var _applied_payloads: Array[Dictionary] = []
var _close_requests := 0
var _remove_requests := 0
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
	print("Companions dialog: %d failed" % _failures)
	quit(1 if _failures else 0)


func _run() -> void:
	TranslationServer.set_locale("en")
	InputMap.load_from_project_settings()
	UiInput.set_gamepad(UiDriver.FAKE_DEVICE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NO_WRITE_PATH))
	root.size = Vector2i(1280, 720)
	var dialog := CompanionsDialog.new()
	dialog.applied.connect(_on_applied)
	dialog.close_requested.connect(_on_close_requested)
	dialog.removed.connect(_on_removed)
	dialog.configure({})
	root.add_child(dialog)
	await ui.settle()
	_check("new settings are Off with count 1 and seed 0",
		not dialog.enabled_check.button_pressed and dialog.count_picker.get_selected_id() == 1
		and dialog.seed_edit.text == "0")

	# Apply is a draft transaction. The controller's Accept button commits a valid selection.
	dialog.configure(DEFAULT_CONFIG)
	dialog.apply_button.grab_focus()
	await ui.joy_button(JOY_BUTTON_A)
	_check("controller Accept applies the selected settings once", _applied_payloads.size() == 1,
		str(_applied_payloads))
	_check("Apply emits the flight and presentation draft",
		_applied_payloads.size() == 1 and _applied_payloads[0] == DEFAULT_CONFIG,
		str(_applied_payloads))
	_applied_payloads.clear()

	# An invalid seed reports an error and leaves all typed controls untouched.
	dialog.configure(DEFAULT_CONFIG)
	dialog.seed_edit.text = "4294967296"
	dialog.apply_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("an out-of-range seed blocks Apply", _applied_payloads.is_empty() and dialog.error_label.visible)
	_check("invalid Apply preserves every control value",
		dialog.enabled_check.button_pressed and dialog.count_picker.get_selected_id() == 3
		and dialog.seed_edit.text == "4294967296",
		"enabled=%s count=%d seed=%s" % [dialog.enabled_check.button_pressed,
		dialog.count_picker.get_selected_id(), dialog.seed_edit.text])
	_check("invalid seed focuses the field for correction", root.gui_get_focus_owner() == dialog.seed_edit)

	# Escape is Cancel: it asks the owner to close, and the input dictionary stays unchanged.
	var source := DEFAULT_CONFIG.duplicate(true)
	var original := source.duplicate(true)
	dialog.configure(source)
	dialog.enabled_check.button_pressed = false
	dialog.seed_edit.text = "42"
	dialog.cancel_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("Cancel requests close without applying the draft",
		_close_requests == 1 and _applied_payloads.is_empty() and source == original)
	dialog.enabled_check.grab_focus()
	await ui.tap(KEY_ESCAPE)
	_check("Escape requests close from a focused control", _close_requests == 2)

	# Keyboard Tab and controller Down follow the visible focus chain.
	dialog.configure({})
	dialog.enabled_check.grab_focus()
	await ui.tap(KEY_TAB)
	_check("Tab moves from enable to count", root.gui_get_focus_owner() == dialog.count_picker, ui.focus_name())
	await ui.tap(KEY_TAB)
	_check("Tab moves from count to seed", root.gui_get_focus_owner() == dialog.seed_edit, ui.focus_name())
	dialog.enabled_check.grab_focus()
	await ui.joy_button(JOY_BUTTON_DPAD_DOWN)
	_check("controller navigation moves from enable to count",
		root.gui_get_focus_owner() == dialog.count_picker, ui.focus_name())
	dialog.seed_edit.grab_focus()
	await ui.tap(KEY_TAB)
	_check("Tab reaches companion volume", root.gui_get_focus_owner() == dialog.volume_slider, ui.focus_name())
	await ui.joy_button(JOY_BUTTON_DPAD_DOWN)
	_check("controller reaches optional labels", root.gui_get_focus_owner() == dialog.labels_check, ui.focus_name())
	dialog.volume_slider.value = 35.0
	dialog.labels_check.button_pressed = true
	dialog.label_distance.value = 500.0
	dialog.apply_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("presentation values are emitted without touching the source", _applied_payloads.size() == 1
		and _applied_payloads[0].engine_volume == 0.35 and _applied_payloads[0].show_labels
		and _applied_payloads[0].label_distance_m == 500.0 and DEFAULT_CONFIG.engine_volume == 1.0)
	_applied_payloads.clear()

	# Pause scope exposes the current traffic status, default-save choice and immediate removal action.
	dialog.configure(DEFAULT_CONFIG, {
		"in_flight": true,
		"airborne": 2,
		"active": 3,
		"requested": 3,
	})
	_check("in-flight status explains restart and Remove now behavior",
		dialog.status_label.visible and dialog.status_label.text.contains("2 airborne / 3 active / 3 requested")
		and dialog.status_label.text.contains("Flight settings apply after Restart flight")
		and dialog.status_label.text.contains("Sound and labels apply immediately")
		and dialog.status_label.text.contains("Remove now clears the current companions."),
		dialog.status_label.text)
	_check("Remove companions is shown only for an active in-flight group",
		dialog.remove_button.visible and dialog.save_default_check.visible)
	dialog.save_default_check.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("Save as default checkbox is available to the Pause owner", dialog.save_as_default)
	dialog.remove_button.grab_focus()
	await ui.joy_button(JOY_BUTTON_A)
	_check("Remove emits the immediate removal request", _remove_requests == 1)

	_check("the dialog leaves its preferences path untouched", not FileAccess.file_exists(NO_WRITE_PATH))
	root.remove_child(dialog)
	dialog.free()
	UiInput.isolate_joypads()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NO_WRITE_PATH))
	await ui.settle()


func _on_applied(config: Dictionary) -> void:
	_applied_payloads.append(config.duplicate(true))


func _on_close_requested() -> void:
	_close_requests += 1


func _on_removed() -> void:
	_remove_requests += 1
