extends RefCounted
## Research-only circuit pilot through FlightSession's ordinary keyboard seam.
## The companion produces trim-relative demands and an absolute throttle target;
## Commands.step_commands still owns all keyboard rate limits and session inputs.

signal failed(reason: String)

const Pilot := preload("res://ai/companions/pilot.gd")
const Airdata := preload("res://ai/companions/observation_airdata.gd")
const Spec := preload("res://spec.gd")
const Simulation := preload("res://sim/simulation.gd")
const UPDATE_TICKS := 4

var session: Node
var pilot: RefCounted
var failure := ""
var input_reads := 0
var pilot_updates := 0
var last_read_tick := -1
var last_pilot_tick := -1
var input_elapsed_usec := 0
var pilot_elapsed_usec := 0
var latest_packet: Dictionary = {}
var latest_clearance_m := NAN
var min_clearance_m := INF
var max_abs_radius_error_m := 0.0
var _trim: Dictionary = {}
var _turbulence := PackedFloat64Array([0.0, 0.0, 0.0])


func configure(owner: Node, field: Dictionary, seed_value: int) -> bool:
	if not is_instance_valid(owner) or owner.sim == null or owner.sim.tick != 0 \
			or not owner.physics_enabled or not owner.input_enabled or owner.external_driver_enabled \
			or owner.radio.connected or owner.rate_profile != "full" or not owner.is_flyable():
		return _fail("session must be a valid automatic-input, full-rate flight at tick zero")
	if field.get("id", "") != "default" or not Simulation.state_is_valid(owner.sim.state):
		return _fail("Club field and finite initial flight state are required")
	session = owner
	_trim = owner.start.duplicate(true)
	var weather: Dictionary = owner.weather_configuration()
	_turbulence = PackedFloat64Array(weather.get("turbulence_rms_mps", [0.0, 0.0, 0.0]))
	pilot = Pilot.new()
	if not pilot.configure(0, 1, seed_value, _trim, field):
		return _fail("circuit pilot refused trim/field: " + str(pilot.configure_error))
	return true


## Same conversion as debug_bridge._read_override. It deliberately does not
## invert the keyboard slew limit: large target changes take multiple ticks.
static func keyboard_sample(packet: Dictionary, current_throttle: float, dt: float) -> Dictionary:
	if not is_finite(current_throttle) or current_throttle < 0.0 or current_throttle > 1.0 \
			or not is_finite(dt) or dt <= 0.0:
		return {ok = false, reason = "invalid current throttle or tick duration"}
	for axis: String in ["roll", "pitch", "yaw", "throttle"]:
		if typeof(packet.get(axis)) not in [TYPE_INT, TYPE_FLOAT]:
			return {ok = false, reason = "missing or nonnumeric " + axis}
		var value := float(packet[axis])
		if not is_finite(value) or value > 1.0 or value < (0.0 if axis == "throttle" else -1.0):
			return {ok = false, reason = "out-of-range " + axis}
	var per_tick: float = float(Spec.CONTROLS.throttle_rate) * dt
	return {ok = true, raw = {roll = float(packet.roll), pitch = float(packet.pitch),
		yaw = float(packet.yaw), throttle = clampf((float(packet.throttle) - current_throttle) / per_tick, -1.0, 1.0)}}


## Called by the production FlightSession once before each automatically owned tick.
func read_raw() -> Dictionary:
	var began := Time.get_ticks_usec()
	var result := _read_raw_impl()
	input_elapsed_usec += Time.get_ticks_usec() - began
	return result


func _read_raw_impl() -> Dictionary:
	var neutral := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	if not failure.is_empty() or not is_instance_valid(session) or pilot == null:
		return neutral
	var sim: Node = session.sim
	var tick: int = sim.tick
	input_reads += 1
	if (last_read_tick < 0 and tick != 0) or (last_read_tick >= 0 and tick != last_read_tick + 1):
		_fail("input sampling lost consecutive ticks: %d after %d" % [tick, last_read_tick])
		return neutral
	last_read_tick = tick
	if tick % UPDATE_TICKS == 0 or latest_packet.is_empty():
		if not Simulation.state_is_valid(sim.state):
			_fail("pilot received invalid simulation state")
			return neutral
		var state: PackedFloat64Array = sim.state.duplicate()
		var wind: PackedFloat64Array = session.wind_at(sim.time(), state)
		var ground: PackedFloat64Array = session.environment.ground(state[0], state[1])
		if wind.size() != 3 or ground.is_empty() or not is_finite(ground[0]):
			_fail("pilot weather or ground observation is invalid")
			return neutral
		latest_clearance_m = -state[2] - ground[0]
		var snapshot := {state = state, wind_ned = wind, airspeed_m_s = Airdata.airspeed_m_s(state, wind),
			ground_clearance_m = latest_clearance_m, trim = _trim,
			turbulence_rms_m_s = _turbulence, is_player = true}
		var pilot_began := Time.get_ticks_usec()
		var result: Dictionary = pilot.command(snapshot, tick, [])
		pilot_elapsed_usec += Time.get_ticks_usec() - pilot_began
		if not result.get("ok", false):
			_fail("pilot refused state: " + str(result.get("reason", "unknown")))
			return neutral
		if not is_finite(latest_clearance_m) or not is_finite(float(result.get("radius_error_m", NAN))):
			_fail("pilot produced nonfinite route observation")
			return neutral
		latest_packet = result
		last_pilot_tick = tick
		pilot_updates += 1
		min_clearance_m = minf(min_clearance_m, latest_clearance_m)
		max_abs_radius_error_m = maxf(max_abs_radius_error_m, absf(float(result.radius_error_m)))
	var converted := keyboard_sample(latest_packet, float(session.commands.throttle), sim.dt())
	if not converted.ok:
		_fail("pilot command refused: " + str(converted.reason))
		return neutral
	return converted.raw


func _fail(reason: String) -> bool:
	if failure.is_empty():
		failure = reason
		failed.emit(reason)
	return false
