extends SceneTree

const Actions := preload("res://input/controller_actions.gd")

var checks := 0
var failures := 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	_test_definitions_and_defaults()
	_test_unbound_and_boundaries()
	_test_resolution()
	_test_profile_axis_rules()
	_test_aux_compatibility()
	_test_aux_to_aux_collisions()
	_test_radio_aux_pause_compatibility()
	_test_aircraft_defaults()
	_test_restart_and_flap_defaults()
	if failures == 0:
		print("PASS extended controller actions: %d checks" % checks)
	else:
		printerr("FAIL extended controller actions: %d/%d checks failed" % [failures, checks])
	quit(1 if failures > 0 else 0)


func _test_definitions_and_defaults() -> void:
	var defaults := Actions.default_bindings()
	var added := [
		"smoke_toggle", "flaps_up", "flaps_down", "flaps_cycle", "gear_toggle",
		"camera_previous", "camera_pilot", "camera_chase", "camera_orbit",
		"camera_zoom_in", "camera_zoom_out", "camera_auto_zoom", "lights_cycle",
	]
	for action_id in added:
		var definition := Actions.action_definition(action_id)
		_check("optional action %s is defined" % action_id, not definition.is_empty() and definition.id == action_id)
		_check("optional action %s is unbound by default" % action_id, defaults.get(action_id) == {"type": "unbound"})
	_check("legacy camera cycle remains bound", defaults.camera_cycle == {"type": "button", "button": JOY_BUTTON_Y})
	_check("recovery bindings remain bound by default", Actions.validate(defaults).ok)
	var definition := Actions.action_definition("smoke_toggle")
	definition.label = "mutated copy"
	_check("action metadata is returned as a copy", Actions.action_definition("smoke_toggle").label != "mutated copy")
	_check("optional defaults are explicit and serializable", defaults.smoke_toggle.keys() == ["type"] and defaults.smoke_toggle.type == "unbound")
	var name_keyed_profile := _profile()
	name_keyed_profile.actions = {StringName("camera_cycle"): {StringName("type"): "button", StringName("button"): JOY_BUTTON_X}}
	var normalized := Actions.effective_bindings(name_keyed_profile)
	var has_string_action_key := false
	for action_key in normalized.keys():
		if str(action_key) == "camera_cycle" and typeof(action_key) == TYPE_STRING:
			has_string_action_key = true
	_check("effective map normalizes StringName action IDs", has_string_action_key)
	_check("effective map preserves StringName binding override", normalized.camera_cycle.button == JOY_BUTTON_X)
	normalized.camera_cycle.button = JOY_BUTTON_A
	_check("effective bindings do not alias saved nested dictionaries", name_keyed_profile.actions[StringName("camera_cycle")][StringName("button")] == JOY_BUTTON_X)


func _test_unbound_and_boundaries() -> void:
	var bindings := {"back": {"type": "button", "button": 1}, "pause": {"type": "button", "button": 6}, "smoke_toggle": {"type": "unbound"}}
	_check("optional unbound action validates", Actions.validate(bindings).ok)
	bindings.smoke_toggle = {"type": "unbound", "button": 1}
	_check("unbound binding rejects unexpected fields", not Actions.validate(bindings).ok)
	bindings.smoke_toggle = {"type": "unbound"}
	bindings.back = {"type": "unbound"}
	_check("recovery action cannot be unbound", not Actions.validate(bindings).ok)
	bindings.back = {"type": "button", "button": JOY_BUTTON_MAX - 1}
	bindings.pause = {"type": "button", "button": JOY_BUTTON_MAX - 2}
	_check("highest valid button index is accepted", Actions.validate(bindings).ok)
	bindings.back.button = JOY_BUTTON_MAX
	_check("button max is exclusive", not Actions.validate(bindings).ok)
	bindings.back = {"type": "button", "button": 1}
	bindings.pause = {"type": "button", "button": 6}
	bindings.camera_zoom_in = {"type": "axis", "axis": JOY_AXIS_MAX - 1, "sign": 1, "threshold": 0.65}
	_check("highest valid action axis index is accepted", Actions.validate(bindings).ok)
	bindings.camera_zoom_in.axis = JOY_AXIS_MAX
	_check("axis max is exclusive", not Actions.validate(bindings).ok)


func _test_resolution() -> void:
	var bound := Actions.default_bindings()
	var event := InputEventJoypadButton.new()
	event.device = 4
	event.button_index = JOY_BUTTON_Y
	event.pressed = true
	_check("unbound optional action never resolves", not Actions.resolve_event(event, bound, 4, "flight").has("smoke_toggle"))
	bound.smoke_toggle = {"type": "button", "button": JOY_BUTTON_Y}
	var resolved := Actions.resolve_event(event, bound, 4, "flight")
	_check("new optional action resolves in flight context", resolved.has("smoke_toggle"))
	_check("optional action is excluded in menu context", not Actions.resolve_event(event, bound, 4, "menu").has("smoke_toggle"))
	_check("input event from another device remains isolated", Actions.resolve_event(event, bound, 5, "flight").is_empty())
	_check("explicit unbind suppresses only that action", Actions.matches_binding({"type": "unbound"}, event, 4) == false)
	var axis_binding := {"type": "axis", "axis": 4, "sign": 1, "threshold": 0.65}
	var axis_actions := {"back": {"type": "button", "button": 1}, "pause": {"type": "button", "button": 6}, "camera_zoom_in": axis_binding}
	var active := PackedStringArray()
	var rising_edges := 0
	for axis_value in [0.66, 0.64, 0.66]:
		var axis_event := _axis_event(axis_value)
		var next_active := Actions.resolve_event(axis_event, axis_actions, 4, "flight", active)
		if next_active.has("camera_zoom_in") and not active.has("camera_zoom_in"):
			rising_edges += 1
		active = next_active
	_check("trigger jitter preserves one latched rising edge", rising_edges == 1 and active.has("camera_zoom_in"))
	active = Actions.resolve_event(_axis_event(0.4), axis_actions, 4, "flight", active)
	_check("axis action releases below hysteresis threshold", active.is_empty())
	active = Actions.resolve_event(_axis_event(0.7), axis_actions, 4, "flight", active)
	if active.has("camera_zoom_in"):
		rising_edges += 1
	_check("axis action rearms after release", active.has("camera_zoom_in") and rising_edges == 2)
	_check("non-finite motion value cannot resolve", Actions.resolve_event(_axis_event(NAN), axis_actions, 4, "flight", active).is_empty())


func _test_profile_axis_rules() -> void:
	var profile := _profile()
	var report := Actions.validate_profile_bindings(profile)
	_check("default profile actions validate", report.ok)
	_check("effective bindings are returned", report.bindings is Dictionary and report.bindings.has("camera_cycle"))
	profile.actions = {"camera_zoom_in": {"type": "axis", "axis": 2, "sign": 1, "threshold": 0.65}}
	report = Actions.validate_profile_bindings(profile)
	_check("action axis cannot reuse a primary flight axis", not report.ok and _contains(report.errors, "primary flight axis 2"))
	profile.actions.camera_zoom_in.axis = 9
	report = Actions.validate_profile_bindings(profile)
	_check("unreserved upper action axis remains available", report.ok)
	profile.actions.camera_zoom_in.axis = 4
	profile.aux = {"smoke": {"type": "axis", "axis": 4, "off": -1.0, "on": 1.0, "invert": false}}
	report = Actions.validate_profile_bindings(profile)
	_check("aux axis reserves both directions", not report.ok and _contains(report.errors, "conflicts with aux.smoke"))
	profile.aux.smoke.axis = 3
	report = Actions.validate_profile_bindings(profile)
	_check("AUX cannot claim a primary flight axis", not report.ok and _contains(report.errors, "aux.smoke is invalid"))


func _test_aux_compatibility() -> void:
	var profile := _profile()
	profile.aux = {"smoke": {"type": "button", "button": JOY_BUTTON_Y, "mode": "level"}}
	var before := profile.duplicate(true)
	var effective := Actions.effective_bindings(profile)
	_check("inherited flight default that overlaps AUX is silenced", effective.camera_cycle == {"type": "unbound"})
	_check("legacy unrelated defaults remain", effective.overlay_preset == {"type": "button", "button": JOY_BUTTON_X})
	_check("effective binding resolution does not mutate saved profile", profile == before)
	_check("legacy aux button with inherited flight collision validates", Actions.validate_profile_bindings(profile).ok)
	profile.actions = {"camera_cycle": {"type": "button", "button": JOY_BUTTON_Y}}
	_check("explicit flight binding is never silently suppressed", Actions.effective_bindings(profile).camera_cycle.button == JOY_BUTTON_Y)
	_check("explicit flight/AUX collision is rejected", not Actions.validate_profile_bindings(profile).ok)

	profile = _profile()
	profile.aux = {"smoke": {"type": "button", "button": JOY_BUTTON_X, "mode": "level"}}
	profile.actions = {"pause": {"type": "button", "button": JOY_BUTTON_X}}
	_check("recovery/both-context collision remains visible", Actions.effective_bindings(profile).pause.button == JOY_BUTTON_X)
	_check("recovery/AUX collision is rejected", not Actions.validate_profile_bindings(profile).ok)

	profile = _profile()
	profile.aux = {"smoke": {"type": "button", "button": JOY_BUTTON_X, "mode": "level"}}
	profile.actions = {"smoke_toggle": {"type": "button", "button": JOY_BUTTON_A}}
	_check("explicit smoke action conflicts even on another input", not Actions.validate_profile_bindings(profile).ok)
	profile.actions.smoke_toggle = {"type": "unbound"}
	_check("explicitly unbound smoke action leaves AUX assignment valid", Actions.validate_profile_bindings(profile).ok)

	profile = _profile()
	profile.aux = {"flaps": {"type": "button", "button": JOY_BUTTON_X, "mode": "toggle_edge"}}
	profile.actions = {"flaps_up": {"type": "button", "button": JOY_BUTTON_A}}
	_check("flaps action conflicts with AUX flaps channel", not Actions.validate_profile_bindings(profile).ok)
	profile.actions = {"flaps_up": {"type": "unbound"}}
	_check("unbound flaps actions leave AUX assignment valid", Actions.validate_profile_bindings(profile).ok)

	profile = _profile()
	profile.aux = {"gear": {"type": "button", "button": JOY_BUTTON_X, "mode": "toggle_edge"}}
	profile.actions = {"gear_toggle": {"type": "button", "button": JOY_BUTTON_A}}
	_check("gear action conflicts with AUX gear channel", not Actions.validate_profile_bindings(profile).ok)
	profile.actions = {"gear_toggle": {"type": "unbound"}}
	_check("unbound gear action leaves AUX assignment valid", Actions.validate_profile_bindings(profile).ok)

	profile = _profile()
	profile.aux = {"lights": {"type": "button", "button": JOY_BUTTON_X, "mode": "toggle_edge"}}
	_check("unrelated future AUX metadata does not affect current lights action", Actions.validate_profile_bindings(profile).ok)


func _test_aux_to_aux_collisions() -> void:
	var profile := _profile()
	profile.aux = {
		"smoke": {"type": "axis", "axis": 4, "off": -1.0, "on": 1.0, "invert": false},
		"flaps": {"type": "axis", "axis": 4, "off": 0.0, "on": 1.0, "invert": false},
	}
	var report := Actions.validate_profile_bindings(profile)
	_check("AUX channels cannot share an axis across calibration ranges", not report.ok and _contains(report.errors, "aux.smoke and aux.flaps"))

	profile.aux = {
		"smoke": {"type": "button", "button": JOY_BUTTON_MAX - 1, "mode": "level"},
		"gear": {"type": "button", "button": JOY_BUTTON_MAX - 1, "mode": "toggle_edge"},
	}
	report = Actions.validate_profile_bindings(profile)
	_check("AUX channels cannot share a button across activation modes", not report.ok and _contains(report.errors, "aux.smoke and aux.gear"))

	profile.aux = {
		"smoke": {"type": "axis", "axis": 4, "off": -1.0, "on": 1.0, "invert": false},
		"flaps": {"type": "axis", "axis": 5, "off": -1.0, "on": 1.0, "invert": false},
		"gear": {"type": "button", "button": JOY_BUTTON_MAX - 1, "mode": "level"},
	}
	report = Actions.validate_profile_bindings(profile)
	_check("distinct AUX controls remain valid", report.ok)


func _test_radio_aux_pause_compatibility() -> void:
	var profile := _profile()
	profile["schema_version"] = 2
	profile["kind"] = "radio"
	profile.aux = {"smoke": {"type": "button", "button": JOY_BUTTON_START, "mode": "toggle_edge"}}
	var report := Actions.validate_profile_bindings(profile)
	_check("V2 radio AUX keeps button 6 and moves inherited pause to Escape", report.ok \
		and report.bindings.pause.type == "key" and report.bindings.pause.physical_keycode == KEY_ESCAPE)

	profile = _profile()
	profile.kind = "radio" # Legacy profile shape has no schema_version.
	profile.aux = {"smoke": {"type": "button", "button": JOY_BUTTON_START, "mode": "toggle_edge"}}
	report = Actions.validate_profile_bindings(profile)
	_check("legacy radio AUX on button 6 remains valid", report.ok \
		and report.bindings.pause.type == "key" and report.bindings.pause.physical_keycode == KEY_ESCAPE)

	profile.kind = "gamepad"
	report = Actions.validate_profile_bindings(profile)
	_check("gamepad AUX still reports an inherited pause collision", not report.ok \
		and report.bindings.pause.button == JOY_BUTTON_START)

	profile.kind = "radio"
	profile.actions = {"pause": {"type": "button", "button": JOY_BUTTON_START}}
	report = Actions.validate_profile_bindings(profile)
	_check("explicit radio pause is never silently moved off its AUX collision", not report.ok \
		and report.bindings.pause.type == "button" and report.bindings.pause.button == JOY_BUTTON_START)


func _test_aircraft_defaults() -> void:
	var profile := _profile()
	profile.kind = "gamepad"
	var original := profile.duplicate(true)
	var jet := Actions.effective_bindings(profile, {gear = true, smoke = false, flaps = false})
	_check("jet automatically maps B/Circle to retractable gear", jet.gear_toggle == {type = "button", button = JOY_BUTTON_B})
	_check("unavailable equipment actions remain unbound", jet.smoke_toggle.type == "unbound" and jet.flaps_cycle.type == "unbound")
	var stik := Actions.effective_bindings(profile, {gear = false, smoke = true})
	_check("Stik automatically maps RB/R1 to smoke only", stik.smoke_toggle == {type = "button", button = JOY_BUTTON_RIGHT_SHOULDER} and stik.gear_toggle.type == "unbound")
	_check("aircraft defaults never mutate a saved profile", profile == original)
	_check("automatic assignments pass existing validation", Actions.validate_profile_bindings(profile).ok)
	var event := InputEventJoypadButton.new()
	event.device = 4
	event.button_index = JOY_BUTTON_B
	event.pressed = true
	_check("B means gear only in flight", Actions.resolve_event(event, jet, 4, "flight") == PackedStringArray(["gear_toggle"]))
	_check("B retains Back in menus", Actions.resolve_event(event, jet, 4, "menu") == PackedStringArray(["back"]))
	_check("another device cannot operate automatic gear", Actions.resolve_event(event, jet, 5, "flight").is_empty())
	profile.actions.gear_toggle = {type = "unbound"}
	_check("explicit Clear survives automatic defaults", Actions.effective_bindings(profile).gear_toggle.type == "unbound")
	profile.actions.gear_toggle = {type = "button", button = 127}
	_check("explicit remap survives aircraft changes", Actions.effective_bindings(profile, {}).gear_toggle.button == 127)
	profile.actions = {camera_cycle = {type = "button", button = JOY_BUTTON_B}, pause = {type = "button", button = JOY_BUTTON_RIGHT_SHOULDER}}
	var occupied := Actions.effective_bindings(profile)
	_check("automatic actions never steal occupied flight or recovery buttons", occupied.gear_toggle.type == "unbound" and occupied.smoke_toggle.type == "unbound" and Actions.validate_profile_bindings(profile).ok)
	profile.actions = {}
	profile.aux = {gear = {type = "axis", axis = 9, off = -1.0, on = 1.0, invert = false}}
	_check("gear AUX owns the function even on another source", Actions.effective_bindings(profile).gear_toggle.type == "unbound" and Actions.validate_profile_bindings(profile).ok)
	profile.aux = {flaps = {type = "button", button = JOY_BUTTON_RIGHT_SHOULDER, mode = "toggle_edge"}}
	_check("another AUX owns the physical smoke candidate", Actions.effective_bindings(profile).smoke_toggle.type == "unbound" and Actions.validate_profile_bindings(profile).ok)
	profile.aux = {}
	for kind in ["radio", "joystick"]:
		profile.kind = kind
		var raw := Actions.effective_bindings(profile)
		_check("%s receives no invented standard button mapping" % kind, raw.gear_toggle.type == "unbound" and raw.smoke_toggle.type == "unbound")
		profile.actions.gear_toggle = {type = "button", button = 25}
		_check("%s retains explicit equipment mappings" % kind, Actions.effective_bindings(profile).gear_toggle.button == 25)
		profile.actions = {}


func _test_restart_and_flap_defaults() -> void:
	var profile := _profile()
	profile.kind = "gamepad"
	var bindings := Actions.effective_bindings(profile, {flaps = true})
	_check("installed flaps receive A/Cross", bindings.flaps_cycle == {type = "button", button = JOY_BUTTON_A})
	_check("restart receives View/Share independently of equipment", bindings.restart_flight == {type = "button", button = JOY_BUTTON_BACK})
	_check("no equipment still allows restart", Actions.effective_bindings(profile, {}).restart_flight == bindings.restart_flight)
	var event := InputEventJoypadButton.new()
	event.device = 4
	event.button_index = JOY_BUTTON_A
	event.pressed = true
	_check("A only cycles flaps in flight", Actions.resolve_event(event, bindings, 4, "flight") == PackedStringArray(["flaps_cycle"]))
	_check("A still accepts in menus", Actions.resolve_event(event, bindings, 4, "menu") == PackedStringArray(["accept"]))
	profile.actions = {flaps_cycle = {type = "unbound"}, restart_flight = {type = "unbound"}}
	bindings = Actions.effective_bindings(profile)
	_check("saved Clear wins for both new defaults", bindings.flaps_cycle.type == "unbound" and bindings.restart_flight.type == "unbound")
	profile.actions = {camera_cycle = {type = "button", button = JOY_BUTTON_BACK}, lights_cycle = {type = "button", button = JOY_BUTTON_A}}
	bindings = Actions.effective_bindings(profile)
	_check("new defaults never steal a saved binding", bindings.restart_flight.type == "unbound" and bindings.flaps_cycle.type == "unbound" and Actions.validate_profile_bindings(profile).ok)
	profile.actions = {}
	profile.aux = {flaps = {type = "axis", axis = 9, off = -1.0, on = 1.0, invert = false}, smoke = {type = "button", button = JOY_BUTTON_BACK, mode = "level"}}
	bindings = Actions.effective_bindings(profile)
	_check("AUX owns flap semantics and restart button source", bindings.flaps_cycle.type == "unbound" and bindings.restart_flight.type == "unbound" and Actions.validate_profile_bindings(profile).ok)
	profile.aux = {}
	profile.kind = "radio"
	profile.actions = {restart_flight = {type = "axis", axis = 9, sign = 1, threshold = 0.65}}
	_check("radio can bind restart to an unused channel", Actions.validate_profile_bindings(profile).ok)
	profile.actions.restart_flight.axis = 2
	_check("restart cannot reuse a primary flight channel", not Actions.validate_profile_bindings(profile).ok)


func _profile() -> Dictionary:
	return {
		"roll": {"axis": 0},
		"pitch": {"axis": 1},
		"yaw": {"axis": 2},
		"throttle": {"axis": 3},
		"actions": {},
		"aux": {},
	}


func _axis_event(value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = 4
	event.axis = 4
	event.axis_value = value
	return event


func _contains(values: Array, phrase: String) -> bool:
	for value in values:
		if str(value).contains(phrase):
			return true
	return false
