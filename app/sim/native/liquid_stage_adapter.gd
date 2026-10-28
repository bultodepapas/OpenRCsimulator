## Research-only finite-liquid stage preparation. FlightSession retains all
## tick policies, failure modes, resource events and accepted-step state.
extends RefCounted

const WeatherAdapter := preload("weather_adapter.gd")
const Turbine := preload("res://physics/turbine.gd")
const RB := preload("res://physics/rigid_body.gd")
const MASS_FIELDS := ["reference_mass_kg", "reference_inertia_kgm2", "references", "capacities", "centers", "tensors"]
const TURBINE_FIELDS := ["max_rpm", "axis", "offset", "intake_offset", "throttle_map", "accel_limit", "decel_limit",
	"static_thrust", "mass_flow", "fuel_flow", "governor_tau", "installed_factor", "rotor_inertia", "rotor_sense"]


## Source data are selected from the already validated aircraft; no numerical
## values are synthesized and the capability flag `liquid` remains a bool.
static func snapshot(prop: Dictionary) -> Dictionary:
	if not prop.has("liquid_fuel"): return {}
	var adapter: Dictionary = prop.liquid_fuel
	var inventory: Dictionary = adapter.prepared_inventory
	var mass := {}
	for field: String in MASS_FIELDS:
		if not inventory.has(field): return {}
		mass[field] = inventory[field]
	var index := -1
	for i: int in inventory.resources.size():
		if inventory.resources[i].id == adapter.tank_id: index = i
	if index < 0: return {}
	var gas: bool = not Turbine.is_turbine(prop)
	var source := {}
	if gas:
		source = {power_curve = prop.shaft.power_curve, friction = prop.shaft.friction, idle_power = prop.shaft.idle_power,
			peak_indicated_power = prop.shaft.peak_indicated_power, bsfc_kg_kwh = adapter.bsfc_kg_kwh,
			idle_flow_kg_s = adapter.idle_flow_kg_s}
	else:
		for field: String in TURBINE_FIELDS:
			if not prop.has(field): return {}
			source[field] = prop[field]
		for field: String in ["ram_jet", "ram_flow"]:
			if prop.has(field): source[field] = prop[field]
	return {format = "openrc-nk3-liquid-component-v1", family = "gas" if gas else "turbine", mass = mass,
		store = {capacity_kg = adapter.capacity_kg, unusable_kg = adapter.unusable_kg, bound_index = index}, source = source}


static func config_for(session: Node) -> Dictionary:
	if not session.liquid_fuel_is_active(): return {}
	var config: Dictionary = WeatherAdapter.config_for(session)
	if config.is_empty(): return {}
	var source: Dictionary = snapshot(session.aircraft.model.propulsion)
	if source.is_empty(): return {}
	# Retraction is an auxiliary tick state: prepare the full-down source gear,
	# even when the session's currently posed contacts are partially retracted.
	config.gear = session.aircraft.model.landing_gear.duplicate(true)
	config.liquid_source = source
	config.layout.gear_aux = session.gear_aux_index()
	config.layout.liquid_index = session._liquid_index()
	config.gravity = session.sim.gravity
	return config


static func set_context(session: Node, native: Object, aux: PackedFloat64Array,
		inputs: PackedFloat64Array, at: float) -> bool:
	var d: Dictionary = session._deflections(aux)
	var deflections := PackedFloat64Array([d.elevator, d.aileron_right, d.aileron_left, d.rudder, d.get("flap", 0.0)])
	# The first reset can prepare the native stage before a body is committed.
	# An empty body may compare equal to itself in the owner's preview predicate,
	# but cannot identify an actual 13-component RK stage.
	var capture: bool = session.sim.state.size() == RB.SIZE \
		and session._should_capture_substep_context(session.sim.state, session.sim.continuous, at)
	return native.set_tick_context(aux, inputs, deflections, at) \
		and native.set_power_context(session.propulsion_throttle(), session.propulsion_power_enabled()) \
		and native.set_preview_context(session.sim.state, session.sim.continuous, capture)
