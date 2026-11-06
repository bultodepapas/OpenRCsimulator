# FUEL-12 / A6 F4: a connected trial must keep consuming until its accepted boundary.
# Reuse the existing physical fixture; the analytic test holds RPM/thermal/transport constant.
extends "res://tests/test_glow_flight_physics.gd"

func _initialize() -> void:
	_successors()
	for path: String in ["res://data/aircraft/stik_glow_55ax_2t.json", "res://data/aircraft/stik_glow_61fx_2t.json", "res://data/aircraft/stik_glow_fs64v_4t.json", "res://data/aircraft/gp_extra_300s_60.json"]:
		var loaded: Dictionary = AircraftData.load_file(path)
		_check(path + " loads", loaded.ok)
		if loaded.ok: _connected_case(loaded.model)
	print("glow connected trial: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)

func _successors() -> void:
	var smallest := PackedByteArray([1, 0, 0, 0, 0, 0, 0, 0]).decode_double(0)
	for zero: float in [0.0, -0.0]:
		_check("zero reserve advances to positive subnormal", Flight._connected_trial_fuel(zero) == smallest)
	for reserve: float in [smallest, 1.0e-30, 0.0042846, 1.0]:
		_check("positive reserve advances exactly one ULP", Flight._connected_trial_fuel(reserve) == _neighbor(reserve, 1))
	for invalid: float in [-1.0, INF, -INF, NAN, 1.7976931348623157e308]:
		_check("unrepresentable availability fails closed", is_nan(Flight._connected_trial_fuel(invalid)))

func _neighbor(value: float, direction: int) -> float:
	var bytes := PackedFloat64Array([value]).to_byte_array()
	bytes.encode_u64(0, bytes.decode_u64(0) + direction)
	return bytes.decode_double(0)

func _connected_case(model: Dictionary) -> void:
	var owner := _owner(model, 6000.0, true, 0.75)
	var body := _body(PackedFloat64Array([15.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))
	var initial: PackedFloat64Array = Flight.initial(owner, PackedFloat64Array([6000.0]), body)
	var install: Dictionary = model.propulsion.glow
	var reserve: float = install.unusable_fuel_kg
	var tag: String = str(install.profile.family)
	var state_bytes := initial.to_byte_array()
	var reference_values := initial.duplicate()
	reference_values[1] = _neighbor(reserve, 1)
	var reference: Dictionary = Flight.point(owner, body, reference_values, 0.0)
	_check(tag + " above reserve burns", reference.ok and reference.rates.fuel_kg < 0.0 and reference.source.chemical_power_w > 0.0)
	for mass: float in [reserve, _neighbor(reserve, -1), reserve - 1.0e-7, -1.0e-7]:
		var values := initial.duplicate()
		values[1] = mass
		var saved := values.to_byte_array()
		var point: Dictionary = Flight.point(owner, body, values, 0.0)
		_check(tag + " connected trial consumes at " + str(mass), point.ok and point.rates.fuel_kg == reference.rates.fuel_kg and point.source.chemical_power_w == reference.source.chemical_power_w)
		_check(tag + " trial input stays read-only", saved == values.to_byte_array() and state_bytes == initial.to_byte_array())
		var mass_context: Dictionary = Flight._stage_mass_context(owner, values)
		var physical: Dictionary = point.get("mass", mass_context.properties)
		_check(tag + " physical inventory excludes availability sentinel", point.ok and mass_context.ok and physical.mass_kg == mass_context.properties.mass_kg)
		if install.has("fuel_feed"):
			_check(tag + " wet connected feed stays available", point.ok and point.fuel_feed.factor > 0.0)
	# Source transition, explicit cut and injected owner cut must not restart burning.
	var combined := body.duplicate()
	combined.append_array(reference_values)
	var stopped: PackedFloat64Array = Flight._transition_source(combined, owner, Flight.MODE_STARVED, "fuel_exhausted", reserve)
	var stopped_point: Dictionary = Flight.point(owner, body, stopped.slice(RB.SIZE), 0.0)
	_check(tag + " accepted starved source burns no fuel", stopped_point.ok and stopped_point.rates.fuel_kg == 0.0 and stopped_point.source.chemical_power_w == 0.0)
	owner.engine_running = false
	reference_values[1] = reserve
	var cut: Dictionary = Flight.point(owner, body, reference_values, 0.0)
	_check(tag + " owner cut remains inactive", cut.ok and cut.rates.fuel_kg == 0.0 and cut.firing_fraction == 0.0)
	owner.engine_running = true
	for dt: float in [1.0 / 120.0, 1.0 / 240.0, 1.0 / 480.0]:
		_analytic_exhaustion(owner, body, initial, reference, stopped_point, dt)
	owner.free()

func _analytic_exhaustion(owner: Node, body: PackedFloat64Array, initial: PackedFloat64Array,
		running: Dictionary, stopped: Dictionary, dt: float) -> void:
	var reserve: float = owner.aircraft.model.propulsion.glow.unusable_fuel_kg
	var flow: float = -running.rates.fuel_kg
	var values := initial.duplicate()
	values[1] = reserve + flow * 0.0008
	for i: int in range(13, 17): values[i] = 0.0
	var start := body.duplicate()
	start.append_array(values)
	var expected_time: float = (values[1] - reserve) / flow
	var derivative: Callable = func(combined: PackedFloat64Array, at: float) -> PackedFloat64Array:
		var point: Dictionary = Flight.point(owner, combined.slice(0, RB.SIZE), combined.slice(RB.SIZE), at)
		if not point.ok: return PackedFloat64Array([NAN])
		var rate := PackedFloat64Array()
		rate.resize(combined.size())
		rate[RB.SIZE + 1] = point.rates.fuel_kg
		rate[RB.SIZE + 13] = point.source.shaft_torque_nm
		rate[RB.SIZE + 14] = point.propeller.thrust_n
		rate[RB.SIZE + 16] = point.source.chemical_power_w
		return rate
	# These three diagnostic integral slots hold torque impulse, thrust impulse and chemical work.
	var result: Variant = Flight.step(start, 0.0, dt, derivative, PackedFloat64Array(), owner)
	var ok: bool = result is Dictionary and result.has("state")
	_check("constant-flow step accepted dt=" + str(dt), ok)
	if not ok: return
	var crossing := NAN
	for event: Dictionary in result.events:
		if event.type == "fuel_exhausted": crossing = event.time_s
	_near("constant-flow analytic exhaustion time", crossing, expected_time, 2.0e-11)
	var end: PackedFloat64Array = result.state
	_near("constant-flow chemical work", end[RB.SIZE + 16], running.source.chemical_power_w * expected_time, 1.0e-7)
	_near("constant-flow torque impulse", end[RB.SIZE + 13], running.source.shaft_torque_nm * expected_time + stopped.source.shaft_torque_nm * (dt - expected_time), 1.0e-10)
	_near("constant-flow thrust impulse", end[RB.SIZE + 14], running.propeller.thrust_n * dt, 1.0e-10)
	_check("event commits exact residue and stopped source", end[RB.SIZE + 1] == reserve and end[RB.SIZE + Flight.SOURCE_MODE_INDEX] == Flight.MODE_STARVED and end[RB.SIZE + 7] == 0.0)
