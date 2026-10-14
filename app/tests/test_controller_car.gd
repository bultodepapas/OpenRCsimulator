extends SceneTree

const Activity = preload("res://vehicles/ground/ground_scene.gd")
const Registry = preload("res://input/controller_registry.gd")
const UiInput = preload("res://ui/ui_input.gd")

class TestActivity extends Activity:
	var test_keys := {}
	func _key(code: Key) -> bool:
		return bool(test_keys.get(code, false))

var checks := 0
var failures := 0
var activity: Node3D
var axes := {JOY_AXIS_LEFT_X: 0.10, JOY_AXIS_TRIGGER_RIGHT: 0.03, JOY_AXIS_TRIGGER_LEFT: 0.02}
var reverse_held := false
const PAD := 15
const RADIO := {"id": 13, "name": "RC radio", "kind": "radio", "known": false}
const UNKNOWN := {"id": 14, "name": "Unmapped joystick", "kind": "joystick", "known": false}
const GAMEPAD := {"id": PAD, "name": "DualSense", "guid": "test-car-pad", "known": true, "kind": "gamepad"}

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + description)

func step() -> void:
	activity._physics_process(1.0 / 240.0)
	activity._process(0.0)

func button(index: JoyButton, device := PAD) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = device
		event.button_index = index
		event.pressed = pressed
		Input.parse_input_event(event)
	await process_frame
	await process_frame

func create_activity(source: RefCounted) -> Node3D:
	var candidate := TestActivity.new()
	candidate.controller_registry = source
	candidate.use_practice_fixture = true
	candidate.enable_audio = false
	candidate.enable_course_visual = false
	candidate.joy_axis_reader = func(_id: int, axis: JoyAxis) -> float: return float(axes.get(axis, 0.0))
	candidate.joy_button_reader = func(_id: int, index: JoyButton) -> bool: return index == JOY_BUTTON_B and reverse_held
	root.add_child(candidate)
	candidate.set_physics_process(false)
	candidate.set_process(false)
	return candidate

func _run() -> void:
	TranslationServer.set_locale("es")
	var shared := Registry.new()
	shared.update_devices([RADIO, UNKNOWN, GAMEPAD])
	shared.select_device("flight", 13)
	shared.select_device("ui", 14)
	activity = create_activity(shared)
	await process_frame
	await process_frame
	check(activity.startup_error.is_empty(), "car starts")
	if not activity.startup_error.is_empty():
		activity.free()
		quit(1)
		return
	check(activity.controller_registry != shared and activity._controller_device_id == PAD, "aircraft radio does not override a recognized driving gamepad")
	check(shared.selected_device_id("flight") == 13 and shared.selected_device_id("ui") == 14, "starting car preserves aircraft selections")
	check(activity.dashboard.controller_choice.item_count == 2, "garage lists keyboard and mapped gamepad, not raw devices")
	check(UiInput.selected_gamepad_id() == PAD, "driving gamepad owns garage navigation")
	check(activity.dashboard.control_hint.text.contains("R2") and activity.dashboard.control_hint.text.contains("L2") and activity.dashboard.resume_button.text.contains(tr("Options")), "DualSense prompts follow its actual driving scheme")
	for i in 4: step()
	check(activity._controls_ready(activity._last_controls) and activity.session.paused and activity.session.tick == 0, "resting stick and trigger drift remain ready while garage freezes time")
	check(activity.dashboard.input_status.text.contains("listos"), "garage reports controls ready")
	axes[JOY_AXIS_TRIGGER_RIGHT] = 0.8
	activity.handle_action("resume")
	check(activity.session.paused and activity.dashboard.menu_visible, "fresh trigger at click rejects stale neutral")
	axes[JOY_AXIS_TRIGGER_RIGHT] = 0.03
	step()
	await button(JOY_BUTTON_START, 14)
	check(activity.session.paused, "unselected device cannot resume")
	await button(JOY_BUTTON_START)
	check(not activity.session.paused and not activity.dashboard.menu_visible, "Start resumes from actual GUI input with resting drift")
	axes[JOY_AXIS_TRIGGER_RIGHT] = 1.0
	axes[JOY_AXIS_LEFT_X] = 0.56
	step()
	var tape: PackedFloat64Array = activity.session.control_tape_snapshot()
	check(tape.size() == 4 and tape[0] == 1.0 and tape[1] > 0.0 and tape[2] == 0.0 and tape[3] == 0.0, "RT and right steer reach accepted simulation command")
	axes[JOY_AXIS_TRIGGER_LEFT] = 0.52
	step()
	tape = activity.session.control_tape_snapshot()
	check(tape[-4] == 0.0 and is_equal_approx(tape[-2], 0.5), "LT brakes proportionally and wins over RT")
	axes[JOY_AXIS_TRIGGER_LEFT] = 0.02
	axes[JOY_AXIS_LEFT_X] = -0.56
	reverse_held = true
	step()
	tape = activity.session.control_tape_snapshot()
	check(tape[-4] == 1.0 and tape[-3] < 0.0 and tape[-1] == 1.0, "reverse modifier and left steer reach accepted command")
	reverse_held = false
	axes[JOY_AXIS_LEFT_X] = 0.10
	axes[JOY_AXIS_TRIGGER_RIGHT] = 0.03
	var camera_before: int = activity.camera_rig.mode
	var state_before: PackedFloat64Array = activity.session.state_snapshot()
	await button(JOY_BUTTON_X)
	check(activity.camera_rig.mode != camera_before and activity.session.state_snapshot() == state_before, "X/Square changes camera without touching physics")
	await button(JOY_BUTTON_Y)
	check(activity.session.paused and not activity.session.run_valid and activity.dashboard.menu_visible, "Y/Triangle recovers explicitly and marks assistance")
	activity.handle_action("reset")
	for i in 3: step()
	await button(JOY_BUTTON_START)
	check(not activity.session.paused and activity.session.run_valid, "reset followed by neutral Start drives again")
	activity._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await button(JOY_BUTTON_START)
	check(activity.session.paused and activity.dashboard.menu_visible, "unfocused Start is ignored")
	activity._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(activity.session.paused, "focus return never resumes automatically")
	axes[JOY_AXIS_TRIGGER_RIGHT] = 0.8
	step()
	activity.handle_action("resume")
	check(activity.session.paused, "held trigger across focus cannot resume")
	axes[JOY_AXIS_TRIGGER_RIGHT] = 0.03
	step()
	await button(JOY_BUTTON_START)
	check(not activity.session.paused, "released trigger allows explicit resume after focus")
	axes[JOY_AXIS_TRIGGER_LEFT] = NAN
	step()
	check(activity.session.paused and activity.dashboard.menu_visible and not activity._last_controls.get("armed", false), "invalid native trigger sample pauses instead of becoming zero")
	axes[JOY_AXIS_TRIGGER_LEFT] = 0.02
	step()
	activity.handle_action("resume")
	shared.update_devices([RADIO, UNKNOWN])
	check(activity.session.paused and activity._controller_requires_selection and UiInput.selected_gamepad_id() == -1, "disconnect pauses and removes stale navigation ownership")
	shared.update_devices([RADIO, UNKNOWN, GAMEPAD])
	step()
	activity.handle_action("resume")
	check(activity.session.paused and activity._controller_requires_selection, "reconnect does not take over automatically")
	activity.select_driving_device(PAD)
	step()
	await button(JOY_BUTTON_START)
	check(not activity.session.paused, "garage reselection acknowledges new connection generation")
	activity.open_garage()
	activity.dashboard.controller_choice.item_selected.emit(0)
	for i in 3: step()
	check(activity._controller_device_id == -1 and not activity._controller_requires_selection, "garage selector chooses keyboard without leaving activity")
	activity.test_keys[KEY_W] = true
	activity.handle_action("resume")
	check(activity.session.paused, "fresh keyboard throttle also rejects stale neutral")
	activity.test_keys.clear()
	step()
	activity.handle_action("resume")
	activity.test_keys = {KEY_S: true, KEY_A: true}
	step()
	tape = activity.session.control_tape_snapshot()
	check(tape[-4] == 1.0 and tape[-3] == -1.0 and tape[-1] == 1.0, "keyboard reverse and left work after local selection")
	check(shared.selected_device_id("flight") == 13 and shared.selected_device_id("ui") == 14, "driving selection never writes aircraft ownership")
	activity.test_keys.clear()
	activity.free()
	await process_frame
	shared.update_devices([RADIO, UNKNOWN])
	activity = create_activity(shared)
	for i in 3: step()
	activity.handle_action("resume")
	check(activity._controller_device_id == -1 and not activity.session.paused, "radio-only setup falls back to usable keyboard")
	shared.update_devices([RADIO, UNKNOWN, GAMEPAD])
	step()
	check(activity._controller_device_id == -1 and not activity.session.paused, "new gamepad never steals keyboard during driving")
	activity.free()
	await process_frame
	await process_frame
	print("Car controller audit: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
