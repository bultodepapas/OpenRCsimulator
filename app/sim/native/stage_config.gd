## Canonical preparation projection of the committed fixed-wing session.
## Independent of native loading and session classes to avoid preload cycles.
extends RefCounted

const Propulsion := preload("res://physics/propulsion.gd")
const Turbine := preload("res://physics/turbine.gd")
const LakeSurface := preload("res://physics/lake_surface.gd")
const REFERENCE_STAGE_METHOD := &"_wheel_evaluate"


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
