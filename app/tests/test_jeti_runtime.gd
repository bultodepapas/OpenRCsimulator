extends SceneTree

const Profile := preload("res://input/controller_profile.gd")
const Actions := preload("res://input/controller_actions.gd")
const RcInput := preload("res://input/rc_input.gd")
const Store := preload("res://input/controller_profile_store.gd")
const Calibration := preload("res://input/rc_calibration.gd")
const DEVICE := 41

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_presets_and_clean_draft()
	_direct_identity_safety()
	_conflicts_and_persistence()
	_absolute_requests_and_boundaries()
	print("JETI runtime: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func _check(label: String, condition: bool) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL ", label)


func _switch(buttons: Array, invert := false, label := "Sa") -> Dictionary:
	return {"type": "switch", "buttons": buttons, "invert": invert, "label": label}


func _presets_and_clean_draft() -> void:
	var profile := Profile.defaults("radio", "jeti_mode2")
	_check("JETI preset validates", not profile.is_empty() and Profile.validate(profile).ok)
	if profile.is_empty():
		return
	_check("known Mode 2 axes and direction", [profile.roll.axis, profile.pitch.axis, profile.throttle.axis, profile.yaw.axis] == [0, 1, 2, 3] and profile.pitch.invert)
	_check("radio absolute throttle and no copied identity", profile.kind == "radio" and profile.throttle_mode == "radio_absolute" and profile.association.is_empty())
	_check("preset instances own distinct identities", profile.profile_id != Profile.defaults("radio", "jeti_mode2").profile_id)
	_check("gamepads cannot use the radio preset", Profile.defaults("gamepad", "jeti_mode2").is_empty())
	var bindings := Actions.effective_bindings(profile)
	_check("distinct keyboard recovery validates", Actions.validate(bindings).ok and bindings.back.type == "key" and bindings.pause.type == "key" and bindings.back != bindings.pause)
	for button in range(32):
		var event := InputEventJoypadButton.new()
		event.device = DEVICE
		event.button_index = button
		event.pressed = true
		_check("unmapped radio button %d has no inherited action" % button, Actions.resolve_event(event, bindings, DEVICE, "both").is_empty())
	var old := Profile.defaults("joystick", "radio_custom")
	old.name = "Existing calibrated JETI"
	old.roll.min = -0.85
	old.pitch.invert = false
	old.aux = {"flaps": _switch([80, 81, 82])}
	var before := old.duplicate(true)
	var clean := Profile.clean_radio_actions(old)
	_check("clean is valid and preserves configured kind", not clean.is_empty() and clean.kind == "joystick" and Profile.validate(clean).ok)
	_check("clean preserves saved identity/calibration/AUX", clean.profile_id == old.profile_id and clean.name == old.name and clean.roll == old.roll and clean.pitch == old.pitch and clean.aux == old.aux)
	_check("clean does not mutate original draft", old == before)
	_check("clean does not reset gamepad bindings", Profile.clean_radio_actions(Profile.defaults()).is_empty())
	var invalid := old.duplicate(true)
	invalid.roll.axis = invalid.pitch.axis
	_check("clean cannot legitimize invalid flight mapping", Profile.clean_radio_actions(invalid).is_empty())


func _conflicts_and_persistence() -> void:
	var profile := Profile.defaults("radio", "jeti_mode2")
	profile.aux = {"flaps": _switch([80, 81, 82])}
	_check("three-position AUX profile validates", Profile.validate(profile).ok)
	for button in [80, 81, 82]:
		profile.actions.camera_cycle = {"type": "button", "button": button}
		_check("every detent source is reserved %d" % button, not Profile.validate(profile).ok)
	profile.actions.camera_cycle = {"type": "unbound"}
	profile.aux.gear = _switch([82, 83], false, "Sb")
	_check("partially overlapping groups rejected", not Profile.validate(profile).ok)
	profile.aux.gear = {"type": "button", "button": 81, "mode": "level"}
	_check("single button overlapping a group rejected", not Profile.validate(profile).ok)
	profile.aux.erase("gear")
	var wizard := Calibration.new(profile)
	var samples := PackedFloat64Array()
	samples.resize(RcInput.AXES)
	wizard.advance(samples)
	for axis in [2, 0, 1, 3]:
		for value in [1.0, -1.0, 0.0]:
			samples.fill(0.0)
			samples[axis] = value
			wizard.sample(samples)
		wizard.advance(samples)
	_check("radio recalibration preserves named switch groups", wizard.done() and wizard.profile.get("aux", {}).get("flaps", {}) == profile.aux.flaps)
	var invalid := profile.duplicate(true)
	invalid.aux.smoke = _switch([90, 90])
	_check("invalid extended smoke group rejected before optional sanitization", Profile.upgrade_legacy(invalid).is_empty())
	for aux_id in ["smoke", "gear", "flaps"]:
		for bad_buttons in [[true, 90], [90.0, 91], ["90", 91], [90, 90], [90, 128], [90]]:
			var malformed := Profile.defaults("radio", "jeti_mode2")
			malformed.aux = {aux_id: _switch(bad_buttons)}
			_check("malformed %s group fails profile activation: %s" % [aux_id, str(bad_buttons)], not Profile.validate(malformed).ok and Profile.upgrade_legacy(malformed).is_empty())
	var path := "user://jeti_runtime_%d.cfg" % OS.get_process_id()
	var store := Store.new(path, path + ".legacy")
	var saved: Dictionary = store.save_profile(profile)
	_check("group profile transaction saves", saved.get("ok", false))
	var loaded: Dictionary = store.load_all()
	_check("ConfigFile preserves typed detents and explicit clears", loaded.ok and loaded.profiles.size() == 1 and loaded.profiles[0] == saved.get("profile", {}))
	var rejected: Dictionary = store.save_profile(invalid)
	_check("invalid candidate cannot replace stored working profile", not rejected.get("ok", false) and store.load_all().profiles == loaded.profiles)
	for suffix in ["", ".tmp", ".rollback", ".legacy"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _direct_identity_safety() -> void:
	var info := {"name": "JETI DC/DS Mass Storage", "vendor_id": 1155, "product_id": 41084, "known": true}
	var radio := RcInput.new()
	radio.connect_device(DEVICE, info)
	_check("direct recognized JETI uses radio preset despite known-gamepad flag", radio.profile.get("preset", "") == "jeti_mode2" and not radio.is_gamepad())
	_poll(radio, {})
	_check("direct JETI still needs fresh throttle evidence", not radio.armed)
	var saved := Profile.defaults("joystick", "radio_custom")
	saved.roll.invert = true
	radio.connect_device(DEVICE, info, saved)
	_check("direct saved custom joystick is not silently migrated", radio.profile.kind == "joystick" and radio.profile.roll.invert and radio.profile.profile_id == saved.profile_id)
	var invalid := saved.duplicate(true)
	invalid.throttle.axis = 99
	radio.connect_device(DEVICE, info, invalid)
	_check("invalid explicit JETI profile cannot fall back to ready defaults", not radio.profile.get("configured", false) and not radio.armed)
	var missing := info.duplicate(true)
	missing.erase("product_id")
	radio.connect_device(DEVICE, missing)
	_check("incomplete JETI claim cannot inherit gamepad defaults", not radio.profile.get("configured", false) and not radio.is_gamepad())


func _absolute_requests_and_boundaries() -> void:
	var profile := Profile.defaults("radio", "jeti_mode2")
	profile.aux = {"flaps": _switch([80, 81, 82]), "smoke": _switch([90, 91], false, "Sb"), "gear": _switch([100, 101], true, "Sc")}
	var radio := RcInput.new()
	radio.connect_device(DEVICE, {"name": "JETI test", "known": false}, profile)
	var on := {82: true, 91: true, 100: true}
	_poll(radio, on)
	_check("held startup positions cannot activate AUX", _zero(radio))
	_check("polling alone cannot arm radio throttle", not radio.armed)
	radio.on_motion(DEVICE, 2, -1.0)
	_poll(radio, on)
	_check("fresh low throttle arms independently of maintained switches", radio.armed and _zero(radio))
	for pair in [[82, 80], [91, 90], [100, 101]]:
		radio.on_button(DEVICE, pair[0], false)
		radio.on_button(DEVICE, pair[1], true)
	var off := {80: true, 90: true, 101: true}
	_poll(radio, off)
	_check("deliberate OFF arms channels without activation", _zero(radio) and radio.smoke_is_armed())
	for pair in [[80, 81], [90, 91], [101, 100]]:
		# Reversed callback order cannot emit an intermediate detent request.
		radio.on_button(DEVICE, pair[1], true)
		radio.on_button(DEVICE, pair[0], false)
	_check("callbacks alone do not update absolute requests", _zero(radio))
	var flying := {81: true, 91: true, 100: true}
	_poll(radio, flying)
	_check("three independent absolute requests reach correct detents", radio.auxiliary_amount("flaps") == 0.5 and radio.smoke_amount() == 1.0 and radio.auxiliary_amount("gear") == 1.0)
	for i in range(5):
		_poll(radio, flying)
	_check("held samples never cycle or toggle", radio.auxiliary_amount("flaps") == 0.5 and radio.smoke_amount() == 1.0 and radio.auxiliary_amount("gear") == 1.0)
	radio.on_button(DEVICE + 1, 80, true)
	_poll(radio, flying)
	_check("foreign device cannot change position", radio.auxiliary_amount("flaps") == 0.5)
	_poll(radio, {80: true, 81: true, 91: true, 100: true})
	_check("contradictory stable group fails safe", radio.auxiliary_amount("flaps") == 0.0)
	_poll(radio, flying)
	_check("corrected snapshot alone cannot revive invalidated flap request", radio.auxiliary_amount("flaps") == 0.0)
	_poll(radio, {91: true, 100: true})
	_poll(radio, flying)
	_check("zero-active snapshot also requires fresh switch arming", radio.auxiliary_amount("flaps") == 0.0)
	radio.set_auxiliary_enabled(false)
	_check("menu boundary drops all requests", _zero(radio))
	radio.on_button(DEVICE, 80, true)
	_poll(radio, flying)
	_check("resume retains no stale OFF event or request", _zero(radio))
	radio.require_neutral(true, true)
	_poll(radio, flying, 0.4)
	_check("focus return with raised throttle stays unarmed", not radio.armed and radio.sticks().throttle == 0.0)
	radio.disconnect_device()
	_check("disconnect drops outputs", _zero(radio))
	radio.connect_device(DEVICE, {"name": "JETI test", "known": false}, profile)
	_poll(radio, flying)
	_check("reconnect cannot restore old requests", _zero(radio) and not radio.armed)


func _poll(radio: RcInput, held: Dictionary, throttle := -1.0) -> void:
	radio.poll(func(_id: int, axis: int) -> float: return throttle if axis == 2 else 0.0, 1.0 / 240.0,
		func(_id: int, button: int) -> bool: return bool(held.get(button, false)))


func _zero(radio: RcInput) -> bool:
	return radio.smoke_amount() == 0.0 and radio.auxiliary_amount("gear") == 0.0 and radio.auxiliary_amount("flaps") == 0.0
