extends SceneTree

const NaturalRandom := preload("res://scenarios/natural_random.gd")
const ScenarioConfig := preload("res://scenarios/scenario_config.gd")
const SolarPosition := preload("res://environment/solar_position.gd")
const AircraftCatalog := preload("res://app_state/aircraft_catalog.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const FieldLoader := preload("res://data/field_loader.gd")

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
	_test_runtime_default_aircraft_sources()
	_test_strict_mutations(scenario)
	_test_small_gust_identities(scenario)
	_test_custom_lighting(scenario)
	_finish()


func _test_runtime_default_aircraft_sources() -> void:
	for aircraft_id: String in ScenarioConfig.EXPECTED_AIRCRAFT_IDS:
		var mode: String = AircraftCatalog.default_battery_mode(aircraft_id)
		var path: String = AircraftCatalog.data_for(aircraft_id, mode)
		var loaded: Dictionary = AircraftData.load_file(path)
		var source: Dictionary = ScenarioConfig.resolve_source_identities(aircraft_id, FieldLoader.DEFAULT_PATH, false)
		_check("scenario identity uses runtime default %s data for %s" % [mode, aircraft_id],
			loaded.get("ok", false) and source.get("ok", false)
			and source.source.aircraft_identity == loaded.get("input_identity", {}).get("sha256", ""),
			str(source.get("errors", [])))

	var turbo_id := "turbo-lumber-evolution"
	var turbo_entry: Dictionary = AircraftCatalog.entry(turbo_id)
	var pack_path: String = AircraftCatalog.data_for(turbo_id, AircraftCatalog.default_battery_mode(turbo_id))
	var base: Dictionary = AircraftData.load_file(str(turbo_entry.get("data", "")))
	var pack: Dictionary = AircraftData.load_file(pack_path)
	var seed_four: Dictionary = NaturalRandom.generate(4)
	_check("seed 4 remains the deterministic Turbo Lumber UI regression draw",
		seed_four.get("ok", false) and seed_four.scenario.aircraft_id == turbo_id)
	_check("seed 4 binds the finite default pack input identity", seed_four.get("ok", false)
		and pack.get("ok", false) and seed_four.scenario.aircraft_identity == pack.input_identity.sha256
		and base.get("ok", false) and seed_four.scenario.aircraft_identity != base.input_identity.sha256)
	if seed_four.get("ok", false) and base.get("ok", false):
		var stale: Dictionary = seed_four.scenario.duplicate(true)
		stale.aircraft_identity = base.input_identity.sha256
		stale.identity = ""
		stale.identity = ScenarioConfig.identity_for(stale)
		_check("changing the default battery source invalidates an old random selection",
			not ScenarioConfig.validate_sources(stale).get("ok", false))


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


func _test_small_gust_identities(scenario: Dictionary) -> void:
	var negative_zero := PackedByteArray([0, 0, 0, 0, 0, 0, 0, 128]).decode_double(0)
	var negative_zero_bits := PackedByteArray()
	negative_zero_bits.resize(8)
	negative_zero_bits.encode_double(0, negative_zero)
	_check("signed-zero fixture preserves the negative bit", negative_zero_bits[7] == 128)
	var reference := {"values": [0.0, 0.0, 1.25, 1.0e-13, 4294967295]}
	var reference_identity := ScenarioConfig.identity_for(reference)
	_check("ordinary numeric identity remains compatible",
		reference_identity == "a972eb16366cafaae3f28423ffc52a8834aa6e69c1a8c93c7a2a4f083125ff9f", reference_identity)
	var signed_reference := {"values": [0.0, negative_zero, 1.25, 1.0e-13, 4294967295]}
	_check("signed zero retains its existing identity",
		ScenarioConfig.identity_for(signed_reference) == "3cd8a6e195c4b2ea15d3f657211bbd39287baa0fc36165b7ef23f6e040f33c5f"
		and ScenarioConfig.identity_for({"value": 0.0}) != ScenarioConfig.identity_for({"value": negative_zero}))
	var zero: Dictionary = scenario.duplicate(true)
	zero.weather_config.gust_up_mps = 0.0
	_reseal(zero)
	var tiny: Dictionary = scenario.duplicate(true)
	tiny.weather_config.gust_up_mps = 1.0e-200
	_reseal(tiny)
	var other_tiny: Dictionary = scenario.duplicate(true)
	other_tiny.weather_config.gust_up_mps = 2.0e-200
	_reseal(other_tiny)
	_check("zero and tiny vertical gusts are accepted scenario values",
		_valid(zero) and _valid(tiny) and _valid(other_tiny))
	_check("zero and a tiny vertical gust have distinct identities", zero.identity != tiny.identity)
	_check("distinct tiny vertical gusts have distinct identities", tiny.identity != other_tiny.identity)
	_check("tiny vertical gust identities survive JSON round trips",
		_json_round_trip_is_valid(tiny) and _json_round_trip_is_valid(other_tiny))
	var stale: Dictionary = tiny.duplicate(true)
	stale.weather_config.gust_up_mps = other_tiny.weather_config.gust_up_mps
	_check("changing a tiny gust without resealing fails validation", not _valid(stale))
	var rounding_low: Dictionary = scenario.duplicate(true)
	rounding_low.weather_config.gust_up_mps = 1.2345678901231e-200
	_reseal(rounding_low)
	var rounding_same: Dictionary = rounding_low.duplicate(true)
	rounding_same.weather_config.gust_up_mps = 1.2345678901234e-200
	_reseal(rounding_same)
	var rounding_high: Dictionary = rounding_low.duplicate(true)
	rounding_high.weather_config.gust_up_mps = 1.2345678901251e-200
	_reseal(rounding_high)
	_check("tiny values retain the published 12-significant-digit precision",
		_valid(rounding_low) and _valid(rounding_same) and _valid(rounding_high)
		and rounding_low.identity == rounding_same.identity and rounding_low.identity != rounding_high.identity)
	var negative: Dictionary = scenario.duplicate(true)
	negative.weather_config.gust_up_mps = -1.0e-200
	_reseal(negative)
	_check("negative tiny gusts are distinct and survive JSON", _valid(negative)
		and negative.identity != tiny.identity and _json_round_trip_is_valid(negative))
	var boundary: Dictionary = scenario.duplicate(true)
	boundary.weather_config.gust_up_mps = 1.0e-13
	_reseal(boundary)
	var boundary_low: Dictionary = boundary.duplicate(true)
	boundary_low.weather_config.gust_up_mps = 9.999999999999e-14
	_reseal(boundary_low)
	_check("rounding across the decimal and scientific boundary preserves identity", _valid(boundary)
		and _valid(boundary_low) and boundary.identity == boundary_low.identity)
	var subnormal: Dictionary = scenario.duplicate(true)
	subnormal.weather_config.gust_up_mps = PackedByteArray([1, 0, 0, 0, 0, 0, 0, 0]).decode_double(0)
	_reseal(subnormal)
	var other_subnormal: Dictionary = scenario.duplicate(true)
	other_subnormal.weather_config.gust_up_mps = PackedByteArray([2, 0, 0, 0, 0, 0, 0, 0]).decode_double(0)
	_reseal(other_subnormal)
	_check("subnormal gusts are nonzero and valid", subnormal.weather_config.gust_up_mps != 0.0
		and other_subnormal.weather_config.gust_up_mps != 0.0 and _valid(subnormal) and _valid(other_subnormal))
	_check("distinct subnormal gusts have distinct identities", subnormal.identity != other_subnormal.identity,
		"%s %s" % [String.num_scientific(subnormal.weather_config.gust_up_mps), String.num_scientific(other_subnormal.weather_config.gust_up_mps)])
	var subnormal_json: String = JSON.stringify(subnormal, "", true, true)
	var subnormal_decoded: Variant = JSON.parse_string(subnormal_json)
	# Godot can underflow this value while decoding JSON. A changed value must fail validation;
	# an engine that preserves the value may instead validate the round trip.
	var decoded_subnormal: float = subnormal_decoded.weather_config.gust_up_mps
	_check("subnormal JSON either preserves the value or fails validation on underflow",
		(decoded_subnormal == subnormal.weather_config.gust_up_mps and _valid(subnormal_decoded))
		or (decoded_subnormal == 0.0 and not _valid(subnormal_decoded)))


func _json_round_trip_is_valid(scenario: Dictionary) -> bool:
	var parser := JSON.new()
	if parser.parse(JSON.stringify(scenario, "", true, true)) != OK:
		return false
	var checked: Dictionary = ScenarioConfig.validate(parser.data)
	# Decoding may move a float by one ULP; validation must retain decoded values even when the
	# 12-significant-digit identity deliberately treats that transport difference as equivalent.
	return bool(checked.get("ok", false)) and checked.scenario.identity == scenario.identity \
			and _same_full_precision_value(checked.scenario, parser.data)


func _same_full_precision_value(actual: Variant, expected: Variant) -> bool:
	var actual_type := typeof(actual)
	var expected_type := typeof(expected)
	var actual_is_number := actual_type in [TYPE_INT, TYPE_FLOAT]
	var expected_is_number := expected_type in [TYPE_INT, TYPE_FLOAT]
	if actual_is_number or expected_is_number:
		return actual_is_number and expected_is_number and float(actual) == float(expected)
	if actual_type != expected_type:
		return false
	if actual_type == TYPE_DICTIONARY:
		if actual.size() != expected.size():
			return false
		for key: Variant in actual:
			if not expected.has(key) or not _same_full_precision_value(actual[key], expected[key]):
				return false
		return true
	if actual_type == TYPE_ARRAY:
		if actual.size() != expected.size():
			return false
		for index: int in actual.size():
			if not _same_full_precision_value(actual[index], expected[index]):
				return false
		return true
	return actual == expected


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
