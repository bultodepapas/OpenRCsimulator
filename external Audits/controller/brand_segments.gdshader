# UI-15-UX-07: connects the Setup assistant (setup_assistant.gd) to the Controls screen (controller_setup.gd).
# Every call goes through the screen's own draft paths (kind, preset, invert, capture, calibration, Save), so the
# assistant inherits their validation, capture ownership and transactional Save. Nothing here stores anything.
extends "res://ui/controls/setup_assistant_host.gd"

const ControllerActions := preload("res://input/controller_actions.gd")
const ControllerProfile := preload("res://input/controller_profile.gd")
const ControllerPrompts := preload("res://ui/controller_prompts.gd")
const CalibrationView := preload("res://ui/controls/calibration_view.gd")

const FLIGHT_CHANNELS: Array[String] = ["roll", "pitch", "yaw", "throttle"]
## Buttons sampled for the Test step's "held now" row (standard gamepad layout and the first radio switches).
const PREVIEW_BUTTONS := 24

var setup: Node
var assistant: Object
var _error := ""
## Reverse in the assistant means "opposite to the correct setup", not the profile's raw invert flag: gamepad
## presets already invert some axes (Mode 2 throttle: stick up reads negative) and calibration measures a radio's
## direction. The baseline is the preset default (gamepads) or the draft once kind/preset/calibration settle.
var _baseline_invert: Dictionary = {}


func _init(owner_setup: Node) -> void:
	setup = owner_setup


func device_info() -> Dictionary:
	var device_id: int = setup.selected_flight_device_id()
	var device: Dictionary = setup._device_for_id(device_id) if device_id >= 0 else {}
	var draft: Dictionary = setup.current_profile()
	var info := device.duplicate(true)
	info["display_name"] = str(device.get("display_name", device.get("name", "")))
	info["kind"] = str(device.get("kind", draft.get("kind", "joystick")))
	if bool(draft.get("configured", true)) and not str(draft.get("kind", "")).is_empty():
		info["profile_kind"] = str(draft.get("kind", ""))
	info["preset"] = str(draft.get("preset", ""))
	var presentation: Variant = draft.get("presentation", {})
	var requested_family := str(presentation.get("glyph_family", "auto")) if presentation is Dictionary else "auto"
	info["family"] = ControllerPrompts.resolve_family(requested_family, device)
	info["stick_mode"] = 1 if str(draft.get("preset", "")) == "mode1" else CalibrationView.presentation_stick_mode(setup)
	return info


func vehicle_capabilities() -> Dictionary:
	return setup.action_capabilities.duplicate()


func set_profile_kind(kind: String) -> bool:
	_error = ""
	if str(setup.current_profile().get("kind", "")) == kind:
		return true
	var picker: OptionButton = setup.profile_kind_picker
	if not picker.visible:
		# A recognised device keeps its kind (controller contract): only unknown devices and joysticks choose.
		var device: Dictionary = setup._device_for_id(setup.selected_flight_device_id())
		_error = tr("This controller is recognised as a gamepad, so its type cannot be changed.") 			if str(device.get("kind", "")) == "gamepad" else tr("This controller type could not be applied.")
		return false
	for index in picker.item_count:
		var choice_id := picker.get_item_id(index)
		for choice: Dictionary in setup.get_script().get_script_constant_map().get("PROFILE_KIND_CHOICES", []):
			if int(choice.id) == choice_id and str(choice.kind) == kind:
				picker.select(index)
				setup._on_profile_kind_selected(index)
				if str(setup.current_profile().get("kind", "")) == kind:
					reset_reverse_baseline()
					return true
				_error = tr("This controller type could not be applied.")
				return false
	_error = tr("This controller type could not be applied.")
	return false


func apply_preset(preset_id: String) -> bool:
	_error = ""
	var kind := str(setup.current_profile().get("kind", ""))
	if kind != "gamepad":
		# Radios and joysticks: Mode 1/2 only names the stick layout; calibration detects the channels.
		return preset_id in ["mode1", "mode2"]
	if preset_id not in ["mode1", "mode2", "trigger_absolute"]:
		_error = tr("This stick layout could not be applied.")
		return false
	if str(setup.current_profile().get("preset", "")) != preset_id:
		setup._apply_preset(preset_id)
	if str(setup.current_profile().get("preset", "")) != preset_id:
		_error = tr("This stick layout could not be applied.")
		return false
	reset_reverse_baseline()
	return true


func request_calibration() -> bool:
	_error = ""
	var device_id: int = setup.selected_flight_device_id()
	if setup._is_capture_active() or device_id < 0 or not bool(setup._device_for_id(device_id).get("connected", false)):
		_error = tr("Calibration could not start.")
		return false
	if str(setup._draft_profile.get("kind", "")) != "radio":
		# The calibration wizard measures radios only; a joystick's axes are assigned with Detect in Flight axes.
		_error = tr("Joysticks are set up with Detect in Flight axes; skip this step.")
		return false
	if setup.calibration_saves_first and setup.radio_mapping_verified(setup._draft_profile):
		# During a flight a verified radio recalibrates from Pause (it saves first and leaves Controls).
		_error = tr("During a flight, recalibrate this radio from Pause → Controls.")
		return false
	setup.calibration_requested.emit()
	return true


func preview() -> Dictionary:
	var device_id: int = setup.selected_flight_device_id()
	var draft: Dictionary = setup._draft_profile # read only: no per-poll deep copy
	# A fresh array each poll: the assistant compares the previous sample with the new one.
	var buttons: Array[int] = []
	var result := {"buttons": buttons, "inverted": {}}
	var kind := str(draft.get("kind", "gamepad"))
	var throttle_mode := str(draft.get("throttle_mode", "stick_rate" if kind == "gamepad" else "radio_absolute"))
	result["throttle_centered"] = throttle_mode == "stick_rate"
	# A radio's direction comes from its calibration; reversing it here would void that calibration.
	result["reverse_available"] = kind != "radio"
	for channel_name in FLIGHT_CHANNELS:
		var channel: Variant = draft.get(channel_name, {})
		var value := 0.0
		if channel is Dictionary and device_id >= 0:
			value = ControllerProfile.channel_value(setup._read_axis_preview(device_id, int(channel.get("axis", -1))), channel_name, draft)
		result[channel_name] = value
		result.inverted[channel_name] = _invert_flag(draft, channel_name) != _baseline(draft, channel_name)
	if device_id >= 0:
		for button in PREVIEW_BUTTONS:
			if setup._read_button_preview(device_id, button):
				buttons.append(button)
	return result


func set_channel_inverted(channel: String, inverted: bool) -> void:
	if channel not in FLIGHT_CHANNELS:
		return
	var draft: Dictionary = setup._draft_profile
	if str(draft.get("kind", "")) == "radio":
		return # see reverse_available: the next preview restores the switch
	setup._on_axis_invert(_baseline(draft, channel) != inverted, channel)
	setup._update_axis_controls()
	setup.draft_changed.emit()


func binding_for(id: String) -> Dictionary:
	var draft: Dictionary = setup.current_profile()
	if id.begins_with("aux:"):
		var aux: Variant = draft.get("aux", {})
		var binding: Variant = aux.get(id.trim_prefix("aux:"), {}) if aux is Dictionary else {}
		return binding.duplicate(true) if binding is Dictionary and not binding.is_empty() else {"type": "unbound"}
	var bindings: Dictionary = ControllerActions.effective_bindings(draft, setup.action_capabilities)
	var action_binding: Variant = bindings.get(id, {"type": "unbound"})
	return action_binding.duplicate(true) if action_binding is Dictionary else {"type": "unbound"}


func capture(id: String) -> bool:
	_error = ""
	if not setup.has_method("start_capture_for"):
		_error = tr("Assignment could not start.")
		return false
	# The screen becomes active first so its capture can take focus and show its overlay and conflict question.
	setup._assistant_capture_started()
	if not setup.start_capture_for(id):
		setup._assistant_capture_aborted()
		_error = tr("Assignment could not start.")
		return false
	return true


func save() -> bool:
	_error = ""
	if setup._save_profile(false):
		return true
	_error = str(setup.status_label.text) if is_instance_valid(setup.status_label) else ""
	if _error.is_empty():
		_error = tr("Controller settings could not be saved.")
	return false


func last_error() -> String:
	return _error


## Forget the Reverse baseline after the kind, preset or calibration changed.
func reset_reverse_baseline() -> void:
	_baseline_invert.clear()


func _invert_flag(draft: Dictionary, channel_name: String) -> bool:
	var channel: Variant = draft.get(channel_name, {})
	return bool(channel.get("invert", false)) if channel is Dictionary else false


func _baseline(draft: Dictionary, channel_name: String) -> bool:
	if _baseline_invert.is_empty():
		var reference := draft
		if str(draft.get("kind", "")) == "gamepad":
			var defaults: Dictionary = ControllerProfile.defaults("gamepad", str(draft.get("preset", "mode2")))
			if not defaults.is_empty():
				reference = defaults
		for name in FLIGHT_CHANNELS:
			_baseline_invert[name] = _invert_flag(reference, name)
	return bool(_baseline_invert.get(channel_name, false))
