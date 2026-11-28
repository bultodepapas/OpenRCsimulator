## Fixed-wing native preparation and control-deflection packing.
## Independent of native loading and session classes to avoid preload cycles.
extends RefCounted

const Propulsion := preload("res://physics/propulsion.gd")
const Turbine := preload("res://physics/turbine.gd")
const LakeSurface := preload("res://physics/lake_surface.gd")
const WindTurbulence := preload("res://physics/wind_turbulence.gd")
const REFERENCE_STAGE_METHOD := &"_wheel_evaluate"


## Fixed-wing ABI order. Callers own when servo deflections are sampled; each
## call returns a fresh packet, including the optional flap lane for ABI 2.
static func pack_deflections(deflections: Dictionary) -> PackedFloat64Array:
	return PackedFloat64Array([deflections.elevator, deflections.aileron_right,
		deflections.aileron_left, deflections.rudder, deflections.get("flap", 0.0)])


static func config_for(session: Node) -> Dictionary:
	var sim: Node = session.sim
	var model: Dictionary = session.aircraft.model
	var prop: Dictionary = model.propulsion
	var lake: Dictionary = session._lake
	var weather: RefCounted = session._weather
	var constants: Dictionary = session.get_script().get_script_constant_map()
	var stage_method: StringName = sim.model.stage.get_method() if sim.model.stage.is_valid() else &""
	return {
		model = model,
		gear = session.current_landing_gear(sim.aux),
		surfaces = session.ground_surfaces,
		lake = lake,
		lake_valid = lake.is_empty() or LakeSurface.is_valid_definition(lake),
		hull = session._hull_contact,
		soft_hull = session.soft_hull_contacts,
		density = session.air_density(),
		ground_effect_reach = session._ground_effect_reach,
		layout = {aux_size = sim.aux.size(), rpm = int(constants.get("AUX_RPM", -1)),
			servo = int(constants.get("AUX_SERVO", -1)), anchors = int(constants.get("AUX_ANCHORS", -1)),
			anchor_count = session.anchor_count(), downwash = session.downwash_index(),
			wheel_count = session.wheel_count(), rotor_index = session._rotor_index(), wheel_index = session.wheel_index(),
			brake_input = session.wheel_brake_input_index(), input_count = sim.inputs.size()},
		retractable = session.gear_is_retractable(), glow = session.glow_is_active(),
		coupled = session.shaft_is_coupled(), turbine = Turbine.is_turbine(prop) or session.turbine_is_continuous(),
		liquid = session.liquid_fuel_is_active(), finite_fuel = session.finite_fuel_is_active(),
		flaps = session.flaps_available(), spatial_weather = weather.is_spatial(),
		turbulence = weather.has_turbulence(), vertical_atmosphere = weather.has_vertical_atmosphere(),
		weather_pending_reset = session._weather_pending_reset, not_calm = not weather.is_calm(),
		slipstream = not prop.get("slipstream", {}).is_empty(),
		rotor_dynamics = Propulsion.has_rotor_dynamics(prop) or (sim.model.stage.is_valid() and stage_method != REFERENCE_STAGE_METHOD),
	}


## NK-5g: the fixed inputs of FlightSession._pre_step that the native pre-step reads besides its prepared stage. Each
## value comes from the guarded aircraft, shaft integrator, lake or weather. The native preparation checks the layout
## against the stage it extends and refuses anything it cannot reproduce.
static func pre_step_config_for(session: Node) -> Dictionary:
	var model: Dictionary = session.aircraft.model
	var prop: Dictionary = model.propulsion
	var flaps_on: bool = session.flaps_available()
	var flaps: Dictionary = model.get("flaps", {}) if flaps_on else {}
	var weather: RefCounted = session._weather
	var turbulent: bool = weather.has_turbulence()
	var config := {
		servo_rate = model.controls.servo_rate,
		rpm_passthrough = session.shaft_is_coupled() or session.turbine_is_continuous(),
		rpm_turbine = Turbine.is_turbine(prop), rpm_shaft = Propulsion.has_shaft(prop),
		flaps = flaps_on,
		# Flaps.advance reads float(config.get(key, 1.5)); the manual mix reads the fraction itself.
		flap_extension_time = flaps.get("extension_time", 1.5), flap_retraction_time = flaps.get("retraction_time", 1.5),
		flap_elevator_mix = flaps.get("elevator_mix_per_flap_fraction", NAN),
		flap_aux = session.flap_aux_index(), flap_input = session.flap_input_index(),
		retractable = session.gear_is_retractable(), input_count = session._input_count(),
		lake_present = not session._lake.is_empty(),
		# FlightSession._gear_weight_on_wheels' threshold in its own spelling: the engine parses both alike.
		weight_on_wheels_threshold = 1.0e-5,
		downwash_length = model.get("surfaces", {}).get("horizontal", {}).get("downwash_lag_length", NAN),
		turbulence = turbulent, turbulence_index = session.turbulence_index() if turbulent else -1,
		turbulence_sigma = weather.turbulence_rms() if turbulent else PackedFloat64Array(),
		turbulence_tau = weather.turbulence_tau() if turbulent else 0.0,
		turbulence_seed = weather.turbulence_seed() if turbulent else 0,
		turbulence_uniform_denominator = WindTurbulence.UINT53_DENOMINATOR,
		turbulence_max_uniform = WindTurbulence.MAX_OPEN_UNIFORM,
	}
	# Propulsion.rpm_step reads prop.idle_rpm, prop.max_rpm and prop.lag; only that branch needs them.
	if prop.has("idle_rpm") and prop.has("max_rpm") and prop.has("lag"):
		config.idle_rpm = prop.idle_rpm
		config.max_rpm = prop.max_rpm
		config.rpm_lag = prop.lag
	return config
