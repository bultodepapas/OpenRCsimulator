## Research-only native Glow stage preparation. The session retains pre_tick,
## source-mode and accepted-step event policy; this installs no app backend.
extends RefCounted

const WeatherAdapter := preload("weather_adapter.gd")

const MASS_FIELDS := ["reference_mass_kg", "reference_inertia_kgm2", "references", "capacities", "centers", "tensors"]
const BLADE_FIELDS := ["diameter_m", "pitch_m", "chord_m", "lift_slope", "cd0", "induced_drag", "blades"]
const THERMAL_FIELDS := ["heat_capacity_j_k", "head_heat_fraction", "cooling_base_w_k",
	"cooling_airflow_w_s_m_k", "premix_evaporation_j_kg", "evaporation_head_fraction"]
const LIFECYCLE_FIELDS := ["idle_opening", "servo_time_constant_s", "air_time_constant_s", "fuel_transport_time_constant_s",
	"lean_misfire_zero_ratio", "lean_misfire_start_ratio", "rich_misfire_start_ratio", "rich_misfire_zero_ratio",
	"temperature_firing_min_k", "temperature_firing_full_k", "temperature_firing_hot_full_k", "temperature_firing_hot_zero_k"]


static func snapshot(install: Dictionary) -> Dictionary:
	var profile: Dictionary = install.profile
	var p: Dictionary = profile.parameters
	var two: bool = profile.family == "glow_2t"
	var source := {family = profile.family, max_rpm = profile.operation.max_rpm, displacement_m3 = p.displacement_m3,
		oil_fraction = p.oil_fraction, stoich_air_fuel_ratio = p.stoich_air_fuel_ratio, fuel_lhv_j_kg = p.fuel_lhv_j_kg,
		breathing = p.delivery_ratio if two else p.volumetric_efficiency,
		pumping_pressure = p.scavenge_pressure_pa if two else p.pumping_pressure_pa,
		mechanical_torque_nm = p.mechanical_torque_nm, combustion_efficiency = p.combustion_efficiency,
		indicated_efficiency = p.indicated_efficiency}
	if two: source.trapping_efficiency = p.trapping_efficiency
	else:
		source.intake_pressure_drop_pa = p.intake_pressure_drop_pa
		source.valve_torque_nm = p.valve_torque_nm
	var blade := {}
	for field: String in BLADE_FIELDS: blade[field] = install.propeller[field]
	if install.propeller.has("zero_lift_angle_rad"):
		blade.zero_lift_angle_rad = install.propeller.zero_lift_angle_rad
	var mass := {}
	for field: String in MASS_FIELDS: mass[field] = install.mass_reference[field]
	var settings: Dictionary = install.settings
	var thermal := {}
	for field: String in THERMAL_FIELDS: thermal[field] = settings.thermal[field]
	var life := {nominal_mixture = profile.operation.nominal_mixture, idle_offset = install.throttle_idle_offset,
		travel_exponent = settings.throttle_travel_exponent, throttle_capacity_m3_s = install.throttle_capacity_m3_s,
		thermal = thermal}
	for field: String in LIFECYCLE_FIELDS: life[field] = settings[field]
	var has_line: bool = install.has("feed_line")
	var line_capacity: float = float(install.feed_line.capacity_kg) if has_line else 0.0
	var out := {format = "openrc-nk3-glow-component-v1", source = source, blade = blade, mass = mass,
		lifecycle = life, store = {main_capacity_kg = install.capacity_fuel_kg, unusable_kg = install.unusable_fuel_kg,
			has_line = has_line, line_capacity_kg = line_capacity}}
	if install.has("fuel_feed"):
		var feed: Dictionary = install.fuel_feed
		out.feed = {carburetor_body_m = feed.carburetor_body_m, tank_center_body_m = install.tank_position,
			tank_size_body_m = install.tank_size, density_kg_m3 = feed.density_kg_m3,
			idle_drive_pressure_pa = feed.idle_drive_pressure_pa, wot_drive_pressure_pa = feed.wot_drive_pressure_pa,
			rated_rpm = feed.rated_rpm}
		if install.has("pickup_position"): out.feed.pickup_body_m = install.pickup_position
	return out


static func config_for(session: Node) -> Dictionary:
	var config: Dictionary = WeatherAdapter.config_for(session)
	if config.is_empty(): return {}
	config.glow_snapshot = snapshot(session.aircraft.model.propulsion.glow)
	config.gravity = session.sim.gravity
	return config


static func set_context(session: Node, native: Object, aux: PackedFloat64Array,
		inputs: PackedFloat64Array, at: float) -> bool:
	var d: Dictionary = session._deflections(aux)
	var deflections := PackedFloat64Array([d.elevator, d.aileron_right, d.aileron_left, d.rudder, d.get("flap", 0.0)])
	return native.set_tick_context(aux, inputs, deflections, at) \
		and native.set_glow_context(session.propulsion_throttle(), session.engine_running, session.failure_power_cut_active())
