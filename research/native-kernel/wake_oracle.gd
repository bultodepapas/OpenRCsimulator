## NK-3 wake component oracle; this does not qualify native flight integration.
## Actual catalog tail installations and existing manufactured, validated legacy,
## smooth, swirl and transport fixtures are compared against current GDScript.
extends "oracle.gd"

const Slipstream := preload("res://physics/slipstream.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const WashTransport := preload("res://physics/wash_transport.gd")
const LegacyFixture := preload("res://tests/test_slipstream_downwash.gd")
const SmoothFixture := preload("res://tests/test_wash_profile.gd")
const TransportFixture := preload("res://tests/test_wash_transport.gd")


func _source_hashes() -> Dictionary:
	var out: Dictionary = super._source_hashes()
	for path: String in ["res://physics/slipstream.gd", "res://physics/swirl_loads.gd",
			"res://physics/wash_transport.gd", "res://tests/test_slipstream_downwash.gd",
			"res://tests/test_wash_profile.gd", "res://tests/test_wash_transport.gd",
			"res://tests/fixtures/stik_wash_profile.json"]:
		out[path] = FileAccess.get_sha256(path)
	return out


func _checks() -> void:
	_report.format = "openrc-nk3-wake-oracle v1"
	if not _native.has_method("prepare_wake") or not _native.has_method("wake_component"):
		_failures.append("native wake component methods are missing")
		return
	if _states <= 0:
		_failures.append("wake states must be positive")
		return
	var cases: Array[Dictionary] = []
	for id: String in ["gp-extra-300s-60", "p51d-mustang-120", "f4u-corsair-250"]:
		var loaded: Dictionary = AircraftData.load_file(Catalog.data_for(id))
		if not loaded.ok or not loaded.model.propulsion.has("slipstream"):
			_failures.append("catalog wake data failed: " + id)
		else:
			cases.append({name = id, model = loaded.model})
	var raw_cases: Array[Dictionary] = [
		{name = "manufactured_legacy", raw = LegacyFixture.combined_raw()},
		{name = "manufactured_smooth", raw = SmoothFixture.combined_raw()},
		{name = "manufactured_transport", raw = TransportFixture.raw_fixture()},
	]
	var swirl: Dictionary = SmoothFixture.combined_raw()
	swirl.propulsion.propeller.slipstream.swirl_factor.value = 0.4
	raw_cases.append({name = "manufactured_smooth_swirl", raw = swirl})
	for fixture: Dictionary in raw_cases:
		var loaded: Dictionary = AircraftData.validate_and_derive(fixture.raw)
		if not loaded.ok:
			_failures.append("wake fixture %s failed: %s" % [fixture.name, str(loaded.errors)])
		else:
			cases.append({name = fixture.name, model = loaded.model})
	for case: Dictionary in cases:
		_check_case(case)


func _prop_geometry(prop: Dictionary) -> Dictionary:
	var out := {}
	for key: String in ["diameter", "offset", "ct", "cp", "rotor_inertia", "cp_min", "axis", "normal_force", "pfactor_moment"]:
		if prop.has(key):
			out[key] = prop[key]
	return out


func _check_case(case: Dictionary) -> void:
	var model: Dictionary = case.model
	var prop: Dictionary = model.propulsion
	var ss: Dictionary = prop.slipstream
	var label := str(case.name)
	var aero_prepared: Dictionary = _native.prepare_aero(model)
	var prop_prepared: Dictionary = _native.prepare_propeller(_prop_geometry(prop))
	if not aero_prepared.ok or not prop_prepared.ok:
		_failures.append("%s aero/prop prepare failed: %s / %s" % [label, aero_prepared.error, prop_prepared.error])
		return
	var prepared: Dictionary = _native.prepare_wake(ss)
	if not prepared.ok:
		_failures.append("%s wake prepare failed: %s" % [label, prepared.error])
		return
	var group := "wake_" + label
	for i in _states:
		var body := PackedFloat64Array([_rng.randf_range(-100.0, 100.0), _rng.randf_range(-100.0, 100.0),
			-_rng.randf_range(1.0, 100.0), _rng.randf_range(-15.0, 40.0), _rng.randf_range(-5.0, 5.0),
			_rng.randf_range(-8.0, 8.0), 1.0, 0.0, 0.0, 0.0,
			_rng.randf_range(-2.0, 2.0), _rng.randf_range(-2.0, 2.0), _rng.randf_range(-2.0, 2.0)])
		if i % 17 == 0:
			body[3] = 0.0
			body[4] = 0.0
			body[5] = 0.0
		var attitude: PackedFloat64Array = _random_unit_quaternion()
		for axis in 4:
			body[6 + axis] = attitude[axis]
		var wind := PackedFloat64Array([_rng.randf_range(-3.0, 3.0), _rng.randf_range(-3.0, 3.0), _rng.randf_range(-1.0, 1.0)])
		var rho := _rng.randf_range(0.9, 1.3)
		var air: Dictionary = Air.compute(body, wind, rho)
		var source_delta := PackedFloat64Array()
		if i % 3 == 0:
			source_delta = PackedFloat64Array([_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)])
			air.wake_source_delta_body = source_delta
		var source: PackedFloat64Array = Slipstream.source_air(air)
		var d := {elevator = _rng.randf_range(-0.35, 0.35), aileron_right = _rng.randf_range(-0.25, 0.25),
			aileron_left = _rng.randf_range(-0.25, 0.25), rudder = _rng.randf_range(-0.35, 0.35), flap = 0.0}
		if model.get("capabilities", {}).get("flaps", "") == "simulated":
			d.flap = _rng.randf_range(0.0, deg_to_rad(float(model.flaps.max_angle_deg)))
		var packed_d := _deflection_array(d)
		var downwash: float = NAN if i % 2 == 0 else _rng.randf_range(-5.0, 30.0)
		var rpm: float = _rng.randf_range(300.0, maxf(float(prop.max_rpm), 400.0))
		if i % 11 == 0:
			rpm = 0.0
		elif i % 19 == 0:
			rpm = 1.0
		var tq := PackedFloat64Array([_rng.randf_range(-10.0, 120.0), _rng.randf_range(-1.0, 3.0)])
		var lagged := PackedFloat64Array()
		if WashTransport.enabled(prop):
			for _piece: Variant in ss.pieces:
				lagged.append(_rng.randf_range(-1.0, 10.0))
		var arguments := [label, i, body, wind, rho, packed_d, rpm, tq, downwash, lagged, source_delta]
		var reference: PackedFloat64Array = Slipstream.stage_loads(body, air, d, model, rpm, rho, downwash, lagged, 1, tq)
		var native: PackedFloat64Array = _native.wake_component(0, body, wind, rho, packed_d, rpm, tq, downwash, lagged, source_delta)
		_compare("wake_loads", reference, native, arguments)
		var w: Dictionary = Slipstream.wake(source, tq[0], tq[1], prop, rho)
		_compare("wake_state", PackedFloat64Array([w.u, w.w, w.vs, w.dv, w.rs, w.swirl, w.core]),
			_native.wake_component(1, body, wind, rho, packed_d, rpm, tq, downwash, lagged, source_delta), arguments)
		if ss.has("edge_fraction"):
			_compare("wake_reverse_weight", PackedFloat64Array([Slipstream.reverse_weight(source, rpm, prop)]),
				_native.wake_component(4, body, wind, rho, packed_d, rpm, tq, downwash, lagged, source_delta), arguments)
		if WashTransport.enabled(prop):
			var transport_tq: PackedFloat64Array = Propulsion.thrust_torque(source, rpm, prop, rho).slice(0, 2)
			_compare("wash_target", WashTransport.target(source, rpm, prop, rho),
				_native.wake_component(2, body, wind, rho, packed_d, rpm, transport_tq, downwash, lagged, source_delta), arguments)
			_compare("wash_derivative", WashTransport.derivative(source, rpm, prop, rho, lagged),
				_native.wake_component(3, body, wind, rho, packed_d, rpm, transport_tq, downwash, lagged, source_delta), arguments)
		_tally(group, "states")
		if rpm < 1.0: _tally(group, "stopped")
		if source[0] < 0.0: _tally(group, "reverse_flow")
		if not source_delta.is_empty(): _tally(group, "hub_delta")
		if not is_nan(downwash): _tally(group, "held_wake")
		if not lagged.is_empty(): _tally(group, "transport")
		if reference != PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]): _tally(group, "nonzero_load")
	var invalid: Dictionary = ss.duplicate(true)
	invalid.unsupported_future_law = 1.0
	if _native.prepare_wake(invalid).ok:
		_failures.append(label + " accepted unknown wake law")
	if not _native.wake_component(0,
			PackedFloat64Array([0.0, 0.0, -10.0, 10.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
			PackedFloat64Array([0.0, 0.0, 0.0]), 1.225, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]), 5000.0,
			PackedFloat64Array([1.0, 0.1]), NAN, PackedFloat64Array(), PackedFloat64Array()).is_empty():
		_failures.append(label + " retained usable wake after failed prepare")
