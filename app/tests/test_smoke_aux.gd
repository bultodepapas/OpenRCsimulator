# SM-03/04: fake-device coverage for the pump assignment and failsafe behavior.
extends SceneTree

const RcInput := preload("res://input/rc_input.gd")
const RcCalibration := preload("res://input/rc_calibration.gd")
const SmokeAux := preload("res://input/smoke_aux.gd")
const Assignment := preload("res://ui/smoke_aux_assignment.gd")
const PATH := "user://test_smoke_aux.cfg"
const CORRUPT_PATH := "user://test_smoke_aux_corrupt.cfg"
const UNREADABLE_PATH := "user://test_smoke_aux_unreadable"
const INFO := { guid = "fake", name = "EdgeTX test radio", vendor_id = 0x1209, product_id = 0x4f54 }
const DT := 1.0 / 240.0

var _count: int = 0
var _failures: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _radio_profile(binding: Dictionary = {}) -> Dictionary:
	var profile: Dictionary = RcInput.DEFAULT_PROFILE.duplicate(true)
	if not binding.is_empty():
		profile.aux = { smoke = binding.duplicate(true) }
	return profile


func _calibration_with_aux(aux_axis: int) -> RcCalibration:
	var old_profile := _radio_profile({ type = "axis", axis = aux_axis, off = -1.0, on = 1.0, invert = false })
	var calibration := RcCalibration.new(old_profile)
	var rest := PackedFloat64Array()
	rest.resize(RcInput.AXES)
	calibration.advance(rest)
	for axis in [0, 5, 6, 7]:
		var low := rest.duplicate()
		var high := rest.duplicate()
		low[axis] = -1.0
		high[axis] = 1.0
		calibration.sample(low)
		calibration.sample(high)
		calibration.advance(rest)
	return calibration


func _initialize() -> void:
	var axis_binding := { type = "axis", axis = 4, off = -1.0, on = 1.0, invert = false }
	var profile := _radio_profile(axis_binding)
	_check("valid AUX remains optional to the AETR validator", RcCalibration.valid(profile))
	_check("axis binding is valid away from AETR", SmokeAux.valid_binding(axis_binding, [0, 1, 2, 3]))
	_check("AETR axis cannot be assigned to smoke", not SmokeAux.valid_binding({ type = "axis", axis = 0, off = -1.0, on = 1.0, invert = false }, [0, 1, 2, 3]))
	_check("reversed axis endpoints require inversion metadata", not SmokeAux.valid_binding({ type = "axis", axis = 4, off = 1.0, on = -1.0, invert = false }, [0, 1, 2, 3]))
	_check("button binding accepts explicit level and toggle modes", SmokeAux.valid_binding({ type = "button", button = 5, mode = "level" }) and SmokeAux.valid_binding({ type = "button", button = 5, mode = "toggle_edge" }))

	# Invalid optional AUX is removed without invalidating or changing the four flight channels.
	var malformed := _radio_profile({ type = "axis", axis = 90, off = -1.0, on = 1.0, invert = false })
	_check("bad AUX does not reject a valid radio base", RcCalibration.valid(malformed))
	var cleaned := SmokeAux.sanitize_profile(malformed, false)
	_check("bad AUX is discarded", not cleaned.has("aux") and RcCalibration.valid(cleaned))
	var overlap := _radio_profile({ type = "axis", axis = 2, off = -1.0, on = 1.0, invert = false })
	var fake_radio := RcInput.new()
	fake_radio.connect_device(3, INFO, overlap)
	fake_radio.poll(func(_device: int, axis: int) -> float: return -1.0 if axis == 2 else 0.0, DT)
	_check("AETR collision disables smoke only", fake_radio.profile.has("roll") and fake_radio.sticks().throttle == 0.0 and not fake_radio.profile.has("aux"))
	_check("flight channels stay live after invalid AUX", fake_radio.sticks().roll == 0.0 and RcCalibration.valid(fake_radio.profile))

	# Axis starts OFF only after an observed OFF; high on connect/reconnect/profile change is safe.
	var radio := RcInput.new()
	radio.connect_device(3, INFO, profile)
	radio.poll(func(_device: int, _axis: int) -> float: return 0.0, DT)
	_check("startup polling zero is not an OFF event", not radio.smoke_is_armed() and radio.smoke_amount() == 0.0)
	radio.on_motion(8, 4, -1.0)
	radio.on_motion(3, 4, 1.0)
	radio.poll(func(_device: int, _axis: int) -> float: return 0.0, DT)
	_check("other device is ignored and stale zero polling cannot arm after ON", not radio.smoke_is_armed() and radio.smoke_amount() == 0.0)
	radio.on_motion(3, 0, 1.0)
	_check("AETR motion does not drive the pump", radio.smoke_amount() == 0.0)
	radio.on_motion(3, 4, -1.0)
	_check("matching-device OFF event arms with pump stopped", radio.smoke_is_armed() and radio.smoke_amount() == 0.0)
	radio.poll(func(_device: int, axis: int) -> float: return 1.0 if axis == 4 else (-1.0 if axis == 2 else 0.0), DT)
	_check("axis ON produces full pump request", absf(radio.smoke_amount() - 1.0) < 1e-12)
	radio.use_profile(profile, "calibrated")
	_check("profile change immediately stops and disarms smoke", not radio.smoke_is_armed() and radio.smoke_amount() == 0.0)
	radio.poll(func(_device: int, _axis: int) -> float: return 0.0, DT)
	_check("same-axis stale zero after profile change is not OFF evidence", not radio.smoke_is_armed() and radio.smoke_amount() == 0.0)
	radio.on_motion(3, 4, -1.0)
	_check("profile requires a new AUX OFF event", radio.smoke_is_armed() and radio.smoke_amount() == 0.0)
	radio.disconnect_device()
	_check("disconnect forces smoke OFF", radio.smoke_amount() == 0.0 and not radio.smoke_is_armed())
	radio.connect_device(3, INFO, profile)
	radio.poll(func(_device: int, _axis: int) -> float: return 0.0, DT)
	_check("reconnect stale zero stays disarmed", radio.smoke_amount() == 0.0 and not radio.smoke_is_armed())
	radio.on_motion(3, 4, 1.0)
	radio.poll(func(_device: int, _axis: int) -> float: return 0.0, DT)
	_check("reconnect polling zero after ON event stays disarmed", radio.smoke_amount() == 0.0 and not radio.smoke_is_armed())
	radio.on_motion(3, 4, -1.0)
	_check("reconnect OFF event rearms", radio.smoke_is_armed() and radio.smoke_amount() == 0.0)

	# Button level follows the held state; wrong devices/buttons have no effect.
	var level_profile := _radio_profile({ type = "button", button = 5, mode = "level" })
	var level_radio := RcInput.new()
	level_radio.connect_device(3, INFO, level_profile)
	level_radio.poll(func(_device: int, _axis: int) -> float: return 0.0, DT, func(_device: int, _button: int) -> bool: return false)
	_check("button false polling alone is not OFF evidence", not level_radio.smoke_is_armed())
	level_radio.on_button(8, 5, true)
	level_radio.on_button(3, 6, true)
	_check("other device and button do not pump", level_radio.smoke_amount() == 0.0)
	level_radio.on_button(3, 5, true)
	_check("button ON event before OFF stays disarmed", not level_radio.smoke_is_armed() and level_radio.smoke_amount() == 0.0)
	level_radio.poll(func(_device: int, _axis: int) -> float: return 0.0, DT, func(_device: int, _button: int) -> bool: return false)
	_check("button false polling after ON still cannot arm", not level_radio.smoke_is_armed())
	level_radio.on_button(3, 5, false)
	_check("button OFF event arms with pump stopped", level_radio.smoke_is_armed() and level_radio.smoke_amount() == 0.0)
	level_radio.on_button(3, 5, true)
	_check("level mode pumps while held", level_radio.smoke_amount() == 1.0)
	level_radio.on_button(3, 5, false)
	_check("level mode stops on release", level_radio.smoke_amount() == 0.0)

	# toggle_edge changes only on the press edge, not release or repeated held samples.
	var toggle_profile := _radio_profile({ type = "button", button = 6, mode = "toggle_edge" })
	var toggle_radio := RcInput.new()
	toggle_radio.connect_device(3, INFO, toggle_profile)
	toggle_radio.poll(func(_device: int, _axis: int) -> float: return 0.0, DT, func(_device: int, _button: int) -> bool: return false)
	_check("toggle button polling false does not arm", not toggle_radio.smoke_is_armed())
	toggle_radio.on_button(3, 6, true)
	toggle_radio.poll(func(_device: int, _axis: int) -> float: return 0.0, DT, func(_device: int, _button: int) -> bool: return false)
	_check("stale toggle false poll after press does not arm", not toggle_radio.smoke_is_armed())
	toggle_radio.on_button(3, 6, false)
	_check("toggle OFF event arms", toggle_radio.smoke_is_armed())
	toggle_radio.on_button(3, 6, true)
	toggle_radio.on_button(3, 6, true)
	_check("toggle mode turns on once at the press edge", toggle_radio.smoke_amount() == 1.0)
	toggle_radio.on_button(3, 6, false)
	toggle_radio.on_button(3, 6, false)
	_check("toggle mode ignores release edges", toggle_radio.smoke_amount() == 1.0)
	toggle_radio.on_button(3, 6, true)
	_check("second press edge toggles OFF", toggle_radio.smoke_amount() == 0.0)

	# AETR recalibration carries AUX forward, except when a newly selected flight axis collides.
	var preserved := _calibration_with_aux(4)
	_check("recalibration stays complete", preserved.done() and RcCalibration.valid(preserved.profile))
	_check("recalibration preserves non-conflicting AUX", preserved.profile.aux.smoke.axis == 4)
	var collided := _calibration_with_aux(5)
	_check("recalibration drops a newly conflicting AUX axis", collided.done() and collided.aux_warning != "" and not collided.profile.has("aux"))

	# The guided assignment ignores other devices and AETR, rejects ambiguity, and emits a complete profile.
	var axes := PackedFloat64Array()
	axes.resize(RcInput.AXES)
	var wizard := Assignment.new()
	get_root().add_child(wizard)
	var ready_profiles: Array = []
	wizard.profile_ready.connect(func(value: Dictionary) -> void: ready_profiles.append(value))
	wizard.begin(9, _radio_profile(), "fake-device", PATH, axes)
	wizard.advance()
	wizard.sample_axis(8, 4, 1.0)
	wizard.sample_axis(9, 0, 1.0)
	wizard.sample_axis(9, 5, -1.0)
	wizard.sample_axis(9, 4, 1.0)
	wizard.advance()
	_check("wizard rejects ambiguous controls and ignores AETR", wizard.stage == 1 and not wizard.error.is_empty())
	wizard.sample_axis(9, 4, 1.0)
	wizard.advance()
	wizard.sample_axis(9, 4, 0.0)
	_check("axis wizard completes after OFF → ON → OFF", wizard.advance() and ready_profiles.size() == 1)
	_check("wizard emits full profile with explicit AUX axis endpoints", ready_profiles[0].aux.smoke.axis == 4 and ready_profiles[0].aux.smoke.off == 0.0 and ready_profiles[0].aux.smoke.on == 1.0)
	wizard.queue_free()

	var button_wizard := Assignment.new()
	get_root().add_child(button_wizard)
	var button_profiles: Array = []
	button_wizard.profile_ready.connect(func(value: Dictionary) -> void: button_profiles.append(value))
	button_wizard.begin(9, _radio_profile(), "", PATH, axes)
	button_wizard.advance()
	button_wizard.sample_button(9, 7, true)
	button_wizard.advance()
	button_wizard.set_button_mode("toggle_edge")
	button_wizard.sample_button(9, 7, false)
	_check("button wizard records explicit toggle mode", button_wizard.advance() and button_profiles[0].aux.smoke.mode == "toggle_edge")
	button_wizard.queue_free()

	# Radio profiles keep their strict validator; gamepad persistence stores only a validated binding.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CORRUPT_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(UNREADABLE_PATH))
	_check("save valid AUX profile", RcCalibration.save_profile(PATH, "fake-device", profile) == OK)
	_check("valid AUX profile round trips", RcCalibration.load_profile(PATH, "fake-device").aux.smoke == axis_binding)
	_check("old profiles without AUX remain valid", RcCalibration.save_profile(PATH, "legacy", RcInput.DEFAULT_PROFILE) == OK and not RcCalibration.load_profile(PATH, "legacy").has("aux"))
	_check("save drops malformed AUX but preserves AETR", RcCalibration.save_profile(PATH, "bad-aux", malformed) == OK and not RcCalibration.load_profile(PATH, "bad-aux").has("aux"))
	var gamepad_binding := { type = "button", button = 11, mode = "toggle_edge" }
	_check("save a valid gamepad smoke binding", RcCalibration.save_smoke_binding(PATH, "gamepad-device", gamepad_binding) == OK)
	_check("gamepad smoke binding round trips", RcCalibration.load_smoke_binding(PATH, "gamepad-device") == gamepad_binding)
	_check("gamepad binding write preserves radio profile", RcCalibration.valid(RcCalibration.load_profile(PATH, "fake-device")) and RcCalibration.load_profile(PATH, "fake-device").aux.smoke == axis_binding)
	_check("gamepad binding does not become a flight profile", RcCalibration.load_profile(PATH, "gamepad-device").is_empty())
	_check("unknown device has no smoke binding", RcCalibration.load_smoke_binding(PATH, "unknown-device").is_empty())
	var bad_gamepad_binding := { type = "axis", axis = SmokeAux.AXES, off = 0.0, on = 1.0, invert = false }
	_check("invalid gamepad binding is rejected without replacing the saved binding", RcCalibration.save_smoke_binding(PATH, "gamepad-device", bad_gamepad_binding) == ERR_INVALID_DATA and RcCalibration.load_smoke_binding(PATH, "gamepad-device") == gamepad_binding)
	_check("empty device key cannot save a smoke binding", RcCalibration.save_smoke_binding(PATH, "", gamepad_binding) == ERR_INVALID_DATA)
	var invalid_cfg := ConfigFile.new()
	var mismatch_section := "identity-mismatch".md5_text()
	invalid_cfg.set_value(mismatch_section, "device_key", "different-identity")
	invalid_cfg.set_value(mismatch_section, "smoke_binding", gamepad_binding)
	var invalid_binding_section := "invalid-binding".md5_text()
	invalid_cfg.set_value(invalid_binding_section, "device_key", "invalid-binding")
	invalid_cfg.set_value(invalid_binding_section, "smoke_binding", bad_gamepad_binding)
	_check("write malformed binding fixture", invalid_cfg.save(CORRUPT_PATH) == OK)
	_check("mismatched stored identity is rejected", RcCalibration.load_smoke_binding(CORRUPT_PATH, "identity-mismatch").is_empty())
	_check("corrupt stored binding is rejected", RcCalibration.load_smoke_binding(CORRUPT_PATH, "invalid-binding").is_empty())
	var corrupt_file := FileAccess.open(CORRUPT_PATH, FileAccess.WRITE)
	corrupt_file.store_string("[broken\nkey = value\n")
	corrupt_file.close()
	var corrupt_bytes := FileAccess.get_file_as_bytes(CORRUPT_PATH)
	var corrupt_read := ConfigFile.new()
	# ConfigFile intentionally logs an ERROR for broken syntax. Suppress only these three synchronous
	# negative-control calls; restore diagnostics before checking their exact results or doing other work.
	var previous_error_output := Engine.print_error_messages
	Engine.print_error_messages = false
	var parse_error: Error = corrupt_read.load(CORRUPT_PATH)
	var rejected_binding: Dictionary = RcCalibration.load_smoke_binding(CORRUPT_PATH, "gamepad-device")
	var save_error: Error = RcCalibration.save_smoke_binding(CORRUPT_PATH, "gamepad-device", gamepad_binding)
	Engine.print_error_messages = previous_error_output
	_check("malformed config fixture is unreadable", parse_error == ERR_PARSE_ERROR)
	_check("unreadable config returns no binding", rejected_binding.is_empty())
	_check("save preserves unreadable config", save_error == ERR_PARSE_ERROR and FileAccess.get_file_as_bytes(CORRUPT_PATH) == corrupt_bytes)
	var unreadable_absolute := ProjectSettings.globalize_path(UNREADABLE_PATH)
	DirAccess.make_dir_recursive_absolute(unreadable_absolute)
	_check("directory at config path returns no binding", RcCalibration.load_smoke_binding(UNREADABLE_PATH, "gamepad-device").is_empty())
	_check("directory at config path rejects saves", RcCalibration.save_smoke_binding(UNREADABLE_PATH, "gamepad-device", gamepad_binding) != OK)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CORRUPT_PATH))
	DirAccess.remove_absolute(unreadable_absolute)

	print("SM-03/04: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures else 0)
