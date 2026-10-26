## Strict, detached schema for the opt-in spatial wind provider.
## This schema is nested in a future openrc-weather v5 document; legacy weather stays separate.
class_name WindSpatialConfig
extends RefCounted

const FORMAT := "openrc-spatial-wind v1"
const FORMAT_V2 := "openrc-spatial-wind v2"
const FRAME := "NED"
const DATUM_LAW := "flat-site-ground-plane-v1"
const PROFILE_LAW := "neutral-log-flat-site-c1-wall-v1"
const GUST_LAW := "resolved-degree6-c2-bell-uniform-v1"
const TURBULENCE_LAW := "finite-equal-variance-log-wavelength-vector-potential-frozen-reference-advection-flat-wall-v1"
const SEED_ALGORITHM := "xorshift32-v1"

const ROOT_KEYS := ["format", "identity", "frame", "datum", "domain", "profile", "gusts", "turbulence"]
const ROOT_KEYS_V2 := ["format", "identity", "frame", "datum", "domain", "profile", "gusts", "turbulence", "thermal_field"]
const IDENTITY_KEYS := ["seed_u32", "world_epoch_id_u32", "epoch_offset_s", "seed_algorithm"]
const DATUM_KEYS := ["law", "ground_down_m"]
const DOMAIN_KEYS := [
	"half_extent_north_m", "half_extent_east_m", "max_height_agl_m", "time_horizon_s",
	"ground_extension_m", "ground_transition_height_m",
]
const PROFILE_KEYS := [
	"law", "reference_speed_mps", "reference_from_deg", "reference_height_agl_m",
	"roughness_length_m", "displacement_height_m", "wall_join_height_agl_m",
	"surface_layer_top_agl_m", "free_air_join_height_m", "free_air_wind_ned_mps", "layers",
]
const LAYER_KEYS := ["id", "center_agl_m", "half_thickness_m", "delta_wind_ned_mps"]
const GUSTS_KEYS := ["law", "events"]
const GUST_EVENT_KEYS := ["id", "start_s", "duration_s", "amplitude_ned_mps"]
const TURBULENCE_KEYS := [
	"law", "rms_mps", "min_wavelength_m", "max_wavelength_m", "mode_count", "coherence_time_s",
]
const ThermalConfig := preload("res://physics/wind_thermal_field.gd")


## Complete, zero-wind candidate. Nonzero values remain explicitly authored by the scenario.
static func defaults() -> Dictionary:
	return {
		"format": FORMAT,
		"identity": {
			"seed_u32": 20261025,
			"world_epoch_id_u32": 0,
			"epoch_offset_s": 0.0,
			"seed_algorithm": SEED_ALGORITHM,
		},
		"frame": FRAME,
		"datum": {"law": DATUM_LAW, "ground_down_m": 0.0},
		"domain": {
			"half_extent_north_m": 10000.0,
			"half_extent_east_m": 10000.0,
			"max_height_agl_m": 200.0,
			"time_horizon_s": 86400.0,
			"ground_extension_m": 0.25,
			"ground_transition_height_m": 3.0,
		},
		"profile": {
			"law": PROFILE_LAW,
			"reference_speed_mps": 0.0,
			"reference_from_deg": 0.0,
			"reference_height_agl_m": 10.0,
			"roughness_length_m": 0.03,
			"displacement_height_m": 0.0,
			"wall_join_height_agl_m": 0.3,
			"surface_layer_top_agl_m": 80.0,
			"free_air_join_height_m": 20.0,
			"free_air_wind_ned_mps": [0.0, 0.0, 0.0],
			"layers": [],
		},
		"gusts": {"law": GUST_LAW, "events": []},
		"turbulence": {
			"law": TURBULENCE_LAW,
			"rms_mps": 0.0,
			"min_wavelength_m": 5.0,
			"max_wavelength_m": 50.0,
			"mode_count": 24,
			"coherence_time_s": 4.0,
		},
	}


## Return a validated v2 candidate whose empty thermal agenda shares the spatial clock and datum.
## The return shape matches resolve(): {ok, config, content_hash, errors}.
static func thermal_defaults(raw_spatial: Variant = {}) -> Dictionary:
	var spatial: Dictionary = defaults()
	if typeof(raw_spatial) == TYPE_DICTIONARY:
		var supplied: Dictionary = raw_spatial
		if not supplied.is_empty():
			var checked_spatial: Dictionary = resolve(supplied)
			if not checked_spatial.ok:
				return checked_spatial
			if checked_spatial.config.format != FORMAT:
				return _failure("thermal_defaults requires a spatial v1 configuration")
			spatial = checked_spatial.config.duplicate(true)
	elif raw_spatial != null:
		return _failure("thermal_defaults spatial input must be an object")
	var spatial_domain: Dictionary = spatial.domain
	if float(spatial_domain.max_height_agl_m) < 200.0:
		return _failure("spatial domain height must be at least 200 m to host the thermal provider")
	if float(spatial_domain.time_horizon_s) < 120.0:
		return _failure("spatial time horizon must be at least 120 s to host the thermal provider")
	var thermal: Dictionary = ThermalConfig.defaults()
	thermal.identity.world_epoch_id_u32 = spatial.identity.world_epoch_id_u32
	thermal.identity.epoch_offset_s = spatial.identity.epoch_offset_s
	thermal.datum = spatial.datum.duplicate(true)
	thermal.domain = {
		"half_extent_north_m": spatial_domain.half_extent_north_m,
		"half_extent_east_m": spatial_domain.half_extent_east_m,
		"max_height_agl_m": spatial_domain.max_height_agl_m,
		"time_horizon_s": spatial_domain.time_horizon_s,
	}
	spatial.format = FORMAT_V2
	spatial["thermal_field"] = thermal
	return resolve(spatial)


## Upgrade only a valid v1 base and a complete explicit thermal agenda. No identity or domain
## values are inferred from the agenda: resolve() checks their compatibility without rewriting it.
static func upgrade_thermals(raw_spatial: Variant, thermal_raw: Variant) -> Dictionary:
	var checked_spatial: Dictionary = resolve(raw_spatial)
	if not checked_spatial.ok:
		return checked_spatial
	if checked_spatial.config.format != FORMAT:
		return _failure("upgrade_thermals requires a spatial v1 configuration")
	if typeof(thermal_raw) != TYPE_DICTIONARY:
		return _failure("upgrade_thermals requires a complete thermal configuration object")
	var upgraded: Dictionary = checked_spatial.config.duplicate(true)
	upgraded.format = FORMAT_V2
	upgraded["thermal_field"] = (thermal_raw as Dictionary).duplicate(true)
	return resolve(upgraded)


## Validate a complete object and return only canonical, detached data.
## Array order is meaningful and therefore must already be canonical: layers by center height,
## gust events by start time. Values retain their float64 precision; only 360 degrees becomes 0.
static func resolve(raw: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(raw) != TYPE_DICTIONARY:
		return _failure("spatial wind configuration must be an object")
	var source: Dictionary = raw
	var format_name := str(source.get("format", ""))
	var version_two := format_name == FORMAT_V2
	if format_name not in [FORMAT, FORMAT_V2]:
		errors.append("spatial_wind.format must be '%s' or '%s'" % [FORMAT, FORMAT_V2])
	_check_keys(source, ROOT_KEYS_V2 if version_two else ROOT_KEYS, "spatial_wind", errors)
	if source.get("frame") != FRAME:
		errors.append("spatial_wind.frame must be 'NED'")

	var identity_raw: Variant = source.get("identity")
	var identity: Dictionary = {}
	if typeof(identity_raw) != TYPE_DICTIONARY:
		errors.append("spatial_wind.identity must be an object")
	else:
		var identity_source: Dictionary = identity_raw
		_check_keys(identity_source, IDENTITY_KEYS, "spatial_wind.identity", errors)
		var seed := _uint32(identity_source.get("seed_u32"), "identity.seed_u32", errors)
		var epoch_id := _uint32(identity_source.get("world_epoch_id_u32"), "identity.world_epoch_id_u32", errors)
		var epoch_offset := _number(identity_source.get("epoch_offset_s"), "identity.epoch_offset_s", 0.0, 86400.0, errors)
		if identity_source.get("seed_algorithm") != SEED_ALGORITHM:
			errors.append("identity.seed_algorithm must be '%s'" % SEED_ALGORITHM)
		identity = {
			"seed_u32": seed,
			"world_epoch_id_u32": epoch_id,
			"epoch_offset_s": epoch_offset,
			"seed_algorithm": SEED_ALGORITHM,
		}

	var datum_raw: Variant = source.get("datum")
	var datum: Dictionary = {}
	if typeof(datum_raw) != TYPE_DICTIONARY:
		errors.append("spatial_wind.datum must be an object")
	else:
		var datum_source: Dictionary = datum_raw
		_check_keys(datum_source, DATUM_KEYS, "spatial_wind.datum", errors)
		if datum_source.get("law") != DATUM_LAW:
			errors.append("datum.law must be '%s'" % DATUM_LAW)
		var ground_down := _number(datum_source.get("ground_down_m"), "datum.ground_down_m", 0.0, 0.0, errors)
		datum = {"law": DATUM_LAW, "ground_down_m": ground_down}

	var domain_raw: Variant = source.get("domain")
	var domain: Dictionary = {}
	if typeof(domain_raw) != TYPE_DICTIONARY:
		errors.append("spatial_wind.domain must be an object")
	else:
		var domain_source: Dictionary = domain_raw
		_check_keys(domain_source, DOMAIN_KEYS, "spatial_wind.domain", errors)
		domain = {
			"half_extent_north_m": _number(domain_source.get("half_extent_north_m"), "domain.half_extent_north_m", 100.0, 10000.0, errors),
			"half_extent_east_m": _number(domain_source.get("half_extent_east_m"), "domain.half_extent_east_m", 100.0, 10000.0, errors),
			"max_height_agl_m": _number(domain_source.get("max_height_agl_m"), "domain.max_height_agl_m", 20.0, 1000.0, errors),
			"time_horizon_s": _number(domain_source.get("time_horizon_s"), "domain.time_horizon_s", 60.0, 86400.0, errors),
			"ground_extension_m": _number(domain_source.get("ground_extension_m"), "domain.ground_extension_m", 0.01, 1.0, errors),
			"ground_transition_height_m": _number(domain_source.get("ground_transition_height_m"), "domain.ground_transition_height_m", 0.1, 50.0, errors),
		}

	var profile_raw: Variant = source.get("profile")
	var profile: Dictionary = {}
	if typeof(profile_raw) != TYPE_DICTIONARY:
		errors.append("spatial_wind.profile must be an object")
	else:
		var profile_source: Dictionary = profile_raw
		_check_keys(profile_source, PROFILE_KEYS, "spatial_wind.profile", errors)
		if profile_source.get("law") != PROFILE_LAW:
			errors.append("profile.law must be '%s'" % PROFILE_LAW)
		var from_deg := _number(profile_source.get("reference_from_deg"), "profile.reference_from_deg", 0.0, 360.0, errors)
		profile = {
			"law": PROFILE_LAW,
			"reference_speed_mps": _number(profile_source.get("reference_speed_mps"), "profile.reference_speed_mps", 0.0, 20.0, errors),
			"reference_from_deg": 0.0 if from_deg == 360.0 else from_deg,
			"reference_height_agl_m": _number(profile_source.get("reference_height_agl_m"), "profile.reference_height_agl_m", 0.1, 200.0, errors),
			"roughness_length_m": _number(profile_source.get("roughness_length_m"), "profile.roughness_length_m", 0.001, 0.5, errors),
			"displacement_height_m": _number(profile_source.get("displacement_height_m"), "profile.displacement_height_m", 0.0, 20.0, errors),
			"wall_join_height_agl_m": _number(profile_source.get("wall_join_height_agl_m"), "profile.wall_join_height_agl_m", 0.1, 100.0, errors),
			"surface_layer_top_agl_m": _number(profile_source.get("surface_layer_top_agl_m"), "profile.surface_layer_top_agl_m", 1.0, 500.0, errors),
			"free_air_join_height_m": _number(profile_source.get("free_air_join_height_m"), "profile.free_air_join_height_m", 0.1, 200.0, errors),
			"free_air_wind_ned_mps": _horizontal_vector(profile_source.get("free_air_wind_ned_mps"), "profile.free_air_wind_ned_mps", 30.0, errors),
			"layers": [],
		}
		var layers_raw: Variant = profile_source.get("layers")
		if typeof(layers_raw) != TYPE_ARRAY:
			errors.append("profile.layers must be an array")
		else:
			if layers_raw.size() > 16:
				errors.append("profile.layers may contain at most 16 entries")
			var previous_center := -INF
			var layer_ids := {}
			for index: int in layers_raw.size():
				var layer_raw: Variant = layers_raw[index]
				if typeof(layer_raw) != TYPE_DICTIONARY:
					errors.append("profile.layers[%d] must be an object" % index)
					continue
				var layer_source: Dictionary = layer_raw
				var label := "profile.layers[%d]" % index
				_check_keys(layer_source, LAYER_KEYS, label, errors)
				var layer_id := _identifier(layer_source.get("id"), "%s.id" % label, errors)
				var center := _number(layer_source.get("center_agl_m"), "%s.center_agl_m" % label, 0.0, 1000.0, errors)
				var half := _number(layer_source.get("half_thickness_m"), "%s.half_thickness_m" % label, 0.1, 100.0, errors)
				var delta := _horizontal_vector(layer_source.get("delta_wind_ned_mps"), "%s.delta_wind_ned_mps" % label, 5.0, errors)
				if layer_ids.has(layer_id):
					errors.append("profile.layers[%d].id must be unique" % index)
				layer_ids[layer_id] = true
				if center < previous_center:
					errors.append("profile.layers must be sorted by center_agl_m")
				previous_center = center
				profile.layers.append({
					"id": layer_id,
					"center_agl_m": center,
					"half_thickness_m": half,
					"delta_wind_ned_mps": delta,
				})

	var gusts_raw: Variant = source.get("gusts")
	var gusts: Dictionary = {}
	if typeof(gusts_raw) != TYPE_DICTIONARY:
		errors.append("spatial_wind.gusts must be an object")
	else:
		var gusts_source: Dictionary = gusts_raw
		_check_keys(gusts_source, GUSTS_KEYS, "spatial_wind.gusts", errors)
		if gusts_source.get("law") != GUST_LAW:
			errors.append("gusts.law must be '%s'" % GUST_LAW)
		gusts = {"law": GUST_LAW, "events": []}
		var events_raw: Variant = gusts_source.get("events")
		if typeof(events_raw) != TYPE_ARRAY:
			errors.append("gusts.events must be an array")
		else:
			if events_raw.size() > 32:
				errors.append("gusts.events may contain at most 32 entries")
			var previous_start := -INF
			var event_ids := {}
			for index: int in events_raw.size():
				var event_raw: Variant = events_raw[index]
				if typeof(event_raw) != TYPE_DICTIONARY:
					errors.append("gusts.events[%d] must be an object" % index)
					continue
				var event_source: Dictionary = event_raw
				var label := "gusts.events[%d]" % index
				_check_keys(event_source, GUST_EVENT_KEYS, label, errors)
				var event_id := _identifier(event_source.get("id"), "%s.id" % label, errors)
				var start := _number(event_source.get("start_s"), "%s.start_s" % label, 0.0, 86400.0, errors)
				var duration := _number(event_source.get("duration_s"), "%s.duration_s" % label, 0.1, 120.0, errors)
				var amplitude := _horizontal_vector(event_source.get("amplitude_ned_mps"), "%s.amplitude_ned_mps" % label, 2.5, errors)
				if event_ids.has(event_id):
					errors.append("gusts.events[%d].id must be unique" % index)
				event_ids[event_id] = true
				if start < previous_start:
					errors.append("gusts.events must be sorted by start_s")
				previous_start = start
				gusts.events.append({
					"id": event_id,
					"start_s": start,
					"duration_s": duration,
					"amplitude_ned_mps": amplitude,
				})

	var turbulence_raw: Variant = source.get("turbulence")
	var turbulence: Dictionary = {}
	if typeof(turbulence_raw) != TYPE_DICTIONARY:
		errors.append("spatial_wind.turbulence must be an object")
	else:
		var turbulence_source: Dictionary = turbulence_raw
		_check_keys(turbulence_source, TURBULENCE_KEYS, "spatial_wind.turbulence", errors)
		if turbulence_source.get("law") != TURBULENCE_LAW:
			errors.append("turbulence.law must be '%s'" % TURBULENCE_LAW)
		var mode_count := _integer(turbulence_source.get("mode_count"), "turbulence.mode_count", 8, 64, errors)
		turbulence = {
			"law": TURBULENCE_LAW,
			"rms_mps": _number(turbulence_source.get("rms_mps"), "turbulence.rms_mps", 0.0, 1.0, errors),
			"min_wavelength_m": _number(turbulence_source.get("min_wavelength_m"), "turbulence.min_wavelength_m", 2.0, 100.0, errors),
			"max_wavelength_m": _number(turbulence_source.get("max_wavelength_m"), "turbulence.max_wavelength_m", 2.0, 500.0, errors),
			"mode_count": mode_count,
			"coherence_time_s": _number(turbulence_source.get("coherence_time_s"), "turbulence.coherence_time_s", 0.1, 600.0, errors),
		}

	var thermal_config: Dictionary = {}
	var thermal_content_hash := ""
	if version_two:
		var thermal_checked: Dictionary = ThermalConfig.resolve(source.get("thermal_field"))
		if not thermal_checked.ok:
			for thermal_error: String in thermal_checked.errors:
				errors.append("thermal_field: %s" % thermal_error)
		else:
			thermal_config = thermal_checked.config
			thermal_content_hash = str(thermal_checked.content_hash)

	if not errors.is_empty():
		return {"ok": false, "config": {}, "content_hash": "", "errors": errors}

	if profile.reference_from_deg == 360.0:
		profile.reference_from_deg = 0.0
	_validate_domain(domain, profile, identity, errors)
	_validate_layers(profile, domain, errors)
	_validate_events(gusts, domain, errors)
	_validate_turbulence(turbulence, errors)
	if version_two and not thermal_config.is_empty():
		_validate_thermal_coupling(thermal_config, identity, datum, domain, errors)
	if not errors.is_empty():
		return {"ok": false, "config": {}, "content_hash": "", "errors": errors}

	var canonical := {
		"format": format_name,
		"identity": identity,
		"frame": FRAME,
		"datum": datum,
		"domain": domain,
		"profile": profile,
		"gusts": gusts,
		"turbulence": turbulence,
	}
	if version_two:
		canonical["thermal_field"] = thermal_config
	var result := {
		"ok": true,
		"config": canonical,
		"content_hash": _hash_canonical(canonical),
		"errors": PackedStringArray(),
	}
	if version_two:
		result["thermal_content_hash"] = thermal_content_hash
		result["thermal_law"] = str(thermal_config.law)
	return result


static func _validate_thermal_coupling(thermal: Dictionary, identity: Dictionary, datum: Dictionary, domain: Dictionary, errors: PackedStringArray) -> void:
	var thermal_identity: Dictionary = thermal.identity
	if int(thermal_identity.world_epoch_id_u32) != int(identity.world_epoch_id_u32):
		errors.append("thermal_field.identity.world_epoch_id_u32 must match spatial_wind.identity")
	if float(thermal_identity.epoch_offset_s) != float(identity.epoch_offset_s):
		errors.append("thermal_field.identity.epoch_offset_s must exactly match spatial_wind.identity")
	var thermal_datum: Dictionary = thermal.datum
	if thermal_datum.law != datum.law or float(thermal_datum.ground_down_m) != float(datum.ground_down_m):
		errors.append("thermal_field datum must exactly match spatial_wind datum")
	var thermal_domain: Dictionary = thermal.domain
	for key: String in ["half_extent_north_m", "half_extent_east_m", "max_height_agl_m", "time_horizon_s"]:
		if float(thermal_domain[key]) > float(domain[key]):
			errors.append("thermal_field.domain.%s may not exceed spatial_wind.domain.%s" % [key, key])
		elif float(thermal_domain[key]) != float(domain[key]):
			errors.append("thermal_field.domain.%s must exactly match spatial_wind.domain.%s" % [key, key])


static func _validate_domain(domain: Dictionary, profile: Dictionary, identity: Dictionary, errors: PackedStringArray) -> void:
	var ground_transition := float(domain.ground_transition_height_m)
	var max_height := float(domain.max_height_agl_m)
	var time_horizon := float(domain.time_horizon_s)
	if ground_transition > max_height:
		errors.append("domain.ground_transition_height_m must not exceed max_height_agl_m")
	if float(identity.epoch_offset_s) > time_horizon:
		errors.append("identity.epoch_offset_s must not exceed domain.time_horizon_s")
	var z0 := float(profile.roughness_length_m)
	var displacement := float(profile.displacement_height_m)
	var wall := float(profile.wall_join_height_agl_m)
	var reference_height := float(profile.reference_height_agl_m)
	var layer_top := float(profile.surface_layer_top_agl_m)
	var join_height := float(profile.free_air_join_height_m)
	if wall < displacement + maxf(0.3, 10.0 * z0):
		errors.append("profile.wall_join_height_agl_m must be at least d + max(0.3 m, 10 z0)")
	if wall <= displacement + z0:
		errors.append("profile.wall_join_height_agl_m must be above d + z0")
	if reference_height <= wall or reference_height >= layer_top:
		errors.append("profile.reference_height_agl_m must lie strictly inside the neutral profile section")
	if reference_height <= displacement + z0:
		errors.append("profile.reference_height_agl_m must be above d + z0")
	if layer_top + join_height > max_height:
		errors.append("profile surface-layer and free-air join exceed domain.max_height_agl_m")
	if layer_top <= displacement + z0:
		errors.append("profile.surface_layer_top_agl_m must be above d + z0")
	var neutral_denominator := log((reference_height - displacement) / z0)
	if not is_finite(neutral_denominator) or neutral_denominator <= 0.0:
		errors.append("profile neutral logarithm denominator must be positive and finite")
	else:
		var wall_log := log((wall - displacement) / z0)
		var matched_slope_ratio := wall / ((wall - displacement) * wall_log)
		if not is_finite(matched_slope_ratio) or matched_slope_ratio < 0.0 or matched_slope_ratio > 3.0:
			errors.append("profile wall join slope cannot be bounded by the monotone cubic")
	if time_horizon > 0.0 and float(profile.surface_layer_top_agl_m) > max_height:
		errors.append("profile.surface_layer_top_agl_m exceeds domain.max_height_agl_m")


static func _validate_layers(profile: Dictionary, domain: Dictionary, errors: PackedStringArray) -> void:
	var reference_height := float(profile.reference_height_agl_m)
	var wall := float(profile.wall_join_height_agl_m)
	var maximum := float(domain.max_height_agl_m)
	for index: int in profile.layers.size():
		var layer: Dictionary = profile.layers[index]
		var bottom := float(layer.center_agl_m) - float(layer.half_thickness_m)
		var top := float(layer.center_agl_m) + float(layer.half_thickness_m)
		if bottom < wall:
			errors.append("profile.layers[%d] support must start at or above the wall join" % index)
		if top > maximum:
			errors.append("profile.layers[%d] support exceeds domain.max_height_agl_m" % index)
		if reference_height >= bottom and reference_height <= top:
			errors.append("profile.layers[%d] support must not contain reference_height_agl_m" % index)
		if index > 0:
			var previous: Dictionary = profile.layers[index - 1]
			var previous_top := float(previous.center_agl_m) + float(previous.half_thickness_m)
			if bottom < previous_top:
				errors.append("profile.layers may not overlap; keep separate smooth layers")


static func _validate_events(gusts: Dictionary, domain: Dictionary, errors: PackedStringArray) -> void:
	var horizon := float(domain.time_horizon_s)
	var events: Array = gusts.events
	for index: int in events.size():
		var event: Dictionary = events[index]
		if float(event.start_s) + float(event.duration_s) > horizon:
			errors.append("gusts.events[%d] ends outside domain.time_horizon_s" % index)
	var maximum_overlap := 0
	var maximum_amplitude_bound := 0.0
	for origin: Dictionary in events:
		var active := 0
		var amplitude_bound := 0.0
		var origin_time := float(origin.start_s)
		for candidate: Dictionary in events:
			var start := float(candidate.start_s)
			var end := start + float(candidate.duration_s)
			if start <= origin_time and origin_time < end:
				active += 1
				var amplitude: Array = candidate.amplitude_ned_mps
				amplitude_bound += sqrt(float(amplitude[0]) * float(amplitude[0]) + float(amplitude[1]) * float(amplitude[1]))
		maximum_overlap = maxi(maximum_overlap, active)
		maximum_amplitude_bound = maxf(maximum_amplitude_bound, amplitude_bound)
	if maximum_overlap > 4:
		errors.append("gust timeline allows at most four overlapping events")
	if maximum_amplitude_bound > 8.0:
		errors.append("overlapping gust horizontal amplitude bound must not exceed 8 m/s")


static func _validate_turbulence(turbulence: Dictionary, errors: PackedStringArray) -> void:
	if float(turbulence.min_wavelength_m) > float(turbulence.max_wavelength_m):
		errors.append("turbulence.min_wavelength_m must not exceed max_wavelength_m")


static func _horizontal_vector(raw: Variant, label: String, maximum_component: float, errors: PackedStringArray) -> Array:
	if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
		errors.append("%s must be an NED array of three finite numbers" % label)
		return [NAN, NAN, NAN]
	var values: Array = []
	for index: int in 3:
		var value := _number(raw[index], "%s[%d]" % [label, index], -maximum_component, maximum_component, errors)
		values.append(value)
	if values.size() == 3 and float(values[2]) != 0.0:
		errors.append("%s[2] must be zero; this law has no mean vertical flow" % label)
	return values


static func _check_keys(source: Dictionary, required: Array, label: String, errors: PackedStringArray) -> void:
	for key: String in required:
		if not source.has(key):
			errors.append("%s is missing required field '%s'" % [label, key])
	for key: Variant in source:
		if key not in required:
			errors.append("%s has unknown field '%s'" % [label, str(key)])


static func _number(value: Variant, label: String, minimum: float, maximum: float, errors: PackedStringArray) -> float:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		errors.append("%s must be a finite number" % label)
		return NAN
	var number := float(value)
	if not is_finite(number):
		errors.append("%s must be a finite number" % label)
		return NAN
	if number < minimum or number > maximum:
		errors.append("%s must be in [%s, %s]" % [label, minimum, maximum])
	return number


static func _uint32(value: Variant, label: String, errors: PackedStringArray) -> int:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		errors.append("%s must be an integer in [0, 4294967295]" % label)
		return 0
	var number := float(value)
	if not is_finite(number) or number < 0.0 or number > 4294967295.0 or number != floor(number):
		errors.append("%s must be an integer in [0, 4294967295]" % label)
		return 0
	return int(number)


static func _integer(value: Variant, label: String, minimum: int, maximum: int, errors: PackedStringArray) -> int:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		errors.append("%s must be an integer in [%d, %d]" % [label, minimum, maximum])
		return minimum
	var number := float(value)
	if not is_finite(number) or number < float(minimum) or number > float(maximum) or number != floor(number):
		errors.append("%s must be an integer in [%d, %d]" % [label, minimum, maximum])
		return minimum
	return int(number)


static func _identifier(value: Variant, label: String, errors: PackedStringArray) -> String:
	if typeof(value) != TYPE_STRING or str(value).is_empty() or str(value).length() > 64:
		errors.append("%s must be a nonempty string of at most 64 characters" % label)
		return ""
	return str(value)


static func _hash_canonical(config: Dictionary) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(JSON.stringify(config, "", true, true).to_utf8_buffer())
	return context.finish().hex_encode()


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "config": {}, "content_hash": "", "errors": PackedStringArray([message])}
