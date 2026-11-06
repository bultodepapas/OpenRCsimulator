# NK-2a / external audit A6 O4: same-callback air reuse, legacy dispatch and refusal.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Weather := preload("res://physics/wind_config.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

# Derived sessions deliberately retain the old two-query path; this is the oracle.
class LegacyFlight extends "res://sim/flight_session.gd":
	pass

class DispatchFlight extends "res://sim/flight_session.gd":
	var calls: Array[String] = []
	var sentinel := false
	var reject_explicit := false
	func _wing_cl(s: PackedFloat64Array, aux: PackedFloat64Array, time_s: float = NAN) -> float:
		calls.append("wake")
		return 7.0 if sentinel else super._wing_cl(s, aux, time_s)
	func air_data(s: PackedFloat64Array, time_s: float = NAN) -> Dictionary:
		calls.append("implicit" if is_nan(time_s) else "explicit")
		var air := super.air_data(s, time_s)
		if reject_explicit and not is_nan(time_s): air.V = NAN
		return air

class CountingWind extends "res://physics/wind_field.gd":
	var queries := 0
	var reject := ""
	var origin := PackedFloat64Array()
	func sample(time_s: float) -> PackedFloat64Array:
		queries += 1
		return PackedFloat64Array([NAN, NAN, NAN]) if reject == "datum" else super.sample(time_s)
	func sample_world(position: PackedFloat64Array, time_s: float) -> PackedFloat64Array:
		queries += 1
		if reject == "datum" or (reject == "station" and position != origin):
			return PackedFloat64Array([NAN, NAN, NAN])
		return super.sample_world(position, time_s)

var _checks := 0
var _failures := 0

func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for spatial: bool in [false, true]:
		for id: String in ["jensen-das-ugly-stik-60", "turbo-lumber-evolution", "moonrunner-x99"]:
			_pair(id, spatial)
	_dispatch()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)

func _prepare(script: Script, id: String, spatial: bool) -> Node:
	var flight: Node = script.new()
	flight.input_enabled = false
	flight.physics_enabled = false
	flight.crash_auto_restart = false
	flight.setup(Catalog.entry(id).data)
	var config: Dictionary = Weather.spatial_defaults() if spatial else Weather.upgrade_column(Weather.defaults())
	if spatial:
		config.spatial_wind.identity.seed_u32 = 20261025
		config.spatial_wind.profile.reference_speed_mps = 3.0
		config.spatial_wind.profile.reference_from_deg = 270.0
		config.spatial_wind.turbulence.rms_mps = 0.3
		config.spatial_wind.turbulence.mode_count = 8
	else:
		config.speed_mps = 3.0
		config.from_deg = 270.0
	_check(id + " weather setup", flight.setup_weather(config))
	flight.reset()
	_check(id + " flyable", flight.is_flyable() and flight.sim.fault_reason.is_empty())
	return flight

func _counted(flight: Node) -> CountingWind:
	var wind := CountingWind.new()
	_check("counting provider preserves configuration", wind._apply_config(flight.weather_configuration()))
	flight.environment.weather = wind
	return wind

func _next(flight: Node) -> PackedFloat64Array:
	return flight._kernel_pre_step(flight.sim.aux, flight.sim.inputs, flight.sim.dt())

func _bytes(flight: Node) -> PackedByteArray:
	var bytes: PackedByteArray = flight.sim.state.to_byte_array()
	bytes.append_array(flight.sim.aux.to_byte_array())
	bytes.append_array(flight.sim.continuous.to_byte_array())
	bytes.append_array(flight.sim.modes.to_byte_array())
	bytes.append_array(flight.sim.inputs.to_byte_array())
	bytes.append_array(PackedInt64Array([flight.sim.tick]).to_byte_array())
	return bytes

func _pair(id: String, spatial: bool) -> void:
	var fast := _prepare(Flight, id, spatial)
	var legacy := _prepare(LegacyFlight, id, spatial)
	var fw := _counted(fast)
	var lw := _counted(legacy)
	var tag := "%s spatial=%s " % [id, spatial]
	var has_lag: bool = fast.downwash_index() >= 0
	_check(tag + "same initial state", _bytes(fast) == _bytes(legacy))
	# Fresh state/time/controls on each call, including zero, reverse and signed-zero body velocity.
	for speed: float in [15.0, 0.0, -15.0, -0.0, 22.0]:
		for flight: Node in [fast, legacy]:
			flight.sim.state = RB.make_state(M.v3(11.0, -9.0, -20.0), M.v3(speed, -0.0, 0.0), M.q_identity(), M.v3(0.01, -0.02, 0.03))
			flight.sim.tick = 432
			flight.sim.inputs[0] = 0.2
			flight.sim.inputs[1] = -0.1
			if flight.flaps_available():
				flight.sim.inputs[flight.flap_input_index()] = 0.6
				flight.sim.aux[flight.flap_aux_index()] = 0.3
		fw.queries = 0
		lw.queries = 0
		var a := _next(fast)
		var b := _next(legacy)
		_check(tag + "callback bytes speed=" + str(speed), a.to_byte_array() == b.to_byte_array())
		_check(tag + "one air evaluation speed=" + str(speed), fw.queries > 0 and lw.queries == 2 * fw.queries if has_lag else fw.queries == lw.queries)
	# Mutating the live model between callbacks must still be observed.
	if has_lag:
		var old_length: float = fast.aircraft.model.surfaces.horizontal.downwash_lag_length
		var before := _next(fast)
		for flight: Node in [fast, legacy]:
			flight.aircraft.model.surfaces.horizontal.downwash_lag_length = old_length * 1.3
		var changed := _next(fast)
		_check(tag + "model edit observed", changed.to_byte_array() != before.to_byte_array() and changed.to_byte_array() == _next(legacy).to_byte_array())
		for flight: Node in [fast, legacy]:
			flight.aircraft.model.surfaces.horizontal.downwash_lag_length = old_length
	if spatial and has_lag:
		# A stale air bundle could hide invalid geometry even if the lag-length check above passes.
		var station_y: float = fast.aircraft.model.envelope.station_ys[0]
		for flight: Node in [fast, legacy]:
			flight.reset() # use a committed endpoint for the kernel's invalid-model rollback guard
			_next(flight)
			flight.aircraft.model.envelope.station_ys[0] = NAN
		var a := _next(fast)
		var b := _next(legacy)
		_check(tag + "invalid station geometry refuses afresh", is_nan(a[fast.downwash_index()]) and a.to_byte_array() == b.to_byte_array())
		for flight: Node in [fast, legacy]:
			var committed := _bytes(flight)
			flight.sim.step()
			_check(tag + "invalid station geometry rolls back", not flight.sim.fault_reason.is_empty() and committed == _bytes(flight))
			flight.aircraft.model.envelope.station_ys[0] = station_y
			flight.reset()
			flight.sim.step()
			_check(tag + "restored station geometry recovers", flight.sim.fault_reason.is_empty() and flight.sim.tick == 1)
	for failure: String in (["datum", "station", "pending"] if spatial else ["datum", "pending"]):
		for flight: Node in [fast, legacy]:
			flight.reset()
			flight.environment.weather.origin = flight.sim.state.slice(RB.POS, RB.POS + 3)
			flight.environment.weather.reject = failure
			flight._weather_pending_reset = failure == "pending"
		var a := _next(fast)
		var b := _next(legacy)
		_check(tag + failure + " callback parity", a.to_byte_array() == b.to_byte_array())
		for flight: Node in [fast, legacy]:
			var committed := _bytes(flight)
			flight.sim.step()
			_check(tag + failure + " refused and rolled back", not flight.sim.fault_reason.is_empty() and committed == _bytes(flight))
			flight.environment.weather.reject = ""
			flight._weather_pending_reset = false
			flight.reset()
			flight.sim.step()
			_check(tag + failure + " recovery", flight.sim.fault_reason.is_empty() and flight.sim.tick == 1)
	# Same accepted input tape through the real kernel; no callback cache survives a tick.
	fast.reset()
	legacy.reset()
	for tick: int in 24:
		for flight: Node in [fast, legacy]:
			flight.sim.inputs[0] = 0.15 if tick < 12 else -0.15
			flight.sim.inputs[1] = -0.05
			if flight.flaps_available(): flight.sim.inputs[flight.flap_input_index()] = 0.5
			flight.sim.step()
		_check(tag + "accepted tick " + str(tick), fast.sim.fault_reason.is_empty() and legacy.sim.fault_reason.is_empty() and fast.sim.tick == tick + 1 and _bytes(fast) == _bytes(legacy))
	fast.free()
	legacy.free()

func _dispatch() -> void:
	var flight := _prepare(DispatchFlight, "jensen-das-ugly-stik-60", false)
	flight.calls.clear()
	_next(flight)
	_check("derived wake/super/air dispatch order", flight.calls == ["wake", "implicit", "explicit"])
	flight.sentinel = true
	flight.calls.clear()
	var out := _next(flight)
	_check("derived wake override without super", flight.calls == ["wake", "explicit"])
	var speed: float = flight.air_data(flight.sim.state).V
	var lag: int = flight.downwash_index()
	var expected: float = 7.0 + (flight.sim.aux[lag] - 7.0) * M.exp_(-flight.sim.dt() * speed / flight.aircraft.model.surfaces.horizontal.downwash_lag_length)
	_check("derived sentinel determines lag", PackedFloat64Array([out[lag]]).to_byte_array() == PackedFloat64Array([expected]).to_byte_array())
	flight.sentinel = false
	flight.reject_explicit = true
	flight.calls.clear()
	var committed := _bytes(flight)
	flight.sim.step()
	_check("derived second sample rejects and rolls back", not flight.sim.fault_reason.is_empty() and committed == _bytes(flight))
	_check("derived rejection preserves implicit then explicit calls", flight.calls.slice(0, 3) == ["wake", "implicit", "explicit"])
	flight.free()
