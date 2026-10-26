## Immutable, deterministic spatial NED wind field built from a resolved config.
## It has no scene-tree, aircraft, RNG-at-query, or mutable-clock dependency.
class_name WindSpatialField
extends RefCounted

const Config := preload("res://physics/wind_spatial_config.gd")
const ThermalField := preload("res://physics/wind_thermal_field.gd")
const TAU_F64 := 6.283185307179586476925286766559
const U32_MASK := 0xffffffff
const U32_SCALE := 4294967296.0

var _config: Dictionary = {}
var _content_hash := ""
var _modes: Array[Dictionary] = []
var _rng_state: int = 0
var _thermal_field: Variant = null
var _thermal_content_hash := ""
var _thermal_law := ""


## Validate, detach, and freeze a spatial provider. A failure never yields a zero-wind fallback.
static func build(raw: Variant) -> Dictionary:
	var checked: Dictionary = Config.resolve(raw)
	if not checked.ok:
		return {"ok": false, "field": null, "errors": checked.errors}
	var thermal_field: Variant = null
	var thermal_content_hash := ""
	var thermal_law := ""
	if checked.config.format == Config.FORMAT_V2:
		var thermal_built: Dictionary = ThermalField.build(checked.config.thermal_field)
		if not thermal_built.ok:
			return {"ok": false, "field": null, "errors": thermal_built.errors}
		thermal_field = thermal_built.field
		thermal_content_hash = str(checked.thermal_content_hash)
		thermal_law = str(checked.thermal_law)
	var script: Script = load("res://physics/wind_spatial_field.gd")
	var field: Variant = script.new()
	field.call("_apply_config", checked.config, checked.content_hash, thermal_field, thermal_content_hash, thermal_law)
	return {"ok": true, "field": field, "errors": PackedStringArray()}


func _apply_config(config: Dictionary, content_hash: String, thermal_field: Variant, thermal_content_hash: String, thermal_law: String) -> void:
	_config = config.duplicate(true)
	_content_hash = content_hash
	_thermal_field = thermal_field
	_thermal_content_hash = thermal_content_hash
	_thermal_law = thermal_law
	_modes = _resolve_modes()


## A detached canonical schema object. Mutating the return value cannot change this field.
func configuration() -> Dictionary:
	return _config.duplicate(true)


func content_hash() -> String:
	return _content_hash


## Complete separately canonicalized thermal agenda identity for v2 receipts.
func thermal_content_hash() -> String:
	return _thermal_content_hash


func thermal_law() -> String:
	return _thermal_law


func has_thermal_field() -> bool:
	return _thermal_field != null


func identity() -> Dictionary:
	return _config.identity.duplicate(true)


## The v1 provider is always spatial, including a zero-amplitude configuration.
func is_spatial() -> bool:
	return true


## This is an authored nominal target. Wall taper and finite realization change local RMS.
func nominal_turbulence_rms_mps() -> float:
	return float(_config.turbulence.rms_mps)


## Conservative global bound from the validated profile/layer/event/mode limits.
## This is a mathematical envelope, not a statement about atmospheric plausibility.
func absolute_speed_bound_mps() -> float:
	var profile: Dictionary = _config.profile
	var z0 := float(profile.roughness_length_m)
	var displacement := float(profile.displacement_height_m)
	var reference_height := float(profile.reference_height_agl_m)
	var upper_join_end := float(profile.surface_layer_top_agl_m) + float(profile.free_air_join_height_m)
	var log_denominator := log((reference_height - displacement) / z0)
	var log_speed := float(profile.reference_speed_mps) * log((upper_join_end - displacement) / z0) / log_denominator
	var free_air: Array = profile.free_air_wind_ned_mps
	var free_air_speed := sqrt(float(free_air[0]) * float(free_air[0]) + float(free_air[1]) * float(free_air[1]))
	var bound := maxf(log_speed, free_air_speed)
	for layer: Dictionary in profile.layers:
		var delta: Array = layer.delta_wind_ned_mps
		var layer_bound := sqrt(float(delta[0]) * float(delta[0]) + float(delta[1]) * float(delta[1]))
		bound += layer_bound
	if not _config.gusts.events.is_empty():
		bound += 8.0
	var rms := float(_config.turbulence.rms_mps)
	var count := float(_config.turbulence.mode_count)
	bound += 2.0 * (1.0 + 1.875 / TAU_F64) * rms * sqrt(count)
	if _thermal_field != null:
		bound += float(_thermal_field.absolute_speed_bound_mps())
	return bound


## Evaluate at a world point [north, east, down] and caller simulation seconds.
## Returns a structured failure outside the declared flat-site domain.
func sample_world(position_ned: PackedFloat64Array, simulation_time_s: float) -> Dictionary:
	if position_ned.size() != 3:
		return _sample_failure("position_ned must contain exactly three NED components")
	for component: float in position_ned:
		if not is_finite(component):
			return _sample_failure("position_ned must contain only finite numbers")
	if not is_finite(simulation_time_s) or simulation_time_s < 0.0:
		return _sample_failure("simulation_time_s must be finite and nonnegative")
	var domain: Dictionary = _config.domain
	if absf(position_ned[0]) > float(domain.half_extent_north_m):
		return _sample_failure("north position is outside the declared flat-site domain")
	if absf(position_ned[1]) > float(domain.half_extent_east_m):
		return _sample_failure("east position is outside the declared flat-site domain")
	if simulation_time_s > float(domain.time_horizon_s):
		return _sample_failure("simulation time is outside the declared horizon")
	var epoch_time := simulation_time_s + float(_config.identity.epoch_offset_s)
	if not is_finite(epoch_time) or epoch_time > float(domain.time_horizon_s):
		return _sample_failure("world epoch time is outside the declared horizon")
	var height_agl := -position_ned[2]
	if height_agl < -float(domain.ground_extension_m):
		return _sample_failure("position is below the declared flat-site ground extension")
	if height_agl > float(domain.max_height_agl_m):
		return _sample_failure("position is above domain.max_height_agl_m")
	# The extension inside solid ground is exactly zero. Every component is C1-zero at the wall.
	if height_agl <= 0.0:
		return _sample_success(PackedFloat64Array([0.0, 0.0, 0.0]))

	var wind := _profile_wind(height_agl)
	var gust := _gust_wind(height_agl, epoch_time)
	var turbulent := _turbulence_wind(position_ned[0], position_ned[1], height_agl, epoch_time)
	for axis: int in 3:
		wind[axis] += gust[axis] + turbulent[axis]
		if not is_finite(wind[axis]):
			return _sample_failure("spatial field evaluation overflowed")
	if _thermal_field != null:
		var thermal_sample: Dictionary = _thermal_field.sample_world(position_ned, simulation_time_s)
		if not thermal_sample.ok:
			return _sample_failure("thermal field sample failed: %s" % str(thermal_sample.error))
		var thermal_wind: PackedFloat64Array = thermal_sample.wind_ned_mps
		for axis: int in 3:
			wind[axis] += thermal_wind[axis]
			if not is_finite(wind[axis]):
				return _sample_failure("combined spatial and thermal field evaluation overflowed")
	return _sample_success(wind)


func _profile_wind(height_agl: float) -> PackedFloat64Array:
	var profile: Dictionary = _config.profile
	var result: PackedFloat64Array
	var wall := float(profile.wall_join_height_agl_m)
	var surface_top := float(profile.surface_layer_top_agl_m)
	if height_agl < wall:
		result = _wall_join(height_agl)
	elif height_agl <= surface_top:
		result = _neutral_profile(height_agl)
	else:
		var fraction := (height_agl - surface_top) / float(profile.free_air_join_height_m)
		fraction = clampf(fraction, 0.0, 1.0)
		if fraction >= 1.0:
			result = PackedFloat64Array(profile.free_air_wind_ned_mps)
		else:
			var weight := _smooth5(fraction)
			var neutral := _neutral_profile(height_agl)
			# Convex blend from the log law to a constant free-air vector. Evaluating the
			# neutral law through the join preserves its entering slope; the quintic weight
			# has zero endpoint slope, so both ends are C1 and the blend remains bounded.
			result = PackedFloat64Array([
				neutral[0] * (1.0 - weight) + float(profile.free_air_wind_ned_mps[0]) * weight,
				neutral[1] * (1.0 - weight) + float(profile.free_air_wind_ned_mps[1]) * weight,
				0.0,
			])
	for layer: Dictionary in profile.layers:
		var normalized := absf(height_agl - float(layer.center_agl_m)) / float(layer.half_thickness_m)
		if normalized >= 1.0:
			continue
		var weight := 1.0 - _smooth5(normalized)
		var delta: Array = layer.delta_wind_ned_mps
		result[0] += float(delta[0]) * weight
		result[1] += float(delta[1]) * weight
	return result


func _neutral_profile(height_agl: float) -> PackedFloat64Array:
	var profile: Dictionary = _config.profile
	var reference_speed := float(profile.reference_speed_mps)
	if reference_speed == 0.0:
		return PackedFloat64Array([0.0, 0.0, 0.0])
	var reference_height := float(profile.reference_height_agl_m)
	var z0 := float(profile.roughness_length_m)
	var displacement := float(profile.displacement_height_m)
	var denominator := log((reference_height - displacement) / z0)
	var scale := log((height_agl - displacement) / z0) / denominator
	var radians := deg_to_rad(float(profile.reference_from_deg))
	var north := -reference_speed * cos(radians) * scale
	var east := -reference_speed * sin(radians) * scale
	return PackedFloat64Array([north, east, 0.0])


func _wall_join(height_agl: float) -> PackedFloat64Array:
	var profile: Dictionary = _config.profile
	var wall := float(profile.wall_join_height_agl_m)
	var reference_speed := float(profile.reference_speed_mps)
	if height_agl <= 0.0 or reference_speed == 0.0:
		return PackedFloat64Array([0.0, 0.0, 0.0])
	var reference_height := float(profile.reference_height_agl_m)
	var z0 := float(profile.roughness_length_m)
	var displacement := float(profile.displacement_height_m)
	var denominator := log((reference_height - displacement) / z0)
	var wall_log := log((wall - displacement) / z0)
	var scale_at_wall := wall_log / denominator
	var scale_slope_at_wall := 1.0 / ((wall - displacement) * denominator)
	var radians := deg_to_rad(float(profile.reference_from_deg))
	var unit_north := -cos(radians)
	var unit_east := -sin(radians)
	var s := clampf(height_agl / wall, 0.0, 1.0)
	var h01 := -2.0 * s * s * s + 3.0 * s * s
	var h11 := s * s * s - s * s
	var north := reference_speed * unit_north * (h01 * scale_at_wall + h11 * wall * scale_slope_at_wall)
	var east := reference_speed * unit_east * (h01 * scale_at_wall + h11 * wall * scale_slope_at_wall)
	return PackedFloat64Array([north, east, 0.0])


func _gust_wind(height_agl: float, epoch_time: float) -> PackedFloat64Array:
	var result := PackedFloat64Array([0.0, 0.0, 0.0])
	var transition := float(_config.domain.ground_transition_height_m)
	var wall_weight := _smooth5(clampf(height_agl / transition, 0.0, 1.0))
	for event: Dictionary in _config.gusts.events:
		var start := float(event.start_s)
		var duration := float(event.duration_s)
		var elapsed := epoch_time - start
		if elapsed < 0.0 or elapsed >= duration:
			continue
		var s := elapsed / duration
		var one_minus_s := 1.0 - s
		# Compact C2 bell: zero value, slope, and curvature at both event endpoints.
		var pulse := 64.0 * s * s * s * one_minus_s * one_minus_s * one_minus_s
		var amplitude: Array = event.amplitude_ned_mps
		result[0] += float(amplitude[0]) * pulse * wall_weight
		result[1] += float(amplitude[1]) * pulse * wall_weight
	return result


func _turbulence_wind(north_m: float, east_m: float, height_agl: float, epoch_time: float) -> PackedFloat64Array:
	var result := PackedFloat64Array([0.0, 0.0, 0.0])
	if float(_config.turbulence.rms_mps) == 0.0:
		return result
	for mode: Dictionary in _modes:
		var spatial_phase := float(mode.k_n) * north_m + float(mode.k_e) * east_m + float(mode.phase)
		var temporal_phase := float(mode.omega) * epoch_time
		var phase := fposmod(fposmod(spatial_phase, TAU_F64) + fposmod(temporal_phase, TAU_F64), TAU_F64)
		var cosine_phase := cos(phase)
		var sine_phase := sin(phase)
		var vertical_phase := float(mode.k_down) * height_agl
		var sine_vertical := sin(vertical_phase)
		var cosine_vertical := cos(vertical_phase)
		# A per-mode C2 potential taper reaches one over one vertical wavelength.
		# Its derivative is bounded by 1.875*k_down/TAU and is zero at ground.
		var wall_fraction := clampf(vertical_phase / TAU_F64, 0.0, 1.0)
		var wall_weight := _smooth5(wall_fraction)
		var wall_derivative := 0.0
		if wall_fraction > 0.0 and wall_fraction < 1.0:
			wall_derivative = _smooth5_derivative(wall_fraction) * float(mode.k_down) / TAU_F64
		var potential_height := wall_weight * sine_vertical
		var potential_height_derivative := wall_derivative * sine_vertical + wall_weight * float(mode.k_down) * cosine_vertical
		var amplitude := float(mode.potential_amplitude)
		var horizontal_derivative := amplitude * potential_height_derivative * cosine_phase
		var vertical_velocity := amplitude * potential_height * float(mode.cross_wavenumber) * sine_phase
		result[0] += float(mode.axis_east) * horizontal_derivative
		result[1] -= float(mode.axis_north) * horizontal_derivative
		result[2] += vertical_velocity
	return result


func _resolve_modes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var turbulence: Dictionary = _config.turbulence
	var count := int(turbulence.mode_count)
	if count <= 0:
		return result
	var identity: Dictionary = _config.identity
	var seed := int(identity.seed_u32)
	var epoch_id := int(identity.world_epoch_id_u32)
	_rng_state = (seed ^ ((epoch_id * 1664525 + 1013904223) & U32_MASK)) & U32_MASK
	if _rng_state == 0:
		_rng_state = 1831565813
	var rms := float(turbulence.rms_mps)
	var min_wavelength := float(turbulence.min_wavelength_m)
	var max_wavelength := float(turbulence.max_wavelength_m)
	var coherence := float(turbulence.coherence_time_s)
	var profile: Dictionary = _config.profile
	var reference_radians := deg_to_rad(float(profile.reference_from_deg))
	var reference_north := -float(profile.reference_speed_mps) * cos(reference_radians)
	var reference_east := -float(profile.reference_speed_mps) * sin(reference_radians)
	for index: int in count:
		# Stratified log-wavelength selection avoids accidental clusters while remaining seed-specific.
		var jitter := _random_unit() - 0.5
		var stratum := clampf((float(index) + 0.5 + 0.75 * jitter) / float(count), 0.0, 1.0)
		var wavelength := min_wavelength * pow(max_wavelength / min_wavelength, stratum)
		var wavenumber := TAU_F64 / wavelength
		var vertical_share := 0.5 + 0.5 * _random_unit()
		var k_down := wavenumber * vertical_share
		var k_horizontal := wavenumber * sqrt(maxf(0.0, 1.0 - vertical_share * vertical_share))
		var wave_angle := TAU_F64 * _random_unit()
		var k_north := k_horizontal * cos(wave_angle)
		var k_east := k_horizontal * sin(wave_angle)
		var axis_angle := TAU_F64 * _random_unit()
		var axis_north := cos(axis_angle)
		var axis_east := sin(axis_angle)
		var cross_wavenumber := -axis_east * k_north + axis_north * k_east
		var variance_wavenumber := sqrt(k_down * k_down + cross_wavenumber * cross_wavenumber)
		var potential_amplitude := 0.0
		if rms > 0.0 and variance_wavenumber > 0.0:
			# Each independent phase contributes nominal variance rms^2 / N before wall taper.
			potential_amplitude = 2.0 * rms / sqrt(float(count)) / variance_wavenumber
		var phase := TAU_F64 * _random_unit()
		var sign := -1.0 if _random_unit() < 0.5 else 1.0
		var intrinsic_omega := sign * TAU_F64 / coherence * (0.5 + _random_unit())
		# Frozen-reference advection keeps the same Eulerian world field moving with
		# the declared reference mean, without height-sliced aircraft-speed advection.
		var omega := intrinsic_omega - k_north * reference_north - k_east * reference_east
		result.append({
			"k_n": k_north,
			"k_e": k_east,
			"k_down": k_down,
			"axis_north": axis_north,
			"axis_east": axis_east,
			"cross_wavenumber": cross_wavenumber,
			"potential_amplitude": potential_amplitude,
			"phase": phase,
			"omega": omega,
		})
	return result


func _random_unit() -> float:
	var value := _rng_state
	value = (value ^ (value << 13)) & U32_MASK
	value = (value ^ (value >> 17)) & U32_MASK
	value = (value ^ (value << 5)) & U32_MASK
	_rng_state = value
	return float(value) / U32_SCALE


func _smooth5(value: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	return x * x * x * (10.0 + x * (-15.0 + 6.0 * x))


func _smooth5_derivative(value: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	return 30.0 * x * x * (1.0 - x) * (1.0 - x)


func _sample_success(wind: PackedFloat64Array) -> Dictionary:
	return {"ok": true, "wind_ned_mps": wind, "error": ""}


func _sample_failure(message: String) -> Dictionary:
	return {"ok": false, "wind_ned_mps": PackedFloat64Array(), "error": message}
