extends RefCounted
class_name NaturalRandom

const ScenarioConfig := preload("res://scenarios/scenario_config.gd")
const SolarPosition := preload("res://environment/solar_position.gd")
const TimeOfDayConfig := preload("res://environment/time_of_day_config.gd")
const FieldLoader := preload("res://data/field_loader.gd")

const GENERATOR_VERSION := 1
const RECIPE_VERSION := 1
const UINT32_MAX := 4294967295
const RNG_DOMAIN := "openrc-natural-random-v1"
const SOLAR_SCAN_STEP_SECONDS := 300

static var _daylight_times_ready := false
static var _daylight_times: Dictionary = {}


## Build one detached, reproducible v1 scenario without touching scene or simulation state.
static func generate(seed: int, field_path: String = FieldLoader.DEFAULT_PATH) -> Dictionary:
	if seed < 0 or seed > UINT32_MAX:
		return _failure("seed must be an unsigned 32-bit integer")
	var policy_result: Dictionary = ScenarioConfig.policy_catalog()
	if policy_result.is_empty():
		var policy_errors := ScenarioConfig.policy_errors()
		return {"ok": false, "scenario": {}, "errors": policy_errors}

	var aircraft_ids: Array = ScenarioConfig.EXPECTED_AIRCRAFT_IDS
	var aircraft_rng := _rng_for(seed, "aircraft")
	var aircraft_id: String = aircraft_ids[aircraft_rng.randi_range(0, aircraft_ids.size() - 1)]
	var sources: Dictionary = ScenarioConfig.resolve_source_identities(aircraft_id, field_path)
	if not bool(sources.get("ok", false)):
		return {"ok": false, "scenario": {}, "errors": sources.get("errors", PackedStringArray())}

	var recipe_rng := _rng_for(seed, "recipe")
	var recipe: Dictionary = _select_weighted(policy_result.get("recipes", []), recipe_rng.randi_range(0, 99))
	if recipe.is_empty():
		return _failure("the v1 recipe policy is incomplete")
	var daylight_rng := _rng_for(seed, "daylight")
	var daylight: Dictionary = _select_weighted(policy_result.get("daylight", []), daylight_rng.randi_range(0, 99))
	if daylight.is_empty():
		return _failure("the v1 daylight policy is incomplete")
	var local_seconds := _choose_daylight_time(daylight, policy_result, daylight_rng)
	if local_seconds < 0:
		return _failure("no readable astronomical time exists for daylight band '%s'" % daylight.get("id", ""))

	var weather := _make_weather(seed, recipe, daylight, policy_result)
	var lighting := _make_lighting(local_seconds, policy_result)
	var build_identity: Dictionary = ScenarioConfig.current_build_identity()
	if build_identity.is_empty():
		return _failure("the current build identity is invalid")

	var raw: Dictionary = {
		"format": ScenarioConfig.FORMAT,
		"mode": "natural_random",
		"generator_version": GENERATOR_VERSION,
		"recipe_version": RECIPE_VERSION,
		"seed": seed,
		"aircraft_id": aircraft_id,
		"field_id": str(sources.source.get("field_id", "")),
		"field_identity": str(sources.source.get("field_identity", "")),
		"aircraft_identity": str(sources.source.get("aircraft_identity", "")),
		"model_identity": str(sources.source.get("model_identity", "")),
		"start_choice": "airborne",
		"weather_config": weather,
		"lighting_config": lighting,
		"recipe_id": str(recipe.get("id", "")),
		"daylight_id": str(daylight.get("id", "")),
		"provenance": "generated",
		"parent_identity": "",
		"required_capabilities": ScenarioConfig.EXPECTED_CAPABILITIES.duplicate(),
		"build_identity": build_identity,
		"identity": "",
	}
	raw["identity"] = ScenarioConfig.identity_for(raw)
	return ScenarioConfig.validate(raw)


static func _make_weather(seed: int, recipe: Dictionary, daylight: Dictionary, policy: Dictionary) -> Dictionary:
	var still_rng := _rng_for(seed, "perfectly-still")
	var still_roll: int = still_rng.randi_range(0, 99)
	var still: bool = still_roll < int(recipe.get("perfectly_still_probability_pct", 0))
	var intensity_rng := _rng_for(seed, "wind-intensity")
	var atmosphere_rng := _rng_for(seed, "atmosphere")
	var gust_rng := _rng_for(seed, "gust-shape")
	var direction_rng := _rng_for(seed, "wind-direction")
	var turbulence_seed_rng := _rng_for(seed, "turbulence-seed")
	var context: Dictionary = policy.get("field_context", {})
	var sigma_north := 0.0 if still else _draw_band(intensity_rng, recipe.get("horizontal_rms_mps", []))
	var sigma_east := 0.0 if still else _draw_band(intensity_rng, recipe.get("horizontal_rms_mps", []))
	var sigma_down := 0.0 if still else _draw_band(intensity_rng, recipe.get("vertical_rms_mps", []))
	var gust := 0.0 if still else _draw_band(gust_rng, recipe.get("gust_increment_mps", []))
	var gust_up := 0.0
	if not still:
		var max_vertical_gust := float(recipe.get("gust_up_abs_max_mps", 0.0))
		gust_up = _draw_band(gust_rng, [0.0, max_vertical_gust])
		if gust_rng.randi_range(0, 1) == 0:
			gust_up = -gust_up
	var speed := 0.0 if still else _draw_band(intensity_rng, recipe.get("speed_mps", []))
	var from_deg := direction_rng.randf_range(0.0, 360.0)
	var turbulence_seed := int(turbulence_seed_rng.randi()) & UINT32_MAX
	var temperature := _draw_band(atmosphere_rng, daylight.get("temperature_c", []))
	var humidity := _draw_band(atmosphere_rng, daylight.get("relative_humidity_pct", []))
	var qnh := _draw_band(atmosphere_rng, daylight.get("qnh_hpa", []))
	var duration := _draw_band(gust_rng, recipe.get("gust_duration_s", []))
	var period := _draw_band(gust_rng, recipe.get("gust_period_s", []))
	# The catalog keeps every possible period above the duration range; retain the invariant if it changes.
	period = maxf(period, duration + 0.001)
	var delay := _draw_band(gust_rng, recipe.get("gust_delay_s", []))
	var tau := _draw_band(gust_rng, recipe.get("turbulence_tau_s", []))
	return {
		"format": "openrc-weather v3",
		"speed_mps": speed,
		"from_deg": from_deg,
		"gust_mps": gust,
		"gust_up_mps": gust_up,
		"gust_duration_s": duration,
		"gust_period_s": period,
		"gust_delay_s": delay,
		"turbulence_rms_mps": [sigma_north, sigma_east, sigma_down],
		"turbulence_tau_s": tau,
		"turbulence_seed": turbulence_seed,
		"atmosphere_mode": "custom",
		"field_elevation_m": float(context.get("elevation_m", 0.0)),
		"temperature_c": temperature,
		"qnh_hpa": qnh,
		"relative_humidity_pct": humidity,
	}


static func _make_lighting(local_seconds: int, policy: Dictionary) -> Dictionary:
	var context: Dictionary = policy.get("field_context", {})
	return {
		"format": TimeOfDayConfig.FORMAT,
		"mode": "astronomical",
		"date": str(context.get("date", "")),
		"local_seconds": local_seconds,
		"utc_offset_minutes": int(context.get("utc_offset_minutes", 0)),
		"latitude_deg": float(context.get("latitude_deg", 0.0)),
		"longitude_deg": float(context.get("longitude_deg", 0.0)),
		"location_name": str(context.get("location_name", "")),
	}


static func _choose_daylight_time(daylight: Dictionary, policy: Dictionary, rng: RandomNumberGenerator) -> int:
	_prepare_daylight_times(policy)
	var candidates: Array = _daylight_times.get(str(daylight.get("id", "")), [])
	if candidates.is_empty():
		return -1
	return int(candidates[rng.randi_range(0, candidates.size() - 1)])


static func _prepare_daylight_times(policy: Dictionary) -> void:
	if _daylight_times_ready:
		return
	_daylight_times_ready = true
	_daylight_times = {}
	var context: Dictionary = policy.get("field_context", {})
	for daylight_value: Variant in policy.get("daylight", []):
		if typeof(daylight_value) != TYPE_DICTIONARY:
			continue
		var daylight: Dictionary = daylight_value
		var id := str(daylight.get("id", ""))
		var candidates: Array[int] = []
		for local_seconds: int in range(0, 86400, SOLAR_SCAN_STEP_SECONDS):
			var sample: Dictionary = {
				"date": str(context.get("date", "")),
				"local_seconds": local_seconds,
				"utc_offset_minutes": int(context.get("utc_offset_minutes", 0)),
				"latitude_deg": float(context.get("latitude_deg", 0.0)),
				"longitude_deg": float(context.get("longitude_deg", 0.0)),
			}
			var solar: Dictionary = SolarPosition.evaluate(sample)
			if not bool(solar.get("ok", false)):
				continue
			var elevation := float(solar.get("elevation_deg", NAN))
			var hour_angle := float(solar.get("hour_angle_deg", NAN))
			var band: Array = daylight.get("solar_elevation_deg", [])
			if band.size() != 2 or elevation < float(band[0]) or elevation > float(band[1]):
				continue
			var hour_angle_rule := str(daylight.get("hour_angle", "any"))
			if hour_angle_rule == "rising" and hour_angle >= 0.0:
				continue
			if hour_angle_rule == "setting" and hour_angle <= 0.0:
				continue
			candidates.append(local_seconds)
		_daylight_times[id] = candidates


static func _select_weighted(records: Variant, roll: int) -> Dictionary:
	if typeof(records) != TYPE_ARRAY or roll < 0 or roll > 99:
		return {}
	var ceiling := 0
	for record_value: Variant in records:
		if typeof(record_value) != TYPE_DICTIONARY:
			return {}
		var record: Dictionary = record_value
		var weight := int(record.get("weight_pct", 0))
		if weight <= 0:
			return {}
		ceiling += weight
		if roll < ceiling:
			return record
	return {}


static func _draw_band(rng: RandomNumberGenerator, raw_band: Variant) -> float:
	if typeof(raw_band) != TYPE_ARRAY or raw_band.size() != 2:
		return NAN
	var minimum := float(raw_band[0])
	var maximum := float(raw_band[1])
	var unit := (rng.randf() + rng.randf() + rng.randf()) / 3.0
	return lerpf(minimum, maximum, unit)


static func _rng_for(master_seed: int, stream: String) -> RandomNumberGenerator:
	var derived := ("%s|%d|%s" % [RNG_DOMAIN, master_seed, stream]).sha256_text()
	var rng := RandomNumberGenerator.new()
	rng.seed = derived.substr(0, 8).hex_to_int()
	return rng


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "scenario": {}, "errors": PackedStringArray([message])}
