## NK-3 research adapter for a detached, validated weather-provider snapshot.
## Called at preparation boundaries only; native RK stages never call the field.
extends RefCounted

const NativeStage := preload("res://sim/native_stage.gd")
const WeatherConfig := preload("res://physics/wind_config.gd")
const WeatherField := preload("res://physics/wind_field.gd")
const SpatialField := preload("res://physics/wind_spatial_field.gd")
const ThermalField := preload("res://physics/wind_thermal_field.gd")
const SimEnvironment := preload("res://sim/environment.gd")


static func _field_inputs(field: RefCounted) -> Dictionary:
	var out := {}
	for key: String in ["_atmosphere", "_atmosphere_active", "_vertical_air", "_rho", "_engine_charge",
			"_mean_ned", "_gust_ned", "_gust_duration_s", "_gust_period_s", "_gust_delay_s", "_has_gust",
			"_calm", "_turbulent", "_turbulence_rms", "_turbulence_tau", "_turbulence_seed"]:
		out[key] = field.get(key)
	return out


static func _spatial_inputs(field: RefCounted) -> Dictionary:
	var out := {}
	for key: String in ["_reference_speed", "_roughness_length", "_displacement_height", "_wall_height",
			"_surface_top", "_free_air_join_height", "_direction_cosine", "_direction_sine", "_log_denominator",
			"_wall_scale", "_wall_scale_slope", "_gust_transition_height", "_gust_values", "_gust_max_duration",
			"_turbulence_rms", "_modes"]:
		out[key] = field.get(key)
	return out


## Capture object identities and detached configuration; the actual turbulence
## Callable must be FlightSession's sampler, not an arbitrary replacement.
static func provider_identity(session: Node) -> Dictionary:
	if session == null or session.get("sim") == null:
		return {ok = false, reason = "session or simulation unavailable"}
	var environment: Variant = session.get("environment")
	if environment == null or not is_instance_valid(environment) or environment.get_script() != SimEnvironment:
		return {ok = false, reason = "environment is not the built-in provider"}
	var field: Variant = environment.get("weather")
	if field == null or not is_instance_valid(field) or field.get_script() != WeatherField:
		return {ok = false, reason = "weather is not the built-in provider"}
	var turbulence: Callable = environment.get("turbulence")
	if turbulence != Callable(session, "_turbulence_noise"):
		return {ok = false, reason = "turbulence callback differs from the session owner"}
	if session._weather_pending_reset:
		return {ok = false, reason = "pending weather requires reset"}
	var dt: float = session.sim.dt()
	if not is_finite(dt) or dt <= 0.0:
		return {ok = false, reason = "invalid tick duration"}
	var config: Dictionary = field.configuration()
	var validated: Dictionary = WeatherConfig.validate(config)
	if not validated.ok or validated.config != config:
		return {ok = false, reason = "weather configuration is not validated and canonical"}
	var index: int = session.turbulence_index() if field.has_turbulence() else -1
	if field.has_turbulence() and (index < 4 or session._turbulence_aux_index != index \
			or session.sim.aux.size() != index + 7):
		return {ok = false, reason = "session turbulence layout differs from the provider"}
	var spatial: Variant = field.get("_spatial")
	var thermal: Variant = null
	if field.is_spatial():
		if spatial == null or not is_instance_valid(spatial) or spatial.get_script() != SpatialField:
			return {ok = false, reason = "spatial weather is not the built-in provider"}
		if var_to_bytes(spatial.configuration()) != var_to_bytes(config.spatial_wind):
			return {ok = false, reason = "spatial provider configuration differs from the weather field"}
		thermal = spatial.get("_thermal_field")
		var has_thermal: bool = config.spatial_wind.get("format") == "openrc-spatial-wind v2"
		if has_thermal != (thermal != null) \
				or (thermal != null and (not is_instance_valid(thermal) or thermal.get_script() != ThermalField)):
			return {ok = false, reason = "thermal weather provider differs from its configuration"}
		if thermal != null and var_to_bytes(thermal.configuration()) != var_to_bytes(config.spatial_wind.thermal_field):
			return {ok = false, reason = "thermal provider configuration differs from the weather field"}
	elif spatial != null:
		return {ok = false, reason = "unexpected spatial weather provider"}
	# GDScript fields are logically immutable but can be reached through Object.get/set.
	# Rebuild once at this boundary to refuse changed cached values or seeded modes.
	var rebuilt: Dictionary = WeatherField.build(config)
	if not rebuilt.ok or var_to_bytes(_field_inputs(field)) != var_to_bytes(_field_inputs(rebuilt.field)) \
			or (spatial != null and var_to_bytes(_spatial_inputs(spatial)) \
				!= var_to_bytes(_spatial_inputs(rebuilt.field.get("_spatial")))) \
			or var_to_bytes(snapshot(field)) != var_to_bytes(snapshot(rebuilt.field)):
		return {ok = false, reason = "prepared weather values differ from their validated configuration"}
	return {ok = true, environment = environment, field = field, spatial = spatial, thermal = thermal,
		turbulence = turbulence, configuration = config, dt = dt, turbulence_index = index,
		field_inputs = _field_inputs(field), prepared_snapshot = snapshot(field)}


## Used only at owner boundaries: checks that the prepared provider and callback
## still belong to the session. Do not call this in the native RK evaluator.
static func provider_matches(session: Node, identity: Dictionary) -> bool:
	if not identity.get("ok", false):
		return false
	var current := provider_identity(session)
	return current.get("ok", false) and current.environment == identity.environment \
		and current.field == identity.field and current.spatial == identity.spatial and current.thermal == identity.thermal \
		and current.turbulence == identity.turbulence and current.configuration == identity.configuration \
		and current.dt == identity.dt and current.turbulence_index == identity.turbulence_index \
		and var_to_bytes(current.field_inputs) == var_to_bytes(identity.field_inputs) \
		and var_to_bytes(current.prepared_snapshot) == var_to_bytes(identity.prepared_snapshot)


## HelicopterFlightSession has a distinct contract: its current setup refuses
## spatial wind, column atmosphere and OU turbulence and supplies no callback.
## Do not manufacture the fixed-wing owner's pending-reset or OU layout here.
static func helicopter_provider_identity(session: Node) -> Dictionary:
	if session == null or not is_instance_valid(session) \
			or session.get_script() != load("res://sim/helicopter_flight_session.gd") or session.sim == null:
		return {ok = false, reason = "unsupported helicopter session"}
	if not session._ready_to_fly:
		return {ok = false, reason = "helicopter has no completed reset"}
	var environment: Variant = session.environment
	if environment == null or not is_instance_valid(environment) or environment.get_script() != SimEnvironment:
		return {ok = false, reason = "environment is not the built-in provider"}
	var field: Variant = environment.weather
	if field == null or not is_instance_valid(field) or field.get_script() != WeatherField:
		return {ok = false, reason = "weather is not the built-in provider"}
	var turbulence: Callable = environment.turbulence
	if turbulence != Callable() or field.is_spatial() or field.has_turbulence() or field.has_vertical_atmosphere():
		return {ok = false, reason = "helicopter weather requires uniform wind and no turbulence callback"}
	var dt: float = session.sim.dt()
	if not is_finite(dt) or dt <= 0.0 or session.sim.aux.size() != 1 or session.sim.model.aux_size != 1:
		return {ok = false, reason = "invalid helicopter tick duration or auxiliary layout"}
	var config: Dictionary = field.configuration()
	var checked: Dictionary = WeatherConfig.validate(config)
	if not checked.ok or var_to_bytes(checked.config) != var_to_bytes(config):
		return {ok = false, reason = "weather configuration is not validated and canonical"}
	var rebuilt: Dictionary = WeatherField.build(config)
	if not rebuilt.ok or var_to_bytes(_field_inputs(field)) != var_to_bytes(_field_inputs(rebuilt.field)) \
			or var_to_bytes(snapshot(field)) != var_to_bytes(snapshot(rebuilt.field)):
		return {ok = false, reason = "prepared weather values differ from their validated configuration"}
	return {ok = true, environment = environment, field = field, spatial = null, thermal = null,
		turbulence = turbulence, configuration = config, dt = dt, turbulence_index = -1,
		field_inputs = _field_inputs(field), prepared_snapshot = snapshot(field)}


## Exact detached provider coefficients: temporal RNG is separately owned by
## FlightSession; spatial modes are copied from the already resolved field.
static func snapshot(field: RefCounted) -> Dictionary:
	var config: Dictionary = field.configuration()
	var out := {format = "openrc-nk3-weather-snapshot-v1", kind = "spatial" if field.is_spatial() else "uniform",
		vertical_atmosphere = field.has_vertical_atmosphere(), has_turbulence = field.has_turbulence(),
		temperature_k = float((field.get("_atmosphere") as Dictionary).temperature_k),
		atmosphere = PackedFloat64Array([float(config.get("field_elevation_m", 0.0)),
			field.air_density(), field.engine_charge_ratio()])}
	if not field.is_spatial():
		out.uniform = PackedFloat64Array([float(config.speed_mps), float(config.from_deg), float(config.gust_mps),
			float(config.gust_up_mps), float(config.gust_duration_s), float(config.gust_period_s), float(config.gust_delay_s)])
		return out
	var provider: RefCounted = field.get("_spatial")
	var spatial: Dictionary = config.spatial_wind
	var domain: Dictionary = spatial.domain
	var profile: Dictionary = spatial.profile
	var free_air: Array = profile.free_air_wind_ned_mps
	var layers := PackedFloat64Array()
	for layer: Dictionary in profile.layers:
		layers.append_array(PackedFloat64Array([float(layer.center_agl_m), float(layer.half_thickness_m),
			float(layer.delta_wind_ned_mps[0]), float(layer.delta_wind_ned_mps[1])]))
	var thermal := {}
	if provider.get("_thermal_field") != null:
		var source: Dictionary = spatial.thermal_field
		var thermal_domain: Dictionary = source.domain
		var cells := PackedFloat64Array()
		for cell: Dictionary in source.cells:
			cells.append_array(PackedFloat64Array([float(cell.birth_s), float(cell.duration_s), float(cell.center_ne_m[0]),
				float(cell.center_ne_m[1]), float(cell.drift_ne_mps[0]), float(cell.drift_ne_mps[1]),
				float(cell.radius_m), float(cell.top_agl_m), float(cell.peak_updraft_mps)]))
		thermal = {domain = PackedFloat64Array([float(thermal_domain.half_extent_north_m),
			float(thermal_domain.half_extent_east_m), float(thermal_domain.max_height_agl_m),
			float(thermal_domain.time_horizon_s), float(source.identity.epoch_offset_s)]), cells = cells}
	out.spatial = {
		domain = PackedFloat64Array([float(domain.half_extent_north_m), float(domain.half_extent_east_m),
			float(domain.max_height_agl_m), float(domain.time_horizon_s), float(domain.ground_extension_m),
			float(spatial.identity.epoch_offset_s), float(domain.ground_transition_height_m)]),
		profile = PackedFloat64Array([float(provider.get("_reference_speed")), float(provider.get("_roughness_length")),
			float(provider.get("_displacement_height")), float(provider.get("_wall_height")),
			float(provider.get("_surface_top")), float(provider.get("_free_air_join_height")),
			float(provider.get("_direction_cosine")), float(provider.get("_direction_sine")),
			float(provider.get("_log_denominator")), float(provider.get("_wall_scale")),
			float(provider.get("_wall_scale_slope")), float(free_air[0]), float(free_air[1]), float(free_air[2])]),
		layers = layers, gust_values = (provider.get("_gust_values") as PackedFloat64Array).duplicate(),
		gust_max_duration = float(provider.get("_gust_max_duration")),
		turbulence_rms = float(provider.get("_turbulence_rms")),
		modes = (provider.get("_modes") as PackedFloat64Array).duplicate(), thermal = thermal,
	}
	return out


## The normal NativeStage capability flags remain honest and unchanged. A
## successful decoder explicitly admits each newly ported weather capability.
static func config_for(session: Node) -> Dictionary:
	var identity := provider_identity(session)
	if not identity.get("ok", false):
		return {}
	var config: Dictionary = NativeStage.config_for(session)
	config.weather = identity.prepared_snapshot.duplicate(true)
	config.dt = identity.dt
	config.layout.turbulence = identity.turbulence_index
	return config
