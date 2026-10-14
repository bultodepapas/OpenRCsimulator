extends SceneTree

## Focused AV-17-R2 contract and input-shaping regression checks.
## Run from the repo root with the pinned Godot build; --check-only validates syntax.

const AircraftData := preload("res://physics/aircraft_data.gd")
const Commands := preload("res://input/commands.gd")
const Flight := preload("res://sim/flight_session.gd")
const Profile := preload("res://input/controller_profile.gd")
const RcInput := preload("res://input/rc_input.gd")

const AVANTI_PATH := "res://data/aircraft/sebart_avanti_s_a200.json"
const OTHER_AIRCRAFT_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const TEST_DEVICE_ID := 37
const EPS := 1e-10

var _checks := 0
var _failures := 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	_run_checks()


func _run_checks() -> void:
	var source := _load_source(AVANTI_PATH)
	var loaded: Dictionary = AircraftData.validate_and_derive(source)
	_check("Avanti source passes aircraft validation", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		_finish()
		return
	var model: Dictionary = loaded.model
	_check("Avanti normalizes the 0.4 gamepad pitch scale", absf(float(model.controls.gamepad.pitch_scale) - 0.4) < EPS)

	_check("default Mode 2 gamepad profile validates", Profile.validate(Profile.defaults("gamepad", "mode2")).ok)
	var input := _new_gamepad_input()
	input.on_motion(TEST_DEVICE_ID, 3, 0.5)
	var pitch_only: Dictionary = input.sticks()
	var expected_half := _gamepad_condition(0.5, 0.08, 0.3)
	_check("RcInput maps raw axis 3 to pitch using one gamepad expo stage", absf(float(pitch_only.pitch) - expected_half) < EPS)
	_check("pitch-only raw sample leaves roll and yaw neutral", absf(float(pitch_only.roll)) < EPS and absf(float(pitch_only.yaw)) < EPS)
	input.on_motion(TEST_DEVICE_ID, 2, -0.4)
	input.on_motion(TEST_DEVICE_ID, 0, 0.25)
	var three_axes: Dictionary = input.sticks()
	_check("raw pitch, roll and yaw remain on their separate Mode 2 axes",
		absf(float(three_axes.pitch) - expected_half) < EPS
		and absf(float(three_axes.roll) - _gamepad_condition(-0.4, 0.08, 0.3)) < EPS
		and absf(float(three_axes.yaw) - _gamepad_condition(0.25, 0.08, 0.3)) < EPS)

	var normal_gamepad := _new_session(model, "normal", "gamepad")
	normal_gamepad.radio = input
	normal_gamepad.commands = three_axes.duplicate(true)
	var normal_outputs: Dictionary = normal_gamepad.flown_commands()
	var rates: Dictionary = model.controls.rates.normal
	_check("normal gamepad scales pitch only after its input expo",
		absf(float(normal_outputs.pitch) - expected_half * float(rates.elevator) * 0.4) < EPS)
	_check("gamepad pitch does not receive Avanti elevator expo a second time",
		absf(float(normal_outputs.pitch) - Commands.expo(expected_half, float(rates.elevator_expo)) * float(rates.elevator) * 0.4) > 1e-4)
	_check("normal gamepad pitch gain leaves aileron and rudder response unchanged",
		absf(float(normal_outputs.roll) - float(three_axes.roll) * float(rates.aileron)) < EPS
		and absf(float(normal_outputs.yaw) - float(three_axes.yaw) * float(rates.rudder)) < EPS)
	normal_gamepad.free()

	for endpoint in [-1.0, 1.0]:
		var endpoint_input := _new_gamepad_input()
		endpoint_input.on_motion(TEST_DEVICE_ID, 3, endpoint)
		var endpoint_session := _new_session(model, "normal", "gamepad")
		endpoint_session.radio = endpoint_input
		endpoint_session.commands = endpoint_input.sticks()
		var endpoint_output: Dictionary = endpoint_session.flown_commands()
		_check("normal gamepad pitch endpoint %.0f reaches scaled throw" % endpoint,
			absf(float(endpoint_session.commands.pitch) - endpoint) < EPS
			and absf(float(endpoint_output.pitch) - endpoint * 0.5 * 0.4) < EPS)
		if endpoint > 0.0:
			endpoint_session.trims.pitch = 0.1
			var trimmed: Dictionary = endpoint_session.flown_commands()
			_check("pitch trim is added after gamepad gain", absf(float(trimmed.pitch) - 0.3) < EPS)
		endpoint_session.free()

	var full_gamepad := _new_session(model, "full", "gamepad")
	full_gamepad.commands.pitch = 0.6
	_check("full-rate gamepad bypasses the normal pitch gain", absf(float(full_gamepad.flown_commands().pitch) - 0.6) < EPS)
	full_gamepad.free()

	var keyboard := _new_session(model, "normal", "keyboard")
	keyboard.commands.pitch = 0.5
	var keyboard_pitch: float = float(keyboard.flown_commands().pitch)
	_check("keyboard normal-rate path retains aircraft expo and bypasses gamepad gain",
		absf(keyboard_pitch - Commands.expo(0.5, float(rates.elevator_expo)) * float(rates.elevator)) < EPS)
	keyboard.free()

	var physical_radio := _new_session(model, "normal", "radio")
	physical_radio.commands.pitch = 1.0
	_check("physical radio bypasses the gamepad pitch scale and keeps full travel", absf(float(physical_radio.flown_commands().pitch) - 1.0) < EPS)
	physical_radio.free()

	var explicit_unity_source := source.duplicate(true)
	explicit_unity_source.controls.gamepad.pitch_scale.value = 1.0
	var explicit_unity_result: Dictionary = AircraftData.validate_and_derive(explicit_unity_source)
	var missing_gamepad_source := source.duplicate(true)
	missing_gamepad_source.controls.erase("gamepad")
	var missing_gamepad_result: Dictionary = AircraftData.validate_and_derive(missing_gamepad_source)
	_check("explicit unity gamepad scale is accepted", bool(explicit_unity_result.get("ok", false)))
	_check("missing optional gamepad section remains accepted", bool(missing_gamepad_result.get("ok", false)))
	if explicit_unity_result.get("ok", false) and missing_gamepad_result.get("ok", false):
		_check("explicit and missing gamepad scale normalize to one", absf(float(explicit_unity_result.model.controls.gamepad.pitch_scale) - 1.0) < EPS and not missing_gamepad_result.model.controls.has("gamepad"))
		var explicit_unity_session := _new_session(explicit_unity_result.model, "normal", "gamepad")
		var missing_gamepad_session := _new_session(missing_gamepad_result.model, "normal", "gamepad")
		for session in [explicit_unity_session, missing_gamepad_session]:
			session.commands = {roll = 0.2, pitch = 0.6, yaw = -0.3, throttle = 0.4}
		var unity_output: Dictionary = explicit_unity_session.flown_commands()
		var missing_output: Dictionary = missing_gamepad_session.flown_commands()
		_check("missing gamepad config behaves like explicit unity scale",
			absf(float(unity_output.pitch) - float(missing_output.pitch)) < EPS
			and absf(float(unity_output.roll) - float(missing_output.roll)) < EPS
			and absf(float(unity_output.yaw) - float(missing_output.yaw)) < EPS)
		explicit_unity_session.free()
		missing_gamepad_session.free()

	var other_source := _load_source(OTHER_AIRCRAFT_PATH)
	var other_loaded: Dictionary = AircraftData.validate_and_derive(other_source)
	_check("non-Avanti fallback aircraft passes validation", bool(other_loaded.get("ok", false)), str(other_loaded.get("errors", [])))
	if other_loaded.get("ok", false):
		var other_model: Dictionary = other_loaded.model
		_check("fallback aircraft has no gamepad-specific pitch scale", not other_model.controls.has("gamepad"))
		var other_gamepad := _new_session(other_model, "normal", "gamepad")
		other_gamepad.commands.pitch = 0.8
		var other_rates: Dictionary = other_model.controls.rates.normal
		_check("other aircraft uses unity gamepad scale with its normal elevator travel",
			absf(float(other_gamepad.flown_commands().pitch) - 0.8 * float(other_rates.elevator)) < EPS)
		other_gamepad.free()

	var wrong_unit := source.duplicate(true)
	wrong_unit.controls.gamepad.pitch_scale.unit = "deg"
	_check("gamepad pitch scale rejects a non-dimensionless unit", not AircraftData.validate_and_derive(wrong_unit).ok)
	for invalid_value in [0.04, 1.01]:
		var wrong_range := source.duplicate(true)
		wrong_range.controls.gamepad.pitch_scale.value = invalid_value
		_check("gamepad pitch scale rejects out-of-range value %s" % str(invalid_value), not AircraftData.validate_and_derive(wrong_range).ok)
	var missing_quantity := source.duplicate(true)
	missing_quantity.controls.gamepad.erase("pitch_scale")
	_check("gamepad pitch scale quantity is required when gamepad is present", not AircraftData.validate_and_derive(missing_quantity).ok)
	var missing_value := source.duplicate(true)
	missing_value.controls.gamepad.pitch_scale.erase("value")
	_check("gamepad pitch-scale quantity rejects a missing value", not AircraftData.validate_and_derive(missing_value).ok)
	var missing_rates := source.duplicate(true)
	missing_rates.controls.erase("rates")
	missing_rates.controls.erase("keyboard") # Isolate the gamepad dependency from the keyboard requirement.
	_check("gamepad pitch scale requires normal aircraft rates", not AircraftData.validate_and_derive(missing_rates).ok)
	var unknown_field := source.duplicate(true)
	unknown_field.controls.gamepad.pitch_scalar = 0.4
	_check("gamepad settings reject unknown fields", not AircraftData.validate_and_derive(unknown_field).ok)

	_finish()


func _load_source(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _new_gamepad_input() -> RcInput:
	var result := RcInput.new()
	var profile: Dictionary = Profile.defaults("gamepad", "mode2")
	result.connect_device(TEST_DEVICE_ID, {name = "AV-17-R2 test gamepad", guid = "draft-guid", vendor_id = 1, product_id = 1, known = true}, profile)
	result.set_auxiliary_enabled(true)
	result.armed = true
	return result


func _new_session(model: Dictionary, rate_profile: String, controller: String) -> Flight:
	var result := Flight.new()
	result.aircraft = {ok = true, model = model}
	result.rate_profile = rate_profile
	if controller == "gamepad":
		result.radio = _new_gamepad_input()
	elif controller == "radio":
		result.radio.connect_device(TEST_DEVICE_ID, {name = "AV-17-R2 test radio", guid = "draft-radio", vendor_id = 2, product_id = 2}, Profile.defaults("radio", "radio_custom"))
	return result


func _gamepad_condition(value: float, deadzone: float, expo: float) -> float:
	var rescaled := maxf(0.0, absf(value) - deadzone) / (1.0 - deadzone)
	return signf(value) * ((1.0 - expo) * rescaled + expo * rescaled * rescaled * rescaled)


func _finish() -> void:
	print("AV-17-R2 gamepad contract and input shaping: %d checks, %d failed" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
