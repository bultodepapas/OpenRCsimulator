## Fixed-wing finite liquid adapter. The kernel sees only stage and event contracts.
extends RefCounted

const Liquid := preload("res://physics/liquid_fuel.gd")
const Sample := preload("res://sim/fuel_sample.gd")
const FixedDatum := preload("res://physics/fixed_datum_body.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Turbine := preload("res://physics/turbine.gd")
const Wash := preload("res://physics/wash_transport.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

const LAW := "single-store-finite-liquid-fixed-datum-v1"
const LAYOUT := "base propulsion/wheels; usable fuel kg; source latch 0/1"
const CUTOFF_LAW := "combustion-thrust-off; rotor existing deceleration schedule to zero; estimated"


static func initial(owner: Node) -> PackedFloat64Array:
	var config: Dictionary = owner.aircraft.model.propulsion.liquid_fuel
	var amount: float = owner.start_fuel_kg()
	if not is_finite(amount) or amount <= float(config.unusable_kg) or amount > float(config.capacity_kg):
		return PackedFloat64Array([NAN, NAN])
	return PackedFloat64Array([amount - float(config.unusable_kg), 1.0 if owner.engine_running else 0.0])


static func valid(owner: Node, values: PackedFloat64Array, trial: bool = false) -> bool:
	var index: int = owner._liquid_index()
	if values.size() != index + 2:
		return false
	for value: float in values:
		if not is_finite(value):
			return false
	var config: Dictionary = owner.aircraft.model.propulsion.liquid_fuel
	return values[index + 1] in [0.0, 1.0] and (trial or values[index] >= 0.0) \
		and values[index] <= float(config.capacity_kg) - float(config.unusable_kg) \
		and (trial or values[index] != 0.0 or values[index + 1] == 0.0)


static func properties(owner: Node, values: PackedFloat64Array, trial: bool = false) -> Dictionary:
	if not valid(owner, values, trial):
		return {ok = false}
	var config: Dictionary = owner.aircraft.model.propulsion.liquid_fuel
	# The usable coordinate was validated against capacity-unusable. Reconstructing
	# absolute mass can round one ulp above capacity when residue is nonzero.
	var amount: float = clampf(maxf(0.0, values[owner._liquid_index()]) + float(config.unusable_kg),
		float(config.unusable_kg), float(config.capacity_kg))
	return Liquid.properties(config, {str(config.tank_id): amount})


static func sample(owner: Node, values: PackedFloat64Array) -> Dictionary:
	var live: Dictionary = properties(owner, values)
	if not live.get("ok", false):
		return {ok = false}
	var config: Dictionary = owner.aircraft.model.propulsion.liquid_fuel
	var amount: float = clampf(values[owner._liquid_index()] + float(config.unusable_kg),
		float(config.unusable_kg), float(config.capacity_kg))
	var result: Dictionary = Sample.build(live, owner.aircraft.model.fuel_system.tanks,
		{str(config.tank_id): amount}, owner.sim.tick, owner.sim.time(), true)
	if result.get("ok", false):
		result.law = LAW
		result.consumption_law = str(config.law)
		result.registry_sha256 = str(owner.aircraft.model.fuel_system.registry_sha256)
	return result


static func evaluate(body: PackedFloat64Array, values: PackedFloat64Array, at: float, owner: Node) -> Dictionary:
	var live: Dictionary = properties(owner, values, true)
	if not live.get("ok", false):
		return {}
	var index: int = owner._liquid_index()
	var base: PackedFloat64Array = values.slice(0, index)
	var prop: Dictionary = owner.aircraft.model.propulsion
	var running: bool = values[index + 1] == 1.0 and owner.propulsion_power_enabled()
	var rpm: float
	var loads: PackedFloat64Array
	var derivative: PackedFloat64Array
	var rotor: PackedFloat64Array
	var shaft_power: float = 0.0
	if Turbine.is_turbine(prop):
		var response: Dictionary = owner._turbine_evaluate(body, base, at, live, running)
		if response.is_empty():
			return {}
		rpm = base[0]
		loads = response.loads
		derivative = response.derivative
		rotor = response.rotor_momentum
		var shift: PackedFloat64Array = M.cross(live.cg_body_m, loads.slice(0, 3))
		for axis: int in 3:
			loads[3 + axis] -= shift[axis]
	else:
		var response: Dictionary = owner._coupled_response(body, base, at, live, running)
		if not response.get("ok", false):
			return {}
		rpm = owner._coupled_rpm(base)
		loads = response.loads
		derivative = Wash.derivative(response.air.v_air, rpm, prop, owner.air_density(body),
			base.slice(0, owner._rotor_index())) if owner._rotor_index() > 0 else PackedFloat64Array()
		derivative.append(response.rpm_rate)
		derivative.append_array(response.wheel_derivative)
		rotor = owner._coupled_rotor(body, base, at)
		shaft_power = maxf(0.0, Propulsion.engine_torque(rpm, owner.propulsion_throttle(), prop,
			owner.engine_charge_ratio(body)) * rpm * TAU / 60.0) if running else 0.0
	var rate: float = Liquid.flow_rate_kg_s(prop.liquid_fuel,
		{running = running, shaft_power_w = shaft_power, rpm = rpm})
	if not is_finite(rate) or rate < 0.0:
		return {}
	derivative.append(-rate)
	derivative.append(0.0)
	var body_rate: PackedFloat64Array = FixedDatum.derivative(body, live, loads.slice(0, 3),
		loads.slice(3, 6), owner.sim.gravity, rotor)
	return {loads = loads, derivative = derivative, rotor_momentum = rotor, body_derivative = body_rate}


static func project_exhaustion(combined: PackedFloat64Array, at: int) -> PackedFloat64Array:
	var out: PackedFloat64Array = combined.duplicate()
	if at < RB.SIZE or at + 1 >= out.size():
		return PackedFloat64Array()
	out[at] = 0.0
	out[at + 1] = 0.0
	return out


static func aux(values: PackedFloat64Array, sampled: PackedFloat64Array, owner: Node) -> PackedFloat64Array:
	if not valid(owner, values):
		return PackedFloat64Array([NAN])
	return owner._turbine_aux(values, sampled) if Turbine.is_turbine(owner.aircraft.model.propulsion) \
		else owner._coupled_aux(values, sampled)


static func contact_sampler(owner: Node, before: PackedFloat64Array, after: PackedFloat64Array) -> Callable:
	if not valid(owner, before) or not valid(owner, after):
		return Callable()
	var config: Dictionary = owner.aircraft.model.propulsion.liquid_fuel
	var index: int = owner._liquid_index()
	var start: float = clampf(before[index] + float(config.unusable_kg), float(config.unusable_kg), float(config.capacity_kg))
	var end: float = clampf(after[index] + float(config.unusable_kg), float(config.unusable_kg), float(config.capacity_kg))
	var tanks: Array = owner.aircraft.model.fuel_system.tanks
	var contact_tick: int = owner.sim.tick + 1
	var start_time: float = owner.sim.time()
	var dt: float = owner.sim.dt()
	return func(fraction: float) -> Dictionary:
		if not is_finite(fraction) or fraction < 0.0 or fraction > 1.0:
			return {ok = false}
		var amounts: Dictionary = {str(config.tank_id): lerpf(start, end, fraction)}
		var result: Dictionary = Sample.build(Liquid.properties(config, amounts), tanks, amounts,
			contact_tick, start_time + fraction * dt, true)
		result.sample_boundary = "swept_contact_linear_inventory"
		result.impact_fraction = fraction
		result.law = LAW
		result.consumption_law = str(config.law)
		result.registry_sha256 = str(owner.aircraft.model.fuel_system.registry_sha256)
		return result
