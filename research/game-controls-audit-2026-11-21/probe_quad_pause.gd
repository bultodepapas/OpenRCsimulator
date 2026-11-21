# Diagnostic expectations describe the adverse baseline; these are not fix regressions.
# Reuses the production activity and synthetic-source fixture from the existing authority test.
extends "res://tests/test_mr_controller_authority.gd"

const Actions := preload("res://input/controller_actions.gd")


func _run() -> void:
	_radio_pause_diagnostic()
	print("QUAD_PAUSE_AUDIT_COMPLETE %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures else 0)


func _radio_pause_diagnostic() -> void:
	_reset_input()
	axes = {0: 0.0, 1: 0.0, 2: -1.0, 3: 0.0}
	var registry := FakeRegistry.new()
	registry.devices[8] = {id = 8, connected = true, name = "Synthetic radio", guid = "pause-radio", known = false, kind = "radio"}
	registry.flight = 8
	var profile := Profile.defaults("radio", "radio_custom")
	profile.actions["pause"] = {"type": "button", "button": 20}
	var report: Dictionary = Actions.validate_profile_bindings(profile, Actions.MULTIROTOR_CAPABILITIES)
	_check("precondition: radio Pause button is valid and applicable to quad", Profile.validate(profile).ok and report.ok
		and Actions.action_applies("pause", Actions.MULTIROTOR_CAPABILITIES))
	var learned := profile.duplicate(true)
	learned.actions["pause"] = {"type": "axis", "axis": 4, "off": -1.0, "on": 1.0, "invert": false, "sign": 1, "threshold": 0.65}
	_check("precondition: learned radio Pause axis is also admitted", Profile.validate(learned).ok
		and Actions.validate_profile_bindings(learned, Actions.MULTIROTOR_CAPABILITIES).ok)
	var activity := _activity(registry, func(_id: int) -> Dictionary: return profile.duplicate(true), Callable())
	root.add_child(activity)
	activity.set_physics_process(false)
	activity.set_process(false)
	activity.input.radio.on_motion(8, 2, -1.0)
	activity.handle_action("resume")
	_check("precondition: the actual radio quad session is running", not activity.session.paused)
	for pressed: bool in [false, true]:
		var event := InputEventJoypadButton.new()
		event.device = 8
		event.button_index = 20
		event.pressed = pressed
		activity._input(event)
		activity._unhandled_input(event)
	var ignored: bool = not activity.session.paused and not activity.hud.menu_visible
	_check("witness: saved radio Pause OFF-ON edge is ignored", ignored)
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	activity._unhandled_input(escape)
	var fallback: bool = activity.session.paused and activity.hud.menu_visible
	_check("positive control: Escape pauses the same activity", fallback)
	print("AUDIT_OBSERVATIONS ", JSON.stringify({id = "GCA-01", button_profile_valid = report.ok,
		radio_pause_ignored = ignored, escape_pauses = fallback, evidence = "Production quad activity/session; synthetic radio and direct event callbacks"}))
	_free(activity)
