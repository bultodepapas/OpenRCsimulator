## NK-3 finite-liquid component qualification: actual P-51, Corsair and Avanti
## prepared gas/turbine source, fuel inventory and fixed-datum response. Does
## not admit a full aircraft stage, flight backend or physical validation.
extends "oracle.gd"

const LiquidFuel := preload("res://physics/liquid_fuel.gd")
const LiquidFlight := preload("res://sim/liquid_fuel_flight.gd")
const LiquidPropulsion := preload("res://physics/propulsion.gd")
const LiquidTurbine := preload("res://physics/turbine.gd")
const FixedDatum := preload("res://physics/fixed_datum_body.gd")

const LIQUID_IDS := ["p51d-mustang-120", "f4u-corsair-250", "sebart-avanti-s-a200-p100rx"]
const MASS_FIELDS := ["reference_mass_kg", "reference_inertia_kgm2", "references", "capacities", "centers", "tensors"]
const TURBINE_FIELDS := ["max_rpm", "axis", "offset", "intake_offset", "throttle_map", "accel_limit", "decel_limit",
	"static_thrust", "mass_flow", "fuel_flow", "governor_tau", "installed_factor", "rotor_inertia", "rotor_sense"]


func _source_hashes() -> Dictionary:
	var out: Dictionary = super._source_hashes()
	for path: String in ["res://physics/liquid_fuel.gd", "res://sim/liquid_fuel_flight.gd",
			"res://physics/mass_inventory.gd", "res://physics/fixed_datum_body.gd", "res://physics/rigid_body.gd",
			"res://physics/rotor_coupling.gd", "res://physics/turbine.gd", "res://app_state/aircraft_catalog.gd",
			"res://data/aircraft/p51d_mustang_120.json", "res://data/aircraft/f4u_corsair_250.json",
			"res://data/aircraft/sebart_avanti_s_a200.json", "res://data/fuels/openrc-fuel-registry.json"]:
		out[path] = FileAccess.get_sha256(path)
	return out


func _checks() -> void:
	_report.format = "openrc-nk3-liquid-oracle v1"
	if _states < 2:
		_failures.append("liquid oracle requires at least two states per installation")
		return
	_report.liquid_cases = []
	for id: String in LIQUID_IDS:
		_check_case(id)
	if _report.liquid_cases.size() != LIQUID_IDS.size():
		_failures.append("not all liquid catalog aircraft were exercised")


func _snapshot(prop: Dictionary) -> Dictionary:
	var adapter: Dictionary = prop.liquid_fuel
	var prepared: Dictionary = adapter.prepared_inventory
	var mass := {}
	for field: String in MASS_FIELDS: mass[field] = prepared[field]
	var bound_index := -1
	for i: int in prepared.resources.size():
		if prepared.resources[i].id == adapter.tank_id: bound_index = i
	if bound_index < 0: return {}
	var source := {}
	var gas: bool = not LiquidTurbine.is_turbine(prop)
	if gas:
		source = {power_curve = prop.shaft.power_curve, friction = prop.shaft.friction, idle_power = prop.shaft.idle_power,
			peak_indicated_power = prop.shaft.peak_indicated_power, bsfc_kg_kwh = adapter.bsfc_kg_kwh,
			idle_flow_kg_s = adapter.idle_flow_kg_s}
	else:
		for field: String in TURBINE_FIELDS: source[field] = prop[field]
		for field: String in ["ram_jet", "ram_flow"]:
			if prop.has(field): source[field] = prop[field]
	return {format = "openrc-nk3-liquid-component-v1", family = "gas" if gas else "turbine", mass = mass,
		store = {capacity_kg = adapter.capacity_kg, unusable_kg = adapter.unusable_kg, bound_index = bound_index}, source = source}


func _vector(scale: float) -> PackedFloat64Array:
	return PackedFloat64Array([_rng.randf_range(-scale, scale), _rng.randf_range(-scale, scale),
		_rng.randf_range(-scale, scale)])


func _mass_values(point: Dictionary, usable: float, adapter: Dictionary) -> PackedFloat64Array:
	var values := PackedFloat64Array([point.mass_kg])
	for field: String in ["cg_body_m", "inertia", "inverse", "inertia_origin"]: values.append_array(point[field])
	var onboard: float = clampf(maxf(0.0, usable) + float(adapter.unusable_kg), float(adapter.unusable_kg), float(adapter.capacity_kg))
	var inventory_usable: float = clampf(maxf(onboard, float(adapter.unusable_kg)) - float(adapter.unusable_kg),
		0.0, float(adapter.capacity_kg) - float(adapter.unusable_kg))
	values.append(onboard)
	values.append(inventory_usable)
	return values


func _status(name: String, expected: bool, actual: bool, inputs: Array) -> void:
	_compare(name, PackedFloat64Array([1.0 if expected else 0.0]), PackedFloat64Array([1.0 if actual else 0.0]), inputs)


func _check_case(id: String) -> void:
	var session: Node = Session.new()
	session.input_enabled = false
	session.setup(Catalog.data_for(id), id)
	if not session.is_flyable() or not session.liquid_fuel_is_active():
		_failures.append("finite-liquid session failed: %s (%s)" % [id, session.pause_reason])
		session.free()
		return
	var prop: Dictionary = session.aircraft.model.propulsion
	var adapter: Dictionary = prop.liquid_fuel
	var snapshot: Dictionary = _snapshot(prop)
	var prepared: Dictionary = _native.prepare_liquid(snapshot)
	if not prepared.get("ok", false):
		_failures.append("liquid prepare %s failed: %s" % [id, prepared.get("error", "")])
		session.free()
		return
	var gas: bool = not LiquidTurbine.is_turbine(prop)
	if gas:
		var geometry := {}
		for field: String in ["diameter", "offset", "ct", "cp", "rotor_inertia", "cp_min", "axis", "normal_force", "pfactor_moment"]:
			if prop.has(field): geometry[field] = prop[field]
		var prop_prepared: Dictionary = _native.prepare_propeller(geometry)
		if not prop_prepared.get("ok", false):
			_failures.append("gas propeller prepare %s failed: %s" % [id, prop_prepared.get("error", "")])
			session.free()
			return
	var original: PackedFloat64Array = session.sim.continuous.duplicate()
	var liquid_index: int = session._liquid_index()
	var rotor_index: int = session._rotor_index() if gas else 0
	if original.size() != liquid_index + 2:
		_failures.append("liquid session layout invalid: " + id)
		session.free()
		return
	var capacity: float = float(adapter.capacity_kg) - float(adapter.unusable_kg)
	var mass_accepted := 0
	var mass_rejected := 0
	var source_accepted := 0
	var source_rejected := 0
	for i: int in _states:
		var usable: float = _rng.randf_range(0.0, capacity)
		if i % 13 == 0: usable = [0.0, -0.001, capacity, capacity + 1.0][(i / 13) % 4]
		if i % 113 == 0 and i > 0: usable = _special()
		var values: PackedFloat64Array = original.duplicate()
		values[liquid_index] = usable
		values[liquid_index + 1] = 1.0 if i % 3 != 0 else 0.0
		var live: Dictionary = LiquidFlight.properties(session, values, true)
		var native_mass: Dictionary = _native.liquid_mass_component(usable)
		var inputs := [id, i, usable]
		var live_ok: bool = live.get("ok", false)
		var native_mass_ok: bool = native_mass.get("ok", false)
		_status("liquid_mass_validity", live_ok, native_mass_ok, inputs)
		if live_ok and native_mass_ok:
			_compare("liquid_mass_values", _mass_values(live, usable, adapter), native_mass.values, inputs)
			mass_accepted += 1
		else:
			mass_rejected += 1
		var body: PackedFloat64Array = session.sim.state.duplicate()
		for k: int in 3:
			body[RB.VEL + k] = _rng.randf_range(-20.0, 30.0)
			body[RB.RATE + k] = _rng.randf_range(-4.0, 4.0)
		var rpm: float = _rng.randf_range(0.0, float(prop.max_rpm))
		if i % 17 == 0: rpm = [0.0, 0.5, 1.0, -0.001][(i / 17) % 4]
		var throttle: float = _rng.randf_range(0.0, 1.0)
		var running: bool = i % 3 != 0
		var datum: PackedFloat64Array = _vector(30.0)
		var explicit := PackedFloat64Array()
		if i % 4 == 0: explicit = _vector(30.0)
		var air := {v_air = datum}
		if not explicit.is_empty(): air[LiquidPropulsion.STAGE_PROPULSION_AIR_KEY] = explicit
		var flow: Dictionary = LiquidPropulsion.stage_air_velocity(body, air, prop)
		var rho: float = session.air_density(body)
		var charge: float = session.engine_charge_ratio(body)
		if gas:
			_check_gas_laws(id, i, prop, rpm, throttle, rho, charge, running)
			values[rotor_index] = rpm
			var base: PackedFloat64Array = values.slice(0, liquid_index)
			var external := PackedFloat64Array()
			for k: int in 6: external.append(_rng.randf_range(-10.0, 10.0))
			if live_ok and i % 11 <= 2:
				# Explicit rest hold, forward release and reverse refusal, all with source off.
				running = false
				rpm = 0.0
				base[rotor_index] = 0.0
				for k: int in 3: body[RB.RATE + k] = 0.0
				var axis: PackedFloat64Array = LiquidPropulsion.axis(prop)
				var friction: float = prop.shaft.friction[0]
				var required: float = [0.0, -2.0 * friction, 2.0 * friction][i % 11]
				var target: PackedFloat64Array = RB.inertia_mul(live.inertia, M.scale(axis, required / float(prop.rotor_inertia)))
				for k: int in 3: external[3 + k] = target[k]
			var expected := {ok = false}
			if live_ok and flow.get("ok", false):
				session.engine_running = true
				session.sim.inputs[3] = throttle
				expected = session._coupled_response(body, base, 0.0, live, running, {air = air, pre_reaction_loads = external})
				if expected.get("ok", false):
					var power: float = maxf(0.0, LiquidPropulsion.engine_torque(rpm, throttle, prop, charge) * rpm * TAU / 60.0) if running else 0.0
					expected.fuel_rate = LiquidFuel.flow_rate_kg_s(adapter, {running = running, shaft_power_w = power, rpm = rpm})
					if not is_finite(expected.fuel_rate) or expected.fuel_rate < 0.0: expected = {ok = false}
			var local: PackedFloat64Array = flow.velocity_body if flow.get("ok", false) else PackedFloat64Array([NAN, NAN, NAN])
			var stage := PackedFloat64Array([usable, rpm, throttle, rho, charge])
			var actual: Dictionary = _native.liquid_gas_component(body, external, local, datum, not explicit.is_empty(), stage, running, session.sim.gravity)
			var source_ok: bool = expected.get("ok", false)
			var actual_ok: bool = actual.get("ok", false)
			var gas_inputs := [id, i, body, external, datum, explicit, stage, running]
			_status("liquid_gas_coupling_validity", source_ok, actual_ok, gas_inputs)
			if source_ok and actual_ok:
				var expected_values: PackedFloat64Array = expected.loads.duplicate()
				var rotor: PackedFloat64Array = session._coupled_rotor(body, base, 0.0)
				expected_values.append_array(rotor)
				expected_values.append(expected.rpm_rate)
				expected_values.append(expected.fuel_rate)
				_compare("liquid_gas_coupling_values", expected_values, actual.values, gas_inputs)
				var body_ref: PackedFloat64Array = FixedDatum.derivative(body, live, expected.loads.slice(0, 3),
					expected.loads.slice(3, 6), session.sim.gravity, rotor)
				_compare("liquid_gas_body_derivative", body_ref, actual.body_derivative, gas_inputs)
				source_accepted += 1
			else:
				source_rejected += 1
		else:
			var expected := _turbine_reference(prop, body, datum, explicit, rpm, throttle, rho, running)
			var stage := PackedFloat64Array([rpm, throttle, rho])
			var actual: Dictionary = _native.liquid_turbine_component(body, datum, explicit, stage, running)
			var source_ok: bool = expected.get("ok", false)
			var actual_ok: bool = actual.get("ok", false)
			var turbine_inputs := [id, i, body, datum, explicit, stage, running]
			_status("liquid_turbine_validity", source_ok, actual_ok, turbine_inputs)
			if source_ok and actual_ok:
				_compare("liquid_turbine_values", expected.values, actual.values, turbine_inputs)
				source_accepted += 1
			else:
				source_rejected += 1
		_tally("liquid_" + id, "states")
	if mass_accepted == 0 or mass_rejected == 0 or source_accepted == 0 or source_rejected == 0:
		_failures.append("liquid %s missed accepted or rejected stages" % id)
	_report.liquid_cases.append({name = id, family = snapshot.family, states = _states, mass_accepted = mass_accepted,
		mass_rejected = mass_rejected, source_accepted = source_accepted, source_rejected = source_rejected,
		resources = snapshot.mass.references.size()})
	var malformed: Dictionary = snapshot.duplicate(true)
	malformed.store.capacity_kg = 0.0
	if _native.prepare_liquid(malformed).get("ok", false): _failures.append("invalid liquid capacity admitted: " + id)
	if _native.liquid_mass_component(0.0).get("ok", false): _failures.append("liquid failed prepare retained stale model: " + id)
	malformed = snapshot.duplicate(true)
	malformed.source.unknown = 1.0
	if _native.prepare_liquid(malformed).get("ok", false): _failures.append("unknown liquid source field admitted: " + id)
	session.free()


func _check_gas_laws(id: String, i: int, prop: Dictionary, rpm: float, throttle: float,
		rho: float, charge: float, running: bool) -> void:
	var axial: float = _rng.randf_range(-30.0, 40.0)
	var power: float = _rng.randf_range(-100.0, 6000.0)
	if i % 41 == 0: charge = -1.0
	elif i % 47 == 0: rho = 0.0
	elif i % 67 == 0: power = _special()
	var expected := PackedFloat64Array([LiquidPropulsion.engine_torque(rpm, throttle, prop, charge),
		LiquidPropulsion.shaft_rate(rpm, throttle, axial, prop, rho, charge, running),
		LiquidFuel.flow_rate_kg_s(prop.liquid_fuel, {running = running, shaft_power_w = power, rpm = rpm})])
	var actual: Dictionary = _native.liquid_gas_laws_component(rpm, throttle, axial, rho, charge, power, running)
	if not actual.get("ok", false):
		_failures.append("prepared gas law refused: %s state %d" % [id, i])
		return
	_compare("liquid_gas_laws", expected, actual.values, [id, i, rpm, throttle, axial, rho, charge, power, running])


func _turbine_reference(prop: Dictionary, body: PackedFloat64Array, datum: PackedFloat64Array,
		explicit: PackedFloat64Array, rpm: float, throttle: float, rho: float, running: bool) -> Dictionary:
	if not is_finite(rpm) or rpm < 0.0 or rpm > float(prop.max_rpm): return {ok = false}
	var air := {v_air = datum}
	if not explicit.is_empty(): air[LiquidPropulsion.STAGE_PROPULSION_AIR_KEY] = explicit
	var flow: Dictionary = LiquidPropulsion.stage_air_velocity(body, air, prop)
	if not flow.get("ok", false): return {ok = false}
	var rate: float = LiquidFuel.flow_rate_kg_s(prop.liquid_fuel, {running = running, rpm = rpm})
	if not is_finite(rate) or rate < 0.0: return {ok = false}
	var values: PackedFloat64Array = flow.velocity_body.duplicate()
	values.append_array(LiquidTurbine.loads(flow.velocity_body, rpm, prop, rho) if running else PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]))
	values.append_array(LiquidTurbine.rotor_momentum(rpm, prop))
	values.append(LiquidTurbine.spool_rate(rpm, LiquidTurbine.demand_rpm(throttle, prop) if running else 0.0, prop))
	values.append(rate)
	return {ok = true, values = values}
