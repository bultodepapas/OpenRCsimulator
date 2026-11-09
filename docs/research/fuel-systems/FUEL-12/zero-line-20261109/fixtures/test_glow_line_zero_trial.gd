## Exact-zero feed-line stage is the connected left limit until the event commits.
extends "res://tests/test_glow_counter_edges.gd"

class CutOwner extends FlightOwner:
	func failure_power_cut_active() -> bool:
		return true

func _initialize() -> void:
	var loaded: Dictionary = AircraftData.load_file("res://data/aircraft/stik_glow_55ax_2t.json")
	_check("synthetic fixture source loads", loaded.ok)
	if loaded.ok:
		for with_feed: bool in [false, true]:
			for prepared: bool in [false, true]:
				_check_boundary(loaded.model, with_feed, prepared)
		_analytic_event(loaded.model)
	print("Glow zero line trial: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

func _check_boundary(source: Dictionary, with_feed: bool, prepared: bool) -> void:
	var model: Dictionary = _line_model(source, 0.25, with_feed, true)
	var owner: FlightOwner = _owner(model, 6000.0, true, 0.75)
	owner.start_fuel_override_kg = 0.25
	var body := _body(PackedFloat64Array([15.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))
	var values: PackedFloat64Array = Flight.initial(owner, PackedFloat64Array([6000.0]), body)
	if not prepared: owner.set_meta(Flight.EVALUATOR_IDENTITY_META, {})
	for mode: int in [Flight.MODE_MAIN_TANK, Flight.MODE_FEED_LINE]:
		values[Flight.SOURCE_MODE_INDEX] = float(mode)
		values[1] = -1e-12
		values[Flight.LINE_FUEL_INDEX] = -1e-12 if mode == Flight.MODE_FEED_LINE else 0.0
		var negative: Dictionary = Flight.point(owner, body, values, 0.0)
		values[1] = 0.0
		values[Flight.LINE_FUEL_INDEX] = 0.0
		var saved: PackedByteArray = values.to_byte_array()
		var boundary: Dictionary = Flight.point(owner, body, values, 0.0)
		var label := "feed=%s prepared=%s mode=%d" % [with_feed, prepared, mode]
		_check(label + " zero fuel has connected negative-trial source", boundary.get("ok", false) and negative.get("ok", false)
			and negative.rates.fuel_kg < 0.0 and boundary.rates.fuel_kg == negative.rates.fuel_kg
			and boundary.source.chemical_power_w == negative.source.chemical_power_w,
			"zero=%s negative=%s" % [str(boundary.get("rates", {})), str(negative.get("rates", {}))])
		_check(label + " trial does not alter input", values.to_byte_array() == saved)
		var actual: Dictionary = Flight.evaluate(body, values, 0.0, owner)
		_check(label + " RK derivative uses same connected source", not actual.is_empty()
			and actual.derivative[1] == negative.rates.fuel_kg
			and (mode != Flight.MODE_FEED_LINE or actual.derivative[Flight.LINE_FUEL_INDEX] == negative.rates.fuel_kg)
			and actual.derivative[16] == negative.source.chemical_power_w)
		var mass: Dictionary = Flight._stage_mass_context(owner, values)
		_check(label + " physical inventory stays empty", mass.ok and mass.total_fuel_kg == 0.0
			and mass.line_fuel_kg == 0.0 and mass.main_fuel_kg == 0.0)
		var negative_zero: float = PackedByteArray([0, 0, 0, 0, 0, 0, 0, 128]).decode_double(0)
		values[1] = negative_zero
		values[Flight.LINE_FUEL_INDEX] = negative_zero
		var signed_zero: Dictionary = Flight.point(owner, body, values, 0.0)
		_check(label + " negative zero has the same connected rate", signed_zero.get("ok", false)
			and signed_zero.rates.fuel_kg == negative.rates.fuel_kg)
		values[1] = 0.0
		values[Flight.LINE_FUEL_INDEX] = 0.0
		owner.engine_running = false
		var cut: Dictionary = Flight.point(owner, body, values, 0.0)
		_check(label + " owner cut stays inactive", cut.get("ok", false) and cut.rates.fuel_kg == 0.0
			and cut.source.chemical_power_w == 0.0)
		owner.engine_running = true
		values[7] = 0.0
		var stopped: Dictionary = Flight.point(owner, body, values, 0.0)
		_check(label + " stopped source stays inactive", stopped.get("ok", false) and stopped.rates.fuel_kg == 0.0
			and stopped.source.chemical_power_w == 0.0)
		values[7] = 1.0
		var injected := CutOwner.new()
		injected.aircraft = owner.aircraft
		injected.sim = owner.sim
		injected.engine_running = true
		for key: StringName in owner.get_meta_list():
			injected.set_meta(key, owner.get_meta(key))
		var cut_fault: Dictionary = Flight.point(injected, body, values, 0.0)
		_check(label + " injected power cut stays inactive", cut_fault.get("ok", false)
			and cut_fault.rates.fuel_kg == 0.0 and cut_fault.source.chemical_power_w == 0.0)
		injected.free()
	values[7] = 0.0
	values[Flight.SOURCE_MODE_INDEX] = float(Flight.MODE_STARVED)
	var starved: Dictionary = Flight.point(owner, body, values, 0.0)
	_check("committed starved state stays inactive", starved.get("ok", false)
		and starved.rates.fuel_kg == 0.0 and starved.source.chemical_power_w == 0.0)
	owner.free()

func _analytic_event(source: Dictionary) -> void:
	var model: Dictionary = _line_model(source, 0.25, false, true)
	var owner: FlightOwner = _owner(model, 6000.0, true, 0.75)
	owner.start_fuel_override_kg = 0.25
	var body := _body(PackedFloat64Array([15.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))
	var values: PackedFloat64Array = Flight.initial(owner, PackedFloat64Array([6000.0]), body)
	values[Flight.SOURCE_MODE_INDEX] = float(Flight.MODE_FEED_LINE)
	values[1] = 1e-9
	values[Flight.LINE_FUEL_INDEX] = values[1]
	var running: Dictionary = Flight.point(owner, body, values, 0.0)
	var flow: float = -running.rates.fuel_kg
	for hz: int in [240, 480, 960]:
		var dt: float = 1.0 / float(hz)
		values[1] = (dt / 2.0) * flow
		values[Flight.LINE_FUEL_INDEX] = values[1]
		for index: int in range(13, 17): values[index] = 0.0
		var combined := body.duplicate()
		combined.append_array(values)
		var zero_stages: Array[int] = [0]
		var derivative: Callable = func(state: PackedFloat64Array, at: float) -> PackedFloat64Array:
			if state[RB.SIZE + 1] == 0.0 and int(state[RB.SIZE + Flight.SOURCE_MODE_INDEX]) == Flight.MODE_FEED_LINE:
				zero_stages[0] += 1
			var p: Dictionary = Flight.point(owner, state.slice(0, RB.SIZE), state.slice(RB.SIZE), at)
			if not p.get("ok", false): return PackedFloat64Array([NAN])
			var out := PackedFloat64Array()
			out.resize(state.size())
			out[RB.SIZE + 1] = p.rates.fuel_kg
			out[RB.SIZE + Flight.LINE_FUEL_INDEX] = p.rates.fuel_kg
			out[RB.SIZE + 13] = p.source.shaft_torque_nm
			out[RB.SIZE + 16] = p.source.chemical_power_w
			return out
		var saved := combined.to_byte_array()
		var result: Variant = Flight.step(combined, 0.0, dt, derivative, PackedFloat64Array(), owner)
		_check("%d Hz connected depletion accepts with an exact-zero RK trial" % hz,
			result is Dictionary and zero_stages[0] > 0 and combined.to_byte_array() == saved, str(result))
		if result is Dictionary:
			var event_time := NAN
			var types: Array = []
			for event: Dictionary in result.events:
				types.append(str(event.type))
				if event.type == "fuel_exhausted": event_time = float(event.time_s)
			_near("%d Hz constant flow analytic depletion time" % hz, event_time, values[1] / flow, 2e-11)
			_near("%d Hz pre-boundary chemical work" % hz, result.state[RB.SIZE + 16], running.source.chemical_power_w * event_time, 1e-7)
			_check("%d Hz depletion commits line empty then stop" % hz,
				types == ["fuel_exhausted", "glow_stopped"] and result.state[RB.SIZE + 1] == 0.0
				and result.state[RB.SIZE + Flight.LINE_FUEL_INDEX] == 0.0
				and result.state[RB.SIZE + Flight.SOURCE_MODE_INDEX] == float(Flight.MODE_STARVED), str(types))
	owner.free()
