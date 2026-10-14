extends RefCounted
class_name ScenarioConfig

const WindConfig := preload("res://physics/wind_config.gd")
const TimeOfDayConfig := preload("res://environment/time_of_day_config.gd")
const SolarPosition := preload("res://environment/solar_position.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const AircraftCatalog := preload("res://app_state/aircraft_catalog.gd")
const ModelRegistry := preload("res://aircraft/model_registry.gd")

const FORMAT := "openrc-flight-scenario v1"
const CATALOG_PATH := "res://data/scenarios/natural_random_v1.json"
const EXPECTED_FIELD_ID := "default"
const UINT32_MAX := 4294967295
const EXPECTED_AIRCRAFT_IDS: Array[String] = [
	"jensen-das-ugly-stik-60",
	"gp-extra-300s-60",
	"p51d-mustang-120",
	"sebart-avanti-s-a200-p100rx",
	"turbo-lumber-evolution",
]
const EXPECTED_RECIPE_IDS: Array[String] = ["calm_air", "gentle_breeze", "lively_afternoon", "windy_day"]
const EXPECTED_DAYLIGHT_IDS: Array[String] = ["morning", "day", "afternoon"]
const EXPECTED_CAPABILITIES: Array[String] = ["airborne_start", "fixed_lighting_snapshot", "weather_v3"]
const SCENARIO_KEYS: Array[String] = [
	"format", "mode", "generator_version", "recipe_version", "seed", "aircraft_id",
	"field_id", "field_identity", "aircraft_identity", "model_identity", "start_choice",
	"weather_config", "lighting_config", "recipe_id", "daylight_id", "provenance",
	"parent_identity", "required_capabilities", "build_identity", "identity",
]
const BUILD_IDENTITY_KEYS: Array[String] = [
	"engine_version", "application_version", "describe", "commit", "dirty", "commit_date",
]

static var _policy_loaded := false
static var _policy_ok := false
static var _policy: Dictionary = {}
static var _policy_errors := PackedStringArray()
static var _source_cache: Dictionary = {}


## Read-only copy of the versioned recipe policy. The returned dictionary must not be modified.
static func policy_catalog() -> Dictionary:
	_policy_status()
	return _policy.duplicate(true)


static func policy_errors() -> PackedStringArray:
	_policy_status()
	return _policy_errors.duplicate()


## Validate an untrusted resolved flight record, normalize its nested inputs and verify its digest.
## No source files, scenes, preferences or simulation state are loaded here.
static func validate(raw: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("scenario: expected an object")
		return _failure(errors)
	var source: Dictionary = raw
	_check_exact_keys(errors, "scenario", source, SCENARIO_KEYS)
	if not errors.is_empty():
		return _failure(errors)

	var policy_result := _policy_status()
	if not bool(policy_result.get("ok", false)):
		errors.append_array(_policy_errors)
		return _failure(errors)
	var policy: Dictionary = _policy

	if source.format != FORMAT:
		errors.append("scenario.format must be '%s'" % FORMAT)
	if source.mode != "natural_random":
		errors.append("scenario.mode must be 'natural_random'")
	var generator_version := _integer_value(source.get("generator_version"), "scenario.generator_version", 1, 1, errors)
	var recipe_version := _integer_value(source.get("recipe_version"), "scenario.recipe_version", 1, 1, errors)
	var seed_value := _integer_value(source.get("seed"), "scenario.seed", 0, UINT32_MAX, errors)
	var aircraft_id := _read_string(source.get("aircraft_id"), "scenario.aircraft_id", errors)
	if not EXPECTED_AIRCRAFT_IDS.has(aircraft_id):
		errors.append("scenario.aircraft_id is not in the Natural Random stock allowlist")
	var field_id := _read_slug(source.get("field_id"), "scenario.field_id", errors)
	if field_id != EXPECTED_FIELD_ID:
		errors.append("scenario.field_id must be the fixed v1 field '%s'" % EXPECTED_FIELD_ID)
	var field_identity := _read_sha256(source.get("field_identity"), "scenario.field_identity", errors)
	var aircraft_identity := _read_sha256(source.get("aircraft_identity"), "scenario.aircraft_identity", errors)
	var model_identity := _read_sha256(source.get("model_identity"), "scenario.model_identity", errors)
	var start_choice := _read_string(source.get("start_choice"), "scenario.start_choice", errors)
	if start_choice != "airborne":
		errors.append("scenario.start_choice must be 'airborne' in Natural Random v1")
	var recipe_id := _read_string(source.get("recipe_id"), "scenario.recipe_id", errors)
	var recipe: Dictionary = _find_record(policy.get("recipes", []), recipe_id)
	if recipe.is_empty():
		errors.append("scenario.recipe_id is not a supported Natural Random v1 recipe")
	var daylight_id := _read_string(source.get("daylight_id"), "scenario.daylight_id", errors)
	var provenance := _read_string(source.get("provenance"), "scenario.provenance", errors)
	if provenance not in ["generated", "customized"]:
		errors.append("scenario.provenance must be 'generated' or 'customized'")
	var parent_identity: String = ""
	if provenance == "generated":
		parent_identity = _read_string(source.get("parent_identity"), "scenario.parent_identity", errors, true)
		if not parent_identity.is_empty():
			errors.append("generated scenarios must have an empty parent_identity")
	elif provenance == "customized":
		parent_identity = _read_sha256(source.get("parent_identity"), "scenario.parent_identity", errors)
	if provenance == "generated" and not EXPECTED_DAYLIGHT_IDS.has(daylight_id):
		errors.append("generated scenario.daylight_id must be morning, day or afternoon")
	elif provenance == "customized" and daylight_id != "custom":
		errors.append("customized scenario.daylight_id must be 'custom'")

	var capabilities: Array[String] = _read_string_array(source.get("required_capabilities"), "scenario.required_capabilities", errors)
	if capabilities != EXPECTED_CAPABILITIES:
		errors.append("scenario.required_capabilities must exactly match the supported v1 capability list")
	var build_identity := _validate_build_identity(source.get("build_identity"), errors)
	var weather_result: Dictionary = WindConfig.validate(source.get("weather_config"))
	var weather: Dictionary = {}
	if not bool(weather_result.get("ok", false)):
		errors.append_array(weather_result.get("errors", PackedStringArray()))
	else:
		weather = weather_result.config
		if weather.get("format") != WindConfig.ATMOSPHERE_FORMAT:
			errors.append("scenario.weather_config must use openrc-weather v3")
		elif not recipe.is_empty():
			_validate_weather_for_recipe(errors, weather, recipe, policy, daylight_id, provenance)

	var lighting_result: Dictionary = TimeOfDayConfig.validate(source.get("lighting_config"))
	var lighting: Dictionary = {}
	if not bool(lighting_result.get("ok", false)):
		errors.append_array(lighting_result.get("errors", []))
	else:
		lighting = lighting_result.config
		if provenance == "generated" and EXPECTED_DAYLIGHT_IDS.has(daylight_id):
			_validate_generated_lighting(errors, lighting, daylight_id, policy)

	var normalized: Dictionary = {
		"format": FORMAT,
		"mode": "natural_random",
		"generator_version": generator_version,
		"recipe_version": recipe_version,
		"seed": seed_value,
		"aircraft_id": aircraft_id,
		"field_id": field_id,
		"field_identity": field_identity,
		"aircraft_identity": aircraft_identity,
		"model_identity": model_identity,
		"start_choice": start_choice,
		"weather_config": weather,
		"lighting_config": lighting,
		"recipe_id": recipe_id,
		"daylight_id": daylight_id,
		"provenance": provenance,
		"parent_identity": parent_identity,
		"required_capabilities": capabilities,
		"build_identity": build_identity,
		"identity": _read_sha256(source.get("identity"), "scenario.identity", errors),
	}
	if not errors.is_empty():
		return _failure(errors)
	var expected_identity := identity_for(normalized)
	if normalized.identity != expected_identity:
		errors.append("scenario.identity does not match the canonical resolved scenario content")
		return _failure(errors)
	return {"ok": true, "scenario": normalized, "errors": PackedStringArray()}


## Return a detached, re-sealed scenario with a validated fixed-time lighting configuration.
## Invalid scenario or lighting input returns an empty dictionary; callers can validate the inputs for errors.
static func customize_lighting(scenario: Variant, lighting_config: Variant) -> Dictionary:
	var checked: Dictionary = validate(scenario)
	if not bool(checked.get("ok", false)):
		return {}
	var lighting_result: Dictionary = TimeOfDayConfig.validate(lighting_config)
	if not bool(lighting_result.get("ok", false)):
		return {}
	var customized: Dictionary = checked.scenario.duplicate(true)
	customized["lighting_config"] = lighting_result.config.duplicate(true)
	customized["daylight_id"] = "custom"
	customized["provenance"] = "customized"
	customized["parent_identity"] = str(checked.scenario.identity)
	customized["identity"] = ""
	customized["identity"] = identity_for(customized)
	var result: Dictionary = validate(customized)
	return result.scenario if bool(result.get("ok", false)) else {}


## SHA-256 over the whole resolved scenario except its identity field.
## Dictionary keys are sorted and numeric values are canonicalized to 12 significant decimal digits.
## This digest precision avoids a one-ULP drift observed when Godot parses serialized float64 JSON;
## stored scenario values and transport JSON remain full precision. Identity is therefore a content
## check at 12 significant digits, not a bit-exact digest of every stored float bit.
static func identity_for(scenario: Variant) -> String:
	if typeof(scenario) != TYPE_DICTIONARY:
		return ""
	var canonical: Dictionary = scenario.duplicate(true)
	canonical.erase("identity")
	return JSON.stringify(_sorted_value(canonical), "", true, true).sha256_text()


## Read and validate the exact field bytes used to create their source identity.
static func load_field_source(path: String = FieldLoader.DEFAULT_PATH) -> Dictionary:
	if path.strip_edges().is_empty():
		return {"ok": false, "field": {}, "identity": "", "errors": PackedStringArray(["field path is empty"])}
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return {"ok": false, "field": {}, "identity": "", "errors": PackedStringArray(["%s: cannot read field file (error %d)" % [path, FileAccess.get_open_error()]])}
	var parser := JSON.new()
	var parse_error: Error = parser.parse(bytes.get_string_from_utf8())
	if parse_error != OK:
		return {"ok": false, "field": {}, "identity": "", "errors": PackedStringArray(["%s: JSON error at line %d: %s" % [path, parser.get_error_line(), parser.get_error_message()]])}
	var checked: Dictionary = FieldLoader.validate(parser.data)
	if not bool(checked.get("ok", false)):
		return {"ok": false, "field": {}, "identity": "", "errors": checked.get("errors", PackedStringArray())}
	return {
		"ok": true,
		"field": checked.field.duplicate(true),
		"identity": _sha256(bytes),
		"errors": PackedStringArray(),
	}


## Resolve immutable source identities. Generation may reuse same-process profiles; source verification always bypasses this cache.
static func resolve_source_identities(aircraft_id: String, field_path: String = FieldLoader.DEFAULT_PATH,
		use_cache: bool = true) -> Dictionary:
	if not EXPECTED_AIRCRAFT_IDS.has(aircraft_id):
		return {"ok": false, "source": {}, "errors": PackedStringArray(["aircraft_id is not in the Natural Random stock allowlist"])}
	var field_key := "field|%s|%s" % [field_path, _file_stamp(field_path)]
	var field_source: Dictionary = {}
	if use_cache and _source_cache.has(field_key):
		field_source = _source_cache[field_key].duplicate(true)
	else:
		field_source = load_field_source(field_path)
		if bool(field_source.get("ok", false)) and use_cache:
			_source_cache[field_key] = field_source.duplicate(true)
	if not bool(field_source.get("ok", false)):
		return {"ok": false, "source": {}, "errors": field_source.get("errors", PackedStringArray())}

	var entry: Dictionary = AircraftCatalog.entry(aircraft_id)
	if entry.is_empty() or entry.get("data", "").is_empty() or entry.get("status", "") == AircraftCatalog.PREVIEW:
		return {"ok": false, "source": {}, "errors": PackedStringArray(["aircraft catalog has no stock flight data for '%s'" % aircraft_id])}
	var visual_family := str(entry.get("visual_family", ""))
	if visual_family.is_empty():
		return {"ok": false, "source": {}, "errors": PackedStringArray(["aircraft catalog has no visual family for '%s'" % aircraft_id])}
	var data_path := str(entry.data)
	var model_path := "res://data/aircraft_models/%s.json" % visual_family
	var aircraft_key := "aircraft|%s|%s|%s|%s" % [aircraft_id, data_path, _file_stamp(data_path), _file_stamp(model_path)]
	var aircraft_source: Dictionary = {}
	if use_cache and _source_cache.has(aircraft_key):
		aircraft_source = _source_cache[aircraft_key].duplicate(true)
	else:
		var loaded: Dictionary = AircraftData.load_file(data_path)
		if not bool(loaded.get("ok", false)):
			return {"ok": false, "source": {}, "errors": loaded.get("errors", PackedStringArray())}
		var input_identity: Variant = loaded.get("input_identity", {})
		if typeof(input_identity) != TYPE_DICTIONARY or input_identity.get("format") != "openrc-aircraft v2":
			return {"ok": false, "source": {}, "errors": PackedStringArray(["aircraft source did not expose its accepted openrc-aircraft v2 byte identity"])}
		var described: Dictionary = ModelRegistry.describe(visual_family)
		if not bool(described.get("ok", false)):
			return {"ok": false, "source": {}, "errors": described.get("errors", PackedStringArray())}
		aircraft_source = {
			"aircraft_identity": str(input_identity.get("sha256", "")),
			"model_identity": str(described.get("manifest_sha256", "")),
		}
		if not _is_sha256(str(aircraft_source.aircraft_identity)) or not _is_sha256(str(aircraft_source.model_identity)):
			return {"ok": false, "source": {}, "errors": PackedStringArray(["accepted aircraft or model source did not expose a SHA-256 identity"])}
		if use_cache:
			_source_cache[aircraft_key] = aircraft_source.duplicate(true)

	return {
		"ok": true,
		"source": {
			"field_id": str(field_source.field.get("id", "")),
			"field_identity": str(field_source.identity),
			"aircraft_identity": str(aircraft_source.aircraft_identity),
			"model_identity": str(aircraft_source.model_identity),
		},
		"errors": PackedStringArray(),
	}


## Re-read, structurally validate and compare the exact field, aircraft and model sources before launch.
static func validate_sources(scenario: Variant, field_path: String = FieldLoader.DEFAULT_PATH) -> Dictionary:
	var errors := PackedStringArray()
	var checked: Dictionary = validate(scenario)
	if not bool(checked.get("ok", false)):
		return {"ok": false, "errors": checked.get("errors", PackedStringArray())}
	var current: Dictionary = resolve_source_identities(str(checked.scenario.aircraft_id), field_path, false)
	if not bool(current.get("ok", false)):
		return {"ok": false, "errors": current.get("errors", PackedStringArray())}
	var source: Dictionary = current.source
	var accepted: Dictionary = checked.scenario
	if source.field_id != accepted.field_id:
		errors.append("field ID changed after the scenario was drawn")
	if source.field_identity != accepted.field_identity:
		errors.append("field source bytes changed after the scenario was drawn")
	if source.aircraft_identity != accepted.aircraft_identity:
		errors.append("aircraft source bytes changed after the scenario was drawn")
	if source.model_identity != accepted.model_identity:
		errors.append("aircraft model manifest changed after the scenario was drawn")
	return {"ok": errors.is_empty(), "errors": errors}


static func current_build_identity() -> Dictionary:
	var version: Dictionary = Engine.get_version_info()
	var identity: Dictionary = {
		"engine_version": str(version.get("string", "")),
		"application_version": str(ProjectSettings.get_setting("application/config/version", "")),
		"describe": "development",
		"commit": "",
		"dirty": true,
		"commit_date": "",
	}
	if not FileAccess.file_exists("res://build_info.json"):
		return identity
	var parser := JSON.new()
	var parse_error: Error = parser.parse(FileAccess.get_file_as_string("res://build_info.json"))
	if parse_error != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {}
	var build: Dictionary = parser.data
	if build.get("format") != "openrc-build v1":
		return {}
	identity["describe"] = build.get("describe", "")
	identity["commit"] = build.get("commit", "")
	identity["dirty"] = build.get("dirty", false)
	identity["commit_date"] = build.get("commit_date", "")
	return identity


static func _validate_build_identity(value: Variant, errors: PackedStringArray) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("scenario.build_identity must be an object")
		return {}
	var identity: Dictionary = value
	_check_exact_keys(errors, "scenario.build_identity", identity, BUILD_IDENTITY_KEYS)
	var result: Dictionary = {}
	for key: String in ["engine_version", "application_version", "describe"]:
		result[key] = _read_string(identity.get(key), "scenario.build_identity." + key, errors)
	for key: String in ["commit", "commit_date"]:
		result[key] = _read_string(identity.get(key), "scenario.build_identity." + key, errors, true)
	var dirty: Variant = identity.get("dirty")
	if typeof(dirty) != TYPE_BOOL:
		errors.append("scenario.build_identity.dirty must be a boolean")
		result["dirty"] = false
	else:
		result["dirty"] = dirty
	return result


static func _validate_weather_for_recipe(errors: PackedStringArray, weather: Dictionary,
		recipe: Dictionary, policy: Dictionary, daylight_id: String, provenance: String) -> void:
	_check_band(errors, "weather_config.speed_mps", weather.get("speed_mps"), recipe.get("speed_mps"))
	_check_band(errors, "weather_config.gust_mps", weather.get("gust_mps"), recipe.get("gust_increment_mps"))
	if _finite(weather.get("gust_up_mps")) and absf(float(weather.gust_up_mps)) > float(recipe.get("gust_up_abs_max_mps", -1.0)):
		errors.append("weather_config.gust_up_mps exceeds the recipe's v1 vertical gust bound")
	_check_band(errors, "weather_config.gust_duration_s", weather.get("gust_duration_s"), recipe.get("gust_duration_s"))
	_check_band(errors, "weather_config.gust_period_s", weather.get("gust_period_s"), recipe.get("gust_period_s"))
	_check_band(errors, "weather_config.gust_delay_s", weather.get("gust_delay_s"), recipe.get("gust_delay_s"))
	_check_band(errors, "weather_config.turbulence_tau_s", weather.get("turbulence_tau_s"), recipe.get("turbulence_tau_s"))
	if _finite(weather.get("gust_duration_s")) and _finite(weather.get("gust_period_s")) \
			and float(weather.gust_period_s) <= float(weather.gust_duration_s):
		errors.append("weather_config.gust_period_s must be greater than gust_duration_s")
	var rms: Variant = weather.get("turbulence_rms_mps")
	if typeof(rms) == TYPE_ARRAY and rms.size() == 3:
		_check_band(errors, "weather_config.turbulence_rms_mps[0]", rms[0], recipe.get("horizontal_rms_mps"))
		_check_band(errors, "weather_config.turbulence_rms_mps[1]", rms[1], recipe.get("horizontal_rms_mps"))
		_check_band(errors, "weather_config.turbulence_rms_mps[2]", rms[2], recipe.get("vertical_rms_mps"))
	if provenance == "generated":
		var daylight: Dictionary = _find_record(policy.get("daylight", []), daylight_id)
		if not daylight.is_empty():
			var context: Dictionary = policy.get("field_context", {})
			if float(weather.get("field_elevation_m", NAN)) != float(context.get("elevation_m", NAN)):
				errors.append("weather_config.field_elevation_m must match the fixed v1 synthetic field context")
			_check_band(errors, "weather_config.temperature_c", weather.get("temperature_c"), daylight.get("temperature_c"))
			_check_band(errors, "weather_config.relative_humidity_pct", weather.get("relative_humidity_pct"), daylight.get("relative_humidity_pct"))
			_check_band(errors, "weather_config.qnh_hpa", weather.get("qnh_hpa"), daylight.get("qnh_hpa"))
	else:
		var context: Dictionary = policy.get("field_context", {})
		if float(weather.get("field_elevation_m", NAN)) != float(context.get("elevation_m", NAN)):
			errors.append("customized scenario atmosphere must retain the fixed v1 field elevation")
		_check_union_band(errors, "weather_config.temperature_c", weather.get("temperature_c"), policy, "temperature_c")
		_check_union_band(errors, "weather_config.relative_humidity_pct", weather.get("relative_humidity_pct"), policy, "relative_humidity_pct")
		_check_union_band(errors, "weather_config.qnh_hpa", weather.get("qnh_hpa"), policy, "qnh_hpa")


static func _validate_generated_lighting(errors: PackedStringArray, lighting: Dictionary, daylight_id: String,
		policy: Dictionary) -> void:
	var context: Dictionary = policy.get("field_context", {})
	var daylight: Dictionary = _find_record(policy.get("daylight", []), daylight_id)
	if lighting.get("mode") != "astronomical":
		errors.append("generated scenario lighting must be an astronomical snapshot")
	for key: String in ["date", "utc_offset_minutes", "latitude_deg", "longitude_deg", "location_name"]:
		if lighting.get(key) != context.get(key):
			errors.append("generated scenario lighting.%s must match the fixed v1 synthetic field context" % key)
	if daylight.is_empty():
		return
	var solar: Dictionary = SolarPosition.evaluate(lighting)
	if not bool(solar.get("ok", false)):
		errors.append_array(solar.get("errors", []))
		return
	var elevation_band: Array = daylight.get("solar_elevation_deg", [])
	if elevation_band.size() == 2 and (float(solar.elevation_deg) < float(elevation_band[0]) or float(solar.elevation_deg) > float(elevation_band[1])):
		errors.append("scenario daylight solar elevation is outside its readable v1 window")
	var hour_angle := float(solar.get("hour_angle_deg", NAN))
	if daylight.get("hour_angle") == "rising" and hour_angle >= 0.0:
		errors.append("morning scenario must use a rising sun")
	elif daylight.get("hour_angle") == "setting" and hour_angle <= 0.0:
		errors.append("afternoon scenario must use a setting sun")


static func _check_union_band(errors: PackedStringArray, path: String, value: Variant,
		policy: Dictionary, key: String) -> void:
	var matches := false
	for daylight: Dictionary in policy.get("daylight", []):
		var band: Variant = daylight.get(key)
		if _in_band(value, band):
			matches = true
	if not matches:
		errors.append("%s is outside the v1 atmosphere range" % path)


static func _check_band(errors: PackedStringArray, path: String, value: Variant, band: Variant) -> void:
	if not _in_band(value, band):
		errors.append("%s is outside its Natural Random recipe range" % path)


static func _in_band(value: Variant, band: Variant) -> bool:
	if not _finite(value) or typeof(band) != TYPE_ARRAY or band.size() != 2:
		return false
	if not _finite(band[0]) or not _finite(band[1]):
		return false
	return float(value) >= float(band[0]) and float(value) <= float(band[1])


static func _find_record(records: Variant, id: String) -> Dictionary:
	if typeof(records) != TYPE_ARRAY:
		return {}
	for record: Variant in records:
		if typeof(record) == TYPE_DICTIONARY and str(record.get("id", "")) == id:
			return record
	return {}


static func _policy_status() -> Dictionary:
	if _policy_loaded:
		return {"ok": _policy_ok, "errors": _policy_errors}
	_policy_loaded = true
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(CATALOG_PATH)
	if bytes.is_empty():
		_policy_errors = PackedStringArray(["Natural Random recipe catalog cannot be read: %s" % CATALOG_PATH])
		return {"ok": false, "errors": _policy_errors}
	var parser := JSON.new()
	var parse_error: Error = parser.parse(bytes.get_string_from_utf8())
	if parse_error != OK or typeof(parser.data) != TYPE_DICTIONARY:
		_policy_errors = PackedStringArray(["Natural Random recipe catalog is invalid JSON or not an object"])
		return {"ok": false, "errors": _policy_errors}
	var parsed: Dictionary = parser.data
	var validation_errors := PackedStringArray()
	_validate_policy(validation_errors, parsed)
	if not validation_errors.is_empty():
		_policy_errors = validation_errors
		return {"ok": false, "errors": _policy_errors}
	_policy = parsed.duplicate(true)
	_policy_ok = true
	return {"ok": true, "errors": PackedStringArray()}


static func _validate_policy(errors: PackedStringArray, value: Dictionary) -> void:
	_check_exact_keys(errors, "catalog", value, [
		"format", "generator_version", "recipe_version", "qualification_status", "qualification_note",
		"aircraft_ids", "start_choice", "required_capabilities", "field_context", "recipes", "daylight",
	])
	if value.get("format") != "openrc-natural-random-catalog v1":
		errors.append("catalog.format must be 'openrc-natural-random-catalog v1'")
	if value.get("generator_version") != 1 or value.get("recipe_version") != 1:
		errors.append("catalog generator and recipe versions must both be 1")
	if value.get("qualification_status") != "software_bounds_only":
		errors.append("catalog must not claim physical or pilot acceptance")
	if typeof(value.get("qualification_note")) != TYPE_STRING or str(value.qualification_note).strip_edges().is_empty():
		errors.append("catalog.qualification_note must describe its evidence status")
	if value.get("aircraft_ids") != EXPECTED_AIRCRAFT_IDS:
		errors.append("catalog.aircraft_ids must match the fixed five-aircraft v1 order")
	if value.get("start_choice") != "airborne":
		errors.append("catalog.start_choice must be airborne")
	if value.get("required_capabilities") != EXPECTED_CAPABILITIES:
		errors.append("catalog.required_capabilities must match the fixed v1 capability list")
	var context: Variant = value.get("field_context")
	if typeof(context) != TYPE_DICTIONARY:
		errors.append("catalog.field_context must be an object")
	else:
		_check_exact_keys(errors, "catalog.field_context", context, [
			"elevation_m", "date", "utc_offset_minutes", "latitude_deg", "longitude_deg", "location_name",
		])
		if not _finite(context.get("elevation_m")) or float(context.get("elevation_m")) != 0.0:
			errors.append("catalog.field_context.elevation_m must retain the synthetic sea-level v1 value")
		if typeof(context.get("date")) != TYPE_STRING or typeof(context.get("location_name")) != TYPE_STRING:
			errors.append("catalog field context date and location name must be strings")
	if typeof(value.get("recipes")) != TYPE_ARRAY or value.recipes.size() != EXPECTED_RECIPE_IDS.size():
		errors.append("catalog.recipes must contain the four ordered v1 recipes")
	else:
		var expected_weights: Array[int] = [20, 40, 25, 15]
		for index: int in EXPECTED_RECIPE_IDS.size():
			var item: Variant = value.recipes[index]
			if typeof(item) != TYPE_DICTIONARY:
				errors.append("catalog.recipes[%d] must be an object" % index)
				continue
			_check_exact_keys(errors, "catalog.recipes[%d]" % index, item, [
				"id", "weight_pct", "speed_mps", "gust_increment_mps", "gust_up_abs_max_mps",
				"horizontal_rms_mps", "vertical_rms_mps", "perfectly_still_probability_pct",
				"gust_duration_s", "gust_period_s", "gust_delay_s", "turbulence_tau_s",
			])
			if item.get("id") != EXPECTED_RECIPE_IDS[index] or item.get("weight_pct") != expected_weights[index]:
				errors.append("catalog recipe order or target weight changed without a recipe version")
			for key: String in ["speed_mps", "gust_increment_mps", "horizontal_rms_mps", "vertical_rms_mps",
				"gust_duration_s", "gust_period_s", "gust_delay_s", "turbulence_tau_s"]:
				if not _valid_range_pair(item.get(key)):
					errors.append("catalog.recipes[%d].%s must be an ordered finite range" % [index, key])
	if typeof(value.get("daylight")) != TYPE_ARRAY or value.daylight.size() != EXPECTED_DAYLIGHT_IDS.size():
		errors.append("catalog.daylight must contain the three ordered v1 daylight groups")
	else:
		var expected_weights: Array[int] = [25, 50, 25]
		for index: int in EXPECTED_DAYLIGHT_IDS.size():
			var item: Variant = value.daylight[index]
			if typeof(item) != TYPE_DICTIONARY:
				errors.append("catalog.daylight[%d] must be an object" % index)
				continue
			_check_exact_keys(errors, "catalog.daylight[%d]" % index, item, [
				"id", "weight_pct", "solar_elevation_deg", "hour_angle", "temperature_c",
				"relative_humidity_pct", "qnh_hpa",
			])
			if item.get("id") != EXPECTED_DAYLIGHT_IDS[index] or item.get("weight_pct") != expected_weights[index]:
				errors.append("catalog daylight order or target weight changed without a recipe version")
			for key: String in ["solar_elevation_deg", "temperature_c", "relative_humidity_pct", "qnh_hpa"]:
				if not _valid_range_pair(item.get(key)):
					errors.append("catalog.daylight[%d].%s must be an ordered finite range" % [index, key])
			if item.get("hour_angle") not in ["rising", "any", "setting"]:
				errors.append("catalog daylight hour_angle must be rising, any or setting")


static func _valid_range_pair(value: Variant) -> bool:
	return typeof(value) == TYPE_ARRAY and value.size() == 2 and _finite(value[0]) \
			and _finite(value[1]) and float(value[0]) <= float(value[1])


static func _check_exact_keys(errors: PackedStringArray, path: String, value: Dictionary,
		required: Array) -> void:
	for key: Variant in required:
		if not value.has(key):
			errors.append("%s: missing required field '%s'" % [path, str(key)])
	for key: Variant in value.keys():
		if typeof(key) != TYPE_STRING or not required.has(key):
			errors.append("%s: unknown field '%s'" % [path, str(key)])


static func _read_string(value: Variant, path: String, errors: PackedStringArray, allow_empty := false) -> String:
	if typeof(value) != TYPE_STRING or (not allow_empty and str(value).strip_edges().is_empty()):
		errors.append("%s must be %s string" % [path, "a string" if allow_empty else "a nonempty"])
		return ""
	return str(value)


static func _read_slug(value: Variant, path: String, errors: PackedStringArray) -> String:
	var slug := _read_string(value, path, errors)
	if slug.is_empty():
		return slug
	if slug.length() > 64:
		errors.append("%s must be a lowercase slug no longer than 64 characters" % path)
		return slug
	for index: int in slug.length():
		var code: int = slug.unicode_at(index)
		if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 45 or code == 95):
			errors.append("%s must contain only lowercase letters, numbers, hyphens and underscores" % path)
			break
	return slug


static func _read_sha256(value: Variant, path: String, errors: PackedStringArray) -> String:
	if typeof(value) != TYPE_STRING or not _is_sha256(str(value)):
		errors.append("%s must be a lowercase 64-character SHA-256 digest" % path)
		return ""
	return str(value)


static func _read_string_array(value: Variant, path: String, errors: PackedStringArray) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s must be an array of strings" % path)
		return result
	for index: int in value.size():
		if typeof(value[index]) != TYPE_STRING:
			errors.append("%s[%d] must be a string" % [path, index])
		else:
			result.append(str(value[index]))
	return result


static func _integer_value(value: Variant, path: String, minimum: int, maximum: int,
		errors: PackedStringArray) -> int:
	if not _finite(value) or float(value) < float(minimum) or float(value) > float(maximum) or floor(float(value)) != float(value):
		errors.append("%s must be an integer in [%d, %d]" % [path, minimum, maximum])
		return minimum
	return int(value)


static func _finite(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index: int in value.length():
		var code: int = value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true


static func _sha256(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()


static func _file_stamp(path: String) -> String:
	var absolute := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	var modified: int = FileAccess.get_modified_time(absolute)
	var length := -1
	var file := FileAccess.open(path, FileAccess.READ)
	if file != null:
		length = file.get_length()
		file.close()
	return "%s:%d:%d" % [absolute, modified, length]


static func _sorted_value(value: Variant) -> Variant:
	# Normalize integer and float variants before the 12-significant-digit digest serialization.
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return ("%.12g" % float(value)).to_float()
	if typeof(value) == TYPE_DICTIONARY:
		var sorted_keys: Array = value.keys()
		sorted_keys.sort()
		var result: Dictionary = {}
		for key: Variant in sorted_keys:
			result[key] = _sorted_value(value[key])
		return result
	if typeof(value) == TYPE_ARRAY:
		var result: Array = []
		for item: Variant in value:
			result.append(_sorted_value(item))
		return result
	return value


static func _failure(errors: PackedStringArray) -> Dictionary:
	return {"ok": false, "scenario": {}, "errors": errors}
