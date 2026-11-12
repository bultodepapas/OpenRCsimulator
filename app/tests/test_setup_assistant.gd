# UI-15-UX-07: Setup assistant journeys with a fake host: gamepad (calibration skipped), radio (calibration only on
# click; completion and cancellation), unknown device (Next disabled until a kind is chosen), vehicle essentials
# (FPV quad arm/flight mode), press-to-assign through the host, Skip, Back/Esc, Save success and failure, Cancel,
# preview polling only on the Test step, focus always inside the assistant and unique accessible names.
# Run: godot --headless --path . --audio-driver Dummy --script res://tests/test_setup_assistant.gd
extends SceneTree

const UiTheme := preload("res://ui/ui_theme.gd")
const Assistant := preload("res://ui/controls/setup_assistant.gd")
const HostBase := preload("res://ui/controls/setup_assistant_host.gd")

var _failures := 0
var _count := 0


class FakeHost extends HostBase:
	var info := {}
	var capabilities := {"gear": true, "smoke": true, "flaps": true, "rates": true}
	var calls: Array = []
	var kind_ok := true
	var preset_ok := true
	var calibration_ok := true
	var capture_ok := true
	var save_ok := true
	var error_text := ""
	var bindings := {}
	var sample := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.0, "buttons": []}
	var preview_count := 0

	func device_info() -> Dictionary:
		return info

	func vehicle_capabilities() -> Dictionary:
		return capabilities

	func set_profile_kind(kind: String) -> bool:
		calls.append(["set_profile_kind", kind])
		return kind_ok

	func apply_preset(preset_id: String) -> bool:
		calls.append(["apply_preset", preset_id])
		return preset_ok

	func request_calibration() -> bool:
		calls.append(["request_calibration"])
		return calibration_ok

	func preview() -> Dictionary:
		preview_count += 1
		return sample

	func set_channel_inverted(channel: String, inverted: bool) -> void:
		calls.append(["set_channel_inverted", channel, inverted])

	func binding_for(id: String) -> Dictionary:
		return bindings.get(id, {"type": "unbound"})

	func capture(id: String) -> bool:
		calls.append(["capture", id])
		return capture_ok

	func save() -> bool:
		calls.append(["save"])
		return save_ok

	func last_error() -> String:
		return error_text

	func called(method: String) -> int:
		var total := 0
		for call: Array in calls:
			if call[0] == method:
				total += 1
		return total


class Recorder extends RefCounted:
	var finished: Array = []
	var closed := 0

	func on_finished(saved: bool) -> void:
		finished.append(saved)

	func on_closed() -> void:
		closed += 1


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for index in count:
		await process_frame


func _open(host: FakeHost, recorder: Recorder) -> Assistant:
	var assistant := Assistant.new()
	assistant.configure(host)
	root.add_child(assistant)
	assistant.finished.connect(recorder.on_finished)
	assistant.closed.connect(recorder.on_closed)
	assistant.open()
	await _frames(2)
	return assistant


func _close(assistant: Assistant) -> void:
	root.remove_child(assistant)
	assistant.free()
	await _frames(1)


func _escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event)
	var release := event.duplicate() as InputEventKey
	release.pressed = false
	root.push_input(release)


## Focus is on a visible, enabled control inside the assistant; every visible button has a unique accessible name.
func _check_step_state(assistant: Assistant, label: String) -> void:
	var focused := root.gui_get_focus_owner()
	_check("%s: focus inside the assistant" % label, focused != null and assistant.is_ancestor_of(focused)
		and focused.is_visible_in_tree(), str(focused))
	var names := {}
	var missing := []
	var duplicates := []
	for node: Node in assistant.find_children("*", "BaseButton", true, false):
		var button := node as BaseButton
		if not button.is_visible_in_tree():
			continue
		var text := str(button.accessibility_name)
		if text.is_empty():
			missing.append(button.name)
		elif names.has(text):
			duplicates.append(text)
		names[text] = true
	_check("%s: every visible button has an accessible name" % label, missing.is_empty(), str(missing))
	_check("%s: accessible names are unique" % label, duplicates.is_empty(), str(duplicates))


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	await _gamepad_journey()
	await _radio_journey()
	await _unknown_device()
	await _multirotor_and_capture()
	await _save_failure_and_cancel()
	await _escape_navigation()
	print("setup assistant: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _gamepad_journey() -> void:
	var host := FakeHost.new()
	host.info = {"display_name": "Xbox Wireless Controller", "name": "Xbox Wireless Controller", "kind": "gamepad",
		"known": true, "vendor_id": 0x045E}
	var recorder := Recorder.new()
	var assistant := await _open(host, recorder)
	_check("gamepad: starts on Identify", assistant.current_step() == "identify")
	_check("gamepad: known gamepad preselected", assistant.chosen_kind() == "gamepad"
		and (assistant.kind_cards.gamepad as BaseButton).button_pressed)
	_check("gamepad: no Calibrate step", not assistant.steps().has("calibrate"), str(assistant.steps()))
	_check("gamepad: Next enabled", not assistant.next_button.disabled)
	_check("gamepad: Back hidden on the first step", not assistant.back_button.visible)
	_check_step_state(assistant, "gamepad identify")
	_check("gamepad: no preview before Test", host.preview_count == 0)
	assistant.next_button.pressed.emit()
	_check("gamepad: kind applied on Next", host.calls.has(["set_profile_kind", "gamepad"]))
	_check("gamepad: Mode step", assistant.current_step() == "mode")
	_check("gamepad: three layouts offered", assistant.mode_cards.size() == 3 and assistant.mode_cards.has("trigger_absolute"))
	_check("gamepad: Mode 2 preselected", assistant.chosen_preset() == "mode2")
	_check_step_state(assistant, "gamepad mode")
	(assistant.mode_cards.trigger_absolute as BaseButton).pressed.emit()
	_check("gamepad: trigger throttle chosen", assistant.chosen_preset() == "trigger_absolute")
	assistant.next_button.pressed.emit()
	_check("gamepad: preset applied on Next", host.calls.has(["apply_preset", "trigger_absolute"]))
	_check("gamepad: calibration skipped automatically", assistant.current_step() == "test")
	_check("gamepad: calibration never requested", host.called("request_calibration") == 0)
	_check_step_state(assistant, "gamepad test")
	host.sample = {"roll": 0.5, "pitch": -0.25, "yaw": 0.75, "throttle": 0.6, "buttons": [JOY_BUTTON_A]}
	await _frames(3)
	_check("gamepad: preview polled on Test", host.preview_count >= 2, str(host.preview_count))
	_check("gamepad: roll bar follows preview", is_equal_approx((assistant.channel_bars.roll).current_value(), 0.5))
	_check("gamepad: aircraft follows preview", assistant.aircraft.controls().is_equal_approx(Vector4(0.5, -0.25, 0.75, 0.6)))
	_check("gamepad: pressed button chip shown", assistant._pressed_chips[0].visible and not assistant._pressed_chips[1].visible)
	var redraws: int = assistant.aircraft.redraw_requests
	await _frames(3)
	_check("gamepad: unchanged preview does not redraw", assistant.aircraft.redraw_requests == redraws)
	(assistant.reverse_toggles.yaw as BaseButton).button_pressed = true
	_check("gamepad: Reverse calls the host", host.calls.has(["set_channel_inverted", "yaw", true]))
	assistant.back_button.pressed.emit()
	_check("gamepad: Back returns to Mode", assistant.current_step() == "mode")
	var polled := host.preview_count
	await _frames(3)
	_check("gamepad: no preview polling off the Test step", host.preview_count == polled)
	assistant.next_button.pressed.emit()
	assistant.next_button.pressed.emit()
	_check("gamepad: Switches step", assistant.current_step() == "switches")
	_check_step_state(assistant, "gamepad switches")
	assistant.skip_button.pressed.emit()
	_check("gamepad: Skip goes to Summary", assistant.current_step() == "summary")
	_check_step_state(assistant, "gamepad summary")
	_check("gamepad: Save button on Summary", assistant.next_button.text == "Save")
	assistant.next_button.pressed.emit()
	_check("gamepad: Save called once", host.called("save") == 1)
	_check("gamepad: finished(true) then closed", recorder.finished == [true] and recorder.closed == 1)
	await _close(assistant)


func _radio_journey() -> void:
	var host := FakeHost.new()
	host.info = {"display_name": "JETI DC-24 II", "kind": "radio", "known": false}
	var recorder := Recorder.new()
	var assistant := await _open(host, recorder)
	_check("radio: radio preselected", assistant.chosen_kind() == "radio")
	_check("radio: Calibrate step present", assistant.steps().has("calibrate"))
	assistant.next_button.pressed.emit()
	_check("radio: two stick layouts", assistant.mode_cards.size() == 2 and not assistant.mode_cards.has("trigger_absolute"))
	assistant.next_button.pressed.emit()
	_check("radio: Calibrate step", assistant.current_step() == "calibrate")
	await _frames(2)
	_check("radio: calibration never starts by itself", host.called("request_calibration") == 0)
	_check("radio: Next disabled until calibrated", assistant.next_button.disabled)
	_check("radio: Skip offered", assistant.skip_button.is_visible_in_tree())
	_check_step_state(assistant, "radio calibrate")
	assistant.start_calibration_button.pressed.emit()
	_check("radio: calibration requested on click", host.called("request_calibration") == 1)
	_check("radio: busy and hidden while calibrating", assistant.is_busy() and not assistant.surface().visible)
	assistant.go_back()
	assistant.skip()
	_check("radio: navigation ignored while calibrating", assistant.current_step() == "calibrate")
	assistant.notify_capture_finished("calibration", true, "")
	assistant.notify_calibration_finished(false, "Calibration cancelled. The draft is unchanged.")
	await _frames(1)
	_check("radio: visible again after cancellation", assistant.surface().visible and not assistant.is_busy())
	_check("radio: cancellation reason shown", assistant.calibration_banner.visible
		and assistant.calibration_label.text.contains("Calibration cancelled"))
	_check("radio: Next still disabled after cancellation", assistant.next_button.disabled)
	_check_step_state(assistant, "radio calibrate cancelled")
	host.calibration_ok = false
	host.error_text = "The radio disconnected."
	assistant.start_calibration_button.pressed.emit()
	_check("radio: refused start shows the host error", not assistant.is_busy() and assistant.calibration_label.text == "The radio disconnected.")
	host.calibration_ok = true
	assistant.start_calibration_button.pressed.emit()
	assistant.notify_calibration_finished(true, "")
	await _frames(1)
	_check("radio: Next enabled after calibration", not assistant.next_button.disabled)
	_check("radio: focus moves to Next", root.gui_get_focus_owner() == assistant.next_button)
	assistant.notify_calibration_finished(false, "late")
	_check("radio: stale completion ignored", not assistant.calibration_label.text.contains("late"))
	assistant.next_button.pressed.emit()
	_check("radio: Test after calibration", assistant.current_step() == "test")
	_check("radio: throttle bar one-ended", assistant.channel_bars.throttle.one_ended)
	_check("radio: Mode 2 throttle on the left gimbal", assistant.left_gimbal.one_ended_y and not assistant.right_gimbal.one_ended_y)
	assistant.cancel_button.pressed.emit()
	_check("radio: Cancel closes without saving", recorder.finished == [false] and recorder.closed == 1 and host.called("save") == 0)
	await _close(assistant)


func _unknown_device() -> void:
	var host := FakeHost.new()
	host.info = {"display_name": "USB Joystick", "kind": "joystick", "known": false}
	var recorder := Recorder.new()
	var assistant := await _open(host, recorder)
	_check("unknown: nothing preselected", assistant.chosen_kind() == "")
	_check("unknown: Next disabled", assistant.next_button.disabled)
	var none_pressed := true
	for kind: String in assistant.kind_cards:
		none_pressed = none_pressed and not (assistant.kind_cards[kind] as BaseButton).button_pressed
	_check("unknown: no card pressed", none_pressed)
	_check_step_state(assistant, "unknown identify")
	assistant.go_next()
	_check("unknown: Next refused without a kind", assistant.current_step() == "identify" and host.called("set_profile_kind") == 0)
	(assistant.kind_cards.joystick as BaseButton).pressed.emit()
	_check("unknown: joystick chosen", assistant.chosen_kind() == "joystick" and not assistant.next_button.disabled)
	_check("unknown: joystick is calibrated", assistant.steps().has("calibrate"))
	(assistant.kind_cards.gamepad as BaseButton).pressed.emit()
	_check("unknown: gamepad drops Calibrate", not assistant.steps().has("calibrate"))
	host.kind_ok = false
	host.error_text = "That type does not fit this device."
	assistant.next_button.pressed.emit()
	_check("unknown: refused kind keeps Identify with the error", assistant.current_step() == "identify"
		and assistant.error_banner.visible and assistant.error_label.text == host.error_text)
	host.kind_ok = true
	assistant.next_button.pressed.emit()
	_check("unknown: error cleared after success", assistant.current_step() == "mode" and not assistant.error_banner.visible)
	await _close(assistant)


func _multirotor_and_capture() -> void:
	var host := FakeHost.new()
	host.info = {"display_name": "RadioMaster TX16S", "kind": "radio"}
	host.capabilities = {"multirotor": true}
	var recorder := Recorder.new()
	var assistant := await _open(host, recorder)
	_check("quad: arm and flight mode offered", assistant.assign_buttons.has("aux:arm") and assistant.assign_buttons.has("aux:flight_mode"))
	_check("quad: airplane equipment hidden", not assistant.assign_buttons.has("flaps_cycle") and not assistant.assign_buttons.has("gear_toggle"))
	_check("quad: Pause assignable, Back read-only", assistant.assign_buttons.has("pause")
		and assistant.binding_chips.has("back") and not assistant.assign_buttons.has("back"))
	await _close(assistant)

	host = FakeHost.new()
	host.info = {"display_name": "Xbox Wireless Controller", "kind": "gamepad", "known": true}
	host.capabilities = {"helicopter": true}
	assistant = await _open(host, recorder)
	_check("helicopter: arm, hold and mode", assistant.assign_buttons.has("helicopter_arm")
		and assistant.assign_buttons.has("helicopter_hold") and assistant.assign_buttons.has("helicopter_mode")
		and not assistant.assign_buttons.has("throttle_cut"))
	await _close(assistant)

	host = FakeHost.new()
	host.info = {"display_name": "Xbox Wireless Controller", "kind": "gamepad", "known": true}
	assistant = await _open(host, recorder)
	for essential in ["throttle_cut", "flaps_cycle", "gear_toggle", "smoke_toggle", "camera_cycle", "restart_flight", "pause"]:
		_check("airplane: %s offered" % essential, assistant.assign_buttons.has(essential))
	assistant.next_button.pressed.emit()
	assistant.next_button.pressed.emit()
	assistant.next_button.pressed.emit()
	_check("capture: on Switches", assistant.current_step() == "switches")
	var chip: Control = assistant.binding_chips.flaps_cycle
	_check("capture: chip starts unbound", chip.is_unbound())
	await _frames(2)
	(assistant.assign_buttons.flaps_cycle as BaseButton).pressed.emit()
	_check("capture: host asked for the id", host.calls.has(["capture", "flaps_cycle"]))
	_check("capture: busy", assistant.is_busy())
	var all_disabled := assistant.next_button.disabled and assistant.back_button.disabled and assistant.cancel_button.disabled
	for id: String in assistant.assign_buttons:
		all_disabled = all_disabled and (assistant.assign_buttons[id] as BaseButton).disabled
	_check("capture: every button disabled while the host captures", all_disabled)
	_check("capture: surface ignores keys while capturing", not assistant.surface().is_processing_input())
	_escape()
	await _frames(1)
	_check("capture: Esc belongs to the owner", assistant.current_step() == "switches" and recorder.closed == 0)
	(assistant.assign_buttons.gear_toggle as BaseButton).pressed.emit()
	_check("capture: no second capture while busy", host.called("capture") == 1)
	host.bindings["flaps_cycle"] = {"type": "button", "button": JOY_BUTTON_A}
	assistant.notify_capture_finished("gear_toggle", true, "")
	_check("capture: another id's completion is ignored", assistant.is_busy())
	assistant.notify_capture_finished("flaps_cycle", true, "")
	await _frames(1)
	_check("capture: chip updated from the host", not chip.is_unbound(), chip.label_text())
	_check("capture: buttons enabled again", not (assistant.assign_buttons.flaps_cycle as BaseButton).disabled
		and not assistant.next_button.disabled)
	_check("capture: surface handles keys again", assistant.surface().is_processing_input())
	_check("capture: status says assigned", (assistant.row_status.flaps_cycle as Label).text == "Assigned")
	_check("capture: focus moves to the next row", root.gui_get_focus_owner() == assistant.assign_buttons.gear_toggle)
	(assistant.assign_buttons.smoke_toggle as BaseButton).pressed.emit()
	assistant.notify_capture_finished("smoke_toggle", false, "RB is already Cycle camera.")
	_check("capture: conflict message shown", (assistant.row_status.smoke_toggle as Label).text == "RB is already Cycle camera.")
	_check("capture: focus stays on the row after a refusal", root.gui_get_focus_owner() == assistant.assign_buttons.smoke_toggle)
	host.capture_ok = false
	host.error_text = "Connect the controller first."
	(assistant.assign_buttons.camera_cycle as BaseButton).pressed.emit()
	_check("capture: refused start is not busy", not assistant.is_busy()
		and (assistant.row_status.camera_cycle as Label).text == host.error_text)
	_check_step_state(assistant, "capture done")
	assistant.skip_button.pressed.emit()
	_check("summary: reached", assistant.current_step() == "summary")
	_check("summary: assigned control marked", assistant.summary_overlay.marks.has(["button:%d" % JOY_BUTTON_A, 1]),
		str(assistant.summary_overlay.marks))
	await _close(assistant)


func _save_failure_and_cancel() -> void:
	var host := FakeHost.new()
	host.info = {"display_name": "Xbox Wireless Controller", "kind": "gamepad", "known": true}
	host.save_ok = false
	host.error_text = "Settings could not be written: disk full."
	host.sample = {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.4, "throttle_centered": true}
	var recorder := Recorder.new()
	var assistant := await _open(host, recorder)
	assistant.go_next()
	assistant.go_next()
	_check("rate throttle: Mode 2 on Test", assistant.current_step() == "test" and assistant.chosen_preset() == "mode2")
	_check("rate throttle: centred gimbal and bar", not assistant.left_gimbal.one_ended_y
		and not assistant.channel_bars.throttle.one_ended)
	_check("rate throttle: stick forward is up", assistant.left_gimbal.stick().y < -0.3)
	for index in 2:
		assistant.go_next()
	_check("save: on Summary", assistant.current_step() == "summary")
	assistant.next_button.pressed.emit()
	_check("save: failure shows the host error", assistant.error_banner.visible and assistant.error_label.text == host.error_text)
	_check("save: failure stays on Summary", assistant.current_step() == "summary" and recorder.finished.is_empty() and recorder.closed == 0)
	_check("save: focus on Save after failure", root.gui_get_focus_owner() == assistant.next_button)
	host.save_ok = true
	assistant.next_button.pressed.emit()
	_check("save: retry succeeds", recorder.finished == [true] and recorder.closed == 1)
	await _close(assistant)


func _escape_navigation() -> void:
	var host := FakeHost.new()
	host.info = {"display_name": "Xbox Wireless Controller", "kind": "gamepad", "known": true}
	var recorder := Recorder.new()
	var assistant := await _open(host, recorder)
	assistant.go_next()
	assistant.go_next()
	_check("escape: on Test", assistant.current_step() == "test")
	_escape()
	await _frames(1)
	_check("escape: Esc goes back one step", assistant.current_step() == "mode")
	_check_step_state(assistant, "escape mode")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_B
	pad.pressed = true
	if InputMap.action_has_event("ui_cancel", pad):
		root.push_input(pad)
		var release := pad.duplicate() as InputEventJoypadButton
		release.pressed = false
		root.push_input(release)
		await _frames(1)
		_check("escape: pad Back goes back one step", assistant.current_step() == "identify")
	else:
		assistant.go_back()
	_escape()
	await _frames(1)
	_check("escape: Esc on the first step cancels without saving", recorder.finished == [false] and recorder.closed == 1
		and host.called("save") == 0)
	await _close(assistant)
