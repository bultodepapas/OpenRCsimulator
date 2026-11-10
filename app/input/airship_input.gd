## BL-10: pilot input for the RC blimp. Reuses the shared RC reader (radio, joystick, gamepad with calibrated
## profiles) and the Mode 2 keyboard layout, and returns semantic sticks [roll, pitch, yaw, throttle]:
## roll = differential side thrust, pitch > 0 (stick back) = vector up / nose up, yaw > 0 = nose right,
## throttle 0..1 = main thrust. Throttle is unidirectional with a low-end neutral, matching the existing radio
## arming endpoint; the reversible stern thruster is driven only by the spring-centred yaw stick.
extends RefCounted

const RcInput = preload("res://input/rc_input.gd")
const RcCalibration = preload("res://input/rc_calibration.gd")
const ControllerStore = preload("res://input/controller_profile_store.gd")
const Commands = preload("res://input/commands.gd")
const Keyboard = preload("res://input/keyboard.gd")

const ARM_THROTTLE := 0.05

var radio: RefCounted = RcInput.new()
var profiles_path := "user://rc_calibration.cfg"
var read_axis: Callable = Input.get_joy_axis
var read_button: Callable = Input.is_joy_button_pressed
var read_keys: Callable = Keyboard.read_raw
var keyboard_commands: Dictionary = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
var message := ""


func connect_first_device() -> void:
	for id: int in Input.get_connected_joypads():
		if not radio.connected:
			on_connection_changed(id, true)


func on_connection_changed(id: int, connected: bool) -> void:
	if connected and not radio.connected:
		var info: Dictionary = Input.get_joy_info(id)
		info.merge({name = Input.get_joy_name(id), guid = Input.get_joy_guid(id), known = Input.is_joy_known(id)})
		var device_info := func(other: int) -> Dictionary:
			var record: Dictionary = Input.get_joy_info(other)
			record.merge({name = Input.get_joy_name(other), guid = Input.get_joy_guid(other), known = Input.is_joy_known(other)})
			return record
		var unique: bool = ControllerStore.legacy_identity_is_unique_for_ids(id, info, Input.get_connected_joypads(), device_info)
		var saved: Dictionary = RcCalibration.load_profile(profiles_path, RcInput.key_for(id, info)) if unique else {}
		radio.connect_device(id, info, saved)
		if radio.is_rate_throttle():
			radio.set_rate_throttle_for_start(0.0)
		message = "%s connected: lower the throttle to arm." % radio.device_name
	elif not connected and radio.connected and id == radio.device_id:
		radio.disconnect_device()
		message = "Controller disconnected: flight paused."


func on_event(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		radio.on_motion(event.device, event.axis, event.axis_value)
	elif event is InputEventJoypadButton:
		radio.on_button(event.device, event.button_index, event.pressed)


## A spring-centred gamepad keeps a virtual throttle; restarting returns it to zero.
func reset_throttle() -> void:
	keyboard_commands = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	if radio.connected and radio.is_rate_throttle():
		radio.set_rate_throttle_for_start(0.0)
	if radio.connected:
		radio.require_neutral(false)


func source() -> String:
	if radio.connected:
		return "gamepad" if radio.is_gamepad() else "radio"
	return "keyboard"


## Sample once per physics tick. Returns {sticks, armed, source, error}.
func sample(dt: float, integrate: bool) -> Dictionary:
	if radio.connected:
		radio.poll(read_axis, dt, read_button, integrate)
		var error := str(radio.input_error) if not str(radio.input_error).is_empty() else str(radio.profile_error)
		var s: Dictionary = radio.sticks()
		return {sticks = PackedFloat64Array([s.roll, s.pitch, s.yaw, s.throttle]), armed = bool(radio.armed) and error.is_empty(),
			source = source(), error = error, throttle_low = float(s.throttle) <= ARM_THROTTLE}
	var raw: Dictionary = read_keys.call()
	if integrate:
		keyboard_commands = Commands.step_commands(keyboard_commands, raw, dt)
	var k := keyboard_commands
	return {sticks = PackedFloat64Array([k.roll, k.pitch, k.yaw, k.throttle]), armed = true, source = "keyboard", error = "",
		throttle_low = float(k.throttle) <= ARM_THROTTLE}
