## NK-3 research-only preparation and per-tick handoff for the electric joint
## stage. Session pre_tick, source events and all accepted-step policies stay in
## GDScript. This helper does not change application admission.
extends RefCounted

const WeatherAdapter := preload("weather_adapter.gd")
const RB := preload("res://physics/rigid_body.gd")
const ECM_FIELDS := ["kind", "series", "branches", "group_capacity_c", "initial_soc", "weak_capacity_factor",
	"weak_resistance_factor", "weak_soc_offset", "interconnect_ohm", "auxiliary_current_a",
	"cooling_airflow_fraction", "thermal_capacity_j_per_k", "h_still_w_per_k",
	"h_forced_w_per_k_sqrt_mps", "lvc_filter_s", "soc_knots", "temperature_knots_k", "ocv", "r0", "rc_r", "rc_tau"]


## Same strict source schema used by electric_oracle.gd. No session mode,
## state or callbacks are fabricated or changed to satisfy the native decoder.
static func snapshot(prop: Dictionary) -> Dictionary:
	var battery: Dictionary = prop.battery
	var fields: Array = []
	match str(battery.kind):
		"fixed_voltage": fields = ["kind", "voltage_v"]
		"ocv_resistance": fields = ["kind", "capacity_ah", "resistance_ohm", "auxiliary_current_a", "initial_soc", "ocv_points"]
		"pack_ecm": fields = ECM_FIELDS
		_: return {}
	var selected := {}
	for field: String in fields:
		if not battery.has(field): return {}
		selected[field] = battery[field]
	return {format = "openrc-nk3-electric-snapshot-v1", motor = prop.motor.duplicate(true), battery = selected,
		esc = {kind = prop.esc.kind, command_mapping = prop.esc.command_mapping}}


static func config_for(session: Node) -> Dictionary:
	var config: Dictionary = WeatherAdapter.config_for(session)
	if config.is_empty(): return {}
	var prepared: Dictionary = snapshot(session.aircraft.model.propulsion)
	if prepared.is_empty(): return {}
	config.electric = prepared
	config.inertia = session.sim.inertia.duplicate()
	config.inverse = RB.inertia_inverse(config.inertia)
	return config


static func set_context(session: Node, native: Object, aux: PackedFloat64Array,
		inputs: PackedFloat64Array, at: float) -> bool:
	var d: Dictionary = session._deflections(aux)
	var deflections := PackedFloat64Array([d.elevator, d.aileron_right, d.aileron_left, d.rudder, d.get("flap", 0.0)])
	return native.set_tick_context(aux, inputs, deflections, at) \
		and native.set_power_context(session.propulsion_throttle(), session.propulsion_power_enabled())
