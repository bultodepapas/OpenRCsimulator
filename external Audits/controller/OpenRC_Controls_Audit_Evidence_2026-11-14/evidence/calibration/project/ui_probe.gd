extends SceneTree

const Profile := preload("res://input/controller_profile.gd")
const Assistant := preload("res://ui/controls/setup_assistant.gd")
const Bridge := preload("res://ui/controls/setup_assistant_bridge.gd")
const Wizard := preload("res://ui/radio_calibration_setup.gd")

class Registry extends RefCounted:
	signal devices_changed
	func connection_generation(id: int) -> int: return 1 if id == 4 else 0
	func device_for_id(id: int) -> Dictionary: return {"connected": id == 4, "name": "synthetic radio", "kind": "radio"}

class Setup extends Node:
	signal calibration_requested
	var _draft_profile: Dictionary = Profile.defaults("radio", "radio_custom")
	var action_capabilities := {}
	var calibration_saves_first := false
	func current_profile() -> Dictionary: return _draft_profile.duplicate(true)
	func selected_flight_device_id() -> int: return 4
	func _device_for_id(id: int) -> Dictionary: return {"connected": id == 4, "name": "synthetic radio", "kind": "radio"}
	func _is_capture_active() -> bool: return false
	func radio_mapping_verified(_profile: Dictionary) -> bool: return false

var checks := 0
var failures := 0
var opened_wizard: CanvasLayer
func check(label: String, condition: bool, detail: Variant = "") -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL ", label, " ", detail)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var registry := Registry.new()
	var setup := Setup.new()
	root.add_child(setup)
	var bridge := Bridge.new(setup)
	var assistant := Assistant.new()
	assistant.configure(bridge)
	root.add_child(assistant)
	assistant.open()
	setup.calibration_requested.connect(func() -> void:
		opened_wizard = Wizard.new()
		if opened_wizard.configure(registry, 4, setup.current_profile()):
			root.add_child(opened_wizard))
	assistant.go_next()
	check("radio reaches mode page", assistant.current_step() == "mode")
	assistant._on_preset_chosen("mode1")
	assistant.go_next()
	check("radio Mode 1 reaches calibration page", assistant.current_step() == "calibrate" and assistant.chosen_preset() == "mode1")
	assistant._start_calibration()
	check("wizard opens", opened_wizard != null and assistant.is_busy())
	check("calibration still shows Mode 2", opened_wizard.view.stick_mode == 2)
	print("MODE_MISMATCH assistant=", assistant.chosen_preset(), " wizard_mode=", opened_wizard.view.stick_mode,
		" left=", opened_wizard.view.gimbal_functions(opened_wizard.view.stick_mode)[0],
		" right=", opened_wizard.view.gimbal_functions(opened_wizard.view.stick_mode)[1])
	var joystick_profile := Profile.defaults("joystick", "radio_custom")
	setup._draft_profile = joystick_profile
	check("joystick calibration always refused", not bridge.request_calibration() and "Detect" in bridge.last_error(), bridge.last_error())
	print("JOYSTICK_CALIBRATION refusal=", bridge.last_error())
	opened_wizard.queue_free()
	assistant.queue_free()
	setup.queue_free()
	await process_frame
	print("Calibration UI audit: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
