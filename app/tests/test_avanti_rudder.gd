extends SceneTree

## AV-17-R3: focused input-response contract checks.
const AircraftData := preload("res://physics/aircraft_data.gd")
const Commands := preload("res://input/commands.gd")
const Flight := preload("res://sim/flight_session.gd")
const Profile := preload("res://input/controller_profile.gd")

const AVANTI_PATH := "res://data/aircraft/sebart_avanti_s_a200.json"
const DEVICE_ID := 37
const EPS := 1.0e-10

var checks := 0
var failures := 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	_test_response_law()
	_test_optional_configuration()
	_test_sampler_and_boundaries()
	print("AV-17-R3 rudder checks: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)


func _test_response_law() -> void:
	var expected := 1.0 - exp(-1.0)
	for hz in [120, 240, 480]:
		var value := 0.0
		var monotone := true
		for _tick in range(int(hz) / 10):
			var next: float = Commands.gamepad_yaw_response(value, 1.0, 1.0 / float(hz), 0.1)
			monotone = monotone and next >= value and next <= 1.0
			value = next
		_check("yaw response reaches 63.2 percent after 0.1 s at %d Hz" % hz,
			absf(value - expected) < EPS and monotone, "observed %.12f expected %.12f" % [value, expected])
	for side in [-1.0, 1.0]:
		var released: float = side * 0.8
		var release_monotone := true
		for _tick in 100:
			var next: float = Commands.gamepad_yaw_response(released, 0.0, 1.0 / 240.0, 0.1)
			release_monotone = release_monotone and signf(next) == side and absf(next) < absf(released)
			released = next
		_check("yaw release decays without sign reversal for side %.0f" % side, release_monotone)
	_check("zero response time preserves immediate target",
		absf(Commands.gamepad_yaw_response(-0.4, 0.35, 1.0 / 240.0, 0.0) - 0.35) < EPS)


func _test_optional_configuration() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AVANTI_PATH))
	var valid: Dictionary = AircraftData.validate_and_derive(source)
	_check("Avanti gamepad yaw fields validate", bool(valid.get("ok", false)), str(valid.get("errors", [])))
	if not bool(valid.get("ok", false)):
		return
	var minimum := source.duplicate(true)
	minimum.controls.gamepad.yaw_scale.value = 0.05
	minimum.controls.gamepad.yaw_response_time.value = 0.02
	var minimum_result: Dictionary = AircraftData.validate_and_derive(minimum)
	_check("yaw scale and response-time lower bounds are accepted", bool(minimum_result.get("ok", false)), str(minimum_result.get("errors", [])))
	var maximum := source.duplicate(true)
	maximum.controls.gamepad.yaw_scale.value = 1.0
	maximum.controls.gamepad.yaw_response_time.value = 0.5
	var maximum_result: Dictionary = AircraftData.validate_and_derive(maximum)
	_check("yaw scale and response-time upper bounds are accepted", bool(maximum_result.get("ok", false)), str(maximum_result.get("errors", [])))

	var missing := source.duplicate(true)
	missing.controls.gamepad.erase("yaw_scale")
	missing.controls.gamepad.erase("yaw_response_time")
	var missing_result: Dictionary = AircraftData.validate_and_derive(missing)
	_check("new yaw quantities remain optional", bool(missing_result.get("ok", false)), str(missing_result.get("errors", [])))
	if bool(missing_result.get("ok", false)):
		_check("normalization leaves absent yaw defaults absent",
			not missing_result.model.controls.gamepad.has("yaw_scale")
			and not missing_result.model.controls.gamepad.has("yaw_response_time"))

	var bad_number := source.duplicate(true)
	bad_number.controls.gamepad.yaw_response_time.value = "0.1"
	_check("response time rejects a string-valued quantity",
		not bool(AircraftData.validate_and_derive(bad_number).get("ok", false)))
	var out_of_range := source.duplicate(true)
	out_of_range.controls.gamepad.yaw_scale.value = 0.049
	_check("yaw scale rejects a value below its declared minimum",
		not bool(AircraftData.validate_and_derive(out_of_range).get("ok", false)))
	var out_of_range_time := source.duplicate(true)
	out_of_range_time.controls.gamepad.yaw_response_time.value = 0.501
	_check("response time rejects a value above its declared maximum",
		not bool(AircraftData.validate_and_derive(out_of_range_time).get("ok", false)))
	var bad_unit := source.duplicate(true)
	bad_unit.controls.gamepad.yaw_response_time.unit = "1"
	_check("response time requires seconds",
		not bool(AircraftData.validate_and_derive(bad_unit).get("ok", false)))
	var malformed := source.duplicate(true)
	malformed.controls.gamepad.yaw_scale = 0.5
	_check("yaw scale rejects a bare number instead of a quantity",
		not bool(AircraftData.validate_and_derive(malformed).get("ok", false)))
	var missing_rates := source.duplicate(true)
	missing_rates.controls.erase("rates")
	missing_rates.controls.erase("keyboard")
	var rates_result: Dictionary = AircraftData.validate_and_derive(missing_rates)
	_check("gamepad yaw settings still require normal rates",
		not bool(rates_result.get("ok", false)) and str(rates_result.get("errors", [])).contains("controls.gamepad: requires controls.rates.normal"),
		str(rates_result.get("errors", [])))


func _test_sampler_and_boundaries() -> void:
	var bundle := _new_gamepad_flight()
	var flight: Flight = bundle.flight
	var axes: Dictionary = bundle.axes
	if not flight.radio.armed:
		_check("synthetic gamepad arms from neutral evidence", false, str(flight.radio.input_error))
		flight.free()
		return
	var dt: float = flight.sim.dt()
	var tau: float = float(flight.aircraft.model.controls.gamepad.get("yaw_response_time", 0.0))
	var scale: float = float(flight.aircraft.model.controls.gamepad.get("yaw_scale", 1.0))
	axes.yaw = 0.5
	flight._physics_process(dt)
	var target: float = Profile.conditioned_axis(0.5, flight.radio.profile.yaw, "gamepad")
	var expected_first := target * (1.0 - exp(-dt / tau)) if tau > 0.0 else target
	_check("live poll exposes conditioned yaw in raw while filtering commands",
		absf(float(flight.raw.yaw) - target) < EPS and absf(float(flight.commands.yaw) - expected_first) < EPS,
		"raw %.9f command %.9f expected %.9f" % [flight.raw.yaw, flight.commands.yaw, expected_first])
	_check("live yaw filtering leaves roll and pitch independent",
		absf(float(flight.raw.roll)) < EPS and absf(float(flight.raw.pitch)) < EPS
		and absf(float(flight.commands.roll)) < EPS and absf(float(flight.commands.pitch)) < EPS)
	var rates: Dictionary = flight.aircraft.model.controls.rates.normal
	flight.trims.yaw = 0.1
	var normal_output: Dictionary = flight.flown_commands()
	var expected_output := expected_first * float(rates.rudder) * scale + 0.1
	_check("gamepad yaw travel is applied after one input-expo stage and before trim",
		absf(float(normal_output.yaw) - expected_output) < EPS,
		"output %.9f expected %.9f" % [normal_output.yaw, expected_output])

	var previous: float = flight.commands.yaw
	axes.yaw = 0.0
	flight._physics_process(dt)
	var expected_release := previous * exp(-dt / tau) if tau > 0.0 else 0.0
	_check("live release moves toward center while raw yaw is already zero",
		absf(float(flight.raw.yaw)) < EPS and absf(float(flight.commands.yaw) - expected_release) < EPS
		and (tau <= 0.0 or signf(float(flight.commands.yaw)) == signf(previous)))

	flight.hold("rudder-test")
	var held_command: float = flight.commands.yaw
	var held_raw: float = flight.raw.yaw
	axes.yaw = -0.5
	flight._physics_process(dt)
	_check("hold freezes live command and raw sample", absf(float(flight.commands.yaw) - held_command) < EPS and absf(float(flight.raw.yaw) - held_raw) < EPS)
	flight.release("rudder-test")
	flight.reset()
	_check("reset centers the transient gamepad yaw command", absf(float(flight.commands.yaw)) < EPS)

	# The existing physics checkpoint stores the command fed to the airplane, not a new radio-state field.
	axes.yaw = 0.5
	flight._physics_process(dt)
	var boundary: Dictionary = flight.checkpoint()
	var checkpoint_ok: bool = boundary.has("simulation") and boundary.simulation.get("inputs", PackedFloat64Array()).size() >= 3
	_check("flight checkpoint contains filtered yaw input", checkpoint_ok, str(boundary.keys()))
	if checkpoint_ok:
		var saved_yaw: float = float(boundary.simulation.inputs[2])
		flight.sim.inputs[2] = 0.0
		var restored: bool = flight.restore_checkpoint(boundary)
		_check("checkpoint restores the filtered airplane yaw input",
			restored and absf(float(flight.sim.inputs[2]) - saved_yaw) < EPS)
	var model: Dictionary = flight.aircraft.model
	flight.free()

	# Missing optional fields must retain the pre-R3 immediate/full normal-travel behavior.
	var fallback_bundle := _new_gamepad_flight()
	var fallback: Flight = fallback_bundle.flight
	var fallback_axes: Dictionary = fallback_bundle.axes
	var controls: Dictionary = fallback.aircraft.model.controls.gamepad
	controls.erase("yaw_scale")
	controls.erase("yaw_response_time")
	fallback_axes.yaw = 0.5
	fallback._physics_process(fallback.sim.dt())
	var fallback_target: float = Profile.conditioned_axis(0.5, fallback.radio.profile.yaw, "gamepad")
	_check("missing yaw quantities use immediate unity-gain runtime fallbacks",
		absf(float(fallback.raw.yaw) - fallback_target) < EPS
		and absf(float(fallback.commands.yaw) - fallback_target) < EPS)
	fallback.commands.yaw = 0.4
	fallback.trims.yaw = 0.1
	var fallback_output: Dictionary = fallback.flown_commands()
	_check("missing yaw scale does not attenuate rudder travel or trim",
		absf(float(fallback_output.yaw) - (0.4 * float(fallback.aircraft.model.controls.rates.normal.rudder) + 0.1)) < EPS)
	# Reinstate filtering to check that disarming clears a real nonzero response state.
	controls.yaw_response_time = 0.1
	fallback.radio.armed = false
	fallback.radio.confirmed_gamepad_connection = func(_id: int) -> bool: return false
	fallback_axes.yaw = 0.5
	fallback._physics_process(fallback.sim.dt())
	_check("unarmed gamepad polling clears command without response memory",
		not fallback.radio.armed and absf(float(fallback.commands.yaw)) < EPS)
	fallback.free()

	var full := _new_detached_session(model, "gamepad", "full")
	full.commands.yaw = 0.4
	full.trims.yaw = 0.1
	_check("full-rate gamepad bypasses yaw scale", absf(float(full.flown_commands().yaw) - 0.5) < EPS)
	full.free()
	var full_bundle := _new_gamepad_flight()
	var full_poll: Flight = full_bundle.flight
	var full_axes: Dictionary = full_bundle.axes
	full_poll.rate_profile = "full"
	full_axes.yaw = 0.5
	full_poll._physics_process(full_poll.sim.dt())
	var full_target: float = Profile.conditioned_axis(0.5, full_poll.radio.profile.yaw, "gamepad")
	_check("full-rate gamepad sampler bypasses response filtering",
		absf(float(full_poll.raw.yaw) - full_target) < EPS and absf(float(full_poll.commands.yaw) - full_target) < EPS)
	full_poll.free()
	var radio := _new_detached_session(model, "radio", "normal")
	radio.commands.yaw = 0.4
	radio.trims.yaw = 0.1
	_check("physical-radio yaw bypasses gamepad scale and normal dual-rate travel", absf(float(radio.flown_commands().yaw) - 0.5) < EPS)
	radio.free()
	var radio_bundle := _new_radio_flight()
	var radio_poll: Flight = radio_bundle.flight
	var radio_axes: Dictionary = radio_bundle.axes
	radio_axes.yaw = 0.5
	radio_poll._physics_process(radio_poll.sim.dt())
	var radio_target: float = Profile.conditioned_axis(0.5, radio_poll.radio.profile.yaw, "radio")
	_check("physical-radio sampler bypasses gamepad response filtering",
		absf(float(radio_poll.raw.yaw) - radio_target) < EPS and absf(float(radio_poll.commands.yaw) - radio_target) < EPS)
	radio_poll.free()
	var keyboard := _new_detached_session(model, "keyboard", "normal")
	keyboard.commands.yaw = 0.4
	keyboard.trims.yaw = 0.1
	var keyboard_expected := Commands.expo(0.4, float(rates.rudder_expo)) * float(rates.rudder) + 0.1
	_check("keyboard yaw retains aircraft expo and bypasses gamepad scale", absf(float(keyboard.flown_commands().yaw) - keyboard_expected) < EPS)
	keyboard.free()


func _new_gamepad_flight() -> Dictionary:
	var flight: Flight = Flight.new()
	flight.rate_profile = "normal"
	flight.setup(AVANTI_PATH, "sebart-avanti-s-a200-p100rx")
	root.add_child(flight)
	flight.set_physics_process(false)
	flight.sim.set_physics_process(false)
	flight.reset()
	flight.radio.connect_device(DEVICE_ID, {known = true, name = "Synthetic Gamepad"}, Profile.defaults("gamepad", "mode2"))
	flight.radio.confirmed_gamepad_connection = func(id: int) -> bool: return id == DEVICE_ID
	var axes := {yaw = 0.0}
	flight.read_axis = func(_id: int, axis: int) -> float: return float(axes.yaw) if axis == 0 else 0.0
	flight.read_button = func(_id: int, _button: int) -> bool: return false
	for _tick in 60:
		flight.radio.poll(flight.read_axis, flight.sim.dt(), flight.read_button, false)
	return {flight = flight, axes = axes}


func _new_detached_session(model: Dictionary, kind: String, rates: String) -> Flight:
	var flight: Flight = Flight.new()
	flight.aircraft = {ok = true, model = model}
	flight.rate_profile = rates
	if kind == "gamepad":
		flight.radio.connect_device(DEVICE_ID, {known = true, name = "Synthetic Gamepad"}, Profile.defaults("gamepad", "mode2"))
	elif kind == "radio":
		flight.radio.connect_device(DEVICE_ID, {known = true, name = "Synthetic Radio"}, Profile.defaults("radio", "radio_custom"))
	if kind != "keyboard":
		flight.radio.armed = true
	flight.commands = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	flight.trims = {roll = 0.0, pitch = 0.0, yaw = 0.0}
	return flight


func _new_radio_flight() -> Dictionary:
	var flight: Flight = Flight.new()
	flight.rate_profile = "normal"
	flight.setup(AVANTI_PATH, "sebart-avanti-s-a200-p100rx")
	root.add_child(flight)
	flight.set_physics_process(false)
	flight.sim.set_physics_process(false)
	flight.reset()
	flight.radio.connect_device(DEVICE_ID, {known = true, name = "Synthetic Radio"}, Profile.defaults("radio", "radio_custom"))
	flight.radio.armed = true
	var axes := {yaw = 0.0}
	flight.read_axis = func(_id: int, axis: int) -> float: return float(axes.yaw) if axis == 3 else 0.0
	flight.read_button = func(_id: int, _button: int) -> bool: return false
	return {flight = flight, axes = axes}
