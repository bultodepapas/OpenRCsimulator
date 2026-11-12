extends SceneTree

# UI-15-UX-02 / 02b / 02c: accessible names, full-text popovers, friendly validation sentences,
# the unsaved-changes guard and the vehicle-aware action list of the Controls screen.

const ControllerSetup := preload("res://ui/controller_setup.gd")
const ControllerActions := preload("res://input/controller_actions.gd")
const ControllerProfile := preload("res://input/controller_profile.gd")

class FakeRegistry extends RefCounted:
	signal devices_changed

	var generation := 3
	var selections := {"flight": 5, "ui": 5}
	var devices: Array[Dictionary] = [
		{"id": 5, "name": "Known gamepad", "raw_name": "Known gamepad", "kind": "gamepad", "known": true, "connected": true},
		{"id": 9, "name": "Radio transmitter", "raw_name": "Radio transmitter", "kind": "radio", "known": false, "connected": true},
	]

	func get_devices() -> Array[Dictionary]:
		return devices.duplicate(true)

	func selected_device_id(role: String) -> int:
		return int(selections.get(role, -1))

	func device_for_id(device_id: int) -> Dictionary:
		for device: Dictionary in devices:
			if int(device.id) == device_id:
				return device.duplicate(true)
		return {}

	func connection_generation(_device_id: int) -> int:
		return generation


class FakeStore extends RefCounted:
	var saved_count := 0
	var save_succeeds := false
	var profiles: Array[Dictionary] = []

	func load_all() -> Dictionary:
		return {"ok": true, "profiles": profiles.duplicate(true), "errors": []}

	func import_legacy_radio() -> Dictionary:
		return {"ok": true, "profiles": [], "errors": []}

	func save_profile(candidate: Dictionary) -> Dictionary:
		saved_count += 1
		if not save_succeeds:
			return {"ok": false, "profile": {}, "error": "storage offline"}
		profiles.append(candidate.duplicate(true))
		return {"ok": true, "profile": candidate.duplicate(true), "error": ""}

	func match_profile(_info: Dictionary, _connected: Array = []) -> Dictionary:
		return {}


var failures := 0
var closes := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	InputMap.load_from_project_settings()
	_test_action_applies()
	await _test_accessible_names()
	await _test_info_popover()
	await _test_friendly_errors()
	await _test_unsaved_guard()
	await _test_calibration_only_dirty()
	await _test_vehicle_filter()
	print("all controls setup P0 checks passed" if failures == 0 else "%d controls setup P0 checks failed" % failures)
	quit(1 if failures > 0 else 0)


func _open(capabilities: Dictionary = ControllerActions.AIRPLANE_CAPABILITIES, device_id := 5, store: FakeStore = null) -> ControllerSetup:
	var setup := ControllerSetup.new()
	setup.configure(FakeRegistry.new(), store if store != null else FakeStore.new(), device_id, device_id if device_id == 5 else -1, capabilities)
	setup.close_requested.connect(func() -> void: closes += 1)
	root.add_child(setup)
	await process_frame
	await process_frame
	await process_frame
	return setup


func _close(setup: ControllerSetup) -> void:
	setup.free()
	await process_frame


func _test_action_applies() -> void:
	var plane := ControllerActions.AIRPLANE_CAPABILITIES
	var heli := ControllerActions.HELICOPTER_CAPABILITIES
	_check("helicopter actions need the helicopter capability",
		ControllerActions.action_applies("helicopter_arm", heli) and not ControllerActions.action_applies("helicopter_arm", plane))
	_check("gear, smoke, flaps and rates follow their capabilities",
		ControllerActions.action_applies("gear_toggle", plane) and not ControllerActions.action_applies("gear_toggle", heli)
		and ControllerActions.action_applies("smoke_toggle", {"smoke": true}) and not ControllerActions.action_applies("smoke_toggle", {"gear": true})
		and ControllerActions.action_applies("flaps_down", {"flaps": true}) and not ControllerActions.action_applies("flaps_up", heli)
		and not ControllerActions.action_applies("flaps_cycle", heli) and not ControllerActions.action_applies("rates_toggle", heli))
	_check("every other action applies to every vehicle",
		ControllerActions.action_applies("restart_flight", {}) and ControllerActions.action_applies("camera_cycle", {})
		and ControllerActions.action_applies("back", heli) and ControllerActions.action_applies("unknown_future", {}))


func _test_accessible_names() -> void:
	var setup := await _open()
	var names: Dictionary = {}
	var duplicates: Array[String] = []
	var unnamed: Array[String] = []
	var controls: Array[Control] = []
	for definition in ControllerActions.ACTIONS:
		for prefix: String in ["Remap_", "Clear_", "LearnAxis_"]:
			controls.append(setup.find_child(prefix + str(definition.id), true, false) as Control)
	for channel: String in ControllerSetup.CHANNELS:
		for key: String in ["axis", "deadzone", "expo", "invert"]:
			controls.append(setup._axis_controls[channel][key])
	for aux_name: String in ControllerSetup.AUX_CHANNELS:
		var aux: Dictionary = setup._aux_controls[aux_name]
		for key: String in ["type", "axis", "off", "on", "invert", "button", "button_mode", "switch_count", "switch_label", "switch_invert"]:
			controls.append(aux[key])
		for index in 3:
			controls.append(aux.switch_button_spins[index])
			controls.append(aux.switch_capture_buttons[index])
	for control: Control in controls:
		var accessible := str(control.accessibility_name)
		if accessible.is_empty():
			unnamed.append(str(control.name))
		elif names.has(accessible):
			duplicates.append(accessible)
		names[accessible] = true
	_check("every per-row control has an accessible name", unnamed.is_empty(), str(unnamed))
	_check("per-row accessible names are unique", duplicates.is_empty(), str(duplicates))
	_check("Buttons rows name their action",
		(setup.find_child("Remap_flaps_down", true, false) as Control).accessibility_name == "Remap Flaps down"
		and (setup.find_child("Clear_flaps_down", true, false) as Control).accessibility_name == "Clear Flaps down"
		and (setup.find_child("LearnAxis_flaps_down", true, false) as Control).accessibility_name == "Learn axis for Flaps down")
	_check("AUX capture names channel and position",
		(setup._aux_controls.flaps.switch_capture_buttons[0] as Control).accessibility_name == "Capture Flaps Up position")
	_check("axis fields name their channel",
		setup._axis_controls.roll.axis.accessibility_name == "Roll source axis"
		and setup._axis_controls.roll.axis.get_line_edit().accessibility_name == "Roll source axis"
		and setup._axis_controls.roll.deadzone.accessibility_name == "Roll deadzone"
		and setup._axis_controls.roll.expo.accessibility_name == "Roll expo"
		and setup._axis_controls.roll.invert.accessibility_name == "Invert Roll")
	_check("the table-layout Invert checkbox keeps its name without text",
		setup._axis_layout_is_table and setup._axis_controls.pitch.invert.text.is_empty() and setup._axis_controls.pitch.invert.accessibility_name == "Invert Pitch")
	await _close(setup)


func _test_info_popover() -> void:
	var setup := await _open()
	setup.select_section("aux")
	await process_frame
	await process_frame
	var info := setup.aux_help_info_button
	_check("one-line AUX help at 1080p has a focusable full-text button", setup.aux_help_label.max_lines_visible == 1
		and info.is_visible_in_tree() and info.focus_mode == Control.FOCUS_ALL and not str(info.accessibility_name).is_empty())
	info.grab_focus()
	info.pressed.emit()
	await process_frame
	await process_frame
	var dialog := setup._info_dialog
	_check("the popover shows the whole help text", dialog != null and dialog.visible and dialog.dialog_text == setup.tr(setup.aux_help_label.text))
	_check("the popover takes keyboard and gamepad focus", dialog.get_ok_button().has_focus())
	var count := closes
	setup.request_close() # Back/Escape routed to the screen
	await process_frame
	await process_frame
	_check("Back closes the popover, not the screen", not dialog.visible and closes == count)
	_check("focus returns to the info button", root.gui_get_focus_owner() == info)
	info.pressed.emit()
	await process_frame
	dialog.get_ok_button().pressed.emit()
	await process_frame
	await process_frame
	_check("OK closes the popover and restores focus", not dialog.visible and root.gui_get_focus_owner() == info)
	root.size = Vector2i(1000, 720)
	await process_frame
	await process_frame
	_check("wrapped AUX help needs no info button", setup.aux_help_label.max_lines_visible == 0 and not info.visible)
	root.size = Vector2i(1920, 1080)
	await process_frame
	_check("the controller summary has a focusable details button", setup.device_summary_info_button.is_visible_in_tree()
		and setup.device_summary_info_button.focus_mode == Control.FOCUS_ALL)
	await _close(setup)


func _test_friendly_errors() -> void:
	var setup := await _open()
	var conflict := setup.current_profile()
	conflict.actions = {"camera_cycle": {"type": "button", "button": JOY_BUTTON_DPAD_LEFT}}
	setup._set_draft_profile(conflict)
	_check("a conflict blocks Save", not setup._save_profile(false))
	await process_frame
	_check("the conflict names both actions by label", setup.status_label.text.contains("“Cycle camera” and “Trim left” use the same control. Change one of them."), setup.status_label.text)
	_check("the conflict keeps raw identifiers out of the message", not setup.status_label.text.contains("camera_cycle"), setup.status_label.text)
	var remap_button := setup.find_child("Remap_camera_cycle", true, false) as Button
	_check("conflicting fields stay highlighted", remap_button.has_theme_stylebox_override("normal")
		and (setup.find_child("Remap_trim_left", true, false) as Button).has_theme_stylebox_override("normal"))
	var missing := setup.current_profile()
	missing.actions = {"back": {"type": "unbound"}}
	setup._set_draft_profile(missing)
	setup.select_section("devices")
	_check("a missing recovery binding blocks Save", not setup._save_profile(false))
	await process_frame
	await process_frame
	_check("missing recovery is a sentence naming Back", setup.status_label.text.contains("“Back / cancel” needs a control"), setup.status_label.text)
	_check("the missing recovery field is focused", root.gui_get_focus_owner() == setup.find_child("Remap_back", true, false))
	_check("unknown issue codes fall back to the validator text",
		setup._friendly_validation_text([{"code": "future_code", "paths": [], "message": "Raw validator text"}], []) == "Raw validator text"
		and setup._friendly_validation_text([], ["Raw error"]) == "Raw error")
	var aux := setup.current_profile()
	aux.actions = {}
	aux.aux = {"smoke": {"type": "button", "button": 15, "mode": "level"}}
	setup._set_draft_profile(aux)
	setup._start_capture("camera_previous", setup.find_child("Remap_camera_previous", true, false) as Button)
	var event := InputEventJoypadButton.new()
	event.device = 5
	event.button_index = 15 as JoyButton
	event.pressed = true
	setup._capture_binding(event)
	_check("a rejected remap names the action and the extra channel",
		setup.status_label.text.contains("“Previous camera” uses the same control as the Smoke extra channel."), setup.status_label.text)
	await _close(setup)


func _test_unsaved_guard() -> void:
	var store := FakeStore.new()
	var setup := await _open(ControllerActions.AIRPLANE_CAPABILITIES, 5, store)
	_check("a freshly loaded draft is clean", not setup.has_unsaved_changes() and not setup._unsaved_marker.visible
		and setup._settings_title.text == "Controls")
	var count := closes
	setup.request_close()
	_check("a clean close is immediate", closes == count + 1 and setup.unsaved_dialog == null)

	setup = await _open(ControllerActions.AIRPLANE_CAPABILITIES, 5, store)
	setup.select_section("axes")
	await process_frame
	var deadzone_edit := setup._axis_controls.roll.deadzone.get_line_edit() as LineEdit
	deadzone_edit.grab_focus()
	setup._axis_controls.roll.deadzone.value = 0.2
	await process_frame
	_check("an edit makes the draft dirty", setup.has_unsaved_changes())
	_check("the title and footer mark the dirty draft", setup._settings_title.text == "Controls •" and setup._unsaved_marker.visible
		and setup.save_button.accessibility_description == "Unsaved changes")
	count = closes
	setup.request_close()
	await process_frame
	var dialog := setup.unsaved_dialog
	_check("a dirty close asks first", dialog != null and dialog.visible and closes == count)
	_check("the question offers Save, Discard and Keep editing", dialog.get_ok_button().text == "Save"
		and setup._unsaved_discard_button.text == "Discard" and dialog.get_cancel_button().text == "Keep editing")
	dialog.get_cancel_button().pressed.emit()
	await process_frame
	await process_frame
	_check("Keep editing stays open and restores focus", not dialog.visible and closes == count and root.gui_get_focus_owner() == deadzone_edit)
	setup.request_close()
	await process_frame
	setup.request_close() # a second Back while asking = Keep editing
	await process_frame
	_check("Back while asking keeps editing", not dialog.visible and closes == count and setup.has_unsaved_changes())

	setup.request_close()
	await process_frame
	dialog.get_ok_button().pressed.emit()
	await process_frame
	_check("a failed Save keeps the screen open with its error", closes == count and store.saved_count == 1
		and setup.status_label.text.contains("storage offline") and setup.has_unsaved_changes())

	store.save_succeeds = true
	setup.request_close()
	await process_frame
	dialog.get_ok_button().pressed.emit()
	await process_frame
	_check("Save from the question saves through the transactional path and closes", closes == count + 1 and store.saved_count == 2
		and not setup.has_unsaved_changes())
	await process_frame
	_check("a saved draft clears the marker", setup._settings_title.text == "Controls" and not setup._unsaved_marker.visible)
	await _close(setup)

	var discard_store := FakeStore.new()
	setup = await _open(ControllerActions.AIRPLANE_CAPABILITIES, 5, discard_store)
	var registry: FakeRegistry = setup.registry
	setup._axis_controls.pitch.expo.value = 0.5
	count = closes
	setup.request_close()
	await process_frame
	setup._unsaved_discard_button.pressed.emit()
	await process_frame
	_check("Discard closes without saving or changing the active selection", closes == count + 1 and discard_store.saved_count == 0
		and discard_store.profiles.is_empty() and registry.selections == {"flight": 5, "ui": 5} and not setup.unsaved_dialog.visible)
	await _close(setup)

	setup = await _open()
	setup.select_section("buttons")
	await process_frame
	setup._axis_controls.yaw.expo.value = 0.4
	(setup.find_child("Close", true, false) as Button).pressed.emit()
	await process_frame
	_check("the Close button asks with a dirty draft", setup.unsaved_dialog != null and setup.unsaved_dialog.visible)
	setup.unsaved_dialog.get_cancel_button().pressed.emit()
	await process_frame
	var remap_button := setup.find_child("Remap_camera_previous", true, false) as Button
	setup._start_capture("camera_previous", remap_button)
	count = closes
	setup.request_close() # Escape/Back during capture
	await process_frame
	_check("Escape during capture cancels only the capture", not setup._is_capture_active() and closes == count and not setup.unsaved_dialog.visible)
	(setup.find_child("Cancel", true, false) as Button).pressed.emit()
	_check("the explicit Cancel button discards at once", closes == count + 1 and not setup.unsaved_dialog.visible)
	await _close(setup)

	setup = await _open()
	setup._axis_controls.yaw.deadzone.value = 0.3
	setup.request_close()
	await process_frame
	count = closes
	setup.close_without_prompt()
	_check("a programmatic close never waits behind the question", closes == count + 1 and not setup.unsaved_dialog.visible)
	await _close(setup)

	setup = await _open()
	setup.flight_device_picker.select(0)
	setup.flight_device_picker.item_selected.emit(0)
	_check("a device role change counts as unsaved", setup.has_unsaved_changes())
	setup.flight_device_picker.select(setup.flight_device_picker.get_item_index(5))
	setup.flight_device_picker.item_selected.emit(setup.flight_device_picker.selected)
	_check("returning to the loaded device and draft is clean again", not setup.has_unsaved_changes())
	await _close(setup)


func _test_calibration_only_dirty() -> void:
	var setup := await _open(ControllerActions.AIRPLANE_CAPABILITIES, 9)
	_check("a radio draft starts clean", setup.current_profile().kind == "radio" and not setup.has_unsaved_changes())
	var measured := ControllerProfile.defaults("radio", "radio_custom")
	_check("calibration enters the draft", setup.apply_calibration_draft(measured, 9, 3))
	_check("a calibration-only draft counts as dirty", setup.has_unsaved_changes())
	setup.request_close()
	await process_frame
	_check("closing after calibration asks", setup.unsaved_dialog != null and setup.unsaved_dialog.visible)
	setup.unsaved_dialog.get_cancel_button().pressed.emit()
	await process_frame
	await _close(setup)


func _rows_visible(setup: ControllerSetup, ids: Array) -> bool:
	for action_id: String in ids:
		if not (setup.find_child("Remap_" + action_id, true, false) as Control).is_visible_in_tree():
			return false
	return true


func _rows_hidden(setup: ControllerSetup, ids: Array) -> bool:
	for action_id: String in ids:
		if (setup.find_child("Remap_" + action_id, true, false) as Control).visible:
			return false
	return true


func _test_vehicle_filter() -> void:
	var heli_ids := ["helicopter_arm", "helicopter_hold", "helicopter_mode", "helicopter_trainer"]
	var plane_ids := ["gear_toggle", "smoke_toggle", "flaps_up", "flaps_down", "flaps_cycle", "rates_toggle"]
	var common := ["back", "pause", "camera_cycle", "restart_flight", "trim_yaw_left"]
	var setup := await _open()
	setup.select_section("buttons")
	await process_frame
	_check("airplane rows show airplane and common actions", _rows_visible(setup, plane_ids + common))
	_check("airplane rows hide helicopter actions", _rows_hidden(setup, heli_ids))
	setup.show_all_vehicle_actions.button_pressed = true
	await process_frame
	_check("Show all reveals other vehicles' actions", _rows_visible(setup, heli_ids + plane_ids + common))
	(setup.find_child("Remap_helicopter_arm", true, false) as Button).grab_focus()
	setup.show_all_vehicle_actions.button_pressed = false
	await process_frame
	var owner := root.gui_get_focus_owner()
	_check("hiding the focused row moves focus to a visible control", owner == setup.show_all_vehicle_actions and _rows_hidden(setup, heli_ids))
	setup.action_filter.select(3)
	setup._on_action_filter_selected(3)
	await process_frame
	_check("category filter combines with the vehicle filter", _rows_visible(setup, ["gear_toggle", "smoke_toggle", "flaps_cycle"])
		and _rows_hidden(setup, ["camera_cycle", "back"] + heli_ids))
	(setup.find_child("Remap_flaps_cycle", true, false) as Button).grab_focus()
	setup.action_filter.select(2)
	setup._on_action_filter_selected(2)
	await process_frame
	owner = root.gui_get_focus_owner()
	_check("a category change never leaves focus on a hidden row", owner != null and owner.is_visible_in_tree() and not setup.action_grid.is_ancestor_of(owner))
	setup.action_filter.select(0)
	setup._on_action_filter_selected(0)
	setup._start_capture("helicopter_arm", setup.find_child("Remap_helicopter_arm", true, false) as Button)
	_check("a capture request reveals its hidden row", setup.show_all_vehicle_actions.button_pressed
		and (setup.find_child("Remap_helicopter_arm", true, false) as Control).is_visible_in_tree() and setup._capturing_action == "helicopter_arm")
	setup._cancel_capture()
	await _close(setup)

	setup = await _open(ControllerActions.HELICOPTER_CAPABILITIES)
	setup.select_section("buttons")
	await process_frame
	_check("helicopter rows show helicopter and common actions", _rows_visible(setup, heli_ids + common))
	_check("helicopter rows hide airplane equipment", _rows_hidden(setup, plane_ids))
	setup.action_filter.select(3)
	setup._on_action_filter_selected(3)
	_check("helicopter Auxiliary category is empty until Show all", _rows_hidden(setup, plane_ids))
	setup.show_all_vehicle_actions.button_pressed = true
	await process_frame
	_check("Show all with a category shows that category only", _rows_visible(setup, ["gear_toggle", "smoke_toggle", "flaps_cycle"]) and _rows_hidden(setup, ["camera_cycle"] + heli_ids))
	setup.show_all_vehicle_actions.button_pressed = false
	setup.action_filter.select(0)
	setup._on_action_filter_selected(0)
	var hidden_bound := setup.current_profile()
	hidden_bound.actions = {"gear_toggle": {"type": "button", "button": 30}}
	setup._set_draft_profile(hidden_bound)
	_check("a hidden row keeps its binding", setup.current_profile().actions.gear_toggle == {"type": "button", "button": 30}
		and _rows_hidden(setup, ["gear_toggle"]))
	var conflicting := setup.current_profile()
	conflicting.actions = {"gear_toggle": {"type": "button", "button": JOY_BUTTON_Y}}
	setup._set_draft_profile(conflicting)
	_check("hidden rows still take part in validation", not setup._save_profile(false))
	await process_frame
	await process_frame
	_check("validation reveals the hidden conflicting row", setup.show_all_vehicle_actions.button_pressed
		and (setup.find_child("Remap_gear_toggle", true, false) as Control).is_visible_in_tree()
		and setup.status_label.text.contains("“Cycle camera” and “Toggle landing gear”"), setup.status_label.text)
	await _close(setup)


func _check(label: String, condition: bool, detail: Variant = "") -> void:
	if condition:
		print("ok   ", label)
	else:
		failures += 1
		printerr("FAIL ", label, "  ", detail)
