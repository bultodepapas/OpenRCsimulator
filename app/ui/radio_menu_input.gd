extends RefCounted
## Converts only a verified selected radio's real events into native GUI actions.
## The owner dispatches every returned event and resets at context/connection boundaries.

const RadioMenu := preload("res://input/radio_menu.gd")
const FIRST_REPEAT := 0.4
const NEXT_REPEAT := 0.12
const MAX_DELTA := 1.0
const MAX_PENDING := 64
const COMMAND_ACTIONS := {"accept": "ui_accept", "back": "ui_cancel", "pause": "openrc_radio_pause"}

var _device := -1
var _generation := 0
var _profile: Dictionary = {}
var _axes := PackedFloat64Array()
var _seen_axes := {}
var _buttons := {}
var _physical_on := {"accept": false, "back": false, "pause": false}
var _observed_off := {"accept": false, "back": false, "pause": false}
var _armed := {"accept": false, "back": false, "pause": false}
var _logical_on := {"accept": false, "back": false, "pause": false}
var _sent := {}
var _pending: Array[InputEventAction] = []
var _release_backlog: Array[InputEventAction] = []
var _enabled := false
var _nav_ready := false
var _directions := {"horizontal": 0, "vertical": 0}
var _direction_armed := {"horizontal": false, "vertical": false}
var _repeat := {"horizontal": FIRST_REPEAT, "vertical": FIRST_REPEAT}


func _init() -> void:
	_axes.resize(RadioMenu.AXES)


## Connection generation is part of ownership; the caller verifies it remains current.
## Dispatch reset_context(true) before discarding or replacing an active router.
func configure(id: int, generation: int, profile: Dictionary) -> bool:
	_release_backlog.append_array(reset_context(true))
	_device = -1
	_generation = 0
	_profile.clear()
	if id < 0 or generation <= 0 or not RadioMenu.is_verified(profile): return false
	_device = id
	_generation = generation
	_profile = profile.duplicate(true)
	return true


## Record genuine events even during blocked dispatch, so releases are not lost.
func observe(event: InputEvent) -> void:
	if _device < 0 or event.device != _device or _profile.is_empty(): return
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if motion.axis < 0 or motion.axis >= RadioMenu.AXES: return
		if not is_finite(motion.axis_value) or absf(motion.axis_value) > 1.0:
			_release_backlog.append_array(reset_context(true))
			return
		_axes[motion.axis] = motion.axis_value
		_seen_axes[motion.axis] = true
		for name: String in COMMAND_ACTIONS:
			var binding: Dictionary = _profile.actions[name]
			if binding.type != "axis" or binding.axis != motion.axis: continue
			if not RadioMenu.axis_action_active(motion.axis_value, binding, true):
				_observe_command(name, false)
			elif RadioMenu.axis_action_active(motion.axis_value, binding, false):
				_observe_command(name, true)
			else:
				# Between release and activation thresholds the current position is
				# not fresh OFF evidence, even if its last state was released.
				_observed_off[name] = false
	elif event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		if button.button_index < 0 or button.button_index >= JOY_BUTTON_MAX: return
		_buttons[button.button_index] = button.pressed
		for name: String in COMMAND_ACTIONS:
			var binding: Dictionary = _profile.actions[name]
			if binding.type == "button" and binding.button == button.button_index:
				_observe_command(name, button.pressed)


func _observe_command(name: String, on: bool) -> void:
	var previous := bool(_physical_on[name])
	_physical_on[name] = on
	_observed_off[name] = not on
	if not on:
		_armed[name] = true
		if bool(_logical_on[name]):
			if not _queue(str(COMMAND_ACTIONS[name]), false): return
			_logical_on[name] = false
		return
	if previous: return
	if bool(_armed[name]) and _enabled and _nav_ready:
		if not _queue(str(COMMAND_ACTIONS[name]), true): return
		_logical_on[name] = true
	_armed[name] = false


## The owner may seed only immediately after a completed, same-generation
## verification challenge. These are current hardware samples, never input injection.
func seed_verified_samples(axes: PackedFloat64Array, buttons: Dictionary) -> bool:
	if _profile.is_empty() or _enabled or not _sent.is_empty() or not _pending.is_empty() or axes.size() != RadioMenu.AXES:
		return false
	for value: float in axes:
		if not is_finite(value) or absf(value) > 1.0: return false
	var roll: Dictionary = _profile.roll
	var pitch: Dictionary = _profile.pitch
	if absf(RadioMenu.normalized(axes[roll.axis], roll)) > RadioMenu.CENTER_THRESHOLD \
			or absf(RadioMenu.normalized(axes[pitch.axis], pitch)) > RadioMenu.CENTER_THRESHOLD:
		return false
	for name: String in COMMAND_ACTIONS:
		var binding: Dictionary = _profile.actions[name]
		if binding.type == "button":
			if not buttons.has(binding.button) or typeof(buttons[binding.button]) != TYPE_BOOL or buttons[binding.button]:
				return false
		elif RadioMenu.axis_action_active(axes[binding.axis], binding, true):
			return false
	_axes = axes.duplicate()
	_seen_axes.clear()
	_seen_axes[roll.axis] = true
	_seen_axes[pitch.axis] = true
	_buttons = buttons.duplicate(true)
	_physical_on = {"accept": false, "back": false, "pause": false}
	_observed_off = {"accept": true, "back": true, "pause": true}
	_armed = {"accept": true, "back": true, "pause": true}
	return true


## True means actual events for both selected axes established a current center.
func sticks_centered() -> bool:
	if _profile.is_empty(): return false
	var roll: Dictionary = _profile.roll
	var pitch: Dictionary = _profile.pitch
	if not _seen_axes.has(roll.axis) or not _seen_axes.has(pitch.axis): return false
	return absf(RadioMenu.normalized(_axes[roll.axis], roll)) <= RadioMenu.CENTER_THRESHOLD \
		and absf(RadioMenu.normalized(_axes[pitch.axis], pitch)) <= RadioMenu.CENTER_THRESHOLD


func ready_for_commands() -> bool:
	return _nav_ready and bool(_observed_off.accept) and bool(_observed_off.back) and bool(_observed_off.pause)


func advance(delta: float, enabled: bool = true) -> Array[InputEventAction]:
	var output: Array[InputEventAction] = []
	output.append_array(_release_backlog)
	_release_backlog.clear()
	if not is_finite(delta) or delta < 0.0 or delta > MAX_DELTA:
		output.append_array(reset_context(true))
		return output
	if _device < 0 or _profile.is_empty(): return output
	if not enabled:
		if _enabled: output.append_array(reset_context(false))
		return output
	_enabled = true
	if not _nav_ready:
		if sticks_centered():
			_nav_ready = true
			_direction_armed.horizontal = true
			_direction_armed.vertical = true
		else:
			_pending.clear()
			return output
	for event: InputEventAction in _pending:
		output.append(event)
	_pending.clear()
	var x := RadioMenu.normalized(_axes[int(_profile.roll.axis)], _profile.roll)
	var y := RadioMenu.normalized(_axes[int(_profile.pitch.axis)], _profile.pitch)
	_move_axis("horizontal", x, "ui_left", "ui_right", delta, output)
	_move_axis("vertical", y, "ui_up", "ui_down", delta, output)
	return output


func _move_axis(name: String, value: float, negative_action: String, positive_action: String,
		delta: float, output: Array[InputEventAction]) -> void:
	var previous: int = _directions[name]
	if previous != 0:
		if absf(value) <= RadioMenu.NAV_RELEASE or signf(value) != float(previous):
			_emit(output, negative_action if previous < 0 else positive_action, false)
			_directions[name] = 0
			_direction_armed[name] = absf(value) <= RadioMenu.NAV_RELEASE
			_repeat[name] = FIRST_REPEAT
			return
		_repeat[name] = float(_repeat[name]) - delta
		if float(_repeat[name]) <= 0.0:
			var action := negative_action if previous < 0 else positive_action
			_emit(output, action, false)
			_emit(output, action, true)
			_repeat[name] = NEXT_REPEAT # never emit more than one repeat per frame
		return
	if absf(value) <= RadioMenu.NAV_RELEASE: _direction_armed[name] = true
	if not bool(_direction_armed[name]) or absf(value) < RadioMenu.NAV_THRESHOLD: return
	var direction := -1 if value < 0.0 else 1
	_directions[name] = direction
	_direction_armed[name] = false
	_repeat[name] = FIRST_REPEAT
	_emit(output, negative_action if direction < 0 else positive_action, true)


## Releases already-dispatched virtual actions. Cached axis observations survive
## ordinary context changes; focus/connection loss requests invalidation.
func reset_context(invalidate_observations: bool = false) -> Array[InputEventAction]:
	var output: Array[InputEventAction] = []
	output.append_array(_release_backlog)
	_release_backlog.clear()
	for action: String in _sent:
		output.append(_event(action, false))
	_sent.clear()
	_pending.clear()
	_enabled = false
	_nav_ready = false
	_directions = {"horizontal": 0, "vertical": 0}
	_direction_armed = {"horizontal": false, "vertical": false}
	_repeat = {"horizontal": FIRST_REPEAT, "vertical": FIRST_REPEAT}
	_armed = {"accept": bool(_observed_off.accept), "back": bool(_observed_off.back), "pause": bool(_observed_off.pause)}
	_logical_on = {"accept": false, "back": false, "pause": false}
	if invalidate_observations:
		_seen_axes.clear()
		_axes.fill(0.0)
		_buttons.clear()
		_physical_on = {"accept": false, "back": false, "pause": false}
		_observed_off = {"accept": false, "back": false, "pause": false}
		_armed = {"accept": false, "back": false, "pause": false}
	for event: InputEventAction in output: event.set_meta("openrc_radio_reset", true)
	return output


func _queue(action: String, pressed: bool) -> bool:
	if _pending.size() >= MAX_PENDING:
		_release_backlog.append_array(reset_context(true))
		return false
	_pending.append(_event(action, pressed))
	return true


func _emit(output: Array[InputEventAction], action: String, pressed: bool) -> void:
	output.append(_event(action, pressed))


## Call immediately after actually delivering each event. An earlier event can
## change the screen and cause the owner to discard the rest of the batch.
func mark_dispatched(event: InputEventAction) -> void:
	if event.device != _device or str(event.action) not in ["ui_accept", "ui_cancel", "ui_left", "ui_right", "ui_up", "ui_down", "openrc_radio_pause"]:
		return
	if event.pressed: _sent[str(event.action)] = true
	else: _sent.erase(str(event.action))


func _event(action: String, pressed: bool) -> InputEventAction:
	var event := InputEventAction.new()
	event.device = _device
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	return event
