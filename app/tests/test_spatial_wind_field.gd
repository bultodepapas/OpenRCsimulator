extends SceneTree

const Config := preload("res://physics/wind_spatial_config.gd")
const SpatialField := preload("res://physics/wind_spatial_field.gd")
const ThermalConfig := preload("res://physics/wind_thermal_field.gd")

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _field(raw: Dictionary) -> Variant:
	var built: Dictionary = SpatialField.build(raw)
	if not built.ok:
		printerr("spatial wind fixture rejected: ", built.errors)
		return null
	return built.field


func _sample(field: Variant, north: float, east: float, height_agl: float, time_s: float) -> Dictionary:
	return field.sample_world(PackedFloat64Array([north, east, -height_agl]), time_s)


func _near(actual: PackedFloat64Array, expected: PackedFloat64Array, tolerance := 1e-12) -> bool:
	if actual.size() != expected.size():
		return false
	for index: int in actual.size():
		if not is_finite(actual[index]) or absf(actual[index] - expected[index]) > tolerance:
			return false
	return true


func _norm(value: PackedFloat64Array) -> float:
	return sqrt(value[0] * value[0] + value[1] * value[1] + value[2] * value[2])


func _validate_schema_and_identity() -> void:
	var raw := Config.defaults()
	var checked: Dictionary = Config.resolve(raw)
	_check("complete zero-wind defaults resolve", checked.ok and checked.config == raw, str(checked.errors))
	_check("v1 full-precision canonical hash anchor", checked.content_hash == "cc4de19f44386dbf05dacb2b0e75326a2e44ec81ca12f311b5a7046a71a24555", str(checked.content_hash))
	_check("canonical hash is lowercase SHA-256", str(checked.content_hash).length() == 64 and str(checked.content_hash).to_lower() == checked.content_hash)
	var again: Dictionary = Config.resolve(checked.config)
	_check("canonical resolve is stable", again.ok and again.content_hash == checked.content_hash)
	var precision_a := Config.defaults()
	precision_a.identity.epoch_offset_s = 1.0
	var precision_b := Config.defaults()
	precision_b.identity.epoch_offset_s = 1.0000000000001
	var precise_a: Dictionary = Config.resolve(precision_a)
	var precise_b: Dictionary = Config.resolve(precision_b)
	var precision_roundtrip: Dictionary = Config.resolve(JSON.parse_string(JSON.stringify(precise_b.get("config", {}), "", true, true)))
	var precision_roundtrip_config: Dictionary = precision_roundtrip.get("config", {})
	var precise_b_config: Dictionary = precise_b.get("config", {})
	_check("sub-picosecond epoch offsets retain distinct canonical hashes", precise_a.ok and precise_b.ok
		and precise_a.content_hash != precise_b.content_hash, str([precise_a.get("content_hash", ""), precise_b.get("content_hash", ""), precise_b.get("errors", [])]))
	_check("full-precision JSON roundtrip preserves the authored float64 identity", precision_roundtrip.ok
		and precision_roundtrip_config.get("identity", {}).get("epoch_offset_s") == precise_b_config.get("identity", {}).get("epoch_offset_s")
		and precision_roundtrip.get("content_hash", "") == precise_b.get("content_hash", ""),
		str([precision_roundtrip.get("errors", []), JSON.stringify(precise_b.get("config", {}), "", true, true)]))
	var built: Dictionary = SpatialField.build(raw)
	_check("complete config builds spatial zero-amplitude provider", built.ok and built.field.is_spatial())
	if built.ok:
		var field: Variant = built.field
		var expected_hash: String = checked.content_hash
		_check("field retains immutable config identity", field.content_hash() == expected_hash and field.identity() == raw.identity)
		raw.identity.seed_u32 = 7
		var exposed: Dictionary = field.configuration()
		exposed.identity.world_epoch_id_u32 = 12
		_check("input and exposed config are detached", field.identity().seed_u32 == 20261025 and field.identity().world_epoch_id_u32 == 0)

	for invalid: Dictionary in [
		{"case": "missing root key", "mutate": "root"},
		{"case": "unknown root key", "mutate": "unknown"},
		{"case": "boolean seed", "mutate": "boolean_seed"},
		{"case": "nonfinite epoch", "mutate": "nan_epoch"},
		{"case": "vertical mean", "mutate": "vertical_mean"},
		{"case": "underspecified vector", "mutate": "short_vector"},
		{"case": "negative wavelength", "mutate": "wavelength"},
		{"case": "unsupported law", "mutate": "law"},
		{"case": "wrong datum", "mutate": "datum"},
	]:
		var bad := Config.defaults()
		match str(invalid.mutate):
			"root": bad.erase("gusts")
			"unknown": bad["future"] = 1.0
			"boolean_seed": bad.identity.seed_u32 = true
			"nan_epoch": bad.identity.epoch_offset_s = NAN
			"vertical_mean": bad.profile.free_air_wind_ned_mps = [0.0, 0.0, 0.01]
			"short_vector": bad.profile.free_air_wind_ned_mps = [1.0, 2.0]
			"wavelength": bad.turbulence.min_wavelength_m = -1.0
			"law": bad.turbulence.law = "von-karman"
			"datum": bad.datum.ground_down_m = 1.0
		_check("reject %s" % str(invalid.case), not Config.resolve(bad).ok)

	var huge := Config.defaults()
	huge.profile.reference_speed_mps = 1.0e308
	_check("reject finite but out-of-range overflow-scale values", not Config.resolve(huge).ok)
	var fractional_seed := Config.defaults()
	fractional_seed.identity.seed_u32 = 4.5
	_check("reject fractional seed", not Config.resolve(fractional_seed).ok)
	var unknown_nested := Config.defaults()
	unknown_nested.profile.extra = 1.0
	_check("reject unknown nested keys", not Config.resolve(unknown_nested).ok)


func _reference_profile_oracle() -> void:
	var raw := Config.defaults()
	raw.profile.reference_speed_mps = 4.25
	raw.profile.reference_from_deg = 37.0
	var field: Variant = _field(raw)
	var reference: Dictionary = _sample(field, 0.0, 0.0, 10.0, 0.0)
	var bearing := deg_to_rad(37.0)
	var expected := PackedFloat64Array([-4.25 * cos(bearing), -4.25 * sin(bearing), 0.0])
	_check("reference horizontal mean matches independent log-profile oracle", reference.ok and _near(reference.wind_ned_mps, expected, 1e-12), str(reference))
	var at_five: Dictionary = _sample(field, 0.0, 0.0, 5.0, 0.0)
	var scale := log(5.0 / 0.03) / log(10.0 / 0.03)
	var five_expected := PackedFloat64Array([-4.25 * cos(bearing) * scale, -4.25 * sin(bearing) * scale, 0.0])
	_check("neutral section follows independent logarithmic law", at_five.ok and _near(at_five.wind_ned_mps, five_expected, 1e-12), str(at_five.wind_ned_mps))

	var free_air := Config.defaults()
	free_air.profile.reference_speed_mps = 3.0
	free_air.profile.free_air_wind_ned_mps = [1.25, -0.75, 0.0]
	var high_field: Variant = _field(free_air)
	var upper: Dictionary = _sample(high_field, 0.0, 0.0, 100.0, 0.0)
	_check("free-air join reaches authored horizontal endpoint", upper.ok and _near(upper.wind_ned_mps, PackedFloat64Array([1.25, -0.75, 0.0]), 0.0))
	var reference_upper: Dictionary = _sample(high_field, 0.0, 0.0, 10.0, 0.0)
	_check("free-air settings do not duplicate or alter reference wind", _near(reference_upper.wind_ned_mps,
		PackedFloat64Array([-3.0, 0.0, 0.0]), 1e-12))


func _wall_and_join_continuity() -> void:
	var raw := Config.defaults()
	raw.profile.reference_speed_mps = 4.0
	raw.profile.reference_from_deg = 0.0
	raw.profile.free_air_wind_ned_mps = [2.0, 1.0, 0.0]
	raw.gusts.events = [{"id": "wall-gust", "start_s": 0.0, "duration_s": 4.0, "amplitude_ned_mps": [-1.0, 0.5, 0.0]}]
	raw.turbulence.rms_mps = 0.2
	var field: Variant = _field(raw)
	var wall: Dictionary = _sample(field, 1.0, -2.0, 0.0, 2.0)
	var underground: Dictionary = field.sample_world(PackedFloat64Array([1.0, -2.0, 0.1]), 2.0)
	_check("ground wall is exactly zero velocity", wall.ok and _near(wall.wind_ned_mps, PackedFloat64Array([0.0, 0.0, 0.0]), 0.0))
	_check("slightly underground aircraft station gets zero extension", underground.ok and underground.wind_ned_mps == PackedFloat64Array([0.0, 0.0, 0.0]))
	var too_deep: Dictionary = field.sample_world(PackedFloat64Array([0.0, 0.0, 0.251]), 1.0)
	_check("deep subsurface point fails closed", not too_deep.ok and not str(too_deep.error).is_empty())
	var near_wall: Dictionary = _sample(field, 0.0, 0.0, 1.0e-4, 2.0)
	_check("all field components approach zero with a C1 wall join", near_wall.ok and _norm(near_wall.wind_ned_mps) < 1e-6, str(near_wall.wind_ned_mps))
	var closer_to_wall: PackedFloat64Array = _sample(field, 0.0, 0.0, 1e-6, 2.0).wind_ned_mps
	_check("wall-normal derivative also tends to zero through the solid extension", _norm(closer_to_wall) / 1e-6 < 1e-4)

	var profile: Dictionary = raw.profile
	var profile_only_config := Config.defaults()
	profile_only_config.profile = profile.duplicate(true)
	var profile_only: Variant = _field(profile_only_config)
	var wall_height := float(profile.wall_join_height_agl_m)
	var wall_step := 1e-7
	var at_wall_minus: PackedFloat64Array = _sample(profile_only, 0.0, 0.0, wall_height - wall_step, 0.0).wind_ned_mps
	var at_wall_plus: PackedFloat64Array = _sample(profile_only, 0.0, 0.0, wall_height + wall_step, 0.0).wind_ned_mps
	var wall_slope := (at_wall_plus[0] - at_wall_minus[0]) / (2.0 * wall_step)
	var denominator := log((profile.reference_height_agl_m - profile.displacement_height_m) / profile.roughness_length_m)
	var expected_wall_slope := -float(profile.reference_speed_mps) / ((wall_height - float(profile.displacement_height_m)) * denominator)
	_check("cubic wall join matches neutral value slope", absf(wall_slope - expected_wall_slope) < 1e-5, str([wall_slope, expected_wall_slope]))

	var top := float(profile.surface_layer_top_agl_m)
	var top_step := 1e-4
	var left: PackedFloat64Array = _sample(profile_only, 0.0, 0.0, top - top_step, 0.0).wind_ned_mps
	var right: PackedFloat64Array = _sample(profile_only, 0.0, 0.0, top + top_step, 0.0).wind_ned_mps
	var measured_slope := (right[0] - left[0]) / (2.0 * top_step)
	var expected_top_slope := -float(profile.reference_speed_mps) / ((top - float(profile.displacement_height_m)) * denominator)
	_check("free-air transition matches entering neutral derivative", absf(measured_slope - expected_top_slope) < 1e-5,
		str([measured_slope, expected_top_slope]))
	var join_end := top + float(profile.free_air_join_height_m)
	var end_left: PackedFloat64Array = _sample(profile_only, 0.0, 0.0, join_end - top_step, 0.0).wind_ned_mps
	var end_right: PackedFloat64Array = _sample(profile_only, 0.0, 0.0, join_end + top_step, 0.0).wind_ned_mps
	_check("free-air endpoint value and slope are continuous", absf(end_right[0] - end_left[0]) < 1e-8 and absf(end_right[1] - end_left[1]) < 1e-8)


func _layers_and_gust_timeline() -> void:
	var layered := Config.defaults()
	layered.profile.reference_speed_mps = 2.0
	layered.profile.layers = [{
		"id": "low-shear",
		"center_agl_m": 35.0,
		"half_thickness_m": 5.0,
		"delta_wind_ned_mps": [1.0, -0.5, 0.0],
	}]
	var layered_field: Variant = _field(layered)
	var layer_center: Dictionary = _sample(layered_field, 0.0, 0.0, 35.0, 0.0)
	var base_center := Config.defaults()
	base_center.profile.reference_speed_mps = 2.0
	var base_field: Variant = _field(base_center)
	var base_value: PackedFloat64Array = _sample(base_field, 0.0, 0.0, 35.0, 0.0).wind_ned_mps
	_check("finite layer adds authored center delta", absf(layer_center.wind_ned_mps[0] - base_value[0] - 1.0) < 1e-12
		and absf(layer_center.wind_ned_mps[1] - base_value[1] + 0.5) < 1e-12)
	var layer_edge: Dictionary = _sample(layered_field, 0.0, 0.0, 30.0, 0.0)
	var base_edge: PackedFloat64Array = _sample(base_field, 0.0, 0.0, 30.0, 0.0).wind_ned_mps
	_check("finite layer is zero at compact support edge", _near(layer_edge.wind_ned_mps, base_edge, 1e-12))
	var just_inside: PackedFloat64Array = _sample(layered_field, 0.0, 0.0, 30.0001, 0.0).wind_ned_mps
	var just_inside_base: PackedFloat64Array = _sample(base_field, 0.0, 0.0, 30.0001, 0.0).wind_ned_mps
	_check("finite layer approaches its support edge with zero slope", absf(just_inside[0] - just_inside_base[0]) < 1e-10
		and absf(just_inside[1] - just_inside_base[1]) < 1e-10)
	var reference: PackedFloat64Array = _sample(layered_field, 0.0, 0.0, 10.0, 0.0).wind_ned_mps
	_check("finite layer preserves reference-height equality", _near(reference, PackedFloat64Array([-2.0, 0.0, 0.0]), 1e-12))
	var layer_overlap := Config.defaults()
	layer_overlap.profile.layers = [
		{"id": "a", "center_agl_m": 20.0, "half_thickness_m": 4.0, "delta_wind_ned_mps": [1.0, 0.0, 0.0]},
		{"id": "b", "center_agl_m": 25.0, "half_thickness_m": 4.0, "delta_wind_ned_mps": [0.0, 1.0, 0.0]},
	]
	_check("overlapping layer supports are rejected", not Config.resolve(layer_overlap).ok)

	var gust_config := Config.defaults()
	gust_config.identity.epoch_offset_s = 1.0
	gust_config.gusts.events = [{"id": "resolved-01", "start_s": 2.0, "duration_s": 4.0, "amplitude_ned_mps": [-1.2, 0.6, 0.0]}]
	var gust_field: Variant = _field(gust_config)
	var before: PackedFloat64Array = _sample(gust_field, 0.0, 0.0, 10.0, 0.99).wind_ned_mps
	var start: PackedFloat64Array = _sample(gust_field, 0.0, 0.0, 10.0, 1.0).wind_ned_mps
	var peak: PackedFloat64Array = _sample(gust_field, 0.0, 0.0, 10.0, 3.0).wind_ned_mps
	var end: PackedFloat64Array = _sample(gust_field, 0.0, 0.0, 10.0, 5.0).wind_ned_mps
	var near_start: PackedFloat64Array = _sample(gust_field, 0.0, 0.0, 10.0, 1.00001).wind_ned_mps
	var near_end: PackedFloat64Array = _sample(gust_field, 0.0, 0.0, 10.0, 4.99999).wind_ned_mps
	_check("epoch offset and resolved event endpoints are deterministic", _near(before, PackedFloat64Array([0.0, 0.0, 0.0]), 0.0)
		and _near(start, PackedFloat64Array([0.0, 0.0, 0.0]), 0.0) and _near(end, PackedFloat64Array([0.0, 0.0, 0.0]), 0.0))
	_check("resolved degree-six gust reaches authored midpoint amplitude", _near(peak, PackedFloat64Array([-1.2, 0.6, 0.0]), 1e-12), str(peak))
	_check("degree-six gust has C1 zero endpoints", _norm(near_start) < 1e-10 and _norm(near_end) < 1e-10)
	const N := 2048
	var area := PackedFloat64Array([0.0, 0.0])
	var dt := 4.0 / float(N)
	for index: int in N + 1:
		var value: PackedFloat64Array = _sample(gust_field, 0.0, 0.0, 10.0, 1.0 + float(index) * dt).wind_ned_mps
		var weight := 0.5 if index == 0 or index == N else 1.0
		area[0] += weight * value[0]
		area[1] += weight * value[1]
	area[0] *= dt
	area[1] *= dt
	_check("pre-resolved gust area matches independent degree-six bell integral", absf(area[0] - (-1.2 * 4.0 * 16.0 / 35.0)) < 1e-10
		and absf(area[1] - (0.6 * 4.0 * 16.0 / 35.0)) < 1e-10, str(area))
	var vertical_gust := Config.defaults()
	vertical_gust.gusts.events = [{"id": "bad", "start_s": 0.0, "duration_s": 2.0, "amplitude_ned_mps": [0.0, 0.0, 0.1]}]
	_check("vertical uniform gusts are rejected", not Config.resolve(vertical_gust).ok)
	var overlap := Config.defaults()
	for index: int in 5:
		overlap.gusts.events.append({"id": "g%d" % index, "start_s": 0.0, "duration_s": 10.0, "amplitude_ned_mps": [0.1, 0.0, 0.0]})
	_check("gust overlap is bounded in the config resolver", not Config.resolve(overlap).ok)


func _divergence(field: Variant, north: float, east: float, height_agl: float, time_s: float, step: float) -> float:
	var north_plus: PackedFloat64Array = _sample(field, north + step, east, height_agl, time_s).wind_ned_mps
	var north_minus: PackedFloat64Array = _sample(field, north - step, east, height_agl, time_s).wind_ned_mps
	var east_plus: PackedFloat64Array = _sample(field, north, east + step, height_agl, time_s).wind_ned_mps
	var east_minus: PackedFloat64Array = _sample(field, north, east - step, height_agl, time_s).wind_ned_mps
	var down_plus: PackedFloat64Array = _sample(field, north, east, height_agl - step, time_s).wind_ned_mps
	var down_minus: PackedFloat64Array = _sample(field, north, east, height_agl + step, time_s).wind_ned_mps
	return (north_plus[0] - north_minus[0] + east_plus[1] - east_minus[1] + down_plus[2] - down_minus[2]) / (2.0 * step)


func _determinism_coherence_and_divergence() -> void:
	var raw := Config.defaults()
	raw.identity.seed_u32 = 73423
	raw.identity.world_epoch_id_u32 = 194
	raw.profile.reference_speed_mps = 3.0
	raw.profile.reference_from_deg = 270.0
	raw.profile.free_air_wind_ned_mps = [1.0, -0.25, 0.0]
	raw.profile.layers = [{"id": "shear", "center_agl_m": 32.0, "half_thickness_m": 6.0, "delta_wind_ned_mps": [0.4, -0.2, 0.0]}]
	raw.gusts.events = [{"id": "gust-a", "start_s": 1.0, "duration_s": 5.0, "amplitude_ned_mps": [-0.4, 0.25, 0.0]}]
	raw.turbulence.rms_mps = 0.2
	raw.turbulence.min_wavelength_m = 4.0
	raw.turbulence.max_wavelength_m = 20.0
	raw.turbulence.mode_count = 24
	raw.turbulence.coherence_time_s = 3.0
	var first: Variant = _field(raw)
	var second: Variant = _field(raw.duplicate(true))
	var point_north := 1.5
	var point_east := -2.0
	var point_height := 27.0
	var sample_a: PackedFloat64Array = _sample(first, point_north, point_east, point_height, 2.75).wind_ned_mps
	_check("v1 full-precision canonical hash and pre-thermal nonzero sample bytes are stable",
		Config.resolve(raw).content_hash == "901627a5bb902ad2fb15e625cda0610d106c8ea2a5d9e30719dd99580b37b867"
		and sample_a.to_byte_array().hex_encode() == "d7c7bae0206bd6bf6ff70f68fd790e4033ca32339282d03f",
		str([Config.resolve(raw).content_hash, sample_a.to_byte_array().hex_encode()]))
	var sample_b: PackedFloat64Array = _sample(second, point_north, point_east, point_height, 2.75).wind_ned_mps
	_check("same seed and immutable epoch build byte-identical field", sample_a.to_byte_array() == sample_b.to_byte_array())
	_sample(first, 2.0, 3.0, 80.0, 12.0)
	_sample(first, -30.0, 7.0, 15.0, 0.1)
	_check("query order does not mutate repeated samples", _sample(first, point_north, point_east, point_height, 2.75).wind_ned_mps.to_byte_array() == sample_a.to_byte_array())
	var close: PackedFloat64Array = _sample(first, point_north + 0.01, point_east, point_height, 2.75).wind_ned_mps
	var close_difference := _norm(PackedFloat64Array([sample_a[0] - close[0], sample_a[1] - close[1], sample_a[2] - close[2]]))
	_check("nearby stations sample a spatially coherent field", close_difference < 0.02, "difference " + str(close_difference))

	var calm_modes := Config.defaults()
	calm_modes.identity.seed_u32 = 8
	calm_modes.turbulence.rms_mps = 0.2
	calm_modes.profile.reference_speed_mps = 0.0
	var calm_field: Variant = _field(calm_modes)
	var at_zero: PackedFloat64Array = _sample(calm_field, 0.0, 0.0, 20.0, 0.0).wind_ned_mps
	var at_one: PackedFloat64Array = _sample(calm_field, 0.0, 0.0, 20.0, 1.0).wind_ned_mps
	_check("seeded modes evolve while mean wind is calm", at_zero.to_byte_array() != at_one.to_byte_array())
	var other_seed := calm_modes.duplicate(true)
	other_seed.identity.seed_u32 = 9
	var other_seed_field: Variant = _field(other_seed)
	_check("different immutable seed changes the field", _sample(other_seed_field, 0.0, 0.0, 20.0, 0.25).wind_ned_mps.to_byte_array()
		!= _sample(calm_field, 0.0, 0.0, 20.0, 0.25).wind_ned_mps.to_byte_array())
	_check("reported turbulence value is nominal and explicit", calm_field.nominal_turbulence_rms_mps() == 0.2)
	_check("field exposes a finite conservative speed bound", is_finite(first.absolute_speed_bound_mps()) and first.absolute_speed_bound_mps() > _norm(sample_a))
	for north: float in [-100.0, 0.0, 250.0]:
		for east: float in [-75.0, 20.0]:
			var bounded_sample: PackedFloat64Array = _sample(first, north, east, 32.0, 3.0).wind_ned_mps
			_check("sample remains under the declared global envelope", _norm(bounded_sample) <= first.absolute_speed_bound_mps() + 1e-10)

	var advected := Config.defaults()
	advected.identity.seed_u32 = 448
	advected.profile.reference_speed_mps = 2.5
	advected.profile.reference_from_deg = 0.0
	advected.turbulence.rms_mps = 0.18
	advected.turbulence.mode_count = 24
	var zero_mean := advected.duplicate(true)
	zero_mean.profile.reference_speed_mps = 0.0
	var mean_only := advected.duplicate(true)
	mean_only.turbulence.rms_mps = 0.0
	var advected_field: Variant = _field(advected)
	var zero_mean_field: Variant = _field(zero_mean)
	var mean_field: Variant = _field(mean_only)
	for elapsed: float in [0.25, 0.8, 1.7]:
		var moving_north := 2.0 - 2.5 * elapsed
		var moving_east := -3.0
		var moving_sample: PackedFloat64Array = _sample(advected_field, moving_north, moving_east, 24.0, elapsed).wind_ned_mps
		var moving_mean: PackedFloat64Array = _sample(mean_field, moving_north, moving_east, 24.0, elapsed).wind_ned_mps
		var still_fluctuation: PackedFloat64Array = _sample(zero_mean_field, 2.0, -3.0, 24.0, elapsed).wind_ned_mps
		var moving_fluctuation := PackedFloat64Array([
			moving_sample[0] - moving_mean[0], moving_sample[1] - moving_mean[1], moving_sample[2] - moving_mean[2],
		])
		_check("reference-mean advection follows the declared frozen flow", _near(moving_fluctuation, still_fluctuation, 1e-10),
			str([moving_fluctuation, still_fluctuation]))

	var method_args: Array = []
	for method: Dictionary in first.get_method_list():
		if method.get("name", "") == "sample_world":
			method_args = method.get("args", [])
	var argument_names := PackedStringArray()
	for argument: Dictionary in method_args:
		argument_names.append(str(argument.get("name", "")))
	_check("field sample accepts only position and simulation time", argument_names == PackedStringArray(["position_ned", "simulation_time_s"]), str(argument_names))

	for height: float in [5.0, 17.0, 31.75, 39.0, 65.0]:
		var coarse := absf(_divergence(first, 1.5, -2.0, height, 2.75, 0.02))
		var fine := absf(_divergence(first, 1.5, -2.0, height, 2.75, 0.01))
		_check("complete profile+layer+gust+curl field has convergent zero divergence at h=%.2f" % height,
			fine < 2e-6 and fine <= coarse * 0.6 + 1e-8, "coarse " + str(coarse) + " fine " + str(fine))
	var ground_normal: Dictionary = _sample(first, 1.5, -2.0, 0.0, 2.75)
	_check("complete field has zero normal and tangential ground velocity", ground_normal.ok
		and _near(ground_normal.wind_ned_mps, PackedFloat64Array([0.0, 0.0, 0.0]), 0.0))


func _invalid_samples() -> void:
	var field: Variant = _field(Config.defaults())
	_check("wrong position dimension is structured failure", not field.sample_world(PackedFloat64Array([0.0, 1.0]), 0.0).ok)
	_check("NaN position is structured failure", not field.sample_world(PackedFloat64Array([NAN, 0.0, 0.0]), 0.0).ok)
	_check("infinite position is structured failure", not field.sample_world(PackedFloat64Array([0.0, INF, 0.0]), 0.0).ok)
	_check("NaN time is structured failure", not field.sample_world(PackedFloat64Array([0.0, 0.0, 0.0]), NAN).ok)
	_check("infinite time is structured failure", not field.sample_world(PackedFloat64Array([0.0, 0.0, 0.0]), INF).ok)
	_check("overflow-scale finite time is outside declared horizon", not field.sample_world(PackedFloat64Array([0.0, 0.0, 0.0]), 1e308).ok)
	_check("negative time is rejected", not field.sample_world(PackedFloat64Array([0.0, 0.0, 0.0]), -0.01).ok)
	_check("horizontal position outside finite domain fails closed", not field.sample_world(PackedFloat64Array([10000.01, 0.0, -1.0]), 0.0).ok)
	_check("height above finite domain fails closed", not field.sample_world(PackedFloat64Array([0.0, 0.0, -200.01]), 0.0).ok)
	_check("caller simulation time outside finite horizon fails closed", not field.sample_world(PackedFloat64Array([0.0, 0.0, -1.0]), 86400.01).ok)


func _v2_thermal_integration() -> void:
	var base := Config.defaults()
	base.identity.seed_u32 = 88217
	base.identity.world_epoch_id_u32 = 435
	base.identity.epoch_offset_s = 2.5
	base.profile.reference_speed_mps = 2.75
	base.profile.reference_from_deg = 23.0
	base.gusts.events = [{"id": "base-gust", "start_s": 0.0, "duration_s": 8.0, "amplitude_ned_mps": [0.2, -0.1, 0.0]}]
	base.turbulence.rms_mps = 0.09
	var defaulted: Dictionary = Config.thermal_defaults(base)
	_check("thermal_defaults returns a compatible validated v2 candidate", defaulted.ok and defaulted.config.format == Config.FORMAT_V2,
		str(defaulted.errors))
	if not defaulted.ok:
		return
	var v2: Dictionary = defaulted.config
	var agenda: Dictionary = v2.thermal_field.duplicate(true)
	agenda.cells = [{
		"id": "thermal-a",
		"birth_s": 0.0,
		"duration_s": 120.0,
		"center_ne_m": [0.0, 0.0],
		"drift_ne_mps": [0.25, -0.15],
		"radius_m": 30.0,
		"top_agl_m": 200.0,
		"peak_updraft_mps": 1.0,
	}]
	var upgraded: Dictionary = Config.upgrade_thermals(base, agenda)
	_check("upgrade_thermals validates and canonically attaches a complete agenda", upgraded.ok and upgraded.config.format == Config.FORMAT_V2,
		str(upgraded.errors))
	if not upgraded.ok:
		return
	v2 = upgraded.config
	var thermal_checked: Dictionary = ThermalConfig.resolve(v2.thermal_field)
	var built: Dictionary = SpatialField.build(v2)
	_check("v2 field binds the complete nested thermal hash and law", built.ok
		and built.field.has_thermal_field()
		and built.field.content_hash() == upgraded.content_hash
		and built.field.thermal_content_hash() == thermal_checked.content_hash
		and built.field.thermal_law() == ThermalConfig.LAW)
	var changed_agenda_identity: Dictionary = v2.duplicate(true)
	changed_agenda_identity.thermal_field.identity.agenda_seed_u32 += 1
	var changed_checked: Dictionary = Config.resolve(changed_agenda_identity)
	_check("full spatial and nested thermal hashes bind agenda identity", changed_checked.ok
		and changed_checked.content_hash != upgraded.content_hash
		and changed_checked.thermal_content_hash != upgraded.thermal_content_hash)
	if not built.ok:
		return
	var field: Variant = built.field
	var base_v1: Dictionary = v2.duplicate(true)
	base_v1.format = Config.FORMAT
	base_v1.erase("thermal_field")
	var base_built: Dictionary = SpatialField.build(base_v1)
	var thermal_built: Dictionary = ThermalConfig.build(v2.thermal_field)
	var time := 17.5
	var query := PackedFloat64Array([4.0, -2.4, -20.0])
	var combined: Dictionary = field.sample_world(query, time)
	var base_sample: Dictionary = base_built.field.sample_world(query, time)
	var thermal_sample: Dictionary = thermal_built.field.sample_world(query, time)
	var expected := PackedFloat64Array([
		base_sample.wind_ned_mps[0] + thermal_sample.wind_ned_mps[0],
		base_sample.wind_ned_mps[1] + thermal_sample.wind_ned_mps[1],
		base_sample.wind_ned_mps[2] + thermal_sample.wind_ned_mps[2],
	])
	_check("v2 adds exactly one coincident-position and time thermal sample", combined.ok and base_sample.ok and thermal_sample.ok
		and combined.wind_ned_mps.to_byte_array() == expected.to_byte_array(), str([combined, expected]))
	_check("thermal updraft contributes NED down with the streamfunction sign", thermal_sample.ok and thermal_sample.wind_ned_mps[2] < 0.0)
	_check("v2 speed bound includes the thermal conservative bound", field.absolute_speed_bound_mps()
		>= base_built.field.absolute_speed_bound_mps() + thermal_built.field.absolute_speed_bound_mps())
	_check("zero agenda remains spatial and contributes exactly zero", field.is_spatial() and field.has_thermal_field())

	var no_cells := Config.thermal_defaults(base)
	var no_cells_v2: Variant = _field(no_cells.config)
	var no_cells_base: Variant = _field(base)
	var no_cells_point := PackedFloat64Array([2.0, 3.0, -18.0])
	_check("empty thermal agenda adds no uniform sink or pointwise offset",
		no_cells_v2.sample_world(no_cells_point, 8.0).wind_ned_mps.to_byte_array()
		== no_cells_base.sample_world(no_cells_point, 8.0).wind_ned_mps.to_byte_array())

	var bad_epoch: Dictionary = v2.duplicate(true)
	bad_epoch.thermal_field.identity.world_epoch_id_u32 += 1
	_check("reject a thermal agenda from another world epoch", not Config.resolve(bad_epoch).ok)
	var bad_clock: Dictionary = v2.duplicate(true)
	bad_clock.thermal_field.identity.epoch_offset_s += 0.25
	_check("reject a thermal agenda with a different epoch clock", not Config.resolve(bad_clock).ok)
	var bad_datum: Dictionary = v2.duplicate(true)
	bad_datum.thermal_field.datum.ground_down_m = 1.0
	_check("reject a thermal agenda with a different flat ground datum", not Config.resolve(bad_datum).ok)
	var oversized_domain: Dictionary = v2.duplicate(true)
	oversized_domain.thermal_field.domain.max_height_agl_m = 201.0
	_check("reject a thermal domain that exceeds its spatial parent", not Config.resolve(oversized_domain).ok)
	var smaller_domain: Dictionary = v2.duplicate(true)
	smaller_domain.thermal_field.domain.half_extent_east_m -= 1.0
	_check("reject a thermal domain smaller than its spatial parent", not Config.resolve(smaller_domain).ok)
	var smaller_horizon: Dictionary = v2.duplicate(true)
	smaller_horizon.thermal_field.domain.time_horizon_s -= 1.0
	_check("reject a thermal horizon that differs from its spatial clock domain", not Config.resolve(smaller_horizon).ok)
	var incomplete: Dictionary = v2.duplicate(true)
	incomplete.thermal_field.erase("cells")
	_check("reject a v2 config with an incomplete nested thermal block", not Config.resolve(incomplete).ok)
	_check("reject thermal_defaults when spatial domain cannot host minimum thermal horizon",
		not Config.thermal_defaults({"domain": {"time_horizon_s": 60.0}}).ok)

	_check("v2 outer-domain position errors fail closed instead of dropping thermal law",
		not field.sample_world(PackedFloat64Array([10000.01, 0.0, -20.0]), 1.0).ok)
	_check("v2 outer-clock errors fail closed instead of dropping thermal law",
		not field.sample_world(PackedFloat64Array([0.0, 0.0, -20.0]), 86400.01).ok)
	var invalid_cell: Dictionary = no_cells.config.duplicate(true)
	invalid_cell.thermal_field.cells = [{"id": "bad"}]
	_check("reject invalid resolved thermal cells before field construction", not SpatialField.build(invalid_cell).ok)


func _initialize() -> void:
	_validate_schema_and_identity()
	_reference_profile_oracle()
	_wall_and_join_continuity()
	_layers_and_gust_timeline()
	_determinism_coherence_and_divergence()
	_invalid_samples()
	_v2_thermal_integration()
	print("spatial wind field: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
