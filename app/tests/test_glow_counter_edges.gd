## A4 edge regressions: source transitions, fractional carry and atomic failure.
extends "res://tests/test_glow_flight_physics.gd"

const Life := preload("res://physics/glow/lifecycle.gd")
const Sim := preload("res://sim/simulation.gd")
const Vehicle := preload("res://sim/vehicle_model.gd")


class TimedOwner extends FlightOwner:
	var bad_time: float = NAN
	var rejected_samples: int = 0

	func air_data(body: PackedFloat64Array, at: float) -> Dictionary:
		if is_finite(bad_time) and absf(at - bad_time) < 1.0e-9:
			rejected_samples += 1
			return {}
		return super.air_data(body, at)


func _initialize() -> void:
	call_deferred("_run_edges")


func _run_edges() -> void:
	Engine.physics_ticks_per_second = 240
	var loaded: Dictionary = AircraftData.load_file("res://data/aircraft/stik_glow_55ax_2t.json")
	_check("edge fixture loads", loaded.get("ok", false), str(loaded.get("errors", [])))
	if loaded.get("ok", false):
		_fractional_line(loaded.model)
		_empty_line_main_exhaustion(loaded.model)
		_stopped_coast(loaded.model)
		_rotor_fuel_tie(loaded.model)
		_pickup_with_stopped_source(loaded.model)
		_rejected_counter_sample(loaded.model)
	print("Glow counter edges: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


## Reuse the two-store conventions from test_glow_flight_physics.
func _line_model(source: Dictionary, line_mass: float, keep_feed: bool, zero_reserve: bool) -> Dictionary:
	var model: Dictionary = source.duplicate(true)
	var install: Dictionary = model.propulsion.glow
	if not keep_feed: install.erase("fuel_feed")
	if zero_reserve: install.unusable_fuel_kg = 0.0
	var line_capacity: float = maxf(0.08, line_mass * 1.2)
	var center := PackedFloat64Array([0.0, 0.0, 0.0])
	var size := PackedFloat64Array([0.08, 0.02, 0.02])
	var liquid_id := "edge_feed_line_liquid"
	var store: Dictionary = {id = liquid_id, fuel = str(install.fuel_tank.fuel), family = "glow",
		density_kg_m3 = float(install.profile.fuel.density_kg_m3), capacity_kg = line_capacity,
		unusable_kg = 0.0, reserve_kg = 0.0, reserve_estimated = false, kind = "feed_line"}
	install.feed_line = {id = "edge_feed_line", liquid_inventory_id = liquid_id,
		reference_mass_kg = line_mass, capacity_kg = line_capacity,
		capacity_m3 = line_capacity / float(install.profile.fuel.density_kg_m3),
		family = "glow", fuel = str(install.fuel_tank.fuel),
		density_kg_m3 = float(install.profile.fuel.density_kg_m3), position = center, size = size, sample_store = store}
	install.total_capacity_kg = float(install.capacity_fuel_kg) + line_capacity
	install.total_reference_fuel_kg = float(install.reference_fuel_kg) + line_mass
	model.mass_kg += line_mass
	var tensor: PackedFloat64Array = MassInventory.rectangular_box_per_kg(center, size)
	for index: int in 6: model.inertia[index] += line_mass * tensor[index]
	install.mass_reference = Flight._prepare_resources(install, model)
	return model


func _fractional_line(source: Dictionary) -> void:
	var model: Dictionary = _line_model(source, 0.25, false, true)
	var install: Dictionary = model.propulsion.glow
	_check("fractional line has a valid resource reference", install.mass_reference.get("ok", false))
	if not install.mass_reference.get("ok", false): return
	var owner: FlightOwner = _owner(model, 6000.0, true, 0.75)
	owner.start_fuel_override_kg = 0.25
	var body := _body(PackedFloat64Array([15.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))
	var values: PackedFloat64Array = Flight.initial(owner, PackedFloat64Array([6000.0]), body)
	_check("fractional line starts with valid main and line stores", Flight.valid(values, install))
	if not Flight.valid(values, install):
		owner.free()
		return
	var cold: float = float(install.settings.temperature_firing_min_k)
	var span: float = float(install.settings.temperature_firing_full_k) - cold
	values[2] = cold - 0.25 * span
	values[6] = 0.1
	values[11] = 0.2
	var at_main := values.duplicate()
	at_main[1] = 0.25
	at_main[2] = cold + 0.25 * span
	at_main[6] = 2.1
	var main_point: Dictionary = Flight.point(owner, body, at_main, 0.25)
	var at_line := at_main.duplicate()
	at_line[1] = 0.0
	at_line[2] = cold + 0.75 * span
	at_line[6] = 4.1
	at_line[Flight.LINE_FUEL_INDEX] = 0.0
	at_line[Flight.SOURCE_MODE_INDEX] = float(Flight.MODE_FEED_LINE)
	var saved_line: PackedByteArray = at_line.to_byte_array()
	var ordinary: Dictionary = Flight.point(owner, body, at_line, 0.5)
	_check("zero-total line sample leaves packed inventory untouched", at_line.to_byte_array() == saved_line)
	_near("main segment endpoint probability is 5/32", float(main_point.get("firing_fraction", NAN)), 0.15625, 1.0e-12)
	_near("connected zero-total line probability is 27/32", float(ordinary.get("firing_fraction", NAN)), 0.84375, 1.0e-12)
	var start: PackedFloat64Array = body.duplicate()
	start.append_array(values)
	var original: PackedByteArray = start.to_byte_array()
	var rate: Callable = func(state: PackedFloat64Array, _at: float) -> PackedFloat64Array:
		var out := PackedFloat64Array()
		out.resize(state.size())
		var mode: int = int(state[RB.SIZE + Flight.SOURCE_MODE_INDEX])
		if mode in [Flight.MODE_MAIN_TANK, Flight.MODE_FEED_LINE]: out[RB.SIZE + 1] = -1.0
		if mode == Flight.MODE_FEED_LINE: out[RB.SIZE + Flight.LINE_FUEL_INDEX] = -1.0
		out[RB.SIZE + 2] = 2.0 * span
		out[RB.SIZE + 6] = 8.0
		return out
	var prepared_result: Dictionary = {}
	for prepared: bool in [true, false]:
		if not prepared: owner.set_meta(Flight.EVALUATOR_IDENTITY_META, {})
		var result: Variant = Flight.step(start, 0.0, 0.625, rate, PackedFloat64Array(), owner)
		var label := "prepared" if prepared else "fallback"
		_check(label + " fractional multi-source step accepted", result is Dictionary, str(result))
		if not result is Dictionary: continue
		_check(label + " input remains immutable", start.to_byte_array() == original)
		var out: PackedFloat64Array = result.state
		var types: Array = []
		for event: Dictionary in result.events: types.append(str(event.type))
		_check(label + " main to line to exhaustion order", types == ["fuel_tank_unusable", "fuel_exhausted", "glow_stopped"], str(types))
		_check(label + " five mechanical opportunities and two fires", out[RB.SIZE + 9] == 5.0 and out[RB.SIZE + 10] == 2.0,
			str(out.slice(RB.SIZE + 6, RB.SIZE + 12)))
		_near(label + " carries the accumulator across both sources", out[RB.SIZE + 11], 0.2, 1.0e-12)
		_check(label + " stops after line reaches zero", out[RB.SIZE + 1] == 0.0
			and out[RB.SIZE + Flight.LINE_FUEL_INDEX] == 0.0
			and int(out[RB.SIZE + Flight.SOURCE_MODE_INDEX]) == Flight.MODE_STARVED)
		if prepared: prepared_result = result
		elif not prepared_result.is_empty():
			_check("prepared and fallback results agree exactly", out.to_byte_array() == (prepared_result.state as PackedFloat64Array).to_byte_array()
				and result.events == prepared_result.events)
	owner.free()


## An installed line can already be empty when a wet main tank is selected.
## The accepted state remains valid, and the main source is connected up to its
## zero-reserve boundary even though its total inventory is then exactly zero.
func _empty_line_main_exhaustion(source: Dictionary) -> void:
	var model: Dictionary = _line_model(source, 0.25, false, true)
	var install: Dictionary = model.propulsion.glow
	var owner: FlightOwner = _owner(model, 6000.0, true, 0.75)
	owner.start_fuel_override_kg = 0.25
	var body := _body(PackedFloat64Array([15.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))
	var values: PackedFloat64Array = Flight.initial(owner, PackedFloat64Array([6000.0]), body)
	values[1] = 0.25
	values[6] = 0.1
	values[Flight.LINE_FUEL_INDEX] = 0.0
	values[Flight.SOURCE_MODE_INDEX] = float(Flight.MODE_MAIN_TANK)
	_check("empty line with usable main fuel is an accepted state", Flight.valid(values, install), str(values))
	var boundary := values.duplicate()
	boundary[1] = 0.0
	boundary[6] = 1.1
	var ordinary: Dictionary = Flight.point(owner, body, boundary, 0.25)
	_check("empty-line main RK sample sees the connected left limit",
		ordinary.get("ok", false) and ordinary.firing_fraction == 1.0,
		str(ordinary.get("firing_fraction", NAN)))
	var start: PackedFloat64Array = body.duplicate()
	start.append_array(values)
	var rate: Callable = func(state: PackedFloat64Array, _at: float) -> PackedFloat64Array:
		var out := PackedFloat64Array()
		out.resize(state.size())
		if int(state[RB.SIZE + Flight.SOURCE_MODE_INDEX]) == Flight.MODE_MAIN_TANK: out[RB.SIZE + 1] = -1.0
		out[RB.SIZE + 6] = 4.0
		return out
	for prepared: bool in [true, false]:
		if not prepared: owner.set_meta(Flight.EVALUATOR_IDENTITY_META, {})
		var label := "prepared" if prepared else "fallback"
		var result: Variant = Flight.step(start, 0.0, 0.375, rate, PackedFloat64Array(), owner)
		_check(label + " empty-line main exhaustion is accepted", result is Dictionary, str(result) if not result is Dictionary else "")
		if result is Dictionary:
			var out: PackedFloat64Array = result.state
			_check(label + " preserves the pre-exhaustion fire with empty line",
				out[RB.SIZE + 9] == 1.0 and out[RB.SIZE + 10] == 1.0,
				str(out.slice(RB.SIZE + 6, RB.SIZE + 12)))
	owner.free()


func _stopped_coast(source: Dictionary) -> void:
	var model: Dictionary = source.duplicate(true)
	model.propulsion.glow.erase("fuel_feed")
	var owner: FlightOwner = _owner(model, 6000.0, true, 0.75)
	var body := _body(PackedFloat64Array([15.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))
	var values: PackedFloat64Array = Flight.initial(owner, PackedFloat64Array([6000.0]), body)
	values[1] = float(model.propulsion.glow.unusable_fuel_kg) + 0.001 * 0.0025
	values[6] = 0.1
	values[11] = 1.0 - 0.5e-12
	var remainder: float = values[11]
	var start: PackedFloat64Array = body.duplicate()
	start.append_array(values)
	var rate: Callable = func(state: PackedFloat64Array, _at: float) -> PackedFloat64Array:
		var out := PackedFloat64Array()
		out.resize(state.size())
		if int(state[RB.SIZE + Flight.SOURCE_MODE_INDEX]) == Flight.MODE_MAIN_TANK: out[RB.SIZE + 1] = -0.001
		out[RB.SIZE + 6] = 200.0
		return out
	var dt: float = 1.0 / 240.0
	var first: Variant = Flight.step(start, 0.0, dt, rate, PackedFloat64Array(), owner)
	_check("near-threshold case stops before an opportunity", first is Dictionary)
	if first is Dictionary:
		var first_state: PackedFloat64Array = first.state
		_check("stop retains the unspent accumulator", first_state[RB.SIZE + 7] == 0.0
			and first_state[RB.SIZE + 9] == 0.0 and first_state[RB.SIZE + 10] == 0.0 and first_state[RB.SIZE + 11] == remainder)
		var next: Variant = Flight.step(first_state, dt, dt, rate, PackedFloat64Array(), owner)
		_check("coast tick after stop is accepted", next is Dictionary)
		if next is Dictionary:
			var stopped: PackedFloat64Array = next.state
			_check("zero probability never awards a coast fire", stopped[RB.SIZE + 9] == 1.0
				and stopped[RB.SIZE + 10] == 0.0 and stopped[RB.SIZE + 11] == remainder)
	owner.free()


func _rotor_fuel_tie(source: Dictionary) -> void:
	var model: Dictionary = source.duplicate(true)
	model.propulsion.glow.erase("fuel_feed")
	var owner: FlightOwner = _owner(model, 6000.0, true, 0.75)
	var body := _body(PackedFloat64Array([15.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))
	var values: PackedFloat64Array = Flight.initial(owner, PackedFloat64Array([6000.0]), body)
	values[1] = float(model.propulsion.glow.unusable_fuel_kg) + 0.001 * 0.0025
	values[6] = 0.1
	var start: PackedFloat64Array = body.duplicate()
	start.append_array(values)
	var rate: Callable = func(state: PackedFloat64Array, _at: float) -> PackedFloat64Array:
		var out := PackedFloat64Array()
		out.resize(state.size())
		if int(state[RB.SIZE + Flight.SOURCE_MODE_INDEX]) == Flight.MODE_MAIN_TANK:
			out[RB.SIZE] = -2400000.0
			out[RB.SIZE + 1] = -0.001
		out[RB.SIZE + 6] = 400.0
		return out
	var result: Variant = Flight.step(start, 0.0, 1.0 / 240.0, rate, PackedFloat64Array(), owner)
	_check("coincident rotor and fuel boundaries are accepted", result is Dictionary, str(result))
	if result is Dictionary:
		var types: Array = []
		for event: Dictionary in result.events: types.append(str(event.type))
		_check("rotor projection precedes fuel stop", types == ["glow_rotor_stopped", "fuel_exhausted", "glow_stopped"], str(types))
		var out: PackedFloat64Array = result.state
		_check("rotor/fuel tie counts the pre-stop chance once", out[RB.SIZE + 9] == 1.0 and out[RB.SIZE + 10] == 1.0,
			str(out.slice(RB.SIZE + 6, RB.SIZE + 12)))
	owner.free()


func _pickup_with_stopped_source(source: Dictionary) -> void:
	var model: Dictionary = _line_model(source, 0.05, true, false)
	var install: Dictionary = model.propulsion.glow
	install.pickup_position = M.add(install.tank_position, PackedFloat64Array([0.0, 0.0, float(install.tank_size[2]) * 0.25]))
	install.has_pickup_position = true
	var owner: FlightOwner = _owner(model, 0.0, false, 0.0)
	owner.support_gravity = true
	owner.sim.gravity = 9.80665
	owner.start_fuel_override_kg = float(install.capacity_fuel_kg) * 0.6
	var body := _body(PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))
	var values: PackedFloat64Array = Flight.initial(owner, PackedFloat64Array([0.0]), body)
	values[6] = 0.1
	values[11] = 1.0 - 0.5e-12
	var remainder: float = values[11]
	var start: PackedFloat64Array = body.duplicate()
	start.append_array(values)
	var rate: Callable = func(state: PackedFloat64Array, _at: float) -> PackedFloat64Array:
		var out := PackedFloat64Array()
		out.resize(state.size())
		var mode: int = int(state[RB.SIZE + Flight.SOURCE_MODE_INDEX])
		if mode in [Flight.MODE_MAIN_TANK, Flight.MODE_FEED_LINE]: out[RB.SIZE + 1] = -0.5
		if mode == Flight.MODE_FEED_LINE: out[RB.SIZE + Flight.LINE_FUEL_INDEX] = -0.5
		# Deliberately advance mechanical phase to exercise missed opportunities while stopped.
		out[RB.SIZE + 6] = 10.0
		return out
	var result: Variant = Flight.step(start, 0.0, 0.6, rate, PackedFloat64Array(), owner)
	_check("pickup loss and line drain accept while source is stopped", result is Dictionary, str(result))
	if result is Dictionary:
		var types: Array = []
		for event: Dictionary in result.events: types.append(str(event.type))
		_check("pickup loss precedes line starvation", types == ["fuel_pickup_lost", "fuel_starved"], str(types))
		var out: PackedFloat64Array = result.state
		_check("pickup transitions never relight the stopped source", out[RB.SIZE + 9] == 6.0
			and out[RB.SIZE + 10] == 0.0 and out[RB.SIZE + 11] == remainder)
	owner.free()


func _rejected_counter_sample(source: Dictionary) -> void:
	var model: Dictionary = source.duplicate(true)
	model.propulsion.glow.erase("fuel_feed")
	var owner := TimedOwner.new()
	owner.aircraft = {model = model}
	owner.engine_running = true
	owner.sim = {inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.75]), aux = PackedFloat64Array([6000.0]), gravity = 0.0}
	var body := _body(PackedFloat64Array([15.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))
	var values: PackedFloat64Array = Flight.initial(owner, PackedFloat64Array([6000.0]), body)
	var stop_time := 0.0025
	values[1] = float(model.propulsion.glow.unusable_fuel_kg) + 0.001 * stop_time
	values[6] = 0.9
	var start: PackedFloat64Array = body.duplicate()
	start.append_array(values)
	var saved: PackedByteArray = start.to_byte_array()
	var rate: Callable = func(state: PackedFloat64Array, _at: float) -> PackedFloat64Array:
		var out := PackedFloat64Array()
		out.resize(state.size())
		if int(state[RB.SIZE + Flight.SOURCE_MODE_INDEX]) == Flight.MODE_MAIN_TANK: out[RB.SIZE + 1] = -0.001
		out[RB.SIZE + 6] = 100.0
		return out
	var dt: float = 1.0 / 240.0
	owner.bad_time = stop_time
	var bounded: Dictionary = ResourceStep.advance(start, 0.0, dt, rate, PackedFloat64Array(), Flight._resource_events(owner))
	_check("resource step succeeds before counter observation", bounded.get("ok", false)
		and bounded.events.size() == 1 and bounded.events[0].type == "fuel_exhausted" and owner.rejected_samples == 0)
	var rejected: Variant = Flight.step(start, 0.0, dt, rate, PackedFloat64Array(), owner)
	_check("needed failed counter sample rejects the step", rejected is PackedFloat64Array
		and rejected.size() == 1 and is_nan(rejected[0]) and owner.rejected_samples == 1)
	_check("failed sample leaves its input untouched", start.to_byte_array() == saved)

	# Exercise the real Simulation transaction with a simple joint-stage rate.
	var sim: Node = Sim.new()
	root.add_child(sim)
	var vehicle := Vehicle.new()
	vehicle.continuous_size = Flight.SIZE
	vehicle.aux_size = 0
	vehicle.modes_size = 0
	vehicle.stage = func(_body_state: PackedFloat64Array, block: PackedFloat64Array, _at: float) -> Dictionary:
		var derivative := PackedFloat64Array()
		derivative.resize(block.size())
		if int(block[Flight.SOURCE_MODE_INDEX]) == Flight.MODE_MAIN_TANK: derivative[1] = -0.001
		derivative[6] = 100.0
		var body_rate := PackedFloat64Array()
		body_rate.resize(RB.SIZE)
		return {loads = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
			derivative = derivative, rotor_momentum = PackedFloat64Array([0.0, 0.0, 0.0]), body_derivative = body_rate}
	vehicle.step_policy = func(combined: PackedFloat64Array, at: float, step_dt: float, derivative: Callable, first: PackedFloat64Array) -> Variant:
		return Flight.step(combined, at, step_dt, derivative, first, owner)
	sim.aux = PackedFloat64Array()
	sim.continuous = values.duplicate()
	_check("rollback fixture installs and resets", sim.set_model(vehicle) and sim.reset(body), sim.fault_reason)
	var before_body: PackedByteArray = sim.state.to_byte_array()
	var before_values: PackedByteArray = sim.continuous.to_byte_array()
	var before_aux: PackedByteArray = sim.aux.to_byte_array()
	owner.rejected_samples = 0
	sim.step()
	_check("counter sample failure faults the Simulation tick", not sim.fault_reason.is_empty() and owner.rejected_samples == 1,
		sim.fault_reason)
	_check("failed tick preserves body, counters, clock, auxiliary state and events", sim.tick == 0
		and sim.state.to_byte_array() == before_body and sim.continuous.to_byte_array() == before_values
		and sim.aux.to_byte_array() == before_aux and sim.last_events.is_empty())
	sim.free()
	owner.free()
