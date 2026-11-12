# UI-15-UX-01: the shared radio calibration view and its two hosts, driven by the real wizard with synthetic axes.
# Run: godot --headless --path . --audio-driver Dummy --script res://tests/test_calibration_view.gd
extends SceneTree

const UiTheme := preload("res://ui/ui_theme.gd")
const RcInput := preload("res://input/rc_input.gd")
const Calibration := preload("res://input/rc_calibration.gd")
const CalibrationView := preload("res://ui/controls/calibration_view.gd")
const ChannelBarView := preload("res://ui/controls/channel_bar.gd")
const GimbalView := preload("res://ui/controls/stick_gimbal_view.gd")
const CalibrationCard := preload("res://ui/calibration_card.gd")
const RadioCalibration := preload("res://ui/radio_calibration_setup.gd")

var _failures := 0
var _count := 0
var _raw := PackedFloat64Array()


class RadioRegistry extends RefCounted:
	signal devices_changed
	var devices: Array[Dictionary] = [{"id": 5, "name": "Fixture radio", "kind": "radio", "connected": true}]
	func device_for_id(id: int) -> Dictionary: return devices[0].duplicate(true) if id == 5 else {}
	func connection_generation(id: int) -> int: return 1 if id == 5 else 0


class FakeRadio extends RefCounted:
	var axes := PackedFloat64Array()


class FakeSession extends Node:
	var calibration: Variant = null
	var radio := FakeRadio.new()


class FlightStub extends Node:
	var overlay_settings := {"stick_mode": 1}


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


## The unusual radio of test_rc_calibration.gd: yaw axis 0, pitch axis 1 (stick back = −), throttle axis 4 reversed
## (LOW = +0.9), roll axis 6 resting at +0.05 with −0.8…+0.9 travel.
func _axes(throttle: float, roll: float, pitch: float, yaw: float) -> PackedFloat64Array:
	var a := PackedFloat64Array()
	a.resize(RcInput.AXES)
	a[0] = yaw
	a[1] = -pitch
	a[4] = 0.9 - 1.8 * throttle
	a[6] = 0.05 + roll * 0.85
	return a


func _feed(view: CalibrationView, wizard: Calibration, axes: PackedFloat64Array) -> void:
	wizard.sample(axes)
	view.update(wizard, axes)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("en")
	var host := Control.new()
	host.theme = UiTheme.build()
	host.size = Vector2(1920, 1080)
	root.add_child(host)
	_static_tests()
	_wizard_tests(host)
	_mode_tests(host)
	host.queue_free()
	await _card_tests()
	await _preflight_tests()
	print("calibration view: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _static_tests() -> void:
	_check("Mode 2 places throttle/yaw left and pitch/roll right",
		CalibrationView.gimbal_functions(2) == [["yaw", "throttle"], ["roll", "pitch"]])
	_check("Mode 1 swaps throttle and pitch", CalibrationView.gimbal_functions(1) == [["yaw", "pitch"], ["roll", "throttle"]])
	var reference := PackedFloat64Array([0.0, 0.0, -1.0, 0.0])
	_check("moving axis is the largest deviation from the reference",
		CalibrationView.moving_axis(PackedFloat64Array([0.05, -0.4, -1.0, 0.3]), reference, 0.1) == 1)
	_check("a resting throttle at its reference is not moving",
		CalibrationView.moving_axis(PackedFloat64Array([0.05, 0.0, -1.0, 0.02]), reference, 0.1) == -1)
	var flight := FlightStub.new()
	var child := Node.new()
	flight.add_child(child)
	_check("stick mode follows the flight's saved overlay setting", CalibrationView.presentation_stick_mode(child) == 1)
	flight.overlay_settings = {"stick_mode": "bad"}
	_check("an invalid saved stick mode falls back to Mode 2", CalibrationView.presentation_stick_mode(child) == 2)
	var orphan := Node.new()
	_check("no setting means Mode 2", CalibrationView.presentation_stick_mode(orphan) == 2)
	orphan.free()
	flight.free()


func _wizard_tests(host: Control) -> void:
	var view := CalibrationView.new()
	host.add_child(view)
	var wizard := Calibration.new()
	var rest := _axes(0, 0, 0, 0)
	view.update(wizard, rest)
	_check("rest step shows the checklist and the rest prompt", view.checklist.visible
		and view.instruction_label.text.begins_with("Centre the sticks") and not view.error_banner.visible)
	_check("prompts no longer name a key", not "Enter" in view.instruction_label.text)
	_check("rest step marks the first chip current", view.strip.chip_state(0) == "current" and view.strip.chip_state(1) == "pending")
	_check("Mode 2: left gimbal has the one-ended throttle", view.left_gimbal.one_ended_y and not view.right_gimbal.one_ended_y)
	_check("before the rest sample no gimbal is live", not view.left_gimbal.is_live() and not view.right_gimbal.is_live())
	_check("rest targets: throttle LOW and centred sticks", view.left_gimbal.target() == Vector2(0, 1)
		and view.left_gimbal.target_label == "LOW" and view.right_gimbal.target() == Vector2.ZERO
		and view.right_gimbal.target_label == "CENTRE")
	_check("no axis is moving at the first reading", view.current_moving_axis() == -1)
	var moved := rest.duplicate()
	moved[6] = 0.9
	view.update(wizard, moved)
	_check("a moved axis is highlighted in the channel monitor", view.current_moving_axis() == 6
		and view.channel_bars[6].highlight == ChannelBarView.Highlight.MOVING
		and view.channel_bars[0].highlight == ChannelBarView.Highlight.IDLE)
	_check("unassigned channels read Axis N", view.channel_bars[6].label == "Axis 6")

	wizard.advance(rest)
	view.update(wizard, rest)
	_check("throttle step hides the checklist and advances the strip", not view.checklist.visible
		and view.strip.chip_state(0) == "done" and view.strip.chip_state(1) == "current")
	_check("throttle step asks for FULL with an arrow from LOW", view.left_gimbal.target() == Vector2(0, -1)
		and view.left_gimbal.target_label == "FULL" and not view.right_gimbal.has_target())
	for k in 11:
		_feed(view, wizard, _axes(k / 10.0, 0, 0, 0))
	_check("the throttle sweep moves the left dot up and is detected", view.left_gimbal.is_live()
		and view.left_gimbal.stick().y < -0.75 and view.detected_label.visible and view.detected_label.text == "Detected: axis 4",
		"%s %s" % [view.left_gimbal.stick(), view.detected_label.text])
	_check("the throttle sweep envelope reaches FULL", view.left_gimbal.has_envelope()
		and view.left_gimbal.envelope().position.y < -0.75)
	for k in 11:
		_feed(view, wizard, _axes(1.0 - k / 10.0, 0, 0, 0))
	_check("after FULL the target moves to LOW", view.left_gimbal.target() == Vector2(0, 1) and view.left_gimbal.target_label == "LOW")
	wizard.advance(rest)
	view.update(wizard, rest)
	_check("throttle assigned: Axis 4 · Throttle with calibrated endpoints", wizard.assigned_axis("throttle") == 4
		and view.channel_bars[4].label == "Axis 4 · Throttle" and view.channel_bars[4].highlight == ChannelBarView.Highlight.ASSIGNED
		and view.channel_bars[4].endpoints().is_equal_approx(Vector2(-0.9, 0.9)))
	_check("calibrated throttle at LOW draws at the bottom", view.left_gimbal.is_live()
		and is_equal_approx(view.left_gimbal.stick().y, 1.0), str(view.left_gimbal.stick()))

	# Roll: hold RIGHT, then LEFT and centre.
	_check("roll step targets RIGHT on the right stick", view.right_gimbal.target() == Vector2(1, 0)
		and view.right_gimbal.target_label == "RIGHT" and not view.left_gimbal.has_target())
	_check("roll prompt uses the glossary", view.instruction_label.text == "Hold the ROLL stick (aileron) fully RIGHT.",
		view.instruction_label.text)
	var held := _axes(0, 1, 0, 0)
	_feed(view, wizard, held)
	_check("held roll previews toward RIGHT before it is confirmed", view.right_gimbal.stick().x > 0.8
		and view.detected_label.text == "Detected: axis 6")
	wizard.advance(held)
	view.update(wizard, held)
	_check("confirmed roll asks for LEFT then centre", wizard.requested_target() == {function = "roll", direction = "left", phase = "opposite"}
		and view.right_gimbal.target() == Vector2(-1, 0) and view.right_gimbal.target_label == "LEFT"
		and "then centre" in view.instruction_label.text and wizard.held_axis() == 6)
	for k in 21:
		_feed(view, wizard, _axes(0, 1.0 - k / 10.0, 0, 0))
	_check("opposite roll sweep moves the dot left with its envelope", view.right_gimbal.stick().x < -0.8
		and view.right_gimbal.envelope().position.x < -0.8 and view.right_gimbal.envelope().end.x > 0.8)
	for k in 11:
		_feed(view, wizard, _axes(0, -1.0 + k / 10.0, 0, 0))
	_check("after the opposite endpoint the target is the centre", view.right_gimbal.target() == Vector2.ZERO
		and view.right_gimbal.target_label == "CENTRE")
	wizard.advance(rest)
	view.update(wizard, rest)
	_check("roll assigned: Axis 6 · Roll", wizard.assigned_axis("roll") == 6 and view.channel_bars[6].label == "Axis 6 · Roll")

	# Pitch: BACK, then FORWARD and centre.
	_check("pitch step targets BACK (down) on the right stick", view.right_gimbal.target() == Vector2(0, 1)
		and view.right_gimbal.target_label == "BACK")
	held = _axes(0, 0, 1, 0)
	_feed(view, wizard, held)
	wizard.advance(held)
	view.update(wizard, held)
	_check("pitch opposite targets FORWARD (up)", view.right_gimbal.target() == Vector2(0, -1)
		and view.right_gimbal.target_label == "FORWARD")
	for value: float in [0.5, 0.0, -0.5, -1.0, -0.5, 0.0]:
		_feed(view, wizard, _axes(0, 0, value, 0))
	wizard.advance(rest)
	view.update(wizard, rest)
	_check("pitch assigned to axis 1", wizard.assigned_axis("pitch") == 1 and view.channel_bars[1].label == "Axis 1 · Pitch")
	view.update(wizard, _axes(0, 0, 1, 0))
	_check("calibrated pitch BACK draws the right dot down", is_equal_approx(view.right_gimbal.stick().y, 1.0),
		str(view.right_gimbal.stick()))
	view.update(wizard, rest)

	# An error from the wizard appears in the banner.
	wizard.advance(rest)
	view.update(wizard, rest)
	_check("wizard error shows the banner", view.error_banner.visible and view.error_label.visible
		and view.error_label.text == wizard.error and not wizard.error.is_empty(), wizard.error)
	_check("yaw step targets RIGHT on the throttle stick at LOW", view.left_gimbal.target() == Vector2(1, 1)
		and view.left_gimbal.target_label == "RIGHT")
	held = _axes(0, 0, 0, -1) # this fixture reports RIGHT as a negative axis
	_feed(view, wizard, held)
	wizard.advance(held)
	view.update(wizard, held)
	_check("a valid step clears the banner", not view.error_banner.visible and not view.error_label.visible)
	for value: float in [-0.5, 0.0, 0.5, 1.0]:
		_feed(view, wizard, _axes(0, 0, 0, value))
	_check("yaw opposite preview: the inverted axis still draws LEFT", view.left_gimbal.stick().x < -0.9
		and view.left_gimbal.target_label == "LEFT", str(view.left_gimbal.stick()))
	for value: float in [0.5, 0.0]:
		_feed(view, wizard, _axes(0, 0, 0, value))
	var finished := wizard.advance(rest)
	_check("synthetic wizard finished", finished and wizard.done() and Calibration.valid(wizard.profile))
	view.set_verify_state(false, false)
	view.update(wizard, rest)
	_check("all four functions are labelled", view.channel_bars[0].label == "Axis 0 · Yaw"
		and view.channel_bars[4].label == "Axis 4 · Throttle" and view.channel_bars[1].label == "Axis 1 · Pitch"
		and view.channel_bars[6].label == "Axis 6 · Roll")
	_check("verify panel shows with nothing checked", view.verify_panel.visible
		and not view.verify_panel.find_child("ReachedFull", true, false).checked
		and not view.verify_panel.find_child("BackToLow", true, false).checked)
	_check("verify step: strip on Verify, throttle target FULL", view.strip.chip_state(5) == "current"
		and view.strip.chip_state(4) == "done" and view.left_gimbal.target() == Vector2(0, -1)
		and view.step_label.text == "Calibration complete")
	var full := _axes(1, 0, 0, 0)
	view.set_verify_state(true, false)
	view.update(wizard, full)
	_check("verify bar follows the calibrated throttle", is_equal_approx(view.verify_bar.current_value(), 1.0)
		and view.verify_panel.find_child("ReachedFull", true, false).checked
		and view.left_gimbal.target() == Vector2(0, 1))
	view.set_verify_state(true, true)
	view.update(wizard, rest)
	_check("verified: both checks, every chip done, no target", view.verify_panel.find_child("BackToLow", true, false).checked
		and view.strip.chip_state(5) == "done" and not view.left_gimbal.has_target())
	var bars_before := view.channel_bars[3].redraw_requests
	var gimbal_before := view.right_gimbal.redraw_requests
	for frame in 5:
		view.update(wizard, rest)
	_check("unchanged samples do not redraw the monitor or gimbals", view.channel_bars[3].redraw_requests == bars_before
		and view.right_gimbal.redraw_requests == gimbal_before)
	_check("the view never takes focus or the mouse", _passive(view))
	view.free()


func _mode_tests(host: Control) -> void:
	var view := CalibrationView.new()
	host.add_child(view)
	_check("Mode 2 captions", view.left_gimbal.caption == "Throttle · Yaw" and view.right_gimbal.caption == "Pitch · Roll")
	view.stick_mode = 1
	_check("Mode 1 moves the one-ended throttle to the right stick", not view.left_gimbal.one_ended_y
		and view.right_gimbal.one_ended_y and view.left_gimbal.caption == "Pitch · Yaw"
		and view.right_gimbal.caption == "Throttle · Roll")
	var wizard := Calibration.new()
	wizard.advance(_axes(0, 0, 0, 0))
	view.update(wizard, _axes(0, 0, 0, 0))
	_check("Mode 1 throttle step targets the right stick", view.right_gimbal.target() == Vector2(0, -1)
		and not view.left_gimbal.has_target())
	_check("presentation mode does not change the wizard", wizard.step == 1 and wizard.requested_target().function == "throttle")
	view.free()


func _passive(node: Node) -> bool:
	if node is Control and ((node as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE
			or ((node as Control).focus_mode != Control.FOCUS_NONE and not node is Label)):
		printerr("not passive: ", node.get_path())
		return false
	for child in node.get_children():
		if not _passive(child):
			return false
	return true


func _card_tests() -> void:
	var session := FakeSession.new()
	session.radio.axes = _axes(0, 0, 0, 0)
	root.add_child(session)
	var focus_holder := Button.new()
	focus_holder.text = "flight focus"
	root.add_child(focus_holder)
	focus_holder.grab_focus()
	var card := CalibrationCard.new(session)
	session.add_child(card)
	await process_frame
	_check("card hidden without a wizard", not card.visible)
	session.calibration = Calibration.new()
	await process_frame
	await process_frame
	var prompt := card.find_child("Prompt", true, false) as Label
	_check("card shows the shared view and the rest prompt", card.visible and prompt != null
		and prompt.text.begins_with("Centre the sticks") and card.find_child("ChannelMonitor", true, false) != null)
	_check("card keeps the key hint", (card.find_child("Keys", true, false) as Label).text.begins_with("Enter or controller Accept"))
	_check("card never takes focus", root.gui_get_focus_owner() == focus_holder)
	var all_ignore := true
	for node: Node in card.find_children("*", "Control", true, false):
		var control := node as Control
		if control.mouse_filter != Control.MOUSE_FILTER_IGNORE or control.focus_mode != Control.FOCUS_NONE:
			all_ignore = false
			printerr("card control takes input: ", control.get_path())
	_check("every card control ignores the mouse and focus", all_ignore)
	session.calibration.advance(session.radio.axes)
	session.radio.axes = _axes(1, 0, 0, 0)
	await process_frame
	_check("card follows the session's wizard and radio axes", card.view.step_label.text == "Step 2 of 5"
		and card.view.left_gimbal.is_live() and card.view.current_moving_axis() == 4)
	session.calibration = RefCounted.new() # foreign doubles must not crash the card
	await process_frame
	session.calibration = null
	await process_frame
	_check("card hides when the wizard ends", not card.visible and root.gui_get_focus_owner() == focus_holder)
	session.queue_free()
	focus_holder.queue_free()
	await process_frame


func _frames(count: int) -> void:
	for frame in count:
		await process_frame


func _preflight_tests() -> void:
	_raw = _axes(0, 0, 0, 0)
	var registry := RadioRegistry.new()
	var setup := RadioCalibration.new()
	_check("preflight accepts the connected radio", setup.configure(registry, 5, {"kind": "radio"}))
	setup.read_axis = func(_id: int, axis: int) -> float: return _raw[axis]
	var finished: Array = []
	setup.completed.connect(func(profile: Dictionary, _warning: String) -> void: finished.append(profile))
	root.add_child(setup)
	await _frames(2)
	_check("preflight keeps its node names", setup.find_child("RadioCalibrationCard", true, false) != null
		and setup.find_child("NextCalibrationStep", true, false) == setup.next_button
		and setup.find_child("CancelCalibration", true, false) == setup.cancel_button)
	_check("Next has the initial focus", root.gui_get_focus_owner() == setup.next_button)
	_check("preflight hosts the shared view", setup.view != null and setup._prompt == setup.view.instruction_label
		and setup._device_label.text == "Fixture radio" and setup.view.checklist.visible)
	setup.advance() # rest
	await _frames(1)
	setup.advance() # throttle without a sweep
	await _frames(1)
	_check("missing sweep shows the error banner", setup._error_label.visible and setup.view.error_banner.visible
		and setup._wizard.step == 1)
	for value: float in [0.5, 1.0, 0.5, 0.0]:
		_raw = _axes(value, 0, 0, 0)
		await _frames(1)
	setup.advance()
	await _frames(1)
	_check("throttle step accepted through Next", setup._wizard.assigned_axis("throttle") == 4 and not setup._error_label.visible)
	for move: Array in [[1, 1.0], [2, 1.0], [3, -1.0]]:
		var function: int = move[0]
		var held := [0.0, 0.0, 0.0, 0.0]
		held[function] = move[1]
		_raw = _axes(held[0], held[1], held[2], held[3])
		await _frames(1)
		setup.advance()
		await _frames(1)
		_check("held direction asks for the opposite endpoint (%d)" % function, "then centre" in setup._prompt.text, setup._prompt.text)
		for value: float in [-move[1], 0.0]:
			held[function] = value
			_raw = _axes(held[0], held[1], held[2], held[3])
			await _frames(1)
		setup.advance()
		await _frames(1)
	_check("preflight wizard finished, Next waits for throttle verification", setup._wizard.done() and setup.next_button.disabled
		and setup.view.verify_panel.visible and "throttle 4" in setup._result_label.text)
	_raw = _axes(1, 0, 0, 0)
	await _frames(1)
	_check("FULL is checked", setup.view.verify_panel.find_child("ReachedFull", true, false).checked and setup.next_button.disabled)
	_raw = _axes(0, 0, 0, 0)
	await _frames(1)
	_check("back to LOW enables Use calibration", setup.view.verify_panel.find_child("BackToLow", true, false).checked
		and not setup.next_button.disabled and setup.next_button.text == "Use calibration")
	setup.advance()
	_check("Use calibration completes with a valid profile", finished.size() == 1 and Calibration.valid(finished[0]))
	setup.queue_free()
	await _frames(1)

	var cancelled: Array = []
	var other := RadioCalibration.new()
	other.configure(registry, 5, {"kind": "radio"})
	other.read_axis = func(_id: int, axis: int) -> float: return _raw[axis]
	other.cancelled.connect(func(reason: String) -> void: cancelled.append(reason))
	root.add_child(other)
	await _frames(1)
	other.cancel_button.pressed.emit()
	_check("Cancel still cancels with the unchanged-draft reason", cancelled.size() == 1
		and cancelled[0] == "Calibration cancelled. The draft is unchanged.")
	other.queue_free()
	await _frames(1)
