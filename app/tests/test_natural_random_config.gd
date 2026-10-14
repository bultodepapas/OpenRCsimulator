extends SceneTree

const NaturalRandom := preload("res://scenarios/natural_random.gd")
const ScenarioConfig := preload("res://scenarios/scenario_config.gd")
const SolarPosition := preload("res://environment/solar_position.gd")

var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_policy_copy()
	var generated: Dictionary = NaturalRandom.generate(0)
	_check("seed zero generates a valid resolved scenario", bool(generated.get("ok", false)), str(generated.get("errors", [])))
	if not bool(generated.get("ok", false)):
		_finish()
		return
	var scenario: Dictionary = generated.scenario
	_check("scenario has the exact v1 envelope", _has_exact_scenario_keys(scenario))
	_check("scenario uses the fixed default field and one of five stock aircraft",
		scenario.field_id == "default" and ScenarioConfig.EXPECTED_AIRCRAFT_IDS.has(scenario.aircraft_id))
	_check("source identities are lowercase SHA-256 digests",
		_is_sha256(scenario.field_identity) and _is_sha256(scenario.aircraft_identity) and _is_sha256(scenario.model_identity))
	_check("resolved identity survives full-precision JSON round trip", _json_round_trip_is_valid(scenario))
	var sources: Dictionary = ScenarioConfig.validate_sources(scenario)
	_check("current field, aircraft data and model sources match the record", bool(sources.get("ok", false)), str(sources.get("errors", [])))
	_test_strict_mutations(scenario)
	_test_custom_lighting(scenario)
	_finish()


func _test_policy_copy() -> void:
	var first: Dictionary = ScenarioConfig.policy_catalog()
	_check("policy catalog is loaded", not first.is_empty())
	if first.is_empty():
		return
	var expected_low: float = float(first.recipes[0].speed_mps[0])
	first.recipes[0].speed_mps[0] = -1000.0
	var second: Dictionary = ScenarioConfig.policy_catalog()
	_check("policy catalog callers receive detached data", float(second.recipes[0].speed_mps[0]) == expected_low)


func _test_strict_mutations(scenario: Dictionary) -> void:
	var unknown: Dictionary = scenario.duplicate(true)
	unknown["unreviewed"] = true
	_check("unknown scenario keys are rejected", not _valid(unknown))
	var missing: Dictionary = scenario.duplicate(true)
	missing.erase("build_identity")
	_check("missing envelope keys are rejected", not _valid(missing))
	var bad_seed: Dictionary = scenario.duplicate(true)
	bad_seed.seed = -1
	_reseal(bad_seed)
	_check("negative seeds are rejected even with a matching digest", not _valid(bad_seed))
	bad_seed = scenario.duplicate(true)
	bad_seed.seed = 4294967296
	_reseal(bad_seed)
	_check("seeds above uint32 are rejected", not _valid(bad_seed))
	var bad_field: Dictionary = scenario.duplicate(true)
	bad_field.field_id = "workshop"
	_reseal(bad_field)
	_check("non-default field IDs are rejected", not _valid(bad_field))
	var bad_aircraft: Dictionary = scenario.duplicate(true)
	bad_aircraft.aircraft_id = "preview-only"
	_reseal(bad_aircraft)
	_check("non-stock aircraft IDs are rejected", not _valid(bad_aircraft))
	var bad_weather: Dictionary = scenario.duplicate(true)
	bad_weather.weather_config["unreviewed_weather_field"] = 1.0
	_reseal(bad_weather)
	_check("unknown weather v3 keys are rejected", not _valid(bad_weather))
	var bad_daylight: Dictionary = scenario.duplicate(true)
	bad_daylight.daylight_id = "night"
	_reseal(bad_daylight)
	_check("generated night lighting is rejected", not _valid(bad_daylight))
	var bad_capability: Dictionary = scenario.duplicate(true)
	bad_capability.required_capabilities.reverse()
	_reseal(bad_capability)
	_check("capabilities must exactly match the supported set and order", not _valid(bad_capability))
	var bad_digest: Dictionary = scenario.duplicate(true)
	bad_digest.identity = "0".repeat(64)
	_check("tampered canonical identity is rejected", not _valid(bad_digest))
	var float_mutation: Dictionary = scenario.duplicate(true)
	float_mutation.weather_config.qnh_hpa = float(float_mutation.weather_config.qnh_hpa) + 0.000001
	_check("float changes at the published 12-significant-digit identity precision alter the digest",
		ScenarioConfig.identity_for(float_mutation) != scenario.identity and not _valid(float_mutation))


func _test_custom_lighting(scenario: Dictionary) -> void:
	var original: Dictionary = scenario.duplicate(true)
	var legacy: Dictionary = scenario.lighting_config.duplicate(true)
	legacy.mode = "legacy"
	legacy.local_seconds = 2
	var customized: Dictionary = ScenarioConfig.customize_lighting(scenario, legacy)
	_check("valid legacy lighting can customize a generated scenario", not customized.is_empty())
	if not customized.is_empty():
		_check("customization records lineage and changes the identity",
			customized.provenance == "customized" and customized.daylight_id == "custom"
			and customized.parent_identity == scenario.identity and customized.identity != scenario.identity)
		_check("custom scenario still passes cheap strict validation", _valid(customized))
		_check("customization leaves the source record detached", scenario == original)
	var night: Dictionary = legacy.duplicate(true)
	night.mode = "astronomical"
	night.local_seconds = 0
	var solar: Dictionary = SolarPosition.evaluate(night)
	_check("the custom astronomical sample is a real night", bool(solar.get("ok", false)) and float(solar.get("elevation_deg", 0.0)) < -18.0)
	var customized_night: Dictionary = ScenarioConfig.customize_lighting(scenario, night)
	_check("valid night lighting can customize a generated scenario", not customized_night.is_empty() and _valid(customized_night))
	var invalid_lighting: Dictionary = legacy.duplicate(true)
	invalid_lighting["unsupported"] = true
	_check("invalid lighting customization fails closed", ScenarioConfig.customize_lighting(scenario, invalid_lighting).is_empty())


func _json_round_trip_is_valid(scenario: Dictionary) -> bool:
	var parser := JSON.new()
	if parser.parse(JSON.stringify(scenario, "", true, true)) != OK:
		return false
	var checked: Dictionary = ScenarioConfig.validate(parser.data)
	return bool(checked.get("ok", false)) and checked.scenario.identity == scenario.identity \
			and JSON.stringify(checked.scenario, "", true, true) == JSON.stringify(scenario, "", true, true)


func _has_exact_scenario_keys(scenario: Dictionary) -> bool:
	if scenario.size() != ScenarioConfig.SCENARIO_KEYS.size():
		return false
	for key: String in ScenarioConfig.SCENARIO_KEYS:
		if not scenario.has(key):
			return false
	return true


func _is_sha256(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or str(value).length() != 64:
		return false
	for index: int in str(value).length():
		var code: int = str(value).unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true


func _valid(value: Variant) -> bool:
	return bool(ScenarioConfig.validate(value).get("ok", false))


func _reseal(scenario: Dictionary) -> void:
	scenario.identity = ""
	scenario.identity = ScenarioConfig.identity_for(scenario)


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _finish() -> void:
	print("all Natural Random config checks passed" if _failures == 0 else "%d Natural Random config checks failed" % _failures)
	quit(1 if _failures > 0 else 0)
