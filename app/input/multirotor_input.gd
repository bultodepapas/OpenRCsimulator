## DR-14/15: pilot input for the experimental FPV quad. Reuses the shared RC reader (device ownership, calibrated
## profiles, fresh-evidence guards) and the Mode 2 keyboard layout, and produces the flight controller's 9-value
## pilot frame (physics/multirotor/flight_controller.gd): calibrated, PRE-expo sticks in [-1, 1] (the controller's
## rates curve is the one and only shaping), roll > 0 right, pitch > 0 stick back (nose up), yaw > 0 right.
## Throttle policy follows the source and is fixed for a flight: a radio/joystick (or gamepad trigger) throttle is
## absolute [0, 1]; a spring-centred gamepad stick and the keyboard send the centred stick in [-1, 1] and the
## controller integrates it (nothing is integrated here). Arm is a level the controller edge-checks itself (OFF then
## a fresh ON at low throttle); this adapter only latches toggles or reads the radio switch. Presentation-side input:
## it never touches a session.
extends RefCounted

const RcInput = preload("res://input/rc_input.gd")
const RcCalibration = preload("res://input/rc_calibration.gd")
const ControllerStore = preload("res://input/controller_profile_store.gd")
const ControllerProfile = preload("res://input/controller_profile.gd")
const ControllerActions = preload("res://input/controller_actions.gd")
const SmokeAux = preload("res://input/smoke_aux.gd")
const Commands = preload("res://input/commands.gd")
const Keyboard = preload("res://input/keyboard.gd")
const Spec = preload("res://spec.gd")
const FC = preload("res://physics/multirotor/flight_controller.gd")

## Explicit mapping (also reported in `raw`). Keys do not collide with the activity keys (P, Esc, R, C, H, F10, F11,
## [ ] - =) or the Mode 2 flying keys (arrows, W A S D).
const ARM_KEY := KEY_E
const MODE_KEY := KEY_M
## DR-19e: the turtle-mode (crash flip) toggle: F on the keyboard, Y on a gamepad (never a button an AUX channel or
## Pause owns). The controller engages it only on an arming edge, never in flight.
const TURTLE_KEY := KEY_F
const TURTLE_BUTTON := JOY_BUTTON_Y
const ARM_BUTTON := JOY_BUTTON_LEFT_SHOULDER
const MODE_BUTTON := JOY_BUTTON_RIGHT_SHOULDER
## D6-UX-01: a controller profile with the explicit "arm" AUX channel bound arms from that switch level (any source).
const ARM_AUX := "arm"
## Legacy fallback, kept exactly: a radio/joystick profile with no "arm" binding but a calibrated switch on this AUX
## function (Controls "Landing gear") arms from that switch level, as before D6-UX-01.
const RADIO_ARM_AUX := "gear"
## D6-UX-01: a profile with the "flight_mode" AUX channel bound takes Angle/Acro from that switch; the M key and the
## gamepad mode button are then ignored (the switch wins, as the arm switch disables the arm toggle).
const MODE_AUX := "flight_mode"
## A switch position at or above this AUX amount is ON.
const ARM_SWITCH_ON := 0.5
## Flight-mode switch: a request at or above this amount is Acro, below it Angle. The AUX OFF position (amount 0,
## also the position its fresh-OFF arming needs) is the self-levelling Angle mode; a 2-position switch is OFF Angle /
## ON Acro, and a 3-position switch (0, 0.5, 1) is Angle in its first position and Acro in the other two. The
## controller has no third mode (no Horizon), so the middle detent cannot mean anything else.
const MODE_SWITCH_ACRO := 0.5
## Throttle limit choices (pilot preference: the share of the command range a full throttle stick reaches). The
## 5-inch quad hovers near 15 % and climbs at tens of m/s from a third of the range, so the centred-stick sources
## (keyboard, gamepad) start limited; a radio flies the full range. The value is a session option: a change takes a
## fresh prepare on the pad, never mid-flight.
const THROTTLE_LIMITS := [0.35, 0.45, 0.6, 1.0]
const RADIO_THROTTLE_LIMIT := 1.0
const TRAINER_THROTTLE_LIMIT := 0.45

var radio: RefCounted = RcInput.new()
var profiles_path := "user://rc_calibration.cfg"
var read_axis: Callable = Input.get_joy_axis
var read_button: Callable = Input.is_joy_button_pressed
## Test seam: {roll, pitch, yaw, throttle} in [-1, 1] (Keyboard.read_raw) plus {arm, mode} booleans for the keys.
var read_keys: Callable
var message := ""
## Increases on every connection change or source switch; the controller drops authority on a new generation.
var source_generation := 0
var _arm_latch := false
var _last_arm_channel := ""
var _mode := FC.FLIGHT_ANGLE
var _arm_input_held := false
var _mode_input_held := false
var _turtle := false
var _turtle_input_held := false
var _turtle_button := -1
## The turtle request was engaged on an arming edge: the following disarm ends it (one flip per request; the next arm
## flies). A request made while armed (after a crash, still armed) waits: the pilot's mode keeps flying until the disarm.
var _turtle_used := false
## Audit: the controller's motor state, reported after each accepted tick (note_motor_state). Once reported, only an
## arming edge the controller accepted consumes the request; a refused arm leaves it pending. Without reports (a bare
## input driven by a test) the arming edge alone consumes it, as before.
var _motor_reported := false
var _motor_armed := false
var _turtle_engaged := false
var _actions := 0
var _keyboard_sticks := {roll = 0.0, pitch = 0.0, yaw = 0.0}
var _source_key := ""
## Pilot-chosen throttle limit per source kind ("radio", "gamepad", "keyboard"); absent = the kind's default.
var _throttle_limits := {}
## Key names for `raw` and the OSD bindings, looked up once (the sample runs every 240 Hz tick).
var _arm_key_name := OS.get_keycode_string(ARM_KEY)
var _mode_key_name := OS.get_keycode_string(MODE_KEY)
## Audit A02: the gamepad shortcuts in force for the active source (-1 = none). A button that a configured AUX
## channel or the effective Pause binding owns is never also an arm or mode toggle (one authority per control).
var _arm_button := -1
var _mode_button := -1
var _pause_button := -1
## DR-14d: the source's effective "Restart flight" binding ({} = none): a pad's View/Back by default, a radio's
## saved switch (the EdgeTX FPV preset: CH9). Never a control an AUX channel or Pause owns.
var _restart_binding: Dictionary = {}
## Audit A03: ordinary-hold continuity of an arm SWITCH. A pause resets the AUX channels (no edge may be queued
## while the menu is open), so on the first resumed ticks the switch has no valid request yet. While the same
## source, mapping and connection hold and the physical switch was read ON through the whole hold, the arm level
## stays ON until the channel is valid again; any OFF reading, an unknown position or a changed source ends it.
var _arm_continuity := false
var _continuity_generation := -1
var _continuity_profile: Dictionary = {}
## The hold could not keep the arm switch's ON (not ON at entry, unreadable, or changed): resuming disarms.
var _continuity_lost := false
var _last_arm_level := false


func _init() -> void:
	read_keys = _read_keyboard
	_source_key = _current_source_key()
	_mode = default_mode(source())


static func _read_keyboard(include_axes := true) -> Dictionary:
	var raw: Dictionary = Keyboard.read_raw() if include_axes else {}
	raw.arm = Input.is_physical_key_pressed(ARM_KEY)
	raw.mode = Input.is_physical_key_pressed(MODE_KEY)
	raw.turtle = Input.is_physical_key_pressed(TURTLE_KEY)
	return raw


## Acro for a radio (a pilot with a transmitter expects rate mode); Angle for gamepad and keyboard.
static func default_mode(kind: String) -> int:
	return FC.FLIGHT_ACRO if kind == "radio" else FC.FLIGHT_ANGLE


## Full range for a radio (absolute throttle); a trainer limit for gamepad and keyboard.
static func default_throttle_limit(kind: String) -> float:
	return RADIO_THROTTLE_LIMIT if kind == "radio" else TRAINER_THROTTLE_LIMIT


## The choice after `current` in THROTTLE_LIMITS (wrapping); an unlisted value goes to the first choice above it.
static func next_throttle_limit(current: float) -> float:
	for value: float in THROTTLE_LIMITS:
		if value > current + 1.0e-6:
			return value
	return THROTTLE_LIMITS[0]


## The throttle limit the next prepared flight uses for the current source.
func throttle_limit() -> float:
	var kind := source()
	return float(_throttle_limits.get(kind, default_throttle_limit(kind)))


## Cycle the current source's limit; returns the new value (applied by the next prepare, never mid-flight).
func cycle_throttle_limit() -> float:
	var next := next_throttle_limit(throttle_limit())
	_throttle_limits[source()] = next
	return next


## Bindings of the active source for the OSD hints: {arm: key or button name, arm_switch: an AUX switch arms instead,
## throttle_up: key name or "" when the source has a stick, source: radio, gamepad or keyboard}. D6-UX-01 adds
## (additively) arm_aux: the AUX channel that arms ("arm", legacy "gear" or ""), mode: the mode toggle's key or
## button name, mode_switch: the "flight_mode" AUX switch sets the mode instead.
## Audit A02/A18: arm_button and mode_button name the gamepad shortcut only while it is in force (a button an AUX
## channel or Pause owns is not one); arm_control and mode_control describe a bound AUX switch's physical control.
func bindings() -> Dictionary:
	var result := {arm = _arm_key_name, arm_switch = arm_from_switch(), arm_aux = arm_aux(), throttle_up = "",
		source = source(), mode = _mode_key_name, mode_switch = mode_from_switch(), arm_button = "", mode_button = "",
		arm_control = aux_control_text(arm_aux()), mode_control = aux_control_text(MODE_AUX) if mode_from_switch() else "",
		pause_button = _button_text(_pause_button), turtle = OS.get_keycode_string(TURTLE_KEY),
		turtle_button = _button_text(_turtle_button) if radio.connected and radio.is_gamepad() else "",
		restart_control = _control_text(_restart_binding) if not _restart_binding.is_empty() else "", axes = {throttle = stick_axis("throttle"), yaw = stick_axis("yaw"),
		roll = stick_axis("roll"), pitch = stick_axis("pitch")}}
	match result.source:
		"gamepad":
			if _arm_button >= 0:
				result.arm = "LB"
				result.arm_button = "LB"
			if _mode_button >= 0:
				result.mode = "RB"
				result.mode_button = "RB"
		"keyboard":
			result.throttle_up = "W"
	return result


## DR-14d: the source's effective Restart flight binding ({} = none; the keyboard keeps R).
func restart_binding() -> Dictionary:
	return _restart_binding


## The active gamepad's effective Pause button (-1: none, or not a gamepad); the activity pauses only on it.
func pause_button() -> int:
	return _pause_button


## The calibrated source axis of a flight channel (-1 for the keyboard or an unmapped channel), for the help.
func stick_axis(channel_name: String) -> int:
	if not radio.connected:
		return -1
	var channel: Variant = radio.profile.get(channel_name, {})
	return int((channel as Dictionary).get("axis", -1)) if typeof(channel) == TYPE_DICTIONARY else -1


## The physical control of a bound AUX channel ("" when unbound): a button name, a calibrated axis or the buttons
## of a maintained switch.
func aux_control_text(channel_name: String) -> String:
	if channel_name.is_empty() or not _aux_bound(channel_name):
		return ""
	var binding: Dictionary = radio.profile.aux[channel_name]
	match str(binding.get("type", "")):
		"button", "axis":
			return _control_text(binding)
		"switch":
			var names := PackedStringArray()
			for button: Variant in SmokeAux.bound_buttons(binding):
				names.append(_button_text(int(button)))
			return " / ".join(names)
	return ""


func _button_text(button: int) -> String:
	return _control_text({type = "button", button = button}) if button >= 0 else ""


## A binding's physical control as the pilot knows it: SDL names on a gamepad, the joystick's own 1-based button
## number on a radio (an EdgeTX radio's CH9 is its button 1), never a gamepad face-button name for a radio.
func _control_text(binding: Dictionary) -> String:
	if str(binding.get("type", "")) == "button" and not radio.is_gamepad():
		return TranslationServer.translate("Button %d") % (int(binding.get("button", -1)) + 1)
	return ControllerActions.binding_text(binding)


## Recompute the gamepad shortcuts for the active source and profile (audit A02): LB arms and RB changes the mode
## only when no arm/mode switch replaces them and neither the profile's AUX channels nor its Pause binding own that
## button; Pause is the profile's effective Pause button unless an AUX channel owns it. Fixed-wing actions the quad
## never dispatches (LB's inherited throttle cut) do not count as owners.
func _refresh_shortcuts() -> void:
	_arm_button = -1
	_mode_button = -1
	_turtle_button = -1
	_pause_button = -1
	_restart_binding = {}
	if not radio.connected or not bool(radio.profile.get("configured", true)):
		return
	var profile: Dictionary = radio.profile
	var effective: Dictionary = ControllerActions.effective_bindings(profile, ControllerActions.MULTIROTOR_CAPABILITIES)
	var owned: Dictionary = ControllerActions.aux_owned_buttons(profile)
	var restart: Variant = effective.get("restart_flight", {})
	if typeof(restart) == TYPE_DICTIONARY and str((restart as Dictionary).get("type", "")) in ["button", "axis"] 			and not ControllerActions.binding_conflicts_aux(restart, profile) 			and not ControllerActions.same_binding(restart, effective.get("pause", {})):
		_restart_binding = (restart as Dictionary).duplicate(true)
	if not radio.is_gamepad():
		return
	var pause: Dictionary = effective.get("pause", {})
	if str(pause.get("type", "")) == "button" and not owned.has(int(pause.get("button", -1))):
		_pause_button = int(pause.button)
		owned[_pause_button] = "pause"
	if arm_aux().is_empty() and not owned.has(int(ARM_BUTTON)):
		_arm_button = ARM_BUTTON
	if not mode_from_switch() and not owned.has(int(MODE_BUTTON)):
		_mode_button = MODE_BUTTON
	if not owned.has(int(TURTLE_BUTTON)):
		_turtle_button = TURTLE_BUTTON


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
		connect_device(id, info, saved)
	elif not connected and radio.connected and id == radio.device_id:
		radio.disconnect_device()
		_source_changed()
		message = "Controller disconnected: the motors are disarmed."


## Connect one device with an optional saved profile (also the test seam for profiles).
func connect_device(id: int, info: Dictionary, saved: Dictionary = {}) -> void:
	radio.connect_device(id, info, saved)
	_source_changed()
	message = "%s connected." % radio.device_name


## Fly from the keyboard (the app selected no flight device): drop a connected device as a source change.
func use_keyboard() -> void:
	if not radio.connected:
		return
	radio.disconnect_device()
	_source_changed()
	message = "Keyboard selected: the motors are disarmed."


## Activate another profile on the connected device; a different mapping is a new source generation.
func use_profile(profile: Dictionary, label: String = "calibrated") -> bool:
	if not radio.use_profile(profile, label):
		return false
	_source_changed()
	return true


func on_event(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		radio.on_motion(event.device, event.axis, event.axis_value)
	elif event is InputEventJoypadButton:
		radio.on_button(event.device, event.button_index, event.pressed)


## "radio" (radio or joystick profile), "gamepad" or "keyboard".
func source() -> String:
	if radio.connected:
		return "gamepad" if radio.is_gamepad() else "radio"
	return "keyboard"


## The throttle policy the current source implies; the activity fixes it for a flight.
func throttle_policy() -> String:
	match source():
		"keyboard":
			return "rate"
		"gamepad":
			return "rate" if radio.is_rate_throttle() else "absolute"
	return "absolute"


## Whether the arm level comes from an AUX switch rather than a latched toggle.
func arm_from_switch() -> bool:
	return not arm_aux().is_empty()


## The AUX channel the arm level comes from: "arm" when the profile binds it (any connected source), else the legacy
## radio "gear" switch (radio/joystick profiles only, exactly as before D6-UX-01), else "" (the arm toggle).
func arm_aux() -> String:
	if not radio.connected:
		return ""
	if _aux_bound(ARM_AUX):
		return ARM_AUX
	if not radio.is_gamepad() and _aux_bound(RADIO_ARM_AUX):
		return RADIO_ARM_AUX
	return ""


## Whether the flight mode comes from the "flight_mode" AUX switch rather than the M key / gamepad toggle.
func mode_from_switch() -> bool:
	return radio.connected and _aux_bound(MODE_AUX)


func _aux_bound(channel_name: String) -> bool:
	var aux: Variant = radio.profile.get("aux", {})
	return typeof(aux) == TYPE_DICTIONARY and typeof(aux.get(channel_name)) == TYPE_DICTIONARY \
		and not (aux[channel_name] as Dictionary).is_empty()


## Rate policy: the next integrating sample asks the controller to zero its virtual throttle first.
func request_throttle_reset() -> void:
	_actions |= FC.ACTION_THROTTLE_RESET


## The activity attests OFF then ON at low throttle in the new source generation (next integrating sample only).
func attest_recovery() -> void:
	_actions |= FC.ACTION_RECOVERY


## Focus loss is a new authority boundary. A queued recovery cannot bridge it;
## the controller must see this generation disarmed before a fresh arm request.
func invalidate_for_focus() -> void:
	if radio.connected:
		radio.require_neutral(true, true)
	source_generation += 1
	_end_arm_continuity(true)
	_last_arm_level = false
	_arm_latch = false
	_arm_input_held = true
	_mode_input_held = true
	_actions &= ~FC.ACTION_RECOVERY
	_keyboard_sticks = {roll = 0.0, pitch = 0.0, yaw = 0.0}


## A pad restart: the virtual arm switch returns to OFF and the keyboard sticks to centre. The flight mode is kept.
func reset_for_restart() -> void:
	_arm_latch = false
	_turtle = false
	_turtle_used = false
	_turtle_engaged = false
	_end_arm_continuity(false)
	_continuity_lost = false
	_last_arm_level = false
	_actions = 0
	_keyboard_sticks = {roll = 0.0, pitch = 0.0, yaw = 0.0}


func flight_mode() -> int:
	# Turtle while disarmed (awaiting the arming edge) or once engaged; a request made while armed waits.
	return FC.FLIGHT_TURTLE if _turtle and (not _last_arm_level or _turtle_used) else _mode


## DR-19e: whether turtle mode (the crash flip) is requested.
func turtle_requested() -> bool:
	return _turtle


## The activity reports the controller's motor state after each accepted tick: an armed motor during a turtle arm cycle
## marks the request as engaged (its disarm consumes it).
func note_motor_state(armed: bool) -> void:
	_motor_reported = true
	_motor_armed = armed
	if armed and _turtle_used:
		_turtle_engaged = true


func _current_source_key() -> String:
	return "%s|%d|%s" % [source(), int(radio.device_id), str(radio.profile.get("profile_id", ""))]


## Every connection change or source switch: new generation, arm latch OFF, the new source's default mode. With a
## flight-mode switch bound the mode starts at Angle (the switch's OFF position) until the switch reports a valid
## position after its fresh-OFF arming.
func _source_changed() -> void:
	source_generation += 1
	_source_key = _current_source_key()
	_arm_latch = false
	_actions &= ~FC.ACTION_RECOVERY
	_mode = FC.FLIGHT_ANGLE if mode_from_switch() else default_mode(source())
	_keyboard_sticks = {roll = 0.0, pitch = 0.0, yaw = 0.0}
	_turtle = false
	_turtle_used = false
	_turtle_engaged = false
	_end_arm_continuity(_arm_continuity)
	_last_arm_level = false
	_refresh_shortcuts()


## Audit A03: the activity enters an ordinary hold (P, Esc, Start, the menu). An arm switch read ON by the last
## flying sample keeps its level across the hold only if its position can be read without the AUX channel's
## arming (a level button, an axis or a maintained switch, not an edge toggle). Returns whether it is kept.
func begin_hold() -> bool:
	_continuity_lost = false
	_arm_continuity = false
	var channel := arm_aux()
	if channel.is_empty() or not _last_arm_level:
		return false
	if _raw_switch_on(channel) != 1:
		_continuity_lost = true
		return false
	_arm_continuity = true
	_continuity_generation = source_generation
	_continuity_profile = radio.profile.duplicate(true)
	return true


## Whether resuming now keeps an armed arm level: the toggle latch, or an arm switch whose hold continuity holds.
func hold_keeps_arm() -> bool:
	if arm_aux().is_empty():
		return _arm_latch
	return _arm_continuity


## Whether an armed hold lost its arm switch's continuity (resuming disarms); the activity discloses it.
func hold_continuity_lost() -> bool:
	return _continuity_lost


func _end_arm_continuity(lost: bool) -> void:
	if _arm_continuity and lost:
		_continuity_lost = true
	_arm_continuity = false
	_continuity_profile = {}


## Physical position of a bound AUX switch from the live device, independent of the channel's arming: 1 ON, 0 OFF,
## -1 unknown (an edge toggle has no position; a switch reading no or two positions is transitional).
func _raw_switch_on(channel_name: String) -> int:
	if not radio.connected or not _aux_bound(channel_name):
		return -1
	var binding: Dictionary = radio.profile.aux[channel_name]
	var id := int(radio.device_id)
	match str(binding.get("type", "")):
		"button":
			if str(binding.get("mode", "")) != "level" or not read_button.is_valid():
				return -1
			return 1 if bool(read_button.call(id, int(binding.button))) else 0
		"axis":
			var axis := int(binding.axis)
			if axis < 0 or axis >= radio.axes.size() or not is_finite(radio.axes[axis]):
				return -1
			return 1 if SmokeAux.axis_amount(radio.axes[axis], binding) >= ARM_SWITCH_ON else 0
		"switch":
			if not read_button.is_valid():
				return -1
			var buttons: Array = SmokeAux.bound_buttons(binding)
			var active := -1
			for i in buttons.size():
				if bool(read_button.call(id, int(buttons[i]))):
					if active >= 0:
						return -1
					active = i
			if active < 0 or buttons.size() < 2:
				return -1
			var amount := float(active) / float(buttons.size() - 1)
			if bool(binding.get("invert", false)):
				amount = 1.0 - amount
			return 1 if amount >= ARM_SWITCH_ON else 0
	return -1


## The kept arm level is still that of the same source, mapping and switch position.
func _continuity_holds(channel_name: String, ready: bool) -> bool:
	return ready and source_generation == _continuity_generation and radio.profile == _continuity_profile \
		and _raw_switch_on(channel_name) == 1


## Sample once per physics tick. `integrate` false (a hold) still tracks readiness and button state, but toggles and
## one-shot actions wait for the next integrating sample. Returns {pilot, source, ready, error, throttle_policy, raw,
## source_generation}.
func sample(dt: float, integrate: bool) -> Dictionary:
	if radio.connected:
		radio.poll(read_axis, dt, read_button, integrate)
	if _current_source_key() != _source_key:
		_source_changed()
	var kind := source()
	# Polling can change the source. Only the built-in reader can omit axes without running a caller's callback.
	var keys: Dictionary
	if radio.connected and read_keys == _read_keyboard:
		keys = _read_keyboard(false)
	else:
		keys = read_keys.call()
	var error := ""
	var ready := true
	var roll := 0.0
	var pitch := 0.0
	var yaw := 0.0
	var throttle := 0.0
	var button_arm := false
	var button_mode := false
	var button_turtle := false
	if radio.connected:
		error = str(radio.input_error) if not str(radio.input_error).is_empty() else str(radio.profile_error)
		# RcInput owns fresh low-throttle evidence for raw radios and the verified
		# polling/neutral gate for gamepads. Never decode throttle ahead of it.
		ready = error.is_empty() and bool(radio.armed)
		if ready:
			var profile: Dictionary = radio.profile
			roll = _centered(profile, "roll")
			pitch = _centered(profile, "pitch")
			yaw = _centered(profile, "yaw")
			throttle = _throttle(profile)
		if radio.is_gamepad() and read_button.is_valid():
			button_arm = _arm_button >= 0 and bool(read_button.call(radio.device_id, _arm_button))
			button_mode = _mode_button >= 0 and bool(read_button.call(radio.device_id, _mode_button))
			button_turtle = _turtle_button >= 0 and bool(read_button.call(radio.device_id, _turtle_button))
	else:
		if integrate:
			var rate: float = Spec.CONTROLS.rate
			_keyboard_sticks.roll = Commands.rate_limit(_keyboard_sticks.roll, float(keys.get("roll", 0.0)), rate, dt)
			_keyboard_sticks.pitch = Commands.rate_limit(_keyboard_sticks.pitch, float(keys.get("pitch", 0.0)), rate, dt)
			_keyboard_sticks.yaw = Commands.rate_limit(_keyboard_sticks.yaw, float(keys.get("yaw", 0.0)), rate, dt)
		roll = _keyboard_sticks.roll
		pitch = _keyboard_sticks.pitch
		yaw = _keyboard_sticks.yaw
		throttle = clampf(float(keys.get("throttle", 0.0)), -1.0, 1.0)
	# Toggles: rising edges only, and only while flying (a hold cannot queue an arm request).
	var arm_pressed := bool(keys.get("arm", false)) or button_arm
	var mode_pressed := bool(keys.get("mode", false)) or button_mode
	var arm_channel := arm_aux()
	var mode_switch := mode_from_switch()
	# A changed arm source (a switch bound or unbound in Controls) starts from OFF: a latch toggled earlier must not
	# reappear as an arm level, and the controller then needs its own fresh OFF -> ON at low throttle.
	if arm_channel != _last_arm_channel:
		_last_arm_channel = arm_channel
		_arm_latch = false
	if integrate and arm_pressed and not _arm_input_held and arm_channel.is_empty():
		_arm_latch = not _arm_latch
	if integrate and mode_pressed and not _mode_input_held and not mode_switch:
		_mode = FC.FLIGHT_ANGLE if _mode == FC.FLIGHT_ACRO else FC.FLIGHT_ACRO
	var turtle_pressed := bool(keys.get("turtle", false)) or button_turtle
	if integrate and turtle_pressed and not _turtle_input_held:
		_turtle = not _turtle
	_turtle_input_held = turtle_pressed
	_arm_input_held = arm_pressed
	_mode_input_held = mode_pressed
	var arm_level := _arm_latch
	var arm_source := "toggle"
	if not arm_channel.is_empty():
		arm_source = "switch:" + arm_channel
		if ready and radio.auxiliary_request_valid(arm_channel):
			# The channel speaks again (fresh OFF evidence after the hold): its level is the command.
			arm_level = float(radio.auxiliary_amount(arm_channel)) >= ARM_SWITCH_ON
			_end_arm_continuity(false)
		elif _arm_continuity and _continuity_holds(arm_channel, ready):
			# Audit A03: an invalid request is "no command yet", not OFF; the switch held ON keeps the arm level.
			arm_level = true
			arm_source += ":held"
		else:
			_end_arm_continuity(true)
			arm_level = false
	if integrate:
		var was_armed_level := _last_arm_level
		_last_arm_level = arm_level and ready
		if _turtle and arm_level and ready and not was_armed_level:
			_turtle_used = true
			# A new arming edge while the motors are still armed (a source that was not ready for a moment) is the same
			# arm cycle: a flip already engaged stays engaged.
			_turtle_engaged = _turtle_engaged and _motor_armed
		elif _turtle_used and not arm_level:
			# The disarm ends the request only if the controller armed in turtle; a refused arm leaves it pending.
			_turtle = _motor_reported and not _turtle_engaged
			_turtle_used = false
			_turtle_engaged = false
		elif not _turtle:
			_turtle_used = false
			_turtle_engaged = false
	var mode_source := "toggle"
	if mode_switch:
		mode_source = "switch:" + MODE_AUX
		# A position consumer: without a valid request (before fresh-OFF evidence, after a pause, focus or menu
		# boundary, or while the source is not ready) the last accepted mode is kept, never snapped to Angle.
		if ready and radio.auxiliary_request_valid(MODE_AUX):
			_mode = FC.FLIGHT_ACRO if float(radio.auxiliary_amount(MODE_AUX)) >= MODE_SWITCH_ACRO else FC.FLIGHT_ANGLE
	var policy := throttle_policy()
	if not ready:
		roll = 0.0
		pitch = 0.0
		yaw = 0.0
		throttle = 0.0
	throttle = clampf(throttle, -1.0 if policy == "rate" else 0.0, 1.0)
	var actions := 0
	if integrate:
		actions = _actions
		_actions = 0
	var pilot := FC.neutral_input(source_generation, ready)
	pilot[FC.IN_ROLL] = clampf(roll, -1.0, 1.0)
	pilot[FC.IN_PITCH] = clampf(pitch, -1.0, 1.0)
	pilot[FC.IN_YAW] = clampf(yaw, -1.0, 1.0)
	pilot[FC.IN_THROTTLE] = throttle
	pilot[FC.IN_ARM] = 1.0 if arm_level else 0.0
	pilot[FC.IN_MODE] = float(flight_mode())
	pilot[FC.IN_ACTIONS] = float(actions)
	var raw := {roll = pilot[FC.IN_ROLL], pitch = pilot[FC.IN_PITCH], yaw = pilot[FC.IN_YAW], throttle = throttle,
		arm = arm_level, arm_source = arm_source, mode = "turtle" if flight_mode() == FC.FLIGHT_TURTLE else ("angle" if _mode == FC.FLIGHT_ANGLE else "acro"),
		mode_source = mode_source,
		arm_key = _arm_key_name, mode_key = _mode_key_name,
		arm_button = _arm_button, mode_button = _mode_button}
	return {pilot = pilot, source = kind, ready = ready, error = error, throttle_policy = policy, raw = raw,
		source_generation = source_generation}


## Calibrated, pre-expo centred channel: endpoints/centre/inversion, then (gamepad only) the rescaled deadzone.
## The profile's cubic expo is never applied. Pitch: the shared profiles already read stick back as positive.
func _centered(profile: Dictionary, channel_name: String) -> float:
	var channel: Variant = profile.get(channel_name, {})
	if typeof(channel) != TYPE_DICTIONARY:
		return 0.0
	return pre_expo(_raw_axis(channel), channel, str(profile.get("kind", "radio")))


## The pre-expo stage alone (test seam): normalize_axis, then a rescaled deadzone for a gamepad.
static func pre_expo(raw: float, channel: Dictionary, kind: String) -> float:
	var x := ControllerProfile.normalize_signed_axis(raw, channel)
	if kind != "gamepad":
		return x
	var dz := float(channel.get("deadzone", ControllerProfile.DEFAULT_DEADZONE))
	if not is_finite(dz) or dz < 0.0 or dz >= 1.0:
		return 0.0
	return signf(x) * maxf(0.0, absf(x) - dz) / (1.0 - dz)


## Absolute throttle in [0, 1], or the centred rate stick in [-1, 1] (deadzone only for a gamepad).
func _throttle(profile: Dictionary) -> float:
	var channel: Variant = profile.get("throttle", {})
	if typeof(channel) != TYPE_DICTIONARY:
		return 0.0
	var kind := str(profile.get("kind", "radio"))
	var mode := str(profile.get("throttle_mode", "stick_rate" if kind == "gamepad" else "radio_absolute"))
	var raw := _raw_axis(channel)
	if mode in ["trigger_absolute", "radio_absolute"]:
		return ControllerProfile.normalize_absolute(raw, channel)
	return pre_expo(raw, channel, kind)


## The last polled raw value of a channel's source axis (RcInput owns polling and fresh-evidence guards).
func _raw_axis(channel: Dictionary) -> float:
	var axis := int(channel.get("axis", -1))
	return float(radio.axes[axis]) if axis >= 0 and axis < radio.axes.size() else 0.0
