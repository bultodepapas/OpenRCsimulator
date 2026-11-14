extends SceneTree

const Menu := preload("res://input/radio_menu.gd")
const Router := preload("res://ui/radio_menu_input.gd")
const Profile := preload("res://input/controller_profile.gd")
const DEVICE := 17
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func fixture() -> Dictionary:
	var profile := Profile.defaults("radio", "radio_custom")
	profile.roll.min = -0.8
	profile.roll.center = 0.05
	profile.roll.max = 0.65
	profile.pitch.min = -0.6
	profile.pitch.center = 0.1
	profile.pitch.max = 0.9
	profile.pitch.invert = false
	profile.actions["accept"] = {"type": "button", "button": 10}
	profile.actions["back"] = {"type": "axis", "axis": 7, "sign": -1, "threshold": 0.65, "off": 0.8, "on": 0.2, "invert": true}
	profile.actions["pause"] = {"type": "button", "button": 11}
	return profile


func axes_at_rest() -> PackedFloat64Array:
	var axes := PackedFloat64Array()
	axes.resize(Menu.AXES)
	axes[0] = 0.05
	axes[1] = 0.1
	axes[2] = -1.0
	axes[7] = 0.8
	return axes


func axis(index: int, value: float, device := DEVICE) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = index as JoyAxis
	event.axis_value = value
	return event


func button(index: int, pressed: bool, device := DEVICE) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = index as JoyButton
	event.pressed = pressed
	return event


func event_is(events: Array[InputEventAction], name: String, pressed: bool) -> bool:
	return events.size() == 1 and str(events[0].action) == name and events[0].pressed == pressed and events[0].device == DEVICE


func _advance(router: RefCounted, delta: float, enabled: bool = true) -> Array[InputEventAction]:
	var events: Array[InputEventAction] = router.advance(delta, enabled)
	for event: InputEventAction in events:
		router.mark_dispatched(event)
	return events


func _stable_sample(challenge: RefCounted, axes: PackedFloat64Array, buttons: Dictionary) -> Dictionary:
	challenge.sample(axes, buttons, 0.2)
	return challenge.sample(axes, buttons, 0.2)


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	InputMap.load_from_project_settings()
	_validation_test()
	_verification_test()
	_router_test()
	_pause_safety_test()
	_mode_one_test()
	_seed_and_context_test()
	await _gui_test()
	print("Radio menu: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _validation_test() -> void:
	var original := fixture()
	var before := original.duplicate(true)
	check("ordinary profiles remain valid and unverified", Menu.validate(original).ok and not Menu.is_verified(original))
	var disabled := original.duplicate(true)
	disabled["ui_navigation"] = {"enabled": false}
	check("explicitly disabled navigation is harmless", Menu.validate(disabled).ok and not Menu.is_verified(disabled))
	var verified := Menu.verified_profile(original)
	check("physical radio actions can be verified", not verified.is_empty() and Menu.is_verified(verified), str(Menu.validate(verified)))
	check("verification does not mutate source", original == before and not original.has("ui_navigation"))
	check("metadata specifies roll and pitch", verified.ui_navigation.horizontal == "roll" and verified.ui_navigation.vertical == "pitch")
	var shape := verified.duplicate(true)
	shape.roll["expo"] = 0.8
	check("unrelated presentation shaping does not invalidate calibration evidence", Menu.is_verified(shape))
	for name: String in Menu.CHANNELS:
		for field: String in Menu.CHANNEL_FIELDS:
			var changed := verified.duplicate(true)
			match field:
				"axis": changed[name][field] = 9
				"min": changed[name][field] = float(changed[name][field]) + 0.01
				"center": changed[name][field] = float(changed[name][field]) + 0.01
				"max": changed[name][field] = float(changed[name][field]) - 0.01
				"invert": changed[name][field] = not bool(changed[name][field])
				"range_kind": changed[name][field] = "absolute" if name != "throttle" else "centered"
			check("changed %s.%s invalidates evidence" % [name, field], not Menu.is_verified(changed))
	for field: String in ["kind", "throttle_mode"]:
		var changed := verified.duplicate(true)
		changed[field] = "gamepad" if field == "kind" else "stick_rate"
		check("changed %s invalidates evidence" % field, not Menu.is_verified(changed))
	for action: String in Menu.COMMANDS:
		var changed := verified.duplicate(true)
		changed.actions[action] = {"type": "button", "button": 31}
		check("changed %s invalidates evidence" % action, not Menu.is_verified(changed))
	for flight_name: String in Menu.CHANNELS:
		var conflict := original.duplicate(true)
		conflict.actions["accept"] = {"type": "axis", "axis": conflict[flight_name].axis, "sign": 1, "threshold": 0.65}
		check("menu action cannot reuse %s primary axis" % flight_name, Menu.verified_profile(conflict).is_empty())
	var conflict := original.duplicate(true)
	conflict.actions["pause"] = {"type": "button", "button": 10}
	check("two commands cannot use one button", Menu.verified_profile(conflict).is_empty())
	conflict = original.duplicate(true)
	conflict.actions["pause"] = {"type": "axis", "axis": 7, "sign": 1, "threshold": 0.65}
	check("two commands cannot share an axis even with opposite signs", Menu.verified_profile(conflict).is_empty())
	for bad: Variant in [null, 7, "radio", {"type": "key", "keycode": KEY_ENTER}, {"type": "unbound"}]:
		conflict = original.duplicate(true)
		conflict.actions["accept"] = bad
		check("invalid or nonphysical menu source is rejected: %s" % str(bad), Menu.verified_profile(conflict).is_empty())
	for bad: Variant in [1, null, "wrong", NAN]:
		var malformed := verified.duplicate(true)
		malformed.roll["range_kind"] = bad
		check("malformed range kind fails closed: %s" % str(bad), not Menu.is_verified(malformed))
	for bad: Variant in [1, null, "true"]:
		var malformed := verified.duplicate(true)
		malformed.ui_navigation["enabled"] = bad
		check("malformed enable flag fails closed: %s" % str(bad), not Menu.is_verified(malformed) and not Menu.validate(malformed).ok)
	for bad: Variant in [null, 99, "identity", [], {"serial_number": 123}, {"guid": false}, {"vendor_id": []}]:
		var malformed := verified.duplicate(true)
		malformed["association"] = bad
		var validation: Dictionary = Profile.validate(malformed)
		var menu_validation: Dictionary = Menu.validate(malformed)
		check("malformed association with enabled navigation fails closed: %s" % str(bad), \
			not validation.ok and not menu_validation.ok)
	check("calibrated offset center reads zero", is_zero_approx(Menu.normalized(0.05, original.roll)))
	check("calibrated asymmetric endpoints normalize per side", is_equal_approx(Menu.normalized(-0.8, original.roll), -1.0) and is_equal_approx(Menu.normalized(0.65, original.roll), 1.0))
	var invert: Dictionary = original.roll.duplicate(true)
	invert.invert = true
	check("calibrated inversion applies after normalization", is_equal_approx(Menu.normalized(-0.8, invert), 1.0))


func _verification_test() -> void:
	var challenge = Menu.verification(fixture())
	var axes := axes_at_rest()
	var buttons := {10: true, 11: false}
	var result: Dictionary = challenge.sample(axes, buttons, 0.5)
	check("held Accept at connection cannot establish center", result.step == "center" and not result.done)
	buttons[10] = false
	result = challenge.sample(axes, buttons, 0.2)
	check("one isolated center sample cannot establish stable center", result.step == "center")
	result = challenge.sample(axes, buttons, 0.2)
	check("released controls and stable center begin directional challenge", result.step == "right" and "RIGHT" in challenge.instruction())
	check("challenge matches its original mapping and actions", challenge.matches(fixture()))
	var modified := fixture()
	modified.roll.invert = true
	check("challenge rejects a changed mapping", not challenge.matches(modified))
	modified = fixture()
	modified.actions["accept"] = {"type": "button", "button": 12}
	check("challenge rejects a changed command", not challenge.matches(modified))
	for point: Array in [[0, 0.65, "center_after_right"], [0, 0.05, "left"], [0, -0.8, "center_after_left"], [0, 0.05, "down"],
			[1, 0.9, "center_after_down"], [1, 0.1, "up"], [1, -0.6, "center_after_up"], [1, 0.1, "accept_on"]]:
		axes[point[0]] = point[1]
		result = _stable_sample(challenge, axes, buttons)
		check("challenge captures " + str(point[2]), result.step == point[2], str(result))
	buttons[10] = true
	result = challenge.sample(axes, buttons, 0.2)
	check("held Accept at its step cannot count without fresh OFF", result.step == "accept_on")
	buttons[10] = false
	challenge.sample(axes, buttons, 0.2)
	buttons[10] = true
	result = _stable_sample(challenge, axes, buttons)
	check("fresh Accept press advances", result.step == "accept_off")
	buttons[10] = false
	result = _stable_sample(challenge, axes, buttons)
	check("Accept release advances", result.step == "back_on")
	challenge.sample(axes, buttons, 0.2)
	axes[7] = 0.2
	result = _stable_sample(challenge, axes, buttons)
	check("reversed offset Back ON advances", result.step == "back_off")
	axes[7] = 0.8
	result = _stable_sample(challenge, axes, buttons)
	check("reversed offset Back OFF advances", result.step == "pause_on")
	challenge.sample(axes, buttons, 0.2)
	buttons[11] = true
	result = _stable_sample(challenge, axes, buttons)
	check("Pause ON must precede release", result.step == "pause_off")
	buttons[11] = false
	buttons[10] = true
	result = _stable_sample(challenge, axes, buttons)
	check("verification cannot finish while Accept is held again", not result.done and result.step == "pause_off")
	buttons[10] = false
	axes[7] = 0.2
	result = _stable_sample(challenge, axes, buttons)
	check("verification cannot finish while Back is held again", not result.done and result.step == "pause_off")
	axes[7] = 0.8
	axes[0] = 0.65
	result = _stable_sample(challenge, axes, buttons)
	check("verification cannot finish while either menu stick is displaced", not result.done and result.step == "pause_off")
	axes[0] = 0.05
	result = _stable_sample(challenge, axes, buttons)
	check("completed challenge requires every physical action OFF", result.done and result.step == "done")
	var invalid = Menu.verification(fixture())
	var bad := axes_at_rest()
	bad[0] = NAN
	check("nonfinite sample fails challenge", not invalid.sample(bad, buttons, 0.1).error.is_empty())
	check("failed challenge cannot recover without a new verification", not invalid.sample(axes_at_rest(), buttons, 0.2).error.is_empty())
	var missing = Menu.verification(fixture())
	check("unobserved button zero does not prove release", missing.sample(axes_at_rest(), {}, 0.2).step == "center")


func _configured_router() -> RefCounted:
	var router := Router.new()
	check("verified selected radio configures router", router.configure(DEVICE, 1, Menu.verified_profile(fixture())))
	return router


func _prime(router: RefCounted) -> void:
	router.observe(axis(0, 0.05))
	router.observe(axis(1, 0.1))
	router.observe(button(10, false))
	router.observe(axis(7, 0.8))
	router.observe(button(11, false))
	_advance(router, 0.01)


func _router_test() -> void:
	var router := _configured_router()
	check("no stale zeros prove center", not router.sticks_centered())
	router.observe(axis(0, 0.05, 3))
	router.observe(axis(1, 0.1, 3))
	check("foreign device observations cannot prove center", not router.sticks_centered())
	router.observe(axis(0, 0.05))
	check("one real centered axis is insufficient", not router.sticks_centered())
	router.observe(axis(1, 0.1))
	check("both observed centered axes establish center", router.sticks_centered() and _advance(router, 0.01).is_empty())
	router.observe(button(10, true))
	check("held-at-entry Accept cannot fire without actual OFF", _advance(router, 0.01).is_empty())
	router.observe(button(10, false))
	router.observe(button(10, true))
	check("OFF then ON produces one Accept press", event_is(_advance(router, 0.01), "ui_accept", true))
	router.observe(button(10, true))
	check("held Accept never repeats", _advance(router, 0.8).is_empty())
	router.observe(button(10, false))
	check("Accept release is balanced", event_is(_advance(router, 0.01), "ui_accept", false))
	router.observe(button(10, true))
	router.observe(button(10, false))
	var quick: Array[InputEventAction] = _advance(router, 0.01)
	check("quick press and release between frames are preserved", quick.size() == 2 and quick[0].pressed and not quick[1].pressed)
	router.observe(button(10, true))
	router.observe(button(10, false))
	var batch: Array[InputEventAction] = router.advance(0.01)
	var before_ack: Array[InputEventAction] = router.reset_context(false)
	check("undelivered batch cannot leave a virtual action held", batch.size() == 2 and before_ack.is_empty())
	if batch.size() == 2:
		router.mark_dispatched(batch[0]) # first push changed context; second event is discarded
		check("acknowledged first press is released after context change", event_is(router.reset_context(false), "ui_accept", false))
	_prime(router)
	router.observe(axis(7, 0.8))
	router.observe(axis(7, 0.2))
	check("reversed offset axis creates Back press", event_is(_advance(router, 0.01), "ui_cancel", true))
	router.observe(axis(7, 0.45))
	check("axis hysteresis retains Back while held", _advance(router, 0.01).is_empty())
	router.observe(axis(7, 0.8))
	check("reversed offset axis releases Back", event_is(_advance(router, 0.01), "ui_cancel", false))
	router.observe(button(11, false))
	router.observe(button(11, true))
	check("Pause uses its own semantic action rather than native Back", event_is(_advance(router, 0.01), "openrc_radio_pause", true))
	router.observe(button(11, true))
	check("held Pause does not repeat", _advance(router, 0.5).is_empty())
	router.observe(button(11, false))
	check("Pause release is balanced", event_is(_advance(router, 0.01), "openrc_radio_pause", false))
	router.observe(axis(0, 0.65))
	check("roll right emits right", event_is(_advance(router, 0.01), "ui_right", true))
	check("repeat waits for first delay", _advance(router, 0.39).is_empty())
	var repeat: Array[InputEventAction] = _advance(router, 0.02)
	check("repeat emits one balanced right pulse", repeat.size() == 2 and not repeat[0].pressed and repeat[1].pressed and str(repeat[0].action) == "ui_right")
	repeat = _advance(router, 0.8)
	check("a long frame is bounded to one repeat pulse", repeat.size() == 2)
	router.observe(axis(0, -0.8))
	check("abrupt reversal first releases right", event_is(_advance(router, 0.01), "ui_right", false))
	check("opposite direction requires center", _advance(router, 0.1).is_empty())
	router.observe(axis(0, 0.05))
	_advance(router, 0.01)
	router.observe(axis(0, -0.8))
	check("center then left emits left", event_is(_advance(router, 0.01), "ui_left", true))
	check("context boundary releases active direction", event_is(router.reset_context(false), "ui_left", false))
	router.observe(button(10, false))
	_advance(router, 0.01)
	router.observe(button(10, true))
	check("uncentered stick prevents Accept after context change", _advance(router, 0.01).is_empty())
	router.observe(button(10, false))
	router.observe(axis(0, 0.05))
	_advance(router, 0.01)
	router.observe(button(10, true))
	check("center and fresh OFF/ON recover Accept", event_is(_advance(router, 0.01), "ui_accept", true))
	router.observe(axis(0, NAN))
	check("nonfinite event releases active native action", event_is(_advance(router, 0.01), "ui_accept", false))
	check("nonfinite event invalidates observed center", not router.sticks_centered())
	var bad := fixture()
	check("unverified profile cannot configure router", not router.configure(DEVICE, 1, bad))
	check("negative handle cannot configure router", not router.configure(-1, 1, Menu.verified_profile(fixture())))
	check("missing connection generation cannot configure router", not router.configure(DEVICE, 0, Menu.verified_profile(fixture())))


func _pause_safety_test() -> void:
	var router := _configured_router()
	router.observe(axis(0, 0.05))
	router.observe(axis(1, 0.1))
	router.observe(button(10, false))
	router.observe(axis(7, 0.8))
	router.observe(button(11, true)) # switch already held at connection
	check("held Pause at connection never dispatches", _advance(router, 0.01).is_empty() and not router.ready_for_commands())
	router.observe(button(11, true))
	check("held Pause remains blocked after center", _advance(router, 0.5).is_empty())
	router.observe(button(11, false))
	check("fresh Pause OFF establishes command readiness", _advance(router, 0.01).is_empty() and router.ready_for_commands())
	router.observe(button(11, true))
	check("fresh Pause ON emits exactly its own action", event_is(_advance(router, 0.01), "openrc_radio_pause", true))
	check("context change releases dispatched Pause", event_is(router.reset_context(false), "openrc_radio_pause", false))
	router.observe(button(11, true))
	check("Pause held across context cannot trigger again", _advance(router, 0.01).is_empty() and not router.ready_for_commands())
	router.observe(button(11, false))
	check("fresh physical Pause OFF rearms after context", _advance(router, 0.01).is_empty() and router.ready_for_commands())
	router.observe(button(11, true))
	check("new Pause ON after context emits one action", event_is(_advance(router, 0.01), "openrc_radio_pause", true))
	check("disabling dispatch releases held Pause", event_is(_advance(router, 0.01, false), "openrc_radio_pause", false))
	router.observe(button(11, true))
	check("held Pause through disabled dispatch stays consumed", _advance(router, 0.01).is_empty())
	router.observe(button(11, false))
	_advance(router, 0.01)
	var clean := true
	for i in 100:
		router.observe(button(11, true))
		var pressed: Array[InputEventAction] = _advance(router, 0.01)
		router.observe(button(11, true))
		var held: Array[InputEventAction] = _advance(router, 0.2)
		router.observe(button(11, false))
		var released: Array[InputEventAction] = _advance(router, 0.01)
		clean = clean and event_is(pressed, "openrc_radio_pause", true) and held.is_empty() and event_is(released, "openrc_radio_pause", false)
	check("100 held Pause sequences each activate exactly once", clean)
	var axis_profile := fixture()
	axis_profile.actions["pause"] = {"type": "axis", "axis": 8, "sign": -1, "threshold": 0.65, "off": 0.8, "on": 0.2, "invert": true}
	var axis_router := Router.new()
	check("learned-axis Pause configures", axis_router.configure(DEVICE, 3, Menu.verified_profile(axis_profile)))
	var axes := axes_at_rest()
	axes[8] = 0.2
	check("held learned-axis Pause cannot seed readiness", not axis_router.seed_verified_samples(axes, {10: false}))
	axes[8] = 0.8
	check("observed OFF for all three commands can seed readiness", axis_router.seed_verified_samples(axes, {10: false}))
	_advance(axis_router, 0.01)
	axis_router.observe(axis(8, 0.2))
	check("reversed learned-axis Pause emits its semantic action", event_is(_advance(axis_router, 0.01), "openrc_radio_pause", true))
	axis_router.observe(axis(8, 0.47))
	check("learned Pause uses release hysteresis", _advance(axis_router, 0.01).is_empty())
	axis_router.observe(axis(8, 0.8))
	check("learned Pause releases from its calibrated OFF", event_is(_advance(axis_router, 0.01), "openrc_radio_pause", false))


func _mode_one_test() -> void:
	var mode1 := fixture()
	mode1.roll.axis = 5
	mode1.roll.invert = true
	mode1.pitch.axis = 3
	mode1.pitch.invert = true
	mode1.yaw.axis = 1
	var router := Router.new()
	check("Mode 1 distinct remapped controls configure", router.configure(DEVICE, 7, Menu.verified_profile(mode1)))
	router.observe(axis(5, 0.05))
	router.observe(axis(3, 0.1))
	router.observe(button(10, false))
	_advance(router, 0.01)
	check("Mode 1 center uses remapped axis evidence", router.sticks_centered())
	router.observe(axis(5, -0.8))
	check("Mode 1 inverted roll still moves right", event_is(_advance(router, 0.01), "ui_right", true))
	router.observe(axis(5, 0.05))
	_advance(router, 0.01)
	router.observe(axis(3, 0.9))
	check("Mode 1 inverted pitch still moves up", event_is(_advance(router, 0.01), "ui_up", true))


func _seed_and_context_test() -> void:
	var router := _configured_router()
	var axes := axes_at_rest()
	check("seed requires current physical button OFF samples", not router.seed_verified_samples(axes, {}))
	check("seed rejects an unobserved Pause", not router.seed_verified_samples(axes, {10: false}))
	check("seed rejects a held Accept", not router.seed_verified_samples(axes, {10: true, 11: false}))
	check("seed rejects a held Pause", not router.seed_verified_samples(axes, {10: false, 11: true}))
	var bad := axes.duplicate()
	bad[7] = 0.2
	check("seed rejects a held learned Back axis", not router.seed_verified_samples(bad, {10: false, 11: false}))
	bad = axes.duplicate()
	bad[0] = NAN
	check("seed rejects nonfinite values without partial observations", not router.seed_verified_samples(bad, {10: false, 11: false}) and not router.sticks_centered())
	bad = axes.duplicate()
	bad[0] = 0.5
	check("seed requires centered navigation sticks", not router.seed_verified_samples(bad, {10: false, 11: false}))
	check("trusted verification sample seeds current centered/OFF values", router.seed_verified_samples(axes, {10: false, 11: false}))
	check("seeded radio does not need artificial motion to become ready", router.sticks_centered() and _advance(router, 0.01).is_empty() and router.ready_for_commands())
	router.observe(button(10, true))
	check("seeded OFF allows the next real Accept press", event_is(_advance(router, 0.01), "ui_accept", true))
	check("blocked dispatch releases an active Accept", event_is(_advance(router, 0.01, false), "ui_accept", false))
	router.observe(button(10, true))
	check("held Accept through ownership change does not fire", _advance(router, 0.01).is_empty())
	router.observe(button(10, false))
	_advance(router, 0.01)
	check("ordinary context reset has no held release", router.reset_context(false).is_empty())
	_advance(router, 0.01)
	router.observe(button(10, true))
	check("genuine cached OFF survives an ordinary context transition", event_is(_advance(router, 0.01), "ui_accept", true))
	router.observe(button(10, false))
	_advance(router, 0.01)
	router.observe(axis(7, 0.8))
	router.observe(axis(7, 0.47)) # learned axis between activation and release thresholds
	router.reset_context(false)
	_advance(router, 0.01)
	router.observe(axis(7, 0.2))
	check("hysteresis gap is not cached as OFF across context", _advance(router, 0.01).is_empty())
	router.observe(axis(7, 0.8))
	router.observe(axis(7, 0.2))
	check("fresh learned-axis OFF then ON recovers Back", event_is(_advance(router, 0.01), "ui_cancel", true))
	router.observe(axis(7, 0.8))
	_advance(router, 0.01)
	router.reset_context(true)
	check("focus invalidation clears cached axis and OFF evidence", not router.sticks_centered())
	router.observe(axis(0, 0.05))
	router.observe(axis(1, 0.1))
	_advance(router, 0.01)
	router.observe(button(10, true))
	check("focus invalidation requires a new real OFF", _advance(router, 0.01).is_empty())
	router.observe(button(10, false))
	router.observe(button(10, true))
	check("focus recovery accepts fresh OFF/ON", event_is(_advance(router, 0.01), "ui_accept", true))
	router.observe(button(10, false))
	_advance(router, 0.01)
	var clean := true
	for i in 100:
		router.observe(button(10, true))
		var pressed: Array[InputEventAction] = _advance(router, 0.01)
		router.observe(button(10, true))
		var held: Array[InputEventAction] = _advance(router, 0.2)
		router.observe(button(10, false))
		var released: Array[InputEventAction] = _advance(router, 0.01)
		clean = clean and event_is(pressed, "ui_accept", true) and held.is_empty() and event_is(released, "ui_accept", false)
	check("100 held Accept sequences each activate once", clean)
	var overloaded := _configured_router()
	_prime(overloaded)
	for i in 40:
		overloaded.observe(button(10, true))
		overloaded.observe(button(10, false))
	check("bounded event queue fails closed instead of replaying a flood", _advance(overloaded, 0.01).is_empty() and not overloaded.sticks_centered())
	var replaced := _configured_router()
	_prime(replaced)
	replaced.observe(axis(0, 0.65))
	check("replacement fixture has an active direction", event_is(_advance(replaced, 0.01), "ui_right", true))
	check("new generation configures", replaced.configure(DEVICE, 2, Menu.verified_profile(fixture())))
	check("replacement generation releases the previous virtual action", event_is(_advance(replaced, 0.01), "ui_right", false) and not replaced.sticks_centered())


func _dispatch(router: RefCounted, events: Array[InputEventAction]) -> void:
	for event: InputEventAction in events:
		root.push_input(event)
		router.mark_dispatched(event)


func _gui_test() -> void:
	var router := _configured_router()
	_prime(router)
	var raw_axis_before := Input.get_joy_axis(DEVICE, 0)
	var raw_button_before := Input.is_joy_button_pressed(DEVICE, 10)
	var surface := Control.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.position = Vector2(100, 100)
	column.size = Vector2(360, 300)
	surface.add_child(column)
	var first := Button.new()
	first.text = "First"
	var second := Button.new()
	second.text = "Second"
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 10.0
	slider.step = 1.0
	var option := OptionButton.new()
	option.add_item("One")
	option.add_item("Two")
	column.add_child(first)
	column.add_child(second)
	column.add_child(slider)
	column.add_child(option)
	root.add_child(surface)
	await process_frame
	await process_frame
	var presses := [0]
	first.pressed.connect(func() -> void: presses[0] += 1)
	first.grab_focus()
	router.observe(button(10, true))
	_dispatch(router, router.advance(0.01))
	router.observe(button(10, false))
	_dispatch(router, router.advance(0.01))
	await process_frame
	check("selected-radio native Accept activates a focused Button", presses[0] == 1, str(presses[0]))
	router.observe(axis(1, 0.9))
	_dispatch(router, router.advance(0.01))
	await process_frame
	check("selected-radio native Down moves GUI focus", second.has_focus(), str(root.gui_get_focus_owner()))
	router.observe(axis(1, 0.1))
	_dispatch(router, router.advance(0.01))
	slider.grab_focus()
	var old_slider := slider.value
	router.observe(axis(0, 0.65))
	_dispatch(router, router.advance(0.01))
	await process_frame
	check("selected-radio native Right adjusts a slider", slider.value > old_slider, str([old_slider, slider.value]))
	router.observe(axis(0, 0.05))
	_dispatch(router, router.advance(0.01))
	check("GUI fixture uses embedded native popups", root.gui_embed_subwindows)
	option.grab_focus()
	router.observe(button(10, true))
	_dispatch(router, router.advance(0.01))
	router.observe(button(10, false))
	_dispatch(router, router.advance(0.01))
	await process_frame
	check("selected-radio Accept opens OptionButton popup", option.get_popup().visible)
	router.observe(axis(1, 0.9))
	_dispatch(router, router.advance(0.01))
	router.observe(axis(1, 0.1))
	_dispatch(router, router.advance(0.01))
	router.observe(button(10, true))
	_dispatch(router, router.advance(0.01))
	router.observe(button(10, false))
	_dispatch(router, router.advance(0.01))
	await process_frame
	check("selected-radio navigates and chooses an OptionButton item", option.selected == 1, str(option.selected))
	check("GUI action delivery never injects raw joystick state", Input.get_joy_axis(DEVICE, 0) == raw_axis_before \
		and Input.is_joy_button_pressed(DEVICE, 10) == raw_button_before)
	_dispatch(router, router.reset_context(true))
	surface.free()
	await process_frame
