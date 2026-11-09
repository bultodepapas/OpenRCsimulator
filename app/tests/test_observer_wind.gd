# WOPT-02: production overlay observation, provider order/counts, and refusal parity.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Config := preload("res://physics/wind_config.gd")
const Flow := preload("res://physics/wind_aircraft_flow.gd")
const Manager := preload("res://render/overlays/overlay_manager.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")


# Independent oracle for the pre-change overlay's wind_at -> air_data sequence.
class BaselineFlight extends "res://sim/flight_session.gd":
	func observer_air_and_wind(s: PackedFloat64Array, time_s: float) -> Dictionary:
		var wind: PackedFloat64Array = wind_at(time_s)
		return {wind = wind, air = air_data(s, time_s)}


class OverrideFlight extends "res://sim/flight_session.gd":
	var calls: Array[String] = []
	func wind_at(_time_s: float, _s: PackedFloat64Array = PackedFloat64Array()) -> PackedFloat64Array:
		calls.append("wind")
		return PackedFloat64Array([4.0, -3.0, 2.0])
	func air_data(s: PackedFloat64Array, time_s: float = NAN) -> Dictionary:
		calls.append("air")
		var result := super.air_data(s, time_s)
		result.V = 42.0
		return result


class CountedField extends "res://physics/wind_field.gd":
	var trace: Array = []
	var reject_position := PackedFloat64Array()
	func sample_world(position: PackedFloat64Array, time_s: float) -> PackedFloat64Array:
		trace.append([position.duplicate(), time_s])
		if not reject_position.is_empty() and position.to_byte_array() == reject_position.to_byte_array():
			return PackedFloat64Array([NAN, NAN, NAN])
		return super.sample_world(position, time_s)


# A Node adapter with the original observer interface and no new accessor.
class LegacyFacade extends Node:
	var flight: Node
	var calls: Array[String] = []
	var aircraft: Dictionary
	var sim: Node
	var ground_surfaces: PackedFloat64Array
	var radio: RefCounted
	var pause_reason: String
	var trims: Dictionary
	var _controller_lost := false
	func _init(source: Node) -> void:
		flight = source
		aircraft = source.aircraft
		sim = source.sim
		ground_surfaces = source.ground_surfaces
		radio = source.radio
		pause_reason = source.pause_reason
		trims = source.trims
	func wind_at(time_s: float) -> PackedFloat64Array:
		calls.append("wind")
		return flight.wind_at(time_s)
	func air_data(s: PackedFloat64Array, time_s: float) -> Dictionary:
		calls.append("air")
		return flight.air_data(s, time_s)
	func mass_properties() -> Dictionary:
		return flight.mass_properties()
	func battery_is_dynamic() -> bool:
		return flight.battery_is_dynamic()
	func electrical_state() -> Dictionary:
		return flight.electrical_state()
	func rate_profile_label() -> String:
		return flight.rate_profile_label()


var checks := 0
var failures := 0


func _check(label: String, passed: bool, detail := "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("en")
	for modes: int in [8, 24, 64]:
		_spatial_case("jensen-das-ugly-stik-60", modes, modes == 24)
	_spatial_case("moonrunner-x99", 24, true)
	_legacy_and_pending()
	_dispatch()
	_adapter_and_unprepared()
	print("observer wind: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _spatial_config(modes: int) -> Dictionary:
	var config: Dictionary = Config.spatial_defaults()
	config.spatial_wind.identity.seed_u32 = 20261025
	config.spatial_wind.profile.reference_speed_mps = 3.0
	config.spatial_wind.profile.reference_from_deg = 270.0
	config.spatial_wind.profile.free_air_wind_ned_mps = [1.0, 3.5, 0.0]
	config.spatial_wind.turbulence.rms_mps = 0.3
	config.spatial_wind.turbulence.mode_count = modes
	return config


func _prepare(script: Script, id: String, config: Dictionary, reset := true) -> Node:
	var session: Node = script.new()
	session.input_enabled = false
	session.physics_enabled = false
	session.setup(Catalog.entry(id).data)
	root.add_child(session)
	_check(id + " initial setup", session.aircraft.get("ok", false))
	_check(id + " weather accepted", session.setup_weather(config), session.weather_error)
	if reset:
		session.reset()
		_check(id + " reset flyable", session.is_flyable(), session.start_error)
	return session


func _counted(session: Node) -> CountedField:
	var field := CountedField.new()
	_check("counted provider installs the real weather", field._apply_config(session.weather_configuration()))
	session.environment.weather = field
	return field


func _state(north := 11.0, east := -9.0) -> PackedFloat64Array:
	return RB.make_state(M.v3(north, east, -30.0), M.v3(17.0, -0.4, 1.1),
		M.q_from_euler(0.3, -0.1, 0.2), M.v3(0.01, -0.02, 0.03))


func _snapshot(session: Node) -> Dictionary:
	return Manager.snapshot(session, {north = 2.0, east = -3.0, down = 0.0, eye_height = 1.7}, 1.5, false, 17.0)


func _same(a: Variant, b: Variant) -> bool:
	return var_to_bytes(a) == var_to_bytes(b)


func _diff(a: Dictionary, b: Dictionary) -> String:
	var differences: Array[String] = []
	for key: Variant in a:
		if not b.has(key) or not _same(a[key], b[key]):
			differences.append(str(key))
	return "; ".join(differences)


func _air_same(a: Dictionary, b: Dictionary) -> bool:
	var keys := ["v_air", "V", "alpha", "beta", "qbar", "spatial_air_law", "spatial_aero_law",
		"spatial_state", "spatial_time_s", "spatial_rho", "aero_station_delta_body",
		"propulsion_air_body", "wake_source_delta_body"]
	for key: String in keys:
		if a.has(key) != b.has(key) or (a.has(key) and not _same(a[key], b[key])):
			return false
	return true


func _spatial_case(id: String, modes: int, more: bool) -> void:
	var config := _spatial_config(modes)
	var fast := _prepare(Flight, id, config)
	var old := _prepare(BaselineFlight, id, config)
	# Both sessions otherwise receive independently generated controller profile IDs.
	old.radio.profile = fast.radio.profile.duplicate(true)
	var fw := _counted(fast)
	var ow := _counted(old)
	var label := "%s modes=%d" % [id, modes]
	for tick: int in [0, 147, 777]:
		for session: Node in [fast, old]:
			session.sim.state = _state(11.0 + tick * 0.01, -9.0 - tick * 0.02)
			session.sim.tick = tick
		fw.trace.clear()
		ow.trace.clear()
		var before: PackedByteArray = var_to_bytes(fast.sim.checkpoint())
		var actual := _snapshot(fast)
		var expected := _snapshot(old)
		var context := "%s tick=%d" % [label, tick]
		_check(context + " entire production overlay equals baseline", _same(actual, expected), _diff(actual, expected))
		_check(context + " removes one datum provider call", fw.trace.size() > 1 and ow.trace.size() == fw.trace.size() + 1,
			"fast=%d baseline=%d" % [fw.trace.size(), ow.trace.size()])
		_check(context + " preserves all remaining station order and time", ow.trace.slice(1) == fw.trace
			and ow.trace[0] == fw.trace[0])
		_check(context + " observation leaves simulation checkpoint unchanged", before == var_to_bytes(fast.sim.checkpoint()))
		print("%s tick=%d overlay provider calls baseline=%d candidate=%d" % [label, tick, ow.trace.size(), fw.trace.size()])
	if more:
		_check_receipt_and_ownership(fast, old, fw, ow, label)
		_check_refusals(fast, old, fw, ow, label)
	fast.free()
	old.free()


func _check_receipt_and_ownership(fast: Node, old: Node, fw: CountedField, ow: CountedField, label: String) -> void:
	var time_s: float = fast.sim.time()
	var observed: Dictionary = fast.observer_air_and_wind(fast.sim.state, time_s)
	var reference: Dictionary = old.observer_air_and_wind(old.sim.state, time_s)
	_check(label + " receipt wind and numeric air fields match", _same(observed.wind, reference.wind)
		and _air_same(observed.air, reference.air))
	var receipt_ok: bool = observed.air.has("spatial_sampler") and Flow.matches_stage(observed.air, fast.sim.state, fast.air_density(fast.sim.state))
	_check(label + " complete spatial receipt still validates", receipt_ok)
	if not receipt_ok:
		return
	var original: PackedByteArray = observed.wind.to_byte_array()
	var wind_copy: PackedFloat64Array = observed.wind
	wind_copy[0] += 123.0
	_check(label + " returned wind does not change stage sampler", observed.air.spatial_sampler.reference_wind.to_byte_array() == original)
	var changed_wind: PackedByteArray = observed.wind.to_byte_array()
	observed.air.spatial_sampler.reference_wind = PackedFloat64Array([90.0, 91.0, 92.0])
	_check(label + " sampler mutation does not change returned wind", observed.wind.to_byte_array() == changed_wind)
	var again: Dictionary = fast.observer_air_and_wind(fast.sim.state, time_s)
	_check(label + " prior receipt mutation does not affect next observation", again.wind.to_byte_array() == original)
	fw.trace.clear()
	var repeated := _snapshot(fast)
	var first_count := fw.trace.size()
	var repeated_again := _snapshot(fast)
	_check(label + " repeated observation samples afresh", _same(repeated, repeated_again)
		and first_count > 0 and fw.trace.size() == 2 * first_count)
	# Non-endpoint calls retain the previous wind_at(endpoint) then air_data(explicit state/time) behavior.
	var other: PackedFloat64Array = fast.sim.state.duplicate()
	other[RB.POS] += 8.0
	for query: Array in [["state", other, time_s], ["time", fast.sim.state, time_s + 0.25],
			["both", other, time_s + 0.25]]:
		fw.trace.clear()
		ow.trace.clear()
		var a: Dictionary = fast.observer_air_and_wind(query[1], query[2])
		var b: Dictionary = old.observer_air_and_wind(query[1], query[2])
		_check(label + " non-endpoint " + query[0] + " retains original result and sequence", _same(a.wind, b.wind)
			and _air_same(a.air, b.air) and fw.trace == ow.trace)
	var positive_zero: PackedFloat64Array = fast.sim.state.duplicate()
	positive_zero[RB.VEL + 1] = 0.0
	fast.sim.state = positive_zero
	old.sim.state = positive_zero.duplicate()
	# Construct the binary64 sign bit explicitly; the parser can fold the -0.0 literal to +0.0.
	var signed_bytes: PackedByteArray = positive_zero.to_byte_array()
	signed_bytes[(RB.VEL + 1) * 8 + 7] = 0x80
	var negative_zero: PackedFloat64Array = signed_bytes.to_float64_array()
	fw.trace.clear()
	ow.trace.clear()
	var signed_a: Dictionary = fast.observer_air_and_wind(negative_zero, time_s)
	var signed_b: Dictionary = old.observer_air_and_wind(negative_zero, time_s)
	_check(label + " signed-zero state difference keeps original sequence", negative_zero.to_byte_array() != positive_zero.to_byte_array()
		and _same(signed_a.wind, signed_b.wind) and _air_same(signed_a.air, signed_b.air) and fw.trace == ow.trace,
		"different=%s wind=%s air=%s trace=%s fast=%d old=%d" % [str(negative_zero.to_byte_array() != positive_zero.to_byte_array()),
		str(_same(signed_a.wind, signed_b.wind)), str(_air_same(signed_a.air, signed_b.air)), str(fw.trace == ow.trace), fw.trace.size(), ow.trace.size()])
	fast.sim.tick = 0
	old.sim.tick = 0
	var negative_time_bytes := PackedFloat64Array([0.0]).to_byte_array()
	negative_time_bytes[7] = 0x80
	var negative_time: float = negative_time_bytes.to_float64_array()[0]
	fw.trace.clear()
	ow.trace.clear()
	var time_a: Dictionary = fast.observer_air_and_wind(fast.sim.state, negative_time)
	var time_b: Dictionary = old.observer_air_and_wind(old.sim.state, negative_time)
	_check(label + " signed-zero time difference keeps original sequence", PackedFloat64Array([negative_time]).to_byte_array() != PackedFloat64Array([fast.sim.time()]).to_byte_array()
		and _same(time_a.wind, time_b.wind) and _air_same(time_a.air, time_b.air) and fw.trace == ow.trace)
	# No observation may survive a new state, time or provider.
	fast.sim.state = _state(37.0, 18.0)
	old.sim.state = fast.sim.state.duplicate()
	fast.sim.tick += 99
	old.sim.tick = fast.sim.tick
	fw.trace.clear()
	ow.trace.clear()
	_check(label + " changed state/time snapshot matches baseline", _same(_snapshot(fast), _snapshot(old)))
	_check(label + " changed state/time samples the provider afresh", not fw.trace.is_empty()
		and ow.trace.size() == fw.trace.size() + 1 and fw.trace[0][0] == fast.sim.state.slice(0, 3)
		and fw.trace[0][1] == fast.sim.time())
	var previous := _snapshot(fast)
	var replacement: Dictionary = fast.weather_configuration()
	replacement.spatial_wind.profile.reference_speed_mps = 5.0
	replacement.spatial_wind.profile.reference_from_deg = 180.0
	var checked: Dictionary = Config.validate(replacement)
	_check(label + " replacement weather validates", checked.ok)
	var new_fw := CountedField.new()
	var new_ow := CountedField.new()
	_check(label + " replacement providers install", new_fw._apply_config(checked.config) and new_ow._apply_config(checked.config))
	fast.environment.weather = new_fw
	old.environment.weather = new_ow
	var new_snap := _snapshot(fast)
	_check(label + " replaced provider is queried afresh", _same(new_snap, _snapshot(old))
		and not _same(previous.telemetry.wind_speed, new_snap.telemetry.wind_speed)
		and not new_fw.trace.is_empty() and new_ow.trace.size() == new_fw.trace.size() + 1)
	# Return installed providers to the refusal fixture.
	fast.environment.weather = fw
	old.environment.weather = ow


func _check_refusals(fast: Node, old: Node, fw: CountedField, ow: CountedField, label: String) -> void:
	fw.trace.clear()
	_snapshot(fast)
	var origin: PackedFloat64Array = fast.sim.state.slice(0, 3)
	var first_station: PackedFloat64Array = fw.trace[1][0]
	var last_station: PackedFloat64Array = fw.trace.back()[0]
	_check(label + " first and last physical stations differ from datum", first_station != origin and last_station != origin)
	for entry: Array in [["datum", origin], ["first station", first_station], ["last station", last_station]]:
		fw.reject_position = entry[1]
		ow.reject_position = entry[1]
		fw.trace.clear()
		ow.trace.clear()
		var a := _snapshot(fast)
		var b := _snapshot(old)
		var prefix: String = label + " " + entry[0]
		_check(prefix + " refusal reaches actual overlay identically", _same(a, b))
		_check(prefix + " refusal retains every provider call", fw.trace.size() == ow.trace.size()
			and fw.trace.slice(0, fw.trace.size() - 1) == ow.trace.slice(1)
			and fw.trace.back() == ow.trace[0])
		if entry[0] != "datum":
			_check(prefix + " retains finite datum wind with invalid air", is_finite(float(a.telemetry.wind_speed))
				and is_nan(float(a.telemetry.airspeed)))
		else:
			_check(prefix + " reports invalid air and wind", is_nan(float(a.telemetry.airspeed))
				and is_nan(float(a.telemetry.wind_speed)))
		print("%s %s refusal overlay provider calls baseline=%d candidate=%d" % [label, entry[0], ow.trace.size(), fw.trace.size()])
	fw.reject_position = PackedFloat64Array()
	ow.reject_position = PackedFloat64Array()
	var first_y: float = fast.aircraft.model.envelope.station_ys[0]
	for session: Node in [fast, old]: session.aircraft.model.envelope.station_ys[0] = NAN
	fw.trace.clear()
	ow.trace.clear()
	var bad := _snapshot(fast)
	var prior := _snapshot(old)
	_check(label + " invalid geometry still validates before station queries", _same(bad, prior)
		and fw.trace.size() == 1 and ow.trace.size() == 1 and is_nan(float(bad.telemetry.airspeed))
		and is_finite(float(bad.telemetry.wind_speed)))
	for session: Node in [fast, old]: session.aircraft.model.envelope.station_ys[0] = first_y


func _legacy_and_pending() -> void:
	var id := "jensen-das-ugly-stik-60"
	var fast := _prepare(Flight, id, Config.preset("turbulent"))
	var old := _prepare(BaselineFlight, id, Config.preset("turbulent"))
	old.radio.profile = fast.radio.profile.duplicate(true)
	var fw := _counted(fast)
	var ow := _counted(old)
	fw.trace.clear()
	ow.trace.clear()
	_check("legacy OU overlay and provider sequence remain unchanged", _same(_snapshot(fast), _snapshot(old))
		and fw.trace == ow.trace and fw.trace.size() == 2)
	fast.free()
	old.free()
	fast = _prepare(Flight, id, _spatial_config(8), false)
	old = _prepare(BaselineFlight, id, _spatial_config(8), false)
	old.radio.profile = fast.radio.profile.duplicate(true)
	fw = _counted(fast)
	ow = _counted(old)
	fw.trace.clear()
	ow.trace.clear()
	var a := _snapshot(fast)
	var b := _snapshot(old)
	_check("actual pending reset reports the same invalid air and wind without querying provider", fast._weather_pending_reset
		and old._weather_pending_reset and _same(a, b) and is_nan(float(a.telemetry.airspeed))
		and is_nan(float(a.telemetry.wind_speed)) and fw.trace.is_empty() and ow.trace.is_empty())
	fast.free()
	old.free()


func _dispatch() -> void:
	var session := _prepare(OverrideFlight, "jensen-das-ugly-stik-60", _spatial_config(8))
	session.calls.clear()
	var observed := _snapshot(session)
	_check("derived overrides retain wind then air dispatch", session.calls == ["wind", "air"], str(session.calls))
	_check("actual overlay receives derived wind and air values", float(observed.telemetry.wind_speed) == 5.0
		and float(observed.telemetry.wind_up) == -2.0 and float(observed.telemetry.airspeed) == 42.0)
	session.free()


func _adapter_and_unprepared() -> void:
	var unprepared := Flight.new()
	_check("unprepared flight is refused before any observation", _snapshot(unprepared).is_empty())
	unprepared.free()
	var session := _prepare(Flight, "jensen-das-ugly-stik-60", _spatial_config(8))
	var facade := LegacyFacade.new(session)
	var expected := _snapshot(session)
	var observed := _snapshot(facade)
	_check("legacy Node adapter retains wind then air order", not facade.has_method("observer_air_and_wind")
		and facade.calls == ["wind", "air"])
	_check("legacy Node adapter produces the same overlay", _same(observed, expected), _diff(observed, expected))
	facade.free()
	session.free()
