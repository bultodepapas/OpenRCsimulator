## Preparation and tick handoff for prescribed-fuel shaft and turbine stages.
## The source is the complete validated normalized propulsion model, detached
## and bound exactly to the committed model before the native decoder uses it.
extends RefCounted

const WeatherAdapter := preload("weather_adapter.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Turbine := preload("res://physics/turbine.gd")
const RB := preload("res://physics/rigid_body.gd")


static func kind_for(session: Node) -> String:
	var prop: Dictionary = session.aircraft.model.propulsion
	if session.glow_is_active() or session.liquid_fuel_is_active() or Propulsion.is_electric(prop):
		return ""
	if Turbine.is_turbine(prop):
		return "turbine-continuous" if session.turbine_is_continuous() else "turbine-sampled"
	if Propulsion.has_rotor_dynamics(prop):
		return "shaft-coupled" if session.shaft_is_coupled() else "shaft-split"
	return ""


static func config_for(session: Node) -> Dictionary:
	var kind := kind_for(session)
	if kind.is_empty(): return {}
	var config: Dictionary = WeatherAdapter.config_for(session)
	if config.is_empty(): return {}
	config.prescribed = {format = "openrc-nk3-prescribed-snapshot-v1", kind = kind,
		source = session.aircraft.model.propulsion.duplicate(true)}
	if kind == "shaft-coupled":
		config.inertia = session.sim.inertia.duplicate()
		config.inverse = RB.inertia_inverse(config.inertia)
	return config


static func set_context(session: Node, native: Object, aux: PackedFloat64Array,
		inputs: PackedFloat64Array, at: float) -> bool:
	var d: Dictionary = session._deflections(aux)
	var deflections := PackedFloat64Array([d.elevator, d.aileron_right, d.aileron_left, d.rudder, d.get("flap", 0.0)])
	var turbine: bool = Turbine.is_turbine(session.aircraft.model.propulsion)
	# Prescribed turbine stage tests engine_running directly. The gas shaft uses
	# propulsion_power_enabled(), including the session's existing failure latch.
	var enabled: bool = session.engine_running if turbine else session.propulsion_power_enabled()
	var capture: bool = session.sim.state.size() == RB.SIZE \
		and session._should_capture_substep_context(session.sim.state, session.sim.continuous, at)
	return native.set_tick_context(aux, inputs, deflections, at) \
		and native.set_power_context(session.propulsion_throttle(), enabled) \
		and native.set_preview_context(session.sim.state, session.sim.continuous, capture)
